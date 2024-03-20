inherit annotated;

Sql.Sql dbconn;
Concurrent.Promise query_pending;

__async__ array(mapping) run_query(string query, mapping bindings) {

	// TODO: figure out why promise queries are failing with broken promise error
	//write("Query result: %O\n", await(dbconn->promise_query(query))->get());
	//write("%O\n", await(Protocols.HTTP.Promise.do_method("GET", "http://localhost:8002/")));
	//write("Query result: %O\n", dbconn->typed_query(query));
	write("%O\n", dbconn->promise_query);
	write("Waiting for query: %O\n", query[..64]);

	object pending = query_pending;
	object completion = query_pending = Concurrent.Promise();

	if (pending) await(pending->future()); //If there's a queue, put us at the end of it.
	array|zero result;
	mixed ex = catch {
		result = await(dbconn->promise_query(query, bindings))->get();
		//write ("---the query: %O\n", promise);
		//mixed result = await(promise)->get();

		write ("---result: %O\n", result);

		if (result) {
			foreach(result, mapping row) {
				// clean out the keys with dots (the table-name qualified keys)
				foreach(indices(row), string key) {
					if (has_value(key, ".")) m_delete(row, key);
				}
			}
		}
		write("-----processed result\n" );
	};

	write("------passed catch block\n");
	completion->success(1);
	if (query_pending == completion) query_pending = 0;
	write("Query complete: %O\n", result);

	if (ex) throw(ex);


	return result;

}



__async__ array(mapping) get_templates_for_org(int org_id) {

	string query = #"
		SELECT * FROM page_type t
		JOIN page_type_group g ON t.page_type_id = g.page_type_id
		WHERE t.page_template_url IS NOT NULL and t.org_id = :org_id
		ORDER by t.page_type_id
	";

	mapping bindings = (["org_id":org_id]);

	return await(run_query(query, bindings));

}

__async__ array(mapping) get_template_pages(int org_id, int page_group_id) {
	// TODO: simplify this query
	string query = #"
		SELECT ts.name as signatory_name, ar.* FROM template_signatory ts
		JOIN audit_rect ar
		JOIN page_type pt
		JOIN page_type_group pg
		ON pg.page_type_id = pt.page_type_id
		WHERE pg.page_group_id = :page_group_id
	";

	mapping bindings = (["org_id":org_id, "page_group_id":page_group_id]);

	return await(run_query(query, bindings));

}

__async__ mapping|zero load_password_for_email(string email) {

	string query = #"
		select u.password
		, u.active
		from user u
		where u.email = :email
		and u.deleted = 0;
	";

	mapping bindings = (["email":email]);

	array results = await(run_query(query, bindings));
	// write("From database: %O\n", results);
	if (sizeof(results)) {
		return results[0];
	}
}

__async__ mapping|zero get_user_details(string email) {

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
 AND u.deleted = 0;
";

	mapping bindings = (["email":email]);

	array results = await(run_query(query, bindings);
	// write("From database: %O\n", results);
	if (sizeof(results)) {
		return results[0];
	}
}


protected void create(string name) {

	G->G->DB = this;

	::create(name);
	if (G->G->instance_config->database->connection_string) {
		werror("DB Connecting\n");
		dbconn = Sql.Sql(G->G->instance_config->database->connection_string);
		write("%O\n", dbconn);
	}

}
