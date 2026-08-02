#!/usr/bin/env bash
# Load the unseen dataset, deciding for itself whether it CONTINUES the data
# we already have or REPLACES it.
#
# "A fresh slice of the same universe" is ambiguous, and the difference matters
# enormously:
#
#   CONTINUATION — the new events start after ours end. Combining gives the
#                  detector the full history behind them, so it baselines at
#                  rung 1 (same weekday, 3 weeks back). Strongest detection.
#
#   REPLACEMENT  — the new events overlap ours. Combining would double-count,
#                  so load them alone and accept whatever history they carry.
#
# Guessing wrong is expensive in both directions: combining an overlap corrupts
# every metric, and NOT combining a continuation throws away the history that
# makes detection work. So compare the ranges and let the data decide.
#
#   scripts/load-unseen.sh /path/to/unseen [target_db]
set -euo pipefail

DATA="${1:?usage: load-unseen.sh /path/to/unseen-dir [target_db]}"
DB="${2:-unseen}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CH_ENV:-$HOME/.config/clickhouse/clickathon.env}"
CH="${CH_CLIENT:-$HOME/Documents/projects/click/bin/clickhouse}"
BASE_DB="${BASE_DB:-pw}"

[[ -f "$DATA/ad_events.parquet" ]] || { echo "no ad_events.parquet in $DATA" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
ch() { "$CH" client --host "$CH_HOST" --port 9440 --secure \
        --user "$CH_USER" --password "$CH_PASSWORD" "$@"; }

echo "==> schema in $DB"
sed "s/{{DB}}/$DB/g" "$ROOT/load/schema.sql" | ch --multiquery
sed "s/{{DB}}/$DB/g" "$ROOT/load/detections.sql" | ch --multiquery

echo "==> staging the new events"
ch --query "TRUNCATE TABLE $DB.ad_events_raw"
ch --query "INSERT INTO $DB.ad_events_raw FORMAT Parquet" \
   --max_insert_block_size 1000000 < "$DATA/ad_events.parquet"

# Parquet inserts match columns by NAME, not position. A file whose timestamp
# column is named anything else leaves event_time at its 1970 default and the
# load "succeeds" with every row unusable. Catch it before anything downstream.
EPOCH=$(ch --query "SELECT countIf(event_time < toDateTime('2000-01-01')) FROM $DB.ad_events_raw SETTINGS select_sequential_consistency=1")
if [[ "$EPOCH" -gt 0 ]]; then
  echo "FATAL: $EPOCH rows have event_time before 2000 — the parquet's timestamp" >&2
  echo "       column is probably not called 'event_time'. Columns found:" >&2
  ch --query "DESCRIBE TABLE $DB.ad_events_raw" | awk '{print "         " $1}' >&2
  exit 1
fi

NEW_MIN=$(ch --query "SELECT toString(min(event_time)) FROM $DB.ad_events_raw SETTINGS select_sequential_consistency=1")
NEW_MAX=$(ch --query "SELECT toString(max(event_time)) FROM $DB.ad_events_raw SETTINGS select_sequential_consistency=1")
NEW_N=$(ch --query   "SELECT count() FROM $DB.ad_events_raw SETTINGS select_sequential_consistency=1")
OLD_MIN=$(ch --query "SELECT toString(min(event_time)) FROM $BASE_DB.ad_events_raw")
OLD_MAX=$(ch --query "SELECT toString(max(event_time)) FROM $BASE_DB.ad_events_raw")
OLD_N=$(ch --query   "SELECT count() FROM $BASE_DB.ad_events_raw")

echo "    existing : $OLD_MIN .. $OLD_MAX   ($OLD_N rows)"
echo "    new      : $NEW_MIN .. $NEW_MAX   ($NEW_N rows)"

DISJOINT=$(ch --query "SELECT toDateTime('$NEW_MIN') > toDateTime('$OLD_MAX')")

if [[ "$DISJOINT" == "1" ]]; then
  echo "==> CONTINUATION — new events begin after ours end; combining for history"
  ch --query "
    INSERT INTO $DB.ad_events_raw
    SELECT * FROM $BASE_DB.ad_events_raw"
  MODE=continuation
else
  echo "==> REPLACEMENT — ranges overlap; loading the new events alone"
  echo "    (combining would double-count the overlap)"
  MODE=replacement
fi

echo "==> dimensions"
for t in apps advertisers geo_device; do
  ch --query "TRUNCATE TABLE $DB.$t"
  ch --query "INSERT INTO $DB.$t FORMAT CSVWithNames" < "$DATA/$t.csv"
  n=$(ch --query "SELECT count() FROM $DB.$t SETTINGS select_sequential_consistency=1")
  [[ "$n" -gt 0 ]] || { echo "FATAL: $DB.$t loaded 0 rows" >&2; exit 1; }
  printf '    %-14s %s rows\n' "$t" "$n"
done

echo "==> cube + denormalized fact"
sed "s/{{DB}}/$DB/g" "$ROOT/load/cube.sql" | ch --multiquery
ch --query "TRUNCATE TABLE $DB.ad_events"
ch --query "TRUNCATE TABLE $DB.segment_cube"
ch --query "
INSERT INTO $DB.ad_events
SELECT
    e.event_time, e.app_id, e.geo_device_id, e.advertiser_id, e.ad_format,
    if(a.app_id = '', 'unknown', a.category)       AS category,
    if(a.app_id = '', 'unknown', a.publisher_tier) AS publisher_tier,
    multiIf(e.advertiser_id = '', 'none', v.vertical = '', 'unknown', v.vertical),
    multiIf(e.advertiser_id = '', 'none', v.campaign_type = '', 'unknown', v.campaign_type),
    if(g.geo_device_id = '', 'unknown', g.region),
    if(g.geo_device_id = '', 'unknown', g.country),
    if(g.geo_device_id = '', 'unknown', g.device_model),
    if(g.geo_device_id = '', 'unknown', g.os_version),
    e.is_filled, e.is_impression, e.is_click,
    CAST(toString(e.revenue) AS Decimal(18, 6))
FROM $DB.ad_events_raw AS e
LEFT JOIN $DB.apps        AS a ON a.app_id        = e.app_id
LEFT JOIN $DB.advertisers AS v ON v.advertiser_id = e.advertiser_id
LEFT JOIN $DB.geo_device  AS g ON g.geo_device_id = e.geo_device_id
SETTINGS join_algorithm = 'parallel_hash'"

echo "==> verify"
ch --query "
SELECT count() AS rows, min(event_time) AS t0, max(event_time) AS t1,
       countIf(region='unknown') AS unmatched_geo,
       countIf(category='unknown') AS unmatched_app,
       uniqExact(os_version) AS distinct_os, uniqExact(country) AS distinct_country
FROM $DB.ad_events FORMAT Vertical SETTINGS select_sequential_consistency=1"
ch --query "
SELECT throwIf(count() > 0, 'FATAL: a dimension collapsed in segment_cube')
FROM (SELECT dim_name, uniqExact(dim_value) v FROM $DB.segment_cube
      WHERE dim_name != '__total__' GROUP BY dim_name HAVING v < 2)
SETTINGS select_sequential_consistency=1"

echo
echo "MODE=$MODE   next:  CH_DB=$DB python3 -m engine.run --out out/unseen"
