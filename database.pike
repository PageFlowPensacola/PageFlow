inherit annotated;

object mysqlconn, pgsqlconn;
Concurrent.Promise query_pending;

Concurrent.Future run_my_query(string|array query, mapping|void bindings) {return run_query(mysqlconn, query, bindings);}
//Concurrent.Future run_pg_query(string|array query, mapping|void bindings) {return run_query(pgsqlconn, query, bindings);}

// Every domain and its children are visible to its owner
// * Objects belong to a domain and all of its subdomains
	// - documents, templates, ML model
	// - when a user creates and object they can choose to put it at any level
	//	 between the session domain and the user domain
	// – when you create a template at a particular level, if a model does
	//		not exist at that level, it will be created by copying the nearest parent.
	//		so users don't need to think about the models. They will self manage.
// * Users belong to a domain
  // - users have control of all objects in their domain and its subdomains
	// - however that means that there could be multiple subtrees of
	//	 documents that are not visible to each other
// * Sessions belong in a domain
	// - meaning that if you are the owner of com.pageflow.dealership.automobile
	//  your current session might be com.pageflow.dealership.automobile.tagtech.sansing.toyota.
	// - at any given time you are always able to see anything in the
	//	 linear parentage of your current session's domain
	//	 so we only need to worry about the current session's domain at a time.
	// - Session implementation may not be specifically as browser sessions
	// - You could switch manually to a different (sub) domain eg .sansing.honda.
	// - If your current session is .sansing. you can't see anything in .sansing.toyota
	//   except for in some operations (like search) that don't use the standard visibility rules.
	//   eg you wouldn't see templates from .sansing.toyota in the template list
// * Visibility is usually defined by one thing:
//  - the domain of the object has to be a prefix of the domain of the session.
//  - however some operations such as document searches may span subdomains of the session domain.
mapping tables = ([
	"domains": ({
		"name text PRIMARY KEY", // eg com.pageflow.dealership.automotive.tagtech.sansing.toyota.
		"ml_model BYTEA",
		"legacy_org_id int", // TODO make unique, maybe.
		"display_name text",
	}),
	"users": ({
		"user_id SERIAL PRIMARY KEY",
		"email varchar NOT NULL",
		"domain text NOT NULL REFERENCES domains ON DELETE RESTRICT",
		"created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()",
	}),
	"template_packages": ({
		"id SERIAL PRIMARY KEY",
		"name text NOT NULL",
		"created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()",
		"domain text NOT NULL REFERENCES domains ON DELETE RESTRICT",
	}),
	"rules": ({
		"id SERIAL PRIMARY KEY",
		"name text NOT NULL",
		"created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()",
		"rule jsonb NOT NULL",
	}),
	"package_rules": ({
		"package_id int NOT NULL REFERENCES template_packages ON DELETE CASCADE",
		"rule_id int NOT NULL REFERENCES rules ON DELETE CASCADE",
		" PRIMARY KEY (package_id, rule_id)",
	}),
	// "user_credentials": ({TODO: Implement this}),
	"templates": ({
		"id SERIAL PRIMARY KEY",
		"name varchar NOT NULL",
		"created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()",
		"domain text NOT NULL REFERENCES domains ON DELETE RESTRICT",
		"page_count smallint",
	}),
	"template_pages": ({
		"template_id int NOT NULL REFERENCES templates ON DELETE CASCADE",
		"page_number smallint NOT NULL",
		"page_data BYTEA NOT NULL",
		"ocr_result jsonb NOT NULL",
		"pxleft smallint",
		"pxtop smallint",
		"pxright smallint",
		"pxbottom smallint",
		" PRIMARY KEY (template_id, page_number)",
	}),
	"template_signatories": ({
		"id BIGSERIAL PRIMARY KEY",
		"name varchar NOT NULL",
		"template_id int NOT NULL REFERENCES templates ON DELETE CASCADE",
	}),
	"audit_rects": ({
		"id BIGSERIAL PRIMARY KEY",
		"audit_type varchar NOT NULL", //NOT IN USE initials, signature, date
		"template_id int NOT NULL REFERENCES templates ON DELETE CASCADE",
		"page_number smallint NOT NULL",
		"x1 smallint NOT NULL",
		"y1 smallint NOT NULL",
		"x2 smallint NOT NULL",
		"y2 smallint NOT NULL",
		"name varchar DEFAULT NULL",
		"optional boolean NOT NULL DEFAULT FALSE",
		"transition_score int NOT NULL DEFAULT -1", // to compare against signature
		"template_signatory_id int REFERENCES template_signatories ON DELETE CASCADE",
	}),
	// Exact uploaded file to be analyzed (digital dignatures will be lost in PNGs)
	// For each page we need the pageref it was detected as eg: 102:1, 102:2, etc...
	// Thinking we shouldn't store
	//
	"uploaded_files": ({
		"id SERIAL PRIMARY KEY",
		"filename text NOT NULL",
		"page_count smallint",
		"domain text NOT NULL REFERENCES domains",
		"created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()",
		"pdf_data BYTEA",
		"template_package_id int REFERENCES template_packages ON DELETE RESTRICT",
	}),
	"uploaded_file_pages": ({
		"file_id int NOT NULL REFERENCES uploaded_files ON DELETE CASCADE",
		"seq_idx smallint NOT NULL", // file sequence index
		"png_data BYTEA NOT NULL",
		"template_id int REFERENCES templates ON DELETE RESTRICT",
		"page_number smallint", // document page number from classification
		"transform jsonb NOT NULL default '[1,0,0,0,1,0]'", // six coefficients: x, y and constant for each of x and y
		"ocr_result jsonb",
		" PRIMARY KEY (file_id, seq_idx)",
	}),
	"page_rects": ({
		"file_id int NOT NULL REFERENCES uploaded_files ON DELETE CASCADE",
		"seq_idx smallint NOT NULL",
		"audit_rect_id int NOT NULL REFERENCES audit_rects ON DELETE CASCADE",
		"difference int NOT NULL DEFAULT 0",
		"content text NOT NULL DEFAULT ''", // not currently in use
		" PRIMARY KEY (file_id, seq_idx, audit_rect_id)",
	}),
]);

array(mapping) parse_mysql_result(array(mapping) result) {
	if (result) {
		foreach(result, mapping row) {
			// clean out the keys with dots (the table-name qualified keys)
			foreach(indices(row), string key) {
				if (has_value(key, ".")) m_delete(row, key);
			}
		}
	}
	return result;
}

/**
	@param sql may be an array which includes queries and callbacks.
	eg:

	({"select id, seq where blah blah",
	callback_to_figure_out_changes,
	"update set seq = :cur where id=:other"
	"update set seq = :new where id = :this"
	})
*/
__async__ array(mapping) run_query(object conn, string|array sql, mapping|void bindings) {

	// TODO: figure out why promise queries are failing with broken promise error
	//write("Query result: %O\n", await(mysqlconn->promise_query(query))->get());
	//write("%O\n", await(Protocols.HTTP.Promise.do_method("GET", "http://localhost:8002/")));
	//write("Query result: %O\n", mysqlconn->typed_query(query));
	//write("%O\n", mysqlconn->promise_query);
	//write("Waiting for query: %O\n", query[..64]);

	// If sql is an array will perform them in a transaction
	// eg: a process sequence change: 1,2,3,4: 1,2,4,3
	// Currently only support in/decremental updates

	object pending = query_pending;
	object completion = query_pending = Concurrent.Promise();

	if (pending) await(pending->future()); //If there's a queue, put us at the end of it.
	mixed ret, ex;
	while (1) {
		if (arrayp(sql)) {
			ret = ({ });
			ex = catch {await(conn->promise_query("begin"))->get();};
			if (!ex) foreach (sql, string|function q) {
				//A null entry in the array of queries is ignored, and will not have a null return value to correspond.
				if (ex = q && catch {
					if (functionp(q)) q(ret, bindings); //q is allowed to mutate its bindings.
					else ret += ({parse_mysql_result(await(conn->promise_query(q, bindings))->get())});
				}) break;
			}
			werror("Transaction result: %O\n", ret);

			// TODO Something critically wrong. Failing to rollback after an exception.
			//Ignore errors from rolling back - the exception that gets raised will have come from
			//the actual query (or possibly the BEGIN), not from rolling back.
			// NOTE run with `pike -DPG_DEBUG app.pike --exec=tables to debug`
			if (ex) {
				mixed ex2 = catch {
					conn->resync();
					object rollback = conn->promise_query("rollback");
					werror("Exception: %O\n", rollback);
					object query = await(rollback);
					werror("Rollback: %O\n", query);
					mixed rollback_result = query->get();
					werror("Rollback result: %O\n", rollback_result);
				};
				werror("Rollback exception: %O\n", ex2);
			}
			//But for committing, things get trickier. Technically an exception here leaves the
			//transaction in an uncertain state, but I'm going to just raise the error. It is
			//possible that the transaction DID complete, but we can't be sure.
			else ex = catch {await(conn->promise_query("commit"))->get();};
		}
		else {
			//Implicit transaction is fine here; this is also suitable for transactionless
			//queries (of which there are VERY few).
			ex = catch {ret = parse_mysql_result(await(conn->promise_query(sql, bindings))->get());};
		}
		// Trying to diagnose the server gone away errors.
		// Once one occurrs note the type and see if we can catch that
		// specifically. It does not seem to be an array.
		// Once detected, these can be handled by reconnecting
		// and retrying (continue rather than break).
		// Also, if the error is not an array and not "server gone away",
		// it may be worth wrapping it so backtraces can be retrieved.
		if (ex && mysqlconn->errno() == 2006) { // "MySQL server has gone away"
			werror("Mysql DB Reconnecting\n");
			mysqlconn = conn = Sql.Sql(G->G->instance_config->mysql_connection_string);
		} else break;
	}

	//write("------passed catch block\n");
	completion->success(1);
	if (query_pending == completion) query_pending = 0;
	if (objectp(ex) && ex->status_command_complete) throw(ex->status_command_complete);
	if (ex) throw(ex);

	return ret;

}


__async__ array run_pg_query(string|array sql, mapping|void bindings) {
	if (arrayp(sql)) {
		array ret = ({ });
		await(pgsqlconn->transaction(__async__ lambda(function query) {
			foreach (sql, string q) {
				//A null entry in the array of queries is ignored, and will not have a null return value to correspond.
				if (q) ret += ({await(query(q, bindings))});
			}
		}));
		return ret;
	}
	else return await(pgsqlconn->query(sql, bindings));
}

__async__ mapping|zero insert_template_page(int page_type_id, string name, string url, int org_id) {

	string query = #"
		INSERT INTO audit_rect (page_type_id, name, url, org_id)
		VALUES (:page_type_id, :name, :url, :org_id)
	";

	mapping bindings = (["page_type_id":page_type_id, "name":name, "url":url, "org_id":org_id]);

	array results = await(run_my_query(query, bindings));

	return results[0];
}

__async__ mapping|zero insert_template_signatory(int page_type_id, string name, string email, int org_id) {

	string query = #"
		INSERT INTO template_signatory (page_type_id, name, email, org_id)
		VALUES (:page_type_id, :name, :email, :org_id)
	";

	mapping bindings = (["page_type_id":page_type_id, "name":name, "email":email, "org_id":org_id]);

	array results = await(run_my_query(query, bindings));

	return results[0];
}

__async__ mapping|zero insert_audit_rect(int page_type_id, string name, string url, int org_id) {

	string query = #"
		INSERT INTO audit_rect (page_type_id, name, url, org_id)
		VALUES (:page_type_id, :name, :url, :org_id)
	";

	mapping bindings = (["page_type_id":page_type_id, "name":name, "url":url, "org_id":org_id]);

	array results = await(run_my_query(query, bindings));

	return results[0];
}

__async__ mapping|zero get_user_details(string email) {

	if (!email) return 0;
	string query = #"
		SELECT u.user_id
 , u.first_name
 , u.last_name
 , u.org_id as primary_org
 , uo.org_id
 , o.display_name
 FROM user u
 JOIN user_org uo ON u.user_id = uo.user_id
 JOIN org o ON o.org_id = uo.org_id
 WHERE u.email = :email
 AND u.deleted = 0
";

	mapping bindings = (["email":email]);

	mapping user = ([]);

	array results;

	mixed ex = catch {
		results = await(run_my_query(query, bindings));
	};

	if (ex) {
		write("Error: %t\n%O\n", ex, ex);
		error("Error: %t\n%O\n", ex, ex);
		return 0;
	}

	if (sizeof(results) == 0) return 0;

	user = results[0];
	user["email"] = email;
	user["orgs"] = ([]);

	foreach(results, mapping row) {
		user["orgs"][(string)row["org_id"]] = row["display_name"];
	}
	m_delete(user, "org_id");
	m_delete(user, "display_name");
	return user;
}


__async__ void recalculate_transition_scores(int template_id, int page_number) {
	// If template_id is 0, all templates are considered
	// If page_number is 0, all pages are considered

	array(mapping) rects = await(run_pg_query(#"
			SELECT template_id, x1, y1, x2, y2,
				page_number,
				audit_type,
				template_signatory_id,
				id, page_data,
				pxleft, pxright, pxtop, pxbottom
			FROM audit_rects
			NATURAL JOIN template_pages
			WHERE transition_score = -1
			AND (template_id = :template_id OR :template_id = 0)
			AND (page_number = :page_number OR :page_number = 0)
			ORDER BY template_id, page_number, id",
		(["template_id": template_id, "page_number": page_number])));

	mapping img;
	object grey;
	string last_page_data;
	mapping bounds;
	foreach (rects, mapping r) {
		// Pike uses string interning here, so this is an efficient comparison
		if (r->page_data != last_page_data) {
			bounds = (["left": r->pxleft, "right": r->pxright, "top": r->pxtop, "bottom": r->pxbottom ]);
			img = Image.PNG._decode(r->page_data);
			grey = img->image->grey();
			last_page_data = r->page_data;
		}

		int transition_score = calculate_transition_score(r, grey)->score;
		await(G->G->DB->run_pg_query(#"
			UPDATE audit_rects
			SET transition_score = :score
			WHERE id = :id", (["score": transition_score, "id": r->id])));
		werror("Template Id: %3d Page no: %2d Signatory Id: %2d Transition score: %6d\n", r->template_id, r->page_number, r->template_signatory_id || 0, transition_score);
	}
}


//Attempt to create all tables and alter them as needed to have all columns
__async__ void create_tables(int confirm) {
	werror("create_tables\n");
	array cols = await(run_pg_query("select table_name, column_name from information_schema.columns where table_schema = 'public' order by table_name, ordinal_position"));
	array stmts = ({ });
	mapping(string:array(string)) havecols = ([]);
	foreach (cols, mapping col) havecols[col->table_name] += ({col->column_name});
	foreach (tables; string tbname; array cols) {
		if (!havecols[tbname]) {
			//The table doesn't exist. Create it from scratch.
			array extras = filter(cols, has_suffix, ";");
			stmts += ({
				sprintf("create table %s (%s)", tbname, (cols - extras) * ", "),
			}) + extras;
			continue;
		}
		//If we have columns that aren't in the table's definition,
		//drop them. If the converse, add them. There is no provision
		//here for altering columns.
		string alter = "";
		multiset sparecols = (multiset)havecols[tbname];
		foreach (cols, string col) {
			if (has_suffix(col, ";") || has_prefix(col, " ")) continue;
			sscanf(col, "%s ", string colname);
			if (sparecols[colname]) sparecols[colname] = 0;
			else alter += ", add " + col;
		}
		//If anything hasn't been removed from havecols, it should be dropped.
		foreach (sparecols; string colname;) alter += ", drop " + colname;
		if (alter != "") stmts += ({"alter table " + tbname + alter[1..]}); //There'll be a leading comma
		else write("Table %s unchanged\n", tbname);
	}
	if (sizeof(stmts)) {
		werror("Updating db %O\n", stmts);
		if (confirm) await(run_pg_query(stmts));
		else {
			werror("Run with --confirm to apply changes.\n");
		}
	}
}

protected void create(string name) {

	G->G->DB = this;

	::create(name);
	if (G->G->instance_config->mysql_connection_string) {
		werror("Mysql DB Connecting\n");
		mysqlconn = Sql.Sql(G->G->instance_config->mysql_connection_string);
		write("%O\n", mysqlconn);
	}
	if (G->G->instance_config->pgsql_connection_string) {
		werror("Postgres DB Connecting\n");
		//pgsqlconn = Sql.Sql(G->G->instance_config->pgsql_connection_string);
		// ATM using the Stillebot connection approach.
		pgsqlconn = SSLDatabase(G->G->instance_config->pgsql_connection_string);
		write("%O\n", pgsqlconn);
	}

}
