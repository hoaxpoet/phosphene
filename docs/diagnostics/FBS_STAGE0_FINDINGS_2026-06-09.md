# FBS Stage 0 — Load-bearing-assumption verification (2026-06-09)

**Phase tag:** FBS (Ferrofluid Beat Sync) — *pending Matt's confirm/rename.*
**Scope:** Stage 0 of `docs/prompts/FFO_BEAT_SYNC_KICKOFF.md`. Measurement only — **no production code changed.** Establishes the quality of the phase source before any pulse is built.

## Questions (from the kickoff)

1. **Is the pre-analysed (cached) BeatGrid accurate on local files?** Compare the grid's predicted beats to where the real onsets land in `raw_tap.wav`. Decompose into **tempo** and **phase**.
2. **Is the first strong hit cleanly detectable as the anchor?**
3. (Supporting) **How far does the live drift tracker wander over the opening?** — motivates "hold the pulse steady."

## Data

- **`~/Documents/phosphene_sessions/2026-06-09T13-06-15Z/`** — the M7-failure session. 8 local tracks (`features.csv`, 17226 frames). `raw_tap.wav` = IEEE-float32 stereo 44.1 kHz, first **~17 s = SZ2** then **~13 s = Tras 3** (SZ2 auto-advanced at 17 s; the 30 s tap bled into track 2 — clipped in analysis).
- **6 single-track Cherub Rock sessions** (`13-41-55Z` … `17-14-25Z`), each a fresh 30 s `raw_tap.wav` of **Cherub Rock (grid 171.3 bpm, 4/4)** — the track the kickoff flags as the worst live-tracker wanderer. PCM ground truth for the key adversarial track, ×6 takes.
- Net PCM ground truth: **2 distinct tracks** (SZ2 85.9 bpm; Cherub Rock 171.3 bpm ×6). features.csv coverage: **all 8 local tracks.**

## Method / tools (`tools/fbs/`, pure-stdlib, permanent diagnostics)

- **`measure_grid_phase.py`** — PCM path. Full-band **log-compressed spectral-flux** onset function (FFT), high-passed (local-mean subtraction) to remove the sustained/DC component. **Tempo** via autocorrelation of the onset function; **phase** via circular phase-locking (`R` = concentration ∈ [0,1]; `offset` = where in the beat onset energy piles up). Self-validated on a synthetic click-train (clean → R 0.89, offset −5 ms; the HP step is what makes R meaningful — a DC floor otherwise collapses R 0.31→0.02).
- **`grid_phase_csv.py`** — PCM-free companion. Circular lock of the engine's own raw onset novelty (`spectralFlux`, FFT-derived, grid-independent) against the grid's own phase clock (`beatPhase01`). Covers every track.

> Calibration note: on **real** music the circular `R` is modest even when a beat is unambiguous — an autocorr-confirmed Cherub Rock beat sits at R≈0.22–0.26 (lots of off-beat 8th/16th onset content is normal). Thresholds: STRONG ≥ 0.35, moderate ≥ 0.22, weak ≥ 0.14.

## Findings

### Q1a — TEMPO of the cached grid is reliably CORRECT ✅

| Track | grid bpm | measured (PCM autocorr) | error |
|---|---|---|---|
| Cherub Rock (×6 takes) | 171.3 | 169.4 (folded) | **1.1%**, reproducible |
| SZ2 | 85.9 | ~88.5 | ~3% |

The autocorrelation of the real onsets lands on the grid's BPM to ≈1% on the clean 4/4 track, identically across all six Cherub takes. **A steady metronome ticking at the pre-analysed tempo will keep pace with the music's beat through the opening — it will not slowly walk off.** This is the load-bearing positive the whole proposal rests on, and it holds.

### Q1b — PHASE of the cached grid is NOT reliable ❌ (cross-capture-unstable)

Six plays of the *same* track gave six different grid-phase positions:

- Global grid-phase-error per take: **+84, −175, +81, +109, −162, −159 ms** (period = 350 ms, so this scatter spans most of a whole beat). These absolute numbers are low-confidence individually (circular R is low), **but the scatter is corroborated independently**: the live drift tracker's correction starts at 0 and moves in *different directions* on different takes (0→+12→−15; 0→−34→−36; 0→+18→+7; 0→+26→+32), i.e. the cached grid's phase relative to live audio genuinely differs each play.
- features-proxy across all 8 local tracks: onset-vs-grid-phase concentration R = 0.02–0.13 (all "none"), offsets large and scattered (−316…+345 ms). The offset is roughly *stable within a track* (early vs full) but *large* — the grid is internally consistent but mis-positioned.

This matches the documented **BSAudit.2** finding (Beat This! is cross-capture-unstable on 5–6/10 tracks) and **Failed Approach #69** (cold-start beat phase is a retired hard problem). **Conclusion: even local files cannot trust the pre-analysis for phase — only for tempo.** Both sources (streaming + local) therefore use the *same* machine: **first-NOTE anchor for phase + cached grid for tempo** (see Q2). (This simplifies the design vs. the kickoff's "feed local files the grid's beat positions" idea — those positions aren't phase-stable.)

### Supporting — the LIVE tracker WANDERS materially ✅ (confirms "hold steady")

Live drift correction (`drift_ms`) over the opening, from production logs:

- Cherub Rock takes: total span **57–86 ms** within 30 s; one take still moving at 30 s (+66 → … ).
- Mingus "Better Git It": 0 → +50 → **+119 ms** over the track.
- Tras 3: starts at **−111 ms** (a half-beat gross correction at track start).

The live phase slides by most of a beat over the opening. This sliding — the beat marker visibly creeping/searching — is the most likely culprit behind prior "broken sync" reads, and is the direct argument for the proposal's **dead-steady pulse + slow, bar-boundary handoff** rule. Do **not** chase this signal.

### Q2 — Anchor to the FIRST NOTE, not the first strong hit ✅ (Matt's correction, 2026-06-09, verified)

**Correction adopted:** the downbeat is most reliably **the moment the music begins** (first note / silence→sound), *not* the first loud hit. Music starts on the one; silence→signal is the single cleanest event in the take to detect; and unlike a strength threshold, it is not fooled by a quiet/building intro (where the first *strong* hit can land bars late). Cherub Rock is the motivating case — it opens with a quiet (snare-roll/clean-guitar) intro whose start IS beat 1, but whose first *strong* hit is well into the song.

**Verified from PCM:**
- **First note is detected cleanly** — a sharp silence→signal transition at **t ≈ 0.89 s (SZ2), ≈ 1.04 s (Cherub)** with true silence (floor ≈ 0) before it. (The ~1 s is the app/playback startup gap before audio flows; the first audible sample is unambiguous.)
- **A pulse anchored at the first note (at the cached tempo) lands on the beat well:** Cherub onsets fall **+27…+29 ms** off the first-note pulse, **consistent across all three takes** (~28 ms is within perceptual tolerance — < 1/12 beat at 171 bpm — and is likely mostly the detector's own group delay, so the true alignment is tighter). SZ2 (polyrhythmic, genuinely beat-ambiguous) is the hard case at +100 ms.
- **First-note beats the grid's own phase** on every case: first-note offset +27…+100 ms vs grid-phase +60…+239 ms (and the grid scatters across takes; the first-note offset does not).

**Honest caveat:** in *these* recordings the first note and first strong hit nearly coincide (within ~0.4 s) because the tracks happen to start with an immediate onset — so this data does **not** itself show a dramatic "first hit lands seconds late" case. (An earlier inline figure that suggested a +24 s gap on SZ2 was a measurement artifact — the 30 s tap had bled into the next track — and is discarded.) The first-note advantage over first-hit is clearest on a genuine fade-in / quiet-build intro; worth confirming on such a track (the streaming session may supply one). The principle and the better/steadier alignment are confirmed; the worst-case first-hit failure is argued, not yet demonstrated in-hand.

### Bonus — tracks often OPEN WITHOUT THE BEAT (important for the proposal)

The most-tested track (Cherub Rock) opens with a **quiet intro — on the order of 15 s — before the full-band beat establishes** (broadband RMS stays ≤ 0.07 through ~16 s, then jumps to 0.10–0.19; per-second onset energy is sparse until then). For a meaningful slice of the cold-start window there is **no beat in the audio to lock onto at all**. This is fine for the proposal (the steady pulse + live-energy height still drive the spikes), but it means "is the beat aligned in the first few seconds" is *partly a question the music itself doesn't answer early on.*

### Confirmed — the "frozen" diagnosis (code read)

`FerrofluidOcean.metal::fo_spike_strength` = `baseline(cached_bass_proportion, ≤ +0.25) + 0.8·clamp(f.bass,0,1)`. The only reactive term is the smoothed, AGC-levelled bass — held near-constant by design → spikes barely move on bass-light material. `fo_swell_scale` = arousal-only, slow (leave its timescale alone). Stage 1 replaces the `0.8·f.bass` term with the anchored pulse; baseline + swell untouched.

## What this means for the plan

The plan as written is **supported**, with one course-correction:

- **Tempo from the grid: trustworthy — use it.** ✅
- **Phase from the grid: not trustworthy, even on local files → anchor to the FIRST NOTE.** Local and streaming collapse to one path. ⚠️ (course-correction vs the kickoff's local-file optimism)
- **Live phase wanders → hold the pulse dead steady; hand off slowly at a bar line.** ✅ (now quantified)
- **First-NOTE anchor (not first-hit): clean, instant, = the downbeat; lands the pulse within ~30 ms of the beat on the clean track and beats the grid's phase.** ✅ (Matt's correction, verified)

## What I could NOT verify (no overclaiming)

- **No clean streaming session in hand.** All recordings here are local files. Streaming is the harder, real target of the proposal — a fresh streaming session (and ideally a fresh local one) is needed before/along Stage 1.
- **Phase confidence is inherently low.** Automatically pinning beat *phase* from a generic onset signal is unreliable (this is itself the FA #69 lesson). The tempo result is robust; the phase result is "strongly suggestive + corroborated," not "proven on all music."
- **PCM ground truth on only 2 of 8 local tracks.** The other six lean on the engine's own signals (`grid_phase_csv.py`), which corroborate but are weaker evidence.

## Next

**STOP per the staged plan.** Await Matt's read of the plain-English report before Stage 1 (build only the anchored steady pulse, prove it holds steady through the live pipeline). Confirm the `FBS` tag. No code committed yet.

---

# ADDENDUM — Stage 1 live verdict (2026-06-10, session `2026-06-10T03-02-32Z`)

**Matt's read: NEGATIVE on a streaming playlist** ("strong opening with Love Rehab… totally falls apart for So What… same regular beat but not synced [There There]… definitely a regression for [Pyramid Song]… Money perfectly synced… Lotus appears more synced but is not").

**What the pulse columns show (the mechanism worked exactly as built):** every track pulsed at its OWN cached tempo to 0.05 % (118.13 / 135.52 / 126.27 / 69.96 / 123.23 / 128.05), anchored instantly, held dead steady. No tempo lag, no wander, no bug.

**Per-track sync (spectralFlux folded on pulse phase, 10 s windows):**
- **Love Rehab: LOCKED — R 0.43/0.35/0.31, offset stable at ~+200 ms** → Matt's "strong opening." The design working as intended: real track start (audio began with the session) + regular beat + correct tempo.
- **So What (swing jazz): R ≈ 0.01–0.21, offsets random** — no quarter-note pulse to fold; the 135.5 thump reads as a metronome ignoring Miles Davis. Matt's "same beat as Love Rehab": two generic mid-tempo thumps that both ignore the music ARE perceptually the same.
- **There There: R ≈ 0.06–0.10** — tempo essentially right (grid/drums agree 0.4 %) but the anchor = the mid-audio title-change instant → arbitrary phase; regular-but-not-synced.
- **Pyramid Song: R ≈ 0.03–0.09, offsets swinging ±300 ms — THE REGRESSION.** Rubato/irregular song; the prepare-time 3-way tempo disagreement (47.7 % / 57.4 %!) flagged it as irregular and we pulsed anyway, confidently thumping 70 bpm nonsense. Worse than the frozen baseline.
- **Money: Matt perceived "perfectly synced"** (walking bass at ~123 = notes on every beat; the 123.23 pulse coincides) though the flux-fold stays low (7/4 meter + dense flux smear the metric) — perception credit, not metric credit.
- **Lotus Flower: R ≈ 0.01–0.04** — syncopated groove + arbitrary anchor phase; "appears more synced but is not."

**The three structural causes (now measured, not hypothesized):**
1. **Mid-playlist streaming anchors are musically meaningless.** Gapless switches mean every anchor (te ≈ 0.03 on all of tracks 2–6) = the title-change instant, not a musical event. The first-note premise holds only for true starts (track 1 / local files). This was filed as a "known limitation" — the live test shows it is THE dominant case on a playlist, not an edge.
2. **No regularity gate.** Songs without a steady quarter-note beat (swing, rubato, heavy syncopation) get a confident robotic pulse — actively worse than no pulse. The gating signal already exists at prepare time (3-way BPM agreement, bar confidence).
3. **Steady-but-meaningless reads WORSE than nothing.** The Stage-1 bet was "steady wrong-by-a-hair beats wandering right-on-average" — true when the anchor is near-musical (Love Rehab), false when the phase is arbitrary: a regular thump that ignores the music is maximally visible as fake. Stage 3 (one-time bar-boundary handoff to a musical phase source) is load-bearing for tracks 2+, not polish.

**What I now believe:** the steady pulse earns its place only when its phase comes from a musical event AND the song actually has a regular beat; Stage 1 proved the mechanism and falsified the streaming-anchor premise — phase sourcing and regularity gating, not tempo, are the binding constraints.
