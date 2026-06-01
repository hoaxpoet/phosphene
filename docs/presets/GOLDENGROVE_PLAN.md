# Goldengrove — Feasibility-Researched Build Plan

> **SHELVED 2026-06-01 (not built).** Matt's call: not the next best preset to develop — a repeat of the Drift Motes (D-102 / FA #58) and Ferrofluid Ocean (69-round) pattern, where neither the musical coherence nor the hero-fidelity deliverability was settled. Two unresolved problems: (1) the distinctive hook (growth) is the *slowest, least music-alignable* behaviour, and the signal that would make it strong (song structure) doesn't reach a preset; the achievable version is soft intensity-envelope modulation — the Drift Motes failure shape. (2) Hero painterly fidelity is the category that's been botched repeatedly. Research record retained as a real-feasibility reference for any future tree work. Do not revive without a fundamentally stronger, signal-grounded musical hook.

**Status:** SHELVED — plan-for-sign-off below kept as historical record. Supersedes `GOLDENGROVE_CONCEPT.md` (kept for the experiential picture). No production code until approved; the first work items are **de-risking spikes**, not the build.

**What this is:** a new high-fidelity preset (painterly, golden-hour, back-lit autumn tree that grows with the music) on the V.10 cert rung. The existing Fractal Tree is preserved untouched as a sibling.

**Research basis:** two parallel research passes (2026-06-01) — engine-internal feasibility (every recipe + the mesh/lighting path + the state-machine pattern, cited to file:line) and external desk-research on proven techniques (cited to papers / Shadertoys / shipped-game write-ups). Both are summarized inline below with citations.

---

## 1. The headline truths the research forced

1. **This is not a tweak of FractalTree — it's a new preset on a different render path.** The existing tree uses `passes: ["mesh_shader"]`: a direct mesh path that writes flat HSV color with **no lighting and no G-buffer** (`FractalTree.json:8`, `FractalTree.metal:199–256`). Bark (§4.7), leaf SSS (§4.8), and golden-hour lighting (§5.6) **all require PBR materials + lighting**, which on a mesh preset means the **deferred `ray_march` + `setMeshGBufferEncoder` path** — the exact path Ferrofluid Ocean's mesh already uses (`RenderPipeline+PresetSwitching.swift:167–177`). Proven, but it is real architecture work, not a parameter change.

2. **The load-bearing musical hook — audio-driven growth — has NO published precedent.** External research found zero citable references for music driving the *growth* of a procedural tree (branch extension / canopy fill). Every *other* mechanism is grounded in production-proven prior art; this one is grounding-level-3 (assertion only). Per the Grounding-Priority rule, that makes it a **spike with a go/no-go**, not a build assumption.

3. **"Blooms at the chorus / sheds at the section boundary" is not achievable from preset signals.** Confirmed: `FeatureVector` contains only continuous energy, beats/bar-phase, spectral, valence/arousal, and time/track-elapsed — **no section, boundary, build, or peak signal** (`Common.metal:9–46`). Growth can track an *energy/arousal/accumulated-energy intensity envelope* (achievable) but cannot align to song structure unless the Orchestrator routes segment metadata to the preset (a separate infrastructure increment). **This is a product decision (§7).**

4. **The painterly post-filter is the one mechanism that can blow the 16 ms budget.** Everything else (instancing, foliage SSS, god rays, dust, fog) is cheap and proven; anisotropic Kuwahara is a wide-kernel fullscreen pass that even its best real-time reference (Maxime Heckel) had to optimize hard. Measure it before committing.

---

## 2. Architecture decision — the deferred mesh-G-buffer path

**Goldengrove ships as `passes: ["ray_march"]` + a `MeshGBufferEncode` closure** (not `mesh_shader`). The closure emits branch + foliage geometry into the G-buffer (normal, albedo, roughness, emission); the standard lighting pass applies Cook-Torrance + IBL + scene lights, which is where golden-hour + bark + leaf-SSS materials become possible. Reference consumer: `FerrofluidMesh` (`RenderPipeline+PresetSwitching.swift:168–170`).

Consequences (all net-new, all bounded):
- Extend the mesh vertex format with a **tangent frame** (POM + normal mapping need `ws_to_ts()`; current `MeshVertex` has position/normal/uv only — `FractalTree.metal` vertex format).
- Provide **view + light directions** to the leaf-SSS material (reconstructed in the G-buffer encode from screen UV + camera, or passed via `SceneUniforms`).
- Golden-hour becomes **scene configuration** (low warm sun, IBL warm tint, altitude fog) on the ray-march scene path — no per-pixel hook needed once deferred.

---

## 3. Per-mechanism feasibility + grounding

| Mechanism | Engine status | External grounding | Verdict |
|---|---|---|---|
| **Branch geometry** | L-system already built (`FractalTree.metal:90–133`), binary tree, mesh-shader instanced quads | CPU-expand L-system → instanced frustums (jysandy, ~3.65 ms/tree). SDF trees are background-only, not hero (matches FA #32/#49) | ✅ proven path |
| **Growth animation** | Branch-count growth prototyped (`FractalTree.metal:48–53`) | **Bake growth-stage snapshots offline + morph/segment-reveal at runtime** — cheaper + more stable than live regeneration (forest-env, arxiv 2208.01471). Space-colonization (Runions 2007) for believable asymmetric growth | ✅ proven, with offline-bake steer |
| **Bark material (§4.7)** | Prose recipe; `worley3d`/`fbm8`/`triplanar_detail_normal` utilities exist; needs G-buffer path + tangent frames | standard PBR | ✅ on deferred path |
| **Leaf back-lit SSS (§4.8)** | Prose recipe; **needs view/light dirs → deferred path** | **Best-grounded mechanism:** Frostbite translucency (GDC 2011, ~6 ALU ops) + GPU-Gems wrap lighting + per-leaf thickness. The hero canopy-glow moment | ✅ strongest piece |
| **Foliage billboards** | Mesh vertex budget maxed (252) → needs separate path | instanced billboards / brushstroke particles; existing `ParticleGeometry` path (Murmuration/FFO) | ✅ via particle/instanced path |
| **Golden-hour atmosphere** | scene config on ray-march path | god rays (GPU Gems 3 Ch.13, radial-blur post), dust motes (point sprites/Worley), altitude fog tinted per FA #38, rim glow from SSS+bloom. ~1–2 ms total | ✅ cheap + proven |
| **Painterly look** | none today | (a) soft-alpha **brushstroke-billboard canopy** = painterly *by construction*; (b) light anisotropic-Kuwahara post (Heckel; pmndrs). **Cost risk** | ⚠️ proven but budget-sensitive |
| **Growth state machine** | `ArachneState` pattern (setMeshPresetTick, audio-modulated pacing, pause guards — `ArachneState.swift:823–863`) | — | ✅ proven internal pattern |
| **Audio→growth coupling** | continuous signals only; no structure | **NO PRECEDENT FOUND** | ⛔ spike-gated |

---

## 4. The audio→visual reaction model (grounded in real signals)

No peak/section detector exists, so the model is built bottom-up from signals the preset actually receives. **Every row cites a real `FeatureVector`/`StemFeatures` field.** One primitive per visual layer (per the one-primitive-per-layer rule, `feedback_audio_layer_one_primitive`):

| Visual layer | Driver (real signal) | Timescale | Character |
|---|---|---|---|
| **Canopy growth / fullness** | smoothed **vitality envelope** = f(`arousal`, accumulated positive energy, `track_elapsed_s`) held in `GoldengroveState` | slow (whole-song) | tree fills as the music sustains intensity; sparse in calm intros. **Intensity envelope, NOT chorus-aligned.** |
| **Growth-front advance rate** | `mid_att_rel` (continuous) + `drums_energy_dev` accent — the exact Arachne build-pace formula (`ArachneState.swift:840–843`) | per-beat-ish | branches extend faster on sustained energy, bump on drum hits |
| **Leaf shimmer / catch-light** | `beat_composite` / `bass_att` | per-beat (accent) | leaves flash/catch light on beats (Layer-4 accent, never primary) |
| **Wind sway** | `other_energy_att` (+ continuous `mid`) | continuous | branch/leaf motion; gust on melodic swells |
| **Season / palette** | `valence` | very slow (per-track) | autumn default; negative→winter frost, positive→spring/summer |
| **Shed / release** | **track change** (the only real boundary; `track_elapsed_s` resets) | per-track | leaves release at track end, canopy resets to rebuild |

**This is the honest version of "grows with the song":** the tree gets fuller and more alive as the music intensifies, breathes with energy, shimmers on beats, shifts season with mood, and sheds at each track's end. It does **not** bloom precisely on the drop — that needs §7's orchestrator decision.

**The unproven crux:** whether this envelope-driven growth reads as *musical* rather than *mechanical* is exactly what has no precedent and cannot be asserted — it's **Spike 1**.

---

## 5. De-risking spikes (do these FIRST — they gate the build)

### Spike 1 — Audio-reactive growth coupling *(make-or-break; gates everything)*
**Question:** does a tree whose growth is driven by the §4 vitality envelope read as *musically alive* on real tracks, or as mechanical/arbitrary?
**Build:** the `GoldengroveState` growth state machine + the §4 audio mapping, driving the **existing cheap flat-quad geometry** (no materials, no foliage, no lighting). Drive growth-front + fullness from real signals.
**Validate:** replay against ≥3 real, contrasting tracks (sparse/calm, mid build, dense/energetic) via a recorded session + `PresetSessionReplay`; **Matt watches it grow against the music.**
**Success criterion:** Matt's gut read is "the tree is responding to *this song*," not "the tree is doing its own thing." 
**Go/no-go:** if growth doesn't read musical on cheap geometry, **stop** — no bark, foliage, or painterly work happens. This is the Drift Motes / Authoring-Discipline gate: the musical role is proven before the decoration.

### Spike 2 — Painterly + foliage perf budget *(the only budget risk)*
**Question:** can a dense foliage canopy (target leaf count TBD per §7) + back-lit SSS + an anisotropic-Kuwahara painterly post fit the ~6.5 ms preset slice of the 16 ms Tier-2 frame?
**Build:** a static (non-growing) tree with N leaf billboards + Frostbite/wrap SSS + the Kuwahara post at candidate radii (full-res, half-res).
**Validate:** GPU capture; measure each layer's cost (overdraw is the flagged dominant cost — jysandy).
**Success criterion:** total within budget at an acceptable leaf count + Kuwahara radius; or a documented decision to drop/cheapen the painterly post (brushstroke-billboards-only painterly).
**Go/no-go:** sets the leaf-count + painterly ceiling for the real build; may downgrade the painterly approach.

*(Spikes are throwaway PoCs on branches; success criteria are written before, not after — per the verification-criteria discipline.)*

---

## 6. Build plan (only after both spikes pass)

Ordered so the proven-cheap, highest-payoff pieces land first and the cost-risk piece is gated:

1. **Deferred-path conversion** — `passes: ["ray_march"]` + `MeshGBufferEncode` closure emitting the branch geometry into the G-buffer with a placeholder material; verify lit output composites (FFO-mesh parity). Extend `MeshVertex` with tangent frame.
2. **Bark material (§4.7)** on branches — `mat_bark` (worley lichen + fiber ridges + triplanar detail) + optional POM. Golden-hour scene config (warm low sun + IBL tint + altitude fog).
3. **Foliage + the hero SSS moment (§4.8 / Frostbite)** — leaf-cluster billboards at branch tips (instanced/particle path) with back-lit translucency. This is the canopy-glow payoff.
4. **Atmosphere** — god rays (radial-blur post), dust motes (point sprites), rim bloom, ground fog (tinted, FA #38).
5. **Season + wind** — valence→palette (autumn/winter/spring/summer), curl-noise wind ← `other_energy_att`.
6. **Painterly post** — brushstroke-billboard canopy + (budget-permitting) Kuwahara post at the Spike-2 radius.
7. **Perf + M7 polish rounds** — count unknown; this is the multi-round grind every cert takes (Lumen Mosaic 8, FFO ~dozens). Each round = `RENDER_VISUAL` contact sheet + `PresetSessionReplay` evidence + Matt M7.

Each numbered item is its own increment with its own closeout.

---

## 7. Open product decisions (need Matt's call)

1. **Growth coupling target** — accept the **energy/arousal intensity-envelope** model (achievable now, but "responds to intensity," not "blooms on the chorus"), **OR** fund an Orchestrator increment to route segment/peak metadata to the preset so growth can align to song structure (bigger, separate infrastructure work). *Spike 1 uses the envelope model regardless — this decides the ceiling.*
2. **Leaf count** — product/perf trade-off set by Spike 2 (sparse-but-cheap ↔ dense-but-budget-tight). Decide as "how full is the canopy" in product terms, not vertex counts.
3. **Painterly intensity** — full anisotropic-Kuwahara plein-air vs. brushstroke-billboards-only (cheaper, still soft-edged). Set by Spike 2 cost.

---

## 8. Risk register

- **Audio-growth coupling (highest)** — no prior art; mapping-reads-as-musical is unvalidated → **Spike 1 gates the whole preset.**
- **Combination cost** — live growth + dense foliage + painterly post unproven *together* in 16 ms → mitigations baked in (offline-baked growth stages, brushstroke-by-construction foliage, moderate Kuwahara) → **Spike 2.**
- **Execution-fidelity grind** — painterly hero look is the category that's been botched; multi-round M7 expected even with grounding.
- **Architecture lift** — deferred-path conversion + tangent frames + foliage path is real net-new work (bounded; FFO-proven pattern).

## 9. Recommendation

**Proceed to Spike 1 only.** Build the growth state machine + audio coupling on cheap geometry and prove the tree feels musical against real tracks before committing a single hour to bark, foliage, or lighting. If Spike 1 passes, run Spike 2 to set the perf ceiling, then build §6. If Spike 1 fails, we've spent one cheap spike instead of 60 rounds — which is the entire point of this document.

*(Citations: engine findings → `SHADER_CRAFT.md` §4.7/§4.8/§5.6/§8.3, `FractalTree.metal`, `ArachneState.swift`, `RenderPipeline+PresetSwitching.swift`, `Common.metal`. External → jysandy procedural-trees; Runions 2007 space-colonization; forest-env arxiv 2208.01471; Frostbite translucency GDC 2011; GPU Gems Ch.16 + GPU Gems 3 Ch.13/16; Heckel painterly shaders; pmndrs Kuwahara. Full URLs in the research record.)*
