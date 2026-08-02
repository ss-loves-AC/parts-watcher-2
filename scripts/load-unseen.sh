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
# ---------------------------------------------------------------------------
# EACH ERA KEEPS ITS OWN ATTRIBUTION. The subtlety that cost us a whole run.
#
# The spec ships regenerated dimension CSVs: same IDs, different attribute
# values. It warns that joining NEW events to OLD dimensions gives wrong
# segments. The mirror of that is just as wrong and far less obvious: joining
# OLD events to NEW dimensions.
#
# We did exactly that — truncated ad_events and re-joined all 10.5M rows
# (history included) against the new CSVs. The ID -> attribute map turned out
# to be a uniform reshuffle, so every historical event got a random label:
#
#   os_version fill rate, Jun 23-25    true      re-attributed
#     Android 15                       0.4333    0.7000
#     Android 14                       0.7835    0.7594
#     iOS 18.1                         0.7848    0.7549
#
# A textbook localized incident smeared into a flat band. The detector called
# it "global" — correctly, on data that was wrong. Worse, every segment's
# baseline collapsed toward the population mean, so real July structure then
# read as a huge deviation against it: region MEA "fell" 2.875 -> 1.118 when
# MEA's eCPM had been 1.134 all along and nothing had happened to it.
#
# So: new events join the new CSVs, history is carried over ALREADY
# denormalized, and the two are never re-attributed. Segment semantics survive
# the seam even though the IDs behind them do not — MEA is still the low-eCPM
# region on both sides — which is what makes the baseline comparable at all.
# ---------------------------------------------------------------------------
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
  echo "    history is carried over already denormalized, NOT re-joined (see header)"
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

# Did the regeneration actually change the mapping? Cheap to ask, and the
# answer decides whether the history may be re-attributed at all. Agreement at
# chance level (1/n_values) means a reshuffle; near 1.0 means the CSVs are the
# same tables and either attribution would do.
if [[ "$MODE" == "continuation" ]]; then
  echo "==> seam check — did the regeneration move the ID -> attribute map?"
  ch --query "
    SELECT
        round(avg(p.os_version = u.os_version), 4)   AS os_agreement,
        round(avg(p.country    = u.country),    4)   AS country_agreement,
        round(1.0 / uniqExact(u.os_version),    4)   AS chance_level
    FROM $BASE_DB.geo_device AS p
    INNER JOIN $DB.geo_device AS u USING (geo_device_id)
    FORMAT Vertical SETTINGS select_sequential_consistency = 1"
  echo "    at chance level the eras are different universes — hence per-era attribution"
fi

echo "==> cube + denormalized fact"
sed "s/{{DB}}/$DB/g" "$ROOT/load/cube.sql" | ch --multiquery
ch --query "TRUNCATE TABLE $DB.ad_events"
ch --query "TRUNCATE TABLE $DB.segment_cube"

# The NEW events only, against the NEW dimensions. ad_events_raw deliberately
# still holds nothing but the new slice, so this join cannot reach history.
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

# History, carried over with the attribution it was loaded under. The MV on
# ad_events fires per INSERT, so the cube picks up both eras without a rebuild.
if [[ "$MODE" == "continuation" ]]; then
  echo "    + history from $BASE_DB.ad_events (original attribution, not re-joined)"
  ch --query "INSERT INTO $DB.ad_events SELECT * FROM $BASE_DB.ad_events"
fi

echo "==> verify"
ch --query "
SELECT count() AS rows, min(event_time) AS t0, max(event_time) AS t1,
       countIf(region='unknown') AS unmatched_geo,
       countIf(category='unknown') AS unmatched_app,
       uniqExact(os_version) AS distinct_os, uniqExact(country) AS distinct_country
FROM $DB.ad_events FORMAT Vertical SETTINGS select_sequential_consistency=1"

# Per-era, so an attribution mistake shows as a level shift instead of hiding.
# eCPM by region is the sharpest probe: it is strongly region-dependent, so if
# history has been re-attributed the two eras converge on the population mean.
if [[ "$MODE" == "continuation" ]]; then
  echo "    eCPM by region per era — these should track, not converge:"
  ch --query "
    SELECT region,
           round(sumIf(revenue, event_time <= '$OLD_MAX') /
                 nullIf(sumIf(is_impression, event_time <= '$OLD_MAX'), 0) * 1000, 3) AS history,
           round(sumIf(revenue, event_time >  '$OLD_MAX') /
                 nullIf(sumIf(is_impression, event_time >  '$OLD_MAX'), 0) * 1000, 3) AS new_slice
    FROM $DB.ad_events GROUP BY region ORDER BY region
    FORMAT PrettyCompact SETTINGS select_sequential_consistency = 1"
fi
ch --query "
SELECT throwIf(count() > 0, 'FATAL: a dimension collapsed in segment_cube')
FROM (SELECT dim_name, uniqExact(dim_value) v FROM $DB.segment_cube
      WHERE dim_name != '__total__' GROUP BY dim_name HAVING v < 2)
SETTINGS select_sequential_consistency=1"

echo
echo "MODE=$MODE   next:  CH_DB=$DB python3 -m engine.run --out out/unseen"
