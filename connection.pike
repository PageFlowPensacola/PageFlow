inherit hook;
inherit irc_callback;
inherit annotated;

void session_cleanup() {
	//Go through all HTTP sessions and dispose of old ones
	G->G->http_session_cleanup = call_out(session_cleanup, 86400);
	G->G->DB->generic_query("delete from stillebot.http_sessions where active < now () - '7 days'::interval");
}

__async__ void http_request(Protocols.HTTP.Server.Request req)
{
	req->misc->session = await(G->G->DB->load_session(req->cookies->session));
	//TODO maybe: Refresh the login token. Currently the tokens don't seem to expire,
	//but if they do, we can get the refresh token via authcookie (if present).
	[function handler, array args] = find_http_handler(req->not_query);
	//If we receive URL-encoded form data, assume it's UTF-8.
	if (req->request_headers["content-type"] == "application/x-www-form-urlencoded" && mappingp(req->variables))
	{
		//NOTE: We currently don't UTF-8-decode the keys; they should usually all be ASCII anyway.
		foreach (req->variables; string key; mixed value) catch {
			if (stringp(value)) req->variables[key] = utf8_to_string(value);
		};
	}
	mapping|string resp;
	if (mixed ex = handler && catch {
		mixed h = handler(req, @args); //Either a promise or a result (mapping/string).
		resp = objectp(h) && h->on_await ? await(h) : h; //Await if promise, otherwise we already have it.
	}) {
		werror("HTTP handler crash: %O\n", req->not_query);
		werror(describe_backtrace(ex));
		resp = (["error": 500, "data": "Internal server error\n", "type": "text/plain; charset=\"UTF-8\""]);
	}
	if (!resp)
	{
		//werror("HTTP request: %s %O %O\n", req->request_type, req->not_query, req->variables);
		//werror("Headers: %O\n", req->request_headers);
		resp = ([
			"data": "No such page.\n",
			"type": "text/plain; charset=\"UTF-8\"",
			"error": 404,
		]);
	}
	if (stringp(resp)) resp = (["data": resp, "type": "text/plain; charset=\"UTF-8\""]);
	//All requests should get to this point with a response.

	//As of 20190122, the Pike HTTP server doesn't seem to handle keep-alive.
	//The simplest fix is to just add "Connection: close" to all responses.
	if (!resp->extra_heads) resp->extra_heads = ([]);
	resp->extra_heads->Connection = "close";
	resp->extra_heads["Access-Control-Allow-Origin"] = "*";
	resp->extra_heads["Access-Control-Allow-Private-Network"] = "true";
	mapping sess = req->misc->session;
	if (sizeof(sess) && !sess->fake) {
		if (!sess->cookie) sess->cookie = await(G->G->DB->generate_session_cookie());
		G->G->DB->save_session(sess);
		resp->extra_heads["Set-Cookie"] = "session=" + sess->cookie + "; Path=/; Max-Age=604800; SameSite=Lax; HttpOnly";
	}
	req->response_and_finish(resp);
}

void http_handler(Protocols.HTTP.Server.Request req) {spawn_task(http_request(req));}

void ws_msg(Protocols.WebSocket.Frame frm, mapping conn)
{
	if (function f = bounce(this_function)) {f(frm, conn); return;}
	//Depending on timings, we might not have loaded the session yet. Hold all messages till we have.
	if (arrayp(conn->session)) {conn->session += ({frm}); return;}
	//Check for an expired session. It's highly unlikely that a websocket will be idle for a week
	//without anything pinging the session, but much more likely that the user logs out in another
	//tab, which should kick the websocket's session and login.
	//Note that this is the only place we reload the session. Changes to an existing session are not
	//currently picked up. That means, if you log in again (eg to add scopes), the token will most
	//likely be broken. This may require redefining "http_sessions_deleted" to "session_login_changed"
	//or something, and using it for both. Reconsider this if tokens get removed from session though.
	if (conn->session->user && !conn->session->fake && G->G->http_sessions_deleted[conn->session->cookie]) {
		//This is only relevant if the user's logged in; otherwise, I don't think anyone will
		//much care if a still-connected socket remains. We then keep a list of removed sessions.
		string cookie = conn->session->cookie;
		conn->session = ({frm});
		G->G->DB->load_session(cookie)->then() { //TODO: Deduplicate, again
			if (sizeof(__ARGS__[0]) < 2) {
				//No active session. Kick the socket.
				conn->sock->send_text(Standards.JSON.encode(([
					"cmd": "*DC*",
					"error": "Logged out.",
				])));
				return;
			}
			//Otherwise, we have a session, so go ahead and use it (freshly loaded).
			//And we can drop it from the deleted list, so we don't keep checking.
			array pending = conn->session;
			conn->session = __ARGS__[0];
			m_delete(G->G->http_sessions_deleted, conn->session->cookie);
			ws_msg(pending[*], conn);
		};
	}
	mixed data;
	if (catch {data = Standards.JSON.decode(frm->text);}) return; //Ignore frames that aren't text or aren't valid JSON
	if (!stringp(data->cmd)) return;
	if (data->cmd == "init")
	{
		if (string other = !is_active && get_active_bot()) {
			//If we are definitely not active and there's someone who is,
			//send the request over there instead. Browsers don't all follow
			//302 redirects for websockets, and even if they did, session and
			//login information would be lost (since the websocket would be
			//going to an unrelated origin). So instead, we notify the client
			//of the situation. This DOES mean that we have to give the JS the
			//session cookie, but that's only a minor security issue - you'd
			//have to know how to retrieve that, and then use it to gain access
			//to the real server. In theory, the transfer cookie could be some
			//completely separate identifier, which we first stash into the DB
			//somewhere before notifying the client; this would be valid for
			//some extremely short duration, after which the client would be
			//told "redirect back to default".
			conn->sock->send_text(Standards.JSON.encode(([
				"cmd": "*DC*",
				"error": "This bot is not active, see other",
				"redirect": other,
				"xfr": conn->session->cookie,
			])));
			conn->sock->close(); destruct(conn->sock);
			return;
		}
		//Initialization is done with a type and a group.
		//The type has to match a module ("inherit websocket_handler")
		//The group has to be a string or integer.
		if (conn->type) return; //Can't init twice
		object handler = G->G->websocket_types[data->type];
		if (!handler) return; //Ignore any unknown types.
		//If this socket was redirected from a different node, it will include a
		//session transfer cookie. (See above; currently, a "transfer cookie" is
		//just the session cookie itself, but that may change.)
		if (stringp(data->xfr) && data->xfr != conn->session->cookie) {
			conn->session = ({frm});
			G->G->DB->load_session(data->xfr)->then() { //TODO: Deduplicate with below?
				array pending = conn->session;
				conn->session = __ARGS__[0];
				ws_msg(pending[*], conn);
			};
			return;
		}
		[object channel, string grp] = handler->split_channel(data->group);
		//Previously, this transformation would transform to logins.
		//if (channel) data->group = grp + channel->name;
		if (channel) data->group = grp + "#" + channel->userid;
		//NOTE: Don't save the channel object itself here, in case code gets
		//updated. We want to fetch up the latest channel object whenever it's
		//needed. But it'll be useful to synchronize the group, regardless of
		//whether it was requested by name or ID.
		if (string err = handler->websocket_validate(conn, data)) {
			conn->sock->send_text(Standards.JSON.encode((["error": err])));
			conn->sock->close(); destruct(conn->sock);
			return;
		}
		string group = (stringp(data->group) || intp(data->group)) ? data->group : "";
		conn->type = data->type; conn->group = group;
		handler->websocket_groups[group] += ({conn->sock});
		string uid = conn->session->user->?id;
		if (object h = uid && uid != "0" && uid != "3141592653589793" && G->G->websocket_types->prefs) {
			//You're logged in. Provide automated preference synchronization.
			h->websocket_groups[conn->prefs_uid = uid] += ({conn->sock});
			call_out(h->websocket_cmd_prefs_send, 0, conn, ([]));
		}
	}
	string type = has_prefix(data->cmd||"", "prefs_") ? "prefs" : conn->type;
	if (object handler = G->G->websocket_types[type]) handler->websocket_msg(conn, data);
	else write("Message: %O\n", data);
}

void ws_close(int reason, mapping conn)
{
	if (function f = bounce(this_function)) {f(reason, conn); return;}
	if (object handler = G->G->websocket_types[conn->type])
	{
		handler->websocket_msg(conn, 0);
		handler->websocket_groups[conn->group] -= ({conn->sock});
	}
	if (object handler = conn->prefs_uid && G->G->websocket_types->prefs) //Disconnect from preferences
	{
		handler->websocket_msg(conn, 0);
		handler->websocket_groups[conn->prefs_uid] -= ({conn->sock});
	}
	m_delete(conn, "sock"); //De-floop
}

void ws_handler(array(string) proto, Protocols.WebSocket.Request req)
{
	if (function f = bounce(this_function)) {f(proto, req); return;}
	if (req->not_query != "/ws")
	{
		req->response_and_finish((["error": 404, "type": "text/plain", "data": "Not found"]));
		return;
	}
	//Lifted from Protocols.HTTP.Server.Request since, for some reason,
	//this isn't done for WebSocket requests.
	if (req->request_headers->cookie)
		foreach (MIME.decode_headerfield_params(req->request_headers->cookie); ; ADT.OrderedMapping m)
			foreach (m; string key; string value)
				if (value) req->cookies[key] = value;
	//End lifted from Pike's sources
	string remote_ip = req->get_ip(); //Not available after accepting the socket for some reason
	Protocols.WebSocket.Connection sock = req->websocket_accept(0);
	mapping conn = (["sock": sock, //Minstrel Hall style floop
		"session": ({ }), //Queue of requests awaiting the session
		"remote_ip": remote_ip,
		"hostname": deduce_host(req->request_headers),
	]);
	sock->set_id(conn);
	G->G->DB->load_session(req->cookies->session)->then() {
		array pending = conn->session;
		conn->session = __ARGS__[0];
		if (sizeof(pending)) ws_msg(pending[*], conn);
	};
	sock->onmessage = ws_msg;
	sock->onclose = ws_close;
}

protected void create(string name)
{
	::create(name);
	if (mixed id = m_delete(G->G, "http_session_cleanup")) remove_call_out(id);
	session_cleanup();
	register_bouncer(ws_handler); register_bouncer(ws_msg); register_bouncer(ws_close);

		if (G->G->httpserver) G->G->httpserver->callback = http_handler;
			else G->G->httpserver = Protocols.WebSocket.Port(http_handler, ws_handler, listen_port, listen_addr);
}
