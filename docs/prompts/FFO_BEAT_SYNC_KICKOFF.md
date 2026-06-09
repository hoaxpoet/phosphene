# FFO Beat-Sync Kickoff — Ferrofluid Ocean reads frozen; make the spikes punch on a steady, first-hit-anchored, tempo-locked beat pulse

> Hand this to a new Claude Code session verbatim. Do not summarise.
>
> **Suggested project/phase tag:** `FBS` (Ferrofluid Beat Sync). Confirm or rename with Matt before committing.

---

## READ THIS BEFORE ANYTHING ELSE — three rules that this work lives or dies by

1. **Matt is product/design lead. He is NOT an engineer.** Every explanation you give him is in **plain English about what he SEES on screen** — never code, never field names (`beat_phase01`, `drumsEnergyDev`, etc.), never math/formulas. The session that produced this kickoff failed Matt repeatedly by talking to him like a peer engineer; he said, verbatim, *"I am not an engineer"* and *"just word salad."* If you catch yourself writing a formula or a variable name in a message to Matt, stop and rewrite it as "the spikes bounce higher when the music hits harder."

2. **Do not over-promise. Verify with DATA before you claim anything works.** The originating work shipped a fix on a passing synthetic test and **failed live** at M7. Then it spent ten turns promising beat-sync behaviour that wasn't feasible. The standing rule now: say *"I'll measure X"*, not *"X works"*. If you can't measure it, say *"cannot verify"* — do not assert it.

3. **A manual M7 review CANNOT detect whether this is working.** Matt established this directly: a human cannot reliably eyeball whether spikes are beat-locked, or tell a 0.8 s lurch from a normal loud hit. **Validation is measurement** (does the pulse hold steady? does it land on the first hit? does the spike field actually move?), computed from recorded sessions — not Matt's eyes.

---

## TL;DR — what to build

**Ferrofluid Ocean reads "frozen / broken / inconsistent" for the first 20–30 s of playback and often throughout** — because its only reactive motion is one thin thing: spike *height* driven by the smooth, auto-levelled bass, which the leveller deliberately holds near-constant. Measured: the spikes' height barely moves (motion std **0.09** on bass-light tracks vs 0.27 on bass-heavy Mingus — which is exactly why Matt said Mingus "performed best"). The cure Matt has wanted from the first message is **beat-sync** — the Phosphene differentiator — which FFO currently doesn't do at all.

**The proposal (one mechanism):** the spikes **punch up on a steady beat pulse** that is

1. **anchored to the first strong hit** of the track (= what the listener hears as "one"; detected live, instantly),
2. **ticking at the tempo Phosphene computed before playback**,
3. **held dead steady — it does NOT wander** (this is the load-bearing rule),
4. with each punch's **height set by the live energy** (loud beat → tall, soft → small, silence → nothing),
5. and the whole preset's **colour/intensity set to the song's mood** from the pre-analysis (so it *looks like the song* from frame one),
6. then **handed off to the live-detected beat on a bar boundary around the 10 s mark** — so it goes from "convincingly aligned" to "actually locked" with no visible seam.

One design covers both sources: **streaming** = first-hit anchor + tempo; **local files** = the *same machine* fed a better starting point (the pre-analysed beat positions instead of the first-hit guess).

**Build and prove the CORE first** (the anchored steady pulse), with numbers, against existing sessions, **before** layering energy/mood/handoff. If a steady anchored pulse by itself doesn't read as aligned, almost nothing was risked and you stop there.

---

## The diagnosis — so you do not re-narrow the problem (the originating session's central failure)

- **The cold-start AGC `f.bass` spike (BUG-029 / AGC3.x, already committed) is a NARROW SIDESHOW. It is not why FFO reads frozen.** It's real (a ~0.8 s over-bright pop at some onsets) and it's fixed, but it is *the opposite* problem (too much, briefly) from "frozen" (too little, for 20–30 s). **Do not touch the AGC3 work, do not conflate it with this, do not "finish" it.** It is done and orthogonal.
- **The real problem:** FFO's spike motion is `baseline + 0.8 × clamp(f.bass, 0, 1)`, and `f.bass` is the *auto-levelled* (AGC-normalised) bass, which is held near-constant by design → the spikes barely pulse, and go dead whenever the bass is light (most intros, lots of music).
- **The cure is to make the spikes punch on the beat** — which they currently do not. They read the smooth bass, not the beat.

## Why this is genuinely hard — constraints you MUST respect (each was learned the hard way)

- **Beat-sync quality is capped by beat-PHASE accuracy, which is a hard, partly-open problem.** No change to FFO can make the spikes land tighter than the beat the system hands them.
- **The live beat tracker WANDERS during the opening.** Measured on Matt's local-file session: the live phase correction drifted out to **~90 ms on Cherub Rock and was still moving at 30 s**, because the live drift tracker chases the *bassline*, not the beat (Failed Approach #68: sub-bass onsets are bass *events*, not beats). **Syncing the spikes to that wandering phase looks like the visual is *searching* — worse than frozen.**
- **The single load-bearing insight: a *steady* pulse that's wrong-by-a-hair beats a *wandering* pulse that's right-on-average, every time.** Almost everything Matt has read as "broken sync" was the pulse *moving*. The pulse must be held steady; any correction must be slow enough to be invisible, applied at a bar boundary.
- **You CANNOT derive the cold-start beat phase from live tap audio.** Failed Approach #69 — six iterations proved it; the premise is retired. **Do not attempt to "detect the beat faster" in the first few seconds.** Anchor to the first hit instead.
- **You CANNOT retrieve the beat positions.** Spotify deprecated its audio-analysis/audio-features endpoints (tempo, time_signature, *and* per-beat timestamps) on 2024-11-27 — new apps get a 403, and as of May 2025 you need 250k+ MAU to even apply. Apple Music never exposed this data. Third-party services (Soundcharts/GetSongBPM/Tunebat) give BPM/key/time-signature but generally not start-aligned beat timestamps, with coverage/cost/accuracy caveats. **So the beats must be computed/anchored, not retrieved.** (Confirmed by web search this session.)
- **Streaming's opening cannot be literally beat-synced** — the preview clip Phosphene analyses is a ~30 s excerpt (often not the song's start), and the live playback offset isn't known, so there is *no measured beat position for the opening*. **The goal for streaming is the PERCEPTION of alignment**, which the proposal creates by *stacking* what IS precise (mood + energy, dead-on from frame one) under an *entrained*, anchored, steady beat pulse. The two precise layers carry the "it's with the song" feeling; the beat pulse only has to *feel* right.

## The perception model (the conceptual heart — keep it intact)

The perception of musical alignment in the first 5–10 s does **not** rest on beat precision (which isn't available for streaming). It is carried by three stacked layers:

1. **Character match — precise, free, frame one.** Palette/intensity set to the song's mood/key/energy (computed before playback). *Looks* like the song immediately.
2. **Energy match — precise, live, frame one.** Motion *size* driven by live energy. *Responds* to the song immediately, no warm-up.
3. **Beat anchor — a perceptually-convincing guess.** First strong hit = "one"; a rock-steady pulse at the pre-analysed tempo from there. The brain *entrains* to a steady on-tempo pulse within a couple of beats (and 5–10 s is plenty of beats), and accepts it as the beat.

Even where the beat anchor is slightly off, the whole thing reads as "with the song" because #1 and #2 genuinely are. You are not staking the result on a beat you can't nail.

---

## Staged plan — prove the core before you build the rest (do NOT collapse this)

### Stage 0 — Verify the load-bearing assumptions (no production code; measure, then report)

Two things the originating session asserted but never verified. Establish them from the existing session data first:

1. **Is the pre-analysed beat grid actually accurate on local files?** Compare the grid's predicted beat positions to where the real kicks/onsets land in `raw_tap.wav`. Accurate → local files can be fed the grid directly (best phase). Not accurate → even local files lean on the first-hit anchor. *This tells you the quality of your phase source before you build anything.*
2. **Is the first strong hit cleanly detectable as the anchor?** Confirm an onset/first-hit signal exists and fires at a sane time at track start in the session data.

Report both to Matt **in plain English with the numbers.** Stop.

### Stage 1 — Build ONLY the anchored steady pulse, and prove it

- Build just the pulse: **first-hit anchor + pre-analysed tempo + dead-steady, no wandering.** Drive the FFO spikes off it (replace the `f.bass` term in the spike-height function). Nothing else yet.
- **Test through the LIVE rendering pipeline FFO actually uses** (its `mv_warp`/staged path), for enough frames to cover the opening — not a bypassed single-frame test (Failed Approach #66). Use REAL recorded audio, never synthetic envelopes (Failed Approach #27 — synthetic is exactly what gave the false pass that failed M7).
- **Prove with measurement:** (a) the pulse anchors to the first hit; (b) it holds steady through the opening — quantify the wander (it must not drift the way the live tracker does); (c) the spike field now *moves* (spike-height motion up from the frozen ~0.09).
- Present the numbers to Matt **in plain English.** **STOP.** Do not build Stage 2/3 until Matt has seen Stage 1's proof and agreed the steady pulse reads as aligned.

### Stage 2 — Layer energy + mood (only after Stage 1 is accepted)

- Per-punch **height from live energy** (loud→tall, soft→small, a small floor so every beat registers while music plays, nothing at silence).
- Preset **colour/intensity from the song's mood** (pre-analysis).

### Stage 3 — The handoff

- Around 10 s, when live detection has a confident beat, **crossfade the pulse onto it on a bar boundary** — no seam. The correction must be applied slowly/at a bar line so it never reads as a skip or stutter.

---

## Hard rules (in addition to the three at the top)

1. **Keep the swell slow.** FFO's Gerstner swell is deliberately slow/atmospheric (arousal-driven amplitude). Putting rhythm into the swell *and* the spikes is the "competing rhythms" regression FFO fought through rounds 60–65 (Failed Approach #67 — one primitive per visual layer). **The spikes are the one rhythmic layer; do not touch the swell's timescale.**
- **Drive the pulse from the BEAT, not from kick/snare energy.** Matt was explicit: the kick and snare are *not always the beat* (syncopation). Transient-following is not beat-following. Use the beat grid / anchored tempo for *timing*; energy only sets *size*.
- **Verify in the production-grade pipeline. No shortcuts.** (Failed Approach #66 / the "test in production-grade pipeline" rule.) The originating cold-start fix passed bypassed tests and failed live.
- **Every claim of "it works" cites measured evidence** from a real session (pulse-steadiness numbers, anchor-accuracy, spike-motion). "Looks right" / "the test passes" is not evidence that it reads as aligned.
- **Multi-increment discipline.** This is a large change (new beat-pulse infrastructure + FFO spike-driver rewrite + onset anchor + handoff). Stage it as above; commit per stage; do not push without Matt's explicit "yes, push."

---

## Where to look (verify the specifics yourself — don't trust exact names/lines from this doc)

- **`PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.metal`** — `fo_spike_strength` is the spike height (currently `baseline + 0.8·clamp(f.bass,0,1)` — the frozen line you replace). `fo_swell_scale` is the slow swell (leave its timescale alone). The file's header comments hold the rounds 50–65 history — read it before editing.
- **The beat data** lives on the per-frame `FeatureVector` (the MSL mirror struct is in `Renderer/Shaders/Common.metal` — names are **snake_case** there, Failed Approach #72): the beat-phase clock, tempo, lock state, meter/beats-per-bar, downbeat flag. The beat tracking itself is `MIRPipeline` + the cached `BeatGrid` (Beat This! on the preview, installed at track start) + `LiveBeatDriftTracker` (the wandering live correction — this is what you must NOT chase blindly).
- **Onset detection** (for the first-hit anchor) is in the DSP layer (`BeatDetector`/`BandEnergyProcessor` produce onsets). Find the cleanest first-strong-hit signal.
- **Mood/energy** are computed during preparation (MoodClassifier + MIR on the preview) and reach the GPU via the FeatureVector (valence/arousal) and the AGC band energies.
- **The committed cold-start AGC fix** is in `BandEnergyProcessor.swift` (seed-from-first-audible + hold-through-silence + the AGC3.6 peak floor, gated to the main mix). **Leave it alone.**
- **Session data:** `~/Documents/phosphene_sessions/2026-06-09T13-06-15Z/` — the M7-failure session, **local files**: Battles EP (SZ2 / Tras 3 / IPT2 / Bttls / Dance) then Cherub Rock / Alameda / Mingus. `raw_tap.wav` is the first track (SZ2, 30 s, the audio whose first loud hit was the cold-start case). `features.csv` has all 8 tracks' beat + energy columns. (If absent, ask Matt to record fresh local-file *and* streaming sessions — you need both paths; streaming is the harder case the proposal is really about.)
- **Tools:** `tools/agc3/` has pure-Python readers for `features.csv` / `raw_tap.wav` (manual IEEE-float WAV read + a stdlib FFT) — a working starting point for measuring pulse-steadiness, anchor-accuracy, and spike-motion. Extend them; don't reinvent.
- **`CLAUDE.md`** — Audio Data Hierarchy (continuous energy is primary; beat is accent — note the stable beat-grid *phase* is allowed to drive *timing*, it's the jittery *onset* that's Layer-4-accent-only), the §Cold-Start Phase Contract, Failed Approaches #4/#27/#66/#67/#68/#69/#72, and the Ferrofluid memory notes (constant-field premise; one-primitive-per-layer).

---

## Done-when (Stage 1 — the gate that matters)

- [ ] **Stage 0 verified + reported:** is the pre-analysis beat grid accurate on local files (vs the real onsets in `raw_tap.wav`)? is the first-hit anchor cleanly detectable? — numbers, plain English, to Matt.
- [ ] The anchored steady pulse is built and drives the FFO spikes **through the live pipeline** (not a bypass).
- [ ] **Measured proof** on the session data: the pulse locks to the first hit and **holds steady** through the opening (wander quantified and small), and the spike field **moves** (motion up from ~0.09).
- [ ] Presented to Matt **in plain English with the numbers** — no code, no jargon.
- [ ] **STOP.** Stage 2/3 only after Matt agrees the steady pulse reads as aligned.

## What NOT to do

- **Do not** re-narrow to the cold-start AGC spike — it's a finished sideshow, not the problem. **Do not touch the AGC3 work.**
- **Do not** drive the spikes from the smooth `f.bass` (that's the frozen) or from raw kick/snare energy (transient-aligned, not beat-aligned).
- **Do not** make the swell rhythmic (competing-rhythms regression — keep it slow).
- **Do not** let the beat pulse wander. A steady-wrong-by-a-hair pulse beats a wandering-right-on-average one. Corrections happen slowly, at bar boundaries.
- **Do not** try to detect the cold-start beat phase from live audio (Failed Approach #69 — dead end), or build on retrieved beat timestamps (deprecated/unavailable).
- **Do not** promise sync you can't measure, or claim a manual M7 validated it (it cannot — validation is measurement).
- **Do not** explain anything to Matt in code, field names, or formulas. Plain English, what he sees.
- **Do not** build the whole stack and hope — prove the steady anchored pulse first, with numbers, then layer.

---

## One-paragraph context for the human reading this

This kickoff is the distilled output of a long, hard design conversation that started as a P3 cold-start bug and ended at the real issue: Ferrofluid Ocean has almost no beat-aligned motion, beat alignment is Phosphene's whole differentiator, and getting it — especially in the first 5–10 s of a stream — is genuinely hard because the precise beat position isn't knowable that early and can't be retrieved. The agreed answer is to stop chasing precision we can't get and instead **stack precise mood + energy under a steady, first-hit-anchored, tempo-locked beat pulse**, prove the pulse holds steady before building anything else, and validate everything by measurement rather than by eye. Build the core, show the numbers, in plain English. Then stop and let Matt look.
