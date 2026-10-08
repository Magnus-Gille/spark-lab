#!/usr/bin/env bash
# Steg 19: hamtar embeddingmodellen F (google/embeddinggemma-2) och reserven
# (embeddinggemma-300m), samt vLLM:s nattliga arm64-bild som har stodet for F.
# Laste revisioner 2026-10-08. Ca 1,5 + 1,2 GB modeller plus bilden.
set -euo pipefail
cd "$(dirname "$0")/.."
./hamta.sh google/embeddinggemma-2    914f7f89142e33e77833254d9c9b90c3cef7303b
# Reserven ligger under Gemma-licensen och ar gated pa Hugging Face: kraver
# inloggning (hf auth login) och godkand licens. Hoppas over om den inte gar att hamta.
./hamta.sh google/embeddinggemma-300m 57c266a740f537b4dc058e1b0cda161fd15afa75 \
  || echo "OBS: embeddinggemma-300m (reserv) kunde inte hamtas, troligen gated. Fortsatter utan den."
[[ -e /srv/models/google__embeddinggemma-300m.del-57c266a740f5 ]] && rm -rf /srv/models/google__embeddinggemma-300m.del-57c266a740f5
./bild.sh vllm/vllm-openai:cu134-nightly-81198e97ba7eee2a22540caaa756b7fdddcb4d93
echo "KLART: F hamtad. Starta som sidomodell:"
echo "  ./steg/16-instans.sh embed google__embeddinggemma-2 recept/embeddinggemma-2.args 8002 0.05 vllm/vllm-openai:cu134-nightly-81198e97ba7eee2a22540caaa756b7fdddcb4d93"
