inherit annotated;

Sql.Sql mysqlconn, pgsqlconn;
Concurrent.Promise query_pending;

Concurrent.Future run_my_query(string query, mapping|void bindings) {return run_query(mysqlconn, query, bindings);}
Concurrent.Future run_pg_query(string query, mapping|void bindings) {return run_query(pgsqlconn, query, bindings);}

__async__ array(mapping) run_query(Sql.Sql conn, string query, mapping bindings) {

	// TODO: figure out why promise queries are failing with broken promise error
	//write("Query result: %O\n", await(mysqlconn->promise_query(query))->get());
	//write("%O\n", await(Protocols.HTTP.Promise.do_method("GET", "http://localhost:8002/")));
	//write("Query result: %O\n", mysqlconn->typed_query(query));
	//write("%O\n", mysqlconn->promise_query);
	//write("Waiting for query: %O\n", query[..64]);

	object pending = query_pending;
	object completion = query_pending = Concurrent.Promise();

	if (pending) await(pending->future()); //If there's a queue, put us at the end of it.
	array|zero result;
	mixed ex = catch {
		result = await(conn->promise_query(query, bindings))->get();
		//write ("---the query: %O\n", promise);
		//mixed result = await(promise)->get();

		//write ("---result: %O\n", result);

		if (result) {
			foreach(result, mapping row) {
				// clean out the keys with dots (the table-name qualified keys)
				foreach(indices(row), string key) {
					if (has_value(key, ".")) m_delete(row, key);
				}
			}
		}
		//write("-----processed result\n" );
	};

	//write("------passed catch block\n");
	completion->success(1);
	if (query_pending == completion) query_pending = 0;

	if (ex) throw(ex);


	return result;

}



__async__ array(mapping) get_templates_for_org(int org_id) {

	string query = #"
		SELECT id, name, page_count FROM templates
		WHERE primary_org_id = :org_id
		AND page_count IS NOT NULL
	";

	mapping bindings = (["org_id":org_id]);

	return await(run_pg_query(query, bindings));

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
	array(mapping) template_pages = await(G->G->DB->run_pg_query(#"
			SELECT template_id, page_number, page_data
			FROM template_pages
			WHERE (template_id = :template_id OR :template_id = 0)
			AND (page_number = :page_number OR :page_number = 0)",
		(["template_id": template_id, "page_number": page_number])));

	array(mapping) rects = await(G->G->DB->run_pg_query(#"
			SELECT template_id, x1, y1, x2, y2, page_number, audit_type, template_signatory_id, id
			FROM audit_rects WHERE transition_score = -1
			AND (template_id = :template_id OR :template_id = 0)
			AND (page_number = :page_number OR :page_number = 0)",
		(["template_id": template_id, "page_number": page_number])));

	mapping page_rects = ([]);
	foreach (rects, mapping r) page_rects[r->template_id+":"+r->page_number] += ({r});

	foreach (template_pages, mapping p) {
		mapping img = Image.PNG._decode(p->page_data);
		object grey = img->image->grey();
		foreach(page_rects[p->template_id+":"+p->page_number] || ({}), mapping r) {
			int last = -1, transition_count = 0, pixel_count = 0;
			for (int y = r->y1; y < r->y2; ++y) {
				for (int x = r->x1; x < r->x2; ++x) {
					int cur = grey->getpixel(x * img->xsize / 32767, y * img->ysize / 32767)[0] > 128;
					transition_count += (cur != last);
					last = cur;
					pixel_count++;
				}
			}
			last = -1;
			for (int x = r->x1; x < r->x2; ++x) {
				for (int y = r->y1; y < r->y2; ++y) {
					int cur = grey->getpixel(x * img->xsize / 32767, y * img->ysize / 32767)[0] > 128;
					transition_count += (cur != last);
					last = cur;
				}
			}
			await(G->G->DB->run_pg_query(#"
				UPDATE audit_rects
				SET transition_score = :score
				WHERE id = :id", (["score": transition_count, "id": r->id])));
			werror("Template Id: %d Page no: %d Signatory Id: %d Transitions: %d, Pixel count: %d, Transition score: %d\n", r->template_id, r->page_number, r->template_signatory_id || 0, transition_count, pixel_count, pixel_count/transition_count);
		}
		// Do stuff with page_data and page_rects
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
		pgsqlconn = Sql.Sql(G->G->instance_config->pgsql_connection_string);
		write("%O\n", pgsqlconn);
	}

}
