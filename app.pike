/* Http server

*/

array(string) bootstrap_files = ({"globals.pike", "console.pike", "database.pike", "connection.pike", /*"window.pike",*/ "modules", "modules/http"});
array(string) restricted_update;
mapping G = ([]);

class CompilerErrors {
	int(1bit) reported;
	void compile_error(string filename, int line, string msg) {
		reported = 1;
		werror("\e[1;31m%s:%d\e[0m: %s\n", filename, line, msg); // ansi color codes
	}
}

object bootstrap(string c) // c is the code file to compile
{
	sscanf(explode_path(c)[-1], "%s.pike", string name);
	program|object compiled;

	object handler = CompilerErrors();
	//mixed ex = catch {compiled = compile_file(c, handler);};
	//if (ex) {if (!handler->reported) werror("Exception in compile!\n%s\n", ex->describe()); return 0;}
	mixed ex = catch {compiled = compile_file(c, handler);}; // try is implicit.
	if (ex) {
		if (!handler->reported) {
			werror("Exception in compile!\n");
			werror(ex->describe()+"\n");
		}
		return 0;
	}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	if (mixed ex = catch {
			compiled = compiled(name);
		}) {
		G->warnings++;
		werror(describe_backtrace(ex)+"\n");
	}
	werror("Bootstrapped "+c+"\n");
	return compiled;
}

int bootstrap_all()
{
	if (restricted_update) bootstrap_files = restricted_update;
	else {
		object main = bootstrap(__FILE__);
		if (!main || !main->bootstrap_files) {werror("UNABLE TO RESET ALL\n"); return 1;}
		bootstrap_files = main->bootstrap_files;
	}
	int err = 0;
	foreach (bootstrap_files, string fn)
		if (file_stat(fn)->isdir)
		{
			foreach (sort(get_dir(fn)), string f)
				if (has_suffix(f, ".pike")) err += !bootstrap(fn + "/" + f);
		}
		else err += !bootstrap(fn);
	return err;
}

int main(int argc,array(string) argv)
{
	add_constant("G", this);
	G->argv = argv;
	if (has_value(argv, "--test")) {
		restricted_update = ({"globals.pike", "console.pike", "database.pike", "testing.pike"});
	}
  bootstrap_all();

  return -1;
}
