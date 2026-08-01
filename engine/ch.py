"""ClickHouse access.

Deliberately dependency-free: shells out to the standalone `clickhouse client`
binary and parses JSONEachRow. Nothing to pip-install at 3am, and the same
binary is already required to load the data.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

DEFAULT_ENV = Path.home() / ".config" / "clickhouse" / "clickathon.env"
DEFAULT_CLIENT = Path.home() / "Documents/projects/click/bin/clickhouse"
SQL_DIR = Path(__file__).resolve().parent.parent / "sql"


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
        env = _load_env(Path(env_file or os.environ.get("CH_ENV", DEFAULT_ENV)))
        self.host = env["CH_HOST"]
        self.user = env["CH_USER"]
        self.password = env["CH_PASSWORD"]
        self.binary = Path(binary or os.environ.get("CH_CLIENT", DEFAULT_CLIENT))
        if not self.binary.exists():
            raise SystemExit(f"missing clickhouse client: {self.binary}")

    def query(self, sql: str, params: dict[str, object] | None = None) -> list[dict]:
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
        for key, value in (params or {}).items():
            cmd += [f"--param_{key}", str(value)]

        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        if proc.returncode != 0:
            raise RuntimeError(f"query failed:\n{proc.stderr.strip()}")
        return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]

    def query_file(self, name: str, params: dict[str, object] | None = None) -> list[dict]:
        return self.query((SQL_DIR / name).read_text(), params)

    def scalar(self, sql: str, params: dict[str, object] | None = None):
        rows = self.query(sql, params)
        return next(iter(rows[0].values())) if rows else None
