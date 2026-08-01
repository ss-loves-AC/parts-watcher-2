-- Click-a-thon 2026 · InMobi track — base schema
-- Raw source-faithful tables + one denormalized fact table.

CREATE DATABASE IF NOT EXISTS {{DB}};

-- ---------- dimension tables (source-faithful) ----------

CREATE TABLE IF NOT EXISTS {{DB}}.apps
(
    app_id         LowCardinality(String),
    category       LowCardinality(String),
    publisher_tier LowCardinality(String)
)
ENGINE = MergeTree
ORDER BY app_id;

CREATE TABLE IF NOT EXISTS {{DB}}.advertisers
(
    advertiser_id LowCardinality(String),
    vertical      LowCardinality(String),
    campaign_type LowCardinality(String)
)
ENGINE = MergeTree
ORDER BY advertiser_id;

CREATE TABLE IF NOT EXISTS {{DB}}.geo_device
(
    geo_device_id LowCardinality(String),
    region        LowCardinality(String),
    country       LowCardinality(String),
    device_model  LowCardinality(String),
    os_version    LowCardinality(String)
)
ENGINE = MergeTree
ORDER BY geo_device_id;

-- ---------- raw fact (exactly as shipped) ----------

CREATE TABLE IF NOT EXISTS {{DB}}.ad_events_raw
(
    event_time    DateTime,
    app_id        LowCardinality(String),
    geo_device_id LowCardinality(String),
    advertiser_id LowCardinality(String),   -- empty on unfilled requests
    ad_format     LowCardinality(String),
    is_filled     UInt8,
    is_impression UInt8,
    is_click      UInt8,
    revenue       Float64
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY event_time;

-- ---------- denormalized fact (what the RCA engine queries) ----------
-- Dimensions folded in at load time: the drill-down never joins.
-- revenue is Decimal so sums are bit-for-bit reproducible regardless of
-- parallel merge order — the rubric penalises a single irreproducible figure.

CREATE TABLE IF NOT EXISTS {{DB}}.ad_events
(
    event_time     DateTime,
    app_id         LowCardinality(String),
    geo_device_id  LowCardinality(String),
    advertiser_id  LowCardinality(String),
    ad_format      LowCardinality(String),
    category       LowCardinality(String),
    publisher_tier LowCardinality(String),
    vertical       LowCardinality(String),
    campaign_type  LowCardinality(String),
    region         LowCardinality(String),
    country        LowCardinality(String),
    device_model   LowCardinality(String),
    os_version     LowCardinality(String),
    is_filled      UInt8,
    is_impression  UInt8,
    is_click       UInt8,
    revenue        Decimal(18, 6)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY event_time;
