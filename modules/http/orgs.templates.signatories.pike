inherit restful_endpoint;

__async__ mapping(string:mixed)|Concurrent.Future handle_list(Protocols.HTTP.Server.Request req, string org, string template_id) {

	string query = #"
		SELECT s.name as field_name, s.id as signatory_id FROM template_signatories s
		JOIN templates t ON s.template_id = t.id
		WHERE t.id = :template_id
		AND t.primary_org_id = :org_id
	";

	mapping bindings = (["org_id":org, "template_id":template_id]);

	return jsonify(await(G->G->DB->run_pg_query(query, bindings)));

};

__async__ mapping(string:mixed)|Concurrent.Future handle_create(Protocols.HTTP.Server.Request req, string org, string template_id) {

	mapping data = req->misc->json;

	string query = #"
		INSERT INTO template_signatories (template_id, name)
		VALUES (:template_id, :name)
		RETURNING id
	";

	mapping bindings = ([
		"template_id":template_id,
		"name":data["name"],
	]);

	return jsonify(await(G->G->DB->run_pg_query(query, bindings)));

};
