#!/usr/bin/env bash
# William — restore Hermes state from the latest (or a given) backup tarball.
# Usage: restore.sh [path-or-s3-uri]   (default: newest local backup)
set -euo pipefail

REPO="${WILLIAM_HOME:-$HOME/william}"
set -a; [[ -f "$REPO/.env" ]] && source "$REPO/.env"; set +a
DEST="${BACKUP_LOCAL_DIR:-$HOME/william-backups}"

SRC="${1:-}"
if [[ -z "$SRC" ]]; then
  SRC="$(ls -1t "$DEST"/hermes-*.tar.gz 2>/dev/null | head -1 || true)"
  [[ -z "$SRC" ]] && { echo "No local backups in $DEST"; exit 1; }
fi

TMP=""
if [[ "$SRC" == s3://* ]]; then
  TMP="$(mktemp)"; aws s3 cp "$SRC" "$TMP" --only-show-errors; SRC="$TMP"
fi

echo "Restoring from: $SRC"
sudo systemctl stop hermes 2>/dev/null || true
tar -xzf "$SRC" -C "$HOME"
chmod 600 "$HOME/.hermes/.env" 2>/dev/null || true
chmod -R go-rwx "$HOME/.hermes/platforms/whatsapp/session" 2>/dev/null || true
sudo systemctl start hermes 2>/dev/null || true
[[ -n "$TMP" ]] && rm -f "$TMP"
echo "[ok] Restored. WhatsApp session reused — no re-pair needed."
