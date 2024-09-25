
typedef mapping(string: mixed)|array(_rule)|zero _rule;
typedef _rule executable_rule;
typedef string|int|float value;
typedef value|mapping(string: mixed) expression;

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

int(1bit) assess(executable_rule rule) {
	if (!rule) return 1;
	if (arrayp(rule)) {
		foreach(rule, executable_rule subrule) {
			if (!assess(subrule)) {
				return 0;
			}
		}
		return 1;
	}
	if (!mappingp(rule)) error("Invalid ruletype %O\n", rule);
	// must be a mapping
	if (rule->condition && !truthy(eval(rule->condition))) {
		// Rule is effectively optional and check didn't happen
		// so effectively the rule has passed.
		return 1;
	}
	if (rule->require && !truthy(eval(rule->require))) {
		return 0;
	}
	if (rule->children) return assess(rule->children);
	return 1;
}

value eval(expression expr) {
	if (stringp(expr) || floatp(expr) || intp(expr)) {
		return expr;
	}
	if (!mappingp(expr)) {
		error("Invalid expression type %O\n", expr);
	}
	/*
	pageref evaulates to a page object or null (as below)
	any(#101:1, #101:2, #101:3)
	all(#101:1, #101:2, #101:3)
	set_complete(#101:1, #101:2, #101:3) <=> any(*args) && all(*args)
	*/
	if (expr->call) {
		array args = eval(expr->args[*]);
		function func = this["func_"+expr->call];
		if (!func) error("Unknown function %O\n", expr->call); //shouldn't happen
			return func(args);
	}
	if (expr->pageref) {
		// get id:page return null or the page object
	}

}

__async__ mapping|zero fetch_doc_package(int id) {
	// ar.id will be the same as pr.audit_rect_id unless pr.audit_rect_id is null
	array(mapping) file_rects = await(G->G->DB->run_pg_query(#"
		SELECT ar.id as audit_rect_id, difference, template_id, page_number, ufp.file_id, ufp.seq_idx, audit_type, name, optional
		FROM uploaded_file_pages ufp
		LEFT JOIN audit_rects ar USING (template_id, page_number)
		LEFT JOIN page_rects pr ON pr.file_id = ufp.file_id AND pr.seq_idx = ufp.seq_idx AND pr.audit_rect_id = audit_rect_id
		WHERE ufp.file_id = :id
		AND template_id IS NOT NULL
		ORDER BY ufp.file_id, ufp.seq_idx, ar.id
		", (["id": id])));
	werror("File pages %O\n", file_rects);
	mapping statuses = ([]);
	foreach(file_rects, mapping rect) {
		statuses[rect->template_id+":"+rect->page_number] = 1; // this one we indeed have
		// is there rect content?
		// for now cheat with fm (something magic bofh (bastard operator from hell) term)
		// testing for rect content is potentially costly so for now set to 1
		if (rect->audit_rect_id) {
			int signed = 1; // @TODO
			if (!signed && !rect->optional) {
				// TODO
			}
			statuses[rect->audit_rect_id] = signed;
		}
	}
	return statuses;

}
