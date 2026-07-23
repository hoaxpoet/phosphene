# Volumetric Lithograph — Design (psychedelic terrain-flight rebuild)

**Status:** Accepted (Matt, 2026-07-23) — the committed VL rebuild design record. Implementation
is gated on the open items in §Open decisions (reference re-curation is the live blocker; SDF.1
approved, awaiting its session).
**Supersedes:** the naturalistic `SHADER_CRAFT.md §10.5` / V.11 uplift direction (aerial
perspective, ridged_mf drainage, cloud shadows — all dropped) **and** the "psychedelic
linocut" label that the shipped v9.4 never achieved.
**Author seat:** design/concept (Cowork). Claude Code implements from this doc.

> **Why the reset.** The shipped v9.4 reads (Matt, 2026-07-23) as "a topographic map that
> adds and removes depth," not psychedelic linocut — the label was aspirational, never
> delivered, and Matt is not happy with the result. The terrain is too patterned and wants
> musically-driven variation; the camera dolly is a keeper but underused; beat sync is loose;
> the palette is interesting but not mind-altering. Decision (2026-07-23): re-scope VL to a
> **genuinely psychedelic terrain flight**. This is a near-rebuild, not a tune — run it through
> the concept gate and the reference-port before writing shader code (the Aurora Veil / FA #65
> lesson: stop deriving, commit a spec, port a reference).

---

## 1. Identity (one sentence)

**An endless forward flight through a living psychedelic landscape whose *geometry itself*
folds, kaleidoscopes, and domain-warps with the music — the ground is a mind-altering
structure you move *through*, not hills that rise and fall.**

**How it stays distinct from Phase PG.** The psychedelic-geometry presets are static-camera
or radial geometries (Mandala, Droste, Mandelbox Cathedral, Poincaré). VL's identity anchor
is the **flight** — a forward dolly over infinite, warping terrain. Nothing else in the
catalog is a *landscape you travel through*. Keep the dolly load-bearing so VL never collapses
into "Mandelbox Cathedral with a moving camera."

---

## 2. Concept-viability gate (SHADER_CRAFT §2.0 — all three clear before code)

1. **Iconic visual subject deliverable at fidelity.** The subject is folding/kaleidoscopic
   warping terrain seen in flight. Grounded, not derived: the fold math is **ported from
   hg_sdf** (`pModPolar` kaleidoscope, `pReflect` / `pModMirror2` mirror folds) and the organic
   warp from the existing `warped_fbm` domain-warp (Quilez). The ray-march terrain-flight
   skeleton already ships; the warp is a bounded, grounded addition — not a from-scratch invention.
2. **Musical role.** See §3 — one sentence, specific features → specific behaviours.
3. **Infrastructure-feasible.**
   - Geometry-space warp in `sceneSDF`: **yes**, but depends on **SDF.1 (vendor hg_sdf)**,
     which is spec'd (`HG_SDF_VENDORING_SPEC.md`) but **not yet built**; its original proof-presets
     (GB/KS) were retired. **VL becomes SDF.1's proof consumer.** (Decision needed — §9.)
   - Camera speed + downbeat forward lurch: **yes** (existing bass→dolly + cached BeatGrid).
   - Music-driven camera *placement / bank / height*: **needs a new per-preset camera hook**
     in the render path (today only dolly *speed* is modulated; base pose is static JSON).
     **Deferred to a later increment; v1 excludes it** (Matt's default, 2026-07-23).

---

## 3. Musical role + 30-second temporal contract

**Musical-role sentence (the gate):** *The camera's forward speed rides the bass, so you
accelerate through the world when the low end drives; each downbeat on the cached BeatGrid
fires one coordinated gesture — a forward camera lurch plus a snap of the terrain's
kaleidoscopic symmetry; a broad vocal/energy swell continuously deepens the geometric folding
and domain-warp so the ground morphs with the song's dynamics; spectral flux churns fine
surface variation; and the melody flows the palette through mind-altering hue rotations — so
the listener pairs the bass with rushing forward, the beat with a lurch-and-fold, the swell
with the world deforming, and the melody with colour washing across the landscape.*

**Temporal contract (~30 s):** sparse intro → low-order symmetry, gentle warp, slow hue drift.
Build → swell deepens fold-depth and raises symmetry order; camera accelerates with the bass.
Downbeats → the coordinated lurch-and-symmetry-snap gesture. Sustained sections → flux detail
churn + continuous hue flow carry motion between beats. Comedown → symmetry and fold relax back
toward the calm field.

---

## 4. Audio routing table (one primitive per layer — FA #67)

| Visual layer | Audio primitive | Timescale |
|---|---|---|
| Terrain fold-depth + domain-warp amount (macro deform) | broad vocal/energy swell (`vocals_energy` / total-energy envelope) — **not bass** | continuous / slow |
| Camera dolly **speed** | `features.bass` | continuous |
| Downbeat gesture: forward camera **lurch** + kaleidoscopic **symmetry snap** (one coordinated gesture) | downbeat on cached BeatGrid (`bar_phase01`) — bounded, D-157 | beat-locked / per-bar |
| Fine surface churn / variation | `spectral_flux` | continuous / fast |
| Palette hue flow | melody/`vocals` + `accumulated_audio_time` | continuous / slow |
| *(deferred)* Camera placement / bank / height | slow mood envelope (`arousal` / `valence`) | slow — **later increment** |

**Carry-forward from v9 (do not relearn the hard way):** bass drives **camera speed only**.
Do **not** route bass into terrain deform — the documented v9.1 failure was bass overloading the
landmasses so distinct percussion events produced no visible delta. The macro deform is a
vocal/energy swell; the beat gesture is downbeat-locked; bass stays on the camera.

**Intentional coupling note.** The downbeat drives two visual channels (camera lurch + symmetry
snap) *on purpose* — it is one designed gesture ("the beat = lurch-and-fold"), exactly the
tighter camera/terrain beat-coupling Matt asked for. This is coordinated, not the FA #67
"fighting itself" failure (which is two *unrelated* layers sharing a primitive by accident).

**Silence (D-037):** at `totalStemEnergy == 0` the terrain settles to a calm, slow-breathing
low-order symmetric field with gentle hue drift — non-black, alive-but-quiet. No beat gesture,
no flux churn.

---

## 5. Warp mechanism + grounding (the load-bearing engineering constraint)

**Geometry-space only.** The warp lives inside `sceneSDF` (world-space, evaluated per frame),
**never** as a screen-space feedback pass. mv_warp was reverted from VL (D-029) because its
UV-space accumulator fights the moving camera and smears; it must **not** return (README
anti-reference). "Warp everything" = warp the *terrain*, not the *image*.

**Primitives:**
- **Kaleidoscope / mirror folds:** hg_sdf `pModPolar` (radial kaleidoscopic repeat), `pReflect`,
  `pModMirror2` — applied to the domain before the heightfield eval.
- **Organic warp:** existing `warped_fbm` / `warped_fbm_vec` (`Utilities/Noise/DomainWarp.metal`).
- **Height base:** the current fBM heightfield stays as the substrate the folds act on.

**Grounding / port target (FA #73 — port, don't derive):** hg_sdf (Mercury), MIT option, per
`HG_SDF_VENDORING_SPEC.md`; `warped_fbm` traces to Quilez's domain-warp article. Both are
license-clean and repo-native. This is the single biggest anti-spiral lever: the kaleidoscope
math is *ported*, not invented mid-session.

---

## 6. Palette

Keep the IQ cosine palette as the seed (Matt: "interesting"), but push it from *coloured* to
*mind-altering*: hue **flows** continuously with the melody + audio time, the range widens, and
a second cosine layer / chroma boost gives the saturated, shifting character. Target look comes
from the new reference curation (§7), not from the current naturalistic set.

---

## 7. Visual references — **RE-CURATION REQUIRED (Matt-owned pre-flight gate)**

The current set (`docs/VISUAL_REFERENCES/volumetric_lithograph/`) is naturalistic / linocut
(drainage relief, Hokusai, Canyonlands aerial perspective) and is now **off-direction**. Before
implementation, curate a psychedelic set:

- Kaleidoscopic / IFS fractal stills; radial-symmetry mandala-in-motion frames.
- Saturated colour-flow / liquid-light psychedelia; "flying through a folding world" stills.
- **Anti-references:** naturalistic terrain with aerial haze (the *old* VL — now explicitly
  off-brand); flat neon screensaver strobe; muddy over-blended smear.

Per the checklist this is a hard pre-flight gate — no shader tuning until the set + annotated
README exist.

---

## 8. Performance / tier

`ray_march + post_process` (deferred G-buffer + bloom/ACES; SSGI stays off for hard contrast).
Kaleidoscopic folds add march cost and can hurt SDF Lipschitz continuity — watch the step scale
(current `VL_SDF_STEP_SCALE = 0.6`). Hold the Tier-2 ceiling (~5 ms p95 @ 1080p); profile after
the macro warp lands.

---

## 9. Sidecar + metadata fixes (drifted from v9.4, fix at rebuild)

`VolumetricLithograph.json`: `stem_affinity` still claims all four stems drive terrain height
(false since v9.3); `beat_source: "bass"` contradicts the routing; README header says
`Family: fluid` while JSON says `geometric`. Rewrite the description to the psychedelic identity;
`certified: false`.

---

## 10. Increment arc (coarse-to-fine — anti-spiral order)

0. **SDF.1 — vendor hg_sdf** (MIT), VL as the proof consumer. *Prerequisite; decision needed.*
1. **Multi-frame ray-march harness FIRST** — copy-adapt `RayMarchPathHarnessTemplate` (D-182,
   Lumen-Mosaic-based). Repeatable gate before any tuning (VL has never had one).
2. **Macro warp** — kaleidoscope + domain warp in `sceneSDF` (vocal/energy swell → fold depth;
   downbeat → symmetry snap). `RENDER_VISUAL=1` contact sheet before the first tuning commit.
3. **Camera + beat sync** — downbeat forward lurch + bass dolly speed; tighten grid-lock.
4. **Palette push** — mind-altering hue flow.
5. **Detail + variation + silence + cert polish** — spectral-flux churn, silence state, rubric.

*(Music-driven camera placement = separate later increment, per §2.3.)*

---

## Open decisions (DECISION-NEEDED)

1. **SDF.1 revival.** ~~✅ APPROVED (Matt, 2026-07-23) — vendor hg_sdf (MIT) with VL as the proof
   consumer; Session 1 prompt drafted (`VOLUMETRIC_LITHOGRAPH_REBUILD_PROMPTS.md`).~~
   ⚠️ **SUPERSEDED later the same day (Matt, VL.1): port only what VL uses.** `pModPolar`,
   `pModMirror2`, `pReflect` ported **verbatim from canonical `hg_sdf.glsl`** (MIT, copyright
   header retained) straight into VL's shader tree — ~50 lines. FA #73 is satisfied (the fold math
   is *ported*, not derived); vendoring ~40 operators for a preset that calls three of them is not.
   `HG_SDF_VENDORING_SPEC.md` stays on the shelf, but §3's gotchas (**floored `hg_mod`**, `atan2`,
   `thread&` for `inout`, symbol collisions with the existing preamble trees) are mandatory reading
   for the three ported functions. The RENDERER capability flip waits for a second consumer.
   **Consequence: the Session-1 / SDF.1 prompt is void; the fold math folds into Session 2's task 2.**
2. **Reference curation (§7).** ✅ **RESOLVED (Matt, 2026-07-23): Claude proposes, Matt approves.**
   Claude sources candidates (kaleidoscopic / IFS stills, liquid-light psychedelia, folding-world
   flight frames) and presents them annotated; Matt accepts / rejects / replaces before the README
   is written. **Still a hard pre-flight gate** — no shader tuning until the approved set exists.
3. **Camera placement.** ✅ **Deferred (Matt, 2026-07-23)** — v1 = camera speed + downbeat lurch;
   music-driven placement/banking is a later engine increment.
