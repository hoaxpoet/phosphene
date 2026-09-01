# DS.3 captures — what was rendered, and what is reachable in a real session

Captures are produced by `UzumeAppTests/DS3StatusCaptureHarness.swift` via SwiftUI
`ImageRenderer` at 2× and are byte-reproducible. They are not screenshots of a driven
session: several tones cannot be reached from any real failure, and rendering is the
only way to evidence the whole colour map. Reachability is recorded per row.

`a11y.txt` alongside the images records the accessibility label each surface
**declares**. That is the contract VoiceOver reads; it is not a transcript of VO
speech, which applies its own rotor and punctuation rules on top.

| Capture | Reachable in a real session? |
|---|---|
| `fullscreen-fatal-networkOffline` | **Yes** — `PreparationErrorViewModel` fires `.fullScreen` on network loss. |
| `fullscreen-fatal-allTracksFailed` | **Yes** — every track failing to prepare. |
| `fullscreen-warning-spotifyUnreachable` | **No.** `spotifyUnreachable` has `presentationMode == .fullScreen`, but the only construction site of the full-screen surface is `PreparationProgressView`'s `.fullScreen` branch, and `PreparationErrorViewModel` only ever routes the two fatal cases there. Rendered to evidence the `warning` arm of the colour map. |
| `fullscreen-degradation-stemSeparationFailed` | **No.** `stemSeparationFailed` routes to `.inlineOnRow`. Rendered to evidence the `degradation` arm — the arm conflict 1 is about. |
| `fullscreen-info-emptyPlaylist` | **No.** Routed to the connection views, not this surface. Rendered to evidence the `info` arm. |
| `banner-rateLimited` | **Yes** — `previewRateLimited`. |
| `banner-slowFirstTrack` | **Yes** — `preparationSlowOnFirstTrack`. |
| `banner-totalTimeout` | **Yes** — `preparationTotalTimeout`. |
| `banner-fatal-networkOffline` | **No**, and not reachable after DS.3 either — a fatal error routes to the full-screen surface, never the banner. Rendered only to show that the banner's tone now varies with severity where before every banner was the same amber. |
| `banner-info-rePlanSucceeded` | **No**, same reason. Same purpose. |
| `inline-*` (4) | **Yes** — all four are reachable from the local-file picker flow (drop an unsupported file, an unreadable file, a bad `.m3u`, an empty folder). |
| `toast-info` / `toast-warning` / `toast-degradation` | **Yes** — all three severities occur during playback. |
| *a `fatal` toast* | **Not representable.** `UzumeToast.Severity` has no `fatal` case, and `PlaybackErrorBridge` : 203 folds `.fatal` into `.degradation` before the view sees it. Out of scope (do-NOT: neither source enum changes). |
| *`FullScreenErrorView` in any state* | **Not reachable at all** — zero construction sites. This is task 8's second dead affordance and the reason task 4 can delete it at no behavioural risk. Not captured; there is no before-state to preserve because it has never been on screen. |
