# Eval: kundens egna uppgifter avgör modellvalet

`../eval.py` kör uppgifter ur en JSONL-fil mot motorn, skriver modellens kod
till en fil, kör ett test och räknar andelen godkända. Varje rad i
`/srv/llm/eval.csv` bär modellrevision, bild-id och hash av `serve.args`, så att
samma uppgiftsfil körd mot två kandidater eller två recept går att jämföra.

```bash
./eval.py eval/exempel.jsonl --etikett B                # prova flödet (tre små Python-uppgifter)
./eval.py eval/kund.jsonl --etikett B --samtidiga 4     # egna uppgifter (filen skriver ni själva), fyra parallellt
./eval.py eval/kund.jsonl --etikett B-utan-tank --utan-tank
./eval.py eval/kund.jsonl --etikett B --sandbox <bild>  # testerna i Docker utan nät
```

## Så skrivs en uppgift

En JSON-rad per uppgift. Kommentarsrader börjar med `#`.

| Fält | Betydelse |
| --- | --- |
| `id` | kort unikt namn; blir katalognamn under `svar/<etikett>/` |
| `prompt` | instruktionen, som en utvecklare skulle skriva den |
| `katalog` | (valfri) katalog som kopieras till arbetskatalogen, relativt uppgiftsfilen |
| `filer` | (valfri) filer i katalogen som bifogas i prompten som kontext |
| `svarsfil` | filen som modellens svar skrivs till; första kodblocket i svaret |
| `test` | (valfri) kommando i arbetskatalogen; exitkod 0 = godkänt. Saknas: `manuell` |
| `timeout` | (valfri) sekunder för testet, standard 120 |
| `system` | (valfri) systemprompt |

Modellen ombeds svara med hela filen, inte en diff. Håll därför `svarsfil` till en
fil på några hundra rader; peka ut rätt fil i `katalog` och ge resten som `filer`.

## Från ett riktigt repo till uppgifter

Utgå från repots egen testkörning. Exempel på en C++-uppgift där katalogen är
en kopia av ett repo och testet är repots eget byggskript (namnen är påhittade):

```
{"id": "polygon-area-spec", "prompt": "docs/spec.md beskriver hur arean av en polygon ska beraknas. Implementationen i src/geometry/area.cpp avviker fran specifikationen i ett fall. Hitta avvikelsen och ratta den med minsta mojliga andring. Behall alla funktionssignaturer.", "katalog": "repo", "filer": ["docs/spec.md", "src/geometry/area.h", "src/geometry/area.cpp"], "svarsfil": "src/geometry/area.cpp", "test": "cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null && cmake --build build --parallel >/dev/null && ctest --test-dir build --output-on-failure", "timeout": 600}
```

Motsvarande för C#: `"svarsfil": "src/Geometry/Area.cs"` och
`"test": "dotnet test tests/Geometry.Tests/Geometry.Tests.csproj --nologo"`.

Bra uppgifter kommer från tre källor: buggar som redan är rättade i historiken
(ta commiten före rättningen som `katalog`, rättningens test som `test`),
små funktioner med befintliga enhetstester, och kodgranskning där facit är en
seniors blinda bedömning av `svar/<etikett>/<id>/svar.md` (uppgift utan `test`).
Tio uppgifter räcker för att skilja kandidater åt; trettio för att skilja recept.

## Sandbox och tid

Utan `--sandbox` körs testerna som labbkontot på Sparken, med modellens kod.
Använd uppgifter du litar på, eller ge en Docker-bild med kompilator och
testverktyg (`--sandbox`), då körs testet med `--network none` och
arbetskatalogen monterad på `/w`. Bilden måste finnas lokalt (`docker pull` i
förväg, `./bild.sh` sparar den för drift utan nät).

Tidsbudget på en Spark med B: cirka 24 tok/s per ström ger en kort uppgift på
20 till 30 sekunder; med tänkande på går 5 000 till 15 000 tokens åt till
resonemang innan svaret kommer, så `--max-tokens` (standard 24 000) måste ha
marginal, annars blir uppgiften `fel` med "tomt svar". Fyra strömmar ger
ungefär 100 korta uppgifter i timmen på B och flera hundra på C; C++-byggen i
testet kommer utöver det. Kör stora uppgiftsfiler på natten med `--samtidiga 4`.

## Jämföra

```bash
grep -E 'SUMMA' /srv/llm/eval.csv | cut -d, -f1-6,12
```

ger en rad per körning med etikett, pass-andel och fördelning. Jämför alltid
samma uppgiftsfil, och kör nära beslutsgränsen två gånger.
