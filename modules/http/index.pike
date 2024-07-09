inherit http_endpoint;


constant markdown = #"# Signatory Check

## Check files for signatures based on user defined templates.

Use the menu above to manage templates or submit files for analysis.

For more information, reach out to [Mike](mailto:mike@pageflow.com) or [John](mailto:john@pageflow.com).

";


mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render_template(markdown, ([]));
}

protected void create(string name) {
	::create(name);
	G->G->http_endpoints[""] = http_request;
}
