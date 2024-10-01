protected void create(string n)
{
	foreach (indices(this),string f)
		if (f!="create" && f[0]!='_')
			add_constant(f,this[f]);
}


class annotated {
	protected void create(string name) {
		//TODO: Find a good way to move prev handling into the export class or object below
		foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
			if (ann) foreach (indices(ann), mixed anno) {
				if (functionp(anno)) anno(this, name, key);
			}
		}
		//Purge any that are no longer being exported (handles renames etc)
	}
}

void export(object module, string modname, string key) {

}

