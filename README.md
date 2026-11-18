# vast-dual-gpu

ComfyUI su una GPU e Ollama sull'altra, su un'istanza vast.ai con 2 GPU.
Modelli, LoRA e GGUF arrivano dal tuo bucket (S3, R2, B2, Wasabi, MinIO),
da link firmati o da Hugging Face e CivitAI.

| Servizio | GPU | Porta | Dati |
|---|---|---|---|
| ComfyUI | `COMFY_GPU` (0) | 8188 | `/workspace/ComfyUI` |
| Ollama  | `OLLAMA_GPU` (1) | 11434 | `/workspace/ollama-models`, GGUF in `/workspace/gguf` |

## 1. Template vast.ai

**Immagine**: una con CUDA e PyTorch, per esempio `pytorch/pytorch:2.7.1-cuda12.8-cudnn9-runtime`
o `vastai/pytorch`. Non usare l'immagine ComfyUI di vast: ha già il suo ComfyUI sulla 8188.

**Spazio disco**: abbondante. Checkpoint, video model e LLM occupano decine di GB ciascuno.

**Variabili d'ambiente** (nel template, *non* nel repo):

| Variabile | A cosa serve |
|---|---|
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | chiavi dell'utente IAM di sola lettura (vedi sotto) |
| `AWS_DEFAULT_REGION` | regione del bucket, es. `eu-south-1` (Milano), `eu-central-1` (Francoforte) |
| `S3_ENDPOINT_URL` | **non serve con AWS S3**: lasciala vuota (solo per R2, B2, Wasabi, MinIO) |
| `HF_TOKEN` | modelli Hugging Face con accesso limitato (Flux dev, ...) |
| `CIVITAI_TOKEN` | download da CivitAI |
| `COMFY_MODELS_SYNC`, `GGUF_SYNC` | facoltativi, vedi sotto |

In alternativa crea a mano `/workspace/secrets.env` sull'istanza (stesso formato `CHIAVE=valore`).

### Utente AWS di sola lettura

Non usare le chiavi del tuo account: su vast.ai l'istanza gira su macchine di terzi.
In IAM crea un utente dedicato (es. `vast-reader`) con questa policy, poi genera una
access key per lui (tipo "Application running outside AWS"):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::MIO-BUCKET"
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::MIO-BUCKET/*"
    }
  ]
}
```

Se vuoi limitarla a una cartella, sostituisci `MIO-BUCKET/*` con `MIO-BUCKET/comfyui/*` ecc.
Quando smetti di usare vast.ai, disattiva la chiave.

Prova dal tuo computer che le chiavi funzionano:

```bash
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_DEFAULT_REGION=eu-south-1 aws s3 ls s3://MIO-BUCKET/
```

**Costi**: scaricare da S3 verso vast.ai è traffico in uscita da AWS (circa 0,09 $/GB).
Un checkpoint da 20 GB scaricato a ogni nuova istanza si somma: tieni l'istanza
ferma (stop, non destroy) quando possibile, così `/workspace` resta e non riscarichi.

**On-start script**:

```bash
cd /workspace && (git -C vast-dual-gpu pull --ff-only || git clone https://github.com/<TUO_UTENTE>/vast-dual-gpu) \
  && bash vast-dual-gpu/setup.sh 2>&1 | tee -a /workspace/logs-setup.txt
```

Se il repo è privato usa un token GitHub di sola lettura nell'URL di clone
(`https://<token>@github.com/...`), sempre passato come variabile del template.

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

Le porte sono su `127.0.0.1`: Ollama non ha autenticazione e nemmeno ComfyUI.
Usa un tunnel SSH:

```bash
ssh -p <PORTA_SSH> root@<IP> -L 8188:localhost:8188 -L 11434:localhost:11434
```

Poi apri http://localhost:8188 (ComfyUI) e usa http://localhost:11434 (Ollama).
Se vuoi davvero esporre ComfyUI, imposta `COMFY_LISTEN=0.0.0.0` e aggiungi `-p 8188:8188` alle Docker options.

## Note

- Ogni servizio vede solo la sua GPU: scegli modelli che stanno nella VRAM di una scheda.
- Con una sola GPU lo script mette entrambi sulla GPU 0.
- I download già completati sono registrati in `/workspace/.vast-downloads.done`.
  Cancella una riga per forzare di nuovo quel download.
- Log: `/workspace/logs/comfyui.log`, `/workspace/logs/ollama.log`.
- Riavvio di un servizio: `supervisorctl restart vdg-comfyui` (o `vdg-ollama`).
