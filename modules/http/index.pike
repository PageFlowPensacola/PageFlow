inherit http_websocket;

constant markdown = #"# Signatory Check

## Check files for signatures based on user defined templates.

";

// Called on connection and update.
__async__ mapping get_state(string|int group, string|void id, string|void type){
	werror("get_state: %O %O %O\n", group, id, type);
	return ([]);
}
