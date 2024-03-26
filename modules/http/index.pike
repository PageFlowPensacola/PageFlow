inherit websocket_handler;
inherit http_endpoint;

constant http_path_pattern = "";

constant markdown = #"# PageFlow Index Screen

* This is a variable: $$foo$$
* This variable has no value but a default: $$bar||bar-default$$
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render(req,
	([
			"vars": (["ws_group": "", "helloworld": 1234]),
			"foo": "foo-value",
	]));
}

// Due to a quirk in Pike, multiple inheritance
// requires that the create() function be defined.
protected void create(string name) {::create(name);}
