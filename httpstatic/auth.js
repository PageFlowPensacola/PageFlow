let user = JSON.parse(localStorage.getItem("user") || "{}");

on("submit", "#loginform", async function (evt) {
	evt.preventDefault();
	let form = evt.match.elements;
	const credentials = {email: form.email.value, password: form.password.value};
	const resp = await fetch("/login", {method: "POST", body: JSON.stringify(credentials)});
	const token = await resp.json();
	if (token) {
		user = {email: form.email.value, token: token.token};
		localStorage.setItem("user", JSON.stringify(user));
		await get_user_details();
		window.location.reload();
	} else {
		alert("Invalid username or password");
	}
});

on("click", "#logout", function () {
	localStorage.removeItem("user");
	window.location.reload();
});

let org_id;

export function get_org_id() {
	return org_id;
}

export function select_org(id) {
	console.error({"select_org unsupported": id});
}

export function get_token() {
	return user?.token;
}

export function get_user() {
	return user;
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
