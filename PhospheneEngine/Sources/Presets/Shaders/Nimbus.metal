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
constant float  kNimbusShadowDt  = 0.22;   // light-march step length (reach ≈ full body depth)
constant float  kNimbusSigma     = 1.55;   // primary extinction (translucent: see INTO the volume)
constant float  kNimbusShadowSig = 2.40;   // self-shadow extinction — strong → dark core vs bright forward-scatter rim (the backlit silver lining, NB.3.2)
constant float  kNimbusCamZ      = -6.0;   // camera distance (looking +Z)
constant float  kNimbusFocal     = 1.25;   // FOV (larger = narrower)
constant float  kNimbusPhaseG    = 0.58;   // Henyey-Greenstein anisotropy — strong forward scatter → backlit glow (NB.3.2)

// NB.3.1 Perlin-Worley density (HZD / "Nubis"). Scales are body-space sample
// units; noiseVolume tiles every 1.0 and itself holds ~4 billow cycles per tile.
constant float  kNimbusBillowScale = 0.55;  // base billow frequency (≈ cauliflower lumps across the body)
constant float  kNimbusDetailMul   = 3.1;   // detail-erosion octave frequency = base × this
constant float  kNimbusDetailErode = 0.32;  // how hard the high-freq Worley carves the billow edges

// Edge-agitation amplitude — scales the detail erosion: 0 = smooth lobes, 1 = the
// NB.3 default, >1 = more torn / churning edges. Compile-time FOR NOW; NB.6
// replaces it with smoothed `arousal` (DESIGN §1.3 — arousal → flow agitation).
constant float  kNimbusTurbulence  = 1.0;

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

// HZD / "Nubis" remap (Schneider 2015): linear remap of v from [lo,hi] → [nlo,nhi].
static inline float nimbus_remap(float v, float lo, float hi, float nlo, float nhi) {
    return nlo + (v - lo) * (nhi - nlo) / (hi - lo);
}

// Full body density — the ported HZD / "Nubis" volumetric-cloud build (NB.3.1).
// The bounded body comes from the analytic envelope; the cauliflower BILLOWS come
// from the Perlin-Worley base texture (R channel), carved by its Worley detail
// octaves (G/B/A) and remapped against the envelope as "coverage" — the single HZD
// remap that yields a dense core AND feathered cauliflower edges at once. All noise
// is texture-sampled (§6.1 budget rule). Time-only drift (audio is NB.4).
static inline float nimbus_density(float3 p, float t,
                                   texture3d<float> noiseVol, sampler smp) {
    float rr;
    float env = nimbus_envelope(p, rr);
    if (env <= 0.001) { return 0.0; }   // outside the body → skip the noise cost

    // Off-lattice sample coordinate: a constant offset so the body is NOT centred
    // on a tile boundary / lattice point — centring there makes +δ and −δ sample
    // near-identical values across the seamless tile boundary → 4-fold mirror
    // symmetry (NB.3.0 finding). Slow time drift on top.
    float3 q = p + float3(3.17, 1.73, 5.41)                 // off-lattice offset
                 + float3(0.0, -t * 0.015, t * 0.008);      // slow drift

    // ── Base shape: Perlin-Worley billows (R) carved by Worley detail (G/B/A) ──
    float4 base      = noiseVol.sample(smp, q * kNimbusBillowScale);
    float  worleyFBM = base.g * 0.625 + base.b * 0.25 + base.a * 0.125;
    // HZD remap: expand the Perlin-Worley base by the Worley clumps → nested
    // cauliflower lumps (this is what makes them read as billows, not soft blobs).
    float  billows   = clamp(nimbus_remap(base.r, worleyFBM - 1.0, 1.0, 0.0, 1.0), 0.0, 1.0);

    // ── Coverage remap by the envelope → bounded body + feathered billow edges ──
    // The envelope (clamped) is the "coverage": at the core (cov≈1) the full billow
    // structure survives; toward the shell (cov→0) only the highest billow peaks
    // survive, so the edge breaks into cauliflower lumps and feathers into the void
    // — both the dense core and the soft edge from one remap. cov ≥ 0.001 (the
    // early-out) so the remap's (hi−lo)=cov is never zero.
    float coverage = clamp(env, 0.0, 1.0);
    float density  = clamp(nimbus_remap(billows, 1.0 - coverage, 1.0, 0.0, 1.0), 0.0, 1.0);

    // ── Detail erosion: a higher-frequency Worley octave carves the billow edges
    // into finer structure (HZD's high-freq detail pass), weighted toward the rim
    // so the dense core stays coherent. kNimbusTurbulence is the agitation knob
    // (NB.6 → arousal): more erosion = more torn / churning edges.
    float4 detail     = noiseVol.sample(smp, q * kNimbusBillowScale * kNimbusDetailMul);
    float  detailFBM  = detail.g * 0.625 + detail.b * 0.25 + detail.a * 0.125;
    float  edgeWeight = 1.0 - coverage;                     // 0 core → 1 shell
    float  erodeLo    = clamp((1.0 - detailFBM) * kNimbusDetailErode * kNimbusTurbulence
                              * edgeWeight, 0.0, 0.9);
    density = clamp(nimbus_remap(density, erodeLo, 1.0, 0.0, 1.0), 0.0, 1.0);

    return density;
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

    // ── Lighting: backlit internal glow (NB.3.2 — ported HZD / "Nubis") ──────
    // The references are BACKLIT (hero 08): the key sits behind the body, so
    // forward-scatter through the thin edges makes the glowing silver-lining rim
    // while the dense front self-shadows into a deep core. Strong forward HG +
    // the detail-aware cone self-shadow (in the march below) is what makes the
    // cauliflower billows read as 3D.
    float3 lightDir   = normalize(float3(-0.30, 0.42, 0.74));   // upper-left, strongly behind
    float3 lightColor = float3(1.00, 0.97, 0.92) * 5.6;         // neutral warm-white key
    float3 ambient    = float3(0.022, 0.028, 0.055);            // faint cool fill (shadowed front still reads)

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
            // Detail-aware CONE self-shadow (NB.3.2): march toward the light
            // accumulating the real billow DENSITY (not the smooth envelope), so
            // the crevices between cauliflower lumps fall into shadow and thin
            // edges stay lit → the 3D billow read. This is the cost driver the
            // plan flagged (re-measured at NB.8).
            float densToLight = 0.0;
            for (int j = 1; j <= kNimbusShadowN; j++) {
                float3 sp = pos + lightDir * (float(j) * kNimbusShadowDt);
                densToLight += nimbus_density(sp, t, noiseVolume, linearSampler);
            }
            float shadow = exp(-densToLight * kNimbusShadowDt * kNimbusShadowSig);
            // Forward-scatter phase: thin edges grazing the back-light glow brightest.
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
