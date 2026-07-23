# Volumetric Lithograph — Rebuild Session Prompts

Two sequenced Claude Code sessions for the VL psychedelic-terrain-flight rebuild, per
`docs/presets/VOLUMETRIC_LITHOGRAPH_DESIGN.md`. **Run in order** — Session 1 is an
infrastructure increment that Session 2 depends on, and per the authoring protocol infra is
never bundled into the preset increment.

- **Session 1 — SDF.1:** vendor hg_sdf (approved by Matt, 2026-07-23). Standalone infra.
- **Session 2 — VL-PSY.1:** the VL rebuild v1. Depends on SDF.1 + a re-curated reference set.

Feed **one** session into a fresh Claude Code context.

> ⚠️ **SESSION 1 (SDF.1) IS VOID as of 2026-07-23 (VL.1).** Matt reversed the full-vendoring
> approval: VL now ports only `pModPolar` / `pModMirror2` / `pReflect` verbatim from canonical
> `hg_sdf.glsl` (~50 lines) directly into its own shader tree, and the fold math folds into
> Session 2 task 2. Do not run Session 1. Session 2's "SDF.1 landed on main" pre-flight is
> likewise struck. See `VOLUMETRIC_LITHOGRAPH_DESIGN.md` §Open decisions #1.
>
> Session 2 **task 1 (harness) is already DONE** — `VolumetricLithographRayMarchHarnessTest`
> landed at VL.1. Start Session 2 at the reference gate, then task 2.


---

# Session 1

## Increment SDF.1 — Vendor hg_sdf SDF operator library
**Type:** infrastructure.

**Objective.** After this session, Mercury's `hg_sdf` domain/boolean operators (MIT option) are
vendored as a shared Metal header injected into every preset's shader preamble — with the
floored-modulo gotcha handled — and proven by unit tests, flipping the RENDERER capability
**SDF authoring: Missing → Supported**. This is the grounded port target for VL's kaleidoscopic
folds (VL is the first real consumer, in Session 2). No preset consumes it yet in this session.

## Skills
- `shader-authoring` — before touching the vendored `.metal`.
- `closeout` — at the end.

## Read-first
1. `HG_SDF_VENDORING_SPEC.md` (repo root) — the authoritative spec: license call, MSL port
   gotchas, operator list, verification.
2. `PhospheneEngine/Sources/Presets/Shaders/Utilities/` tree + the preamble injector
   (`PresetLoader+Preamble.swift`) — where the header is concatenated.
3. The hg_sdf source to port from (`hg_sdf.glsl`, MIT lines) — **must be present locally on the
   Mac**; the sandbox cannot fetch it (see pre-flight).

## Pre-flight invariants (a failed check stops the session)
- Clean branch off `main`; full battery green.
- `hg_sdf.glsl` is present locally to port from (download from mercury.sexy on the Mac first).
- **Proof-preset note:** the spec named Glass Brutalist / Kinetic Sculpture as the proof
  consumers — **both are now retired (D-186 / D-188)**. This session proves the vendor via
  **unit tests only**, not a preset refactor; VL consumes the operators in Session 2.

## Tasks
1. **Port hg_sdf → `Utilities/Geometry/HgSdf.metal`** (retain the MIT copyright header). Apply the
   spec's MSL adaptations: `inout` → `thread T&`; `atan(y,x)` → `atan2`; and a floored `gmod`
   helper used everywhere hg_sdf uses `mod` (gotcha #3 — the single most important one).
   **Done-when:** file compiles inside the preamble; operators present per spec (`pMod1/2/3`,
   `pModInterval1`, `pModPolar`, `pModMirror2`, `pReflect`, `pR`, `fOpUnionRound`, …).
2. **Wire into the preamble injection** so every preset gets the operators for free.
   **Done-when:** an existing ray-march preset (e.g. Lumen Mosaic) still builds and its
   `PresetRegressionTests` goldens are **byte-identical** — pure addition, zero behavioural change.
3. **Add `HgSdfOperatorTests`:** `gmod`/`pMod1` symmetry-across-origin correctness (the gotcha #3
   gate), `pModPolar` repetition count, no-NaN sweep. **Done-when:** the suite passes.
4. **Capability + docs.** Flip `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` "SDF authoring →
   Supported"; ARCHITECTURE Module Map row for `HgSdf.metal`; record SDF.1 revival (GB/KS retired,
   VL is the intended first consumer). **Done-when:** docs updated, `DocIntegrityTests` green.

## Do-NOT
- Do **not** refactor any preset to consume the operators this session (scope discipline; VL does
  that in Session 2).
- Do **not** take the CC-BY-NC option — **MIT only** (Phosphene is MIT).
- Do **not** push without Matt's explicit "yes, push".

## Verification
```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
```
Plus: `HgSdfOperatorTests` green; existing ray-march `PresetRegressionTests` goldens byte-identical.

## Commit
`[SDF.1] Presets: vendor hg_sdf SDF operator library` — small commits per step, local-only,
push on Matt's explicit yes.

## Closeout
Invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.

## DECISION-NEEDED
None — pure infrastructure, no product-visible change.

---

# Session 2

## Increment VL-PSY.1 — Volumetric Lithograph psychedelic-flight rebuild (v1)
**Type:** preset.

**Objective.** After this session, Volumetric Lithograph is a genuinely psychedelic terrain
flight: the ground kaleidoscopically **folds and domain-warps with the music** via geometry-space
hg_sdf operators; camera dolly speed rides the bass; each downbeat fires a coordinated **forward
lurch + symmetry snap**; the palette flows into mind-altering hue territory; and there's a
non-black silence state — reviewable at M7 for the look and the hero audio coupling. Fine
spectral-flux detail churn and full cert polish are explicitly **v2**.

## Skills
- `preset-session` — before any `.metal` or sidecar edit.
- `shader-authoring` — before GPU code.
- `closeout` — at the end.

## Read-first
1. `docs/presets/VOLUMETRIC_LITHOGRAPH_DESIGN.md` — the committed concept, musical-role sentence,
   temporal contract, routing table (this is the spec of record).
2. `docs/VISUAL_REFERENCES/volumetric_lithograph/README.md` — the **re-curated psychedelic** set
   (see pre-flight; the old set is off-concept).
3. `Utilities/Geometry/HgSdf.metal` (from SDF.1) + `Utilities/Noise/DomainWarp.metal` — the warp
   primitives.
4. `PhospheneEngine/Sources/Presets/Shaders/VolumetricLithograph.metal` + `.json` — what's being
   replaced (the v9.4 header carries the audio-liveness history worth preserving).
5. The `RayMarchPathHarnessTemplate` (D-182, Lumen-Mosaic-based) — the multi-frame harness to
   copy-adapt.

## Pre-flight invariants (each stops the session if failed)
- **SDF.1 landed on `main`** — hg_sdf operators available in the preamble; `HgSdfOperatorTests` green.
- **References RE-CURATED to the psychedelic direction.** The prior naturalistic/linocut set is
  **outdated and off-concept** (Matt, 2026-07-23) and cannot grade this preset. Proceed only if
  `docs/VISUAL_REFERENCES/volumetric_lithograph/` has been **replaced** with a psychedelic set +
  annotated README (mandatory traits + anti-references, including *"naturalistic terrain with
  aerial haze = the OLD VL, now off-brand"*). Old images archived/removed, not mixed in. **If not
  curated → STOP and escalate to Matt** (curation is Matt-owned, D-064/D-065).
- `VOLUMETRIC_LITHOGRAPH_DESIGN.md` committed to `main`, status flipped DRAFT → accepted.
- Clean branch off `main`; full battery green.

## Tasks
0. **Reference gate check** (pre-flight above). If unmet → stop and report. Do not open a `.metal`.
1. **Harness first.** Copy-adapt `RayMarchPathHarnessTemplate` → `VolumetricLithographRenderTests`
   driving the live `ray_march → post_process` path. **Done-when:** VL renders across ≥ N frames on
   the production dispatch path; a **silence** and an **audio** fixture `RENDER_VISUAL=1` contact
   sheet are emitted **before any tuning**.
2. **Macro geometry-space warp** in `sceneSDF`: fold the domain with `pModPolar` / `pReflect` /
   `pModMirror2` + `warped_fbm` around the heightfield. Route the **vocal/energy swell → fold depth
   + warp amount**; **downbeat (`bar_phase01`) → symmetry-order snap**. **Done-when:** the audio
   contact sheet shows kaleidoscopic folding terrain morphing with the fixture; non-black at
   silence; **no mv_warp anywhere**.
3. **Camera + beat sync.** Retain **bass → dolly speed**; add a **downbeat → bounded forward
   lurch** (D-157: bounded footprint, steady global luminance). **Done-when:** the harness shows a
   per-downbeat lurch coordinated with the symmetry snap; no luminance strobe.
4. **Palette push.** Hue flows with melody + `accumulated_audio_time`; widen the range for a
   mind-altering, shifting character. **Done-when:** the contact sheet reads saturated and moving,
   not the old flat map.
5. **Silence state + sidecar fix.** Non-black slow-warping symmetric field at
   `totalStemEnergy == 0`. Fix `VolumetricLithograph.json` (`stem_affinity`, `beat_source`,
   `family`, description) and the README `Family` header to match the shipped routing.
   **Done-when:** `SilenceFallbackTests` green; sidecar matches the design-doc routing table.
6. **STOP before golden regeneration.** Present the contact sheets for Matt's M7 look **before**
   regenerating VL's `PresetRegressionTests` goldens. **Done-when:** stop and report.

## Do-NOT
- **No mv_warp / screen-space feedback warp** — the warp is geometry-space only (D-029; the VL
  revert + the README anti-reference). Reintroducing it is the documented smear failure.
- **Do not route bass into terrain deform** — bass drives camera speed only (the v9.1 overload
  lesson: bass on the landmasses swallowed the percussion delta).
- **No naturalistic aerial-perspective fog, `ridged_mf` drainage, or cloud shadows** — the dropped
  §10.5 direction; scene_fog stays 0.
- **Do not build the music-driven camera-placement engine hook** — deferred; v1 is speed + downbeat
  lurch (DESIGN §2.3).
- **Do not grade against the old naturalistic reference images.**

## Verification
```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
```
Plus: `VolumetricLithographRenderTests`, `SilenceFallbackTests`, `PresetAcceptanceTests` green;
`RENDER_VISUAL=1` contact sheets (silence + audio); VL rubric report printed.

## Commit
`[VL-PSY.1] Presets: <step>` — small commits per logical step, local-only, push on Matt's yes.

## Closeout
Invoke `closeout`; 8-part report with the `Scripts/closeout_evidence.sh` block as §2. Additions:
state **which dispatch path** the tests exercised (`ray_march → post_process` live path);
per-route firing evidence from the harness (swell→fold %, downbeat→snap/lurch firing %); and name
the deferred v2 items (spectral-flux detail churn, cert polish, camera placement).

## DECISION-NEEDED (product-level, for Matt at M7)
**How far should the kaleidoscopic folding go?**
- **A — Folded landscape:** still reads as a terrain you fly over, but it visibly mirrors and folds
  on the beat. Grounded, less risk of "abstract soup."
- **B — Full radial mandala-terrain:** the ground becomes a strong kaleidoscopic mandala in
  motion — more overtly psychedelic, further from "landscape."
- **Recommendation:** A for v1 (keeps VL's flight identity legible), push toward B at M7 if it
  reads too tame. **Default if no reply:** A.
