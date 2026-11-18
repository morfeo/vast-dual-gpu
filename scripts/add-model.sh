#!/usr/bin/env bash
# Scarica un modello per ComfyUI mentre l'istanza è accesa.
#   add-model.sh <categoria> <https://...|s3://bucket/file|s3://bucket/cartella/> [nome_file] [--save]
#   add-model.sh --list        mostra le categorie (cartelle in ComfyUI/models)
# --save aggiunge la riga anche a comfyui/models/<categoria>/download.txt,
#        così al prossimo avvio c'è.
#   add-model.sh --all         riscarica tutte le liste e i workflow (dopo un git pull)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_DIR/config.env"
source "$REPO_DIR/lib.sh"

if [ "${1:-}" = "--list" ]; then ls -1 "$WORKSPACE/ComfyUI/models"; exit 0; fi
if [ "${1:-}" = "--all" ]; then comfy_workflows; comfy_lists; log "fatto."; exit 0; fi

save=0; args=()
for a in "$@"; do if [ "$a" = "--save" ]; then save=1; else args+=("$a"); fi; done
if [ "${#args[@]}" -lt 2 ]; then sed -n '2,7p' "$0"; exit 1; fi

cat="${args[0]%/}"
comfy_fetch "$cat" "${args[1]}" "${args[2]:-}"
if [ "$save" = "1" ]; then
  mkdir -p "$REPO_DIR/comfyui/models/$cat"
  echo "${args[*]:1}" >> "$REPO_DIR/comfyui/models/$cat/download.txt"
  log "aggiunto a comfyui/models/$cat/download.txt (ricordati commit e push)"
fi
log "fatto. In ComfyUI premi R (o ricarica la pagina) per vedere il modello."
