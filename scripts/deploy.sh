#!/usr/bin/env bash
# William — deploy. Run manually on the box (inside WSL2).
# Pulls latest, syncs deps, re-renders config + units, restarts services, health-checks.
set -euo pipefail

REPO="${WILLIAM_HOME:-$HOME/william}"
BRANCH="${WILLIAM_BRANCH:-main}"
HERMES_HOME="$HOME/.hermes"
cd "$REPO"

log() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }

log "Pull origin/$BRANCH"
git fetch --all --prune -q
git reset --hard "origin/$BRANCH"     # take exactly what's on the remote branch; discards local edits
chmod +x wsl/setup.sh scripts/*.sh 2>/dev/null || true

# Load env for rendering
set -a; [[ -f "$REPO/.env" ]] && source "$REPO/.env"; set +a
export WILLIAM_HOME="$REPO" LINUX_USER="$(id -un)" HOME \
       GCAL_MCP_PORT="${GCAL_MCP_PORT:-8731}" GMAIL_MCP_PORT="${GMAIL_MCP_PORT:-8732}" \
       LITELLM_PORT="${LITELLM_PORT:-8740}" HERMES_PRIMARY_MODEL="${HERMES_PRIMARY_MODEL:-gemini-2.5-flash-lite}"

log "Sync Python tools"
( cd tools && uv sync -q )

log "Re-render config + systemd units"
mkdir -p "$HERMES_HOME"
# Only overwrite config.yaml if the template changed since last deploy (avoid clobbering live tweaks).
if ! diff -q <(envsubst < config/config.yaml.tmpl) "$HERMES_HOME/config.yaml" >/dev/null 2>&1; then
  envsubst < config/config.yaml.tmpl > "$HERMES_HOME/config.yaml"
  echo "  config.yaml updated"
fi
units=(hermes gcal-mcp gmail-mcp)
[[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && units+=(litellm)
for u in "${units[@]}"; do
  envsubst < "systemd/$u.service" | sudo tee "/etc/systemd/system/$u.service" >/dev/null
done
sudo systemctl daemon-reload

log "Restart services"
for u in "${units[@]}"; do
  sudo systemctl enable "$u" >/dev/null 2>&1 || true
  sudo systemctl restart "$u"
done

log "Health check"
sleep 4
fail=0
for u in "${units[@]}"; do
  if systemctl is-active --quiet "$u"; then echo "  [ok] $u active";
  else echo "  [FAIL] $u"; journalctl -u "$u" -n 20 --no-pager || true; fail=1; fi
done
exit $fail
