# Decisions History

This file holds decisions that have been **superseded by amendments** or **whose increment shipped long ago and is no longer cited by an active decision**. Decisions that remain load-bearing — referenced by code, by another active decision, or by an open follow-up — stay in `docs/DECISIONS.md`.

## Why this file exists

`docs/DECISIONS.md` grew to 122 entries (3,396 lines). Several decision chains involve multiple amendments to the same decision (e.g. the DASH series: DASH.2 → DASH.2.1 → DASH.7 → DASH.7.1 → DASH.7.2; the LM series: LM.3 → LM.3.1 → LM.3.2 → LM.4 → LM.4.1 → LM.4.3 → LM.4.4 → LM.4.5 → LM.4.6 → LM.7). The terminal decision in each chain remains load-bearing; the intermediate amendments are institutional memory worth preserving but should not crowd the active-decisions list.

The cut is:

- **Active:** the decision is currently referenced by code, by another active decision, or by an open follow-up.
- **History:** the decision has been superseded by a newer decision, or its increment shipped and nothing currently references it.

Both lists stay fully searchable via `grep`. The active list becomes scannable.

## Population

This file is populated by **DOC.4** (Decisions refactor). It is empty in DOC.1.

Entries land below this divider preserving their original D-NNN number for cross-reference with git history. A one-line "Superseded by:" or "Shipped in:" header on each entry records why it moved.

---

<!-- Entries land here. Format mirrors docs/DECISIONS.md: ## D-NNN header + body. -->

## D-086 — Dashboard composer + single-`D` toggle + per-path composite call sites (Phase DASH.6)

**Status:** Superseded by D-087 (DASH.7 SwiftUI dashboard port). Moved to history 2026-05-13 (DOC.4). The composer-and-Metal-cards architecture this decision documents was retired when D-087 ported the dashboard to SwiftUI.

DASH.3 + DASH.4 + DASH.5 produced three pure builders + a snapshot type. DASH.6 wires them live: a `DashboardComposer` owns layer + builders + composite pipeline state, the existing `D` shortcut drives both the SwiftUI debug overlay and the new Metal cards, and the composite is encoded at the tail of every render path immediately before `commandBuffer.present(drawable)`.

### Decision 1 — `DashboardComposer` class, not free functions on `RenderPipeline`

The composer's lifecycle is cohesive: it owns one `DashboardTextLayer` (the shared MTLBuffer-backed bgra8 canvas), three builder structs, one `MTLRenderPipelineState` (alpha-blended), an `enabled: Bool`, drawable-size state for placement, and the bytewise snapshot-equality cache. Spreading those across free functions on `RenderPipeline` would require multiple parallel `NSLock`s and seven new public-ish entry points; encapsulating in one class makes the `D` toggle a single property change with no fan-out. `RenderPipeline` holds only a weak read via the `setDashboardComposer(_:)` setter; strong ownership lives on `VisualizerEngine`. Pattern mirrors `DynamicTextOverlay` / `RayMarchPipeline`.

### Decision 2 — Decision B (per-path composite call sites) over Decision A (render-loop refactor)

The DASH.6 spec offered two structural choices: (A) centralize commit at the end of `renderFrame` so the dashboard composite always lands on the same command buffer as the preset draw — and (B) add the composite call at the tail of each draw path that currently calls `commandBuffer.present(drawable)` individually. Audit showed `commit()` is already centralized in `draw(in:)`; what is per-path is `present(drawable)`. Centralizing `present` would require moving 10 `commandBuffer.present(drawable)` lines out of 8 draw paths and threading the drawable back to `draw(in:)` (or capturing it once at the top and threading down) — well beyond the spec's ~30-line ceiling for Decision A. Decision B chosen: a single helper `RenderPipeline.compositeDashboard(commandBuffer:view:)` is added (snapshots the composer under lock, calls `composite` if non-nil) and 10 sites × 1 line of insertion immediately before each `present`. Total impact: ~30 lines including the helper, well under the ceiling. Render-loop refactor (Decision A flavour) deferred to a future increment if multiple consumers want a shared `pre-present` hook.

### Decision 3 — Single `D` shortcut drives BOTH the SwiftUI overlay and the dashboard composer

One cognitive model, no per-surface UX. Cards (top-right Metal, "instruments") and `DebugOverlayView` (bottom-leading SwiftUI, "raw diagnostics") are complementary surfaces, not alternatives. The user reaching for `D` wants either both or neither — splitting the toggle would force them to learn which surface answers which question. `PlaybackView`'s existing `onToggleDebug` closure flips `showDebug` (SwiftUI overlay visibility) and now also writes `engine.dashboardEnabled = showDebug` (Metal cards). `DebugOverlayView` is deduplicated of metrics that the cards now show (Tempo, standalone QUALITY, standalone ML); the rest (MOOD V/A, Key, SIGNAL block, MIR diag, SPIDER, G-buffer, REC) remain because the cards do not show them.

### Decision 4 — No `Equatable` on `StemFeatures` or `BeatSyncSnapshot`

The composer's rebuild-skip path needs to check whether the previous frame's snapshots match the current frame's — but `StemFeatures` is a `@frozen` GPU-shared SIMD-aligned struct (broadening conformance is a separate decision per D-085) and `BeatSyncSnapshot` is a Sendable instrumentation value type (doesn't otherwise warrant an Equatable conformance for engine code). Adding Equatable to either would broaden public API beyond what one internal cache needs. The composer instead implements a private generic `bytewiseEqual<T>` using `withUnsafeBytes` + `memcmp`. `PerfSnapshot` already conforms to `Equatable` (D-085) and uses the synthesized `==`. Test (b) regression-locks the rebuild-skip behaviour against equal snapshots.

### Decision 5 — Premultiplied alpha discipline in the composite pipeline

The layer's CGContext is configured with `kCGBitmapByteOrder32Little | premultipliedFirst`, so glyph + chrome pixels arrive in the texture as premultiplied sRGB. The composite pipeline state therefore configures blending as `src = .one`, `dst = .oneMinusSourceAlpha` (rather than `.sourceAlpha` / `.oneMinusSourceAlpha`). Using `.sourceAlpha` would double-multiply the source RGB by its own alpha and produce a visible black halo at card edges where chrome alpha drops. Verified by reading `DashboardTextLayer.makeResources` before finalizing the descriptor.

### Decision 6 — Per-frame snapshot rebuild cost is acceptable (CGContext text drawing on M-series is sub-millisecond)

The DASH.5 prompt allowed builder-level computation per frame because the alternative (caching layouts at preset-switch time and patching individual rows on update) is much more code for a sub-1% perf win. DASH.6 keeps the same model: `update()` rebuilds all three layouts and repaints the entire layer when any snapshot differs from the previous frame. Steady-state BAR sustain (no snapshot change) hits the bytewise-equality fast path and skips repaint entirely. Engine soak data + on-device measurement remain follow-ups, but the test suite (1130 engine tests, 130 suites) showed no measurable build-time regression from the per-frame rebuild path.

### Decision 7 — DASH.6.1 amendment slot for any per-card position / margin / order / colour tuning

Live D-toggle review on real music is the acceptance artifact (no static PNG). If Matt's eyeball flags any per-card visual issue (chrome misplaced, cards stacked outside the drawable, spacing wrong, top-right margin off, font fallback ugly), DASH.6.1 is the amendment slot. The DASH.6 closeout is the structural delivery (composer + wiring + dedup + tests + docs); v1 visual tuning lives in 6.1. Same pattern as DASH.4.1 / DASH.5.1.

### Tests

After DASH.6: **45 dashboard tests pass** (12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3 progress-bar + 6 StemsCardBuilder + 6 PerfCardBuilder + 6 DashboardComposer). Full engine suite green: 1130 tests / 130 suites. 0 SwiftLint violations on touched files; xcodebuild app build clean.

### Files changed

New: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardComposer.swift`, `PhospheneEngine/Sources/Renderer/Shaders/Dashboard.metal`, `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardComposerTests.swift`. Edited: `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift` (`Spacing.cardGap`), `PhospheneEngine/Sources/Renderer/RenderPipeline.swift` (composer setter + `hasDashboardComposer` + `compositeDashboard` helper + resize forward), every `RenderPipeline+*.swift` draw-path file (composite call before each `present`), `PhospheneApp/VisualizerEngine.swift` (composer property + `dashboardEnabled`), `PhospheneApp/VisualizerEngine+InitHelpers.swift` (composer alloc + `assemblePerfSnapshot` + per-frame snapshot push wired onto `onFrameRendered`), `PhospheneApp/Views/Playback/PlaybackView.swift` (`D` toggle writes `engine.dashboardEnabled`), `PhospheneApp/Views/DebugOverlayView.swift` (Tempo / QUALITY / ML rows removed).

## D-013: Spotify Audio Features endpoint dropped

> **Moved to history (DOC.4, 2026-06-11).** Shipped; records the 2024 deprecation of a dead Spotify endpoint — the dead-API fact lives in `docs/HISTORICAL_DEAD_ENDS.md` #10. Not cited by code, CLAUDE.md, or an active decision.

**Status:** Accepted

Spotify is search-only for track matching. The Audio Features endpoint was deprecated for new apps (Nov 2024, returns 403).

**Reason:** External constraint. Soundcharts is the commercial replacement for audio feature data. Self-computed MIR is the authoritative source.

---


## D-031: Preset metadata schema extended for Orchestrator scoring (Increment 4.0)

> **Moved to history (DOC.4, 2026-06-11).** Shipped in Increment 4.0; the descriptor schema has since evolved through D-080 / D-123-era extensions which are the live authorities. Not cited by code, CLAUDE.md, or an active decision.

**Status:** Accepted (2026-04-20)

Seven new fields were added to `PresetDescriptor` to give the Orchestrator (Increment 4.1) the signal it needs to make tasteful preset-selection decisions without hard-coding per-preset logic in scoring rules.

**New fields:** `visual_density`, `motion_intensity`, `color_temperature_range`, `fatigue_risk`, `transition_affordances`, `section_suitability`, `complexity_cost`.

**Why pulled forward from Phase 5.1:** The original engineering plan placed the enriched metadata schema in Phase 5.1 (Orchestrator polish) on the assumption that PresetScorer (Increment 4.1) could be prototyped against a minimal schema and extended later. In practice, building PresetScorer without the fields it scores on forces either placeholder logic or a breaking schema change immediately after. Pulling the schema forward costs a small amount of effort (back-filling 11 JSON sidecars) and eliminates the breaking change.

**Decoding contract:** Missing field → default. Malformed `fatigue_risk` string → log warning via `Logging.renderer`, use `.medium`, do not throw. This matches the existing `synthesizePasses` fallback philosophy. `complexity_cost` accepts both scalar (applied to both tiers) and nested `{"tier1": x, "tier2": y}` forms.

**Why these specific fields:**
- `visual_density` + `motion_intensity`: direct proxies for the two axes of arousal that the MoodClassifier already tracks. The Orchestrator can intersect descriptor ranges with mood targets.
- `color_temperature_range`: bridges mood-derived valence (warm/cool palette bias) to preset capability. Allows scoring without inspecting shader source.
- `fatigue_risk`: encodes the subjective reviewer observation that some presets (high-contrast, strobing) become uncomfortable over extended viewing. A cooldown penalty enforces variety.
- `transition_affordances`: hard cuts work beautifully for GlassBrutalist (stark) and VolumetricLithograph (linocut) but would feel jarring on particle or plasma presets. Encoding this prevents the Orchestrator from scheduling inappropriate transitions.
- `section_suitability`: structural section matching (ambient/buildup/peak/bridge/comedown) is the highest-leverage hook for making visual choices feel intentional rather than random.
- `complexity_cost`: tier1/tier2 device tiers reflect the M1/M2 vs M3+ performance gap for ray march presets. Excludes frame-budget breakers at scoring time rather than at runtime.

**New types:** `FatigueRisk`, `TransitionAffordance`, `SongSection` (all `String`-raw, `Codable`, `Sendable`, `Hashable`, `CaseIterable`), `ComplexityCost` (struct with custom dual-form Codable). Defined in `PresetMetadata.swift`.

**Back-fill note:** 11 JSON sidecars were back-filled. KineticSculpture's `color_temperature_range` was adjusted from spec `[0.3, 0.7]` (identical to the default) to `[0.3, 0.65]` to make the back-fill detectable by the regression test and to better reflect the slightly cooler warm-end of its metallic/glass palette.

---


## D-046 — Connector picker architecture decisions (Increment U.3)

> **Moved to history (DOC.4, 2026-06-11).** Shipped in Increment U.4; the connector picker is in production and its Decision 4 (`.spotifyAuthRequired` silent degrade) was explicitly superseded by D-068 (U.10). Not cited by code, CLAUDE.md, or an active decision.

**Status:** Accepted (2026-04-23)

**Decision 1: `nonisolated(unsafe)` for NSWorkspace observer storage in `@MainActor` classes.**

`@MainActor` classes have `deinit` that is nonisolated (Swift 6 requirement). `NSWorkspace.notificationCenter.removeObserver(_:)` must be called from `deinit`. If the observer handles (`Any?`) are stored as regular `@MainActor`-isolated properties, accessing them from `deinit` produces a Swift 6 concurrency error. The correct pattern is `nonisolated(unsafe) private var observer: Any?` — these properties are only written in `init` and read in `deinit`, so no concurrent access is possible. `@unchecked Sendable` on a wrapper class would also work but adds unnecessary indirection. Use `nonisolated(unsafe)` for any `@MainActor` class that must remove NSWorkspace / NotificationCenter observers from `deinit`.

**Decision 2: `ConnectorPickerView` as a `.sheet` with internal `NavigationStack`.**

The app's top-level content model is a pure enum switch — there is no `NavigationStack` at the root. The connector picker needs push navigation (picker → Apple Music flow / Spotify flow). Solution: present `ConnectorPickerView` as a `.sheet` from `IdleView`, and embed the `NavigationStack` inside the sheet. This keeps the app's flat state-machine routing intact while enabling connector-specific push flows. Do not add a `NavigationStack` to `ContentView` — it would pollute all six session-state views.

**Decision 3: `DelayProviding` protocol for testable retry loops.**

The Spotify rate-limit retry ([2s, 5s, 15s]) and Apple Music auto-retry (2s) use wall-clock delays. Injecting a `DelayProviding` protocol with `RealDelay` (production) and `InstantDelay` (tests, uses `await Task.yield()`) allows retry paths to be exercised in fast unit tests without wall-clock waits. `Task.yield()` is the correct implementation for `InstantDelay` — it suspends and resumes the current task, giving other tasks (including test observations) a chance to run, without introducing any real-time delay. An empty `async throws {}` body would not yield the actor and retry loops would spin synchronously.

**Decision 4: `.spotifyAuthRequired` silently degrades to `startSession`.** *(Superseded by D-068, Increment U.10 — do not follow this pattern.)*

Without OAuth (deferred to v2), `PlaylistConnector.connect()` immediately throws `.spotifyAuthRequired` (empty access token check). Rather than showing an error, the ViewModel calls `startSession(.spotifyPlaylistURL(url, accessToken: ""))` directly. `SessionManager` degrades gracefully: it starts a session with an empty plan and enters live-only reactive mode. This is a valid and useful state — the user gets responsive real-time visuals while the Orchestrator uses the reactive path. An error message here would lie: the session IS starting, just without pre-analyzed stems. User-visible error copy would be `UX_SPEC §8` compliant only if the session actually fails to start.

---


## D-120 — Phase MD property taxonomy: concept_tags + motion_paradigm (Strategy Addendum follow-up, filed 2026-05-12)

> **Moved to history (DOC.4, 2026-06-11).** REVERTED in commit `0981ca4f` within 24 h of filing (the schema landed without a demonstrated orchestrator consumer; Matt rejected the premise). The durable lessons are CLAUDE.md Failed Approaches #59 and #60, which remain active; cross-references to D-120 resolve here.

> **⚠ STATUS: REVERTED 2026-05-13** (commit `0981ca4f`). The schema addition (`concept_tags` + `motion_paradigm` fields on `PresetDescriptor`) + retroactive tagging pass across all 15 production presets landed across six commits before Matt's product framing rejected the premise — penalty-based diversity at additional axes pushes the planner toward worse-fitting picks. See Failed Approach #59 in `CLAUDE.md` for the post-mortem and memory note `feedback_multi_preset_per_song.md` for Matt's product framing. The text below is preserved for the historical record; the decision is no longer in force.

**Rule.** Every Phosphene preset's JSON sidecar declares two metadata fields beyond `family`:

1. **`concept_tags: [String]`** — array of visual-concept tags drawn from a controlled vocabulary mirroring the cream-of-crop pack's themes (per `docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md` §0.5) extended with Phosphene-native registers. Vocabulary (extends as needed; reuse over invention):

   `fractal`, `geometric`, `waveform`, `reaction_diffusion`, `dancer`, `drawing`, `sparkle`, `particles`, `supernova`, `hypnotic`, `kaleidoscope`, `aurora`, `cavern`, `web`, `terrain`, `nebula`, `plasma`, `glass`, `mosaic`, …

   A preset may declare multiple tags where its visual register sits at an intersection (e.g. `["supernova", "particles"]` for a particle-nova). Empty array is allowed for genuinely uncategorisable diagnostic presets.

2. **`motion_paradigm: String`** — one of the D-029 motion-source paradigms enumerated in [`docs/MILKDROP_ARCHITECTURE.md`](MILKDROP_ARCHITECTURE.md) §4:

   `feedback_warp` | `particles` | `camera_flight` | `mesh_animation` | `direct_time_modulation` | `mv_warp` | `ray_march_static` | `staged_composition`

   Single value (D-029 says paradigms are alternatives, not composable; tier-collapse semantics from D-103 amendment do not change this — a preset that combines `ray_march_static` + `mv_warp` on top is still a single composed paradigm at the orchestrator-scheduling level, recorded as `staged_composition` or `ray_march_static` per the dominant motion source).

**Applies to all Phosphene presets**, not just Milkdrop-inspired. Existing catalog members get retroactively tagged in a one-time pass (documented per-preset rationale; small task — 15 presets × 2 fields × 30 sec lookup ≈ 15 min).

**Why.** Three things at once:

1. **Restores orchestrator scheduling information lost by D-103 tier collapse.** All 200 future inspired-by uplifts ship as `family: "milkdrop_inspired"`; the family-repeat penalty (Phase 4) treats them as a single bucket. Concept-repeat and paradigm-repeat penalties give the orchestrator multi-axis diversity scheduling (a session selecting two `concept_tags: ["fractal"]` presets in a row gets the same cool-down regardless of family).
2. **Generalises to non-Milkdrop presets.** The taxonomy applies to Aurora Veil / Crystalline Cavern / the Phase G-uplift catalog members too — orchestrator gains diversity scheduling across the whole catalog, not just Milkdrop-inspired subset.
3. **Mirrors the cream-of-crop pack's existing taxonomy.** Inspired-by authors opening a source `.milk` already know what theme it sits in; the same taxonomy carries through to the Phosphene preset's tags. Removes a translation step.

Matt's framing per 2026-05-12: *"tag or categorize them according to the Milkdrop Architecture document — by what the preset does or its underlying concept / technology. This is a property taxonomy."* `concept_tags` captures "what the preset does"; `motion_paradigm` captures "underlying concept / technology" per `MILKDROP_ARCHITECTURE.md` §3 / §4.

**Why NOT a `fidelity: close/loose/divergent` field** (rejected from the adversarial review): (a) speculative axis with no empirical grounding; (b) doesn't generalise outside Milkdrop-inspired subset; (c) the substantial-similarity discipline rule (D-116 / D-121) already governs the fidelity question at authoring time, so a per-preset fidelity tag is descriptive metadata at best — not useful for orchestrator scheduling. The property taxonomy in D-120 is a better axis on all three counts.

**Carry-forward.**

- **JSON schema.** `PresetDescriptor` Codable extension to read the two new fields, both with sensible defaults (empty array for `concept_tags`; `motion_paradigm` inferred from existing render-pass declaration if absent, with explicit override available).
- **Existing-preset retroactive tagging pass.** One-time increment, documented per-preset; lands alongside the first inspired-by uplift or earlier as a standalone tagging session.
- **Phase 4 orchestrator wiring.** `PresetScoringContext` extended with concept-repeat + paradigm-repeat history; scoring weights TBD when wiring lands. Naturally additive to existing family-repeat infrastructure.
- **No new `PresetCategory` Swift enum cases.** `family` stays as-is (the original 14 cases + the future `.milkdropInspired`); `concept_tags` + `motion_paradigm` are JSON-side metadata, not Swift enum.

---

