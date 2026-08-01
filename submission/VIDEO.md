# Demo video — script, narration and scene plan

**Target 4:30, hard ceiling 5:00.** The statement says *skip restating the
problem* — so we open on the trap, not on "advertising is complex".

## Before you record

- [ ] Tunnel up: `ssh -f -N -L 3000:127.0.0.1:3000 kite@100.76.253.89`
- [ ] Terminal: dark, ~16pt, window ~120×34. Nothing else on screen.
- [ ] `cd ~/Documents/projects/parts-watcher && clear`
- [ ] Browser tabs pre-loaded, in order: **Langfuse trace** · **HyperDX saved
      searches** · **the GitHub report**
- [ ] Dry-run once. `engine.run` takes ~20s — know exactly how long the pause is.
- [ ] Silence notifications.

**Record in four takes** (opening / live run / results / loop) and cut together.
One continuous take invites a fumble at 4 minutes.

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

## SCENE 2 · What it does, in one run — 0:45–2:00

**Screen:** clean terminal.

> One command. It reads nine million ad events in ClickHouse Cloud.

```bash
python3 -m engine.run --out out/
```

*(runs ~20s — keep talking, don't narrate the spinner)*

> While that runs — nothing here is an LLM deciding what to look at. Detection,
> attribution and proof are all SQL. A materialized view fans every event into a
> cube keyed by dimension and value, so **one query scans all twelve
> dimensions** in sixty-nine milliseconds.
>
> The model appears once, at the very end, and only to write a sentence.

*(output appears)*

> Five movements. Two localized, two global, one partial. And it pinned three
> findings straight into HyperDX.

**Screen:** `cat out/REPORT.md` — or the GitHub tab. Hold on the summary table.

> Fill rate, June 23rd to 25th, down four point three percent — **Android 15**.
> eCPM — **the finance category**.
>
> And twice: **global. No segment responsible.** That's June 21st. It declined.

---

## SCENE 3 · Why you can believe the numbers — 2:00–3:00

**Screen:** the Langfuse trace, expanded to show nested spans.

> Every investigation is one trace. Detect, scan, refine, evidence, narrate —
> each carrying its real inputs and outputs. A judge opens this and follows what
> was checked, in what order, and why.

**Screen:** click into the `5-narrate` generation, show the input JSON.

> Here's what the model was given. Not the database. Not rows. **Finished
> strings.** Minus forty-four point eight percent, already formatted. "Device OS
> version", already named.
>
> It has no database handle and does no arithmetic. A number that isn't in this
> JSON has nowhere to come from.
>
> Then we check: every numeric token in the paragraph must appear in the
> evidence. Two failures and a deterministic template ships instead. We tested it
> against a re-rounded figure and an invented one — both caught.
>
> Hallucination isn't discouraged here. It's **structurally impossible**, and
> verified.

---

## SCENE 4 · Attribution, and the intersection — 3:00–3:50

**Screen:** deck slide 07, then slide 11.

> Attribution asks three separate questions, and only the third can name a cause.
>
> **Is it real?** ClickHouse has `proportionsZTest` built in — Android 15 scores
> minus one eighty-seven against a next-best of minus fifty-two.
>
> **Is it distinctive?** Measured against the population's change, not its own
> size. That's what saves us on June 21st.
>
> **Is it responsible?** Remove the candidate and remeasure. Whichever leaves
> least behind is the cause. One app beat the population by thirty-three percent
> and explained twenty-four percent of the movement — unusual, not responsible.

**Screen:** slide 11.

> And when one dimension isn't enough, it drills. The June 29th drop looks like
> **Japan**. It isn't. It's **iOS 18.1 in Japan** — fill from point seven-nine to
> point three-nine. Every other OS in Japan is flat; iOS 18.1 elsewhere barely
> moved.
>
> The system already knew it hadn't finished — that's what *partial* means. Now
> it acts on its own signal.

---

## SCENE 5 · The loop closes — 3:50–4:30

**Screen:** HyperDX, saved searches list showing the `RCA:` entries.

> It doesn't just report. When it localizes a cause, it pins it — the next person
> to open HyperDX finds *"RCA: device OS version = Android 15"* already there.
> Nobody copied anything across.

**Screen:** the alert config, then the GitHub Actions run.

> And the alert doesn't need to know the answer in advance. The old version
> counted Android 15 failures above a threshold — which only works because we
> already knew. Now the detector writes what it finds to a table, and HyperDX
> asks one question: **did it find anything?** Threshold zero.
>
> That fires a webhook, wakes a self-hosted runner, and the full investigation
> runs. We proved it by breaking a segment that appears nowhere in any config —
> Japan — and it was caught and correctly blamed.

**Screen:** deck slide 15.

> Every number checked. Every claim traced. And silence is a valid answer.

*Cut.*

---

## Cutting-room rules

- **Never say a number the screen doesn't show.** The whole pitch is that we
  don't do that.
- **Cut every spinner.** Jump-cut through the 20 seconds.
- If the live run misbehaves, use the recorded take. Say so if asked — that is
  cheaper than a bad demo.
- Do not read the slides aloud. The slides are for the eye; you carry the
  argument.

## If you only have three minutes

Keep Scenes 1, 2 and 5. The trap, the run, the closed loop. Scene 3 becomes one
line: *"every figure is machine-checked against the computed evidence, and every
investigation is traced."*

## The one thing to land

Most entries will find Android 15. The differentiator is **the two it refused to
localize** — and that this refusal is measured, not luck. Say the word *global*
out loud at least twice.
