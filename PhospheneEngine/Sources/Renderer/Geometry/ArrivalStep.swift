// ArrivalStep — the tree's size HOLDS and STEPS, instead of drifting.
//
// ★★★ WHY THIS TYPE EXISTS, because the fix is a premise change and not a coefficient.
//
// Matt has now rejected the Fractal Tree's growth channel on three consecutive live reviews with
// the same word: *"Tree also grows and shrinks in a seemingly random manner"* (2026-08-19).
// Measured on that capture, the total branch count spans **15 → 33**, crosses its own median
// **0.105 times/s** — one grow/shrink cycle every ~9.5 s — and is **entirely drift**: half its
// variance sits in a τ 8 s component and the remainder is slower still. There is not one step
// in it.
//
// His own definition of what he asked for is a STEP: *"shoot up = the trunk elongates and the
// next level of branches appears"* (FTR.11). Five drivers have been tried — `bass_rel`,
// `arousal`, `spectral_density`, `spectral_surge`, the τ 20 s section rank — and every one is a
// continuous statistic that the preset then smooths, so the step-shaped intent arrived as drift
// each time.
//
// ★★ AND ACCURACY IS NOT THE MISSING PROPERTY. The size already follows true loudness measured
// from `raw_tap.wav` at **r = +0.863** (FTR.15 §2) and still reads as random. What makes a
// channel legible is a reference the LISTENER is also holding: the beat, in the gait that Matt
// approved (*"The tree bounces to the beat - great"*), and a sound LANDING, here. A step that
// coincides with something audible can be paired with it; a faithful follower of a rank cannot.
//
// So the size becomes a small number of held tiers, and each change of tier is committed on an
// arrival so the step lands WITH a sound Matt just heard.
//
// NOT FTR.24 AGAIN. That increment fed `spectral_level_rise` to the size as a CONTINUOUS accent
// added after the glide, and Matt rejected it on sight (*"herky-jerky … looks defective"*) —
// measured, 10.7× peak velocity. Here the field is only a TRIGGER: it decides *when* a step is
// allowed to commit, never how large the size is. The magnitude comes from the tier table, the
// rate from one ease, and both are bounded by construction.

import Foundation

// MARK: - ArrivalStep

/// A size that holds at one of a few tiers and steps between them when a sound lands.
///
/// Feed it a per-track density rank (0…1) and an arrival transient (`spectral_level_rise`), and it
/// returns the eased growth value the preset should use. Deterministic: all state advances from
/// the `deltaTime` passed in, so a harness can drive it frame-exactly.
public final class ArrivalStep {

    // MARK: Tuning

    /// Three tiers, normalised. What a tier MEANS — trunk length, branch count, thickness — is the
    /// preset's business (`FractalTree.metal` maps 0…1 onto the spans it already used, so the tree
    /// covers the same size range it does today; it is held still and stepped through, not
    /// inflated). Keeping the mapping out of here is what stops this type from being tree-shaped.
    private static let tiers: [Float] = [0.0, 0.5, 1.0]

    /// ★★ EDGES ON A PER-TRACK RANK, WHICH IS WHY THEY CAN BE CONSTANTS.
    ///
    /// Two earlier attempts got this wrong in opposite directions and both are worth keeping.
    /// First, fixed edges on the level (0.34 / 0.62): the corrected level lives in 0.38…0.75 on
    /// Matt's capture, so the tree sat in one tier for 130 of 142 seconds. Then a running
    /// mean-and-spread, so the tiers would mean "louder than usual for this track" — and TRACED
    /// on the same capture the mean read 0.691 against a level of 0.445 and the tier never left 0
    /// at all. The bug behind that one is the more useful finding: I modelled the section glide as
    /// a plain EMA when production glides it on `BeatHold`, so the offline simulation that said
    /// "12 steps, all three tiers" was measuring a pipeline that does not exist. Measure the
    /// consumer's arithmetic, not a plausible stand-in for it.
    ///
    /// The engine already solved the underlying problem. `spectral_section_ratio` is DYN.2c's
    /// rank of this moment in the TRACK's own density distribution — uniform over the track by
    /// construction, which is exactly what makes constant edges legitimate here and why the
    /// 0.78/1.38 pair it replaced had to go. Scaled ×0.5 (so 1.0 reads as "this track's normal",
    /// the same convention the drifting `fullness` term used) it spans 0.06…0.93 on the capture
    /// with p33 0.175 and p66 0.520, crossing each edge 0.8–1.3 times a minute. No statistics, no
    /// warmup, no seeding — a filter's first seconds cannot be wrong if there is no filter.
    ///
    /// It is also the more perceptible quantity of the two: density is how much is PLAYING, and
    /// "more instruments came in" is something a listener notices, where a level rank is not.
    private static let bounds: [Float] = [0.33, 0.66]
    private static let hysteresis: Float = 0.06

    /// A crossing must PERSIST before an arrival can commit it. Without this the slack alone has
    /// to do the whole job, and a rank that touches an edge for two frames could step the tree the
    /// moment the next transient lands — the drift complaint rebuilt as a twitch, which is worse
    /// because it is faster and harder to attribute to anything.
    private static let minDwellSeconds: Float = 0.35

    /// An arrival this large commits a pending step. `spectral_level_rise` is a 2–7 dB band, so
    /// 0.4 is a clearly audible entry rather than a swell.
    private static let arrivalThreshold: Float = 0.40

    /// A step UP waits for an arrival, but not forever: a section can get fuller without a single
    /// clean transient, and a tree that refuses to grow is FTR.3d's complaint (*"I expect the tree
    /// to grow outward, but it barely moves"*) rebuilt as a deadlock.
    private static let upTimeoutSeconds: Float = 3.0

    /// A step DOWN is never triggered by a transient — a thinning does not announce itself with
    /// one — so it commits on dwell alone.
    private static let downDwellSeconds: Float = 1.5

    /// Floor on the gap between committed steps, so a busy passage cannot produce a staircase.
    private static let cooldownSeconds: Float = 1.0

    /// The ease onto a new tier. Long enough to read as the tree moving rather than cutting,
    /// short enough that the step still lands with the sound that triggered it.
    private static let easeTau: Float = 0.25

    // MARK: State

    private var tier: Int = 0
    private var wantDwell: Float = 0
    private var sinceCommit: Float = ArrivalStep.cooldownSeconds
    private var eased: Float = ArrivalStep.tiers[0]

    /// The current growth value, eased. 0…1.
    public var growth: Float { eased }

    /// Diagnostic only — the internal state, for tracing why a tier did or did not change.
    public var debugState: String {
        String(format: "tier=%d dwell=%.2f since=%.2f", tier, wantDwell, sinceCommit)
    }

    public init() {}

    // MARK: Update

    /// Advance one frame and return the growth value.
    ///
    /// - Parameters:
    ///   - level: `spectral_section_ratio × 0.5` on the section glide — this passage's rank in
    ///     the track's own density distribution, 0…1.
    ///   - arrival: `spectral_level_rise` for this frame, 0…1.
    ///   - deltaTime: seconds since the previous call (render rate, not analysis rate — BUG-087).
    @discardableResult
    public func update(level: Float, arrival: Float, deltaTime: Float) -> Float {
        let dt = min(max(deltaTime, 1.0 / 240.0), 1.0 / 15.0)
        sinceCommit += dt

        let want = tierWanted(for: level)
        if want == tier {
            wantDwell = 0
        } else {
            wantDwell += dt
            let ready = sinceCommit >= Self.cooldownSeconds
            // One tier per commit: a level that jumps two tiers walks there, so the tree never
            // teleports between sizes however abrupt the audio is.
            let stepping = want > tier
                ? (wantDwell >= Self.minDwellSeconds
                   && (arrival >= Self.arrivalThreshold || wantDwell >= Self.upTimeoutSeconds))
                : wantDwell >= Self.downDwellSeconds
            if ready && stepping {
                tier += want > tier ? 1 : -1
                wantDwell = 0
                sinceCommit = 0
            }
        }

        let target = Self.tiers[tier]
        eased += (target - eased) * (1 - exp(-dt / Self.easeTau))
        return eased
    }

    /// Back to the smallest tier, for a track change — a new track's first arrival should grow the
    /// tree, not find it already full from the last one.
    public func reset() {
        tier = 0
        wantDwell = 0
        sinceCommit = Self.cooldownSeconds
        eased = Self.tiers[0]
    }

    // MARK: - Tiers

    private func tierWanted(for rank: Float) -> Int {
        // The slack widens whichever band is current, so leaving a tier costs more than staying.
        var want = 0
        for (index, bound) in Self.bounds.enumerated()
        where rank >= (index < tier ? bound - Self.hysteresis : bound + Self.hysteresis) {
            want = index + 1
        }
        return min(max(want, 0), Self.tiers.count - 1)
    }
}
