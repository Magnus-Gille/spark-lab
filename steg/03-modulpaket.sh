#!/usr/bin/env bash
# Steg 03: finns ett nvidia-modulpaket for den korande karnan, och vad finns pa 6.17?
# Bara lasning. apt-get -s ar simulering.
set -uo pipefail
d() { echo; echo "== $1 =="; shift; "$@" 2>&1 | head -n "${N:-12}"; }
K="$(uname -r)"
N=15 d "installerade kernel-/modulpaket" bash -c 'dpkg -l | awk "/^ii/ && \$2 ~ /^linux-(image|modules|headers|nvidia)/ {print \$2, \$3}"'
N=12 d "modulpaket i apt-kallorna (7.0.0 och 6.17.0)" bash -c 'apt-cache search linux-modules-nvidia-580 2>/dev/null | grep -E "7\.0\.0|6\.17\.0" | cut -c1-110; echo "(slut)"'
N=8  d "apt policy for 7.0.0-paketet" apt-cache policy "linux-modules-nvidia-580-open-$K"
N=12 d "simulerad installation (andrar inget)" sudo apt-get -s install "linux-modules-nvidia-580-open-$K"
N=6  d "modulen pa 6.17: version"   bash -c 'modinfo /lib/modules/6.17.0-1021-nvidia/kernel/nvidia-580-open/nvidia.ko 2>&1 | grep -E "^(version|vermagic)"'
N=4  d "userspace-drivrutin"        bash -c 'dpkg -l nvidia-utils-580 | awk "/^ii/{print \$2, \$3}"; cat /sys/module/nvidia/version 2>/dev/null'
N=12 d "grub-poster"                bash -c 'grep -E "^\s*menuentry" /boot/grub/grub.cfg 2>/dev/null | sed -E "s/menuentry \x27([^\x27]*)\x27.*/\1/" | cut -c1-90; echo "(slut)"'
N=4  d "grub standard"              bash -c 'grep -E "^GRUB_(DEFAULT|TIMEOUT)" /etc/default/grub 2>/dev/null; cat /boot/grub/grubenv 2>/dev/null | grep -v "^#"'
N=4  d "apt-kallor med nvidia"      bash -c 'grep -rhsE "^deb|^URIs" /etc/apt/sources.list /etc/apt/sources.list.d/ | grep -i nvidia | cut -c1-100; echo "(slut)"'
echo
echo "Fota allt ovan."
