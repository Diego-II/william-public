#!/usr/bin/env bash
# William — back up Hermes state (config, .env, SQLite, WhatsApp session, skills, memory).
# Local timestamped tarball + optional S3 copy. Keeps the last 14 local backups.
set -euo pipefail

REPO="${WILLIAM_HOME:-$HOME/william}"
set -a; [[ -f "$REPO/.env" ]] && source "$REPO/.env"; set +a
HERMES_HOME="$HOME/.hermes"
DEST="${BACKUP_LOCAL_DIR:-$HOME/william-backups}"
mkdir -p "$DEST"
STAMP="$(date +%Y%m%d-%H%M%S)"
FILE="$DEST/hermes-$STAMP.tar.gz"

# WhatsApp session keys mutate constantly — tar is point-in-time, good enough for recovery.
tar -czf "$FILE" -C "$HOME" \
  --exclude='.hermes/logs' \
  --exclude='.hermes/**/*.sock' \
  .hermes 2>/dev/null
echo "[ok] $FILE ($(du -h "$FILE" | cut -f1))"

# prune to last 14
ls -1t "$DEST"/hermes-*.tar.gz 2>/dev/null | tail -n +15 | xargs -r rm -f

if [[ -n "${BACKUP_S3_BUCKET:-}" ]]; then
  if command -v aws >/dev/null 2>&1; then
    aws s3 cp "$FILE" "s3://$BACKUP_S3_BUCKET/$(basename "$FILE")" --only-show-errors && \
      echo "[ok] uploaded to s3://$BACKUP_S3_BUCKET/"
  else
    echo "[!] aws CLI not installed — skipping S3 upload"
  fi
fi
