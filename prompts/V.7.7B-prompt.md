Execute Increment V.7.7B — Promote V.7.7-redo WORLD + V.7.8 chord-spiral
into the dispatched staged path; extend staged dispatch to bind per-preset
fragment buffers.

Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md` §3A (staged renderer
architecture), §4 (WORLD pillar), §5.6 (chord-segment capture spiral).
Authoritative plan entry: `docs/ENGINEERING_PLAN.md` §Increment V.7.7B
(filed by the doc-correction prompt that runs before this one).
Architectural pivot record: `docs/DECISIONS.md` D-072 (compositing layers),
plus the V.ENGINE.1 / V.7.7A scaffold landing.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. The doc-correction prompt (`prompts/ARACHNE-DOC-CORRECTION-prompt.md`)
   has run. CLAUDE.md and ENGINEERING_PLAN.md correctly state that
   V.7.7 / V.7.8 / V.7.9 are *not* live in the dispatched path and that
   V.7.7B is the active increment. Verify with:
   `grep "Status correction (2026-05-07)" docs/ENGINEERING_PLAN.md | wc -l`
   — expect 3.

2. BUG-007.9 (hybrid runtime recalibration) and QR.4 (UX dead ends +
   duplicate `SettingsStore`) have landed. Verify with:
   `git log --oneline | grep -E '\[(BUG-007\.9|QR\.4)\]'`

3. The current Arachne dispatched path is still V.7.7A scaffold +
   placeholders. Confirm:
   `grep -A1 'arachne_world_fragment\|arachne_composite_fragment' PhospheneEngine/Sources/Presets/Shaders/Arachne.metal | head -10`
   — expect the placeholder bodies (vertical gradient + 12-spoke
   overlay), not `drawWorld(...)` calls.

4. The dead reference code is intact and reusable:
   `grep -n '^static float3 drawWorld\|^static ArachneWebResult arachneEvalWeb\|^fragment float4 arachne_fragment' PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`
   — expect three hits at approximately lines 142, 265, 617.

5. Decision-ID numbering: D-090 was the most recent (QR.3). QR.4 likely
   added D-091. Verify with `grep '^## D-0' docs/DECISIONS.md | tail -3`
   and use the next free integer.

6. `git status` is clean except `prompts/*.md` and `default.profraw`.

────────────────────────────────────────
GOAL
────────────────────────────────────────

Restore visual parity with the pre-V.7.7A monolithic shader, on the
V.ENGINE.1 staged-composition scaffold. After V.7.7B:

- `arachne_world_fragment` renders the full six-layer dark-close-up
  forest (mood-tinted atmosphere + radial mist + light shaft + dust
  motes + organic floor + bark-textured branches) — what
  `drawWorld()` already implements.
- `arachne_composite_fragment` samples `worldTex` at `[[texture(13)]]`
  and overlays the active foreground web via `arachneEvalWeb()`
  (chord-segment capture spiral, not concentric rings) plus the spider
  if present.
- Engine + harness staged dispatch correctly bind the per-preset
  ArachneWebGPU buffer at fragment buffer index 6 and ArachneSpiderGPU
  at index 7. (This was the gap left by V.7.7A: the legacy fragment
  read these via `directPresetFragmentBuffer` / `directPresetFragmentBuffer2`,
  which the staged path does not consult.)
- Result: Arachne renders at parity with the V.7.5/V.7.7-redo/V.7.8
  baseline — minus refractive droplets, biology-correct build state
  machine, spider deepening, and whole-scene vibration, which are
  V.7.7C / V.7.7D scope.

The increment is **not** a cert run. The V.7.10 cert review is gated on
V.7.7D landing. V.7.7B's success is "harness output reads as the V.7.5
v5 build with the V.7.7-redo WORLD pillar and V.7.8 chord-spiral applied"
— a known intermediate state, not an end state.

The risk to manage is **scope creep**: while porting `drawWorld` into the
staged path, the temptation to "also fix the silk material" or "add the
spider trigger" is exactly how V.7.7A's intended one-step scaffold
migration ballooned into ~3 hours of monolithic shader work that was then
retired. Keep V.7.7B mechanical: port what already exists; do not write
new shader content.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

The increment has four sub-items, sequenced. Land them in two commit
boundaries.

──── COMMIT 1: engine + harness — bind per-preset buffers in staged dispatch ────

1. EDIT — `PhospheneEngine/Sources/Renderer/RenderPipeline+Staged.swift`

   `encodeStage()` (around line 187-215) currently binds:
   - buffer(0) = FeatureVector
   - buffer(1) = FFT magnitudes
   - buffer(2) = waveform
   - buffer(3) = StemFeatures (as `setFragmentBytes`, copy of the inout
     arg)
   - buffer(5) = SpectralHistory
   - texture(13+) = sampled stage outputs

   It does NOT bind:
   - buffer(6) = preset-specific fragment buffer #1
     (`directPresetFragmentBuffer`)
   - buffer(7) = preset-specific fragment buffer #2
     (`directPresetFragmentBuffer2`)

   These are owned by `RenderPipeline` already
   ([RenderPipeline.swift:145-153](PhospheneEngine/Sources/Renderer/RenderPipeline.swift:145))
   and consumed by the legacy `mv_warp` / direct paths via the existing
   `setDirectPresetFragmentBuffer` / `setDirectPresetFragmentBuffer2`
   API ([RenderPipeline+PresetSwitching.swift:122,128](PhospheneEngine/Sources/Renderer/RenderPipeline+PresetSwitching.swift:122)).

   Extend `encodeStage()` to bind both buffers when present:

   ```swift
   if let presetBuf = directPresetFragmentBufferLock.withLock({ directPresetFragmentBuffer }) {
       encoder.setFragmentBuffer(presetBuf, offset: 0, index: 6)
   }
   if let presetBuf2 = directPresetFragmentBuffer2Lock.withLock({ directPresetFragmentBuffer2 }) {
       encoder.setFragmentBuffer(presetBuf2, offset: 0, index: 7)
   }
   ```

   Add a tight `// MARK:` comment at the binding site documenting that
   slots 6/7 are reserved for preset-specific fragment buffers and the
   binding is per-frame uniform across all stages of a staged preset
   (i.e. WORLD and COMPOSITE both see the same `ArachneWebGPU` /
   `ArachneSpiderGPU` snapshot).

   Place the binding BEFORE the sampled-textures binding loop, after the
   noise textures. Do not change `kStagedSampledTextureFirstSlot` (still
   13).

2. EDIT — `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift`

   `encodeStagePass()` (around line 378-407) has the same gap. Mirror
   the engine fix:
   - Accept an optional `arachneState: ArachneState?` parameter (or a
     more general `presetBuffer1: MTLBuffer?` / `presetBuffer2: MTLBuffer?`
     pair — pick whichever reads cleaner; the harness is already
     Arachne-aware via the legacy `renderFrame()` path so a typed param
     is acceptable).
   - When non-nil, bind `arachneState.webBuffer` at index 6 and
     `arachneState.spiderBuffer` at index 7.

   Update both staged test entry points
   (`renderStagedPresetPerStage`, `renderStagedFrame`) to construct the
   warmed `ArachneState` (mirroring the existing 30-tick warmup at
   [PresetVisualReviewTests.swift:143-150](PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift:143))
   when `presetName == "Arachne"`, and pass it through to
   `encodeStagePass`. For "Staged Sandbox" (the V.ENGINE.1 reference
   preset), pass nil — it has no per-preset buffer needs.

3. NEW TEST — `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/StagedPresetBufferBindingTests.swift`

   Regression test for the new binding. Without this, V.7.7B's engine
   change can silently regress under future refactoring.

   Approach:
   - Construct a `RenderPipeline` for a synthetic two-stage staged
     preset that reads buffer(6) in its final stage and writes a
     known sentinel value to its output texture.
   - Set a sentinel `MTLBuffer` via `setDirectPresetFragmentBuffer`.
   - Drive one frame through the staged path.
   - Read back the offscreen texture and assert the sentinel value
     was correctly read.

   ~80 LOC. If the synthetic-preset construction is awkward in unit
   testing, an alternative is to write the test against Arachne with
   a known `ArachneState` seed and assert a specific pixel of the
   output is non-black (i.e. the COMPOSITE stage successfully read
   the web buffer to render a strand). This is brittler but cheaper.

──── COMMIT 2: shader port — promote drawWorld() + arachneEvalWeb() into staged fragments ────

4. EDIT — `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`

   Replace the placeholder bodies of `arachne_world_fragment` (current
   lines 883-918) and `arachne_composite_fragment` (current lines
   920-962) with calls into the existing `drawWorld()` and
   `arachneEvalWeb()` free functions.

   **`arachne_world_fragment`** — gain access to the web GPU buffer
   so it can read `webs[0].row4` for `moodRow` and `accumulatedAudioTime`:

   ```metal
   fragment float4 arachne_world_fragment(
       VertexOut in [[stage_in]],
       constant FeatureVector& f [[buffer(0)]],
       device const ArachneWebGPU* webs [[buffer(6)]]
   ) {
       float4 moodRow = webs[0].row4;
       float accTime = moodRow.z;
       float3 col = drawWorld(in.uv, moodRow, accTime);
       return float4(col, 1.0);
   }
   ```

   The free-function `drawWorld()` at line 142 already returns the
   full six-layer dark-close-up forest with silence anchor. No edits
   to `drawWorld()` itself.

   **`arachne_composite_fragment`** — sample `worldTex` for the
   backdrop, then walk the active web array and overlay strands. The
   monolithic legacy fragment at line 617 contains the full reference
   implementation (web pool walk + arachneEvalWeb call + emission
   gain + silence anchor). Mechanically lift those pieces (NOT the
   `drawWorld` call — that's now in the WORLD stage):

   ```metal
   fragment float4 arachne_composite_fragment(
       VertexOut in [[stage_in]],
       constant FeatureVector& f [[buffer(0)]],
       constant StemFeatures& stems [[buffer(3)]],
       device const ArachneWebGPU* webs [[buffer(6)]],
       device const ArachneSpiderGPU& spider [[buffer(7)]],
       texture2d<float, access::sample> worldTex [[texture(13)]]
   ) {
       float2 uv = in.uv;
       float3 col = worldTex.sample(arachne_world_sampler, uv).rgb;

       // … exact lift from arachne_fragment lines ~660-820:
       //   for each active web slot:
       //       wr = arachneEvalWeb(uv, ...)
       //       col += silkTint * wr.strandCov * gain;
       //       col += dropEmissive * wr.dropMask * gain;
       //   spider rendering block (already in legacy fragment).
       //   silence anchor (already in legacy fragment).

       return float4(col, 1.0);
   }
   ```

   Use `git diff` to confirm the lift is mechanical: every line in
   the new `arachne_composite_fragment` should be traceable to a line
   in the legacy `arachne_fragment` (post-port the dead reference
   `arachne_fragment` becomes redundant; see clean-up step below).

   **Cleanup:** after the port lands and tests pass, delete the legacy
   `arachne_fragment` (lines 617-855) along with its preceding comment
   block. Keep `drawWorld()` and `arachneEvalWeb()` and their helpers
   — those are now actively dispatched. Total file should drop from
   962 LOC to roughly 450-500 LOC.

   **Do NOT** add features that were not in the V.7.5 / V.7.7-redo /
   V.7.8 baseline:
   - No refractive droplets (V.7.7C scope).
   - No biology-correct build state machine — the existing
     `ArachneState` pool-of-webs system stays as-is for V.7.7B
     (V.7.7C scope).
   - No spider trigger / pose / gait changes (V.7.7D scope).
   - No whole-scene vibration (V.7.7D scope).
   - No silk material upgrades (V.7.7D scope).

   The V.7.7-redo `drawBackgroundWeb()` was removed from dispatch in
   the V.7.7-redo commit ("circular drop-patches produced oval
   artefacts"). Do NOT re-instate it — V.7.7C revisits with Snell's-law
   refraction.

──── 5. Golden-hash regeneration ────

After the shader port:
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift`
  — regenerate Arachne hashes via
  `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --filter test_printGoldenHashes`,
  copy the printed value into `goldenPresetHashes`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift`
  — regenerate via the same mechanism.

The hashes will diverge from the V.7.7A placeholder values. Document the
new values in the commit message. Pre-V.7.7A baseline values exist in
`fa5dacdf` and `3536a023` commit messages for sanity check; expect the
new V.7.7B hashes to be similar but not identical (the staged compile
path generates different code than the monolithic compile path).

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT implement Snell's-law refractive droplets. V.7.7C scope.
- Do NOT implement the biology-correct frame → radial → spiral build
  state machine. V.7.7C scope. The V.7.5 pool-of-webs `ArachneState`
  stays for V.7.7B.
- Do NOT modify `ArachneState.swift` or any `Arachnid/*.swift`. V.7.7B
  is a shader + engine port; pool-of-webs state machine is unchanged.
- Do NOT touch the spider — its current trigger and silhouette behavior
  are inherited as-is from V.7.5. V.7.7D revisits.
- Do NOT add or modify visual references in `docs/VISUAL_REFERENCES/arachne/`.
  The 19-image set is final for V.7.10.
- Do NOT modify `Arachne.json`. The current declaration
  (`passes: ["staged"]`, two-stage list) is correct. The
  `description` field is correct ("V.7.7A staged-composition scaffold")
  for now — V.7.7C will rewrite it when the build state machine + drops
  land.
- Do NOT run the M7 contact-sheet review. V.7.7B is intermediate; M7 is
  V.7.10.
- Do NOT extend `RenderPipeline+Staged.encodeStage` to take parameters
  beyond the current signature. The fix is to read the existing
  `directPresetFragmentBuffer` / `directPresetFragmentBuffer2` fields
  from inside `encodeStage`, not to add a parameter.
- Do NOT collapse the legacy `arachne_fragment` and the new staged
  fragments into a single function. Stage isolation is the V.ENGINE.1
  contract; merging would defeat the architectural pivot the entire
  V.7.7+ stream rests on.

────────────────────────────────────────
DESIGN GUARDRAILS (CLAUDE.md)
────────────────────────────────────────

- **Buffer slots 6/7 are reserved for per-preset fragment buffers.** No
  other binding in the staged path may use these. Other presets that
  need additional buffers should add new `directPresetFragmentBuffer3`
  / `4` slots (i.e. via a new pair of fields on `RenderPipeline`)
  rather than overload 6/7. Add this as a one-line entry in CLAUDE.md
  §GPU Contract Details / Buffer Binding Layout.
- **Staged compile path includes the standard preamble only.** It does
  NOT include the `mvWarpPreamble`. Any helper that depends on
  `MVWarpPerFrame` must stay out of the staged compile unit. The legacy
  `arachne_fragment` removal in this increment is partly motivated by
  this: keeping monolithic dead code in the file works only if it
  doesn't reference mv-warp types, and the legacy fragment is cleanly
  free of them.
- **The staged composite stage is the place for cross-stage geometry,
  not for re-rendering WORLD.** WORLD lives in the WORLD stage and is
  sampled via `worldTex` at texture(13). Calling `drawWorld()` from
  the COMPOSITE fragment defeats the architectural separation. Add a
  CLAUDE.md "What NOT to do" entry: "Do not call `drawWorld()` from
  `arachne_composite_fragment`. The WORLD stage owns it; COMPOSITE
  samples the texture."

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters.

1. **Build (engine)**: `swift build --package-path PhospheneEngine` —
   must succeed with zero warnings on touched files.

2. **Per-suite tests** (engine):
   ```
   swift test --package-path PhospheneEngine \
       --filter "StagedComposition|StagedPresetBufferBinding|PresetRegression|ArachneSpiderRender|ArachneState"
   ```
   Each suite must pass post-port. `PresetRegressionTests` will fail until
   the golden hashes are regenerated; expect that step to be the iterative
   loop.

3. **Visual harness** (load-bearing for V.7.7B):
   ```
   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
       --filter "PresetVisualReview/renderStagedPresetPerStage" 2>&1 | tee /tmp/v77b_staged.log
   ```
   Inspect `/tmp/phosphene_visual/<ISO8601>/Arachne_*_world.png` and
   `Arachne_*_composite.png`. Expected:
   - `world.png` is dark-close-up forest with branches + atmosphere +
     light shaft + motes (matches `drawWorld()` output for the given
     fixture).
   - `composite.png` is the WORLD with web strands + drops overlaid
     (chord-segment spiral visible — no concentric rings).
   - Neither should be the V.7.7A placeholder (vertical gradient +
     three trunks, or 12-spoke + concentric-ring overlay).

4. **Contact-sheet harness**:
   ```
   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
       --filter "PresetVisualReview/renderPresetVisualReview" 2>&1 | tee /tmp/v77b_contact.log
   ```
   `Arachne_contact_sheet.png` should show the steady-mid render above
   refs `01` / `04` / `05` / `08`. The rendered output is now the
   V.7.5 v5 baseline (drops as visual hero, warm rim, ambient fill, etc)
   — *not* a cert match, but a known intermediate state. Confirm with
   one-line written verdict in commit message: "V.7.5 v5 baseline
   reproduced on staged scaffold; V.7.7C scope remains".

5. **Full engine suite**: `swift test --package-path PhospheneEngine` —
   must remain green. Pre-existing flakes documented elsewhere remain
   exempt.

6. **App suite**: `xcodebuild -scheme PhospheneApp -destination
   'platform=macOS' test 2>&1 | tail -5` — must end clean.

7. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml
   --quiet PhospheneEngine/Sources/Renderer/RenderPipeline+Staged.swift
   PhospheneEngine/Sources/Presets/Shaders/Arachne.metal
   PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift
   PhospheneEngine/Tests/PhospheneEngineTests/Renderer/StagedPresetBufferBindingTests.swift`
   — zero violations on touched files. The Arachne.metal file-length
   gate is exempt per `SHADER_CRAFT.md §11.1`; if SwiftLint complains
   about a Swift file's length, surface to Matt before truncating.

8. **Manual smoke (optional but recommended)**: launch the app, force
   Arachne via developer keybinding, observe live render. Confirm:
   - Atmosphere renders dark with branches visible.
   - Web strands render with chord-segment angularity (look for the
     bends at spoke crossings — V.7.8's signature).
   - No 12-spoke + concentric-ring placeholder visible.
   - Spider eventually fires under sustained sub-bass.

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** §Increment V.7.7B: flip status to ✅
   with the date. Mark each of the four sub-items checked. Confirm the
   forward chain (V.7.7C → V.7.7D → V.7.10) still reads correctly in
   the carry-forward bullet list.

2. **`docs/DECISIONS.md`** — append `D-<next>` documenting:
   - The decision to bind `directPresetFragmentBuffer` /
     `directPresetFragmentBuffer2` at slots 6/7 in the staged dispatch
     (mirroring the legacy direct/mv_warp paths).
   - The decision to reuse `drawWorld()` and `arachneEvalWeb()` as free
     functions across legacy + staged paths rather than fork them.
   - The decision to delete the legacy `arachne_fragment` after the
     port (vs. keeping it as further reference code).
   - Cite Failed Approach #49 ("constant-tuning on a renderer
     structurally missing compositing layers") as the architectural
     motivation that V.7.7A → V.7.7B is unwinding correctly.

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X] V.7.7B`
   entry summarising the engine binding fix + shader port. List file
   counts (LOC delta on Arachne.metal: ~962 → ~480 after legacy
   removal).

4. **`CLAUDE.md`**:
   - §Module Map: update `Arachne.metal` description from "V.7.7A
     staged-composition scaffold" to "V.7.7B: staged WORLD + COMPOSITE
     fragments using shared `drawWorld()` + `arachneEvalWeb()` free
     functions; refractive drops + biology-correct build pending in
     V.7.7C."
   - §GPU Contract Details / Buffer Binding Layout: add the
     buffer 6/7 = preset-specific reservation note.
   - §What NOT To Do: add "Do not call `drawWorld()` from
     `arachne_composite_fragment` — the WORLD stage owns it; COMPOSITE
     samples the texture."
   - §Recent landed work: append the V.7.7B entry.

5. **`docs/QUALITY/KNOWN_ISSUES.md`**:
   - No new entries unless V.7.7B itself surfaces a defect.

────────────────────────────────────────
COMMITS
────────────────────────────────────────

Two commits, in this order. Each must pass tests at the commit boundary.

1. `[V.7.7B] Engine: bind preset fragment buffers (6/7) in staged dispatch`
   - `RenderPipeline+Staged.swift` — `encodeStage` extension.
   - `PresetVisualReviewTests.swift` — `encodeStagePass` parallel fix.
   - `StagedPresetBufferBindingTests.swift` — new regression test.
   - No shader changes in this commit. Verifies engine fix in isolation
     (the Arachne staged fragments still render placeholders post-commit-1
     because their function bodies have not changed yet).

2. `[V.7.7B] Arachne: port drawWorld() + arachneEvalWeb() into staged fragments (D-<next>)`
   - `Arachne.metal` — staged fragment bodies replaced + legacy
     `arachne_fragment` deleted.
   - `PresetRegressionTests.swift` — golden hashes regenerated.
   - `ArachneSpiderRenderTests.swift` — golden hashes regenerated.
   - All docs from §Documentation Obligations.

Local commits to `main` only. Do NOT push without explicit "yes, push"
approval. The visual change is significant — Arachne goes from "obvious
placeholder" to "V.7.5 v5 baseline" — and pushing it remotely communicates
"the cert review is imminent" prematurely.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **The staged compile fails with `MVWarpPerFrame` unresolved.** Means
  the lift accidentally pulled in mv-warp helpers. Audit the legacy
  `arachne_fragment` before lifting; it should be free of mv-warp
  types per the V.7.7A retirement note. If a helper *does* reference
  `MVWarpPerFrame`, the ony correct response is to inline the
  helper's logic (without the mv-warp types) into the staged fragment;
  do not touch `PresetLoader.shaderPreamble` to add `mvWarpPreamble`
  to staged compiles.

- **Buffer 6/7 are silently zero in the staged fragments.** Means the
  engine binding fix (sub-item 1) didn't land or didn't propagate.
  Inspect with a diagnostic `return float4(webs[0].row4.xyz, 1.0)`
  in the WORLD fragment — should produce a vibrant solid color from
  the mood vector. If the result is black, the buffer is unbound or
  has the wrong storage mode. STOP and verify
  `directPresetFragmentBuffer` is set during preset switch by the
  engine path that loads Arachne — V.7.7A may have stopped calling
  `setDirectPresetFragmentBuffer()` for staged presets.

- **Golden hashes don't stabilize across runs.** Indicates the staged
  fragment is reading uninitialized memory somewhere. Check that the
  `ArachneState.webBuffer` is fully populated to all 32 web slots
  every frame by `ArachneState._tick()`. The legacy path tolerated
  partial writes because the fragment iterated only over
  `numActiveWebs`; the staged port should preserve that invariant.

- **The chord-segment spiral renders as concentric rings again.**
  Means the lift accidentally took the V.7.7A placeholder logic
  instead of the V.7.8 `arachneEvalWeb()`. The signature distinguisher
  is "angular bends at spoke crossings" — if you see smooth
  concentric arcs, you regressed Failed Approach #34. STOP and
  re-port from the legacy fragment.

- **Deleting `arachne_fragment` breaks something subtle.** If a test
  references the legacy fragment by name (e.g. a pipeline-state
  cache test), the test will fail at compile time. Either update
  the test to point at `arachne_composite_fragment`, or — if the
  test was a cert / regression that no longer applies — delete it
  with a one-line note in the commit message.

- **STOP and report instead of forging ahead** if:
  - The staged fragments need more than the existing
    `drawWorld` / `arachneEvalWeb` free functions to reach V.7.5
    parity. That would mean V.7.7-redo + V.7.8 added inline shader
    code that wasn't refactored into free functions — surface
    before re-implementing it inline in the staged fragment.
  - The engine staged dispatch needs a structural change beyond
    the buffer 6/7 bindings (e.g. the fragment buffer signature
    on `MTLRenderPipelineDescriptor` rejects the new `device const`
    qualifier; or the `setStagedRuntime()` API needs a new
    per-preset hook). That's V.7.7B+ scope expansion — surface
    to Matt before opening that door.
  - The `ArachneState` tick rate (currently driven by the legacy
    fragment path) is somehow tied to the legacy dispatch and goes
    silent on the staged path. State updates should be entirely
    independent of which fragment is dispatched.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md` §3A staged renderer
  architecture, §4 WORLD pillar, §5.6 chord-segment capture spiral.
- Engine plan entry: `docs/ENGINEERING_PLAN.md` §Increment V.7.7B
  (filed by the doc-correction prompt before this prompt runs).
- Architectural pivot record: `docs/DECISIONS.md` D-072 (compositing-anchored
  diagnosis), V.ENGINE.1 + V.7.7A staged scaffold landing entries.
- Shader handbook: `docs/SHADER_CRAFT.md` §10.1 (compositing-anchored
  rewrite), §11.1 (file-length exemption for `.metal`).
- Failed Approaches: `CLAUDE.md` #34 (`abs(fract−0.5)` SDF inversion),
  #44 (Metal `half` reserved type silent compile failure), #49
  (constant-tuning on missing compositing layers — the V.7.5 trap
  V.7.7A unwound).
- Engine: `RenderPipeline+Staged.swift` (encode + binding extension
  point), `RenderPipeline.swift` (`directPresetFragmentBuffer` +
  `directPresetFragmentBuffer2` field locations), `RenderPipeline+PresetSwitching.swift`
  (`setDirectPresetFragmentBuffer*` setters that V.7.7B reuses).
- Harness: `PresetVisualReviewTests.swift` `encodeStagePass` (parallel
  fix needed). Closed BUG-002 reference at
  [PresetVisualReviewTests.swift:417-422](PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift:417).
- Source material for the port:
  - `Arachne.metal` `drawWorld` at line 142 (V.7.7-redo, full WORLD).
  - `Arachne.metal` `arachneEvalWeb` at line 265 (V.7.8 chord-segment).
  - `Arachne.metal` `arachne_fragment` at line 617 (legacy monolithic
    composition; delete after port).
- Golden hashes update path: `Renderer/PresetRegressionTests.swift`,
  `Presets/ArachneSpiderRenderTests.swift`, and the
  `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --filter test_printGoldenHashes`
  procedure (see CLAUDE.md §Recent landed work, V.5.3 entry).
- Reference implementations:
  - V.7.7A migration commit `ccefe065` — read this before starting
    sub-item 4 to understand exactly what the placeholder fragments
    replaced.
  - V.7.7-redo commit `fa5dacdf` — message documents the exact
    `drawWorld()` design intent.
  - V.7.8 commit `3536a023` — message documents the chord-segment SDF
    architecture.
- Forward chain (do NOT do here):
  - V.7.7C — refractive droplets (Snell's law, sample `worldTex`),
    biology-correct build state machine (frame → radials → spiral),
    anchor logic.
  - V.7.7D — spider pillar deepening (anatomy, material, gait),
    whole-scene vibration.
  - V.7.10 — Matt M7 cert review.
- CLAUDE.md sections to read: §Increment Completion Protocol, §Defect
  Handling Protocol, §GPU Contract Details, §Visual Quality Floor,
  §Failed Approaches, §What NOT To Do.
