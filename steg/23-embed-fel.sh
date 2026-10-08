#!/usr/bin/env bash
# Steg 23: visar grundorsaken nar llm@embed (eller annan instans, $1) inte startar.
# Bara lasning.
set -uo pipefail
U="llm@${1:-embed}"
echo "== status $U =="; systemctl is-active "$U"; systemctl show "$U" -p ExecMainStatus --value | sed 's/^/exitkod: /'
echo "== felrader (forsta tracebackens orsak) =="
journalctl -u "$U" --no-pager -o cat 2>/dev/null \
  | grep -iE 'error|raise|unsupported|not supported|no module|keyerror|valueerror|assert|not found|unrecognized|invalid' \
  | grep -vE 'Traceback|^\s*raise RuntimeError\(' | cut -c1-220 | head -n 25
echo "== sista 12 raderna fore kraschen =="
journalctl -u "$U" --no-pager -o cat 2>/dev/null | grep -vE '^\s*(File |\^+|return |self\.|super\(|with |next\(|async with|await )' | tail -n 12 | cut -c1-220
