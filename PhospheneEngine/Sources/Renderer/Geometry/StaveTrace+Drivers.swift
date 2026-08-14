// StaveTrace+Drivers — Stave's GPU struct mirrors, its band tracker and its field-tint driver.
//
// Split out of `StaveTrace.swift` for the 400-line lint budget, the same way `WitchlightPath`
// was split at WL.9/WL.10. These are the pure-data and pure-CPU halves: no Metal, no
// pipelines, so they are drivable (and unit-testable) without a GPU.

import Metal
import Shared

// MARK: - GPU mirrors (field ORDER is the contract, not field names)

/// 28 bytes, matching MSL `StaveVertexGPU`. **`packed_*` on the MSL side is load-bearing:**
/// a plain `float4 color` is 16-byte aligned and pads the struct to a 48-byte stride against
/// Swift's 28, after which the vertex buffer is read at the wrong offsets and the traces
/// render as large mis-coloured triangles (CHR.2 defect 1 — magenta in a flat-*white*
/// control was the tell).
struct StaveVertexGPU {
    var posX: Float = 0, posY: Float = 0
    var colR: Float = 1, colG: Float = 1, colB: Float = 1, colA: Float = 1
    var width: Float = 0.004
}

/// 24 bytes, all scalar floats — no vector members, so there is no alignment padding to get
/// wrong on either side.
struct StaveConfigGPU {
    var aspect: Float = 16.0 / 9.0
    var tintR: Float = 1, tintG: Float = 1, tintB: Float = 1
    var ruleAlpha: Float = 1
    var time: Float = 0
}

extension StaveVertexGPU {
    /// Convenience construction with the colour as one value, so the upload call sites stay
    /// one-argument-per-line without a seven-line construction per vertex.
    init(x: Float, y: Float, colour: SIMD3<Float>, alpha: Float, width: Float) {
        self.init()
        posX = x
        posY = y
        colR = colour.x
        colG = colour.y
        colB = colour.z
        colA = alpha
        self.width = width
    }
}

// MARK: - Band EMA

/// One band's running-average pivot, mirroring `BandDeviationTracker` (D-146):
/// seed-from-first-non-zero, two-speed warmup, `(v − ema) × 2`. Absolute thresholds on
/// AGC-normalised band values are FA #31; every position driver here is EMA-centred.
struct StaveBandTracker {
    static let decay: Float = 0.9989
    static let warmupDecay: Float = 0.9
    static let warmupFrames = 180
    static let valueCeiling: Float = 2.0

    private var avg: Float = 0
    private var warmup = 0

    mutating func rel(_ raw: Float) -> Float {
        let value = min(max(raw, 0), Self.valueCeiling)
        if value > 0 && warmup < Self.warmupFrames { warmup += 1 }
        let decay = warmup < Self.warmupFrames ? Self.warmupDecay : Self.decay
        if avg == 0 && value > 0 { avg = value }
        avg = avg * decay + value * (1 - decay)
        return (value - avg) * 2.0
    }
}

// MARK: - Field tint

/// The D-216 stem channel, and the ONLY place stems touch this preset.
///
/// The drive is the `drums+bass` **share of raw stem energy**, not `energyRel`. Measured at
/// CHR.3 (`docs/diagnostics/CHR3_FIELD_TINT_GATE_2026-08-14.md`): `energyRel` is centred on a
/// *per-stem* ~10 s EMA, so a sustained drum-led section drives its own deviation back toward
/// zero and the balance self-cancels on exactly the timescale a field tint lives at.
/// Between-section variance share (eta²) of the smoothed drive, seven captures — RATIO
/// 0.26–0.76 vs REL 0.11–0.20, RATIO winning on every one.
///
/// A share is **scale-invariant**, so this is not the FA #31 failure: multiply every stem by
/// any AGC gain and the ratio is unchanged, because the gain cancels between numerator and
/// denominator. The fixed window below is therefore a window on a *ratio*, not a threshold on
/// an AGC-normalised level.
struct StaveFieldTintDriver {
    /// Corpus-measured mapping window. Per-20 s section means span 0.447–0.526 and centre
    /// near 0.485 across three sessions and two capture paths, so one fixed window covers the
    /// corpus and no per-track normaliser is needed. `tanh` so an out-of-window track
    /// compresses rather than pinning to an end stop.
    static let centre: Float = 0.485
    static let scale: Float = 0.035

    /// The field's OWN time constant, which is not D-216's 3.0 s — that figure is the stem
    /// pipeline's latency. Measured at CHR.3: at τ = 3 s the field churns inside a single
    /// section (within-section sd 0.168); at τ = 8 s that halves to 0.092 while the
    /// between-section gap only falls 0.59 → 0.55.
    static let tau: Float = 8.0

    private var share: Float = -1

    /// 0 = vocals/other lead (cool), 1 = drums/bass lead (warm).
    private(set) var tint: Float = 0.5

    mutating func advance(stems: StemFeatures, deltaTime: Float) {
        let rhythm = stems.drumsEnergy + stems.bassEnergy
        let melodic = stems.vocalsEnergy + stems.otherEnergy
        let total = rhythm + melodic
        // D-019 warmup: stems are all-zero for the first ~10 s. Hold the neutral midpoint
        // rather than letting a 0/0 guard snap the field to an end stop on frame 1.
        guard total > 1e-6 else { return }
        let raw = rhythm / total

        if share < 0 {
            share = raw
        } else {
            share += (raw - share) * (1 - exp(-max(deltaTime, 0) / Self.tau))
        }
        tint = 0.5 + 0.5 * tanhf((share - Self.centre) / Self.scale)
    }

    /// The tint as a multiply-blend colour. Interpolated along a HUE path with the peak
    /// channel pinned to 1.0 — never a straight RGB lerp between complementary hues, which
    /// passes through desaturated grey at the midpoint, and the midpoint is where the tint
    /// spends most of its time (CHR.3 gate §3; the source's own field drifts around a hue
    /// circle per reference `03_palette_field_hue_drift.png`).
    var multiplyColour: SIMD3<Float> {
        // Cool teal (~192°) → warm amber (~28°), travelling the SHORT way through blue and
        // violet rather than through grey.
        let hue = (0.535 + (0.078 - 0.535 + 1.0) * tint).truncatingRemainder(dividingBy: 1.0)
        let saturation: Float = 0.62
        return Self.hueToMultiply(hue: hue, saturation: saturation)
    }

    /// HSV→RGB at value 1.0, so the brightest channel is always 1.0 and a multiply blend
    /// recolours the backdrop without darkening it overall.
    private static func hueToMultiply(hue: Float, saturation: Float) -> SIMD3<Float> {
        let sextant = hue * 6.0
        let index = floor(sextant)
        let frac = sextant - index
        let low = 1.0 - saturation
        let falling = 1.0 - saturation * frac
        let rising = 1.0 - saturation * (1.0 - frac)
        switch Int(index) % 6 {
        case 0: return SIMD3(1, rising, low)
        case 1: return SIMD3(falling, 1, low)
        case 2: return SIMD3(low, 1, rising)
        case 3: return SIMD3(low, falling, 1)
        case 4: return SIMD3(rising, low, 1)
        default: return SIMD3(1, low, falling)
        }
    }
}

// MARK: - Configuration

public struct StaveConfiguration: Sendable {
    /// Seconds of history on screen. CHR.1 measured the two traces' decorrelation in 8 s
    /// windows; the trace shows the same window so the measured numbers describe what is drawn.
    public var window: Float
    /// Plot rate. **20 Hz, not per render frame** — the analyser behind these bands updates at
    /// ~10 Hz (BUG-087: 16.4 Hz local-file, ~51 Hz streaming), so a 60 Hz plot draws two
    /// duplicate points for every real one and the segment-to-segment direction is numerical
    /// noise (CHR.2 defect 3). Pairs with the degenerate-segment guard in the vertex shader.
    public var plotHz: Float
    public var beadRadius: Float

    public init(window: Float = 8.0, plotHz: Float = 20.0, beadRadius: Float = 0.0115) {
        self.window = window
        self.plotHz = plotHz
        self.beadRadius = beadRadius
    }
}

// MARK: - Pipelines

enum StaveBlend { case alpha, additive, multiply }

/// Builds the four `stave_*` pipelines. The device/library/format triple is held here rather
/// than threaded through every call so the factory stays inside the parameter-count lint.
struct StavePipelineFactory {
    let device: MTLDevice
    let library: MTLLibrary
    let pixelFormat: MTLPixelFormat

    /// `prefix` names a `<prefix>_vertex` / `<prefix>_fragment` pair.
    func make(prefix: String, blend: StaveBlend) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "\(prefix)_vertex"),
              let fragmentFunction = library.makeFunction(name: "\(prefix)_fragment") else {
            throw StaveError.functionNotFound(prefix)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        guard let attachment = descriptor.colorAttachments[0] else {
            throw StaveError.functionNotFound("\(prefix): colorAttachments[0]")
        }
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        switch blend {
        case .alpha:
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        case .additive:
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .one
        case .multiply:
            // dst *= src. Recolours the backdrop without covering it.
            attachment.sourceRGBBlendFactor = .destinationColor
            attachment.destinationRGBBlendFactor = .zero
        }
        attachment.sourceAlphaBlendFactor = .zero
        attachment.destinationAlphaBlendFactor = .one
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
