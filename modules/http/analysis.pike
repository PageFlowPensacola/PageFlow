inherit http_websocket;

constant markdown = "# Analysis\n\n";

__async__ void websocket_cmd_upload(mapping(string:mixed) conn, mapping(string:mixed) msg){
	// @TODO actually create a group for this once we're actually saving something

	string fileid = await(G->G->DB->run_pg_query(#"
		INSERT INTO uploaded_files
		filename
		VALUES (:filename)
		returning id", (["filename": msg->filename])))[0]->id;

	string upload_id = G->G->prepare_upload(
		"contract", ([
			"template_id": msg->template,
			"file_id": fileid,
			"conn": conn]));
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "upload_id": upload_id, "group": fileid])));
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

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->session->user_id) {
		return render_template("login.md", (["msg": "You must be logged in to analyze files."]));
	}
	return render(req, (["vars": (["ws_group": req->misc->session->domain])]));
};

__async__ mapping get_state(string|int group, string|void id, string|void type){
	werror("get_state: %O %O %O\n", group, id, type);
	// BROKEN.
	array(mapping) templates = await(G->G->DB->get_templates_for_domain(group));
	return (["templates":templates]);
}
