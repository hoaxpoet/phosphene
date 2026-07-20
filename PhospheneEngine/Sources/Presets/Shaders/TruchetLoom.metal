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
// AUDIO ROUTING (PG.4.1 subset of PG_4 §A4 — density + drift only; per-beat flips,
// per-path hue teams, and the glow accent are PG.4.2):
//   - Subdivision density (HERO) ← SMOOTHED spectral_flux. Read as a single CPU-side
//     EMA float from SpectralHistory buffer(5) slot `offsetFluxSmoothed` (index 3390);
//     see SpectralHistoryBuffer.append(). spectral_flux is the one primitive that
//     LITERALLY measures the thing we map (broadband busyness) and is reliably alive
//     across genres (PG_0 §3). It is a continuous variable soft-saturated into a
//     level, NEVER an absolute threshold on an AGC-normalized energy band (FA #31 /
//     D-026): the smoothing removes frame-to-frame flicker, the soft-saturation is
//     scale-robust so no hard cut-point is baked in.
//   - Global drift (flow) ← f.arousal sets the scroll/rotate SPEED; f.time is the
//     non-reactive wall-clock BASELINE (advances at silence, so the loom always
//     drifts — D-037). One audio primitive on this layer (arousal); f.time is not a
//     second audio driver (FA #67).
//
// SILENCE (D-037): smoothed flux ≈ 0 → level ≈ base → coarse large-arc weave, no
// subdivision, drifting slowly on f.time. Non-black (deep-cobalt ground, not #000).

// MARK: - Constants

constant float  kTL_baseTiles   = 3.5;   // big arcs across the short axis at level 0
constant int    kTL_maxDepth    = 3;     // recursion cap (Restrained default)
constant float  kTL_lineW       = 0.062; // arc half-width in cell space
constant float  kTL_openJitter  = 0.9;   // per-parent reveal-threshold spread
constant float  kTL_levelBase   = 0.40;  // level at silence (coarse weave)
constant float  kTL_fluxGain    = 6.0;   // soft-saturation gain on smoothed flux

// Azulejo-derived duotone-plus-accent (PG_4 §A6; ref 04_palette_op_art_tile.jpg).
// Deep cobalt GROUND (a deep colour, not black — pale-tone ≤ 30 %, FA #45), a bright
// cyan-white RIBBON, and a warm-gold ACCENT the finer sub-tiles shift toward so the
// nesting reads as depth rather than a flat monochrome maze.
constant float3 kTL_ground = float3(0.020, 0.045, 0.140);
constant float3 kTL_ribbon = float3(0.760, 0.910, 0.980);
constant float3 kTL_accent = float3(0.980, 0.780, 0.240);

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

// MARK: - Multiscale weave

/// Coverage (0 = ground, 1 = ribbon core) + a depth shade (0 coarse → 1 finest)
/// for the woven field at continuous subdivision `level`, sampled at tiling
/// coordinate `t` (units: ~short-axis halves). Coarse-to-fine accumulation with
/// per-parent-cell reveal so subdivision crossfades smoothly (no pop) and finer
/// tiles are drawn on top of coarser ones (Carlson's rule).
static inline float2 tl_weave(float2 t, float level) {
    float coverage   = 0.0;
    float depthShade = 0.0;
    for (int L = 0; L <= kTL_maxDepth; L++) {
        float  s  = kTL_baseTiles * exp2(float(L));
        float2 p  = t * s;
        float2 id = floor(p);
        float2 f  = fract(p) - 0.5;
        float  h  = hash_f01_2(id + 0.5);        // per-cell orientation
        float  d  = tl_arc(f, h);
        float  aa = fwidth(d) + 1e-4;            // crisp anti-aliased edge
        float  cov = smoothstep(kTL_lineW + aa, kTL_lineW - aa, d);

        // Openness of this level, keyed to the PARENT cell so a coarse tile's four
        // children reveal together as its big arc fades (the "one big arc → four
        // small arcs" morph). Level 0 is always fully present (the base weave).
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

    // ── Weave → palette ─────────────────────────────────────────────────────────
    float2 w = tl_weave(p, level);
    float coverage   = w.x;
    float depthShade = w.y;

    // Finer sub-tiles lean toward the warm accent so the nesting reads as depth.
    float3 ribbon = mix(kTL_ribbon, kTL_accent, depthShade * 0.85);
    float3 color  = mix(kTL_ground, ribbon, coverage);

    // Soft ribbon core highlight (op-art punch without pure-white flatness).
    color += kTL_ribbon * smoothstep(0.55, 1.0, coverage) * 0.12;

    return float4(min(color, float3(1.0)), 1.0);
}
