Execute Increment DASH.5 — Frame budget card.

Authoritative spec: docs/ENGINEERING_PLAN.md §Phase DASH §Increment DASH.5.
Authoritative design: .impeccable.md §Aesthetic Direction (Color, Typography),
§State-Specific Design Notes, §Anti-Patterns. Read both before writing
any code.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. DASH.4 must have landed. Verify with
   `git log --oneline | grep '\[DASH\.4\]'` — expect two commits
   ending with `[DASH.4] docs: ENGINEERING_PLAN, DECISIONS D-084, …`.

2. Confirm DASH.4's API surface is in place:
   `test -f PhospheneEngine/Sources/Renderer/Dashboard/StemsCardBuilder.swift`
   — file must exist.

3. Confirm DASH.3's API surface is still in place (you will reuse
   `.singleValue` and `.progressBar`):
   `grep -E "case progressBar|case singleValue" \
     PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
   — both row variants must be present.

4. Decision-ID numbering: D-084 covers DASH.4. The next available number
   is **D-085**. Verify with
   `grep '^## D-0' docs/DECISIONS.md | tail -3`.

5. The data sources you will read live in two existing types — do NOT
   modify either:

   - `PhospheneEngine/Sources/Renderer/FrameBudgetManager.swift`
     - `public private(set) var currentLevel: QualityLevel`
     - `public var recentMaxFrameMs: Float` (computed; 30-slot rolling
       window — see CLAUDE.md FrameBudgetManager entry)
     - `public var recentFramesObserved: Int`
     - `public let configuration: Configuration` → `targetFrameMs: Float`
     - `QualityLevel.displayName: String` ("full", "no-SSGI",
       "no-bloom", "step-0.75", "particles-0.5", "mesh-0.5") — already
       returns the .impeccable-aligned compact form.

   - `PhospheneEngine/Sources/Renderer/MLDispatchScheduler.swift`
     - `public private(set) var lastDecision: Decision?`
     - `Decision = .dispatchNow | .defer(retryInMs: Float) | .forceDispatch`
     - `public private(set) var forceDispatchCount: Int`

6. `default.profraw` may be present in the repo root. Ignore.

────────────────────────────────────────
GOAL
────────────────────────────────────────

The third live dashboard card. DASH.3 produced BEAT (beat-grid state);
DASH.4 produced STEMS (stem-energy deviation); DASH.5 produces PERF —
the device-health card driven by the existing renderer governor state.

This increment is **data binding only**. It does NOT add a new row
variant. It does NOT wire the card into PlaybackView or compose
multiple cards (DASH.6). It produces:

  1. A small `PerfSnapshot` Sendable value type (8–12 fields, no logic)
     so the builder has a single Sendable input crossing actor lines.
     Mirrors DASH.3's `BeatSyncSnapshot` pattern (the live state is
     spread across two manager classes — assembling a snapshot at the
     call site is the right seam, and is not the same as DASH.4's
     rejected `StemEnergySnapshot` because there is no single existing
     live type to read from like `StemFeatures`).

  2. A `PerfCardBuilder` struct that maps `PerfSnapshot` →
     `DashboardCardLayout` (title `PERF`, three rows FRAME / QUALITY /
     ML).

  3. Status-colour semantics consistent with .impeccable / D-083:
     muted = no info, green = healthy, yellow = governor active /
     degraded.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

1. NEW FILE — `PerfSnapshot.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/PerfSnapshot.swift`

   ```
   /// Sendable per-frame snapshot of renderer governor + ML dispatch
   /// state, used as the single input to `PerfCardBuilder`. Assembled
   /// by the caller (typically RenderPipeline / VisualizerEngine) from
   /// `FrameBudgetManager` and `MLDispatchScheduler`. Pure value type —
   /// no references to either manager.
   public struct PerfSnapshot: Sendable, Equatable {
       /// Maximum frame time over the recent rolling window (ms).
       public var recentMaxFrameMs: Float
       /// Number of frames that have populated the rolling window so
       /// far. 0 when the manager has not yet observed any frame —
       /// FRAME row renders "—" and bar at 0 in that case.
       public var recentFramesObserved: Int
       /// Per-tier frame budget target (ms). Used as the FRAME bar's
       /// upper bound; typical value 14 ms (Tier 1) or 16 ms (Tier 2).
       public var targetFrameMs: Float
       /// Current quality level rawValue (0=full ... 5=reducedMesh).
       /// rawValue used (not the enum) so `PerfSnapshot` does not pull
       /// in `FrameBudgetManager.QualityLevel` and the snapshot stays
       /// trivially `Sendable`.
       public var qualityLevelRawValue: Int
       /// Display string for the quality level (`QualityLevel.displayName`).
       /// Caller passes through; builder does not re-derive.
       public var qualityLevelDisplayName: String
       /// ML dispatch decision encoding:
       ///   0 = no decision yet (lastDecision == nil)
       ///   1 = dispatchNow
       ///   2 = defer
       ///   3 = forceDispatch
       /// Same pattern as `BeatSyncSnapshot.sessionMode`.
       public var mlDecisionCode: Int
       /// When `mlDecisionCode == 2` (.defer), the retry-in delay in
       /// milliseconds. Zero otherwise.
       public var mlDeferRetryMs: Float

       public init(
           recentMaxFrameMs: Float,
           recentFramesObserved: Int,
           targetFrameMs: Float,
           qualityLevelRawValue: Int,
           qualityLevelDisplayName: String,
           mlDecisionCode: Int,
           mlDeferRetryMs: Float
       )

       /// Neutral snapshot — no observations, full quality, no ML
       /// decision yet. Used by tests + as a startup default.
       public static let zero: PerfSnapshot
   }
   ```

   `.zero` produces: `recentMaxFrameMs=0, recentFramesObserved=0,
   targetFrameMs=14.0, qualityLevelRawValue=0,
   qualityLevelDisplayName="full", mlDecisionCode=0, mlDeferRetryMs=0`.

   Do NOT expose convenience constructors that accept a
   `FrameBudgetManager` and `MLDispatchScheduler`. The snapshot is a
   pure value type, and snapshot construction lives at the call site
   (DASH.6 scope, not DASH.5). Keep imports minimal — no
   `import Renderer` from this file (it lives inside Renderer, not
   above it).

2. NEW FILE — `PerfCardBuilder.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/PerfCardBuilder.swift`

   ```
   /// Maps a `PerfSnapshot` to a `DashboardCardLayout` for the PERF
   /// card. Pure function — no Metal, no allocations beyond the layout
   /// itself. Safe to call every frame.
   public struct PerfCardBuilder: Sendable {
       public init() {}
       public func build(
           from snapshot: PerfSnapshot,
           width: CGFloat = 280
       ) -> DashboardCardLayout
   }
   ```

   The builder produces a card titled `PERF` with **three** rows in
   this display order:

   - **FRAME** (`.progressBar`):
     - label `FRAME`.
     - value: `recentMaxFrameMs / targetFrameMs` clamped to [0, 1] —
       `.progressBar` is unsigned 0–1 by definition (D-083), and the
       builder is the right place to do this normalization since the
       row variant carries no `range` field. Test (e) regression-locks
       the clamp.
     - valueText:
       - `"—"` when `recentFramesObserved == 0`.
       - `String(format: "%.1f ms", recentMaxFrameMs)` otherwise (e.g.
         `"12.4 ms"`, `"7.8 ms"`).
     - fillColor: `Color.coral` (uniform — direction / fill ratio
       carries headroom semantics; per-bar status-colour tinting is a
       potential DASH.5.1 amendment if review surfaces it, do NOT
       pre-empt).

   - **QUALITY** (`.singleValue`):
     - label `QUALITY`.
     - value: `qualityLevelDisplayName` ("full", "no-SSGI", etc.) —
       passed through verbatim from the snapshot. Builder does NOT
       lowercase / uppercase / re-format. The DASH.2.1 row renderer
       already uppercases via `String.uppercased()` if you want all-
       caps, but `displayName` returns mixed case ("no-SSGI") and the
       compact tokens already read as labels rather than prose — leave
       case alone.
     - valueColor:
       - `recentFramesObserved == 0` → `Color.textMuted` ("—" should
         not be rendered here; the displayName always has a real
         string. The muted-on-no-observations rule applies to FRAME's
         valueText, not to QUALITY's value. QUALITY uses muted
         exclusively when the governor has nothing to say, which is
         when `recentFramesObserved == 0` AND `qualityLevelRawValue
         == 0` — hand off to the next bullet for that combined case).
         Concretely: `recentFramesObserved == 0` → `textMuted` over
         the displayName ("full" rendered in muted grey, signalling
         "no observations yet, default level").
       - `qualityLevelRawValue == 0` AND `recentFramesObserved > 0`
         → `statusGreen` (healthy: governor has observed frames and
         is at full quality).
       - `qualityLevelRawValue >= 1` → `statusYellow` (governor has
         downshifted at least once — degradation is happening, but no
         status colour for "broken" exists in the token system, and
         nothing is broken; the governor doing its job is the
         expected state under load).

   - **ML** (`.singleValue`):
     - label `ML`.
     - value mapping (mirrors DASH.3 lock-state colour mapping
       precedent):
       - `mlDecisionCode == 0` → `"—"` (no decision yet).
       - `mlDecisionCode == 1` → `"READY"` (dispatchNow — clean
         frames, ML free to run).
       - `mlDecisionCode == 2` → `String(format: "WAIT %.0fms",
         mlDeferRetryMs)` — round to whole ms; if `mlDeferRetryMs == 0`
         render `"WAIT"` plain (no trailing zero).
       - `mlDecisionCode == 3` → `"FORCED"` (max-deferral exceeded;
         scheduler forced the dispatch onto a non-clean frame).
       - Any other rawValue → `"—"` (graceful fallback; do NOT
         crash / fatalError).
     - valueColor:
       - `mlDecisionCode == 0` → `Color.textMuted`.
       - `mlDecisionCode == 1` → `Color.statusGreen`.
       - `mlDecisionCode == 2` → `Color.statusYellow`.
       - `mlDecisionCode == 3` → `Color.statusYellow` (forced
         dispatch is a yellow signal — the system is shipping work
         but not on its preferred timing; statusGreen would imply
         "everything is fine" which is misleading).
       - Other → `Color.textMuted`.

   The builder is a pure function. No clamping is required at the
   builder layer for `qualityLevelRawValue` or `mlDecisionCode` —
   unknown values fall through to muted "—" gracefully (defence-in-
   depth at the rendering boundary, not the ingestion boundary). The
   FRAME bar value DOES clamp to [0, 1] at the builder layer because
   `.progressBar` has no `range` field — the row variant cannot
   defend itself the way `.bar` can. Test (e) locks this.

3. NEW TEST FILE — `PerfCardBuilderTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PerfCardBuilderTests.swift`

   Six `@Test` functions in `@Suite("PerfCardBuilder")`:

   a. **`build_zeroSnapshot_producesNoObservationsLayout`**: feed
      `PerfSnapshot.zero`, assert `title == "PERF"`, `rows.count == 3`.
      FRAME (`.progressBar`) — value 0, valueText "—", fillColor
      coral. QUALITY (`.singleValue`) — value "full", valueColor
      `textMuted` (no observations). ML (`.singleValue`) — value "—",
      valueColor `textMuted`. Use the same switch-pattern row
      extractors + sRGB-channel colour comparator pattern from
      `BeatCardBuilderTests` / `StemsCardBuilderTests`. Copy the
      helpers locally (file-independence convention).

   b. **`build_healthyFullQuality_producesGreenQualityAndReadyML`**:
      snapshot with `recentMaxFrameMs=8.2, recentFramesObserved=30,
      targetFrameMs=14, qualityLevelRawValue=0,
      qualityLevelDisplayName="full", mlDecisionCode=1,
      mlDeferRetryMs=0`. Assert: FRAME value ≈ 0.586 (8.2/14;
      tolerance ±0.01), valueText "8.2 ms"; QUALITY value "full",
      valueColor `statusGreen`; ML value "READY", valueColor
      `statusGreen`.

   c. **`build_governorDownshifted_producesYellowQualityAndDeferML`**:
      snapshot with `recentMaxFrameMs=15.3, recentFramesObserved=30,
      targetFrameMs=14, qualityLevelRawValue=2,
      qualityLevelDisplayName="no-bloom", mlDecisionCode=2,
      mlDeferRetryMs=200`. Assert: FRAME value clamps to 1.0 (15.3/14
      = 1.09; clamp to 1.0), valueText "15.3 ms"; QUALITY value
      "no-bloom", valueColor `statusYellow`; ML value "WAIT 200ms",
      valueColor `statusYellow`.

   d. **`build_forcedDispatch_producesYellowMLForced` + artifact**:
      snapshot representative of governor pressure — FRAME ≈ 11.2 ms
      (~80% of 14 ms budget, governor at full but ML forced):
      `recentMaxFrameMs=11.2, recentFramesObserved=30,
      targetFrameMs=14, qualityLevelRawValue=0,
      qualityLevelDisplayName="full", mlDecisionCode=3,
      mlDeferRetryMs=0`. Assert: FRAME value ≈ 0.8, valueText "11.2 ms";
      QUALITY "full" `statusGreen`; ML "FORCED" `statusYellow`.

      Then render the layout via `DashboardCardRenderer` onto a
      320×220 `DashboardTextLayer` with the deep-indigo backdrop
      helper, write to `.build/dash1_artifacts/card_perf_active.png`.
      Mirrors the artifact pattern from
      `BeatCardBuilderTests.build_lockedSnapshot_…` and
      `StemsCardBuilderTests.build_mixedSnapshot_…`.

   e. **`build_frameTimeAboveBudget_clampsBarValueAtOne`**:
      snapshot with `recentMaxFrameMs=42.0, recentFramesObserved=10,
      targetFrameMs=14, qualityLevelRawValue=5,
      qualityLevelDisplayName="mesh-0.5", mlDecisionCode=0,
      mlDeferRetryMs=0`. Assert FRAME `value == 1.0` exactly (clamp
      authority lives in the builder for `.progressBar` because the
      row variant has no `range` field). valueText "42.0 ms" (raw value
      passed to format string — not clamped, since the user wants to
      see how bad it actually is). Document via test name + inline
      `// ` comment that the FRAME clamp is *builder-layer*, in
      contrast to STEMS where clamp authority is renderer-layer
      (D-084).

   f. **`build_widthOverride_passesThrough`**: call
      `build(from: .zero, width: 320)`, assert resulting layout's
      `width == 320`. Default-arg test mirroring
      `BeatCardBuilderTests.build_widthOverride_passesThrough` and
      `StemsCardBuilderTests.build_widthOverride_passesThrough`.

   Switch-pattern row extractors + `colorMatches` sRGB comparator are
   copied from `StemsCardBuilderTests` (file-independence). The
   `savePNGArtifact` + `writeTextureToPNG` helpers and bundle anchor
   pattern are copied locally too — do NOT hoist.

4. ARTIFACT
   Test (d) writes `card_perf_active.png` to `.build/dash1_artifacts/`.
   This is the artifact Matt will eyeball during M7-style review of
   the live PERF card. Use the same deep-indigo backdrop helper as
   DASH.3 / DASH.4 artifacts so the three card artifacts compose
   visually under review.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT modify `FrameBudgetManager` or `MLDispatchScheduler`. Both
  already expose every field PERF needs. Adding convenience
  constructors / accessors there is DASH.6 scope, not DASH.5.
- Do NOT introduce a constructor that takes
  `FrameBudgetManager` + `MLDispatchScheduler` instances (e.g.
  `PerfSnapshot(from: budget, ml:)`). The snapshot is a pure value
  type; assembly happens at the call site in DASH.6.
- Do NOT wire `PerfCardBuilder` into `RenderPipeline`,
  `PlaybackView`, `DebugOverlayView`, or any encoder. DASH.6 owns
  wiring.
- Do NOT compose multiple cards into a dashboard layout. DASH.6 owns
  multi-card composition and screen positioning.
- Do NOT add a fourth row (e.g. GPU TIME, MEMORY, FPS, dropped
  frames). The PERF card is exactly FRAME / QUALITY / ML. Per-frame
  GPU timing belongs to a future increment if and only if soak-test
  reports show it carries information not already in
  `recentMaxFrameMs`.
- Do NOT add per-row colour tuning for FRAME (e.g. coral when
  comfortable, yellow when nearing budget, red when over). The
  uniform-colour-with-direction-as-signal lesson from DASH.4 (D-084)
  applies: the bar fill ratio itself encodes headroom; QUALITY's
  status-colour-coded text carries the actual governor state. If
  Matt's eyeball flags ambiguity, that becomes a DASH.5.1
  amendment ticket — do NOT pre-empt.
- Do NOT add Equatable to `Row` or its associated values (D-082,
  D-083, D-084). NSColor comparison is non-trivial; tests use
  switch-pattern extraction.
- Do NOT add a sparkline / mini-graph for frame time history. The
  card is typographic + bar geometry, consistent with .impeccable
  "no animation" and DASH.2.1 / DASH.3 / DASH.4 precedent. A history
  visualization, if needed, is a future increment with its own scope.
- Do NOT introduce a `statusRed` token. The token system has
  `textBody` / `textHeading` / `textMuted` / `statusYellow` /
  `statusGreen` / `coral` / `purpleGlow` (see DashboardTokens). Red
  has no current sanctioned use; the governor never enters a state
  the user needs alarm-coloured signalling for.
- Do NOT clamp `qualityLevelRawValue` or `mlDecisionCode` at the
  builder. Unknown values fall through to muted "—" gracefully.
- Do NOT format frame time with more than one decimal place. `"%.1f
  ms"` is right — `"%.2f ms"` reads as fake precision (the rolling
  window itself only has ~30 samples).

────────────────────────────────────────
DESIGN GUARDRAILS (.impeccable.md)
────────────────────────────────────────

- **Status colour discipline.** Green = healthy / READY. Yellow =
  transitional / degraded / governor-active / WAIT / FORCED. Muted =
  no information yet. This is the same three-state system DASH.3
  used for lock state (D-083). PERF reuses it because the underlying
  semantic — "is the system in a good state?" — is identical.
- **Direction / ratio carries meaning.** FRAME's bar fill ratio is
  the load-bearing signal (what fraction of the budget did the worst
  recent frame consume?). QUALITY's text token is the discrete-state
  signal. ML's text is the timing-state signal. Colour reinforces;
  it does not differentiate.
- **Stable absence-of-information state.** When
  `recentFramesObserved == 0`, FRAME draws no fill (bar value 0) and
  QUALITY / ML render in `textMuted`. This is a stable visual state,
  not a transient. No "loading" or "—.—" placeholders beyond the
  single em-dash convention DASH.3 already established.
- **No icons. No animation. No sparkline.** The card is typographic
  + bar geometry. Per-frame rebuild from current state.
- **Whitespace as signal.** Don't tighten row spacing. The DASH.2.1
  row rhythm holds.

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
   --filter "BeatCardBuilder|StemsCardBuilder|PerfCardBuilder|\
   DashboardCardRenderer|DashboardTextLayer|DashboardTokens|\
   DashboardFontLoader"` — all 39 tests pass (12 DASH.1 + 6 DASH.2.1
   + 6 BeatCardBuilder + 3 ProgressBar + 6 StemsCardBuilder + 6
   PerfCardBuilder).

4. **Test (full)**: `swift test --package-path PhospheneEngine` — full
   suite green except known pre-existing flakes
   (`MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget`,
   `MemoryReporter.residentBytes` env-dependent,
   `RenderPipelineICBTests.test_gpuDrivenRendering_cpuFrameTimeReduced`
   and `SSGITests.test_ssgi_performance_under1ms_at1080p` —
   parallel-contention flakes that pass in isolation, see DASH.4
   release note). Any other failure is a regression — diagnose
   before committing.

5. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml \
   --quiet PhospheneEngine/Sources/Renderer/Dashboard/ \
   PhospheneEngine/Tests/PhospheneEngineTests/Renderer/` — zero
   violations on touched files. (Note: trailing-comma spacing /
   double-space-after-comma on parameter alignment caught DASH.4 —
   keep single spaces between `,` and the next identifier.)

6. **Artifact eyeball** (manual): copy
   `.build/dash1_artifacts/card_perf_active.png` into the project
   tree (`mkdir -p /Users/braesidebandit/Documents/Projects/phosphene/\
   .build/dash1_artifacts && cp …` — see DASH.2.1 / DASH.3 / DASH.4
   closeout for the path resolution bug). Open in Preview. Verify:
   - Card chrome is purple-tinted (visible against the deep-indigo
     backdrop), not black.
   - Title `PERF` reads in muted UPPERCASE.
   - Row order top-to-bottom: FRAME / QUALITY / ML.
   - FRAME bar fills ~80% of the way across (11.2 / 14 ms), valueText
     reads `"11.2 ms"` in coral on the right.
   - QUALITY value reads `"full"` in **green** (statusGreen).
   - ML value reads `"FORCED"` in **yellow** (statusYellow).
   - Card does NOT read like a system-monitor / Activity Monitor
     widget — text-and-bar discipline holds.
   - If the per-row colour mix (coral fill / green text / yellow
     text on the same card) feels chaotic, that is the trigger for a
     DASH.5.1 amendment ticket (NOT a within-DASH.5 fix). Surface the
     observation; do not unilaterally retune.

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** — Phase DASH §Increment DASH.5:
   flip status to ✅ with the date. Update the "Done when" checklist.
   Add a one-line implementation summary noting the new
   `PerfSnapshot` value type, `PerfCardBuilder`, the three-row layout,
   and the green-healthy / yellow-degraded / muted-no-info status
   discipline.

2. **`docs/DECISIONS.md`** — append D-085 covering:
   - Why a `PerfSnapshot` value type rather than passing the manager
     instances or individual parameters: snapshot lives in Renderer
     module (no upward import), is `Sendable` for actor-line crossing,
     and matches DASH.3's `BeatSyncSnapshot` pattern. Differs from
     DASH.4's rejected `StemEnergySnapshot` because there is no
     existing single live type to read from like `StemFeatures` —
     PERF state is genuinely spread across two manager classes.
   - Why FRAME is a `.progressBar` (unsigned ramp 0..1) and not a
     `.bar` (signed-from-centre): frame time vs budget is naturally
     unsigned, headroom is the load-bearing signal, and `.progressBar`
     is exactly the variant D-083 added for ramps.
   - Why FRAME clamps at the builder (in contrast to STEMS, where
     clamp authority is at the renderer per D-084): `.progressBar`
     has no `range` field — the row variant cannot defend itself.
     Single source of truth for the clamp is the builder.
   - Why `qualityLevelRawValue` is encoded as Int rather than
     re-exposing `FrameBudgetManager.QualityLevel`: keeps
     `PerfSnapshot` trivially `Sendable` without importing the
     manager's enum, and the displayName carries the human-readable
     part. Same pattern as `BeatSyncSnapshot.sessionMode`.
   - Why ML decision is encoded as Int + a separate retry-ms float
     rather than re-exposing `MLDispatchScheduler.Decision`: same
     reason — keep the snapshot a leaf value type, no upward
     dependency on the scheduler's enum.
   - Why no `statusRed` token is introduced: the governor never
     enters a state the user needs alarm-coloured signalling for; the
     "yellow = governor active" semantic is sufficient and consistent
     with D-083's three-state palette. The "no red" rule is durable
     across the dashboard, not just PERF.
   - Why no per-row colour tuning for FRAME (uniform coral),
     consistent with D-084's stems-card decision: bar fill ratio
     carries headroom, QUALITY text carries discrete state, colour
     reinforces rather than differentiates.
   - The DASH.5.1 amendment slot for any per-row colour or
     formatting tuning surfaced by Matt's eyeball.

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X] DASH.5
   — Frame budget card` entry covering files added, tests added,
   what's intentionally NOT in this increment (DASH.6 wiring, no
   sparkline, no fourth row, no statusRed, no per-row tuning),
   decision IDs, test-suite count delta (33 → 39 dashboard tests).

4. **`CLAUDE.md` Module Map** — under `Renderer/Dashboard/`, add:
   - `PerfSnapshot` — Sendable value type wrapping renderer governor
     (`FrameBudgetManager.recentMaxFrameMs` / `currentLevel` /
     `targetFrameMs`) + ML dispatch state (`MLDispatchScheduler.
     lastDecision` / `forceDispatchCount`) for the PERF card.
     Decision/quality enums encoded as Int + display string so the
     snapshot is trivially `Sendable` without importing the manager
     enums. `.zero` neutral default.
   - `PerfCardBuilder` — pure function `PerfSnapshot →
     DashboardCardLayout` for the PERF card (3 rows: FRAME / QUALITY
     / ML). FRAME is `.progressBar` (unsigned ramp, builder-layer
     clamp); QUALITY + ML are `.singleValue` with status-colour
     mapping (green=healthy, yellow=governor active / WAIT /
     FORCED, muted=no observations yet). DASH.5, D-085.

────────────────────────────────────────
COMMITS
────────────────────────────────────────

Two commits, in this order. Each must pass tests at the commit boundary.

1. `[DASH.5] dashboard: add PerfSnapshot + PerfCardBuilder + 6 builder tests`
   — `PerfSnapshot.swift` + `PerfCardBuilder.swift` +
   `PerfCardBuilderTests.swift`. The builder is a pure function over
   `PerfSnapshot` — no Metal needed for the unit tests; only test (d)'s
   artifact render touches a device. No new row variant means no
   renderer change in this increment (one less commit than DASH.3,
   matching DASH.4's two-commit shape).

2. `[DASH.5] docs: ENGINEERING_PLAN, DECISIONS D-085, release note,
   CLAUDE.md module map`
   — docs only.

Local commits to `main` only. Do NOT push to remote without explicit
"yes, push" approval.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **Status-colour drift across cards.** BEAT (D-083) uses muted /
  yellow / green for lock state. PERF must use the same palette for
  the same semantic (no info / transitional or degraded / healthy).
  If you find yourself reaching for `statusYellow` to mean "warning"
  in one row and "transitional" in another, stop — the semantic is
  one thing, applied consistently.

- **Tempting "red = over budget" introduction.** The token system
  intentionally has no `statusRed`. The first DASH.5 PR will be
  tempting to flag "FRAME bar fill > 1.0" with a red colour. Don't.
  The QUALITY row already says "the governor downshifted in
  response", which is the actionable signal. A red FRAME bar would
  triple-encode the same information and break D-085's no-red rule.

- **`PerfSnapshot` accidentally importing manager types.** If
  `PerfSnapshot` ends up with a `qualityLevel: FrameBudgetManager.
  QualityLevel` field (instead of the rawValue Int + displayName
  String pair), the snapshot pulls in `Renderer/FrameBudgetManager.
  swift` and may compile-leak its dependencies into anywhere that
  imports `Renderer.PerfSnapshot`. The Int+String encoding is
  deliberate — keep it.

- **Builder clamp at the wrong layer.** STEMS (D-084) clamps in the
  renderer because `.bar` carries a `range` field. PERF (D-085)
  clamps in the builder because `.progressBar` does not. The
  asymmetry is documented; tests (e) regression-lock both. If you
  find yourself adding a clamp in the renderer for `.progressBar`,
  stop — that's a different increment.

- **STOP and report instead of forging ahead** if:
  - Any DASH.1 / DASH.2 / DASH.3 / DASH.4 test breaks (12 + 6 + 6 + 3
    + 6 = 33 must remain green). DASH.5 must not regress prior
    increments.
  - SwiftLint introduces violations on touched files.
  - The artifact eyeball shows the PERF card reading like a
    system-monitor widget — that means typographic discipline lapsed.
  - You find yourself adding a fourth row, a sparkline, a
    `statusRed` token, per-row colour tuning, or wiring the card
    into PlaybackView. None are in scope; pause and surface the
    pressure.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- DASH.3 builder (canonical pattern, `BeatSyncSnapshot` analogue):
  `PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift`
- DASH.3 builder tests (canonical helpers, copy locally):
  `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/BeatCardBuilderTests.swift`
- DASH.4 builder (most recent canonical pattern):
  `PhospheneEngine/Sources/Renderer/Dashboard/StemsCardBuilder.swift`
- DASH.4 builder tests:
  `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/StemsCardBuilderTests.swift`
- DASH.2 layout:
  `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
- DASH.2 renderer:
  `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift`
- DASH.3 progress-bar renderer extension (clamp at row level via
  `clamp(value, 0, 1)`):
  `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer+ProgressBar.swift`
- DASH.1 tokens (`textBody` / `textMuted` / `statusGreen` /
  `statusYellow` / `coral` / `purpleGlow`):
  `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift`
- FrameBudgetManager (governor + 30-slot rolling window):
  `PhospheneEngine/Sources/Renderer/FrameBudgetManager.swift`
- MLDispatchScheduler (decision enum + lastDecision):
  `PhospheneEngine/Sources/Renderer/MLDispatchScheduler.swift`
- BeatSyncSnapshot (Int-encoded enum precedent for `sessionMode`):
  `PhospheneEngine/Sources/Shared/BeatSyncSnapshot.swift`
- D-082, D-082.1, D-083, D-084: dashboard layout engine + .impeccable
  redesign + BEAT card binding + STEMS card binding
- CLAUDE.md: Increment Completion Protocol, Visual Quality Floor,
  What NOT To Do, FrameBudgetManager / MLDispatchScheduler entries
  in the Module Map
- Design context: `.impeccable.md` (Color section, Aesthetic
  Direction)
