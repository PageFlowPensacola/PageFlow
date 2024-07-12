inherit http_endpoint;

string http_request(Protocols.HTTP.Server.Request req) {
	if (!NetUtils.is_local_host(req->get_ip())) return "Not authorized";
	return G->G->kick_python(req->variables->force);
}
