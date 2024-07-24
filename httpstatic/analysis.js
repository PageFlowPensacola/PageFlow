import {lindt, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {DIV, FORM, "svg:g": G, H3, IMG, INPUT, LI, P, "svg:path": PATH, SECTION, SPAN, "svg:svg": SVG, UL} = lindt; //autoimport
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
		state.templates && state.template_names && UL({id: "pagesinfo"}, [
			state.template_names.map((document) => [
				H3(document.name), Object.entries(state.templates[document.id]).map(([page_no, details]) => {
					const page_details = details[0]; // for now not supporting duplicates (TODO)
					return LI({"data-page": page_details.seq_idx}, [
						P({class: "doc_page"}, [page_no,
						/*SPAN({class: "file_page_no"}, "File Page " + page.file_page_no)*/]),
						DIV([page_details.scores?.map((field) => {
							const status = field.status === "Signed" ? SVG({viewBox: "0 0 64 64", "text-anchor": "middle", width: 30, height: 30, fill: "#000000"}, [
								G({fill: "green", transform: 'translate(-256.000000, -1035.000000)'}, PATH({d: 'M286,1063 C286,1064.1 285.104,1065 284,1065 L260,1065 C258.896,1065 258,1064.1 258,1063 L258,1039 C258,1037.9 258.896,1037 260,1037 L284,1037 C285.104,1037 286,1037.9 286,1039 L286,1063 L286,1063 Z M284,1035 L260,1035 C257.791,1035 256,1036.79 256,1039 L256,1063 C256,1065.21 257.791,1067 260,1067 L284,1067 C286.209,1067 288,1065.21 288,1063 L288,1039 C288,1036.79 286.209,1035 284,1035 L284,1035 Z M278.027,1044.07 C277.548,1043.79 276.937,1043.96 276.661,1044.43 L270.266,1055.51 L266.688,1052.21 C266.31,1051.81 265.677,1051.79 265.274,1052.17 C264.871,1052.54 264.85,1053.18 265.228,1053.58 L269.8,1057.8 C270.177,1058.2 270.81,1058.22 271.213,1057.84 C271.335,1057.73 278.393,1045.43 278.393,1045.43 C278.669,1044.96 278.505,1044.34 278.027,1044.07 L278.027,1044.07 Z'}))]) : field.status === "Unsigned" ? "❌" : "❓";
							const signatoryName = state.signatories[field.signatory];
							console.log(status); // SPAN(signatoryName + ": " + status + " ");
							return SPAN([signatoryName + ": ", status," "]);
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
			localState.currentPage && IMG({src: `/showpage?id=${state.file.id}&page=${localState.currentPage}&annotate`}),
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
	localState.uploading ? localState.uploading-- : 0;
	localState.currentPage = 0;
	render({}); // Clear the page
};

export function sockmsg_upload_status(msg) {
	//localState.rects = msg.rects;
	localState.uploading = 1;
	render(stateSnapshot);
}
