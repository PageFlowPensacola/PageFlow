import {choc, set_content, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, CANVAS, DIV, FIELDSET, FIGCAPTION, FIGURE, FORM, H2, IMG, INPUT, LABEL, LEGEND, LI, OPTION, P, SECTION, SELECT, SPAN, UL} = choc; //autoimport
import {simpleconfirm} from "./utils.js";

let stateSnapshot = {};

const localState = {
	templates: [],
	current_template: null,
	pages: [],
	current_page: null,
	uploading: 0,
};

try {
	localState.pages = pages;
	localState.current_template = ws_group;
	DOM("#template_thumbnails") && set_content("#template_thumbnails", template_thumbnails());
} catch (e) { }

const canvas = CANVAS({width:300, height:450, style: "border: 1px solid black;"});
const ctx = canvas.getContext('2d');
let submittedFile = null;

const pageImage = new Image();
// repaint canvas when image is loaded
pageImage.onload = repaint;
let scaleFactor = 1;

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
	rect_start_x = rect_end_x = e.offsetX / scaleFactor;
	rect_start_y = rect_end_y = e.offsetY / scaleFactor;
	e.target.setPointerCapture(e.pointerId);
	repaint();
});

canvas.addEventListener('pointermove', (e) => {
	// TODO more nuance desired
	clicking = false;
	if (currently_dragging) {
		rect_end_x = e.offsetX / scaleFactor;
		rect_end_y = e.offsetY / scaleFactor;
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
			if (rect_end_x >= rect.x1 && rect_end_x <= rect.x2 && rect_end_y >= rect.y1 && rect_end_y <= rect.y2) {
				// found it
				let dlg = DOM("#editauditrect");
				set_content("#signatories", [OPTION({value: 0}, "Select a signatory"),
						stateSnapshot.signatories.map(
							(signatory) => OPTION({value: signatory.signatory_id},
								signatory.signatory_field)
					)]).value = rect.template_signatory_id;
				dlg.dataset.rectid = rect.id;
				dlg.showModal();
				return;
			}
		}
		return;
	} // end if clicking

	// Clamp rectangle to canvas/image bounds
	rect_start_x = Math.min(Math.max(rect_start_x, 0), pageImage.width);
	// Here rect_start_x is the closest place _within_ the canvas to
	// where the user started dragging.
	rect_start_y = Math.min(Math.max(rect_start_y, 0), pageImage.height);
	rect_end_x = Math.min(Math.max(rect_end_x, 0), pageImage.width);
	rect_end_y = Math.min(Math.max(rect_end_y, 0), pageImage.height);

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

	// Don't create rectangles smaller than 5x5
	if (right - left < 5 || bottom - top < 5) return;
	ws_sync.send({
		"cmd": "add_rect",
		"rect": {
			left, top, right, bottom
		},
		"page": localState.current_page
	});
});

function repaint() {
	scaleFactor = Math.min(1, 800 / pageImage.width, 1100 / pageImage.height);
	canvas.width = pageImage.width * scaleFactor;
	canvas.height = pageImage.height * scaleFactor;

	ctx.clearRect(0, 0, canvas.width, canvas.height);
	ctx.scale(scaleFactor, scaleFactor);
	ctx.drawImage(pageImage, 0, 0);
	for (const rect of stateSnapshot.page_rects[localState.current_page - 1]) {
		ctx.fillStyle = +hovering === rect.id ? "#ff88" : "#00f8";
		const left = rect.x1;
		const top = rect.y1;
		const width = (rect.x2 - rect.x1);
		const height = (rect.y2 - rect.y1);
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
				H2(state.name),
				localState.current_page ?
					[
						localState.current_page && BUTTON({id: "backtotemplate"},"<<"),
						SPAN(" Current page: " + localState.current_page),
						P("Drag to select a region to add a signatory to. Click on a region to edit the signatory."),
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
					SPAN([
						INPUT({value: "", id: "newTemplateName"}),
						INPUT({id: "newTemplateFile", type: "file", accept: "image/pdf"})
					]),
					SPAN({style: "width:25%", class: localState.uploading && "loading"}, localState.uploading && "Uploading"),
					INPUT({class: "btn", type: "submit", value: "Upload"}),
				]),
				UL(
					state.templates.map((template) => LI({class: 'template-item'},
						[
							A({
								class: 'specified-template',
								href: "templates?id=" + template.id,
								'data-name': template.name,
								'data-id': template.id,
								title: "Click to view template " + template.id
							},
								[
									template.name,
									" (id: " + template.id + ")",
									SPAN({class: "gray"}, " (" + template.domain + ")"),
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


on("change", "#newTemplateFile", async function (e) {
	const file = e.match.files[0];
	if (file && DOM("#newTemplateName").value === "") {
		DOM("#newTemplateName").value = file.name;
	}

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
	ws_sync.send({"cmd": "upload", "name": fileName});
});

export async function sockmsg_upload(msg) {
	const resp = await fetch(`/upload?id=${msg.upload_id}`, {
		method: "POST",
		body: submittedFile
	});
	console.log("Upload response", resp);
	localState.uploading--;
	render(stateSnapshot);
};

on("click", "#deleterect", (e) => {
	ws_sync.send({"cmd": "delete_rect", "id": +e.match.closest("dialog").dataset.rectid});
	e.match.closest("dialog").close();
});

on("click", "#template_thumbnails figure", function (e) {
	localState.current_page = e.match.dataset.idx;
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
	repaint();
});

on("click", "#backtotemplate", function () {
	localState.current_page = null;
	render(stateSnapshot);
});
