# ClickHouse schema review

`load/schema.sql` and `load/cube.sql` reviewed against the 31 rules in the
official `clickhouse-best-practices` skill. Run at T+3h, before building the
detector on top of these tables — `ORDER BY` is immutable, so this is the last
cheap moment to change it.

## Rules checked

| Rule | Result |
|---|---|
| `schema-pk-plan-before-creation` | Compliant — reviewed before the engine depends on it |
| `schema-pk-cardinality-order` | **Violation on `segment_cube` — fixed**; deliberate deviation on `ad_events` |
| `schema-pk-prioritize-filters` | **Violation on `segment_cube` — fixed** |
| `schema-pk-filter-on-orderby` | Compliant after the fix |
| `schema-types-native-types` | Compliant |
| `schema-types-minimize-bitwidth` | Compliant |
| `schema-types-lowcardinality` | Compliant |
| `schema-types-enum` | Deliberate deviation |
| `schema-types-avoid-nullable` | Compliant |
| `schema-partition-low-cardinality` | Compliant |
| `schema-partition-lifecycle` | Compliant |
| `schema-partition-start-without` | Deliberate deviation (low impact) |
| `query-mv-incremental` | Compliant in substance |
| `query-join-choose-algorithm` | Compliant |
| `query-index-skipping-indices` | Deferred — not yet warranted |
| `insert-batch-size` | Compliant |
| `insert-mutation-avoid-update` / `-delete` | Compliant — no mutations at all |

---

## Violation found and fixed

### `segment_cube` ordering was backwards

Per `schema-pk-cardinality-order`, ordering columns run low-to-high cardinality
so the sparse primary index can skip granules. Measured cardinality:

```
dim_name     12
bucket      840
dim_value  2561
```

The original `ORDER BY (bucket, dim_name, dim_value)` led with the *middle*
cardinality column and buried `dim_name` — which is exactly the column the
detector filters by equality (`dim_name = '__total__'`), so
`schema-pk-prioritize-filters` was violated too.

Benchmarked both orderings on the two real query shapes, three runs each,
taking the last:

| Query | `(bucket, dim_name, dim_value)` | `(dim_name, bucket, dim_value)` |
|---|---|---|
| **Detector** — `dim_name='__total__'` | 3,018,832 rows · 21.7 ms | **40,960 rows · 4.9 ms** |
| **Segment scan** — all dims, two 3-day windows | 606,208 rows · 30.5 ms | **402,399 rows · 9.5 ms** |

**74x fewer rows read on the detector query.** The original ordering full-scanned
the cube to answer a question about 1/12th of it. Elapsed times are small either
way at this data size — `rows_read` is the honest metric, and it's the one that
scales when the dataset grows.

**Fixed** in `load/cube.sql`; table recreated and reloaded. All 12 dimensions
still reconcile to the exact fact-table totals after the change.

---

## Deliberate deviations

These are choices that read as violations but are correct for this workload.
Documented so a reviewer doesn't "fix" them.

### 1. `ad_events` orders by `event_time` alone — the highest-cardinality column

`schema-pk-cardinality-order` says lead with low cardinality. `event_time` has
~3M distinct values across 9M rows, so it looks like the anti-pattern.

It isn't, because **every query against this table is a time-range filter**, and
`event_time` is monotonic — range pruning works directly on the sort key
without needing a low-cardinality prefix. That rule's failure mode is a
high-cardinality column filtered by *equality* (a UUID), where the index can
skip nothing.

The alternative — leading with a dimension — would only help queries filtering
*that* dimension. The refinement step filters on **arbitrary** dimensions
(whichever the scan implicated), so no fixed dimension prefix helps the general
case.

### 2. No `Enum8` for finite-value columns

`schema-types-enum` recommends `Enum` for fixed value sets, and `ad_format` (5),
`publisher_tier` (3), `campaign_type` (4), `region` (5) all qualify. It would
add validation and shrink storage below `LowCardinality`.

**Rejected because of the unseen incident.** The sealed dataset arrives in the
final hours. If it contains an `ad_format` value not in our `Enum`, the
`INSERT` **fails outright**. `LowCardinality(String)` accepts the new value and
the pipeline keeps running.

Trading a little storage and some validation for "cannot fail on unseen input"
is the right call when the highest-weighted judging criterion runs on data we
have never seen.

### 3. Monthly partitioning kept, though `schema-partition-start-without` suggests none

Two partitions for 35 days of data. The rule's advice is to skip partitioning
without a lifecycle requirement. Kept because reloads for the unseen dataset
can operate at partition granularity, and 2 partitions cost essentially
nothing. Low impact in either direction.

### 4. `SimpleAggregateFunction` rather than `-State` / `-Merge`

`query-mv-incremental` demonstrates `countState()` / `countMerge()`. We store
`SimpleAggregateFunction(sum, …)` instead.

Compliant in substance: `SimpleAggregateFunction` exists precisely for
associative functions like `sum`, where the partial aggregate *is* the value and
no intermediate state is needed. It's lighter and simpler. We would need
`-State`/`-Merge` the moment we add `uniq` or a quantile to the cube — worth
knowing before someone adds "unique users" to it.

---

## Compliant, with notes

- **`schema-types-lowcardinality`** — every dimension is under the 10K
  threshold; the widest is `geo_device_id` at 5,000.
- **`schema-types-avoid-nullable`** — no `Nullable` anywhere. Unmatched joins
  fall back to `'unknown'`, and structurally-absent advertisers to `'none'`, so
  the two cases stay distinguishable without null semantics.
- **`schema-types-minimize-bitwidth`** — `UInt8` for the three funnel flags.
- **`schema-partition-low-cardinality`** — 2 partitions, far inside the
  100–1,000 guidance.
- **`insert-batch-size`** — a handful of large inserts rather than many small
  ones. Part counts confirm no small-parts problem:
  `ad_events` 5 parts / 9M rows, `segment_cube` 5 parts.
- **`query-join-choose-algorithm`** — the denormalizing `INSERT SELECT` uses
  `parallel_hash` against three tiny dimension tables, which is the right
  algorithm for a small right-hand side.
- **`insert-mutation-avoid-update` / `-delete`** — no mutations exist. Reloads
  are `TRUNCATE` + insert, which is a metadata operation rather than a
  row-by-row rewrite.

## Deferred

**`query-index-skipping-indices`** — the refinement query filters `ad_events` on
arbitrary dimensions not in `ORDER BY`, which is the textbook case for a skip
index. Not added yet, because the rule itself says skip indices come *after*
type, key, and MV optimisation and should never be added "without testing on
real data". That query currently runs in 356ms and is executed only for the top
few candidates, so it isn't the bottleneck. Revisit if the refinement step
becomes hot.

## Operational trap worth remembering

`query-mv-incremental` notes that an incremental MV does **not** include data
that already exists when the view is created. `load/load.sh` creates the MV
*before* inserting, so the cube populates naturally.

If anyone creates the view after loading the fact table, **the cube will be
silently empty** — no error, just zero rows. Relevant when the unseen dataset
lands and someone is tempted to load it by hand.
