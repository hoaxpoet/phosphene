# V.7.7C.5 — Arachne §4 atmospheric reframe + canvas-filling web

**Status:** Ready for implementation. **Gated on V.7.7C.4 manual smoke green** — do
not start this increment until Matt has confirmed the V.7.7C.4 build (commit
`3feb6330`) reads as expected on real music. The §4 spec rewrite landed in
commits `97e53354` (§4 + §5.9 reframe), `a7508027` (Q14/Q15 off-frame anchors +
canvas-filling), `f6cf8ec5` (filename slot 19 → 20 fix), and `37b02910` (README
trait rewrite + slot 20). All design questions are resolved; no spec ambiguity
remains.

**Single commit.** Per the V.7.7C.3 / V.7.7C.4 atomicity guidance, this is one
commit covering shader rewrite + state-side constants + golden hash regen + docs.
Do not split unless you hit a hard SwiftLint or test-runtime ceiling that
forces a split.

---

## Where this lands

Arachne's foreground / WEB / SPIDER pillars are stable as of V.7.7C.4. What
remains visually weak is the WORLD pillar — the six-layer dark close-up forest
shipped in V.7.7B (`drawWorld()` in `Arachne.metal` ~line 175) reads as
"completely devoid of value" / "lines do not read as branches" per Matt's
2026-05-08T18-28-16Z manual smoke. The V.7.7C.5 reframe (Q&A in
`docs/presets/ARACHNE_V8_DESIGN.md §4.5`) retires the entire forest and replaces
it with a two-layer atmospheric abstraction:

1. **Atmospheric color band (full-frame).** A vertical mood-driven gradient
   that fills the full frame, replacing the V.7.7B sky band that only filled
   the upper ~40 %.
2. **Volumetric atmosphere.** Beam-anchored fog (`0.15–0.30` density inside
   shaft cones, much thinner outside) + 1–2 mood-angled god-ray light shafts
   at brightness coefficient `0.30 × val` (raised from V.7.7B's `0.06 × val`)
   + dust motes concentrated **inside the shaft cones only**.

Concurrently, Q14 + Q15 reposition the WEB so it reads as anchored to off-frame
structures that fill the canvas:

3. **Off-frame anchors.** `kBranchAnchors[6]` constants move to or just past
   the `[0,1]²` borders so the WEB threads enter the canvas from outside,
   matching ref `20_macro_backlit_purple_canvas_filling_web.jpg`.
4. **Canvas-filling web.** Foreground hero `webs[0].radius` increases from
   `0.35` to `~1.10` (so shader-side `webR = radius × 0.5 ≈ 0.55`, up from
   `0.175`) and the hub moves to canvas centre. The polygon spans most of
   the visible UV.

Anti-references (`09`, `10`) and the silence anchor (`08`) are unchanged.
Spider rendering is unchanged. Drop refraction is unchanged. The build state
machine and per-segment cooldowns are unchanged.

---

## Spec source pointers (read these first)

- `docs/presets/ARACHNE_V8_DESIGN.md §4` — full atmospheric reframe spec.
  - §4.1 conceptual frame (no literal scene; pure volumetric).
  - §4.2 layer stack (two layers, half-res `arachneWorldTex`).
  - §4.2.1 atmospheric color band (full-frame; aurora ribbon at high arousal).
  - §4.2.2 volumetric atmosphere (fog + 1–2 shafts + cone-confined motes).
  - §4.3 mood-driven color field — **preserved verbatim** (`topHue`, `botHue`,
    `satScale`, `valScale`, `topCol`, `botCol`, `beamCol`).
  - §4.4 reference cross-walk (which refs anchor what, post-reframe).
  - §4.5 decisions log (Q0–Q15).
- `docs/presets/ARACHNE_V8_DESIGN.md §5.3` — V.7.7C.5 callout box (off-frame
  anchors at `[0,1]²` borders, `webR ≈ 0.55`).
- `docs/VISUAL_REFERENCES/arachne/README.md` — mandatory / expected /
  strongly-preferred / audio-routing entries already rewritten for V.7.7C.5
  (commit `37b02910`).
- `docs/VISUAL_REFERENCES/arachne/20_macro_backlit_purple_canvas_filling_web.jpg`
  — primary visual target for both atmosphere AND web framing.
- `docs/VISUAL_REFERENCES/arachne/07_atmosphere_dust_light_shaft.jpg` — beam
  structure / cone-confined mote signature (color tint is incidental — the
  Arachne shaft tint comes from §4.3 `beamCol`, not from `07`).

The §1.1 visual-target reframe (D-096) applies: references define the aesthetic
family, NOT a pixel-match target. M7 cert review asks "does this frame belong
in the same visual conversation as ref 20?" not "does this frame match ref 20?"

---

## Files to change

### 1. `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`

**Retire** (delete the bodies; keep nothing as dead reference — this is a clean
break, the V.7.7B forest was wrong-architecture, not just under-tuned):

- The "Deep background near-black with subtle fbm tonal variation" block in
  `drawWorld()` (~line 188).
- The "Light shaft" block in its current V.7.7B form (~line 200).
- The "Dust motes" block in its current uniform-field form (~line 211).
- The "Forest floor" block (~line 216).
- All three near-frame branch blocks — left / right / lower-twig (~lines 222–278).
- The V.7.7C.2 §5.9 anchor-twig loop (~line 280–299, `for (int i = 0; i < 6; i++)`).

**Keep** (these stay verbatim — they are the §4.3 mood palette, which Q10
elected to preserve unchanged):

- The mood unpack (`v`, `a` clamped from `moodRow`).
- The §4.3 hue/saturation/value math producing `topCol`, `botCol`, `beamCol`
  (currently the implementation derives `atmDark` and `atmMid`; rebuild this
  per the §4.3 recipe with `topCol` / `botCol` / `beamCol` as named in the
  spec — the four-line literal `topHue` / `botHue` / `satScale` / `valScale`
  block is the canonical form).
- The silence anchor: `if (sat * val < 0.04) return float3(0.0);`.

**Add** (new V.7.7C.5 atmospheric layers, in this composite order):

1. **Sky band — full frame.** `col = mix(botCol, topCol, uv.y)`, with a
   low-frequency `fbm4` modulation (~5–10 % amplitude) so the gradient is not
   perfectly smooth. **Aurora ribbon (§4.2.1):** when
   `smoothedArousal > 0.6`, fade in horizontal ribbon structure phase-anchored
   to `f.beat_phase01` (Failed Approach #33 — pause at silence; the
   `accumulated_audio_time` field on `FeatureVector` is the FA-#33-compliant
   substitute when `beat_phase01` is unavailable, but here we have it). The
   ribbon term is additive, gated by `smoothstep(0.6, 0.85, smoothedArousal)`.
   No more than ~10 % brightness lift at peak; this is a subtle high-arousal
   tell, not a hero element.

2. **Fog density — beam-anchored.** Compute fog density per pixel anchored
   around the light-shaft axes (next item). Inside the shaft cones, density
   is `0.15–0.30` modulated by `f.mid_att_rel` (continuous breath); outside,
   density falls to a thinner ambient haze (`mix(botCol, topCol, 0.5) × 0.3`).
   Inside-cone color: `mix(botCol, topCol, 0.5) × kLightCol`. The fog sits
   *behind* the shafts in the composite — fog first, shafts on top.

3. **Light shafts — 1–2 mood-driven.** Engages when `f.mid_att_rel > 0.05`
   (raised from V.7.7B's 0.10 so shafts engage on lighter music). Source
   position per §4.2.2:
   - Warm valence (`v > 0`) → primary shaft enters from upper-LEFT at ~30°
     from vertical. Optional secondary at upper-LEFT ~50° engaging at high
     arousal (`smoothedArousal > 0.4`).
   - Cool valence (`v < 0`) → mirror to upper-RIGHT.
   - Neutral → defaults to warm-side angles.
   Implementation: use the V.1 utility `ls_radial_step_uv` family from
   `Volume/LightShafts.metal` (the preamble already loads it). Step-march
   along the shaft axis sampling a hash-jittered 1D noise to break the cone
   into discrete shafts (per §4.2.2 — uniform glow is the wrong reading).
   Brightness: `0.30 × val` (NOT `0.06 × val`). Color: `beamCol` per §4.3.
   Sun anchor for both fog and shafts is the same UV position (so fog is
   correctly cone-anchored).

4. **Dust motes — caustic in shafts.** Hash-lattice particle field, but only
   sampled and accumulated *inside* the shaft cones — outside, motes are
   invisible (no key light to catch them). Per-mote opacity ~0.4 (raised
   from V.7.7B's 0.3 since they only exist inside shafts). Color: local fog
   color × `kLightCol`. Density modulated by `f.mid_att_rel`. Phase-anchored
   to `f.beat_phase01` (Failed Approach #33 — no free-running `time`).

**`kBranchAnchors[6]` constants (Q14).** Move from interior positions
(`(0.18, 0.22)` etc.) to **just outside** the canvas border so the polygon
vertices are off-frame and the WEB threads enter the canvas from outside —
matching ref `20_macro_backlit_purple_canvas_filling_web.jpg` (anchors are
implied, not depicted). Locked values:

```metal
constant float2 kBranchAnchors[6] = {
    float2(-0.05,  0.05),   // upper-left, off-canvas
    float2( 1.05,  0.02),   // upper-right, off-canvas (slightly higher)
    float2( 1.06,  0.52),   // right, off-canvas
    float2( 1.04,  0.97),   // lower-right, off-canvas
    float2(-0.04,  0.95),   // lower-left, off-canvas
    float2(-0.06,  0.48)    // left, off-canvas
};
```

These coordinates lie in `[-0.06, 1.06]² \ [0,1]²` — outside the visible UV
band by ~5 % on each side, asymmetrically distributed (no two on opposing
edges at the same vertical position). Polygon vertices ARE invisible; the
visible silk is the radials and chords intersected with `[0,1]²`. The
`webR ≈ 0.55` paired with off-frame anchors guarantees the canvas-filling
reading per Q15 (polygon interior covers ~70–85 % of `[0,1]²`).

**Q14 is locked off-canvas; do not flip to "just inside" without surfacing.**

The `ArachneState.branchAnchors` Swift mirror MUST be updated byte-for-byte to
match — `ArachneBranchAnchorsTests` regression-locks the sync via
string-search.

### 2. `PhospheneEngine/Sources/Presets/Arachnid/ArachneState.swift`

- Update `branchAnchors` to match the new `kBranchAnchors[6]` MSL values
  (~line 290).
- In `seedInitialWebs()` (~line 689), update `webs[0]`:
  - `hubX: -0.35` → `hubX: 0.0` (canvas centre)
  - `hubY: 0.25` → `hubY: 0.0` (canvas centre)
  - `radius: 0.35` → `radius: 1.10` (so shader-side `webR = 0.55`)
- `webs[1]` (the secondary stable background web) stays untouched —
  background-web migration crossfade will re-seed it under the canvas-filling
  geometry naturally.
- Verify that `trySpawn`'s pool radius distribution (`0.25 + lcg(&rng) * 0.30`,
  ~line 598) is still what we want for background webs. The `webs[1..3]` pool
  webs serve as background depth context now; they should stay smaller than
  the foreground hero. No change required for V.7.7C.5; document the rationale
  in DECISIONS.md.

### 3. `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneBranchAnchorsTests.swift`

- Update the expected literal float pairs to match the new `kBranchAnchors[6]`
  values. The test string-searches `Arachne.metal` for the same float pairs
  declared in `ArachneState.branchAnchors` — the test should pass after both
  source files are updated.

### 4. Golden hash regeneration

Run `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --filter test_printGoldenHashes` and
update both:

- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift`
  — Arachne `(steady, beatHeavy, quiet)` triple. Expect significant drift
  from V.7.7C.4's `0x06129A65E458494D` / `0x0000000000000000` / `0x06129A65E458494D`
  baseline because (a) the WORLD is now atmospheric not forest, (b) the polygon
  is canvas-filling, (c) the foreground hero spans most of the frame. dHash
  hamming distance vs. V.7.7C.4 baseline expected to be HIGH — log the actual
  distances and document in the closeout report. The `beatHeavy` fixture had
  hash `0x0000000000000000` post-V.7.7C.4 because the small beat-pulse
  contribution at the harness's frame-phase-0 % composition collapsed to all
  zeros; the canvas-filling web will likely change this materially since the
  foreground now covers most pixels even at frame phase 0.

- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift`
  — spider forced hash. Expect drift since the background composition under
  the spider patch is now atmospheric instead of forest.

### 5. `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetAcceptanceTests.swift`

- The `makeRenderBuffers` Arachne slot-6 buffer seeding stays (build state
  must still seed for stable BuildState across all four invariant fixtures).
- Re-verify all four D-037 invariants pass with the canvas-filling foreground.
  Invariant 1 (non-black at silence) is robust — silence anchor in `drawWorld`
  still returns black; the foreground hero polygon at canvas-fill scale +
  warmup state must produce non-black silk. Invariant 3
  (`beatMotion ≤ continuousMotion × 2.0 + 1.0`) is the gate that V.7.7C.4's
  `0.06` coefficient calibration touched — re-confirm the new shader doesn't
  push beatMotion past the threshold. The hybrid coupling
  (`+= max(beat_bass, beat_composite) * 0.06`) stays as-is.

### 6. Documentation updates

- `docs/DECISIONS.md` — file new decision (next available, expected D-099 or
  D-100; grep `## D-0` first to confirm). Title:
  `## D-099 — Arachne §4 atmospheric reframe + off-frame anchors + canvas-filling web (V.7.7C.5)`.
  Reference the §4.5 Q&A and Q14/Q15 decisions; document the chosen
  `kBranchAnchors[6]` values (off-canvas, in `[-0.06, 1.06]² \ [0,1]²`, per
  Matt 2026-05-09; locked at prompt time, not implementer discretion).
- `docs/ENGINEERING_PLAN.md` — flip V.7.7C.5 from READY FOR IMPLEMENTATION to
  ✅ with the closeout report stub.
- `docs/RELEASE_NOTES_DEV.md` — new dev release entry (next id, follow the
  V.7.7C.4 entry's format).
- `CLAUDE.md` — update the Arachne shader doc-string (Module Map section)
  describing `drawWorld()`'s post-V.7.7C.5 contents (sky band + volumetric
  atmosphere; no forest layers; no §5.9 anchor twigs). Update
  `kBranchAnchors[6]` description if any. Update the Arachne preset
  description's mention of "six-layer dark close-up forest atmosphere" to
  "two-layer atmospheric abstraction backdrop". Add Failed Approach entry
  if anything bites during implementation that wasn't anticipated.

---

## Verification gates

1. `swift test --package-path PhospheneEngine` — full engine suite green
   except documented pre-existing flakes
   (`MetadataPreFetcher.fetch_networkTimeout` is the load-bearing one). The
   Arachne-specific suites that MUST pass:
   - `PresetAcceptanceTests` (Arachne × 4 invariants)
   - `PresetRegressionTests` (Arachne × 3 fixtures, with the regenerated hashes)
   - `ArachneSpiderRenderTests` (with the regenerated forced hash)
   - `ArachneStateTests` + `ArachneStateBuildTests` (build state machine
     unaffected by V.7.7C.5; if they fail, you have unintended state coupling)
   - `ArachneBranchAnchorsTests` (regression-locks Swift / MSL sync after
     the constants move)
   - `ArachneListeningPoseTests` (spider unaffected by V.7.7C.5)
   - `PresetLoaderCompileFailureTest` (catches Failed Approach #44 silent
     shader-compile drops — if Arachne falls out of the production preset
     count, the test will fail loudly)
   - `StagedCompositionTests` + `StagedPresetBufferBindingTests` (staged
     dispatch contract unaffected; if these fail you have a binding regression)

2. `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` —
   app build clean (warnings-as-errors).

3. `swiftlint lint --strict --config .swiftlint.yml` — zero violations on
   touched files. The `Arachne.metal` `.metal` file has no SwiftLint coverage
   but the `.swift` files (`ArachneState.swift`, tests) do.

4. `RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests` — produces
   per-stage PNGs for Arachne (silence / mid / beat fixtures × WORLD stage +
   COMPOSITE stage). **Eyeball the WORLD PNGs against ref 20** before
   committing. The COMPOSITE PNGs should show the canvas-filling foreground
   over the atmospheric backdrop (the sole visible element in regression-mode
   PresetRegressionTests since `worldTex` is unbound there; in the per-stage
   harness `worldTex` IS bound from the WORLD stage). Save the PNG paths in
   the closeout report.

5. `Scripts/check_sample_rate_literals.sh` — no new `44100` literals
   (D-079 / Failed Approach #52 lint gate; this increment shouldn't introduce
   any but the gate runs anyway).

---

## Closeout report scope (CLAUDE.md Increment Completion Protocol)

Required sections:

1. **Files changed** — concrete paths, grouped new vs. edited.
2. **Tests run** — engine + app suite counts, pass/fail, pre-existing flakes
   called out by name.
3. **Visual harness output** — `RENDER_VISUAL=1` PNG paths (WORLD silence /
   mid / beat; COMPOSITE silence / mid / beat). Note in plain language what
   the WORLD PNGs show. Compare against ref `20`.
4. **Documentation updates** — list every doc file touched
   (CLAUDE.md / DECISIONS.md / ENGINEERING_PLAN.md / RELEASE_NOTES_DEV.md /
   any others).
5. **Capability registry updates** — V.7.7C.5 is preset-internal; the
   renderer / harness / certification capabilities are unchanged. Confirm
   no `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` rows changed.
6. **Engineering plan updates** — V.7.7C.5 row flipped to ✅; cite line
   numbers and the new commit hash.
7. **Known risks and follow-ups** — V.7.10 cert review (Matt M7 contact
   sheet); V.7.7C.6 spider movement (deferred); any §4 sub-elements that
   aren't fully landed (aurora ribbon at high arousal can be deferred to a
   follow-up if it lands flaky — document the deferral).
8. **Git status** — branch (`main`), commit hash, `git status` clean
   (only V.7.7C.5 files staged + committed; nothing from the working tree's
   ongoing DM.2 / Lumen Mosaic / prompts work bled in — same scope-discipline
   that the V.7.7C.4 land followed).
9. **dHash drift table** — Arachne three regression hashes + spider forced
   hash, V.7.7C.4 → V.7.7C.5, with hamming distances. Helps future
   forensics if a downstream regression surfaces.

---

## Stop conditions — pause and surface to Matt

- **PresetAcceptance D-037 invariant 3 fails** (beatMotion threshold breach).
  The hybrid coupling coefficient `0.06` was calibrated against the V.7.7C.4
  shader; if the canvas-filling foreground changes the proxy continuousMotion
  reading enough that `0.06` is no longer safe, surface before tuning. Do
  NOT tune the coefficient unilaterally — the calibration is paired with the
  V.7.7C.4 manual-smoke green and should not drift without Matt's review.

- **Aurora ribbon implementation introduces visible artifacts at high
  arousal.** §4.2.1 calls for it but it's a tertiary detail. If the
  implementation has time-budget / coupling problems, defer to a follow-up
  increment and document. Don't ship visibly-broken aurora.

- **Polygon visibility regression — chord-by-chord spiral no longer reads.**
  V.7.7C.3 fixed this with a per-chord visibility gate
  (`globalChordIdx < int(progress × N_RINGS × nSpk)`); the canvas-filling
  geometry shouldn't break it but might surface a calibration issue if the
  spiral now spans many more pixels. If chords visibly clump at scale,
  surface before re-tuning.

- **Background webs (slots 1–3) render at canvas-filling scale alongside
  the foreground.** That would defeat the foreground/background separation.
  V.7.7C.3 retired the V.7.5 pool from rendering (shader pool loop starts at
  `wi = 1` with empty body); confirm this is still the case post-V.7.7C.5.
  If background webs appear at canvas-filling scale, you've accidentally
  re-enabled the pool render path.

- **`worldTex` unbound in regression mode produces black-only frames.** Some
  Arachne regression hashes might collapse to all zeros. That's expected for
  the `quiet` fixture (no audio, foreground at progress=stable produces
  silk-only over black). It's NOT expected for `steady` and `beatHeavy`. If
  multiple fixtures collapse to `0x0000…`, you have a foreground rendering
  regression — surface.

- **The chosen `kBranchAnchors[6]` values produce a polygon that doesn't
  span most of the canvas after the `radius: 1.10` change.** Q15 spec is
  "polygon interior occupies ~70–85 % of canvas area". If you get less,
  surface — either the radius needs to go higher than 1.10, or the anchor
  positions need to push further out, or both. Document the choice.

---

## Git protocol

- Commit format: `[V.7.7C.5] Arachne: §4 atmospheric reframe + off-frame anchors + canvas-filling web (D-095 follow-up #3)`.
- One commit (split only if forced by hard ceilings — see header).
- **Do not push to origin/main.** Local commit only. Wait for Matt's "push" /
  "yes, push" before `git push`.
- The working tree currently has unrelated DM.2 (Common.metal extension),
  Lumen Mosaic (docs/presets/), and prompts/ work pending. Stage ONLY
  V.7.7C.5 files; verify `git status` shows the unrelated work still
  unstaged before committing.

---

## Failed Approaches / risks to remember

- **Failed Approach #33 — `sin(time)` in organic preset motion.** The
  aurora ribbon and dust mote drift MUST phase-anchor to `f.beat_phase01`
  (or `accumulated_audio_time` as the silence-pause-compatible substitute).
  Free-running `time` regresses Arachne to mechanical motion.

- **Failed Approach #42 — `smoothstep(0.x, 0.y, fbm8(...))` thresholds
  above 0.3.** `fbm8` is centred at 0; thresholds above 0.3 always return 0.
  The V.7.7C.5 shader rewrites use `fbm4` for sky-band noise modulation,
  which has the same characteristic — centre any threshold near 0 or remap
  first.

- **Failed Approach #44 — Metal type-name shadowing.** Variables named
  `half`, `ushort`, etc. silently break shader compilation. The
  `PresetLoaderCompileFailureTest` will catch this loudly if the preset
  count drops below 15 — but watch for it on first compile attempts.

- **Failed Approach #57 — acoustically-impossible spider trigger.** Don't
  reintroduce. Spider trigger is `f.bass_att_rel > 0.30` (V.7.7C.4 form),
  not subBass + bassAttackRatio. The V.7.7C.5 increment doesn't touch the
  spider, but if you find yourself near `ArachneState+Spider.swift`, leave
  it alone.

- **CLAUDE.md "Do not call `drawWorld()` from `arachne_composite_fragment`."**
  WORLD stage owns the call; COMPOSITE samples the resulting texture at
  `[[texture(13)]]`. The V.7.7C.5 increment retires forest layers within
  `drawWorld()`; it does NOT change which stage calls `drawWorld()`. Verify
  the `worldTex.sample(arachne_world_sampler, uv)` line at the bottom of
  `arachne_composite_fragment` (~line 1540 area) is unchanged.

- **CLAUDE.md "Do not pack per-segment Arachne polygon state into webs[0]
  Row 5 or a new WebGPU row."** Polygon anchor indices stay in
  `webs[0].rngSeed` (V.7.7C.3 contract). The V.7.7C.5 reframe changes the
  *positions* the indices reference (`kBranchAnchors[6]` move), not the
  packing scheme.

- **CLAUDE.md "Do not gate the chord spiral on per-ring visibility."**
  V.7.7C.3's per-chord gate (`globalChordIdx < int(progress × N_RINGS × nSpk)`)
  is the load-bearing fix. The V.7.7C.5 increment doesn't change the gate
  but the spiral spans more pixels at canvas-filling scale, so visually
  re-verify the chord-by-chord lay still reads correctly.

- **CLAUDE.md "Do not re-enable the V.7.5 pool web rendering loop."** The
  shader's pool loop bound stays at `for (int wi = 1; wi < 1; wi++)` (empty
  body). V.7.7C.5 is the FOREGROUND atmospheric reframe — background webs
  stay invisible to the shader. CPU-side V.7.5 spawn state continues to
  advance harmlessly so unit tests pass.

- **D-019 stem-warmup blend.** The §4 atmosphere doesn't directly read
  stems but if the implementation introduces any stem-keyed variation,
  apply the `smoothstep(0.02, 0.06, totalStemEnergy)` blend per D-019. The
  current §4 spec uses only `f.mid_att_rel` + mood (which is FV-derived),
  so this should not bite — but flag if any new `stems.*` reference creeps in.

- **D-026 deviation primitives.** Audio routing must use deviation
  primitives (`f.bass_att_rel`, `f.mid_att_rel`, `bassDev`, etc.) and never
  absolute thresholds (`smoothstep(0.22, 0.32, f.bass)`). The V.7.7C.5
  spec already uses `f.mid_att_rel`; preserve that.

- **`base_zoom` ≥ 2× `beat_zoom` rule (CLAUDE.md Audio Data Hierarchy).**
  Atmosphere is continuous-energy-driven; no beat-driven motion in §4 means
  this rule is trivially satisfied. Don't accidentally introduce
  beat-driven shaft pulsing or beat-driven fog density spikes — that would
  regress to "beat-dominant" reading (Failed Approach #4).

---

## Closing note

V.7.7C.5 is the last load-bearing structural increment for Arachne 2D before
V.7.10 cert review. After this lands and Matt eyeballs it green, the only
remaining 2D Arachne work is V.7.10 (Matt M7 contact-sheet review +
`certified: true` flip), the three V.7.10 follow-ups (per-chord drop
accretion, anchor-blob discs at polygon vertices, background-web migration
crossfade visual), and V.7.7C.6 (spider movement system, V.7.7D-scale —
deferred per Matt 2026-05-08 sequencing).

Single commit. No push without Matt approval. Read §4 and §4.5 in
`ARACHNE_V8_DESIGN.md` before touching any code.
