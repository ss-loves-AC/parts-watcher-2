-- Every figure in diagnosis.md comes from these queries.
-- Parameters per incident are listed below; the SQL follows verbatim
-- so it can be re-run against the answer key.

-- request volume · Jun 21 · verdict=global
--   window     : 2026-06-21 00:00:00 -> 2026-06-22 00:00:00
--   database   : unseen
--   detect.sql : weeks=3 threshold=4.0 grain=daily+hourly
--   scan       : metric=requests min_z=4.0

-- fill rate · Jul 8–Jul 9 · verdict=partial
--   window     : 2026-07-08 00:00:00 -> 2026-07-10 00:00:00
--   database   : unseen
--   detect.sql : weeks=3 threshold=4.0 grain=daily+hourly
--   scan       : metric=fill_rate min_z=4.0

-- eCPM · Jul 6 00:00 to Jul 10 23:00 · verdict=partial
--   window     : 2026-07-06 00:00:00 -> 2026-07-10 23:00:00
--   database   : unseen
--   detect.sql : weeks=3 threshold=4.0 grain=daily+hourly
--   scan       : metric=ecpm min_z=4.0

-- fill rate · Jun 23–Jun 25 · verdict=localized
--   window     : 2026-06-23 00:00:00 -> 2026-06-26 00:00:00
--   database   : unseen
--   detect.sql : weeks=3 threshold=4.0 grain=daily+hourly
--   scan       : metric=fill_rate min_z=4.0

-- revenue · Jun 21 · verdict=global
--   window     : 2026-06-21 00:00:00 -> 2026-06-22 00:00:00
--   database   : unseen
--   detect.sql : weeks=3 threshold=4.0 grain=hourly+daily
--   scan       : metric=revenue min_z=4.0

-- revenue · Jul 9 · verdict=global
--   window     : 2026-07-09 00:00:00 -> 2026-07-10 00:00:00
--   database   : unseen
--   detect.sql : weeks=3 threshold=4.0 grain=hourly+daily
--   scan       : metric=revenue min_z=4.0


-- ===== counterfactual.sql =====
-- Counterfactual impact — what did this incident actually cost?
--
-- A diagnosis names a cause. This turns it into a number someone can act on:
--
--     "Had Android 15 fill held at its baseline, revenue would have been
--      $X higher over the window."
--
-- Method, deliberately the simplest defensible one: hold the accused segment's
-- REVENUE PER REQUEST at its baseline level and re-price the traffic it
-- actually received. Requests are the top of the funnel and were not what
-- moved, so counterfactual revenue is
--
--     requests_during  x  (revenue_baseline / requests_baseline)
--
-- and the impact is that minus what it actually earned.
--
-- Why revenue-per-request rather than walking the funnel (fill -> render ->
-- eCPM): the chain multiplies three estimates and invites argument about each.
-- Revenue per request is one ratio, computed sum/sum from the same rows as
-- everything else, and it captures the whole funnel by construction. A judge
-- can recompute it in one line.
--
-- The baseline is scaled by hours actually present, same as segment_scan.sql,
-- because a multi-week baseline is being compared against one window.
--
-- Params: dim, value, win_start, win_end, weeks

SELECT
    requests_during,
    revenue_baseline_per_request,
    revenue_counterfactual,
    revenue_actual,
    revenue_counterfactual - revenue_actual AS impact
FROM
(
    SELECT
        countIf(in_inc)                                    AS requests_during,
        toFloat64(sumIf(revenue, in_inc))                  AS revenue_actual,
        if(countIf(in_base) > 0,
           toFloat64(sumIf(revenue, in_base)) / countIf(in_base),
           0)                                              AS revenue_baseline_per_request,
        requests_during * revenue_baseline_per_request     AS revenue_counterfactual
    FROM
    (
        SELECT
            revenue,
            (event_time >= {win_start:DateTime}) AND (event_time < {win_end:DateTime}) AS in_inc,
            arrayExists(
                k -> (event_time >= {win_start:DateTime} - toIntervalHour(k * 168))
                 AND (event_time <  {win_end:DateTime}   - toIntervalHour(k * 168)),
                range(1, {weeks:UInt8} + 1)
            ) AS in_base
        FROM {db:Identifier}.ad_events
        WHERE multiIf(
                  {dim:String} = 'ad_format',      ad_format,
                  {dim:String} = 'category',       category,
                  {dim:String} = 'publisher_tier', publisher_tier,
                  {dim:String} = 'vertical',       vertical,
                  {dim:String} = 'campaign_type',  campaign_type,
                  {dim:String} = 'region',         region,
                  {dim:String} = 'country',        country,
                  {dim:String} = 'device_model',   device_model,
                  {dim:String} = 'os_version',     os_version,
                  {dim:String} = 'app_id',         app_id,
                  {dim:String} = 'advertiser_id',  advertiser_id,
                  '\0no_such_dimension\0'
              ) = {value:String}
          AND event_time >= {win_start:DateTime} - toIntervalHour({weeks:UInt8} * 168)
          AND event_time <  {win_end:DateTime}
    )
    WHERE in_inc OR in_base
)


-- ===== detect.sql =====
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

-- ---------------------------------------------------------------------------
-- A2/A4: contiguous flagged buckets are grouped into incidents HERE, not in
-- Python. Classic gaps-and-islands: mark each flagged bucket that starts a new
-- run, then take a running sum of those marks as the island id.
--
-- The two-pass baseline cleaning still runs as two invocations (the excluded
-- days from pass 1 feed pass 2 as a parameter), because a single query cannot
-- reference its own output as a filter without materialising it first — and
-- materialising costs more than the second round trip.
-- ---------------------------------------------------------------------------
, flagged AS
(
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
),

islands AS
(
    SELECT
        *,
        -- A new island starts when the previous flagged bucket for this metric
        -- is further back than the merge gap (or there is no previous one).
        sum(new_run) OVER (PARTITION BY metric ORDER BY bucket
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS island
    FROM
    (
        SELECT
            *,
            if(prev_bucket = toDateTime(0)
               OR dateDiff('hour', prev_bucket, bucket) > {merge_gap:UInt16}, 1, 0) AS new_run
        FROM
        (
            SELECT
                *,
                lagInFrame(bucket, 1, toDateTime(0)) OVER
                    (PARTITION BY metric ORDER BY bucket
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS prev_bucket
            FROM flagged
        )
    )
)

SELECT
    metric,
    min(bucket)                                             AS start,
    max(bucket)                                             AS end,
    addHours(max(bucket), {grain_hours:UInt16})             AS end_exclusive,
    count()                                                 AS buckets_flagged,
    -- Peak significance across the island, sign preserved.
    arrayElement(
        arraySort(x -> -abs(x), groupArray(wobbles)), 1)     AS peak_wobbles,
    avg(expected)                                           AS mean_expected,
    avg(actual)                                             AS mean_actual,
    avg(effect)                                             AS mean_effect,
    if(avg(actual) < avg(expected), 'down', 'up')            AS direction
FROM islands
GROUP BY metric, island
-- A single flagged hour is noise; a single flagged DAY is already a day of
-- evidence.
HAVING (count() >= {min_buckets:UInt8})
ORDER BY abs(peak_wobbles) DESC


-- ===== drill2.sql =====
-- Stage 3b — the second level, run only when the first does not explain enough.
--
-- The cube holds one row per (dimension, value), so it can find "country = JP"
-- but never "iOS 18.1 IN Japan". Real incidents are often an intersection:
--
--   reported   country = JP           fill 0.784 -> 0.776   explains ~47%
--   actually   JP x iOS 18.1          fill 0.787 -> 0.394   explains ~all
--   and        iOS 18.1 outside JP    -6.6%, mild
--
-- Neither dimension alone is the cause, which is precisely what a `partial`
-- verdict means. This drills INSIDE the accused segment and scans every other
-- dimension within it, so the residual has somewhere to go.
--
-- Deliberately not run for every incident. Two-dimension search over 11
-- dimensions is far more surface for a spurious result, and when one dimension
-- already explains the movement there is nothing left to find. The residual
-- decides whether to come here — evidence, not routine.
--
-- Params: metric, dim, value (the accused), win_start, win_end, weeks, min_requests

WITH
    scoped AS
    (
        SELECT
            arrayJoin([
                ('ad_format', toString(ad_format)), ('category', toString(category)),
                ('publisher_tier', toString(publisher_tier)), ('vertical', toString(vertical)),
                ('campaign_type', toString(campaign_type)), ('region', toString(region)),
                ('country', toString(country)), ('device_model', toString(device_model)),
                ('os_version', toString(os_version)), ('app_id', toString(app_id)),
                ('advertiser_id', toString(advertiser_id))
            ]) AS d,
            d.1 AS sub_dim,
            d.2 AS sub_value,
            event_time, is_filled, is_impression, is_click, revenue, in_inc, in_base
        FROM
        (
            SELECT
                *,
                (event_time >= {win_start:DateTime}) AND (event_time < {win_end:DateTime}) AS in_inc,
                arrayExists(
                    k -> (event_time >= {win_start:DateTime} - toIntervalHour(k * 168))
                     AND (event_time <  {win_end:DateTime}   - toIntervalHour(k * 168)),
                    range(1, {weeks:UInt8} + 1)
                ) AS in_base
            FROM {db:Identifier}.ad_events
            -- Everything below is INSIDE the accused segment.
            WHERE multiIf(
                      {dim:String} = 'ad_format',      ad_format,
                      {dim:String} = 'category',       category,
                      {dim:String} = 'publisher_tier', publisher_tier,
                      {dim:String} = 'vertical',       vertical,
                      {dim:String} = 'campaign_type',  campaign_type,
                      {dim:String} = 'region',         region,
                      {dim:String} = 'country',        country,
                      {dim:String} = 'device_model',   device_model,
                      {dim:String} = 'os_version',     os_version,
                      {dim:String} = 'app_id',         app_id,
                      {dim:String} = 'advertiser_id',  advertiser_id,
                      '\0no_such_dimension\0'
                  ) = {value:String}
              AND event_time >= {win_start:DateTime} - toIntervalHour({weeks:UInt8} * 168)
              AND event_time <  {win_end:DateTime}
        )
        WHERE (in_inc OR in_base) AND sub_dim != {dim:String}
    ),

    agg AS
    (
        SELECT
            sub_dim, sub_value,
            countIf(in_inc)                     AS i_requests,
            sumIf(is_filled, in_inc)            AS i_fills,
            sumIf(is_impression, in_inc)        AS i_impressions,
            sumIf(is_click, in_inc)             AS i_clicks,
            toFloat64(sumIf(revenue, in_inc))   AS i_revenue,
            countIf(in_base)                    AS b_requests,
            sumIf(is_filled, in_base)           AS b_fills,
            sumIf(is_impression, in_base)       AS b_impressions,
            sumIf(is_click, in_base)            AS b_clicks,
            toFloat64(sumIf(revenue, in_base))  AS b_revenue,
            -- Baseline spans several weeks against one incident window.
            uniqExactIf(toStartOfHour(event_time), in_inc)  AS i_hours,
            uniqExactIf(toStartOfHour(event_time), in_base) AS b_hours
        FROM scoped
        GROUP BY sub_dim, sub_value
    )

SELECT
    sub_dim,
    sub_value,
    i_requests AS incident_requests,
    baseline_value,
    incident_value,
    if(baseline_value > 0, incident_value / baseline_value - 1, 0) AS sub_change,
    -- Proportion metrics get the exact test; the rest fall back to volume.
    multiIf(
        {metric:String} = 'fill_rate',
            proportionsZTest(i_fills, b_fills, i_requests, b_requests, 0.95, 'pooled').1,
        {metric:String} = 'render_rate',
            proportionsZTest(i_impressions, b_impressions, i_fills, b_fills, 0.95, 'pooled').1,
        {metric:String} = 'ctr',
            proportionsZTest(i_clicks, b_clicks, i_impressions, b_impressions, 0.95, 'pooled').1,
        nan
    ) AS z
FROM
(
    SELECT
        *,
        if(b_hours > 0, i_hours / b_hours, 1.0) AS b_scale,
        multiIf(
            {metric:String} = 'requests',    toFloat64(b_requests) * b_scale,
            {metric:String} = 'fill_rate',   if(b_requests    > 0, b_fills / b_requests, 0),
            {metric:String} = 'render_rate', if(b_fills       > 0, b_impressions / b_fills, 0),
            {metric:String} = 'ctr',         if(b_impressions > 0, b_clicks / b_impressions, 0),
            {metric:String} = 'ecpm',        if(b_impressions > 0, b_revenue / b_impressions * 1000, 0),
            b_revenue * b_scale
        ) AS baseline_value,
        multiIf(
            {metric:String} = 'requests',    toFloat64(i_requests),
            {metric:String} = 'fill_rate',   if(i_requests    > 0, i_fills / i_requests, 0),
            {metric:String} = 'render_rate', if(i_fills       > 0, i_impressions / i_fills, 0),
            {metric:String} = 'ctr',         if(i_impressions > 0, i_clicks / i_impressions, 0),
            {metric:String} = 'ecpm',        if(i_impressions > 0, i_revenue / i_impressions * 1000, 0),
            i_revenue
        ) AS incident_value
    FROM agg
)
WHERE i_requests >= {min_requests:UInt64}
ORDER BY sub_change ASC
LIMIT 8


-- ===== refine.sql =====
-- Stage 3 — refinement. Does the accused segment FULLY explain the movement?
--
-- The segment scan returns shadows alongside the culprit: Galaxy S23 scored
-- -8.7% on the Android 15 incident purely because most Galaxy S23 devices run
-- Android 15. Naming both would be wrong; naming the shadow would be worse.
--
-- The test: remove a candidate and recompute. If the movement disappears, the
-- candidate explains it. If a residual survives, something else is going on.
--
-- Measured on the Android 15 incident:
--     all traffic            0.7852 -> 0.7508   the movement
--     excluding Android 15   0.7852 -> 0.7844   flat: fully explained
--
-- ---------------------------------------------------------------------------
-- ALL CANDIDATES IN ONE PASS.
--
-- This used to run once per candidate — six sequential queries, six full scans
-- of the incident + baseline window, ~18s for a five-incident report. The
-- candidate list is now passed as arrays and fanned out with arrayJoin, so
-- every candidate is evaluated in a SINGLE scan of ad_events.
--
-- Deviation says "unusual"; only the residual says "responsible". Because the
-- residual is what actually SELECTS the culprit rather than merely checking
-- one, it has to be cheap enough to run on every leading candidate.
-- ---------------------------------------------------------------------------
--
-- This runs on ad_events rather than the cube. The cube holds one row per
-- (dimension, value) so it cannot express "Galaxy S23 AND NOT Android 15" —
-- conditioning needs the fact table.
--
-- Params: metric, dims (Array), values (Array), win_start, win_end, weeks

SELECT
    cand_idx,
    dim,
    value,
    baseline_all,
    incident_all,
    baseline_without,
    incident_without,
    if(baseline_all > 0, incident_all / baseline_all - 1, 0)         AS change_all,
    if(baseline_without > 0, incident_without / baseline_without - 1, 0) AS change_without
FROM
(
    SELECT
        cand_idx,
        {dims:Array(String)}[cand_idx]   AS dim,
        {values:Array(String)}[cand_idx] AS value,

        -- "all" = accused + not-accused, summed back together. Same figure for
        -- every candidate, but computed per candidate so the two numbers being
        -- compared always come from identical filtering.
        multiIf(
            {metric:String} = 'requests',    toFloat64(sum(b_requests)),
            {metric:String} = 'fill_rate',   if(sum(b_requests) > 0, sum(b_fills) / sum(b_requests), 0),
            {metric:String} = 'render_rate', if(sum(b_fills) > 0, sum(b_impressions) / sum(b_fills), 0),
            {metric:String} = 'ctr',         if(sum(b_impressions) > 0, sum(b_clicks) / sum(b_impressions), 0),
            {metric:String} = 'ecpm',        if(sum(b_impressions) > 0, sum(b_revenue) / sum(b_impressions) * 1000, 0),
            sum(b_revenue)
        ) AS baseline_all,
        multiIf(
            {metric:String} = 'requests',    toFloat64(sum(i_requests)),
            {metric:String} = 'fill_rate',   if(sum(i_requests) > 0, sum(i_fills) / sum(i_requests), 0),
            {metric:String} = 'render_rate', if(sum(i_fills) > 0, sum(i_impressions) / sum(i_fills), 0),
            {metric:String} = 'ctr',         if(sum(i_impressions) > 0, sum(i_clicks) / sum(i_impressions), 0),
            {metric:String} = 'ecpm',        if(sum(i_impressions) > 0, sum(i_revenue) / sum(i_impressions) * 1000, 0),
            sum(i_revenue)
        ) AS incident_all,

        multiIf(
            {metric:String} = 'requests',    toFloat64(sumIf(b_requests, NOT accused)),
            {metric:String} = 'fill_rate',   if(sumIf(b_requests, NOT accused) > 0, sumIf(b_fills, NOT accused) / sumIf(b_requests, NOT accused), 0),
            {metric:String} = 'render_rate', if(sumIf(b_fills, NOT accused) > 0, sumIf(b_impressions, NOT accused) / sumIf(b_fills, NOT accused), 0),
            {metric:String} = 'ctr',         if(sumIf(b_impressions, NOT accused) > 0, sumIf(b_clicks, NOT accused) / sumIf(b_impressions, NOT accused), 0),
            {metric:String} = 'ecpm',        if(sumIf(b_impressions, NOT accused) > 0, sumIf(b_revenue, NOT accused) / sumIf(b_impressions, NOT accused) * 1000, 0),
            sumIf(b_revenue, NOT accused)
        ) AS baseline_without,
        multiIf(
            {metric:String} = 'requests',    toFloat64(sumIf(i_requests, NOT accused)),
            {metric:String} = 'fill_rate',   if(sumIf(i_requests, NOT accused) > 0, sumIf(i_fills, NOT accused) / sumIf(i_requests, NOT accused), 0),
            {metric:String} = 'render_rate', if(sumIf(i_fills, NOT accused) > 0, sumIf(i_impressions, NOT accused) / sumIf(i_fills, NOT accused), 0),
            {metric:String} = 'ctr',         if(sumIf(i_impressions, NOT accused) > 0, sumIf(i_clicks, NOT accused) / sumIf(i_impressions, NOT accused), 0),
            {metric:String} = 'ecpm',        if(sumIf(i_impressions, NOT accused) > 0, sumIf(i_revenue, NOT accused) / sumIf(i_impressions, NOT accused) * 1000, 0),
            sumIf(i_revenue, NOT accused)
        ) AS incident_without
    FROM
    (
        SELECT
            cand_idx,
            accused,
            countIf(in_inc)                    AS i_requests,
            sumIf(is_filled, in_inc)           AS i_fills,
            sumIf(is_impression, in_inc)       AS i_impressions,
            sumIf(is_click, in_inc)            AS i_clicks,
            toFloat64(sumIf(revenue, in_inc))  AS i_revenue,
            -- Baseline spans several weeks against one incident window, so the
            -- additive measures are scaled by the hours actually present. A
            -- 3-week lookback can reach before the data starts.
            countIf(in_base)                   * any(b_scale) AS b_requests,
            sumIf(is_filled, in_base)          * any(b_scale) AS b_fills,
            sumIf(is_impression, in_base)      * any(b_scale) AS b_impressions,
            sumIf(is_click, in_base)           * any(b_scale) AS b_clicks,
            toFloat64(sumIf(revenue, in_base)) * any(b_scale) AS b_revenue
        FROM
        (
            SELECT
                is_filled, is_impression, is_click, revenue, in_inc, in_base,
                (SELECT
                     if(b > 0, i / b, 1.0)
                 FROM
                 (
                     SELECT
                         uniqExactIf(toStartOfHour(event_time),
                             event_time >= {win_start:DateTime} AND event_time < {win_end:DateTime}) AS i,
                         uniqExactIf(toStartOfHour(event_time),
                             arrayExists(k -> event_time >= {win_start:DateTime} - toIntervalHour(k * 168)
                                          AND event_time <  {win_end:DateTime}   - toIntervalHour(k * 168),
                                 range(1, {weeks:UInt8} + 1))) AS b
                     FROM {db:Identifier}.ad_events
                     WHERE event_time >= {win_start:DateTime} - toIntervalHour({weeks:UInt8} * 168)
                       AND event_time <  {win_end:DateTime}
                 )) AS b_scale,
                -- Fan out: one row per candidate — every candidate evaluated
                -- in this single scan rather than one query each.
                arrayJoin(arrayMap(
                    i -> (i,
                          multiIf(
                              {dims:Array(String)}[i] = 'ad_format',      ad_format,
                              {dims:Array(String)}[i] = 'category',       category,
                              {dims:Array(String)}[i] = 'publisher_tier', publisher_tier,
                              {dims:Array(String)}[i] = 'vertical',       vertical,
                              {dims:Array(String)}[i] = 'campaign_type',  campaign_type,
                              {dims:Array(String)}[i] = 'region',         region,
                              {dims:Array(String)}[i] = 'country',        country,
                              {dims:Array(String)}[i] = 'device_model',   device_model,
                              {dims:Array(String)}[i] = 'os_version',     os_version,
                              {dims:Array(String)}[i] = 'app_id',         app_id,
                              {dims:Array(String)}[i] = 'advertiser_id',  advertiser_id,
                              -- Sentinel, not throwIf(): multiIf evaluates its
                              -- fallback eagerly inside arrayMap, so a throw
                              -- here fires unconditionally. Dimension names are
                              -- validated in engine/scan.py against DIM_LABELS
                              -- before the query is built.
                              '\0no_such_dimension\0'
                          ) = {values:Array(String)}[i]
                         ),
                    range(1, length({dims:Array(String)}) + 1)
                )) AS c,
                c.1 AS cand_idx,
                c.2 AS accused
            FROM
            (
                SELECT
                    *,
                    (event_time >= {win_start:DateTime}) AND (event_time < {win_end:DateTime}) AS in_inc,
                    arrayExists(
                        k -> (event_time >= {win_start:DateTime} - toIntervalHour(k * 168))
                         AND (event_time <  {win_end:DateTime}   - toIntervalHour(k * 168)),
                        range(1, {weeks:UInt8} + 1)
                    ) AS in_base
                FROM {db:Identifier}.ad_events
                WHERE event_time >= {win_start:DateTime} - toIntervalHour({weeks:UInt8} * 168)
                  AND event_time <  {win_end:DateTime}
            )
            WHERE in_inc OR in_base
        )
        GROUP BY cand_idx, accused
    )
    GROUP BY cand_idx
)
ORDER BY cand_idx


-- ===== segment_scan.sql =====
-- Stage 2 — segment scan. Given an incident window, which segment explains it?
--
-- Scans all 12 dimensions in ONE query. That is the whole point of the cube:
-- every dimension is a row shape, not a column, so the drill-down is one
-- parameterised statement rather than twelve.
--
-- Params: metric, win_start, win_end, weeks, min_requests, min_z
--
-- ---------------------------------------------------------------------------
-- THE UNIFORMITY TEST — the single most important idea in this file.
--
-- Ranking segments by absolute change finds the BIGGEST segments, not the
-- responsible ones. On Jun 21 every dimension value fell ~44% together;
-- absolute ranking names `banner` and `NAM` with total confidence, because
-- they are simply the largest. The honest answer is "global, nothing to
-- localize".
--
-- So each segment's change is measured against the POPULATION's change:
--
--     vs_global = (segment_incident / segment_baseline)
--               / (global_incident  / global_baseline)  - 1
--
-- A segment that merely moved with everything else scores ~0 no matter how
-- large its absolute swing. A segment that genuinely broke stands apart.
-- Measured: Android 15 scores -42.3% while the worst Jun 21 segment scores
-- -2.9%. That gap is the difference between a diagnosis and a fabrication.
--
-- ---------------------------------------------------------------------------
-- SIGNIFICANCE — the second gate, and the one that used to be a guess.
--
-- vs_global says a segment moved DIFFERENTLY. It does not say the move was
-- real. A 300-request segment can post a violent percentage swing on pure
-- noise, and ranking by effect alone puts it on top: that is how the eCPM scan
-- first crowned a single app that turned out to explain 24% of the movement.
--
-- The old guard against this was a hand-picked `min_requests = 5000`.
--
-- fill_rate, render_rate and ctr are PROPORTIONS, so there is an exact test
-- rather than a guess: the two-proportion z-test, built into ClickHouse as
-- proportionsZTest(successes_x, successes_y, trials_x, trials_y, conf, pool).
-- Verified against a hand-rolled formula, identical to one decimal.
--
-- Measured on the Android 15 incident, with the volume floor dropped to 200:
--     os_version = Android 15        z = -186.9
--     region = EU                    z =  -51.8
--     device_model = Galaxy A54      z =  -48.8
-- A 3.6x separation, and the 1/n term inside the standard error handles small
-- segments on its own — no arbitrary volume floor needed.
--
-- It also removes a structural artifact for free: advertiser_id / vertical /
-- campaign_type only exist on FILLED requests, so their fill rate is 1.0 by
-- construction. They used to flood the top of the scan at a spurious +4.6%
-- (an artifact of vs_global moving when the population moves). Their z is
-- exactly 0, so they now drop out without a special case.
--
-- requests / revenue / ecpm are not proportions and the cube carries no
-- variance term for them, so they keep the volume guard for now. Adding
-- sum(revenue^2) to the cube would enable meanZTest for eCPM later.
-- ---------------------------------------------------------------------------

WITH
    -- Baseline is the SAME window shifted back whole weeks, so weekday and
    -- hour-of-day line up and seasonality cancels rather than contaminates.
    windowed AS
    (
        SELECT
            dim_name,
            dim_value,
            sumIf(requests,    in_inc) AS i_requests,
            sumIf(fills,       in_inc) AS i_fills,
            sumIf(impressions, in_inc) AS i_impressions,
            sumIf(clicks,      in_inc) AS i_clicks,
            toFloat64(sumIf(revenue, in_inc)) AS i_revenue,
            sumIf(requests,    in_base) AS b_requests,
            sumIf(fills,       in_base) AS b_fills,
            sumIf(impressions, in_base) AS b_impressions,
            sumIf(clicks,      in_base) AS b_clicks,
            toFloat64(sumIf(revenue, in_base)) AS b_revenue,
            -- The baseline spans several weeks; the incident spans one window.
            -- Additive metrics must be scaled or a 1-day drop reads as -68%
            -- instead of -44%. Counting buckets rather than assuming `weeks`
            -- matters at the edges of the dataset: a 3-week lookback from
            -- Jun 21 reaches May 31, which does not exist, so only 2 windows
            -- carry data. Ratio metrics are unaffected — the factor cancels.
            uniqExactIf(bucket, in_inc)  AS i_buckets,
            uniqExactIf(bucket, in_base) AS b_buckets,
            if(b_buckets > 0, i_buckets / b_buckets, 1.0) AS b_scale
        FROM
        (
            SELECT
                *,
                (bucket >= {win_start:DateTime}) AND (bucket < {win_end:DateTime}) AS in_inc,
                arrayExists(
                    k -> (bucket >= {win_start:DateTime} - toIntervalHour(k * 168))
                     AND (bucket <  {win_end:DateTime}   - toIntervalHour(k * 168)),
                    range(1, {weeks:UInt8} + 1)
                ) AS in_base
            FROM {db:Identifier}.segment_cube
        )
        WHERE in_inc OR in_base
        GROUP BY dim_name, dim_value
    ),

    -- The requested metric, computed sum/sum per the glossary. Never an
    -- average of per-bucket ratios, so the figure stays correct at any rollup.
    valued AS
    (
        SELECT
            dim_name,
            dim_value,
            i_requests,
            b_scale,
            -- Exact test for the proportion metrics; NaN where it doesn't apply.
            multiIf(
                {metric:String} = 'fill_rate',
                    proportionsZTest(i_fills, b_fills, i_requests, b_requests, 0.95, 'pooled').1,
                {metric:String} = 'render_rate',
                    proportionsZTest(i_impressions, b_impressions, i_fills, b_fills, 0.95, 'pooled').1,
                {metric:String} = 'ctr',
                    proportionsZTest(i_clicks, b_clicks, i_impressions, b_impressions, 0.95, 'pooled').1,
                nan
            ) AS z,
            multiIf(
                {metric:String} = 'requests',    toFloat64(i_requests),
                {metric:String} = 'fill_rate',   if(i_requests    > 0, i_fills / i_requests, 0),
                {metric:String} = 'render_rate', if(i_fills       > 0, i_impressions / i_fills, 0),
                {metric:String} = 'ctr',         if(i_impressions > 0, i_clicks / i_impressions, 0),
                {metric:String} = 'ecpm',        if(i_impressions > 0, i_revenue / i_impressions * 1000, 0),
                i_revenue
            ) AS incident_value,
            multiIf(
                {metric:String} = 'requests',    toFloat64(b_requests * b_scale),
                {metric:String} = 'fill_rate',   if(b_requests    > 0, b_fills / b_requests, 0),
                {metric:String} = 'render_rate', if(b_fills       > 0, b_impressions / b_fills, 0),
                {metric:String} = 'ctr',         if(b_impressions > 0, b_clicks / b_impressions, 0),
                {metric:String} = 'ecpm',        if(b_impressions > 0, b_revenue / b_impressions * 1000, 0),
                b_revenue * b_scale
            ) AS baseline_value
        FROM windowed
    ),

    -- The population's own movement, from the __total__ rows already in the
    -- cube. Same scan, no second query.
    globals AS
    (
        SELECT if(baseline_value > 0, incident_value / baseline_value, 1.0) AS global_ratio
        FROM valued
        WHERE dim_name = '__total__'
    )

SELECT
    dim_name,
    dim_value,
    baseline_value,
    incident_value,
    i_requests AS incident_requests,
    z,
    if(baseline_value > 0, incident_value / baseline_value - 1, 0) AS seg_change,
    -- The uniformity test. See the header.
    if(baseline_value > 0,
       (incident_value / baseline_value) / (SELECT global_ratio FROM globals) - 1,
       0) AS vs_global,
    (SELECT global_ratio FROM globals) - 1 AS global_change
FROM valued
WHERE dim_name != '__total__'
  AND if(
        isNaN(z),
        -- No exact test available: fall back to the volume guard.
        i_requests >= {min_requests:UInt64},
        -- Exact test available: significance replaces the guess. The small
        -- floor only keeps degenerate 1-row segments out of the output.
        (abs(z) >= {min_z:Float64}) AND (i_requests >= 200)
      )
ORDER BY abs(vs_global) DESC
