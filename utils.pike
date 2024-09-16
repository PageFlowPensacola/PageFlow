protected void create (string name) {
	G->G->utils = this;
}

@"Test":
__async__ void test() {
	werror("Test\n");
	mixed ex = catch { await(G->G->DB->run_my_query("SELECT 1+")); };
	werror("Caught: %s\n", describe_backtrace(ex));
	werror("ERRNO: %O\n", G->G->DB->mysqlconn->errno());
	werror("SQL State: %O\n", G->G->DB->mysqlconn->sqlstate());
}

@"Reset Models":
__async__ void reset_models() {
	if (!G->G->args->confirm) {
		werror("Delete all models and templates? \n Confirm with --confirm\n");
		return;
	}
	werror("Clearing domain models.\n");
	await(G->G->DB->run_pg_query("UPDATE domains SET ml_model = NULL"));
	werror("Truncating upload pages and templates.\n");
	await(G->G->DB->run_pg_query("truncate uploaded_file_pages cascade;"));
	await(G->G->DB->run_pg_query("truncate uploaded_files cascade;"));
	await(G->G->DB->run_pg_query("truncate templates cascade;"));
	werror("Reseeding parent domain model.\n");
	await(G->G->utils->seed());
}

@"Match HOCR words":
__async__ void matchhocr() {
	/*
	Can also redirect stderr to stdout then pipe into less:
	pike app.pike --exec=matchhocr --file=107 --seqidx=3 --template=156 --page=1 2>&1 | less
	*/
	array(mapping) templates = await(G->G->DB->run_pg_query(#"
		SELECT ocr_result
		FROM template_pages
		WHERE template_id = :template_id
		AND page_number = :page_number",
		(["template_id": G->G->args->template, "page_number": G->G->args->page])));
	array(mapping) pages = await(G->G->DB->run_pg_query(#"
		SELECT ocr_result
		FROM uploaded_file_pages
		WHERE file_id = :file_id
		AND seq_idx = :seq_idx",
		(["file_id": G->G->args->file, "seq_idx": G->G->args->seqidx])));
	array pages_ocr = Standards.JSON.decode(pages[0]->ocr_result);
	array pairs = match_arrays(Standards.JSON.decode(templates[0]->ocr_result), pages_ocr, 1) {[mapping o, mapping d] = __ARGS__;
		return o->text == d->text && o->text;
	};
	werror("Pairs: %O\n", pairs);
}

@"Annotate":
__async__ void annotate() {
	if (sizeof(G->G->args[Arg.REST]) < 1) { werror("Usage: pike app --exec=annotate [--template ID, --page NUM] FILEID SEQIDX\n"); return; }

	function regression = G->bootstrap("modules/regress.pike")->regression;
	int seq_idx = 1;
	if (sizeof(G->G->args[Arg.REST]) > 1) seq_idx = G->G->args[Arg.REST][1];
	array(mapping) pages = await((G->G->DB->run_pg_query(#"
		SELECT png_data, template_id, page_number, ocr_result, seq_idx
		FROM uploaded_file_pages
		WHERE file_id = :id AND seq_idx = :seq_idx", (["id": G->G->args[Arg.REST][0], "seq_idx": seq_idx]))));

	array(mapping) templates = await(G->G->DB->run_pg_query(#"
			SELECT page_data, ocr_result
			FROM template_pages
			WHERE template_id = :template_id
			AND page_number = :page_number",
		(["template_id": G->G->args->template || pages[0]->template_id, "page_number": G->G->args->page || pages[0]->page_number])));
	object template = Image.PNG.decode(templates[0]->page_data)->grey();
	object page = Image.PNG.decode(pages[0]->png_data)->grey();

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

	if (sizeof(pairs) < 10) {
		werror("Not enough matches\n");
		return;
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
		//werror("Expected x: %f, Actual x: %d\n", x, x2);
		//werror("Expected y: %f, Actual y: %d\n", y, y2);
		error += (x - x2) ** 2 + (y - y2) ** 2;
	}
	werror("Average error per point: %f\n", (error / sizeof(testpairs)) ** 0.5); //  ** 0.5 is square root
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
	/*
	Add or modify text collection and array index to test various inputs

	Can also redirect stderr to stdout then pipe into less:
	pike app.pike --exec=matchhocr --file=107 --seqidx=3 2>&1 | less
	*/
	string domain = "com.pageflow.tagtech.";
	function classipy = G->bootstrap("modules/classifier.pike")->classipy;

	string text = ({
		"Marathon to Waterloo",
		" STATE OF FLORIDA DEPARTMENT OF HIGHWAY SAFETY AND MOTOR VEHICLES - DIVISION OF MOTOR VEHICLES NEN. KIRKMAN BUILDING - TALLAHASSEE. FL 32399-0610 APPLICATION FOR CERTIFICATE OF TITLE WITH/WITHOUT REGISTRATION TRANSFER VEHICLE Type; (C] oFF-sicHway venicte [[] motor venice [_] mosite Home [] vessec ano NOTE: When joint ownership, please indicate if â\200\234orâ\200\235 or â\200\234andâ\200\235 to be shown on title when issued. if neither box Is checked, the will be with â\200\234and.â\200\235 W applicable: [_] Lite Estate/Remainder Person [_] Tenancy By the Entiraty â\200\224 [_] With Rights of Survivorship Owneâ\200\231s County of Residence: 00 Commercial Sponge C Commercial Shrimp Recip. [] Commercial Charter [] Commercial Other (1 Commercial Shrimp Non-Recip. Commercial Oyster Federally Documented Vessel, Attach Copy of Coast Guard Release From Documentation Form; or Applicable Boxe: | | | | [J Di # and Sex and Date of Birth [_] DMV Account # ELT customer [_] If Lienholder authorizes the Department to send the motor vehide or mobile home title to the owner, check box and countersign: (Does not apply to vessels). if box is not checked, title will be mailed to the first lienholder. (Signature of Lienhoider's Representative) | if OWNERSHIP HAS TRANSFERRED, HOW AND WHEN WAS THE VEHICLE, MOBILE HOME, OR VESSEL ACQUIRED? WARNING: Federal and State law requires that you state the mileage in connection with an application for a Certificate of Title, Failure to co OF providing a false statement may resuit in fines or imprisonment. | STATE ",
		"ODOMETER DISCLOSURE STATEMENT Federal law (and State law, if applicable) requires that you state the mileage upon transfer of ownership of a vehicle. Failure to complete an odometer disclosure statement or providing a false statement may result in fines and/or imprisonment. I state that the odometer (of the vehicle described below) now reads (no tenths) miles and to the best of my knowledge that it reflects the actual mileage of the vehicle described below, unless one of the following statements is checked. (1 (1)! hereby certify that to the best of my knowledge the odometer reading reflects the amount of mileage in excess of its mechanical limits. C1] (2)! hereby certify that the odometer reading is NOT the actual mileage. WARNING - ODOMETER DISCREPANCY. VEHICLE IDENTIFICATION BODY TYPE MODEL STOCK NUMBER TRANSFERORÃ¢\200\231S (SELLER) INFORMATION TRANSFEROR'S PRINTED NAME (SELLER) VEHICLE ID NUMBER TRANSFEROR'S STREET ADDRESS wor: we AUTHORIZED TRANSFEROR'S SIGNATURE (SELLER) SIGNATURE DATE STATEMENT SIGNED | PRINTED NAME OF PERSON SIGNING TRANSFEREEÃ¢\200\231S (BUYER) INFORMATION TRANSFEREE'S PRINTED NAME (BUYER) TRANSFEREE'S STREET ADDRESS RECEIPT OF COPY ACKNOWLEDGED BY TRANSFEREE (BUYER) TRANSFEREE'S SIGNATURE-BUYER DATE @IGNED PRINTED NAME OF PERSON SIGNING x Laer REORDER FROM: gallagher promotional products, inc. Ã\202Â¢ in Ortando (407) 788-0818 + Outside Orlando (800) 367-8458 Rev. 4497 hem #14460 Ady @, es",
	})[1];

	if(G->G->args->file) {
		array(mapping) pages = await(G->G->DB->run_pg_query(#"
		SELECT ocr_result
		FROM uploaded_file_pages
		WHERE file_id = :file_id
		AND seq_idx = :seq_idx",
		(["file_id": G->G->args->file, "seq_idx": G->G->args->seqidx])));
		text = Standards.JSON.decode(pages[0]->ocr_result)->text * " ";
	}
	// warm the proc
	await(classipy(domain,
		([
			"cmd": "classify",
			"text": "",
		])));

	array(mapping) templates = await(G->G->DB->run_pg_query(#"
		SELECT ocr_result FROM template_pages
		JOIN templates ON template_pages.template_id = templates.id
		WHERE :domain LIKE domain || '%'
		AND page_count IS NOT NULL",
		(["domain": domain])));

	multiset domain_template_words = (multiset) Array.uniq((Standards.JSON.decode(templates->ocr_result[*]) * ({}))->text);
	werror(sizeof(text / " ") + " words\n");
	text = filter(text / " ", domain_template_words) * " ";
	werror(sizeof(text / " ") + " words\n");

	System.Timer tm = System.Timer();
	mapping classification = await(classipy(domain,
	([
		"cmd": "classify",
		"text": text,
	])));
	float overhead = tm->get() - classification->elapsed;
	werror("Classification took %f seconds. \n Overhead: %f\n", classification->elapsed, overhead);
	array pagerefs = indices(classification->results);
	array confs = values(classification->results);
	sort(confs, pagerefs);
	werror("%{%8s: %.2f\n%}", Array.transpose(({pagerefs, confs})));
}

@"ML Tire Kick":
__async__ void mltk() {
	/*

	*/
	if (!G->G->args->file || !G->G->args->seqidx) {
		werror("Usage: pike app --exec=mltk --file=FILEID --seqidx=SEQIDX\n"); return;
	}

	string domain = "com.pageflow.tagtech.";
	function classipy = G->bootstrap("modules/classifier.pike")->classipy;
	function regression = G->bootstrap("modules/regress.pike")->regression;

	string text;

	array(mapping) pages = await(G->G->DB->run_pg_query(#"
	SELECT ocr_result
	FROM uploaded_file_pages
	WHERE file_id = :file_id
	AND seq_idx = :seq_idx",
	(["file_id": G->G->args->file, "seq_idx": G->G->args->seqidx])));
	text = Standards.JSON.decode(pages[0]->ocr_result)->text * " ";

	System.Timer tm = System.Timer();

	int page = 0;
	foreach (get_dir("seedcontent"), string fn) {
		werror("Peek at Seeding %O %f\n", fn, tm->peek());
		foreach (Stdio.read_file("seedcontent/"+fn) / "\f", string text) { // split on form feed
			await(classipy("", ([
				"cmd": "train",
				"text": Stdio.read_file("seedcontent/shining.txt"),
				"pageref": "0:" + (++page),
			])));
			werror("Trained %O\n", page);
			//break;
		}
		//break;
	}

	array(mapping) templates = await(G->G->DB->run_pg_query(#"
		SELECT ocr_result, template_id, page_number FROM template_pages
		JOIN templates ON template_pages.template_id = templates.id
		WHERE :domain LIKE domain || '%'
		AND page_count IS NOT NULL",
		(["domain": domain])));

	foreach(templates, mapping template) {
		werror("Peek at %O %f\n", template->template_id, tm->peek());
		string doc = Standards.JSON.decode(template->ocr_result)->text * " ";
		await(classipy("",
			([
				"cmd": "train",
				"text": doc,
				"pageref": sprintf("%d:%d", template->template_id, template->page_number),
			])));
	}
	werror("Training took %f seconds\n", tm->get());

	mapping classification = await(classipy("",
	([
		"cmd": "classify",
		"text": text,
	])));

	float overhead = tm->get() - classification->elapsed;
	werror("Classification took %f seconds. \n Overhead: %f\n", classification->elapsed, overhead);

	array pagerefs = indices(classification->results);
	array confs = values(classification->results);

	sort(confs, pagerefs);

	werror("%{%8s: %.2f\n%}", Array.transpose(({pagerefs, confs})));
	if (confs[-1] < 0.8) {
		werror("No match\n");
		return;
	}
	sscanf(pagerefs[-1], "%d:%d", int template_id, int page_number);

	array template_words = Standards.JSON.decode(await(G->G->DB->run_pg_query(#"
		SELECT ocr_result
		FROM template_pages
		WHERE template_id = :template_id
		AND page_number = :page_number",
		(["template_id": template_id, "page_number": page_number])))[0]->ocr_result);


	array pairs = match_arrays(template_words, Standards.JSON.decode(pages[0]->ocr_result), 0) {[mapping o, mapping d] = __ARGS__;
		return o->text == d->text && (centroid(o->pos) + centroid(d->pos));
	};

	werror("Pairs: %O\n", pairs);

	if (sizeof(pairs) < 10) {
		werror("Not enough matching words for page %d\n");
		return;
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
		//werror("%4d,%4d -> %4d,%4d or %4.0f,%4.0f err %O\n", x1, y1, x2, y2, x, y, (x - x2) ** 2 + (y - y2) ** 2);
		error += (x - x2) ** 2 + (y - y2) ** 2;
	}
	werror("Regression error: %O\n", error);
}

@"Rebuild Models":
 __async__ void rebuild_models() {
	/*
	It is entirely possible that retraining as it retrains in a different
	order than the original training, that the models will be different.
	*/
	if (!G->G->args->confirm) {
		werror("Rebuild all models? \n Confirm with --confirm\n");
		return;
	}
	function classipy = G->bootstrap("modules/classifier.pike")->classipy;
	werror("Clearing domain models\n");
	await(G->G->DB->run_pg_query("UPDATE domains SET ml_model = NULL"));

	werror("Seeding parent domain model\n");
	int page = 0;
	foreach (get_dir("seedcontent"), string fn) {
		werror("Seeding %O\n", fn);
		foreach (Stdio.read_file("seedcontent/"+fn) / "\f", string text) { // split on form feed
			await(classipy("com.pageflow.", ([
				"cmd": "train",
				"text": text,
				"pageref": "0:" + (++page),
			])));
			werror("Trained %O\n", page);
		}
	}

	werror("Fetching template pages\n");
	array(mapping) templates = await(G->G->DB->run_pg_query(#"
		SELECT ocr_result, template_id, page_number, name, domain FROM template_pages
		JOIN templates ON template_pages.template_id = templates.id
		WHERE domain LIKE 'com.pageflow.%'
		AND page_count IS NOT NULL
		ORDER BY length(domain) - length(replace(domain, '.', '')), page_number, template_id"));
	/*
	Deliberately illogical ordering above to:
		1. Always train a parent model before its children
		2. Train different models at the same time to (eventually) effectively parallelize
		The idea will be that we are interspersing at this stage.
	*/
	multiset domains = (<"com.pageflow.">);

	// TODO this in one big transaction

	foreach(templates, mapping template) {
		if (!domains[template->domain]) {
			werror("Seeding %O\n", template->domain);
			domains[template->domain] = 1;
			// replicate the parent model down.
			await(G->G->DB->run_pg_query(#"
			UPDATE domains SET ml_model =
				(SELECT ml_model
				FROM domains
				WHERE :domain LIKE name || '%'
				AND ml_model IS NOT NULL
				ORDER BY LENGTH(name) DESC LIMIT 1)
			WHERE name = :domain",
			(["domain": template->domain])));
			werror("Classifying for %s\n", template->domain);
			await(classipy(
				template->domain,
				([
					"cmd": "train",
					"text": Standards.JSON.decode(template->ocr_result)->text * " ",
					"pageref": template->template_id + ":" + template->page_number,
				])));
		}
	}
	werror("Congratulations, you have rebuilt the models\n");

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
	werror("Model found%O\n", sizeof(model[0]->ml_model));
	Stdio.write_file("/tmp/model", model[0]->ml_model);
	Process.exec("python", "-i", "-c", "import pickle, base64, river; model=pickle.loads(base64.b64decode(open('/tmp/model').read()));");
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
			if (!template) continue;
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
