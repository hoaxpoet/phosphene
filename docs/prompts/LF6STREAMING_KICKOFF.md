# Claude Code Session Prompt — Increment LF.6.streaming: Streaming-Path Artwork Surface

## Context

LF.6 (kickoff at `docs/prompts/LF6_KICKOFF.md`) lands the chrome-side album-artwork surface for **local-file** sessions: it adds `engine.currentTrackArtworkData: Data?` as the publisher field, redesigns `TrackInfoCardView` with a 48 × 48 pt artwork slot, and ships an in-memory `AlbumArtworkCache` for decode-and-downsize work. The bytes come from the LF.5 `artwork.bin` sibling that's already on disk per cached track.

LF.6 explicitly leaves the **streaming path** unchanged: every Spotify / Apple Music session continues to render the artwork slot with the LF.6 fallback glyph because `currentTrackArtworkData` stays `nil` for those sessions. The TODO is documented in `PlaybackChromeViewModel.swift:42-47` (`albumArtURL: URL?` with `TODO(U.future): populate from MetadataPreFetcher`) and in `StreamingMetadata.swift:237` (the `TrackMetadata(...)` constructor never passes `artworkURL`).

LF.6.streaming closes that gap. The streaming chrome should look indistinguishable from the LF chrome on tracks where artwork is resolvable, and indistinguishable from LF.6's no-art fallback when nothing resolves.

The minimum-viable scope is: **for every streaming track-change, fetch the per-track artwork bytes (Spotify Web API + iTunes Search fallback) and publish them to `engine.currentTrackArtworkData` so the existing LF.6 `TrackInfoCardView` artwork slot renders them**.

The three subsystems this requires:

1. **Capture artwork URLs at connector / metadata-source time.** `SpotifyWebAPIConnector` already parses tracks at [SpotifyWebAPIConnector.swift:228](PhospheneEngine/Sources/Session/Connectors/SpotifyWebAPIConnector.swift:228); the `album.images[]` field is in the same dict it already reads. The Apple Music AppleScript path / Core Audio tap path resolves artwork URLs differently — see the Pre-Flight Audit.
2. **Fetch image bytes from URLs.** A new `StreamingArtworkFetcher` protocol with a URLSession-based default. Cancellable, timeout-bounded, doesn't block the render loop.
3. **Cache fetched bytes on disk across launches.** A new `StreamingArtworkDiskCache` keyed by SHA-256 of the source URL. Separate from the LF.5 stem cache (different lifecycle, different size budget, different eviction semantics).

## What LF.6.streaming explicitly DOES

* **S1 — Spotify connector captures `album.images[]`.** Extend `parseTrack` in `SpotifyWebAPIConnector.swift` to lift the highest-resolution image URL from `track["album"]["images"][0]["url"]` and surface it on `TrackIdentity.spotifyArtworkURL: URL?` (new field, sibling to `spotifyPreviewURL`).
* **S2 — Streaming-metadata resolver layer.** New `StreamingArtworkURLResolver` protocol. Default implementation tries (a) Spotify connector's already-captured `spotifyArtworkURL`, (b) iTunes Search API by title + artist (similar shape to `PreviewResolver`, but querying `artworkUrl100` and upgrading to `600x600bb`). Returns the first non-nil hit or nil.
* **S3 — Image fetcher.** New `StreamingArtworkFetcher` protocol with `func fetch(url:) async throws -> Data`. Default implementation: URLSession, 5-second timeout, plain `data(for:)` call. No request-coalescing in the first cut; if multiple track-changes race we'll see them in profiling.
* **S4 — On-disk byte cache.** New `StreamingArtworkDiskCache` actor. Key = SHA-256 of the source URL string. File on disk = `<hash>.bin` under `~/Library/Caches/com.phosphene.app/streaming-artwork/`. Trim to N MB total on launch and after each write (LRU by access time).
* **S5 — Wire it into the streaming track-change callback.** `StreamingMetadata.swift:237` and / or `VisualizerEngine+Capture.swift:189` (the `makeTrackChangeCallback`) — at every `event.current` track change, kick off `Task { await artworkFlow.update(for: track) }` and publish the resulting `Data?` to `engine.currentTrackArtworkData`.
* **S6 — Tests.** Unit tests for `StreamingArtworkDiskCache` (LRU eviction, persistence roundtrip, missing-file recovery), `StreamingArtworkURLResolver` (Spotify-first, iTunes Search fallback, no-match nil), and a wiring test that asserts `currentTrackArtworkData` updates within N ms of a streaming track change (timing-bounded similar to U.11's debounce tests).

## What LF.6.streaming explicitly does NOT do

* **Apple Music / MusicKit native artwork API.** The MusicKit `Song.artwork` URL is per-token-authenticated and our codebase already routes through iTunes Search for previews. Sticking with iTunes Search keeps one well-trodden code path; if Matt wants MusicKit later it can be a swap in `StreamingArtworkURLResolver`.
* **Real-time tap-path metadata extraction.** When the user is playing audio through the macOS process tap without us knowing the source app, we have no track identity to query. The fallback glyph applies. That's a separate problem from this increment.
* **Image format conversion.** We persist the bytes verbatim (JPEG/PNG/etc. — whatever the API serves). `AlbumArtworkCache` (LF.6) already decodes via `NSImage(data:)` and downsizes.
* **`MetadataPreFetcher` rewiring.** The PlaybackChromeViewModel `albumArtURL: URL?` TODO is misleading — by LF.6 we already replaced it with `albumArtData: Data?`, and LF.6.streaming feeds the same Data publisher. No URL-keyed view-model path.
* **`PreparationProgressView` per-track artwork.** Same out-of-scope rationale as LF.6's L5 line — artwork is fetched lazily after track-change, not during preparation.
* **Mid-track artwork updates / animated swap.** The chrome's existing opacity-animate-in covers it; no separate fade.
* **Public-build telemetry on cache hit-rate.** Internal Logger lines only.
* **Artwork display in `TrackChangeAnimationView` boundary cards.** Stays typographic per `.impeccable.md §3.6`.
* **`Recents` submenu thumbnails for streaming history.** Out of scope (LF.6 itself defers `NSMenuItem.image` per-track thumbnails).

## Prerequisites (hard dependency)

LF.6 must have shipped before this increment runs:

* `engine.currentTrackArtworkData: Data?` publisher exists.
* `PlaybackChromeViewModel.TrackInfoDisplay.albumArtData: Data?` exists (LF.6-L3 chose option (i)).
* `AlbumArtworkCache.image(for:identity:)` exists in `PhospheneApp/`.
* The `TrackInfoCardView` artwork slot already renders correctly for LF tracks.

If LF.6 hasn't shipped, **stop the session and tell Matt to ship LF.6 first**. This increment doesn't define those surfaces.

## Required Reading

In dependency order:

1. `CLAUDE.md` — Increment Completion Protocol, Defect Handling Protocol (LF.6.streaming is forward progress, but if any pre-existing flake reproduces in the test pass, it's a stop-and-report moment per the protocol), all `Scripts/check_*.sh` invariants for the changed files.
2. `docs/prompts/LF6_KICKOFF.md` (the shipped LF.6 doc) + the LF.6 release-notes entry — exact shape of the LF.6 surface this increment feeds.
3. `PhospheneEngine/Sources/Session/Connectors/SpotifyWebAPIConnector.swift` — `parseTrack` at line 228 is the S1 site. Note how `spotifyPreviewURL` was added (LF.4) for an identical shape — copy that pattern.
4. `PhospheneEngine/Sources/Session/TrackIdentity.swift` — `spotifyPreviewURL` field declaration (S1 extends this struct).
5. `PhospheneEngine/Sources/Session/PreviewResolver.swift` — the iTunes Search call pattern. S2 mirrors the URL-construction + JSON-parse + caching shape.
6. `PhospheneEngine/Sources/Shared/AudioFeatures+Metadata.swift` — `TrackMetadata.artworkURL` already exists in the schema but is never populated. S2 feeds it for the live-track callback path.
7. `PhospheneEngine/Sources/Audio/StreamingMetadata.swift` — line 237's `TrackMetadata(...)` constructor is one of two wiring sites for S5; the other is the engine's `makeTrackChangeCallback`.
8. `PhospheneApp/VisualizerEngine+Capture.swift` — `makeTrackChangeCallback` (line ~189) is where the LF.6 release-notes entry says streaming-side `currentTrack` is published. S5 adds the artwork fetch alongside.
9. `PhospheneApp/AlbumArtworkCache.swift` (LF.6-L4) — the decode-and-downsize layer LF.6.streaming feeds via its `Data?` output.
10. `docs/ARCHITECTURE.md §Session Preparation` — LF.6 added a publisher-path subsection; LF.6.streaming extends it with the streaming flow.
11. The `~/Library/Caches/` directory's macOS semantics — `NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)`. See Apple's File System Programming Guide; the cache is allowed to be purged under disk pressure.

## Pre-Flight Audit (do this before writing any code)

1. **Decision: cache location — `Application Support` (persistent) or `Caches` (system can purge)?** Recommended **(b) Caches**. User-visible trade-off:
   * **(a) Application Support.** Artwork survives across launches indefinitely. Disk usage grows monotonically (capped only by our LRU). Pro: re-opening a recently-played track is always instant. Con: artwork accumulates even when the user has long stopped listening to that track; system never reclaims under low-disk pressure.
   * **(b) Caches** *(recommended)*. macOS can purge under disk pressure. Pro: behaves like every other cache on the system; no user surprise. Con: re-fetching costs one HTTP round-trip after a purge. Matches Spotify's own app's behavior.
   * Default to **(b)** unless Matt has a reason for **(a)**.

2. **Decision: cache size cap.** How much disk should LF.6.streaming consume in the worst case? Recommended **100 MB**. Quick math: a high-res Spotify artwork is ~80 KB JPEG. 100 MB ≈ 1,200 cached tracks at full resolution. The LRU evicts the least-recently-accessed once full. User-visible trade-off:
   * **(a) 50 MB.** Tighter; evicts after ~600 tracks. Reasonable for someone who streams a few sessions a week.
   * **(b) 100 MB** *(recommended)*. Comfortable headroom for a deep streaming history.
   * **(c) 500 MB.** Effectively no cap; user-visible only on disk-usage inspection.

3. **Decision: artwork source order.** Recommended **Spotify-first, iTunes Search second, then nil**. User-visible trade-off:
   * **(a) Spotify + iTunes Search** *(recommended)*. Covers both connector paths. iTunes Search has 20 req/min rate limit — within a session that's plenty (a streaming session sees one track-change per ~3 minutes).
   * **(b) Spotify only.** Reduces scope. Apple Music / Core Audio tap sessions show the fallback glyph until LF.6.streaming.2 lands the iTunes path. Faster shipment, narrower coverage.
   * **(c) Spotify + iTunes Search + MusicKit.** Adds MusicKit as the third source for Apple Music subscribers. Apple Music users would see the highest-res artwork, but it requires MusicKit token plumbing we don't have for the music-library scope. Defer.

4. **Decision: in-flight track-change cancellation.** When the user changes track quickly, the previous fetch is in-flight. Should we cancel it? Recommended **yes, cancel**. The LF.5.fix.3 lessons (Bug B, just shipped) apply: orphaned in-flight tasks waste resources and can race the new track's fetch. Store the in-flight fetch task on `VisualizerEngine`; cancel-and-replace at every track change. State this decision explicitly even though it's an engineering call, because the failure mode (artwork briefly showing the previous track before snapping to the new one) is visible.

5. **Confirm the publisher path.** Read these in order:
   * `PhospheneApp/VisualizerEngine+Capture.swift:189` — track-change callback site (post-LF.6 it publishes `currentTrack`; LF.6.streaming adds artwork alongside).
   * `PhospheneApp/VisualizerEngine.swift` — the `@Published var currentTrackArtworkData: Data?` field LF.6 added.
   * `PhospheneApp/ViewModels/PlaybackChromeViewModel.swift` — the binding from `currentTrackArtworkData` into `TrackInfoDisplay.albumArtData`.

6. **Confirm the URL path.** `SpotifyWebAPIConnector.parseTrack` reads `track["album"]["images"][0]["url"]`. Spotify's API returns images in descending size order; index 0 is always the highest. The URL is HTTPS, no auth needed for the image itself (only the original track fetch needs the access token). Confirm against the Spotify response JSON in `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/spotify_items_response.json` before writing the extractor.

7. **Order of operations.** S1 → S4 → S3 → S2 → S5 → S6. S1 + S4 are independent (one engine field, one app file); S3 is the fetcher used by S5; S2 is the URL resolver used by S5; S5 wires everything; S6 backstops. Each step's tests gate the next.

Write up the audit findings (under ~250 words) + the three decisions before starting S1. The decisions need Matt's sign-off via short reply — do NOT assume the defaults.

## Task Breakdown

### Task S1 — Spotify connector captures artwork URL

Files: `PhospheneEngine/Sources/Session/TrackIdentity.swift`, `PhospheneEngine/Sources/Session/Connectors/SpotifyWebAPIConnector.swift`, `PhospheneEngine/Tests/PhospheneEngineTests/Session/SpotifyWebAPIConnectorTests.swift`.

* Add `spotifyArtworkURL: URL?` to `TrackIdentity` (sibling to `spotifyPreviewURL`).
* `parseTrack` extracts the highest-res image URL: `(track["album"]?["images"] as? [[String: Any]])?.first?["url"] as? String` → `URL.init`.
* New test: extend `SpotifyWebAPIConnectorTests.swift` to assert `spotifyArtworkURL` matches the fixture's `album.images[0].url`.

Verification: `swift test --package-path PhospheneEngine --filter "SpotifyWebAPIConnectorTests"` stays green; the new assertion passes.

Commit: `[LF.6.streaming-S1] SpotifyWebAPIConnector: capture album.images[0].url`.

### Task S4 — On-disk byte cache

Files: new `PhospheneApp/StreamingArtworkDiskCache.swift`. (App-layer, not engine — same rationale as `AlbumArtworkCache`.)

* Actor type. Init takes a `directoryURL: URL` (default: `~/Library/Caches/com.phosphene.app/streaming-artwork/`) and `maxBytes: Int` (default per decision-2).
* `func bytes(for url: URL) async -> Data?` — returns cached bytes or nil. Updates the LRU access time on hit.
* `func store(_ data: Data, for url: URL) async` — writes `<sha256(url)>.bin` and an `<sha256(url)>.access` sentinel for LRU. Trims to `maxBytes` after write (LRU eviction).
* `func clearAll() async` — for tests + a future `Settings → Clear Cache` button.
* Concurrency: actor isolation suffices. Disk I/O within the actor is OK (it's `Caches` so async-detached is overkill — confirm under profiling if it shows up).
* Persistence roundtrip survives launches.
* New file registered in `project.pbxproj` across all four sections per the CLAUDE.md project-file rule.
* New tests: `StreamingArtworkDiskCacheTests.swift` — init / store-read / LRU eviction at cap / persistence roundtrip / clearAll / corrupt-file recovery (returns nil, doesn't crash).

Verification: build clean; new tests pass; `Scripts/check_user_strings.sh` exit 0 (no new user-facing strings expected).

Commit: `[LF.6.streaming-S4] StreamingArtworkDiskCache: SHA-256-keyed LRU cache in Caches/`.

### Task S3 — Image fetcher

Files: new `PhospheneApp/StreamingArtworkFetcher.swift`.

* Protocol `StreamingArtworkFetching` with `func fetch(url: URL) async throws -> Data`.
* Default implementation: URLSession with 5-second timeout. Throws on non-200 / timeout / network failure. The throw is OK — the caller (S5) catches and falls back to nil → fallback glyph.
* Tests: `StreamingArtworkFetcherTests.swift` — stub URLProtocol per `URLProtocolStubTests.swift` pattern. Per the CLAUDE.md URLProtocol invariant, **suite is `@Suite(.serialized)`**.

Verification: build clean; new tests pass.

Commit: `[LF.6.streaming-S3] StreamingArtworkFetcher: URLSession-based protocol`.

### Task S2 — Streaming-metadata artwork resolver

Files: new `PhospheneEngine/Sources/Session/StreamingArtworkURLResolver.swift` + companion tests.

* Protocol `StreamingArtworkURLResolving` with `func resolveArtworkURL(for track: TrackIdentity) async -> URL?`.
* Default implementation: try `track.spotifyArtworkURL` first; if nil, fall through to iTunes Search by title + artist. Cache the result in-memory per-session (avoid re-querying iTunes for the same track in a session).
* iTunes Search call mirrors `PreviewResolver` shape: GET `https://itunes.apple.com/search?term=<artist+title>&media=music&entity=song&limit=1`, parse `results[0].artworkUrl100`, upgrade `100x100bb` → `600x600bb` in the URL string (Apple's CDN supports the swap).
* Tests: stub URLProtocol, `@Suite(.serialized)`. Cases: Spotify URL present (no iTunes hit), Spotify nil + iTunes hit, both nil (returns nil), iTunes 429 (returns nil per the existing PreviewResolver fallback policy).

Verification: `swift test --package-path PhospheneEngine --filter "StreamingArtworkURLResolverTests"` passes. Engine suite stays at-or-above LF.6 baseline.

Commit: `[LF.6.streaming-S2] StreamingArtworkURLResolver: Spotify-first + iTunes Search`.

### Task S5 — Wire fetcher into streaming track-change callback

Files: `PhospheneApp/VisualizerEngine+Capture.swift` (or a new `+StreamingArtwork.swift` extension if `+Capture.swift` is already past `file_length`).

* Engine fields: `streamingArtworkResolver: StreamingArtworkURLResolving`, `streamingArtworkFetcher: StreamingArtworkFetching`, `streamingArtworkDiskCache: StreamingArtworkDiskCache`, `streamingArtworkInFlight: Task<Void, Never>?`.
* New helper: `@MainActor func updateStreamingArtwork(for track: TrackIdentity?) -> Task<Void, Never>`. Cancels `streamingArtworkInFlight`. Resolves URL → check disk cache → if hit, publish bytes; if miss, fetch → write to disk → publish. Stores the new task on `streamingArtworkInFlight`.
* Call site: in `makeTrackChangeCallback`, after the existing `currentTrack` publish, add `streamingArtworkInFlight = updateStreamingArtwork(for: <new identity>)`.
* Publish bytes to `engine.currentTrackArtworkData` on MainActor, ALWAYS in the same MainActor tick as the title publish (per the LF.6 critical invariant about avoiding "—" + artwork flashes).
* If `updateStreamingArtwork` is called with `nil` track (track-cleared event), publish `nil` immediately and return.

Verification:
* Build clean. Lint clean (check `file_length` after the additions — may need an extension split).
* New tests: `StreamingArtworkPublishingTests.swift` (app-layer) — uses stub fetcher + stub resolver. Asserts:
  1. On track-change with resolvable artwork, `currentTrackArtworkData` updates to the stub's bytes within N ms.
  2. On track-change with unresolvable artwork, `currentTrackArtworkData` becomes nil within N ms.
  3. On rapid track-change A → B before A's fetch returns, only B's bytes ever appear in `currentTrackArtworkData` (in-flight cancellation works).

Commit: `[LF.6.streaming-S5] VisualizerEngine: publish streaming artwork on track change`.

### Task S6 — Closeout

* `docs/QUALITY/KNOWN_ISSUES.md` — no new entry (forward progress, not a defect).
* `docs/RELEASE_NOTES_DEV.md` — `[dev-YYYY-MM-DD-X] LF.6.streaming — streaming-path artwork resolver + fetcher + cache + wire`. Include the in-flight cancellation behavior and the new cache location.
* `docs/ENGINEERING_PLAN.md` — LF.6.streaming row above LF.6 in "Recently Completed". Done-when criteria, files touched, follow-up: MusicKit-native artwork as separate increment if Matt wants it.
* `docs/DECISIONS.md` — new entry. Likely D-134 (verify with `project_decisions_numbering.md` memory note before assigning). Document: (a) the Spotify-first + iTunes Search source order, (b) the cache location and size cap Matt picked at Pre-Flight, (c) the in-flight cancel-on-track-change choice.
* `docs/ARCHITECTURE.md §Session Preparation` (the LF.6 publisher path subsection) — extend with the streaming flow: connector capture → in-flight resolver → fetcher → disk cache → MainActor publish.

Closeout report per CLAUDE.md "Increment Completion Protocol." Attach a screenshot of the streaming chrome with artwork (Spotify session) and without artwork (Apple Music session pre-iTunes-resolve / unknown source).

Commit: `[LF.6.streaming] docs: ENGINEERING_PLAN + RELEASE_NOTES + DECISIONS + ARCHITECTURE`.

## Critical Invariants

* LF.6 baseline test counts hold: engine `≥` LF.6 baseline, app `≥` LF.6 baseline.
* All existing streaming-session tests stay green. No behavioral change for tracks where artwork doesn't resolve (still get the LF.6 fallback glyph).
* SwiftLint `--strict` clean on every touched file.
* `Scripts/check_user_strings.sh` exit 0.
* `Scripts/check_sample_rate_literals.sh` exit 0.
* New file `StreamingArtworkDiskCache.swift` (app), `StreamingArtworkFetcher.swift` (app) registered in `project.pbxproj` across all four PBX sections.
* `StreamingArtworkURLResolver.swift` (engine) registered in the engine SPM target via SPM's auto-discovery.
* `currentTrack` and `currentTrackArtworkData` publishers update on the **same MainActor tick** — never publish artwork before the title or vice versa.
* Track-change A → B with B-arrived-first never shows A's artwork. Test S5.3 backstops.
* No `URLSession` calls from `@MainActor` — all fetches happen in detached / nonisolated context, results hop back to MainActor for the publish.
* `URLProtocol`-stub test suites use `@Suite(.serialized)` per CLAUDE.md.
* Disk cache files are written atomically (`.write(to:options:.atomic)`) so a crash mid-write doesn't leave half-bytes.
* Cache trim runs after every write, never during the render loop.
* No new dependency. URLSession + SHA-256 from CommonCrypto / CryptoKit are platform-standard.
* The LF chrome (LF.6) remains pixel-identical — LF.6.streaming touches no LF code paths.
* Streaming-session chrome with artwork: pixel-identical to LF.6's LF chrome with artwork, by sharing the same `TrackInfoCardView` slot.

## Verification Commands

```sh
# Per-task verification
swift test --package-path PhospheneEngine --filter "SpotifyWebAPIConnectorTests|StreamingArtworkURLResolverTests" 2>&1 | tail -5
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test -only-testing:PhospheneAppTests/StreamingArtworkDiskCacheTests -only-testing:PhospheneAppTests/StreamingArtworkFetcherTests -only-testing:PhospheneAppTests/StreamingArtworkPublishingTests 2>&1 | tail -5
swiftlint lint --strict --config .swiftlint.yml <touched files>

# Full regression at closeout
swift test --package-path PhospheneEngine 2>&1 | tail -5
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test 2>&1 | tail -3
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail -3

# Manual smoke (Matt)
# 1. Spotify session: open a Spotify playlist with album-art-bearing tracks. Verify
#    TrackInfoCardView shows the album art (left of title) within ~1 s of each track change.
# 2. Apple Music session: same against an Apple Music playlist. iTunes Search should
#    resolve artwork for most mainstream tracks; less-mainstream tracks may fall back
#    to the glyph — verify the glyph renders, no crash.
# 3. Rapid Next-track Next-track Next-track: chrome should never flash a previous
#    track's artwork; final state matches the final track.
# 4. Offline: airplane mode on, restart a previously-played streaming session. Cached
#    artwork should still render (disk cache hit).
# 5. Disk cap: streaming-artwork directory under ~/Library/Caches/com.phosphene.app/
#    should not exceed the cap Matt picked at Pre-Flight Audit step 2.
```

## Commit Cadence

1. `[LF.6.streaming-S1] SpotifyWebAPIConnector: capture album.images[0].url`
2. `[LF.6.streaming-S4] StreamingArtworkDiskCache: SHA-256-keyed LRU cache in Caches/`
3. `[LF.6.streaming-S3] StreamingArtworkFetcher: URLSession-based protocol`
4. `[LF.6.streaming-S2] StreamingArtworkURLResolver: Spotify-first + iTunes Search`
5. `[LF.6.streaming-S5] VisualizerEngine: publish streaming artwork on track change`
6. `[LF.6.streaming] docs: ENGINEERING_PLAN + RELEASE_NOTES + DECISIONS + ARCHITECTURE`

If Pre-Flight Audit step 3 picks **(b) Spotify only**, drop S2 and the iTunes-related pieces of S3; close as LF.6.streaming and file LF.6.streaming.2 for iTunes Search as a follow-up.

## Overall Done-When Gate

* `git log --oneline -8` shows the LF.6.streaming commit chain.
* Engine + app test suites green; pass counts at-or-above LF.6 baseline.
* SwiftLint + strings + sample-rate-literal gates clean.
* New `StreamingArtwork*` tests run and pass.
* Manual smoke (Matt-driven) confirms:
  - Spotify chrome shows resolved artwork within ~1 s of every track change.
  - Apple Music chrome shows resolved artwork (or restrained glyph if iTunes Search has no match) — no crashes.
  - Rapid track-change race: only the final track's artwork ever displays.
  - Offline replay of a recently-cached track renders the cached artwork.
  - Disk-cache directory respects the size cap.
* `docs/ENGINEERING_PLAN.md` has the LF.6.streaming entry above LF.6.
* `docs/RELEASE_NOTES_DEV.md` has the LF.6.streaming entry.
* `docs/DECISIONS.md` has the new entry (D-134 likely — check numbering memory).
* `docs/ARCHITECTURE.md` § Session Preparation extended.
* Closeout report per CLAUDE.md "Increment Completion Protocol." Two chrome screenshots attached (Spotify with artwork; Apple Music with mixed-resolve).

## Out of Scope (Do Not Do)

* Apple Music MusicKit native artwork (separate increment if Matt wants it).
* Core Audio tap-only sessions where no source app identity is available — fallback glyph applies, no fetch attempted.
* Animated artwork crossfade.
* Artwork color extraction for chrome tinting (separate design exploration).
* User-supplied artwork override / right-click menus.
* Pre-fetching artwork during the streaming session's preparation window (would require building a streaming-side analog of LF.5's prepareLocalFiles; out of scope).
* Streaming-side `lastEndedLocalFileOrigin`-style "play this playlist again" CTA.
* In-memory cache *layer* — `AlbumArtworkCache` (LF.6) already handles in-memory decode cache; LF.6.streaming only handles fetch + disk persistence of bytes.
* Surfacing fetch errors to the user — they fall back to the glyph silently.

## Stuck-State Guidance

* **`SpotifyWebAPIConnectorTests` fails after S1 because the fixture has no `images` field.** Verify the fixture JSON at `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/spotify_items_response.json` — Spotify's response always includes `album.images`, but the fixture may have been trimmed. If trimmed, extend the fixture (it's still ≤ a few KB).

* **iTunes Search returns artworkUrl100 but the `100x100bb` → `600x600bb` swap returns 404.** Apple's CDN supports the swap for most entries, but a small fraction return 404 at 600px. Fall back to the original 100×100 URL on fetch failure (S3's catch site).

* **In-flight cancellation visibly snaps artwork from A → nil → B.** That's the desired behavior — the nil moment is sub-frame and the chrome's existing opacity-animate-in covers it. If product feedback says it's visible, gate the nil-publish on "the fetch was non-trivially-delayed" (cancel-immediate: keep showing A; cancel-after-N-ms: switch to nil then B).

* **`URLSession` warns about MainActor in Swift 6 strict concurrency mode.** Route all fetcher calls through `URLSession.shared.data(for:)` in a `Task.detached(priority: .utility)` body. Results hop back to MainActor for the publish.

* **`StreamingArtworkDiskCache` LRU eviction is slow on large caches.** Trim runs after every write. If profiling shows it costing > 50 ms, switch from "scan all files, sort by access time" to "maintain an in-memory access-time index, persist on actor deinit."

* **The disk cache lives in a directory that doesn't exist yet.** First write creates `~/Library/Caches/com.phosphene.app/streaming-artwork/` lazily. Don't pre-create at engine init — that adds an unnecessary I/O at launch.

* **A streaming track-change emits identical title+artist back-to-back (e.g. user re-played the same track).** The track-change callback already dedupes; LF.6.streaming inherits that behavior. No re-fetch.

* **The chrome briefly flashes the fallback glyph between the title appearing and the artwork loading.** That's the unavoidable consequence of network-fetched artwork. The opacity-animate-in covers most of it. If product wants it tighter, S5 can publish the *previous* track's artwork until the new fetch resolves, but that introduces a "wrong artwork briefly visible" failure mode and is rejected per Bug A's "no wrong-art at any moment" rule from LF.6.

* **`NSImage(data:)` returns nil for a fetched JPEG.** Streaming CDN occasionally serves a 1-pixel error image with a 200 status. `AlbumArtworkCache.image(for:identity:)` already handles nil by returning nil (LF.6 stuck-state guidance). The chrome falls back to the glyph. No special handling needed.

* **The cache trim deletes a file that another track-change is reading in parallel.** Use `os_unfair_lock`-equivalent per-file coordination, or accept the rare race (the reader gets nil and re-fetches). Default: accept the race. The fetch is idempotent and bounded.

* **`SpotifyWebAPIConnector.swift` is past `file_length` warning after S1.** Two lines added; unlikely. If it does tip, factor the artwork extraction into a small helper file `SpotifyArtworkExtraction.swift`.

* **`VisualizerEngine+Capture.swift` is past `file_length` after S5.** Likely. Split the new helper into `VisualizerEngine+StreamingArtwork.swift`. Match the existing extension-file naming convention.
