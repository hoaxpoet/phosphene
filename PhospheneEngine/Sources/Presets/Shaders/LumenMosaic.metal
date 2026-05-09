// LumenMosaic.metal — Ray march preset: vibrant backlit pattern-glass panel.
//
// The energetic-dance-partner preset: a single planar glass panel fills the
// camera frame and bleeds 50% past it on every side, so the viewer sees
// only a field of vivid stained-glass cells dancing to the music. Each
// cell has its own deterministic colour identity from a procedural IQ
// palette keyed on cell hash + audio time + mood (Decision D.4); the four
// per-stem light agents (slot 8 fragment buffer, LM.2 contract §P.4) drive
// per-cell INTENSITY, not colour. LM.4 will add pattern-engine bursts
// (radial ripples, sweeps) on top.
//
// Materials:
//   matID 1 — Pattern glass (single material, panel-wide). Albedo carries
//             backlight intensity; the lighting fragment dispatches on
//             matID == 1 (gbuf0.g) and renders an emission-dominated path
//             (gain × albedo + IBL ambient floor) instead of full
//             Cook-Torrance dielectric. See RayMarch.metal §matID dispatch.
//
// Detail cascade (LM.3 partial — specular sparkle lands at LM.6):
//   Macro      : sd_box panel oversized to bleed past frame (Decision G.1).
//   Meso       : Voronoi domed-cell relief — sharp inter-cell ridges baked
//                into the SDF as a Lipschitz-safe displacement so the G-buffer
//                central-differences normal picks them up.
//   Micro      : fbm8 in-cell frost, 8 octaves of Perlin at scale 80, baked
//                as a smaller SDF displacement on top of the relief.
//   Specular   : the matID == 1 emission-dominated path skips Cook-Torrance
//                entirely; specular sparkle from the frost normal lands at
//                LM.6 polish.
//
// Audio routing (LM.3 / D-LM-d4 / D-LM-e3):
//   - Per-cell COLOUR comes from a procedural IQ palette keyed on the cell
//     hash + accumulated_audio_time + 5 s smoothed mood + per-track seed.
//     Cells visibly cycle through the palette during energetic music; cells
//     rest (hold their hue) at silence. The panel is always vivid — the
//     LM.1/LM.2 cream baseline was retired (see LUMEN_MOSAIC_DESIGN.md §11).
//   - Per-cell INTENSITY comes from the analytical sum over the four light
//     agents at the cell-centre uv (LM.2 contract §P.3 formula). Each agent's
//     intensity is driven by its stem's deviation primitive (D-026) with FV
//     fallback (D-019). Stems brighten cells in their lobe; cell colour is
//     unchanged.
//   - LM.4 will add pattern-engine bursts (radial ripples on drum onsets,
//     sweeps on bar boundaries) that inject extra per-cell brightness without
//     overriding the cell's palette colour (so a ripple takes the colour of
//     the cells it crosses).
//
// References:
//   docs/presets/LUMEN_MOSAIC_DESIGN.md          — design intent + open decisions.
//   docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md
//                                                — pass structure + buffer layout
//                                                  + panel sizing + matID == 1.
//   docs/SHADER_CRAFT.md §4.5b                   — mat_pattern_glass cookbook
//                                                  recipe (height-gradient
//                                                  domed cell + sharp ridge).
//   docs/VISUAL_REFERENCES/lumen_mosaic/         — mandatory / decorative /
//                                                  actively-disregard traits +
//                                                  rubric.
//
// Pipeline: ray_march → post_process (G-buffer deferred + bloom/ACES).
// SSGI is intentionally NOT in the pass list — emission dominates, SSGI's
// contribution is invisible against bright cells, the saved budget keeps
// Tier 2 headroom for the LM.4 pattern engine.

// ── Constants ──────────────────────────────────────────────────────────────

/// Panel SDF half-extents, expressed as a multiple of the frame's
/// world-space half-extents at the panel z-plane. 1.50 = panel bleeds
/// 50% past the visible frame on every side; the viewer never sees a
/// panel boundary or void corner. Per Decision G.1 (design doc §3) +
/// contract §P.1 (frame-edge invariant).
constant float kPanelOversize = 1.50f;

/// Panel z half-thickness. Small (0.02 world units) — primary rays only
/// hit the front face, the back face is for SDF closure.
constant float kPanelThickness = 0.02f;

/// Camera-to-panel distance along the camera forward axis. Matches
/// `scene_camera.position = (0, 0, -3)` + `target = (0, 0, 0)` in
/// LumenMosaic.json. Hardcoded for LM.1 (Decision G.1 fixed camera);
/// if the camera ever moves (G.2/G.3 deferred), recompute from
/// `length(camera_position - target)`.
constant float kFocalDist = 3.0f;

/// Voronoi cell density — passed directly as the inner scale argument
/// to voronoi_f1f2(panel_uv, kCellDensity). 30 cells per uv unit gives
/// ≈ 60 cells across the visible frame (uv ∈ [-1, +1]) at 16:9 — close
/// to Decision C.2's "≈ 50 cells across" target. JSON-tunable later
/// via `lumen_mosaic.cell_density`; constant here for LM.1.
constant float kCellDensity = 30.0f;

/// Lipschitz-safe SDF displacement amplitude for the Voronoi domed-cell
/// relief. The relief field varies from 0 (cell edge) to ≈ 1 (cell
/// centre) over ≈ 0.025 world units, so its gradient magnitude reaches
/// ≈ 40. Multiplying by 0.004 keeps the additional Lipschitz contribution
/// below 0.16, well within the ray march's `t += max(d, 0.002)` step
/// floor. Larger amplitudes overshoot the panel surface.
constant float kReliefAmplitude = 0.004f;

/// Lipschitz-safe SDF displacement amplitude for the in-cell frost.
/// fbm8 at scale 80 reaches gradient ≈ 80; 0.0008 keeps Lipschitz
/// contribution below 0.07.
constant float kFrostAmplitude = 0.0008f;

/// Distance from the panel face inside which `sceneSDF` evaluates the
/// relief + frost displacement; outside this band the SDF returns the
/// raw `box_dist` so distant march samples skip the voronoi + fbm8
/// cost. The band must be wider than the maximum displacement
/// (kReliefAmplitude + kFrostAmplitude = 0.0048) by enough that the
/// G-buffer fragment's eps=0.001 central-differences normal samples
/// always fall inside the band when evaluated at a hit position
/// (box_dist ≈ 0). 0.02 world units = ≈ 4× the maximum displacement;
/// the safety margin also covers cases where the eventual hit's normal
/// eps lands marginally outside the displaced surface. Eliminates ~30×
/// of the voronoi + fbm8 cost per frame at 1080p (sphere tracing only
/// touches the band on the last 1–2 march steps before convergence).
constant float kReliefBandRadius = 0.02f;

/// fbm8 spatial scale for the in-cell frost. Per SHADER_CRAFT.md §4.5b
/// convention (mat_pattern_glass companion frost). 80 cycles per world
/// unit ≈ 16 cycles per cell at kCellDensity = 30, so frost reads as
/// sub-cell micro-texture, not as a competing macro pattern.
constant float kFrostScale = 80.0f;

/// Static-light-field magnitude (LM.3.1). Each agent's POSITION (not its
/// audio-driven intensity) creates a permanent light pool around it via
/// `falloff = 1 / (1 + r² × attenuationRadius)`. Cells under an agent see
/// a strong static field; cells in the gaps between agents see a weak one.
/// This is the **backlight character** — cells aren't uniformly painted;
/// the panel reads as "lit from behind by 4 point sources." 0.50 puts
/// near-agent cells at half brightness from position alone (audio adds on
/// top); corners can drop to ~0.05 even before the safety floor kicks in.
constant float kAgentStaticIntensity = 0.50f;

/// Absolute minimum cell intensity. Catches cells in dead zones (far from
/// every agent) so they don't render as black; well below
/// `kAgentStaticIntensity` so the position-driven light field is the
/// dominant variation source. Per Matt 2026-05-09: silence rests — cells
/// hold their colours, but the panel can dim into dead zones (this is
/// part of the backlight character — it's not supposed to be uniformly
/// lit).
constant float kCellMinIntensity = 0.05f;

/// Per-cell hue cycle rate (LM.3 / Decision D.4). Cells cycle through the
/// procedural palette as `accumulated_audio_time` advances. Larger values
/// = faster cycling = busier visual register.
///
///   0.05  — full hue cycle every ~20 s of energetic music. Calm but visible.
///   0.15  — full cycle every ~7 s. Energetic, dance-floor pace.       ← LM.3 default
///   0.30  — full cycle every ~3 s. Restless, may strobe on quiet tracks.
///   0.50  — full cycle per beat at 120 BPM. Discotheque.
///
/// The accumulated_audio_time accumulator advances faster during loud
/// passages and stops at silence by construction (see CLAUDE.md §AccumulatedAudioTime),
/// so silence freezes the cycle naturally — no separate freeze logic needed.
/// M7-tunable in LM.3 review against a known-BPM track.
constant float kCellHueRate = 0.15f;

/// IQ palette parameters — endpoints interpolated by mood (LM.3 / E.3).
///
/// IQ form: `palette(t, a, b, c, d) = a + b * cos(2π * (c*t + d))`. Each of
/// `a, b, c, d` is a float3 (per-channel control). `t` is the per-cell phase.
///
/// Mood interpolation:
/// - `a` = mix(kPaletteACool, kPaletteAWarm, warmAxis)        ← valence
/// - `b` = mix(kPaletteBSubdued, kPaletteBVivid, arousalAxis) ← arousal
/// - `c` = mix(kPaletteCUnison, kPaletteCOffset, arousalAxis) ← arousal
/// - `d` = mix(kPaletteDComplementary, kPaletteDAnalogous, warmAxis) ← valence
///
/// Per-track seed (`lumen.trackPaletteSeedA/B/C/D`) perturbs the result so
/// two tracks at the same mood produce visibly different palette character.
///
/// All endpoints chosen for vivid bold output. NO cream baseline. NO
/// pastel pull. Subdued ≠ desaturated — it just means narrower hue range.
/// Per CLAUDE.md project rule: muted has no place in Phosphene.
constant float3 kPaletteACool          = float3(0.50f, 0.50f, 0.55f);
constant float3 kPaletteAWarm          = float3(0.55f, 0.45f, 0.45f);
constant float3 kPaletteBSubdued       = float3(0.40f, 0.45f, 0.50f);
constant float3 kPaletteBVivid         = float3(0.55f, 0.55f, 0.55f);
constant float3 kPaletteCUnison        = float3(1.00f, 1.00f, 1.00f);
constant float3 kPaletteCOffset        = float3(1.00f, 1.30f, 1.70f);
constant float3 kPaletteDComplementary = float3(0.00f, 0.33f, 0.67f);
constant float3 kPaletteDAnalogous     = float3(0.00f, 0.10f, 0.20f);

/// Mood-driven palette phase drift — adds a slow whole-palette rotation as
/// valence shifts, on top of the per-cell + audio-time phase. Small enough
/// that it doesn't fight the per-cell hash for hue identity. 0.10 ≈ ⅓ of a
/// palette cycle across the full valence range.
constant float kPaletteMoodPhaseShift = 0.10f;

/// Per-track seed perturbation magnitudes. Each seed component is in
/// `[-1, +1]`; the magnitude here is what it scales to before being added
/// to the palette parameter. Magnitudes deliberately chosen so the
/// perturbation is visible (different tracks look different) without
/// pushing the palette outside the saturated regime.
constant float kSeedMagnitudeA = 0.05f;   // baseline shift  (small)
constant float kSeedMagnitudeB = 0.05f;   // chroma shift    (small)
constant float kSeedMagnitudeC = 0.10f;   // rate shift      (medium)
constant float kSeedMagnitudeD = 0.20f;   // phase shift     (large — colour family character)

/// Default attenuation coefficient for the slot-8 placeholder state
/// (`LumenPatternState.activeLightCount == 0`). The fragment never
/// dereferences a non-existent agent — but kept here so future code
/// changes have the centroid's expected falloff value to compare against.
constant float kLumenDefaultFalloffK = 6.0f;

// ── Helpers ────────────────────────────────────────────────────────────────

/// Visible-frame half-extents at the panel z-plane, derived from the
/// SceneUniforms FOV + aspect ratio + the hardcoded kFocalDist. Returns
/// (half-width-x, half-height-y) in world units. The cell-uv coordinate
/// system uses these as its [-1, +1] basis so cell density is independent
/// of FOV / aspect drift across hardware.
static inline float2 lm_camera_tangents(constant SceneUniforms& s) {
    float yFovTan = tan(s.cameraOriginAndFov.w * 0.5f);
    float aspect  = s.sceneParamsA.y;
    return float2(yFovTan * aspect, yFovTan) * kFocalDist;
}

/// Compute the cell's scalar brightness — the backlight character (LM.3.1).
///
/// Two contributions:
///
/// 1. **Static field** (`static_max × kAgentStaticIntensity`) — driven by
///    agent POSITIONS only, not intensities. The maximum-falloff agent
///    determines the brightness; this gives spotlit character (cells under
///    an agent are brighter than cells equidistant from all agents). At
///    silence this creates the always-on backlight — cells under an agent
///    are clearly brighter than cells in the gaps between agents.
///
/// 2. **Audio field** (`audio_acc`) — sum over agents of `intensity ×
///    falloff`. Music-driven brightness adds on top of the static field.
///    Multiple stems can each contribute additively to the same cell.
///
/// Floored at `kCellMinIntensity` to catch the deepest dead-zone cells.
///
/// Why max-of-falloffs for the static field, not sum: with 4 agents
/// spread across the panel, summing falloffs gives the geometric centre
/// (all agents at medium distance) higher static brightness than cells
/// under a single agent — backwards. Max-of-falloffs gives the cleaner
/// "this cell is in this agent's lobe" character.
static inline float lm_cell_intensity(float2 cell_center_uv,
                                      constant LumenPatternState& lumen) {
    float static_max = 0.0f;
    float audio_acc  = 0.0f;
    int agentCount = min(lumen.activeLightCount, 4);
    for (int i = 0; i < agentCount; ++i) {
        LumenLightAgent a = lumen.lights[i];
        float2 d = cell_center_uv - float2(a.positionX, a.positionY);
        float r2 = dot(d, d) + a.positionZ * a.positionZ + 1.0e-4f;
        float falloff = 1.0f / (1.0f + r2 * a.attenuationRadius);
        static_max = max(static_max, falloff);
        audio_acc  += a.intensity * falloff;
    }
    float total = static_max * kAgentStaticIntensity + audio_acc;
    return max(total, kCellMinIntensity);
}

/// Compute the cell's palette sample (Decision D.4 / E.3). Per-cell hash
/// drives the basic phase; accumulated_audio_time × kCellHueRate adds
/// time evolution (cells visibly cycle during energetic playback);
/// smoothed valence + arousal interpolate the IQ palette parameters
/// between cool/warm and subdued/vivid endpoints; the per-track seed
/// perturbs the parameters so different tracks produce different palette
/// character even at the same mood.
///
/// Returns a linear RGB value with each channel in roughly `[0, 1]`. The
/// lighting fragment multiplies by `kLumenEmissionGain (4.0)` then runs
/// through PostProcessChain bloom + ACES, so saturated palette outputs
/// (`b ≈ 0.55` per channel → channel range ≈ `[0, 1.1]`) get tone-mapped
/// gracefully into HDR.
static inline float3 lm_cell_palette(uint cell_id,
                                     float accumulated_audio_time,
                                     constant LumenPatternState& lumen) {
    // Per-cell deterministic phase, in [0, 1).
    float cell_t = float(cell_id & 0xFFFFu) * (1.0f / 65535.0f);

    // Mood interpolation axes ∈ [0, 1].
    float warm    = clamp(lumen.smoothedValence * 0.5f + 0.5f, 0.0f, 1.0f);
    float arousal = clamp(lumen.smoothedArousal * 0.5f + 0.5f, 0.0f, 1.0f);

    // IQ palette parameters interpolated by mood, then perturbed by the
    // per-track seed. Per-track seed components are in [-1, +1]; we
    // multiply by `kSeedMagnitude*` to scale into the desired
    // perturbation magnitude per parameter.
    float3 a = mix(kPaletteACool, kPaletteAWarm, warm)
             + float3(lumen.trackPaletteSeedA * kSeedMagnitudeA);
    float3 b = mix(kPaletteBSubdued, kPaletteBVivid, arousal)
             + float3(lumen.trackPaletteSeedB * kSeedMagnitudeB);
    float3 c = mix(kPaletteCUnison, kPaletteCOffset, arousal)
             + float3(lumen.trackPaletteSeedC * kSeedMagnitudeC);
    float3 d = mix(kPaletteDComplementary, kPaletteDAnalogous, warm)
             + float3(lumen.trackPaletteSeedD * kSeedMagnitudeD);

    // Phase: per-cell hash + time-driven cycling + small mood-driven shift.
    // accumulated_audio_time naturally stops at silence (energy = 0 →
    // no advance), so silence freezes the cycle without explicit logic.
    float phase = cell_t
                + accumulated_audio_time * kCellHueRate
                + lumen.smoothedValence * kPaletteMoodPhaseShift;

    // V.3 IQ cosine palette (Color/Palettes.metal). Saturated by
    // construction; no cream pull.
    return palette(phase, a, b, c, d);
}

/// Voronoi domed-cell relief field. Returns a per-pixel scalar in
/// [0, ≈ 1]: 1 at cell centres (where v.f1 → 0), 0 at cell edges (where
/// v.f1 → cell_radius). The smoothstep on (f2 - f1) sharpens the falloff
/// to a thin inter-cell ridge — this is what gives pattern glass its
/// "dimple plus crisp seam" character (SHADER_CRAFT.md §4.5b).
///
/// Sampled at panel-face uv, NOT in raw world space, so cell density
/// is decoupled from the panel's world-space size and can be retuned
/// (LM.6) by changing kCellDensity alone.
static inline float lm_cell_relief(float2 panel_uv) {
    VoronoiResult v = voronoi_f1f2(panel_uv, kCellDensity);
    float dome = (1.0f - saturate(v.f1 * kCellDensity));
    float ridge = smoothstep(0.0f, 0.04f, v.f2 - v.f1);
    return dome * ridge;
}

/// In-cell frost field. fbm8 at scale 80 gives 8 octaves of Perlin
/// centred near 0 with practical range ≈ [-0.7, 0.7]. Kept as a raw
/// fbm8 read here; sceneSDF subtracts the value (after centre-shift)
/// as a Lipschitz-safe displacement so the central-differences normal
/// in raymarch_gbuffer_fragment picks up the perturbation. Per
/// SHADER_CRAFT.md §4.5b the frost is the canonical micro layer for
/// pattern glass.
static inline float lm_frost(float3 p) {
    return fbm8(p * kFrostScale);
}

// ── Scene SDF ──────────────────────────────────────────────────────────────

/// Static glass panel — one `sd_box` at z = 0, sized 1.50 × the visible
/// frame's world-space half-extents at the panel plane (so panel edges
/// are never visible). Voronoi domed-cell relief and fbm8 in-cell frost
/// are baked into the SDF as small Lipschitz-safe displacements on top
/// of the box. The G-buffer central-differences normal then picks up
/// per-cell relief + sub-pixel frost variation without any sceneMaterial
/// normal-output channel (the D-021 signature has none).
///
/// `f` and `stems` are accepted for D-021 conformance but unused here —
/// LM.1 has zero audio reactivity per Decision G.1 + design doc §3.
float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems) {
    (void)f;
    (void)stems;

    // Panel half-extents: oversized so the box bleeds past the visible
    // frame on every side. Per contract §P.1.
    float2 cam_t = lm_camera_tangents(s);
    float3 panel_size = float3(cam_t * kPanelOversize, kPanelThickness);
    float box_dist = sd_box(p, panel_size);

    // Band-limited relief + frost evaluation. Sphere tracing visits ~128
    // march samples per pixel; at 1080p with ~50% panel coverage that's
    // ~7M voronoi + ~7M fbm8 calls per frame if every sample evaluates
    // both. Most samples are far from the panel surface where the
    // displacement contribution is noise-floor anyway. Gating on
    // `box_dist > kReliefBandRadius` returns the raw box SDF for the
    // ~99% of march samples that fall outside the band. The eventual
    // hit + its 6 central-differences-normal neighbours all sit within
    // box_dist ≈ ±0.001, well inside the 0.02 band.
    if (box_dist > kReliefBandRadius) {
        return box_dist;
    }

    // Cell-relief displacement in panel-face uv. voronoi_f1f2 ≈ 0.11 ms
    // at 1080p; the gate above limits this evaluation to near-surface
    // samples (typically 1–2 steps before march convergence).
    float2 panel_uv = p.xy / cam_t;
    float relief = lm_cell_relief(panel_uv);
    float frost  = lm_frost(p) - 0.5f;     // re-centre to [-0.5, +0.5]

    // Subtract relief + frost from the box distance so the panel surface
    // bumps outward at cell centres + bumps in/out at frost peaks. Both
    // amplitudes are tuned for Lipschitz safety against the box's unit
    // gradient (see kReliefAmplitude / kFrostAmplitude rationale above).
    return box_dist
         - relief * kReliefAmplitude
         - frost  * kFrostAmplitude;
}

// ── Scene Material ─────────────────────────────────────────────────────────

/// LM.3 sceneMaterial — per-cell colour identity from the procedural IQ
/// palette (Decision D.4 / E.3). Each cell's albedo is the product of:
///
///   1. Its palette colour (per-cell hash + accumulated_audio_time +
///      smoothed mood + per-track seed) — `lm_cell_palette()`.
///   2. Its scalar intensity (sum of the four light agents at the
///      cell's centre uv, floored at `kSilenceIntensity` so cells stay
///      vivid at silence) — `lm_cell_intensity()`.
///
/// All pixels within a Voronoi cell sample the same `cell_center_uv` →
/// the same palette + the same intensity → exactly one colour per cell.
/// That's the stained-glass quantization. Adjacent cells get adjacent
/// palette samples (cell hashes differ → palette phases differ → cells
/// can be on opposite sides of the hue wheel).
///
/// `roughness` / `metallic` are stored in the G-buffer's packed material
/// byte but only affect output when `matID == 0`; for `matID == 1` (this
/// preset) the lighting fragment skips Cook-Torrance entirely so they're
/// cosmetic placeholders.
///
/// `outMatID = 1` flags this hit pixel as emission-dominated dielectric
/// (D-LM-matid). The G-buffer fragment encodes the value into gbuf0.g;
/// the lighting fragment dispatches on it.
void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   constant StemFeatures& stems,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic,
                   thread int& outMatID,
                   constant LumenPatternState& lumen) {
    (void)matID;
    (void)stems;

    // Project hit position into the panel-face uv frame (`[-1, +1]`
    // exactly at the visible frame edges; `[-1.5, +1.5]` at the SDF
    // edges per kPanelOversize). Cell-density is decoupled from the
    // oversize factor by dividing through `cameraTangents` only —
    // contract §P.1 frame-edge invariant.
    float2 cam_t   = lm_camera_tangents(s);
    float2 panel_uv = p.xy / cam_t;

    // Voronoi cell membership. `v.id` is the deterministic per-cell hash
    // (drives palette phase); `v.pos` is the cell-centre uv (drives
    // intensity sampling). `voronoi_f1f2.pos` is in panel-uv units —
    // the utility divides by scale internally (Voronoi.metal:71).
    VoronoiResult cellV = voronoi_f1f2(panel_uv, kCellDensity);
    uint   cell_id        = uint(cellV.id);
    float2 cell_center_uv = cellV.pos;

    // Per-cell colour from the procedural palette (D.4 / E.3).
    float3 cell_hue = lm_cell_palette(cell_id, f.accumulated_audio_time, lumen);

    // Per-cell scalar intensity from the four light agents.
    float cell_intensity = lm_cell_intensity(cell_center_uv, lumen);

    // Albedo carries the per-cell colour signal (matID == 1 contract).
    // Multiply palette × intensity; clamp to [0, 1] so the rgba8Unorm
    // G-buffer encoding is loss-free; the lighting fragment multiplies
    // by kLumenEmissionGain (4.0) to recover perceptual HDR before
    // bloom + ACES.
    albedo = clamp(cell_hue * cell_intensity, 0.0f, 1.0f);

    // Pattern-glass material aesthetic from SHADER_CRAFT.md §4.5b.
    roughness = 0.40f;
    metallic  = 0.0f;

    // Flag this pixel as emission-dominated dielectric (D-LM-matid).
    outMatID  = 1;
}
