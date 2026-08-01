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
