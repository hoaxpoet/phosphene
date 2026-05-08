Execute Increment QR.3 (TEST.1) — Close silent-skip test holes.

Authoritative spec: docs/ENGINEERING_PLAN.md §Phase QR §Increment QR.3.
Authoritative defect taxonomy: docs/QUALITY/DEFECT_TAXONOMY.md;
KNOWN_ISSUES.md for BUG-002 (PresetVisualReviewTests staged-preset
PNG-export bug) and BUG-003 (DSP.3.6/3.7 tests not yet implemented).

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. QR.1 (D-079) and QR.2 (D-080) must have landed. Verify with
   `git log --oneline | grep -E '\[QR\.(1|2)\]'` — expect at least one
   commit per increment.

2. BUG-009 must have landed. Verify with
   `git log --oneline | grep '\[BUG-009\]'` — expect commit
   `eada589e` ending with `halving threshold 160 → 175 BPM …`.
   (Doesn't gate QR.3 directly but the BPM ranges referenced in the
   `LiveDriftValidationTests` setup will assume the post-BUG-009
   threshold.)

3. Confirm QR.3 surface is unstarted: the eight test files listed in
   SCOPE below should NOT yet exist.
   `for f in BeatThisFixturePresenceGate BeatThisStemReshapeTests \
            BeatThisRoPEPairingTests LiveDriftValidationTests \
            PresetLoaderCompileFailureTest SpotifyItemsSchemaTests \
            MoodClassifierGoldenTests ; do
      find PhospheneEngine/Tests -name "${f}.swift" ; done`
   — expect zero results.

4. Decision-ID numbering: D-089 was the most recent (DASH.7.2). The
   next available is **D-090**. Verify with
   `grep '^## D-0' docs/DECISIONS.md | tail -3`.

5. Existing test-suite baseline (do NOT modify these files except as
   spec'd):

   - `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisLayerMatchTests.swift`
     — currently uses silent `print(... skipping ...)` + `return` when
     fixtures are absent (lines 97–104). QR.3 changes this to
     `Issue.record(...)` (hard fail on missing fixtures).

   - `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisBugRegressionTests.swift`
     — already uses `Issue.record(...)` at the right spots. Audit; if
     you find a silent skip on missing fixtures, fix it.

   - `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift`
     — `makeBGRAPipeline` calls `Bundle.module.url(forResource: "Shaders")`
     against the test target's bundle (which has no `Shaders` resource).
     Staged presets fail with `cgImageFailed` at PNG export. BUG-002.
     Fix is one line: `Bundle(for: PresetLoader.self).url(forResource: "Shaders", ...)`.

   - `PhospheneEngine/Sources/Presets/PresetLoader.swift` —
     `public private(set) var presets: [LoadedPreset] = []`. Production
     count is currently 14 (14 .json sidecars in
     `PhospheneEngine/Sources/Presets/Shaders/`; `ShaderUtilities.metal`
     has no sidecar and is not a preset). Verify with
     `ls PhospheneEngine/Sources/Presets/Shaders/*.json | wc -l`.

   - `PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a` — existing
     audio fixture, used by `BeatThisLayerMatchTests`. Re-used by the
     new `LiveDriftValidationTests` (sub-scope item 6).

   - `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/beat_this_reference/love_rehab_reference.json`
     — existing Beat This! reference fixture. Useful for the cached
     BeatGrid that `LiveDriftValidationTests` installs.

   - `docs/diagnostics/DSP.2-S8-python-activations.json` — Python
     reference fixture for `BeatThisLayerMatchTests`. Big binary blob
     intentionally NOT in the test bundle (lives in `docs/`); the
     fixture-presence gate (item 1) will assert it exists.

6. `default.profraw` may be present in the repo root. Ignore.

────────────────────────────────────────
GOAL
────────────────────────────────────────

Eliminate the class of test-suite failures that pass silently when a
fixture is missing or a harness is broken. Two of four DSP.2 S8 bugs
are *only* catchable by `BeatThisLayerMatchTests`, which silently
skips on a fresh checkout because the fixtures aren't bundled. The
DSP.2 hardening commits regression-locked the bugs by name but the
gate is silent — a future contributor pulling the repo without the
fixtures gets a green test run with the entire S8 regression surface
gone. Same shape of risk for `PresetVisualReviewTests` (broken for
staged presets — Arachne V.7.7A through V.7.7B+ are invisible to the
harness), the orchestrator's reactive path (no closed-loop
musical-sync test), `PresetLoader` (silent compilation failure
drops a preset from the fixture, see Failed Approach #44), the
Spotify connector (Failed Approach #45 has no regression test), and
`MoodClassifier` (3,346 hardcoded weights, no golden-fixture test
flagged the ML reviewer's audit).

This increment lands nine sub-tests (eight new + one in-place fix
of `BeatThisLayerMatchTests`) that close those holes.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

The plan has nine sub-items. Land them in two commit boundaries
(grouping is per-commit; within a commit, sub-items can land in any
internal order). Each sub-item below has a concrete file path, a
concrete test list, and concrete assertions to write.

──── COMMIT 1: ML / harness gates (sub-items 1–5) ────

1. NEW FILE — `BeatThisFixturePresenceGate.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisFixturePresenceGate.swift`

   ```swift
   @Suite("BeatThisFixturePresenceGate")
   struct BeatThisFixturePresenceGate {

       @Test("love_rehab.m4a is present in the test fixtures tree")
       func test_loveRehabAudioFixturePresent() {
           let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
           let audioURL = testDir
               .deletingLastPathComponent()  // PhospheneEngineTests/
               .deletingLastPathComponent()  // Tests/
               .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
           #expect(FileManager.default.fileExists(atPath: audioURL.path),
                   "love_rehab.m4a missing at \(audioURL.path) — BeatThisLayerMatchTests + LiveDriftValidationTests will be silently disabled. Restore the fixture before committing.")
       }

       @Test("DSP.2-S8-python-activations.json is present at the repo-relative path")
       func test_pythonActivationsJSONPresent() {
           let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
           let jsonURL = testDir
               .deletingLastPathComponent()  // PhospheneEngineTests/
               .deletingLastPathComponent()  // Tests/
               .deletingLastPathComponent()  // PhospheneEngine/
               .deletingLastPathComponent()  // repo root
               .appendingPathComponent("docs/diagnostics/DSP.2-S8-python-activations.json")
           #expect(FileManager.default.fileExists(atPath: jsonURL.path),
                   "Python activations JSON missing at \(jsonURL.path) — BeatThisLayerMatchTests cannot run end-to-end. The file is committed under docs/diagnostics/; if absent, your checkout is incomplete.")
       }
   }
   ```

   These tests *fail* on a missing fixture (do not skip). Locks the
   fixture supply chain.

2. EDIT — `BeatThisLayerMatchTests.swift` skip → fail
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisLayerMatchTests.swift`

   Replace lines 97–104:

   ```swift
   guard FileManager.default.fileExists(atPath: audioURL.path) else {
       print("BeatThisLayerMatchTests: skipping — audio fixture absent at \(audioURL.path)")
       return
   }
   guard FileManager.default.fileExists(atPath: jsonURL.path) else {
       print("BeatThisLayerMatchTests: skipping — JSON fixture absent at \(jsonURL.path)")
       return
   }
   ```

   With:

   ```swift
   guard FileManager.default.fileExists(atPath: audioURL.path) else {
       Issue.record("BeatThisLayerMatchTests: audio fixture absent at \(audioURL.path) — BeatThisFixturePresenceGate should also be failing; fix that first.")
       return
   }
   guard FileManager.default.fileExists(atPath: jsonURL.path) else {
       Issue.record("BeatThisLayerMatchTests: JSON fixture absent at \(jsonURL.path) — see docs/diagnostics/DSP.2-S8-python-activations.json")
       return
   }
   ```

   Audit `BeatThisBugRegressionTests.swift` for the same pattern.
   That file already uses `Issue.record(...)` for missing
   `predictDiagnostic` keys (line 73–74), but check the fixture-loading
   branch — if it has a silent skip path, replace identically.

3. NEW FILE — `BeatThisStemReshapeTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisStemReshapeTests.swift`

   Standalone test for DSP.2 S8 Bug 2 (stem reshape transpose).
   Bug 2: pre-fix `[T, F]` was byte-reinterpreted to `[1, F, T, 1]`
   instead of transposed-then-reshaped, scrambling the mel
   spectrogram into the conv. Post-fix: transpose first, then reshape.

   Synthetic input with a known per-mel pattern (e.g. a one-hot
   spectrogram where only mel bin 7 has non-zero values at every
   time step). Run `BeatThisModel.predictDiagnostic` (or the lower-
   level reshape-and-conv path if exposed); assert that
   `stem.bn1d[t, mel]` for `mel == 7` is consistently large across
   `t` and near-zero for other mels. This is what the transpose-then-
   reshape produces; the byte-reinterpret would scramble it.

   Approximate shape:

   ```swift
   @Suite("BeatThisStemReshape")
   struct BeatThisStemReshapeTests {
       @Test("stem.bn1d preserves per-mel structure (transpose, not byte-reinterpret) — DSP.2 S8 Bug 2")
       func test_stemReshapePreservesPerMelStructure() throws {
           guard let device = MTLCreateSystemDefaultDevice() else {
               try withKnownIssue { Issue.record("Metal device unavailable") }
               return
           }
           let model = try BeatThisModel(device: device)
           let frameCount = 64
           let melCount = 128
           let activeMel = 7
           // Build [T, F] with one-hot mel pattern.
           var spect = [Float](repeating: 0, count: frameCount * melCount)
           for t in 0..<frameCount {
               spect[t * melCount + activeMel] = 1.0
           }
           let captures = try model.predictDiagnostic(spect: spect, frameCount: frameCount)
           guard let bn1d = captures["stem.bn1d"] else {
               Issue.record("stem.bn1d not captured — predictDiagnostic shape change?")
               return
           }
           // Expected dims after stem.conv2d + stem.bn1d: roughly [B=1, C, F', T'].
           // With a mel-7 input pattern, the value should bias toward F'-rows
           // that overlap mel 7 of the original input. The exact post-conv
           // shape depends on the stem conv kernel; the assertion is "energy
           // is structured along F', not uniform" — a byte-reinterpret would
           // smear it uniformly. Inspect bn1d.shape; assert that the
           // standard deviation along F' is at least 5× the standard
           // deviation along T'. Same shape of test as BeatThisBugRegression
           // but starting from a synthetic input rather than love_rehab.
           // (Implementing agent: confirm the exact shape via
           // `print(bn1d.shape)` once and codify the assertion.)
           // Placeholder skeleton:
           let stdAlongF = computeStdAlongAxis(bn1d, axis: .freq)
           let stdAlongT = computeStdAlongAxis(bn1d, axis: .time)
           #expect(stdAlongF > stdAlongT * 5,
                   "Bug 2 regression: reshape collapsed per-mel structure (stdF=\(stdAlongF), stdT=\(stdAlongT))")
       }
   }
   ```

   ~30–60 LOC including the helper. No external fixture (synthetic
   input). The implementing agent should run a single one-shot
   probe to confirm the exact `stem.bn1d` shape and codify the
   assertion accordingly. The assertion's *direction* matters more
   than the precise threshold (5× is conservative; if real values
   show 50× difference, tighten).

4. NEW FILE — `BeatThisRoPEPairingTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisRoPEPairingTests.swift`

   Standalone test for DSP.2 S8 Bug 4 (RoPE pairing — adjacent vs
   half-and-half). Bug 4: pre-fix Swift used `(x[i], x[D/2+i])`
   half-and-half pairing; PyTorch's `rotary_embedding_torch.rotate_half`
   uses adjacent `(x[2i], x[2i+1])`.

   Synthetic Q tensor with values `[1, 2, 3, 4, 5, 6, 7, 8]`. Apply
   RoPE with a cos/sin table chosen so the rotation angle is exactly
   π/2 — adjacent rotation produces `[2, -1, 4, -3, 6, -5, 8, -7]`,
   half-and-half rotation produces `[5, -1, 7, -3, 2, 6, 4, 8]`.
   Assert the output matches the adjacent pattern.

   ```swift
   @Suite("BeatThisRoPEPairing")
   struct BeatThisRoPEPairingTests {
       @Test("RoPE applies adjacent-pair rotation, not half-and-half — DSP.2 S8 Bug 4")
       func test_ropeAdjacentPairing() {
           // 1-batch, 1-head, 1-frame, headDim=8 input.
           let input: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
           // cos/sin table for π/2 rotation: cos=0, sin=1 across all 4 pairs.
           let cos = [Float](repeating: 0, count: 4)
           let sin = [Float](repeating: 1, count: 4)
           let output = applyRoPEAdjacent(input: input, cos: cos, sin: sin)
           // Adjacent (x[2i], x[2i+1]) at angle π/2:
           //   pair 0: (1, 2) → (2, -1)
           //   pair 1: (3, 4) → (4, -3)
           //   pair 2: (5, 6) → (6, -5)
           //   pair 3: (7, 8) → (8, -7)
           let expected: [Float] = [2, -1, 4, -3, 6, -5, 8, -7]
           for (i, exp) in expected.enumerated() {
               #expect(abs(output[i] - exp) < 1e-5,
                       "RoPE Bug 4 regression at index \(i): got \(output[i]), expected \(exp)")
           }
       }
   }
   ```

   The `applyRoPEAdjacent` helper: either expose `BeatThisModel`'s
   internal RoPE function via `@testable import ML` (likely option),
   or inline a 30-LOC reference implementation in the test file
   that mirrors what the production model does. Pick whichever is
   less invasive — the implementing agent should choose based on
   what the existing source exposes. **The point of the test is to
   regression-lock the *production* RoPE function**, so prefer
   testable-import access over inlined reference (an inlined
   reference is its own copy, doesn't catch a future regression in
   the production path).

5. EDIT — `PresetVisualReviewTests.swift` Bundle fix (BUG-002)
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift`

   Find `makeBGRAPipeline` and locate the line:
   ```swift
   guard let shadersURL = Bundle.module.url(forResource: "Shaders", withExtension: nil) else { ... }
   ```

   Replace with:
   ```swift
   guard let shadersURL = Bundle(for: PresetLoader.self).url(forResource: "Shaders", withExtension: nil) else { ... }
   ```

   `Bundle(for: PresetLoader.self)` resolves the *engine* target's
   resource bundle (which has the `Shaders/` resource directory).
   `Bundle.module` resolves the *test target*'s bundle (which has
   no Shaders).

   Add Arachne to the harness fixture list if not already present
   (search for the `@Test(arguments:)` array; should be ~3–4 preset
   names already). Verify by running:
   ```
   RENDER_VISUAL=1 swift test --filter PresetVisualReview
   ```
   — confirm at least one PNG appears under
   `/tmp/phosphene_visual/<timestamp>/` for Arachne, AND that no
   `cgImageFailed` is logged.

──── COMMIT 2: integration / connector / ML golden (sub-items 6–9) ────

6. NEW FILE — `LiveDriftValidationTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Integration/LiveDriftValidationTests.swift`

   Closed-loop musical-sync test. Drives `LiveBeatDriftTracker` against
   real onsets from love_rehab.m4a, with the cached BeatGrid pre-installed.
   Assertions:
   - Lock state reaches `.locked` within 5 s of the first onset.
   - Steady-state `|driftMs| < 50` over the 10–30 s window.
   - For at least 80 % of the grid beats in 10–30 s, the corresponding
     `beatPhase01` zero-crossing is within ±30 ms of the grid beat
     timestamp.

   The third assertion is the load-bearing one: it's the closed-loop
   "the visual orb pulses on the music" property that no other test
   exercises. The first two are warm-up gates.

   Skeleton:

   ```swift
   import Audio
   import DSP
   @testable import Renderer  // Or wherever LiveBeatDriftTracker lives.
   import Shared
   import Testing

   @Suite("LiveDriftValidation")
   struct LiveDriftValidationTests {

       @Test("loveRehab: live drift tracker locks within 5s and beatPhase01 zero-crossings align with grid")
       func test_liveDriftSync_loveRehab() throws {
           // 1. Locate fixture
           let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
           let audioURL = testDir
               .deletingLastPathComponent()  // PhospheneEngineTests/
               .deletingLastPathComponent()  // Tests/
               .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
           guard FileManager.default.fileExists(atPath: audioURL.path) else {
               Issue.record("love_rehab.m4a missing — see BeatThisFixturePresenceGate")
               return
           }

           // 2. Decode audio to mono Float32 at 44.1 kHz
           let samples = try decodeMono44100(url: audioURL)

           // 3. Run BeatDetector on the audio to produce a real onset stream.
           //    Don't fabricate onsets — the whole point is closed-loop.
           let onsets = runBeatDetectorOnsets(samples: samples, sampleRate: 44100)

           // 4. Install the cached love_rehab BeatGrid (true 125 BPM).
           //    Either decode from love_rehab_reference.json, or construct
           //    a synthetic grid at 125 BPM matching the fixture's known beats.
           let grid = loadCachedBeatGrid("love_rehab_reference.json")
           let tracker = LiveBeatDriftTracker()
           tracker.setBeatGrid(grid)

           // 5. Drive the tracker frame-by-frame at the audio rate, feeding
           //    onsets at their timestamps. After each frame, sample
           //    tracker.lockState and tracker.driftMs and tracker.beatPhase01.
           var lockedAt: Double?
           var phaseSamples: [(time: Double, phase: Float)] = []
           var driftSamples: [(time: Double, ms: Float)] = []
           let dt = 1.0 / 60.0  // 60 Hz tracker tick
           var elapsed: Double = 0
           var onsetCursor = 0
           while elapsed < 30.0 {
               while onsetCursor < onsets.count, onsets[onsetCursor] <= elapsed {
                   tracker.observeOnset(at: onsets[onsetCursor])
                   onsetCursor += 1
               }
               tracker.update(playbackTime: elapsed)
               if tracker.currentLockState == .locked && lockedAt == nil {
                   lockedAt = elapsed
               }
               if elapsed >= 10.0 {
                   phaseSamples.append((elapsed, tracker.currentBeatPhase01))
                   driftSamples.append((elapsed, tracker.currentDriftMs))
               }
               elapsed += dt
           }

           // 6. Assertions
           #expect(lockedAt != nil, "tracker did not reach .locked in 30 s")
           if let t = lockedAt {
               #expect(t < 5.0, "locked at \(t)s — expected < 5s")
           }
           let maxDrift = driftSamples.map { abs($0.ms) }.max() ?? .infinity
           #expect(maxDrift < 50, "max drift \(maxDrift)ms exceeds 50ms ceiling")

           // 7. beatPhase01 zero-crossing alignment
           let zeroCrossings = findZeroCrossings(phaseSamples)
           let gridBeatsInWindow = grid.beats.filter { $0 >= 10.0 && $0 <= 30.0 }
           let alignedCount = zeroCrossings.filter { zc in
               gridBeatsInWindow.contains(where: { abs($0 - zc) <= 0.030 })
           }.count
           let expectedCount = gridBeatsInWindow.count
           let alignmentRatio = Double(alignedCount) / Double(max(1, expectedCount))
           #expect(alignmentRatio >= 0.80,
                   "Only \(alignedCount)/\(expectedCount) zero-crossings aligned within ±30ms (\(alignmentRatio))")
       }
   }
   ```

   This test will discover real bugs. If the alignment ratio is
   below 80 %, you've caught a sync regression. If it's between
   65–80 % consistently, the threshold needs calibration on the
   *current* (post-BUG-009 + post-BUG-007.5) tracker — adjust to
   the value that holds today as a regression baseline. Document
   the calibrated threshold in a comment.

   The decoder helper: `decodeMono44100(url:)` — reuse
   `BeatThisLayerMatchTests`'s `decodeMono22050` pattern but at
   44.1 kHz (or factor it out into a shared `AudioFixtureLoader`
   helper file if it doesn't exist already). The
   `runBeatDetectorOnsets` helper: instantiate `BeatDetector`,
   feed FFT chunks, collect `result.onsets[0]` timestamps. Look
   at how `TempoDumpRunner` does this offline — same pattern.

   The `findZeroCrossings` helper: scan `phaseSamples` for points
   where `phase` drops from > 0.9 to < 0.1 (modulo wrap). ~10 LOC.

   ~150 LOC test file total. The agent should NOT inline a fake
   `LiveBeatDriftTracker` reference implementation — drive the
   *production* one.

7. NEW FILE — `PresetLoaderCompileFailureTest.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetLoaderCompileFailureTest.swift`

   Asserts `PresetLoader.presets.count == expectedProductionCount` so
   silent shader compilation failure (Failed Approach #44) is loud at
   test time. Currently 14 production presets (count of .json sidecars
   in `PhospheneEngine/Sources/Presets/Shaders/`). The agent should
   verify by listing the sidecars and codifying the count.

   ```swift
   @Suite("PresetLoaderCompileFailure")
   struct PresetLoaderCompileFailureTest {

       /// Expected production preset count. Update this number whenever a
       /// preset is added or retired AND a corresponding decision is
       /// recorded in `docs/DECISIONS.md`. A drop in this number without
       /// a decision means a preset was silently dropped from the fixture
       /// — Failed Approach #44 territory (see CLAUDE.md).
       static let expectedProductionPresetCount = 14

       @Test("PresetLoader.presets.count matches expectedProductionPresetCount — catches Failed Approach #44 silent drops")
       func test_presetLoaderProductionCount() throws {
           guard let device = MTLCreateSystemDefaultDevice() else {
               try withKnownIssue { Issue.record("Metal device unavailable") }
               return
           }
           let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
           #expect(loader.presets.count == Self.expectedProductionPresetCount,
                   "Production preset count is \(loader.presets.count); expected \(Self.expectedProductionPresetCount). If you added or retired a preset, update expectedProductionPresetCount AND log a decision.")
       }
   }
   ```

   **Verification of the gate's effectiveness (do this BEFORE
   committing):** temporarily break one shader (e.g. introduce a
   Metal compiler error in `Stalker.metal` by adding `int half = 1;`
   per Failed Approach #44), run the test, confirm it fails. Revert
   the shader. Document the verification in the commit message.

8. NEW FILE — `SpotifyItemsSchemaTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/Session/SpotifyItemsSchemaTests.swift`

   ALSO NEW FIXTURE:
   `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/spotify_items_response.json`

   Decodes a fixture playlist `/items` response with the `"item"`
   key (not the deprecated `"track"`). Locks Failed Approach #45
   (Spotify deprecated `/tracks` → `/items` and silently changed
   the schema; pre-fix `item["track"]` returned nil for every item).

   The fixture should be a minimal real-shape `/items` response: 2–3
   items, with `"item"` keys at the top level of each entry, and
   `"item": {"name": "...", "artists": [...], "preview_url": "..."}`.
   Crib the actual structure from the Spotify Web API documentation
   or from a captured response in `~/Documents/phosphene_sessions/`.

   ```swift
   @Suite("SpotifyItemsSchema")
   struct SpotifyItemsSchemaTests {

       @Test("Spotify /items response decodes via the 'item' key (Failed Approach #45 regression-lock)")
       func test_itemsResponseDecodesViaItemKey() throws {
           let fixtureURL = URL(fileURLWithPath: String(#filePath))
               .deletingLastPathComponent()  // Session/
               .deletingLastPathComponent()  // PhospheneEngineTests/
               .appendingPathComponent("Fixtures/spotify_items_response.json")
           let data = try Data(contentsOf: fixtureURL)
           let connector = SpotifyWebAPIConnector(...)
           let tracks = try connector.parseTracksFromItemsResponse(data)
           #expect(tracks.count == 3, "expected 3 tracks; if 0 the parser regressed to the deprecated 'track' key")
           #expect(tracks.first?.spotifyPreviewURL != nil,
                   "preview_url must be captured inline (Failed Approach #47 regression-lock)")
       }
   }
   ```

   The implementing agent should locate the actual decoder method
   on `SpotifyWebAPIConnector` and call it from the test. If the
   method is private, expose it via `@testable import` or extract
   into an internal helper.

   The fixture JSON should look approximately like:
   ```json
   {
     "items": [
       {
         "added_at": "2026-01-01T00:00:00Z",
         "item": {
           "name": "Track A",
           "artists": [{ "name": "Artist 1" }],
           "preview_url": "https://example.com/preview-a.mp3",
           "duration_ms": 180000
         }
       },
       {
         "added_at": "2026-01-02T00:00:00Z",
         "item": {
           "name": "Track B",
           "artists": [{ "name": "Artist 2" }],
           "preview_url": null,
           "duration_ms": 200000
         }
       },
       {
         "added_at": "2026-01-03T00:00:00Z",
         "item": {
           "name": "Track C",
           "artists": [{ "name": "Artist 3" }],
           "preview_url": "https://example.com/preview-c.mp3",
           "duration_ms": 220000
         }
       }
     ],
     "total": 3,
     "next": null
   }
   ```

   Make sure the fixture is added to the test target's resources
   in `Package.swift` (`Tests/PhospheneEngineTests/Fixtures/` should
   already be a resources directory; add the new JSON to its inclusion
   list).

9. NEW FILE — `MoodClassifierGoldenTests.swift`
   Path: `PhospheneEngine/Tests/PhospheneEngineTests/ML/MoodClassifierGoldenTests.swift`

   ALSO NEW FIXTURE:
   `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/mood_classifier_golden.json`

   Ten input feature vectors (10 × 10 floats each — see
   `MoodClassifier`'s 10 input features) → expected
   `(valence, arousal)` outputs within 1e-4. Generated by running
   the *current* `MoodClassifier` once over deterministic inputs
   and capturing the outputs.

   The fixture is the safety net: if a future contributor
   re-extracts the hardcoded weights from a different DEAM
   training run (or accidentally byte-orders a weight buffer
   wrong), this test fails immediately rather than silently
   producing different mood classifications in production.

   ```swift
   @Suite("MoodClassifierGolden")
   struct MoodClassifierGoldenTests {

       struct GoldenEntry: Decodable {
           let inputs: [Float]      // 10 features
           let valence: Float
           let arousal: Float
       }

       @Test("MoodClassifier output matches golden fixtures within 1e-4")
       func test_moodClassifierGolden() throws {
           let fixtureURL = URL(fileURLWithPath: String(#filePath))
               .deletingLastPathComponent()  // ML/
               .deletingLastPathComponent()  // PhospheneEngineTests/
               .appendingPathComponent("Fixtures/mood_classifier_golden.json")
           let data = try Data(contentsOf: fixtureURL)
           let entries = try JSONDecoder().decode([GoldenEntry].self, from: data)
           #expect(entries.count == 10)
           let classifier = MoodClassifier()
           for (i, entry) in entries.enumerated() {
               let result = classifier.classify(features: entry.inputs)
               #expect(abs(result.valence - entry.valence) < 1e-4,
                       "Entry \(i): valence \(result.valence) vs golden \(entry.valence)")
               #expect(abs(result.arousal - entry.arousal) < 1e-4,
                       "Entry \(i): arousal \(result.arousal) vs golden \(entry.arousal)")
           }
       }
   }
   ```

   To generate the fixture: write a one-off Swift script (or a
   `@Test(.disabled)` test) that runs `MoodClassifier` over 10
   deterministic input vectors and dumps `(inputs, valence,
   arousal)` to JSON. Inputs should be varied: a mix of
   high-energy / low-energy / major / minor / sparse / dense
   patterns. Document the generation method in a comment at the
   top of the fixture file.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT add new BeatThis! S8 bug-pair tests beyond Bug 2 and Bug 4.
  Bugs 1 (norm-after-conv) and 3 (BN1d-aware padding) are already
  covered by `BeatThisBugRegressionTests`. The plan explicitly scopes
  this to Bug 2 + Bug 4.

- Do NOT add a `BeatThisModelOutputGolden` test (model output ≈
  Python reference). That's `BeatThisLayerMatchTests`'s job. Don't
  duplicate.

- Do NOT change `LiveBeatDriftTracker`'s public API to make
  `LiveDriftValidationTests` easier to write. If a needed accessor
  doesn't exist (e.g. `currentBeatPhase01`), add ONE accessor,
  document why in a doc comment, and don't expand further.

- Do NOT generate the MoodClassifier golden fixture by hand-typing
  expected values. Run the classifier programmatically and capture
  outputs. Hand-typed values are wrong; running the classifier
  produces a fixture that's correct by construction.

- Do NOT skip the `verify-by-breaking-Stalker.metal` step for
  `PresetLoaderCompileFailureTest`. The test's value is entirely in
  whether it actually fires; if you don't verify it fires, you
  haven't earned the test.

- Do NOT add a `Bundle(for: PresetLoader.self)` workaround to other
  test files unless they have the same broken `Bundle.module` lookup.
  The fix is targeted at `PresetVisualReviewTests` per BUG-002.

- Do NOT introduce a Spotify mock-server harness. The fixture-based
  approach is sufficient for the schema regression test. Live
  network testing is out of scope for QR.3.

- Do NOT couple the MoodClassifier test to specific weight loading
  (e.g. asserting the .bin file contents). Test the *output behavior*
  on golden inputs. The weights can change format; the function
  semantics shouldn't.

- Do NOT increase test runtime by more than ~3 seconds wall-clock
  for the slowest of the new tests. `LiveDriftValidationTests`
  decodes 30 s of audio and runs 1800 tracker ticks — should
  complete well under 3 s if the helpers are efficient. If it
  takes longer, profile before merging.

────────────────────────────────────────
DESIGN GUARDRAILS (CLAUDE.md)
────────────────────────────────────────

- **No silent skips.** Every guard that returns early on missing
  setup MUST be `Issue.record(...)`, not `print(...) + return`.
  This is the entire point of the increment.

- **No duplicate work.** The plan calls for **9** sub-items. Don't
  add a 10th "while we're here" test. Don't expand any single
  sub-item beyond what the plan describes. Future test holes can
  ride along with future increments.

- **Every test must run on a fresh checkout.** If a fixture is
  required, it must either (a) be committed to the repo, or
  (b) cause a hard failure with a path-and-instructions message
  if absent. The fixture-presence-gate test in sub-item 1
  enforces this for love_rehab.m4a + the Python activations JSON.

- **Test names are documentation.** Use full sentences in `@Test(...)`
  string args: e.g. `"loveRehab: live drift tracker locks within 5s
  and beatPhase01 zero-crossings align with grid"`. Future
  contributors should be able to read the test name and know what
  it's protecting.

- **Fixtures are committed to the repo.** Both new JSON fixtures
  (`spotify_items_response.json`, `mood_classifier_golden.json`)
  go into `Tests/PhospheneEngineTests/Fixtures/`. The audio fixture
  (`love_rehab.m4a`) is already there.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters. Each step must pass before proceeding.

1. **Build (engine)**: `swift build --package-path PhospheneEngine`
   — must succeed with zero warnings on touched files.

2. **Per-suite tests** (run each in isolation first to confirm
   correctness independent of parallel-execution noise):
   ```
   swift test --package-path PhospheneEngine --filter BeatThisFixturePresenceGate
   swift test --package-path PhospheneEngine --filter BeatThisLayerMatch
   swift test --package-path PhospheneEngine --filter BeatThisStemReshape
   swift test --package-path PhospheneEngine --filter BeatThisRoPEPairing
   swift test --package-path PhospheneEngine --filter LiveDriftValidation
   swift test --package-path PhospheneEngine --filter PresetLoaderCompileFailure
   swift test --package-path PhospheneEngine --filter SpotifyItemsSchema
   swift test --package-path PhospheneEngine --filter MoodClassifierGolden
   ```
   Each suite must pass.

3. **PresetVisualReviewTests under RENDER_VISUAL=1** (manual,
   required for sub-item 5):
   ```
   RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview
   ```
   Confirm:
   - At least one PNG produced under `/tmp/phosphene_visual/<timestamp>/`
     for Arachne (the staged preset).
   - No `cgImageFailed` errors in the test log.

4. **Verify the `PresetLoaderCompileFailureTest` actually fires**
   (mandatory verification step):
   - Temporarily edit `PhospheneEngine/Sources/Presets/Shaders/Stalker.metal`
     to add `int half = 1;` (Metal compiler error per Failed Approach #44).
   - Run `swift test --filter PresetLoaderCompileFailure`.
   - Confirm the test FAILS with a count mismatch.
   - Revert the change to Stalker.metal.
   - Re-run; confirm the test PASSES.
   - Document the verification in the commit message.

5. **Full engine suite**: `swift test --package-path PhospheneEngine`
   — full suite green except the documented pre-existing flakes
   (`SessionManager.afterPreparation_transitionsToReady` family,
   `MetadataPreFetcher.fetch_networkTimeout`, `MemoryReporter`
   residentBytes growth — all listed in CLAUDE.md). Any other
   failure is a regression.

6. **App build**: `xcodebuild -scheme PhospheneApp -destination
   'platform=macOS' build 2>&1 | tail -3` — must end
   `** BUILD SUCCEEDED **`.

7. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml
   --quiet PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisFixturePresenceGate.swift
   PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisLayerMatchTests.swift
   PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisStemReshapeTests.swift
   PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisRoPEPairingTests.swift
   PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift
   PhospheneEngine/Tests/PhospheneEngineTests/Integration/LiveDriftValidationTests.swift
   PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetLoaderCompileFailureTest.swift
   PhospheneEngine/Tests/PhospheneEngineTests/Session/SpotifyItemsSchemaTests.swift
   PhospheneEngine/Tests/PhospheneEngineTests/ML/MoodClassifierGoldenTests.swift`
   — zero violations on touched files.

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** — Phase QR §Increment QR.3:
   flip status to ✅ with the date. Update the "Done when"
   checklist (six boxes — all should now be checked). Add a one-
   line implementation summary noting the 8 new test files +
   1 in-place fix + 2 new fixtures.

2. **`docs/DECISIONS.md`** — append D-090 covering:
   - Why `Issue.record(...)` for missing fixtures, not `XCTSkip` /
     silent return: a CI run that silently skips is indistinguishable
     from a CI run that didn't have the regression to begin with;
     `Issue.record` makes the supply-chain failure visible.
   - Why fixtures are committed to the repo (the existing
     `love_rehab.m4a` is small enough; the new JSONs are tiny).
   - The `expectedProductionPresetCount = 14` policy: any change to
     this constant requires a corresponding decision in DECISIONS.md
     to prevent silent preset drops from being papered over.
   - The 80 % zero-crossing alignment threshold for
     `LiveDriftValidationTests` — calibrated against the current
     post-BUG-009 / post-BUG-007.5 tracker; future regressions
     should be diagnosed, not papered over by lowering the
     threshold.

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X] QR.3
   — Close silent-skip test holes` entry. List the 8 new test
   files + 1 in-place fix + 2 new fixtures. Note the verification-
   by-breaking-Stalker.metal step. Note the test count delta
   (engine suite goes from N → N+M).

4. **`docs/QUALITY/KNOWN_ISSUES.md`**:
   - Mark BUG-002 as resolved (`Status: Resolved 2026-MM-DD by QR.3
     commit hash`).
   - Mark BUG-003 as resolved (the missing closed-loop test is now
     `LiveDriftValidationTests`).

5. **`CLAUDE.md`**:
   - Update the test-suite section to reference the new test files.
   - Failed Approach #44 entry: add a note that
     `PresetLoaderCompileFailureTest` now catches this category at
     test time; the entry stays as a cautionary note for the future.
   - Failed Approach #45: same — note that
     `SpotifyItemsSchemaTests` catches the schema regression.

────────────────────────────────────────
COMMITS
────────────────────────────────────────

Two commits, in this order. Each must pass tests at the commit
boundary.

1. `[QR.3] tests: ML / harness gates (BeatThisFixturePresenceGate +
   layer-match-skip-to-fail + stem-reshape + rope-pairing +
   PresetVisualReview Bundle fix)` — sub-items 1–5.

2. `[QR.3] tests: integration / connector / ML golden (LiveDriftValidation
   + PresetLoaderCompileFailure + SpotifyItemsSchema +
   MoodClassifierGolden) + docs (D-090, ENGINEERING_PLAN, KNOWN_ISSUES,
   release note, CLAUDE.md)` — sub-items 6–9 + all docs.

   The docs update can ride in this commit because the doc updates
   reference the full surface of the increment; splitting docs
   across both commits would require redundant boilerplate.

Local commits to `main` only. Do NOT push to remote without explicit
"yes, push" approval.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **`LiveDriftValidationTests` falls below 80 % alignment.** This is
  the hardest sub-test to land. If the alignment ratio is < 80 % on
  a clean run, you've discovered an actual sync regression — STOP
  and surface it. Don't lower the threshold to make the test pass.
  Diagnose first.

- **`BeatThisStemReshapeTests` 5× std-dev assertion is wrong.**
  The first run of the test will tell you the actual std-dev ratio.
  If the production code is correct, the ratio should be substantial
  (10×+). If you see a ratio near 1×, either (a) the test is set up
  wrong (input pattern not propagating through the conv as expected)
  or (b) the production stem reshape regressed. Inspect manually
  before adjusting the threshold.

- **`SpotifyItemsSchemaTests` cannot be unit-tested without exposing
  internals.** If `SpotifyWebAPIConnector` doesn't have a public
  `parseTracksFromItemsResponse(data:)` method, you'll need to add
  one OR use `@testable import Session`. Prefer `@testable import` —
  don't expand the public API just for tests.

- **MoodClassifier golden fixture generation is non-trivial.**
  The classifier's `classify(features:)` API may not exist as such;
  the `MoodClassifier` initializer might be needed. The agent will
  need to read `MoodClassifier.swift` carefully, write a one-off
  Swift script (or `@Test(.disabled)` test) that exercises the
  classifier and dumps outputs, then bundle the dump as the fixture.
  Do this once and lock it.

- **`Bundle(for: PresetLoader.self)` fix doesn't resolve `Shaders`.**
  Verify by running `RENDER_VISUAL=1 swift test --filter PresetVisualReview`
  and confirming the PNG export succeeds. If it doesn't, the
  problem is more than a Bundle path — re-read the harness setup
  and surface the deeper issue.

- **`PresetLoaderCompileFailureTest` doesn't fire when Stalker.metal
  is broken.** The verification step is mandatory because if it
  doesn't fire, the test is decorative. If breaking Stalker.metal
  doesn't trigger a count mismatch, the assumption that compilation
  failure drops a preset is wrong — re-read `PresetLoader` to
  understand the actual failure mode.

- **STOP and report instead of forging ahead** if:
  - Any pre-QR.3 test breaks (the suite count goes down on a fresh
    run, indicating a regression introduced by the new tests).
  - The `LiveDriftValidationTests` alignment threshold cannot be
    set ≥ 80 % without skipping or weakening assertions.
  - Adding a fixture-presence gate would require committing > 5 MB
    of new fixture data (love_rehab.m4a is ~700 KB; both new JSONs
    should be < 50 KB combined).
  - The `MoodClassifier` API doesn't expose `classify(features:)` and
    extracting it would require non-trivial refactoring (> 30 LOC
    change). In that case, the test scope shrinks to "the classifier
    initializes and produces *some* output for fixture inputs"
    without the strict 1e-4 tolerance — and that's noted as a
    follow-up.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- Engineering plan: `docs/ENGINEERING_PLAN.md` §Phase QR §Increment QR.3
- Quality docs: `docs/QUALITY/DEFECT_TAXONOMY.md`,
  `docs/QUALITY/KNOWN_ISSUES.md` (BUG-002, BUG-003 close on completion),
  `docs/QUALITY/BUG_REPORT_TEMPLATE.md`
- Failed Approaches catalogue: `CLAUDE.md` Failed Approaches #44 (Metal
  built-in shadowing → silent compile failure), #45 (Spotify schema
  regression), #47 (preview_url discard)
- Existing test files (read before writing):
  `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisLayerMatchTests.swift`
  `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisBugRegressionTests.swift`
  `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisModelTests.swift`
  `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift`
  `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift`
  `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatGridUnitTests.swift`
- Production code (read before writing):
  `PhospheneEngine/Sources/ML/BeatThisModel.swift`
  + `BeatThisModel+Frontend.swift` + `BeatThisModel+Graph.swift`
  + `BeatThisModel+Ops.swift` (RoPE lives in one of these)
  `PhospheneEngine/Sources/ML/MoodClassifier.swift` (+ `+Weights.swift`)
  `PhospheneEngine/Sources/Presets/PresetLoader.swift`
  `PhospheneEngine/Sources/Renderer/LiveBeatDriftTracker.swift`
  (or DSP/ — find via `grep -rn "class LiveBeatDriftTracker"`)
  `PhospheneApp/Services/SpotifyWebAPIConnector.swift`
- Fixtures already in tree:
  `PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a`
  `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/beat_this_reference/love_rehab_reference.json`
  `docs/diagnostics/DSP.2-S8-python-activations.json`
- D-076 / D-077 / D-079 / D-080: surrounding context for the BeatThis!
  + sample-rate + stem-affinity work that QR.3 protects
- CLAUDE.md: Increment Completion Protocol, Defect Handling Protocol,
  the Test-suite-related entries in the Module Map
