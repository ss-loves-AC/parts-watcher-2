# The observability plane

Everything needed to stand up ClickStack, Langfuse and LibreChat and wire them
to this project — reproducible from this repo alone.

## What is ours and what is not

**Not ours:** HyperDX (ClickStack), Langfuse and LibreChat are third-party open
source, pulled from upstream images. `docker compose config --images` lists
nine images and **not one is built here** — we author no service.

**Ours:** the wiring. Which services exist, how they reach ClickHouse Cloud,
and the provisioning that gives them this project's shape:

| Ours | What it does |
|---|---|
| `docker-compose.yml` | the services and how they connect |
| `librechat.yaml` | DeepSeek endpoint + the ClickStack MCP |
| `librechat-clickstack-instructions.md` | what the agent is told about the data |
| `../scripts/provision-clickstack.js` | connection, sources, saved searches, alert, webhook |
| `../scripts/provision-librechat-agent.js` | the Ad Metrics Analyst agent |

That distinction matters for the rules: all code in this repo was written
during the event. Configuration of upstream OSS is the honest scope of what a
24-hour build should contain.

## Where the data actually is

**The ad data is not in here.** It lives in **ClickHouse Cloud**, which is the
primary datastore and where every figure in every diagnosis is computed. These
containers only observe.

- **HyperDX** reads ClickHouse Cloud over HTTPS, via a connection our script
  provisions. It holds no ad data itself.
- **Langfuse** keeps its traces in its own ClickHouse. That is Langfuse's
  architecture, not us splitting our data — Langfuse v3 requires Postgres,
  Redis, ClickHouse and S3-compatible storage of its own.
- **LibreChat** has no database access at all. Its tools are the ClickStack MCP
  that HyperDX serves, so it reaches Cloud through HyperDX.

So there are two ClickHouses with entirely separate jobs: **Cloud holds the ad
events**; Langfuse's holds Langfuse's own traces.

## Standing it up

```bash
cd stack
cp .env.example .env          # fill in ClickHouse Cloud + secrets
docker compose up -d

# HYPERDX_MCP_API_KEY cannot be minted at bootstrap. Log into HyperDX once,
# Team Settings -> API Keys, put it in .env, then:
docker compose up -d --force-recreate --no-deps librechat

# wire this project's shape into the stack
docker compose exec -T mongodb mongosh --quiet hyperdx   < ../scripts/provision-clickstack.js
docker compose exec -T mongodb mongosh --quiet LibreChat < ../scripts/provision-librechat-agent.js
```

Then `python3 -m engine.run --out out/` — the pipeline reads ClickHouse Cloud,
traces to Langfuse, and pins its findings in HyperDX.

## Three things that will cost you an hour if you don't know them

**`requiresOAuth: false` is load-bearing.** HyperDX answers unauthenticated
requests with a bare `401`. LibreChat probes for OAuth *without* the configured
headers, reads that 401 as "OAuth required", ignores the static bearer token,
and loads **zero tools** — with no error that says so. The flag skips the probe.

**`librechat.yaml` is read only at startup.** It is bind-mounted, and a plain
`docker compose up -d` will not recreate a service because a mounted file
changed. Use `--force-recreate --no-deps librechat` after editing it.

**mongosh scripts must be run from a file, not piped.** Piped, mongosh behaves
as a REPL: a blank line inside a statement ends it, and a line beginning with
`.` is read as a keyword. Both fail confusingly mid-object. `docker compose
exec -T ... < file` is fine because the file arrives whole.

## Memory

Langfuse alone wants ~2GB across its five containers. On a small host bring up
`hyperdx` and `mongodb` first — that alone gives you ClickStack, the MCP and
the alert — and add Langfuse only if there is headroom. Every service carries a
`mem_limit` so one cannot starve the rest.

## The instance we actually run

This compose reproduces what is deployed on our VPC behind a Cloudflare tunnel:

| | |
|---|---|
| ClickStack | https://hyperdx.datagan.site |
| Langfuse | https://langfuse.datagan.site |
| LibreChat | https://chat.datagan.site |

One consequence worth knowing: Cloudflare Access rejects Langfuse's *ingestion
API* from outside, so traces are posted over localhost while trace **links**
use the public URL. `LANGFUSE_HOST` and `LANGFUSE_PUBLIC_URL` are separate for
exactly that reason.
