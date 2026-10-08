#!/usr/bin/env bash
# Steg 07: installerar tjansten med receptet for B och fyller i llm.env fran
# bild.sh:s och hamta.sh:s utdata. ANDRAR maskinen (install.sh). Fragar forst.
set -euo pipefail
cd "$(dirname "$0")/.."
MODELL=nvidia__Qwen3.8-27B-NVFP4
KALLA="$(ls -t /srv/images/vllm_vllm-openai_qwen38_*.kalla | head -n1)"
TAGG="$(sed -n 's/^tagg: *//p' "$KALLA")"
ID="$(sed -n 's/^id: *//p' "$KALLA")"
[[ -n "$TAGG" && "$ID" == sha256:* ]] || { echo "Hittar inte tagg/id i $KALLA" >&2; exit 1; }
[[ -f "/srv/models/$MODELL.kalla" ]] || { echo "/srv/models/$MODELL.kalla saknas, ar B hamtad?" >&2; exit 1; }

echo "Planerade andringar:"
echo "  1. ./install.sh recept/qwen38-27b.args   (program till /usr/local/lib/llm, llm.service, ny llm.env + serve.args)"
echo "  2. i /etc/llm/llm.env:"
echo "       LLM_IMAGE=$TAGG"
echo "       LLM_IMAGE_ID=$ID"
echo "       LLM_MODEL_DIR=$MODELL"
echo "  3. visa det sammansatta kommandot (start.sh --visa), inget startas"
read -r -p "Fortsatt? [j/N] " s; [[ "$s" == "j" ]] || { echo "Avbrutet."; exit 1; }

echo; echo "== 1. install.sh =="
./install.sh recept/qwen38-27b.args
echo; echo "== 2. llm.env =="
sudo sed -i -e "s|^LLM_IMAGE=.*|LLM_IMAGE=$TAGG|" -e "s|^LLM_IMAGE_ID=.*|LLM_IMAGE_ID=$ID|" -e "s|^LLM_MODEL_DIR=.*|LLM_MODEL_DIR=$MODELL|" /etc/llm/llm.env
sudo sed 's/^\(VLLM_API_KEY=\).*/\1<dold>/' /etc/llm/llm.env | grep -vE '^\s*(#|$)'
echo; echo "== 3. kommandot som kommer att koras =="
sudo /usr/local/lib/llm/start.sh --visa
echo
echo "Nasta: sudo systemctl enable --now llm   och sedan   journalctl -fu llm"
