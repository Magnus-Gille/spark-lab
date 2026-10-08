# spark-lab

Skript för att sätta upp, mäta och frysa lokal LLM-inferens (vLLM i Docker) på en
NVIDIA DGX Spark. Allt är avsett att läsas innan det körs. Inga hemligheter eller
kunduppgifter hör hemma i det här repot: API-nyckeln skapas på maskinen.

Status 2026-10-08: hela flödet för kandidat B (hämta, spara bild, installera,
starta, röktest, mätning, frysning) är kört på en riktig DGX Spark med DGX OS 7.2
och `vllm/vllm-openai:qwen38`; siffrorna i dokumentationen kommer därifrån.
Kandidat C, varianterna och eval-exemplet körs i en obevakad serie samma dag.
Recepten för A, D och E är utgångslägen från playbook, modellkort och forumtrådar
och är inte provade. Skripten är dessutom testade i en Linux-container med
låtsade `docker`, `hf` och `systemd`, och Python-skripten mot en låtsasserver.
Repot har granskats i två rundor av en fristående modell; det som inte är
åtgärdat står under "Kända begränsningar".

## Ordlista

| Term | Betydelse |
| --- | --- |
| vLLM | Inferensmotorn som kör modellen och svarar på OpenAI-kompatibla API-anrop |
| GB10 | Sparkens chip: GPU och CPU med 128 GB gemensamt minne |
| NVFP4, FP8, bf16 | Hur många bitar varje modellvikt lagras i: 4, 8 respektive 16. NVFP4 är Blackwell-formatet som GB10 kör i hårdvara; mindre vikter ger plats för mer kontext |
| MoE | Mixture of experts: modellen aktiverar bara en del av sina parametrar per token (C: 3B av 35B), så avkodningen går fortare än storleken antyder |
| kontext, kontextfönster | Allt modellen ser i ett anrop: systemprompt, filer, konversation, svar. Mäts i tokens, ungefär 3 tecken per token för kod |
| KV-cache | Motorns arbetsminne för kontexten: varje token i varje pågående anrop tar några kB. Det som avgör hur många användare som ryms samtidigt |
| prefill | Fasen när modellen läser prompten; snabb per token men lång vid stora kontexter. Avgör tiden till första token |
| prefixcache | Återanvändning av KV-cache för en prompt-början motorn redan sett (samma systemprompt, samma filer). Gör andra anropet i en dialog mycket snabbare |
| MTP, spekulativ avkodning | Modellen gissar flera tokens i taget med ett litet extra huvud och verifierar; ger ungefär dubbla tok/s på en ensam ström |
| tok/s | Tokens per sekund. Per ström = vad en användare upplever; totalt = maskinens genomströmning |
| ttft | Time to first token: väntetiden innan svaret börjar |
| röktest | `rok.py`: fem snabba kontroller av att API:et fungerar som avsett |
| kanariefågel | Röktest 4: en prompt på nära maximal längd med kodord först och i mitten; avslöjar om motorn tyst klipper långa prompter |
| recept | En fil med vLLM-flaggor, en per rad, för en viss modell (`recept/`) |
| tmux | Terminalsessioner som överlever att du loggar ut; för timslånga nedladdningar och körningar |

## Karta

| Läs | När |
| --- | --- |
| den här filen | översikt, kandidater, dagens ordning, säkerhet |
| `FELSOK.md` | något krånglar: symptom, kommando, vad man letar efter |
| `steg/README.md` | vad varje skript i `steg/` gör, om det ändrar maskinen, och i vilken ordning |
| `recept/README.md` | varje vLLM-flagga förklarad, och vilka recept som är provade |
| `eval/README.md` | hur kundens egna uppgifter skrivs och körs som kvalitetsmått |
| `docs/kolumner.md` | varje kolumn i `bench.csv` och `eval.csv` |
| `docs/anvanda-api.md` | använda API:et från andra datorer: öppna porten, nyckel, inställningar, exempel per klient |
| filhuvudena | varje skript börjar med vad det gör, hur det anropas och om det ändrar något |

Konventioner: svenska utan diakritiska tecken i skript och utskrifter (säkrare i
terminaler), med diakritiska tecken i dokumentation. Allt som ändrar maskinen
visar sin plan och frågar först. Inga hemligheter, värdnamn eller kunduppgifter
hör hemma i repot.

## Förutsättningar på maskinen

- DGX OS med Docker och NVIDIA Container Toolkit (`docker run --gpus all` fungerar).
  Labbkontot har `sudo` och är medlem i gruppen `docker` under dagen (skripten
  kör `docker` utan sudo). Medlemskap i `docker` motsvarar root; `./stada.sh`
  påminner om att ta bort det om det var tillfälligt.
- `hf` (Hugging Face CLI): `pipx install 'huggingface_hub[cli]'` eller
  `sudo apt install pipx` först. Ingen inloggning behövs för modellerna nedan.
- `tmux`, `zstd`, `curl`, `python3`, `git` (`sudo apt install tmux zstd`).
- Utgående 443 till `huggingface.co`, dess CDN-värdar, `docker.io` och `github.com`
  under dagen, samt kundens paketkälla om `pipx`, `tmux` eller `zstd` saknas.
  `./kolla.sh` kontrollerar allt ovan utan att ändra något; `./diag.sh nat` visar
  vilka värdar som nås.

## Kom igång

```bash
cd ~ && git clone https://github.com/Magnus-Gille/spark-lab && cd spark-lab
git log -1 --format=%h        # jämför med samma kommando på den egna datorn
./kolla.sh                    # förkontroll, ändrar inget
```

Säger `kolla.sh` FEL på `hf`, `docker som <konto>`, `tmux` eller `zstd`: kör
`./steg/04-forutsattningar.sh`, logga ut och in igen, och kör `./kolla.sh` på
nytt. Säger den FEL på GPU: se FELSOK, "GPU:n syns inte", och `steg/01`–`03`.
När `kolla.sh` slutar med "Inga FEL" fortsätter du med tabellen under "Dagens
ordning", eller snabbspåret för B:

```bash
./lage.sh fore && ./system.sh        # före-läge och maskinens värden
tmux new -s hamta                     # i tmux: ./steg/05-hamta-b-c.sh   (Ctrl-b d lämnar)
./steg/06-bild-b.sh                   # containerbilden för B
./steg/07-installera-b.sh             # install.sh + llm.env ifylld automatiskt
sudo systemctl enable --now llm && journalctl -fu llm   # vänta på "Application startup complete", Ctrl-C
./rok.py                              # röktest 1–5
```

Första anropet för hand, med nyckeln ur `/etc/llm/llm.env` (modellen heter alltid `kod`):

```bash
KEY=$(sudo sed -n 's/^VLLM_API_KEY=//p' /etc/llm/llm.env)
curl -s http://127.0.0.1:8000/v1/chat/completions -H "Authorization: Bearer $KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"kod","messages":[{"role":"user","content":"Skriv en funktion som vänder en sträng i C#."}]}'
```

## Kandidater

Alla är NVFP4-kvantiserade (Blackwell-formatet som GB10 kör i hårdvara).
Revisionen är den commit som gällde 2026-10-07; ange den som andra argument
till `hamta.sh` så att samma filer hämtas igen.

| | Modell | Storlek | Licens | Bild | Recept |
|---|---|---|---|---|---|
| B | [nvidia/Qwen3.8-27B-NVFP4](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4) rev `482ca0f3832238542f8f5295dde86b5f22711d80` | 20 GiB | Apache-2.0 | `vllm/vllm-openai:qwen38` (NVIDIA:s [Spark-playbook](https://build.nvidia.com/spark/vllm)) | `recept/qwen38-27b.args` |
| C | [nvidia/Qwen3.6-35B-A3B-NVFP4](https://huggingface.co/nvidia/Qwen3.6-35B-A3B-NVFP4) rev `1355db6a052410cfd62085d94b58866fd0f2c3c5` | 22 GiB | Apache-2.0 | `vllm/vllm-openai:latest` (modellkortet) | `recept/qwen36-35b-a3b.args` |
| A | [nvidia/Qwen3.8-Flash-Next-NVFP4](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4) rev `fc694b54fb0174e0913e6adf86691ef85a4ead47` | 124 GiB | NVIDIA Open Model License + Qwen Community License | specialbyggd, se receptet | `recept/qwen38-flash-next.args` |
| D | [Cloudflare/clef-flash](https://huggingface.co/Cloudflare/clef-flash) rev `fde727a287004204b7518dcc983fe64379776712` | ~19 GB bf16 | Apache-2.0 | `vllm/vllm-openai:qwen38` (obekräftat) | `recept/clef-flash.args` |
| E | [Cloudflare/clef](https://huggingface.co/Cloudflare/clef) rev `ed3eed331870db2eff4b0db01237128ede8a00ce` | 55 GB bf16 | Apache-2.0 | samma | `recept/clef.args` |
| F | [google/embeddinggemma-2](https://huggingface.co/google/embeddinggemma-2) rev `914f7f89142e33e77833254d9c9b90c3cef7303b` | 1,5 GB | Apache-2.0 | `vllm/vllm-openai:cu134-nightly-81198e97…` (stödet är nyare än 0.31.0) | `recept/embeddinggemma-2.args` |

F är en embeddingmodell (768 dimensioner, 8k tokens, flerspråkig, tränad för
kodsökning) och körs som sidomodell `llm@embed` på port 8002 bredvid
kodmodellen, cirka 0,5 GiB minne. Reserv om den nattliga bilden krånglar:
`google/embeddinggemma-300m` på den vanliga bilden (`recept/embeddinggemma-300m.args`).
Klienten sätter själv prefixen `task: code retrieval | query: …` och
`title: none | text: …`; `./steg/20-embed-test.sh` kontrollerar dimension och
att en kodfråga hamnar närmast rätt dokument.

D och E är beslutsmodeller ("system 1", i stil med TypeSafes Jev): de svarar med ett
val och en sannolikhet i stället för text, för routing, klassning och
verktygsval. Valet gjordes 2026-10-08 efter en genomgång av öppna alternativ:
Jev självt är stängt; Perplexitys `pplx-decider` saknar vLLM-stöd; AutoTrusts
GEV-26B kräver patchad vLLM; JEV-9B (destillerad från Jevs utdata, inte av
TypeSafe) hålls som reserv. Clef är Cloudflares egen öppna familj under
Apache-2.0, och bf16-vikterna hämtas direkt från Cloudflare i stället för
community-kvantiseringar. Förbehåll: beslutshuvudet är egen modellkod
(`--trust-remote-code`), och det är obekräftat att sannolikheterna kommer ut
genom vanlig `vllm serve`; kortet för en NVFP4-variant anger 177 till 705 ms per
beslut på en Spark. Alternativen som föll bort är listade ovan; källorna är
modellkorten på Hugging Face.

Ordning: hämta B och C först och mät dem; D och E efter att baslinjen är fryst.
A (tre timmar) hämtas i en egen `tmux`-session mellan mätningarna, inte under
en beslutande mätning: hämtning, hashning och komprimering konkurrerar om disk,
CPU och minne. A kräver en containerbild från en forumtråd och ett licensbeslut;
den är kvalitetskandidat, inte baslinje.

Alternativ som valts bort: `unsloth/Qwen3.8-27B-NVFP4` (samma modell, fungerar
med receptet för B, men repot har haft tokenizer-trunkering) och
`unsloth/Qwen3.6-35B-A3B-NVFP4` (har fortfarande `truncation.max_length=16384`,
klipper långa prompter tyst).

Exempel:

```bash
./hamta.sh nvidia/Qwen3.8-27B-NVFP4 482ca0f3832238542f8f5295dde86b5f22711d80   # -> /srv/models/nvidia__Qwen3.8-27B-NVFP4
./bild.sh vllm/vllm-openai:qwen38
./install.sh recept/qwen38-27b.args
```

Licensgrinden för A (Qwen Community License: intern användning är undantagen
från villkoret om separat licens för "AI Work Assistant"-tjänster, men kundens
jurist avgör) tas innan de 124 GiB hämtas, inte efter.

## Dagens ordning

| Steg | Kommando | Vad det gör |
| --- | --- | --- |
| 0 | `./kolla.sh` | Förkontroll: verktyg, Docker-rättigheter, GPU, disk, nät. Ändrar inget |
| 1 | `./lage.sh fore` | Sparar före-läget (paket, konton, portar, rättigheter) och skapar `/srv/llm`, `/srv/models`, `/srv/images` |
| 2 | `./system.sh` | Skriver ut maskinens värden (OS, kärna, drivrutin, GPU, Docker, minne, disk) och sparar rådata |
| 3 | `./hamta.sh <org/modell> [revision]` | Hämtar modellen låst till en commit (anges, eller `main` slås upp), räknar checksummor. Kör i `tmux` |
| 4 | `./bild.sh <bild:tagg>` | Hämtar containerbilden, läser id och digest, sparar den som fil |
| 5 | `./install.sh recept/<fil>.args` | Lägger program och verktyg i `/usr/local/lib/llm`, systemd-enheten, `llm.env` och `serve.args` på plats |
| 6 | `sudo nano /etc/llm/llm.env` | Fyll i `LLM_IMAGE`, `LLM_IMAGE_ID` (från steg 4) och `LLM_MODEL_DIR` (från steg 3) |
| 7 | `sudo /usr/local/lib/llm/start.sh --visa` | Granska det exakta kommandot innan start |
| 8 | `sudo systemctl enable --now llm` och `journalctl -fu llm` | Starta och följ laddningen |
| 9 | `./rok.py` | Röktest 1–5: modellista med nyckel, 401 utan nyckel, kodfråga som ska vara tolkbar Python, kanariefågel på ~80 % av max kontext (tar 3–5 min), verktygsanrop med rätt argument. Allt ska bli OK |
| 10 | `./bench.py --djup 32000 --samtidiga 4 --etikett B` | Mätning, läggs till i `bench.csv` |
| 11 | `./verifiera.sh frys` och `./verifiera.sh` | Fryser checksummor för konfiguration och verktyg; kontrollerar modeller, bilder och konfiguration utan nät |
| 12 | Offlineåterstart, se nedan | Kunden startar om tjänsten från de sparade filerna utan nät och utan klonen |
| 13 | `./stada.sh` | Visar vad som ändrats sedan steg 1 och vad som återstår att ta bort |

Byta kandidat: `./hamta.sh` nästa modell, ändra `LLM_MODEL_DIR` (och vid behov
`LLM_IMAGE`/`LLM_IMAGE_ID`) i `llm.env`, `sudo cp recept/<fil>.args /etc/llm/serve.args`,
`sudo systemctl restart llm`. Alla kandidater heter `kod` mot klienterna;
`bench.csv` skiljer dem åt på modellkatalog, revision, bild-id och hash av `serve.args`.

`llm.service` levereras med `Restart=no`: varje misslyckad start kostar en
modelladdning, och en frekvensgräns skyddar inte mot långsamma slingor. Tjänsten
startar vid boot men inte om efter krasch. När konfigurationen är fryst och
provad kan kunden sätta `Restart=on-failure` i enheten.

## Prova en ny modell

Hela flödet är fyra kommandon och ett recept. Allt loggas i `bench.csv` med
modellrevision, bild-id och hash av flaggorna, så att körningar går att jämföra.

```bash
./hamta.sh <org/modell> [revision]            # 1. till /srv/models/<org>__<modell>, låst commit
cp recept/qwen38-27b.args recept/<ny>.args    # 2. utgå från närmaste recept, se modellkortet
./byt-modell.sh <org>__<modell> recept/<ny>.args [bildtagg]   # 3. byter, startar om, röktest
./bench.py --etikett <ny> --djup 32000        # 4. mät; jämför raderna i /srv/llm/bench.csv
```

Behöver modellen en nyare vLLM-bild: `./bild.sh <bild:tagg>` först, och ange taggen
som tredje argument. `./rok.py` (med kanariefågeln) körs när modellen ska in i
drift, inte vid varje prov. Tillbaka till den frysta modellen:
`./byt-modell.sh <katalog> recept/<fil>.args` med värdena från `/etc/llm/konfig.sha256`
eller `./verifiera.sh`. Ta bort en bortvald modell med
`rm -rf /srv/models/<katalog> /srv/models/<katalog>.sha256 /srv/models/<katalog>.kalla`.

Vad som styr tok/s på Sparken, i fallande ordning: spekulativ avkodning (MTP) om
modellen har ett MTP-huvud, aktiva parametrar (MoE-modeller avkodar snabbare än
storleken antyder), prefixcache för upprepad kontext, och `--max-num-batched-tokens`
för prefill på långa prompter. `recept/varianter/` har exempel.

## När något krånglar

Börja med `./diag.sh`, som ger en översikt på en skärm. `./diag.sh hjalp` listar
delkommandona och `FELSOK.md` går från symptom till kommando.

`sudo /usr/local/lib/llm/start.sh --visa`, `./diag.sh konf` och `./diag.sh allt`
ändrar ingenting: de bygger och visar kommandot utan att röra en körande container.
`systemctl is-active llm` säger att containern kör, inte att API:et är redo;
`./diag.sh` visar `/health`.

## Ändra inställningar

Motorns flaggor står i `/etc/llm/serve.args`, en per rad. Värdet skiljs från
flaggan med ett mellanslag (eller tabb) och behöver inga citattecken, inte ens JSON:

```
--max-model-len 65536
--speculative-config {"method":"mtp","num_speculative_tokens":3}
```

Efter en ändring: `sudo systemctl restart llm`, vänta på laddningen, kör `./rok.py`.

## Mätning

```bash
./bench.py                                   # tom kontext, en ström
./bench.py --djup 32000                      # kall cache, unikt prefix per anrop
./bench.py --djup 32000 --varm               # delat prefix, som en pågående dialog
./bench.py --djup 32000 --samtidiga 4        # fyra samtidiga strömmar
./bench.py --djup 32000 --kod ~/kod          # riktig kod som kontext i stället för utfyllnad
./bench.py --utan-tank ...                   # stänger av tänkande (Qwen)
```

Varje körning gör en uppvärmning som slängs och sedan fem varv med olika
uppgifter. Medianer skrivs ut och läggs till i `bench.csv` tillsammans med
modellrevision, bild-id och hash av `serve.args`. En ström utan slutlig `usage`,
utan `[DONE]` eller utan `finish_reason` räknas som fel, inte som en gissning.
`finish_length` visar hur många svar som stoppades av `max_tokens`: rätt för
hastighetsmätning, fel om svaret ska bedömas. Siffrorna i forumtrådarna är
andras mätningar på andra bilder; jämför bara egna körningar med varandra, och
upprepa nära en beslutsgräns. `--kod` visar vilka filer som skickas och frågar
först; dolda filer, symlänkar och filnamn som brukar innehålla hemligheter
hoppas över.

Beslutsregeln (drift, licens, hastighetsgolv, sedan kvalitet) kräver kundens
egna uppgifter med facit eller körbara tester. Finns de inte är dagens utfall
en preliminär teknisk rekommendation, inte ett kvalitetsval.

## Tänkande: på eller av

Qwen3-modellerna resonerar först (fältet `reasoning` i svaret, inte synligt för
användaren) och svarar sedan. Det är den inställning som mest styr hur maskinen
upplevs, och den syns inte om man inte vet om den.

| | Tänkande på | Tänkande av |
| --- | --- | --- |
| Svarstid på en enkel kodfråga | 5 till 20 s innan första synliga tecken, ibland minuter | under en sekund |
| Kvalitet på svåra uppgifter (buggjakt, flera filer, specifikationer) | bättre | sämre |
| Risk | modellen kan fastna i resonemang och fylla hela `max_tokens` utan att svara (`finish_reason: length`, tomt svar); sett på C med en trivial uppgift: 187 s, 80 000 tecken resonemang, inget svar | inga |
| Kostnad per anrop | 2 000 till 30 000 extra tokens | inga extra |

Tre sätt att styra det, i prioritetsordning:

1. **Per anrop**, i klienten: `"chat_template_kwargs": {"enable_thinking": false}`
   i anropskroppen. Det vinner alltid över serverns standard.
2. **Serverbrett**, i receptet: raden
   `--default-chat-template-kwargs {"enable_thinking":false}` i `serve.args` gör
   att alla anrop får tänkande av om de inte själva säger annat. Rekommenderas
   för en maskin som i huvudsak används av kodverktyg.
3. **Alltid på** är vLLM:s standard om inget av ovanstående finns.

Mätt 2026-10-08 på C med tre små Python-uppgifter: tänkande på gav 2 av 3
godkända på 235 s (den tredje fastnade i resonemang); tänkande av gav 3 av 3 på
5 s. Tumregel: tänkande av som standard, på för uppgifter där användaren är
beredd att vänta en minut på ett bättre svar. Sätt alltid `max_tokens` så att det finns plats
för resonemanget när tänkande är på (8 000 till 32 000), annars blir svaret tomt.
`rok.py --utan-tank`, `bench.py --utan-tank` och `eval.py --utan-tank` mäter med
tänkande av; kolumnen `tank` i resultatfilerna visar vilket som gällde.

## Kapacitet och fler användare

`./steg/14-kapacitet.sh` läser ur motorns startlogg hur mycket minne vikterna
tar, hur många tokens KV-cachen rymmer och hur många användare som därmed ryms
vid olika kontextstorlekar. `./steg/15-svep.sh` mäter 1, 2, 4 och 8 samtidiga
strömmar. Tumregler från dagens mätningar på B (Qwen3.8-27B-NVFP4, MTP):

- En ensam användare får cirka 29 tok/s med tom kontext och 24 tok/s vid 32k.
- Fyra samtidiga delar på cirka 17 tok/s totalt, 11 per användare; första token
  dröjer upp till en minut om alla skickar 32k kall kontext samtidigt.
- C (Qwen3.6-35B-A3B, MoE med 3B aktiva) på samma bild och recept: 110 tok/s
  ensam, 106 vid 32k med första token efter 6 s i stället för 18, och fyra
  samtidiga får 30 tok/s var (52 totalt) med första token efter 17 s. Tre till
  fyra gånger B:s genomströmning; kvaliteten är det kundens eval ska avgöra.
- Samtidighetssvep på C vid 8k kontext (`steg/15-svep.sh`):

  | användare | första token | tok/s per användare | tok/s totalt |
  | --- | --- | --- | --- |
  | 1 | 1,3 s | 118 | 86 |
  | 2 | 2,4 s | 87 | 109 |
  | 4 | 4,6 s | 58 | 140 |
  | 8 | 8,3 s | 48 | 142 |
  | 8 × 32k | 30 s | 23 | 53 |

  Totalen planar ut vid cirka 140 tok/s från fyra användare; vid 32k × 8 köar
  hälften eftersom receptet har `--max-num-seqs 4`. `recept/varianter/c-samtidig.args`
  höjer till 16 strömmar och 0.5 minne. C:s KV-cache kostar 12,7 kB per token
  (B: 38 kB), så C rymmer tre gånger fler användare på samma minne.
- Prefixcachen är det som räddar vardagen: samma kontext igen ger första token på
  två sekunder i stället för arton.
- Större prefill-batchar (`--max-num-batched-tokens` 32768) gjorde väntetiden
  längre vid fyra strömmar, inte kortare; 8192 behålls.
- Maskinen är bäst på en modell i taget. Två stora modeller samtidigt delar både
  KV-cache och minnesbandbredd och blir båda sämre än var och en ensam. Byt
  modell med `byt-modell.sh` i stället. En liten sidomodell (några GiB) bredvid
  huvudmodellen är det enda undantaget; stöd för det finns som `llm@.service`
  men är inte provat på en Spark.

## Offlineåterstart på befintlig värd (test 6 och 7, kundens prov)

Det här är ett prov av att tjänsten kommer upp utan nät och utan klonen, från
filerna som ligger kvar på maskinen. Det är inte en flytt till en ny maskin:
något exportpaket finns inte, så en ny Spark kräver att stegen i "Dagens ordning"
görs om med de sparade modell- och bildfilerna (`hamta.sh` ersätts av att kopiera
`/srv/models/<katalog>` med `.sha256` och `.kalla`).

Det som behövs finns kvar på maskinen när klonen är borta:

| Var | Vad |
| --- | --- |
| `/srv/models/<org>__<modell>` + `.sha256`, `.kalla` | Modellen, manifest, revision |
| `/srv/images/<bild>.tar.zst` + `.sha256`, `.kalla` | Containerbilden som fil, med tagg och id |
| `/usr/local/lib/llm/` | hela repot utom `.git`: alla skript, `steg/`, `recept/`, `eval/`, `docs/`, README och FELSOK (ägare root) |
| `/etc/llm/llm.env` (600, root), `/etc/llm/serve.args`, `/etc/llm/konfig.sha256` | Konfiguration, nyckel, frysta checksummor |
| `/etc/systemd/system/llm.service` | Autostart |

Provet görs av kunden, med nätet blockerat, utan klonen och utan konsultens hjälp.
Varje steg ska lyckas innan nästa:

```bash
cd /usr/local/lib/llm
./verifiera.sh                                   # 1. modeller, bildfiler, verktyg och konfiguration oförändrade
sudo systemctl stop llm && docker ps -a          # 2. tjänsten stoppad, ingen container llm kvar
docker image rm <tagg>                           # 3. bilden bort ur Docker; docker images ska inte visa id:t
zstd -dc /srv/images/<fil>.tar.zst | docker load # 4. läs in den sparade filen, taggen följer med
docker image inspect <tagg> --format '{{.Id}}'   # 5. ska vara LLM_IMAGE_ID i /etc/llm/llm.env
sudo systemctl start llm                         # 6. starta utan nät (test 6)
journalctl -fu llm                               # 7. vänta på "Application startup complete", Ctrl-C
./diag.sh && ./rok.py --hoppa 4                  # 8. /health 200, API:et svarar med nyckel
sudo reboot                                      # 9. omstart (test 7): tjänsten ska komma upp själv
cd /usr/local/lib/llm && ./diag.sh               # 10. efter omstart: /health 200
```

`start.sh` vägrar starta om bilden saknas lokalt eller har annat id än
`LLM_IMAGE_ID` (obligatoriskt), och hämtar aldrig bilder (`--pull=never`), så en
tyst "latest"-uppdatering kan inte smyga sig in. Modeller utan `.kalla` och
`.sha256` från `hamta.sh` startas inte. Nyckeln roteras genom att byta
`VLLM_API_KEY` i `llm.env` och starta om; diagnosfiler maskerar bara den nyckel
som gällde när de skrevs.

## Säkerhet och nät

- Program som systemd kör som root ligger i `/usr/local/lib/llm` (ägare root,
  inte skrivbar för labbkontot). `/srv/llm` är labbkontots arbetskatalog.
- API-nyckeln skapas av `install.sh` utan att passera något kommandos argument,
  ligger i `/etc/llm/llm.env` (600, root) och skickas till containern som
  miljövariabel. Klienterna (`diag.sh`, `rok.py`, `bench.py`) läser den från
  filen eller miljövariabeln `KEY`, aldrig från kommandoraden. Den syns i
  `docker inspect llm` för den som har Docker-rättigheter, vilket motsvarar root.
- `LLM_BIND=127.0.0.1` är standard: bara maskinen själv når API:et. Ska
  utvecklarnas maskiner nå det, sätt `LLM_BIND` till maskinens adress på labbnätet
  och låt nätansvarig begränsa porten i brandväggen. Bara `/v1/...` kräver nyckel;
  `/health`, `/version` och `/metrics` (motorns räknare, inga prompter) svarar
  utan. Trafiken går okrypterat över HTTP: nyckel och kod kan avlyssnas på
  nätvägen. Utanför ett isolerat labbnät behövs en SSH-tunnel eller en
  TLS-proxy framför porten; det ingår inte här.
- Containern kör som root i bilden med `--ipc=host` och NVIDIA:s ulimit-värden,
  samma som NVIDIA:s Spark-playbook. Bara den valda modellen monteras,
  skrivskyddad. Recept med `--trust-remote-code` (A, C, D, E) kör modellens egen
  Python-kod i containern; bilden och modellrevisionen är därför det man litar på,
  checksummorna visar bara att de inte ändrats.
- `./diag.sh allt` maskerar den aktuella nyckeln i filen den skriver (600), utan
  att nyckeln passerar något programs argument. Hugging Face-token, docker-gruppen
  och utgående 443 kontrolleras av `./stada.sh` i slutet av dagen; ett misslyckat
  curl-anrop betyder inte att egress är stängd, det bekräftar nätansvarig.

## Dag 2 och framåt: driften på egen hand

| Situation | Gör |
| --- | --- |
| Prova en ny modell | avsnittet "Prova en ny modell": `hamta.sh`, recept, `byt-modell.sh`, `bench.py`, `eval.py` |
| Ny vLLM-version | `./bild.sh <bild:tagg>`, sedan `./byt-modell.sh <katalog> <recept> <bild:tagg>`; `rok.py` avslöjar flaggor som bytt namn. Gamla bildfilen ligger kvar i `/srv/images` för rollback |
| Byta API-nyckel | `sudo nano /etc/llm/llm.env`, ny `VLLM_API_KEY=$(openssl rand -hex 32)`, `sudo systemctl restart llm`, `./verifiera.sh frys` (nyckeln ingår inte i frysningen, men `llm.env` i övrigt gör det) |
| Kärn- eller drivrutinsuppgradering | Kör `nvidia-smi` efteråt. Svarar den inte: `./steg/01-gpu.sh`, `02`, `03`. Första labbdagen stod maskinen utan GPU för att modulpaketet för den nya kärnan inte följt med; `apt-get install linux-modules-nvidia-<ver>-open-$(uname -r)` löste det. Installera inte över SSH-löst skrivbord: skärmen kan svartna tills omstart |
| Tjänsten startar inte efter boot | `./diag.sh`, `./diag.sh fel 300 \| head -60`. Tjänsten har `Restart=no`; `sudo systemctl start llm` när felet är rättat |
| Fler användare än det räcker till | `recept/varianter/b-samtidig.args` (fler strömmar, kortare kontext), `./steg/14-kapacitet.sh` visar hur många som ryms |
| Vad är ändrat sedan leveransen? | `./verifiera.sh`: FEL på konfiguration betyder att `serve.args`, `llm.env` (utan nyckel), verktygen eller `llm.service` ändrats sedan `frys` |
| Lämna över till en kollega | `./steg/13-overlamning.sh` samlar allt under `/srv/llm/overlamning-<datum>/` |

## Kända begränsningar

- Bara kandidat B är körd på en riktig Spark; A, D och E är utgångslägen. En ny
  vLLM-bild kan byta flaggnamn: kör `./rok.py` efter varje bildbyte.
- `--varm` antar att prefixcachen träffar efter uppvärmningen; räknarna i
  `./diag.sh matvarden` (`prefix_cache_hits`) visar om det stämmer.
- Kanariefågeln larmar vid klippning över ca 5 % och vid tappade kodord; den
  bevisar inte frånvaro av all trunkering. Kör den vid flera djup, särskilt
  strax över 16 384 om en unsloth-tokenizer används.
- Verktygstestet kontrollerar namn och argument i ett anrop, inte en full tur
  med verktygsresultat. Ska kunden köra ett agentflöde behövs det provet också.
- Hastighetsmåttet per ström är ett klientestimat; jämför kandidater på
  `tok_s_totalt` och på kompletta anrop.
- `llm.env` tolkas av bash (`start.sh`) och av en enkel Python-tolk
  (`_klient.py`); håll dig till formatet i mallen.

## Filer

| Fil | Hamnar i | Innehåll |
| --- | --- | --- |
| `kolla.sh` | | Förkontroll utan ändringar |
| `start.sh` | `/usr/local/lib/llm/start.sh` | Bygger och kör `docker run` från `llm.env` och `serve.args`, kontrollerar bildens id |
| `llm.service` | `/etc/systemd/system/` | Autostart med startgräns |
| `llm.env.mall` | `/etc/llm/llm.env` | Bild, bild-id, modellkatalog, adress, port, API-nyckel |
| `verifiera.sh` | `/usr/local/lib/llm/` | Checksummor för modeller, bilder och fryst konfiguration |
| `recept/*.args` | `/etc/llm/serve.args` | Utgångslägen per kandidat, källa i filhuvudet, otestade av oss |
| `diag.sh` | | Diagnostik: översikt, logg, fel, minne, GPU, nät, API, mätvärden |
| `FELSOK.md` | | Symptom, kommando och vad man letar efter |
| `_klient.py` | | Delad kod för `rok.py` och `bench.py`, bara standardbiblioteket |
