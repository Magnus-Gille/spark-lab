#!/usr/bin/env bash
# Steg 10: byter serve.args till en variant, startar om tjansten, vantar pa att
# API:et svarar och kor roktest 1-3 och 5. Darefter: ./steg/09-bench.sh <etikett>
#   ./steg/10-variant.sh b-mtp          (recept/varianter/b-mtp.args)
#   ./steg/10-variant.sh recept/qwen38-27b.args   (tillbaka till baslinjen)
# ANDRAR /etc/llm/serve.args och startar om tjansten. Fragar forst.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
V="${1:?Ange variant}"
FIL="$V"; [[ -f "$FIL" ]] || FIL="recept/varianter/$V.args"
[[ -f "$FIL" ]] || { echo "Hittar inte $FIL" >&2; exit 1; }
echo "Skillnad mot nuvarande /etc/llm/serve.args:"
diff <(grep -vE '^\s*(#|$)' /etc/llm/serve.args) <(grep -vE '^\s*(#|$)' "$FIL") && echo "(ingen skillnad)"
if [[ "${JA:-}" == "1" ]]; then echo "(JA=1: ingen fraga)"; else
  read -r -p "Byt till $FIL och starta om tjansten? [j/N] " s; [[ "$s" == "j" ]] || { echo "Avbrutet."; exit 1; }
fi
sudo install -o root -g root -m 644 "$FIL" /etc/llm/serve.args
sudo systemctl restart llm
echo "Startar om, vantar pa /health (max 15 min)..."
for i in $(seq 1 180); do
  if curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/health 2>/dev/null | grep -q 200; then echo " redo efter $((i*5)) s"; break; fi
  if ! systemctl is-active --quiet llm; then echo; echo "TJANSTEN DOG. Senaste fel:"; ./diag.sh fel 40; exit 1; fi
  printf '.'; sleep 5
done
./rok.py --hoppa 4
