"""Google Calendar MCP server for William.

Exposes a small set of typed Calendar tools over streamable-HTTP MCP, connected
to Hermes via its MCP client. Auth is the shared refresh-token flow in
``william_tools.google_auth``.
"""

from __future__ import annotations

import os
from datetime import datetime, timezone

from mcp.server.fastmcp import FastMCP
from pydantic import BaseModel, Field

from william_tools.google_auth import build_service

SCOPES = ["https://www.googleapis.com/auth/calendar.events"]

mcp = FastMCP(
    "william-calendar",
    host=os.environ.get("GCAL_MCP_HOST", "127.0.0.1"),
    port=int(os.environ.get("GCAL_MCP_PORT", "8731")),
)


class EventSummary(BaseModel):
    id: str
    summary: str = Field(default="(no title)")
    start: str = Field(description="RFC3339 datetime or YYYY-MM-DD for all-day")
    end: str = ""
    location: str = ""
    attendees: list[str] = Field(default_factory=list)
    html_link: str = ""


def _svc():
    return build_service("calendar", "v3", SCOPES)


def _when(value: str) -> dict[str, str]:
    """Map an ISO string to a Calendar start/end object (all-day vs timed)."""
    return {"date": value} if len(value) == 10 else {"dateTime": value}


def _summarize(item: dict) -> EventSummary:
    start = item.get("start", {})
    end = item.get("end", {})
    return EventSummary(
        id=item.get("id", ""),
        summary=item.get("summary", "(no title)"),
        start=start.get("dateTime") or start.get("date") or "",
        end=end.get("dateTime") or end.get("date") or "",
        location=item.get("location", ""),
        attendees=[a.get("email", "") for a in item.get("attendees", [])],
        html_link=item.get("htmlLink", ""),
    )


@mcp.tool()
def list_events(
    time_min: str | None = None,
    time_max: str | None = None,
    max_results: int = 10,
    calendar_id: str = "primary",
) -> list[EventSummary]:
    """List upcoming events. time_min/time_max are RFC3339 (default: now → unbounded)."""
    if time_min is None:
        time_min = datetime.now(timezone.utc).isoformat()
    events = (
        _svc()
        .events()
        .list(
            calendarId=calendar_id,
            timeMin=time_min,
            timeMax=time_max,
            maxResults=max(1, min(max_results, 50)),
            singleEvents=True,
            orderBy="startTime",
        )
        .execute()
    )
    return [_summarize(e) for e in events.get("items", [])]


@mcp.tool()
def create_event(
    summary: str,
    start: str,
    end: str,
    description: str = "",
    location: str = "",
    attendees: list[str] | None = None,
    calendar_id: str = "primary",
) -> EventSummary:
    """Create an event. start/end are ISO (YYYY-MM-DD all-day, or RFC3339 datetime)."""
    body: dict = {
        "summary": summary,
        "description": description,
        "location": location,
        "start": _when(start),
        "end": _when(end),
    }
    if attendees:
        body["attendees"] = [{"email": e} for e in attendees]
    created = _svc().events().insert(calendarId=calendar_id, body=body).execute()
    return _summarize(created)


@mcp.tool()
def quick_add_event(text: str, calendar_id: str = "primary") -> EventSummary:
    """Create an event from natural language, e.g. 'Lunch with Ana Friday 1pm'."""
    created = _svc().events().quickAdd(calendarId=calendar_id, text=text).execute()
    return _summarize(created)


@mcp.tool()
def delete_event(event_id: str, calendar_id: str = "primary") -> str:
    """Delete an event by id."""
    _svc().events().delete(calendarId=calendar_id, eventId=event_id).execute()
    return f"Deleted event {event_id}."


def main() -> None:
    mcp.run(transport="streamable-http")


if __name__ == "__main__":
    main()
