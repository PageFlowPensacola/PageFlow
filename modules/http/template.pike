inherit restful_endpoint;

	mapping(string:mixed)|string|Concurrent.Future handle_list(Protocols.HTTP.Server.Request req) {


	 };

	mapping(string:mixed)|string|Concurrent.Future handle_detail(Protocols.HTTP.Server.Request req, string id) { };

	mapping(string:mixed)|string|Concurrent.Future handle_create(Protocols.HTTP.Server.Request req) { };

	mapping(string:mixed)|string|Concurrent.Future handle_update(Protocols.HTTP.Server.Request req, string id) { };

	mapping(string:mixed)|string|Concurrent.Future handle_delete(Protocols.HTTP.Server.Request req, string id) { };

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {


	int org_id = 271540;
	//write ("%O\n", await(G->G->DB->get_templates_for_org(org_id)));

	return jsonify(await(G->G->DB->get_templates_for_org(org_id)));



 };
