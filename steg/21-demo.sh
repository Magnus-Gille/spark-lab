#!/usr/bin/env bash
# Steg 21: forbereder demon "bygg nagot med bara Sparkens modell": installerar
# OpenCode (last version, GitHub-release, ingen curl|bash), skriver en
# OpenCode-konfiguration som pekar pa Sparkens API, och skapar ~/demo med en
# uppgift. ANDRAR: ~/.local/bin/opencode, ~/.config/opencode/opencode.json, ~/demo.
# Fragar forst. Nyckeln hamnar i opencode.json (600): ta bort filen i slutet av dagen
# om kontot inte ska ha den kvar (stada.sh paminner).
set -euo pipefail
VER="v1.18.35"
URL="https://github.com/sst/opencode/releases/download/$VER/opencode-linux-arm64.tar.gz"
PORT="$(sudo sed -n 's/^LLM_PORT=//p' /etc/llm/llm.env | tr -d '"')"; PORT="${PORT:-8000}"
echo "Plan:"
echo "  1. hamta $URL till ~/.local/bin/opencode"
echo "  2. skriva ~/.config/opencode/opencode.json (leverantor 'spark', http://127.0.0.1:$PORT/v1, modell kod, nyckel fran llm.env)"
echo "  3. skapa ~/demo med en uppgift (CLI i C# eller Python som laser /srv/llm/bench.csv)"
read -r -p "Fortsatt? [j/N] " s; [[ "$s" == "j" ]] || { echo "Avbrutet."; exit 1; }

mkdir -p ~/.local/bin ~/.config/opencode ~/demo
T="$(mktemp -d)"
curl -fsSL -o "$T/oc.tar.gz" "$URL"
echo "sha256 $(sha256sum "$T/oc.tar.gz" | cut -c1-16)...  (version $VER, anteckna)"
tar -xzf "$T/oc.tar.gz" -C "$T"
install -m 755 "$(find "$T" -type f -name opencode | head -n1)" ~/.local/bin/opencode
rm -rf "$T"
~/.local/bin/opencode --version

KEY="$(sudo sed -n 's/^VLLM_API_KEY=//p' /etc/llm/llm.env | tr -d '"')"
umask 077
cat > ~/.config/opencode/opencode.json <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "spark": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Spark (lokal)",
      "options": { "baseURL": "http://127.0.0.1:$PORT/v1", "apiKey": "$KEY" },
      "models": { "kod": { "name": "kod (Spark)" } }
    }
  },
  "model": "spark/kod"
}
JSON
unset KEY
umask 022

cat > ~/demo/UPPGIFT.md <<'MD'
# Demo: bygg ett verktyg med bara Sparkens modell

Allt sker lokalt: OpenCode pratar med http://127.0.0.1:8000, ingen trafik lamnar maskinen.

Forslag pa uppgift (valj ett, eller hitta pa eget):

1. Ett kommandoradsverktyg i Python som laser /srv/llm/bench.csv och skriver ut
   en tabell per kandidat (etikett, tok/s per anvandare, tok/s totalt, forsta token),
   sorterad pa tok/s totalt. Med enhetstester (pytest eller unittest).
2. Samma sak i C# (dotnet 8, om det finns pa maskinen).
3. En statisk HTML-sida som visar samma tabell och ett stapeldiagram.

Sa har:
  cd ~/demo && opencode
  > Las UPPGIFT.md och bygg alternativ 1. Kor testerna och ratta tills de gar igenom.

Titta samtidigt i ett annat fonster:  /usr/local/lib/llm/diag.sh folj
(KV%, antal korande anrop, tok/s i realtid).
MD
cp /srv/llm/bench.csv ~/demo/bench.csv 2>/dev/null || true
echo
echo "KLART. Demo:  cd ~/demo && opencode   (modell spark/kod ar standard)"
echo "I ett andra fonster:  /usr/local/lib/llm/diag.sh folj"
