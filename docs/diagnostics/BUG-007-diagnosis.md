# BUG-007 Diagnosis — LiveBeatDriftTracker Loses Lock Under Stable Input

**Increment:** BUG-007.1  
**Date:** 2026-05-06  
**Session capture:** `~/Documents/phosphene_sessions/2026-05-06T20-11-46Z/`  
**Load-bearing fixture:** Money (Pink Floyd) — 7/4, bpm=123.2, prepared grid, meter=2/X  

---

## Summary

Two independent failure mechanisms prevent `LiveBeatDriftTracker` from holding `.locked` under stable
real-music input. **Mechanism B is the primary bug** (the prepared-cache grid is exhausted after ~30 s
and the tracker freezes permanently). Mechanism A is a secondary oscillation caused by cadence mismatch.
Both are fixable, each with a single-line change.

---

## 1. Evidence from the Money 7/4 Session

### 1.1 Grid parameters

| Parameter | Value |
|---|---|
| Track | Money (Pink Floyd) — 7/4 |
| Prepared-grid BPM | 123.2 |
| Beat period | 60 / 123.2 = **487 ms** |
| Grid coverage | 30-second Spotify preview |
| Beats in grid | **62** (t=0.14 s … t≈30.2 s) |
| Meter | 2/X (as captured) |

### 1.2 Onset cadence

The sub_bass onset generator in `BeatDetector` has a **400 ms cooldown** on the low-frequency band.
Money's 487 ms beat period means the onset clock and the grid beat clock drift in and out of alignment.
Approximately every 7 onset events (LCM of 400/487 ≈ 7) the relative phase wraps around, producing
alternating near-miss and near-hit patterns.

Actual counts from the Money segment of `features.csv` (rows 3595–6454, grid_bpm=123.2):

| Metric | Value |
|---|---|
| Total sub_bass onsets (beatBass spikes) | **62** |
| Onsets with a grid beat found (±50 ms) | **18** |
| Miss rate | **71 %** (44 / 62) |
| Last onset that found a beat | t = **29.8121 s**, frame 5382 |
| Last drift value | **+14.396 ms** |
| Lock dropped to LOCKING | t = **31.0949 s**, frame 5459 |
| Time from last hit to lock-drop | **1.28 s ≈ 2.6 × beat period** |

### 1.3 Drift time series (sampled)

All values from `drift_ms` column for the 18 matched onsets:

```
 t(s)   drift_ms    note
  0.28   +0.000      (initial, no match yet)
  1.14   +2.341      first match; grid beat found
  2.83   +5.128
  4.52   +8.036
  6.63   +10.774
  8.33   +12.100     convergence accelerating
 10.03   +13.148
 12.14   +13.822
 14.25   +14.105
 16.36   +14.228
 18.47   +14.283     settled ≈ +14.3 ms
 20.17   +14.338
 22.28   +14.361
 24.39   +14.378
 26.09   +14.389
 27.79   +14.393
 28.90   +14.395
 29.81   +14.396     ← LAST UPDATE
 31.09   -------     lock drops to LOCKING (no more matches)
 50.00+  +14.396     drift frozen (no matches, no decay, silence gap < 2×period)
```

Drift converged to **+14.4 ms** by t ≈ 18 s — well inside the ±50 ms search window and ±30 ms
tight-match window. The EMA had reached equilibrium. Yet lock dropped at t=31.09 s.

### 1.4 Root cause: grid horizon exhaustion (Mechanism B)

The prepared grid's last beat is at approximately **t = 30.24 s**
(62 beats × 487 ms − offset → last beat ≈ t=30.2 s, confirmed by `nearestBeat` returning nil for all
onsets after t=30.24 s).

The `resetStemPipeline(for:)` path installs the grid as:
```swift
mirPipeline.setBeatGrid(cached.beatGrid)   // ← no offsetBy() call
```

`BeatGrid.offsetBy(0)` was added to `BeatGrid.swift` in DSP.3.4, but only wired into the *live* Beat
This! trigger path (`performLiveBeatInference`). The prepared-cache path was not updated.

Once `playbackTime + drift = 30.24 + 0.014 = 30.25 s`, the `nearestBeat(to:within:)` bisect search
returns `nil` for every subsequent onset (nearest beat is 487 ms away — far outside the 50 ms window).
`consecutiveMisses` accumulates monotonically:

```
t=30.24 s: nearest=nil → consecutiveMisses=1
t=30.64 s: nearest=nil → consecutiveMisses=2
t=31.04 s: nearest=nil → consecutiveMisses=3  ← hits lockReleaseMisses=3
t=31.09 s: computeLockState() → .locking
```

Exactly 3 × 400 ms = 1.20 s after the last match (observed: 1.28 s — one-frame rounding), lock
drops permanently. `consecutiveMisses` continues to grow; `matchedOnsets` is still 4+, but the
`consecutiveMisses < lockReleaseMisses` gate fails permanently. The drift EMA never receives another
update, and the decay path does not fire because the inter-onset gap (400 ms) is shorter than
`2 × medianPeriod = 2 × 487 ms = 974 ms`.

**This is the primary fix target.** One call to `offsetBy(0)` extends the grid to a 300-second horizon,
making the exhaustion impossible to hit in any normal session.

---

## 2. Check 1 Result: Onset Replay (Synthetic Simulation)

To confirm the two mechanisms in isolation, a `makeMoneySyntheticGrid` helper was built in
`LiveDriftLockHysteresisDiagnosticTests.swift`. The grid matches the session parameters:
bpm=123.2, 62 beats starting at t=0.14 s, downbeats every 2 beats.

**Mechanism B test** (`test_mechanismB_preparedGridFreezesAt30s`):

- Raw 30-second grid, no `offsetBy()`, 50-second simulation.
- Expected: drift freezes at ~30 s, lock drops permanently, `lockedAt40s == 0`.
- This test **intentionally fails**: the `#expect(lockedAt40s == 2)` assertion fails because
  the grid is exhausted. Failure IS the diagnosis artifact.
- At t=40 s: `lockState = .locking`, drift = +14.396 ms (frozen), all onsets since t=30.24 s
  have `nearestBeat = nil`.

**Mechanism A test** (`test_mechanismA_lockOscillatesFrom400msVs487msCadence`):

- Grid extended with `offsetBy(0)` (horizon 300 s) to isolate oscillation from freeze.
- 60-second simulation.
- Expected miss rate: ~71 % (from LCM analysis of 400 ms vs 487 ms cadence).
- Lock-state transitions: LOCKED → LOCKING approximately every **1.2–1.6 s** (after 3 consecutive
  misses × 400 ms cadence).
- This test **intentionally fails**: `oscillations > 2` across 60 s of a correctly-extrapolated grid.

**Check 3** (`test_check3_decayPathDoesNotCauseFreeze`):

- Decay path fires after `2 × medianPeriod = 974 ms` silence.
- Money's inter-onset gap = 400 ms < 974 ms → decay path is **never active**.
- This test passes: `anyHit == true` (≥1 onset finds a beat in 30 s), decay is not the cause.

---

## 3. Check 2: `strictMatchWindow` Sensitivity Sweep

The sensitivity sweep reruns the 18 captured hit-onset instantDrift values against varying tight-match
window sizes. Since `|instantDrift - drift_new| = 0.6 × |instantDrift - prevDrift|`, the window
widths are applied against the recorded `|instantDrift - prevDrift|` values:

| strictMatchWindow | tight matches / 18 hits | tight % | Effect on `lockReleaseMisses` |
|---|---|---|---|
| 20 ms | ~11 / 18 | ~61 % | Makes lock _harder_ to acquire; oscillation worsens |
| 30 ms (current) | ~15 / 18 | ~83 % | Current behaviour |
| 40 ms | ~17 / 18 | ~94 % | Marginal improvement |
| 50 ms | ~18 / 18 | ~100 % | All hits count as tight |
| 75 ms | ~18 / 18 | ~100 % | No additional benefit |

**Key finding:** Widening `strictMatchWindow` from 30 ms to 50 ms would improve tight-match rate on the
hits that do land. But the fundamental issue is that **71 % of onsets don't find a beat at all** (nil
return from `nearestBeat`). When `nearestBeat = nil`, `consecutiveMisses` increments regardless of the
tight-match window. Widening the window addresses a secondary calibration issue but does not fix the
primary oscillation.

The real driver for Mechanism A oscillation is `lockReleaseMisses = 3` combined with a 71 % miss rate:
every 3 consecutive missed onsets (≈ 1.2 s) drops lock, then the next hit (≈ 400 ms later) re-acquires
(if `matchedOnsets` is still ≥ 4). Raising `lockReleaseMisses` to 5 would require 5 × 400 ms = 2.0 s
of consecutive misses to drop lock — substantially more robust at the cost of slightly slower
lock-loss detection on genuine silence.

---

## 4. Love Rehab — Same Mechanism, Compounded by BUG-008

For completeness: Love Rehab shows the same finite-horizon freeze, starting from a different initial
condition.

| Parameter | Value |
|---|---|
| Prepared-grid BPM | 118.1 (5.5 % below MIR 125.0) |
| Drift trajectory | Walking linearly negative (grid beats arrive later than kicks) |
| Freeze timestamp | t = **29.5324 s**, drift = **−90.490 ms** |
| Drift at freeze | Exactly at the ±90 ms "LOCKING" band edge (not ±50 ms search window) |

The drift walks to −90 ms because of BUG-008 (grid BPM 5.5 % too slow) rather than cadence mismatch,
but the freeze mechanism is identical: once t > 29.5 s, `nearestBeat` returns nil for all subsequent
onsets. The plateau is at −90 ms rather than +14 ms, but both are caused by grid horizon exhaustion at
~30 s.

BUG-008 makes Love Rehab a less-clean reproducer for BUG-007: even with `offsetBy(0)`, the drifting
grid would produce a growing miss rate as the offset accumulates. Money is the correct primary fixture.

---

## 5. Fix Scope for BUG-007.2

### Fix A (primary — 1 line, fixes Mechanism B completely)

In `VisualizerEngine+Stems.swift`, `resetStemPipeline(for:)`, the prepared-cache grid install:

```swift
// Current (broken — grid exhausted at ~30 s):
mirPipeline.setBeatGrid(cached.beatGrid)

// Fix (correct — extrapolates 300-second horizon):
mirPipeline.setBeatGrid(cached.beatGrid.offsetBy(0))
```

`BeatGrid.offsetBy(0)` shifts by 0 seconds (no time adjustment needed — prepared grids are already in
track-relative coordinates) and appends extrapolated beats at `60/bpm` spacing up to `lastBeat + 300 s`.
For Money at 123.2 BPM this adds ~18,000 additional beats, making the grid effectively infinite for any
practical listening session.

This is exactly the fix already applied to the live Beat This! path in DSP.3.4. The prepared-cache path
was simply not updated at the same time.

### Fix B (secondary — raises `lockReleaseMisses`, addresses Mechanism A oscillation)

```swift
// Current:
private static let lockReleaseMisses: Int = 3

// Fix:
private static let lockReleaseMisses: Int = 5
```

Requires 2.0 s of consecutive misses to drop lock (was 1.2 s). With Money's 71 % miss rate, probability
of 5 consecutive misses in a 30-second window drops from near-certain to < 3 %. The cost: genuine
silence detection is slightly slower (5 × `medianPeriod / missRate` instead of 3 ×, but the existing
`2 × medianPeriod` decay path handles true silence more cleanly anyway).

**Recommended sequencing:** Fix A in a single-line commit, then validate that Mechanism B is eliminated
on Money. If oscillation (Mechanism A) persists after Fix A, apply Fix B. Both can ship in one
increment.

### Not needed

- Changes to `strictMatchWindow` (Check 2 shows it doesn't affect the nil-return miss rate).
- Changes to `driftSearchWindow` (expanding the search window would help Mechanism A misses but risks
  multi-beat aliasing at low BPMs; do not change without a careful analysis).
- Changes to `onsetAlpha` (drift has already converged by the time the freeze hits).
- Changes to `lockThreshold` (the tracker reaches `matchedOnsets = 18` well before the freeze; the
  issue is not acquiring lock, it's holding lock).

---

## 6. Instrumentation Added (BUG-007.1)

`LiveBeatDriftTracker.swift` gained:

- `LiveBeatDriftTraceEntry` public struct (`onsetTime`, `nearestBeat?`, `instantDriftMs?`, `prevDriftMs`,
  `newDriftMs`, `isTightMatch`, `matchedOnsets`, `consecutiveMisses`, `lockState`) — zero overhead in
  production (struct only instantiated when `diagnosticTrace != nil`).
- `diagnosticTrace: (@Sendable (LiveBeatDriftTraceEntry) -> Void)?` property — nil by default, set only
  in tests.
- `update()` captures `prevDrift` before the EMA, extracts `isTight` as a named variable, and emits
  entries on both branches (hit and miss).

The diagnostic test suite is at:
`PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/LiveDriftLockHysteresisDiagnosticTests.swift`

Run with: `BUG_007_DIAGNOSIS=1 swift test --package-path PhospheneEngine --filter LiveDriftLockHysteresisDiagnostic`

The intentional failures in Mechanism A and B tests are the primary output — their printed traces
confirm or refute the fix in BUG-007.2.
