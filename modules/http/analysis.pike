inherit http_websocket;

constant markdown = "# Analysis\n\n";

__async__ void websocket_cmd_upload(mapping(string:mixed) conn, mapping(string:mixed) msg){
	werror("CONN SESSION %O\n", conn->session);
	// @TODO actually create a group for this once we're actually saving something
	int fileid = await(G->G->DB->run_pg_query(#"
		INSERT INTO uploaded_files
		(filename, domain)
		VALUES (:filename, :domain)
		returning id", (["filename": msg->name, "domain": conn->session->domain])))[0]->id;

	string upload_id = G->G->prepare_upload(
		"contract", ([
			"template_id": msg->template, // TODO this is no longer relevant
			"file_id": fileid,
			"conn": conn]));
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "upload_id": upload_id, "group": fileid])));
}

void websocket_cmd_delete_analysis(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	// @TODO actually delete the analysis
	G->G->DB->run_pg_query(#"
		DELETE FROM uploaded_files
		WHERE id = :id", (["id": msg->id]));
	send_updates_all(conn->group);
}

// TODO maybe dedupe following two functions with the ones in templates.pike
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

	/*
	@TODO eventually reenstate some validation here
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
	return ""; */
	// implicitly return 0
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

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->session->user_id) {
		return render_template("login.md", (["msg": "You must be logged in to analyze files."]));
	}
	int fileid = (int) req->variables->id;
	if (fileid) {
		return render(req, (["vars": (["ws_group": fileid])]));
	}
	return render(req, (["vars": (["ws_group": req->misc->session->domain])]));
};

array calc_transition_scores(Image.Image img, array(mapping) rects, array transform){
	array results = ({});
	object grey = img->grey();
	foreach (rects || ({}), mapping r) {
		mapping box = calculate_transition_score(r, grey, transform);
		int difference = abs(r->transition_score - box->score);
		results += ({
			([
				"difference": difference,
				"signatory": r->template_signatory_id,
				"status": (difference >= 100) ? "Signed" : (difference >= 25) ? "Unclear" : "Unsigned",
			])
		});
	}
	return results;
}

__async__ mapping get_state(string|int group, string|void id, string|void type){
	if (stringp(group)) {
		// if group is a string, it's a domain eg 'com.pageflow.tagtech.'
		array(mapping) files = await((G->G->DB->run_pg_query(#"
			SELECT filename, page_count, id, created_at as created
			FROM uploaded_files
			WHERE :domain LIKE domain || '%'", (["domain":group]))));
		return (["files": files]);
	}
	// Must have an analysis set in mind
	array(mapping) file = await((G->G->DB->run_pg_query(#"
		SELECT filename, page_count, id, created_at as created
		FROM uploaded_files
		WHERE id = :id", (["id": group]))));
	array(mapping) pages = await((G->G->DB->run_pg_query(#"
		SELECT png_data, template_id, page_number, seq_idx, transform
		FROM uploaded_file_pages
		WHERE file_id = :id", (["id": group]))));
	if (!sizeof(file) || !sizeof(pages)) {
		return 0;
	}
	// This will store template pages (rects, etc)
	mapping templates = ([]);

	// TODO can we move this into a function?
	multiset signatories = (<>);
	foreach(pages, mapping page){
		string template_id = (string) (page->template_id || 9999999999);
		if (!templates[template_id]) templates[template_id] = ([]);
		string png = page->png_data;
		array(mapping) audit_rects = await((G->G->DB->run_pg_query(#"
			SELECT x1, y1, x2, y2, template_signatory_id, transition_score
			FROM audit_rects
			WHERE template_id = :id AND page_number = :page", (["id": page->template_id, "page": page->page_number]))));

		templates[template_id][ (string) (page->page_number || 1)] += ({
			([
				"audit_rects": audit_rects,
				"scores": calc_transition_scores(
						Image.PNG.decode(png),
						audit_rects,
						Standards.JSON.decode(page->transform),
					),
				"seq_idx": page->seq_idx,
			])
		});
		signatories |= (multiset) audit_rects->template_signatory_id;
	}

	// fetch signatory names from template_signatories
	array(mapping) signatory_names = await((G->G->DB->run_pg_query(sprintf(#"
		SELECT id, name
		FROM template_signatories
		WHERE id IN  (%{%d,%}0)", (array) signatories))));
	mapping signatory_map = mkmapping((array(string)) signatory_names->id, signatory_names->name);
	// fetch signatory names from template_signatories
	array(mapping) template_names = await((G->G->DB->run_pg_query(sprintf(#"
		SELECT id, name
		FROM templates
		WHERE id IN (%{%s,%}0) AND id != 0 ORDER BY name", indices(templates)))));
	if (templates["9999999999"]) template_names += ({([ "id": 9999999999, "name": "No template matched" ])});

	templates["0"] = (["1": ({([ "audit_rects": ([]), "scores": ({}), "seq_idx": 0 ])})]);
	// TODO handle duplicate pages

	return (["file":file[0], "templates":templates, "template_names": template_names, "signatories": signatory_map]);
}
