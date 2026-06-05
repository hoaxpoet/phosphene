# Skein — implementation plan (for review)

This is the increment breakdown for review. It is **not** the session prompts. Once you approve the shape and sequencing, each increment becomes a self-contained, paste-ready session prompt in the standard structure (read-first file list → numbered audit-before-implementation tasks → explicit Do NOT → done-when with numeric verification commands → commit cadence). **Per D-064, the Skein.1+ session prompts cannot be written until Skein.0 (reference lock) is complete.** Skein.ENGINE.1 is reference-independent and can be prompted the moment you approve.

Companion design doc: `SKEIN_pollock_preset_architecture.md` (becomes the seed for `Sources/Presets/Skein/DESIGN.md`).

---

## Locked decisions (from §8 of the architecture doc)

1. **Subtle structural bias**, not pure allover — sections softly lean the painter's region; repeated choruses revisit and build density. Overall allover-ness preserved.
2. **Wet sheen ships in V1** (Skein.4) — but Skein.4 + Skein.ENGINE.2 are the **explicit cut-line**: if Skein.2 overruns, they defer to V2 and the preset certifies matte-only.
3. **Visible painter locus** — implemented behind an off-by-default flag in Skein.5.
4. **In-flight paint** — deferred to V2 (not in this plan).
5. **Explicit canvas-hold mode** in the mv_warp family (Skein.ENGINE.1), not an overload of the narrower `feedback` path. ⚠️ **AMENDED by the Skein.ENGINE.1 audit (D-142):** canvas-hold needed **no new engine "mode"** — it is reachable as pure per-preset config of the existing mv_warp machinery (identity `mvWarpPerVertex` + `decay=1.0` + `chromaticMix=0`), and (as this decision intended) did NOT overload the `feedback`/Membrane path. Verdict: config-only, no PhospheneEngine source change; every other mv_warp preset byte-identical. See DECISIONS D-142.
6. **Family `painterly`; name Skein.**
7. **8-bit canvas** (RGB is the lossless permanent record); revisit only if soak surfaces banding.

---

## Roadmap at a glance

| ID | Title | Type | Depends on | Gate |
|---|---|---|---|---|
| **Skein.0** | Reference lock | doc | — | `CheckVisualReferences` green; you sign off the trait/anti-ref set |
| **Skein.ENGINE.1** | Canvas-hold accumulation path | engine | — | Regression: all goldens byte-identical; hold-persistence test |
| **Skein.ENGINE.1.1** | Per-preset marks-on-top + cream ground (D-143) | engine | ENGINE.1 | Regression byte-identical (DB/FM + all mv_warp); per-preset marks-on-top test green; Skein renders live |
| **Skein.1** | Canvas + pour spike | preset | ENGINE.1.1 | Eyeball (gate-before-the-gate): does a skein hold + read as paint? |
| **Skein.2** | Splatter morphology + viscosity | preset | Skein.1 | Harness contact sheet: reads as Pollock, not particle-fountain |
| **Skein.3** | Stem palette + full emission routing | preset | Skein.2 | Harness + replay registration; routing is legible |
| **Skein.ENGINE.2** | Wetness channel | engine | — (land before Skein.4) | Regression: byte-identical for others; stamp+decay test |
| **Skein.4** | Wet/dry sheen *(cut-line)* | preset | ENGINE.2, Skein.3 | Harness: wet-now reads vs dry-past |
| **Skein.5** | Mood + structure + anticipation + locus flag | preset | Skein.3 | Harness across mood/section fixtures |
| **Skein.6** | Certification | preset | all | Soak + acceptance + determinism gate + **Matt M7** |

Execution order is top-to-bottom. ENGINE.2 is shown near Skein.4 because that's the increment that needs it; it can be built any time after approval but **must land before Skein.4 opens** (infra-before-preset, never bundled).

---

## Increment detail

### Skein.0 — Reference lock
**doc · depends on: — · gate: `CheckVisualReferences` green + your sign-off**

**Goal.** Complete Gate 0/1 so the downstream session prompts can cite authoritative reference files. This is the coarse-to-fine gate; nothing visual gets prompted before it.

**Scope.**
- Populate `Sources/Presets/Skein/VISUAL_REFERENCES/` with macro / meso / micro / palette images, `NN_<scale>_<descriptor>.(jpg|png)`, ≤500 KB each, regex-clean.
- README distinguishing trustworthy traits from any AI-confabulated ones (`_AIGEN` suffix + D-065(c) "actively disregard" annotations on any target-slot AI images).
- Author the **anti-references**: neon/sci-fi particle burst, clean geometric polka-dots, a literal brush stroke, a muddy fully-saturated canvas, a kaleidoscopic/symmetric layout.
- Finalise the §2 trait matrix against the locked images.

**Out of scope / Do NOT.** No code. No engine work. Do not begin Skein.1 prompting until this is green and signed off.

**Key files.** `Sources/Presets/Skein/VISUAL_REFERENCES/*`, `Sources/Presets/Skein/DESIGN.md` (seeded from the architecture doc).

**Done-when.**
- `swift run --package-path PhospheneTools CheckVisualReferences` green for the Skein folder.
- Trait matrix + anti-references reviewed and approved by you.

---

### Skein.ENGINE.1 — Canvas-hold accumulation path
**engine · depends on: — · gate: full golden-hash regression byte-identical + hold-persistence test**

**Goal.** Establish a persistent, lossless accumulation path: identity warp, no decay, no colour transfer — paint composited normal-alpha on top stays put. This is the no-decay/identity configuration of the Dragon-Bloom brush-on-feedback paradigm (D-138), so it is **not** a new render paradigm and **not** a D-029 concern.

**Scope.**
- **Audit first.** Read `RenderPipeline+MVWarp.swift` (`drawWithMVWarp`, strands-on-top branch), `PresetLoader+WarpPreamble.swift`, `RenderPipeline+SceneGeometry.swift`. Determine whether a pure hold (identity `mvWarpPerVertex` + `decayMul=1` + no R→G→B transfer + strands-on-top) is reachable via JSON params + preset-authored warp functions **alone**. If yes → no engine change, config only. If the existing no-decay path is bound to the colour transfer, add a minimal **gated "hold" transfer mode** (pure pass-through), gated per-preset so every other mv_warp preset is byte-identical.
- DECISIONS.md entry ratifying canvas-hold as the no-decay/identity config of the brush-on-feedback paradigm (the one-line D-### note).

**Out of scope / Do NOT.** No wetness yet. No mark shapes yet (a trivial test stamp is fine for the persistence test). Do NOT touch any code path that other mv_warp presets share without a gate — a format/transfer mismatch stalls the GPU at preset transition (the D-137 beachball pitfall).

**Key files.** `RenderPipeline+MVWarp.swift`, `PresetLoader+WarpPreamble.swift`, `RenderPipeline.swift`/`+PresetSwitching.swift`, `DECISIONS.md`, a new `SkeinCanvasHoldTest.swift`.

**Done-when.**
- All existing golden-hash regression entries pass **unchanged** (other presets byte-identical).
- MVWarp/StagedComposition suites green; app build green.
- Hold-persistence test: a stamped mark, with identity hold under silence, is **pixel-unchanged frame-over-frame** (Hamming 0 at the mark location across ≥120 frames) — i.e. true lossless persistence, no decay, no drift.

---

### Skein.1 — Canvas + pour spike
**preset · depends on: ENGINE.1.1 · gate: eyeball (gate-before-the-gate)**

**Goal.** A single white pour line traced by a wandering painter, accumulating on a cream canvas. No audio routing yet. If a persistent skein does not hold and read as *paint*, the concept stops here.

> **Moved to Skein.ENGINE.1.1 (D-143):** the marks-on-top wiring (the per-preset `<prefix>_geometry_*` overlay path, draw-params/chromatic/comp via the `marks` block) and the **base cream-canvas fill on apply/reset** (per-preset `canvas_clear`) are already done and gated byte-identical. Skein already **renders live** (cream ground + a held test disc through the overlay). Skein.1 is now pure preset work: replace the static test disc with the wandering painter's swept-capsule pour.

**Scope.**
- `SkeinState.swift` (painter trajectory: position, velocity, base-path phase via curl-noise / incommensurate sinusoids; per-frame tick) — the established `*State.swift` pattern.
- Establish a **seed hook** on the painter (fixed seed acceptable for the spike; audit whether the track SHA-256 from `PersistentStemCache` is reachable by preset state on apply — full wiring deferred to Skein.3).
- Replace the ENGINE.1.1 static test disc in `skein_geometry_*` with the **swept capsule** from `painter_prev → painter_now` (the moving locus accumulates a continuous looping line on the held canvas via the already-wired overlay). Marks drawn once as the painter moves keep their AA (unlike the static test disc, which is hard-edged for idempotent redraw).
- Coverage diagnostic (% painted) + painter-trajectory debug overlay.
- `Skein.json`: `passes: ["direct", "mv_warp"]`, family `painterly`, `certified: false`, canvas-hold + `marks` block from ENGINE.1 / ENGINE.1.1 (D-143).

**Out of scope / Do NOT.** No splatter, no filaments, no viscosity, no stems, no colour beyond white, no wetness, no mood/structure. Do NOT add audio routing.

**Key files.** `Sources/Presets/Skein/SkeinState.swift`, `Shaders/Skein.metal`, `Skein.json`, `VisualizerEngine+Presets.swift` (wiring), `SkeinCanvasHoldTest.swift` (extend).

**Done-when.**
- `RENDER_VISUAL=1` contact sheet across ≥4 fixtures shows a continuous, accumulating, looping pour line.
- Coverage meter increases monotonically; silence fixture non-black.
- **Eyeball gate:** the line holds, layers, and reads as poured paint on a surface.

---

### Skein.2 — Splatter morphology + viscosity
**preset · depends on: Skein.1 · gate: harness contact sheet (highest aesthetic risk)**

**Goal.** Add the splatter vocabulary and make a still frame read as Pollock — central mark + velocity-biased satellite droplets + thin filaments, with viscosity shaping. This is where the iteration lives (cf. Dragon Bloom "not seeing petals", Arachne clipart).

**Scope.**
- Splatter burst: N droplet discs (cap N ≈ 64) at velocity-biased radial offsets, density falling off with distance; thin filament caps along the velocity direction.
- **Scissor the mark pass to this frame's bounding box** (cost ∝ new marks, not total marks).
- Viscosity parameter (driven by a debug scalar for now, real routing in Skein.3) shaping: line width, satellite count/spread, mark alpha (translucent thin ↔ opaque thick), edge raggedness.
- SHADER_CRAFT.md entry for the swept-capsule + splatter-morphology technique.

**Out of scope / Do NOT.** No stem/audio routing yet (drive bursts and viscosity from debug scalars). No wetness. No mood. Do NOT let droplets read as clean circles or sci-fi sparks — ragged edges and matte are the whole game; check against the Skein.0 anti-references each iteration.

**Key files.** `Shaders/Skein.metal`, `SkeinState.swift` (burst bookkeeping), `SHADER_CRAFT.md`.

**Done-when.**
- Contact sheet: bursts produce a believable central-mark + satellite-halo + filament structure.
- A still frame reads as **poured paint, not a particle field**, and does not match any Skein.0 anti-reference (manual check).
- Per-frame new-mark count exposed (governor input).

---

### Skein.3 — Stem palette + full emission routing
**preset · depends on: Skein.2 · gate: harness + PresetSessionReplay registration**

**Goal.** Wire the §5.4 routing so the painting becomes legibly musical: stem→colour, energy-deviation→pour, onset→splatter, centroid→viscosity.

**Scope.**
- Stem→paint palette (drums→near-black, bass→deep teal, vocals→cream/ochre, harmonic→sienna; base cream).
- Routing (all deviation-normalised per **D-026**; **one primitive per visual layer**):
  - pour flow per stem ← that stem's energy deviation (`xRel`/`xAttRel`) — **primary**.
  - painter speed ← broadband energy deviation; local jitter ← high-band / onset rate.
  - splatter intensity per stem ← that stem's onset pulse — **accent**.
  - viscosity ← that stem's spectral **centroid**; flick sharpness ← **attackRatio**.
- **Stem warmup blend** (`smoothstep(0.02,0.06,totalStemEnergy)`, **D-019**) on everything reading `stems.*`.
- Wire the painter seed to track identity (the SHA hook from Skein.1).
- Register Skein in **PresetSessionReplay** (routes) — deferred until now because the routing must exist to verify, matching the Dragon Bloom Spike-2/3 pattern.

**Out of scope / Do NOT.** No mood, no structural bias, no anticipation, no wetness, no painter locus (all Skein.4/5). Do NOT use absolute-threshold audio patterns (anti-pattern); do NOT write valence/arousal anywhere yet.

**Key files.** `Shaders/Skein.metal`, `SkeinState.swift`, `Skein.json` (routing block), `PresetSessionReplay` registration, `PresetAcceptanceTests.swift`.

**Done-when.**
- Replay + acceptance: a beat-heavy fixture produces measurably more splatter than a steady fixture; stems produce distinct colours in the canvas.
- Contact sheet on real-ish fixtures: drum hits → black flicks, bass → teal pools, vocals → cream lines are visually distinguishable.
- Stem-warmup verified (no first-10 s colour pop).

---

### Skein.ENGINE.2 — Wetness channel
**engine · depends on: — (must land before Skein.4) · gate: regression byte-identical + stamp/decay test**

**Goal.** A transient per-pixel wetness signal: stamped to 1 where paint lands this frame, decaying toward 0 each frame (decay pauses at silence via `accumulated_audio_time`), readable by the display/blit stage.

**Scope.**
- **Audit first.** Decide wetness storage: **canvas alpha channel** (RGB stays the lossless permanent record; A carries decaying wetness — fewer bindings; the hold path must decay A while holding RGB) **vs** a dedicated single-channel ping-pong (cleaner separation, one extra texture). Default toward the alpha-channel approach if the hold path can decay A cleanly; otherwise the dedicated buffer.
- Stamp + per-frame decay plumbing; pause decay at silence.
- Let the mv_warp blit (`mvWarp_blit_fragment`) **sample** wetness — gated, **no-op for every other preset**.

**Out of scope / Do NOT.** No specular/lighting look here (that's Skein.4 authoring) — just the signal + the ability to read it. Same GPU-stall caution as ENGINE.1: gate everything; no shared format changes without a gate.

**Key files.** `RenderPipeline+MVWarp.swift` (blit sampling), `PresetLoader.swift` (format/binding), `RenderPipeline+FeedbackDraw.swift` (if dedicated buffer), a new `SkeinWetnessTest.swift`.

**Done-when.**
- All goldens byte-identical; other mv_warp presets unaffected.
- Stamp/decay test: wetness at a freshly-stamped texel = 1, decays monotonically toward 0 over the expected frame count, and **holds (no decay) under silence**.

---

### Skein.4 — Wet/dry sheen *(cut-line)*
**preset · depends on: ENGINE.2, Skein.3 · gate: harness (wet-now vs dry-past)**

**Goal.** The legibility device: fresh paint glistens, old paint is matte, so the eye tracks the musical *now*.

**Scope.**
- Display/lighting authoring reading canvas + wetness: GGX specular highlight (single overhead light) scaled by wetness; matte + slight desaturation where dry.
- Optional subtle canvas-weave grain beneath the paint.
- Optional bloom on wet specular sparkle (governor-gated, drops at `.noBloom`).

**Out of scope / Do NOT.** No new audio routing (wetness comes from where paint lands, already known). Do NOT make dry paint glossy or wet paint matte (that inverts the read).

**Key files.** `Shaders/Skein.metal` (display/comp authoring), `Skein.json` (specular/bloom params).

**Done-when.**
- Contact sheet: recently-painted regions visibly catch light; older regions are matte. The live edge of the music is visible.

**Cut-line note.** If Skein.2 overruns, defer ENGINE.2 + Skein.4 to V2; Skein certifies matte-only without them.

---

### Skein.5 — Mood + structure + anticipation + painter-locus flag
**preset · depends on: Skein.3 (Skein.4 optional) · gate: harness across mood/section fixtures**

**Goal.** The slow global modulators + the gesture quality that makes the painter read as a performer + the agreed subtle structural bias.

**Scope.**
- **Mood:** valence → palette warmth/saturation; arousal → vigour/density. Smooth valence/arousal **in state** (never via `setFeatures` — FA #25).
- **Structure (subtle bias):** on `StructuralPrediction` boundaries, shift palette emphasis + pour density, and softly lean the painter's region so repeated sections revisit and build density — preserving overall allover-ness.
- **Anticipation:** painter wind-up/coil on the rising edge of `beatPhase01`, release into a flick — motion driven by **beat phase, not raw onset** (FA #33). (Splatter emission itself stays onset-driven; that's the accent.)
- **Painter locus (flagged, off by default):** a faint luminous pour-point hovering above the canvas, trackable by eye.

**Out of scope / Do NOT.** No in-flight paint (V2). Do NOT make the structural bias hard zoning — it must stay subtle (allover read intact). Locus stays behind the flag.

**Key files.** `SkeinState.swift` (mood smoothing, structural region bias, anticipation curve, locus), `Shaders/Skein.metal` (palette + locus), `Skein.json`.

**Done-when.**
- Contact sheet across high/low-valence and high/low-arousal fixtures shows the palette/density shifts.
- Section-boundary fixture shows the gentle density/region response without breaking allover-ness.
- Anticipation reads as intentional wind-up-then-flick on a beat-heavy fixture.

---

### Skein.6 — Certification
**preset · depends on: all · gate: soak + acceptance + determinism + Matt M7**

**Goal.** Certify Skein and flip `certified: true`.

**Scope.**
- **Soak:** multi-hour `SoakTestHarness` run — confirm the 8-bit canvas under identity-hold shows no banding/drift over a long session (the §5.5 verify-don't-assume check). 16-bit fallback only if this fails.
- **Acceptance invariants** (`PresetAcceptanceTests`): silence-non-black (trivial here); beat-ratio (splatter density beat-heavy > steady); **coverage bound** (typical track ends 60–80 %, never full, never near-empty on a dense track).
- **Determinism gate (headline property):** same track + same seed → dHash-stable final canvas across two runs, within tolerance. Wire the painter seed fully to the track SHA-256.
- Golden dHash regression entry for Skein.
- **Anti-reference check:** manual (the automated anti-reference dHash gate is itself a Missing engine capability — same gap Arachne has — so this stays an M7 judgement).
- ENGINEERING_PLAN.md rows marked landed; FidelityRubric profile set.
- **Matt M7:** live, on real music, ≥5 tracks + a local file — Pollock-must-read / painter-must-perform. Non-negotiable, non-bypassable.

**Out of scope / Do NOT.** No new features at cert. Do NOT flip `certified: true` before M7 passes.

**Key files.** `PresetAcceptanceTests.swift`, `PresetRegressionTests.swift` (golden), `SoakTestHarness` config, `Skein.json` (`certified`, `rubric_profile`), `ENGINEERING_PLAN.md`, `FidelityRubric` wiring.

**Done-when.**
- Soak clean; acceptance green; determinism gate green; golden registered.
- M7 verdict: pass.

---

## Sequencing, cut-lines, and risk

- **Critical path:** Skein.0 → ENGINE.1 → Skein.1 → Skein.2 → Skein.3 → Skein.5 → Skein.6. Wet-sheen (ENGINE.2 + Skein.4) is a parallel branch off Skein.3 and the explicit **cut-line** — defer to V2 under schedule pressure; matte-only still certifies.
- **The risk is concentrated in Skein.2** (splatter morphology = paint vs particle-fountain). Everything before it is low-risk plumbing; everything after is routing on top of a working look. Budget iteration there.
- **Two GPU-stall traps** (ENGINE.1, ENGINE.2): any shared mv_warp format/transfer change must be gated, or the preset-transition beachball (D-137 pitfall) bites. Both engine increments are golden-regression-locked for exactly this reason.
- **8-bit assumption** is verified at Skein.6 soak, not assumed earlier — but it's load-bearing for the whole "lossless identity hold" story, so if it ever fails the fix (16-bit canvas) is a trivial format swap, not a redesign.

## Documentation write-backs (house culture)

- **DECISIONS.md** — canvas-hold paradigm ratification (ENGINE.1); any routing/structural-bias decisions worth a D-### (Skein.3/5).
- **ENGINEERING_PLAN.md** — increment rows per increment as they land.
- **SHADER_CRAFT.md** — swept-capsule + splatter morphology (Skein.2); wet-sheen (Skein.4).
- **`Sources/Presets/Skein/DESIGN.md`** — seeded from the architecture doc at Skein.0, kept current.
- **RENDER_CAPABILITY_REGISTRY.md** — flip canvas-hold + wetness to Supported once they ship.

---

## To proceed

If the breakdown and sequencing look right, I'll write the first paste-ready session prompts in your standard structure. **Skein.0** (reference lock) and **Skein.ENGINE.1** (canvas-hold, reference-independent) can both go to Claude Code immediately on approval; Skein.1+ prompts follow once Skein.0 is green. Tell me whether to start with ENGINE.1, Skein.0, or both.
