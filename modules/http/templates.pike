inherit http_websocket;

constant markdown = #"# Templates

> ### Edit audit rect
>
> <form method=dialog>
> <label>Signatory
>  <select class=rectlabel name=signatory_id id=signatories></select>
> </label>
>
>
> <footer>[Clear Rectangle](: type=submit value=delete) [Cancel](: type=submit value=cancel)</footer>
> </form>
{: tag=dialog #editauditrect}

";

__async__ void websocket_cmd_set_signatory(mapping(string:mixed) conn, mapping(string:mixed) msg) {
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
				"template_id": conn->group,
				"name": msg->name
			])));
	}
	send_updates_all(conn->group);
}


string|zero websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->session->domain) {
		return "Not authorized";
	}
	if (stringp(msg->group)) {
		if (has_prefix(msg->group, conn->session->domain)) {
			return 0;
		} else {
			return "Not authorized";
		}
	} // else group must be a template id

	if (!conn->template_domains) conn->template_domains = ([]);
	string domain = conn->template_domains[msg->group];
	if (domain) {
		if (has_prefix(conn->session->domain, domain)) {
			return 0;
		} else {
			return "Not authorized";
		}
	}
	fetch_template_domain(conn, msg->group);
	return "";
}

__async__ void 	fetch_template_domain(mapping conn, int group) {
	array(mapping) domains = await(G->G->DB->run_pg_query(#"
		SELECT domain
		FROM templates
		WHERE id = :id", (["id":group])));
	werror("#####domains: %O\n", domains);
	conn->template_domains[group] = sizeof(domains) ? domains[0]->domain : "---";
	array pending = conn->pending;
	conn->pending = 0;
	foreach(pending, mapping(string:mixed) msg) {
		G->G->bouncers["connection.pike()->ws_msg"](conn, msg);
	}

}

__async__ void websocket_cmd_delete_signatory(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	// TODO check who owns this document.
	await(G->G->DB->run_pg_query(#"
		DELETE FROM template_signatories
		WHERE id = :id", ([
			"id": msg->id
		])));
	send_updates_all(conn->group);
}

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	werror("templates: %O\n", req->misc->session);
	return render(req, (["vars": (["ws_group": req->misc->session->domain])]));// TODO ability to switch domains & select template.
};

__async__ void websocket_cmd_add_rect(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	int page = msg->page;
	werror("add_rect: %O %O %O\n", conn->group, msg, page);
	await(G->G->DB->run_pg_query(#"
		INSERT INTO audit_rects (
			template_id, x1, y1, x2, y2, page_number, audit_type, template_signatory_id
		)
		VALUES (:template_id, :x1, :y1, :x2, :y2, :page_number, :audit_type, :signatory_id)", ([
			"template_id": conn->group,
			"x1": msg->rect->left,
			"y1": msg->rect->top,
			"x2": msg->rect->right,
			"y2": msg->rect->bottom,
			"page_number": page,
			"audit_type": "rect",
			"signatory_id": msg->signatory_id
		]))
	);
	send_updates_all(conn->group);
	G->G->DB->recalculate_transition_scores((int) conn->group, page);
}

__async__ void websocket_cmd_delete_rect(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->run_pg_query(#"
		DELETE FROM audit_rects
		WHERE id = :id
		AND template_id = :template", ([
			"id": msg->id,
			"template": conn->group
		])));
	send_updates_all(conn->group);
}

__async__ void websocket_cmd_set_rect_signatory(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->run_pg_query(#"
		UPDATE audit_rects
		SET template_signatory_id = :signatory_id
		WHERE id = :id
		AND template_id = :template", ([
			"id": msg->id,
			"signatory_id": (int) msg->signatory_id || Val.null,
			"template": conn->group
		])));
	send_updates_all(conn->group);
}

// Called on connection and update.
__async__ mapping get_state(string|int group, string|void id, string|void type){
	werror("get_state: %O %O %O\n", group, id, type);
	if (intp(group)){
		return await(template_details(group));
	}
	array(mapping) templates = await(G->G->DB->get_templates_for_domain(group));
	werror("templates: %O\n", templates);
	return (["templates":templates]);
}

__async__ mapping(string:mixed)|string|Concurrent.Future template_details(int template_id) {
	if (!template_id) return 0;

	mapping details = await(G->G->DB->run_pg_query(#"
		SELECT name, page_count as count
		FROM templates
		WHERE id = :template_id
		AND page_count IS NOT NULL
	", (["template_id":template_id])));

	array(mapping) rects = await(G->G->DB->run_pg_query(#"
			SELECT x1, y1, x2, y2, page_number, audit_type, template_signatory_id, id
			FROM audit_rects
			WHERE template_id = :template_id", (["template_id":template_id])));

	//create empty array empty array for each of count of pages
	array page_rects = allocate(details[0]->count, ({ }));

	foreach(rects, mapping rect) {
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
	", (["template_id":template_id]))),

			"page_rects": page_rects,
		]);

		werror("template: %O\n", template);

	return template;

};

__async__ void websocket_cmd_upload(mapping(string:mixed) conn, mapping(string:mixed) msg) {

		string query = #"
		INSERT INTO templates (
			name, domain
		)
		VALUES (:name, :domain)
		RETURNING id
	";

	mapping bindings = (["name":msg->name, "domain": conn->session->domain]);

	array result = await(G->G->DB->run_pg_query(query, bindings));

	string upload_id = G->G->prepare_upload("template", (["template_id": result[0]->id]));

	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "upload_id": upload_id])));
};

mapping(string:mixed)|string|Concurrent.Future handle_update(Protocols.HTTP.Server.Request req, string org, string template) { };

__async__ void websocket_cmd_delete_template(mapping(string:mixed) conn, mapping(string:mixed) msg) {

	if (!stringp(conn->group)) return;

	await(G->G->DB->run_pg_query(#"
		DELETE FROM templates
		WHERE id = :template
		AND :domain LIKE domain || '%'", (["domain": conn->group, "template":msg->id])));

	send_updates_all(msg->id);
	send_updates_all(conn->group);
};
