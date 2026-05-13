// GlassBrutalist.metal — Ray march preset: Brutalist concrete corridor with glass panels.
//
// A stark brutalist corridor of massive concrete pillars and horizontal slabs frames
// narrow near-mirror glass panels positioned between each pillar bay. Low-frequency
// energy causes the entire architecture to breathe and heave; beat pulses produce
// a transient structural impact. The glass panels — rendered as near-perfect metallic
// mirrors — produce high luminance in the lit texture which the SSGI pass then bleeds
// as diffuse indirect light onto the adjacent concrete surfaces.
//
// Materials:
//   Concrete — gritty grey slab + pillar surfaces, high roughness, zero metallic.
//               Procedural Perlin FBM provides tactile variation without a texture sampler.
//   Glass    — cyan near-mirror panels, very low roughness, high metallic.
//               Strong specular IBL → high litTexture luminance → SSGI light bleed.
//
// Audio routing (FeatureVector only — StemFeatures is not passed to sceneSDF or
// sceneMaterial by the preamble forward declarations; use band proxies instead):
//   f.sub_bass + f.low_bass   → pillar Y-scale (architecture heaves with bass stem)
//   f.beat_bass               → transient pillar X/Z-squeeze (kick impact)
//   f.mid                     → glass panel Y-scale (panels breathe with mid content)
//   f.accumulated_audio_time  → slow sinusoidal corridor drift (scene breathes overall)
//
// Band-to-stem proxies:
//   f.sub_bass  ≈ stems.bass_energy   (20–80 Hz; overlapping frequency range)
//   f.beat_bass ≈ stems.drums_beat    (low-frequency onset pulse)
//   f.mid       ≈ stems.vocals_energy (250 Hz–4 kHz mid-range content)
//
// Pipeline: ray_march → ssgi → post_process
//           G-buffer deferred lighting → SSGI indirect bleed → bloom + ACES tone map

// ── Corridor geometry constants ───────────────────────────────────────────────

/// Z spacing between pillar rows (one corridor bay).
constant float GB_CELL_Z      = 7.0f;

/// X distance from the corridor centre-line to the pillar centre.
constant float GB_CORRIDOR_X  = 2.5f;

/// Pillar X and Z half-extents (square cross-section).
constant float GB_PILLAR_HW   = 0.50f;

/// Pillar Y half-height — taller than the floor-to-ceiling gap so that bases
/// and caps are always hidden inside the floor and ceiling slabs.
constant float GB_PILLAR_HH   = 5.5f;

/// Y centre of the horizontal cross-beam that connects each pillar pair at the top.
constant float GB_BEAM_Y      = 3.80f;

/// Glass fin X half-width — narrow vertical fins, not full-wall panels.
/// Two fins per bay at x = ±GB_GLASS_CX leave the corridor centreline
/// open so rays looking down-corridor see a receding vista instead of
/// a screen-filling mirror. Changed from 1.78 → 0.60 in the Option-A
/// redesign to fix the "giant cyan rectangle" framing problem.
constant float GB_GLASS_HW    = 0.60f;

/// X centre-distance of each glass fin from the corridor centre-line.
/// Fin extent is therefore x ∈ [GB_GLASS_CX − GB_GLASS_HW, GB_GLASS_CX + GB_GLASS_HW]
/// = [0.6, 1.8], leaving |x| < 0.6 (the centre channel) as open air.
constant float GB_GLASS_CX    = 1.20f;

/// Glass fin Y half-height — from just above floor (y ≈ −0.95) to just
/// below beam (y ≈ 3.75). Taller than the original panels; reads as a
/// floor-to-beam architectural fin rather than a vitrine window.
constant float GB_GLASS_HH    = 2.35f;

/// Glass fin Y centre. Matches (floor + beam) / 2 ≈ ( −1 + 3.8 ) / 2 = 1.4.
constant float GB_GLASS_CY    = 1.40f;

/// Glass fin Z half-depth (physical thickness of the fin).
constant float GB_GLASS_HD    = 0.05f;

// ── Domain helpers ────────────────────────────────────────────────────────────

/// Correct infinite domain repetition for negative coordinates.
/// fmod-based opRepeat breaks on negative inputs; round() handles them properly.
static inline float gb_repZ(float z, float c) {
    return z - c * round(z / c);
}

// ── Concrete sub-SDF ─────────────────────────────────────────────────────────

/// Signed distance to all concrete elements at world position p.
///
/// Deliberately audio-independent: brutalist architecture reads as solid,
/// permanent mass. Music reactivity is applied via scene lighting + fog
/// (handled in Swift via SceneUniforms per-frame modulation), never by
/// deforming geometry.
static inline float gb_sdConcrete(float3 p) {
    // Floor slab: normal = +Y, plane equation dot(p,(0,1,0)) + 1.0 = 0 → Y = -1.0.
    float dFloor   = sd_plane(p, float3(0.0f, 1.0f, 0.0f), 1.0f);

    // Ceiling slab: normal = -Y, plane equation dot(p,(0,-1,0)) + 5.2 = 0 → Y = 5.2.
    float dCeiling = sd_plane(p, float3(0.0f, -1.0f, 0.0f), 5.2f);

    // Side walls: continuous concrete planes at x = ±GB_CORRIDOR_X.
    float dSideWalls = GB_CORRIDOR_X - abs(p.x);

    // Pillar rows: abs-fold in X collapses both columns into one sd_box evaluation.
    float zR   = gb_repZ(p.z, GB_CELL_Z);
    float3 pP  = float3(abs(p.x) - GB_CORRIDOR_X, p.y, zR);
    float dPillar = sd_box(pP, float3(GB_PILLAR_HW, GB_PILLAR_HH, GB_PILLAR_HW));

    // Horizontal cross-beam spanning the full corridor width at pillar tops.
    float3 bP   = float3(p.x, p.y - GB_BEAM_Y, zR);
    float dBeam = sd_box(bP, float3(GB_CORRIDOR_X + GB_PILLAR_HW, 0.35f, GB_PILLAR_HW));

    return min(min(min(dFloor, dCeiling), dSideWalls), min(dPillar, dBeam));
}

// ── Glass sub-SDF ────────────────────────────────────────────────────────────

/// Signed distance to the glass fins at world position p.
///
/// Two narrow fins per bay, mirrored in X via abs-fold, offset by half a
/// cell in Z so they land between each pillar row.
///
/// - `finCX`: audio-modulated fin centre-distance from the corridor midline.
///   At rest = GB_GLASS_CX (1.20); shrinks when the music is bass-heavy so
///   the corridor *path* between the fins narrows. The architecture (walls,
///   pillars, beam, floor, ceiling) stays static; only the fins move.
static inline float gb_sdGlass(float3 p, float finCX) {
    // Offset by half a cell so fins land between pillar rows, then repeat.
    float zG   = gb_repZ(p.z - GB_CELL_Z * 0.5f, GB_CELL_Z);

    // abs-fold in X collapses both fins into one sd_box evaluation.
    float3 gP  = float3(abs(p.x) - finCX,
                        p.y - GB_GLASS_CY,
                        zG);
    return sd_box(gP, float3(GB_GLASS_HW, GB_GLASS_HH, GB_GLASS_HD));
}

// ── Scene SDF ────────────────────────────────────────────────────────────────

/// Static architecture with one music-driven element: the glass fins'
/// X-position is modulated so the open corridor path between them widens
/// and narrows with the music. The value comes from Swift via
/// `sceneUniforms.cameraForward.w` (a free SIMD4 lane) — both `sceneSDF`
/// and `sceneMaterial` read from the same uniform so the glass/concrete
/// classification stays consistent.
///
/// Forward motion through the corridor is produced by advancing the
/// camera position in Swift each frame; the SDF is never time-offset.
float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems) {
    float finCX = s.cameraForward.w > 0.0f ? s.cameraForward.w : GB_GLASS_CX;
    return min(gb_sdConcrete(p), gb_sdGlass(p, finCX));
}

// ── Scene Material ────────────────────────────────────────────────────────────

// Glass Brutalist ships its stem-independent Option-A design (see D-020):
// architecture stays solid, audio modulates only light/fog/path via the shared
// Swift path.  `stems` is accepted for signature conformance but unused here.
// The glass material's near-zero roughness + high metallic ensure strong
// specular IBL reflection → high luminance in the litTexture → SSGI bleeds
// cyan-tinted indirect diffuse onto adjacent concrete regardless of audio level.
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
    // outMatID stays at the caller's default (0 = standard dielectric); Glass
    // Brutalist materials are rendered through the existing Cook-Torrance path.
    (void)outMatID;
    // `lumen` (LM.2 / D-LM-buffer-slot-8) is the trailing slot-8 buffer used
    // by Lumen Mosaic. Non-Lumen presets ignore it.
    (void)lumen;
    // Re-evaluate sub-SDFs with the SAME audio-reactive fin position used
    // in sceneSDF — otherwise fin edges at a displaced X would classify as
    // concrete when they should be glass (the "glass-turning-to-concrete"
    // bug). Reading from the same scene uniform guarantees consistency.
    float finCX = s.cameraForward.w > 0.0f ? s.cameraForward.w : GB_GLASS_CX;
    float dConcrete = gb_sdConcrete(p);
    float dGlass    = gb_sdGlass(p, finCX);

    if (dGlass < dConcrete) {
        // ── Structural Glass ─────────────────────────────────────────────────
        // Deferred PBR cannot refract, so pure dielectric (metallic=0) glass
        // degenerates to "tinted concrete" because F0=0.04 leaves the IBL
        // specular term at ~4% — albedo × irradiance dominates and reads
        // like a diffuse surface.
        //
        // The fix: raise F0 enough that IBL Fresnel (F_ibl in RayMarch.metal)
        // returns cool *environment reflection*, not the surface tint. Glass
        // then looks like reflective glass rather than painted concrete.
        //
        //   metallic = 0.55 → F0 ≈ 0.46 (high enough to dominate IBL specular)
        //   roughness = 0.02 → crisp, near-perfect mirror reflection
        //   albedo   = deep cool blue — what transmitted light would look like
        //              at grazing angles when Fresnel is low
        albedo    = float3(0.35f, 0.72f, 0.95f);
        roughness = 0.02f;
        metallic  = 0.55f;
    } else {
        // ── Bare Concrete ────────────────────────────────────────────────────
        // Two octaves of Perlin noise provide tactile variation without a
        // texture sampler — fine grain atop large-scale panel mottling.
        float finGrain = perlin2D(p.xz * 5.5f);     // fine surface grain
        float macroVar = perlin2D(p.xz * 1.3f);     // large-scale colour band

        // Grey value: [0.32 … 0.56], slightly warmer (R > B) for aged concrete.
        float grey = mix(0.32f, 0.56f, finGrain * 0.60f + macroVar * 0.40f);
        albedo    = float3(grey, grey * 0.97f, grey * 0.93f);

        // Roughness follows grain — pitted zones are rougher than smooth zones.
        roughness = mix(0.82f, 0.92f, finGrain);
        metallic  = 0.0f;

        // ── Floor stripes for motion cue ─────────────────────────────────────
        // Without Z-varying features, an infinite corridor looks static even
        // as the dolly advances. Painted bright stripes on the floor at each
        // pillar row (z = 0, ±GB_CELL_Z, ±2·GB_CELL_Z…) sweep past as the
        // world moves, giving an unambiguous optical-flow motion cue.
        //
        // Floor check: plane at y = −1, normal +Y. Test against p.y within
        // a small tolerance to avoid striping side-walls/pillars/ceiling.
        if (p.y < -0.95f) {
            float stripePhase = p.z / GB_CELL_Z;
            float stripeT     = fract(stripePhase + 0.5f);        // 0..1 within bay
            // Thin bright band centred at each pillar row:
            float stripe = smoothstep(0.44f, 0.50f, stripeT)
                         - smoothstep(0.50f, 0.56f, stripeT);
            albedo    = mix(albedo, float3(0.95f, 0.90f, 0.78f), stripe);
            roughness = mix(roughness, 0.35f, stripe);  // polished strip
        }
    }
}
