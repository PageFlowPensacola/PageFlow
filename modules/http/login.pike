inherit http_endpoint;

constant markdown = #"# Login

<form method='POST'>
	<label>Email: <input type='text' name='email' placeholder='Email'></label>
	<label>Password: <input type='password' name='password' placeholder='Password'></label>
	<input type='submit' value='Login'>
	<input type=hidden name=grant_type value=session>
</form>";

Crypto.SHA256.HMAC jwt_hmac = Crypto.SHA256.HMAC(G->G->instance_config->jwt_signing_key);

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {

	mapping form = req->misc->json || req->variables;

	if (req->request_type == "POST") {
		array results = await(G->G->DB->run_my_query(#"
			select password, user_id, org_id
			from user
			where email = :email
			and active = 1
			and deleted = 0
		", (["email":form->email])));

		mapping|zero user = sizeof(results) && results[0];
		werror("User: %O", user);

		if(!user || !Crypto.Password.verify(form->password, user->password)) {
			// Pipe to merge two mappings: jsonify() and [("error": 400)]
			return jsonify((["data":"Password validation failed."])) | (["error": 400]);
		}
		results = await(G->G->DB->run_pg_query(#"
			select name, display_name
			from domains
			where legacy_org_id = :org_id", ([ "org_id": user->org_id ])));
		if (!sizeof(results)) {
			return jsonify((["data":"No domains found for this user."])) | (["error": 400]);
		}
		req->misc->session->user_id = user->user_id;
		req->misc->session->email = form->email;
		req->misc->session->domain = results[0]->name;
		req->misc->session->auth_domain = results[0]->name;
		return "Okay";
	} else {
		return render_template(markdown, ([]));
 	}
 }
