# Architecture

**Rendered diagram:** [`architecture.svg`](architecture.svg) ·
[`architecture.png`](architecture.png) — generated from
[`architecture.mmd`](architecture.mmd) and verified clean:

```bash
npx --no-install agentic-mermaid verify docs/architecture.mmd --json
npx --no-install agentic-mermaid render docs/architecture.mmd \
    --format svg --style publication-figure --output docs/architecture.svg
```

`.mcp.json` also registers agentic-mermaid as an MCP server, so the diagram can
be inspected and edited structurally rather than by patching text — `describe`
reads it back as facts, `execute` applies typed mutations. Takes effect on the
next session start.

The ASCII below is kept because it reads in a terminal and in a diff.

```
                            ClickHouse Cloud · ap-south-1 · database "pw"  (CH_DB)
  ┌──────────────────────────────────────────────────────────────────────────────────────┐
  │                                                                                      │
  │   ad_events.parquet      apps.csv    advertisers.csv    geo_device.csv               │
  │      9,000,000              2,000          500              5,000                    │
  │          │                    └─────────────┴────────────────┘                       │
  │          ▼                                  ▼                                        │
  │   ┌──────────────┐                   ┌──────────────┐                                │
  │   │ad_events_raw │                   │  dimension   │        load/schema.sql          │
  │   │ source-exact │                   │    tables    │        load/load.sh  ~31s      │
  │   └──────┬───────┘                   └──────┬───────┘                                │
  │          │            LEFT JOIN (parallel_hash)                                      │
  │          └──────────────────┬─────────────────┘                                      │
  │                             ▼                                                        │
  │                   ┌───────────────────┐                                              │
  │                   │    ad_events      │  denormalized · 17 cols · LowCardinality      │
  │                   │  9,000,000 rows   │  revenue Decimal(18,6) · no joins downstream  │
  │                   └─────────┬─────────┘                                              │
  │                             │  MATERIALIZED VIEW  (fires on insert)                  │
  │                             │  ARRAY JOIN → 1 row per (dim_name, dim_value) + total   │
  │                             ▼                                                        │
  │                   ┌───────────────────┐                                              │
  │                   │   segment_cube    │  2.9M rows · 17 MiB · 840 hourly buckets      │
  │                   │ AggregatingMerge  │  12 dimensions · ORDER BY (dim_name,          │
  │                   │      Tree         │                    bucket, dim_value)         │
  │                   └─────────┬─────────┘                                              │
  │                             │                                                        │
  └─────────────────────────────┼────────────────────────────────────────────────────────┘
                                │
     ┌──────────────────────────┴───────────────────────────┐
     │                                                      │
     ▼  dim_name='__total__'                                ▼  dim_name!='__total__'
  ╔═══════════════════════╗                          ╔═══════════════════════════╗
  ║  [1] DETECT           ║   40,960 rows · 4.9ms    ║  [2] SEGMENT SCAN         ║
  ║  sql/detect.sql       ║                          ║  all 12 dims, one query   ║
  ║                       ║                          ║  69ms · full report 8.3s  ║
  ║  expected = median of ║                          ║  REAL?  proportionsZTest  ║
  ║   same weekday+hour,  ║                          ║   exact, no volume guess  ║
  ║   3 weeks back        ║                          ║  DISTINCTIVE?  %change    ║
  ║  wobble  = MAD of the ║                          ║   vs the population's     ║
  ║   ratio, whole series ║                          ╚════════════╤══════════════╝
  ║  wobbles = effect/    ║                                       │
  ║   wobble   (gate: 4)  ║                                       ▼
  ║                       ║                          ╔═══════════════════════════╗
  ║  grains: hourly+daily ║                          ║  [3] REFINE — the arbiter ║
  ║  pass 2 excludes      ║                          ║  RESPONSIBLE?  remove each║
  ║   anomalous days      ║                          ║   candidate, keep the one ║
  ║   from history        ║                          ║   leaving least behind.   ║
  ║                       ║                          ║   ALL candidates in ONE   ║
  ║                       ║                          ║   ad_events scan          ║
  ╚═══════════╤═══════════╝                          ╚════════════╤══════════════╝
              │  when                                             │  who
              └────────────────────────┬──────────────────────────┘
                                       ▼
                         ╔═════════════════════════════╗
                         ║  [4] EVIDENCE JSON          ║
                         ║  pre-formatted strings      ║
                         ║  verdict: localized/global/ ║
                         ║           seasonal          ║
                         ║  + ruled_out ledger         ║
                         ╚══════════════╤══════════════╝
                                        │  no raw data crosses this line
                    ────────────────────┼────────────────────────────────
                                        ▼
                         ╔═════════════════════════════╗
                         ║  [5] LLM NARRATES           ║
                         ║  templating, not reasoning  ║
                         ║  every number = a field it  ║
                         ║  was handed                 ║
                         ╚══════════════╤══════════════╝
                                        │
                                        ▼
                         ╔═════════════════════════════╗
                         ║  guard: every numeric token ║
                         ║  in the prose must exist in ║
                         ║  the evidence JSON. 2 fails ║
                         ║  -> deterministic template  ║
                         ╚══════════════╤══════════════╝
                                        ▼
                    out/  diagnosis.md · evidence.json · trace.txt · queries.sql


  ── observability plane ────────────────────────────────────────────────────────

    schedule ──► [1] DETECT ──► investigation      the detector IS the alert;
    (detect.sql on a timer)                        no external trigger on the
                                                   critical path

    Langfuse ◄── spans from [1]..[5], one trace per investigation   (VPC)

    ClickStack/HyperDX ──► reads ClickHouse Cloud, NOT a second ClickHouse
      · OTEL spans of the pipeline land beside the ad data
      · dashboards over the investigation record
      · serves the MCP that gives LibreChat its tools

    LibreChat ──ClickStack MCP──► investigations table
    ("why did you rule out volume?")


  ── legend ─────────────────────────────────────────────────────────────────────

    ╔═══╗  built and measured          ┌───┐  ClickHouse object
    ║   ║                              └───┘
    ╚═══╝

    [1] built    [2] built    [3] built    [4] built    [5] built

    replay:  engine/replay.py — steps an as_of cutoff through the timeline so
             the detector sees only the past. Measured time-to-detect: 6h on
             the sharp incidents, 48h on the slow eCPM drift.

    observability plane: ClickStack source registered (Ad Events -> ClickHouse
             Cloud, provisioned by scripts/provision-clickstack.js on the
             self-hosted runner). Langfuse spans: not wired.
```
