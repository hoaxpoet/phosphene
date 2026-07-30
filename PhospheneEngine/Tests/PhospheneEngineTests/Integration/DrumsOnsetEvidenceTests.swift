// DrumsOnsetEvidenceTests — TRK.2 task 1: does the drums stem carry better beat
// evidence than sub-bass flux?
//
// BUG-065's root cause (TRK.1) is a period error the legacy proportional tracker
// cannot null. TRK.1's PI controller failed real-fixture validation because it
// integrates sub_bass onsets, which are *events, not beats* (FA #68). TRK.2's
// premise is that drums-stem onsets are better *evidence*. This test measures
// that premise instead of assuming it.
//
// For one capture it runs BOTH detectors — the production `BeatDetector` on the
// full mix (what the tracker consumes today) and a second detector instance on
// the drums stem produced by the production `StemSeparator` (D-075: a separate
// detector instance, not a fused band) — and prints each source's
// |offset-to-nearest-grid-beat| distribution against the same grid.
//
// DIAGNOSTIC ONLY. Env-gated (`PHOSPHENE_TRK2_EVIDENCE=1`) because a full run
// separates the whole capture through MPSGraph — ~1 s of GPU per 10 s of audio.
// It asserts nothing; the printed table is the artifact.
//
//   PHOSPHENE_TRK2_EVIDENCE=1 \
//   swift test --package-path PhospheneEngine --filter DrumsOnsetEvidence
//
// Overrides for replaying a recorded session instead of the bundled fixture:
//   PHOSPHENE_TRK2_AUDIO       audio file (default Fixtures/tempo/love_rehab.m4a)
//   PHOSPHENE_TRK2_BEATS       JSON `{"beats":[…]}` (default: analyze the audio)
//   PHOSPHENE_TRK2_GRID_OFFSET seconds added to the GRID's beat times to bring them
//                              into the audio's time base (e.g. a session's raw_tap.wav
//                              starts N s after track zero → pass −N)
//   PHOSPHENE_TRK2_SECONDS     analyse only the first N seconds
//   PHOSPHENE_TRK2_DUMP_DRUMS  write the separated drums stem (raw f32le mono 44.1 kHz)
//                              for cross-checking against a session's own stem dumps

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import ML
@testable import Session

@Suite("DrumsOnsetEvidence")
struct DrumsOnsetEvidenceTests {

    /// One source's alignment against the grid.
    ///
    /// Matching mirrors `GridOnsetCalibrator` (±200 ms), not the tracker's ±50 ms
    /// search window: the per-track grid-vs-detector bias is documented at ±50–150 ms
    /// and is *calibratable*, so scoring inside ±50 ms would just re-measure the bias.
    /// Every statistic below is therefore **bias-corrected** — offsets are reported
    /// relative to this source's own median, which is what BUG-007.8's
    /// `initialDriftMs` already removes in production.
    ///
    /// The BUG-065 ramp is common-mode: both sources ride the same wrong grid period.
    /// So the deciding number is `residualMAD` — spread about each source's own linear
    /// trend, i.e. the jitter no controller of any type can learn away.
    private struct Alignment {
        let label: String
        /// `(onsetTime, signed nearestBeat − onsetTime in ms)` within ±200 ms.
        let samples: [(t: Double, offMs: Double)]
        let onsetCount: Int

        var matchedCount: Int { samples.count }
        /// Calibratable per-track bias (BUG-007.8 `gridOnsetOffsetMs`).
        var biasMs: Double { Self.percentile(samples.map(\.offMs), 0.50) }
        /// Bias-corrected offsets — the evidence the tracker actually has to work with.
        var corrected: [(t: Double, offMs: Double)] {
            let bias = biasMs
            return samples.map { ($0.t, $0.offMs - bias) }
        }
        /// Fraction of ALL onsets that land inside the tracker's ±50 ms search
        /// window once the bias is calibrated out.
        var searchRate: Double {
            onsetCount > 0
                ? Double(corrected.filter { abs($0.offMs) < 50 }.count) / Double(onsetCount) : 0
        }
        /// Fraction inside the tracker's ±30 ms tight gate, bias-corrected.
        var tightRate: Double {
            onsetCount > 0
                ? Double(corrected.filter { abs($0.offMs) < 30 }.count) / Double(onsetCount) : 0
        }
        var madMs: Double { Self.percentile(corrected.map { abs($0.offMs) }, 0.50) }
        /// Linear fit of bias-corrected offset against time: (slope ms/s, R²).
        var trend: (slopeMsPerS: Double, r2: Double) { Self.linearFit(corrected) }
        /// MAD of the residual about that linear fit — the evidence-quality number.
        var residualMADMs: Double {
            let points = corrected
            let fit = Self.fitCoefficients(points)
            let residuals = points.map { $0.offMs - (fit.slope * $0.t + fit.intercept) }
            let med = Self.percentile(residuals, 0.50)
            return Self.percentile(residuals.map { abs($0 - med) }, 0.50)
        }

        static func percentile(_ values: [Double], _ q: Double) -> Double {
            guard !values.isEmpty else { return .nan }
            let sorted = values.sorted()
            let idx = min(sorted.count - 1, max(0, Int(q * Double(sorted.count - 1) + 0.5)))
            return sorted[idx]
        }

        static func fitCoefficients(_ s: [(t: Double, offMs: Double)]) -> (slope: Double, intercept: Double) {
            guard s.count >= 2 else { return (0, s.first?.offMs ?? 0) }
            let n = Double(s.count)
            let meanT = s.reduce(0) { $0 + $1.t } / n
            let meanY = s.reduce(0) { $0 + $1.offMs } / n
            var sxy = 0.0, sxx = 0.0
            for p in s { sxy += (p.t - meanT) * (p.offMs - meanY); sxx += (p.t - meanT) * (p.t - meanT) }
            let slope = sxx > 0 ? sxy / sxx : 0
            return (slope, meanY - slope * meanT)
        }

        static func linearFit(_ s: [(t: Double, offMs: Double)]) -> (slopeMsPerS: Double, r2: Double) {
            guard s.count >= 2 else { return (0, 0) }
            let fit = fitCoefficients(s)
            let n = Double(s.count)
            let meanY = s.reduce(0) { $0 + $1.offMs } / n
            var ssRes = 0.0, ssTot = 0.0
            for p in s {
                let pred = fit.slope * p.t + fit.intercept
                ssRes += (p.offMs - pred) * (p.offMs - pred)
                ssTot += (p.offMs - meanY) * (p.offMs - meanY)
            }
            return (fit.slope, ssTot > 0 ? 1 - ssRes / ssTot : 0)
        }
    }

    @Test("TRK.2 evidence: sub-bass vs drums-stem onset alignment to the cached grid")
    func test_subBassVsDrumsStemOnsetAlignment() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_TRK2_EVIDENCE"] == "1" else {
            print("[TRK.2] skipped — set PHOSPHENE_TRK2_EVIDENCE=1 to run (slow: full-capture stem separation)")
            return
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("no Metal device")
            return
        }
        let env = ProcessInfo.processInfo.environment
        let sampleRate: Double = 44100

        let audioURL = env["PHOSPHENE_TRK2_AUDIO"].map { URL(fileURLWithPath: $0) } ?? Self.defaultFixtureURL()
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Issue.record("audio missing at \(audioURL.path)")
            return
        }
        let gridOffset = env["PHOSPHENE_TRK2_GRID_OFFSET"].flatMap(Double.init) ?? 0

        // Stereo for the separator (the live path separates the stereo tap);
        // mono for the full-mix detector (what MIRPipeline analyses).
        let limitS = env["PHOSPHENE_TRK2_SECONDS"].flatMap(Double.init)
        let stereo = try Self.decode(url: audioURL, channels: 2, sampleRate: Int(sampleRate), seconds: limitS)
        var mono = [Float](repeating: 0, count: stereo.count / 2)
        for i in 0..<mono.count { mono[i] = (stereo[i * 2] + stereo[i * 2 + 1]) * 0.5 }
        let durationS = Double(mono.count) / sampleRate

        // Grid: supplied beats, or the production offline analyzer on this audio.
        // `offsetBy` also extrapolates forward, exactly as the live install path does.
        let baseGrid: BeatGrid
        if let beatsPath = env["PHOSPHENE_TRK2_BEATS"] {
            baseGrid = try Self.loadGrid(path: beatsPath)
        } else {
            baseGrid = try DefaultBeatGridAnalyzer(device: device)
                .analyzeBeatGrid(samples: mono, sampleRate: sampleRate)
        }
        guard !baseGrid.beats.isEmpty else {
            Issue.record("empty grid — nothing to align against")
            return
        }
        let grid = baseGrid.offsetBy(gridOffset, horizon: durationS + 60)

        // Drums stem for the whole capture: tile the audio into the separator's
        // fixed ~10 s window and concatenate. Non-overlapping tiling keeps the
        // output sample-aligned with the input, so onset times stay in audio time.
        let drums = try Self.separateDrums(stereo: stereo, sampleRate: Float(sampleRate), device: device)

        // Escape hatch for verifying this offline separation against the live path's
        // own stem dumps (session `stems/NNNN_<track>/drums.wav`).
        if let dumpPath = env["PHOSPHENE_TRK2_DUMP_DRUMS"] {
            try Data(bytes: drums, count: drums.count * 4).write(to: URL(fileURLWithPath: dumpPath))
            print("[TRK.2] drums stem written (raw f32le mono 44100) → \(dumpPath)")
        }

        let fft = try FFTProcessor(device: device)
        // Every band of the drums stem, not just sub_bass — the premise is that the
        // drums stem "carries the actual pulse", and on most kits that pulse is split
        // between kick (sub_bass) and snare (low/mid). Testing one band would leave the
        // "you measured the wrong band" objection open.
        var rows = [Self.align("full-mix sub_bass (today)",
                               Self.onsetTimes(mono: mono, fft: fft, sampleRate: sampleRate, band: 0),
                               grid)]
        for (idx, name) in Self.bandNames.enumerated() {
            rows.append(Self.align("drums-stem \(name)",
                                   Self.onsetTimes(mono: drums, fft: fft, sampleRate: sampleRate, band: idx),
                                   grid))
        }
        rows.append(Self.align("drums-stem any-band*",
                               Self.onsetTimes(mono: drums, fft: fft, sampleRate: sampleRate, band: nil),
                               grid))

        print("""

        ================ TRK.2 task 1 — onset alignment to the cached grid ================
        audio      : \(audioURL.lastPathComponent) (\(String(format: "%.1f", durationS)) s)
        grid       : \(grid.beats.count) beats, \(String(format: "%.2f", grid.bpm)) BPM, \
        offset \(String(format: "%+.3f", gridOffset)) s
        stem check : RMS mix \(String(format: "%.4f", Self.rms(mono))) → \
        drums \(String(format: "%.4f", Self.rms(drums))) \
        (ratio \(String(format: "%.2f", Self.rms(drums) / max(Self.rms(mono), 1e-9))))
        offsets    : signed (nearestBeat − onset), matched within ±200 ms, BIAS-CORRECTED
        \(String(repeating: "-", count: 96))
        \(Self.header())
        """)
        for row in rows { print(Self.format(row)) }
        let period = grid.bpm > 0 ? 60.0 / grid.bpm : 0.5
        print(String(repeating: "-", count: 96))
        print(Self.pad("onset position within the beat cycle (bin 0 = on the beat)", 26) + " ")
        for row in rows { print(Self.phaseHistogram(row, period: period)) }
        print("""
        \(String(repeating: "-", count: 96))
        * any-band is DIAGNOSTIC ONLY — a fused-band detector is not a candidate
          evidence source (D-075). The TRK.2 candidate is drums-stem sub_bass.
        match     : onsets within ±200 ms of a beat — the calibratable population.
        bias      : per-track grid-vs-detector offset (BUG-007.8 already removes this).
        ±50/±30   : share of ALL onsets that would be usable / tight evidence after
                    calibration. Higher is better; this is the evidence yield.
        slope/R²  : the BUG-065 clock ramp, per source. Agreement across sources
                    confirms it is the grid's period error, not a detector artifact.
        resid MAD : spread about each source's own trend — the jitter an integrating
                    controller CANNOT learn away. THIS is the TRK.2 premise test.
        ================================================================================

        """)
    }

    // MARK: - Measurement

    /// `BeatDetector.Result.onsets` band order.
    private static let bandNames = ["sub_bass", "low_bass", "low_mid", "mid_high", "high_mid", "high"]

    private static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    private static func header() -> String {
        pad("source", 26) + String(format: "%7@ %7@ %7@ %7@ %8@ %9@ %6@ %9@",
                                   "onsets" as NSString, "match" as NSString, "±50ms" as NSString,
                                   "±30ms" as NSString, "bias ms" as NSString, "slope/s" as NSString,
                                   "R²" as NSString, "resid MAD" as NSString)
    }

    private static func format(_ a: Alignment) -> String {
        let trend = a.trend
        return pad(a.label, 26) + String(format: "%7d %7d %6.1f%% %6.1f%% %+8.1f %+9.3f %6.3f %9.1f",
                                         a.onsetCount, a.matchedCount,
                                         a.searchRate * 100, a.tightRate * 100,
                                         a.biasMs, trend.slopeMsPerS, trend.r2,
                                         a.residualMADMs)
    }

    /// Where in the beat cycle each onset lands, 12 bins from beat 0 to the next
    /// beat. Real beat evidence piles up in the first and last bins; `events, not
    /// beats` (FA #68) spreads flat. This is the shape the summary stats compress.
    private static func phaseHistogram(_ a: Alignment, period: Double) -> String {
        var bins = [Int](repeating: 0, count: 12)
        for sample in a.corrected {
            // offMs > 0 ⇒ the beat is ahead of the onset ⇒ onset sits late in the
            // PREVIOUS beat's cycle. Fold onto [0, 1) of a beat cycle.
            var phase = -sample.offMs / 1000.0 / period
            phase -= floor(phase)
            bins[min(11, Int(phase * 12))] += 1
        }
        let peak = max(bins.max() ?? 1, 1)
        let blocks = bins.map { count -> String in
            let level = Int((Double(count) / Double(peak)) * 8.0 + 0.5)
            return [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"][min(8, level)]
        }.joined()
        return pad(a.label, 26) + "|" + blocks + "|  peak bin \(bins.firstIndex(of: peak) ?? 0)/12"
    }

    private static func align(_ label: String, _ onsets: [Double], _ grid: BeatGrid) -> Alignment {
        // ±200 ms — GridOnsetCalibrator's `maxMatchWindow`.
        var samples: [(t: Double, offMs: Double)] = []
        for onset in onsets {
            guard let nearest = grid.nearestBeat(to: onset, within: 0.200) else { continue }
            samples.append((onset, (nearest - onset) * 1000))
        }
        return Alignment(label: label, samples: samples, onsetCount: onsets.count)
    }

    /// Onset times (seconds) from the production `BeatDetector` driven at the real
    /// FFT-hop cadence. `band` picks one of the six bands; nil ORs all of them.
    private static func onsetTimes(mono: [Float], fft: FFTProcessor,
                                   sampleRate: Double, band: Int?) -> [Double] {
        let hop = FFTProcessor.fftSize
        let dt = Float(hop) / Float(sampleRate)
        let detector = BeatDetector(binCount: FFTProcessor.binCount,
                                    sampleRate: Float(sampleRate),
                                    fftSize: hop)
        var magnitudes = [Float](repeating: 0, count: FFTProcessor.binCount)
        var times: [Double] = []
        var chunk = 0
        while (chunk + 1) * hop <= mono.count {
            let frame = Array(mono[(chunk * hop)..<((chunk + 1) * hop)])
            _ = fft.process(samples: frame, sampleRate: Float(sampleRate))
            for bin in 0..<FFTProcessor.binCount { magnitudes[bin] = fft.magnitudeBuffer[bin] }
            let result = detector.process(magnitudes: magnitudes, fps: 1.0 / dt, deltaTime: dt)
            let fired = band.map { result.onsets.indices.contains($0) && result.onsets[$0] }
                ?? result.onsets.contains(true)
            if fired { times.append(Double(chunk * hop) / sampleRate) }
            chunk += 1
        }
        return times
    }

    /// Run the production separator over the whole capture and return the drums
    /// stem as one mono waveform in the input's time base.
    private static func separateDrums(stereo: [Float], sampleRate: Float,
                                      device: MTLDevice) throws -> [Float] {
        let separator = try StemSeparator(device: device)
        let chunkMono = StemSeparator.requiredMonoSamples
        let totalMono = stereo.count / 2
        var drums: [Float] = []
        drums.reserveCapacity(totalMono)
        var start = 0
        while start < totalMono {
            let end = min(start + chunkMono, totalMono)
            guard end - start >= StemSeparator.hopLength else { break }
            let slice = Array(stereo[(start * 2)..<(end * 2)])
            let result = try separator.separate(audio: slice, channelCount: 2, sampleRate: sampleRate)
            let stem = result.stemWaveforms.count > 1 ? result.stemWaveforms[1] : []
            drums.append(contentsOf: stem.prefix(end - start))
            start = end
        }
        // Pad any short tail so drums stays sample-aligned with the input.
        if drums.count < totalMono { drums.append(contentsOf: [Float](repeating: 0, count: totalMono - drums.count)) }
        return drums
    }

    // MARK: - Fixtures

    private static func defaultFixtureURL() -> URL {
        URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()   // Integration/
            .deletingLastPathComponent()   // PhospheneEngineTests/
            .deletingLastPathComponent()   // Tests/
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
    }

    private struct GridJSON: Decodable {
        let beats: [Double]
        let downbeats: [Double]?
        let bpm: Double?
        let beatsPerBar: Int?
    }

    private static func loadGrid(path: String) throws -> BeatGrid {
        let json = try JSONDecoder().decode(GridJSON.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return BeatGrid(beats: json.beats,
                        downbeats: json.downbeats ?? [],
                        bpm: json.bpm ?? 0,
                        beatsPerBar: json.beatsPerBar ?? 4,
                        barConfidence: 1,
                        frameRate: 50,
                        frameCount: 0)
    }

    /// Decode any audio file to interleaved Float32 at the requested rate/channels.
    private static func decode(url: URL, channels: Int, sampleRate: Int,
                               seconds: Double? = nil) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = ["ffmpeg", "-loglevel", "error", "-i", url.path]
        if let seconds { args += ["-t", "\(seconds)"] }
        args += ["-ac", "\(channels)", "-ar", "\(sampleRate)", "-f", "f32le", "-"]
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()
        // Drain concurrently — a whole capture overruns the 64 KB pipe buffer.
        var raw = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            raw.append(chunk)
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "DrumsOnsetEvidence", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ffmpeg decode failed for \(url.path)"])
        }
        return raw.withUnsafeBytes { buf in
            let typed = buf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed.baseAddress, count: raw.count / 4))
        }
    }
}
