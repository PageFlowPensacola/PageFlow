import {choc, set_content, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {FIGURE, FORM, H3, IMG, INPUT, P, SECTION} = choc; //autoimport
import * as auth from "./auth.js";

const localState = {};
let submittedFile = null;
let stateSnapshot = {};

export function render(state) {
	stateSnapshot = state;
	set_content("main", SECTION([
		FORM({id: "file_submit"}, [
			INPUT({id: "newFile", type: "file", accept: "image/pdf"}),
			localState.uploading && P({style: "display:inline"}, "Uploading... "),
		]),
		(typeof(localState.confidence) !== "undefined") && H3("Confidence: " + (localState.confidence === 1 ? "High" : "Low")),
		localState.templatePages?.map((page, idx) => {
			return FIGURE([
				IMG({src: page}),
			]);
		}),
	]));
}

on("change", "#newFile", async (e) => {
	e.preventDefault();
	submittedFile = DOM("#newFile").files[0];
	let org_id = auth.get_org_id();
	ws_sync.send({"cmd": "upload", "name": DOM("#newFile").value, "org": org_id});
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
	localState.uploading--;
	render(stateSnapshot);
};
