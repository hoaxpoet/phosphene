// ArachneState — Per-preset world state for the Arachne mesh-shader preset (Increment 3.5.5).
//
// Manages a fixed pool of up to 12 webs. Each web progresses through stages
// (.anchorPulse → .radial → .spiral → .stable → .evicting) measured in beats,
// so spinning is slower on slow music and faster on fast music — a
// Phosphene-exclusive behavior derived from MV-3b BeatPredictor.
//
// The `webBuffer` MTLBuffer carries WebGPU structs (64 bytes each) that the
// Arachne mesh shader reads at object/mesh buffer(1) to determine which webs
// to render and how to build their geometry.

import Metal
import Shared
import simd
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "Arachne")

// MARK: - WebStage

/// Lifecycle stage of a single web.
public enum WebStage: UInt32, Sendable {
    case anchorPulse = 0   // Anchor dots pulse before downbeat
    case radial      = 1   // Radial spokes extend one by one
    case spiral      = 2   // Capture spiral winds outward
    case stable      = 3   // Fully spun; quivers to audio
    case evicting    = 4   // Fading out to make room in the pool
}

// MARK: - WebGPU

/// GPU-side web descriptor — 64 bytes (16 × 4-byte words, 4 rows of 4).
/// Must match `ArachneWebGPU` in Arachne.metal byte-for-byte.
public struct WebGPU: Sendable {
    // Row 0: clip-space position and scale
    public var hubX: Float        // clip-space X (-1..1)
    public var hubY: Float        // clip-space Y (-1..1)
    public var radius: Float      // clip-space outer radius
    public var depth: Float       // 0 = near, 1 = far (scales opacity)

    // Row 1: orientation and topology
    public var rotAngle: Float          // 2-D rotation of the web (radians)
    public var anchorCount: UInt32      // 5–8 radial anchors; fixed at spawn
    public var spiralRevolutions: Float
    public var rngSeed: UInt32          // deterministic per-web noise/jitter

    // Row 2: lifecycle
    public var birthBeatPhase: Float    // globalBeatIndex when spawned
    public var stage: UInt32            // WebStage.rawValue
    public var progress: Float          // 0..1 within current stage
    public var opacity: Float           // 1 during life; ramps to 0 during .evicting

    // Row 3: birth-baked color and alive flag
    public var birthHue: Float
    public var birthSat: Float
    public var birthBrt: Float
    public var isAlive: UInt32          // 0 = dead slot, 1 = alive

    public static var zero: WebGPU {
        WebGPU(
            hubX: 0,
            hubY: 0,
            radius: 0,
            depth: 0,
            rotAngle: 0,
            anchorCount: 0,
            spiralRevolutions: 0,
            rngSeed: 0,
            birthBeatPhase: 0,
            stage: 0,
            progress: 0,
            opacity: 0,
            birthHue: 0,
            birthSat: 0,
            birthBrt: 0,
            isAlive: 0
        )
    }
}

// MARK: - ArachneState

/// Owns the Arachne web pool and its GPU-side buffer.
///
/// Thread-safe: `tick()` and `webBuffer` can be accessed from any queue.
/// The object shader reads `webBuffer` directly; Swift never blocks GPU access.
public final class ArachneState: @unchecked Sendable {

    // MARK: - Constants

    public static let maxWebs: Int = 12
    static let spawnThreshold: Float = 1.0
    static let minSpawnGapBeats: Float = 0.5

    // Stage durations in beats.
    static let anchorPulseDuration: Float = 1.0
    static func radialDuration(_ anchorCount: UInt32) -> Float {
        min(max(Float(anchorCount) - 2.0, 3), 6)
    }
    static func spiralDuration(_ revolutions: Float) -> Float {
        max(4.0, revolutions * 1.5)
    }
    static let evictingDuration: Float = 2.0

    // MARK: - Public Properties

    /// GPU-side web descriptor array — bound at object/mesh buffer(1) each frame.
    public let webBuffer: MTLBuffer

    /// Number of alive webs this frame (updated by tick).
    public private(set) var webCount: Int = 0

    /// Spawn accumulator exposed for diagnostics.
    public private(set) var spawnAccumulator: Float = 0

    // MARK: - Private State

    private var webs: [WebGPU]
    private var globalBeatIndex: Float = 0
    private var lastSpawnBeatIndex: Float = -10
    private var prevBeatPhase01: Float = 0
    private var prevBeatComposite: Float = 0
    private var rng: UInt32
    private let lock = NSLock()

    // MARK: - Init

    /// Creates a new ArachneState with 2 initial stable webs pre-seeded.
    ///
    /// - Parameters:
    ///   - device: Metal device for buffer allocation.
    ///   - seed: Deterministic seed — same seed + same frame inputs → identical output.
    public init?(device: MTLDevice, seed: UInt32 = 42) {
        let bufferSize = Self.maxWebs * MemoryLayout<WebGPU>.stride
        guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            logger.error("ArachneState: failed to allocate webBuffer (\(bufferSize) bytes)")
            return nil
        }
        webBuffer = buf
        webs = Array(repeating: .zero, count: Self.maxWebs)
        rng = seed
        seedInitialWebs()
        writeToGPU()
    }

    // MARK: - Public API

    /// Update web pool for one rendered frame, then flush to `webBuffer`.
    ///
    /// Called once per frame by the RenderPipeline tick hook before mesh draw.
    public func tick(features: FeatureVector, stems: StemFeatures) {
        lock.withLock { _tick(features: features, stems: stems) }
        writeToGPU()
    }

    // MARK: - Private: tick (called while holding lock)

    private func _tick(features: FeatureVector, stems: StemFeatures) {
        let dt = max(features.deltaTime, 0.001)

        // Advance globalBeatIndex from beat_phase01 (wraparound-safe; 120 BPM fallback).
        let beatsDt = advanceBeatIndex(features: features, dt: dt)

        // D-019 warmup blend: 0 = FV only, 1 = stems fully warm.
        let totalStemEnergy = stems.drumsEnergy + stems.bassEnergy
                            + stems.otherEnergy + stems.vocalsEnergy
        let stemMix = arachSmoothstep(0.02, 0.06, totalStemEnergy)

        // Spawn accumulator ——————————————————————————————————————————————————
        // Stem path: drumsOnsetRate [onsets/sec] × dt → fraction of spawn threshold.
        let drumDrive = stems.drumsOnsetRate * dt * stemMix

        // FV fallback: rising edge on beat_composite / beat_bass counts as one onset.
        // Suppressed by actual drum activity, not by general stem warmup — so quiet/drumless
        // tracks (e.g. post-rock openings where drumsOnsetRate=0 but stems are warm) still
        // get a working spawn path from the beat detector.
        let currentBeat = max(features.beatComposite, features.beatBass)
        let risingEdge: Float = (currentBeat > 0.5 && prevBeatComposite <= 0.5) ? 0.8 : 0.0
        prevBeatComposite = currentBeat
        let drumActivity = min(stems.drumsOnsetRate * 0.05, 1.0)  // fully suppressed at ≥20 onsets/s
        let fvDrive = risingEdge * (1.0 - drumActivity)

        spawnAccumulator += drumDrive + fvDrive

        if spawnAccumulator >= Self.spawnThreshold &&
           (globalBeatIndex - lastSpawnBeatIndex) >= Self.minSpawnGapBeats {
            spawnAccumulator -= Self.spawnThreshold
            trySpawn(features: features, stems: stems, stemMix: stemMix)
        }

        // Advance all alive web stages.
        for i in 0..<Self.maxWebs where webs[i].isAlive != 0 {
            advanceStage(index: i, beatsDt: beatsDt)
        }

        webCount = webs.filter { $0.isAlive != 0 }.count
    }

    // MARK: - Private: beat index advancement

    /// Returns the beat-fraction elapsed this frame and advances globalBeatIndex.
    @discardableResult
    private func advanceBeatIndex(features: FeatureVector, dt: Float) -> Float {
        var delta = features.beatPhase01 - prevBeatPhase01
        if delta < -0.5 { delta += 1.0 }  // wraparound: 0.95→0.05 ⟹ +0.10
        let beatsDt: Float = delta > 0 ? delta : dt * 2.0  // 120 BPM fallback
        globalBeatIndex += beatsDt
        prevBeatPhase01 = features.beatPhase01
        return beatsDt
    }

    // MARK: - Private: web spawning

    private func trySpawn(features: FeatureVector, stems: StemFeatures, stemMix: Float) {
        guard let slot = freeSlot() ?? evictAndRetry() else { return }
        lastSpawnBeatIndex = globalBeatIndex

        // Birth color: D-019 mix of stems.otherCentroid vs features.spectralCentroid.
        let hue = arachMix(centroidToHue(features.spectralCentroid),
                           centroidToHue(stems.otherCentroid),
                           stemMix)
        let sat = arachMix(saturateF(features.midAtt * 1.5),
                           saturateF(stems.otherEnergy * 1.5),
                           stemMix)
        let brt = 0.50 + lcg(&rng) * 0.45   // 0.50–0.95

        let seed = rng
        let hubX   = lcg(&rng) * 1.6 - 0.8       // −0.8..0.8 clip
        let hubY   = lcg(&rng) * 1.6 - 0.8
        let radius = 0.25 + lcg(&rng) * 0.30     // 0.25..0.55 clip
        let depth  = lcg(&rng)
        let rot    = lcg(&rng) * .pi * 2
        let anchors = UInt32(5) + UInt32(lcg(&rng) * 3.99)   // 5..8
        let revs   = 4.0 + lcg(&rng) * 4.0                   // 4..8

        webs[slot] = WebGPU(
            hubX: hubX,
            hubY: hubY,
            radius: radius,
            depth: depth,
            rotAngle: rot,
            anchorCount: anchors,
            spiralRevolutions: revs,
            rngSeed: seed,
            birthBeatPhase: globalBeatIndex,
            stage: WebStage.anchorPulse.rawValue,
            progress: 0,
            opacity: 1,
            birthHue: hue.truncatingRemainder(dividingBy: 1.0),
            birthSat: sat,
            birthBrt: brt,
            isAlive: 1
        )
    }

    // MARK: - Private: stage advancement

    private func advanceStage(index: Int, beatsDt: Float) {
        var web = webs[index]
        let stage = WebStage(rawValue: web.stage) ?? .stable

        switch stage {
        case .anchorPulse:
            web.progress = min(web.progress + beatsDt / Self.anchorPulseDuration, 1)
            if web.progress >= 1 { web.stage = WebStage.radial.rawValue; web.progress = 0 }

        case .radial:
            let dur = Self.radialDuration(web.anchorCount)
            web.progress = min(web.progress + beatsDt / dur, 1)
            if web.progress >= 1 { web.stage = WebStage.spiral.rawValue; web.progress = 0 }

        case .spiral:
            let dur = Self.spiralDuration(web.spiralRevolutions)
            web.progress = min(web.progress + beatsDt / dur, 1)
            if web.progress >= 1 { web.stage = WebStage.stable.rawValue; web.progress = 1 }

        case .stable:
            break

        case .evicting:
            web.progress = min(web.progress + beatsDt / Self.evictingDuration, 1)
            web.opacity = max(1 - web.progress, 0)
            if web.progress >= 1 { web = .zero }
        }

        webs[index] = web
    }

    // MARK: - Private: pool management

    private func freeSlot() -> Int? {
        webs.indices.first { webs[$0].isAlive == 0 }
    }

    /// Begin evicting an eligible web; returns nil (spawn will retry next frame).
    private func evictAndRetry() -> Int? {
        // Prefer oldest .stable web.
        let stableIndices = webs.indices.filter {
            webs[$0].isAlive != 0 && WebStage(rawValue: webs[$0].stage) == .stable
        }
        if let oldest = stableIndices.min(by: { webs[$0].birthBeatPhase < webs[$1].birthBeatPhase }) {
            webs[oldest].stage = WebStage.evicting.rawValue
            webs[oldest].progress = 0
            return nil
        }
        // Fallback: evict highest-progress building web (never .anchorPulse).
        let buildable = webs.indices.filter {
            guard webs[$0].isAlive != 0 else { return false }
            let webStage = WebStage(rawValue: webs[$0].stage) ?? .stable
            return webStage == .radial || webStage == .spiral
        }
        if let highest = buildable.max(by: { webs[$0].progress < webs[$1].progress }) {
            webs[highest].stage = WebStage.evicting.rawValue
            webs[highest].progress = 0
        }
        return nil
    }

    // MARK: - Private: initial pool seeding

    private func seedInitialWebs() {
        // Two pre-spun stable webs satisfy D-037 invariants 1 and 4 from frame zero.
        let seed0 = rng; _ = lcg(&rng)
        webs[0] = WebGPU(
            hubX: -0.35,
            hubY: 0.25,
            radius: 0.35,
            depth: 0,
            rotAngle: lcg(&rng) * .pi * 2,
            anchorCount: 6,
            spiralRevolutions: 5.5,
            rngSeed: seed0,
            birthBeatPhase: 0,
            stage: WebStage.stable.rawValue,
            progress: 1,
            opacity: 1,
            birthHue: 0.55,
            birthSat: 0.75,
            birthBrt: 0.70,
            isAlive: 1
        )
        let seed1 = rng; _ = lcg(&rng)
        webs[1] = WebGPU(
            hubX: 0.40,
            hubY: -0.30,
            radius: 0.40,
            depth: 0.35,
            rotAngle: lcg(&rng) * .pi * 2,
            anchorCount: 7,
            spiralRevolutions: 5.5,
            rngSeed: seed1,
            birthBeatPhase: 0,
            stage: WebStage.stable.rawValue,
            progress: 1,
            opacity: 1,
            birthHue: 0.80,
            birthSat: 0.75,
            birthBrt: 0.70,
            isAlive: 1
        )
        webCount = 2
    }

    // MARK: - Private: GPU write

    private func writeToGPU() {
        let ptr = webBuffer.contents().bindMemory(to: WebGPU.self, capacity: Self.maxWebs)
        lock.withLock {
            for i in 0..<Self.maxWebs { ptr[i] = webs[i] }
        }
    }

    // MARK: - Private: PRNG (LCG)

    @discardableResult
    private func lcg(_ seed: inout UInt32) -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 8) / Float(1 << 24)
    }

    // MARK: - Private: math helpers

    private func centroidToHue(_ centroid: Float) -> Float {
        // Log-map spectral centroid [0,1] → hue [0.15, 0.85] for vivid bioluminescent palette.
        0.15 + centroid * 0.70
    }

    private func arachSmoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let value = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return value * value * (3 - 2 * value)
    }

    private func arachMix(_ from: Float, _ to: Float, _ factor: Float) -> Float { from + (to - from) * factor }
    private func saturateF(_ x: Float) -> Float { min(max(x, 0), 1) }
    private func clamp(_ x: Float, min lo: Float, max hi: Float) -> Float { min(max(x, lo), hi) }
}
