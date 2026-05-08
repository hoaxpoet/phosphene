Correct the V.7.7 / V.7.8 / V.7.9 status drift in CLAUDE.md and
docs/ENGINEERING_PLAN.md. No production code changes.

────────────────────────────────────────
WHY THIS PROMPT EXISTS
────────────────────────────────────────

CLAUDE.md and ENGINEERING_PLAN.md currently state that V.7.7 (WORLD pillar),
V.7.8 (chord-segment outside-in capture spiral), and V.7.9 (biology-correct
build order) all shipped on 2026-05-05. The git history confirms commits
exist with those tags. **However**, the work in those commits was inside
the monolithic `arachne_fragment` and was retired hours later by
`ccefe065 [V.7.7A]`, which migrated Arachne to the V.ENGINE.1
staged-composition scaffold with placeholder fragments. The current
dispatched render path (`arachne_world_fragment` + `arachne_composite_fragment`,
[Arachne.metal:883-962](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal:883))
is a vertical gradient with three trunk lines plus a 12-spoke + concentric-ring
overlay — not the WORLD pillar, not the chord-segment spiral, not the
biology-correct build, no spider, no refractive drops.

The V.7.7-redo and V.7.8 shader code remains in
[Arachne.metal](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal) as
dead reference code (the legacy `arachne_fragment` at line 617, plus the
free-function helpers `drawWorld` at line 142 and `arachneEvalWeb` at
line 265). Those are reusable as the source material for V.7.7B's port.

This prompt updates the documentation to reflect what actually happened. It
does NOT touch shader code or run the harness.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. `git status` clean except `prompts/*.md` and `default.profraw`.
2. Verify the chronology with:
   `git log --pretty='%h %ai %s' --follow PhospheneEngine/Sources/Presets/Shaders/Arachne.metal | head -8`
   — expect `ccefe065 [V.7.7A]` as the most recent change to Arachne.metal,
   landing AFTER `3536a023 [V.7.8]` and `fa5dacdf [V.7.7 redo]` on the same
   day.
3. Verify the placeholder state with:
   `grep -A2 '"description"' PhospheneEngine/Sources/Presets/Shaders/Arachne.json`
   — expect "primitive forest backdrop ... placeholder hub-and-spokes web ...
   arrive in V.7.7B+".

────────────────────────────────────────
SCOPE
────────────────────────────────────────

Three docs touched. No code, no tests, no shader changes, no new
DECISIONS.md entry (this is a status correction, not a new decision).

──── 1. CLAUDE.md — `## Current Status` block + `Recent landed work` ────

The status block currently says:

> V.7.7 ✅ 2026-05-05 (WORLD pillar: six-layer inline forest + background
> dewy webs with Snell's-law drop refraction; ...);
> V.7.8 ✅ 2026-05-05 (chord-segment outside-in capture spiral replacing
> degenerate Archimedean SDF);
> V.7.9 ✅ 2026-05-05 (biology-correct build order: frame→radial→spiral
> §5.2; WebStage.anchorPulse→frame; timing 6/42/60 beats; hub fbm4 noise
> knot §5.4; Marschner BRDF removed §5.10; golden hashes regenerated)

Replace with:

> **V.7.7 / V.7.8 / V.7.9 status correction (2026-05-07).** Three commits
> tagged `[V.7.7 redo]` (`fa5dacdf`), `[V.7.8]` (`3536a023`), and
> `[V.7.9 ✅]` (`97f42220`) landed on 2026-05-05. The first two added
> WORLD-pillar geometry and the chord-segment capture spiral *inside the
> monolithic* `arachne_fragment`; the third was a CLAUDE.md status update
> only (4 lines, no code). Three hours later, `ccefe065 [V.7.7A]`
> migrated Arachne onto the V.ENGINE.1 staged-composition scaffold,
> retiring the monolith and replacing the dispatched path with placeholder
> stubs (`arachne_world_fragment` = vertical gradient + three trunk
> silhouettes; `arachne_composite_fragment` = 12-spoke + concentric-ring
> overlay). The V.7.7-redo and V.7.8 work survives in
> [Arachne.metal](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal)
> as dead reference code (legacy `arachne_fragment` at line 617,
> free-function `drawWorld` at line 142, `arachneEvalWeb` at line 265).
> The currently-rendered Arachne is the V.7.7A scaffold-with-placeholders.
> V.7.7B is the open increment that ports the dead WORLD + chord-spiral
> code into the staged path and adds the engine plumbing for
> per-preset fragment buffers (web buffer at index 6, spider buffer at
> index 7) under staged dispatch. V.7.7C / V.7.7D / V.7.10 follow.

Also update the carry-forward bullet list (currently "Increment V.7.10 —
Arachne M7 contact sheet + cert. Pending V.7.7B+.") to read:

> **Arachne stream open.** Currently dispatched: V.7.7A scaffold + placeholders.
> Open increments in order:
> - V.7.7B — Port V.7.7-redo WORLD and V.7.8 chord-spiral into the
>   staged fragments; thread preset-specific fragment buffers (web
>   index 6, spider index 7) through `RenderPipeline+Staged` and
>   `PresetVisualReviewTests`.
> - V.7.7C — Refractive droplets (Snell's law sampling of `worldTex`),
>   biology-correct build state machine, anchor logic.
> - V.7.7D — Spider pillar deepening + whole-scene vibration.
> - V.7.10 — Matt M7 contact-sheet review + cert. Gated on V.7.7D.

In the "Recent landed work" bullet list at the top of the file, edit the
existing V.7.7 / V.7.8 / V.7.9 entries (currently each marked ✅) to
match the corrected story:
- V.7.7 → "see V.7.7A; full WORLD pillar deferred to V.7.7B"
- V.7.8 → "see V.7.7A; chord-spiral preserved as dead reference code,
  port deferred to V.7.7B"
- V.7.9 → "CLAUDE.md status only; no shader changes"

Do NOT delete the existing ✅ entries — Matt's audit trail wants the
inflight history preserved. Append the correction inline, do not rewrite
history.

──── 2. ENGINEERING_PLAN.md — `### Increment V.7.7` / `V.7.8` / `V.7.9` ────

Each of these entries currently reads as ✅ on the staged path.
Add a `**Status correction (2026-05-07):**` block at the top of each that
mirrors the CLAUDE.md correction:

For V.7.7:

> **Status correction (2026-05-07):** The `[V.7.7 redo]` commit
> (`fa5dacdf`, 2026-05-05 10:54) added the six-layer inline `drawWorld()`
> and frame threads to the *monolithic* `arachne_fragment`. Three hours
> later, `[V.7.7A]` (`ccefe065`, 2026-05-05 14:13) retired that fragment
> and shipped placeholder staged stubs. The V.7.7 work is therefore
> preserved as dead reference code in
> [Arachne.metal](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal),
> not in the dispatched path. Promotion into the staged path is V.7.7B.

For V.7.8:

> **Status correction (2026-05-07):** The `[V.7.8]` commit (`3536a023`,
> 2026-05-05 11:06) added the chord-segment capture spiral to
> `arachneEvalWeb()` inside the monolithic fragment. Same retirement story
> as V.7.7 — code survives as dead reference at
> [Arachne.metal:265](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal:265),
> port to staged dispatch is V.7.7B. The chord-segment SDF replacement
> for the degenerate Archimedean curve (Failed Approach #34) is a
> permanent reference for V.7.7B; do not regress to circular rings.

For V.7.9:

> **Status correction (2026-05-07):** The `[V.7.9 ✅]` commit (`97f42220`)
> was a CLAUDE.md status update only — 4 line changes, no shader code.
> The biology-correct frame → radial → spiral build order remains
> unimplemented in the dispatched path. Scheduled for V.7.7C.

Also: append a new numbered §Increment V.7.7B entry between V.7.7A and
the carry-forward note. The full V.7.7B specification will live in
`prompts/V.7.7B-prompt.md`; the engineering-plan entry is a one-paragraph
stub:

> **Scope:** Promote V.7.7-redo's `drawWorld()` and V.7.8's chord-segment
> `arachneEvalWeb()` from dead reference code into the dispatched
> `arachne_world_fragment` and `arachne_composite_fragment` staged
> stages. Extend `RenderPipeline+Staged.encodeStage()` and
> `PresetVisualReviewTests.encodeStagePass()` so staged stages can read
> the per-preset fragment buffers at index 6 (`ArachneWebGPU`) and
> index 7 (`ArachneSpiderGPU`) — the legacy path used these via
> `directPresetFragmentBuffer` / `directPresetFragmentBuffer2`; the
> staged path currently does not bind them. Result is parity with the
> pre-V.7.7A monolithic shader output, on the staged-composition
> scaffold. Refractive droplets, biology-correct build state machine,
> spider deepening, and whole-scene vibration are V.7.7C / V.7.7D —
> not in scope for V.7.7B.
>
> **Done when:** WORLD-only and COMPOSITE captures via the harness show
> parity with the pre-V.7.7A V.7.5 baseline (allowing for the chord-spiral
> +V.7.7-redo WORLD additions). All test suites pass. 0 SwiftLint
> violations. Golden hashes regenerated.
>
> **Estimated sessions:** 2.

──── 3. docs/QUALITY/KNOWN_ISSUES.md ────

If a `BUG-002` entry references the staged-preset PNG export breakage,
verify it is in the resolved list (QR.3 closed it via
`PresetLoader.bundledShadersURL`, see
[PresetVisualReviewTests.swift:417-422](PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift:417)).
If it is in the open list, move it to resolved. If it is not present at
all, no action needed.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT modify any shader files. The corrections are documentation only.
- Do NOT modify `Arachne.json`. Its current `description` field is
  accurate ("V.7.7A staged-composition scaffold ... arrive in V.7.7B+");
  do not change it.
- Do NOT delete the V.7.7-redo or V.7.8 dead reference code from
  `Arachne.metal`. V.7.7B re-uses it. The cleanup of the legacy
  `arachne_fragment` is V.7.7B's exit task.
- Do NOT add a new DECISIONS.md entry. This is a status correction, not
  a new architectural decision. The V.7.7B prompt may add a new D-XXX
  if it makes one.
- Do NOT run `RENDER_VISUAL=1` or any test suite. This prompt is
  documentation-only; verification is `git diff` review.
- Do NOT update CLAUDE.md "Failed Approaches" — the V.7.7A scaffold +
  placeholder pattern was deliberate, not a failed approach. (V.7.10's
  Failed Approach #48 stands on its own merits, separate concern.)
- Do NOT touch RELEASE_NOTES_DEV.md unless an existing entry there
  duplicates the corrected story; if so, append a `2026-05-07
  correction` paragraph to that entry rather than rewriting.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

1. `git diff CLAUDE.md docs/ENGINEERING_PLAN.md` — review carefully.
   Each correction inserted should preserve the existing ✅ entries
   as audit trail and append the correction below them. No deletions.

2. `grep -n "V.7.7B" CLAUDE.md docs/ENGINEERING_PLAN.md` — expect
   matches in both. The carry-forward bullet in CLAUDE.md and the
   ENGINEERING_PLAN.md entry both name V.7.7B.

3. `grep -n "Status correction (2026-05-07)" docs/ENGINEERING_PLAN.md`
   — expect exactly three matches (V.7.7, V.7.8, V.7.9 entries).

4. Build sanity: `xcodebuild -scheme PhospheneApp -destination
   'platform=macOS' build 2>&1 | tail -3` — must end
   `** BUILD SUCCEEDED **`. Doc edits cannot break the build, but
   verifying serves as a "did you accidentally edit a Swift file"
   trip-wire.

5. `swift test --package-path PhospheneEngine 2>&1 | tail -10` — full
   suite green. Same trip-wire purpose.

────────────────────────────────────────
COMMIT
────────────────────────────────────────

One commit:

`[V.7.7B prep] Docs: correct V.7.7/V.7.8/V.7.9 status drift; file V.7.7B in plan`

Local commit to `main` only. Do NOT push.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- Git evidence:
  `git log --pretty='%h %ai %s' --follow PhospheneEngine/Sources/Presets/Shaders/Arachne.metal | head -8`
- Current rendered state of Arachne:
  - `Arachne.json` `"description"` field (placeholder declaration).
  - [Arachne.metal:883-962](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal:883)
    (placeholder fragments).
- Dead reference code:
  - [Arachne.metal:142](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal:142)
    (`drawWorld`).
  - [Arachne.metal:265](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal:265)
    (`arachneEvalWeb`).
  - [Arachne.metal:617](PhospheneEngine/Sources/Presets/Shaders/Arachne.metal:617)
    (legacy `arachne_fragment`).
- Engine staged dispatch (binds 0/1/2/3/5 only — buffer 6/7 gap):
  [RenderPipeline+Staged.swift:194-204](PhospheneEngine/Sources/Renderer/RenderPipeline+Staged.swift:194).
- Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md`.
- Forward plan source: `prompts/V.7.7B-prompt.md` (separate prompt).
