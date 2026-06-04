// Nimbus — volumetric luminous-body preset (family: volumetric).
//
// A single coherent gaseous body suspended in a true-black void, rendered as a
// single-pass 2D direct-fragment volumetric ray-march that composes the
// preamble-injected V.2 Volume tree (no engine changes, no new utilities, no
// extra passes — passes: []). Contract of record: docs/presets/NIMBUS_DESIGN.md.
//
// NB.1 — MACRO MAQUETTE. Coarse-geometry pass (SHADER_CRAFT §2.2): one coherent
// body with a denser, brighter core fraying to soft wispy edges on a true-black
// void, framed to docs/VISUAL_REFERENCES/nimbus/01_macro_coherent_body. Slow
// time-only drift (NO audio coupling — Breath is NB.4). Minimal single-scatter +
// cheap envelope self-shadow (the internal-glow recipe is NB.3). Static cool
// indigo tint (valence/arousal mapping is NB.6). Fixed camera + FOV.
//
// References folded into the code below:
//   01_macro_coherent_body  — bright core → soft wispy edges, vertical long axis,
//                             dominant black negative space (FORM only; colour is
//                             the cool baseline, not 01's turquoise — README).
//   02_meso_billow_and_filament — rounded billows / density lobes (voronoi carve).
//   06_palette_cool_baseline — deep desaturated indigo/violet body tint.
//   ANTI 05_anti_uniform_fog   — bounded body + negative space (never frame-filling).
//   ANTI 05_anti_solid_surface — translucent medium: a small cool ambient keeps the
//                             shadow side readable; glow is in-scatter, not a lit shell.

// MARK: - Debug views (DESIGN §5.6)
// Compile-time toggle (no engine uniform is plumbed in NB.1 — by design, no engine
// changes). Flip the value, rebuild, render.
//   0 = normal (lit, tinted, composited)
//   1 = density-only (accumulated opacity as greyscale; no lighting/tint — the
//       load-bearing guard: confirms centre of mass + silhouette + negative space)
//   2 = step-count heatmap (in-body march steps per fragment → cost / early-out)
#define NIMBUS_DEBUG_MODE 0

// MARK: - Nimbus tunables (NB.1 macro maquette)

// Body ellipsoid semi-axes (body space). Long axis vertical (y > x,z).
constant float3 kNimbusSemiAxes  = float3(1.20, 1.50, 1.20);
constant float  kNimbusBoundR    = 1.85;   // bounding sphere for the march range
constant int    kNimbusSteps     = 64;     // primary march steps
constant int    kNimbusShadowN   = 6;      // secondary light-march steps
constant float  kNimbusShadowDt  = 0.16;   // light-march step length
constant float  kNimbusSigma     = 1.55;   // primary extinction (translucent: low enough to see INTO the volume so front-to-back accumulation reads lobe depth — NB.2)
constant float  kNimbusShadowSig = 1.10;   // softer self-shadow extinction (keeps the core lit → brighter)
constant float  kNimbusCamZ      = -6.0;   // camera distance (looking +Z)
constant float  kNimbusFocal     = 1.25;   // FOV (larger = narrower)
constant float  kNimbusPhaseG    = 0.40;   // Henyey-Greenstein anisotropy (DESIGN §5.2)
constant float  kNimbusWarpAmt   = 0.26;   // domain-warp strength → micro tendrils/curl (NB.2; ref 03)

// MARK: - Density field

// Analytic ellipsoidal envelope: 1 at the dense core, smoothly → 0 at the shell.
// Cheap (no noise) — also used directly for the secondary self-shadow march.
static inline float nimbus_envelope(float3 p, thread float& rrOut) {
    float3 bp = p / kNimbusSemiAxes;
    float rr = length(bp);
    rrOut = rr;
    // Fuller shell for a substantial body, multiplied by a gaussian core boost so
    // the centre is the densest region (→ reads as the brighter core) while the
    // body keeps its size; smoothly → 0 at the shell (rr ≈ 1.05).
    float shell = smoothstep(1.05, 0.12, rr);
    float core  = 0.50 + 1.05 * exp(-rr * rr * 3.2);
    return shell * core;
}

static inline float nimbus_envelope(float3 p) {
    float rr;
    return nimbus_envelope(p, rr);
}

// Full body density: the smooth ellipsoidal envelope ERODED by a multi-scale
// detail field — the macro→meso→micro cascade in one field (SHADER_CRAFT §2.2).
// Erosion increases toward the shell (fray weighting) so the core stays dense and
// coherent while the periphery breaks into lobes, wisps and soft voids. ALL detail
// is sampled from the preamble 64³ tileable 3D FBM texture (noiseVolume,
// [[texture(6)]], production-bound via TextureManager) — never computed per step
// (NB.1.1 budget lesson, D-140 / DESIGN §6.1: per-step fbm4 was ~20 ms @1080p,
// texture sampling ~1.4 ms). Time-only drift (no audio — Breath is NB.4).
static inline float nimbus_density(float3 p, float t,
                                   texture3d<float> noiseVol, sampler smp) {
    float rr;
    float env = nimbus_envelope(p, rr);
    if (env <= 0.001) { return 0.0; }   // outside the body → skip the noise cost

    float3 q = p + float3(0.0, -t * 0.015, t * 0.008);   // slow, time-only drift

    // ── MESO: nested billow lobes (ref 02_meso_billow_and_filament) ─────────
    // Two octave-doubled lobe scales → rounded lumps with sub-lumps riding on
    // them. Shaped (tight smoothstep) so the billows read as DISTINCT bright
    // lobes separated by dimmer valleys — ref 02's soft cellular boundaries —
    // not a smooth egg. The depth / self-occlusion read (ref 02's "nearer lobes
    // shadow those behind") is NOT painted here: it emerges from the march's
    // front-to-back transmittance accumulation (a near dense lobe attenuates the
    // in-scatter of the lobes behind it) plus the existing envelope self-shadow.
    // No detail-aware shadow in NB.2 — that is the NB.3 lighting recipe.
    float lobeA  = noiseVol.sample(smp, q * 0.7).r;          // coarse billows
    float lobeB  = noiseVol.sample(smp, q * 1.4).r;          // nested sub-billows
    float lobes  = lobeA * 0.62 + lobeB * 0.38;              // [0,1]
    float billow = smoothstep(0.35, 0.70, lobes);            // distinct lumps [0,1] (tight range → crisp lobe/valley contrast)

    // ── Interior turbulence (mid octave) ────────────────────────────────────
    // Roughens the inside of each billow so the gas reads as gas, not jelly.
    float turbMid = noiseVol.sample(smp, q * 2.8).r;         // [0,1], centred ~0.5

    // ── MICRO: domain-warped fine filaments + curl (ref 03_micro_wisp_*) ────
    // Domain warp: perturb the sample coordinate with a low-freq noiseVolume tap
    // so the fine octave stretches into swirling tendrils / curl at the wisp
    // tips (ref 03) rather than isotropic stipple. The texture is single-channel
    // (.r8Unorm), so two decorrelated low-freq taps build a 2-axis swirl offset.
    // The warp is a CHEAP texture sample — NEVER warped_fbm / fbm_vec3, which
    // compute fbm8 (~56 perlin evals) and re-blow the budget (D-140 / §6.1).
    float w0 = noiseVol.sample(smp, q * 0.9).r - 0.5;                       // [-0.5,0.5]
    float w1 = noiseVol.sample(smp, q * 0.9 + float3(4.7, 1.3, 8.1)).r - 0.5;
    float3 qw    = q + float3(w0, w1, (w0 - w1) * 0.5) * kNimbusWarpAmt;    // swirled coords
    float micro  = noiseVol.sample(smp, qw * 5.6).r;                        // warped fine filaments
    // 4 octaves (0.7 / 1.4 / 2.8 / 5.6 warped) — the §12.1 ≥4-octave noise
    // floor; the warp adds a low-freq swirl band on top (texture is itself FBM).

    // ── Compose: billow lobes CARVE the envelope (distinct lumps) ───────────
    // Multiplicative carve, not additive: valleys (low billow) thin the body
    // toward transparency while crests stay dense, so the density iso-surface is
    // genuinely LUMPY (the ref-02 billow read) rather than a smooth saturated
    // egg — additive modulation just brightens an already-opaque core and the
    // lumps wash out (the 05_anti_solid_surface interior). Crests push slightly
    // above 1 so lobe peaks read brighter than valleys. The interior roil is the
    // mid + warped-fine octaves so the inside carries the §12.1 fine detail too.
    float lobeCarve = mix(0.14, 1.10, billow);              // [0.14 valley .. 1.10 crest]
    float roil      = 1.0 + (turbMid - 0.5) * 0.42 + (micro - 0.5) * 0.28;
    float dens      = env * lobeCarve * roil;

    // ── Edge feathering: peeling curling tendrils dissolving into void (ref 03)
    // Toward the rim, MULTIPLY density by the warped micro field so the body
    // breaks into curling filaments separated by void — a multiplicative mask
    // gives crisp filament-vs-gap contrast where a smooth subtraction only
    // softened the whole rim into a blur. The domain warp curls the tendrils
    // (ref 03's vortex tips) instead of stippling them straight out; the larger
    // billow gaps let whole lobes peel off the mass. The core (low rr) is
    // unmasked so the body stays one coherent mass; the rim never hard-cuts
    // (never 05_anti_solid_surface) because the mask is continuous noise.
    float rim          = smoothstep(0.48, 1.06, rr);         // 0 core → 1 shell
    float microFil     = smoothstep(0.34, 0.64, micro);      // fine curling tendrils (sharper → crisper filaments)
    float lobeFil      = smoothstep(0.28, 0.74, billow);     // larger lobe gaps peel off
    float filamentMask = clamp(microFil * 0.74 + lobeFil * 0.42, 0.0, 1.0);
    dens *= mix(1.0, filamentMask, rim);

    return max(0.0, dens);
}

// MARK: - Nimbus fragment (NB.1 macro maquette)

fragment float4 nimbus_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                texture3d<float> noiseVolume [[texture(6)]]) {
    // ── View ray (fixed camera + FOV, aspect-corrected) ──────────────────────
    float2 uv = in.uv;
    float2 p = uv - 0.5;
    p.x *= max(features.aspect_ratio, 1e-4);
    float3 ro = float3(0.0, 0.0, kNimbusCamZ);
    float3 rd = normalize(float3(p.x, -p.y, kNimbusFocal));  // -p.y: uv.y=0 is top → +world-up

    float3 voidColor = float3(0.0);   // true-black void (NB.1; the haze floor is NB.4)

    // ── Bounding-sphere intersection (skip the void; the env early-out makes the
    // in-sphere / outside-body steps nearly free — a loose sphere is *cheaper*
    // than a tight ellipsoid here because it spends most steps in empty space
    // that early-outs, rather than forcing every step through the noise field).
    float bq = dot(ro, rd);                       // sphere centred at origin
    float cq = dot(ro, ro) - kNimbusBoundR * kNimbusBoundR;
    float disc = bq * bq - cq;
    if (disc < 0.0) { return float4(voidColor, 1.0); }   // ray misses the body bound
    float sq = sqrt(disc);
    float t0 = max(-bq - sq, 0.0);
    float t1 = -bq + sq;

    // ── Fixed lighting (minimal — NOT the NB.3 internal-glow recipe) ─────────
    // 3/4 key from upper-left, biased behind the body so single-scatter reads as
    // a luminous gas (forward-scatter through the dense core → brighter core)
    // while the soft self-shadow gives a 3D form. Intensity is artistic, not
    // physical (the HG phase is normalised small).
    float3 lightDir   = normalize(float3(-0.35, 0.42, 0.45));   // upper-left, biased behind
    float3 lightColor = float3(1.00, 0.97, 0.92) * 5.2;         // neutral warm-white (intensity restores body presence under the lower NB.2 sigma)
    float3 ambient    = float3(0.025, 0.030, 0.060);            // faint cool ambient (shadow side just reads, gradient preserved)

    float t = features.time;

    // ── Front-to-back single-scatter march ──────────────────────────────────
    VolumeSample acc = vol_sample_zero();
    float dt = (t1 - t0) / float(kNimbusSteps);
    int litSteps = 0;
    for (int i = 0; i < kNimbusSteps; i++) {
        float ti = t0 + (float(i) + 0.5) * dt;
        float3 pos = ro + rd * ti;
        float dens = nimbus_density(pos, t, noiseVolume, linearSampler);
        if (dens > 0.002) {
            litSteps++;
            // Self-shadow: short secondary light-march over the analytic envelope
            // only (cheap; the dense core occludes the far side → reads as 3D).
            float tau = 0.0;
            for (int j = 1; j <= kNimbusShadowN; j++) {
                float3 sp = pos + lightDir * (float(j) * kNimbusShadowDt);
                tau += nimbus_envelope(sp) * kNimbusShadowSig * kNimbusShadowDt;
            }
            float shadow = exp(-tau);
            float phase = hg_phase(dot(rd, lightDir), kNimbusPhaseG);
            float3 lit = lightColor * (phase * shadow) + ambient;
            float3 inscat = lit * dens * kNimbusSigma * dt;
            acc.color += inscat * acc.transmittance;
            acc.transmittance *= exp(-dens * kNimbusSigma * dt);
            if (acc.transmittance < 0.01) { break; }
        }
    }

#if NIMBUS_DEBUG_MODE == 1
    // Density-only: accumulated opacity as greyscale (no lighting / no tint).
    float opacity = 1.0 - acc.transmittance;
    return float4(float3(opacity), 1.0);
#elif NIMBUS_DEBUG_MODE == 2
    // Step-count heatmap: in-body march steps → blue (cheap) → green → red (costly).
    float load = float(litSteps) / float(kNimbusSteps);
    float3 heat = float3(load, 1.0 - abs(load - 0.5) * 2.0, 1.0 - load);
    return float4(heat, 1.0);
#else
    // ── Composite: cool indigo body over the black void → ACES ───────────────
    // Body tinted toward the cool baseline (deep desaturated indigo/violet,
    // 06_palette_cool_baseline). The densest/brightest core desaturates toward
    // white at the top end (luminance, not a second hue) → the ref-01 bright core.
    float3 coolTint = float3(0.40, 0.36, 0.74);
    float lum = dot(acc.color, float3(0.299, 0.587, 0.114));
    float3 tint = mix(coolTint, float3(0.80, 0.80, 0.94), smoothstep(0.9, 2.2, lum));
    float3 outc = acc.color * tint + voidColor * acc.transmittance;
    outc = toneMapACES(outc);
    return float4(outc, 1.0);
#endif
}
