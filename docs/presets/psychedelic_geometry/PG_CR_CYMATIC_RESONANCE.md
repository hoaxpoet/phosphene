# CR — Cymatic Resonance

> **⚠ CR.2 REBUILD — READ FIRST (2026-07-22, D-199). Everything below Part A is the RETIRED CR.1 figure-shader design.** Cymatic Resonance shipped and **certified** as a **vibrating-sand particle simulation**, not the static nodal-figure shader this doc originally specified. After 3 live M7s, Matt's read was concept-level: the figure-shader rendered the *result* of resonance (a nodal figure) rather than the *phenomenon* (a plate vibrating, sand jumping and re-forming) — "not a clear connection to the music… the references are about resonance/vibration and I'm not seeing it." Rebuilt (Matt's call) as `feedback+particles`: ~400K glowing sand grains do the **vibration-driven random walk** (Zhou et al. 2017; ported from luciopaiva/chladni per FA #73) on the plate field — grains shimmer at antinodes, collect on the nodal lines, scatter+re-collect on a mode change. Music: loudness→vibration (transient-dominant so bass hits are tight), `bass_dev`→burst, `spectral_centroid`→mode (+ a beat-stepped wander for variety), `tonal_phase_fifths`→jewel hue; top-down cover-fit fills the 16:9 frame. Impl: `CymaticSandGeometry` + `Renderer/Shaders/CymaticSand.metal`. Certified CR.2.7 (flash-safe 0.00/s, perf 0.74 ms p95 @1080p). **The CR.1 material below is kept as the design history of the retired approach + the still-valid plate-field math (plus basis, same-parity ladder correction #5).** Full arc: `docs/DECISIONS.md` D-196→D-199.

Phosphene-native abstract-geometry preset (filed in the psychedelic-geometry set). Working name; rename freely at sign-off. Increment IDs use the **CR** prefix (the "second-pass slate" / `PG_HDR_SLATE.md` framing referenced in the origin prompt does not exist in-tree — do not invent it; treat CR as a standalone PG-family preset).

> **Read this first — Concept-gate outcome (2026-07-22).** This preset cleared the `preset-concept` gate **look-spike-first**, before any shader, using Matt's own real-Chladni-plate footage (`brusspup`, screen-recorded) as the ground-truth moving source. The numpy look-spikes + frame-by-frame comparison against the real plates earned **four corrections to the original design prose** — each a defect that would otherwise have surfaced at M7 (where Kinetic Sculpture D-188 and Truchet Loom D-194 both died). The corrections are baked into Part A below. The original prose (12-band spectral-shape superposition, minus-basis, slight tilt, jewel-optional) is superseded where it conflicts.

| # | Original prose said | Ground truth (Matt's video) → **adopted** |
|---|---|---|
| 1 | minus basis `cos(mξ)cos(nη) − cos(nξ)cos(mη)` (Shadertoy [4dXSD2](https://www.shadertoy.com/view/4dXSD2)) | **plus basis** `cos(mξ)cos(nη) + cos(nξ)cos(mη)`. The minus combination forces `ξ=η` to be a nodal line on *every* figure → a spurious dominant diagonal; the plus combination recovers the real 4-fold axis-symmetric concentric figures. |
| 2 | HERO = per-band FFT share → **12 mode-amplitudes summed** ("geometry = full spectral shape") | HERO = **one dominant mode selected by brightness (spectral centroid)**, crossfading up a complexity ladder as pitch rises. Real plates show ONE clean eigenmode per frequency; the 12-sum reads as squiggle-soup (verified). Still "geometry = the sound," now the sound's *pitch* → resonant figure. |
| 3 | "slight tilt, near-top-down" | **strong oblique tilt (~40°)**, plate-on-a-surface — matches the reference camera. |
| 4 | jewel-toned emissive (thin-film) | **jewel / iridescent** (Matt's call, 2026-07-22) — the Phosphene signature, applied to the corrected geometry. Real sand is white; we stylize. |
| 5 | ladder = adjacent pairs `(1,2)(1,3)(2,3)…` | **same-parity `(m,m+2)` family `(1,3)(2,4)…(11,13)`** (found at the CR.1 maquette render, D-196). The plus basis (correction #1) removes the minus basis's main-diagonal (ξ=η) but FORCES an anti-diagonal (η=1−ξ) nodal line for any OPPOSITE-parity (m,n) — verified `max\|φ\|` on η=1−ξ = 0 for (1,2),(2,3),… vs 2 for (1,3),(2,4),… So the adjacent-pair ladder (full of opposite-parity modes, incl. the fundamental (1,2) = the silence rest state) rendered the very spurious diagonal the plus↔minus switch was meant to kill. Same-parity pairs are 4-fold symmetric AND diagonal-free on BOTH diagonals. **Same-parity is the load-bearing property**, not the specific family. |

Concept-gate artifacts (throwaway spike, not committed): numpy renderer + contact sheets + `motion_gate.sh` runs; motion clean except the intentional bass-drop snap. Grounding source watched in motion: Matt's real footage (kept private/uncommitted — `brusspup` is copyrighted).

---

# PART A — DESIGN

## A0. Identity
- **Name (working):** Cymatic Resonance
- **Family:** `geometric` · **concept_tags:** `["geometric","resonant","hypnotic"]` (⚠ confirm `resonant` is in the D-120 controlled vocab at implementation; fallback `["geometric","hypnotic"]`)
- **motion_paradigm:** `direct_time_modulation` (D-029) · **passes:** `["direct","post_process"]`

**One-line pitch:** A resonant plate whose Chladni nodal figure is selected live by the music's brightness — as the track brightens the figure blooms into finer, more complex 4-fold-symmetric patterns; a bass drop snaps it back to a big simple figure. The figure you see is the *pitch of the sound made solid.*

## A1. Concept-viability gate (`SHADER_CRAFT.md §2.0`)
- **Gate 1 — Musical role:** spectral centroid (brightness) selects which plate eigenmode is excited → the nodal figure; rising brightness climbs the mode-complexity ladder (finer figure), a bass drop snaps to a low simple mode. Two features (brightness level; its rate/drop) → two behaviours (which figure; snap-vs-morph). **Passes** — and now grounded in real footage, not prose.
- **Gate 2 — iconic subject at fidelity (honest):** **low risk, gate-passed.** The corrected plus-basis single-mode figures were compared frame-to-frame against real plates and rhyme (concentric rings, 4-fold grids, finer with pitch). Analytic closed form — no fractal detail-stability or ray-march-perf exposure. Build to the achievable bar: a luminous, dimensional Chladni figure that visibly is the sound's pitch.
- **Gate 3 — infra-feasible:** yes. Direct fragment reads spectral centroid (FeatureVector, buffer(0)); renders a displaced 2.5D relief; derives a normal from the height gradient; lights GGX; jewel emissive + thin-film; shipped ACES/bloom post. Optional preset state buffer (slot 6) for the mode-ladder EMA (NimbusState precedent). No new passes.

## A2. Visual target & the four-scale nested detail cascade
Mechanic (**PORT the math, don't derive** — FA #73): plate coords (ξ,η) ∈ [0,1]²; eigenmode **plus** combination φ_{m,n} = cos(mπξ)cos(nπη) **+** cos(nπξ)cos(mπη); nodal set where the active field ≈ 0 (bright emissive ridge; sand analog). Active field = crossfade between two adjacent ladder modes: `z = (1−f)·φ[i] + f·φ[i+1]`, `i,f` from brightness. Fixed low→high complexity ladder of (m,n) pairs (m<n): `(1,2)(1,3)(2,3)(2,4)(3,4)(3,5)(4,5)(4,6)(5,6)(5,7)(6,7)`.

- **Macro:** the plate silhouette + the dominant symmetric nodal figure (few big lobes at low brightness), strong oblique tilt.
- **Meso:** as brightness climbs, the figure resolves into finer concentric rings + symmetric grid cells (the "figure within the figure").
- **Micro:** surface micro-grain (fbm) between ridges + iridescent thin-film on the ridge crests.
- **Specular/breakup:** derived-normal GGX key highlight on the relief (the depth cue), HDR bloom on crests, deep-black plate body.

## A3. Motion & 30-second temporal contract
Camera holds (`direct_time_modulation`); **the figure is the motion** — no camera move, no `mv_warp` (would smear the crisp nodal lines). Strong oblique tilt is a fixed framing, not a moving camera.
- **Hero:** brightness (spectral centroid, EMA) drives the mode-ladder position → the figure morphs between clean symmetric figures (bright → finer/more complex).
- **Bass drop → snap** to a low simple figure (fast EMA, a visible restructure — the one big legible event).
- **Excitation** breathes gain with `f.arousal` (CR.3).
- **Over 30 s:** a plate unmistakably listening — figure blooming complex on bright passages, snapping simple on drops.

## A4. Audio-routing table (one primitive per layer — FA #67)
| Visual layer | Primitive | Timescale | Role |
|---|---|---|---|
| Mode-ladder position (which figure) | `f.spectral_centroid`, EMA-smoothed (slot-6 state) | continuous / slow | **HERO** — geometry = pitch of sound |
| Snap-to-simple event | `f.bassDev` (deviation, D-026) crossing → fast-EMA yank down the ladder | per-drop | the one big legible restructure |
| Excitation gain (CR.3) | `f.arousal` | slow | how hard the plate vibrates |
| Ridge hue / thin-film phase (CR.3) | `f.spectral_centroid`→ valence IBL tint (D-022) | slow | colour temperature |
| Ridge shimmer accent (CR.3) | `stems.drums_energy_dev_smoothed` | per-beat (bounded) | glint on the figure; steady global luminance |

Self-check: hero (centroid, slow) and snap (bassDev, event) are distinct primitives/timescales. No two motion layers share a primitive. Deviation primitives only — no absolute thresholds on AGC-normalized values (FA #31).

**Liveness (§14.1):** `spectral_centroid` is reliably alive and level-independent (it tracks timbre/brightness, which always varies) — this is why the corrected mapping is alive by construction where the original raw-FFT-magnitude mapping was near-dead on quiet bands. Add the slot-6 EMA + `smoothstep(0.02,0.06,totalStemEnergy)` warmup (D-019).

## A5. Silence state (D-037)
`totalStemEnergy == 0`: plate rests in the fundamental (low ladder mode `(1,2)`), dim emissive, breathing slowly, non-black (plate body + faint emissive figure + IBL floor). Nothing strobes.

## A6. Palette & lighting
Deep-black plate; **jewel/iridescent** emissive nodal ridges are the light source (Matt's call). Derive surface normal from the height-field gradient, light GGX (SHADER_CRAFT §18.9 — Skein wet-sheen precedent) so relief catches a key highlight. Thin-film iridescence on ridges (`thinfilm_rgb`). Mood-tinted IBL (valence, D-022). ACES + bloom on crests. Pale-tone ≤ 30 % (§12.7). Saturated jewel tones, no grey (FA #39/#45).

## A7. Reference sourcing
**Ground truth (private, uncommitted):** Matt's real-Chladni footage (`brusspup`, copyrighted — do NOT commit its frames). This is the authoritative LOOK reference for the build.
**Committed set** `docs/VISUAL_REFERENCES/cymatic_resonance/` — curate CC/PD stills before the port task. Candidate sources (verify license at commit): Stephen Morris Chladni photos (flickr, CC BY 2.0), Chladni's 1787 engravings (PD), Faraday-wave lattice (MDPI CC BY), high-freq Chladni filigree (flickr CC BY), Rubens'-tube emissive standing wave (PD Mark, palette), anti-ref = a fixed radial mandala that looks cymatic but has no frequency response. Write `README.md` with per-image trait-trustability + anti-reference. **REFERENCES TO READ (port, don't commit):** square-plate eigenmode superposition; Shadertoy 4dXSD2 (cite — but note we use the **plus** combination, not its minus).

## A8. Performance & tier
Cheap direct fragment: two ladder-mode fields (each ~2 cos-product evals over a small integer set — precompute per-mode `(mπ,nπ)` constants) + crossfade + 4-tap height gradient normal + GGX + `thinfilm_rgb` + bloom. Est. ~1.5–2.5 ms, well under Tier-2 7 ms (measure at implementation). Tier-1 comfortable.

## A9. Fidelity-uplift arc
- **CR.1 (build now):** plate + hero brightness→mode-ladder figure (plus basis, crossfade, snap-on-drop) + derived-normal GGX relief + jewel emissive + strong tilt + non-black fundamental silence. "Clay maquette" (SHADER_CRAFT §2.2).
- **CR.2:** materials + micro — thin-film on ridges, plate material, sand-accumulation band along ridges, fbm micro-grain, roughness breakup (four-scale cascade complete).
- **CR.3:** secondary audio (`arousal` excitation, `spectral_centroid` hue, drum shimmer) + mood/valence IBL + optional shallow DOF + perf tune + Tier-1 degradation + M7 + cert.

## A10. JSON sidecar sketch
```jsonc
{
  "name": "Cymatic Resonance", "family": "geometric",
  "concept_tags": ["geometric","resonant","hypnotic"],   // confirm vocab (D-120); fallback ["geometric","hypnotic"]
  "motion_paradigm": "direct_time_modulation",
  "passes": ["direct","post_process"],
  "duration": 30,
  "certified": false, "rubric_profile": "lightweight",   // 2D single-plate; hold to multi-octave/non-pale/nested bar regardless
  "complexity_cost": { "tier1": 2.5, "tier2": 1.5 },      // measure + correct at implementation
  "visual_density": 0.6, "motion_intensity": 0.5,
  "color_temperature_range": [0.2, 0.9], "fatigue_risk": "medium",
  "transition_affordances": ["crossfade","cut"],
  "section_suitability": ["ambient","buildup","peak","bridge","comedown"],
  "stem_affinity": { "other": "mode_shape", "drums": "ridge_shimmer", "bass": "snap_to_simple", "vocals": "high_modes" }
}
```

---

# PART B — SESSION PROMPT (CR.1)

**Increment CR.1** — Cymatic Resonance plate + hero brightness→mode-ladder figure (preset increment). Objective: a direct preset whose fragment renders the **plus-basis** square-plate Chladni figure, mode-ladder position selected by `spectral_centroid` (crossfade between clean symmetric figures; snap-to-simple on `bassDev` drop), rendered as a strong-oblique-tilt displaced relief lit via height-gradient normal + GGX, jewel emissive on deep-black, through ACES + bloom. Non-black fundamental silence. Registered, compiling, golden-hashed, perf-profiled. `certified` stays false. Materials/micro/secondary-audio/cert → CR.2–CR.3.

1. **Skills:** `preset-session` (done) → `shader-authoring` (before GPU code; port the plus-basis superposition, cite 4dXSD2, do NOT derive) → `closeout` (end).
2. **Read-first:** this doc (Part A of record); `docs/VISUAL_REFERENCES/cymatic_resonance/README.md`; `ARCHITECTURE.md §GPU Contract Details` (direct-pass fragment layout; confirm buffer(0) FeatureVector `spectral_centroid`/`bassDev`/`arousal`/`totalStemEnergy`, buffer(1) FFT, slot-6 preset state via `setDirectPresetFragmentBuffer`); `SHADER_CRAFT.md §18.9` (derived-normal GGX), §4.18 thin-film, §6.4 bloom, §9 perf, §14.1 liveness; a reference direct preset holding a slot-6 state buffer (Skein) for fragment structure + state plumbing; `PresetLoader+Preamble.swift`; `PostProcessChain`.
3. **Pre-flight:** clean tree; engine tests green; `docs/VISUAL_REFERENCES/cymatic_resonance/` curated + README + `CheckVisualReferences` green; ENGINEERING_PLAN CR.1 row present; confirm production preset count to bump by exactly 1 (25 → 26); verify centroid/bassDev binding against a reference preset before writing bindings.
4. **Tasks (done-when):** scaffold (row + `.metal` + `.json` + register + count bump; loads/renders) → port plus-basis field + mode ladder (contact sheet: legible crisp 4-fold figure, non-black) → brightness→ladder crossfade + bassDev snap (multi-frame test: bright→fine figure, drop→snap-to-simple, verified as real geometric change) → derived-normal relief lighting + jewel emissive + strong tilt (reads dimensional, not flat) → silence fundamental (non-black, calm) → audio-routing review (deviation/centroid only; one primitive per layer; liveness note in shader header) → perf (Tier-2 p95 ≤ 7 ms) → golden hash **STOP AND REPORT** (maquette contact sheet; note materials/micro/secondary deferred) → closeout.
5. **Do-NOT:** don't derive mode shapes (port); no `mv_warp`/camera-motion/ray-march; no absolute thresholds / raw-FFT-magnitude drivers (centroid + deviation only); no two motion layers on one primitive; no materials/micro/secondary-audio/DOF beyond maquette; don't flip `certified`; don't regenerate other goldens; **don't commit `chladni_real.mov` or any `brusspup` frames** (copyrighted).
6. **Commit templates:** `[CR.1] Presets: scaffold Cymatic Resonance (direct) + JSON + registration` · `[CR.1] Cymatic Resonance: port plus-basis Chladni field + mode ladder (ref 4dXSD2)` · `[CR.1] Cymatic Resonance: derived-normal relief + jewel emissive` · `[CR.1] Cymatic Resonance: spectral-centroid → mode ladder + bassDev snap (D-019 warmup)` · `[CR.1] Cymatic Resonance: golden hash + perf + ENGINEERING_PLAN row`. Push only on Matt's "yes, push".
7. **Closeout:** 8-part report + verbatim evidence block; direct-pass dispatch path; embodiment evidence (bright-vs-dim figure delta + snap-on-drop); perf p50/p95/p99 + N-cap Tier-1 plan; maquette M7 contact-sheet path; explicit deferral of materials/micro/secondary/cert to CR.2–CR.3.

## DECISION-NEEDED (resolved at concept gate)
- Sequencing → **look-spike first** (Matt, 2026-07-22). · Look axis → **symmetric** (Matt). · Mapping → **brightness→single-mode** (recommended, adopted). · Basis → **plus** (reference-forced). · Tilt → **strong oblique** (reference-forced). · Palette → **jewel/iridescent** (Matt). · Band-count → obsolete (single-mode ladder, not N-band sum). · Rubric → `lightweight` (single plate; hold to the craft bar regardless).
