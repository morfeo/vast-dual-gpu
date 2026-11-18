#!/usr/bin/env bash
# Scarica un modello per ComfyUI mentre l'istanza è accesa.
#   add-model.sh <categoria> <https://...|s3://bucket/file|s3://bucket/cartella/> [nome_file] [--save]
#   add-model.sh --list        mostra le categorie (cartelle in ComfyUI/models)
# --save aggiunge la riga anche a comfyui/models.txt, così al prossimo avvio c'è.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_DIR/config.env"
source "$REPO_DIR/lib.sh"

if [ "${1:-}" = "--list" ]; then ls -1 "$WORKSPACE/ComfyUI/models"; exit 0; fi

save=0; args=()
for a in "$@"; do if [ "$a" = "--save" ]; then save=1; else args+=("$a"); fi; done
if [ "${#args[@]}" -lt 2 ]; then sed -n '2,5p' "$0"; exit 1; fi

comfy_fetch "${args[0]}" "${args[1]}" "${args[2]:-}"
if [ "$save" = "1" ]; then
  echo "${args[*]}" >> "$REPO_DIR/comfyui/models.txt"
  log "aggiunto a comfyui/models.txt (ricordati commit e push)"
fi
log "fatto. In ComfyUI premi R (o ricarica la pagina) per vedere il modello."
