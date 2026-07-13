# Session prompt — PUB.10

## Increment PUB.10 — R3.2: CaptureStateSurface decomposition slice

**Type:** infrastructure (app-layer refactor; no engine-module changes).

**Objective.** After this session, the capture/signal-state `@Published`
surface of `VisualizerEngine` (`audioSignalState`, `signalHealth`,
`hasScreenCapturePermission`, and — pending Task 1's semantic check —
`isCapturing`) lives in a dedicated child ObservableObject
(`CaptureStateSurface`) with `private(set)` publication and semantic
mutators, exactly per the R3.1 recipe that shipped `NowPlayingSurface`
(PUB.9). Behavior-identical: same emission pattern, same threading, all
suites green. This is slice 2 of 5 of the R3 / CLEAN-Phase-8 decomposition.

## Skill invocations

- `closeout` at the end (mandatory).
- No preset/shader/defect skills apply — this is app-layer state plumbing.

## Read-first file list

1. `PhospheneApp/NowPlayingSurface.swift` — the R3.1 worked example this
   slice copies: `private(set) @Published` + mutators +
   `dispatchPrecondition(.onQueue(.main))` + file-header rationale.
2. `docs/ENGINEERING_PLAN.md` §Increment PUB.9 — the recorded recipe
   (child + forwarders + objectWillChange bridge + compiler-found writers).
3. `PhospheneApp/VisualizerEngine.swift` lines ~148–165 and ~637–648 — the
   four declarations and their doc comments (they carry ASH.1/ASH.2 context
   that must move with the fields).
4. `PhospheneApp/VisualizerEngine+Capture.swift` lines ~36–110 — writer
   sites, including the `isCapturing` semantic question (Task 1).
5. `PhospheneApp/VisualizerEngine+Audio.swift` ~line 54 — the
   `signalHealth` writer (already hops via `Task { @MainActor }` — the
   pattern every off-main writer must keep).
6. `PhospheneApp/VisualizerEngine+PublicAPI.swift` lines ~40–70 — the
   permission/signal-state writers on the start path.
7. `PhospheneApp/ContentView.swift` + `PhospheneApp/Views/Playback/PlaybackView.swift`
   — the `engine.$audioSignalState` / `engine.$signalHealth` publisher
   injection sites (become `engine.captureState.$…`).
8. `PhospheneApp/Services/FirstAudioDetector.swift` line ~40 — doc comment
   citing `engine.$audioSignalState`; update the citation.

## Pre-flight invariants

- Branch `claude/phosphene-codebase-review-4303dc` checked out at or after
  `17b22ee`, clean tree, in sync with origin. A dirty tree or unpushed
  divergence → stop.
- `Scripts/test_fast.sh` green before any edit (baseline). Red → stop.
- `PhospheneApp/NowPlayingSurface.swift` exists (R3.1 landed). Missing →
  wrong branch, stop.

## Numbered tasks

1. **Map the writers and settle `isCapturing`'s membership.** Grep every
   assignment to the four fields; record file:line + thread context for
   each. `isCapturing`'s writers (`VisualizerEngine+Capture.swift` ~40/47)
   are the **CSV feature-capture** start/stop — a diagnostics flag, not the
   tap state. Decide: include it in `CaptureStateSurface` (it is
   capture-adjacent published state) or leave it engine-side for a later
   diagnostics slice. Either is acceptable — record the choice and rationale
   in the child's file header. **Done-when:** a writer inventory (field →
   sites → thread context) exists in the session notes and the membership
   decision is written down.
2. **Create `CaptureStateSurface.swift`** (PhospheneApp root, next to
   NowPlayingSurface) — `private(set) @Published` fields, semantic mutators
   with `dispatchPrecondition(.onQueue(.main))`, doc comments moved from the
   engine declarations (keep the ASH.1/ASH.2 and D-165 references intact).
   Register in `PhospheneApp.xcodeproj/project.pbxproj` — **all four
   sections** (PBXBuildFile, PBXFileReference, group children, Sources
   phase; the K-prefixed id convention — see the NowPlayingSurface entries,
   K10090/K20090). **Done-when:** app target builds with the new file.
3. **Swap the engine declarations for the child + read-only forwarders +
   bridge.** `let captureState = CaptureStateSurface()`; computed get-only
   forwarders under the historical names; extend the existing R3.1
   objectWillChange bridge (one combined subscription or a second
   cancellable — either, documented). Then build and **let the compiler
   enumerate every writer**; convert each to the semantic mutator,
   preserving each site's exact thread-hop shape (writers already inside
   `Task { @MainActor }` stay that way; any writer NOT on main must gain the
   hop, not lose the precondition). **Done-when:** app target builds; zero
   writer sites remain on the forwarders.
4. **Move the publisher injection sites** (`ContentView`, `PlaybackView`,
   and the FirstAudioDetector doc citation) to `engine.captureState.$…`.
   **Done-when:** app target builds; `grep -rn '\$audioSignalState\|\$signalHealth' PhospheneApp --include='*.swift'`
   shows only `captureState.$…` forms.
5. **Contract tests.** Add `CaptureStateSurfaceTests` (mirror
   `NowPlayingSurfaceTests`): mutators publish; any grouped transitions this
   surface turns out to have (e.g. permission+state on the start path) are
   paired. Register in pbxproj (both test sections). **Done-when:** app
   suite green including the new tests.
6. **Full verification + docs.** ARCHITECTURE §Module Map row for the new
   file (the D-168 gate will fail the suite until it exists); EP Phase-PUB
   header + PUB.10 increment entry; RELEASE_NOTES_DEV entry
   (`[dev-YYYY-MM-DD-HHMMSS]` UTC id — never hand-letter). **Done-when:**
   verification commands below all pass.

## Do NOT

- Do not touch the orchestrator-bridge fields (`livePlannedSession`,
  `livePlan`, `liveTrackPlanIndex`, `orchestratorLock`) — that is R3.5, the
  cross-thread-delicate slice, its own session.
- Do not touch the LF transport fields (`isLocalFilePaused`,
  `localFileCacheBytes`, `lastEndedLocalFileOrigin`) — R3.4.
- Do not touch the analysis surface (`currentMood`, `estimatedKey`,
  `estimatedTempo`, `mirDiag`) — R3.3.
- Do not change `PlaybackErrorBridge`'s injected-publisher API — only the
  injection call sites change.
- Do not modify anything under `PhospheneEngine/Sources` — this slice is
  app-target only (SignalHealthMonitor and the router stay as they are).
- Do not "fix" writer thread-hops opportunistically beyond the mechanical
  conversion — a hop that looks wrong is a finding to report, not to change
  in this increment (BUG-063 doctrine: no unverified-theory fixes).

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test 2>&1
swift test --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter DocIntegrityTests 2>&1
```

Known-environment notes: ~21 tempo-fixture tests fail in a fresh worktree
until `Scripts/bootstrap_fixtures.sh`; a one-off SIGTRAP in
`swiftpm-testing-helper` was observed once at the PUB.9 battery (green on
immediate re-run) — if it recurs, note it in the closeout and file a BUG.

## Commit message templates

Small commits, one per logical step; local-only until Matt's explicit
"yes, push":

```
[PUB.10] App: CaptureStateSurface child + pbxproj registration (R3.2)
[PUB.10] App: engine declarations → forwarders; writers converted (R3.2)
[PUB.10] App: publisher injection sites → captureState.$… (R3.2)
[PUB.10] App: CaptureStateSurface contract tests
[PUB.10] Docs: Module Map row + EP + release-notes entries
```

## Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim
`Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:
the Task-1 writer inventory (field → sites → thread context) and the
`isCapturing` membership decision with rationale.

## DECISION-NEEDED

None — this is engineering-internal state plumbing with no user-visible
change. (The `isCapturing` membership call in Task 1 is Claude's to make
and record.)
