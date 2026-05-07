# Phosphene — Developer Release Notes

Internal release notes for the `main` branch. Audience: Matt and Claude Code. Each entry covers one session or a logical batch of increments. These notes complement `docs/ENGINEERING_PLAN.md` (authoritative for what's planned) and `docs/QUALITY/KNOWN_ISSUES.md` (authoritative for open defects).

User-visible release notes are not yet in scope (no public build).

---

## [dev-2026-05-07-c] DASH.2.1 — Card layout redesign: stacked rows + WCAG-AA labels + brighter chrome

**Increment:** DASH.2.1 (amendment to DASH.2)
**Type:** Design (renderer)

**What changed.**

`/impeccable` review of the DASH.2 artifact surfaced five issues that constant-tuning could not fix: (1) horizontal `label LEFT … value RIGHT` swallowed the label-value relationship at typical card widths; (2) `textMuted` on the card surface gave ~3.3:1 contrast — failing WCAG AA for body-size text; (3) `Color.surface` (oklch 0.13) read as near-black against any backdrop; (4) the pair-row 1 px divider was invisible; (5) bar rows had label/bar/value spatially detached. All five resolved.

**API changes:**

- `DashboardCardLayout.Row` cases reduced to two: `.singleValue` and `.bar` (the `.pair` variant is removed; no callers).
- Stacked layout: label 11 pt UPPERCASE on top, value below. Heights: `singleHeight = 39` (11 + 4 + 24), `barHeight = 32` (11 + 4 + 17). New constant `DashboardCardLayout.labelToValueGap = 4`.
- `DashboardCardLayout.height` skips the `titleSize` term when `title.isEmpty`.

**Renderer changes:**

- Card chrome: `Color.surface` → `Color.surfaceRaised` (oklch 0.17 / 0.018, slightly brighter and more chromatic). Alpha 0.92 unchanged.
- Title and all row labels: `Color.textMuted` → `Color.textBody` (~10:1 vs ~3.3:1).
- Bar row geometry: bar reserves a 56 pt right-side column for value text + 8 pt gap; bar centre is the bar's own mid-x, not the card centre. Bar fill refactored into `drawBarChrome` + `drawBarFill` helpers (SwiftLint compliance).

**Test changes (still 6 in `@Suite("DashboardCardRenderer")`):**

- `render_pairRow_dividerVisible` removed (variant deleted); replaced with `render_singleValueRow_stacksLabelAboveValue` (asserts vertical span between first and last glyph row ≥ 12 pt).
- Canonical artifact test renamed to `render_beatCard_pixelVerifyLabelPositions`. New test helper `paintVisualizerBackdrop` paints a representative deep-indigo backdrop (oklch 0.18 / 0.06 / 285) before the card is drawn — the saved `card_beat.png` now reflects production conditions over a visualizer rather than over transparent black.
- Bar-row tests rebuilt around the new geometry: `barGeometry(for:at:)` helper reproduces the renderer's reserved-column math so sample positions land well inside the fill rather than on its edge.

**Demo fixture (`beatCardFixture`):** card titled `BEAT` with four rows MODE / BPM / BAR / BASS, matching the .impeccable Beat panel. MODE's value uses `Color.statusGreen` for the locked-state colour cue.

**Files edited:**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardCardRendererTests.swift`
- `docs/ENGINEERING_PLAN.md`, `docs/DECISIONS.md` (D-082 Amendment 1), `CLAUDE.md`

**Test counts:** 6 DASH.2 tests rebuilt (still 6); 18 dashboard tests total. Full engine suite green; 0 SwiftLint violations on touched files; app build clean. Decisions: D-082 Amendment 1.

**Visual approval:** Matt approved the new artifact `card_beat.png` 2026-05-07.

---

## [dev-2026-05-07-b] BUG-007.3 — Lock hysteresis + live BPM credibility

**Increment:** BUG-007.3
**Type:** Bug fix (DSP / live beat tracking)

**What changed.**

Closes the two failure modes observed during 2026-05-07 manual validation that BUG-007.2 left unaddressed:

- **Mechanism C — natural-music tempo variation drops lock under correct BPM.** Pre-fix, SLTS held lock 80 s but Everlong dropped 5 times in 50 s with drift in the −30 to −68 ms band, even though grid BPM was correct. Individual onsets falling outside `abs(instantDrift − drift) < 30 ms` for ≥ 7 consecutive onsets dropped lock; at 158 BPM that's a 2.7 s window, easily filled by harmonics, reverb tail, snare bleed.
- **Mechanism D — live BPM resolver returns 4 % low on busy mid-frequency content.** Reactive Everlong locked to `grid_bpm=151.9` (true ≈158); drift went 0 → −358 ms over 75 s.

**Part (a) — Schmitt-style asymmetric hysteresis** (`PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`):

New `staleMatchWindow: Double = 0.060` constant. `update()` lock-decision rewritten — onsets within ±30 ms (`strictMatchWindow`) increment `matchedOnsets` toward `lockThreshold` (acquisition selectivity unchanged). While *already locked*, onsets within ±60 ms but outside ±30 ms are **stale-OK**: they do not increment `matchedOnsets` *or* `consecutiveMisses`, preserving lock through natural expressive timing. Only onsets outside ±60 ms (or no-match returns from `nearestBeat`) increment `consecutiveMisses` toward `lockReleaseMisses=7`.

**Part (b) — drift-slope detector + wider-window retry**:

- New ring buffer of 30 `(playbackTime, driftMs)` samples in `LiveBeatDriftTracker`, pushed on every matched onset. Public `currentDriftSlope() -> Double?` returns least-squares ms/sec slope when ≥ 5 samples cover ≥ 5 s; nil otherwise. Reset on `setGrid` / `reset`.
- New retry trigger in `PhospheneApp/VisualizerEngine+Stems.swift runLiveBeatAnalysisIfNeeded()`. Three paths: (A) no grid → existing 10 s / 20 s initial attempts; (B) prepared-cache grid → skip live inference (BUG-008 territory); (C) live grid present → slope-driven 20 s wider retry when `abs(slope) > 5 ms/s` sustained ≥ 10 s, with 30 s cooldown and a hard cap at 1 retry per track. After the retry, a second high-slope event logs `WARN: live BPM unstable` and *retains* the previous grid rather than installing a third candidate.
- New `BeatGridSource` enum on `VisualizerEngine` (`.none / .preparedCache / .liveAnalysis`) tracks where the installed grid came from so Path C only fires on live grids.

**Files edited:**

- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`
- `PhospheneApp/VisualizerEngine.swift`
- `PhospheneApp/VisualizerEngine+Stems.swift`
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` (4 new tests)
- `docs/QUALITY/KNOWN_ISSUES.md`, `docs/ENGINEERING_PLAN.md`, `docs/RELEASE_NOTES_DEV.md`

**Tests added** (MARKs 19–22 in `LiveBeatDriftTrackerTests`):

- `schmittHysteresis_preservesLockThroughExpressiveTempoVariation` — synthetic 158 BPM grid + sinusoidal ±50 ms drift wander over 60 s. Asserts ≤ 1 lock drop. Pre-fix would drop ≥ 4.
- `driftSlope_insufficientSamples_returnsNil` — slope returns nil before 5 samples accumulate.
- `driftSlope_flatDrift_returnsNearZero` — perfectly aligned onsets for 12 s → slope < 1 ms/s.
- `driftSlope_linearWalkingDrift_recoversSlope` — onsets pushed forward by 4 ms each (≈ 8 ms/s) → recovered |slope| within 2 ms/s of truth, sign negative (drift = nearest − pt convention).

**Tests run.** `LiveBeatDriftTrackerTests` 22 / 22 pass. Full engine suite 1104 / 1106 (two pre-existing flakes: `MemoryReporter.residentBytes` env-dependent, `MetadataPreFetcher.fetch_networkTimeout` timing-sensitive — both pass on isolated re-run). `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` — clean. `swiftlint --strict` — 0 violations on touched files.

**Manual validation pending.** Acceptance gates in `KNOWN_ISSUES.md BUG-007.3`. Capture sessions to be run on SLTS planned, Everlong planned, Everlong reactive, Billie Jean reactive (control).

**Out of scope (deferred).** Constant ~10–15 ms negative-drift offset (tap-output latency calibration). BUG-008 (offline BPM disagreement). `strictMatchWindow` widening (acquisition selectivity stays). Slope-driven retry on prepared-cache path.

---

## [dev-2026-05-07-a] DASH.2 — Metrics card layout engine

**Increment:** DASH.2
**Type:** Infrastructure (renderer)

**What changed.**

Added the layout primitive that DASH.3 (Beat & BPM), DASH.4 (Stems), and DASH.5 (Frame budget) will compose. Cards are the unit of visual identity for the dashboard — fixed width, fixed row heights, three row variants only.

**Files added:**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift` — value type describing one card: title, ordered rows, fixed width, padding, title size, row spacing. `Row` enum with three cases (`.singleValue` / `.pair` / `.bar`) and static row-height constants (single = 18 pt, pair = 18 pt, bar = 22 pt). `height` is computed: `padding + titleSize + (rowSpacing + rowHeight) × N + padding`.
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift` — stateless `Sendable` struct. `render(_:at:on:cgContext:)` paints chrome (rounded `Color.surface` fill at 0.92 alpha + 1 px `Color.border` stroke) → bar geometry → text in that order; reversing the order is a known Failed Approach (text gets painted over). Right-edge clipping enforced via `align: .right` on every value column. Bar fill is signed slice from centre (negative left, positive right), clamped to the supplied range.

**Files edited:**

- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardTextLayer.swift` — added `internal var graphicsContext: CGContext` so the renderer can paint chrome and bar geometry into the same shared buffer the text layer rasterises into.

**Tests added (6 `@Test` functions in `@Suite("DashboardCardRenderer")`):**

- `layoutHeight_matchesSumOfRows` — encodes the height formula explicitly so future row-height edits surface as test failures.
- `render_threeRowCard_pixelVerifyLabelPositions` — renders the canonical three-row card, asserts title-strip glyph alpha and zero paint past `layout.height`. Writes `.build/dash1_artifacts/card_three_row.png` for M7-style review.
- `render_cardNearRightEdge_clipsCorrectly` — places a 280 pt card at `canvasWidth - 280` on a 512 px canvas; asserts the rightmost column's luma is below the text-glyph threshold (chrome fill at the edge is allowed; a stray `textHeading` glyph would fail).
- `render_barRow_negativeValueFillsLeft` — `value: -0.5, range: -1...1` with coral fill: left half coral, right half background.
- `render_barRow_positiveValueFillsRight` — mirror of the negative test.
- `render_pairRow_dividerVisible` — 1 px `Color.border` divider at the midpoint.

Pixel-assertion brittleness (the prompt's risk note) is mitigated by `maxChromaPixel(around:)`: the bar background and foreground are both opaque, so alpha alone cannot distinguish them — chroma can. The right-edge overflow check uses Rec. 601 luma instead of alpha so chrome (low-luma) is correctly distinguished from text glyphs (high-luma `textHeading`).

**What's intentionally NOT in this increment:**

- No card is wired into `RenderPipeline`, `PlaybackView`, or `DebugOverlayView`. DASH.6 owns wiring.
- No data binding (which metrics each card shows). DASH.3/4/5 own that.
- No interactive state (hover, focus). The dashboard is read-only telemetry.
- No animation / transition. Cards repaint each frame from current state.
- No fourth row variant, no flex-width card, no sparkline. Adding variants is a separate increment with explicit Matt approval.

**Decisions:** D-082 (this increment).

**Test counts:** 6 new (18 dashboard total = DASH.1 12 + DASH.2 6). Full engine suite: **1102 tests / 125 suites**, all green. App build clean. 0 SwiftLint violations on touched files.

---

## [dev-2026-05-06-e] DASH.1 — Telemetry dashboard text-rendering layer

**Increment:** DASH.1
**Type:** Infrastructure (renderer + shared)

**What changed.**

Added the foundation layer for Phosphene's floating telemetry dashboard — a developer-togglable HUD that will display real-time metrics (BPM, lock state, stem energies, frame budget) over any active preset.

New files:
- `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift` — design token namespace: `TypeScale` (6 point sizes from caption=10 to display=36), `Spacing` (4 sizes), `Color` (11 SIMD4 swatches), `Weight`/`TextFont`/`Alignment` enums.
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardFontLoader.swift` — resolves Epilogue TTF from bundle `Fonts/` directory; falls back to system sans-serif; `OSAllocatedUnfairLock` cache; `resetCacheForTesting()` for test isolation.
- `PhospheneEngine/Sources/Renderer/Dashboard/DashboardTextLayer.swift` — zero-copy `MTLBuffer` → `CGContext` → `MTLTexture` text renderer; `.bgra8Unorm` pixel format; Core Text with permanent CTM flip; `beginFrame()` clears each frame.
- `PhospheneEngine/Sources/Renderer/Resources/Fonts/README.md` — custom TTF drop-in instructions.

New tests (12):
- `DashboardTokensTests` (4) — color channel ranges, type scale ordering, alignment enum, spacing values.
- `DashboardFontLoaderTests` (3) — system fallback, idempotent caching, test reset.
- `DashboardTextLayerTests` (5) — mono text coverage, prose text coverage, between-frame clear, alignment shift, color application.

Also fixed (pre-existing blockers):
- `LiveAdapter.swift`: added `nonisolated(unsafe)` to `lastOverrideTimePerTrack` (Swift 6.3.1 requirement for mutable stored properties on `@unchecked Sendable` classes).
- `ReactiveOrchestratorTests`: updated Test 5 to expect a hold (not a switch) at gap=0.030 < `minBoundaryScoreGap(0.05)`; added `mediumGapCatalog()` for Test 6 with gap≈0.060 > 0.05.

**Test suite:** 1096 engine tests; 2 pre-existing timing flakes (MetadataPreFetcher, AppleMusicConnectionViewModel). App build: `** BUILD SUCCEEDED **`. SwiftLint: 0 violations.

**No behaviour change to existing presets or sessions.** `DashboardTextLayer` is not yet wired into the render pipeline; wiring lands in DASH.6.

**Decision:** D-081 (font strategy, zero-copy pattern, SC retention, pixel-coverage calibration).

---

## [dev-2026-05-06-f] DASH.1.1 — Tokens aligned to `.impeccable.md` OKLCH spec

**Increment:** DASH.1.1
**Type:** Design-system alignment (shared tokens)

**What changed.**

The DASH.1 token placeholders are replaced with values derived from the `.impeccable.md` OKLCH palette, before DASH.2/3/4 cards reach for them.

- Brand: `purple`, `coral`, `teal` re-tuned from sRGB approximations to OKLCH-derived values; `purpleGlow`, `coralMuted`, `tealMuted` added.
- Surfaces: `bg`, `surface`, `surfaceRaised`, `border` added (4-step ladder, hue 275–278). Replaces the flat `chromeBg`/`chromeBorder`.
- Text: renamed and re-tuned. `textPrimary` → `textHeading` `oklch(0.94 0.008 278)`, `textSecondary` → `textBody` `oklch(0.80 0.010 278)`, `textMuted` re-tuned to `oklch(0.50 0.014 278)`. All three are tinted toward brand purple (~278°) — no pure white anywhere.
- TypeScale: `bodyLarge = 15` added (spec `md`, body in card content). Existing scale unchanged.
- Status: `statusGreen/Yellow/Red` unchanged — held close to pure for legibility per the "color carries meaning" principle.

Test changes:
- `DashboardTokensTests.colorValues()` rewritten to assert the OKLCH ladder: surface monotonically rising, neutrals tinted toward purple (blue > red), text ladder monotonically rising, heading bright but not pure white.
- `DashboardTextLayerTests` renamed `textPrimary` → `textHeading`, `textSecondary` → `textBody` at all five call sites.

**Test suite:** All 12 dashboard tests pass; SwiftLint 0 violations on touched files; app build clean.

**No behaviour change** — `DashboardTextLayer` is still not wired into the render pipeline (DASH.6).

**Decision:** D-081 amendment in DECISIONS.md.

---

## [dev-2026-05-06-d] DSP.4 — Drums-stem Beat This! diagnostic (third BPM estimator)

**Increment:** DSP.4
**Type:** Diagnostic enhancement (`dsp.beat`)

**What changed.** Added a third BPM estimator — Beat This! run on the isolated drums stem — logged at preparation time alongside the existing MIR (kick-rate IOI) and full-mix Beat This! estimates. No runtime behaviour change.

**Files changed:**
- `PhospheneEngine/Sources/Session/StemCache.swift` — `CachedTrackData.drumsBeatGrid: BeatGrid` (default `.empty`); `StemCache.drumsBeatGrid(for:)` accessor.
- `PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift` — Step 6: feed `stemWaveforms[1]` (drums) into the same `DefaultBeatGridAnalyzer` used for the full mix.
- `PhospheneEngine/Sources/Session/BPMMismatchCheck.swift` — `ThreeWayBPMReading` struct + `detectThreeWayBPMDisagreement` pure function.
- `PhospheneEngine/Sources/Session/SessionPreparer+WiringLogs.swift` — `WIRING: SessionPreparer.drumsBeatGrid` per track; precedence logic: `WARN: BPM 3-way` (preferred, all three present) / `WARN: BPM mismatch` (fallback, drumsBPM zero).
- `PhospheneEngine/Tests/.../Session/BPMMismatchCheckTests.swift` — 7 new 3-way detector tests.
- `PhospheneEngine/Tests/.../Integration/BeatGridIntegrationTests.swift` — 2 new drumsBeatGrid wiring tests.
- `docs/ENGINEERING_PLAN.md`, `docs/RELEASE_NOTES_DEV.md`, `CLAUDE.md` — updated.

**Log lines added per prepared track:**
```
WIRING: SessionPreparer.beatGrid track='...' bpm=118.1 beats=60 isEmpty=false
WIRING: SessionPreparer.drumsBeatGrid track='...' bpm=125.0 beats=60 isEmpty=false
WARN: BPM 3-way track='Love Rehab' mir_bpm=125.0 grid_bpm=118.1 drums_bpm=125.0 mir-grid=5.6% mir-drums=0.0% grid-drums=5.6% (DSP.4: estimators on full-mix vs drums-stem vs kick-rate IOI)
```

**Performance:** one additional Beat This! inference call per prepared track (~415 ms on M-class silicon, absorbed in existing preparation window).

**Next step:** collect 2–3 fresh captures across genres; design fusion logic (OR.4 / DSP.5) when the fan-out pattern is understood.

---

## [dev-2026-05-06-e] BUG-007.2 — Fix prepared-grid horizon exhaustion + lock-hysteresis oscillation

**Increment:** BUG-007.2
**Type:** P2 defect fix (`dsp.beat` / `api-contract` + `algorithm`)

**What changed.** Two independent mechanisms prevented `LiveBeatDriftTracker` from holding `.locked` state in Spotify-prepared sessions. Both fixed.

**Fix A (Mechanism B — horizon exhaustion, 1 line).** `resetStemPipeline(for:)` now calls `cached.beatGrid.offsetBy(0)` instead of using the raw grid. The 30-second Spotify preview produces ~62 beats; `offsetBy(0)` extrapolates the grid to a 300-second horizon at the grid's own BPM. After t ≈ 30 s, `nearestBeat()` continued returning matches instead of nil, so `consecutiveMisses` stopped accumulating and lock held.

**Fix B (Mechanism A — cadence-mismatch oscillation, 1 line).** `lockReleaseMisses` raised from 3 → 7. The BeatDetector sub_bass cooldown (400 ms) vs Money's beat period (487 ms) produces roughly 5 consecutive misses per onset cycle. At threshold 3, lock dropped every 1.2 s; at threshold 7 (7 × 400 ms = 2.8 s), the worst-case gap never reaches the threshold and lock holds. Note: the diagnosis document stated 5; the regression test (`test_lockDoesNotOscillateOnStableInput`) demonstrates that the deterministic adversarial scenario requires ≥ 7 to achieve ≤ 2 oscillations in 60 s.

**Files changed:**
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — `lockReleaseMisses = 7` (was 3); updated doc comment.
- `PhospheneApp/VisualizerEngine+Stems.swift` — `cached.beatGrid.offsetBy(0)` in `resetStemPipeline`.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — tests 16–18: `makeMoneySyntheticGrid` helper + three regression gates.
- `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/LiveDriftLockHysteresisDiagnosticTests.swift` — `test_mechanismB` updated from raw-grid bug-documenter to `offsetBy(0)` fix-verifier; `%s` → `%@` format-string SIGSEGV fix; `test_mechanismA` assertion unchanged.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-007 marked Resolved; verification criteria checked.

**Tests:** 1076 pass (1 pre-existing `MetadataPreFetcher` network-timeout flake). `BUG_007_DIAGNOSIS=1 swift test --filter LiveDriftLockHysteresisDiagnostic` — all 3 pass.

---

## [dev-2026-05-06-c] BUG-008.1 + BUG-008.2 — Diagnose & surface offline-grid vs MIR BPM disagreement

**Increments:** BUG-008.1 (diagnosis), BUG-008.1 follow-up (synthetic-kick test), BUG-008.2 (fix)
**Type:** P2 defect diagnosis + fix (`dsp.beat` / `algorithm`)

**Diagnosed:** The 5.5 % "BPM error" Love Rehab surfaces on the prepared BeatGrid path is **not a Phosphene port bug** and **not a sample-rate plumbing bug**. The vendored PyTorch reference fixture (`love_rehab_reference.json`, generated by the official Beat This! Python implementation on the same audio) reports `bpm_trimmed_mean=118.05`; Phosphene's Swift port reproduces this at 118.10 — within rounding. Three already-committed regression tests pin every layer of the port end-to-end. The disagreement reflects how Beat This! was trained: human tap annotations integrate the whole mix's accent structure, locking to the perceptual beat (118), while the kick-rate IOI estimator locks to the kick interval (125). Neither is mechanically "right." A synthetic-kick follow-up confirmed the model recovers exactly 125.00 BPM on machine-quantized input — so 125 is in the model's output distribution; on Love Rehab specifically it locks to the perceptual beat instead.

**Fixed (BUG-008.2):** Added `BPMMismatchCheck.swift` (pure detector) and wired it into `SessionPreparer+WiringLogs.swift`. After `prepare()` populates the cache, each track's `TrackProfile.bpm` (MIR / DSP.1 trimmed-mean IOI on sub_bass) is compared against `CachedTrackData.beatGrid.bpm` (Beat This! transformer). When the relative delta exceeds 3 %, a `WARN: BPM mismatch track='...' mir_bpm=... grid_bpm=... delta_pct=...% (BUG-008: estimators disagree; prepared grid uses Beat This! value)` line is emitted to `session.log` via the existing `SessionRecorder` and to the unified log via `Logger.warning`. **No runtime behaviour change** — `LiveBeatDriftTracker` continues to consume the offline grid. The 3 % threshold is intentionally generous: Money 7/4 (1.4 %) and Pyramid Song 16/8 (2.86 %) fall within and do NOT warn; Love Rehab (5.5 %) firmly does. Side finding from the synthetic-kick test: Beat This! returns 117.97 on a 120 BPM input (-1.7 %) and 130.09 on 130 BPM (+0.07 %) — small tempo-specific artifacts unrelated to BUG-008, documented in the diagnosis writeup.

**New tests:**
- `Tests/Diagnostics/BeatGridAccuracyDiagnosticTests.swift` (BUG-008.1) — 4 cases: port-fidelity tripwire on `love_rehab.m4a` against the PyTorch reference fixture; parametrized synthetic-kick recovery at 120/125/130 BPM.
- `Tests/Session/BPMMismatchCheckTests.swift` (BUG-008.2) — 7 pure-function cases: agreement/disagreement at default threshold, zero/non-finite guards, exact-tie boundary, custom threshold override, symmetric `delta_pct` normalization.
- `Tests/Integration/BeatGridIntegrationTests.swift` extended with `bpmMismatch_wiring_doesNotCrash_andGridReachesCache` — integration smoke using a `FixedBPMBeatGridAnalyzer` stub; verifies the wiring runs end-to-end and reaches the detector with both BPMs non-zero.

**Files added:**
- `PhospheneEngine/Sources/Session/BPMMismatchCheck.swift` — pure detector function + `BPMMismatchWarning` struct.
- `PhospheneEngine/Sources/Session/SessionPreparer+WiringLogs.swift` — extracted from `SessionPreparer.swift` (the file would otherwise breach the 400-line SwiftLint gate). Holds the existing BUG-006.1 `WIRING:` per-track summary plus the new BUG-008.2 BPM-mismatch warning.
- `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/BeatGridAccuracyDiagnosticTests.swift`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Session/BPMMismatchCheckTests.swift`.
- `docs/diagnostics/BUG-008-diagnosis.md` — full diagnosis writeup with all three checks (determinism / sample-rate plumbing / independent ground truth) settled by existing artifacts, plus the synthetic-kick follow-up section with results table.

**Files changed:**
- `PhospheneEngine/Sources/Session/SessionPreparer.swift` — extension moved to `+WiringLogs`; `sessionRecorder` visibility relaxed from `private` to `internal` so the new extension file can access it.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/BeatGridIntegrationTests.swift` — `FixedBPMBeatGridAnalyzer` stub + wiring smoke test added.
- `docs/QUALITY/KNOWN_ISSUES.md` — BUG-008 entry rewritten with the diagnosis result, fix description, and softened "estimators disagree" framing (replaces the original "true 125 BPM" framing, which the diagnosis cannot prove).

**Tests:** Engine suite green except the two documented baseline flakes (`MetadataPreFetcher.fetch_networkTimeout`, `SessionManagerCancel`/`ProgressiveReadiness` `@MainActor` timing under parallel execution — both pass in isolation). xcodebuild clean. SwiftLint baseline preserved on touched files (zero new violations).

**Manual validation:** Not gated on a fresh capture — the existing `2026-05-06T20-11-46Z` capture already contains the data that would trigger the WARN on Love Rehab. A future Spotify-prepared session will surface the new line in `session.log`. Live drift behaviour is unchanged from BUG-007's state — that is the intended scope.

**Known issues introduced:** None.
**Known issues resolved:** BUG-008 — disagreement is now surfaced; underlying upstream-model behaviour unchanged by design. BUG-007 (drift-tracker lock-hysteresis) remains open and continues to block the user-visible PLANNED · LOCKED criterion.

**Related:** BUG-008, BUG-006.2 (exposed the latent disagreement end-to-end), BUG-007 (independent — drift-tracker symptom is not addressed by this fix), DSP.2 S5 (introduced offline BeatGrid resolver), Failed Approach #52 (sample-rate plumbing — explicitly ruled out by BUG-008.1 diagnosis).

---

## [dev-2026-05-06-b] BUG-006.2 — Prepared-BeatGrid wiring fix

**Increments:** BUG-006.1 (instrumentation, prior commit), BUG-006.2 (fix)
**Type:** P1 defect fix (`dsp.beat` / `pipeline-wiring`)

**Fixed:**
- **Cause 1 — engine.stemCache never assigned.** `VisualizerEngine.swift:171` declared `var stemCache: StemCache?` but no code in the codebase ever assigned to it. Every `resetStemPipeline(for:)` call therefore took the cache-miss branch and the prepared `BeatGrid` never installed. Now wired in `init` to `sessionManager.cache` (the same `StemCache` instance `SessionPreparer` populates) — entries become visible by reference as preparation completes.
- **Cause 2 — Track-change handler built a partial `TrackIdentity`.** `VisualizerEngine+Capture.swift:129` constructed `TrackIdentity(title:, artist:)` only — duration, catalog IDs, and `spotifyPreviewURL` left nil. `Hashable` therefore mismatched the keys `SessionPreparer` stored from full Spotify-API identities. Now resolves the canonical identity from `livePlan` via the new `PlannedSession.canonicalIdentity(matchingTitle:artist:)` helper. Falls back to the partial identity for ad-hoc/reactive sessions and ambiguous matches.

**New tests:**
- `Tests/Integration/PreparedBeatGridAppLayerWiringTests.swift` (6 cases) — closes the BUG-003 coverage gap that allowed BUG-006 to ship. Tests cover `engineStemCache_isWiredAfterSessionPrepare`, `trackChangeIdentity_matchesPlannedIdentity`, `ambiguousMatch_returnsNil_partialFallback`, `noMatch_returnsNil`, `endToEndProduces_preparedCacheInstall`, `partialIdentity_withoutCanonicalResolution_missesCache` (negative control pinning the regression direction).

**Files added:**
- `PhospheneApp/VisualizerEngine+TrackIdentityResolution.swift` — `canonicalTrackIdentity(matching:)` instance method delegating to the Orchestrator-module pure helper.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/PreparedBeatGridAppLayerWiringTests.swift`.

**Files changed:**
- `PhospheneApp/VisualizerEngine.swift` — assigns `self.stemCache = self.sessionManager.cache` after `makeSessionManager`.
- `PhospheneApp/VisualizerEngine+Capture.swift` — track-change handler resolves canonical identity before `resetStemPipeline`.
- `PhospheneApp/VisualizerEngine+WiringLogs.swift` — `logTrackChangeObserved` now reports `resolution=fromLivePlan|partialFallback`.
- `PhospheneEngine/Sources/Orchestrator/PlannedSession.swift` — `canonicalIdentity(matchingTitle:artist:)` pure-function helper added.
- `PhospheneApp.xcodeproj/project.pbxproj` — registered `VisualizerEngine+TrackIdentityResolution.swift` (N10007 / N20007).

**Tests:** 1051 engine tests / 116 suites. Pass except the two documented baseline flakes (`MetadataPreFetcher.fetch_networkTimeout`, `MemoryReporter.residentBytes growth`). App build clean. SwiftLint baseline preserved on touched files (zero new violations).

**Manual validation:** Pending the next live Spotify capture. The BUG-006.1 `WIRING:` instrumentation logs will surface end-to-end behaviour in `session.log`. Verification criteria from the BUG-006 entry remain unchecked until a live session is captured (SpectralCartograph mode label, drift readout settling, `grid_bpm` column in `features.csv`).

**Known issues introduced:** None.
**Known issues resolved:** BUG-006 (code-only — manual sign-off pending). BUG-003's first verification criterion checked off (`PreparedBeatGridAppLayerWiringTests`); LiveDriftValidationTests still pending.

**Related:** BUG-006, BUG-003, BUG-006.1, DSP.3.6, D-070 (`TrackIdentity.spotifyPreviewURL` excluded from `Hashable`).

---

## [dev-2026-05-06-a] BUG-006.1 — Wiring instrumentation

**Increments:** BUG-006.1
**Type:** Instrumentation (no behaviour change)

Source-tagged `WIRING:` log entries added across the prepared-BeatGrid path so a live session capture surfaces the failure mode end-to-end. Optional `SessionRecorder` threaded through `SessionPreparer` and `SessionManager` so logs land in `session.log`. New file `PhospheneApp/VisualizerEngine+WiringLogs.swift` consolidates helpers; `SessionManager+Readiness.swift` extracted to keep `SessionManager.swift` under the SwiftLint 400-line gate. New `caller:` parameter on `resetStemPipeline(for:caller:)` discriminates pre-fire (planner) from track-change paths. Commits `7f95cec0` + `807d3b8c`.

---

## [dev-2026-05-05-c] Quality System Documentation

**Increments:** QS.1
**Type:** Infrastructure / documentation

**New:**
- `docs/QUALITY/DEFECT_TAXONOMY.md` — severity definitions (P0–P3), domain tags, failure classes, and defect process.
- `docs/QUALITY/BUG_REPORT_TEMPLATE.md` — structured template for filing defects with required fields.
- `docs/QUALITY/KNOWN_ISSUES.md` — active issue tracker: 5 open defects (BUG-001 through BUG-005), 5 pre-existing flakes, and 5 recently-resolved P1 defects from DSP.3.x work.
- `docs/QUALITY/RELEASE_CHECKLIST.md` — 10-section pre-release gate covering build, DSP/beat-sync, stem routing, preset fidelity, render pipeline, session/UX, performance, documentation, and git hygiene.
- `docs/RELEASE_NOTES_DEV.md` — this file.

**Changed:**
- `CLAUDE.md` — new `Defect Handling Protocol` section added after `Increment Completion Protocol`.
- `docs/ENGINEERING_PLAN.md` — QS.1 increment added and marked complete.

**Known issues introduced:** None.
**Known issues resolved:** None (documentation only).

---

## [dev-2026-05-05-b] DSP.3.5 + V.7.7A

**Increments:** DSP.3.5, V.7.7A
**Type:** DSP fix + preset architecture

**DSP.3.5 — Halving octave correction + retry:**
- `BeatGrid.halvingOctaveCorrected()` added: halves BPM > 160 recursively, drops every other beat, re-snaps downbeats, recomputes `beatsPerBar`. BPM < 80 unchanged (Pyramid Song guard).
- Live Beat This! retry gate: `liveBeatAnalysisAttempts: Int` (was Bool), max 2 attempts — first at 10 s, retry at 20 s on empty grid.
- `performLiveBeatInference()` extracted for SwiftLint compliance.
- 4 new `BeatGridUnitTests`. **1032 engine tests.**
- Post-validation triage: `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md`.

**V.7.7A — Arachne staged-composition scaffold migration:**
- Arachne migrated from `passes: ["mv_warp"]` to V.ENGINE.1 staged scaffold.
- New fragment functions: `arachne_world_fragment` (placeholder forest backdrop) + `arachne_composite_fragment` (placeholder 12-spoke web overlay).
- Mv-warp helpers removed (incompatible with staged preamble).
- Legacy `arachne_fragment` retained as v5/v7/v9 reference.
- `Arachne.json` updated: `passes: ["staged"]` with two stage definitions.

**Known issues introduced:**
- BUG-002 (PresetVisualReviewTests PNG export broken for staged presets) — pre-existing harness bug exposed by V.7.7A.

**Known issues resolved:**
- BUG-R004 (double-time BPM on 10-second window) — resolved by DSP.3.5 octave correction.

---

## [dev-2026-05-05-a] DSP.3.1–3.4 + V.7.7

**Increments:** DSP.3.1, DSP.3.2, DSP.3.3, DSP.3.4, V.7.7
**Type:** DSP fixes + preset content

**DSP.3.1+3.2 — Diagnostic hold + session-mode signal + pre-fire BeatGrid:**
- `diagnosticPresetLocked` flag, `L` shortcut.
- `SpectralHistoryBuffer[2420]` session-mode slot (0–3).
- SpectralCartograph mode labels: ○ REACTIVE / ◐ PLANNED·UNLOCKED / ◑ PLANNED·LOCKING / ● PLANNED·LOCKED.
- `_buildPlan()` pre-fires BeatGrid.

**DSP.3.3 — Beat sync observability:**
- `SpectralCartographText.draw()` extended with beat-in-bar, drift, phase-offset readouts.
- `textOverlayCallback` now passes `FeatureVector` per frame.
- `[`/`]` developer shortcuts for ±10 ms visual phase calibration.
- `BeatSyncSnapshot` struct (9-field).
- `SessionRecorder.features.csv` gains 9 beat-sync columns.
- `SpectralHistoryBuffer[2421..2429]` downbeat_times + drift_ms slots.
- 31 new tests. **1018 engine tests.**

**DSP.3.4 — Three root causes fixed blocking PLANNED·LOCKED:**
- Bug 1: `BeatGrid.offsetBy` now extrapolates to 300-second horizon.
- Bug 2: `VisualizerEngine.tapSampleRate` stored from audio callback; passed to Beat This!.
- Bug 3: `StemSampleBuffer.snapshotLatest(seconds:sampleRate:)` overload uses actual tap rate.
- 14 new tests. **1028 engine tests.**

**V.7.7 — Arachne WORLD pillar + background dewy webs:**
- Six-layer `drawWorld()` Metal function: sky gradient, distant + near trees, forest floor, atmosphere.
- Snell's-law refractive drops on two background hub webs.
- `ArachneState._tick()` gains `smoothedValence`/`smoothedArousal` (5s low-pass) for mood palette.
- `WebGPU` struct extended with Row 4 `moodData: SIMD4<Float>` (64 → 80 bytes).
- Golden hashes regenerated.

**Known issues resolved:**
- BUG-R001 (BeatGrid finite horizon) — resolved by DSP.3.4.
- BUG-R002 (hardcoded 44100 Hz sample rate) — resolved by DSP.3.4.
- BUG-R003 (StemSampleBuffer undersized at 48000 Hz) — resolved by DSP.3.4.

---

## [dev-2026-05-05] DSP.2 Complete + DSP.3 Audit

**Increments:** DSP.2 S3–S9, DSP.2 hardening, DSP.3 audit
**Type:** DSP — Beat This! transformer + drift tracker

**Summary:** Full Beat This! small0 transformer implemented in Swift/MPSGraph. BeatGrid pipeline end-to-end from Spotify-prepared sessions. Live reactive mode gets Beat This! inference after 10 s of playback. `barPhase01`/`beatsPerBar` propagated to FeatureVector and GPU.

**Bug fixes landed:**
- Four S8 bugs: norm-after-conv shape, transpose-before-reshape, BN1d zero-padding semantics, paired-adjacent RoPE. All individually regression-locked in `BeatThisBugRegressionTests`.
- DSP.3 audit revealed three root causes blocking LOCKED state (fixed in DSP.3.4, see above entry).

**Test suite:** 1028 engine tests / 106 suites at DSP.3.4.

**Known issues introduced:**
- BUG-001 (Money 7/4 stays REACTIVE on live path) — identified during DSP.3.5 post-validation.

---

## [dev-2026-05-04] DSP.2 S1–S2 + DSP.1

**Increments:** DSP.1, DSP.2 S1, DSP.2 S2
**Type:** DSP — tempo estimation rewrite + Beat This! vendoring

**DSP.1 — Sub_bass-only IOI + trimmed-mean BPM:**
- Eliminated band-fusion IOI bias (Failed Approach #50) and histogram-mode bias (Failed Approach #51).
- BPM error dropped from 10–20% to <2% on kick-on-the-beat tracks.
- Reference results: love_rehab 122–126 (true 125), so_what 135–138 (true 136).
- `TempoDumpRunner` CLI + `Scripts/dump_tempo_baselines.sh` + `Scripts/analyze_tempo_baselines.py` shipped as permanent regression infrastructure.

**DSP.2 S1 — Beat This! architecture audit + weight vendoring:**
- `small0` model selected: 2,101,352 params, 8.4 MB FP32, MIT license confirmed.
- 161 weight tensors vendored under Git LFS.
- Six JSON reference fixtures (love_rehab, so_what, there_there, pyramid_song, money, if_i_were_with_her_now).

**DSP.2 S2 — BeatThisPreprocessor Swift port:**
- Mono Float32 → log-mel spectrogram matching Beat This! Python `LogMelSpect` exactly.
- Critical: Slaney mel filterbank with continuous Hz interpolation (integer-bin approach underestimates ~12%).
- Golden match on love_rehab first 10 frames: max|Δ| = 2.9×10⁻⁵.

---

## [dev-2026-05-02] V.7.5, V.7.6.C, V.7.6.D, V.7.6.1, V.7.6.2

**Increments:** V.7.5, V.7.6.C, V.7.6.D, V.7.6.1, V.7.6.2

**V.7.5 — Arachne v5 (composition + warm restoration + drops + spider cleanup):**
- Pool capped 12→4, drops as visual hero (radius 8 px), Marschner TRT-lobe warm rim restored, warm key / cool ambient.
- Spider: dark silhouette, AR gate restored, `subBassThreshold` 0.65→0.30.
- M7 review result: output matches `10_anti_neon_stylized_glow.jpg` anti-reference. `certified` rolled back to false. V.7.6 (atmosphere-as-mist patch) abandoned in favour of compositing-anchored V.7.7+.

**V.7.6.1 — Visual feedback harness:**
- `PresetVisualReviewTests` renders presets at 1920×1280 for three FeatureVector fixtures.
- Contact sheet: render in top half, refs 01/04/05/08 in bottom half.
- Gated behind `RENDER_VISUAL=1`.

**V.7.6.C — maxDuration calibration + diagnostic class:**
- Per-section linger factors inverted to Option B.
- `is_diagnostic` JSON field (→ `maxDuration = .infinity`); SpectralCartograph flagged.

**V.7.6.D — Diagnostic preset orchestrator exclusion:**
- `DefaultPresetScorer` excludes `is_diagnostic` presets categorically.
- `DefaultLiveAdapter` no-ops mood override for diagnostic presets.
- `DefaultReactiveOrchestrator` skips diagnostic presets in ranking.

**Known issues introduced:**
- BUG-004 (all presets `certified: false`) — documented; V.7.10 is the planned resolution path.

---

## [dev-2026-04-25] Milestones A, B, C

**Increments:** U.1–U.11, 4.0–4.6, 5.2–5.3, 6.1–6.3, 7.1–7.2, V.1–V.6, MV-0–MV-3
**Type:** Multi-phase milestone delivery

Milestones A (Trustworthy Playback), B (Tasteful Orchestration), and C (Device-Aware Show Quality) all met on 2026-04-25.

**Highlights:**
- Full session lifecycle (idle → connecting → preparing → ready → playing → ended).
- Apple Music + Spotify OAuth connectors.
- Progressive session readiness (partial-ready CTA).
- Orchestrator: PresetScorer, TransitionPolicy, SessionPlanner, LiveAdapter, ReactiveOrchestrator.
- Frame budget governor + ML dispatch scheduler.
- V.1–V.3 shader utility library (Noise, PBR, Geometry, Volume, Texture, Color, Materials).
- V.6 fidelity rubric + certification pipeline.
- Phase U: permission onboarding, connector picker, preparation UI, playback chrome, settings panel, error taxonomy, toast system, accessibility.
- Beat This! architecture committed (DSP.2 scope).

**Known issues at milestone:**
- All presets uncertified (BUG-004).
- Spotify preview_url null for some tracks (BUG-005).
- Test suite: 4 pre-existing Apple Music environment failures (unchanged).
