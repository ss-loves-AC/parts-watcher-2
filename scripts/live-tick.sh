#!/usr/bin/env bash
# Replay historical events into "now", so the stack has a live stream.
#
# The provided dataset ends 2026-07-05. Any alert evaluating "the last hour"
# therefore sees zero rows forever — the wiring can be perfect and still never
# fire. This makes the data current instead of pretending it is.
#
# Each tick copies one minute of historical traffic and shifts its timestamps
# to the present, so `pw_live.ad_events` always has fresh rows. The shift is a
# whole number of WEEKS, which keeps hour-of-day and day-of-week intact — the
# seasonality the detector depends on survives the move.
#
#   scripts/live-tick.sh              one minute of normal traffic
#   scripts/live-tick.sh --break-fill reproduce the Android 15 fill collapse
#
# Run it on a loop for a live demo:
#   while true; do scripts/live-tick.sh; sleep 60; done
set -euo pipefail

BREAK=0
[[ "${1:-}" == "--break-fill" ]] && BREAK=1

ENV_FILE="${CH_ENV:-$HOME/.config/clickhouse/clickathon.env}"
CH="${CH_CLIENT:-$HOME/Documents/projects/click/bin/clickhouse}"
SRC_DB="${SRC_DB:-pw}"
LIVE_DB="${LIVE_DB:-pw_live}"
# shellcheck disable=SC1090
source "$ENV_FILE"
ch() { "$CH" client --host "$CH_HOST" --port 9440 --secure \
        --user "$CH_USER" --password "$CH_PASSWORD" "$@"; }

ch --query "CREATE DATABASE IF NOT EXISTS $LIVE_DB"
ch --query "
CREATE TABLE IF NOT EXISTS $LIVE_DB.ad_events AS $SRC_DB.ad_events
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(event_time)
ORDER BY event_time
-- Rolling window only. This is a demo stream, not a second copy of the
-- dataset; without a TTL it would grow without bound.
TTL event_time + INTERVAL 2 DAY"

# Whole weeks between the end of the data and now, so weekday and hour align.
WEEKS=$(ch --query "
SELECT toUInt32(ceil(dateDiff('day', max(event_time), now()) / 7.0))
FROM $SRC_DB.ad_events_raw")

# Take the minute of history that maps onto the current minute after shifting.
ch --query "
INSERT INTO $LIVE_DB.ad_events
SELECT
    -- NOT 'AS event_time': aliasing the shifted value back to the source
    -- column name makes the WHERE below resolve to the SHIFTED timestamp, so
    -- the window matches nothing and the insert silently writes zero rows.
    -- Same alias-shadowing trap as toStartOfInterval(bucket) AS bucket in
    -- sql/detect.sql — it fails quietly both times.
    event_time + INTERVAL $WEEKS WEEK,
    app_id, geo_device_id, advertiser_id, ad_format, category, publisher_tier,
    vertical, campaign_type, region, country, device_model, os_version,
    -- --break-fill reproduces the planted incident live: Android 15 stops
    -- filling. Everything else is untouched, so the segment scan has a real
    -- culprit to find rather than a synthetic one.
    if($BREAK = 1 AND os_version = 'Android 15', 0, is_filled) AS is_filled,
    if($BREAK = 1 AND os_version = 'Android 15', 0, is_impression) AS is_impression,
    if($BREAK = 1 AND os_version = 'Android 15', 0, is_click) AS is_click,
    if($BREAK = 1 AND os_version = 'Android 15', toDecimal64(0, 6), revenue) AS revenue
FROM $SRC_DB.ad_events
WHERE event_time >= toStartOfMinute(now()) - INTERVAL $WEEKS WEEK
  AND event_time <  toStartOfMinute(now()) - INTERVAL $WEEKS WEEK + INTERVAL 1 MINUTE"

ch --query "
SELECT
    '$([[ $BREAK == 1 ]] && echo BROKEN || echo normal)' AS tick,
    count()                                             AS rows_last_5min,
    round(sum(is_filled) / count(), 4)                  AS fill_rate,
    countIf(is_filled = 0)                              AS unfilled
FROM $LIVE_DB.ad_events
WHERE event_time >= now() - INTERVAL 5 MINUTE"
