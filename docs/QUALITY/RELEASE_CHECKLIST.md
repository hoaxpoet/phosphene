# Phosphene — Release Checklist

Run this checklist before tagging a local release or before asking Matt to review a session's output. "Release" in this context means: the code is in a state where Matt would reasonably run the app and judge it as representative of the project's current quality.

Not every increment requires a full release check. Infrastructure, test, and documentation increments may skip sections marked **[preset-facing only]** or **[UX-facing only]**.

---

## 1. Build Gate

- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` — zero errors, zero warnings treated as errors.
- [ ] `swift test --package-path PhospheneEngine` — passes. Pre-existing flakes (see `KNOWN_ISSUES.md`) are called out by name; no new failures.
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test` — passes. App test suite green.
- [ ] `swiftlint lint --strict --config .swiftlint.yml` — zero violations in active source paths. (`swiftlint` autocorrect is not acceptable as a substitute.)

**Stop condition:** Any new test failure or SwiftLint violation blocks the release. Investigate and fix before continuing.

---

## 2. Known Issues Review

- [ ] Open `docs/QUALITY/KNOWN_ISSUES.md`. Confirm no P0 defects are open.
- [ ] For any P1 defects resolved in this session, verify the `Resolved` field is filled in and `RELEASE_NOTES_DEV.md` is updated.
- [ ] New defects discovered during this session are filed in `KNOWN_ISSUES.md` with at minimum: severity, domain tag, expected behavior, actual behavior, and reproduction steps.

---

## 3. DSP / Beat Sync Verification  *(required when any DSP, BeatGrid, or drift-tracker code changed)*

- [ ] Run `swift test --filter BeatDetectorTests BeatGridUnitTests LiveBeatDriftTrackerTests BeatThisLayerMatchTests`. All pass.
- [ ] Play Love Rehab (Chaim) on a Spotify-prepared session. Confirm SpectralCartograph shows `● PLANNED · LOCKED` within 10 seconds. `grid_bpm` in `features.csv` is within ±2 of 125.
- [ ] Manual: beats align to perceived kick drum at normal listening volume. No double-time or half-time artefacts.
- [ ] If Pyramid Song was reachable: confirm `grid_bpm` ≈ 68 and is NOT halved further (BPM < 80 guard respected).

**Artifact to retain:** `features.csv` from the Love Rehab verification session, archived to `docs/diagnostics/` if the DSP change is significant.

---

## 4. Stem Routing Verification  *(required when StemAnalyzer, StemFeatures, or stem routing code changed)*

- [ ] `swift test --filter StemAnalyzerMV3Tests MIRPipelineDriftIntegrationTests`. All pass.
- [ ] Run `SessionRecorder`-enabled session on Love Rehab. Confirm `stems.csv` shows non-constant `drumsBeat` values across 500+ frames (more than 25 unique values — prior to per-frame stem fix, only 25/8987 were unique).
- [ ] Manual: visual response (e.g., Stalker gait, Arachne quiver, VolumetricLithograph terrain) responds to musical onsets, not silently frozen.

---

## 5. Preset Fidelity Review  **[preset-facing only]** *(required when any .metal shader, JSON sidecar, or preamble changed)*

- [ ] `swift test --filter PresetRegressionTests` — all golden hashes match. If hashes changed, explain why in the commit message and update the golden values.
- [ ] `swift test --filter PresetAcceptanceTests` — all 44 invariant tests pass (non-black at silence, no white clip, beat response ≤ 2× continuous, form complexity ≥ 2).
- [ ] `swift test --filter FidelityRubricTests` — rubric scores for touched presets are as expected.
- [ ] **[if RENDER_VISUAL=1 supported for the preset]** Run `RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests`. Review contact sheet against `docs/VISUAL_REFERENCES/<preset>/` reference images. Note any anti-references matched (see Failed Approach #48).
- [ ] For any preset with new content: M7 review scheduled with Matt before `certified: true` is set.

**Stop condition for certification:** Do NOT flip `certified: true` in a JSON sidecar without Matt's explicit M7 approval.

---

## 6. Render Pipeline Verification  *(required when renderer, shader infrastructure, or GPU contract changed)*

- [ ] `swift test --filter RenderPipelineTests MetalContextTests ShaderLibraryTests`. All pass.
- [ ] `swift test --filter FrameBudgetManagerTests MLDispatchSchedulerTests`. All pass.
- [ ] Open the app on a Tier 1 device (M1/M2) if available. Confirm no quality level below `noSSGI` at 60 fps on any production preset.
- [ ] Check `DebugOverlayView` (press `D`) — frame time reported, quality level shown, ML dispatch not stuck in DEFER for > 5 s.

---

## 7. Session / UX Verification  **[UX-facing only]** *(required when SessionManager, SessionPreparer, ViewModels, or Views changed)*

- [ ] App launches to `IdleView`. No crash.
- [ ] Apple Music connector: connect a playlist with ≥ 3 tracks. Preparation progresses normally. "Start now" CTA appears at `readyForFirstTracks`.
- [ ] Spotify connector: paste a valid Spotify playlist URL. Tracks appear, preparation starts, first 3 tracks reach `.ready`. Preview clips play in `PreparationProgressView` preview (if applicable).
- [ ] `.playing` state: full-bleed Metal + preset badge visible. No pause/play controls. `D` key shows debug overlay. `Space` key shows/hides chrome. `L` key toggles diagnostic hold (SpectralCartograph only).
- [ ] `.ended` state: session summary shown. "New session" CTA works.

---

## 8. Performance Verification  *(required monthly or when render loop, ML dispatch, or resource management changed)*

- [ ] `SOAK_TESTS=1 swift test --filter SoakTestHarnessTests` — 2-minute soak passes. Memory footprint stable (no monotonic growth). No `droppedFrames` count > 5 in the report.
- [ ] `swift test --filter DSPPerformanceTests RenderLoopPerformanceTests` — no regressions.
- [ ] Alternatively: run `Scripts/run_soak_test.sh` for a 2-hour full soak. Review `~/Documents/phosphene_soak_reports/<timestamp>/report.md`.

---

## 9. Documentation and Registry

- [ ] `docs/ENGINEERING_PLAN.md` — all completed increments have ✅ and completion dates. No incomplete items marked complete.
- [ ] `docs/QUALITY/KNOWN_ISSUES.md` — resolved defects have `Resolved` field filled. New defects from this session are filed.
- [ ] `docs/RELEASE_NOTES_DEV.md` — entry added for the current release (or updated for the current increment batch).
- [ ] `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` — updated if any renderer, shader infrastructure, or preset architecture capability changed.
- [ ] `CLAUDE.md` Module Map — reflects actual file structure. No references to files that no longer exist.

---

## 10. Git Status

- [ ] `git status` — no untracked files that belong to the increment. No staged files outside the increment's scope.
- [ ] Commit message format: `[<increment-id>] <component>: <description>`.
- [ ] `git log --oneline -10` — commits readable, no squash of in-progress work.
- [ ] Do NOT `git push` without Matt's explicit approval ("yes, push" in chat).

---

## Sign-off

A release is ready when all applicable sections above are checked. For Matt's review sessions, additionally confirm:

- [ ] The app launches without manual intervention on Matt's Mac mini.
- [ ] At least one preset produces an acceptable visual on Love Rehab or Blue in Green at steady-state.
- [ ] SpectralCartograph is reachable via `⌘]` preset cycling and shows meaningful data.
