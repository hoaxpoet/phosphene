# DS.6 captures — the playback chrome, before and after

Two kinds of image, read differently.

**Rendered (`before/chrome-*.png`, `after/chrome-*.png`, `a11y-chrome.txt`)** — produced by
`UzumeAppTests/ReviewCaptureHarness+Chrome.swift` through the DS.3/DS.4/DS.5 harness: the
shipped `PlaybackChromeView`, driven through the real `PlaybackChromeViewModel` by scripted
publishers (the seam `PlaybackView` itself uses), in an offscreen `NSHostingView` at 2× over a
stand-in for the live frame — the performed-light gradient, chosen because its gold/ember corner
is the bright case the backdrop has to hold contrast against. Reduced motion on so the pulse and
spinner hold still; the auto-hide delay is a `NeverDelay`, so every render is a settled state.

```
TEST_RUNNER_UZUME_CAPTURE=1 TEST_RUNNER_UZUME_CAPTURE_SET=chrome \
TEST_RUNNER_UZUME_CAPTURE_DIR=docs/reviews/DS.6/<before|after> \
  xcodebuild -scheme UzumeApp -destination 'platform=macOS' test \
  -only-testing:UzumeAppTests/ReviewCaptureHarness
```

`before/` was taken at the harness commit, before any view change (the chrome there is `main`
at `d4fb16ea`). `after/` is the same scenario list on the DS.6 build, plus the states DS.6 adds.
The pairing is by filename.

**Live (`after/live-*.png`)** — window-only captures (`screencapture -l`) of the real built app.
See §Live captures below.

## Scenario list — reachable?

| file | what | reachable in a real session? |
|---|---|---|
| `chrome-streaming-planned` | streaming session, no artwork: card (title / artist / preset / pill), six progress dots at track 3, gear, End session | **yes** — any planned streaming session |
| `chrome-streaming-artwork` | the same with artwork in the 48 pt slot | **yes** — LF.6.streaming wires URL-fetched art; streaming sessions with none render `-planned` |
| `chrome-streaming-reactive` | no plan: "Reactive" pulsing dot in the cluster, "Reactive" pill on the card | **yes** — ad-hoc (no-playlist) sessions |
| `chrome-localFile-playing` | local-file session: artwork slot always present, transport bar bottom-centre, pause glyph | **yes** — every local-file session |
| `chrome-localFile-paused` | the same, play glyph | **yes** — after Space / the transport's pause |
| `chrome-listening` | `audioSignalState == .silent` (≥ 3 s): "Listening…" badge top-centre | **yes** — sustained silence mid-session |
| `chrome-stillPreparing` | `ProgressiveReadinessLevel < .fullyPrepared`: "Still preparing" under the cluster | **yes** — "Start now" before the playlist finished preparing |
| `chrome-toast-info` / `-warning` / `-degradation` / `-fatal` | one toast per `UzumeToast.Severity`, bottom-trailing | **yes** — display connected / disconnected / stem failure / sustained silence (D-236). **`before/` shows BUG-113**: the toast is the full window height. Found here, confirmed live, fixed in DS.6. |
| `chrome-hidden` | `overlayVisible == false`: nothing drawn, hit-testing off | **yes** — 3 s after any input, and on Space. Matt's call (D-241): nothing stays on screen; mouse, tap, key or track change bring it back |
| `chrome-trackInfoHidden` *(after only)* | `uzume.settings.visuals.showTrackInformation == false`: no card, no artwork, cluster shows "Show track info" | **yes, after DS.6** |
| *chrome mid-fade* | — | **not rendered.** The fade is a moment inside a 240 ms (was 500 ms) opacity animation; the harness renders settled states. Covered by the live captures. |
| *end confirmation* | the `confirmationDialog` on End session | **not rendered** — it is `PlaybackView`'s dialog (Layer 6), not chrome; unchanged by DS.6. |

`a11y-chrome.txt` in each directory is the label each element **declares** (VoiceOver applies its
own rotor and punctuation), followed by every `uzume.playback.*` identifier and the type that
declares it.

## Off-token inventory (task 2) — `main` at `d4fb16ea`

Run against the unchanged tree; the increment gates in `prompts/DS.6-prompt.md` produce exactly
these rows and nothing else (fixed-font gate: no output; identifier gate: no output).

| # | file:line | what it is | replaced by | resolved |
|---|---|---|---|---|
| 1 | `PlaybackChromeView.swift:24` | `Color.teal` — the "still preparing" dot | `StatusTone.info` — the indicator becomes a status placement: `tone.symbol` in `tone.foreground` on `tone.background`, bordered `tone.border` (D-234) | ✅ |
| 2 | `PlaybackChromeView.swift:28` | `.teal.opacity(0.85)` — its text | `StatusTone.info.foreground` | ✅ |
| 3 | `PlaybackChromeView.swift:31` | `.easeIn(duration: 0.4)` — indicator appear | `UzumeAppMotion.standard` (240 ms, exponential ease-out) | ✅ |
| 4 | `PlaybackChromeView.swift:115` | `.easeInOut(duration: 0.5)` — the chrome fade | `UzumeAppMotion.standard` | ✅ |
| 5 | `TrackInfoCardView.swift:136` | `.green.opacity(0.7)` / `.orange.opacity(0.7)` — the Planned/Reactive pill | removed with the pill (D-241 §1) | ✅ |
| 6 | `TrackInfoCardView.swift:142` | `color.opacity(0.15)` — the pill's field | removed with the pill | ✅ |
| 7 | `PlaybackControlsCluster.swift:25` | `Divider().opacity(0.4)` — the separator, a system colour at an ad-hoc alpha | a 1 × 16 pt rule in `UzumeAppColor.line` | ✅ |
| 8 | `SessionProgressDotsView.swift:45`, `:86` | `easeInOut(1.0).repeatForever` — the current-dot pulse | **kept** — an ambient pulse, not a state change; the three design-system durations govern feedback / state / opening. Already removed under reduced motion; `PlaybackChromeReducedMotionTests` pins that | ✅ |
| 9 | `SessionProgressDotsView.swift:92` | `.easeInOut(duration: 0.25)` — current-dot change | `UzumeAppMotion.standard` | ✅ |
| 10 | `ListeningBadgeView.swift:31` | `linear(1.5).repeatForever` — the spinner | **kept** — continuous by design, removed under reduced motion (pinned by the same test) | ✅ |
| 11 | `ListeningBadgeView.swift:45` | `.easeInOut(duration: 0.4)` — badge fade | `UzumeAppMotion.standard` | ✅ |
| 12 | `ToastRegion.swift:26` | `.easeInOut(duration: 0.3)` + `.move(edge:)` — toast insert | `UzumeAppMotion.standard`; reduced motion drops the slide for a crossfade | ✅ |
| 13 | `LocalFileTransportBar.swift:3`, `:13` | the `.impeccable.md` / "coral is action" header | rewritten to the design system's rule: violet is the interaction accent | ✅ |
| 14 | `LocalFileTransportBar.swift:66` | `DashboardTokens.Color.surfaceRaised` | `UzumeAppColor.surfaceRaised` (`--color-surface-raised`) | ✅ |
| 15 | `LocalFileTransportBar.swift:68` | `DashboardTokens.Color.purpleGlow.opacity(0.55)`, radius 28 — the purple glow | `UzumeAppShadow.raised` (`--shadow-raised`: 0 16 42 / 32 % black). DESIGN.md: the bar genuinely floats, so it takes the raised shadow; "vaporwave glow" is a listed Don't | ✅ |
| 16 | `LocalFileTransportBar.swift:76` | `DashboardTokens.Color.border.opacity(0.6)` | `UzumeAppColor.line` (`--color-line`) | ✅ |
| 17 | `LocalFileTransportBar.swift:114`, `:147` | `.easeInOut(duration: 0.15)` — hover | `UzumeAppMotion.feedback` (120 ms) | ✅ |
| 18 | `LocalFileTransportBar.swift:135`, `:136` | `DashboardTokens.Color.textBody` / `.textMuted` — glyph fills | `UzumeAppColor.textPrimary` / `.textTertiary` | ✅ |
| 19 | `PlaybackView.swift:170` | the `.impeccable.md` citation in the dashboard-overlay comment | comment rewritten (the layer itself is untouched — Layer 6 is out of scope) | ✅ |

Not in the table because no gate fires on them and the design system does not own them: the
48 pt artwork slot, the 200–380 pt card width, the 44 / 30 pt transport targets (DESIGN.md's
44 px minimum is met by the disc; the muted buttons are 30 pt — recorded in
`UPSTREAM-FINDINGS.md`).

## Identifiers

Before: `uzume.playback.chrome`, `.trackInfoCard`, `.trackInfoCard.artwork`, `.controlsCluster`,
`.progressDots`, `.listeningBadge`, `.lfTransport`, `.shortcutHelp` (Layer 4), and
`uzume.view.playing` on `PlaybackView`.

After: all of the above unchanged, plus **`uzume.playback.toggleTrackInfo`** on the new control
and **`uzume.playback.quietEndSession`** on the quiet-state control. `PlaybackViewIdentifierTests`
is extended, not edited.

## Live captures

Window-only captures (`screencapture -x -o -l<CGWindowID>`) of the real DS.6 build in a local-file
session (`UZUME_LOCAL_FILE_PLAYBACK=…/so_what.m4a`, 900 × 632 window, 2×), driven by synthetic
`CGEvent` input after activating the app. In order:

| file | moment |
|---|---|
| `live-full-after-arrival.png` | the full chrome, the arrival just faded (card, cluster with three controls, transport) |
| `live-hidden.png` | 3 s later: nothing on screen (D-241, Matt's call) |
| `live-restored-mouse.png` | a mouse move brings the full chrome back |
| `live-restored-tap.png` | after it has gone again, a tap on the screen brings it back |
| `live-restored-key.png` | after it has gone again, a key press (`j`) brings it back |
| `live-hidden-space.png` | Space: hidden at once |
| `live-trackInfoShown.png` / `live-trackInfoHidden.png` | the cluster's Show/Hide track info control, clicked; the card and its artwork leave the tree |
| `live-toast-BUG113-before-fix.png` | `l` (diagnostic hold) raises a toast — and the build before the fix drew it floor to ceiling over the cluster. The evidence for BUG-113; the `after/chrome-toast-*.png` renders are from the fixed build |

**Not captured live: a real streaming session.** It needs Spotify playing; Matt runs that as the
M7, as at DS.5. The streaming states (card without artwork, planned dots, reactive dot) are
evidenced by the harness renders above.

Pairs for review, by filename: every `before/chrome-*.png` has an `after/chrome-*.png`;
`after/` adds `chrome-trackInfoHidden`.
