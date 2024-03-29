import {choc, set_content, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, DIV, FIELDSET, FIGCAPTION, FIGURE, FORM, H2, IMG, INPUT, LABEL, LEGEND, LI, P, SECTION, SPAN, UL} = choc; //autoimport
import { simpleconfirm } from "./utils.js";

// TODO return user orgs on login. For now, hardcode the org ID.
let org_id;
let user = JSON.parse(localStorage.getItem("user") || "{}");
let stateSnapshot = {};

const localState = {
	templates: [],
	current_template: null,
	pages: [],
	current_page: null,
	uploading: 0,
};

const canvas = choc.CANVAS({width:300, height:450});
const ctx = canvas.getContext('2d');

const pageImage = new Image();
// repaint canvas when image is loaded
pageImage.onload = repaint;

let rect_start_x = 0;
let rect_start_y = 0;
let rect_end_x = 0;
let rect_end_y = 0;
let currently_dragging = false;
let hovering = -1;

canvas.addEventListener('pointerdown', (e) => {
  e.preventDefault();
  currently_dragging = true;
  rect_start_x = rect_end_x = e.offsetX;
  rect_start_y = rect_end_y = e.offsetY;
  e.target.setPointerCapture(e.pointerId);
  repaint();
});

canvas.addEventListener('pointermove', (e) => {
  if (currently_dragging) {
    rect_end_x = e.offsetX;
    rect_end_y = e.offsetY;
    repaint();
  }
});

canvas.addEventListener('pointerup', (e) => {
  currently_dragging = false;
  e.target.releasePointerCapture(e.pointerId);
  let left = Math.min(rect_start_x, rect_end_x);
  let top = Math.min(rect_start_y, rect_end_y);
  let right = Math.max(rect_start_x, rect_end_x);
  let bottom = Math.max(rect_start_y, rect_end_y);
  // Now clamp to the canvas

  left = Math.max(Math.min(left, e.target.width), 0) / e.target.width;
  top = Math.max(Math.min(top, e.target.height), 0) / e.target.height;
  right = Math.max(Math.min(right, e.target.width), 0) / e.target.width;
  bottom = Math.max(Math.min(bottom, e.target.height), 0) / e.target.height;
  if (right - left < .01 || bottom - top < .01) return;
  ws_sync.send({
    "cmd": "add_rect",
    "rect": {
      left, top, right, bottom
    },
    "page": localState.current_page
  });
});

function repaint() {
  canvas.width = pageImage.width;
  canvas.height = pageImage.height;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  // Draw stuff here
	ctx.drawImage(pageImage, 0, 0);
  for (const [idx, rect] of stateSnapshot.rects.entries()) {
    ctx.fillStyle = +hovering === idx ? "#ff88" : "#00f8";
    const left = rect.left * canvas.width;
    const top = rect.top * canvas.height;
    const width = (rect.right - rect.left) * canvas.width;
    const height = (rect.bottom - rect.top) * canvas.height;
    ctx.fillRect(
      left,
      top,
      width,
      height
    );
    ctx.strokeStyle = "#00f";
    ctx.strokeRect(
      left,
      top,
      width,
      height
    );
  }
  if (currently_dragging) {
    ctx.strokeStyle = "#f00";
    ctx.lineWidth = 3;
    ctx.fillStyle = "#0f08";
    ctx.fillRect(
      rect_start_x,
      rect_start_y,
      rect_end_x - rect_start_x,
      rect_end_y - rect_start_y
    );
  }
}

export function socket_auth() {
	return user?.token;
}


function signatory_fields(template) {
	console.log("Rendering signatory fields", template);
	return FIELDSET([
		LEGEND("Potential Signatories"),
		UL({class: 'signatory_fields'}, [
			template.signatories?.map(
				(field) => LI(
					[
						LABEL(
							INPUT({class: 'signatory-field', 'data-id': field.signatory_id, type: 'text', value: field.signatory_field})
						),
						BUTTON({class: 'delete-signatory', 'data-id': field.signatory_id,}, "❌")
					],
				)
			),
			LI(
				LABEL(INPUT({class: 'signatory-field', type: 'text', value: ''})),
			)
		])
	]);
}

function template_thumbnails() {
	return localState.pages.map(
			(url, idx) => LI(
				FIGURE({"data-idx": idx + 1}, [
					IMG({src: url, alt: "Page " + (idx + 1)}),
					FIGCAPTION(["Page: ", (idx + 1)])
				])
			)
		)
};

function hellobutton() {
	return BUTTON({class: 'hello', }, "Hello");
}

export function render(state) {
	stateSnapshot = state;
	console.log("Rendering with state", state);
		if (!user?.token) {
			return set_content("#pageheader",
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
		set_content("#pageheader", ["Welcome, ", user.email, " ", BUTTON({id: "logout"}, "Log out"), hellobutton()]);
	if (typeof (state.page_count) === 'number') {
		// If it got neither a non-zero page count or a template, it wasn't (re)rendering anything.
		console.log("Rendering template", state);
		if (localState.current_page && pageImage.src !== localState.pages[localState.current_page]) {
			pageImage.src = localState.pages[localState.current_page];
		}
			set_content("main", SECTION([
				H2(state.name),
				localState.current_page ?
					[
						P("Current page: " + localState.current_page),

						DIV([
							canvas,
							SECTION([
							UL([
								/* stateSnapshot.pages[currentPage].rects */[].map((rect, idx) => LI({'class': 'rect-item', 'data-rectindex': idx}, [
									INPUT({class: 'reclabel', type: "text", value: rect.label || ""}),
									LABEL(["Initials", INPUT({class: "initials", type: "checkbox", checked: !!rect.initials})]),
									BUTTON({class: 'delete-rect'}, "❌")
								]))
							])
						])]),
					]
					:
					[
						signatory_fields(state),
						UL({id: 'template_thumbnails'}, [
							template_thumbnails(),
						]),
				]
			]));
	}
	if (state.templates) {
		console.log("Rendering template listing", localState, localState.uploading);
			set_content("main", SECTION([
				FORM({id: "template_submit"}, [
					INPUT({value: "", id: "newTemplateName"}),
					INPUT({id: "blankcontract", type: "file", accept: "image/pdf"}),
					localState.uploading && P({style: "display:inline"}, "Uploading... "),
					INPUT({type: "submit", value: "Upload"}),
				]),
				UL(
					state.templates.map((template) => LI({class: 'template-item'},
						[
							SPAN({
								class: 'specified-template',
								'data-name': template.name,
								'data-id': template.id,
								title: "Click to view template " + template.id
							},
								[
									template.name,
									" (", template.page_count, ")"
								]),
							BUTTON({class: 'delete-template', 'data-id': template.id}, "❌"),
						]
						) // close LI
					) // close map
				) // close UL
			]))

		}; // end if state template_pages (or template listing)

}

if (user.token) {
	get_user_details();
}

async function update_template_details(id) {
	localState.current_template = id;
	ws_sync.send({cmd: "chgrp", group: ws_group = `${org_id}:${id}`});
	localState.pages = [];
	const resp = await fetch(`/orgs/${org_id}/templates/${id}/pages`, {
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
	localState.pages = await resp.json();
	DOM("#template_thumbnails") && set_content("#template_thumbnails", template_thumbnails());
}

function handle_url_params() {
	console.log(
		"Handling URL params", user.token
	);
	if (!user.token) return;
	const params = new URLSearchParams(window.location.hash.slice(1));
	const template_id = params.get("template") || '';
	if (template_id) {
		update_template_details(params.get("template"));
		localState.current_page = params.get("page");
	} else {
		localState.current_template = null;
		localState.current_page = null;
		localState.pages = [];
	}
	ws_sync.send({cmd: "chgrp", group: ws_group = `${org_id}:${template_id}`});
}

window.onpopstate = (event) => {
	handle_url_params();
	console.log({"popstate event": event, hash:location.hash});
};

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
	org_id = userDetails.primary_org;
	handle_url_params();
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
	} else {
		alert("Invalid username or password");
	}
});

on("click", "#logout", function () {
	localStorage.removeItem("user");
	user = null;
	ws_sync.reconnect();
});

on("change", "#blankcontract", async function (e) {
	const file = e.match.files[0];
	if (file && DOM("#newTemplateName").value === "") {
		DOM("#newTemplateName").value = file.name;
	}

});

on("click", ".specified-template", async function (e) {
	history.pushState(null, null, "#template=" + e.match.dataset.id);
	update_template_details(e.match.dataset.id);
});

on("submit", "#template_submit", async function (e) {
	e.preventDefault();
	const submittedFile = DOM("#blankcontract").files[0];
	const fileName = DOM("#newTemplateName").value;
	localState.uploading++;
	render(stateSnapshot);
	let resp = await fetch("/orgs/" + org_id + "/templates", {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			Authorization: "Bearer " + user.token
		},
		body: JSON.stringify({name: fileName})
	});
	const template_info = await resp.json();
	resp = await fetch(`/upload?template_id=${template_info.id}`, {
		method: "POST",
		headers: {
			Authorization: "Bearer " + user.token
		},
		body: submittedFile
	});
	localState.uploading--;
	render(stateSnapshot);
});

on("click", "#template_thumbnails figure", function (e) {
	localState.current_page = e.match.dataset.idx;
	history.pushState(null, null, "#template=" + localState.current_template + "&page=" + localState.current_page);

	render(stateSnapshot);
});

on("click", ".delete-template", simpleconfirm("Delete this template", async function (e) {
	const id = e.match.dataset.id;
	const resp = await fetch(`/orgs/${org_id}/templates/${id}`, {
		method: "DELETE",
		headers: {
			Authorization: "Bearer " + user.token
		}
	});
}));

on("click", ".delete-signatory", async function (e) {
	const id = e.match.dataset.id;
	ws_sync.send({"cmd": "delete_signatory", "id": +id});
});

on('change', '.signatory-field', (e) => {
	const id = e.match.dataset.id;
	ws_sync.send({"cmd": "set_signatory", "id": +id, "name": e.match.value});
});

on("click", ".hello", function () {
	ws_sync.send({cmd: "hello"});
});
