# Memory Index

- [Audio-to-GPU pipeline](project_audio_architecture.md) — Complete pipeline: Core Audio taps → UMA buffers → Metal shader, all working
- [Audio tap permission](project_audio_permission.md) — AudioHardwareCreateProcessTap silently delivers zeros without screen capture permission
- [ScreenCaptureKit failure](project_screencapturekit_fragility.md) — Zero audio callbacks on macOS 26 despite video working, abandoned
- [User profile](user_role.md) — Matt, product/design lead, Mac mini, prefers proper solutions
- [Prefer proper solutions](feedback_proper_solutions.md) — Investigate root causes before proposing workarounds
- [Permission re-grant UX](project_permission_ux.md) — Rebuilds invalidate screen capture auth, tap delivers silent zeros with no indication
- [Implement verification criteria](feedback_verification_criteria.md) — Increment verification steps are requirements, not suggestions
- [Representational presets](feedback_representational_presets.md) — Depicting real objects requires 3D rendering, full scene context, and a sustainable cycle for the whole track
- [Diagnostic testing discipline](feedback_diagnostic_testing.md) — Diagnostic tests that pass do not prove the preset still renders; visually verify every affected preset after test changes
- [Never use synthetic audio](feedback_synthetic_audio.md) — Diagnostic harnesses must use real preview clips, replayed FeatureVectors, or in-app recording during real playback — never hand-authored envelopes
- [SwiftLint baseline](project_swiftlint_baseline.md) — 0 violations after L-1 cleanup; any violation in active source paths is a regression
- [DECISIONS.md numbering](project_decisions_numbering.md) — Next decision is D-037; D-036 was reactive orchestrator design (4.6); grep docs/DECISIONS.md for '## D-0' before assigning
- [Test suite baseline](project_test_baseline.md) — 415 tests, 4 pre-existing failures; 5th failure = regression
