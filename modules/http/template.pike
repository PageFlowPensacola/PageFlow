inherit http_endpoint;

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {

	int org_id = 271540;
	//write ("%O\n", await(G->G->DB->get_templates_for_org(org_id)));

	return jsonify(await(G->G->DB->get_templates_for_org(org_id)));



 };
