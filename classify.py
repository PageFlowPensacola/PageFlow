from river import compose
from river import feature_extraction
from river import naive_bayes
import os
import sys
import base64
import collections
import pprint
import pickle
import time
import json

start = time.monotonic()
model = compose.Pipeline(
        ("tokenize", feature_extraction.BagOfWords(lowercase=False, ngram_range=(1, 2))),
        ("nb", naive_bayes.ComplementNB(alpha=1))
    )

""" input = {
		"cmd": "train",
    "pageref": "42:3",
    "text": "When I was a lad I served a term As",
    "msgid": "1"
} """

try:
	print("Ready", file=sys.stderr, flush=True)
	while 1:
		print("Waiting", file=sys.stderr, flush=True)
		msg = json.loads(input()) # input looks for one line of txt followed by newline
		if ("cmd" not in msg):
			print(json.dumps({"status": "error", "msgid": msg["msgid"], "error": "No command"}))
			continue
		if msg["cmd"] == "train":
			model.learn_one(msg["text"], msg["pageref"])
			print(json.dumps({"status": "ok", "msgid": msg["msgid"], "model": base64.b64encode(pickle.dumps(model)).decode("utf-8")}))
		elif msg["cmd"] == "classify":
			res = model.predict_proba_one(msg["text"])
			print(json.dumps({"result": res, "msgid": msg["msgid"]}))
		elif msg["cmd"] == "load":
			model = pickle.loads(base64.b64decode(msg["model"]))
			print(json.dumps({"status": "ok", "msgid": msg["msgid"]}))
		else:
			print(json.dumps({"status": "error", "msgid": msg["msgid"], "error": "Unknown command"}))
except EOFError: pass
