
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
