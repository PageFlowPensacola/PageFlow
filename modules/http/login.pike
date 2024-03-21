inherit http_endpoint;

Crypto.SHA256.HMAC jwt_hmac = Crypto.SHA256.HMAC(G->G->instance_config->jwt_signing_key);

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {

	string query = #"
		select u.password
		, u.active
		, u.user_id
		from user u
		where u.email = :email
		and u.deleted = 0;
	";

	mapping bindings = (["email":req->misc->json->email]);

	array results = await(G->G->DB->run_my_query(query, bindings));

	mapping|zero result_set = sizeof(results) && results[0];

	if(!result_set || !Crypto.Password.verify(req->misc->json->password, result_set->password) || !result_set->active) {
		return (["error": 400, "type":"text/plain", "data":"Password validation failed."]);
	}

	string jwt = Web.encode_jwt(jwt_hmac, (["email": req->misc->json->email, "iss":"https://gotagtech.com", "id": result_set->user_id]));

	return jsonify((["token": jwt]));


 };
