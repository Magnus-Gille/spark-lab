# Kolumnerna i bench.csv och eval.csv

Båda filerna ligger i `/srv/llm/` och får en rad per körning (bench) eller per
uppgift (eval). Samma spårbarhetskolumner finns i båda, så att en rad alltid
går att knyta till exakt modell, bild och flaggor.

## Spårbarhet (båda filerna)

| Kolumn | Betydelse |
| --- | --- |
| `tid` | när raden skrevs |
| `etikett` | fri text från `--etikett`; konventionen är `<kandidat>-<variant>-<mätpunkt>`, t.ex. `B-mtp-32k-x4` |
| `url` | vilken motor som mättes |
| `modell` | namnet motorn svarar med (`kod` för alla kandidater) |
| `modellkatalog` | katalogen under `/srv/models`, t.ex. `nvidia__Qwen3.8-27B-NVFP4` |
| `revision` | modellens commit (12 tecken) från `.kalla` |
| `bild_id` | containerbildens id enligt `llm.env` |
| `korande_bild` | id på bilden i den container som faktiskt kör; skiljer sig från `bild_id` om konfigurationen ändrats utan omstart |
| `args_hash` | sha256 (12 tecken) av `/etc/llm/serve.args`; samma hash = samma flaggor |
| `tank` | `ja`/`nej`: tänkande på eller av (`--utan-tank`) |
| `max_tokens` | svarstak per anrop |

## bench.csv

| Kolumn | Betydelse |
| --- | --- |
| `djup` | begärd kontext i tokens före uppgiften |
| `in_tokens` | median av faktiska prompt-tokens enligt motorn |
| `samtidiga` | antal strömmar som skickades samtidigt |
| `cache` | `kall` = unikt prefix per anrop, `varm` = delat prefix (prefixcachen träffar) |
| `ttft_s` | median tid till första delta (resonemang eller text), sekunder |
| `ttft_max_s` | sämsta anropet |
| `ttft_text_s` | median tid till första synliga text (efter tänkandet); tom om inget svar hann börja inom `max_tokens` |
| `tok_s_per_strom` | median (completion_tokens − 1) / tid från första till sista delta. Klientestimat; se README |
| `tok_s_totalt` | summan av completion_tokens i ett varv / varvets väggtid, median över varv. Huvudmåttet |
| `ut_tokens` | median completion_tokens |
| `finish_length` | antal svar som stoppades av `max_tokens` (väntat vid hastighetsmätning) |
| `lyckade`, `fel` | antal strömmar som gav komplett svar respektive misslyckades; en rad med `fel` > 0 är inte ett rent mätvärde |

## eval.csv

| Kolumn | Betydelse |
| --- | --- |
| `uppgiftsfil`, `id` | vilken uppgift; raden `SUMMA` sammanfattar körningen |
| `status` | `pass`, `fail`, `timeout` (testet), `manuell` (uppgift utan test), `fel` (anropet eller filen misslyckades) |
| `tid_modell_s`, `tid_test_s` | tid för modellsvaret respektive testet |
| `in_tokens`, `ut_tokens`, `tankande_tecken`, `finish` | storlek på prompt, svar och resonemang, och varför svaret slutade |
| `detalj` | sista raden ur testets utskrift vid fail/timeout, eller felorsak |
| `samtidiga`, `sandbox` | hur körningen gjordes |

`SUMMA`-radens `status` är pass-andelen av de testade (pass + fail + timeout);
`fel` räknas inte in, men står i `detalj`. Svar och testloggar per uppgift
ligger i `svar/<etikett>/<id>/`.
