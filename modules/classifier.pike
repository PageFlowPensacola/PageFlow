inherit annotated;

Process.create_process python;
Stdio.File pythonstdin;
Stdio.File pythonstdout;
string pythondata = "";

@retain:
mapping(int:Concurrent.Promise) pending_messages = ([]);
// A Promise is a Future but not every Future is a Promise

void pythonoutput(mixed _, string data){
	pythondata += data;
	while (sscanf(pythondata, "%s\n%s", string line, pythondata)){
		mapping msg = Standards.JSON.decode(line);
		werror("Classipy response %O\n", msg);
		object|zero prom = m_delete(pending_messages, msg->msgid);
		if (prom){
			prom->success(msg);
			// TODO consider checking for error in Python response.
		}
		if (msg->domain && msg->model) {
			G->G->DB->run_pg_query(#"
				UPDATE domains
				SET ml_model = :model
				WHERE name = :name", ([
					"name": msg->domain,
					"model": msg->model
			]));
		}
	}
}

@export:
Concurrent.Future classipy(mapping json){
	// json will always include a cmd (train, classify, etc)
	json->msgid = G->G->next_model_msgid++;
	if (!python){
		pythonstdin = Stdio.File();
		pythonstdout = Stdio.File();
		pythonstdout->set_read_callback(pythonoutput);
		// TODO use a Buffer
		python = Process.create_process(
			({"python", "classify.py"}),
			([
				"stdin": pythonstdin->pipe(Stdio.PROP_IPC|Stdio.PROP_REVERSE),
				"stdout": pythonstdout->pipe(Stdio.PROP_IPC)
			]));
		pythonstdin->write(Standards.JSON.encode((["cmd": "load", "msgid": "init", "model": MIME.encode_base64(Stdio.read_file("model.dat"))]), 1) + "\n");
		werror("process created");
	}

	pythonstdin->write(Standards.JSON.encode(json, 1) + "\n");
	return (pending_messages[json->msgid] = Concurrent.Promise())->future();
}
/* TODO
* If message has "domain" and "model", automatically update the model.
*/
