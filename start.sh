#!/usr/bin/env bash
# Startar inferensmotorn (vLLM) i Docker.
# Kors av systemd (llm.service) eller for hand.
#   ./start.sh          starta
#   ./start.sh --visa   skriv ut kommandot utan att kora (nyckeln maskad)
# Flera motorer samtidigt: llm@<namn>.service satter LLM_ENV=/etc/llm/<namn>.env,
# LLM_ARGS=/etc/llm/<namn>.args och LLM_CONTAINER=llm-<namn>; varje env-fil har
# egen LLM_PORT och egen --gpu-memory-utilization i sin args-fil (summa <= ca 0.85).
set -euo pipefail

ENV_FIL="${LLM_ENV:-/etc/llm/llm.env}"
ARG_FIL="${LLM_ARGS:-/etc/llm/serve.args}"

[[ -r "$ENV_FIL" ]] || { echo "Kan inte lasa $ENV_FIL (kor med sudo?)" >&2; exit 1; }
[[ -r "$ARG_FIL" ]] || { echo "Kan inte lasa $ARG_FIL" >&2; exit 1; }

set -a; . "$ENV_FIL"; set +a

: "${LLM_IMAGE:?LLM_IMAGE saknas i $ENV_FIL}"
: "${LLM_MODEL_DIR:?LLM_MODEL_DIR saknas i $ENV_FIL}"
: "${VLLM_API_KEY:?VLLM_API_KEY saknas i $ENV_FIL}"
LLM_NAME="${LLM_NAME:-kod}"
LLM_BIND="${LLM_BIND:-127.0.0.1}"
LLM_PORT="${LLM_PORT:-8000}"
LLM_ENTRYPOINT="${LLM_ENTRYPOINT:-vllm}"
: "${LLM_IMAGE_ID:?LLM_IMAGE_ID saknas i $ENV_FIL (skrivs ut av bild.sh)}"
LLM_CONTAINER="${LLM_CONTAINER:-llm}"
VISA=0; [[ "${1:-}" == "--visa" ]] && VISA=1

[[ -d "/srv/models/$LLM_MODEL_DIR" ]] || { echo "Modellkatalogen /srv/models/$LLM_MODEL_DIR finns inte" >&2; exit 1; }
[[ -f "/srv/models/$LLM_MODEL_DIR.kalla" && -f "/srv/models/$LLM_MODEL_DIR.sha256" ]] \
  || { echo "Modellen $LLM_MODEL_DIR ar inte fardigstalld (saknar .kalla/.sha256 fran hamta.sh)" >&2; exit 1; }

# Bilden ska finnas lokalt (ingen pull vid start) och, om LLM_IMAGE_ID ar satt,
# vara exakt den bild som frystes med bild.sh. Id overlever docker save/load,
# till skillnad fran digesten.
if ! ID_NU="$(docker image inspect "$LLM_IMAGE" --format '{{.Id}}' 2>/dev/null)"; then
  echo "Bilden $LLM_IMAGE finns inte lokalt. Las in den sparade filen: se README, Aterstallning utan nat" >&2; exit 1
fi
if [[ "$ID_NU" != "$LLM_IMAGE_ID" ]]; then
  echo "Bilden $LLM_IMAGE har id $ID_NU men llm.env kraver $LLM_IMAGE_ID" >&2; exit 1
fi

# serve.args: en flagga per rad. "--flagga varde" delas vid FORSTA blanktecknet
# (mellanslag eller tabb), sa JSON-varden behover inga citattecken.
# Rader som borjar med # hoppas over.
ARGS=()
while IFS= read -r rad || [[ -n "$rad" ]]; do
  rad="${rad#"${rad%%[![:space:]]*}"}"
  rad="${rad%"${rad##*[![:space:]]}"}"
  [[ -z "$rad" || "$rad" == \#* ]] && continue
  if [[ "$rad" =~ ^([^[:space:]]+)[[:space:]]+(.*)$ ]]; then
    ARGS+=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")
  else
    ARGS+=("$rad")
  fi
done < "$ARG_FIL"

# Ordsplittring utan globbning (set -f) for de extra docker-flaggorna.
set -f
# shellcheck disable=SC2206
EXTRA=( ${LLM_DOCKER_EXTRA:-} )
set +f

# API-nyckeln skickas som miljovariabel (-e utan varde tas fran var miljo),
# inte som --api-key, sa den syns inte i ps eller i motorns startlogg.
# --ipc=host och ulimit-vardena ar samma som i NVIDIA:s Spark-playbook
# (dgx-spark-playbooks/nvidia/playbook-vllm/assets/sync-vllm-single-spark.sh):
# ett medvetet kompatibilitetsundantag, host-IPC ar en utokad rattighet.
# Bara den valda modellen monteras (skrivskyddad), inte hela /srv/models.
# --pull=never: bilden ska redan finnas lokalt (bild.sh), aldrig hamtas vid start.
CMD=(docker run --rm --name "$LLM_CONTAINER" --label spark-lab=1 --pull=never
  --gpus all --ipc=host
  --ulimit memlock=-1 --ulimit stack=67108864
  -e HF_HUB_OFFLINE=1
  -e VLLM_API_KEY
  -p "${LLM_BIND}:${LLM_PORT}:8000"
  -v "/srv/models/$LLM_MODEL_DIR:/models/$LLM_MODEL_DIR:ro"
  "${EXTRA[@]}"
  --entrypoint "$LLM_ENTRYPOINT"
  "$LLM_IMAGE"
  serve "/models/$LLM_MODEL_DIR"
  --served-model-name "$LLM_NAME"
  --host 0.0.0.0 --port 8000
  "${ARGS[@]}")

# --visa: bara visa, inget far andras (ingen container tas bort, inget startas).
if [[ $VISA -eq 1 ]]; then
  for a in "${CMD[@]}"; do
    [[ "$a" == *"$VLLM_API_KEY"* ]] && a='NYCKEL-DOLD'
    printf '%q ' "$a"
  done
  echo
  echo "(VLLM_API_KEY skickas som miljovariabel fran $ENV_FIL)"
  exit 0
fi

# Forst har borjar mutationerna. En gammal container med namnet llm tas bara
# bort om den ar var egen (etikett spark-lab); en frammande stoppar starten.
if docker container inspect "$LLM_CONTAINER" >/dev/null 2>&1; then
  if [[ "$(docker container inspect "$LLM_CONTAINER" --format '{{index .Config.Labels "spark-lab"}}')" == "1" ]]; then
    docker rm -f "$LLM_CONTAINER" >/dev/null
  else
    echo "En container som heter $LLM_CONTAINER finns redan och ar inte skapad av start.sh. Ta bort den for hand." >&2; exit 1
  fi
fi

exec "${CMD[@]}"
