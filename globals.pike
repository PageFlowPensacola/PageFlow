protected void create(string n)
{
	foreach (indices(this),string f)
		if (f!="create" && f[0]!='_')
			add_constant(f,this[f]);
	foreach (Program.annotations(this_program); string anno;)
		if (stringp(anno) && sscanf(anno, "G->G->%s", string gl) && gl) // add p to string to make it a predicate: stringp.
			if (!G->G[gl]) G->G[gl] = ([]);
  catch {G->G->instance_config = Standards.JSON.decode_utf8(Stdio.read_file("instance-config.json"));};

}


@"G->G->http_endpoints";
class http_endpoint
{
	//Set to an sscanf pattern to handle multiple request URIs. Otherwise will handle just "/myname".
	constant http_path_pattern = 0;
	//A channel will be provided if and only if this is chan_foo.pike and the URL is /channels/spam/foo
	//May be a continue function or may return a Future. May also return a string (recommended for
	//debugging only, as it'll be an ugly text/plain document).
	mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) { }
	//Whitelist query variables for redirects. Three options: 0 means error, don't allow the
	//redirect at all; ([]) to allow redirect but suppress query vars; or vars&(<"...","...">)
	//to filter the variables to a specific set of keys.
	mapping(string:string|array) safe_query_vars(mapping(string:string|array) vars) {return ([]);}

	protected void create(string name)
	{
		if (http_path_pattern)
		{
			G->G->http_endpoints[http_path_pattern] = http_request;
			return;
		}
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (!name) return;
		G->G->http_endpoints[name] = http_request;
	}
}

array(function|array) find_http_handler(string not_query) {
	//Simple lookups are like http_endpoints["listrewards"], without the slash.
	//Exclude eg http_endpoints["chan_vlc"] which are handled elsewhere.
	if (function handler = !has_prefix(not_query, "/chan_") && G->G->http_endpoints[not_query[1..]])
		return ({handler, ({ })});
	//Try all the sscanf-based handlers, eg http_endpoints["/channels/%[^/]/%[^/]"], with the slash
	//TODO: Look these up more efficiently (and deterministically)
	foreach (G->G->http_endpoints; string pat; function handler) if (has_prefix(pat, "/"))
	{
		//Match against an sscanf pattern, and require that the entire
		//string be consumed. If there's any left (the last piece is
		//non-empty), it's not a match - look for a deeper pattern.
		array pieces = array_sscanf(not_query, pat + "%s");
		if (pieces && sizeof(pieces) && pieces[-1] == "") return ({handler, pieces[..<1]});
	}
	return ({0, ({ })});
}

/* Easily slide a delayed callback to the latest code

In create(), call register_bouncer(some_function)
In some_function, start with:
if (function f = bounce(this_function)) return f(...my args...);

If the code has been updated since the callback was triggered, it'll give back
the new function. Functions are identified by their %O descriptions.
*/
@"G->G->bouncers";
void register_bouncer(function f) {G->G->bouncers[sprintf("%O", f)] = f;}
function|void bounce(function f)
{
	function current = G->G->bouncers[sprintf("%O", f)];
	if (current != f) return current;
	return UNDEFINED;
}

@"G->G->exports";
class annotated {
	protected void create(string name) {
		//TODO: Find a good way to move prev handling into the export class or object below
		mapping prev = G->G->exports[name];
		G->G->exports[name] = ([]);
		foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
			if (ann) foreach (indices(ann), mixed anno) {
				if (objectp(anno) && anno->is_callable_annotation) anno(this, name, key);
			}
		}
		//Purge any that are no longer being exported (handles renames etc)
		if (prev) foreach (prev - G->G->exports[name]; string key;)
			add_constant(key);
	}
}
object export = class {
	constant is_callable_annotation = 1;
	protected void `()(object module, string modname, string key) {
		add_constant(key, module[key]);
		G->G->exports[modname][key] = 1;
	}
}();

object retain = class {
	constant is_callable_annotation = 1;
	protected void `()(object module, string modname, string key) {
		if (!G->G[key]) G->G[key] = module[key];
		else module[key] = G->G[key];
	}
}();

mapping(string:mixed) jsonify(mixed data, int|void jsonflags) {
	return (["data": string_to_utf8(Standards.JSON.encode(data, jsonflags)), "type": "application/json"]);
}
