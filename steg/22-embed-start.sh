#!/usr/bin/env bash
# Steg 22: hamtar den nattliga vLLM-bilden (om den saknas) och startar
# embeddingmodellen F som sidomodell llm@embed pa port 8002, sedan roktest.
# Kortkommando for: bild.sh + steg/16-instans.sh embed ... + steg/20-embed-test.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
BILD="vllm/vllm-openai:cu134-nightly-81198e97ba7eee2a22540caaa756b7fdddcb4d93"
if ! grep -qs "^tagg: *$BILD\$" /srv/images/*.kalla 2>/dev/null; then
  echo "== bild =="; ./bild.sh "$BILD" || exit 1
fi
echo "== instans llm@embed =="
./steg/16-instans.sh embed google__embeddinggemma-2 recept/embeddinggemma-2.args 8002 0.05 "$BILD" || exit 1
echo "== vantar pa /health pa 8002 (max 10 min) =="
for i in $(seq 1 120); do
  curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8002/health 2>/dev/null | grep -q 200 && { echo " redo efter $((i*5)) s"; break; }
  systemctl is-active --quiet llm@embed || { echo; echo "llm@embed DOG. Senaste logg:"; journalctl -u llm@embed --no-pager -n 40 | cut -c1-200; exit 1; }
  printf '.'; sleep 5
done
echo "== roktest =="
./steg/20-embed-test.sh 8002
