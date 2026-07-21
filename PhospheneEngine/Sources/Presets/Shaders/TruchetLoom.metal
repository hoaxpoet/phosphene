// Truchet Loom — Multiscale curved-Truchet op-art weave (PG.4, direct pass).
//
// A woven labyrinth of curved Truchet tiles that subdivide into smaller tiles
// of the SAME weave when the music gets busy (rising spectral flux → nested
// sub-tiles) and merge back into large sweeping arcs when it thins. Musical
// complexity rendered as geometric complexity. Crisp `direct` fragment — no
// feedback (feedback would smear the fine paths; D-029, the anti-reference).
//
// PORTING (FA #73 — port, don't first-principles):
//   - Arc SDF: Inigo Quilez's canonical two-quarter-arc Truchet tile — per-cell
//     hash picks one of two orientations; distance to the nearer of two
//     corner-centred r=0.5 circles connects edge midpoints into continuous
//     winding paths across cells. (IQ "Truchet tiles", iquilezles.org/articles/truchet.)
//   - Multiscale recursion: Christopher Carlson's "Multi-Scale Truchet Patterns"
//     rule — successive tiles scaled by 1/2, smaller tiles placed on top of
//     larger. Cross-referenced against IQ's multiscale Truchet (Shadertoy 4t3BW4).
//     (Shadertoy source is Cloudflare-blocked from offline retrieval, so the
//     recursion is authored from Carlson's published rule + IQ's arc recipe, not
//     copied line-for-line; the arc math and the ½-scale hierarchy are the
//     load-bearing borrowed components.)
//
// SUBDIVISION CROSSFADE: a continuous global "level" (uniform for PG.4.1) selects
// how deep the weave subdivides. Each level's sub-arcs reveal by a per-PARENT-cell
// smoothstep of (level - L), so a coarse tile's four children fade in together as
// its big arc fades out — subdivision ANIMATES rather than pops. A per-parent hash
// jitters the reveal threshold so subdivision spreads across the field like a wave
// (the self-similar "nesting" read) instead of the whole canvas flipping at once.
// Recursion depth is capped at 3 (Restrained default, DECISION-NEEDED PG.4.1 §9).
//
// AUDIO ROUTING (full PG_4 §A4 — one primitive per layer, FA #67):
//   - Subdivision density (HERO) ← SMOOTHED spectral_flux. Read as a single CPU-side
//     EMA float from SpectralHistory buffer(5) slot 3390 (SpectralHistoryBuffer.append).
//     spectral_flux LITERALLY measures the thing we map (broadband busyness) and is
//     reliably alive across genres (PG_0 §3). Continuous variable soft-saturated into a
//     level, NEVER an absolute threshold on an AGC-normalized energy band (FA #31/D-026).
//   - Global drift (flow) ← f.arousal SPEED on an f.time wall-clock BASELINE (advances
//     at silence, D-037; f.time is not a second audio driver, FA #67).
//   - Per-beat tile flips (RHYTHM, PG.4.2) ← f.beat_phase01 (cached grid) + the
//     SpectralHistory beat_index counter (slot 3391). A bounded hash-selected SUBSET
//     (~22%) of tiles re-route their arc each beat; the target seed advances with
//     beat_index so the re-routing EVOLVES, and it crossfades over beat_phase01 so it
//     animates (not a pop). D-157: bounded footprint + orientation-swap keeps global
//     luminance steady (same ink coverage). Gated by f.pulse_amp01 → zero at
//     cold-start/silence (the cold-start phase contract; wrong-phase beats stay silent).
//   - Per-path hue teams (COLOUR, PG.4.2) ← f.spectral_centroid. Coarse spatial regions
//     get a quantised hue TEAM (coherent along paths → coloured ribbons, not per-cell
//     rainbow noise); centroid slowly phases the whole set. Colour, not motion.
//   - Path glow accent (PG.4.2, optional/subtle) ← f.bass_dev. A bounded additive glow
//     on the freshly-subdivided (high-depth) ribbons on bass onsets; drop if it competes.
//
// SILENCE (D-037): smoothed flux ≈ 0 → level ≈ base → coarse large-arc weave, no
// subdivision, no flips (pulse_amp01 = 0), drifting slowly on f.time. Non-black.

// MARK: - Constants

constant float  kTL_baseTiles   = 3.5;   // big arcs across the short axis at level 0
constant int    kTL_maxDepth    = 3;     // recursion cap (Restrained default)
constant float  kTL_lineW       = 0.062; // arc half-width in cell space
constant float  kTL_openJitter  = 0.9;   // per-parent reveal-threshold spread
constant float  kTL_levelBase   = 0.40;  // level at silence (coarse weave)
// spectral_flux is running-max normalized to [0,1] upstream (MIRPipeline.normalizeFlux);
// its ~0.35 s EMA typically sits ~0.1–0.5 sustained (spiking higher on drops). gain 2.5
// spreads that band across ~1 (quiet) → ~2.5 (busy) → 3 (peak) — the Restrained curve
// (DECISION-NEEDED §9). First-pass; calibrate against real-session flux p50/p95 at M7.
constant float  kTL_fluxGain    = 2.5;   // soft-saturation gain on smoothed flux
constant float  kTL_flipFrac    = 0.22;  // PG.4.2 — fraction of tiles that re-route per beat
constant float  kTL_glowGain    = 0.28;  // PG.4.2 — bounded bass-onset ribbon glow
constant float  kTL_hueTeams    = 5.0;   // PG.4.2 — quantised hue-team count
constant float  kTL_hueWarp     = 0.85;  // PG.4.3 — organic warp of the hue-team block edges
constant float  kTL_grain       = 0.028; // PG.4.3 — subtle paper grain (§A2 breakup)

// Azulejo-derived deep GROUND (PG_4 §A6; ref 04_palette_op_art_tile.jpg). Deep cobalt,
// not black — pale-tone ≤ 30 %, FA #45. Ribbon colour is a per-region HUE TEAM (PG.4.2,
// hsv), phased by spectral_centroid; the ground stays fixed for op-art contrast.
constant float3 kTL_ground = float3(0.020, 0.045, 0.140);

// MARK: - Truchet arc SDF (IQ canonical)

/// Distance to the two quarter-arcs of one Truchet cell. `f` is cell-centred in
/// [-0.5, 0.5]; `h` (0..1) picks the orientation. Radius-0.5 arcs centred on two
/// opposite corners connect the cell's edge midpoints — the pieces join edge-to-edge
/// into continuous winding paths (the defining Truchet property).
static inline float tl_arc(float2 f, float h) {
    if (h < 0.5) { f.x = -f.x; }                 // two orientations
    const float2 c = float2(0.5, 0.5);
    float d = abs(length(f - c) - 0.5);
    d = min(d, abs(length(f + c) - 0.5));
    return d;
}

/// Anti-aliased arc coverage for one cell orientation. `aa` is the fragment's
/// cell-space footprint (orientation-independent, computed once by the caller).
static inline float tl_arcCov(float2 f, float h, float aa) {
    float d = tl_arc(f, h);
    return smoothstep(kTL_lineW + aa, kTL_lineW - aa, d);
}

/// Cheap smooth (C1) single-octave value noise, centred at 0 (PG.4.3). Four hash
/// lattice lookups + a smoothstep bilerp — ~8× cheaper than an fBM, plenty to make
/// the hue-team block edges wander organically without the perlin3d cost.
static inline float tl_vnoise(float2 p) {
    float2 i = floor(p), fp = fract(p);
    float2 u = fp * fp * (3.0 - 2.0 * fp);
    float a = hash_f01_2(i);
    float b = hash_f01_2(i + float2(1.0, 0.0));
    float c = hash_f01_2(i + float2(0.0, 1.0));
    float d = hash_f01_2(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) - 0.5;
}

// MARK: - Multiscale weave

/// Coverage (0 = ground, 1 = ribbon core) + a depth shade (0 coarse → 1 finest)
/// for the woven field at continuous subdivision `level`, sampled at tiling
/// coordinate `t`. Coarse-to-fine accumulation with per-parent-cell reveal so
/// subdivision crossfades smoothly (Carlson's rule).
///
/// PG.4.2 per-beat flips: a bounded hash-selected subset of tiles re-route their
/// arc each beat. `beatIdx` (monotonic cached-grid beat counter) advances the
/// target orientation seed so the re-routing evolves; the crossfade runs over
/// `beatPhase` (0→1 within the beat) so it animates; `flipGate` (pulse_amp01) is
/// 0 at cold-start/silence → the static PG.4.1 weave. An orientation swap keeps
/// per-cell ink coverage steady (D-157 luminance stability).
static inline float2 tl_weave(float2 t, float level,
                              float beatIdx, float beatPhase, float flipGate) {
    float coverage   = 0.0;
    float depthShade = 0.0;
    float flipMix = smoothstep(0.05, 0.55, beatPhase);   // re-route early, then hold
    for (int L = 0; L <= kTL_maxDepth; L++) {
        float  s  = kTL_baseTiles * exp2(float(L));
        float2 p  = t * s;
        float2 id = floor(p);
        float2 f  = fract(p) - 0.5;
        // AA width from the CONTINUOUS scaled coord `p` (not the wrapping arc
        // distance, whose derivative spikes at fract() seams → blocky smear).
        float  aa = length(fwidth(p)) + 1e-4;

        // Static orientation (the PG.4.1 weave, exactly, at flipGate 0).
        float covStatic = tl_arcCov(f, hash_f01_2(id + 0.5), aa);
        // Per-beat re-route: participating subset crossfades prev-beat → this-beat
        // orientation. Integer beat offsets shift the hash lattice → distinct
        // orientation per cell per beat.
        float participate = step(hash_f01_2(id + float2(101.0, 53.0)), kTL_flipFrac);
        float hPrev = hash_f01_2(id + float2((beatIdx - 1.0) * 37.0 + 3.0, (beatIdx - 1.0) * 17.0 + 1.0));
        float hCurr = hash_f01_2(id + float2(beatIdx * 37.0 + 3.0, beatIdx * 17.0 + 1.0));
        float covFlip = mix(tl_arcCov(f, hPrev, aa), tl_arcCov(f, hCurr, aa), flipMix);
        float cov = mix(covStatic, covFlip, participate * flipGate);

        // Openness — parent-keyed so a coarse tile's four children reveal together.
        float open;
        if (L == 0) {
            open = 1.0;
        } else {
            float2 pid    = floor(t * kTL_baseTiles * exp2(float(L - 1)));
            float  jitter = hash_f01_2(pid + 19.7) - 0.5;
            open = smoothstep(0.0, 1.0, level - float(L) + jitter * kTL_openJitter);
        }
        coverage   = mix(coverage, cov, open);
        depthShade = mix(depthShade, float(L) / float(kTL_maxDepth), open * cov);
    }
    return float2(coverage, depthShade);
}

// MARK: - Fragment

fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& f [[buffer(0)]],
                                constant float* fftMagnitudes [[buffer(1)]],
                                constant float* waveformData [[buffer(2)]],
                                constant float* spectralHistory [[buffer(5)]]) {
    // ── Aspect-corrected, drifting tiling coordinate ────────────────────────────
    float2 p = in.uv - 0.5;
    p.x *= f.aspect_ratio;

    // Drift: f.time is the always-advancing wall-clock BASELINE (keeps the loom
    // alive at silence, D-037); f.arousal sets the SPEED (the one audio primitive
    // on this layer). arousal is −1..1 → [0,1].
    float driftT = f.time;
    float speed  = 0.020 + clamp((f.arousal + 1.0) * 0.5, 0.0, 1.0) * 0.045;
    float ang    = driftT * speed * 0.5;
    float ca = cos(ang), sa = sin(ang);
    p = float2(ca * p.x - sa * p.y, sa * p.x + ca * p.y);
    p += float2(driftT * speed, driftT * speed * 0.32);

    // ── HERO: subdivision level from SMOOTHED spectral_flux (buffer(5), idx 3390) ─
    // Single CPU-side EMA float (SpectralHistoryBuffer.append). Soft-saturated into
    // [base, maxDepth] — a continuous monotonic map, never a hard threshold. In the
    // regression/visual harnesses the buffer is zeroed → level = base (coarse weave).
    float smoothedFlux = spectralHistory[3390];
    float density = 1.0 - exp(-max(0.0, smoothedFlux) * kTL_fluxGain);
    float level = kTL_levelBase + (float(kTL_maxDepth) - kTL_levelBase) * density;

    // ── PG.4.2 rhythm: per-beat flips (cached grid + beat_index) ────────────────
    float beatIdx  = spectralHistory[3391];              // monotonic beat counter
    float flipGate = clamp(f.pulse_amp01, 0.0, 1.0);     // 0 at cold-start/silence
    float2 w = tl_weave(p, level, beatIdx, f.beat_phase01, flipGate);
    float coverage   = w.x;
    float depthShade = w.y;

    // ── PG.4.2 colour: per-path hue teams (coarse region → quantised hue) ───────
    // Coarse spatial blocks (½ the base tile frequency) share a hue so colour reads
    // as ribbons along paths, not per-cell rainbow noise. spectral_centroid slowly
    // phases the whole set; finer sub-tiles brighten so nesting still reads.
    // PG.4.3: the block lookup is domain-warped by a low-freq fbm so team boundaries
    // WANDER organically instead of snapping to a hard square grid.
    float2 hueUV    = p * kTL_baseTiles * 0.5;
    float2 hueWarp  = float2(tl_vnoise(hueUV * 0.6),
                             tl_vnoise(hueUV * 0.6 + 3.7)) * kTL_hueWarp;
    float2 hueBlock = floor(hueUV + hueWarp);
    float  teamSeed = hash_f01_2(hueBlock + 61.0);
    float  team     = floor(teamSeed * kTL_hueTeams) / kTL_hueTeams;
    float  hue      = fract(team + f.spectral_centroid * 0.30 + 0.55);
    float3 ribbon   = hsv2rgb(float3(hue, 0.52 - depthShade * 0.12, 0.86 + depthShade * 0.14));

    float3 color = mix(kTL_ground, ribbon, coverage);
    // Soft ribbon core highlight (op-art punch without pure-white flatness).
    color += ribbon * smoothstep(0.55, 1.0, coverage) * 0.12;

    // ── PG.4.2 accent: bounded bass-onset glow on the subdivided ribbons ────────
    // Weighted toward the finer (higher-depth) tiles — the "newest subdivided
    // cluster" — but broad enough to read. Bounded (drop if it competes at M7).
    float glow = kTL_glowGain * clamp(f.bass_dev, 0.0, 1.5)
               * smoothstep(0.28, 0.9, depthShade) * coverage;
    color += ribbon * glow;

    // ── PG.4.3 breakup: subtle static paper grain (§A2 breakup scale). Screen-
    // anchored (a print texture on the poster, not on the pattern), very low
    // amplitude so the op-art stays crisp. Zeroed nowhere special — deterministic.
    float grain = hash_f01_2(in.uv * 1600.0 + 0.5) - 0.5;
    color += grain * kTL_grain;

    return float4(clamp(color, 0.0, 1.0), 1.0);
}
