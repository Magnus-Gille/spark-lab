#!/usr/bin/env bash
# Byter modell (och recept, och vid behov bild) for tjansten, startar om, vantar
# pa att API:et svarar och kor roktest 1-3 och 5.
#   ./byt-modell.sh <modellkatalog> <recept.args> [bildtagg]
#   ./byt-modell.sh nvidia__Qwen3.6-35B-A3B-NVFP4 recept/qwen36-35b-a3b.args
#   ./byt-modell.sh nvidia__Qwen3.8-27B-NVFP4 recept/qwen38-27b.args vllm/vllm-openai:qwen38
# Modellkatalogen ar namnet under /srv/models (skapas av hamta.sh). Bildtaggen
# maste vara sparad med bild.sh (id hamtas fran /srv/images/*.kalla).
# ANDRAR /etc/llm/llm.env och /etc/llm/serve.args och startar om tjansten. Fragar forst.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
M="${1:?Ange modellkatalog under /srv/models}"; R="${2:?Ange recept (.args)}"; B="${3:-}"
[[ -f "/srv/models/$M.kalla" && -f "/srv/models/$M.sha256" ]] || { echo "/srv/models/$M ar inte hamtad med hamta.sh" >&2; exit 1; }
[[ -f "$R" ]] || { echo "Hittar inte $R" >&2; exit 1; }
ID=""
if [[ -n "$B" ]]; then
  K="$(grep -l "^tagg: *$B\$" /srv/images/*.kalla 2>/dev/null | head -n1)"
  [[ -n "$K" ]] || { echo "Bilden $B ar inte sparad med bild.sh (ingen .kalla med den taggen)" >&2; exit 1; }
  ID="$(sed -n 's/^id: *//p' "$K")"
fi
echo "Nu:   $(sudo sed -n 's/^LLM_MODEL_DIR=//p' /etc/llm/llm.env)  bild $(sudo sed -n 's/^LLM_IMAGE=//p' /etc/llm/llm.env)"
echo "Blir: $M  bild ${B:-(oforandrad)}"
echo "Skillnad i serve.args:"
diff <(grep -vE '^\s*(#|$)' /etc/llm/serve.args) <(grep -vE '^\s*(#|$)' "$R") && echo "(ingen skillnad)"
if [[ "${JA:-}" == "1" ]]; then echo "(JA=1: ingen fraga)"; else
  read -r -p "Byt och starta om tjansten? [j/N] " s; [[ "$s" == "j" ]] || { echo "Avbrutet."; exit 1; }
fi
sudo sed -i "s|^LLM_MODEL_DIR=.*|LLM_MODEL_DIR=$M|" /etc/llm/llm.env
[[ -n "$B" ]] && sudo sed -i -e "s|^LLM_IMAGE=.*|LLM_IMAGE=$B|" -e "s|^LLM_IMAGE_ID=.*|LLM_IMAGE_ID=$ID|" /etc/llm/llm.env
sudo install -o root -g root -m 644 "$R" /etc/llm/serve.args
sudo /usr/local/lib/llm/start.sh --visa >/dev/null || { echo "start.sh vagrar (se ovan). Inget startat om." >&2; exit 1; }
sudo systemctl restart llm
echo "Startar om, vantar pa /health (max 15 min; forsta starten av en ny modell kompilerar)..."
for i in $(seq 1 180); do
  if curl -s -m 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$(sudo sed -n 's/^LLM_PORT=//p' /etc/llm/llm.env | tr -d '"')/health" 2>/dev/null | grep -q 200; then echo " redo efter $((i*5)) s"; break; fi
  if ! systemctl is-active --quiet llm; then echo; echo "TJANSTEN DOG. Senaste fel:"; ./diag.sh fel 40; exit 1; fi
  printf '.'; sleep 5
done
./rok.py --hoppa 4
echo "Nasta: ./steg/09-bench.sh <etikett>   (eller ./bench.py --etikett <namn> ...)"
