-- Stage 3 — refinement. Does the accused segment FULLY explain the movement?
--
-- The segment scan returns shadows alongside the culprit: Galaxy S23 scored
-- -8.7% on the Android 15 incident purely because most Galaxy S23 devices run
-- Android 15. Naming both would be wrong; naming the shadow would be worse.
--
-- The test: remove the accused segment and recompute. If the movement
-- disappears, the segment explains it. If a residual survives, something else
-- is going on and the diagnosis must say so.
--
-- Measured on the Android 15 incident:
--     all traffic            0.7852 -> 0.7508   the movement
--     excluding Android 15   0.7852 -> 0.7844   flat: fully explained
--
-- This runs on ad_events rather than the cube. The cube holds one row per
-- (dimension, value) so it cannot express "Galaxy S23 AND NOT Android 15" —
-- conditioning needs the fact table. That's the intended trade: the 12-dim
-- sweep costs 69ms on the cube, and only the top candidates pay the ~350ms
-- fact-table query.
--
-- Params: metric, dim (column name), value, win_start, win_end, weeks

SELECT
    scope,
    baseline_value,
    incident_value,
    if(baseline_value > 0, incident_value / baseline_value - 1, 0) AS change
FROM
(
    SELECT
        scope,
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
    FROM
    (
        SELECT
            scope,
            countIf(in_inc)                          AS i_requests,
            sumIf(is_filled, in_inc)                 AS i_fills,
            sumIf(is_impression, in_inc)             AS i_impressions,
            sumIf(is_click, in_inc)                  AS i_clicks,
            toFloat64(sumIf(revenue, in_inc))        AS i_revenue,
            countIf(in_base)                         AS b_requests,
            sumIf(is_filled, in_base)                AS b_fills,
            sumIf(is_impression, in_base)            AS b_impressions,
            sumIf(is_click, in_base)                 AS b_clicks,
            toFloat64(sumIf(revenue, in_base))       AS b_revenue,
            -- Same baseline scaling as segment_scan.sql: several baseline
            -- weeks against one incident window. Counted in hours actually
            -- present, so a lookback reaching before the data starts doesn't
            -- inflate the baseline.
            uniqExactIf(toStartOfHour(event_time), in_inc)  AS i_hours,
            uniqExactIf(toStartOfHour(event_time), in_base) AS b_hours,
            if(b_hours > 0, i_hours / b_hours, 1.0)         AS b_scale
        FROM
        (
            SELECT
                event_time, is_filled, is_impression, is_click, revenue,
                (event_time >= {win_start:DateTime}) AND (event_time < {win_end:DateTime}) AS in_inc,
                arrayExists(
                    k -> (event_time >= {win_start:DateTime} - toIntervalHour(k * 168))
                     AND (event_time <  {win_end:DateTime}   - toIntervalHour(k * 168)),
                    range(1, {weeks:UInt8} + 1)
                ) AS in_base,
                -- Explicit column map rather than dynamic column lookup:
                -- an unknown dim name fails loudly instead of silently
                -- matching nothing and reporting "fully explained".
                arrayJoin(
                    if(multiIf(
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
                           throwIf(1, 'unknown dimension')
                       ) = {value:String},
                       ['all', 'accused'],
                       ['all', 'without_accused'])
                ) AS scope
            FROM rca.ad_events
            WHERE (event_time >= {win_start:DateTime} - toIntervalHour({weeks:UInt8} * 168))
              AND (event_time <  {win_end:DateTime})
        )
        WHERE in_inc OR in_base
        GROUP BY scope
    )
)
ORDER BY scope
