#!/usr/bin/env bash
# Stato veloce: servizi, GPU, modelli Ollama.
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_DIR/config.env"
source "$REPO_DIR/lib.sh"

supervisorctl status vdg-comfyui vdg-ollama
echo
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv
echo
ollama list
echo
echo "log: $WORKSPACE/logs/comfyui.log  $WORKSPACE/logs/ollama.log"
