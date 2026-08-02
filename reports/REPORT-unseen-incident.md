# Unseen incident — report

*Click-a-thon 2026 · InMobi track. Output of the pipeline on the sealed
dataset released in the final hours
([`InMobi/unseen_data`](https://github.com/sidagarwal04/click-a-thon-2026/tree/main/InMobi/unseen_data)):
1,500,000 events, Jul 6–10 2026. See
[`docs/UNSEEN_RUNBOOK.md`](../docs/UNSEEN_RUNBOOK.md) for the procedure.*

Generated 2026-08-02 · database `unseen` · **CONTINUATION** load: the new
events begin after the provided dataset ends, so the two were combined —
10,500,000 rows, Jun 1 – Jul 10 — giving every day in the new slice three full
weeks of history and the detector its strongest baseline rung,
`rung1_same_weekday_3w`.

## The seam, and why it decides everything

The spec ships regenerated dimension CSVs: **same IDs, different attribute
values**, and warns that joining new events to old dimensions gives wrong
segments. The mirror of that warning is just as wrong and much easier to miss
— joining *old* events to *new* dimensions.

We measured the two mappings against each other before trusting either:

```
os_version agreement      0.126
country agreement         0.079
chance level              0.125     <- agreement IS chance
```

The regeneration is a uniform reshuffle. The two eras are different labelling
universes, so **each era keeps its own attribution**: new events join the new
CSVs, history is carried over already denormalized, and neither is re-derived
from the other. The loader now measures this agreement on every run and prints
it (`scripts/load-unseen.sh`).

That the segment *semantics* survive the reshuffle is what makes a baseline
possible at all — the labels move, the behaviour behind them does not:

```
eCPM by region     history   new slice
  APAC               1.589       1.560
  EU                 2.947       2.898
  LATAM              1.360       1.338
  MEA                1.134       1.118
  NAM                3.631       3.558
```

Every region tracks across the seam. An earlier run of this report
re-attributed the history instead, which pulled every segment's baseline toward
the population mean; MEA then appeared to "crash" from 2.875 to 1.118 when its
eCPM had been 1.134 all along, and the real Android 15 incident dissolved into
a flat band and was reported as *global*. Both were artifacts of the load. The
corrected run below reproduces the known incidents exactly and finds three new
ones.

## What moved

| Metric | Window | Change | Verdict | Responsible | |
|---|---|---|---|---|---|
| fill rate | Jul 8–Jul 9 | -6.64% | ◐ partial | device OS = iOS 17.5 → app_00004 | **unseen** |
| eCPM | Jul 6 00:00–Jul 10 23:00 | -8.50% | ◐ partial | device model = iPhone 14 → app_00074 | **unseen** |
| revenue | Jul 9 | -14.60% | 🌍 global | — | **unseen** |
| fill rate | Jun 23–Jun 25 | -4.29% | 🎯 localized | device OS = Android 15 | known |
| request volume | Jun 21 | -45.68% | 🌍 global | — | known |
| revenue | Jun 21 | -46.21% | 🌍 global | — | known |

> **localized** — one segment explains it. **global** — everything moved
> together; naming a segment would be wrong. **partial** — a segment explains
> some of it, not all.

**The three known incidents reproduce unchanged on combined history** — Android
15 still localized at 98% explained, both Jun 21 movements still global. That
is the check that the seam was handled correctly, and it is why it is reported
here rather than assumed.

Two results worth a judge's attention. **Revenue on Jul 9 is declared global**
even though it sits one day inside the fill-rate incident: the strongest
candidate, country = MX, departed the population by +116% and was still
rejected, because removing it does not shrink the movement. And the two
July incidents are both **partial** — the system names a segment and says in
the same breath that the segment is not the whole story.

---

## The diagnoses (unseen window)

## Fill Rate — Jul 8–Jul 9  ·  **partial**

Fill rate fell from 78.4% to 73.2% (a -6.64% change) between Jul 8–Jul 9, a movement 24x larger than normal. The culprit was device OS version = iOS 17.5, whose fill rate dropped from 78.6% to 47.7% (-39.3%), departing the population by -35.8% with evidence strength of 156 standard errors. Excluding iOS 17.5, fill rate moved +2.57% versus -5.38% for all traffic, proving this segment drove the decline. This explains 52% of the movement, which further concentrates in app = app_00004 (0.9104 → 0.4049, -55.5%). The incident cost $105.41 in lost revenue, and apps app_00106, app_00283, app_00202, and app_00107 were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=3e898ce6-e938-4a96-837d-0de0981d88d5) · narrated by `deepseek-chat`</sub>

## Ecpm — Jul 6 00:00 to Jul 10 23:00  ·  **partial**

eCPM fell from $2.464 to $2.255, a -8.50% drop, which was 16x larger than normal movement. The culprit was device model = iPhone 14, whose value dropped from $2.518 to $1.951 (-22.5%), exceeding the population by -14.5%. Excluding iPhone 14, eCPM moved -6.09% versus -9.37% for all traffic, explaining 35% of the movement. Within iPhone 14, the drop concentrated in app = app_00074, falling from 2.6584 to 1.6887 (-36.5%). Device OS version = Android 13, Galaxy S23, iPhone 13, and iPhone 14 itself were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=2d7be6c4-e307-4f7c-a2ad-683d9698aa3b) · narrated by `deepseek-chat`</sub>

## Revenue — Jul 9  ·  **global**

Revenue on Jul 9 fell from $22.41 to $19.15, a -14.60% drop that is 5x larger than this metric's normal movement. The verdict is global, with proof that every segment moved with the population (-10.5%) and none stands apart. Country = MX, app category = news, region = LATAM, and campaign type = CPC were all ruled out because, despite departing the population by +116.1%, +165.8%, +137.9%, and +120.2% respectively, removing each leaves the movement as large or larger (e.g., removing MX leaves -11.96% of the original -10.49%). No single segment is responsible.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=5cd77701-84c0-45ab-b461-1cc918003103) · narrated by `deepseek-chat`</sub>

---

## The diagnoses (reproduced from the provided dataset)

## Fill Rate — Jun 23–Jun 25  ·  **localized**

Fill rate fell from 78.4% to 75.1% between Jun 23–Jun 25, a -4.29% change that was 15x larger than normal. The drop was localized to device OS version = Android 15, whose fill rate collapsed from 78.5% to 43.3% (-44.8%), departing from the population by -42.3% with evidence strength of 187 standard errors. Excluding Android 15, fill rate moved only -0.08% versus -4.36% for all traffic, fully explaining 98% of the movement. Had Android 15 held its baseline revenue per request, revenue would have been $69.53 higher. Device model = Galaxy S23, app = app_00246, device model = Redmi Note 12, and app = app_00160 were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=f01eb0b4-9f80-49fe-87f0-1447ce726bda) · narrated by `deepseek-chat`</sub>

## Request Volume — Jun 21  ·  **global**

Request volume on Jun 21 fell from 232,053 to 126,052, a -45.68% drop that is 38x larger than this metric's normal movement. The incident is global: every segment moved with the population (-43.5%), and no single segment stands apart. Advertiser vertical gaming (-4.0% relative), app category news (-2.5%), country AE (-2.1%), country ES (+2.0%), and ad format rewarded (-1.8%) were all ruled out as within normal spread.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=ef299582-7376-42ed-a651-a15475db56b4) · narrated by `deepseek-chat`</sub>

## Revenue — Jun 21  ·  **global**

Revenue on Jun 21 fell from $18.13 to $9.77, a -46.21% drop that is 15x larger than this metric's normal movement. The verdict is global, with every segment moving with the population at -44.8%, and no single segment stands apart as the culprit. The finance app category was ruled out because, despite standing out at -34.7%, removing it leaves -43.37% of the original -44.81%, accounting for only 3% of the movement. App app_00000, ecommerce, and gaming were also ruled out because, though they departed the population by +4.2% or -4.1%, none survived the removal test.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=4a87bdd1-c1d4-40ad-9bed-d8797ec9af41) · narrated by `deepseek-chat`</sub>

---

## Traces

One run, six investigations nested inside it. Public — no login needed.

**Run:** https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410

Each investigation span carries **the SQL actually executed**, its parameters,
rows returned and elapsed time — the working, not a claim about the working.

## Reproducing this

```bash
./scripts/load-unseen.sh /path/to/unseen unseen   # prints the seam agreement
CH_DB=unseen python3 -m engine.watch              # record what moved
CH_DB=unseen python3 -m engine.run --out out/unseen
```

`out/unseen/queries.sql` carries the exact SQL and per-incident parameters
behind every number above.

| File | What it is |
|---|---|
| `REPORT-unseen-incident.md` | this document |
| [`../out/unseen/diagnosis.md`](../out/unseen/diagnosis.md) | the prose alone |
| [`../out/unseen/evidence.json`](../out/unseen/evidence.json) | every computed number, machine-readable |
| [`../out/unseen/queries.sql`](../out/unseen/queries.sql) | the SQL behind every figure |
| [`../out/unseen/trace.txt`](../out/unseen/trace.txt) | Langfuse links |
