import {choc, set_content, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, CANVAS, DIV, FIELDSET, FIGCAPTION, FIGURE, FORM, H2, IMG, INPUT, LABEL, LEGEND, LI, OPTION, P, SECTION, SELECT, SPAN, UL} = choc; //autoimport
import {simpleconfirm} from "./utils.js";
import * as auth from "./auth.js";

let stateSnapshot = {};

const localState = {
	templates: [],
	current_template: null,
	pages: [],
	current_page: null,
	uploading: 0,
};

const canvas = CANVAS({width:300, height:450, style: "border: 1px solid black;"});
const ctx = canvas.getContext('2d');
let submittedFile = null;

const pageImage = new Image();
// repaint canvas when image is loaded
pageImage.onload = repaint;

let rect_start_x = 0;
let rect_start_y = 0;
let rect_end_x = 0;
let rect_end_y = 0;
let currently_dragging = false;
let clicking = false;
let hovering = -1;

canvas.addEventListener('pointerdown', (e) => {
	e.preventDefault();
	currently_dragging = clicking = true;
	rect_start_x = rect_end_x = e.offsetX;
	rect_start_y = rect_end_y = e.offsetY;
	e.target.setPointerCapture(e.pointerId);
	repaint();
});

canvas.addEventListener('pointermove', (e) => {
	// TODO more nuance desired
	clicking = false;
	if (currently_dragging) {
		rect_end_x = e.offsetX;
		rect_end_y = e.offsetY;
		repaint();
	}
});

canvas.addEventListener('pointerup', (e) => {
	if (!currently_dragging) return;
	const bounds = localState.pages[localState.current_page - 1];
	currently_dragging = false;
	e.target.releasePointerCapture(e.pointerId);
	if (clicking) {// as opposed to dragging
		// did you click in a rect?
		// iterate over all rects, find the one that contains the click
		for (const rect of stateSnapshot.page_rects[localState.current_page - 1]) {
			const left = rect.x1 * (bounds.pxright - bounds.pxleft) + bounds.pxleft;
			const top = rect.y1 * (bounds.pxbottom - bounds.pxtop) + bounds.pxtop;
			const right = rect.x2 * (bounds.pxright - bounds.pxleft) + bounds.pxleft;
			const bottom = rect.y2 * (bounds.pxbottom - bounds.pxtop) + bounds.pxtop;
			if (rect_end_x >= left && rect_end_x <= right && rect_end_y >= top && rect_end_y <= bottom) {
				// found it
				let dlg = DOM("#editauditrect");
				set_content("#signatories", [OPTION({value: 0}, "Select a signatory"),
						stateSnapshot.signatories.map(
							(signatory) => OPTION({value: signatory.signatory_id},
								signatory.signatory_field)
						)]).value = rect.template_signatory_id;
				dlg.showModal();
				return;
			}
		}
		return;
	}


	// Calculate the width and height of the (text-based) bounding box
	// returned based on Tesseract's output.
	const width = bounds.pxright - bounds.pxleft;
	const height = bounds.pxbottom - bounds.pxtop;

	// Clamp rectangle to canvas/image bounds
	rect_start_x = Math.min(Math.max(rect_start_x, 0), canvas.width);
	// Here rect_start_x is the closest place _within_ the canvas to
	// where the user started dragging.
	rect_start_y = Math.min(Math.max(rect_start_y, 0), canvas.height);
	rect_end_x = Math.min(Math.max(rect_end_x, 0), canvas.width);
	rect_end_y = Math.min(Math.max(rect_end_y, 0), canvas.height);

	// Normalize the rectangle since we don't know
	// which direction the user dragged in.
	// While we're at it remove margins as defined in bounding box.
	let left = Math.min(rect_start_x, rect_end_x);
	// Here left will be either rect_start_x or rect_end_x, whichever is least.
	// Left will be the number of pixels from the left edge of the canvas to the
	// left edge of the rectangle.
	let top = Math.min(rect_start_y, rect_end_y);
	let right = Math.max(rect_start_x, rect_end_x);
	let bottom = Math.max(rect_start_y, rect_end_y);

	// Now we change the coordinate system from pixels to bounding box coordinates.
	// The edges of the bounding box are defined as 0 and 1.
	// Since most of these documents will be in portrait orientation,
	// the Y scale will generally have a larger step size than the X scale,
	// but this won't make a difference.
	// First we cut off the margin, then in order to
	// get the percentage of the bounding box, we divide by the width or height,
	// which is the scale of our percentage.
	left = (left - bounds.pxleft) / width;
	top = (top - bounds.pxtop) / height;
	right = (right - bounds.pxleft) / width;
	bottom = (bottom - bounds.pxtop) / height;

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
	const bounds = localState.pages[localState.current_page - 1];
	ctx.strokeStyle = "magenta";
	ctx.lineWidth = 1;
	ctx.moveTo(bounds.pxleft, bounds.pxtop);
	ctx.lineTo(bounds.pxright, bounds.pxtop);
	ctx.lineTo(bounds.pxright, bounds.pxbottom);
	ctx.lineTo(bounds.pxleft, bounds.pxbottom);
	ctx.lineTo(bounds.pxleft, bounds.pxtop);
	ctx.lineTo(bounds.pxright, bounds.pxbottom);
	ctx.moveTo(bounds.pxright, bounds.pxtop);
	ctx.lineTo(bounds.pxleft, bounds.pxbottom);
	ctx.stroke();
	for (const rect of stateSnapshot.page_rects[localState.current_page - 1]) {
		ctx.fillStyle = +hovering === rect.id ? "#ff88" : "#00f8";
		const left = rect.x1 * (bounds.pxright - bounds.pxleft) + bounds.pxleft;
		const top = rect.y1 * (bounds.pxbottom - bounds.pxtop) + bounds.pxtop;
		const width = (rect.x2 - rect.x1) * (bounds.pxright - bounds.pxleft);
		const height = (rect.y2 - rect.y1) * (bounds.pxbottom - bounds.pxtop);
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

document.addEventListener("keydown", (e) => {
	if (e.key === "Escape" && currently_dragging) {
		currently_dragging = false;
		repaint();
	}
});




function signatory_fields(template) {
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
			(page, idx) => LI(
				FIGURE({"data-idx": idx + 1}, [
					IMG({src: page.page_data, alt: "Page " + (idx + 1)}),
					FIGCAPTION(["Page: ", (idx + 1)])
				])
			)
		)
};

export function render(state) {
	stateSnapshot = state;
	console.log("Rendering with state", state);
	if (typeof (state.page_count) === 'number') {
		// If it got neither a non-zero page count or a template, it wasn't (re)rendering anything.
		if (localState.current_page && pageImage.src !== localState.pages[localState.current_page - 1].page_data) {
			// if we have a current page and has changed, reload the image
			pageImage.src = localState.pages[localState.current_page - 1].page_data;
		}
			set_content("main", SECTION([
				H2(A({href: "#template=" + localState.current_template}, state.name)),
				localState.current_page ?
					[
						P("Current page: " + localState.current_page),

						DIV({id: "auditrects"},[
							canvas,
							SECTION([
							UL([
								stateSnapshot.page_rects[localState.current_page - 1].map((rect) => LI({'class': 'rect-item', 'data-rectid': rect.id}, [
									SELECT({class: 'rectlabel', value: rect.template_signatory_id}, [
										OPTION({value: 0}, "Select a signatory"),
										stateSnapshot.signatories.map(
										(signatory) => OPTION({value: signatory.signatory_id},
											signatory.signatory_field)
									)]),
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
			set_content("main", SECTION([
				FORM({id: "template_submit"}, [
					INPUT({value: "", id: "newTemplateName"}),
					INPUT({id: "newTemplateFile", type: "file", accept: "image/pdf"}),
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
									template.name + " (id: " + template.id + ")",
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

async function update_template_details(id) {
	localState.current_template = id;
	let org_id = auth.get_org_id();
	auth.chggrp(id);
	localState.pages = [];
	const resp = await fetch(`/orgs/${org_id}/templates/${id}/pages`, {
		headers: {
			Authorization: "Bearer " + auth.get_token()
		}
	});
	localState.pages = await resp.json();
	DOM("#template_thumbnails") && set_content("#template_thumbnails", template_thumbnails());
}

function handle_url_params() {
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
	// TODO don't hack this!!!!!!!!
	auth.chggrp(template_id || "com.pageflow.tagtech.dunder-mifflin.");
}
handle_url_params();

window.onpopstate = (event) => {
	handle_url_params();
};

on("change", "#newTemplateFile", async function (e) {
	const file = e.match.files[0];
	if (file && DOM("#newTemplateName").value === "") {
		DOM("#newTemplateName").value = file.name;
	}

});

on("click", ".specified-template", async function (e) {
	history.pushState(null, null, "#template=" + e.match.dataset.id);
	update_template_details(e.match.dataset.id);
});

/*
	First send a request to upload the file, then send the file itself.
*/
on("submit", "#template_submit", async function (e) {
	e.preventDefault();
	submittedFile = DOM("#newTemplateFile").files[0];
	if (!submittedFile) return;
	const fileName = DOM("#newTemplateName").value;
	localState.uploading++;
	render(stateSnapshot);
	let org_id = auth.get_org_id();
	ws_sync.send({"cmd": "upload", "name": fileName, "org": org_id});
});


export async function sockmsg_upload(msg) {
	const resp = await fetch(`/upload?id=${msg.upload_id}`, {
		method: "POST",
		headers: {
			Authorization: "Bearer " + auth.get_token()
		},
		body: submittedFile
	});
	console.log("Upload response", resp);
	localState.uploading--;
	render(stateSnapshot);
};

on("click", "#template_thumbnails figure", function (e) {
	localState.current_page = e.match.dataset.idx;
	history.pushState(null, null, "#template=" + localState.current_template + "&page=" + localState.current_page);

	render(stateSnapshot);
});

on("click", ".delete-template", simpleconfirm("Delete this template", async function (e) {
	const id = e.match.dataset.id;
	ws_sync.send({"cmd": "delete_template", "id": +id});
}));

on("click", ".delete-signatory", async function (e) {
	const id = e.match.dataset.id;
	ws_sync.send({"cmd": "delete_signatory", "id": +id});
});

on('change', '.signatory-field', (e) => {
	const id = e.match.dataset.id;
	ws_sync.send({"cmd": "set_signatory", "id": +id, "name": e.match.value});
});

on('change', '.rectlabel', (e) => {
	const id = e.match.closest("[data-rectid]").dataset.rectid;
	ws_sync.send({"cmd": "set_rect_signatory", "id": +id, "signatory_id": e.match.value});
});

on('click', '.delete-rect', (e) => {
	const id = e.match.closest("[data-rectid]").dataset.rectid;
	ws_sync.send({"cmd": "delete_rect", "id": +id});
});

on('mouseover', '.rect-item', (e) => {
	const id = e.match.closest("[data-rectid]").dataset.rectid;
	hovering = id;
	repaint();
});

on('mouseout', '.rect-item', () => {
	hovering = -1;
	repaint();
});

on("click", 'a[href^="#"]', function () {
	setTimeout(handle_url_params, 0);
	repaint();
});
