#!/usr/bin/env bash
# Sparar maskinens lage (paket, konton, portar, bilder, rattigheter) for
# jamforelse fore/efter. Inventerar FORST, skapar kataloger sedan.
#   ./lage.sh fore     kors pa morgonen innan nagot installeras
#   ./lage.sh efter    kors av stada.sh
set -uo pipefail
NAMN="${1:-}"
[[ "$NAMN" == "fore" || "$NAMN" == "efter" ]] || { echo "Anvandning: $0 fore|efter" >&2; exit 1; }

UT="/srv/llm/lage-$NAMN.txt"
if [[ "$NAMN" == "fore" && -e "$UT" && "${2:-}" != "-f" ]]; then
  echo "$UT finns redan. Skriv over med: $0 fore -f" >&2; exit 1
fi

# Misslyckade kontroller syns som "(misslyckades: kod N)" i stallet for att doljas.
del() { echo; echo "=== $1 ==="; shift; "$@" 2>&1 || echo "(misslyckades: kod $?)"; }

INV="$(mktemp)"
{
  echo "# lage: $NAMN"
  del "paket (dpkg)"        dpkg-query -W -f='${Package} ${Version}\n'
  del "snap"                snap list
  del "pip (anvandare)"     python3 -m pip list --user --format=freeze
  del "pipx"                pipx list --short
  del "npm globalt"         npm ls -g --depth=0
  del "konton"              getent passwd
  del "grupper for $USER"   id
  del "sudo-regler"         sh -c 'ls -l /etc/sudoers.d 2>/dev/null'
  del "ssh-nycklar"         sh -c 'cat ~/.ssh/authorized_keys 2>/dev/null | cut -c1-60'
  del "lyssnande portar"    sh -c "ss -tlnH | awk '{print \$4}' | sort -u"
  del "docker-bilder"       docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}'
  del "docker-containrar"   docker ps -a --format '{{.Names}} {{.Image}}'
  del "hemkatalog"          sh -c 'ls -A1 ~ ; ls -A1 ~/.config 2>/dev/null | sed "s|^|.config/|"; ls -A1 ~/.cache 2>/dev/null | sed "s|^|.cache/|"'
  del "systemd-enheter"     sh -c 'ls -1 /etc/systemd/system/*.service 2>/dev/null'
  del "rattigheter /srv /etc/llm /usr/local/lib/llm" sh -c 'stat -c "%U:%G %a %n" /srv /srv/llm /srv/models /srv/images /etc/llm /usr/local/lib/llm 2>/dev/null'
  del "/srv"                sh -c 'ls -1 /srv/llm /srv/models /srv/images 2>/dev/null'
} > "$INV"

# Bara "fore" skapar arbetskataloger, och bara de som saknas. En befintlig katalog
# med annan agare lamnas orord och rapporteras. "efter" andrar ingenting.
if [[ "$NAMN" == "fore" ]]; then
  for d in /srv/llm /srv/models /srv/images; do
    if [[ ! -e "$d" ]]; then sudo mkdir -p "$d" && sudo chown "$USER": "$d"
    elif [[ "$(stat -c %U "$d")" != "$USER" ]]; then echo "OBS: $d finns redan med agare $(stat -c %U "$d"); lamnas orord" >&2; fi
  done
fi
[[ -w /srv/llm ]] || { echo "Kan inte skriva i /srv/llm; inventeringen ligger kvar i $INV" >&2; exit 1; }
mv "$INV" "$UT"
echo "Sparat: $UT ($(wc -l < "$UT") rader), tid: $(date '+%F %T')"
