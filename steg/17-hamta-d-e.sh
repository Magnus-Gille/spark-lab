#!/usr/bin/env bash
# Steg 17: hamtar beslutsmodellerna D (Cloudflare/clef-flash, 9B) och E
# (Cloudflare/clef, 27B), bf16 fran Cloudflare, laste revisioner 2026-10-08.
# Kor i tmux efter batchen. Ca 75 GB.
set -euo pipefail
cd "$(dirname "$0")/.."
./hamta.sh Cloudflare/clef-flash fde727a287004204b7518dcc983fe64379776712
./hamta.sh Cloudflare/clef       ed3eed331870db2eff4b0db01237128ede8a00ce
echo "KLART: D och E hamtade."
