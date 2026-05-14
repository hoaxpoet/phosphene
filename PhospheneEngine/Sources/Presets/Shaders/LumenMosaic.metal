// LumenMosaic.metal — Ray march preset: vibrant backlit pattern-glass panel.
//
// The energetic-dance-partner preset: a single planar glass panel fills the
// camera frame and bleeds 50% past it on every side, so the viewer sees
// only a field of vivid stained-glass cells dancing to the music.
//
// LM.7 — Per-track RGB tint vector. Adds a small per-track tint
// (derived from `lumen.trackPaletteSeed{A,B,C}`) to every cell's
// uniform random RGB, saturate-clamped. Result: each track plays at a
// visibly distinct aggregate mean (warm vs cool vs amber vs teal etc.)
// without restricting per-cell freedom — every cell still independently
// rolls a colour from the full RGB cube, just from a slightly shifted
// sampling window. Per Matt 2026-05-12: *"mean should NOT be
// middle-gray; the mean should be different for each track played."*
// Closes the LM.4.6 "panel-aggregate uniform across tracks" complaint
// while preserving the LM.4.6 per-cell independence contract in spirit.
//
// LM.6 — Cell-depth gradient + optional hot-spot specular. Each cell
// reads as a 3D-ish dome: brightest at the centre (where the backlit
// glass is "thinnest" and most light gets through), darker toward the
// edge (where the lead came / cell boundary casts a shadow band). An
// optional pinpoint specular at the very centre simulates a viewer-
// aligned highlight ("wet glass" sheen). Modulation is on the per-cell
// palette colour *before* the frost diffusion in `sceneMaterial`; the
// SDF relief stays flat (`kReliefAmplitude = 0`, `kFrostAmplitude = 0`)
// per LM.3.2 round 7 / Failed Approach lock — no normal-driven specular
// in the lighting path, no per-pixel dot artifacts. The lighting
// fragment's matID == 1 emission contract is unchanged.
//
// LM.4.6 — Pure uniform random RGB per cell. Each cell INDEPENDENTLY
// picks one of 16M possible colours. No rules, no anchors, no zones,
// no clusters. The hash combines (cellHash, beat step, trackSeed,
// sectionSalt) so the random choice differs per cell, per beat, per
// track, per section. Section salt now reads `lumen.bassCounter / 64`
// (every ~32 s at 120 BPM, resets on track change) — fixed from the
// LM.4.5.3 broken accumulatedAudioTime proxy.
//
// Per Matt 2026-05-11: "EVERY CELL CAN BE INDEPENDENT OF ITS
// NEIGHBORS... I literally want ANY possible color to be possible
// within ANY cell." Anchor distributions and spatial zones explicitly
// rejected. Pure independence is the contract. LM.7 (above) refines
// this: per-cell independence still holds, but the per-track tint
// vector means the *distribution* the cells sample from is shifted
// per track. The reachable colour set shrinks slightly at extreme
// tints (cells whose uniform RGB + tint would land outside [0, 1]
// clamp to the cube face), but every track still samples a
// 3-dimensional region of the cube with mass at every interior point.
// Earlier LM.4.5.4 — Pure uniform random RGB. No rules. Each cell picks a
// colour at random from the full 16M-colour RGB cube. The hash
// combines (cellHash, beat step, trackSeed, sectionSalt) so the
// random choice differs per cell, per beat, per track, per section.
// No HSV indirection, no coupling rule, no mood gamma, no per-track
// hue bias — pure random sampling. All previous LM.4.5.x rules
// retired per Matt's 2026-05-11 ask: "All I am asking you to do
// now is choose at random a color from the 4-billion-color bag."
//
// Per-cell brightness variation lives separately in `lm_cell_intensity`
// (multiplies the colour by [0.3, 1.6] × bar pulse) — gives stained-
// glass brightness diversity without restricting which colours appear.
//
// Section salt: bassCounter / 64 (every ~32 s at 120 BPM). Resets on
// track change. Replaces the broken LM.4.5.3 accumulatedAudioTime
// proxy that never advanced past bucket 0 in production playback.
//
// Caveat: pure random includes pales, grays, and washed cells. If
// the visual is too noisy / too gray-tan-dominant, the next iteration
// can re-introduce constraints (coupling, sat floor, hue region).
// Earlier LM.4.5.2 — Full-cube palette card model with val/sat coupling. Each
// track gets a procedurally-generated "card" of `kCardSize` (48) colours;
// cells pick slots deterministically (cellHash + beat-step ratchet) and
// the colour at each slot is `lm_hash_u32(cardIndex ^ trackSeed)` decoded
// as three uniform HSV samples. Hue spans the full wheel (uniform);
// SATURATION spans the full range [0, 1] (uniform); value spans
// [0.08, 0.95] with arousal-driven gamma bias. **Coupling rule
// (mandatory)**: `val ≤ sat + kValSatCouplingMargin (0.20)` —
// a weak (low-sat) cell is forced to also be dark, so the
// pale/washed/cream-tinted family is unreachable by construction.
// The trackSeed XOR makes two tracks at the same mood produce
// completely different cards.
//
// Why coupling, not a saturation floor (the LM.4.5.1 mistake): pale
// colours and muted colours look almost the same on screen but are
// produced differently. Pale = light + weak (washed-out — the
// rejected v1 failure mode). Muted = dark + weak (dusty rose,
// espresso, sage — real colours). The difference is value, not
// saturation. The coupling rule keeps the muted family and bans
// the pale family without flooring sat — every kind of colour is
// allowed, including charcoals, browns, slates, dusty earth tones,
// and near-greys.
//
// LM.4.5.2 supersedes LM.4.5.1 (sat floor at 0.70 — too restrictive,
// produced jewel-tone-only output) and LM.4.5 v1 (no coupling —
// produced pale washed cells across ~23 % of the panel). LM.4.5
// supersedes LM.3.2's IQ-cosine palette, which floored sat at 0.78
// and val at 0.80 and centred hue ±0.20 around a mood axis —
// every cell sat inside ~5 % of the HSV cube. See `kCardSize` /
// `kValSatCouplingMargin` constants block + `lm_cell_palette`.
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

/// LM.4.5.3 — uncapped per-cell palette + per-track hue bias +
/// per-cell brightness variation + section-driven mutation.
///
/// **No card cap.** Each cell on each beat on each track on each
/// section gets a unique colour from the full 32-bit hash space
/// (~4 billion possibilities, ~16 M distinct after display
/// quantization). 1500 cells × ~480 beats per song × N sections
/// = potentially millions of distinct cell-colour events per song.
///
/// Colour hash:
///   `lm_hash_u32(cellHash ^ uint(step) ^ trackSeed ^ sectionSalt)`
///
/// Decoded as three uniform [0, 1] HSV samples mapped to HSV via:
///   - **Hue**: full wheel uniform, then per-track hue rotation
///     (a track-derived offset shifts the whole wheel) so the same
///     cellHash on different tracks lands at completely different
///     hues. Distribution stays full-range.
///   - **Saturation**: full range [0, 1] uniform.
///   - **Value**: full range mapped to [`kCardValMin`, `kCardValMax`]
///     with arousal-driven gamma bias (calm darker, energetic brighter).
///   - **Coupling rule**: `val ≤ sat + kValSatCouplingMargin (0.05)`.
///     Tightened at LM.4.5.3 from 0.20 — the previous margin admitted
///     borderline pale cells (sat=0.4 + val=0.6). At 0.05 every weak
///     cell is also dark; pale family unreachable by construction.
///
/// **Per-cell brightness variation.** A separate hash byte drives a
/// wide brightness multiplier (`kCellBrightnessMin` to
/// `kCellBrightnessMax` = 0.30 to 1.60), so some cells are dim
/// shadows and some are HDR-bright (over-exposing into bloom via
/// `kLumenEmissionGain = 1.5`). Real stained-glass character —
/// dramatic brightness diversity within a single panel.
///
/// **Section-driven mutation.** `sectionSalt` is derived from
/// `f.accumulated_audio_time` quantized into ~`kSectionPeriodSeconds`
/// (25 s) buckets, hashed with a constant. Each section bucket gives
/// every cell a completely different colour assignment — the
/// palette visibly shifts on each section boundary. (This is a time-
/// quantized proxy for true `StructuralPrediction.sectionIndex`;
/// follow-up may plumb the real section index through `LumenPatternState`.)
constant float kCardValMin              = 0.08f;
constant float kCardValMax              = 0.95f;
/// Coupling margin: maximum amount that value may exceed saturation.
/// 0.05 (LM.4.5.3, tightened from 0.20 at LM.4.5.2) gives effectively
/// `val ≲ sat` — every weak cell is also dark. At sat=0.3, val caps
/// at 0.35 (deep charcoal-pink). At sat=0.5, val caps at 0.55 (mid
/// muted). At sat=0.9, val caps at 0.95 (full bright jewel). The
/// "pale family" (sat=0.3 + val=0.6 cells) is unreachable by
/// construction.
constant float kValSatCouplingMargin    = 0.05f;
/// Per-cell brightness multiplier range. A separate hash byte gives
/// each cell a brightness multiplier in [`kCellBrightnessMin`,
/// `kCellBrightnessMax`]. Cells below 1.0 are dim shadows; cells
/// above 1.0 are over-exposed bright (the bloom kick comes from
/// values > 1.0 in linear space being tonemapped through ACES).
/// 0.30 → 1.60 gives ~5× brightness ratio, the kind of dramatic
/// variation real backlit stained glass exhibits.
/// LM.4.6: tightened from [0.30, 1.60] to [0.85, 1.15]. The wide
/// [0.30, 1.60] range produced ~30% dim/gray cells (intensity 0.3 ×
/// any anchor colour = dark grayish). Within-anchor variety now
/// comes from the kAnchorJitterMagnitude per-RGB jitter (gives
/// hue/sat/val variation around the anchor, not just brightness).
/// The intensity multiplier stays narrow so every cell reads as
/// "lit" rather than "in shadow."
constant float kCellBrightnessMin       = 0.85f;
constant float kCellBrightnessMax       = 1.15f;
/// Section bucket size in beats. `lumen.bassCounter` quantised into
/// integer buckets of this length drives the section salt — palette
/// resets on each bucket boundary. 64 beats ≈ 32 s at 120 BPM, ≈ 38 s
/// at 100 BPM — roughly verse/chorus duration in pop music. The
/// bassCounter resets on track change, so each new track starts at
/// section 0. Replaces the LM.4.5.3 `accumulatedAudioTime / 25`
/// proxy which never advanced (audio-energy accumulator, not time).
/// Follow-up: plumb real `StructuralPrediction.sectionIndex` for
/// music-accurate section boundaries (verse/chorus/bridge alignment).
constant float kSectionBeatLength       = 64.0f;
// LM.4.6: anchor-distribution model retired — the kAnchorJitterMagnitude
// constant lived here. Per Matt 2026-05-11 it added unwanted structure;
// the palette is back to pure uniform random RGB per cell.

/// LM.7 — Per-track RGB tint magnitude. Each cell still samples uniform
/// random RGB independently (LM.4.6 contract preserved). A small
/// per-track tint vector derived from `lumen.trackPaletteSeed{A,B,C}`
/// (each ∈ [-1, +1] from FNV-1a hash of "title | artist") is added to
/// every cell's RGB before saturate-clamp. Result: every track has a
/// visibly different aggregate mean (warm tracks lean orange/amber;
/// cool tracks lean teal/cyan; etc.) while per-cell freedom is
/// preserved — every cell still independently rolls a colour from the
/// full RGB cube, just from a slightly shifted sampling window.
///
/// At kTintMagnitude = 0.25, the per-channel mean shifts up to ±0.20
/// after the saturate clamp (the linear ±0.25 loses ~0.05 to clamp
/// pile-up at 0/1). Some extreme corners (e.g. pure cyan on a maximally
/// warm track where seedA = +1) become unreachable; near-corner is
/// still reachable. This is the agreed-on relaxation of the LM.4.6
/// "every colour reachable in every track" framing — Matt 2026-05-12:
/// *"mean should NOT be middle-gray; the mean should be different for
/// each track played."*
///
/// **Tuning surface (M7 review):** lower (0.15) for subtler per-track
/// distinction with less clamp loss at extremes; raise (0.35) for
/// stronger panel-aggregate variety at the cost of more colour
/// squashing near the cube corners.
constant float kTintMagnitude = 0.25f;
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

/// LM.6 — Cell-depth gradient: cells appear "thicker" at the edges and
/// "thinner" at the centre, mimicking real backlit stained glass where
/// the centre transmits the most light. `kCellEdgeDarkness` is the
/// per-cell multiplier applied at the cell boundary (`v.f1 → v.f2`);
/// the centre stays at 1.0 (full brightness). `kDepthGradientFalloff`
/// controls the effective cell radius — 1.0 = gradient falls off across
/// the full Voronoi cell radius; lower values compress the gradient
/// toward the centre (sharper edge falloff, brighter centre core).
///
/// **Tuning surface (M7 review):** lower `kCellEdgeDarkness` (e.g. 0.30)
/// for a stronger 3D dome effect; raise (0.75) for subtler depth.
/// `kDepthGradientFalloff = 0.7` compresses the bright core; 1.0 spreads
/// it across the full cell.
constant float kCellEdgeDarkness        = 0.55f;
constant float kDepthGradientFalloff    = 1.0f;

/// LM.6 — Hot-spot specular at cell centre. A small, sharp pinpoint at
/// the very centre of each cell brightens that cell's own colour
/// (additive: `colour += hotSpot × kHotSpotIntensity × colour`), so
/// the palette character is preserved — we don't mix toward white, we
/// just over-expose the cell's own hue at the centre point. `kHotSpotRadius`
/// is the fraction of the cell's Voronoi radius where the hot-spot lives
/// (0.15 = inner 15% of cell). `kHotSpotShape` is the pow() exponent for
/// the falloff — higher = sharper pinpoint; lower = softer dome.
/// `kHotSpotIntensity` is the peak brightness boost at the centre point.
///
/// **Tuning surface (M7 review):** set `kHotSpotIntensity = 0` to disable
/// the hot-spot entirely; raise to 0.5+ for an aggressive "wet glass" look.
/// `kHotSpotShape = 8.0` gives a sharper pinpoint; 2.0 gives a softer
/// dome of brightness.
constant float kHotSpotRadius           = 0.15f;
constant float kHotSpotShape            = 4.0f;
constant float kHotSpotIntensity        = 0.30f;

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
    // LM.4.5.3: per-cell brightness varies WIDELY (0.30 to 1.60) so
    // some cells are dim shadows and some over-expose into bloom —
    // dramatic stained-glass brightness diversity. Replaces the
    // narrow [0.85, 1.15] LM.3.2 jitter range. The brightness byte
    // is hashed separately from the colour-hash bytes (uses cellHash
    // bits 24..31 + a mixing constant) so brightness and colour
    // vary independently per cell.
    uint brightnessHash = lm_hash_u32(cellHash ^ 0xB7E15163u);
    float jitterNorm = float((brightnessHash >> 24u) & 0xFFu) * (1.0f / 255.0f);
    float baseIntensity = mix(kCellBrightnessMin, kCellBrightnessMax, jitterNorm);
    float barShape = pow(saturate(barPhase01), kBarPulseShape);
    float barFactor = 1.0f + kBarPulseMagnitude * barShape;
    return baseIntensity * barFactor;
}

/// LM.4.5.4 — pure uniform random RGB. No rules.
///
/// Each cell picks a colour at random from the full 16-million-color
/// RGB cube (3 × 8-bit channels). The hash combines (cellHash, beat
/// step, trackSeed, sectionSalt) so the random choice differs per
/// cell, per beat, per track, per section. No HSV indirection, no
/// coupling rule, no mood gamma, no per-track hue rotation. Pure
/// random sampling.
///
/// Per-cell brightness variation lives separately in `lm_cell_intensity`
/// (multiplies the colour by [0.3, 1.6] × bar pulse). That gives
/// stained-glass brightness diversity without restricting which
/// colours appear.
///
/// Section salt: derived from `lumen.bassCounter / 64` — every 64
/// grid beats (≈ 32 s at 120 BPM) the palette resets. bassCounter
/// resets on track change, so each track starts fresh from section 0.
/// Time-quantised proxy for true `StructuralPrediction.sectionIndex`.
static inline float3 lm_cell_palette(uint cellHash,
                                     constant LumenPatternState& lumen) {
    // Team selection — drives the beat-step ratchet (per-cell colour
    // changes on each team's beat).
    uint teamBucket = cellHash % 100u;
    float teamCounter = 0.0f;
    if (teamBucket < kBassTeamCutoff) {
        teamCounter = lumen.bassCounter;
    } else if (teamBucket < kMidTeamCutoff) {
        teamCounter = lumen.midCounter;
    } else if (teamBucket < kTrebleTeamCutoff) {
        teamCounter = lumen.trebleCounter;
    }

    uint periodBucket = (cellHash >> 8u) & 0x7u;
    float period = 1.0f;
    if (periodBucket >= 7u) { period = 8.0f; }
    else if (periodBucket >= 5u) { period = 4.0f; }
    else if (periodBucket >= 3u) { period = 2.0f; }
    float step = floor(teamCounter / period);

    // Section salt — bassCounter quantised into 64-beat buckets.
    // Resets on track change (bassCounter is reset by setTrackSeed).
    uint sectionSalt = uint(floor(lumen.bassCounter / kSectionBeatLength));
    uint trackSeed   = lm_track_seed_hash(lumen);

    // Pure uniform random RGB per cell. Any of 16M colours equally
    // likely. Cell × beat × track × section all XOR'd into one hash so
    // every (cell, beat, track, section) tuple gets its own colour.
    uint colourHash = lm_hash_u32(cellHash
                               ^ (uint(step) * 0x9E3779B9u)
                               ^ trackSeed
                               ^ (sectionSalt * 0xCC9E2D51u));

    float r = float((colourHash >>  0u) & 0xFFu) * (1.0f / 255.0f);
    float g = float((colourHash >>  8u) & 0xFFu) * (1.0f / 255.0f);
    float b = float((colourHash >> 16u) & 0xFFu) * (1.0f / 255.0f);

    // LM.7 — per-track RGB tint vector. Shifts the aggregate panel mean
    // per track without restricting per-cell freedom (cells still
    // independently sample the full uniform random RGB cube). The
    // saturate-clamp keeps values in rgba8Unorm storage range; the
    // small clamp pile-up at cube faces is the documented trade-off for
    // visible track-to-track aggregate distinction. When all three
    // trackPaletteSeed components are 0 (e.g. regression-harness path
    // where slot-8 is zero-bound), tint is (0,0,0) and behaviour is
    // identical to LM.4.6.
    //
    // **Chromatic projection (Matt 2026-05-12 fix):** the raw tint is
    // projected onto the chromatic plane (perpendicular to the
    // achromatic axis (1,1,1)/√3) by subtracting its mean component.
    // Without this, seed configurations near the achromatic diagonal
    // (e.g. all-positive → +0.25 on all channels) shift the whole
    // panel toward white or black, producing washed/muddy aggregates
    // instead of chromatic ones. Mean-subtraction guarantees a *hue*
    // shift on every track. Side-effect: tracks whose seeds happen to
    // be roughly equal (achromatic-aligned) lose tint strength
    // proportionally and read as neutral — preferred over washed.
    float3 rawTint = float3(lumen.trackPaletteSeedA,
                            lumen.trackPaletteSeedB,
                            lumen.trackPaletteSeedC);
    float meanShift = (rawTint.r + rawTint.g + rawTint.b) * (1.0f / 3.0f);
    float3 trackTint = (rawTint - float3(meanShift)) * kTintMagnitude;
    return saturate(float3(r, g, b) + trackTint);
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
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)f;
    (void)stems;
    (void)ferrofluidHeight;  // V.9 Session 4.5b slot-10; Ferrofluid Ocean only.

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

    // ── LM.6 — Cell-depth gradient ──────────────────────────────────────────
    //
    // Each cell reads as a 3D-ish dome rather than a flat tile: brightest
    // in the middle (where backlit-glass transmission is greatest), darker
    // at the edge. Driven entirely by the Voronoi field at the per-pixel
    // rate `voronoi_f1f2` already runs at — no extra cost. The SDF normal
    // stays flat (`kReliefAmplitude = 0`); this is an albedo modulation,
    // not a geometric perturbation. Same anti-pattern lock as the round-7
    // frost: no SDF relief, no per-pixel normal noise, no dot artifacts.
    float cellRadius = cellV.f2 * kDepthGradientFalloff;
    float depth01 = 1.0f - smoothstep(0.0f, cellRadius, cellV.f1);
    cell_hue *= mix(kCellEdgeDarkness, 1.0f, depth01);

    // ── LM.6 — Hot-spot specular at cell centre ─────────────────────────────
    //
    // Optional small, sharp pinpoint at the very centre of each cell:
    // brightens the cell's own colour rather than mixing toward white, so
    // palette character is preserved. Simulates a viewer-aligned specular
    // highlight on a domed cell. Set `kHotSpotIntensity = 0` to disable.
    float hotSpot = 1.0f - smoothstep(0.0f, kHotSpotRadius * cellV.f2, cellV.f1);
    hotSpot = pow(hotSpot, kHotSpotShape);
    cell_hue += hotSpot * kHotSpotIntensity * cell_hue;

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
