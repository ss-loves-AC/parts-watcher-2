# Demo video — script, narration and scene plan

**Target 4:40, hard ceiling 5:00.** The statement says *skip restating the
problem* — so we open on the trap, not on "advertising is complex".

## Before you record

- [ ] Tunnel up: `ssh -f -N -L 3000:127.0.0.1:3000 kite@100.76.253.89`
- [ ] **Fresh detections**, so the dashboard is not showing hours-old rows:
      ```sql
      TRUNCATE TABLE pw.detections;
      ```
      then `python3 -m engine.run --out out/` once as a warm-up.
- [ ] **HyperDX time range → Last 24 hours.** It defaults to 15 minutes and
      will look empty. This is the single most likely thing to ruin a take.
- [ ] Terminal: dark, ~16pt, ~120×34. Nothing else on screen.
- [ ] Tabs pre-loaded, in order:
      **① HyperDX dashboard** *RCA — what broke and why*
      **② Langfuse trace** (expanded, showing nested spans)
      **③ GitHub report**
- [ ] Dry-run once. `engine.run` takes ~20s — know how long the pause is.
- [ ] Silence notifications.

**Record in four takes** (opening / live run / trace / loop) and cut together.
One continuous take invites a fumble at four minutes.

---

## SCENE 1 · The trap — 0:00–0:45

**Screen:** deck slide 03, full screen.

> On June 21st, ad requests fell forty-five percent. Every segment fell with it
> — banner, North America, ecommerce, all down forty-four.
>
> Rank those by absolute change and the biggest segment wins. Your system
> announces: *banner is responsible.* Confident. Specific. Completely wrong —
> nothing was responsible, the whole platform moved.
>
> The brief is blunt about this: **a single fabricated figure costs more than a
> missed anomaly.** So we built a system whose hardest skill is knowing when to
> say nothing.

*Beat. Cut.*

---

## SCENE 2 · One command — 0:45–1:45

**Screen:** clean terminal.

> One command. It reads nine million ad events in ClickHouse Cloud.

```bash
python3 -m engine.run --out out/
```

*(runs ~20s — keep talking, do not narrate the spinner)*

> Nothing here is an LLM deciding what to look at. Detection, attribution and
> proof are all SQL. A materialized view fans every event into a cube keyed by
> dimension and value, so **one query scans all twelve dimensions** in
> sixty-nine milliseconds.
>
> The model appears once, at the very end, and only to write a sentence.

*(output appears — five incidents, three pins, a trace URL)*

> Five movements found. Three causes pinned straight into HyperDX. One trace.

---

## SCENE 3 · The list — 1:45–2:35

**Screen:** tab ①, the HyperDX dashboard. Let it sit for two seconds before speaking.

> This is where a human looks. Every anomaly, and the segment responsible, on
> one line.

*Point at the rows as you say them.*

> Fill rate, June 23rd to 25th — **Android 15**. Remove Android 15 and
> ninety-eight percent of the drop goes with it. That is what *explains* means:
> how much of the movement disappears when you take that segment out.
>
> eCPM — **the finance category**. Ninety-eight percent again.
>
> And twice — **global. No segment responsible. Zero percent.** That's June
> 21st. The system looked, found nothing that stood clear of the population,
> and refused to name anyone.

*Scroll to the "Global — correctly refused to blame anyone" tile.*

> That refusal has its own panel, because it is the result we are proudest of.

---

## SCENE 4 · Why you can believe it — 2:35–3:35

**Screen:** tab ②, the Langfuse trace, spans expanded.

> One trace per run. Each investigation nested inside it — detect, scan,
> refine, evidence, narrate.

**Screen:** click into `2-segment-scan + 3-refine`, show the `queries` input.

> And here is the part that matters. The trace carries **the SQL we actually
> ran** — the query text, the parameters it ran with, how many rows came back,
> how long it took. You can copy that out and re-run it yourself.
>
> Traceability that is just a claim is not traceability.

**Screen:** click into `5-narrate`, show the input JSON.

> Here is everything the model received. Not the database. Not rows. **Finished
> strings.** Minus forty-four point eight percent, already formatted. "Device
> OS version", already named.
>
> No database handle, no arithmetic. A number that isn't in this JSON has
> nowhere to come from. Then we check every number in the paragraph back against
> the evidence — two failures and a deterministic template ships instead.
>
> Hallucination isn't discouraged here. It's **structurally impossible**, and
> verified.

---

## SCENE 5 · Attribution, and the intersection — 3:35–4:10

**Screen:** deck slide 07, then slide 11.

> Attribution asks three questions, and only the third can name a cause.
>
> **Is it real?** ClickHouse has `proportionsZTest` built in — Android 15 scores
> minus one eighty-seven against a next-best of minus fifty-two.
>
> **Is it distinctive?** Measured against the population's change, not its own
> size. That is what saves us on June 21st.
>
> **Is it responsible?** Remove the candidate and remeasure. One app beat the
> population by thirty-three percent and explained twenty-four — unusual, not
> responsible.

**Screen:** slide 11.

> And when one dimension isn't enough, it drills. June 29th looks like
> **Japan** — but only forty-six percent explained. Inside Japan it's **iOS
> 18.1**: fill from point seven-nine to point three-nine. Every other OS in
> Japan is flat.
>
> The system already knew it hadn't finished. *Partial* is it saying so.

---

## SCENE 6 · The loop closes — 4:10–4:40

**Screen:** HyperDX alert config, then the GitHub Actions run, then back to the dashboard.

> The alert doesn't need to know the answer in advance. The old version counted
> Android 15 failures above a threshold — which only works because we already
> knew.
>
> Now the detector writes what it finds to a table, and HyperDX asks one
> question: **did it find anything?** Threshold zero. No tuned number, no named
> segment.
>
> That fires a webhook, wakes a self-hosted runner, and the full investigation
> runs — ending back on this dashboard, with the cause pinned as its own view.
> Nobody copied anything across.
>
> We proved it by breaking a segment that appears nowhere in any config —
> Japan — and it was caught and correctly blamed.

**Screen:** deck slide 15.

> Every number checked. Every query inspectable. And silence is a valid answer.

*Cut.*

---

## Cutting-room rules

- **Never say a number the screen doesn't show.** Not doing that is the entire
  pitch.
- **Cut every spinner.** Jump-cut through the 20 seconds.
- If the live run misbehaves, use the recorded take. Say so if asked — cheaper
  than a bad demo.
- Do not read the slides aloud. They are for the eye; you carry the argument.

## If you only have three minutes

Keep Scenes 1, 2, 3 and 6 — the trap, the run, the list, the closed loop.
Scene 4 collapses to one line over the trace: *"every figure is machine-checked
against the evidence, and the trace carries the SQL that produced it."*

## The one thing to land

Most entries will find Android 15. The differentiator is **the two it refused to
localize**, and that the refusal is measured rather than lucky. Say the word
*global* out loud at least twice, and let the "0%" sit on screen while you do.
