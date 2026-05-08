# Arachne v8 — Design Spec

**Status:** Three-pillar deep rewrite, 2026-05-03. Replaces the 2026-05-02 layer-structured draft. Several subsystems described here have already shipped (V.7.6.1 harness, V.7.6.2 orchestrator multi-segment, V.7.6.C framework calibration, V.7.6.D diagnostic semantics) and are preserved verbatim as reference; their behavior is unchanged. Implementation increments V.7.7 → V.7.9 are listed in `ENGINEERING_PLAN.md`; this spec is the source of design truth they cite.

**Material-priority decision, 2026-05-05:** For Arachne v8, droplets are the primary fidelity carrier. Silk is secondary. Keep axial silk highlights as a minor lighting effect, but do not implement full Marschner-lite as the first material priority. Prioritize refractive droplet material, sag, irregular geometry, and world interaction.

**Why this rewrite:** The 2026-05-02 draft was structured as three render layers (background / foreground / overlay), which led to the WORLD pillar being underspecified — one paragraph in §4.1 plus the §4.3 color recipe. The 2026-05-02 design conversation reframed Arachne as three pillars at *equal* fidelity: a forest in which a single web is being drawn, in which a spider rarely appears. WORLD is not "background"; it is the stage. SPIDER is not a "dark silhouette"; it is a detailed biological organism that earns its rare appearances. This rewrite specifies all three pillars at the depth required to implement them.

**Reference set.** Refs 01–10 (curated original) plus refs 11–19 (extension set landed 2026-05-03) in `docs/VISUAL_REFERENCES/arachne/`. One previously-listed reference (anchor-to-bark macro) was dropped 2026-05-03 — real orb-weaver webs predominantly anchor to twigs, leaf petioles, and grass stems, not to bark trunks; ref 11 covers the polygon-of-anchors context without it. Two time-lapse stills (radials laid no spiral, capture spiral mid-construction) are reclassified P1 — the construction sequence is grounded in the biology citations (§13) and is implementable without photographic refs.

---

## 1. Status and history

Five Arachne attempts (3.5.5 mesh, 3.5.10 3D ray-march, 3.5.12 2D SDF rebuild, V.7 v4, V.7.5 v5) have failed to reach the visual bar. Decision D-072 diagnosed the V.7.5 failure as architectural (missing compositing layers, not bad constants); the empirical M7 review showed a near-pixel match for `10_anti_neon_stylized_glow.jpg`, the explicit anti-reference. The 2026-05-02 design conversation (recorded in this document's predecessor) committed to a three-pillar reframing.

**Subsystems already shipped:**
- **V.7.6.1 — visual feedback harness** (2026-05-02). Renders any preset against silence/steady/beat-heavy fixtures into PNG contact sheets in `/tmp/phosphene_visual/<ISO8601>/`. Gated behind `RENDER_VISUAL=1`. Used to diagnose that V.7.5's output reads as flat 2D ring spirals.
- **V.7.6.2 — orchestrator multi-segment + completion-signal + maxDuration framework** (2026-05-02 → 2026-05-03). `PlannedTrack.segments: [PlannedPresetSegment]`, `PresetSignaling` protocol, `LiveAdapter` segment-aware, `PresetDescriptor.maxDuration(forSection:)` computed property.
- **V.7.6.C — framework calibration pass** (2026-05-03). Per-section linger factors set per Option B (ambient=0.80, peak=0.75, comedown=0.65, buildup=0.40, bridge=0.35); diagnostic class `is_diagnostic` flag added with default false; Spectral Cartograph flagged true.
- **V.7.6.D — diagnostic preset orchestrator semantics** (2026-05-03). Diagnostic presets categorically excluded from `DefaultPresetScorer`, `DefaultLiveAdapter`, `SessionPlanner`, `DefaultReactiveOrchestrator`; reachable only via manual switch.

**Outstanding implementation:** V.7.7 (WORLD pillar + 1–2 background dewy webs), V.7.8 (foreground build refactor with corrected biology), V.7.9 (spider deepening + whole-scene vibration + cert review).

### 1.1 Visual target reframe (canonical, 2026-05-08, D-096)

> The references define the aesthetic family — backlit macro nature photography, dewy webs, atmospheric forest, biological asymmetry, droplets as primary visual carrier. They are NOT pixel-match targets. The bar is: a frame from Arachne3D should look like it belongs in the same visual conversation as ref 01, not look identical to ref 01. A viewer seeing both side by side should classify them as 'same world, different rendering' — not 'photograph next to clipart.' Real-time constraints (Tier 1 14ms / Tier 2 16ms p95) are inviolable. If a fidelity feature cannot be achieved in budget, document the gap and pick the nearest achievable approximation.

This reframe replaces any prior implicit "match the photographs" contract that earlier drafts of this document carried. It is **preset-system-wide**, not Arachne-specific — V.9 FerrofluidOcean, V.10 FractalTree, V.11 VolumetricLithograph, and V.12 GlassBrutalist + KineticSculpture all inherit the same principle. Everywhere this document refers to "the visual target," "matching the references," "documentary close-up of nature," "BBC Earth time-lapse footage," "photorealistic" or similar phrasing, read it through this reframe — the language describes the aesthetic family the rendering must join, not a per-pixel target it must hit. The anti-references (`09_anti_clipart_symmetry.jpg`, `10_anti_neon_stylized_glow.jpg`) define the failure modes that disqualify a frame from the visual conversation; staying out of those failure modes is the cert bar, not pixel-equivalence with a particular reference.

The cert rubric (`SHADER_CRAFT.md §12.1`) still requires Matt's eyeball on a contact sheet at M7. The reframe shifts what M7 *means* — "does this frame belong in the same visual conversation as the references?" not "does this frame match the photograph?".

---

## 2. Goal

A naturalistic time-lapse of a single spider web being drawn in a quietly-lit forest, with photographic dewy webs already present in the depth of the scene, and with a spider that appears in response to sustained bass and shakes the world during heavy bass.

The visual target is the *aesthetic family* of the BBC Earth orb-weaver time-lapse footage (§13): a documentary close-up of nature, not a stylized graphic — read through the §1.1 reframe (rendering joins the aesthetic family, does not pixel-match it). Two anti-references — `09_anti_clipart_symmetry.jpg` and `10_anti_neon_stylized_glow.jpg` — are the failure modes the rubric rejects, and which V.7.5's V.5 build matched.

---

## 3. Three pillars — overview

| Pillar | What it is | When it's present | Reference anchor |
|---|---|---|---|
| **WORLD** | The forest. Layered fixed stage: sky, distant trees, mid-distance trees with bark, near-frame anchor branches, forest floor, atmospheric volume (fog + light shafts + dust motes). Mood-driven palette. | Always, from frame zero. | Refs 06 / 15 / 16 / 17 / 18 / 07 |
| **WEB** | One foreground web actively under construction over a 60s cycle (frame → radials → inward capture spiral → settle), plus 1–2 already-finished dewy webs in the depth of the scene. Drops carry 80% of the visual weight; threads are connective tissue. Outer radials anchor to the WORLD's near-frame branches. | Always, from frame zero (background webs); foreground build runs continuously. | Refs 01 / 02 / 03 / 04 / 11 |
| **SPIDER** | Rare easter egg. Triggered by sustained sub-bass with low attack ratio. Detailed biological organism (cephalothorax + abdomen, 8 articulated legs with knee bend, eye cluster, abdominal pattern, iridescent chitin material, alternating-tetrapod gait, listening pose). | At most once per Arachne segment. ~1 in 5–10 segments in practice. | Refs 12 / 13 / 14 / 19 |

The three pillars compose into a single rendered frame. They are NOT three separate render targets the user toggles. The pillar separation is for design and authoring depth, not runtime structure. Each pillar must be implementable, reviewable, and certifiable on its own merits.

**Vibration is independent of the SPIDER pillar.** Whole-scene tremor on bass fires whenever heavy bass is present, with or without the spider visible. See §8.2.


## 3A. Core rendering architecture

Arachne v8 must be implemented as a staged renderer, not as a monolithic web-drawing shader.

The purpose of this architecture is to prevent the known failure mode where Arachne renders as graphic web geometry — rings, shields, dart boards, neon strokes, or clipart — instead of a material-rendered nature scene. The visual target is a fixed forest world in which a physical dewy orb-weaver web exists, with droplets, atmosphere, light, and rare spider behavior all composed into one scene.

### Required pass structure

#### Pass 1 — WORLD

Render the forest stage before any web or spider elements.

Includes:
- sky band;
- distant tree silhouettes;
- mid-distance trunks with bark detail;
- near-frame branches / twigs used as web anchors;
- forest floor;
- fog volume;
- light shafts;
- dust motes.

Output:
- `arachneWorldTex`, or the closest engine-supported equivalent.

Acceptance gate:
- With WEB and SPIDER disabled, WORLD-only output must read as a misty forest stage with depth, atmosphere, and physical anchor geometry. It must not read as a flat color field or abstract backdrop.

#### Pass 2 — BACKGROUND WEBS

Render 1–2 already-finished dewy webs at depth.

Includes:
- irregular web geometry;
- saturated droplets from frame zero;
- upper-range sag;
- mild blur / depth treatment;
- low visual priority relative to the foreground web.

Acceptance gate:
- Background webs must read as existing dewy webs in the scene, not as duplicate foreground meshes or flat decorative overlays.

#### Pass 3 — FOREGROUND WEB GEOMETRY

Render the active foreground web under construction.

Includes:
- irregular branch-anchored polygon frame;
- hub knot, not concentric rings;
- 12–17 jittered radials;
- inward chord-segment capture spiral;
- parabolic sag;
- build lifecycle.

Acceptance gate:
- The web must not contain perfect circular rings, target hubs, shield shapes, sand-dollar geometry, or regular clipart symmetry.

#### Pass 4 — DROPLET MATERIAL

Render adhesive droplets as the primary fidelity carrier.

Includes:
- droplets only on capture spiral chords;
- near-uniform biological spacing with low jitter;
- spherical-cap normals;
- screen-space refraction using `arachneWorldTex`;
- Fresnel rim;
- dark edge ring;
- pinpoint specular highlight;
- time-based accretion after each chord is laid.

Acceptance gate:
- Droplets must visibly refract / invert the world behind them. If droplets read as flat dots, pearls, neon beads, or simple glow sprites, this pass fails.

#### Pass 5 — ATMOSPHERIC / LIGHTING COMPOSITE

Composite the scene lighting and atmosphere.

Includes:
- backlit silk interaction;
- local fog depth;
- light shafts;
- dust motes;
- depth/focus treatment;
- mood-driven palette integration.

Acceptance gate:
- The final scene must read as web-in-air, not web-on-background. Atmosphere must create depth without overpowering the web.

#### Pass 6 — SPIDER EASTER EGG

Render the spider only when triggered.

Includes:
- rare trigger behavior;
- biological orb-weaver anatomy;
- articulated legs;
- chitin material;
- dorsal pattern;
- eye specular;
- listening pose;
- bass-driven whole-scene vibration.

Acceptance gate:
- The spider must be rare and high-fidelity when present. It must not become the main subject of every Arachne segment.

### Architectural non-negotiables

- Arachne is not a spiderweb drawing. It is a staged, material-rendered nature scene.
- Droplets are the primary fidelity carrier. Silk is secondary.
- Full Marschner-lite silk is not the first material priority.
- The WORLD pass must exist before refractive droplets can be certified.
- The foreground web must be anchored to the WORLD's near-frame branches or twigs.
- Audio may modulate material, light, atmosphere, vibration, and build pace, but must not randomly deform the web topology.
- Major motion must be audio-anchored or beat-phase anchored, not free-running `sin(time)`.
- Every major pass must support debug / harness capture.

---

## 4. THE ATMOSPHERE

> **V.7.7C.5 reframe (2026-05-09).** Section 4 was rewritten end-to-end from a six-layer dark close-up forest scene to a pure atmospheric-abstraction backdrop after Matt's 2026-05-08T18-28-16Z manual smoke flagged the V.7.7B–C.4 forest framing as "completely devoid of value" and "the lines do not read as branches" (full Q&A captured below the section). The forest layers (distant trees / mid-distance trees / near-frame branches / forest floor) are retired; what remains is sky band + volumetric atmosphere (fog + light shafts + dust motes). The §5.9 anchor-twig SDFs added in V.7.7C.2 Commit 1 are also retired (Q12) — polygon vertices alone provide the WEB attachment points; no literal "branch" or "twig" rendering anywhere in WORLD.
>
> The mood-driven color field (§4.3) is preserved verbatim from the 2026-05-02 spec — Matt elected to keep it locked (Q10). Reference cross-walk re-interprets existing references as mood-palette anchors only (Q13); the forest-specific references (02, 11, 17, 18) are retired for V.7.7C.5 implementation purposes but stay in `docs/VISUAL_REFERENCES/arachne/` for V.7.10 cert-review historical comparison.

### 4.1 Conceptual frame

The atmosphere is a fixed stage. The viewer's vantage is fixed (no camera dolly). What varies is mood-driven color, atmospheric volume density, and audio-driven vibration. The atmosphere does NOT depict a literal scene — no trees, no forest floor, no horizon, no branches. It is purely volumetric: fog, light, motion of air, and the mood-driven palette colouring all of it. The web reads as floating *in* this atmosphere; the spider walks across the polygon perimeter when triggered. The sense that the world is *solid and persistent* comes from the consistent mood palette and the fixed vantage; literal scenic detail (the V.7.7B–C.4 forest) was retired because it competed with the foreground build rather than supporting it.

References 06 (`06_atmosphere_dark_misty_forest.jpg`), 16 (`16_atmosphere_dappled_pine_forest.jpg`), and 15 (`15_atmosphere_aurora_forest.jpg`) remain as **mood-palette anchors only** — the §4.3 mood field interpolates among their colour signatures, but the forest scenes those references depict are NOT the implementation target. The implementation target is the pure-atmospheric volumetric backdrop the references' colour palettes are extracted from.

### 4.2 Layer stack

The atmosphere is composed of two layers, rendered back-to-front into a half-resolution texture `arachneWorldTex` before WEB and SPIDER passes composite over it. Reduced from six layers in the V.7.7B–C.4 spec (Q3, Q4, Q5, Q6).

**4.2.1 Atmospheric color band (full frame).** Vertical gradient `mix(botCol, topCol, uv.y)` over the **full** frame (Q2 — expanded from the V.7.7B–C.4 spec's "upper ~40%" since the forest floor is retired and the gradient now needs to fill the lower edge too). Slight noise modulation via low-frequency `fbm4` to break perfectly-smooth gradient. At very high arousal (`smoothedArousal > 0.6`), aurora-like horizontal ribbon structure fades in — phase-anchored to `f.beat_phase01` so ribbon motion is musically coupled (Failed Approach #33 compliance). Suppressed at silence (pure-black calibration anchor per ref 08, Q11 keeps the established convention).

**4.2.2 Volumetric atmosphere.** Three sub-elements composited additively. The atmospheric layer carries the entire visual weight that the V.7.7B–C.4 forest layers were meant to bear; brightness coefficients are raised significantly across the board so atmosphere reads as a hero element rather than a faint overlay.

- **Fog density (Q7 — volumetric god-ray anchored).** Fog density is anchored *around* the light shafts (denser inside the shaft cones, thinner outside the cones). This produces the "visible particulate medium catching the light" reading — what cinematographers call volumetric god-ray fog. Modulated by `f.mid_att_rel` (continuous breath); range raised from V.7.7B's 0.02–0.06 to **0.15–0.30** for substantial fog presence (Q7's "raise fog amplitude significantly" combined with the beam-anchored density profile). Color inside the cones: `mix(botCol, topCol, 0.5) × kLightCol` (warm tint at the beam centroid). Outside the cones, fog falls to a much thinner ambient haze at `mix(botCol, topCol, 0.5) × 0.3`. Heavier overall fog at low valence (cooler, mistier); lighter at high valence (clearer dawn).

- **Light shafts (Q8 — 1–2 mood-driven, raised brightness).** When `f.mid_att_rel > 0.05` (lowered from V.7.7B's 0.10 so shafts engage on lighter music), 1–2 god-ray cones descend from the upper edges of the frame. **Mood-driven angle**:
   - Warm valence (`v > 0`) → primary cone enters from the upper-LEFT at ~30° from vertical. Optional secondary cone from upper-LEFT at ~50° (engages at high arousal).
   - Cool valence (`v < 0`) → primary cone enters from the upper-RIGHT at ~30° from vertical. Optional secondary cone from upper-RIGHT at ~50° (engages at high arousal).
   - Neutral valence: defaults to the warm-side angles.
  
  Implementation: radial-blur in UV space along each shaft axis, sampled from a hash-jittered 1D noise (the `Volume/LightShafts.metal` `ls_radial_step_uv` family is the V.1 utility — discrete shafts, not uniform glow). Shaft color: `beamCol` from §4.3 (warm at high valence, cool at low). **Brightness coefficient raised from V.7.7B's `0.06 × val` to `0.30 × val`** — the V.7.7B coefficient produced barely-visible shafts per Matt's 2026-05-08T18-28-16Z manual smoke; V.7.7C.5 makes shafts the dominant atmospheric light source.

- **Dust motes (Q9 — caustic-concentrated inside light shafts).** Hash-lattice particle field, **concentrated inside the light shaft cones only** (not uniform across the volume as in V.7.7B). This is the "dust visible in sunlight" cinematographic signature — the motes outside the shafts are invisible because there's no key light to catch them. Per-mote opacity ~0.4 (raised from 0.3 since they only exist inside shafts now); color matched to local fog × `kLightCol` so motes glow within the shaft. Density modulated by `f.mid_att_rel`. Phase-anchored to `f.beat_phase01` (motes drift on beat phase, no free-running `time` motion — Failed Approach #33 compliance).

### 4.3 Mood-driven color field

Locked 2026-05-02 per Matt direction (Option B, full specification). Shipped through V.7.6.C calibration. **This subsection is preserved verbatim from the 2026-05-02 spec; the recipe is correct as authored.**

Single source of truth: the smoothed mood signal (`f.valence`, `f.arousal` from MoodClassifier) drives the entire scene palette. Smoothed over a 5-second low-pass window so palette transitions are gradual (no jarring mid-section shifts). Standard psychophysics mapping: **valence → warm/cool hue, arousal → saturation + brightness**.

```hlsl
// Inputs: smoothed mood signal (5s low-pass on f.valence and f.arousal)
float v = smoothedValence;  // -1..1
float a = smoothedArousal;  // -1..1

// Hue: cool (cyan/blue 0.55–0.65) at low valence, warm (orange/amber 0.05–0.10) at high valence
float topHue = mix(0.62, 0.05, saturate(0.5 + 0.5 * v));   // sky-ish: cool when sad, warm at dawn
float botHue = mix(0.58, 0.08, saturate(0.5 + 0.5 * v));   // ground-ish: cool mist or warm earth

// Saturation/brightness scale with arousal. Low arousal = desaturated, dim. High = saturated, brighter.
float satScale = 0.25 + 0.40 * saturate(0.5 + 0.5 * a);   // 0.25 calm → 0.65 energetic
float valScale = 0.10 + 0.20 * saturate(0.5 + 0.5 * a);   // 0.10 dim → 0.30 brighter

float3 topCol = hsv2rgb(float3(topHue, satScale, valScale * 1.2));
float3 botCol = hsv2rgb(float3(botHue, satScale * 0.85, valScale));

// Volumetric beam (when f.mid_att_rel > 0.05): warm at v>0, cool at v<0
float3 beamCol = hsv2rgb(float3(mix(0.6, 0.08, saturate(0.5 + 0.5 * v)), 0.5, 0.4));
```

**Per-layer color application within the WORLD pass:**

| Layer | Color recipe | Notes |
|---|---|---|
| Sky band (4.2.1) | `mix(botCol, topCol, uv.y)` | Primary visual carrier of palette |
| Distant tree silhouettes (4.2.2) | `botCol * 0.18` | Dark silhouette tone |
| Mid-distance trees (4.2.3) | `mix(botCol, topCol, 0.35) * 0.55` | Readable bark detail at mid darkness |
| Near-frame branches (4.2.4) | `mix(botCol, topCol, 0.35) * 0.65` | Slightly brighter than mid-distance (closer to viewer) |
| Forest floor (4.2.5) | `botCol * 0.4` | Floor matches ground-ish hue, dimmed |
| Fog (4.2.6) | `mix(botCol, topCol, 0.5)` | Mid-tone, thicker mid-frame |
| Light shafts (4.2.6) | `beamCol`, additive | Warm at high valence, cool at low |
| Dust motes (4.2.6) | local fog color | Inherits |

**Coverage of the reference set.** Mood quadrants map to references:
- `(v>0, a>0)` high valence high arousal → ref `04` warm gold backlit, ref `05` golden field, ref `16` dappled pine.
- `(v>0, a<0)` high valence low arousal → muted warm dawn (between refs `04` and `05`).
- `(v<0, a>0)` low valence high arousal → dramatic cool with rim accents (variant of ref `01`); ref `15` aurora at extreme arousal.
- `(v<0, a<0)` low valence low arousal → ref `06` cool blue-grey misty, ref `08` dark with bioluminescent accents.

**Smoothing implementation.** Per-preset state struct holds `smoothedValence` and `smoothedArousal` fields (don't pollute `FeatureVector` — this is preset-specific). Each frame: `smoothedX = lerp(smoothedX, currentX, dt / 5.0)`. The 5-second window is initial; tune up to 8s if mood shifts feel jumpy in practice, down to 3s if palette feels sluggish.

**Pure black at silence is preserved** as the calibration anchor (per `08_palette_bioluminescent_organism.jpg`): if `(satScale × valScale) < 0.05` (silence-state mood signal), the WORLD pass clears to black; gradient + foliage suppressed. WEB drops + threads still render against black; the palette fades back in as audio resumes.

### 4.4 Reference cross-walk

V.7.7C.5 reframe (Q13). References are **mood-palette anchors only** — the references' colour signatures drive the §4.3 palette, but the literal compositional content of the references (forests, branches, etc.) is NOT the implementation target. The atmospheric-abstraction backdrop renders the colour palette and atmospheric depth derived from these references without depicting the references' subject matter.

| Layer / element | Primary reference | Secondary references |
|---|---|---|
| Mood-cool default (palette only) | `06_atmosphere_dark_misty_forest.jpg` | — |
| Mood-warm default (palette only) | `16_atmosphere_dappled_pine_forest.jpg` | `05_lighting_backlit_atmosphere.jpg` |
| Mood-high-arousal psychedelic (palette only) | `15_atmosphere_aurora_forest.jpg` | — |
| Light shafts | `07_atmosphere_dust_light_shaft.jpg` | — |
| Dust motes (caustic in shaft) | `07_atmosphere_dust_light_shaft.jpg` | — |
| Pure-black silence anchor | `08_palette_bioluminescent_organism.jpg` | — |
| Anti-reference (clipart) | `09_anti_clipart_symmetry.jpg` | — |
| Anti-reference (neon) | `10_anti_neon_stylized_glow.jpg` | — |

**Retired references (V.7.7C.5)**: the following references no longer drive any §4 implementation choice. They remain in `docs/VISUAL_REFERENCES/arachne/` for V.7.10 cert-review historical comparison and for retrospective comparison against the V.7.7B–C.4 forest spec.

| Reference | Was anchoring | Why retired |
|---|---|---|
| `02_meso_per_strand_sag.jpg` | Mood-cool secondary | Mood-cool palette now anchored on 06 only; 02's web composition is not a §4 element |
| `11_anchor_web_in_branch_frame.jpg` | Near-frame branches (§4.2.4) | Branches retired per Q5(a) |
| `17_floor_moss_leaf_litter.jpg` | Forest floor (§4.2.5) | Floor retired per Q6(a); sky band fills the lower edge |
| `18_bark_close_up.jpg` | Bark texture on branches | Bark detail no longer rendered anywhere |

### 4.5 Decisions log (V.7.7C.5 reframe Q&A)

The §4 rewrite resolved the open spec questions surfaced by the V.7.7C.5 ENGINEERING_PLAN entry. Captured here for future reference:

| Q | Decision | Rationale |
|---|---|---|
| Q0 — direction | (A) atmospheric abstraction | Matt: "I have no confidence that you can render a forest in 2D" — simplification primary motive |
| Q1 — frame | "atmosphere is a fixed stage" | Direct rephrase of §4.1 opening |
| Q2 — sky band | (b) expand to fill frame | Compensates for retired forest floor |
| Q3 — distant trees | retire | (A) consequence |
| Q4 — mid trees | retire | (A) consequence |
| Q5 — near-frame branches | retire | "lines do not read as branches" — and retiring solves it cleanly |
| Q6 — forest floor | retire | (A) consequence; sky band fills lower edge |
| Q7 — fog density | (c) volumetric god-ray anchored | Beam-anchored fog reads as cinematographic god-rays |
| Q8 — light shafts | (b) 1–2 shafts mood-driven; brightness raised from `0.06 × val` to `0.30 × val` | Matt's "fog and light behind the web" — shafts must read as hero elements |
| Q9 — dust motes | (c) concentrate in shaft cones | Caustic-like; ties motes + shafts into a single visual element |
| Q10 — mood palette | keep verbatim | Recipe is sound; issue was the layers, not the palette |
| Q11 — silence anchor | keep | Cross-preset convention |
| Q12 — §5.9 anchor twigs | retire entirely | Polygon vertices alone provide WEB attachment; no literal "branch" or "twig" anywhere |
| Q13 — references | (b) reinterpret existing | Matt: "you don't follow the references anyway, so what does it matter?" — references stay as mood-palette anchors only |

---

## 5. THE WEB

### 5.1 Real construction biology

Real orb-weaver spiders construct webs in this sequence (Foelix, *Biology of Spiders*, 3rd ed. ch. 6; British Arachnological Society 2024; Eberhard 1990):

1. **Bridge thread.** A single horizontal silk thread between two anchor points, drifted across on the wind. The first commitment to a location.
2. **Y-frame.** A single radial drops from the bridge thread to a third anchor point below, creating a Y-shape. The intersection becomes the eventual hub.
3. **Frame threads.** The outer perimeter of the eventual web — an irregular polygon (4–7 sides) bounded by the actual anchor points (branches, twigs, leaves). NOT a circle.
4. **Hub.** The point where the radials converge. A small dense knot of silk; not concentric rings.
5. **Radials.** 12–17 thin threads from hub to frame, laid in alternating-pair order (left-right balanced) for naturalistic angular distribution.
6. **Auxiliary spiral.** A temporary wide spiral wound from hub OUTWARD, used as scaffolding while the spider lays the capture spiral.
7. **Capture spiral.** The final adhesive spiral, laid from the OUTER FRAME spiraling INWARD toward the hub. As the spider winds inward, it dismantles the auxiliary spiral.
8. **Free zone and finishing.** A small no-spiral zone around the hub; spider rests at hub.

**The 2026-05-02 spec inverted step 7.** That version had the capture spiral winding outward, which is geometrically simpler but biologically wrong. This rewrite corrects the direction: the capture spiral winds INWARD from the outer frame to the hub. This direction is non-trivial — when the user watches the build, the visual character of "winding inward" (the spiral closing around the hub) is fundamentally different from "winding outward" (the spiral expanding into emptiness). Inward winding is what real spiders do, and what the BBC time-lapse footage shows.

### 5.2 Phosphene's 60-second compressed cycle

Compress steps 1–8 into a 60-second build cycle, eliding biology that wouldn't read at this scale (auxiliary spiral, distinct frame-thread vs bridge phases):

| Phase | Time | What's drawn |
|---|---|---|
| Frame | 0–3s | Bridge thread first (single horizontal between two anchors), then 3–6 additional frame threads connecting branch anchors into an irregular polygon. |
| Radials | 3–25s | 12–17 radials extending from hub to frame, alternating-pair order, ±20% angular jitter per spoke. Each radial draws over ~1.5s. |
| Capture spiral | 25–55s | Chord segments laid INWARD from outer frame to hub. Drops accumulate on each chord as it's laid. Wind progresses chord-by-chord at audio-modulated rate. |
| Settle | 55–60s | Hub finish; brief pause; web emits `presetCompletionEvent`. |

Build pace audio-modulated per §7. Average music: ~50–55s (within the 60s ceiling); silence: ~75s (orchestrator transitions before completion); heavy mid-band: ~45s.

**No spider visible during construction.** The threads "draw themselves" as if by an invisible hand. Showing the spider building the web was considered and rejected: a continuously-visible spider would dominate the frame and break the easter-egg rarity that makes the SPIDER pillar meaningful. The BBC time-lapse footage also frequently shows the build with the spider out of frame.

### 5.3 Frame polygon

**Not a circle.** Real orb webs are bounded by an irregular polygon whose vertices are the anchor points the spider could find. Reference 11 shows this directly — the web is bounded by branches at multiple positions, not by a circular boundary.

For Phosphene: 4–7 frame anchor points, distributed irregularly around the visible web area but determined by the WORLD's near-frame branches (§4.2.4). The polygon is computed when the segment begins:
- Identify the entry points of near-frame branches into the frame.
- Pick a subset of 4–7 branch-edge points as anchor candidates, biased toward roughly-perimeter distribution but allowing irregularity.
- Connect adjacent anchors (in angular order around the polygon centroid) with frame threads.

The polygon is asymmetric on purpose. Ref 09 is the symmetric anti-reference; symmetry is the failure mode. If the polygon comes out symmetric by chance, perturb it (rotate one anchor by 15°).

### 5.4 Hub

A small dense knot of silk at the geometric centroid of the polygon, offset by `rng_seed`-driven jitter (±5% of the polygon's bounding-box short axis — the hub is rarely exactly centered in real webs). Free zone: no spiral threads within ~`hub_radius * 1.5` of the hub.

The hub is **not concentric rings.** The V.7.5 hub used a target-style ring structure; that's anatomically wrong (refs 01, 11, 12 all show the hub as a tangled small knot, not concentric circles). Real hubs look like overlapping silk — implementable as a small radius patch of high-density `worley_fbm` noise, threshold-clipped to give the look of overlapping silk strands.

### 5.5 Radials

12–17 thin lines from hub to polygon edge, count drawn from `rng_seed` (per-segment determinism). Angular distribution biased toward equiangular but with ±20% per-spoke jitter from `hash_f01(seed * radial_index)`. Each radial has its own slight per-radial sag amount within the kSag range (§5.7), so the visible weight of each radial differs.

**Alternating-pair draw order.** During the build sequence (§5.2 Radials phase), radials are laid in the order `[0, n/2, 1, n/2+1, 2, n/2+2, ...]` rather than clockwise. This visually balances the web fill — each new radial extends opposite the previous one, so the in-progress shape always reads as approximately radially complete, not lopsided.

Each radial's visible drawing-itself animation: `buildAccumulator` controls the visible length from hub outward over ~1.5s. The radial is "drawn from spider" — the tip extends outward from the hub; the hub end has been there since the radial's draw started.

### 5.6 Capture spiral — chord-segment SDF, INWARD

The capture spiral is N straight chord segments per revolution, each connecting an attachment point on radial `i` to the next attachment point on radial `i+1` mod N. **Not** a continuous Archimedean curve.

Reasons:
- Chord segments are SDF-friendly (line-segment SDF is fast and clean).
- Real capture spirals visually break into chord-like segments at typical scales — the spider lays straight silk between two radials before pivoting at the next radial.
- Continuous Archimedean curves degenerate into target-circle visuals at low resolution (V.7.5 failure mode — Failed Approach #34 was a related SDF-correctness bug at the formula level, but the *visual* failure was ring-spirals reading as a bullseye).

**Spiral parameters.**
- Outer radius: ~95% of polygon's inscribed-circle radius.
- Inner radius: ~`hub_radius * 1.5` (free zone boundary).
- Revolutions: 7–9 turns from outer to inner. Per-segment determined by `rng_seed`.
- Per-turn shrinkage: `pitch ≈ (outer - inner) / turns`. Stays approximately constant (real capture spirals have approximately uniform spacing between turns).

**Direction.** The visible draw-itself progression winds INWARD: chord-by-chord from outer to inner, finishing at the free-zone boundary. The `spiralBuildAccumulator` advances chord index from outermost = 0 to innermost = total - 1. Building chord at index `k` reveals it (alpha 0 → 1 over ~0.3s) and deposits drops on it (§5.8).

### 5.7 Sag

Each thread sags parabolically:
```
y_offset = u * (1.0 - u) * kSag * length * gravityWeight
```
where `u` is the parametric position along the thread (0..1, midpoint = 0.5), `length` is the thread length in UV space, `kSag` is the per-web sag coefficient drawn from `[0.10, 0.18]` (calibrated against ref 02 — longest visible radial sags ~8–12% of its length; the V.7.5 range `[0.06, 0.14]` was admitted in that spec as too subtle), and `gravityWeight` projects the local sag direction onto the world-down axis (downward radials sag more than horizontal; upward radials don't sag but droop downward at their midpoint anyway since gravity is real).

`gravityWeight` is the dot product of the radial's outward direction with world-down (positive y in our convention), clamped non-negative for radials angled above horizontal: `gravityWeight = mix(0.4, 1.0, max(0, sin(spokeAngle)))` (the V.7.5 recipe). 0.4 minimum so even upward radials show some droop.

**Drop weight modifies sag.** Chord segments with many drops sag more: per-chord `sagAmount += 0.04 * dropCount / maxDropsPerChord`. This is what produces the dewy droopy look in refs 02 and 03 — heavily-dewy chords on the lower half of the web visibly droop under their drops. Drops cluster in the troughs of sagging chords, which makes the sag self-reinforcing visually.

### 5.8 Drops — the visual hero

Drops do 80% of the visual work. Threads are connective tissue between drop chains. This is the conclusion the 2026-05-03 reference review arrived at: in refs 01, 02, 03, the silk threads are barely visible at all — what you see is drops, drops, drops chained along nearly-invisible threads.

**Placement.** Drops appear on capture spiral chords ONLY. Real adhesive silk is only on the capture spiral; radials and frame threads are smooth (no glue, no drops). This is biology and matches refs 03 and 04. It's also a meaningful design constraint — drops on radials would wash out the radial structure, and the radial structure is what makes the web read as a web.

**Spacing.** Plateau-Rayleigh instability makes real drops uniform-spaced (§13 citations). Surface tension breaks a continuous water film into regular beads at characteristic spacing of about 4–5 drop-diameters. For Phosphene: along each chord, place drops at 4–5 drop-diameter spacing with ±5% hash-jitter (NOT the V.7.5 ±25% — that was wrong; refs 03 confirm real drops are nearly-uniform). Drop-count-per-chord scales with chord length so spacing stays even.

**Size.** Each drop's radius is ~0.008 UV (≈ 8.6 px at 1080p — continuing V.7.5's 8.6 px target, which was correct as a goal even though V.7.5 didn't make drops the visual hero). ±5% per-drop variation from `hash_f01`. Drops near the hub are slightly smaller (older silk, more drainage); drops near the frame are slightly larger.

**Shape.** Filled circles in 2D, but the lighting recipe makes them read as 3D spheres:

- **Spherical-cap normal.** For a drop at center `c` with radius `r`, at sample point `p` inside the drop, compute `localUV = (p - c) / r`. The 3D normal of a spherical cap at this UV is `n = float3(localUV, sqrt(saturate(1.0 - dot(localUV, localUV))))`.

- **Refraction via Snell's law.** Sample `arachneWorldTex` (the WORLD pass output) at `p`, but offset by the refracted view ray. View ray is `float3(0, 0, -1)` (camera-aligned, 2D scene). Refracted ray: `refract(viewRay, n, eta)` with `eta = 1.0 / 1.33 ≈ 0.752` (water IOR). The refracted ray's xy projection becomes a UV offset; sample `arachneWorldTex` at `c + refractedOffset * worldSampleScale` where `worldSampleScale ≈ 2.5 * r` (tunable — controls how much the WORLD is "magnified" through the drop). This inverts the WORLD through the drop — what's at the top of the WORLD shows at the bottom of the drop, the classic photographic dewdrop signature.

- **Fresnel rim.** At the drop's edge (where `localUV` magnitude approaches 1), Schlick fresnel boosts brightness: `fresnel = pow(1.0 - saturate(n.z), 5.0)`. Add `fresnel * 0.4` to the local color, tinted toward `kLightCol * 0.85` so the rim picks up the warm key light.

- **Specular pinpoint.** A single bright dot at the position where the dominant light direction (`kL` projected to screen) hits the spherical cap. Compute `halfVec = normalize(kL.xy + viewRay.xy)`; specular position on the drop is `c + halfVec * r * 0.6`. Use a tight `1.0 - smoothstep(0.0, 0.2, dist_from_specular_position / r)` to make the highlight small and sharp. Specular color is `kLightCol * 0.85`.

- **Dark edge ring.** A thin darker ring where the sphere curves toward grazing angles and refraction breaks down. Implementation: `darkRing = smoothstep(0.85, 0.95, length(localUV)) * (1.0 - smoothstep(0.95, 1.0, length(localUV)))`. Multiply the drop's color by `(1.0 - darkRing * 0.5)` to darken that band.

**Accretion over time.** Foreground spiral chords have FEW drops at the moment they're laid; drop count grows on each chord during the remaining build time. Background webs are saturated from preset entry (older webs).

Implementation: for chord `k` laid at build time `t_k`, drop count at current time `t` is `min(maxDrops, baseDrops + accretionRate * (t - t_k))` where `accretionRate ≈ 0.5 drops/second/chord` and `maxDrops ≈ chord_length * dropDensity`.

### 5.9 Anchor logic — terminate at polygon vertices

> **V.7.7C.5 reframe (2026-05-09).** Per Q12 the §5.9 literal-branch / literal-twig rendering is retired alongside §4.2.4 (near-frame branches) and §4.2.5 (forest floor) of the WORLD reframe. The web's frame threads now terminate at the polygon vertex positions in `kBranchAnchors[]` directly, without rendering visible branch or twig structure at those positions. Polygon vertices remain visible only as the implicit endpoints of frame thread polygon edges + radial spoke tips. The "anchor blob" detail (V.7.7C.2 deferred sub-item #2 — small adhesive silk discs at polygon vertices) is retained as the sole visual hint of attachment point at those positions; it remains a V.7.10 deferred sub-item.

The web's outer frame threads terminate at the polygon vertex positions defined by `kBranchAnchors[]` (constants in `Arachne.metal` line ~153 + `ArachneState.swift`). The constants stay — `ArachneState.selectPolygon(rng:)` continues to consume them as polygon vertex candidates, and `ArachneBranchAnchorsTests` continues to regression-lock the Swift / MSL sync.

Implementation (V.7.7C.5):
- Each frame anchor point is the polygon vertex position from `kBranchAnchors[bs.anchors[i]]`.
- At the anchor point, render a small adhesive blob (radius ~`drop_radius * 1.3`, color matching nearby silk + slight warm tint, no refraction — adhesive silk is opaque). Implementation deferred to V.7.10 cert review (V.7.7C.2 deferred sub-item #2 still standing).
- The frame thread terminates *into* the blob position. With the §4.2.4 branches retired in V.7.7C.5, the silk no longer "wraps" any visible structure — the blob alone marks the attachment.
- The §5.9 anchor twigs added in V.7.7C.2 Commit 1 (`drawWorld()` rendering of six small dark capsule SDFs at `kBranchAnchors[i]` positions) are retired in V.7.7C.5 per Q12. The capsule-SDF rendering loop in `drawWorld()` is removed; the constants stay.

**Why no literal branches anywhere in V.7.7C.5.** The V.7.7B–C.4 spec depicted branches at multiple scales (distant tree silhouettes / mid-distance trees / near-frame branches / anchor twigs). The 2026-05-08T18-28-16Z manual smoke confirmed they did not read as branches at any scale ("the lines do not read as branches"). V.7.7C.5 retires literal branch / twig rendering entirely; the polygon perimeter is now defined by abstract anchor positions in atmosphere, not by visible structures the silk attaches to. This is consistent with the "atmospheric abstraction" framing from §4.1.

The V.7.5/V.7.7B–C.4 commentary on bark-vs-twig anchor scale (Matt's empirical correction 2026-05-03 about real webs anchoring to twigs/leaf petioles/grass stems) is retained in version-history form: it informed why V.7.7C.2's `kBranchAnchors[6]` are at irregular UV positions near frame edges rather than centered on imagined trunks. The constants' positions remain biologically defensible even though the rendered "twigs" are gone.

### 5.10 Silk material — minor finishing

Silk threads themselves are barely visible in refs 01, 02, 03. Drops do the visual work; silk is the line the drops hang on.

For Phosphene: silk threads are rendered as thin (1–2 px) lines with a subtle axial highlight when the `kL` direction grazes them at low angle (`abs(dot(strandDir, kL.xy)) < 0.3`). Color: `mix(botCol, topCol, 0.5) * silkTint` where `silkTint ≈ 0.5–0.7` (V.7.5's 0.32 was correct in spirit but Marschner-lite was over-spec).

The Marschner-lite fiber BRDF specified in earlier versions of the spec is **removed as a v8 implementation priority.** Ref 04 (the silk close-up) is preserved as a reference for restrained axial glints, but not as the primary silk recipe — ref 04 represents the silk material at extreme zoom; at typical Arachne frame scale, threads read as faint translucent lines plus drops, not as silk fibers with axial Marschner highlights. The earlier choice to make Marschner-lite mandatory was a misreading of ref 04's role: it's an edge case in the reference set, not the dominant visual goal.

This is the section where this rewrite materially differs from V.7's spec. V.7 made silk a featured material and got primitive output anyway; V.8 demotes silk to "a line drops hang on" and lets refractive droplets + sag + irregular geometry + world interaction carry the fidelity.

### 5.11 Lighting interaction with the world

Two lighting interactions matter:

- **Backlit silk against atmospheric glow.** When the WORLD is bright (high arousal, light shafts present, warm mood), silk threads that lie within a light shaft pick up extra brightness via screen-space proximity to the shaft. Implementation: sample shaft intensity at the silk's screen position; multiply silk brightness by `1.0 + 0.6 * shaftIntensity`. This produces the look of refs 04 and 05 — silk catching light against an atmospheric glow.

- **Drops refract the WORLD.** Already specified in §5.8. The WORLD's gradient, foliage silhouettes, and light shafts all show through drops via refraction. This is what makes drops read as photographic dewdrops rather than abstract spheres. It also means the WORLD pass MUST land before the WEB pass — the drop refraction depends on `arachneWorldTex` being populated.

### 5.12 Background webs

1–2 already-finished dewy webs at depth, present from preset entry. Avoid the empty-scene problem during the first build cycle. Specified in 2026-05-02 §1.1; preserved here:

- Geometry: same as foreground (frame polygon + radials + chord-segment capture spiral + sag), but with `sagAmount` at upper end of the range (`[0.14, 0.18]`) so background webs read as more weathered.
- Drops: saturated from preset entry (older webs — full drop count on every chord).
- Blur: mild Gaussian blur applied so foreground reads as the focus point.
- Vibration: applies (§8.2) — background webs shake on bass.
- Migration: when foreground build completes, the foreground web migrates to the background pool over a ~1s crossfade. Old background web fades out if the pool is at capacity. Pool size: 1–2 background webs. No more.

### 5.13 Reference cross-walk

| Web element | Primary reference | Secondary references |
|---|---|---|
| Hero frame match | `01_macro_dewy_web_on_dark.jpg` | — |
| Per-strand sag | `02_meso_per_strand_sag.jpg` | `01` |
| Drop placement + spacing | `03_micro_adhesive_droplet.jpg` | `01` |
| Drop refraction signature | `01`, `03`, `04` | — |
| Anchor polygon context | `11_anchor_web_in_branch_frame.jpg` | — |
| Backlit silk + atmosphere | `04_specular_silk_fiber_highlight.jpg` | `05`, `01` |
| Silk axial highlight (minor lighting effect) | `04_specular_silk_fiber_highlight.jpg` | — |
| Anti-reference (clipart) | `09_anti_clipart_symmetry.jpg` | — |
| Anti-reference (neon) | `10_anti_neon_stylized_glow.jpg` | — |

---

## 6. THE SPIDER

The spider is the easter egg. It is rare. When present, it must carry as much fidelity as the WEB and WORLD — there is no point in a rare appearance that reads as a smudge. The V.7.5 implementation rendered the spider as a near-black silhouette with a thin warm rim and an alternating-tetrapod gait; that was the right *direction* but the wrong *depth*. This pillar specifies the spider at full depth.

### 6.1 Anatomy

(Per refs 12 and 13.)

The spider is rendered as a 3D SDF on a small screen-space patch (full resolution; rest of frame is sampled from composited WEB+WORLD passes via the foreground composite texture).

- **Cephalothorax (front body segment).** Slightly flattened ellipsoid, ~1.0 unit long × 0.7 wide × 0.5 tall in body-space. Smooth surface; this is where eyes and legs originate.
- **Abdomen (rear body segment).** Larger rounded ellipsoid behind cephalothorax, ~1.4 long × 1.1 wide × 0.95 tall. Connected to cephalothorax by a narrow petiole — a smooth-union neck region with negative blend (`op_smooth_subtract` with small radius creates the visible neck).
- **Legs (eight, articulated).** Each leg has 7 anatomical segments (coxa-trochanter-femur-patella-tibia-metatarsus-tarsus); the visible articulation needs only 3 in the SDF: a "hip" where the leg joins the cephalothorax, a knee bend, and a tip. Per ref 13, the knee bends OUTWARD (away from the body in the leg's plane), not downward — this is the orb-weaver-specific posture. Two-segment IK to compute knee position from hip + tip + segment lengths. The IK solver lives in the spider state (CPU side), not the SDF — the SDF receives knee positions per frame.
- **Eye cluster.** 8 small eyes in a tight forward cluster on the cephalothorax. Most orb-weavers have 4 prominent eyes in a 2x2 anterior arrangement plus 4 smaller posterior eyes; per-eye count is barely discriminable at typical zoom — render as a small `worley_fbm`-thresholded patch of 6–8 dark dots within an oval area (NOT the two large forward-facing eyes of a jumping spider — ref 19 is the eye-specular technique reference, not the eye-anatomy reference; the README annotation on ref 19 is explicit about this).
- **Abdominal pattern.** Per ref 12, garden orb-weavers have a distinctive cream-and-brown striped or spotted dorsal pattern. For Phosphene: render a 2-band dorsal pattern (lighter median stripe + darker flanking bands) using `worley_fbm` thresholded against a body-space y-coordinate. Subtle — doesn't dominate the body color, but readable as "this is a real species."

### 6.2 Material

(Per ref 14.)

Chitinous carapace with thin-film iridescence. Recipe:
- **Base color.** Dark brown-amber `(0.08, 0.05, 0.03)`. Body absorbs more light than it reflects. This is the V.7.5 base, kept.
- **Thin-film iridescence.** Hue rotates with view angle: `hue = 0.55 + 0.3 * dot(normal, viewDir)`. Saturation 0.5, value 0.4. Composited additively at low strength (0.15) so it tints the body rather than dominating. The V.3 `mat_chitin` cookbook recipe is the foundation; the strength is what makes it read as biological vs neon (high strength → ref 10 anti-neon territory).
- **Hair fuzz.** Subtle Oren-Nayar-like roughness via `pow(1 - saturate(dot(normal, viewDir)), 1.5) * 0.18` — gives the velvety look of ref 14 without explicit fur geometry.
- **Eye specular.** Per ref 19, single bright pinpoint reflection on each visible eye lens. Compute halfVec for each eye from `kL`; if `dot(halfVec, eyeNormal) > 0.95`, render a small bright dot at the eye position. This is what makes the spider read as alive rather than glassy.

NOT bioluminescent in the neon sense (ref 10 anti-reference). The thin-film iridescence is biological — ref 14's tarantula shows it without being neon. Ref 08 (palette anchor) shows the correct interpretation of "biological luminescence": dark base with subtle hue accents, not pure-saturation glow.

### 6.3 Pose, gait, listening pose

**Resting pose (default when on web).** Spider is positioned at the foreground web's hub, head pointing toward the center of the spiral (orientation uses one radial as the "downward" reference). All 8 legs fan out radially, gripping radials within reach. Front legs slightly raised compared to rear (the existing Stalker preset's recipe — orb-weavers at rest do hold front legs forward).

**Walking gait — alternating tetrapod.** When the spider walks (slow drift across the web during a long sustained-bass passage), legs move in two alternating sets of four: legs 1, 3, 5, 7 lift while 2, 4, 6, 8 plant; then swap. Phase-locked to BPM via soft pull (not snap) per Stalker's existing implementation. For Arachne, walking is rare — the spider mostly sits at the hub. The gait code can be lifted from `StalkerGait.swift` directly; the visual feedback model differs (Arachne spider is at the hub with limited motion range, not crossing a static web like Stalker).

**Listening pose.** When sustained bass holds (`stems.bassAttackRatio < 0.55` and `f.subBass_dev` high for ≥ 1.5s), the spider raises its two front legs (legs 1 and 2, leftmost pair) ~30° off the web. Legs are still gripping with the metatarsus/tarsus end; the lift is at the femur-patella joint. This is the canonical "listening for vibration" pose real orb-weavers adopt when they detect prey on the web. Hold pose while bass sustains; relax over ~1s when bass eases.

The listening pose is the SPIDER pillar's signature audio-reactive moment — it's what makes the spider feel responsive to the music in a way no abstract preset can match.

### 6.4 Lighting

The spider is lit by the WORLD's key light direction `kL` (warm-amber) and ambient fill (cool, dim). Specifically:
- **Body shadow.** Most of the body is in deep shadow — `body_color * 0.3` at minimum. The body absorbs light; ref 12 and 14 both show spiders as predominantly dark with selective highlights.
- **Rim light.** A thin warm-amber rim where the surface curves toward the viewer at grazing angle: `rim = pow(1 - saturate(dot(normal, viewDir)), 3) * kL_warmth`. Brightness ~0.5–0.8 at the strongest curvature. This is the V.7.5 rim, preserved.
- **Eye sparkle.** Per §6.2 — bright pinpoint when `halfVec` aligns with eye normal.

The spider must read as a dark biological object in a softly-lit forest, not as a neon glowing graphic. If at runtime the spider reads as too bright, the body base color or rim brightness is the lever (don't lower iridescence — that's the alive quality).

### 6.5 Trigger and behavior

Mostly preserved from 2026-05-02 §1.3 + §2:

**Trigger.** Sustained `f.subBass_dev > 0.30` AND `stems.bassAttackRatio ∈ (0, 0.55)` for ≥ 0.75s. Sub-bass with low attack ratio = sustained resonant low frequency, not transient kick drums. The distinction is what makes the trigger feel meaningful — the spider responds to the *music's character*, not to drum hits. (Failed Approach #33 reference: free-running motion divorced from music is the failure; this trigger ties the spider's appearance to a specific musical quality.)

**Cooldown.** Per-segment flag: at most one spider appearance per Arachne segment. Combined with the natural rarity of sustained-low-attack-ratio sub-bass, this targets ~1 spider per 5–10 Arachne segments without an explicit timer. The V.7.5 300s session cooldown is dropped — segment-scoped cooldown is sufficient and more deterministic.

**On trigger:**
- Spider fades in at the foreground web's hub over ~2s.
- Foreground build PAUSES (the chord-laying accumulator stops). The web at this moment is whatever fraction was built when the spider appeared — which means the spider can appear at any phase, including very early (only frame + a few radials) or very late (almost-complete spiral). That variation is intentional.
- If the spider triggers during the radials phase, the web has only the frame + some radials — the spider sits at the hub on a partly-completed web. Visually fine; matches what BBC time-lapse footage shows when a spider pauses mid-build.

**During presence:**
- Spider holds resting pose by default; transitions to listening pose if the bass sustains as described in §6.3.
- Vibration shake (§8.2) applies to the whole scene continuously. The spider's body itself participates in the shake (its position offsets with the foreground web's hub).
- Eye sparkles flash when the music's key-light direction shifts (which it does as `kL` is mood-driven).

**On bass ease:**
- Spider fades out over ~2s.
- Foreground build RESUMES from where it paused. Does not restart.

### 6.6 Reference cross-walk

| Spider element | Primary reference | Notes |
|---|---|---|
| Dorsal anatomy + pattern | `12_spider_orb_weaver_dorsal.jpg` | Anatomical baseline |
| Lateral leg articulation | `13_spider_orb_weaver_lateral.jpg` | Knee bend direction |
| Material (chitin + thin-film + hair) | `14_spider_iridescent_chitin.jpg` | Material recipe ONLY — NOT anatomy (tarantula, not orb-weaver) |
| Eye specular | `19_spider_eye_specular.jpg` | Highlight technique ONLY — NOT eye anatomy (jumping spider, not orb-weaver) |
| Backlit context | `05_lighting_backlit_atmosphere.jpg` | Spider visible in frame but incidental — atmosphere is the lesson |
| Anti-reference (neon) | `10_anti_neon_stylized_glow.jpg` | Iridescence at high strength → here. Stay in biological territory. |

---

## 7. Audio mapping

D-026 deviation primitives only. No absolute thresholds. Continuous/beat ratio ≥ 2× per CLAUDE.md rule of thumb.

| Audio source | Drives | Continuous / accent | Pillar |
|---|---|---|---|
| `smoothedValence` (5s low-pass on `f.valence`) | WORLD palette hue | Continuous | WORLD |
| `smoothedArousal` (5s low-pass on `f.arousal`) | WORLD palette saturation/brightness; aurora ribbon visibility (high arousal) | Continuous | WORLD |
| `f.mid_att_rel` | fog density; light shaft brightness; dust mote density; foreground build pace; drop accretion rate | Continuous | WORLD + WEB |
| `f.bass_att_rel` | foreground build pace (radial advance, spiral chord placement) | Continuous | WEB |
| `stems.drums_energy_dev` | brief construction-pace acceleration on drum onsets | Beat accent | WEB |
| `max(f.subBass_dev, f.bass_dev)` | **whole-scene vibration amplitude** (all webs + spider + branches) — see §8.2 | Continuous | WORLD + WEB + SPIDER |
| `f.beatBass` | brief vibration amplitude spike per kick | Beat accent | (vibration overlay) |
| `stems.vocals_pitch` | optional subtle hue shift on background-web drops (vocal melody → drop tint) | Continuous | WEB (optional, V.7.9 polish) |
| Sustained `f.subBass_dev > 0.30 && stems.bassAttackRatio < 0.55` for ≥ 0.75s | **spider trigger** | Threshold event | SPIDER |
| Sustained low attack ratio bass for ≥ 1.5s during spider presence | **listening pose** activation | Threshold event | SPIDER |
| `f.beat_phase01` | dust-mote phase (when gated, see §4.2.6); aurora ribbon motion (when present) | Continuous (phase-locked) | WORLD |

**Construction pace audio mapping (foreground only):**
- Base rate: 1 chord segment / second at silence.
- Mid-band continuous boost: `+0.18 * f.mid_att_rel` segments/second.
- Drum-onset accent: `+0.5 * stems.drums_energy_dev` (per-frame, decays naturally).
- Total build time at average music: ~50–55s (within the 60s ceiling). At silence: ~75s (would exceed ceiling — orchestrator transitions before completion).

**Spider behavior on trigger:** see §6.5.

---

## 8. Render architecture

### 8.1 Pass layout

Per frame, in order:

1. **WORLD pass** → `arachneWorldTex` (half-res). Renders §4.2 layers back-to-front: sky band → distant trees → mid-distance trees → near-frame branches → forest floor → fog → light shafts → dust motes. Mood-driven palette per §4.3. Subtle Gaussian blur baked in (3–5 px) to give the impression of camera focus on the WEB.

2. **Background webs pass** → composite over `arachneWorldTex`. 1–2 pre-populated dewy webs at depth (§5.12). Drops sample `arachneWorldTex` via the refractive recipe (§5.8). Mild additional Gaussian blur (depth-of-field).

3. **Foreground web pass** → composite over background composite. SDF chord-segment threads (drawn-so-far portion only, controlled by `buildAccumulator`) + refractive drops on completed spiral chords. Sharp focus. Vibration offset applied (§8.2).

4. **Spider overlay** → if `spiderBlend > 0`, composite spider SDF over foreground (§6).

5. **Post-process** → `PostProcessChain` bloom on bright drops + spider rim + light-shaft tips. ACES tone-mapping. Optional depth-weighted bokeh DoF for additional separation.

The half-resolution WORLD texture is the cost-saving choice. Drops sample it; if WORLD at full resolution is required for refraction sharpness, this is the architectural call to make during V.7.7 implementation. Initial scope assumes half-res is sufficient — the WORLD's role is to provide *colors* and *layered depth* for the drops to refract, not pixel-sharp detail.

### 8.2 Vibration model

Whole-scene tremor on bass. Applied as per-vertex UV offset in the vertex shader of every web (background + foreground) and per-frame translation offset on the spider position.

```hlsl
// Per-strand random phase from rng_seed for naturalistic incoherence.
float strandPhase = rand(seed * 0.001 + radial_index * 0.137);

// Audio-driven amplitude. Continuous from sub-bass + bass deviation.
float bassAmp = max(f.subBass_dev, f.bass_dev);
float beatSpike = 0.4 * f.beatBass;  // brief +40% on each kick
float amplitude = (0.0025 * bassAmp + beatSpike * 0.0015) * length(thread_local_position);

// 12 Hz tremor rate — fast enough to read as vibration, slow enough not to blur.
float tremor = sin(2.0 * M_PI_F * 12.0 * time + strandPhase * 6.28);

// Apply offset perpendicular to strand direction (where vibration physically goes).
float2 perp = normalize(float2(-strand_dir.y, strand_dir.x));
vertex_offset += perp * tremor * amplitude;
```

Tunables:
- `tremor_frequency = 12 Hz` (perceptible vibration; not a swaying motion)
- `bass_amplitude_scale = 0.0025` (UV-space; visible at moderate bass, prominent at heavy bass)
- `beat_spike_amplitude = 0.0015` (brief per-kick spike)
- `length-scaling factor` so tips of long radials shake more than near-hub points (physically correct — anchor stays still, tip moves)

The near-frame branches (§4.2.4) also shake by a smaller amplitude (`amplitude * 0.3`) so the WEB's anchor points move with the branches, not against them. The forest floor and distant layers do not shake (too far away to read motion at this amplitude).

### 8.3 Pure-black silence anchor

If `(satScale × valScale) < 0.05` (silence-state mood signal), the WORLD pass clears to black; gradient + foliage + fog + shafts + motes all suppressed. Background webs stay rendered (drops still sample the now-black world; refraction returns black, drops read as dim outlines plus their fresnel rim and specular). Foreground web continues drawing-itself; threads and drops render against black. The palette fades back in as audio resumes.

This is the calibration anchor (ref 08). Phosphene's silence state is *deliberate* black, not styled darkness.

---

## 9. Per-preset `maxDuration` framework — shipped reference

This section preserves the V.7.6.C-shipped framework verbatim for reference. Behavior is locked. New presets declare `naturalCycleSeconds` (optional) and `is_diagnostic` (default false) per the shipped schema.

### 9.1 Inputs

All from existing data — no new declarations required except an optional `naturalCycleSeconds` for presets with fixed cycles (Arachne).

| Input | Source | Range |
|---|---|---|
| `motionIntensity` | preset JSON sidecar | 0..1 |
| `visualDensity` | preset JSON sidecar | 0..1 |
| `fatigueRisk` | preset JSON sidecar | enum {low=0, medium=1, high=2} |
| `naturalCycleSeconds` | preset JSON sidecar (optional) | seconds, only set for presets with a fixed visual cycle |
| `isDiagnostic` | preset JSON sidecar (default false) | bool — diagnostic presets return `.infinity` |
| `sectionLingerFactor` | per-section table | 0..1 |

### 9.2 Formula

```swift
func computeMaxDuration(preset: PresetDescriptor, section: SongSection?) -> TimeInterval {
    // Diagnostic presets are exempt — they remain in place until manually switched.
    if preset.isDiagnostic { return .infinity }

    // Base maxDuration from preset properties — answers "how long does this preset stay
    // interesting on average music?"
    let baseMax: Double = 90.0
                        - 50.0 * (preset.motionIntensity - 0.5)
                        - 30.0 * Double(preset.fatigueRisk.score)  // low=0, medium=1, high=2
                        - 15.0 * (preset.visualDensity - 0.5)

    // Section adjustment — ambient/peak linger; buildup/bridge are transitional.
    let sectionAdjust = baseMax * (0.7 + 0.6 * lingerFactor(section))

    // Hard cap from natural cycle length (Arachne's 60s build, etc.)
    if let cycle = preset.naturalCycleSeconds {
        return min(cycle, sectionAdjust)
    }
    return sectionAdjust
}

// V.7.6.C Option B linger factors:
//   ambient  = 0.80   (longest — meditative)
//   peak     = 0.75   (climactic moments are the emotional core)
//   comedown = 0.65
//   buildup  = 0.40   (transitional)
//   bridge   = 0.35   (transitional, shortest)
//   nil      = 0.50   (neutral midpoint when no section context)
```

### 9.3 Computed values (V.7.6.C calibrated)

| Preset | motionIntensity | visualDensity | fatigueRisk | naturalCycle | default | ambient | peak | comedown | buildup | bridge |
|---|---|---|---|---|---|---|---|---|---|---|
| Arachne | 0.50 | 0.65 | low | **60s** | 60 | 60 | 60 | 60 | 60 | 60 |
| Ferrofluid Ocean | 0.65 | 0.75 | medium | — | 49 | 58 | 56 | 53 | 46 | 44 |
| Fractal Tree | 0.55 | 0.65 | medium | — | 55 | 65 | 64 | 60 | 52 | 50 |
| Glass Brutalist | 0.40 | 0.40 | medium | — | 67 | 79 | 77 | 73 | 63 | 61 |
| Gossamer | 0.30 | 0.40 | low | — | 102 | 120 | 117 | 111 | 95 | 92 |
| Kinetic Sculpture | 0.70 | 0.60 | medium | — | 49 | 57 | 56 | 53 | 46 | 44 |
| Membrane | 0.70 | 0.55 | medium | — | 49 | 58 | 57 | 54 | 46 | 45 |
| Murmuration | 0.85 | 0.90 | low | — | 67 | 79 | 77 | 73 | 63 | 61 |
| Nebula | 0.30 | 0.80 | low | — | 96 | 113 | 110 | 104 | 90 | 87 |
| Plasma | 0.50 | 0.70 | high | — | 27 | 32 | 31 | 29 | 25 | 25 |
| Spectral Cartograph | 0.00 | 0.10 | low | — | ∞ | ∞ | ∞ | ∞ | ∞ | ∞ |
| Volumetric Lithograph | 0.60 | 0.70 | low | — | 82 | 97 | 94 | 89 | 77 | 75 |
| Waveform | 0.60 | 0.30 | medium | — | 58 | 68 | 67 | 63 | 54 | 53 |

Spectral Cartograph is flagged `is_diagnostic: true`. Diagnostic presets are exempt from the framework — they return `.infinity` and are never auto-segmented (V.7.6.D wired this through Scorer + LiveAdapter + Planner + Reactive).

### 9.4 Implication for orchestrator

`PresetDescriptor.maxDuration` is a computed property, not a JSON field:

```swift
extension PresetDescriptor {
    func maxDuration(forSection section: SongSection) -> TimeInterval {
        computeMaxDuration(preset: self, section: section)
    }
}
```

JSON sidecar gains the `naturalCycleSeconds` field (optional, only declared for presets with fixed cycles) and the `is_diagnostic` field (default false). Coefficients live in code (with documentation), not in JSON — coefficient tuning is a code change reviewed via tests.

---

## 10. Implementation sequence

All design dimensions locked. Subsystems V.7.6.1 → V.7.6.D shipped. Remaining work:

| Step | Increment | Scope | Estimated sessions |
|---|---|---|---|
| 1 | V.7.7 | **WORLD pillar — layer stack + mood palette + 1–2 background dewy webs.** Implement §4 in full: `arachneWorldTex` half-res render target, sky band + distant trees + mid-distance trees with bark + near-frame branches + forest floor + fog + light shafts + dust motes. Mood-driven palette per §4.3 (already specified, just plumbed through). 1–2 background dewy webs per §5.12 with refractive drops sampling `arachneWorldTex`. Foreground unchanged for now (still V.7.5 build code — refactored in V.7.8). Visual review against refs 06 / 15 / 16 / 17 / 18 + 01 / 03 / 04 via harness. | 3 |
| 2 | V.7.8 | **WEB pillar — foreground build refactor.** Implement §5.1–§5.11 in full: corrected biology (frame → radials → INWARD capture spiral → settle), chord-segment SDF, drop accretion during build, anchor-blob terminations on near-frame branches, completion signal at 60s. Pause on spider trigger; resume on spider fade. Per-segment spider cooldown. Visual review for build-pace feel and reference matching against 01 / 02 / 03 / 04 / 11. | 3 |
| 3 | V.7.9 | **SPIDER pillar — anatomy/material/lighting + whole-scene vibration + final polish + cert.** Implement §6 in full: cephalothorax + abdomen + 8 articulated legs with knee-bend IK + eye cluster + abdominal pattern + chitin material with thin-film + listening pose. Vibration model §8.2 applied to all webs + branches + spider. Final tuning of drop counts, brightness, sag magnitude, free-zone size, mood-smoothing window against references via harness. Cert review. | 2 |

**Total: 8 sessions of implementation work.** Realistic given Arachne's track record (V.7 alone took 3 sessions of mechanical work that didn't reach the bar). Each step includes harness-driven visual verification before commit; no more "build for a session, ship to Matt, discover at M7 that it's wrong."

**Order constraints:**
- V.7.7 must complete first — V.7.8's drop refraction depends on `arachneWorldTex`; V.7.8's anchor logic depends on near-frame branch positions from §4.2.4.
- V.7.9 should not start until V.7.7 + V.7.8 are visually approved — the vibration model and spider deepening only make sense once the WORLD and WEB read correctly.

**Each increment ends with:**
- Harness contact sheet rendered and committed under `/tmp/phosphene_visual/<ISO8601>/` and reviewed against named references.
- `PresetVisualReviewTests` golden hashes regenerated and committed.
- Test suite green, 0 SwiftLint violations on touched files.
- Matt runtime visual review pass.

---

## 11. Open questions

None blocking the spec. Items that may surface during implementation:

- **Mid-distance forest reference (P1).** The mid-distance fog/silhouette layer (§4.2.2 boundary into 4.2.3) would benefit from a moderate-fog forest reference between ref 06 (heavy fog) and a hypothetical clear forest. Implement V.7.7 against the refs we have; source the missing reference if §4.2.2 / §4.2.3 falloff reads wrong in harness review.

- **Time-lapse stills (P1).** V.7.8 implementation of §5.6 (capture spiral winding inward) would benefit from BBC Earth time-lapse stills showing the spiral mid-construction. The biology is grounded in §13 citations and is implementable without the photo refs; if V.7.8's harness review shows the spiral character is off, source stills then.

- **Foreground web → background migration animation.** When the foreground build completes, the in-progress / completed foreground web could either fade out cleanly or migrate to the background pool. Background-pool migration is more visually interesting (the webs accumulate over a session) but requires the next preset selection to know that Arachne is the next preset too. Punt to V.7.9 polish — start with clean fade.

- **What happens when bass eases mid-spider-pose.** Construction resumes immediately, or does the spider take a moment to depart first? Punt to V.7.9 polish — start with simultaneous fade-out + resume, refine if it reads wrong.

- **Drop hue shifts via vocal pitch.** Listed as optional in §7. Punt to V.7.9 polish — start without, add if the visual needs more variety.

- **Spider walking across web.** §6.3 specifies the gait but treats walking as rare. If runtime review finds the spider's resting pose monotonous during long sustained-bass passages, allow slow drift (one chord-width per ~3 seconds). Punt to V.7.9 polish.

---

## 12. Acceptance criteria

The Arachne v8 implementation is complete when:

1. **WORLD reads as a forest.** A viewer seeing only the WORLD pass (WEB and SPIDER suppressed) sees a layered, mood-tinted forest with depth — not a flat gradient. Six layers (sky / distant / mid-distance / near-frame / floor / atmosphere) all readable. Side-by-side with refs 06 / 15 / 16 / 17 / 18 / 07 via the harness contact sheet, reads as the same kind of place.

2. **Foreground build is visibly happening.** A viewer watching for 30 seconds sees radials extending and the spiral winding INWARD. Not a static finished web. Construction phases (frame → radials → spiral → settle) are individually identifiable.

3. **Background dewy webs are visible from frame zero.** The scene is never sparse, even at preset entry. Background webs read as photorealistic dewdrops side-by-side with refs 01 / 03 / 04 via the harness contact sheet.

4. **Drops are the visual hero.** A viewer's eye lands on drops first, threads second. Drops show: refraction inverting the WORLD through them, fresnel rim, sharp specular pinpoint, dark edge ring. Not abstract circles.

5. **Anchor structure reads as solid.** The web's outer frame visibly meets near-frame branches at small adhesive blobs. The polygon of anchors is irregular, not a circle. Side-by-side with ref 11.

6. **Spider, when present, is detailed.** A viewer can see cephalothorax, abdomen, 8 legs with visible knee bends, eye cluster, abdominal pattern. Material reads as biological iridescent chitin (ref 14), not neon (ref 10). Listening pose visibly fires on sustained bass.

7. **Web vibration is visible during heavy bass.** Whole-scene tremor with audio-rate (~12 Hz) frequency. Background webs + foreground web + near-frame branches + spider all participate. Forest floor and distant layers don't shake.

8. **Build cycle completes in ≤ 60s** under typical music. Completion event triggers immediate transition out per V.7.6.2 infrastructure.

9. **Matt M7 review against references.** No anti-ref `09` (clipart symmetry) or `10` (neon glow) match. Refs `01`, `03`, `04`, `05`, `06`, `08`, `11`, `12`, `15`, `16` cited as reachable.

10. **Pure black at silence.** When `totalStemEnergy == 0` and mood signal is below silence threshold, scene clears to deliberate black with WEB drops + threads visible against black. No styled darkness.

---

## 13. Citations and grounding

This spec is grounded in research conducted 2026-05-02 and 2026-05-03; key sources:

- **Web construction biology.** Foelix, R. F. (2011), *Biology of Spiders* (3rd ed., Oxford University Press), ch. 6 "Webs and Web-building". Eberhard, W. G. (1990), "Function and phylogeny of spider webs." *Annual Review of Ecology and Systematics* 21, 341–372. [British Arachnological Society — Orb Web Construction](https://britishspiders.org.uk/orb-webs). [Patterns in movement sequences of spider web construction (ScienceDirect)](https://www.sciencedirect.com/science/article/pii/S0960982221013221). The capture-spiral-winds-inward direction, alternating-pair radial order, and irregular polygon frame are all canonical.
- **Time-lapse footage as visual target.** [BBC Earth — Beautiful Spider Web Build Time-lapse](https://www.youtube.com/watch?v=zNtSAQHNONo). [Spider Spinning Its Web — Time Lapse](https://www.youtube.com/watch?v=rBPyX5Yq6Y0). The construction process is the visual subject, not the finished surface.
- **Drop physics.** [Plateau-Rayleigh instability (Wikipedia)](https://en.wikipedia.org/wiki/Plateau%E2%80%93Rayleigh_instability). [In-drop capillary spooling of spider capture thread (PNAS)](https://www.pnas.org/doi/10.1073/pnas.1602451113). Drops are uniform-spaced via a physical instability, not random — this is the source of the ±5% spacing-jitter rule (V.7.5's ±25% was wrong).
- **Real-time rendering technique.** [NVIDIA GPU Gems 2 ch.19 — Generic Refraction Simulation](https://developer.nvidia.com/gpugems/gpugems2/part-ii-shading-lighting-and-shadows/chapter-19-generic-refraction-simulation). [Tympanus Codrops Rain & Water Effect](https://tympanus.net/codrops/2015/11/04/rain-water-effect-experiments/). [Slomp 2011 — Photorealistic real-time rendering of spherical raindrops](https://onlinelibrary.wiley.com/doi/10.1002/cav.421). Standard industry technique for the §5.8 drop recipe: background-to-texture + drop-as-quad + screen-space refraction.
- **Spider locomotion (for §6.3 gait).** [Biomechanics of octopedal locomotion (J Exp Biol)](https://journals.biologists.com/jeb/article/214/20/3433/10466/Biomechanics-of-octopedal-locomotion-kinematic-and). [Arachnid locomotion (Wikipedia)](https://en.wikipedia.org/wiki/Arachnid_locomotion). Alternating-tetrapod gait already implemented in `StalkerGait.swift`; reuse.
- **Procedural generation prior art.** [Konstantin Magnus — procegen / Spider Web](https://procegen.konstantinmagnus.de/spider-web). [Houdini Vellum Spider Web (Lesterbanks)](https://lesterbanks.com/2018/12/create-spider-web-houdini-vellum/). The parabolic sag formula `y -= u*(1-u)*amount*length` is the canonical industry choice.

---

## 14. Reference set status

**Curated and committed (refs 01–10, 11–19, 19 entries total).** Annotated in `docs/VISUAL_REFERENCES/arachne/README.md`. Compression to ≤500 KB pending for refs 11–19.

**P1 enrichment (not blocking implementation).**
- Mid-distance forest reference (moderate fog, between ref 06 and a clearer variant) — would refine §4.2.2 / §4.2.3 falloff. Source if V.7.7 harness review shows the boundary reads wrong.
- Time-lapse still: radials laid, no spiral yet — would anchor §5.5 visual review. Source if V.7.8 harness review shows the radials phase reads wrong.
- Time-lapse still: capture spiral mid-construction — would anchor §5.6 visual review of the inward winding character. Source if V.7.8 harness review shows the spiral phase reads wrong.

**Dropped 2026-05-03.**
- Anchor-to-bark macro (formerly P0-#1). Real orb-weaver webs anchor to twigs / leaves / grass stems more often than bark; ref 11 covers polygon-of-anchors context at the right scale. Removing this requirement is also the reason §5.9 relaxes the bark-thickness assumption.

---

**This spec supersedes the 2026-05-02 draft. Implementation begins at V.7.7 once Matt signs off.**
