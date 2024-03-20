Concurrent.Future main() {return test();}


__async__ void test() {
	Sql.Sql dbconn = Sql.Sql("mysql://deal_audit_root:c--GSyJf2aFTEUC!#$sz@mysql-test.gotagtech.com:3306/deal_audit");
	werror("Query result: %O\n", dbconn->typed_query("select 1 from dual"));
	mixed q = dbconn->promise_query("select 1 from dual");
	werror("Promise: %O\n", q);
	mixed result = await(q);
	werror("Result: %O\n", result);
	werror("Rows: %O\n", result->get());

}
