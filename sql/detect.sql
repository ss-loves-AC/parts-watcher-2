-- Detector: which (metric, hour) pairs deviate from a like-for-like baseline?
--
-- Answers only "did something move, and when?" — never "who caused it".
-- Attribution is the segment scan's job; keeping them apart is what lets the
-- seasonal verdict discard weekend dips before any expensive drill-down runs.
--
-- Params: grain_hours (1 = hourly, 24 = daily), lags (history depth),
--         period_hours (168 = same weekday, 24 = same hour-of-day),
--         min_hist, threshold (wobbles), min_effect,
--         excl_dates (days to keep OUT of the baseline history),
--         as_of (pretend the data ends here — see engine/replay.py)
--
-- No date literal appears anywhere in this file. Every window is relative to
-- the data's own buckets, so the unseen slice works untouched.
--
-- ---------------------------------------------------------------------------
-- Two measurement decisions, both learned the hard way (v1 produced 66
-- candidates against 4 real movements):
--
-- 1. WORK IN RATIO SPACE, NOT DIFFERENCE SPACE.
--    The data has a slow growth trend, so a baseline drawn from 1-3 weeks ago
--    sits systematically below today. In difference space every hour looks
--    mildly "up" and the detector fires constantly. The ratio actual/expected
--    has the trend as a near-constant offset, which the median absorbs.
--
-- 2. RUN AT MORE THAN ONE TIME SCALE.
--    A movement can be small per hour and undeniable per day. The eCPM
--    incident is -2.5% for four days, but hourly eCPM noise is 1.4%, so no
--    single hour clears the bar — measured peak was 3.3 wobbles against a
--    threshold of 4, a miss. Aggregated daily, the noise averages down and the
--    same shift is obvious. Persistence IS the evidence; looking only at hours
--    throws it away.
--
-- 3. AN ANOMALY MUST NOT POISON LATER BASELINES.
--    The Jun 21 collapse sits in the history of Jun 28 and Jul 5 (same
--    weekday, 7 and 14 days on). It drags their expected value down, so two
--    perfectly normal Sundays got reported as spikes. Pass 1 finds anomalous
--    days; pass 2 re-runs with those days excluded from history via
--    excl_dates. Detecting an incident and then quietly believing it was
--    normal is how a detector manufactures its own false positives.
--
-- 4. ESTIMATE THE SCALE GLOBALLY, NOT PER BUCKET.
--    Three weeks x three adjacent hours is ~3 independent samples, and MAD of
--    3 points badly underestimates spread. Measured: MAD said 0.0222 for an
--    hour whose true spread was 0.65 — 20x too small, so a 3% move scored 26
--    wobbles. The spread of the ratio across the whole series (~800 buckets
--    per metric) is a stable estimate of what "normal" movement looks like.
-- ---------------------------------------------------------------------------

WITH
    -- Where the data actually starts and ends. The first and last periods are
    -- almost always partial — a slice cut at 23:59:59 opens with one second of
    -- traffic — and a partial period used as a baseline produces impossible
    -- figures (measured: -124% on a 6-day slice, and +15,000,000% on a 14-day
    -- one). Counting source rows catches this for daily buckets but NOT for
    -- hourly, where "one source row" is trivially satisfied. So drop the edge
    -- periods outright: one bucket at each end is a cheap price.
    bounds AS
    (
        SELECT min(bucket) AS lo, max(bucket) AS hi
        FROM {db:Identifier}.segment_cube
        WHERE dim_name = '__total__' AND bucket < {as_of:DateTime}
    ),

    -- The global series. One scan of the __total__ rows: with the cube ordered
    -- (dim_name, bucket, dim_value) this touches ~40K rows, not the whole cube.
    totals AS
    (
        SELECT
            -- NB: alias must NOT be `bucket`. Aliasing the truncated value
            -- back to the source column name makes uniqExact(bucket) resolve
            -- to the alias and return 1 for every group, which silently
            -- deletes the entire daily grain.
            toStartOfInterval(bucket, INTERVAL {grain_hours:UInt16} HOUR) AS grain_bucket,
            uniqExact(bucket)       AS hours_present,
            sum(requests)           AS requests,
            sum(fills)              AS fills,
            sum(impressions)        AS impressions,
            sum(clicks)             AS clicks,
            toFloat64(sum(revenue)) AS revenue
        FROM {db:Identifier}.segment_cube
        WHERE dim_name = '__total__'
          -- Replay cutoff. Everything downstream already derives its windows
          -- from the data, so capping the input here is all it takes to make
          -- the detector see the world as it looked at a past moment.
          AND bucket < {as_of:DateTime}
        GROUP BY grain_bucket
        -- Only COMPLETE buckets. A slice that begins mid-day leaves a partial
        -- first bucket holding a few seconds of traffic; used as a baseline it
        -- makes the next week look like a 15,000,000% increase. Found by the
        -- holdout rehearsal, where the export cut at 23:59:59 and the opening
        -- daily bucket held one second. A daily bucket needs 24 hourly rows,
        -- an hourly bucket needs 1; anything short is a boundary artifact.
        HAVING hours_present = {grain_hours:UInt16}
           AND grain_bucket > toStartOfInterval(
                   (SELECT lo FROM bounds), INTERVAL {grain_hours:UInt16} HOUR)
           AND grain_bucket < toStartOfInterval(
                   (SELECT hi FROM bounds), INTERVAL {grain_hours:UInt16} HOUR)
    ),

    -- Unpivot to (bucket, metric, value) so one baseline computation covers
    -- every metric — the same trick the cube uses for dimensions.
    -- Ratios are sum/sum within the bucket, per the metrics glossary.
    series AS
    (
        SELECT
            grain_bucket AS bucket,
            m.1 AS metric,
            m.2 AS value
        FROM totals
        ARRAY JOIN
        [
            ('requests',    toFloat64(requests)),
            ('fill_rate',   if(requests    > 0, fills / requests,              0)),
            ('render_rate', if(fills       > 0, impressions / fills,           0)),
            ('ctr',         if(impressions > 0, clicks / impressions,          0)),
            ('ecpm',        if(impressions > 0, revenue / impressions * 1000,  0)),
            ('revenue',     revenue)
        ] AS m
    ),

    -- Like-for-like history: same weekday, same hour (168h = 1 week), plus the
    -- hour either side. Keeps the comparison inside "same time of day, same day
    -- of week", which is what makes weekend seasonality cancel instead of alarm.
    probes AS
    (
        SELECT
            bucket,
            metric,
            value,
            -- period_hours is the seasonal cycle we step back through: 168h
            -- (same weekday, same hour) when there is a week of history to
            -- draw on, 24h (same hour of day) when the slice is too short for
            -- that. The second is weaker — it cannot tell a Sunday from a
            -- Tuesday — which is exactly why the rung is reported alongside
            -- the diagnosis rather than hidden.
            --
            -- Hourly also takes the hour either side, for 3 samples per step
            -- back. A daily bucket has no adjacent-hour concept, so one each.
            arrayJoin(arrayFlatten(arrayMap(
                k -> if({grain_hours:UInt16} = 1,
                        [-(k * {period_hours:UInt16}) - 1,
                         -(k * {period_hours:UInt16}),
                         -(k * {period_hours:UInt16}) + 1],
                        [-(k * {period_hours:UInt16})]),
                range(1, {lags:UInt8} + 1)
            ))) AS off_h
        FROM series
    ),

    joined AS
    (
        SELECT
            p.bucket AS bucket,
            p.metric AS metric,
            p.value  AS actual,
            h.value  AS hist
        FROM probes AS p
        INNER JOIN series AS h
            ON  h.metric = p.metric
            AND h.bucket = p.bucket + toIntervalHour(p.off_h)
        -- Known-bad days never serve as anyone's idea of normal.
        WHERE NOT has({excl_dates:Array(Date)}, toDate(h.bucket))
    ),

    -- Expected value, and the ratio of actual to it. See decision (1) above.
    per_bucket AS
    (
        SELECT
            bucket,
            metric,
            any(actual)                             AS actual,
            count()                                 AS n_hist,
            arrayReduce('median', groupArray(hist)) AS expected,
            if(expected > 0, actual / expected, 1.0) AS ratio
        FROM joined
        GROUP BY bucket, metric
        HAVING n_hist >= {min_hist:UInt8}
    ),

    -- How does that ratio normally behave, across the whole series? Median
    -- absorbs the growth trend; MAD measures ordinary movement. See decision
    -- (2) above. Floored so a pathologically flat metric can't divide by zero.
    scale AS
    (
        SELECT
            metric,
            arrayReduce('median', groupArray(ratio)) AS typical_ratio,
            greatest(
                arrayReduce('median', arrayMap(x -> abs(x - typical_ratio), groupArray(ratio))) * 1.4826,
                0.0005
            ) AS wobble
        FROM per_bucket
        GROUP BY metric
    )

SELECT
    b.bucket                                   AS bucket,
    b.metric                                   AS metric,
    b.actual                                   AS actual,
    b.expected * s.typical_ratio               AS expected,
    b.n_hist                                   AS n_hist,
    -- Relative change against the trend-adjusted expectation. NOT
    -- (ratio - typical_ratio): that is a difference of two ratios, not a
    -- percentage change, and it can report a drop worse than -100%, which is
    -- impossible for a non-negative metric. Measured -125% on a short slice
    -- before this was corrected.
    b.ratio / s.typical_ratio - 1              AS effect,
    s.wobble                                   AS wobble,
    (b.ratio - s.typical_ratio) / s.wobble     AS wobbles
FROM per_bucket AS b
INNER JOIN scale AS s ON s.metric = b.metric
-- Two independent gates. Statistical: is this beyond ordinary movement?
-- Practical: is it big enough for a human to care? A 0.3% shift can be
-- statistically undeniable and still not worth an alert.
WHERE (abs(wobbles) >= {threshold:Float64})
  AND (abs(effect)  >= {min_effect:Float64})
ORDER BY metric ASC, bucket ASC
