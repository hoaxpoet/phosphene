// MFCCProcessor — 13 MFCC, matching librosa.feature.mfcc(n_mfcc=13).
//
// Pipeline (librosa defaults): STFT n_fft=2048, hop=512, periodic Hann,
// center=True with zero-padding (pad_mode='constant') → power spectrogram
// (|STFT|²) → Slaney mel filterbank (128 bins, fmin=0, fmax=sr/2, norm='slaney')
// → power_to_db(ref=1.0, top_db=80) → DCT-II (ortho), keep the first 13.
//
// The DCT is a precomputed 13×128 cosine matrix (scipy dct type-2 ortho formula)
// rather than vDSP_DCT, to avoid any normalisation-convention mismatch.

import Accelerate
import Foundation

// MARK: - MFCCProcessor

/// Offline 13-MFCC extractor at 22050 Hz. Not thread-safe; one per analysis task.
final class MFCCProcessor {

    // MARK: - Spec

    static let sampleRate = 22050.0
    static let nFFT = 2048
    static let hop = 512
    static let nMels = 128
    static let nMFCC = 13
    static let fMin = 0.0
    static var fMax: Double { sampleRate / 2.0 }
    static let aminP: Float = 1e-10        // power_to_db default amin
    static let topDB: Float = 80.0

    static var nBins: Int { nFFT / 2 + 1 }           // 1025

    // MARK: - Precomputed

    private let rfft: VDSPRealFFT
    private let window: [Float]                 // periodic Hann, nFFT
    private let melBasis: [Float]               // nMels × nBins, row-major
    private let dct: [Float]                    // nMFCC × nMels, row-major

    // MARK: - Init

    init() {
        self.rfft = VDSPRealFFT(size: Self.nFFT)
        self.window = (0..<Self.nFFT).map {
            0.5 * (1.0 - cos(2.0 * Float.pi * Float($0) / Float(Self.nFFT)))
        }
        self.melBasis = Self.buildSlaneyMelBasis()
        self.dct = Self.buildDCT()
    }

    // MARK: - Transform

    /// 13 MFCC for mono 22050 Hz PCM.
    ///
    /// - Returns: bin-major row-major matrix, length `nMFCC * T`, indexed
    ///   `coeff * T + frame` (matches librosa's `(13, T)` C-order layout).
    func matrix(samples: [Float]) -> (data: [Float], frameCount: Int) {
        let nSamples = samples.count
        let frames = 1 + nSamples / Self.hop                 // center=True frame count
        guard frames > 0 else { return ([], 0) }
        let pad = Self.nFFT / 2
        let bins = Self.nBins

        // center=True, pad_mode='constant' → zero-pad nFFT/2 each side.
        var padded = [Float](repeating: 0, count: nSamples + 2 * pad)
        padded.withUnsafeMutableBufferPointer { dst in
            samples.withUnsafeBufferPointer { src in
                if let srcBase = src.baseAddress, let dstBase = dst.baseAddress {
                    (dstBase + pad).update(from: srcBase, count: nSamples)
                }
            }
        }

        // Pass 1: mel power_to_db (ref=1, no clamp yet) into a frame-major buffer,
        // tracking the global max for the top_db floor.
        var melDB = [Float](repeating: 0, count: frames * Self.nMels)
        var windowed = [Float](repeating: 0, count: Self.nFFT)
        var outReal = [Float](repeating: 0, count: rfft.binCount)
        var outImag = [Float](repeating: 0, count: rfft.binCount)
        var power = [Float](repeating: 0, count: bins)
        var imagSq = [Float](repeating: 0, count: bins)
        var mel = [Float](repeating: 0, count: Self.nMels)
        var globalMaxDB: Float = -Float.greatestFiniteMagnitude

        padded.withUnsafeBufferPointer { padBuf in
            let padBase = padBuf.baseAddress!     // swiftlint:disable:this force_unwrapping
            for frameIdx in 0..<frames {
                vDSP_vmul(padBase + frameIdx * Self.hop, 1, window, 1, &windowed, 1, vDSP_Length(Self.nFFT))
                windowed.withUnsafeBufferPointer { winBuf in
                    rfft.forward(frame: winBuf.baseAddress!, outReal: &outReal, outImag: &outImag)
                    // swiftlint:disable:previous force_unwrapping
                }
                // power = re² + im²
                vDSP_vsq(outReal, 1, &power, 1, vDSP_Length(bins))
                vDSP_vsq(outImag, 1, &imagSq, 1, vDSP_Length(bins))
                vDSP_vadd(power, 1, imagSq, 1, &power, 1, vDSP_Length(bins))
                // mel = melBasis (nMels×bins) · power (bins) → nMels
                vDSP_mmul(melBasis, 1, power, 1, &mel, 1, vDSP_Length(Self.nMels), 1, vDSP_Length(bins))
                // power_to_db, ref=1.0: 10·log10(max(amin, mel)).
                for melIdx in 0..<Self.nMels {
                    let decibel = 10.0 * log10(max(Self.aminP, mel[melIdx]))
                    melDB[frameIdx * Self.nMels + melIdx] = decibel
                    if decibel > globalMaxDB { globalMaxDB = decibel }
                }
            }
        }

        // Clamp to globalMax − top_db, then DCT-II ortho → first 13 coeffs.
        let floorDB = globalMaxDB - Self.topDB
        var out = [Float](repeating: 0, count: Self.nMFCC * frames)
        for frameIdx in 0..<frames {
            let base = frameIdx * Self.nMels
            for melIdx in 0..<Self.nMels where melDB[base + melIdx] < floorDB { melDB[base + melIdx] = floorDB }
            for coeff in 0..<Self.nMFCC {
                var acc: Float = 0
                let dctRow = coeff * Self.nMels
                for melIdx in 0..<Self.nMels { acc += dct[dctRow + melIdx] * melDB[base + melIdx] }
                out[coeff * frames + frameIdx] = acc
            }
        }
        return (out, frames)
    }

    // MARK: - Slaney mel filterbank (librosa.filters.mel, norm='slaney')

    static func buildSlaneyMelBasis() -> [Float] {
        let bins = nBins
        let halfSr = sampleRate / 2.0
        let fftFreqs = (0..<bins).map { Double($0) * halfSr / Double(bins - 1) }

        // Slaney hz↔mel.
        let fSp = 200.0 / 3.0
        let minLogHz = 1000.0
        let minLogMel = minLogHz / fSp
        let logStep = log(6.4) / 27.0
        func hzToMel(_ hz: Double) -> Double {
            hz < minLogHz ? hz / fSp : minLogMel + log(hz / minLogHz) / logStep
        }
        func melToHz(_ mel: Double) -> Double {
            mel < minLogMel ? mel * fSp : minLogHz * exp(logStep * (mel - minLogMel))
        }

        let nPts = nMels + 2
        let melMin = hzToMel(fMin), melMax = hzToMel(fMax)
        let melF = (0..<nPts).map { melToHz(melMin + Double($0) / Double(nPts - 1) * (melMax - melMin)) }
        let fdiff = (0..<(nPts - 1)).map { melF[$0 + 1] - melF[$0] }

        var basis = [Float](repeating: 0, count: nMels * bins)
        for melIdx in 0..<nMels {
            // Slaney area normalisation: 2 / (melF[m+2] − melF[m]).
            let enorm = 2.0 / (melF[melIdx + 2] - melF[melIdx])
            for binIdx in 0..<bins {
                let lower = -(melF[melIdx] - fftFreqs[binIdx]) / fdiff[melIdx]
                let upper = (melF[melIdx + 2] - fftFreqs[binIdx]) / fdiff[melIdx + 1]
                let weight = max(0.0, min(lower, upper))
                basis[melIdx * bins + binIdx] = Float(weight * enorm)
            }
        }
        return basis
    }

    // MARK: - DCT-II (orthonormal), scipy norm='ortho'

    static func buildDCT() -> [Float] {
        let count = nMels
        var matrix = [Float](repeating: 0, count: nMFCC * count)
        for coeff in 0..<nMFCC {
            let scale = coeff == 0 ? (1.0 / Double(count)).squareRoot()
                                   : (2.0 / Double(count)).squareRoot()
            for melIdx in 0..<count {
                let angle = Double.pi * Double(coeff) * Double(2 * melIdx + 1) / Double(2 * count)
                matrix[coeff * count + melIdx] = Float(scale * cos(angle))
            }
        }
        return matrix
    }
}
