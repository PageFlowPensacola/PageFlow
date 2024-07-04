Crypto.SHA256.HMAC jwt_hmac = Crypto.SHA256.HMAC(G->G->instance_config->jwt_signing_key);

__async__ void http_handler(Protocols.HTTP.Server.Request req)
{

	write("incoming http request: %O\n", req->not_query);

	req->misc->session = G->G->http_sessions[req->cookies->session] || ([]);

	catch {req->misc->json = Standards.JSON.decode_utf8(req->body_raw);};

	//TODO maybe: Refresh the login token. Currently the tokens don't seem to expire,
	//but if they do, we can get the refresh token via authcookie (if present).
	[function handler, array args] = find_http_handler(req->not_query);

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
	if (sizeof(sess)) {
		//TODO: Persist these things somewhere
		if (!sess->cookie) G->G->http_sessions[sess->cookie = random(1<<64)->digits(36)] = sess;
		resp->extra_heads["Set-Cookie"] = "session=" + sess->cookie + "; Path=/; Max-Age=604800; SameSite=Lax; HttpOnly";
	}
	req->response_and_finish(resp);
}

void ws_msg(Protocols.WebSocket.Frame frm, mapping conn)
{
	if (function f = bounce(this_function)) {f(frm, conn); return;}

	mixed data;
	if (catch {data = Standards.JSON.decode(frm->text);}) return; //Ignore frames that aren't text or aren't valid JSON
	if (!stringp(data->cmd)) return;
	if (data->cmd == "init")
	{
		//Initialization is done with a type and a group.
		//The type has to match a module ("inherit websocket_handler")
		//The group has to be a string or integer.
		if (conn->type) return; //Can't init twice
		object handler = G->G->websocket_types[data->type];
		if (!handler) return; //Ignore any unknown types.
		if (data->auth) {
			conn->auth = Web.decode_jwt(jwt_hmac, data->auth); // will be null if invalid
		} else {
			conn->auth = (["email": conn->session->email, "id": conn->session->user_id]);
		}
		if (string err = handler->websocket_validate(conn, data)) {
			conn->sock->send_text(Standards.JSON.encode((["error": err])));
			conn->sock->close();
			return;
		}
		string group = (stringp(data->group) || intp(data->group)) ? data->group : "";
		conn->type = data->type; conn->group = group;
		handler->websocket_groups[group] += ({conn->sock});
	}
	if (object handler = G->G->websocket_types[conn->type]) handler->websocket_msg(conn, data);
	else write("Message: %O\n", data);
}

void ws_close(int reason, mapping conn)
{
	if (function f = bounce(this_function)) {f(reason, conn); return;}
	werror("WebSocket close: %O\n", conn);
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
	mapping conn = (["sock": sock, //Minstrel Hall style floop (reference loop to the socket)
		"remote_ip": remote_ip, "session": G->G->http_sessions[req->cookies->session] || ([])
	]);
	sock->set_id(conn);
	sock->onmessage = ws_msg;
	sock->onclose = ws_close;
}

protected void create(string name)
{
	register_bouncer(ws_handler); register_bouncer(ws_msg); register_bouncer(ws_close);
	if (!G->G->http_sessions) G->G->http_sessions = ([]);
	if (G->G->httpserver) G->G->httpserver->callback = http_handler;
		else {
			G->G->httpserver = Protocols.WebSocket.Port(http_handler, ws_handler, 8002, "");
			write("WebSocket server started on port 8002\n");
		}
}
