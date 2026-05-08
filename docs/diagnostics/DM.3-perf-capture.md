# DM.3 Drift Motes — full-pipeline perf capture procedure

## Why a runtime procedure

`SoakTestHarnessTests.shortRunDriftMotes` measures the `motes_update`
compute kernel only — that's the work that grew between DM.1 → DM.2 → DM.3
and the right shape of regression gate for kernel-cost drift.

The Drift Motes architecture contract specifies a **full-frame** budget of
1.6 ms (Tier 2) / 2.1 ms (Tier 1) covering: sky fragment + curl-noise
compute + sprite render + feedback decay + composite. The sprite render
needs a `CAMetalDrawable` from a real `MTKView`, so the `swift test`
harness cannot exercise it in isolation. This file documents the runtime
options for closing that gap.

## What's actually available today

Drift Motes does not currently emit per-frame timing to a CSV. The
`SessionRecorder.features.csv` columns cover audio features (FFT bands,
beat sync, mood, stem state) but **not** frame time. Three real options:

### Option A — Dashboard PERF card (vibe check)

Fastest. Build the app, pin Drift Motes, watch the dashboard. The PERF
card's `FRAME` row shows `recentMaxFrameMs / target ms` from the 30-slot
rolling window in `FrameBudgetManager`. The `QUALITY` row only appears
when the budget governor downshifts.

```bash
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
           -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/PhospheneApp-*/Build/Products/Release/PhospheneApp.app
# In the app:
# 1. Start an ad-hoc session.
# 2. Press ⌘[ / ⌘] to cycle presets until the dashboard BEAT card shows
#    "Drift Motes". Hold L (diagnostic-preset-locked) so the orchestrator
#    does not migrate away.
# 3. Play representative audio (Love Rehab — Chaim, 125 BPM electronic
#    stresses emission-rate scaling; So What — Miles Davis, 136 BPM jazz
#    with sparse drum hits stresses dispersion shock).
# 4. Watch the PERF card for ~60 s.
```

**Pass criteria (eyeball):**
- `FRAME` row stays under `14 / 14ms` (Tier 2 budget; downshift at 14 ms).
- `QUALITY` row stays hidden (governor stays at `full`).
- No visible jank during sustained playback.

This is a vibe check — it tells you "the budget is healthy" or "the budget
is breached" but does not produce p50/p95/p99 percentiles. Sufficient for
catching a regression that breaks budget; insufficient for tuning.

### Option B — Temporary CSV instrumentation (rigorous)

For percentile capture, add ~20 LOC of throwaway instrumentation in
`RenderPipeline.draw(in:)`:

```swift
// TEMPORARY — DM.3 perf capture. Delete after measurement.
private static let _dm3PerfFile: FileHandle? = {
    let url = URL(fileURLWithPath: "/tmp/dm3_perf.csv")
    FileManager.default.createFile(atPath: url.path,
        contents: "frame,gpu_ms\n".data(using: .utf8))
    return try? FileHandle(forWritingTo: url)
}()
```

Then in the per-frame block, after `commandBuffer.commit()` and
`commandBuffer.addCompletedHandler { … }`:

```swift
let gpuMs = (cmdBuf.gpuEndTime - cmdBuf.gpuStartTime) * 1000.0
Self._dm3PerfFile?.write("\(frameIndex),\(gpuMs)\n".data(using: .utf8)!)
```

After 60 s of playback, parse:

```bash
awk -F',' 'NR>1 {print $2}' /tmp/dm3_perf.csv | sort -n | \
    awk 'BEGIN {n=0} {a[n++]=$1} END {
      print "p50="a[int(n*0.50)]"ms p95="a[int(n*0.95)]"ms p99="a[int(n*0.99)]"ms"
    }'
```

**Pass criteria:**
- p50 ≤ 8 ms (50% headroom over 16.6 ms refresh)
- p95 ≤ 14 ms (within FrameBudgetManager Tier 2 downshift threshold)
- p99 ≤ 25 ms (single-frame outliers tolerable; sustained breaches
  trigger governor downshift)
- drops (gpu_ms > 32 ms) ≤ 5 across 60 s ≈ ≤ 8% — exceeding this means
  the `kEmissionRateGain` / `kDispersionShockGain` constants in
  `ParticlesDriftMotes.metal` need lowering.

Revert the instrumentation once measurements are captured.

### Option C — `SoakRunner` CLI under synthetic audio

`Scripts/run_soak_test.sh` runs the app under `caffeinate -i` with the
`SoakTestHarness` driving a procedural audio fixture. Produces full
`FrameTimingReporter` percentiles. Limitation: doesn't pin Drift Motes
specifically — it measures the app's overall full-pipeline cost across
whatever presets the orchestrator selects. Best for "is the app healthy
under load," not "is Drift Motes within budget."

## Notes on tuning regress

- If Tier 2 full-pipeline p95 exceeds 14 ms, the first lever is reducing
  `kEmissionRateGain` from 1.5 → 1.0 (less lifetime compression at peak
  melody → fewer respawns per second → less aggregate respawn work).
- The dispersion-shock branch (the `if (beatGate > 0.0)` clause in
  `motes_update`) is an in-line conditional; the cost cliff between
  "shock firing" and "shock idle" is small (smoothstep + length + 6 muls
  + 1 sqrt) but predictable.
- If the kernel itself regresses, the `shortRunDriftMotes` SOAK test will
  catch it before this full-pipeline measurement matters.

## When Drift Motes ships a permanent perf-capture path

Future work (not in DM.3 scope): a build-flag-gated `frame_ms` column on
`features.csv`, written from a `RenderPipeline` `onFrameTimingObserved`
fan-out closure. That would eliminate Options A/B/C entirely — every
session would carry full-pipeline percentiles. Tracked as a candidate
follow-up; not blocking M7 sign-off.
