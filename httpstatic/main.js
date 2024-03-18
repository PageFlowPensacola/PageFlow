import {choc, set_content, on, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, FIELDSET, FORM, INPUT, LABEL} = choc; //autoimport

// TODO return user orgs on login. For now, hardcode the org ID.
let org_id = 271540;

let user = JSON.parse(localStorage.getItem("user") || "{}");
console.log("User is", user);
function render() {
		if (!user.token) {
			return set_content("header",
				FORM({id:"loginform"}, [
					LABEL([
						"Email: ", INPUT({name: "email"})
					]),
					LABEL([
						"Password: ", INPUT({type: "password", name: "password"})
					]),
					BUTTON("Log in")
				])
			);
		} else {
			set_content("header", ["Welcome, ", user.email, " ", BUTTON({id: "logout"}, "Log out")]);
		}
}

render();

if (user.token) {
	console.log("Have a token, fetching templates");
	const templates = await fetch("/org/" + org_id + "/templates/", {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	const data = await templates.json();
	console.log("Templates:", data);
}

on("submit", "#loginform", async function (evt) {
	evt.preventDefault();
	let form = evt.match.elements;
	const credentials = {email: form.email.value, password: form.password.value};
	const resp = await fetch("/login", {method: "POST", body: JSON.stringify(credentials)});
	const token = await resp.json();
	if (token) {
		user = {email: form.email.value, token: token.token};
		localStorage.setItem("user", JSON.stringify(user));
		render();
	} else {
		alert("Invalid username or password");
	}
});

on("click", "#logout", function () {
	localStorage.removeItem("user");
	user = null;
	render();
});
