#!/usr/bin/env bash
# Steg 02: ar nvidia-modulen byggd for den korande karnan, och vantar en omstart?
# Bara lasning (modprobe kors med -n, torrkorning).
set -uo pipefail
d() { echo; echo "== $1 =="; shift; "$@" 2>&1 | head -n "${N:-12}"; }
K="$(uname -r)"
N=3  d "korande karna"              echo "$K"
N=8  d "installerade karnor"        bash -c 'ls -1 /boot/vmlinuz-* | sed "s|/boot/vmlinuz-||"'
N=3  d "omstart kravs?"             bash -c 'cat /var/run/reboot-required 2>/dev/null; cat /var/run/reboot-required.pkgs 2>/dev/null; [ -e /var/run/reboot-required ] || echo "(ingen flagga)"'
N=10 d "dkms status"                bash -c 'command -v dkms >/dev/null && dkms status || echo "(dkms saknas)"'
N=8  d "nvidia-moduler for $K"      bash -c "find /lib/modules/$K -name 'nvidia*.ko*' 2>/dev/null || true; echo '(slut)'"
N=8  d "nvidia-moduler for andra karnor" bash -c 'find /lib/modules -name "nvidia.ko*" 2>/dev/null | sed "s|/lib/modules/||" || true; echo "(slut)"'
N=6  d "modinfo nvidia"             bash -c 'modinfo nvidia 2>&1 | grep -E "^(filename|version|vermagic)"'
N=6  d "modprobe torrkorning"       sudo modprobe -n -v nvidia
N=10 d "dkms-bygglogg (sista rader)" bash -c 'ls -t /var/lib/dkms/nvidia/*/build/make.log 2>/dev/null | head -n1 | xargs -r tail -n 10; echo "(slut)"'
N=12 d "apt-historik nvidia/kernel"  bash -c 'grep -hE "^(Start-Date|Commandline|Upgrade|Install)" /var/log/apt/history.log 2>/dev/null | grep -iE "date|nvidia|linux-image|linux-headers" | tail -n 12'
N=4  d "headers for $K"             dpkg -l "linux-headers-$K" 2>&1
N=4  d "nouveau svartlistad?"       bash -c 'grep -rhs nouveau /etc/modprobe.d/ | head -n 3; echo "(slut)"'
echo
echo "Klistra in / fota allt ovan."
