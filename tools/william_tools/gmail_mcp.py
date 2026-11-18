"""Gmail MCP server for William.

Typed Gmail tools over streamable-HTTP MCP: search, read, send, draft. Auth is the
shared refresh-token flow in ``william_tools.google_auth``.
"""

from __future__ import annotations

import base64
import os
from email.message import EmailMessage

from mcp.server.fastmcp import FastMCP
from pydantic import BaseModel, Field

from william_tools.google_auth import build_service

SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.compose",
]

mcp = FastMCP(
    "william-gmail",
    host=os.environ.get("GMAIL_MCP_HOST", "127.0.0.1"),
    port=int(os.environ.get("GMAIL_MCP_PORT", "8732")),
)


class MessageSummary(BaseModel):
    id: str
    thread_id: str = ""
    sender: str = Field(default="", alias="from")
    subject: str = ""
    date: str = ""
    snippet: str = ""

    model_config = {"populate_by_name": True}


class MessageBody(MessageSummary):
    to: str = ""
    body: str = ""


def _svc():
    return build_service("gmail", "v1", SCOPES)


def _headers(payload: dict) -> dict[str, str]:
    return {h["name"].lower(): h["value"] for h in payload.get("headers", [])}


def _find_part(payload: dict, mime: str) -> str:
    """Depth-first walk for the first part of the given mime type."""
    if payload.get("mimeType") == mime:
        data = payload.get("body", {}).get("data")
        if data:
            return base64.urlsafe_b64decode(data).decode("utf-8", "replace")
    for part in payload.get("parts", []) or []:
        text = _find_part(part, mime)
        if text:
            return text
    return ""


def _extract_text(payload: dict) -> str:
    """First text/plain part anywhere in the tree; text/html only if there is none."""
    return _find_part(payload, "text/plain") or _find_part(payload, "text/html")


@mcp.tool()
def search_messages(query: str = "in:inbox", max_results: int = 10) -> list[MessageSummary]:
    """Search mail with Gmail query syntax (e.g. 'from:ana is:unread newer_than:7d')."""
    svc = _svc()
    listing = (
        svc.users()
        .messages()
        .list(userId="me", q=query, maxResults=max(1, min(max_results, 25)))
        .execute()
    )
    out: list[MessageSummary] = []
    for ref in listing.get("messages", []):
        msg = (
            svc.users()
            .messages()
            .get(userId="me", id=ref["id"], format="metadata",
                 metadataHeaders=["From", "Subject", "Date"])
            .execute()
        )
        h = _headers(msg.get("payload", {}))
        out.append(
            MessageSummary(
                id=msg["id"],
                thread_id=msg.get("threadId", ""),
                **{"from": h.get("from", "")},
                subject=h.get("subject", ""),
                date=h.get("date", ""),
                snippet=msg.get("snippet", ""),
            )
        )
    return out


@mcp.tool()
def get_message(message_id: str) -> MessageBody:
    """Fetch a single message's headers and plain-text body."""
    msg = _svc().users().messages().get(userId="me", id=message_id, format="full").execute()
    payload = msg.get("payload", {})
    h = _headers(payload)
    return MessageBody(
        id=msg["id"],
        thread_id=msg.get("threadId", ""),
        **{"from": h.get("from", "")},
        to=h.get("to", ""),
        subject=h.get("subject", ""),
        date=h.get("date", ""),
        snippet=msg.get("snippet", ""),
        body=_extract_text(payload),
    )


def _raw(to: str, subject: str, body: str, cc: str = "", bcc: str = "") -> dict[str, str]:
    em = EmailMessage()
    em["To"] = to
    em["Subject"] = subject
    if cc:
        em["Cc"] = cc
    if bcc:
        em["Bcc"] = bcc
    em.set_content(body)
    return {"raw": base64.urlsafe_b64encode(em.as_bytes()).decode()}


@mcp.tool()
def send_message(to: str, subject: str, body: str, cc: str = "", bcc: str = "") -> str:
    """Send an email immediately."""
    sent = _svc().users().messages().send(userId="me", body=_raw(to, subject, body, cc, bcc)).execute()
    return f"Sent message {sent.get('id', '?')} to {to}."


@mcp.tool()
def create_draft(to: str, subject: str, body: str, cc: str = "", bcc: str = "") -> str:
    """Create a draft (does not send) — good for human review before sending."""
    draft = (
        _svc()
        .users()
        .drafts()
        .create(userId="me", body={"message": _raw(to, subject, body, cc, bcc)})
        .execute()
    )
    return f"Created draft {draft.get('id', '?')} to {to}."


def main() -> None:
    mcp.run(transport="streamable-http")


if __name__ == "__main__":
    main()
