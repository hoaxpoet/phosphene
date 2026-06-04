# Nimbus — implementation plan (for review)

This is the increment breakdown for review. It is **not** the session prompts. Once you approve the shape and sequencing, each increment becomes a self-contained, paste-ready session prompt in the standard structure (read-first file list → numbered audit-before-implementation tasks → explicit Do NOT → done-when with numeric verification commands → commit cadence). **Per D-064, NB.1+ session prompts cannot be written until NB.0 (reference lock) is signed off** — and NB.0 is substantially complete already (this session).

Companion design doc: `NIMBUS_DESIGN.md` (the Gate 0→6 architecture; the seed for `docs/presets/NIMBUS_DESIGN.md`).

Nimbus is unusual in this queue in one way: **there is no engine increment.** No `NB.ENGINE.*` row. The V.2 Volume utilities Nimbus needs are already injected into every preset's shader (`PresetLoader+Preamble.swift`), so every increment below is `doc` or `preset`. Skein needed two engine increments (canvas-hold, wetness); Nimbus needs none — which also means none of Skein's GPU-stall / shared-format traps apply here.

---

## Locked decisions (from §8 of the design doc + this session)

1. **Tier 2 (M3+) only.** `complexity_cost.tier1` set above the Tier-1 budget so the Orchestrator excludes Nimbus on M1/M2. No Tier-1 fallback in v1. (DESIGN §6.)
2. **Single `direct` paradigm**, no extra passes (D-029 trivially satisfied). No engine work, no new pass-combination, no D-### ratification needed.
3. **Four channels only** — Breath / Pulse / Mood / Page. Per-stem roles, pitch→hue, centroid: cut for v1. (DESIGN §1.2 / §8.2.)
4. **Half-res internal march + MetalFX Temporal** is the budget mechanism, proven at NB.8. (DESIGN §6 / §5.5.)
5. **Silence = dim held breath + faint haze**, not black (D-037); a settle, not a collapse. (DESIGN §1.5.)
6. **Breath primary, Pulse a bounded accent** — the body breathes, it must not strobe per-beat. (DESIGN §5.7 beat-ratio.)
7. **D-139** scoped exception accepts the authored `06_palette_*` swatches for Nimbus only. (Drafted this session; pending paste into `DECISIONS.md`.)
8. **Name *Nimbus*, family `volumetric`** (provisional, your call — §8.1).

---

## Roadmap at a glance

| ID | Title | Type | Depends on | Gate |
|---|---|---|---|---|
| **NB.0** | Reference lock | doc | — | `CheckVisualReferences` green; you sign off trait/anti-ref set *(substantially done)* |
| **NB.1** | Macro maquette | preset | NB.0 | Eyeball (gate-before-gate) **+ budget gate**: one body reads; macro-only ≤ 7 ms Tier 2 |
| **NB.2** ✅ | Meso/micro detail | preset | NB.1 | Contact sheet: billows / filaments / feathering read; not a flat card *(done 2026-06-04)* |
| **NB.3** | Lighting / internal glow | preset | NB.2 | Contact sheet vs hero `08`: reads as luminous backlit gas *(highest aesthetic risk)* |
| **NB.4** | Breath + silence floor | preset | NB.3 | Body mass/luminosity tracks energy deviation; silence non-black |
| **NB.5** | Pulse (embers) | preset | NB.4 | Beat-ratio: ember accent bounded < Breath; reads as ignition, not strobe |
| **NB.6** | Mood | preset | NB.4 | Valence → warm/cool, arousal → turbulence visible across mood fixtures |
| **NB.7** | Page (reorganisation) | preset | NB.4 | Section-boundary fixture shows one slow reorganisation, not a thrash |
| **NB.8** | Performance tranche | preset | NB.3 (NB.5/6/7 landed) | `MTLCounterSet` profile: p95 ≤ 16 ms full-frame, ≤ 7 ms preset; `complexity_cost` set |
| **NB.9** | Certification | preset | all | Acceptance + golden + anti-ref manual + **Matt M7** |

Execution order is top-to-bottom. **NB.5 / NB.6 / NB.7 all branch off NB.4** (independent channels layered on a working Breath) and may be sequenced or reordered freely; NB.8 wants the heaviest channels present (≥ NB.3, ideally embers + turbulence too) so the profile is honest.

---

## Increment detail

### NB.0 — Reference lock
**doc · depends on: — · gate: `CheckVisualReferences` green + your sign-off**

**Goal.** Close Gate 0/1 so NB.1+ prompts cite authoritative reference files. Coarse-to-fine gate; nothing visual is prompted before it.

**Scope.**
- Curated set in `docs/VISUAL_REFERENCES/nimbus/` — 11 files, one per slot, `NN_<scale>_<descriptor>.(jpg|png)`, ≤ 500 KB, regex-clean. *(Locked this session.)*
- README with D-065(c) three-category annotations (mandatory / decorative / actively-disregard) + the "how to read this set" usage caveat (FA #63). *(Finalised this session.)*
- Anti-references authored: uniform fog, solid surface, literal sky, oil-slick rainbow (`05_anti_*`). *(Locked this session.)*
- §2 trait matrix finalised against the locked images. *(In DESIGN §2.)*
- D-139 logged for the authored `06_palette_*` swatches. *(Drafted this session; paste into `DECISIONS.md`.)*

**Out of scope / Do NOT.** No code. Do not begin NB.1 prompting until green + signed off.

**Key files.** `docs/VISUAL_REFERENCES/nimbus/*`, `docs/presets/NIMBUS_DESIGN.md`, `DECISIONS.md` (D-139).

**Done-when.**
- `swift run --package-path PhospheneTools CheckVisualReferences` green for the nimbus folder.
- Trait matrix + anti-references reviewed and approved by you.
- D-139 in `DECISIONS.md`.

---

### NB.1 — Macro maquette
**preset · depends on: NB.0 · gate: eyeball (gate-before-gate) + budget gate**

**Goal.** A single coherent volumetric body suspended in the dark void, framed to `01_macro_coherent_body`, with slow time-based drift and minimal single-scatter lighting. No audio. If one body does not read against the void — or if the march does not fit budget — the concept stops or re-scopes here.

**Scope.**
- `NimbusState.swift` (the established `*State.swift` pattern): time / drift phase, `rng_seed` hook (fixed seed acceptable for the spike; audit whether track identity is reachable on apply — full wiring deferred to NB.4).
- `Nimbus.metal`: view-ray setup; procedural body density (FBM + `voronoi_smooth`) **shaped to a bounded body** (centre of mass + falloff → silhouette, explicitly NOT a frame-filling field); single-scatter march (`ParticipatingMedia` + `HenyeyGreenstein`) with a minimal light set; composite over the void.
- `Nimbus.json`: `passes: []` (direct), family `volumetric`, `certified: false`, `complexity_cost.tier1` set above Tier-1 budget (exclude on M1/M2 from day one).
- Debug: density-only view + step-count heatmap (DESIGN §5.6).
- **Budget probe:** capture macro-only per-preset GPU ms via `MTLCounterSet.timestampGPU` on the steady-mid fixture.

**Out of scope / Do NOT.** No audio routing of any kind. No meso/micro detail cascade. No internal-glow recipe (minimal lighting only). No palette / mood mapping. No embers. **Do NOT let the density fill the frame** (that is the `05_anti_uniform_fog` failure — keep negative space from the first commit).

**Key files.** `Sources/Presets/NimbusState.swift`, `Sources/Presets/Shaders/Nimbus.metal`, `Sources/Presets/Nimbus.json`, `VisualizerEngine+Presets.swift` (wiring), `PresetLoaderCompileFailureTest.swift` (`expectedProductionPresetCount` +1).

**Done-when.**
- App build green; `expectedProductionPresetCount` incremented; preset loads.
- `RENDER_VISUAL=1` contact sheet (`PresetVisualReviewTests`) across ≥4 fixtures shows **one coherent body** with a clear silhouette and dominant negative space — density-only view confirms it is not uniform fog.
- **Budget gate:** macro-only per-preset GPU ≤ 7 ms at 1080p Tier 2 (at the intended half-res march if already in place). **If > 7 ms, stop and report** — a march that can't fit at the maquette stage won't fit certified (DESIGN §6).
- **Eyeball gate:** the body reads as a luminous gaseous mass in a void, framed like `01_macro_coherent_body`.

---

### NB.2 — Meso/micro detail
**preset · depends on: NB.1 · gate: contact sheet (billows / filaments / feathering)**

**Goal.** Add body-scale and fine-scale structure so the volume reads with depth — billows and lobes, peeling filaments, edge feathering, interior turbulence — matching `02_meso_billow_and_filament` and `03_micro_wisp_feathering`. Still no audio.

**Scope.**
- Layered density detail: secondary FBM octaves / domain warp for billows + filaments; edge feathering so the body dissolves into the void (no hard cut); interior turbulence term (amplitude on a debug scalar for now — real arousal routing in NB.6).
- Tune step count / detail vs cost (feeds NB.8).
- `SHADER_CRAFT.md` entry for the volumetric body-shaping + detail technique (first V.2-consumer recipe).

**Out of scope / Do NOT.** No audio routing (drive turbulence from a debug scalar). No glow recipe yet (NB.3). **Do NOT add detail by raising global density** (that fills negative space → uniform-fog failure); detail comes from structure, not opacity.

**Key files.** `Sources/Presets/Shaders/Nimbus.metal`, `Sources/Presets/NimbusState.swift`, `SHADER_CRAFT.md`.

**Done-when.**
- Contact sheet shows billows + filaments + edge feathering + interior variation; the body reads as volume with depth, not a flat card.
- Negative space preserved (density-only view still shows a bounded body).
- Does not match `05_anti_solid_surface` (still translucent at edges) — manual.

**Status: ✅ done (2026-06-04).** All three done-when met: body reads as volume with depth (distinct billows + valleys + peeling tendrils + feathered edges); density-only guard shows a bounded body with dominant negative space; edges translucent (not anti-solid-surface). Built via multiplicative billow carve + translucent-σ depth + domain-warp-on-texture-coords micro filaments + multiplicative rim feathering; interior turbulence on the `kNimbusTurbulence` knob (NB.6 wires arousal). Budget macro+meso+micro p50 1.65 ms @1080p (NIMBUS_DESIGN §6.2). Recipe in SHADER_CRAFT §6.5. (NB: no `NimbusState.swift` this increment — state lands with audio at NB.4/NB.6; turbulence is a compile-time constant for now.) `certified:false` unchanged.

---

### NB.3 — Lighting / internal glow
**preset · depends on: NB.2 · gate: contact sheet vs hero `08` (highest aesthetic risk)**

**Goal.** The signature look: the body lit so it reads as luminous backlit gas (hero `08_lighting_internal_glow`), with soft self-shadowing through the denser mass (`08_lighting_self_shadow`). This is where the preset earns its identity and where iteration concentrates.

**Scope.**
- Light set: single key + ambient, biased to internal / backlit so forward-scatter (HG) produces the glow; emission-term scaffold for embers (lit by a debug trigger now; real onset routing in NB.5).
- Self-shadow: attenuate in-scatter through accumulated density (cheap single-light shadowing, not a second march if budget-prohibitive).
- ACES composite; faint-haze void floor (non-black) established here so silence (NB.4) has its ground.

**Out of scope / Do NOT.** No audio routing (lighting responds to nothing yet; embers on a debug trigger). No palette / mood (single neutral-cool baseline temperature; valence mapping is NB.6). **Do NOT make the body read as an opaque lit surface** (`05_anti_solid_surface`) — glow comes from light *through* the medium, not a surface highlight on it.

**Key files.** `Sources/Presets/Shaders/Nimbus.metal`, `Sources/Presets/Nimbus.json` (lighting params), `SHADER_CRAFT.md` (internal-glow recipe).

**Done-when.**
- Contact sheet reads as a luminous backlit gaseous body comparable to hero `08`; self-shadowing gives interior depth.
- Does not match any `05_anti_*` (manual; especially solid-surface and oil-slick).
- Per-preset GPU re-checked (lighting is the cost step before the formal NB.8 tranche).

---

### NB.4 — Breath + silence floor
**preset · depends on: NB.3 · gate: mass/luminosity tracks energy deviation; silence non-black**

**Goal.** Wire the primary continuous channel — broadband energy **deviation** (D-026) → body mass/extent + luminosity — and the dim-held-breath silence floor (D-037). The body starts breathing with the music.

**Scope.**
- Breath routing: broadband energy deviation → body extent + luminosity (DESIGN §5.4); smoothed in state (breath integrator).
- Silence floor: as energy-deviation goes quiet, settle to a dim slow breath + faint haze; pause `accumulated_audio_time`-linked drift; **non-black** (D-037).
- Wire the **seed** to track identity (the SHA hook scaffolded in NB.1) → deterministic body per track.
- Stem warmup blend (`smoothstep(0.02,0.06,totalStemEnergy)`, D-019) **only if** a `stems.*` term is read — Breath uses broadband, so warmup is N/A unless a per-stem term is introduced; note it either way.
- Register Nimbus in **PresetSessionReplay** (routes) — deferred until now because routing must exist to verify (Dragon Bloom Spike-2/3 / Skein.3 pattern).

**Out of scope / Do NOT.** No Pulse / embers (NB.5), no Mood (NB.6), no Page (NB.7). Do NOT use absolute-threshold audio patterns (D-026 deviation only). Do NOT write valence/arousal anywhere yet.

**Key files.** `Sources/Presets/Shaders/Nimbus.metal`, `Sources/Presets/NimbusState.swift`, `Sources/Presets/Nimbus.json` (Breath routing), PresetSessionReplay registration, `PresetAcceptanceTests.swift`.

**Done-when.**
- Replay / acceptance: body mass + luminosity track the continuous energy-deviation signal (loud → larger/brighter, sparse → smaller/dimmer); zero-delay feel.
- Silence fixture: dim breathing body + haze, measurably **non-black**; drift paused.
- Same track → same starting body (seed determinism).

---

### NB.5 — Pulse (embers)
**preset · depends on: NB.4 · gate: beat-ratio (accent bounded < Breath)**

**Goal.** On a beat onset, kindle one ember deep in the body and flare it outward — the accent layer. It must read as ignition, never as a per-beat strobe.

**Scope.**
- Composite onset pulse → spawn one ember (seeded interior position, age, intensity); small active cap (≈4–8, DESIGN §8.3); flare-and-decay animated in state + emission term in shader.
- Bound the accent: ember contribution capped so Breath remains the dominant luminosity signal.

**Out of scope / Do NOT.** No Mood, no Page. **Do NOT drive body mass from onsets** (mass is Breath's; onsets only kindle embers). Do NOT let ember density rise to a strobe — check the beat-ratio criterion each iteration (FA #33: rhythm lives in Breath, not the spark).

**Key files.** `Sources/Presets/Shaders/Nimbus.metal`, `Sources/Presets/NimbusState.swift`, `Sources/Presets/Nimbus.json`, `PresetAcceptanceTests.swift`.

**Done-when.**
- Beat-heavy fixture: visible ember flares on onsets; ember (Pulse) luminosity energy measurably **below** Breath energy by the set margin — it breathes, it doesn't strobe.
- Ember cap respected; flares decay cleanly.

---

### NB.6 — Mood
**preset · depends on: NB.4 (NB.5 optional) · gate: mood fixtures show warm/cool + turbulence travel**

**Goal.** The slow colour-of-mood channel: valence → body colour temperature; arousal → internal turbulence amplitude.

**Scope.**
- Valence → colour temperature (cool indigo/violet baseline ↔ warm gold/amber peak, the `06_palette_*` axis); arousal → turbulence amplitude (placid ↔ roiling) + ember vigour. **Smoothed in state — never via `setFeatures` (FA #25).**
- Replace the NB.2/NB.3 debug turbulence scalar with the arousal route.

**Out of scope / Do NOT.** No Page, no per-stem tint (V2, §8.2). Do NOT write valence/arousal through `setFeatures`. Do NOT let mood introduce a fast colour flicker — temperature drifts slowly.

**Key files.** `Sources/Presets/NimbusState.swift` (mood smoothers), `Sources/Presets/Shaders/Nimbus.metal` (temperature + turbulence), `Sources/Presets/Nimbus.json`.

**Done-when.**
- Contact sheet across high/low-valence fixtures: visibly warm vs cool body.
- High/low-arousal fixtures: visibly different turbulence amplitude.
- No first-frames colour pop; transitions smooth (state-smoothed).

---

### NB.7 — Page (reorganisation)
**preset · depends on: NB.4 · gate: section-boundary fixture shows one slow reorganisation**

**Goal.** The rarest channel: at a predicted section boundary, the body performs one slow mass reorganisation — felt more than seen.

**Scope.**
- `StructuralPrediction` boundary → trigger a single reorganisation: redistribute the density field's shaping toward a new silhouette, interpolated over ~1–2 s (DESIGN §8.4). State carries target + interpolation `t`.

**Out of scope / Do NOT.** Do NOT reorganise per-section-beat or per-onset (Page is rare). Do NOT make it a hard cut / new body — it is a slow redistribution of the same body.

**Key files.** `Sources/Presets/NimbusState.swift` (reorg state), `Sources/Presets/Shaders/Nimbus.metal` (silhouette interpolation), `Sources/Presets/Nimbus.json`.

**Done-when.**
- Section-boundary fixture: one slow, legible reorganisation at the boundary; no thrash between boundaries.

---

### NB.8 — Performance tranche
**preset · depends on: NB.3 (with NB.5/6/7 landed for an honest profile) · gate: `MTLCounterSet` profile within budget; `complexity_cost` set**

**Goal.** Make Nimbus fit the Tier-2 budget and set the Orchestrator cost sidecar. This is the increment that proves the half-res + MetalFX lever and locks Tier-1 exclusion.

**Scope.**
- **Audit / validate** the half-resolution internal march + **MetalFX Temporal** upscale to 1080p is actually wired (not just planned) — Arachne V.8.1 precedent. If absent, wire it here.
- Step-count cap + early-out on accumulated opacity; bounded body extent to skip empty-space steps.
- Profile p50/p95/p99/max via `MTLCounterSet.timestampGPU` on silence / steady-mid / beat-heavy fixtures (`PresetPerformanceTests`).
- Set `complexity_cost.tier2` from the measured profile; confirm `complexity_cost.tier1` is above Tier-1 budget (Orchestrator excludes on M1/M2).

**Out of scope / Do NOT.** No new visual features at the perf tranche. **Do NOT add a Tier-1 fallback** (v1 is Tier-2-only by decision). Do NOT certify if p95 exceeds budget — re-scope detail / steps instead.

**Key files.** `Sources/Presets/Nimbus.json` (`complexity_cost`, quality params), `Sources/Presets/Shaders/Nimbus.metal` (march res / step cap / early-out), `PresetPerformanceTests.swift`, MetalFX wiring (audit).

**Done-when.**
- Per-preset GPU ≤ 7 ms; full-frame p95 ≤ 16 ms; drops (>32 ms) ≤ 1 % on Tier 2 fixtures.
- `complexity_cost.tier1` > Tier-1 budget verified by an Orchestrator test (Nimbus excluded on M1/M2); `complexity_cost.tier2` set from measurement.

---

### NB.9 — Certification
**preset · depends on: all · gate: acceptance + golden + anti-ref manual + Matt M7**

**Goal.** Certify Nimbus and flip `certified: true`.

**Scope.**
- **Acceptance invariants** (`PresetAcceptanceTests`, DESIGN §5.7): silence-non-black; breath-primacy / beat-ratio (Pulse < Breath margin); body-coherence (single bounded mass, negative space preserved, ≠ uniform fog); mood travel (warm/cool + turbulence).
- Golden dHash regression entry for Nimbus.
- **Anti-reference check:** manual (the automated anti-reference dHash gate is a Missing engine capability — same as Arachne / Skein — so this stays an M7 judgement).
- `ENGINEERING_PLAN.md` rows marked landed; `FidelityRubric` profile set (full-rubric — Nimbus is an artistic preset, not lightweight).
- **Matt M7:** live, on real music, ≥5 tracks + a local file — body-must-breathe / glow-must-read. Non-negotiable, non-bypassable.

**Out of scope / Do NOT.** No new features at cert. Do NOT flip `certified: true` before M7 passes.

**Key files.** `PresetAcceptanceTests.swift`, `PresetRegressionTests.swift` (golden), `Sources/Presets/Nimbus.json` (`certified`, `rubric_profile`), `ENGINEERING_PLAN.md`, `FidelityRubric` wiring.

**Done-when.**
- Acceptance green; golden registered; anti-reference manual check clean.
- M7 verdict: pass.

---

## Sequencing, cut-lines, and risk

- **Critical path:** NB.0 → NB.1 → NB.2 → NB.3 → NB.4 → NB.8 → NB.9. NB.5 / NB.6 / NB.7 are independent channels branching off NB.4 and can be sequenced in any order — or cut/deferred individually without blocking cert. (A certified Nimbus wants at least Breath + Pulse + Mood; **Page is the most cuttable to V2**.)
- **Two risk concentrations, both early:**
  - **NB.1 — feasibility.** The unprecedented thing is *cost*: no preset has marched a volume in production. The NB.1 budget gate exists to fail fast — if the macro-only march can't fit 7 ms (even at half-res), escalate to "this preset needs a staged volume pass" or "re-scope," per the §5.5 fallback, rather than tuning forward. (CC_DESIGN flagship-risk lesson / FA #58: escalate non-viability, don't grind.)
  - **NB.3 — aesthetics.** The internal-glow recipe is where Nimbus reads as luminous gas or as a lit blob. Budget iteration here (cf. Arachne clipart, Dragon Bloom "not seeing petals").
- **The uniform-fog trap runs through every increment.** Negative space + a bounded body with a centre of mass is the load-bearing property; the **density-only debug view is the guard**, re-checked in every preset increment's done-when. Detail and breath must never be bought by raising global opacity.
- **No engine increments = no GPU-stall traps.** Unlike Skein (two gated engine increments to avoid the D-137 preset-transition beachball), Nimbus touches no shared pipeline code — it is config + one shader + one state file.
- **MetalFX is an assumption, validated at NB.8, not assumed earlier** — but the whole Tier-2 budget rests on it, so if NB.8 finds it unwired the fix (wire MetalFX Temporal) is bounded, not a redesign. The Tier-1 *exclusion* removes the hardest budget constraint entirely.

## Documentation write-backs (house culture)

- **DECISIONS.md** — D-139 (authored `06_palette_*` swatches, this session); plus a D-### for **Tier-1 exclusion via `complexity_cost`** if you want the rationale on the record (recommend yes — it's a reusable pattern for future heavy presets, and the first formal "this preset is Tier-2-only" decision).
- **ENGINEERING_PLAN.md** — a short Nimbus phase entry (first `volumetric`-family preset, like Phase CC) + increment rows per increment as they land.
- **SHADER_CRAFT.md** — the volumetric body-shaping + detail recipe (NB.2) and the internal-glow recipe (NB.3) — the first V.2-Volume-consumer entries; a §9.x per-preset budget note for the half-res-march pattern.
- **`docs/presets/NIMBUS_DESIGN.md`** — seeded from `NIMBUS_DESIGN.md` at NB.0, kept current.
- **RENDER_CAPABILITY_REGISTRY.md** — note the V.2 Volume utilities move from "Supported, no production consumer" to "Supported, consumed by Nimbus" once NB.1 ships.

## To proceed

If the breakdown and sequencing look right, I'll write the first paste-ready session prompt (**NB.1**) in your standard structure — referencing `NIMBUS_DESIGN.md` + the reference folder in its read-first list, **not** authoring the design doc mid-session. NB.0 is reference-independent and effectively done; the moment you sign off the reference set + DESIGN, NB.1 can go to Claude Code.

> Note on the earlier NB.1 draft: it needs exactly two fixes to conform — add `NIMBUS_DESIGN.md` + the references to its read-first list, and **remove the "author Nimbus_DESIGN.md" task** (Claude Code references the design, it does not write it). I'll regenerate it from this plan on your word.
