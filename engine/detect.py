"""Stage 1 — detection.

Finds *when* a metric moved. Never *who* caused it; that's the segment scan.

Run:  python3 -m engine.detect            # human-readable
      python3 -m engine.detect --json     # machine-readable
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta

from .ch import Client

# A movement is reported past this many wobbles. Tuned toward precision: the
# rubric penalises crying wolf, and a confident wrong answer costs more than a
# quiet miss.
THRESHOLD = 4.0

# Flagged hours this far apart or closer are one incident. Six hours bridges a
# quiet overnight stretch inside a multi-day movement without welding two
# genuinely separate incidents together.
MERGE_GAP_HOURS = 6

# Fewer flagged hours than this is treated as noise rather than an incident.
MIN_HOURS = 2

# A movement smaller than this fraction of baseline is not worth reporting even
# when statistically undeniable. The weakest planted movement is ~2.5%, so 1%
# keeps real incidents while discarding trend wobble.
MIN_EFFECT = 0.01

# Detection runs at both scales and the results are merged. A sharp one-day
# collapse is obvious hourly; a shallow multi-day drift is only obvious daily.
# Neither grain alone finds all four planted movements.
GRAINS = (
    # grain_hours, label, preferred_min_hist, merge_gap_hours
    (1,  "hourly", 3, 6),
    (24, "daily",  2, 48),
)


def _min_hist(grain_hours: int, lags: int, preferred: int) -> int:
    """How many historical samples to demand, given how many actually exist.

    A fixed requirement silently kills a whole grain on a short slice. Found by
    the holdout rehearsal: at weeks=1 the daily grain offers exactly ONE sample
    but demanded two, so daily detection returned nothing at all — and daily is
    what catches slow multi-day drifts. No error, no warning, just silence,
    which is indistinguishable from a clean dataset.

    Hourly draws 3 samples per week back (the hour either side); daily draws 1.
    """
    available = 3 * lags if grain_hours == 1 else lags
    return max(1, min(preferred, available))

METRIC_LABELS = {
    "requests": "request volume",
    "fill_rate": "fill rate",
    "render_rate": "render rate",
    "ctr": "click-through rate",
    "ecpm": "eCPM",
    "revenue": "revenue",
}


@dataclass
class Incident:
    metric: str
    metric_label: str
    start: str
    end: str
    end_exclusive: str
    hours_flagged: int
    direction: str
    peak_wobbles: float
    approx_expected: float
    approx_actual: float
    baseline_rung: str
    grain: str
    effect_pct: float

    def as_dict(self) -> dict:
        return asdict(self)


# The baseline ladder: (min span in days, lags, period_hours, name).
# Ordered strongest first; the first rung the data can support wins.
LADDER = (
    (22, 3, 168, "rung1_same_weekday_3w"),
    (15, 2, 168, "rung2_same_weekday_2w"),
    (8,  1, 168, "rung3_same_weekday_1w"),
    # Below a week there is no same-weekday history at all, so fall back to
    # the same hour on preceding DAYS. Weaker by construction — it cannot
    # distinguish a Sunday from a Tuesday, and weekends run ~18% below
    # weekdays — but a weaker answer that says so beats no answer.
    (4,  3,  24, "rung4_same_hour_3d"),
    (2,  1,  24, "rung4_same_hour_1d"),
)


def choose_baseline(span_days: float) -> tuple[int, int, str]:
    """Pick the strongest baseline the data can actually support.

    A 'fresh slice of the same universe' may be far shorter than the 5 weeks
    we developed against. The baseline degrades in defined steps rather than
    failing, and which step fired is carried into the diagnosis — a fallback
    should be visible, not hidden.
    """
    for min_span, lags, period, name in LADDER:
        if span_days >= min_span:
            return lags, period, name
    raise SystemExit(
        f"data spans only {span_days:.1f} days — under two, no baseline of any "
        "kind can be formed"
    )


def detect(client: Client, threshold: float = THRESHOLD,
           as_of: str | None = None) -> list[Incident]:
    if as_of is None:
        as_of = str(client.scalar(
            "SELECT addHours(max(bucket), 1) FROM {db:Identifier}.segment_cube"
        ))
    span_days = float(
        client.scalar(
            "SELECT dateDiff('hour', min(bucket), max(bucket)) / 24.0 "
            "FROM {db:Identifier}.segment_cube "
            "WHERE dim_name = '__total__' AND bucket < {as_of:DateTime}",
            {"as_of": as_of},
        )
    )
    lags, period_hours, rung = choose_baseline(span_days)

    # Pass 1: find anomalous days with an uncleaned baseline.
    first: list[Incident] = []
    for grain_hours, grain_label, preferred, merge_gap in GRAINS:
        first += _detect_at_grain(
            client, lags, period_hours, rung, threshold, grain_hours,
            grain_label, _min_hist(grain_hours, lags, preferred), merge_gap,
            excl_dates=[], as_of=as_of,
        )

    # Pass 2: re-detect with those days barred from serving as history, so a
    # real incident cannot make the following weeks look anomalous.
    excl = sorted({
        d for inc in first
        for d in _dates_between(inc.start, inc.end)
    })

    incidents: list[Incident] = []
    for grain_hours, grain_label, preferred, merge_gap in GRAINS:
        incidents += _detect_at_grain(
            client, lags, period_hours, rung, threshold, grain_hours,
            grain_label, _min_hist(grain_hours, lags, preferred), merge_gap,
            excl_dates=excl, as_of=as_of,
        )

    incidents = _dedupe(incidents)
    incidents.sort(key=lambda i: abs(i.peak_wobbles), reverse=True)
    return incidents


def _dates_between(start: str, end: str) -> list[str]:
    d0 = datetime.fromisoformat(start).date()
    d1 = datetime.fromisoformat(end).date()
    return [(d0 + timedelta(days=n)).isoformat() for n in range((d1 - d0).days + 1)]


def _detect_at_grain(
    client: Client, lags: int, period_hours: int, rung: str, threshold: float,
    grain_hours: int, grain_label: str, min_hist: int, merge_gap: int,
    excl_dates: list[str], as_of: str,
) -> list[Incident]:
    rows = client.query_file(
        "detect.sql",
        {
            "grain_hours": grain_hours,
            "lags": lags,
            "period_hours": period_hours,
            "min_hist": min_hist,
            "threshold": threshold,
            "min_effect": MIN_EFFECT,
            "excl_dates": "[" + ",".join(f"'{d}'" for d in excl_dates) + "]",
            "as_of": as_of,
            "merge_gap": merge_gap,
            # A single flagged hour is noise; a single flagged day is already a
            # day of evidence.
            "min_buckets": MIN_HOURS if grain_hours == 1 else 1,
        },
    )

    # The query now returns finished incidents — grouping contiguous buckets
    # into islands is gaps-and-islands SQL, not a Python loop.
    return [
        Incident(
            metric=r["metric"],
            metric_label=METRIC_LABELS.get(r["metric"], r["metric"]),
            start=r["start"],
            end=r["end"],
            end_exclusive=r["end_exclusive"],
            hours_flagged=int(r["buckets_flagged"]),
            direction=r["direction"],
            peak_wobbles=round(float(r["peak_wobbles"]), 1),
            approx_expected=float(r["mean_expected"]),
            approx_actual=float(r["mean_actual"]),
            baseline_rung=rung,
            grain=grain_label,
            effect_pct=round(float(r["mean_effect"]) * 100, 2),
        )
        for r in rows
    ]


def _dedupe(incidents: list[Incident]) -> list[Incident]:
    """One real movement seen at two grains is one incident, not two.

    Overlapping windows on the same metric collapse to the more significant
    detection; the surviving record keeps the wider window so the segment scan
    gets the full extent of the movement.
    """
    out: list[Incident] = []
    for inc in sorted(incidents, key=lambda i: abs(i.peak_wobbles), reverse=True):
        clash = None
        for kept in out:
            if kept.metric == inc.metric and inc.start <= kept.end and kept.start <= inc.end:
                clash = kept
                break
        if clash is None:
            out.append(inc)
        else:
            clash.start = min(clash.start, inc.start)
            clash.end = max(clash.end, inc.end)
            clash.end_exclusive = max(clash.end_exclusive, inc.end_exclusive)
            # Merge grain labels as a SET: repeated dedupe passes otherwise
            # accumulate 'daily+hourly+hourly+hourly'.
            clash.grain = "+".join(
                dict.fromkeys(clash.grain.split("+") + inc.grain.split("+")))
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Detect metric movements")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--threshold", type=float, default=THRESHOLD)
    args = ap.parse_args()

    incidents = detect(Client(), args.threshold)

    if args.json:
        print(json.dumps([i.as_dict() for i in incidents], indent=2))
        return

    if not incidents:
        print("no movements past threshold")
        return

    print(f"{len(incidents)} candidate movement(s), most significant first:\n")
    print(f"{'metric':<12} {'window':<34} {'dir':<5} {'wobbles':>8} {'effect%':>8}"
          f" {'expected':>10} {'actual':>10}  grain")
    print("-" * 104)
    for i in incidents:
        print(
            f"{i.metric:<12} {i.start[:16]} -> {i.end[:16]} {i.direction:<5}"
            f" {i.peak_wobbles:>8.1f} {i.effect_pct:>8.2f}"
            f" {i.approx_expected:>10.4f} {i.approx_actual:>10.4f}  {i.grain}"
        )
    print(f"\nbaseline: {incidents[0].baseline_rung}")


if __name__ == "__main__":
    main()
