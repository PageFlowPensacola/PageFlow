inherit annotated;

Sql.Sql dbconn;


__async__ void run_query(string query, mapping bindings) {

	// TODO: figure out why promise queries are failing with broken promise error
	//write("Query result: %O\n", await(dbconn->promise_query(query))->get());
	//write("%O\n", await(Protocols.HTTP.Promise.do_method("GET", "http://localhost:8002/")));
	//write("Query result: %O\n", dbconn->typed_query(query));

	return dbconn->typed_query(query, bindings);

}


protected void create(string name) {

	::create(name);
	dbconn = Sql.Sql(G->G->instance_config->database->connection_string);

	write("%O\n", dbconn);
	// foo();

}
