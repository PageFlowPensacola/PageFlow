/*
* Console.pike
* manages console commands, including:
* - hot reloads
* -
*/

void console(object stdin, string buf) {
	while (has_value(buf, "\n")) {
		sscanf(buf, "%s\n%s", string line, buf);
		if (line == "update") G->bootstrap_all();
	}
	if (buf == "update") G->bootstrap_all(); //TODO: Dedup with the above
}

protected void create(string name) {
	Stdio.stdin->set_read_callback(console);
}
