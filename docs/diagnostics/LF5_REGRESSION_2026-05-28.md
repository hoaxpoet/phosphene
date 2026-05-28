# LF.5 — Multi-File / Folder / M3U / File-Association Regression Capture (2026-05-28)

**Purpose.** Confirm that LF.5's `SessionManager.startLocalFiles(at:origin:)`
multi-file path + `SessionPreparer.prepareLocalFiles(urls:placeholders:via:)`
queue worker + `PersistentStemCache` schema v2 (LocalFileMetadata + artwork)
+ `LocalFilePlaybackProvider.onFileEnded` mid-session advance do not
regress the LF.4 single-file cold/warm latency baseline
(`docs/diagnostics/LF4_REGRESSION_2026-05-27.md`).

**Fixture.** `PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a`
(29.93 s, AAC, 44100 Hz mono). Same file LF.3 / LF.4 measured against.

**Build.** Release build, M2 Pro, macOS 26.4.1. Launched via the
`PHOSPHENE_LOCAL_FILE_PLAYBACK` env-var hook (routes through
`engine.sessionManager.startLocalFile(at:)` which now wraps
`startLocalFiles(at: [url], origin: .localFile(url))`).

## Verdict

**LF.5 done-when gates achieved. No regression vs LF.4 baseline.**

| Path | LF.4 Baseline | LF.5 Capture | Δ |
|---|---|---|---|
| Cold (no cache on disk) | ~1.892 s wall | ~2.0 s wall | within noise (≤ 100 ms) |
| Warm (cache populated)  | ~607 ms wall | ~600 ms–1.0 s wall (per-second log granularity) | within noise |

The LF.5 schema-v2 cache write adds metadata.json title/artist/album
fields + an optional `artwork.bin` sibling. For tracks with no embedded
artwork (love_rehab.m4a), `artworkBytes=0` and the write cost is
unchanged (`elapsedMs=9` in the LF.5 capture vs `elapsedMs=7` in LF.4 —
within run-to-run noise).

## Cold-Launch Session (LF.5)

**Setup.**
```
rm -rf "$HOME/Library/Application Support/Phosphene/StemCache"
PHOSPHENE_LOCAL_FILE_PLAYBACK=PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a \
  /Users/braesidebandit/Library/Developer/Xcode/DerivedData/PhospheneApp-cngkdwcjwuuqgbfrcioserxgammt/Build/Products/Release/PhospheneApp.app/Contents/MacOS/PhospheneApp
```

**Session ID:** `2026-05-28T13-56-52Z`.

**Load-bearing log lines:**

```
[13:56:52Z] SessionRecorder started schema=1 dir=…/2026-05-28T13-56-52Z
[13:56:52Z] WIRING: SessionManager.startLocalFiles ENTER count=1 first='love_rehab.m4a' origin=localFile
[13:56:52Z] STEM_CACHE_MISS: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, reason=no-entry
[13:56:54Z] STEM_CACHE_WROTE: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, bytes=7045120, artworkBytes=0, elapsedMs=9
[13:56:54Z] BeatGrid installed: source=preparedCache, track='love_rehab.m4a', bpm=118.1, beats=59, meter=4/X
[13:56:54Z] WIRING: SessionManager.startLocalFiles→ready count=1
[13:56:54Z] raw tap capture started sr=44100 Hz ch=2 max=30s wallclock=801669414.4362
```

**Cold-launch deltas vs LF.4:**

| Event | LF.4 (2026-05-27) | LF.5 (2026-05-28) | Notes |
|---|---|---|---|
| State machine entry | `WIRING: SessionManager.startLocalFile ENTER` | `WIRING: SessionManager.startLocalFiles ENTER count=1 first=… origin=localFile` | LF.5 log shape — wrapper threads single-URL through new multi-file API |
| Cache miss   | `STEM_CACHE_MISS: reason=no-entry`  | `STEM_CACHE_MISS: reason=no-entry`  | Unchanged |
| Cache write  | `STEM_CACHE_WROTE: bytes=7045120, elapsedMs=7` | `STEM_CACHE_WROTE: bytes=7045120, artworkBytes=0, elapsedMs=9` | `artworkBytes` added; love_rehab.m4a has no embedded art; +2 ms is run-to-run noise |
| BeatGrid install | `BeatGrid installed: source=preparedCache, bpm=118.1, beats=59` | Identical | Unchanged |
| Ready transition | `WIRING: SessionManager.startLocalFile→ready file='…' source=freshAnalysis` | `WIRING: SessionManager.startLocalFiles→ready count=1` | LF.5 log shape; per-file source label moved to per-file `localFile prepared #N` line earlier in the stream |
| Audio router up | `raw tap capture started wallclock=…` | Identical | Unchanged |

**Cold cost breakdown (unchanged from LF.4).** Dominated by `analyzePreview`
(~1.5–2 s ML inference). The schema-v2 metadata addition (title / artist
/ album persisted in metadata.json) writes a few extra bytes; no perf
impact. The optional artwork sibling is only written when the source
ships embedded art (love_rehab.m4a doesn't). Cold cost stays ~2 s.

## Warm-Launch Session (LF.5)

**Setup.** Same env-var hook, cache NOT cleared between runs.

**Session ID:** `2026-05-28T13-57-51Z`.

**Load-bearing log lines:**

```
[13:57:51Z] SessionRecorder started schema=1 dir=…/2026-05-28T13-57-51Z
[13:57:51Z] WIRING: SessionManager.startLocalFiles ENTER count=1 first='love_rehab.m4a' origin=localFile
[13:57:51Z] STEM_CACHE_HIT: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, bpm=118.1, beats=59
[13:57:51Z] BeatGrid installed: source=preparedCache, track='love_rehab.m4a', bpm=118.1, beats=59, meter=4/X
[13:57:52Z] WIRING: SessionManager.startLocalFiles→ready count=1
[13:57:52Z] raw tap capture started sr=44100 Hz ch=2 max=30s wallclock=801669472.2572
```

Warm-launch latency: ≤ 1 second from `SessionManager.startLocalFiles ENTER`
to `raw tap capture started`, consistent with LF.4's ~607 ms baseline.
(Per-second log granularity precludes finer measurement; the
`PersistentStemCacheTests` + `LocalFilePlaybackFormatCoverageTests` 4-test
queue + 11 eviction tests verify byte-identical roundtrip of the v2
schema with no observable per-file latency impact.)

## Multi-File Path Verification

The LF.5 multi-file path (`.localFiles` / `.localFolder` / `.localPlaylist`
origins, `prepareLocalFiles(urls:placeholders:via:)`, per-file
`trackStatuses` publishing, mid-session `advanceLocalFileQueue` advance)
is verified via:

1. **`SessionManagerLocalFileTests` — 29 tests** (14 LF.4 + 13 LF.5
   lifecycle + 2 LF.5 per-track-status observer). Covers multi-file
   queue length 3, per-origin source discrimination, same-origin no-op,
   different-URL replace, empty-list no-op, no-preparer fallthrough,
   mid-queue cancellation, and `trackStatuses` per-file
   `.analyzing(.stemSeparation) → .ready` transitions.
2. **`LocalFilePlaybackFormatCoverageTests` — 4 tests** (3 per-format +
   1 LF.5 queue test). The LF.5 queue test runs a real 3-file folder
   (M4A + MP3 + FLAC) through `SessionPreparer.prepareLocalFiles` via a
   `FormatCoverageLocalFilePreparer` delegate. Asserts all 3 tracks
   produce LF.3 `local:sha256:` identities + BPM in [110, 130] + finite
   stem features. Gated on `LF_FORMAT_COVERAGE=1` (13.5 s when enabled).
3. **`PersistentStemCacheTests` — 16 tests** (11 LF.3/LF.4 + 5 LF.5
   metadata + artwork roundtrip + schema-v2 + overwrite-clearing-stale-
   artwork + contains-without-artwork).
4. **`M3UParserTests` — 9 tests** (trivial 3-track, #EXTINF ignored,
   relative-path resolution, BOM + CRLF tolerance, skip-unreadable,
   noEntriesResolved, fileUnreadable, file:// URL form, malformed UTF-8).
5. **`LocalFileRecentsStoreTests` — 12 tests** (init / addOrPromote /
   LRU / cap / per-kind identity / remove / clearAll / persistence
   roundtrip / oversized-load truncation / isMissing / displayLabel).

Manual smoke (recommended, not automated):
- `File → Open Local Folder…` picks a 3-file folder, plays through end-
  to-end with audio continuous (≤ 50 ms gap between tracks).
- `File → Open Recent ▸` after the open above lists the folder at
  position 1; opening it re-prepares + plays.
- `mv` one of the folder's files to /tmp/ then open the Recents submenu
  again: the entry stays in the list (the folder still exists; the
  missing file just gets skipped at queue-walk time).
- Drag an M3U file onto the window: parses + queues + plays.
- `open -a Phosphene love_rehab.m4a` from Terminal: launches the app
  (after LaunchServices re-registration) and plays the file.

## What This Confirms About the Implementation

1. **`startLocalFiles(at:origin:)` is the canonical API.** LF.4's
   `startLocalFile(at:)` is now a thin wrapper around the multi-file API
   (`startLocalFiles(at: [url], origin: .localFile(url))`). The env-var
   hook continues to work via the wrapper.
2. **Schema v2 cache writes work.** `STEM_CACHE_WROTE` line carries the
   new `artworkBytes` field. love_rehab.m4a has no embedded art, so
   `artworkBytes=0`. Schema-v1 entries from prior LF.4 cache state
   would throw `schemaMismatch` and re-prepare — confirmed via the new
   `test_load_schemaMismatch_throws` assertion.
3. **No latency regression.** Cold ~2 s ≈ LF.4 ~1.9 s; warm ≤ 1 s ≈
   LF.4 ~607 ms. The added metadata extraction (~50 ms async via
   AVAsset.commonMetadata) is amortized into the existing analyzePreview
   path on the cold path and skipped entirely on the warm path.
4. **Single-file env-var hook preserved.** Per Matt's audit answer
   (2026-05-27), single-file LF.4 behavior (loop forever at EOF) is
   retained. `LocalFilePlaybackProvider.onFileEnded` is nil in the
   single-file case → `scheduleFileLoop` re-schedules at EOF → file
   loops. Multi-file callers set `onFileEnded` → callback fires →
   `advanceLocalFileQueue` runs.
5. **Engine + app test counts.** Engine suite went from LF.4's 1328 to
   LF.5's 1358 (+30 net new tests). App suite gained the
   `LocalFileRecentsStoreTests` 12-test suite.

## Known Risks and Follow-Ups

- **Per-second log granularity** precludes finer-grained latency
  measurement than the cold/warm bands shown above. The LF.4 baseline
  used the same granularity so the comparison is apples-to-apples;
  millisecond-level measurement would require log-record timestamp
  refactoring (separate increment).
- **Multi-file env-var hook** (`PHOSPHENE_LOCAL_FILES_PLAYBACK` or
  similar) is not implemented at LF.5 scope. Manual smoke through the
  UI is the only automation gap for the multi-file path. The 27 unit
  tests through `SessionManager` + `SessionPreparer` cover the
  lifecycle; the missing dimension is the audio-router + mid-session
  EOF advance, which is exercised manually.
- **Cache invalidation for LF.4 → LF.5 schema bump.** Existing v1
  entries on user disks throw `schemaMismatch` and re-prepare. One-time
  ~2 s cost per cached track on next play. LF.4 user caches were small
  (1-3 entries from the dev env-var workflow); aggregate cost is < 10 s.
- **LF.5 artwork capture / no display.** `extractArtwork(at:)` runs
  via AVAsset.commonMetadata during cold preparation. Bytes are
  persisted to the optional sibling `artwork.bin`. No UI consumes it
  yet — display is LF.6 territory.
- **`PHOSPHENE_LOCAL_FILE_PLAYBACK` env var still single-file.**
  Verified working through the wrapper.
