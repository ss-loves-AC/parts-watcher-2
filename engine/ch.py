"""ClickHouse access.

Deliberately dependency-free: shells out to the standalone `clickhouse client`
binary and parses JSONEachRow. Nothing to pip-install at 3am, and the same
binary is already required to load the data.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

DEFAULT_ENV = Path.home() / ".config" / "clickhouse" / "clickathon.env"
DEFAULT_CLIENT = Path.home() / "Documents/projects/click/bin/clickhouse"
SQL_DIR = Path(__file__).resolve().parent.parent / "sql"

# Own database, not the shared one. See load/load.sh for why.
DB = os.environ.get("CH_DB", "pw")


def _load_env(env_file: Path) -> dict[str, str]:
    if not env_file.exists():
        raise SystemExit(f"missing credentials file: {env_file}")
    out = {}
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


class Client:
    def __init__(self, env_file: Path | None = None, binary: Path | None = None):
        # Environment first, file second. The CI runner and the deploy path
        # supply credentials as env vars and have no dotfile — insisting on the
        # file made the engine unrunnable anywhere but the laptop it was
        # written on.
        env: dict[str, str] = {}
        if not all(os.environ.get(k) for k in ("CH_HOST", "CH_USER", "CH_PASSWORD")):
            env = _load_env(Path(env_file or os.environ.get("CH_ENV", DEFAULT_ENV)))
        self.host = os.environ.get("CH_HOST") or env["CH_HOST"]
        self.user = os.environ.get("CH_USER") or env["CH_USER"]
        self.password = os.environ.get("CH_PASSWORD") or env["CH_PASSWORD"]
        self.binary = Path(binary or os.environ.get("CH_CLIENT", DEFAULT_CLIENT))
        if not self.binary.exists():
            raise SystemExit(f"missing clickhouse client: {self.binary}")
        # Every query this client runs, so a trace can show the actual SQL and
        # what it returned. "No trace, no credit" means a judge must be able to
        # check the working, and a filename plus a conclusion is not the
        # working — it is a claim about it.
        self.log: list[dict] = []

    def query(self, sql: str, params: dict[str, object] | None = None,
              name: str | None = None) -> list[dict]:
        """Run SQL, return rows as dicts.

        Values go through ClickHouse's own --param_ mechanism rather than string
        interpolation, so a parameter can never alter the shape of the query.
        """
        cmd = [
            str(self.binary), "client",
            "--host", self.host, "--port", "9440", "--secure",
            "--user", self.user, "--password", self.password,
            "--format", "JSONEachRow",
            "--query", sql,
        ]
        params = {"db": DB, **(params or {})}
        for key, value in params.items():
            cmd += [f"--param_{key}", str(value)]

        # stdin=DEVNULL is load-bearing for INSERT ... VALUES: given --query,
        # the client keeps reading stdin for more rows and blocks until EOF,
        # so an insert that should take milliseconds hangs until the timeout.
        t0 = time.time()
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180,
                              stdin=subprocess.DEVNULL)
        elapsed = round((time.time() - t0) * 1000)
        if proc.returncode != 0:
            self.log.append({"sql": sql, "params": params, "error": proc.stderr.strip()[:300]})
            raise RuntimeError(f"query failed:\n{proc.stderr.strip()}")
        rows = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
        self.log.append({
            "name": name or "inline",
            "sql": sql.strip(),
            "params": {k: str(v) for k, v in params.items()},
            "rows_returned": len(rows),
            "ms": elapsed,
            # First rows only — enough to see WHAT came back without turning
            # the trace into a data dump.
            "sample": rows[:5],
        })
        return rows

    def query_file(self, name: str, params: dict[str, object] | None = None) -> list[dict]:
        return self.query((SQL_DIR / name).read_text(), params, name=name)

    def since(self, mark: int) -> list[dict]:
        """Queries run since `mark` — used to attach SQL to a trace span."""
        return self.log[mark:]

    def mark(self) -> int:
        return len(self.log)

    def scalar(self, sql: str, params: dict[str, object] | None = None):
        rows = self.query(sql, params)
        return next(iter(rows[0].values())) if rows else None
