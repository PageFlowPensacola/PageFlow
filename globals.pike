protected void create(string n)
{
	foreach (indices(this),string f)
		if (f!="create" && f[0]!='_')
			add_constant(f,this[f]);
	foreach (Program.annotations(this_program); string anno;)
		if (stringp(anno) && sscanf(anno, "G->G->%s", string gl) && gl) // add p to string to make it a predicate: stringp.
			if (!G->G[gl]) G->G[gl] = ([]);
  catch {G->G->instance_config = Standards.JSON.decode_utf8(Stdio.read_file("instance-config.json"));};
}

array(int) bbox_color = ({180, 180, 0});
array(int) audit_rect_color = ({0, 192, 0});

__async__ mixed asyncify(mixed gen) {
	return objectp(gen) && gen->on_await ? await(gen) : gen;
}

@"G->G->http_endpoints";
class http_endpoint
{
	//Set to an sscanf pattern to handle multiple request URIs. Otherwise will handle just "/myname".
	constant http_path_pattern = 0;

	//A channel will be provided if and only if this is chan_foo.pike and the URL is /channels/spam/foo
	//May be a continue function or may return a Future. May also return a string (recommended for
	//debugging only, as it'll be an ugly text/plain document).
	mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) { }

	protected void create(string name)
	{
		if (http_path_pattern)
		{
			G->G->http_endpoints[http_path_pattern] = http_request;
			return;
		}
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		G->G->http_endpoints[name] = http_request;
	}
}

@"G->G->restful_endpoints";
class restful_endpoint
{

	mapping(string:mixed)|string|Concurrent.Future handle_list(Protocols.HTTP.Server.Request req, string ...path_values) { };
	mapping(string:mixed)|string|Concurrent.Future handle_detail(Protocols.HTTP.Server.Request req, string ...path_values /* even number ones plus one */) { };
	mapping(string:mixed)|string|Concurrent.Future handle_create(Protocols.HTTP.Server.Request req, string ...path_values) { };
	mapping(string:mixed)|string|Concurrent.Future handle_update(Protocols.HTTP.Server.Request req, string ...path_values /* even number ones plus one */) { };
	mapping(string:mixed)|string|Concurrent.Future handle_delete(Protocols.HTTP.Server.Request req, string ...path_values /* even number ones plus one */) { };

	protected void create(string name)
	{

		G->G->restful_endpoints[name] = this;

	}

}



array(function|array) find_http_handler(string not_query) {
	//Simple lookups are like http_endpoints["listrewards"], without the slash.
	//Exclude eg http_endpoints["chan_vlc"] which are handled elsewhere.
	if (function handler = !has_prefix(not_query, "/chan_") && G->G->http_endpoints[not_query[1..]])
		return ({handler, ({ })});
	//Try all the sscanf-based handlers, eg http_endpoints["/channels/%[^/]/%[^/]"], with the slash
	//TODO: Look these up more efficiently (and deterministically)
	foreach (G->G->http_endpoints; string pat; function handler) if (has_prefix(pat, "/"))
	{
		//Match against an sscanf pattern, and require that the entire
		//string be consumed. If there's any left (the last piece is
		//non-empty), it's not a match - look for a deeper pattern.
		array pieces = array_sscanf(not_query, pat + "%s");
		if (pieces && sizeof(pieces) && pieces[-1] == "") return ({handler, pieces[..<1]});
	}
	return ({0, ({ })});
}

/* Easily slide a delayed callback to the latest code

In create(), call register_bouncer(some_function)
In some_function, start with:
if (function f = bounce(this_function)) return f(...my args...);

If the code has been updated since the callback was triggered, it'll give back
the new function. Functions are identified by their %O descriptions.
*/
@"G->G->bouncers";
void register_bouncer(function f) {G->G->bouncers[sprintf("%O", f)] = f;}
function|void bounce(function f)
{
	function current = G->G->bouncers[sprintf("%O", f)];
	if (current != f) return current;
	return UNDEFINED;
}

@"G->G->exports";
class annotated {
	protected void create(string name) {
		//TODO: Find a good way to move prev handling into the export class or object below
		mapping prev = G->G->exports[name];
		G->G->exports[name] = ([]);
		foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
			if (ann) foreach (indices(ann), mixed anno) {
				if (functionp(anno)) anno(this, name, key);
			}
		}
		//Purge any that are no longer being exported (handles renames etc)
		if (prev) foreach (prev - G->G->exports[name]; string key;)
			add_constant(key);
	}
}

void export(object module, string modname, string key) {
	add_constant(key, module[key]);
	G->G->exports[modname][key] = 1;
}

void retain(object module, string modname, string key) {
	if (!G->G[key]) G->G[key] = module[key];
	else module[key] = G->G[key];
}

mapping(string:mixed) jsonify(mixed data, int|void jsonflags) {
	return (["data": string_to_utf8(Standards.JSON.encode(data, jsonflags)), "type": "application/json"]);
}

// The following builds on Process module
// https://pike.lysator.liu.se/generated/manual/modref/ex/predef_3A_3A/Process/create_process.html#create_process
Concurrent.Future run_promise(string|array(string) cmd, mapping modifiers = ([]))
{
  string gotstdout="", gotstderr="", stdin_str;
  int exitcode;

  if((modifiers->stdout && !callablep(modifiers->stdout))
    || (modifiers->stderr && !callablep(modifiers->stderr)))
    throw( ({ "Can not redirect stdout or stderr in Process.run, "
              "please use Process.Process instead.", backtrace() }) );

  object(Stdio.File)|zero mystdout = Stdio.File();
  object(Stdio.File)|zero mystderr = Stdio.File();
  object(Stdio.File)|zero mystdin;

  object|zero p;
  if(stringp(modifiers->stdin))
  {
    mystdin = Stdio.File();
    stdin_str = modifiers->stdin;
    p = Process.Process(cmd, modifiers + ([
                  "stdout":mystdout->pipe(),
                  "stderr":mystderr->pipe(),
                  "stdin":mystdin->pipe(Stdio.PROP_IPC|Stdio.PROP_REVERSE)
                ]));
  }
  else
    p = Process.Process(cmd, modifiers + ([
                  "stdout":mystdout->pipe(),
                  "stderr":mystderr->pipe(),
                ]));

  object promise = Concurrent.Promise();
  void done() {
    if (mystdin || mystdout || mystderr) return;
    exitcode = p->wait();
    promise->success(([ "stdout"  : gotstdout,
              "stderr"  : gotstderr,
              "exitcode": exitcode   ]));
  }
  mystdout->set_read_callback( lambda( mixed i, string data) {
                                 if (modifiers->stdout) modifiers->stdout(data);
                                 else gotstdout += data;
                               } );
  mystderr->set_read_callback( lambda( mixed i, string data) {
                                 if (modifiers->stderr) modifiers->stderr(data);
                                 else gotstderr += data;
                               } );
  mystdout->set_close_callback( lambda () {
				  mystdout->set_read_callback(0);
				  catch { mystdout->close(); };
				  mystdout = 0; done();
				});
  mystderr->set_close_callback( lambda () {
				  mystderr->set_read_callback(0);
				  catch { mystderr->close(); };
				  mystderr = 0; done();
				});

  if (mystdin) {
    if (stdin_str != "") {
      Shuffler.Shuffler sfr = Shuffler.Shuffler();
      Shuffler.Shuffle sf = sfr->shuffle( mystdin );
      sf->add_source(stdin_str);
      sf->set_done_callback (lambda (mixed ...) {
                               catch { mystdin->close(); };
                               mystdin = 0; done();
                             });
      sf->start();
    } else {
      catch { mystdin->close(); };
      mystdin = 0;
    }
  }
  return promise->future();
}

__async__ mapping analyze_page(string page_data, int imgwidth, int imgheight) {
	//Bounds are in the form of left, top, right, bottom
	// where left is the number of px from the left edge of the image
	// and top is the number of px from the top edge of the image
	// and right is the number of px from the _left_ edge of the image
	// and bottom is the number of px from the _top_ edge of the image.
	// Returned in px coordinates
	mapping bounds = ([]);
	bounds->left = imgwidth;
	bounds->top = imgheight;
	// Maybe output tesseract as hocr instead of makebox, which
	// gives a list of "words", per line, with bounding boxes
	// as opposed to individual characters.
	mapping hocr = await(run_promise(({"tesseract", "-", "-", "hocr"}), (["stdin": page_data])));
	array data = Parser.XML.Simple()->parse(hocr->stdout){
		// implicit lambda
		[string type, string name, mapping attr, mixed data, mixed loc] = __ARGS__;
		switch (type) {
			case "<?xml": return 0;
			case "<": return 0;
			case "":
				data = String.trim(data);
				return data != "" && data;
			case ">":
			// Ensure we always get back an array of arrays, but flatten to single array.
			if (name == "body") return Array.arrayify(data[*]) * ({ });
			if (name == "html") return data * ({ });
				switch (attr->class) {
					case "ocr_page": return data;
					case "ocr_carea": {
						sscanf(attr->title, "%*sbbox %d %d %d %d", int l, int t, int r, int b);
						bounds->left = min(bounds->left, l); bounds->top = min(bounds->top, t);
						bounds->right = max(bounds->right, r); bounds->bottom = max(bounds->bottom, b);
						return data * "\n\n";
					}
					case "ocr_par": return data * "\n";
					case "ocr_line": return data * " ";
					case "ocrx_word": return data * " ";
					default: return 0;
				}
		}
	} * ({ }); // then flatten at the end
	return (["bounds": bounds, "data": data]);
}

mapping calculate_transition_score(mapping r, mapping bounds, object grey) {
	int last = -1, transition_count = 0;
	// Represent the box in px coords for the box we are now using,
	// which may be based on a template or on a document.
	int x1 = (int) (r->x1 * (bounds->right - bounds->left) + bounds->left);
	int x2 = (int) (r->x2 * (bounds->right - bounds->left) + bounds->left);
	int y1 = (int) (r->y1 * (bounds->bottom - bounds->top) + bounds->top);
	int y2 = (int) (r->y2 * (bounds->bottom - bounds->top) + bounds->top);
	// Now clamp to the image bounds
	x1 = limit(0, x1, grey->xsize() - 1);
	x2 = limit(0, x2, grey->xsize() - 1);
	y1 = limit(0, y1, grey->ysize() - 1);
	y2 = limit(0, y2, grey->ysize() - 1);
	constant STRIP_COUNT = 16;
	// regions and middle
	int ymid = y1 + (y2 - y1) / STRIP_COUNT / 2;
	for (int strip = 0; strip < STRIP_COUNT; strip++) {
		int y = ymid + (y2 - y1) * strip / STRIP_COUNT;
		for (int x = x1; x < x2; x++) {
			int cur = grey->getpixel(x, y)[0] > 128;
			transition_count += (cur != last);
			last = cur;
		}
	}
	last = -1;
	int xmid = x1 + (x2 - x1) / STRIP_COUNT / 2;
	for (int strip = 0; strip < STRIP_COUNT; strip++) {
		int x = xmid + (x2 - x1) * strip / STRIP_COUNT;
		for (int y = y1; y < y2; y++) {
			int cur = grey->getpixel(x, y)[0] > 128;
			transition_count += (cur != last);
			last = cur;
		}
	}
	return (["score":transition_count, "x1":x1, "x2":x2, "y1":y1, "y2":y2]);
}


@"G->G->websocket_types"; @"G->G->websocket_groups";
class websocket_handler {

	string ws_type; //Will be set in create(), but can be overridden (also in create) if necessary
	constant markdown = ""; //Override this with a hash-quoted inline Markdown file

	mapping(string|int:array(object)) websocket_groups;

	//Generate a state mapping for a particular connection group. If state is 0, no
	//information is sent; otherwise it must be a JSON-compatible mapping. An ID will
	//be given if update_one was called, otherwise it will be 0. Type is rarely needed
	//but is used only in conjunction with an ID.
	mapping|Concurrent.Future get_state(string|int group, string|void id, string|void type) { }
	//__async__ mapping get_state(string|int group, string|void id, string|void type) { } //Alternate (equivalent) signature

	//Override to validate any init requests. Return 0 to allow the socket
	//establishment, or an error message.
	string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
		// On init, we don't have a group yet, so check for it in msg.
		// Subsequently, we will have a group in the conn.
		sscanf((string)msg->group, "%d:%s", int org, string subgroup);
		if (!org) return "Bad group";
		//TODO if user is not authorized for this org fail.
		msg->group = sprintf("%d:%s", org, subgroup || "");
	 }

	//If msg->cmd is "init", it's a new client and base processing has already been done.
	//If msg is 0, a client has disconnected and is about to be removed from its group.
	//Use websocket_groups[conn->group] to find an array of related sockets.
	void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
		if (!msg) return;
		if (msg->cmd == "refresh" || msg->cmd == "init") send_update(conn);
		if (function f = this["websocket_cmd_" + msg->cmd]) f(conn, msg);
	}

	void websocket_cmd_chgrp(mapping(string:mixed) conn, mapping(string:mixed) msg) {

		if (string err = websocket_validate(conn, msg)) {
			conn->sock->send_text(Standards.JSON.encode((["error": err])));
			conn->sock->close();
			return;
		}

		websocket_groups[conn->group] -= ({conn->sock});
		websocket_groups[conn->group = msg->group] += ({conn->sock});
		send_update(conn);
	}

	void _low_send_updates(mapping resp, array(object) socks) {
		if (!resp) return;
		string text = Standards.JSON.encode(resp | (["cmd": "update"]), 4);
		foreach (socks, object sock)
			if (sock && sock->state == 1) sock->send_text(text);
	}
	void _send_updates(array(object) socks, string|int group, mapping|void data) {
		if (!data) data = get_state(group);
		if (objectp(data) && data->then) data->then() {_low_send_updates(__ARGS__[0], socks);};
		else _low_send_updates(data, socks);
	}

	//Send an update to a specific connection. If not provided, data will
	//be generated by get_state(). TODO: Is this used anywhere? If not,
	//replace it with send_message() and have it not add cmd:update. Would
	//be more useful.
	void send_update(mapping(string:mixed) conn, mapping|void data) {
		_send_updates(({conn->sock}), conn->group, data);
	}

	//Update all connections in a given group.
	//Generates just one state object and sends it everywhere.
	void send_updates_all(string|int group, mapping|void data) {
		array dest = websocket_groups[group];
		if (dest && sizeof(dest)) _send_updates(dest, group, data);
	}
	//Compatibility overlap variant form. Use this with a channel object to send to
	//the correct group for that channel.
	variant void send_updates_all(object chan, string|int group, mapping|void data) {
		send_updates_all(group + "#" + chan->userid, data);
	}

	void update_one(string|int group, string id, string|void type) {
		asyncify(get_state(group, id, type))->then() {
			send_updates_all(group, (["id": id, "data": __ARGS__[0], "type": type || "item"]));
		};
	}
	//Compatibility overlap variant form, as above.
	variant void update_one(object chan, string|int group, string id, string|void type) {
		update_one(group + "#" + chan->userid, id, type);
	}

	mapping(string:mixed) render(Protocols.HTTP.Server.Request req, mapping replacements) {
		werror("render: %O\n", replacements | req->misc->userinfo);
		if (replacements->vars->?ws_group) {
			if (!replacements->vars->ws_type) replacements->vars->ws_type = ws_type;
			if (req->misc->channel) replacements->vars->ws_group += "#" + req->misc->channel->userid;
		}
		if (markdown != "") return render_template(markdown, replacements | req->misc->userinfo);
		return render_template(ws_type + ".md", replacements | req->misc->userinfo);
	}

	protected void create(string name) {
		if (!(websocket_groups = G->G->websocket_groups[name]))
			websocket_groups = G->G->websocket_groups[name] = ([]);

		if (!ws_type) ws_type = name;
		G->G->websocket_types[name] = this;
	}
}


class http_websocket
{
	inherit http_endpoint;
	inherit websocket_handler;

	mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
		return render(req, (["vars": (["ws_group": ""])]));
	};

	constant markdown = "# Page Title\n\n";

	string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
		if (string err = ::websocket_validate(conn, msg)) return err;
		if (!conn->auth) return "Not logged in";
		// TODO check for user org access
	}

	// Due to a quirk in Pike, multiple inheritance
	// requires that the create() function be defined.
	protected void create(string name) {::create(name);}

}

// Markdown Parser
bool _parse_attrs(string text, mapping tok) //Used in renderer and lexer - ideally would be just lexer, but whatevs
{
	if (sscanf(text, "{:%[^{}\n]}%s", string attrs, string empty) && empty == "")
	{
		attrs = String.trim(attrs);
		while (attrs != "") {
			sscanf(attrs, "%[^= ]%s", string att, attrs);
			if (att == "") {sscanf(attrs, "%*[= ]%s", attrs); continue;} //Malformed, ignore
			if (att[0] == '.') {
				if (tok["attr_class"]) tok["attr_class"] += " " + att[1..];
				else tok["attr_class"] = att[1..];
			}
			else if (att[0] == '#')
				tok["attr_id"] = att[1..];
			//Note that the more intuitive notation asdf="qwer zxcv" is NOT supported, as it
			//conflicts with Markdown's protections. So we use a weird at-quoting notation
			//instead. (Think "AT"-tribute? I dunno.)
			else if (sscanf(attrs, "=@%s@%*[ ]%s", string val, attrs) //Quoted value asdf=@qwer zxcv@
					|| sscanf(attrs, "=%s%*[ ]%s", val, attrs)) //Unquoted value asdf=qwer
				tok["attr_" + att] = val;
			else if (sscanf(attrs, "%*[ ]%s", attrs)) //No value at all (should always match, but will trim for consistency)
				tok["attr_" + att] = "1";
		}
		return 1;
	}
}

class Renderer
{
	inherit Parser.Markdown.Renderer;
	//Put borders on all tables
	string table(string header, string body, mapping token)
	{
		return ::table(header, body, (["attr_border": "1"]) | token);
	}
	//Allow cell spanning by putting just a hyphen in a cell (it will
	//be joined to the NEXT cell, not the preceding one)
	int spancount = 0;
	string tablerow(string row, mapping token)
	{
		spancount = 0; //Can't span across rows
		if (row == "") return ""; //Suppress the entire row if all cells were suppressed
		return ::tablerow(row, token);
	}
	string tablecell(string cell, mapping flags, mapping token)
	{
		if (String.trim(cell) == "-") {++spancount; return "";} //A cell with just a hyphen will not be rendered, and the next cell spans.
		if (spancount) token |= (["attr_colspan": (string)(spancount + 1)]);
		spancount = 0;
		return ::tablecell(cell, flags, token);
	}
	//Allow a blockquote to become a dialog
	string blockquote(string text, mapping token)
	{
		// in md, tag=someval becomes attr_tag=someval
		// # and . become id and class, respectively.
		// Everything _inside_ of the blockquote will have
		// already been parsed.
		if (string tag = m_delete(token, "attr_tag")) {
			//If the blockquote starts with an H3, it is some form of title.
			if (sscanf(text, "<h3%*[^>]>%s</h3>%s", string title, string main)) switch (tag) {
				//For dialogs, the title is outside the scroll context, and also gets a close button added.
				case "dialogform": case "formdialog": //(allow this to be spelled both ways)
				case "dialog": options->dialogs[sizeof(options->dialogs)] = sprintf("<dialog%s><section>"
						"<header><h3>%s</h3><div><button type=button class=dialog_cancel>x</button></div></header>"
						"<div>%s%s%s</div>"
						"</section></dialog>",
					attrs(token), title || "",
					tag == "dialog" ? "" : "<form method=dialog>",
					main,
					tag == "dialog" ? "" : "</form>",
				);
				return ""; // dialog will be rendered in its own section
				case "details": return sprintf("<details%s><summary>%s</summary>%s</details>",
					attrs(token), title || "Details", main);
				default: break; //No special title handling
			}
			return sprintf("<%s%s>%s</%[0]s>", tag, attrs(token), text);
		}
		return ::blockquote(text, token);
	}
	string heading(string text, int level, string raw, mapping token)
	{
		if (options->headings && !options->headings[level])
			//Retain the first-seen heading of each level
			options->headings[level] = text;
		return ::heading(text, level, raw, token);
	}
	//Allow a link to be a button (or anything else)
	string link(string href, string title, string text, mapping token)
	{
		if (_parse_attrs("{" + href + "}", token)) {
			//Usage: [Text](: attr=value)
			string tag = m_delete(token, "attr_tag") || "button";
			if (tag == "button" && !token->attr_type) token->attr_type = "button";
			return sprintf("<%s%s>%s</%[0]s>", tag, attrs(token, ([])), text);
		}
		if (sscanf(href, "%s :%s", string dest, string att) && _parse_attrs("{:" + att + "}", token)) {
			//Usage: [Text](https://link.example/destination/ :attr=value)
			string tag = m_delete(token, "attr_tag") || "a";
			return sprintf("<%s%s>%s</%[0]s>", tag, attrs(token, (["href": dest])), text);
		}
		return ::link(href, title, text, token);
	}
}
class Lexer
{
	inherit Parser.Markdown.Lexer;
	this_program lex(string src)
	{
		::lex(src);
		foreach (tokens; int i; mapping tok)
		{
			if (tok->type == "paragraph" && tok->text[-1] == '}')
			{
				mapping target = tok;
				array(string) lines = tok->text / "\n";
				if (i + 1 < sizeof(tokens) && tokens[i + 1]->type == "blockquote_end") target = tokens[i + 1];
				else if (sizeof(lines) == 1 && i > 0)
				{
					//It's a paragraph consisting ONLY of attributes.
					//Attach the attributes to the preceding token.
					//TODO: Only do this if the preceding token is a
					//type that can take attributes.
					target = tokens[i - 1];
				}
				if (_parse_attrs(lines[-1], target))
				{
					if (sizeof(lines) > 1) tok->text = lines[..<1] * "\n";
					else tok->type = "space"; //Suppress the text altogether.
				}
			}
			if (tok->type == "list_end")
			{
				//Scan backwards into the list, finding the last text.
				//If that text can be parsed as attributes, apply them to the
				//list_end, which will then apply them to the list itself.
				for (int j = i - 1; j >= 0; --j)
				{
					if (tokens[j]->type == "text")
					{
						if (_parse_attrs(tokens[j]->text, tok))
							tokens[j]->type = "space";
						break;
					}
					if (!(<"space", "list_item_end">)[tokens[j]->type]) break;
				}
			}
		}
		return this;
	}
}

@"G->G->template_defaults";
mapping(string:mixed) render_template(string template, mapping replacements)
{
	string content;
	if (has_value(template, '\n')) {content = template; template = "<inline>.md";}
	else content = utf8_to_string(Stdio.read_file("templates/" + template));
	if (!content) error("Unable to load templates/" + template + "\n");
	array pieces = content / "$$";
	if (!(sizeof(pieces) & 1)) error("Mismatched $$ in templates/" + template + "\n");
	function static_fn = G->G->template_defaults["static"];
	if (replacements->vars) {
		//Set vars to a mapping of variable name to value and they'll be made available to JS.
		//To trigger automatic synchronization, set ws_type to a keyword, and ws_group to a string or int.
		//Provide a static file that exports render(state). By default, that's the same name
		//as the ws_type (so if ws_type is "raidfinder", it'll load "raidfinder.js"), but
		//this can be overridden by explicitly setting ws_code.
		string jsonvar(array nv) {return sprintf("let %s = %s;", nv[0], Standards.JSON.encode(nv[1], 5));}
		array vars = jsonvar(sort((array)(replacements->vars - (["ws_code":""])))[*]);
		if (replacements->vars->ws_type) {
			string code = replacements->vars->ws_code || replacements->vars->ws_type;
			if (!has_suffix(code, ".js")) code += ".js";
			vars += ({
				jsonvar(({"ws_code", static_fn(code)})),
				"let ws_sync = null; import('" + static_fn("ws_sync.js") + "').then(m => ws_sync = m);",
			});
		}
		replacements->js_variables = "<script>" + vars * "\n" + "</script>";
	}
	replacements->head_scripts = "";
	//Set js to a string or an array of strings, and those files will be loaded.
	if (replacements->js) foreach (Array.arrayify(replacements->js), string fn) {
		if (!has_value(fn, ".")) fn += ".js";
		replacements->head_scripts += "<script type=module src=\"" + static_fn(fn) + "\"></script>\n";
	}
	//Similarly for CSS files.
	if (replacements->css) foreach (Array.arrayify(replacements->css), string fn) {
		if (!has_value(fn, ".")) fn += ".css";
		replacements->head_scripts += "<link rel=\"stylesheet\" href=\"" + static_fn(fn) + "\">\n";
	}

	for (int i = 1; i < sizeof(pieces); i += 2)
	{
		string token = pieces[i];
		if (token == "") {pieces[i] = "$$"; continue;} //Escape a $$ by doubling it ($$$$)
		if (sizeof(token) > 200) //TODO: Check more reliably for it being a 'token'
			error("Invalid token name %O in templates/%s - possible mismatched marker\n",
				"$$" + token[..80] + "$$", template);
		sscanf(token, "%s||%s", token, string dflt);
		int trim_before = has_prefix(token, ">");
		int trim_after  = has_suffix(token, "<");
		token = token[trim_before..<trim_after];
		string|function repl = replacements[token] || G->G->template_defaults[token];
		if (!repl)
		{
			if (dflt) pieces[i] = dflt;
			else error("Token %O not found in templates/%s\n", "$$" + token + "$$", template);
		}
		else if (callablep(repl)) pieces[i] = repl(dflt);
		else pieces[i] = repl;
		if (pieces[i] == "")
		{
			if (trim_before) pieces[i-1] = String.trim("^" + pieces[i-1])[1..];
			if (trim_after)  pieces[i+1] = String.trim(pieces[i+1] + "$")[..<1];
		}
	}
	content = pieces * "";
	if (has_suffix(template, ".md"))
	{
		mapping headings = ([]);
		mapping dialogs = ([]);
		string content = Tools.Markdown.parse(content, ([
			"renderer": Renderer, "lexer": Lexer,
			"headings": headings,
			"attributes": 1, //Ignored if using older Pike (or, as of 2020-04-13, vanilla Pike - it's only on branch rosuav/markdown-attribute-syntax)
			"dialogs": dialogs, //Allow dialogs to be created with {:dialog}...{:/dialog}
		]));
		return render_template("markdown.html", ([
			//Dynamic defaults - can be overridden, same as static defaults can
			"title": headings[1] || "PageFlow",
		]) | replacements | ([
			//Forced attributes
			"content": content,
			"dialogs": values(dialogs) * "",
		]));
	}
	return ([
		"data": string_to_utf8(content),
		"type": "text/html; charset=\"UTF-8\"",
	]);
}
