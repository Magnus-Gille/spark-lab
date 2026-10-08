#!/usr/bin/env bash
# Steg 14: kapacitetssiffror for den motor som kor: minne for vikter, KV-cache i
# tokens, max samtidighet vid full kontext, samt hur manga anvandare som ryms vid
# olika kontextstorlekar. Bara lasning (journalctl, free, nvidia-smi).
set -uo pipefail
L="$(journalctl -u llm --no-pager -o cat 2>/dev/null | tail -n 4000)"
h() { echo "$L" | grep -oE "$1" | tail -n1 | grep -oE '[0-9][0-9,.]*' | tr -d ',' | head -n1; }
VIKT="$(h 'Model loading took [0-9.]+ GiB')"
KVGIB="$(h 'Available KV cache memory: [0-9.]+ GiB')"
KVTOK="$(h 'KV cache size: [0-9,]+ tokens')"
MAXLEN="$(h 'Maximum concurrency for [0-9,]+ tokens')"
CONC="$(echo "$L" | grep -oE 'Maximum concurrency for [0-9,]+ tokens per request: [0-9.]+x' | tail -n1 | grep -oE '[0-9.]+x' | tr -d x)"
# Bara riktiga flaggrader (inte kommentarer som namner samma flagga).
UTIL="$(grep -vE '^\s*#' /etc/llm/serve.args | grep -oE -- '--gpu-memory-utilization [0-9.]+' | awk '{print $2}' | head -n1)"
SEQS="$(grep -vE '^\s*#' /etc/llm/serve.args | grep -oE -- '--max-num-seqs [0-9]+' | awk '{print $2}' | head -n1)"
MODELL="$(sudo sed -n 's/^LLM_MODEL_DIR=//p' /etc/llm/llm.env)"
TOT="$(free -g | awk '/^Mem:/{print $2}')"
echo "== Motor som kor: $MODELL =="
printf '%-34s %s\n' "minne totalt (delat CPU/GPU)" "${TOT} GiB"
printf '%-34s %s\n' "gpu-memory-utilization" "${UTIL:-?}  (vLLM:s budget ca $(awk -v t="$TOT" -v u="${UTIL:-0}" 'BEGIN{printf "%.0f", t*u}') GiB)"
printf '%-34s %s\n' "vikter (Model loading took)" "${VIKT:-?} GiB"
printf '%-34s %s\n' "KV-cache tillganglig" "${KVGIB:-?} GiB = ${KVTOK:-?} tokens"
printf '%-34s %s\n' "max-model-len" "${MAXLEN:-?} tokens, max samtidighet vid full kontext ${CONC:-?}x"
printf '%-34s %s\n' "max-num-seqs (tak for samtidiga)" "${SEQS:-?}"
if [[ -n "$KVTOK" ]]; then
  echo; echo "== Anvandare som ryms i KV-cachen samtidigt (kontext per anvandare, inkl. svar) =="
  for k in 8000 16000 32000 65536 131072 262144; do
    n=$(( KVTOK / k )); printf '  %7d tokens: %3d st%s\n' "$k" "$n" "$( [[ -n "$SEQS" && $n -gt $SEQS ]] && echo "  (begransas till $SEQS av max-num-seqs)" )"
  done
  B="$(awk -v g="$KVGIB" -v t="$KVTOK" 'BEGIN{printf "%.0f", g*1073741824/t}')"
  echo "  (KV per token ca ${B} byte; prefixcache gor att delad kontext bara raknas en gang)"
fi
echo; echo "== Flera modeller samtidigt (vikter ur /srv/models/*.kalla, resten blir KV) =="
for k in /srv/models/*.kalla; do printf '  %-40s %s\n' "$(basename "$k" .kalla)" "$(sed -n 's/^storlek: *//p' "$k")"; done
echo "  Tva motorer kraver var sin --gpu-memory-utilization med summa <= ca 0.85 och olika LLM_PORT;"
echo "  KV-cachen (anvandare x kontext) delas da upp. Exempel: B 0.45 + C 0.40 ger vardera ca $(awk -v t="$TOT" 'BEGIN{printf "%.0f", t*0.45-20}') resp. $(awk -v t="$TOT" 'BEGIN{printf "%.0f", t*0.40-22}') GiB KV."
echo; echo "== nvidia-smi =="; nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu,temperature.gpu,power.draw --format=csv,noheader 2>/dev/null
echo "== free =="; free -h | sed -n '1,2p'
