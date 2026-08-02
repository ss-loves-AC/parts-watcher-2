# Unseen incident — submission bundle

The brief asks for three things: *"the diagnosis, the numbers behind it, and
the trace that proves your system generated them."* One file each, plus the
SQL so the numbers can be recomputed rather than taken on trust.

| File | What it is |
|---|---|
| [`REPORT-unseen-incident.md`](REPORT-unseen-incident.md) | **Start here.** The findings, with how the dataset was loaded and why that decision mattered. |
| [`diagnosis.md`](diagnosis.md) | the plain-language diagnosis alone, one section per incident |
| [`evidence.json`](evidence.json) | every computed number, machine-readable — and exactly what the model was handed |
| [`queries.sql`](queries.sql) | the SQL and per-incident parameters behind every figure |
| [`trace.txt`](trace.txt) | Langfuse links: one run, six investigations nested inside it |
| [`REPORT.md`](REPORT.md) | the raw pipeline output the above was assembled from |

## What moved

| Metric | Window | Change | Verdict | Responsible |
|---|---|---|---|---|
| fill rate | Jul 8–Jul 9 | -6.64% | ◐ partial | device OS = iOS 17.5 → app_00004 |
| eCPM | Jul 6–Jul 10 | -8.50% | ◐ partial | device model = iPhone 14 → app_00074 |
| revenue | Jul 9 | -14.60% | 🌍 global | — |
| fill rate | Jun 23–Jun 25 | -4.29% | 🎯 localized | device OS = Android 15 |
| request volume | Jun 21 | -45.68% | 🌍 global | — |
| revenue | Jun 21 | -46.21% | 🌍 global | — |

The bottom three are the known incidents, reproduced unchanged on combined
history — that is the check that the two datasets were joined correctly, not
a padding of the list.

## Two things worth a judge's minute

**The seam.** The unseen package ships regenerated dimension CSVs: same IDs,
new attribute values. We measured the two mappings against each other before
trusting either — agreement `0.126` against a chance level of `0.125`, a pure
reshuffle — so each era keeps its own attribution. Getting this wrong is
silent: it dissolved a real localized incident into a flat band and invented
a segment that had never moved. The `## The seam` section of the report shows
both the measurement and the failure.

**A refusal.** Revenue on Jul 9 is declared **global** despite sitting one day
inside the fill-rate incident. Its strongest candidate departed the population
by +116% and was still rejected, because removing it does not shrink the
movement. Departing the population is not the same as causing the move, and
the removal test is what enforces the difference.

## Verifying any figure

Every number here was computed in ClickHouse and handed to the model as a
finished string; the model has no database access and performs no arithmetic.
Each numeric token in the prose is checked back against `evidence.json` before
the report is written, and two failures ship a deterministic template instead.

```bash
./scripts/load-unseen.sh /path/to/unseen unseen
CH_DB=unseen python3 -m engine.watch              # record what moved
CH_DB=unseen python3 -m engine.run --out out/unseen
```
