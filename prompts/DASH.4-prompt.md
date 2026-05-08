Execute Increment DASH.4 — Stem energy card.

Authoritative spec: docs/ENGINEERING_PLAN.md §Phase DASH §Increment DASH.4.
Authoritative design: .impeccable.md §Aesthetic Direction (Color, Typography),
§State-Specific Design Notes, §Anti-Patterns. Read both before writing
any code.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. DASH.3 must have landed. Verify with
   `git log --oneline | grep '\[DASH\.3\]'` — expect three commits
   ending with `[DASH.3] docs: ENGINEERING_PLAN, DECISIONS D-083, …`.

2. Confirm DASH.3's API surface is in place:
   `grep -E "case progressBar|case bar|case singleValue" \
     PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
   — expect 3 row variants. If `.progressBar` is missing, DASH.3 has not
   landed; stop.

3. Confirm `BeatCardBuilder` exists:
   `test -f PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift`
   — file must exist.

4. Decision-ID numbering: D-083 covers DASH.3. The next available number
   is **D-084**. Verify with
   `grep '^## D-0' docs/DECISIONS.md | tail -3`.

5. `StemFeatures` lives at
   `PhospheneEngine/Sources/Shared/StemFeatures.swift` with the four
   `*EnergyRel: Float` fields you will read (`vocalsEnergyRel`,
   `drumsEnergyRel`, `bassEnergyRel`, `otherEnergyRel`, MV-1 / D-026).
   `StemFeatures.zero` exists. No changes to `StemFeatures` are in scope
   for DASH.4.

6. `default.profraw` may be present in the repo root. Ignore.

────────────────────────────────────────
GOAL
────────────────────────────────────────

The second live dashboard card. DASH.3 produced the BEAT card driven by
beat-grid state; DASH.4 produces the STEMS card driven by stem-energy
deviation primitives.

This increment is **data binding only**. It does NOT add a new row
variant (`.bar` from DASH.2 already covers signed deviation). It does
NOT wire the card into PlaybackView (DASH.6). It does NOT compose
multiple cards (DASH.6). It produces:

  1. A `StemsCardBuilder` struct that maps `StemFeatures` →
     `DashboardCardLayout` (title `STEMS`, four rows DRUMS / BASS /
     VOCALS / OTHER, each `.bar` with range −1.0…1.0).
  2. Sign-correct visual feedback: positive `*EnergyRel` fills right of
     bar centre, negative fills left, zero draws no foreground (the
     dim background bar dominates — the .impeccable "absence-of-signal"
     stable state).
  3. Uniform fill colour across all four stems for v1 (`Color.coral`).
     Per-stem palette tuning is an explicit DASH.4.1 follow-up if Matt's
     eyeball review surfaces monotony — do NOT pre-empt it.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

1. NEW FILE — `StemsCardBuilder.swift`
   Path: `PhospheneEngine/Sources/Renderer/Dashboard/StemsCardBuilder.swift`

   ```
   /// Maps a `StemFeatures` snapshot to a `DashboardCardLayout` for the
   /// STEMS card. Pure function — no Metal, no allocations beyond the
   /// layout itself. Safe to call every frame.
   public struct StemsCardBuilder: Sendable {
       public init() {}
       public func build(
           from stems: StemFeatures,
           width: CGFloat = 280
       ) -> DashboardCardLayout
   }
   ```

   The builder produces a card titled `STEMS` with **four** rows in this
   order (matching .impeccable's percussion-first reading order):

   - **DRUMS**  (.bar): label `DRUMS`,  value `stems.drumsEnergyRel`,
     valueText `String(format: "%+.2f", drumsEnergyRel)`,
     fillColor `Color.coral`, range `-1.0 ... 1.0`.
   - **BASS**   (.bar): label `BASS`,   value `stems.bassEnergyRel`,   …
   - **VOCALS** (.bar): label `VOCALS`, value `stems.vocalsEnergyRel`, …
   - **OTHER**  (.bar): label `OTHER`,  value `stems.otherEnergyRel`,  …

   `*EnergyRel` is centred at 0 with typical range ±0.5 (CLAUDE.md "AGC
   authoring implication"). Range `-1.0 ... 1.0` gives headroom for
   loud transients without clipping; typical content reads in the
   inner 50 % of the bar — visible motion, not full-bar saturation.

   valueText format: `%+.2f` always shows the sign (`+0.42` / `-0.30` /
   `+0.00`). The leading `+` for non-negative values is the Milkdrop-
   convention readback users expect when the bar is signed.

   Uniform `Color.coral` for all four rows in v1. The DASH.4.1 amendment
   slot is reserved for per-stem palette tuning if monotony reads on the
   artifact eyeball — do NOT introduce per-stem colours pre-emptively
   here. `.impeccable.md` "purposeful colour" is satisfied by the bar
   *direction* (left/right of centre) carrying the stem-state semantics;
   colour reinforces, not differentiates, in v1.

   The builder is a pure function. No clamping is required at the
   builder layer (the `.bar` row variant clamps to `range` defensively
   in `drawBarFill`). The builder passes the raw `*EnergyRel` value
   through unchanged so test assertions can read it back.

2. NEW TEST FILE — `StemsCardBuilderTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/StemsCardBuilderTests.swift`

   Six `@Test` functions in `@Suite("StemsCardBuilder")`:

   a. **`build_zeroSnapshot_producesAllZeroBars`**: feed
      `StemFeatures.zero`, assert `title == "STEMS"`, `rows.count == 4`.
      For each row, switch-extract the `.bar` payload and assert
      `value == 0`, `valueText == "+0.00"`, `fillColor` matches
      `Color.coral` (sRGB-channel comparison with 0.01 tolerance,
      same pattern as `BeatCardBuilderTests.colorMatches`),
      `range == -1.0 ... 1.0`.

   b. **`build_positiveDrums_setsBarValueAndText`**: snapshot with
      `drumsEnergyRel = 0.42`, others zero. Assert row[0] (DRUMS)
      `value == 0.42` (exact, no clamp at builder layer), valueText
      `"+0.42"`. Other rows still at 0.

   c. **`build_negativeBass_setsBarValueAndText`**: snapshot with
      `bassEnergyRel = -0.30`, others zero. Assert row[1] (BASS)
      `value == -0.30`, valueText `"-0.30"`.

   d. **`build_mixedSnapshot_rowOrderAndPayloadsCorrect`**: snapshot
      with all four `*EnergyRel` distinct (e.g. drums 0.5, bass −0.4,
      vocals 0.2, other −0.1). Assert row order DRUMS / BASS / VOCALS /
      OTHER by label, and each row's value matches the corresponding
      input field. Confirms field-to-row mapping has no transposition
      bug.

   e. **`build_largeValue_passesThroughUnclampedAtBuilderLayer`**:
      snapshot with `drumsEnergyRel = 1.5` (above range upper bound).
      Assert builder emits `value == 1.5` unchanged — the renderer's
      `drawBarFill` is the clamp authority, not the builder. Document
      via test name + inline `// ` comment that the clamp lives in the
      renderer.

   f. **`build_widthOverride_passesThrough`**: call
      `build(from: .zero, width: 320)`, assert resulting layout's
      `width == 320`. Default-arg test mirroring
      `BeatCardBuilderTests.build_widthOverride_passesThrough`.

   Use the same switch-pattern row extractor + sRGB-channel colour
   comparator pattern from `BeatCardBuilderTests`. Copy the helpers
   locally rather than hoisting (file-independence convention).

3. ARTIFACT
   Add a `savePNGArtifact` call to `StemsCardBuilderTests` test (d)
   (`build_mixedSnapshot_…`). Render the builder's output via
   `DashboardCardRenderer` onto a 320×220 `DashboardTextLayer` with
   the deep-indigo backdrop helper from DASH.2.1 / DASH.3. Write to
   `.build/dash1_artifacts/card_stems_active.png`. This is the artifact
   Matt will eyeball during M7-style review of the live STEMS card. Use
   the same `BeatCardBuilderTests`-style local `savePNGArtifact` +
   `writeTextureToPNG` helper pattern; do NOT reach into
   `DashboardCardRendererTests`.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT modify `StemFeatures`. The four `*EnergyRel` fields you need
  already exist (MV-1 / D-026, floats 17–24).
- Do NOT introduce a `StemEnergySnapshot` value type or any other
  intermediate snapshot. The builder takes `StemFeatures` directly —
  the four-field read is cheap and a new snapshot type would just
  duplicate the existing MV-1 contract.
- Do NOT wire `StemsCardBuilder` into `RenderPipeline`, `PlaybackView`,
  `DebugOverlayView`, or any encoder. DASH.6 owns wiring.
- Do NOT compose multiple cards into a dashboard layout. DASH.6 owns
  multi-card composition and screen positioning.
- Do NOT add per-stem fill colours. v1 is uniform `Color.coral` across
  all four rows. If monotony reads on the artifact, that becomes a
  DASH.4.1 amendment ticket — do NOT pre-empt it. The DASH.2 →
  DASH.2.1 redesign cycle exists precisely so amendments don't bloat
  the originating increment.
- Do NOT add a fifth row (e.g. `TOTAL`, mood, frame budget). The STEMS
  card is exactly DRUMS / BASS / VOCALS / OTHER. Frame budget is
  DASH.5; mood would belong on a future MOOD card.
- Do NOT clamp the value at the builder layer. The renderer's
  `drawBarFill` is the clamp authority (defence-in-depth lives at one
  layer, not two). Test (e) regression-locks this.
- Do NOT switch row variant from `.bar` to `.progressBar`. Stem energy
  deviation is naturally signed (above-average kick = positive,
  ducked-bass = negative). `.progressBar` is for unsigned ramps only
  (D-083). A unsigned-only stems card would lose the duck-information.
- Do NOT add Equatable to `Row` or its associated values (D-082,
  D-083). NSColor comparison is non-trivial; tests use switch-pattern
  extraction.
- Do NOT use `*EnergyDev` (positive-only `max(0, *EnergyRel)`). Dev
  primitives are for accent thresholds in shader code, not for signed
  visual feedback. The plan's "stemEnergyDev" wording is loose; the
  done-when checklist's "negative = left of centre" makes the intent
  unambiguous.

────────────────────────────────────────
DESIGN GUARDRAILS (.impeccable.md)
────────────────────────────────────────

- **Direction carries meaning.** Bar fill direction (left vs. right of
  centre) is the load-bearing signal: a kick raises drums above its
  recent average → bar grows right; a duck drops it below → bar grows
  left. The colour (`Color.coral`) reinforces but does not
  differentiate. This is .impeccable's "Color carries meaning" rule
  applied to direction: the *sign* of the deviation is the meaning.
- **Stable zero state.** When all four stems sit at AGC average
  (`*EnergyRel == 0`), all four rows draw no fill — the dim background
  bar dominates. This is a stable, readable visual state, not a
  transient. No "loading" or "—" placeholders.
- **No icons. No animation.** The card is typographic + bar geometry.
  Per-frame rebuild from current state; transitions live above this
  layer.
- **Whitespace as signal.** Don't tighten row spacing. The DASH.2.1
  rhythm holds.
- **Uniform colour for v1, not multi-colour.** A four-bar card rendered
  in four different stem colours risks reading like a stereo VU meter
  or DAW mixer — categorically wrong product cue. Coral × 4 reads as
  "one instrument, four channels" which is what STEMS *is*. Tune in
  DASH.4.1 if and only if the artifact eyeball flags monotony.

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
   --filter "BeatCardBuilder|StemsCardBuilder|DashboardCardRenderer|\
   DashboardTextLayer|DashboardTokens|DashboardFontLoader"` — all 33
   tests pass (12 DASH.1 + 6 DASH.2.1 + 6 BeatCardBuilder + 3
   ProgressBar + 6 StemsCardBuilder).

4. **Test (full)**: `swift test --package-path PhospheneEngine` — full
   suite green except known pre-existing flakes
   (`MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget`,
   `MemoryReporter.residentBytes` env-dependent). Any other failure
   is a regression — diagnose before committing.

5. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml \
   --quiet PhospheneEngine/Sources/Renderer/Dashboard/ \
   PhospheneEngine/Tests/PhospheneEngineTests/Renderer/` — zero
   violations on touched files.

6. **Artifact eyeball** (manual): copy `.build/dash1_artifacts/
   card_stems_active.png` into the project tree (`mkdir -p
   /Users/braesidebandit/Documents/Projects/phosphene/.build/
   dash1_artifacts && cp …`) — see DASH.2.1 / DASH.3 closeout for the
   path resolution bug. Open in Preview. Verify:
   - Card chrome is purple-tinted (visible against the deep-indigo
     backdrop), not black.
   - Title `STEMS` reads in muted UPPERCASE.
   - Row order top-to-bottom: DRUMS / BASS / VOCALS / OTHER.
   - DRUMS bar fills RIGHT of centre, ~50 % toward the right limit;
     valueText reads `+0.50` in coral.
   - BASS bar fills LEFT of centre, ~40 % toward the left limit;
     valueText reads `-0.40`.
   - VOCALS bar fills RIGHT, ~20 %; valueText `+0.20`.
   - OTHER bar fills LEFT, ~10 %; valueText `-0.10`.
   - Card does NOT read as a stereo VU meter or DAW mixer. If it does,
     the colour-uniformity rule was not internalised — re-read
     §DESIGN GUARDRAILS before tuning.
   - If the four rows reading in identical coral feels visually
     monotone, that is the trigger for a DASH.4.1 amendment ticket
     (NOT a within-DASH.4 fix). Surface the observation; do not
     unilaterally introduce per-stem colours.

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** — Phase DASH §Increment DASH.4:
   flip status to ✅ with the date. Update the "Done when" checklist.
   Add a one-line implementation summary noting the new
   `StemsCardBuilder` and the v1 uniform-coral colour decision.

2. **`docs/DECISIONS.md`** — append D-084 covering:
   - Why `.bar` (signed) and not `.progressBar` (unsigned) — `*EnergyRel`
     is naturally signed; using unsigned would lose duck information.
   - Why the builder reads `StemFeatures` directly rather than
     introducing a `StemEnergySnapshot` analog of `BeatSyncSnapshot`
     (DASH.3 reused an existing diagnostic snapshot; DASH.4 has the
     four needed fields already on the live `StemFeatures` type and a
     new snapshot would only duplicate the MV-1 contract).
   - The uniform-coral v1 colour decision and the explicit DASH.4.1
     amendment slot for per-stem palette tuning.
   - Why the builder does not clamp values (clamp lives in renderer,
     defence-in-depth at one layer).
   - Range `-1.0 ... 1.0` rationale (headroom over typical ±0.5
     `*EnergyRel` envelope; loud transients still readable).
   - The four-row layout is exactly DRUMS / BASS / VOCALS / OTHER —
     percussion-first reading order matches .impeccable Beat-panel
     precedent.

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X] DASH.4
   — Stem energy card` entry covering files added, tests added,
   what's intentionally NOT in this increment (DASH.6 wiring, per-stem
   palette deferral), decision IDs, test-suite count delta.

4. **`CLAUDE.md` Module Map** — under `Renderer/Dashboard/`, add:
   - `StemsCardBuilder` — pure function `StemFeatures →
     DashboardCardLayout` for the STEMS card (4 rows: DRUMS / BASS /
     VOCALS / OTHER). Uniform `Color.coral` fill v1; per-stem palette
     tuning reserved for DASH.4.1 amendment.

────────────────────────────────────────
COMMITS
────────────────────────────────────────

Two commits, in this order. Each must pass tests at the commit boundary.

1. `[DASH.4] dashboard: add StemsCardBuilder + 6 builder tests`
   — `StemsCardBuilder.swift` + `StemsCardBuilderTests.swift`. The
   builder is a pure function over `StemFeatures` — no Metal needed
   for the unit tests; only test (d)'s artifact render touches a
   device. No new row variant means no renderer change in this
   increment (one less commit than DASH.3).

2. `[DASH.4] docs: ENGINEERING_PLAN, DECISIONS D-084, release note,
   CLAUDE.md module map`
   — docs only.

Local commits to `main` only. Do NOT push to remote without explicit
"yes, push" approval.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **Field-to-row transposition.** With four near-identical fields
  (`{vocals,drums,bass,other}EnergyRel`) and four nearly-identical
  rows, swapping two field reads is the most likely silent bug
  (e.g. row labelled VOCALS shows `bassEnergyRel`). Test (d)'s mixed
  snapshot is the load-bearing assertion — keep distinct values for
  each stem so any swap surfaces.

- **`*EnergyRel` vs `*EnergyDev` confusion.** The plan's done-when
  uses "stemEnergyDev" loosely. Dev is positive-only (`max(0, rel)`)
  and would lose the negative-direction signal entirely. Use Rel.
  If you find yourself reading any `*EnergyDev` field, stop —
  that's the wrong field family for a signed bar.

- **Range mismatch with renderer clamp.** `.bar` clamps to its
  declared `range` in `drawBarFill`. If the builder declares
  `range: -0.5 ... 0.5` but the snapshot carries 0.6, the renderer
  clamps and the bar reads full-right when the underlying value isn't
  actually saturated. Stick with `-1.0 ... 1.0` so typical content
  reads at ~50 % bar fill (visible motion) and outliers don't clip.

- **Per-stem colour temptation.** It will be tempting to tag drums
  coral, bass purpleGlow, vocals statusYellow, other textBody for
  "design polish". Don't. Status colours are reserved for status
  semantics (D-083 lock-state mapping). A four-colour stems card
  reads as a DAW mixer — wrong product cue. The DASH.4.1 amendment
  slot exists precisely for tuning here; let Matt's eyeball decide.

- **STOP and report instead of forging ahead** if:
  - Any DASH.1 / DASH.2 / DASH.3 test breaks (12 + 6 + 6 + 3 = 27
    must remain green). DASH.4 must not regress prior increments.
  - SwiftLint introduces violations on touched files.
  - The artifact eyeball shows the STEMS card reading as a stereo VU
    meter or DAW mixer — that means the colour-uniformity rule
    wasn't internalised.
  - You find yourself adding a fifth row, an animation, per-stem
    colours, or a `StemEnergySnapshot` value type. None are in scope;
    pause and surface the pressure.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- DASH.3 builder (canonical pattern): `PhospheneEngine/Sources/Renderer/Dashboard/BeatCardBuilder.swift`
- DASH.3 builder tests (canonical helpers, copy locally): `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/BeatCardBuilderTests.swift`
- DASH.2 layout: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardLayout.swift`
- DASH.2 renderer: `PhospheneEngine/Sources/Renderer/Dashboard/DashboardCardRenderer.swift`
- DASH.2.1 STEMS fixture (the original 4-row sketch in tests): `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/DashboardCardRendererTests.swift` (`render_barRow_negativeValueFillsLeft` uses a `STEMS`-titled card)
- DASH.1 tokens: `PhospheneEngine/Sources/Shared/Dashboard/DashboardTokens.swift`
- StemFeatures (D-026 deviation primitives): `PhospheneEngine/Sources/Shared/StemFeatures.swift`
- Design context: `.impeccable.md` (Color section, Aesthetic Direction)
- D-082, D-082.1, D-083: dashboard layout engine + .impeccable redesign + BEAT card binding
- CLAUDE.md: Increment Completion Protocol, Visual Quality Floor, What
  NOT To Do, AGC authoring implication (D-026)
