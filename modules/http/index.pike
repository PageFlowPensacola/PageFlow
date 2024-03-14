inherit http_endpoint;

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {


	write("%O\n", req->misc->auth);
	return "Hello, World!";


 };

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints[""] = http_request;
}
