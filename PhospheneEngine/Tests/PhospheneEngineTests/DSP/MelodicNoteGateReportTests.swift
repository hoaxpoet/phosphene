// MelodicNoteGateReportTests — FTR.6: does the refractory gate actually reach the note rate?
//
// Same discipline as `TrunkTrajectoryReportTests`, and for the same reason: every previous
// round of this preset's tip behaviour was validated against something that was not the
// engine, and each one shipped a rate Matt rejected on sight. So this runs the REAL
// `MIRPipeline` — the same object the live app calls, including the real `BeatDetector`
// that produces `beat_mid` and the real `MelodicNoteGate` hanging off it — frame by frame
// over a fully decoded track, and reports the branch count the object shader would compute.
// No CSV, no proxy, no hand-authored envelope (FA #27).
//
//   FTR_AUDIO_DIR="/Volumes/Extreme SSD/S/Smashing Pumpkins/[1993] - Siamese Dream" \
//     swift test --package-path PhospheneEngine --filter MelodicNoteGateReport
//
// WHAT IS AND IS NOT GATED HERE. The object shader multiplies the tips term by `amp`
// (`pulse_amp01`) and by `smoothstep(0, 0.35, reach)` (`arousal`). Neither is available
// offline — `arousal` is an ML-module output that `MIRPipeline` leaves at 0, and
// `pulse_amp01` needs an installed `BeatGrid`. Both gates only ever REDUCE the tip count,
// so the ungated term measured here is the upper bound on activity: if it meets the rate
// target ungated, it meets it live. Stated rather than quietly assumed.

import Testing
import Foundation
import AVFoundation
@testable import Audio
@testable import DSP
@testable import Shared

@Suite("Melodic note gate report (FTR.6)")
struct MelodicNoteGateReportTests {

    private static let fftSize = 1024

    /// The two tracks FTR.5 certifies on: *Hummer* is bass-dominant (the friendliest case
    /// for the old design, the harshest for a mid-band trigger) and *Cherub Rock* is the
    /// mid-rich capture every FTR.3 measurement was taken against.
    private static let tracks = ["04 Hummer.mp3", "01 Cherub Rock.mp3"]

    // MARK: - Decode

    private static func decodeMono(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return ([], 0)
        }
        try file.read(into: buffer)
        let count = Int(buffer.frameLength)
        guard count > 0, let channels = buffer.floatChannelData else { return ([], 0) }
        let channelCount = Int(format.channelCount)
        if channelCount == 1 {
            return (Array(UnsafeBufferPointer(start: channels[0], count: count)), format.sampleRate)
        }
        var mono = [Float](repeating: 0, count: count)
        let scale = 1.0 / Float(channelCount)
        for channel in 0..<channelCount {
            let pointer = UnsafeBufferPointer(start: channels[channel], count: count)
            for index in 0..<count { mono[index] += pointer[index] * scale }
        }
        return (mono, format.sampleRate)
    }

    // MARK: - Per-track run

    private struct Run {
        var beatMid: [Float] = []
        var tips: [Float] = []
        var duration: Double = 0
        var bpm: Float = 0
    }

    /// Run the production pipeline over a decoded track, hop 1024 — the same hop
    /// `SessionPreparer+Analysis` uses for offline preparation.
    private static func run(url: URL) throws -> Run {
        let (samples, sampleRate) = try decodeMono(url)
        guard !samples.isEmpty else { return Run() }

        let pipeline = MIRPipeline(binCount: fftSize / 2,
                                   sampleRate: Float(sampleRate),
                                   fftSize: fftSize)
        let fft = try FFTMagnitudeKernel(fftSize: fftSize)
        let fps = Float(sampleRate) / Float(fftSize)
        let deltaTime = Float(fftSize) / Float(sampleRate)

        var out = Run()
        var offset = 0
        var time: Float = 0
        while offset + fftSize <= samples.count {
            samples.withUnsafeBufferPointer { src in
                fft.windowed.withUnsafeMutableBufferPointer { dst in
                    guard let s = src.baseAddress, let d = dst.baseAddress else { return }
                    d.update(from: s.advanced(by: offset), count: fftSize)
                }
            }
            fft.computeMagnitudes()
            let fv = pipeline.process(magnitudes: fft.magnitudes,
                                      fps: fps, time: time, deltaTime: deltaTime)
            out.beatMid.append(fv.beatMid)
            out.tips.append(fv.melodicTips)
            offset += fftSize
            time += deltaTime
        }
        out.duration = Double(samples.count) / sampleRate
        out.bpm = pipeline.stableBPM ?? 0
        return out
    }

    // MARK: - Metrics

    /// Integer-count change rate and mean absolute jump — the two numbers Matt's feedback
    /// is about. `truncate` mirrors the shader's `(uint)` cast exactly.
    private static func stepMetrics(_ series: [Float], duration: Double) -> (rate: Double, meanJump: Double) {
        let counts = series.map { Int(max($0, 0)) }
        var jumps: [Int] = []
        for (a, b) in zip(counts, counts.dropFirst()) where a != b { jumps.append(abs(b - a)) }
        guard !jumps.isEmpty, duration > 0 else { return (0, 0) }
        return (Double(jumps.count) / duration,
                Double(jumps.reduce(0, +)) / Double(jumps.count))
    }

    /// The FTR.3e formula this increment replaces: `melody * 26`, where
    /// `melody = beat_mid / (beat_mid + 2.2)`. Kept here so the before/after is measured
    /// on identical audio in the same run rather than quoted from a prior session.
    private static func legacyTips(_ beatMid: [Float]) -> [Float] {
        beatMid.map { ($0 / ($0 + 2.2)) * 26.0 }
    }

    /// Re-runs only the gate over an already-captured `beat_mid` series at a different
    /// trigger level or drain constant. These sweeps are the evidence behind both
    /// coefficients in `MelodicNoteGate`.
    private struct Sweep {
        var events = 0.0
        var meanTips = 0.0
        /// Fraction of frames sitting above the trigger level. If this is high the
        /// REFRACTORY is what limits the rate, not the music — the gate becomes a
        /// metronome that ticks whether or not a note was played.
        var duty = 0.0
        /// Share of events that fired on the first frame the refractory expired. 1.0 means
        /// fully metronomic; low means the music is choosing the moments.
        var refractoryLimited = 0.0
        /// Coefficient of variation of the per-10 s event rate. A metronome is ~0; a gate
        /// following the music varies with the arrangement.
        var rateCV = 0.0
    }

    private static func sweep(_ beatMid: [Float], level: Float, bpm: Float, tau: Float,
                              deltaTime: Float, duration: Double) -> Sweep {
        var secondsSinceEvent = Float.greatestFiniteMagnitude
        var tips: Float = 0
        var events = 0
        var limited = 0
        var above = 0
        var sum = 0.0
        let refractory = bpm > 0
            ? min(max(30 / bpm, MelodicNoteGate.refractoryBounds.lowerBound),
                  MelodicNoteGate.refractoryBounds.upperBound)
            : MelodicNoteGate.defaultRefractory
        let windowFrames = max(Int(10.0 / Double(deltaTime)), 1)
        var windowCounts: [Int] = []
        var windowEvents = 0
        for (index, value) in beatMid.enumerated() {
            secondsSinceEvent += deltaTime
            tips *= exp(-deltaTime / tau)
            if value >= level { above += 1 }
            if value >= level && secondsSinceEvent >= refractory {
                // Was the music ready and only the clock holding it back?
                if secondsSinceEvent < refractory + deltaTime * 1.5 { limited += 1 }
                tips = min(tips + 1, MelodicNoteGate.maxTips)
                secondsSinceEvent = 0
                events += 1
                windowEvents += 1
            }
            sum += Double(tips)
            if (index + 1) % windowFrames == 0 { windowCounts.append(windowEvents); windowEvents = 0 }
        }
        guard duration > 0, !beatMid.isEmpty else { return Sweep() }
        var out = Sweep()
        out.events = Double(events) / duration
        out.meanTips = sum / Double(beatMid.count)
        out.duty = Double(above) / Double(beatMid.count)
        out.refractoryLimited = events > 0 ? Double(limited) / Double(events) : 0
        if windowCounts.count > 1 {
            let mean = Double(windowCounts.reduce(0, +)) / Double(windowCounts.count)
            let variance = windowCounts
                .map { pow(Double($0) - mean, 2) }
                .reduce(0, +) / Double(windowCounts.count)
            out.rateCV = mean > 0 ? variance.squareRoot() / mean : 0
        }
        return out
    }

    // MARK: - Mechanism (runs everywhere, no audio needed)

    /// The report above is the evidence, but it only runs where the source MP3s are
    /// mounted. These three are the load-bearing behaviours, gated unconditionally so a
    /// later refactor cannot quietly turn the gate back into a pass-through.
    @Test("the refractory is what limits the rate")
    func refractorySuppressesRetrigger() {
        var gate = MelodicNoteGate()
        let deltaTime: Float = 1.0 / 60.0
        // A pulse held permanently above the trigger — the worst case, and close to what
        // `beat_mid` actually does at a low trigger level (duty 0.61 at level 0.25).
        var events = 0
        var previous: Float = 0
        for _ in 0..<600 {   // 10 s
            let tips = gate.update(beatMid: 1.0, bpm: 120, deltaTime: deltaTime)
            if tips > previous { events += 1 }
            previous = tips
        }
        // 120 BPM → eighth note 0.25 s → at most 4 events a second, however loud the input.
        #expect(events <= 41, "\(events) events in 10 s; the eighth note at 120 BPM caps it at 40")
        #expect(events >= 38, "\(events) events in 10 s; a permanently-open input should reach the cap")

        // Silence drains the canopy back to the rest tree (D-037: the sparse figure, not
        // a canopy left standing from the last chorus). 30 s is ~12 drain constants.
        for _ in 0..<1800 { _ = gate.update(beatMid: 0, bpm: 120, deltaTime: deltaTime) }
        #expect(gate.update(beatMid: 0, bpm: 120, deltaTime: deltaTime) < 0.01)
    }

    @Test("the refractory scales with tempo, and survives a missing one")
    func refractoryTracksTempo() {
        func events(bpm: Float) -> Int {
            var gate = MelodicNoteGate()
            var count = 0
            var previous: Float = 0
            for _ in 0..<600 {
                let tips = gate.update(beatMid: 1.0, bpm: bpm, deltaTime: 1.0 / 60.0)
                if tips > previous { count += 1 }
                previous = tips
            }
            return count
        }
        // Faster track, shorter eighth note, more tips allowed — the point of deriving the
        // interval from tempo rather than fixing it in seconds.
        #expect(events(bpm: 180) > events(bpm: 90))
        // No tempo yet (cold start): the 120 BPM default, not an open gate.
        #expect(abs(events(bpm: 0) - events(bpm: 120)) <= 1)
        // A nonsense estimate cannot open the gate to every frame.
        #expect(events(bpm: 600) <= 68, "clamped at the 0.15 s bound → ≤ 67 events in 10 s")
    }

    @Test("a track change carries nothing across")
    func resetClearsState() {
        var gate = MelodicNoteGate()
        for _ in 0..<300 { _ = gate.update(beatMid: 1.0, bpm: 120, deltaTime: 1.0 / 60.0) }
        #expect(gate.update(beatMid: 0, bpm: 120, deltaTime: 1.0 / 60.0) > 1)
        gate.reset()
        // Zero tips, and the refractory expired — the first note of the new track fires
        // immediately instead of waiting out the previous track's clock.
        #expect(gate.update(beatMid: 1.0, bpm: 120, deltaTime: 1.0 / 60.0) == 1)
    }

    // MARK: - Fixture regeneration (FTR.6)

    /// Backfills `melodic_tips` onto the three `route_coverage` fixtures.
    ///
    /// The fixtures predate this column, and QG.1 fails a route whose column is absent
    /// ("not recorded") — correctly, since it cannot tell a missing column from a dead
    /// route. Re-capturing them is not an option (they are checked-in recordings of real
    /// preview clips), but the column does not need re-capturing: the gate is a pure
    /// function of `beatMid`, `grid_bpm` and `deltaTime`, all three of which the fixtures
    /// already carry. So this replays the PRODUCTION `MelodicNoteGate` over them — the same
    /// object `MIRPipeline` calls — rather than reimplementing its arithmetic anywhere.
    /// That is the whole reason this lives here and not in a shell script.
    ///
    ///   FTR_REGEN_FIXTURES=1 swift test --package-path PhospheneEngine \
    ///     --filter MelodicNoteGateReport
    @Test("regenerate the route_coverage melodic_tips column (FTR_REGEN_FIXTURES=1)")
    func regenerateFixtures() throws {
        guard ProcessInfo.processInfo.environment["FTR_REGEN_FIXTURES"] == "1" else { return }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // DSP
            .deletingLastPathComponent()      // PhospheneEngineTests
            .appendingPathComponent("Fixtures/route_coverage")

        for track in ["love_rehab", "so_what", "there_there"] {
            let url = root.appendingPathComponent(track).appendingPathComponent("features.csv")
            var lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            guard let header = lines.first else { continue }
            let names = header.components(separatedBy: ",")
            guard !names.contains("melodic_tips") else {
                print("  \(track): already has melodic_tips — skipped")
                continue
            }
            guard let dtCol = names.firstIndex(of: "deltaTime"),
                  let midCol = names.firstIndex(of: "beatMid"),
                  let bpmCol = names.firstIndex(of: "grid_bpm") else {
                Issue.record("\(track): fixture lacks the gate's inputs")
                continue
            }
            lines[0] = header + ",melodic_tips"
            var gate = MelodicNoteGate()
            for index in 1..<lines.count where !lines[index].isEmpty {
                let cells = lines[index].components(separatedBy: ",")
                guard cells.count > max(dtCol, midCol, bpmCol) else { continue }
                let tips = gate.update(beatMid: Float(cells[midCol]) ?? 0,
                                       bpm: Float(cells[bpmCol]) ?? 0,
                                       deltaTime: Float(cells[dtCol]) ?? 0)
                lines[index] += String(format: ",%.3f", tips)
            }
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            print("  \(track): melodic_tips written (\(lines.count - 1) rows)")
        }
    }

    // MARK: - Report

    @Test("one tip per note: rate and granularity on the Siamese Dream sources")
    func reportNoteGate() throws {
        guard let dir = ProcessInfo.processInfo.environment["FTR_AUDIO_DIR"] else { return }
        let base = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)

        for name in Self.tracks {
            let url = base.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                Issue.record("missing source track \(url.path)")
                continue
            }
            let result = try Self.run(url: url)
            guard !result.tips.isEmpty else {
                Issue.record("decoded no frames from \(name)")
                continue
            }
            let deltaTime = Float(result.duration / Double(result.tips.count))
            let gated = Self.stepMetrics(result.tips, duration: result.duration)
            let legacy = Self.stepMetrics(Self.legacyTips(result.beatMid), duration: result.duration)
            // How often `beat_mid` is available to trigger at all — the 6.9/s ceiling the
            // shader could never get under.
            let crossings = zip(result.beatMid, result.beatMid.dropFirst())
                .filter { $0 < MelodicNoteGate.triggerLevel && $1 >= MelodicNoteGate.triggerLevel }
                .count
            let crossingRate = Double(crossings) / result.duration

            let meanTips = result.tips.map(Double.init).reduce(0, +) / Double(result.tips.count)
            // NOTE EVENTS, read straight off the production series: the accumulator only
            // ever rises on an event and only ever falls on the drain, so a rise IS an
            // event. This is the number Matt's "one tip per note" is about — distinct from
            // the count-transition rate above, which also counts each tip's departure.
            let noteEvents = zip(result.tips, result.tips.dropFirst()).filter { $1 > $0 }.count
            let noteRate = Double(noteEvents) / result.duration
            print("\n── MELODIC NOTE GATE ──────────────────────────────────────────────")
            print(String(format: "file            %@   %.1fs   stableBPM %.1f",
                         name as NSString, result.duration, result.bpm))
            print(String(format: "beat_mid        crosses %.2f/s at level %.2f",
                         crossingRate, MelodicNoteGate.triggerLevel))
            print(String(format: "NOTE EVENTS     %.2f/s   (target ~3/s; guitar note rate 3.29/s)",
                         noteRate))
            print(String(format: "BEFORE (FTR.3e) %.2f count-changes/s, mean jump %.2f branches",
                         legacy.rate, legacy.meanJump))
            print(String(format: "AFTER  (FTR.6)  %.2f count-changes/s, mean jump %.2f branches",
                         gated.rate, gated.meanJump))
            print(String(format: "tip count       %.2f mean of %.0f max  (route saturation %.0f %%)",
                         meanTips, Double(MelodicNoteGate.maxTips),
                         100 * meanTips / Double(MelodicNoteGate.maxTips)))
            print("  level   events/s  meanTips  duty  refrac-limited  rateCV")
            for level in [Float(0.25), 0.55, 0.75, 0.85, 0.92, 0.96, 0.99] {
                let swept = Self.sweep(result.beatMid, level: level, bpm: result.bpm,
                                       tau: MelodicNoteGate.drainTau,
                                       deltaTime: deltaTime, duration: result.duration)
                print(String(format: "  %5.2f   %6.2f    %5.2f    %.2f      %.2f          %.2f",
                             level, swept.events, swept.meanTips, swept.duty,
                             swept.refractoryLimited, swept.rateCV))
            }
            print("  drain-tau sweep at the chosen level (mean tips out of \(Int(MelodicNoteGate.maxTips))):")
            for tau in [Float(0.5), 0.75, 1.0, 1.5, 2.0] {
                let swept = Self.sweep(result.beatMid, level: MelodicNoteGate.triggerLevel,
                                       bpm: result.bpm, tau: tau,
                                       deltaTime: deltaTime, duration: result.duration)
                print(String(format: "    tau %.2f s   %.2f tips", tau, swept.meanTips))
            }
            print("───────────────────────────────────────────────────────────────────\n")

            // GRANULARITY. This is the claim the mechanism makes structurally: a unit
            // accumulator with a continuous drain cannot move more than one integer step
            // per frame. If this ever fails, the accumulator has been changed into
            // something else.
            #expect(gated.meanJump <= 1.0, """
                \(name): the tips jump \(gated.meanJump) branches per change. FTR.3e measured \
                4.6 and Matt called it "too active"; one branch per note is the whole point.
                """)
            // NOTE RATE. Bounded on both sides. The upper bound is Matt's complaint; the
            // lower bound catches a gate that "passes" by firing almost never — a still
            // canopy would satisfy "not too active" and fail the preset just as badly.
            #expect(noteRate > 2.0 && noteRate < 4.5, """
                \(name): the gate fires \(noteRate) note events a second, against a measured \
                guitar note rate of 3.29/s.
                """)
            // The gate must be a REDUCTION, not a re-parameterisation.
            #expect(gated.rate < legacy.rate, "\(name): the gate did not reduce the rate")
            // ROUTE SATURATION. A tips term pinned near its ceiling stops carrying
            // information — the FTR.2 "pinned at 63" defect in a smaller register. Keep it
            // in the band where a dense passage can still climb and a sparse one can drop.
            #expect(meanTips > 0.15 * Double(MelodicNoteGate.maxTips)
                    && meanTips < 0.65 * Double(MelodicNoteGate.maxTips), """
                \(name): the tips sit at \(meanTips) of \(MelodicNoteGate.maxTips) on average. \
                A route that lives against its ceiling expresses nothing.
                """)
        }
    }
}
