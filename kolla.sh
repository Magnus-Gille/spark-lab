#!/usr/bin/env bash
# Forkontroll innan nagot installeras. Andrar ingenting. Varje rad ar OK, FEL
# eller OKANT; FEL maste losas innan dagen fortsatter.
set -uo pipefail
FEL=0
r() { printf '%-6s %-30s %s\n' "$1" "$2" "${3:-}"; [[ "$1" == FEL ]] && FEL=1; return 0; }
har() { command -v "$1" >/dev/null 2>&1; }

for p in docker hf openssl zstd tmux curl python3 git sha256sum; do
  if har "$p"; then r OK "$p" "$(command -v "$p")"; else
    case "$p" in
      hf)   r FEL "$p" "pipx install 'huggingface_hub[cli]'  (eller sudo apt install pipx forst)";;
      zstd|tmux) r FEL "$p" "sudo apt install $p";;
      *)    r FEL "$p" "saknas";;
    esac
  fi
done
har huggingface-cli && ! har hf && r OK "huggingface-cli" "aldre namn, fungerar"

if sudo -n true 2>/dev/null; then r OK "sudo utan losenord"; elif sudo -v 2>/dev/null; then r OK "sudo med losenord"; else r FEL "sudo" "labbkontot saknar sudo"; fi
if docker info >/dev/null 2>&1; then r OK "docker som $USER"; elif sudo docker info >/dev/null 2>&1; then r FEL "docker som $USER" "bara via sudo. Valj: sudo usermod -aG docker $USER (motsvarar root) eller kor alla docker-steg med sudo"; else r FEL "docker" "demonen svarar inte"; fi
if docker info 2>/dev/null | grep -qi nvidia; then r OK "NVIDIA-runtime i Docker"; else r OKANT "NVIDIA-runtime i Docker" "docker info namner inte nvidia; testa ./diag.sh gputest <bild> efter bild.sh"; fi
if har nvidia-smi && nvidia-smi -L >/dev/null 2>&1; then r OK "GPU" "$(nvidia-smi -L | head -n1 | cut -c1-60)"; else r FEL "GPU" "nvidia-smi svarar inte"; fi
[[ "$(uname -m)" == "aarch64" ]] && r OK "arkitektur aarch64" || r FEL "arkitektur" "$(uname -m), vantat aarch64"

LEDIGT="$(df --output=avail -BG /srv 2>/dev/null | tail -n1 | tr -dc '0-9')"
[[ -z "$LEDIGT" ]] && LEDIGT="$(df --output=avail -BG / | tail -n1 | tr -dc '0-9')"
if [[ "${LEDIGT:-0}" -ge 400 ]]; then r OK "disk ledigt" "${LEDIGT} GB"; elif [[ "${LEDIGT:-0}" -ge 100 ]]; then r OKANT "disk ledigt" "${LEDIGT} GB: racker for B+C (ca 50 GB + bilder), inte for A (124 GB + 2x vid komprimering)"; else r FEL "disk ledigt" "${LEDIGT:-?} GB"; fi
MEM="$(free -g | awk '/^Mem:/{print $2}')"; [[ "${MEM:-0}" -ge 100 ]] && r OK "minne" "${MEM} GB" || r OKANT "minne" "${MEM} GB, Spark har 128"
[[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == "yes" ]] && r OK "klocka synkad" || r OKANT "klocka synkad" "timedatectl; fel klocka ger certifikatfel"

nat() { local k; k="$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null)"; local e=$?
  case "$e" in 0) [[ "$k" =~ ^(200|301|302|401|403)$ ]] && r OK "nat $2" "HTTP $k" || r OKANT "nat $2" "HTTP $k";;
    6) r FEL "nat $2" "DNS misslyckas";; 7) r FEL "nat $2" "ingen anslutning (brandvagg?)";; 28) r FEL "nat $2" "timeout";;
    35|60) r FEL "nat $2" "TLS/certifikatfel (proxy med inspektion? fel klocka?)";; *) r FEL "nat $2" "curl kod $e";; esac; }
nat https://huggingface.co huggingface.co
nat https://github.com github.com
nat https://registry-1.docker.io/v2/ docker.io
[[ -n "${https_proxy:-${HTTPS_PROXY:-}}" ]] && r OKANT "proxy i miljon" "satt; Docker och git behover samma installning"

echo
[[ $FEL -eq 0 ]] && echo "Inga FEL. Nasta: ./lage.sh fore" || echo "FEL finns, se ovan."
exit $FEL
