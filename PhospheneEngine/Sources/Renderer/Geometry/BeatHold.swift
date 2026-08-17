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

import Foundation
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

    /// GLIDE (FTR.14, Matt 2026-08-13). Time constant for the continuous glide toward the
    /// beat-latched target, as a fraction of a beat. `0` = the FTR.10 hard snap.
    ///
    /// ── WHY THE FTR.13 EASE WAS REMOVED RATHER THAN TUNED ────────────────────────────────
    /// FTR.13 eased the step over 1/3 of a beat, driven off `beatPhase01`. Matt's M7:
    /// *"After 6-8 seconds, the tree looks like it's dancing the robot — I don't like the
    /// stepped changes."* The cause is arithmetic, not taste, and it is BUG-087: on the
    /// local-file path every `FeatureVector` field updates at **~10 Hz**, so a 94 BPM beat
    /// carries only **6.4 samples**. A 1/3-beat ease is **2.1 samples** and the hold after it is
    /// **4.3 samples dead still** — the "smooth ease" rendered as two jumps then four ticks of
    /// nothing, 1.57 times a second. An ease cannot be smooth on two samples.
    ///
    /// ── WHAT REPLACES IT: THE BEAT SETS THE DESTINATION, NEVER THE STILLNESS ─────────────
    /// Matt's call, 2026-08-13, from three options. The beat still latches the TARGET, exactly
    /// as before — that is the sync he said he appreciates. What changed is that the visible
    /// value now glides toward that target on the **render** clock (~60 Hz) with an exponential
    /// time constant, so it is always moving and never arrives-and-freezes. Same 6.4 analysis
    /// samples per beat decide WHERE to go; ~38 render frames per beat decide how it gets
    /// there.
    ///
    /// **The glide runs whether or not the grid is trusted, and that is the point.** Before the
    /// grid engages the target is the live 10 Hz vector; after, it is the beat-latched one.
    /// Either way the geometry glides, so the 6–8 s transition Matt has now objected to three
    /// times does not exist — and the pre-grid opening he keeps preferring gets *smoother* than
    /// it was, because the glide also resolves the raw 10 Hz staircase into render-rate motion.
    private let glideBeats: Float
    /// FTR.16 — absolute-τ variant of the glide; see ``init(glideSeconds:)``.
    private let glideSeconds: Float

    /// FTR.22 — CONTINUOUS-TARGET mode: how much the beat slows the chase late in the bar.
    /// `0` keeps the beat-LATCHED target of FTR.14. Non-zero switches to a target that tracks
    /// the live frame every update, with the beat modulating the chase SPEED instead.
    ///
    /// ── WHY THE LATCH HAD TO GO ──────────────────────────────────────────────────────────
    /// Matt, clarifying "robotic" after six M7s: *"it moves in a precise, start-and-stop pattern,
    /// like the robot dance. It looks MECHANICAL, rather than organic."* That is a VELOCITY
    /// description, and it is structural rather than a tuning value: a target that only changes
    /// on beats means the value converges before the next target exists, so it arrives and then
    /// waits. Measured on his capture — 647 ms beat, τ 162 ms, so it arrives in ~485 ms and has
    /// nothing to move toward for the remaining 162 ms:
    ///
    ///     frames below  2 % of peak velocity   46.5 %
    ///     frames below  5 %                    64.8 %
    ///     frames below 10 %                    78.5 %
    ///
    /// **A value that arrives has to stop.** Continuous velocity requires a continuously-moving
    /// target, so the latch is gone and the beat now modulates the chase RATE:
    /// `τ = glideBeats · beatPeriod · (1 + beatSpeedBoost · beatPhase01)` — fastest immediately
    /// after a beat, slowest just before the next. The beat stays legible as a 4× swing in speed
    /// while position is never quantised. Simulated on the same capture at 0.35 beat / boost 3:
    /// stillness **46.5 % → 20.9 %**, against an 18.8 % floor set by the analysis rate itself,
    /// with the value's span unchanged (0.528 → 0.519).
    ///
    /// ── FTR.23: THE FIRST τ WAS 3.5× TOO SLOW, AND MY METRIC HID IT ─────────────────────
    /// FTR.22 shipped 0.35 beat with boost 3, i.e. an effective mean τ of 567 ms against
    /// FTR.18's 162 ms. Matt: *"Now it barely moves."* The stillness figure had improved
    /// (46.5 % → 14.8 %) because it was expressed as a fraction of frames below 2 % of **its own
    /// PEAK velocity** — and the peak had collapsed 44 % (0.500 → 0.281). A metric normalised by
    /// its own peak cannot detect the whole signal getting slower. Absolute travel is the bar:
    ///
    ///     build                        total travel   peak |v|   stillness
    ///     FTR.18 (rejected: robotic)       3.09         0.500       40.2 %
    ///     FTR.22 (rejected: barely moves)  2.78         0.281       14.8 %
    ///     FTR.23 (0.12 beat, boost 1.0)    3.27         0.455       22.1 %
    ///
    /// So the shipped constants give MORE total motion than the build Matt called robotic, a peak
    /// within 9 % of it, and roughly half its stillness.
    ///
    /// **τ HAS A FLOOR: the analysis tick.** The source updates ~15.8 times a second on this
    /// capture (63 ms), so τ below that converges inside one tick and the value becomes a
    /// staircase again — the FTR.13 trap. 0.12 beat is 78 ms, comfortably above it; 0.08 beat
    /// (52 ms) is not, which is why the faster candidates were rejected despite better numbers.
    ///
    /// Note the earlier burstiness check (FTR.14) passed this build at 0.101 empty windows: it
    /// measured DISPLACEMENT per 100 ms window, not velocity, and on the trunk rather than the
    /// branch count that carries 26× the coefficient. Wrong quantity twice — see
    /// `docs/diagnostics/FTR15_SIZE_READS_LEVEL_2026-08-13.md` §7.
    private let beatSpeedBoost: Float
    /// The value actually on screen — always in motion toward `held` (FTR.14).
    private var visible = FeatureVector()
    private var visibleStems = StemFeatures()
    private var seeded = false

    /// FTR.13 — THE STEM SIDE, held on the same beats. Matt: *"the tips … should be beat
    /// matched."* The tips are driven by a per-stem field, which lives in a different struct,
    /// so holding only the `FeatureVector` leaves them changing 4–5 times a second no matter
    /// what the frame does. Same boundaries, same ease, one clock — the two cannot desync
    /// because there is only one set of beat evidence.
    private var heldStems = StemFeatures()
    private var previousStems = StemFeatures()
    private var pendingStems = StemFeatures()

    /// Hard sample-and-hold: the snapshot snaps on the beat (FTR.10 behaviour, unchanged).
    public init() { glideBeats = 0; glideSeconds = 0; beatSpeedBoost = 0 }

    /// Gliding hold: the visible value chases the beat-latched target continuously on the
    /// render clock and never holds still. Deliberately a separate initialiser rather than a
    /// defaulted parameter on ``init()`` — a defaulted parameter changes the existing signature
    /// and breaks incremental links (CLEAN.3.5).
    ///
    /// - Parameter glideBeats: exponential time constant as a fraction of a beat, clamped to
    ///   `0…1`. Tempo-relative on purpose, so the motion means the same thing at 94 and 124 BPM
    ///   (the FTR.12c lesson about per-second bars carrying the tempo).
    public init(glideBeats: Float) {
        self.glideBeats = min(max(glideBeats, 0), 1)
        glideSeconds = 0
        beatSpeedBoost = 0
    }

    /// CONTINUOUS-TARGET glide (FTR.22, Matt 2026-08-16). The target tracks the live frame every
    /// update — it is never latched — and the beat modulates how fast the visible value chases
    /// it. The result never arrives, so it never stops. See ``beatSpeedBoost``.
    ///
    /// - Parameters:
    ///   - continuousGlideBeats: base time constant as a fraction of a beat.
    ///   - beatSpeedBoost: how much slower the chase gets by the end of the beat. 3 gives a 4×
    ///     speed swing, which keeps the beat legible without quantising position.
    public init(continuousGlideBeats: Float, beatSpeedBoost: Float) {
        glideBeats = min(max(continuousGlideBeats, 0), 1)
        glideSeconds = 0
        self.beatSpeedBoost = max(beatSpeedBoost, 0)
    }

    /// SECTION-SCALE glide with an absolute time constant, for quantities that answer to song
    /// structure rather than to beats (FTR.16).
    ///
    /// Tempo-relative τ is right for anything the beat drives, but a section is not a multiple
    /// of a beat — and `glideBeats` is capped at one beat (0.64 s at 94 BPM), far too fast for
    /// "how big is the tree". Measured on three captures, `spectral_density` needs τ ≈ 5 s to sit
    /// in the same motion band as the level rank it replaces (0.75–0.87 direction changes/s
    /// against 0.66–0.77); at the fast leg's own rate it turns 3.6 times a second, which is the
    /// restlessness FTR.3f banned from continuous geometry.
    ///
    /// - Parameter glideSeconds: exponential time constant in seconds. There is deliberately no
    ///   beat latch on this path: a section-scale value has nothing to gain from beat
    ///   quantisation and would only inherit the grid's failure modes.
    public init(glideSeconds: Float) {
        glideBeats = 0
        self.glideSeconds = max(glideSeconds, 0)
        beatSpeedBoost = 0
    }

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
        update(frame, renderDeltaTime: 0)
    }

    /// Feed one frame plus the wall-clock seconds since the last DRAW, and get back the value
    /// to render.
    ///
    /// `renderDeltaTime` must come from the render clock (~1/60 s), not from `frame.time` —
    /// `frame.time` advances at the ~10 Hz analysis rate on the local-file path (BUG-087), and
    /// driving the glide from it would reproduce the exact staircase FTR.14 removes.
    public mutating func update(
        _ frame: FeatureVector, renderDeltaTime: Float
    ) -> FeatureVector {
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

        // THE TARGET. Latched on the beat while the grid is trusted, otherwise the live frame.
        // Section mode never latches: `glideSeconds` answers to structure, not to beats.
        // FTR.22 — continuous-target mode never latches: the target IS the live frame.
        if wrapped || !isStepping || glideSeconds > 0 || beatSpeedBoost > 0 {
            held = frame
            heldStems = pendingStems
        }
        guard glideBeats > 0 || glideSeconds > 0 else { return held }

        // First frame: start ON the target rather than gliding up from an all-zero vector,
        // which would read as the tree growing out of nothing at every track change.
        if !seeded {
            visible = held
            visibleStems = heldStems
            seeded = true
        }

        // THE GLIDE, on the RENDER clock. `renderDeltaTime` is wall-clock seconds since the
        // last draw (~1/60 s), NOT the analysis interval — that distinction is the whole fix.
        // Passing 0 leaves the visible value untouched, which is what `advanceBeatHold` wants
        // when it is only feeding the beat clock for rows it does not draw.
        // Section-scale mode ignores the beat period entirely — see `init(glideSeconds:)`.
        let tau = currentTau(beatPhase01: frame.beatPhase01)
        let alpha = Self.glideAlpha(deltaTime: renderDeltaTime, tau: tau)
        visible = Self.lerp(visible, held, alpha, clocksFrom: frame)
        visibleStems = Self.lerpStems(visibleStems, heldStems, alpha)
        return visible
    }

    /// The chase time constant for this frame.
    ///
    /// FTR.22 — in continuous-target mode the beat modulates SPEED, not position: τ is smallest
    /// immediately after a beat and largest just before the next, so the value is always moving
    /// and the beat reads as a change of pace. Gated on `isStepping`, because on an untrusted
    /// grid `beatPhase01` is `BeatPredictor`'s raw-onset estimate — banned as a motion driver —
    /// and the chase must fall back to its base rate rather than be steered by it.
    private func currentTau(beatPhase01: Float) -> Float {
        let base = glideSeconds > 0
            ? glideSeconds
            : Self.glideTau(glideBeats: glideBeats, beatPeriod: Self.mean(intervals))
        guard beatSpeedBoost > 0, isStepping else { return base }
        return base * (1 + beatSpeedBoost * min(max(beatPhase01, 0), 1))
    }

    /// Exponential time constant in seconds. Tempo-relative while a beat period is known;
    /// falls back to a fixed value before the grid has produced one, so the glide is running
    /// from the very first frame of playback (which is the part Matt likes).
    static func glideTau(glideBeats: Float, beatPeriod: Float?) -> Float {
        let period = beatPeriod ?? 0.6      // ~100 BPM, only until real intervals arrive
        return max(glideBeats * period, 0.001)
    }

    /// Frame-rate-independent smoothing factor: `1 − exp(−dt/τ)`. Frame-rate independence is
    /// not a nicety here — a fixed per-frame alpha would make the motion faster on a machine
    /// that renders faster, and the whole defect being fixed came from confusing two clocks.
    static func glideAlpha(deltaTime: Float, tau: Float) -> Float {
        guard deltaTime > 0, tau > 0 else { return 0 }
        return 1 - exp(-deltaTime / tau)
    }

    /// Feed the stem side for this frame, then read ``heldStemFeatures``.
    ///
    /// Separate from ``update(_:)`` on purpose: `update` is the beat clock and every caller
    /// already drives it for every frame (including the harness rows it skips drawing). Making
    /// the stems a second argument there would have meant one signature change across three
    /// call sites and a silent desync the moment one of them was missed. Call this BEFORE
    /// `update` for the same frame.
    public mutating func offerStems(_ stems: StemFeatures) { pendingStems = stems }

    /// The stem features on screen — glided identically to ``update(_:renderDeltaTime:)``'s
    /// return value, and advanced by the same call. Read after `offerStems` + `update`.
    public var glidingStemFeatures: StemFeatures {
        glideBeats > 0 || glideSeconds > 0 ? visibleStems : heldStems
    }

    // MARK: - Glide

    private mutating func reset(_ frame: FeatureVector) {
        // FTR.14 — the glide is NOT reset across a track change: `visible` keeps chasing, so a
        // new track eases in from whatever was on screen instead of snapping. `seeded` stays
        // true for the same reason.
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
