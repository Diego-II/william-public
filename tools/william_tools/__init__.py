"""William custom MCP tool servers (Google Calendar, Gmail) — typed with Pydantic.

Each tool runs as its own streamable-HTTP MCP server (managed by systemd) and is
connected to Hermes Agent via its MCP client. Shared Google OAuth lives in
``william_tools.google_auth``.
"""

__version__ = "0.1.0"
