#!/usr/bin/env bash
# Steg 08: vilka modeller och bilder finns redan pa maskinen? Bara lasning.
set -uo pipefail
d() { echo; echo "== $1 =="; shift; "$@" 2>&1 | head -n "${N:-15}"; }
N=10 d "/srv/models (vara)"            bash -c 'du -sh /srv/models/*/ 2>/dev/null; cat /srv/models/*.kalla 2>/dev/null | grep -E "^(kalla|revision)"'
N=10 d "/srv/images (vara)"            bash -c 'ls -lh /srv/images/*.zst /srv/images/*.gz 2>/dev/null | awk "{print \$5, \$9}"'
N=15 d "Hugging Face-cache (~/.cache/huggingface/hub)" bash -c 'du -sh ~/.cache/huggingface/hub/models--* 2>/dev/null || echo "(tom)"'
N=10 d "andra HF-cachar"               bash -c 'ls -d /home/*/.cache/huggingface/hub /root/.cache/huggingface/hub /srv/*/huggingface /opt/*/huggingface 2>/dev/null; echo "(slut)"'
N=10 d "Ollama"                        bash -c 'du -sh ~/.ollama/models /usr/share/ollama/.ollama/models 2>/dev/null; ollama list 2>/dev/null; echo "(slut)"'
N=20 d "Docker-bilder"                 docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}'
N=20 d "stora viktfiler (>1 GB) utanfor /srv/models" bash -c 'sudo find / -xdev \( -name "*.safetensors" -o -name "*.gguf" -o -name "*.bin" -o -name "*.pt" \) -size +1G -not -path "/srv/models/*" -printf "%s %p\n" 2>/dev/null | sort -rn | awk "{printf \"%5.1f GB  %s\n\", \$1/1073741824, \$2}" | head -n 20; echo "(slut)"'
N=10 d "storsta katalogerna i /home och /opt" bash -c 'sudo du -xsh /home/* /opt/* /var/lib/docker 2>/dev/null | sort -rh | head -n 10'
echo
echo "Klart."
