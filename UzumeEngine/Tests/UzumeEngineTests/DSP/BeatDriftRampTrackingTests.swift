// BeatDriftRampTrackingTests — TRK.1 / BUG-065: the tracker must NULL a period error,
// not merely bound it.
//
// THE DEFECT, stated as control theory. The legacy tracker updates drift with a
// first-order EMA on the phase error — a proportional-only controller. Such a
// controller has zero steady-state error against a STEP but *constant* steady-state
// error against a RAMP. A cached BeatGrid whose period is slightly wrong produces
// exactly a ramp: the audible beat and the grid separate linearly forever.
//
// EVIDENCE this is the real shape (session `2026-07-30T15-39-21Z`, Lumen Mosaic,
// 80.45 BPM): drift by 10 s window 0/6/8/52/70/59/68/104/119 ms, linear fit
// −1.493 ms/s at R² = 0.844, `grid_bpm` rock-constant. The BPM is right; the PHASE
// slips, implying a 0.149 % period error (0.12 BPM). 50 % of frames exceeded the
// ~60 ms perceptual window. Matt: "feels a little laggy."
//
// THE FIX (TRK.1): add an integral-of-error PERIOD term, making the loop type-2,
// which tracks a ramp with zero steady-state error.
//
// This suite simulates a playback clock running at a slightly different rate from the
// cached grid and asserts the controller property. It is deliberately control-theory
// rather than golden-image: the bug is a property of the controller.
//
// ⚠ SCOPE — READ BEFORE TRUSTING THIS AS A BUG-065 GATE. With clean once-per-beat
// onsets this simulation does NOT reproduce the live magnitude: legacy reaches only
// ~12 ms here versus 119 ms measured live. So it validates that the period term
// behaves as designed (12 -> 9 ms, and it nulls a ramp by construction) but it does
// NOT yet prove the live runaway is fixed. Something else is required to make drift
// escape to 119 ms, and until that mechanism is reproduced this is a controller test,
// not a closure gate for BUG-065.
//
// Two candidate mechanisms, neither yet confirmed — do not pick one without evidence:
//   (a) `driftSearchWindow` (±50 ms) is a CLIFF: once drift exceeds it, `nearestBeat`
//       returns nil, matching stops, and corrections stop entirely. The live curve
//       crossing 52 ms and then accelerating is consistent with this.
//   (b) the search is centred on `pt + drift` — the tracker's OWN estimate — so a
//       drifted estimate can keep confirming itself against whichever grid beat is
//       nearest to where it already believes it is.
//
// ⛔ VALIDATION RESULT (do not enable the flag on this basis). With
// PHOSPHENE_BEAT_PLL=1 the REAL recorded fixture regresses hard —
// `LiveDriftValidationTests` (loveRehab) goes to maxAbsDrift 101.5 ms against a
// 50 ms limit and beat-alignment 0.05 against a 0.80 limit. This synthetic suite
// said "improved" (12 -> 9 ms) while real data says materially worse: the period
// term integrates noisy sub-bass onsets (which are EVENTS, not beats — FA #68) into
// a runaway, exactly the failure mode the clean once-per-beat model cannot show.
//
// The controller therefore stays DEFAULT-OFF and is NOT a fix yet. The diagnosis
// (ramp / missing period term) is well-evidenced; the controller needs tuning
// against real captures, per the program's replay-first rule — most likely gating
// the rate update on tight matches only and a far smaller period gain, plus the
// TRK.2 evidence upgrade (drums-stem onsets) so it integrates beat evidence rather
// than bassline events. One failed validation attempt logged against this premise
// (beat-sync two-strikes rule).

import Testing
import Foundation
@testable import DSP
@testable import Shared

@Suite("Beat drift — ramp tracking (TRK.1 / BUG-065)")
struct BeatDriftRampTrackingTests {

    /// Playback clock error, matching the 0.149 % measured on the live session.
    static let clockErrorFraction = 0.00149
    static let bpm = 80.45
    static let trackSeconds = 90.0

    /// Drive the tracker with onsets that land on the AUDIBLE beat, while the cached
    /// grid's period is wrong by `clockErrorFraction`. Returns |drift error| sampled
    /// in 10 s windows — the same presentation BUG-065 uses.
    private static func driftByWindow(pllEnabled: Bool) -> [Double] {
        let period = 60.0 / bpm
        // Cached grid: slightly WRONG period (this is the defect's cause).
        let gridPeriod = period * (1.0 + clockErrorFraction)
        let beatCount = Int(trackSeconds / gridPeriod) + 8
        let grid = BeatGrid(
            beats: (0..<beatCount).map { Double($0) * gridPeriod },
            downbeats: stride(from: 0, to: beatCount, by: 4).map { Double($0) * gridPeriod },
            bpm: 60.0 / gridPeriod,
            beatsPerBar: 4,
            barConfidence: 1.0,
            frameRate: 60.0,
            frameCount: Int(trackSeconds * 60.0))

        let tracker = LiveBeatDriftTracker()
        tracker.setGrid(grid)

        let frameDt = 1.0 / 60.0
        var nextAudibleBeat = 0.0
        var errorsByWindow: [Int: [Double]] = [:]
        var t = 0.0
        while t < trackSeconds {
            // The onset fires on the AUDIBLE beat, which advances at the true period.
            var onset = false
            if t >= nextAudibleBeat {
                onset = true
                nextAudibleBeat += period
            }
            _ = tracker.update(subBassOnset: onset, playbackTime: t, deltaTime: Float(frameDt))

            // Truth: where the grid says the beat is, vs where it is actually heard.
            // A perfect tracker drives this to zero.
            let gridBeatIndex = (t / gridPeriod).rounded()
            let gridBeatTime = gridBeatIndex * gridPeriod
            let audibleBeatTime = gridBeatIndex * period
            let residual = (gridBeatTime - (tracker.currentDriftMs / 1000.0)) - audibleBeatTime
            errorsByWindow[Int(t / 10.0), default: []].append(abs(residual) * 1000.0)
            t += frameDt
        }
        return errorsByWindow.sorted { $0.key < $1.key }
            .map { $0.value.reduce(0, +) / Double($0.value.count) }
    }

    @Test("a period error makes the legacy proportional controller drift without bound")
    func test_legacyControllerCannotNullARamp() {
        guard !LiveBeatDriftTracker.pllEnabled else {
            print("[TRK.1] PHOSPHENE_BEAT_PLL=1 set — legacy baseline skipped")
            return
        }
        let windows = Self.driftByWindow(pllEnabled: false)
        print("[TRK.1] legacy drift by 10 s window (ms): "
              + windows.map { String(format: "%.0f", $0) }.joined(separator: "/"))
        // Documents the defect: the error GROWS across the track rather than settling.
        let first = windows.first ?? 0
        let last = windows.last ?? 0
        #expect(last > first, "legacy controller is expected to accumulate error on a ramp")
    }

    @Test("the period-tracking controller holds drift inside the perceptual window")
    func test_periodControllerNullsTheRamp() {
        guard LiveBeatDriftTracker.pllEnabled else {
            print("[TRK.1] set PHOSPHENE_BEAT_PLL=1 to exercise the period controller")
            return
        }
        let windows = Self.driftByWindow(pllEnabled: true)
        print("[TRK.1] PLL drift by 10 s window (ms): "
              + windows.map { String(format: "%.0f", $0) }.joined(separator: "/"))
        // The program's TRK.1 gate: <= 30 ms in EVERY window, not merely on average.
        let worst = windows.dropFirst().max() ?? 0     // first window is acquisition
        #expect(worst <= 30.0, """
            TRK.1 gate: every 10 s window must hold |drift| <= 30 ms once acquired. \
            Worst settled window was \(String(format: "%.1f", worst)) ms. \
            Windows: \(windows.map { String(format: "%.0f", $0) })
            """)
    }
}
