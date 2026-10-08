#!/usr/bin/env bash
# Hamtar en modell fran Hugging Face till /srv/models/<org>__<modell>, last till
# en commit, och raknar checksummor.
#   ./hamta.sh <org/modell> [revision]
# Kor garna i tmux: stora modeller tar timmar. Revisionen (commit-hash, tagg
# eller gren) slas alltid upp till en full commit-hash fore hamtningen; gar det
# inte (natet?) stoppar skriptet, sa att ingen olast hamtning sker.
# Hamtningen sker till <mal>.del-<commit> och publiceras (mv) forst nar
# checksummor och .kalla ar skrivna. En avbruten hamtning atertas med samma
# kommando. start.sh startar bara modeller som har .kalla och .sha256.
set -euo pipefail
REPO="${1:-}"; REV="${2:-main}"
[[ "$REPO" == */* ]] || { echo "Anvandning: $0 <org/modell> [revision]" >&2; exit 1; }
NAMN="${REPO//\//__}"
MAL="/srv/models/$NAMN"

HF="$(command -v hf || command -v huggingface-cli || true)"
[[ -n "$HF" ]] || { echo "Varken 'hf' eller 'huggingface-cli' finns. Installera: pipx install 'huggingface_hub[cli]'" >&2; exit 1; }
[[ -e "$MAL" ]] && { echo "$MAL finns redan. Ta bort den (och $MAL.sha256, $MAL.kalla) forst om den ska hamtas om." >&2; exit 1; }

# Los upp revisionen till en full commit-hash via API:et.
if [[ "$REV" =~ ^[0-9a-f]{40}$ ]]; then
  COMMIT="$REV"
else
  COMMIT="$(curl -s -m 15 "https://huggingface.co/api/models/$REPO/revision/$REV" | grep -o '"sha":"[0-9a-f]\{40\}"' | head -n1 | cut -d'"' -f4 || true)"
  [[ -n "$COMMIT" ]] || { echo "Kunde inte sla upp '$REV' for $REPO till en commit (natet? fel namn?). Ange en 40-teckens commit-hash fran modellsidan." >&2; exit 1; }
  echo "Revision '$REV' = $COMMIT. Anteckna den; den star ocksa i $MAL.kalla efterat."
fi
DEL="$MAL.del-${COMMIT:0:12}"

echo "Ledigt pa /srv: $(df -h --output=avail /srv | tail -n1 | tr -d ' ')"
echo "Hamtar $REPO@$COMMIT -> $DEL  (start $(date '+%T'))"
"$HF" download "$REPO" --revision "$COMMIT" --local-dir "$DEL"
echo "Nedladdning klar $(date '+%T')"

# Varje fils metadatafil (<del>/.cache/huggingface/download/<fil>.metadata) har
# commit-hashen pa forsta raden. Alla ska vara samma som den begarda.
AVVIK="$(find "$DEL/.cache" -name '*.metadata' -exec head -n1 {} \; 2>/dev/null | sort -u | grep -vx "$COMMIT" || true)"
if [[ -n "$AVVIK" ]]; then
  echo "STOPP: filer i $DEL kommer fran andra revisioner an $COMMIT:" >&2; echo "$AVVIK" >&2
  echo "Ta bort $DEL och kor om." >&2; exit 1
fi
[[ -n "$(find "$DEL/.cache" -name '*.metadata' 2>/dev/null | head -n1)" ]] || { echo "STOPP: inga metadatafiler i $DEL; hamtningen ser ofullstandig ut." >&2; exit 1; }

echo "Raknar checksummor (tar nagra minuter for stora modeller)..."
( cd "$DEL" && find . -type f ! -path './.cache/*' -exec sha256sum {} + | sort -k2 ) > "$DEL.sha256"
{
  echo "kalla:    $REPO"
  echo "revision: $COMMIT"
  echo "hamtad:   $(date '+%F %T')"
  echo "storlek:  $(du -sh --exclude=.cache "$DEL" | cut -f1)"
  echo "filer:    $(wc -l < "$DEL.sha256")"
} > "$DEL.kalla"
mv "$DEL.sha256" "$MAL.sha256"; mv "$DEL.kalla" "$MAL.kalla"; mv "$DEL" "$MAL"
cat "$MAL.kalla"

# Kand fallgrop: vissa ompaketerade modeller har trunkering inbyggd i tokenizern,
# sa att langa prompter klipps tyst (sett i unsloth-repon).
if [[ -f "$MAL/tokenizer.json" ]]; then
  python3 - "$MAL/tokenizer.json" <<'PY'
import json, sys
t = json.load(open(sys.argv[1])).get("truncation")
print("tokenizer truncation:", t, "-> OK" if t is None else "-> VARNING: ska vara null, annars klipps langa prompter")
PY
fi
LIC=( "$MAL"/[Ll][Ii][Cc][Ee][Nn]* )
if [[ -e "${LIC[0]}" ]]; then echo "Licensfil finns: ${LIC[0]}"; else echo "OBS: ingen licensfil i modellkatalogen, spara modellkortets licens for hand"; fi
echo "I llm.env:  LLM_MODEL_DIR=$NAMN"
