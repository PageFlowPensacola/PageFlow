inherit websocket_handler;
inherit http_endpoint;

constant http_path_pattern = "";

constant markdown = #"# PageFlow Index Screen

";

void websocket_cmd_hello(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("Got a hello! %O\n", conn->auth);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->auth && msg->group != "") return "Not logged in";
}


mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render(req,
	([
			"vars": (["ws_group": ""]),
	]));
}

// Due to a quirk in Pike, multiple inheritance
// requires that the create() function be defined.
protected void create(string name) {::create(name);}
