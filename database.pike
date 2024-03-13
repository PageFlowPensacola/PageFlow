inherit annotated;

Sql.Sql dbconn;





protected void create(string name) {

	::create(name);
	dbconn = Sql.Sql(G->G->instance_config->database->connection_string);

	string query = "select 1 as one";

	write("%O\n", dbconn);
	write("Query result: %O\n", dbconn->typed_query(query));

}
