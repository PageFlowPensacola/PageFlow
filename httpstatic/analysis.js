import {choc, set_content, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {FIGURE, FORM, H3, H4, IMG, INPUT, LI, OPTION, P, SECTION, SELECT, SPAN, UL} = choc; //autoimport
import * as auth from "./auth.js";

const localState = {};
let submittedFile = null;
let stateSnapshot = {};

export function render(state) {
	stateSnapshot = state;

	set_content("main", SECTION([
		FORM({id: "file_submit"}, [
			SELECT({id: "templateselect", value: 0}, [
				OPTION({value: 0}, "Select a template"),
				state.templates.map((t) => OPTION({value: t.id}, t.name))
			]),
			INPUT({id: "newFile", type: "file", accept: "image/pdf", disabled: true}),
			localState.uploading && P({style: "display:inline"}, "Uploading... ")
		]),
		(typeof (localState.confidence) !== "undefined") && H3("Confidence: " + (localState.confidence === 1 ? "High" : "Low")),
		(typeof (localState.rects) !== "undefined") && H4("Fields checked: " + localState.rects.length),
		UL({id: "pagesinfo"}, [
			localState.templatePages?.map((page, idx) => {
				return LI([
					P("Page " + (idx+1)),
					page.fields.map((field) => {
						const status = field.status === "Signed" ? "✅" : field.status === "Unsigned" ? "❌" : "❓";
						const signatoryName = localState.rects.find((f) => f.template_signatory_id === field.signatory)?.name;
						return SPAN(signatoryName + ": " + status + " ");
					}),
				]);
			}),
		]),
		localState.templatePages?.map((page, idx) => {
			return FIGURE([
				IMG({src: page.annotated_img}),
			]);
		}),
	]));
}

on("change", "#templateselect", (e) => {
	DOM("#newFile").disabled = e.match.value === "0";
});

on("change", "#newFile", async (e) => {
	e.preventDefault();
	submittedFile = DOM("#newFile").files[0];
	let org_id = auth.get_org_id();
	ws_sync.send({
		"cmd": "upload",
		"name": DOM("#newFile").value,
		"org": org_id,
		"template": +DOM("#templateselect").value
	});
});

export async function sockmsg_upload(msg) {
	console.log("Got upload message", msg);
	const resp = await fetch(`/upload?id=${msg.upload_id}`, {
		method: "POST",
		headers: {
			Authorization: "Bearer " + auth.get_token()
		},
		body: submittedFile
	});
	const json = await resp.json();
	console.log("Upload response", json);
	localState.templatePages = json.pages;
	localState.confidence = json.confidence;
	localState.rects = json.rects;
	localState.uploading--;
	render(stateSnapshot);
};
