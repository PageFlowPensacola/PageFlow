protected void create (string name) {
	G->G->utils = this;
}

@"Test":
void test() {
	werror("Hello World\n");
}

@"Audit score":
__async__ void audit_score() {
	await(G->G->DB->recalculate_transition_scores(0, 0));
}

@"Compare scores":
__async__ void compare_scores() {
	array(int) args = (array(int)) G->G->args[Arg.REST];
	// expecting 3 arguments: template_id, page_no, file_id (a second template, perhaps)
	await(G->G->DB->compare_transition_scores(@args));
}

@"Update page bounds":
__async__ void update_page_bounds() {
	werror("Updating page bounds\n");
	array(mapping) pages = await(G->G->DB->run_pg_query(#"
			SELECT template_id, page_number, page_data
			FROM template_pages
			WHERE pxleft IS NULL"));

	foreach(pages, mapping page) {
		mapping img = Image.PNG._decode(page->page_data);
		mapping bounds = await(calculate_image_bounds(page->page_data, img->xsize, img->ysize));
		await(G->G->DB->run_pg_query(#"
				UPDATE template_pages
				SET pxleft = :left, pxright = :right, pxtop = :top, pxbottom = :bottom
				WHERE template_id = :template_id
				AND page_number = :page_number",
			(["template_id": page->template_id, "page_number": page->page_number]) | bounds));
	}
}

@"This help information":
void help() {
	write("\nUSAGE: pike app --exec=ACTION\nwhere ACTION is one of the following:\n");
	array names = indices(this), annot = annotations(this);
	sort(names, annot);
	foreach (annot; int i; multiset|zero annot)
		foreach (annot || (<>); mixed anno;)
			if (stringp(anno)) write("%-20s: %s\n", names[i], anno);
}
