#!/usr/bin/env bash
# Visar vad som andrats pa maskinen sedan ./lage.sh fore och gar igenom
# en checklista for avslut. Skriver lage-efter.txt. Tar INTE bort nagot sjalv.
set -uo pipefail
HAR="$(cd "$(dirname "$0")" && pwd)"
FORE=/srv/llm/lage-fore.txt
[[ -e "$FORE" ]] || { echo "Hittar inte $FORE (kordes ./lage.sh fore i morse?)" >&2; exit 1; }
"$HAR/lage.sh" efter >/dev/null || { echo "Efterinventeringen misslyckades; ingen jamforelse gors." >&2; exit 1; }

echo "=== Andringar sedan i morse (< bara fore, > bara efter) ==="
# diff ger kod 1 nar det finns skillnader; det ar inte ett fel har.
D="$(diff <(tail -n +2 "$FORE") <(tail -n +2 /srv/llm/lage-efter.txt) | grep -E '^[<>]' || true)"
[[ -n "$D" ]] && echo "$D" || echo "(inga)"

p() { printf '%-52s %s\n' "$1" "$2"; }
echo
echo "=== Kontroller ==="
if [[ -e ~/.cache/huggingface/token || -e ~/.huggingface/token ]]; then p "Hugging Face-token" "FINNS KVAR -> hf auth logout"; else p "Hugging Face-token" "borta"; fi
if env | grep -qiE '^(HF_TOKEN|HUGGING_FACE_HUB_TOKEN)='; then p "HF-token i miljon" "FINNS KVAR"; else p "HF-token i miljon" "borta"; fi
# Snavt monster: HF-token (hf_...), OpenAI-liknande (sk-...), eller var egen nyckel (64 hex efter VLLM_API_KEY).
H="$(grep -lsE 'hf_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|VLLM_API_KEY=[0-9a-f]{64}' ~/.bashrc ~/.profile ~/.zshrc ~/.bash_history ~/.zsh_history 2>/dev/null | tr '\n' ' ')"
p "Hemligheter i profiler/historik" "${H:-inga traffar}"
curl -m 5 -sI https://huggingface.co >/dev/null 2>&1; K=$?
case $K in 0) p "Utgaende 443" "OPPET (ska stangas av natansvarig)";;
  *) p "Utgaende 443" "forbindelse misslyckades (curl kod $K), egressregeln ar INTE verifierad";; esac
echo "   (bara natansvarigs regel och ett overenskommet test, aven fran containern, verifierar stangning)"
p "Korande containrar" "$(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
p "Tjansten llm" "$(systemctl is-active llm 2>/dev/null)"
if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then p "docker-gruppen" "$USER AR MEDLEM (motsvarar root; ta bort om det var tillfalligt: sudo gpasswd -d $USER docker)"; else p "docker-gruppen" "inte medlem"; fi
echo
echo "Modeller pa disk:";  du -sh /srv/models/*/ 2>/dev/null
echo "Bilder i Docker:";   docker images --format '  {{.Repository}}:{{.Tag}}  {{.Size}}' 2>/dev/null
echo
echo "Ta bort for hand det som inte ska vara kvar (bortvalda modeller, testfiler), kor sedan om skriptet."
echo "Klonen (~/spark-lab) kan tas bort NAR aterstallningsprovet i README ar gjort fran /usr/local/lib/llm."
echo "Historiken kan innehalla kommandon med nyckeln: history -c; rm -f ~/.bash_history"
[[ -e ~/.config/opencode/opencode.json ]] && echo "OBS: ~/.config/opencode/opencode.json innehaller API-nyckeln (demo). Ta bort om kontot inte ska ha den: rm ~/.config/opencode/opencode.json"
