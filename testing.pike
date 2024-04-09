protected void create (string name) {
	templatestuff();
}

__async__ void templatestuff() {
	array(mapping) template_pages = await(G->G->DB->run_pg_query(#"
			SELECT template_id, page_number, page_data
			FROM template_pages"));

	array(mapping) rects = await(G->G->DB->run_pg_query(#"
			SELECT template_id, x1, y1, x2, y2, page_number, audit_type, template_signatory_id, id
			FROM audit_rects WHERE transition_score = -1"));

	mapping page_rects = ([]);
	foreach (rects, mapping r) page_rects[r->template_id+":"+r->page_number] += ({r});

	foreach (template_pages, mapping p) {
		mapping img = Image.PNG._decode(p->page_data);
		object grey = img->image->grey();
		foreach(page_rects[p->template_id+":"+p->page_number] || ({}), mapping r) {
			int last = -1, transitions = 0, count = 0;
			for (int y = r->y1; y < r->y2; ++y) {
				for (int x = r->x1; x < r->x2; ++x) {
					int cur = grey->getpixel(x * img->xsize / 32767, y * img->ysize / 32767)[0] > 128;
					transitions += (cur != last);
					last = cur;
					count++;
				}
			}
			await(G->G->DB->run_pg_query(#"
				UPDATE audit_rects
				SET transition_score = :score
				WHERE id = :id", (["score": count/transitions, "id": r->id])));
			werror("Template Id: %d Page no: %d Signatory Id: %d Transitions: %d, count: %d, transition score: %d\n", r->template_id, r->page_number, r->template_signatory_id || 0, transitions, count, count/transitions);
		}
		// Do stuff with page_data and page_rects
	}

	exit(0);
}
