# DS.4 captures — what was rendered, and what is reachable in a real session

Captures are produced by `UzumeAppTests/ReviewCaptureHarness.swift` (the DS.3 harness,
generalised) through an offscreen `NSHostingView` at 2×, driving the shipped
`PreparationProgressView` with scripted statuses through the same publisher protocol
`SessionPreparer` implements. They are the real view with real state, not mock-ups.

```
TEST_RUNNER_UZUME_CAPTURE=1 TEST_RUNNER_UZUME_CAPTURE_DIR=docs/reviews/DS.4/<before|after> \
TEST_RUNNER_UZUME_CAPTURE_SET=preparation \
  xcodebuild -scheme UzumeApp -destination 'platform=macOS' test \
  -only-testing:UzumeAppTests/ReviewCaptureHarness
```

`before/` was taken at the harness commit, before any view change (the view there is
`main` at 67c42092). `after/` renders every state twice, `-mysterious` and `-detailed`.
`a11y-preparation.txt` in each records the label each element **declares**; VoiceOver applies
its own rotor and punctuation on top. `before/live-early.png` is a screenshot of the real app
mid-run on `main` (the task 2 baseline), and `after/live-*.png` are the same from the DS.4
build (task 10).

| Capture | Reachable in a real session? |
|---|---|
| `preparation-early` | **Yes** — the first seconds of any playlist: resolving / downloading / queued, nothing heard. In the mysterious view the cave is shut. |
| `preparation-mid` | **Yes** — two heard, one analysing, downloads in flight; below the three-track threshold. Pinprick, no "Start now". |
| `preparation-threeReady` | **Yes** — three consecutive tracks ready: `readyForFirstTracks`, "Start now" enabled. The cave opens properly here at any playlist length. |
| `preparation-halfway` | **Yes** — ≥ 50 % ready: `partiallyPlanned`. |
| `preparation-previewNotFound` | **Yes** — a track with no iTunes preview (`.failed("Preview not available")`). Inline on its row in the detailed view; a count line in the mysterious view. |
| `preparation-stemSeparationFailed` | **Yes** — stem separation failed for one track (`.partial("Stems unavailable")`). Inline on its row; counts as usable, so it is *not* in the mysterious failure count (only `.failed` is). |
| `preparation-banner` | **Rendered, but the trigger used is not reachable.** `PreparationErrorViewModel` raises `.previewRateLimited` on a `.partial` whose reason mentions "rate", and no production path emits one — `PreviewResolver` throttles through `ITunesRateLimiter` silently. The two *reachable* banners (slow first track > 90 s, total timeout > 120 s) need a real clock the harness cannot rewind through the view. The slot and its placement are what the capture evidences; DS.3's `banner-*` captures evidence the tones. This is a DS.3-era finding, recorded here, not fixed (no DS.3 status component is touched). |
| `preparation-recovery` | **Yes** — every track failed → `RecoveryScreen`. Identical in both views: the `.fullScreen` branch is above the preference. |
| *fully prepared* | **Not capturable as a held state.** When the last track lands with "Start now" untouched, `SessionManager` moves to `.ready` on the same tick; the aperture's fully-open stop is visible only in the last frames before `ReadyView`. Whether it persists into the ready state is DS.5's question. |
| *reduced motion* | **Not a capture — a test.** `PreparationApertureTests.reducedMotion_rendersNonEmptyAperture` renders the scene at the pinprick and at three-ready with the timeline frozen and asserts both are non-empty and ordered. Under reduced motion the view snaps to its stop with no easing and no swell. |
