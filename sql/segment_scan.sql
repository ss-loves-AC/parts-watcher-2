-- Stage 2 — segment scan. Given an incident window, which segment explains it?
--
-- Scans all 12 dimensions in ONE query. That is the whole point of the cube:
-- every dimension is a row shape, not a column, so the drill-down is one
-- parameterised statement rather than twelve.
--
-- Params: metric, win_start, win_end, weeks, min_requests
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
            FROM rca.segment_cube
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
    if(baseline_value > 0, incident_value / baseline_value - 1, 0) AS seg_change,
    -- The uniformity test. See the header.
    if(baseline_value > 0,
       (incident_value / baseline_value) / (SELECT global_ratio FROM globals) - 1,
       0) AS vs_global,
    (SELECT global_ratio FROM globals) - 1 AS global_change
FROM valued
WHERE dim_name != '__total__'
  -- Volume guard: a 40-request segment at 0% fill will out-rank a real
  -- incident on percentage terms alone. Small segments are noise, not causes.
  AND i_requests >= {min_requests:UInt64}
ORDER BY abs(vs_global) DESC
