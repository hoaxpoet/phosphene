# Ricercar — contrapuntal visual-music painting preset

**Working name:** Ricercar (Baroque antecedent of the fugue; Italian *ricercare*, "to seek out" — the contrapuntal lineage plus the generative, searching quality of the canvas). Provisional; alternatives in §9. Runners-up: **Stretto** (overlapping voice-entries in tight imitation), **Cantus** (the singing line).

**Lineage:** Visual music / abstract animation — Oskar Fischinger, the Whitneys, Len Lye, Norman McLaren; the "color organ" tradition of translating music to abstract colour and motion. Ricercar adopts the *spirit and technique* (music painting itself in abstract colour and line), **not** the literal imagery of the 1940 *Fantasia* segment (§2). Showcased with Bach, Toccata & Fugue in D minor, BWV 565 (Stokowski orchestral transcription = the *Fantasia* performance), but built as a reusable preset.

**Family:** painterly / generative (sibling of [Skein](SKEIN_DESIGN.md); see §9).

---

## 0. Verdict

**Feasible today with no new audio/feature primitives and one bounded, audited engine touch.** Ricercar is assembled from two already-certified stacks:

- **Skein's canvas-hold mv_warp** (D-142 / D-143 / D-149): a feedback canvas that accumulates colour, marks-on-top overlay geometry, per-track FNV-1a seed (`lumenTrackSeedHash`). Ricercar reuses this with one deliberate fork from Skein — instead of identity warp + no decay (Skein's permanent drip record), Ricercar uses a **gentle curl-noise flow warp + slow decay** so held colour advects, merges, and breathes (§1.4).
- **Filigree's compute-agent trails** (PHYS.x, certified): N agents that move, steer, and deposit pigment into a ping-ponged trail texture (~0.66 ms/frame @1080p). Ricercar uses a small set (≤8) as its contrapuntal **voices**.

### The one integration — AUDITED, scope confirmed (2026-06-29)

Each stack is certified separately. Ricercar needs the agent layer to deposit into the mv_warp canvas so voice-trails join the flowing field. A pre-design audit (the analogue of the Skein.ENGINE.1 config audit, D-142) read the actual renderer and resolved this to **(B) a bounded engine touch — NOT pure config**:

- Skein's mv_warp canvas (`MVWarpState` ping-pong) and Filigree's agent trail (`PhysarumGeometry`'s private `r16Float` pair) are **isolated texture memories**.
- The render loop assumes particle-mode presets draw **straight to the drawable** and *skips feedback-texture allocation entirely* when `particles != nil` ([`RenderPipeline+Draw.swift`](../../PhospheneEngine/Sources/Renderer/RenderPipeline+Draw.swift) ~line 113, the CLEAN.4.4 comment). So agents cannot deposit into the warp canvas today — there is no shared texture.
- Registry confirms: composing feedback canvas + agent deposit = **Missing** ([RENDER_CAPABILITY_REGISTRY.md](../ENGINE/RENDER_CAPABILITY_REGISTRY.md)).

**The fix is small and named** (~60 lines, zero shader/kernel changes):
- `ParticleGeometry` protocol gains `rendersToFeedbackTexture: Bool` (`false` for Murmuration, `true` for Filigree-as-voice).
- `RenderPipeline+Draw.swift` routes particle render → the current feedback texture (instead of the drawable) when `mvWarpActive && rendersToFeedbackTexture`, then falls through to the existing `.mvWarp` warp/compose/blit.
- `PhysarumGeometry` sets the flag.

This lands as its own infra increment, **Ricercar.3.x**, surfaced to Matt before proceeding (per protocol). The alternative — Filigree re-writing its agents to output to a user-managed texture — is the wrong direction (violates the `PhysarumGeometry`-sibling design, FILIGREE_DESIGN §11) and is rejected.

> **Correction note (vs the original pitch):** the pitch's "zero new engine surfaces for V1" / "one open question to confirm" is **falsified** — the integration is *confirmed needed*, not open. It is bounded and scoped, not an open-ended gamble. Everything downstream of the bridge is pure preset config.

### The spine (against Phosphene's first principle)

> Continuous register energy raises and steers the voices (**primary**). Onsets announce entries and flick accents (**accent**).

Each orchestral register is a *voice* — an independent line of colour that wakes when its register sings, weaves a path while it sustains, and fades when it falls silent. The number of voices weaving at any instant tracks how many registers are sounding. This is the continuous-energy-primary / onset-accent policy (CLAUDE.md §Audio Data Hierarchy) made into counterpoint.

Three axes: **who** is playing (register → orchestral section → colour identity), **when / how much** (energy deviation steers; onsets announce), **what character** (spectral centroid → line crispness; mood → palette).

### The honest caveat (see §6)

Phosphene cannot separate individual orchestral instruments — Open-Unmix yields only vocals/drums/bass/other, all of which collapse to "other" on an orchestral recording. Ricercar therefore **does not transcribe instruments**. It evokes counterpoint through register-banded voice-agents and onset-driven entries. On the target piece this reads true because register density and voice count move together. It is an evocation, not a transcription, and the design never claims otherwise.

---

## 1. Creative architecture — "the orchestra paints itself"

The goal is a canvas a listener can read as counterpoint: watch a low voice enter and weave, hear a second line answer in a brighter register and see a second colour braid in, feel the coda's full chords as every voice converges into one massed gesture. Abstract, painterly, flowing — Fischinger's visual music, not a literal *Fantasia* redraw. **Generative but stable per play** (Matt, 2026-06-29): the same recording always paints the same painting (per-track FNV-1a seed — the Skein/Lumen-Mosaic identity), so it can be tuned and certified; two recordings paint visibly different paintings.

### 1.0 Visual music, grounded — the tradition Ricercar simulates

Cite this section in Ricercar.N sessions rather than reaching for memory.

1. **The line is the voice — counterpoint is the subject.** *Fantasia*'s Bach opener works because it gives the music's own layered, interweaving lines a visual body ("animated lines, shapes and cloud formations," "lacy figures cometing through space, a sky-writing cipher tracing patterns"). Fischinger's prior abstract films are built from discrete moving elements each tied to a musical line, not one undifferentiated field. → Ricercar's headline subject is a small set of independent lines (the **voices**, §1.1), each owned by a register; the flowing colour substrate (§1.4) is the ground they're drawn on.
2. **Colour is identity, assigned — not arbitrary.** In the color-organ tradition (Rimington, Scriabin's *Prometheus*, Fischinger's Lumigraph) a stable music→hue mapping is what lets the eye track a part. → Ricercar binds register → orchestral section → a stable colour family (§1.2). Low = dark heavy voices, high = bright voices, mid = warm middle. The eye learns the code in seconds.
3. **Abstraction over depiction.** Fischinger quit *Fantasia* because Disney pushed his rigorous abstraction toward representational clouds and landscapes. Matt's direction (2026-06-29) is *inspired-by / new abstraction* — closer to Fischinger's original intent than the released film. → No literal orchestra silhouettes, no recognisable clouds/comets; the vocabulary is pure colour, line, flow, accent (§2 anti-references).

Sources: §11.

### 1.1 The voices are the band (the musical role)

**Musical-role sentence** (mandatory, PRESET_SESSION_CHECKLIST Part 2):

> Each orchestral register is a contrapuntal voice — when continuous energy rises in that register (a part entering or sustaining), an independent, register-coloured line of paint wakes, weaves a path whose motion is steered by that register's energy deviation, and persists into the flowing canvas; as more registers sound, more lines braid together, so the listener watches the orchestra's voices enter, interweave, and converge exactly as a fugue stacks its subject.

This names specific musical features (per-register continuous energy, entries/sustains, accumulation of independent lines) and the specific visual behaviour paired with each. It is the spine; if a later increment can't trace a behaviour back to it, the behaviour is wrong.

Three **voice-lanes** (Matt's "by register — orchestral sections"), each a horizontal region, each owning a colour family and 1–2 agent voices:

| Lane | Band (driver) | Section it stands for | Colour family | Canvas region |
|---|---|---|---|---|
| **LOW** | bass / `bassDev` (sub-bass + low-bass refine) | basses, cellos, contrabassoon, organ pedal | deep indigo → midnight blue → violet | lower third |
| **MID** | mid / `midDev` (low-mid + mid-high refine) | violas, horns, bassoons, tenor register | amber → gold → copper | central band |
| **HIGH** | treble / `trebDev` (high-mid + high refine) | violins, flutes, oboes, piccolo | cyan → bright white-gold → cool bright | upper third |

Three lanes (not six) keeps counterpoint legible — the eye can track three braided colours, not six. The 6-band fields refine *vertical position* within a lane; gating is on the 3-band deviation primitives (`bassDev`/`midDev`/`trebDev`), **never** on absolute 6-band energy (FA #31). Each lane's hue jitters within its family (seeded) so two simultaneous voices in one lane stay distinguishable as the same section.

### 1.2 The three-axis mapping

| Axis | Musical input | Visual consequence |
|---|---|---|
| **Who** (which voice) | register → orchestral section | which colour family that line carries, and which lane it lives in |
| **When / how much** | per-register energy deviation (primary) + per-register onset (accent) | deviation wakes & steers the line; onset announces an entry (brief flare) and flicks splatter accents |
| **Character** | spectral centroid, attack sharpness | line crispness / texture: bright → fine, crisp filament; dark → soft, broad, smeared wash |

**Who → colour.** Register owns colour; a line's colour says which section is singing. Bass-heavy music → indigo-dominant canvas; soaring violins → high cyan/gold lines lead. The canvas's colour balance at any instant mirrors the registral balance of the music; its colour history over the piece mirrors the arrangement. Palette is open and tunable — the binding rule is **legibility**: one stable, well-separated colour family per lane, dark-low / warm-mid / bright-high so the eye reads register as vertical colour at a glance.

**When → emission (the spine).** Two channels, mirroring Skein's primary/accent split:
- **Voice channel (PRIMARY):** while a lane's energy deviation is positive (its register sounds above its running mean), that lane's agent(s) are awake — moving, steering, depositing a continuous line of the lane's colour into the canvas. Steering and speed scale with deviation magnitude. Driven by deviation (D-026), never absolute level.
- **Entry / accent channel (ACCENT):** a per-lane onset (`beatBass`/`beatMid`/`beatTreble`) marks a voice entry — a brief bright flare and a quickening at the head of that lane's line. `beatComposite` drives sparse global splatter accents. Accents punctuate; they never carry primary motion (Layer 4 / FA #4).

**Character → crispness.** Spectral centroid sets line texture: bright/airy → thin, fast, finely-dispersing filaments (delicate, slightly translucent so the ground reads through); dark/heavy → broad, slow, smeared washes (opaque, gloopy). A bright fugue subject in the violins looks different from the same subject growled in the basses.

### 1.3 Slow global modulators

**Mood.** Valence → palette warmth/saturation (high → warmer, more saturated; low → cooler, restrained); arousal → overall vigour, how eagerly voices weave, how much the substrate swirls. Smooth valence/arousal **in preset state, never through `setFeatures`** (the Skein/FA #25 convention).

**Structure / three-act feel.** Section boundaries + arousal envelope drive a slow density-and-convergence arc (§3): sparse and gestural when the music is free and thin (the toccata), accumulating and interweaving as voices stack (the fugue), massed and convergent at full tutti (the coda). On arbitrary tracks this rides the engine's existing section/arousal signals; on the target piece it lands as the natural Toccata→Fugue→Coda shape.

### 1.4 The canvas as a flowing colour field (how Ricercar differs from Skein)

Skein's canvas is a permanent record (identity warp, no decay — paint lands and never moves). Ricercar's canvas is a **flowing field** (gentle curl-noise flow warp + slow decay ≈ 0.93–0.96 — colour advects, merges wet-into-wet, slowly breathes out). This is the deliberate aesthetic fork that makes Ricercar painterly visual-music rather than a second drip record (**Matt confirmed, 2026-06-29**):

- Deposited voice-colour is carried by a slow, **divergence-free** flow field (curl noise → swirl without sources/sinks; seeded per track, speed scaled by arousal), so two crossing lines bleed and braid like wet pigment, with the drifting, merging quality of Fischinger's colour masses.
- Slow decay → the canvas is a moving present with a fading memory, not an ever-filling archive — "masses of colour flowing and merging," not a Pollock that only gets denser.
- The voices stay legible on top because they are freshly, opaquely deposited each frame and the ground is their slowly-dissolving wake.

### 1.5 Silence and track change

**Silence:** all lane deviations fall quiet → voices stop emitting and drift to rest; flow field slows; the colour field keeps breathing and slowly dissolves. A paint-on-light-ground preset is bright by construction, so silence-non-black (D-037) is satisfied with no collapse choreography.

**Track change:** canvas and voices reset; the per-track FNV-1a seed re-seeds flow field, lane hue-jitter, agent start positions; a fresh painting begins behind a brief fade-through-ground. Reuse Skein's reset hooks (`resetAccumulatedAudioTime`, per-preset `State.reset`).

---

## 2. Reference decomposition — what we take from *Fantasia*, what we leave

Matt's direction is *inspired-by / new abstraction*, so the 1940 segment is a spiritual reference, not a trait-match target. A curated `docs/VISUAL_REFERENCES/ricercar/` set is assembled before Ricercar.2 — its job is to anchor the abstract-visual-music idiom (Fischinger studies, color-organ stills, abstract-animation frames), with the *Fantasia* Bach segment annotated as inspiration with explicit disregard-these-properties notes.

**Take (the idiom):**
- Independent moving lines each tied to a musical part ("lacy figures cometing," "sky-writing cipher tracing patterns").
- Colour-as-identity; flowing, merging colour masses as the ground.
- Accents as sprays/bursts ("sprays of falling stars") punctuating, not dominating.
- The free→contrapuntal→massed dramatic arc made visual.

**Leave (anti-references — Ricercar must NOT look like these):**
- Literal orchestra silhouettes / the blue-and-gold live-action opening (the faithful-homage path Matt declined).
- Representational depiction — recognisable clouds, landscapes, comets, stars-as-objects.
- Kaleidoscopic symmetry, neon-particle-fountain, clean polka-dot, single-reactive-blob (shared anti-reference list with Skein/Arachne).

---

## 3. Musical contract

### 3.1 The three-act arc (showcased on BWV 565, generalised for any track)

| Act (BWV 565) | What the music does | What the canvas does |
|---|---|---|
| **I — Toccata** (free, improvisatory) | famous descending mordent; dissonant flourishes, broken-chord arpeggios, huge scalar runs over long pedal notes; hands alternating; few simultaneous lines | sparse, high-contrast; one or two bold gestural lines sweep the near-empty ground; arpeggio runs read as fast rising/falling filament cascades; the held pedal is a slow LOW-lane indigo wash beneath |
| **II — Fugue** (counterpoint accumulates) | subject enters voice by voice (exposition D–G–D–G); 3–4 lines interweave; free-fantasia episodes between entries; full 4-voice texture only at the climactic cadences | the heart of the preset: voices enter one lane at a time, each register-coloured; lines braid and bleed in the flowing field; density grows with each entry; episodes thin to fewer voices; cadences flare all lanes at once |
| **III — Coda** (free + full chords) | fugue cadences deceptively in B♭; toccata-style free material returns with full slow chords; grand close | voices converge into massed full-canvas chordal gestures and splatter-washes; motion slows and broadens; the field reaches its richest, then settles on the final cadence |

**Generalisation.** Ricercar does not require a fugue. The arc rides the engine's arousal envelope, section boundaries (`StructuralPrediction`), and textural density = how many lanes carry positive deviation at once. Contrapuntal/layered music lights up multiple lanes and reads richly; sparse music lights few lanes and reads as a quieter painting. It shines on counterpoint and degrades gracefully elsewhere — the honest reusability story behind Matt's "reusable visualizer, tuned to this piece" choice.

### 3.2 Audio routing (one primitive per visual layer — D-026 deviation-normalised; FA #67)

| Visual layer | Single audio primitive | Channel / timescale |
|---|---|---|
| LOW voice wake & steer | `bassDev` | primary / continuous |
| MID voice wake & steer | `midDev` | primary / continuous |
| HIGH voice wake & steer | `trebDev` | primary / continuous |
| Voice vertical position within lane | that lane's 6-band split | character (position only, not gating) |
| Substrate flow speed / swirl | broadband energy deviation + arousal | slow global |
| Substrate decay / breath | arousal | slow global |
| Voice-entry flare | per-lane onset (`beatBass`/`beatMid`/`beatTreble`) | accent (spawn) |
| Global splatter accents | `beatComposite` | accent (per-beat) |
| Line crispness / texture | `spectralCentroid` | character |
| Flare / spray tightness | per-band attack sharpness | character |
| Colour family per lane | register identity | structural |
| Palette warmth / saturation | valence / arousal (smoothed in state) | slow global |
| Density / convergence (3-act) | section boundary + arousal + active-lane count | slow global |
| Voice melodic contour (OPTIONAL, Phase 2) | exposed chroma / melodic-salience pitch (§5) | character |

Every row is a single driving primitive at a single timescale; no two layers share a primitive at the same timescale (the FA #67 audit). Primary motion is continuous deviation; onsets and beats are accents only (Layer 4).

---

## 4. Rendering architecture

A single paradigm, precedented twice over. Per-frame, three stacked layers:

1. **Substrate (flowing colour field).** mv_warp canvas with a gentle curl-noise flow warp (per-vertex displacement; curl noise = divergence-free → swirl without sources/sinks) and slow decay (≈0.93–0.96). Skein's canvas-hold machinery with the warp set to a flow field instead of identity and decay turned partly on. Per-track FNV-1a seed drives the flow field. **Pure preset config of the mv_warp path** (the D-142 config audit applies to this layer).
2. **Voices (the counterpoint).** A small compute-agent set ported from Filigree's trail-agent loop: each lane owns 1–2 agents (cap ~6–8 total). An agent is awake when its lane's `*Dev` is positive; it moves (base wander + steering from its lane's deviation, vertical bias from the 6-band split) and deposits its lane-colour into the substrate canvas so its trail joins the flowing field. Filigree's sense-steer-deposit loop with (a) far fewer agents, (b) agent colour bound to lane, (c) wake/sleep gated by lane deviation. **Port the loop; do not re-derive (FA #73).** The deposit-into-mv_warp-canvas integration is the **Ricercar.3.x** bridge (§0).
3. **Accents (marks-on-top).** Skein's marks-on-top overlay: per-lane onset → brief entry flare at that line's head; `beatComposite` → sparse splatter-sprays. Display-only flares can also live in the comp fragment (Skein's slot-6 preset-buffer adornment path) so they glint without baking into the canvas.

### Draft JSON sidecar (`PhospheneEngine/Sources/Presets/Shaders/Ricercar.json` — values to be tuned)

```json
{
  "name": "Ricercar",
  "family": "painterly",
  "description": "Contrapuntal visual-music painting: each orchestral register is a weaving voice of colour on a flowing field.",
  "author": "Matt",
  "passes": ["direct", "mv_warp"],
  "beat_source": "composite",
  "base_zoom": 0.0,
  "base_rot": 0.0,
  "decay": 0.94,
  "beat_zoom": 0.01,
  "beat_rot": 0.004,
  "beat_sensitivity": 1.0,
  "visual_density": 0.55,
  "motion_intensity": 0.5,
  "color_temperature_range": [0.25, 0.85],
  "fatigue_risk": "low",
  "section_suitability": ["ambient", "buildup", "peak", "bridge", "comedown"],
  "marks": { "...": "entry-flare + splatter overlay config, per Skein.ENGINE.1.1" },
  "certified": false,
  "rubric_profile": "lightweight"
}
```

The compute-agent voices are a render-path branch (like Filigree's particles pass), not expressible purely in the sidecar; `passes` may need to gain the agent/particles path via the Ricercar.3.x bridge. Claude Code wires the agents in the renderer alongside the mv_warp path.

---

## 5. Engine prerequisites

**V1 (Ricercar.1–.7):** no new audio/feature primitives; **one bounded rendering bridge** (Ricercar.3.x, §0). Every audio input the V1 needs already exists and is certified-in-use: 3-band + deviation primitives (`bassDev`/`midDev`/`trebDev`), 6-band, per-band onsets (`beatBass`/`beatMid`/`beatTreble`/`beatComposite`), `beatPhase01`/`barPhase01`, `spectralCentroid`, valence/arousal, the canvas-hold mv_warp + flow-warp + marks-on-top stack (Skein), the compute-agent trail loop (Filigree), and the per-track FNV-1a seed. This clears the session checklist's three-part bar: iconic subject deliverable at fidelity (both constituent stacks certified), clear musical role (§1.1), infrastructure-feasible (no missing primitive; the lone integration is bounded, scoped, and lands early as its own increment).

**Phase 2 (optional, deferred — name it, don't gold-plate V1):** expose pitch to the GPU. `ChromaExtractor` (12-bin, Krumhansl-Schmuckler) is computed but consumed only by the mood classifier — not in `FeatureVector`, not on the GPU. A discrete increment could surface a chroma vector (or a melodic-salience pitch per lane) to the preset, letting each voice trace its register's actual melodic contour (pitch → vertical position) and optionally shade hue by pitch-class. Product framing: "the lines would sing the tune, not just rise and fall with their register's loudness." Matt did not select the pitch/color-organ mapping, so this stays optional and out of V1; flag it as the obvious first enhancement if register-only voices read as too generic.

---

## 6. Known limitations & honest constraints

- **No instrument separation (headline constraint).** Open-Unmix yields vocals/drums/bass/other; an orchestral recording collapses into "other." Ricercar uses frequency **register**, not stems, as its proxy for "which section." It cannot distinguish an oboe from a flute in the same register. Stated, not hidden.
- **Counterpoint is evoked, not transcribed.** Real-time polyphonic voice-separation on arbitrary audio is unsolved; Ricercar does not attempt it. Voice count = active-lane count = textural density, which correlates with the number of sounding parts on real counterpoint but is not a transcription. On BWV 565 this reads true; never describe the design as "following the fugue's voices" in the score-following sense.
- **Cold-start phase (CLAUDE.md contract).** Beat phase may be wrong in the first ~3 s. V1 primary motion is on continuous deviation (frame-1 reliable), so voices wake correctly from the first phrase; entry flares are ungated beat accents (acceptable — a small phase error reads as a small offset).
- **Aesthetic risk = the Skein.3-equivalent.** The real risk is making the weaving lines read as painterly orchestral voices, not "neon spaghetti" or "particle soup." Iteration concentrates here; phase it so a still frame is judged early (§7), judged against the curated reference idiom, never self-assessment.

---

## 7. Phased implementation — Claude Code handoff

House-style increment IDs (Ricercar.N), small commits (`[Ricercar.N] <component>: <desc>`), each ending with the standard Increment Completion Protocol (closeout + `Scripts/closeout_evidence.sh` block, `RENDER_VISUAL=1` contact sheet for visual increments, ENGINEERING_PLAN + RENDER_CAPABILITY_REGISTRY updates, local main commit; push only on Matt's explicit approval). Infra patches land in their own `.x` increment.

- **Ricercar.1 — reference lock (gating, doc-only).** Curate `docs/VISUAL_REFERENCES/ricercar/` (visual-music / Fischinger / color-organ idiom; *Fantasia* Bach segment annotated inspiration, disregard representational traits), README with trait-trustability + §2 anti-references. Per D-064 no later session prompt is written until this exists. *(This design doc + the references README scaffold + plan/registry rows are the Ricercar.1 deliverables.)*
- **Ricercar.2 — substrate spike.** Flowing colour field: mv_warp canvas + curl-noise flow warp + slow decay, seeded per track, hand-fed colour (no audio). Gate-before-the-gate: if it doesn't read as flowing, merging painterly colour, stop and re-tune before adding voices.
- **Ricercar.3.x — integration bridge (infra).** Land the particle-to-feedback-texture routing (§0): `ParticleGeometry.rendersToFeedbackTexture` + the `RenderPipeline+Draw.swift` reroute + `PhysarumGeometry` opt-in. Golden-locked (every other mv_warp/particle preset byte-identical). Surface scope to Matt before proceeding.
- **Ricercar.3 — one voice.** Port one Filigree-class agent depositing a register-coloured line into the substrate, hard-coded motion. Does a single weaving line read as a voice on the flowing ground? Contact sheet.
- **Ricercar.4 — three lanes + audio routing.** Three lanes wired to `bassDev`/`midDev`/`trebDev` (wake/steer), 6-band vertical bias, per-lane onset entry-flares, `beatComposite` splatters, centroid→crispness (the §3.2 table). Counterpoint first appears here — expect the highest aesthetic iteration.
- **Ricercar.5 — mood + three-act arc.** Valence/arousal palette + density/convergence arc on section/arousal signals; verify the Toccata→Fugue→Coda shape on the BWV 565 fixture.
- **Ricercar.6 — silence, track-change, polish.** Rest behaviour, fade-through-ground reset, governor hooks (cap agents + splatter count under budget), soak test.
- **Ricercar.7 — certification.** Acceptance invariants (§8), determinism golden-hash gate, then Matt M7 on live music across ≥5 tracks + the BWV 565 local file.
- **Ricercar.8 (optional) — pitch contour.** The §5 Phase-2 chroma/salience exposure, only if register-only voices read as too generic.

Build the production-grade temporal test alongside the audio increments (the `AuroraVeilMVWarpAccumulationTest` / `SkeinCanvasHoldTest` pattern) — no shader-alone shortcuts for a feedback+agent preset.

---

## 8. Acceptance criteria (Gate 6 preview)

- **Silence-non-black (D-037):** trivially passes (light ground + colour).
- **Counterpoint legibility (headline):** on a contrapuntal fixture, ≥3 distinct register-coloured lines simultaneously trackable by eye during the dense passage; on a sparse fixture, visibly fewer. Active-lane count tracks textural density (assert from `features.csv` lane-deviation columns).
- **Determinism:** same track + seed → dHash-stable final field across two runs (a headline property, as for Skein).
- **Beat/entry ratio:** entry-flare + splatter density on a beat-heavy fixture measurably exceeds a steady fixture.
- **Anti-reference rejection:** must not read as neon-spaghetti / particle-fountain / kaleidoscopic-symmetric / single-reactive-blob (M7 manual until the automated anti-reference gate lands).
- **Performance:** 60 fps at 1080p incl. M1 (light: one mv_warp + ≤8 agents + scissored marks; orders of magnitude lighter than Filigree's 262k agents).
- **M7:** Matt, live, real music ≥5 tracks + the BWV 565 local file — the counterpoint-must-read perceptual gate. Non-negotiable.

---

## 9. Open decisions for Matt

| # | Decision | Recommendation | Status |
|---|---|---|---|
| Name | Ricercar / Stretto / Cantus | **Ricercar** (lineage + "to seek out"); Stretto more legible if wanted | open |
| Family | painterly vs new visual-music family | **painterly** (Skein sibling — Orchestrator variety/fatigue accounting) | open |
| Lanes | three vs more | **three** (low/mid/high) for legible counterpoint; Phase-2 pitch is the better path to "more voices" | open |
| Substrate fork | flowing field vs Skein's frozen record | **flowing field** — **CONFIRMED Matt 2026-06-29** | ✅ resolved |
| Phase-2 pitch contour | now vs later | **later** — ship register-only voices first | open |
| Visible "conductor" locus | faint glints where voices enter, off by default | **try in Ricercar.6 behind a flag** | open |

### One-line feasibility summary for the queue

Ricercar is buildable now with **no new audio/feature primitives** and **one bounded, audited engine bridge** (Ricercar.3.x, ~60 lines) — it's Skein's canvas-hold mv_warp (reconfigured to a flowing field) carrying a small set of Filigree-class agent "voices," one per orchestral register, woken and steered by the 3-band deviation primitives, with onset entry-flares and beat splatters as accents. A single paradigm precedented twice (Skein + Filigree), lighter than either, with clean silence and determinism stories. The real work and risk are in Ricercar.4 — making the braided register-lines read as orchestral counterpoint, not coloured spaghetti.

---

## 10. Failed approaches this design must respect

- **FA #4 / Layer 4** — never drive primary voice motion from raw live onsets (jitter; feedback amplifies it). Voices wake/steer on continuous deviation; onsets only announce and accent.
- **FA #31** — no absolute thresholds on AGC-normalised energy. Lane gating is on `bassDev`/`midDev`/`trebDev`, not on `bass`/`mid`/`treble` levels.
- **FA #67** — one primitive per visual layer per timescale (the §3.2 table is the audit).
- **FA #64 / #73** — ground in the references; port Filigree's agent loop and Skein's canvas-hold recipe rather than re-deriving. "I cited it in the design doc" is not using it — read both presets' code/design before writing Ricercar.3/.4.
- **Reusable-infrastructure / structure-as-substitute discipline** — keep the concept tight; if a defence of keeping a deleted concept invokes "reusable infrastructure," it's wrong.

---

## 11. Sources

**Source material & music**
- *Fantasia* (1940) — Wikipedia: https://en.wikipedia.org/wiki/Fantasia_(1940_film)
- "Bach's Toccata and Fugue: The Fantasia opener that drove Disney to abstraction" — YourClassical/MPR: https://www.yourclassical.org/story/2015/02/27/bach-toccata-fugue-fantasia
- The Walt Disney Family Museum, "Fantasia in Eight Parts: Toccata and Fugue in D minor": https://www.waltdisney.org/blog/fantasia-eight-parts-toccata-and-fugue-d-minor
- Toccata and Fugue in D minor, BWV 565 — Wikipedia: https://en.wikipedia.org/wiki/Toccata_and_Fugue_in_D_minor,_BWV_565
- Netherlands Bach Society (All of Bach), BWV 565: https://www.bachvereniging.nl/en/bwv/bwv-565
- J. S. Bach / Stokowski, Toccata and Fugue — American Symphony Orchestra programme note: https://americansymphony.org/concert-notes/j-s-bach-leopold-stokowski-toccata-and-fugue-in-d-minor/

**Visual-music lineage**
- Oskar Fischinger — Wikipedia: https://en.wikipedia.org/wiki/Oskar_Fischinger
- Visual music / color organ tradition (Rimington, Scriabin *Prometheus*, the Whitneys, Len Lye, Norman McLaren) — Wikipedia: https://en.wikipedia.org/wiki/Visual_music

**Engine grounding (in-repo)**
- [SKEIN_DESIGN.md](SKEIN_DESIGN.md) — canvas-hold mv_warp, marks-on-top, per-track seed, primary/accent split.
- [FILIGREE_DESIGN.md](FILIGREE_DESIGN.md) — compute-agent sense-steer-deposit trail loop (the voice stack to port).
- [RENDER_CAPABILITY_REGISTRY.md](../ENGINE/RENDER_CAPABILITY_REGISTRY.md) — feedback / mv_warp / flow-advection / compute-agent capability statuses; the feedback-canvas + agent-deposit bridge (§0).
- [ARCHITECTURE.md](../ARCHITECTURE.md) §Key Types / §Audio Analysis Tuning — FeatureVector fields, deviation primitives (D-026), chroma extractor (computed, not yet on GPU).
- CLAUDE.md §Audio Data Hierarchy, §Cold-Start Phase Contract, Failed Approaches #4/#31/#64/#67/#73.
</content>
</invoke>
