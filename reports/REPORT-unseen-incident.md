# Unseen incident — report

*Click-a-thon 2026 · InMobi track. Output of the pipeline on the sealed
dataset released in the final hours
([`InMobi/unseen_data`](https://github.com/sidagarwal04/click-a-thon-2026/tree/main/InMobi/unseen_data),
spec [here](https://github.com/sidagarwal04/click-a-thon-2026/blob/main/InMobi/unseen_data/spec.md)):
1,500,000 events, Jul 6–10 2026. Run unmodified — no threshold or detector
logic was touched after seeing this data. See
[`docs/UNSEEN_RUNBOOK.md`](../docs/UNSEEN_RUNBOOK.md) for the procedure
followed.*

Generated 2026-08-02T02:24:39Z · database `unseen` · loaded as
**CONTINUATION** (new events begin after the 9M-row provided dataset ends, so
they were combined — 10.5M rows total, Jun 1 – Jul 10) · dimension tables
reloaded from the unseen package per the spec's note that attribute values
were regenerated on the same IDs · baseline fired at
**`rung1_same_weekday_3w`**, its strongest setting, because three full weeks
of history now sit behind every day in the new slice.

## What's new here

Six incidents fired in total. **Three sit inside the unseen window
(Jul 6–10) — these are the ones that matter for this submission.** The other
three (Jun 21, Jun 23–25) are unchanged reproductions of what
[`REPORT-provided-dataset.md`](REPORT-provided-dataset.md) already found,
included here to show the combined-history load didn't disturb prior
results.

| Metric | Window | Change | Verdict | Responsible | |
|---|---|---|---|---|---|
| eCPM | Jul 6 00:00–Jul 10 23:00 | -8.50% | ◐ partial | region = MEA → Android 14 | **unseen** |
| revenue | Jul 9 | -14.60% | ◐ partial | device OS = iOS 17.5 → country NG | **unseen** |
| fill rate | Jul 8–Jul 9 | -6.64% | 🌍 global | — | **unseen** |
| request volume | Jun 21 | -45.68% | 🌍 global | — | known |
| revenue | Jun 21 | -46.21% | 🌍 global | — | known |
| fill rate | Jun 23–Jun 25 | -4.29% | 🌍 global | — | known |

> **localized** — one segment explains it. **global** — everything moved
> together; naming a segment would be wrong. **partial** — a segment
> explains some of it, not all.

The result we'd point a judge to first: **fill rate, Jul 8–Jul 9, correctly
declared global.** This is genuinely unseen data — the system had no way to
know in advance that nothing there was localizable, and it said so instead
of naming the largest-looking app.

---

## The diagnoses (unseen window)

## Ecpm — Jul 6 00:00 to Jul 10 23:00  ·  **partial**

eCPM fell from $2.464 to $2.255 (-8.50%) between Jul 6 00:00 and Jul 10
23:00, a movement 16x larger than normal. The culprit is region = MEA, whose
eCPM dropped from $2.875 to $1.118 (-61.1%), versus -57.1% for everything
else. Excluding MEA, eCPM moved -5.37% against -9.37% for all traffic, but
this explains only 43% of the movement, so the incident is only partially
explained. Within MEA, the drop concentrates in Android 14 (3.5289 ->
1.1262, -68.1%). Ruled out are region = NAM (+68.9%), country = ES (+59.6%),
country = NG (-58.5%), and country = AE (-58.5%), all moving far less than
MEA's -57.1%. Had MEA held baseline, revenue would have been $122.47 higher
over the window.

<sub>✅ every figure machine-verified against the computed evidence ·
[full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=b1d3669c-2798-4870-8f93-1c6d63b72c7f)
· narrated by `deepseek-chat`</sub>

## Revenue — Jul 9  ·  **partial**

Revenue on Jul 9 fell from $22.41 expected to $19.15 actual, a -14.60% drop
that was 5x larger than normal movement. The culprit dimension was device OS
version = iOS 17.5, whose value dropped from $127.66 to $47.99 (-62.4%),
versus -58.0% for everything else. Proof: excluding iOS 17.5, revenue moved
+6.31% against -10.49% for all traffic, but this only explains 40% of the
movement, so the incident is partial. Within iOS 17.5, the movement
concentrates in country = NG: 3.0462 -> 0.7472 (-75.5%). Ruled out were
region = NAM (+75.0%), country = ES (+65.1%), country = NG (-59.9%), and
country = US (+59.5%), all far less than the -58.0% of iOS 17.5. Had iOS
17.5 held baseline, revenue would have been $89.49 higher.

<sub>✅ every figure machine-verified against the computed evidence ·
[full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=e236ade5-64ef-46ac-a640-0aae7e3fb61a)
· narrated by `deepseek-chat`</sub>

## Fill Rate — Jul 8–Jul 9  ·  **global**

Fill rate dropped from 78.4% to 73.2% between Jul 8–Jul 9, a change of
-6.64%, which is 24x larger than this metric's normal movement. The verdict
is global: every segment moved with the population (-5.4%), and no single
segment stands apart. App app_00283 was ruled out because removing it
leaves -5.40% of the original -5.38%, accounting for only -0% of the
movement. Apps app_00106, app_00283, and app_00202 were also ruled out as
their movements (+39.0%, +38.6%, +38.5% relative to the population) were
within normal spread.

<sub>✅ every figure machine-verified against the computed evidence ·
[full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=56bae3c7-1f56-4baa-9f69-e96564f9e1fe)
· narrated by `deepseek-chat`</sub>

---

## The diagnoses (reproduced from the provided dataset, unchanged)

## Request Volume — Jun 21  ·  **global**

Request volume on Jun 21 fell to 126,052 from an expected 232,053, a
-45.68% drop that was 38x larger than this metric's normal movement. The
verdict is global, with every segment moving with the population at -43.5%,
and no single segment stands apart as the culprit.

<sub>✅ every figure machine-verified against the computed evidence ·
[full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=c26c3d9d-618b-4ed5-8a8f-b857e12f121c)
· narrated by `deepseek-chat`</sub>

## Fill Rate — Jun 23–Jun 25  ·  **global**

Fill rate fell from 78.4% to 75.1% between Jun 23–Jun 25, a -4.29% change
that is 15x larger than normal movement. The verdict is global: every
segment moved with the population (-4.4%), and no single segment is
responsible. Android 15 was ruled out because, despite standing out at
-6.8%, removing it leaves -3.61% of the original -4.36%, accounting for
only 17% of the movement.

<sub>✅ every figure machine-verified against the computed evidence ·
[full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=bea345e3-6a0e-4508-bb8f-f4b8c5f4013a)
· narrated by `deepseek-chat`</sub>

## Revenue — Jun 21  ·  **global**

Revenue on Jun 21 fell from $18.13 to $9.77, a -46.21% drop that is 15x
larger than this metric's normal movement. The verdict is global, with
every segment moving with the population (-44.8%) and none standing apart,
so no single segment is responsible.

<sub>✅ every figure machine-verified against the computed evidence ·
[full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=de8fe2e3-3e85-48f3-a65d-2c0f01034f3f)
· narrated by `deepseek-chat`</sub>

---

## Traces

One run, six investigations nested inside it. Public — no login needed.

**Run:** https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872

- eCPM             Jul 6–Jul 10           https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=b1d3669c-2798-4870-8f93-1c6d63b72c7f
- revenue          Jul 9                  https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=e236ade5-64ef-46ac-a640-0aae7e3fb61a
- fill rate        Jul 8–Jul 9            https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=56bae3c7-1f56-4baa-9f69-e96564f9e1fe
- request volume   Jun 21                 https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=c26c3d9d-618b-4ed5-8a8f-b857e12f121c
- fill rate        Jun 23–Jun 25          https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=bea345e3-6a0e-4508-bb8f-f4b8c5f4013a
- revenue          Jun 21                 https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=de8fe2e3-3e85-48f3-a65d-2c0f01034f3f

## Reproducing this

Every figure can be recomputed against ClickHouse.

```bash
./scripts/load-unseen.sh /path/to/unseen unseen   # load — detects CONTINUATION vs REPLACEMENT itself
CH_DB=unseen python3 -m engine.run --out out/unseen
```

`out/unseen/queries.sql` carries the exact SQL and per-incident parameters
behind every number above; it can be re-run against the answer key.

| File | What it is |
|---|---|
| `REPORT-unseen-incident.md` | this document |
| [`../out/unseen/diagnosis.md`](../out/unseen/diagnosis.md) | the prose alone |
| [`../out/unseen/evidence.json`](../out/unseen/evidence.json) | every computed number, machine-readable |
| [`../out/unseen/queries.sql`](../out/unseen/queries.sql) | the SQL behind every figure |
| [`../out/unseen/trace.txt`](../out/unseen/trace.txt) | Langfuse links |
