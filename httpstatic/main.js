import {choc, set_content, on, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, FIELDSET, FIGCAPTION, FIGURE, FORM, H2, IMG, INPUT, LABEL, LEGEND, LI, SECTION, UL} = choc; //autoimport

// TODO return user orgs on login. For now, hardcode the org ID.
let org_id;
let user = JSON.parse(localStorage.getItem("user") || "{}");

const state = {
	templates: [],
	current_template: null,
};

function signatory_fields(template) {
	return FIELDSET([
		LEGEND("Potential Signatories"),
		UL({class: 'signatory_fields'}, [
			template.signatories?.map(
				(field) => LI(
					LABEL(INPUT({class: 'signatory-field', 'data-id': field.id, type: 'text', value: field.signatory_field})),
				)
			),
			LI(
				LABEL(INPUT({class: 'signatory-field', type: 'text', value: ''})),
			)
		])
	]);
}

function template_thumbnails(template) {
	const base_url = "/orgs/" + org_id + "/templates/" + state.current_template.id + "/pages/";
	return UL({class: 'template_thumbnails'}, [
		template.pages.map(
			(number) => LI(
				FIGURE([
					IMG({src: base_url + number, alt: "Page " + number, width: 100, height: 100}),
					FIGCAPTION(["Page: ", number])
				])
			)
		)
	])
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
				signatory_fields(state.current_template),
				template_thumbnails(state.current_template),
			]));
		} else {
			set_content("main", SECTION([
				FORM({id: "template_submit"},[
					INPUT({value: "", id: "newTemplateName"}),
					INPUT({id: "blankcontract", type: "file", accept: "image/pdf"}),
					INPUT({type: "submit", value: "Upload"}),
				]),
				UL(
					state.templates.map((template) => LI({'class': 'specified-template', 'data-name': template.name, 'data-id': template.id},
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

async function update_template_details(id) {
	console.log("Fetching template details for", user.token);
	const resp = await fetch("/orgs/" + org_id + "/templates/" + id, {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	if (!resp.ok) {
		return;
	}
	const template = await resp.json();
	state.current_template = template;
	state.current_template.id = id;
	//console.log("Template is", state.current_template);
	render();
}

let urlfragment = window.location.hash.slice(1); // always a string, even if no fragment.
if (urlfragment.startsWith("template-")) {
	update_template_details(urlfragment.slice(9));
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

on("click", ".specified-template", async function (e) {
	update_template_details(e.match.dataset.id);
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
