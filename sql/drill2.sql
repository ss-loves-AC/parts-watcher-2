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
