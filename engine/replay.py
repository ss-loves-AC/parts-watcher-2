"""Replay — watch anomalies surface as they would have, live.

Steps an `as_of` cutoff forward through the timeline. At each step the detector
sees only data up to that moment, exactly as a streaming system would, and we
record when each incident first becomes detectable.

That turns time-to-detect into a reportable number: "caught 7 hours in, while
it was still happening" is a different claim from "found it afterwards", and it
is the difference between an alerting system and a reporting one.

It is also a correctness test. The batch detector estimates its noise scale
across the WHOLE series, including buckets after the row being scored, and its
second pass excludes anomalies found anywhere in the timeline. Retrospectively
that is fine. Live it is impossible. Replay is what measures whether detection
quality survives without that lookahead — better to learn it here than in front
of judges.

Run:  python3 -m engine.replay --from 2026-06-20 --to 2026-06-26 --step 6
"""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta

from .ch import Client
from .detect import detect


def _fmt(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def replay(
    client: Client,
    start: datetime,
    end: datetime,
    step_hours: int,
    quiet: bool = False,
) -> dict[tuple[str, str], dict]:
    """Return, per incident, the moment it first cleared the threshold."""
    first_seen: dict[tuple[str, str], dict] = {}
    t = start
    while t <= end:
        as_of = _fmt(t)
        try:
            incidents = detect(client, as_of=as_of)
        except SystemExit as e:  # not enough history yet for the ladder
            if not quiet:
                print(f"{as_of}   (skipped: {e})")
            t += timedelta(hours=step_hours)
            continue

        new = []
        for inc in incidents:
            # Key on metric + start: the same incident seen at successive
            # cutoffs is one detection, not many.
            key = (inc.metric, inc.start)
            if key not in first_seen:
                began = datetime.fromisoformat(inc.start)
                first_seen[key] = {
                    "metric": inc.metric_label,
                    "began": inc.start,
                    "detected_at": as_of,
                    "latency_h": round((t - began).total_seconds() / 3600, 1),
                    "wobbles": inc.peak_wobbles,
                    "effect_pct": inc.effect_pct,
                }
                new.append(first_seen[key])

        if not quiet:
            if new:
                for n in new:
                    print(f"{as_of}   *** DETECTED  {n['metric']}  "
                          f"{n['effect_pct']:+.2f}%  ({n['wobbles']:+.1f} wobbles)"
                          f"  — began {n['began'][:16]}, {n['latency_h']:.0f}h earlier")
            else:
                print(f"{as_of}   nothing new  ({len(incidents)} known)")
        t += timedelta(hours=step_hours)

    return first_seen


def main() -> None:
    ap = argparse.ArgumentParser(description="Replay the timeline as if live")
    ap.add_argument("--from", dest="start", required=True, help="YYYY-MM-DD[ HH:MM]")
    ap.add_argument("--to", dest="end", required=True)
    ap.add_argument("--step", type=int, default=6, help="hours between cutoffs")
    ap.add_argument("--quiet", action="store_true", help="summary only")
    args = ap.parse_args()

    def parse(s: str) -> datetime:
        return datetime.fromisoformat(s if " " in s or "T" in s else s + " 00:00:00")

    client = Client()
    seen = replay(client, parse(args.start), parse(args.end), args.step, args.quiet)

    print(f"\n{'=' * 74}\nTIME TO DETECT\n{'=' * 74}")
    if not seen:
        print("  nothing detected in this window")
        return
    print(f"{'metric':<16}{'began':<18}{'detected':<18}{'latency':>9}")
    for r in sorted(seen.values(), key=lambda r: r["detected_at"]):
        print(f"{r['metric']:<16}{r['began'][:16]:<18}{r['detected_at'][:16]:<18}"
              f"{r['latency_h']:>7.0f}h")


if __name__ == "__main__":
    main()
