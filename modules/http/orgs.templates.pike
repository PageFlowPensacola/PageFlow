inherit restful_endpoint;
inherit websocket_handler;

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (string err = ::websocket_validate(conn, msg)) return err;
	if (!conn->auth && msg->group != "") return "Not logged in";
	// TODO check for user org access
}

constant unauthenticated_landing_page = 1;

constant markdown = #"# Templates Listing

";

void websocket_cmd_hello(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("Got a hello! %O\n", conn->auth);
}

__async__ void websocket_cmd_set_signatory(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf((string)conn->group, "%d:%d", int org, int template);
	// If we receive an id, make it an update
	if (msg->id) {
		await(G->G->DB->run_pg_query(#"
			UPDATE template_signatories
			SET name = :name
			WHERE id = :id
			RETURNING id", ([
				"id": msg->id,
				"name": msg->name
			])));
	} else {
		// Otherwise, insert a new one
		await(G->G->DB->run_pg_query(#"
			INSERT INTO template_signatories (
				template_id, name
			)
			VALUES (:template_id, :name)
			RETURNING id", ([
				"template_id": template,
				"name": msg->name
			])));
	}
	G->G->websocket_types["orgs.templates"]->send_updates_all(org + ":" + template);
}

__async__ void websocket_cmd_delete_signatory(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("Got a conn! %O\n and a delete request %O\n", conn, msg);
	sscanf((string)conn->group, "%d:%d", int org, int template);
	await(G->G->DB->run_pg_query(#"
		DELETE FROM template_signatories
		WHERE id = :id
		RETURNING id", ([
			"id": msg->id
		])));
	G->G->websocket_types["orgs.templates"]->send_updates_all(org + ":" + template);
}

__async__ void websocket_cmd_add_rect(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("Got a conn! %O\n and a rect %O\n", conn, msg);

	sscanf((string)conn->group, "%d:%d", int org, int template);
	int page = msg->page;
	await(G->G->DB->run_pg_query(#"
		INSERT INTO audit_rects (
			template_id, x1, y1, x2, y2, page_number, audit_type, template_signatory_id
		)
		VALUES (:template_id, :x1, :y1, :x2, :y2, :page_number, :audit_type, :signatory_id)
		RETURNING id", ([
			"template_id": template,
			"x1": msg->rect->left,
			"y1": msg->rect->top,
			"x2": msg->rect->right,
			"y2": msg->rect->bottom,
			"page_number": page,
			"audit_type": "rect",
			"signatory_id": msg->signatory_id
		])));
	G->G->websocket_types["orgs.templates"]->send_updates_all(org + ":" + template);
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
			"name": details[0]->name,
			"page_count": details[0]->count,

			"signatories": await(G->G->DB->run_pg_query(#"
			SELECT s.name as signatory_field,
			s.id as signatory_id
			FROM template_signatories s
			JOIN templates t ON s.template_id = t.id
			WHERE t.id = :template_id
			AND t.primary_org_id = :org_id
	", (["org_id":org, "template_id":template_id]))),

			"rects": await(G->G->DB->run_pg_query(#"
			SELECT x1, y1, x2, y2, page_number, audit_type
			FROM audit_rects
			WHERE template_id = :template_id", (["template_id":template_id])))
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

__async__ mapping(string:mixed)|string|Concurrent.Future handle_delete(Protocols.HTTP.Server.Request req, string org, string template) {
	string query = #"
		DELETE FROM templates
		WHERE id = :template
		AND primary_org_id = :org";
	mapping bindings = (["org":org, "template":template]);

	await(G->G->DB->run_pg_query(query, bindings));

	send_updates_all(org + ":");
	send_updates_all(org + ":" + template);

	return (["error": 204]);
};


// Due to a quirk in Pike, multiple inheritance
// requires that the create() function be defined.
protected void create(string name) {::create(name);}
