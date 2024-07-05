inherit http_endpoint;

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->session->auth_domain) {
		return (["error": 403]);
	}
	string domain = req->variables->domain;
	if (!has_prefix(domain, req->misc->session->auth_domain)) {
		return (["error": 403]);
	}
	// query the database for the domain
	array(mapping) domains = await(G->G->DB->run_pg_query(#"
		SELECT name
		FROM domains
		WHERE name = :name", (["name":domain])));
	if (!sizeof(domains)) {
		return (["error": 404]);
	}
	req->misc->session->domain = domain;
	return "okay";
}
