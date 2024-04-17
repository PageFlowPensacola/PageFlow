let user = JSON.parse(localStorage.getItem("user") || "{}");
console.log(user);

let org_id;

export function get_org_id() {
	return org_id;
}
export function select_org(id) {
	// TODO filter by access
	org_id = id;
}

export function get_token() {
	return user?.token;
}

export function get_user() {
	return user;
}
