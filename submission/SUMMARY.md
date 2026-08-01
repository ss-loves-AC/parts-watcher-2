# From alert to answer — solution summary

**A metric moves. In under a minute the system says which segment did it, proves
it, states what it ruled out, and shows the SQL it used.**

## How it works

ClickHouse does the analysis; the LLM only writes the sentence.

`ad_events` is denormalised at load so the drill-down never joins. A
materialized view fans every event into a cube keyed by `(hour, dim_name,
dim_value)`, so **one query scans all twelve dimensions** in 69 ms — adding a
dimension is one line, not a new table.

Detection compares each metric against the same weekday three weeks back,
scored against how much that metric normally moves. Weekend seasonality cancels
by construction. It runs hourly *and* daily: the eCPM incident is −2.4% across
four days — invisible per hour, obvious per day.

Attribution asks three separate questions. **Is it real?** ClickHouse's native
`proportionsZTest`: Android 15 scores z = −187 against a next-best of −52.
**Is it distinctive?** Measured against the population's change, not its own
size. **Is it responsible?** Remove each candidate and remeasure; whichever
leaves least behind is the cause. Only the third can name a culprit — one app
beat the population by 33% and accounted for 24% of the movement.

When one dimension doesn't explain it, it drills inside. The Jun 29 drop looks
like `country = JP`; the truth is **JP × iOS 18.1** (0.787 → 0.394).

## Why the numbers can be trusted

The model receives a JSON of finished strings — no database handle, no rows, no
arithmetic. A figure not in that JSON has nowhere to come from. Every numeric
token in the prose is then checked back against the evidence; two failures and a
deterministic template ships. Hallucination isn't discouraged, it's
structurally impossible — and verified against a re-rounded figure and an
invented one.

Each trace carries **the SQL actually executed, its parameters, rows returned
and elapsed time**. "No trace, no credit" should mean a judge can check the
working, not read a claim about it.

## Knowing when to say nothing

On Jun 21 every segment fell ~45% together. Ranking by absolute delta names
`banner` confidently and wrongly. We report **global — no segment responsible**,
because nothing stands clear of the population. Declining to localise is the
hardest result to produce and the easiest to get wrong.

## It closes the loop

The detector writes findings to a `detections` table; the investigation writes
the cause back onto the same row, so one list answers *what moved* and *why*.
HyperDX alerts on "did the detector find anything?" — threshold zero, no tuned
number, no named segment. That fires a webhook, wakes a self-hosted runner, and
the system pins the culprit back into HyperDX as a saved view. Proven on
`country = JP`, which appears in no configuration.

## Results

Four planted movements, four found, zero false positives, no weekend flagged.
Full report in 20 seconds. Replay shows 6-hour time-to-detect. Twelve
regression tests — proven to fail, not merely to pass.

**ClickHouse Cloud · ClickStack · Langfuse · LibreChat**
