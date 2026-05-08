Execute Increment V.7.7C — Replace the V.7.5 mat_frosted_glass drop overlay
with the §5.8 Snell's-law refractive dewdrop recipe sampling the WORLD
stage's offscreen texture.

Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md` §5.8 (Drops — the visual
hero), §5.11 (Drops refract the WORLD), §3A (staged renderer architecture).
Architectural pivot record: `docs/DECISIONS.md` D-072 (compositing layers),
D-092 (V.7.7B port). Reference for the working refraction recipe:
`PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` `drawBackgroundWeb()`
at ~line 563 (V.7.7-redo dead code; matches the §5.8 recipe almost exactly).

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. V.7.7B has landed. Verify with:
   `git log --oneline | grep -E '\[V\.7\.7B\]' | wc -l` — expect 2
   (`08449dfd` engine + harness binding; `6e2b4770` shader port + app +
   docs).

2. The dispatched COMPOSITE fragment is the V.7.5 v5 web walk + drop
   overlay (`mat_frosted_glass` based, no refraction). Confirm:
   `grep -n 'mat_frosted_glass\|dropEmission' PhospheneEngine/Sources/Presets/Shaders/Arachne.metal | head -10`
   — expect two `mat_frosted_glass` call sites (anchor block + pool block,
   ~lines 749 + 813) and matching `dropEmission` accumulation.

3. The reference recipe is intact in `drawBackgroundWeb()` at ~line 563
   and has the working Snell's-law block (sampler `arachne_world_sampler`,
   `refract(-kViewRay, sphN, 0.752)`, fresnel rim, pinpoint specular). The
   only difference for V.7.7C is the call shape: `drawBackgroundWeb()`
   currently calls `drawWorld(refractedUV, ...)` inline; the dispatched
   COMPOSITE must instead sample `worldTex` (the per-stage offscreen output)
   so we are not recomputing the entire WORLD per drop pixel.

4. `arachne_world_sampler` is already declared in `Arachne.metal` and
   already used by COMPOSITE for the backdrop sample. No new sampler
   needed.

5. Decision-ID numbering: D-092 was V.7.7B (most recent). V.7.7C is
   D-093 unless something else has landed in between — verify with
   `grep '^## D-0' docs/DECISIONS.md | tail -3` and use the next free
   integer.

6. `git status` is clean except `prompts/*.md` and `default.profraw`.

────────────────────────────────────────
GOAL
────────────────────────────────────────

After V.7.7C the staged Arachne COMPOSITE renders **photographic
dewdrops** instead of glassy amber bullseyes:

- Each drop refracts the WORLD pass underneath it. The forest backdrop
  visible inside the drop is **inverted** (top of WORLD shows at bottom
  of drop) — the classic dewdrop signature from refs `01_macro_dewy_web_on_dark.jpg`,
  `03_micro_adhesive_droplet.jpg`.
- A thin Schlick-fresnel rim brightens the drop's edge toward the warm
  key-light tint.
- A small sharp specular pinpoint sits where the dominant light direction
  hits the drop's spherical cap (per §5.8).
- A subtle dark edge ring sits just inside the silhouette where refraction
  breaks down at grazing angles.
- Drop response to audio stays D-026 deviation-form (continuous gain ≥ 2×
  beat accent, CLAUDE.md rule of thumb) — the existing `(baseEmissionGain
  + beatAccent)` modulation pattern is preserved.

The pool-of-webs system (V.7.5 4-slot pool, `ArachneState`, alternating-pair
spoke order, chord-segment outside-in spiral) stays as-is. The build state
machine refactor (single foreground build with frame → radials → INWARD
spiral over 60 s, drop accretion over time, anchor blobs on near-frame
branches, completion event) is **V.7.7C.2 / V.7.7D scope** — not in scope
for V.7.7C.

V.7.7C's success is **"drops read as photographic dewdrops sampling the
forest behind them"** — a single-purpose, single-shader-block change with
big visual impact. It is **not** a cert run — V.7.10 is gated on V.7.7D
landing.

The risk to manage is **scope creep**: while replacing the drop block, the
temptation to "also redo the build state machine" or "wire anchors to actual
branch positions" is exactly how V.7.7A's intended scaffold migration
ballooned into a monolithic shader rewrite that was then retired. Keep
V.7.7C surgical: replace the two drop blocks; do not touch anything else.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

The increment has one shader sub-item (with parallel edits at two call
sites) plus golden-hash regeneration. Land in a single commit.

──── Sub-item 1: replace the mat_frosted_glass drop overlay with the §5.8 recipe ────

EDIT — `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`

The COMPOSITE fragment currently has two near-identical drop-rendering
blocks, one inside the anchor-web block (~lines 743–762) and one inside
the pool-web loop (~lines 807–826). Both blocks must be updated in
parallel; the recipe is identical for anchor + pool drops.

**The replacement recipe** (lifted mechanically from the §5.8 spec and
the existing `drawBackgroundWeb()` reference):

```metal
if (wr.dropCov > 0.01) {
    float2 d2     = wr.dropVec;
    float  rDrop  = wr.dropRadius;
    float  rNorm  = length(d2) / max(rDrop, 1e-5);

    // Spherical-cap normal at sample point inside the drop (§5.8).
    float  h      = sqrt(max(0.0, 1.0 - rNorm * rNorm));
    float3 sphN   = normalize(float3(d2 / max(rDrop, 1e-5), h));
    const float3 kViewRay = float3(0.0, 0.0, 1.0);

    // Snell's-law refraction (§5.8): air n=1.0 → water n=1.33; eta = 0.752.
    // Sample worldTex at the refracted UV — NOT drawWorld() — because
    // the WORLD stage already wrote its forest backdrop into worldTex
    // and re-evaluating drawWorld() per drop pixel would multiply the
    // WORLD render cost by the drop coverage area.
    float3 refr        = refract(-kViewRay, sphN, 0.752);
    // worldSampleScale ~ 2.5×r per spec (controls how much the WORLD
    // is "magnified" through the drop). The 8× value used in
    // drawBackgroundWeb is the V.7.7-redo background-web tuning;
    // foreground drops should use 2.5×r per §5.8 — visually tighter
    // and matches refs 01 / 03.
    float2 refractedUV = uv + refr.xy * (rDrop * 2.5);
    float3 bgSeen      = worldTex.sample(arachne_world_sampler, refractedUV).rgb;

    // Fresnel rim (§5.8) — Schlick power 5; edge brightens toward warm
    // key-light tint. Schlick at edge ≈ 1.0; rim addition ~0.4 per spec.
    float  fresnel  = pow(1.0 - saturate(sphN.z), 5.0);
    float3 rimTint  = kLightCol * 0.85;
    float3 dropCol  = mix(bgSeen, rimTint, saturate(fresnel * 0.40));

    // Pinpoint specular (§5.8) — tight highlight at half-vector position
    // on the spherical cap. kL is the key-light direction already declared
    // at the top of the fragment; kViewRay points OUT of the screen.
    float3 halfVec  = normalize(kL.xy + kViewRay.xy);
    float2 specPos  = halfVec.xy * rDrop * 0.6;
    float  specD    = length(d2 - specPos) / max(rDrop, 1e-5);
    float  specMask = 1.0 - smoothstep(0.0, 0.20, specD);
    dropCol += rimTint * specMask * 1.0;

    // Dark edge ring (§5.8) — thin darker band inside the silhouette
    // where refraction breaks down at grazing angles. Per spec:
    //   darkRing = smoothstep(0.85, 0.95, |localUV|)
    //            * (1.0 - smoothstep(0.95, 1.0, |localUV|))
    //   color *= (1.0 - darkRing * 0.5)
    float  ring1    = smoothstep(0.85, 0.95, rNorm);
    float  ring2    = 1.0 - smoothstep(0.95, 1.0, rNorm);
    float  darkRing = ring1 * ring2;
    dropCol *= (1.0 - darkRing * 0.50);

    // Audio-reactive emission gain — preserve the V.7.5 D-026 modulation
    // shape so drops still swell with the music. (baseEmissionGain ±0.09
    // continuous + beatAccent ≤ 0.07 — ratio 2.57× per CLAUDE.md rule.)
    dropCol *= (baseEmissionGain + beatAccent);

    dropColorAccum += dropCol * wr.dropCov;
}
```

Apply this block at **both** call sites (anchor + pool). The pool block
should additionally multiply `wr.dropCov` by `w.opacity` (preserving the
V.7.5 `scaledDrop` semantics) — i.e. the pool block's existing
`scaledDrop = wr.dropCov * w.opacity` calculation stays, and the final
accumulation reads `dropColorAccum += dropCol * scaledDrop` so older /
fading webs contribute proportionally less.

**What goes away.** The `MaterialResult glass = mat_frosted_glass(...)`
call, the `dropAmber = (1.00, 0.78, 0.45)` constant, the
`reflect(-kL, detail_normal)` reflection vector, and the
`glintAdd = (1.00, 0.95, 0.85)` cool-white pinpoint. They are all
superseded by the spec recipe (which has its own warm-tinted specular).

**What stays untouched at both call sites.** The drop-coverage gate
(`wr.dropCov > 0.01`), the strand walk above the drop block, every line
in the rest of the fragment (mist, dust motes, spider, final compose,
0.95 clip).

**`drawBackgroundWeb()` stays as dead reference code.** It is still not
dispatched by anything; V.7.7C does not reintroduce it. The two
foreground recipes (anchor + pool) and the dead-code background recipe
will look almost identical; that is fine and intentional. V.7.7C.2 will
revisit background webs (§5.12) once the foreground build state machine
is in place.

──── Sub-item 2: golden-hash regeneration ────

After the shader port:

- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift`
  — regenerate Arachne hashes via
  `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter test_printGoldenHashes`,
  copy the new value into `goldenPresetHashes`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift`
  — regenerate via `test_printSpiderGoldenHash` similarly.

The hashes will diverge from the V.7.7B values. Document the new values in
the commit message. The Arachne regression renders the COMPOSITE fragment
with `worldTex` unbound (the test path samples zero), so the **refraction
recipe will sample zero** and the drops will read close to black + thin
warm rim + warm pinpoint + dark ring. That is correct for the regression
test (it is not a visual-quality assertion, only a pixel-stability gate);
the harness PNGs are where visual quality is reviewed.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT replace the V.7.5 4-web pool with a single-foreground build
  state machine. V.7.7C.2 / V.7.8 scope.
- Do NOT implement frame → radials → INWARD spiral build phases over
  60 s. V.7.7C.2 / V.7.8 scope.
- Do NOT add per-chord drop accretion over build time. V.7.7C.2 / V.7.8
  scope (the existing per-pixel hash-jitter spacing stays for now).
- Do NOT add adhesive anchor blobs at frame anchor points. V.7.7C.2 /
  V.7.8 scope.
- Do NOT modify `drawWorld()`. It is the WORLD pillar's responsibility;
  this increment touches only COMPOSITE drop rendering.
- Do NOT modify `arachneEvalWeb()`. The drop-vector + drop-radius
  outputs it produces are the inputs the new recipe consumes; no change
  needed.
- Do NOT modify `ArachneState.swift` or any `Arachnid/*.swift`.
  V.7.7C is shader-only.
- Do NOT modify `Arachne.json`. The current declaration
  (`passes: ["staged"]`, two-stage list) is correct.
- Do NOT add or modify visual references in
  `docs/VISUAL_REFERENCES/arachne/`. The 19-image set is final for V.7.10.
- Do NOT run the M7 contact-sheet review. V.7.7C is intermediate; M7 is
  V.7.10.
- Do NOT change spec strength constants without explicit reason — the
  spec values (`fresnel * 0.40`, `darkRing * 0.50`, `pow(... , 5.0)`,
  `2.5 × rDrop` magnification) are all calibrated against refs 01 + 03.
  If a tuning change feels needed at runtime, surface to Matt before
  diverging.
- Do NOT inline-call `drawWorld()` from inside the drop block. The whole
  point of staged composition is that the WORLD stage runs once into a
  half-res target; refraction samples that target, never re-evaluates
  the world.

────────────────────────────────────────
DESIGN GUARDRAILS (CLAUDE.md)
────────────────────────────────────────

- **Drops sample `worldTex`, not `drawWorld()`.** This is the cross-stage
  geometry contract V.ENGINE.1 / V.7.7B established. Re-evaluating
  `drawWorld` per drop pixel would multiply WORLD cost by drop coverage
  area and defeat the staged-composition pivot. CLAUDE.md §What NOT To
  Do already documents the equivalent rule for the COMPOSITE backdrop;
  V.7.7C extends it to drop refraction.
- **Snell's-law direction.** `eta = 0.752 = 1.0 / 1.33` is air → water.
  The incident ray is `-kViewRay` (pointing INTO the screen, since the
  view ray points OUT). With `dot(sphN, -kViewRay) = -h < 0`, `refract`
  returns the correctly-bent transmission ray. If the refracted UVs
  invert the world wrong-way (top of WORLD shows at top of drop instead
  of bottom), the sign on `refr.xy` is wrong. Reference
  `drawBackgroundWeb()` at ~line 590-595 for the working sign
  convention.
- **D-026 audio compliance.** The `(baseEmissionGain + beatAccent)`
  multiplicative gain on `dropCol` preserves the V.7.5 deviation-form
  audio response. The continuous driver
  (`1.0 + 0.18 × f.bass_att_rel`) and beat accent
  (`0.07 × max(0, drums_energy_dev)`) ratios stay 2.57× — satisfies
  CLAUDE.md "continuous ≥ 2× beat" rule of thumb.
- **Failed Approach #34 caution.** The chord-segment SDF in
  `arachneEvalWeb` is the load-bearing geometry that prevents the V.7.5
  bullseye-degenerate Archimedean. V.7.7C does not touch
  `arachneEvalWeb`. If you find yourself reaching into it, stop —
  that's V.7.7C.2 / V.7.8 work.
- **CLAUDE.md What NOT To Do additions.** Add one line to that section:
  "Do not call `drawWorld()` from inside `arachne_composite_fragment`
  drop blocks. Drop refraction must sample `worldTex` at
  `[[texture(13)]]`. D-092/D-093."

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters.

1. **Build (engine)**: `swift build --package-path PhospheneEngine` —
   must succeed with zero warnings on touched files.

2. **Targeted suites**:
   ```
   swift test --package-path PhospheneEngine \
       --filter "StagedComposition|StagedPresetBufferBinding|PresetRegression|ArachneSpiderRender|ArachneState"
   ```
   Each suite must pass post-port. `PresetRegressionTests` will fail
   until the golden hash is regenerated; expect that step to be the
   iterative loop.

3. **Visual harness — staged per-stage** (load-bearing for V.7.7C):
   ```
   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
       --filter "renderStagedPresetPerStage" 2>&1 | tee /tmp/v77c_staged.log
   ```
   Inspect `/tmp/phosphene_visual/<ISO8601>/Arachne_*_composite.png`.
   Expected (silence / mid / beat — drops are the deciding signal):
   - Drops are clearly visible against the strand structure.
   - Inside each drop there is a **darker, recognisable forest fragment**
     — visibly the WORLD pillar's atmosphere + branch silhouettes,
     refracted through the drop's spherical-cap normal. NOT a flat amber
     fill.
   - Drops have a thin warm rim along their silhouette (Schlick fresnel)
     and a small sharp warm pinpoint where the key light hits the cap.
   - Drops have a subtle dark edge ring just inside the rim.
   - Mid / beat fixtures: drops swell brighter via the audio gain (V.7.5
     D-026 modulation preserved), but the refraction signature stays.

4. **Visual harness — contact sheet** (optional but valuable):
   ```
   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
       --filter "renderPresetVisualReview" 2>&1 | tee /tmp/v77c_contact.log
   ```
   `Arachne_contact_sheet.png` shows the steady-mid composite over refs
   `01` / `04` / `05` / `08`. The legacy single-pipeline render path
   leaves `worldTex` unbound, so foreground drops will read with thin
   warm rim + dark ring + zero refracted backdrop (drops will be near-
   black inside). That is **expected**, not a regression — full
   refraction is exercised only by `renderStagedPresetPerStage`. State
   this explicitly in the commit message.

5. **Full engine suite**: `swift test --package-path PhospheneEngine` —
   must remain green. The pre-existing `ProgressiveReadinessTests`
   parallel-load timing flakes (CLAUDE.md U.11 entry) trip independently
   of this increment and pass in isolation; document in the commit
   message if they appear under full-suite parallel load.

6. **App suite**: `xcodebuild -scheme PhospheneApp -destination
   'platform=macOS' test 2>&1 | tail -5` — must end clean.

7. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml
   --quiet PhospheneEngine/Sources/Presets/Shaders/Arachne.metal
   PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift
   PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift`
   — zero violations on touched files. The `Arachne.metal` file-length
   gate is exempt per `SHADER_CRAFT.md §11.1`.

8. **Manual smoke (recommended)**: launch the app, force Arachne via
   developer keybinding, observe live drop rendering. Confirm:
   - Drops magnify the forest behind them (you can see branch silhouettes
     + atmosphere fragments inverted inside drops).
   - Warm rim and warm pinpoint visible.
   - Dark edge ring visible at the silhouette.
   - Drops swell with the music's bass deviation but the refraction
     character holds across silence / mid / loud passages.
   - No 12-spoke + concentric-ring placeholder visible (V.7.7B baseline
     locked).

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** §Increment V.7.7C: file a new section
   if one does not already exist; flip status to ✅ with the date and
   carry-forward (V.7.7C.2 / V.7.8 build state machine; V.7.7D spider +
   vibration; V.7.10 cert).

2. **`docs/DECISIONS.md`** — append `D-<next>` documenting:
   - The decision to sample `worldTex` (not `drawWorld()`) inside the
     drop block — cross-stage geometry contract per V.ENGINE.1 / D-072.
   - The decision to delete `mat_frosted_glass` from the foreground drop
     recipe (vs keeping it as a fallback). It is superseded by the
     §5.8 recipe; the cookbook entry stays available for other presets.
   - The decision to preserve the V.7.5 4-web pool for V.7.7C and defer
     the single-foreground build state machine to V.7.7C.2 / V.7.8.
     Cite Failed Approach #49 (constant-tuning on a renderer
     structurally missing layers — the refraction layer is what V.7.7C
     adds).
   - The `worldSampleScale = 2.5 × rDrop` choice (vs the V.7.7-redo
     `8.0 × rDrop` used by `drawBackgroundWeb`). Tighter magnification
     reads as foreground dewdrop per refs 01 / 03; the larger
     magnification was tuned for background webs at depth (§5.12) and
     is preserved in the dead-code reference for V.7.7C.2 to use as-is.

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X] V.7.7C`
   entry summarising the drop recipe replacement. List the LOC delta
   on `Arachne.metal` (small — two roughly-30-line blocks rewritten,
   net change ±0).

4. **`CLAUDE.md`**:
   - §Module Map: update `Arachne.metal` description from
     "V.7.7B: staged WORLD + COMPOSITE fragments using shared
     `drawWorld()` + `arachneEvalWeb()` free functions" to
     "V.7.7C: drops upgraded to §5.8 Snell's-law refraction sampling
     `worldTex`; build state machine + anchor logic pending in V.7.7C.2."
   - §What NOT To Do: add "Do not call `drawWorld()` from inside
     `arachne_composite_fragment` drop blocks. Drop refraction samples
     `worldTex` at `[[texture(13)]]`. D-092/D-093."
   - §Recent landed work: append the V.7.7C entry.

5. **`docs/QUALITY/KNOWN_ISSUES.md`**:
   - No new entries unless V.7.7C itself surfaces a defect.

────────────────────────────────────────
COMMITS
────────────────────────────────────────

One commit. The change is shader-only and small enough to land
atomically.

`[V.7.7C] Arachne: refractive dewdrops (§5.8 Snell's-law) (D-<next>)`

- `Arachne.metal` — both drop blocks (anchor + pool) replaced with the
  §5.8 refraction recipe sampling `worldTex`.
- `PresetRegressionTests.swift` — Arachne hash regenerated.
- `ArachneSpiderRenderTests.swift` — spider forced hash regenerated.
- All docs from §Documentation Obligations.

Local commit to `main` only. Do NOT push without explicit "yes, push"
approval. The visual change is significant — Arachne drops go from
"glassy amber overlay" to "photographic dewdrops" — and pushing it
remotely communicates "the cert review is imminent" prematurely.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **Refracted UVs invert wrong direction (top of WORLD shows at top of
  drop)**: the sign on `refr.xy` is inverted. The §5.8 spec and
  `drawBackgroundWeb()` agree on `refractedUV = uv + refr.xy * (...)`
  — i.e. ADD the refraction offset. If drops read non-inverted, swap
  the sign. STOP and inspect a single drop with a sentinel `bgSeen =
  refractedUV.y` colour to verify the offset direction before tuning.

- **Drops read flat / non-refractive (no visible WORLD inside)**: most
  likely cause is `worldTex` being unbound when the harness path is
  the legacy `renderFrame` path (this is documented as expected for
  the contact-sheet harness, but unexpected for the staged per-stage
  harness). Confirm the staged per-stage harness binds the WORLD
  texture into texture slot 13 of the COMPOSITE encode (it does as of
  V.7.7B; no engine change required). Second cause: `worldSampleScale`
  too small — try doubling to `5.0 × rDrop` and confirm; if drops
  start to show forest at 5×, the issue is the magnification, not the
  sampler. Restore the spec value once the issue is identified.

- **Specular pinpoint sits in the wrong place / off-centre**: the spec
  uses `halfVec.xy` projected onto the spherical cap. `kL` is declared
  in screen space (xy) at the top of the fragment. If the highlight
  drifts wrong with viewing angle, double-check the half-vector
  computation matches §5.8 (`halfVec = normalize(kL.xy + viewRay.xy)`).

- **Dark edge ring over-darkens at the silhouette**: the spec value is
  `darkRing * 0.5`. If silhouettes go to near-black, lower to 0.3 and
  surface to Matt — but try the spec value first. Refs 01 + 03 are
  unambiguous about a visible dark ring.

- **Golden hashes don't stabilize across runs**: indicates the new
  refraction sampling is reading non-deterministic memory (e.g.
  `worldTex` is uninitialised on the regression test path). Check
  that `worldTex` is bound in the regression render: it's intentionally
  unbound (the regression test renders COMPOSITE alone), and Metal
  returns deterministic zero for unbound texture samples. If you see
  drift, the issue is elsewhere — STOP and inspect the noise textures
  bound at slots 4–8.

- **The Arachne regression render goes pure-black after the change**:
  most likely cause is the drop block now multiplying through to zero
  because the refracted sample reads zero (unbound `worldTex` →
  `bgSeen = 0`), AND the rim+specular+ring contributions are too small
  to register against the zero base. Visually correct for the regression
  test path; the harness path is where you see drops with refraction.
  STOP and re-confirm by running the staged per-stage harness — if THAT
  output also reads black, the issue is real.

- **STOP and report instead of forging ahead** if:
  - The §5.8 recipe needs fields beyond `wr.dropVec` / `wr.dropRadius`
    that `arachneEvalWeb` doesn't currently produce — that means the
    recipe assumes geometry the WEB pillar isn't carrying yet, surface
    before extending `arachneEvalWeb`.
  - Refraction sampling pushes per-frame cost above the Tier 2 ≤ 6 ms
    budget (`FrameBudgetManager` should report). Drops are bounded
    (closest drop per pixel only), so this should not happen — but if
    it does, surface to Matt before optimising. The `worldSampleScale`
    knob and the drop-coverage early-exit are the natural levers.
  - The §5.8 dark-edge-ring formula causes Metal compile errors (it
    uses `smoothstep` chained on a saturated input — Metal 3.1 should
    handle this fine, but if not, try `min(1.0, …)` instead of
    `saturate`).

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md` §5.8 Drops, §5.11
  Lighting interaction with the world, §3A staged renderer
  architecture.
- Architectural pivot record: `docs/DECISIONS.md` D-072 (compositing-
  anchored diagnosis), D-092 (V.7.7B port).
- Failed Approaches: `CLAUDE.md` #34 (`abs(fract−0.5)` SDF inversion —
  do not regress to circular Archimedean spirals), #49 (constant-
  tuning on missing compositing layers — V.7.7C ADDS the refraction
  layer that the V.7.5 era was missing).
- Reference recipes:
  - `Arachne.metal` `drawBackgroundWeb()` at ~line 563 — V.7.7-redo
    Snell's-law block. Almost identical to the §5.8 recipe; the only
    differences are it inline-calls `drawWorld()` (V.7.7C samples
    `worldTex` instead) and uses `8 × rDrop` magnification (V.7.7C uses
    the §5.8 spec value `2.5 × rDrop`).
  - `Arachne.metal` `arachne_composite_fragment` ~lines 743 + 807 —
    V.7.5 `mat_frosted_glass` blocks the new recipe replaces.
- Visual references:
  - `docs/VISUAL_REFERENCES/arachne/01_macro_dewy_web_on_dark.jpg` —
    hero frame match, drops as visual hero.
  - `docs/VISUAL_REFERENCES/arachne/03_micro_adhesive_droplet.jpg` —
    drop-spacing + refraction signature reference.
  - `docs/VISUAL_REFERENCES/arachne/04_specular_silk_fiber_highlight.jpg`
    — backlit silk + atmospheric glow context (§5.11 lighting).
- Forward chain (do NOT do here):
  - V.7.7C.2 / V.7.8 — single-foreground build state machine
    (frame → radials → INWARD spiral over 60 s); per-chord drop
    accretion over build time; anchor-blob terminations on near-frame
    branches; foreground completion event via V.7.6.2 channel.
  - V.7.7D — spider pillar deepening (anatomy + material + gait +
    listening pose); whole-scene 12 Hz vibration on bass.
  - V.7.10 — Matt M7 cert review.
- CLAUDE.md sections to read: §Increment Completion Protocol, §Defect
  Handling Protocol, §GPU Contract Details, §Visual Quality Floor,
  §Failed Approaches, §What NOT To Do.
