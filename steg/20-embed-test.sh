#!/usr/bin/env bash
# Steg 20: roktest for embeddingmodellen pa port 8002 (eller $1): dimension,
# normalisering, och att en kodfraga ligger narmare ratt dokument an fel.
set -uo pipefail
P="${1:-8002}"; URL="http://127.0.0.1:$P"
KEY="$(sudo sed -n 's/^VLLM_API_KEY=//p' /etc/llm/llm.env | tr -d '"')"
hdr() { printf 'header = "Authorization: Bearer %s"\n' "$KEY"; }
echo "modeller: $(hdr | curl -s -K - -m 10 "$URL/v1/models" | grep -o '"id":"[^"]*"' | head -n1)"
python3 - "$URL" "$KEY" <<'PY'
import json, sys, urllib.request, math
url, key = sys.argv[1], sys.argv[2]
def emb(texts):
    req = urllib.request.Request(url + "/v1/embeddings", data=json.dumps({"model": "embed", "input": texts}).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    d = json.load(urllib.request.urlopen(req, timeout=120))
    return [x["embedding"] for x in d["data"]], d.get("usage", {})
q = "task: code retrieval | query: funktion som vander en strang"
docs = ["title: none | text: def vand(s):\n    return s[::-1]",
        "title: none | text: SELECT kund_id, SUM(belopp) FROM orderrad GROUP BY kund_id",
        "title: none | text: Mötet flyttas till torsdag klockan tio."]
v, u = emb([q] + docs)
n = [math.sqrt(sum(a*a for a in x)) for x in v]
cos = lambda a, b: sum(x*y for x, y in zip(a, b)) / (math.sqrt(sum(x*x for x in a)) * math.sqrt(sum(y*y for y in b)))
print("dimension:", len(v[0]), " norm:", round(n[0], 3), " usage:", u)
s = [cos(v[0], d) for d in v[1:]]
for t, c in zip(["python vand", "sql", "svenska mote"], s):
    print("  likhet fraga/%-12s %.3f" % (t, c))
ok = len(v[0]) == 768 and s[0] > s[1] and s[0] > s[2]
print("EMBED-TEST", "OK" if ok else "FEL")
sys.exit(0 if ok else 1)
PY
