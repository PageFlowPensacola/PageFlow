protected void create (string name) {
	G->G->utils = this;
}

@"Test":
__async__ void test() {
	array(mapping) pages = await((G->G->DB->run_pg_query(#"
		SELECT png_data, template_id, page_number, ocr_result, seq_idx
		FROM uploaded_file_pages
		WHERE file_id = :id AND seq_idx = 2", (["id": 74]))));

	array(mapping) templates = await(G->G->DB->run_pg_query(#"
			SELECT page_data, ocr_result
			FROM template_pages
			WHERE template_id = :template_id
			AND page_number = :page_number",
		(["template_id": pages[0]->template_id, "page_number": pages[0]->page_number])));
	object template = Image.PNG.decode(templates[0]->page_data)->grey();
	object page = Image.PNG.decode(pages[0]->png_data)->grey();
	object pythonstdin = Stdio.File(), pythonstdout = Stdio.File();
	string pythonbuf = "";
	object python = Process.create_process(({"python3", "regress.py"}),
		(["stdin": pythonstdin->pipe(Stdio.PROP_IPC | Stdio.PROP_REVERSE), "stdout": pythonstdout->pipe(Stdio.PROP_IPC)]));

	array template_words = Standards.JSON.decode(templates[0]->ocr_result);
	array page_words = Standards.JSON.decode(pages[0]->ocr_result);
	array pairs = match_arrays(template_words, page_words, 1) {[mapping template, mapping filepage] = __ARGS__;
		return sizeof(template->text) > 1 && template->text == filepage->text && (centroid(template->pos) + centroid(filepage->pos));
	};

	/*
	Above can also be done with explicit lambda:
	array pairs = match_arrays(template_words, page_words, 1, lambda( mixed ...__ARGS__ ) {
		[mapping o, mapping d] = __ARGS__;
		return sizeof(o->text) > 1 && o->text == d->text && (centroid(o->pos) + centroid(d->pos));
	}); */

	mapping long = template_words[0];
	foreach (template_words, mapping w) {
		if (sizeof(w->text) > sizeof(long->text)) long = w;
	}
	foreach (page_words, mapping w) {
		if (sizeof(w->text) > sizeof(long->text)) long = w;
	}
	werror("%O\n", long);
	//Least-squares linear regression. Currently done in Python+Numpy, would it be worth doing in Pike instead?
	pythonstdin->write(Standards.JSON.encode(pairs, 1) + "\n");
	while (!has_value(pythonbuf, '\n')) {
		pythonbuf += pythonstdout->read(1024, 1);
	}
	sscanf(pythonbuf, "%s\n%s", string line, pythonbuf);
	array matrix = Standards.JSON.decode(line);
	constant gutter = 10;
	constant center = 1;
	werror("Matrix: %O\n", matrix);
	Image.Image preview = Image.Image(template->xsize() + gutter + page->xsize(), max(template->ysize(), page->ysize()));
	int origy = center && (preview->ysize() - template->ysize()) / 2;
	int imgx = template->xsize() + gutter;
	int imgy = center && (preview->ysize() - page->ysize()) / 2;
	preview->paste(template, 0, origy);
	preview->paste(page, imgx, imgy);
	//For every matched word pair, draw a connecting line
	foreach (pairs, [int x1, int y1, int x2, int y2]) {
			preview->line(x1, y1 + origy,
				x2 + imgx, y2 + imgy,
				random(256), random(256), random(256));
		}
		Stdio.write_file("preview.png", Image.PNG.encode(preview));
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
