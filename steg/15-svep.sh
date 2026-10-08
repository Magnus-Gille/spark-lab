#!/usr/bin/env bash
# Steg 15: samtidighetssvep for kapacitetstabellen: 1, 2, 4, 8 strommar vid 8k
# kontext (kall), plus 8 strommar vid 32k. Kor pa en variant med max-num-seqs 8
# (b-samtidig), annars koar strom 5-8. Argument: etikett. Ca 30 min.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
E="${1:?Ange etikett, t.ex. B-svep}"
for n in 1 2 4 8; do ./bench.py --etikett "$E-8k-x$n" --djup 8000 --samtidiga "$n" --varv 3 || true; done
./bench.py --etikett "$E-32k-x8" --djup 32000 --samtidiga 8 --varv 2 || true
echo; echo "===== $E ====="
python3 - "$E" <<'PY'
import csv, sys
r = [x for x in csv.DictReader(open("/srv/llm/bench.csv")) if x["etikett"].startswith(sys.argv[1] + "-")]
print("%-14s %6s %4s %8s %10s %8s %6s" % ("etikett", "djup", "sam", "ttft_s", "tok/s/anv", "tok/s", "fel"))
for x in r: print("%-14s %6s %4s %8s %10s %8s %6s" % (x["etikett"], x["djup"], x["samtidiga"], x["ttft_s"], x["tok_s_per_strom"], x["tok_s_totalt"], x["fel"]))
PY
