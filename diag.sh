#!/usr/bin/env bash
# Diagnostik och felsokning. Varje delkommando ryms pa en skarm.
#   ./diag.sh            oversikt (borja alltid har)
#   ./diag.sh <del>      se listan langst ner, eller ./diag.sh hjalp
# Andrar ingenting pa maskinen, utom 'cache' som fragar forst.
set -uo pipefail
HAR="$(cd "$(dirname "$0")" && pwd)"
ENV_FIL=/etc/llm/llm.env
ARG_FIL=/etc/llm/serve.args

env_varde() { sudo sed -n "s/^$1=//p" "$ENV_FIL" 2>/dev/null | tr -d '"' | head -n1; }
PORT="$(env_varde LLM_PORT)"; PORT="${PORT:-8000}"
ADR="$(env_varde LLM_BIND)"; [[ -z "$ADR" || "$ADR" == "0.0.0.0" ]] && ADR=127.0.0.1
URL="${URL:-http://$ADR:$PORT}"
KEY="${KEY:-$(env_varde VLLM_API_KEY)}"

rubrik() { echo; echo "== $* =="; }
rad() { printf '%-26s %s\n' "$1" "$2"; }
# Nyckeln ges till curl via en konfiguration pa stdin (-K -), inte som argument.
hdr() { printf 'header = "Authorization: Bearer %s"\n' "$KEY"; }
api() { hdr | curl -s -K - -m "${2:-10}" "$URL$1"; }
kod() { hdr | curl -s -K - -m 10 -o /dev/null -w '%{http_code}' "$URL$1" 2>/dev/null; }
# Doljer den aktuella API-nyckeln i allt som skrivs ut. Ren bash: nyckeln
# passerar inget programs argv. Aldre nycklar (fore en rotation) kanns inte igen.
maskera() { local l; while IFS= read -r l; do if [[ -n "$KEY" ]]; then printf '%s\n' "${l//$KEY/<nyckel dold>}"; else printf '%s\n' "$l"; fi; done; }

oversikt() {
  rubrik "Oversikt $(date '+%F %T')"
  rad "Tjansten llm"       "$(systemctl is-active llm 2>&1) (sedan $(systemctl show llm -p ActiveEnterTimestamp --value 2>/dev/null))"
  rad "Omstarter"          "$(systemctl show llm -p NRestarts --value 2>/dev/null)"
  rad "Container"          "$(docker ps --filter name=^llm$ --format '{{.Status}}' 2>/dev/null | grep . || echo 'kor inte')"
  rad "Port $PORT lyssnar" "$(ss -tlnH 2>/dev/null | grep -q ":$PORT " && echo ja || echo NEJ)"
  rad "API /health"        "HTTP $(kod /health)"
  rad "API /v1/models"     "HTTP $(kod /v1/models)  $(api /v1/models 5 | grep -o '"id":"[^"]*"' | head -n1)"
  rad "Minne (tillgangligt)" "$(free -h | awk '/^Mem:/{print $7" av "$2}')   swap anvand: $(free -h | awk '/^Swap:/{print $3}')"
  rad "Sidcache"           "$(free -h | awk '/^Mem:/{print $6}')"
  rad "GPU"                "$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw --format=csv,noheader 2>/dev/null || echo 'nvidia-smi svarar inte')"
  rad "Disk /srv ledigt"   "$(df -h --output=avail /srv 2>/dev/null | tail -n1 | tr -d ' ')"
  rad "Last (1/5/15 min)"  "$(cut -d' ' -f1-3 /proc/loadavg)"
  rubrik "Senaste fel i loggen"
  journalctl -u llm -b --no-pager 2>/dev/null | grep -iE 'error|exception|traceback|killed|out of memory' | tail -n 5 | maskera | cut -c1-200 | grep . || echo "(inga)"
}

logg() {   # nyckelrader ur motorns logg; ./diag.sh logg 80 for fler rader
  rubrik "Nyckelrader ur loggen (denna uppstart). Saknade MTP-rader bevisar inte att MTP ar av: se ./diag.sh matvarden"
  journalctl -u llm -b --no-pager 2>/dev/null \
    | grep -iE 'error|warn|exception|traceback|kv cache|cache size|max_model_len|maximum concurrency|mtp|specul|draft|architecture|quantiz|nvfp4|cuda graph|loading weights|took .* s|startup complete|Uvicorn running|truncat|tool.?call|reasoning' \
    | tail -n "${1:-30}" | maskera | cut -c1-220 | grep . || echo "(inga rader, kor motorn? se ./diag.sh fel)"
}

fel() {
  rubrik "Tjanstens status"
  systemctl status llm --no-pager -n 0 2>&1 | head -n 8
  rubrik "Fel i motorns logg"
  journalctl -u llm -b --no-pager 2>/dev/null | grep -iE -B1 -A6 'traceback|error|exception|killed|out of memory|cuda' | tail -n "${1:-30}" | maskera | cut -c1-220 | grep . || echo "(inga)"
  echo "(vid omstartsslinga: ./diag.sh fel 300 | head -n 60 visar forsta felet, inte sista)"
  rubrik "Karnan: OOM, GPU-fel (Xid), varme"
  sudo dmesg -T 2>/dev/null | grep -iE 'out of memory|oom-kill|killed process|xid|nvrm|thermal|throttl' | tail -n 8 | cut -c1-200 | grep . || echo "(inga)"
}

minne() {
  rubrik "Minne (delat mellan CPU och GPU pa Sparken)"
  free -h
  rubrik "Storsta processerna"
  ps -eo rss,pid,comm --sort=-rss | head -n 8 | awk 'NR==1{print "   GiB    PID KOMMANDO";next}{printf "%6.1f %6s %s\n",$1/1048576,$2,$3}'
  rubrik "GPU-processer"
  nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv 2>&1 | head -n 6
  echo
  echo "Hog 'buff/cache' efter nedladdning eller modellbyte kan hindra start."
  echo "Frigor med: ./diag.sh cache"
}

cache() {
  echo "Fore:  $(free -h | awk '/^Mem:/{print "tillgangligt "$7", cache "$6}')"
  read -r -p "Tomma sidcachen (sync; drop_caches=3)? Ofarligt, men nasta modelladdning lases fran disk. [j/N] " s
  [[ "$s" == "j" ]] || { echo "Avbrutet."; return; }
  sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
  echo "Efter: $(free -h | awk '/^Mem:/{print "tillgangligt "$7", cache "$6}')"
}

gpu() {
  rubrik "GPU"
  nvidia-smi 2>&1 | head -n 20
  rubrik "Fem matningar, 1 s mellanrum (last %, temp C, effekt W)"
  nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw --format=csv,noheader -l 1 2>/dev/null & P=$!
  sleep 5.5; kill $P 2>/dev/null
  rubrik "CPU-temperatur"
  paste <(cat /sys/class/thermal/thermal_zone*/type 2>/dev/null) <(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null) | awk '{printf "%-20s %.0f C\n",$1,$2/1000}' | head -n 8
}

gputest() {   # fungerar GPU:n inifran en container?
  BILD="$(env_varde LLM_IMAGE)"; BILD="${1:-$BILD}"
  [[ -n "$BILD" ]] || { echo "Ange bild: ./diag.sh gputest <bild>"; return 1; }
  rubrik "nvidia-smi inuti $BILD"
  docker run --rm --gpus all --entrypoint nvidia-smi "$BILD" 2>&1 | head -n 15
  rubrik "Docker-runtime"
  docker info 2>/dev/null | grep -iE 'runtimes|default runtime|cgroup driver|architecture'
}

nat() {    # namnuppslag, klocka och vilka adresser som faktiskt nas (aven omdirigeringar)
  rubrik "DNS och klocka"
  rad "DNS-servrar"   "$(resolvectl dns 2>/dev/null | sed 's/^[^:]*: //' | tr '\n' ' ' | grep . || grep nameserver /etc/resolv.conf | tr '\n' ' ')"
  rad "Klocka synkad" "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)   $(date '+%F %T %Z')"
  rad "Proxy i miljon" "$(p="${https_proxy:-${HTTPS_PROXY:-ingen}}"; echo "${p/\/\/*@/\/\/<anv:losen>@}")"
  rubrik "HTTPS (000 = inget svar, 401 fran register = nabart, 403 = ofta proxy/brandvagg)"
  for u in https://huggingface.co https://github.com https://raw.githubusercontent.com \
           https://registry-1.docker.io/v2/ https://ghcr.io/v2/ https://nvcr.io/v2/ \
           https://pypi.org/simple/ https://ports.ubuntu.com ${1:+"$1"}; do
    h="${u#https://}"; h="${h%%/*}"
    ip="$(getent ahostsv4 "$h" | awk '{print $1; exit}')"
    r="$(curl -s -m 8 -o /dev/null -L -w '%{http_code} %{url_effective}' "$u" 2>/dev/null)"
    mal="${r#* }"; mal="${mal#https://}"; mal="${mal%%/*}"
    printf '%-28s dns:%-16s http:%s%s\n' "$h" "${ip:-MISSLYCKAS}" "${r%% *}" "$([[ "$mal" != "$h" ]] && echo " -> $mal")"
  done
  echo
  echo "Stora filer fran Hugging Face hamtas fran andra vardar an huggingface.co."
  echo "Fastnar en nedladdning: kor hamtningen igen och se vilken vard som namns i felet,"
  echo "eller testa den direkt: ./diag.sh nat https://<vard>"
}

apitest() {
  rubrik "API pa $URL"
  rad "/health"    "HTTP $(kod /health)"
  rad "/v1/models" "$(api /v1/models 5 | cut -c1-200)"
  rad "utan nyckel" "HTTP $(curl -s -m 5 -o /dev/null -w '%{http_code}' "$URL/v1/models") (vantat 401)"
  M="$(api /v1/models 5 | grep -o '"id":"[^"]*"' | head -n1 | cut -d'"' -f4)"
  rubrik "Kort fraga till $M"
  T0=$(date +%s.%N)
  hdr | curl -s -K - -m 120 "$URL/v1/chat/completions" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$M\",\"max_tokens\":40,\"temperature\":0,\"messages\":[{\"role\":\"user\",\"content\":\"Svara med ordet klar.\"}]}" | cut -c1-500
  echo; echo "tid: $(awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}') s"
}

matvarden() {
  rubrik "Motorns matvarden ($URL/metrics)"
  api /metrics 5 | grep -E '^vllm:' | grep -vE '_bucket|_created' \
    | grep -E 'num_requests|cache_usage|prefix_cache|preempt|request_success|tokens_total|spec_decode|accepted|draft' | cut -c1-150 | head -n 30 \
    | grep . || echo "Inget svar. Kor motorn? Ar det vLLM?"
}

folj() {   # en rad varannan sekund medan en matning eller ett test gar. Ctrl-C avslutar.
  printf '%-8s %5s %5s %7s %9s %5s %5s %6s\n' TID KOR KOAR KV% LEDIGT GPU% TEMP EFFEKT
  while true; do
    m="$(api /metrics 2)"
    v() { echo "$m" | grep -E "^vllm:$1" | grep -v _created | awk '{print $NF}' | head -n1; }
    kv="$(v '(gpu|kv)_cache_usage_perc')"
    printf '%-8s %5s %5s %7s %9s %5s %5s %6s\n' "$(date +%T)" "$(v num_requests_running | cut -d. -f1)" "$(v num_requests_waiting | cut -d. -f1)" \
      "$(awk -v k="${kv:-0}" 'BEGIN{printf "%.1f", k*100}')" "$(free -h | awk '/^Mem:/{print $7}')" \
      $(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null | tr -d ',' || echo "- - -")
    sleep 2
  done
}

disk() {
  rubrik "Disk"
  df -h / /srv 2>/dev/null | awk '!s[$0]++'
  rubrik "Modeller och bilder"
  du -sh /srv/models/*/ /srv/images/* 2>/dev/null
  rubrik "Docker"
  docker system df 2>&1
}

konf() {
  rubrik "$ENV_FIL (nyckeln dold)"
  sudo sed 's/^\(VLLM_API_KEY=\).*/\1<dold>/' "$ENV_FIL" 2>&1 | grep -vE '^\s*(#|$)'
  rubrik "$ARG_FIL"
  grep -vE '^\s*(#|$)' "$ARG_FIL" 2>&1
  rubrik "Sammansatt kommando"
  sudo /usr/local/lib/llm/start.sh --visa 2>&1
  rubrik "Checksummor"
  sudo sha256sum "$ARG_FIL" /usr/local/lib/llm/start.sh /etc/systemd/system/llm.service 2>&1 | cut -c1-16,65-
  echo "(jamfor med /etc/llm/konfig.sha256 via ./verifiera.sh)"
}

tokenizer() {
  D="/srv/models/$(env_varde LLM_MODEL_DIR)"; D="${1:-$D}"
  rubrik "Tokenizer och kontext i $D"
  python3 - "$D" <<'PY'
import json, os, sys
d = sys.argv[1]
def las(f):
    try: return json.load(open(os.path.join(d, f)))
    except FileNotFoundError: return None
    except Exception as e:
        print("FEL i %s: %s" % (f, e)); return None
t = las("tokenizer.json")
print("tokenizer.json truncation:", "FIL SAKNAS" if t is None else t.get("truncation"), " (ska vara None)")
tc = las("tokenizer_config.json") or {}
print("model_max_length:        ", tc.get("model_max_length"))
print("chattmall finns:         ", bool(tc.get("chat_template")) or os.path.exists(os.path.join(d, "chat_template.jinja")))
c = las("config.json") or {}
tx = c.get("text_config") or {}
print("max_position_embeddings: ", c.get("max_position_embeddings") or tx.get("max_position_embeddings"))
print("arkitektur:              ", c.get("architectures"))
print("kvantisering:            ", (c.get("quantization_config") or {}).get("format") or (c.get("quantization_config") or {}).get("quant_method"))
PY
}

allt() {   # allt i en fil, for dokumentation eller for att skicka vidare
  UT="/srv/llm/diag-$(date +%Y%m%d-%H%M%S).txt"
  umask 077   # ny fil, bara lasbar for labbkontot
  [[ -e "$UT" ]] && { echo "$UT finns redan, forsok igen om en sekund" >&2; return 1; }
  { oversikt; konf; logg 80; fel 60; minne; disk; matvarden; tokenizer; } 2>&1 | maskera > "$UT"
  echo "Sparat: $UT ($(wc -l < "$UT") rader, rattigheter 600). Aktuell nyckel ar ersatt med <nyckel dold>;"
  echo "aldre nycklar och annat kansligt kan finnas kvar: granska filen innan den lamnar maskinen."
}

hjalp() {
  cat <<'H'
./diag.sh             oversikt: tjanst, port, API, minne, GPU, senaste fel
./diag.sh logg [n]    nyckelrader ur startloggen (KV-cache, MTP, kontext, varningar)
./diag.sh fel [n]     fel och tracebacks, samt OOM och GPU-fel ur karnan
./diag.sh minne       minne, storsta processer, sidcache
./diag.sh cache       tom sidcachen (fragar forst)
./diag.sh gpu         GPU-last, temperatur och effekt under 5 s
./diag.sh gputest     nar GPU:n fran en container?
./diag.sh nat [url]   DNS, klocka och vilka vardar som nas, med omdirigeringar
./diag.sh api         halsa, modellista, nyckelkontroll och en kort fraga
./diag.sh matvarden   vLLM:s raknare: kor, KV-anvandning, prefixcache
./diag.sh folj        lopande rad varannan sekund under en matning
./diag.sh disk        utrymme, modeller, bilder
./diag.sh konf        gallande konfiguration och sammansatt startkommando
./diag.sh tokenizer   trunkering, maxlangd och chattmall i modellkatalogen
./diag.sh allt        allt ovan till en fil under /srv/llm
H
}

case "${1:-oversikt}" in
  oversikt) oversikt ;;
  logg) logg "${2:-}" ;;        fel) fel "${2:-}" ;;
  minne) minne ;;               cache) cache ;;
  gpu) gpu ;;                   gputest) gputest "${2:-}" ;;
  nat) nat "${2:-}" ;;          api) apitest ;;
  matvarden) matvarden ;;       folj) folj ;;
  disk) disk ;;                 konf) konf ;;
  tokenizer) tokenizer "${2:-}" ;;
  allt) allt ;;
  *) hjalp ;;
esac
