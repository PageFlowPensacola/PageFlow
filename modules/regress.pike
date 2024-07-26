inherit annotated;
// Get a regression for submitted numbers and return a transformation matrix.

@retain: mapping regression_status = ([]);

void pythonoutput(mixed _, string data){
	if (function f = bounce(this_function)) return f(_, data);// to support code update
	regression_status->pythondata += data;
	regression_status->idle_count = 0;
	while (sscanf(regression_status->pythondata, "%s\n%s", string line, regression_status->pythondata)){
		array matrix = Standards.JSON.decode(line);
		// Grab the next promise from the fifo queue
		// and reassign the queue to the rest of the messages (a newly returned array).
		[object prom, regression_status->pending_messages] = Array.shift(regression_status->pending_messages);
		prom->success(matrix);
	}
}

void pythondone() {
	werror("Python process for for regression closed\n");
	m_delete(regression_status, "pythonstdout");
	if (sizeof(regression_status->pending_messages)) {
		werror("Orphaned pending messages for %O\n", regression_status->pending_messages);
	}
}

@export:
Concurrent.Future regression(array pairs) {
	if (!regression_status->pythonstdout){
		regression_status->pythonstdout = Stdio.File();
		regression_status->pythonstdin = Stdio.File();
		regression_status->pending_messages = ({});
		regression_status->pythonstdout->set_read_callback(pythonoutput);
		regression_status->pythonstdout->set_close_callback(pythondone);
		regression_status->pythondata = "";
		// TODO use a Buffer
		Process.create_process(
			({"python", "regress.py"}),
			([
				"stdin": regression_status->pythonstdin->pipe(Stdio.PROP_IPC|Stdio.PROP_REVERSE),
				"stdout": regression_status->pythonstdout->pipe(Stdio.PROP_IPC),
			]));
		werror("process created for regression\n");
	}
	regression_status->idle_count = 0;
	object prom = Concurrent.Promise();
	regression_status->pending_messages += ({prom});
	regression_status->pythonstdin->write(Standards.JSON.encode(pairs, 1) + "\n");
	return prom->future();
}

protected void create(string name){
	::create(name);
	register_bouncer(pythonoutput);
}
