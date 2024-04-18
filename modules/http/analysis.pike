inherit http_websocket;

constant markdown = "# Analysis\n\n";


__async__ void websocket_cmd_upload(mapping(string:mixed) conn, mapping(string:mixed) msg){

	string upload_id = G->G->prepare_upload("contract", (["template_id": 50]));
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "upload_id": upload_id])));
}

__async__ mapping get_state(string|int group, string|void id, string|void type){
	werror("get_state: %O %O %O\n", group, id, type);
	return ([ ]);
}
