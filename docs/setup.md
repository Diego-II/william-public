# William — setup notes

Detailed companion to the root README. Order: number → install → Google tools → (optional) Bedrock →
deploying changes → later: Tailscale.

## 1. WhatsApp number (do this first)
- Use a **dedicated, disposable number** — a cheap prepaid **SIM** or carrier-grade **eSIM**. **Not**
  your personal number, **not** Google Voice/VoIP (WhatsApp blocks VoIP; voice-OTP + real SIM are
  reliable). Put a normal WhatsApp account on it (on a phone), then link William as a device.
- A ban (Baileys is an unofficial client, which WhatsApp's terms do not allow) affects **only this number** — group
  members are safe. Keep it human: allowlist only, no rapid-fire, treat the number as replaceable.

## 2. Install on the laptop
- AC power, temporary screen/keyboard attached.
- Elevated PowerShell: `irm https://raw.githubusercontent.com/Diego-II/william-public/main/install.ps1 | iex`
  (using a private fork? clone it first and run `.\install.ps1 -RepoUrl <url> -GitHubToken <PAT>`;
  the token goes on the command line, so use a short-lived one limited to that repo).
- After the one reboot, the in-WSL setup prompts for your **Gemini key** + **allowed numbers**, then
  shows the **WhatsApp QR** — scan it from the bot phone (WhatsApp ▸ Linked Devices). Services enable.

## 3. Google Calendar + Gmail tools (optional)
1. Google Cloud Console → enable **Calendar API** + **Gmail API**; create an OAuth **Desktop** client.
2. Put `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` in `.env`.
3. On any machine with a browser: `cd tools && uv run william-google-auth` → approve → paste the printed
   `GOOGLE_OAUTH_REFRESH_TOKEN` into `.env`. Publish the consent screen so the token stays long-lived.
4. Run `scripts/deploy.sh` on the box → the `gcal-mcp` / `gmail-mcp` services pick it up.

## 4. AWS Bedrock switch (optional)
- Create a **dedicated IAM user** with only `bedrock:InvokeModel` (region us-east-1). Put its
  `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in `.env`. `setup.sh` then runs the LiteLLM service.
- To use it, set the Hermes provider to `bedrock` / model `bedrock-cheap` (Nova Micro) or `bedrock-mid`
  (Haiku 4.5) in `config/config.yaml.tmpl`, then deploy. `infra/` has optional Terraform for the IAM
  user + S3 backup bucket.

## 5. Deploying changes (manual)
- Push your changes to the repo the box was cloned from, then on the box run `~/william/scripts/deploy.sh`.
  It hard-resets the checkout to `origin/main`, syncs the Python tools, re-renders config and systemd
  units, restarts the services and health-checks them.
- There is no CI deploy here on purpose. Do not attach a self-hosted GitHub Actions runner to a public
  repository: anyone who opens a pull request could run code on that machine.

## 6. Later: Tailscale (remote access)
- Install Tailscale on the laptop, `tailscale up`. Then you can SSH into WSL2 from anywhere for ad-hoc
  ops, tail logs, or trigger `scripts/deploy.sh` — without exposing anything publicly.

## Troubleshooting
- `journalctl -u hermes -f` — gateway logs. `systemctl status gcal-mcp gmail-mcp litellm`.
- Lid-closed still sleeps? `powercfg /a` — if only S0/Modern Standby exists, disable nap or keep lid open.
- WhatsApp dropped? Session is saved; `systemctl restart hermes`. If banned, new SIM → `hermes whatsapp`.
- Restore after a wipe: `scripts/restore.sh` (no re-pair).
