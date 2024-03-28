inherit restful_endpoint;
inherit websocket_handler;

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	msg["group"] = (string) msg["group"];
	if (!conn->auth && msg->group != "") return "Not logged in";
	// TODO check for user org access
}

constant unauthenticated_landing_page = 1;

constant markdown = #"# Templates Listing

";

void websocket_cmd_hello(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("Got a hello! %O\n", conn->auth);
}

// Called on connection and update.
__async__ mapping get_state(string|int group, string|void id, string|void type){
	werror("get_state: %O %O %O\n", group, id, type);
	sscanf(group, "%d:%d", int org, int template);
	if (template){
		return await(template_details(org, template));
	}
	array(mapping) templates = await(G->G->DB->get_templates_for_org(group));
	return (["templates":templates]);
}

__async__ mapping(string:mixed)|string handle_list(Protocols.HTTP.Server.Request req, string org) {
	//werror("handle_list: %O %O %O\n", req, org, template);

	//werror("%O\n", templates);

	return render(req,
	([
			"vars": (["ws_group": org]),
	]));
};

__async__ mapping(string:mixed)|string|Concurrent.Future template_details(int org, int template_id) {
	if (! (int) org) return ([ "error": 403 ]);
	if (!template_id) return 0;
	mapping details = await(G->G->DB->run_pg_query(#"
		SELECT name,
		(SELECT count(*)
		FROM template_pages
		WHERE template_id = :template_id)
		FROM templates
		WHERE primary_org_id = :org_id
	", (["org_id":org, "template_id":template_id])));

	mapping template = (
		[
			"name": details[0]->template_name,
			"page_count": details[0]->count,
			"signatories": await(G->G->DB->run_pg_query(#"
			SELECT s.name as signatory_field
			FROM template_signatories s
			JOIN templates t ON s.template_id = t.id
			WHERE t.id = :template_id
			AND t.primary_org_id = :org_id
	", (["org_id":org, "template_id":template_id])))
		]);
	return template;

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


// Due to a quirk in Pike, multiple inheritance
// requires that the create() function be defined.
protected void create(string name) {::create(name);}
