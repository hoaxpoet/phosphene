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
constant int    kNimbusSteps     = 64;     // primary march steps (the cheap shadow density + 2-octave cascade keep crispness within budget; >64 just aliases the fine octave)
constant int    kNimbusShadowN   = 6;      // secondary light-march steps
constant float  kNimbusShadowDt  = 0.32;   // light-march step length (reach ≈ full body depth — grown with the body, NB.3.3)
constant float  kNimbusSigma     = 1.55;   // primary extinction (translucent: see INTO the volume)
constant float  kNimbusShadowSig = 3.40;   // self-shadow extinction — STRONGER (NB.3.3) → deeper dark crevices vs bright forward-scatter rim (the backlit silver lining)
constant float  kNimbusCamZ      = -6.0;   // camera distance (looking +Z)
constant float  kNimbusFocal     = 1.30;   // FOV (larger = narrower). NB.3.4: 1.44→1.30 (~10% smaller on-screen, Matt-directed for budget — fewer body-pixels do the expensive march; ~19% fewer). Still above the pre-NB.3.3 1.25.
constant float  kNimbusPhaseG    = 0.70;   // Henyey-Greenstein anisotropy — stronger forward scatter (NB.3.3 step 3) → brighter silver-lining rim where rays graze thin edges toward the back-key (ref 08)

// NB.3.1 Perlin-Worley density (HZD / "Nubis"). Scales are body-space sample
// units; noiseVolume tiles every 1.0 and itself holds ~4 billow cycles per tile.
constant float  kNimbusBillowScale = 0.40;  // NB.3.5: base billow frequency 0.55→0.40 → BIGGER primary lobes (huge cauliflower with sub-lobes from the cascade, rolling like the refs) instead of small uniform lumps
constant float  kNimbusDetailErode = 0.40;  // NB.3.4: how hard the Worley cascade carves the billow edges (was 0.32 — deeper crevices, ref 02)

// NB.3.4 — fractal detail CASCADE (ref 02 cauliflower + 03 filaments). Three
// Worley octaves at rising frequency carve the billows into nested cauliflower
// lumps + curling edge filaments; each noiseVolume tap already blends 3 Worley
// sub-octaves (G/B/A), so this is ~9 effective octaves. noiseVolume samples are
// near-free vs ALU (§6.1) — buy crispness with octaves, not computed noise.
constant float  kNimbusDetailS1 = 1.70;  // medium knobble (≈ old single detail octave)
constant float  kNimbusDetailS2 = 3.60;  // fine (finest the 64-step march resolves without aliasing)

// NB.3.4 — INTERIOR cauliflower carve. The HZD edge-erosion above leaves the core
// smooth (realistic for a distant cloud, but ref 02 is a close-up — lump/crevice
// detail EVERYWHERE). This multiplicatively carves crevices (×lo) and keeps lumps
// (×hi) throughout the body from the same fractal detail, so the cone self-shadow
// then has interior structure to darken → crisp cauliflower, not a smooth blob.
constant float  kNimbusInteriorCarve = 0.70;  // 0 = smooth core (old), 1 = fully carved
constant float  kNimbusCarveLo = 0.30;  // crevice density multiplier (darkens between lumps)
constant float  kNimbusCarveHi = 1.18;  // lump density multiplier (brightens lump tops)

// NB.3.5 — RISING, CURLING SMOKE motion (Matt's chosen character). The gas RISES
// (vertical domain scroll), TWISTS as it rises (a height+time helical rotation →
// curling vortices), and its fine detail CHURNS faster than the base (billows
// form/dissolve in place, not just slide). All rates ride flowT (the NB.4 bloom-
// modulated clock) so the smoke rises/curls faster with energy and drifts at
// silence. ~20× the old linear-drift rate — it was imperceptible before.
constant float  kNimbusRiseRate   = 0.34;  // vertical scroll: body-units of rise per unit flowT
constant float  kNimbusTwistFreq  = 0.30;  // helical curl: twist angle (rad) per body-unit of height (gentle torsion, not a tornado)
constant float  kNimbusTwistRate  = 0.26;  // the curl itself rotates over time (rad per unit flowT)
// Organic ROLLING — two octaves of noise domain-warp give the billows-rolling-
// over-each-other character of the references (dense churning smoke), not a clean
// twist. Big rolls + medium churn; the warp fields themselves rise/drift.
constant float  kNimbusSwirlAmp   = 0.40;  // big-roll warp amplitude
constant float  kNimbusSwirl2Amp  = 0.18;  // medium-churn warp amplitude
constant float  kNimbusSwirl1Scale = 0.27; // big-roll spatial scale
constant float  kNimbusSwirl2Scale = 0.85; // medium-churn spatial scale
constant float  kNimbusDetailChurn = 0.45; // fine detail evolves this much faster than the base drift

// MARK: - NB.6 Mood (DESIGN §1.3 / §5.4)

// Valence → body colour cool↔warm (the 06_palette axis): deep indigo at the low
// pole, warm gold/amber at the high pole. Arousal → flow agitation: calm =
// smoother lobes + gentler roll; energetic = more torn edges + stronger churn.
// Both smoothed ~4 s in NimbusState (FA #25) and crawl at the section timescale.
// NB.10 (D-142, Matt M7 r1): poles SATURATED for an expressive cool↔warm swing
// (the prior muted lavender/soft-gold read "white/gray" once the bright core
// washed out — Matt's Billie Jean note). Cool = vivid indigo-violet; warm =
// rich amber/gold.
constant float3 kNimbusMoodCool   = float3(0.30, 0.26, 0.95);  // low warmth — vivid indigo-violet
constant float3 kNimbusMoodWarm   = float3(1.00, 0.56, 0.14);  // high warmth — rich amber/gold
constant float3 kNimbusAmbCool    = float3(0.014, 0.018, 0.055); // cool fill (the NB.3.3 ambient) — low warmth
constant float3 kNimbusAmbWarm    = float3(0.060, 0.034, 0.012); // warm fill — high warmth (shadow side warms too)
constant float  kNimbusAgitCalm   = 0.65;  // arousal −1 → calmer (smoother lobes, less churn)
constant float  kNimbusAgitWild   = 1.55;  // arousal +1 → wilder (torn edges, stronger churn)

// NB.10 (D-142) — ENERGY warms the body for genuine bangers. Matt M7 r1: an
// energetic track (B.O.B.) read cool/purple because colour tracked valence only
// (the classifier hears aggressive-but-dark as low-valence). r1.5 fix: warmth is
// PRIMARILY valence; high AROUSAL (the classifier's intensity read — more
// reliable than the often-near-zero `bloom` in real captures) adds warmth ONLY
// past a high threshold, so it never washes out the cool↔warm axis. (r1's flat
// +energy bias turned every moderate-energy track warm and collapsed the range —
// the "clobbered / neutral" regression.)
constant float  kNimbusEnergyWarmth = 0.50;  // max warmth lift at full arousal (a banger)
constant float  kNimbusEnergyLo     = 0.65;  // arousal01 where energy-warmth STARTS (arousal +0.30); below = pure valence
constant float  kNimbusEnergyHi     = 0.95;  // arousal01 for the full lift (arousal +0.90)
constant float  kNimbusMoodContrast = 1.60;  // expand the (often subtle) VALENCE travel around mid so it reads clearly
// Bright core keeps its MOOD HUE (brightened), it does NOT wash to white — the
// old near-white desaturation killed the colour on the most-visible pixels.
constant float  kNimbusCoreHueGain  = 1.55;  // brighten the mood hue at the dense core (luminance, same hue)
constant float  kNimbusCoreWhiteAdd = 0.10;  // a small white lift for only the very hottest pixels
constant float  kNimbusCoreWash     = 0.62;  // cap on how much the core lightens (leaves the hue intact)

// NB.3.4 — interior lump/crevice contrast (ref 02: deep crevices between cauliflower
// lumps). TIGHTER window than NB.3.3 → sharper lit lumps + darker crevices (less
// blurry). Gated by coverage so the soft feathered rim (ref 03) is not fragmented.
constant float  kNimbusLumpLo   = 0.32;  // contrast window low  → deepens crevices (was 0.20)
constant float  kNimbusLumpHi   = 0.70;  // contrast window high → sharpens lit lumps (was 0.82)

// NB.3.3 — denser CORE for substance (ref 01: a denser core falling to wispy edges).
// Backlit (existing model), a denser core self-shadows into ref 08's dark-core /
// bright-rim — substance, not a glow source. Pure density; no emission.
constant float  kNimbusCoreGain = 0.55;  // density boost added at the centre (0 = none) — eased so the core gains substance without saturating flat (keeps ref-02 interior lumps)
constant float  kNimbusCoreSig  = 1.50;  // core falloff (larger = tighter dense core)

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
    float valence;     // NB.6 mood — smoothed valence (-1 cool · +1 warm)
    float arousal;     // NB.6 mood — smoothed arousal (-1 calm · +1 churning)
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
constant float  kNimbusKickBulge = 0.26;   // NB.5 recal: whole-body inflate at full kick punch (drums) — bigger for more motion
constant float  kNimbusLobeBulge = 0.42;   // NB.5 recal: directional bulge at a full stem hit (cosine²) — bigger so the heave reads
constant float  kNimbusKickBright = 0.72;  // NB.5 recal: brightness POP at full kick punch (on top of bloom)

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
                                   float4 lobes, float agitation,
                                   texture3d<float> noiseVol, sampler smp) {
    // NB.4 — uniform bloom inflation. Scaling the sample position DOWN grows the
    // whole body (boundary AND internal billows together) so the gas reads as
    // puffing up with energy rather than gaining detail. bodyScale comes from
    // mix(kNimbusSizeFloor, kNimbusSizePeak, bloom) in the fragment.
    float3 p = worldP / bodyScale;

    float rr;
    float env = nimbus_envelope(p, lobes, rr);   // NB.5 per-stem bulge baked into the envelope
    if (env <= 0.001) { return 0.0; }   // outside the body → skip the noise cost

    // ── NB.3.5 RISING, CURLING SMOKE motion (flowT = NB.4 bloom-modulated clock) ──
    // 1. Helical twist — rotate the horizontal plane by an angle that grows with
    //    height and time, so the rising gas CURLS into vortices (a slow torsion).
    float twist = p.y * kNimbusTwistFreq + flowT * kNimbusTwistRate;
    float ct = cos(twist), st = sin(twist);
    float3 pt = float3(ct * p.x - st * p.z, p.y, st * p.x + ct * p.z);
    // 2. Rise — scroll the sample coordinate DOWN so features travel UP through the
    //    body. 3. Off-lattice offset (kills the tile-boundary 4-fold mirror, NB.3.0).
    float rise = flowT * kNimbusRiseRate;
    float3 q = pt + float3(3.17, 1.73, 5.41) - float3(0.0, rise, 0.0);
    // 4. Organic ROLLING — two noiseVolume warps (big rolls + medium churn) so the
    //    billows roll over each other like dense churning smoke (the motion refs),
    //    not a uniform twist. Each warp field rises/drifts so the rolls travel up.
    float3 sw1 = noiseVol.sample(smp, q * kNimbusSwirl1Scale - float3(0.0, rise * 0.6, 0.0)).rgb - 0.5;
    float3 sw2 = noiseVol.sample(smp, q * kNimbusSwirl2Scale
                                 + float3(rise * 0.3, -rise * 0.45, rise * 0.2)).rgb - 0.5;
    q += sw1 * kNimbusSwirlAmp + sw2 * kNimbusSwirl2Amp;

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

    // ── Detail erosion CASCADE (NB.3.4): three Worley octaves at rising frequency
    // carve the billow into nested cauliflower lumps (ref 02) + curling edge
    // filaments (ref 03). Decorrelated from the base so it adds structure rather
    // than echoing it. Each tap blends 3 Worley sub-octaves → ~9 effective octaves.
    // dq churns faster than the base (extra rise) so the fine billows FORM and
    // DISSOLVE as they travel, rather than rigidly sliding with the big lobes.
    float3 dq  = q + float3(11.3, 4.7, 8.9) - float3(0.0, flowT * kNimbusDetailChurn, 0.0);
    float4 d1  = noiseVol.sample(smp, dq * kNimbusDetailS1);
    float4 d2  = noiseVol.sample(smp, dq * kNimbusDetailS2);
    float  wf1 = d1.g * 0.625 + d1.b * 0.25 + d1.a * 0.125;
    float  wf2 = d2.g * 0.625 + d2.b * 0.25 + d2.a * 0.125;
    float  detailFBM  = wf1 * 0.62 + wf2 * 0.38;   // fractal Worley (2 taps; the scale-7.6 octave only aliased at 64 steps)
    float  edgeWeight = 1.0 - coverage;                         // 0 core → 1 shell
    // Erode hardest at the rim (fraying filaments) but keep some interior carve so
    // the core surface is knobbly too (ref 02 detail is everywhere, not just edges).
    // `agitation` (NB.6 ← smoothed arousal) is the flow-agitation knob: calm =
    // smoother lobes, energetic = more torn / churning edges.
    float  erodeAmt = kNimbusDetailErode * agitation * (0.25 + 0.75 * edgeWeight);
    float  erodeLo  = clamp((1.0 - detailFBM) * erodeAmt, 0.0, 0.92);
    density = clamp(nimbus_remap(density, erodeLo, 1.0, 0.0, 1.0), 0.0, 1.0);

    // NB.3.3 — denser CORE (ref 01: a denser core falling off to wispy edges). The
    // coverage remap caps core density at the raw billow value, so the body read
    // evenly thin. A radial boost adds substance at the centre (which, BACKLIT, then
    // self-shadows into ref 08's dark core + bright scattering rim) while leaving the
    // already-feathered edges (coreW→0 → ×1) wispy. Pure density; lighting unchanged.
    float coreW = exp(-rr * rr * kNimbusCoreSig);
    density = clamp(density * (1.0 + kNimbusCoreGain * coreW), 0.0, 1.0);

    // NB.3.4 — interior cauliflower carve (ref 02): the fractal detail darkens
    // crevices and lifts lump tops THROUGHOUT the body (not just the rim), so the
    // backlit cone self-shadow has interior structure to bite into → crisp lumps,
    // not a smooth gradient. Multiplicative contrast, not removal (stays connected).
    float lumps = smoothstep(0.32, 0.68, detailFBM);            // 0 crevice → 1 lump
    float carve = mix(1.0, mix(kNimbusCarveLo, kNimbusCarveHi, lumps), kNimbusInteriorCarve);
    density = clamp(density * carve, 0.0, 1.0);

    return density;
}

// Cheap density for the cone SELF-SHADOW march (NB.3.4). The shadow march runs
// ~6× per in-body primary step; paying the full detail cascade + swirl there
// blew the budget to ~20 ms. The self-shadow only needs the COARSE density (lit
// top vs shadowed underside = the macro depth), not the fine crevice detail —
// so this is the base billow only (1 sample), with the rise+twist motion (no
// extra samples) so the shadow tracks the body. ~1 sample vs ~7.
static inline float nimbus_density_shadow(float3 worldP, float flowT, float bodyScale,
                                          float4 lobes, texture3d<float> noiseVol, sampler smp) {
    float3 p = worldP / bodyScale;
    float rr;
    float env = nimbus_envelope(p, lobes, rr);
    if (env <= 0.001) { return 0.0; }
    float twist = p.y * kNimbusTwistFreq + flowT * kNimbusTwistRate;
    float ct = cos(twist), st = sin(twist);
    float3 pt = float3(ct * p.x - st * p.z, p.y, st * p.x + ct * p.z);
    float rise = flowT * kNimbusRiseRate;
    float3 q = pt + float3(3.17, 1.73, 5.41) - float3(0.0, rise, 0.0);
    float4 base = noiseVol.sample(smp, q * kNimbusBillowScale);
    float worleyFBM = base.g * 0.625 + base.b * 0.25 + base.a * 0.125;
    float billows = clamp(nimbus_remap(base.r, worleyFBM - 1.0, 1.0, 0.0, 1.0), 0.0, 1.0);
    float coverage = clamp(env, 0.0, 1.0);
    float density = clamp(nimbus_remap(billows, 1.0 - coverage, 1.0, 0.0, 1.0), 0.0, 1.0);
    float coreW = exp(-rr * rr * kNimbusCoreSig);
    return clamp(density * (1.0 + kNimbusCoreGain * coreW), 0.0, 1.0);
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

    // ── NB.6/NB.10 Mood (slow global) — warmth (valence + ENERGY) → colour,
    // arousal → agitation. Both ∈ [-1, 1], smoothed ~4 s in NimbusState. ───────
    float valence01 = clamp(nb.valence * 0.5 + 0.5, 0.0, 1.0);
    float arousal01 = clamp(nb.arousal * 0.5 + 0.5, 0.0, 1.0);
    // NB.10 r1.5 (D-142): warmth is PRIMARILY valence (sad → cool, happy → warm).
    // High AROUSAL adds warmth ONLY past a high threshold (a genuine banger reads
    // hot even at low valence — B.O.B.), so it never biases moderate tracks warm
    // and collapse the cool↔warm range (the r1 regression). Then expand around
    // mid so the often-subtle valence travel reads clearly (the "VERY subtle"
    // complaint). bloom stays out of the colour — it already drives size/bright.
    float energyWarm = kNimbusEnergyWarmth * smoothstep(kNimbusEnergyLo, kNimbusEnergyHi, arousal01);
    float warm01     = clamp(valence01 + energyWarm, 0.0, 1.0);
    warm01           = clamp((warm01 - 0.5) * kNimbusMoodContrast + 0.5, 0.0, 1.0);
    float3 moodTint = mix(kNimbusMoodCool, kNimbusMoodWarm, warm01);  // body colour
    float3 moodAmb  = mix(kNimbusAmbCool,  kNimbusAmbWarm,  warm01);  // fill warms too (D-022 propagation)
    float  agitation = mix(kNimbusAgitCalm, kNimbusAgitWild, arousal01); // erosion knob

    // ── Non-black haze floor (D-037 / DESIGN §1.4-§1.5): a faint cool halo,
    // brightest near the body, fading to near-black corners (negative space
    // preserved — NOT 05_anti_uniform_fog). Used as the background everywhere
    // the body doesn't fully occlude. Eased with bloom but with a hard non-zero
    // floor so the silence frame is provably non-black.
    float  hazeR2   = dot(p, p);
    float  hazeAmt  = kNimbusHazeBase * (0.60 + 0.40 * clamp(bloomV, 0.0, 1.0));
    // NB.6/NB.10: the halo warms with the body (warmth = valence + energy) so a
    // warm/energetic mood doesn't sit in a cool-blue halo. kNimbusHazeColor is the cool pole.
    float3 hazeCol  = mix(kNimbusHazeColor, float3(0.95, 0.52, 0.22), warm01);
    float3 haze     = hazeCol * hazeAmt * exp(-hazeR2 * kNimbusHazeFalloff);

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
    float3 ambient    = moodAmb * bright;       // NB.6: cool↔warm fill (valence) — so the shadow side warms with the mood too, not just the lit rim (D-022 propagation). Lifted floor (NB.3.3 step 3b) carried in kNimbusAmb*.

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
        float dens = nimbus_density(pos, flowT, bodyScale, lobes, agitation, noiseVolume, linearSampler);
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
                densToLight += nimbus_density_shadow(sp, flowT, bodyScale, lobes, noiseVolume, linearSampler);
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
    // ── Composite: mood-tinted body over the haze floor → ACES ───────────────
    // NB.6/NB.10: the body is tinted toward `moodTint` (vivid indigo ← cool/low-
    // energy … rich amber ← warm/energetic). NB.10 (D-142): the densest/brightest
    // core keeps its MOOD HUE, brightened (luminance, same hue) — it does NOT
    // desaturate to near-white. The old white-wash killed the colour on exactly
    // the brightest, most-visible pixels, so an energetic body read "white/gray"
    // (Matt M7 r1, Billie Jean). moodTint multiplies every body pixel so the
    // cool↔warm shift propagates across the whole mass.
    float  lum = dot(acc.color, float3(0.299, 0.587, 0.114));
    float3 moodBright = clamp(moodTint * kNimbusCoreHueGain + kNimbusCoreWhiteAdd, 0.0, 1.6);
    float3 tint = mix(moodTint, moodBright, smoothstep(0.9, 2.4, lum) * kNimbusCoreWash);
    // Composite the body over the faint cool haze floor (NB.4 / D-037 — never
    // pure black at steady state). Where the body is opaque, transmittance → 0
    // and the haze is hidden; in the gaps and around the silhouette it reads as
    // a dim halo.
    float3 outc = acc.color * tint + haze * acc.transmittance;
    outc = toneMapACES(outc);
    return float4(outc, 1.0);
#endif
}
