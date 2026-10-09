# Repot: hur det är byggt och hur man ändrar det

README beskriver hur man driver maskinen. Den här filen beskriver repot självt:
hur delarna hänger ihop, hur de når maskinen, vad som gör körningar spårbara och
vad man gör när man lägger till något. Läs den innan du ändrar ett skript.

## Tre lager

| Lager | Var | Princip |
| --- | --- | --- |
| Verktyg | skripten i roten | Ett verktyg per uppgift, generiskt, styrt av argument. Filhuvudet säger vad det gör, hur det anropas och om det ändrar maskinen. Inga värden för en viss dag står i verktygen |
| Recept | `recept/*.args` | En vLLM-flagga per rad. Kopieras till `/etc/llm/serve.args` av `install.sh` eller `byt-modell.sh`. Källan (playbook, modellkort, forumtråd) står i filhuvudet. `recept/varianter/` har avvikelser från ett recept |
| Moment | `steg/NN-*.sh` | Tunna skal med dagens konkreta värden (modellnamn, revisioner, bildtaggar) som anropar verktygen, så att varje moment är ett kommando. Numreringen är historisk, inte en tvingande ordning |

Runt lagren finns systemd-enheterna (`llm.service`, `llm@.service`), mallen
`llm.env.mall`, `eval/` (uppgifter och exempel för kvalitetsmått) och `docs/`.
Regeln: ändras en modell, en revision eller en tagg, ändras ett moment eller ett
recept, inte ett verktyg. Behöver ett moment något verktyget inte kan, lär
verktyget det med ett argument.

| Fil | Lager och roll |
| --- | --- |
| `kolla.sh` | verktyg, förkontroll: verktyg, rättigheter, GPU, disk, nät. Ändrar inget |
| `lage.sh` | verktyg, förbereder: sparar maskinens läge, skapar `/srv`-katalogerna |
| `system.sh` | verktyg, förbereder: maskinens värden, rådata till `/srv/llm` |
| `hamta.sh` | verktyg, hämtar modell: låst revision, `.sha256`, `.kalla` |
| `bild.sh` | verktyg, hämtar containerbild: sparas som fil med `.sha256` och `.kalla` |
| `install.sh` | verktyg, driftsätter: repot till `/usr/local/lib/llm`, `llm.service`, `llm.env`, `serve.args` |
| `start.sh` | verktyg, drift: bygger `docker run` från `llm.env` och `serve.args`; körs av systemd |
| `byt-modell.sh` | verktyg, drift: byter modell, recept och vid behov bild, startar om, röktest |
| `verifiera.sh` | verktyg, drift: kontrollerar checksummor; `frys` skriver dem |
| `rok.py`, `bench.py`, `eval.py` | verktyg, mäter: röktest, hastighet, kvalitet; läser API:et, ändrar inte motorn |
| `_klient.py` | delad kod för de tre mätverktygen, bara standardbiblioteket |
| `diag.sh` | verktyg, felsöker: översikt och delkommandon, ändrar inget (`cache` frågar först) |
| `stada.sh`, `spela-in.sh` | verktyg, avslutar och spelar in terminalen; `stada.sh` tar inte bort något själv |
| `llm.service`, `llm@.service` | systemd-enheter: huvudtjänsten och instansmallen |
| `llm.env.mall` | mall för `/etc/llm/llm.env` |
| `README.md`, `FELSOK.md` | dokumentation: driva maskinen; symptom till kommando |
| `steg/`, `recept/`, `eval/`, `docs/` | moment, recept, kvalitetsuppgifter, fördjupningar |
| `.gitignore` | håller tillståndet ur träden (nästa avsnitt) |

## Kod och tillstånd

Repot har bara kod och dokumentation. Tillståndet ligger på maskinen och ska
aldrig hamna i en commit:

| Var | Vad |
| --- | --- |
| `/etc/llm` | `llm.env` (med API-nyckeln, 600, root), `serve.args`, `konfig.sha256` |
| `/srv/models` | modeller med `.sha256` och `.kalla` |
| `/srv/images` | sparade containerbilder med `.sha256` och `.kalla` |
| `/srv/llm` | labbkontots arbetskatalog: `bench.csv`, `eval.csv`, lägesfiler, diagnos, överlämning |

`.gitignore` utesluter `*.env`, `bench.csv`, `svar/`, `__pycache__/` och `debate/`
för fall då en mätning eller en kopia av en env-fil hamnar i klonen. Nyckeln
skapas av `install.sh` på maskinen och passerar aldrig ett kommandos argument
och aldrig repot. Mallen `llm.env.mall` har en tom nyckelrad och är den enda
env-liknande filen som är incheckad.

## Från repo till maskin

```bash
git clone https://github.com/Magnus-Gille/spark-lab   # eller git pull i en befintlig klon
./install.sh recept/<fil>.args                        # klonen -> /usr/local/lib/llm
./verifiera.sh frys                                   # skriver /etc/llm/konfig.sha256
./verifiera.sh                                        # kontrollerar allt utan nät
```

`install.sh` kopierar skripten (`*.sh`, `*.py`, `steg/*.sh`) med läge 755 och
övriga filer (`*.md`, `*.mall`, `*.service`, `recept/`, `steg/*.md`, `eval/`,
`docs/`) med 644, alla ägda av root, så att klonen kan tas bort. `.git` och
`.gitignore` följer inte med. Skriptet tar aldrig bort något i målet och skriver
aldrig över en befintlig `/etc/llm/llm.env` eller `/etc/llm/serve.args`; de
skapas bara om de saknas. Ändrade recept når därför inte en körande maskin av sig
självt: kopiera dem med `byt-modell.sh` eller `sudo cp`. `llm.service` läggs i
`/etc/systemd/system/` av `install.sh`; `llm@.service` av `steg/16-instans.sh`.

Efter en `git pull` säger `./verifiera.sh` FEL på konfiguration tills
`./install.sh` och `./verifiera.sh frys` körts igen: `frys` har checksummor för
allt i `/usr/local/lib/llm`, och installationen ändrar filerna. Det är avsikten.
Frysningen svarar på frågan "är det som kör exakt det som levererades?", och en
uppdatering ska vara ett medvetet beslut, inte något som syns först när någon
kontrollerar. Samma gäller en ändring av `serve.args`, av `llm.env` (utan
nyckelraden) eller av `llm.service`, till exempel via `byt-modell.sh`. En fil som
tagits bort ur repot ligger kvar i `/usr/local/lib/llm` tills någon tar bort den
för hand, och ingår då fortfarande i frysningen.

## Hur start.sh bygger kommandot

`start.sh` körs av systemd (eller för hand) och gör i ordning:

1. Läser `LLM_ENV` (standard `/etc/llm/llm.env`) och `LLM_ARGS` (standard `/etc/llm/serve.args`).
2. Kräver `LLM_IMAGE`, `LLM_IMAGE_ID`, `LLM_MODEL_DIR` och `VLLM_API_KEY`. Övriga
   variabler har standardvärden: `LLM_NAME=kod`, `LLM_BIND=127.0.0.1`,
   `LLM_PORT=8000`, `LLM_ENTRYPOINT=vllm`, `LLM_CONTAINER=llm`. `LLM_DOCKER_EXTRA`
   delas i ord utan globbning och läggs på `docker run`.
3. Kräver att modellkatalogen finns under `/srv/models` med både `.kalla` och
   `.sha256`, alltså att `hamta.sh` gått klart.
4. Kontrollerar att bilden finns lokalt och att dess id är exakt `LLM_IMAGE_ID`.
   Containern startas med `--pull=never`, så ingenting hämtas vid start.
5. Läser `serve.args` rad för rad: tomma rader och `#`-rader hoppas över, och
   raden delas vid första blanktecknet, så JSON-värden behöver inga citattecken.
6. Monterar bara den valda modellen, skrivskyddad, och skickar nyckeln som
   miljövariabel (`-e VLLM_API_KEY`), aldrig som `--api-key`.
7. Med `--visa` skrivs kommandot ut med nyckeln maskad och inget ändras. Annars
   tas en gammal container med samma namn bort, men bara om den bär etiketten
   `spark-lab`; en främmande container stoppar starten.

Flera motorer: `llm@.service` sätter `LLM_ENV=/etc/llm/<namn>.env`,
`LLM_ARGS=/etc/llm/<namn>.args` och `LLM_CONTAINER=llm-<namn>`, och `start.sh` är
samma skript. Varje instans behöver egen port och egen minnesandel. Det är
**oprövat på en Spark**; grundregeln är en modell i taget.

## Spårbarhet

- `hamta.sh` slår upp revisionen till en full commit och stoppar om det inte går,
  hämtar till `<mål>.del-<commit>`, kontrollerar att alla filers metadata pekar
  på den commiten, skriver `.sha256` (manifest över filerna) och `.kalla` (källa,
  revision, tid, storlek) och publicerar först därefter. Ett avbrott lämnar
  därför aldrig en halv modell som ser färdig ut.
- `bild.sh` sparar bilden som `tar.zst` (eller `tar.gz`) med id i filnamnet,
  `.sha256` och en `.kalla` med tagg, id, digest och arkitektur. Id och tagg
  används, inte digest: `docker save` och `docker load` behåller taggen och
  bildens id men inte registrets digest, så en digestlåst start vore omöjlig
  utan nät. `llm.env` har därför `LLM_IMAGE` (taggen) och `LLM_IMAGE_ID`.
- `bench.csv` och `eval.csv` bär `revision`, `bild_id`, `korande_bild` och
  `args_hash` på varje rad. Därmed går en siffra att knyta till modell, bild och
  flaggor, och `korande_bild` avslöjar en konfiguration som ändrats utan omstart.
  Kolumnerna står i `docs/kolumner.md`.

## Säkerhetsmodellen i korthet

- Det som systemd kör som root ligger i `/usr/local/lib/llm`, rootägt och inte
  skrivbart för labbkontot. Klonen körs aldrig som root av tjänsten.
- Nyckeln skapas av `install.sh`, ligger i `llm.env` (600, root) och går aldrig via
  argv, repot eller en commit. Klienterna läser den ur filen eller miljön.
- Verifieringen är fail-closed: saknat manifest, saknad `.kalla` eller en ofryst
  konfiguration är FEL, inte "inga avvikelser". `start.sh` och `hamta.sh` stoppar
  hellre än gissar.
- Momenten i `steg/` som ändrar maskinen, och `byt-modell.sh`, visar sin plan och
  frågar `[j/N]`; bara `j` räknas som ja. `JA=1` hoppar över frågan i
  `byt-modell.sh` och `steg/10-variant.sh` (och därmed i `steg/11-batch.sh`);
  `steg/04`, `07`, `16` och `21` frågar men saknar `JA=1`. `install.sh` och
  `verifiera.sh frys` frågar inte.
- API:et lyssnar på `127.0.0.1` om inte `LLM_BIND` ändras. Trafiken är okrypterad
  HTTP.
- `--trust-remote-code` i ett recept betyder att modellens egen Python-kod körs i
  containern. Checksummorna visar bara att filerna inte ändrats, så bilden och
  modellrevisionen är det man litar på.

## Konventioner

- Svenska utan diakritiska tecken (å, ä, ö) i skript, utskrifter och filnamn, med
  diakritiska tecken i dokumentation.
- Inga hemligheter, värdnamn, IP-adresser eller kunduppgifter i träd eller historik.
  Repot är publikt: en rad som lagts till och tagits bort finns kvar i historiken.
- Bara grenen `main`. Commit-meddelanden på svenska utan diakritiska tecken.
- Har en modell skrivit ändringen avslutas commit-meddelandet med en
  `Co-Authored-By:`-trailer.
- Kontrollera efter push att den nådde GitHub:
  `gh api repos/Magnus-Gille/spark-lab/commits --jq '.[0].sha[0:7]'` ska ge samma
  hash som `git log -1 --format=%h`.
- Ändra ett skript: uppdatera filhuvudet i samma commit, och raden i `steg/README.md`
  eller `README.md` om beteendet syns där.

## Lägga till

| Du vill | Gör |
| --- | --- |
| Ny modell | `./hamta.sh <org/modell> <revision>`; nytt recept med `cp` från närmaste i `recept/` och källa i filhuvudet; `./byt-modell.sh <katalog> recept/<ny>.args [bildtagg]`; `./bench.py --etikett <ny>`; rad i kandidattabellen i README |
| Nytt moment | nästa lediga nummer i `steg/`, tunt skal som `cd`:ar till repots rot och anropar verktygen; rad i tabellen i `steg/README.md` (ändrar det maskinen: ja i kolumnen, `[j/N]`-fråga och stöd för `JA=1`, som `10-variant.sh`) |
| Nytt felsymptom | rad i rätt tabell i `FELSOK.md`: symptom, kommando, vad man letar efter |
| Ny vLLM-flagga | rad i flaggtabellen i `recept/README.md`: vad den gör och vad man ska veta |
| Ny fil i en ny katalog | lägg katalogen och filtypen i `install.sh`, annars når den inte `/usr/local/lib/llm` |

Nya skript i roten, nya moment, recept och dokument täcks av de mönster
`install.sh` redan använder. Efter ändringen: `./install.sh` och sedan
`./verifiera.sh frys`, annars visar nästa `./verifiera.sh` FEL.

## Testa utan en Spark

Det mesta går att pröva utan en GPU. Skalskripten har körts i en Linux-container
där `docker`, `hf` och `systemd`-kommandona ersatts av låtsade program som loggar
sina anrop; Python-skripten har körts mot en låtsasserver som svarar som API:et.
Det prövar logiken (argument, kontroller, filer som skrivs, felvägar), inte
vLLM, drivrutiner eller minne, som bara en riktig Spark visar. Skalskript
granskas med `shellcheck`; undantag skrivs som `# shellcheck disable=...` på raden
före. Pröva en felväg lika noga som huvudvägen, särskilt att ett skript
stoppar när ett manifest, en `.kalla` eller ett id saknas.
