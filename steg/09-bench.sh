#!/usr/bin/env bash
# Steg 09: matserie for den kandidat som kor. Argument: etikett (B, C, A...).
#   ./steg/09-bench.sh B
# Fyra matpunkter, resultat i /srv/llm/bench.csv. Tar 10-20 minuter.
# Kor inga hamtningar eller komprimeringar samtidigt.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
E="${1:?Ange etikett, t.ex. B}"
FEL=0
k() { echo; echo "===== $* ====="; ./bench.py "$@" || FEL=1; }
k --etikett "$E-tom"
k --etikett "$E-32k-kall"   --djup 32000
k --etikett "$E-32k-varm"   --djup 32000 --varm
k --etikett "$E-32k-x4"     --djup 32000 --samtidiga 4
echo
echo "===== sammanfattning ($E) ====="
python3 - "$E" <<'PY'
import csv, sys
r = [x for x in csv.DictReader(open("/srv/llm/bench.csv")) if x["etikett"].startswith(sys.argv[1] + "-")]
print("%-12s %6s %4s %5s %8s %8s %8s %8s %4s" % ("etikett", "djup", "sam", "cache", "ttft_s", "tok/s/st", "tok/s", "ut_tok", "fel"))
for x in r[-4:]:
    print("%-12s %6s %4s %5s %8s %8s %8s %8s %4s" % (x["etikett"], x["djup"], x["samtidiga"], x["cache"], x["ttft_s"], x["tok_s_per_strom"], x["tok_s_totalt"], x["ut_tokens"], x["fel"]))
PY
[[ $FEL -eq 0 ]] && echo "KLART utan fel." || echo "KLART, men minst en matpunkt hade fel: se ovan."
