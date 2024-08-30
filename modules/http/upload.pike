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
	// On low quality scans/results we may be able to rescue with items like:
		// increase density
		// normalize
		// deskew
	// May be better to always run at 300 density.
	mapping results = await(run_promise(
		({"convert", "-density", "300", "-", "png:-"}),
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
	werror("template upload %O\n", sizeof(req->body_raw));
	// if user necessary:
	// mapping user = await(G->G->DB->get_user_details(req->misc->auth->email));
	// string org_name = user->orgs[user->primary_org];
	string document_domain = req->misc->session->domain;

	array pages = await(pdf2png(req->body_raw));

	// hand ocr_data off to model
	// get the model for current domain from the db
	// Fetch all models for this domain and its subdomains
	// and train on all of them.
	array(mapping) domains = await(G->G->DB->run_pg_query(#"
		SELECT name
		FROM domains
		WHERE name LIKE :domain
		AND ml_model IS NOT NULL
		ORDER BY LENGTH(name)",
		(["domain": req->misc->session->domain + "%"])));

	werror("domains: %O\n", domains);

	if (!sizeof(domains) || domains[0]->name != req->misc->session->domain) {
		// copy upstream model into current domain before making the change.
		await(G->G->DB->run_pg_query(#"
		UPDATE domains SET ml_model =
			(SELECT ml_model
			FROM domains
			WHERE :domain LIKE name || '%'
			AND ml_model IS NOT NULL
			ORDER BY LENGTH(name) DESC LIMIT 1)
		WHERE name = :domain",
		(["domain": req->misc->session->domain])));

		domains += ({(["name": req->misc->session->domain])});
		werror("Copying for %s %O\n", req->misc->session->domain, domains);
	}
foreach(pages; int i; string current_page) {
		// https://pike.lysator.liu.se/generated/manual/modref/ex/predef_3A_3A/Image/Image.html#Image
		// object page = Image.PNG.decode(current_page);

		// new timer
		object tm = System.Timer();
		mapping img = Image.PNG._decode(current_page);
		if (img->alpha) {
			// Make a blank image of the same size as the original image
			object blank = Image.Image(img->xsize, img->ysize, 255, 255, 255);
			// Paste original into it, fading based on alpha channel
			img->image = blank->paste_mask(img->image, img->alpha);
		}
		werror("\t[%6.3f] Calculating bounds\n", tm->peek());
		array ocr_data = await(analyze_page(current_page, img->xsize, img->ysize));
		foreach (domains, mapping domain) {
			werror("Classifying for %s\n", domain->name);
			classipy(
				domain->name,
				([
					"cmd": "train",
					"text": ocr_data->text * " ",
					"pageref": upload->template_id + ":" + (i+1),
				]));
		}
		werror("\t[%6.3f] Calculated (expensive) bounds\n", tm->peek());
		int left = min(@ocr_data->pos[*][0]);
		int top = min(@ocr_data->pos[*][1]);
		int right = max(@ocr_data->pos[*][2]);
		int bottom = max(@ocr_data->pos[*][3]);

		mapping results = await(G->G->DB->run_pg_query(#"
		INSERT INTO template_pages
			(template_id, page_number, page_data, ocr_result,
			pxleft, pxright, pxtop, pxbottom)
		VALUES
			(:template_id, :page_number, :page_data, :ocr_result, :left, :right, :top, :bottom)
		", ([
			"template_id":upload->template_id, "page_number":i+1, "page_data":Image.PNG.encode(img->image),
			"ocr_result": Standards.JSON.encode(ocr_data),
			// To be replaced when using Rosuav imgmap code
			"left": left, "right": right, "top": top, "bottom": bottom
			])));
	Stdio.write_file(sprintf("ocr_data%d.json", i+1), Standards.JSON.encode(ocr_data, 6));
	} // end iterate over pages

	// Update the template record with the number of pages
	await(G->G->DB->run_pg_query(#"
		UPDATE templates
		SET page_count = :page_count
		WHERE id = :template_id
	", (["template_id":upload->template_id, "page_count":sizeof(pages)])));
	G->G->websocket_types["templates"]->send_updates_all(document_domain);
	return "done";
};

__async__ string find_closest_domain_with_model(string domain) {
	return await(G->G->DB->run_pg_query(#"
	SELECT name
	FROM domains
	WHERE :domain LIKE name || '%'
	AND ml_model IS NOT NULL
	ORDER BY LENGTH(name) DESC LIMIT 1",
	(["domain": domain])))[0]->name;
}

__async__ array parse_page(string current_page, string domain, int i) {

	mapping img = Image.PNG._decode(current_page);
	if (img->alpha) {
		// Make a blank image of the same size as the original image
		object blank = Image.Image(img->xsize, img->ysize, 255, 255, 255);
		// Paste original into it, fading based on alpha channel
		img->image = blank->paste_mask(img->image, img->alpha);
	}

	/* upload->conn->sock->send_text(Standards.JSON.encode(
		(["cmd": "upload_status",
		"count": file_page_count,
		"pages": ({(["number": i+1, "fields": ({})])}),
		"current_page": i+1,
		"step": "Analyzing page " + (i+1) + " of " + file_page_count + " pages.",
		]))); */

	array page_ocr = await(analyze_page(current_page, img->xsize, img->ysize));

	/* upload->conn->sock->send_text(Standards.JSON.encode(
		(["cmd": "upload_status",
		"count": file_page_count,
		"pages": ({(["number": i+1, "fields": ({})])}),
		"current_page": i+1,
		"step": "Classifying page " + (i+1) + " of " + file_page_count + " pages.",
	]))); */

	mapping classification = await(classipy(
			domain,
			([
				"cmd": "classify",
				"text": page_ocr->text * " ",
			])));

	string pageref; float confidence = 0.0;

	array pagerefs = indices(classification->results);
	array confs = values(classification->results);
	sort(confs, pagerefs);
	werror("%{%8s: %.2f\n%}", Array.transpose(({pagerefs, confs})));
	foreach(classification->results; string pgref; float conf) {
		if (conf > confidence) {
			pageref = pgref;
			confidence = conf;
		}
	}
	string templateName = "Unknown";
	if (! (int) pageref || confidence < 0.5) {
		werror("No classification found for page %d %O \n", i+1, classification);
		return ({page_ocr, 0, 0 ,0, templateName});
	}
	//werror("Confidence level for page %d: %f\n", i+1, confidence);
	array(mapping) matchingTemplates = await(G->G->DB->run_pg_query(#"
		SELECT name, page_count
		FROM templates
		WHERE id = :id", (["id": (int) pageref]))); // (int) will disregard colon and anything after it.

	if (!sizeof(matchingTemplates)) {
		werror("WARNING!!!!!!!: ML has template we don't have: %d. Fix the ML.\n", (int) pageref);
		return ({page_ocr, 0, 0 ,0, templateName}); // Should never happen.
	}
	templateName = matchingTemplates[0]->name; // assume it has a name at this point

	sscanf(pageref, "%d:%d", int template_id, int page_number);

	array template_words = Standards.JSON.decode(await(G->G->DB->run_pg_query(#"
		SELECT ocr_result
		FROM template_pages
		WHERE template_id = :template_id
		AND page_number = :page_number",
		(["template_id": template_id, "page_number": page_number])))[0]->ocr_result);

	array pairs = match_arrays(template_words, page_ocr, 0) {[mapping o, mapping d] = __ARGS__;
		return o->text == d->text && (centroid(o->pos) + centroid(d->pos));
	};

	if (sizeof(pairs) < 10) {
		werror("Not enough matching words for page %d\n", i+1);
		return ({page_ocr, 0, 0 ,0, templateName});
	}
	// mutate pairs
	Array.shuffle(pairs);
	array testpairs = pairs[..sizeof(pairs) / 10]; // 10% of the pairs
	array trainpairs = pairs[(sizeof(pairs) / 10) + 1..]; // remaining 90% of the pairs

	//Least-squares linear regression. Currently done in Python+Numpy, would it be worth doing in Pike instead?
	array matrix = await(regression(trainpairs));
	float error = 0.0;
	foreach (testpairs, [int x1, int y1, int x2, int y2]) {
		float x = matrix[0] * x1 + matrix[1] * y1 + matrix[2];
		float y = matrix[3] * x1 + matrix[4] * y1 + matrix[5];
		error += (x - x2) ** 2 + (y - y2) ** 2;
	}
	if (error / sizeof(testpairs) > img->xsize / 10) {
		// Could compare Pythagorean distance to image size, but this is close enough.
		werror("Regression error too high for page %d\n", i+1);
		werror("Error: %f\n", error / sizeof(testpairs));
		werror("Image size: %d %d\n", img->xsize, img->ysize);

		return ({page_ocr, 0, 0 ,0, templateName});
	}
	//Least-squares linear regression. Currently done in Python+Numpy, would it be worth doing in Pike instead?
	return ({page_ocr, matrix, template_id, page_number, templateName}); // the matrix
}

__async__ mapping contract(Protocols.HTTP.Server.Request req, mapping upload) {
	werror("contract upload %O\n", upload);

	object analysis = G->G->websocket_types->analysis;


	object tm = System.Timer();

	// This will store template pages (rects, etc)
	mapping templates = ([]);

	mapping template_pages = ([]);

	string fileid = upload->file_id;

	analysis->send_updates_all(fileid);

	array rects = ({});

	// This will store annotated page images
	array file_page_details = ({});

	mapping timings = ([]);

	array file_pages = await(pdf2png(req->body_raw));
	timings["pdf2png"] = tm->get();

	// update uploaded files with page_count
	G->G->DB->run_pg_query(#"
		UPDATE uploaded_files
		SET page_count = :page_count, pdf_data = :pdf_data
		WHERE id = :file_id", (["pdf_data": req->body_raw, "page_count": sizeof(file_pages), "file_id": fileid]))
		->then() {
			analysis->send_updates_all(fileid);
		};

	bool confidence = 1;

	int file_page_count = sizeof(file_pages);

	analysis->send_updates_all(fileid);

	string domain = await(find_closest_domain_with_model(req->misc->session->domain));

	foreach(file_pages; int i; string current_page) {

		analysis->send_updates_all(fileid);
		[array page_ocr, array|zero matrix, int template_id, int page_number, string templateName] = await(parse_page(current_page, domain, i+1));
		if (!matrix) {
			G->G->DB->run_pg_query(#"
			INSERT INTO uploaded_file_pages
				(file_id, seq_idx, png_data, ocr_result)
			VALUES
				(:file_id, :seq_idx, :png_data, :ocr_result)",
				(["file_id": fileid, "seq_idx": i+1, "png_data": current_page, "ocr_result": Standards.JSON.encode(page_ocr)]));

		/* upload->conn->sock->send_text(Standards.JSON.encode(
			(["cmd": "upload_status",
			"count": file_page_count,
			"pages": ({(["number": i+1, "fields": ({})])}),
			"current_page": i+1,
			"step": sprintf("No document template found for file page %d", i+1),
		]))); */

			file_page_details+=({(["error": "No document template found for page.",
			"fields": ({}),
			"file_page_no": i+1,
			"img":"data:image/png;base64," + MIME.encode_base64(current_page),
			"template_id": 1<<41,
			"template_name": "No template found",
			])});
			continue;
		}

		// Since not awaiting, won't report errors!
		G->G->DB->run_pg_query(#"
			INSERT INTO uploaded_file_pages
				(file_id, seq_idx, png_data, template_id, page_number, ocr_result, transform)
			VALUES
				(:file_id, :seq_idx, :png_data, :template_id, :page_number, :ocr_result, :transform)",
				(["file_id": fileid, "seq_idx": i+1, "png_data": current_page, "template_id": template_id, "page_number": page_number, "ocr_result": Standards.JSON.encode(page_ocr), "transform": Standards.JSON.encode(matrix)]));

		if (!templates[template_id]) templates[template_id] = ([]);
		if (!templates[template_id][page_number]) { // if not a duplicate
			// TODO stop getting template name here as getting separately anyway.
			rects += templates[template_id][page_number] = await(G->G->DB->run_pg_query(#"
				SELECT x1, y1, x2, y2, template_signatory_id, transition_score, ts.name as name, t.name as Template
				FROM audit_rects r
				JOIN template_signatories ts ON ts.id = r.template_signatory_id
				JOIN templates t ON t.id = ts.template_id
				WHERE r.template_id = :template_id
				AND page_number = :page_number
				ORDER BY r.id",
			(["template_id": template_id, "page_number": page_number])));
		}

		if (!sizeof(templates[template_id][page_number])) {
			werror("No rects found for template %d, page %d\n", template_id, page_number);
			file_page_details+=({([
				"fields": ({}),
				"file_page_no": i+1,
				"img":"data:image/png;base64," + MIME.encode_base64(current_page),
				"template_id": template_id,
				"template_name": templateName,
			])});
			timings["analyze page"] += tm->get();
			continue;
		}

		timings["analyze page"] += tm->get();
	} // End of foreach document pages loop.
	werror("Timings %O\n", timings);
	mapping annotated_pages_by_template = ([]);
	foreach(file_page_details, mapping page) {
		annotated_pages_by_template[(string) page->template_id] += ({page});
	}
	/* upload->conn->sock->send_text(Standards.JSON.encode(
			(["cmd": "upload_status",
			"step": sprintf("Matched %d pages to templates", file_page_count),
		]))); */
	werror("Before %O\n", tm->get());
		await(G->G->DB->run_pg_query(#"
			SELECT 1"));
	werror("After %O\n", tm->get());
	analysis->send_updates_all(fileid);
	return jsonify((["documents": annotated_pages_by_template, "confidence": confidence]));
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
