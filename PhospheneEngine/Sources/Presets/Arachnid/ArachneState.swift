// ArachneState — Per-preset world state for the Arachne mesh-shader preset (Increment 3.5.5).
// swiftlint:disable file_length
//
// Manages a fixed pool of up to `maxWebs` webs (V.7.5 §10.1.1: 4). Each web
// progresses through stages
// (.anchorPulse → .radial → .spiral → .stable → .evicting) measured in beats,
// so spinning is slower on slow music and faster on fast music — a
// Phosphene-exclusive behavior derived from MV-3b BeatPredictor.
//
// The `webBuffer` MTLBuffer carries WebGPU structs (64 bytes each) that the
// Arachne mesh shader reads at object/mesh buffer(1) to determine which webs
// to render and how to build their geometry.
//
// Diagnostic build flags:
//   ARACHNE_DIAG     — one-shot per-slot stable-web parameters (geometry log).
//   ARACHNE_M7_DIAG  — once-per-second snapshot of pool occupancy + spawn cadence
//                      + spider trigger state + numeric proxies for silk-vs-drop
//                      luminance ratio. Used to verify V.7.5 step deltas
//                      (pool cap, drops-as-hero) numerically rather than visually.
//                      Activate with: -Xswiftc -DARACHNE_M7_DIAG.
//
// V.7.6.2 breadcrumb (TODO V.7.8): when ArachneState moves to the v8 design
// (foreground build cycle, ~60 s per ARACHNE_V8_DESIGN.md §1.2 step 4), it will
// emit `presetCompletionEvent` upon reaching the `.settle` stage so the
// orchestrator advances to the next planned segment. The PresetSignaling
// protocol and subscription wiring (VisualizerEngine+Presets) are already in
// place — only the emit point + Combine stored property are pending. Do NOT
// emit yet; current ArachneState is the V.7.5 mesh-pool state and has no
// natural completion.

import Metal
import Shared
import simd
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "Arachne")

// MARK: - WebStage

/// Lifecycle stage of a single web (V.7.9 — §5.2 60-second biology-correct cycle).
public enum WebStage: UInt32, Sendable {
    case frame    = 0   // Frame polygon draws first (bridge + outer polygon, 0–3 s)
    case radial   = 1   // Radial spokes extend alternating-pair, one by one (3–25 s)
    case spiral   = 2   // Capture spiral winds inward chord-by-chord (25–55 s)
    case stable   = 3   // Fully spun; quivers to audio
    case evicting = 4   // Fading out to make room in the pool
}

// MARK: - WebGPU

/// GPU-side web descriptor — 80 bytes (20 × 4-byte words, 5 rows of 4).
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

    // Row 4: global mood — written identically to all slots each frame by _tick().
    // drawWorld() in Arachne.metal reads webs[0].row4 for the V.7.7 WORLD palette.
    public var moodData: SIMD4<Float> = .zero  // x=smoothedValence, y=smoothedArousal, z=accTime, w=reserved

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

    // V.7.5 §10.1.1: pool capped to 4 (was 12) for single hero composition.
    // 2 slots are pre-seeded; the remaining 2 transient slots churn slowly so
    // the composition does not feel busy. minSpawnGapBeats raised 2→8 to slow
    // spawn cadence to ~one transient web every 4 s at 120 BPM.
    public static let maxWebs: Int = 4
    static let spawnThreshold: Float = 3.0
    static let minSpawnGapBeats: Float = 8.0

    // Stage durations in beats (V.7.9 — calibrated to §5.2 60-second cycle at 120 BPM).
    // Frame:   6 beats ≈  3 s at 120 BPM  (§5.2: Frame 0–3 s)
    // Radial: ~42 beats ≈ 21 s at 120 BPM (§5.2: Radials 3–25 s, ~1.5 s each)
    // Spiral:  60 beats =  30 s at 120 BPM (§5.2: Capture spiral 25–55 s)
    // Total: ~108 beats ≈ 54 s — within the 60 s ceiling.
    static let frameDuration: Float = 6.0
    static func radialDuration(_ anchorCount: UInt32) -> Float {
        Float(anchorCount) * 6.5          // 5→32.5, 8→52 beats; avg ~42 beats ≈ 21 s at 120 BPM
    }
    static func spiralDuration(_ revolutions: Float) -> Float {
        max(60.0, revolutions * 8.0)      // ≥60 beats (30 s at 120 BPM); 4–8 revs → 60–64 beats
    }
    static let evictingDuration: Float = 4.0

    // MARK: - Public Properties

    /// GPU-side web descriptor array — bound at object/mesh buffer(1) each frame.
    public let webBuffer: MTLBuffer

    /// Number of alive webs this frame (updated by tick).
    public private(set) var webCount: Int = 0

    /// Spawn accumulator exposed for diagnostics.
    public private(set) var spawnAccumulator: Float = 0

    // MARK: - Spider State (Increment 3.5.9)

    /// GPU-side spider descriptor buffer — 80 bytes; bound at fragment buffer(7).
    public let spiderBuffer: MTLBuffer
    var spiderBlend: Float = 0
    var spiderActive: Bool = false
    var sustainedSubBassAccumulator: Float = 0
    var timeSinceLastSpider: Float = 300.0  // starts at cooldown so first song can trigger
    var spiderPosX: Float = 0; var spiderPosY: Float = 0; var spiderHeading: Float = 0
    var spiderLegPhase: Float = 0
    var spiderLegTips: [SIMD2<Float>] = Array(repeating: .zero, count: 8)

    // V.7.7D listening-pose state — CPU-side only. The shader stays oblivious;
    // listening pose is realised by lifting tip[0]/tip[1] before the GPU flush.
    // Keeping this CPU-side preserves the V.7.7B 80-byte ArachneSpiderGPU contract.
    var listenLiftAccumulator: Float = 0
    var listenLiftEMA: Float = 0

    #if DEBUG
    /// Force the spider active regardless of organic trigger conditions. DEBUG builds only.
    /// Does not modify the organic trigger accumulator or cooldown state.
    public var forceSpiderActive: Bool = false
    #endif

    // MARK: - Private State

    var webs: [WebGPU]
    var globalBeatIndex: Float = 0
    /// Beat-index at last spawn fire. Internal so M7 diag extension can read.
    var lastSpawnBeatIndex: Float = -10
    private var prevBeatPhase01: Float = 0
    private var prevBeatComposite: Float = 0
    var rng: UInt32

    // Mood smoothing for WORLD palette (V.7.7 — ARACHNE_V8_DESIGN.md §4.3).
    // 5s low-pass filter; protected by lock (written in _tick, never read externally).
    private var smoothedValence: Float = 0.0
    private var smoothedArousal: Float = 0.0

    let lock = NSLock()
    #if DEBUG && ARACHNE_DIAG
    private var loggedStableSlots: Set<Int> = []
    #endif
    #if DEBUG && ARACHNE_M7_DIAG
    /// Last `Int(globalBeatIndex / 2)` bucket logged. Internal so M7 diag extension can read.
    var lastM7DiagBucket: Int = -1
    #endif

    // MARK: - Init

    /// Creates a new ArachneState with 2 initial stable webs pre-seeded.
    ///
    /// - Parameters:
    ///   - device: Metal device for buffer allocation.
    ///   - seed: Deterministic seed — same seed + same frame inputs → identical output.
    public init?(device: MTLDevice, seed: UInt32 = 42) {
        let webBufSize = Self.maxWebs * MemoryLayout<WebGPU>.stride
        guard let wBuf = device.makeBuffer(length: webBufSize, options: .storageModeShared) else {
            logger.error("ArachneState: failed to allocate webBuffer (\(webBufSize) bytes)")
            return nil
        }
        let spiderBufSize = MemoryLayout<ArachneSpiderGPU>.stride
        guard let sBuf = device.makeBuffer(length: spiderBufSize, options: .storageModeShared) else {
            logger.error("ArachneState: failed to allocate spiderBuffer (\(spiderBufSize) bytes)")
            return nil
        }
        webBuffer = wBuf
        spiderBuffer = sBuf
        webs = Array(repeating: .zero, count: Self.maxWebs)
        rng = seed
        seedInitialWebs()
        writeToGPU()
        sBuf.contents().bindMemory(to: ArachneSpiderGPU.self, capacity: 1)[0] = .zero
    }

    // MARK: - Public API

    /// Update web pool and spider state for one rendered frame, then flush to GPU buffers.
    ///
    /// Called once per frame by the RenderPipeline tick hook before mesh draw.
    public func tick(features: FeatureVector, stems: StemFeatures) {
        lock.withLock { _tick(features: features, stems: stems) }
        writeToGPU()
        writeSpiderToGPU()
    }

    // MARK: - Private: tick (called while holding lock)

    private func _tick(features: FeatureVector, stems: StemFeatures) {
        let dt = max(features.deltaTime, 0.001)

        // Advance globalBeatIndex from beat_phase01 (wraparound-safe; 120 BPM fallback).
        let beatsDt = advanceBeatIndex(features: features, dt: dt)

        // V.7.7: 5s low-pass mood smoothing for WORLD palette (ARACHNE_V8_DESIGN.md §4.3).
        // dt / 5.0 is the RC fraction per frame; clamped to 1.0 to prevent overshoot.
        smoothedValence += (features.valence - smoothedValence) * min(dt / 5.0, 1.0)
        smoothedArousal += (features.arousal - smoothedArousal) * min(dt / 5.0, 1.0)
        let moodRow = SIMD4<Float>(smoothedValence, smoothedArousal, features.accumulatedAudioTime, 0)
        for i in 0..<Self.maxWebs { webs[i].moodData = moodRow }

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
            if let slot = freeSlot() {
                trySpawn(features: features, stems: stems, stemMix: stemMix, slot: slot)
            } else {
                _ = evictAndRetry()
            }
        }

        // Advance all alive web stages.
        for i in 0..<Self.maxWebs where webs[i].isAlive != 0 {
            advanceStage(index: i, beatsDt: beatsDt)
        }

        webCount = webs.filter { $0.isAlive != 0 }.count

        updateSpider(dt: dt, features: features, stems: stems)

        #if DEBUG && ARACHNE_M7_DIAG
        m7DiagSnapshot(features: features)
        #endif

        #if DEBUG && ARACHNE_DIAG
        for i in 0..<Self.maxWebs
            where webs[i].isAlive != 0
            && WebStage(rawValue: webs[i].stage) == .stable
            && !loggedStableSlots.contains(i) {
            loggedStableSlots.insert(i)
            let web    = webs[i]
            let spokes = Self.diagSpokeCount(seed: web.rngSeed)
            let asp    = Self.diagAspect(seed: web.rngSeed)
            let ang    = Self.diagAspectAngle(seed: web.rngSeed)
            let ksag   = Self.diagKSag(seed: web.rngSeed)
            let jx     = (Self.diagHash(web.rngSeed &+ 0xE5) - 0.5) * 0.10
            let jy     = (Self.diagHash(web.rngSeed &+ 0xF6) - 0.5) * 0.10
            logger.debug("""
                ARACHNE_DIAG slot=\(i) seed=\(web.rngSeed) \
                hub=(x:\(web.hubX, format: .fixed(precision: 3)) \
                y:\(web.hubY, format: .fixed(precision: 3))) \
                jitter=(dx:\(jx, format: .fixed(precision: 3)) \
                dy:\(jy, format: .fixed(precision: 3))) \
                radius=\(web.radius, format: .fixed(precision: 3)) \
                spokes=\(spokes) aspect=\(asp, format: .fixed(precision: 3)) \
                aspectAngle=\(ang, format: .fixed(precision: 3)) \
                kSag=\(ksag, format: .fixed(precision: 4))
                """)
        }
        #endif
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

    private func trySpawn(features: FeatureVector, stems: StemFeatures, stemMix: Float, slot: Int) {
        lastSpawnBeatIndex = globalBeatIndex

        // Per-slot golden-ratio hue so each web slot has a distinct, evenly
        // distributed color. Small centroid jitter (±0.03) prevents adjacent spawns
        // looking identical even when the same slot is reused.
        let centroidJitter = arachMix(features.spectralCentroid,
                                      stems.otherCentroid,
                                      stemMix) * 0.06 - 0.03
        let rawHue = Float(slot) * 0.618 + centroidJitter
        // Map golden-ratio 0-1 to bioluminescent palette: cyan (0.42) → blue → violet (0.82).
        let hue = 0.42 + (rawHue - floor(rawHue)) * 0.40
        let sat = 0.88 + lcg(&rng) * 0.10   // 0.88–0.98, always vivid
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
            stage: WebStage.frame.rawValue,
            progress: 0,
            opacity: 1,
            birthHue: hue,
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
        case .frame:
            web.progress = min(web.progress + beatsDt / Self.frameDuration, 1)
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
            birthHue: 0 * 0.618,                              // slot 0 → 0.000 red-magenta
            birthSat: 0.92,
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
            birthHue: 1 * 0.618,                              // slot 1 → 0.618 cyan-blue
            birthSat: 0.92,
            birthBrt: 0.70,
            isAlive: 1
        )
        webCount = 2
    }

    // MARK: - Private: PRNG (LCG)

    @discardableResult
    func lcg(_ seed: inout UInt32) -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 8) / Float(1 << 24)
    }

    // MARK: - Private: Diagnostic helpers (mirrors Metal arachHash + seed-derived funcs)
    // These reproduce the Metal-shader math so diagnostic logs match render output.

    #if DEBUG && ARACHNE_DIAG
    static func diagHash(_ seed: UInt32) -> Float {
        var sv = seed
        sv = (sv ^ 61) ^ (sv >> 16)
        sv = sv &* 9
        sv ^= sv >> 4
        sv = sv &* 0x27d4eb2d
        sv ^= sv >> 15
        return Float(sv) * Float(1.0 / 4_294_967_296.0)
    }
    static func diagSpokeCount(seed: UInt32) -> Int { 11 + Int(diagHash(seed &+ 0xA1) * 6.99) }
    static func diagAspect(seed: UInt32) -> Float { 0.85 + diagHash(seed &+ 0xB2) * 0.30 }
    static func diagAspectAngle(seed: UInt32) -> Float { diagHash(seed &+ 0xC3) * 2.0 * .pi }
    /// V.7.5 §10.1.2: must match arachKSag in Arachne.metal — range [0.06, 0.14].
    static func diagKSag(seed: UInt32) -> Float { 0.06 + diagHash(seed &+ 0xD4) * 0.08 }
    #endif
}
