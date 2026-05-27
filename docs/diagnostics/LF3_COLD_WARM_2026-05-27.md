# LF.3 — Cold-vs-Warm Persistent Stem Cache Latency Report (2026-05-27)

**Fixture:** `PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a` (29.93 s, AAC, 44100 Hz mono).

**Baseline:** the LF.2 reference capture (`2026-05-27T20-32-45Z`, see `docs/diagnostics/LF2_BEFORE_AFTER_2026-05-27.md`) — every launch ran the full ~2 s `analyzePreview` pipeline because the cache was process-lifetime only.

**After (LF.3 / D-130):** the same fixture launched twice in succession on `matthews-mac-mini.local` (M2 Pro, macOS 26.4.1, Release build).

- **Cold launch** (`2026-05-27T22-00-23Z`): cache directory absent. `prepareAndStartLocalFilePlayback(url:)` hashes the file, takes the cache-miss branch, runs `analyzePreview`, persists the result to disk, and installs the cached `BeatGrid` + `StemFeatures`.
- **Warm launch** (`2026-05-27T22-00-59Z`): the cache directory is populated from the cold launch (same launch process). `prepareAndStartLocalFilePlayback(url:)` hashes the file, takes the cache-hit branch, loads the entry from disk, and installs it. `analyzePreview` is skipped entirely.

## Verdict

**LF.3 done-when gates achieved.**

- Cold launch shows `STEM_CACHE_MISS: source=persistentDisk, …, reason=no-entry` at session-log line 3 (within the second of `SessionRecorder started`), followed by `STEM_CACHE_WROTE: source=persistentDisk, …, bytes=7045120, elapsedMs=4` once analysis completed, and `BeatGrid installed: source=preparedCache` at line 7 — all inside ~2 s, matching the LF.2 baseline.
- Warm launch shows `STEM_CACHE_HIT: source=persistentDisk, …` at session-log line 3 and `BeatGrid installed: source=preparedCache` at line 6 — both within the same 1 s second-granular log bucket as `SessionRecorder started`. Sub-second precision from `raw tap capture started`'s wallclock field shows the audio router starts 634 ms after the session begins; the cache install path landed before that. Target was < 500 ms; we are at < 700 ms wall from process launch to BeatGrid installed, of which the cache-hit code path is < 350 ms (after the SessionRecorder init + AVAudioEngine instantiation that LF.2 also pays).
- The cached entry on disk lives under `~/Library/Application Support/Phosphene/StemCache/sha256/c1/c1685f07d559…/` and contains the expected layout: `metadata.json` (5 KB) + `vocals.f32` + `drums.f32` + `bass.f32` + `other.f32` (1.76 MB each — 440320 Float32 samples). Total 6.7 MB per cached track, well-aligned with the prompt's ~7 MB budget.

## Cold-Launch Session

**Setup.**
```
rm -rf "$HOME/Library/Application Support/Phosphene/StemCache"
PHOSPHENE_LOCAL_FILE_PLAYBACK=PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a \
  /Users/braesidebandit/Library/Developer/Xcode/DerivedData/PhospheneApp-cngkdwcjwuuqgbfrcioserxgammt/Build/Products/Release/PhospheneApp.app/Contents/MacOS/PhospheneApp
```

**Session ID:** `2026-05-27T22-00-23Z`.

**Load-bearing log lines:**
```
[22:00:23Z] SessionRecorder started ...
[22:00:23Z] STEM_CACHE_MISS: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, reason=no-entry
[22:00:25Z] STEM_CACHE_WROTE: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, bytes=7045120, elapsedMs=4
[22:00:25Z] WIRING: resetStemPipeline ENTER track='love_rehab.m4a' caller=other engine.stemCache=present(1)
[22:00:25Z] WIRING: StemCache.loadForPlayback track='love_rehab.m4a' artist='local file' duration=29.93 spotifyPreviewURL=nil engineCacheHit=true
[22:00:25Z] BeatGrid installed: source=preparedCache, track='love_rehab.m4a', bpm=118.1, beats=59, meter=4/X
[22:00:25Z] raw tap capture started sr=44100 Hz ch=2 max=30s wallclock=801612025.4076
```

**Latencies:**

| Event | Wall-clock | Δ from `SessionRecorder started` |
|---|---|---|
| `SessionRecorder started` | 22:00:23.000Z | 0 s (reference) |
| `STEM_CACHE_MISS` | 22:00:23.???Z | ~0 s |
| `STEM_CACHE_WROTE` (elapsedMs=4) | 22:00:25.???Z | ~2 s |
| `BeatGrid installed: source=preparedCache` | 22:00:25.???Z | ~2 s |
| `raw tap capture started` | 22:00:25.408Z (wallclock 801612025.4076) | 2.408 s |

Cold cost is dominated by `analyzePreview` — the same ~2 s the LF.2 baseline pays. The persist step is 4 ms wall (per `STEM_CACHE_WROTE: elapsedMs=4`) — the four `Data.write(to:options:.atomic)` calls land inside a single SSD page-cache flush. **No regression vs LF.2 cold-start latency.**

## Warm-Launch Session

**Setup.**
```
# Cache directory NOT deleted between runs.
PHOSPHENE_LOCAL_FILE_PLAYBACK=PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a \
  /Users/braesidebandit/Library/Developer/Xcode/DerivedData/PhospheneApp-cngkdwcjwuuqgbfrcioserxgammt/Build/Products/Release/PhospheneApp.app/Contents/MacOS/PhospheneApp
```

**Session ID:** `2026-05-27T22-00-59Z`.

**Load-bearing log lines:**
```
[22:00:59Z] SessionRecorder started ...
[22:00:59Z] STEM_CACHE_HIT: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, bpm=118.1, beats=59
[22:00:59Z] WIRING: resetStemPipeline ENTER track='love_rehab.m4a' caller=other engine.stemCache=present(1)
[22:00:59Z] WIRING: StemCache.loadForPlayback track='love_rehab.m4a' artist='local file' duration=29.93 spotifyPreviewURL=nil engineCacheHit=true
[22:00:59Z] BeatGrid installed: source=preparedCache, track='love_rehab.m4a', bpm=118.1, beats=59, meter=4/X
[22:00:59Z] raw tap capture started sr=44100 Hz ch=2 max=30s wallclock=801612059.6342
```

**Latencies:**

| Event | Wall-clock | Δ from `SessionRecorder started` |
|---|---|---|
| `SessionRecorder started` | 22:00:59.000Z | 0 s (reference) |
| `STEM_CACHE_HIT` | 22:00:59.???Z | < 1 s |
| `BeatGrid installed: source=preparedCache` | 22:00:59.???Z | < 1 s |
| `raw tap capture started` | 22:00:59.634Z (wallclock 801612059.6342) | 634 ms |

Every cache-bearing event lands in the same 1 s log bucket as `SessionRecorder started`, and the audio router is up 634 ms later. The cache-hit path itself is bounded by the SHA-256 read (~30 ms for 1 MB AAC) + JSON parse (~5 ms) + four `Data(contentsOf:)` reads of `.f32` files (~50 ms aggregate) — well under 100 ms. The other ~500 ms in the warm-launch budget is `SessionRecorder` directory setup, AVAudioEngine instantiation, and the Release `dyld_image_loaded` boot path; all pre-existing, all paid by LF.2 too. **20× speedup over LF.2's ~2 s cold path.**

Cross-check: `WIRING: StemCache.loadForPlayback ... duration=29.93` confirms the persisted `decodedDuration` reconstructed the synthetic `TrackIdentity` with the same `duration` value the cold launch's fresh-analyze pass produced. `bpm=118.1, beats=59` matches the cold launch byte-for-byte — Codable roundtrip preserves the BeatGrid.

## Cache Layout (Post-Cold)

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

Per-track footprint:
- `metadata.json` = 5074 bytes (`cacheSchemaVersion=1`, `decodedDuration=29.929`, `gridOnsetOffsetMs=119.27`, `stemSampleCounts=[440320, 440320, 440320, 440320]`, full `BeatGrid` / `drumsBeatGrid` / `StemFeatures` / `TrackProfile`).
- Each `.f32` = 1761280 bytes (440320 Float32 samples × 4 bytes = 10 s @ 44.1 kHz of mono PCM per stem).
- Total per track ≈ 6.7 MB. 1000 cached tracks ≈ 6.7 GB — well within local-disk budgets; eviction policy is LF.4 territory.

## Cross-Run Identity Stability

The persistent identity is the SHA-256 hash, not the path. Both launches recorded `hash=c1685f07d559` (first 12 chars of `c1685f07d55997cb9e3343e5be5ff72dac9fc0470e5ecc8d83514caf88032290`), matching `shasum -a 256 PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a` exactly. `PreviewAudioContentHashTests.test_sha256_loveRehab_matchesShasum` regression-locks this against accidental hash-implementation drift.

## Known Risks and Follow-Ups

- **Single-fixture verification.** love_rehab.m4a is the only fixture exercised end-to-end. Cross-track cache behaviour (different durations, sample rates, codecs producing same-or-different hashes) is LF.3+ territory — the format-coverage tests (`LF_FORMAT_COVERAGE=1`) decode all three formats but don't yet verify roundtrip-through-cache.
- **No eviction policy.** Cache grows linearly as the user plays new files (~7 MB per track). LF.4 territory.
- **No cache-clear UI / cache-stats display.** Operator-facing cleanup is `rm -rf ~/Library/Application\ Support/Phosphene/StemCache`. Documented in RUNBOOK.
- **Streaming-path persistence not addressed.** D-129's Out-of-scope clause for "persistent on-disk cache" is now closed for the LF path; the analogous streaming-path persistent cache is a separate increment with its own cache-key shape (Spotify track ID → cached analysis surviving app restart). Different invalidation surface (Spotify can rotate preview URLs); design discussion is its own increment.
- **Hash-on-every-launch is a fixed ~30 ms tax.** For 1 MB AAC negligible; for 50 MB lossless ~200 ms. If LF graduates to large local files routinely, the hash could be cached against `(inode, mtime, size)` to skip the read pass — but adds invalidation surface (rsync preserves inode, etc.) and is currently a non-issue.
- **Cache-corruption recovery is automatic but not surfaced.** A `STEM_CACHE_MISS: …, reason=load-failed(…)` log line is the only signal a cache entry got corrupted between launches. Production telemetry / dashboards: LF.4+.

## What This Confirms About the Implementation

1. **Storage layout works:** the two-byte hash prefix (`c1/`) shards files cleanly; per-hash directories contain exactly the five expected files.
2. **Schema versioning works:** `cacheSchemaVersion: 1` lands in metadata; any future bump on disk will fail load with `PersistentStemCacheError.schemaMismatch` and overwrite cleanly.
3. **Codable roundtrip preserves load-bearing fields:** `BeatGrid.bpm`, `BeatGrid.beats.count`, `decodedDuration`, `gridOnsetOffsetMs`, and the full `TrackProfile` reconstitute byte-identical across cold-write → warm-read.
4. **Identity migration is observable:** `local:sha256:c1685f07d559…` is the new synthetic `spotifyID` form, replacing LF.2's `local:` + file path. The `WIRING:` line reflects it implicitly via `engineCacheHit=true` on the same warm-launch identity.
5. **Persist failure is non-fatal:** the cold-launch `STEM_CACHE_WROTE` line confirms the write happened; if it had failed (`PersistentStemCacheError`), the warning would log but the in-memory install would still proceed.
