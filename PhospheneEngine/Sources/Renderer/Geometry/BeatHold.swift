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

    /// EASED STEPS (FTR.13, Matt 2026-08-12). Fraction of a beat over which the snapshot
    /// travels from the previous beat's value to this one. `0` = the original hard snap.
    ///
    /// Matt's M7 on FTR.11: *"the motion reads as robotic and stuttering … it's the stepping
    /// itself that is the problem."* A hard sample-and-hold holds perfectly still and then
    /// jumps — which is what a low turn rate BUYS, and why a rate bar scored the frame calm at
    /// 0.30 turns/beat while the canopy read as robotic. The opposite of a snap is not
    /// "unlock from the beat", which brings back the motion he rejected at FTR.11; it is a step
    /// that STARTS on the beat and takes a fraction of a beat to arrive. Motion onset stays
    /// beat-locked (the eye reads onset as the event) and travel per beat is unchanged — only
    /// the sharpness goes.
    private let easeBeats: Float
    /// The value the previous beat settled on — the near end of the ease.
    private var previous = FeatureVector()

    /// FTR.13 — THE STEM SIDE, held on the same beats. Matt: *"the tips … should be beat
    /// matched."* The tips are driven by a per-stem field, which lives in a different struct,
    /// so holding only the `FeatureVector` leaves them changing 4–5 times a second no matter
    /// what the frame does. Same boundaries, same ease, one clock — the two cannot desync
    /// because there is only one set of beat evidence.
    private var heldStems = StemFeatures()
    private var previousStems = StemFeatures()
    private var pendingStems = StemFeatures()

    /// Hard sample-and-hold: the snapshot snaps on the beat (FTR.10 behaviour, unchanged).
    public init() { easeBeats = 0 }

    /// Eased hold: the snapshot starts moving ON the beat and arrives `easeBeats` of a beat
    /// later. Deliberately a separate initialiser rather than a defaulted parameter on
    /// ``init()`` — a defaulted parameter changes the existing signature and breaks
    /// incremental links (CLEAN.3.5), and an explicit initialiser keeps the two behaviours
    /// legible at the call site.
    ///
    /// - Parameter easeBeats: clamped to `0…1`. Above 1 the ease would outlast its own beat.
    public init(easeBeats: Float) { self.easeBeats = min(max(easeBeats, 0), 1) }

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

        if wrapped || !isStepping {
            // The value we were showing becomes the near end of the next ease. While not
            // stepping both ends are the live frame, so the ease is a no-op and the preset
            // gets exactly its continuous behaviour.
            previous = isStepping ? held : frame
            held = frame
            previousStems = isStepping ? heldStems : pendingStems
            heldStems = pendingStems
        }
        guard easeBeats > 0, isStepping else { return held }
        let weight = Self.easeWeight(frame.beatPhase01, over: easeBeats)
        return Self.lerp(previous, held, weight, clocksFrom: frame)
    }

    /// Feed the stem side for this frame, then read ``heldStemFeatures``.
    ///
    /// Separate from ``update(_:)`` on purpose: `update` is the beat clock and every caller
    /// already drives it for every frame (including the harness rows it skips drawing). Making
    /// the stems a second argument there would have meant one signature change across three
    /// call sites and a silent desync the moment one of them was missed. Call this BEFORE
    /// `update` for the same frame.
    public mutating func offerStems(_ stems: StemFeatures) { pendingStems = stems }

    /// The stem features as of the last beat boundary, eased identically to ``update(_:)``'s
    /// return value. Read after `offerStems` + `update` for the frame.
    public func heldStemFeatures(at beatPhase01: Float) -> StemFeatures {
        guard easeBeats > 0, isStepping else { return heldStems }
        let weight = Self.easeWeight(beatPhase01, over: easeBeats)
        return Self.lerpStems(previousStems, heldStems, weight)
    }

    // MARK: - Easing

    /// Smoothstep from 0 at the beat to 1 after `easeBeats` of a beat. Smoothstep rather than
    /// a straight ramp so there is no velocity discontinuity at either end — a linear ease
    /// still arrives with a visible stop, which is the artifact being removed.
    static func easeWeight(_ beatPhase01: Float, over easeBeats: Float) -> Float {
        guard easeBeats > 0 else { return 1 }
        let progress = min(max(beatPhase01 / easeBeats, 0), 1)
        return progress * progress * (3 - 2 * progress)
    }

    /// Element-wise lerp of two snapshots.
    ///
    /// `FeatureVector` is 47 stored properties and every one is a `Float` (verified by
    /// `BeatHoldTests.everyFeatureVectorFieldIsFloat`, which fails if a non-`Float` field is
    /// ever added), so the blend runs over the raw float storage instead of 47 hand-written
    /// lines that a new field would silently escape.
    ///
    /// CLOCKS ARE NOT BLENDED. `time`, `beatPhase01`, `barPhase01` and `pulseBeatIndex` are
    /// copied from the live frame: a phase lerped across its 1 → 0 wrap runs BACKWARDS, and a
    /// consumer reading a clock wants the real one. (The pre-FTR.13 hard hold froze these too,
    /// so this is strictly better, not a new obligation.)
    static func lerp(
        _ from: FeatureVector, _ to: FeatureVector, _ weight: Float,
        clocksFrom live: FeatureVector
    ) -> FeatureVector {
        // t == 0 is the beat frame itself and must return the PREVIOUS value — the ease starts
        // from where the eye already was. Returning `b` there put a one-frame snap on every
        // beat, i.e. precisely the artifact FTR.13 exists to remove; caught by
        // `BeatHoldTests.blendedStructsAreFloatOnly`.
        var out = weight <= 0 ? from : to
        if weight > 0 && weight < 1 {
            let count = MemoryLayout<FeatureVector>.size / MemoryLayout<Float>.size
            withUnsafeMutableBytes(of: &out) { destination in
                withUnsafeBytes(of: from) { nearBytes in
                    withUnsafeBytes(of: to) { farBytes in
                        let output = destination.bindMemory(to: Float.self)
                        let near = nearBytes.bindMemory(to: Float.self)
                        let far = farBytes.bindMemory(to: Float.self)
                        for i in 0..<count {
                            output[i] = near[i] + (far[i] - near[i]) * weight
                        }
                    }
                }
            }
        }
        out.time = live.time
        out.beatPhase01 = live.beatPhase01
        out.barPhase01 = live.barPhase01
        out.pulseBeatIndex = live.pulseBeatIndex
        return out
    }

    /// `lerp` for the stem side. `StemFeatures` is 58 stored properties and every one is a
    /// `Float` (gated by `BeatHoldTests.everyStemFeaturesFieldIsFloat`); it carries no clocks,
    /// so nothing needs restoring from a live frame.
    static func lerpStems(
        _ from: StemFeatures, _ to: StemFeatures, _ weight: Float
    ) -> StemFeatures {
        guard weight > 0, weight < 1 else { return weight <= 0 ? from : to }
        var out = to
        let count = MemoryLayout<StemFeatures>.size / MemoryLayout<Float>.size
        withUnsafeMutableBytes(of: &out) { destination in
            withUnsafeBytes(of: from) { nearBytes in
                withUnsafeBytes(of: to) { farBytes in
                    let output = destination.bindMemory(to: Float.self)
                    let near = nearBytes.bindMemory(to: Float.self)
                    let far = farBytes.bindMemory(to: Float.self)
                    for i in 0..<count {
                        output[i] = near[i] + (far[i] - near[i]) * weight
                    }
                }
            }
        }
        return out
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
