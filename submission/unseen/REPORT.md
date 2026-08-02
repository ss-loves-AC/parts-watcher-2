# Automated Root-Cause Analysis — report

Generated 2026-08-02T04:03:47.774125+00:00 · database `unseen` · 6 incident(s) found.

Every figure below was computed in ClickHouse and handed to the narrator
as a finished string. The narrator has no database access and performs no
arithmetic, and every number it produced was machine-checked against the
evidence before this was written.

## What moved

| Metric | Window | Change | Verdict | Responsible |
|---|---|---|---|---|
| request volume | Jun 21 | -45.68% | 🌍 global | — |
| fill rate | Jul 8–Jul 9 | -6.64% | ◐ partial | device OS version = iOS 17.5 |
| eCPM | Jul 6 00:00 to Jul 10 23:00 | -8.50% | ◐ partial | device model = iPhone 14 |
| fill rate | Jun 23–Jun 25 | -4.29% | 🎯 localized | device OS version = Android 15 |
| revenue | Jun 21 | -46.21% | 🌍 global | — |
| revenue | Jul 9 | -14.60% | 🌍 global | — |

> **localized** — one segment explains it.  
> **global** — everything moved together; naming a segment would be wrong.  
> **partial** — a segment explains some of it, not all.

---

## The diagnoses

## Request Volume — Jun 21  ·  **global**

Request volume on Jun 21 fell from 232,053 to 126,052, a -45.68% drop that is 38x larger than this metric's normal movement. The incident is global: every segment moved with the population (-43.5%), and no single segment stands apart. Advertiser vertical gaming (-4.0% relative), app category news (-2.5%), country AE (-2.1%), country ES (+2.0%), and ad format rewarded (-1.8%) were all ruled out as within normal spread.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=ef299582-7376-42ed-a651-a15475db56b4) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** 232,053 → **actual** 126,052 (-45.68%)
- **how unusual** 38x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **proof** Every segment moved with the population (-43.5%); none stands apart. No single segment is responsible.
- **ruled out**
  - _advertiser vertical = gaming_ — moved -4.0% relative to the population — within normal spread
  - _app category = news_ — moved -2.5% relative to the population — within normal spread
  - _country = AE_ — moved -2.1% relative to the population — within normal spread
  - _country = ES_ — moved +2.0% relative to the population — within normal spread
  - _ad format = rewarded_ — moved -1.8% relative to the population — within normal spread

</details>

## Fill Rate — Jul 8–Jul 9  ·  **partial**

Fill rate fell from 78.4% to 73.2% (a -6.64% change) between Jul 8–Jul 9, a movement 24x larger than normal. The culprit was device OS version = iOS 17.5, whose fill rate dropped from 78.6% to 47.7% (-39.3%), departing the population by -35.8% with evidence strength of 156 standard errors. Excluding iOS 17.5, fill rate moved +2.57% versus -5.38% for all traffic, proving this segment drove the decline. This explains 52% of the movement, which further concentrates in app = app_00004 (0.9104 → 0.4049, -55.5%). The incident cost $105.41 in lost revenue, and apps app_00106, app_00283, app_00202, and app_00107 were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=3e898ce6-e938-4a96-837d-0de0981d88d5) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** 78.4% → **actual** 73.2% (-6.64%)
- **how unusual** 24x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **culprit** device OS version = `iOS 17.5` — 78.6% → 47.7% (-39.3%), -35.8% beyond the population, 156 standard errors
- **proof** Excluding device OS version = iOS 17.5, fill rate moved +2.57% against -5.38% for all traffic.
- **cost** Had device OS version = iOS 17.5 held at its baseline revenue per request, revenue over this window would have been $105.41 higher.
- **ruled out**
  - _app = app_00106_ — departed the population by +39.0%, but removing it does not shrink the movement — the removal test selected device OS version = iOS 17.5 instead
  - _app = app_00283_ — departed the population by +38.6%, but removing it does not shrink the movement — the removal test selected device OS version = iOS 17.5 instead
  - _app = app_00202_ — departed the population by +38.5%, but removing it does not shrink the movement — the removal test selected device OS version = iOS 17.5 instead
  - _app = app_00107_ — departed the population by +36.7%, but removing it does not shrink the movement — the removal test selected device OS version = iOS 17.5 instead

</details>

## Ecpm — Jul 6 00:00 to Jul 10 23:00  ·  **partial**

eCPM fell from $2.464 to $2.255, a -8.50% drop, which was 16x larger than normal movement. The culprit was device model = iPhone 14, whose value dropped from $2.518 to $1.951 (-22.5%), exceeding the population by -14.5%. Excluding iPhone 14, eCPM moved -6.09% versus -9.37% for all traffic, explaining 35% of the movement. Within iPhone 14, the drop concentrated in app = app_00074, falling from 2.6584 to 1.6887 (-36.5%). Device OS version = Android 13, Galaxy S23, iPhone 13, and iPhone 14 itself were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=2d7be6c4-e307-4f7c-a2ad-683d9698aa3b) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** $2.464 → **actual** $2.255 (-8.50%)
- **how unusual** 16x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **culprit** device model = `iPhone 14` — $2.518 → $1.951 (-22.5%), -14.5% beyond the population, not applicable to this metric
- **proof** Excluding device model = iPhone 14, eCPM moved -6.09% against -9.37% for all traffic.
- **cost** Had device model = iPhone 14 held at its baseline revenue per request, revenue over this window would have been $183.28 higher.
- **ruled out**
  - _device OS version = Android 13_ — departed the population by +21.1%, but removing it does not shrink the movement — the removal test selected device model = iPhone 14 instead
  - _device model = Galaxy S23_ — departed the population by +15.9%, but removing it does not shrink the movement — the removal test selected device model = iPhone 14 instead
  - _device model = iPhone 14_ — departed the population by -14.5%, but removing it does not shrink the movement — the removal test selected device model = iPhone 14 instead
  - _device model = iPhone 13_ — departed the population by +13.9%, but removing it does not shrink the movement — the removal test selected device model = iPhone 14 instead

</details>

## Fill Rate — Jun 23–Jun 25  ·  **localized**

Fill rate fell from 78.4% to 75.1% between Jun 23–Jun 25, a -4.29% change that was 15x larger than normal. The drop was localized to device OS version = Android 15, whose fill rate collapsed from 78.5% to 43.3% (-44.8%), departing from the population by -42.3% with evidence strength of 187 standard errors. Excluding Android 15, fill rate moved only -0.08% versus -4.36% for all traffic, fully explaining 98% of the movement. Had Android 15 held its baseline revenue per request, revenue would have been $69.53 higher. Device model = Galaxy S23, app = app_00246, device model = Redmi Note 12, and app = app_00160 were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=f01eb0b4-9f80-49fe-87f0-1447ce726bda) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** 78.4% → **actual** 75.1% (-4.29%)
- **how unusual** 15x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **culprit** device OS version = `Android 15` — 78.5% → 43.3% (-44.8%), -42.3% beyond the population, 187 standard errors
- **proof** Excluding device OS version = Android 15, fill rate moved -0.08% against -4.36% for all traffic.
- **cost** Had device OS version = Android 15 held at its baseline revenue per request, revenue over this window would have been $69.53 higher.
- **ruled out**
  - _any additional cause_ — Excluding device OS version = Android 15, fill rate moved -0.08% against -4.36% for all traffic. Nothing else is required to explain it.
  - _device model = Galaxy S23_ — departed the population by -8.6%, but removing it does not shrink the movement — the removal test selected device OS version = Android 15 instead
  - _app = app_00246_ — departed the population by -7.3%, but removing it does not shrink the movement — the removal test selected device OS version = Android 15 instead
  - _device model = Redmi Note 12_ — departed the population by -6.8%, but removing it does not shrink the movement — the removal test selected device OS version = Android 15 instead
  - _app = app_00160_ — departed the population by -6.0%, but removing it does not shrink the movement — the removal test selected device OS version = Android 15 instead

</details>

## Revenue — Jun 21  ·  **global**

Revenue on Jun 21 fell from $18.13 to $9.77, a -46.21% drop that is 15x larger than this metric's normal movement. The verdict is global, with every segment moving with the population at -44.8%, and no single segment stands apart as the culprit. The finance app category was ruled out because, despite standing out at -34.7%, removing it leaves -43.37% of the original -44.81%, accounting for only 3% of the movement. App app_00000, ecommerce, and gaming were also ruled out because, though they departed the population by +4.2% or -4.1%, none survived the removal test.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=4a87bdd1-c1d4-40ad-9bed-d8797ec9af41) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** $18.13 → **actual** $9.77 (-46.21%)
- **how unusual** 15x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `hourly+daily`
- **proof** Every segment moved with the population (-44.8%); none stands apart. No single segment is responsible.
- **ruled out**
  - _app category = finance_ — stood out at -34.7% against the population, but removing it leaves -43.37% of the original -44.81% — it accounts for only 3% of the movement
  - _app = app_00000_ — departed the population by +4.2%, but no segment survived the removal test — departure alone does not make a segment the cause
  - _app category = ecommerce_ — departed the population by +4.2%, but no segment survived the removal test — departure alone does not make a segment the cause
  - _advertiser vertical = gaming_ — departed the population by -4.1%, but no segment survived the removal test — departure alone does not make a segment the cause

</details>

## Revenue — Jul 9  ·  **global**

Revenue on Jul 9 fell from $22.41 to $19.15, a -14.60% drop that is 5x larger than this metric's normal movement. The verdict is global, with proof that every segment moved with the population (-10.5%) and none stands apart. Country = MX, app category = news, region = LATAM, and campaign type = CPC were all ruled out because, despite departing the population by +116.1%, +165.8%, +137.9%, and +120.2% respectively, removing each leaves the movement as large or larger (e.g., removing MX leaves -11.96% of the original -10.49%). No single segment is responsible.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=5cd77701-84c0-45ab-b461-1cc918003103) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** $22.41 → **actual** $19.15 (-14.60%)
- **how unusual** 5x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `hourly+daily`
- **proof** Every segment moved with the population (-10.5%); none stands apart. No single segment is responsible.
- **ruled out**
  - _country = MX_ — stood out at +116.1% against the population, but removing it leaves -11.96% of the original -10.49% — it accounts for none of the movement — removing it leaves the movement as large or larger
  - _app category = news_ — departed the population by +165.8%, but no segment survived the removal test — departure alone does not make a segment the cause
  - _region = LATAM_ — departed the population by +137.9%, but no segment survived the removal test — departure alone does not make a segment the cause
  - _campaign type = CPC_ — departed the population by +120.2%, but no segment survived the removal test — departure alone does not make a segment the cause

</details>

---

## Traces

Every investigation was recorded. Open the run, or jump straight to an incident:

**Run:** https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410

- request volume   Jun 21                 https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=ef299582-7376-42ed-a651-a15475db56b4
- fill rate        Jul 8–Jul 9            https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=3e898ce6-e938-4a96-837d-0de0981d88d5
- eCPM             Jul 6 00:00 to Jul 10 23:00 https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=2d7be6c4-e307-4f7c-a2ad-683d9698aa3b
- fill rate        Jun 23–Jun 25          https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=f01eb0b4-9f80-49fe-87f0-1447ce726bda
- revenue          Jun 21                 https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=4a87bdd1-c1d4-40ad-9bed-d8797ec9af41
- revenue          Jul 9                  https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=5cd77701-84c0-45ab-b461-1cc918003103

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
