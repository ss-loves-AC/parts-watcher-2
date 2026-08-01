#!/usr/bin/env bash
# Load the InMobi problem package into ClickHouse Cloud.
# Usage: load/load.sh [path/to/creds.env]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-$HOME/.config/clickhouse/clickathon.env}"

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
ch --multiquery < "$ROOT/load/schema.sql"
ch --multiquery < "$ROOT/load/cube.sql"

echo "==> dimensions"
for t in apps advertisers geo_device; do
  ch --query "TRUNCATE TABLE rca.$t"
  ch --query "INSERT INTO rca.$t FORMAT CSVWithNames" < "$DATA/$t.csv"
  printf '    %-14s %s rows\n' "$t" "$(ch --query "SELECT count() FROM rca.$t")"
done

echo "==> ad_events_raw (9M rows, ~103MB parquet)"
ch --query "TRUNCATE TABLE rca.ad_events_raw"
ch --query "INSERT INTO rca.ad_events_raw FORMAT Parquet" \
   --max_insert_block_size 1000000 < "$DATA/ad_events.parquet"

echo "==> ad_events (denormalized) + segment_cube via MV"
# TRUNCATE on the source does NOT cascade to a materialized view's target table,
# so the cube must be cleared explicitly or a re-run double-counts every metric.
ch --query "TRUNCATE TABLE rca.ad_events"
ch --query "TRUNCATE TABLE rca.segment_cube"
ch --query "
INSERT INTO rca.ad_events
SELECT
    e.event_time,
    e.app_id,
    e.geo_device_id,
    e.advertiser_id,
    e.ad_format,
    ifNull(a.category, 'unknown')        AS category,
    ifNull(a.publisher_tier, 'unknown')  AS publisher_tier,
    -- advertiser_id is empty on unfilled requests: label rather than drop,
    -- so 'unfilled' is a first-class segment the drill-down can name.
    multiIf(e.advertiser_id = '', 'none', v.vertical = '', 'unknown', v.vertical)           AS vertical,
    multiIf(e.advertiser_id = '', 'none', v.campaign_type = '', 'unknown', v.campaign_type) AS campaign_type,
    ifNull(g.region, 'unknown')       AS region,
    ifNull(g.country, 'unknown')      AS country,
    ifNull(g.device_model, 'unknown') AS device_model,
    ifNull(g.os_version, 'unknown')   AS os_version,
    e.is_filled,
    e.is_impression,
    e.is_click,
    -- NOT toDecimal64(revenue, 6): that truncates the binary float toward zero
    -- (0.000123 stored as 0.000122999... -> 0.000122), a systematic downward
    -- bias worth ~$0.12 across the 9M rows. Round-tripping through the shortest
    -- decimal representation is exact. Source has at most 6 decimal places.
    CAST(toString(e.revenue) AS Decimal(18, 6)) AS revenue
FROM rca.ad_events_raw AS e
LEFT JOIN rca.apps        AS a ON a.app_id        = e.app_id
LEFT JOIN rca.advertisers AS v ON v.advertiser_id = e.advertiser_id
LEFT JOIN rca.geo_device  AS g ON g.geo_device_id = e.geo_device_id
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
    countIf(category = 'unknown')                 AS unmatched_app
FROM rca.ad_events
FORMAT Vertical"
