#!/usr/bin/env bash
# Startar en inspelning av terminalen (kommandon och utskrifter) till
# ~/spark-lab-logg/session-<datum-tid>.txt och oppnar ett nytt skal i den.
#   ./spela-in.sh        starta; skriv exit for att avsluta inspelningen
# Historiken i det inspelade skalet far tidsstamplar. Inspelningen innehaller
# allt som visas pa skarmen, aven nycklar om de skrivs ut: maskera innan den
# lamnar maskinen (se README, "Spara underlag").
set -euo pipefail
umask 077   # inspelningen ar privat: katalog 700, fil 600
KAT="$HOME/spark-lab-logg"
mkdir -p "$KAT" && chmod 700 "$KAT"
FIL="$KAT/session-$(date +%Y%m%d-%H%M%S).txt"
: >> "$FIL" && chmod 600 "$FIL"
export HISTTIMEFORMAT='%F %T '
echo "Spelar in till $FIL. Skriv exit for att avsluta."
exec script -a -q "$FIL"
