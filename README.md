# parts-watcher — from alert to answer

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/ss-loves-AC/parts-watcher-2)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![ClickHouse](https://img.shields.io/badge/database-ClickHouse-FFCC01.svg)](https://clickhouse.com)
[![Python 3.x](https://img.shields.io/badge/python-3.x-3776AB.svg)](https://www.python.org)
[![Tests](https://img.shields.io/badge/tests-12%20passing-brightgreen.svg)](tests/)
[![Click-a-thon 2026](https://img.shields.io/badge/Click--a--thon-2026-orange.svg)](docs/PROBLEM_STATEMENT.md)

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
| **The unseen incident** | [`reports/REPORT-unseen-incident.md`](reports/REPORT-unseen-incident.md) — the sealed dataset, run for real: what moved, what caused it, the proof |
| **The provided-dataset result** | [`reports/REPORT-provided-dataset.md`](reports/REPORT-provided-dataset.md) — same, on the build-time data |
| **Summary** | [`submission/SUMMARY.md`](submission/SUMMARY.md) |
| **How it works** | [`docs/DESIGN.md`](docs/DESIGN.md) · [`docs/architecture.svg`](docs/architecture.svg) |
| **Runbook used for the unseen incident** | [`docs/UNSEEN_RUNBOOK.md`](docs/UNSEEN_RUNBOOK.md) |

## Seeing it run

**Langfuse — the reasoning.** Traces are marked public, so no account is
needed. One trace per run, with each investigation nested inside it, carrying
the SQL that produced every figure.
→ links are in `out/trace.txt` and in the report.

**ClickStack / HyperDX — the list.** Dashboard *"RCA — what broke and why"*:
every anomaly with its cause. **Set the time range to Last 24 hours** — it
defaults to 15 minutes, and findings are stamped when the detector ran, not
when the incident happened.
→ https://hyperdx.datagan.site

HyperDX's open-source edition is single-team by design — `/register` returns
`teamAlreadyExists` once a team is created, and there is no anonymous mode. So
a shared read account is the only way in that does not mean handing over the
owner's login. **Those credentials are supplied with the submission, not
committed here** — see `submission/SUMMARY.md` for what the dashboard shows if
you would rather not log in at all.

**LibreChat — ask it questions.** Registration is open; sign up with any email,
pick the *Ad Metrics Analyst* agent.
→ https://chat.datagan.site

> Nothing essential sits behind any login: the diagnosis, every number, and
> the exact SQL are committed to this repo, and the Langfuse traces are public.
> The UIs show the same findings in a nicer form.

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
