# From alert to answer — solution summary

**A metric moves. In under a minute the system says which segment did it, proves
it, states what it ruled out, and shows its working.**

## How it works

ClickHouse does the analysis; the LLM only writes the sentence.

`ad_events` is denormalised at load so the drill-down never joins. A
materialized view fans every event into a cube keyed by `(hour, dim_name,
dim_value)`, so **one parameterised query scans all twelve dimensions** —
adding a dimension is one line, not a new table.

Detection compares each metric against the same weekday three weeks back and
scores it against how much that metric normally moves (median/MAD). Weekend
seasonality cancels by construction. Detection runs at hourly *and* daily
grain: the eCPM incident is −2.4% across four days, invisible per hour and
obvious per day.

Attribution asks three separate questions. **Is it real?** ClickHouse's native
`proportionsZTest` — Android 15 scores z = −187 against a next-best of −52.
**Is it distinctive?** Each segment's change measured against the population's.
**Is it responsible?** Remove each candidate and remeasure; whichever leaves
least behind is the cause. Only the third can name a culprit — a segment can
beat the population handsomely and still drive nothing.

When one dimension doesn't explain the movement, it drills inside it. The
Jun 29 fill drop looks like `country = JP`; the truth is **JP × iOS 18.1**
(0.787 → 0.394). Neither dimension alone is the answer.

## Why the numbers can be trusted

The model receives a JSON of finished strings — no database handle, no raw
rows, no arithmetic. A figure not in that JSON has no source to come from. Then
every numeric token in the prose is checked back against the evidence; two
failures and a deterministic template ships instead. Hallucination isn't
discouraged, it's structurally impossible — and verified.

## Knowing when to say nothing

On Jun 21 every segment fell ~45% together. Ranking by absolute delta names
`banner` with total confidence. Our system reports **"global — no segment
responsible"**, because no segment stands clear of the population. Declining to
localise is the hardest result to produce and the easiest to get wrong.

## It closes the loop

The detector writes findings to a `detections` table. HyperDX alerts on *"did
the detector find anything?"* — threshold zero, no tuned number, no hard-coded
segment. That fires a webhook to GitHub, which wakes a self-hosted runner,
which investigates and pins the culprit back into HyperDX as a saved view.
Proven end to end on `country = JP`, which appears nowhere in any config.

Every investigation is one Langfuse trace, stages nested inside it.

## Results

All four planted movements found, zero false positives, none of the ten
weekends flagged. Full report in 20 seconds; the 12-dimension sweep in 69 ms.
Replay shows a 6-hour time-to-detect on the sharp incidents.

Twelve regression tests guard recall, precision and the numeric guard — and
they were proven to fail, not just to pass.

**Stack:** ClickHouse Cloud · ClickStack/HyperDX · Langfuse · LibreChat.
