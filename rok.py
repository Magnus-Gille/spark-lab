#!/usr/bin/env python3
"""Roktest 1-5: fungerar API:et som avsett? (README, "Dagens ordning", steg 9)

  ./rok.py                    alla tester, kanariefagel pa 80 % av max kontext
  ./rok.py --kontext 32000    kanariefagel pa ca 32 000 tokens
  ./rok.py --hoppa 4          hoppa over test 4 (tar tid vid stor kontext)
  ./rok.py --utan-tank        stang av tankande (Qwen: enable_thinking=false)

URL och nyckel lases fran /etc/llm/llm.env, eller fran miljovariablerna URL och KEY.
Nyckeln tas aldrig fran kommandoraden. Testen kontrollerar att API-kontraktet
haller (nyckel, kod som gar att tolka, lang prompt oklippt, verktygsanrop med
ratt argument); de bevisar inte modellkvalitet.
"""
import argparse
import ast
import json
import random
import re
import sys
import time

from _klient import anrop, modellinfo, resonemang, standard, utfyllnad

resultat = []


def rapport(nr, namn, ok, detalj=""):
    resultat.append(ok)
    print("%-2s %-34s %-5s %s" % (nr, namn, "OK" if ok else "FEL", detalj))
    sys.stdout.flush()


def chatt(url, nyckel, modell, text, extra, max_tokens=1500, **mer):
    kropp = {"model": modell, "temperature": 0, "max_tokens": max_tokens,
             "messages": [{"role": "user", "content": text}]}
    kropp.update(extra)
    kropp.update(mer)
    return anrop(url, nyckel, "/v1/chat/completions", kropp, timeout=3600)


def innehall(svar):
    m = svar["choices"][0]["message"]
    return (m.get("content") or ""), m


def kodblock(text):
    """Koden ur ett svar: forsta ```-blocket om det finns, annars hela texten."""
    m = re.search(r"```(?:python)?\n(.*?)```", text, re.S)
    return m.group(1) if m else text


def kodord():
    return "%s-%d" % (random.choice(["KANTARELL", "SKOGSHARE", "MOLNTOPP", "GRANRIS", "SJOFART"]), random.randint(100, 999))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--url")
    p.add_argument("--kontext", type=int, help="malstorlek i tokens for test 4")
    p.add_argument("--hoppa", type=int, action="append", default=[])
    p.add_argument("--utan-tank", action="store_true")
    a = p.parse_args()

    url, nyckel = standard(a.url)
    extra = {"chat_template_kwargs": {"enable_thinking": False}} if a.utan_tank else {}
    print("Mal: %s" % url)

    # 1. Modellistan
    modell, maxlen = modellinfo(url, nyckel)
    rapport(1, "modellista med nyckel", True, "modell=%s, max kontext=%s" % (modell, maxlen))

    # 2. Utan nyckel
    if 2 not in a.hoppa:
        kod, _ = anrop(url, "", "/v1/models", timeout=30)
        rapport(2, "avvisas utan nyckel", kod == 401, "HTTP %s (vantat 401)" % kod)

    # 3. Kodfraga: svaret ska vara tolkbar Python med en funktion
    if 3 not in a.hoppa:
        t0 = time.time()
        kod, svar = chatt(url, nyckel, modell, "Skriv en Python-funktion som vander en strang. Bara kod.", extra)
        if kod == 200:
            text, m = innehall(svar)
            slut = svar["choices"][0].get("finish_reason")
            u = svar.get("usage", {})
            try:
                trad = ast.parse(kodblock(text))
                har_def = any(isinstance(n, ast.FunctionDef) for n in ast.walk(trad))
                tolk = "tolkbar" if har_def else "ingen funktion"
            except SyntaxError as e:
                har_def, tolk = False, "syntaxfel: %s" % e
            rapport(3, "kodfraga", har_def and slut == "stop",
                    "finish=%s, %s tokens ut, %d tecken tankande, %s, %.1f s%s"
                    % (slut, u.get("completion_tokens"), len(resonemang(m)), tolk, time.time() - t0,
                       "  <- tankandet at upp max_tokens, prova --utan-tank" if slut == "length" and not text else ""))
        else:
            rapport(3, "kodfraga", False, "HTTP %s: %s" % (kod, str(svar)[:160]))

    # 4. Kanariefagel: avslojar tyst trunkering av langa prompter. Tva slumpade
    #    kodord, ett forst och ett i mitten; fragan sist. Klipps borjan forsvinner
    #    det forsta, klipps slutet forsvinner fragan, klipps mitten det andra.
    if 4 not in a.hoppa:
        SVAR_BUDGET = 6000
        mal = a.kontext or (int(maxlen * 0.8) if maxlen else 8000)
        if maxlen and mal + SVAR_BUDGET > maxlen:
            mal = maxlen - SVAR_BUDGET
            print("   (kontextmalet sankt till %d sa att prompt + svarsbudget %d ryms i %d)" % (mal, SVAR_BUDGET, maxlen))
        k1, k2 = kodord(), kodord()
        fraga = ("\nTva kodord star i det har meddelandet: ett pa allra forsta raden och ett "
                 "pa en rad som borjar med 'Andra kodordet'. Svara bara med de tva kodorden, "
                 "i den ordningen, atskilda med ett mellanslag.")
        # Kalibrera tokens per rad med en liten forfragan
        kod, svar = chatt(url, nyckel, modell, utfyllnad(200, fro=1), extra, max_tokens=1)
        if kod != 200:
            rapport(4, "kanariefagel", False, "kalibrering misslyckades, HTTP %s: %s" % (kod, str(svar)[:160]))
        else:
            per_rad = svar["usage"]["prompt_tokens"] / 200.0
            rader = max(10, int(mal / per_rad))  # prompten ska ligga PA malet, inte under
            fro = int(time.time())
            text = "Kodordet ar %s.\n%s\nAndra kodordet ar %s.\n%s%s" % (
                k1, utfyllnad(rader // 2, fro=fro), k2, utfyllnad(rader - rader // 2, fro=fro + 1), fraga)
            t0 = time.time()
            kod, svar = chatt(url, nyckel, modell, text, extra, max_tokens=SVAR_BUDGET)
            if kod == 200:
                ut, m = innehall(svar)
                slut = svar["choices"][0].get("finish_reason")
                pt = svar.get("usage", {}).get("prompt_tokens", 0)
                vantat = rader * per_rad   # uppskattning fran kalibreringen, ingen oberoende tokenrakning
                hel = pt > 0.95 * vantat
                ordning = ut.strip().split()
                ratt_ordning = len(ordning) >= 2 and ordning[0] == k1 and ordning[1] == k2
                traff = (k1 in ut, k2 in ut)
                orsak = ""
                if slut == "length" and not ut:
                    orsak = "  <- otillracklig svarsbudget (tankandet), kor om med --utan-tank"
                elif not hel:
                    orsak = "  <- MISSTANKT TRUNKERING: servern rapporterar farre tokens an uppskattat skickat"
                elif not all(traff):
                    orsak = "  <- kodord saknas trots att tokenantalet stammer: kontextaterhamtning eller trunkering i mitten"
                elif not ratt_ordning:
                    orsak = "  <- bada kodorden finns men inte i ratt ordning/form"
                elif slut != "stop":
                    orsak = "  <- finish_reason ar inte stop"
                rapport(4, "kanariefagel, lang prompt", all(traff) and hel and ratt_ordning and slut == "stop",
                        "prompt_tokens=%s (uppskattat %d), kodord forst %s, mitten %s, finish=%s, %.0f s%s"
                        % (pt, vantat, "ratt" if traff[0] else "SAKNAS", "ratt" if traff[1] else "SAKNAS",
                           slut, time.time() - t0, orsak))
            else:
                rapport(4, "kanariefagel, lang prompt", False, "HTTP %s: %s" % (kod, str(svar)[:160]))

    # 5. Verktygsanrop: ratt funktion OCH ratt argument som giltig JSON
    if 5 not in a.hoppa:
        verktyg = [{"type": "function", "function": {
            "name": "las_fil", "description": "Laser en textfil och returnerar innehallet.",
            "parameters": {"type": "object", "properties": {"sokvag": {"type": "string"}}, "required": ["sokvag"]}}}]
        kod, svar = chatt(url, nyckel, modell, "Anvand verktyget for att lasa filen README.md.", extra, tools=verktyg)
        if kod == 200:
            _, m = innehall(svar)
            anropen = m.get("tool_calls") or []
            namn = anropen[0]["function"]["name"] if anropen else None
            arg_ok, arg_txt = False, ""
            if anropen:
                arg_txt = anropen[0]["function"].get("arguments") or ""
                try:
                    arg_ok = json.loads(arg_txt).get("sokvag", "") == "README.md"
                except (ValueError, AttributeError):
                    arg_ok = False
            rapport(5, "verktygsanrop", namn == "las_fil" and arg_ok,
                    "tool_calls=%d, namn=%s, argument=%s%s" % (
                        len(anropen), namn, arg_txt[:60].replace("\n", " "),
                        "" if anropen else "  <- kom som text: " + (m.get("content") or "")[:80].replace("\n", " ")))
        else:
            rapport(5, "verktygsanrop", False, "HTTP %s: %s" % (kod, str(svar)[:160]))

    print("\n%d av %d godkanda. Test 6 (start utan nat) och 7 (omstart) gors for hand, se README." % (sum(resultat), len(resultat)))
    sys.exit(0 if all(resultat) else 1)


if __name__ == "__main__":
    main()
