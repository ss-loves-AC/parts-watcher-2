# Automated Root-Cause Analysis — report

Generated 2026-08-01T17:13:56.550890+00:00 · database `pw` · 5 incident(s) found.

Every figure below was computed in ClickHouse and handed to the narrator
as a finished string. The narrator has no database access and performs no
arithmetic, and every number it produced was machine-checked against the
evidence before this was written.

## What moved

| Metric | Window | Change | Verdict | Responsible |
|---|---|---|---|---|
| request volume | Jun 21 | -45.77% | 🌍 global | — |
| fill rate | Jun 23–Jun 25 | -4.30% | 🎯 localized | device OS version = Android 15 |
| revenue | Jun 21 | -46.45% | 🌍 global | — |
| eCPM | Jun 19–Jun 22 | -2.37% | 🎯 localized | app category = finance |
| fill rate | Jun 29–Jun 30 | -1.10% | ◐ partial | country = JP |

> **localized** — one segment explains it.  
> **global** — everything moved together; naming a segment would be wrong.  
> **partial** — a segment explains some of it, not all.

---

## The diagnoses

## Request Volume — Jun 21  ·  **global**

Request volume on Jun 21 dropped from 232,435 to 126,052, a -45.77% change, which is 32x larger than this metric's normal movement. The verdict is global, with no single segment responsible; every segment moved with the population at -43.5%, and none stands apart. The proof shows that advertiser vertical = gaming moved -4.0% relative to the population, app category = news moved -2.5%, country = AE moved -2.1%, country = ES moved +2.0%, and ad format = rewarded moved -1.8%, all within normal spread. These segments were ruled out as causes.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=d82e6e16-e188-4016-b98d-7cdb4b6dc70d) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** 232,435 → **actual** 126,052 (-45.77%)
- **how unusual** 32x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **proof** Every segment moved with the population (-43.5%); none stands apart. No single segment is responsible.
- **ruled out**
  - _advertiser vertical = gaming_ — moved -4.0% relative to the population — within normal spread
  - _app category = news_ — moved -2.5% relative to the population — within normal spread
  - _country = AE_ — moved -2.1% relative to the population — within normal spread
  - _country = ES_ — moved +2.0% relative to the population — within normal spread
  - _ad format = rewarded_ — moved -1.8% relative to the population — within normal spread

</details>

## Fill Rate — Jun 23–Jun 25  ·  **localized**

Fill rate dropped from 78.5% to 75.1% between Jun 23–Jun 25, a -4.30% change that was 18x larger than normal. The incident was localized to device OS version = Android 15, whose fill rate fell from 78.5% to 43.3% (-44.8%), versus -42.3% for everything else. Excluding Android 15, fill rate moved only -0.08% against -4.36% for all traffic, proving this segment fully explained the drop (98% of movement). Device model = Galaxy S23 (-8.6%), app = app_00246 (-7.3%), device model = Redmi Note 12 (-6.8%), and app = app_00160 (-6.0%) were all ruled out as lesser contributors. Had Android 15 held its baseline revenue per request, revenue would have been $69.53 higher.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=ef03075d-71fe-40b0-88dd-2d8112ecbd99) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** 78.5% → **actual** 75.1% (-4.30%)
- **how unusual** 18x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **culprit** device OS version = `Android 15` — 78.5% → 43.3% (-44.8%), -42.3% vs everything else, 187 standard errors
- **proof** Excluding device OS version = Android 15, fill rate moved -0.08% against -4.36% for all traffic.
- **cost** Had device OS version = Android 15 held at its baseline revenue per request, revenue over this window would have been $69.53 higher.
- **ruled out**
  - _any additional cause_ — Excluding device OS version = Android 15, fill rate moved -0.08% against -4.36% for all traffic. Nothing else is required to explain it.
  - _device model = Galaxy S23_ — moved -8.6% relative to the population, far less than the -42.3% of device OS version = Android 15
  - _app = app_00246_ — moved -7.3% relative to the population, far less than the -42.3% of device OS version = Android 15
  - _device model = Redmi Note 12_ — moved -6.8% relative to the population, far less than the -42.3% of device OS version = Android 15
  - _app = app_00160_ — moved -6.0% relative to the population, far less than the -42.3% of device OS version = Android 15

</details>

## Revenue — Jun 21  ·  **global**

Revenue on Jun 21 fell from $18.22 to $9.77, a -46.45% drop that is 18x larger than this metric's normal movement. The verdict is global: every segment moved with the population (-44.8%), and no single segment is responsible. The finance app category stood out at -34.7% against the population, but removing it leaves -43.37% of the original -44.81%, accounting for only 3% of the movement. App app_00000, ecommerce, and gaming were all ruled out as they moved within normal spread (+4.2%, +4.2%, and -4.1% relative to the population, respectively).

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=b3b2151a-8620-45f6-acf0-ee49b15d9cc7) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** $18.22 → **actual** $9.77 (-46.45%)
- **how unusual** 18x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `hourly+daily`
- **proof** Every segment moved with the population (-44.8%); none stands apart. No single segment is responsible.
- **ruled out**
  - _app category = finance_ — stood out at -34.7% against the population, but removing it leaves -43.37% of the original -44.81% — it accounts for only 3% of the movement
  - _app = app_00000_ — moved +4.2% relative to the population — within normal spread
  - _app category = ecommerce_ — moved +4.2% relative to the population — within normal spread
  - _advertiser vertical = gaming_ — moved -4.1% relative to the population — within normal spread

</details>

## Ecpm — Jun 19–Jun 22  ·  **localized**

eCPM fell from $2.475 to $2.416, a -2.37% drop that was 5x larger than normal movement. The decline was localized to app category = finance, whose eCPM dropped from $2.470 to $1.613 (-34.7%), versus -33.1% for everything else. Excluding finance, eCPM moved +0.05% against -2.38% for all traffic, fully explaining 98% of the movement. Had finance held its baseline, revenue would have been $41.56 higher. App = app_00011 (-32.7%), interstitial (-4.8%), and native (+4.1%) were ruled out as lesser contributors.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=4c46ddfa-4c5f-44e6-b6e5-6d0418eb9e84) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** $2.475 → **actual** $2.416 (-2.37%)
- **how unusual** 5x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily`
- **culprit** app category = `finance` — $2.470 → $1.613 (-34.7%), -33.1% vs everything else, not applicable to this metric
- **proof** Excluding app category = finance, eCPM moved +0.05% against -2.38% for all traffic.
- **cost** Had app category = finance held at its baseline revenue per request, revenue over this window would have been $41.56 higher.
- **ruled out**
  - _any additional cause_ — Excluding app category = finance, eCPM moved +0.05% against -2.38% for all traffic. Nothing else is required to explain it.
  - _app category = finance_ — moved -33.1% relative to the population, far less than the -33.1% of app category = finance
  - _app = app_00011_ — moved -32.7% relative to the population, far less than the -33.1% of app category = finance
  - _ad format = interstitial_ — moved -4.8% relative to the population, far less than the -33.1% of app category = finance
  - _ad format = native_ — moved +4.1% relative to the population, far less than the -33.1% of app category = finance

</details>

## Fill Rate — Jun 29–Jun 30  ·  **partial**

Fill rate fell from 78.4% to 77.5% between Jun 29–Jun 30, a -1.10% change that was 4x larger than normal. Country = JP was the primary culprit, dropping from 78.1% to 69.8% (-10.6%), with evidence strength of 32 standard errors. Excluding JP, fill rate actually rose +0.24% versus -0.45% for all traffic, proving JP drove the decline. However, JP explained only 46% of the movement, so the incident was only partially explained. Ruled out were country = JP (moved -10.2% relative to population), Android 15 (+9.0%), iPhone 14 (-5.5%), and APAC (-3.2%), none matching JP's -10.2% relative shift.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=d5d9187f-7558-43f2-8479-09ac327a2df5) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** 78.4% → **actual** 77.5% (-1.10%)
- **how unusual** 4x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily`
- **culprit** country = `JP` — 78.1% → 69.8% (-10.6%), -10.2% vs everything else, 32 standard errors
- **proof** Excluding country = JP, fill rate moved +0.24% against -0.45% for all traffic.
- **cost** Had country = JP held at its baseline revenue per request, revenue over this window would have been $4.50 higher.
- **ruled out**
  - _country = JP_ — moved -10.2% relative to the population, far less than the -10.2% of country = JP
  - _device OS version = Android 15_ — moved +9.0% relative to the population, far less than the -10.2% of country = JP
  - _device model = iPhone 14_ — moved -5.5% relative to the population, far less than the -10.2% of country = JP
  - _region = APAC_ — moved -3.2% relative to the population, far less than the -10.2% of country = JP

</details>

---

## Traces

Every investigation was recorded. Open the run, or jump straight to an incident:

**Run:** https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0

- request volume   Jun 21                 https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=d82e6e16-e188-4016-b98d-7cdb4b6dc70d
- fill rate        Jun 23–Jun 25          https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=ef03075d-71fe-40b0-88dd-2d8112ecbd99
- revenue          Jun 21                 https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=b3b2151a-8620-45f6-acf0-ee49b15d9cc7
- eCPM             Jun 19–Jun 22          https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=4c46ddfa-4c5f-44e6-b6e5-6d0418eb9e84
- fill rate        Jun 29–Jun 30          https://langfuse.datagan.site/trace/3ccb2bac-83e1-4973-be95-c622c71636f0?observation=d5d9187f-7558-43f2-8479-09ac327a2df5

---

## Reproducing this

Every figure can be recomputed. `queries.sql` in this directory carries
the SQL and the per-incident parameters behind each one.

```bash
./scripts/load-unseen.sh /path/to/data unseen   # load
CH_DB=unseen python3 -m engine.run --out out/   # detect, attribute, narrate
```

| File | What it is |
|---|---|
| `REPORT.md` | this document |
| `diagnosis.md` | the prose alone |
| `evidence.json` | every computed number, machine-readable |
| `queries.sql` | the SQL behind every figure |
| `trace.txt` | Langfuse links |
