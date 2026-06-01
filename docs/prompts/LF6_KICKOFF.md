# Claude Code Session Prompt — Increment LF.6: Album Artwork Surface (LF path-first)

## Context

LF.5 (commit `e9443e9f`, shipped 2026-05-28) persists ID3 / Vorbis / MP4-atom artwork bytes alongside each cached LF entry as a sibling `artwork.bin` file. The data lands cleanly: `PreviewAudio.extractArtwork` runs during `analyzeAndPersist`, `PersistentStemCache.store(...)` writes the bytes, `PersistentStemCache.load(...)` reads them back into `Entry.artworkData: Data?`. Nothing past the cache layer consumes the bytes — they sit on disk waiting for a UI surface.

LF.6 surfaces those bytes. The minimum-viable scope is: **render the LF-cached artwork in the `TrackInfoCardView` chrome during playback**. That's the smallest atomic shipment that delivers real product value.

While auditing the surface, two related gaps came up that LF.6 must decide on:

**Gap A — LF currently shows "—" for track info.** The streaming path sets `engine.currentTrack` via `makeTrackChangeCallback` in `VisualizerEngine+Capture.swift:190`. The LF path **never** publishes `TrackMetadata` to `currentTrack`. Today, every LF playback session renders `TrackInfoCardView` with `trackInfo == nil` — the title shows as `—` (line 22 of `TrackInfoCardView.swift`) and the artist row is hidden entirely. The track title from the `TrackIdentity` (sourced from ID3 / Vorbis tags at LF.5) sits in the orchestrator's plan but never reaches the chrome. This is invisible today because most users haven't watched LF mode's chrome auto-hide-then-reappear closely enough to notice it shows placeholder text.

**Gap B — Streaming path constructs `TrackMetadata(artworkURL: nil)` always.** `StreamingMetadata.swift:237` constructs the metadata struct without ever passing an `artworkURL`. The streaming connectors (`SpotifyWebAPIConnector`, AppleScript bridges) don't surface artwork URLs even when the upstream API returns them. So while `TrackMetadata.artworkURL: URL?` exists in the schema, no production code path ever populates it.

**LF.6 fixes Gap A as a prerequisite (you can't render artwork in a card that's already showing placeholder text without first making the card render real text). Gap B is an explicit decision point — see Pre-Flight Audit step 1.**

## What LF.6 explicitly DOES

* **L1 — Engine surface.** Carry the LF cache's `artworkData: Data?` forward from `LocalFilePrepResult` into the engine's published surface so the App layer can read it without reaching back into `PersistentStemCache`.
* **L2 — Publish `TrackMetadata` for LF sessions.** Construct a `TrackMetadata` from the LF `TrackIdentity` (title/artist/album) + cached artwork, set it on `engine.currentTrack` at LF session start AND at every `advanceLocalFileQueue` track change. Fixes the `—` placeholder gap.
* **L3 — `TrackInfoCardView` artwork slot.** Add a 48 × 48 pt thumbnail slot leading the text column. Renders the LF cache's artwork bytes via `NSImage(data:)`. Falls back to a restrained local-file glyph (matches `LocalSourceConnectionView`'s tile aesthetic from GAP A) when artwork is absent.
* **L4 — Artwork-bytes-to-display projection.** Add a Data → NSImage decode-and-downsize helper in App layer; cache the decoded image keyed by track identity so per-frame chrome re-renders don't re-decode. Hold to ≤ 64 px native target size (128 px @2x retina) regardless of source bytes — embedded artwork commonly ships 600 × 600 to 3000 × 3000 px and rendering raw is wasteful.

## What LF.6 explicitly does NOT do

* **Streaming-path artwork fetch.** Wiring Spotify Web API `album.images[]` URLs + iTunes Search artwork URLs + an image-fetch + on-disk image cache is its own increment (LF.6.streaming or U.12). LF.6's `TrackInfoCardView` redesign accepts a `Data?` input; streaming path continues to pass `nil`. The streaming chrome stays unchanged at LF.6.
* **`TrackChangeAnimationView` artwork.** The boundary-cross center-card stays typographic per impeccable's "feel typographic, not icon-led" principle (`.impeccable.md` §3.6). If product reads otherwise after LF.6 lands, follow up as a discrete design pass.
* **`EndedView` replay-CTA thumbnail.** The CTA stays text-only.
* **`Recents submenu` thumbnails.** Menu items rendering NSImage thumbnails on macOS requires `NSMenuItem.image` work that doesn't compose cleanly with the GAP E typographic refresh and adds menu-load-time latency on cache miss. Defer.
* **`PreparationProgressView` track-row artwork.** Artwork is extracted DURING `analyzeAndPersist` — it isn't available at the moment preparation rows render. Adding artwork here would require lifting extraction into a pre-analysis pass. Defer.
* **Artwork extraction from the streaming-path's PreviewAudio.** The Spotify-preview / iTunes-Search preview clips are 30 s mp3 stubs without embedded artwork. Different fetch chain — out of scope.
* **Animation on artwork load.** Artwork appears when ready, no separate fade. The existing chrome opacity-animate-in is sufficient.
* **User-supplied artwork override.** Right-click → Set artwork… is its own feature, not LF.6.

## Required Reading

In dependency order:

1. `CLAUDE.md` — Increment Completion Protocol (the closeout obligations), the "@MainActor / Sendable" rules for the new publisher field, the "all user-facing strings externalised" + "Tooltips do not lie" invariants.
2. `.impeccable.md` — Design Context section. The LF.6 visual treatment must respect "PlaybackView is the product" + "feel typographic, not icon-led" + "color carries meaning. Never decorate with it" principles. Artwork is content, not decoration.
3. `docs/UX_SPEC.md` § PlaybackView state contract — what the chrome is allowed to show, the auto-hide semantics, the curator vs. viewer distinction.
4. `docs/ENGINEERING_PLAN.md` § Increment LF.5 — confirms the artwork-bytes persistence pipeline + notes "Album-art display in `PlaybackView` (data captured at LF.5; UI is LF.6)" as the explicit follow-up.
5. `PhospheneEngine/Sources/Session/PersistentStemCache.swift` — focus on `Entry.artworkData` (lines 82-96), `load(_:)` (the artwork.bin read at line 291-299), and `store(...)` (the artwork.bin write at line 347-358).
6. `PhospheneEngine/Sources/Session/PreviewAudio+Metadata.swift` — `extractArtwork(at:)` returns `Data?` of whatever the container shipped (JPEG for m4a/mp4, JPEG or PNG for mp3/flac).
7. `PhospheneEngine/Sources/Shared/AudioFeatures+Metadata.swift` — `TrackMetadata` schema: title/artist/album/genre/duration/`artworkURL`/source. Note `artworkURL` is `URL?` and is never populated today.
8. `PhospheneApp/VisualizerEngine.swift` — find the `@Published var currentTrack: TrackMetadata?` declaration (line 71). This is the publisher LF must populate.
9. `PhospheneApp/VisualizerEngine+Capture.swift:189-202` — streaming path's `currentTrack = event.current` assignment. The LF analogue should mirror this shape inside `handleLocalFileReady` and `advanceLocalFileQueue`.
10. `PhospheneApp/VisualizerEngine+LocalFilePlayback.swift` — the LF entry-point file. `runLocalFilePreparation` (the off-main worker), `handleLocalFileReady` (the `.ready` observer), `advanceLocalFileQueue` (track advance). All three sites need touch.
11. `PhospheneApp/ViewModels/PlaybackChromeViewModel.swift:42-47` — `TrackInfoDisplay` already has an unused `albumArtURL: URL?` field with a `TODO(U.future): populate from MetadataPreFetcher`. LF.6 needs to either replace this with `albumArtData: Data?` OR add a parallel field — see Pre-Flight Audit step 3.
12. `PhospheneApp/Views/Playback/TrackInfoCardView.swift` — current text-only layout. LF.6's L3 redesigns this file.
13. `PhospheneApp/Views/LocalSourceConnectionView.swift` (GAP A) — for the no-artwork fallback glyph aesthetic. The visual register the artwork slot's fallback should match.
14. `~/Documents/phosphene_sessions/2026-05-28T19-42-50Z/session.log` — the post-BUG-021 verification log. Confirms LF.5's `STEM_CACHE_HIT: artworkBytes=...` lines (search the LF.5 closeout cache-write logs in your local sessions dir for the line shape).
15. `PhospheneEngine/Tests/PhospheneEngineTests/Session/PersistentStemCacheTests.swift` — the LF.5 artwork roundtrip test pattern (5 LF.5 tests added). LF.6's new tests use the same fixture-with-embedded-art shape.

## Pre-Flight Audit (do this before writing any code)

1. **Decision: streaming-path artwork in LF.6, or deferred?** Confirm Matt's intent. Default recommendation: **defer to LF.6.streaming or U.12**. Reason: streaming artwork requires (a) Spotify Web API `album.images[]` capture in `SpotifyWebAPIConnector` + (b) iTunes Search artwork URL capture in the Apple Music path + (c) an image-fetch chain + (d) on-disk image cache (separate from the LF stem cache). That's three subsystems vs. LF.6's single-surface change. State the decision at the top of the closeout.

2. **Decision: visual treatment of the artwork slot in `TrackInfoCardView`.** Three viable shapes — Matt picks one at pre-flight (do NOT just pick the default and ship):
   * **(a) Cornered thumbnail (recommended).** 48 × 48 pt artwork tile leading the existing text column. Card grows from ~200-320 pt wide to ~270-380 pt. Maintains the "ghost chrome" register; reads as record sleeve adjacent to track text. Closest to the brand register (Braun audio component).
   * **(b) Stacked card.** Album art on top (full card width, square-aspect, ~180 × 180 pt), text below. Album-shape card, total ~200 × 260 pt. Stronger "now playing" moment; takes more screen real estate.
   * **(c) Full-bleed behind text.** Artwork stretched + heavily blurred as the card's backdrop; text overlaid. Replaces the existing `overlayBackdrop()`. Strongest visual statement; reads as "the chrome is dressed by the music". Highest risk of legibility regression — the existing backdrop is calibrated for contrast.

   The kickoff implementation defaults to (a). If Matt picks (b) or (c), the L3 task scope expands proportionally.

3. **Decision: `TrackInfoDisplay.albumArtURL` keep / replace / parallel?** The existing field is `URL?` (commented for a future fetched-URL surface). LF.6's bytes come from `Data?`. Three shapes:
   * **(i) Replace** `albumArtURL: URL?` with `albumArtData: Data?`. Clean break; the existing TODO is satisfied by a different mechanism. Recommended for LF.6.
   * **(ii) Add parallel** `albumArtData: Data?` alongside the existing `albumArtURL: URL?`. The view-model carries both; the view picks the first non-nil. Keeps room for streaming-path URL chain later.
   * **(iii) Use `Image` directly.** Decode in the view-model layer; pass `Image?`. Couples view-model to AppKit decode — only ok if view-model already imports AppKit (it does, per line 31).

   (iii) is fastest but bypasses the test surface (view-model tests would need Image fixtures). Recommend (i) for clean break OR (ii) if Matt wants streaming-path artwork imminently. The kickoff defaults to (i).

4. **Decision: no-artwork fallback glyph.** When `artwork.bin` is absent (track has no embedded art, OR the track is a streaming-path session pre-LF.6.streaming), what shows in the slot?
   * **(a) Generic local-file glyph** (a 24 × 24 SF Symbol like `music.note.list` tinted purple-muted, on a `surface-raised` background). Matches LocalSourceConnectionView's tile glyphs. Recommended.
   * **(b) Generated abstract pattern from track hash.** Sigil-style; visually distinctive per track. Cooler but adds shader / canvas work — deferred.
   * **(c) Hide the slot entirely.** Card reverts to text-only shape. Lowest visual signal; if half a session has artwork and half doesn't, the chrome geometry shifts back and forth per track, distracting.

   Default (a). Defer (b) to LF.7+ polish.

5. **Confirm the artwork pipeline.** Read these in order:
   * `PersistentStemCache.load(_:)` line 291-299 — confirms `artworkData: Data?` lands in `Entry`.
   * `VisualizerEngine+LocalFilePlayback.swift:386-412` — `loadFromPersistentDisk` returns `LocalFilePrepResult` which currently doesn't carry artwork. Need to add a field.
   * `VisualizerEngine+LocalFilePlayback.swift:427-483` — `analyzeAndPersist` builds `LocalFilePrepResult` from `FreshAnalysisOutcome`. `FreshAnalysisOutcome` already has `artwork: Data?` (line 567) but discards it after persist. Need to thread it through.
   * `LocalFilePrepResult` definition (search the file) — add `artworkData: Data?` field.

6. **Confirm `currentTrack` consumers.** `engine.currentTrack` feeds:
   * `PlaybackChromeViewModel.currentTrack` (via publisher injection at `ContentView.swift:142`).
   * `MIRPipeline.currentTrackName / currentArtistName` (via the streaming track-change callback only; LF doesn't drive these and may not need to — confirm with Matt).
   * `DebugOverlayView` (line 29 + 57 — purely informational).
   * `VisualizerEngine+Capture.swift:56-57` — used for capture-recording metadata. LF path does record sessions; needs the populated `currentTrack` to surface track names in session.log.

   Cross-check that publishing `TrackMetadata` from LF path doesn't break `makeTrackChangeCallback`'s assumptions. The callback reads `event.previous / event.current` from the streaming-metadata publisher only; LF path bypasses it. No conflict.

7. **Order of operations.** L1 → L2 → L3 → L4. L1+L2 are engine-side plumbing (uncontroversial — closes Gap A as a side effect). L3 is the visual change requiring the design decision from step 2. L4 (decode cache) can interleave with L3.

Write up the audit findings (under ~250 words) + the three decisions before starting L1. The decisions need Matt's sign-off via short reply — do not assume the defaults.

## Task Breakdown

### Task L1 — Carry artwork bytes through the LF prep pipeline

Files: `PhospheneApp/VisualizerEngine+LocalFilePlayback.swift`.

* Add `artworkData: Data?` field to `LocalFilePrepResult`.
* In `loadFromPersistentDisk(...)` — read `entry.artworkData` from the cache hit and pass it into the result.
* In `analyzeAndPersist(...)` — thread `outcome.artwork` into the result (don't drop it after persist).
* In `runLocalFilePreparation` (the off-main worker that calls both) — confirm the field survives.

No behaviour change visible to the user; just plumbing.

Verification: `swift test --package-path PhospheneEngine --filter "PersistentStemCacheTests|LocalFilePlaybackFormatCoverageTests"` stays green. No new test required for this step alone (covered by existing roundtrip).

Commit: `[LF.6-L1] LocalFilePlayback: thread artwork bytes through prep pipeline`.

### Task L2 — Publish `TrackMetadata` for LF sessions (closes Gap A)

Files: `PhospheneApp/VisualizerEngine+LocalFilePlayback.swift`.

Two sites:

**Site 1 — `handleLocalFileReady()`.** After `lastResolvedTrackIdentity = identity` (line 136), construct and publish:

```swift
self.currentTrack = TrackMetadata(
    title: identity.title,
    artist: identity.artist,
    album: identity.album,
    duration: identity.duration,
    source: .unknown
)
```

(The fact that artworkURL is nil here is fine — LF doesn't use the URL field. Artwork bytes flow through a different mechanism in L3.)

**Site 2 — `advanceLocalFileQueue(direction:)`.** Right after `lastResolvedTrackIdentity = nextIdentity` (line 258), the same construction.

Both sites need a corresponding artwork-bytes publisher path — see L3. Decide at L2 time whether `currentTrack`'s publisher carries the artwork via the cache lookup (App layer reads `engine.persistentStemCache?.load(...)` on the new identity) OR via a new `@Published var currentTrackArtworkData: Data?` field on `VisualizerEngine`.

The kickoff recommends the **second** option (new `@Published var currentTrackArtworkData: Data?`) because (a) cache lookup at L2 time is synchronous and the cache is on-disk so we're not bouncing through actor boundaries on every track change, (b) the view-model already has one publisher binding per piece of data and adding one more is cleaner than threading cache references into the view-model.

Implementation sketch for the artwork publisher:

```swift
@Published var currentTrackArtworkData: Data?
// ...
// In handleLocalFileReady, after publishing currentTrack:
self.currentTrackArtworkData = persistentStemCache
    .flatMap { try? $0.load(for: identity) }
    .flatMap { $0.artworkData }
// In advanceLocalFileQueue, the same pattern for nextIdentity.
```

Verification:
* Build clean. Lint clean (file is large — verify `file_length` warning doesn't tip into error).
* Engine + app suite green.
* Manual smoke: open a 2-track folder, verify the top-left chrome shows the actual track title (not `—`) and that the title updates on Next/Prev.

Commit: `[LF.6-L2] VisualizerEngine: publish TrackMetadata + artwork data for LF sessions`.

### Task L3 — `TrackInfoCardView` artwork slot

Files: `PhospheneApp/Views/Playback/TrackInfoCardView.swift`, `PhospheneApp/ViewModels/PlaybackChromeViewModel.swift`.

**ViewModel change:** Add a published projection from `engine.currentTrackArtworkData`. Per Pre-Flight decision 3, recommend replacing `albumArtURL: URL?` on `TrackInfoDisplay` with `albumArtData: Data?`. Add a `currentTrackArtworkDataPublisher: AnyPublisher<Data?, Never>` init parameter; bind it to update `currentTrack.albumArtData`. Wire from `ContentView.swift` (mirroring the existing publisher injection at line 142-143).

**View change:** Add a leading 48 × 48 pt `HStack` slot to `TrackInfoCardView`. Visual treatment is the Pre-Flight decision-2 winner. For the default (Option a, cornered thumbnail):

* `HStack(alignment: .top, spacing: 12)` wrapping the artwork slot + the existing text column.
* Artwork slot: `48 × 48 pt`, `cornerRadius(6)`, no border. Inside: `Image(nsImage: ...)` for the decoded artwork, or the fallback glyph (`Image(systemName: "music.note.list")` on a `surface-raised` background tile) when nil.
* Card `maxWidth` grows from `320` → `380` to accommodate.
* When `albumArtData` is nil AND the source is a streaming session, hide the artwork slot entirely (text-only fallback so the chrome doesn't render an out-of-place glyph for streaming).

Add accessibility labels: artwork slot gets `.accessibilityHidden(true)` (the title/artist text in the existing accessibility-combine already covers content).

Verification:
* Build clean. Lint clean.
* Manual smoke: artwork visible for LF tracks with embedded art (the LF.5 tempo fixtures all have art — verify on `love_rehab.m4a`). Fallback glyph visible for tracks without art (need a no-art fixture — see Task L4 fixture work). Streaming-path chrome unchanged.
* Snapshot/Visual: capture a Debug-build screenshot of the chrome with artwork and without artwork; attach to closeout.

Commit: `[LF.6-L3] TrackInfoCardView: add artwork slot with cornered thumbnail`.

### Task L4 — Decode-and-downsize helper + cache

Files: new `PhospheneApp/AlbumArtworkCache.swift`.

* Single-purpose helper. Public API: `static func image(for data: Data, identity: TrackIdentity) -> NSImage?`.
* On first call for a given `(data.hashValue, identity)` pair: decode via `NSImage(data:)`, downsize to 64 pt max edge (128 px native @2x via `representation(...).draw(in:)` or `bestRepresentation(for:context:hints:)`), cache the result in an `NSCache<NSString, NSImage>`.
* On subsequent calls: cache hit returns cached `NSImage`.
* Decoded-image cache size cap: 20 entries (covers a long playlist's worth of recent tracks).
* No persistent disk cache; the source bytes are already persisted by LF.5's `artwork.bin`, no need to double-cache.
* Thread-safe: `NSCache` already is.

Wire from `TrackInfoCardView`: when `albumArtData` is non-nil, pass to `AlbumArtworkCache.image(for:identity:)`; render the result. The view becomes:

```swift
if let data = albumArtData,
   let identity = /* the identity for this track */,
   let image = AlbumArtworkCache.image(for: data, identity: identity) {
    Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))
}
```

(Note: passing `identity` into `TrackInfoCardView` means extending the published `TrackInfoDisplay` with a cache key. The simplest cache key is `title + "|" + artist`.)

Verification:
* Build clean. Lint clean. New file added to `project.pbxproj` (four sections per CLAUDE.md project-file rule — verify).
* New test `AlbumArtworkCacheTests.swift`: decode a known JPEG, verify size ≤ 64 pt, verify cache hit on second call. Use a small embedded JPEG fixture (~200 bytes hex-string ok) so no on-disk fixture is needed.

Commit: `[LF.6-L4] AlbumArtworkCache: decode + downsize + LRU cache`.

### Task L5 — No-artwork fixture for manual smoke + automated tests

* Locate one of the LF.5 fixtures and verify with `mediainfo` or similar which ones do/don't have embedded artwork. Most tempo fixtures (`love_rehab`, `there_there`) ship art from the source release. If none of the LF.5 fixtures are art-free, create a small synthetic fixture (e.g. a 2 s silence m4a authored via `afconvert` with no `--art` flag).
* Add to `LocalFilePlaybackFormatCoverageTests.swift` (or a new `Session/LocalFileArtworkPipelineTests.swift`): assert (a) cache hit on an art-having fixture surfaces `artworkData != nil`, (b) cache hit on an art-free fixture surfaces `artworkData == nil`, (c) `TrackInfoDisplay.albumArtData` updates on track advance.

Commit: `[LF.6-L5] LocalFile: artwork pipeline tests + no-art fixture`.

### Task L6 — Closeout

* `docs/QUALITY/KNOWN_ISSUES.md` — no new entry (LF.6 is forward progress, not a defect).
* `docs/RELEASE_NOTES_DEV.md` — `[dev-YYYY-MM-DD-X] LF.6 — album-art display in PlaybackView chrome` entry. Mention Gap A is closed as a side effect.
* `docs/ENGINEERING_PLAN.md` — LF.6 entry above LF.5.fix.2. Done-when criteria, files touched, follow-up: LF.6.streaming for streaming-path artwork fetch.
* `docs/DECISIONS.md` — new entry. Likely D-133 (verify with the `project_decisions_numbering.md` memory note before assigning). Document: (a) LF-first scope choice, (b) the visual-treatment decision Matt picked at Pre-Flight, (c) the `albumArtData: Data?` schema choice, (d) the no-artwork fallback glyph choice.
* `docs/ARCHITECTURE.md` § Session Preparation — extend with the LF.6 publisher path. § Key Types — note `TrackMetadata.artworkURL: URL?` remains nil-for-LF; LF artwork flows through `currentTrackArtworkData` instead.
* Closeout report per CLAUDE.md "Increment Completion Protocol." Attach the L3 chrome screenshots.

Commit: `[LF.6] docs: ENGINEERING_PLAN + RELEASE_NOTES + DECISIONS + ARCHITECTURE`.

## Critical Invariants

* All existing engine tests stay green. Pass count ≥ 1358 (LF.5 baseline).
* All existing app tests stay green. Pass count ≥ 305.
* SwiftLint `--strict` clean on every touched file. `VisualizerEngine.swift` is already past `file_length` warning with disable comments; check whether L2's additions tip it past the `type_body_length` cap (currently disabled with a `swiftlint:disable type_body_length` blanket per the LF.5.fix work).
* `Scripts/check_user_strings.sh` exit 0 — any new user-facing string in `TrackInfoCardView` (e.g. fallback-glyph accessibility label) must route through `String(localized:)`.
* `Scripts/check_sample_rate_literals.sh` exit 0.
* New file `AlbumArtworkCache.swift` registered in `project.pbxproj` across all four PBX sections.
* `TrackInfoCardView`'s existing snapshot / unit tests (if any — verify in `Tests/`) continue to pass with the new artwork slot.
* No new dependency. `NSImage(data:)` + `NSCache` are AppKit-standard. No SwiftUI `AsyncImage` (it's URL-driven and we have bytes).
* The artwork slot is **off the main thread for decode**. `NSImage(data:)` initialization is fast but downsize draws to a context — verify it doesn't block frame compositing on track change. If it does, move decode to `Task.detached` and publish the decoded image via a separate published field.
* `currentTrack` and `currentTrackArtworkData` publishers update on the **same MainActor tick** — never publish artwork before the title or vice versa, otherwise the chrome flashes "—" + artwork briefly on track advance. The LF.6-L2 implementation must set both `@Published` fields back-to-back inside the same MainActor block.
* Streaming-path behaviour is byte-identical to pre-LF.6. `engine.currentTrack` continues to be set by `makeTrackChangeCallback` for streaming, `currentTrackArtworkData` stays `nil` on streaming sessions.
* `TrackInfoCardView` does not change shape (vertical/horizontal flow, padding, font sizes) for streaming sessions — only LF sessions get the artwork slot. Verify the streaming chrome remains pixel-identical via comparison screenshots.
* No artwork persistence beyond LF.5's existing `artwork.bin` sibling.
* Tooltips do not lie (CLAUDE.md) — if the artwork slot gains any hover affordance (e.g. a "click to open album" right-click), don't ship the affordance with no handler.

## Verification Commands

```sh
# Engine + app builds + per-task verification
swift test --package-path PhospheneEngine --filter "PersistentStemCacheTests|LocalFilePlaybackFormatCoverageTests|AlbumArtworkCacheTests" 2>&1 | tail -5
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail -3
swiftlint lint --strict --config .swiftlint.yml <touched files>
Scripts/check_user_strings.sh

# Full regression at closeout
swift test --package-path PhospheneEngine 2>&1 | tail -5
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test 2>&1 | tail -3
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail -3

# Manual smoke (Matt)
# 1. Launch Debug build. Open Local Folder → 2-track fixture (use a folder with both art-having and art-less tracks).
# 2. Verify TrackInfoCardView shows: artwork thumbnail (left) + title + artist + preset name + state pill.
# 3. Compare against pre-LF.6 build: streaming session chrome should be visually identical.
# 4. Press Next. Verify (a) title updates (not stuck on previous), (b) artwork updates within one frame of the title.
# 5. Open a single-file session for a track WITHOUT embedded artwork: verify the fallback glyph renders, no crash.
# 6. End session. Verify TrackInfoCardView fades out cleanly (no orphan artwork frame).
```

## Commit Cadence

1. `[LF.6-L1] LocalFilePlayback: thread artwork bytes through prep pipeline`
2. `[LF.6-L2] VisualizerEngine: publish TrackMetadata + artwork data for LF sessions`
3. `[LF.6-L3] TrackInfoCardView: add artwork slot with cornered thumbnail`
4. `[LF.6-L4] AlbumArtworkCache: decode + downsize + LRU cache`
5. `[LF.6-L5] LocalFile: artwork pipeline tests + no-art fixture`
6. `[LF.6] docs: ENGINEERING_PLAN + RELEASE_NOTES + DECISIONS + ARCHITECTURE`

If Pre-Flight Audit step 2 picks Option (b) or (c), L3 splits into two commits (geometry change + content render). Surface that split at decision time.

## Overall Done-When Gate

* `git log --oneline -8` shows the LF.6 commit chain.
* Engine + app test suites green; pass counts at-or-above baseline.
* SwiftLint + strings gates clean.
* New `AlbumArtworkCacheTests` runs and passes (decode + downsize + cache hit assertions).
* New `LocalFileArtworkPipelineTests` (or extension to existing format-coverage tests) runs and passes.
* Manual smoke (Matt-driven) confirms:
  - LF chrome shows real title (not `—`) + real artwork on tracks with embedded art.
  - Fallback glyph visible on tracks without artwork — no crash, no layout shift.
  - Streaming chrome visually unchanged.
  - Track advance updates artwork in the same frame as title.
* `docs/ENGINEERING_PLAN.md` has the LF.6 entry above LF.5.fix.2.
* `docs/RELEASE_NOTES_DEV.md` has the LF.6 entry.
* `docs/DECISIONS.md` has the new entry (D-133 likely — check numbering memory).
* Closeout report per CLAUDE.md "Increment Completion Protocol." Two chrome screenshots attached (with art / without art).

## Out of Scope (Do Not Do)

* Streaming-path artwork fetch (Spotify Web API `album.images[]`, iTunes Search artwork). Separate increment (LF.6.streaming / U.12).
* `TrackChangeAnimationView` artwork — boundary card stays text-only.
* `EndedView` replay-CTA thumbnail.
* `Recents submenu` thumbnails (`NSMenuItem.image`).
* `PreparationProgressView` track-row artwork (extraction happens DURING analysis, not before).
* Artwork as full-bleed PlaybackView background (the visualizer IS the background per impeccable §5).
* User-supplied artwork override / right-click menus.
* Animation on artwork swap — the existing chrome opacity-animate covers it.
* `AsyncImage` or any URL-driven image loading. The artwork is bytes, not URLs.
* New persisted cache. LF.5's `artwork.bin` is the persistence layer; LF.6 adds an in-memory decode cache only.

## Stuck-State Guidance

* **`NSImage(data:)` crashes or returns nil on real-world fixtures.** Embedded artwork is occasionally malformed (truncated mid-write, wrong magic bytes). `NSImage(data:)` returns nil on those — render the fallback glyph. Verify your decoder does not assume validity.

* **Decoded image's `size` is in DPI-aware points, not pixels.** `NSImage` `size` is points; `representations[0].pixelsWide` is pixels. Downsize math must use pixels to keep the 64-pt target consistent. Test on a 3000 × 3000 px source: downsized output should be ≤ 128 px native and the rendered view should be 48 × 48 pt sharp.

* **Track advance shows artwork BEFORE title.** L2 published the artwork publisher first. Fix by setting both in the same MainActor block, in the order title-first then artwork-second.

* **`type_body_length` cap tripped on `VisualizerEngine.swift`.** Extract the L2 LF-currentTrack-publishing into a small helper file `VisualizerEngine+LocalFileMetadata.swift`. Match the existing extension-file naming convention.

* **`TrackInfoDisplay.albumArtURL` removal breaks downstream code.** Search the codebase: `grep -rn "albumArtURL"` should turn up only the U.future TODO comment + the line that sets it to nil. If it turns up anywhere else, that consumer needs migration first.

* **Cache-hit-on-load test fails because the fixture has no embedded art.** Verify with `mediainfo love_rehab.m4a` or `ffprobe -v error -select_streams v:0 -show_entries stream=codec_type love_rehab.m4a`. If genuinely no art, file a separate "fixture art curation" task and use a synthetic art-having fixture for L5.

* **Streaming-session chrome shifts geometry.** L3's `TrackInfoCardView` change should gate the artwork slot on `currentTrack.albumArtData != nil OR isLocalFileSession`. Verify the streaming path's `currentTrack.albumArtData` stays nil at all times (no inadvertent publisher cross-binding).

* **The cache-decode helper runs on MainActor and hitches frame compositing on track advance.** Profile with Instruments. If hitch is > 4 ms on track change, move decode to `Task.detached(priority: .userInitiated)` and publish via a separate `@Published var decodedAlbumArt: NSImage?` field. Sometimes the simple call site is hot enough.

* **The artwork data exists in cache but doesn't reach the publisher.** Cache lookup in L2 reads `engine.persistentStemCache?.load(for: identity)`. The identity must match the one used at LF.5's store time exactly. Compare `Hashable` field-by-field if a mismatch is suspected. Common cause: `duration` was rounded differently between store and load.

* **No fixtures are art-free.** Skip L5's "art-free fixture" path — instead add a unit test that constructs a synthetic `PersistentStemCache.Entry` with `artworkData: nil` and asserts the view path renders the fallback. The fixture path is nice-to-have, not load-bearing.
