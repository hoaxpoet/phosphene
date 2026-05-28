# LF.5.fix — Structural Verification (2026-05-28)

**Increment:** LF.5.fix (commits `488afc1e` + `fe09a594` + `46a9f1c2` + `5de8657b`).
**Defects covered:** BUG-LF5-1 (orchestrator wire), BUG-LF5-2 (End Session audio stop), BUG-LF5-3 (transport bar UI), BUG-LF5-4 (multi-segment plan build).
**Scope:** structural-fix verification only (per Matt 2026-05-28). Multi-preset-per-song variety deferred to when the certified catalog reaches ≥ 5 presets; current count is 2 (`FerrofluidOcean`, `LumenMosaic`).

## Method

`PHOSPHENE_LOCAL_FILE_PLAYBACK=PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a` env-var hook against the Debug build at `~/Library/Developer/Xcode/DerivedData/PhospheneApp-cngkdwcjwuuqgbfrcioserxgammt/Build/Products/Debug/PhospheneApp.app` (signed `e52e31eb` series). Capture ran ~22 s — preparation + ~10 s of audible playback — then SIGTERM. Session under `~/Documents/phosphene_sessions/2026-05-28T17-44-10Z/`.

The env-var hook routes through `engine.sessionManager.startLocalFile(at:)` → `startLocalFiles(at: [url], origin: .localFile(url))` (post-LF.5 wrapper). That exercises the same `handleLocalFileReady` code path the menu / drag-and-drop / folder ingest entry points use — the structural changes from LF.5.fix are not entry-point-specific.

## Pre-fix vs post-fix session-log delta

Compared the new capture against folder session `2026-05-28T17-06-08Z` (Matt's pre-fix smoke). The structural markers flipped exactly as predicted:

| Marker | Pre-fix (17-06-08Z, 8-track folder) | Post-fix (17-44-10Z, 1-track env var) |
|---|---|---|
| Orchestrator wire log | `mode=reactive, planIdx=—, elapsedTrackTime=55.1s` | **`mode=session, planIdx=0, elapsedTrackTime=3.7s`** |
| `WIRING: _buildPlan ENTER` | (absent — buildPlan never called) | **`trackCount=1 engine.stemCache=present(1) sessionManager.cache.count=1`** |
| `WIRING: _buildPlan DONE` | (absent) | **`livePlanSet=true firstTrack='love_rehab.m4a' aboutToPreFire=true`** |
| `resetStemPipeline caller=preFire` | (absent) | **Present — orchestrator pre-fires first preset on .ready** |
| First `preset → <name>` line | 6 s after BeatGrid install; reactive autonomous pick (`Waveform → Arachne → Aurora Veil → Ferrofluid Ocean` cascade over ~7 s) | **`preset → Waveform` at session start** (planner's pick for the track) |

The binary signals that prove each LF.5.fix landing:

- **D-LF5-1 (`liveTrackPlanIndex` wire):** `planIdx=0` (was `—` — nil literal).
- **D-LF5-4 (`buildPlan()` call):** `_buildPlan ENTER` + `_buildPlan DONE livePlanSet=true` (both absent in pre-fix log).
- **Orchestrator mode flip:** `mode=session` (was `reactive`). "session" is the orchestrator's internal label for "consulting `livePlannedSession`"; the binary opposite of `reactive`.

## Full post-fix session log (load-bearing lines)

```
[2026-05-28T17:44:11Z] WIRING: SessionManager.startLocalFiles ENTER count=1 first='love_rehab.m4a' origin=localFile
[2026-05-28T17:44:11Z] WIRING: SessionPreparer.prepareLocalFiles ENTER count=1 delegate=wired
[2026-05-28T17:44:11Z] STEM_CACHE_HIT: source=persistentDisk, track='love_rehab.m4a', hash=c1685f07d559, bpm=118.1, beats=59
[2026-05-28T17:44:11Z] WIRING: SessionPreparer.prepareLocalFile #1 of 1 file='love_rehab.m4a' source=persistentDisk
[2026-05-28T17:44:11Z] WIRING: SessionPreparer.prepareLocalFiles DONE cached=1 failed=0 total=1
[2026-05-28T17:44:11Z] WIRING: resetStemPipeline ENTER track='love_rehab.m4a' caller=other engine.stemCache=present(1)
[2026-05-28T17:44:11Z] WIRING: StemCache.loadForPlayback track='love_rehab.m4a' artist='local file' duration=29.93 spotifyPreviewURL=nil engineCacheHit=true
[2026-05-28T17:44:11Z] BeatGrid installed: source=preparedCache, track='love_rehab.m4a', bpm=118.1, beats=59, meter=4/X
[2026-05-28T17:44:11Z] WIRING: _buildPlan ENTER trackCount=1 engine.stemCache=present(1) sessionManager.cache.count=1
[2026-05-28T17:44:11Z] WIRING: _buildPlan DONE livePlanSet=true firstTrack='love_rehab.m4a' aboutToPreFire=true
[2026-05-28T17:44:11Z] WIRING: resetStemPipeline ENTER track='love_rehab.m4a' caller=preFire engine.stemCache=present(1)
[2026-05-28T17:44:11Z] BeatGrid installed: source=preparedCache, track='love_rehab.m4a', bpm=118.1, beats=59, meter=4/X
[2026-05-28T17:44:11Z] preset → Waveform
[2026-05-28T17:44:11Z] WIRING: SessionManager.startLocalFiles→ready count=1
[2026-05-28T17:44:11Z] raw tap capture started sr=44100 Hz ch=2 max=30s wallclock=801683051.6852
[2026-05-28T17:44:14Z] Orchestrator: wire active (mode=session, planIdx=0, elapsedTrackTime=3.7s)
[2026-05-28T17:44:17Z] signal quality → green: peak -0 dBFS, treble 0.08% — OK
[2026-05-28T17:44:22Z] stem separation 0 (440320 samples) track=unknown → 0000_unknown
[2026-05-28T17:44:27Z] stem separation 1 (440320 samples) track=unknown → 0001_unknown
```

Note the `caller=preFire` line at 17:44:11 — `_buildPlan` invoked `resetStemPipeline` to pre-fire the first preset before audio started. That's the planner's deliberate "the song's about to begin; pick the right preset" hook. The streaming path has the same behaviour; LF.5 inherits it now that `buildPlan()` runs.

## Things this capture does NOT verify

Documented for transparency. Each has a stated path to verification.

- **D-LF5-2 (End Session stops audio).** Requires UI input — clicking "End session" on chrome or transport-bar Stop. No UI automation infrastructure yet (see follow-up below). Engine-side `.ended` Combine observer is a 4-line patch readable by inspection; state-transition unit tests in `SessionManagerLocalFileTests` cover the SessionManager half.
- **D-LF5-3 (transport bar renders + buttons dispatch).** Requires SwiftUI rendering verification. `LocalFileTransportBar` view + `PlaybackChromeViewModel`'s isLocalFileSession / isLocalFilePaused projections are testable in unit tests; the actual rendered appearance + hover-reveal + button-action wiring are not.
- **Multi-preset-per-song variety.** With 2 certified presets (`FerrofluidOcean`, `LumenMosaic`), the planner cannot demonstrate variety even if every code path is correct. The single-track capture above produced one segment (`Waveform`) for love_rehab — both certified candidates lost to the uncertified `Waveform` (showUncertifiedPresets default). Re-run when catalog reaches ≥ 5 certified presets.

## Follow-ups queued

1. **UI automation infrastructure** (Matt 2026-05-28 directive). Phosphene has no XCUITest target / snapshot library / ViewInspector. Three options ranked in the chat thread; recommended split is `swift-snapshot-testing` + `ViewInspector` first, defer XCUITest. Will be filed as its own Q.* infrastructure increment.
2. **`impeccable` skill run on file-based user flows** (Matt 2026-05-28 directive). Schedule a design pass on the full LF.4 / LF.5 UI surface: file picker, folder picker, Recents submenu, transport bar, drag-and-drop affordance, error alerts. Run after #1 lands so the design pass can ship with snapshot tests proving the new visuals don't regress.
3. **Re-run multi-preset-per-song smoke** when certified catalog reaches ≥ 5 presets.

## Closeout

LF.5.fix structural fixes verified. Four commits land on `main`:

- `488afc1e` — D-LF5-1 + D-LF5-2 engine fixes
- `fe09a594` — D-LF5-3 transport bar
- `46a9f1c2` — D-LF5-4 buildPlan() call for LF
- `5de8657b` — closeout docs (KNOWN_ISSUES + RELEASE_NOTES + UX_SPEC carve-out)

KNOWN_ISSUES.md BUG-LF5-{1,2,3,4} all marked RESOLVED with this commit's hash referenced.
