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
app procedure that closes that gap.

## Tier 2 full-pipeline capture (M3+)

1. **Build the app in Release.**

   ```bash
   xcodebuild -scheme PhospheneApp -destination 'platform=macOS' \
              -configuration Release build
   ```

2. **Pin Drift Motes.** Launch the app, start an ad-hoc session, press
   `⌘[` / `⌘]` to cycle presets until the dashboard `BEAT` card shows
   "Drift Motes". Hold `L` (diagnostic-preset-locked) so the orchestrator
   doesn't migrate away.

3. **Drive representative audio.** Play a track with mid energy and
   distinct drum hits — Love Rehab (Chaim, 125 BPM electronic) and So What
   (Miles Davis, 136 BPM jazz with sparse drum hits) are the two
   reference fixtures. The first stresses emission-rate scaling
   (continuous mid-frequency content); the second stresses dispersion
   shock (sparse, clear kicks).

4. **Capture per-frame timings.** The session recorder writes
   `~/Documents/phosphene_sessions/<timestamp>/features.csv`. The
   `frame_ms` column is the full-pipeline frame time. Run for 60 seconds
   minimum so percentiles are stable.

5. **Compute percentiles.** A one-liner:

   ```bash
   awk -F',' 'NR>1 {print $NF}' \
       ~/Documents/phosphene_sessions/<timestamp>/features.csv \
       | sort -n | awk 'BEGIN {n=0} {a[n++]=$1} END {
         print "p50="a[int(n*0.50)]"ms p95="a[int(n*0.95)]"ms p99="a[int(n*0.99)]"ms"
       }'
   ```

6. **Pass criteria.**
   - p50 ≤ 8 ms (50% headroom over 16.6 ms refresh)
   - p95 ≤ 14 ms (within FrameBudgetManager Tier 2 downshift threshold)
   - p99 ≤ 25 ms (single-frame outliers tolerable; sustained breaches
     trigger governor downshift)
   - drops (frame_ms > 32 ms) ≤ 5 across 60 s = ≤ 8% — exceeding this
     means the `kEmissionRateGain` and `kDispersionShockGain` constants
     in `ParticlesDriftMotes.metal` need lowering.

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
