# william-tools

Custom **MCP tool servers** for William, typed with Pydantic (Python ≥3.13). Each runs as its own
streamable-HTTP MCP server (managed by systemd) and is wired into Hermes via its MCP client.

| Server | Entry point | Default port | Scopes |
|---|---|---|---|
| Calendar | `gcal-mcp` | `8731` | `calendar.events` |
| Gmail | `gmail-mcp` | `8732` | `gmail.readonly`, `gmail.send`, `gmail.compose` |

## One-time Google OAuth

1. In Google Cloud Console → APIs & Services → Credentials, create an **OAuth client ID** of type
   *Desktop app*. Enable the **Calendar API** and **Gmail API**. Put the client id/secret in `.env`
   (`GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET`).
2. On a machine with a browser, run the consent flow once:
   ```bash
   uv run william-google-auth          # or: python -m william_tools.google_auth
   ```
   Approve the scopes; it prints `GOOGLE_OAUTH_REFRESH_TOKEN=...`. Paste that into `.env`.
3. Publish the OAuth consent screen (Testing tokens expire in 7 days; Production tokens are long-lived).

At runtime the servers rebuild credentials from those three values and refresh access tokens
automatically — no browser, no token files on the box.

## Run locally

```bash
uv sync --extra dev
uv run gcal-mcp     # serves http://127.0.0.1:8731/mcp
uv run gmail-mcp    # serves http://127.0.0.1:8732/mcp
uv run pytest
```

Hermes connects to these via its MCP client (see `config/config.yaml.tmpl`).
