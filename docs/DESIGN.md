# Automated Root-Cause Analyst — design

Click-a-thon 2026, InMobi track: *"From alert to answer."*

Written T+0.5h (2026-08-01), updated T+2.5h with results from the built cube.
See [PROBLEM_STATEMENT.md](PROBLEM_STATEMENT.md) for what we're solving and
[DATA_LOADING.md](DATA_LOADING.md) for how the data gets into ClickHouse.

## What's actually in the data

Established by scanning the provided 9M rows before designing anything. Global
shape: ~78.5% fill rate, ~1.09% CTR, eCPM ~$2.47, $17,020 revenue over
Jun 1 – Jul 5 2026.

| Window | What moved | Localization |
|---|---|---|
| Jun 23–25 | fill rate 0.785 → 0.750 | **`os_version = Android 15`: 0.785 → 0.433.** Clean, single-dimension, large |
| Jun 28–30 | fill rate 0.785 → 0.776 | Milder, same shape — likely a second planted fill incident |
| Jun 19–22 | eCPM 2.476 → 2.415 | **`ad_format = interstitial`: −7.1%** vs −2.5% global. Localized but weak |
| Jun 21 (Sun) | requests 225K → 126K (−44%) | **Not localized at all** |

### Two traps that drive the design

**1. Jun 21 is a global collapse, not a segment.** Every dimension value moved
by the same −44%. A detector ranking segments by absolute delta will
confidently name `banner` and `NAM`, because they're the largest segments and
so have the largest absolute drops. That is the hallucinated-localization
failure the rubric punishes. The right answer is *"global, ~−44% uniform, no
segment responsible."*

**2. Weekends are −18% on requests**, and the glossary warns that at least one
planted movement is pure seasonality, to be ruled out rather than alarmed on.

---

# Anomaly detection, in plain terms

The detector is deliberately simple. Not because sophistication is unavailable,
but because **the explanation has to survive a judge asking "how do you know
that?"** — and because a method you can state in one sentence is a method an
LLM can narrate without inventing anything.

## The method: four questions

**1. What should this number have been?**
Look at the same hour, on the same weekday, for the last 3 weeks. Take the
middle value. That's the *expected* value.

> Why same-weekday: weekends run ~18% below weekdays. Comparing Sunday to
> Sunday means seasonality cancels itself out instead of masquerading as an
> incident.

**2. How much does this number normally wobble?**
Take those same historical values and ask how far they typically sit from their
own middle value. That's the *normal wobble* (formally: median absolute
deviation).

> Why the middle value and not the average: one bad day drags an average
> sideways *and* inflates the spread — so an anomaly quietly raises the bar for
> detecting itself. The median ignores outliers, which is what you want when
> outliers are the thing you're hunting.

**3. Is this far off?**
`(actual − expected) ÷ normal wobble` = **how many wobbles away**. Past about
4 wobbles, report it. Below that, stay quiet.

**4. Who caused it?**
For every value of every dimension, compare *its* percentage change against the
*whole population's* percentage change. One value standing far apart from the
rest is the culprit. Nothing standing apart means the move is global.

That's the whole detector. Steps 1–3 find *when*, step 4 finds *who*.

## Three verdicts, decided by code

The classification is made by deterministic rules, never by the LLM. The LLM is
handed the verdict and writes prose for it.

| Verdict | Rule | Plain meaning |
|---|---|---|
| **localized** | top segment stands well clear of the next | "One segment did this" |
| **global** | no segment stands clear of the population | "Everything moved together" |
| **seasonal** | actual sits within normal wobble of the same-weekday expectation | "This is just what Sundays look like" |

The `global` verdict is what saves us on Jun 21; the `seasonal` verdict is what
stops us firing on all ten weekends.

## The evidence contract

**The LLM must never compute, compare, or infer. Every fact it needs arrives as
a finished phrase.** Narration becomes templating, and a fabricated figure
becomes structurally impossible rather than merely discouraged.

So the engine emits this, not raw statistics:

```json
{
  "metric": "fill rate",
  "window": "Jun 23-25",
  "expected": "78.5%",
  "actual": "75.1%",
  "direction": "down",
  "change": "-4.4%",
  "normal_wobble": "±0.3%",
  "how_unusual": "14x larger than normal day-to-day movement",
  "verdict": "localized",

  "culprit": {
    "dimension": "device OS version",
    "value": "Android 15",
    "its_change": "-44.8%",
    "everything_else_changed": "-0.1%",
    "share_of_traffic": "8%"
  },

  "proof": "Excluding Android 15, fill rate went 78.5% -> 78.4%: essentially flat.",

  "ruled_out": [
    { "what": "weekend seasonality",
      "why": "compared Tue-Thu against Tue-Thu" },
    { "what": "request volume",
      "why": "within normal range, +0.4%" },
    { "what": "Galaxy S23",
      "why": "moves only because most Galaxy S23 devices run Android 15; with Android 15 excluded it is flat" }
  ]
}
```

Three rules this JSON follows:

- **Percentages are pre-formatted strings**, not floats. The LLM copies
  "−44.8%" rather than rounding `-0.44797` and getting it subtly wrong.
- **Dimensions carry human names** — `"device OS version"`, not `os_version`.
  The narrator shouldn't be inventing readable labels.
- **`ruled_out` is populated by the engine**, because it tested those things
  anyway. The honesty bonus costs nothing extra: it's a byproduct of the
  drill-down already running.

Given the above, the model's entire job is:

> *"Fill rate fell 4.4% on Jun 23–25, from an expected 78.5% to 75.1% — about
> 14 times a normal day's movement. Effectively all of it came from Android 15
> devices, where fill dropped 44.8% while everything else stayed flat at −0.1%.
> Excluding Android 15, the metric is unchanged. Weekend seasonality and
> request volume were checked and cleared; Galaxy S23 appeared affected only
> because most of those devices run Android 15."*

Every number in that paragraph is a field it was handed.

---

## Architecture

```
parquet ─► denormalized fact (dims folded in at load, LowCardinality)
        ─► cube MV: (hour, dim_name, dim_value) -> AggregatingMergeTree sums
        ─► [1] detector      four questions above, over the __total__ rows
        ─► [2] identity walk  Revenue = Req x Fill x Render x eCPM/1000
        ─► [3] segment scan   all 12 dimensions in one query, vs global
        ─► [4] refinement     condition on the winner, re-scan for residual
        ─► evidence JSON      pre-formatted, ruled-out ledger included
        ─► LLM narrates       never sees raw data
        ─► trace ─► Langfuse + investigations table in ClickHouse
```

**The cube trick.** One materialized view `ARRAY JOIN`s each event into one row
per `(dim_name, dim_value)` pair, plus a `__total__` row. A *single*
parameterised query then scans every dimension — adding a dimension later means
one more line in an array, not a new table and not a new query.

Ordered `(dim_name, bucket, dim_value)`, low-to-high cardinality. See
[CLICKHOUSE_REVIEW.md](CLICKHOUSE_REVIEW.md) — the obvious `(bucket, …)`
ordering read 74x more rows on the detector query.

### Built and measured (T+2.5h)

`rca.segment_cube`: **2,970,060 rows · 17.36 MiB · 840 hourly buckets · 12
dimensions.** Smaller than the parquet it summarises.

All 12 dimensions independently reconstruct the exact fact-table totals
(9,000,000 requests / 7,027,910 fills / 6,887,058 impressions / 74,940 clicks /
17020.36 revenue). Any `ARRAY JOIN` branch dropping or duplicating events would
break that reconciliation; none does.

**Case A — fill rate, Jun 23–25 vs Jun 16–18. One query, all 12 dimensions, 69ms:**

```
dim_name      dim_value       base    incident  seg_pct  vs_global_pct
os_version    Android 15      0.7849  0.4333    -44.80   -42.27
device_model  Galaxy S23      0.7874  0.6873    -12.70    -8.71
device_model  Redmi Note 12   0.7842  0.6998    -10.76    -6.67
country       UK              0.7827  0.7056     -9.85    -5.72
```

**Case B — requests, Sun Jun 21 vs Sun Jun 14. Same template, 42ms:**

```
dim_name      dim_value   seg_pct  vs_global_pct
vertical      gaming      -45.67    -2.85
country       AE          -45.42    -2.41
category      news        -45.22    -2.05
```

Everything is down ~45%, but normalized against global the worst offender is
−2.85%. The uniformity test correctly reports **no localization**.

**Refinement — does the culprit fully explain it? 356ms on the fact table:**

```
ALL traffic                   0.7852 -> 0.7508    the incident
EXCLUDING Android 15          0.7852 -> 0.7844    flat: fully explained
Galaxy S23, EXCL Android 15   0.7894 -> 0.7852    flat: pure shadow
```

An 0.08% residual against a 3.4-point drop. This is what populates `proof` and
the third `ruled_out` entry — computed, not asserted.

**Known limit:** the cube is single-dimension by construction, so it cannot
answer "Galaxy S23 **and** not Android 15". Conditioning goes to the fact table.
That's the right trade — the broad 12-dimension sweep costs 69ms, and only the
top few candidates pay the 356ms fact-table query.

## The three decisions

**1. Baseline** — same hour-of-week, trailing 3 weeks, median + MAD. Chosen over
multiplicative decomposition (more machinery, similar accuracy on 5 weeks) and
forecasting libraries (hours of work, no gain). Explainable in one sentence,
which is the point.

**2. Attribution** — relative-change-vs-global (the uniformity test, validated
above) plus **mix-vs-rate decomposition** for ratio metrics:

```
Δ fill_rate  =  Σ w_base × (r_inc − r_base)     ← rate effect
             +  Σ (w_inc − w_base) × r_base     ← mix effect
```

This separates *"Android 15's fill rate collapsed"* from *"more Android 15
traffic arrived and it always filled worse"* — two different incidents a naive
scan reports identically.

**3. Agent, not free-form SQL** — an agent orchestrating *typed tools* that wrap
parameterised deterministic SQL. Not a pure pipeline (scores poorly on
innovation), not an LLM writing its own SQL (the trap the statement warns
about: slow, expensive, invents numbers).

---

# OSS stack integration

## Where each tool is actually used

**Status as of T+3h: none of them are wired up yet.** Everything below is
planned. Saying so plainly matters more than a diagram that implies otherwise —
the requirement is "meaningfully integrate", and a judge will check.

```
 HyperDX ───alert fires───► [1] DETECT ──► [2] DRILL DOWN ──► [3] REFINE
 "fill rate is 14 wobbles                                          │
  below normal"                                                    ▼
                                                          [4] EVIDENCE JSON
                                                                   │
                                            Langfuse ◄──── [5] LLM NARRATES
                                            (every step a span)    │
                                                                   ▼
                                                        investigations table
                                                          (ClickHouse Cloud)
                                                                   │
                            LibreChat ◄──ClickStack MCP────────────┘
                            "why did you rule out volume?"
```

| Tool | Exactly where it plugs in | What it buys | Status |
|---|---|---|---|
| **Langfuse** | Wraps stages 1–5. Each investigation is one trace; detect / scan / refine / narrate are spans carrying their inputs and outputs | **The scored deliverable.** "No trace, no credit" on the unseen incident. A judge replays what was checked, in what order, and why. Also captures LLM cost and latency | planned — **P1, mandatory** |
| **HyperDX** | *Upstream* of stage 1. A saved alert on a metric threshold fires a webhook → `repository_dispatch` → the agent wakes and investigates | This is the **"alert"** in *"from alert to answer"*. Without it the system is a script someone runs; with it, the loop closes | planned — **P2, highest innovation-per-hour** |
| **ClickStack** | *Around* the pipeline. OTEL spans from stages 1–5 land in ClickHouse; the `investigations` table is registered as a ClickStack source | Our own pipeline becomes queryable telemetry — the 24 semantic tools work over the investigation record, not just raw SQL | planned — P3 |
| **LibreChat** | *Downstream* of stage 5. Chat UI with the ClickStack MCP attached, pointed at `investigations` | The "ask a follow-up" ending in the suggested demo: *"why did you rule out request volume?"* answered from the stored evidence, not re-derived | planned — P4, only if ahead |

**The minimum bar is Langfuse alone** — the rules require *at least one* of
ClickStack / Langfuse / LibreChat, and Langfuse is the one that doubles as a
judging criterion. HyperDX is not on the required list at all; it earns its
place by making the alert trigger real rather than simulated.

Doing all four organically also targets the Spot Award.

## Why this is cheaper than it looks

The warm-up repo (`ch-hacker`) holds working, proven components that map onto
this problem almost exactly, and rebuilding them under a 24h clock would be
wasteful. Until T+2.5h this section named the tools generically without using
any of those assets, and never mentioned HyperDX at all — that was a real gap.

## The mapping nobody should miss

The problem is titled **"From alert to answer"**. The warm-up already built
*alert → triage → typed-skill RCA → verify → log*, demonstrated end to end on
2026-07-24. The shapes are the same; only the domain changes — telemetry
incidents become ad-metric incidents.

| Warm-up asset | Reuse here |
|---|---|
| **SRE agent** (`drills/agentic-remediation/sre_agent.py`) — triage → load playbook → RCA → act → verify → log | The agent shell. Swap the incident taxonomy for metric-movement types (volume / fill / price / mix) |
| **Runtime-loaded markdown skills** (`skills/{triage,<type>}.md`) | One playbook per metric-movement type, progressively disclosed |
| **`agent_annotations` table** + daily rollup MV | Becomes the `investigations` audit table — one row per detection/step/verdict, queryable by a judge |
| **HyperDX alert → `repository_dispatch` → agent** | Literally implements "from alert to answer": a fill-rate alert fires, the agent wakes and investigates |
| **ClickStack MCP** (24 semantic tools, in-process at HyperDX `/api/mcp`) | LibreChat's follow-up-question interface over the investigation record |
| **Langfuse `observations` in ClickHouse** | Traces of every investigation — the "no trace, no credit" deliverable |
| **PydanticAI + DeepSeek gotchas** | Filter MCP toolsets (tuple-form `items` schemas crash the transformer); raise `retries`; directive prompts; `UsageLimits`; schema hints in the prompt |

## Priority under a 24h clock

1. **Langfuse — mandatory.** "No trace, no credit" makes traceability a scored
   deliverable. Every investigation step is a span; the judge replays what was
   checked, in what order, and why. Already wired in the warm-up.
2. **HyperDX alert → agent — highest innovation-per-hour.** It's the literal
   title of the problem statement, and the dispatch path is already proven.
3. **ClickStack OTEL spans** over the RCA pipeline — the system's own telemetry
   becomes queryable.
4. **LibreChat + ClickStack MCP** — the "ask a follow-up" ending in the
   suggested demo. Last three hours, strictly optional.

Doing all four organically also targets the Spot Award.

## Architectural caveat: two ClickHouse instances

The hackathon requires ad data to live in **ClickHouse Cloud** (ap-south-1).
The warm-up ClickStack / HyperDX / Langfuse stack runs on the **Hetzner VPC**
against a *different* ClickHouse, with a hard 7.6GB memory ceiling.

Don't merge them. The split is clean and defensible:

- **Cloud** = the primary datastore. Ad events, the cube, the investigations
  table. This is what "ClickHouse is the primary database" means for judging.
- **VPC** = the observability plane. Langfuse receives traces over HTTP;
  HyperDX raises alerts. Neither needs to hold the ad data.

State this explicitly in the deck — a judge seeing two ClickHouse instances
should read it as deliberate separation, not confusion.

---

## Innovation levers

- **The ruled-out ledger as a first-class output** — the engine tests every
  dimension anyway; emit all of them with verdicts, not just the winner.
- **Counterfactual impact** — *"had Android 15 fill held at baseline, revenue
  would have been $X higher"*. One extra query.
- **Correctly declining** — demo Jun 21 (*"global, no segment responsible"*)
  and a weekend (*"expected seasonality"*). Most teams will over-fire;
  calibrated silence is the differentiator.
- **Investigation trace queryable in ClickHouse**, not only in Langfuse — the
  judge can `SELECT` the reasoning.

## Build plan

| Time | Milestone | Status |
|---|---|---|
| T+1h | Repo, Cloud service, data loaded | **done** |
| T+2.5h | Cube MV + all-dimension scan validated | **done** |
| T+4h | Detector: four questions, over `__total__` | next |
| T+6h | Segment scan + refinement → evidence JSON | |
| T+9h | LLM narration from JSON only; Langfuse tracing | |
| T+13h | Agent shell (reuse `sre_agent.py`); HyperDX alert trigger | |
| T+18h | Harden loader for the unseen file | |
| T+20h | Freeze. Unseen incident → run → capture output + trace | |
| T+23h | Video, deck, 500-word summary | |
| T+23.5h | **Submit** — portal closes server-side at 12pm | |

## Risks

- **Hardcoded dates.** The unseen slice will not span Jun 1 – Jul 5. Every
  baseline must derive its windows from the data's own `max(event_time)`.
- **Threshold calibration.** Tune on the four known windows but favour
  precision — Jun 21 shows how easy a confident wrong answer is.
- **Small-segment noise.** Without a minimum-volume guard, a 40-request app at
  0% fill outranks the real incident. The validated scans above use a
  `HAVING requests > 20000` guard.
- **Scope creep into the agent.** The deterministic engine is the scored part.
