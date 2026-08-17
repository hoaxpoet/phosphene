// StaveDispersionModel — Stave's motion model: the waveform, split into its spectral colours.
//
// The concept, Matt 2026-08-16: **align the visible light spectrum to the frequency spectrum.**
// Bass at the red end, treble at violet, one pass across the visible band. The wave is the
// subject; the colour tells you what is in it. A red curve IS low frequency — instantaneously
// and by construction, so unlike the retired stem hue it cannot be a late or a false label.
//
// Pure CPU, no Metal, mirroring the `WitchlightPath` / `WitchlightStroke` split: this file is
// the whole model and `StaveTrace` is the seam that uploads and draws it. Costs ~8 prefix-sum
// passes over 1024 samples per frame.
//
// Everything the first Stave did is gone: no scrolling history ring, no time axis, no beat
// rules, no static stave lines, no sparkle field, no stem tint, no beads. Matt cut the beads
// and the stems explicitly; the rest went with the plot. What is left is the present moment of
// the sound, in colour.

import Foundation
import Shared

// MARK: - Band plan

/// The dispersion's frequency bands.
///
/// Bands come from a cascade of moving averages over the waveform window: a box average of
/// width `W` is a low-pass with cutoff ≈ `fs / 2W`, and the difference of two consecutive
/// low-passes is a band-pass. No filter design, no per-frame FFT, and it runs on the raw
/// waveform the engine already binds.
///
/// **NOT one band per octave.** Even octave spacing put three bands above 3 kHz, and because
/// high frequencies oscillate densely they clumped into a single purple mass at the violet end
/// (rendered and rejected, CHR.3b). These widths fall steeply at the bottom and coarsely at the
/// top, so the RED half gets five bands across 69–550 Hz — where the music's energy actually
/// lives — and the violet half gets three wide ones.
public enum StaveBandPlan {
    /// Moving-average widths, widest (lowest cutoff) first. Cutoffs at 44.1 kHz:
    /// 69, 98, 138, 197, 306, 551, 1378, 5512 Hz.
    public static let widths = [320, 224, 160, 112, 72, 40, 16, 4]
    public static var count: Int { widths.count }

    /// Geometric-mean centre frequency of band `index`, from the two cutoffs bounding it.
    public static func centreHz(_ index: Int, sampleRate: Float) -> Float {
        let lo = sampleRate / Float(2 * widths[index])
        let hi = index + 1 < widths.count
            ? sampleRate / Float(2 * widths[index + 1])
            : sampleRate / 2
        return (lo * hi).squareRoot()
    }

    /// Frequency → visible wavelength, compressed ONCE across the audible span — the literal
    /// alignment Matt asked for, not an octave wrap. Log-frequency maps linearly onto
    /// 700 nm (red) … 400 nm (violet), because pitch is logarithmic and hue is not.
    public static func wavelengthNm(_ hz: Float) -> Float {
        let loHz: Float = 40, hiHz: Float = 12_000
        let ramp = min(max((log2(max(hz, loHz)) - log2(loHz)) / (log2(hiHz) - log2(loHz)), 0), 1)
        return 700 - ramp * (700 - 400)
    }

    /// Approximate sRGB for a visible wavelength (Dan Bruton's standard piecewise fit).
    /// Used rather than a hand-picked hue ramp because the whole concept is that the colour IS
    /// the physical wavelength — inventing a palette here would quietly discard the direction.
    public static func spectralRGB(nm: Float) -> SIMD3<Float> {
        var red: Float = 0, green: Float = 0, blue: Float = 0
        switch nm {
        case ..<440: red = -(nm - 440) / (440 - 380); blue = 1
        case ..<490: green = (nm - 440) / (490 - 440); blue = 1
        case ..<510: green = 1; blue = -(nm - 510) / (510 - 490)
        case ..<580: red = (nm - 510) / (580 - 510); green = 1
        case ..<645: red = 1; green = -(nm - 645) / (645 - 580)
        default: red = 1
        }
        // Eye sensitivity falls off at both ends; without this the deep red reads as bright as
        // the greens and the whole thing flattens into an even rainbow.
        var falloff: Float = 1
        if nm > 700 { falloff = 0.3 + 0.7 * (780 - nm) / (780 - 700) }
        if nm < 420 { falloff = 0.3 + 0.7 * (nm - 380) / (420 - 380) }
        return SIMD3(red, green, blue) * max(falloff, 0)
    }
}

// MARK: - Configuration

public struct StaveConfiguration: Sendable {
    /// Samples drawn across the frame. The engine's waveform buffer is 2048 interleaved
    /// stereo floats = 1024 frames ≈ 23 ms at 44.1 kHz.
    public var sampleCount: Int
    /// Overall amplitude against the frame. Settled by render sweep (CHR.3b): 0.85 left the
    /// wave a thin strip in the middle, 2.8 overflowed into wall-to-wall fringe.
    public var scale: Float
    /// Partial spectral-tilt compensation. 1.0 equalises every band to the same level and the
    /// top bands arrive as a dense spiky comb; < 1 leaves the spectrum WEIGHTED the way music
    /// actually is — bass-dominant core, top end present but subordinate.
    public var tilt: Float
    /// Fan-spacing exponent. 1 = even; < 1 weights the spread toward the red end so the bass
    /// has room to be a gesture instead of competing with a crowded violet end.
    public var spacing: Float
    /// Fan extents. The spread is DRIVEN, not fixed — see `fan`.
    public var fanMin: Float
    public var fanMax: Float
    /// Seconds. How fast the spectrum may open and close; smoothed so it reads as a gesture
    /// rather than flickering per frame.
    public var fanTau: Float
    /// Seconds. Per-band level tracking. Long by design — see `gains`.
    public var levelTau: Float

    public init(
        sampleCount: Int = 1024,
        scale: Float = 1.7,
        tilt: Float = 0.45,
        spacing: Float = 0.5,
        fanMin: Float = 0.02,
        fanMax: Float = 0.40,
        fanTau: Float = 0.12,
        levelTau: Float = 20.0
    ) {
        self.sampleCount = sampleCount
        self.scale = scale
        self.tilt = tilt
        self.spacing = spacing
        self.fanMin = fanMin
        self.fanMax = fanMax
        self.fanTau = fanTau
        self.levelTau = levelTau
    }
}

// MARK: - StaveDispersionModel

public final class StaveDispersionModel: @unchecked Sendable {

    public let configuration: StaveConfiguration

    /// Drawn curves, `[band * sampleCount + i]`, in NDC half-heights.
    public private(set) var curves: [Float]
    /// Fixed per-band spectral colours — the mapping is physical, so these never animate.
    public private(set) var colours: [SIMD3<Float>]

    /// Current spread. **Driven, not fixed.** A fixed fan was rendered and rejected: on smooth
    /// quiet material (Take Five — brushed kit, upright bass, no transients) the wave
    /// excursions become small next to the gap between bands and the image collapses into
    /// evenly spaced parallel stripes, a static rainbow layer cake. Dispersion has to be
    /// something the music DOES. Driving it also gives quiet-vs-loud a real visual difference
    /// on modern masters, which matters more than it sounds: Carry The Zero spans only 1.4×
    /// RMS across the whole song, so level alone can never carry dynamics there.
    ///
    /// ⚠ This is a deliberate departure from strict optics — a real prism's separation is
    /// fixed by its material and does not breathe. Recorded as an expressive choice, accepted
    /// by Matt 2026-08-16.
    public private(set) var fan: Float

    /// Per-band running RMS, for the gains below.
    private var levels: [Float]
    private var seeded = false
    private var mono: [Float]
    private var lowpass: [[Float]]
    private var prefix: [Float]

    public init(configuration: StaveConfiguration = .init()) {
        self.configuration = configuration
        let samples = configuration.sampleCount
        self.curves = [Float](repeating: 0, count: StaveBandPlan.count * samples)
        self.levels = [Float](repeating: 0, count: StaveBandPlan.count)
        self.fan = configuration.fanMin
        self.mono = [Float](repeating: 0, count: samples)
        self.lowpass = Array(repeating: [Float](repeating: 0, count: samples),
                             count: StaveBandPlan.count)
        self.prefix = [Float](repeating: 0, count: samples + 1)
        self.colours = (0..<StaveBandPlan.count).map { index in
            // 44.1 kHz is the tap's rate; the mapping is fixed at build so the colours are a
            // property of the preset rather than something that shifts with the input device.
            StaveBandPlan.spectralRGB(nm: StaveBandPlan.wavelengthNm(
                StaveBandPlan.centreHz(index, sampleRate: 44_100)))
        }
    }

    // MARK: Tick

    /// Advance one frame from the engine's interleaved-stereo waveform buffer.
    ///
    /// - Parameters:
    ///   - waveform: 2 × `sampleCount` interleaved floats (the engine's `waveformBuffer`).
    ///   - frames: number of stereo frames available.
    ///   - deltaTime: seconds since the previous frame.
    public func advance(waveform: UnsafePointer<Float>, frames: Int, deltaTime: Float) {
        let usable = min(frames, configuration.sampleCount)
        guard usable > 8 else { return }
        for i in 0..<usable {
            mono[i] = (waveform[2 * i] + waveform[2 * i + 1]) * 0.5
        }
        if usable < configuration.sampleCount {
            for i in usable..<configuration.sampleCount { mono[i] = 0 }
        }

        for (k, width) in StaveBandPlan.widths.enumerated() {
            boxFilter(mono, width: width, into: &lowpass[k])
        }

        let dt = max(deltaTime, 1e-4)
        let levelAlpha = 1 - exp(-dt / max(configuration.levelTau, 1e-3))
        var drawnEnergy: Float = 0

        for k in 0..<StaveBandPlan.count {
            // band k = (next, brighter low-pass) − (this, duller low-pass)
            let hi = k + 1 < StaveBandPlan.count ? lowpass[k + 1] : mono
            var sumSquares: Float = 0
            let base = k * configuration.sampleCount
            for i in 0..<configuration.sampleCount {
                let sample = hi[i] - lowpass[k][i]
                curves[base + i] = sample
                sumSquares += sample * sample
            }
            let rms = (sumSquares / Float(configuration.sampleCount)).squareRoot()
            // Long-τ per-band level. NOT a per-section normaliser: at τ = 20 s a quiet passage
            // still draws quieter than the chorus either side of it, which is the whole point
            // of the original design's fixed-gain decision — but unlike a fixed gain it
            // survives a track change without the author knowing the track in advance. The
            // spike used whole-track gains, which production cannot have.
            if !seeded { levels[k] = rms } else { levels[k] += (rms - levels[k]) * levelAlpha }

            let gain = levels[k] > 1e-7
                ? configuration.scale * pow(0.16 / levels[k], configuration.tilt)
                : 0
            var bandEnergy: Float = 0
            for i in 0..<configuration.sampleCount {
                let drawn = curves[base + i] * gain
                curves[base + i] = drawn
                bandEnergy += drawn * drawn
            }
            drawnEnergy += (bandEnergy / Float(configuration.sampleCount)).squareRoot()
        }
        seeded = true

        // Spread on the DRAWN amplitude, so the fan reflects what is on screen rather than a
        // raw level the gains have already reshaped.
        let excursion = drawnEnergy / Float(StaveBandPlan.count)
        let target = configuration.fanMin
            + (configuration.fanMax - configuration.fanMin) * min(excursion / 0.10, 1)
        fan += (target - fan) * (1 - exp(-dt / max(configuration.fanTau, 1e-3)))
    }

    /// Return to the cold-start state (track change, harness reuse).
    public func reset() {
        for i in curves.indices { curves[i] = 0 }
        for i in levels.indices { levels[i] = 0 }
        seeded = false
        fan = configuration.fanMin
    }

    /// Centred box average via a prefix sum — O(n) per width, not O(n·W).
    private func boxFilter(_ input: [Float], width: Int, into out: inout [Float]) {
        let count = configuration.sampleCount
        guard width > 1 else { out = input; return }
        prefix[0] = 0
        for i in 0..<count { prefix[i + 1] = prefix[i] + input[i] }
        let half = width / 2
        for i in 0..<count {
            let lo = max(0, i - half), hi = min(count, i + half)
            out[i] = (prefix[hi] - prefix[lo]) / Float(max(hi - lo, 1))
        }
    }
}
