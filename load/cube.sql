-- Click-a-thon 2026 · InMobi track — the segment cube
--
-- One pre-aggregated table covering EVERY dimension, keyed by
-- (hour, dim_name, dim_value). Each ad event is fanned out via ARRAY JOIN into
-- one row per dimension it belongs to, plus one '__total__' row carrying the
-- global figures for the same hour.
--
-- Why this shape: the drill-down asks the same question of every dimension
-- ("which value of X explains the move?"). With a cube keyed by dim_name, that
-- is ONE parameterised query template instead of one query per dimension, and
-- adding a dimension later means adding one line to the array below — no new
-- table, no new query. The '__total__' rows sit in the same table so a segment
-- and its global baseline are read in a single scan, which is what the
-- uniformity test needs (see docs/DESIGN.md).
--
-- Only additive measures are stored. Every ratio in the metrics glossary
-- (fill rate, render rate, CTR, eCPM, RPR) is sum/sum over these five, so the
-- cube is closed under rollup and ratios stay correct at any granularity —
-- exactly what the glossary demands ("never as an average of per-row or
-- per-day ratios").

CREATE TABLE IF NOT EXISTS {{DB}}.segment_cube
(
    bucket      DateTime,                                    -- hour
    dim_name    LowCardinality(String),
    dim_value   LowCardinality(String),
    requests    SimpleAggregateFunction(sum, UInt64),
    fills       SimpleAggregateFunction(sum, UInt64),
    impressions SimpleAggregateFunction(sum, UInt64),
    clicks      SimpleAggregateFunction(sum, UInt64),
    revenue     SimpleAggregateFunction(sum, Decimal(38, 6))
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(bucket)
-- Ordering is low-to-high cardinality: dim_name (12) < bucket (840) <
-- dim_value (2561), per schema-pk-cardinality-order. It also puts the
-- detector's equality filter (dim_name='__total__') on the key prefix, per
-- schema-pk-prioritize-filters. Measured against the obvious (bucket,
-- dim_name, dim_value) alternative on the two real query shapes:
--   detector   3,018,832 -> 40,960 rows read  (74x less)
--   full scan    606,208 -> 402,399 rows read (30.5ms -> 9.5ms)
-- ORDER BY is immutable, so changing this later means recreating the table.
ORDER BY (dim_name, bucket, dim_value);

-- Incremental MV: fires on every INSERT into {{DB}}.ad_events, so a streaming
-- feed stays current with no rebuild. AggregatingMergeTree merges the partial
-- blocks in the background — queries must therefore always aggregate
-- (sum(...) ... GROUP BY), never read a row and trust it to be final.

CREATE MATERIALIZED VIEW IF NOT EXISTS {{DB}}.segment_cube_mv TO {{DB}}.segment_cube AS
SELECT
    toStartOfHour(event_time)     AS bucket,
    dim.1                         AS dim_name,
    dim.2                         AS dim_value,
    count()                       AS requests,
    sum(is_filled)                AS fills,
    sum(is_impression)            AS impressions,
    sum(is_click)                 AS clicks,
    sum(revenue)                  AS revenue
FROM {{DB}}.ad_events
ARRAY JOIN
[
    ('__total__',      'all'),
    ('ad_format',      toString(ad_format)),
    ('category',       toString(category)),
    ('publisher_tier', toString(publisher_tier)),
    ('vertical',       toString(vertical)),
    ('campaign_type',  toString(campaign_type)),
    ('region',         toString(region)),
    ('country',        toString(country)),
    ('device_model',   toString(device_model)),
    ('os_version',     toString(os_version)),
    ('app_id',         toString(app_id)),
    ('advertiser_id',  toString(advertiser_id))
] AS dim
GROUP BY bucket, dim_name, dim_value;
