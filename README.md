# parts-watcher — from alert to answer

Automated root-cause analysis over 9M ad events in ClickHouse.
**Click-a-thon 2026 · InMobi track.**

A metric moves. In under a minute the system names the segment responsible,
proves it, states what it ruled out, and shows the SQL it used.

```bash
./scripts/load-unseen.sh /path/to/data unseen   # load
CH_DB=unseen python3 -m engine.run --out out/   # detect → attribute → narrate → act
```

## Start here

| | |
|---|---|
| **The result** | [`reports/REPORT-provided-dataset.md`](reports/REPORT-provided-dataset.md) — what moved, what caused it, and the proof |
| **Summary** | [`submission/SUMMARY.md`](submission/SUMMARY.md) |
| **How it works** | [`docs/DESIGN.md`](docs/DESIGN.md) · [`docs/architecture.svg`](docs/architecture.svg) |
| **When the sealed data lands** | [`docs/UNSEEN_RUNBOOK.md`](docs/UNSEEN_RUNBOOK.md) |

## Seeing it run

**Langfuse — the reasoning.** Traces are marked public, so no account is
needed. One trace per run, with each investigation nested inside it, carrying
the SQL that produced every figure.
→ links are in `out/trace.txt` and in the report.

**ClickStack / HyperDX — the list.** Dashboard *"RCA — what broke and why"*:
every anomaly with its cause. **Set the time range to Last 24 hours** — it
defaults to 15 minutes and findings are stamped when the detector ran.
→ https://hyperdx.datagan.site

**LibreChat — ask it questions.** Registration is open; sign up with any email,
pick the *Ad Metrics Analyst* agent.
→ https://chat.datagan.site

> HyperDX has no anonymous mode and refuses self-registration once a team
> exists, so it needs an account we create. **If you are judging and want
> access, open an issue on this repo and we will send an invite.** Nothing
> essential is behind it: the diagnosis, every number, and the exact SQL are all
> committed here, and the Langfuse traces are public.

## What is in here

```
engine/    detect → scan → refine → evidence → narrate → act
sql/       every piece of analysis, as ClickHouse queries
load/      schema, the segment cube, detections, the loader
scripts/   provisioning, holdout rehearsal, live replay
stack/     docker-compose for the observability plane
tests/     12 regression tests against known ground truth
docs/      design, architecture, runbook, ClickHouse review
```

## Verify it yourself

```bash
python3 -m unittest discover -s tests -t . -v   # 12 tests, ~18s
scripts/holdout-rehearsal.sh 14                 # the unseen path, end to end
python3 -m engine.replay --from 2026-06-21 --to 2026-06-24 --step 6
```

Every figure in the report can be recomputed: `out/queries.sql` carries the SQL
and per-incident parameters behind each one.

## Licence

MIT.
