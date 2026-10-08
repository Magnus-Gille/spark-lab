#!/usr/bin/env python3
"""Matning: tid till forsta token och tok/s
vid valt kontextdjup och antal samtidiga strommar.

  ./bench.py                                 tom kontext, 1 strom
  ./bench.py --djup 32000                    ca 32 000 tokens kontext, kall cache
  ./bench.py --djup 32000 --samtidiga 4      4 samtidiga strommar
  ./bench.py --djup 32000 --varm             delat prefix (pagaende dialog)
  ./bench.py --djup 32000 --kod ~/kundkod    fyll kontexten med riktiga filer (visar fillistan, fragar forst)

Varje matpunkt: en uppvarmning som slangs, sedan --varv omgangar med olika
uppgifter. Kall matning ger varje forfragan ett unikt prefix sa att prefixcachen
inte mats. Resultatet laggs ocksa till i bench.csv med modellrevision, bild-id
och hash av serve.args, sa att rader gar att jamfora i efterhand.

Vad siffrorna betyder:
  ttft_s           tid till forsta delta (resonemang, verktyg eller text), klientsidan
  ttft_text_s      tid till forsta synliga text- eller verktygsdelta
  tok_s_per_strom  (completion_tokens - 1) / tid fran forsta till sista delta, per strom.
                   Ett klientsidigt estimat: forsta chunken antas vara en token, vilket
                   inte behover galla vid spekulativ avkodning eller buffring.
  tok_s_totalt     summan av completion_tokens i ett varv / varvets vaggtid. Det ar
                   huvudmattet for jamforelse mellan kandidater.
  finish_length    antal svar som stoppades av max_tokens (OK for hastighet, inte for kvalitet)
Raden i CSV:n beskriver den konfiguration som ligger pa disk (llm.env, serve.args,
.kalla) plus mal-URL och, nar motorn kor lokalt, den korande containerns bild-id.
Andras konfigurationen utan omstart stammer inte raden med motorn.
En strom utan slutlig usage, utan [DONE] eller utan finish_reason raknas som fel,
inte som en gissning. Fem varv racker for att sortera kandidater, inte for att
skilja pa sma skillnader; upprepa nara en beslutsgrans. Kor inga stora
hamtningar, hashningar eller komprimeringar under en beslutande matning.
"""
import argparse
import csv
import json
import os
import statistics
import sys
import threading
import time
import urllib.request

from _klient import anrop, modellinfo, sparbarhet, standard, utfyllnad

UPPGIFTER = [
    "Skriv en Python-funktion som slar ihop tva sorterade listor utan att anvanda sort(). Inkludera tre enhetstester.",
    "Skriv en SQL-fraga som ger de fem kunder som handlat for mest per manad under 2025, givet tabellerna kund(id, namn) och orderrad(kund_id, datum, belopp).",
    "Forklara skillnaden mellan en mutex och en semafor och visa ett kort exempel i Go.",
    "Skriv ett bash-skript som hittar alla filer storre an 100 MB under en katalog och skriver ut dem sorterade efter storlek.",
    "Skriv en TypeScript-funktion som gor debounce pa en asynkron funktion och returnerar det senaste resultatet. Typa den generiskt.",
    "Granska koden och foresla forbattringar: def f(l):\n    r = []\n    for i in range(len(l)):\n        if l[i] not in r: r.append(l[i])\n    return r",
    "Skriv en C-funktion som vander en enkellankad lista pa plats och forklara tidskomplexiteten.",
]

HEMLIGT = (".env", ".pem", ".key", ".p12", ".pfx", "id_rsa", "id_ed25519", ".netrc", ".npmrc", ".pypirc",
           "credentials", "secret", ".htpasswd", ".kdbx", "passwd", "shadow")
HEMLIG_KATALOG = ("secret", "secrets", "credentials", "private", "keys", "certs", "node_modules", "vendor", "build", "dist")
MAX_PER_FIL = 200_000


def las_kod(katalog, max_tecken):
    """Slar ihop textfiler under katalogen till en lang strang. Hoppar over dolda
    filer och kataloger, symlankar och filnamn som brukar innehalla hemligheter.
    Returnerar (text, lista over anvanda filer)."""
    delar, n, anvanda = [], 0, []
    rot0 = os.path.realpath(os.path.expanduser(katalog))
    # os.walk itereras direkt (inte via sorted(), som skulle ga igenom hela tradet
    # innan filtret far verka). Katalogfiltret styr rekursionen.
    for rot, kataloger, filer in os.walk(rot0):
        kataloger[:] = sorted(d for d in kataloger if not d.startswith(".") and d.lower() not in HEMLIG_KATALOG
                              and not os.path.islink(os.path.join(rot, d)))
        for f in sorted(filer):
            sokvag = os.path.join(rot, f)
            if f.startswith(".") or os.path.islink(sokvag) or any(h in f.lower() for h in HEMLIGT):
                continue
            if not os.path.realpath(sokvag).startswith(rot0 + os.sep):
                continue
            try:
                t = open(sokvag, encoding="utf-8").read(MAX_PER_FIL + 1)
            except (UnicodeDecodeError, OSError):
                continue
            if len(t) > MAX_PER_FIL:
                continue
            delar.append("# fil: %s\n%s\n" % (os.path.relpath(sokvag, rot0), t))
            anvanda.append(os.path.relpath(sokvag, rot0))
            n += len(t)
            if n > max_tecken:
                return "".join(delar), anvanda
    return "".join(delar), anvanda


def en_strom(url, nyckel, kropp, ut):
    """En strommande forfragan. Fyller ut med ttft, total, tokens, finish.
    Fel om strommen inte avslutas med [DONE], saknar finish_reason eller slutlig usage."""
    kropp = dict(kropp, stream=True, stream_options={"include_usage": True})
    req = urllib.request.Request(url + "/v1/chat/completions", data=json.dumps(kropp).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + nyckel})
    t0 = time.perf_counter()
    forsta, forsta_text, sista, anv, finish, klar = None, None, None, {}, None, False
    try:
        with urllib.request.urlopen(req, timeout=3600) as svar:
            for rad in svar:
                rad = rad.decode("utf-8", "replace").strip()
                if not rad.startswith("data:"):
                    continue
                data = rad[5:].strip()
                if data == "[DONE]":
                    klar = True
                    break
                d = json.loads(data)
                if d.get("usage"):
                    anv = d["usage"]
                for val in d.get("choices") or []:
                    delta = val.get("delta") or {}
                    if val.get("finish_reason"):
                        finish = val["finish_reason"]
                    if delta.get("content") or delta.get("reasoning") or delta.get("reasoning_content") or delta.get("tool_calls"):
                        sista = time.perf_counter()
                        if forsta is None:
                            forsta = sista
                        if forsta_text is None and (delta.get("content") or delta.get("tool_calls")):
                            forsta_text = sista
    except Exception as e:  # noqa: BLE001
        ut["fel"] = "%s: %s" % (type(e).__name__, str(e)[:120])
        return
    if forsta is None:
        ut["fel"] = "inget innehall i svaret"; return
    if not klar:
        ut["fel"] = "strommen avslutades utan [DONE]"; return
    if not finish:
        ut["fel"] = "finish_reason saknas"; return
    ct = anv.get("completion_tokens")
    if not ct:
        ut["fel"] = "usage.completion_tokens saknas (stream_options.include_usage stods inte?)"; return
    ut.update(ttft=forsta - t0, ttft_text=(forsta_text - t0) if forsta_text else None, total=sista - t0,
              ut_tokens=ct, in_tokens=anv.get("prompt_tokens"), finish=finish,
              avkodning=(ct - 1) / (sista - forsta) if sista > forsta and ct > 1 else None)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--url")
    p.add_argument("--djup", type=int, default=0, help="kontext i tokens fore uppgiften")
    p.add_argument("--samtidiga", type=int, default=1)
    p.add_argument("--varv", type=int, default=5, help="antal omgangar (olika uppgifter)")
    p.add_argument("--max-tokens", type=int, default=400)
    p.add_argument("--varm", action="store_true", help="delat prefix, mater med traff i prefixcachen")
    p.add_argument("--kod", help="katalog med riktiga kodfiler som utfyllnad")
    p.add_argument("--ja", action="store_true", help="hoppa over fragan om fillistan vid --kod")
    p.add_argument("--utan-tank", action="store_true")
    p.add_argument("--etikett", default="", help="fri text till resultatraden, t.ex. A-mtp3")
    p.add_argument("--ut", default=("/srv/llm/bench.csv" if os.access("/srv/llm", os.W_OK) else "bench.csv"),
                   help="resultatfil (standard /srv/llm/bench.csv om den katalogen ar skrivbar)")
    a = p.parse_args()

    url, nyckel = standard(a.url)
    modell, maxlen = modellinfo(url, nyckel)
    bas = {"model": modell, "temperature": 0, "max_tokens": a.max_tokens}
    if a.utan_tank:
        bas["chat_template_kwargs"] = {"enable_thinking": False}
    if maxlen and a.djup + a.max_tokens + 500 > maxlen:
        sys.exit("djup %d + svar ryms inte i max kontext %d" % (a.djup, maxlen))

    # Underlag for kontexten och kalibrering av tokens per tecken
    if a.kod:
        underlag, filer = las_kod(a.kod, max(200000, a.djup * 8 * (a.varv * a.samtidiga + 2)))
        if len(underlag) < 2000:
            sys.exit("Hittade for lite text under %s" % a.kod)
        print("Foljande %d filer under %s skickas som kontext till %s:" % (len(filer), a.kod, url))
        for f in filer:
            print("  " + f)
        if not a.ja:
            if input("Fortsatt? [j/N] ").strip().lower() != "j":
                sys.exit("Avbrutet.")
    else:
        underlag = None
    per_tecken = 0.0
    if a.djup:
        prov = (underlag or utfyllnad(300, fro=7))[:20000]
        kod, svar = anrop(url, nyckel, "/v1/chat/completions",
                          dict(bas, max_tokens=1, messages=[{"role": "user", "content": prov}]))
        if kod != 200:
            sys.exit("Kalibrering misslyckades, HTTP %s: %s" % (kod, str(svar)[:200]))
        per_tecken = svar["usage"]["prompt_tokens"] / float(len(prov))

    def kontext(fro):
        if not a.djup:
            return ""
        tecken = int(a.djup / per_tecken)
        if underlag:
            if len(underlag) <= tecken:
                return (underlag * (tecken // len(underlag) + 1))[:tecken]
            start = (fro * 7919 * 1000) % (len(underlag) - tecken)
            return underlag[start:start + tecken]
        text = utfyllnad(int(tecken / 70) + 10, fro=fro)
        return text[:tecken]

    def meddelande(i):
        uppgift = UPPGIFTER[i % len(UPPGIFTER)]
        marke = "%d-%d" % (int(time.time() * 1000), i)
        if a.varm:   # samma prefix for alla, unikt bara i slutet
            return "%s\n\n# id %s\n%s" % (kontext(0), marke, uppgift)
        return "# id %s\n%s\n\n%s" % (marke, kontext(i + 1), uppgift)

    spar = sparbarhet(url)
    print("Modell %s | djup %d | samtidiga %d | %s | %d varv | tank %s | revision %s | bild %s | korande %s" % (
        modell, a.djup, a.samtidiga, "varm" if a.varm else "kall", a.varv, "nej" if a.utan_tank else "ja",
        spar["revision"][:12] or "?", spar["bild_id"] or "?", spar["korande_bild"] or "okand"))
    if spar["bild_id"] and spar["korande_bild"] and not spar["korande_bild"].startswith(spar["bild_id"]):
        print("OBS: korande container har bild %s men llm.env sager %s: konfigurationen pa disk ar inte den som kor."
              % (spar["korande_bild"], spar["bild_id"]))

    # Uppvarmning (slangs). Varm matning: fyller ocksa prefixcachen.
    u = {}
    en_strom(url, nyckel, dict(bas, messages=[{"role": "user", "content": meddelande(9999)}]), u)
    if "fel" in u:
        sys.exit("Uppvarmningen misslyckades: " + u["fel"])

    alla, totalt, fel, nr = [], [], 0, 0
    for v in range(a.varv):
        svar = [dict() for _ in range(a.samtidiga)]
        # Alla forfragningar byggs fore tidtagningen, sa att klientens textbygge
        # inte raknas in i vaggtiden. Tradarna startas sedan tatt efter varandra.
        kroppar = []
        for _ in svar:
            kroppar.append(dict(bas, messages=[{"role": "user", "content": meddelande(nr)}]))
            nr += 1
        tradar = [threading.Thread(target=en_strom, args=(url, nyckel, k, s)) for k, s in zip(kroppar, svar)]
        t0 = time.perf_counter()
        for t in tradar:
            t.start()
        for t in tradar:
            t.join()
        vagg = time.perf_counter() - t0
        bra = [s for s in svar if "fel" not in s]
        fel += len(svar) - len(bra)
        for s in svar:
            if "fel" in s:
                print("  fel: " + s["fel"])
        alla += bra
        if bra:
            totalt.append(sum(s["ut_tokens"] for s in bra) / vagg)
        print("  varv %d: %s" % (v + 1, ", ".join(
            "%.2fs/%.1f tok/s%s" % (s["ttft"], s["avkodning"] or 0, "" if s["finish"] == "stop" else "/" + s["finish"]) for s in bra)))
        sys.stdout.flush()

    if not alla:
        sys.exit("Inga lyckade forfragningar.")
    med = statistics.median
    avk = [s["avkodning"] for s in alla if s["avkodning"]]
    rad = {
        "tid": time.strftime("%Y-%m-%d %H:%M"), "modell": modell, "etikett": a.etikett, "url": url,
        "modellkatalog": spar["modellkatalog"], "revision": spar["revision"][:12],
        "bild_id": spar["bild_id"], "korande_bild": spar["korande_bild"], "args_hash": spar["args_hash"],
        "tank": "nej" if a.utan_tank else "ja", "max_tokens": a.max_tokens,
        "djup": a.djup, "in_tokens": int(med([s["in_tokens"] or 0 for s in alla])),
        "samtidiga": a.samtidiga, "cache": "varm" if a.varm else "kall",
        "ttft_s": round(med([s["ttft"] for s in alla]), 2),
        "ttft_max_s": round(max(s["ttft"] for s in alla), 2),
        "ttft_text_s": round(med([s["ttft_text"] for s in alla if s["ttft_text"]]), 2) if any(s["ttft_text"] for s in alla) else "",
        "tok_s_per_strom": round(med(avk), 1) if avk else "",
        "tok_s_totalt": round(med(totalt), 1),
        "ut_tokens": int(med([s["ut_tokens"] for s in alla])),
        "finish_length": sum(1 for s in alla if s["finish"] == "length"),
        "lyckade": len(alla), "fel": fel,
    }
    print("\nRESULTAT")
    for k, v in rad.items():
        print("  %-16s %s" % (k, v))
    if not a.varm and a.djup >= 4000 and rad["ttft_s"] > 0:
        print("  %-16s %d tok/s (in_tokens / forsta token, klientsidan)" % ("prefill ca", rad["in_tokens"] / rad["ttft_s"]))
    ny = not os.path.exists(a.ut)
    with open(a.ut, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rad))
        if ny:
            w.writeheader()
        w.writerow(rad)
    print("Tillagt i %s" % a.ut)
    if fel:
        print("OBS: %d forfragningar misslyckades; raden ar inte ett rent matvarde." % fel)
        sys.exit(1)


if __name__ == "__main__":
    main()
