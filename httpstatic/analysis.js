import {lindt, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, DETAILS, DIV, FIGCAPTION, FIGURE, FORM, "svg:g": G, H3, H4, IMG, INPUT, LI, P, "svg:path": PATH, SECTION, SPAN, SUMMARY, "svg:svg": SVG, UL} = lindt; //autoimport
import { simpleconfirm } from "./utils.js";

const localState = {currentPage: 1};
let submittedFile = null;
let stateSnapshot = {};

function render_expr(rule_condition, status_condition) {
	if (!rule_condition) return 0;
	console.log("render_expr", rule_condition, status_condition);
	if (typeof rule_condition !== 'object') return rule_condition;
	if (rule_condition.call) return UL([
		LI([status_condition.result ? checkmark() : crossmark(), SPAN({style: "font-weight: bold;text-transform: capitalize"},rule_condition.call.split('_').join(' ') + ":")]),
		LI(UL(rule_condition.args.map((arg, idx) => LI(render_expr(arg, status_condition.args[idx]))))),
		LI(render_expr(rule_condition.result, status_condition.result)),
	]);
	if (rule_condition.exists) return SPAN(["Exists: ", rule_condition.exists + " ", status_condition.result ? checkmark() : crossmark()]);
}

function render_statuses(ruleset, statuses) {
	console.log("Rendering render_statuses", ruleset, statuses);
	if (!ruleset) return null;
	if (Array.isArray(ruleset)) return UL(ruleset.map((rule, idx) => LI(render_statuses(rule, statuses[idx]))));
	if (ruleset.condition) return UL([
		LI([statuses.result ? " " : checkmark(), render_expr(ruleset.condition, statuses.condition)]),
		LI(render_statuses(ruleset.children, statuses.children)),
	]);
	if (ruleset.require) return UL([
		LI([statuses.result ? checkmark() : crossmark(), render_expr(ruleset.require, statuses.require)]),
		LI(render_statuses(ruleset.children, statuses.children)),
	]);
	if (ruleset.children) return render_statuses(ruleset.children, statuses.children);
	return null;
}

const dateTime = new Intl.DateTimeFormat("en-US", {
	year: "numeric", month: "short", day: "numeric",
	hour: "numeric", minute: "numeric", second: "numeric"
});

/*
Choc doesn't support using the same SVG element in multiple places, but it may be fine 'cause we're using Lindt.
*/
const checkmark = () => SVG({viewBox: "0 0 32 32", style: "vertical-align: middle;", width: 15, height: 15}, [
	G({fill: "green", transform: 'translate(-256.000000, -1035.000000)'}, PATH({d: 'M286,1063 C286,1064.1 285.104,1065 284,1065 L260,1065 C258.896,1065 258,1064.1 258,1063 L258,1039 C258,1037.9 258.896,1037 260,1037 L284,1037 C285.104,1037 286,1037.9 286,1039 L286,1063 L286,1063 Z M284,1035 L260,1035 C257.791,1035 256,1036.79 256,1039 L256,1063 C256,1065.21 257.791,1067 260,1067 L284,1067 C286.209,1067 288,1065.21 288,1063 L288,1039 C288,1036.79 286.209,1035 284,1035 L284,1035 Z M278.027,1044.07 C277.548,1043.79 276.937,1043.96 276.661,1044.43 L270.266,1055.51 L266.688,1052.21 C266.31,1051.81 265.677,1051.79 265.274,1052.17 C264.871,1052.54 264.85,1053.18 265.228,1053.58 L269.8,1057.8 C270.177,1058.2 270.81,1058.22 271.213,1057.84 C271.335,1057.73 278.393,1045.43 278.393,1045.43 C278.669,1044.96 278.505,1044.34 278.027,1044.07 L278.027,1044.07 Z'}))]);
const crossmark = () => SVG({viewBox: "0 0 64 64", style: "vertical-align: middle;", width: 15, height: 15}, [
	G({fill: "red"}, PATH({d: 'M32.085,56.058c6.165,-0.059 12.268,-2.619 16.657,-6.966c5.213,-5.164 7.897,-12.803 6.961,-20.096c-1.605,-12.499 -11.855,-20.98 -23.772,-20.98c-9.053,0 -17.853,5.677 -21.713,13.909c-2.955,6.302 -2.96,13.911 0,20.225c3.832,8.174 12.488,13.821 21.559,13.908c0.103,0.001 0.205,0.001 0.308,0Zm-0.282,-4.003c-9.208,-0.089 -17.799,-7.227 -19.508,-16.378c-1.204,-6.452 1.07,-13.433 5.805,-18.015c5.53,-5.35 14.22,-7.143 21.445,-4.11c6.466,2.714 11.304,9.014 12.196,15.955c0.764,5.949 -1.366,12.184 -5.551,16.48c-3.672,3.767 -8.82,6.016 -14.131,6.068c-0.085,0 -0.171,0 -0.256,0Zm-12.382,-10.29l9.734,-9.734l-9.744,-9.744l2.804,-2.803l9.744,9.744l10.078,-10.078l2.808,2.807l-10.078,10.079l10.098,10.098l-2.803,2.804l-10.099,-10.099l-9.734,9.734l-2.808,-2.808Z'}))]);
const questionmark = () => SVG({viewBox: "0 0 15 15", style: "vertical-align: middle;", width: 15, height: 15}, [
	G({fill: "red"}, PATH({d: "M0.877075 7.49972C0.877075 3.84204 3.84222 0.876892 7.49991 0.876892C11.1576 0.876892 14.1227 3.84204 14.1227 7.49972C14.1227 11.1574 11.1576 14.1226 7.49991 14.1226C3.84222 14.1226 0.877075 11.1574 0.877075 7.49972ZM7.49991 1.82689C4.36689 1.82689 1.82708 4.36671 1.82708 7.49972C1.82708 10.6327 4.36689 13.1726 7.49991 13.1726C10.6329 13.1726 13.1727 10.6327 13.1727 7.49972C13.1727 4.36671 10.6329 1.82689 7.49991 1.82689ZM8.24993 10.5C8.24993 10.9142 7.91414 11.25 7.49993 11.25C7.08571 11.25 6.74993 10.9142 6.74993 10.5C6.74993 10.0858 7.08571 9.75 7.49993 9.75C7.91414 9.75 8.24993 10.0858 8.24993 10.5ZM6.05003 6.25C6.05003 5.57211 6.63511 4.925 7.50003 4.925C8.36496 4.925 8.95003 5.57211 8.95003 6.25C8.95003 6.74118 8.68002 6.99212 8.21447 7.27494C8.16251 7.30651 8.10258 7.34131 8.03847 7.37854L8.03841 7.37858C7.85521 7.48497 7.63788 7.61119 7.47449 7.73849C7.23214 7.92732 6.95003 8.23198 6.95003 8.7C6.95004 9.00376 7.19628 9.25 7.50004 9.25C7.8024 9.25 8.04778 9.00601 8.05002 8.70417L8.05056 8.7033C8.05924 8.6896 8.08493 8.65735 8.15058 8.6062C8.25207 8.52712 8.36508 8.46163 8.51567 8.37436L8.51571 8.37433C8.59422 8.32883 8.68296 8.27741 8.78559 8.21506C9.32004 7.89038 10.05 7.35382 10.05 6.25C10.05 4.92789 8.93511 3.825 7.50003 3.825C6.06496 3.825 4.95003 4.92789 4.95003 6.25C4.95003 6.55376 5.19628 6.8 5.50003 6.8C5.80379 6.8 6.05003 6.55376 6.05003 6.25Z"}))]);
const empty = () => SVG({viewBox: "0 0 15 15", style: "vertical-align: middle;", width: 15, height: 15}, [
	G({fill: "black"}, PATH({d: "M0.877075 7.49972C0.877075 3.84204 3.84222 0.876892 7.49991 0.876892C11.1576 0.876892 14.1227 3.84204 14.1227 7.49972C14.1227 11.1574 11.1576 14.1226 7.49991 14.1226C3.84222 14.1226 0.877075 11.1574 0.877075 7.49972ZM7.49991 1.82689C4.36689 1.82689 1.82708 4.36671 1.82708 7.49972C1.82708 10.6327 4.36689 13.1726 7.49991 13.1726C10.6329 13.1726 13.1727 10.6327 13.1727 7.49972C13.1727 4.36671 10.6329 1.82689 7.49991 1.82689Z"}))]);
const statuses = [empty, checkmark, questionmark, crossmark];

export function render(state) {
	stateSnapshot = state;
	console.log("Rendering analysis page", localState, state);
	if (state.files) {
		return replace_content("main", SECTION([
			FORM({id: "file_submit"}, [
				INPUT({id: "newFile", type: "file", accept: "image/pdf"}),
			]),
			H3("Uploaded Files"),
			UL(state.files.map(file => LI([A({href: `/analysis?id=${file.id}`}, [
				(SPAN(file.filename)), " ", (SPAN(dateTime.format(new Date(file.created))))
			]), " ",
				BUTTON({type: "button", class: "delete", "data-id": file.id}, "❌")]))),
		]));
	}


	replace_content("main", SECTION([
		submittedFile ? H3("Analyzing " + submittedFile.name) : H3("Analysis Results " + state.file.filename + " " + dateTime.format(new Date(state.file.created))),
			localState.rects && ("Fields checked: " + localState.rects.length),
			state.templates && state.template_names && DIV({id: "analysis-results"}, [
				[
				DIV({id: "analysis-meta"}, [
					(state.analyzedcount && state.file.page_count) ?
						H4(`${state.analyzedcount} of ${state.file.page_count} pages analyzed`)
						: H4({class: "loading"}, "File submitted, awaiting analysis"),
					DIV({id: "analysis-results__progress"}, [
						(state.file.page_count && state.analyzedcount)
							? [SPAN({style: `flex-grow: ${state.analyzedcount}`}), SPAN({style: `flex-grow: ${(state.file.page_count - state.analyzedcount)}`})]
							: [SPAN({style: `flex-grow: ${0}`}), SPAN({style: `flex-grow: ${1}`})]
					]),
				]),
				DIV({id: "analysis-results__listing"}, [
					Object.keys(state.templates).length && UL({id: "pagesinfo"}, [
						state.statuses && DETAILS({/* open: false */}, [
							SUMMARY("Rule Checks"),
							render_statuses(state.ruleset, state.statuses),
						]),
						state.template_names.map((doc) => {
							let worstStatus = 0;
							const analysis = Object.entries(state.templates[doc.id]).map(([page_no, details]) => {
								return details.map(page_details => LI({
									"data-page": page_details.seq_idx,
									class: page_details.seq_idx === +localState.currentPage ? "current" : "",
								}, [
									/* TODO this will be nicer with a proper icon
									<svg viewBox="0 0 24 24" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" fill="#000000"><g id="SVGRepo_bgCarrier" stroke-width="0"></g><g id="SVGRepo_tracerCarrier" stroke-linecap="round" stroke-linejoin="round"></g><g id="SVGRepo_iconCarrier"> <title>Reload</title> <g id="Page-1" stroke="none" stroke-width="1" fill="none" fill-rule="evenodd"> <g id="Reload"> <rect id="Rectangle" fill-rule="nonzero" x="0" y="0" width="24" height="24"> </rect> <path d="M4,13 C4,17.4183 7.58172,21 12,21 C16.4183,21 20,17.4183 20,13 C20,8.58172 16.4183,5 12,5 C10.4407,5 8.98566,5.44609 7.75543,6.21762" id="Path" stroke="#0C0310" stroke-width="2" stroke-linecap="round"> </path> <path d="M9.2384,1.89795 L7.49856,5.83917 C7.27552,6.34441 7.50429,6.9348 8.00954,7.15784 L11.9508,8.89768" id="Path" stroke="#0C0310" stroke-width="2" stroke-linecap="round"> </path> </g> </g> </g></svg>
									*/
									P({class: "doc_page"}, [doc.id === 9999999999 ? "File page " + page_details.seq_idx : page_no,
									/*SPAN({class: "file_page_no"}, "File Page " + page.file_page_no)*/]),
									DIV([page_details.scores?.map((field) => {
										const status = field.status === "Signed" ? 1 : field.status === "Unsigned" ? 3 : 2;
										const signatoryName = state.signatories[field.signatory];
										if (status > worstStatus) worstStatus = status;
										return SPAN([signatoryName + ": ", statuses[status](), " "]);
									})]),
									DIV(page_details.seq_idx === +localState.currentPage && ">"),
								]));
							});
							return DETAILS(Object.values(state.templates[doc.id]).filter((t) => t.find( p => p.seq_idx === +localState.currentPage)).length ? {open: true} : {}, [
								SUMMARY([doc.name, " ", statuses[worstStatus]()]), analysis
							])}),
					]),
				Object.keys(state.templates).length && DIV({class: "thumbnail__wrapper loadable"}, [
							A(
								{href: `/showpage?id=${state.file.id}&page=${localState.currentPage}&annotate`},
								FIGURE({class: "thumbnail"}, [
									IMG({onload: imgLoaded, src: `/showpage?id=${state.file.id}&page=${localState.currentPage}&annotate&width=400`}),
									FIGCAPTION(BUTTON({class: "reanalyze", "data-id": localState.currentPage}, "Reanalyze"),),
						])),
							DIV({class: 'loading'}, "Loading"),
						]),
				]),
			] // end of analysis-results__listing
		]), // end of analysis-results
	]));

	document.querySelectorAll(".loadable").forEach(elem => elem.classList.toggle(
		"pending", !elem.querySelector("img").complete
	));
}

on("change", "#newFile", async (e) => {
	e.preventDefault();
	submittedFile = DOM("#newFile").files[0];
	DOM("#newFile").style.display = "none";
	ws_sync.send({
		"cmd": "upload",
		"name": submittedFile.name,
	});
	render(stateSnapshot);
});

function imgLoaded(e) {
	e.currentTarget.closest(".loadable").classList.remove("pending");
}


on("click", "#pagesinfo li", async (e) => {
	localState.currentPage = e.match.dataset.page;
	render(stateSnapshot);
});

on("click", ".delete", simpleconfirm("Delete this analysis", async function (e) {
	const id = e.match.dataset.id;
	ws_sync.send({"cmd": "delete_analysis", "id": +id});
}));

on("click", ".reanalyze", simpleconfirm("Reanalyze this page", async function (e) {
	const id = e.match.dataset.id;
	ws_sync.send({"cmd": "reanalyze", "id": +id});
}));

on("toggle", "details", function (e) {
	if (!e.match.open) return;
	e.match.scrollIntoView({behavior: "smooth", block: "center"});
	document.querySelectorAll("details").forEach(elem => {
		if (elem !== e.match) elem.open = false;
	});
}, {capture: true});

export async function sockmsg_upload(msg) {
	ws_sync.send({cmd: "chgrp", group: msg.group});
	history.replaceState(null, "", `/analysis?id=${msg.group}`);
	const resp = await fetch(`/upload?id=${msg.upload_id}`, {
		method: "POST",
		body: submittedFile,
	});
	render({}); // Clear the page
};

export function sockmsg_upload_status(msg) {
	render(stateSnapshot);
}
