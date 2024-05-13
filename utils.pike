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

@"Tesseract and parse HOCR on a PNG file named annoteted.png":
__async__ void tesseract(){
	[string fn] = G->G->args[Arg.REST];
	mapping|object img = Image.PNG._decode(Stdio.read_file(fn));
	if (img->alpha) {
		// Make a blank image of the same size as the original image
		object blank = Image.Image(img->xsize, img->ysize, 255, 255, 255);
		// Paste original into it, fading based on alpha channel
		img->image = blank->paste_mask(img->image, img->alpha);
	}
	int left = img->xsize, top = img->ysize, right = 0, bottom = 0;
	img = img->image;
	img->setcolor(255, 0, 255);
	mapping hocr = await(run_promise(({"tesseract", fn, "-", "hocr"})));
	array data = Parser.XML.Simple()->parse(hocr->stdout){
		// implicit lambda
		[string type, string name, mapping attr, mixed data, mixed loc] = __ARGS__;
		switch (type) {
			case "<?xml": return 0;
			case "<": return 0;
			case "":
				data = String.trim(data);
				return data != "" && data;
			case ">":
			// Ensure we always get back an array of arrays, but flatten to single array.
			if (name == "body") return Array.arrayify(data[*]) * ({ });
			if (name == "html") return data * ({ });
				switch (attr->class) {
					case "ocr_page": return data;
					case "ocr_carea": {
						sscanf(attr->title, "%*sbbox %d %d %d %d", int l, int t, int r, int b);
						left = min(left, l); top = min(top, t);
						right = max(right, r); bottom = max(bottom, b);
						return data * "\n\n";
					}
					case "ocr_par": return data * "\n";
					case "ocr_line": return data * " ";
					case "ocrx_word": return data * " ";
					default: return 0;
				}
		}
	} * ({ }); // then flatten at the end
	img->line(left, top, right, top);
	img->line(right, top, right, bottom);
	img->line(right, bottom, left, bottom);
	img->line(left, bottom, left, top);
	img->line(left, top, right, bottom);
	img->line(right, top, left, bottom);
	Stdio.write_file("annotated.png", Image.PNG.encode(img));
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
