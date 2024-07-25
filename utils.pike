protected void create (string name) {
	G->G->utils = this;
}

array match_arrays(array arr1, array arr2, function pred) {
	//Step through the arrays, finding those that match
	//The predicate function should return a truthy value when they match, and these values
	//will be collected into the result.
	int d1, d2; //Denoters for the respective arrays
	array ret = ({ });
	nextmatch: while (d1 < sizeof(arr1) && d2 < sizeof(arr2)) {
		if (mixed match = pred(arr1[d1], arr2[d2])) {
			//Match!
			d1++; d2++;
			ret += ({match});
			continue;
		}
		//Try to advance d1 until we get a match; not too many steps though.
		//The limit is a tweakable - if resynchronization can happen after
		//that many failures, it might be a phantom resync and not actually
		//helpful. A lower number is also faster than a higher one.
		for (int i = 1; i < 10 && d1 + i < sizeof(arr1); ++i) {
			if (mixed match = pred(arr1[d1+i], arr2[d2])) {
				//That'll do!
				d1 += i + 1; d2++;
				ret += ({match});
				continue nextmatch;
			}
		}
		//No match in the next few? Skip one from arr2 and carry on.
		d2++;
	}
	return ret;
}

array centroid(array pos) {
	return ({(pos[0] + pos[2]) / 2, (pos[1] + pos[3]) / 2});
}


@"Test":
__async__ void test() {
	array(mapping) pages = await((G->G->DB->run_pg_query(#"
		SELECT png_data, template_id, page_number, ocr_result, seq_idx
		FROM uploaded_file_pages
		WHERE file_id = :id", (["id": 59]))));
		werror("Page words: %O\n", pages[0]->ocr_result);
	array(mapping) rects = await(G->G->DB->run_pg_query(#"
			SELECT x1, y1, x2, y2,
				audit_type,
				template_signatory_id,
				id, page_data, ocr_result
			FROM audit_rects
			NATURAL JOIN template_pages
			WHERE (template_id = :template_id OR :template_id = 0)
			AND (page_number = :page_number OR :page_number = 0)
			ORDER BY template_id, page_number, id",
		(["template_id": pages[0]->template_id, "page_number": pages[0]->page_number])));
	object template = Image.PNG.decode(rects[0]->page_data)->grey();
	object page = Image.PNG.decode(pages[0]->png_data)->grey();
	object pythonstdin = Stdio.File(), pythonstdout = Stdio.File();
	string pythonbuf = "";
	object python = Process.create_process(({"python3.12", "regress.py"}),
		(["stdin": pythonstdin->pipe(Stdio.PROP_IPC | Stdio.PROP_REVERSE), "stdout": pythonstdout->pipe(Stdio.PROP_IPC)]));

	array template_words = Standards.JSON.decode(rects[0]->ocr_result);
	array page_words = Standards.JSON.decode(pages[0]->ocr_result);
	array pairs = match_arrays(template_words, page_words) {[mapping o, mapping d] = __ARGS__;
		return o->text == d->text && (centroid(o->pos) + centroid(d->pos));
	};
	werror("Pairs: %O\n", pairs);
	//5. Least-squares linear regression. Currently done in Python+Numpy, would it be worth doing in Pike instead?
	pythonstdin->write(Standards.JSON.encode(pairs, 1) + "\n");
	while (!has_value(pythonbuf, '\n')) {
		pythonbuf += pythonstdout->read(1024, 1);
	}
	sscanf(pythonbuf, "%s\n%s", string line, pythonbuf);
	array matrix = Standards.JSON.decode(line);
	werror("Matrix: %O\n", matrix);
	foreach (rects, mapping r) {
		mapping template_score = calculate_transition_score(r, template);
		mapping page_score = calculate_transition_score(r, page, matrix);
		werror("Score %O \n %O \n", template_score, page_score);
	}
}



@"Create a user with email and password":
__async__ void usercreate() {
	[string email, string pwd] = G->G->args[Arg.REST];
	werror("Creating user\n");
	await(G->G->DB->run_query(#"
		INSERT INTO users (email)
		VALUES (:email)",
		(["email": email]))); //bcrypt
}


@"Delete a user":
__async__ void userdelete() {
	[string email] = G->G->args[Arg.REST];
	werror("Deleting user\n");
	await(G->G->DB->run_query(#"
		DELETE FROM user
		WHERE email = :email",
		(["email": email])));
}

@"List all users":
__async__ void userlist() {
	werror("Listing users\n");
	mixed result = await(G->G->DB->run_my_query(#"
		SELECT email
		FROM user"));
	write("Result: %O\n", result);
}

@"Find user by email":
__async__ void userfind() {
	[string email] = G->G->args[Arg.REST];
	werror("Finding user\n");
	mixed result = await(G->G->DB->run_my_query(#"
		SELECT email
		FROM user
		WHERE email = :email",
		(["email": email])));
	write("Result: %O\n", result);
}

@"Domain import":
__async__ void domain_import() {
	werror("Fetching user orgs\n");
	array orgs = await(G->G->DB->run_my_query(#"
		SELECT org_id, display_name, org_type, parent_org_id
		FROM org"));
	write("Orgs: %O\n", orgs);
	werror("Importing domains\n");

	array(mapping) dom = await(G->G->DB->run_pg_query(#"
		SELECT * from domains where legacy_org_id is not null"));
	mapping domains = mkmapping(dom->legacy_org_id, dom);
	write("Domains: %O\n", domains);
	foreach (orgs, mapping org) {
		if (mapping par = !domains[org->org_id] && domains[org->parent_org_id]) {
			write("Parent name %O display name %O\n", par->name, par->display_name);
			write("Org display name %O Org type %O\n", org->display_name, org->org_type);
			write("Enter desired domain string: ");
			string domain = String.trim(Stdio.stdin.gets());
			if (domain == "") {
				continue;
			}
			if (!has_suffix(domain, ".")) {
				domain += ".";
			}
			await(G->G->DB->run_pg_query(#"
			INSERT INTO domains (name, legacy_org_id, display_name)
			VALUES (:domain, :org_id, :display_name)",
			(["domain": par->name + domain, "org_id": org->org_id, "display_name": org->display_name])));
		}
	}
}

@"Audit score":
__async__ void audit_score() {
	await(G->G->DB->recalculate_transition_scores(0, 0));
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
	img->setcolor(@bbox_color);
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

@"Test the classifier":
__async__ void ml() {
	string domain = "com.pageflow.tagtech.dunder-mifflin.";
	function classipy = G->bootstrap("modules/classifier.pike")->classipy;

	werror("Result: %O\n", await(classipy(domain,
	([
		"cmd": "classify",
		"text": "hereby certify that to the best of my knowledge the odometer reading reflects the amount of mileage ni excess of its mechanical limits.",
	]))));
}

@"Update database schema":
__async__ void tables() {
	werror("Creating tables\n");
	await(G->G->DB->create_tables(G->G->args["confirm"]));
}

@"Load a ml_model":
__async__ void load_model() {
	[string domain] = G->G->args[Arg.REST];
	werror("Loading model\n");
	array(mapping) model = await(G->G->DB->run_pg_query(#"
		SELECT ml_model FROM domains WHERE name = :domain",
		(["domain": domain])));
	if(!sizeof(model)) {
		werror("No domain found for %O\n", domain);
		return;
	}
	if(!model[0]->ml_model) {
		werror("No model found for %O\n", domain);
		return;
	}
	Process.exec("python", "-i", "-c", "import pickle, base64, river; model=pickle.loads(base64.b64decode('" + model[0]->ml_model + "'))");
}

@"Cleanup pagerefs for a model":
__async__ void cleanup() {
	// TODO perhaps eventually do a complete retrain on the model,
	// as currently, this just prevents it from returning removed templates.
	[string domain] = G->G->args[Arg.REST];
	function classipy = G->bootstrap("modules/classifier.pike")->classipy;
	mapping result = await(classipy(domain,
	([
		"cmd": "pagerefs",
	])));
	array templateids = (result->pagerefs[*] / ":")[*][0];
	if (!sizeof(templateids)) {
		werror("No templates found for %O\n", domain);
		return;
	}

	array(mapping) going = await(G->G->DB->run_pg_query("values " + sprintf("(%s)", templateids[*]) * ", " + " except select id from templates"));
	multiset gone = (multiset) going->column1;
	werror("Result: %O\n", gone);
	foreach(result->pagerefs, string pageref) {
		sscanf(pageref, "%d:", int template);
		if (gone[template]) {
			werror("Template %d is gone\n", template);
			await(classipy(domain,
				([
					"cmd": "untrain",
					"pageref_prefix": ((int) pageref) + ":",
				])));
		}
	}
}

@"End all python processes":
__async__ void kickpy() {
	string force = G->G->args->force ? "?force=1" : "";
	object result = await(Protocols.HTTP.Promise.get_url("http://localhost:8002/kickpy" + force));
	write(result->data);
}

@"Model audit":
__async__ void model_audit() {
	// This WILL NOT tell us if there's a template which model hasn't been trained on
	// or if there is a page missing out of it.
	function classipy = G->bootstrap("modules/classifier.pike")->classipy;

	array(mapping) domains = await(G->G->DB->run_pg_query(#"
		SELECT name
		FROM domains
		WHERE ml_model IS NOT NULL
		ORDER BY name"));

	array(mapping) all_templates = await(G->G->DB->run_pg_query(#"
		SELECT *
		FROM templates"));

		mapping templates = mkmapping(all_templates->id, all_templates);
	foreach(domains, mapping domain) {
		werror("Auditing model %O\n", domain->name);
		mapping result = await(classipy(domain->name,
			([
				"cmd": "pagerefs",
			])));
		foreach(result->pagerefs, string pageref) {
			sscanf(pageref, "%d:%d", int template, int page);
			mapping t = templates[template];
			if (!t) {
				werror("\t\e[1;31m%s: Template not found\e[0m\n", pageref);
				continue;
			}
			if (page > t->page_count) {
				werror("\t\e[1;31m%s: Page out of bounds\e[0m\n", pageref);
				continue;
			}
			if (!has_prefix(domain->name, t->domain)) {
				werror("\t\e[1;31m%s: Domain mismatch %s\e[0m\n", pageref, t->domain);
				continue;
			}
			werror("\t%s: %s\n", pageref, t->name);
		}
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
