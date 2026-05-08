# Aurora Veil — Design

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

## 5. Rendering architecture

### 5.1 Pass structure

`passes: ["mv_warp"]`. The fragment shader (the preset's `aurora_fragment` function) is invoked by the mv_warp scene draw; output goes to `warpState.sceneTexture`; the warp pass then performs its 32×24 vertex grid per-pixel feedback and presents to drawable.

### 5.2 Scene composition

Fragment shader builds the frame in three layers, back to front:

**1. Sky.** Vertical gradient: top `(0.005, 0.005, 0.02)` (deep night), bottom `(0.01, 0.015, 0.04)` (slightly warmer near horizon). Stars: sparse pinpoints from `hash_f01_2(uv * 800)` thresholded > 0.997, brightness modulated by another hash for variety.

**2. Curtain layer (3 ribbons).** Each ribbon `i ∈ {0, 1, 2}` has center-line:

```metal
float xc(float y, int i) {
    return 0.5 + 0.15 * (i - 1)
         + 0.08 * warped_fbm(float3(y * 1.5 + i * 7.0, time * 0.04, 0.0));
}
```

Ribbon width is feathered at top and bottom and varies along y:

```metal
float width(float y, int i) {
    return baseWidth
         * smoothstep(0.0, 0.15, y)
         * smoothstep(1.0, 0.85, y)
         * (0.7 + 0.3 * fbm4(float2(y * 4.0 + i * 3.0, time * 0.06)));
}
```

Ribbon brightness: `1 - smoothstep(0, width(y), abs(uv.x - xc(y, i)))`, further multiplied by:

- **Vertical ray detail:** `0.5 + 0.5 * fbm4(float2(uv.x * 80 + raysPhase[i], y * 4))` where `raysPhase[i] += dt * (0.3 + bass_att_rel * 0.5)`.
- **Fold modulation:** `0.6 + 0.4 * sin(uv.y * (8 + 4 * mid_att_rel) + foldPhase[i])`.
- **Ribbon-specific depth dim:** `depthScale[i] ∈ {1.0, 0.7, 0.5}`.

**3. Hue stratification (per ribbon).** Sample IQ cosine palette with `t = uv.y + pitchHue` where `pitchHue ∈ [0, 1]` is sampled from the live `vocalsPitchNorm` SpectralHistoryBuffer position. Palette constants tuned to real aurora colors: low-y → green `(0.0, 1.0, 0.4)`, mid-y → cyan-green, high-y → magenta `(0.9, 0.3, 0.7)`. When pitch confidence is low, fall back to fixed hue stratification (no per-frame hue movement).

Final color: `sky + Σ_i ribbon_color[i] * ribbon_brightness[i] * depthScale[i]`.

### 5.3 mv_warp specifics

- Per-frame: `baseRot = 0.0008 + valence * 0.0004` (slow rotation), `baseZoom = 0.0015` (slight inward drift), `decay = 0.945`.
- Per-vertex: UV displacement `disp = curl_noise(float3(uv * 2.0, time * 0.1)).xy * 0.005`. Audio-modulated component: `disp += float2(0, drums_energy_dev * 0.003 * sin(uv.x * 12))` — the y-offset on drums creates the characteristic aurora curtain "kink."
- Decay 0.945 is shorter than Gossamer's 0.955 (less echo) but longer than Starburst's pre-revert 0.97 (we don't want full smear). Curtains should leave a faint trail when they shift, not a smear.

### 5.4 Lighting / atmosphere

None. Emission-only. Sky color provides ambient floor. The curtain is the light source for compositional purposes.

### 5.5 State

No CPU-side state. All evolution is mv_warp-accumulated. `raysPhase[i]` and `foldPhase[i]` accumulate from `time` inside the fragment using `float(time * coefficient + i * offset)` — they're not persisted between frames since mv_warp handles temporal continuity.

### 5.6 Audio routing

| Driver | Source | Effect | Continuous/accent |
|---|---|---|---|
| Hue along ribbon | `vocalsPitchNorm` (SpectralHistoryBuffer[1920..]) | Per-y offset into IQ cosine palette | continuous |
| Brightness breathing | `f.bass_att_rel` | All-ribbon brightness scale (0.85 + 0.30 × x) | continuous |
| Fold density | `f.mid_att_rel` | Multiplier on uv.y fold frequency | continuous |
| Vertical ray phase advance | `f.bass_att_rel` | Accumulator rate | continuous |
| Curtain kink | `stems.drums_energy_dev` | mv_warp y-displacement amplitude | accent |
| Palette warm/cool | `f.valence` | IQ cosine palette phase shift | continuous |
| Star twinkle | `f.beat_phase01` | Per-star brightness modulation gated by `pitchConfidence > 0.5` | accent (subtle) |

**D-026 compliance:** every primary driver uses `*_rel` or `*_dev`. No absolute thresholds.

**D-019 compliance:** stem reads gated through `smoothstep(0.02, 0.06, totalStemEnergy)` warmup blend; FeatureVector beat_drums fallback used pre-warmup.

**Continuous-vs-accent ratio:** brightness breathing amplitude 0.30; curtain kink amplitude 0.003 UV. Continuous primary drivers dominate by >10× — well clear of the 2× minimum.

### 5.7 Silence fallback

At `totalStemEnergy = 0` and zero deviation, ribbons remain at base brightness (0.85), folds are static, mv_warp continues to accumulate slow rotation. Curtains drift visually with their warped_fbm center-line motion. Stars twinkle faintly via blue_noise temporal index. Silence is meditative, not dead.

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
2. **Per-frame palette modulation rate.** Initial proposal sets pitch-hue update at the per-frame SpectralHistoryBuffer read rate. If hue shifts feel jittery on rapid melodic phrases, switch to a 5-frame smoothing window.
3. **Star count.** 800-density (`hash > 0.997`) is the proposed start. May increase if ribbons feel isolated against sky.
