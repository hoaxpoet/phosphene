// GossamerState — Per-preset world state for the Gossamer mv_warp preset (Increment 3.5.6).
//
// Maintains a fixed pool of up to 32 propagating color waves. Each wave travels outward
// from the hub along all radials simultaneously. Wave hue is baked from vocal pitch at
// emission (MV-3c YIN pitch tracking); saturation from "other" stem density; amplitude
// from vocal energy deviation.
//
// The waveBuffer MTLBuffer is bound at fragment buffer(6) in the scene fragment encoder
// via RenderPipeline.directPresetFragmentBuffer. The gossamer_fragment shader reads a
// GossamerGPU header (wave_count + 3 padding UInt32s) followed by up to 32 WaveGPU
// entries (16 bytes each). Total buffer size: 528 bytes.
//
// Emission gate: vocalsPitchConfidence > 0.35 OR |vocalsEnergyDev| > 0.05.
// Without either condition, the accumulator integrates but emission is suppressed.
// A slow ambient-drift fallback ensures waveCount ≥ 2 at silence (D-037 invariant 4).

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "Gossamer")

// MARK: - Wave (Swift-side state)

/// A single propagating color wave. Radius = age × waveSpeed (computed each frame, not stored).
public struct Wave: Sendable {
    /// Preset-local time when this wave was born (seconds since apply).
    public var birthTime: Float
    /// Hue [0..1] baked from vocalsPitchHz at emission.
    public var birthHue: Float
    /// Saturation [0..1] baked from other stem energy at emission.
    public var birthSaturation: Float
    /// Amplitude [0..1] baked from vocals_energy_dev at emission.
    public var amplitude: Float
}

// MARK: - WaveGPU

/// GPU-side wave descriptor — 16 bytes (4 × Float32).
/// Must match `WaveGPU` in Gossamer.metal byte-for-byte.
struct WaveGPU {
    var age: Float          // currentTime - birthTime
    var hue: Float          // 0..1
    var saturation: Float   // 0..1
    var amplitude: Float    // 0..1

    static let zero = WaveGPU(age: 0, hue: 0, saturation: 0, amplitude: 0)
}

// MARK: - GossamerState

/// Owns the wave pool and GPU-side buffer for the Gossamer preset.
///
/// Thread-safe: tick() and waveBuffer can be accessed from any queue.
public final class GossamerState: @unchecked Sendable {

    // MARK: - Constants

    public static let maxWaves: Int = 32
    /// Waves older than this are retired (seconds). Covers hub→rim at kWaveSpeed with margin.
    public static let maxWaveLifetime: Float = 6.0
    /// Wave radial speed in UV/sec. 0.12 UV/sec × 6s = 0.72 UV > web radius 0.42. ✓
    public static let waveSpeed: Float = 0.12

    // D-019 warmup: blend FV → stems as total stem energy climbs through this window.
    private static let warmupLow: Float  = 0.02
    private static let warmupHigh: Float = 0.06

    // Initial seeded wave ages — provide non-empty state from frame zero.
    private static let seed0Age: Float = 1.0
    private static let seed1Age: Float = 3.0

    // MARK: - Public Properties

    /// GPU-side wave buffer.
    ///
    /// Layout (528 bytes):
    ///   bytes  0– 3: UInt32 wave_count
    ///   bytes  4–15: 3 × UInt32 padding
    ///   bytes 16–527: 32 × WaveGPU (16 bytes each)
    ///
    /// Bound at fragment buffer(6) by VisualizerEngine+Presets via
    /// RenderPipeline.setDirectPresetFragmentBuffer.
    public let waveBuffer: MTLBuffer

    /// Active wave count this frame (updated by tick). Exposed for diagnostics.
    public private(set) var waveCount: Int = 0

    /// Wave emission accumulator (fractional waves pending emission). Exposed for diagnostics.
    public private(set) var waveEmissionAccumulator: Float = 0

    // MARK: - Private State

    private var pool: [Wave?]           // nil = empty slot
    private var currentTime: Float = 0
    private var rng: UInt32
    private let lock = NSLock()

    // MARK: - Init

    /// Creates a new GossamerState with 2 initial ambient waves pre-seeded.
    ///
    /// - Parameters:
    ///   - device: Metal device for buffer allocation.
    ///   - seed: Deterministic seed — same seed + same frame inputs → identical output.
    public init?(device: MTLDevice, seed: UInt32 = 42) {
        // 16-byte header + maxWaves × 16-byte WaveGPU
        let bufferSize = 16 + Self.maxWaves * MemoryLayout<WaveGPU>.stride
        guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            logger.error("GossamerState: failed to allocate waveBuffer (\(bufferSize) bytes)")
            return nil
        }
        waveBuffer = buf
        pool = Array(repeating: nil, count: Self.maxWaves)
        rng = seed
        seedInitialWaves()
        writeToGPU()
    }

    // MARK: - Public API

    /// Update wave pool for one rendered frame, then flush to waveBuffer.
    ///
    /// Call once per frame from the render-loop tick hook before the scene draw.
    ///
    /// - Parameters:
    ///   - deltaTime: Seconds elapsed since last frame.
    ///   - features: Current FeatureVector from MIR pipeline.
    ///   - stems: Current StemFeatures from stem analysis.
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        lock.withLock { _tick(deltaTime: deltaTime, features: features, stems: stems) }
        writeToGPU()
    }

    // MARK: - Private: tick (called while holding lock)

    private func _tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        let dt = max(deltaTime, 0.001)
        currentTime += dt

        // D-019 warmup: 0.0 = FV-only, 1.0 = stems fully warm.
        let totalStemEnergy = stems.vocalsEnergy + stems.drumsEnergy
                            + stems.bassEnergy   + stems.otherEnergy
        let stemMix = gossamerSmoothstep(Self.warmupLow, Self.warmupHigh, totalStemEnergy)

        // Retire waves older than maxWaveLifetime.
        retireOldWaves()

        // Emission rate: otherOnsetRate × 1.5 at high density; FV fallback mid_att × 2.0.
        let stemRate = stems.otherOnsetRate * 1.5
        let fvRate   = features.midAtt * 2.0
        let emissionRate = gossamerMix(fvRate, stemRate, stemMix)
        waveEmissionAccumulator += emissionRate * dt

        // Emit until accumulator < 1.0.
        while waveEmissionAccumulator >= 1.0 {
            waveEmissionAccumulator -= 1.0
            let pitchConfident = stems.vocalsPitchConfidence > 0.35
            let vocalActive    = abs(stems.vocalsEnergyDev) > 0.05
            if pitchConfident || vocalActive {
                emitWave(features: features, stems: stems, stemMix: stemMix,
                         pitchConfident: pitchConfident)
            }
            // Accumulator decremented regardless of gate: no clumping on re-entry.
        }

        // Ambient drift floor: ensure ≥ 2 waves alive at silence (D-037 invariant 4).
        let aliveCount = pool.filter { $0 != nil }.count
        if aliveCount < 2 {
            let driftRate: Float = 0.5   // ~1 wave every 2 seconds
            waveEmissionAccumulator += driftRate * dt
            if waveEmissionAccumulator >= 1.0 {
                waveEmissionAccumulator -= 1.0
                emitDriftWave()
            }
        }

        waveCount = pool.filter { $0 != nil }.count
    }

    // MARK: - Private: wave emission

    private func emitWave(
        features: FeatureVector, stems: StemFeatures,
        stemMix: Float, pitchConfident: Bool
    ) {
        let hue: Float
        if pitchConfident && stems.vocalsPitchHz > 0 {
            // log2(pitch/80) / log2(10) maps 80..800 Hz → 0..1.
            hue = gossamerClamp(
                log2(stems.vocalsPitchHz / 80.0) / log2(10.0), 0, 1
            )
        } else {
            // Ambient drift so fallback path still emits varied hues.
            hue = gossamerFract(0.5 + 0.3 * sin(currentTime * 0.2))
        }

        // Saturation: D-019 mix; floor at 0.5 so waves are never desaturated to invisibility.
        let satStem = gossamerClamp(stems.otherEnergy * 2.0, 0, 1)
        let satFV   = gossamerClamp(features.mid * 1.5, 0, 1)
        let rawSat  = gossamerMix(satFV, satStem, stemMix)
        let saturation = gossamerMix(0.5, 1.0, rawSat)

        // Amplitude: D-019 mix; quiet vocals = dim, loud = bright.
        let ampStem = gossamerClamp(abs(stems.vocalsEnergyDev) * 3.0 + 0.3, 0, 1)
        let ampFV   = gossamerClamp(abs(features.midRel) * 1.5 + 0.3, 0, 1)
        let amplitude = gossamerClamp(gossamerMix(ampFV, ampStem, stemMix), 0, 1)

        emitSlot(hue: hue, saturation: saturation, amplitude: amplitude)
    }

    private func emitDriftWave() {
        // Slow ambient hue walk; moderate sat/amp so the web never goes dark at silence.
        let hue = gossamerFract(0.5 + 0.3 * sin(currentTime * 0.15))
        emitSlot(hue: hue, saturation: 0.6, amplitude: 0.5)
    }

    private func emitSlot(hue: Float, saturation: Float, amplitude: Float) {
        let wave = Wave(
            birthTime: currentTime,
            birthHue: hue,
            birthSaturation: saturation,
            amplitude: amplitude
        )
        if let slot = freeSlot() {
            pool[slot] = wave
        } else {
            evictOldestAndReplace(with: wave)
        }
    }

    // MARK: - Private: pool management

    private func freeSlot() -> Int? {
        pool.indices.first { pool[$0] == nil }
    }

    private func evictOldestAndReplace(with wave: Wave) {
        // Evict the wave with the smallest birthTime (longest-lived, furthest from hub).
        var oldestIdx: Int?
        var oldestBirth = Float.infinity
        for i in pool.indices {
            guard let w = pool[i] else { continue }
            if w.birthTime < oldestBirth {
                oldestBirth = w.birthTime
                oldestIdx   = i
            }
        }
        if let idx = oldestIdx {
            pool[idx] = wave
        }
    }

    private func retireOldWaves() {
        for i in pool.indices {
            guard let wave = pool[i] else { continue }
            if currentTime - wave.birthTime >= Self.maxWaveLifetime {
                pool[i] = nil
            }
        }
    }

    // MARK: - Private: initial seeding

    private func seedInitialWaves() {
        // Two pre-existing waves so D-037 invariants 1 and 4 hold from frame zero.
        pool[0] = Wave(
            birthTime: -Self.seed0Age,  // age = 1.0s at frame zero
            birthHue: 0.55,
            birthSaturation: 0.70,
            amplitude: 0.65
        )
        pool[1] = Wave(
            birthTime: -Self.seed1Age,  // age = 3.0s at frame zero
            birthHue: 0.80,
            birthSaturation: 0.65,
            amplitude: 0.60
        )
        waveCount = 2
    }

    // MARK: - Private: GPU write

    private func writeToGPU() {
        // Collect alive waves (compacted — fragment iterates exactly wave_count entries).
        var aliveWaves: [(birthTime: Float, wave: Wave)] = []
        for wave in pool.compactMap({ $0 }) where currentTime - wave.birthTime < Self.maxWaveLifetime {
            aliveWaves.append((wave.birthTime, wave))
        }
        let count = min(aliveWaves.count, Self.maxWaves)

        let ptr = waveBuffer.contents()

        // Header: wave_count (UInt32) + 3 × UInt32 padding to 16-byte boundary.
        let hdr = ptr.bindMemory(to: UInt32.self, capacity: 4)
        hdr[0] = UInt32(count)
        hdr[1] = 0; hdr[2] = 0; hdr[3] = 0

        // Wave data starting at byte 16.
        let wavePtr = ptr.advanced(by: 16).bindMemory(to: WaveGPU.self, capacity: Self.maxWaves)
        for i in 0..<count {
            let w = aliveWaves[i].wave
            wavePtr[i] = WaveGPU(
                age:        currentTime - w.birthTime,
                hue:        w.birthHue,
                saturation: w.birthSaturation,
                amplitude:  w.amplitude
            )
        }
    }

    // MARK: - Private: PRNG (LCG — unused in Gossamer but kept for future Stalker extraction)

    @discardableResult
    private func lcg(_ seed: inout UInt32) -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 8) / Float(1 << 24)
    }

    // MARK: - Private: math helpers (local to avoid dependency on global functions)

    private func gossamerSmoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = gossamerClamp((x - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    private func gossamerClamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float { min(max(x, lo), hi) }
    private func gossamerMix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    private func gossamerFract(_ x: Float) -> Float { x - floor(x) }
}
