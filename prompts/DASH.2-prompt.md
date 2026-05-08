Execute Increment DASH.2 — Metrics card layout engine.

Authoritative spec: docs/ENGINEERING_PLAN.md §Phase DASH §Increment DASH.2.
Authoritative design: .impeccable.md §Aesthetic Direction (Color, Typography),
§State-Specific Design Notes, and §Anti-Patterns. Read both before writing
any code.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. DASH.1 + DASH.1.1 must have landed. Verify with
   `git log --oneline | grep '\[DASH\.1'` — expect at least four
   commits including `[DASH.1.1] dashboard: align tokens with
   .impeccable.md OKLCH spec` (40f79fd8).

2. Before reading tokens, confirm the spec-aligned palette is in place:
   `grep -E "surface |surfaceRaised|textHeading|purpleGlow" \
     PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift`
   — expect 4+ matches. If not, DASH.1.1 has not landed; stop.

3. Decision-ID numbering: D-081 covers the dashboard infrastructure
   *and* the DASH.1.1 amendment. The next available number is **D-082**.
   Verify with `grep '^## D-0' docs/DECISIONS.md | tail -3`.

4. `default.profraw` may be present in the repo root from prior test
   runs. It is gitignored implicitly by being absent from any tracked
   path; do not stage or commit it.

────────────────────────────────────────
GOAL
────────────────────────────────────────

Build the layout primitive that DASH.3 (Beat & BPM), DASH.4 (Stems), and
DASH.5 (Frame budget) will all consume. Cards are the unit of visual
identity for the dashboard — get this right and the next three increments
become trivial composition exercises; get it wrong and every card
re-fights the same layout battles.

This increment is **rendering primitives + a tiny layout DSL**. It does
NOT wire any card into PlaybackView (that's DASH.6). It does NOT decide
what data each card shows (that's DASH.3+). It produces:

  1. A value type (`DashboardCardLayout`) describing one card's
     structure: title, rows, fixed width, padding.
  2. A renderer (`DashboardCardRenderer`) that takes a layout + a frame
     of values and emits `drawText` calls onto a `DashboardTextLayer`,
     plus a small amount of bar-chart geometry via the underlying
     `CGContext`.
  3. Three row variants: single-value, two-column pair, bar-chart row.
  4. Right-edge clipping so a card placed near the canvas edge never
     overflows the layout's declared width.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

1. NEW FILE — `DashboardCardLayout.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`

   Pure value types (`Sendable`, no Metal). Define:

   ```
   public struct DashboardCardLayout: Sendable {
       public let title: String
       public let rows: [Row]
       public let width: CGFloat            // fixed; cards do not flex
       public let padding: CGFloat          // inset for content (default Spacing.md = 12)
       public let titleSize: CGFloat        // default TypeScale.label = 11 (UPPERCASE)
       public let rowSpacing: CGFloat       // default Spacing.xs = 4
       public init(title:rows:width:padding:titleSize:rowSpacing:)
       // Computed:
       public var height: CGFloat { ... }   // padding + title + rowSpacing + Σ row heights + padding
   }

   public enum Row: Sendable {
       /// "BPM"          "125"
       case singleValue(label: String, value: String, valueColor: NSColor)
       /// "MODE"   "PLANNED · LOCKED"   |   "BAR"   "3 / 4"
       case pair(leftLabel: String, leftValue: String,
                 rightLabel: String, rightValue: String,
                 valueColor: NSColor)
       /// "BASS"  ▮▮▮▮▮▮▯▯▯▯  +0.42
       /// Bar fill is clamped [-1, +1]; negative draws left of centre.
       case bar(label: String, value: Float, valueText: String,
                fillColor: NSColor, range: ClosedRange<Float>)
   }
   ```

   Row heights are fixed per variant (single: 18pt — TypeScale.numeric;
   pair: 18pt; bar: 22pt — bar+label stacked). Encode as static constants
   on `Row`. The layout is intentionally rigid: the dashboard reads as a
   set of identical instruments, not a CSS flexbox playground.

   Do NOT add `func render(...)` to either type. Rendering lives in
   `DashboardCardRenderer` so cards remain pure data describable from
   tests.

2. NEW FILE — `DashboardCardRenderer.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift`

   ```
   public struct DashboardCardRenderer: Sendable {
       public init() {}
       /// Render `layout` onto `textLayer` at top-left `origin`.
       /// Returns the Y coordinate immediately below the card so callers
       /// can stack cards vertically with `Spacing.sm` between them.
       @discardableResult
       public func render(
           _ layout: DashboardCardLayout,
           at origin: CGPoint,
           on textLayer: DashboardTextLayer,
           cgContext: CGContext       // for bar geometry — same context the
                                       // text layer draws into; expose via a
                                       // new internal accessor on the layer.
       ) -> CGFloat
   }
   ```

   Internal layout rules (do not invent — match these exactly):

   - Title row: `.label` size, `.medium` weight, `.prose` font,
     `Color.textMuted`, `tracking: TypeScale.labelTracking` (1.5),
     UPPERCASE the input string at the call site (do not mutate at
     render time — UPPERCASE is a *visual* convention but the source
     string passes through unchanged so tests can read it back).
   - Single-value row: label left in `.body / .regular / .prose /
     textMuted`. Value right-aligned in `.numeric / .medium / .mono /
     valueColor`. Right edge = `origin.x + width - padding`.
   - Pair row: same as single, then a vertical 1px divider tinted
     `Color.border` at the midpoint, then the right label/value.
   - Bar row: label top-left in `.label / .medium / .prose / textMuted`.
     Bar below at full inner width, height 6pt, corner radius 1pt.
     Background fill = `Color.surfaceRaised`. Foreground fill = sliced
     from centre (range straddles 0): negative values fill left of
     centre, positive values fill right. Clamp `value` to `range`.
     Numeric value text right-aligned next to the bar in `.body /
     .regular / .mono / textBody`.

   Right-edge clipping: every `drawText` call computed for the right
   column (`origin.x + width - padding`) must use `align: .right`. The
   bar geometry is bounded by `padding` on both inner edges — a card's
   bar can never overflow its declared width.

   Card chrome (background + border): drawn as 2 `CGPath` operations
   *before* any text — rounded rect (radius `Spacing.xs` = 4) filled
   with `Color.surface` at 0.92 alpha (the cards float over visuals,
   slight transparency lets the visualizer breathe through), stroked
   1px with `Color.border`. This is the ONE place where alpha < 1 is
   acceptable in the dashboard — see `.impeccable.md` "no
   glassmorphism unless purposeful": the chrome over a moving
   visualizer IS the purposeful case.

3. MINOR CHANGE — `DashboardTextLayer.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardTextLayer.swift`

   Expose the underlying `CGContext` via a new internal accessor:

   ```
   /// Internal access for renderers that need direct CGPath geometry
   /// (e.g. card chrome, bar charts). External callers must prefer
   /// `drawText`.
   internal var graphicsContext: CGContext { cgContext }
   ```

   No other changes. Do not add a `drawRect` method to the text layer —
   the layer's job is text. Geometry sits in the renderer.

4. NEW TEST FILE — `DashboardCardRendererTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardCardRendererTests.swift`

   Six `@Test` functions in one `@Suite("DashboardCardRenderer")`:

   a. **`layoutHeight_matchesSumOfRows`**: build a 3-row layout
      (single + pair + bar), assert `layout.height` == padding + title
      + rowSpacing×3 + 18 + 18 + 22 + padding (encode the math
      explicitly so future row-height edits surface as test failures).

   b. **`render_threeRowCard_pixelVerifyLabelPositions`**: build the
      same 3-row card, render to a 320×200 `DashboardTextLayer`,
      sample alpha at 4 known pixel positions:
        - Title row baseline at (padding, padding + label-ascent)
          must have alpha > 64 (label drawn).
        - Single-value label at (padding, …) alpha > 64.
        - Single-value value's *right edge* at (width - padding - 1, …)
          alpha > 64 — confirms right-alignment lands inside the card.
        - Below the card (y > layout.height + 4) alpha == 0 — confirms
          the card does not paint outside its declared height.

      Use the `pixelAt` helper from `DashboardTextLayerTests`; either
      copy it (preferred — keeps test files independent) or hoist into
      a shared `DashboardTestHelpers.swift` if you do, document the
      decision in commit message.

   c. **`render_cardNearRightEdge_clipsCorrectly`**: place a 280pt-wide
      card at `origin.x = canvasWidth - 280` on a 512×200 canvas.
      Sample 5 pixels at `x = canvasWidth - 1` (the rightmost column).
      None should have alpha > 200 from a *text* glyph — text right-
      aligned to `width - padding` cannot reach the canvas edge if the
      card is at most `width` wide. (Border alpha CAN appear on the
      rightmost stroke pixel — that is correct chrome.)

   d. **`render_barRow_negativeValueFillsLeft`**: build a single-row
      layout with `.bar(label:"BASS", value:-0.5, valueText:"-0.50",
      fillColor: .coral, range: -1...1)`. Render. Sample two pixels:
        - left of centre at `x = origin.x + padding + (innerWidth/4)`
          on the bar row's y — alpha > 200, channel matches coral.
        - right of centre at `x = origin.x + width - padding -
          (innerWidth/4)` — alpha < 50 (no fill).

   e. **`render_barRow_positiveValueFillsRight`**: same layout but
      `value: +0.5`. Mirror-image assertions.

   f. **`render_pairRow_dividerVisible`**: build a pair row, render,
      sample at the midpoint x — assert one column of pixels in
      `Color.border` exists between the left value and the right
      label.

   Pixel-format reminder: `.bgra8Unorm`, `(b, g, r, a)` byte order in
   `getBytes()`. Reuse `pixelAt`/`readPixels` semantics from
   `DashboardTextLayerTests`.

   Skip pattern (no Metal device): use `withKnownIssue("No Metal device
   available") {}` exactly as `DashboardTextLayerTests` does. Do NOT
   silently skip — silent skips have already disappeared regression
   surfaces (CLAUDE.md "What NOT To Do").

5. ARTIFACT
   Add a `savePNGArtifact` call to test (b) writing
   `card_three_row.png` to the same `.build/dash1_artifacts/` dir
   already used by `DashboardTextLayerTests`. This is the artifact
   Matt will eyeball during M7-style review of the cards.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT wire any card into `RenderPipeline`, `PlaybackView`,
  `DebugOverlayView`, or any renderer encoder. DASH.6 owns wiring.
- Do NOT define what metrics each card shows. DASH.3/4/5 own data
  binding.
- Do NOT add interactive state (hover, focus, selection). The
  dashboard is read-only telemetry.
- Do NOT animate anything. Cards repaint each frame from current
  state; transitions live above this layer.
- Do NOT introduce a `DashboardTheme` or runtime token override. The
  tokens are static; that's the contract.
- Do NOT add chart sparklines, history rings, or graph plotting. Bar
  rows are bounded geometry only. Spectral Cartograph remains the home
  of time-series visualisation.
- Do NOT add a card builder DSL beyond the three row variants. Adding
  variants is a separate increment with explicit Matt approval.

────────────────────────────────────────
DESIGN GUARDRAILS (.impeccable.md)
────────────────────────────────────────

The design context demands restraint. Apply these as hard constraints:

- **No side-stripe borders**. The card chrome is a full 1px border or
  nothing. Never `border-left: 4px solid var(--purple)`. (impeccable
  BAN 1)
- **No gradient text or gradient fills**. Bar foregrounds are solid
  color; status colors come from the token palette unchanged.
  (impeccable BAN 2)
- **No drop shadows on cards**. The 1px tinted border on the
  surface-tinted background is the depth cue. Drop shadows read as
  generic AI dashboard.
- **Whitespace as signal**. Padding inside cards is generous
  (`Spacing.md` = 12pt); row spacing is tight (`Spacing.xs` = 4pt).
  The contrast between padding and row gap is the visual rhythm.
- **Color carries meaning**. `valueColor` for hero numerics: coral
  for energy/action moments, teal for analytical readouts, purple for
  session-presence, textHeading for neutral. NEVER decorate a number
  in coral when it's not active; NEVER decorate in purple when there
  is no session presence to convey.
- **No iconography**. The dashboard is typographic. Status letters
  ("L" for locked, "U" for unlocked) replace icons in DASH.3+, but
  the layout engine itself is text and bars only.

If a row variant *needs* to communicate state via icon-like glyph in
DASH.3+, the bitmap-glyph approach from `SpectralCartographText` is the
precedent — strictly defer until a future increment proves the need.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters. Each step must pass before proceeding.

1. **Build (engine)**: `swift build --package-path PhospheneEngine`
   — must succeed with zero warnings on touched files.

2. **Build (app)**: `xcodebuild -scheme PhospheneApp -destination \
   'platform=macOS' build 2>&1 | tail -3` — must end
   `** BUILD SUCCEEDED **`.

3. **Test (focused)**: `swift test --package-path PhospheneEngine \
   --filter "DashboardCardRenderer|DashboardTextLayer|DashboardTokens|\
   DashboardFontLoader"` — all 18 tests pass (12 from DASH.1 + 6 new).

4. **Test (full)**: `swift test --package-path PhospheneEngine` — full
   suite green except the two pre-existing flakes
   (`MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` and
   `AppleMusicConnectionViewModel`'s timing test). Any other failure
   is a regression caused by this increment — diagnose before
   committing.

5. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml \
   --quiet PhospheneEngine/Sources/Renderer/Dashboard/ \
   PhospheneEngine/Tests/PhospheneEngineTests/Renderer/` — zero
   violations on touched files.

6. **Artifact eyeball** (manual): open
   `.build/dash1_artifacts/card_three_row.png` in Preview. Verify:
   - Card has subtle purple-tinted background, 1px border.
   - Title in muted UPPERCASE, generous padding.
   - Single-value row reads cleanly: label left muted, value right
     bright.
   - Pair row's divider is visible but not loud.
   - Bar row's bar reads as a single instrument, not a UI widget.
   - Card is NOT a clipart admin-dashboard tile. If it is, the
     padding/typography/color choices are wrong — re-read
     .impeccable.md before tuning.

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** — Phase DASH §Increment DASH.2:
   flip status to ✅ with the date. Update the "Done when" checklist
   to all-checked. Add a one-line implementation summary.

2. **`docs/DECISIONS.md`** — append D-082 covering:
   - The fixed-width / no-flex card decision (rigid layout = visual
     consistency across all instruments).
   - The text-layer-vs-renderer split (pure data + pure renderer).
   - The 0.92 alpha card chrome as the single sanctioned glassmorphic
     surface.
   - The "no card icons in the layout engine" constraint and why
     (typographic identity).

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X] DASH.2
   — Metrics card layout engine` entry covering files added, tests
   added, what's intentionally NOT in this increment, decision IDs,
   test-suite count delta.

4. **`CLAUDE.md` Module Map** — under `Renderer/Dashboard/`, add:
   - `DashboardCardLayout` — value type, fixed-width card description.
   - `DashboardCardRenderer` — composes drawText + bar geometry.

────────────────────────────────────────
COMMITS
────────────────────────────────────────

Three commits, in this order. Each must pass tests at the commit
boundary; do not stack failures.

1. `[DASH.2] dashboard: add DashboardCardLayout + DashboardCardRenderer`
   — sources only (`DashboardCardLayout.swift`,
   `DashboardCardRenderer.swift`, the `graphicsContext` accessor on
   `DashboardTextLayer.swift`).

2. `[DASH.2] dashboard: add 6 card-renderer tests`
   — `DashboardCardRendererTests.swift` plus shared helper hoist if
   you chose that route.

3. `[DASH.2] docs: ENGINEERING_PLAN, DECISIONS D-082, release note,
   CLAUDE.md module map`
   — docs only.

Local commits to `main` only. Do NOT push to remote without explicit
"yes, push" approval.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **Test (b) right-edge alpha sample is brittle.** Right-aligned text
  ends at `x = origin.x + width - padding`; sampling at exactly that
  x might land in inter-glyph whitespace. If the assertion is flaky,
  sample a 3-pixel column and require any cell > 64 — do NOT widen
  the assertion to "alpha > 0 anywhere on the row" (defeats the
  purpose).

- **Bar geometry rendering through CGContext while text renders
  through Core Text in the same buffer.** The contexts share memory.
  Order of operations matters: paint chrome first (rect fill +
  stroke), then bars (rect fills), then text (CTLineDraw on top of
  chrome and bars). If you reverse the order text glyphs get painted
  over by the bar fill.

- **`Spacing.xs` corner radius (4pt) on a 12pt-padded card may look
  too sharp at 320pt width.** If the artifact eyeball shows the
  corners reading as boxy, escalate to `Spacing.sm` (8pt). Do NOT
  cross 12pt — the dashboard is precise, not soft.

- **Bar row at `range: -1...1` with a value of exactly 0 should draw
  no foreground fill.** Verify your fill-rect math: `width = abs(value
  / range.upperBound) * (innerWidth / 2)`. A value of 0 → width 0 →
  no fill rectangle drawn. Test (d)/(e) cover positive/negative; if
  you want a 7th test for the zero case, add it — but don't expand
  scope further.

- **STOP and report instead of forging ahead** if:
  - Any test from the existing 12 breaks (token/layer/loader). DASH.2
    must not regress DASH.1.
  - SwiftLint introduces violations on touched files.
  - The artifact eyeball produces output that looks like a
    rounded-rectangle admin tile with drop shadow — that means the
    chrome painting order is wrong or the design rules above were
    not internalised.
  - You find yourself adding a 4th row variant, a flex-width card,
    or a sparkline. None are in scope; pause and surface the
    pressure.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- DASH.1 layer: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardTextLayer.swift`
- DASH.1 tokens: `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift`
- DASH.1 tests (pixel sampling pattern): `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardTextLayerTests.swift`
- Bitmap-glyph precedent (for DASH.3+, NOT this increment):
  `PhospheneEngine/Sources/Presets/Shaders/SpectralCartograph.metal` and
  `Sources/Renderer/SpectralCartographText.swift`
- Design context: `.impeccable.md` (palette, typography, anti-patterns)
- D-081: dashboard infrastructure decision
- D-081 amendment: token spec alignment (DASH.1.1)
- CLAUDE.md: Increment Completion Protocol, Visual Quality Floor, What
  NOT To Do
