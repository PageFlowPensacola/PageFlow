import {choc, set_content, on, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, DETAILS, FORM, INPUT, LABEL, LI, SECTION, SUMMARY, UL} = choc; //autoimport

// TODO return user orgs on login. For now, hardcode the org ID.
let org_id = 271540;

const state = {
	templates: [],
};

let user = JSON.parse(localStorage.getItem("user") || "{}");
console.log("User is", user);
function render() {
		if (!user.token) {
			set_content("header",
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

			if (state.templates) {
				set_content("main", state.templates.map(t => SECTION([
					INPUT({id: "blankcontract", type: "file", accept: "image/pdf"}),
					UL(
						state.templates.map((document) => LI({'class': 'contract-item'},
							DETAILS({'data-name': document.name}, [
									SUMMARY(document.name), /* signatoryFields(document),  */UL(
								document.pages.map((page) => LI(
									A({href: `${page.page_template_url}?t=${user.token}`, 'data-page': page.page_number}, page.page_type_name)
									)
								)
								)]
							)) // close LI
						) // close map
					) // close UL
				])
				));
			}; // end if state templates
		}
}

render();

if (user.token) {
	console.log("Have a token, fetching details for a template.");
	const templateDeetsReq = await fetch("/orgs/" + org_id + "/templates/3518320/audit_rect", {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	const deets = await templateDeetsReq.json();
	console.log("Template details:", deets);
	const response = await fetch("/orgs/" + org_id + "/templates/", {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	const unmappedTemplates = await response.json();
	console.log("Unmapped templates:", unmappedTemplates);
  const templateCollection = {};
  unmappedTemplates.forEach((t) => {
    const parts = t.page_type_name.split('-');
    const pageNo = parts.pop();
    const docName = parts.join('-');
    if (!templateCollection[docName]) templateCollection[docName] = {};
    templateCollection[docName][pageNo] = t;
  });
  Object.values(templateCollection).forEach((pages) => {
		state.templates.push({
			name: Object.values(pages)[0].page_type_name.split('-').slice(0, -1).join('-'),
			pages: Object.entries(pages).sort((a, b) => a[0] - b[0]).map(x => x[1])
		});
  });
	console.log("Templates:", state.templates);
	render();
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
