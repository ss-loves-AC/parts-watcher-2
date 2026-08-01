"""Langfuse tracing — "no trace, no credit".

Traceability is a scored criterion, not instrumentation for our own comfort:
a judge must be able to open a trace and follow what was checked, in what
order, and why. So every investigation becomes one trace, and every stage a
span carrying its real inputs and outputs.

Dependency-free on purpose, same as ch.py: this posts to Langfuse's public
ingestion API over stdlib HTTP. Nothing to pip-install at 3am, and the batch
format is stable.

Host resolution matters. The self-hosted Langfuse sits behind Cloudflare
Access, which rejects API calls from outside the tunnel with a 403. On the VPC
runner — where the real runs happen — it is plain localhost. So LANGFUSE_HOST
defaults to localhost and is overridable; from a laptop, open a tunnel:

    ssh -f -N -L 3000:127.0.0.1:3000 kite@<vpc>

Tracing never breaks the pipeline. If Langfuse is unreachable the run
continues and says so — a missing trace costs a criterion, a crashed run costs
everything.
"""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

LLM_ENV = Path.home() / ".config" / "clickhouse" / "llm.env"
DEFAULT_HOST = "http://127.0.0.1:3000"
# Where a HUMAN opens the trace. Deliberately separate from the ingestion host:
# we post over localhost (fast, and Cloudflare Access 403s the API from
# outside), but a link to 127.0.0.1 is useless in someone else's browser — and
# an unopenable trace fails "a judge should be able to open your traces".
DEFAULT_PUBLIC_URL = "https://langfuse.datagan.site"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _uuid() -> str:
    return str(uuid.uuid4())


def _creds() -> tuple[str | None, str | None]:
    pk = os.environ.get("LANGFUSE_PUBLIC_KEY")
    sk = os.environ.get("LANGFUSE_SECRET_KEY")
    if pk and sk:
        return pk, sk
    if LLM_ENV.exists():
        env = dict(
            line.split("=", 1)
            for line in LLM_ENV.read_text().splitlines()
            if "=" in line and not line.startswith("#")
        )
        return (
            env.get("LANGFUSE_PUBLIC_KEY", "").strip() or None,
            env.get("LANGFUSE_SECRET_KEY", "").strip() or None,
        )
    return None, None


class Tracer:
    """Collects events and posts them in one batch at flush()."""

    def __init__(self, host: str | None = None, public_url: str | None = None):
        self.host = (host or os.environ.get("LANGFUSE_HOST") or DEFAULT_HOST).rstrip("/")
        self.public_url = (
            public_url or os.environ.get("LANGFUSE_PUBLIC_URL") or DEFAULT_PUBLIC_URL
        ).rstrip("/")
        self.pk, self.sk = _creds()
        self.enabled = bool(self.pk and self.sk)
        self.events: list[dict] = []
        self.error: str | None = None if self.enabled else "no Langfuse credentials"

    # ------------------------------------------------------------------ api
    def trace(self, name: str, *, input=None, metadata=None, tags=None) -> str:
        tid = _uuid()
        self._add("trace-create", {
            "id": tid, "name": name, "timestamp": _now(),
            # public=True so the trace is viewable without a Langfuse account.
            # "No trace, no credit" is worth nothing if opening the link needs
            # an account only we have — a judge would see a sign-in screen and
            # score zero for traceability.
            #
            # This is belt-and-braces, not the plan: the submission also ships
            # queries.sql, evidence.json and REPORT.md in the repo, so the
            # working is checkable even if this instance is unreachable.
            "public": True,
            "input": input, "metadata": metadata, "tags": tags or [],
        })
        return tid

    def span(self, trace_id: str, name: str, start: str, end: str,
             *, input=None, output=None, metadata=None, level: str = "DEFAULT",
             parent: str | None = None) -> str:
        sid = _uuid()
        self._add("span-create", {
            "id": sid, "traceId": trace_id, "name": name,
            "startTime": start, "endTime": end, "parentObservationId": parent,
            "input": input, "output": output, "metadata": metadata, "level": level,
        })
        return sid

    def generation(self, trace_id: str, name: str, start: str, end: str,
                   *, model: str, input=None, output=None, metadata=None,
                   parent: str | None = None) -> str:
        gid = _uuid()
        self._add("generation-create", {
            "id": gid, "traceId": trace_id, "name": name,
            "startTime": start, "endTime": end, "model": model,
            "parentObservationId": parent,
            "input": input, "output": output, "metadata": metadata,
        })
        return gid

    def finish_trace(self, trace_id: str, *, output=None, metadata=None) -> None:
        self._add("trace-create", {  # same id upserts
            "id": trace_id, "output": output, "metadata": metadata,
            "timestamp": _now(),
        })

    def url(self, trace_id: str, observation: str | None = None) -> str:
        """The link a human clicks — public host, not the ingestion host.

        With an observation id the UI opens focused on that node, so a single
        run-level trace still yields a direct link per investigation.
        """
        base = f"{self.public_url}/trace/{trace_id}"
        return f"{base}?observation={observation}" if observation else base

    # ----------------------------------------------------------------- guts
    def _add(self, type_: str, body: dict) -> None:
        if self.enabled:
            self.events.append({"id": _uuid(), "timestamp": _now(),
                                "type": type_, "body": body})

    def flush(self) -> bool:
        """Post everything. Returns success; never raises."""
        if not self.enabled or not self.events:
            return False
        payload = json.dumps({"batch": self.events}, default=str).encode()
        auth = base64.b64encode(f"{self.pk}:{self.sk}".encode()).decode()
        req = urllib.request.Request(
            f"{self.host}/api/public/ingestion", data=payload,
            headers={"Content-Type": "application/json",
                     "Authorization": f"Basic {auth}"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                body = json.loads(r.read() or b"{}")
            errs = body.get("errors") or []
            if errs:
                self.error = f"{len(errs)} event(s) rejected: {errs[:1]}"
                return False
            self.events.clear()
            return True
        except urllib.error.HTTPError as e:
            detail = e.read()[:200].decode(errors="replace")
            self.error = (
                f"HTTP {e.code} {detail.strip()}"
                + ("  (Cloudflare Access blocks the API from outside — "
                   "open an SSH tunnel or run on the VPC)" if e.code == 403 else "")
            )
        except Exception as e:  # network, DNS, timeout
            self.error = f"{type(e).__name__}: {e}"
        return False
