inherit restful_endpoint;
inherit websocket_handler;

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (msg->group == "") return 0; // login not required.
	if (string err = ::websocket_validate(conn, msg)) return err;
	if (!conn->auth) return "Not logged in";
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
			WHERE id = :id", ([
				"id": msg->id,
				"name": msg->name
			])));
	} else {
		// Otherwise, insert a new one
		await(G->G->DB->run_pg_query(#"
			INSERT INTO template_signatories (
				template_id, name
			)
			VALUES (:template_id, :name)", ([
				"template_id": template,
				"name": msg->name
			])));
	}
	send_updates_all(conn->group);
}

__async__ void websocket_cmd_delete_signatory(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf((string)conn->group, "%d:%d", int org, int template);
	await(G->G->DB->run_pg_query(#"
		DELETE FROM template_signatories
		WHERE id = :id", ([
			"id": msg->id
		])));
	send_updates_all(conn->group);
}

__async__ void websocket_cmd_add_rect(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf((string)conn->group, "%d:%d", int org, int template);
	int page = msg->page;
	werror("add_rect: %O %O %O\n", conn->group, msg, page);
	await(G->G->DB->run_pg_query(#"
		INSERT INTO audit_rects (
			template_id, x1, y1, x2, y2, page_number, audit_type, template_signatory_id
		)
		VALUES (:template_id, :x1, :y1, :x2, :y2, :page_number, :audit_type, :signatory_id)", ([
			"template_id": template,
			// multiply by 2 pow 15 to get to largest number that fits in a signed int
			"x1": msg->rect->left * 32767,
			"y1": msg->rect->top * 32767,
			"x2": msg->rect->right * 32767,
			"y2": msg->rect->bottom * 32767,
			"page_number": page,
			"audit_type": "rect",
			"signatory_id": msg->signatory_id
		])));
	send_updates_all(conn->group);
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

	return render(req,
	([
			"vars": (["ws_group": req->misc->auth ? org : ""]),
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

	array(mapping) rects = await(G->G->DB->run_pg_query(#"
			SELECT x1, y1, x2, y2, page_number, audit_type, template_signatory_id
			FROM audit_rects
			WHERE template_id = :template_id", (["template_id":template_id])));

	array page_rects = allocate(details[0]->count, ({ }));

	foreach(rects, mapping rect) {
		rect-> x1 /= 32767.0;
		rect-> y1 /= 32767.0;
		rect-> x2 /= 32767.0;
		rect-> y2 /= 32767.0;
		page_rects[rect->page_number - 1] += ({ rect });
	}

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

			"page_rects": page_rects,
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
