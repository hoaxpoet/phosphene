# Visual References — Drift Motes

**Family:** particles (per D-067(b) lightweight-rubric particles bucket; same enum value as Murmuration)
**Render pipeline:** particle compute + sprite render + feedback (single-pass `["feedback", "particles"]`; mv_warp incompatible with particle systems per D-029)
**Rubric:** lightweight (per D-067(b) — particle systems are exempt from the §12.1 detail-cascade and §12.3 PBR-oriented traits)
**Last curated:** 2026-05-08

> **Architectural reminder.** Drift Motes is a particle system that is NOT a flock. Particles drift in a directional force field (wind + curl_noise turbulence) through a single dramatic god-ray light shaft. No cohesion, no alignment, no neighbor-seeking. The aesthetic is cinematographic — Roger Deakins interior dust shaft, late-afternoon beam through pine canopy, morning shaft through cathedral window. Murmuration is the catalog's flock; Drift Motes inverts that. The compute kernel is short; the compositing is well-defined; the audio routing is conventional. References below assume that target.

> **Visual target reframe (D-096).** All "must read as ..." acceptance gates below are aesthetic-family bars, not pixel-match contracts. A render that reads as belonging in the same visual conversation as the reference — real photographic god-ray with mote-laden volumetric — passes the gate. A render that reads like the called-out failure modes (flock repetition, generic particle.js dust demo, beat-pulsing motes) fails it. Pixel-fidelity to a particular reference image is an explicit non-goal. Real-time constraints (Tier 2 ~2.1 ms / Tier 1 ~1.6 ms p95) are inviolable.

## Reference images

Per `DRIFT_MOTES_DESIGN.md §2`, the design's default plan is to reuse a single image — the existing `07_atmosphere_dust_motes_light_shaft.jpg` from `docs/VISUAL_REFERENCES/arachne/` — without curating new images. The aesthetic is well-precedented in cinematography and the single reference covers shaft + mote-density + light-volume interaction in one frame. This README respects that plan: one image, renumbered to slot `01_` for this preset's hero role. Three optional follow-up references are documented in **Outstanding actions** below; commission them only if Session 1 visual review surfaces a need.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_atmosphere_dust_motes_light_shaft.jpg` | **Hero image — the only reference.** Wide forest light shaft with airborne motes drifting through a directional sun beam, multiple distinct shafts visible, particulate readable as discrete points scattering through each beam. The composition documents three traits simultaneously: (a) **shaft compositional anchor** — single dramatic beam at ~30° from vertical occupying the central frame, dark surround, beam volumetric clearly readable; (b) **mote density target** — particulates discrete and individually resolvable, not a smoke field; (c) **mote-shaft interaction** — motes inside the shaft volume read brighter than motes outside (the `DriftMotesShaftIntersectionTest` ≥ 1.5× brightness gate). The image's warm amber tone IS the target backdrop palette per design §5.4 (`top (0.05, 0.03, 0.02), bottom (0.10, 0.07, 0.04)`, valence-tinted) — the warmth is intentional for this preset, NOT a caveat to ignore. **Cross-preset reuse:** this same file exists at `docs/VISUAL_REFERENCES/arachne/07_atmosphere_dust_motes_light_shaft.jpg`, where it serves Arachne's atmosphere/light-shaft slot. There it carries a "use for mote density and beam structure ONLY, NOT palette" caveat because Arachne's palette is cool — for Drift Motes that caveat is reversed: the warm palette IS what we want. |

## Mandatory traits (lightweight rubric, per D-067(b))

The lightweight rubric ladder is L1–L4. For Drift Motes specifically:

- [ ] **L1 — Silence fallback.** At `totalStemEnergy == 0`, wind force at base level (0.3 magnitude), motes drift gently, emission rate at base (60/sec), shaft at base brightness, all motes inherit `default_warm_hue()`. Feedback trail decay continues. Form complexity ≥ 3 at silence (motes + shaft + fog gradient). The scene must be alive — shaft cuts the frame, motes drift, fog softly glows. Reference `01_atmosphere_dust_motes_light_shaft.jpg` for what the silence-state should evoke even without audio modulation.
- [ ] **L2 — Deviation primitives only (D-026).** Every primary driver uses `*_rel` or `*_dev`. No absolute thresholds — except the explicit `drums_energy_dev > 0.3` shock gate, which is a deviation-form threshold and therefore D-026 compliant (the threshold is on the *deviation*, not on raw amplitude). Verified by `FidelityRubricTests`.
- [ ] **L3 — Performance budget.** p95 ≤ Tier 2 ~2.1 ms / Tier 1 ~1.6 ms (per design §7). Verified by `PresetPerformanceTests` against silence / steady / beat-heavy fixtures.
- [ ] **L4 — Frame match.** Matt M7 review against `01_atmosphere_dust_motes_light_shaft.jpg` for shaft composition, mote density, and shaft-mote-interaction brightness ratio. Note the design doc rates L4 as "light, given optional curation" — depth of M7 review scales with reference set size.

Plus design-doc-specific must-haves (rooted in §3 trait matrix and §5 architecture):

- [ ] **Force-field motion, NOT flocking.** Particles do not seek each other. No cohesion, no alignment, no neighbor-checking. Motion = wind force + curl_noise turbulence + lifecycle recycle. Verified by `DriftMotesNonFlockTest` (200 frames; 50 random particle pairs; pairwise distance distribution does NOT contract).
- [ ] **Single dramatic light shaft.** `ls_shadow_march` from sun position `(2.5, 5.0, 1.0)` direction `(-0.4, -0.85, 0.0)`, cone half-angle ~12° (a wide beam, not a pencil). Without the shaft, motes lack compositional anchor — design §6 explicit failure mode. The shaft is half the preset.
- [ ] **Mote brightness modulated by shaft intersection.** Sprite brightness scaled by sampling shaft density at particle position. Particles inside shaft volume read ≥ 1.5× brighter than particles outside. Verified by `DriftMotesShaftIntersectionTest`.
- [ ] **Per-mote hue baked at emission time from `vocalsPitchNorm`.** When confidence > 0.4, hue derives from `log2(vocalsPitchHz / 80) / log2(10)` mapped through `hue_from_pitch()`; the hue persists for the mote's full life. The trail becomes a visual record of the melody, similar to Gossamer's wave hue baking. Pre-warmup, hue falls back to `default_warm_hue()`. Verified by `DriftMotesPitchHueBakeTest` (pitch sweep produces lockstep hue distribution shift with one-second lag for emission cadence).
- [ ] **Floor fog (`vol_density_height_fog`).** Without floor fog, scene reads as motes on void (design §6 failure mode). Fog is the ambient haze the shaft cuts through.
- [ ] **Feedback trail decay 0.92.** Short trails — motes leave faint streaks during fast wind, not persistent ribbons. `base_zoom = 0.0`, `base_rot = 0.0` (no global motion; pure trail decay).
- [ ] **No free-running `sin(time)` motion.** All oscillation must be audio-anchored or `curl_noise(p, time)`-driven. The `time` parameter inside `curl_noise` is a phase advance, not a visible oscillation (CLAUDE.md catalog-wide rule from Arachne tuning).

## Expected / strongly preferred traits

Lightweight presets are exempt from §12.2 (expected) and §12.3 (strongly preferred) per D-067(b). The full PBR-oriented traits (triplanar texturing, detail normals, hero specular, POM, thin-film, etc.) are inapplicable to an emission-only additive-blend particle preset.

**Optional preferences for Drift Motes specifically (not gated, not required):**

- Anticipatory shaft pulse on `f.beat_phase01` — `approachFrac × 0.05` brightness ramp adds subtle music-coupled motion to the shaft itself. Subtle is the operative word; obvious pulsing reads as EDM lighting cue (called out in §6 failure modes).
- `valence`-driven backdrop palette warm/cool shift — small phase offset on the warm-amber gradient so minor-key passages read cooler, major-key warmer. Range bounded by the design's `color_temperature_range: [0.55, 0.85]` (warm-biased; never goes fully cool).

## Anti-references — no curated images, six failure modes called out

Per design §6, all anti-references for Drift Motes are no-image failure modes. Each must be avoided through implementation discipline:

- **Murmuration repetition (flocking behavior).** The motion model must NOT exhibit any cohesion or alignment. Particles do not seek each other. If reviewers detect clustering or formation, the `curl_noise` turbulence must be re-tuned to dominate. Verified by `DriftMotesNonFlockTest`.
- **Generic dust shader.** Without the dramatic light shaft, motes lack compositional anchor. The shaft is half the preset; cutting it produces a flat dust field with no purpose. Verified by L4 review against the hero image.
- **Constant emission rate.** Looks lifeless. Emission must vary visibly with mids (`60 + 60 × f.mid_att_rel` particles/sec).
- **Motes don't catch the shaft.** If sprite brightness is constant regardless of shaft intersection, the shaft has no purpose. Brightness modulation by shaft-density sample at particle position is mandatory. Verified by `DriftMotesShaftIntersectionTest`.
- **Beat-pulsing motes.** Drum-coupled per-mote brightness flashing reads as EDM. Drum coupling is dispersion shock only — radial impulse on `drums_energy_dev > 0.3`, NOT per-mote brightness modulation.
- **Murky floor.** Without `vol_density_height_fog`, scene reads as motes on void. Floor fog is mandatory.

## Audio routing notes

Specific audio→visual mappings that must hold (per `DRIFT_MOTES_DESIGN.md §5.6`):

- **Continuous primary drivers** (deviation primitives, D-026): wind force magnitude ← `f.bass_att_rel` (wind vector magnitude `0.3 + 0.6 × x`); emission rate ← `f.mid_att_rel` (`60 + 60 × x` particles/sec); per-mote hue ← `stems.vocalsPitchNorm` baked at emission, gated by `vocalsPitchConfidence > 0.4`; light shaft density ← `f.mid_att_rel` (`0.6 + 0.4 × x`); backdrop palette warm/cool tint ← `f.valence`; shaft brightness ± 15% ← `f.bass_att_rel`.
- **Beat accents** (deviation primitives, D-026): dispersion shock ← `stems.drums_energy_dev` (radial impulse from shaft center, gated `dev > 0.3`, scaled `(dev − 0.3) × 1.2`); anticipatory shaft pulse ← `f.beat_phase01` approach curve (`approachFrac × 0.05` brightness ramp).
- **Stem warmup** (D-019): all `stems.*` reads must blend through `smoothstep(0.02, 0.06, totalStemEnergy)` to FeatureVector proxies. The first ~10 s of every track and all of ad-hoc mode must look correct without stems — pre-warmup, hue baking falls back to `default_warm_hue()`; dispersion shock disabled.
- **Structure stays solid** (D-020): shaft direction, sun position, fog parameters, feedback decay, particle count, lifetime distribution are all fixed in code or JSON. Audio modulates wind magnitude, emission rate, mote hue at emission, shaft density/brightness, backdrop tint, and dispersion impulse — **not** shaft direction, particle count, or lifecycle parameters.
- **Continuous-vs-accent ratio** (Audio Data Hierarchy): wind force base 0.3 with bass-coupled `+0.6 × x` continuous → max wind 0.9; shock impulse `1.2 × (dev_max ≈ 0.5) = 0.6` peak only above `dev > 0.3` threshold. Continuous wind force dominates the rare shock impulse by occurrence. Verified by `DriftMotesShockBoundsTest` (post-shock max particle velocity bounded; no runaway dispersion).

## Outstanding actions

- [ ] **Verify family enum.** Design §1.13 references `particles` as the family. Per the prior Crystalline Cavern conversation, `PresetCategory.swift` enum members are `waveform, fractal, geometric, particles, hypnotic, supernova, reaction, drawing, dancer, transition, abstract, fluid, instrument, organic`. Confirm `particles` is the value Murmuration uses (Drift Motes inherits Murmuration's family per design §1.13).
- [ ] **Re-validate `DriftMotes.json` schema** against `Gossamer.json` (the actual existing schema). Required fields per the prior Crystalline Cavern findings: `name` (not `id`), `description`, `author`, `duration`, `fragment_function`, `vertex_function`, `beat_source`, top-level `decay` (not nested `feedback` wrapper). The JSON template in `DRIFT_MOTES_DESIGN.md §10` was drafted before the real schema was confirmed; regenerate during Session 1.
- [ ] **`Particle` struct hue field verification.** Open question §11.1 in design doc — verify whether the existing `Particle.color` slot (4× Float32) can carry baked hue + saturation + value separately, or if it's a single packed RGBA. If single RGBA, may need a small struct extension (anticipate during Session 1; flag if 64-byte budget is tight).
- [ ] **Particle count tier scaling.** Open question §11.3 — 800/400 is proposed; may need 1000/500 if motes feel too sparse. Budget allows it (current Tier 2 estimate 2.1 ms vs ~5 ms tier ceiling). Defer to Session 1 visual review.
- [ ] **Shaft direction tunability.** Open question §11.4 — upper-left → lower-right at 30° from vertical is the proposed start. Should be a JSON-tunable scene parameter so direction can be iterated without code changes. Make sure `scene_lights[0].position` and an optional `shaft_direction` field are read from sidecar.
- [ ] **P1 enrichment refs (not blocking; commission only if Session 1 review surfaces a need):**
  - **God-ray hero shot.** A wider light shaft with motes drifting through it — cathedral or interior cinematography (e.g. Reims Cathedral, abandoned warehouse). Source if `01` reads too forest-specific and the implementation drifts toward woodland-only feel.
  - **Side-lit pollen.** Pollen field side-lit by low-angle sun, motes glowing against dark backdrop. Source if mote brightness/halo character at sprite render time reads wrong against `01`.
  - **Anti-reference: generic particle.js dust demo.** For documenting what we are NOT building. Source only if reviewers flag the rendered output as "looks like every JS demo from 2018."
- [ ] **M7 review pending** until Session 3 (per `DRIFT_MOTES_DESIGN.md §9`). `DriftMotes.json` `certified` stays `false` until that pass succeeds.

## Provenance

Curated by: Matt
Curation date: 2026-05-08

Image sources:

- `01_atmosphere_dust_motes_light_shaft.jpg` — **Cross-preset reuse from `docs/VISUAL_REFERENCES/arachne/07_atmosphere_dust_motes_light_shaft.jpg`.** Same file content; renumbered to `01_` for this preset's hero-anchor role. Original Unsplash source: photographer Johny Goerend, photo ID `x3WQMj5QkEE` (verify against Arachne's provenance entry — Arachne README records the original source). Unsplash License. The cross-preset reuse approach (per design §2 default plan) avoids duplicate curation effort and signals catalog-level coherence between Arachne's atmosphere slot and Drift Motes' hero anchor.

Unsplash License terms: free for commercial and non-commercial use, no attribution required but recommended. Recording attributions here protects future re-licensing audits.
