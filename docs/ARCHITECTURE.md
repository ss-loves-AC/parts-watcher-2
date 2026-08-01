# Architecture

```
                            ClickHouse Cloud · ap-south-1 · database "rca"
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
  ║                       ║                          ║                     69ms  ║
  ║  expected = median of ║                          ║  each segment's %change   ║
  ║   same weekday+hour,  ║                          ║   vs the population's     ║
  ║   3 weeks back        ║                          ║   %change                 ║
  ║  wobble  = MAD of the ║                          ╚════════════╤══════════════╝
  ║   ratio, whole series ║                                       │
  ║  wobbles = effect/    ║                                       ▼
  ║   wobble   (gate: 4)  ║                          ╔═══════════════════════════╗
  ║                       ║                          ║  [3] REFINE               ║
  ║  grains: hourly+daily ║                          ║  condition on the winner, ║
  ║  pass 2 excludes      ║                          ║  re-scan for residual     ║
  ║   anomalous days      ║                          ║  on ad_events      356ms  ║
  ║   from history        ║                          ╚════════════╤══════════════╝
  ╚═══════════╤═══════════╝                                       │
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
                         ┌─────────────────────────────┐
                         │  guard: every numeric token │
                         │  in the prose must exist in │
                         │  the evidence JSON          │
                         └──────────────┬──────────────┘
                                        ▼
                    out/  diagnosis.md · evidence.json · trace.txt · queries.sql


  ── observability plane ────────────────────────────────────────────────────────

    HyperDX ──alert──► repository_dispatch ──► [1]        Langfuse ◄── spans from
    (metric threshold)                                    (1..5, one trace per
                                                           investigation)
    LibreChat ──ClickStack MCP──► investigations table
    ("why did you rule out volume?")


  ── legend ─────────────────────────────────────────────────────────────────────

    ╔═══╗  built and measured          ┌───┐  ClickHouse object
    ║   ║                              └───┘
    ╚═══╝

    [1] built    [2] validated inline, not yet committed
    [3] validated inline, not yet committed    [4] not built    [5] not built
    observability plane: not built
```
