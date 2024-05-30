from river import compose
from river import feature_extraction
from river import naive_bayes
import os
import sys
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
try:
    with open("model.dat", "rb") as m: model = pickle.load(m)
except FileNotFoundError:
    pass

""" input = {
    "pageref": "42:3",
    "text": "When I was a lad I served a term As",
    "msgid": "1",
} """

try:
    print("Ready", file=sys.stderr, flush=True)
    while 1:
        print("Waiting", file=sys.stderr, flush=True)
        msg = json.loads(input()) # input looks for one line of txt followed by newline
        if ("pageref" in msg):
            model.learn_one(msg["text"], msg["pageref"])
            with open("model.dat", "wb") as m:
                pickle.dump(model, m)
            print(json.dumps({"status": "ok", "msgid": msg["msgid"]}))
        else:
            res = model.predict_proba_one(msg["text"])
            print(json.dumps({"result": res, "msgid": msg["msgid"]}))
except EOFError: pass
