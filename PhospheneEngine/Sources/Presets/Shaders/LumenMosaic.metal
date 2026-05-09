// LumenMosaic.metal — Ray march preset: backlit pattern glass panel.
//
// The "still-and-shift register" preset: a single planar glass panel fills
// the camera frame and bleeds 50% past it on every side, so the viewer sees
// only the field of cells filled with light. Audio (LM.2+) drives a small
// field of light agents behind the glass; LM.1 ships static warm-amber
// backlight as the proof-of-rendering increment.
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

/// fbm8 spatial scale for the in-cell frost. Per SHADER_CRAFT.md §4.5b
/// convention (mat_pattern_glass companion frost). 80 cycles per world
/// unit ≈ 16 cycles per cell at kCellDensity = 30, so frost reads as
/// sub-cell micro-texture, not as a competing macro pattern.
constant float kFrostScale = 80.0f;

/// LM.1 static backlight color: warm amber. Replaced in LM.2 by a
/// 4-light analytical sample over panel face uv. This single constant
/// is the only color a LM.1 panel can show (modulo the small mood
/// ambient floor below).
constant float3 kLumenStaticBacklight = float3(0.95f, 0.60f, 0.30f);

/// Mood-tinted ambient floor magnitude. Combines with mood_tint() for
/// the panel's silence-fallback colour (D-019). Small enough that the
/// static backlight dominates in LM.1; LM.2's continuous-energy lights
/// will scale comparably.
constant float kAmbientFloorIntensity = 0.04f;

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

/// LM.1 backlight sampling: returns a static warm-amber colour plus a
/// tiny mood-tinted ambient floor so the panel reads as coloured at all
/// times (D-019 silence fallback). LM.2 replaces this with an analytical
/// sum over 4 audio-driven light agents read from the slot 8 fragment
/// buffer. The function takes a cell_seed argument (unused in LM.1) so
/// the call-site signature stays stable when LM.2 promotes per-cell
/// sampling.
static inline float3 lm_backlight_static(float2 cell_seed,
                                          constant FeatureVector& f) {
    (void)cell_seed;
    float3 ambient = lm_mood_tint(f.valence, f.arousal) * kAmbientFloorIntensity;
    return kLumenStaticBacklight + ambient;
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

    // Cell-relief displacement in panel-face uv. Sampling the relief
    // field at every SDF query is acceptable on Apple Silicon — the
    // central-differences normal already evaluates sceneSDF six times
    // per hit, and voronoi_f1f2 is ≈ 0.11 ms at 1080p.
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
/// the backlight signal — for LM.1 a static warm-amber + mood ambient
/// floor; LM.2 replaces this with an analytical sum over light agents.
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
                   thread int& outMatID) {
    (void)matID;
    (void)stems;

    // Cell coordinate for future per-cell backlight sampling (LM.2).
    // For LM.1 the backlight is uniform across the panel, so v0 itself
    // isn't read — but we keep the call-site stable so LM.2's per-cell
    // sample only changes lm_backlight_static -> lm_backlight_at(...).
    float2 cam_t = lm_camera_tangents(s);
    float2 panel_uv = p.xy / cam_t;
    VoronoiResult v0 = voronoi_f1f2(panel_uv, kCellDensity);
    float2 cell_seed = v0.pos;

    // Backlight signal carried in albedo (matID == 1 contract). Clamped
    // to [0, 1] so the rgba8Unorm G-buffer encoding is loss-free in the
    // single-cell case; the lighting fragment then gains by 4× to recover
    // perceptual HDR. For LM.2+ where multiple agents may sum > 1, the
    // clamp will become an artistic compromise that the LM.6 polish pass
    // can revisit.
    float3 backlight = lm_backlight_static(cell_seed, f);
    albedo    = clamp(backlight, 0.0f, 1.0f);

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
