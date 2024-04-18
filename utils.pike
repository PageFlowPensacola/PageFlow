protected void create (string name) {
	G->G->utils = this;
}

void test() {
	werror("Hello World\n");
}

__async__ void audit_score() {
	await(G->G->DB->recalculate_transition_scores(0, 0));
}

__async__ void compare_scores() {
	array(int) args = (array(int)) G->G->args[Arg.REST];
	// expecting 3 arguments: template_id, page_no, file_id (a second template, perhaps)
	await(G->G->DB->compare_transition_scores(@args));
}

__async__ void update_page_bounds() {
	array(mapping) pages = await(G->G->DB->run_pg_query(#"
			SELECT template_id, page_number, page_data
			FROM template_pages
			WHERE pxleft IS NULL"));

	foreach(pages, mapping page) {
		mapping img = Image.PNG._decode(page->page_data);
		int right, bottom;
		int left = img->xsize;
		int top = img->ysize;
		mapping rc = await(run_promise(({"tesseract", "-", "-", "makebox"}), (["stdin": page->page_data])));
		foreach(rc->stdout / "\n", string line){
			array(string) parts = line / " ";
			if (sizeof(parts) < 6){
				continue;
			}
			if (parts[0] == "~"){
				continue;
			}
			int x1 = (int)parts[1];
			int y1 = img->ysize - (int)parts[2];
			int x2 = (int)parts[3];
			int y2 = img->ysize - (int)parts[4];
			left = min(left, (x1 + x2) / 2);
			top = min(top, (y1 + y2) / 2);
			right = max(right, (x1 + x2) / 2);
			bottom = max(bottom, (y1 + y2) / 2);
		}
		werror("Template %d: Pg %d: %d %d %d %d\n", page->template_id, page->page_number, left, right, top, bottom);
		await(G->G->DB->run_pg_query(#"
				UPDATE template_pages
				SET pxleft = :pxleft, pxright = :pxright, pxtop = :pxtop, pxbottom = :pxbottom
				WHERE template_id = :template_id
				AND page_number = :page_number",
			(["template_id": page->template_id, "page_number": page->page_number, "pxleft": left, "pxright": right, "pxtop": top, "pxbottom": bottom])));
	}
}
