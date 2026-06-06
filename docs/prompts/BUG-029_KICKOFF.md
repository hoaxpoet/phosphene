# BUG-029 Kickoff — The AGC `f.bass` cold-start spike pops/drops continuous-energy presets at every track onset

> Hand this to a new Claude Code session verbatim. Do not summarise.
>
> **Suggested project/phase tag:** `AGC3` (the AGC series so far: `AGC.1` shelved/retired —
> wrong root cause; `AGC2` = BUG-027, the per-band-EMA deviation fix, **resolved 2026-06-06**;
> `AGC3` = this, the cold-start *spike* in the AGC band values themselves). Confirm or rename
> the tag with Matt before committing anything.

---

## TL;DR

At the start of every track, `BandEnergyProcessor`'s total-energy AGC seeds its running average
off the preceding **silence**, so the **first audible frame explodes the AGC scale** and `f.bass`
spikes to **3.7–4.0** (vs a steady ~0.25) for ~1–2 s before the AGC catches up. Continuous-energy
presets that read `f.bass` directly — Ferrofluid Ocean's spike height is `1.0 + 0.8·clamp(f.bass,0,1)`
— **pop to maximum then collapse** as bass settles: a jarring "pop-and-drop" instead of a smooth
arrival. (During the silent pre-roll, `f.bass`=0, so those presets sit static; then they pop.)

This is the same AGC-cold-start family as **BUG-025** (shelved as P3 — a "one-time 2 s session-start
flash, not worth a cross-cutting AGC change") — but the evidence now shows it is **not** one-time:
it recurs at **every track onset** and is a *felt* artifact on `f.bass`-driven presets. That
re-justifies the work; the new session must confirm the "every track" claim and characterise it.

**This is NOT a quick clamp.** The AGC band values feed **every** preset, the deviation primitives,
and the per-stem analyzers — so any change to `BandEnergyProcessor` is cross-cutting. It needs a
measured-evidence-first decision with Matt, a fix that touches **only** cold-start (never steady-state
mix-density stability), and a **live-path** regression test (the lesson the AGC2 work learned the
hard way — see FA #66). Staged: **measure → decide with Matt → fix → validate → release.** Do not
skip to a fix.

---

## What this is

[BUG-029](../QUALITY/KNOWN_ISSUES.md#bug-029) was filed 2026-06-06 after the AGC2 (BUG-027) re-M7,
when Matt observed "motion not present consistently from the first frame" on Ferrofluid Ocean.
Diagnosis traced it to the AGC band-value spike, **not** to the AGC2 deviation work (FFO uses
`f.bass`/`arousal`, no deviation primitives). Severity **P3** (cosmetic, ~1–2 s at each onset);
Matt may re-rate to P2 if it materially hurts the per-track first impression. Domain `dsp.beat`
(AGC cold-start).

### The mechanism (read carefully — the fix turns on this)

In `BandEnergyProcessor.process(magnitudes:fps:)` (`PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift`):

1. `totalRawEnergy = raw6.reduce(0, +)` (`:204`) — sum of the 6-band RMS this frame.
2. Seed: `if frameCount == 0 { agcRunningAvg = max(totalRawEnergy, 1e-6) }` (`:207–208`); otherwise the
   EMA `agcRunningAvg = agcRate * agcRunningAvg + (1 - agcRate) * totalRawEnergy` (`:210`), with
   `agcRate` = `agcRateFast` 0.95 for the first `warmupFastFrames` 60 frames, then `agcRateModerate`
   0.992 (`:205`, `:128–138`).
3. `agcScale = 0.5 / agcRunningAvg` (`:213`), applied to **every** band: `agc3 = raw3.map { $0 * agcScale }`,
   `agc6 = raw6.map { $0 * agcScale }` (`:216–217`).

The spike has (at least) **two modes** — characterise both in the measurement increment:
- **Session start (frame 0):** the first frames are silence → `totalRawEnergy ≈ 0` → `agcRunningAvg`
  seeds at `1e-6` → `agcScale = 0.5/1e-6` is enormous → the first audible frame's band values explode.
- **Every later track onset:** the AGC is **not** reset per track (`MIRPipeline.reset()` is never
  called per track — verified `MIR_RESET=0` in the AGC2 work), but during the inter-track silence
  `totalRawEnergy ≈ 0`, so `agcRunningAvg` *decays* (0.992/frame) toward 0; when the next track's
  audio resumes, the decayed denominator gives a too-large scale → another spike.

Measured (session `2026-06-06T01-18-36Z`, local-file): **Cherub Rock** te=1.42 `f.bass`=**4.003**
(after ~1 s of `0.000` silence); **Alameda** te=0.66 `f.bass`=**3.697**. Steady `f.bass` is ~0.25.

### The visible effect

Ferrofluid Ocean (`fo_spike_strength` in `PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal`)
= `1.0 + 0.8·clamp(f.bass,0,1)`. At onset the clamp pins the 4.0 spike to 1.0 → spike height **1.8×**
(pop); as `f.bass` settles to ~0.25 → spike height ~1.2 (drop). Every preset reading `f.bass`
linearly for primary motion gets the same pop-and-drop.

> **Scope boundary — do not over-reach.** BUG-029 is the **spike**. Ferrofluid Ocean *also* looks
> static during the **silent pre-roll** (te 0→onset: `f.bass`=0 so the spikes don't animate, and its
> Gerstner swell is deliberately slow). That staticness is a **separate, preset-level** concern
> (ambient motion during silence) — *not* BUG-029, and not fixable by an AGC change. Stay on the spike.

### Why this is worth doing now (BUG-025 was shelved)

BUG-025 shelved this family because it was framed as a one-time ~2 s session-start flash — "not worth
a cross-cutting AGC change touching the catalog." The new evidence reframes it: the spike recurs at
**every track onset** and produces a felt pop-and-drop on continuous-energy presets. **Confirm the
"every track" claim in the measurement increment** (the filed evidence only covers tracks 1–2); if it
turns out to be session-start-only, surface that to Matt — it changes the cost/benefit.

---

## Read these first, before doing anything else

1. **[`docs/QUALITY/KNOWN_ISSUES.md` § BUG-029](../QUALITY/KNOWN_ISSUES.md)** — the filed entry +
   verification criteria. Source of truth; this kickoff expands it, never overrides it.
2. **`PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift`** — the whole `process(...)` (`:192–248`),
   the seed/EMA/scale (`:204–217`), the warmup constants (`:128–138`), and `reset()` (`:251`). **The
   total-energy AGC is load-bearing for mix-density stability (D-026 / Audio Data Hierarchy) — the fix
   must change ONLY cold-start/silence behaviour, never steady state.**
3. **`docs/QUALITY/KNOWN_ISSUES.md` § BUG-025** — the shelved sibling (same AGC-cold-start root). Read
   why it was shelved; your job is to justify + scope what it deferred.
4. **`docs/QUALITY/KNOWN_ISSUES.md` § BUG-018** — "stem deviation primitives exceed `[0,1]` during
   cold-start," fixed by SAR.1's seed-from-first-non-zero in `StemAnalyzer`. **`BandEnergyProcessor` is
   also used per-stem** (`StemAnalyzer.energyProcessors[0..3]`), so your fix affects stem energy +
   stem deviations too — don't regress BUG-018.
5. **`docs/DECISIONS.md` D-146 + `PhospheneEngine/Sources/DSP/BandDeviationTracker.swift`** — the AGC2
   cold-start *precedent*: a two-speed warmup that converges a per-band EMA *through* the spike. It is
   at the **deviation** layer and does **not** touch `f.bass` — so it does NOT fix BUG-029. Read it for
   the *pattern* (two-speed warmup, value ceiling, seed-from-first-non-zero), and to avoid confusing
   the two layers.
6. **`PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal`** — `fo_spike_strength` (the
   `f.bass` consumer) — the canonical victim + your manual-validation target.
7. **CLAUDE.md** — §Audio Data Hierarchy (Layer 1 continuous energy is the primary driver, active from
   frame 1 — this bug corrupts the *first* frames of it), the **Defect Handling Protocol**, and the
   **"Decisions presented to Matt must be framed in product-level language"** rule (both binding here).
8. **Failed Approach #66** (CLAUDE.md) — test/prod parity gap. The AGC2 cold-start hole shipped because
   its tests bypassed the live path; the fix was caught only after a wasted M7 round. **Write a
   live-path silence→onset test FIRST this time.**
9. **Reference session for measurement** (do not synthesise — Failed Approach #27):
   `~/Documents/phosphene_sessions/2026-06-06T01-18-36Z/` (local-file: Cherub Rock, Alameda, Mingus,
   Wilhelms Scream — multiple track onsets). If absent, ask Matt to record fresh sessions with several
   track changes on **both** capture paths (the spike must be characterised on streaming too).
   The AGC2 measurement harness `tools/agc2/measure_deviation_centring.py` is a starting point for
   reading `features.csv`.

---

## Hard rules

1. **Multi-increment protocol (CLAUDE.md Defect Handling).** Cross-cutting AGC change. Run the staged
   plan below; do not collapse it.
2. **Measure before you decide; decide with Matt before you fix.** Reconstruct the spike's real shape
   from the session CSVs first: magnitude, duration, which track onsets, both capture paths, and the
   inter-track-silence-decay vs frame-0-seed split. The fix approach is Matt's call on measured
   evidence, framed in product language — not a number you pick.
3. **Change ONLY cold-start/silence behaviour.** The total-energy AGC's steady-state response is the
   mix-density-stability guarantee (D-026). A fix that shifts steady-state band values is wrong. Prove
   steady-state is byte-identical (or explain every shift).
4. **Do not clamp `f.bass` to a low ceiling at the AGC output** to "solve" it — that throws away
   dynamic range on legitimately loud moments (the whole point of the AGC headroom). Bound/ramp the
   *scale* or the *seed*, not the output range.
5. **Write the live-path test FIRST (FA #66).** Before the fix: a test that drives silence→onset→steady
   through the **real** `BandEnergyProcessor` (and ideally through `MIRPipeline.process`), asserts the
   spike is reproduced un-fixed, then green after the fix. Isolation-only tests are insufficient.
6. **Golden hashes:** `PresetRegressionTests` feed hand-built FeatureVectors and likely **bypass** the
   live AGC, so they may not shift — **verify** this, and don't assume "no drift" without checking. The
   real validation is **live** (M7), because the change is cold-start-only.
7. **Manual M7 across continuous-energy presets, both paths.** Every preset reads continuous energy, so
   the catalog is in scope; the highest-signal targets are the `f.bass`-for-primary-motion ones
   (Ferrofluid Ocean first). Confirm the pop-and-drop is gone AND nothing regressed mid-track.
8. **`KNOWN_ISSUES.md` (Resolved + commit) and `RELEASE_NOTES_DEV.md` updates are mandatory**, plus
   `ENGINEERING_PLAN.md` and (if the AGC's documented behaviour changes) the
   `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` continuous-energy row + CLAUDE.md.
9. **Stop and report** the moment any of these fire: the reference session is missing; the measured
   spike contradicts this kickoff (e.g. it's session-start-only); the fix needs broader changes than
   the chosen approach authorised (e.g. you find yourself wanting to reset `MIRPipeline` per track —
   that has its own implications, surface it separately); a steady-state golden hash shifts you didn't
   expect; or you're producing structure as a substitute for an answer.

---

## Staged plan

### AGC3.1 — Instrument & measure (commit, then STOP)

Produce the evidence that grounds Matt's decision; leave it as a permanent diagnostic. **No production
code change.**

1. From the reference session(s), per track onset and per capture path, report: the **peak** `f.bass`
   (and the 6 bands) in the first ~3 s, the **steady** value, the **ratio**, the **duration** until it
   settles to within ~1.5× steady, and the **silent-pre-roll length** before onset.
2. Determine the **mechanism split**: is the spike session-start-only (frame-0 seed) or every-track
   (inter-track-silence decay)? Correlate spike magnitude with inter-track-silence duration. Confirm or
   refute the "every track onset" claim.
3. Confirm the downstream effect: `fo_spike_strength` (and any other `f.bass`-linear preset) pops then
   drops. Confirm the stem path (`StemAnalyzer`'s per-stem `BandEnergyProcessor`) shows the same onset
   spike (BUG-018 territory).
4. Write the table into the increment's working notes + extend the BUG-029 evidence in `KNOWN_ISSUES`.
   Commit (`[AGC3.1] dsp: measure the AGC cold-start band-value spike across real sessions`). **Stop.
   Bring the evidence to Matt.**

### AGC3.2 — Decision gate with Matt (no code)

Present the fix approaches **in product language** (next section) with the AGC3.1 evidence + a
recommendation. Matt picks one. File the decision in `DECISIONS.md` — **grep `^## D-` for the next free
number first** (D-146 is the AGC2 decision; verify the current max). Record the chosen approach,
evidence, and rejected options.

### AGC3.3 — Fix (test-before-fix, live-path test first)

1. **Write the failing live-path test first** (silence→onset→steady through the real
   `BandEnergyProcessor` / `MIRPipeline.process`); watch it reproduce the spike; *then* fix.
2. Implement the chosen approach in `BandEnergyProcessor`, touching **only** cold-start/silence. Mirror
   the existing patterns where sensible (seed-from-first-audible like SAR.1; a two-speed warmup like
   AGC2.4.1's `BandDeviationTracker`; a scale floor/ramp).
3. Prove steady-state is unchanged (a steady-input test asserting the post-warmup band values match the
   pre-fix values). Do not regress BUG-018 (stem cold-start ceiling) — extend/keep its gate.

### AGC3.4 — Validation (full sweep + catalog M7)

- Full engine suite green; app build green; SwiftLint `--strict` clean.
- `PresetRegressionTests`: surface any golden shift with its cause (expected: none, if fixtures bypass
  the live AGC — verify). Regenerate only with Matt's approval.
- **Matt M7, both paths**, on continuous-energy presets — Ferrofluid Ocean first (the pop-and-drop must
  be gone and the onset smooth), plus a sample of `f.bass`-driven presets and a spot-check that
  mid-track behaviour and the AGC2 deviation primitives are unaffected.

### AGC3.5 — Release notes & close

`KNOWN_ISSUES.md` BUG-029 → `Resolved` + commit + ticked boxes; `RELEASE_NOTES_DEV.md` entry;
`ENGINEERING_PLAN.md` rows; `RENDER_CAPABILITY_REGISTRY.md` continuous-energy row + CLAUDE.md if the
AGC's documented cold-start behaviour changed. Closeout report per CLAUDE.md. Commit locally to `main`;
**do not push without Matt's explicit "yes, push."**

---

## Decision points for Matt (AGC3.2 — frame in product language)

> Matt is product/design lead. Each option says **what he sees**, with trade-offs and a recommendation
> he can ratify without engineering math. Sharpen the phrasings with the AGC3.1 evidence (e.g. "today
> the surface jumps to full height for ~1.5 s at every track start, then settles").

**The question:** *Today, at the start of every track the picture lurches — presets driven by overall
loudness jump to full intensity for a second or two, then settle. How should we smooth that arrival?*

- **(a) Ease the loudness meter in at each track start.** Instead of the meter cold-starting and
  over-reacting to the first sound, it ramps to the right level over the first second or two — so the
  picture *arrives* into the music instead of lurching. *Trade-off:* the very first moment of a track
  is slightly muted before it settles (a gentle fade-in, not a pop). Touches the shared loudness meter,
  so every preset is affected — needs a catalog look. *(Likely recommendation, pending AGC3.1.)*
- **(b) Cap how hard the picture can jump at a track start.** Keep the meter as-is but clip the
  over-reaction so the jump can't exceed a sane amount. *Trade-off:* simpler, but the first loud hit of
  a track still reads a bit strong (just not a full white-out); less smooth than (a).
- **(c) Leave the engine; fix it per-preset.** Each preset softens its own response to the loudness
  meter at track start. *Trade-off:* no shared-engine risk, but every preset author must remember it
  forever, and presets that already shipped stay un-fixed until individually re-touched.

State the cost honestly: (a)/(b) change the shared loudness meter that feeds **every** preset and the
music-reactivity primitives — so they need a fresh catalog look even though the change is only at track
starts.

---

## Done-when (from KNOWN_ISSUES verification criteria + protocol)

- [ ] **AGC3.1 evidence table** from ≥ 1 real multi-track session (ideally both paths); the spike's
      magnitude/duration/which-onsets characterised; the "every track" claim confirmed or refuted.
- [ ] **Matt has chosen** (a)/(b)/(c) on that evidence; the decision is filed in `DECISIONS.md`.
- [ ] **Automated (live-path):** on a silence→onset fixture through the real pipeline, `f.bass` does
      not exceed ~N× steady after the first ~M frames (thresholds set from AGC3.1). Reproduced the
      spike un-fixed → green with the fix.
- [ ] **Automated:** a steady-state test proves post-warmup band values are unchanged (no steady-state
      regression); BUG-018 stem cold-start gate still green.
- [ ] Full engine suite green; app build green; SwiftLint clean.
- [ ] `PresetRegressionTests`: no drift, OR every shift surfaced + Matt-approved.
- [ ] **Manual M7:** Matt confirms continuous-energy presets (Ferrofluid Ocean first) arrive smoothly
      at track onset — no pop-and-drop — and nothing regressed mid-track, both paths.
- [ ] `KNOWN_ISSUES.md` BUG-029 → `Resolved` (commit); `RELEASE_NOTES_DEV.md`, `ENGINEERING_PLAN.md`,
      and (if AGC behaviour changed) `RENDER_CAPABILITY_REGISTRY.md` + CLAUDE.md updated.
- [ ] Closeout report filed. Local commit on `main`; not pushed without "yes, push."

---

## What NOT to do

- **Do not skip to a fix.** Measure the spike's real shape (which onsets, how big, how long, both
  paths) first; the (a)/(b)/(c) call is Matt's on that evidence.
- **Do not change steady-state AGC behaviour.** Only cold-start/silence. The total-energy AGC's
  steady-state response is the mix-density-stability guarantee (D-026); shifting it is a regression.
- **Do not clamp `f.bass` to a low ceiling at the AGC output** — that kills dynamic range on loud
  moments. Bound/ramp the *scale* or the *seed*.
- **Do not test only in isolation.** Write the live-path silence→onset test first (FA #66) — the AGC2
  cold-start hole shipped exactly because its tests bypassed the live path.
- **Do not confuse this with the AGC2 deviation warmup.** `BandDeviationTracker`'s warmup is at the
  deviation layer and does not touch `f.bass`; BUG-029 is the AGC band value itself.
- **Do not try to fix the silent-pre-roll staticness** (FFO showing little motion before audio starts)
  here — that's a separate preset-level/ambient-motion concern, not the AGC spike.
- **Do not reset `MIRPipeline` per track as the fix** without surfacing it — it's not currently called
  per track (which also makes the shader-facing `trackElapsedS` a session clock); changing that has
  wider implications and is its own decision.
- **Do not regress BUG-018** (stem cold-start `[0,1]` ceiling) — `BandEnergyProcessor` is used per-stem
  too; verify the stem gate stays green.
- **Do not synthesise the measurement audio** (FA #27). Use the recorded session; if it's missing, ask
  Matt to record real multi-track sessions on both paths.
