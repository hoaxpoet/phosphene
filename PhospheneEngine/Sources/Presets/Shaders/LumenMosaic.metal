// LumenMosaic.metal — Ray march preset: vibrant backlit pattern-glass panel.
//
// The energetic-dance-partner preset: a single planar glass panel fills the
// camera frame and bleeds 50% past it on every side, so the viewer sees
// only a field of vivid stained-glass cells dancing to the music.
//
// LM.3.2 — Band-routed beat-driven dance model. Each cell is assigned to one
// of four "teams" by `hash(cell_id ^ trackSeedHash) % 100`:
//
//   - 30% bass team    — advances palette step on each bass beat
//   - 35% mid team     — advances palette step on each mid beat (the typical
//                        carrier of melody on real-music playback)
//   - 25% treble team  — advances palette step on each treble beat
//   - 10% static team  — never advances; holds its base palette colour
//                        (cells in the static team are different on each
//                        track because the team hash is XOR'd with the
//                        per-track seed)
//
// Each cell's `period ∈ {1, 2, 4, 8}` is also hashed — fast cells advance
// every team beat, slow cells hold their step for many beats. Pareto-shaped
// distribution (~37.5% period=1, 25% period=2, 25% period=4, 12.5% period=8)
// targets ~50–60% of cells visibly stepping in any given second of energetic
// music — Matt's "bubbling cauldron" register.
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
// Audio routing (LM.3.2):
//   - Per-cell PALETTE STEP advances on rising-edge of the cell's team's
//     beat counter (`lumen.bassCounter` / `midCounter` / `trebleCounter`).
//     Each counter is incremented by the engine on rising-edges of
//     `f.beatBass` / `f.beatMid` / `f.beatTreble`, scaled by `beatStrength`
//     (energy modulation). The shader does `step = floor(counter / period)`
//     to pin each cell to a discrete palette index that ratchets forward.
//   - Per-cell INTENSITY is uniform with a small hash-driven jitter
//     `[0.85, 1.0]` so the panel reads as vivid throughout (no dim
//     backlight gradient). A bar pulse (`f.barPhase01 ^ 8`) adds a brief
//     +30% brightness flash at each downbeat; falls back to no-pulse
//     gracefully when no BeatGrid is installed (`barPhase01` stays at 0).
//   - The four light agents (slot 8 buffer, LM.2 contract §P.4) are still
//     ticked CPU-side for ABI continuity but the `lights[i].intensity` /
//     `lights[i].colorR/G/B` fields are unused by the LM.3.2 shader. The
//     agent loop is retained as zeroed scaffolding.
//   - **LM.4 pattern engine** layers transient brightness spikes on top of
//     the cell field: `radialRipple` (Gaussian-band ring expanding from a
//     hash-derived origin, spawned on rising-edge of `f.beatBass`) +
//     `sweep` (Gaussian-band wavefront crossing the panel from an edge
//     midpoint, spawned on bar-counter rising edges, mood-weighted vs
//     ripple). Patterns INJECT INTENSITY only — the contribution is added
//     to `cell_intensity` AFTER `lm_cell_intensity` is computed, so the
//     wavefront paints the cells' own palette colours brighter (a ripple
//     on a warm-red cell flashes warm-red; on a cool-cyan cell, cool-cyan).
//     Pool capacity 4; overflowing spawns evict the oldest. See
//     `LumenPatternEngine` (CPU) + `lm_evaluate_active_patterns` (this file).
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
/// to voronoi_f1f2(panel_uv, kCellDensity). 15 cells per uv unit gives
/// ≈ 30 cells across the visible frame (uv ∈ [-1, +1]) at 16:9 — fewer,
/// larger cells per Matt 2026-05-09 LM.3.2 review ("the camera can zoom
/// in a little, 50 → 30 cells across"). Cells are large enough that each
/// cell's distinct palette colour reads as a stained-glass tile rather
/// than as confetti. JSON-tunable later via `lumen_mosaic.cell_density`;
/// constant here for LM.3.2. Lipschitz-safe relief + frost amplitudes
/// are unchanged — halving density only halves the SDF gradient, which
/// adds Lipschitz headroom.
constant float kCellDensity = 15.0f;

/// Lipschitz-safe SDF displacement amplitude for the Voronoi domed-cell
/// relief. **Round 7 (2026-05-10): set to 0.** The relief geometry
/// produced sub-pixel normal noise that the frost-scatter lighting
/// path amplified into per-pixel white dots inside cells (Matt
/// 2026-05-10: "Why is there a dot in every colored cell?"). Frost
/// character now comes from cell-edge white-whitening baked into
/// albedo by `sceneMaterial` directly (using the Voronoi `f2 - f1`
/// distance, not a normal-driven path) — see `kFrostBlendWidth` and
/// `kFrostStrength` below. The panel's geometric normal stays a clean
/// flat (0, 0, -1) per pixel; no more per-pixel relief noise.
constant float kReliefAmplitude = 0.0f;

/// Lipschitz-safe SDF displacement amplitude for the in-cell frost.
/// fbm8 at scale 80 reaches gradient ≈ 80; 0.0008 keeps Lipschitz
/// contribution below 0.07.
///
/// **Round 7 (2026-05-10): set to 0.** The fbm8 frost displacement
/// was producing per-pixel central-difference normal deviations that
/// the round-7 frost-scatter lighting path amplified into visible
/// white pixel artifacts ("dots in every cell"). The frost was
/// originally decorative — intended for specular sparkle that the
/// matID == 1 path does not use. Disabling it cleans up the
/// per-pixel dots while preserving the Voronoi cell-relief edge
/// gradient, which remains the only normal feature driving frost
/// scatter at cell ridges. A future round can re-introduce a
/// different frost mechanism (e.g. a procedural noise tile applied
/// in the lighting frag rather than as an SDF displacement) if
/// micro-glints are needed for cert.
constant float kFrostAmplitude = 0.0f;

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

/// LM.3.2 — uniform-cell-intensity baseline. Replaces LM.3.1's agent-static-
/// field model after Matt's 2026-05-09 rejection ("fixed-color cells with
/// brightness modulation; the bright pools dominated the visual story").
/// Cells are uniformly bright with a small per-cell hash jitter so the panel
/// reads as a flat field of vivid colours rather than a backlit gradient.
/// The dance signal lives in *colour change*, not in *brightness change*.
constant float kCellIntensityBase   = 0.85f;
constant float kCellIntensityJitter = 0.15f;   // adds [0, 0.15] from hash

/// LM.3.2 — bar-pulse magnitude. A brief +30% panel-wide brightness flash
/// at each downbeat (driven by `f.barPhase01 ^ 8`) gives the dance a
/// structural pulse on top of the per-cell team-counter advance. When no
/// BeatGrid is installed (`f.barPhase01` stays at 0) the term collapses
/// to 1.0 and there is no pulse — the team-counter dance still fires
/// because the engine increments `barCounter` every 4 bass beats as a
/// fallback (see LumenPatternEngine `_tick` bar-fallback path).
constant float kBarPulseMagnitude = 0.30f;
constant float kBarPulseShape     = 8.0f;

/// LM.3.2 — palette-step size. Each beat-counter step advances the cell's
/// palette phase by this much. 0.137 (≈ 1/φ²) ensures adjacent steps land
/// far apart on the palette wheel — a single bass-team beat moves a fast
/// cell roughly 50° around the hue circle. After ≈ 7 steps the cell has
/// almost completed a full rotation.
constant float kPaletteStepSize = 0.137f;

/// LM.3.2 round 7 (2026-05-10) — frosted-glass diffusion at cell
/// boundaries. The previous round drove frost via an SDF relief
/// displacement + central-differences normal in the lighting frag,
/// which produced sub-pixel normal noise → per-pixel white dot
/// artifacts inside cells. Round 7 abandons normal-driven frost; the
/// diffusion is now applied directly in `sceneMaterial` using the
/// Voronoi `f2 - f1` cell-edge distance — a large-scale, smooth
/// signal that produces clean cell-boundary white-mixing without
/// per-pixel noise.
///
/// `frostiness = 1 - smoothstep(0, kFrostBlendWidth, f2 - f1)`:
///   0 deep inside cell (vivid colour)
///   1 at cell boundary (full white-mix)
/// `kFrostStrength` caps how much white can mix in even at the very
/// boundary — 0.6 gives a soft frost halo without bleaching the cell.
constant float kFrostBlendWidth = 0.04f;
constant float kFrostStrength   = 0.60f;

/// LM.3.2 — team assignment percentages. Buckets summed left-to-right so
/// `bucket = h % 100`:
///   bucket  ∈ [0,  30) → bass team   (30%)
///   bucket  ∈ [30, 65) → mid team    (35%)
///   bucket  ∈ [65, 90) → treble team (25%)
///   bucket  ∈ [90,100) → static team (10%)
constant uint kBassTeamCutoff   = 30u;
constant uint kMidTeamCutoff    = 65u;
constant uint kTrebleTeamCutoff = 90u;

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
/// **Endpoints widened at LM.3.2** so HV-HA and LV-LA produce visibly
/// different palette character (not just permutations of the same colour
/// wheel — the LM.3 narrow endpoints (`a` ∈ [(0.50,0.50,0.55), (0.55,0.45,0.45)])
/// only rotated which cell got which colour, not which colours appeared).
/// LM.3.2 widens the `a` (offset) endpoints so cool→blue-dominant base,
/// warm→red/orange-dominant base. Combined with the `d` complementary→
/// analogous shift, the two moods produce genuinely different colour
/// regions of palette-space. Verified at M7-prep contact-sheet review:
/// HV-HA shows red/yellow/orange dominant, LV-LA shows blue/teal/cyan
/// dominant.
///
/// All endpoints chosen for vivid bold output. NO cream baseline. NO
/// pastel pull. Subdued ≠ desaturated — it just means narrower hue range.
/// Some channel saturation (palette output briefly clipping to 0 or 1)
/// is acceptable and contributes to vividness via the bloom + ACES
/// post-process; this is **not** the LM.2 cream-baseline failure mode.
/// Per CLAUDE.md project rule: muted has no place in Phosphene.
constant float3 kPaletteACool          = float3(0.25f, 0.50f, 0.75f);   // strong blue base
constant float3 kPaletteAWarm          = float3(0.75f, 0.50f, 0.25f);   // strong red base
constant float3 kPaletteBSubdued       = float3(0.40f, 0.45f, 0.55f);   // saturated even at low arousal
constant float3 kPaletteBVivid         = float3(0.65f, 0.65f, 0.65f);   // pushed past LM.3 to avoid pastel midpoints
constant float3 kPaletteCUnison        = float3(1.00f, 1.00f, 1.00f);
constant float3 kPaletteCOffset        = float3(1.00f, 1.20f, 1.50f);   // moderate channel-rate spread
constant float3 kPaletteDComplementary = float3(0.00f, 0.50f, 1.00f);   // wide phase spread → complementary colours
constant float3 kPaletteDAnalogous     = float3(0.00f, 0.05f, 0.15f);   // narrow → analogous

/// Mood-driven palette phase drift — adds a slow whole-palette rotation as
/// valence shifts, on top of the per-cell + audio-time phase. Small enough
/// that it doesn't fight the per-cell hash for hue identity. 0.10 ≈ ⅓ of a
/// palette cycle across the full valence range.
constant float kPaletteMoodPhaseShift = 0.10f;

/// Per-track seed perturbation magnitudes. Each seed component is in
/// `[-1, +1]`; the magnitude here is what it scales to before being added
/// to the palette parameter.
///
/// **LM.3.2 calibration follow-up #2 (2026-05-09)** — the previous magnitudes
/// 0.20/0.20/0.30/0.50 had two failure modes observed in M7-prep: (a) seedB
/// large enough to pull `b` (chroma amplitude) into pastel territory at
/// negative seed values; (b) `a` and `d` perturbations applied *uniformly*
/// across channels (single scalar × float3(s)), which only shifted overall
/// brightness or rotated phase — same colour set, different cell-to-colour
/// mapping. To produce *genuinely different palettes* per track, the
/// shader now applies **sum-to-zero per-channel** perturbations to `a` and
/// `d` (see `lm_apply_track_seed` below), keeping brightness preserved
/// while shifting hue dominance. Magnitudes:
constant float kSeedMagnitudeA = 0.20f;   // per-channel hue shift on a (offset) — keeps a + b ≤ 1.0 (prevents clipping)
constant float kSeedMagnitudeB = 0.05f;   // uniform chroma shift on b — small, can't pull palette pastel
constant float kSeedMagnitudeC = 0.20f;   // uniform rate shift on c — moderate
constant float kSeedMagnitudeD = 0.50f;   // per-channel phase shift on d — large (phase rotation is the workhorse for per-track variety)

/// Default attenuation coefficient for the slot-8 placeholder state
/// (`LumenPatternState.activeLightCount == 0`). The fragment never
/// dereferences a non-existent agent — but kept here so future code
/// changes have the centroid's expected falloff value to compare against.
constant float kLumenDefaultFalloffK = 6.0f;

// ── LM.4 pattern engine tuning constants ───────────────────────────────────
//
// Patterns inject INTENSITY, not COLOUR. Per-cell colour comes from
// `lm_cell_palette`; pattern contributions brighten cells they cross,
// preserving the unified-panel aesthetic (a ripple firing on a warm-red
// cell flashes warm-red brighter; on a cool-cyan cell, cool-cyan brighter).
// The frost halo at cell boundaries (round 7 frost) brightens too —
// intentional and visually correct.
//
// `kPatternBoost` scales the summed pattern contribution before adding
// to `cell_intensity` in `sceneMaterial`. Sized so that the peak combined
// response (silence baseline `[0.85, 1.0]` × bar pulse 1.30 + peak
// pattern 1.0 × kPatternBoost) stays under the D-037 "beat response ≤
// 2× continuous + 1.0" ceiling. Tune in M7 review.

/// Pattern contribution scaling. `cell_intensity += clamp(sum, 0, kPatternMaxSum) × kPatternBoost`.
/// Peak per-cell contribution at a wavefront is therefore ≤ kPatternMaxSum × kPatternBoost.
constant float kPatternBoost = 0.40f;

/// Upper-bound on the summed pattern contribution before scaling by
/// `kPatternBoost`. Overlapping patterns can't unboundedly stack —
/// the cap of 1.0 means any number of simultaneously-active patterns
/// can contribute no more than 1.0 × kPatternBoost = 0.40.
constant float kPatternMaxSum = 1.0f;

/// Radial-ripple maximum radius (cell-uv units, [0, 1] space). At
/// `phase = 1`, the ring centred on `p.origin` has radius √2 ≈ 1.414 —
/// large enough to reach any panel-edge corner from any origin in
/// `[0.05, 0.95]²` (max corner distance ≈ √(0.95² + 0.95²) ≈ 1.343).
constant float kRippleMaxRadius = 1.4142136f;   // √2

/// Radial-ripple Gaussian band width at phase = 0. The shader narrows
/// this as the ring grows so the wavefront sharpens as it expands —
/// near the panel edge the band is `kRippleSigmaBase × 0.3`.
constant float kRippleSigmaBase = 0.10f;

/// Sweep Gaussian band width. Constant across the wavefront's lifetime;
/// the wavefront's *position* sweeps, not its *width*.
constant float kSweepSigma = 0.10f;

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

/// LM.3.2 — integer hash. Mixes a single uint into a uint with good
/// avalanche so adjacent cell ids produce well-separated team and period
/// assignments. (Murmur-style xor-shift mixer; same scheme as Arachne's
/// `arachHashU32`, kept lexically distinct so future shader-utility work
/// can promote one of them into a shared helper without import order
/// drift.)
static inline uint lm_hash_u32(uint x) {
    x ^= 61u;
    x ^= (x >> 16);
    x *= 0x7feb352du;
    x ^= (x >> 15);
    x *= 0x846ca68bu;
    x ^= (x >> 16);
    return x;
}

/// LM.3.2 — derive a single 32-bit hash from the four `trackPaletteSeed`
/// components on `LumenPatternState`. Each seed component is in `[-1, +1]`;
/// we map to a 16-bit integer and concatenate. This is the value XOR'd
/// with `cell_id` to scramble the per-cell team / period assignment per
/// track (different tracks → different cells in the static team, different
/// cells on each band team).
static inline uint lm_track_seed_hash(constant LumenPatternState& lumen) {
    uint a = uint((lumen.trackPaletteSeedA * 0.5f + 0.5f) * 65535.0f);
    uint b = uint((lumen.trackPaletteSeedB * 0.5f + 0.5f) * 65535.0f);
    uint c = uint((lumen.trackPaletteSeedC * 0.5f + 0.5f) * 65535.0f);
    uint d = uint((lumen.trackPaletteSeedD * 0.5f + 0.5f) * 65535.0f);
    return lm_hash_u32((a & 0xFFu)
                     | ((b & 0xFFu) << 8u)
                     | ((c & 0xFFu) << 16u)
                     | ((d & 0xFFu) << 24u));
}

/// LM.3.2 — uniform cell intensity with hash-driven jitter and a global
/// bar pulse. Replaces the LM.3.1 agent-driven static field after Matt's
/// 2026-05-09 rejection ("the bright pools dominated the visual story").
///
/// `cellHash` is the same hash used for team / period assignment in
/// `sceneMaterial` (so the jitter pattern is stable per-track).
/// `barPhase01 ∈ [0, 1)` is `f.barPhase01` from the FeatureVector; when
/// no BeatGrid is installed it stays at 0 and the bar pulse term collapses
/// to 1.0. The team-counter dance still fires because the engine maintains
/// `barCounter` via the "every 4 bass beats" fallback.
///
/// The four light agents on `LumenPatternState` are still ticked CPU-side
/// for ABI continuity but their `intensity` / `colorR/G/B` fields are
/// unused here. `LM.4` may revisit per-cell pattern bursts that read the
/// agent positions.
static inline float lm_cell_intensity(uint cellHash, float barPhase01) {
    float jitterNorm = float((cellHash >> 16u) & 0xFFu) * (1.0f / 255.0f);
    float baseIntensity = kCellIntensityBase + kCellIntensityJitter * jitterNorm;
    float barShape = pow(saturate(barPhase01), kBarPulseShape);
    float barFactor = 1.0f + kBarPulseMagnitude * barShape;
    return baseIntensity * barFactor;
}

/// LM.3.2 — compute the cell's palette sample. Each cell is assigned to
/// one of four teams (bass / mid / treble / static) by `cellHash % 100`
/// and to one of four periods (1, 2, 4, 8) by another hash bucket. The
/// cell's palette phase is its base offset plus `step * kPaletteStepSize`,
/// where `step = floor(team_counter / period)`. Team counters increment
/// once per band-beat in `LumenPatternEngine._tick`, so the cell advances
/// its palette index discretely on each beat — not continuously over
/// time. Static cells (team bucket ≥ 90) hold their base phase forever;
/// they're rotated per track because the team hash is XOR'd with the
/// per-track seed.
///
/// Returns a linear RGB value with each channel in roughly `[0, 1]`. The
/// lighting fragment multiplies by `kLumenEmissionGain (4.0)` then runs
/// through PostProcessChain bloom + ACES, so saturated palette outputs
/// (`b ≈ 0.55` per channel → channel range ≈ `[0, 1.1]`) get tone-mapped
/// gracefully into HDR.
static inline float3 lm_cell_palette(uint cellHash,
                                     constant LumenPatternState& lumen) {
    // Per-cell deterministic base phase, in [0, 1). Pulled from the low
    // 16 bits of the same hash that drives team/period assignment.
    float cell_t = float(cellHash & 0xFFFFu) * (1.0f / 65535.0f);

    // Team selection. Buckets are non-overlapping percentages of [0, 100):
    // 30% bass / 35% mid / 25% treble / 10% static.
    uint teamBucket = cellHash % 100u;
    float teamCounter = 0.0f;
    if (teamBucket < kBassTeamCutoff) {
        teamCounter = lumen.bassCounter;
    } else if (teamBucket < kMidTeamCutoff) {
        teamCounter = lumen.midCounter;
    } else if (teamBucket < kTrebleTeamCutoff) {
        teamCounter = lumen.trebleCounter;
    }
    // else: static team — teamCounter stays 0, step stays 0 forever.

    // Period selection. Pareto-shaped distribution from a 3-bit bucket
    // ∈ [0, 7]: ≈37.5% period=1, 25% period=2, 25% period=4, 12.5%
    // period=8. Many fast cells (visibly stepping every beat) + a long
    // tail of slow cells (stepping only every few bars). Computed in
    // `floor(counter / period)` form so the cell's palette index ratchets
    // forward integer-step rather than drifting smoothly.
    uint periodBucket = (cellHash >> 8u) & 0x7u;
    float period = 1.0f;
    if (periodBucket >= 7u) {
        period = 8.0f;
    } else if (periodBucket >= 5u) {
        period = 4.0f;
    } else if (periodBucket >= 3u) {
        period = 2.0f;
    }
    float step = floor(teamCounter / period);

    // Mood interpolation axes ∈ [0, 1].
    float warm    = clamp(lumen.smoothedValence * 0.5f + 0.5f, 0.0f, 1.0f);
    float arousal = clamp(lumen.smoothedArousal * 0.5f + 0.5f, 0.0f, 1.0f);

    // **HSV-driven palette (LM.3.2 calibration round 4 — 2026-05-10).**
    // The IQ cosine form `palette(t, a, b, c, d) = a + b * cos(2π * (c*t + d))`
    // used in rounds 1–3 was structurally pastel-prone: with `a ≈ 0.5` and
    // per-channel `c` rates desynchronising the three cosines, most cells
    // landed at mid-saturation mid-tones because pure jewel hues require
    // all three channels to hit specific extremes simultaneously, which
    // rarely happens. Switching to `hsv2rgb` gives every cell a saturated
    // hue from the colour wheel by construction; pastel-haze cannot occur.
    //
    // Per-track variety lands as a hue rotation (large) plus a small
    // saturation perturbation. Per-mood character lands as a hue range
    // bias (cool → blue/teal/violet range, warm → red/orange/yellow range)
    // and an arousal-driven saturation/value lift (calm → slightly
    // dimmer, energetic → fully saturated, near-max value).
    //
    // The four `kSeedMagnitude{A,B,C,D}` constants and the eight
    // `kPalette[A,B,C,D][Cool/Warm/Subdued/Vivid/Unison/Offset/
    // Complementary/Analogous]` constants are retained on the file but
    // **unused at LM.3.2 round 4** (the IQ palette was the only
    // consumer); kept for ABI continuity with future round-5+ work that
    // may revisit them. The retired constants are documented in
    // `LumenMosaic.metal` header.

    // Hue: cell-specific base + step ratchet + per-track hue rotation
    // + mood hue bias. Each component contributes additively in [0, 1)
    // and the result is fract'd into a single hue.
    float trackHueShift = lumen.trackPaletteSeedA * 0.30f
                        + lumen.trackPaletteSeedD * 0.50f;

    // Mood hue bias: cool mood pushes hue toward blue (~0.65 on the
    // colour wheel), warm mood pushes toward red-orange (~0.05). This
    // means HV-HA tracks cluster around oranges + yellows + reds, while
    // LV-LA tracks cluster around blues + teals + violets. Spread per
    // cell stays at ±0.20 around the mood centre so adjacent cells can
    // differ noticeably while overall palette character stays mood-
    // appropriate.
    float moodHueCentre = mix(0.65f, 0.02f, warm);   // wraps 0/1 cleanly
    float perCellHue    = (cell_t - 0.5f) * 0.40f;   // ±0.20 around centre
    float hue = fract(moodHueCentre + perCellHue
                    + step * kPaletteStepSize
                    + trackHueShift);

    // Saturation: arousal-driven, floored high so cells never go
    // pastel. The mix range `[0.85, 0.98]` was widened upward at
    // round 4 follow-up (2026-05-10) after track v3 with seed
    // `(1, -1, 1, -1)` rendered pastel — seedB = -1 with magnitude
    // 0.10 dropped sat to 0.75, which combined with high val (0.95)
    // produces pastel character. Tightened sat range + reduced
    // seedB perturbation magnitude to ±0.05 so the worst-case sat
    // stays at `mix(0.85, 0.98, 0) - 0.05 = 0.80` — always vivid.
    float sat = clamp(mix(0.85f, 0.98f, arousal)
                    + lumen.trackPaletteSeedB * 0.05f,
                    0.78f, 1.00f);

    // Value: arousal-driven, floored high so the panel stays bright
    // at calm moods (visual rest character is in the *hue* bias
    // toward cool blues/teals, not in dimness). Per-track seedC
    // modulates by ±0.03 — preserves overall brightness while
    // adding fine-grained track identity.
    float val = clamp(mix(0.85f, 1.00f, arousal)
                    + lumen.trackPaletteSeedC * 0.03f,
                    0.80f, 1.00f);

    return hsv2rgb(float3(hue, sat, val));
}

// ── LM.4 pattern evaluators ────────────────────────────────────────────────
//
// Per-pattern intensity evaluators. Each returns a scalar in [0, 1] for
// a cell centred at `cell_uv` (in the [0, 1]² panel-face UV space; the
// integration site in `sceneMaterial` remaps `cellV.pos` from
// `panel_uv ∈ [-1, +1]` to `[0, 1]` before calling). The sum is clamped
// in `lm_evaluate_active_patterns` and scaled by `kPatternBoost` before
// being added to `cell_intensity`.

/// Radial ripple intensity at `cell_uv`. The wavefront is a Gaussian band
/// centred on the expanding radius `phase × kRippleMaxRadius`; the band
/// narrows as the ring grows so the edge sharpens at the panel boundary.
/// `p.intensity` scales the peak; the engine sets it to
/// `LumenPatternFactory.defaultPeakIntensity = 1.0`.
///
/// `p` is passed by value (small 48-byte struct; MSL allows freely passing
/// `LumenPattern` between address spaces this way, avoiding the
/// thread/constant reference mismatch when the caller has already copied
/// a slot out of `lumen.patterns[]`).
static inline float lm_pattern_radial_ripple(float2 cell_uv, LumenPattern p) {
    float radius = p.phase * kRippleMaxRadius;
    float sigma  = kRippleSigmaBase * (1.0f - 0.7f * p.phase);
    sigma = max(sigma, 1e-3f);                          // floor — never collapses
    float2 origin = float2(p.originX, p.originY);
    float dist = distance(cell_uv, origin);
    float delta = dist - radius;
    float gauss = exp(-(delta * delta) / (2.0f * sigma * sigma));
    return p.intensity * gauss;
}

/// Sweep intensity at `cell_uv`. The wavefront is a Gaussian band whose
/// centre's projection onto `p.direction` is
/// `sweep_position = phase × 2 − 1`. As `phase ∈ [0, 1]`, the band
/// traverses [-1, +1] along the direction axis, entering the panel from
/// outside and exiting on the opposite side.
static inline float lm_pattern_sweep(float2 cell_uv, LumenPattern p) {
    float2 origin = float2(p.originX, p.originY);
    float2 direction = float2(p.directionX, p.directionY);
    float sweep_position = p.phase * 2.0f - 1.0f;
    float projected = dot(cell_uv - origin, direction);
    float delta = projected - sweep_position;
    float gauss = exp(-(delta * delta) / (2.0f * kSweepSigma * kSweepSigma));
    return p.intensity * gauss;
}

/// Sum the per-pattern intensity contributions at `cell_uv` over the
/// `lumen.activePatternCount` active slots, clamp the sum to
/// `kPatternMaxSum`, and return. Caller multiplies by `kPatternBoost`
/// before adding to `cell_intensity`.
///
/// `cell_uv` is the per-fragment uv remapped from `panel_uv ∈ [-1, +1]`
/// to `[0, 1]` — see the integration site in `sceneMaterial` for the
/// remap rationale (within-cell variation is below visual perception and
/// reads as a smooth wavefront).
static inline float lm_evaluate_active_patterns(float2 cell_uv,
                                                constant LumenPatternState& lumen) {
    int count = min(lumen.activePatternCount, 4);
    if (count <= 0) {
        return 0.0f;
    }
    float sum = 0.0f;
    for (int i = 0; i < count; i++) {
        // MSL doesn't permit a runtime-indexed reference into a fixed-
        // size constant array — pull the slot through a switch on `i`.
        // The compiler unrolls this cleanly at the count = 4 ceiling.
        // The copied slot is `thread`-space, which is why the per-pattern
        // helpers accept `LumenPattern` by value (not `constant LumenPattern&`).
        LumenPattern p;
        if (i == 0)      p = lumen.patterns[0];
        else if (i == 1) p = lumen.patterns[1];
        else if (i == 2) p = lumen.patterns[2];
        else             p = lumen.patterns[3];

        if (p.kindRaw == 1) {           // .radialRipple
            sum += lm_pattern_radial_ripple(cell_uv, p);
        } else if (p.kindRaw == 2) {    // .sweep
            sum += lm_pattern_sweep(cell_uv, p);
        }
        // .idle (0) and future kinds contribute 0.
    }
    return clamp(sum, 0.0f, kPatternMaxSum);
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

/// LM.3.2 sceneMaterial — band-routed beat-driven dance.
///
/// Each cell is hashed (with the per-track seed mixed in) and assigned to
/// one of four teams (bass / mid / treble / static). The cell's palette
/// phase is its hash-derived base offset plus `floor(team_counter /
/// period) * kPaletteStepSize` — the cell ratchets one palette step
/// forward each time its team's beat counter crosses a period boundary.
/// Static cells never advance; they're rotated per track because the
/// team hash is XOR'd with the per-track seed.
///
/// Per-cell intensity is uniform with a small hash-driven jitter
/// (`[0.85, 1.0]`) plus a global bar-pulse `1.0 + 0.30 × barPhase01^8`.
/// Replaces the LM.3.1 agent-driven static-light field after Matt's
/// 2026-05-09 rejection — brightness modulation is no longer the visual
/// story; *colour change synchronised to the beat* is.
///
/// All pixels within a Voronoi cell sample the same `cell_id` → the same
/// palette + the same intensity → exactly one colour per cell. That's
/// the stained-glass quantization. Adjacent cells get well-separated
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
    // (`voronoi_f1f2.id` is `int`; we cast to uint for the bit-mixing
    // pipeline below). `v.pos` is the cell-centre uv but unused at LM.3.2
    // — the new uniform-with-jitter intensity model doesn't need a per-
    // cell spatial coordinate.
    VoronoiResult cellV = voronoi_f1f2(panel_uv, kCellDensity);
    uint cell_id = uint(cellV.id);

    // Mix the Voronoi cell id with the per-track seed and run a cheap
    // avalanche hash. The output drives team / period / base-phase /
    // jitter assignments — same hash for all four so the cell's identity
    // is one stable bit-pattern.
    uint cellHash = lm_hash_u32(cell_id ^ lm_track_seed_hash(lumen));

    // Per-cell colour from the procedural palette + team-counter step.
    float3 cell_hue = lm_cell_palette(cellHash, lumen);

    // Per-cell scalar intensity (uniform jitter + bar pulse).
    float cell_intensity = lm_cell_intensity(cellHash, f.bar_phase01);

    // LM.4 — pattern engine contribution. Evaluate the active pattern pool
    // (≤ 4 slots) at the fragment's uv, remapped from `panel_uv ∈ [-1, +1]`
    // into the patterns' `[0, 1]²` UV space (where engine-side origins are
    // hash-derived in `[0.05, 0.95]²` and sweep entries sit on the four
    // edge midpoints). Patterns inject intensity, not colour — the
    // contribution brightens whatever palette colour the cell already
    // carries (the wavefront keeps the cell's identity). The frost halo
    // at cell boundaries (round 7) also brightens, since
    // `albedo = clamp(frosted_hue × cell_intensity, …)` multiplies the
    // boosted intensity through the entire albedo chain.
    //
    // We use the fragment's panel_uv (not a per-cell-quantized centre) so
    // the wavefront reads as a smooth Gaussian band crossing the panel —
    // the per-fragment variation within a cell is below visual perception
    // (cell radius ≈ 0.07 in [0, 1] uv, ripple σ ≈ 0.10 — within-cell
    // intensity variation is sub-pixel-rate smooth). Per-cell colour
    // identity is preserved because `cell_hue` still derives from
    // `cellHash`.
    float2 cell_center_uv = panel_uv * 0.5f + 0.5f;
    float pattern_contribution = lm_evaluate_active_patterns(cell_center_uv, lumen);
    cell_intensity += pattern_contribution * kPatternBoost;

    // Frosted-glass diffusion at cell boundaries (LM.3.2 round 7,
    // 2026-05-10). The Voronoi `f2 - f1` distance is the natural
    // "distance to nearest cell boundary" signal — large inside the
    // cell, drops to 0 at the boundary. Mixing toward white at small
    // `f2 - f1` values produces a clean frost halo where neighbouring
    // cells meet, without the sub-pixel normal noise that the
    // round-5/6 SDF-relief-driven approach introduced. Driven entirely
    // from the Voronoi field at the per-pixel rate that the f1/f2
    // computation already runs at, so no extra cost.
    float frostiness = 1.0f
                     - smoothstep(0.0f, kFrostBlendWidth, cellV.f2 - cellV.f1);
    float3 frosted_hue = mix(cell_hue,
                             float3(1.0f),
                             saturate(frostiness * kFrostStrength));

    // Albedo carries the per-cell colour signal (matID == 1 contract).
    // Multiply frosted palette × intensity; clamp to [0, 1] so the
    // rgba8Unorm G-buffer encoding is loss-free. The matID == 1
    // lighting fragment skips Cook-Torrance and emits this directly
    // (the "frosted glass surface character" is fully baked here in
    // sceneMaterial, not added by the lighting path).
    //
    // **LM.3.2 round 8 (2026-05-10): beat envelope removed.** Round 6
    // dimmed cells between beats to produce a "fade in / fade out
    // like a light turning on and off" pulse cycle. Live session
    // review (Matt 2026-05-10, session 2026-05-10T14-48-52Z) flagged
    // the dark "pulse off" state between beats as too frequent /
    // visually distracting: cells should HOLD their previous state
    // until the next beat advances the palette step, not fade to
    // dark in between. Removing the envelope leaves cells at full
    // brightness; per-beat colour change is the only rhythm-coupled
    // visual signal (plus the bar-pulse downbeat flash baked into
    // `cell_intensity`). The `lm_cell_envelope` helper and
    // `kBeatDecayEnd / kBeatAttackStart` constants are deleted.
    albedo = clamp(frosted_hue * cell_intensity, 0.0f, 1.0f);

    // Pattern-glass material aesthetic from SHADER_CRAFT.md §4.5b.
    roughness = 0.40f;
    metallic  = 0.0f;

    // Flag this pixel as emission-dominated dielectric (D-LM-matid).
    outMatID  = 1;
}
