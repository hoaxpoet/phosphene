// BeatPulseClockTests — FBS Stage 1 (D-153) gates for the steady
// first-note-anchored beat pulse.
//
// The proof tests replay REAL recorded sessions (FA #27 — never synthetic for
// claims about real-music behaviour): per-frame `bass/mid/treble` energy series
// extracted verbatim from `features.csv` of sessions whose first-note times
// were independently measured from the raw PCM (`raw_tap.wav`) by the FBS
// Stage 0 tools (`tools/fbs/measure_grid_phase.py`,
// docs/diagnostics/FBS_STAGE0_FINDINGS_2026-06-09.md):
//
//   - cherub_rock_2026-06-09T21-19-14Z_seg0.csv — Cherub Rock, clean local
//     signal, cached grid 171.3 BPM. PCM first note = 1.03 s.
//   - sz2_2026-06-09T13-06-15Z_seg0.csv — SZ2 (Battles), local, cached grid
//     85.9 BPM. PCM first note = 0.89 s.
//
// Stage 1 claims under test:
//   (a) ANCHOR — the pulse anchors at the track's first note (PCM-verified
//       time, ±60 ms).
//   (b) STEADY — the pulse never wanders: across the whole replay, every beat
//       interval equals the grid period exactly (sub-ms), unlike the live
//       drift tracker's 50–90 ms wander the Stage 0 findings measured.
//   (c) MOVES — the spike-height envelope the pulse drives has far more
//       motion than the frozen `0.8·f.bass` term it replaces.

import Foundation
import XCTest
@testable import DSP

// MARK: - BeatPulseClockTests

final class BeatPulseClockTests: XCTestCase {

    // MARK: - Fixture replay infrastructure

    private struct Frame {
        let trackElapsedS: Double
        let wallclockS: Double
        let deltaTime: Float
        let energySum: Float    // bass + mid + treble (AGC-normalised)
        let bass: Float
    }

    private func loadFixture(_ name: String) throws -> [Frame] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "fbs"),
            "\(name).csv missing from Fixtures/fbs — real-session replay fixture required (FA #27)"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        var frames: [Frame] = []
        for line in text.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: ",").map { Double($0) ?? 0 }
            guard cols.count >= 6 else { continue }
            frames.append(Frame(trackElapsedS: cols[0], wallclockS: cols[1],
                                deltaTime: Float(cols[2]),
                                energySum: Float(cols[3] + cols[4] + cols[5]),
                                bass: Float(cols[3])))
        }
        XCTAssertGreaterThan(frames.count, 500, "fixture suspiciously short")
        return frames
    }

    /// Index of the frame the clock anchored on: the FIRST frame of the first
    /// sustained-audible run (the clock backdates its anchor there; outputs
    /// show amp01 > 0 starting `anchorConfirmFrames - 1` frames later).
    private func anchorFrameIndex(_ outs: [BeatPulseClock.Output]) throws -> Int {
        let firstLive = try XCTUnwrap(outs.indices.first { outs[$0].amp01 > 0 },
                                      "pulse never became active on a music fixture")
        return max(0, firstLive - (BeatPulseClock.anchorConfirmFrames - 1))
    }

    /// Replay a fixture through the clock; returns per-frame outputs.
    private func replay(_ frames: [Frame], bpm: Double) -> [BeatPulseClock.Output] {
        let clock = BeatPulseClock()
        clock.setTempo(bpm: bpm)
        return frames.map {
            clock.update(energySum: $0.energySum, time: $0.trackElapsedS, deltaTime: $0.deltaTime)
        }
    }

    /// Times where phase wraps 1 → 0 (the pulse's beat instants), linearly
    /// interpolated between frames.
    private func wrapTimes(_ frames: [Frame], _ outs: [BeatPulseClock.Output]) -> [Double] {
        var wraps: [Double] = []
        for i in 1..<outs.count where outs[i].phase01 < outs[i - 1].phase01 - 0.3 {
            let prev = Double(outs[i - 1].phase01)
            let cur = Double(outs[i].phase01)
            let frac = (1.0 - prev) / max(1e-9, (1.0 - prev) + cur)
            let t0 = frames[i - 1].trackElapsedS
            wraps.append(t0 + frac * (frames[i].trackElapsedS - t0))
        }
        return wraps
    }

    // MARK: - (a) Anchor accuracy on real sessions (PCM-verified ground truth)

    /// The anchor must land on the track's first note as heard in the RAW PCM
    /// (`raw_tap.wav`), not merely on the analysis pipeline's own first frame.
    /// Cross-clock check: the anchor frame's wallclock, expressed in raw-tap
    /// time (wallclock − tap-start-wallclock from session.log), must equal the
    /// PCM-measured first-note time. On this purpose-recorded Cherub Rock
    /// session the two clocks agree to ~2 ms.
    func test_anchor_cherubRock_landsOnPCMFirstNote_crossClock() throws {
        let frames = try loadFixture("cherub_rock_2026-06-09T21-19-14Z_seg0")
        let outs = replay(frames, bpm: 171.3)
        let anchorIdx = try anchorFrameIndex(outs)
        // session.log: "raw tap capture started ... wallclock=802732769.5655"
        let tapStartWallclock = 802732769.5655
        // Stage 0 PCM measurement: sound begins at 1.03 s into raw_tap.wav.
        let pcmFirstNoteS = 1.03
        let anchorInRawTapTime = frames[anchorIdx].wallclockS - tapStartWallclock
        XCTAssertEqual(anchorInRawTapTime, pcmFirstNoteS, accuracy: 0.06,
                       "anchor must land on the track's first note as heard in the PCM")
    }

    /// SZ2 session (13-06-15Z): the session had an 18.3 s startup stall on
    /// frame 0, which bunched the early frames' wallclock stamps — the
    /// cross-clock PCM comparison is unverifiable on this fixture (verified
    /// directly: the PCM is digitally silent until 0.88 s, while the stalled
    /// frames' wallclocks sit ~0.86 s earlier than the audio they carry).
    /// What IS verifiable: the clock anchors exactly at the first
    /// sustained-audible frame of the series the pipeline actually saw —
    /// the operative anchor definition.
    func test_anchor_sz2_landsOnFirstAudibleFrame() throws {
        let frames = try loadFixture("sz2_2026-06-09T13-06-15Z_seg0")
        let outs = replay(frames, bpm: 85.9)
        let anchorIdx = try anchorFrameIndex(outs)
        let firstAudible = try XCTUnwrap(
            frames.indices.first { frames[$0].energySum > BeatPulseClock.audibleEnergyFloor })
        XCTAssertEqual(anchorIdx, firstAudible,
                       "anchor must be the first sustained-audible frame of the real series")
    }

    // MARK: - (b) Dead-steady: zero wander across the replay

    func test_pulse_holdsSteady_everyBeatIntervalEqualsGridPeriod() throws {
        for (name, bpm) in [("cherub_rock_2026-06-09T21-19-14Z_seg0", 171.3),
                            ("sz2_2026-06-09T13-06-15Z_seg0", 85.9)] {
            let frames = try loadFixture(name)
            let outs = replay(frames, bpm: bpm)
            let wraps = wrapTimes(frames, outs)
            XCTAssertGreaterThan(wraps.count, 10, "\(name): expected many beats in 25 s")
            let period = 60.0 / bpm
            // Every interval == one grid period. Tolerance 5 ms covers the
            // frame-boundary interpolation error at ~60 fps; the live drift
            // tracker moved 50–90 ms over the same window (Stage 0).
            for (a, b) in zip(wraps, wraps.dropFirst()) {
                XCTAssertEqual(b - a, period, accuracy: 0.005,
                               "\(name): pulse interval deviated — the pulse must NEVER wander")
            }
            // Cumulative: the LAST beat is exactly n periods from the FIRST.
            if let lo = wraps.first, let hi = wraps.last {
                let n = ((hi - lo) / period).rounded()
                XCTAssertEqual(hi - lo, n * period, accuracy: 0.005,
                               "\(name): cumulative drift across the opening must be ~0")
            }
        }
    }

    // MARK: - (c) The spike driver actually moves (vs the frozen f.bass term)

    private func envSeries(_ outs: [BeatPulseClock.Output]) -> [Float] {
        // Mirrors fo_spike_strength's Layer-2 term: head × amp × env(phase),
        // head = 0.62 (baseline 1.0 on cache-miss tracks).
        outs.map { out in
            let ph = out.phase01
            let attack = min(max(ph / 0.08, 0), 1)
            let dec = 1 - min(max((ph - 0.08) / (0.85 - 0.08), 0), 1)
            return 0.62 * out.amp01 * attack * dec
        }
    }

    private func std(_ xs: [Float]) -> Float {
        let m = xs.reduce(0, +) / Float(xs.count)
        return (xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(xs.count)).squareRoot()
    }

    /// THE frozen case: the streaming Lotus Flower session Matt reviewed as
    /// unresponsive. On it the old `0.8·f.bass` spike term barely moves (the
    /// auto-levelled bass is held near-constant by design) while the pulse
    /// envelope must deliver "performed best"-grade motion (the Mingus
    /// session, the kickoff's positive reference, measured std ~0.27).
    func test_pulseEnvelope_movesOnTheFrozenStreamingTrack() throws {
        let frames = try loadFixture("lotus_flower_2026-06-09T22-20-46Z")
        let outs = replay(frames, bpm: 128.0)
        let oldStd = std(frames.map { 0.8 * min(max($0.bass, 0), 1) })
        let newStd = std(envSeries(outs))
        XCTAssertLessThan(oldStd, 0.05,
                          "fixture sanity: this is the frozen case — the old term barely moves")
        XCTAssertGreaterThan(newStd, 0.15,
                             "pulse envelope must move the spike field (frozen was ~0.07 here)")
        XCTAssertGreaterThan(newStd, 4.0 * oldStd,
                             "pulse must out-move the frozen f.bass term by a wide margin")
    }

    /// Consistency across material: the pulse's motion must not collapse on
    /// any music type — bass-heavy local rock and bass-light streaming pop
    /// both get the same punch (the old term's motion varied 5× between them).
    func test_pulseEnvelope_motionIsConsistentAcrossMaterial() throws {
        let cherub = envSeries(replay(try loadFixture("cherub_rock_2026-06-09T21-19-14Z_seg0"),
                                      bpm: 171.3))
        let lotus = envSeries(replay(try loadFixture("lotus_flower_2026-06-09T22-20-46Z"),
                                     bpm: 128.0))
        XCTAssertGreaterThan(std(cherub), 0.15)
        XCTAssertGreaterThan(std(lotus), 0.15)
        XCTAssertLessThan(abs(std(cherub) - std(lotus)), 0.08,
                          "punch motion must be material-independent")
    }

    // MARK: - Behaviour gates (deterministic edge cases)

    func test_noTempo_pulseStaysSilent() {
        let clock = BeatPulseClock()          // no setTempo — reactive / no grid
        var out = BeatPulseClock.Output.zero
        for i in 0..<300 {
            out = clock.update(energySum: 0.5, time: Double(i) / 60.0, deltaTime: 1 / 60)
        }
        XCTAssertEqual(out.amp01, 0, accuracy: 1e-5, "no grid tempo → no pulse")
        XCTAssertEqual(out.phase01, 0, accuracy: 1e-5)
    }

    func test_silenceBeforeFirstNote_noPulse_andSingleSpuriousFrameDoesNotAnchor() {
        let clock = BeatPulseClock()
        clock.setTempo(bpm: 120)
        var t = 0.0
        // 2 s of true silence with one single-frame pop at 1.0 s.
        for i in 0..<120 {
            let pop: Float = (i == 60) ? 0.5 : 0.001
            let out = clock.update(energySum: pop, time: t, deltaTime: 1 / 60)
            XCTAssertEqual(out.amp01, 0, accuracy: 1e-4, "no pulse before the first sustained note")
            t += 1.0 / 60.0
        }
        // Music begins: anchor latches at the run's FIRST frame (backdated).
        let musicStart = t
        var lastPhaseZeroCrossDistance: Float = 1
        for _ in 0..<240 {
            let out = clock.update(energySum: 0.6, time: t, deltaTime: 1 / 60)
            let expected = Float(((t - musicStart) / 0.5).truncatingRemainder(dividingBy: 1.0))
            lastPhaseZeroCrossDistance = min(lastPhaseZeroCrossDistance, abs(out.phase01 - expected))
            t += 1.0 / 60.0
        }
        XCTAssertLessThan(lastPhaseZeroCrossDistance, 0.02,
                          "anchor must backdate to the audible run's first frame")
    }

    func test_sustainedSilence_fadesPulseOut_briefDipDoesNot() {
        let clock = BeatPulseClock()
        clock.setTempo(bpm: 120)
        var t = 0.0
        var out = BeatPulseClock.Output.zero
        for _ in 0..<240 {                                    // 4 s music
            out = clock.update(energySum: 0.6, time: t, deltaTime: 1 / 60); t += 1 / 60
        }
        XCTAssertGreaterThan(out.amp01, 0.95, "music playing → full pulse")
        for _ in 0..<18 {                                     // 0.3 s dip (between phrases)
            out = clock.update(energySum: 0.001, time: t, deltaTime: 1 / 60); t += 1 / 60
        }
        XCTAssertGreaterThan(out.amp01, 0.9, "a brief dip must NOT fade the pulse")
        for _ in 0..<120 {                                    // 2 s sustained silence
            out = clock.update(energySum: 0.001, time: t, deltaTime: 1 / 60); t += 1 / 60
        }
        XCTAssertLessThan(out.amp01, 0.05, "sustained silence → pulse fades out")
        for _ in 0..<60 {                                     // music returns
            out = clock.update(energySum: 0.6, time: t, deltaTime: 1 / 60); t += 1 / 60
        }
        XCTAssertGreaterThan(out.amp01, 0.9, "music back → pulse returns (same anchor, no re-anchor)")
    }

    func test_resetAnchor_clearsAnchorButKeepsTempo() {
        let clock = BeatPulseClock()
        clock.setTempo(bpm: 120)
        var t = 0.0
        for _ in 0..<120 { _ = clock.update(energySum: 0.6, time: t, deltaTime: 1 / 60); t += 1 / 60 }
        clock.resetAnchor()                                   // track change
        let silent = clock.update(energySum: 0.001, time: 0.0, deltaTime: 1 / 60)
        XCTAssertEqual(silent.amp01, 0, accuracy: 1e-4, "after reset: no anchor → no pulse")
        // New track's audio arrives — pulse re-anchors WITHOUT a new setTempo
        // call (tempo survives reset; setBeatGrid is the sole tempo authority).
        var t2 = 0.5
        var out = BeatPulseClock.Output.zero
        for _ in 0..<60 { out = clock.update(energySum: 0.6, time: t2, deltaTime: 1 / 60); t2 += 1 / 60 }
        XCTAssertGreaterThan(out.amp01, 0.5, "pulse re-anchors on the new track's first note")
    }
}
