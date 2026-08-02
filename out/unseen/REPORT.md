# Automated Root-Cause Analysis — report

Generated 2026-08-02T02:24:39.413012+00:00 · database `unseen` · 6 incident(s) found.

Every figure below was computed in ClickHouse and handed to the narrator
as a finished string. The narrator has no database access and performs no
arithmetic, and every number it produced was machine-checked against the
evidence before this was written.

## What moved

| Metric | Window | Change | Verdict | Responsible |
|---|---|---|---|---|
| request volume | Jun 21 | -45.68% | 🌍 global | — |
| fill rate | Jul 8–Jul 9 | -6.64% | 🌍 global | — |
| eCPM | Jul 6 00:00 to Jul 10 23:00 | -8.50% | ◐ partial | region = MEA |
| fill rate | Jun 23–Jun 25 | -4.29% | 🌍 global | — |
| revenue | Jun 21 | -46.21% | 🌍 global | — |
| revenue | Jul 9 | -14.60% | ◐ partial | device OS version = iOS 17.5 |

> **localized** — one segment explains it.  
> **global** — everything moved together; naming a segment would be wrong.  
> **partial** — a segment explains some of it, not all.

---

## The diagnoses

## Request Volume — Jun 21  ·  **global**

Request volume on Jun 21 fell to 126,052 from an expected 232,053, a -45.68% drop that was 38x larger than this metric's normal movement. The verdict is global, with every segment moving with the population at -43.5%, and no single segment stands apart as the culprit. Advertiser vertical = travel moved +2.5% relative to the population, app category = finance moved +2.3%, country = UK moved -2.0%, country = AR moved +1.9%, and country = PH moved -1.9%, all within normal spread and thus ruled out.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=c26c3d9d-618b-4ed5-8a8f-b857e12f121c) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** 232,053 → **actual** 126,052 (-45.68%)
- **how unusual** 38x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **proof** Every segment moved with the population (-43.5%); none stands apart. No single segment is responsible.
- **ruled out**
  - _advertiser vertical = travel_ — moved +2.5% relative to the population — within normal spread
  - _app category = finance_ — moved +2.3% relative to the population — within normal spread
  - _country = UK_ — moved -2.0% relative to the population — within normal spread
  - _country = AR_ — moved +1.9% relative to the population — within normal spread
  - _country = PH_ — moved -1.9% relative to the population — within normal spread

</details>

## Fill Rate — Jul 8–Jul 9  ·  **global**

Fill rate dropped from 78.4% to 73.2% between Jul 8–Jul 9, a change of -6.64%, which is 24x larger than this metric's normal movement. The verdict is global: every segment moved with the population (-5.4%), and no single segment stands apart. App app_00283 was ruled out because removing it leaves -5.40% of the original -5.38%, accounting for only -0% of the movement. Apps app_00106, app_00283, and app_00202 were also ruled out as their movements (+39.0%, +38.6%, +38.5% relative to the population) were within normal spread.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=56bae3c7-1f56-4baa-9f69-e96564f9e1fe) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** 78.4% → **actual** 73.2% (-6.64%)
- **how unusual** 24x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **proof** Every segment moved with the population (-5.4%); none stands apart. No single segment is responsible.
- **ruled out**
  - _app = app_00283_ — stood out at +38.6% against the population, but removing it leaves -5.40% of the original -5.38% — it accounts for only -0% of the movement
  - _app = app_00106_ — moved +39.0% relative to the population — within normal spread
  - _app = app_00283_ — moved +38.6% relative to the population — within normal spread
  - _app = app_00202_ — moved +38.5% relative to the population — within normal spread

</details>

## Ecpm — Jul 6 00:00 to Jul 10 23:00  ·  **partial**

eCPM fell from $2.464 to $2.255 (-8.50%) between Jul 6 00:00 and Jul 10 23:00, a movement 16x larger than normal. The culprit is region = MEA, whose eCPM dropped from $2.875 to $1.118 (-61.1%), versus -57.1% for everything else. Excluding MEA, eCPM moved -5.37% against -9.37% for all traffic, but this explains only 43% of the movement, so the incident is only partially explained. Within MEA, the drop concentrates in Android 14 (3.5289 -> 1.1262, -68.1%). Ruled out are region = NAM (+68.9%), country = ES (+59.6%), country = NG (-58.5%), and country = AE (-58.5%), all moving far less than MEA's -57.1%.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=b1d3669c-2798-4870-8f93-1c6d63b72c7f) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** $2.464 → **actual** $2.255 (-8.50%)
- **how unusual** 16x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **culprit** region = `MEA` — $2.875 → $1.118 (-61.1%), -57.1% vs everything else, not applicable to this metric
- **proof** Excluding region = MEA, eCPM moved -5.37% against -9.37% for all traffic.
- **cost** Had region = MEA held at its baseline revenue per request, revenue over this window would have been $122.47 higher.
- **ruled out**
  - _region = NAM_ — moved +68.9% relative to the population, far less than the -57.1% of region = MEA
  - _country = ES_ — moved +59.6% relative to the population, far less than the -57.1% of region = MEA
  - _country = NG_ — moved -58.5% relative to the population, far less than the -57.1% of region = MEA
  - _country = AE_ — moved -58.5% relative to the population, far less than the -57.1% of region = MEA

</details>

## Fill Rate — Jun 23–Jun 25  ·  **global**

Fill rate fell from 78.4% to 75.1% between Jun 23–Jun 25, a -4.29% change that is 15x larger than normal movement. The verdict is global: every segment moved with the population (-4.4%), and no single segment is responsible. Android 15 was ruled out because, despite standing out at -6.8%, removing it leaves -3.61% of the original -4.36%, accounting for only 17% of the movement. App app_00160 (-6.0%) and country MX (-5.6%) were also ruled out as within normal spread.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=bea345e3-6a0e-4508-bb8f-f4b8c5f4013a) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** 78.4% → **actual** 75.1% (-4.29%)
- **how unusual** 15x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `daily+hourly`
- **proof** Every segment moved with the population (-4.4%); none stands apart. No single segment is responsible.
- **ruled out**
  - _device OS version = Android 15_ — stood out at -6.8% against the population, but removing it leaves -3.61% of the original -4.36% — it accounts for only 17% of the movement
  - _device OS version = Android 15_ — moved -6.8% relative to the population — within normal spread
  - _app = app_00160_ — moved -6.0% relative to the population — within normal spread
  - _country = MX_ — moved -5.6% relative to the population — within normal spread

</details>

## Revenue — Jun 21  ·  **global**

Revenue on Jun 21 fell from $18.13 to $9.77, a -46.21% drop that is 15x larger than this metric's normal movement. The verdict is global, with every segment moving with the population (-44.8%) and none standing apart, so no single segment is responsible. App app_00000, region MEA, country UK, app app_00002, and advertiser vertical travel were all ruled out because each moved within normal spread relative to the population (+4.2%, +3.3%, -2.8%, +2.8%, and +2.8%, respectively).

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=de8fe2e3-3e85-48f3-a65d-2c0f01034f3f) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** $18.13 → **actual** $9.77 (-46.21%)
- **how unusual** 15x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `hourly+daily`
- **proof** Every segment moved with the population (-44.8%); none stands apart. No single segment is responsible.
- **ruled out**
  - _app = app_00000_ — moved +4.2% relative to the population — within normal spread
  - _region = MEA_ — moved +3.3% relative to the population — within normal spread
  - _country = UK_ — moved -2.8% relative to the population — within normal spread
  - _app = app_00002_ — moved +2.8% relative to the population — within normal spread
  - _advertiser vertical = travel_ — moved +2.8% relative to the population — within normal spread

</details>

## Revenue — Jul 9  ·  **partial**

Revenue on Jul 9 fell from $22.41 expected to $19.15 actual, a -14.60% drop that was 5x larger than normal movement. The culprit dimension was device OS version = iOS 17.5, whose value dropped from $127.66 to $47.99 (-62.4%), versus -58.0% for everything else. Proof: excluding iOS 17.5, revenue moved +6.31% against -10.49% for all traffic, but this only explains 40% of the movement, so the incident is partial. Within iOS 17.5, the movement concentrates in country = NG: 3.0462 -> 0.7472 (-75.5%). Ruled out were region = NAM (+75.0%), country = ES (+65.1%), country = NG (-59.9%), and country = US (+59.5%), all far less than the -58.0% of iOS 17.5.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=e236ade5-64ef-46ac-a640-0aae7e3fb61a) · narrated by `deepseek-chat`</sub>

<details><summary>evidence</summary>

- **expected** $22.41 → **actual** $19.15 (-14.60%)
- **how unusual** 5x larger than this metric's normal movement
- **baseline** `rung1_same_weekday_3w` · detected at `hourly+daily`
- **culprit** device OS version = `iOS 17.5` — $127.66 → $47.99 (-62.4%), -58.0% vs everything else, not applicable to this metric
- **proof** Excluding device OS version = iOS 17.5, revenue moved +6.31% against -10.49% for all traffic.
- **cost** Had device OS version = iOS 17.5 held at its baseline revenue per request, revenue over this window would have been $89.49 higher.
- **ruled out**
  - _region = NAM_ — moved +75.0% relative to the population, far less than the -58.0% of device OS version = iOS 17.5
  - _country = ES_ — moved +65.1% relative to the population, far less than the -58.0% of device OS version = iOS 17.5
  - _country = NG_ — moved -59.9% relative to the population, far less than the -58.0% of device OS version = iOS 17.5
  - _country = US_ — moved +59.5% relative to the population, far less than the -58.0% of device OS version = iOS 17.5

</details>

---

## Traces

Every investigation was recorded. Open the run, or jump straight to an incident:

**Run:** https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872

- request volume   Jun 21                 https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=c26c3d9d-618b-4ed5-8a8f-b857e12f121c
- fill rate        Jul 8–Jul 9            https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=56bae3c7-1f56-4baa-9f69-e96564f9e1fe
- eCPM             Jul 6 00:00 to Jul 10 23:00 https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=b1d3669c-2798-4870-8f93-1c6d63b72c7f
- fill rate        Jun 23–Jun 25          https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=bea345e3-6a0e-4508-bb8f-f4b8c5f4013a
- revenue          Jun 21                 https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=de8fe2e3-3e85-48f3-a65d-2c0f01034f3f
- revenue          Jul 9                  https://langfuse.datagan.site/trace/e8390d36-3c79-4bd7-a6be-4f39e122c872?observation=e236ade5-64ef-46ac-a640-0aae7e3fb61a

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
