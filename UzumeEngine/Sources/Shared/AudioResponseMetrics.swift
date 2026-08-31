// AudioResponseMetrics — the seam that lets a gate read a preset's VISUAL response.
//
// QG.1's `audio_routes` manifest asserts a declared PRIMITIVE varies on the canonical
// fixtures. It does not — and structurally cannot — assert that the visual quantity the
// primitive drives moves a useful amount. The chain is
//
//     primitive  →  gain  →  visual response
//
// and only the first arrow was ever gated. That gap is why "the gain is too low" is a
// recurring defect class rather than a one-off:
//
//   BUG-027 / CR.1.1  `spectral_centroid × N` traversed < 1 rung of an 11-rung ladder.
//   AGC2              `midDev` / `trebDev` were structurally ~0 under a fixed 0.5 pivot.
//   FA #73            deviation primitives spike to ~3× on real music, so a gain tuned
//                     against a nominal 1.0 under-drives everything.
//   Witchlight        pen heading turned 0.20 turns per 30 s trail against a needed 1.5+.
//
// Every one passed route coverage. The primitive was alive; the picture barely moved.
//
// A preset runtime conforms to this and answers to the metric names its sidecar declares
// in `audio_routes[].response.metric`. Metrics are plain scalars in whatever unit makes
// the behaviour legible — turns of heading, rungs of a ladder, pixels of camera push —
// because the useful band is a property of the behaviour, not of a normalised abstraction.
//
// Deliberately NOT a rendered-frame metric. Frame statistics can tell you the picture
// changed; they cannot tell you the pen turned far enough, and it is that specific
// quantity the author reasons about when choosing a gain.

import Foundation

// MARK: - AudioResponseMetrics

/// A preset runtime that can report named scalar response metrics after a replay.
///
/// Conformance is opt-in and per-preset, exactly as `audio_routes` was at QG.1: a preset
/// that declares no `response` band needs none. Adopt it when a route's gain is the kind
/// of thing that can silently drift out of range — which, on the evidence above, is most
/// of them.
public protocol AudioResponseMetrics: AnyObject {

    /// Value of a named metric, or `nil` if this runtime does not publish it.
    ///
    /// Called ONCE after a fixture replay completes, so implementations are free to
    /// accumulate across the run and normalise here (e.g. total heading travel ÷ elapsed
    /// seconds × the trail window). The replay length is fixture-dependent, so a metric
    /// must be expressed per unit of something — never as a raw total, which would make
    /// the band depend on how long the fixture happens to be.
    func responseMetric(_ name: String) -> Double?
}
