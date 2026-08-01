#!/usr/bin/env bash
# Load the InMobi problem package into ClickHouse Cloud.
# Usage: load/load.sh [path/to/creds.env]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-$HOME/.config/clickhouse/clickathon.env}"

# Database is a variable, not a constant. `rca` is shared with a teammate and
# their test rows extended max(event_time) past the dataset end, which the
# detector correctly read as a -103% collapse and which buried every real
# movement. A pipeline must not read a table other people mutate.
DB="${CH_DB:-pw}"

# The problem package (587MB of Git LFS) and the ClickHouse client binary
# (664MB) deliberately live OUTSIDE this repo. Override either with an env var
# — DATA_DIR is what you repoint when the unseen incident dataset lands.
DATA="${DATA_DIR:-$HOME/Documents/projects/click/click-a-thon-2026/InMobi/data}"
CH="${CH_CLIENT:-$HOME/Documents/projects/click/bin/clickhouse}"

[[ -f "$ENV_FILE" ]] || { echo "missing creds file: $ENV_FILE" >&2; exit 1; }
[[ -d "$DATA" ]]     || { echo "missing data dir: $DATA (set DATA_DIR)" >&2; exit 1; }
[[ -x "$CH" ]]       || { echo "missing clickhouse client: $CH (set CH_CLIENT)" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${CH_HOST:?}" "${CH_USER:?}" "${CH_PASSWORD:?}"

ch() { "$CH" client --host "$CH_HOST" --port 9440 --secure \
        --user "$CH_USER" --password "$CH_PASSWORD" "$@"; }

echo "==> schema"
sed "s/{{DB}}/$DB/g" "$ROOT/load/schema.sql" | ch --multiquery
sed "s/{{DB}}/$DB/g" "$ROOT/load/cube.sql" | ch --multiquery

echo "==> dimensions"
for t in apps advertisers geo_device; do
  ch --query "TRUNCATE TABLE $DB.$t"
  ch --query "INSERT INTO $DB.$t FORMAT CSVWithNames" < "$DATA/$t.csv"
  # select_sequential_consistency: this service has 2 replicas, and a plain
  # SELECT straight after an INSERT can land on one that hasn't caught up and
  # report 0. Without it the assertion below fails at random.
  n=$(ch --query "SELECT count() FROM $DB.$t SETTINGS select_sequential_consistency = 1")
  # A transient network error once emptied geo_device here and the run carried
  # on: `set -e` does not fire on a failure inside a command substitution, and
  # every downstream check still passed. Assert explicitly.
  [[ "$n" -gt 0 ]] || { echo "FATAL: $DB.$t loaded 0 rows" >&2; exit 1; }
  printf '    %-14s %s rows\n' "$t" "$n"
done

echo "==> ad_events_raw (9M rows, ~103MB parquet)"
ch --query "TRUNCATE TABLE $DB.ad_events_raw"
ch --query "INSERT INTO $DB.ad_events_raw FORMAT Parquet" \
   --max_insert_block_size 1000000 < "$DATA/ad_events.parquet"

echo "==> ad_events (denormalized) + segment_cube via MV"
# TRUNCATE on the source does NOT cascade to a materialized view's target table,
# so the cube must be cleared explicitly or a re-run double-counts every metric.
ch --query "TRUNCATE TABLE $DB.ad_events"
ch --query "TRUNCATE TABLE $DB.segment_cube"
ch --query "
INSERT INTO $DB.ad_events
SELECT
    e.event_time,
    e.app_id,
    e.geo_device_id,
    e.advertiser_id,
    e.ad_format,
    -- NOT ifNull(): with join_use_nulls=0 (the default) an unmatched LEFT
    -- JOIN row yields the type's DEFAULT — empty string — never NULL. So
    -- ifNull() never fires, misses silently become '', and the unmatched
    -- counter below reads zero while every dimension is quietly empty.
    -- Test the join key instead. (best-practices: query-join-null-handling)
    if(a.app_id = '', 'unknown', a.category)       AS category,
    if(a.app_id = '', 'unknown', a.publisher_tier) AS publisher_tier,
    -- advertiser_id is empty on unfilled requests: label rather than drop,
    -- so 'unfilled' is a first-class segment the drill-down can name.
    multiIf(e.advertiser_id = '', 'none', v.vertical = '', 'unknown', v.vertical)           AS vertical,
    multiIf(e.advertiser_id = '', 'none', v.campaign_type = '', 'unknown', v.campaign_type) AS campaign_type,
    if(g.geo_device_id = '', 'unknown', g.region)       AS region,
    if(g.geo_device_id = '', 'unknown', g.country)      AS country,
    if(g.geo_device_id = '', 'unknown', g.device_model) AS device_model,
    if(g.geo_device_id = '', 'unknown', g.os_version)   AS os_version,
    e.is_filled,
    e.is_impression,
    e.is_click,
    -- NOT toDecimal64(revenue, 6): that truncates the binary float toward zero
    -- (0.000123 stored as 0.000122999... -> 0.000122), a systematic downward
    -- bias worth ~$0.12 across the 9M rows. Round-tripping through the shortest
    -- decimal representation is exact. Source has at most 6 decimal places.
    CAST(toString(e.revenue) AS Decimal(18, 6)) AS revenue
FROM $DB.ad_events_raw AS e
LEFT JOIN $DB.apps        AS a ON a.app_id        = e.app_id
LEFT JOIN $DB.advertisers AS v ON v.advertiser_id = e.advertiser_id
LEFT JOIN $DB.geo_device  AS g ON g.geo_device_id = e.geo_device_id
SETTINGS join_algorithm = 'parallel_hash'"

echo "==> verify"
ch --query "
SELECT
    count()                                       AS rows,
    min(event_time)                               AS t0,
    max(event_time)                               AS t1,
    sum(is_filled)                                AS fills,
    sum(is_impression)                            AS impressions,
    sum(is_click)                                 AS clicks,
    round(sum(revenue), 2)                        AS revenue,
    countIf(region   = 'unknown')                 AS unmatched_geo,
    countIf(category = 'unknown')                 AS unmatched_app,
    uniqExact(os_version)                         AS distinct_os,
    uniqExact(country)                            AS distinct_country,
    uniqExact(category)                           AS distinct_category
FROM $DB.ad_events
FORMAT Vertical
SETTINGS select_sequential_consistency = 1"

# Totals reconciling per dimension does NOT prove the dimension has values:
# a collapsed dimension still sums to 9M. Assert cardinality directly.
echo "==> cube integrity"
ch --query "
SELECT throwIf(
    count() > 0,
    'FATAL: dimension collapsed to a single value in segment_cube'
)
FROM (
    SELECT dim_name, uniqExact(dim_value) AS vals
    FROM $DB.segment_cube
    WHERE dim_name != '__total__'
    GROUP BY dim_name
    HAVING vals < 2
)
SETTINGS select_sequential_consistency = 1"
ch --query "
SELECT dim_name, uniqExact(dim_value) AS distinct_values, sum(requests) AS requests
FROM $DB.segment_cube GROUP BY dim_name ORDER BY dim_name
SETTINGS select_sequential_consistency = 1"
