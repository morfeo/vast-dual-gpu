#!/bin/bash
# Script da indicare in PROVISIONING_SCRIPT nel template vast.ai.
# Scarica (o aggiorna) questo repo in /workspace e lancia setup.sh.
# Vast lo esegue al primo avvio dell'istanza, dopo aver avviato i suoi servizi.
#
# Repo pubblico:  PROVISIONING_SCRIPT=https://raw.githubusercontent.com/morfeo/vast-dual-gpu/main/provision.sh
# Repo privato:   copia questo file in un Gist "secret" e usa l'URL "Raw" del Gist,
#                 e aggiungi la variabile GH_TOKEN (token GitHub di sola lettura sul repo).
set -euo pipefail

REPO_URL="${VDG_REPO:-https://github.com/morfeo/vast-dual-gpu}"
BRANCH="${VDG_BRANCH:-main}"
WORKSPACE="${WORKSPACE:-/workspace}"
DEST="$WORKSPACE/vast-dual-gpu"

# Il token si usa solo nel comando, non resta salvato in .git/config
auth_url="$REPO_URL"
if [ -n "${GH_TOKEN:-}" ]; then
  auth_url="${REPO_URL/https:\/\//https://x-access-token:${GH_TOKEN}@}"
fi

mkdir -p "$WORKSPACE"
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull -q --ff-only "$auth_url" "$BRANCH" || echo "[vast] repo non aggiornato, uso la copia presente"
else
  git clone -q --branch "$BRANCH" "$auth_url" "$DEST"
  git -C "$DEST" remote set-url origin "$REPO_URL"
fi

bash "$DEST/setup.sh" 2>&1 | tee -a "$WORKSPACE/logs-setup.txt"
