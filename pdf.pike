int main(int argc, array(string) argv)
{
	//https://www.adobe.com/devnet-docs/acrobatetk/tools/DigSig/Acrobat_DigitalSignatures_in_PDF.pdf
	https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf
	// Chris noticed a PDF that had multiple %%EOF markers, and startxrefs
	// which come from incremental updates to the file.
	mapping args = Arg.parse(argv);
	if (!sizeof(args[Arg.REST])) {
		exit(1, "Usage: pike " + argv[0] + " <file> <file> ...\n");
	}
	foreach (args[Arg.REST], string file) {
		string f = Stdio.read_file(file);
		array parts = f / "%%EOF";
		// Remove tailing %%EOF and following, then rejoin array parts.
		string data = parts[.. < 1] * "%%EOF";
		array lastlines = data[<64..] / "\n";
		// assert lastlines[-1] == "";
		// assert lastlines[-3] == "startxref" or "startxref\r";
		int startxref = (int) lastlines[-2];
		// byte position at which data begins. (probably Root object)
		werror("Data from startxref %O\n", data[startxref.. startxref + 16]);
	}
}
