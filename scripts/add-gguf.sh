#!/usr/bin/env bash
# Scarica un GGUF e lo registra in Ollama mentre l'istanza è accesa.
#   add-gguf.sh <nome_modello> <https://...|s3://bucket/file.gguf> [Modelfile] [--save]
#   add-gguf.sh --sync         riesegue la sincronizzazione di GGUF_SYNC
# --save aggiunge la riga anche a ollama/gguf.txt, così al prossimo avvio c'è.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_DIR/config.env"
source "$REPO_DIR/lib.sh"

if [ "${1:-}" = "--sync" ]; then gguf_sync; ollama list; exit 0; fi

save=0; args=()
for a in "$@"; do if [ "$a" = "--save" ]; then save=1; else args+=("$a"); fi; done
if [ "${#args[@]}" -lt 2 ]; then sed -n '2,5p' "$0"; exit 1; fi

gguf_add "${args[0]}" "${args[1]}" "${args[2]:-}"
if [ "$save" = "1" ]; then
  echo "${args[*]}" >> "$REPO_DIR/ollama/gguf.txt"
  log "aggiunto a ollama/gguf.txt (ricordati commit e push)"
fi
log "fatto. Prova con: ollama run ${args[0]}"
