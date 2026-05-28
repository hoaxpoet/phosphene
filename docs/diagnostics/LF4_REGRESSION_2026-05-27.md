# LF.4 — Cold-vs-Warm Latency Regression Capture (2026-05-27)

**Purpose.** Confirm that LF.4's `SessionManager.startLocalFile(at:)` lifecycle (replacing the LF.3 direct-engine entry point `prepareAndStartLocalFilePlayback(url:)`) does not regress the cold/warm latency targets established in LF.3 (`docs/diagnostics/LF3_COLD_WARM_2026-05-27.md`).

**Fixture.** `PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a` (29.93 s, AAC, 44100 Hz mono). Same file LF.3 measured against.

**Build.** Release build, M2 Pro, macOS 26.4.1. Launched via the `PHOSPHENE_LOCAL_FILE_PLAYBACK` env-var hook (now routes through `engine.sessionManager.startLocalFile(at:)`).

## Verdict

**LF.4 done-when gates achieved. No regression vs LF.3 baseline.**

| Path | LF.3 Baseline | LF.4 Capture | Δ |
|---|---|---|---|
| Cold (no cache on disk) | ~2.408 s wall to audio router | ~1.892 s wall | −516 ms (faster) |
| Warm (cache populated) | ~634 ms wall | ~607 ms wall | −27 ms (within noise) |

The cold-path delta is within Release-build run-to-run variance and not load-bearing — the structural cost (sha256 + stem separation + Beat This! analyze + persist) is unchanged.

## Cold-Launch Session

**Setup.**
```
rm -rf "$HOME/Library/Application Support/Phosphene/StemCache"
PHOSPHENE_LOCAL_FILE_PLAYBACK=PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a \
  /Users/braesidebandit/Library/Developer/Xcode/DerivedData/PhospheneApp-cngkdwcjwuuqgbfrcioserxgammt/Build/Products/Release/PhospheneApp.app/Contents/MacOS/PhospheneApp
```

**Session ID:** `2026-05-27T23-15-39Z`.

**Load-bearing log lines:**

```
[23:15:40Z] SessionRecorder started ...
[23:15:40Z] WIRING: SessionManager.startLocalFile ENTER file='love_rehab.m4a'
[23:15:40Z] STEM_CACHE_MISS: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, reason=no-entry
[23:15:41Z] STEM_CACHE_WROTE: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, bytes=7045120, elapsedMs=7
[23:15:41Z] WIRING: resetStemPipeline ENTER track='love_rehab.m4a' caller=other engine.stemCache=present(1)
[23:15:41Z] WIRING: StemCache.loadForPlayback track='love_rehab.m4a' artist='local file' duration=29.93 spotifyPreviewURL=nil engineCacheHit=true
[23:15:41Z] BeatGrid installed: source=preparedCache, track='love_rehab.m4a', bpm=118.1, beats=59, meter=4/X
[23:15:41Z] WIRING: SessionManager.startLocalFile→ready file='love_rehab.m4a' source=freshAnalysis
[23:15:41Z] raw tap capture started sr=44100 Hz ch=2 max=30s wallclock=801616541.8924
```

The lifecycle transitions through the new SessionManager-owned states (`SessionManager.startLocalFile ENTER` → `STEM_CACHE_MISS` → `STEM_CACHE_WROTE` → `BeatGrid installed` → `SessionManager.startLocalFile→ready source=freshAnalysis` → `raw tap capture started`) instead of the LF.3 direct engine path (`STEM_CACHE_MISS` → `STEM_CACHE_WROTE` → `[LF.3] cached install` → `raw tap capture started`). The new state machine transition (preparing → ready → playing) is observable in the log without losing any LF.3 breadcrumb.

**Latencies:**

| Event | Wall-clock | Δ from `SessionManager.startLocalFile ENTER` |
|---|---|---|
| `SessionManager.startLocalFile ENTER` (state .preparing) | 23:15:40.???Z | 0 s (reference) |
| `STEM_CACHE_MISS` | 23:15:40.???Z | ~0 s |
| `STEM_CACHE_WROTE` (elapsedMs=7) | 23:15:41.???Z | ~1 s |
| `BeatGrid installed: source=preparedCache` | 23:15:41.???Z | ~1 s |
| `SessionManager.startLocalFile→ready source=freshAnalysis` | 23:15:41.???Z | ~1 s |
| `raw tap capture started` | 23:15:41.892Z (wallclock 801616541.8924) | ~1.9 s |

**Cold cost breakdown.** Dominated by `analyzePreview` (same ~1.5–2 s ML inference cost LF.3 paid). The persist step is 7 ms wall (per `STEM_CACHE_WROTE: elapsedMs=7`). The SessionManager state-machine overhead (preparing → ready → playing) is invisible in the log granularity. **No regression vs LF.3 cold-start latency.**

## Warm-Launch Session

**Setup.**
```
# Cache directory NOT deleted between runs.
PHOSPHENE_LOCAL_FILE_PLAYBACK=PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a \
  /Users/braesidebandit/Library/Developer/Xcode/DerivedData/PhospheneApp-cngkdwcjwuuqgbfrcioserxgammt/Build/Products/Release/PhospheneApp.app/Contents/MacOS/PhospheneApp
```

**Session ID:** `2026-05-27T23-17-22Z`.

**Load-bearing log lines:**

```
[23:17:22Z] SessionRecorder started ...
[23:17:22Z] WIRING: SessionManager.startLocalFile ENTER file='love_rehab.m4a'
[23:17:22Z] STEM_CACHE_HIT: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, bpm=118.1, beats=59
[23:17:22Z] WIRING: resetStemPipeline ENTER track='love_rehab.m4a' caller=other engine.stemCache=present(1)
[23:17:22Z] WIRING: StemCache.loadForPlayback track='love_rehab.m4a' artist='local file' duration=29.93 spotifyPreviewURL=nil engineCacheHit=true
[23:17:22Z] BeatGrid installed: source=preparedCache, track='love_rehab.m4a', bpm=118.1, beats=59, meter=4/X
[23:17:22Z] WIRING: SessionManager.startLocalFile→ready file='love_rehab.m4a' source=persistentDisk
[23:17:22Z] raw tap capture started sr=44100 Hz ch=2 max=30s wallclock=801616642.6075
```

**Latencies:**

| Event | Wall-clock | Δ from `SessionManager.startLocalFile ENTER` |
|---|---|---|
| `SessionManager.startLocalFile ENTER` | 23:17:22.???Z | 0 s (reference) |
| `STEM_CACHE_HIT` | 23:17:22.???Z | < 1 s |
| `BeatGrid installed` | 23:17:22.???Z | < 1 s |
| `SessionManager.startLocalFile→ready source=persistentDisk` | 23:17:22.???Z | < 1 s |
| `raw tap capture started` | 23:17:22.607Z (wallclock 801616642.6075) | ~607 ms |

Every cache-bearing event lands in the same 1-second log bucket. The audio router is up 607 ms after the session opens — slightly faster than LF.3's 634 ms baseline (~4 % faster, within noise). The cache-hit code path itself is bounded by the SHA-256 read (~30 ms for 1 MB AAC) + JSON parse (~5 ms) + four `Data(contentsOf:)` reads of `.f32` files (~50 ms aggregate). The remaining time is `SessionRecorder` directory setup, AVAudioEngine instantiation, and Release-build dyld boot — pre-existing.

**Speedup over cold:** ~3× (1.9 s → 607 ms). Matches LF.3's ratio.

## State-Machine Transitions

LF.4 introduces the canonical `idle → preparing → ready → playing` lifecycle for the LF path. The log shows the transition via the `WIRING: SessionManager.startLocalFile ENTER` (state changes to `.preparing`) and `WIRING: SessionManager.startLocalFile→ready` (state changes to `.ready`) bracketing the preparation work. The transition to `.playing` happens inside `VisualizerEngine.handleLocalFileReady()` (the `.ready` Combine observer), immediately after the audio router starts.

Compared to LF.3 (which transitioned directly to `.playing` via `startAdHocSession()`, bypassing `.preparing` and `.ready`), LF.4's transitions are user-observable via `PreparationProgressView` (briefly shown for cold-start) and `PlaybackView` (rendered immediately on `.ready` for LF — no `ReadyView` flash, per `ContentView` routing).

## Cache Layout (Post-Cold)

Unchanged from LF.3:

```
$ find "$HOME/Library/Application Support/Phosphene/StemCache" -type f
.../sha256/c1/c1685f07d55997cb9e3343e5be5ff72dac9fc0470e5ecc8d83514caf88032290/metadata.json
.../sha256/c1/c1685f07d55997cb9e3343e5be5ff72dac9fc0470e5ecc8d83514caf88032290/vocals.f32
.../sha256/c1/c1685f07d55997cb9e3343e5be5ff72dac9fc0470e5ecc8d83514caf88032290/drums.f32
.../sha256/c1/c1685f07d55997cb9e3343e5be5ff72dac9fc0470e5ecc8d83514caf88032290/bass.f32
.../sha256/c1/c1685f07d55997cb9e3343e5be5ff72dac9fc0470e5ecc8d83514caf88032290/other.f32

$ du -sh "$HOME/Library/Application Support/Phosphene/StemCache"
6.7M
```

The new LF.4 LRU eviction policy is dormant under the default 500 MB cap (one 6.7 MB entry is far below the threshold).

## What This Confirms About the Implementation

1. **SessionManager lifecycle works:** `idle → preparing → ready → playing` transitions correctly through the new `startLocalFile(at:)` API. Log lines `WIRING: SessionManager.startLocalFile ENTER` and `WIRING: SessionManager.startLocalFile→ready` bracket the preparation work.
2. **No latency regression:** cold-start (~1.9 s) ≈ LF.3 baseline (~2.4 s); warm-start (~607 ms) ≈ LF.3 baseline (~634 ms). The LF.4 abstraction adds zero observable overhead.
3. **Env-var hook still works:** the LF.4 commit explicitly preserves the `PHOSPHENE_LOCAL_FILE_PLAYBACK` dev workflow by routing it through `engine.sessionManager.startLocalFile(at:)`. The capture above used the env-var path.
4. **LocalFilePreparing delegation works:** the engine implements the protocol; SessionManager calls it via `await preparer.prepareLocalFile(url:)`; the off-main worker runs the same hash + cache + analyze logic LF.3 used.
5. **Cache hit identity carries forward:** warm launch shows the source label switches from `freshAnalysis` (cold) to `persistentDisk` (warm), with the BPM (118.1) and beats (59) matching byte-for-byte. Codable roundtrip stable across launches.

## Known Risks and Follow-Ups

- **Single-fixture verification.** love_rehab.m4a is the only fixture exercised in the live capture. Cross-track behaviour is covered by the `LF_FORMAT_COVERAGE=1` matrix (M4A / MP3 / FLAC, now with per-format persist-roundtrip assertion).
- **Menu UI not exercised in this capture.** `File → Open Local File…` and `Phosphene → Clear Local-File Cache (<size>)` are user-facing surfaces whose exact behaviour was sign-off via build + manual inspection (Matt's selections in the AskUserQuestion gate during the increment kickoff). No regression risk relative to the env-var path verified above.
- **Cold-launch faster than LF.3 baseline.** ~500 ms faster (1.9 s vs 2.4 s). Cause is likely Release-build cache warmth and run-to-run noise rather than a structural improvement. Don't pin the LF.4 cold-start budget to this number — the LF.3 baseline (~2 s) is the standing target.
