#!/usr/bin/env bash
# Funzioni condivise. Si carica con: source config.env; source lib.sh
# Richiede REPO_DIR impostato da chi lo carica.

log()  { printf '\033[1;34m[vast]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[vast] ATTENZIONE:\033[0m %s\n' "$*" >&2; }

# Segreti: le variabili del template vast arrivano nell'ambiente di on-start;
# in una shell SSH a volte no, quindi le rileggiamo da /etc/environment e,
# se esiste, da $WORKSPACE/secrets.env (file da creare a mano, mai nel repo).
for _f in /etc/environment "$WORKSPACE/secrets.env"; do
  if [ -f "$_f" ]; then set -a; . "$_f" 2>/dev/null || true; set +a; fi
done
unset _f

# Il client ollama parla sempre col server locale
export OLLAMA_HOST="127.0.0.1:${OLLAMA_PORT}"

DONE_FILE="$WORKSPACE/.vast-downloads.done"

# Legge un file di lista saltando righe vuote e commenti (# a inizio riga
# o preceduto da uno spazio, così i # dentro gli URL non danno fastidio).
read_list() {
  [ -f "$1" ] || return 0
  sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' "$1" | grep -v '^[[:space:]]*$' || true
}

is_done()   { [ -f "$DONE_FILE" ] && grep -qxF "$1" "$DONE_FILE"; }
mark_done() { echo "$1" >> "$DONE_FILE"; }

# --- bucket S3-compatibili (AWS S3, Cloudflare R2, Backblaze B2, Wasabi, MinIO) ---
ensure_aws() {
  command -v aws >/dev/null 2>&1 && return 0
  if [ ! -x "$WORKSPACE/tools-venv/bin/aws" ]; then
    log "installo awscli per leggere dal bucket"
    python3 -m venv "$WORKSPACE/tools-venv"
    "$WORKSPACE/tools-venv/bin/pip" install -q awscli
  fi
  export PATH="$WORKSPACE/tools-venv/bin:$PATH"
}

s3_aws() {
  ensure_aws
  if [ -n "${S3_ENDPOINT_URL:-}" ]; then
    aws --endpoint-url "$S3_ENDPOINT_URL" "$@" </dev/null
  else
    aws "$@" </dev/null
  fi
}

# --- download via http(s): Hugging Face, CivitAI, link firmati del bucket, qualsiasi URL ---
fetch_http() {
  local url="$1" dir="$2" name="$3"
  local args=(-x 16 -s 16 -k 1M -c --console-log-level=warn --summary-interval=0
              --auto-file-renaming=false --allow-overwrite=true -d "$dir")
  case "$url" in
    https://huggingface.co/*)
      url="${url/\/blob\//\/resolve\/}"   # il link "blob" della pagina diventa download diretto
      if [ -n "${HF_TOKEN:-}" ]; then args+=(--header="Authorization: Bearer $HF_TOKEN"); fi
      ;;
    https://civitai.com/*)
      # CivitAI reindirizza a un URL firmato: il token va nella query, non nell'header
      if [ -n "${CIVITAI_TOKEN:-}" ]; then
        if [[ "$url" == *\?* ]]; then url+="&token=$CIVITAI_TOKEN"; else url+="?token=$CIVITAI_TOKEN"; fi
      fi
      ;;
  esac
  # senza nome esplicito aria2 usa quello indicato dal server (Content-Disposition) o dall'URL
  if [ -n "$name" ]; then args+=(-o "$name"); fi
  aria2c "${args[@]}" "$url" </dev/null
}

# fetch <sorgente> <cartella_destinazione> [nome_file]
# sorgente: https://...  |  s3://bucket/percorso/file  |  s3://bucket/cartella/  (finisce con /)
fetch() {
  local src="$1" dir="$2" name="${3:-}"
  mkdir -p "$dir"

  # cartella intera del bucket: sync è già incrementale, niente registro
  if [[ "$src" == s3://*/ ]]; then
    log "sync $src -> $dir"
    s3_aws s3 sync "$src" "$dir/" --only-show-errors || { warn "sync fallito: $src"; return 1; }
    return 0
  fi

  case "$src" in
    s3://*|http://*|https://*) ;;
    *) warn "sorgente non riconosciuta (serve https:// o s3://): $src"; return 1 ;;
  esac

  local key="$src -> $dir/$name"
  if is_done "$key"; then log "già presente: ${name:-$src}"; return 0; fi

  log "scarico ${name:-$(basename "${src%%\?*}")} -> $dir"
  local rc=0
  case "$src" in
    s3://*)           s3_aws s3 cp "$src" "$dir/${name:-$(basename "$src")}" --only-show-errors || rc=$? ;;
    http://*|https://*) fetch_http "$src" "$dir" "$name" || rc=$? ;;
    *) warn "sorgente non riconosciuta (serve https:// o s3://): $src"; return 1 ;;
  esac
  if [ "$rc" -ne 0 ]; then warn "download fallito: $src"; return 1; fi
  mark_done "$key"
}

# --- ComfyUI ---
# comfy_fetch <categoria> <sorgente> [nome_file]
# categoria = cartella sotto ComfyUI/models, anche con sottocartelle (es. loras/flux)
comfy_fetch() {
  local cat="${1%/}" src="$2" name="${3:-}"
  local base="$WORKSPACE/ComfyUI/models"
  local top="${cat%%/*}"
  if [ ! -d "$base/$top" ]; then
    warn "models/$top non è una cartella standard di ComfyUI: la creo (serve solo se un custom node la usa)"
  fi
  fetch "$src" "$base/$cat" "$name"
}

# Legge tutte le liste in comfyui/models/<categoria>/*.txt (anche in sottocartelle)
# e scarica ogni riga "<sorgente> [nome_file]" in ComfyUI/models/<categoria>.
comfy_lists() {
  local root="$REPO_DIR/comfyui/models" list cat src name
  [ -d "$root" ] || return 0
  while IFS= read -r list <&4; do
    cat="$(dirname "${list#"$root"/}")"
    if [ "$cat" = "." ]; then warn "$(basename "$list") è fuori da una cartella di categoria: lo salto"; continue; fi
    while read -r src name <&3; do
      comfy_fetch "$cat" "$src" "${name:-}" || true
    done 3< <(read_list "$list")
  done 4< <(find "$root" -type f -name '*.txt' | sort)
}

# --- Ollama da GGUF ---
# ollama_create_gguf <nome> <file.gguf> [Modelfile]
# Nel Modelfile scrivi "FROM __GGUF__": viene sostituito col percorso del file.
ollama_create_gguf() {
  local name="$1" gguf="$2" mf="${3:-}"
  if ollama show "$name" >/dev/null 2>&1; then log "ollama: $name esiste già"; return 0; fi
  local tmp rc=0
  tmp="$(mktemp)"
  if [ -n "$mf" ] && [ -f "$mf" ]; then
    sed "s|__GGUF__|$gguf|g" "$mf" > "$tmp"
  else
    echo "FROM $gguf" > "$tmp"
  fi
  log "ollama: creo $name da $(basename "$gguf")"
  ollama create "$name" -f "$tmp" </dev/null || rc=$?
  rm -f "$tmp"
  return "$rc"
}

# gguf_add <nome> <sorgente> [Modelfile]
gguf_add() {
  local name="$1" src="$2" mf="${3:-}"
  if [[ "$src" == s3://*/ ]]; then warn "per un GGUF serve un file, non una cartella: $src"; return 1; fi
  fetch "$src" "$GGUF_DIR" "$name.gguf" || return 1
  if [ -n "$mf" ] && [[ "$mf" != /* ]]; then mf="$REPO_DIR/ollama/modelfiles/$mf"; fi
  if [ -z "$mf" ] && [ -f "$REPO_DIR/ollama/modelfiles/$name.Modelfile" ]; then
    mf="$REPO_DIR/ollama/modelfiles/$name.Modelfile"
  fi
  ollama_create_gguf "$name" "$GGUF_DIR/$name.gguf" "$mf"
}

# Scarica tutta la cartella GGUF_SYNC e crea un modello per ogni .gguf.
# Nome del modello = nome del file in minuscolo. Modelfile: <file>.Modelfile accanto
# al gguf nel bucket, oppure ollama/modelfiles/<nome>.Modelfile nel repo.
gguf_sync() {
  [ -n "${GGUF_SYNC:-}" ] || return 0
  local dir="$GGUF_DIR/sync" f name mf
  fetch "${GGUF_SYNC%/}/" "$dir" || return 1
  for f in "$dir"/*.gguf; do
    [ -e "$f" ] || continue
    if [[ "$(basename "$f")" =~ -[0-9]{5}-of-[0-9]{5}\.gguf$ ]]; then
      warn "$(basename "$f") è un GGUF diviso in parti: Ollama vuole un file unico (unisci con llama-gguf-split --merge)"
      continue
    fi
    name="$(basename "$f" .gguf | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._\n-' '-')"
    mf=""
    if [ -f "${f%.gguf}.Modelfile" ]; then mf="${f%.gguf}.Modelfile"
    elif [ -f "$REPO_DIR/ollama/modelfiles/$name.Modelfile" ]; then mf="$REPO_DIR/ollama/modelfiles/$name.Modelfile"; fi
    ollama_create_gguf "$name" "$f" "$mf" || warn "creazione fallita: $name"
  done
}
