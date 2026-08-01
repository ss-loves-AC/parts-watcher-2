// Create the LibreChat agent that answers questions over the ad data.
//
// Run:  scp scripts/provision-librechat-agent.js kite@vpc:/tmp/ && \
//       ssh kite@vpc 'docker cp /tmp/provision-librechat-agent.js \
//         ch-hacker-mongodb-1:/tmp/ && docker exec ch-hacker-mongodb-1 \
//         mongosh --quiet LibreChat /tmp/provision-librechat-agent.js'
//
// Run from a FILE, never piped into mongosh. Piped, mongosh behaves as a REPL:
// a blank line inside a statement ends it, and a line starting with '.' is read
// as a keyword. Both fail with confusing errors mid-object.
//
// LibreChat's authenticated agent-CRUD HTTP API returns opaque "Illegal
// request" errors and is not worth driving headless, so this writes the
// document directly — the same approach used for HyperDX sources. Trade-off:
// couples to LibreChat's Mongo schema, so revisit on a major upgrade.

const OWNER_EMAIL = process.env.AGENT_OWNER_EMAIL || 'in.balamurugan@gmail.com';
const AGENT_ID = 'agent_rca_analyst';

const owner = db.users.findOne({ email: OWNER_EMAIL });
if (!owner) {
  print('FATAL: no user ' + OWNER_EMAIL + ' — log into LibreChat once first');
  quit(1);
}

// LibreChat namespaces MCP tools as <tool>_mcp_<serverName>.
const TOOLS = [
  'clickstack_list_sources_mcp_ClickStack',
  'clickstack_describe_source_mcp_ClickStack',
  'clickstack_sql_mcp_ClickStack',
  'clickstack_search_mcp_ClickStack',
  'clickstack_timeseries_mcp_ClickStack',
  'clickstack_event_deltas_mcp_ClickStack',
  'clickstack_event_patterns_mcp_ClickStack',
];

const INSTRUCTIONS = [
  'You investigate why advertising metrics moved, using the ad-events data in ClickHouse.',
  '',
  'Start with clickstack_list_sources. Use the "ClickHouse Cloud (rca)" connection and the',
  '"Ad Events" source. The "Local ClickHouse" connection holds unrelated warm-up telemetry.',
  '',
  'Metrics are ALWAYS sum/sum over the rows in a group, never an average of per-row ratios:',
  '  fill rate = sum(is_filled)/count()',
  '  CTR       = sum(is_click)/sum(is_impression)',
  '  eCPM      = sum(revenue)/sum(is_impression)*1000',
  '',
  'THE RULE THAT MATTERS. Ranking segments by absolute change finds the BIGGEST segments,',
  'not the responsible ones. Compare a segment percentage change against the POPULATION',
  'percentage change over the same windows. If nothing stands clear of the population, say',
  'so plainly - "this was global, no segment is responsible" - rather than naming the',
  'largest. Then verify: exclude the accused segment, recompute, and report what remains.',
  '',
  'Compare like for like. Weekends run about 18% below weekdays, so baseline against the',
  'same weekday a week or more back, never against yesterday.',
  '',
  'Never state a number you did not compute with a tool. Always LIMIT your queries.',
].join('\n');

const now = new Date();

db.agents.updateOne(
  { id: AGENT_ID },
  {
    $set: {
      id: AGENT_ID,
      name: 'Ad Metrics Analyst',
      description: 'Investigates why an ad metric moved, over the ad-events data in ClickHouse Cloud.',
      provider: 'DeepSeek',
      model: 'deepseek-v4-flash',
      model_parameters: { temperature: 0.2 },
      tools: TOOLS,
      instructions: INSTRUCTIONS,
      conversation_starters: [
        'Fill rate dropped between Jun 16-18 and Jun 23-25. What caused it?',
        'Why did revenue fall on Jun 21?',
        'What changed in eCPM between Jun 12-15 and Jun 19-22?',
      ],
      category: 'general',
      author: owner._id,
      authorName: 'rca',
      versions: [],
      tool_resources: {},
      edges: [],
      updatedAt: now,
    },
    $setOnInsert: { createdAt: now, __v: 0 },
  },
  { upsert: true },
);

const a = db.agents.findOne({ id: AGENT_ID });
print('agent    : ' + a.name + '  (' + a.id + ')');
print('model    : ' + a.provider + ' / ' + a.model);
print('tools    : ' + a.tools.length);
print('starters : ' + a.conversation_starters.length);
print('owner    : ' + OWNER_EMAIL);
