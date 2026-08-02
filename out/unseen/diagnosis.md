# Diagnosis

Generated 2026-08-02T03:31:50.372072+00:00 · database `unseen` · 6 incident(s).

Every figure below was computed in ClickHouse and handed to the narrator as a finished string; the narrator has no database access and performs no arithmetic.

## Request Volume — Jun 21  ·  **global**

Request volume on Jun 21 fell from an expected 232,053 to an actual 126,052, a change of -45.68%, which is 38x larger than this metric's normal movement. The verdict is global, with no single segment responsible; every segment moved with the population at -43.5%, and none stands apart. The gaming vertical moved -4.0% relative to the population, the news app category moved -2.5%, country AE moved -2.1%, country ES moved +2.0%, and the rewarded ad format moved -1.8% — all within normal spread, ruling each out as the cause.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/edb983e6-e996-4096-8e92-596d62f32004?observation=04c583af-38c1-4ea8-99e2-e9d39220fe46) · narrated by `deepseek-chat`</sub>

## Fill Rate — Jul 8–Jul 9  ·  **partial**

Fill rate fell from 78.4% to 73.2% (a -6.64% change) between Jul 8–Jul 9, a movement 24x larger than normal. The culprit is device OS version = iOS 17.5, whose fill rate dropped from 78.6% to 47.7% (-39.3%), departing from the population by -35.8% with evidence strength of 156 standard errors. Excluding iOS 17.5, fill rate moved +2.57% versus -5.38% for all traffic, and this segment explains 52% of the movement. Within iOS 17.5, the movement concentrates in app = app_00004, which fell from 0.9104 to 0.4049 (-55.5%). The incident was not fully explained; apps app_00106, app_00283, app_00202, and app_00107 were ruled out because removing them did not shrink the movement. Had iOS 17.5 held its baseline revenue per request, revenue would have been $105.41 higher.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/edb983e6-e996-4096-8e92-596d62f32004?observation=1d27f68f-e058-4ab5-9966-a5265027ac09) · narrated by `deepseek-chat`</sub>

## Ecpm — Jul 6 00:00 to Jul 10 23:00  ·  **partial**

eCPM fell from $2.464 to $2.255, a -8.50% drop that was 16x larger than normal movement. The culprit was device model = iPhone 14, whose value dropped from $2.518 to $1.951 (-22.5%), which was -14.5% beyond the population. Excluding iPhone 14, eCPM moved -6.09% versus -9.37% for all traffic, explaining 35% of the movement. Within iPhone 14, the movement concentrated in app = app_00074, dropping from 2.6584 to 1.6887 (-36.5%). Had iPhone 14 held baseline, revenue would have been $183.28 higher; Android 13, Galaxy S23, and iPhone 13 were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/edb983e6-e996-4096-8e92-596d62f32004?observation=11a5f006-d579-4787-b08c-619757df6d85) · narrated by `deepseek-chat`</sub>

## Fill Rate — Jun 23–Jun 25  ·  **localized**

Fill rate fell from 78.4% to 75.1% between Jun 23–Jun 25, a -4.29% change that was 15x larger than normal. The drop was localized to device OS version = Android 15, whose fill rate went from 78.5% to 43.3% (-44.8%), departing from the population by -42.3% with evidence strength of 187 standard errors. Excluding Android 15, fill rate moved only -0.08% versus -4.36% for all traffic, fully explaining 98% of the movement. Had Android 15 held its baseline revenue per request, revenue would have been $69.53 higher. Device model = Galaxy S23, app = app_00246, device model = Redmi Note 12, and app = app_00160 were ruled out because removing them did not shrink the movement.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/edb983e6-e996-4096-8e92-596d62f32004?observation=018c18fc-268c-4cb6-a07d-1f087cd1fb07) · narrated by `deepseek-chat`</sub>

## Revenue — Jun 21  ·  **global**

Revenue on Jun 21 fell from $18.13 to $9.77, a -46.21% drop that is 15x larger than this metric's normal movement. The verdict is global, with every segment moving with the population at -44.8%, and no single segment stands apart as responsible. The finance app category was ruled out because, despite standing out at -34.7%, removing it leaves -43.37% of the original -44.81%, accounting for only 3% of the movement. App app_00000, ecommerce, and gaming were also ruled out because, although they departed the population by +4.2% or -4.1%, none survived the removal test.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/edb983e6-e996-4096-8e92-596d62f32004?observation=875d9a40-e12e-4546-99bb-d28cce7e79c0) · narrated by `deepseek-chat`</sub>

## Revenue — Jul 9  ·  **global**

Revenue on Jul 9 fell from $22.41 to $19.15, a -14.60% drop that is 5x larger than this metric's normal movement. The verdict is global, with proof that every segment moved with the population (-10.5%) and none stands apart. Country = MX, app category = news, region = LATAM, and campaign type = CPC were all ruled out because, despite departing the population by +116.1%, +165.8%, +137.9%, and +120.2% respectively, removing each leaves the movement as large or larger, so no single segment is responsible.

<sub>✅ every figure machine-verified against the computed evidence · [full trace of this investigation](https://langfuse.datagan.site/trace/edb983e6-e996-4096-8e92-596d62f32004?observation=d6dee213-d746-485b-b26e-59cb79cf77f8) · narrated by `deepseek-chat`</sub>
