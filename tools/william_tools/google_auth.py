"""Shared Google OAuth for the William MCP tools.

The serverless/headless model: do the interactive OAuth consent **once** on a
machine with a browser (``william-google-auth``), which prints a long-lived
**refresh token**. Store the client id/secret + refresh token in ``.env``. At
runtime each MCP server rebuilds credentials from those three values and refreshes
the short-lived access token on demand — no browser, no token files on the box.

Scopes requested cover both tools so a single refresh token serves Calendar + Gmail.
"""

from __future__ import annotations

from functools import lru_cache

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import Resource, build
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

# All scopes William may use. The one-time authorize flow asks for the union;
# individual tools pass the subset they need to build a service.
SCOPES: list[str] = [
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.compose",
]

TOKEN_URI = "https://oauth2.googleapis.com/token"


class GoogleSettings(BaseSettings):
    """OAuth credentials, read from the environment (.env)."""

    model_config = SettingsConfigDict(env_prefix="GOOGLE_OAUTH_", extra="ignore")

    client_id: str = Field(default="")
    client_secret: str = Field(default="")
    refresh_token: str = Field(default="")

    def assert_configured(self) -> None:
        missing = [
            name
            for name, val in (
                ("GOOGLE_OAUTH_CLIENT_ID", self.client_id),
                ("GOOGLE_OAUTH_CLIENT_SECRET", self.client_secret),
                ("GOOGLE_OAUTH_REFRESH_TOKEN", self.refresh_token),
            )
            if not val
        ]
        if missing:
            raise RuntimeError(
                "Google OAuth not configured. Missing: "
                + ", ".join(missing)
                + ". Run `william-google-auth` once to obtain a refresh token."
            )


@lru_cache(maxsize=1)
def _settings() -> GoogleSettings:
    return GoogleSettings()


def get_credentials(scopes: list[str]) -> Credentials:
    """Build refreshed user credentials for the given scopes."""
    s = _settings()
    s.assert_configured()
    creds = Credentials(
        token=None,
        refresh_token=s.refresh_token,
        client_id=s.client_id,
        client_secret=s.client_secret,
        token_uri=TOKEN_URI,
        scopes=scopes,
    )
    creds.refresh(Request())
    return creds


def build_service(api: str, version: str, scopes: list[str]) -> Resource:
    """Return an authenticated googleapiclient service (e.g. ('calendar','v3'))."""
    creds = get_credentials(scopes)
    return build(api, version, credentials=creds, cache_discovery=False)


def cli_authorize() -> None:
    """One-time interactive OAuth: prints a refresh token to paste into .env.

    Usage (on a machine with a browser):
        GOOGLE_OAUTH_CLIENT_ID=... GOOGLE_OAUTH_CLIENT_SECRET=... william-google-auth
    or pass a downloaded OAuth client JSON as the first CLI arg.
    """
    import json
    import sys

    from google_auth_oauthlib.flow import InstalledAppFlow

    if len(sys.argv) > 1:
        client_config = json.load(open(sys.argv[1]))
    else:
        s = _settings()
        if not (s.client_id and s.client_secret):
            sys.exit(
                "Set GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET, or pass an "
                "OAuth client JSON path as the first argument."
            )
        client_config = {
            "installed": {
                "client_id": s.client_id,
                "client_secret": s.client_secret,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": TOKEN_URI,
                "redirect_uris": ["http://localhost"],
            }
        }

    flow = InstalledAppFlow.from_client_config(client_config, scopes=SCOPES)
    # access_type=offline + prompt=consent guarantees a refresh token is returned.
    creds = flow.run_local_server(port=0, access_type="offline", prompt="consent")
    print("\n=== Add this to your .env ===")
    print(f"GOOGLE_OAUTH_REFRESH_TOKEN={creds.refresh_token}")
    if not creds.refresh_token:
        print(
            "\n⚠️  No refresh token returned. Revoke prior access at "
            "https://myaccount.google.com/permissions and re-run."
        )


if __name__ == "__main__":
    cli_authorize()
