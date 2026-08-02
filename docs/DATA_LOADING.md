# Data loading — InMobi track

How the Click-a-thon 2026 InMobi problem package gets into ClickHouse, and
exactly what is and isn't modified on the way in.

## Target

| | |
|---|---|
| Organization | DocuSign — `7d400f95-760d-48c7-9a5e-00b32fc516c8` |
| Account | `docusignclickathon2026@gmail.com` (sole member, created 2026-08-01) |
| Service | "My first service" — `d1b5021d-6252-4238-8385-27d31cc43b76` |
| Provider / region | AWS `ap-south-1` |
| Endpoint | `yl3hyta2vr.ap-south-1.aws.clickhouse.cloud` (`:9440` native/TLS, `:8443` HTTPS) |
| Database | `rca` |
| Server version | 26.2.1.525 |

Credentials live in `~/.config/clickhouse/clickathon.env` (mode 600), never in
the repo. The `default` user's credential was rotated through the Cloud control
plane with `--new-password-hash`, so only the hash ever crossed the API.

The service's IP access list is `0.0.0.0/0` ("Anywhere"). Convenient for a
hackathon and for demoing from a different network tomorrow; not a production
posture.

## Running it

```bash
./load/load.sh                      # uses ~/.config/clickhouse/clickathon.env
./load/load.sh path/to/other.env    # or point it elsewhere
```

Requires `bin/clickhouse` (the standalone client, ~664MB, gitignored — fetch
with `curl https://clickhouse.com/ | sh`).

The script is **idempotent**: every table is `TRUNCATE`d before insert, so
re-running is safe and non-cumulative. This matters — when the unseen incident
dataset drops in the final hours, the load path is the same script against a
new file, not an improvised one-off.

Runtime: **~21 seconds** end to end from this machine, including the 103MB
parquet upload to ap-south-1.

## What gets loaded

Source: `click-a-thon-2026/InMobi/data/`

| Source file | Table | Rows |
|---|---|---|
| `ad_events.parquet` | `rca.ad_events_raw` | 9,000,000 |
| `apps.csv` | `rca.apps` | 2,000 |
| `advertisers.csv` | `rca.advertisers` | 500 |
| `geo_device.csv` | `rca.geo_device` | 5,000 |
| *(derived)* | `rca.ad_events` | 9,000,000 |

## Is the data loaded as-is?

**`ad_events_raw` and the three dimension tables: yes.** Straight inserts, no
transformation, column-for-column with the source. `revenue` remains `Float64`.
`advertiser_id` remains an empty string on unfilled requests. This table is the
untouched source of truth — anything you want to re-derive differently later,
derive it from here.

**`ad_events`: no.** It is a derived, denormalized table with exactly three
deliberate changes from the raw data. Nothing else differs.

### 1. Dimensions folded in (denormalization)

The three dimension tables are `LEFT JOIN`ed into the fact table at load time,
adding 8 columns: `category`, `publisher_tier`, `vertical`, `campaign_type`,
`region`, `country`, `device_model`, `os_version`.

*Why:* the root-cause drill-down scans every dimension on every investigation.
Joining 9M rows against three dimension tables per scan, repeatedly, is the
dominant cost. Denormalized, the segment scan is a single-table aggregation.
Standard ClickHouse practice, and it costs only ~17MB (117MB vs 100MB) because
every added column is `LowCardinality(String)`.

*Verified:* `unmatched_geo = 0`, `unmatched_app = 0` — no orphan keys, no
silent join failures. Unmatched keys would fall back to `'unknown'` rather than
dropping rows, and the verify step counts them precisely so a broken join can
never pass silently.

### 2. `revenue`: `Float64` → `Decimal(18,6)`

*Why:* floating-point addition isn't associative, so parallel aggregation can
return revenue figures that differ in the last bits between runs. The rubric
states "a single fabricated figure costs more than a missed anomaly", and a
number a judge can't reproduce exactly is that failure. Decimal sums are exact
and order-independent. The source has at most 6 decimal places, so scale 6 is
lossless.

*Gotcha, found the hard way:* the obvious `toDecimal64(revenue, 6)` **truncates
the binary float toward zero** rather than rounding — `0.000123` held as
`0.000122999…` becomes `0.000122`. That's a systematic downward bias worth
**$0.12** across the 6.2M revenue-bearing rows. Measured against the source:

```
17020.3642      source Float64 sum
17020.240498    toDecimal64(revenue, 6)              WRONG, -$0.12
17020.364187    CAST(toString(revenue) AS Decimal)   correct
17020.364008    toDecimal64(revenue, 9)              still truncating
```

The load uses `CAST(toString(revenue) AS Decimal(18,6))`. Round-tripping via
the shortest decimal representation is exact.

### 3. Empty `advertiser_id` → `vertical`/`campaign_type` = `'none'`

~22% of rows are unfilled requests, which by definition have no advertiser, so
`advertiser_id` is `''` and the advertiser join produces nothing.

*Why label rather than leave blank or drop:* "unfilled traffic" becomes a
first-class segment the drill-down can name and explicitly rule out, instead of
a silent hole in the cube. `'none'` (no advertiser, correct by definition) is
kept distinct from `'unknown'` (join failed, a bug) so the two can never be
confused in a diagnosis.

## Schema notes

- Every dimension is `LowCardinality(String)` — the widest is `geo_device_id`
  at 5,000 distinct values, comfortably inside the ~10K guideline.
- `PARTITION BY toYYYYMM(event_time)` — the dataset spans 2 months, so 2
  partitions. Deliberately coarse; daily partitioning on 35 days of data would
  create many small parts for no pruning benefit.
- `ORDER BY event_time` — every RCA query is time-windowed first, so time is
  the selective prefix. Dimension filtering happens after the window narrows
  the scan.

## Verification

The load's final step prints, and these are the expected values for the
provided (non-unseen) dataset:

```
rows:          9000000
t0:            2026-06-01 00:00:00
t1:            2026-07-05 23:59:59
fills:         7027910
impressions:   6887058
clicks:        74940
revenue:       17020.36
unmatched_geo: 0
unmatched_app: 0
```

Every figure was cross-checked against an independent DuckDB read of the raw
parquet before loading, and matches.

Independent sanity check that the denormalized table preserves the signal — the
planted Android 15 fill-rate anomaly, computed in ClickHouse, reproduces the
DuckDB result exactly:

| `os_version` | baseline (Jun 16–18) | incident (Jun 23–25) |
|---|---|---|
| Android 15 | 0.7849 | **0.4333** |
| Android 13 | 0.7873 | 0.7827 |
| iOS 17.5 | 0.7879 | 0.7847 |

## Loading the unseen incident dataset

When the sealed dataset is released in the final hours:

1. Drop the new parquet/CSVs into a directory alongside the originals.
2. Point `DATA` in `load.sh` at it (or copy over the existing files).
3. Re-run — the script truncates and reloads.

**Nothing in the schema or the loader hardcodes a date.** The provided data
happens to span Jun 1 – Jul 5 2026; the unseen slice will not. Any baseline
logic built downstream must derive its windows from the data's own
`max(event_time)`, never from a literal.
