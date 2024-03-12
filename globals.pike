protected void create(string n)
{
	foreach (indices(this),string f)
		if (f!="create" && f[0]!='_')
			add_constant(f,this[f]);
	foreach (Program.annotations(this_program); string anno;)
		if (stringp(anno) && sscanf(anno, "G->G->%s", string gl) && gl) // add p to string to make it a predicate: stringp.
			if (!G->G[gl]) G->G[gl] = ([]);
}
// Placeholder annotation, as G wants at least one.
@"G->G->builtins";
