# Använda API:et från andra datorer

Motorn svarar på ett OpenAI-kompatibelt API. Allt som kan prata med OpenAI
(SDK:er, VS Code-tillägg, OpenCode, Aider, Continue, LangChain, curl) fungerar
mot Sparken genom att byta bas-URL, nyckel och modellnamn.

## 1. Öppna porten på labbnätet (görs på Sparken, en gång)

Som levererat lyssnar API:et bara på maskinen själv (`LLM_BIND=127.0.0.1`).
För att andra datorer ska nå det:

```bash
sudo nano /etc/llm/llm.env          # LLM_BIND=0.0.0.0  (eller Sparkens egen adress på nätet)
sudo systemctl restart llm
./verifiera.sh frys                 # llm.env utan nyckel ingår i frysningen
```

Be nätansvarig begränsa porten (standard 8000) i brandväggen till de datorer
som ska ha åtkomst. Trafiken går okrypterat över HTTP: på ett isolerat kontorsnät
är det ett medvetet val, över andra nät behövs en TLS-proxy eller SSH-tunnel
framför porten (se "Säkerhet och nät" i README).

Sparkens adress: `hostname -I` på Sparken, eller `spark-<xxxx>.local` via mDNS
om nätet tillåter det. Nedan används `<spark>` som platshållare.

## 2. Nyckeln

Nyckeln står i `/etc/llm/llm.env` på Sparken (`VLLM_API_KEY=...`, bara root
kan läsa filen). Dela den via kundens lösenordshanterare, inte via chatt eller
e-post. Byt nyckel: ny `VLLM_API_KEY=$(openssl rand -hex 32)` i filen,
`sudo systemctl restart llm`, och dela den nya.

Alla anrop under `/v1/` kräver `Authorization: Bearer <nyckel>`. `/health`,
`/version` och `/metrics` svarar utan nyckel.

## 3. Snabbtest från en annan dator

```bash
curl -s http://<spark>:8000/health            # 200 utan kropp = motorn är redo
curl -s http://<spark>:8000/v1/models -H "Authorization: Bearer <nyckel>"
```

Modellen heter alltid `kod`, oavsett vilken kandidat som kör. Det gör att
klienternas konfiguration inte behöver ändras vid modellbyte.

```bash
curl -s http://<spark>:8000/v1/chat/completions \
  -H "Authorization: Bearer <nyckel>" -H "Content-Type: application/json" \
  -d '{"model":"kod","messages":[{"role":"user","content":"Skriv en C#-funktion som vänder en sträng."}],"max_tokens":2000}'
```

## 4. Inställningar som spelar roll

| Inställning | Värde | Varför |
| --- | --- | --- |
| Bas-URL | `http://<spark>:8000/v1` | de flesta klienter vill ha `/v1` med |
| Modell | `kod` | fast namn, se ovan |
| `max_tokens` | 8 000 till 32 000 för kodarbete | Qwen3 tänker först (fältet `reasoning`) och svarar sedan; ett lågt tak ger tomt svar med `finish_reason: length` |
| Tänkande av | `"chat_template_kwargs": {"enable_thinking": false}` i anropet | se avsnittet "Tänkande: på eller av" i README. Kort: av ger svar på under en sekund, på ger bättre svar på svåra uppgifter men kan ta minuter och kan fastna. Kontrollera med Sparkens ansvarige vad servern har som standard |
| Kontext | upp till 262 144 tokens per anrop | mer kontext per användare = färre samtidiga användare, se "Kapacitet" i README |
| `temperature` | 0 till 0,7 | 0 för reproducerbara svar (med spekulativ avkodning varierar texten ändå något) |
| Streaming | `"stream": true` | rekommenderas; första token kommer efter sekunder, hela svaret efter tiotals sekunder |
| Verktyg | OpenAI `tools`-format | motorn returnerar `tool_calls`; röktest 5 kontrollerar det |

## 5. Exempel per klient

**Python (OpenAI SDK):**

```python
from openai import OpenAI
klient = OpenAI(base_url="http://<spark>:8000/v1", api_key="<nyckel>")
svar = klient.chat.completions.create(
    model="kod", max_tokens=8000,
    messages=[{"role": "user", "content": "Förklara skillnaden mellan Span<T> och Memory<T> i C#."}],
)
print(svar.choices[0].message.content)
```

**C# (OpenAI-paketet från NuGet):**

```csharp
var klient = new OpenAI.Chat.ChatClient("kod",
    new System.ClientModel.ApiKeyCredential("<nyckel>"),
    new OpenAI.OpenAIClientOptions { Endpoint = new Uri("http://<spark>:8000/v1") });
var svar = klient.CompleteChat("Skriv en xUnit-test för en stack.");
Console.WriteLine(svar.Value.Content[0].Text);
```

**OpenCode** (`~/.config/opencode/opencode.json`):

```json
{ "provider": { "spark": { "npm": "@ai-sdk/openai-compatible", "name": "Spark",
    "options": { "baseURL": "http://<spark>:8000/v1", "apiKey": "<nyckel>" },
    "models": { "kod": { "name": "kod (Spark)" } } } } }
```

**Continue / Cline / liknande VS Code-tillägg:** leverantör "OpenAI-kompatibel",
bas-URL `http://<spark>:8000/v1`, modell `kod`, nyckel enligt ovan.

**Aider:** `aider --openai-api-base http://<spark>:8000/v1 --openai-api-key <nyckel> --model openai/kod`.

## 6. Embeddings (om sidomodellen `llm@embed` körs)

Port 8002, samma nyckel, modellnamn `embed`, endpoint `/v1/embeddings`.
Prefix sätts av klienten: `task: code retrieval | query: ...` för frågor,
`title: none | text: ...` för dokument. 768 dimensioner (kan trunkeras till 512,
256 eller 128 och normaliseras om). `./steg/20-embed-test.sh` visar ett anrop.

## 7. När det inte fungerar

| Symptom | Orsak |
| --- | --- |
| Ingen kontakt alls | `LLM_BIND` fortfarande 127.0.0.1, brandvägg, eller tjänsten nere (`./diag.sh` på Sparken) |
| HTTP 401 | fel nyckel, eller `Bearer ` saknas i headern |
| HTTP 404 på `/v1/models` | bas-URL utan `/v1`, eller med dubbelt `/v1/v1` |
| HTTP 400 om "maximum context length" | prompt + `max_tokens` över 262 144 |
| Tomt svar, `finish_reason: length` | höj `max_tokens` eller stäng av tänkande |
| Svar efter en minut först | kö: fler samtidiga än `--max-num-seqs`, eller alla skickar stora kalla kontexter samtidigt. Se "Kapacitet" i README |
| Modellen heter något annat än `kod` | `LLM_NAME` ändrat i `llm.env`; `/v1/models` visar namnet |
