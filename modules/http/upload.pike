inherit http_endpoint;

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	werror("req: %O\n", typeof(req->request_type));
		if (req->request_type != "POST") {
			return ([ "error": 405 ]);
		}
		//werror("req: %O\n", req);

		// if user necessary:
		// mapping user = await(G->G->DB->get_user_details(req->misc->auth->email));
		// string org_name = user->orgs[user->primary_org];


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
	mapping results = await(run_promise(({"convert", "-density", "300", "-depth", "8", "-quality", "85", "-", "png:-"}),
	(["stdin": req->body_raw])));
	//werror("results: %O\n", indices(results));
	werror("input file size: %O, %O\n", sizeof(results->stdout), sizeof(req->body_raw));
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
		// https://pike.lysator.liu.se/generated/manual/modref/ex/predef_3A_3A/Image/Image.html#Image
		object page = Image.PNG.decode(current_page);

		// could confirm template Id exists in templates table,
		// but we just created it so it should be there

		string query = #"
		INSERT INTO template_pages
			(template_id, page_number, page_data)
		VALUES
			(:template_id, :page_number, :page_data)
		";

		mapping bindings = (
			["template_id":req->variables->template_id, "page_number":++count, "page_data":current_page]
		);

		mapping results = await(G->G->DB->run_pg_query(query, bindings));
		werror("results: %O\n", results);
		// TODO support specifying the org
		/* mapping s3 = await(run_promise(({"aws", "s3", "cp", "-", sprintf("s3://%s/%d/templatepage2.png", G->G->instance_config->aws->pdf_bucket_name, user->primary_org), }),
			(["stdin": current_page,
				"env": getenv() | ([
				"AWS_ACCESS_KEY_ID": G->G->instance_config->aws->key_id,
				"AWS_SECRET_ACCESS_KEY": G->G->instance_config->aws->secret,
				"AWS_DEFAULT_REGION": G->G->instance_config->aws->region
			])])));
			werror("s3: %O\n", s3); */
	} // end while data (pages)
	return sprintf("%d pages uploaded\n", count);
};
