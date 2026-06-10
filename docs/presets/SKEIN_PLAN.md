# Skein — implementation plan (for review)

This is the increment breakdown for review. It is **not** the session prompts. Once you approve the shape and sequencing, each increment becomes a self-contained, paste-ready session prompt in the standard structure (read-first file list → numbered audit-before-implementation tasks → explicit Do NOT → done-when with numeric verification commands → commit cadence). **Per D-064, the Skein.1+ session prompts cannot be written until Skein.0 (reference lock) is complete.** Skein.ENGINE.1 is reference-independent and can be prompted the moment you approve.

Companion design doc: `SKEIN_pollock_preset_architecture.md` (becomes the seed for `Sources/Presets/Skein/DESIGN.md`).

---

## Locked decisions (from §8 of the architecture doc)

1. **Subtle structural bias**, not pure allover — sections softly lean the painter's region; repeated choruses revisit and build density. Overall allover-ness preserved.
2. **Wet sheen ships in V1** (Skein.4) — but Skein.4 + Skein.ENGINE.2 are the **explicit cut-line**: if Skein.2 overruns, they defer to V2 and the preset certifies matte-only. ✅ **Cut-line NOT invoked (2026-06-08, D-149):** the ENGINE.2 audit found a gated additive signal (canvas-alpha wetness + Skein-owned warp/comp fragments) — no shared format change, no new pass — so both landed in V1. Skein certifies *with* the sheen.
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
| **Skein.1** | Canvas + pour spike | preset | ENGINE.1.1 | ✅ **landed 2026-06-05** (`57ee7383`/`528021b5`); **pending Matt's eyeball gate**: does a skein hold + read as paint? |
| **Skein.2** | Splatter morphology + viscosity | preset | Skein.1 | ✅ **landed + Matt eyeball PASS 2026-06-05** (closed-form / path A, no engine touch; round-droplet M7 fix `409c1b70`) — reads as poured paint, not a particle-fountain. Cert at Skein.6. |
| **Skein.3** | Stem palette + full emission routing | preset | Skein.2 | Harness + replay registration; routing is legible |
| **Skein.ENGINE.2** | Wetness channel | engine | — (land before Skein.4) | ✅ **landed 2026-06-08** (D-149, approach A) — DB/FM byte-identical, RGB lossless-hold intact, stamp/decay/holds-at-silence green |
| **Skein.4** | Wet/dry sheen *(cut-line — NOT invoked)* | preset | ENGINE.2, Skein.3 | ✅ **M7 PASS 2026-06-09** (4 rounds — "rings are gone and the drying looks good"): union-SDF line, darker-saturated-glossy wet, wetness-blur killed the displaced rings |
| **Skein.4.1** | Colour-per-stroke | preset | Skein.4 | ✅ **M7 PASS 2026-06-09** (D-150, 2 rounds) — colour-breakpoint ring freezes the line per-segment + displaced NEW pour on a switch (option 2); round-2 added a min-dwell + hysteresis so pours are long continuous drips (63→10 pours); coverage byte-identical |
| **Skein.ENGINE.3** | Structural-section signal → preset tick | engine | Skein.4.1 | ✅ **landed 2026-06-09 (D-151)** — gated `RenderPipeline.setStructuralPrediction` (separate lock, default `.none`; mirrors `setMood`) delivers live `StructuralPrediction` to `SkeinState.tick(…structure:)` from the per-frame MIR publish; CPU-only, byte-identical (all presets + Skein), no GPU-contract change; `SkeinStructureSignalTests` proves the live path (FA #66); signal STORED for Skein.5, visually identical to today |
| **Skein.5** | Mood + structure + anticipation + locus flag | preset | Skein.3, **ENGINE.3** (for structure) | ✅ **landed 2026-06-09 (D-152; pending Matt M7)** — BUG-035 fixed first (the structure signal's ring-wrap dedup); mood frozen at lay-time (the canvas archives the arc); structure biased through pour offsets, conf-gated to exactly zero; anticipation = τ-warping (cannot smear by construction); locus display-only at comp, flagged OFF |
| **Skein.5.3b** | Per-palette grounds + anchored re-curation | preset | Skein.5.3 | ✅ **landed 2026-06-10 (D-155 amendment)** — final library fathom/poles/nocturne/ember (1 light + 3 dark grounds, all work-anchored); ground travels with the palette end-to-end |
| **Skein.5.3** | Curated palette library + per-track picker | preset | Skein.5 | ✅ **landed 2026-06-10 (D-155)** — 5 Matt-curated palettes (fathom/nocturne/jewel/inkpop/electric), fixed role grammar, deterministic per-track picker (seed % count, §5.7 extends to colour); separability-under-mood-tint gates |
| **Skein.5.4** | Two painting techniques: pour drips vs independent flicks | preset | Skein.5.3b | ✅ **landed + Matt eyeball-gate PASSED 2026-06-10 (3 live sessions: look "I like it" / round-2 speed tune "the speed adjustments look good" / BUG-044 wipe verify "Looks good"); merged to local main `befb406b`** — the pour sheds drips beside the line ∝ pour volume (`lineFlow`, τ-clocked); flicks land anywhere ≥ 0.20 UV from the painter with their own throw angle (lobed blot + 1–3 flung threads w/ terminal droplets + power-law teardrop satellites; magnitude = soft-saturated dev excess in `burst.size`); emission timing UNCHANGED, no GPU-struct change (`sharpness < 0` = drip marker); round-2: spatter rate −41 %, pour starts +13 % |
| **Skein.6** | Certification | preset | all | 🔶 **gates landed 2026-06-10 (D-159) — AWAITING MATT'S M7** (≥5 streaming tracks + a local file, from the main build). Landed: track-length coverage bound (Matt's decision: approved density stands, §5.7 60–80 % band retired for never-solid/never-near-empty), §5.7 determinism dHash (two-run byte-identity + hamming ≤ 8; full-track evidence 2×10,800f diff 0), golden dHash entry, §5.5 two-hour canvas soak (`SKEIN_SOAK=1`, via the live mv_warp path — `SoakTestHarness` can't see the canvas), `family: painterly` + `PresetCategory` case (D-142(c)), `rubric_profile: lightweight` ratified (D-064 precedent). Seed stays FNV-1a `title\|artist` (SHA-256 wording amended). `certified: true` flips ONLY on the M7 verdict |

Execution order is top-to-bottom. ENGINE.2 is shown near Skein.4 because that's the increment that needs it; it can be built any time after approval but **must land before Skein.4 opens** (infra-before-preset, never bundled). **ENGINE.3 likewise must land before Skein.5's structure sub-feature** — Matt chose the deliberate engine increment (option (a)) over an in-state proxy for real section-awareness.

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

**Scope (as planned).**
- ~~`SkeinState.swift` (painter trajectory: position, velocity, base-path phase via curl-noise / incommensurate sinusoids; per-frame tick) — the established `*State.swift` pattern.~~ → **deferred to ENGINE.1.2** (see Landed note).
- ~~Establish a **seed hook** on the painter (fixed seed for the spike; track SHA-256 from `PersistentStemCache`).~~ → fixed seed is the in-shader constants; per-track seeding deferred to Skein.3.
- Replace the ENGINE.1.1 static test disc in `skein_geometry_*` with the **swept capsule** from `painter_prev → painter_now` (the moving locus accumulates a continuous looping line on the held canvas via the already-wired overlay). Marks drawn once as the painter moves keep their AA (unlike the static test disc, which is hard-edged for idempotent redraw).
- Coverage diagnostic (% painted) + the env-gated contact sheet.
- `Skein.json`: `passes: ["direct", "mv_warp"]`, `certified: false`, canvas-hold + `marks` block from ENGINE.1 / ENGINE.1.1 (D-143). (`family: painterly` deferred — see Landed note.)

**Landed (path A, 2026-06-05 — `57ee7383` / `528021b5`).** The session audit took **Path A (closed-form, in-shader)** over Path B (`SkeinState` + a per-preset overlay buffer): the marks-on-top overlay binds `features` only at the **vertex** stage (`drawSceneGeometryOverlay:36-37`, no fragment binding), so the painter position is computed in `skein_geometry_vertex` (which already reads `features@0` — the same slot `dragon_bloom_strand_vertex` reads) and passed to the fragment as varyings. **Zero engine touch, no CPU state, no per-preset buffer; DB/FM byte-identical by construction.** `SkeinState` + the gated `drawSceneGeometryOverlay` buffer-binding (Path B) are **deferred to a future ENGINE.1.2**, opened when Skein.2's stateful painter (droplet positions, per-stem integrators) genuinely needs them (FA #59/#60 — don't build infra before its consumer exists; SKEIN_DESIGN §7 "infra patches land in their own .x increment"). The trajectory is three gesture scales per axis at non-harmonic frequencies (slow drift + gesture loops + tight loops, all gesture-band); the loops are the GESTURE not a coiling/noise term (§1.0 fact 1); width rides 1/speed (pools at turning points, filament on sweeps — §1.0/§1.2). The pour's leading END **trails off** (a closed-form tapering tail over the painter's last ~0.67 s — Matt's eyeball-pass refinement, `8b8d167d`; a *fully*-persistent trail-off is the wet-now/dry-past device §1.4 → the deferred wetness channel ENGINE.2). `family: painterly` + the `PresetCategory` case stay **deferred** per D-142(c)/D-143 — adding the enum case is an engine touch outside Skein.1's pure-preset scope; it lands with the rubric/family decision (Skein.3 or .6). No `SkeinState.swift` / `VisualizerEngine+Presets.swift` change this increment.

**Out of scope / Do NOT.** No splatter, no filaments, no viscosity, no stems, no colour beyond white, no wetness, no mood/structure. Do NOT add audio routing.

**Key files (as landed).** `Shaders/Skein.metal` (the pour line replaces the disc), `SkeinCanvasHoldTest.swift` (the disc hold test → the accumulation + hold + continuity gate + env-gated contact sheet). `Skein.json` unchanged.

**Done-when.** ✅ (pending Matt's eyeball gate)
- ✅ `RENDER_VISUAL=1`/`SKEIN_VISUAL=1` contact sheet (live marks-on-top path, 480×270) at ~2/5/10/20 s shows a continuous, accumulating, looping pour line (coverage 0.4 → 1.4 → 2.7 → 5.9 %).
- ✅ Coverage grows monotonically; far-corner held byte-identical; continuity = 1.000 (single connected component). Silence-non-black trivial (cream ground). All through the **live** scene→warp→overlay→blit→swap path advancing `features.time`.
- ⏳ **Eyeball gate:** Matt confirms the line holds, layers, and reads as poured paint.

---

### Skein.2 — Splatter morphology + viscosity ✅ (2026-06-05) — pending Matt's M7
**preset · depends on: Skein.1 · gate: harness contact sheet (highest aesthetic risk)**

**Landed (path A — closed-form, in-shader, no engine touch).** The Skein.1 audit's Path A extended cleanly: droplet bursts + filaments + viscosity are a deterministic hash of (flick, droplet) generated in `skein_geometry_fragment`, with a closed-form debug viscosity sweep of `features.time` computed in `skein_geometry_vertex` and passed as a varying — **no `SkeinState`, no per-preset overlay buffer, no engine touch** (DB/FM byte-identical by construction; verified `drawSceneGeometryOverlay:36-37` binds `features` at the vertex only). The ENGINE.1.2 buffer + CPU state stay **deferred to Skein.3** (their real consumer — per-stem flow integrators + onset emission + the per-track SHA seed; FA #59/#60). Two iteration findings: big+dense droplets read as merged "froth" → small+crisp+wider-flung DISTINCT dots; straight line→droplet filaments radiate as a sci-fi **starburst** (the particle-burst anti-reference) → forward-gated/short/sparse spray-streaks. Viscosity → line-width factor floors at 1.0 (widen-only) so the Skein.1 continuity invariant is preserved. See `ENGINEERING_PLAN.md` Skein.2 + `SHADER_CRAFT.md §18`.

**Goal.** Add the splatter vocabulary and make a still frame read as Pollock — central mark + velocity-biased satellite droplets + thin filaments, with viscosity shaping. This is where the iteration lives (cf. Dragon Bloom "not seeing petals", Arachne clipart).

**Scope.**
- Splatter burst: N droplet discs (cap N ≈ 64) at velocity-biased radial offsets, density falling off with distance; thin filament caps along the velocity direction.
- **Scissor the mark pass to this frame's bounding box** (cost ∝ new marks, not total marks).
- Viscosity parameter (driven by a debug scalar for now, real routing in Skein.3) shaping: line width, satellite count/spread, mark alpha (translucent thin ↔ opaque thick), edge raggedness.
- SHADER_CRAFT.md entry for the swept-capsule + splatter-morphology technique.

**Out of scope / Do NOT.** No stem/audio routing yet (drive bursts and viscosity from debug scalars). No wetness. No mood. Do NOT let droplets read as clean circles or sci-fi sparks — ragged edges and matte are the whole game; check against the Skein.0 anti-references each iteration.

**Key files (as landed).** `Shaders/Skein.metal` (`skein_fbm2` + `skeinDebugViscosity` + splatter/filament/viscosity in `skein_geometry_fragment`), `SkeinCanvasHoldTest.swift` (corridor-isolated line continuity + the splatter halo/viscosity/bake-hold/new-mark test + a viscosity-sweep contact sheet), `SHADER_CRAFT.md §18`, `ENGINEERING_PLAN.md`. **No `SkeinState.swift`** (path A — deferred to Skein.3 / ENGINE.1.2). `Skein.json` unchanged.

**Done-when.** ✅ (Matt eyeball PASS 2026-06-05; cert at Skein.6)
- ✅ Contact sheet: bursts produce a central-mark + satellite-halo + filament structure (halo dense-near/sparse-far; the viscosity-sweep sheet shows both poles).
- ✅ **M7 gate (round 2):** Matt "looks good" — a still frame reads as **poured paint, not a particle field**, and matches no Skein.0 anti-reference (all 5 checked clear). Round-droplet fix `409c1b70` resolved the M7-round-1 rounded-square readout.
- ✅ Per-frame new-mark count exposed (governor input — 178/179 frames in the bake/hold test).

---

### Skein.3 — Stem palette + full emission routing ✅ (2026-06-05) — Matt M7 PASS 2026-06-06
**preset (+ ENGINE.1.2) · depends on: Skein.2 · gate: harness + PresetSessionReplay registration + Matt's palette sign-off + M7**

**Landed (ENGINE.1.2 = Option B, the lightest gated form).** The Skein.1/2 audit deferred `SkeinState` + the overlay buffer to "when the stateful painter genuinely needs them" — that is here. **The audit found Option A (pure config via slot 6) UNAVAILABLE:** the marks-on-top `strandsOnTop` path (`encodeMVWarpScenePass`) never bound fragment slot 6 — only the non-strands `renderSceneToTexture` did — so the overlay fragment could not see `directPresetFragmentBuffer`. Landed the lightest **Option B**: a gated slot-6 fragment-buffer binding in the `strandsOnTop` branch (Dragon Bloom sets no buffer → nil → byte-identical; Fata Morgana uses its own draw branch → byte-identical). `SkeinState.swift` (new) packs `SkeinHeaderGPU` (64 B) + 48 × `SkeinBurstGPU` (48 B): the audio-modulated painter clock, per-track seed phases, dominant-stem line colour, and the onset-burst ring. `skein_geometry_fragment` consumes it at `buffer(6)`. **Palette: Full Fathom Five (charcoal/oxblood/ochre/teal), Matt-approved 2026-06-05.** Key finding: only `drums_beat` is a real pulse — the other `*_beat` are reserved-zero, so per-stem onsets derive from `*_energy_dev` rising-activity in `SkeinState` (the history the closed-form fragment cannot see). sRGB (FA #71): the `.bgra8Unorm_srgb` canvas sRGB-encodes on store, so `SkeinState` sRGB-DECODES the display palette to linear before packing — without it, dark stems lifted to washed mid-tones and painted nothing. Commits: `f0fef708` (ENGINE.1.2), `7098eff7` (colour+routing), `8ddcb438` (seed+reset).

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

**Key files (as landed).** `Shaders/Skein.metal` (consume `SkeinUniforms@6`; debug drivers retired), `Presets/Skein/SkeinState.swift` (new — painter integrators + onset-burst ring + per-track seed + sRGB-decoded palette), `RenderPipeline+MVWarpScene.swift` (gated slot-6 bind), `RenderPipeline+MVWarp.swift` (`clearMVWarpCanvasToGround`), `VisualizerEngine+Presets.swift` / `+Capture.swift` / `+Stems.swift` (wire + reseed-on-track-change), `SkeinCanvasHoldTest.swift` (real-stem colour/route gate + seed determinism), `PresetSessionReplay/SkeinRoutes.swift` (new — route registration). `Skein.json` unchanged (routing is in `SkeinState`/shader, not a JSON block — supersedes the planned routing-block scope).

**Done-when.** ✅ (pending Matt's M7)
- ✅ Real-stem colour/route gate (live scene→warp→overlay→blit→swap, replayed real stems): ≥3 separable colour clusters (got 4 — all stems), opaque-not-mud (0.075), onset→splatter (busy 129 vs steady 0 bursts), D-019 warmup (0 bursts at silence), bake+hold, round droplets.
- ✅ Per-track seed determinism (§5.7): same seed → byte-identical painting (pixel-diff 0); different seed → different (3947); reseed clears the painter (bursts 160→0, clock→0).
- ✅ Palette contact sheet (live path, 3 candidates) → **Matt signed off on Full Fathom Five 2026-06-05**.
- ✅ `PresetSessionReplay --preset skein` registered (per-stem `*_energy_dev` onset routes + the broadband painter-speed route; viscosity←centroid / sharpness←attackRatio are not SR.1-measurable — `SessionFrame` records no centroid/attackRatio).
- ✅ **M7 gate PASS (2026-06-06):** Matt "Looks great!" live on local-file session `2026-06-06T14-59-12Z` (Skein active, no errors, 4318 frames, all four stems heavily active → every colour painted) — a listener can read the arrangement. Cert (full M7 ≥5 tracks + soak + dHash) is Skein.6.

---

### Skein.ENGINE.2 — Wetness channel ✅ (2026-06-08, D-149)
**engine · depends on: — (must land before Skein.4) · gate: regression byte-identical + stamp/decay test**

**Landed (approach A — canvas ALPHA channel; the plan's default-if-clean, taken).** The audit (D-149) found approach A clean *and* the per-prefix override mechanism (`PresetLoader.swift:689`/`:691`, used by Fata Morgana) lets Skein own its warp + comp fragments with **no shared GPU code touched**. Wetness lives in the feedback texture's ALPHA channel (linear 8-bit on the `.bgra8Unorm_srgb` feedback; RGB stays the lossless permanent record). **Stamp:** the overlay's existing alpha-over blend (`A = bestCover² + dst.a·(1−cover)` → fresh solid paint → A≈1; no new stamp code). **Decay:** `skein_warp_fragment` holds RGB byte-identically and does `A *= wetnessDecay`; `wetnessDecay = exp(-rate·dt·stemMix)` from `SkeinState` **pauses at silence** (stemMix→0 → 1.0). **Read-hook:** the blit already samples the compose texture — Skein.4's `skein_comp_fragment` reads `.a`. Plumbing: a gated `mvWarpWetnessDecay` uniform (mirror of `mvWarpChromatic`) at warp-fragment `buffer(1)`, default 1.0 — only `skein_warp_fragment` declares it, FM never runs the standard warp pass → **DB/FM/Starburst byte-identical by construction**. **Cut-line check: PASS, NOT invoked** (no shared format change, no new pass, no loop reshape). Approach B (dedicated R8) rejected — it forces MRT on the shared overlay pass or a mark re-dispatch, more code/risk for the same separation. Files: `RenderPipeline.swift`/`+PresetSwitching.swift`/`+MVWarp.swift` (the uniform), `Skein.metal` (`skein_warp_fragment`), `SkeinState.swift` (`wetnessDecay`), `VisualizerEngine+Presets.swift` (per-frame push), `SkeinCanvasHoldTest.swift` (`SkeinWetnessTest` + RGB-only hold re-scope). Commits `255fcc64` / `c5192d28`.

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

### Skein.4 — Wet/dry sheen *(cut-line — NOT invoked)* ✅ (2026-06-08) — pending Matt's M7
**preset · depends on: ENGINE.2, Skein.3 · gate: harness (wet-now vs dry-past)**

**Landed.** `skein_comp_fragment` (the `<prefix>_comp_fragment` override — shared blit byte-identical) reads canvas RGB + wetness A and renders the wet-now / dry-past device: **wet → GGX specular** (normal from the canvas luminance gradient — central-difference/Sobel; tonemapped GGX NDF, Walter et al. 2007), hard-gated by wetness so it fires on recent paint and ~0 on the dried past; **dry → matte + slight desaturation**; subtle canvas-weave grain. The sheen is an **additive glint + a subtle wet saturation "deepen"** (glossy depth, not whitening) so the Skein.3 stem colours **read through** (verified — all 4 stems preserved on the blit). sRGB (FA #71): the feedback is sRGB → sampling auto-decodes to linear; no manual decode. Bloom-on-wet-specular deferred (needs a pass / governor state — the in-shader glint gives the sparkle, cut-line-conscious). Gate (live BLIT path, real replayed stems): wet (A>180) sheen boost **25.77** vs dry (A<80) **3.71** (≈7×), glint **162**, stem colours **CANVAS [1906,7205,5601,10328] → BLIT all 4 intact**. Files: `Skein.metal` (`skein_comp_fragment` + sheen tuning), `SkeinCanvasHoldTest.swift` (wet-now/dry-past gate + BLIT capture + contact sheet + canvas-vs-blit isolation). Commits `ba62e1ef` / `23060d11`. **Pending Matt's M7** (the eye-tracks-the-now perceptual gate, live).

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

### Skein.4.1 — Colour-per-stroke ✅ M7 PASS (2026-06-09, 2 rounds)
**preset (+ small SkeinState/SkeinUniforms extension) · depends on: Skein.4 · gate: Matt's M7 — a colour change reads as a new pour, never the existing stroke recolouring**

> **M7-round-2 (Matt: "the lines are very short rather than a long continuous dripping/pouring"):** the dominant-stem argmax flickers (63 switches / 44 s), so a new pour now COMMITS only on a sustained, decisive change — `minPourTau = 3.0` τ since the last switch AND the challenger leads by `pourSwitchHysteresis = 1.25×`; colour/flow follow the *committed* pour; bursts stay ungated. 63 → 10 long pours. "Why no teal lines?" (later session) = working-as-designed: the line is the *decisive dominant* stem, and that song was vocals+bass-dominated; `other` (teal) appears only as splatter unless it's decisively dominant (song-dependent).

**Defect (Matt M7, session `2026-06-09T14-19-14Z`).** The pour line is redrawn closed-form each frame over a ~40-frame tail in ONE current `lineCol` (the dominant-stem argmax), so a dominant-stem switch recoloured the recent ~40 frames of already-laid line ("the colour changes in the middle of a stroke"). The bursts were already correct (frozen at spawn); only the line recoloured.

**Landed (D-150) — Matt chose option 2 (a colour change is a genuinely NEW pour, not a recoloured seam).** A `SkeinState` colour-**breakpoint ring** (push `(painterTau-at-switch, linear colour, bounded position offset)` on each dominant change) packed as an **additive tail** of the slot-6 `SkeinUniforms` (`SkeinBreakGPU`, 24 B; `pad0`→`breakCount`; mirrors the burst ring). `skein_geometry_fragment` Layer A looks up each tail sample's lay-time colour+offset (`skeinLineLookupAt`, ascending-ring early-out): (1) **colour freeze** — a segment laid before a switch keeps the old colour, one after gets the new (the per-burst freeze applied to the line); (2) **new pour** — each pour carries a fixed-magnitude (0.05 UV) golden-angle-rotated offset (non-cumulative → never drifts off canvas; seeded → §5.7 determinism), so the new line is spatially displaced and the segment bridging two pours is not drawn → a clean gap. **Coverage is byte-identical** to Skein.4's union SDF (one per-frame radius → `max-over-capsules ≡ 1−smoothstep(min sdf−r)`), so no rings regression. Bursts flick from the jumped position (throw direction from the un-offset path). At silence only the white baseline breakpoint exists (offset 0) → the byte-identical pre-4.1 continuous white line.

**Rejected:** option 1 (continuous path, colour frozen, no jump) — fixes the literal complaint but Matt asked for a NEW line; a pure temporal gap (no jump) — neighbouring capsules refill it at slow movement, so only a spatial jump reads as a new pour at all speeds; option B (per-frame colour into the canvas) — the closed-form tail has no single lay-frame to write into.

**Gate (all green).** New live-path test `test_lineColorFreeze_keepsColourAndStartsNewPour` (two ordered real-stem slices across a dominant switch): switch stem 2→1 — pre-switch @offA X=61 Y=0 (old paint KEEPS its colour), post-switch @offB Y=61 X=0 (new colour), jump 0.093 with the new pour at offB not the un-jumped path. Silence continuity 1.000; `test_sheen_noConcentricRings` 8.68 < 13; real-stem colour separation 4 stems / mud 0.067; determinism same-seed=0; DB/FM + `PresetRegressionTests` byte-identical; `PresetLoaderCompileFailure` count intact (FA #72); app build + SwiftLint `--strict` clean. Files: `Skein.metal`, `SkeinState.swift`, `SkeinCanvasHoldTest.swift`. **Deferred (unchanged):** `family: painterly` + `PresetCategory` case (Skein.6); mood/structure (Skein.5); cert (Skein.6).

---

### Skein.ENGINE.3 — Structural-section signal → preset tick ✅ (landed 2026-06-09; D-151; Matt chose option (a))
**engine · depends on: Skein.4.1 · gate: signal reaches `SkeinState.tick` end-to-end; every other preset byte-identical; no GPU-contract change — ALL MET**

Plumbs the live `StructuralPrediction` (`MIRPipeline.latestStructuralPrediction` — `sectionIndex`/`sectionStartTime`/`predictedNextBoundary`/`confidence`) to the preset tick via a **gated `RenderPipeline.setStructuralPrediction(_:)`** (a separate lock-guarded `storedStructuralPrediction` + computed `latestStructuralPrediction`, default `.none` — mirrors the `setMood` value-injection bridge). **Landed (D-151):** the setter is called from `VisualizerEngine+Audio.swift` **at the per-frame MIR publish (right after `setFeatures`, reading `mir.latestStructuralPrediction`)** — the audit moved it off the `setMood` site the prompt's recon named because the `setFeatures` site is unconditional + freshest (the `setMood` path early-returns when the mood classifier is absent / `classify` throws). The Skein tick closure reads `pipeline.latestStructuralPrediction` and passes it to the extended `SkeinState.tick(…structure: = .none)`, which STORES the section index/start-time/confidence + a one-frame `didCrossSectionBoundaryThisFrame` flag (cleared on `reseed`; reset to `.none` on preset switch). **Delivers + proves the signal only — the structural VISUAL is Skein.5** (infra-before-preset, FA #59/#60); the app is **visually identical to today**. CPU-only (no `FeatureVector`/`Common.metal` change; never written to the GPU buffer). Byte-identical for all other presets AND Skein itself (`PresetRegressionTests` + DB/FM MVWarp + loader count all green). Gate `SkeinStructureSignalTests` (FA #66 — real bridge + `meshPresetTick` invocation indirection + ingestion + one-frame boundary). Prompt: `~/Downloads/SKEIN.ENGINE.3_structure_plumbing_session_prompt.md`.

---

### Skein.5 — Mood + structure + anticipation + painter-locus flag ✅ (landed 2026-06-09; D-152; pending Matt M7)
**preset · depends on: Skein.3 + Skein.4.1 + **Skein.ENGINE.3** (for structure) · gate: harness across mood/section fixtures + Matt M7** · prompt: `~/Downloads/SKEIN.5_mood_structure_session_prompt.md`

**Landed (D-152) — see the ENGINEERING_PLAN Skein.5 row for the full record.** BUG-035 (NoveltyDetector ring-wrap dedup — the structure signal's corruption) was fixed first as its own increment. The four placement decisions that made the sub-features safe on a lossless canvas: mood tint at LAY TIME frozen into breakpoints/bursts (the canvas archives the emotional arc; identity at valence 0); the structural region lean routed through the per-pour breakpoint OFFSETS (a per-frame painter displacement would smear the redrawn tail), conf-gated smoothstep(0.25, 0.55) to EXACTLY zero below; anticipation as τ-SPEED warping (samples stay ON the trajectory curve — no smear by construction; exactly 1.0 at silence); the locus DISPLAY-ONLY in `skein_comp_fragment` via a gated blit buffer-1 binding (the geometry overlay would bake it permanently), OFF by default. Gates: warmth(R−B) 106.4 vs 81.4, coverage +24 %, pale 0.003; boundary flurry 88→144 on identical tiled audio, lean 0.083, conf 0.05 ⇒ all-zero; wind-up 0.649 / flick 1.627, silence 1.0; locus canvas byte-identical on/off. Craft: `SHADER_CRAFT.md §18.10`.

**Goal.** The slow global modulators + the gesture quality that makes the painter read as a performer + the agreed subtle structural bias.

**Scope.**
- **Mood:** valence → palette warmth/saturation; arousal → vigour/density. Smooth valence/arousal **in state** (never via `setFeatures` — FA #25).
- **Structure (subtle bias):** CONSUME the **Skein.ENGINE.3** signal — on `StructuralPrediction` boundaries (`sectionIndex` change), shift palette emphasis + pour density, and softly lean the painter's region so repeated sections revisit and build density — preserving overall allover-ness. **Gate the bias on `confidence`** (low → no bias, allover intact). ENGINE.3 must land first.
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
- **Determinism gate (headline property):** same track + same seed → dHash-stable final canvas across two runs, within tolerance. ~~Wire the painter seed fully to the track SHA-256.~~ **AMENDED at Skein.6 (D-159): the seed stays FNV-1a `title|artist`** (the seed every approved painting was drawn from); the SHA-256 wording was a design-phase proposal, amended in `SKEIN_DESIGN.md §1`/`§5.7`.
- Golden dHash regression entry for Skein.
- **Anti-reference check:** manual (the automated anti-reference dHash gate is itself a Missing engine capability — same gap Arachne has — so this stays an M7 judgement).
- ENGINEERING_PLAN.md rows marked landed; FidelityRubric profile set.
- **Matt M7:** live, on real music, ≥5 tracks + a local file — Pollock-must-read / painter-must-perform. Non-negotiable, non-bypassable.

**Out of scope / Do NOT.** No new features at cert. Do NOT flip `certified: true` before M7 passes.

**Key files.** `PresetAcceptanceTests.swift`, `PresetRegressionTests.swift` (golden), `SoakTestHarness` config, `Skein.json` (`certified`, `rubric_profile`), `ENGINEERING_PLAN.md`, `FidelityRubric` wiring.

**Done-when.**
- Soak clean; acceptance green; determinism gate green; golden registered.
- M7 verdict: pass.

**Status (2026-06-10, D-159).** All automated gates landed and green (coverage bound per Matt's keep-the-approved-look decision; determinism dHash; golden entry; the §5.5 soak runs the CANVAS through the live mv_warp path — `SoakTestHarness` is the headless audio-path harness and cannot observe banding/drift). `family: painterly` + `rubric_profile: lightweight` ratified. **Awaiting Matt's M7**; `certified` stays `false` until the verdict.

---

## Sequencing, cut-lines, and risk

- **Critical path:** Skein.0 → ENGINE.1 → Skein.1 → Skein.2 → Skein.3 → Skein.4 → Skein.4.1 → **ENGINE.3 → Skein.5** → Skein.6. Wet-sheen (ENGINE.2 + Skein.4) was a parallel branch off Skein.3 (cut-line NOT invoked — landed). **ENGINE.3** (structural-signal plumbing, Matt's option (a)) is the prerequisite for Skein.5's structure sub-feature (infra-before-preset).
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
