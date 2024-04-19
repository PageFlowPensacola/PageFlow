inherit restful_endpoint;

__async__ mapping(string:mixed)|Concurrent.Future handle_detail(Protocols.HTTP.Server.Request req, string org, string template_id, string page_number) {

	string query = #"
		SELECT page_data FROM template_pages p
		JOIN templates t ON p.template_id = t.id
		WHERE t.id = :template_id
		AND t.primary_org_id = :org_id
		AND p.page_number = :page_number
	";

	mapping bindings = (["org_id":org, "template_id":template_id, "page_number":page_number]);
	array(mapping(string:mixed)) image = await(G->G->DB->run_pg_query(query, bindings));
	if (sizeof(image) == 0) {
		return 0; // 404
	}
	return (["data": image[0]->page_data, "type": "image/png"]);

};

__async__ mapping(string:mixed)|Concurrent.Future handle_list(Protocols.HTTP.Server.Request req, string org, string template_id) {

	string query = #"
		SELECT page_data, pxleft, pxtop, pxright, pxbottom
		FROM template_pages p
		JOIN templates t ON p.template_id = t.id
		WHERE t.id = :template_id
		AND t.primary_org_id = :org_id
		ORDER BY p.page_number
	";
	mapping bindings = (["org_id":org, "template_id":template_id]);
	array(mapping(string:mixed)) pages = await(G->G->DB->run_pg_query(query, bindings));
	foreach(pages, mapping page) {
		page->page_data = "data:image/png;base64," + MIME.encode_base64(page->page_data);
	}
	// again Automap
	return jsonify(pages);

};
