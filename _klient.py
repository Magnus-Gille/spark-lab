"""Gemensamma hjalpfunktioner for rok.py och bench.py. Bara standardbiblioteket."""
import hashlib
import json
import os
import subprocess
import urllib.error
import urllib.request

ENV_FIL = "/etc/llm/llm.env"
ARG_FIL = "/etc/llm/serve.args"


def las_env():
    """Laser /etc/llm/llm.env (via sudo om det behovs). Enkel tolkning:
    NYCKEL=varde, valfria raka citattecken runt vardet, ingen expansion."""
    try:
        text = open(ENV_FIL).read()
    except PermissionError:
        text = subprocess.run(["sudo", "cat", ENV_FIL], capture_output=True, text=True, check=True).stdout
    except FileNotFoundError:
        return {}
    env = {}
    for rad in text.splitlines():
        rad = rad.strip()
        if rad and not rad.startswith("#") and "=" in rad:
            k, v = rad.split("=", 1)
            env[k.strip()] = v.strip().strip('"')
    return env


def standard(url=None):
    """URL och nyckel fran argument/miljovariabler (URL, KEY) eller llm.env.
    Nyckeln tas aldrig fran kommandoraden."""
    url = url or os.environ.get("URL")
    nyckel = os.environ.get("KEY")
    if not url or not nyckel:
        env = las_env()
        if not url:
            adr = env.get("LLM_BIND", "127.0.0.1")
            if adr in ("0.0.0.0", ""):
                adr = "127.0.0.1"
            url = "http://%s:%s" % (adr, env.get("LLM_PORT", "8000"))
        nyckel = nyckel or env.get("VLLM_API_KEY", "")
    return url.rstrip("/"), nyckel


def sparbarhet(url=""):
    """Modellkatalog, revision, bild-id och hash av serve.args (konfigurationen pa
    disk), samt den korande containerns bild-id nar motorn kor pa den har maskinen."""
    env = las_env()
    ut = {"modellkatalog": env.get("LLM_MODEL_DIR", ""), "revision": "", "bild": env.get("LLM_IMAGE", ""),
          "bild_id": env.get("LLM_IMAGE_ID", "")[:19], "args_hash": "", "korande_bild": ""}
    if any(h in url for h in ("127.0.0.1", "localhost", "[::1]")):
        try:
            r = subprocess.run(["docker", "container", "inspect", "llm", "--format", "{{.Image}}"],
                               capture_output=True, text=True, timeout=10)
            if r.returncode == 0:
                ut["korande_bild"] = r.stdout.strip()[:19]
        except (OSError, subprocess.TimeoutExpired):
            pass
    try:
        for rad in open("/srv/models/%s.kalla" % ut["modellkatalog"]):
            if rad.startswith("revision:"):
                ut["revision"] = rad.split(":", 1)[1].strip()
    except OSError:
        pass
    try:
        ut["args_hash"] = hashlib.sha256(open(ARG_FIL, "rb").read()).hexdigest()[:12]
    except OSError:
        pass
    return ut


def anrop(url, nyckel, sokvag, kropp=None, timeout=600):
    """Ett HTTP-anrop. Returnerar (statuskod, tolkad JSON eller text)."""
    data = json.dumps(kropp).encode() if kropp is not None else None
    huvud = {"Content-Type": "application/json"}
    if nyckel:
        huvud["Authorization"] = "Bearer " + nyckel
    req = urllib.request.Request(url + sokvag, data=data, headers=huvud)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as svar:
            text = svar.read().decode()
            kod = svar.status
    except urllib.error.HTTPError as e:
        text = e.read().decode(errors="replace")
        kod = e.code
    try:
        return kod, json.loads(text)
    except ValueError:
        return kod, text


def modellinfo(url, nyckel):
    """(modellnamn, max kontext eller None) fran /v1/models."""
    kod, svar = anrop(url, nyckel, "/v1/models", timeout=30)
    if kod != 200 or not isinstance(svar, dict) or not svar.get("data"):
        raise SystemExit("Fick inget svar fran %s/v1/models (HTTP %s): %s" % (url, kod, str(svar)[:200]))
    m = svar["data"][0]
    return m["id"], m.get("max_model_len")


def resonemang(m):
    """Resonemangstext ur ett message/delta. vLLM >= 0.30: 'reasoning', aldre: 'reasoning_content'."""
    return m.get("reasoning") or m.get("reasoning_content") or ""


def utfyllnad(rader, fro=0):
    """Kodliknande utfyllnad. Olika fro ger olika text (viktigt mot prefixcache)."""
    import random
    r = random.Random(fro)
    ord_ = ["order", "kund", "faktura", "lager", "rapport", "session", "kalender", "betalning", "logg", "profil"]
    verb = ["hamta", "spara", "validera", "rakna", "sortera", "filtrera", "skicka", "tolka", "uppdatera", "radera"]
    ut = []
    for i in range(rader):
        a, b, n = r.choice(verb), r.choice(ord_), r.randint(1, 9999)
        ut.append("def %s_%s_%d(x, y=%d):  # rad %d\n    return [v for v in x if v %% %d == y]" % (a, b, n, r.randint(0, 9), i, r.randint(2, 97)))
    return "\n".join(ut)
