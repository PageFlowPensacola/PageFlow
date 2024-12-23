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
> <footer>[Clear Rectangle](: #deleterect) [Cancel](.dialog_close)</footer>
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

// TODO maybe dedupe following two with ones in analysis.pike
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

	conn->template_domains[group] = sizeof(domains) ? domains[0]->domain : "---";
	array pending = conn->pending;
	conn->pending = 0;

	foreach(pending, mapping(string:mixed) msg) {
		G->G->bouncers["connection.pike()->ws_msg"](msg, conn);
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

__async__ mapping(string:mixed)|string|zero http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->session->email)  {
		return render_template("login.md", (["msg": "You must be logged in to access templates."]));
	}
	werror("templates: %O\n", req->misc->session->domain);
	int templateid = (int) req->variables->id;
	if (templateid) {
		array(mapping(string:mixed)) pages = await(G->G->DB->run_pg_query(#"
			SELECT page_data, pxleft, pxtop, pxright, pxbottom
			FROM template_pages p
			JOIN templates t ON p.template_id = t.id
			WHERE t.id = :template_id
			AND t.domain LIKE :domain
			ORDER BY p.page_number
		", (["domain":req->misc->session->auth_domain+"%", "template_id":templateid])));
		foreach(pages, mapping page) {
			page->page_data = "data:image/png;base64," + MIME.encode_base64(page->page_data);
		}
		if(!sizeof(pages)) {
			return 0;
		}
		werror("pages: %O %O\n", req->misc->session->auth_domain, templateid);
		return render(req, (["vars": (["ws_group": templateid, "pages": pages])]));
	}
	return render(req, (["vars": (["ws_group": req->misc->session->domain])]));
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
			"signatory_id": msg->signatory_id || Val.null
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
	if (stringp(group)){
		array(mapping) templates = await(G->G->DB->run_pg_query(#"
		SELECT id, name, page_count, domain FROM templates
		WHERE :domain LIKE domain || '%'
		AND id != 0", (["domain":group])));
		return (["templates":templates]);
	}

	int template_id = group;

	mapping details = await(G->G->DB->run_pg_query(#"
		SELECT name, page_count as count
		FROM templates
		WHERE id = :template_id
		AND page_count IS NOT NULL
	", (["template_id":template_id])));

	werror("Details: %O\n", details);

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

	array result = await(G->G->DB->run_pg_query(#"
		INSERT INTO templates (
			name, domain
		)
		VALUES (:name, :domain)
		RETURNING id
	", (["name":msg->name, "domain": conn->session->domain])));

	string upload_id = G->G->prepare_upload("template", (["template_id": result[0]->id]));

	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "upload_id": upload_id])));
};

mapping(string:mixed)|string|Concurrent.Future handle_update(Protocols.HTTP.Server.Request req, string org, string template) { };

__async__ void websocket_cmd_delete_template(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("Delete template %O\n", msg->id);
	if (!stringp(conn->group)) return;

	array(mapping) pagecounts = await(G->G->DB->run_pg_query(#"
		DELETE FROM templates
		WHERE id = :template
		AND :domain LIKE domain || '%'
		RETURNING page_count", (["domain": conn->group, "template":msg->id])));

	if (sizeof(pagecounts) && pagecounts[0]->page_count) {
		array(mapping) domains = await(G->G->DB->run_pg_query(#"
			SELECT name
			FROM domains
			WHERE name LIKE :domain || '%' AND ml_model IS NOT NULL", (["domain": conn->group])));

		foreach(domains, mapping domain) {
			for (int i = 1; i <= pagecounts[0]->page_count; i++) {
				werror("Clearing page %O for %s and template %O\n", i, domain->name, msg->id);
				classipy(domain->name,
						([
							"cmd": "untrain",
							"pageref_prefix": sprintf("%d:", msg->id),
						]));
			}
		}
	}




	send_updates_all(msg->id);
	send_updates_all(conn->group);
};
