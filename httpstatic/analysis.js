import {lindt, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {CAPTION, DIV, FIGURE, FORM, H2, H3, H4, IMG, INPUT, LI, P, SECTION, SPAN, UL} = lindt; //autoimport
import "./utils.js";

const localState = {};
let submittedFile = null;
let stateSnapshot = {};

const render_upload_status = (state) => {
	console.log({"render_upload_status": state});
	return DIV([
		H2("Analysis"),
		P({class: "loading"}, state.step),
	]);
};

export function render(state) {
	stateSnapshot = state;
	console.log("Rendering", state);
	console.log("Local state", localState);
	replace_content("main", SECTION([
		FORM({id: "file_submit"}, [
			INPUT({id: "newFile", type: "file", accept: "image/pdf"}),
			localState.uploading && P({class: "loading", style: "display:inline"}, "Uploading")
		]),
		//(typeof (localState.template_names) !== "undefined") && H4("Fields checked: " + localState.rects.length),
		state.template_names && UL({id: "pagesinfo"}, [
			state.template_names.map((document) => [
				H3(document.name), Object.entries(state.templates[document.id]).map(([page_no, details]) => {
					console.log("Document page", page_no, details);
					const page_details = details[0]; // for now not supporting duplicates (TODO)
					return LI({"data-page": page_details.seq_idx}, [
						P({class: "doc_page"}, [page_no,
						/*SPAN({class: "file_page_no"}, "File Page " + page.file_page_no)*/]),
						DIV([page_details.scores?.map((field) => {
							console.log("Field", field);
							const status = field.status === "Signed" ? "✅" : field.status === "Unsigned" ? "❌" : "❓";
							const signatoryName = state.signatories[field.signatory];
							return SPAN(signatoryName + ": " + status + " ");
						})]),
					]);
				})]),
		]),
		/* DIV({class: "thumbnails"}, [localState.templateDocuments && Object.values(localState.templateDocuments).map((document) => {
			return document.map((page, idx) => {
				return page.annotated_img && FIGURE({class: "thumbnail"}, [
					IMG({src: page.annotated_img}),
					CAPTION(UL([
						LI("Page " + page.file_page_no),
						LI("Page Transition Score " + page.page_transition_score),
						LI("Calculated " + page.page_calculated_transition_score),
						page.error && LI("ERROR " + page.error),
					])),
				]);
			})
		})]) */,
		DIV({class: "thumbnail"}, [
			localState.currentPage && IMG({src: `/showpage?id=${state.file.id}&page=${localState.currentPage}`}),
		]),
	]));
}

on("change", "#newFile", async (e) => {
	e.preventDefault();
	submittedFile = DOM("#newFile").files[0];
	ws_sync.send({
		"cmd": "upload",
		"name": submittedFile.name,
	});
	localState.step = "Uploading";
	console.log("Clearing local state", stateSnapshot);
	render(stateSnapshot);
});

on("click", "#pagesinfo li", async (e) => {
	localState.currentPage = e.match.dataset.page;
	render(stateSnapshot);
 });

export async function sockmsg_upload(msg) {
	ws_sync.send({cmd: "chgrp", group: msg.group});
	history.replaceState(null, "", `/analysis?id=${msg.group}`);
	const resp = await fetch(`/upload?id=${msg.upload_id}`, {
		method: "POST",
		body: submittedFile,
	});
	localState.uploading--;
	render(stateSnapshot);
};

export function sockmsg_upload_status(msg) {
	localState.count = msg.count;
	localState.step = msg.step;
	localState.process = msg.process;
	//localState.rects = msg.rects;
	render(stateSnapshot);
}
