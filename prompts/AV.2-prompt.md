# AV.2 — Aurora Veil multi-column parallax + audio routing

**Increment ID:** AV.2
**Status:** ⏳ Planned (after AV.1 land 2026-05-18)
**Authoritative design:** `docs/presets/AURORA_VEIL_DESIGN.md` §5.7 (audio routing) + §5.5 (off-axis composition) + §5.4 (multi-timescale motion table — AV.2 substrate row only; sub-second + 2–20 s rows stay deferred to AV.3)
**Research dossier:** `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` — §3.1 / §3.2 / §3.3 are the load-bearing audio-routing sections (Magnetosphere precedent, drum-kink rare-event gating, vocal-pitch sourcing)
**Reference set:** `docs/VISUAL_REFERENCES/aurora_veil/` (4 must-pass + anti-ref); the README's amended mandatory-traits checklist is the implementer-side acceptance gate
**Engineering plan entry:** `docs/ENGINEERING_PLAN.md` → Phase AV → "Increment AV.2 — Multi-ribbon parallax + audio routing"
**Sibling preset (precedent):** Gossamer — direct-fragment + mv_warp + audio routing via D-019 stem-warmup blend; the closest neighbour for the seven-route wiring pattern

---

## The product change in one paragraph

Aurora Veil moves from silence-stable single-column to **audio-responsive multi-column**. Three implicit drift columns at off-thirds horizontal positions create the multi-curtain parallax depth the references show (ref `04`); per-column depth-scale dimming + non-parallel drift velocities are what reads as "ribbons stacked at different distances from camera." The seven audio routes from `AURORA_VEIL_DESIGN.md §5.7` wire on top — vocals_pitch → palette phase along the ribbon (Sigur Rós-grade slow hue migration with the song's melody); `bass_att_rel` breathes overall brightness; `mid_att_rel` modulates fold density (`tri_noise_2d` spatial frequency); `bass_att_rel` also speeds up substrate drift; gated `stems.drums_energy_dev` kinks the curtain laterally on rare high-amplitude drum events with damped 1–2 s response (Failure Mode #11 — festival strobe — mitigated by construction); `f.valence` shifts palette warm/cool; `f.beat_phase01` gated by `vocals_pitch_confidence > 0.5` adds subtle star twinkle. **No multi-timescale motion enrichment (sub-second flicker + 2–20 s pulsation envelope) — those land at AV.3.** The two new preset-specific tests (`AuroraVeilContinuousDominanceTest`, `AuroraVeilPitchHueTest`) verify the routing produces what the design promises (continuous primaries dominate accents by ≥ 10×; vocal pitch sweep produces continuous, not stepwise, hue migration).

This is the increment where Aurora Veil becomes a *music* visualizer rather than a *silence-renders-aurora* demo. The audio coupling is the load-bearing change; the multi-column is the load-bearing visual change. Done together because the vocal-pitch palette migration reads correctly only when there's enough visual structure (multiple ribbons) to host it.

---

## Read these first

In this order. The AV.1 closeout (`docs/RELEASE_NOTES_DEV.md` entry `dev-2026-05-18-c`) explains what landed and the deviations from the prompt's literal recipe — read it so you understand the camera-less Lawlor stratification mechanism (phase-rate + base-offset by screen-altitude) you're about to extend.

1. **`docs/RELEASE_NOTES_DEV.md` entry `[dev-2026-05-18-c]`** — AV.1 closeout. The "Implementation notes" section is load-bearing: AV.1 added `phaseRate = mix(0.005, 0.043, topness)` + `baseOffset = 2.0 * topness` to the prompt's literal recipe. AV.2's vocal-pitch palette phase MUST add to `baseOffset` (not replace it) — the topness-driven Lawlor stratification stays. Skim the "9-question rubric — AV.1 status" — Q3 (vertical ray fine structure) and Q7 (off-axis composition) are partial because of the single-column AV.1 scope; AV.2's multi-column work closes both.
2. **`docs/presets/AURORA_VEIL_DESIGN.md` §5.6 / §5.7 / §5.8** — audio-route table, vocals_pitch sourcing resolution, silence fallback. §5.7 is the canonical source for the seven routes. §5.6's `kinkAccumulator` form is mandatory (rare-event gated, damped response). §5.8 silence fallback continues to work.
3. **`docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` §3.1 / §3.2 / §3.3** — audio-coupling lessons. §3.1 names Magnetosphere as the validated precedent (continuous spectral coupling primary, beat accent only). §3.2 spells out the drum-kink rare-event gating + damped response form (load-bearing — getting this wrong is Failure Mode #11). §3.3 resolves the vocals_pitch sourcing problem (read `stems.vocals_pitch_hz` direct, normalize via log2, fall back to 0.5 on low confidence).
4. **`docs/VISUAL_REFERENCES/aurora_veil/AURORA_VEIL_README.md`** — per-image annotations + mandatory-traits checklist + audio-routing notes. The "Audio routing notes" section's "Continuous primary drivers" / "Beat accents" / "Stem warmup" / "Structure stays solid" / "Continuous-vs-accent ratio" headings are the acceptance-shape contract. Reference `04_atmosphere_multi_curtain_parallax.jpg` is the closest visual target for the multi-column work — three ribbons at slightly different angles with clear depth ordering.
5. **`PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.metal`** — the AV.1 shader. Read end-to-end. The header docstring + inline comments on `phaseRate` / `baseOffset` / sky-blue trim / rotation-rate slow / final clamp explain why each constant lands where it does. AV.2 modifies the fragment body (multi-column loop + audio routing) and `mvWarpPerFrame` (audio-modulated zoom / rot + kinkAccumulator into a q-var) and `mvWarpPerVertex` (kink applied to UV displacement).
6. **`PhospheneEngine/Sources/Presets/Shaders/Gossamer.metal`** — the closest catalog precedent for D-019 stem-warmup blend. Lines 127–135 show the canonical form: compute `totalStemEnergy`, blend `f.*_att_rel` with `stems.*_energy_rel` via `smoothstep(0.02, 0.06, totalStemEnergy)`. Match this verbatim for the bass/mid reads.
7. **`PhospheneEngine/Sources/Renderer/Shaders/Common.metal` lines 60–100** — `StemFeatures` MSL layout. The fields you'll read at AV.2: `vocals_pitch_hz` (float 41), `vocals_pitch_confidence` (float 42), `drums_energy_dev` (float 21), `bass_energy_rel` (float 23), `vocals_energy_rel` (float 19). Verify offsets before reading; the AV.1 prompt warned about `SpectralHistoryBuffer[1920..]` being bar phase not pitch — same precision required here.
8. **`PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.json`** — current sidecar. AV.2 may bump `motion_intensity` (currently 0.25; the multi-column adds visible motion via the kink + brightness breathing) and update the description field. Do NOT flip `certified` — that's AV.3's gate after Matt M7.
9. **`CLAUDE.md`** — re-read the Audio Data Hierarchy, Failed Approach #4 (beat-dominant designs), Failed Approach #31 (absolute thresholds on AGC), Failed Approach #67 (one audio primitive per visual layer — see §AV-routing-conflicts below), Failed Approach #63 (mid-session visual check against named references), and D-026 (deviation primitives) / D-019 (stem-warmup blend).
10. **`docs/SHADER_CRAFT.md` §12.7** — pale-tone-share ceiling. Aurora Veil is emission-only and isn't currently at risk, but with vocal-pitch phase migration the palette can drift toward cream/pearl in the high-pitch range. If it does, the §12.7 ceiling kicks in.

You do NOT need to read: the AV.1-paperwork commits (the design is already amended), the full Phase MV history, Arachne / Ferrofluid / Lumen Mosaic preset details, or the live nimitz Shadertoy source.

---

## What the codebase already does (don't re-implement)

- **AV.1 shader** is in place. The fragment renders sky + 50-step volumetric raymarch + stars with the camera-less Lawlor stratification (phase-rate + base-offset by screen-altitude). `mvWarpPerFrame` / `mvWarpPerVertex` are wired at conservative parameters. `pf.q1` carries `f.time` for curl-noise advection — AV.2 will repurpose this slot.
- **D-019 stem-warmup blend pattern** — Gossamer.metal lines 127–135 is the canonical form. Compute `totalStemEnergy = stems.vocals_energy + stems.drums_energy + stems.bass_energy + stems.other_energy`; blend via `smoothstep(0.02, 0.06, totalStemEnergy)`. Every `stems.*` read must blend with a FeatureVector proxy.
- **D-026 deviation primitives** — `f.bass_att_rel` / `f.mid_att_rel` / `f.valence` are already on `FeatureVector`. `stems.vocals_pitch_hz` / `stems.vocals_pitch_confidence` / `stems.drums_energy_dev` / `stems.bass_energy_rel` are on `StemFeatures` (MV-3, post-DM.2 extension D-099). No engine work — every primitive you need is bound.
- **`PresetRegressionTests` golden-hash table** — Aurora Veil entry exists; regen expected at AV.2 because audio routes will drive across-fixture divergence. Use `UPDATE_GOLDEN_SNAPSHOTS=1` to regen.
- **`PresetAcceptanceTests`** — the `beatMotion ≤ continuousMotion * 2 + 1` invariant currently passes (AV.1 has no audio routing). AV.2's audio coupling could push this boundary — see §AV-beatresp below.
- **`PresetVisualReviewTests`** — Aurora Veil is in the arg list; `RENDER_VISUAL=1` produces silence / mid / beat PNGs. AV.2 will produce visibly different renders across the three fixtures (mid + beat will show audio response); use this for the mid-session sanity check.
- **Star renderer at AV.1** — sparse `hash_f01_2(uv * 800) > 0.997` pinpoints. AV.2 adds the beat_phase01-gated star twinkle on top per §5.7; leave the base star pattern alone.
- **`AuroraVeilSilenceTest`** — three assertions on the silence frame. Should continue to pass at AV.2 (silence fallback is intact). If it fails, the silence-stable contract is broken — investigate before forging ahead.

---

## What this increment changes

### 1. Multi-column raymarch (closes 9-Q rubric Q3 + Q7)

The AV.1 shader has one implicit column rooted at `uv.x`. AV.2 adds two more at off-thirds positions with depth-scale dimming + non-parallel drift velocities.

**Three columns:** anchor at `uv.x` (foreground, depth=1.0), offset `+0.27` (mid-ground, depth=0.7), offset `-0.18` (background, depth=0.5). Per-column drift velocity scales with depth (background drifts slower → parallax illusion of depth). Each column's noise sample is `aurora_tri_noise_2d(float2(uv.x + offset, pt), spd, time * velocityScale)`; depth-scale dims the column's contribution by multiplying the final accumulator.

The combined accumulator is a **MAX**, not a SUM, over the three columns — physically, "the ribbon you see at this pixel is the brightest ribbon at this pixel," not "the sum of all overlapping ribbons." Sum would over-saturate where columns coincide; max preserves the ribbon character.

**Important: the per-fragment phase-rate + base-offset stratification (AV.1) stays.** Each column contributes its own per-`i` palette × noise; the per-fragment phase machinery is applied uniformly across all three columns. The visual result: three vertically-stratified ribbons at different horizontal positions, brightness-modulated by depth, with the green-base / magenta-crown gradient running through all of them.

### 2. Audio routing — seven routes per `AURORA_VEIL_DESIGN.md §5.7`

| # | Route | Source | Target | Form |
|---|---|---|---|---|
| 1 | Hue along ribbon | `stems.vocals_pitch_hz` + `vocals_pitch_confidence` | Per-fragment palette `baseOffset` additive | `vocalsPitchNorm = clamp(log2(max(pitch_hz, 80.0) / 80.0) / 4.0, 0, 1)`; smoothed 5-frame moving average (CPU-side, or use the `*_smoothed` proxy if available — check `Common.metal` for `vocals_pitch_*_smoothed`); fallback 0.5 on `confidence < 0.5`. Add `(vocalsPitchNorm - 0.5) * 1.6` to `baseOffset` (range ±0.8 — shifts palette phase by ~1 IQ cycle worth, gives clear hue migration). |
| 2 | Brightness breathing | `f.bass_att_rel` (D-019-blended with `stems.bass_energy_rel`) | Aurora final scale | Replace `kAuroraGain` with `kAuroraGain * (0.85 + 0.30 * bassRel)`. Continuous, never beat — Failed Approach #4 compliant. |
| 3 | Fold density | `f.mid_att_rel` (D-019-blended with `stems.vocals_energy_rel`) | `tri_noise_2d` spatial frequency | Multiply `marchPos` by `(1.0 + 0.30 * midRel)` before sampling — thicker mids → denser folds. |
| 4 | Substrate drift speed | `f.bass_att_rel` (same blend as route 2) | `aurora_tri_noise_2d` `spd` argument | `spd = 0.06 + 0.04 * bassRel`. Faster drift on high-bass sections. |
| 5 | Curtain kink | `kinkAccumulator` gated on `stems.drums_energy_dev` | mv_warp y-displacement amplitude | CPU OR shader-side accumulator (see §AV-kink below). Form: `kinkAccumulator = max(kinkAccumulator * 0.93, drums_energy_dev * smoothstep(0.4, 0.7, drums_energy_dev))`. Decays ~0.5/sec. Charge only on `drums_energy_dev > 0.4` events. Pass through `pf.q2`. Per-vertex disp adds `float2(0, pf.q2 * 0.003 * sin(uv.x * 12.0))`. |
| 6 | Palette warm/cool | `f.valence` | Per-fragment palette additive phase | Add `f.valence * 0.4` to `baseOffset` (positive valence → warmer shift). Stacks with route 1. |
| 7 | Star twinkle | `f.beat_phase01` gated by `vocals_pitch_confidence > 0.5` | Per-star brightness modulation | Multiply `starShade` by `(1.0 + 0.30 * sin(f.beat_phase01 * 2.0 * π + hash_f01_2(uv * 800) * π) * step(0.5, vocals_pitch_confidence))`. Subtle — obvious twinkle reads as decorative. |

**Stacking the palette routes.** Routes 1 (vocals) and 6 (valence) both modify `baseOffset`. They're additive: `baseOffset = 2.0 * topness + (vocalsPitchNorm - 0.5) * 1.6 + f.valence * 0.4`. Topness is the dominant term (the Lawlor stratification), vocals + valence are perturbations.

### 3. CPU-side kink accumulator (§AV-kink — open question)

The kink accumulator's `max(prev * 0.93, drums * smoothstep(0.4, 0.7, drums))` form needs PERSISTENT state between frames. Two implementation paths:

**Path A — shader-side, leak through mv_warp's q-var.** `pf.q2 = pf.q2 * 0.93 + drums_energy_dev * smoothstep(0.4, 0.7, drums_energy_dev)`. Problem: `pf` is freshly constructed per-frame; there's no GPU-side persistent state for a non-mesh / non-staged direct-fragment preset. Won't work without engine plumbing.

**Path B — CPU-side, set via `setStemFeatures`-like proxy.** Compute the accumulator on the CPU side each frame in `VisualizerEngine`, pass through a slot 6 / 7 buffer or as a synthesized `StemFeatures` field. Adds CPU code outside the shader file.

**Path C (recommended) — leak through the warp-pass feedback texture itself.** The mv_warp pipeline already has a persistent feedback texture (per D-027 / decay 0.945). The accumulator can live as a "ghost" — but reading it back requires sampling the previous warp texture from the fragment shader, which the existing preamble doesn't expose to `aurora_fragment` (only to `mvWarp_fragment`). Won't work without engine work.

**Recommended:** Path B. Add a CPU-side `AuroraVeilState` class (similar to Gossamer's `GossamerState` or Lumen's `LumenPatternState`) that ticks the accumulator each frame from `stems.drums_energy_dev`, exposes it via a small UMA buffer at slot 6. Bind the buffer in `VisualizerEngine+Presets.swift` (look at the Gossamer wiring at the `setPresetFragmentBuffer` call site). Read in fragment as `constant AuroraVeilStateGPU& av [[buffer(6)]]; float kinkAmp = av.kinkAccumulator;`.

Match Gossamer's State struct pattern verbatim (CPU `AuroraVeilState` class with `@unchecked Sendable`, `MTLBuffer` allocation, per-frame `tick(features:, stems:)` method).

**If this scope makes AV.2 too large**, defer the kink to a smaller AV.2.5 increment and ship multi-column + the six continuous routes first. Surface to Matt before splitting.

### 4. New tests

- **`AuroraVeilContinuousDominanceTest.swift`** (`@Suite("AuroraVeil continuous dominance")`). Render with zero `drums_energy_dev` and rising `bass_att_rel` (e.g. 0.0, 0.2, 0.4, 0.6, 0.8); assert frame max-luma scales monotonically with `bass_att_rel` by ≥ 0.2 amplitude across the sweep. Validates continuous primary driver (brightness breathing) actually dominates. Complement with a paired check: render with rising `drums_energy_dev` and zero `bass_att_rel`; assert the visual change (UV displacement amplitude in the kink direction) is < 10 % of the bass-driven brightness change at peak — encodes the §5.7 continuous-vs-accent ratio ≥ 10× contract.
- **`AuroraVeilPitchHueTest.swift`** (`@Suite("AuroraVeil pitch hue")`). Sweep `stems.vocals_pitch_hz` from 100 Hz → 2000 Hz in 8 steps (with `vocals_pitch_confidence = 1.0`); for each, sample the ribbon's hue at uv.y = 0.4 / 0.5 / 0.6 in the brightest column; assert the hue value (extracted as a single scalar via `atan2(R-G, B-G)` or similar) shifts monotonically across the sweep AND the step-to-step delta stays below a "stepwise" threshold (e.g. no single step > 30 % of total sweep range). Catches the failure mode where pitch quantization makes the palette jump rather than slide.

The AV.1 `AuroraVeilSilenceTest` continues to pass — silence fallback intact.

### 5. Hash regen + JSON description bump + visual review

- Regenerate the three golden hashes (`UPDATE_GOLDEN_SNAPSHOTS=1 swift test --filter "Print golden hashes"`). Steady / beat-heavy / quiet will all drift because audio is now coupled. Replace the AV.1 hashes; update the comment to note "AV.2 wired the seven audio routes per §5.7; hashes drift across fixtures."
- Update `AuroraVeil.json` `description` to drop "AV.1: silence-stable" and reflect AV.2 state. Optionally bump `motion_intensity` to 0.35 if the multi-column + kink reads as more motion than 0.25 captured (judgment call — Matt's M7 will tune this anyway at AV.3).
- `RENDER_VISUAL=1` PNG inspection: silence frame should look identical to AV.1; mid + beat frames should show clearly modulated brightness + visible kink on the beat fixture. Side-by-side against ref `04_atmosphere_multi_curtain_parallax.jpg` — three ribbons should be visible at different depths (depth-dimming readable; brighter foreground, dimmer background).

---

## Done when

- [ ] `AuroraVeil.metal` updated: 3-column raymarch loop (anchor + 2 offsets with depth dimming + non-parallel velocities), seven audio routes wired per §5.7, D-019 stem-warmup blend on every `stems.*` read.
- [ ] CPU-side `AuroraVeilState` class added (assuming Path B, §AV-kink) for the kink accumulator; wired in `VisualizerEngine+Presets.swift` like Gossamer's state path. Path A or C documented if Path B is rejected for scope reasons.
- [ ] `AuroraVeilSilenceTest` continues to pass — silence fallback intact (no `stems.*` energy → kink accumulator stays at 0 → bass-blend defaults to FeatureVector → silence-stable).
- [ ] New `AuroraVeilContinuousDominanceTest` passes (continuous primaries dominate accents by ≥ 10×).
- [ ] New `AuroraVeilPitchHueTest` passes (vocal-pitch sweep produces monotonic + continuous hue migration).
- [ ] `PresetAcceptanceTests` continue to pass — especially the `beatMotion ≤ continuousMotion * 2 + 1` invariant (§AV-beatresp below).
- [ ] `PresetRegressionTests` golden hash regen — three hashes for Aurora Veil reflect AV.2 state. Comment block updated.
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` clean.
- [ ] `swift test --package-path PhospheneEngine` full suite green (modulo documented pre-existing flakes: `MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel` timing race).
- [ ] `swiftlint lint --strict --config .swiftlint.yml` — 0 violations on touched files.
- [ ] **Visual mid-fixture sanity check (load-bearing).** Open `Aurora_Veil_mid.png` and `Aurora_Veil_beat.png` from `RENDER_VISUAL=1` output. Side-by-side comparison vs `04_atmosphere_multi_curtain_parallax.jpg` (depth-ordered multi-ribbon target) and `01_macro_curtain_hero_purple_green.jpg` (multi-curtain composition with full color range visible). Per Failed Approach #63 the check is comparison against NAMED references, NOT self-judgment.
  - Three distinct ribbons readable at different depths? Brighter foreground ribbon, dimmer background ones? Drift velocities visibly non-parallel between successive frames (compare mid vs beat — same noise field rotation but bass-driven `spd` and vocal-driven palette phase differ)?
  - Vocal-pitch palette migration reads as smooth hue shift along the ribbon, NOT stepwise / quantized? (`AuroraVeilPitchHueTest` is the automated gate; the visual check is the sanity floor.)
  - Beat fixture's curtain kink reads as a slow 1–2 s shudder, NOT a per-beat hard deflection? (If it's hard deflections, the §3.2 rare-event gating is broken — likely the `smoothstep(0.4, 0.7, drums_energy_dev)` threshold is too low, or the 0.93 decay coefficient is wrong.)
  - Bottom-band silhouette: still present (or did the multi-column extend aurora into the previously-dark band)? auroraEnv should still cut off at uv.y > 0.84.
  - Anti-reference check: does the rendered output NOT read like `09_anti_neon_festival_aurora.jpg`? Pure-saturation neon, festival strobe (per-beat brightness flashing), kinetic ribbons converging to a focal point — none should be present.
- [ ] **9-question authenticity rubric check** (`AURORA_VEIL_RESEARCH_2026-05-18.md §2.3`). AV.2 should close Q3 (vertical ray fine structure via multi-column at different `pt`-sample positions) and Q7 (off-axis composition via off-thirds column placement). Q4 (multi-timescale motion) stays partial — AV.3 work. Document each Q1–Q9 with YES / NO / PARTIAL in the closeout report.
- [ ] AV.2 entry in `docs/ENGINEERING_PLAN.md` flipped from ⏳ to ✅. AV.2 release-notes entry added to `docs/RELEASE_NOTES_DEV.md` (entry `[dev-YYYY-MM-DD-X]`).

**No Matt M7 review at AV.2** — that's AV.3 (after sub-second flicker + 2–20 s pulsation envelope land + perf-profile run). AV.2's visual check is your own side-by-side against named references + the rubric.

---

## Verify

After each logical step and at the end:

```
swift test --package-path PhospheneEngine --filter "AuroraVeil|PresetLoaderCompileFailure|PresetRegression|PresetAcceptance|FidelityRubric"

RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "PresetVisualReview" 2>&1 | grep "Aurora Veil"
# Open /tmp/phosphene_visual/<ISO8601>/Aurora_Veil_{silence,mid,beat}.png

xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build

swiftlint lint --strict --config .swiftlint.yml
```

---

## Out of scope (AV.3 work, do not touch)

- **Sub-second ray flicker (5–10 Hz)** — research §2.1 + design §5.4. AV.3 polish via `rzt *= 1.0 + 0.10 * fbm2(float2(uv.x * 4.0, time * 8.0))`.
- **2–20 second whole-curtain pulsation envelope** — design §5.4 row. `aurora *= 0.85 + 0.15 * fbm2(float2(time * 0.1, 0.0))`.
- **Matt M7 cert review + `certified: true` flip** — AV.3 final gate.
- **Star-density / silhouette-foreground tuning** — the AV.1 closeout flagged the rendered output has dense stars and no silhouette foreground in the bottom band. Three remediation options were documented (reduce density, mask stars under aurora envelope, add silhouette band). All deferred to AV.3 polish. If you find the stars distracting at AV.2 review, surface to Matt — do not fix unilaterally.
- **Tuning palette constants against curated references** — AV.3's job. AV.2 wires the audio routes at their nominal amplitudes per §5.7; final tuning lands at cert.
- **Performance profiling against Tier-1 / Tier-2 budget** — AV.3 deliverable. If you observe a regression, surface it (§AV-perf) but don't preemptively optimize.

---

## Open questions to surface (don't decide alone)

### §AV-kink — kink accumulator implementation path

Path A (shader-side q-var) doesn't work without engine plumbing. Path C (warp-feedback ghost) doesn't work without engine plumbing. **Path B (CPU-side state class) is recommended.** If the scope feels too large for one increment, **stop and ask Matt** about splitting AV.2 into:

- AV.2a: multi-column + six continuous audio routes (no kink).
- AV.2b: kink accumulator + `AuroraVeilState` class + drum-route wiring.

Both halves are individually testable; the split keeps each session under 3 hours.

### §AV-beatresp — PresetAcceptance beat-response invariant

The `beatMotion ≤ continuousMotion * 2 + 1` invariant in `PresetAcceptanceTests.test_beatResponse_bounded` could push back on AV.2's routing amplitudes. The beat-heavy fixture has `beat_bass = 1.0`, `bassDev = 0.60`, `bassRel = 0.60` — so brightness breathing on bass_att_rel will produce a large continuous-motion delta (good — that's what we want), and the drum-kink (only via `stems.drums_energy_dev` which is zero in `PresetAcceptanceTests` fixtures because there are no stems!) will not fire. The invariant should pass naturally because continuousMotion will be large.

But if it fails, the most likely cause is the kink accumulator carrying state between successive `renderFrame` calls in the harness (which would create unexpected motion). Verify the test fixture resets the accumulator between fixtures (zero `stems.drums_energy_dev` → accumulator decays to zero quickly, but `renderFrame` is called sequentially with shared state). The AuroraVeilState `reset()` method must be called at fixture boundaries.

### §AV-perf — performance budget revisit

Tier 1 budget is ~4.0 ms; Tier 2 is ~1.7 ms. AV.2 adds 3× the noise sampling (multi-column) — pre-AV.1 each fragment ran one 50-step march × 5-octave triangular noise; AV.2 runs three of those. Cost will be ~3×.

If profiling shows the cost exceeds budget:
1. **First fallback:** reduce march count 50 → 35. Same character; modest fidelity loss.
2. **Second fallback:** background column (depth=0.5) uses 4-octave noise instead of 5. The background is dimmed anyway; the fifth octave is barely visible.
3. **Third fallback:** drop to 2 columns (anchor + one offset). Lose some of the depth-parallax character.

Don't preemptively optimize. Run the shader as specified, measure, react if needed. **Profiling itself is AV.3 scope** — at AV.2, you only need to confirm the suite runs in reasonable time (no test-suite timeouts).

### §AV-routing-conflicts — Failed Approach #67 risk

FA #67: do not route the same audio timescale into two different visual layers. Audit:

| Visual layer | Audio primitive | Timescale |
|---|---|---|
| Multi-column foreground brightness | `f.bass_att_rel` | continuous, ~100 ms |
| Substrate drift speed | `f.bass_att_rel` | continuous, ~100 ms |
| Curtain kink | gated `stems.drums_energy_dev` | per-beat, accent |
| Palette phase (ribbon hue) | `stems.vocals_pitch_hz` | continuous, melody timescale |
| Palette phase (warm/cool) | `f.valence` | slow, song-section |
| Fold density | `f.mid_att_rel` | continuous, ~100 ms |
| Star twinkle | `f.beat_phase01` | per-beat, accent |

`f.bass_att_rel` drives TWO layers (brightness + drift speed). FA #67 calls this a risk pattern ("competing rhythms"). The design §5.7 specifies both — the question is whether they're at the same TIMESCALE.

Brightness breathing is amplitude (`0.85 + 0.30 * bassRel`); drift speed is rate (`spd = 0.06 + 0.04 * bassRel`). They're physically different parameters of the same musical input — analogous to "audio amplitude modulates both light intensity and a flame's flicker speed." Not necessarily a FA #67 violation, because the visual responses are distinct (brightness change is instant, drift speed change is integrated over time = ribbon moves faster).

**Default position:** ship both as designed; mid-session sanity check is whether the visual reads as "fighting itself" (FA #67 symptom). If it does, surface to Matt — likely fix is to drop the drift-speed route and keep only the brightness one.

### §AV-pitch-smoothing — vocal pitch smoothing source

The design §5.7 says "smoothed via 5-frame moving average." Implementation options:
- **CPU-side smoothing** — track a 5-frame ring buffer of `stems.vocals_pitch_hz`, pass the average through a uniform.
- **Use the `_smoothed` variant** if `Common.metal` exposes one (check `vocals_pitch_*_smoothed` — the MV-3 / DM.2 extension added smoothed proxies for some fields).
- **Per-frame shader-side IIR** — needs persistent state, same problem as the kink accumulator.

Recommended: check `Common.metal` for `vocals_pitch_*_smoothed` first. If not present, do CPU-side smoothing via the same `AuroraVeilState` class as the kink accumulator (path B).

---

## Stop and report instead of forging ahead when

Per CLAUDE.md Increment Completion Protocol:

- Any test fails that wasn't a documented flake (`MetadataPreFetcher.fetch_networkTimeout`, `SoakTestHarness.cancel`). Especially the AV.1 `AuroraVeilSilenceTest` — if it fails, the silence fallback is broken and must be fixed before continuing.
- `AuroraVeilPitchHueTest` produces stepwise hue migration even with 5-frame smoothing — likely `vocals_pitch_hz` is being read at low rate / coarse resolution; surface for engine investigation rather than tuning the smoothing window.
- The visual sanity check shows beat-coupled flashing (kink fires per-beat instead of slow 1–2 s shudder) — Failure Mode #11 triggered; the §3.2 rare-event gating is broken.
- Stem-warmup blend is missing on any `stems.*` read — D-019 violation; grep for `stems\.` in the diff to catch.
- The `beatMotion ≤ continuousMotion * 2 + 1` invariant fails (§AV-beatresp). Likely the kink amplitude is too high or the brightness breathing too low — surface the trade-off; the design's "continuous ≥ 10× accent" ratio is the load-bearing constraint.
- The multi-column work breaks the silence-stable rendering (silence test fails after multi-column lands). Surface — likely the noise samples at offset positions are interacting with the auroraEnv in unexpected ways.
- Performance regression so large it makes the test suite slow (multiple-minute regression on `PresetVisualReview`). Surface; §AV-perf fallback chain.

The cost of pausing is low. The cost of an increment that silently re-shapes scope is high.

---

## Commit cadence

Per CLAUDE.md, multiple small commits within the increment, message format `[AV.2] <component>: <description>`. Suggested boundaries:

1. `[AV.2] AuroraVeilState: CPU-side kink + pitch-smoothing class with GPU buffer` (if Path B — Gossamer-pattern state class with `tick(features:, stems:)`).
2. `[AV.2] AuroraVeil.metal: 3-column raymarch with depth-scale dimming + non-parallel drift velocities`.
3. `[AV.2] AuroraVeil.metal: continuous audio routes (bass brightness + drift speed, mid fold density, vocal-pitch + valence palette phase, beat-phase star twinkle)` — six continuous routes wired with D-019 blend.
4. `[AV.2] AuroraVeil.metal + mvWarp: kink accumulator → curtain kink (rare-event gated, 1–2 s damped)` — drum kink wired via AuroraVeilState.
5. `[AV.2] AuroraVeilContinuousDominanceTest: bass sweep + drum sweep dominance ratio`.
6. `[AV.2] AuroraVeilPitchHueTest: vocal-pitch sweep produces continuous monotonic hue migration`.
7. `[AV.2] PresetRegression: regen Aurora Veil golden hashes for audio-coupled state`.
8. `[AV.2] AuroraVeil.json: description + motion_intensity reflect audio-responsive state`.
9. `[AV.2] ENGINEERING_PLAN + RELEASE_NOTES: AV.2 ✅`.

Each commit should leave the repo in a buildable, testable state.

Push to remote only after Matt's explicit "yes, push" in chat. Local main commits stay local until then.

---

## Closeout report (at end of increment)

Per CLAUDE.md Increment Completion Protocol:

1. **Files changed** — concrete paths, new vs edited.
2. **Tests run** — suites, pass/fail counts, pre-existing flakes called out. Especially the two new tests' assertion-by-assertion outcomes.
3. **Visual harness output** — paths to the three `Aurora_Veil_*.png` files from `RENDER_VISUAL=1` plus a one-sentence assessment of each fixture's frame against the named references AND the 9-question authenticity rubric (mark each Q1–Q9 YES / NO / PARTIAL / N/A; explicitly note Q3 + Q7 status — AV.2 was supposed to close them).
4. **Documentation updates** — `ENGINEERING_PLAN.md` AV.2 flip + `RELEASE_NOTES_DEV.md` entry.
5. **Open-question outcomes** — explicit answers (or escalations) for §AV-kink, §AV-beatresp, §AV-perf, §AV-routing-conflicts, §AV-pitch-smoothing.
6. **Engineering plan updates** — flip Increment AV.2 status from ⏳ to ✅.
7. **Known risks and follow-ups** — anything deferred (especially AV.3 multi-timescale motion enrichment + Matt M7 cert).
8. **Git status** — branch, commit hashes, clean tree confirmation.

---

## Project context inherited from CLAUDE.md (read those entries directly; reinforced here)

- **D-026 deviation primitives.** Every primary driver uses `*_rel` / `*_dev`. No absolute thresholds. Grep should return zero `smoothstep(0.2x, 0.3x, f.bass)`-style patterns in the diff.
- **D-019 stem-warmup blend.** Every `stems.*` read blends through `smoothstep(0.02, 0.06, totalStemEnergy)` to a FeatureVector proxy. Five routes touch this: routes 1 (vocals pitch — uses `stems.vocals_pitch_hz` direct + confidence gate; no FV proxy possible, fall back to mid-palette 0.5 at low confidence), 2 (`f.bass_att_rel` ↔ `stems.bass_energy_rel`), 3 (`f.mid_att_rel` ↔ `stems.vocals_energy_rel`), 4 (same as route 2), 5 (`stems.drums_energy_dev` — no FV proxy; kink accumulator stays at 0 pre-warmup, that's the silence fallback).
- **Failed Approach #4: beat-dominant designs.** The drum kink amplitude must be dominated by the continuous primaries by ≥ 10× per design §5.7. `AuroraVeilContinuousDominanceTest` is the automated gate.
- **Failed Approach #31: absolute thresholds on AGC.** Every threshold is on `*_rel` or `*_dev`.
- **Failed Approach #33: free-running `sin(time)`.** The star twinkle uses `f.beat_phase01` (audio-anchored). The kink uses `kinkAccumulator` (audio-anchored). No `sin(time)` for primary motion anywhere new.
- **Failed Approach #63: read references' README; mid-session visual check is side-by-side comparison.** Don't self-judge "looks reasonable."
- **Failed Approach #67: one audio primitive per visual layer.** See §AV-routing-conflicts. `f.bass_att_rel` drives two layers — design accepts this; verify visually it doesn't read as "fighting itself."
- **D-067(b) lightweight rubric profile.** Aurora Veil is emission-only; M1 cascade + M3 material count gates do NOT apply. L1–L4 ladder applies.
- **Linear-RGB everywhere on the GPU side.**

---

## Why this matters

AV.2 is the increment that makes Aurora Veil a *music* visualizer. At AV.1 it renders aurora; at AV.2 it renders aurora *that listens.* The vocal-pitch palette migration is the single feature that separates this preset from every other "procedural aurora" demo on the web — it's the Sigur Rós-grade slow hue migration along the melody that gives the listener "this preset is responding to *this song*" rather than "this preset is a screensaver that happens to be playing while music is on."

The multi-column work closes the rubric Q3 / Q7 gaps from AV.1 (single-column couldn't produce vertical ray fine structure or off-axis composition). Together with the audio routing, AV.2 is the increment where the preset moves from "infrastructure demo" to "ready for AV.3 polish + M7 cert review."

**Estimated effort for AV.2 alone:** one session, ~3 hours including the visual sanity check + rubric pass. If §AV-kink splits AV.2 into AV.2a + AV.2b, ~1.5 hours each. AV.3 is a separate prompt to be authored after AV.2 ships.

Treat the visual mid-fixture sanity check + 9-question rubric pass as the load-bearing final gate **for AV.2**. Automated tests prove the routing produces the right *amplitudes*; they don't prove the result *feels musical*. Side-by-side comparison against ref `04` (multi-curtain parallax) + the rubric is the discriminator.
