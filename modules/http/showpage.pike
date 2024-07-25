inherit http_endpoint;

constant IS_A_SIGNATURE = 75;

mapping annotate_transition_scores(object img, array rects, array transform) {
	object grey = img->grey();

	int page_transition_score = 0;
	int page_calculated_transition_score = 0;
	array field_results = ({});
	foreach (rects || ({}), mapping r) {
		mapping box = calculate_transition_score(r, grey, transform);
		werror("Box %O\n", box);

		img->setcolor(@audit_rect_color, 0);
		img->line(box->x1, box->y1, box->x2, box->y1);
		img->line(box->x2, box->y1, box->x2, box->y2);
		img->line(box->x2, box->y2, box->x1, box->y2);
		img->line(box->x1, box->y2, box->x1, box->y1);

		int alpha = 200; // HACK limit(16, (box->score - r->transition_score) * 255 / IS_A_SIGNATURE, 255);

		img->box(box->x1, box->y1, box->x2, box->y2, 0, 255, 255, alpha);
	}
}

/*
TODO support width equals
*/
__async__ mapping http_request(Protocols.HTTP.Server.Request req) {
	int file = (int) req->variables->id;
	int file_page = (int) req->variables->page;
	array(mapping) image = await(G->G->DB->run_pg_query(#"
		SELECT png_data, transform, template_id, page_number
		FROM uploaded_file_pages
		WHERE file_id = :id AND seq_idx = :page", (["id": file, "page": file_page])));
		if (!sizeof(image)) return 0;
	string png = image[0]->png_data;
	if (req->variables->annotate) {
		Image.Image img = Image.PNG.decode(png);
		array(mapping) audit_rects = await(G->G->DB->run_pg_query(#"
			SELECT x1, y1, x2, y2, template_signatory_id, transition_score
			FROM audit_rects
			WHERE template_id = :id AND page_number = :page", (["id": image[0]->template_id, "page": image[0]->page_number])));
		annotate_transition_scores(img, audit_rects, Standards.JSON.decode(image[0]->transform));
		png = Image.PNG.encode(img);
	}
	return (["data": png, "type": "image/png"]);
}
