#!/usr/bin/env bash
# Samlar maskinens varden (OS, karna, drivrutin, GPU, Docker, minne, disk) och sparar radata.
set -uo pipefail
mkdir -p /srv/llm 2>/dev/null || { echo "Kor ./lage.sh fore forst (skapar /srv/llm)" >&2; exit 1; }
RA="/srv/llm/system-$(date +%Y%m%d).txt"

v() { printf '%-28s %s\n' "$1" "$2"; }
forsta() { "$@" 2>/dev/null | head -n1; }

echo "--- Maskinens varden ---"
v "Vardnamn"            "$(hostname)"
v "Arkitektur"          "$(uname -m)"
v "OS"                  "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-okant}")"
[[ -r /etc/dgx-release ]] && v "DGX OS" "$(grep -m1 -i version /etc/dgx-release | tr -d '"')"
v "Karna"               "$(uname -r)"
v "NVIDIA-drivrutin"    "$(forsta nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
v "GPU"                 "$(forsta nvidia-smi --query-gpu=name --format=csv,noheader)"
v "Docker"              "$(forsta docker version --format '{{.Server.Version}}')"
v "Container Toolkit"   "$(forsta nvidia-ctk --version)"
v "Minne totalt/ledigt" "$(free -h | awk '/^Mem:/{print $2" / "$7}')"
v "Disk ledigt /srv"    "$(df -h --output=avail /srv | tail -n1 | tr -d ' ')"
v "Swap"                "$(free -h | awk '/^Swap:/{print $2}')"
v "Klocka synkad"       "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"

{ hostnamectl; uname -a; cat /etc/os-release; cat /etc/dgx-release; nvidia-smi; docker version; nvidia-ctk --version; free -h; df -h; timedatectl; } > "$RA" 2>&1
echo "Radata: $RA"
