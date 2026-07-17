# Aurora Veil — Design

> **Amendment 2026-07-14: footprint reauthor (AV.5, D-185).** The shipped model renders the *right look, wrong expression* — a full-field wash, not discrete dancing curtains. The reauthor makes the Lawlor footprint `F(x,y)` a real footprint (bright bands + negative space) advected by curl-noise, keeping the nimitz texture; dramatic multi-colour palette (resets the anti-neon contract); half-bar star blink. See **§5.10** (architecture, musical-role sentence, temporal contract, concept bar) and §6 (updated anti-references). Session prompt: `prompts/AV.5-prompt.md`. Feasibility proven by the AV.4 spike (`memory: project_aurora_veil_reauthor`).

> **Amendment 2026-05-18: rendering architecture pivot.** Pre-implementation desk research surfaced three convergent authoritative prior-art references (nimitz "Auroras" / Lawlor & Genetti 2011 / Wittens NeverSeenTheSky) and a 15-mode failure-mode taxonomy. The original §5 specified a 2D pixel-shader "ribbon with horizontal proximity test against a `warped_fbm` centre-line + vertical fbm rays" — structurally distinct from every photographically-credible procedural aurora in the wild, and exposed to at least four named failure modes (#3, #9, #13, missing multi-timescale motion). §5 has been rewritten around the **volumetric-raymarch recipe**: per-pixel raymarch up a vertical column, triangular domain-warped noise (`triNoise2d`-style) sampled at each step, running-average vertical smear, per-march-step IQ-cosine palette cycling for Lawlor-Genetti height-curve stratification, mv_warp for substrate temporal compounding. Original §5 preserved verbatim in §5-LEGACY at end-of-doc for the iteration history. Research dossier: `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` (READ FIRST — load-bearing for the architectural rationale and the 9-question authenticity rubric used at AV.3 cert).

A direct-fragment + `mv_warp` preset rendering an aurora curtain over a faintly-starred night sky. Lowest-barrier authoring example in Phosphene's catalog: no SDF, no PBR, no mesh shader. Demonstrates the canonical Milkdrop pattern (direct fragment + per-vertex feedback warp) which currently has no consumer in the catalog.

## 1. Intent

A real aurora moves slowly. A real aurora is *colored* — green at the base, magenta at the crown, occasionally blue at low altitude — never uniformly neon. A real aurora has *structure* — folds, curtains, shimmering rays — at multiple scales. A real aurora is photographable in a way that no shader has authentically reproduced because every shader-aurora skips the slow-motion compounding that makes real ones feel alive.

Aurora Veil's job is to be the catalog's "ambient ribbon" preset — what plays during quiet listening, low-energy passages, the comedown after a peak. It pairs with Membrane and Gossamer in the Orchestrator's ambient-section bench.

**Audio summary.** Vocals pitch shifts hue along the ribbon length (the SpectralHistoryBuffer trail makes this trivial); `bass_att_rel` breathes brightness; `mid_att_rel` modulates fold density; `drums_energy_dev` kinks the curtain on accents; valence shifts the green/blue/magenta mix.

**Family.** `fluid` (ribbon dynamics; reuses the family-repeat penalty against Membrane / FerrofluidOcean / VolumetricLithograph). _Confirm enum value during sidecar writing._

**Render passes.** `["mv_warp"]` — direct fragment shader runs inside the warp-pass scene draw; mv_warp handles drawable presentation.

## 2. References

**Recommendation: curate.** Aurora has very specific real-world signatures that procedural shaders routinely miss; references are the difference between authentic aurora and "neon ribbon shader." Suggested images:

- **Curtain hero shot.** Auroral curtain over a dark landscape, full vertical structure visible (green base + pink/magenta crown + ray structure). E.g., Iceland or Yukon photography.
- **Color stratification close-up.** A frame where the green-to-magenta vertical gradient is unambiguous.
- **Multi-curtain composition.** Two or more overlapping curtains with parallax — the layered-ribbon target.
- **Fold detail.** A single curtain section with the meso-scale fold structure (the "drape" pattern) clearly visible.
- **Anti-reference: neon EDM aurora.** A festival-visual or Tron-style "aurora" so the contrast is documented.

The existing `15_atmosphere_aurora_forest.jpg` in `docs/VISUAL_REFERENCES/arachne/` is a usable starting point but it's a foreground-trees-with-aurora-backdrop composition; we want hero-aurora frames where the curtain fills frame.

## 3. Trait matrix

| Scale | Trait |
|---|---|
| **Macro** | One to three vertical curtain ribbons spanning frame height. Ribbons curve gently along x; vertical extent tapers at top and bottom. |
| **Meso** | Per-ribbon fold structure: 4-8 folds along x, fold density modulated by `mid_att_rel`. Fold sharpness varies. |
| **Micro** | Vertical "ray" striations within each curtain — fine pillars that read as the discrete electron-precipitation columns of real aurora. |
| **Specular breakup** | Per-pixel brightness variation via `blue_noise_sample` for grain; smooth temporal accumulation via mv_warp masks the noise into shimmer rather than sizzle. |
| **Material** | Emission-only. No PBR. Lightweight rubric profile per D-067(b). |
| **Lighting** | None directly. The curtain *is* a light source. Sky glow falls off radially from the brightest ribbon section. Faint ambient sky color underlies everything. |
| **Motion** | mv_warp slow rotation + slow zoom; ribbon center-line shifts via low-frequency `warped_fbm`; vertical ray phase advances with continuous `bass_att_rel`. No free-running `sin(time)` (CLAUDE.md Arachne tuning rule). |
| **Audio reactivity** | See §5.6. |

## 4. Renderer capability audit

| Need | Available? | Notes |
|---|---|---|
| Direct fragment pipeline | ✓ | Plasma / Nebula / Waveform / Gossamer use it. |
| `mv_warp` pass | ✓ | D-027; Gossamer is current consumer. |
| `warped_fbm`, `curl_noise` | ✓ | V.1 noise utility tree. |
| `blue_noise_sample` for grain | ✓ | Noise/BlueNoise.metal. |
| `palette_cool` / IQ cosine palette | ✓ | Color/Palettes.metal (V.3). |
| `SpectralHistoryBuffer` for pitch trail | ✓ | buffer(5), 480 samples of `vocalsPitchNorm` at offset [1920..2399]. |
| Hash-based starfield | ✓ | `hash_f01_2` from Noise/Hash.metal. |

**No blocking gaps.** This preset uses only existing utilities — that's the point of picking it as the entry-level demonstration. No engine work required.

## 5. Rendering architecture (amended 2026-05-18)

**Architectural prior art (READ THESE FIRST).** Three convergent references from the 2026-05-18 desk research dossier (`AURORA_VEIL_RESEARCH_2026-05-18.md`):

1. **nimitz "Auroras" (Shadertoy XtGGRt, 2017)** — the canonical procedural-aurora recipe. Triangular domain-warped noise + 50-step volumetric raymarch + running-average smear + per-march-step palette cycling. Phosphene's recipe is a clean-room MSL reimplementation of this algorithm (Shadertoy source is CC-BY-NC-SA, incompatible with MIT; algorithms aren't copyrightable, code is).
2. **Lawlor & Genetti, *Interactive Volume Rendering Aurora on the GPU* (WSCG 2011)** — the physical anchor. `emission = H(altitude) × F(x, y)` factorization: 1D height curve × 2D electron-flux footprint. nimitz's per-march-step palette IS the Lawlor `H(z)` curve; `triNoise2d` IS the Lawlor `F(x, y)`.
3. **Wittens NeverSeenTheSky (2013)** — the motion reference. Real aurora motion is curling vortical, not pan-the-noise-coordinate. We borrow curl-noise advection (cheap) without paying the full fluid-solver cost (expensive).

### 5.1 Pass structure

`passes: ["mv_warp"]`. The fragment shader (`aurora_fragment`) is invoked by the mv_warp scene draw; output goes to `warpState.sceneTexture`; the warp pass then performs its 32×24 vertex-grid per-pixel feedback and presents to drawable.

### 5.2 Scene composition

Three layers, back to front:

**1. Sky.** Vertical gradient: top `(0.005, 0.005, 0.02)` (deep night), bottom `(0.01, 0.015, 0.04)` (slightly warmer near horizon). Sparse stars from `hash_f01_2(uv * 800) > 0.997`, brightness varied by a secondary hash. **Additive composite**, so stars punch through aurora (Failure Mode #5 avoided).

**2. Aurora — volumetric vertical-column raymarch.** Per fragment, march 50 steps up an implicit vertical "column" rooted at the fragment's screen position. At each step `i ∈ [0, 50)`:

```metal
// Polynomial step distance — dense near bottom, coarse near top.
// (Adapted from nimitz; concentrates samples where stratification is sharpest.)
float pt = 0.8 + pow(float(i), 1.4) * 0.002;

// March position in "world" (column space). uv.x = horizontal in frame; pt = altitude.
float2 marchPos = float2(uv.x, pt);

// Sample the 2D ribbon-shape field (triangular domain-warped noise).
float rzt = tri_noise_2d(marchPos, 0.06 /* drift speed */);

// Per-march-step palette cycle (the Lawlor H(z) height curve).
// sin(...) advances with i, so green sits at low-i, magenta at high-i.
float3 col2 = (sin(1.0 - float3(2.15, -0.5, 1.2) + float(i) * 0.043) * 0.5 + 0.5) * rzt;

// Running-average smear — converts vertical noise samples into vertical ribbons.
// Without this line, the result reads as volumetric salt-and-pepper; with it,
// adjacent altitudes blur into coherent vertical streaks. Load-bearing.
avgCol = mix(avgCol, float4(col2, rzt), 0.5);

// Exponential decay accumulator — early (low-altitude) samples contribute most.
col += avgCol * exp2(-float(i) * 0.065 - 2.5) * smoothstep(0.0, 5.0, float(i));
```

Final aurora colour `col * 1.8` (modest gain); the IQ-cosine sin() produces values in `[0, 1]` per channel, so the accumulator stays within reasonable HDR range.

**Triangular domain-warped noise `tri_noise_2d` — clean-room MSL.** Five iterations of:
- triangular waveform `tri(x) = clamp(abs(fract(x) - 0.5), 0.01, 0.49)` (sharp ribbon edges; Perlin is too blurry);
- 2D triangle noise `tri2(p) = float2(tri(p.x) + tri(p.y), tri(p.y + tri(p.x)))`;
- per-octave rotation `mm2(time * spd)` for biological asymmetry across the frame;
- per-octave domain warp `p -= dg / z2` with `z2 *= 0.45` decay;
- final return `clamp(1.0 / pow(rz * 29.0, 1.3), 0, 0.55)`.

Algorithm exposure in `AURORA_VEIL_RESEARCH_2026-05-18.md §1.1`. Implementer reimplements from the description, citing nimitz + Lawlor in the shader header. **Do NOT substitute the engine's existing `fbm8` for `tri_noise_2d`** — Perlin-derived smoothed octaves produce fog-like blurry ribbons (Failure Mode #8); the triangular waveform is what gives aurora its sharp edges.

**3. Composite.** `final = sky + aurora`. Additive only. Foreground is sky-context dark, not aurora-lit (Failure Modes #5, #14, #15 avoided).

### 5.3 mv_warp specifics

- Per-frame: `baseRot = 0.0008 + valence * 0.0004` (slow rotation), `baseZoom = 0.0015` (slight inward drift), `decay = 0.945`.
- Per-vertex: UV displacement `disp = curl_noise(float3(uv * 2.0, time * 0.1)).xy * 0.005`. The curl-noise advection (rather than straight time-pan) mimics NeverSeenTheSky's vortical-flow signature without paying the fluid-solver cost.
- Audio-modulated component (rare-event gated, see §5.6): `disp += float2(0, kinkAccumulator * 0.003 * sin(uv.x * 12))`. **`kinkAccumulator` is NOT raw `drums_energy_dev`** — see §5.6 for the gating + damped-response form.
- Decay 0.945: shorter than Gossamer's 0.955 (less echo) but long enough to give the substrate a 1-second persistence trail.

### 5.4 Multi-timescale motion (Failure Mode #4 mitigation — non-negotiable)

Real aurora moves on **four separable timescales** (research §2.1). Phosphene's mechanism per scale:

| Timescale | What moves | Phosphene mechanism |
|---|---|---|
| **Minutes (substorm advance)** | Whole-hemisphere brightening | Not modelled at AV (we render ~30s panels); future increment if needed |
| **Tens of seconds (substrate drift)** | Curtain undulation, ribbon-shape evolution | `tri_noise_2d` time argument at `spd = 0.06`; mv_warp `decay = 0.945` |
| **2–20 seconds (whole-curtain pulsation)** | Brightness pulses | `aurora *= 0.85 + 0.15 * fbm2(float2(time * 0.1, 0.0))` — slow envelope multiplier on the entire raymarch result |
| **0.1–0.2 s (5–10 Hz ray flicker)** | Per-ray local brightness flicker in bright pillars | `rzt *= 1.0 + 0.10 * fbm2(float2(uv.x * 4.0, time * 8.0))` — subsecond modulation at the per-march-step density level. **AV.3 polish, not AV.1.** |

AV.1 implements substrate-drift + mv_warp only. AV.2 adds the audio-coupled enrichment. AV.3 adds the 2–20 s pulsation envelope + the sub-second flicker.

### 5.5 Composition (Failure Modes #9 + #12 mitigation)

- **Off-axis bias.** The implicit column position is `uv.x` directly (no centre-line offset), but the `tri_noise_2d` field's biological asymmetry produces brightness concentrations off-axis by construction. No additional bias needed — but at AV.2, the second + third ribbons land at `uv.x + offset` with the offsets picked off-thirds (e.g. `0.27`, `-0.18`) rather than symmetric.
- **Dark sky context.** Sky gradient peaks at `(0.01, 0.015, 0.04)` — near-black. Aurora is the only chromatic emission in frame. No daytime / sunset / twilight contexts.
- **Soft top, sharp bottom (Failure Mode #13 mitigation).** The polynomial step distance `0.8 + pow(i, 1.4) * 0.002` + the exponential decay `exp2(-i * 0.065 - 2.5)` together produce a denser, brighter accumulation near low altitude and a soft fade at high altitude. The bottom is sharp (lots of bright samples accumulated quickly); the top dissolves (decay dominates). Physically correct.

### 5.6 State

No CPU-side state. All evolution is mv_warp-accumulated + per-frame triangular-noise sample.

**Audio-driven accumulators (introduced at AV.2, not AV.1):**

- **`kinkAccumulator`** (rare-event gated, damped response). Initialised at `0.0`. Updated each frame: `kinkAccumulator = max(kinkAccumulator * 0.93, drums_energy_dev * smoothstep(0.4, 0.7, drums_energy_dev))`. Decays at ~0.5/second; charges only on rare high-amplitude drum events. The visual response is a 1–2 s slow shudder, not a sharp instantaneous deflection. **Mandatory mitigation for Failure Mode #11 (festival-strobe).**
- **`pulseEnvelope`** (continuous, multi-second). Smoothed `fbm2(time * 0.1)` per §5.4; precomputed at the mv_warp `q1`/`q2` register or evaluated per-frame in fragment.

### 5.7 Audio routing (amended 2026-05-18)

| Driver | Source | Effect | Continuous/accent |
|---|---|---|---|
| Hue along ribbon | `stems.vocals_pitch_hz` + `vocals_pitch_confidence` (MV-3c, normalized) | Per-march-step palette phase offset; smoothed via 5-frame moving average | continuous |
| Brightness breathing | `f.bass_att_rel` | Aurora overall scale `(0.85 + 0.30 × x)` | continuous |
| Fold density / curtain texture | `f.mid_att_rel` | Multiplies `tri_noise_2d` spatial frequency: `tri_noise_2d(marchPos * (1.0 + 0.3 * f.mid_att_rel), spd)` | continuous |
| Substrate drift speed | `f.bass_att_rel` | `tri_noise_2d` spd argument: `spd = 0.06 + 0.04 * f.bass_att_rel` | continuous |
| Curtain kink | `kinkAccumulator` (gated on `stems.drums_energy_dev`) | mv_warp y-displacement amplitude | accent (rare-event, damped) |
| Palette warm/cool | `f.valence` | Per-march-step palette phase additive offset (`+0.1 * f.valence`) | continuous |
| Star twinkle | `f.beat_phase01` (gated by `vocalsPitchConfidence > 0.5`) | Per-star brightness modulation, subtle | accent |

**Vocals-pitch sourcing (research §3.3).** The original spec referenced `SpectralHistoryBuffer[1920..]` which is `offsetBarPhase`, not vocal pitch. Resolution: read `stems.vocals_pitch_hz` + `stems.vocals_pitch_confidence` directly. Normalize: `vocalsPitchNorm = clamp(log2(pitch_hz / 80.0) / 4.0, 0, 1)` (E2 ≈ 80 Hz → 0, C7 ≈ 2093 Hz → ~1). Pre-pitch-detection or low-confidence fallback: `vocalsPitchNorm = 0.5` (mid-palette neutral).

**D-026 compliance:** every primary driver uses `*_rel` or `*_dev`. No absolute thresholds.

**D-019 compliance:** stem reads gated through `smoothstep(0.02, 0.06, totalStemEnergy)` warmup blend; FeatureVector proxy used pre-warmup.

**Continuous-vs-accent ratio:** brightness breathing amplitude 0.30; curtain kink amplitude 0.003 UV × `kinkAccumulator` (peak ~0.3 on rare events). Continuous primary drivers dominate by ≥ 10× at all times. The gated kink doubles the dominance margin vs the original spec.

### 5.8 Silence fallback

At `totalStemEnergy = 0` and zero deviation: aurora renders at base brightness (0.85 × 1.0 = 0.85 effective gain); `tri_noise_2d` drifts at base `spd = 0.06`; `kinkAccumulator` decays to zero; pulsing envelope continues at its `fbm2(time * 0.1)` baseline (no audio coupling). Curtains drift visually with the noise field's slow evolution. Stars are static (no twinkle without beat phase). Silence is meditative, not dead — form complexity ≥ 2 (sky + stars + drifting aurora column).

### 5.9 Lighting / atmosphere

None. Emission-only. Sky colour provides the ambient floor. The aurora is the light source for compositional purposes; no Cook-Torrance dispatch, no IBL ambient, no shadow casting.

### 5.10 Footprint reauthor (amended 2026-07-14 — AV.5, D-185)

**Why.** The AV.2/AV.3 implementation is the *right look* but the *wrong expression*. It collapsed the Lawlor footprint `F(x, y)` to **full-field** `triNoise2d` — bright *everywhere* — so the aurora fills the frame as a flat "veil in stacked colours." No footprint means no discrete curtains and no negative space, and no amount of undulation/drift tuning can turn a full-field wash into curtains (verified across AV.3 motion tweaks + a geometric-ribbon attempt that read as the `09` festival-spotlight anti-reference). Aurora Veil was paused for exactly this; Matt confirmed the reauthor 2026-07-14. Feasibility proven by the AV.4 spike (see `memory: project_aurora_veil_reauthor`).

**The fix — a real footprint.** Keep the factorization `emission = H(z) × F(x, y)`, but make `F(x)` a **footprint**: bright only along a few meandering curtain bands, dark between (negative space). Concretely (spike-validated): `footprint = smoothstep(≈-0.05, ≈0.22, fbm8(columnUVx·freq + curlAdv, …))` — `fbm8` is ~[-1, 1], so the threshold sits near zero for ~40–60 % coverage. The footprint **multiplies** the existing nimitz `H(z) × texture`, so the authentic ray texture (the look Matt liked) is *preserved* — the footprint only decides *where* the aurora hangs. This is the whole reauthor: the H(z) palette, the running-average smear, the ray texture all stay; `F` changes from full-field to footprint.

**Motion — the dance (Wittens).** The footprint is advected by `curl_noise` (vortical plasma flow, research §1.3), amplitude scaled by mid activity — so curtains curl, fold and drift with the music, gently at silence. This replaces the failed AV.3 sine-undulation (the internal noise warp averages out over the 50-step integration; the *footprint* has to move, not the internal sample). Multi-timescale: slow substrate drift + curtain fold over seconds + ray flicker. **NOT** free `sin(time)` (FA #33); **NOT** raw beats (Audio Data Hierarchy); **NOT** mv_warp (smears — `AuroraVeilMVWarpAccumulationTest`).

**Palette — dramatic multi-colour (Matt's choice 2026-07-14).** Green base → violet → magenta/pink crown by altitude (`H(z)`, indexed by march-step/world-y — never fold altitude into the noise, research §1.2). This resets the former anti-neon green-only contract: "still aurora, not festival" is now anchored on *structure* — biological ray striation, translucency, negative space, curl motion — **not** on desaturation. See §6.

**Musical-role sentence.** *When the music's harmonic body swells, the aurora curtains curl and sweep wider across the sky and brighten; when it thins, they settle to a slow drift — the curtains dance with the continuous energy envelope, while a rare drum accent sends a fold shuddering along a curtain and each half-bar downbeat flickers the stars.*

**Temporal contract (what changes over time).**
- *Continuous (mid activity)* → curl-advection amplitude/speed: curtains dance more vigorously when busy, drift when calm. Primary driver.
- *Bass transients* → whole-aurora brightness pulse (breathing).
- *Rare drum accents* → a curtain kink/fold shudder (rare-event gated, 1–2 s decay — not per-beat).
- *Vocals pitch* → palette band shift along altitude.
- *Half-bar downbeat (cached grid)* → staggered star blink (`f.bar_phase01`, `stemMix`-gated).
- *Silence* → gentle curl drift at base amplitude, non-black (D-037), no blink.

**Three-part concept bar (cleared).** (1) *Iconic subject at fidelity* — the AV.4 spike renders discrete curtains with negative space that read as aurora; feasibility demonstrated, not asserted. (2) *Clear musical role* — the sentence above (mid→dance, bass→brightness, drums→kink, vocals→hue, downbeat→stars). (3) *Infrastructure-feasible* — `curl_noise` + `fbm8` exist; one extra `fbm8` + one `curl_noise` per column, within the Tier-1 4.0 ms budget (perspective drape is the only part with a perf question — scope-gated in the AV.5 prompt DECISION).

### 5.11 Streak-field reauthor (amended 2026-07-14 — AV.6, D-186)

**Why (what AV.5 got wrong).** AV.5's §5.10 footprint model was built on a rendering core that never produced real fine filaments. The `aurora_tri_noise_2d` "volumetric march" was a bug'd port of nimitz: it sampled the noise at `(screen-x FIXED per fragment-column, altitude)` — a *vertical slice* through low-frequency noise — so it returned a smooth **wash**, not filaments. Every apparent "streak" in AV.5 was the **footprint band mask**, not the aurora texture. When AV.5 then replaced the hard footprint with a soft `fbm` field, the result read as **blobby fog** — "amorphous blobs with volume and shadow" (Matt, 2026-07-14, on the AV.5 real-audio GIF). The nimitz march works because it marches a view ray *at an angle* through a 3-D volume (`triNoise2d(bpos.zx)`), so the ray **crosses many filaments** as it rises; the AV.5 port collapsed that traversal (FA #73 — ported the shape, not the traversal).

**The target (Matt's real-time footage, 2026-07-14 — the motion reference).** Aurora is a **mass of fine, translucent, vertical streaks**: many thin rays hanging like a curtain, **brightest at the lower edge** (near white-green), fading up through blue to a magenta crown, **stars visible between and through them**, per-streak brightness variation. **Flat and emissive** — no bright-core-to-dark-edge gradient (that reads as 3-D volume/shadow, the AV.5 fog failure). The curtain occupies **part** of the frame against dominant dark sky. **Streaky is correct** — Matt confirmed he liked the streaky earlier iterations; the failure was that the streaks were never *real fine translucent filaments*.

**The fix — a real fine-streak field.** Generate genuine high-frequency vertical streaks — either the correctly-ported angled view-ray march, or (simpler, more controllable) a direct 2-D streak field: noise at `(x·HIGH_freq + curl/warp, y·LOW_freq + time)` so streaks are vertically coherent, many, and fine. Multiply by a soft **curtain envelope** (intense lower edge, soft top), a large-scale **concentration** field (negative space + curtain form), and the **altitude palette** (§5.10 green→violet→magenta, naturalistic); composite **translucent additive** so stars punch through. The AV.5 palette, audio routes + manifest, half-bar star blink, and perspective drape are **preserved**; only the aurora-generation core is rebuilt.

**Musical-role sentence.** *When the music's harmonic body swells, the streak curtain brightens and its shimmer quickens and the bright regions sweep faster along the curtain; when it thins, the streaks settle to a slow shimmer and gentle drift — the curtain dances with the continuous energy envelope, while a bass transient flares the whole curtain, a rare drum accent kinks a fold through it, and each half-bar downbeat blinks the stars.*

**Temporal contract (streak motion, multi-timescale — matching the footage's real-time motion).**
- *Sub-second* → streak **shimmer/flicker** (fine per-streak brightness modulation; fast, low-amplitude).
- *Continuous (mid activity)* → **sideways travel** of bright regions along the curtain + shimmer rate. Primary driver.
- *Tens of seconds* → the whole curtain **drifts/undulates and re-forms** (curl-advected substrate).
- *Bass transients* → whole-curtain brightness flare (breathing).
- *Rare drum accents* → a fold/kink shudders through the curtain (rare-event gated, 1–2 s decay).
- *Vocals pitch* → palette band shift along altitude.
- *Half-bar downbeat (cached grid)* → staggered star blink (`f.bar_phase01`, `stemMix`-gated).
- *Silence* → gentle shimmer + slow drift at base amplitude, non-black (D-037), no blink.

**Three-part concept bar.** (1) *Iconic subject at fidelity* — the **real-time footage is the fidelity target** (fine translucent streaks); the target is proven real, and the direct-streak-field / correctly-ported-march techniques are established graphics (nimitz §1.1, Theunissen abs-of-difference §1.4). Implementation feasibility is the **AV.6 first-streak-render go/no-go** (task 2), grounded in the footage — not a pre-spiked claim. (2) *Clear musical role* — the sentence above. (3) *Infrastructure-feasible* — `curl_noise` + `fbm`/tri-noise exist; a 2-D streak field is **cheaper** than the 50-step march, within the Tier-1 4.0 ms budget.

**Scope (Matt 2026-07-14): curtain of streaks only.** The horizontal **arc** and overhead radiating **corona** forms in the footage are out of scope for AV.6 (later increments if wanted); the corona's converging rays risk the festival-spotlight anti-reference (`09` / FM #14).

**Exposure calibration (AV.6, 2026-07-16 — the tone-map floor/scale).** The convergence march's raw density is genuinely tiny (linear `dlum` peak ≈ 0.025, avg ≈ 0.0035). The floor-subtract tone map (`kToneFloor`/`kToneScale`) turns that dim march into bright rays on black: floor just above the measured avg, scale ≈ `0.9/(peak − floor)`. Committed: floor `0.0044`, scale `43`. **Re-measure and re-derive both whenever `kDepDecay`, the accumulation-weight rate, the palette, or the gain change — they all move `dlum`.** **⚠️ Instrumentation gotcha (cost two sessions a "floor above peak → all black" spiral): the `AURORA_GIF` harness writes sRGB-encoded PNGs.** Reading `signalstats` `Y` as if it were linear overstates density ~3×, so a floor set from that reading lands above the real per-frame peak and blacks the frame. Invert first: `linear = (((Y−16)/219) + 0.055)/1.055)^2.4`. To read raw `dlum` directly, temporarily return `saturate(dlum * 10)` from the debug branch and divide the inverted reading by 10. Also: sharp high-contrast rays make any *spatial* audio motion (the drum kink) produce large whole-frame MSD, so the beat-kink is bounded to a screen-y band (D-157) and kept subtle while bass-brightness carries a wide swing — that is what satisfies the §5.7 ≥10× continuous-dominance ratio at this exposure.

**Palette range must match the marched range (AV.6 fix, 2026-07-16 — "the aurora is more than green", Matt).** The march traverses `h ∈ [kBaseShell·kShellDH, (kBaseShell+kAuroraSteps−1)·kShellDH] ≈ [0.018, 0.864]`, but the AV.5 palette put green→blue at `smoothstep(0.55, 0.98)` and blue→magenta at `smoothstep(0.98, 1.45)` — **above the marched ceiling, so the magenta crown was unreachable and the curtain read all-green.** Thresholds are now `0.42→0.70` (green→blue) and `0.70→0.86` (blue→magenta), i.e. the upper third of the *actual* range. Two coupled constraints: (1) each pixel sums its WHOLE column, so an early crossover desaturates the entire curtain — transitions must sit high to keep the green body dominant (L2 gate); (2) the upper shells are suppressed by `D(h)` and the accumulation weight, so `kDepDecay` (1.35 → 0.85) and the weight rate (0.055 → 0.035) were softened or the crown stays drowned.

**Known gap (next increment) — RESOLVED at §5.12.** Because every pixel integrates the full `h` range, colour did not correlate with SCREEN elevation. Fixed by the elevation-tilt in §5.12 (bias the palette index toward the crown for high-`rd.y` pixels), not by a palette threshold tweak — as this note predicted.

### 5.12 Band-through-march ray generator (amended 2026-07-17 — AV.6, D-186)

**The whole-AV.6 defect (why every footprint noise fogged).** Through the march, `uv = rd.xz·t` sweeps the footprint **radially**. Any footprint detail that is high-frequency in that radial direction de-coheres as the ray marches across it, and the running-average smear (`acc = mix(acc, d, 0.5)`) averages it to fog. This is why nimitz tri-noise, fbm, and every noise-as-footprint approach across AV.4–AV.6 read as a wash, never filaments. FA #73 one level deeper: the traversal, not the noise, was the problem.

**The fix — the ray field in the convergence frame.** `angle = atan2(uv.y, uv.x) = atan2(rd.z, rd.x)` is **independent of `t`** — constant along each view ray, and constant-angle lines fan from the vanishing point (the zenith, above the frame). So put the filament ridges in **angle** (many thin rays across the curtain) and keep them **coherent in radius** (they extrude down each ray instead of fogging). `aurora_rays(ang, rad, time)`: sharp triangle-wave ridges at `kStriationFreq` per radian, irregular spacing (two incommensurate sine warps → organic, not uniform beams), per-ray brightness + slow shimmer keyed on the ray index. Sharp-edged aurora, not a Gaussian spotlight (FM #14 / ref `09`).

**Structure (all in the convergence frame).**
- **Curtain = a soft angular SECTOR** about the convergence (`exp(-((ang−centerAng)/kBandHalfWidth)²)`), giving dark sky to the sides = real negative space (`darkFraction` gate 0.13→0.43). The sector center sways slowly over radius + time (the arc's dance).
- **Vertical base-bright fade** is `D(h)` (height-deposition), NOT the sector — fixes the inverted brightness the uv.y-strip band produced.
- **Crown fade** (`smoothstep(0, kCrownFadeR, rad)`) dims toward the convergence: kills the `atan2` singularity's alias blob and matches the reference's faint crown.

**Colour — elevation tilt (the §5.11 known-gap fix).** Each pixel integrates its whole column, so per-step altitude colour alone washes out. Bias the palette index toward the crown for high-elevation pixels (`elevTilt = smoothstep(0.40, 0.85, rd.y) · kElevTilt`), so colour tracks SCREEN height: green base low → violet crown high (satisfies the green-base/magenta-crown stratification gate). Palette `H(z)`: saturated green base (authored from `ref_240`'s measured emission ≈ 19,130,61) → cool-teal mid → violet/magenta crown (design §5.10, refs 01/07).

**⚠ Palette-source nuance (open for Matt).** `ref_240` itself measures **green→cyan**, with *no* violet/magenta crown (its upper sky samples pure black). The violet crown is the *design intent* (refs 01/07 + the stratification gate), not present in that one frame. The shipped palette honours the intent (green→violet). If Matt prefers strict `ref_240` fidelity (green→cyan), swap the `crown` constant toward cyan and relax the stratification gate — a colour call, flagged at M7.

**Exposure (bgra8Unorm_srgb target).** The fragment outputs **linear**; the render target sRGB-encodes on write, so a linear channel of 0.94 → ~248/255 but 0.97 → ~251 (trips `PresetAcceptance` "max channel < 250"). Composite clamp is `min(…, 0.94)`; `kAuroraGain = 1.35`; the core bleach is gentle and green-leaning. The floor-subtract tone map is off (identity) — the sector + crown fade carry the negative space, so it is no longer load-bearing.

**Final constants (2026-07-17):** `kStriationFreq 11.0`, `kRayWidth 0.13`, `kCrownFadeR 0.40`, `kBandCenterAngle 1.62`, `kBandHalfWidth 0.42→0.30` (narrowed for negative space), `kElevTilt 0.55`, `kCrownCurve 1.6`, `kCrownH 0.286`, `kAuroraGain 1.35`, `kLookPitch 0.52` (already an overhead curtain; Q1 met without re-tilting). The nimitz tri-noise chain (`aurora_tri`/`tri2`/`mm2`/`tri_noise_2d`, `kSubstrateSpd`) is **retired**.

## 6. Anti-references and failure modes

- **Full-field wash (the shipped AV.2/AV.3 look).** `F(x,y)` bright everywhere → a frame-filling veil with no discrete curtains and no negative space. THE reason for the AV.5 reauthor. The footprint must carve negative space.
- **Blobby fog / "volume and shadow" (the AV.5 soft-veil dead-end).** A soft `fbm` concentration field with smooth bright-core-to-dark-edge falloff reads as 3-D shaded smoke, not aurora (FM #8 pillow-fog). Aurora is FLAT emissive fine filaments — no shading gradient. Fixed by the AV.6 streak-field (§5.11).
- **Smooth wash from a collapsed march (the AV.5 core bug).** Sampling the noise at `(fixed-x, altitude)` traces a vertical slice → a smooth gradient with no fine streaks. Real filaments require an angled traversal that crosses many streaks, or a direct high-frequency streak field (§5.11).
- **Solid opaque streaks.** Hard-masked, high-opacity streaks read as a painted "cartoon fill" (Matt's first AV.5 critique). Streaks must be translucent — stars and sky visible between and through them.
- **Geometric spotlight beams.** Clean Gaussian vertical bands (the failed AV.4-early attempt) read as the festival-spotlight anti-reference `09` — stage lights, not aurora. Curtains must carry the organic ray texture, not clean falloffs.
- **"Festival visual."** Beat-flashing aurora that pulses to every kick. Beat is accent-only (rare-event drum kink + half-bar star blink); mid-driven curl motion is the continuous primary. NOTE (AV.5): saturated multi-colour is now the *desired* palette — "not festival" is judged on structure/motion, not saturation.
- **"Free-running sin oscillation."** Never `sin(time)` for primary motion (FA #33). Motion is curl-advected substrate, audio-scaled.
- **Altitude in the noise call.** `fbm(float3(x,y,z))` → monotonic top-to-bottom gradient, not stratified bands (research §1.2). Altitude lives only in the palette.
- **"Procedural night sky."** A noise-based sky pattern is wrong — real aurora night sky is mostly black with sparse stars.
- **mv_warp.** Smears this preset to mush (AV.2.2). Do not re-add.

## 7. Performance budget

- **Tier 1 (M1/M2):** Fragment ~3.5 ms (3 ribbons × warped_fbm × vertical-ray fbm4 × palette evaluations) + mv_warp grid ~0.4 ms = ~4.0 ms total.
- **Tier 2 (M3+):** ~1.7 ms total.

`complexity_cost: {"tier1": 4.0, "tier2": 1.7}`. Well within both tier budgets.

## 8. Acceptance criteria

**Rubric profile: lightweight** (D-067(b)) — emission-only direct-fragment plasma-family preset, exempt from M1 detail cascade and M3 material count requirements.

- **L1 (silence):** Curtains drift, ribbons remain at base brightness, mv_warp accumulates rotation. Form complexity ≥ 2 at silence (multi-ribbon + stars + sky).
- **L2 (deviation primitives):** All audio routing uses `*_rel` / `*_dev` per D-026. Verified by `FidelityRubricTests`.
- **L3 (perf):** p95 ≤ tier budget. Verified by `PresetPerformanceTests`.
- **L4 (frame match):** Matt M7 review against curated references.

**Preset-specific tests:**

1. `AuroraVeilSilenceTest` — render at zero audio, assert non-black, assert ≥3 distinct ribbons by horizontal slice luma analysis.
2. `AuroraVeilPitchHueTest` — render with `vocalsPitchNorm` swept low→high; assert ribbon hue shifts continuously (not stepwise).
3. `AuroraVeilContinuousDominanceTest` — render with zero `drums_energy_dev` and rising `bass_att_rel`; assert frame max-luma scales with `bass_att_rel` by ≥ 0.2 amplitude. Validates continuous primary driver actually dominates.

## 9. Implementation phases

**Session 1 — Single-ribbon foundation.** Sky + stars + one ribbon with center-line `warped_fbm` + vertical rays + IQ cosine palette stratification. mv_warp wired with conservative parameters. Silence test passes.

**Session 2 — Multi-ribbon with parallax + audio.** Add ribbons 2 and 3 with depth scaling. Wire all audio routes per §5.6. Continuous-dominance test passes.

**Session 3 — Refine + cert.** Tune palette constants, mv_warp amplitudes, fold density coefficients against curated reference frames. Pitch-hue test passes. Performance profile run. Matt M7 review.

**Estimated: 3 sessions.**

## 10. JSON sidecar template

```json
{
  "id": "aurora_veil",
  "family": "fluid",
  "passes": ["mv_warp"],
  "tags": ["aurora", "ambient", "ribbon", "atmospheric"],
  "feedback": {
    "decay": 0.945,
    "base_zoom": 0.0015,
    "base_rot": 0.0008,
    "beat_zoom": 0.0,
    "beat_rot": 0.0,
    "beat_sensitivity": 0.0
  },
  "stem_affinity": {
    "vocals": "ribbon_hue",
    "drums": "curtain_kink",
    "bass": "brightness_breath",
    "other": null
  },
  "visual_density": 0.4,
  "motion_intensity": 0.25,
  "color_temperature_range": [0.15, 0.55],
  "fatigue_risk": "low",
  "transition_affordances": ["crossfade", "morph"],
  "section_suitability": ["ambient", "comedown", "bridge"],
  "complexity_cost": { "tier1": 4.0, "tier2": 1.7 },
  "certified": false,
  "rubric_profile": "lightweight",
  "rubric_hints": {}
}
```

## 11. Open questions

1. **Family enum value.** Confirm `fluid` is the intended family — alternative is to coin `atmospheric` if a category for aurora/sky/cloud presets is appropriate longer-term. (Affects family-repeat scoring.)
2. **~~Per-frame palette modulation rate~~** *(resolved by 2026-05-18 amendment)*. Vocals pitch now sourced from `stems.vocals_pitch_hz` + 5-frame moving average per §5.7; not from `SpectralHistoryBuffer[1920..]` (which was bar phase, not pitch).
3. **Star count.** 800-density (`hash > 0.997`) is the proposed start. May increase if ribbons feel isolated against sky.
4. *(new, 2026-05-18)* **`tri_noise_2d` performance budget.** The clean-room MSL reimplementation needs profiling against the Tier-1 4.0 ms / Tier-2 1.7 ms budget per §7. If 50-step march × 5-octave triangular noise overshoots, fallback options in priority order: drop march to 40 steps; reduce noise octaves 5 → 4; final fallback to Roy Theunissen's "difference of two Perlins, take abs()" baseline (lower fidelity ceiling, cited in research dossier §1.4).

---

## 5-LEGACY (original §5, archived 2026-05-18)

Preserved for iteration history. The 2026-05-18 amendment pivoted §5 to the volumetric-raymarch recipe per `AURORA_VEIL_RESEARCH_2026-05-18.md`. The pre-amendment §5 specified a 2D pixel-shader ribbon with horizontal proximity test against a `warped_fbm` centre-line — structurally distinct from every photographically-credible procedural aurora in the wild, and exposed to Failure Modes #3 (horizontal wave bands, no vertical extent), #9 (symmetric centered composition), #13 (hard-edged top AND bottom), plus missing multi-timescale motion mechanisms entirely. The legacy spec is NOT the implementation target; it's preserved here so the rationale for the amendment is visible in one place.

### Legacy §5.1 — Pass structure (unchanged in amendment)

`passes: ["mv_warp"]`. The fragment shader (`aurora_fragment`) is invoked by the mv_warp scene draw; output goes to `warpState.sceneTexture`; the warp pass then performs its 32×24 vertex grid per-pixel feedback and presents to drawable.

### Legacy §5.2 — Scene composition (SUPERSEDED — see new §5.2 above)

Fragment shader built the frame in three layers, back to front:

**1. Sky.** Vertical gradient: top `(0.005, 0.005, 0.02)` (deep night), bottom `(0.01, 0.015, 0.04)` (slightly warmer near horizon). Stars: sparse pinpoints from `hash_f01_2(uv * 800)` thresholded > 0.997, brightness modulated by another hash for variety. *(Retained verbatim in amendment.)*

**2. Curtain layer (3 ribbons).** Each ribbon `i ∈ {0, 1, 2}` has center-line:

```metal
float xc(float y, int i) {
    return 0.5 + 0.15 * (i - 1)
         + 0.08 * warped_fbm(float3(y * 1.5 + i * 7.0, time * 0.04, 0.0));
}
```

Ribbon width feathered at top and bottom, varying along y:

```metal
float width(float y, int i) {
    return baseWidth
         * smoothstep(0.0, 0.15, y)
         * smoothstep(1.0, 0.85, y)
         * (0.7 + 0.3 * fbm4(float2(y * 4.0 + i * 3.0, time * 0.06)));
}
```

Ribbon brightness: `1 - smoothstep(0, width(y), abs(uv.x - xc(y, i)))`, multiplied by vertical-ray detail + fold modulation + depth-scale. *(SUPERSEDED — see new §5.2 volumetric raymarch.)*

**3. Hue stratification.** Sample IQ cosine palette with `t = uv.y + pitchHue` where `pitchHue` was incorrectly sourced from `SpectralHistoryBuffer[1920..]` (that offset is bar phase, not vocal pitch — discovered during 2026-05-18 desk research). *(SUPERSEDED — palette now indexed by march-step / world-y per Lawlor-Genetti factorization, hue sourced from `stems.vocals_pitch_hz`.)*

### Legacy §5.3 — mv_warp specifics (retained substantially unchanged)

Per-frame: `baseRot = 0.0008 + valence * 0.0004`, `baseZoom = 0.0015`, `decay = 0.945`. Per-vertex: UV displacement `curl_noise(...).xy * 0.005` plus drum-coupled y-displacement. *(See new §5.3 for the amended `kinkAccumulator` rare-event-gated form.)*

### Legacy §5.6 — Audio routing table (SUPERSEDED — see new §5.7)

The legacy table routed `vocalsPitchNorm` from a non-existent buffer offset (resolved: stems direct) and routed `drums_energy_dev` directly to mv_warp displacement (resolved: rare-event-gated `kinkAccumulator` with damped response — without this, the preset becomes EDM festival per Failure Mode #11).

### Legacy §5.7 — Silence fallback (substantively unchanged, see new §5.8)

At silence, ribbons remained at base brightness, folds static, mv_warp continued slow rotation. Curtains drifted via `warped_fbm` centre-line motion. Stars twinkled faintly via blue_noise temporal index.
