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
		({"convert", "-density", "150", "-", "png:-"}),
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
		mapping json = ([
			"template_id": upload->template_id,
			"page": i+1,
			"data": ocr_data, // hocr data
		]);
		foreach (domains, mapping domain) {
			werror("Classifying for %s\n", domain->name);
			classipy(
				domain->name,
				([
					"cmd": "train",
					"text": ocr_data * " ",
					"pageref": upload->template_id + ":" + (i+1),
				]));
		}

		werror("\t[%6.3f] Calculated (expensive) bounds\n", tm->peek());
		// Rescale current_page
		object scaled = img->image;
		int left = min(@ocr_data->pos[0]);
		int top = min(@ocr_data->pos[1]);
		int right = max(@ocr_data->pos[2]);
		int bottom = max(@ocr_data->pos[3]);
		while(scaled->xsize() > 1000) {
			scaled = scaled->scale(0.5);
			left /= 2; top /= 2; right /= 2; bottom /= 2;
		}
		werror("\t[%6.3f] Scaled\n", tm->peek());
		// Encode the scaled image
		string scaled_png = Image.PNG.encode(scaled);
		werror("[%6.3f] Encoded\n", tm->peek());

		mapping results = await(G->G->DB->run_pg_query(#"
		INSERT INTO template_pages
			(template_id, page_number, page_data,
			pxleft, pxright, pxtop, pxbottom)
		VALUES
			(:template_id, :page_number, :page_data, :left, :right, :top, :bottom)
		", ([
			"template_id":upload->template_id, "page_number":i+1, "page_data":scaled_png,
			// To be replaced when using Rosuav imgmap code
			"left":min(@ocr_data->pos[0]),
			"right":max(@ocr_data->pos[2]),
			"top":min(@ocr_data->pos[1]),
			"bottom":max(@ocr_data->pos[3])
			])));
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

__async__ mapping contract(Protocols.HTTP.Server.Request req, mapping upload) {
	werror("contract upload %O\n", upload);

	object analysis = G->G->websocket_types->analysis;

	object tm = System.Timer();

	// This will store template pages (rects, etc)
	mapping templates = ([]);

	mapping template_pages = ([]);

	string fileid = upload->file_id;

	array rects = ({});

	// This will store annotated page images
	array file_page_details = ({});

	mapping timings = ([]);

	G->G->DB->run_pg_query(#"
		UPDATE uploaded_files
		SET pdf_data = :pdf_data
		WHERE id = :fileid", (["pdf_data": upload->body_raw, "fileid": fileid]))
		->then() {
			analysis->send_updates_all(fileid);
		};

	array file_pages = await(pdf2png(req->body_raw));
	timings["pdf2png"] = tm->get();

	// update uploaded files with page_count
	G->G->DB->run_pg_query(#"
		UPDATE uploaded_files
		SET page_count = :page_count
		WHERE id = :file_id", (["page_count": sizeof(file_pages), "file_id": fileid]));

	constant IS_A_SIGNATURE = 75;

	bool confidence = 1;

	int file_page_count = sizeof(file_pages);

	analysis->send_updates_all(fileid);

	string domain = await(find_closest_domain_with_model(req->misc->session->domain));

	foreach(file_pages; int i; string current_page) {

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

		array ocr_results = await(analyze_page(current_page, img->xsize, img->ysize));

		timings["Tesseract"] += tm->get();
		mapping json = ([
			"data": ocr_results,
		]);

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
					"text": ocr_results->text * " ",
				])));
		timings["classify_page"] += tm->get();

		string pageref; float confidence = 0.0;

		array pagerefs = indices(classification->results);
		array confs = values(classification->results);
		sort(confs, pagerefs);
		// werror("%{%8s: %.2f\n%}", Array.transpose(({pagerefs, confs})));
		foreach(classification->results; string pgref; float conf) {
			if (conf > confidence) {
				pageref = pgref;
				confidence = conf;
			}
		}
		if (!pageref || confidence < 0.5) {
			werror("No classification found for page %d %O \n", i+1, classification);

			G->G->DB->run_pg_query(#"
			INSERT INTO uploaded_file_pages
				(file_id, seq_idx, png_data, ocr_result)
			VALUES
				(:file_id, :seq_idx, :png_data, :ocr_result)",
				(["file_id": fileid, "seq_idx": i+1, "png_data": current_page, "ocr_result": Standards.JSON.encode(ocr_results)]));

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
				timings["analyze page"] += tm->get();
				continue;
		}
		//werror("Confidence level for page %d: %f\n", i+1, confidence);
		array(mapping) matchingTemplates = await(G->G->DB->run_pg_query(#"
			SELECT name, page_count
			FROM templates
			WHERE id = :id", (["id": (int) pageref]))); // (int) will disregard colon and anything after it.

		string templateName = "Unknown";

		if(!sizeof(matchingTemplates)) {
			continue;
		}

		template_pages[pageref] = 1;
		werror("######Template pages: %O\n", template_pages);
		templateName = matchingTemplates[0]->name; // assume it has a name at this point

		sscanf(pageref, "%d:%d", int template_id, int page_number);
		G->G->DB->run_pg_query(#"
			INSERT INTO uploaded_file_pages
				(file_id, seq_idx, png_data, template_id, page_number, ocr_result)
			VALUES
				(:file_id, :seq_idx, :png_data, :template_id, :page_number, :ocr_result)",
				(["file_id": fileid, "seq_idx": i+1, "png_data": current_page, "template_id": template_id, "page_number": page_number, "ocr_result": Standards.JSON.encode(ocr_results)]));
		// Send back a message so we can fetch the annotated templates

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
/*
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
		foreach (templates[template_id][page_number] || ({}), mapping r) {
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
			}); */

			/* werror(#"RECT INFO: Template Id: %3d
			Template Page no: %2d
			File Page no: %2d
			Signatory Id: %2d
			Transition score: %6d,
			Calculated transition score: %6d \n", template_id, page_number, i+1,
			r->template_signatory_id || 0, r->transition_score, box->score);
		} // End loop templates[template_id][page_number] (audit_rects) loop.
		if (page_calculated_transition_score < page_transition_score) {
			confidence = 0.0;
		}*/
		/* if (!template_pages[pageref]) {
			werror("### Template %d, page %d not yet accounted for (%s)\n", template_id, page_number, pageref);
			file_page_details+=({
				([
					"annotated_img": "data:image/png;base64," + MIME.encode_base64(Image.PNG.encode(img->image)),
					"file_page_no": i+1,
					"fields": field_results,
					"template_id": template_id,
					"template_name": templateName,
					"page_transition_score": page_transition_score,
					"page_calculated_transition_score": page_calculated_transition_score,
					"document_page": page_number,
				])
			});
		} else {
			werror("### Template %d, page %d already accounted for (%s)\n", template_id, page_number, pageref);
			annotated_contract_pages+=({
				([
					"annotated_img": "data:image/png;base64," + MIME.encode_base64(Image.PNG.encode(img->image)),
					"file_page_no": i+1,
					"fields": field_results,
					"template_id": template_id,
					"template_name": templateName,
					"page_transition_score": page_transition_score,
					"page_calculated_transition_score": page_calculated_transition_score,
					"error": "Duplicate document page.",
					"document_page": page_number,
					"template_id": 1<<40,
					"template_name": "Duplicate document page.",
				])
			});
		}  */

		timings["analyze page"] += tm->get();
	} // End of foreach document pages loop.
	werror("Timings %O\n", timings);
	mapping annotated_pages_by_template = ([]);
	foreach(file_page_details, mapping page) {
		annotated_pages_by_template[(string) page->template_id] += ({page});
	}
	upload->conn->sock->send_text(Standards.JSON.encode(
			(["cmd": "upload_status",
			"step": sprintf("Matched %d pages to templates", file_page_count),
		])));
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
