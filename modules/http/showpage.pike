inherit http_endpoint;

constant IS_A_SIGNATURE = 75;

mapping calculate_transition_scores(mapping img, mapping bounds, array rects){
	object grey = img->image->grey();

	int left = bounds->left;
	int top = bounds->top;
	int right = bounds->right;
	int bottom = bounds->bottom;

	img->image->setcolor(@bbox_color);
	img->image->line(left, top, right, top);
	img->image->line(right, top, right, bottom);
	img->image->line(right, bottom, left, bottom);
	img->image->line(left, bottom, left, top);
	img->image->line(left, top, right, bottom);
	img->image->line(right, top, left, bottom);
	int page_transition_score = 0;
	int page_calculated_transition_score = 0;
	array field_results = ({});
	foreach (rects || ({}), mapping r) {
		mapping box = calculate_transition_score(r, bounds, grey);

		img->image->setcolor(@audit_rect_color, 0);
		img->image->line(box->x1, box->y1, box->x2, box->y1);
		img->image->line(box->x2, box->y1, box->x2, box->y2);
		img->image->line(box->x2, box->y2, box->x1, box->y2);
		img->image->line(box->x1, box->y2, box->x1, box->y1);

		int alpha = limit(16, (box->score - r->transition_score) * 255 / IS_A_SIGNATURE, 255);

		img->image->box(box->x1, box->y1, box->x2, box->y2, 0, 192, 192, 255 - alpha);

		page_transition_score += r->transition_score;
		page_calculated_transition_score += box->score;
		int difference = abs(r->transition_score - box->score);
		field_results += ({
			([
				"signatory": r->template_signatory_id,
				"status": (difference >= 100) ? "Signed" : (difference >= 25) ? "Unclear" : "Unsigned",
			])
		});
	}
}

__async__ mapping http_request(Protocols.HTTP.Server.Request req) {
	int file = (int) req->variables->id;
	int file_page = (int) req->variables->page;
	array(mapping) image = await (G->G->DB->run_pg_query(#"
		SELECT ocr_result, png_data
		FROM uploaded_file_pages
		WHERE file_id = :id AND seq_idx = :page", (["id": file, "page": file_page])));
	return (["data": image[0]->png_data, "type": "image/png"]);
}
