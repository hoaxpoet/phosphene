// MoodFluxCalibrationTests — DYN.6: is the mood classifier's input still in scale?
//
// WHY THIS EXISTS, AND THE CLAIM IT RETRACTED. DYN.5 recorded a caveat: `rawSmoothedFlux`
// is a per-FRAME spectral difference, so its magnitude "is rate-dependent by construction"
// and the mood classifier — which consumes it raw as feature [7], z-scored against a
// hardcoded mean/std — would therefore be biased by the analysis rate. Presets are
// insulated (they read `spectral_flux`, an AGC ratio in which a constant gain cancels); the
// classifier is not.
//
// **That caveat was wrong, and it was wrong because it came from a synthetic drive.** The
// DYN.5 signal was a smoothly varying spectrum, where consecutive frames differ mostly by
// the frame interval, so flux scaled with the hop and the dependence looked structural.
// Real music does not behave that way: at a 1024-sample window the spectrum decorrelates
// almost completely between hops whatever the hop is, so the frame interval barely enters.
// Measured through the production pipeline on eight Siamese Dream tracks, the rate shift on
// EVERY one of the ten mood features is within ±0.11 sigma between the 43 Hz offline
// preparation rate and the 9.9 Hz live rate. This is FA #27 exactly — a synthetic signal
// reproduced a property real audio does not have — and it is worth the retraction being
// louder than the original claim.
//
// WHAT THE MEASUREMENT DID FIND. The flux feature runs systematically HIGH against the
// shipped scaler on this material: z of +3.38, +2.87, +2.78, +1.89, +0.95, +0.78, +0.27,
// -0.18 across eight tracks (median +1.34), while the other nine features sit within
// ±1.9 sigma. Six of eight positive, three above +2.5. Whether that is a stale scaler or an
// accurate reading of one dense, distorted-guitar album cannot be settled from one album —
// `CorpusCensusRunner` already computes `rawSmoothedFlux` over a broad library and is the
// instrument that would settle it.
//
// So: this suite ASSERTS only rate-invariance, which is mechanically checkable and is what
// DYN.4/DYN.5 bought. Where the features sit relative to TRAINING is reported, never
// asserted — a test cannot decide whether a distribution shift is a defect or the music.
//
//   MOOD_AUDIO="/path/to/track.mp3" swift test --package-path PhospheneEngine \
//     --filter MoodFluxCalibration

import Testing
import Foundation
import AVFoundation
@testable import Audio
@testable import DSP
@testable import ML
@testable import Shared

@Suite("Mood classifier input calibration (DYN.6)")
struct MoodFluxCalibrationTests {

    private static let fftSize = 1024

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

    /// The full 10-feature mood input over a decoded track, assembled exactly as
    /// `VisualizerEngine.accumulateMoodFeatures` assembles it live — same fields, same
    /// order, same Nyquist normalisation — through the production `MIRPipeline`.
    private static func moodFeatures(url: URL, hop: Int) throws -> [[Float]] {
        let (samples, sampleRate) = try decodeMono(url)
        guard !samples.isEmpty else { return [] }
        let pipeline = MIRPipeline(binCount: fftSize / 2,
                                   sampleRate: Float(sampleRate), fftSize: fftSize)
        let fft = try FFTMagnitudeKernel(fftSize: fftSize)
        let deltaTime = Float(hop) / Float(sampleRate)
        let fps = Float(sampleRate) / Float(hop)
        var rows: [[Float]] = []
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
            let nyquist = Float(sampleRate) / 2
            rows.append([
                fv.subBass, fv.lowBass, fv.lowMid, fv.midHigh, fv.highMid, fv.high,
                pipeline.rawSmoothedCentroid / nyquist,
                pipeline.rawSmoothedFlux,
                pipeline.latestMajorKeyCorrelation,
                pipeline.latestMinorKeyCorrelation
            ])
            offset += hop
            time += deltaTime
        }
        return rows
    }

    private static func median(_ v: [Float]) -> Float {
        v.isEmpty ? 0 : v.sorted()[v.count / 2]
    }

    private static let names = ["subBass", "lowBass", "lowMid", "midHigh", "highMid",
                                "high", "centroid", "flux", "majorCorr", "minorCorr"]

    @Test("report every mood feature's z-score against the shipped scaler")
    func reportMoodFeatureCalibration() throws {
        guard let path = ProcessInfo.processInfo.environment["MOOD_AUDIO"] else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("missing \(url.path)"); return
        }
        let means = MoodClassifier.scalerMeansForTesting
        let stds = MoodClassifier.scalerStdsForTesting

        // 1024 = the offline preparation hop (43.07 fps at CD rate); 736 ~ the measured
        // live analysis rate on session 2026-08-10T01-29-10Z (9.9 Hz).
        var zByRate: [Int: [Float]] = [:]
        for hop in [1024, 736] {
            let rows = try Self.moodFeatures(url: url, hop: hop)
            guard !rows.isEmpty else { continue }
            zByRate[hop] = (0..<MoodClassifier.featureCount).map { idx in
                (Self.median(rows.map { $0[idx] }) - means[idx]) / stds[idx]
            }
        }
        guard let offline = zByRate[1024], let live = zByRate[736] else {
            Issue.record("needed both rates"); return
        }

        print("\n── MOOD FEATURE CALIBRATION ───────────────────────────────────────")
        print(String(format: "file  %@", url.lastPathComponent as NSString))
        print("feature      scaler mean    z @43 fps   z @60 fps   rate shift")
        for idx in 0..<MoodClassifier.featureCount {
            print(String(format: "  %-10s %10.5f    %+7.2f     %+7.2f     %+.2f",
                         (Self.names[idx] as NSString).utf8String!, means[idx],
                         offline[idx], live[idx], live[idx] - offline[idx]))
        }
        let worst = (0..<MoodClassifier.featureCount).max { abs(offline[$0]) < abs(offline[$1]) }!
        print(String(format: "worst feature: %@ at %+.2f sigma",
                     Self.names[worst] as NSString, offline[worst]))
        print("───────────────────────────────────────────────────────────────────\n")

        // MECHANICAL CLAIM: the analysis RATE must not move any feature materially. That is
        // what DYN.4/DYN.5 bought, and it is the part this suite can assert. Whether the
        // features sit where the model was TRAINED is a separate question, reported above
        // and owned by whoever owns the model — a test cannot decide it.
        for idx in 0..<MoodClassifier.featureCount {
            #expect(abs(live[idx] - offline[idx]) < 0.25, """
                \(Self.names[idx]) moves \(live[idx] - offline[idx]) sigma between the \
                offline preparation rate and the live rate. The two paths would then \
                classify the same track differently.
                """)
        }
    }
}
