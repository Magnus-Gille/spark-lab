#!/usr/bin/env bash
# Steg 13: samlar dagens underlag for kunden under /srv/llm/overlamning-<datum>/:
# diag allt, bench/eval, batchloggar, lage fore/efter, inspelningar (med aktuell
# nyckel maskad), systemvarden, konfiguration (utan nyckel). Andrar inget annat.
set -uo pipefail
cd /usr/local/lib/llm || exit 1
UT="/srv/llm/overlamning-$(date +%Y%m%d)"; mkdir -p "$UT"; chmod 700 "$UT"
KEY="$(sudo sed -n 's/^VLLM_API_KEY=//p' /etc/llm/llm.env | tr -d '"')"
maskera() { local l; while IFS= read -r l; do printf '%s\n' "${l//$KEY/<nyckel dold>}"; done; }
echo "== diag allt =="; ./diag.sh allt | tail -n 2
cp -p /srv/llm/diag-*.txt /srv/llm/bench.csv /srv/llm/eval.csv /srv/llm/batch-*.log /srv/llm/lage-*.txt /srv/llm/system-*.txt "$UT/" 2>/dev/null
cp -rp /srv/llm/svar "$UT/" 2>/dev/null
for f in "$HOME"/spark-lab-logg/*.txt; do [[ -f "$f" ]] && maskera < "$f" | col -b > "$UT/inspelning-$(basename "$f")"; done
{ echo "# Konfiguration $(date '+%F %T')"; echo; echo "## /etc/llm/llm.env (utan nyckel)"; sudo grep -v '^VLLM_API_KEY=' /etc/llm/llm.env | grep -vE '^\s*(#|$)'
  echo; echo "## /etc/llm/serve.args"; grep -vE '^\s*(#|$)' /etc/llm/serve.args; echo; echo "## konfig.sha256"; sudo cat /etc/llm/konfig.sha256
  echo; echo "## modeller"; cat /srv/models/*.kalla; echo; echo "## bilder"; cat /srv/images/*.kalla; } > "$UT/konfiguration.md"
grep -c '<nyckel dold>' "$UT"/inspelning-* 2>/dev/null | sed 's/^/maskeringar: /'
echo; echo "Samlat i $UT:"; ls -la "$UT" | tail -n +2 | awk '{print "  "$5, $9}'
echo "Granska inspelningarna innan de lamnar maskinen; bara den aktuella nyckeln ar maskad."
