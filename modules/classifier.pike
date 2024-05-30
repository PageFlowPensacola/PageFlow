inherit annotated;

Process.create_process python;
Stdio.File pythonstdin;
Stdio.File pythonstdout;
string pythondata = "";

void pythonoutput(mixed _, string data){
	pythondata += data;
	while (sscanf(pythondata, "%s\n%s", string line, pythondata)){
		werror("line %O", line);
	}
}

@export:
Concurrent.Future send_msg(mapping json){
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
	werror("Json %O", json);
	pythonstdin->write(Standards.JSON.encode(json, 1) + "\n");
}
