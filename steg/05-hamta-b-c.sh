#!/usr/bin/env bash
# Steg 05: hamtar kandidat B och sedan C med laste revisioner (2026-10-07).
# Kor INUTI tmux: tmux new -s hamta, sedan ./steg/05-hamta-b-c.sh, sedan Ctrl-b d.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "B: nvidia/Qwen3.8-27B-NVFP4 (20 GiB)"
./hamta.sh nvidia/Qwen3.8-27B-NVFP4 482ca0f3832238542f8f5295dde86b5f22711d80
echo
echo "C: nvidia/Qwen3.6-35B-A3B-NVFP4 (22 GiB)"
./hamta.sh nvidia/Qwen3.6-35B-A3B-NVFP4 1355db6a052410cfd62085d94b58866fd0f2c3c5
echo
echo "KLART: B och C hamtade. Se /srv/models/*.kalla"
