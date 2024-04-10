protected void create (string name) {
	G->G->utils = this;
}

void test() {
	werror("Hello World\n");
}

__async__ void audit_score() {
	await(G->G->DB->recalculate_transition_scores(0, 0));
}
