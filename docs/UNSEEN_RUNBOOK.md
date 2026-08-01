# Unseen incident — runbook

Follow this top to bottom when the sealed dataset lands. It is written to be
executed under time pressure, not read for understanding — the reasoning is in
[DESIGN.md](DESIGN.md).

**The governing rule: change nothing about the detector.** Every threshold and
window was set without reference to the planted anomalies. Tuning them once you
can see the new data is how a calibrated system becomes an overfitted one, and
the criterion is judged on comparable output across teams.

Budget **90 minutes** from file-in-hand to submitted. It has taken ~3 minutes in
rehearsal; the rest is contingency.

---

## 0. Before the drop (do this while waiting)

- [ ] `git pull` and confirm clean: `git status`
- [ ] Regression suite green on our data — this proves the engine is healthy
      *before* unfamiliar input, so a later failure is attributable to the data:
      ```bash
      python3 -m unittest discover -s tests -t . -q
      ```
- [ ] Langfuse reachable. Either open the tunnel, or plan to run on the VPC:
      ```bash
      ssh -f -N -L 3000:127.0.0.1:3000 kite@100.76.253.89
      curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/api/public/health
      ```
- [ ] Decide where to run. **The VPC is the safer choice** — Langfuse is
      localhost there, so traces cannot fail on a tunnel dropping.

---

## 1. Load it (~60s)

Put the new files in one directory. The loader expects the same four names:
`ad_events.parquet`, `apps.csv`, `advertisers.csv`, `geo_device.csv`.

```bash
./scripts/load-unseen.sh /path/to/unseen unseen
```

**Use `load-unseen.sh`, not `load.sh`.** The new events are most likely a
CONTINUATION of the data we already hold, not a replacement — and that
distinction decides how well detection works:

- **Continuation** (new events start after ours end) → the script combines
  them with the existing 9M rows, so every new day has three weeks of history
  behind it and the detector baselines at **rung 1**, its strongest setting.
- **Replacement** (ranges overlap) → combining would double-count, so it loads
  the new events alone and accepts whatever history they carry.

It compares the ranges and decides itself, printing which mode it chose.
Rehearsed both ways: a continuation produced 10.9M rows spanning Jun 1 – Aug 2
and `rung1_same_weekday_3w`.

**It writes to a fresh database.** Never load over `pw` — if anything is wrong
with the new file you still have a working system to fall back to.

### Gate — do not continue unless all of these hold

The loader prints them; it also fails hard on the first two.

| Check | Expected | If it fails |
|---|---|---|
| every dimension loaded | non-zero rows each | rerun; a transient replica read once reported 0 |
| cube integrity | no dimension collapsed | a dimension has one value — check the CSV actually has data |
| `unmatched_geo` / `unmatched_app` | `0` | join keys differ; the new dims may not cover the new events |
| `distinct_os` / `distinct_country` / `distinct_category` | > 1 | a dimension collapsed; **totals still reconcile in this case, so trust these, not the row count** |
| `rows` | parquet count, plus 9M if CONTINUATION | |
| no `FATAL: … event_time before 2000` | — | the parquet's timestamp column isn't named `event_time`; **Parquet inserts match by NAME, not position**, so it silently defaulted to 1970. The script prints the actual column names |

---

## 2. Sanity-look before trusting anything (~1 min)

```bash
CH_DB=unseen python3 -m engine.detect
```

Read the header line, not just the incidents:

- **`baseline: rung1_same_weekday_3w`** — good, full strength.
- **`rung2`/`rung3`** — shorter history, weaker but fine.
- **`rung4_same_hour_*`** — under a week of data. Detection cannot tell a
  Sunday from a Tuesday. Still report, but say so (§5).
- **`data spans only N days`** and it exits — under two days, no baseline is
  possible. Go to §6.

Then eyeball the numbers:

- Any `effect%` at or beyond **−100%** is impossible → stop, something is wrong
  with the load.
- **Zero incidents** is a legitimate answer, but check the slice actually has a
  usable window first (§6).
- More than ~10 incidents suggests the baseline is contaminated (§6).

---

## 3. Run the full pipeline (~40s)

```bash
CH_DB=unseen python3 -m engine.run --out out/unseen
```

Or on the VPC, which is safer for traces:

```bash
rsync -az --delete --exclude out --exclude __pycache__ --exclude .git \
  ~/Documents/projects/parts-watcher/ kite@100.76.253.89:/tmp/rca-src/
ssh kite@100.76.253.89 'set -a; . ~/rca/rca.env; set +a; cd /tmp/rca-src && \
  CH_DB=unseen python3 -m engine.run --out /tmp/unseen'
```

Produces `out/unseen/`:

```
diagnosis.md     plain language, one section per incident
evidence.json    every computed number + the ruled-out ledger
trace.txt        Langfuse links (public URL — check they are NOT 127.0.0.1)
queries.sql      the SQL and parameters behind every figure
```

### Gate

- [ ] `diagnosis.md` — every section ends **"every number verified against the
      evidence"**. If any says *unsourced*, the narrator invented a figure and
      the guard caught it; the deterministic template was used instead. That is
      safe to submit but mention it.
- [ ] `trace.txt` — links start `https://langfuse.datagan.site`. **Open one.**
      A trace nobody can open scores nothing: *"no trace, no credit."*
- [ ] Trace shows the hierarchy: run → investigation → scan/evidence/narrate.

---

## 4. Load it into the UIs (~2 min, optional but cheap)

Makes the submission browsable rather than four files.

```bash
CH_HOST=... CH_USER=... CH_PASSWORD=... CH_DB=unseen \
GH_DISPATCH_PAT=... \
ssh kite@100.76.253.89 "docker exec -i -e CH_HOST -e CH_USER -e CH_PASSWORD \
  -e CH_DB -e GH_DISPATCH_PAT ch-hacker-mongodb-1 mongosh --quiet hyperdx" \
  < scripts/provision-clickstack.js
```

Repoints the `Ad Events` source at `unseen`, so HyperDX and the LibreChat agent
both see the new data.

---

## 5. Write the submission (~20 min)

The diagnosis is generated; this is the framing around it.

- [ ] Copy `diagnosis.md` in full — it is the deliverable.
- [ ] State **which baseline rung** fired and what that means. If it was rung 4,
      say plainly that a short slice yields weaker claims. Judges reward stated
      limits over quiet confidence.
- [ ] Include **at least one thing ruled out**, with its number. The
      `ruled_out` ledger is already in `evidence.json`.
- [ ] If any incident is `global`, **lead with it.** "No segment is
      responsible" is the hardest result to produce and the easiest to get
      wrong — most systems will name the biggest segment.
- [ ] Attach `queries.sql` and say it can be re-run against the answer key.
- [ ] Paste the Langfuse trace URLs.

---

## 6. When it goes wrong

Every one of these has actually happened.

| Symptom | Cause | Do this |
|---|---|---|
| `effect%` beyond −100%, or absurd figures | partial boundary bucket used as a baseline | should be handled — if not, drop the first and last day from the slice and reload |
| Zero incidents on data that clearly moved | a whole grain died for want of history, or the movement is inside the first week (which has no history to compare against) | check the rung; if the file is short, this may be genuine and unavoidable |
| Detections everywhere, all "up" | the baseline is contaminated by an anomaly the two-pass could not vet, because it sits in the first period | report the strongest few, state the baseline is unverified |
| Exits with "data spans only N days" | under two days | there is no fix; report honestly that the slice is too short to baseline, and show the raw metric movement instead |
| Traces missing, `trace.txt` says 403 | Cloudflare Access — you are running off-VPC without a tunnel | open the tunnel, or run on the VPC, and re-run |
| Dimensions collapsed, but totals reconcile | a dimension table failed to load | **totals reconciling does not prove dimensions loaded** — reload and check cardinality |
| Numbers differ from a colleague's | different database, or someone wrote to a shared one | confirm `CH_DB`; `rca` is shared and has stray rows |

**If the pipeline cannot produce a diagnosis at all**, submit the detector
output alone (`engine.detect`) plus an honest note. A partial, truthful result
scores more than nothing, and far more than a hand-written diagnosis with no
trace — which explicitly scores zero.

---

## 7. Submit

- [ ] Public repo, MIT licence, all commits inside the window — already true
- [ ] `out/unseen/` committed and pushed
- [ ] ≤500-word summary · ≤5-min video · ≤15-slide deck
- [ ] **Only the Team Captain can submit, and the portal closes server-side.**
      Submit at **T+23.5h, not T+24h.**

## Afterwards

- [ ] Rotate the GitHub PAT — it is in a chat transcript
- [ ] Stop the runner if it should not keep picking up dispatches:
      `ssh kite@100.76.253.89 'cd ~/actions-runner-pw && sudo ./svc.sh stop'`
