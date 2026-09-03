# DS.5 captures — what was rendered, what was run, and what is reachable

Two kinds of image here, and they should be read differently.

**Rendered (`after/ready-*.png`, `after/a11y-ready.txt`)** — produced by
`UzumeAppTests/ReviewCaptureHarness+Ready.swift` through the DS.3/DS.4 harness: the shipped view
in an offscreen `NSHostingView` at 2×, reduced motion on so the cave holds still. Real view, real
state, deterministic — the same convention as DS.4's `after/`.

```
TEST_RUNNER_UZUME_CAPTURE=1 TEST_RUNNER_UZUME_CAPTURE_SET=ready \
TEST_RUNNER_UZUME_CAPTURE_DIR=docs/reviews/DS.5/after \
  xcodebuild -scheme UzumeApp -destination 'platform=macOS' test \
  -only-testing:UzumeAppTests/ReviewCaptureHarness
```

| file | what | reachable |
|---|---|---|
| `ready-streaming-appleMusic.png` | `ReadyView`, Apple Music origin — "Ready." / "Press play in Apple Music." / End session / Begin now over the open cave | yes — any Apple Music session reaching `.ready` |
| `ready-streaming-spotify.png` | same, Spotify origin | yes |
| `ready-streaming-fallback.png` | same, no origin — "your music app" | ad-hoc only; a known streaming source never reads this |
| `ready-localFile-countdown.png` | `LocalFileCountdownView` at "3" over the open cave, End session below | yes — every local-file session, for three seconds |
| `a11y-ready.txt` | the label each element declares (not literal VoiceOver speech) | — |

**Live (`after/arrival-*.png`, `after/live-*.png`)** — screenshots of the real built app,
cropped to its window. `arrival-1-push` / `-2-streaks` / `-3-whiteout` are three frames of the
camera push in an ad-hoc session (the first live run, before the ready screens existed; display
capture, cropped). The rest are window-only captures (`screencapture -l`) of a local-file session on the final
build (`UZUME_LOCAL_FILE_PLAYBACK=…/so_what.m4a`), in order:

| file | moment |
|---|---|
| `live-count-3.png`, `live-count-2.png`, `live-count-1.png` | the count, one beat each, over the open cave |
| `live-hold.png` | the count done, numeral gone, the cave holding alone while the engine brings the audio up (~3 s on a cold preset) |
| `live-push.png` | the camera push under way — the real aperture, streaks racing out |
| `live-whiteout.png` | the screen filled with light |
| `live-playing.png` | the first preset running, driven by the file's audio |

The first live run of the count is what found the LF.4 routing shortcut
(`docs/reviews/DS.5/DESIGN.md` §The problem, correction): no count, the push at `.ready`, a flat
line for 95 s. Those frames are not kept; the sequence above is from the fixed build.

Not captured live: the streaming waiting room with a real Spotify / Apple Music session (needs
the listener's own account — that is the M7), and the timeout card (90 s, unchanged from U.5).
