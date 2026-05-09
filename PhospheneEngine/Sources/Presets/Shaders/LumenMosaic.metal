// LumenMosaic.metal — Ray march preset: backlit pattern glass panel.
//
// The "still-and-shift register" preset: a single planar glass panel fills
// the camera frame and bleeds 50% past it on every side, so the viewer sees
// only the field of cells filled with light. The 4-light pattern engine
// (slot 8 fragment buffer, LM.2) drives the backlight; LM.4 will add the
// pattern-engine bursts (radial ripples, sweeps) on top.
//
// Materials:
//   matID 1 — Pattern glass (single material, panel-wide). Albedo carries
//             backlight intensity; the lighting fragment dispatches on
//             matID == 1 (gbuf0.g) and renders an emission-dominated path
//             (gain × albedo + IBL ambient floor) instead of full
//             Cook-Torrance dielectric. See RayMarch.metal §matID dispatch.
//
// Detail cascade (LM.1 partial — full cascade lands LM.2 / LM.6):
//   Macro      : sd_box panel oversized to bleed past frame (Decision G.1).
//   Meso       : Voronoi domed-cell relief — sharp inter-cell ridges baked
//                into the SDF as a Lipschitz-safe displacement so the G-buffer
//                central-differences normal picks them up.
//   Micro      : fbm8 in-cell frost, 8 octaves of Perlin at scale 80, baked
//                as a smaller SDF displacement on top of the relief.
//   Specular   : LM.1 carries no specular term (the matID==1 path skips
//                Cook-Torrance entirely; the IBL ambient floor is diffuse).
//                Specular sparkle from the frost normal lands at LM.2 / LM.6
//                if Matt's review judges the panel reads flat. The detail
//                cascade rubric is a LM.9 certification gate, not LM.1.
//
// Audio routing:
//   LM.1 ships zero audio reactivity. The 4-light pattern engine (slot 8 buffer)
//   arrives in LM.2; pattern-engine-driven beats and bar boundaries arrive in
//   LM.4. Per the rendering contract §LM.1 acceptance, the static backlight
//   case is the proof-of-rendering increment.
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

/// LM.1 static backlight, retained as the silence-fixture safety floor for
/// the brief moment between SceneSDF dispatching and the slot-8 pattern
/// state being populated for the first time. Once LumenPatternEngine has
/// produced its first state, the cell-quantized 4-light sum dominates.
/// Kept at a low magnitude (0.05 brightness) so it can never overpower the
/// mood-tinted ambient floor at silence.
constant float3 kLumenInitialBacklight = float3(0.05f, 0.04f, 0.02f);

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

/// Mood tint: maps valence/arousal to a smooth warm/cool axis crossed
/// with a saturation axis. Used for the silence ambient floor so the
/// preset has a coherent mood-specific colour even with no audio
/// reactivity yet. LM.1 reads a static FeatureVector (valence/arousal
/// at zero in the silence fixture); LM.2+ subscribes to live mood.
///
/// Centred at neutral cream (valence=0, arousal=0). Warm axis at
/// valence=+1 reads orange; cool at -1 reads cool blue. Saturation
/// at arousal=+1 picks up the hue; arousal=-1 collapses to cream.
static inline float3 lm_mood_tint(float valence, float arousal) {
    float warm = clamp(valence * 0.5f + 0.5f, 0.0f, 1.0f);
    float sat  = clamp(arousal * 0.4f + 0.4f, 0.0f, 1.0f);

    float3 cool        = float3(0.60f, 0.75f, 1.00f);
    float3 warm_colour = float3(1.00f, 0.65f, 0.40f);
    float3 hue         = mix(cool, warm_colour, warm);

    float3 cream = float3(1.00f, 0.95f, 0.85f);
    return mix(cream, hue, sat);
}

/// Sample the backlight field at the given panel-face uv (LM.2,
/// contract §P.3 / §P.4). Returns a linear RGB value in roughly
/// `[0, ~3]` per channel; the lighting fragment multiplies by
/// `kLumenEmissionGain (4.0)` then runs through PostProcessChain bloom +
/// ACES, so the dynamic range stays headroom-aware.
///
/// The sample is computed at the cell-centre uv (caller's responsibility,
/// per Decision D.1 — uniform color within a cell). Each agent contributes
/// `intensity / (1 + r² × attenuationRadius)` where `r` is the panel-face
/// distance from the cell centre to the agent xy plus the agent's
/// notional `positionZ` depth-spread term. The mood-tinted ambient floor
/// (`mood_tint × ambientFloorIntensity`) is added unconditionally so the
/// panel is never pure black at silence (D-019 + D-037 invariant 1).
///
/// `lumen.activeLightCount` is the truth source for how many agents to
/// walk; LM.2 always sets it to 4 but the loop respects the field so
/// future increments can promote / retire agents without shader changes.
static inline float3 lm_sample_backlight_at(float2 cell_center_uv,
                                            constant FeatureVector& f,
                                            constant LumenPatternState& lumen) {
    // Walk the active agents. Loop bound is a small fixed integer; the
    // compiler unrolls cleanly. `i < min(4, count)` guards the array
    // access against a placeholder buffer where `activeLightCount`
    // happens to be > 4 (the zero-init placeholder leaves it at 0,
    // so this guard is belt-and-braces).
    float3 acc = float3(0.0f);
    int agentCount = min(lumen.activeLightCount, 4);
    for (int i = 0; i < agentCount; ++i) {
        LumenLightAgent a = lumen.lights[i];
        float2 d = cell_center_uv - float2(a.positionX, a.positionY);
        float r2 = dot(d, d) + a.positionZ * a.positionZ + 1.0e-4f;
        float falloff = a.intensity / (1.0f + r2 * a.attenuationRadius);
        acc += float3(a.colorR, a.colorG, a.colorB) * falloff;
    }

    // Ambient floor: mood-tinted, scaled by the buffer's intensity field
    // so the JSON `lumen_mosaic.ambient_floor_intensity` is the single
    // source of truth (Swift CPU side wires it into the buffer each frame).
    float3 ambient = lm_mood_tint(f.valence, f.arousal) * lumen.ambientFloorIntensity;
    return acc + ambient + kLumenInitialBacklight;
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

/// Pattern-glass material parameters for the panel. The albedo carries
/// the cell-quantized backlight signal — sampled once per cell from the
/// slot-8 LumenPatternState (4 audio-driven agents) and held constant
/// across all pixels inside the cell, per Decision D.1.
///
/// roughness / metallic stay near the SHADER_CRAFT.md §4.5b values for
/// dielectric-style glass character if a future preset re-uses matID 0,
/// but for matID == 1 (this preset) the lighting fragment skips
/// Cook-Torrance entirely so they're cosmetic placeholders only.
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

    // Cell quantization (Decision D.1): the same Voronoi as `lm_cell_relief`
    // but here we want `v.pos` (cell-centre uv in input space) rather than
    // the f1/f2 ridge fields. `voronoi_f1f2.pos` is already in panel-uv
    // units (the utility divides by scale internally — Voronoi.metal:71).
    VoronoiResult cellV = voronoi_f1f2(panel_uv, kCellDensity);
    float2 cell_center_uv = cellV.pos;

    // Cell-quantized backlight: 4 audio-driven agents sampled at the
    // cell centre. `sample_backlight_at` adds the mood-tinted ambient
    // floor so the panel is non-black at silence (D-019 + D-037 inv. 1).
    float3 backlight = lm_sample_backlight_at(cell_center_uv, f, lumen);

    // Albedo carries the backlight signal (matID == 1 contract). Clamp
    // to [0, 1] so the rgba8Unorm G-buffer encoding is loss-free; the
    // lighting fragment then multiplies by `kLumenEmissionGain` (4.0)
    // to recover perceptual HDR before bloom + ACES. Bright cells where
    // multiple agents converge clip into the upper rgba8Unorm bin and
    // get their HDR back via the gain — the loss is < 1 % of cells in
    // typical playback.
    albedo = clamp(backlight, 0.0f, 1.0f);

    // Pattern-glass material aesthetic from SHADER_CRAFT.md §4.5b. These
    // values are stored in the G-buffer's packed material byte but only
    // affect output when matID == 0; for matID == 1 they're cosmetic
    // placeholders that future presets can keep as a dielectric
    // baseline.
    roughness = 0.40f;
    metallic  = 0.0f;

    // Flag this pixel as emission-dominated dielectric. The lighting
    // fragment in RayMarch.metal reads gbuf0.g and dispatches on this
    // value (LM.1 / D-LM-matid).
    outMatID  = 1;
}
