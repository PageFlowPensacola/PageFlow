inherit http_endpoint;

constant IS_A_SIGNATURE = 75;

mapping calculate_transition_scores(Image.Image img, mapping bounds, array rects){
	object grey = img->grey();

	int left = bounds->left;
	int top = bounds->top;
	int right = bounds->right;
	int bottom = bounds->bottom;

	img->setcolor(@bbox_color);
	img->line(left, top, right, top);
	img->line(right, top, right, bottom);
	img->line(right, bottom, left, bottom);
	img->line(left, bottom, left, top);
	img->line(left, top, right, bottom);
	img->line(right, top, left, bottom);
	int page_transition_score = 0;
	int page_calculated_transition_score = 0;
	array field_results = ({});
	foreach (rects || ({}), mapping r) {
		mapping box = calculate_transition_score(r, bounds, grey);

		img->setcolor(@audit_rect_color, 0);
		img->line(box->x1, box->y1, box->x2, box->y1);
		img->line(box->x2, box->y1, box->x2, box->y2);
		img->line(box->x2, box->y2, box->x1, box->y2);
		img->line(box->x1, box->y2, box->x1, box->y1);

		int alpha = limit(16, (box->score - r->transition_score) * 255 / IS_A_SIGNATURE, 255);

		img->box(box->x1, box->y1, box->x2, box->y2, 0, alpha, alpha);

		/*page_transition_score += r->transition_score;
		page_calculated_transition_score += box->score;
		int difference = abs(r->transition_score - box->score);
		field_results += ({
			([
				"signatory": r->template_signatory_id,
				"status": (difference >= 100) ? "Signed" : (difference >= 25) ? "Unclear" : "Unsigned",
			])
		}); */
	}
}

__async__ mapping http_request(Protocols.HTTP.Server.Request req) {
	int file = (int) req->variables->id;
	int file_page = (int) req->variables->page;
	array(mapping) image = await(G->G->DB->run_pg_query(#"
		SELECT ocr_result, png_data, template_id, page_number
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
		mapping ocr = Standards.JSON.decode(image[0]->ocr_result);
		calculate_transition_scores(img, ([
			"left": min(@ocr->pos[0]),
			"top": min(@ocr->pos[1]),
			"right": max(@ocr->pos[2]),
			"bottom": max(@ocr->pos[3]),
		]), audit_rects);
		png = Image.PNG.encode(img);
	}
	return (["data": png, "type": "image/png"]);
}
