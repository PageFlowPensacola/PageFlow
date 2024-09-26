inherit annotated;


int(1bit) truthy(value val) {
	if (val == "") return 0;
	if (val == 0.0) return 0;
	return !!val;
}

value func_any(array(value) args) {
	foreach(args, value v) if (truthy(v)) return v;
}

value func_all(array(value) args) {
	foreach(args, value v) if (!truthy(v)) return v;
	return 1;
}

value func_set_complete(array(value) args) {
	return func_all(args) && func_any(args);
}

@export:
int(1bit)|array|mapping assess(executable_rule rule, mapping pkg, int|void verbose) {
	if (!rule) return 1;
	if (arrayp(rule)) {
		if (verbose) return assess(rule[*], pkg, verbose);
		foreach(rule, executable_rule subrule) {
			if (!assess(subrule, pkg)) {
				return 0;
			}
		}
		return 1;
	}
	if (!mappingp(rule)) error("Invalid ruletype %O\n", rule);
	// must be a mapping
	if (verbose) {
		mapping ret = ([]);
		mapping handler = (["condition": eval, "require": eval, "children": assess]);
		foreach (rule; string key; mixed val) if (function f = handler[key]) ret[key] =  f(val, pkg, verbose);
		return ret;
	}
	if (rule->condition && !truthy(eval(rule->condition, pkg))) {
		// Rule is effectively optional and check didn't happen
		// so effectively the rule has passed.
		return 1;
	}
	if (rule->require && !truthy(eval(rule->require, pkg))) {
		return 0;
	}
	if (rule->children) return assess(rule->children, pkg);
	return 1;
}

value|mapping eval(expression expr, mapping pkg, int|void verbose) {
	if (stringp(expr) || floatp(expr) || intp(expr)) {
		return expr;
	}
	if (!mappingp(expr)) {
		error("Invalid expression type %O\n", expr);
	}
	if (expr->call) {
		array args = eval(expr->args[*], pkg, verbose);
		function func = this["func_"+expr->call];
		if (!func) error("Unknown function %O\n", expr->call); //shouldn't happen
		if (verbose) {
			// So we only need to eval the args once
			array clean_args = map(args) {return mappingp(__ARGS__[0]) ? __ARGS__[0]->result : __ARGS__[0];};
			return (["call": expr->call, "args": args, "result": func(clean_args)]);
		}
		return func(args);
	}
	if (expr->exists) {
		if (verbose) return (["exists": expr->exists, "result": pkg[expr->exists]]);
		return pkg[expr->exists];
	}
	error("Unknown expression %O\n", expr);
}

@export:
__async__ mapping|zero fetch_doc_package(int id) {
	// ar.id will be the same as pr.audit_rect_id unless pr.audit_rect_id is null
	array(mapping) file_rects = await(G->G->DB->run_pg_query(#"
		SELECT ar.id as audit_rect_id, difference, template_id, page_number, ufp.file_id, ufp.seq_idx, audit_type, name, optional
		FROM uploaded_file_pages ufp
		LEFT JOIN audit_rects ar USING (template_id, page_number)
		LEFT JOIN page_rects pr ON pr.file_id = ufp.file_id AND pr.seq_idx = ufp.seq_idx AND pr.audit_rect_id = ar.id
		WHERE ufp.file_id = :id
		AND template_id IS NOT NULL
		ORDER BY ufp.file_id, ufp.seq_idx, ar.id
		", (["id": id])));
	mapping statuses = ([]);
	foreach(file_rects, mapping rect) {
		statuses[rect->template_id+":"+rect->page_number] = 1; // this one we indeed have
		// is there rect content?
		if (rect->audit_rect_id) {
			int signed = rect->difference || 0 >= 100 ;
			if (!signed && !rect->optional) {
				// statuses->missing += ({rect->audit_rect_id});
			}
			statuses[rect->audit_rect_id] = signed;
		}
	}
	return statuses;

}
