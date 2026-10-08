# Felsökning

Börja alltid med `./diag.sh`. Tabellerna går från symptom till nästa kommando
och vad du letar efter i utskriften.

## Innan repot är klonat

De här går att skriva för hand om nätet eller `git clone` inte fungerar.

| Fråga | Kommando | Tolka |
| --- | --- | --- |
| Fungerar namnuppslag? | `getent hosts github.com` | Tom utskrift: DNS-servern saknas eller nås inte |
| Vilken DNS används? | `resolvectl dns` | Ska visa kundens anvisade server |
| Når jag GitHub? | `curl -sI -m 8 https://github.com \| head -n1` | `HTTP/2 200` är bra. Inget svar: brandvägg eller proxy |
| Krävs proxy? | `env \| grep -i proxy \| sed 's#//[^@]*@#//<anv:losen>@#'` | Finns en proxy måste även Docker och git få den. Visa aldrig inloggningen i proxyadressen |
| Går klockan rätt? | `timedatectl` | Fel klocka ger certifikatfel som ser ut som nätfel |
| Certifikatfel? | `curl -sv -m 8 https://github.com 2>&1 \| grep -iE 'issuer\|verify'` | En okänd utfärdare tyder på TLS-inspektion hos kunden |

## Nät och nedladdning

| Symptom | Kommando | Leta efter |
| --- | --- | --- |
| Nedladdning från Hugging Face fastnar eller ger 403 | `./diag.sh nat` | Värden efter pilen (`->`) är omdirigeringen. Den ska också vara öppen i brandväggen |
| `docker pull` misslyckas | `./diag.sh nat` | `401` från registret betyder nåbart. `000` betyder inget svar: brandvägg, proxy, DNS eller tillfälligt fel; vilket avgörs med `./kolla.sh` (curl-kod) och nätansvarig |
| `docker pull` ger "no matching manifest" | `docker manifest inspect <bild> \| grep architecture` | Oftast saknar bilden `arm64`; kan också vara fel tagg eller ett register som kräver inloggning |
| Nedladdningen är långsam | `./diag.sh disk` och hämtningens egen hastighetsrad | Räkna om tidsplanen: 124 GiB tar ca 3 h på 100 Mbit/s |
| Disken tar slut | `./diag.sh disk` | Bortvalda modeller under `/srv/models`, `docker system df` |

## Start

| Symptom | Kommando | Leta efter |
| --- | --- | --- |
| `[ERROR] min_frames is part of Qwen3VLVideoProcessorInitKwargs, but not documented` | ingen | Ofarligt: ett dokumentationsfel i modellens bildprocessor (C har en VL-del) som loggas som ERROR. Tjänsten startar ändå; vänta på "Application startup complete" |
| Tjänsten dör direkt efter start | `./diag.sh fel 300 \| head -n 60` | Första tracebacken, inte den sista. `Restart=no` som levererat: starta om för hand med `sudo systemctl start llm` när felet är rättat |
| "Killed" eller slut på minne vid start | `./diag.sh minne`, sedan `./diag.sh cache` | Hög `buff/cache`. Hjälper det inte: sänk `--gpu-memory-utilization` |
| Okänd flagga (`unrecognized arguments`) | `./diag.sh konf` | Flaggan finns inte i den här bildens vLLM-version. Jämför med receptets bild |
| `KV cache` räcker inte för `max_model_len` | `./diag.sh logg` | Raden om KV-cache. Sänk `--max-model-len` eller höj minnesandelen |
| `OutOfResources: shared memory, Required ... Hardware limit 101376` | `./steg/23-embed-fel.sh` | En Triton-kärna vill ha mer delat minne än GB10:s 99 kB per block. Byt attention-kärna i receptet: `flashinfer` för vanliga modeller, `flash_attn` för embeddingmodeller (FlashInfer stöder inte encoder-only) |
| Krasch med NVFP4 eller `no kernel image` | `./diag.sh logg` | Bilden saknar stöd för GB10. Byt till en bild från NVIDIA:s Spark-playbook (`vllm/vllm-openai:qwen38`) eller en bild byggd för Sparken |
| `har id ... men llm.env kräver ...` | `./diag.sh konf` | Fel bild bakom taggen. Läs in den sparade filen igen eller uppdatera `LLM_IMAGE_ID` medvetet |
| GPU:n syns inte i containern | `./diag.sh gputest` | Ska visa samma GPU som på värden. Annars saknas NVIDIA-runtime i Docker |
| Motorn försöker nå internet | `./diag.sh fel` | Värdnamn i felet. Modellen ska anges som lokal sökväg, `HF_HUB_OFFLINE=1` sätts av `start.sh` |
| Starten tar mycket lång tid | `./diag.sh logg`, `./diag.sh folj` | Går `LEDIGT` nedåt laddas vikterna fortfarande. Stora modeller tar 8–13 min |
| Porten upptagen | `sudo ss -tlnp \| grep <port>` | En gammal egen container tas bort av `start.sh`; en främmande container med namnet `llm` stoppar starten och tas bort för hand efter kontroll |
| `Bilden ... finns inte lokalt` eller `--pull=never` | `docker images` | Bilden hämtas aldrig vid start. Läs in den sparade filen: README, "Offlineåterstart på befintlig värd" |

## Svar och kvalitet

| Symptom | Kommando | Leta efter |
| --- | --- | --- |
| Modellen ignorerar början av långa prompter | `./diag.sh tokenizer`, `./rok.py --kontext <n>` | `truncation` ska vara `None`. `prompt_tokens` ska ligga nära det väntade. Känt i unsloth-repon (27B tidigare, 35B-A3B fortfarande) |
| Verktygsanrop kommer som text | `./diag.sh konf`, `./rok.py --hoppa 4` | `--tool-call-parser` och `--enable-auto-tool-choice` i `serve.args` |
| Tomt svar, `finish_reason: length` | `./diag.sh api` | Tänkandet åt upp `max_tokens`. Höj gränsen eller prova `--utan-tank`. Resonemanget ligger i fältet `reasoning` (`reasoning_content` i äldre vLLM; skripten läser båda) |
| Tankarna hamnar i själva svaret | `./diag.sh konf` | `--reasoning-parser` saknas eller är fel för modellen |
| HTTP 400 om kontextlängd | `./diag.sh logg` | `max_model_len` i loggen jämfört med klientens inställning |
| HTTP 401 | `./diag.sh api` | Klienten skickar fel nyckel. Rätt nyckel står i `/etc/llm/llm.env`. Bara `/v1/...` kräver nyckel; `/health`, `/version` och `/metrics` svarar alla |
| Svaren skiljer sig mellan körningar vid temperatur 0 | | Väntat med spekulativ avkodning. Jämför kvalitet, inte exakt text |

## Hastighet

| Symptom | Kommando | Leta efter |
| --- | --- | --- |
| Ungefär halverad tok/s | `./diag.sh matvarden` | Räknare för spekulativ avkodning (`accepted`/`draft`) som växer. Saknas de helt är MTP troligen inte aktivt; bekräfta med `./diag.sh konf` |
| Lång tid till första token | `./diag.sh matvarden` | `num_requests_waiting` över 0 betyder kö. Annars prefill: jämför `--varm` och kall mätning |
| Långsammare efter en stund | `./diag.sh gpu` | Temperatur och effekt. Sjunkande effekt vid full last kan vara värmestrypning; bekräfta med `dmesg` (`./diag.sh fel`) eller `nvidia-smi -q -d PERFORMANCE` |
| Mycket långsamt, disken arbetar | `./diag.sh minne` | Kontrollera använd swap: är den stor är minnesandelen (`--gpu-memory-utilization`) för hög |
| Samtidiga anrop är långsamma | `./diag.sh folj` under `./bench.py --samtidiga N` | `KV%` (`vllm:kv_cache_usage_perc`) nära 100 eller `KOAR` över 0: sänk kontexten eller antalet sekvenser |
| Krasch under samtidig last | `./diag.sh fel` | Prova lägre `num_speculative_tokens` eller stäng av spekulativ avkodning |

## Spara underlag

`./diag.sh allt` skriver allt till en fil under `/srv/llm`. API-nyckeln byts ut mot
`<nyckel dold>` överallt i filen, även i loggrader. Granska ändå filen innan den
lämnar maskinen.
Kör det när ett fel är färskt, och en gång till när konfigurationen är fryst.
