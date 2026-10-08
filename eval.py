#!/usr/bin/env python3
"""Kvalitetsutvardering med kundens egna uppgifter: korbara tester avgor.

  ./eval.py eval/exempel.jsonl --etikett B                 alla uppgifter, 1 strom
  ./eval.py uppgifter.jsonl --etikett B --samtidiga 4      4 uppgifter parallellt
  ./eval.py uppgifter.jsonl --etikett B --utan-tank        tankande av
  ./eval.py uppgifter.jsonl --etikett B --sandbox python:3.12   testerna kors i Docker utan nat
  ./eval.py uppgifter.jsonl --etikett B --bara id1,id2     ett urval

Uppgiftsfil: en JSON-rad per uppgift med falten
  id        kort namn (unikt)
  prompt    instruktionen till modellen
  katalog   (valfri) katalog vars innehall kopieras till arbetskatalogen, relativt uppgiftsfilen
  filer     (valfri) lista med filer i katalogen som bifogas i prompten som kontext
  svarsfil  filen som modellens kod skrivs till (forsta ```-blocket i svaret)
  test      (valfri) kommando i arbetskatalogen; exitkod 0 = godkant. Saknas: "manuell"
  timeout   (valfri) sekunder for testet, standard 120
  system    (valfri) systemprompt

Varje uppgift far en egen arbetskatalog under svar/<etikett>/<id>/ med modellens
hela svar (svar.md), svarsfilen och testets utskrift (test.log), sa att en
manniska kan granska blint. eval.csv far en rad per uppgift och en summeringsrad.

Testerna kor pa den har maskinen med labbkontots rattigheter om inte --sandbox
anges; anvand bara uppgifter du litar pa, eller --sandbox.
"""
import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time

from _klient import anrop, modellinfo, resonemang, sparbarhet, standard


def las_uppgifter(sokvag):
    ut = []
    for n, rad in enumerate(open(sokvag, encoding="utf-8"), 1):
        rad = rad.strip()
        if not rad or rad.startswith("#"):
            continue
        try:
            u = json.loads(rad)
        except ValueError as e:
            sys.exit("%s rad %d: ogiltig JSON: %s" % (sokvag, n, e))
        for f in ("id", "prompt", "svarsfil"):
            if f not in u:
                sys.exit("%s rad %d: faltet '%s' saknas" % (sokvag, n, f))
        ut.append(u)
    ids = [u["id"] for u in ut]
    if len(ids) != len(set(ids)):
        sys.exit("Dubbla id i %s" % sokvag)
    return ut


def kodblock(text, svarsfil):
    """Forsta ```-blocket vars sprakmarkering passar filandelsen, annars forsta blocket, annars hela texten."""
    block = re.findall(r"```([A-Za-z0-9_+#.-]*)[ \t]*\n(.*?)```", text, re.S)
    if not block:
        return text.strip() + "\n"
    andelse = os.path.splitext(svarsfil)[1].lstrip(".").lower()
    for sprak, kod in block:
        if andelse and sprak.lower().startswith(andelse[:2]):
            return kod
    return block[0][1]


def kor_test(u, arb, sandbox):
    if not u.get("test"):
        return "manuell", "", 0.0
    t0 = time.perf_counter()
    if sandbox:
        cmd = ["docker", "run", "--rm", "--network", "none", "-v", "%s:/w" % arb, "-w", "/w", sandbox,
               "sh", "-c", u["test"]]
    else:
        cmd = ["sh", "-c", u["test"]]
    try:
        r = subprocess.run(cmd, cwd=arb, capture_output=True, text=True, timeout=u.get("timeout", 120))
        ut = (r.stdout + r.stderr)[-4000:]
        return ("pass" if r.returncode == 0 else "fail"), ut, time.perf_counter() - t0
    except subprocess.TimeoutExpired as e:
        return "timeout", ((e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or ""))[-4000:], time.perf_counter() - t0


def en_uppgift(u, bas, url, nyckel, a, rot, res):
    arb = os.path.join(a.svar, a.etikett, u["id"])
    shutil.rmtree(arb, ignore_errors=True)
    os.makedirs(arb)
    if u.get("katalog"):
        kat = os.path.join(rot, u["katalog"])
        if not os.path.isdir(kat):
            res.update(status="fel", detalj="katalogen %s saknas" % kat)
            return
        shutil.copytree(kat, arb, dirs_exist_ok=True)
    kontext = ""
    for f in u.get("filer") or []:
        try:
            kontext += "\n\n### %s\n```\n%s\n```" % (f, open(os.path.join(arb, f), encoding="utf-8").read())
        except OSError as e:
            res.update(status="fel", detalj="kontextfil %s: %s" % (f, e))
            return
    prompt = u["prompt"] + kontext + "\n\nSvara med hela innehallet i filen %s i ett enda kodblock." % u["svarsfil"]
    msgs = ([{"role": "system", "content": u["system"]}] if u.get("system") else []) + [{"role": "user", "content": prompt}]
    t0 = time.perf_counter()
    kod, svar = anrop(url, nyckel, "/v1/chat/completions", dict(bas, messages=msgs), timeout=3600)
    res["tid_modell"] = time.perf_counter() - t0
    if kod != 200 or not isinstance(svar, dict):
        res.update(status="fel", detalj="HTTP %s: %s" % (kod, str(svar)[:160]))
        return
    m = svar["choices"][0]["message"]
    text = m.get("content") or ""
    res["finish"] = svar["choices"][0].get("finish_reason")
    res["ut_tokens"] = (svar.get("usage") or {}).get("completion_tokens")
    res["in_tokens"] = (svar.get("usage") or {}).get("prompt_tokens")
    res["tankande"] = len(resonemang(m))
    with open(os.path.join(arb, "svar.md"), "w", encoding="utf-8") as f:
        f.write("# %s\n\n## Prompt\n\n%s\n\n## Resonemang (%d tecken)\n\n%s\n\n## Svar\n\n%s\n"
                % (u["id"], prompt, res["tankande"], resonemang(m)[:20000], text))
    if not text:
        res.update(status="fel", detalj="tomt svar (finish=%s, %d tecken tankande): hoj --max-tokens eller kor --utan-tank"
                   % (res["finish"], res["tankande"]))
        return
    with open(os.path.join(arb, u["svarsfil"]), "w", encoding="utf-8") as f:
        f.write(kodblock(text, u["svarsfil"]))
    status, logg, res["tid_test"] = kor_test(u, arb, a.sandbox)
    with open(os.path.join(arb, "test.log"), "w", encoding="utf-8") as f:
        f.write(logg)
    res["status"] = status
    res["detalj"] = logg.strip().splitlines()[-1][:120] if logg.strip() and status != "pass" else ""


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("uppgifter")
    p.add_argument("--url")
    p.add_argument("--etikett", required=True, help="namn pa korningen, t.ex. B eller B-mtp")
    p.add_argument("--samtidiga", type=int, default=1)
    p.add_argument("--max-tokens", type=int, default=24000,
                   help="svarstak inkl. tankande; Qwen3 tanker ofta 5-15k tokens pa en kodbugg (standard 24000)")
    p.add_argument("--utan-tank", action="store_true")
    p.add_argument("--sandbox", help="Docker-bild som testerna kors i (utan nat)")
    p.add_argument("--bara", help="kommaseparerade id att kora")
    p.add_argument("--svar", default="svar", help="katalog for svar och testloggar")
    p.add_argument("--ut", default=("/srv/llm/eval.csv" if os.access("/srv/llm", os.W_OK) else "eval.csv"))
    a = p.parse_args()

    upp = las_uppgifter(a.uppgifter)
    if a.bara:
        vill = set(a.bara.split(","))
        upp = [u for u in upp if u["id"] in vill]
    if not upp:
        sys.exit("Inga uppgifter att kora.")
    rot = os.path.dirname(os.path.abspath(a.uppgifter))
    url, nyckel = standard(a.url)
    modell, _ = modellinfo(url, nyckel)
    spar = sparbarhet(url)
    bas = {"model": modell, "temperature": 0, "max_tokens": a.max_tokens}
    if a.utan_tank:
        bas["chat_template_kwargs"] = {"enable_thinking": False}
    print("Eval %s | %d uppgifter | samtidiga %d | tank %s | modell %s rev %s | %s" % (
        a.etikett, len(upp), a.samtidiga, "nej" if a.utan_tank else "ja", spar["modellkatalog"] or modell,
        spar["revision"][:12] or "?", "sandbox " + a.sandbox if a.sandbox else "tester LOKALT utan sandbox"))

    resultat = {u["id"]: {"status": "", "detalj": "", "tid_modell": 0.0, "tid_test": 0.0,
                          "finish": "", "ut_tokens": "", "in_tokens": "", "tankande": 0} for u in upp}
    ko = list(upp)
    las = threading.Lock()
    t_start = time.perf_counter()

    def arbetare():
        while True:
            with las:
                if not ko:
                    return
                u = ko.pop(0)
            r = resultat[u["id"]]
            try:
                en_uppgift(u, bas, url, nyckel, a, rot, r)
            except Exception as e:  # noqa: BLE001
                r.update(status="fel", detalj="%s: %s" % (type(e).__name__, str(e)[:120]))
            with las:
                print("  %-24s %-8s %6.1fs modell %5.1fs test  %s" % (u["id"], r["status"], r["tid_modell"], r["tid_test"], r["detalj"]))
                sys.stdout.flush()

    tradar = [threading.Thread(target=arbetare) for _ in range(max(1, a.samtidiga))]
    for t in tradar:
        t.start()
    for t in tradar:
        t.join()
    vagg = time.perf_counter() - t_start

    n = len(upp)
    antal = {s: sum(1 for r in resultat.values() if r["status"] == s) for s in ("pass", "fail", "timeout", "manuell", "fel")}
    testade = antal["pass"] + antal["fail"] + antal["timeout"]
    andel = (antal["pass"] / testade) if testade else None
    print("\nRESULTAT %s: %d uppgifter, pass %d, fail %d, timeout %d, manuell %d, fel %d | pass-andel %s | %.0f s vaggtid | %.1f uppgifter/min"
          % (a.etikett, n, antal["pass"], antal["fail"], antal["timeout"], antal["manuell"], antal["fel"],
             ("%.0f %% av %d testade" % (100 * andel, testade)) + (" (OBS: %d fel ej medraknade)" % antal["fel"] if antal["fel"] else "")
             if andel is not None else "-", vagg, 60 * n / vagg if vagg else 0))
    print("Svar och testloggar: %s/%s/<id>/" % (a.svar, a.etikett))

    ny = not os.path.exists(a.ut)
    falt = ["tid", "etikett", "uppgiftsfil", "id", "status", "tid_modell_s", "tid_test_s", "in_tokens", "ut_tokens",
            "tankande_tecken", "finish", "detalj", "modell", "modellkatalog", "revision", "bild_id", "korande_bild",
            "args_hash", "tank", "max_tokens", "samtidiga", "sandbox"]
    with open(a.ut, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=falt)
        if ny:
            w.writeheader()
        for u in upp:
            r = resultat[u["id"]]
            w.writerow({"tid": time.strftime("%Y-%m-%d %H:%M"), "etikett": a.etikett, "uppgiftsfil": os.path.basename(a.uppgifter),
                        "id": u["id"], "status": r["status"], "tid_modell_s": round(r["tid_modell"], 1), "tid_test_s": round(r["tid_test"], 1),
                        "in_tokens": r["in_tokens"], "ut_tokens": r["ut_tokens"], "tankande_tecken": r["tankande"], "finish": r["finish"],
                        "detalj": r["detalj"], "modell": modell, "modellkatalog": spar["modellkatalog"], "revision": spar["revision"][:12],
                        "bild_id": spar["bild_id"], "korande_bild": spar["korande_bild"], "args_hash": spar["args_hash"],
                        "tank": "nej" if a.utan_tank else "ja", "max_tokens": a.max_tokens, "samtidiga": a.samtidiga, "sandbox": a.sandbox or ""})
        w.writerow({"tid": time.strftime("%Y-%m-%d %H:%M"), "etikett": a.etikett, "uppgiftsfil": os.path.basename(a.uppgifter), "id": "SUMMA",
                    "status": "%.0f %%" % (100 * andel) if andel is not None else "-", "tid_modell_s": round(vagg, 1),
                    "detalj": "pass %d fail %d timeout %d manuell %d fel %d" % (antal["pass"], antal["fail"], antal["timeout"], antal["manuell"], antal["fel"]),
                    "modell": modell, "modellkatalog": spar["modellkatalog"], "revision": spar["revision"][:12], "bild_id": spar["bild_id"],
                    "korande_bild": spar["korande_bild"], "args_hash": spar["args_hash"], "tank": "nej" if a.utan_tank else "ja",
                    "max_tokens": a.max_tokens, "samtidiga": a.samtidiga, "sandbox": a.sandbox or ""})
    print("Tillagt i %s" % a.ut)
    sys.exit(0 if antal["fel"] == 0 else 1)


if __name__ == "__main__":
    main()
