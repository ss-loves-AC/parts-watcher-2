# Diagnosis

Generated 2026-08-02T04:03:47.772628+00:00 · database `unseen` · 6 incident(s).

Every figure below was computed in ClickHouse and handed to the narrator as a finished string; the narrator has no database access and performs no arithmetic.

## Request Volume — Jun 21  ·  **global**

Request volume on Jun 21 fell from 232,053 to 126,052, a -45.68% drop that is 38x larger than this metric's normal movement. The incident is global: every segment moved with the population (-43.5%), and no single segment stands apart. Advertiser vertical gaming (-4.0% relative), app category news (-2.5%), country AE (-2.1%), country ES (+2.0%), and ad format rewarded (-1.8%) were all ruled out as within normal spread.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=ef299582-7376-42ed-a651-a15475db56b4) · narrated by `deepseek-chat`</sub>

## Fill Rate — Jul 8–Jul 9  ·  **partial**

Fill rate fell from 78.4% to 73.2% (a -6.64% change) between Jul 8–Jul 9, a movement 24x larger than normal. The culprit was device OS version = iOS 17.5, whose fill rate dropped from 78.6% to 47.7% (-39.3%), departing the population by -35.8% with evidence strength of 156 standard errors. Excluding iOS 17.5, fill rate moved +2.57% versus -5.38% for all traffic, proving this segment drove the decline. This explains 52% of the movement, which further concentrates in app = app_00004 (0.9104 → 0.4049, -55.5%). The incident cost $105.41 in lost revenue, and apps app_00106, app_00283, app_00202, and app_00107 were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=3e898ce6-e938-4a96-837d-0de0981d88d5) · narrated by `deepseek-chat`</sub>

## Ecpm — Jul 6 00:00 to Jul 10 23:00  ·  **partial**

eCPM fell from $2.464 to $2.255, a -8.50% drop, which was 16x larger than normal movement. The culprit was device model = iPhone 14, whose value dropped from $2.518 to $1.951 (-22.5%), exceeding the population by -14.5%. Excluding iPhone 14, eCPM moved -6.09% versus -9.37% for all traffic, explaining 35% of the movement. Within iPhone 14, the drop concentrated in app = app_00074, falling from 2.6584 to 1.6887 (-36.5%). Device OS version = Android 13, Galaxy S23, iPhone 13, and iPhone 14 itself were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=2d7be6c4-e307-4f7c-a2ad-683d9698aa3b) · narrated by `deepseek-chat`</sub>

## Fill Rate — Jun 23–Jun 25  ·  **localized**

Fill rate fell from 78.4% to 75.1% between Jun 23–Jun 25, a -4.29% change that was 15x larger than normal. The drop was localized to device OS version = Android 15, whose fill rate collapsed from 78.5% to 43.3% (-44.8%), departing from the population by -42.3% with evidence strength of 187 standard errors. Excluding Android 15, fill rate moved only -0.08% versus -4.36% for all traffic, fully explaining 98% of the movement. Had Android 15 held its baseline revenue per request, revenue would have been $69.53 higher. Device model = Galaxy S23, app = app_00246, device model = Redmi Note 12, and app = app_00160 were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=f01eb0b4-9f80-49fe-87f0-1447ce726bda) · narrated by `deepseek-chat`</sub>

## Revenue — Jun 21  ·  **global**

Revenue on Jun 21 fell from $18.13 to $9.77, a -46.21% drop that is 15x larger than this metric's normal movement. The verdict is global, with every segment moving with the population at -44.8%, and no single segment stands apart as the culprit. The finance app category was ruled out because, despite standing out at -34.7%, removing it leaves -43.37% of the original -44.81%, accounting for only 3% of the movement. App app_00000, ecommerce, and gaming were also ruled out because, though they departed the population by +4.2% or -4.1%, none survived the removal test.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=4a87bdd1-c1d4-40ad-9bed-d8797ec9af41) · narrated by `deepseek-chat`</sub>

## Revenue — Jul 9  ·  **global**

Revenue on Jul 9 fell from $22.41 to $19.15, a -14.60% drop that is 5x larger than this metric's normal movement. The verdict is global, with proof that every segment moved with the population (-10.5%) and none stands apart. Country = MX, app category = news, region = LATAM, and campaign type = CPC were all ruled out because, despite departing the population by +116.1%, +165.8%, +137.9%, and +120.2% respectively, removing each leaves the movement as large or larger (e.g., removing MX leaves -11.96% of the original -10.49%). No single segment is responsible.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/fa087deb-4813-42b5-a9fd-f5429eb10410?observation=5cd77701-84c0-45ab-b461-1cc918003103) · narrated by `deepseek-chat`</sub>
