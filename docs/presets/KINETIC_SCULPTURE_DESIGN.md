# Kinetic Sculpture — Rebuild Design (KSRB)

**Status:** rebuild kickoff, 2026-07-19. Supersedes the never-executed "V.12 materials uplift" framing — that treated the geometry as fixed and lifted only materials, but the viability gate (2026-07-19) found the *geometry itself* is the problem: the shipped periodic 3-axis rod grid (`ks_rep`, `KS_CELL=2.0`) is the preset's own **anti-reference** ("regular geometric grid… reads as engineering drawing, not sculpture"). This rebuild replaces the geometry.

**References:** `docs/VISUAL_REFERENCES/kinetic_sculpture/README.md`. Hero = `01_macro_radiating_strand_lattice.jpg` (Lippold, *Flight*, 1963 — cones of taut radiating members converging on a central spherical hub). Supporting: `02` (Wings of Welcome, interlocking rods), `03` (Gabo linear construction — taut strands generating curved volume through tension).

**Feasibility:** GREEN. The thin-strand ray-march spike (2026-07-19) proved the Lippold silhouette renders cleanly on the existing march loop with **no cost blowup** (max 45–53/128 steps, form legible to sub-pixel radius) because the relative hit-epsilon `0.001·t` implicitly fattens sub-pixel features; the one defect (foreshortened-strand shimmer <2px) is fully rescued by an **emissive glow core** (additive coverage ∝ ray-to-strand min-distance), which also *is* the tensioned-wire-catching-light look. See ENGINEERING_PLAN §roster-survey KS-spike entry; contact sheet was reviewed.

---

## 1. Concept

A single abstract wire sculpture in a gallery interior: **cones of taut, luminous strands radiating from spherical hubs and converging** (Lippold *Flight*). Tension is the visual signature — the strands read as under load, catching a warm key light, set against a cool IBL environment that the polished members reflect. Not a grid; not figurative; irregular and multi-axial per refs 01–03.

## 2. Musical role — **PROPOSED, needs Matt's sign-off before shader authoring**

The gate found the shipped KS musical role *marginal* ("one real hook — mercury melt on bass — poorly staged on an infinite identical grid; twist runs off a clock, not the music"). The rebuild is the chance to fix it, not preserve it. The radiating-strand form is literally string-like — strands under tension are *strings*, and strings are plucked. That gives a strong, legible role:

> **At rest the strands hang taut and dark. The whole radiating fan splays wider as the track's sustained energy swells and draws tight as it falls (continuous); and on each bar downbeat a luminous shimmer plucks hub-to-tip along the strands (cached BeatGrid, bounded). The listener sees the music's intensity as the sculpture's openness, and the downbeat as a plucked-wire flash of light.**

- **Layer 1 (primary, continuous):** sustained energy envelope → cone splay / strand tension. Deviation primitives (`bass_att_rel` / `mid_att_rel`, D-026), never absolute thresholds (FA #31). Silence → strands taut, fully present, materials lit (D-019 / D-037 — never black, never fully static).
- **Layer 4 (accent):** bar downbeat on the cached `BeatGrid` (`barPhase01`), **not** raw `beat_bass` (the KS README + Inc 3.5.4.5 flag a cooldown phase-lock issue on live onsets) → a bounded hub→tip luminance shimmer (D-157: bounded per-beat footprint, steady global luminance; flash-safe by construction — it's a traveling highlight, not a full-field flash). Cold-start-safe (cached grid).
- **One primitive per layer (FA #67):** tension ← energy envelope; pluck ← downbeat phase. No sharing.
- **Layer 3 (slow, optional):** spectral centroid → warm/cool of the key light. Lag-tolerant.

*Open concept question for Matt:* single sculpture with whole-field tension + downbeat pluck (recommended — simple, legible, avoids the Ricercar per-section over-reach), **or** multiple hubs each assigned to a stem/register (richer but risks the Ricercar "4 instruments = 4 things, reads as a legend" failure). Recommend the single-sculpture reading.

## 3. Geometry

- **Hub-and-strand radiating SDF** replacing `ks_rep`. One or two spherical hubs; N strands per hub fanning to a convergence ring/opposing hub (the *Flight* bicone the spike used). Strands = `sd_capsule` unions (`min`), **emissive-cored** (additive glow ∝ ray-strand proximity — the spike's rescue). Irregular per-strand length/tilt/cross-section (meso variation — README "no two struts identical"; the anti-ref is uniformity).
- **Members ≥ ~2px screen width** carry material via distance-fatten; sub-pixel strands carry the emissive core + existing bloom. March budget unchanged (spike: bounded).
- Slow global rotation for the "kinetic" reading (a real spatial orbit, **not** the old `accumulated_audio_time` twist-off-a-clock).

## 4. Materials (3, per README §12.1)

Reconcile the shipped shader (brushed aluminum / frosted glass / **liquid mercury**) with the README (brushed aluminum / frosted glass / **polished chrome**). Mercury was the *grid connector* concept — it does not apply to a strand sculpture. **Propose: chrome** (README-aligned): strands = **polished chrome / brushed aluminum** (anisotropic streak specular §4.2/4.1, `fbm8` roughness), hubs = **frosted glass** (§4.5, SSS-like emission — pairs with the strand glow cores). Chrome mandates a detailed **IBL environment** to reflect (README anti-ref: "chrome against blank env = dull plastic"). *Flag for Matt: chrome vs keep-mercury, and family `geometric` (sidecar) vs `abstract` (README) — reconcile at KSRB.1.*

## 5. Increment plan

- **KSRB.1** — reference-lock (this doc) + first **geometry LOOK render**: hub-and-strand radiating SDF + emissive cores, no audio, rendered through the real ray-march pipeline. Gate: Matt's eye on the silhouette vs ref 01 + the shimmer-in-motion confirm (rotating camera — the spike's one caveat). *Also resolve the chrome/family open questions here.*
- **KSRB.2** — materials + IBL environment (chrome reflectivity, brushed-alu anisotropy, frosted-glass hubs, `fbm8` detail cascade).
- **KSRB.3** — audio routing (§2 role): continuous tension + downbeat pluck; deviation primitives; D-019 silence fallback; `audio_routes` sidecar manifest + RouteCoverageTests (D-180); one-primitive-per-layer table.
- **KSRB.4** — motion/flash pass: confirm the pluck reads in motion, flash-safe measurement (MultiPassFlashHarness), wash/steady-luminance check.
- **KSRB.5** — mood/arc + polish.
- **KSRB.6** — certification (Matt M7 + flip `certified:true` + arm rubric/flash/route gates, mirroring the Nacre/Glaze cert pattern).

## 6. Gate registration reminders (new-geometry preset)

The geometry rewrite is contained in `KineticSculpture.metal` (KS already ships as a ray-march preset, so no new pipeline/count change — `expectedProductionPresetCount` stays 26). Re-baseline: `PresetRegressionTests` golden for Kinetic Sculpture (geometry changed → expect a new hash, regen deliberately), the ray-march visual-review harness entry (already present), and the Module Map row (file exists, description updates). No app factory/registry change (data-driven ray-march).

## 7. Open questions for Matt (sign-off before KSRB.1 shader authoring)

1. **Musical-role concept** (§2) — is the "tension = intensity, downbeat = plucked-wire flash" reading the one to build? Single sculpture vs per-hub-stem.
2. **Third material** — chrome (README) vs keep liquid mercury (shipped).
3. **Family** — `abstract` (README) vs `geometric` (sidecar).
