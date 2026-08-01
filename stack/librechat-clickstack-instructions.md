<!-- serverInstructions for the ClickStack MCP in ch-hacker's librechat.yaml.
     Kept here because it is part of THIS project's integration, and because
     librechat.yaml lives in the warm-up repo where it is easy to lose. -->
PRIMARY DATA — the ad-events dataset, on the "ClickHouse Cloud (rca)" connection.
Get its connectionId from clickstack_list_sources; do NOT use "Local ClickHouse"
for ad data, that connection holds only warm-up telemetry.

Two sources:
- "Ad Events"        pw.ad_events       9M rows, 2026-06-01 to 2026-07-05 (historical)
- "Ad Events (live)" pw_live.ad_events  the same traffic replayed into now()

One row per ad request, already denormalized — never join, every dimension is
a column: ad_format, category, publisher_tier, vertical, campaign_type, region,
country, device_model, os_version, app_id, advertiser_id.

Metrics are ALWAYS sum/sum over rows in a group, never an average of per-row
ratios, or rollups come out wrong:
  requests    count()
  fill rate   sum(is_filled) / count()
  render rate sum(is_impression) / sum(is_filled)
  CTR         sum(is_click) / sum(is_impression)
  revenue     sum(revenue)
  eCPM        sum(revenue) / sum(is_impression) * 1000

Revenue decomposes as: Requests x Fill rate x (Impressions/Fills) x eCPM/1000.
When revenue moves, find which FACTOR moved first, then which SEGMENT.

HOW TO ATTRIBUTE A MOVE — this matters more than any query.
Ranking segments by absolute change finds the BIGGEST segments, not the
responsible ones. Always compare a segment's percentage change against the
POPULATION's percentage change over the same windows:

    vs_global = (segment_now / segment_before) / (global_now / global_before) - 1

A segment that merely moved with everything else scores ~0 no matter how large
its absolute swing. If NO segment stands clear of the population, say so — the
honest answer is "this was global, no segment is responsible". Never name the
largest segment as a cause just because its absolute delta is biggest.

Then verify: exclude the accused segment and recompute. If the movement
disappears, it explains it. If a residual survives, say what remains.

Compare like for like: weekends run ~18% below weekdays, so baseline against
the SAME weekday a week or more back, never against yesterday.

Known incidents in the historical data, for reference:
- Jun 23-25  fill rate fell 4.3%, entirely os_version='Android 15' (0.785 -> 0.433)
- Jun 19-22  eCPM fell 2.4%, entirely category='finance'
- Jun 21     requests and revenue fell ~45% GLOBALLY — no segment responsible

SECONDARY — this pipeline's own LLM telemetry, on the "Local ClickHouse"
connection, `default` database. Use for questions about the system itself
(cost, latency, prompt drift):
- observations: per-generation rows. start_time, provided_model_name,
  total_cost, usage_details, level, input, output, trace_id.
  Filter type='GENERATION'. Also registered as source "Langfuse Observations".
- traces, scores.

Always include a LIMIT.
