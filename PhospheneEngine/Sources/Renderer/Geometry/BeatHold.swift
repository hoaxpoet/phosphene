// BeatHold — sample-and-hold on the cached beat grid, for mesh-pipeline presets (FTR.10).
//
// WHAT IT IS. A mesh preset's object shader is stateless: it sees one `FeatureVector` and
// has no memory of the last frame, so it cannot make a value HOLD between beats and STEP on
// the beat. That state has to live on the CPU. `BeatHold` keeps one snapshot — the
// `FeatureVector` as it stood at the last beat boundary — and `MeshGenerator` binds it at
// object/mesh buffer(4) alongside the live vector at buffer(0). A preset reads whichever it
// wants per visual layer: live for what should slide, held for what should step.
//
// WHY IT GATES ITSELF. `beatPhase01` is the cached grid's drift-corrected phase only when
// a `BeatGrid` is installed; in reactive mode `MIRPipeline` fills the same field from
// `BeatPredictor`, which is raw live onsets — banned as a motion driver (±80 ms jitter,
// CLAUDE.md §Audio Data Hierarchy Layer 4). And a grid can be installed and still be
// untrustworthy: beat-irregular tracks (D-154) carry a grid whose beats genuinely wander,
// and `beatPhase01` has been measured stalling outright (Witchlight WL.2). Holding against
// any of those is worse than not holding — a stalled phase FREEZES the value.
//
// So the snapshot is only frozen while the phase is demonstrably behaving:
//
//   1. a bar clock has been seen — `barPhase01` is identically 0 in reactive mode, so a
//      single non-zero reading is proof that a `BeatGrid` is installed;
//   2. the last 8 beat intervals are steady — sd ≤ 20 % of the mean. Rubato and predictor
//      phase both scatter far more; the ~10 Hz analysis rate quantises a real interval by
//      at most ±1 tick, which is ≤ 12 % on the fastest plausible beat;
//   3. a beat actually arrived recently — no wrap for 2× the mean period clears the
//      evidence, so a stalled phase reverts to tracking rather than freezing.
//
// Until all three hold, the snapshot tracks the live vector every frame and the preset gets
// exactly its previous continuous behaviour. That is also the cold-start answer: eight
// consistent intervals is ~4 s of playback, so nothing steps from frame 1. The grid can
// still install with the right BPM and the WRONG phase (Cold-Start Phase Contract — not
// solvable here, and not to be iterated on); a hold has no attack, so a phase error reads
// as a change landing slightly early or late, not as a wrong-phase flash.

import Shared

// MARK: - BeatHold

/// The `FeatureVector` as it stood at the last beat boundary, for presets that need a value
/// to step on the beat instead of sliding between beats.
///
/// Feed every analysis frame through ``update(_:)`` in order; the returned vector changes
/// only on beat boundaries once the grid has proved steady, and tracks the input frame by
/// frame whenever it has not.
public struct BeatHold: Sendable {

    /// Beat intervals kept for the steadiness test. Eight beats is ~4 s at 120 BPM — long
    /// enough that a single mis-detected wrap cannot certify a bad grid, short enough that
    /// the hold engages early in a track.
    private static let window = 8
    /// Steadiness bar: interval sd as a fraction of the mean.
    private static let maxRelativeSpread: Float = 0.20
    /// Plausible beat period, seconds (240 … 24 BPM). Anything outside is a detection fault.
    private static let periodRange: ClosedRange<Float> = 0.25...2.5

    private var held = FeatureVector()
    private var lastPhase: Float = 0
    private var lastBeatTime: Float = -1
    private var lastTime: Float = -1
    private var intervals: [Float] = []
    private var sawBarClock = false

    public init() {}

    /// `true` while the snapshot is frozen between beats — i.e. all three trust conditions
    /// hold. Diagnostics and tests read this; presets never need it.
    public var isStepping: Bool {
        sawBarClock && intervals.count == Self.window && Self.isSteady(intervals)
    }

    /// Feed one frame and get back the beat-held vector.
    ///
    /// - Parameter frame: the live `FeatureVector` for this frame.
    /// - Returns: `frame` itself whenever the grid is not trusted; otherwise the frame
    ///   captured at the most recent beat boundary.
    public mutating func update(_ frame: FeatureVector) -> FeatureVector {
        let now = frame.time
        // A track change (or a harness rewinding a capture) resets the clock. Carrying beat
        // evidence across that boundary would certify the new track's grid on the old
        // track's beats.
        if lastTime < 0 || now < lastTime || now - lastTime > 1.0 { reset(frame) }
        lastTime = now

        if frame.barPhase01 > 0 { sawBarClock = true }

        // The beat boundary is `beatPhase01` wrapping 1 → 0. The 0.25 margin keeps analysis
        // noise on a slowly-rising ramp from reading as a wrap.
        let wrapped = frame.beatPhase01 < lastPhase - 0.25
        lastPhase = frame.beatPhase01

        if wrapped {
            if lastBeatTime >= 0 {
                let interval = now - lastBeatTime
                if Self.periodRange.contains(interval) {
                    intervals.append(interval)
                    if intervals.count > Self.window { intervals.removeFirst() }
                } else {
                    intervals.removeAll()   // implausible period — start the evidence over
                }
            }
            lastBeatTime = now
        } else if let mean = Self.mean(intervals), now - lastBeatTime > mean * 2 {
            intervals.removeAll()           // the phase stalled; never freeze on it
        }

        if wrapped || !isStepping { held = frame }
        return held
    }

    // MARK: - Private

    private mutating func reset(_ frame: FeatureVector) {
        held = frame
        lastPhase = 0
        lastBeatTime = -1
        intervals.removeAll()
        sawBarClock = false
    }

    private static func mean(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    private static func isSteady(_ values: [Float]) -> Bool {
        guard let mean = mean(values), mean > 0 else { return false }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)
        return variance.squareRoot() / mean <= maxRelativeSpread
    }
}
