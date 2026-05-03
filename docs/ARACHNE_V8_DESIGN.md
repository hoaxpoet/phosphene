# Arachne v8 — Design Spec

**Status:** Draft for Matt review (2026-05-02). Locks the design conversation that produced D-072 and supersedes the V.7.7-V.7.9 sketch in `SHADER_CRAFT.md §10.1`. No code yet — implementation increments are listed in `ENGINEERING_PLAN.md`.

**Goal:** A naturalistic time-lapse of a single spider web being slowly drawn, against an atmospheric backdrop of completed dewy webs, with a spider that appears in response to sustained bass and shakes the whole scene during heavy bass.

**Why this spec exists:** Five Arachne attempts (3.5.5 mesh, 3.5.10 3D ray-march, 3.5.12 2D SDF rebuild, V.7 v4, V.7.5 v5) failed to reach the bar. D-072 diagnosed the V.7.5 failure as architectural (missing compositing layers, not bad constants). Subsequent design conversation (2026-05-02) reframed the visual target away from "static photorealistic dewy web" toward "time-lapse construction sequence with photorealistic background webs" — modeled on the BBC Earth orb-weaver time-lapse footage. This spec captures that reframing in implementable form before any code is written.

---

## 1. Visual model — three layers

### 1.1 Background layer — completed dewy webs

- **At preset entry, pre-populate at least one already-finished web in the background.** Avoids the empty-scene problem during the first build cycle (Matt 2026-05-02: "this would be incredibly boring to watch").
- Background webs are **dewy, saggy, and slightly out of focus**. They sit at depth with mild Gaussian blur applied so the foreground reads as the focus point.
- Drops on background webs are **the photographic look from refs `01`, `03`, `04`**: refractive (sample background atmospheric texture through the spherical-cap normal), fresnel rim, sharp specular pinpoint, dark edge ring. Drops carry the visual weight; threads are faint connective tissue between drop chains.
- Background webs do not animate (no construction). They sit. They shake on bass (§4.2).
- As foreground builds complete (§1.2), the completed web migrates back into the background pool over a short crossfade (~1s). Old background web fades out if the pool is at capacity.
- **Pool size:** 1–2 background webs at any time. No more — the scene is one foreground hero plus atmospheric backdrop, not a field of webs.

### 1.2 Foreground layer — one web, slowly drawn

- **One web in active construction, ≤ 60s build cycle.** Hard ceiling (§3 — preset-declared `maxDuration`). Orchestrator may transition to next preset before completion (§3.4); that's fine.
- **Construction sequence (mirrors orb-weaver biology):**
  1. **Hub appears** (~0–2s): central anchor point with implied free zone (no spiral threads).
  2. **Radials extend one at a time** (~2–25s): each radial draws from hub outward over ~1.5s. Order is alternating-pair (matches biology — `0, n/2, 1, n/2+1, …`) for visually balanced fill. ±20% per-spoke angular jitter (per `rng_seed`) for natural irregularity. Total ≈ 12–17 radials over ~20s.
  3. **Capture spiral winds outward** (~25–55s): chord-segment SDF (straight line between adjacent radials at each spiral revolution; *not* a continuous Archimedean curve — see §1.4). Wind progresses chord-by-chord at a tempo-modulated rate.
  4. **Settle** (~55–60s): brief pause; web emits "complete" signal to orchestrator (§3.4).
- **No spider visible during construction.** The threads "draw themselves" as if by an invisible hand.
- **Drops form on the capture spiral as it's laid**, and continue to accrete in density over the remaining build time and during settle. Drop density on foreground is lower than background (foreground is recently woven; less time for dew to accumulate). Drops use the same refractive recipe as §1.1.

### 1.3 Spider + vibration overlay

See §2 (audio mapping) for trigger conditions and §4.2 (vibration model) for shake characteristics.

- **Spider remains an easter egg.** Triggered by sustained sub-bass with `bassAttackRatio < 0.55` (V.7.5 §10.1.9 gate, unchanged). Per-segment or per-session cooldown enforces rarity — spider should NOT appear on every Arachne segment. Rough target: 1 in 5–10 Arachne segments.
- **Spider appears on the foreground web** when triggered.
- **Construction PAUSES while spider is visible.** The drawing-itself animation freezes; the spider becomes the focus.
- **Web shake applies to ALL webs** (foreground in-progress + background completed). Whole-scene tremor. Vibration is driven by sub-bass + heavy bass continuously (§4.2) — independent of the spider trigger; the web shakes whenever heavy bass is present, with or without the spider.
- **Spider position:** centered on the foreground web's hub, slightly offset, oriented at an angle that reads as "occupying" the web rather than standing on it.
- **Spider visual:** dark silhouette (V.7.5 §10.1.9 recipe — `(0.04, 0.03, 0.02)` body, thin warm-amber rim catching backlit `kL`, alternating-tetrapod gait).
- **When bass eases, spider fades** (over ~2s). Construction RESUMES from where it left off — does NOT restart the build cycle.

**Rarity mechanism (TBD detail):** the V.7.5 implementation used a 300s session-level cooldown. For v8 with 60s Arachne segments, that translates to "at most one spider appearance per ~5 segments" — roughly the right rarity. Implementation can either keep the session cooldown (simpler) or use a per-segment "did spider already appear?" flag (more deterministic). Decide during V.7.9 implementation.

### 1.4 Web geometry — naturalistic, not geometric

- **Threads are 2D SDF chord segments**, not continuous Archimedean curves. Each spiral revolution = N straight `arachSegDist` segments connecting adjacent radial attachments. Visually breaks the bullseye degeneracy that V.7.5 produced (D-072 diagnostic).
- **Sag is parabolic** (`y -= u*(1-u) * amount * length`) per radial, gravity-direction-weighted (downward radials sag more than horizontal). Magnitude must be **visibly large** (`kSag` range [0.06, 0.14] from V.7.5 was too subtle; needs to be larger — calibrate against ref `02`).
- **Hub structure:** single anchor point with a small free zone (no spiral within ~hub_radius * 1.5). NO concentric rings (current V.7.5 hub is anatomically wrong — orb webs don't have ring structure at the hub).
- **Per-web macro variation** from `rng_seed`: hub jitter ±5% UV, elliptical aspect 0.85–1.15, in-plane tilt, spoke count 11–17, sag amount [0.06, 0.14]. (Preserved from V.7.5 §10.1.A.)
- **Drop spacing on capture spiral is regular** — Plateau-Rayleigh instability makes real drops uniform-spaced. Hash-jitter ±5% maximum, not the V.7.5 ±25% (research finding 2026-05-02 — see D-072 update).
- **Drop chains visibly bead-touch** — spacing ≈ 4–5 drop diameters (matches biology).

---

## 2. Audio mapping

D-026 deviation primitives only. No absolute thresholds. Continuous/beat ratio ≥ 2× per CLAUDE.md rule of thumb.

| Audio source | Drives | Continuous / accent |
|---|---|---|
| `f.bass_att_rel` | foreground build pace (radial advance, spiral chord placement) | Continuous |
| `stems.drums_energy_dev` | brief construction-pace acceleration on drum onsets | Beat accent |
| `f.mid_att_rel` | drop accretion rate on foreground spiral, dust-mote density in atmosphere | Continuous |
| `max(f.subBass_dev, f.bass_dev)` | **web vibration amplitude** (all webs) — see §4.2 | Continuous |
| `f.beatBass` | brief vibration amplitude spike per kick | Beat accent |
| `stems.vocals_pitch` | optional subtle hue shift on background-web drops (vocal melody → drop tint) | Continuous |
| Sustained `f.subBass > 0.30 && stems.bassAttackRatio < 0.55` for ≥ 0.75s | **spider trigger** (V.7.5 §10.1.9 gate, unchanged) | Threshold event |

**Construction pace audio mapping (foreground only):**
- Base rate: 1 chord segment / second at silence.
- Mid-band continuous boost: `+0.18 * f.mid_att_rel` segments/second.
- Drum-onset accent: `+0.5 * stems.drums_energy_dev` (per-frame, decays naturally).
- Total build time at average music: ~50–55s (within the 60s ceiling). At silence: ~75s (would exceed ceiling — orchestrator transitions before completion).

**Spider behavior on trigger:**
- Trigger condition (V.7.5 §10.1.9, unchanged): sustained `f.subBass > 0.30` AND `stems.bassAttackRatio ∈ (0, 0.55)` for ≥ 0.75s.
- On trigger: spider fades in over 2s, construction pauses (foreground build accumulator stops advancing). Cooldown removed from V.7.5 (300s session-level lock no longer needed — spider is not a rare easter egg, it's a primary audio-reactive element).
- On bass ease: spider fades out over 2s, construction resumes from paused accumulator.

---

## 3. Orchestrator changes (preset-system-wide)

This is the load-bearing infrastructure change. It affects every preset, not just Arachne. It blocks the Arachne v8 implementation — Arachne can't signal "I'm done" until the orchestrator can accept that signal and act on it.

### 3.1 Per-preset `maxDuration` becomes authoritative

Currently `PresetDescriptor.duration` is interpreted as a "preferred" hint — the orchestrator may run a preset for the whole song. The new contract: **`maxDuration` is a hard ceiling.** A preset is never given a segment longer than its declared `maxDuration`.

Each preset's JSON sidecar declares its `maxDuration` in seconds. Initial values to be set per-preset in §5.

### 3.2 `PlannedTrack` becomes `[PlannedPresetSegment]`

```swift
struct PlannedTrack {
    let track: TrackIdentity
    let trackProfile: TrackProfile
    let segments: [PlannedPresetSegment]   // was: let preset: PresetDescriptor
    let plannedStartTime: TimeInterval
    let plannedEndTime: TimeInterval
}

struct PlannedPresetSegment {
    let preset: PresetDescriptor
    let presetScore: Float
    let scoreBreakdown: PresetScoreBreakdown
    let plannedStartTime: TimeInterval        // session-relative
    let plannedEndTime: TimeInterval          // session-relative
    let incomingTransition: PlannedTransition?
    let trigger: SegmentBoundaryTrigger       // section / max_duration / completion
}

enum SegmentBoundaryTrigger {
    case sectionBoundary(sectionIndex: Int, confidence: Float)
    case maxDurationReached
    case presetCompletion
}
```

### 3.3 Pre-analysis pairs presets with sections

The session planner runs a forward-walk over each track's section list (from `StructuralAnalyzer.predictedNextBoundary` populated during preparation). For each section:
- Score all presets eligible for that section's mood/energy/tempo (existing `DefaultPresetScorer`)
- Constrain by remaining-time-in-section AND preset's `maxDuration`
- If the section is longer than the chosen preset's `maxDuration`, the planner inserts a transition mid-section to a second preset (avoiding family-repeat per existing rules)
- If the section is shorter than the chosen preset's `minDuration`, the preset spans the section and continues into the next

### 3.4 Preset completion signal — new channel

A new protocol method on `RenderPipeline` (or a separate `PresetSignaling` protocol):

```swift
protocol PresetSignaling: AnyObject {
    /// Emitted by a preset to request immediate transition to the next planned segment.
    /// The orchestrator is free to honor or ignore (e.g. if the segment hasn't been on
    /// screen long enough to count as "shown", per minDuration).
    var presetCompletionEvent: PassthroughSubject<Void, Never> { get }
}
```

Arachne emits this when its build cycle completes (§1.2 step 4). Other presets can opt in if they have natural completion points (most won't — they're cyclical). The orchestrator subscribes per active preset; on event, it fast-forwards to the next planned segment if `minDuration` is satisfied, otherwise queues the transition for when `minDuration` elapses.

### 3.5 Live adapter accommodates segment boundaries

Existing `LiveAdapter` overrides need to respect the new segment structure. A user-driven `presetNudge(.next)` advances to the next *segment*, not the next *track*. Track boundaries are handled separately as today.

---

## 4. Render architecture

### 4.1 Render-pass layout

Per frame, in order:

1. **Background atmospheric pass** → texture `arachneBackgroundTex` (half-res, `drawableSize / 2`). Mood-tinted vertical gradient (warm-bottom for high-valence, cool-top for low-valence; pure black is silence-calibration anchor only). Defocused foliage via `worley_fbm` at low frequency, mottled with `fbm8`. Optional volumetric warm beam from `kL` direction. Subtle radial vignette. Baked-in 3–5 px Gaussian blur.

2. **Background webs pass** → composite onto the bg texture. For each background web: 2D SDF chord-segment threads + refractive drops (sample `arachneBackgroundTex` through spherical-cap normal — Snell's law, eta ≈ 0.752, fresnel rim, specular pinpoint). Apply mild Gaussian blur for depth (out-of-focus look). Vibration offset applied per-vertex (§4.2).

3. **Foreground web pass** → composite over background composite. SDF chord-segment threads (drawn-so-far portion only, controlled by `buildAccumulator`) + refractive drops on completed spiral chords. Sharp focus (no DoF blur). Vibration offset applied (§4.2).

4. **Spider overlay** → if `spiderBlend > 0`, composite spider silhouette over foreground (V.7.5 §10.1.9 recipe).

5. **Post-process** → `PostProcessChain` bloom on bright spots (drops, spider rim) + ACES tone-mapping. Optional depth-weighted bokeh DoF for additional separation.

### 4.2 Vibration model

Whole-scene tremor on bass. Applied as per-vertex UV offset in the vertex shader of every web (background + foreground).

```hlsl
// Per-strand random phase from rng_seed for naturalistic incoherence.
float strandPhase = rand(seed * 0.001 + radial_index * 0.137);

// Audio-driven amplitude. Continuous from sub-bass + bass deviation.
float bassAmp = max(f.subBass_dev, f.bass_dev);
float beatSpike = 0.4 * f.beatBass;  // brief +40% on each kick
float amplitude = (0.0025 * bassAmp + beatSpike * 0.0015) * length(thread_local_position);

// 12 Hz tremor rate — fast enough to read as vibration, slow enough not to blur.
float tremor = sin(2.0 * M_PI_F * 12.0 * time + strandPhase * 6.28);

// Apply offset perpendicular to strand direction (where vibration physically goes).
float2 perp = normalize(float2(-strand_dir.y, strand_dir.x));
vertex_offset += perp * tremor * amplitude;
```

Tunables:
- `tremor_frequency = 12 Hz` (perceptible vibration; not a swaying motion)
- `bass_amplitude_scale = 0.0025` (UV-space; visible at moderate bass, prominent at heavy bass)
- `beat_spike_amplitude = 0.0015` (brief per-kick spike)
- `length-scaling factor` so tips of long radials shake more than near-hub points (physically correct — anchor stays still, tip moves)

This is the design call referenced in §1.3. Subject to visual review via the harness.

### 4.3 Color source — live mood-driven palette with smoothing

**Locked 2026-05-02 per Matt direction (Option B with full specification).**

Single source of truth: the smoothed mood signal (`f.valence`, `f.arousal` from MoodClassifier) drives the entire scene palette. Smoothed over a 5-second low-pass window so palette transitions are gradual (no jarring mid-section shifts). Standard psychophysics mapping: **valence → warm/cool hue, arousal → saturation + brightness**.

```hlsl
// Inputs: smoothed mood signal (5s low-pass on f.valence and f.arousal)
float v = smoothedValence;  // -1..1
float a = smoothedArousal;  // -1..1

// Hue: cool (cyan/blue 0.55–0.65) at low valence, warm (orange/amber 0.05–0.10) at high valence
float topHue = mix(0.62, 0.05, saturate(0.5 + 0.5 * v));   // sky-ish: cool when sad, warm at dawn
float botHue = mix(0.58, 0.08, saturate(0.5 + 0.5 * v));   // ground-ish: cool mist or warm earth

// Saturation/brightness scale with arousal. Low arousal = desaturated, dim. High = saturated, brighter.
float satScale = 0.25 + 0.40 * saturate(0.5 + 0.5 * a);   // 0.25 calm → 0.65 energetic
float valScale = 0.10 + 0.20 * saturate(0.5 + 0.5 * a);   // 0.10 dim → 0.30 brighter

float3 topCol = hsv2rgb(float3(topHue, satScale, valScale * 1.2));
float3 botCol = hsv2rgb(float3(botHue, satScale * 0.85, valScale));

// Volumetric beam (when f.mid_att_rel > 0.05): warm at v>0, cool at v<0
float3 beamCol = hsv2rgb(float3(mix(0.6, 0.08, saturate(0.5 + 0.5 * v)), 0.5, 0.4));
```

**Per-layer color application:**

| Layer | Color recipe | Notes |
|---|---|---|
| Background gradient | `mix(botCol, topCol, uv.y)` | Primary visual carrier of palette |
| Foliage silhouettes | `botCol * 0.3` | Darker version of bg so they read as silhouette |
| Volumetric beam (when present) | `beamCol`, additive | Warm at high valence, cool at low |
| Background drops | refraction of bg texture (palette inherits) + white-ish fresnel rim at 0.85 brightness | Drops automatically take on bg colors via refraction |
| Background threads | `mix(botCol, topCol, 0.5) * 0.4` | Barely visible silhouette tone |
| Foreground threads | same as bg threads × 1.5 brightness | Slightly more visible (in focus) |
| Foreground drops | refraction of bg texture | Same recipe as bg drops |
| Spider (when present) | body `(0.04, 0.03, 0.02)` + warm-amber rim `(0.85, 0.55, 0.30)` | **Intentional contrast** — does NOT follow mood palette. Spider rim is audio-reactive overlay, not part of the world. |

**Coverage of the reference set:** mood quadrants map to references:
- `(v>0, a>0)` high valence high arousal → ref `04` warm gold backlit, ref `05` golden field
- `(v>0, a<0)` high valence low arousal → muted warm dawn (between refs `04` and `05`)
- `(v<0, a>0)` low valence high arousal → dramatic cool with rim accents (variant of ref `01`)
- `(v<0, a<0)` low valence low arousal → ref `06` cool blue-grey misty, ref `08` dark with bioluminescent accents

**Smoothing implementation:** add `smoothedValence` and `smoothedArousal` fields to a per-preset state struct (don't pollute FeatureVector — this is preset-specific). Each frame: `smoothedX = lerp(smoothedX, currentX, dt / 5.0)`. The 5-second window is initial; tune up to 8s if mood shifts feel jumpy in practice, down to 3s if palette feels sluggish.

**Pure black at silence is preserved** as the calibration anchor (per `08_palette_bioluminescent_organism.jpg`): if `(satScale × valScale) < 0.05` (silence-state mood signal), bg pass clears to black; gradient + foliage suppressed. Drops + threads still render against black; the palette fades back in as audio resumes.

---

## 5. Per-preset `maxDuration` framework — derived from declared properties + audio analysis

**Locked 2026-05-02 per Matt direction (defensible framework, not empirical reaction).**

`maxDuration` is computed deterministically from existing preset descriptor properties and per-section audio analysis. Same preset paired with same section type produces the same duration ceiling. The framework is transparent (each input's contribution is visible), adjustable (coefficients tunable), and falsifiable (you can compute the table for all 13 presets and check against intuition).

### 5.1 Inputs

All from existing data — no new declarations required except an optional `naturalCycleSeconds` for presets with fixed cycles (Arachne).

| Input | Source | Range |
|---|---|---|
| `motionIntensity` | preset JSON sidecar (V.4 schema, already declared) | 0..1 |
| `visualDensity` | preset JSON sidecar (V.4 schema, already declared) | 0..1 |
| `fatigueRisk` | preset JSON sidecar (V.4 schema, already declared) | enum {low=0, medium=1, high=2} |
| `naturalCycleSeconds` | preset JSON sidecar (V.7.6.2 field, optional) | seconds, only set for presets with a fixed visual cycle |
| `isDiagnostic` | preset JSON sidecar (V.7.6.C field, default false) | bool — diagnostic presets are exempt and return `.infinity` |
| `sectionLingerFactor` | per-section table, see §5.2 below | 0..1 |

### 5.2 Formula

V.7.6.C calibration (Option B): per-section linger factors are tuned so ambient and peak (the meditative + climactic emotional cores) extend `maxDuration`, while buildup and bridge (transitional moments where preset changes feel natural) shorten it. The field name `sectionDynamicRange` from the original §5.2 spec was renamed to `sectionLingerFactor` to reflect that the values are no longer derived from audio variance — they are author-set per-section weights.

```swift
func computeMaxDuration(preset: PresetDescriptor, section: SongSection?) -> TimeInterval {
    // Diagnostic presets are exempt — they remain in place until manually switched.
    if preset.isDiagnostic { return .infinity }

    // Base maxDuration from preset properties — answers "how long does this preset stay interesting on average music?"
    let baseMax: Double = 90.0
                        - 50.0 * (preset.motionIntensity - 0.5)
                        - 30.0 * Double(preset.fatigueRisk.score)  // low=0, medium=1, high=2
                        - 15.0 * (preset.visualDensity - 0.5)

    // Section adjustment — ambient/peak linger; buildup/bridge are transitional.
    let sectionAdjust = baseMax * (0.7 + 0.6 * lingerFactor(section))

    // Hard cap from natural cycle length (Arachne's 60s build, etc.)
    if let cycle = preset.naturalCycleSeconds {
        return min(cycle, sectionAdjust)
    }
    return sectionAdjust
}

// V.7.6.C Option B linger factors:
//   ambient  = 0.80   (longest — meditative)
//   peak     = 0.75   (climactic moments are the emotional core)
//   comedown = 0.65
//   buildup  = 0.40   (transitional)
//   bridge   = 0.35   (transitional, shortest)
//   nil      = 0.50   (neutral midpoint when no section context)
```

### 5.3 Computed values (V.7.6.C calibrated)

Computed against current production preset descriptors with the V.7.6.C Option B linger factors. The table shows the default (section=nil, factor=0.5) value plus the per-section ceiling. Authoritative source-of-truth: the Swift formula in `PresetMaxDuration.swift` evaluated at runtime — these values are reproduced here for review and are asserted in `MaxDurationFrameworkTests`.

| Preset | motionIntensity | visualDensity | fatigueRisk | naturalCycle | default | ambient | peak | comedown | buildup | bridge |
|---|---|---|---|---|---|---|---|---|---|---|
| Arachne | 0.50 | 0.65 | low | **60s** | 60 | 60 | 60 | 60 | 60 | 60 |
| Ferrofluid Ocean | 0.65 | 0.75 | medium | — | 49 | 58 | 56 | 53 | 46 | 44 |
| Fractal Tree | 0.55 | 0.65 | medium | — | 55 | 65 | 64 | 60 | 52 | 50 |
| Glass Brutalist | 0.40 | 0.40 | medium | — | 67 | 79 | 77 | 73 | 63 | 61 |
| Gossamer | 0.30 | 0.40 | low | — | 102 | 120 | 117 | 111 | 95 | 92 |
| Kinetic Sculpture | 0.70 | 0.60 | medium | — | 49 | 57 | 56 | 53 | 46 | 44 |
| Membrane | 0.70 | 0.55 | medium | — | 49 | 58 | 57 | 54 | 46 | 45 |
| Murmuration | 0.85 | 0.90 | low | — | 67 | 79 | 77 | 73 | 63 | 61 |
| Nebula | 0.30 | 0.80 | low | — | 96 | 113 | 110 | 104 | 90 | 87 |
| Plasma | 0.50 | 0.70 | high | — | 27 | 32 | 31 | 29 | 25 | 25 |
| Spectral Cartograph | 0.00 | 0.10 | low | — | ∞ | ∞ | ∞ | ∞ | ∞ | ∞ |
| Volumetric Lithograph | 0.60 | 0.70 | low | — | 82 | 97 | 94 | 89 | 77 | 75 |
| Waveform | 0.60 | 0.30 | medium | — | 58 | 68 | 67 | 63 | 54 | 53 |

**Spectral Cartograph** is flagged `is_diagnostic: true` (V.7.6.C). Diagnostic presets are exempt from the framework — they return `.infinity` and are never auto-segmented. The orchestrator's "diagnostic presets are manual-switch only" semantic (Scorer hard-exclusion + LiveAdapter no-override) is the V.7.6.D follow-up scope.

**Glass Brutalist** computes at 67s default. Matt's earlier intuition (2026-05-02) suggested ~30s, but per Matt's V.7.6.C review note ("the presets are uncertified and very far from ready"), this row is left as-is — fine-tuning here would optimise for an artistic target the preset hasn't reached yet. If a future certified Glass Brutalist genuinely cycles every 30s, declaring `natural_cycle_seconds: 30` is the right tool. Coefficient overrides for one outlier are not.

**Per-section shape (Option B):** ambient and peak linger; buildup and bridge are transitional. Comedown sits between. The neutral default (section=nil) is the midpoint at factor=0.5.

### 5.4 Calibration loop

The framework is initially calibrated by computing the table (§5.3) and checking against Matt's intuition for the presets he has strong opinions on. Where the framework disagrees, the coefficients are tuned. The calibration procedure:

1. Compute table for all 13 presets at `lingerFactor = 0.5`.
2. Matt reviews the table; flags presets whose computed `maxDuration` disagrees with his intuition.
3. Tune coefficients to reduce flagged rows. Verify other presets' values stay sensible.
4. Iterate until table is acceptable — typically 2–3 coefficient passes.

The empirical observation videos from V.7.6.E become **calibration evidence** (instead of "the source of truth") — they validate or invalidate the framework's predictions for specific presets, and inform coefficient tuning. The framework is the source of truth; observation is calibration.

**V.7.6.C calibration outcome (2026-05-02):**
- **Diagnostic class added.** `is_diagnostic` JSON flag (default false). When true, `maxDuration(forSection:)` returns `.infinity`. Spectral Cartograph is the only preset with the flag. The "manual-switch only / never auto-selected" semantic is the V.7.6.D follow-up.
- **Per-section linger inverted (Option B).** Old §5.2 had ambient=0.30 (shortest) and peak=0.80 (longest), which inverted Matt's intuition that ambient sections are exactly where presets should linger. New per-section factors: ambient=0.80, peak=0.75, comedown=0.65, buildup=0.40, bridge=0.35. Default (section=nil) stays 0.5. The field name `sectionDynamicRange` was renamed to `sectionLingerFactor` to reflect that values are now author-set per-section weights, not derived from audio variance.
- **No formula coefficient changes.** `baseDurationSeconds`, `motionPenalty`, `fatiguePenalty`, `densityPenalty`, `sectionAdjustBase`, `sectionLingerWeight` are unchanged from §5.2 defaults.

**Known data points (locked):**
- **Arachne: 60s** — capped by `naturalCycleSeconds = 60` (build cycle ceiling per §1.2).
- **Spectral Cartograph: ∞** — `is_diagnostic: true`.
- **Glass Brutalist** earlier intuition (~30s) is deferred — the preset is uncertified and far from ready; tuning the formula to one outlier is not the right move at this stage.

### 5.5 Implication for orchestrator

`PresetDescriptor.maxDuration` becomes a computed property, not a JSON field:

```swift
extension PresetDescriptor {
    func maxDuration(forSection section: SongSection) -> TimeInterval {
        computeMaxDuration(preset: self, section: section)
    }
}
```

JSON sidecar gains the `naturalCycleSeconds` field (optional, only declared for presets with fixed cycles). Coefficients live in code (with documentation), not in JSON — so coefficient tuning is a code change reviewed via tests, not a data file edit.

---

## 6. Implementation sequence

All design dimensions locked: §4.3 color source (Option B with full spec), §5 maxDuration framework (formula + calibration loop), §1.3 spider rarity (per-segment cooldown). Nothing is blocking.

The orchestrator change is the load-bearing prerequisite. Arachne refactor is blocked on it. The harness is independent and useful regardless.

| Step | Increment | Scope | Estimated sessions |
|---|---|---|---|
| 1 | V.7.6.1 | **Visual feedback harness.** 1920×1280 PNG renders of any preset against fixtures + reference contact-sheet builder. Independent — useful regardless of which path forward. | ½ |
| 2 | V.7.6.2 | **Orchestrator multi-segment + completion-signal + maxDuration framework.** New `PlannedPresetSegment` type, `SessionPlanner` produces multi-segment plans, `PresetSignaling` protocol, `LiveAdapter` segment-aware. `PresetDescriptor.maxDuration(forSection:)` computed property implementing the §5.2 formula. `naturalCycleSeconds` field added to JSON schema. All existing presets continue to work via the framework's computed values. | 2–3 |
| 3 | V.7.6.C | **Framework calibration pass.** Compute the §5.3 table at average music section dynamics. Matt reviews; flags presets where framework output disagrees with intuition (Glass Brutalist is the locked anchor at ~30s). Coefficients tuned per §5.4 calibration loop (most likely change: nonlinear penalty term for low-motion + high-density combination). Optional supporting evidence: 2-minute videos via V.7.6.1 of a few flagged presets. | 1 + Matt review |
| 4 | V.7.7 | **Arachne v8 — background pass + background webs.** Implement §4.1 step 1 (atmospheric texture, palette per §4.3 Option B mood-driven recipe) and §4.1 step 2 (one or two background dewy webs with refractive drops). Foreground unchanged for now (still V.7.5 build). Visual review against refs `01`/`03`/`04` via harness. | 2 |
| 5 | V.7.8 | **Arachne v8 — foreground build refactor.** Implement §1.2 (incremental construction with chord-segment spiral, drop accretion during build, completion signal at 60s). Pause on spider trigger; resume on spider fade. Per-segment spider cooldown (§1.3). Visual review for build-pace feel. | 2 |
| 6 | V.7.9 | **Arachne v8 — vibration + final polish + cert.** Implement §4.2 (whole-scene tremor on bass). Tune drop counts, brightness, sag magnitude, free-zone size, mood-smoothing window against references via harness. Cert review. | 1–2 |

**Total: 8–11 sessions of implementation work, plus Matt's framework calibration review.** Realistic given Arachne's track record. Each step includes harness-driven visual verification before commit; no more "build for a session, ship to Matt, discover at M7 that it's wrong".

**Order constraints:**
- V.7.6.1 (harness) must complete first — V.7.6.C and V.7.7+ all use it.
- V.7.6.2 (orchestrator + framework) must complete before V.7.7 (Arachne v8 needs multi-segment infrastructure to emit completion signals; needs the framework's `maxDuration` to set its 60s ceiling).
- V.7.6.C (calibration) can run in parallel with V.7.6.2 implementation, or right after — they touch independent code paths and the calibration only needs the formula in the framework.

---

## 7. Open questions

None blocking. Items that may surface during implementation:

- **Foreground web → background migration animation.** When the foreground build completes and Arachne hands off (or the orchestrator transitions early), the in-progress / completed foreground web could either fade out cleanly or migrate to the background pool. Background-pool migration is more visually interesting (the webs accumulate over a session) but requires the next preset selection to know that Arachne is the next preset too. Punt to V.7.8 implementation — start with clean fade.

- **What happens when bass eases mid-spider-pose.** Construction resumes immediately, or does the spider take a moment to depart first? Punt to V.7.9 polish — start with simultaneous fade-out + resume, refine if it reads wrong.

- **Drop hue shifts via vocal pitch.** Listed as optional in §2 audio mapping. Punt to V.7.9 polish — start without, add if the visual needs more variety.

---

## 8. Acceptance criteria

The Arachne v8 implementation is complete when:

1. **Foreground build is visibly happening** — a viewer watching for 30 seconds sees radials extending and the spiral winding. Not a static finished web.
2. **Background dewy webs are visible from frame zero** — the scene is never sparse, even at preset entry.
3. **Drops on background webs read as photorealistic dewdrops** — refraction inverts the background through them, fresnel rim, sharp specular pinpoint. Side-by-side with refs `01`/`03`/`04` via the harness contact sheet.
4. **Spider appears on sustained heavy bass** — within ≤ 2s of trigger. Construction visibly pauses while spider is present.
5. **Web vibration is visible during heavy bass** — whole-scene tremor with audio-rate frequency.
6. **Build cycle completes in ≤ 60s** under typical music. Completion event triggers immediate transition out.
7. **Matt M7 review against references.** No anti-ref `09` (clipart symmetry) or `10` (neon glow) match. Refs `01`, `03`, `04`, `05`, `08` cited as reachable.

---

## 9. Citations and grounding

This spec is grounded in research conducted 2026-05-02, citations in D-072 §References. Key sources:

- **Web construction sequence:** [BBC Earth Beautiful Spider Web Build Time-lapse](https://www.youtube.com/watch?v=zNtSAQHNONo), [Spider Spinning Its Web - Time Lapse](https://www.youtube.com/watch?v=rBPyX5Yq6Y0). These are the visual targets — the construction process is the subject, not the finished surface.
- **Web biology:** [Orb-weaver — Wikipedia](https://en.wikipedia.org/wiki/Orb-weaver_spider), [Patterns in movement sequences of spider web construction (ScienceDirect)](https://www.sciencedirect.com/science/article/pii/S0960982221013221), [British Arachnological Society — Orb Web Construction](https://britishspiders.org.uk/orb-webs).
- **Drop physics:** [Plateau-Rayleigh instability (Wikipedia)](https://en.wikipedia.org/wiki/Plateau%E2%80%93Rayleigh_instability), [In-drop capillary spooling of spider capture thread (PNAS)](https://www.pnas.org/doi/10.1073/pnas.1602451113). Drops are uniform-spaced via a physical instability, not random.
- **Real-time rendering technique:** [NVIDIA GPU Gems 2 ch.19 — Generic Refraction Simulation](https://developer.nvidia.com/gpugems/gpugems2/part-ii-shading-lighting-and-shadows/chapter-19-generic-refraction-simulation), [Tympanus Codrops Rain & Water Effect](https://tympanus.net/codrops/2015/11/04/rain-water-effect-experiments/), [Slomp 2011 - Photorealistic real-time rendering of spherical raindrops](https://onlinelibrary.wiley.com/doi/10.1002/cav.421). Standard industry technique: background-to-texture + drop-as-quad + screen-space refraction.
- **Spider locomotion (for Stalker / spider easter egg):** [Biomechanics of octopedal locomotion (J Exp Biol)](https://journals.biologists.com/jeb/article/214/20/3433/10466/Biomechanics-of-octopedal-locomotion-kinematic-and), [Arachnid locomotion (Wikipedia)](https://en.wikipedia.org/wiki/Arachnid_locomotion). Alternating-tetrapod gait already approximated in current Stalker code.
- **Procedural generation prior art:** [Konstantin Magnus — procegen / Spider Web](https://procegen.konstantinmagnus.de/spider-web), [Houdini Vellum Spider Web (Lesterbanks)](https://lesterbanks.com/2018/12/create-spider-web-houdini-vellum/). The parabolic sag formula `y -= u*(1-u)*amount*length` matches what Houdini uses.

---

**This is a draft for sign-off. No code yet. Tell me where it's wrong; I'll revise. When it's right, I'll implement Step 1 (harness) as the first commit.**
