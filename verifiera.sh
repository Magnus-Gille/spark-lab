#!/usr/bin/env bash
# Kontrollerar att modeller, sparade bilder, verktyg och fryst konfiguration ar
# oforandrade. Kraver inget nat. Saknat manifest ar FEL, inte "inga avvikelser".
#   ./verifiera.sh            allt: /srv/models, /srv/images, /usr/local/lib/llm, /etc/llm
#   ./verifiera.sh <namn>     bara modellen /srv/models/<namn>
#   ./verifiera.sh frys       skriver /etc/llm/konfig.sha256: serve.args, llm.service,
#                             allt i /usr/local/lib/llm och llm.env utan nyckelraden
set -uo pipefail
LIB=/usr/local/lib/llm
FEL=0; N=0
T="$(mktemp)"
trap 'rm -f "$T"' EXIT

# llm.env utan nyckeln, i fast form, sa att bild, bild-id, modell och flaggor ingar i frysningen.
env_utan_nyckel() { sudo grep -v '^VLLM_API_KEY=' /etc/llm/llm.env | grep -vE '^\s*(#|$)' | sort; }

if [[ "${1:-}" == "frys" ]]; then
  set -e
  TMP="$(mktemp)"
  # Bara vanliga filer (recept/ ar en katalog och far inte in i listan).
  find /etc/llm/serve.args /etc/systemd/system/llm.service "$LIB" -type f -print0 \
    | sort -z | xargs -0 sudo sha256sum > "$TMP"
  printf '%s  llm.env(utan nyckel)\n' "$(env_utan_nyckel | sha256sum | cut -d' ' -f1)" >> "$TMP"
  [[ "$(wc -l < "$TMP")" -ge 4 ]] || { echo "FEL: for fa rader att frysa, ar install.sh kord?" >&2; rm -f "$TMP"; exit 1; }
  sudo install -o root -g root -m 644 "$TMP" /etc/llm/konfig.sha256 && rm -f "$TMP"
  echo "Skrev /etc/llm/konfig.sha256 ($(wc -l < /etc/llm/konfig.sha256) rader). Nyckeln ingar inte."
  exit 0
fi

modell() {
  local s="$1" n; n="$(basename "$s" .sha256)"; N=$((N+1))
  printf '%-50s ' "modell $n"
  if [[ ! -d "/srv/models/$n" ]]; then echo "FEL (katalogen saknas)"; FEL=1; return; fi
  if [[ ! -e "/srv/models/$n.kalla" ]]; then echo "FEL (.kalla saknas, inte fardigstalld)"; FEL=1; return; fi
  if ( cd "/srv/models/$n" && sha256sum -c --quiet "$s" >"$T" 2>&1 ); then
    local extra; extra="$(cd "/srv/models/$n" && find . -type f ! -path './.cache/*' | sort | comm -23 - <(awk '{print $2}' "$s" | sort))"
    if [[ -n "$extra" ]]; then echo "FEL (filer utanfor manifestet)"; echo "$extra" | sed 's/^/    /'; FEL=1; else echo OK; fi
  else echo FEL; sed 's/^/    /' "$T"; FEL=1; fi
}

if [[ -n "${1:-}" ]]; then
  [[ -e "/srv/models/$1.sha256" ]] || { echo "Hittar ingen /srv/models/$1.sha256 (hamtad med hamta.sh?)" >&2; exit 1; }
  modell "/srv/models/$1.sha256"
else
  for s in /srv/models/*.sha256; do [[ -e "$s" ]] && modell "$s"; done
  for s in /srv/images/*.sha256; do
    [[ -e "$s" ]] || continue; N=$((N+1))
    printf '%-50s ' "bild $(basename "$s" .sha256)"
    if ( cd /srv/images && sha256sum -c --quiet "$s" >"$T" 2>&1 ); then echo OK; else echo FEL; sed 's/^/    /' "$T"; FEL=1; fi
  done
  N=$((N+1)); printf '%-50s ' "konfiguration (/etc/llm/konfig.sha256)"
  if ! sudo test -e /etc/llm/konfig.sha256; then
    echo "FEL (inte fryst: kor ./verifiera.sh frys nar konfigurationen ar klar)"; FEL=1
  else
    # shellcheck disable=SC2024
    if sudo grep -v 'llm.env(utan nyckel)' /etc/llm/konfig.sha256 | sudo sha256sum -c --quiet >"$T" 2>&1 \
       && [[ "$(env_utan_nyckel | sha256sum | cut -d' ' -f1)" == "$(sudo grep 'llm.env(utan nyckel)' /etc/llm/konfig.sha256 | cut -d' ' -f1)" ]]; then
      echo OK
    else echo FEL; sed 's/^/    /' "$T"; grep -q . "$T" || echo "    llm.env (utan nyckel) har andrats"; FEL=1; fi
  fi
fi
[[ $N -eq 0 ]] && { echo "FEL: inga manifest (.sha256) hittades. Inget ar verifierat."; exit 1; }
[[ $FEL -eq 0 ]] && echo "Inga avvikelser ($N kontroller)." || echo "AVVIKELSER FINNS, se ovan."
exit $FEL
