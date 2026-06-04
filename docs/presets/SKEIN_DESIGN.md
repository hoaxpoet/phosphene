# Skein — drip / pour painting preset

**Working name:** *Skein* (a "skein" is the art-historical term for Pollock's tangled drip lines — single-word, house style, captures the thread-tangle quality). Provisional; your call.
**Lineage:** Pollock's pour/drip technique; *Full Fathom Five* as the hero. (The Tempest reference — "full fathom five thy father lies… those are pearls that were his eyes" — is a nice latent theme: the canvas is a thing that *accumulates and transforms* what falls into it.)
**Family:** `painterly` / `generative` (new family, or fold under an existing abstract family — see §8).

---

## 0. Verdict

**Feasible today with localised additions. No blocking renderer gaps. Not a new render paradigm.**

Skein is a **persistent paint canvas**: a feedback buffer that *accumulates* marks instead of decaying them, with new paint composited alpha-over each frame and the camera looking straight down at the result. This is architecturally a **sibling of Dragon Bloom** — the `passes: ["direct", "mv_warp"]` brush-accumulated-through-feedback pattern (D-135 / D-138) — with two changes: the warp is set to **identity** (paint doesn't move once it lands) and decay is **off** (paint persists). The "draw new geometry normal-alpha on top of the accumulated frame" mechanism Skein needs is the exact strands-on-top loop Dragon Bloom already ships.

The spine of the design, and the reason it fits Phosphene's first principle so cleanly:

> **Continuous energy pours the lines (primary). Beats flick the splatters (accent).**
> The long curving drip lines — the dominant Pollock mark — are a continuous pour traced by a moving "painter." The droplet bursts are transient accents on onsets. This is the *continuous-energy-primary / beat-onset-accent* policy made literal.

Everything else hangs off three axes: **who** is playing (stem → paint colour), **how much / when** (energy deviation pours; onsets flick), and **what character** (spectral centroid → paint viscosity → mark morphology).

---

## 1. Creative architecture — "painting the music"

The goal is a canvas a listener can *read*: see the snare in the flicks, feel the bass in the heavy pools, watch the melody draw the long lines. A faithful trace, deterministic given the audio — not a random splatter screensaver. Same song twice → recognisably the same painting; two different songs → visibly different paintings. (Seed from the track's SHA-256 — we already key `PersistentStemCache` that way, so a track always seeds the same canvas.)

### 1.1 The painter is a member of the band

There is a single moving emission locus — the "painter" (Pollock circling the canvas). Its trajectory is the gesture, and the gesture is what makes the result read as *performed* rather than *metered*:

- **Base wander:** an ergodic path (curl-noise flow field, or a sum of incommensurate sinusoids) that covers the canvas evenly over time — the *allover* composition with no focal point. Seeded per track.
- **Speed along the path** ∝ arousal + broadband energy deviation. Vigorous music → fast movement → a denser, more energetic web. A sparse passage → slow, deliberate marks.
- **Local character** ∝ high-band energy / onset density. Busy hi-hats → jittery, scratchy local movement; sustained pads → smooth long arcs.
- **Anticipation (the wind-up):** on a strong *predicted* beat, the painter coils slightly against its direction of travel on the rising edge of `beatPhase01`, then releases into a flick on the beat. This is the same anticipation idea as Drift Motes' shaft-pulse, and it uses the authoritative beat-phase clock rather than raw onset (FA #33 — onset has jitter; phase is the motion source). The wind-up is what sells "the painter threw that," not "a meter twitched."
- **Rest:** at low energy the painter slows, hovers, lets a drip or two fall, and waits. Quiet passages should feel like the painter *listening*.

### 1.2 The three-axis mapping

| Axis | Musical input | Visual consequence |
|---|---|---|
| **Who** (which voice) | stem identity | which **paint colour** is flowing right now |
| **When / how much** | energy deviation (primary) + onset pulses (accent) | **continuous pour** draws the lines; **splatter bursts** punctuate beats |
| **Character** | spectral centroid, attack sharpness (MV-3a) | **viscosity / mark morphology**: thin-fast-fine vs thick-slow-gloopy; sharp-flick vs soft-pour |

**Who → colour (your stem idea, the core colour logic).** Each stem owns a paint — a stable, distinct, identifiable colour. When the mix is drum-heavy the canvas goes drum-colour-dominant; when vocals soar, the vocal colour leads. The canvas's *colour balance at any instant mirrors the stem balance of the mix*, and its *colour history over the song mirrors the arrangement's history* — you can read the arrangement in the layering. **The binding constraint is legibility, not specific hues: one stable, well-separated colour per stem.** The palette itself is open — Skein is *inspired by* drip painting, not limited to any one artist's palette — and is a tunable, free to be wide and saturated. Valence shifts the palette's warmth/saturation and arousal its vigour, across whatever gamut a palette defines.

One example palette (the *Full Fathom Five* register — illustrative, not a default or a constraint):

- **Drums / percussion → near-black.** The flicks and the sharp skeletal web lines.
- **Bass → deep teal / dark green-blue.** The heavy, slow pools — weighty paint for a weighty voice.
- **Vocals → warm cream / ochre-gold.** The most expressive voice gets the long flowing pours — the melodic line literally drawn.
- **Harmonic / other → muted sienna / rust.** Mid-density connective texture.
- **Base canvas → warm off-white (raw, unprimed canvas cream)**, not pure white. The ground stays light whatever the palette, so marks and the wet edge always read against negative space.

**When → emission (the spine).** Two emission channels:

- *Continuous-pour channel* (PRIMARY): paint streams from the moving painter, drawing a continuous line. Width ∝ flow / speed (fast move at fixed flow → thinner line; lingering → pooling). Driven by continuous per-stem energy **deviation** (D-026), never absolute level. This is the long curving skein.
- *Transient-splatter channel* (ACCENT): on an onset, a burst of droplets radiates from the current painter position. Driven by the onset pulse for that stem's band. Sharp transient → tight, fast, fine spray; soft onset → loose, larger droplets.

**Character → viscosity.** Spectral centroid (per stem) sets how the paint behaves: bright/airy → thin, fast, finely dispersing paint (delicate filigree, many fine satellites, slightly translucent so underpaint reads through — low alpha); dark/heavy → thick, gloopy paint (heavy pools, fat lines, fewer-but-bigger droplets, fully opaque — alpha 1). This makes the *texture* of the marks musical, beyond their colour and timing.

### 1.3 Slow global modulators

- **Mood.** Valence → palette warmth/saturation (high → warmer, more saturated; low → cooler, more restrained); arousal → overall vigour/density (more paint, faster painter). A wider, more saturated gamut gives this axis more headroom to travel. This matches the existing restrained-baseline ↔ saturated-peak palette convention (saturation tracks energy/arousal; warmth tracks valence). Smooth valence/arousal in preset state — never write them through `setFeatures` (FA #25).
- **Structure.** On section boundaries (`StructuralPrediction`), shift palette emphasis and pour density. Two flavours, see §8: *allover* (sections distinguished by colour/density-over-time only — Pollock-pure) vs *structural cartography* (sections softly bias the painter's region, so repeated choruses revisit the same patch and build visible density clusters — the canvas layout becomes a map of the song's form). Recommended default: a **subtle** regional bias that preserves overall allover-ness — a painter who returns to motifs is more of a performer than a random walker.

### 1.4 The canvas as a temporal integral

This is the idea worth protecting. Unlike a transient-frame visualiser, Skein's canvas is a *record* — paint lands and stays. The finished canvas is the song's visual fingerprint:

- A sparse ballad → open, mostly-white canvas, a few delicate lines.
- A dense banger → saturated, fully-worked allover web.
- A quiet-verse / explosive-chorus song → calm where the verse was painted, violent where the chorus hit (especially under the structural-cartography variant).

**Wet-now / dry-past — the legibility device.** Freshly-landed paint glistens (a wet specular highlight); older paint is matte. So the eye is drawn to the *now* of the music (wet = the current moment) while the matte accumulation reads as the musical *past*. The painting becomes legibly temporal. Mechanism: a separate decaying "wetness" channel (§5).

### 1.5 Silence and track change as performance beats

- **Silence:** energy-deviation goes quiet → the painter stops emitting and rests; `accumulated_audio_time` pauses so any slow drift pauses with it; the last wet marks slowly dry to matte. The canvas holds — the painting-so-far. Notably this is an *easy* silence behaviour: a white-canvas paint preset is bright by construction, so `silence-non-black` (D-037) is satisfied with no collapse choreography. Compare Ferrofluid's full-silence collapse — Skein's silence is just the painter pausing, which is both simpler and more poetic.
- **Track change:** canvas + wetness reset to fresh cream; painter re-seeds from the new track's hash; a fresh painting begins. A brief intentional wipe-to-fresh-canvas (short fade-through-cream) rather than an instant pop. Reset hooks already exist (`resetAccumulatedAudioTime`, per-preset `State.reset`).

---

## 2. Reference trait matrix (Gate 1)

To be finalised against the locked reference set (§7 gating); extracted from drip painting broadly (*Full Fathom Five* as the seed example) and the pour technique:

| Trait class | Traits |
|---|---|
| **Macro composition** | Allover, edge-to-edge, no focal point; rectangular field; layered depth from overlapping skeins; coverage ranges with the music (open for sparse passages, fully-worked for dense ones) but the resting state keeps negative space so the ground reads through. |
| **Meso structure** | Long looping curvilinear lines that double back; pools where the pour lingered; halos of satellite droplets around lines and at flick points; thin connecting filaments/threads. |
| **Micro detail** | Fine satellite spatter (dense near a mark, sparse far); ragged organic mark edges (not clean circles); thread tendrils; slight bleed/feathering at edges of thin paint. |
| **Material** | Matte-to-glossy enamel/house paint; wet paint glistens, dry paint is flat; opaque thick paint occludes, thin paint is semi-translucent; subtle canvas-weave texture beneath. |
| **Lighting** | Flat overhead illumination; the only specular event is *wet* paint catching light; no dramatic directional shadows (it's a flat field viewed head-on). |
| **Motion** | New paint *arrives* (the act of landing); accumulation only grows; no global motion of laid paint; the live edge is wherever the painter currently is. |
| **Audio-reactive** | Continuous pour ← energy deviation (primary); splatter ← onsets (accent); colour ← stem identity; viscosity ← centroid; vigour/density ← arousal; palette ← valence; section shifts ← structural prediction; painter wind-up ← beat phase. |
| **Failure modes** | (a) Over-covering to a dead mat (no negative space left, marks and the wet edge no longer legible) — let coverage range with the music, keep the resting state open, and composite opaque-overwrite (not additive) so layers occlude rather than average to brown. (b) Reading as a *particle fountain* (droplets that look like sci-fi sparks, not paint) — mark morphology + matte material is the whole game. (c) Random / un-musical splatter — the trace must be legible. (d) Twitchy meter feel — fix with gesture easing + anticipation. (e) A *resting* state that fills the canvas solid — tune emission so quiet passages stay open and only dense passages approach full. |
| **Anti-references** (author before coding) | Neon/sci-fi particle burst; clean geometric polka-dots; a literal paintbrush stroke (no brush ever touches — pour/drip only); an over-covered, overworked dead mat with no negative space; symmetric/kaleidoscopic layout (drip painting is asymmetric, allover). |

---

## 3. Renderer capability audit (Gate 2)

| Required primitive | Registry status | Source / note |
|---|---|---|
| Persistent cross-frame accumulation buffer | **Supported** | Feedback ping-pong (`RenderPipeline+FeedbackDraw.swift`); mv_warp family (`RenderPipeline+MVWarp.swift`). |
| Draw new marks normal-alpha **on top of** the accumulated frame | **Supported** | mv_warp "waves on top" / strands-on-top branch (`drawWithMVWarp`, `RenderPipeline+SceneGeometry.swift`) — D-138. Exactly Dragon Bloom's mechanism. |
| Feedback with **no decay** (paint persists) | **Supported** | No-decay custom-warp path (`decayMul=1`) — D-138. |
| **Identity** warp (paint doesn't move once laid) | **Localised addition** | The simplest possible warp mode; cheaper than any existing warp. New "canvas-hold" mode in the mv_warp family (or use the plain `feedback` path with identity + no decay). |
| 2D SDF marks (capsules for pour lines, discs for droplets, thin caps for filaments) | **Supported** | 2D SDF utility library, 30 `sd_*` primitives + booleans/modifiers (`Utilities/Geometry/`). |
| Wet-sheen specular + matte-dry distinction | **Supported (math)** + **localised addition (channel)** | PBR/GGX specular utilities exist; needs a wetness channel to drive it (§5). |
| ACES tone-map / optional bloom for wet sparkle | **Supported** | `PostProcessChain` + `Shaders/PostProcess.metal`. |
| Per-preset Swift-side state (painter trajectory, pools, seed) | **Supported** | Established pattern — `ArachneState`, `GossamerState`, `StalkerState`. |
| Continuous band energy (instant + attenuated, 3/6-band) | **Supported** | `BandEnergyProcessor` → FeatureVector floats 1–24. Primary driver. |
| AGC deviation primitives (`xRel`, `xDev`, `xAttRel`) | **Supported** | FeatureVector 26–34 / StemFeatures 17–24 — D-026, MV-1. Required style. |
| Per-stem energy + deviation | **Supported** | StemFeatures 1–24. |
| Per-stem centroid / attackRatio / onsetRate | **Supported** | StemAnalyzer → StemFeatures 25–40 (MV-3a). Drives viscosity + flick sharpness. |
| Onset pulses (per-band + composite) | **Supported** | `BeatDetector` → OnsetPulses. Accent-only — fits the splatter channel exactly. |
| Beat-phase clock (`beatPhase01`, `beatsUntilNext`) | **Supported** | `LiveBeatDriftTracker` + offline `BeatGrid`. For the painter wind-up. |
| Mood (valence / arousal) | **Supported** | `MoodClassifier` → `setMood`. Smooth in state (FA #25). |
| Structural prediction (section boundaries) | **Supported** | `StructuralAnalyzer` / `NoveltyDetector` → `StructuralPrediction`. |
| Stem warmup blend (first ~10 s) | **Supported** | `smoothstep(0.02,0.06,totalStemEnergy)` — D-019. Mandatory. |
| `accumulated_audio_time` (pauses at silence) | **Supported** | FeatureVector float 25. |
| Track-change reset hook | **Supported** | `resetAccumulatedAudioTime`, per-preset `State.reset`. |

**Nothing Skein needs is in the hard "Missing" column.** The only non-trivial primitives — persistent accumulation and draw-on-top — are *Supported* and *shipping in Dragon Bloom*.

---

## 4. Gap report (Gate 3)

| Delta | Classification | Notes |
|---|---|---|
| **Canvas-hold warp mode** (identity transform, decay off) | **High** (not blocking) | Smallest possible addition to the mv_warp family. Or reuse the plain `feedback` path. Either way it's a configuration of existing machinery, not a new paradigm. |
| **Wetness ping-pong channel** (single-channel r8/r16; stamp to 1 where paint lands, decay toward 0) | **High** (not blocking) | Tiny. Drives the wet-now/dry-past sheen. First thing to cut if budget is tight (V2). |
| **Mark-stamp fragment shader** (pour capsule + splatter discs + filaments, alpha-over, viscosity-shaped) | **Nice-to-have infra; core preset code** | This is preset shader code — the "scene geometry" drawn on top, like Dragon Bloom's strands. No engine change. **This is where the aesthetic risk lives** (Pollock vs particle-fountain). |
| **Display / lighting pass** (read canvas + wetness → wet specular, matte-dry, optional canvas grain → ACES + bloom) | **Nice-to-have** | Can extend the mv_warp blit (already does display-only effects) to sample wetness, or a small staged composite. |
| **Painter trajectory state** (Swift) | **Not needed** (already supported) | Established `*State.swift` pattern. |
| **Canvas + wetness clear on reset** | **Not needed** (already supported) | Reset hooks exist; just clear two textures. |

**No Blocking gaps.** Classification verdict: *buildable today with localised additions.* The engine investment is one small warp mode + one tiny buffer; the rest is preset authoring.

---

## 5. Rendering architecture contract (Gate 4)

### 5.1 Paradigm and the D-029 question

**This is a single render paradigm: 2D-fragment marks accumulated through feedback.** All mark geometry (pour capsules, droplet discs, filaments) is 2D SDF compositing; the canvas is feedback. There is no second paradigm — no ray-march scene, no particle render, no mesh. This is precisely what Dragon Bloom is (polar-waveform brush accumulated through feedback, D-135). The `passes: ["direct", "mv_warp"]` combination is the **established expression** of "brush accumulated through feedback" and is explicitly *not* paradigm-stacking. So **D-029 is satisfied** — Skein is a sibling of Dragon Bloom, not a Frankenstein. Worth a one-line D-### note ratifying "canvas-hold accumulation is the no-decay/identity configuration of the mv_warp brush-on-feedback paradigm" so the precedent is on the record.

### 5.2 Per-frame pass structure

```
1. CANVAS HOLD        identity warp, no decay → copy prev canvas to current
                      (under identity + no-decay there is no resampling, so this
                       is lossless; see 5.5)
2. MARK STAMP         draw this frame's NEW marks normal-alpha onto the canvas:
                        • pour: swept capsule from painter_prev → painter_now
                        • splatter (on onset frames): N droplet discs at
                          velocity-biased radial offsets + thin filaments
                        • viscosity (centroid) shapes width / satellite count /
                          alpha / edge raggedness
                      scissor the pass to the bounding box of this frame's marks
                      → cost ∝ new marks, NOT total marks
3. WETNESS            stamp wetness=1 where step 2 painted; multiply prev wetness
                      by ~0.99/frame (decay pauses at silence)
4. DISPLAY/LIGHTING   read canvas + wetness:
                        • wet regions → GGX specular highlight (overhead light)
                        • dry regions → matte, slight desaturation
                        • optional subtle canvas-weave grain
                      → ACES tonemap (+ optional bloom on wet specular)
```

Painter state advances on the CPU/Swift side each frame (trajectory + technique mode + per-stem flow accumulators + seed), like `ArachneState`.

### 5.3 State model

- **Canvas** — ping-pong texture, the permanent paint record. Marks composited once on landing; otherwise copied identity. *Not* destructively modified after a mark lands (drying is a read-time effect, see 5.5).
- **Wetness** — ping-pong single-channel, transient.
- **PainterState** (Swift) — position, velocity, phase along base path, current technique (pour/flick), per-stem flow integrators, anticipation coil, `rng_seed` (track SHA-256).
- **Reset** — on track change, clear canvas to cream + wetness to 0, re-seed painter.

### 5.4 Audio routing (one primitive per visual layer — `feedback_audio_layer_one_primitive`; all deviation-normalised — D-026)

| Visual layer | Single audio primitive | Channel |
|---|---|---|
| Pour flow rate (per stem colour) | that stem's energy **deviation** (`stem.xRel`/`xAttRel`) | primary / continuous |
| Painter speed | broadband energy deviation + arousal | primary / continuous |
| Painter local jitter | high-band energy / onset rate | primary / continuous |
| Painter wind-up & flick timing | `beatPhase01` | anticipation (phase, not onset) |
| Splatter burst intensity | onset pulse for that stem's band | accent |
| Paint viscosity → mark morphology | that stem's spectral **centroid** | character |
| Flick sharpness (spray tightness) | that stem's **attackRatio** | character |
| Paint colour selection | stem identity | structural |
| Palette warmth / saturation | valence / arousal (smoothed in state) | slow global |
| Section palette / density shift | `StructuralPrediction` boundary | slow global |
| Vocal-line hue/position nuance (optional) | vocals pitch (YIN) | character |

Mandatory: stem warmup blend (D-019) on everything reading `stems.*`.

### 5.5 Why 8-bit is fine (but soak-verify)

Feedback drift comes from per-frame **resampling** — the warp's bilinear interpolation slowly degrading the image. **Identity warp does no resampling**: an unpainted texel is copied byte-identical, frame after frame. With no decay either, the canvas is *lossless* persistence, and 8-bit is perfectly stable — arguably more stable than a float buffer (Dragon Bloom found float over-accumulates; the 8-bit clamp is load-bearing there). The one caveat: if drying were a *destructive per-frame multiply* on painted texels it would quantise/drift — which is exactly why drying lives in the separate wetness channel and is applied at *read time*, leaving the canvas untouched. **Decision: 8-bit canvas, identity hold, drying as a read-time lighting effect.** Still run a multi-hour `SoakTestHarness` pass before certification — long-duration accumulation is precisely the class of thing that surprises you, and the project rule is verify-don't-assume. (16-bit canvas is the fallback if soak surfaces banding in subtle thin-paint layering; trivial format swap.)

### 5.6 Diagnostic / debug views

- Painter trajectory overlay (path + current position + velocity vector + anticipation coil state).
- Per-stem emission heatmap (where each colour is landing).
- Wetness buffer visualised directly.
- Coverage meter (% canvas painted — assert it lands in the 60–80 % band on a typical fixture).
- Per-frame new-mark count (governor input).

### 5.7 Acceptance criteria (Gate 6 preview)

- **Silence-non-black** (D-037): trivially passes (cream canvas + paint is bright).
- **Beat ratio**: splatter density on a beat-heavy fixture measurably exceeds the steady fixture.
- **Determinism**: same track + same seed → dHash-stable final canvas (within tolerance) across two runs. This is a *headline* acceptance property for Skein, not just a regression nicety.
- **Coverage bound**: typical track ends at 60–80 % coverage (never fully covered, never near-empty on a dense track).
- **Anti-reference rejection**: final canvas must not read as neon-particle-burst / clean-polka-dot / muddy-saturated / kaleidoscopic-symmetric. (The automated anti-reference dHash gate is itself a *Missing* engine capability — same gap Arachne has — so this stays an M7 manual judgement until that lands.)
- **Performance**: 60 fps at 1080p, M1 included (see §6).
- **M7**: Matt, live, on real music across ≥5 tracks + a local file — the bloom-must-dance / Pollock-must-read perceptual gate. Non-negotiable, non-bypassable.

---

## 6. Performance

Skein is a **light** preset, lighter than Dragon Bloom:

- The canvas-hold copy is an identity blit (or skip the copy and accumulate in place with a read/write hazard barrier).
- The mark-stamp pass is **scissored to this frame's marks** — its cost is proportional to *new marks this frame*, not total marks ever laid. This is the key efficiency of bake-into-canvas: every past mark is amortised into stored pixels. A live-particle approach (re-rendering every droplet every frame) would get more expensive as the painting fills; Skein gets *no more expensive*.
- On non-burst frames it's one swept capsule. On onset frames, N droplet discs (cap N ≈ 64) evaluated only over their local bounding box.
- No ray-march, no particle physics, no mesh, no SSGI.

Governor hooks: cap splatter droplet count N (analogous to `activeParticleFraction` / `densityMultiplier`); drop the optional bloom-on-wet-specular at `.noBloom`; the wetness pass and canvas grain are first to shed under budget. ACES composite always runs.

---

## 7. Phased implementation sketch (Gate 5)

Increment IDs in house style (`Skein.N`), small commits per logical concern (`[Skein.N] <component>: <desc>`), push after each increment's verification passes. **Infra patches land in their own `.x` increment before the next preset increment opens.**

- **Skein.1 — reference lock (gating).** Populate the visual references folder (`NN_<scale>_<descriptor>.(jpg|png)`, ≤500 KB, `CheckVisualReferences` green) + README distinguishing trustworthy traits from any AIGEN confabulation (`_AIGEN` suffix, D-065(c) "actively disregard" annotations) + anti-references (§2). **Per D-064 / the development protocol, no Skein.2+ session prompt can be written until this folder exists.** This is doc-only; it's the coarse-to-fine gate.
- **Skein.2 — canvas + pour spike.** Canvas-hold warp mode + a single white pour line traced by a hard-coded wandering painter, accumulating, no audio yet. Gate-before-the-gate: if a persistent skein doesn't *hold and read as paint*, stop. Harness contact sheet.
- **Skein.3 — splatter morphology.** Add droplet bursts + filaments + viscosity shaping; tune until a still frame reads as Pollock, not particle-fountain. Highest aesthetic risk — expect iteration here (cf. Dragon Bloom "not seeing petals", Arachne clipart).
- **Skein.4 — stem palette + emission routing.** Wire the §5.4 routing: stem→colour, energy-deviation→pour, onset→splatter, centroid→viscosity. Stem warmup (D-019). PresetSessionReplay registration.
- **Skein.5 — wet/dry sheen.** Wetness channel + display/lighting pass. (Cuttable to V2.)
- **Skein.6 — mood + structure.** Valence/arousal palette, structural section shifts, painter anticipation (`beatPhase01`).
- **Skein.7 — certification.** Soak test (§5.5), acceptance invariants (§5.7), golden dHash + determinism gate, then Matt M7 on live music.

---

## 8. Open decisions for you

Each with my recommendation — flagging the genuine product calls, not dumping options:

1. **Allover vs structural cartography.** *Recommend:* subtle structural bias (sections softly lean the painter's region; choruses revisit and build density) — preserves allover-ness while letting the canvas layout encode song form. Pure allover if you want maximum Pollock fidelity over musical legibility.
2. **Wet sheen in V1 or V2.** *Recommend:* V1 if budget allows — the wet-now/dry-past read is the single best legibility device. It's also the cleanest thing to defer if Skein.3 eats the schedule.
3. **Visible painter locus.** A faint luminous "pour point" hovering above the canvas, trackable by eye. *Recommend:* optional, off by default — it makes the "member of the band" performer legible (on-brand) but risks looking like a cursor. Try it in Skein.6, keep behind a flag.
4. **In-flight paint.** A brief motion-blur streak resolving into the landed mark, suggesting paint thrown from above. *Recommend:* defer to V2 — nice depth cue, not load-bearing, and the flat head-on view is true to viewing a Pollock.
5. **Canvas-hold mode vs reuse plain `feedback`.** *Recommend:* add the explicit canvas-hold mode to the mv_warp family — keeps Skein a clean sibling of Dragon Bloom and the precedent legible, vs. overloading the narrower `feedback` (Membrane) path.
6. **Family / name.** New `painterly` family vs folding under an abstract family; "Skein" vs your pick.
7. **8-bit vs 16-bit canvas.** *Recommend:* 8-bit (§5.5), revisit only if soak surfaces banding.

---

### One-line feasibility summary for the queue

> Skein is buildable now with two small engine additions (a canvas-hold warp mode + a wetness channel) on top of the Supported feedback / strands-on-top / ping-pong machinery; it's a single paradigm precedented by Dragon Bloom (`direct + mv_warp`), it's lighter than Dragon Bloom on the GPU, and its silence and determinism stories are unusually clean. The real work and the real risk are in Skein.3 — making the splatter morphology read as poured paint, not particles.
