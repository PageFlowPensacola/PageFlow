inherit annotated;


// mapping of domain names to process info, with each domain having a model
@retain: mapping(string:mapping) domain_processes = ([]);

void pythonoutput(mapping proc, string data){
	if (function f = bounce(this_function)) return f(proc, data);// to support code update
	proc->pythondata += data;
	proc->idle_count = 0;
	while (sscanf(proc->pythondata, "%s\n%s", string line, proc->pythondata)){
		mapping msg = Standards.JSON.decode(line);
		object|zero prom = m_delete(proc->pending_messages, msg->msgid);

		if (msg->model && proc->domain != "") {
			G->G->DB->run_pg_query(#"
				UPDATE domains
				SET ml_model = :model
				WHERE name = :name", ([
					"name": proc->domain,
					"model": msg->model
			]));
		}
		if (prom){
			prom->success(msg);
			// TODO consider checking for error in Python response.
		}
	}
}

__async__ void load_model(string domain, mapping proc) {
	// Called once for process launch.
	array(mapping) model = await(G->G->DB->run_pg_query(#"
				SELECT ml_model
				FROM domains
				WHERE name = :name", ([
					"name": domain,
			])));
	if(model[0]->ml_model) {
		proc->pythonstdin->write(Standards.JSON.encode((["cmd": "load", "msgid": "init", "model": model[0]->ml_model]), 1) + "\n");
	} else {
		if (domain != "com.pageflow.") {
			werror("WARNING!!!!!!!!!!!!!!!! No model found for %O\n", domain);
			return;
		}
	}
	array queue = m_delete(proc, "queued_messages");
	foreach(queue, mapping json){
		proc->pythonstdin->write(Standards.JSON.encode(json, 1) + "\n");
	}
}

void pythondone(mapping proc) {
	werror("Python process for %O closed\n", proc->domain);
	m_delete(domain_processes, proc->domain);
	if (sizeof(proc->queued_messages)) {
		werror("Orphaned queued messages %O\n", proc->pending_messages);
	}
	if (sizeof(proc->pending_messages)) {
		werror("Orphaned pending messages for %O\n", proc->pending_messages);
	}
}

@export:
Concurrent.Future classipy(string domain, mapping json){
	// json will always include a cmd (train, classify, etc)
	json->msgid = G->G->next_model_msgid++;
	mapping proc = domain_processes[domain];
	if (!proc){
		Stdio.File pythonstdout = Stdio.File();
		proc = domain_processes[domain] = ([
			"pythonstdin": Stdio.File(),
			"pythondata": "",
			"pending_messages": ([]),
			"domain": domain,
			"queued_messages": ({}),
		]);
		pythonstdout->set_read_callback(pythonoutput);
		pythonstdout->set_close_callback(pythondone);
		// TODO use a Buffer
		Process.create_process(
			({G->G->instance_config->python_interpreter, "classify.py"}),
			([
				"stdin": proc->pythonstdin->pipe(Stdio.PROP_IPC|Stdio.PROP_REVERSE),
				"stdout": pythonstdout->pipe(Stdio.PROP_IPC),
			]));
		pythonstdout->set_id(proc);
		werror("process created for %O\n", domain);
		if (domain != "") load_model(domain, proc);
		else m_delete(proc, "queued_messages");
	}
	proc->idle_count = 0;
	if (proc->queued_messages) proc->queued_messages += ({json});
	else proc->pythonstdin->write(Standards.JSON.encode(json, 1) + "\n");
	/* A Promise is a Future but not every Future is a Promise
	https://pike.lysator.liu.se/generated/manual/modref/ex/predef_3A_3A/Concurrent/Future/map.html#map
	*/
	return (proc->pending_messages[json->msgid] = Concurrent.Promise())->future();
}

void count_idle() {
	G->G->classipy_idle_callout = call_out(count_idle, 300);
	foreach(domain_processes; string domain; mapping proc){
		proc->idle_count++;
		if (proc->idle_count >= 3) {
			proc->pythonstdin->close();
			// If we still have pending messages (after ten minutes), we have a problem
			if (sizeof(proc->pending_messages)) werror("Something went wrong with %O\n", domain);
			werror("Closing process for %O\n", domain);
		}
	}
	// Breach encapsulation to check if we should close the regression process
	if (G->G->regression_status->pythonstdout) {
		G->G->regression_status->idle_count++;
		if (G->G->regression_status->idle_count >= 3) {
			G->G->regression_status->pythonstdin->close();
			werror("Closing regression process\n");
		}
	}
}

string kick_python(string|zero force) {
	string kicked = sprintf("%d processes\n", sizeof(domain_processes));
	foreach(domain_processes; string domain; mapping proc){
		if (sizeof(proc->pending_messages)) {
			if(force) kicked += sprintf("\nShortcircuiting %s process\n", domain);
			else {
				kicked += sprintf("\nNot kicking %s process with pending messages (use force to override) %O\n", domain, proc->pending_messages);
				continue;
			}
			proc->pythonstdin->close();
		}
		kicked += sprintf("\tEnded %s process\n", domain);
	}
	return kicked;
}

protected void create(string name){
	::create(name);
	register_bouncer(pythonoutput);
	remove_call_out(G->G->classipy_idle_callout);
	G->G->classipy_idle_callout = call_out(count_idle, 300);
	G->G->kick_python = kick_python;
}
