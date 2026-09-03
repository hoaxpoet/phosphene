# DS.6 — findings for `uzume-site`

Input to a future `uzume-site` increment. DS.6 retokenized the playback chrome in the Uzume
macOS app and touched nothing in the site repo (D-228). Everything below is something the app
needed and could not get from the published design system, or a place where the design system
and the app disagree after this increment.

Reference points: `DesignSystem/COMPONENTS.md` §`PerformanceChrome`, §`TrackInformation`,
§`PerformanceControls`, §`LocalPlaybackTransport`; `DESIGN.md` §Curator Control Surface, §Shared
States and Motion, §Shadow Vocabulary; the vendored `UzumeTokens.swift` at `03d5478`.

---

## 1. The tokens carry no motion

`DESIGN.md` §Shared States and Motion names three durations (120 / 240 / 480 ms) and one curve
(exponential ease-out), and says what reduced motion removes. Neither `tokens.css` nor
`UzumeTokens.swift` publishes them. The app added `UzumeAppMotion` in `UzumeTokens+App.swift`
with the same provenance-comment style as the colour roles, and approximates the curve as the
cubic-bézier (0.16, 1, 0.3, 1). Publishing `--motion-feedback` / `--motion-standard` /
`--motion-opening` and the curve in the package would let the app consume rather than transcribe.

## 2. The tokens carry no shadow

`DESIGN.md` §Shadow Vocabulary defines `Raised` (`0 16px 42px rgb(0 0 0 / 32%)`) and `Focus`.
The package publishes neither. The app added `UzumeAppShadow.raised` for the local transport bar.

## 3. The chrome disappears completely after inactivity — a product decision, not a gap

`COMPONENTS.md` §`PerformanceChrome` and `DESIGN.md` §Curator Control Surface say the chrome
"may reduce to quiet edge controls after inactivity but cannot become undiscoverable". Matt
decided otherwise for the app (D-241, 2026-09-03): *"Chrome should disappear completely after a
brief period of inactivity so that the user can focus on the visuals. When mouse activity is
detected or the user taps the screen, the chrome returns."* Uzume ships that: after 3 s nothing
is on screen; mouse movement, a tap, any key press or a track change bring all of it back.
Discoverability is the mouse and the tap. This is for `uzume-site` to adopt — the sentence in
both documents should say what the product does.

One note for whoever revisits "quiet edge controls" later: a low-opacity glyph over the live
frame cannot meet the document's own 3:1 floor for meaningful icons on a bright preset. If a
quiet control ever returns, it belongs on the certified backdrop at full opacity — small and
alone, not faint.

## 4. `COMPONENTS.md` names `ToastContainerView`

§`PerformanceChrome` "Existing source" lists `ToastContainerView`. The app renamed it `ToastRegion`
at DS.3 (`PerformanceToast` is the cell). Same for `SessionProgressDotsView` → the component is
`SessionPosition`, which is fine; only the toast name is stale.

## 5. `TrackInformation` says "preset name is omitted by default if it weakens surprise"

The app keeps the preset name on the card: it names what is on screen *now*, which the surprise
model (D-238) allows, and Matt has read it that way since U.6. The orchestrator pill
("Planned / Reactive") is what was removed. If the design system wants the preset name off by
default, that is a product call for Matt, not something the app can infer from the sentence.

## 6. Control target sizes in the transport bar

`DESIGN.md` §Components gives 44 px as the minimum target on the website. The transport bar's
play/pause disc is 44 pt; the stop / previous / next controls are 30 pt hit areas. The native
document does not state a minimum. Recorded, not changed: the bar's geometry is the GAP C
design Matt approved, and 30 pt matches AppKit's own small controls.

## 7. Toasts fade with the chrome

Pre-existing, not introduced here: `ToastRegion` sits inside the chrome's visibility, so a
toast raised while the chrome is quiet is unseen until the mouse moves. `COMPONENTS.md`
§`PerformanceChrome` says the chrome carries the "notification behaviour"; whether a toast
should wake the chrome for its lifetime is a product decision recorded for Matt in D-241.
