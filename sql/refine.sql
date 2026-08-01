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
                     FROM rca.ad_events
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
                FROM rca.ad_events
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
