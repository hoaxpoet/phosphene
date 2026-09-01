# DS.2 — findings for `uzume-site`

What building `SourceChoice` in the app taught, reported rather than committed:
DS.2 does not write to `../uzume-site` (D-228 — the site owns the design system,
the app owns product facts). Each finding names the app file that motivated it.

Companion to `docs/reviews/DS.1/UPSTREAM-FINDINGS.md`.

---

## 1. `SourceChoice` as built, against `COMPONENTS.md`'s description

`COMPONENTS.md` §Native product component extraction describes the component in
two lines: a source, and four variants — *"Navigation, immediate action,
unavailable with reason, and unavailable with recovery action."* The built API
agrees, but collapses four variants into **three enum cases**:

```swift
enum Affordance {
    case navigation
    case action(() -> Void)
    case unavailable(reason: String, recovery: Recovery?)
}
```

The last two variants are one case with an optional `Recovery`, because they
differ only in whether a button is drawn — same fill, same absence of hover,
same "reason replaces subtitle" rule. Four cases would have made
`.unavailable(reason:)` and `.unavailable(reason:recovery:)` two spellings of one
state, and every `switch` would have handled them identically.

**Suggested:** describe the component as **three affordances, one of which
optionally carries a recovery action**. The four-variant framing is right about
what the Curator sees and wrong about the shape of the type.

*Motivated by:* `UzumeApp/Views/Components/SourceChoice.swift`

---

## 2. The document does not say who owns navigation, and that is the load-bearing fact

The census's §State ownership rules to preserve is explicit about view models and
stores but says nothing about navigation. For this component it is the single
most important constraint: if `SourceChoice` had built its own `NavigationLink`,
`ConnectorPickerViewModel` would have lost sole ownership of `connectorPath`, and
`AppleMusicConnectionWrapper` / `OAuthSpotifyConnectionWrapper` — which exist
precisely because rebuilding those view models orphans in-flight OAuth and
auto-retry Tasks (CA.6-FU-3) — would have been back at risk.

**Suggested:** add a rule to §State ownership rules to preserve —
*a presentational component renders the affordance, never the navigation; the
consumer owns the destination and the path.*

*Motivated by:* `UzumeApp/Views/ConnectorPickerView.swift`,
`UzumeApp/ViewModels/ConnectorPickerViewModel.swift`

---

## 3. The census called these "near-identical"; the accessibility behaviour was not

`PHOSPHENE-COMPONENT-CENSUS.md` rows 103–104 describe the local tile as
*"deliberately parallels connector tile."* Visually true. But the connector tiles
carried a VoiceOver hint and the local tiles carried none, and the connector
tiles had no hover where the local tiles did. A census that compares rendered
appearance will keep reporting pairs as near-duplicates when their accessible
and interactive behaviour differ — and those differences are what a
consolidation is forced to resolve.

**Suggested:** the component inventory should record, per candidate, whether the
duplicates agree on **hint, hover, focus and disabled semantics**, not only on
layout. That is the column that predicts how much a consolidation actually
decides.

*Motivated by:* the deleted `ConnectorTileView` and `LocalSourceActionTile`

---

## 4. `EXPERIENCE_MODEL.md` §Add music is satisfied, and names the rule the component now enforces

*"Source selection states requirements before commitment"* is exactly what
`.unavailable(reason:recovery:)` encodes: the reason replaces the subtitle, so an
unavailable source states its condition instead of advertising a capability it
cannot honour. Worth promoting from prose into the component contract — it is a
rule about what the type may render, not only about how a screen reads.

*Motivated by:* `SourceChoice.detail`

---

## 5. Release-contract items this increment could NOT demonstrate

§Release contract lists seven obligations. Against `SourceChoice`:

| Obligation | Status |
|---|---|
| Real content at min/max supported sizes | **Not demonstrated.** The fixed-font ratchet now covers both files, so the tiles scale with Dynamic Type, but no capture at the extremes exists. |
| Keyboard and VoiceOver behavior | **Partly.** Label and hint strings are unit-pinned; live VoiceOver announcement and keyboard focus order are pending Matt's M7. |
| Focus, disabled, loading, empty, error, recovery states | **Partly.** Disabled and recovery are built and previewed. Focus is untested. Loading/empty/error do not apply to this component. |
| Reduced motion and increased contrast | **Not demonstrated.** No motion is introduced, so reduced-motion is vacuous here; **increased contrast is untested** — the tile relies on `surface` vs `surfaceRaised` vs `surfaceSelected`, three near-neighbours on the dark ramp, and that is exactly the separation an increased-contrast setting is expected to widen. |
| Light and dark appearance | **Will not be demonstrated, by decision.** Uzume is always dark ([D-232]); the component contains no appearance branch. The contract's "light and dark" clause does not apply to this app and should say so. |
| Localization expansion and long labels | **Not demonstrated.** Only `en.lproj` exists. The tile's `HStack` gives the text column whatever the icon and trailing content leave; a long German title with a recovery button beside it is the untested worst case. |
| Viewer/Curator separation during performance | **Not applicable.** Source choice happens before the performance begins. |

**Suggested:** the contract should mark which obligations are *vacuous* for a
given app (light appearance here) versus *unmet*. Today both read as failures,
which makes the checklist less useful the moment an app makes a deliberate
platform decision.

---

## 6. `--color-text-tertiary` and `--color-text-disabled` are the same value

Both are `#a4a8a2` in the dark block of `tokens.css`. `SourceChoice` selects
between them by meaning — tertiary for an available subtitle, disabled for an
unavailable reason — so the code documents an intent the palette does not
currently render. Either the roles should diverge, or one should be dropped and
the survivor named for what it is.

This is a token-level observation, adjacent to the DS.1 findings about
`UzumeRadius` and the adaptive system-colour mapping.

*Motivated by:* `UzumeApp/DesignSystem/UzumeTokens+App.swift:48-49`,
`UzumeApp/Views/Components/SourceChoice.swift`

---

## 7. A behaviour the app dropped, so upstream knows it was considered

The old `AccessibilityLabels.connectorTileLabel` fell back to the localized
"Not available" string when a disabled tile carried no caption.
`.unavailable(reason:)` takes a **non-optional** `String`, so that fallback has no
call site and was removed. If a future `SourceChoice` consumer wants an
unavailable tile with no stated reason, that is a new variant and a new decision
— not a silent `nil`.

*Motivated by:* `UzumeApp/Services/AccessibilityLabels.swift`

---

## 8. A source screen contradicts §Add music's own rule — in the app's copy, not its structure

`EXPERIENCE_MODEL.md` §Add music: *"Each source names its actual capabilities; a source never
promises what it cannot honour."* The app's source picker breaks the converse — it makes a blanket
*disclaimer* that is false for one of the three sources under it. The footer reads "Uzume reads
what's playing. It doesn't control playback," while the Local files tile leads to a path where
Uzume owns the audio and ships stop / previous / play-pause / next.

The rule as written guards against a source over-promising. This is a source **under**-promising,
on a shared surface that cannot be true for every tile above it. Worth extending the rule:
*capability statements belong to a source, not to a screen that lists several.*

Filed app-side as **COPY-001**; the wording is a product decision, and `LocalPlaybackTransport`'s
own contract line in `COMPONENTS.md` ("available only when Uzume owns local playback") is the
correct model.

*Motivated by:* `UzumeApp/Views/ConnectorPickerView.swift:124`,
`UzumeApp/Views/Playback/LocalFileTransportBar.swift`

---

## 9. The release contract should ask whether identifiers reach the accessibility tree

§Release contract asks for "Keyboard and VoiceOver behavior". DS.2's M7 read the live accessibility
tree of both builds and found the three local tiles announcing their **parent view's** identifier
rather than their own, while the connector tiles announce theirs (repeated four times, joined by
`-`). Unit tests pin the identifier constants and pass; the constants simply never arrive.

A contract item that says "VoiceOver behavior" is satisfied by a label and a hint being correct —
which they are. The gap is one level down. **Suggested:** add *identifiers resolve in the
accessibility tree, verified against a running build* as its own obligation. It is the only item in
the list that a unit test can appear to satisfy while being false at runtime.

Filed app-side as **A11Y-001**; pre-existing, identical before and after the consolidation.

*Motivated by:* `UzumeApp/Views/LocalSourceConnectionView.swift`,
`UzumeAppTests/SourceChoiceIdentifierTests.swift`
