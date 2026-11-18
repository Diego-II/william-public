"""Pure-logic tests (no network / no Google creds required)."""

from __future__ import annotations

import base64

from william_tools import gcal_mcp, gmail_mcp


def test_when_all_day_vs_timed():
    assert gcal_mcp._when("2026-06-10") == {"date": "2026-06-10"}
    timed = gcal_mcp._when("2026-06-10T13:00:00-04:00")
    assert timed == {"dateTime": "2026-06-10T13:00:00-04:00"}


def test_summarize_picks_datetime_then_date():
    item = {
        "id": "abc",
        "summary": "Sync",
        "start": {"dateTime": "2026-06-10T13:00:00Z"},
        "end": {"date": "2026-06-11"},
        "attendees": [{"email": "a@x.com"}, {"email": "b@x.com"}],
        "htmlLink": "http://e",
    }
    s = gcal_mcp._summarize(item)
    assert s.start == "2026-06-10T13:00:00Z"
    assert s.end == "2026-06-11"
    assert s.attendees == ["a@x.com", "b@x.com"]


def test_extract_text_walks_parts():
    payload = {
        "mimeType": "multipart/alternative",
        "parts": [
            {"mimeType": "text/html", "body": {"data": base64.urlsafe_b64encode(b"<p>hi</p>").decode()}},
            {"mimeType": "text/plain", "body": {"data": base64.urlsafe_b64encode(b"hello").decode()}},
        ],
    }
    assert gmail_mcp._extract_text(payload) == "hello"


def test_raw_roundtrips_headers():
    raw = gmail_mcp._raw("to@x.com", "Subj", "Body", cc="c@x.com")
    decoded = base64.urlsafe_b64decode(raw["raw"]).decode()
    assert "To: to@x.com" in decoded
    assert "Subject: Subj" in decoded
    assert "Cc: c@x.com" in decoded
    assert "Body" in decoded
