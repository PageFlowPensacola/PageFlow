
__async__ void main() {
	mapping instance_config = Standards.JSON.decode_utf8(Stdio.read_file("instance-config.json"));
	object conn = Sql.Sql(instance_config->pgsql_connection_string);
	werror("start\n");
	await(conn->promise_query("begin"))->get();
	catch (await(conn->promise_query("ALTER TABLE asdf9992 ADD id INT"))->get());
	await(conn->promise_query("rollback"))->get();
	werror("done\n");
}
