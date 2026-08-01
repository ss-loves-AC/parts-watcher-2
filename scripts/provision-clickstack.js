// Register ClickHouse Cloud with HyperDX / ClickStack.
//
// Run:  docker exec -i -e CH_HOST -e CH_USER -e CH_PASSWORD \
//         ch-hacker-mongodb-1 mongosh --quiet hyperdx < scripts/provision-clickstack.js
//
// Idempotent: every write is an upsert keyed by (team, name), so re-running
// changes nothing. Safe to run on every deploy.
//
// PURELY ADDITIVE. The existing 'Local ClickHouse' connection and its sources
// (Logs, Traces, Metrics, Sessions, Langfuse Observations, Agent Annotations)
// are never touched — the warm-up stack keeps working unchanged.
//
// Why Mongo and not the REST API: HyperDX only seeds DEFAULT_SOURCES when a
// team has none, and the Personal API Access Key is not authorised for the app
// REST API (/api/sources returns 401). Trade-off: this couples to HyperDX's
// Mongo schema, so revisit on a HyperDX major upgrade.

const host = process.env.CH_HOST;
const user = process.env.CH_USER;
const pass = process.env.CH_PASSWORD;

if (!host || !user || !pass) {
  print('FATAL: CH_HOST, CH_USER and CH_PASSWORD must all be set');
  quit(1);
}

const team = db.teams.findOne();
if (!team) {
  print('FATAL: no HyperDX team found — is the stack initialised?');
  quit(1);
}

const now = new Date();

// ---------------------------------------------------------------- connection
db.connections.updateOne(
  { team: team._id, name: 'ClickHouse Cloud (rca)' },
  {
    $set: {
      team: team._id,
      name: 'ClickHouse Cloud (rca)',
      host: `https://${host}:8443`,
      username: user,
      password: pass,
      updatedAt: now,
    },
    $setOnInsert: { createdAt: now, __v: 0 },
  },
  { upsert: true },
);

const conn = db.connections.findOne({ team: team._id, name: 'ClickHouse Cloud (rca)' });
print(`connection ClickHouse Cloud (rca): ${conn._id}`);

// -------------------------------------------------------------------- source
//
// Registering the ad events as a ClickStack source is what makes the semantic
// tools work over them: clickstack_event_deltas ("what changed between these
// two windows") is the same question our engine answers, so it doubles as an
// independent cross-check rather than a checkbox integration.
//
// Two mappings do the real work:
//   severityText  unfilled requests read as warnings, so the severity-aware
//                 tools key off the funnel's actual failure mode
//   serviceName   ad_format gives ClickStack an axis to group by

const dims = [
  'ad_format', 'category', 'publisher_tier', 'vertical', 'campaign_type',
  'region', 'country', 'device_model', 'os_version', 'app_id', 'advertiser_id',
];
const attrExpr =
  'map(' + dims.map((d) => `'${d}', toString(${d})`).join(', ') + ')';

db.sources.updateOne(
  { team: team._id, name: 'Ad Events' },
  {
    $set: {
      team: team._id,
      name: 'Ad Events',
      kind: 'log',
      connection: conn._id,
      from: { databaseName: 'rca', tableName: 'ad_events' },
      timestampValueExpression: 'event_time',
      displayedTimestampValueExpression: 'event_time',
      severityTextExpression: "if(is_filled = 0, 'warn', 'info')",
      serviceNameExpression: 'ad_format',
      bodyExpression: "concat(ad_format, ' ', country, ' ', os_version)",
      implicitColumnExpression: "concat(ad_format, ' ', country, ' ', os_version)",
      defaultTableSelectExpression:
        'event_time,ad_format,category,region,country,os_version,device_model,is_filled,is_impression,is_click,revenue',
      eventAttributesExpression: attrExpr,
      resourceAttributesExpression: "CAST(map(), 'Map(String, String)')",
      highlightedRowAttributeExpressions: [],
      highlightedTraceAttributeExpressions: [],
      materializedViews: [],
      querySettings: [],
      disabled: false,
      updatedAt: now,
    },
    $setOnInsert: { createdAt: now, __v: 0 },
  },
  { upsert: true },
);

// NB: keep chained calls on ONE line. mongosh reads stdin as a REPL, so a
// line beginning with '.' after a complete statement is parsed as a keyword
// and the chain silently fails with "Invalid REPL keyword".
print('--- sources after provisioning ---');
db.sources.find({ team: team._id }, { name: 1, 'from.databaseName': 1, 'from.tableName': 1 }).forEach((d) => print(`  ${d.name}  ->  ${d.from.databaseName}.${d.from.tableName}`));
