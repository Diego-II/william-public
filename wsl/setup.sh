#!/usr/bin/env bash
# William — in-WSL provisioning (Phase 2). Runs as the `hermes` user with passwordless
# sudo, AFTER systemd has been enabled as PID 1. Idempotent: safe to re-run.
#
#   - installs OS deps, Node 22, Hermes Agent, uv + the Python 3.13 MCP tools, (optional) LiteLLM
#   - writes .env (prompts for essentials on first run) and ~/.hermes config
#   - pairs WhatsApp (interactive QR) and installs/enables the systemd services
#
# Hermes-specific config/pairing uses Hermes' own CLI (correct by construction); the
# exact provider/model keys are validated in the milestone-1 spike.
set -euo pipefail

REPO="${WILLIAM_HOME:-$HOME/william}"
ENV_FILE="$REPO/.env"
HERMES_HOME="$HOME/.hermes"
LINUX_USER="$(id -un)"

log()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m[!]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── 0. .env ──────────────────────────────────────────────────────────────────
ensure_env() {
  log ".env"
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$REPO/.env.example" "$ENV_FILE"
    warn "Created $ENV_FILE from template."
  fi
  chmod 600 "$ENV_FILE"
  # Prompt for the two essentials on first run if we have a terminal.
  if [[ -t 0 ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    if [[ -z "${GEMINI_API_KEY:-}" ]]; then
      read -rp "  Google AI Studio API key (Gemini) [blank to skip]: " v && \
        [[ -n "$v" ]] && sed -i "s|^GEMINI_API_KEY=.*|GEMINI_API_KEY=\"$v\"|" "$ENV_FILE"
    fi
    if [[ -z "${WHATSAPP_ALLOWED_USERS:-}" ]]; then
      read -rp "  Allowed WhatsApp numbers (country code, no +, comma-separated): " v && \
        sed -i "s|^WHATSAPP_ALLOWED_USERS=.*|WHATSAPP_ALLOWED_USERS=\"$v\"|" "$ENV_FILE"
    fi
  fi
  set -a; source "$ENV_FILE"; set +a
  ok ".env loaded."
}

# ── 1. OS deps + Node 22 + browser libs ──────────────────────────────────────
install_system_deps() {
  log "System packages"
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git curl ca-certificates build-essential ripgrep ffmpeg jq gettext-base
  if ! have node || [[ "$(node -v 2>/dev/null | cut -dv -f2 | cut -d. -f1)" -lt 22 ]]; then
    log "Node.js 22"
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
  ok "node $(node -v), npm $(npm -v)"
  # Playwright system deps for the headless browser tool
  sudo npx --yes playwright install-deps chromium || warn "playwright install-deps had warnings (continuing)"
}

# ── 2. Hermes Agent ──────────────────────────────────────────────────────────
install_hermes() {
  log "Hermes Agent"
  if ! have hermes; then
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  fi
  export PATH="$HOME/.local/bin:$PATH"
  grep -q '.local/bin' "$HOME/.bashrc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  hermes --version || warn "hermes installed but --version failed; verify in spike"
}

# ── 3. uv + Python 3.13 MCP tools ────────────────────────────────────────────
install_tools() {
  log "MCP tools (Python 3.13)"
  have uv || curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  ( cd "$REPO/tools" && uv python install 3.13 && uv sync )
  ok "william-tools installed (gcal-mcp, gmail-mcp)."
}

# ── 4. LiteLLM → Bedrock (optional) ──────────────────────────────────────────
install_litellm() {
  if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then warn "No AWS keys — skipping Bedrock/LiteLLM."; return; fi
  log "LiteLLM (Bedrock switch)"
  uv tool install 'litellm[proxy]' || pipx install 'litellm[proxy]' || true
  ok "LiteLLM available on :$LITELLM_PORT (config: config/litellm.config.yaml)."
}

# ── 5. Hermes config + ~/.hermes/.env ────────────────────────────────────────
configure_hermes() {
  log "Hermes config"
  mkdir -p "$HERMES_HOME"
  # Hermes reads ~/.hermes/.env — expose the keys it needs.
  install -m 600 /dev/stdin "$HERMES_HOME/.env" <<EOF
GEMINI_API_KEY=${GEMINI_API_KEY:-}
GOOGLE_API_KEY=${GEMINI_API_KEY:-}
TAVILY_API_KEY=${TAVILY_API_KEY:-}
WHATSAPP_ENABLED=${WHATSAPP_ENABLED:-true}
WHATSAPP_MODE=${WHATSAPP_MODE:-bot}
WHATSAPP_ALLOWED_USERS=${WHATSAPP_ALLOWED_USERS:-}
EOF
  # Seed config.yaml from our template on first run (kept under version control so
  # changes deploy via scripts/deploy.sh). Verify provider/model/mcp keys against `hermes model`
  # / `hermes tools` during the spike, then commit any corrections.
  if [[ ! -f "$HERMES_HOME/config.yaml" ]]; then
    export WILLIAM_HOME="$REPO" GCAL_MCP_PORT GMAIL_MCP_PORT LITELLM_PORT HERMES_PRIMARY_MODEL
    envsubst < "$REPO/config/config.yaml.tmpl" > "$HERMES_HOME/config.yaml"
    warn "Wrote starter ~/.hermes/config.yaml — run 'hermes model' to confirm the provider."
  fi
  # Seed persona + skills (verify exact injection path with Hermes docs during the spike)
  cp -f "$REPO/SOUL.md" "$HERMES_HOME/SOUL.md" 2>/dev/null || true
  mkdir -p "$HERMES_HOME/skills"
  cp -n "$REPO"/skills/*.md "$HERMES_HOME/skills/" 2>/dev/null || true
  ok "Hermes configured."
}

# ── 6. WhatsApp pairing (interactive) ────────────────────────────────────────
pair_whatsapp() {
  log "WhatsApp pairing"
  if [[ -d "$HERMES_HOME/platforms/whatsapp/session" ]]; then ok "Already paired (session present)."; return; fi
  if [[ -t 0 ]]; then
    warn "Scan the QR below from the BOT's phone: WhatsApp ▸ Linked Devices ▸ Link a Device."
    hermes whatsapp || warn "Pairing exited non-zero — re-run 'hermes whatsapp' later."
  else
    warn "No TTY — run 'hermes whatsapp' on the attached screen to pair."
  fi
}

# ── 7. systemd services ──────────────────────────────────────────────────────
install_services() {
  log "systemd services"
  export WILLIAM_HOME="$REPO" LINUX_USER HOME GCAL_MCP_PORT GMAIL_MCP_PORT LITELLM_PORT
  local units=(hermes gcal-mcp gmail-mcp)
  [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && units+=(litellm)
  for u in "${units[@]}"; do
    envsubst < "$REPO/systemd/$u.service" | sudo tee "/etc/systemd/system/$u.service" >/dev/null
  done
  sudo systemctl daemon-reload
  for u in "${units[@]}"; do sudo systemctl enable --now "$u.service" || warn "$u failed to start (check journalctl -u $u)"; done
  ok "Enabled: ${units[*]}"
}

main() {
  cd "$REPO"
  ensure_env
  install_system_deps
  install_hermes
  install_tools
  install_litellm
  configure_hermes
  pair_whatsapp
  install_services
  log "Done"
  ok "William is up. Status: systemctl status hermes | Logs: journalctl -u hermes -f"
}

main "$@"
