inherit http_endpoint;

Crypto.SHA256.HMAC jwt_hmac = Crypto.SHA256.HMAC(G->G->instance_config->jwt_signing_key);

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {

	write("LOGIN %O\n", req->misc->json);

	mapping|zero result_set = await(G->G->DB->load_password_for_email(req->misc->json->email));
	write("%O\n", req->misc->json->password);
	write("%O\n", result_set->password);

	if(!result_set || !Crypto.Password.verify(req->misc->json->password, result_set->password) || !result_set->active) {
		return (["error": 400, "type":"text/plain", "data":"Password validation failed."]);
	}

	string jwt = Web.encode_jwt(jwt_hmac, (["email": req->misc->json->email, "iss":"https://gotagtech.com"]));

	return jsonify((["token": jwt]));


 };
