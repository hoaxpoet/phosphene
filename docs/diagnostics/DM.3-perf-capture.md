# DM.3 Drift Motes — full-pipeline perf capture procedure

## What this measures

The Drift Motes architecture contract specifies a **full-frame** budget of
1.6 ms (Tier 2) / 2.1 ms (Tier 1) covering: sky fragment + curl-noise
compute + sprite render + feedback decay + composite. The sprite render
needs a `CAMetalDrawable` from a real `MTKView`, so it cannot be exercised
inside `swift test`. This procedure runs the production app under
representative audio and parses the resulting `features.csv` for
percentile statistics.

`SoakTestHarnessTests.shortRunDriftMotes` is the kernel-only regression
gate; this procedure is the full-pipeline budget gate and complements it.

## How frame timing reaches features.csv

`RenderPipeline.draw(in:)` registers a command-buffer completion handler
that captures `cpuMs` (CPU wall-time of the encode) and
`gpuMs = cb.gpuEndTime - cb.gpuStartTime` (GPU execution time of the
buffer), then fires `onFrameTimingObserved`. `VisualizerEngine` wires
that callback to `SessionRecorder.recordFrameTiming(cpuMs:gpuMs:)`,
which buffers the values and consumes them into the next features.csv
row's `frame_cpu_ms` / `frame_gpu_ms` columns (DM.3a).

**Lag.** Frame N's row carries timing from some earlier frame in
`[N-3, N-1]` because RenderPipeline triple-buffers and the GPU
completion handler runs after `recordFrame` for the same frame's
features. Adequate for percentile capture over 60 s; slight
misalignment for single-frame cross-correlation.

## Tier 2 full-pipeline capture (M3+)

1. **Build the app.** Debug or Release; both wire the timing observer.

   ```bash
   xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
   ```

   For perf-realistic numbers prefer Release:

   ```bash
   xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
              -configuration Release build
   ```

2. **Pin Drift Motes.** Launch the app, start an ad-hoc session, press
   `⌘[` / `⌘]` to cycle presets until the dashboard `BEAT` card shows
   "Drift Motes". Hold `L` (diagnostic-preset-locked) so the
   orchestrator doesn't migrate away.

3. **Drive representative audio.** Play a track with mid energy and
   distinct drum hits — Love Rehab (Chaim, 125 BPM electronic) and So
   What (Miles Davis, 136 BPM jazz with sparse drum hits) are the two
   reference fixtures. The first stresses emission-rate scaling
   (continuous mid-frequency content); the second stresses dispersion
   shock (sparse, clear kicks).

4. **Capture for ≥ 60 s.** The session recorder writes
   `~/Documents/phosphene_sessions/<timestamp>/features.csv`. End the
   session (or quit the app) so `finish()` flushes outstanding rows.

5. **Compute percentiles.** Look up the `frame_gpu_ms` column by name
   (it's the last column today; future increments may append more):

   ```bash
   SESSION=~/Documents/phosphene_sessions/<timestamp>
   awk -F',' 'NR==1 {
     for (i=1; i<=NF; i++) if ($i == "frame_gpu_ms") col=i
     next
   } NR>1 && $col != "" { print $col }' "$SESSION/features.csv" \
     | sort -n \
     | awk 'BEGIN {n=0} {a[n++]=$1} END {
       drops = 0; for (i=0; i<n; i++) if (a[i] > 32) drops++
       print "n="n" p50="a[int(n*0.50)]"ms p95="a[int(n*0.95)]"ms p99="a[int(n*0.99)]"ms drops="drops
     }'
   ```

   Substitute `frame_cpu_ms` for the CPU-side comparison if you also
   want to see encode cost.

6. **Pass criteria (Tier 2).**
   - p50 ≤ 8 ms (50 % headroom over 16.6 ms refresh)
   - p95 ≤ 14 ms (within `FrameBudgetManager` Tier 2 downshift threshold)
   - p99 ≤ 25 ms (single-frame outliers tolerable; sustained breaches
     trigger governor downshift)
   - drops (gpu_ms > 32 ms) ≤ 5 across 60 s ≈ ≤ 8 % — exceeding this
     means the `kEmissionRateGain` and `kDispersionShockGain` constants
     in `ParticlesDriftMotes.metal` need lowering.

## Notes on the timing data

- Cold-start frames (before the first GPU completion handler returns)
  produce empty `frame_cpu_ms,frame_gpu_ms` cells. The `awk` filter
  above (`$col != ""`) skips them. Typically only the first 1–3 rows.
- `frame_gpu_ms` may also be empty when `cb.gpuEndTime <= cb.gpuStartTime`
  (Metal API contract: returns 0/0 if the buffer was scheduled but
  timing was unavailable). Rare; same `awk` filter handles it.
- `frame_cpu_ms` is encode time only — it does NOT include CPU work in
  the per-frame analysis path (FFT, MIR, mood) that runs in parallel
  on a different queue. To measure that, use Instruments.

## Notes on tuning regress

- If Tier 2 full-pipeline p95 exceeds 14 ms, the first lever is reducing
  `kEmissionRateGain` from 1.5 → 1.0 (less lifetime compression at peak
  melody → fewer respawns per second → less aggregate respawn work).
- The dispersion-shock branch (the `if (beatGate > 0.0)` clause in
  `motes_update`) is an in-line conditional; the cost cliff between
  "shock firing" and "shock idle" is small (smoothstep + length + 6 muls
  + 1 sqrt) but predictable.
- If the kernel itself regresses, the `shortRunDriftMotes` SOAK test
  catches it before this full-pipeline measurement matters.

## Tier 1 (M1/M2)

See `DM.3-tier1-measurement.md`. The procedure is identical from
step 2 onward; only the pass thresholds change (p95 ≤ 19 ms instead
of 14, and the kernel regression gate is run with
`particleCount = 400`).
