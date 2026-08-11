// SurgeLoudnessProfileRealAudioTests — DYN.1c on the capture that reported the defect.
//
// Matt, 2026-08-04: *"the tree had grown to full size before the full band kicked in later
// in the song. there are also louder / fuller sections later."* Measured on session
// `2026-08-04T20-23-15Z` (Hummer, 75 s recovered from a crashed session):
//
//     spectral_surge reaches 1.00 at 31.6 s and stays pinned for 62 % of the capture
//     the 63 s section is 4 dB louder than the 27 s one that saturated it
//
// This runs the REAL `SpectralAnalyzer` over that capture's `raw_tap.wav` twice — once
// with the fixed band, once with a `LoudnessProfile` measured from the same audio — and
// asserts the second stops pinning AND keeps the louder late section above the arrival.
//
// The measured result on that capture: pinned fraction 63.3 % → 0.9 %, and the 63 s
// section reads 0.945 against the 31 s arrival's 0.612 (fixed band: 1.000 vs 1.000).
//
// TWO HONEST LIMITS, both stated rather than hidden:
//   - The profile here is measured over the RECOVERED FRAGMENT, not the whole file. In
//     production it is measured over the full decode during local-file preparation, which
//     can only widen the range further. The fragment is the harsher case.
//   - `raw_tap.wav` is the LF tap, which sits on the player node pre-mixer and pre-volume
//     (`LocalFilePlaybackProvider`), so its samples ARE the decoded file's samples. That
//     is what makes measuring the profile from the tap a fair stand-in for measuring it
//     from the file.
//
// Env-gated: a session capture is not a committed fixture.
//
//   FT_SESSION=~/Documents/phosphene_sessions/2026-08-04T20-23-15Z \
//     swift test --package-path PhospheneEngine --filter SurgeLoudnessProfileRealAudio

import Testing
import Foundation
@testable import Audio
@testable import DSP
@testable import Shared

@Suite("Per-track surge band on real audio (DYN.1c)")
struct SurgeLoudnessProfileRealAudioTests {

    private static let fftSize = 1024
    private static let binCount = 512
    private static let sampleRate: Float = 48000

    /// `FT_EARLY` / `FT_LATE` are audio-times in seconds: the section that saturated the
    /// fixed band, and a later section that is genuinely louder. Defaults are the measured
    /// pair from the Hummer capture.
    @Test("a per-track band stops the surge pinning on a real capture")
    func surgeStopsPinningWithProfile() throws {
        guard let session = ProcessInfo.processInfo.environment["FT_SESSION"] else { return }
        let url = URL(fileURLWithPath: (session as NSString).expandingTildeInPath)
            .appendingPathComponent("raw_tap.wav")
        let samples = try SpectralDensityRealAudioTests.loadFloatWavMonoShared(url)
        #expect(!samples.isEmpty, "no samples decoded from \(url.path)")

        let early = Double(ProcessInfo.processInfo.environment["FT_EARLY"] ?? "") ?? 31
        let late = Double(ProcessInfo.processInfo.environment["FT_LATE"] ?? "") ?? 63

        let profile = try #require(
            LoudnessProfile.measure(samples: samples, sampleRate: Double(Self.sampleRate),
                                    fftSize: Self.fftSize),
            "no usable loudness profile from \(url.path) — capture too short or too flat")

        let fixed = try Self.run(samples: samples, profile: nil)
        let profiled = try Self.run(samples: samples, profile: profile)

        print(String(format: "[DYN.1c] profile %.1f…%.1f dB (music range %.1f dB)",
                     profile.quietDB, profile.loudDB, profile.innerRangeDB))
        print("  t     level    surge(fixed)  surge(profile)")
        for index in stride(from: 0, to: fixed.count, by: 47) {   // ~1 s
            print(String(format: "  %5.1f  %7.2f   %.3f         %.3f",
                         fixed[index].time, fixed[index].level,
                         fixed[index].surge, profiled[index].surge))
        }

        func mean(_ series: [Frame], _ centre: Double, _ pick: (Frame) -> Float) -> Float {
            let window = series.filter { abs($0.time - centre) <= 2.0 }
            guard !window.isEmpty else { return 0 }
            return window.reduce(Float(0)) { $0 + pick($1) } / Float(window.count)
        }
        let levelEarly = mean(fixed, early) { $0.level }
        let levelLate = mean(fixed, late) { $0.level }
        let fixedPinned = Float(fixed.filter { $0.surge > 0.99 }.count) / Float(fixed.count)
        let profiledPinned = Float(profiled.filter { $0.surge > 0.99 }.count) / Float(profiled.count)
        let profiledEarly = mean(profiled, early) { $0.surge }
        let profiledLate = mean(profiled, late) { $0.surge }

        print(String(format: """
            [DYN.1c] level %.1f dB at %.0f s → %.1f dB at %.0f s; \
            pinned fraction %.1f %% (fixed) → %.1f %% (profile); \
            surge at those moments %.3f → %.3f
            """, levelEarly, early, levelLate, late,
            fixedPinned * 100, profiledPinned * 100, profiledEarly, profiledLate))

        // The capture must actually contain the thing being fixed, or this proves nothing.
        #expect(levelLate > levelEarly + 1.0, """
            The \(late) s section measures \(levelLate) dB against \(levelEarly) dB at \
            \(early) s — it is not materially louder. Either FT_EARLY/FT_LATE are wrong for \
            this capture or this capture has no louder late section, and the test cannot \
            judge the band either way.
            """)
        #expect(fixedPinned > 0.3, """
            The fixed band pins for only \(fixedPinned * 100) % of this capture, so this \
            capture does not exhibit the defect DYN.1c fixes. Use the capture that does \
            (2026-08-04T20-23-15Z) or the result is vacuous.
            """)

        // THE GATE. Measured on the Hummer capture: 63.3 % → 0.9 % pinned, and the 63 s
        // section reads 0.945 against the arrival's 0.612. The thresholds sit well inside
        // both so a real regression trips them, not capture-to-capture noise.
        #expect(profiledPinned < 0.05, """
            With this track's own distribution the surge still pins for \
            \(profiledPinned * 100) % of the capture (fixed band: \(fixedPinned * 100) %). \
            Pinned is a constant — the visual still cannot grow past the first loud moment.
            """)
        #expect(profiledLate > profiledEarly + 0.15, """
            The \(late) s section is \(levelLate - levelEarly) dB louder than the \(early) s \
            arrival, but reads \(profiledLate) against \(profiledEarly). Matt's complaint is \
            exactly this: "there are also louder / fuller sections later".
            """)
    }

    // MARK: - Harness

    private struct Frame {
        let time: Double
        let level: Float
        let surge: Float
    }

    /// One pass of the real analyzer over the capture, at the live hop (1024 samples per
    /// frame — the tap delivers 1024-frame buffers, so this is the live analysis rate),
    /// through the shared window→magnitude kernel.
    private static func run(samples: [Float], profile: LoudnessProfile?) throws -> [Frame] {
        let analyzer = SpectralAnalyzer(binCount: binCount, sampleRate: sampleRate, fftSize: fftSize)
        analyzer.setLoudnessProfile(profile)
        let fft = try FFTMagnitudeKernel(fftSize: fftSize)

        var frames: [Frame] = []
        var offset = 0
        while offset + fftSize <= samples.count {
            samples.withUnsafeBufferPointer { src in
                fft.windowed.withUnsafeMutableBufferPointer { dst in
                    guard let srcBase = src.baseAddress, let dstBase = dst.baseAddress else { return }
                    dstBase.update(from: srcBase.advanced(by: offset), count: fftSize)
                }
            }
            fft.computeMagnitudes()
            let result = analyzer.process(magnitudes: fft.magnitudes,
                                          deltaTime: Float(fftSize) / Float(sampleRate))
            frames.append(Frame(
                time: Double(offset) / Double(sampleRate),
                level: LoudnessProfile.levelDB(magnitudes: fft.magnitudes, count: fft.binCount),
                surge: result.surge))
            offset += fftSize
        }
        return frames
    }
}
