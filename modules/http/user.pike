inherit http_endpoint;

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {

	mapping|zero result_set = await(G->G->DB->get_user_details(req->misc->auth->email));

	return jsonify(result_set);


 };
