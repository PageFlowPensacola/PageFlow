import {choc, set_content, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {CAPTION, DIV, FIGURE, FORM, H2, H3, H4, IMG, INPUT, LI, P, SECTION, SPAN, UL} = choc; //autoimport
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
	window.templateDocuments = localState.templateDocuments;
	set_content("main", SECTION([
		FORM({id: "file_submit"}, [
			INPUT({id: "newFile", type: "file", accept: "image/pdf"}),
			localState.uploading && P({class: "loading", style: "display:inline"}, "Uploading")
		]),
		(typeof (localState.step) !== "undefined") && render_upload_status(localState),
		(typeof (localState.confidence) !== "undefined") && H3("Confidence: " + (localState.confidence === 1 ? "High" : "Low")),
		(typeof (localState.rects) !== "undefined") && H4("Fields checked: " + localState.rects.length),
		localState.templateDocuments && UL({id: "pagesinfo"}, [
			Object.values(localState.templateDocuments).map((document) => [
				H3(document[0].template_name), document.map((page, idx) => {
					console.log("Document page", page, idx);
					return LI([
						P([page.template_id && "Document Page " + (idx + 1) + " ",
						SPAN({class: "file_page_no"}, "File Page " + page.file_page_no)]),
						DIV([page.fields?.map((field) => {
							console.log("Field", field, localState.rects);
							const status = field.status === "Signed" ? "✅" : field.status === "Unsigned" ? "❌" : "❓";
							const signatoryName = localState.rects.find((f) => f.template_signatory_id === field.signatory)?.name;
							console.log(localState.rects, field.signatory, signatoryName, field);
							return SPAN(signatoryName + ": " + status + " ");
						})]),
					]);
			})]),
		]),
		DIV({class: "thumbnails"}, [localState.templateDocuments && Object.values(localState.templateDocuments).map((document) => {
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
		})]),
	]));
}

on("change", "#newFile", async (e) => {
	e.preventDefault();
	submittedFile = DOM("#newFile").files[0];
	let org_id = auth.get_org_id();
	ws_sync.send({
		"cmd": "upload",
		"name": DOM("#newFile").value,
	});
	localState.step = "Uploading";
	localState.confidence = undefined;
	localState.rects = undefined;
	localState.templateDocuments = undefined;
	console.log("Clearing local state", stateSnapshot);
	render(stateSnapshot);
});

export async function sockmsg_upload(msg) {
	const resp = await fetch(`/upload?id=${msg.upload_id}`, {
		method: "POST",
		headers: {
			Authorization: "Bearer " + auth.get_token()
		},
		body: submittedFile
	});
	const json = await resp.json();
	console.log("Upload response", json);
	localState.templateDocuments = json.documents;
	localState.confidence = json.confidence;
	localState.rects = json.rects;
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
