// WaveformOccupancy — the routable waveform-derived primitive (CHR.3c).
//
// **What it measures:** how much of the spectrum is currently active *relative to each band's
// own long-run level*. Not loudness, not spectral shape — occupancy. A sparse duo and a dense
// wall of guitars can sit at the same RMS and the same high/low energy ratio; this separates
// them.
//
// **Why it had to exist.** Measured against every recorded primitive on Carry The Zero, the
// quantity a spectral-dispersion preset actually draws correlates with NONE of them — the best
// existing correlate is `arousal` at r = +0.395, and `spectralDensity` runs *negative* at
// −0.364. So it is genuinely absent from `FeatureVector`, not a rename of something present.
//
// **Why it lives here and not in `MIRPipeline`.** The faithful value needs the TIME-DOMAIN
// waveform, and `MIRPipeline.process` receives only FFT magnitudes. A spectral reconstruction
// was prototyped against the same audio and reached only **r = +0.628** — a real relationship,
// but ~40 % of the variance differs, enough to change what a consuming preset draws. So it is
// computed where the waveform actually is: `RenderPipeline`, from the same `waveformBuffer`
// the preset fragments bind at slot 2, written into the `FeatureVector` beside `aspectRatio`.
//
// **Why it survives limiting.** Each band is measured against its own ~20 s envelope, so a
// scalar gain anywhere upstream cancels. That matters on modern masters: Carry The Zero spans
// only 1.4× RMS across the entire song, so an absolute level primitive carries almost nothing
// there. Same reasoning `SpectralAnalyzer.density` records for its own existence.

import Foundation
import Shared

/// Per-frame occupancy tracker. One instance per consumer; cheap (8 prefix-sum passes).
public struct WaveformOccupancy {

    /// Seconds. Per-band envelope — long, so a quiet passage still reads as quieter rather
    /// than normalising itself back up, but short enough to settle across a track change.
    public static let levelTau: Float = 20.0

    /// PARTIAL tilt compensation, and the exponent is load-bearing. A pure ratio
    /// (`rms / level`, i.e. exponent 1) normalises every track to ~1 and destroys the
    /// quiet-vs-dense discrimination entirely — measured: Take Five's consumer spread went
    /// 0.076–0.158 (correct, converged) to 0.184–0.358 (wrong, wide open) the moment the
    /// primitive was defined as a ratio. Below 1 the value keeps absolute level while still
    /// surviving a scalar gain upstream, which is the whole point.
    public static let tilt: Float = 0.45
    /// Reference band level the compensation is taken against.
    public static let reference: Float = 0.16

    /// The value written to `FeatureVector.waveformOccupancy`. Roughly 0…0.2 on real music:
    /// small on sparse quiet material, larger when more of the spectrum is carrying energy,
    /// → 0 at silence. Not normalised to a fixed range on purpose — see `tilt`.
    public private(set) var value: Float = 0

    private var levels = [Float](repeating: 0, count: StaveBandPlan.count)
    private var seeded = false
    private var mono: [Float] = []
    private var lowpass: [[Float]] = []
    private var prefix: [Float] = []

    public init() {}

    /// Advance from an interleaved-stereo waveform buffer (the engine's layout: 2 × frames).
    public mutating func advance(waveform: UnsafePointer<Float>, frames: Int, deltaTime: Float) {
        guard frames > 8 else { return }
        prepare(frames)
        for i in 0..<frames {
            mono[i] = (waveform[2 * i] + waveform[2 * i + 1]) * 0.5
        }
        for (index, width) in StaveBandPlan.widths.enumerated() {
            // Into a local, then back: `&lowpass[index]` while the method also touches `self`
            // is an exclusivity violation on a struct.
            var band = lowpass[index]
            boxFilter(width: width, frames: frames, into: &band)
            lowpass[index] = band
        }
        let alpha = 1 - exp(-max(deltaTime, 1e-4) / Self.levelTau)
        var total: Float = 0
        for band in 0..<StaveBandPlan.count {
            let hi = band + 1 < StaveBandPlan.count ? lowpass[band + 1] : mono
            var sumSquares: Float = 0
            for i in 0..<frames {
                let sample = hi[i] - lowpass[band][i]
                sumSquares += sample * sample
            }
            let rms = (sumSquares / Float(frames)).squareRoot()
            if !seeded { levels[band] = rms } else { levels[band] += (rms - levels[band]) * alpha }
            total += levels[band] > 1e-7
                ? rms * pow(Self.reference / levels[band], Self.tilt)
                : 0
        }
        seeded = true
        value = total / Float(StaveBandPlan.count)
    }

    public mutating func reset() {
        for i in levels.indices { levels[i] = 0 }
        seeded = false
        value = 0
    }

    private mutating func prepare(_ frames: Int) {
        guard mono.count != frames else { return }
        mono = [Float](repeating: 0, count: frames)
        lowpass = Array(repeating: [Float](repeating: 0, count: frames), count: StaveBandPlan.count)
        prefix = [Float](repeating: 0, count: frames + 1)
    }

    /// Centred box average via a prefix sum — O(n) per width, not O(n·W).
    private mutating func boxFilter(width: Int, frames: Int, into out: inout [Float]) {
        guard width > 1 else { out = mono; return }
        prefix[0] = 0
        for i in 0..<frames { prefix[i + 1] = prefix[i] + mono[i] }
        let half = width / 2
        for i in 0..<frames {
            let lo = max(0, i - half), hi = min(frames, i + half)
            out[i] = (prefix[hi] - prefix[lo]) / Float(max(hi - lo, 1))
        }
    }
}
