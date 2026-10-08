# steg/: dagens skript, ett per moment

Skripten här är det som kördes under den första labbdagen, i nummerordning.
De är tunna skal runt verktygen i repots rot (`hamta.sh`, `bild.sh`, `install.sh`,
`bench.py`, ...) så att varje moment är ett kommando. Alla som ändrar maskinen
visar sin plan och frågar `[j/N]` först; `JA=1` hoppar över frågan för obevakad
körning. Alla andra är rena läsningar.

| Skript | Ändrar maskinen? | Vad det gör | Förutsätter | Efteråt |
| --- | --- | --- | --- | --- |
| `01-gpu.sh` | nej | Diagnos när `nvidia-smi` inte svarar: PATH, `/dev/nvidia*`, laddade moduler, drivrutinspaket, `dmesg` | inget | `02` om modulen saknas |
| `02-drivrutin.sh` | nej | Finns nvidia-modulen för den körande kärnan? DKMS, installerade kärnor, `modprobe -n` | inget | `03` |
| `03-modulpaket.sh` | nej | Vilket modulpaket passar kärnan, simulerad `apt-get install`, GRUB-poster | inget | installera paketet för hand (se FELSOK, "GPU:n syns inte") |
| `04-forutsattningar.sh` | **ja** (apt, docker-gruppen, pipx) | Installerar `pipx tmux zstd`, lägger kontot i `docker`, installerar `hf` | sudo | logga ut och in, `./kolla.sh` |
| `05-hamta-b-c.sh` | skriver under `/srv/models` | Hämtar kandidat B och C med låsta revisioner | `kolla.sh` utan FEL, `lage.sh fore` | kör i `tmux` |
| `06-bild-b.sh` | skriver under `/srv/images` | Hämtar och sparar containerbilden för B | docker | `07` |
| `07-installera-b.sh` | **ja** (install.sh, `/etc/llm`) | Installerar tjänsten med B-receptet och fyller i `llm.env` från `bild.sh`:s och `hamta.sh`:s utdata | `05`, `06` | `sudo systemctl enable --now llm` |
| `08-modeller-pa-disk.sh` | nej | Inventerar modeller, cachar och viktfiler som redan finns på maskinen | sudo (för `find`) | undvik dubbla nedladdningar |
| `09-bench.sh <etikett>` | skriver `/srv/llm/bench.csv` | Mätserie: tom, 32k kall, 32k varm, 32k × 4 strömmar; sammanfattning sist | tjänsten svarar | jämför rader i `bench.csv` |
| `10-variant.sh <variant>` | **ja** (`serve.args`, omstart) | Byter till ett recept i `recept/varianter/` (eller en fil), startar om, väntar på `/health`, röktest 1–3 och 5 | tjänsten installerad | `09` med ny etikett |
| `11-batch.sh` | **ja** (flera omstarter, modellbyte) | Obevakad serie: varianter, eval, byte till C och tillbaka till B; logg i `/srv/llm/batch-*.log` | B och C hämtade | läs summeringen sist i loggen |
| `12-offline.sh` | **ja** (bild ur och in i Docker, omstart) | Kundens prov: stoppa, ta bort bilden, läs in filen, kontrollera id, starta utan nät, röktest | `verifiera.sh frys` gjord | `sudo reboot` för test 7 |
| `13-overlamning.sh` | skriver `/srv/llm/overlamning-*/` | Samlar diag, mätningar, loggar, inspelningar (nyckel maskad) och konfiguration (utan nyckel) | inget | granska mappen innan den lämnar maskinen |
| `14-kapacitet.sh` | nej | Ur motorns startlogg: vikter, KV-cache i tokens, användare per kontextstorlek, flera modeller | tjänsten startad | siffror till rapporten |
| `15-svep.sh <etikett>` | skriver `bench.csv` | 1, 2, 4, 8 samtidiga strömmar vid 8k, plus 8 × 32k | helst en variant med `--max-num-seqs 8` | tabell sist |
| `16-instans.sh` | **ja** (`llm@<namn>`) | Andra motor på egen port och minnesandel. **Oprövat på en Spark**; grundregeln är en modell i taget | `llm@.service` | `bench.py --url` mot den nya porten |
| `17-hamta-d-e.sh` | skriver under `/srv/models` | Hämtar beslutsmodellerna D och E | som `05` | recept i `recept/clef*.args` |
| `18-resultat.sh` | nej | Hela mättabellen och alla eval-rader som inte blev godkända, på en skärm | inget | beslutsunderlag |
| `19-hamta-f.sh` | skriver under `/srv/models`, `/srv/images` | Hämtar embeddingmodellen F, reserven och den nattliga vLLM-bilden | som `05` | `16-instans.sh embed ...` |
| `20-embed-test.sh [port]` | nej | Röktest för embeddingmodellen: dimension och att en kodfråga hamnar närmast rätt dokument | `llm@embed` kör | |
| `21-demo.sh` | **ja** (`~/.local/bin/opencode`, `~/.config/opencode`, `~/demo`) | Förbereder demon: OpenCode mot Sparkens API, uppgift i `~/demo/UPPGIFT.md` | tjänsten svarar | `cd ~/demo && opencode` |

Numreringen är historisk, inte en tvingande ordning: `01`–`03` behövs bara om
GPU:n inte svarar, `16` bara för en sidomodell. Ett nytt moment får nästa nummer.
