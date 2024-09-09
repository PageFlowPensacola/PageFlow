import {lindt, on, DOM, replace_content} from "https://rosuav.github.io/choc/factory.js";
const {DETAILS, DIV, H1, SUMMARY} = lindt; //autoimport

let testAnalysisState = {
	"cmd": "update",
	"file": {
			"created": "2024-09-09 12:15:09.734938-05",
			"filename": "MiniDealJacketMissing.pdf",
			"id": 128,
			"page_count": 5
	},
	"signatories": {
			"0": "Unspecified",
			"122": "Odometer Reading",
			"123": "Buyer",
			"124": "Person Signing",
			"125": "VIN",
			"126": "Transferor",
			"127": "Buyer One",
			"128": "Buyer Two",
			"129": "Seller One"
	},
	"template_names": [
			{
					"id": 156,
					"name": "ApplicationCertificateofTitleTemplate.pdf"
			},
			{
					"id": 154,
					"name": "OdometerDisclosureTemplate.pdf"
			},
			{
					"id": 157,
					"name": "TitleReassignmentTemplate.pdf"
			}
	],
	"templates": {
			"0": {
					"1": [
							{
									"audit_rects": {},
									"scores": [],
									"seq_idx": 0
							}
					]
			},
			"154": {
					"1": [
							{
									"audit_rects": [
											{
													"template_signatory_id": 125,
													"transition_score": 227,
													"x1": 409,
													"x2": 1650,
													"y1": 1415,
													"y2": 1516
											},
											{
													"template_signatory_id": 124,
													"transition_score": 72,
													"x1": 464,
													"x2": 1597,
													"y1": 586,
													"y2": 669
											},
											{
													"template_signatory_id": 126,
													"transition_score": 314,
													"x1": 999,
													"x2": 2130,
													"y1": 2025,
													"y2": 2145
											},
											{
													"template_signatory_id": 124,
													"transition_score": 289,
													"x1": 993,
													"x2": 2137,
													"y1": 2148,
													"y2": 2274
											},
											{
													"template_signatory_id": 123,
													"transition_score": 248,
													"x1": 408,
													"x2": 2128,
													"y1": 2349,
													"y2": 2434
											},
											{
													"template_signatory_id": 123,
													"transition_score": 250,
													"x1": 408,
													"x2": 1592,
													"y1": 2738,
													"y2": 2826
											},
											{
													"template_signatory_id": 122,
													"transition_score": 48,
													"x1": 1308,
													"x2": 1742,
													"y1": 681,
													"y2": 746
											},
											{
													"template_signatory_id": 0,
													"transition_score": 36,
													"x1": 410,
													"x2": 999,
													"y1": 1308,
													"y2": 1414
											}
									],
									"scores": [
											{
													"difference": 2,
													"signatory": 125,
													"status": "Unsigned"
											},
											{
													"difference": 162,
													"signatory": 124,
													"status": "Signed"
											},
											{
													"difference": 194,
													"signatory": 126,
													"status": "Signed"
											},
											{
													"difference": 154,
													"signatory": 124,
													"status": "Signed"
											},
											{
													"difference": 128,
													"signatory": 123,
													"status": "Signed"
											},
											{
													"difference": 252,
													"signatory": 123,
													"status": "Signed"
											},
											{
													"difference": 138,
													"signatory": 122,
													"status": "Signed"
											},
											{
													"difference": 2,
													"signatory": 0,
													"status": "Unsigned"
											}
									],
									"seq_idx": 1
							}
					]
			},
			"156": {
					"1": [
							{
									"audit_rects": [
											{
													"template_signatory_id": 0,
													"transition_score": 49,
													"x1": 266,
													"x2": 872,
													"y1": 433,
													"y2": 527
											}
									],
									"scores": [
											{
													"difference": 13,
													"signatory": 0,
													"status": "Unsigned"
											}
									],
									"seq_idx": 3
							}
					],
					"2": [
							{
									"audit_rects": [
											{
													"template_signatory_id": 127,
													"transition_score": 198,
													"x1": 267,
													"x2": 1186,
													"y1": 2511,
													"y2": 2576
											},
											{
													"template_signatory_id": 128,
													"transition_score": 240,
													"x1": 1337,
													"x2": 2284,
													"y1": 2502,
													"y2": 2586
											},
											{
													"template_signatory_id": 129,
													"transition_score": 4,
													"x1": 615,
													"x2": 1365,
													"y1": 439,
													"y2": 516
											}
									],
									"scores": [
											{
													"difference": 60,
													"signatory": 127,
													"status": "Unclear"
											},
											{
													"difference": 4,
													"signatory": 128,
													"status": "Unsigned"
											},
											{
													"difference": 278,
													"signatory": 129,
													"status": "Signed"
											}
									],
									"seq_idx": 4
							}
					]
			},
			"157": {
					"1": [
							{
									"audit_rects": [],
									"scores": [],
									"seq_idx": 2
							}
					]
			}
	}
};

let state = [
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
	{
		"summary": "bla bla bla",
		"detail":	"yada yada yada",
	},
];
replace_content("main", [
	DIV(H1("Test Analysis State")),
	DIV({style: "border: 1px solid red;display:flex;flex-wrap:wrap; flex-direction: column; height: 80vh; width: 90vw; overflow: scroll"},state.map((item) => {
		return DETAILS([SUMMARY(`${item.summary}`), DIV({style: "height: 300px; width: 300px; border: 1px solid #777; overflow: scroll"},item.detail)]);
	})),
]);
