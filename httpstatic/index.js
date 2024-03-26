import {choc, set_content, on, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, FIELDSET, FIGCAPTION, FIGURE, FORM, H2, IMG, INPUT, LABEL, LEGEND, LI, P, SECTION, UL} = choc; //autoimport

// TODO return user orgs on login. For now, hardcode the org ID.
let org_id;
let user = JSON.parse(localStorage.getItem("user") || "{}");


export function socket_auth() {
	return user?.token;
}

const localState = {
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

function template_thumbnails(state, template) {
	// return P("Click on a page to view it in full size.");
	const base_url = "/orgs/" + org_id + "/templates/" + localState.current_template.id + "/pages/";
	return UL({class: 'template_thumbnails'}, [
		template.pages.map(
			(url, idx) => LI(
				FIGURE([
					IMG({src: url, alt: "Page " + (idx + 1)}),
					FIGCAPTION(["Page: ", (idx + 1)])
				])
			)
		)
	])
};

function hellobutton() {
	return BUTTON({class: 'hello', }, "Hello");
}

function render() {
		if (!user?.token) {
			return set_content("header",
				FORM({id:"loginform"}, [
					LABEL([
						"Email: ", INPUT({name: "email"})
					]),
					LABEL([
						"Password: ", INPUT({type: "password", name: "password"})
					]),
					BUTTON("Log in"),
					hellobutton(),
				])
			);
		} // no user token end
		set_content("header", ["Welcome, ", user.email, " ", BUTTON({id: "logout"}, "Log out"), hellobutton()]);
	if (localState.current_template) {
		console.log("Rendering template", localState.current_template);
			set_content("main", SECTION([
				H2(localState.current_template.name),
				localState.current_template.page ?
					P("Current page: " + localState.current_template.page)
					:
				[signatory_fields(localState.current_template),
				template_thumbnails(localState, localState.current_template),]
			]));
		} else {
			set_content("main", SECTION([
				FORM({id: "template_submit"},[
					INPUT({value: "", id: "newTemplateName"}),
					INPUT({id: "blankcontract", type: "file", accept: "image/pdf"}),
					INPUT({type: "submit", value: "Upload"}),
				]),
				UL(
					localState.templates.map((template) => LI({'class': 'specified-template', 'data-name': template.name, 'data-id': template.id},
						[template.name, " (", template.page_count, ")"]
						) // close LI
					) // close map
				) // close UL
			]))

		}; // end if localState template_pages (or template listing)

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
	localState.templates = templates;
	render();
}

if (user.token) {
	get_user_details();
}

async function update_template_details(id, page) {
	const resp = await fetch("/orgs/" + org_id + "/templates/" + id, {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	if (!resp.ok) {
		return;
	}
	const template = await resp.json();
	localState.current_template = template;
	localState.current_template.id = id;
	const pagesResp = await fetch("/orgs/" + org_id + "/templates/" + id + "/pages", {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	const pagesUrls = await pagesResp.json();
	localState.current_template.pages = pagesUrls.pages;
	if (page) {
		localState.current_template.page = page;
	}
	console.log("Template is", localState.current_template);

	render();
}

const params = new URLSearchParams(window.location.hash.slice(1));
if (params.get("template")) {
	update_template_details(params.get("template"), params.get("page"));
}

async function get_user_details() {
	if (!user.token) {
		return;
	}
	const userDetailsReq = await fetch("/user", {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	const userDetails = await userDetailsReq.json();
	ws_group = org_id = userDetails.primary_org;
	ws_sync.reconnect();
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
		await get_user_details();
		render();
	} else {
		alert("Invalid username or password");
	}
});

on("click", "#logout", function () {
	localStorage.removeItem("user");
	user = null;
	ws_sync.reconnect();
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

on("click", ".hello", function () {
	ws_sync.send({cmd: "hello"});
});
