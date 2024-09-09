inherit http_endpoint;

mapping http_request(Protocols.HTTP.Server.Request req) {
		return render_template(#" # Sandbox
		", ([
				"js": "sandbox.js",
		]));
}
