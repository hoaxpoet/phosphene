// StemEnergyHistory — Rolling per-stem energy samples for the STEMS card
// timeseries visualisation (DASH.7).
//
// Held by `DashboardOverlayViewModel`. On each `DashboardSnapshot` push the
// view model appends the current `stems.{drums,bass,vocals,other}EnergyRel`
// to each ring; on each throttled redraw it snapshots the rings into this
// `Sendable` value and feeds it to `StemsCardBuilder`.
//
// Capacity is fixed at 240 samples (≈ 8 s at 30 Hz redraw cadence).

import Foundation

/// Immutable snapshot of recent stem-energy samples for the four stems.
///
/// Each array carries up to `Self.capacity` samples with the OLDEST first.
/// Empty arrays are valid — the timeseries row variant draws nothing for
/// zero-length input. Builder + view consume this directly; no clamping or
/// resampling at the boundary.
public struct StemEnergyHistory: Sendable, Equatable {

    /// Maximum samples retained per stem.
    public static let capacity = 240

    public let drums: [Float]
    public let bass: [Float]
    public let vocals: [Float]
    public let other: [Float]

    public init(drums: [Float], bass: [Float], vocals: [Float], other: [Float]) {
        self.drums = drums
        self.bass = bass
        self.vocals = vocals
        self.other = other
    }

    /// Empty history — used as the initial state and as the no-data fixture.
    public static let empty = StemEnergyHistory(drums: [], bass: [], vocals: [], other: [])
}
