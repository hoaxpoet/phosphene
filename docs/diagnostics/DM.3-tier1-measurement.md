# DM.3 Drift Motes — Tier 1 (M1/M2) hardware measurement procedure

## Why this is a separate procedure

The Drift Motes architecture contract gates Tier 1 at 2.1 ms full-frame
(M1/M2) and Tier 2 at 1.6 ms (M3+). The development machines used during
DM.0 → DM.3 are M3+ (Tier 2). Tier 1 numbers must be reproduced on
genuine M1/M2 hardware — Apple Silicon's GPU performance characteristics
do not extrapolate cleanly between tiers (memory bandwidth, ALU width,
and threadgroup-occupancy ratios differ).

This document is the standing procedure for running the Tier 1 gate.
It is executed on Tier 1 hardware as part of every DM.x perf-impacting
increment's closeout, when that hardware is available.

## Procedure

1. **Hardware**: M1 (mini, MacBook Air, MacBook Pro 13") OR M2 (mini,
   MacBook Air, MacBook Pro 13"). M1 Pro / M1 Max / M1 Ultra and M2 Pro /
   M2 Max / M2 Ultra are Tier 1 by `DeviceTier` mapping but have
   sufficient headroom that they do not stress the budget — M1/M2 base
   silicon is the binding constraint.

2. **Set Tier 1 particle count**: `DriftMotesGeometry.tier1ParticleCount
   = 400`. The kernel benchmark in `SoakTestHarnessTests` uses
   `tier2ParticleCount = 800` by default. Override locally:

   ```swift
   let geometry = try DriftMotesGeometry(
       device: ctx.device,
       library: lib.library,
       particleCount: DriftMotesGeometry.tier1ParticleCount,  // 400
       pixelFormat: nil
   )
   ```

   In production the particle count is selected at preset-init time
   based on `DeviceTier`. Running the kernel benchmark with the wrong
   count gives meaningless numbers.

3. **Run the kernel benchmark** (Tier 1 hardware):

   ```bash
   SOAK_TESTS=1 swift test --package-path PhospheneEngine \
       --filter shortRunDriftMotes
   ```

   Target: kernel p95 ≤ 1.5 ms (loose gate; the strict full-pipeline
   gate is 2.1 ms covering compute + sky fragment + sprite + composite).

4. **Run the full-pipeline capture** following the procedure in
   `DM.3-perf-capture.md`. Target percentiles:
   - p50 ≤ 11 ms
   - p95 ≤ 19 ms
   - p99 ≤ 30 ms
   - drops (frame_ms > 32 ms) ≤ 8 across 60 s

5. **If a gate is exceeded**, see the tuning-regress section in
   `DM.3-perf-capture.md`. Reducing `kEmissionRateGain` is the first
   lever.

## When to run

- Every DM.x increment that touches `motes_update` or
  `DriftMotesGeometry`.
- Every DM.x increment that adds a per-frame audio reactivity (DM.3 was
  the first; DM.4's `f.bass_att_rel` × wind multiplier and shaft pulse
  on `f.beat_phase01` will be the next).
- Whenever `kEmissionRateGain`, `kDispersionShockGain`, or future tuning
  constants change.

## When this procedure is deferred

If Tier 1 hardware is not immediately available, the increment closeout
records "Tier 1 numbers deferred — Matt to run against M1/M2" in the
landing block. Tier 2 numbers always land in the same closeout. Do not
ship a closeout that lacks BOTH measurements.
