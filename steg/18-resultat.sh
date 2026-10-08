#!/usr/bin/env bash
# Steg 18: sammanfattar dagens matningar och evals pa en skarm. Bara lasning.
set -uo pipefail
python3 - <<'PY'
import csv, os
b = "/srv/llm/bench.csv"; e = "/srv/llm/eval.csv"
if os.path.exists(b):
    r = list(csv.DictReader(open(b)))
    print("== bench.csv: %d rader ==" % len(r))
    print("%-20s %6s %4s %5s %8s %10s %8s %4s %s" % ("etikett", "djup", "sam", "cache", "ttft_s", "tok/s/anv", "tok/s", "fel", "args"))
    for x in r:
        print("%-20s %6s %4s %5s %8s %10s %8s %4s %s" % (x["etikett"], x["djup"], x["samtidiga"], x["cache"], x["ttft_s"], x["tok_s_per_strom"], x["tok_s_totalt"], x["fel"], x.get("args_hash", "")[:6]))
if os.path.exists(e):
    r = list(csv.DictReader(open(e)))
    print("\n== eval.csv ==")
    for x in r:
        if x["id"] == "SUMMA" or x["status"] in ("fail", "timeout", "fel"):
            print("%-10s %-20s %-8s %s" % (x["etikett"], x["id"], x["status"], x["detalj"][:110]))
PY
echo; echo "Svar och testloggar: ls /srv/llm/svar/*/"
