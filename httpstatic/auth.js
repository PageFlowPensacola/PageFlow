let user = JSON.parse(localStorage.getItem("user") || "{}");
console.log(user);

let org_id;

export function get_org_id() {
	return org_id;
}

export function select_org(id) {
	const grp = ws_group.split(":");
	grp[0] = org_id = id;
	ws_sync.send({cmd: "chgrp", group: ws_group = grp.join(":")});
}

export function get_token() {
	return user?.token;
}

export function get_user() {
	return user;
}

export function chggrp(grp) {
	ws_sync.send({cmd: "chgrp", group: ws_group = `${org_id}:${grp}`});
}

export async function get_user_details() {
	if (!user?.token) {
		return false;
	}
	const userDetailsReq = await fetch("/user", {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	// TODO if auth failed return false
	const userDetails = await userDetailsReq.json();
	console.log(userDetails);
	org_id = userDetails.primary_org;
	return true;
}
