"""The cheap detection loop.

Runs the detector and records anything it has not already seen into
`detections`. Pure SQL underneath — no LLM, no attribution — so it is cheap
enough to run every minute.

That separation is the point. Detection runs constantly; the expensive
investigation (segment scan, refinement, narration, tracing) fires only when
this finds something. An alert over `detections` therefore needs no threshold
of its own: the baseline ladder and the robust z-score already decided what
counts as abnormal, per metric, without anyone hard-coding a segment.

    python3 -m engine.watch              record anything new
    python3 -m engine.watch --dry-run    show what would be recorded
    while true; do python3 -m engine.watch; sleep 60; done
"""

from __future__ import annotations

import argparse

from .ch import DB, Client
from .detect import detect


def _sql_str(v: object) -> str:
    return "'" + str(v).replace("\\", "\\\\").replace("'", "\\'") + "'"


def record(client: Client, dry_run: bool = False) -> list[dict]:
    incidents = detect(client)
    if not incidents:
        return []

    # Which of these have we already recorded? One round trip, not one per
    # incident. Identity is (metric, window_start, grain): the same movement
    # seen again on a later pass is the same movement.
    known = {
        (r["metric"], r["window_start"], r["grain"])
        for r in client.query(
            "SELECT metric, toString(window_start) AS window_start, grain "
            "FROM {db:Identifier}.detections"
        )
    }

    fresh = [
        i for i in incidents
        if (i.metric, i.start, i.grain) not in known
    ]
    if not fresh or dry_run:
        return [i.as_dict() for i in fresh]

    values = ",".join(
        "(now(), {m}, {ws}, {we}, {g}, {d}, {w}, {e}, {r}, {db})".format(
            m=_sql_str(i.metric), ws=_sql_str(i.start), we=_sql_str(i.end_exclusive),
            g=_sql_str(i.grain), d=_sql_str(i.direction), w=i.peak_wobbles,
            e=i.effect_pct, r=_sql_str(i.baseline_rung), db=_sql_str(DB),
        )
        for i in fresh
    )
    client.query(
        "INSERT INTO {db:Identifier}.detections "
        "(found_at, metric, window_start, window_end, grain, direction, "
        " peak_wobbles, effect_pct, baseline_rung, source_db) VALUES " + values
    )
    return [i.as_dict() for i in fresh]


def main() -> None:
    ap = argparse.ArgumentParser(description="Record new detections")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    client = Client()
    fresh = record(client, dry_run=args.dry_run)

    if not fresh:
        print("nothing new")
        return
    verb = "would record" if args.dry_run else "recorded"
    print(f"{verb} {len(fresh)} new detection(s):")
    for f in fresh:
        print(f"  {f['metric']:<12} {f['start'][:16]} -> {f['end'][:16]}  "
              f"{f['effect_pct']:+.2f}%  ({f['peak_wobbles']:+.1f} wobbles)  "
              f"[{f['grain']}]")


if __name__ == "__main__":
    main()
