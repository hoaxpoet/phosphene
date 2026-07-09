// DumperCore — the AVFoundation/DSP-bound half of TonalDumper: decode, the
// production MIRPipeline loop, manifest reading, and output formatting. Split
// from Dumper.swift so the command struct stays small; the pure math is in
// TonalStats (unit-tested).

import ArgumentParser
import Audio
import AVFoundation
import DSP
import Foundation

// MARK: - Manifest

/// One manifest row we care about (the pilot CSV has 15 columns; we use two).
struct ManifestRow {
    let relpath: String
    let genre: String
}

/// Per-window series for single-file JSON output.
struct WindowSeries: Codable {
    let fps: Double
    let windowSeconds: Double
    let fifthsDeg: [Double]
    let thirdsDeg: [Double]
    let consonance: [Double]
    let tension: [Double]
    let flux: [Double]
}

extension TonalDumperCommand {

    // MARK: - Decode

    /// Decode an audio file to mono Float32 at its native rate, trimmed to
    /// `[start, start+duration]` (whole file if `duration` is nil). Mono-downmix
    /// matches CensusAnalysis.decodeMonoFloat32.
    func decodeMono(url: URL, start: Double, duration: Double?) throws -> (samples: [Float], sampleRate: Float) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ValidationError("empty or unreadable: \(url.lastPathComponent)")
        }
        try file.read(into: buffer)
        let total = Int(buffer.frameLength)
        guard total > 0, let channels = buffer.floatChannelData else {
            throw ValidationError("decode produced no samples: \(url.lastPathComponent)")
        }
        let channelCount = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: total)
        let scale = 1.0 / Float(channelCount)
        for chan in 0..<channelCount {
            let ptr = UnsafeBufferPointer(start: channels[chan], count: total)
            for idx in 0..<total { mono[idx] += ptr[idx] * scale }
        }
        let rate = Float(format.sampleRate)
        let startIdx = max(0, min(total, Int(start * Double(rate))))
        let endIdx = duration.map { min(total, startIdx + Int($0 * Double(rate))) } ?? total
        return (Array(mono[startIdx..<endIdx]), rate)
    }

    // MARK: - Production MIR loop

    /// Run the shipping MIRPipeline (ChromaExtractor + TonalAnalyzer) over the
    /// samples at 1024-pt FFT / 512-hop (2× overlap, the live cadence) and
    /// collect the per-frame tonal signals. MIRPipeline is built at the file's
    /// native rate so the chroma fold maps bins→pitch-classes correctly.
    func analyzeTonal(samples: [Float], sampleRate: Float) -> TonalFrames {
        let fftSize = 1024
        let hop = fftSize / 2
        guard samples.count >= fftSize, let fft = try? FFTMagnitudeKernel(fftSize: fftSize) else {
            return TonalFrames()
        }
        let mir = MIRPipeline(binCount: fftSize / 2, sampleRate: sampleRate, fftSize: fftSize)
        let fps = Double(sampleRate) / Double(hop)
        let deltaTime = Float(1.0 / fps)
        var frames = TonalFrames()
        frames.fps = fps
        var offset = 0
        var frameIdx = 0
        while offset + fftSize <= samples.count {
            for pos in 0..<fftSize { fft.windowed[pos] = samples[offset + pos] }
            fft.computeMagnitudes()
            let feat = mir.process(
                magnitudes: fft.magnitudes,
                fps: Float(fps),
                time: Float(frameIdx) * deltaTime,
                deltaTime: deltaTime
            )
            frames.fifths.append(Double(feat.tonalPhaseFifths))
            frames.thirds.append(Double(feat.tonalPhaseThirds))
            frames.consonance.append(Double(feat.tonalConsonance))
            frames.tension.append(Double(feat.tonalTension))
            frames.flux.append(Double(feat.harmonicFlux))
            offset += hop
            frameIdx += 1
        }
        return frames
    }

    // MARK: - Manifest reading

    /// Parse a manifest CSV (needs a `relpath` column; `genre_bucket` optional).
    func readManifest(_ path: String) throws -> [ManifestRow] {
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        let lines = TonalStats.splitLines(text)   // CRLF-safe (the Swift grapheme gotcha)
        guard let header = lines.first else { return [] }
        let cols = TonalStats.parseCSVLine(header)
        guard let relIdx = cols.firstIndex(of: "relpath") else {
            throw ValidationError("manifest has no `relpath` column")
        }
        let genreIdx = cols.firstIndex(of: "genre_bucket")
        var rows: [ManifestRow] = []
        for line in lines.dropFirst() {
            let fields = TonalStats.parseCSVLine(line)
            guard fields.count > relIdx, !fields[relIdx].isEmpty else { continue }
            let genre = (genreIdx.flatMap { fields.count > $0 ? fields[$0] : nil }) ?? "unknown"
            rows.append(ManifestRow(relpath: fields[relIdx], genre: genre))
        }
        return rows
    }

    // MARK: - Output

    func printWindowTable(_ frames: TonalFrames) {
        let fifthsW = TonalStats.windowMeans(frames.fifths, fps: frames.fps, windowSeconds: window, phase: true)
        let thirdsW = TonalStats.windowMeans(frames.thirds, fps: frames.fps, windowSeconds: window, phase: true)
        let consW = TonalStats.windowMeans(frames.consonance, fps: frames.fps, windowSeconds: window)
        let tensW = TonalStats.windowMeans(frames.tension, fps: frames.fps, windowSeconds: window)
        let fluxW = TonalStats.windowMeans(frames.flux, fps: frames.fps, windowSeconds: window)
        print("  t(s)   fifths°  thirds°   cons   tens   flux")
        for idx in 0..<fifthsW.count {
            let time = Double(idx) * window
            print(String(
                format: "%6.1f  %+7.1f  %+7.1f  %5.3f  %5.3f  %5.3f",
                time,
                deg(fifthsW[idx]),
                deg(thirdsW[idx]),
                consW[idx],
                tensW[idx],
                fluxW[idx]
            ))
        }
    }

    func printSummary(_ frames: TonalFrames, label: String) {
        let conc = TonalStats.circularConcentration(frames.fifths)
        print("\n── \(label): \(frames.consonance.count) frames @ \(String(format: "%.1f", frames.fps)) Hz ──")
        printSignal("consonance", frames.consonance)
        printSignal("tension   ", frames.tension)
        printSignal("flux      ", frames.flux)
        print(String(format: "fifths-phase concentration (0=spread,1=locked): %.3f", conc))
    }

    private func printSignal(_ name: String, _ values: [Double]) {
        let pct = TonalStats.percentiles(values)
        print("\(name)  p10=\(f3(pct[10])) p50=\(f3(pct[50])) p90=\(f3(pct[90])) p99=\(f3(pct[99]))")
    }

    func printCalibration(_ report: CalibrationReport) {
        print("\n════ CALIBRATION (\(report.tracksAnalyzed) tracks, \(report.framesTotal) frames) ════")
        printCalRow("consonance", report.consonance)
        printCalRow("tension   ", report.tension)
        printCalRow("flux      ", report.flux)
        print("\nSuggested TonalAnalyzer constants (review in the pilot report):")
        print("  consonanceFloor ≈ consonance p10 = \(f3(report.consonance.p10))")
        print("  tension p99 (soft-saturate target) = \(f3(report.tension.p99))")
        print("  flux peak-pick ≈ p90 = \(f3(report.flux.p90)) · flux p99 (saturate) = \(f3(report.flux.p99))")
        print("\nper-genre median consonance / tension:")
        for genre in report.genreMedianConsonance.keys.sorted() {
            let cons = f3(report.genreMedianConsonance[genre])
            let tens = f3(report.genreMedianTension[genre])
            print("  \(genre.padding(toLength: 12, withPad: " ", startingAt: 0))  cons=\(cons)  tens=\(tens)")
        }
    }

    private func printCalRow(_ name: String, _ pct: SignalPercentiles) {
        let body = "p1=\(f3(pct.p1)) p5=\(f3(pct.p5)) p10=\(f3(pct.p10)) p25=\(f3(pct.p25))"
            + " p50=\(f3(pct.p50)) p75=\(f3(pct.p75)) p90=\(f3(pct.p90)) p99=\(f3(pct.p99))"
        print("\(name)  \(body)")
    }

    func windowSeries(_ frames: TonalFrames) -> WindowSeries {
        func win(_ values: [Double], phase: Bool = false) -> [Double] {
            TonalStats.windowMeans(values, fps: frames.fps, windowSeconds: window, phase: phase)
        }
        return WindowSeries(
            fps: frames.fps,
            windowSeconds: window,
            fifthsDeg: win(frames.fifths, phase: true).map(deg),
            thirdsDeg: win(frames.thirds, phase: true).map(deg),
            consonance: win(frames.consonance),
            tension: win(frames.tension),
            flux: win(frames.flux)
        )
    }

    // MARK: - Small helpers

    func deg(_ radians: Double) -> Double { radians * 180 / .pi }
    func fmt(_ value: Double) -> String { String(format: "%.4f", value) }
    func f3(_ value: Double?) -> String { String(format: "%.3f", value ?? 0) }
    func csvSafe(_ text: String) -> String { text.contains(",") ? "\"\(text)\"" : text }
}
