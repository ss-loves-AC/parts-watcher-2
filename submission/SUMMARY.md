# From alert to answer — solution summary

**A metric moves. In under a minute the system says which segment did it, proves
it, states what it ruled out, and shows the SQL it used.**

## How it works

ClickHouse does the analysis; the LLM only writes the sentence.

`ad_events` is denormalised at load, and a materialized view fans every event
into a cube keyed by `(hour, dim_name, dim_value)` — **one query scans all
twelve dimensions** in 69 ms.

Detection compares each metric to the same weekday three weeks back, scored
against its normal movement — weekend seasonality cancels by construction.
It runs hourly *and* daily, so a slow eCPM drift invisible per hour still
shows up per day.

Attribution asks three questions. **Is it real?** ClickHouse's native
`proportionsZTest`: Android 15 scores z = −187 against a next-best of −52.
**Is it distinctive?** Measured against the population's change, not its own
size. **Is it responsible?** Remove each candidate and remeasure; whichever
leaves least behind is the cause; only the third can name a culprit. When one
dimension doesn't explain it, it drills inside: the Jun 29 drop looks like
`country = JP`; the truth is **JP × iOS 18.1** (0.787 → 0.394).

## Why the numbers can be trusted

The model receives a JSON of finished strings — no database handle, no rows,
no arithmetic. A figure not in that JSON has nowhere to come from, and every
numeric token in the prose is checked back against it; two failures and a
deterministic template ships instead. Each trace carries **the SQL actually
executed, its parameters, rows returned and elapsed time** — so a judge can
check the working, not read a claim about it.

Ranking by absolute delta on Jun 21 would name `banner` — confidently,
wrongly. Declining to localize (**global — no segment responsible**) is the
hardest result to produce and the easiest to get wrong.

## It closes the loop

The detector writes findings to a `detections` table; the investigation
writes the cause back onto the same row. HyperDX alerts on "did it find
anything?" — threshold zero, no tuned number — waking a self-hosted runner
that pins the culprit back into HyperDX. Proven on `country = JP`, absent
from any config.

## Results

Four planted movements, four found, zero false positives, no weekend
flagged. Replay shows 6-hour time-to-detect. Twelve regression tests, proven
to fail, not merely to pass.

**On the sealed unseen incident**, zero recalibration. It ships regenerated
dimensions — same IDs, new values — so we measured the two mappings before
trusting either: agreement 0.126 against chance 0.125, a pure reshuffle. Each
era keeps its own attribution; the proof is that all three known incidents
reproduce unchanged. Three new movements: fill rate → **iOS
17.5** (78.6% → 47.7%), eCPM → **iPhone 14**, and a Jul 9 revenue drop called
**global** — its strongest candidate departed the population by +116% and was
still rejected, because removing it does not shrink the movement.

**ClickHouse Cloud · ClickStack · Langfuse · LibreChat**
