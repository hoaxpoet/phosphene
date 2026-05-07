// DashboardSnapshot — Sendable bundle of (beat, stems, perf) for one frame.
//
// Published from `VisualizerEngine` once per rendered frame and consumed by
// the SwiftUI dashboard overlay view model (DASH.7). Throttled there to
// ~30 Hz before triggering a redraw.

import Foundation
import Shared

/// Immutable per-frame snapshot of all three dashboard inputs.
public struct DashboardSnapshot: Sendable, Equatable {
    public let beat: BeatSyncSnapshot
    public let stems: StemFeatures
    public let perf: PerfSnapshot

    public init(beat: BeatSyncSnapshot, stems: StemFeatures, perf: PerfSnapshot) {
        self.beat = beat
        self.stems = stems
        self.perf = perf
    }

    public static func == (lhs: DashboardSnapshot, rhs: DashboardSnapshot) -> Bool {
        guard lhs.perf == rhs.perf else { return false }
        return bytewiseEqual(lhs.beat, rhs.beat) && bytewiseEqual(lhs.stems, rhs.stems)
    }
}

/// `BeatSyncSnapshot` and `StemFeatures` lack `Equatable`; bytewise compare
/// via `withUnsafeBytes` + `memcmp` is sufficient for change detection.
private func bytewiseEqual<T>(_ lhs: T, _ rhs: T) -> Bool {
    var lhsCopy = lhs
    var rhsCopy = rhs
    return withUnsafeBytes(of: &lhsCopy) { lhsBytes in
        withUnsafeBytes(of: &rhsCopy) { rhsBytes in
            lhsBytes.count == rhsBytes.count
                && memcmp(lhsBytes.baseAddress, rhsBytes.baseAddress, lhsBytes.count) == 0
        }
    }
}
