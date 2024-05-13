inherit http_endpoint;


constant markdown = #"# Signatory Check

## Check files for signatures based on user defined templates.

";


mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render_template(markdown, ([]));
}

protected void create(string name) {
	::create(name);
	G->G->http_endpoints[""] = http_request;
}
