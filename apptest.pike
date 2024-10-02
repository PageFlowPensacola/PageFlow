
string executor_test = #"
inherit annotated;
@37:
__async__ void fetch_doc_package() {}";

class annotated {
	protected void create() {
	}
}

void main()
{
	add_constant("annotated", annotated);

	while(1) {
		compile_string(executor_test)();
		werror("Bootstrapped.\n");
	}
}
