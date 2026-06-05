// Nimbus — volumetric luminous-body preset (family: volumetric).
//
// A single coherent gaseous body suspended in a (faintly-hazed) void, rendered
// as a single-pass 2D direct-fragment volumetric ray-march that composes the
// preamble-injected V.2 Volume tree (no engine changes, no new utilities, no
// extra passes — passes: []). Contract of record: docs/presets/NIMBUS_DESIGN.md.
//
// NB.3 — THE LOOK (ported HZD / "Nubis" cloud technique): density from
// Perlin-Worley billows (noiseVolume) shaped to a bounded body by the analytic
// envelope; backlit forward-scatter + a detail-aware cone self-shadow → luminous
// cool gaseous body with feathered edges. Matt-approved on the contact sheet
// 2026-06-05. (BACKLIT, never emission — DESIGN §5.2.)
//
// NB.4 — ENERGY (bloom): a slow overall size/brightness/flow swell. NB.5 —
// THE BAND PLAYS THE BODY: the 2026-06-05 Atlas session showed the energy-only
// bloom was too subtle (and floored on bass-dominated music — two dead bands
// vetoed the 3-band average) while the relentless beat went unanswered. The
// model was reversed (DESIGN §1.3): NimbusState now drives, per stem, a
// fast-attack/slow-release follower → a soft bulge of the SINGLE envelope.
// Drums = whole-body punch + brightness pop (the hero beat moment); bass heaves
// DOWN, lead/"vocals" flares UP, other swells to the SIDE. All blended into one
// star-convex mass (it cannot fragment — the §1.4 idea-to-protect). The slow
// bloom now tracks total stem energy (never floored). NO mood yet (valence/
// arousal → colour + agitation is NB.6). Fixed camera + FOV.
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
constant float3 kNimbusSemiAxes  = float3(1.70, 2.10, 1.70);   // NB.3.3: larger, more substantial body (was 1.2,1.5,1.2)
constant float  kNimbusBoundR    = 2.70;   // bounding sphere for the march range (grown with the body)
constant int    kNimbusSteps     = 64;     // primary march steps
constant int    kNimbusShadowN   = 6;      // secondary light-march steps
constant float  kNimbusShadowDt  = 0.32;   // light-march step length (reach ≈ full body depth — grown with the body, NB.3.3)
constant float  kNimbusSigma     = 1.55;   // primary extinction (translucent: see INTO the volume)
constant float  kNimbusShadowSig = 3.40;   // self-shadow extinction — STRONGER (NB.3.3) → deeper dark crevices vs bright forward-scatter rim (the backlit silver lining)
constant float  kNimbusCamZ      = -6.0;   // camera distance (looking +Z)
constant float  kNimbusFocal     = 1.44;   // FOV (larger = narrower) — NB.3.3 zoom +15% (1.25→1.44) to grow the mass on-screen without touching the approved body geometry/density (Matt-directed)
constant float  kNimbusPhaseG    = 0.70;   // Henyey-Greenstein anisotropy — stronger forward scatter (NB.3.3 step 3) → brighter silver-lining rim where rays graze thin edges toward the back-key (ref 08)

// NB.3.1 Perlin-Worley density (HZD / "Nubis"). Scales are body-space sample
// units; noiseVolume tiles every 1.0 and itself holds ~4 billow cycles per tile.
constant float  kNimbusBillowScale = 0.55;  // base billow frequency (≈ cauliflower lumps across the body)
constant float  kNimbusDetailMul   = 3.1;   // detail-erosion octave frequency = base × this
constant float  kNimbusDetailErode = 0.32;  // how hard the high-freq Worley carves the billow edges

// NB.3.3 — interior lump/crevice contrast (ref 02: deep crevices between cauliflower
// lumps). Gated by coverage so it deepens the body's INTERIOR billows without
// fragmenting the soft feathered rim (ref 03). Lighting stays the backlit model.
constant float  kNimbusLumpLo   = 0.20;  // contrast window low  → deepens crevices
constant float  kNimbusLumpHi   = 0.82;  // contrast window high → sharpens lit lumps

// NB.3.3 — denser CORE for substance (ref 01: a denser core falling to wispy edges).
// Backlit (existing model), a denser core self-shadows into ref 08's dark-core /
// bright-rim — substance, not a glow source. Pure density; no emission.
constant float  kNimbusCoreGain = 0.55;  // density boost added at the centre (0 = none) — eased so the core gains substance without saturating flat (keeps ref-02 interior lumps)
constant float  kNimbusCoreSig  = 1.50;  // core falloff (larger = tighter dense core)

// Edge-agitation amplitude — scales the detail erosion: 0 = smooth lobes, 1 = the
// NB.3 default, >1 = more torn / churning edges. Compile-time FOR NOW; NB.6
// replaces it with smoothed `arousal` (DESIGN §1.3 — arousal → flow agitation).
constant float  kNimbusTurbulence  = 1.0;

// MARK: - NB.4/NB.5 audio-reactive state (DESIGN §1.3 / §5.4)

// Per-frame world state from NimbusState (Swift) — 32 bytes, must match
// `NimbusStateGPU` in NimbusState.swift byte-for-byte. Bound at fragment
// buffer(6) (orthogonal to noiseVolume at *texture* 6 — different namespaces).
struct NimbusStateGPU {
    float bloom;       // slow overall size/brightness swell (0 floor · ~0.5 baseline · ~1 peak)
    float flowPhase;   // gas churn phase (seconds-equivalent, bloom + kick modulated)
    float kickPunch;   // NB.5 whole-body beat punch (drums) — fast attack / fast settle
    float bassLobe;    // NB.5 downward heave (bass stem)
    float vocalsLobe;  // NB.5 upward flare (lead/"vocals" stem)
    float otherLobe;   // NB.5 sideways swell (other stem)
    float _pad0;
    float _pad1;
};

// One signal (`bloom`), three visual readings of the same physical event. All
// `mix(floor, peak, bloom)` — the floor is the silence-floor value (smaller /
// dimmer / slower than the approved NB.3 look), the peak is full bloom. The
// floor→peak ratios encode the DESIGN §1.3 ranges (+45 % size, +80 % bright,
// 3.5× flow). Starting points — Matt's eye/ear sets the finals.
constant float kNimbusSizeFloor   = 0.80;  // body scale at silence (smaller than NB.3)
constant float kNimbusSizePeak    = 1.16;  // body scale at full bloom (1.16/0.80 = 1.45 → +45 %; baseline ≈ NB.3)
constant float kNimbusBrightFloor = 0.65;  // luminosity ×NB.3 at silence (dim, still present — non-black)
constant float kNimbusBrightPeak  = 1.17;  // luminosity ×NB.3 at full bloom (1.17/0.65 = 1.80 → +80 %)

// NB.4 — faint non-black HAZE floor (D-037 / DESIGN §1.4-§1.5). A dim cool halo
// fills the void so the steady-playback ground is never pure black; concentrated
// around the body, fading to near-black corners so negative space is preserved
// (NOT the 05_anti_uniform_fog failure — the corners stay dark). Eased slightly
// with bloom but with a hard non-zero floor (the D-037 guarantee at silence).
constant float3 kNimbusHazeColor   = float3(0.36, 0.42, 0.92);  // deep cool indigo (the body's cool baseline)
constant float  kNimbusHazeBase    = 0.040; // peak haze radiance scalar (pre-tonemap, ×color ×falloff)
constant float  kNimbusHazeFalloff = 2.30;  // radial concentration; larger = tighter halo, darker corners

// MARK: - NB.5 stem beat-lobes (DESIGN §1.3 — one mass heaves per-stem)

// The band plays the body. Each stem's follower (NimbusState) pushes a soft bulge
// of the SINGLE envelope: drums = whole-body punch (uniform), bass/lead/other =
// directional heaves. The bulge divides the effective radius (rr/(1+bulge)) so it
// is a star-convex deformation of one body — it CANNOT fragment into separate
// blobs (the §1.4 idea-to-protect). Directions are body-space unit vectors with a
// little musical logic: low → down, melody → up, the rest → to the side.
constant float3 kNimbusDirBass   = float3(0.0, -0.970, 0.243);  // bass heaves DOWN (heavy/low)
constant float3 kNimbusDirVocals = float3(0.0,  0.970, 0.243);  // lead flares UP (the voice reaches up)
constant float3 kNimbusDirOther  = float3(0.970, 0.0,  0.243);  // other swells to the SIDE
constant float  kNimbusKickBulge = 0.20;   // whole-body inflate at full kick punch (drums)
constant float  kNimbusLobeBulge = 0.30;   // directional bulge at a full stem hit (cosine² falloff)
constant float  kNimbusKickBright = 0.55;  // brightness POP at full kick punch (on top of bloom)

// MARK: - Density field

// Analytic ellipsoidal envelope: 1 at the dense core, smoothly → 0 at the shell.
// Cheap (no noise) — also used directly for the secondary self-shadow march.
// `lobes` = (bassLobe, vocalsLobe, otherLobe, kickPunch) from NimbusState (NB.5).
static inline float nimbus_envelope(float3 p, float4 lobes, thread float& rrOut) {
    float3 bp = p / kNimbusSemiAxes;
    float rr = length(bp);
    rrOut = rr;   // ORIGINAL radius → the dense core stays centred while the shell bulges

    // NB.5 — per-stem bulge: drums inflate the WHOLE body (uniform punch);
    // bass/lead/other HEAVE it along their direction (a soft cosine lobe). All
    // added together and dividing the effective radius → a star-convex
    // deformation of ONE mass that cannot fragment into separate blobs.
    float bulge = kNimbusKickBulge * lobes.w;   // .w = kickPunch (whole-body, cheap)
    // Directional lobes: a cosine² falloff (cheap — pure mul-adds, no pow/sqrt;
    // the GPU predicates rather than branches here, and the envelope is evaluated
    // ~7× per in-body sample, so a transcendental at rest doubled the budget).
    // cos² is broad/soft, which is what "one blended mass" wants anyway.
    if (rr > 1e-4) {
        float3 n = bp / rr;   // normalised body-space direction
        float cb = max(0.0, dot(n, kNimbusDirBass));
        float cv = max(0.0, dot(n, kNimbusDirVocals));
        float cs = max(0.0, dot(n, kNimbusDirOther));
        bulge += kNimbusLobeBulge * (lobes.x * cb * cb
                                   + lobes.y * cv * cv
                                   + lobes.z * cs * cs);
    }
    float rrEff = rr / (1.0 + bulge);

    // Fuller shell for a substantial body (bulged boundary), multiplied by a
    // gaussian core boost centred on the ORIGINAL rr so the dense heart stays
    // put while the shell heaves; smoothly → 0 at the shell (rrEff ≈ 1.05).
    float shell = smoothstep(1.05, 0.12, rrEff);
    float core  = 0.50 + 1.05 * exp(-rr * rr * 3.2);
    return shell * core;
}

static inline float nimbus_envelope(float3 p, float4 lobes) {
    float rr;
    return nimbus_envelope(p, lobes, rr);
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
static inline float nimbus_density(float3 worldP, float flowT, float bodyScale,
                                   float4 lobes, texture3d<float> noiseVol, sampler smp) {
    // NB.4 — uniform bloom inflation. Scaling the sample position DOWN grows the
    // whole body (boundary AND internal billows together) so the gas reads as
    // puffing up with energy rather than gaining detail. bodyScale comes from
    // mix(kNimbusSizeFloor, kNimbusSizePeak, bloom) in the fragment.
    float3 p = worldP / bodyScale;

    float rr;
    float env = nimbus_envelope(p, lobes, rr);   // NB.5 per-stem bulge baked into the envelope
    if (env <= 0.001) { return 0.0; }   // outside the body → skip the noise cost

    // Off-lattice sample coordinate: a constant offset so the body is NOT centred
    // on a tile boundary / lattice point — centring there makes +δ and −δ sample
    // near-identical values across the seamless tile boundary → 4-fold mirror
    // symmetry (NB.3.0 finding). NB.4: the drift is advected by the bloom-
    // modulated flow phase (flowT) instead of raw wall-clock time, so the gas
    // flows faster with energy and eases to its slowest drift at silence.
    float3 q = p + float3(3.17, 1.73, 5.41)                          // off-lattice offset
                 + float3(0.0, -flowT * 0.015, flowT * 0.008);       // bloom-modulated flow

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

    // NB.3.3 — deepen LUMP/CREVICE contrast in the INTERIOR (ref 02) so the BACKLIT
    // cone self-shadow has 3D structure to carve; mix by coverage so it's full at the
    // dense core and zero at the wispy rim (ref 03 stays soft). Density-shape only.
    float billowsC = smoothstep(kNimbusLumpLo, kNimbusLumpHi, billows);
    billows = mix(billows, billowsC, coverage);

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

    // NB.3.3 — denser CORE (ref 01: a denser core falling off to wispy edges). The
    // coverage remap caps core density at the raw billow value, so the body read
    // evenly thin. A radial boost adds substance at the centre (which, BACKLIT, then
    // self-shadows into ref 08's dark core + bright scattering rim) while leaving the
    // already-feathered edges (coreW→0 → ×1) wispy. Pure density; lighting unchanged.
    float coreW = exp(-rr * rr * kNimbusCoreSig);
    density = clamp(density * (1.0 + kNimbusCoreGain * coreW), 0.0, 1.0);

    return density;
}

// MARK: - Nimbus fragment (NB.3 look + NB.4 bloom + NB.5 stem beat-lobes)

fragment float4 nimbus_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                constant NimbusStateGPU& nb [[buffer(6)]],
                                texture3d<float> noiseVolume [[texture(6)]]) {
    // ── View ray (fixed camera + FOV, aspect-corrected) ──────────────────────
    float2 uv = in.uv;
    float2 p = uv - 0.5;
    p.x *= max(features.aspect_ratio, 1e-4);
    float3 ro = float3(0.0, 0.0, kNimbusCamZ);
    float3 rd = normalize(float3(p.x, -p.y, kNimbusFocal));  // -p.y: uv.y=0 is top → +world-up

    // ── NB.4 bloom (slow swell) + NB.5 stem beat-lobes (the band plays the body) ──
    // bloom = slow overall size/brightness swell (mean stem energy). kickPunch +
    // the three lobes are the per-stem beat response (DESIGN §1.3). NO mood read
    // yet (valence/arousal is NB.6).
    float bloomV    = clamp(nb.bloom, 0.0, 1.15);
    float bodyScale = mix(kNimbusSizeFloor, kNimbusSizePeak, bloomV);      // slow body extent
    // NB.5: the kick punch pops brightness on top of the slow bloom luminosity.
    float bright    = mix(kNimbusBrightFloor, kNimbusBrightPeak, bloomV)
                      * (1.0 + kNimbusKickBright * nb.kickPunch);          // + beat brightness pop
    float flowT     = nb.flowPhase;                                        // gas flow phase
    // Per-stem bulge amplitudes, packed (bass, lead/vocals, other, kick) for the
    // envelope's star-convex heave (.w = drums whole-body punch).
    float4 lobes    = float4(nb.bassLobe, nb.vocalsLobe, nb.otherLobe, nb.kickPunch);

    // ── Non-black haze floor (D-037 / DESIGN §1.4-§1.5): a faint cool halo,
    // brightest near the body, fading to near-black corners (negative space
    // preserved — NOT 05_anti_uniform_fog). Used as the background everywhere
    // the body doesn't fully occlude. Eased with bloom but with a hard non-zero
    // floor so the silence frame is provably non-black.
    float  hazeR2  = dot(p, p);
    float  hazeAmt = kNimbusHazeBase * (0.60 + 0.40 * clamp(bloomV, 0.0, 1.0));
    float3 haze    = kNimbusHazeColor * hazeAmt * exp(-hazeR2 * kNimbusHazeFalloff);

    // ── Bounding-sphere intersection (grows with the bloomed body). The env
    // early-out makes the in-sphere / outside-body steps nearly free — a loose
    // sphere is *cheaper* than a tight ellipsoid here because it spends most
    // steps in empty space that early-outs, rather than forcing every step
    // through the noise field.
    // Grow the bound for the bloomed body AND the CURRENT max NB.5 bulge (the
    // largest a point can heave right now = kick + the strongest single lobe) so
    // a heave never clips against the march bound — but only as much as the live
    // amplitudes need, so the baseline (no-lobe) march isn't coarsened.
    float maxBulge = kNimbusKickBulge * nb.kickPunch
                   + kNimbusLobeBulge * max(nb.bassLobe, max(nb.vocalsLobe, nb.otherLobe));
    float boundR = kNimbusBoundR * bodyScale * (1.0 + maxBulge);
    float bq = dot(ro, rd);                       // sphere centred at origin
    float cq = dot(ro, ro) - boundR * boundR;
    float disc = bq * bq - cq;
    if (disc < 0.0) { return float4(toneMapACES(haze), 1.0); }   // ray misses → haze only
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
    // NB.4: scale the BACK-key + ambient together by `bright` so the whole body
    // dims at the silence floor and brightens (+80 %) at full bloom, while the
    // backlit rim-vs-core contrast ratio (the approved NB.3 look) is preserved.
    float3 lightColor = float3(1.00, 0.97, 0.92) * 10.0 * bright;   // neutral warm-white BACK-key (NB.3.3 step 3): lifts the forward-scatter silver-lining rim (ref 08). No emission — the dense core stays self-shadowed; the rim-vs-core contrast IS the glow.
    float3 ambient    = float3(0.016, 0.020, 0.045) * bright;       // cool fill LIFTED (NB.3.3 step 3b): the contrast-darkened core read "too dark" (Matt), so raise the floor slightly above baseline → body reads present + slightly brighter, while the step-3 forward-scatter rim still carries the glow.

    // ── Front-to-back single-scatter march ──────────────────────────────────
    VolumeSample acc = vol_sample_zero();
    float dt = (t1 - t0) / float(kNimbusSteps);
    // Cone self-shadow reach tracks the bloomed body so the backlit billow depth
    // reads consistently as the body breathes (NB.4).
    float shadowDt = kNimbusShadowDt * bodyScale;
    int litSteps = 0;
    for (int i = 0; i < kNimbusSteps; i++) {
        float ti = t0 + (float(i) + 0.5) * dt;
        float3 pos = ro + rd * ti;
        float dens = nimbus_density(pos, flowT, bodyScale, lobes, noiseVolume, linearSampler);
        if (dens > 0.002) {
            litSteps++;
            // Detail-aware CONE self-shadow (NB.3.2): march toward the light
            // accumulating the real billow DENSITY (not the smooth envelope), so
            // the crevices between cauliflower lumps fall into shadow and thin
            // edges stay lit → the 3D billow read. This is the cost driver the
            // plan flagged (re-measured at NB.8).
            float densToLight = 0.0;
            for (int j = 1; j <= kNimbusShadowN; j++) {
                float3 sp = pos + lightDir * (float(j) * shadowDt);
                densToLight += nimbus_density(sp, flowT, bodyScale, lobes, noiseVolume, linearSampler);
            }
            float shadow = exp(-densToLight * shadowDt * kNimbusShadowSig);
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
    // Composite the body over the faint cool haze floor (NB.4 / D-037 — never
    // pure black at steady state). Where the body is opaque, transmittance → 0
    // and the haze is hidden; in the gaps and around the silhouette it reads as
    // a dim halo.
    float3 outc = acc.color * tint + haze * acc.transmittance;
    outc = toneMapACES(outc);
    return float4(outc, 1.0);
#endif
}
