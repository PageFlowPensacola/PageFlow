int main(int argc, array(string) argv)
{
		mapping args = Arg.parse(argv);
		if (!sizeof(args[Arg.REST])) {
			exit(1, "Usage: pike " + argv[0] + " <file> <file> ...\n");
		}
		foreach (args[Arg.REST], string file) {
			string f = Stdio.read_file(file);
			array parts = f / "%%EOF";
			// Remove everything after tailing %%EOF and rejoin array parts.
			string data = parts[.. < 1] * "%%EOF";
			werror("Last 60ish chars: %O", data[<60..]);
			werror("Got %O", Regexp.SimpleRegexp("startxref\n([0-9]+)\n$")->split(data));
		}
}
