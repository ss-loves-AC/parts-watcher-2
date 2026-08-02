-- What the detector found, as data.
--
-- This is what makes alerting honest. The previous alert counted rows matching
-- `os_version = 'Android 15' AND is_filled = 0` — which only works because we
-- already knew Android 15 was the culprit. For a system whose purpose is to
-- FIND culprits, that hard-codes the answer into the question, and it stays
-- silent if the unseen data breaks something else.
--
-- Instead the detector writes here, and the alert simply asks "did anything
-- get found?". No thresholds to tune: the baseline ladder and the robust
-- z-score already decide what counts as abnormal, and they do it per metric
-- rather than per hard-coded segment.
--
-- found_at is FIRST-seen, not last-seen. engine/watch.py inserts a row only if
-- (metric, window_start, grain) is absent, so re-running the detector over the
-- same window does not resurrect an old finding and re-fire the alert. That
-- exactly-once behaviour is the whole reason this is a plain MergeTree and not
-- a ReplacingMergeTree — a Replacing engine would refresh found_at on every
-- pass and alert forever on the same incident.

CREATE TABLE IF NOT EXISTS {{DB}}.detections
(
    found_at       DateTime,                 -- when we FIRST saw this movement
    metric         LowCardinality(String),
    window_start   DateTime,
    window_end     DateTime,
    grain          LowCardinality(String),
    direction      LowCardinality(String),
    peak_wobbles   Float64,                  -- how far past normal movement
    effect_pct     Float64,                  -- relative change, always > -100
    baseline_rung  LowCardinality(String),   -- which rung of the ladder fired
    source_db      LowCardinality(String),
    -- Filled in AFTER the investigation, so one row answers both "what moved"
    -- and "why". A reader should not have to join two places in their head.
    verdict        LowCardinality(String) DEFAULT '',
    cause          String DEFAULT '',
    explained_pct  Float64 DEFAULT 0,
    -- The narrated diagnosis itself, not just the segment. The brief asks for
    -- a "plain-language diagnosis ... with explicit statement of
    -- checked-but-ruled-out hypotheses"; `cause` alone is a segment
    -- identifier, which is the answer to a different question. Storing the
    -- prose here means the dashboard shows the diagnosis rather than a code,
    -- and one row still answers what moved, why, and what was ruled out.
    diagnosis      String DEFAULT ''
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(found_at)
-- Ordered for the two real queries: "what is new" (found_at first, and it is
-- also the alert's filter) and "have I seen this window" (the dedup check).
ORDER BY (found_at, metric, window_start);


-- Which HyperDX saved searches we have already created.
--
-- clickstack_save_saved_search creates a NEW record unless handed an id, and
-- the MCP offers no way to look one up by name — clickstack_get_saved_search
-- requires the id you are trying to find. So we keep the mapping ourselves.
-- Without it, four runs left twelve copies of three pins.
--
-- ReplacingMergeTree on name: re-pinning the same finding overwrites rather
-- than accumulating.
CREATE TABLE IF NOT EXISTS {{DB}}.pinned_views
(
    name       String,
    search_id  String,
    pinned_at  DateTime
)
ENGINE = ReplacingMergeTree(pinned_at)
ORDER BY name;
