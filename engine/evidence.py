"""Stage 4 — the evidence contract.

Turns an Attribution into the JSON the narrator is allowed to see.

**Every value here is a finished phrase, not a number to be manipulated.**
The narrator's entire job is to read fields out; it never computes, compares,
rounds or infers. That is not a request in a prompt — it is the reason this
module exists. A figure that isn't in this JSON has no source to come from, so
a fabricated number becomes structurally impossible rather than discouraged.

Three rules the output follows:
  1. Percentages are pre-formatted strings. The narrator copies "-44.8%"
     instead of rounding -0.44797 and getting it subtly wrong.
  2. Dimensions carry human names ("device OS version", not os_version), so
     the narrator is never inventing readable labels.
  3. ruled_out is populated by the engine, because the scan tested those
     segments anyway. The honesty bonus is a byproduct, not extra work.
"""

from __future__ import annotations

import json
from datetime import datetime

from .scan import Attribution

# Metric formatting: how many decimals, and whether it reads as a percentage.
_FORMATS = {
    "fill_rate": ("pct", 1),
    "render_rate": ("pct", 1),
    "ctr": ("pct", 2),
    "ecpm": ("money", 3),
    "revenue": ("money", 2),
    "requests": ("count", 0),
}


def _fmt(metric: str, value: float) -> str:
    kind, dp = _FORMATS.get(metric, ("num", 2))
    if kind == "pct":
        return f"{value * 100:.{dp}f}%"
    if kind == "money":
        return f"${value:,.{dp}f}"
    if kind == "count":
        return f"{value:,.0f}"
    return f"{value:.{dp}f}"


def _pct(x: float, dp: int = 1) -> str:
    return f"{x * 100:+.{dp}f}%"


def _window(start: str, end_exclusive: str) -> str:
    a = datetime.fromisoformat(start)
    b = datetime.fromisoformat(end_exclusive)
    if (b - a).days >= 1 and a.hour == 0 and b.hour == 0:
        last = b.replace(hour=0) - (b - b)  # end is exclusive
        days = (b - a).days
        if days == 1:
            return a.strftime("%b %-d")
        end_day = (b.toordinal() - 1)
        return f"{a.strftime('%b %-d')}–{datetime.fromordinal(end_day).strftime('%b %-d')}"
    return f"{a.strftime('%b %-d %H:%M')} to {b.strftime('%b %-d %H:%M')}"


def build(att: Attribution) -> dict:
    inc = att.incident
    metric = inc["metric"]

    ev: dict = {
        "metric": inc["metric_label"],
        "window": _window(inc["start"], inc["end_exclusive"]),
        "expected": _fmt(metric, inc["approx_expected"]),
        "actual": _fmt(metric, inc["approx_actual"]),
        "direction": inc["direction"],
        "change": f"{inc['effect_pct']:+.2f}%",
        "how_unusual": f"{abs(inc['peak_wobbles']):.0f}x larger than this metric's "
                       f"normal movement",
        "verdict": att.verdict,
        # Which rung of the baseline ladder fired. Stated so a fallback is
        # visible in the diagnosis rather than hidden.
        "baseline": inc["baseline_rung"],
        "detected_at_grain": inc["grain"],
    }

    if att.culprit and att.residual:
        c = att.culprit
        ev["culprit"] = {
            "dimension": c["dimension_label"],
            "value": c["value"],
            "its_value_before": _fmt(metric, c["baseline"]),
            "its_value_during": _fmt(metric, c["incident"]),
            "its_change": _pct(c["seg_change"]),
            "vs_everything_else": _pct(c["vs_global"]),
            "evidence_strength": (
                f"{abs(c['z']):.0f} standard errors" if c.get("z") is not None
                else "not applicable to this metric"
            ),
        }
        ev["proof"] = att.residual["proof"]
        ev["fully_explained"] = att.residual["fully_explained"]
        ev["share_of_movement_explained"] = (
            f"{att.residual['explained_fraction'] * 100:.0f}%"
        )
        if att.counterfactual:
            ev["cost_of_the_incident"] = att.counterfactual["statement"]
    else:
        ev["culprit"] = None
        ev["proof"] = (
            f"Every segment moved with the population "
            f"({_pct(att.global_change)}); none stands apart. "
            f"No single segment is responsible."
        )

    ev["ruled_out"] = att.ruled_out
    return ev


def build_all(atts: list[Attribution]) -> list[dict]:
    return [build(a) for a in atts]


def main() -> None:
    from .ch import Client
    from .detect import detect
    from .scan import scan

    client = Client()
    atts = [scan(client, i) for i in detect(client)]
    print(json.dumps(build_all(atts), indent=2))


if __name__ == "__main__":
    main()
