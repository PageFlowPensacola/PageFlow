inherit http_endpoint;
inherit annotated;

@retain:mapping pending_uploads = ([]);

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {

	if (req->request_type != "POST") {
		return ([ "error": 405 ]);
	}

	mapping upload = m_delete(pending_uploads, req->variables->id);

	if (!upload) return ([ "error": 400 ]);

	return await(this[upload->type](req, upload));
}

__async__ array pdf2png(string pdf) {
	/*
		parse the body pdf and break into page pngs
		upload the pages to the storage
		create a new template record
		assign the pages to the template record
		upload the template record to the db
		return the new template record
	*/
	// fully async run process to convert pdf to png
	// The input:
	// this is where we're probably going to need a shuffler.
	// A shuffler is a Pike thing with is a very robust was of moving data around.
	// results will contain the stdout, stderr, and exit code of the process
	array pages = ({});

	// Time taken is quadratic based on density with
	// depth, quality and format (looked at png, tiff, ppm and webp)
	// not making much difference.
	mapping results = await(run_promise(
		({"convert", "-density", "100", "-", "png:-"}),
		(["stdin": pdf]))
	);
	//werror("results: %O\n", indices(results));
	// https://pike.lysator.liu.se/generated/manual/modref/ex/predef_3A_3A/_Stdio/Buffer.html#Buffer
	Stdio.Buffer data = Stdio.Buffer(results->stdout);
	// stdout will be a string containing the output of the process
	// pngs are chunked files.
	constant PNG_HEADER = "\x89PNG\r\n\x1a\n"; // 8 byte standard header
	int count = 0;
	while(data->read(8) == PNG_HEADER) {
		string current_page = PNG_HEADER;
		//werror("data: %O\n", data);
		//werror("data: %O\n", sizeof(data));
		while (array chunk = data->sscanf("%4H%8s")) {// four byte Hollerrith string, followed by 8 byte string
			// The (length-preceded) four byte Hollerrith string might be empty and won't contain all the data.
			// We are chunking by Hollorith string, which is a 4 byte string that contains the length of the chunk.
			// But the 8 bytes following it will contain the rest of the chunk, which includes the CRC (cyclic redundancy check) hash.
			current_page+=sprintf("%4H%s", @chunk);
			if (chunk[0] == "" && has_prefix(chunk[1], "IEND")) break; // break at the end marker
		}
		// could confirm template Id exists in templates table,
		// but we just created it so it should be there
		pages+=({ current_page });
	} // end while data (pages)
	return pages;
}

__async__ string template(Protocols.HTTP.Server.Request req, mapping upload) {

	// if user necessary:
	// mapping user = await(G->G->DB->get_user_details(req->misc->auth->email));
	// string org_name = user->orgs[user->primary_org];

	array pages = await(pdf2png(req->body_raw));

	foreach(pages; int i; string current_page) {
		// https://pike.lysator.liu.se/generated/manual/modref/ex/predef_3A_3A/Image/Image.html#Image
		// object page = Image.PNG.decode(current_page);

		mapping img = Image.PNG._decode(current_page);
		if (img->alpha) {
			// Make a blank image of the same size as the original image
			object blank = Image.Image(img->xsize, img->ysize, 255, 255, 255);
			// Paste original into it, fading based on alpha channel
			img->image = blank->paste_mask(img->image, img->alpha);
		}
		mapping bounds = await(calculate_image_bounds(current_page, img->xsize, img->ysize));
		// Rescale current_page
		object scaled = img->image;
		while(scaled->xsize() > 1000) {
			scaled = scaled->scale(0.5);
			bounds->left /= 2;
			bounds->right /= 2;
			bounds->top /= 2;
			bounds->bottom /= 2;
		}
		// Encode the scaled image
		string scaled_png = Image.PNG.encode(scaled);

		string query = #"
		INSERT INTO template_pages
			(template_id, page_number, page_data,
			pxleft, pxright, pxtop, pxbottom)
		VALUES
			(:template_id, :page_number, :page_data, :left, :right, :top, :bottom)
		";

		mapping bindings = ([
			"template_id":upload->template_id, "page_number":i+1, "page_data":scaled_png,
			]) | bounds; // the pipe (bitwise or) operator is a way to merge two mappings

		mapping results = await(G->G->DB->run_pg_query(query, bindings));
	}

	// Update the template record with the number of pages
	string query = #"
		UPDATE templates
		SET page_count = :page_count
		WHERE id = :template_id
		RETURNING primary_org_id
	";
	mapping bindings = (["template_id":upload->template_id, "page_count":sizeof(pages)]);
	array(mapping) primary_org_ids = await(G->G->DB->run_pg_query(query, bindings));
	G->G->websocket_types["templates"]->send_updates_all(primary_org_ids[0]->primary_org_id + ":");
	return "done";
};

__async__ mapping contract(Protocols.HTTP.Server.Request req, mapping upload) {
	werror("contract upload %O\n", upload);
	object tm = System.Timer();

	array(mapping) rects = await(G->G->DB->run_pg_query(#"
			SELECT x1, y1, x2, y2, template_signatory_id, transition_score, page_number
			FROM audit_rects
			WHERE template_id = :template_id
			ORDER BY id",
		(["template_id": upload->template_id])));

	mapping template_rects = ([]);
	foreach (rects, mapping r) template_rects[r->page_number] += ({r});

	array annotated_pages = ({});

	array pages = await(pdf2png(req->body_raw));

	constant IS_A_SIGNATURE = 75;

	bool confidence = 1;

	foreach(pages; int i; string current_page) {

		if (!template_rects[i+1]) {
			annotated_pages+=({ "data:image/png;base64," + MIME.encode_base64(current_page) });
			continue;
		}

		mapping img = Image.PNG._decode(current_page);

		if (img->alpha) {
			// Make a blank image of the same size as the original image
			object blank = Image.Image(img->xsize, img->ysize, 255, 255, 255);
			// Paste original into it, fading based on alpha channel
			img->image = blank->paste_mask(img->image, img->alpha);
		}

		mapping bounds = await(calculate_image_bounds(current_page, img->xsize, img->ysize));
		werror("[%6.3f] Calculated (expensive) bounds\n", tm->peek());

		object grey = img->image->grey();

		int left = bounds->left;
		int top = bounds->top;
		int right = bounds->right;
		int bottom = bounds->bottom;

		img->image->setcolor(255, 0, 255);
		img->image->line(left, top, right, top);
		img->image->line(right, top, right, bottom);
		img->image->line(right, bottom, left, bottom);
		img->image->line(left, bottom, left, top);
		img->image->line(left, top, right, bottom);
		img->image->line(right, top, left, bottom);
		int page_transition_score = 0;
		int page_calculated_transition_score = 0;

		foreach (template_rects[i+1] || ({}), mapping r) {
			mapping box = calculate_transition_score(r, bounds, grey);

			img->image->setcolor(0, 192, 0, 0);
			img->image->line(box->x1, box->y1, box->x2, box->y1);
			img->image->line(box->x2, box->y1, box->x2, box->y2);
			img->image->line(box->x2, box->y2, box->x1, box->y2);
			img->image->line(box->x1, box->y2, box->x1, box->y1);

			int alpha = limit(16, (box->score - r->transition_score) * 255 / IS_A_SIGNATURE, 255);

			img->image->box(box->x1, box->y1, box->x2, box->y2, 0, 192, 192, 255 - alpha);

			page_transition_score += r->transition_score;
			page_calculated_transition_score += box->score;

			werror("Template Id: %3d Page no: %2d Signatory Id: %2d Transition score: %6d, Calculated transition score: %6d \n", upload->template_id, i+1, r->template_signatory_id || 0, r->transition_score, box->score);
		}
		if (page_calculated_transition_score < page_transition_score) {
			confidence = 0;
		}

		annotated_pages+=({ "data:image/png;base64," + MIME.encode_base64(Image.PNG.encode(img->image)) });

	}
	werror("[%6.3f] Done\n", tm->peek());
	return jsonify((["pages": annotated_pages, "confidence": confidence, "rects": sizeof(rects)]));
}

string prepare_upload(string type, mapping info) {
	if (!this[type]) error("Invalid upload type.\n");
	string id = MIME.encode_base64url(random_string(9));
	pending_uploads[id] = ([ "type":type ]) | info;
	return id;
}

protected void create(string name) {
	::create(name);
	//werror("%O\n", indices(this));
	//werror("%O\n", indices(this_program));
	G->G->prepare_upload = prepare_upload;
}
