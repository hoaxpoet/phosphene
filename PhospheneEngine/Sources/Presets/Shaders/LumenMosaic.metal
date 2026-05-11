// LumenMosaic.metal — Ray march preset: vibrant backlit pattern-glass panel.
//
// The energetic-dance-partner preset: a single planar glass panel fills the
// camera frame and bleeds 50% past it on every side, so the viewer sees
// only a field of vivid stained-glass cells dancing to the music.
//
// LM.4.5.1 — Saturated stained-glass palette card model. Each track gets a
// procedurally-generated "card" of `kCardSize` (48) colours; cells pick
// slots deterministically (cellHash + beat-step ratchet) and the colour
// at each slot is `lm_hash_u32(cardIndex ^ trackSeed)` decoded as three
// uniform HSV samples. Hue spans the full wheel (uniform); saturation
// is FLOORED at `kSatFloor (0.70)` and uniform within [0.70, 1.00];
// value spans [0.08, 0.95] with arousal-driven gamma bias (calm darker,
// energetic brighter). The trackSeed XOR makes two tracks at the same
// mood produce completely different cards by construction.
//
// Real stained glass is saturated by physics — coloured glass +
// backlight, no near-gray panels in any cathedral window. Diversity
// comes from hue + value, not from sat. Browns are SATURATED dark
// orange (sat 0.85, val 0.30); charcoals are saturated near-black
// (sat doesn't matter at val < 0.15); regal purples are saturated
// deep violet (sat 0.9, val 0.4); slates are saturated dark blue.
// Mid-sat cells (sat 0.3–0.7) produce washed pale cream that reads
// as gray-tinted regardless of value — that's the aesthetic
// failure mode the LM.4.5 v1 implementation produced and Matt
// rejected on real-music re-review (2026-05-11).
//
// LM.4.5.1 supersedes LM.4.5 v1's full-HSV-cube model. The "full
// range [0, 1] saturation" framing in the LM.4.5 prompt was the
// wrong abstraction for stained glass; flooring sat high gives
// every cell identifiable hue identity while preserving the full
// hue × full value × per-track variety the prompt actually wanted.
// LM.4.5 supersedes LM.3.2's IQ-cosine palette, which floored sat
// at 0.78 and val at 0.80 and centred hue ±0.20 around a mood axis —
// every cell sat inside ~5 % of the HSV cube, with no darks and no
// hue variety. See `kCardSize` constants block + `lm_cell_palette`.
//
// Band-routed beat-driven dance (LM.3.2, preserved verbatim). Each cell is
// assigned to one of four "teams" by `hash(cell_id ^ trackSeedHash) % 100`:
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
//   - **LM.4 pattern engine RETIRED at LM.4.4.** The ripple/sweep accent
//     layer was deleted after the third M7 review (Matt 2026-05-11:
//     "barely noticeable ... what value is it really adding?"). The
//     wavefronts were invisible at execution-time-feasible boost levels —
//     they competed with the simultaneous bar pulse for the downbeat
//     moment and lost by area. The LM.3.2 cell-color dance (driven by
//     LM.4.3 grid-wrap counters) + the bar pulse are the entire visual
//     story now. The `LumenPattern` / `LumenPatternKind` /
//     `LumenLightAgent` structs and the `state.patterns[4]` tuple stay
//     in `LumenPatternState` for GPU ABI continuity; the shader doesn't
//     read those slots.
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
/// **LM.4.1 (2026-05-11):** lowered from 0.30 → 0.20 as part of the
/// bleach-out fix. The bar pulse and LM.4 pattern boost stack on the
/// same downbeat frame; cutting both halves the combined peak
/// `cell_intensity` from 1.70 → ~1.20 (cell baseline × 1.20 bar pulse +
/// 1.0 × 0.20 pattern). Still touches the rgba8Unorm 1.0 ceiling on the
/// brightest channel of saturated cells, but stops short of the
/// every-channel-near-white bleach that destroyed cell colour identity
/// at LM.4. Bar pulse remains visible as a panel-wide brightness
/// flash on each downbeat; just less aggressive.
constant float kBarPulseMagnitude = 0.20f;
constant float kBarPulseShape     = 8.0f;

/// LM.4.5.1 — saturated stained-glass palette card model.
///
/// Each track gets a procedurally-generated "card" of `kCardSize`
/// colours. Cells pick slots deterministically (cellHash + beat-step
/// ratchet), then the colour for that slot comes from
/// `lm_hash_u32(cardIndex ^ trackSeed)` decoded as three uniform
/// [0, 1] samples mapped to HSV via:
///
///   - **Hue**: full wheel (uniform [0, 1] → 0–360°). The per-track
///     seed picks WHICH hues populate the card; each cell takes one.
///   - **Saturation**: floored at `kSatFloor (0.70)` and uniform within
///     [0.70, 1.00]. Real stained glass is saturated by physics —
///     coloured glass + backlight, no near-gray panels in any cathedral
///     window. The diversity comes from hue + value, not from sat. A
///     mid-sat range produces washed pale cells that read as gray-tinted
///     cream — the LM.4.5 v1 failure mode Matt rejected (2026-05-11
///     real-music re-review). Browns / regal purples / charcoals /
///     slates are all SATURATED at low value (brown is dark orange,
///     charcoal is near-black at any sat, regal purple is deep
///     saturated violet). Floor at 0.70 produces them; floor below
///     produces washed cells.
///   - **Value**: full range mapped to [`kCardValMin (0.08)`,
///     `kCardValMax (0.95)`] via an arousal-driven gamma bias (calm →
///     gamma 1.8 biases darker, energetic → gamma 0.55 biases brighter).
///     The [0, 1] envelope is preserved — every card contains darks AND
///     brights regardless of mood; only the distribution mode shifts.
///
/// Per-track distinctiveness: the `trackSeed` XOR means track A's
/// card[5] and track B's card[5] are completely different (h, s, v)
/// triples by construction. Same trackSeed + same cardIndex → same
/// colour (determinism). Regression-locked by
/// `LumenPaletteSpectrumTests`.
///
/// **Pastel guardrail retired at LM.4.5.1.** The LM.4.5 v1 guardrail
/// (`sat < 0.3 → val ≤ 0.5`) was downstream of the wrong abstraction;
/// flooring sat at 0.70 makes the forbidden zone unreachable by
/// construction. The CLAUDE.md "no muted palettes" rule is satisfied
/// at the design level — saturated cells cannot be pale.
constant uint  kCardSize             = 48u;
constant float kCardValMin           = 0.08f;
constant float kCardValMax           = 0.95f;
constant float kSatFloor             = 0.70f;
/// Gamma endpoints for arousal-driven VALUE-only distribution bias.
/// arousal = -1 → gamma 1.8 (concave: biases toward darker cells —
/// deep cobalts, deep wines, ruby shadows); arousal = +1 → gamma 0.55
/// (convex: biases toward brighter cells — emeralds, citrines, bright
/// sapphires); arousal = 0 → gamma 1.0 (uniform). Picked so the
/// expected-value gap between calm and energetic moods is large enough
/// to read (≈ ±0.13 on the [`kCardValMin`, `kCardValMax`] range) while
/// both extremes still have ~28 % of samples in the opposite half —
/// neither extreme empties the bright nor dim tail. Saturation is
/// NOT gamma-biased at LM.4.5.1; it's uniform within [`kSatFloor`,
/// 1.00] regardless of mood (saturation should always read as
/// "stained glass", and gamma bias on a [0.7, 1.0] band is
/// imperceptible). Verified by `LumenPaletteSpectrumTests`.
constant float kMoodGammaLowArousal  = 1.80f;
constant float kMoodGammaHighArousal = 0.55f;

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

// ── LM.4.5 — IQ palette constants retired ─────────────────────────────────
//
// The eight IQ palette endpoints (`kPalette[A,B,C,D][Cool/Warm/Subdued/
// Vivid/Unison/Offset/Complementary/Analogous]`), the
// `kPaletteMoodPhaseShift` rotation magnitude, and the four
// `kSeedMagnitude{A,B,C,D}` per-track perturbation magnitudes were all
// deleted at LM.4.5. The IQ cosine palette form `a + b * cos(2π * (c*t +
// d))` was structurally narrow-scope — every cell on a given track sat
// inside a ~5 % slice of the HSV cube, with hue floored ±0.20 around a
// mood-driven centre and saturation/value floored at 0.78 / 0.80. Matt's
// 2026-05-11 review ("I am asking you for VARIETY... Where are the dark
// hues? Where are the regal purples? What about browns and grays?") made
// the breadth limit conclusive. LM.4.5 replaces the entire `lm_cell_palette`
// body with the full-spectrum card model (see `kCardSize` block above).
// Constants gone; the per-track seed plumbing on `LumenPatternState`
// (`trackPaletteSeed{A,B,C,D}`) is preserved — it now flows through
// `lm_track_seed_hash` into the card-slot colour hash unchanged.

/// Default attenuation coefficient for the slot-8 placeholder state
/// (`LumenPatternState.activeLightCount == 0`). The fragment never
/// dereferences a non-existent agent — but kept here so future code
/// changes have the centroid's expected falloff value to compare against.
constant float kLumenDefaultFalloffK = 6.0f;

// ── LM.4.4 — pattern engine constants retired ──────────────────────────────
//
// `kPatternBoost / kPatternMaxSum / kRippleMaxRadius / kRippleSigmaBase /
// kSweepSigma` were deleted at LM.4.4 along with their evaluator helpers
// (`lm_pattern_radial_ripple / lm_pattern_sweep / lm_evaluate_active_patterns`).
// Reason: the ripple/sweep wavefronts were invisible against the
// simultaneous bar pulse — see the LM.4.4 landed-work entry in
// `CLAUDE.md` for the full diagnosis. The slot-8 `LumenPatternState`
// buffer keeps its `patterns[4]` tuple as zeroed scaffolding for GPU
// ABI continuity, but the shader does not read those slots anywhere.

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

/// LM.4.5 — full-spectrum palette card model.
///
/// Each cell picks a slot from a per-track procedural card of `kCardSize`
/// colours. The cell's slot is `(cellHash + step) % kCardSize`, where
/// `step = floor(teamCounter / period)` so the slot ratchets forward
/// integer-step on each team beat (same beat-step semantics as LM.3.2 —
/// only the palette lookup changes). The colour at that slot is
/// `lm_hash_u32(cardIndex ^ trackSeed)` decoded as three uniform [0, 1]
/// samples mapped to HSV via:
///
///   - hue: full wheel, uniform
///   - sat / val: gamma-biased by arousal (calm → darker / less-saturated
///     bias; energetic → brighter / more-saturated bias), then val mapped
///     to [`kCardValMin`, `kCardValMax`]
///   - pastel guardrail: if sat < `kPastelSatCutoff`, val capped at
///     `kPastelValCap` (gives charcoals / browns / slates instead of
///     pastels — CLAUDE.md "no muted palettes" rule)
///
/// Per-track variety lands via `trackSeed` XOR: track A's card[5] and
/// track B's card[5] are completely different (h, s, v) triples by
/// construction. Same track + same cardIndex → same colour (determinism).
///
/// Mood biases the distribution within the card without restricting the
/// envelope: every card contains samples spanning darks / mid-tones /
/// brights regardless of mood, but the average register shifts. Verified
/// by `LumenPaletteSpectrumTests`.
///
/// Returns a linear RGB value with each channel in [0, 1]. The lighting
/// fragment multiplies by `kLumenEmissionGain (1.0)` and runs through
/// PostProcessChain ACES tone-mapping.
static inline float3 lm_cell_palette(uint cellHash,
                                     constant LumenPatternState& lumen) {
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
    // tail of slow cells (stepping only every few bars).
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

    // Card slot — cellHash provides the base offset, step ratchets
    // forward by 1 each team-period boundary. Two cells with adjacent
    // cellHash values can land on completely different colours because
    // the slot-to-colour map (below) is a hash, not a continuous
    // function.
    uint cardIndex = (cellHash + uint(step)) % kCardSize;

    // Per-track colour hash for this card slot. Same track + same
    // cardIndex → identical RGB by construction. Different tracks →
    // different RGB at the same cardIndex → distinct cards.
    uint trackSeed = lm_track_seed_hash(lumen);
    uint colourHash = lm_hash_u32(cardIndex ^ trackSeed);

    // Three uniform [0, 1] samples from the 32-bit hash.
    float h_u = float((colourHash >>  0u) & 0xFFu) * (1.0f / 255.0f);
    float s_u = float((colourHash >>  8u) & 0xFFu) * (1.0f / 255.0f);
    float v_u = float((colourHash >> 16u) & 0xFFu) * (1.0f / 255.0f);

    // Mood biasing — VALUE only (LM.4.5.1). Gamma curve preserves the
    // [0, 1] envelope but shifts the distribution mode. arousal = -1
    // → gamma 1.8 (biases darker, deep jewel shadows); arousal = +1
    // → gamma 0.55 (biases brighter, vivid jewel tones); neutral →
    // gamma 1.0 (uniform). Saturation is uniform within [`kSatFloor`,
    // 1.0] regardless of mood — sat-gamma was retired at LM.4.5.1
    // because the [0.7, 1.0] band is too narrow for gamma bias to
    // read perceptually, and saturation should always look "stained
    // glass" not "moody".
    float arousalNorm = clamp(lumen.smoothedArousal * 0.5f + 0.5f, 0.0f, 1.0f);
    float gamma = mix(kMoodGammaLowArousal, kMoodGammaHighArousal, arousalNorm);
    float v_biased = pow(v_u, gamma);

    // Hue: full wheel, uniform.
    float h = h_u;

    // Saturation: floored at kSatFloor (0.70), uniform within
    // [kSatFloor, 1.0]. Real stained glass is always saturated —
    // browns / regal purples / charcoals / slates are SATURATED at
    // low value, not desaturated at high value. Mid-sat cells
    // (sat 0.3–0.7) read as washed pale cream regardless of value;
    // they have no place in this aesthetic.
    float s = mix(kSatFloor, 1.0f, s_u);

    // Value: mapped to [kCardValMin (0.08), kCardValMax (0.95)] so
    // cells span deep shadow tones to bright jewel tones but never
    // pure black or white. Floor above 0 keeps cells visibly lit
    // against the deferred path's IBL ambient floor; cap below 1.0
    // leaves headroom for the bar pulse +30 % flash without clipping.
    float v = mix(kCardValMin, kCardValMax, v_biased);

    return hsv2rgb(float3(h, s, v));
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
    // **LM.4.4 retired the LM.4 pattern-engine boost** that previously
    // added a Gaussian wavefront contribution here. The wavefront was
    // invisible at execution-time-feasible boost levels (it competed
    // with the bar pulse for the downbeat moment); see the LM.4.4
    // landed-work entry in `CLAUDE.md` for the diagnosis. The LM.3.2
    // per-cell beat-step palette dance + bar pulse are the entire
    // visual story now.
    float cell_intensity = lm_cell_intensity(cellHash, f.bar_phase01);

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
