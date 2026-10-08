#!/usr/bin/env bash
# Steg 11: obevakad batch. Kor i tmux:  tmux new -s batch  ->  ./steg/11-batch.sh
# Gor i ordning, utan fragor, med allt loggat till /srv/llm/batch-<tid>.log:
#   1. variant b-prefill  -> roktest 1,2,3,5 -> matserie B-prefill
#   2. variant b-samtidig -> roktest        -> matserie B-samtidig
#   3. tillbaka till baslinjen B (recept/qwen38-27b.args) -> roktest -> eval exempel (B)
#   4. byt till C (nvidia__Qwen3.6-35B-A3B-NVFP4, recept/qwen36-35b-a3b.args) -> roktest
#      -> matserie C -> eval exempel (C)
#   5. tillbaka till B
# Ett steg som misslyckas stoppar inte resten; summeringen sist visar vad som gick.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export JA=1
LOGG="/srv/llm/batch-$(date +%Y%m%d-%H%M).log"
exec > >(tee -a "$LOGG") 2>&1
echo "Batch start $(date '+%F %T'), logg $LOGG"
R=()
steg() { local namn="$1"; shift; echo; echo "########## $(date +%T) $namn ##########"; if "$@"; then R+=("OK   $namn"); else R+=("FEL  $namn"); fi; }

steg "variant b-prefill"       ./steg/10-variant.sh b-prefill
steg "bench B-prefill"         ./steg/09-bench.sh B-prefill
steg "variant b-samtidig"      ./steg/10-variant.sh b-samtidig
steg "bench B-samtidig"        ./steg/09-bench.sh B-samtidig
steg "tillbaka till B"         ./steg/10-variant.sh recept/qwen38-27b.args
steg "eval exempel B"          ./eval.py eval/exempel.jsonl --etikett B --svar /srv/llm/svar
steg "byt till C"              ./byt-modell.sh nvidia__Qwen3.6-35B-A3B-NVFP4 recept/qwen36-35b-a3b.args
steg "bench C"                 ./steg/09-bench.sh C
steg "eval exempel C"          ./eval.py eval/exempel.jsonl --etikett C --svar /srv/llm/svar
steg "tillbaka till B"         ./byt-modell.sh nvidia__Qwen3.8-27B-NVFP4 recept/qwen38-27b.args

echo; echo "########## $(date +%T) SUMMERING ##########"
printf '%s\n' "${R[@]}"
echo "Resultat: /srv/llm/bench.csv, /srv/llm/eval.csv, logg $LOGG"
