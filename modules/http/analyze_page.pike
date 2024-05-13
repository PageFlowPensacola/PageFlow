inherit http_endpoint;


mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
  werror("#### Analyze: %O\n", req->misc->json);
  return jsonify(([ "template_id": 76, "page": 1]));
}
