protected void create (string name) {
	templatestuff();
}

__async__ void templatestuff() {
	array(mapping) template_pages = await(G->G->DB->run_pg_query(#"
			SELECT page_number, page_data
			FROM template_pages
			WHERE template_id = :template_id",
			(["template_id":42]))
	);

	array(mapping) rects = await(G->G->DB->run_pg_query(#"
			SELECT x1, y1, x2, y2, page_number, audit_type, template_signatory_id, id
			FROM audit_rects
			WHERE template_id = :template_id", (["template_id":42])));

	mapping page_rects = ([]);
	foreach (rects, mapping r) page_rects[r->page_number] += ({r});

	foreach (template_pages, mapping p) {
		mapping img = Image.PNG._decode(p->page_data);
		object grey = img->image->grey();
		foreach(page_rects[p->page_number] || ({}), mapping r) {
			int last = -1, transitions = 0, count = 0;
			for (int y = r->y1; y < r->y2; ++y) {
				for (int x = r->x1; x < r->x2; ++x) {
					int cur = grey->getpixel(x * img->xsize / 32767, y * img->ysize / 32767)[0] > 128;
					transitions += (cur != last);
					last = cur;
					count++;
				}
			}
			werror("Page no: %d Signatory Id: %d Transitions: %d, count: %d, ratio: %f\n", r->page_number, r->template_signatory_id || 0, transitions, count, transitions / (float)count * 100);
		}
		// Do stuff with page_data and page_rects
	}

	exit(0);
}
