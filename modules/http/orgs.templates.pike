inherit restful_endpoint;

__async__ mapping(string:mixed)|string handle_list(Protocols.HTTP.Server.Request req, string org) {
	//werror("handle_list: %O %O %O\n", req, org, template);
	array(mapping) templates = await(G->G->DB->get_templates_for_org(org));
	//werror("%O\n", templates);
	return jsonify(templates);
};

__async__ mapping(string:mixed)|string|Concurrent.Future handle_detail(Protocols.HTTP.Server.Request req, string org, string template_id) {
	if (! (int) org) return ([ "error": 403 ]);
	if (!template_id) return 0;
	mapping details = await(G->G->DB->run_pg_query(#"
		SELECT t.name as template_name, p.page_number as page_number
		FROM templates t
		JOIN template_pages p ON t.id = p.template_id
		WHERE t.id = :template_id
		AND t.primary_org_id = :org_id
	", (["org_id":org, "template_id":template_id])));

	mapping template = (
		[
			"name": details[0]->template_name,
			"pages": details->page_number, // Pike Automapping
			"signatories": await(G->G->DB->run_pg_query(#"
		SELECT s.name as signatory_field
		FROM template_signatories s
		JOIN templates t ON s.template_id = t.id
		WHERE t.id = :template_id
		AND t.primary_org_id = :org_id
	", (["org_id":org, "template_id":template_id])))
		]);
	return jsonify(template);

};

__async__ mapping(string:mixed)|string|Concurrent.Future handle_create(Protocols.HTTP.Server.Request req, string org) {

		string query = #"
		INSERT INTO templates (
			name, primary_org_id
		)
		VALUES (:name, :org)
		RETURNING id
	";

	mapping bindings = (["name":req->misc->json->name, "org":org]);

	array result = await(G->G->DB->run_pg_query(query, bindings));

	//werror("body: %O\n", req->body_raw);
	//string template_name = req->body_raw->name;
	return jsonify(result[0]);
};
mapping(string:mixed)|string|Concurrent.Future handle_update(Protocols.HTTP.Server.Request req, string org, string template) { };
mapping(string:mixed)|string|Concurrent.Future handle_delete(Protocols.HTTP.Server.Request req, string org, string template) { };
