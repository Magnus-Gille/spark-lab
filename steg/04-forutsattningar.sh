#!/usr/bin/env bash
# Steg 04: installerar det kolla.sh saknade. ANDRAR maskinen (apt, docker-gruppen).
# Visar planen och fragar innan nagot gors. Efterat: logga ut och in, kor ./kolla.sh.
set -euo pipefail
echo "Planerade andringar:"
echo "  1. sudo apt-get install pipx tmux zstd"
echo "  2. sudo usermod -aG docker $USER      (gruppmedlemskap, motsvarar root; tas bort i slutet av dagen)"
echo "  3. pipx install 'huggingface_hub[cli]' && pipx ensurepath   (hf, i ~/.local/bin)"
echo "  4. timedatectl                        (bara visa klockan)"
read -r -p "Fortsatt? [j/N] " s; [[ "$s" == "j" ]] || { echo "Avbrutet."; exit 1; }

echo; echo "== 1. apt =="
sudo apt-get install -y pipx tmux zstd
echo; echo "== 2. docker-gruppen =="
sudo usermod -aG docker "$USER" && echo "$USER tillagd i docker (galler efter ny inloggning)"
echo; echo "== 3. hf =="
pipx install 'huggingface_hub[cli]' && pipx ensurepath
echo; echo "== 4. klockan =="
timedatectl | grep -E 'Local time|synchronized|NTP service'
echo
echo "KLART. Logga ut och in igen (Ctrl+D eller menyn), starta inspelningen pa nytt och kor:"
echo "  cd ~/spark-lab && ./kolla.sh"
