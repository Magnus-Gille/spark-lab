#!/usr/bin/env bash
# Steg 16: skapar en andra motor som instans llm@<namn> bredvid tjansten llm.
#   ./steg/16-instans.sh <namn> <modellkatalog> <recept.args> <port> <gpu-andel> [bildtagg]
#   ./steg/16-instans.sh embed google__embeddinggemma-2 recept/embeddinggemma-2.args 8002 0.05 vllm/vllm-openai:cu134-nightly-...
# Kopierar llm.env (samma nyckel) till /etc/llm/<namn>.env med ny port, modell,
# LLM_NAME=<namn> och (om angiven) annan bild som sparats med bild.sh; skriver
# /etc/llm/<namn>.args med given --gpu-memory-utilization,
# installerar llm@.service och startar instansen. OBS: tjansten llm maste ocksa
# fa en --gpu-memory-utilization sa att summan <= ca 0.85, annars OOM.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
N="${1:?namn}"; M="${2:?modellkatalog}"; R="${3:?recept}"; P="${4:?port}"; U="${5:?gpu-andel, t.ex. 0.40}"; B="${6:-}"
ID=""
if [[ -n "$B" ]]; then
  K="$(grep -l "^tagg: *$B\$" /srv/images/*.kalla 2>/dev/null | head -n1)"
  [[ -n "$K" ]] || { echo "Bilden $B ar inte sparad med bild.sh" >&2; exit 1; }
  ID="$(sed -n 's/^id: *//p' "$K")"
fi
[[ -f "/srv/models/$M.kalla" ]] || { echo "/srv/models/$M ar inte hamtad" >&2; exit 1; }
[[ -f "$R" ]] || { echo "Hittar inte $R" >&2; exit 1; }
NU="$(grep -oE -- '--gpu-memory-utilization [0-9.]+' /etc/llm/serve.args | awk '{print $2}')"
echo "Plan: instans llm@$N: modell $M, recept $R, port $P, gpu-andel $U, bild ${B:-(samma som llm)}. Tjansten llm har nu ${NU:-?}; summan blir $(awk -v a="${NU:-0}" -v b="$U" 'BEGIN{print a+b}')."
read -r -p "Fortsatt? [j/N] " s; [[ "$s" == "j" ]] || { echo "Avbrutet."; exit 1; }
sudo install -o root -g root -m 755 start.sh /usr/local/lib/llm/start.sh
sudo install -o root -g root -m 644 llm@.service /etc/systemd/system/llm@.service
sudo sh -c "sed -e 's|^LLM_PORT=.*|LLM_PORT=$P|' -e 's|^LLM_MODEL_DIR=.*|LLM_MODEL_DIR=$M|' -e 's|^LLM_NAME=.*|LLM_NAME=$N|' /etc/llm/llm.env > /etc/llm/$N.env && chmod 600 /etc/llm/$N.env"
[[ -n "$B" ]] && sudo sed -i -e "s|^LLM_IMAGE=.*|LLM_IMAGE=$B|" -e "s|^LLM_IMAGE_ID=.*|LLM_IMAGE_ID=$ID|" "/etc/llm/$N.env"
sed -E "s|^--gpu-memory-utilization .*|--gpu-memory-utilization $U|" "$R" | sudo install -o root -g root -m 644 /dev/stdin "/etc/llm/$N.args"
sudo systemctl daemon-reload
LLM_ENV=/etc/llm/$N.env LLM_ARGS=/etc/llm/$N.args LLM_CONTAINER=llm-$N sudo -E /usr/local/lib/llm/start.sh --visa
sudo systemctl start "llm@$N"
echo "Startad. Folj med: journalctl -fu llm@$N   Mat: ./bench.py --url http://127.0.0.1:$P --etikett $N-parallell"
echo "Stoppa: sudo systemctl stop llm@$N"
