# PG.4 — Truchet Loom

**One combined doc: Part A is the committed design; Part B is the runnable Claude Code session prompt.** Read `PG_0_OVERVIEW.md §3 (audio contract)` and `§4 (JSON conventions)` alongside this. Working name — rename freely.

> **Recommended first build of the phase** (see `PG_0 §6`): lowest fidelity risk (pure crisp 2D, strong published prior art), and it proves the density-mapping routing strategy cleanly.

---
---

# PART A — DESIGN

## A0. Identity

- **Name (working):** Truchet Loom
- **Family:** `geometric` · **concept_tags:** `["geometric","hypnotic"]` · **motion_paradigm:** `direct_time_modulation`
- **Passes:** `["direct"]` (crisp flat op-art; no feedback — subdivision animation *is* the motion)
- **One-line pitch:** A woven op-art labyrinth of curved Truchet tiles that subdivide into smaller tiles of the same weave when the music gets busy and merge back into big sweeping arcs when it thins — musical complexity rendered as geometric complexity.

## A1. Concept-viability gate (`SHADER_CRAFT.md §2.0`)

**Gate 1 — Musical role (the sentence):**
> *As the music gets busier — rising spectral flux — the weave subdivides: each arc-tile splits into four smaller tiles carrying the same curve, so the labyrinth grows denser; when the music thins, the tiles merge back into large sweeping arcs — so the listener literally sees the song's density as the weave's density, and each beat flips a cluster of tiles onto a new path.*

Specific feature (spectral flux / musical busyness; and the beat) each paired with a specific behaviour (subdivision densifying/coarsening; clusters of tiles flipping). It passes. This is the phase's **complexity-mapping** strategy — a music-response idea none of the other four use.

**Gate 2 — Iconic subject deliverable at fidelity:** Yes, easily. Multiscale Truchet tiling is a *thoroughly solved* 2D register with canonical published implementations (Inigo Quilez, Christopher Carlson) and countless Shadertoy examples. It is crisp flat vector art — no photoreal fidelity risk. Comparable Phosphene presets: Plasma / Nebula (simple direct-pass 2D). This is the safe first build of the phase.

**Gate 3 — Infrastructure-feasible:** Yes. Pure `direct` fragment reading `FeatureVector` + optionally `SpectralHistory` (buffer 5, direct-pass) for smoothing. An optional tiny slot-6 state buffer holds the smoothed subdivision level (to prevent flicker). No new passes or contract.

## A2. Visual target & the four-scale nested detail cascade

The "smaller shapes making larger shapes" is the *mechanism itself*: a tile subdivides into four sub-tiles each carrying the same arc motif, and the arcs connect across cells into continuous paths — small shapes literally composing the large weave, self-similar across subdivision levels.

1. **Macro.** The overall weave field and its dominant path-flow direction — a labyrinth silhouette that reads across the room.
2. **Meso (the tiles).** Individual Truchet tiles: two quarter-arcs per cell (hash-chosen orientation) that connect edge-to-edge into long winding paths.
3. **Micro (the subdivision — the nesting).** Cells above the current density threshold **subdivide into 2×2 sub-cells**, each with its own Truchet arc carrying the same motif at half scale. One or two more levels where the density is high. The self-similarity across levels is the psychedelic payload.
4. **Breakup.** Anti-aliased path edges, a soft glow along paths, subtle grain, and **per-path hue** so the weave reads as coloured ribbons, not a monochrome maze. Keep the op-art punch (high contrast) without pure black/white flatness (FA #45; pale-tone ≤ 30 %).

**Mechanic (author's guide — port, don't derive; FA #73):** classic Truchet — `hash` per cell → arc orientation → distance to the two quarter-arcs → path coverage. **Multiscale** — a per-cell continuous "subdivision level" (driven by audio density + a per-cell hash offset); cells whose level exceeds a threshold recurse into 2×2, and the *fractional* part of the level crossfades a tile smoothly between "one big arc" and "four small arcs" so subdivision animates rather than pops. Port IQ's / Carlson's multiscale Truchet approach. `hash_f01_*` (in `Utilities/Noise/Hash.metal`) is the per-cell hash starting point; **there is no existing Truchet/weave utility** — the multiscale recursion is authored from the ported reference.

## A3. Motion & 30-second temporal contract

The canvas is transformed by **the weave densifying and coarsening with the music**, plus a slow global drift and per-beat tile flips. No feedback — every frame is crisp (feedback would smear the fine paths; the anti-reference).

- **Density is the music's busyness (hero).** A smoothed `spectral_flux` sets the global subdivision level: a busy, transient-rich passage drives the level up and the weave shatters into fine nested sub-tiles; a sparse passage lets the level fall and the tiles merge into large sweeping arcs. The *whole canvas re-resolves* as the music breathes — this is the transformation.
- **Slow drift (flow).** The tiling scrolls/rotates gently from `arousal` + `accumulated_audio_time`, so the labyrinth is always flowing even at steady density.
- **Per-beat flips (rhythm accent).** On each `beat_phase01` wrap, a bounded, hash-selected subset of tiles flip their arc orientation — the paths re-route on the beat. Bounded footprint, steady global luminance (D-157).
- **Over 30 s:** the maze is a live readout of the arrangement — verses thin it to broad ribbons, drops shatter it into dense filigree, the beat keeps re-routing the paths. Unmistakably the "complexity-mapping" preset.

## A4. Audio-routing table (one primitive per layer — FA #67)

| Visual layer | Primitive | Timescale | Role |
|---|---|---|---|
| **Subdivision density (nesting depth)** | `f.spectral_flux` (smoothed) | continuous / medium | **HERO** — busyness → geometric density |
| **Global drift / scroll speed** | `f.arousal` (+ `accumulated_audio_time` baseline) | slow | the weave flows |
| **Per-beat tile flips (bounded subset)** | `f.beat_phase01` wrap (cached grid) | per-beat / structural | **HERO #2** — paths re-route on the beat |
| **Path hue / palette phase** | `f.spectral_centroid` | slow | coloured ribbons, not motion |
| *(optional secondary)* **path glow pulse** | `f.bass_dev` | per-onset (bounded) | leading-edge glow on the newest subdivided cluster |

**Self-check:** five layers, five distinct primitives. `spectral_flux` (density) and `arousal` (speed) are different primitives on different channels. Only the flips are strictly beat-locked; the optional glow is a *bounded* onset accent on a different visual channel (glow, not geometry) — keep it subtle and drop it if it competes at M7. No layer runs two audio primitives (`accumulated_audio_time` on the drift layer is a non-reactive wall-clock baseline, not a second audio driver — that layer's one audio primitive is `arousal`).

**Liveness:** `spectral_flux` is reliably alive across genres and literally measures the thing we're mapping (busyness) — an unusually well-matched hero. `arousal`, `spectral_centroid`, `bass_dev` alive; `beat_phase01` alive with a grid. Smooth `spectral_flux` (slot-6 EMA or the `SpectralHistory` trail) so density doesn't flicker frame-to-frame.

## A5. Silence state (D-037)

At `totalStemEnergy == 0` (flux ≈ 0): a **coarse, large-arc weave** (minimum subdivision) drifting slowly, calm duotone palette, non-black. Big simple ribbons breathing gently — "a loom at rest," clearly alive but quiet. No flips at silence.

## A6. Palette

Bold op-art duotone-plus-accent (deep jewel base + a bright ribbon colour + a highlight), per-path hue from centroid, valence warm/cool nudge. High contrast for the psychedelic-poster punch, but keep pale-tone ≤ 30 % and avoid pure #000/#fff flatness — give the base a deep colour, not black.

## A7. Reference sourcing (curate before Part B runs — Matt-owned)

Populate `docs/VISUAL_REFERENCES/truchet_loom/` and write its `README.md`. Shopping list:

> **Status (2026-07-20):** references are curated + committed (PG.0, commit `695fc3a8`) — see the folder `README.md` for the placed set and per-image trait notes. The anti is **prose-only in the README (no committed image)**, per Matt (no anti supplied). The list below is retained as the original sourcing intent / provenance.

- `01_macro_labyrinth_floor.jpg` — **real photo** of a cathedral labyrinth floor (Chartres-style) or a Celtic/Islamic interlace panel (the continuous-path weave read).
- `02_meso_woven_textile.jpg` — **real photo** of a woven basket / textile / brocade (tiles connecting into paths; the ribbon character).
- `03_micro_moire_mesh.jpg` — **real photo** of overlaid mesh screens / sheer fabric showing moiré (emergent large structure from small repeats — the nesting intuition).
- `04_palette_op_art_tile.jpg` — **real photo** of a bold geometric floor mosaic / azulejo tilework for the high-contrast duotone palette.
- **Porting references (read before coding, FA #73):** Inigo Quilez "Truchet tiles" + his multiscale Truchet Shadertoy; Christopher Carlson's *"Multi-scale Truchet Patterns"*; cite the specific Shadertoy ID in the shader header.
- **Anti (prose-only — no committed image):** the failure mode is a static single-scale black-and-white Truchet checker with no subdivision, no colour, no motion; also anti: a high-contrast flickering strobe (seizure risk) and any feedback-style smear (this preset is crisp).

## A8. Performance & tier

Pure 2D `direct` fragment; very cheap. Bounded subdivision recursion (cap depth ~3–4) keeps cost flat. Well under the Tier-2 ceiling on both tiers. Rubric: **lightweight recommended** (DECISION-NEEDED). Reduced-motion: the drift and flips slow/stop; the static weave still reads.

## A9. Fidelity-uplift arc

- **PG.4.1 (Part B, this session) — reviewable v1:** multiscale Truchet + `spectral_flux` density subdivision + slow drift + silence + palette. The hero complexity-mapping is alive.
- **PG.4.2 — rhythm + colour:** per-beat tile flips (bounded subset, cached grid), per-path hue teams, optional `bass_dev` glow.
- **PG.4.3 — nesting + polish:** deeper subdivision level, finer sub-tile motif variety, chromatic/grain/AA polish, and a possible curl-warp of the tile field for organic flow.

## A10. JSON sidecar sketch

```jsonc
{
  "name": "Truchet Loom", "family": "geometric",
  "concept_tags": ["geometric","hypnotic"], "motion_paradigm": "direct_time_modulation",
  "passes": ["direct"], "duration": 30,
  "certified": false, "rubric_profile": "lightweight",
  "complexity_cost": { "tier1": 0.0, "tier2": 0.0 },
  "visual_density": 0.7, "motion_intensity": 0.6,
  "color_temperature_range": [0.15, 0.9], "fatigue_risk": "medium",
  "transition_affordances": ["crossfade","cut"],
  "section_suitability": ["ambient","buildup","peak","bridge","comedown"]
}
```

---
---

# PART B — SESSION PROMPT (PG.4.1)

## Increment PG.4.1 — Truchet Loom scaffold + density-mapping subdivision (preset increment)

**Objective:** After this session, Phosphene has a new `direct` preset "Truchet Loom" that renders a crisp multiscale Truchet weave whose subdivision depth tracks a smoothed `spectral_flux` (busy music → nested sub-tiles; sparse music → large arcs), scrolls slowly with `arousal`/time, renders a coarse drifting weave at silence, and is registered, compiling, loading, golden-hashed, and covered by a multi-frame test. `certified` stays `false`. Per-beat flips + per-path hue teams are PG.4.2. This is the reviewable v1 of the PG.4 arc in `PG_4_TRUCHET_LOOM.md §A9`.

## 1. Skills to invoke (in order)
- **`preset-session`** — before any `.metal` / sidecar edit.
- **`shader-authoring`** — before any GPU code (port the multiscale Truchet reference; FA #73).
- **`closeout`** — at the end.

## 2. Read-first (exact, ordered)
1. `PG_4_TRUCHET_LOOM.md` (this doc — Part A is the design of record; §A2 mechanic + §A7 porting refs are mandatory).
2. `docs/VISUAL_REFERENCES/truchet_loom/README.md` and every image; the cited Truchet porting references.
3. `docs/ARCHITECTURE.md §GPU Contract Details` — the **direct-pass** fragment binding (`buffer(0)=FeatureVector`, `(5)=SpectralHistory`) and the SpectralHistory layout (for smoothing).
4. `docs/SHADER_CRAFT.md §3` (noise for the grain octave floor), `§8` (procedural texturing — the `Utilities/Texture/` tree: `Procedural.metal`, `Voronoi.metal`), `§14` (esp. §14.1 signal liveness).
5. `PhospheneEngine/Sources/Presets/Shaders/Plasma.metal` and `Nebula.metal` — reference `direct`-pass fragment presets (binding + structure).
6. `PhospheneEngine/Sources/Presets/Shaders/Utilities/Noise/Hash.metal` (`hash_f01`, `hash_f01_2`, `hash_f01_3`, and the `*_2x`/`*_3x` variants) — the per-cell hash for arc orientation. **There is no existing Truchet/weave utility; the multiscale recursion is authored** from the ported reference. For the smoothed flux read, use a slot-6 EMA state buffer or the `SpectralHistory` trail (`Tests/.../Shared/SpectralHistoryBufferTests.swift` shows its usage) — pick one and document the choice in the header.

## 3. Pre-flight invariants (a failed check stops the session)
- `git status` clean on `main`; `swift test --package-path PhospheneEngine` green.
- **ML weights smudged:** `bash Scripts/check_lfs_smudged.sh` prints OK (git-lfs installed; weights are real bytes, not pointer stubs). If it FAILs, `git lfs pull` and re-check — a pointer-stub build passes tests falsely.
- **Design + references already committed** (PG.0, commit `695fc3a8` — verify present): this doc and `docs/VISUAL_REFERENCES/truchet_loom/` (4 images + `README.md`). If either is missing, stop.
- `docs/ENGINEERING_PLAN.md` exists. **There is no Phase PG section yet** — task 1 creates the Phase PG heading + the PG.4.1 row (do not assume one is present).
- Read the current `expectedProductionPresetCount` in `PresetLoaderCompileFailureTest.swift`; confirm it bumps by exactly 1.

## 4. Tasks (each has a done-when)
1. **Plan + scaffold.** Add a **Phase PG** section + a PG.4.1 row to `ENGINEERING_PLAN.md` (none exists yet). Create `Shaders/TruchetLoom.metal` + `TruchetLoom.json` (sidecar per `§A10`) + register + bump `expectedProductionPresetCount` by 1. **Done-when:** app + engine build; `PresetLoaderCompileFailureTest` passes at the new count; preset loads.
2. **Single-scale Truchet (scene fragment).** Implement the base weave: per-cell `hash` (from `hash_f01*`) → arc orientation → quarter-arc distance → path coverage, connecting into continuous paths; duotone palette. **Done-when:** a `RENDER_VISUAL=1` contact sheet shows a crisp continuous-path Truchet weave, non-black.
3. **Multiscale subdivision (the nesting).** Add the per-cell continuous subdivision level: cells above threshold recurse into 2×2 sub-tiles carrying the same arc; crossfade tiles by the fractional level so subdivision animates smoothly (no pop). Cap recursion depth (~3). Author from the ported IQ/Carlson reference (FA #73). Level is a uniform for now (constant). **Done-when:** sweeping the level constant across a contact-sheet series shows tiles smoothly splitting into nested sub-tiles and merging back; the self-similarity reads.
4. **Density = music busyness (hero).** Drive the subdivision level from a **smoothed** `f.spectral_flux` (slot-6 EMA or the `SpectralHistory` flux trail — pick one and document it). **Done-when:** a multi-frame test driving the live direct-pass path across a low-flux vs high-flux fixture shows the weave visibly coarsening vs shattering into nested tiles; the level is smoothed (assert no per-frame flicker — bounded frame-to-frame level delta).
5. **Global drift.** Scroll/rotate the tile field slowly from `arousal` + `accumulated_audio_time`. **Done-when:** the multi-frame test shows continuous gentle flow even at constant density.
6. **Silence state.** Verify `§A5`: coarse large-arc weave, slow drift, non-black, no flips. **Done-when:** the silence contact sheet is non-black and shows big simple ribbons drifting.
7. **Audio routing review.** Deviation/flux primitives only; one primitive per layer; liveness note in the shader header (why `spectral_flux` is the right, alive hero). **Done-when:** `grep` finds no absolute-threshold pattern on raw `f.bass`/`f.mid`; routing matches the PG.4.1 subset of `§A4` (density + drift only — flips/hue-teams/glow are PG.4.2).
8. **Performance.** Run the render-loop performance harness (`PhospheneEngine/Tests/PhospheneEngineTests/Performance/RenderLoopPerformanceTests.swift`) on silence/steady/beat-heavy; record p50/p95/p99; confirm the recursion cap keeps cost flat. **Done-when:** p95 ≤ Tier-2 budget; recorded.
9. **Golden hash — STOP AND REPORT.** Register the golden 3-tuple; do NOT touch other goldens. Produce the M7 contact sheet. **Done-when:** new golden passes; then **stop and report** with the contact sheet.
10. **Closeout.** Invoke `closeout`; 8-part report with the verbatim evidence block, the direct-pass dispatch-path statement, the density-mapping firing evidence (low-vs-high-flux subdivision delta), and perf numbers.

## 5. Do-NOT
- **No absolute thresholds** (D-026 / FA #31) — the density hero is *smoothed `spectral_flux`*, driven from variation, never a fixed threshold on raw `f.bass`.
- **No feedback / `mv_warp`** — this preset is crisp `direct` (D-029; feedback would smear the fine paths — the anti-reference). One paradigm.
- **Do not first-principles the multiscale Truchet** (FA #73) — port the cited IQ/Carlson reference.
- Do not route two layers to the same primitive/timescale (FA #67).
- Do not add per-beat flips, per-path hue teams, or the glow accent here — those are PG.4.2.
- Do not flip `certified`; do not regenerate other goldens; do not commit out-of-scope files.

## 6. Verification commands
```
bash Scripts/check_lfs_smudged.sh
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter "PresetLoaderCompileFailureTest|TruchetLoom|PresetRegressionTests"
RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview 2>&1
swift test --package-path PhospheneEngine --filter RenderLoopPerformance 2>&1
```

## 7. Commit message templates (small commits; local `main`; push only on Matt's "yes, push")
- `[PG.4.1] Presets: scaffold Truchet Loom (direct) + JSON sidecar + registration`
- `[PG.4.1] Truchet Loom: single-scale Truchet weave fragment (ref <shadertoy-id>)`
- `[PG.4.1] Truchet Loom: multiscale subdivision recursion + smooth level crossfade`
- `[PG.4.1] Truchet Loom: spectral_flux density hero (smoothed) + arousal drift`
- `[PG.4.1] Truchet Loom: silence state + golden hash + perf + ENGINEERING_PLAN Phase PG row`

## 8. Closeout format
Invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions: (a) the direct-pass dispatch path the multi-frame tests exercised; (b) density-mapping evidence — subdivision-level delta between a low-flux and high-flux fixture + the smoothing/no-flicker metric; (c) perf p50/p95/p99 from `RenderLoopPerformanceTests`; (d) the M7 contact-sheet path; (e) ENGINEERING_PLAN PG.4.1 status.

## 9. DECISION-NEEDED (surface to Matt at review, product-level)
- **How dense does "busy" get?** *Options:* **Restrained** (max 2 subdivision levels — reads as a clean weave that thickens) vs **Deep** (3–4 levels — dense filigree at peaks, more "psychedelic," busier). *Recommendation:* Restrained for v1 (legible), open Deep in PG.4.3 if peaks feel underwhelming. *Default if silent:* Restrained (cap 3).
- **Palette punch.** *Options:* **Bold duotone-plus-accent** (poster-graphic, recommended) vs **full jewel spectrum** (rainbow ribbons — more "trippy," risks noise). *Recommendation/default:* bold duotone for v1; per-path hue teams explored in PG.4.2.
- **Rubric profile:** `lightweight` (recommended) vs `full`. *Default:* lightweight.
