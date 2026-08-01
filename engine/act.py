"""Stage 6 — act on the finding.

Everything up to here produces a report and stops: a very good analyst who
writes it up and goes home. This is the part that leaves a mark someone else
will find.

When an investigation localises a movement to a segment, the system pins that
segment as a HyperDX saved search. The next person to open HyperDX sees
"RCA: device OS version = Android 15" already there, scoped to the window that
mattered — nobody had to copy anything across.

It acts through the SAME ClickStack MCP the chat agent uses, not a private
back door into Mongo. If the tool is reachable by an LLM, it should be
reachable by us on the same terms.

Acting never breaks the pipeline. A diagnosis that could not pin a view is
still a diagnosis, so every failure here is reported and swallowed.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

LLM_ENV = Path.home() / ".config" / "clickhouse" / "llm.env"
DEFAULT_MCP = "http://127.0.0.1:8080/api/mcp"

# Only these dimensions exist as columns to filter on.
_DIM_COLUMNS = {
    "ad_format", "category", "publisher_tier", "vertical", "campaign_type",
    "region", "country", "device_model", "os_version", "app_id", "advertiser_id",
}


def _key() -> str | None:
    if os.environ.get("HYPERDX_MCP_API_KEY"):
        return os.environ["HYPERDX_MCP_API_KEY"]
    if LLM_ENV.exists():
        for line in LLM_ENV.read_text().splitlines():
            if line.startswith("HYPERDX_MCP_API_KEY="):
                return line.split("=", 1)[1].strip()
    return None


class Actor:
    """Talks to the ClickStack MCP over its JSON-RPC/SSE endpoint."""

    def __init__(self, url: str | None = None):
        self.url = url or os.environ.get("HYPERDX_MCP_URL") or DEFAULT_MCP
        self.key = _key()
        self.enabled = bool(self.key)
        self.error: str | None = None if self.enabled else "no HYPERDX_MCP_API_KEY"
        self._ready = False
        self._session: str | None = None

    def _post(self, payload: dict) -> dict | None:
        headers = {
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
            # The endpoint speaks SSE; without this Accept it 406s.
            "Accept": "application/json, text/event-stream",
        }
        # streamable-http MCP hands back a session id on initialize and expects
        # it echoed on every later call. Omit it and the server answers 400 on
        # the *next* request, which reads like an auth problem and is not.
        if self._session:
            headers["Mcp-Session-Id"] = self._session
        req = urllib.request.Request(
            self.url, data=json.dumps(payload).encode(), headers=headers)
        with urllib.request.urlopen(req, timeout=30) as r:
            sid = r.headers.get("Mcp-Session-Id") or r.headers.get("mcp-session-id")
            if sid:
                self._session = sid
            body = r.read().decode(errors="replace")
        for line in body.splitlines():
            if line.startswith("data: "):
                return json.loads(line[6:])
        return None

    def _handshake(self) -> bool:
        if self._ready:
            return True
        # The endpoint returns an intermittent 400 on initialize — measured
        # roughly one attempt in three, with an identical request that
        # succeeds on retry. Retry rather than treat a flaky handshake as a
        # failure to act.
        for attempt in range(4):
            try:
                self._post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                    "protocolVersion": "2024-11-05", "capabilities": {},
                    "clientInfo": {"name": "rca-engine", "version": "1"}}})
                break
            except urllib.error.HTTPError:
                if attempt == 3:
                    raise
                time.sleep(0.5 * (attempt + 1))
        try:
            # A notification carries no id, so the server has nothing to reply
            # with and answers 400. That is not a failure — the handshake is
            # complete either way, and the endpoint is stateless.
            self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        except urllib.error.HTTPError:
            pass
        self._ready = True
        return True

    def _call(self, tool: str, args: dict) -> dict | None:
        self._handshake()
        # Same intermittent 400 as the handshake. Retrying the call matters
        # more: a dropped handshake just delays us, a dropped tool call means
        # the system silently failed to act.
        for attempt in range(4):
            try:
                return self._post({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                                   "params": {"name": tool, "arguments": args}})
            except urllib.error.HTTPError:
                if attempt == 3:
                    raise
                # A stale session is one cause of a repeated 400, so drop it
                # and re-handshake before the next try.
                self._session, self._ready = None, False
                time.sleep(0.5 * (attempt + 1))
                self._handshake()
        return None

    def source_id(self, name: str = "Ad Events") -> str | None:
        r = self._call("clickstack_list_sources", {})
        if not r or "result" not in r:
            return None
        # The tool returns one content item holding {"sources": [...]} — not a
        # bare array, and not one item per source.
        for item in r["result"].get("content", []):
            try:
                payload = json.loads(item.get("text", ""))
            except Exception:
                continue
            entries = payload.get("sources", []) if isinstance(payload, dict) else payload
            for s in entries or []:
                if isinstance(s, dict) and s.get("name") == name:
                    return s.get("id")
        return None

    def pin_culprit(self, attribution) -> str | None:
        """Save a view scoped to the segment that explained the movement."""
        if not self.enabled:
            return None
        c = attribution.culprit
        if not c or c["dimension"] not in _DIM_COLUMNS:
            return None

        inc = attribution.incident
        name = f"RCA: {c['dimension_label']} = {c['value']} ({inc['start'][:10]})"
        try:
            sid = self.source_id()
            if not sid:
                self.error = "Ad Events source not found"
                return None
            # Escape single quotes; segment values are data, not our strings.
            value = str(c["value"]).replace("'", "''")
            r = self._call("clickstack_save_saved_search", {
                "name": name,
                "sourceId": sid,
                "select": ("event_time, " + c["dimension"] +
                           ", ad_format, country, is_filled, is_impression, revenue"),
                "where": f"{c['dimension']} = '{value}'",
                "whereLanguage": "sql",
                "orderBy": "event_time DESC",
                "tags": ["rca", "auto", inc["metric"]],
            })
            if r and "result" in r and not r["result"].get("isError"):
                return name
            self.error = f"save_saved_search rejected: {str(r)[:160]}"
        except urllib.error.HTTPError as e:
            self.error = f"HTTP {e.code} {e.read()[:120].decode(errors='replace')}"
        except Exception as e:
            self.error = f"{type(e).__name__}: {e}"
        return None
