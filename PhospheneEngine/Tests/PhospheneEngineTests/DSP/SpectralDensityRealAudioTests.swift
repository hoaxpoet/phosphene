// SpectralDensityRealAudioTests — does DYN.1's field track a real section change?
//
// WHY THIS EXISTS. `SpectralAnalyzerTests` asserts the density definition on SYNTHETIC
// spectra — single peaks, one bin low and one bin high — and every one of those passes.
// On real audio the field does the opposite of what it was built to do. Measured on
// Matt's session `2026-08-04T17-17-01Z`, at the moment a distorted guitar enters:
//
//     audio 19 s   real HF 0.041   recorded spectral_density 0.1074
//     audio 20 s   real HF 0.068   recorded spectral_density 0.0996   ← guitar enters
//     audio 21 s   real HF 0.151   recorded spectral_density 0.0948
//     audio 22 s   real HF 0.119   recorded spectral_density 0.0893
//
// Real high-frequency content rises 5.6×; the field FALLS. A synthetic single-peak test
// cannot see that, because real music is broadband and a single peak is not — which is
// exactly why the synthetic suite stayed green through eight failed live reviews.
//
// Two tests here, deliberately different in kind:
//
//   1. `densityRisesOnRealSectionChange` — the ground truth. Runs the REAL
//      `SpectralAnalyzer` over a REAL capture's `raw_tap.wav`, through a real vDSP FFT
//      with the same 1024-point / 512-bin geometry the live pipeline uses. Env-gated on
//      `FT_SESSION` because a session capture is not a committed fixture.
//
//   2. `densityRisesWhenBroadbandGainsHarmonics` — fixture-free and always on. Uses a
//      PINK-ish broadband spectrum rather than a single peak, so it fails for the same
//      reason the real audio fails. This is the test that should have existed first.
//
// Reader is the eyes for the trajectory print (D-064); the assertions are the gate.

import Testing
import Foundation
import Accelerate
@testable import DSP

@Suite("Spectral density on real audio (DYN.1)")
struct SpectralDensityRealAudioTests {

    private static let fftSize = 1024
    private static let binCount = 512
    private static let sampleRate: Float = 48000

    // MARK: - Ground truth: the real analyzer over a real capture

    /// `FT_SESSION=~/Documents/phosphene_sessions/<id> [FT_EVENT=20] swift test --filter SpectralDensityRealAudio`
    ///
    /// `FT_EVENT` is the audio-time in seconds where the section change happens (default
    /// 20, the distorted-guitar entry in the capture above). The assertion is that the
    /// field is materially higher in the 3 s after that moment than the 3 s before.
    @Test("density rises across a real section change in a captured session")
    func densityRisesOnRealSectionChange() throws {
        guard let session = ProcessInfo.processInfo.environment["FT_SESSION"] else { return }
        let url = URL(fileURLWithPath: (session as NSString).expandingTildeInPath)
            .appendingPathComponent("raw_tap.wav")
        let samples = try Self.loadFloatWavMono(url)
        #expect(!samples.isEmpty, "no samples decoded from \(url.path)")

        let eventTime = Double(ProcessInfo.processInfo.environment["FT_EVENT"] ?? "") ?? 20

        // The live pipeline advances the analyzer once per FFT frame; mirror that rather
        // than sampling, so the EMA sees the same history it would live.
        let analyzer = SpectralAnalyzer(binCount: Self.binCount,
                                        sampleRate: Self.sampleRate,
                                        fftSize: Self.fftSize)
        let hop = Int(Self.sampleRate) / 10          // ~10 Hz, the MIR analysis rate
        var series: [(time: Double, density: Float, rawHF: Float)] = []

        var frameStart = 0
        while frameStart + Self.fftSize <= samples.count {
            let frame = Array(samples[frameStart..<(frameStart + Self.fftSize)])
            let magnitudes = try Self.magnitudes(of: frame)
            let result = analyzer.process(magnitudes: magnitudes)
            series.append((Double(frameStart) / Double(Self.sampleRate),
                           result.density,
                           Self.timeDomainHFFraction(frame)))
            frameStart += hop
        }
        #expect(series.count > 50, "capture too short to judge (\(series.count) frames)")

        // Independent reference: the SAME quantity measured in the time domain with a
        // one-pole split at the same 1.5 kHz. If the field is correct the two agree in
        // DIRECTION across the event; the recorded session says they do not.
        func mean(_ range: ClosedRange<Double>, _ pick: (Int) -> Float) -> Float {
            let idx = series.indices.filter { range.contains(series[$0].time) }
            guard !idx.isEmpty else { return 0 }
            return idx.reduce(Float(0)) { $0 + pick($1) } / Float(idx.count)
        }
        let before = eventTime - 3.0...eventTime
        let after = eventTime...eventTime + 3.0
        let densityBefore = mean(before) { series[$0].density }
        let densityAfter = mean(after) { series[$0].density }
        let hfBefore = mean(before) { series[$0].rawHF }
        let hfAfter = mean(after) { series[$0].rawHF }

        print("  t     density   time-domain HF")
        for entry in series where Int(entry.time * 2) % 2 == 0 && entry.time.truncatingRemainder(dividingBy: 1) < 0.11 {
            print(String(format: "  %5.1f  %7.4f   %7.4f", entry.time, entry.density, entry.rawHF))
        }
        print(String(format: """
            [density] across the event at %.1f s — reference HF %.4f → %.4f (%.2f×); \
            SpectralAnalyzer.density %.4f → %.4f (%.2f×)
            """, eventTime, hfBefore, hfAfter, hfAfter / max(hfBefore, 1e-6),
            densityBefore, densityAfter, densityAfter / max(densityBefore, 1e-6)))

        // The reference must actually contain an event, or the test proves nothing.
        #expect(hfAfter > hfBefore * 1.5, """
            the reference HF measure does not show a section change at \(eventTime) s \
            (\(hfBefore) → \(hfAfter)). Either FT_EVENT is wrong for this capture or this \
            capture has no event — the test cannot judge the field either way.
            """)

        // THE GATE. The field must move in the same direction, and materially.
        #expect(densityAfter > densityBefore * 1.25, """
            SpectralAnalyzer.density went \(densityBefore) → \(densityAfter) across a \
            section change where real high-frequency content went \(hfBefore) → \(hfAfter) \
            (\(hfAfter / max(hfBefore, 1e-6))×). The field is not measuring what DYN.1 was \
            added to measure. This is the failure behind Matt's "there is no jump in growth \
            when the distorted guitar kicks in" — and note the synthetic single-peak tests \
            in SpectralAnalyzerTests all pass, which is why it survived eight reviews.
            """)
    }

    // MARK: - Fixture-free: the test that should have existed first

    /// Broadband, not a single peak. Real music spreads energy across hundreds of bins,
    /// and a ratio over a broadband spectrum behaves nothing like a ratio over two spikes.
    @Test("density rises when a broadband mix gains harmonic content")
    func densityRisesWhenBroadbandGainsHarmonics() {
        // Pink-ish: energy ∝ 1/f, the rough shape of a rock mix's magnitude spectrum.
        func pink(harmonicGain: Float) -> [Float] {
            (0..<Self.binCount).map { bin in
                let hz = Float(bin) * Self.sampleRate / Float(Self.fftSize)
                let base = 1.0 / max(hz, 30)
                // Distortion adds harmonics ABOVE the split, on top of the same low end.
                let harmonics: Float = hz > 1500 ? base * harmonicGain : 0
                return base + harmonics
            }
        }
        func settle(_ magnitudes: [Float]) -> Float {
            let analyzer = SpectralAnalyzer(binCount: Self.binCount,
                                            sampleRate: Self.sampleRate,
                                            fftSize: Self.fftSize)
            var last: Float = 0
            for _ in 0..<6000 { last = analyzer.process(magnitudes: magnitudes).density }
            return last
        }
        let clean = settle(pink(harmonicGain: 0))
        let dirty = settle(pink(harmonicGain: 3))
        print(String(format: "[density] broadband clean %.4f → with harmonics %.4f", clean, dirty))
        #expect(dirty > clean * 1.25, """
            adding a 3× harmonic shelf above 1.5 kHz to a broadband mix moved density from \
            \(clean) to \(dirty). On a broadband spectrum the field barely responds, which \
            the single-peak synthetic tests cannot reveal.
            """)
    }

    // MARK: - Helpers

    /// Energy fraction above 1.5 kHz measured in the TIME domain with a one-pole split —
    /// deliberately a different method from the field under test, so agreement means
    /// something. This is the measure that showed the 5.6× rise the field missed.
    private static func timeDomainHFFraction(_ samples: [Float]) -> Float {
        let alpha = expf(-2 * .pi * 1500 / sampleRate)
        var low: Float = 0
        var lowEnergy: Float = 0
        var highEnergy: Float = 0
        for sample in samples {
            low = alpha * low + (1 - alpha) * sample
            let high = sample - low
            lowEnergy += low * low
            highEnergy += high * high
        }
        let total = lowEnergy + highEnergy
        return total > 1e-12 ? highEnergy / total : 0
    }

    /// Real vDSP forward FFT with the live pipeline's geometry, Hann-windowed.
    private static func magnitudes(of frame: [Float]) throws -> [Float] {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            throw DensityHarnessError.setupFailed("vDSP_create_fftsetup")
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        windowed.withUnsafeBufferPointer { src in
            real.withUnsafeMutableBufferPointer { realBuf in
                imag.withUnsafeMutableBufferPointer { imagBuf in
                    guard let realBase = realBuf.baseAddress,
                          let imagBase = imagBuf.baseAddress,
                          let srcBase = src.baseAddress else { return }
                    var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    srcBase.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
                }
            }
        }
        let scale = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, [scale], &magnitudes, 1, vDSP_Length(half))
        return magnitudes
    }

    /// Minimal float32 WAV reader, downmixed to mono. Session captures are written as
    /// 32-bit float, which `AVAudioFile` will open but this keeps the test dependency-free
    /// and makes the channel handling explicit.
    private static func loadFloatWavMono(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else { throw DensityHarnessError.setupFailed("wav too short") }

        // Walk the RIFF chunks rather than assuming a 44-byte header.
        var channels = 2
        var offset = 12
        var dataRange: Range<Int>?
        while offset + 8 <= data.count {
            let id = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let size = Int(data[(offset + 4)..<(offset + 8)].withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self).littleEndian
            })
            let body = offset + 8
            if id == "fmt " && body + 4 <= data.count {
                channels = Int(data[(body + 2)..<(body + 4)].withUnsafeBytes {
                    $0.loadUnaligned(as: UInt16.self).littleEndian
                })
            } else if id == "data" {
                dataRange = body..<min(body + size, data.count)
                break
            }
            offset = body + size + (size % 2)
        }
        guard let range = dataRange else { throw DensityHarnessError.setupFailed("no data chunk") }

        let floats = data[range].withUnsafeBytes { raw -> [Float] in
            Array(raw.bindMemory(to: Float.self))
        }
        guard channels > 1 else { return floats }
        return stride(from: 0, to: floats.count - channels + 1, by: channels).map { index in
            (floats[index] + floats[index + 1]) * 0.5
        }
    }
}

enum DensityHarnessError: Error {
    case setupFailed(String)
}
