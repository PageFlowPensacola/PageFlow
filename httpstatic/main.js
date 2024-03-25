import {choc, set_content, on, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, FORM, H2, INPUT, LABEL, LI, SECTION, UL} = choc; //autoimport

// TODO return user orgs on login. For now, hardcode the org ID.
let org_id;
let user = JSON.parse(localStorage.getItem("user") || "{}");

const state = {
	templates: [],
	current_template: null,
};

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
		} // no user token end
		set_content("header", ["Welcome, ", user.email, " ", BUTTON({id: "logout"}, "Log out")]);
		if (state.current_template) {
			set_content("main", SECTION([
				H2(state.current_template.name),
			]));
		} else {
			set_content("main", SECTION([
				FORM({id: "template_submit"},[
					INPUT({value: "", id: "newTemplateName"}),
					INPUT({id: "blankcontract", type: "file", accept: "image/pdf"}),
					INPUT({type: "submit", value: "Upload"}),
				]),
				UL(
					state.templates.map((template) => LI({'class': 'contract-item', 'data-name': template.name, 'data-id': template.id},
						[template.name, " (", template.page_count, ")"]
						) // close LI
					) // close map
				) // close UL
			]))

		}; // end if state template_pages (or template listing)

}

render();

const fetch_templates = async (org_id) => {
	//console.log("Fetching templates for org", org_id);
	const response = await fetch("/orgs/" + org_id + "/templates", {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	const templates = await response.json();
	//console.log("Templates are", templates, org_id);
	state.templates = templates;
	render();
}

if (user.token) {
	const userDetailsReq = await fetch("/user", {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	const userDetails = await userDetailsReq.json();
	org_id = userDetails.primary_org;
	fetch_templates(org_id);
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

on("change", "#blankcontract", async function (e) {
	const file = e.match.files[0];
	if (file && DOM("#newTemplateName").value === "") {
		DOM("#newTemplateName").value = file.name;
	}

});

on("click", ".contract-item", async function (e) {
	state.current_template = {
		name: e.match.dataset.name,
		id: e.match.dataset.id,
	};
	let resp = await fetch("/orgs/" + org_id + "/templates/" + e.match.dataset.id, {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	const current_template_pages = await resp.json();
	state.current_template.pages = current_template_pages;
	console.log("Template pages", state.current_template);
	render();
});

on("submit", "#template_submit", async function (e) {
	e.preventDefault();
	let resp = await fetch("/orgs/" + org_id + "/templates", {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			Authorization: "Bearer " + user.token
		},
		body: JSON.stringify({name: DOM("#newTemplateName").value})
	});
	const template_info = await resp.json();
	resp = await fetch(`/upload?template_id=${template_info.id}`, {
		method: "POST",
		headers: {
			Authorization: "Bearer " + user.token
		},
		body: DOM("#blankcontract").files[0]
	});
	fetch_templates(org_id);
});
