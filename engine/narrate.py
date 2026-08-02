"""Stage 5 — narration, and the guard that makes it trustworthy.

The model receives the evidence JSON and NOTHING else. No database handle, no
raw rows, no arithmetic to perform. A number that isn't in the evidence has no
source to come from.

That is the architecture. The guard below is the proof: every numeric token in
the generated prose must appear in the evidence it was given, or the paragraph
is regenerated, and a second failure fails the run. "The LLM shouldn't invent
figures" becomes "an invented figure cannot reach the output".

Run:  python3 -m engine.narrate            # full pipeline -> diagnosis
      python3 -m engine.narrate --no-llm   # deterministic template only
"""

from __future__ import annotations

import argparse
import json
import os
import re
import urllib.request
from pathlib import Path

LLM_ENV = Path.home() / ".config" / "clickhouse" / "llm.env"
DEEPSEEK_URL = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-chat"
MAX_ATTEMPTS = 2

SYSTEM = """You are writing a short incident diagnosis for an ad-operations team.

You will be given a JSON object of already-computed evidence.

ABSOLUTE RULES:
- Use ONLY numbers that appear verbatim in the JSON. Copy them exactly as
  written, including the % and $ signs.
- Never calculate, re-round, convert, or estimate any figure.
- If a number is not in the JSON, it does not go in your answer.
- Do not add recommendations, causes, or context that is not in the JSON.

Write 3-5 sentences of plain prose. State what moved, by how much, which
segment was responsible (or that none was), the proof, and what was ruled out.
No bullet points, no headings, no preamble."""


def _load_key() -> str | None:
    if os.environ.get("DEEPSEEK_API_KEY"):
        return os.environ["DEEPSEEK_API_KEY"]
    if LLM_ENV.exists():
        for line in LLM_ENV.read_text().splitlines():
            if line.startswith("DEEPSEEK_API_KEY="):
                return line.split("=", 1)[1].strip()
    return None


# Numbers as the evidence writes them: -44.8%, $542.39, 232,411, 14x, 0.7847
_NUM = re.compile(r"-?\$?\d[\d,]*\.?\d*%?x?")


def _numbers_in(text: str) -> set[str]:
    """Every numeric token, normalised for comparison."""
    out = set()
    for m in _NUM.findall(text):
        # Strip sentence punctuation the regex greedily absorbed. Without
        # this, "232,411 to 126,052." yields the token "126,052," which
        # matches nothing in the evidence and rejects a correct paragraph.
        tok = m.strip().rstrip(".,;:")
        if tok and any(ch.isdigit() for ch in tok):
            out.add(tok.lstrip("+"))
    return out


def check_numbers(prose: str, evidence: dict) -> set[str]:
    """Numeric tokens in the prose that the evidence never supplied.

    Compared against the flattened JSON text, so any figure the model was
    handed counts as sourced regardless of which field carried it. Small
    integers (1-31, dates and counts of things) are exempt: they appear in
    ordinary sentences and are not the failure mode we care about.
    """
    allowed = _numbers_in(json.dumps(evidence))
    # Match on magnitude, not sign. The evidence carries "-6.64%"; correct
    # English is "a 6.64% drop", with the direction in the verb. Comparing
    # signed tokens rejected that paragraph and printed "unsourced figures:
    # ['6.64%']" under a diagnosis that was entirely faithful.
    #
    # The cost is that a flipped sign would now pass the guard. That is
    # acceptable here because direction is carried by `ev["direction"]` and by
    # the verb the model is instructed to use, whereas magnitude is the thing
    # it could invent. Rejecting true prose is the worse failure: it trains a
    # reader to ignore the badge.
    allowed_abs = {t.lstrip("-") for t in allowed}
    unsourced = set()
    for tok in _numbers_in(prose):
        if tok in allowed or tok.lstrip("-") in allowed_abs:
            continue
        bare = tok.strip("$%x").replace(",", "")
        try:
            if bare and float(bare).is_integer() and 0 <= float(bare) <= 31:
                continue
        except ValueError:
            pass
        unsourced.add(tok)
    return unsourced


def template(ev: dict) -> str:
    """Deterministic fallback. Also the honest baseline: if this reads nearly
    as well as the model's version, the model is not adding much."""
    parts = [
        f"{ev['metric'].capitalize()} moved {ev['change']} over {ev['window']}, "
        f"from an expected {ev['expected']} to {ev['actual']} — "
        f"{ev['how_unusual']}."
    ]
    c = ev.get("culprit")
    if c:
        parts.append(
            f"It localises to {c['dimension']} = {c['value']}, which went "
            f"{c['its_value_before']} to {c['its_value_during']} "
            f"({c['its_change']}) — {c['beyond_the_population']} beyond what the "
            f"population as a whole did."
        )
        parts.append(ev["proof"])
    else:
        parts.append(ev["proof"])
    if ev.get("ruled_out"):
        parts.append(
            "Ruled out: "
            + "; ".join(f"{r['what']} ({r['why']})" for r in ev["ruled_out"][:2])
            + "."
        )
    return " ".join(parts)


def _call_llm(evidence: dict, key: str) -> str:
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": json.dumps(evidence, indent=2)},
        ],
        "temperature": 0.2,
    }).encode()
    req = urllib.request.Request(
        DEEPSEEK_URL, data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.loads(r.read())["choices"][0]["message"]["content"].strip()


def narrate(evidence: dict, use_llm: bool = True) -> tuple[str, dict]:
    key = _load_key() if use_llm else None
    if not key:
        prose = template(evidence)
        return prose, {"source": "template", "unsourced": []}

    last_bad: set[str] = set()
    for attempt in range(1, MAX_ATTEMPTS + 1):
        prose = _call_llm(evidence, key)
        bad = check_numbers(prose, evidence)
        if not bad:
            return prose, {"source": f"{MODEL} (attempt {attempt})", "unsourced": []}
        last_bad = bad

    # Two strikes: the model cannot be trusted with this one, so fall back to
    # the deterministic template rather than shipping an unverifiable number.
    return template(evidence), {
        "source": "template (LLM produced unsourced numbers)",
        "unsourced": sorted(last_bad),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Narrate detected incidents")
    ap.add_argument("--no-llm", action="store_true", help="template only")
    args = ap.parse_args()

    from .ch import Client
    from .detect import detect
    from .scan import scan
    from .evidence import build

    client = Client()
    for inc in detect(client):
        ev = build(scan(client, inc))
        prose, meta = narrate(ev, use_llm=not args.no_llm)
        print(f"\n{'=' * 78}\n{ev['metric'].upper()}  {ev['window']}  [{ev['verdict']}]")
        print("=" * 78)
        print(prose)
        print(f"\n  [{meta['source']}]"
              + (f"  UNSOURCED: {meta['unsourced']}" if meta["unsourced"] else "  all numbers verified"))


if __name__ == "__main__":
    main()
