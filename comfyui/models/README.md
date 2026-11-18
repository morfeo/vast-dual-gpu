# Liste dei modelli per ComfyUI

Questa cartella ha la stessa struttura di `ComfyUI/models` sull'istanza.
In ogni cartella, ogni file `.txt` è una lista di file da scaricare lì.

```
comfyui/models/
├── checkpoints/download.txt      -> ComfyUI/models/checkpoints/
├── loras/download.txt            -> ComfyUI/models/loras/
├── loras/flux/download.txt       -> ComfyUI/models/loras/flux/      (sottocartella: creala tu)
├── loras/sdxl.txt                -> ComfyUI/models/loras/           (più liste nella stessa cartella vanno bene)
└── ipadapter/download.txt        -> ComfyUI/models/ipadapter/       (cartella di un custom node: creala tu)
```

## Formato di una riga

```
<sorgente>   [nome_file]
```

Righe vuote e righe che iniziano con `#` vengono ignorate.

**sorgente**
- `s3://bucket/percorso/file.safetensors`: un file dal tuo bucket;
- `s3://bucket/cartella/` (con la `/` finale): tutto il contenuto della cartella;
- `https://...`: link firmato o qualsiasi URL;
- `https://huggingface.co/...`: aggiunge `HF_TOKEN` (vanno bene anche i link "blob");
- `https://civitai.com/api/download/models/<id>`: aggiunge `CIVITAI_TOKEN`.

**nome_file** (facoltativo): come salvare il file. Serve quando l'URL non finisce
col nome del file (CivitAI, link firmati).

## Cartelle standard

| Cartella | Cosa contiene |
|---|---|
| `checkpoints` | modelli completi (SD1.5, SDXL, ...) |
| `diffusion_models` | solo il modello di diffusione (Flux, Wan, HunyuanVideo, ...) |
| `unet` | nome vecchio di `diffusion_models` |
| `text_encoders` | T5, CLIP-L, umt5, ... |
| `clip` | nome vecchio di `text_encoders` |
| `clip_vision` | encoder di immagini (IP-Adapter, Wan i2v, ...) |
| `vae` | VAE |
| `vae_approx` | VAE leggeri per le anteprime (TAESD) |
| `loras` | LoRA e LyCORIS |
| `controlnet` | ControlNet e T2I-Adapter |
| `upscale_models` | ESRGAN, 4x-UltraSharp, ... |
| `latent_upscale_models` | upscaler nello spazio latente |
| `embeddings` | textual inversion |
| `hypernetworks`, `style_models`, `gligen`, `photomaker`, `model_patches`, `audio_encoders` | modelli specifici |
| `diffusers` | modelli in formato diffusers |
| `configs` | file `.yaml` di configurazione |

Una cartella che non esiste in ComfyUI viene creata comunque (con un avviso).
