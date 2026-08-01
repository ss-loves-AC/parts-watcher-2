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
    # grain_hours, label, min_hist, merge_gap_hours
    (1,  "hourly", 3, 6),
    (24, "daily",  2, 48),
)

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


def choose_baseline(span_days: float) -> tuple[int, str]:
    """The baseline ladder from docs/DESIGN.md.

    A 'fresh slice of the same universe' may be far shorter than the 5 weeks we
    developed against. Rather than returning nothing, the baseline degrades in
    defined steps — and which step fired is reported, so a fallback is visible
    in the diagnosis rather than hidden.
    """
    if span_days >= 22:
        return 3, "rung1_same_weekday_3w"
    if span_days >= 15:
        return 2, "rung2_same_weekday_2w"
    if span_days >= 8:
        return 1, "rung2_same_weekday_1w"
    # Rungs 3-4 (carry the seasonal shape from the reference dataset, then
    # within-file same-hour-of-day) are specified in DESIGN.md but NOT yet
    # implemented. Fail loudly rather than silently reporting "no anomalies",
    # which would look identical to a clean dataset.
    raise SystemExit(
        f"data spans only {span_days:.1f} days: needs baseline ladder rung 3+, "
        "which is not implemented yet"
    )


def detect(client: Client, threshold: float = THRESHOLD) -> list[Incident]:
    span_days = float(
        client.scalar(
            "SELECT dateDiff('hour', min(bucket), max(bucket)) / 24.0 "
            "FROM rca.segment_cube WHERE dim_name = '__total__'"
        )
    )
    weeks, rung = choose_baseline(span_days)

    # Pass 1: find anomalous days with an uncleaned baseline.
    first: list[Incident] = []
    for grain_hours, grain_label, min_hist, merge_gap in GRAINS:
        first += _detect_at_grain(
            client, weeks, rung, threshold, grain_hours, grain_label,
            min_hist, merge_gap, excl_dates=[],
        )

    # Pass 2: re-detect with those days barred from serving as history, so a
    # real incident cannot make the following weeks look anomalous.
    excl = sorted({
        d for inc in first
        for d in _dates_between(inc.start, inc.end)
    })

    incidents: list[Incident] = []
    for grain_hours, grain_label, min_hist, merge_gap in GRAINS:
        incidents += _detect_at_grain(
            client, weeks, rung, threshold, grain_hours, grain_label,
            min_hist, merge_gap, excl_dates=excl,
        )

    incidents = _dedupe(incidents)
    incidents.sort(key=lambda i: abs(i.peak_wobbles), reverse=True)
    return incidents


def _dates_between(start: str, end: str) -> list[str]:
    d0 = datetime.fromisoformat(start).date()
    d1 = datetime.fromisoformat(end).date()
    return [(d0 + timedelta(days=n)).isoformat() for n in range((d1 - d0).days + 1)]


def _detect_at_grain(
    client: Client, weeks: int, rung: str, threshold: float,
    grain_hours: int, grain_label: str, min_hist: int, merge_gap: int,
    excl_dates: list[str],
) -> list[Incident]:
    rows = client.query_file(
        "detect.sql",
        {
            "grain_hours": grain_hours,
            "weeks": weeks,
            "min_hist": min_hist,
            "threshold": threshold,
            "min_effect": MIN_EFFECT,
            "excl_dates": "[" + ",".join(f"'{d}'" for d in excl_dates) + "]",
        },
    )

    by_metric: dict[str, list[dict]] = {}
    for r in rows:
        by_metric.setdefault(r["metric"], []).append(r)

    incidents: list[Incident] = []
    for metric, hits in by_metric.items():
        hits.sort(key=lambda r: r["bucket"])
        run: list[dict] = []

        def flush(run: list[dict]) -> None:
            # A single daily bucket is already a day of evidence; a single hour
            # is not.
            if grain_hours == 1 and len(run) < MIN_HOURS:
                return
            peak = max(run, key=lambda r: abs(float(r["wobbles"])))
            mean_expected = sum(float(r["expected"]) for r in run) / len(run)
            mean_actual = sum(float(r["actual"]) for r in run) / len(run)
            incidents.append(
                Incident(
                    metric=metric,
                    metric_label=METRIC_LABELS.get(metric, metric),
                    start=run[0]["bucket"],
                    end=run[-1]["bucket"],
                    # Exclusive end recorded here, where the grain is known.
                    # Inferring it later from a merged grain label produced a
                    # 47-hour window for a 24-hour incident and diluted the
                    # signal until the culprit stopped standing out.
                    end_exclusive=(
                        datetime.fromisoformat(run[-1]["bucket"])
                        + timedelta(hours=grain_hours)
                    ).strftime("%Y-%m-%d %H:%M:%S"),
                    hours_flagged=len(run),
                    # Derived from the values actually reported, not from the
                    # peak hour, so direction can never contradict the numbers
                    # printed beside it.
                    direction="down" if mean_actual < mean_expected else "up",
                    peak_wobbles=round(float(peak["wobbles"]), 1),
                    approx_expected=mean_expected,
                    approx_actual=mean_actual,
                    baseline_rung=rung,
                    grain=grain_label,
                    effect_pct=round(
                        sum(float(r["effect"]) for r in run) / len(run) * 100, 2
                    ),
                )
            )

        for row in hits:
            t = datetime.fromisoformat(row["bucket"])
            if run and t - datetime.fromisoformat(run[-1]["bucket"]) > timedelta(
                hours=merge_gap
            ):
                flush(run)
                run = []
            run.append(row)
        flush(run)

    return incidents


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
            clash.grain = f"{clash.grain}+{inc.grain}"
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
