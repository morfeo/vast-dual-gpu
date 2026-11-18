# vast-dual-gpu

ComfyUI su una GPU e Ollama sull'altra, su un'istanza vast.ai con 2 GPU.
Modelli, LoRA e GGUF arrivano dal tuo bucket (S3, R2, B2, Wasabi, MinIO),
da link firmati o da Hugging Face e CivitAI.

| Servizio | GPU | Porta | Dati |
|---|---|---|---|
| ComfyUI | `COMFY_GPU` (0) | 8188 (portale) | `/workspace/ComfyUI` |
| Ollama  | `OLLAMA_GPU` (1) | 11434 | `/workspace/ollama-models`, GGUF in `/workspace/gguf` |

## 1. Template vast.ai

Parti dal template ufficiale **PyTorch (Vast)** e fanne una copia tua
(Templates → icona matita → salva in "My Templates"). L'immagine ha già CUDA,
PyTorch in `/venv/main`, supervisor e l'Instance Portal: lo script usa tutto questo.
Non usare il template ComfyUI di vast: ha già il suo ComfyUI.

**Non toccare l'on-start script** del template: avvia i servizi di vast.
Il nostro setup parte da `PROVISIONING_SCRIPT`, che vast esegue al primo avvio.

**Docker options**: aggiungi `-p 8188:8188` (per ComfyUI nel portale).

**Variabili d'ambiente**:

| Variabile | Valore |
|---|---|
| `PROVISIONING_SCRIPT` | repo pubblico: `https://raw.githubusercontent.com/morfeo/vast-dual-gpu/main/provision.sh`<br>repo privato: URL "Raw" di un Gist secret con dentro `provision.sh` |
| `PORTAL_CONFIG` | quella del template **più** `\|localhost:8188:18188:/:ComfyUI` in fondo |
| `GH_TOKEN` | solo se il repo è privato: token GitHub fine-grained, sola lettura, solo questo repo |
| `HF_TOKEN` | facoltativo: modelli Hugging Face ad accesso limitato (Flux dev, ...) |
| `CIVITAI_TOKEN` | facoltativo: download da CivitAI |

**Disco**: abbondante. Checkpoint, modelli video e LLM occupano decine di GB ciascuno.

### ComfyUI nel portale

Con la voce `ComfyUI` in `PORTAL_CONFIG`, setup.sh fa ascoltare ComfyUI sulla porta
interna (18188, solo locale) e il portale di vast la pubblica sulla 8188 con password.
Dalla scheda dell'istanza premi **Open** e poi **ComfyUI**: niente tunnel SSH.
Ollama resta solo interno (ComfyUI lo raggiunge su `127.0.0.1:11434`).

### Primo avvio e riavvii

- Al primo avvio `provision.sh` clona il repo in `/workspace/vast-dual-gpu` e lancia
  `setup.sh`. Log: `/workspace/logs-setup.txt` (anche nel portale, sezione log).
- Se fermi e riavvii l'istanza (stop, non destroy), tutto resta e supervisor riavvia
  ComfyUI e Ollama da solo: il provisioning non riparte.
- Se cambi le liste su GitHub con l'istanza accesa o riavviata:
  `cd /workspace/vast-dual-gpu && git pull && scripts/add-model.sh --all`
  (con repo privato: `git pull https://x-access-token:$GH_TOKEN@github.com/morfeo/vast-dual-gpu main`).

### File privati nel bucket (facoltativo)

Se i file del bucket sono pubblici bastano i link https e non serve nient'altro.
Per file privati usa righe `s3://...` e aggiungi al template:

| Variabile | A cosa serve |
|---|---|
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | chiavi di un utente IAM di sola lettura |
| `AWS_DEFAULT_REGION` | regione del bucket, es. `eu-south-1` |
| `S3_ENDPOINT_URL` | solo per R2, B2, Wasabi, MinIO (con AWS lasciala vuota) |

Policy IAM minima per l'utente (sostituisci `MIO-BUCKET`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["s3:ListBucket", "s3:GetBucketLocation"], "Resource": "arn:aws:s3:::MIO-BUCKET" },
    { "Effect": "Allow", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::MIO-BUCKET/*" }
  ]
}
```

**Costi**: scaricare da S3 verso vast.ai è traffico in uscita da AWS (circa 0,09 $/GB).
Ferma l'istanza invece di distruggerla quando puoi: `/workspace` resta e non riscarichi.

## 2. Cosa scaricare

Tutto si decide in file di testo, una riga per elemento, con `#` per i commenti.

### ComfyUI — `comfyui/models/<categoria>/download.txt`

`comfyui/models/` ricalca `ComfyUI/models`: c'è una cartella per ogni categoria
(`checkpoints`, `diffusion_models`, `loras`, `vae`, `text_encoders`, `clip_vision`,
`controlnet`, `upscale_models`, `embeddings`, ...) con dentro un `download.txt`.
Scrivi in ogni file i modelli da scaricare in quella cartella, uno per riga:

```
<sorgente>   [nome_file]
```

- Ogni `.txt` nella cartella viene letto: puoi dividere le liste (`loras/flux.txt`, `loras/sdxl.txt`).
- Sottocartelle (`loras/flux/download.txt` → `ComfyUI/models/loras/flux/`) e cartelle dei
  custom node (`ipadapter/`, `ultralytics/bbox/`): basta crearle.
- Dettagli ed elenco delle categorie in [comfyui/models/README.md](comfyui/models/README.md).
- **sorgente**:
  - `s3://bucket/percorso/file.safetensors`: un file dal bucket;
  - `s3://bucket/cartella/` (con la `/` finale): tutta la cartella;
  - `https://...`: link firmato (presigned) o qualsiasi URL. Attenzione: i link firmati scadono;
  - `https://huggingface.co/...`: aggiunge `HF_TOKEN` (vanno bene anche i link "blob");
  - `https://civitai.com/api/download/models/<id>`: aggiunge `CIVITAI_TOKEN`.
- **nome_file**: facoltativo. Utile quando l'URL non finisce col nome del file.

### Workflow — `comfyui/workflows/download.txt`

Link ai tuoi workflow `.json` (uno per riga, `<sorgente> [nome_file.json]`), oppure i `.json`
messi direttamente in `comfyui/workflows/`. Finiscono in `ComfyUI/user/default/workflows/`
e li trovi nella barra laterale "Workflows". Le sottocartelle vengono mantenute.
Un workflow già presente sull'istanza non viene sovrascritto.

### Custom node

Custom node in `comfyui/custom_nodes.txt` (c'è già ComfyUI-Manager, più ComfyUI-GGUF per i modelli `.gguf` di diffusione).

### Ollama — `ollama/models.txt` e `ollama/gguf.txt`

- `ollama/models.txt`: nomi del registry (`qwen3:8b`) o GGUF pubblici su HF (`hf.co/utente/repo:Q4_K_M`).
- `ollama/gguf.txt`: i tuoi GGUF.

  ```
  <nome_modello>   <sorgente>   [Modelfile]
  ```

  Il file viene scaricato e registrato con `ollama create`. Il Modelfile è facoltativo:
  mettilo in `ollama/modelfiles/` e scrivi `FROM __GGUF__` (vedi `esempio.Modelfile`).
  Senza Modelfile Ollama usa il template di chat contenuto nel GGUF.

### Sincronizzare cartelle intere del bucket

Se il bucket è già ordinato, non serve elencare i file:

```
mio-bucket/
├── comfyui/models/          -> COMFY_MODELS_SYNC=s3://mio-bucket/comfyui/models/
│   ├── checkpoints/...
│   ├── loras/...
│   └── vae/...
└── gguf/                    -> GGUF_SYNC=s3://mio-bucket/gguf/
    ├── mio-modello.gguf             diventa il modello "mio-modello"
    └── mio-modello.Modelfile        (facoltativo, con FROM __GGUF__)
```

`sync` copia solo i file nuovi o cambiati, quindi i riavvii sono veloci.

## 3. Con l'istanza accesa

```bash
cd /workspace/vast-dual-gpu
scripts/add-model.sh --list                                         # categorie disponibili
git pull && scripts/add-model.sh --all                              # dopo aver modificato le liste
scripts/add-model.sh loras s3://mio-bucket/loras/nuovo.safetensors --save
scripts/add-model.sh loras https://civitai.com/api/download/models/123456 mio_lora.safetensors
scripts/add-gguf.sh mio-modello s3://mio-bucket/gguf/mio.gguf --save
scripts/add-gguf.sh --sync                                          # rilegge GGUF_SYNC
scripts/status.sh                                                   # servizi, VRAM, modelli
```

`--save` aggiunge la riga al file di lista. Poi fai commit e push, così al prossimo avvio c'è.

## 4. Collegarsi

- **ComfyUI**: dalla scheda dell'istanza su vast.ai premi **Open** → **ComfyUI**
  (protetto dalla password del portale).
- **Ollama** non ha autenticazione e resta interno. Per usarlo dal tuo computer apri un tunnel SSH
  (IP e porta SSH sono nella scheda dell'istanza):

  ```bash
  ssh -p <PORTA_SSH> root@<IP> -L 11434:localhost:11434 -L 8188:localhost:18188
  ```

  poi Ollama è su http://localhost:11434 (e ComfyUI anche su http://localhost:8188).

Senza la voce ComfyUI in `PORTAL_CONFIG`, ComfyUI ascolta direttamente su `127.0.0.1:8188`:
nel tunnel usa `-L 8188:localhost:8188`.

## Note

- Ogni servizio vede solo la sua GPU: scegli modelli che stanno nella VRAM di una scheda.
- Con una sola GPU lo script mette entrambi sulla GPU 0.
- I download già completati sono registrati in `/workspace/.vast-downloads.done`.
  Cancella una riga per forzare di nuovo quel download.
- Log: `/workspace/logs/comfyui.log`, `/workspace/logs/ollama.log`.
- Riavvio di un servizio: `supervisorctl restart vdg-comfyui` (o `vdg-ollama`).
