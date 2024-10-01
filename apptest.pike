/* Http server

*/


mapping G = ([]);


object bootstrap(string c) // c is the code file to compile
{
	return compile_file(c)(c);
}

int | Concurrent.Future main(int argc,array(string) argv)
{
	add_constant("G", this);
	bootstrap("globalstest.pike");

	while(1) {
		bootstrap("modules/executortest.pike");
		werror("Bootstrapped.\n");
	}
}
