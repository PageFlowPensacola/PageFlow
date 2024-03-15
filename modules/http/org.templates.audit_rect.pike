inherit restful_endpoint;

mapping(string:mixed)|string|Concurrent.Future handle_list(Protocols.HTTP.Server.Request req, string org, string template) {
	werror("handle_list: %O %O %O\n", req, org, template);
	return "Not implemented handle_list";
};
mapping(string:mixed)|string|Concurrent.Future handle_detail(Protocols.HTTP.Server.Request req, string org, string template, string audit_rect) { };
mapping(string:mixed)|string|Concurrent.Future handle_create(Protocols.HTTP.Server.Request req, string org, string template) { };
mapping(string:mixed)|string|Concurrent.Future handle_update(Protocols.HTTP.Server.Request req, string org, string template, string audit_rect) { };
mapping(string:mixed)|string|Concurrent.Future handle_delete(Protocols.HTTP.Server.Request req, string org, string template, string audit_rect) { };
