inherit http_endpoint;


mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, string tail) {


	if(!req->misc->auth) return (["error": 403]);
	// Generally path_variables is an array of alternating keys and values
	// For example, if the path is /org/1/department/2/employee/3
	// then path_variables = ({"org", "1", "department", "2", "employee", "3"})
	if (has_suffix(tail, "/")) {
		tail = tail[..<1]; // Remove trailing slash. Slice to remove one last character, like -1 in Python.
	}
	array(string) path_variables = ({"org"}) + tail / "/";
	// Split the path vars into pairs
	// First from each pair is the key, second is the value
	// path_variables/2.0 is an array of key/val pair arrays,
	// the .0 means divide by float, which keeps remainder
	// with [*][0] we get the first element of each pair nested pair
	// With an odd number, the final key/val pair is only a single value
	array keys = (path_variables/2.0)[*][0];
	// Dividing by two ill leave off the remainder (last element if odd #)
	array values = (path_variables/2)[*][1];
	// If the path_variables array has an odd number of elements,
	// then the last element is an array of ids
	// array modulo 2 will give us the remainder of the
	// array divided by 2

	array residual_key = path_variables%2; // used as a value
	// werror("residual_key: %O\n", residual_key);
	string keystring = keys*".";
	//werror("keystring: %O\n", keystring);

	object handler = G->G->restful_endpoints[keystring];
	if(!handler) {
		return 0;
	}
	// If there is no residual key, there's no val for final key
	if (!sizeof(residual_key)) {
		if (req->request_type == "GET") {
			return handler->handle_detail(req, @values);
		} else if (req->request_type == "PUT" || req->request_type == "PATCH") {
			return handler->handle_update(req, @values);
		} else if (req->request_type == "DELETE") {
			return handler->handle_delete(req, @values);
		} else {
			return (["error": 405]); // Method not allowed
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
	// Stick callback into the G->G->http_endpoints mapping for this org
	G->G->http_endpoints["/org/%[^\0]"] = http_request; // [^\0] accepts any character except NUL.
}
