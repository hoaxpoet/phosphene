Execute Increment DASH.3 — Beat & BPM card.

Authoritative spec: docs/ENGINEERING_PLAN.md §Phase DASH §Increment DASH.3.
Authoritative design: .impeccable.md §Aesthetic Direction (Color, Typography),
§State-Specific Design Notes, §Anti-Patterns. Read both before writing
any code.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. DASH.2 + DASH.2.1 must have landed. Verify with
   `git log --oneline | grep '\[DASH\.2'` — expect at least six commits
   ending with `[DASH.2.1] docs: D-082 amendment, …` (cdc4a145).

2. Confirm DASH.2.1's API surface is in place:
   `grep -E "case singleValue|case bar|labelToValueGap" \
     PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
   — expect 3+ matches and NO `case pair` (it was removed in DASH.2.1).
   If `pair` is still present, DASH.2.1 has not landed; stop.

3. Decision-ID numbering: D-082 covers the dashboard card-layout engine
   *and* the DASH.2.1 amendment. The next available number is **D-083**.
   Verify with `grep '^## D-0' docs/DECISIONS.md | tail -3`.

4. `BeatSyncSnapshot` lives at
   `PhospheneEngine/Sources/Shared/BeatSyncSnapshot.swift` with the
   `sessionMode: Int`, `lockState: Int`, `gridBPM: Float`,
   `barPhase01: Float`, `beatsPerBar: Int`, `beatInBar: Int` fields you
   will read. The `.zero` sentinel is the no-grid / reactive-mode
   placeholder. No changes to BeatSyncSnapshot are in scope for DASH.3.

5. `default.profraw` may be present in the repo root. Ignore.

────────────────────────────────────────
GOAL
────────────────────────────────────────

The first **live** dashboard card. DASH.2 produced primitive cards
without data binding; DASH.3 connects the BEAT card to the live
beat-sync state. After this increment, a `BeatCardBuilder` consumes a
`BeatSyncSnapshot` and produces a `DashboardCardLayout` rendered by
`DashboardCardRenderer`.

This increment is **data binding + one new row variant**. It does NOT
wire the card into PlaybackView (DASH.6). It does NOT compose multiple
cards (DASH.6). It produces:

  1. A new row variant `.progressBar` for unsigned 0–1 progress
     visualisations (beat / bar phase) — the existing `.bar` is
     signed-from-centre and inappropriate for ramps.
  2. A `BeatCardBuilder` struct that maps `BeatSyncSnapshot` →
     `DashboardCardLayout` (title `BEAT`, rows MODE / BPM / BAR / BEAT).
  3. Lock-state colour mapping: REACTIVE → muted, LOCKING → amber,
     LOCKED → green.
  4. Graceful no-grid rendering: BPM `—`, BAR `— / 4`, BEAT bar empty,
     MODE `REACTIVE` muted.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

1. EDIT — `DashboardCardLayout.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`

   Add a third Row variant:

   ```
   /// Stacked: UPPERCASE 11 pt label on top, then a *progress* bar with
   /// right-aligned value text on the same line below. Bar fills from
   /// left to `value × innerBarWidth`. Value is clamped to [0, 1].
   /// Use for unsigned ramps (beat phase, bar phase, frame budget).
   /// Distinct from `.bar` which is a signed slice from centre.
   case progressBar(label: String, value: Float, valueText: String, fillColor: NSColor)
   ```

   Row height: same as `.bar` — `static let progressBarHeight: CGFloat`
   = `barHeight` (32 pt). Don't introduce a new height constant; reuse
   `barHeight` since the visual mass is identical (label + 4 pt gap +
   17 pt bar+value band). The `height` switch gains a `.progressBar`
   case returning `Row.barHeight`.

2. EDIT — `DashboardCardRenderer.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift`

   Extend `drawRow(...)` switch with a `.progressBar` case dispatching to
   a new `drawProgressBarRow(...)` helper. The helper layout matches
   `drawBarRow` exactly (label on top, bar + value text below, same
   reserved 56 pt right column for value text, same 8 pt gap, same bar
   height 6 pt, same corner radius 1 pt) — only the *fill geometry*
   changes:

   ```
   // Background: full bar, Color.border tint (same as .bar).
   // Foreground: from barLeft to barLeft + clamp(value, 0, 1) × barWidth.
   ```

   Reuse `drawBarChrome` for the background; add a `drawProgressBarFill`
   helper alongside `drawBarFill` to keep `function_body_length` ≤ 60.
   Do NOT generalise `drawBarFill` to handle both modes — separate
   helpers read more clearly than a Boolean parameter.

3. NEW FILE — `BeatCardBuilder.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift`

   ```
   /// Maps a `BeatSyncSnapshot` to a `DashboardCardLayout` for the BEAT
   /// card. Pure function — no Metal, no allocations beyond the layout
   /// itself. Safe to call every frame.
   public struct BeatCardBuilder: Sendable {
       public init() {}
       public func build(
           from snapshot: BeatSyncSnapshot,
           width: CGFloat = 280
       ) -> DashboardCardLayout
   }
   ```

   The builder produces a card titled `BEAT` with **four** rows in this
   order (matching the .impeccable Beat-panel feedback):

   - **MODE** (.singleValue): label `MODE`, value derived from
     `snapshot.sessionMode`:
       - 0 → `REACTIVE` in `Color.textMuted`
       - 1 → `UNLOCKED` in `Color.textMuted`
       - 2 → `LOCKING` in `Color.statusYellow`
       - 3 → `LOCKED` in `Color.statusGreen`
       - any other (defensive) → `REACTIVE` in `Color.textMuted`

   - **BPM** (.singleValue): label `BPM`, value:
       - `gridBPM <= 0` → `—` in `Color.textMuted`
       - else → integer rounded BPM string (e.g. `125`) in
         `Color.textHeading`. Use `String(format: "%.0f", gridBPM)`.

   - **BAR** (.progressBar): label `BAR`, value `barPhase01` (clamped),
     valueText `"\(beatInBar) / \(beatsPerBar)"`, fillColor
     `Color.purpleGlow`. When `gridBPM <= 0` (no grid), pass valueText
     `— / 4` and value 0 — purpleGlow is fine at zero fill (background
     dominates).

   - **BEAT** (.progressBar): label `BEAT`, value `derivedBeatPhase`
     (see below, clamped), valueText `"\(beatInBar)"` (a single digit
     when there is a grid; `—` when there isn't), fillColor
     `Color.coral`.

   `BeatSyncSnapshot` does NOT carry a `beatPhase01` field directly —
   it's derived in `MIRPipeline.buildFeatureVector` and lives on
   `FeatureVector`. For DASH.3 we only have access to `barPhase01`,
   `beatsPerBar`, and `beatInBar`. Derive an approximation:

   ```
   // beat_phase01 ≈ fract(barPhase01 × beatsPerBar)
   // (exact when beatInBar/beatsPerBar are integer-aligned; close
   //  enough for visual feedback).
   let derivedBeatPhase: Float =
       (snapshot.beatsPerBar > 0)
           ? snapshot.barPhase01 * Float(snapshot.beatsPerBar) - Float(snapshot.beatInBar - 1)
           : 0
   ```

   Document this approximation inline. The full `beatPhase01` plumb-
   through (adding `beatPhase01: Float` to `BeatSyncSnapshot`) is a
   separate increment — DASH.3 must NOT modify `BeatSyncSnapshot`.

4. NEW TEST FILE — `BeatCardBuilderTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/BeatCardBuilderTests.swift`

   Six `@Test` functions in `@Suite("BeatCardBuilder")`:

   a. **`build_zeroSnapshot_producesReactiveLayout`**: feed
      `BeatSyncSnapshot.zero`, assert `title == "BEAT"`, `rows.count == 4`.
      Inspect rows:
        - row[0] is `.singleValue(label:"MODE", value:"REACTIVE", valueColor: textMuted)`
        - row[1] is `.singleValue(label:"BPM", value:"—", valueColor: textMuted)`
        - row[2] is `.progressBar(label:"BAR", value:0, valueText:"— / 4", …)`
        - row[3] is `.progressBar(label:"BEAT", value:0, valueText:"—", …)`
      Use a small private switch helper to extract row payloads — switch
      pattern matching is verbose but unambiguous; do NOT add Equatable
      to Row (NSColor isn't Equatable in a useful way).

   b. **`build_lockingSnapshot_producesAmberMode`**: snapshot with
      `sessionMode=2, lockState=1, gridBPM=125, beatsPerBar=4,
      beatInBar=2, barPhase01=0.375`. Assert MODE value `LOCKING`,
      MODE valueColor `statusYellow`, BPM value `125`, BAR valueText
      `2 / 4`, BAR value within [0.37, 0.38].

   c. **`build_lockedSnapshot_producesGreenModeAndDerivedBeatPhase`**:
      snapshot with `sessionMode=3, gridBPM=140, beatsPerBar=4,
      beatInBar=3, barPhase01=0.625`. Assert MODE value `LOCKED`,
      MODE valueColor `statusGreen`, BPM value `140`, BAR value within
      [0.62, 0.63] valueText `3 / 4`, BEAT value within [0.49, 0.51]
      (derived: 0.625×4 − 2 = 0.5) valueText `3`.

   d. **`build_bpmFormat_roundsHalfUp`**: snapshots with `gridBPM=124.4`
      → "124", `gridBPM=124.5` → "125" (Swift `%.0f` rounds half-to-
      even on Apple platforms — accept either `124` or `125` for the
      .5 case to avoid platform-specific brittleness; the 124.4 case
      must round to 124).

   e. **`build_unlockedSnapshot_producesMutedModeWithGridBpm`**: snapshot
      with `sessionMode=1, lockState=0, gridBPM=120, beatsPerBar=4,
      beatInBar=1, barPhase01=0`. Assert MODE value `UNLOCKED` with
      `textMuted` colour, BPM value `120` with `textHeading`. Confirms
      grid-present-but-not-locked is distinct from no-grid.

   f. **`build_widthOverride_passesThrough`**: call
      `build(from: .zero, width: 320)`, assert resulting layout's
      `width == 320`. Default-arg test.

5. NEW TEST FILE — `DashboardCardRendererProgressBarTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardCardRendererProgressBarTests.swift`

   Three `@Test` functions in `@Suite("DashboardCardRenderer.ProgressBar")`:

   a. **`progressBar_value0_drawsNoForeground`**: render a card with one
      `.progressBar(label:"BEAT", value:0, valueText:"—",
      fillColor: .coral)` row. Sample at the bar's quarter, half, and
      three-quarters positions on the bar centre y. None should look
      coral (no `R > G && R > B` channel ordering with `R - max(G,B) >
      20`). Background-only.

   b. **`progressBar_value1_fillsFullBarWidth`**: same layout with
      `value: 1.0`. Sample at quarter, half, three-quarters. All three
      should look coral (`R > G && R > B`, `R - max(G,B) > 20`).

   c. **`progressBar_valueHalf_fillsLeftHalfOnly`**: same layout with
      `value: 0.5`. Sample at one-third (must be coral) and two-thirds
      (must NOT be coral). Use `maxChromaPixel` from
      `DashboardCardRendererTests` — copy it locally rather than
      hoisting to a shared helper file (file independence convention).

   Pixel-format reminder: `.bgra8Unorm`, `(b, g, r, a)` byte order.
   Reuse the `pixelAt`, `readPixels`, `makeLayerAndQueue`,
   `renderFrame`, `maxChromaPixel`, `barGeometry` helpers from
   `DashboardCardRendererTests` — copy them locally. Document the
   choice in a one-line file-header comment.

   Skip pattern: `withKnownIssue("No Metal device available") {}` —
   never silent skip.

6. ARTIFACT
   Add a `savePNGArtifact` call to `BeatCardBuilderTests` test (c)
   (`build_lockedSnapshot_…`). Render the builder's output via
   `DashboardCardRenderer` onto a 320×220 `DashboardTextLayer` with
   the deep-indigo backdrop helper from DASH.2.1. Write to
   `.build/dash1_artifacts/card_beat_locked.png`. This is the artifact
   Matt will eyeball during M7-style review of the live BEAT card.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT modify `BeatSyncSnapshot`. Adding `beatPhase01` to it is a
  separate increment with its own scope (and CSV-column ramifications
  via SessionRecorder).
- Do NOT wire `BeatCardBuilder` into `RenderPipeline`, `PlaybackView`,
  `DebugOverlayView`, or any encoder. DASH.6 owns wiring.
- Do NOT compose multiple cards into a dashboard layout. DASH.6 owns
  multi-card composition and screen positioning.
- Do NOT add a hover / focus / tap-target — the dashboard remains
  read-only telemetry.
- Do NOT animate the bar fills. The card repaints each frame from
  current state; transitions live above this layer.
- Do NOT introduce a `BeatCardConfiguration` or any settings hook for
  per-installation customisation. Tokens are static.
- Do NOT add a fifth row (drift, frame budget, anything else). The
  BEAT card is exactly MODE + BPM + BAR + BEAT. Frame budget is DASH.5.
- Do NOT generalise the renderer's bar dispatch by adding a Boolean
  `signed:` parameter. Two helpers (`drawBarFill` and
  `drawProgressBarFill`) read more clearly.
- Do NOT add Equatable to `Row` or its associated values. NSColor
  comparison is non-trivial (sRGB vs catalog vs named); tests use
  switch-pattern extraction.

────────────────────────────────────────
DESIGN GUARDRAILS (.impeccable.md)
────────────────────────────────────────

- **Color carries meaning.** Lock-state colours map exactly per .impeccable:
  `statusGreen` = LOCKED (precision/data signal arrived), `statusYellow`
  = LOCKING (acquiring), `textMuted` = REACTIVE/UNLOCKED (off-state,
  visually receded — the *absence* of signal). Coral on the BEAT bar
  is "energy/action — beat moments." Purple-glow on the BAR bar
  signals "session presence / depth" (D-082 amendment / .impeccable
  Color section).
- **No icons.** The card is typographic. Status letters and colour-
  coded values do all status work.
- **No animation, no motion.** `barPhase01` and `beatPhase01` are
  per-frame samples; visible motion arises from the host's repaint
  cadence, not from in-renderer interpolation.
- **No magic numbers in the builder.** All thresholds are token-
  derived (`Color.statusGreen`, `Color.textMuted`). The only literal
  the builder emits is the `"4"` fallback in the no-grid `BAR`
  valueText (`"— / 4"`), which mirrors the `BeatSyncSnapshot.zero`
  default of `beatsPerBar: 4`. If `beatsPerBar > 0` in the snapshot,
  the builder MUST use that value, not the literal 4.
- **Whitespace as signal.** Don't tighten the row spacing. The card
  already has the rhythm it needs from DASH.2.1.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters. Each step must pass before proceeding.

1. **Build (engine)**: `swift build --package-path PhospheneEngine`
   — must succeed with zero warnings on touched files.

2. **Build (app)**: `xcodebuild -scheme PhospheneApp -destination \
   'platform=macOS' build 2>&1 | tail -3` — must end
   `** BUILD SUCCEEDED **`.

3. **Test (focused)**: `swift test --package-path PhospheneEngine \
   --filter "BeatCardBuilder|DashboardCardRenderer|DashboardTextLayer|\
   DashboardTokens|DashboardFontLoader"` — all 27 tests pass
   (12 from DASH.1 + 6 from DASH.2.1 + 6 BeatCardBuilder + 3
   ProgressBar).

4. **Test (full)**: `swift test --package-path PhospheneEngine` — full
   suite green except known pre-existing flakes
   (`MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget`,
   `MemoryReporter.residentBytes` env-dependent). Any other failure
   is a regression — diagnose before committing.

5. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml \
   --quiet PhospheneEngine/Sources/Renderer/Dashboard/ \
   PhospheneEngine/Tests/PhospheneEngineTests/Renderer/` — zero
   violations on touched files.

6. **Artifact eyeball** (manual): copy `.build/dash1_artifacts/
   card_beat_locked.png` into the project tree (`mkdir -p
   /Users/braesidebandit/Documents/Projects/phosphene/.build/
   dash1_artifacts && cp …`) — see DASH.2.1 closeout for the path
   resolution bug. Open in Preview. Verify:
   - Card chrome is purple-tinted (visible against the deep-indigo
     backdrop), not black.
   - Title `BEAT` reads in muted UPPERCASE.
   - Row order top-to-bottom: MODE / BPM / BAR / BEAT.
   - MODE value `LOCKED` reads in green (statusGreen).
   - BPM value `140` reads cleanly, mono medium.
   - BAR progress bar fills ~62% with purpleGlow; valueText `3 / 4`.
   - BEAT progress bar fills ~50% with coral; valueText `3`.
   - Card is NOT a clipart admin tile. If it is, .impeccable was not
     internalised — re-read before tuning.

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** — Phase DASH §Increment DASH.3:
   flip status to ✅ with the date. Update the "Done when" checklist.
   Add a one-line implementation summary noting the new
   `.progressBar` row variant and `BeatCardBuilder` data binder.

2. **`docs/DECISIONS.md`** — append D-083 covering:
   - The `.progressBar` row variant rationale (unsigned ramps need
     left-to-right fill; reusing `.bar` with range `0...1` would
     waste the left half of the bar visually).
   - The lock-state colour mapping (.impeccable Color section: green
     = precision/data, yellow = transition, muted = off).
   - The no-grid graceful rendering policy (`—` placeholders, no
     "loading" or "—.—" or other transient states; the absence of a
     grid is a stable visual state).
   - The `derivedBeatPhase` approximation and the explicit deferral of
     adding `beatPhase01` to `BeatSyncSnapshot`.

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X] DASH.3
   — Beat & BPM card` entry covering files added, tests added,
   what's intentionally NOT in this increment (DASH.6 wiring, snapshot
   field additions), decision IDs, test-suite count delta.

4. **`CLAUDE.md` Module Map** — under `Renderer/Dashboard/`, add:
   - `BeatCardBuilder` — pure function `BeatSyncSnapshot →
     DashboardCardLayout` for the BEAT card (4 rows: MODE / BPM / BAR /
     BEAT). Lock-state colour mapping per .impeccable.
   - Update `DashboardCardLayout` line to mention the third Row case
     (`.progressBar` for unsigned 0–1 ramps).
   - Update `DashboardCardRenderer` line to mention progress-bar
     rendering (left-to-right fill; reuses `drawBarChrome`).

────────────────────────────────────────
COMMITS
────────────────────────────────────────

Three commits, in this order. Each must pass tests at the commit
boundary.

1. `[DASH.3] dashboard: add .progressBar row variant`
   — `DashboardCardLayout.swift` + `DashboardCardRenderer.swift` +
   `DashboardCardRendererProgressBarTests.swift` (3 tests). Sources
   and tests for the renderer change land together because the new
   variant is unusable without renderer support and the renderer
   tests are the only proof the variant works.

2. `[DASH.3] dashboard: add BeatCardBuilder + 6 builder tests`
   — `BeatCardBuilder.swift` + `BeatCardBuilderTests.swift`. Builder
   is a pure function over `BeatSyncSnapshot` — no Metal needed for
   the unit tests; only test (c)'s artifact render touches a device.

3. `[DASH.3] docs: ENGINEERING_PLAN, DECISIONS D-083, release note,
   CLAUDE.md module map`
   — docs only.

Local commits to `main` only. Do NOT push to remote without explicit
"yes, push" approval.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **`derivedBeatPhase` can go negative or > 1** between MIRPipeline
  updates if `barPhase01` and `beatInBar` update on different frames.
  The builder must clamp to [0, 1] before passing to `.progressBar`
  (which clamps again defensively). Don't trust the upstream snapshot
  to be self-consistent — DASH.3.5 / DSP.3.5 history shows
  cross-field invariants get violated under live conditions.

- **`gridBPM == 0` is the no-grid sentinel, NOT a true zero.** The
  builder must treat `<= 0` as "no grid" and emit `—`. A real BPM is
  always > 60 in practice (the IOI clamp). The .zero sentinel uses 0
  exactly for this reason.

- **`statusYellow` luminance vs surfaceRaised** — Yellow on a dark
  purple-tinted surface can read as muddy. If the artifact eyeball
  shows LOCKING reading muddy, escalate to `Color.coralMuted` (warm,
  more visible mid-state) in a follow-up — but do NOT change tokens
  in DASH.3 without surfacing the issue first. Yellow IS the spec.

- **Test (c)'s `derivedBeatPhase` calculation** is the load-bearing
  invariant for the BEAT bar. If the formula is reordered (e.g. round
  vs floor on `beatInBar`), the test bounds [0.49, 0.51] will fail.
  This is intentional — the formula is part of the contract.

- **STOP and report instead of forging ahead** if:
  - Any DASH.1 or DASH.2 test breaks (12 + 6 = 18 must remain green).
    DASH.3 must not regress prior increments.
  - SwiftLint introduces violations on touched files.
  - The artifact eyeball shows the BEAT card reading as a generic
    metrics tile (rounded rect with stat numbers) rather than a
    typographic instrument panel — that means the row-type-vs-token
    decisions weren't internalised.
  - You find yourself adding a fifth row, an animation, a settings
    toggle, or a `beatPhase01` field on `BeatSyncSnapshot`. None are
    in scope; pause and surface the pressure.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- DASH.2.1 layout: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
- DASH.2.1 renderer: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift`
- DASH.2.1 tests (canonical helpers, copy locally): `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardCardRendererTests.swift`
- DASH.1 tokens: `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift`
- BeatSyncSnapshot: `PhospheneEngine/Sources/Shared/BeatSyncSnapshot.swift`
- DSP.3.1 mode label precedent (colour / glyph mapping): `PhospheneEngine/Sources/Renderer/SpectralCartographText.swift` `drawModeLabel(_:)`
- Design context: `.impeccable.md` (Color section, Aesthetic Direction)
- D-082 + Amendment 1: dashboard card layout engine + .impeccable redesign
- CLAUDE.md: Increment Completion Protocol, Visual Quality Floor, What
  NOT To Do
