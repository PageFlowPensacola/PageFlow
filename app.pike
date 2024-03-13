/* Http server

*/

array(string) bootstrap_files = ({"globals.pike", "console.pike", "database.pike", "connection.pike", /*"window.pike",*/ "modules", "modules/http"});
array(string) restricted_update;
mapping G = ([]);

object bootstrap(string c)
{
	sscanf(explode_path(c)[-1], "%s.pike", string name);
	program|object compiled;
	mixed ex = catch {compiled = compile_file(c);};
	if (ex) {werror("Exception in compile!\n"); werror(ex->describe()+"\n"); return 0;}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	if (mixed ex = catch {compiled = compiled(name);}) {G->warnings++; werror(describe_backtrace(ex)+"\n");}
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
  bootstrap_all();

  return -1;
}
