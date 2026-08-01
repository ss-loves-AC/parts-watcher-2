# Problem statement — InMobi track

*Click-a-thon 2026. Condensed from the official package issued by the
organisers; the authoritative wording is theirs. All data is **synthetic** — no
real advertiser, publisher, or user data of any kind.*

## From alert to answer: the automated root-cause analyst

Every data-driven team watches a handful of numbers: revenue, fill rate,
impressions, latency, error rate. When one of them jumps or drops, the useful
question isn't *"did it move?"* — an alert already answers that. It's **"why?"**

Today that answer comes from a human drilling through dashboards, slicing the
metric dimension by dimension, comparing each slice against normal, and
assembling an explanation. Across thousands of app, device, geo, and advertiser
combinations this takes hours or days, even though all the data already exists.
The bottleneck is never the data. It's the manual investigation.

**Build a system that automatically investigates why a metric moved and returns
a short, evidence-backed explanation in seconds, not days.**

Given a stream of metric/event data, the system must:

1. **Detect** when a key metric deviates from its expected baseline
2. **Automatically drill down** to isolate the segment(s) responsible
3. **Produce a plain-language diagnosis** where every claim is backed by a
   specific computed number
4. **Bonus:** state what it checked and *ruled out*, not just what it found

## The data

A synthetic ad-events dataset with dimension tables — ~9M events over 5 weeks
(Jun 1 – Jul 5 2026), with realistic seasonality and noise.

```
        apps (2K)                          advertisers (500)
   app_id, category,                 advertiser_id, vertical,
   publisher_tier                         campaign_type
            \                                 /
             \                               /
            ad_events  (9M rows)  -- the event stream
   event_time, app_id, geo_device_id, advertiser_id, ad_format,
   is_filled, is_impression, is_click, revenue
                        |
                 geo_device (5K)
      geo_device_id, region, country, device_model, os_version
```

Each row is one ad request and what happened to it. `advertiser_id` is empty
when a request wasn't filled.

**Anomalies have been deliberately planted** in specific segments and time
windows. The answer key stays private with the judges.

### Metric definitions

The funnel is **Request → Fill → Impression → Click**, with revenue earned on
impressions.

| Metric | Formula |
|---|---|
| Requests | `count(*)` |
| Fills | `sum(is_filled)` |
| Fill rate | `sum(is_filled) / count(*)` |
| Impressions | `sum(is_impression)` |
| Render rate | `sum(is_impression) / sum(is_filled)` |
| Clicks | `sum(is_click)` |
| CTR | `sum(is_click) / sum(is_impression)` |
| Revenue | `sum(revenue)` |
| eCPM | `sum(revenue) / sum(is_impression) * 1000` |
| Revenue per request | `sum(revenue) / count(*)` |

Ratio metrics must be computed as **sum / sum** over the rows in a group, never
as an average of per-row or per-day ratios, so rollups stay correct.

**The revenue identity**, used to decompose a move:

```
Revenue  =  Requests  x  Fill rate  x  (Impressions / Fills)  x  eCPM / 1000
```

When revenue moves, walk this identity to find *which factor* is responsible
(volume? fill? price?), then slice that factor by dimension to find *which
segment*.

### Sliceable dimensions

- **`ad_events`:** `ad_format` — banner, interstitial, native, rewarded, video
- **`apps`:** `category` (7 values); `publisher_tier` — tier_1/2/3
- **`advertisers`:** `vertical` (7 values); `campaign_type` — CPM, CPC, CPI
- **`geo_device`:** `region` — NAM, EU, APAC, LATAM, MEA; `country`;
  `device_model`; `os_version`

> North America is coded `NAM`, not `NA`, because `NA` is read as null by many
> tools.

### On "normal"

The data has real **daily** (hour-of-day) and **weekly** (weekends lower)
seasonality plus a slow growth trend and random noise. A flat global average
makes every weekend look like an anomaly — compare against a like-for-like
baseline instead. **At least one planted movement is pure seasonality and should
be checked and ruled out, not alarmed on.**

## The unseen incident

A fresh slice of the same universe, with new planted anomalies no one has seen,
is released to all teams simultaneously in the final hours. The submission must
include what the system produced for it: the diagnosis, the numbers behind it,
and the trace proving the system generated them.

**Build for the unseen incident, not the anomalies found during the build.**

## Requirements

- **ClickHouse must be the primary datastore and analytical engine** — all
  metric/event data lives in ClickHouse and the drill-down runs as ClickHouse
  queries.
- **Meaningfully integrate at least one of** ClickStack (observability),
  Langfuse (LLM observability), or LibreChat (conversational interface).
  Superficial inclusion won't count.
- Any anomaly-detection and attribution approach is allowed.
  **Explainability and trustworthiness matter more than sophistication.**

## What "great" looks like

- **Fast.** A moving metric is diagnosed in seconds.
- **Trustworthy.** The explanation cites real computed numbers, no hallucinated
  figures. *Consider: let deterministic code do the analysis and use the LLM
  only to narrate.*
- **Localized.** It names the specific segment responsible, not just "something
  is off."
- **Honest.** It shows which possibilities were checked and cleared.

## How it's evaluated

| Criterion | What it means |
|---|---|
| **Detection & localization accuracy** | Judged against the private answer key: found the planted anomalies, named the right segments, avoided crying wolf on noise |
| **Explanation trustworthiness** | Every number reproducible from the data. **A single fabricated figure costs more than a missed anomaly** |
| **Analytical depth in ClickHouse** | The drill-down lives in queries, not in the LLM |
| **Traceability** | A judge can open the traces and follow the investigation: what was checked, in what order, why |
| **The unseen incident** | Carries significant weight; outputs are directly comparable across teams. **No trace, no credit** |

## Deliverables

- Public GitHub repo (MIT / Apache-2.0), all code written during the 24-hour
  window
- ≤500-word solution summary · ≤5-minute demo video · ≤15-slide pitch deck
- The system's output for the unseen dataset, with the trace that proves the
  system generated it

## Out of scope

Authentication, production deployment, alerting integrations, and polished
frontends. Judges reward the investigation loop, not the scaffolding.

## Suggested demo

Replay an incident end to end: a metric drops → the system runs → a metric tree
lights up green/amber/red → a plain-English diagnosis (*"revenue fell because
fill rate dropped for Device X in Region Y; seasonality checked and ruled
out"*) → optionally, a follow-up question in chat.

---

See [DESIGN.md](DESIGN.md) for how we're solving this.
