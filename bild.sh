#!/usr/bin/env bash
# Hamtar en containerbild, laser dess digest och id, och sparar den som fil for
# aterstallning utan internet.
#   ./bild.sh <register/bild:tagg>
#   ./bild.sh <register/bild@sha256:...>     digestlast; far en lokal tagg :digest-<12 tecken>
#   ./bild.sh <lokal-bild:tagg> lokal        bild som byggts pa maskinen, ingen pull
#
# Varfor en tagg och ett id i stallet for digesten: docker save/load behaller
# taggen och bildens id (sha256 av konfigurationen) men inte registrets digest.
# En llm.env med LLM_IMAGE=...@sha256:... gar darfor inte att starta utan nat.
set -euo pipefail
BILD="${1:-}"; LAGE="${2:-}"
[[ -n "$BILD" ]] || { echo "Anvandning: $0 <bild> [lokal]" >&2; exit 1; }

[[ "$LAGE" == "lokal" ]] || docker pull "$BILD"

if [[ "$BILD" == *@sha256:* ]]; then
  KORT="${BILD##*@sha256:}"; KORT="${KORT:0:12}"
  TAGG="${BILD%%@*}:digest-$KORT"
  docker tag "$BILD" "$TAGG"
else
  TAGG="$BILD"
fi

DIGEST="$(docker image inspect "$TAGG" --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}')"
ID="$(docker image inspect "$TAGG" --format '{{.Id}}')"
# Arkivnamnet bar bildens id, sa att en rorlig tagg (latest, qwen38) som hamtas
# igen inte skriver over ett tidigare arkiv.
FIL="$(echo "$TAGG" | tr '/:' '__')_${ID#sha256:}"; FIL="${FIL:0:$(( ${#FIL} - 52 ))}"
UT="/srv/images/$FIL.tar"
ARK="$(docker image inspect "$TAGG" --format '{{.Architecture}}')"
[[ "$ARK" == "arm64" ]] || { echo "STOPP: bilden ar byggd for '$ARK', Sparken kraver arm64. Sparar den inte." >&2; exit 1; }

echo "Sparar bilden till disk (tar nagra minuter)..."
if command -v zstd >/dev/null; then UT="$UT.zst"; else UT="$UT.gz"; fi
[[ -e "$UT" ]] && { echo "$UT finns redan (samma bild-id), sparar inte om."; exit 0; }
TMP="$UT.del"
if [[ "$UT" == *.zst ]]; then docker save "$TAGG" | zstd -T0 -q -o "$TMP" -f
else docker save "$TAGG" | gzip > "$TMP"; fi
mv "$TMP" "$UT"
( cd /srv/images && sha256sum "$(basename "$UT")" > "$(basename "$UT").sha256" )

{
  echo "bild:       $BILD"
  echo "tagg:       $TAGG"
  echo "digest:     ${DIGEST:-saknas (lokalt byggd)}"
  echo "id:         $ID"
  echo "arkitektur: $ARK"
  echo "fil:        $UT ($(du -h "$UT" | cut -f1))"
  echo "sparad:     $(date '+%F %T')"
} | tee "/srv/images/$FIL.kalla"
echo
echo "Satt i /etc/llm/llm.env:"
echo "  LLM_IMAGE=$TAGG"
echo "  LLM_IMAGE_ID=$ID"
echo "Aterstall utan nat med:  zstd -dc $UT | docker load   (eller gzip -dc)"
