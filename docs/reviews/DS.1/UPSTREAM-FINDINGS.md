# DS.1 — findings for `uzume-site`

Input to a future `uzume-site` increment. DS.1 adopted the design system's tokens in
the Uzume macOS app and touched nothing in the site repo (D-228: the site owns the
design system, the app consumes it). Everything below is something the app needed and
could not get from the published package, or a place where the package and
`tokens.css` disagree.

Reference points: `DesignSystem/SwiftUI/Sources/UzumeDesignSystem/UzumeTokens.swift`
at `03d5478` (the file DS.1 vendored) and `tokens.css` at the same commit.

---

## 1. The Swift package's colour roles resolve to neither published palette

**What the package does.** `UzumeColor.canvas` is `Color(nsColor: .windowBackgroundColor)`,
`surface` is `.controlBackgroundColor`, `textPrimary`/`textSecondary` are
`.labelColor`/`.secondaryLabelColor`, `line` is `.separatorColor`.

**What `tokens.css` publishes.** `--color-canvas` #0b0c10, `--color-surface` #14151a,
`--color-text-primary` #f4f6f1, `--color-line` #34363f (dark); a separate, explicit
light set.

These are not the same colours. AppKit's `windowBackgroundColor` in dark appearance is
a mid-charcoal, several levels lighter than #0b0c10; `labelColor` is pure white at 85%
alpha, not the warm ivory #f4f6f1. An app that consumes `UzumeColor` does not get the
Uzume palette in either appearance — it gets macOS's, tinted only at `accent`.

**What the app did instead.** `UzumeApp/DesignSystem/UzumeTokens+App.swift` transcribes
the dark block of `tokens.css` directly. The vendored file is used only for
`UzumeSpace`, `UzumeRadius`, and the violet/cyan/gold/ember spectrum.

**Motivated by:** every chrome surface — `UzumeApp/ContentView.swift`,
`Views/Idle/IdleView.swift`, `Views/ConnectorPickerView.swift`,
`Views/Preparation/PreparationProgressView.swift`, `Views/Ready/ReadyView.swift`,
`Views/Ended/EndedView.swift`.

**Suggested resolution.** Publish the roles as literals matching `tokens.css`, with an
adaptive wrapper that switches between the light and dark blocks — the same shape
`UzumeColor.accent` already uses for violet. System colours are the right answer only
for the native-control tint, which is exactly where the package already gets it right.

---

## 2. Role coverage — the package publishes 12 colour roles, `tokens.css` publishes 40

Every role below exists in `tokens.css` and has no Swift equivalent. The app had to
transcribe all of them by hand.

| Missing role | `tokens.css` | First app consumer |
|---|---|---|
| `surfaceRaised` | `--color-surface-raised` | `Views/ConnectorTileView.swift`, `Views/SpotifyConnectionView.swift` |
| `surfaceSelected` | `--color-surface-selected` | `Views/LocalSourceConnectionView.swift` (hover), `Views/Preparation/PreparationProgressView.swift` (progress track) |
| `lineSubtle` | `--color-line-subtle` | `Views/Preparation/PreparationProgressView.swift` (row divider) |
| `textTertiary` | `--color-text-tertiary` | `Views/Idle/IdleView.swift`, `Views/ConnectorTileView.swift` |
| `textDisabled` | `--color-text-disabled` | `Views/ConnectorTileView.swift` (disabled tile) |
| `controlDisabledBackground` / `Border` | `--color-control-disabled-*` | not yet consumed; needed once DS.2 consolidates `SourceChoice`'s disabled variant |
| `accentHover` / `accentPressed` / `accentSubtle` | `--color-accent-*` | not yet consumed; needed by any non-native control |
| `onAccent` | `--color-on-accent` | `Views/Preparation/TopBannerView.swift`, `Views/Playback/AudioStallOverlayView.swift` |
| `focus` | `--color-focus` | not yet consumed; needed before any custom focus ring |
| `successSubtle` / `warningSubtle` / `dangerSubtle` / `infoSubtle` | `--color-*-subtle` | not yet consumed |
| the twelve `--color-status-*-foreground/background/border` values | `--color-status-*` | `Views/Playback/ToastView.swift` (severity accent bar) |
| `scrim` | `--color-scrim` | see finding 6 |
| `ivory` | `--color-ivory` | `UzumeAppColor.ivory` |

---

## 3. `UzumeRadius` and `--radius-*` agree only on the smallest rung

`UzumeRadius` is compact 6 / standard 10 / prominent 14. `--radius-sm/md/lg` are
0.375rem / 0.75rem / 1rem — 6 / 12 / 16.

The app follows `tokens.css` (`UzumeAppRadius.sm/md/lg`) so a native surface and its
web counterpart round the same way, and takes `UzumeRadius.standard` (10) directly in
the one place a measured value depends on it — `PerformanceBackdrop`'s corner.

**Motivated by:** `Views/ConnectorTileView.swift` (12), `Views/Playback/LocalFileTransportBar.swift`
(16), `Views/Playback/ShortcutHelpOverlayView.swift` (16), `Views/Playback/PerformanceBackdrop.swift` (10).

**Suggested resolution.** Pick one. If the native scale is deliberately tighter, say so
in `COMPONENTS.md` and name the rungs the same way (`sm`/`md`/`lg`) so the divergence is
visible rather than implied by three different words.

---

## 4. `UzumeSpace` omits half the four-point rhythm

`UzumeSpace` publishes x1 x2 x3 x4 x6 x8 x12 — that is `--space-1` through `--space-4`,
`-6`, `-8`, `-12`. Missing: `--space-5` (20), `--space-10` (40), `--space-16` (64),
`--space-20`, `--space-24`, `--space-32`.

The app's existing layout uses 20, 22, 40 and 44 pt in several places
(`Views/Playback/LocalFileTransportBar.swift`, `Views/Ready/ReadyView.swift`,
`Views/Preparation/TopBannerView.swift`). DS.1 did not reflow any layout, so those
numbers remain literal; DS.2+ cannot retire them without the missing rungs.

---

## 5. No vocabulary for translucency over the live performance frame

This is the largest gap and the one most specific to the native app. Uzume's overlay
chrome is drawn over an arbitrary preset frame, not over a known surface. An opaque
surface role there is wrong twice: it hides the visual the app exists to show, and it
destroys the blur the contrast floor depends on.

The app added `UzumeAppColor.Performance` for this: `backdropTint`, `panelTint`,
`toastTint`, `sheetScrim`, and a fill/mark/indicator ladder. Its values are measured
against real preset frames (`PresetContrastCertificationTests`), not chosen.

**Motivated by:** `Views/Playback/PerformanceBackdrop.swift`, `TrackInfoCardView.swift`,
`ShortcutHelpOverlayView.swift`, `ToastView.swift`, `SessionProgressDotsView.swift`,
`AudioStallOverlayView.swift`, `LocalFileTransportBar.swift`.

**Suggested resolution.** The site has no equivalent surface, so this may belong in the
app permanently. If it does, `COMPONENTS.md` should say so — otherwise the next reader
will assume these are roles someone forgot to upstream.

---

## 6. `--color-scrim` is not the app's scrim

`--color-scrim` is 72% black. The app has three scrims and none of them is 72%: the
performance backdrop is 45% (measured, over `.ultraThinMaterial`), the shortcut-help and
stall panels are 40%, the toast is 35%, and the ready-timeout sheet dims at 60%.

Substituting `--color-scrim` for the 45% would change a measured contrast result. DS.1
kept every number and named them instead.

**Motivated by:** `Views/Playback/PerformanceBackdrop.swift` and the three files above.

---

## 7. No role for ink drawn on a bright status field

`TopBannerView` is a high-attention interruption: a bright warning field with dark
detail on it, which is the treatment the package README describes ("Warning symbols use
a black detail on the yellow field"). `tokens.css` has `--color-on-accent` for ink on
the brand field, but nothing for ink on a status field. The app borrowed `onAccent`.

**Motivated by:** `Views/Preparation/TopBannerView.swift`.

Related: `--color-status-warning-*` describes a *dark* warning treatment (foreground
#ffd60a on background #282400). Both treatments are legitimate and they are different
components — a quiet inline notice and a loud blocking banner. `COMPONENTS.md`
§Status placements should name which is which.

---

## 8. `--color-text-tertiary` and `--color-text-disabled` are the same colour

Both are `#a4a8a2`. A disabled control and tertiary body text are therefore
indistinguishable in the dark theme. The light theme does not separate them either:
`--color-text-tertiary` is `--uzume-ink-600` #64676f and `--color-text-disabled` is
#64676f. So the role pair is redundant in both themes.

The app's disabled connector tile previously read at white@0.3 against tertiary text at
white@0.5 — a visible difference that the token set cannot express.

**Motivated by:** `Views/ConnectorTileView.swift` (`isEnabled ? … : …` on both the icon
and the title).

---

## 9. Semantic status colours diverge between the two implementations

`UzumeColor.success/warning/danger/information` are `.systemGreen/.systemYellow/
.systemRed/.systemBlue`. `tokens.css` publishes #67d6a2 / #ffd60a / #ff8a75 / #64d2ff.
Yellow is close; the green, red and blue are not — `--color-danger` #ff8a75 is a warm
salmon, `systemRed` is not.

Also a naming split: Swift says `information`, CSS says `--color-info`.

**Motivated by:** `Views/TrackPreparationStatusIcon.swift`, `Views/SpotifyConnectionView.swift`,
`Views/Playback/ToastView.swift`.

---

## 10. The package publishes no typography

`tokens.css` publishes a full type system — Alumni Sans display, PT Sans for UI and
prose, seven sizes, three leadings, two trackings. `UzumeTokens.swift` publishes none of
it. The app uses macOS system fonts throughout and DS.1 changed nothing there, which
means the native product currently shares no typographic identity with the site.

This is the single largest remaining gap between the two surfaces, and it is not a
mechanical swap — the native side has to decide whether Alumni Sans appears in the app
at all, and whether PT Sans replaces the system font in Settings and onboarding (where
`List`/`Form` are native by policy). A product decision, not a token one.

---

## 11. Divergence recorded by decision, not by omission: Uzume is always dark

`tokens.css` publishes a complete light palette and the Swift package is built on
adaptive system colours, so upstream's intent is clearly that the app adapts. DS.1
decided otherwise (Matt, 2026-09-01, D-231 option A): every screen keeps the near-black
canvas whatever macOS is set to, and the app root sets `.preferredColorScheme(.dark)`.

Reasons: the ≥4.5:1 overlay contrast floor was measured against a dark composite and
would need re-measuring under a light one; and the product principle that the frame stays
dark so the performance is the only bright thing.

This is recorded here so the option stays open. Light-appearance support is a real
increment with its own visual review, not a side effect of a token swap. If the site
wants the app to adapt, the ask is finding 1 plus a re-measurement of
`PresetContrastCertificationTests` against a light backdrop.

---

## 11b. macOS draws sidebar selection from the system accent, not the design system

`List` selection in a `NavigationSplitView` sidebar is painted from
`NSColor.controlAccentColor` — the user's system-wide Accent colour — and SwiftUI's
`.tint()` does not override it. Verified twice on this build: blue with the tint applied
to the List, and blue in an earlier build that tinted the entire app.

So on a Mac whose accent is Blue, Uzume's Settings sidebar highlights blue, next to a
violet primary button on the same screen. The only way to make it the brand violet is to
draw the selection ourselves, which is the one thing `COMPONENTS.md` §Native platform
controls forbids ("tint and compose; do not rebuild standard macOS control behavior").

**Motivated by:** `UzumeApp/Views/SettingsView.swift`.

**The question for the design system:** is a system-accent selection highlight acceptable
inside an otherwise fully-branded screen, or is the sidebar an exception to the
native-controls rule? `COMPONENTS.md` should answer it explicitly — the app cannot.

---

## 12. Smaller notes

- `UzumeColor` and its members are declared `public`. In the vendored copy that lives in
  an app target, `public` is inert. Harmless, but it is a signal the file was written
  assuming a package boundary the app does not have.
- `UzumeColor.performedLight` has no app consumer yet. It is the background of the
  `PreparationStage` prototype, which DS.1 deliberately did not adopt (the README calls
  it a prototype and `PreparationProgressView` keeps its publishers). It becomes live at
  DS.4.
- The package's prototypes — `CuratorControlSurface`, `StreamingHandoff`,
  `PreparationStage`, `PerformancePreflight`, `UzumeSystemNotice` — were not adopted,
  per the README's own status list. No finding; noted so a future reader does not read
  their absence as an oversight.
- `PHOSPHENE-COMPONENT-CENSUS.md` §Token findings says "Twenty-six view files contain
  direct color/shape values." Counting the same way DS.1's grep gate does, it is 24 in
  scope plus 2 exempt dashboard files; counting every file with a `Color.black` /
  `Color.white` / `.white.opacity(…)` / literal `cornerRadius:` outside the exempt
  diagnostic paths, it is 31. Not a correction so much as a note that the number depends
  on the criterion.
