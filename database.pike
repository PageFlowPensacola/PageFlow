inherit annotated;

Sql.Sql dbconn;


__async__ array(mapping) run_query(string query, mapping bindings) {

	// TODO: figure out why promise queries are failing with broken promise error
	//write("Query result: %O\n", await(dbconn->promise_query(query))->get());
	//write("%O\n", await(Protocols.HTTP.Promise.do_method("GET", "http://localhost:8002/")));
	//write("Query result: %O\n", dbconn->typed_query(query));

	array|zero result = dbconn->typed_query(query, bindings);
	if (!result) return result;
	foreach(result, mapping row) {
		// clean out the keys with dots (the table-name qualified keys)
		foreach(indices(row), string key) {
			if (has_value(key, ".")) m_delete(row, key);
		}
	}
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
		select pg.page_group_id
		, pg.org_id
		, pg.page_group_name
	  , pg.page_group_type
		, pt.page_type_id
	    , pt.page_type_name
	    , pt.page_template_url
	    , ts.template_signatory_id
	    , ts.name signatory_name
	    , ar.name rect_name
	    , ar.audit_rect_id
	    , ar.page_type_id rect_page_id
	    , ar.audit_type
	    , ar.template_signatory_id rect_signatory_id
	    , ar.x1
	    , ar.x2
	    , ar.y1
	    , ar.y2
		from page_group pg
		join page_type_group ptg on (ptg.page_group_id = pg.page_group_id)
		left join page_type pt on (ptg.page_type_id = pt.page_type_id)
		left join template_signatory ts on (pg.page_group_id = ts.page_group_id)
		left join audit_rect ar on (pt.page_type_id = ar.page_type_id)
		where pg.page_group_id = :page_group_id
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


protected void create(string name) {

	G->G->DB = this;

	::create(name);
	if (G->G->instance_config->database->connection_string) {
		werror("DB Connecting\n");
		dbconn = Sql.Sql(G->G->instance_config->database->connection_string);
		write("%O\n", dbconn);
	}

}
