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

/// Glass panel X half-width — narrower than the corridor gap so a sliver of
/// open air is visible between the glass edge and each pillar face.
constant float GB_GLASS_HW    = 1.78f;

/// Glass panel Y half-height — from just above floor to just below beam.
constant float GB_GLASS_HH    = 2.40f;

/// Glass panel Z half-depth (physical thickness of the pane).
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
/// - yScale: audio-driven pillar Y-stretch (1.0 = rest shape; use in sceneSDF only).
/// - beatSq: transient X/Z-squeeze factor (1.0 = rest shape; use in sceneSDF only).
///
/// sceneMaterial passes (1.0, 1.0) to obtain stable, audio-independent material
/// boundaries while accepting a small sub-pixel seam at deformed geometry boundaries.
static inline float gb_sdConcrete(float3 p, float yScale, float beatSq) {
    // Floor slab: normal = +Y, plane equation dot(p,(0,1,0)) + 1.0 = 0 → Y = -1.0.
    float dFloor   = sdPlane(p, float3(0.0f, 1.0f, 0.0f), 1.0f);

    // Ceiling slab: normal = -Y, plane equation dot(p,(0,-1,0)) + 5.2 = 0 → Y = 5.2.
    float dCeiling = sdPlane(p, float3(0.0f, -1.0f, 0.0f), 5.2f);

    // Side walls: continuous concrete planes at x = ±GB_CORRIDOR_X.
    // Positive inside the corridor, zero at the wall surface.
    // Pillar columns project inward from these walls as engaged pilasters —
    // visible where they protrude past the wall face between cross-beam bays.
    float dSideWalls = GB_CORRIDOR_X - abs(p.x);

    // Pillar rows: abs-fold in X collapses both columns into one sdBox evaluation.
    // pP is in pillar-local space; centre at (GB_CORRIDOR_X, 0, zR).
    float zR   = gb_repZ(p.z, GB_CELL_Z);
    float3 pP  = float3(abs(p.x) - GB_CORRIDOR_X,
                        p.y * yScale,
                        zR);
    float dPillar = sdBox(pP, float3(GB_PILLAR_HW * beatSq,
                                     GB_PILLAR_HH,
                                     GB_PILLAR_HW * beatSq));

    // Horizontal cross-beam spanning the full corridor width at pillar tops.
    float3 bP  = float3(p.x, p.y - GB_BEAM_Y, zR);
    float dBeam = sdBox(bP, float3(GB_CORRIDOR_X + GB_PILLAR_HW, 0.35f, GB_PILLAR_HW));

    return min(min(min(dFloor, dCeiling), dSideWalls), min(dPillar, dBeam));
}

// ── Glass sub-SDF ────────────────────────────────────────────────────────────

/// Signed distance to the glass panels at world position p.
///
/// Panels are offset by half a cell in Z so they sit between each pillar row.
///
/// - glassBreath: mid-energy Y-scale (1.0 = rest height; use in sceneSDF only).
///
/// sceneMaterial passes 1.0 for a stable material boundary.
static inline float gb_sdGlass(float3 p, float glassBreath) {
    // Offset by half a cell so panels land between pillar rows, then repeat.
    float zG   = gb_repZ(p.z - GB_CELL_Z * 0.5f, GB_CELL_Z);

    // Divide Y by glassBreath to scale panel height (non-conformal but small).
    float3 gP  = float3(p.x,
                        (p.y - 1.20f) / glassBreath,
                        zG);
    return sdBox(gP, float3(GB_GLASS_HW, GB_GLASS_HH, GB_GLASS_HD));
}

// ── Scene SDF ────────────────────────────────────────────────────────────────

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s) {
    // ── Continuous energy (primary driver) ───────────────────────────────────
    // 20–250 Hz proxy for bass-stem energy; sub_bass dominates kick + 808.
    float bassEnergy = f.sub_bass + f.low_bass;

    // Pillar Y-scale: architecture breathes taller with bass energy.
    // Range: 1.0 (silence) → ~1.14 (loud bass).
    float yScale = 1.0f + bassEnergy * 0.07f;

    // Glass Y-scale: panels stretch subtly with mid-range content.
    // Range: 1.0 (silence) → ~1.10 (loud mid).
    float glassBreath = 1.0f + f.mid * 0.10f;

    // Slow sinusoidal corridor drift driven by accumulated audio time.
    // Gives the scene a slow lateral sway that scales with musical energy.
    float drift = sin(f.accumulated_audio_time * 0.35f) * 0.14f;
    float3 q = p + float3(drift, 0.0f, 0.0f);

    // ── Beat accent (secondary) ──────────────────────────────────────────────
    // Transient X/Z-squeeze on kick/snare onset — pillars momentarily narrow.
    // Kept small (max 5 %) so beat never overrides the continuous motion.
    float beatSq = 1.0f - f.beat_bass * 0.05f;

    float dConcrete = gb_sdConcrete(q, yScale, beatSq);
    float dGlass    = gb_sdGlass(q, glassBreath);
    return min(dConcrete, dGlass);
}

// ── Scene Material ────────────────────────────────────────────────────────────

// NOTE: FeatureVector is architecturally unavailable here — the preamble
// forward declaration for sceneMaterial does not carry it.  Audio-reactive
// properties (glass emissive intensity, concrete roughness variation) are
// instead encoded in the geometry itself via sceneSDF, or approximated through
// fixed material values chosen for their visual effect at any energy level.
//
// The glass material's near-zero roughness + high metallic ensure strong
// specular IBL reflection → high luminance in the litTexture → SSGI bleeds
// cyan-tinted indirect diffuse onto adjacent concrete regardless of audio level.
void sceneMaterial(float3 p,
                   int matID,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic) {
    // Re-evaluate sub-SDFs at rest shape (no audio deformation) to classify.
    // Small seams at peak-deformation geometry boundaries are imperceptible.
    float dConcrete = gb_sdConcrete(p, 1.0f, 1.0f);
    float dGlass    = gb_sdGlass(p, 1.0f);

    if (dGlass < dConcrete) {
        // ── Structural Glass ─────────────────────────────────────────────────
        // Near-mirror finish: low roughness + high metallic maximises IBL
        // specular contribution in the lighting pass, producing high luminance
        // values in the rgba16Float litTexture.  The SSGI pass then samples
        // these bright pixels and bleed cyan-tinted indirect diffuse light
        // onto adjacent concrete walls and floor.
        albedo    = float3(0.55f, 0.82f, 0.96f);   // cool cyan tint
        roughness = 0.04f;                           // near-perfect mirror
        metallic  = 0.92f;
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
    }
}
