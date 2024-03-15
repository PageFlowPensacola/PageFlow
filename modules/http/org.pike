inherit http_endpoint;


mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, string tail) {


	if(!req->misc->auth) return (["error": 403]);

	array(string) path_variables = ({"org"}) + tail / "/";

	array keys = (path_variables/2.0)[*][0];
	array values = (path_variables/2)[*][1];
	array array_id = path_variables%2;

	string keystring = keys*".";

	object handler = G->G->restful_endpoints(keystring);
	if(!handler) {
		return 0;
	}

	if (sizeof(array_id)) {
		if (req->request_type == "GET") {
			return handler->handle_detail(req, @values);
		} else if (req->request_type == "PUT" || req->request_type == "PATCH") {
			return handler->handle_update(req, @values);
		} else if (req->request_type == "DELETE") {
			return handler->handle_delete(req, @values);
		} else {
			return (["error": 405]);
		}
	} else {
		if (req->request_type == "POST") {
			return handler->handle_create(req, @values);
		} else if (req->request_type == "GET") {
			return handler->handle_list(req, @values);
		} else {
			return (["error": 405]);
		}
	}





};



protected void create(string name) {
	::create(name);

	G->G->http_endpoints["/org/%s"] = http_request();
}
