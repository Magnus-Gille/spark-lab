#!/usr/bin/env bash
# Steg 12: offlineaterstart pa befintlig vard (README, test 6). Stoppar tjansten,
# tar bort bilden ur Docker, laser in den sparade filen, kontrollerar id, startar
# utan att nagot hamtas, och kor roktest 1,2,3,5. Reboot (test 7) gors for hand efterat.
# ANDRAR Docker (bild bort och in) och startar om tjansten. Fragar forst.
set -uo pipefail
cd /usr/local/lib/llm 2>/dev/null || cd "$(dirname "$0")/.." || exit 1
TAGG="$(sudo sed -n 's/^LLM_IMAGE=//p' /etc/llm/llm.env | tr -d '"')"
ID="$(sudo sed -n 's/^LLM_IMAGE_ID=//p' /etc/llm/llm.env | tr -d '"')"
FIL="$(grep -l "^tagg: *$TAGG\$" /srv/images/*.kalla 2>/dev/null | head -n1 | xargs -r sed -n 's/^fil: *\([^ ]*\).*/\1/p')"
[[ -n "$TAGG" && -n "$ID" && -f "$FIL" ]] || { echo "Hittar inte tagg/id/fil (tagg=$TAGG fil=$FIL)" >&2; exit 1; }
echo "Plan: stoppa llm, docker image rm $TAGG, docker load < $FIL, kontrollera id $ID, starta, roktest."
read -r -p "Fortsatt? [j/N] " s; [[ "$s" == "j" ]] || { echo "Avbrutet."; exit 1; }
R=0
echo "== 1. verifiera =="; ./verifiera.sh || R=1
echo "== 2. stoppa =="; sudo systemctl stop llm; docker ps -a --filter name=llm --format '{{.Names}} {{.Status}}'; docker container inspect llm >/dev/null 2>&1 && { echo "container llm finns kvar" >&2; R=1; }
echo "== 3. ta bort bilden =="; docker image rm "$TAGG" >/dev/null && echo "borttagen"; docker image inspect "$ID" >/dev/null 2>&1 && { echo "bild-id finns kvar i Docker (fler taggar?)" >&2; docker images --no-trunc | grep "${ID#sha256:}" | head -3; R=1; } || echo "id:t ar borta ur Docker"
echo "== 4. las in filen =="; case "$FIL" in *.zst) zstd -dc "$FIL" | docker load;; *.gz) gzip -dc "$FIL" | docker load;; esac
echo "== 5. id efter inlasning =="; NU="$(docker image inspect "$TAGG" --format '{{.Id}}' 2>/dev/null)"; echo "$NU"; [[ "$NU" == "$ID" ]] && echo "= LLM_IMAGE_ID, OK" || { echo "SKILJER SIG fran LLM_IMAGE_ID $ID" >&2; R=1; }
echo "== 6. starta utan nat (bilden far inte hamtas: --pull=never) =="; sudo systemctl start llm
for i in $(seq 1 180); do curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/health 2>/dev/null | grep -q 200 && { echo " redo efter $((i*5)) s"; break; }; systemctl is-active --quiet llm || { echo; echo "TJANSTEN DOG"; ./diag.sh fel 40; R=1; break; }; printf '.'; sleep 5; done
echo "== 7. roktest =="; ./rok.py --hoppa 4 || R=1
echo; [[ $R -eq 0 ]] && echo "OFFLINEATERSTART OK. Test 7: sudo reboot, logga in, cd /usr/local/lib/llm && ./diag.sh" || echo "AVVIKELSER, se ovan."
exit $R
