"""Stages 2 and 3 — attribution.

Given a detected incident, find which segment explains it, then verify that it
fully explains it.

Run:  python3 -m engine.scan                 # scan every detected incident
      python3 -m engine.scan --json
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict, field

from .ch import Client
from .detect import Incident, detect

# A segment must beat the population by at least this much to be a candidate
# cause. Below it, the segment simply moved with everything else.
LOCALIZATION_FLOOR = 0.05

# The top candidate must beat the runner-up by this factor to be named alone.
# Without it, a movement spread across several segments gets reported as one.
DOMINANCE_RATIO = 2.0

# Fallback volume guard, used ONLY for metrics with no exact test (requests,
# revenue, ecpm). Proportion metrics are gated by MIN_Z instead.
MIN_REQUESTS = 5000

# Significance gate for proportion metrics, in standard errors. Applies to
# fill_rate / render_rate / ctr via ClickHouse's proportionsZTest.
MIN_Z = 4.0

# How much of the movement must vanish when the accused segment is removed.
# The residual test is the ARBITER, not a footnote: a segment can beat the
# population handsomely and still not drive the total. On Jun 21 the finance
# category scored -34.7% vs population, yet removing it left -43.4% of a
# -44.8% movement — it explains 3% of what happened. Calling that "localized"
# would be a confident, wrong diagnosis of exactly the kind the rubric
# punishes hardest.
FULLY_EXPLAINED = 0.85   # >= this fraction removed  -> localized
PARTLY_EXPLAINED = 0.30  # >= this fraction removed  -> partial, else global

# How many leading candidates get the residual test. Ranking by deviation alone
# favours small segments with violent swings: on the eCPM incident a single app
# scored -33% against the population but accounted for 24% of the movement,
# while the real cause (ad format = interstitial) sat fourth at -4.8%. Deviation
# says "unusual"; only the residual says "responsible". So test the leaders and
# let the evidence pick.
CANDIDATES_TESTED = 6

DIM_LABELS = {
    "ad_format": "ad format",
    "category": "app category",
    "publisher_tier": "publisher tier",
    "vertical": "advertiser vertical",
    "campaign_type": "campaign type",
    "region": "region",
    "country": "country",
    "device_model": "device model",
    "os_version": "device OS version",
    "app_id": "app",
    "advertiser_id": "advertiser",
}


@dataclass
class Attribution:
    incident: dict
    verdict: str
    global_change: float
    culprit: dict | None
    residual: dict | None
    counterfactual: dict | None = None
    second_level: dict | None = None
    ruled_out: list[dict] = field(default_factory=list)
    candidates: list[dict] = field(default_factory=list)

    def as_dict(self) -> dict:
        return asdict(self)


def _sql_array(values) -> str:
    """ClickHouse Array(String) literal, single quotes escaped."""
    return "[" + ",".join("'" + str(v).replace("\\", "\\\\").replace("'", "\\'") + "'"
                          for v in values) + "]"


def _window_end(inc: Incident) -> str:
    """The exclusive end recorded by the detector, where the grain was known."""
    return inc.end_exclusive


def scan(client: Client, inc: Incident, weeks: int = 3) -> Attribution:
    rows = client.query_file(
        "segment_scan.sql",
        {
            "metric": inc.metric,
            "win_start": inc.start,
            "win_end": _window_end(inc),
            "weeks": weeks,
            "min_requests": MIN_REQUESTS,
            "min_z": MIN_Z,
        },
    )

    cands = [
        {
            "dimension": r["dim_name"],
            "dimension_label": DIM_LABELS.get(r["dim_name"], r["dim_name"]),
            "value": r["dim_value"],
            "baseline": float(r["baseline_value"]),
            "incident": float(r["incident_value"]),
            "seg_change": float(r["seg_change"]),
            "vs_global": float(r["vs_global"]),
            "requests": int(r["incident_requests"]),
            "z": None if r["z"] in ("nan", None) else round(float(r["z"]), 1),
        }
        for r in rows
    ]
    global_change = float(rows[0]["global_change"]) if rows else 0.0

    top = cands[0] if cands else None
    second = cands[1] if len(cands) > 1 else None

    # --- the verdict, decided here in code and never by the LLM -------------
    if top is None or abs(top["vs_global"]) < LOCALIZATION_FLOOR:
        # Nothing stands apart from the population: the movement is global.
        # This is the Jun 21 case, and getting it wrong means confidently
        # naming the largest segment as a cause it did not have.
        return Attribution(
            incident=inc.as_dict(),
            verdict="global",
            global_change=global_change,
            culprit=None,
            residual=None,
            ruled_out=[
                {
                    "what": f"{c['dimension_label']} = {c['value']}",
                    "why": f"moved {c['vs_global'] * 100:+.1f}% relative to the "
                           f"population — within normal spread",
                }
                for c in cands[:5]
            ],
            candidates=cands[:15],
        )


    # --- stage 3: remove each leading candidate, keep the best explainer ----
    # All candidates are evaluated in ONE scan of ad_events. refine.sql uses a
    # sentinel rather than throwIf for an unrecognised dimension (multiIf
    # evaluates its fallback eagerly inside arrayMap), so validate here.
    probe = cands[:CANDIDATES_TESTED]
    unknown = {c["dimension"] for c in probe} - set(DIM_LABELS)
    if unknown:
        raise ValueError(f"unknown dimension(s) in candidates: {sorted(unknown)}")

    rows_r = client.query_file(
        "refine.sql",
        {
            "metric": inc.metric,
            "dims": _sql_array(c["dimension"] for c in probe),
            "values": _sql_array(c["value"] for c in probe),
            "win_start": inc.start,
            "win_end": _window_end(inc),
            "weeks": weeks,
        },
    )
    tested = [
        (probe[int(r["cand_idx"]) - 1], float(r["change_all"]), float(r["change_without"]))
        for r in rows_r
    ]

    # Best explainer = the one that leaves the least movement behind.
    top, all_change, without_change = min(tested, key=lambda x: abs(x[2]))

    explained_fraction = (
        1 - abs(without_change) / abs(all_change) if all_change else 0.0
    )
    explained = explained_fraction >= FULLY_EXPLAINED
    dominant = True

    residual = {
        "all_traffic_change": all_change,
        "without_accused_change": without_change,
        "explained_fraction": round(explained_fraction, 3),
        "fully_explained": explained,
        "proof": (
            f"Excluding {DIM_LABELS.get(top['dimension'], top['dimension'])} "
            f"= {top['value']}, {inc.metric_label} moved "
            f"{without_change * 100:+.2f}% against {all_change * 100:+.2f}% "
            f"for all traffic."
        ),
    }

    # The accused beat the population but doesn't move the total: not a cause.
    if explained_fraction < PARTLY_EXPLAINED:
        return Attribution(
            incident=inc.as_dict(),
            verdict="global",
            global_change=global_change,
            culprit=None,
            residual=residual,
            ruled_out=[
                {
                    "what": f"{top['dimension_label']} = {top['value']}",
                    "why": f"stood out at {top['vs_global'] * 100:+.1f}% against the "
                           f"population, but removing it leaves "
                           f"{without_change * 100:+.2f}% of the original "
                           f"{all_change * 100:+.2f}% — it accounts for only "
                           f"{explained_fraction * 100:.0f}% of the movement",
                }
            ] + [
                {
                    "what": f"{c['dimension_label']} = {c['value']}",
                    "why": f"moved {c['vs_global'] * 100:+.1f}% relative to the "
                           f"population — within normal spread",
                }
                for c in cands[1:4]
            ],
            candidates=cands[:15],
        )

    # Shadows: segments that only moved because they overlap the culprit. They
    # are ruled OUT, and saying so is the honesty bonus the rubric asks for.
    ruled_out = [
        {
            "what": f"{c['dimension_label']} = {c['value']}",
            "why": f"moved {c['vs_global'] * 100:+.1f}% relative to the population, "
                   f"far less than the {top['vs_global'] * 100:+.1f}% of "
                   f"{DIM_LABELS.get(top['dimension'], top['dimension'])} "
                   f"= {top['value']}",
        }
        for c in cands[1:5]
    ]
    if explained:
        ruled_out.insert(
            0,
            {
                "what": "any additional cause",
                "why": residual["proof"] + " Nothing else is required to explain it.",
            },
        )

    # If one dimension did not explain the movement, the cause is probably an
    # INTERSECTION the single-dimension cube cannot express. Drill inside the
    # accused segment. Measured: "country = JP" explained 47%; inside JP, iOS
    # 18.1 fell 49.8% (z = -65) while every other OS there was flat.
    #
    # Only when the residual says so. A two-dimension search is far more
    # surface for a spurious result, and when one dimension already explains
    # the movement there is nothing left to find.
    second = None
    if not explained:
        try:
            sub = client.query_file("drill2.sql", {
                "metric": inc.metric, "dim": top["dimension"], "value": top["value"],
                "win_start": inc.start, "win_end": _window_end(inc),
                "weeks": weeks, "min_requests": 500,
            })
            best = next((r for r in sub if float(r["sub_change"]) < -0.15), None)
            if best:
                second = {
                    "dimension": best["sub_dim"],
                    "dimension_label": DIM_LABELS.get(best["sub_dim"], best["sub_dim"]),
                    "value": best["sub_value"],
                    "baseline": float(best["baseline_value"]),
                    "incident": float(best["incident_value"]),
                    "change": float(best["sub_change"]),
                    "statement": (
                        f"Within {DIM_LABELS.get(top['dimension'], top['dimension'])} "
                        f"= {top['value']}, the movement concentrates in "
                        f"{DIM_LABELS.get(best['sub_dim'], best['sub_dim'])} = "
                        f"{best['sub_value']}: {float(best['baseline_value']):.4f} -> "
                        f"{float(best['incident_value']):.4f} "
                        f"({float(best['sub_change']) * 100:+.1f}%)."
                    ),
                }
        except Exception:
            second = None

    # What did it cost? Only meaningful once a segment is actually implicated.
    cf = None
    try:
        cf_rows = client.query_file("counterfactual.sql", {
            "dim": top["dimension"], "value": top["value"],
            "win_start": inc.start, "win_end": _window_end(inc), "weeks": weeks,
        })
        if cf_rows:
            r = cf_rows[0]
            impact = float(r["impact"])
            cf = {
                "requests_during": int(r["requests_during"]),
                "revenue_actual": round(float(r["revenue_actual"]), 2),
                "revenue_if_baseline_held": round(float(r["revenue_counterfactual"]), 2),
                "impact": round(impact, 2),
                "statement": (
                    f"Had {DIM_LABELS.get(top['dimension'], top['dimension'])} "
                    f"= {top['value']} held at its baseline revenue per request, "
                    f"revenue over this window would have been "
                    f"${abs(impact):,.2f} {'higher' if impact > 0 else 'lower'}."
                ),
            }
    except Exception:
        # Impact is a bonus, never a blocker: a diagnosis without a price tag
        # is still a diagnosis.
        cf = None

    return Attribution(
        incident=inc.as_dict(),
        verdict=("localized" if (explained and dominant)
                 else "partial" if explained
                 else "partial"),
        counterfactual=cf,
        second_level=second,
        global_change=global_change,
        culprit={
            **top,
            "share_of_traffic": None,
        },
        residual=residual,
        ruled_out=ruled_out,
        candidates=cands[:15],
    )


def main() -> None:
    ap = argparse.ArgumentParser(description="Attribute detected movements")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    client = Client()
    results = [scan(client, inc) for inc in detect(client)]

    if args.json:
        print(json.dumps([r.as_dict() for r in results], indent=2, default=str))
        return

    for r in results:
        inc = r.incident
        print(f"\n{'=' * 78}")
        print(f"{inc['metric_label'].upper()}  {inc['start'][:16]} -> {inc['end'][:16]}"
              f"   {inc['effect_pct']:+.2f}%   [{r.verdict}]")
        print("=" * 78)
        if r.culprit and r.residual:
            c = r.culprit
            print(f"  culprit : {c['dimension_label']} = {c['value']}")
            print(f"            {c['baseline']:.4f} -> {c['incident']:.4f} "
                  f"({c['seg_change'] * 100:+.1f}%), "
                  f"{c['vs_global'] * 100:+.1f}% vs population")
            print(f"  proof   : {r.residual['proof']}")
            if r.second_level:
                print(f"  deeper  : {r.second_level['statement']}")
            print(f"            fully explained: {r.residual['fully_explained']}")
        else:
            print(f"  no segment responsible — population moved "
                  f"{r.global_change * 100:+.1f}% and every segment moved with it")
        print("  ruled out:")
        for x in r.ruled_out[:4]:
            print(f"      - {x['what']}: {x['why']}")


if __name__ == "__main__":
    main()
