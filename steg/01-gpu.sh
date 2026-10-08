#!/usr/bin/env bash
# Steg 01: varfor svarar inte nvidia-smi? Bara lasning, andrar inget.
set -uo pipefail
d() { echo; echo "== $1 =="; shift; "$@" 2>&1 | head -n "${N:-12}"; }
N=3 d "vem och grupper"        id
N=3 d "PATH"                   bash -c 'echo "$PATH" | tr ":" "\n" | grep -n nvidia || echo "(ingen nvidia-katalog i PATH)"'
N=3 d "nvidia-smi i PATH?"     bash -c 'command -v nvidia-smi || echo "(saknas i PATH)"'
N=3 d "nvidia-smi pa disk?"    ls -l /usr/bin/nvidia-smi /usr/local/cuda/bin/nvidia-smi
N=5 d "nvidia-smi"             nvidia-smi
N=5 d "nvidia-smi -L"          nvidia-smi -L
d "/dev/nvidia*"               ls -l /dev/nvidia* /dev/dri
N=5 d "laddade moduler"        bash -c 'lsmod | grep -E "^nvidia|^nouveau" || echo "(inga nvidia-moduler laddade)"'
N=3 d "DGX OS och karna"       bash -c 'cat /etc/dgx-release 2>/dev/null | head -n 3; uname -r'
N=5 d "paket nvidia-driver"    bash -c 'dpkg -l | grep -iE "nvidia-(driver|utils|kernel)" | awk "{print \$2, \$3}" | head -n 5'
N=15 d "dmesg om nvidia (sudo)" sudo dmesg 2>&1 | grep -iE 'nvidia|nvrm|xid' | tail -n 15
N=5 d "systemd nvidia-enheter" bash -c 'systemctl list-units --all "nvidia*" --no-pager --no-legend | head -n 5'
echo
echo "Klistra in allt ovan i chatten."
