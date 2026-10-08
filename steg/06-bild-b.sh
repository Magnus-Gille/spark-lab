#!/usr/bin/env bash
# Steg 06: hamtar och sparar containerbilden for kandidat B (NVIDIA:s Spark-playbook).
# Kan kora i huvudskalet medan steg 05 laddar i tmux.
set -euo pipefail
cd "$(dirname "$0")/.."
./bild.sh vllm/vllm-openai:qwen38
