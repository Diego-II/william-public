# William

A WhatsApp assistant built on [Hermes Agent](https://github.com/NousResearch/hermes-agent), meant to run
on an always-on Windows machine through WSL2. It uses Gemini by default, can switch to AWS Bedrock
through a local LiteLLM proxy, and has Google Calendar and Gmail tools exposed as MCP servers.

This is a public version of a personal setup. Personal configuration (numbers, accounts, keys, hosts)
lives elsewhere and is not part of this repository.

Status: a scaffold. Some Hermes config keys in `config/config.yaml.tmpl` are marked `(verify)` and
should be checked against your Hermes version before you rely on them.

## WhatsApp terms

William talks to WhatsApp through the Baileys bridge in Hermes, which is an unofficial WhatsApp Web
client. That is against WhatsApp's terms of service and the number can be banned. Use a dedicated
number you can afford to lose (a prepaid SIM or eSIM, not your personal number and not a VoIP number),
keep the allowlist short, and keep traffic low.

## How it fits together

```
WhatsApp (dedicated number) -- Baileys socket --+
                                                v
Windows host (never sleeps)        Task Scheduler keeps the WSL2 VM up at boot
  WSL2 Ubuntu 24.04 (systemd)      systemd starts and restarts the services
    hermes.service      Hermes gateway (WhatsApp, skills, browser, cron, memory)
    litellm.service     optional: Bedrock as an OpenAI-compatible endpoint on 127.0.0.1
    gcal-mcp.service    Google Calendar MCP server on 127.0.0.1
    gmail-mcp.service   Gmail MCP server on 127.0.0.1
  state: ~/.hermes (config, .env, SQLite, WhatsApp session), backed up locally and optionally to S3
```

## What you need

- A Windows 10/11 machine on AC power that can stay on, with admin rights and virtualization enabled.
- WSL2 with Ubuntu 24.04 and systemd. The installer sets this up.
- A WhatsApp bridge: the Baileys bridge that ships with Hermes Agent, plus a dedicated WhatsApp number
  on a phone that can scan a QR code.
- Model provider keys: a Gemini API key from Google AI Studio (default), or AWS credentials with
  `bedrock:InvokeModel` if you want the Bedrock switch.
- Optional: a Google OAuth desktop client for the Calendar and Gmail tools, and a Tavily key for web
  search.

## Install

The one-line installer below downloads `install.ps1` from this repository. It will work once the
repository is public. Until then, clone the repository and run the script from the clone.

Open PowerShell as Administrator on the Windows machine:

```powershell
irm https://raw.githubusercontent.com/Diego-II/william-public/main/install.ps1 | iex
```

Or from a clone:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

To install from your own fork, pass `-RepoUrl <url>` (and `-GitHubToken <PAT>` if the fork is private).
The token is passed on the command line and can end up in your shell history, so use a short-lived
token limited to that one repository.

Read the script before running it. It changes the machine:

1. Sets the power plan to never sleep or hibernate, including with the lid closed.
2. Enables WSL2 and installs Ubuntu 24.04. This may reboot once and then resume on its own.
3. Creates a `hermes` Linux user with passwordless sudo and turns on systemd.
4. Clones this repository to `/home/hermes/william` and runs `wsl/setup.sh`.
5. Registers a scheduled task that keeps the WSL VM running without a login.

`wsl/setup.sh` installs Node 22, Hermes Agent, uv and the Python tools, asks for the Gemini key and
the allowed WhatsApp numbers, shows the WhatsApp QR code for pairing (`hermes whatsapp`), and then
installs and starts the systemd services. It is safe to run again.

More detail, including the Google OAuth steps, is in [docs/setup.md](docs/setup.md).

## Configure

All settings live in `.env` in the checkout (`~/william/.env`, mode 600). Start from
[.env.example](.env.example). Never commit the real file.

| Variable | Purpose |
|---|---|
| `GEMINI_API_KEY` | Default model provider. |
| `WHATSAPP_ALLOWED_USERS` | Comma-separated numbers, country code, no `+`. Required: empty means nobody is answered. |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | Optional. Enables the LiteLLM proxy for Bedrock. |
| `LITELLM_MASTER_KEY` | Local key for the LiteLLM proxy. Replace the placeholder. |
| `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `GOOGLE_OAUTH_REFRESH_TOKEN` | Optional. Enables the Calendar and Gmail tools. |
| `TAVILY_API_KEY` | Optional web search. |
| `BACKUP_S3_BUCKET` | Optional. Blank means local backups only. |

To switch between Gemini and Bedrock, change the provider and model in `config/config.yaml.tmpl` (or in
the live `~/.hermes/config.yaml`): `gemini-2.5-flash-lite` on Google, or `bedrock-cheap` / `bedrock-mid`
on the local LiteLLM endpoint. Then restart Hermes.

The assistant's persona is in [SOUL.md](SOUL.md) and its skills are in `skills/`. Edit them to taste.

## Deploy changes

Deployment is manual. Push to the repository the machine was cloned from, then on the machine, inside
WSL2:

```bash
~/william/scripts/deploy.sh
```

It resets the checkout to `origin/main` (local edits in the checkout are discarded), syncs the Python
tools, re-renders the config and systemd units, restarts the services and checks that they are active.

## Operate

| Task | Command (inside WSL2) |
|---|---|
| Status | `systemctl status hermes gcal-mcp gmail-mcp litellm` |
| Logs | `journalctl -u hermes -f` |
| Restart | `sudo systemctl restart hermes` |
| Back up state | `~/william/scripts/backup.sh` |
| Restore state | `~/william/scripts/restore.sh` (reuses the WhatsApp session) |
| New number after a ban | `hermes whatsapp`, then update `WHATSAPP_ALLOWED_USERS` |

## Tests

```bash
cd tools
uv sync --extra dev
uv run pytest
```

## What is not included

- Any personal configuration: phone numbers, accounts, API keys, OAuth tokens, backups.
- Hermes Agent itself. `wsl/setup.sh` installs it from upstream.
- Continuous deployment. Deploying is a manual step here. Do not attach a self-hosted GitHub Actions
  runner to a public fork: anyone who opens a pull request could then run code on the machine.
- Remote access. Use something like Tailscale or another private network if you need a shell from
  outside; nothing here opens inbound ports.
- An official WhatsApp Business API integration.

## Layout

```
install.ps1   Windows installer (WSL2, power settings, boot task, hand-off to setup.sh)
wsl/          setup.sh (provisioning inside WSL), wsl.conf, .wslconfig template, cloud-init alternative
systemd/      service units: hermes, litellm, gcal-mcp, gmail-mcp
config/       Hermes config template and LiteLLM config
tools/        Python 3.13 MCP servers for Google Calendar and Gmail
scripts/      deploy, backup, restore
infra/        optional Terraform: Bedrock IAM user and S3 backup bucket
docs/         setup notes
```

## License

MIT. See [LICENSE](LICENSE). Hermes Agent is a separate MIT-licensed project by Nous Research.
