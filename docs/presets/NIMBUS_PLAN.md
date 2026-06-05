# Nimbus — implementation plan (for review)

This is the increment breakdown for review. It is **not** the session prompts. Once you approve the shape and sequencing, each increment becomes a self-contained, paste-ready session prompt in the standard structure (read-first file list → numbered audit-before-implementation tasks → explicit Do NOT → done-when with numeric verification commands → commit cadence). **Per D-064, NB.1+ session prompts cannot be written until NB.0 (reference lock) is signed off** — and NB.0 is substantially complete already (this session).

Companion design doc: `NIMBUS_DESIGN.md` (the Gate 0→6 architecture; the seed for `docs/presets/NIMBUS_DESIGN.md`).

Nimbus needs **one small engine touch** (Matt-approved 2026-06-04): a baked **Perlin-Worley 3D texture** in `TextureManager` (NB.3.0), required because the reference billows need Worley noise that the existing Perlin-only `noiseVolume` can't provide, and computing it per-step would blow the budget (§6.1). Everything else is `preset` — the V.2 Volume utilities are already injected into every preset's shader (`PresetLoader+Preamble.swift`). (The original plan claimed "no engine increment"; the NB.2 soft-blob result and the §0 direction reset changed that.)

---

## Locked decisions (from §8 of the design doc + this session)

1. **Tier 2 (M3+) only.** `complexity_cost.tier1` set above the Tier-1 budget so the Orchestrator excludes Nimbus on M1/M2. No Tier-1 fallback in v1. (DESIGN §6.)
2. **Single `direct` paradigm**, no extra passes (D-029 trivially satisfied). One small engine touch only: the NB.3.0 Perlin-Worley texture bake.
3. **The look is a ported cloud technique** (HZD / "Nubis": Perlin-Worley billows + Beer-Powder + cone self-shadow), not the NB.1/NB.2 Perlin-FBM march. Port, don't hand-roll (DESIGN §0).
4. **Two music drivers only** — Energy (bloom + flow) and Mood (colour + flow-agitation). **Nothing on the beat.** Per-beat ember and section reorganisation are CUT (DESIGN §1.3).
5. **Silence = small, dim, slowly-drifting body + faint haze**, not black (D-037); a settle, not a collapse. (DESIGN §1.5.)
6. **Energy is the hero, momentum-smoothed** — bloom + flow track the continuous broadband energy, never the beat (FA #4 / FA #33). (DESIGN §1.3.)
7. **D-139** scoped exception accepts the authored `06_palette_*` swatches for Nimbus only.
8. **Name *Nimbus*, family `volumetric`**.

---

## Roadmap at a glance

| ID | Title | Type | Depends on | Gate |
|---|---|---|---|---|
| **NB.0** | Reference lock | doc | — | `CheckVisualReferences` green; you sign off trait/anti-ref set *(substantially done)* |
| **NB.1** | Macro maquette | preset | NB.0 | Eyeball (gate-before-gate) **+ budget gate**: one body reads; macro-only ≤ 7 ms Tier 2 |
| **NB.2** ✅ | Meso/micro detail | preset | NB.1 | *Shipped, but look superseded by NB.3 (Perlin-FBM can't make billows). Test parity + debug views + budget probe reused.* |
| **NB.3** ✅ | The look (cloud-port) | preset + 1 engine touch | NB.2 | *Shipped 2026-06-05, Matt-approved on the contact sheet: cool billowing luminous backlit gas.* |
| **NB.4** ✅ | Energy: bloom + flow + silence | preset | NB.3 | *Shipped 2026-06-05 — bloom→size/brightness/flow + non-black silence floor; nothing on the beat. Pending Matt's live musical-feel sign-off.* |
| **NB.5** ✅ | Beat: stem lobes (the band plays the body) | preset | NB.4 | *Shipped 2026-06-05 (D-141) — reverses "nothing on the beat"; each stem heaves the single body (drums punch, bass↓/lead↑/other↔). Pending Matt's live sign-off.* |
| **NB.6** | Mood | preset | NB.5 | Valence → cool/warm, arousal → flow-agitation visible across mood fixtures |
| ~~**NB.7**~~ | ~~Page (reorganisation)~~ | — | — | ❌ **CUT** — no section reorganisation in v1 (DESIGN §1.3) |
| **NB.8** | Performance tranche | preset | NB.3 + NB.4/6 | `MTLCounterSet` profile (re-measure cone-shadow cost): p95 ≤ 16 ms full-frame, ≤ 7 ms preset; `complexity_cost` set |
| **NB.9** | Certification | preset | all | Acceptance + golden + anti-ref manual + **Matt M7** |

Execution order is top-to-bottom and largely linear now: **NB.3 (the look) → NB.4 (energy swell) → NB.5 (beat: stem lobes) → NB.6 (mood) → NB.8 (perf) → NB.9 (cert)**. NB.3 was the fidelity gate; NB.5 (reinstated, D-141) is the musical-feel gate — the energy-only NB.4 was too subtle on real music, so the beat came back as per-stem lobes.

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

### NB.3 — The look (cloud-port)
**preset · depends on: NB.2 · gate: matches the reference packet — the whole fidelity fight (HIGHEST risk)**

**Goal.** Replace the NB.1/NB.2 Perlin-FBM density + ad-hoc lighting with the ported **HZD / "Nubis"** volumetric-cloud technique, so the body finally reads like the packet: a cool gaseous mass with cauliflower **billows**, self-shadowed 3D depth, a luminous backlit glow, feathered edges into the void. Root cause of the NB.2 soft blob (researched + sourced, DESIGN §0): Perlin noise can't make billows (needs **Worley / Perlin-Worley**), and depth/glow needs **Beer-Powder + cone self-shadow**, not a single key. **Port the technique; don't hand-roll** (FA #70/#73).

**Scope (sub-increments, infra first).**
- **NB.3.0 (infra).** Bake a tileable **Perlin-Worley 3D texture** in `TextureManager` (the one Matt-approved engine touch), generated by the existing GPU noise-gen path; bind via `bindTextures` so it auto-binds everywhere (test paths already get the full noise set, NB.2 Task 1). Own `.x` commit before any shader work.
- **NB.3.1 (density).** Rebuild `nimbus_density`: Perlin-Worley base (billows) + Worley detail erosion + edge gradient, shaped to a bounded body by the existing envelope. Verify real billows in the density-only view.
- **NB.3.2 (lighting).** Port the lighting: **Beer-Powder × HG phase × ~6-step cone self-shadow march** toward the key → luminous, self-shadowed, backlit billows. ACES; faint-haze void floor (non-black).

**Out of scope / Do NOT.** No audio routing (NB.4+). No palette/mood (single cool baseline; valence is NB.6). **No per-step computed noise** — Perlin-Worley is a TEXTURE SAMPLE (§6.1 budget rule). **Do NOT hand-roll** — port the published loop, adapt only what differs (one bounded body vs sky slab; our cool tint; Tier-2 budget).

**Key files.** `Sources/Renderer/TextureManager.swift` (+ a Perlin-Worley gen kernel), `Sources/Presets/Shaders/Nimbus.metal`, `Sources/Presets/Nimbus.json`, `SHADER_CRAFT.md` (extend §6.5 with the Beer-Powder + cone-shadow recipe).

**Done-when.**
- Contact sheet reads as a cool, billowing, luminous backlit gaseous body comparable to the packet (`01`/`02`/`03`/`08`); billows + self-shadow depth present in both the lit and density-only views.
- Does not match any `05_anti_*` (manual; especially solid-surface and uniform-fog).
- Per-preset GPU re-measured — the cone-shadow cost is the new budget unknown (NB.8 formalises).

---

### NB.4 — Energy: bloom + flow + silence floor
**preset · depends on: NB.3 · gate: bloom + flow track continuous energy; silence non-black; nothing on the beat**

**Goal.** Wire the one fast channel — broadband energy **deviation** (D-026) → a momentum-smoothed `bloom` driving the body's size, brightness, and gas-flow rate — plus the dim/small/slow silence floor (D-037). The body starts moving with the music.

**Scope.**
- `NimbusState`: `E = (bass_att_rel + mid_att_rel + treb_att_rel)/3` → a **fast-attack (~150 ms) / slow-release (~400 ms)** follower → `bloom` (DESIGN §5.4).
- `bloom` → body size (~+45 %) + brightness (~+80 %) + flow rate (churn ~1×→3.5×). All three off the one signal, read as one physical event.
- Silence floor: as energy goes quiet, settle to a small/dim/slow-drifting body + faint haze; pause `accumulated_audio_time`-linked flow; **non-black** (D-037).
- Wire the **seed** to track identity (the SHA hook scaffolded in NB.1) → deterministic body per track.
- Register Nimbus in **PresetSessionReplay** (routes) — deferred until now because routing must exist to verify.

**Out of scope / Do NOT.** **No beat field (`beat_*`) — nothing on the beat** (DESIGN §1.3). No Mood (NB.6). Do NOT use absolute-threshold audio (D-026 deviation only). Do NOT write valence/arousal yet.

**Key files.** `Sources/Presets/Shaders/Nimbus.metal`, `Sources/Presets/NimbusState.swift`, `Sources/Presets/Nimbus.json`, PresetSessionReplay registration, `PresetAcceptanceTests.swift`.

**Done-when.**
- Replay / acceptance: size + brightness + flow visibly track continuous energy (loud → bigger/brighter/faster, sparse → smaller/dimmer/slower) with fast-attack/slow-release momentum; **no `beat_*` read** (source-verified).
- Silence fixture: small dim slowly-drifting body + haze, measurably **non-black**; flow eased.
- Same track → same starting body (seed determinism).

**Status: ✅ done (2026-06-05) — pending Matt's live manual-validation sign-off on the musical feel.** `NimbusState.swift` (`Sources/Presets/Nimbus/`) fast-attack/slow-release follower → `bloom`; `flowPhase` (Double accumulator) at a bloom-modulated rate; 16-byte `NimbusStateGPU` at fragment buffer(6). Shader consumes `bloom` for body extent (uniform `bodyScale` inflation, +45 % floor→peak) + luminosity (`bright`, +80 %) and `flowPhase` for the gas drift (1×→3.5×); silence floor = the NB.3 backlit look smaller/dimmer/slower over a faint non-black cool haze (D-037). Wired live (`setDirectPresetFragmentBuffer` + `setMeshPresetTick`); `reset()` on preset apply + track change. **No beat / no mood** (source-verified). Gates: `NimbusBloomFollowerTest` (multi-frame follower feel + render-tracks-bloom through the live direct path — the firing-evidence diagnostic), `PresetVisualReviewTests` silence/mid/energy fixtures, `NimbusBudgetProbeTests` slot-6 bind; 1380 engine tests green; SwiftLint clean; app build clean; count 19; budget p50 2.66 ms (NIMBUS_DESIGN §6.4). First two done-when met (contact sheet + follower test). The third (seed determinism) is met trivially — every track starts from the same `flowPhase=0` body — **but per-track-DISTINCT seeding (re-seed the gas from track identity, NB.1 SHA hook) was DEFERRED**: it requires threading track identity into `NimbusState` init (broader wiring than the prompt's Energy-only scope), and the continuous flow re-diverges the body within seconds regardless. **PresetSessionReplay route registration also DEFERRED** — the follower test already supplies per-route firing evidence; replay is most useful against a real session (the manual-validation step). Both fold naturally into NB.6 (mood adds per-track colour variation + the replay pass against a real mood session).

---

### NB.5 — Beat: stem lobes (the band plays the body) ✅ (2026-06-05, D-141)
**preset · depends on: NB.4 · gate: each stem heaves the single body in its direction; one mass holds; Matt live sign-off**

*(The original NB.5 — Pulse/embers — was CUT 2026-06-04 as "too much activity." This slot is reinstated and redefined after the NB.4 model was falsified live; see D-141.)*

**Why.** The first real-music test of NB.4 (the *Atlas* / Battles session `2026-06-05T14-35-14Z`, a relentless 136-BPM track) showed the energy-only bloom **too subtle** and, on bass-dominated music, structurally floored: `bloom` averaged 3 bands and with mid (0.04) / treble (0.004) near-silent the dead bands vetoed it → the body sat at floor-size all session while the beat (beatComposite > 0.5 on 53 % of frames, grid locked at 136) went unanswered. All four stem deviations swing hard (peaks 1.9–2.8) — the stems carry the structure the 3-band FeatureVector lost. Matt's call: drive from the beat, per stem; "one mass heaves per-stem" (not hard quadrants).

**Delivered.** Four fast-attack/slow-release stem followers in `NimbusState` (`kickPunch` ← drums onset pulse → `drumsEnergyDev`; `bassLobe`/`vocalsLobe`/`otherLobe` ← stem `…EnergyDev`); `NimbusStateGPU` 16→32 bytes; `bloom` re-sourced to mean stem energy (fixes the floor). Shader heaves the **single** envelope per stem (`rr/(1 + kick + Σ lobe·cos²)` — star-convex, cannot fragment): drums punch + brighten the whole body, bass DOWN, lead UP, other SIDE. FA #4 honoured (beat = accent on the slow bloom; safe — no feedback loop, zero-delay pulse, soft-decay heave). Budget p50 3.74 ms (§6.5; perf lesson: cos², never `pow()`). Test: `NimbusBloomFollowerTest.test_stemLobes`. **Remaining: Matt's live sign-off — does the body feel like it's playing with the band?**

---

### NB.6 — Mood
**preset · depends on: NB.4 · gate: mood fixtures show colour + flow-agitation travel**

**Goal.** The two slow mood signals: valence → body colour (cool↔warm); arousal → flow agitation (smooth↔torn).

**Scope.**
- Valence → colour cool indigo/violet ↔ warm gold/amber (the `06_palette_*` axis); arousal → **flow agitation** amplitude (the `kNimbusTurbulence` knob NB.2 built). **Smoothed in state ~4 s — never via `setFeatures` (FA #25).**
- Replace the fixed `kNimbusTurbulence` constant with the arousal route.

**Out of scope / Do NOT.** No per-stem tint (V2, §8.2). Do NOT write valence/arousal through `setFeatures`. Do NOT let mood introduce a fast colour flicker — colour crawls (fast colour = the `05_anti_oilslick` failure).

**Key files.** `Sources/Presets/NimbusState.swift` (mood smoothers), `Sources/Presets/Shaders/Nimbus.metal` (colour + flow agitation), `Sources/Presets/Nimbus.json`.

**Done-when.**
- Contact sheet across high/low-valence fixtures: visibly warm vs cool body.
- High/low-arousal fixtures: visibly different flow agitation.
- No first-frame colour pop; transitions smooth (state-smoothed).

---

### NB.7 — Page (reorganisation) — ❌ CUT (2026-06-04)
**Removed from scope.** No section-boundary reorganisation in v1 — it's not in the reference packet and adds a behaviour the concept doesn't need (DESIGN §1.3).

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
- **Acceptance invariants** (`PresetAcceptanceTests`, DESIGN §5.7): silence-non-black; energy-primacy (bloom + flow track continuous energy; **no `beat_*` read**); flow-is-alive (gas visibly churns at all times, incl. silence); body-coherence (single bounded mass, negative space preserved, ≠ uniform fog); mood travel (cool/warm + flow-agitation).
- Golden dHash regression entry for Nimbus.
- **Anti-reference check:** manual (the automated anti-reference dHash gate is a Missing engine capability — same as Arachne / Skein — so this stays an M7 judgement).
- `ENGINEERING_PLAN.md` rows marked landed; `FidelityRubric` profile set (full-rubric — Nimbus is an artistic preset, not lightweight).
- **Matt M7:** live, on real music, ≥5 tracks + a local file — body-must-bloom-and-flow / glow-must-read. Non-negotiable, non-bypassable.

**Out of scope / Do NOT.** No new features at cert. Do NOT flip `certified: true` before M7 passes.

**Key files.** `PresetAcceptanceTests.swift`, `PresetRegressionTests.swift` (golden), `Sources/Presets/Nimbus.json` (`certified`, `rubric_profile`), `ENGINEERING_PLAN.md`, `FidelityRubric` wiring.

**Done-when.**
- Acceptance green; golden registered; anti-reference manual check clean.
- M7 verdict: pass.

---

## Sequencing, cut-lines, and risk

- **Critical path:** NB.0 ✅ → NB.1 ✅ → NB.2 ✅ → NB.3 ✅ (the look) → NB.4 ✅ (energy swell) → NB.5 ✅ (beat: stem lobes, D-141) → NB.6 (mood) → NB.8 (perf) → NB.9 (cert). NB.5-as-Pulse and NB.7 (Page) were CUT; NB.5 was reinstated as stem beat-lobes after the energy-only model proved too subtle live. A certified Nimbus is the band playing one packet-matching body — beat (per stem) + energy swell + mood.
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
