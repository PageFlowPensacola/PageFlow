inherit restful_endpoint;

__async__ mapping(string:mixed)|string handle_list(Protocols.HTTP.Server.Request req, string org, string template) {
	//werror("handle_list: %O %O %O\n", req, org, template);
	array(mapping) templates = await(G->G->DB->get_templates_for_org(org));
	//werror("%O\n", templates);
	return jsonify(templates);
};

mapping(string:mixed)|string|Concurrent.Future handle_detail(Protocols.HTTP.Server.Request req, string org, string template, string audit_rect) {
	//werror("handle_list: %O %O %O\n", req, org, template);
};

__async__ mapping(string:mixed)|string|Concurrent.Future handle_create(Protocols.HTTP.Server.Request req, string org, string template) {

	werror("handle_list: %O %O\n", org, template);
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
	werror("input file size: %O\n", sizeof(results->stdout));
	// https://pike.lysator.liu.se/generated/manual/modref/ex/predef_3A_3A/_Stdio/Buffer.html#Buffer
	Stdio.Buffer data = Stdio.Buffer(results->stdout);
	// stdout will be a string containing the output of the process
	// pngs are chunked files.
	constant PNG_HEADER = "\x89PNG\r\n\x1a\n"; // 8 byte standard header
	while(data->read(8) == PNG_HEADER) {
		string current_page = PNG_HEADER;
		//werror("data: %O\n", data);
		//werror("data: %O\n", sizeof(data));
		while (array chunk = data->sscanf("%4H%8s")) {// four byte Hollerrith string, followed by 8 byte string
			// The four byte Hollerrith string might be empty and won't contain all the data.
			// But the 8 bytes following it will contain the rest of the chunk, which includes the CRC (cyclic redundancy check)
			current_page+=sprintf("%4H%s", @chunk);
			if (chunk[0] == "" && has_prefix(chunk[1], "IEND")) break; // break at the end marker
		}
		// https://pike.lysator.liu.se/generated/manual/modref/ex/predef_3A_3A/Image/Image.html#Image
		object page = Image.PNG.decode(current_page);
		werror("Page info %O\n", page);
	}
};
mapping(string:mixed)|string|Concurrent.Future handle_update(Protocols.HTTP.Server.Request req, string org, string template, string audit_rect) { };
mapping(string:mixed)|string|Concurrent.Future handle_delete(Protocols.HTTP.Server.Request req, string org, string template, string audit_rect) { };
