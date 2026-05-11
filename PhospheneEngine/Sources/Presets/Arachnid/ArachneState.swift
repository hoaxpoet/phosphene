// ArachneState — Per-preset world state for the Arachne mesh-shader preset (Increment 3.5.5).
// swiftlint:disable file_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_body_length
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

import Combine
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

/// GPU-side web descriptor — 96 bytes (24 × 4-byte words, 6 rows of 4) post-V.7.7C.2.
/// Must match `ArachneWebGPU` in Arachne.metal byte-for-byte.
///
/// V.7.7C.2 (D-095) extends the struct from 80 → 96 bytes by appending a Row 5
/// of 4 individual `Float` fields carrying packed BuildState — `buildStage`,
/// `frameProgress`, `radialPacked` (radialIndex + radialProgress), and
/// `spiralPacked` (spiralChordIndex + spiralChordProgress). Row 5 is written
/// only for the foreground hero web (`webs[0]`); background webs zero it.
///
/// **Important**: the four Row 5 fields are individual `Float`s, NOT a
/// `SIMD4<Float>`. `SIMD4<Float>` carries 16-byte alignment, which would push
/// the struct stride past 96 bytes on Apple Silicon. Keep them as four
/// adjacent `Float` fields and append them at the END of the struct so byte
/// offsets for rows 0–4 stay byte-identical (the shader reads those rows in
/// V.7.7C.2 Commit 2 — Row 5 reads land in Commit 3).
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

    // Row 5 (V.7.7C.2): foreground BuildState packed for the shader's Commit 3 read.
    // Background webs zero this row (no progressive build).
    /// `WebStage.rawValue` of the foreground build (0 = .frame, …, 4 = .evicting).
    public var buildStage: Float = 0
    /// 0..1 within the frame phase.
    public var frameProgress: Float = 0
    /// `radialIndex + radialProgress` (e.g. 5.42 = radial 5 drawn 42 % into the next).
    public var radialPacked: Float = 0
    /// `spiralChordIndex + spiralChordProgress`.
    public var spiralPacked: Float = 0

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

// MARK: - BuildState (V.7.7C.2 / D-095)

/// CPU-side build state for the single foreground hero web.
///
/// All progress values are in `[0, 1]` within their respective phases.
/// `pausedBySpider: Bool` — when true (set whenever `spiderBlend > 0.01`), the
/// per-tick advance skips on all `*Progress` fields.
///
/// The build advances on a *time* basis (seconds since segment start, minus
/// paused time), modulated by audio per V.7.7C.2 §7. Beats are NOT used for
/// stage advancement — V.7.5's beat-measured stage timing was admitted in
/// `ARACHNE_V8_DESIGN.md §5.2` to be wrong; build pace must scale with audio
/// energy, not metronome time.
///
/// Commit 2 stores the build state in CPU memory and writes a packed Row 5 of
/// `WebGPU` for the foreground hero web (`webs[0]`). The shader does NOT read
/// Row 5 yet — Commit 3 wires the read.
public struct ArachneBuildState: Sendable {

    // MARK: - Phase constants (V.7.7C.2 §5.2; tuned for ~50–55 s at average music)

    /// Total seconds of effective time the frame phase consumes.
    public static let frameDurationSeconds: Float = 3.0
    /// Seconds of effective time per radial during the radial phase.
    public static let radialDurationSeconds: Float = 1.5
    /// Seconds of effective time per chord during the spiral phase.
    public static let spiralChordDurationSeconds: Float = 0.3
    /// Seconds of effective time the evicting phase takes to fade out.
    public static let evictingDurationSeconds: Float = 1.0
    /// Pace coefficient on `mid_att_rel` (continuous, primary driver).
    public static let paceMidCoefficient: Float = 0.18
    /// Pace coefficient on `drums_energy_dev` (per-frame accent, secondary).
    public static let paceDrumCoefficient: Float = 0.5
    /// Spider-blend threshold above which build advance pauses.
    public static let spiderPauseThreshold: Float = 0.01

    // MARK: - Frame phase

    /// 0..1 over the frame phase.
    public var frameProgress: Float = 0
    /// Indices into `anchors` for the bridge thread's two endpoints.
    public var bridgeAnchorPairFirst: Int = 0
    /// Indices into `anchors` for the bridge thread's two endpoints.
    public var bridgeAnchorPairSecond: Int = 1

    // MARK: - Polygon (selected at segment start; subset of branchAnchors)

    /// Selected branchAnchors indices (4–6 entries) sorted in angular order
    /// around the centroid. The polygon vertex at edge i is `anchors[i]`.
    public var anchors: [Int] = []
    /// 0..1 per polygon vertex; ramps as the frame thread reaches each anchor.
    public var anchorBlobIntensities: [Float] = []

    // MARK: - Radial phase

    /// Total radial spokes, chosen at segment start ∈ [18, 24].
    /// BUG-011 follow-up — bumped from [12, 17] to [18, 24] (median 13 → 21)
    /// per Matt's 2026-05-11 "more intricate webs" product call. Combined
    /// with the spiralRevolutions bump (8 → 16) this brings median cell
    /// count from ~104 to ~336 per completed web.
    public var radialCount: Int = 21
    /// Current radial being drawn (0..radialCount-1).
    public var radialIndex: Int = 0
    /// 0..1 within the current radial.
    public var radialProgress: Float = 0
    /// Pre-computed alternating-pair draw order per V.7.7C.2 §5.5.
    public var radialDrawOrder: [Int] = []

    // MARK: - Spiral phase

    /// Total revolutions for the capture spiral, chosen at segment start ∈ [14, 18].
    /// BUG-011 follow-up — bumped from [7, 9] to [14, 18] (median 8 → 16) per
    /// Matt's 2026-05-11 "more intricate webs" product call. ~2× the rings
    /// roughly doubles the spiral phase duration (8 × 8 = 64 beats → 16 × 8 =
    /// 128 beats, see `spiralDuration`) — the build now takes ~87s at 120 BPM
    /// instead of ~55s, but Love-Rehab-scale segments accommodate it.
    public var spiralRevolutions: Float = 16.0
    /// `revolutions × radialCount`; pre-computed at spiral-phase entry.
    public var spiralChordsTotal: Int = 0
    /// Current chord being laid (0..spiralChordsTotal-1).
    public var spiralChordIndex: Int = 0
    /// 0..1 within the current chord.
    public var spiralChordProgress: Float = 0
    /// `stageElapsed` at the moment chord k is laid; `count == spiralChordIndex`.
    /// Used by the shader's §5.8 drop accretion in Commit 3.
    public var spiralChordBirthTimes: [Float] = []
    /// Per-chord precomputed radius (UV); strictly decreasing (INWARD).
    public var spiralChordRadii: [Float] = []

    // MARK: - Stage / global

    /// Current stage of the foreground build cycle.
    public var stage: WebStage = .frame
    /// Effective seconds elapsed since the current `stage` was entered.
    public var stageElapsed: Float = 0
    /// `true` while spider blend > 0.01; freezes all `*Progress` fields.
    public var pausedBySpider: Bool = false
    /// Effective seconds since segment start (cumulative across phases).
    public var segmentElapsed: Float = 0
    /// True after the .stable transition has fired the completion event;
    /// reset only by `ArachneState.reset()`.
    public var completionEmitted: Bool = false

    // MARK: - Diagnostics (used by tests; not on the GPU contract)

    /// Effective `stageElapsed` at which the frame→radial transition fired.
    /// `nil` until the frame phase completes.
    public var frameToRadialAtElapsed: Float?
    /// Effective `stageElapsed` at which the radial→spiral transition fired.
    public var radialToSpiralAtElapsed: Float?
    /// Effective `stageElapsed` at which the spiral→stable transition fired.
    public var spiralToStableAtElapsed: Float?

    public static func zero() -> ArachneBuildState { ArachneBuildState() }
}

// MARK: - BackgroundWeb (V.7.7C.2 §5.12)

/// A finished saturated web that decorates the depth backdrop.
///
/// 1–2 entries on `ArachneState`; their build state is trivially full
/// (`stage = .stable`, all radials drawn, all spiral chords laid, all drops at
/// max count). They do NOT advance — they're already finished.
///
/// Commit 2 owns the CPU-side state machine (capacity 2, migration on
/// completion). The shader reads them in Commit 3.
public struct ArachneBackgroundWeb: Sendable {
    /// Full GPU-form web descriptor (Row 5 zeroed — no progressive build).
    public var webGPU: WebGPU
    /// `ArachneState.segmentClock` value at construction; oldest is evicted first.
    public var birthTime: Float
    /// 1.0 by default; ramps 1→0 during eviction (`migrateOnCompletion`).
    public var opacity: Float

    public init(webGPU: WebGPU, birthTime: Float, opacity: Float = 1.0) {
        self.webGPU = webGPU
        self.birthTime = birthTime
        self.opacity = opacity
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

    // V.7.7C.5 §5.3 / Q14 (D-100) — single source of truth for polygon
    // anchor positions. The WEB pillar's polygon-from-anchors path
    // (`packPolygonAnchors` → shader `decodePolygonAnchors`) consumes these
    // as polygon vertex sources. The §4 atmospheric reframe (D-100) retired
    // the WORLD-side capsule-twig SDF that previously also consumed these
    // positions; the constants now serve the polygon path only.
    //
    // V.7.7C.5 update: positions moved to or just past the visible UV
    // border so the WEB threads enter the canvas from outside, matching
    // ref `20_macro_backlit_purple_canvas_filling_web.jpg` (Matt
    // 2026-05-09). All entries lie in `[-0.06, 1.06]² \ [0,1]²`. Distribution
    // is asymmetric (no two opposing-edge anchors share the same vertical
    // position), so polygons drawn from any 4–6-subset still read as
    // irregular per §5.3.
    //
    // MUST stay byte-for-byte in sync with `kBranchAnchors[6]` near
    // line ~153 of Arachne.metal. `ArachneBranchAnchorsTests` regression-locks
    // the sync by string-searching the .metal source for matching float pairs.
    public static let branchAnchors: [SIMD2<Float>] = [
        SIMD2(-0.05, 0.05),  // upper-left, off-canvas
        SIMD2(1.05, 0.02),   // upper-right, off-canvas (slightly higher)
        SIMD2(1.06, 0.52),   // right, off-canvas
        SIMD2(1.04, 0.97),   // lower-right, off-canvas
        SIMD2(-0.04, 0.95),  // lower-left, off-canvas
        SIMD2(-0.06, 0.48)   // left, off-canvas
    ]

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
    /// V.7.7C.2 — replaces V.7.5's 300 s session cooldown (D-095 / §6.5).
    /// Spider may fire AT MOST ONCE per Arachne segment. Reset by `reset()`.
    var spiderFiredInSegment: Bool = false
    /// Pre-V.7.7C.2 V.7.5 session-cooldown timer. **Deprecated** — superseded
    /// by `spiderFiredInSegment`. Kept as a no-op stub so the
    /// `ARACHNE_M7_DIAG` diagnostic build (`ArachneState+M7Diag.swift`)
    /// continues to compile against the same name. The field is no longer
    /// updated; the diag log will print a constant value.
    var timeSinceLastSpider: Float = 300.0
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
    /// V.7.7C.4 / D-095 follow-up — rising-edge tracker for the hybrid audio
    /// coupling. `advanceSpiralPhase` advances `spiralChordIndex` by 1 on
    /// each rising-edge beat (in addition to the time-based pace), so the
    /// chord laydown reads as "TIME pace + per-beat kick". Internal so
    /// `advanceSpiralPhase` can read; reset on `arachneState.reset()`.
    var prevBeatForSpiral: Float = 0
    var rng: UInt32

    // Mood smoothing for WORLD palette (V.7.7 — ARACHNE_V8_DESIGN.md §4.3).
    // 5s low-pass filter; protected by lock (written in _tick, never read externally).
    private var smoothedValence: Float = 0.0
    private var smoothedArousal: Float = 0.0

    // V.7.7C.2 (D-095) — foreground build state machine. CPU-side only in
    // Commit 2; the shader's Row 5 read lands in Commit 3. Internal access
    // exposes the state to ArachneStateBuildTests via @testable import.
    var buildState: ArachneBuildState = .zero()
    /// 1–2 saturated background webs (capacity 2). Migration on completion
    /// pushes the foreground hero into this pool; oldest is evicted at capacity.
    var backgroundWebs: [ArachneBackgroundWeb] = []
    /// Capacity of `backgroundWebs`; oldest evicted on overflow.
    public static let backgroundWebsCapacity: Int = 2
    /// Wall-clock seconds since the most recent `reset()` (segment start).
    /// Drives `BackgroundWeb.birthTime` ordering and migration crossfade timing.
    var segmentClock: Float = 0
    /// 1 s migration crossfade clock; nil when no migration in flight.
    var migrationCrossfadeElapsed: Float?

    /// V.7.7C.2 — fires once when the foreground build cycle reaches `.stable`.
    /// Subscribed by `VisualizerEngine+Presets.wirePresetCompletionSubscription`
    /// via the `PresetSignaling` protocol conformance defined in
    /// `Sources/Orchestrator/ArachneStateSignaling.swift`. The conformance
    /// lives in the Orchestrator module — Presets cannot depend on
    /// Orchestrator without creating a cycle. Reset on `reset()` via
    /// `buildState.completionEmitted = false`. Public so the cross-module
    /// conformance can reach it. The `_`-prefix follows the Swift convention
    /// of pairing a backing Combine subject with a published computed
    /// property (here, `presetCompletionEvent` in
    /// `ArachneStateSignaling.swift`).
    public let _presetCompletionEvent = // swiftlint:disable:this identifier_name
        PassthroughSubject<Void, Never>()

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
        let beatsDt = advanceBeatIndex(features: features, dt: dt)
        updateMoodRow(features: features, dt: dt)

        // D-019 warmup blend: 0 = FV only, 1 = stems fully warm.
        let totalStemEnergy = stems.drumsEnergy + stems.bassEnergy
                            + stems.otherEnergy + stems.vocalsEnergy
        let stemMix = arachSmoothstep(0.02, 0.06, totalStemEnergy)

        accumulateSpawn(features: features, stems: stems, stemMix: stemMix, dt: dt)

        // Advance all alive web stages.
        for i in 0..<Self.maxWebs where webs[i].isAlive != 0 {
            advanceStage(index: i, beatsDt: beatsDt)
        }
        webCount = webs.filter { $0.isAlive != 0 }.count

        updateSpider(dt: dt, features: features, stems: stems)

        // V.7.7C.2 — advance the foreground BuildState. Runs in addition to
        // (not in place of) the V.7.5 spawn/eviction driver above; in Commit 2
        // both coexist because the shader does not yet read Row 5. Commit 3
        // hooks the shader to Row 5 and removes the V.7.5 driver. The pause
        // guard MUST be evaluated before computing `effectiveDt` — order
        // matters per V.7.7C.2 RISKS.
        advanceBuildState(features: features, stems: stems, dt: dt)
        // Maintain background-web migration timers and write Row 5 for webs[0].
        advanceMigrationCrossfade(dt: dt)
        writeBuildStateToWebs0()

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

    // MARK: - Private: per-tick helpers extracted from `_tick`

    /// V.7.7: 5 s low-pass mood smoothing → all webs' Row 4 (`moodData`).
    /// Read by `drawWorld()` for the WORLD palette (ARACHNE_V8_DESIGN.md §4.3).
    private func updateMoodRow(features: FeatureVector, dt: Float) {
        // dt / 5.0 is the RC fraction per frame; clamped to 1.0 to prevent overshoot.
        smoothedValence += (features.valence - smoothedValence) * min(dt / 5.0, 1.0)
        smoothedArousal += (features.arousal - smoothedArousal) * min(dt / 5.0, 1.0)
        let accTime = features.accumulatedAudioTime
        let moodRow = SIMD4<Float>(smoothedValence, smoothedArousal, accTime, 0)
        for i in 0..<Self.maxWebs { webs[i].moodData = moodRow }
    }

    /// V.7.5 spawn driver — drum-onset accumulator + FV beat-rising-edge
    /// fallback. Shared with V.7.7C.2 in Commit 2 because the shader has not
    /// yet been hooked to the BuildState Row 5; this driver still owns the
    /// visible web pool.
    private func accumulateSpawn(features: FeatureVector,
                                 stems: StemFeatures,
                                 stemMix: Float,
                                 dt: Float) {
        // Stem path: drumsOnsetRate [onsets/sec] × dt → fraction of spawn threshold.
        let drumDrive = stems.drumsOnsetRate * dt * stemMix

        // FV fallback: rising edge on beat_composite / beat_bass counts as one onset.
        // Suppressed by actual drum activity, not by general stem warmup — so
        // quiet/drumless tracks (post-rock openings, drumsOnsetRate=0 but stems
        // warm) still get a working spawn path from the beat detector.
        let currentBeat = max(features.beatComposite, features.beatBass)
        let risingEdge: Float = (currentBeat > 0.5 && prevBeatComposite <= 0.5) ? 0.8 : 0.0
        prevBeatComposite = currentBeat
        // Fully suppressed at ≥ 20 onsets/s.
        let drumActivity = min(stems.drumsOnsetRate * 0.05, 1.0)
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
        // V.7.7C.5 (D-100 / Q15) — `webs[0]` (foreground hero) hub moved to
        // canvas centre and radius bumped 0.35 → 1.10 so the shader-side
        // `webR = radius × 0.5 ≈ 0.55` aligns with the canvas-filling
        // foreground. The shader's `arachne_composite_fragment` foreground
        // anchor block hardcodes its own UV/webR (currently (0.5, 0.5) /
        // 0.55), so these CPU values are not consumed for rendering — but
        // keeping the CPU mirror in sync prevents drift between Swift and
        // MSL at slot-6 buffer reads (`ArachneWebGPU.row0` carries hub_x,
        // hub_y, radius for any future readers).
        let seed0 = rng; _ = lcg(&rng)
        webs[0] = WebGPU(
            hubX: 0.0,
            hubY: 0.0,
            radius: 1.10,
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

    // MARK: - Build state advance (V.7.7C.2 / D-095)

    /// Advance the foreground BuildState by one frame.
    ///
    /// Called from `_tick` while the lock is held. Implements the V.7.7C.2 §7
    /// per-tick advance: spider pause guard → audio-modulated pace → effective
    /// dt → phase routing. The completion event fires exactly once when the
    /// build cycle reaches `.stable`.
    func advanceBuildState(features: FeatureVector, stems: StemFeatures, dt: Float) {
        // 1. Pause guard MUST be evaluated before computing effectiveDt.
        let spiderPaused = spiderBlend > ArachneBuildState.spiderPauseThreshold
        buildState.pausedBySpider = spiderPaused

        // 2. Audio-modulated pace per §7. D-026: continuous coefficient
        // 0.18 × mid_att_rel dominates per-frame accent 0.5 × drums_energy_dev
        // (typical peaks 0.05–0.07) by ~3.6×, well above the 2× rule.
        let midBoost = ArachneBuildState.paceMidCoefficient * features.midAttRel
        let drumAccent = ArachneBuildState.paceDrumCoefficient * stems.drumsEnergyDev
        let pace: Float = 1.0 + midBoost + max(0, drumAccent)

        let effectiveDt: Float = spiderPaused ? 0 : dt * pace
        buildState.segmentElapsed += effectiveDt
        segmentClock += dt

        // 3. Route by stage. Each helper updates `stageElapsed` + its phase
        // accumulators, and triggers transitions internally.
        switch buildState.stage {
        case .frame:
            advanceFramePhase(by: effectiveDt)
        case .radial:
            advanceRadialPhase(by: effectiveDt)
        case .spiral:
            advanceSpiralPhase(by: effectiveDt, features: features)
        case .stable:
            advanceStablePhase(by: effectiveDt)
        case .evicting:
            advanceEvictingPhase(by: effectiveDt)
        }
    }

    private func advanceFramePhase(by effectiveDt: Float) {
        buildState.stageElapsed += effectiveDt
        let dur = ArachneBuildState.frameDurationSeconds
        buildState.frameProgress = min(1, buildState.stageElapsed / dur)

        // Anchor blob intensities ramp 0→1 over 0.5 s after the frame thread
        // reaches each anchor. The frame thread "reaches" anchor i at
        // stageElapsed = (i / anchorCount) * frameDuration.
        let anchorCount = max(buildState.anchors.count, 1)
        for i in 0..<buildState.anchorBlobIntensities.count {
            let reachedAtElapsed = Float(i) / Float(anchorCount) * dur
            let elapsedSinceReach = buildState.stageElapsed - reachedAtElapsed
            let raw = max(0, min(1, elapsedSinceReach / 0.5))
            buildState.anchorBlobIntensities[i] = raw
        }

        if buildState.stageElapsed >= dur {
            buildState.frameToRadialAtElapsed = buildState.stageElapsed
            buildState.stage = .radial
            buildState.stageElapsed = 0
            buildState.frameProgress = 1.0
            // Pre-compute spiral chord radii at the moment we step out of frame
            // so they're ready when the radial phase finishes. Pitch is the
            // spiral's per-revolution radial step; outer/inner radii are the
            // foreground hero's web radius and a small core (UV space).
            recomputeSpiralChordTable()
        }
    }

    private func advanceRadialPhase(by effectiveDt: Float) {
        buildState.stageElapsed += effectiveDt
        let perRadial = ArachneBuildState.radialDurationSeconds
        let count = buildState.radialCount
        // Incremental advance — do NOT recompute index/progress from
        // stageElapsed each frame, because external state (e.g. tests
        // pinning a pause-baseline) gets clobbered when effectiveDt is 0.
        // pause-resume must pick up exactly where it left off.
        buildState.radialProgress += effectiveDt / perRadial
        while buildState.radialProgress >= 1.0 && buildState.radialIndex < count {
            buildState.radialIndex += 1
            buildState.radialProgress -= 1.0
        }
        if buildState.radialIndex >= count {
            buildState.radialToSpiralAtElapsed = buildState.stageElapsed
            buildState.stage = .spiral
            buildState.stageElapsed = 0
            buildState.radialIndex = count
            buildState.radialProgress = 1.0
            buildState.spiralChordIndex = 0
            buildState.spiralChordProgress = 0
            buildState.spiralChordBirthTimes.removeAll(keepingCapacity: true)
        }
    }

    private func advanceSpiralPhase(by effectiveDt: Float, features: FeatureVector) {
        let total = buildState.spiralChordsTotal
        guard total > 0 else {
            buildState.stage = .stable
            buildState.stageElapsed = 0
            return
        }
        buildState.stageElapsed += effectiveDt
        let perChord = ArachneBuildState.spiralChordDurationSeconds
        buildState.spiralChordProgress += effectiveDt / perChord
        // Lay each chord on the boundary so birth times reflect lay order.
        while buildState.spiralChordProgress >= 1.0 && buildState.spiralChordIndex < total {
            buildState.spiralChordIndex += 1
            buildState.spiralChordBirthTimes.append(buildState.stageElapsed)
            buildState.spiralChordProgress -= 1.0
        }

        // V.7.7C.4 / D-095 follow-up — hybrid audio coupling. On rising-edge
        // beats (`beat_bass` or `beat_composite` crossing 0.5), advance
        // `spiralChordIndex` by 1 on top of the time-based pace. Keeps the
        // build clock TIME-driven (D-095 Decision 2 preserved — sparse-beat
        // tracks still complete in `naturalCycleSeconds`) while making the
        // chord laydown perceptibly couple to the music. Pause-guard
        // semantics preserved: `effectiveDt = 0` while spider is visible
        // means `prevBeatForSpiral` is still tracked but no chord advance
        // fires (the rising-edge check is gated on `effectiveDt > 0`).
        let beatNow = max(features.beatBass, features.beatComposite)
        let risingEdge = beatNow > 0.5 && prevBeatForSpiral <= 0.5
        if risingEdge && effectiveDt > 0 && buildState.spiralChordIndex < total {
            buildState.spiralChordIndex += 1
            buildState.spiralChordBirthTimes.append(buildState.stageElapsed)
        }
        prevBeatForSpiral = beatNow

        if buildState.spiralChordIndex >= total {
            buildState.spiralToStableAtElapsed = buildState.stageElapsed
            buildState.stage = .stable
            buildState.stageElapsed = 0
            buildState.spiralChordIndex = total
            buildState.spiralChordProgress = 0
        }
    }

    private func advanceStablePhase(by effectiveDt: Float) {
        buildState.stageElapsed += effectiveDt
        // Fire the completion event exactly once on entry to .stable.
        if !buildState.completionEmitted {
            buildState.completionEmitted = true
            _presetCompletionEvent.send()
            // Trigger the migration crossfade (1 s) on completion. Foreground
            // ramps 1→0.4; oldest background ramps 1→0 if pool at capacity.
            beginMigrationCrossfade()
        }
    }

    private func advanceEvictingPhase(by effectiveDt: Float) {
        buildState.stageElapsed += effectiveDt
        let dur = ArachneBuildState.evictingDurationSeconds
        if buildState.stageElapsed >= dur {
            // Evicting completes — the foreground build cycle is over for
            // this segment. The orchestrator decides what comes next; we sit
            // idle until a new `reset()` lands.
            buildState.stage = .stable
            buildState.stageElapsed = 0
        }
    }

    // MARK: - Spiral chord table

    /// Pre-compute `spiralChordsTotal` and `spiralChordRadii` from the current
    /// radialCount + spiralRevolutions. Strictly INWARD: chord k+1's radius
    /// is strictly less than chord k's radius (`test_spiralChordsAreInward`).
    /// Capped at 200 chords (V.7.7C.2 STOP CONDITION on degenerate cases).
    func recomputeSpiralChordTable() {
        let revs = buildState.spiralRevolutions
        let count = buildState.radialCount
        let total = min(200, max(0, Int(revs) * count))
        buildState.spiralChordsTotal = total
        buildState.spiralChordRadii.removeAll(keepingCapacity: true)
        buildState.spiralChordRadii.reserveCapacity(total)
        guard total > 0 else { return }

        let outerRadius: Float = 0.45  // UV; foreground hero's outer radius
        let innerRadius: Float = 0.05  // UV; small core
        let pitch = (outerRadius - innerRadius) / max(revs, 0.001)
        let radialF = Float(count)
        for k in 0..<total {
            let radius = outerRadius - (Float(k) / radialF) * pitch
            buildState.spiralChordRadii.append(radius)
        }
    }

    // MARK: - Row 5 GPU write

    /// Write the foreground BuildState into webs[0]'s Row 5 (V.7.7C.2). Other
    /// slots' Row 5 stays zeroed (background webs / unused). The shader does
    /// NOT read Row 5 in Commit 2 — Commit 3 wires the read.
    ///
    /// V.7.7C.3 / D-095 follow-up: also packs the polygon anchor indices
    /// (`bs.anchors[]`) into `webs[0].rngSeed` so the shader can reconstruct
    /// the irregular `branchAnchors[]` polygon vertices and ray-clip radial
    /// spokes against it. The V.7.5 driver no longer renders pool webs (per
    /// V.7.7C.3 shader-loop disable), so `rngSeed` is free for repurposing
    /// on the foreground hero slot. Layout: bits [0..3] = count (0–6),
    /// bits [4..7] = anchors[0], bits [8..11] = anchors[1], …,
    /// bits [24..27] = anchors[5]. Bits [28..31] are reserved.
    func writeBuildStateToWebs0() {
        guard !webs.isEmpty else { return }
        webs[0].buildStage = Float(buildState.stage.rawValue)
        webs[0].frameProgress = buildState.frameProgress
        webs[0].radialPacked = Float(buildState.radialIndex) + buildState.radialProgress
        webs[0].spiralPacked =
            Float(buildState.spiralChordIndex) + buildState.spiralChordProgress
        webs[0].rngSeed = Self.packPolygonAnchors(buildState.anchors)
    }

    /// V.7.7C.3 / D-095 follow-up — pack up to 6 polygon anchor indices into
    /// a single UInt32 for the shader's polygon-from-branchAnchors path.
    /// Each index is masked to 4 bits (range 0–5 fits cleanly).
    static func packPolygonAnchors(_ anchors: [Int]) -> UInt32 {
        var packed: UInt32 = UInt32(min(max(anchors.count, 0), 6)) & 0xF
        for (i, idx) in anchors.prefix(6).enumerated() {
            let safeIdx = UInt32(min(max(idx, 0), 5)) & 0xF
            packed |= safeIdx << UInt32(4 + i * 4)
        }
        return packed
    }

    // MARK: - Reset (V.7.7C.2 §5.2 — segment-start canonical entry point)

    /// Reset the foreground BuildState and per-segment cooldowns at the start
    /// of an Arachne segment.
    ///
    /// Call sites:
    ///   - `VisualizerEngine+Presets.applyPreset(_:)` `case .staged:` for
    ///     `desc.name == "Arachne"`, immediately after `ArachneState.init`.
    ///   - On track change while Arachne is active.
    ///
    /// Picks fresh `radialCount ∈ [12, 17]` and `spiralRevolutions ∈ [7, 9]`
    /// from `rng`; computes the polygon (rejecting the 6-evenly-spaced subset
    /// per §5.3 to avoid ref `09` anti-symmetry); computes `radialDrawOrder`
    /// per §5.5; resets `spiderFiredInSegment` (V.7.7C.2 Sub-item 8).
    public func reset() {
        lock.withLock { _reset() }
    }

    private func _reset() {
        // Fresh BuildState defaults.
        var bs = ArachneBuildState.zero()

        // BUG-011 follow-up — bumped per Matt's 2026-05-11 "more intricate webs"
        // call: radialCount ∈ [12, 17] → [18, 24]; spiralRevolutions ∈ [7, 9] →
        // [14, 18]. Median cell count goes from ~104 to ~336 per completed web.
        // Derived from rng so reset() is deterministic against `seed`.
        let radialCount = 18 + Int(lcg(&rng) * 6.99)        // 18..24
        let revolutions: Float = 14.0 + lcg(&rng) * 4.0    // 14..18
        bs.radialCount = radialCount
        bs.spiralRevolutions = revolutions
        bs.radialDrawOrder = Self.computeAlternatingPairOrder(radialCount: radialCount)

        // Polygon: select 4–6 of branchAnchors and order by angle around the
        // centroid. The 6-evenly-spaced subset is implicitly never produced
        // because branchAnchors is irregular by construction; the
        // `test_polygonSelectionIsIrregular` test verifies the angular gaps
        // never collapse to within ±2° of equal across 100 seeds.
        let polygon = Self.selectPolygon(rng: &rng)
        bs.anchors = polygon.anchors
        bs.anchorBlobIntensities = Array(repeating: 0, count: polygon.anchors.count)
        bs.bridgeAnchorPairFirst = polygon.bridgeFirst
        bs.bridgeAnchorPairSecond = polygon.bridgeSecond

        buildState = bs
        recomputeSpiralChordTable()

        // Per-segment spider cooldown reset (V.7.7C.2 Sub-item 8).
        spiderFiredInSegment = false
        // V.7.7C.4 — reset rising-edge tracker so the new segment's first
        // beat is treated as a real edge, not a spurious continuation.
        prevBeatForSpiral = 0

        // Migration crossfade clears.
        migrationCrossfadeElapsed = nil
        segmentClock = 0
    }

    // MARK: - Static helpers (radial draw order, polygon selection)

    /// V.7.7C.2 §5.5 alternating-pair radial draw order:
    /// `[0, n/2, 1, n/2+1, 2, n/2+2, …]`. For n=13:
    /// `[0, 6, 1, 7, 2, 8, 3, 9, 4, 10, 5, 11, 12]`.
    public static func computeAlternatingPairOrder(radialCount: Int) -> [Int] {
        guard radialCount > 0 else { return [] }
        let half = radialCount / 2
        var order: [Int] = []
        order.reserveCapacity(radialCount)
        for i in 0..<half {
            order.append(i)
            order.append(i + half)
        }
        if !radialCount.isMultiple(of: 2) {
            order.append(radialCount - 1)
        }
        return order
    }

    /// Polygon selection result from `selectPolygon(rng:)`.
    struct PolygonSelection {
        var anchors: [Int]              // sorted by angle around centroid
        var bridgeFirst: Int            // index into `anchors` (NOT branchAnchors)
        var bridgeSecond: Int           // index into `anchors` (NOT branchAnchors)
    }

    /// Pick 4–6 of `branchAnchors` (cap at 6 since the array has 6 entries),
    /// ordered around their centroid by angle. The bridge thread's anchor
    /// pair is the two whose connecting edge has the largest angular gap.
    static func selectPolygon(rng: inout UInt32) -> PolygonSelection {
        var lcgRng = rng
        let chosenIndices = drawAnchorSubset(rng: &lcgRng)
        let orderedIndices = orderAnchorsByAngle(chosenIndices)
        let bridgePair = largestAngularGap(orderedAnchorIndices: orderedIndices)
        rng = lcgRng
        return PolygonSelection(
            anchors: orderedIndices,
            bridgeFirst: bridgePair.0,
            bridgeSecond: bridgePair.1
        )
    }

    /// Draw 4–6 of `branchAnchors` without replacement using a Fisher-Yates
    /// partial shuffle seeded by `rng`. `rng` is advanced by the draw.
    private static func drawAnchorSubset(rng: inout UInt32) -> [Int] {
        var lcgRng = rng
        @inline(__always) func draw() -> Float {
            lcgRng = lcgRng &* 1_664_525 &+ 1_013_904_223
            return Float(lcgRng >> 8) / Float(1 << 24)
        }
        let sizeRoll = Int(draw() * 2.99)        // 0..2 → 4..6
        let pickCount = 4 + sizeRoll
        var pool = Array(0..<branchAnchors.count)
        for i in 0..<pickCount {
            let j = i + Int(draw() * Float(pool.count - i))
            pool.swapAt(i, j)
        }
        rng = lcgRng
        return Array(pool.prefix(pickCount))
    }

    /// Sort the chosen branchAnchors indices by angle around the centroid of
    /// their positions.
    private static func orderAnchorsByAngle(_ chosenIndices: [Int]) -> [Int] {
        var cx: Float = 0, cy: Float = 0
        for idx in chosenIndices {
            cx += branchAnchors[idx].x
            cy += branchAnchors[idx].y
        }
        let nF = Float(max(chosenIndices.count, 1))
        cx /= nF; cy /= nF
        let withAngle = chosenIndices.map { idx -> (Int, Float) in
            let pt = branchAnchors[idx]
            return (idx, atan2(pt.y - cy, pt.x - cx))
        }
        return withAngle.sorted { $0.1 < $1.1 }.map { $0.0 }
    }

    /// The two adjacent (post-sort) `anchors`-array indices whose connecting
    /// edge has the largest angular gap around the centroid.
    private static func largestAngularGap(orderedAnchorIndices: [Int]) -> (Int, Int) {
        let count = orderedAnchorIndices.count
        guard count >= 2 else { return (0, 0) }
        var cx: Float = 0, cy: Float = 0
        for idx in orderedAnchorIndices {
            cx += branchAnchors[idx].x
            cy += branchAnchors[idx].y
        }
        let nF = Float(count)
        cx /= nF; cy /= nF
        var maxGap: Float = -1
        var bridgePair: (Int, Int) = (0, 1)
        for i in 0..<count {
            let next = (i + 1) % count
            let curPt = branchAnchors[orderedAnchorIndices[i]]
            let nxtPt = branchAnchors[orderedAnchorIndices[next]]
            let aCur = atan2(curPt.y - cy, curPt.x - cx)
            let aNxt = atan2(nxtPt.y - cy, nxtPt.x - cx)
            var gap = aNxt - aCur
            if gap < 0 { gap += 2 * .pi }
            if gap > maxGap { maxGap = gap; bridgePair = (i, next) }
        }
        return bridgePair
    }

    /// Compute the ordered angular gaps between adjacent polygon vertices
    /// (radians). Used by `test_polygonSelectionIsIrregular` to assert that
    /// selected polygons never collapse to within ±2° of equal across seeds.
    public static func polygonAngularGaps(forSelection anchorIndices: [Int]) -> [Float] {
        guard anchorIndices.count >= 3 else { return [] }
        var cx: Float = 0, cy: Float = 0
        for idx in anchorIndices {
            cx += branchAnchors[idx].x
            cy += branchAnchors[idx].y
        }
        cx /= Float(anchorIndices.count); cy /= Float(anchorIndices.count)
        let angles = anchorIndices.map {
            atan2(branchAnchors[$0].y - cy, branchAnchors[$0].x - cx)
        }
        var gaps: [Float] = []
        gaps.reserveCapacity(angles.count)
        for i in 0..<angles.count {
            let next = (i + 1) % angles.count
            var gap = angles[next] - angles[i]
            if gap < 0 { gap += 2 * .pi }
            gaps.append(gap)
        }
        return gaps
    }
}
