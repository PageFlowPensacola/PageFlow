inherit restful_endpoint;

__async__ mapping(string:mixed)|string handle_list(Protocols.HTTP.Server.Request req, string org, string template) {
	//werror("handle_list: %O %O %O\n", req, org, template);
	array(mapping) templates = await(G->G->DB->get_templates_for_org(org));
	//werror("%O\n", templates);
	return jsonify(templates);
};

mapping(string:mixed)|string|Concurrent.Future handle_detail(Protocols.HTTP.Server.Request req, string org, string template, string audit_rect) {
	//werror("handle_list: %O %O %O\n", req, org, template);
};

__async__ mapping(string:mixed)|string|Concurrent.Future handle_create(Protocols.HTTP.Server.Request req) {
	mapping result = await(G->G->DB->insert_template(req->misc->json->name));
	werror("result: %O\n", result);
	//werror("body: %O\n", req->body_raw);
	//string template_name = req->body_raw->name;
	return jsonify((["id": result]));
};
mapping(string:mixed)|string|Concurrent.Future handle_update(Protocols.HTTP.Server.Request req, string org, string template, string audit_rect) { };
mapping(string:mixed)|string|Concurrent.Future handle_delete(Protocols.HTTP.Server.Request req, string org, string template, string audit_rect) { };
