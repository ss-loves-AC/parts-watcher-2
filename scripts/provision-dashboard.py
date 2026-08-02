"""Create the HyperDX dashboard that answers "what broke, and why?".

A saved search is findable only if you know it exists and widen the time
picker. A dashboard is where someone actually looks first, so this is the
front door: one screen listing every anomaly with its cause.

    python3 scripts/provision-dashboard.py

Idempotent — the dashboard id is remembered in ClickHouse (pinned_views),
so re-running updates rather than adding another copy.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from engine.act import Actor          # noqa: E402
from engine.ch import Client          # noqa: E402

DASHBOARD_NAME = "RCA — what broke and why"

HEADER = """### Automated root-cause analysis

Every row below is a metric movement the detector found, **with the segment
responsible**. Nothing here was configured by hand — no thresholds per segment,
no named dimensions.

- **explains** — how much of the movement disappears when that segment is
  removed. `98%` means it is the cause. `0%` means nothing is: the movement was
  global and naming a segment would be a fabrication.
- **verdict** — `localized` one segment did it · `global` no segment did ·
  `partial` a segment is involved but is not the whole story.

_Set the time range to **Last 24 hours** or wider — findings are written when
the detector runs, not when the incident happened._
"""


def main() -> None:
    actor, client = Actor(), Client()
    if not actor.enabled:
        raise SystemExit(f"cannot reach the MCP: {actor.error}")

    det_source = actor.source_id("Detections")
    ad_source = actor.source_id("Ad Events")
    if not det_source:
        raise SystemExit("Detections source missing — run provision-clickstack.js first")

    tiles = [
        {
            "name": "About", "x": 0, "y": 0, "w": 24, "h": 4,
            "config": {"displayType": "markdown", "markdown": HEADER},
        },
        {
            # The list. `search` renders rows as they are, which is what a
            # human wants here — not a chart of a count.
            "name": "Anomalies and their causes", "x": 0, "y": 4, "w": 24, "h": 9,
            "config": {
                "displayType": "search",
                "sourceId": det_source,
                "where": "", "whereLanguage": "sql",
                # `diagnosis` last and widest: it is the deliverable the
                # brief names ("plain-language diagnosis"), and the columns
                # before it are the numbers that back it up.
                "select": ("found_at, metric, window_start, effect_pct, "
                           "verdict, cause, explained_pct, diagnosis"),
            },
        },
        {
            "name": "Localized — a segment was named", "x": 0, "y": 13, "w": 12, "h": 7,
            "config": {
                "displayType": "search", "sourceId": det_source,
                "where": "verdict = 'localized'", "whereLanguage": "sql",
                "select": "metric, window_start, effect_pct, cause, explained_pct, diagnosis",
            },
        },
        {
            # The result worth showing off: movements it refused to attribute.
            "name": "Global — correctly refused to blame anyone", "x": 12, "y": 13, "w": 12, "h": 7,
            "config": {
                "displayType": "search", "sourceId": det_source,
                "where": "verdict = 'global'", "whereLanguage": "sql",
                "select": "metric, window_start, effect_pct, cause, explained_pct, diagnosis",
            },
        },
    ]
    if ad_source:
        tiles.append({
            "name": "Unfilled ad requests (the underlying data)",
            "x": 0, "y": 20, "w": 24, "h": 7,
            "config": {
                "displayType": "search", "sourceId": ad_source,
                "where": "is_filled = 0", "whereLanguage": "sql",
                "select": "event_time, ad_format, category, country, os_version, device_model",
            },
        })

    args = {"name": DASHBOARD_NAME, "tiles": tiles, "tags": ["rca"]}

    prior = client.query(
        "SELECT search_id FROM {db:Identifier}.pinned_views "
        "WHERE name = {n:String} ORDER BY pinned_at DESC LIMIT 1",
        {"n": DASHBOARD_NAME})
    if prior:
        args["id"] = prior[0]["search_id"]

    r = actor._call("clickstack_save_dashboard", args)
    res = (r or {}).get("result", {})
    if not r or res.get("isError"):
        raise SystemExit(f"save_dashboard failed: {json.dumps(r)[:400]}")

    new_id = None
    for item in res.get("content", []):
        try:
            new_id = json.loads(item.get("text", "")).get("id") or new_id
        except Exception:
            pass
    if new_id and not prior:
        client.query(
            "INSERT INTO {db:Identifier}.pinned_views (name, search_id, pinned_at) "
            "VALUES ({n:String}, {i:String}, now())",
            {"n": DASHBOARD_NAME, "i": new_id})

    print(f"dashboard: {DASHBOARD_NAME}")
    print(f"tiles    : {len(tiles)}")
    print(f"url      : https://hyperdx.datagan.site/dashboards/{new_id or prior[0]['search_id']}")


if __name__ == "__main__":
    main()
