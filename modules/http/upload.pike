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

	mapping results = await(run_promise(({"convert", "-density", "72", "-depth", "8", "-quality", "85", "-", "png:-"}),
	(["stdin": pdf])));
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

		string query = #"
		INSERT INTO template_pages
			(template_id, page_number, page_data)
		VALUES
			(:template_id, :page_number, :page_data)
		";

		mapping bindings = (
			["template_id":upload->template_id, "page_number":i+1, "page_data":current_page]
		);

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

__async__ string contract(Protocols.HTTP.Server.Request req, mapping upload) {
	werror("contract upload %O\n", upload);

	array(mapping) rects = await(G->G->DB->run_pg_query(#"
			SELECT x1, y1, x2, y2, template_signatory_id, transition_score, page_number
			FROM audit_rects
			WHERE template_id = :template_id
			ORDER BY id",
		(["template_id": upload->template_id])));

	mapping template_rects = ([]);
	foreach (rects, mapping r) template_rects[r->page_number] += ({r});

	array pages = await(pdf2png(req->body_raw));

	foreach(pages; int i; string current_page) {

		mapping img = Image.PNG._decode(current_page);
		mapping bounds = await(calculate_image_bounds(current_page, img->xsize, img->ysize));
		object grey = img->image->grey();

		foreach (template_rects[i+1] || ({}), mapping r) {
			int calculated_transition_score = calculate_transition_score(r, bounds, grey);
			int pixel_count = (r->x2 - r->x1) * (r->y2 - r->y1);

			werror("Template Id: %3d Page no: %2d Signatory Id: %2d Pixel count: %9d, Transition score: %6d, Calculated transition score: %6d \n", upload->template_id, i+1, r->template_signatory_id || 0, pixel_count, r->transition_score, calculated_transition_score);
		}

	}
	return "contract";
}

string prepare_upload(string type, mapping info) {\
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
