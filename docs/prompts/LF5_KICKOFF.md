# Claude Code Session Prompt — Increment LF.5: Multi-File Local Playback + File-Association + Recents

## Context

LF.1 / LF.2 / LF.3 / LF.4 (2026-05-27, D-128 / D-129 / D-130 / D-131) graduated local-file playback from "AVAudioEngine spike behind an env var" to a first-class user-facing feature: file picker, drag-and-drop, persistent stem cache with LRU eviction, full `SessionManager`-driven `idle → preparing → ready → playing` lifecycle, and a menu cache-clear action. The whole arc shipped against a single load-bearing operation: **one file at a time.**

LF.5 lifts the "one file at a time" ceiling. The user picks a folder, drags multiple files, opens an M3U playlist, or double-clicks a `.m4a` in Finder — and Phosphene treats that input as an ordered queue, walking through it with the same orchestrator-driven preset selection per track that the streaming path uses. The persistent cache populates progressively; the user sees a real preparation progress bar (not the placeholder single-row LF.4 has); and a `File → Open Recent ▸` submenu surfaces the last N played files for one-click resume.

Two flows to be careful about. **(1)** The streaming path's `SessionPreparer.prepare(tracks:)` walks the playlist sequentially with per-track status, network downloads, MIR analysis, and cache writes. LF.5 needs the same per-track status surface, but the per-track work is local (file decode + `analyzePreview` + persist) instead of network-bound — different bottleneck, same UI contract. **(2)** Once a multi-file queue is loaded and playback is in flight, track transitions need to happen *inside* `VisualizerEngine.handleLocalFileReady()` or its sibling — the audio router needs to switch from file N's `AVAudioFile` to file N+1's at the boundary, and `resetStemPipeline(for:identity)` needs to install the next track's cached BeatGrid. Mid-session, not just at startup.

What LF.5 explicitly **does** NOT change: streaming-path cache persistence, the orchestrator's reactive vs planned-mode selection logic, the LF audio router's `AVAudioEngine` foundation. Those stay where LF.4 left them.

## What LF.5 explicitly DOES

* **Folder ingest.** New "Open Local Folder…" menu item under `File`. Recursive walk of supported audio extensions (`.m4a` / `.mp3` / `.flac` per the LF.4 validation set); ordered alphabetically by filename within each subdirectory; subdirectories visited depth-first. Result is a `[URL]` queue handed to `SessionManager.startLocalFiles(at:)` (new multi-file API).
* **M3U playlist ingest.** Drop or open a `.m3u` / `.m3u8` file. Parser reads the file line-by-line, resolves relative paths against the M3U's parent directory, skips `#EXTINF:` extension metadata for now (LF.5 doesn't surface duration / artist hints; ID3 extraction is its own LF.5 task below). Comment lines (`#`) other than `#EXTM3U` are ignored. Empty / unreadable entries skipped with a `STEM_QUEUE_SKIP` session-log line. Result is the same `[URL]` queue.
* **Multi-file drag-and-drop.** ContentView's existing `.onDrop` accepts multi-file drops. If all are audio files: queue them in drop-order. If any are M3U files: each M3U is expanded into its track URLs and concatenated into the overall queue. If any are folders: each folder is expanded recursively (same alphabetical ordering as the menu picker). Mixed drops are flattened in drop-order.
* **Recents menu.** New `File → Open Recent ▸` submenu showing the last N (default 10) opened files, folders, or M3Us. Persisted via `UserDefaults` (`phosphene.lf.recents` key, JSON-encoded `[RecentItem]` where `RecentItem = { url: String, kind: "file" | "folder" | "m3u", openedAt: Date }`). Stale entries (file no longer at that path) are surfaced as disabled menu items with a "(missing)" suffix; one click on a stale item removes it from the list. A "Clear Recents" item at the bottom of the submenu wipes the list.
* **File-association handling.** `Info.plist` `CFBundleDocumentTypes` registers Phosphene as a handler for `.m4a` / `.mp3` / `.flac` / `.m3u` / `.m3u8` (NOT "Default"; macOS lets the user opt into Phosphene-as-default via the Finder "Get Info" panel). `PhospheneApp.swift` extends `.onOpenURL` (or adds a separate handler — the existing one routes Spotify OAuth callbacks) to recognise `file://` URLs and route them through the LF queue path.
* **`SessionManager.startLocalFiles(at:)` API.** Multi-file twin of LF.4's `startLocalFile(at:)`. Walks the input `[URL]`, queues them, drives `idle → preparing → ready → playing`. Per-track preparation status surfaces through the existing `preparingTracks` + `trackStatuses` publishers — `PreparationProgressView` now renders correctly for an N-track queue (it always could, LF.4 just put one placeholder identity in `preparingTracks`).
* **Mid-session track transitions.** When the active file's playback ends (or the user advances via a shortcut — `→` / `space` semantics deferred to a follow-up if non-trivial), the LF audio router swaps to the next file's `AVAudioFile`, `resetStemPipeline(for: nextIdentity, caller: .trackChange)` installs the next track's cached BeatGrid, and the orchestrator's per-track preset selection fires (same `currentTrackIndex` publisher streaming uses).
* **`SessionOrigin` extension.** New `.localFiles([URL])` case alongside LF.4's `.localFile(URL)`. The single-file case stays for the menu's "Open Local File…" path (preserves the "no .preparing UI for a one-second-cold-start" feel); multi-file goes through the new case. Two cases not one because the lifecycle differs (single-file skips progressive readiness UI; multi-file relies on it).
* **`PreparationProgressView` for multi-file LF.** The view already handles N-track sessions for streaming; LF.5 wires the per-track status publishers so each LF entry transitions `queued → analyzing → ready` as the off-main worker walks the queue. "Start now" CTA fires once `defaultProgressiveReadinessThreshold` (3) terminal-ready entries exist — same threshold as streaming.
* **Sequential preparation, off-main, cancellable.** A new `SessionPreparer.prepareLocalFiles(at:[URL])` (or move the worker logic out of `VisualizerEngine+LocalFilePlayback.swift` into the preparer where it belongs for the multi-file case) walks the URL list sequentially, dispatches hash + persistent-cache + analyze + persist per file, advances `trackStatuses` after each. Cancellation honoured at file boundaries (≤ ~2 s granularity). Same `Task.detached(priority: .userInitiated)` pattern LF.4 uses.
* **ID3 / Vorbis tag extraction.** Use `AVAsset.commonMetadata` to read title / artist / album / artwork for each file as it's queued. Surface title + artist on the `PreparationProgressView` row (replaces the LF.4 fallback "filename / 'local file'"). Album art is grabbed but not displayed yet — keep the surface area small, defer to LF.6.
* **Localized strings.** Every new user-facing string ships in `Localizable.strings`. `Scripts/check_user_strings.sh` enforces.

## What LF.5 explicitly does NOT do

* Crossfade / gapless segue. Track transition is a hard cut — LF.6 territory if user demand surfaces. `AVAudioEngine` supports gapless via pre-scheduling buffered files but that's its own diagnosis (sample-rate matching, head/tail-trim heuristics, etc.).
* Album-art display in `PlaybackView` chrome. The data is captured at LF.5 scope; the UI surface is LF.6.
* Per-track skip / next / prev controls in `PlaybackView`. `UX-2` invariant: no playback controls in PlaybackView. The user's queue advance is implicit (track ends → next track starts) at LF.5. Explicit `→` / `←` skip shortcuts are a separate increment.
* Drag-to-reorder of the queue mid-session.
* Manual track removal from the queue (user has to cancel + re-pick).
* Smart-playlists. Apple Music's `.musiclibrary` bundle ingestion. Spotify-local-file integration.
* Per-track persistent cache eviction overrides. The LF.4 LRU policy applies uniformly to all entries.
* Cross-machine library sync. iCloud Music Library / iTunes Match / etc.
* `.fpl` (Foobar2000) playlist files. Format is binary; would need a separate parser. Defer until someone asks for it.
* In-app M3U editor / "Save current queue as M3U" export.
* Streaming-path persistent cache (still its own increment).
* Spotify track ID-keyed cache.

## Required Reading

Before any code, read in this order:

1. `docs/ENGINEERING_PLAN.md` — the LF.4 closeout entry (precursor) and LF.3 / LF.2 / LF.1 below it for the full LF arc context.
2. `docs/diagnostics/LF4_REGRESSION_2026-05-27.md` — current cold/warm latency baseline. LF.5 multi-file queue must not regress these per-file (≈ 2 s cold, < 1 s warm).
3. `docs/DECISIONS.md` — D-128 (LF.1 AVAudioEngine), D-129 (LF.2 dispatch model), D-130 (LF.3 cache layout), D-131 (LF.4 SessionManager + LRU). LF.5 likely produces D-132 (multi-file source model + per-track preparation + recents + file-association).
4. `docs/UX_SPEC.md` — §2 state-to-view mapping, §2.1 LF entry-point section, §5 preparation UI, §9 error taxonomy. LF.5 must respect every invariant. The §2 table entry for `.preparing` already says "N-track list" — LF.5 fills in the N for the LF path.
5. `docs/ARCHITECTURE.md` — §Session Preparation, §Session Manager, §Renderer track-change wiring.
6. `CLAUDE.md` — UX-2 invariant (no playback controls in PlaybackView), externalised-strings rule, U.11 pbxproj 4-section note (LF.5 will add new files).

Then audit:

* `PhospheneEngine/Sources/Session/SessionManager.swift` — `startSession(preFetchedTracks:source:)` is the closest streaming-path analog for "I already have a `[TrackIdentity]` list, prepare them all." LF.5's `startLocalFiles(at:)` follows the same shape but feeds a different preparation worker.
* `PhospheneEngine/Sources/Session/SessionPreparer.swift` — `_runPreparation(tracks:)` walks the list with per-track `prepareTrack(_:)` calls. LF.5 either reuses this with a `prepareLocalTrack(_ url: URL)` swap-in, or introduces a parallel `prepareLocalFiles(at:)` method.
* `PhospheneApp/VisualizerEngine+LocalFilePlayback.swift` — `LocalFilePreparing.prepareLocalFile(url:)` is the single-file delegate the LF.4 path uses. For LF.5: either extend the protocol with `prepareLocalFiles(urls:)`, OR have SessionManager call `prepareLocalFile(url:)` in a loop. The loop is simpler but pushes the queueing logic into SessionManager — both are viable.
* `PhospheneApp/VisualizerEngine+LocalFilePlayback.swift` `handleLocalFileReady()` — the `.ready` observer for the single-file case. For LF.5, this needs to also handle the *first* track of a multi-file queue, AND mid-session track transitions need a parallel path that installs the next track without going through `.ready` (we're already in `.playing`).
* `PhospheneApp/LocalFileMenuCommands.swift` — file picker glue. LF.5 adds `openLocalFolderPanel(engine:)` + extends `handleDrop(providers:engine:)` for multi-file and folder drops.
* `PhospheneApp/PhospheneApp.swift` — `.commands` block adds `File → Open Local Folder…` + `File → Open Recent ▸` submenu. `.onOpenURL` extended for `file://` URLs.
* `PhospheneApp/Info.plist` — `CFBundleDocumentTypes` registration for the audio formats and M3U.
* `PhospheneEngine/Sources/Session/PersistentStemCache.swift` — no LF.5 changes expected; the cache layer is per-file and already handles concurrent stores via NSLock. Verify the LRU eviction policy doesn't thrash under "user opens a 50-track folder, cache cap is 60 tracks": eviction runs after every store and the oldest writes get evicted before the newest land. That's the intended behaviour but worth a spot-check.

## Pre-Flight Audit (do this before writing any code)

1. **Decide the queue lifecycle ownership.** Two shapes:
   * **A: SessionManager owns the queue.** `SessionManager.startLocalFiles(at:)` enqueues the URLs and calls `localFilePreparer.prepareLocalFile(url:)` in a loop. SessionManager publishes `trackStatuses` as it goes. Engine reacts to `.ready` per-track-transition.
   * **B: SessionPreparer owns the queue.** New `SessionPreparer.prepareLocalFiles(urls:)` async method that mirrors `_runPreparation(tracks:)`. SessionManager delegates the whole walk to the preparer; the preparer publishes `trackStatuses` like it does for streaming.
   * Recommendation in your audit: Option B. The streaming-path symmetry is the right shape; SessionManager already calls `preparer.prepare(tracks:)` and observes its publisher — LF.5 reuses the same plumbing. Option A duplicates per-track state-tracking machinery SessionPreparer already has.

2. **Decide track-transition mechanics during playback.** When file N's audio ends, who advances to file N+1? Two paths:
   * **A: LF audio router fires a callback.** `LocalFilePlaybackProvider` (in `PhospheneEngine/Sources/Audio/`) already loops at EOF (per its docstring); LF.5 changes it to fire a delegate callback instead. `VisualizerEngine` consumes the callback and dispatches a track-change.
   * **B: VisualizerEngine polls for EOF.** A periodic check on `AVAudioFile.framePosition` against `length`. Less invasive but adds polling.
   * Recommendation: Option A. The provider already knows where the file's playhead is — surface that knowledge through an `onFileEnded` callback. Note: `LocalFilePlaybackProvider` currently loops at EOF (LF.1 design choice); LF.5 changes that loop into a queue advance.

3. **Decide the SessionOrigin extension shape.** Three options:
   * `.localFiles([URL])` — flat list; folder / M3U inputs flatten into this case before SessionManager sees them.
   * `.localFile(URL)` + `.localFolder([URL])` + `.localPlaylist(URL)` — preserves the input shape so the UI can show "playing folder X" vs "playing playlist Y". More cases, more UI branching.
   * `.localFiles(LocalSource)` where `LocalSource = .file(URL) | .files([URL]) | .folder(URL, expanded: [URL]) | .playlist(URL, expanded: [URL])`. Captures both the original input and the expanded queue. Most expressive; most complex.
   * Recommendation: the second option (three explicit cases). The shape difference matters for UI ("Playing 12 tracks from ~/Music/2026 Mix" vs "Playing love_rehab.m4a"). Multi-line case dispatch is fine; the cost is local to the view layer.

4. **Decide how the LF.4 single-file path coexists.** Two options:
   * **A: LF.4's `startLocalFile(at:)` API stays as-is; LF.5 adds `startLocalFiles(at:)` alongside.** Single-file callers (menu picker for one file, env-var hook) keep the LF.4 behaviour (no preparation UI for a ~2 s cold-start because it's a 1-item queue). Multi-file callers use the new API.
   * **B: `startLocalFile(at:)` becomes a thin wrapper around `startLocalFiles(at: [url])`.** Cleaner API surface; same behaviour. The "no progress UI for 1 item" optimisation is enforced inside the preparer (single-item queue completes too fast for SwiftUI to render the progress view).
   * Recommendation: Option B. Two parallel APIs is a maintenance trap; consolidating is the right move. Verify the single-item lifecycle still works (LF.4's 14 tests are the regression gate here).

5. **Decide the "Recents" persistence schema.** `UserDefaults` JSON-encoded `[RecentItem]`. Per-item shape: `{url, kind, openedAt}` with `kind = "file" | "folder" | "m3u"`. Max 10 entries. Pruning rule: oldest entries fall off when a new one lands; opening an entry that's already in the list moves it to position 1 (LRU-style). `openedAt` is the most recent open time, not the first-ever.

6. **Decide what happens when a folder contains 1000+ files.** Truncate to a max queue size (200?) or accept the user's input verbatim? Per the LF.4 cache cap (500 MB ≈ 70 tracks), a 1000-track queue would thrash eviction. Truncation with a localized toast ("Phosphene queued the first 200 tracks of 1043. Open a smaller folder for full queue.") seems right. Surface as a Matt decision.

7. **Decide the M3U parser's tolerance.** M3U files in the wild contain typos, missing entries, Windows-style line endings, BOM headers, and `#EXT-X-*` segments that belong to HLS rather than music playlists. LF.5 parses defensively:
   * Strip BOM (UTF-8 / UTF-16) on read.
   * Accept both LF and CRLF line endings.
   * Ignore lines starting with `#` (treat as comments).
   * Resolve relative paths against the M3U file's parent directory.
   * Skip lines that don't resolve to a readable audio file (log `STEM_QUEUE_SKIP` per skip).
   * On any parse failure: log + start playback with whatever did parse. If nothing parses: surface the failure as a localized alert.

8. **Decide file-association handling scope.** `.m4a` / `.mp3` / `.flac` — straightforward UTType association. `.m3u` / `.m3u8` — straightforward. Don't register as the *default* handler for these types (annoying UX hijack); let the user opt-in via Finder. Verify that `.onOpenURL` on the SwiftUI app receives file URLs correctly (it does on macOS 14+); the existing Spotify-callback router needs to distinguish `phosphene://` (route to OAuth) from `file://` (route to LF queue) without crossing wires.

9. **Decide whether LF.5 changes streaming-path behaviour.** It shouldn't. The streaming path's `startSession(source:)` and `startSession(preFetchedTracks:source:)` APIs stay. The `SessionPreparer.prepare(tracks:)` method also stays for streaming. New LF.5 plumbing is parallel, not overlapping.

10. **Confirm pbxproj UUID-prefix block.** Q-prefix block (Q10001–Q10002) was used for LF.4's two new app-layer files. Q-prefix has 100s of slots available; allocate Q10003+ for new LF.5 app files (the recents-manager and any M3U parser glue). Engine files use SPM auto-discovery, no pbxproj surgery needed.

Write up the audit findings (under ~250 words) before starting Task 1.

## Task Breakdown

### Task 1 — `SessionOrigin` extension + `SessionManager.startLocalFiles(at:)` API

Extend `SessionOrigin` with the three multi-file cases (`.localFiles([URL])` / `.localFolder(URL, expanded: [URL])` / `.localPlaylist(URL, expanded: [URL])`; OR your audit's chosen shape). Update `currentSource` consumers (`ContentView` permission gate, `VisualizerEngine.startAudio` guard, `LocalFilePreparing` conformance) to recognise all multi-file variants as "LF active." Add `SessionManager.startLocalFiles(at: [URL], origin: SessionOrigin)` — accepts both the URL list AND the SessionOrigin so the UI knows whether the user opened a folder, M3U, or multi-file drop. Replaces LF.4's `startLocalFile(at:)` (now a thin wrapper that calls `startLocalFiles(at: [url], origin: .localFile(url))`).

Done when: `SessionManagerLocalFileTests` extends to cover the multi-file case (queue length 3+, per-track status, mid-queue cancel). LF.4's 14 tests still pass. New tests cover same-URL re-entry on a multi-file queue (no-op if same URL list, replaces if different).

### Task 2 — `SessionPreparer.prepareLocalFiles(urls:contentCache:)` worker

New method on `SessionPreparer` that walks the URL list sequentially, calls `prepareLocalTrack(_ url: URL)` per file (a helper that does hash + persistent-cache + `analyzePreview` + persist + writes to `StemCache`), publishes `trackStatuses` after each. Cancellable at file boundaries (≤ ~2 s granularity per file). Returns the populated cache + the per-file outcome list.

`VisualizerEngine`'s `LocalFilePreparing` conformance is replaced by passing the engine's ML deps directly to `SessionPreparer.init` so the preparer can run the LF work itself (or kept if the audit chooses Option A). Engine still owns the LF audio router and the `.ready` observer for installing BeatGrid into the live pipeline.

Done when: `LocalFilePlaybackFormatCoverageTests` is extended to a 3-track folder fixture (M4A + MP3 + FLAC same content), running through the new `prepareLocalFiles` path. Per-track status transitions are observable via the test's `trackStatusesPublisher` subscription.

### Task 3 — Multi-file UI surfaces (menu + drop + recents)

* `File → Open Local Folder…` menu item with no accelerator (the obvious `⌘⇧O` is already SwiftUI's "Open" alternate; avoid conflict). `NSOpenPanel` with `canChooseDirectories = true, canChooseFiles = false`.
* `File → Open Recent ▸` submenu. Items: last 10 file/folder/M3U opens, newest first. Stale entries shown as disabled with "(missing)" suffix. "Clear Recents" item at the bottom. Submenu rebuilds reactively when the recents list changes.
* `.onDrop` handler in `ContentView` extended for: multi-audio-file drops (queued in drop order), folder drops (recursively expanded), M3U drops (parsed + expanded), mixed drops (flattened in drop order).
* `Info.plist` `CFBundleDocumentTypes` registers Phosphene for `.m4a / .mp3 / .flac / .m3u / .m3u8`. `LSHandlerRank = Default` is NOT set (we don't claim to be the default opener).
* `PhospheneApp.swift` `.onOpenURL` handler distinguishes `phosphene://` (Spotify OAuth) from `file://` (LF queue).
* New `LocalFileRecentsStore` class (or similar) wraps the `UserDefaults` JSON persistence. `@Published var recents: [RecentItem]` so the menu binds reactively.

Done when: manual smoke covers all four entry points (menu file, menu folder, menu recent, drag-and-drop, double-click in Finder). Each surfaces the same `idle → preparing → ready → playing` lifecycle with per-track status. The "(missing)" disabled state for a recent item whose file moved is verifiable by `mv ~/Music/love_rehab.m4a /tmp/` then opening the Recents submenu.

### Task 4 — M3U parser

New `M3UParser` in `PhospheneEngine/Sources/Session/` (or `PhospheneApp/` if SessionManager isn't the right home for I/O). Strips BOM, accepts CRLF + LF, ignores `#`-prefixed lines, resolves relative paths, skips unreadable entries with `STEM_QUEUE_SKIP` log. Returns `[URL]`. Errors surface as `M3UParseError` (file unreadable / no entries resolved / malformed UTF-8). The error → user-facing copy mapping lives in `LocalFileMenuCommands`.

Done when: `M3UParserTests` covers (a) trivial 3-track playlist, (b) `#EXTINF` extension metadata ignored, (c) relative-path resolution against parent dir, (d) BOM + CRLF tolerance, (e) skip-unreadable behaviour, (f) empty-result throws.

### Task 5 — Mid-session track transitions

`LocalFilePlaybackProvider` gains an `onFileEnded` Sendable callback (replacing the LF.1 implicit-loop behaviour for the multi-file case; single-file case still loops if you want — or always-advance and let the orchestrator decide). `VisualizerEngine` wires the callback to a new `advanceLocalFileQueue()` method:

* Pop the next URL off the queue.
* Stop the current router (synchronous).
* Look up the next URL's identity in `stemCache` (the preparer already populated it during the preparation pass).
* `resetStemPipeline(for: nextIdentity, caller: .trackChange)` — installs the next BeatGrid.
* `audioRouter.start(mode: .localFilePlayback(nextURL))` — kicks the audio router.
* Publish `currentTrackIndex` (already exists; UI binds to it).
* If queue is empty: transition to `.ended` (or repeat? — let the audit decide).

Done when: a 3-track queue plays through end-to-end; `session.log` shows three `BEAT_GRID_INSTALL` lines + three `raw tap capture started` lines; `currentTrackIndex` increments 0 → 1 → 2 → nil (at end). Audio is continuous (no silence between tracks longer than the AVAudioEngine restart cost — ~50 ms).

### Task 6 — ID3 / Vorbis tag extraction

`SessionPreparer.prepareLocalTrack(_ url: URL)` extracts title / artist / album / artwork via `AVAsset.commonMetadata` (which works for ID3v2, MP4 atoms, FLAC Vorbis comments). Hands the result through to the synthetic `TrackIdentity` so `PreparationProgressView` shows the real song title instead of "love_rehab.m4a". Artwork is captured into `CachedTrackData` (or a sibling persistent storage location) but not displayed yet.

Done when: a fixture with rich ID3 (e.g. `love_rehab.m4a` if its metadata is populated; otherwise a new fixture) shows the artist + title in the preparation row. The persistent cache schema bumps to version 2 (`metadata.json` carries the new fields); old version-1 entries miss the new fields cleanly (treat as nil; log a `STEM_CACHE_MISS: reason=schemaMismatch` and re-prepare).

### Task 7 — File-association handling

`Info.plist` `CFBundleDocumentTypes` entries for the five extensions. `.onOpenURL` recognises `file://` URLs, validates the extension via `LocalFileMenuCommands.allowedExtensions ∪ {"m3u", "m3u8"}`, dispatches to either `SessionManager.startLocalFiles(at:)` (single-file → `[url]`; folder → expanded list; M3U → parsed list).

Done when: `open -a Phosphene path/to/love_rehab.m4a` in Terminal launches the app and plays the file; double-clicking `.m4a` in Finder (after the user picks Phosphene from "Open With…") does the same.

### Task 8 — Documentation + closeout

* `docs/ENGINEERING_PLAN.md` — new "Increment LF.5 — Multi-File Local Playback + File-Association + Recents ✅" entry above LF.4.
* `docs/DECISIONS.md` — new D-132 (multi-file source model + sequential preparation + recents persistence + file-association). D-131's Out-of-scope updated (multi-file / M3U / recents / file-association struck through as Done).
* `docs/ARCHITECTURE.md` — §Session Preparation extended with the multi-file LF path; §Session Manager extended with the queue model.
* `docs/UX_SPEC.md` — §2.1 extended with the multi-file entry points + the Recents submenu + the file-association behaviour.
* `docs/RUNBOOK.md` — operator command to inspect / clear the recents UserDefaults entry; M3U parsing notes.
* `docs/RELEASE_NOTES_DEV.md` — `[dev-2026-MM-DD-*]` entry.
* `docs/diagnostics/LF5_REGRESSION_2026-MM-DD.md` — per-file cold/warm latencies on a 3-track folder.
* `CLAUDE.md` — only if a new "do not" rule emerges (probably none).

## Critical Invariants

* LF.1 / LF.2 / LF.3 / LF.4 behaviour must not regress. Regression gates:
   * `swift test --filter AudioInputRouterSignalStateTests` — 11/11.
   * `SOAK_TESTS=1 swift test --filter SoakTestHarnessTests` — 7/7.
   * `LF_FORMAT_COVERAGE=1 swift test --filter LocalFilePlaybackFormatCoverageTests` — 3/3.
   * `swift test --filter PersistentStemCacheTests` — 11/11.
   * `swift test --filter PersistentStemCacheEvictionTests` — 11/11.
   * `swift test --filter PreviewAudioContentHashTests` — 8/8.
   * `swift test --filter SessionManagerLocalFileTests` — 14/14 + new multi-file additions.
   * Full engine suite — pass count ≥ LF.4's 1328.
* Per-file cold-start latency must not regress past LF.4's ~2 s baseline. Per-file warm-start latency must not regress past LF.4's ~607 ms baseline.
* `PHOSPHENE_LOCAL_FILE_PLAYBACK` env-var hook stays functional (single-file). New `PHOSPHENE_LOCAL_FILE_PLAYBACK` accepting a folder OR M3U would be a separate increment.
* One `SessionManager` app-wide; one `SettingsStore` app-wide.
* All user-facing strings externalised. `Scripts/check_user_strings.sh` enforces.
* No `44100` literals introduced.
* New app-layer source files registered in `project.pbxproj` across all four sections.
* No playback controls in `PlaybackView`. UX-2 invariant.
* Error messages localised; no jargon (FFT / MPSGraph / tap / SSGI / G-buffer).
* Swift 6 strict concurrency. Off-main work stays `nonisolated`.
* Drag-and-drop accepts multi-file drops at LF.5 scope (was single-file only at LF.4).
* The cache cap (500 MB) is respected throughout: a multi-file queue larger than the cap will see eviction during preparation. That's intended; surface the behaviour in `RUNBOOK.md`.

## Verification Commands

```sh
# Regression gates
swift test --package-path PhospheneEngine --filter AudioInputRouterSignalStateTests
SOAK_TESTS=1 swift test --package-path PhospheneEngine --filter SoakTestHarnessTests
LF_FORMAT_COVERAGE=1 swift test --package-path PhospheneEngine --filter LocalFilePlaybackFormatCoverageTests
swift test --package-path PhospheneEngine --filter PersistentStemCacheTests
swift test --package-path PhospheneEngine --filter PersistentStemCacheEvictionTests
swift test --package-path PhospheneEngine --filter PreviewAudioContentHashTests
swift test --package-path PhospheneEngine --filter SessionManagerLocalFileTests

# New LF.5 tests
swift test --package-path PhospheneEngine --filter M3UParserTests
swift test --package-path PhospheneEngine --filter SessionManagerMultiFileTests
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test -only-testing:PhospheneAppTests/LocalFileRecentsStoreTests

# Sample-rate literal gate
Scripts/check_sample_rate_literals.sh

# Localized-strings gate
Scripts/check_user_strings.sh

# Release build
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' -configuration Release build 2>&1 | tail -3

# Lint (touched files only)
swiftlint lint --strict --config .swiftlint.yml \
  PhospheneApp/VisualizerEngine.swift \
  PhospheneApp/VisualizerEngine+LocalFilePlayback.swift \
  PhospheneApp/LocalFileMenuCommands.swift \
  PhospheneApp/LocalFileRecentsStore.swift \
  PhospheneApp/PhospheneApp.swift \
  PhospheneApp/ContentView.swift \
  PhospheneEngine/Sources/Session/SessionManager.swift \
  PhospheneEngine/Sources/Session/SessionPreparer.swift \
  PhospheneEngine/Sources/Session/PersistentStemCache.swift \
  PhospheneEngine/Sources/Session/M3UParser.swift

# Per-file cold/warm latency re-capture (3-track folder)
CACHE_DIR="$HOME/Library/Application Support/Phosphene/StemCache"
rm -rf "$CACHE_DIR"
APP_BIN="/Users/braesidebandit/Library/Developer/Xcode/DerivedData/PhospheneApp-cngkdwcjwuuqgbfrcioserxgammt/Build/Products/Release/PhospheneApp.app/Contents/MacOS/PhospheneApp"
FOLDER="$(pwd)/PhospheneEngine/Tests/Fixtures/lf5-3-track"  # create this fixture
# Launch via the (future) PHOSPHENE_LOCAL_FILES_PLAYBACK env var (or just open the app manually and pick the folder)
# Inspect session.log for three BEAT_GRID_INSTALL lines + three raw-tap-capture-started lines.

# Manual smoke (Finder file-association)
open -a Phosphene PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a
# Expect: Phosphene launches if not running, queues the file, plays it.

# Manual smoke (Recents)
# 1. Launch the app, File → Open Local File → pick a file.
# 2. Quit the app, relaunch.
# 3. File → Open Recent ▸ — confirm the file is at position 1.
# 4. mv ~/Music/love_rehab.m4a /tmp/love_rehab.m4a
# 5. Reopen the Recents submenu — confirm the entry is disabled with "(missing)".
# 6. Click the disabled entry — confirm it's removed from the list.

# Manual smoke (folder ingestion)
# 1. Drag a folder with 3+ audio files onto the app window.
# 2. Confirm PreparationProgressView shows N rows, transitioning queued → ready.
# 3. Confirm "Start now" CTA fires once 3 tracks are ready.
# 4. Confirm playback walks through all N tracks in alphabetical order.

# Manual smoke (M3U)
# 1. Create test.m3u with 3 relative paths to audio files in the same dir.
# 2. Drag test.m3u onto the app window.
# 3. Confirm the same 3-track playback behaviour as the folder ingestion case.
```

## Commit Cadence

1. `[LF.5] engine: SessionOrigin multi-file extension + startLocalFiles(at:)`
2. `[LF.5] engine: SessionPreparer.prepareLocalFiles(urls:) worker + tests`
3. `[LF.5] engine: M3UParser + tests`
4. `[LF.5] engine: ID3/Vorbis tag extraction via AVAsset.commonMetadata + schema v2`
5. `[LF.5] app: LocalFileRecentsStore + UserDefaults persistence + tests`
6. `[LF.5] app: Open Local Folder menu + Recents submenu + multi-file drag-and-drop`
7. `[LF.5] app: File-association handling (Info.plist + .onOpenURL routing)`
8. `[LF.5] engine: LocalFilePlaybackProvider onFileEnded callback + advanceLocalFileQueue`
9. `[LF.5] tests: SessionManagerMultiFileTests + LF_FORMAT_COVERAGE multi-file extension`
10. `[LF.5] diagnostics: LF5_REGRESSION 3-track per-file latency capture`
11. `[LF.5] docs: ENGINEERING_PLAN + D-132 + ARCHITECTURE + UX_SPEC + RUNBOOK + RELEASE_NOTES`

Prefer fine-grained commits. The PERF.* parallel workstream is likely to keep landing commits on `main`; coordinate via `git pull --rebase` between sessions.

## Documentation Updates

* `docs/ENGINEERING_PLAN.md` — LF.5 entry above LF.4.
* `docs/DECISIONS.md` — D-132 (multi-file source model + sequential preparation + recents persistence + file-association). D-131 Out-of-scope updated.
* `docs/ARCHITECTURE.md` — §Session Preparation multi-file LF sub-bullet; §Session Manager queue model; §Renderer track-change wiring (extended for the mid-session LF transition).
* `docs/UX_SPEC.md` — §2.1 extended; new §2.2 if the file-association behaviour warrants its own subsection.
* `docs/RUNBOOK.md` — operator command to inspect / clear `phosphene.lf.recents` UserDefaults; M3U parsing notes; cap-pressure note for large folders.
* `docs/RELEASE_NOTES_DEV.md` — `[dev-2026-MM-DD-*]` entry.
* `docs/diagnostics/LF5_REGRESSION_2026-MM-DD.md` — Task 10 artifact.
* `CLAUDE.md` — only if a new "do not" rule emerges.

## Overall Done-When Gate

* The user can launch the app, drag a folder of 3+ audio files onto the window, and watch them play through Phosphene in alphabetical order with per-track preset selection driven by the orchestrator. State transitions follow `idle → preparing → ready → playing` (visible in `session.log`).
* `File → Open Local Folder…` and `File → Open Recent ▸` both work as described.
* Dropping an M3U file with 3+ entries produces identical behaviour to the folder case.
* Double-clicking a `.m4a` in Finder (after the user opts into Phosphene-as-handler) launches the app and plays the file.
* The "Start now" CTA fires correctly for a multi-file queue (≥ 3 ready tracks, < 50 % total).
* Mid-session track transitions are silent (≤ 50 ms gap) and observably re-install the BeatGrid per track.
* Per-file cold/warm latencies on the 3-track fixture match LF.4 baselines (≈ 2 s cold, ≈ 607 ms warm — multiplied by track count for the cold path; warm path independent per track).
* All regression gates green; full engine suite pass count ≥ 1328 + new LF.5 tests.
* `PHOSPHENE_LOCAL_FILE_PLAYBACK` env-var hook still works for single-file.
* The Recents submenu correctly tracks the last 10 opens, surfaces stale entries as "(missing)", and rebuilds reactively when the list changes.
* Closeout report produced per CLAUDE.md "Increment Completion Protocol."

## Out of Scope (Do Not Do)

* Crossfade / gapless segue between LF tracks. Track transition is a hard cut at LF.5.
* Album art display in `PlaybackView`. Data captured; UI is LF.6.
* Per-track skip / next / prev controls in `PlaybackView`. UX-2 invariant.
* Drag-to-reorder of the queue mid-session.
* Manual track removal from the queue.
* Smart-playlists / Apple Music library bundle ingestion / Spotify-local-file integration.
* `.fpl` playlist files.
* In-app M3U editor.
* Streaming-path persistent cache (still its own increment).
* Spotify track ID-keyed cache.
* "Save current queue as M3U" export.
* Cross-machine library sync.
* Network-streamed files (HTTP / SoundCloud / etc.).
* Multi-process cache safety. Phosphene is single-instance.

## Stuck-State Guidance

* **`SessionPreparer` doesn't fit the LF case cleanly.** If you find yourself adding LF-specific branches inside `_runPreparation(tracks:)`, stop and reconsider — the preparer's per-track work for streaming is "resolve preview URL → download → analyze" and for LF is "hash → cache lookup → analyze." Those are sibling operations, not a streaming variant. Cleaner: a new `prepareLocalFiles(urls:)` method that owns the per-track work itself, reusing `analyzePreview` for the analysis step.
* **Mid-session track transitions silent-but-broken.** If the BeatGrid install is firing but the visual doesn't change between tracks, the orchestrator's per-track preset selection probably isn't firing. Check `currentTrackIndex` is incrementing and that `applyPreset` runs in `advanceLocalFileQueue`. The streaming path's track-change callback (`makeTrackChangeCallback` in `VisualizerEngine+Capture.swift`) is the reference.
* **M3U parser handling odd inputs poorly.** Real-world M3U files have BOM, CRLF, extension metadata, Windows paths, `file://` prefixes, etc. Defensive parsing wins. If you find yourself adding parser branches for each new edge case the user reports, the parser's strategy needs a rethink — but for LF.5, the scope is "any sane M3U works"; weird ones can fall back to a localized "couldn't parse" alert.
* **`.onOpenURL` not firing for file URLs.** macOS routes file URLs through `.onOpenURL` only if the app is registered as a handler for that file type (via `CFBundleDocumentTypes`). If the menu picker works but `open -a Phosphene file.m4a` doesn't, the Info.plist registration is the first thing to check. `lsregister -dump | grep phosphene` shows the OS's view of what Phosphene handles.
* **Recents list grows unbounded.** Capacity is 10; new entries push the oldest out. If the persisted list has > 10 entries (corrupted UserDefaults from a future-version write), truncate on load and re-persist. Don't trust the persisted shape.
* **Cache thrashes during large-folder ingestion.** The 500 MB cap (≈ 70 tracks) means a 100-track folder will evict the first 30 tracks before the user listens to them. Either: (a) accept it (the user can re-prepare from the cache miss; LF.3 cold path is ~2 s per track), (b) raise the cap automatically when the user opens a folder larger than the cap (set it to `folder.size * 1.1`), or (c) prompt the user to confirm. Surface to Matt if the behaviour is contentious.
* **PBXProj merge conflicts with the parallel PERF.* workstream.** Allocate UUIDs from Q10003+ (Q10001/Q10002 are LF.4); coordinate with Matt if a different prefix block has been claimed.
* **The Localizable.strings file is missing entries for the new UI.** `Scripts/check_user_strings.sh` is the gate. Run before committing.
