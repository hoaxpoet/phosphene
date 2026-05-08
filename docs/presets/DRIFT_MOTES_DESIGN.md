# Drift Motes — Design

A particle preset that is not a flock. Pollen and dust drift in a directional force field through a single dramatic god-ray light shaft. Demonstrates the `Volume/LightShafts.metal` and `vol_density_height_fog` utilities (currently underused) and gives the catalog a true ambient-section-floor preset — purpose-built for the quiet-passage linger that the existing 14 presets don't squarely address.

## 1. Intent

Murmuration is the catalog's only particle preset, and it is a flocking simulation — particles seeking each other in tight formation. Drift Motes inverts that: particles do not seek, they drift. Wind blows. Sun catches them as they cross a beam. Bass gusts; vocals tint individual motes with the pitch of the moment they were emitted; drums occasionally disperse the field with a soft shock. The aesthetic is cinematographic — the dust shaft from a Roger Deakins interior, the late-afternoon shaft through pine canopy, the morning beam through a cathedral window. It pairs with Aurora Veil and Membrane in the Orchestrator's ambient bench.

The third pick of this trio also serves as a clear collaborator onramp: *here is how to author a particle system in Phosphene without committing to a flock simulation*. The compute kernel is short; the compositing is well-defined; the audio routing is conventional.

**Audio summary.** `bass_att_rel` modulates wind force gust strength (continuous primary); `mid_att_rel` modulates emission rate; vocals pitch baked at emission as per-mote hue (the trail becomes a visual record of the melody, similar in spirit to Gossamer's wave hue baking); `drums_energy_dev` triggers a soft dispersion shock.

**Family.** `particles` (matches Nebula's family classification under D-067(b) lightweight-rubric particles bucket). _Confirm enum value._

**Render passes.** `["feedback", "particles"]` (same as Murmuration; mv_warp is incompatible with particle systems per D-029).

## 2. References

**Recommendation: skip dedicated curation.** The aesthetic is well-precedented in cinematography. The existing `07_atmosphere_dust_motes_light_shaft.jpg` in `docs/VISUAL_REFERENCES/arachne/` is on point and can be reused without curating new images. If Session 1 visual review surfaces a need for sharper anchors, three additional images would suffice:

- **God-ray hero shot.** A wide light shaft with motes drifting through it — cathedral, forest, or interior cinematography.
- **Side-lit pollen.** Pollen field side-lit by low-angle sun, motes glowing against dark backdrop.
- **Anti-reference: generic particle.js dust demo.** For documenting what we are NOT building.

Default plan: anchor the design discussion against the reused Arachne `07` image and curate only if the design begins to drift.

## 3. Trait matrix

| Scale | Trait |
|---|---|
| **Macro** | Single dramatic light shaft entering from upper-left at ~30° from vertical, extending across most of frame. Dark warm-amber backdrop. Motes scattered through 3D volume; concentration follows the shaft volume but extends slightly beyond. |
| **Meso** | Particle field has macro-scale density variation (clumps and clearings) from emission and recycle dynamics. Wind gusts produce visible flow patterns. |
| **Micro** | Per-mote sprite is a soft Gaussian blob (~6 px at typical viewing scale). Per-mote brightness modulated by light-shaft intersection. |
| **Specular breakup** | Particle hue varies per-mote (each mote carries the pitch of its emission moment); brightness varies with shaft position. The visual texture of the field is the variation distribution. |
| **Material** | Emission-only (additive blend). Lightweight rubric. |
| **Lighting** | One implicit directional light defining the shaft direction; no PBR. Light shaft volume rendered via `ls_shadow_march` (or screen-space `ls_radial_step_uv`). Floor fog (`vol_density_height_fog`) gives ambient haze. |
| **Atmosphere** | Floor fog + light shaft volume = the entire atmospheric effect. |
| **Motion** | Particle drift in force field (wind + gravity + curl_noise turbulence). No flocking. Feedback trail decay (0.92) gives faint streaks. |
| **Audio reactivity** | See §5.6. |

## 4. Renderer capability audit

| Need | Available? | Notes |
|---|---|---|
| Particle compute kernel infrastructure | ✓ | Murmuration uses it via `Particles.metal`. Sprite render path established. |
| `Particle` struct (64 bytes per spec) | ✓ | Existing in CLAUDE.md key types. May need to extend with bake-hue field — verify if existing `color` slot can carry it. |
| Light shafts (screen-space + ray-march variants) | ✓ | V.2 utility tree. |
| `vol_density_height_fog` | ✓ | V.2 volume tree. |
| Per-particle hue baking from `vocalsPitchNorm` | _wiring required_ | The compute kernel has access to `StemFeatures` via fragment buffer; an emission-time read from `vocalsPitchHz` + `vocalsPitchConfidence` writes the hue into the `Particle.color` slot. Pattern matches Gossamer wave hue baking. |
| Force-field integration | ✓ | `curl_noise` is in V.1 noise tree; per-frame integration is straightforward in compute kernel. |
| Feedback (`feedback` pass) trail decay | ✓ | Used by Membrane / Murmuration. |

**Gaps:** None blocking. The per-particle hue baking is a small wiring task — the data path exists; this preset is the first to use it for non-flock particles. Verify whether the existing `Particle.color` field is sufficient (4× Float32) or whether a wider per-particle struct is needed for `(hue, saturation, value, life_remaining)` separately. Anticipate a small extension to `Particle` if needed; flag as "verify in Session 1."

## 5. Rendering architecture

### 5.1 Pass structure

`passes: ["feedback", "particles"]`. Order:

1. **Sky backdrop** drawn as a fragment shader pass into the scene texture (warm-amber gradient, no stars).
2. **Particle compute** integrates positions/velocities into the particle buffer.
3. **Particle render** pass: each particle drawn as a soft sprite, additively blended onto the scene texture.
4. **Volumetric overlays:** light shaft and floor fog rendered into the scene texture.
5. **Feedback** pass alpha-blends current scene with previous-frame accumulator at decay 0.92.

### 5.2 Compute kernel (per particle, per frame)

```metal
kernel void update_motes(device Particle* particles [[buffer(0)]],
                          constant FeatureVector& f [[buffer(2)]],
                          constant StemFeatures& stems [[buffer(3)]],
                          constant Uniforms& u [[buffer(4)]],
                          uint id [[thread_position_in_grid]]) {
    Particle p = particles[id];
    float dt = u.dt;

    // Lifecycle
    p.age += dt;
    if (p.age > p.life || any(abs(p.position) > BOUNDS)) {
        // Recycle: respawn at top of light shaft volume with hue baked from current pitch
        p.position = sample_emission_position(id, u.time);
        p.velocity = float3(-0.05, -0.4, 0.0);  // slow downward drift
        float pitch_norm = stems.vocalsPitchHz > 0
            ? log2(stems.vocalsPitchHz / 80.0) / log2(10.0)
            : -1.0;
        float confidence = stems.vocalsPitchConfidence;
        p.color = (confidence > 0.4) ? hue_from_pitch(pitch_norm) : default_warm_hue();
        p.age = 0.0;
        p.life = 5.0 + 4.0 * hash_f01(id);
    }

    // Wind force: continuous gentle drift + gust modulation
    float3 wind = normalize(float3(-1.0, -0.2, 0.0)) * (0.3 + 0.6 * f.bass_att_rel);

    // Turbulence: curl_noise field
    float3 turb = curl_noise(p.position * 0.6 + u.time * 0.1) * 0.15;

    // Drum dispersion shock: gated on drums_energy_dev > 0.3, applied as radial impulse from shaft center
    if (stems.drums_energy_dev > 0.3) {
        float3 shock_dir = normalize(p.position - SHAFT_CENTER) * (stems.drums_energy_dev - 0.3) * 1.2;
        p.velocity += shock_dir * dt * 4.0;
    }

    p.velocity = p.velocity * 0.97 + (wind + turb) * dt;  // damping + force integration
    p.position += p.velocity * dt;

    particles[id] = p;
}
```

Particle count: 800 (Tier 2) / 400 (Tier 1).

### 5.3 Sprite render

Each particle drawn as a 6-px soft Gaussian sprite. Brightness scaled by:

- Position inside light shaft volume: sample shaft density at particle position.
- Per-particle hue from `p.color`.
- Distance from light source within shaft (closer = brighter).

Additive blend.

### 5.4 Light shaft + atmosphere

**Shaft.** `ls_shadow_march` from sun position `(2.5, 5.0, 1.0)` direction `(-0.4, -0.85, 0.0)`. Cone half-angle ~12° (a wide beam, not a pencil). Density modulated by `(0.6 + 0.4 * mid_att_rel)`. Color is warm `(1.0, 0.85, 0.5) * valence_tint`.

**Floor fog.** `vol_density_height_fog` with `floorY = -1.0`, falloff 0.6, color matched to backdrop warm tone. Sets the ambient floor — without this the scene reads as motes on solid black.

**Backdrop.** Warm-amber vertical gradient; top `(0.05, 0.03, 0.02)`, bottom `(0.10, 0.07, 0.04)`. Tinted by `valence`.

### 5.5 Feedback specifics

`decay = 0.92` — short trails. We want motes to leave faint streaks during fast wind, not persistent ribbons.

`base_zoom = 0.0`, `base_rot = 0.0`. Pure trail decay; no global motion.

### 5.6 Audio routing

| Driver | Source | Effect | Continuous/accent |
|---|---|---|---|
| Wind force magnitude | `f.bass_att_rel` | Wind vector magnitude | continuous primary |
| Emission rate | `f.mid_att_rel` | Particles emitted per second (60 base + 60 × x) | continuous primary |
| Per-mote hue | `stems.vocalsPitchNorm` (gated) | Baked at emission, persists for life | continuous (per emission) |
| Light shaft density | `f.mid_att_rel` | Density multiplier (0.6 + 0.4 × x) | continuous |
| Backdrop palette tint | `f.valence` | Warm/cool shift | continuous |
| Dispersion shock | `stems.drums_energy_dev` (dev-form, threshold > 0.3) | Radial impulse to particle field | accent |
| Shaft brightness | `f.bass_att_rel` | ±15% multiplier | continuous |
| Anticipatory shaft pulse | `f.beat_phase01` | `approachFrac × 0.05` brightness ramp | accent (subtle) |

**D-026 compliance:** every primary driver uses `*_rel` or `*_dev`. **Continuous-vs-accent ratio:** wind force amplitude 0.6 (continuous), shock impulse `1.2 × (dev_max ≈ 0.5) = 0.6`. The shock fires only above threshold and only when `dev > 0.3`, so it is genuinely accent-like in occurrence. Verify by acceptance test (see §8).

**D-019 compliance:** stem reads gated through `smoothstep(0.02, 0.06, totalStemEnergy)` warmup. Pre-warmup, hue baking falls back to `default_warm_hue()` (a fixed warm-amber); shock disabled.

### 5.7 State

- GPU particle buffer: `Particle * 800` (Tier 2) / `Particle * 400` (Tier 1).
- No CPU-side state per frame. Particle buffer is persistent across frames.
- Reset on track change: `resetParticleBuffer()` at `applyPreset` and `trackChanged`.

### 5.8 Silence fallback

At zero audio: wind force is at base level (0.3 magnitude), motes drift gently, emission rate at base (60/sec), shaft at base brightness, all motes inherit `default_warm_hue()`. Feedback trail decay continues. The scene is alive — the shaft cuts the frame, motes drift, fog softly glows. Form complexity at silence: ≥ 3 (motes + shaft + fog gradient).

## 6. Anti-references and failure modes

- **"Murmuration repetition."** The motion model must NOT exhibit any flocking behavior. Particles do not seek each other. If reviewers detect alignment or cohesion, the curl_noise turbulence must be re-tuned to dominate.
- **"Generic dust shader."** Without the dramatic light shaft, the motes lack compositional anchor. The shaft is half the preset.
- **"Constant emission rate."** Looks lifeless. Emission must vary visibly with mids.
- **"Motes don't catch the shaft."** If sprite brightness is constant regardless of shaft intersection, the shaft has no purpose. Brightness modulation by shaft-density sample at particle position is mandatory.
- **"Beat-pulsing motes."** Drum-coupled per-mote brightness flashing reads as EDM. Drum coupling is dispersion shock only.
- **"Murky floor."** Without `vol_density_height_fog`, scene reads as motes on void.

## 7. Performance budget

| Element | Tier 2 (800 motes) | Tier 1 (400 motes) |
|---|---|---|
| Compute integration | 0.4 ms | 0.25 ms |
| Sprite render | 0.6 ms | 0.35 ms |
| Sky backdrop | 0.1 ms | 0.1 ms |
| Light shaft | 0.5 ms (32 samples) | 0.4 ms (24 samples) |
| Floor fog | 0.2 ms | 0.2 ms |
| Feedback | 0.3 ms | 0.3 ms |
| **Total** | **~2.1 ms** | **~1.6 ms** |

`complexity_cost: {"tier1": 1.6, "tier2": 2.1}`. Comfortably under both tier budgets.

## 8. Acceptance criteria

**Rubric profile: lightweight** (D-067(b) — particle systems exempt).

- **L1 (silence):** Pass if motes continue drifting and shaft remains visible. Form complexity ≥ 3 (motes + shaft + fog).
- **L2 (deviation primitives):** All audio routing uses `*_rel` / `*_dev`. Verified.
- **L3 (perf):** p95 ≤ tier budget. Verified by `PresetPerformanceTests`.
- **L4 (frame match):** Matt M7 review — light, given optional curation.

**Preset-specific tests:**

1. `DriftMotesNonFlockTest` — render 200 frames, sample 50 random particle pairs, assert pairwise distance distribution does not contract (no cohesion).
2. `DriftMotesPitchHueBakeTest` — render with `vocalsPitchHz` swept; sample emitted particle hues over time; assert hue distribution shifts in lockstep with pitch (with one-second lag for emission cadence).
3. `DriftMotesShockBoundsTest` — pulse `drums_energy_dev` from 0 → 0.6 → 0; assert post-shock max particle velocity is bounded (no runaway dispersion).
4. `DriftMotesShaftIntersectionTest` — render and sample 100 particles by position; assert particles inside shaft volume have brightness ≥ 1.5× particles outside.

## 9. Implementation phases

**Session 1 — Compute kernel + particle render + backdrop.** Particle force-field integration (wind + curl_noise + recycle). Sprite render with default warm hue. Sky backdrop. No flocking; verify pairwise distance test.

**Session 2 — Light shaft + atmosphere + per-particle hue baking.** `ls_shadow_march` shaft from upper-left. `vol_density_height_fog` floor. Per-particle hue baking from `vocalsPitchNorm` with confidence gate. Verify hue-bake test.

**Session 3 — Audio routing + drum shock + cert.** Wire all audio routes per §5.6. Drum dispersion shock. Performance profile. Continuous-dominance and shock-bounds tests. Matt M7 review.

**Estimated: 2-3 sessions.**

## 10. JSON sidecar template

```json
{
  "id": "drift_motes",
  "family": "particles",
  "passes": ["feedback", "particles"],
  "tags": ["dust", "pollen", "shaft", "ambient", "atmospheric"],
  "feedback": {
    "decay": 0.92,
    "base_zoom": 0.0,
    "base_rot": 0.0,
    "beat_zoom": 0.0,
    "beat_rot": 0.0,
    "beat_sensitivity": 0.0
  },
  "stem_affinity": {
    "vocals": "mote_hue",
    "bass": "wind_force",
    "drums": "dispersion_shock",
    "other": null
  },
  "particle_count": { "tier1": 400, "tier2": 800 },
  "visual_density": 0.35,
  "motion_intensity": 0.30,
  "color_temperature_range": [0.55, 0.85],
  "fatigue_risk": "low",
  "transition_affordances": ["crossfade", "morph"],
  "section_suitability": ["ambient", "comedown", "bridge"],
  "complexity_cost": { "tier1": 1.6, "tier2": 2.1 },
  "certified": false,
  "rubric_profile": "lightweight",
  "rubric_hints": {}
}
```

## 11. Open questions

1. **`Particle` struct hue field.** The existing `Particle` struct (64 bytes) has a `color` slot — verify it can carry baked hue + saturation + value separately, or if it's a single packed RGBA. If single RGBA, the current 64-byte budget is already tight; consider whether to extend or to compute saturation/value per frame.
2. **Family enum.** Confirm `particles` is the actual `PresetCategory` value Nebula uses; alternative could be `atmospheric` if such a category exists.
3. **Particle count tier scaling.** 800/400 is the proposed split. May need 1000/500 if motes feel too sparse; budget allows it.
4. **Shaft direction.** Upper-left → lower-right at 30° from vertical is the proposed start; reviewers may prefer right-to-left or vertical. Should be a JSON-tunable scene parameter so we can iterate without code changes.
