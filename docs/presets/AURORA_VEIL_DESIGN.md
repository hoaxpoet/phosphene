# Aurora Veil — Design

> **Amendment 2026-05-18: rendering architecture pivot.** Pre-implementation desk research surfaced three convergent authoritative prior-art references (nimitz "Auroras" / Lawlor & Genetti 2011 / Wittens NeverSeenTheSky) and a 15-mode failure-mode taxonomy. The original §5 specified a 2D pixel-shader "ribbon with horizontal proximity test against a `warped_fbm` centre-line + vertical fbm rays" — structurally distinct from every photographically-credible procedural aurora in the wild, and exposed to at least four named failure modes (#3, #9, #13, missing multi-timescale motion). §5 has been rewritten around the **volumetric-raymarch recipe**: per-pixel raymarch up a vertical column, triangular domain-warped noise (`triNoise2d`-style) sampled at each step, running-average vertical smear, per-march-step IQ-cosine palette cycling for Lawlor-Genetti height-curve stratification, mv_warp for substrate temporal compounding. Original §5 preserved verbatim in §5-LEGACY at end-of-doc for the iteration history. Research dossier: `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` (READ FIRST — load-bearing for the architectural rationale and the 9-question authenticity rubric used at AV.3 cert).

A direct-fragment + `mv_warp` preset rendering an aurora curtain over a faintly-starred night sky. Lowest-barrier authoring example in Phosphene's catalog: no SDF, no PBR, no mesh shader. Demonstrates the canonical Milkdrop pattern (direct fragment + per-vertex feedback warp) which currently has no consumer in the catalog.

## 1. Intent

A real aurora moves slowly. A real aurora is *colored* — green at the base, magenta at the crown, occasionally blue at low altitude — never uniformly neon. A real aurora has *structure* — folds, curtains, shimmering rays — at multiple scales. A real aurora is photographable in a way that no shader has authentically reproduced because every shader-aurora skips the slow-motion compounding that makes real ones feel alive.

Aurora Veil's job is to be the catalog's "ambient ribbon" preset — what plays during quiet listening, low-energy passages, the comedown after a peak. It pairs with Membrane and Gossamer in the Orchestrator's ambient-section bench.

**Audio summary.** Vocals pitch shifts hue along the ribbon length (the SpectralHistoryBuffer trail makes this trivial); `bass_att_rel` breathes brightness; `mid_att_rel` modulates fold density; `drums_energy_dev` kinks the curtain on accents; valence shifts the green/blue/magenta mix.

**Family.** `fluid` (ribbon dynamics; reuses the family-repeat penalty against Membrane / FerrofluidOcean / VolumetricLithograph). _Confirm enum value during sidecar writing._

**Render passes.** `["mv_warp"]` — direct fragment shader runs inside the warp-pass scene draw; mv_warp handles drawable presentation.

## 2. References

**Recommendation: curate.** Aurora has very specific real-world signatures that procedural shaders routinely miss; references are the difference between authentic aurora and "neon ribbon shader." Suggested images:

- **Curtain hero shot.** Auroral curtain over a dark landscape, full vertical structure visible (green base + pink/magenta crown + ray structure). E.g., Iceland or Yukon photography.
- **Color stratification close-up.** A frame where the green-to-magenta vertical gradient is unambiguous.
- **Multi-curtain composition.** Two or more overlapping curtains with parallax — the layered-ribbon target.
- **Fold detail.** A single curtain section with the meso-scale fold structure (the "drape" pattern) clearly visible.
- **Anti-reference: neon EDM aurora.** A festival-visual or Tron-style "aurora" so the contrast is documented.

The existing `15_atmosphere_aurora_forest.jpg` in `docs/VISUAL_REFERENCES/arachne/` is a usable starting point but it's a foreground-trees-with-aurora-backdrop composition; we want hero-aurora frames where the curtain fills frame.

## 3. Trait matrix

| Scale | Trait |
|---|---|
| **Macro** | One to three vertical curtain ribbons spanning frame height. Ribbons curve gently along x; vertical extent tapers at top and bottom. |
| **Meso** | Per-ribbon fold structure: 4-8 folds along x, fold density modulated by `mid_att_rel`. Fold sharpness varies. |
| **Micro** | Vertical "ray" striations within each curtain — fine pillars that read as the discrete electron-precipitation columns of real aurora. |
| **Specular breakup** | Per-pixel brightness variation via `blue_noise_sample` for grain; smooth temporal accumulation via mv_warp masks the noise into shimmer rather than sizzle. |
| **Material** | Emission-only. No PBR. Lightweight rubric profile per D-067(b). |
| **Lighting** | None directly. The curtain *is* a light source. Sky glow falls off radially from the brightest ribbon section. Faint ambient sky color underlies everything. |
| **Motion** | mv_warp slow rotation + slow zoom; ribbon center-line shifts via low-frequency `warped_fbm`; vertical ray phase advances with continuous `bass_att_rel`. No free-running `sin(time)` (CLAUDE.md Arachne tuning rule). |
| **Audio reactivity** | See §5.6. |

## 4. Renderer capability audit

| Need | Available? | Notes |
|---|---|---|
| Direct fragment pipeline | ✓ | Plasma / Nebula / Waveform / Gossamer use it. |
| `mv_warp` pass | ✓ | D-027; Gossamer is current consumer. |
| `warped_fbm`, `curl_noise` | ✓ | V.1 noise utility tree. |
| `blue_noise_sample` for grain | ✓ | Noise/BlueNoise.metal. |
| `palette_cool` / IQ cosine palette | ✓ | Color/Palettes.metal (V.3). |
| `SpectralHistoryBuffer` for pitch trail | ✓ | buffer(5), 480 samples of `vocalsPitchNorm` at offset [1920..2399]. |
| Hash-based starfield | ✓ | `hash_f01_2` from Noise/Hash.metal. |

**No blocking gaps.** This preset uses only existing utilities — that's the point of picking it as the entry-level demonstration. No engine work required.

## 5. Rendering architecture (amended 2026-05-18)

**Architectural prior art (READ THESE FIRST).** Three convergent references from the 2026-05-18 desk research dossier (`AURORA_VEIL_RESEARCH_2026-05-18.md`):

1. **nimitz "Auroras" (Shadertoy XtGGRt, 2017)** — the canonical procedural-aurora recipe. Triangular domain-warped noise + 50-step volumetric raymarch + running-average smear + per-march-step palette cycling. Phosphene's recipe is a clean-room MSL reimplementation of this algorithm (Shadertoy source is CC-BY-NC-SA, incompatible with MIT; algorithms aren't copyrightable, code is).
2. **Lawlor & Genetti, *Interactive Volume Rendering Aurora on the GPU* (WSCG 2011)** — the physical anchor. `emission = H(altitude) × F(x, y)` factorization: 1D height curve × 2D electron-flux footprint. nimitz's per-march-step palette IS the Lawlor `H(z)` curve; `triNoise2d` IS the Lawlor `F(x, y)`.
3. **Wittens NeverSeenTheSky (2013)** — the motion reference. Real aurora motion is curling vortical, not pan-the-noise-coordinate. We borrow curl-noise advection (cheap) without paying the full fluid-solver cost (expensive).

### 5.1 Pass structure

`passes: ["mv_warp"]`. The fragment shader (`aurora_fragment`) is invoked by the mv_warp scene draw; output goes to `warpState.sceneTexture`; the warp pass then performs its 32×24 vertex-grid per-pixel feedback and presents to drawable.

### 5.2 Scene composition

Three layers, back to front:

**1. Sky.** Vertical gradient: top `(0.005, 0.005, 0.02)` (deep night), bottom `(0.01, 0.015, 0.04)` (slightly warmer near horizon). Sparse stars from `hash_f01_2(uv * 800) > 0.997`, brightness varied by a secondary hash. **Additive composite**, so stars punch through aurora (Failure Mode #5 avoided).

**2. Aurora — volumetric vertical-column raymarch.** Per fragment, march 50 steps up an implicit vertical "column" rooted at the fragment's screen position. At each step `i ∈ [0, 50)`:

```metal
// Polynomial step distance — dense near bottom, coarse near top.
// (Adapted from nimitz; concentrates samples where stratification is sharpest.)
float pt = 0.8 + pow(float(i), 1.4) * 0.002;

// March position in "world" (column space). uv.x = horizontal in frame; pt = altitude.
float2 marchPos = float2(uv.x, pt);

// Sample the 2D ribbon-shape field (triangular domain-warped noise).
float rzt = tri_noise_2d(marchPos, 0.06 /* drift speed */);

// Per-march-step palette cycle (the Lawlor H(z) height curve).
// sin(...) advances with i, so green sits at low-i, magenta at high-i.
float3 col2 = (sin(1.0 - float3(2.15, -0.5, 1.2) + float(i) * 0.043) * 0.5 + 0.5) * rzt;

// Running-average smear — converts vertical noise samples into vertical ribbons.
// Without this line, the result reads as volumetric salt-and-pepper; with it,
// adjacent altitudes blur into coherent vertical streaks. Load-bearing.
avgCol = mix(avgCol, float4(col2, rzt), 0.5);

// Exponential decay accumulator — early (low-altitude) samples contribute most.
col += avgCol * exp2(-float(i) * 0.065 - 2.5) * smoothstep(0.0, 5.0, float(i));
```

Final aurora colour `col * 1.8` (modest gain); the IQ-cosine sin() produces values in `[0, 1]` per channel, so the accumulator stays within reasonable HDR range.

**Triangular domain-warped noise `tri_noise_2d` — clean-room MSL.** Five iterations of:
- triangular waveform `tri(x) = clamp(abs(fract(x) - 0.5), 0.01, 0.49)` (sharp ribbon edges; Perlin is too blurry);
- 2D triangle noise `tri2(p) = float2(tri(p.x) + tri(p.y), tri(p.y + tri(p.x)))`;
- per-octave rotation `mm2(time * spd)` for biological asymmetry across the frame;
- per-octave domain warp `p -= dg / z2` with `z2 *= 0.45` decay;
- final return `clamp(1.0 / pow(rz * 29.0, 1.3), 0, 0.55)`.

Algorithm exposure in `AURORA_VEIL_RESEARCH_2026-05-18.md §1.1`. Implementer reimplements from the description, citing nimitz + Lawlor in the shader header. **Do NOT substitute the engine's existing `fbm8` for `tri_noise_2d`** — Perlin-derived smoothed octaves produce fog-like blurry ribbons (Failure Mode #8); the triangular waveform is what gives aurora its sharp edges.

**3. Composite.** `final = sky + aurora`. Additive only. Foreground is sky-context dark, not aurora-lit (Failure Modes #5, #14, #15 avoided).

### 5.3 mv_warp specifics

- Per-frame: `baseRot = 0.0008 + valence * 0.0004` (slow rotation), `baseZoom = 0.0015` (slight inward drift), `decay = 0.945`.
- Per-vertex: UV displacement `disp = curl_noise(float3(uv * 2.0, time * 0.1)).xy * 0.005`. The curl-noise advection (rather than straight time-pan) mimics NeverSeenTheSky's vortical-flow signature without paying the fluid-solver cost.
- Audio-modulated component (rare-event gated, see §5.6): `disp += float2(0, kinkAccumulator * 0.003 * sin(uv.x * 12))`. **`kinkAccumulator` is NOT raw `drums_energy_dev`** — see §5.6 for the gating + damped-response form.
- Decay 0.945: shorter than Gossamer's 0.955 (less echo) but long enough to give the substrate a 1-second persistence trail.

### 5.4 Multi-timescale motion (Failure Mode #4 mitigation — non-negotiable)

Real aurora moves on **four separable timescales** (research §2.1). Phosphene's mechanism per scale:

| Timescale | What moves | Phosphene mechanism |
|---|---|---|
| **Minutes (substorm advance)** | Whole-hemisphere brightening | Not modelled at AV (we render ~30s panels); future increment if needed |
| **Tens of seconds (substrate drift)** | Curtain undulation, ribbon-shape evolution | `tri_noise_2d` time argument at `spd = 0.06`; mv_warp `decay = 0.945` |
| **2–20 seconds (whole-curtain pulsation)** | Brightness pulses | `aurora *= 0.85 + 0.15 * fbm2(float2(time * 0.1, 0.0))` — slow envelope multiplier on the entire raymarch result |
| **0.1–0.2 s (5–10 Hz ray flicker)** | Per-ray local brightness flicker in bright pillars | `rzt *= 1.0 + 0.10 * fbm2(float2(uv.x * 4.0, time * 8.0))` — subsecond modulation at the per-march-step density level. **AV.3 polish, not AV.1.** |

AV.1 implements substrate-drift + mv_warp only. AV.2 adds the audio-coupled enrichment. AV.3 adds the 2–20 s pulsation envelope + the sub-second flicker.

### 5.5 Composition (Failure Modes #9 + #12 mitigation)

- **Off-axis bias.** The implicit column position is `uv.x` directly (no centre-line offset), but the `tri_noise_2d` field's biological asymmetry produces brightness concentrations off-axis by construction. No additional bias needed — but at AV.2, the second + third ribbons land at `uv.x + offset` with the offsets picked off-thirds (e.g. `0.27`, `-0.18`) rather than symmetric.
- **Dark sky context.** Sky gradient peaks at `(0.01, 0.015, 0.04)` — near-black. Aurora is the only chromatic emission in frame. No daytime / sunset / twilight contexts.
- **Soft top, sharp bottom (Failure Mode #13 mitigation).** The polynomial step distance `0.8 + pow(i, 1.4) * 0.002` + the exponential decay `exp2(-i * 0.065 - 2.5)` together produce a denser, brighter accumulation near low altitude and a soft fade at high altitude. The bottom is sharp (lots of bright samples accumulated quickly); the top dissolves (decay dominates). Physically correct.

### 5.6 State

No CPU-side state. All evolution is mv_warp-accumulated + per-frame triangular-noise sample.

**Audio-driven accumulators (introduced at AV.2, not AV.1):**

- **`kinkAccumulator`** (rare-event gated, damped response). Initialised at `0.0`. Updated each frame: `kinkAccumulator = max(kinkAccumulator * 0.93, drums_energy_dev * smoothstep(0.4, 0.7, drums_energy_dev))`. Decays at ~0.5/second; charges only on rare high-amplitude drum events. The visual response is a 1–2 s slow shudder, not a sharp instantaneous deflection. **Mandatory mitigation for Failure Mode #11 (festival-strobe).**
- **`pulseEnvelope`** (continuous, multi-second). Smoothed `fbm2(time * 0.1)` per §5.4; precomputed at the mv_warp `q1`/`q2` register or evaluated per-frame in fragment.

### 5.7 Audio routing (amended 2026-05-18)

| Driver | Source | Effect | Continuous/accent |
|---|---|---|---|
| Hue along ribbon | `stems.vocals_pitch_hz` + `vocals_pitch_confidence` (MV-3c, normalized) | Per-march-step palette phase offset; smoothed via 5-frame moving average | continuous |
| Brightness breathing | `f.bass_att_rel` | Aurora overall scale `(0.85 + 0.30 × x)` | continuous |
| Fold density / curtain texture | `f.mid_att_rel` | Multiplies `tri_noise_2d` spatial frequency: `tri_noise_2d(marchPos * (1.0 + 0.3 * f.mid_att_rel), spd)` | continuous |
| Substrate drift speed | `f.bass_att_rel` | `tri_noise_2d` spd argument: `spd = 0.06 + 0.04 * f.bass_att_rel` | continuous |
| Curtain kink | `kinkAccumulator` (gated on `stems.drums_energy_dev`) | mv_warp y-displacement amplitude | accent (rare-event, damped) |
| Palette warm/cool | `f.valence` | Per-march-step palette phase additive offset (`+0.1 * f.valence`) | continuous |
| Star twinkle | `f.beat_phase01` (gated by `vocalsPitchConfidence > 0.5`) | Per-star brightness modulation, subtle | accent |

**Vocals-pitch sourcing (research §3.3).** The original spec referenced `SpectralHistoryBuffer[1920..]` which is `offsetBarPhase`, not vocal pitch. Resolution: read `stems.vocals_pitch_hz` + `stems.vocals_pitch_confidence` directly. Normalize: `vocalsPitchNorm = clamp(log2(pitch_hz / 80.0) / 4.0, 0, 1)` (E2 ≈ 80 Hz → 0, C7 ≈ 2093 Hz → ~1). Pre-pitch-detection or low-confidence fallback: `vocalsPitchNorm = 0.5` (mid-palette neutral).

**D-026 compliance:** every primary driver uses `*_rel` or `*_dev`. No absolute thresholds.

**D-019 compliance:** stem reads gated through `smoothstep(0.02, 0.06, totalStemEnergy)` warmup blend; FeatureVector proxy used pre-warmup.

**Continuous-vs-accent ratio:** brightness breathing amplitude 0.30; curtain kink amplitude 0.003 UV × `kinkAccumulator` (peak ~0.3 on rare events). Continuous primary drivers dominate by ≥ 10× at all times. The gated kink doubles the dominance margin vs the original spec.

### 5.8 Silence fallback

At `totalStemEnergy = 0` and zero deviation: aurora renders at base brightness (0.85 × 1.0 = 0.85 effective gain); `tri_noise_2d` drifts at base `spd = 0.06`; `kinkAccumulator` decays to zero; pulsing envelope continues at its `fbm2(time * 0.1)` baseline (no audio coupling). Curtains drift visually with the noise field's slow evolution. Stars are static (no twinkle without beat phase). Silence is meditative, not dead — form complexity ≥ 2 (sky + stars + drifting aurora column).

### 5.9 Lighting / atmosphere

None. Emission-only. Sky colour provides the ambient floor. The aurora is the light source for compositional purposes; no Cook-Torrance dispatch, no IBL ambient, no shadow casting.

## 6. Anti-references and failure modes

- **"Neon ribbon shader."** Saturated pink/cyan with no green base, no stratification. Demoscene aurora.
- **"Festival visual."** Beat-flashing aurora that pulses to every kick. Beat must be accent-only.
- **"Single solid ribbon."** Without 2-3 layered ribbons with parallax, the depth of real aurora is lost.
- **"Free-running sin oscillation."** Per CLAUDE.md rule from Arachne tuning: never use `sin(time)` for primary motion. All oscillation must be audio-anchored or mv_warp-driven.
- **"Procedural night sky."** A noise-based sky pattern is wrong — real aurora night sky is mostly black with sparse stars.

## 7. Performance budget

- **Tier 1 (M1/M2):** Fragment ~3.5 ms (3 ribbons × warped_fbm × vertical-ray fbm4 × palette evaluations) + mv_warp grid ~0.4 ms = ~4.0 ms total.
- **Tier 2 (M3+):** ~1.7 ms total.

`complexity_cost: {"tier1": 4.0, "tier2": 1.7}`. Well within both tier budgets.

## 8. Acceptance criteria

**Rubric profile: lightweight** (D-067(b)) — emission-only direct-fragment plasma-family preset, exempt from M1 detail cascade and M3 material count requirements.

- **L1 (silence):** Curtains drift, ribbons remain at base brightness, mv_warp accumulates rotation. Form complexity ≥ 2 at silence (multi-ribbon + stars + sky).
- **L2 (deviation primitives):** All audio routing uses `*_rel` / `*_dev` per D-026. Verified by `FidelityRubricTests`.
- **L3 (perf):** p95 ≤ tier budget. Verified by `PresetPerformanceTests`.
- **L4 (frame match):** Matt M7 review against curated references.

**Preset-specific tests:**

1. `AuroraVeilSilenceTest` — render at zero audio, assert non-black, assert ≥3 distinct ribbons by horizontal slice luma analysis.
2. `AuroraVeilPitchHueTest` — render with `vocalsPitchNorm` swept low→high; assert ribbon hue shifts continuously (not stepwise).
3. `AuroraVeilContinuousDominanceTest` — render with zero `drums_energy_dev` and rising `bass_att_rel`; assert frame max-luma scales with `bass_att_rel` by ≥ 0.2 amplitude. Validates continuous primary driver actually dominates.

## 9. Implementation phases

**Session 1 — Single-ribbon foundation.** Sky + stars + one ribbon with center-line `warped_fbm` + vertical rays + IQ cosine palette stratification. mv_warp wired with conservative parameters. Silence test passes.

**Session 2 — Multi-ribbon with parallax + audio.** Add ribbons 2 and 3 with depth scaling. Wire all audio routes per §5.6. Continuous-dominance test passes.

**Session 3 — Refine + cert.** Tune palette constants, mv_warp amplitudes, fold density coefficients against curated reference frames. Pitch-hue test passes. Performance profile run. Matt M7 review.

**Estimated: 3 sessions.**

## 10. JSON sidecar template

```json
{
  "id": "aurora_veil",
  "family": "fluid",
  "passes": ["mv_warp"],
  "tags": ["aurora", "ambient", "ribbon", "atmospheric"],
  "feedback": {
    "decay": 0.945,
    "base_zoom": 0.0015,
    "base_rot": 0.0008,
    "beat_zoom": 0.0,
    "beat_rot": 0.0,
    "beat_sensitivity": 0.0
  },
  "stem_affinity": {
    "vocals": "ribbon_hue",
    "drums": "curtain_kink",
    "bass": "brightness_breath",
    "other": null
  },
  "visual_density": 0.4,
  "motion_intensity": 0.25,
  "color_temperature_range": [0.15, 0.55],
  "fatigue_risk": "low",
  "transition_affordances": ["crossfade", "morph"],
  "section_suitability": ["ambient", "comedown", "bridge"],
  "complexity_cost": { "tier1": 4.0, "tier2": 1.7 },
  "certified": false,
  "rubric_profile": "lightweight",
  "rubric_hints": {}
}
```

## 11. Open questions

1. **Family enum value.** Confirm `fluid` is the intended family — alternative is to coin `atmospheric` if a category for aurora/sky/cloud presets is appropriate longer-term. (Affects family-repeat scoring.)
2. **~~Per-frame palette modulation rate~~** *(resolved by 2026-05-18 amendment)*. Vocals pitch now sourced from `stems.vocals_pitch_hz` + 5-frame moving average per §5.7; not from `SpectralHistoryBuffer[1920..]` (which was bar phase, not pitch).
3. **Star count.** 800-density (`hash > 0.997`) is the proposed start. May increase if ribbons feel isolated against sky.
4. *(new, 2026-05-18)* **`tri_noise_2d` performance budget.** The clean-room MSL reimplementation needs profiling against the Tier-1 4.0 ms / Tier-2 1.7 ms budget per §7. If 50-step march × 5-octave triangular noise overshoots, fallback options in priority order: drop march to 40 steps; reduce noise octaves 5 → 4; final fallback to Roy Theunissen's "difference of two Perlins, take abs()" baseline (lower fidelity ceiling, cited in research dossier §1.4).

---

## 5-LEGACY (original §5, archived 2026-05-18)

Preserved for iteration history. The 2026-05-18 amendment pivoted §5 to the volumetric-raymarch recipe per `AURORA_VEIL_RESEARCH_2026-05-18.md`. The pre-amendment §5 specified a 2D pixel-shader ribbon with horizontal proximity test against a `warped_fbm` centre-line — structurally distinct from every photographically-credible procedural aurora in the wild, and exposed to Failure Modes #3 (horizontal wave bands, no vertical extent), #9 (symmetric centered composition), #13 (hard-edged top AND bottom), plus missing multi-timescale motion mechanisms entirely. The legacy spec is NOT the implementation target; it's preserved here so the rationale for the amendment is visible in one place.

### Legacy §5.1 — Pass structure (unchanged in amendment)

`passes: ["mv_warp"]`. The fragment shader (`aurora_fragment`) is invoked by the mv_warp scene draw; output goes to `warpState.sceneTexture`; the warp pass then performs its 32×24 vertex grid per-pixel feedback and presents to drawable.

### Legacy §5.2 — Scene composition (SUPERSEDED — see new §5.2 above)

Fragment shader built the frame in three layers, back to front:

**1. Sky.** Vertical gradient: top `(0.005, 0.005, 0.02)` (deep night), bottom `(0.01, 0.015, 0.04)` (slightly warmer near horizon). Stars: sparse pinpoints from `hash_f01_2(uv * 800)` thresholded > 0.997, brightness modulated by another hash for variety. *(Retained verbatim in amendment.)*

**2. Curtain layer (3 ribbons).** Each ribbon `i ∈ {0, 1, 2}` has center-line:

```metal
float xc(float y, int i) {
    return 0.5 + 0.15 * (i - 1)
         + 0.08 * warped_fbm(float3(y * 1.5 + i * 7.0, time * 0.04, 0.0));
}
```

Ribbon width feathered at top and bottom, varying along y:

```metal
float width(float y, int i) {
    return baseWidth
         * smoothstep(0.0, 0.15, y)
         * smoothstep(1.0, 0.85, y)
         * (0.7 + 0.3 * fbm4(float2(y * 4.0 + i * 3.0, time * 0.06)));
}
```

Ribbon brightness: `1 - smoothstep(0, width(y), abs(uv.x - xc(y, i)))`, multiplied by vertical-ray detail + fold modulation + depth-scale. *(SUPERSEDED — see new §5.2 volumetric raymarch.)*

**3. Hue stratification.** Sample IQ cosine palette with `t = uv.y + pitchHue` where `pitchHue` was incorrectly sourced from `SpectralHistoryBuffer[1920..]` (that offset is bar phase, not vocal pitch — discovered during 2026-05-18 desk research). *(SUPERSEDED — palette now indexed by march-step / world-y per Lawlor-Genetti factorization, hue sourced from `stems.vocals_pitch_hz`.)*

### Legacy §5.3 — mv_warp specifics (retained substantially unchanged)

Per-frame: `baseRot = 0.0008 + valence * 0.0004`, `baseZoom = 0.0015`, `decay = 0.945`. Per-vertex: UV displacement `curl_noise(...).xy * 0.005` plus drum-coupled y-displacement. *(See new §5.3 for the amended `kinkAccumulator` rare-event-gated form.)*

### Legacy §5.6 — Audio routing table (SUPERSEDED — see new §5.7)

The legacy table routed `vocalsPitchNorm` from a non-existent buffer offset (resolved: stems direct) and routed `drums_energy_dev` directly to mv_warp displacement (resolved: rare-event-gated `kinkAccumulator` with damped response — without this, the preset becomes EDM festival per Failure Mode #11).

### Legacy §5.7 — Silence fallback (substantively unchanged, see new §5.8)

At silence, ribbons remained at base brightness, folds static, mv_warp continued slow rotation. Curtains drifted via `warped_fbm` centre-line motion. Stars twinkled faintly via blue_noise temporal index.
