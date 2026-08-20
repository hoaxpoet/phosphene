// BarLineEstimator+Features — the four beat-synchronous accent features.
//
// One value per beat, from a 2048-sample window starting at that beat. Ported verbatim
// from `beat_features` in `tools/barline_probe.py`; the ordering below is part of the
// contract, because the null's seed is derived from the feature index.
//
//   0  low_energy      sum of |X[k]| below 200 Hz — the kick lands on beat 1
//   1  rms             broadband loudness
//   2  flux            positive spectral change from the previous beat — change lands on bars
//   3  harmonic_change 1 - cosine similarity of adjacent beats' pitch-class profiles
//
// Every one of the four is scale-invariant under the contrast statistic (which divides by
// the feature's own sd), so the FFT's magnitude convention does not have to match the
// reference's — only the *shape* of each feature across beats does.

import Accelerate
import Foundation

extension BarLineEstimator {

    // MARK: - Feature extraction

    /// The four accent features, in the fixed order the null's seeding depends on.
    /// Returns four arrays of `beats.count` values each.
    static func beatFeatures(
        audio: [Float],
        beats: [Double],
        sampleRate: Double
    ) -> [[Double]] {
        let count = beats.count
        let bins = nFFT / 2 + 1
        let window = hannWindow(nFFT)
        let maps = binMaps(sampleRate: sampleRate, bins: bins)

        var lowEnergy = [Double](repeating: 0, count: count)
        var rms = [Double](repeating: 0, count: count)
        var flux = [Double](repeating: 0, count: count)
        var harmonicChange = [Double](repeating: 0, count: count)

        var chroma = [[Double]](repeating: [Double](repeating: 0, count: 12), count: count)
        var previousMagnitudes: [Double]?

        guard let fft = RealFFT(log2n: log2n, size: nFFT) else { return [lowEnergy, rms, flux, harmonicChange] }
        defer { fft.destroy() }

        var segment = [Double](repeating: 0, count: nFFT)
        for (index, beat) in beats.enumerated() {
            fillSegment(&segment, audio: audio, startSample: Int(beat * sampleRate))

            var meanSquare = 0.0
            for sample in segment { meanSquare += sample * sample }
            rms[index] = (meanSquare / Double(nFFT)).squareRoot() + 1e-12

            var windowed = segment
            for i in 0..<nFFT { windowed[i] *= window[i] }
            let magnitudes = fft.magnitudes(of: windowed)

            var low = 0.0
            for bin in maps.low { low += magnitudes[bin] }
            lowEnergy[index] = low

            if let previous = previousMagnitudes {
                var positiveChange = 0.0
                for bin in 0..<bins { positiveChange += max(magnitudes[bin] - previous[bin], 0) }
                flux[index] = positiveChange
            }
            previousMagnitudes = magnitudes

            for bin in maps.usable { chroma[index][maps.pitchClass[bin]] += magnitudes[bin] }
            normalise(&chroma[index])
        }

        for index in 1..<max(count, 1) {
            var similarity = 0.0
            for k in 0..<12 { similarity += chroma[index][k] * chroma[index - 1][k] }
            harmonicChange[index] = 1.0 - similarity
        }

        return [lowEnergy, rms, flux, harmonicChange]
    }

    // MARK: - Helpers

    /// The 2048 samples starting at `startSample`, zero-padded past the end of the track.
    private static func fillSegment(_ segment: inout [Double], audio: [Float], startSample: Int) {
        for offset in 0..<nFFT {
            let position = startSample + offset
            segment[offset] = (position >= 0 && position < audio.count) ? Double(audio[position]) : 0
        }
    }

    /// Symmetric Hann, matching `numpy.hanning`.
    private static func hannWindow(_ size: Int) -> [Double] {
        guard size > 1 else { return [Double](repeating: 1, count: size) }
        let denominator = Double(size - 1)
        return (0..<size).map { 0.5 - 0.5 * cos(2.0 * Double.pi * Double($0) / denominator) }
    }

    /// Bins below 200 Hz, bins usable for chroma (55-4000 Hz), and each bin's pitch class.
    struct BinMaps {
        let low: [Int]
        let usable: [Int]
        let pitchClass: [Int]
    }

    private static func binMaps(sampleRate: Double, bins: Int) -> BinMaps {
        var low = [Int]()
        var usable = [Int]()
        var pitchClass = [Int](repeating: 0, count: bins)
        for bin in 0..<bins {
            let frequency = Double(bin) * sampleRate / Double(nFFT)
            if frequency < 200.0 { low.append(bin) }
            if frequency > 55.0 && frequency < 4000.0 { usable.append(bin) }
            let midi = 69.0 + 12.0 * log2(max(frequency, 1e-6) / 440.0)
            pitchClass[bin] = ((Int(midi.rounded(.toNearestOrEven)) % 12) + 12) % 12
        }
        return BinMaps(low: low, usable: usable, pitchClass: pitchClass)
    }

    /// L2-normalise in place, with the reference's epsilon so an all-zero profile stays zero.
    private static func normalise(_ values: inout [Double]) {
        var sumSquares = 0.0
        for value in values { sumSquares += value * value }
        let norm = sumSquares.squareRoot() + 1e-12
        for index in values.indices { values[index] /= norm }
    }
}

// MARK: - RealFFT

/// Minimal real-input FFT magnitude helper over `vDSP_fft_zripD`.
struct RealFFT {
    private let setup: FFTSetupD
    private let size: Int
    private let log2n: vDSP_Length

    init?(log2n: vDSP_Length, size: Int) {
        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = setup
        self.size = size
        self.log2n = log2n
    }

    func destroy() { vDSP_destroy_fftsetupD(setup) }

    /// `|X[k]|` for k in `0...size/2`. `vDSP_fft_zrip` returns 2x the standard DFT, so the
    /// 0.5 below restores the textbook magnitude — cosmetic here, since every consumer of
    /// these magnitudes is scale-invariant.
    func magnitudes(of signal: [Double]) -> [Double] {
        let half = size / 2
        var real = [Double](repeating: 0, count: half)
        var imaginary = [Double](repeating: 0, count: half)
        var output = [Double](repeating: 0, count: half + 1)

        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let realBase = realBuffer.baseAddress,
                      let imaginaryBase = imaginaryBuffer.baseAddress else { return }
                var split = DSPDoubleSplitComplex(realp: realBase, imagp: imaginaryBase)
                signal.withUnsafeBufferPointer { input in
                    input.baseAddress?.withMemoryRebound(to: DSPDoubleComplex.self, capacity: half) {
                        vDSP_ctozD($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zripD(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                output[0] = abs(realBase[0]) * 0.5
                output[half] = abs(imaginaryBase[0]) * 0.5
                for bin in 1..<half {
                    output[bin] = (realBase[bin] * realBase[bin]
                                   + imaginaryBase[bin] * imaginaryBase[bin]).squareRoot() * 0.5
                }
            }
        }
        return output
    }
}
