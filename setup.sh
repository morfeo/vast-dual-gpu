#!/usr/bin/env bash
# Installa e avvia ComfyUI (una GPU) e Ollama (l'altra) su un'istanza vast.ai,
# poi scarica modelli, LoRA e GGUF dalle liste del repo e dal tuo bucket.
# È idempotente: va rilanciato a ogni avvio e salta quello che c'è già.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.env
source "$REPO_DIR/config.env"
# shellcheck source=lib.sh
source "$REPO_DIR/lib.sh"

COMFY_DIR="$WORKSPACE/ComfyUI"
VENV="$WORKSPACE/comfy-venv"
mkdir -p "$WORKSPACE/logs" "$GGUF_DIR" "$OLLAMA_MODELS_DIR"

# ---------------------------------------------------------------- pacchetti
log "installo i pacchetti di sistema"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git aria2 curl zstd supervisor python3-venv python3-pip >/dev/null

# ---------------------------------------------------------------- GPU
NGPU="$(nvidia-smi -L 2>/dev/null | wc -l | tr -d ' ')"
if [ "$NGPU" -lt 2 ]; then
  warn "trovate $NGPU GPU: ComfyUI e Ollama useranno la stessa (GPU 0)"
  COMFY_GPU=0; OLLAMA_GPU=0
fi
log "ComfyUI -> GPU $COMFY_GPU, Ollama -> GPU $OLLAMA_GPU"

# ---------------------------------------------------------------- ComfyUI
if [ ! -d "$COMFY_DIR/.git" ]; then
  log "scarico ComfyUI"
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI "$COMFY_DIR"
elif [ "$COMFY_UPDATE" = "1" ]; then
  git -C "$COMFY_DIR" pull --ff-only || warn "aggiornamento di ComfyUI fallito, uso la versione presente"
fi

if [ ! -x "$VENV/bin/python" ]; then
  # --system-site-packages: riusa il torch già presente nell'immagine (risparmia GB)
  python3 -m venv --system-site-packages "$VENV"
fi
log "dipendenze di ComfyUI"
"$VENV/bin/pip" install -q -r "$COMFY_DIR/requirements.txt"

log "custom node"
while read -r repo ref <&3; do
  name="$(basename "$repo" .git)"
  dir="$COMFY_DIR/custom_nodes/$name"
  if [ ! -d "$dir/.git" ]; then
    git clone "$repo" "$dir" || { warn "clone fallito: $repo"; continue; }
    if [ -n "${ref:-}" ]; then git -C "$dir" checkout -q "$ref" || warn "$name: ref $ref non trovato"; fi
  fi
  if [ -f "$dir/requirements.txt" ]; then
    "$VENV/bin/pip" install -q -r "$dir/requirements.txt" || warn "$name: requisiti non installati"
  fi
done 3< <(read_list "$REPO_DIR/comfyui/custom_nodes.txt")

# ---------------------------------------------------------------- Ollama
if ! command -v ollama >/dev/null 2>&1; then
  log "installo Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
fi

# ---------------------------------------------------------------- servizi
log "configuro supervisor"
cat > /etc/supervisor/conf.d/vdg-comfyui.conf <<EOF
[program:vdg-comfyui]
directory=$COMFY_DIR
command=$VENV/bin/python main.py --listen $COMFY_LISTEN --port $COMFY_PORT $COMFY_ARGS
environment=CUDA_VISIBLE_DEVICES="$COMFY_GPU"
autorestart=true
stopasgroup=true
killasgroup=true
stdout_logfile=$WORKSPACE/logs/comfyui.log
stdout_logfile_maxbytes=20MB
redirect_stderr=true
EOF

cat > /etc/supervisor/conf.d/vdg-ollama.conf <<EOF
[program:vdg-ollama]
command=$(command -v ollama) serve
environment=CUDA_VISIBLE_DEVICES="$OLLAMA_GPU",OLLAMA_HOST="$OLLAMA_LISTEN:$OLLAMA_PORT",OLLAMA_MODELS="$OLLAMA_MODELS_DIR",OLLAMA_KEEP_ALIVE="$OLLAMA_KEEP_ALIVE"
autorestart=true
stopasgroup=true
killasgroup=true
stdout_logfile=$WORKSPACE/logs/ollama.log
stdout_logfile_maxbytes=20MB
redirect_stderr=true
EOF

if pgrep -x supervisord >/dev/null; then
  supervisorctl reread >/dev/null
  supervisorctl update
else
  supervisord -c /etc/supervisor/supervisord.conf
fi

log "attendo che Ollama risponda"
for _ in $(seq 1 60); do
  curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/version" >/dev/null && break
  sleep 2
done
curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/version" >/dev/null || warn "Ollama non risponde: guarda $WORKSPACE/logs/ollama.log"

# ---------------------------------------------------------------- modelli
# I servizi sono già su: ComfyUI vede i nuovi modelli quando ricarichi la pagina.

if [ -n "$COMFY_MODELS_SYNC" ]; then
  fetch "${COMFY_MODELS_SYNC%/}/" "$COMFY_DIR/models" || true
fi

log "modelli ComfyUI (comfyui/models.txt)"
while read -r cat src name <&3; do
  comfy_fetch "$cat" "$src" "${name:-}" || true
done 3< <(read_list "$REPO_DIR/comfyui/models.txt")

log "modelli Ollama dal registry (ollama/models.txt)"
while read -r model <&3; do
  if ollama show "$model" >/dev/null 2>&1; then log "ollama: $model già presente"; continue; fi
  ollama pull "$model" </dev/null || warn "pull fallito: $model"
done 3< <(read_list "$REPO_DIR/ollama/models.txt")

log "GGUF per Ollama (ollama/gguf.txt)"
while read -r name src mf <&3; do
  gguf_add "$name" "$src" "${mf:-}" || warn "GGUF non aggiunto: $name"
done 3< <(read_list "$REPO_DIR/ollama/gguf.txt")

gguf_sync || true

log "fatto."
supervisorctl status vdg-comfyui vdg-ollama || true
cat <<EOF

Dal tuo computer apri il tunnel (IP e porta SSH li trovi su vast.ai):
  ssh -p <PORTA_SSH> root@<IP> -L $COMFY_PORT:localhost:$COMFY_PORT -L $OLLAMA_PORT:localhost:$OLLAMA_PORT
poi ComfyUI su http://localhost:$COMFY_PORT e Ollama su http://localhost:$OLLAMA_PORT
EOF
