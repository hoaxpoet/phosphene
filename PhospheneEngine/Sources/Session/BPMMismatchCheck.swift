// BPMMismatchCheck — Detect disagreement between the offline BeatGrid (Beat This!)
// BPM and the MIR-derived BPM (DSP.1 trimmed-mean IOI on sub_bass).
//
// Pure function. No I/O, no logging, no Sendable concerns. Caller is responsible
// for adding track context (title) and emitting whatever log line it wants.
//
// Background (BUG-008): the two estimators occasionally disagree by enough to
// matter — Love Rehab's offline BeatGrid returns 118 BPM while the MIR
// estimator returns ~125. Neither is mechanically "right" (BUG-008.1 diagnosis
// in `docs/diagnostics/BUG-008-diagnosis.md` documents the per-estimator
// reasoning); the fix is to surface the disagreement at preparation time so
// future per-track judgment is informed by data rather than tags.
//
// This file does NOT decide which estimator to consume at runtime. The
// LiveBeatDriftTracker continues to compare against the offline BeatGrid
// (CachedTrackData.beatGrid). That is intentional — see BUG-008.2 prompt.

import Foundation

// MARK: - ThreeWayBPMReading

/// All three BPM estimator values for a single track plus their pairwise deltas.
///
/// Produced by `detectThreeWayBPMDisagreement` when all three estimators are non-zero
/// and at least one pair disagrees by more than `thresholdPct`.
///
/// The three estimators are:
///   - **mirBPM**: DSP.1 trimmed-mean IOI on sub_bass (kick-rate IOI estimator).
///   - **gridBPM**: Beat This! transformer on the full-mix preview (offline grid).
///   - **drumsBPM**: Beat This! transformer on the drums stem only (DSP.4 diagnostic).
public struct ThreeWayBPMReading: Equatable, Sendable {
    /// MIR-derived BPM (DSP.1 trimmed-mean IOI on sub_bass).
    public let mirBPM: Double
    /// Offline full-mix BeatGrid BPM (Beat This! → BeatGridResolver).
    public let gridBPM: Double
    /// Offline drums-stem BeatGrid BPM (Beat This! on separated drums, DSP.4).
    public let drumsBPM: Double
    /// Relative delta between MIR and full-mix grid: `|mir - grid| / max(mir, grid)`.
    public let mirGridDeltaPct: Double
    /// Relative delta between MIR and drums-stem grid: `|mir - drums| / max(mir, drums)`.
    public let mirDrumsDeltaPct: Double
    /// Relative delta between full-mix grid and drums-stem grid: `|grid - drums| / max(grid, drums)`.
    public let gridDrumsDeltaPct: Double

    /// Largest relative delta across all three pairs.
    public var maxDeltaPct: Double {
        max(mirGridDeltaPct, mirDrumsDeltaPct, gridDrumsDeltaPct)
    }

    public init(
        mirBPM: Double,
        gridBPM: Double,
        drumsBPM: Double,
        mirGridDeltaPct: Double,
        mirDrumsDeltaPct: Double,
        gridDrumsDeltaPct: Double
    ) {
        self.mirBPM = mirBPM
        self.gridBPM = gridBPM
        self.drumsBPM = drumsBPM
        self.mirGridDeltaPct = mirGridDeltaPct
        self.mirDrumsDeltaPct = mirDrumsDeltaPct
        self.gridDrumsDeltaPct = gridDrumsDeltaPct
    }
}

// MARK: - Three-Way Detector

/// Detect disagreement among three BPM estimators: MIR (sub_bass IOI), full-mix
/// Beat This!, and drums-stem Beat This! (DSP.4).
///
/// Returns `nil` when:
///   - any of the three inputs is zero or non-finite (missing estimator — fall through
///     to the 2-way `detectBPMMismatch` path),
///   - all three pairwise deltas are at or below `thresholdPct`.
///
/// Returns a populated `ThreeWayBPMReading` when all three inputs are valid and at
/// least one pair disagrees strictly beyond `thresholdPct`.
///
/// **Precedence rule (callers):** prefer the 3-way line when this function returns
/// non-nil; fall back to `detectBPMMismatch` (2-way) when `drumsBPM == 0` or when
/// this function returns `nil` (all three agree). This preserves backward grep-ability
/// for the existing `WARN: BPM mismatch` line in tooling cued to BUG-008.2.
///
/// - Parameters:
///   - mirBPM: BPM from MIR analysis (kick-rate IOI estimator).
///   - gridBPM: BPM from offline full-mix BeatGrid (Beat This! transformer).
///   - drumsBPM: BPM from offline drums-stem BeatGrid (Beat This!, DSP.4 diagnostic).
///   - thresholdPct: Minimum relative disagreement for any pair to trigger a reading.
///     Must be in `(0, 1)`; values outside are treated as 0.03.
public func detectThreeWayBPMDisagreement(
    mirBPM: Double,
    gridBPM: Double,
    drumsBPM: Double,
    thresholdPct: Double = 0.03
) -> ThreeWayBPMReading? {
    guard mirBPM.isFinite, gridBPM.isFinite, drumsBPM.isFinite else { return nil }
    guard mirBPM > 0, gridBPM > 0, drumsBPM > 0 else { return nil }

    let safeThreshold: Double = (thresholdPct > 0 && thresholdPct < 1) ? thresholdPct : 0.03

    let mirGridDelta = abs(mirBPM - gridBPM) / max(mirBPM, gridBPM)
    let mirDrumsDelta = abs(mirBPM - drumsBPM) / max(mirBPM, drumsBPM)
    let gridDrumsDelta = abs(gridBPM - drumsBPM) / max(gridBPM, drumsBPM)

    guard max(mirGridDelta, mirDrumsDelta, gridDrumsDelta) > safeThreshold else { return nil }

    return ThreeWayBPMReading(
        mirBPM: mirBPM,
        gridBPM: gridBPM,
        drumsBPM: drumsBPM,
        mirGridDeltaPct: mirGridDelta,
        mirDrumsDeltaPct: mirDrumsDelta,
        gridDrumsDeltaPct: gridDrumsDelta
    )
}

// MARK: - BPMMismatchWarning

/// Track-agnostic record of a BPM-estimator disagreement worth logging.
///
/// Caller composes the log line by combining this with the track title.
public struct BPMMismatchWarning: Equatable, Sendable {
    /// MIR-derived BPM (DSP.1 trimmed-mean IOI on sub_bass). Always non-zero;
    /// callers should not construct one with `mirBPM == 0`.
    public let mirBPM: Double

    /// Offline BeatGrid BPM (Beat This! → BeatGridResolver). Always non-zero.
    public let gridBPM: Double

    /// Relative disagreement: `|mirBPM - gridBPM| / max(mirBPM, gridBPM)`.
    /// Always strictly greater than the threshold passed to `detectBPMMismatch`.
    public let deltaPct: Double

    public init(mirBPM: Double, gridBPM: Double, deltaPct: Double) {
        self.mirBPM = mirBPM
        self.gridBPM = gridBPM
        self.deltaPct = deltaPct
    }
}

// MARK: - Detector

/// Detect disagreement between two BPM estimators.
///
/// Returns `nil` when:
///   - either input is zero (one estimator failed silently — not a useful
///     signal; the upstream WIRING logs already surface that case),
///   - either input is non-finite (NaN or ±∞ guard — defensive),
///   - the relative delta is at or below `thresholdPct`.
///
/// Returns a populated `BPMMismatchWarning` when the relative delta strictly
/// exceeds `thresholdPct`. The threshold default of 0.03 (3 %) is intentionally
/// generous: the offline resolver's own `±0.5` BPM tolerance is ~0.4 % at
/// 125 BPM, so 3 % leaves substantial headroom for legitimate small
/// disagreements (e.g. 123.2 vs 125 = 1.4 % on Money does NOT fire). Love
/// Rehab's 5.5 % firmly does fire.
///
/// - Parameters:
///   - mirBPM: BPM from MIR analysis (kick-rate IOI estimator).
///   - gridBPM: BPM from offline BeatGrid (Beat This! transformer).
///   - thresholdPct: Minimum relative disagreement that returns a warning.
///     Must be in `(0, 1)`; values outside are treated as 0.03.
public func detectBPMMismatch(
    mirBPM: Double,
    gridBPM: Double,
    thresholdPct: Double = 0.03
) -> BPMMismatchWarning? {
    guard mirBPM.isFinite, gridBPM.isFinite else { return nil }
    guard mirBPM > 0, gridBPM > 0 else { return nil }

    let safeThreshold: Double = (thresholdPct > 0 && thresholdPct < 1)
        ? thresholdPct
        : 0.03

    let denom = max(mirBPM, gridBPM)
    let delta = abs(mirBPM - gridBPM) / denom
    guard delta > safeThreshold else { return nil }

    return BPMMismatchWarning(mirBPM: mirBPM, gridBPM: gridBPM, deltaPct: delta)
}
