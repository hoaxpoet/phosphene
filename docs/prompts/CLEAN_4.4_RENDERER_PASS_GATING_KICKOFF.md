# CLEAN.4.4 — Renderer over-allocation: gate unsampled feedback/particle-warp passes + fix the PSO cache key

CONTEXT. Phase 4 (Performance) of the CLEAN backlog, Stretch tier. The June-committed
scope (Phases 0/1/2/5) is **done**; G1/G9 validated; this is a clean, self-contained
renderer increment. It was chosen as a **parallel-safe** pick: it is renderer-only and
**disjoint from the Phase-3 audio/resource work** that may be running in another session.

PARALLEL-SESSION COORDINATION. Other sessions may be live (Phase 3 = audio/DSP; possibly
a Phase-4 audio item). This increment touches **renderer files only** — no `StemAnalyzer`/
`StemCache`/MIR — so no code-merge thrash (CODE_AUDIT Part E note 4). The shared surfaces
are the **docs** (ENGINEERING_PLAN, RELEASE_NOTES [union-merge], CODE_AUDIT, KNOWN_ISSUES)
and possibly **PresetRegression golden hashes** (Phase 3's CLEAN.3.4 Arachne is `[M7]` and
may regen an Arachne golden). Rule: `git fetch` before pushing, **first-to-origin wins**,
**rebase onto origin/main, never merge a diverged main**. Push requires Matt's explicit
"yes, push."

SOURCE OF TRUTH. Audit finding **T7** (`docs/diagnostics/CODE_AUDIT_2026-06-13.md`
§Performance) + the **CLEAN.4.4** row in Part C. Read both first. The CLEAN.4.4 done-when is:
"no wasted alloc/pass; cache key correct."

═══════════════════════════════════════════════════════════════════════════════
SCOPE — exactly two sub-items. Do NOT expand.
═══════════════════════════════════════════════════════════════════════════════

T7 bundles SIX renderer findings across THREE increments. **This increment is only the two
below.** The others are explicitly out of scope:
  - `PostProcessChain.sceneTexture` aliases ray-march `litTexture` + resize-handler
    early-return stale-size → **CLEAN.4.3** (`[M7]`). NOT here.
  - ray-march aspect guard `/height` NaN-at-0 → a separate NaN guard (track with **CLEAN.4.5**'s
    NaN/Inf sweep, or 4.3 — Matt's call); NOT here.
  - DynamicTextOverlay in-flight-frame race → unscheduled; file it if you confirm it, don't fix it here.
If fixing 4.4 seems to require touching those, STOP and surface the scope (CLAUDE.md
"stop and report instead of forging ahead").

─────────────────────────────────────────────────────────────────────────────
SUB-ITEM A — PSO cache keyed by name only (correctness). The clean, bounded half.
─────────────────────────────────────────────────────────────────────────────
`ShaderLibrary.renderPipelineState(named:vertexFunction:fragmentFunction:pixelFormat:device:supportICB:)`
caches in `pipelineStates[name]` (`ShaderLibrary.swift:97` lookup, `:119` store) — keyed by
the `name` **String only**. But the compiled descriptor varies by `pixelFormat`
(`colorAttachments[0].pixelFormat`) AND `supportICB` (`supportIndirectCommandBuffers`). So
two calls with the **same `name` but a different `pixelFormat`/`supportICB`** return the
first-cached PSO — the wrong pixel format / ICB capability → a latent render-state hazard
(wrong-format attach, or an ICB-incompatible PSO used as inherited state in
`executeCommandsInBuffer`).

FIX: make the cache key the full identity — `(name, pixelFormat.rawValue, supportICB)`
(a struct/tuple `Hashable` key, or a composed string). Change WHERE it keys, not WHAT it
compiles. First **audit the call sites**: grep every `renderPipelineState(named:` caller and
record whether any currently passes the *same `name`* with a *different `pixelFormat` or
`supportICB`* — if yes it's a **live** bug, if no it's latent-hardening. Either way key
correctly; note which it is in KNOWN_ISSUES.

VERIFY: a `ShaderLibraryTests` unit test — same `name`, two different `pixelFormat`s ⇒ two
distinct PSOs each carrying the requested format (red on the name-only key, green after). +
same `name`, `supportICB` false vs true ⇒ distinct.

─────────────────────────────────────────────────────────────────────────────
SUB-ITEM B — feedback ping-pong + particle-warp pass allocated/run unconditionally (perf).
─────────────────────────────────────────────────────────────────────────────
The legacy feedback ping-pong textures (`RenderPipeline.feedbackTextures`,
`RenderPipeline.swift:248`; allocated by `ensureFeedbackTexturesAllocated(size:)` at
`RenderPipeline+Draw.swift:47`, called `:110`) are ~32 MB @ 4K, and the particle-mode warp
pass (`runWarpPass` / `drawParticleMode`, `RenderPipeline+FeedbackDraw.swift:21/29/51/78`)
are allocated/executed **even for presets that never sample them**. (Note: `RenderPipeline
.swift:294` already gates some warp *state* "when the active preset…" — so confirm exactly
which alloc/exec paths are still unconditional; don't assume.)

FIRST DIAGNOSE, THEN FIX (don't gate blind):
  1. Determine the predicate: which presets actually consume the feedback ping-pong / the
     particle-warp pass? (preset metadata `passes`, the active-preset mode, or the existing
     `:294` gate — find the real signal). This is the load-bearing decision; get it right.
  2. Gate BOTH the allocation (`ensureFeedbackTexturesAllocated`) AND the execution
     (`runWarpPass`/`drawParticleMode`) behind that predicate, so a non-sampling preset
     allocates and runs neither. Free/skip cleanly on preset switch; reallocate on switch-in.
  3. Watch lifecycle: presets switch mid-session, and `drawableSizeWillChange` resize must
     not resurrect a gated-off texture (and vice-versa — switching INTO a feedback preset
     after a resize must allocate at the current size). The lazy-alloc path at `:110` exists
     precisely for the "resize didn't fire" case — keep that correctness.

═══════════════════════════════════════════════════════════════════════════════
VERIFICATION — the golden hash is load-bearing; this is why 4.4 is NOT `[M7]`.
═══════════════════════════════════════════════════════════════════════════════

Domain artifact (CLAUDE.md, render pipeline): **`PresetRegressionTests` golden hash before
and after.** The whole increment is designed to be **output-preserving**:
  - **Every certified preset's golden hash MUST be byte-identical** after the change. A
    preset that samples feedback/warp must still get it; the PSO-key fix must not alter any
    compiled pipeline's behaviour.
  - **If a golden hash changes, STOP.** Do NOT regenerate the golden to make it pass — a
    changed hash means the gate removed a pass a preset actually needs (or the PSO key fix
    changed a render state). That is a bug in the gate, not a golden that needs updating.
    Re-diagnose the predicate. (Regenerating a golden to silence a gating regression is the
    failure mode this gate exists to catch.)
  - **Perf/alloc evidence:** add an assertion or a logged measurement that a non-feedback
    preset (pick one with no warp/feedback in its `passes`) allocates **zero** feedback
    textures and runs **zero** warp/particle passes — the "no wasted alloc/pass" done-when.
    A Metal GPU trace is only needed if you claim a frame-budget delta; the alloc-count
    assertion is the primary gate.
  - Run the FULL engine + app suites (regression gate) + `swiftlint --strict`.

No live/Spotify session is required (this is GPU-render, validated by golden hashes in
`swift test`/`xcodebuild test`). No M7 is expected — but if you cannot make it
output-preserving (a golden genuinely must change), that flips it into `[M7]`: STOP and
bring it to Matt rather than regenerating goldens yourself.

═══════════════════════════════════════════════════════════════════════════════
PROCESS (CLAUDE.md Increment Completion Protocol)
═══════════════════════════════════════════════════════════════════════════════

- Worktree? run `Scripts/bootstrap_fixtures.sh` first (gitignored fixtures don't reach
  worktrees). Closeout = the `Scripts/closeout_evidence.sh` block, pasted verbatim, commit
  hash matching the closeout's commit.
- Prefer small commits: `[CLEAN.4.4] <component>: <desc>` (e.g. `[CLEAN.4.4] ShaderLibrary:
  key PSO cache by (name,pixelFormat,supportICB)`; `[CLEAN.4.4] RenderPipeline: gate
  feedback/warp alloc+exec to sampling presets`).
- Docs to update: **`docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`** (mandatory — this IS a
  renderer/shader-infra capability change; cite the rows), `docs/ENGINEERING_PLAN.md`
  (CLEAN.4.4 row → done/partial), `docs/RELEASE_NOTES_DEV.md` (prepend a
  `[dev-YYYY-MM-DD-HHMMSS]` entry — `date -u +%Y-%m-%d-%H%M%S`), the CLEAN.4.4 row in
  `docs/diagnostics/CODE_AUDIT_2026-06-13.md`, and `docs/QUALITY/KNOWN_ISSUES.md` (the T7/
  AUDIT-2026-06-13 backlog index — record the PSO-key bug live-vs-latent finding + the
  gating). swiftlint: `.swift` `file_length` error at 400 (relaxed for `.metal`).
- Push requires Matt's explicit "yes, push." Local `main` commits stay local until then.
  When integrating: `git fetch` → rebase onto origin/main → re-run the closeout on the
  rebased tip (the combined tree was never tested) → push. First-to-origin wins.
- Manual validation: not required for the automated golden/alloc gates. (Renderer output is
  golden-hash-verified; only flag for Matt's eyes if a golden genuinely changes — see above.)

FIRST ACTIONS:
1. `git fetch origin`; read CODE_AUDIT T7 + the CLEAN.4.4 Part-C row; read this prompt's two
   sub-items.
2. Sub-item A: read `ShaderLibrary.swift:85-122`; grep all `renderPipelineState(named:`
   callers; classify live-vs-latent; fix the key; add the unit test.
3. Sub-item B: read `RenderPipeline+FeedbackDraw.swift`, `RenderPipeline+Draw.swift:43-115`,
   and `RenderPipeline.swift:248-300` (the `:294` warp-state gate); nail the
   sampling-predicate; gate alloc+exec; handle switch/resize lifecycle.
4. Run `PresetRegressionTests` BEFORE any change to capture the baseline golden hashes;
   keep them; they must match after.
5. Closeout; hand to Matt. Do NOT regenerate any golden to make a gating change pass.
