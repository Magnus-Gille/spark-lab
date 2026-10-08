# recept/: vLLM-flaggor per kandidat

En fil per kandidat, en flagga per rad, kopieras till `/etc/llm/serve.args` av
`install.sh` eller `byt-modell.sh`. `varianter/` har provade avvikelser från
baslinjen för B. Varje fil anger sin källa i huvudet. Siffror som nämns här är
från mätningar på en DGX Spark 2026-10-08 med `vllm/vllm-openai:qwen38`.

## Flaggorna, och varför de står där

| Flagga | Betydelse | Att veta |
| --- | --- | --- |
| `--tensor-parallel-size 1` | En GPU | Sparken har en |
| `--kv-cache-dtype fp8` | KV-cachen i 8 bitar | Dubblar antalet tokens som ryms; NVIDIA:s Spark-recept |
| `--gpu-memory-utilization 0.7` | Andel av det delade minnet som vLLM får ta (vikter + KV-cache) | 0.7 = ca 85 GiB på 121. Högre ger mer KV-cache men mindre till OS och andra program; OOM vid start = sänk |
| `--max-model-len 262144` | Största kontext per anrop | Modellens maximum. Sänk till kundens behov så räcker KV-cachen till fler användare |
| `--max-num-seqs 4` | Största antal samtidiga anrop | Fler köas. 8 i `b-samtidig` |
| `--max-num-batched-tokens 8192` | Hur många tokens prefill tar per steg | 32768 gav längre väntan vid fyra strömmar (en jättebatch blockerar de andra); 8192 behålls |
| `--enable-chunked-prefill` | Dela upp långa prompter så att pågående svar inte stannar | På |
| `--async-scheduling` | Schemalägg nästa steg medan GPU:n räknar | Några procent snabbare |
| `--enable-prefix-caching` | Återanvänd KV-cache för redan sedd början av prompten | Största vinsten i vardagen: första token på 2 s i stället för 18 vid 32k |
| `--load-format fastsafetensors` | Snabbare laddning av vikter | 9 s för 20 GiB |
| `--reasoning-parser qwen3` | Skilj modellens tänkande från svaret (fältet `reasoning`) | Utan den hamnar tankarna i svaret |
| `--tool-call-parser qwen3_xml` + `--enable-auto-tool-choice` | Verktygsanrop som strukturerade `tool_calls` | Röktest 5 kontrollerar |
| `--speculative-config {"method":"mtp","num_speculative_tokens":3}` | Spekulativ avkodning med modellens eget MTP-huvud | 29 tok/s mot 13 utan vid en ström; 10,7 mot 7,1 per ström vid fyra. Kostar lite KV-minne |
| `--trust-remote-code` | Kör modellens egen Python-kod | Krävs av C (Qwen3.6), A och Clef. Bilden och revisionen är då det man litar på |
| `--attention-backend flashinfer`, `--moe-backend marlin` | Kärnval för C | Från NVIDIA:s modellkort för Spark |
| `"moe_backend":"triton"` i C:s speculative-config | Kärna för MTP-huvudets expertlager | Från modellkortet |
| `--moe-backend b12x`, `--linear-backend b12x`, `-cc.mode none`, `-cc.cudagraph_mode ...`, `--engram-config.cpu_offload` | A:s flaggor | Finns bara i forumtrådens specialbyggda bild, inte i standardbilder |

JSON-värden skrivs utan citattecken runt hela värdet: `start.sh` delar raden vid
första blanktecknet och skickar resten ordagrant.

## Filerna

| Fil | Kandidat | Källa |
| --- | --- | --- |
| `qwen38-27b.args` | B, baslinje | NVIDIA:s Spark-playbook plus MTP efter mätning |
| `qwen36-35b-a3b.args` | C | modellkortets Spark-recept |
| `qwen38-flash-next.args` | A | forumrecept, kräver specialbild |
| `clef-flash.args`, `clef.args` | D, E | utgångsläge, otestat |
| `varianter/b-prefill.args` | B med 32768 batched tokens | förkastad, kvar som bevis |
| `varianter/b-samtidig.args` | B med 0.8, 131k, 8 strömmar | för fler användare |
