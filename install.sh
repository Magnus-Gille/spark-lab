#!/usr/bin/env bash
# Lagger tjansten och verktygen pa plats. Skriver aldrig over befintlig llm.env
# eller serve.args.
#   ./install.sh [recept/<fil>.args]
#
# Program som systemd kor som root ligger i /usr/local/lib/llm (agare root, inte
# skrivbar for labbkontot). /srv/llm ar labbkontots arbetskatalog for lagen,
# matningar och diagnosfiler. Verktygen kopieras ocksa till /usr/local/lib/llm
# sa att klonen kan tas bort nar dagen ar slut.
set -euo pipefail
HAR="$(cd "$(dirname "$0")" && pwd)"
RECEPT="${1:-}"
LIB=/usr/local/lib/llm

sudo mkdir -p /srv/llm /srv/models /srv/images /etc/llm "$LIB" "$LIB/recept"
sudo chown root:root "$LIB" /etc/llm
sudo chmod 755 "$LIB" /etc/llm
# Hela repot utom .git, sa att klonen kan tas bort: skript 755, ovrigt 644, agare root.
sudo mkdir -p "$LIB/recept/varianter" "$LIB/steg" "$LIB/eval/exempel" "$LIB/docs"
for f in "$HAR"/*.sh "$HAR"/*.py "$HAR"/steg/*.sh; do
  d="$LIB/$(dirname "${f#"$HAR"/}")"; sudo install -o root -g root -m 755 "$f" "$d/"
done
sudo install -o root -g root -m 644 "$HAR/_klient.py" "$LIB/"
for f in "$HAR"/*.md "$HAR"/*.mall "$HAR"/*.service "$HAR"/recept/*.args "$HAR"/recept/*.md "$HAR"/recept/varianter/*.args \
         "$HAR"/steg/*.md "$HAR"/eval/* "$HAR"/eval/exempel/* "$HAR"/docs/*; do
  [[ -f "$f" ]] || continue
  d="$LIB/$(dirname "${f#"$HAR"/}")"; sudo install -o root -g root -m 644 "$f" "$d/"
done
sudo install -o root -g root -m 644 "$HAR/llm.service" /etc/systemd/system/llm.service

if sudo test -e /etc/llm/llm.env; then
  echo "/etc/llm/llm.env finns redan, ror den inte."
else
  # Nyckeln gar aldrig via argv: openssl skriver den till stdout, bash haller den
  # i en variabel och printf (inbyggt) skriver filen via en pipe.
  NYCKEL="$(openssl rand -hex 32)"
  { grep -v '^VLLM_API_KEY=' "$HAR/llm.env.mall"; printf 'VLLM_API_KEY=%s\n' "$NYCKEL"; } \
    | sudo install -o root -g root -m 600 /dev/stdin /etc/llm/llm.env
  unset NYCKEL
  echo "Skapade /etc/llm/llm.env med ny API-nyckel. Fyll i LLM_IMAGE, LLM_IMAGE_ID och LLM_MODEL_DIR:"
  echo "  sudo nano /etc/llm/llm.env"
fi

if sudo test -e /etc/llm/serve.args; then
  echo "/etc/llm/serve.args finns redan, ror den inte."
elif [[ -n "$RECEPT" ]]; then
  sudo install -o root -g root -m 644 "$RECEPT" /etc/llm/serve.args
  echo "Kopierade $RECEPT till /etc/llm/serve.args"
else
  echo "Ingen /etc/llm/serve.args. Kor om med ett recept: $0 recept/qwen38-27b.args"
fi

sudo systemctl daemon-reload
echo
echo "Nasta steg:"
echo "  sudo $LIB/start.sh --visa   # granska kommandot"
echo "  sudo systemctl enable --now llm    # starta"
echo "  journalctl -fu llm                 # folj laddningen"
