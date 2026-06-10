// SkeinState — Per-preset world state for the Skein painterly preset (Skein.3 / ENGINE.1.2).
//
// Skein.1/2 stayed pure closed-form (the marks were a deterministic hash of features.time
// with no history). Skein.3 needs HISTORY and PER-TRACK IDENTITY the closed-form fragment
// cannot synthesize (SKEIN_DESIGN §5.3 PainterState):
//   • per-mark stem COLOUR — a droplet flung on a stem's onset stays that stem's colour
//     forever, even as the mix moves on (frozen at lay-time, composited opaque — no mud);
//   • onset-driven SPAWNING — a burst fires WHEN a stem's onset fires, which the fragment
//     can't know without an event history. NOTE: only `drums_beat` is a real BeatDetector
//     pulse — `vocals/bass/other_beat` are reserved-zero (StemFeatures.swift). So per-stem
//     onsets are derived here from RISING EDGES on `*_energy_dev` (D-026 deviation), the
//     signal the fragment cannot see;
//   • the per-track SEED (the §5.7 determinism property) — perturbs the painter trajectory;
//   • per-stem continuous-pour integrators (the painter clock + dominant-stem line colour).
//
// This is the demonstrated consumer of ENGINE.1.2 (the gated slot-6 overlay buffer): the
// `SkeinUniforms` packed here is bound at fragment buffer(6) of the marks-on-top overlay via
// RenderPipeline.directPresetFragmentBuffer, exactly as GossamerState/ArachneState do for their
// scene fragments. `skein_geometry_fragment` reads it (Skein.3 commit 3 onward).
//
// Pattern: a direct copy of GossamerState (final class, @unchecked Sendable, one
// storageModeShared MTLBuffer, tick → writeToGPU, a fixed-stride GPU struct that matches the
// MSL struct byte-for-byte). The GPU buffer stays within a fixed stride (CLAUDE.md GPU-contract:
// do not overload reserved slots; do not blow the struct size).
// swiftlint:disable file_length

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "Skein")

// MARK: - Stem identity

/// The four paint "materials" — one stable, well-separated colour per stem over cream.
/// Index order matches the burst-ring `stemIndex` and the palette lookup.
public enum SkeinStem: Int, CaseIterable, Sendable {
    case drums = 0    // the dark skeletal flicks
    case bass = 1     // the heavy deep pools
    case vocals = 2   // the warm flowing lines
    case other = 3    // the connective mid-tone (harmony)
}

// MARK: - SkeinBurstGPU

/// One onset-spawned splatter burst — 12 floats = 48 bytes, align 4 (all floats/uints are
/// 4-byte aligned, so the struct stride is exactly 48, no SIMD-alignment padding surprises).
/// Must match `SkeinBurstGPU` in Skein.metal byte-for-byte.
///
/// The burst is frozen at spawn (position, throw direction, size, viscosity, colour, sharpness)
/// and aged by `header.painterTau − spawnTau`; once it ages past the bake window the CPU stops
/// writing it (it has already baked losslessly into the held canvas), so the ring stays bounded.
struct SkeinBurstGPU {
    var posX: Float        // uv flick point x [0,1]
    var posY: Float        // uv flick point y [0,1]
    var dirX: Float        // throw direction (unit, aspect-corrected) — frozen
    var dirY: Float
    var spawnTau: Float    // painter-clock value at spawn (ageing reference)
    var size: Float        // base droplet size (attackRatio: sharp→smaller, soft→bigger)
    var visc: Float        // viscosity [0,1] frozen at spawn (1 − centroid: thick↔thin)
    var colR: Float        // frozen stem colour (the §colour-mud audit: per-burst mono-colour)
    var colG: Float
    var colB: Float
    var sharpness: Float   // flick sharpness [0,1] (attackRatio → cone tightness)
    var hashSeed: Float    // per-burst deterministic seed for droplet placement variety
}

// MARK: - SkeinHeaderGPU

/// Painter + line state written at the head of the buffer — 16 floats = 64 bytes.
/// Must match `SkeinHeaderGPU` in Skein.metal byte-for-byte.
struct SkeinHeaderGPU {
    var painterTau: Float       // audio-modulated painter clock (replaces features.time as the clock)
    var painterTauStep: Float   // this frame's dτ (so the fragment recomputes the trailing tail)
    var seedPhaseX: Float       // per-track trajectory phase offset (x) — the determinism seed
    var seedPhaseY: Float       // per-track trajectory phase offset (y)
    var lineColR: Float         // dominant-stem line colour (discrete argmax — no mud)
    var lineColG: Float
    var lineColB: Float
    var lineFlow: Float         // dominant stem's smoothed energy_dev → pour width/flow
    var lineVisc: Float         // dominant stem's viscosity (1 − centroid) → line widening
    var jitter: Float           // high-band energy / onset-rate → painter local jitter
    var burstCount: UInt32      // active bursts in the ring this frame
    var seed: UInt32            // raw per-track seed (for any shader-side hashing)
    var breakCount: UInt32      // active colour breakpoints in the ring (Skein.4.1; was pad0)
    var locusEnable: Float      // painter-locus build flag, 0/1 (Skein.5; was pad1 — 0 ⇒ byte-identical)
    var pad2: Float
    var pad3: Float
}

// MARK: - SkeinBreakGPU

/// One line-colour + new-pour BREAKPOINT — 6 floats = 24 bytes, align 4. Must match `SkeinBreakGPU`
/// in Skein.metal byte-for-byte. Pushed on each dominant-stem switch (Skein.4.1, option 2 — Matt's
/// call: a colour change starts a genuinely NEW pour, not a recoloured continuation):
///   • the shader freezes each pour-line tail segment's COLOUR at the painter-clock value it was LAID
///     at, so already-laid paint keeps its colour (never recolouring the existing stroke); AND
///   • each breakpoint carries a small bounded position OFFSET — the painter "grabs new paint and
///     starts a fresh drip" — so the new-colour line is spatially displaced from the old, with a clean
///     GAP at the switch (the segment that would bridge two different offsets is not drawn). The offset
///     is NON-cumulative (a fixed-magnitude, golden-angle-rotated vector) so the line never drifts off
///     canvas. This is the per-burst colour freeze (SkeinBurstGPU.colR/G/B) applied to the line, plus a
///     "new container" jump.
struct SkeinBreakGPU {
    var tauStart: Float   // painter-clock value at the dominant-stem switch (this pour valid from here on)
    var colR: Float       // the new LINEAR (sRGB-decoded) colour — like paletteLinear (FA #71)
    var colG: Float
    var colB: Float
    var offX: Float       // bounded UV position offset for this pour (the "new container" jump; 0 at baseline)
    var offY: Float
}

// MARK: - SkeinColorBreakpoint (test-facing)

/// A line-colour breakpoint as exposed for tests (Skein.4.1): the painter-clock value the pour began,
/// its LINEAR colour, and its bounded position offset (the "new container" jump).
public struct SkeinColorBreakpoint: Sendable {
    public let tauStart: Float
    public let color: SIMD3<Float>
    public let offset: SIMD2<Float>
}

// MARK: - SkeinState

/// Owns the painter integrators + onset-burst ring + per-track seed, and the GPU buffer bound at
/// fragment slot 6 of the Skein marks-on-top overlay.
///
/// Thread-safe: `tick()` and `skeinBuffer` can be accessed from any queue.
public final class SkeinState: @unchecked Sendable {

    // MARK: - Constants

    /// Max active bursts in the ring. ~2 onsets/s/stem × 4 stems × the bake window ≈ a handful
    /// live at once; 48 leaves generous headroom for dense passages without blowing the stride.
    public static let maxBursts: Int = 48

    /// Max colour breakpoints in the line-colour ring (Skein.4.1). The 16 most-recent dominant-stem
    /// switches always cover the ~40-frame live tail (even busy music switches the dominant far slower
    /// than 16×/40-frames); older entries evict. 16 × 24 B = 384 B appended after the burst array.
    public static let maxColorBreaks: Int = 16

    /// New-pour JUMP magnitude (UV) on a colour switch (Skein.4.1 option 2 — Matt's call: a colour
    /// change is a NEW pour). The new-colour line is displaced this far from the old, leaving a clean
    /// gap (≫ the ~0.01–0.02 line radius). Bounded + non-cumulative → the line never drifts off canvas.
    static let breakJumpMagnitude: Float = 0.05
    /// Successive jumps rotate by the golden angle so consecutive new pours land in well-separated
    /// directions (a clear gap every switch — never two near-collinear offsets that barely move).
    static let breakJumpGoldenAngle: Float = 2.399963

    /// Minimum pour length before a NEW pour can start (painter-clock τ; Skein.4.1 M7-round-2). A new
    /// pour = a new colour + a displaced jump; the dominant-stem argmax flickers far faster than a pour
    /// reads, so without a dwell the line breaks into very short segments (Matt M7 2026-06-09: "the
    /// lines are very short rather than a long continuous dripping/pouring across the canvas" — measured
    /// 63 switches / 44 s, median pour 0.2 s). At the trajectory's ~0.15 UV/τ, 3.0 τ ≈ a half-canvas
    /// minimum pour; the typical pour is longer (it only switches when a different stem decisively leads).
    /// Validated on a real session: 63 → 10 pours, ~4 s average. NOT a new audio route (gates the
    /// existing dominant-switch event), so FA #67 holds.
    static let minPourTau: Float = 3.0
    /// A challenger must lead the incumbent's smoothed energy by this factor to start a new pour —
    /// prevents flicker between two near-equal stems at the minPourTau boundary.
    static let pourSwitchHysteresis: Float = 1.25

    /// Seconds a burst is redrawn (fades in then freezes into the held canvas) — matches the
    /// Skein.2 `kSkeinSplatWindow` bake-in window, now measured in painter-clock units.
    static let bakeWindow: Float = 0.55

    // D-019 warmup: blend FV → stems as total stem energy climbs through this window.
    static let warmupLow: Float = 0.02
    static let warmupHigh: Float = 0.06

    /// Painter speed: base rate (1× = real-time) + this gain × broadband energy deviation, so
    /// busy passages fill the canvas faster (the Skein.2 M7 pacing note). NOT arousal (Skein.5).
    static let paintSpeedBase: Float = 1.0
    static let paintSpeedGain: Float = 2.2

    /// Per-stem onset/activity: a stem flicks whenever its `*_energy_dev` is above this DEVIATION
    /// threshold (D-026-clean — a deviation primitive centred at 0, not an absolute AGC energy),
    /// rate-limited by the refractory so a busier stem flicks MORE (splatter density ∝ activity) but
    /// never machine-guns (FA #1/#4 family). Throttled-while-active (not rising-edge-only) so sparse
    /// real onsets still lay enough coloured paint to read per-stem (the line over-dominated when
    /// each stem fired only on a rising edge — drums/bass painted nothing).
    static let onsetDevThreshold: Float = 0.13
    static let onsetRefractory: Float = 0.14   // s — min gap between a stem's bursts (~7 / s max)

    /// EMA time-constant (s) for the per-stem energy used to pick the dominant line colour and
    /// drive pour flow — smooth enough that the dominant-stem argmax doesn't flicker per frame.
    static let stemEnergyTau: Float = 0.30

    /// Wetness dry-rate (Skein.ENGINE.2 / Skein.4). The feedback texture's ALPHA channel carries a
    /// transient "wetness" stamped ~1 where paint lands (the overlay's coverage) and decayed each
    /// frame by `exp(-wetnessDryRate · dt · stemMix)` in `skein_warp_fragment`. The `stemMix` gate
    /// makes the decay PAUSE AT SILENCE (§5.2 step 3 — the accumulated-audio-time semantics: at
    /// silence stemMix→0 → factor→1 → wetness holds, no sheen drift). `ln2 / halfLifeSeconds`:
    /// a ~1.6 s wet half-life → marks read matte after ~3–4 s of active music. Tunable at Skein.4.
    static let wetnessDryRate: Float = 0.43   // ln2 / 1.6 s

    // MARK: - Palette (Skein.3 — placeholder vivid set; Matt sign-off finalises in commit 2)

    /// One stable, well-separated, vivid colour per stem over cream. Indexed by `SkeinStem`.
    /// The *Full Fathom Five* illustrative register (charcoal / oxblood / ochre / teal) — the
    /// default pending Matt's palette sign-off (the README colour rule: legibility, not specific
    /// hues, is the binding constraint). Linear-ish RGB; vivid (not pale).
    public static let defaultPalette: [SIMD3<Float>] = [
        SIMD3(0.12, 0.13, 0.18),   // drums  — near-black charcoal/indigo (dark skeletal flicks)
        SIMD3(0.62, 0.13, 0.16),   // bass   — deep oxblood crimson (heavy deep pools)
        SIMD3(0.90, 0.62, 0.16),   // vocals — warm ochre/gold (warm flowing lines)
        SIMD3(0.12, 0.58, 0.55)    // other  — teal/turquoise (connective harmony mid-tone)
    ]

    // MARK: - Public Properties

    /// GPU-side buffer: `SkeinHeaderGPU` (64 bytes) + `maxBursts` × `SkeinBurstGPU` (48 bytes).
    /// Bound at fragment buffer(6) by VisualizerEngine+Presets via setDirectPresetFragmentBuffer.
    public let skeinBuffer: MTLBuffer

    /// Active burst count this frame (updated by tick). Exposed for diagnostics/tests.
    public private(set) var burstCount: Int = 0

    /// The painter clock this frame (accumulated, audio-modulated). Exposed for tests.
    public private(set) var painterTau: Float = 0

    /// This frame's wetness-channel decay multiplier (Skein.ENGINE.2), pushed to the warp/hold
    /// fragment via `RenderPipeline.setMVWarpWetnessDecay`. `exp(-wetnessDryRate · dt · stemMix)`:
    /// `1.0` at silence (stemMix→0, the decay PAUSES — §5.2 step 3), `< 1.0` while music plays.
    /// Exposed so the render-loop tick hook (and the test harness) can bind it each frame.
    public private(set) var wetnessDecay: Float = 1.0

    /// Total onset bursts spawned since the last reseed. Exposed for the beat-ratio route test
    /// (a beat-heavy stem slice must spawn measurably more bursts than a steady slice).
    public var totalBurstsSpawned: Int { lock.withLock { Int(burstSpawnCounter) } }

    /// The current dominant-stem index for the pour line (-1 until the canvas warms). Exposed for the
    /// Skein.4.1 colour-freeze test (detect the dominant-stem switch frame on the live path).
    public var lineDominantStem: Int { lock.withLock { lineDomIdx } }

    // Skein.ENGINE.3 (D-151): the structural-section read accessors live in a same-file extension
    // (`SkeinState structural-section signal`, below) to keep the class body within the SwiftLint
    // type_body_length budget — the same reason the math helpers are in an extension.

    /// The colour-breakpoint ring (oldest→newest). Each entry is the line colour + position offset in
    /// effect from `tauStart` onward; the shader freezes each tail segment to the latest breakpoint
    /// at/under its lay-time τ, and a switch starts a displaced NEW pour (Skein.4.1 option 2). Test-only.
    public var colorBreakpoints: [SkeinColorBreakpoint] {
        lock.withLock {
            colorBreaks.map {
                SkeinColorBreakpoint(tauStart: $0.tauStart,
                                     color: SIMD3<Float>($0.colR, $0.colG, $0.colB),
                                     offset: SIMD2<Float>($0.offX, $0.offY))
            }
        }
    }

    /// Bursts spawned per stem [drums, bass, vocals, other] since the last reseed. Exposed for
    /// the colour-legibility diagnostic (every stem with onsets should produce bursts).
    public var spawnsPerStem: [Int] { lock.withLock { spawnsPerStemStore } }

    /// The active per-stem palette as the intended DISPLAY (sRGB) colours (defaults to
    /// `defaultPalette`; the contact-sheet harness passes candidates for Matt's sign-off). One
    /// vivid, well-separated colour per stem. Public so the colour-separation test classifies
    /// rendered (sRGB) pixels against these display values directly.
    public let palette: [SIMD3<Float>]

    /// The palette sRGB-DECODED to linear, packed into the GPU buffer. The shader outputs linear;
    /// the `.bgra8Unorm_srgb` canvas sRGB-ENCODES on store, so the round-trip yields the `palette`
    /// display colour (FA #71 — without the decode, dark colours lift to washed mid-tones).
    private let paletteLinear: [SIMD3<Float>]

    // MARK: - Private State

    private var bursts: [SkeinBurstGPU]
    /// Line-colour + new-pour breakpoint ring (Skein.4.1) — pushed on each dominant-stem switch, read
    /// by the shader to freeze each pour-line segment's colour + offset at lay-time. White baseline seed.
    private var colorBreaks: [SkeinBreakGPU] = []
    /// The dominant-stem index the line currently records (-1 until warm) — a switch pushes a breakpoint.
    private var lineDomIdx: Int = -1
    /// Painter-clock value at the last committed pour start — the minPourTau dwell reference (Skein.4.1).
    private var lastSwitchTau: Float = 0
    /// Monotonic colour-break counter — seeds each new pour's jump angle (§5.7 determinism). Reset on reseed.
    private var colorBreakCounter: UInt32 = 0
    /// The current pour's position offset (the latest breakpoint's jump) — bursts flick from here too.
    private var currentLineOffset = SIMD2<Float>(0, 0)
    private var painterTauStep: Float = 0
    private var seedPhaseX: Float = 0
    private var seedPhaseY: Float = 0
    private var seed: UInt32
    /// Monotonic spawn counter — seeds each burst's droplet placement so the same track
    /// (same seed → same onset sequence) places the same droplets (the §5.7 determinism).
    private var burstSpawnCounter: UInt32 = 0
    /// Per-stem spawn tally [drums, bass, vocals, other] (diagnostic).
    private var spawnsPerStemStore = [Int](repeating: 0, count: 4)

    // Per-frame line state (computed in _tick, packed into the header in writeToGPU).
    private var lineCol = SIMD3<Float>(1, 1, 1)
    private var lineFlow: Float = 0
    private var lineVisc: Float = 0
    private var jitter: Float = 0

    /// Per-stem smoothed energy (EMA) for dominant-colour selection + pour flow.
    private var stemEnergySmoothed = [Float](repeating: 0, count: 4)
    /// Per-stem painter-clock value at the last burst (refractory gate).
    private var lastBurstTau = [Float](repeating: -1, count: 4)

    // Structural-section signal (Skein.ENGINE.3, D-151) — delivered by the live bridge; consumed
    // by the Skein.5 structural bias (updateSectionBias). Pure CPU state; never packed into
    // the GPU buffer ⇒ the render is byte-identical.
    private var structSectionIndex: UInt32 = 0
    private var structSectionStartTime: Float = 0
    private var structConfidence: Float = 0
    /// false until the first prediction is observed (so the first frame re-baselines rather than
    /// reporting a spurious boundary); reset on reseed.
    private var structInitialized = false
    /// true for exactly the one frame on which the delivered section index changed.
    private var structBoundaryChanged = false

    /// Skein.5 mood / structure-bias / anticipation state — one stored property (the fields and all
    /// logic live in the Skein.5 same-file extension, keeping the type body within the lint budget).
    var m5 = MusicalityState()

    /// Painter-locus build flag (Skein.5) — a faint luminous pour-point at the live painter tip,
    /// drawn DISPLAY-ONLY in `skein_comp_fragment` (never baked into the held canvas). OFF by
    /// default (`defaultLocusEnabled`); the contact-sheet harness passes `true`.
    public let locusEnabled: Bool

    private let lock = NSLock()

    // MARK: - Init

    /// Creates a SkeinState with an empty burst ring and the given per-track seed.
    ///
    /// - Parameters:
    ///   - device: Metal device for buffer allocation.
    ///   - seed: Per-track deterministic seed (FNV-1a of title|artist — same track → same painting).
    ///   - palette: Per-stem colour set; defaults to `defaultPalette`. The contact-sheet harness
    ///     passes candidates for Matt's palette sign-off.
    public init?(device: MTLDevice,
                 seed: UInt32 = 0,
                 palette: [SIMD3<Float>] = SkeinState.defaultPalette,
                 locusEnabled: Bool = SkeinState.defaultLocusEnabled) {
        self.locusEnabled = locusEnabled
        let bufferSize = MemoryLayout<SkeinHeaderGPU>.stride
            + Self.maxBursts * MemoryLayout<SkeinBurstGPU>.stride
            + Self.maxColorBreaks * MemoryLayout<SkeinBreakGPU>.stride
        guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            logger.error("SkeinState: failed to allocate skeinBuffer (\(bufferSize) bytes)")
            return nil
        }
        skeinBuffer = buf
        let pal = palette.count == 4 ? palette : Self.defaultPalette
        self.palette = pal
        self.paletteLinear = pal.map(Self.srgbToLinear)
        bursts = []
        bursts.reserveCapacity(Self.maxBursts)
        self.seed = seed
        applySeed(seed)
        resetColorBreaks()   // empty ring — no line until the first coloured pour commits (Skein.5.1)
        writeToGPU()
    }

    // MARK: - Public API

    /// Update the painter integrators + onset-burst ring for one rendered frame, then flush.
    ///
    /// Call once per frame from the render-loop tick hook (setMeshPresetTick) before the overlay
    /// draw reads buffer(6).
    ///
    /// `structure` (Skein.ENGINE.3, D-151): the live structural-section prediction, delivered via
    /// the gated `RenderPipeline.latestStructuralPrediction` bridge. CPU-only — **STORED** here for
    /// Skein.5 (which will key the structural visual bias on it); ENGINE.3 only proves the signal
    /// arrives. Nothing below feeds it into geometry/colour/width and it is never written to the GPU
    /// buffer, so the render is byte-identical to today. Defaults to `.none` (the value at silence /
    /// before the first prediction / for the unit-tick test call sites that don't drive structure).
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures,
                     structure: StructuralPrediction = .none) {
        lock.withLock { _tick(deltaTime: deltaTime, features: features, stems: stems, structure: structure) }
        writeToGPU()
    }

    /// Re-seed the painter on track change (the §1.5 reset: canvas cleared to cream by the
    /// preset-apply/track-change clear; here we re-seed the trajectory + clear the live ring so
    /// the new track paints its own deterministic painting). Thread-safe.
    public func reseed(_ newSeed: UInt32) {
        lock.withLock {
            seed = newSeed
            applySeed(newSeed)
            painterTau = 0
            painterTauStep = 0
            wetnessDecay = 1.0
            burstSpawnCounter = 0
            spawnsPerStemStore = [0, 0, 0, 0]
            bursts.removeAll(keepingCapacity: true)
            burstCount = 0
            lineCol = SIMD3<Float>(1, 1, 1)
            resetColorBreaks()   // empty ring — the new track's line waits for its first pour (Skein.5.1)
            lineFlow = 0; lineVisc = 0; jitter = 0
            // Skein.ENGINE.3: clear the structural-section tracking so the new track re-baselines —
            // no spurious boundary from the old track's last section index (the bridge also resets
            // to .none via MIRPipeline.reset on track change, but clearing here is the local guard).
            structSectionIndex = 0
            structSectionStartTime = 0
            structConfidence = 0
            structInitialized = false
            structBoundaryChanged = false
            m5 = MusicalityState()   // Skein.5: mood EMA, section lean/pulse, anticipation state
            for i in 0..<4 {
                stemEnergySmoothed[i] = 0
                lastBurstTau[i] = -1
            }
        }
        writeToGPU()
    }

    // MARK: - Private: tick (called while holding lock)

    private func _tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures,
                       structure: StructuralPrediction) {
        // Skein.ENGINE.3 (D-151): ingest the live structural-section signal FIRST and
        // UNCONDITIONALLY — section detection is independent of the visual warmup/silence gate, so
        // the section index / boundary flag track even at silence. STORED only (Skein.5 consumes
        // it for the structural bias); no field below reads it and it never reaches the GPU buffer,
        // so the render is byte-identical.
        ingestStructure(structure)

        let dt = max(deltaTime, 0.001)

        // Skein.5 — mood EMA (valence/arousal smoothed IN STATE, never written back: FA #25).
        // Unconditional like the structure ingest: the mood arc tracks even while the canvas warms.
        updateMood(features: features, dt: dt)

        // D-019 warmup: 0 = FV-only, 1 = stems fully warm.
        let totalStemEnergy = stems.drumsEnergy + stems.bassEnergy
                            + stems.vocalsEnergy + stems.otherEnergy
        let stemMix = smoothstep(Self.warmupLow, Self.warmupHigh, totalStemEnergy)

        // Wetness decay (Skein.ENGINE.2): the per-frame multiplier applied to the feedback ALPHA
        // channel by `skein_warp_fragment`. Gated by `stemMix` so it PAUSES at silence (§5.2 step 3,
        // the accumulated-audio-time semantics — at silence the held painting freezes wet, no sheen
        // drift). Exponential in `dt` so the dry-rate is frame-rate-independent. NOT a new audio
        // routing — it reuses the existing silence gate; wetness = where paint landed (FA #67).
        wetnessDecay = exp(-Self.wetnessDryRate * dt * stemMix)

        // Per-stem positive energy deviation (D-026) — drumsEnergyDev etc. are already
        // max(0, rel); read them directly. EMA-smooth for the dominant-colour pick + pour flow.
        let dev: [Float] = [
            max(0, stems.drumsEnergyDev),
            max(0, stems.bassEnergyDev),
            max(0, stems.vocalsEnergyDev),
            max(0, stems.otherEnergyDev)
        ]
        let emaA = min(dt / Self.stemEnergyTau, 1.0)
        for i in 0..<4 { stemEnergySmoothed[i] += (dev[i] - stemEnergySmoothed[i]) * emaA }

        // Skein.5 — structural-section bias: boundary pulse + region-lean EMA, all gated on the
        // prediction confidence (low confidence ⇒ zero bias ⇒ the pure allover read).
        updateSectionBias(dt: dt, stemMix: stemMix)

        // Painter speed ← broadband energy deviation (mean of the four positive devs), with an
        // FV fallback (midAttRel) during warmup. Skein.5 layers two MOTION modulators on the same
        // single path (one visual channel — no FA #67 competing-rhythms risk, distinct timescales):
        //   • arousal (slow ~10 s global envelope): vigorous music quickens the whole painter;
        //   • beat anticipation (beat-rate, FA #33): τ-speed wind-up into each beat, flick at the
        //     wrap. τ-warping keeps every tail sample ON the trajectory curve (samples move ALONG
        //     the curve, never laterally), so the held line never smears — safe by construction.
        let broadbandDev = (dev[0] + dev[1] + dev[2] + dev[3]) * 0.25
        let arousalGain = 1.0 + Self.arousalSpeedGain * m5.moodArousal
        let speedStem = (Self.paintSpeedBase + Self.paintSpeedGain * broadbandDev) * arousalGain
        let speedFV = Self.paintSpeedBase + 1.5 * max(0, features.midAttRel)
        let anticipation = anticipationFactor(features: features, dt: dt, stemMix: stemMix)
        // Skein.5.1: the painter CLOCK pauses at true silence — no music, no painting (the same
        // semantics as the wetness decay pause). `activity` is the max of the stem warmup and an
        // FV-energy gate, so the FV-fallback window (track start, live stems still converging,
        // music clearly playing) keeps the painter moving while a pause/track-gap freezes it.
        let fvEnergy = features.bass + features.mid + features.treble
        let activity = max(stemMix, smoothstep(0.01, 0.04, fvEnergy))
        let paintSpeed = mix(speedFV, speedStem, stemMix) * anticipation * activity
        m5.speedFactor = anticipation
        painterTauStep = dt * paintSpeed
        painterTau += painterTauStep

        // Dominant stem → line colour / flow / viscosity + the pour-commit state machine
        // (Skein.4.1 min-dwell + hysteresis; Skein.5 boundary-forced fresh pour + mood tint).
        updateDominantLine(stems: stems, stemMix: stemMix)

        // Per-stem ACTIVITY → splatter burst (energy_dev above threshold, rate-limited by the
        // refractory → a busier stem flicks more). The burst is frozen at the painter's current
        // position, in the stem's colour, with size from attackRatio and viscosity from centroid.
        // Gated by warmup so silence lays nothing.
        if stemMix > 0.001 {
            spawnOnsetBursts(dev: dev, stems: stems, aspect: features.aspectRatio)
        }

        // Retire bursts that have aged past the bake window (already baked losslessly into the
        // held canvas — no longer redrawn).
        bursts.removeAll { painterTau - $0.spawnTau > Self.bakeWindow }
        burstCount = bursts.count
    }

    // MARK: - Private: burst spawning

    private func spawnBurst(stem: Int, stems: StemFeatures, aspect: Float) {
        guard bursts.count < Self.maxBursts else {
            // Ring full (very dense onset cluster): drop the oldest to make room.
            if let oldest = bursts.indices.min(by: { bursts[$0].spawnTau < bursts[$1].spawnTau }) {
                bursts.remove(at: oldest)
            }
            return spawnBurst(stem: stem, stems: stems, aspect: aspect)
        }
        let asp = aspect > 0.01 ? aspect : 1.0
        let base = painterPos(painterTau)
        let prev = painterPos(painterTau - max(painterTauStep, 1.0 / 240.0))
        // Throw direction = direction of travel (aspect-corrected), the flung-forward axis. Computed
        // from the UN-offset path so a switch-frame jump (Skein.4.1) does not spike the throw vector.
        var dx = (base.x - prev.x) * asp
        var dy = base.y - prev.y
        let len = (dx * dx + dy * dy).squareRoot()
        if len > 1e-5 { dx /= len; dy /= len } else { dx = 1; dy = 0 }
        // Flick from the painter's CURRENT pour position — including this pour's jump offset — so the
        // onset splatter lands with the displaced new-pour line, not the un-jumped trajectory (Skein.4.1).
        let pos = base + currentLineOffset

        let stemEnum = SkeinStem(rawValue: stem) ?? .drums
        // Flick sharpness ← attackRatio (∈[0,3]): sharp transient → tight/fast spray (small dots),
        // soft → looser/larger droplets.
        let sharpness = clamp(attackRatio(of: stemEnum, stems: stems) / 3.0, 0, 1)
        let size = mix(1.0, 0.55, sharpness)             // soft→bigger, sharp→smaller base size
        // Viscosity ← centroid: bright/high-centroid = thin-fine (visc→0), dark/low = thick (visc→1).
        let visc = clamp(1.0 - centroid(of: stemEnum, stems: stems), 0, 1)
        // Skein.5: the burst colour is mood-tinted at SPAWN and frozen — like the line breakpoints,
        // the canvas archives the mood each mark was laid under (valence = 0 ⇒ identity tint).
        let col = moodTinted(paletteLinear[stem])

        // Per-burst droplet-placement seed: mix the per-track seed with a monotonic spawn counter
        // so the same track (same onset sequence) places identical droplets (§5.7 determinism).
        burstSpawnCounter &+= 1
        if stem >= 0 && stem < 4 { spawnsPerStemStore[stem] += 1 }
        let mixed = (seed &+ burstSpawnCounter &* 0x9E3779B9) & 0xFFFFF
        let hashSeed = Float(mixed)

        bursts.append(SkeinBurstGPU(
            posX: pos.x,
            posY: pos.y,
            dirX: dx,
            dirY: dy,
            spawnTau: painterTau,
            size: size,
            visc: visc,
            colR: col.x,
            colG: col.y,
            colB: col.z,
            sharpness: sharpness,
            hashSeed: hashSeed))
    }

    // MARK: - Private: GPU write

    private func writeToGPU() {
        // Snapshot all GPU-bound state under one lock, then write the buffer outside it (the
        // GossamerState/ArachneState pattern — the benign CPU/GPU write race is accepted for
        // per-frame visual state; @unchecked Sendable owns the contract).
        let snap: GPUSnapshot = lock.withLock {
            let hdr = SkeinHeaderGPU(
                painterTau: painterTau,
                painterTauStep: painterTauStep,
                seedPhaseX: seedPhaseX,
                seedPhaseY: seedPhaseY,
                lineColR: lineCol.x,
                lineColG: lineCol.y,
                lineColB: lineCol.z,
                lineFlow: lineFlow,
                lineVisc: lineVisc,
                jitter: jitter,
                burstCount: UInt32(min(bursts.count, Self.maxBursts)),
                seed: seed,
                breakCount: UInt32(min(colorBreaks.count, Self.maxColorBreaks)),
                locusEnable: locusEnabled ? 1.0 : 0.0,
                pad2: 0,
                pad3: 0)
            return GPUSnapshot(header: hdr, bursts: bursts, breaks: colorBreaks)
        }
        let ptr = skeinBuffer.contents()
        ptr.bindMemory(to: SkeinHeaderGPU.self, capacity: 1)[0] = snap.header
        let count = min(snap.bursts.count, Self.maxBursts)
        let burstPtr = ptr.advanced(by: MemoryLayout<SkeinHeaderGPU>.stride)
            .bindMemory(to: SkeinBurstGPU.self, capacity: Self.maxBursts)
        for i in 0..<count { burstPtr[i] = snap.bursts[i] }
        // Skein.4.1: the colour-breakpoint ring follows the fixed-size burst array (additive tail).
        let breakCount = min(snap.breaks.count, Self.maxColorBreaks)
        let breakPtr = ptr.advanced(by: MemoryLayout<SkeinHeaderGPU>.stride
                                    + Self.maxBursts * MemoryLayout<SkeinBurstGPU>.stride)
            .bindMemory(to: SkeinBreakGPU.self, capacity: Self.maxColorBreaks)
        for i in 0..<breakCount { breakPtr[i] = snap.breaks[i] }
    }

    /// One frame's GPU-bound snapshot, captured under the lock then written to the buffer outside it
    /// (the GossamerState pattern — avoids a >2-member tuple while keeping the lock window minimal).
    private struct GPUSnapshot {
        let header: SkeinHeaderGPU
        let bursts: [SkeinBurstGPU]
        let breaks: [SkeinBreakGPU]
    }

    // MARK: - Private: colour-break ring (Skein.4.1)

    /// Clear the line-colour ring to EMPTY (Skein.5.1 — Matt M7 2026-06-09: the old white baseline
    /// laid a permanent white squiggle at every track start; "white disturbs the colour palette").
    /// With an empty ring the shader draws NO line at all (`breakCount == 0` skips Layer A): the
    /// painter never pours white — the line starts when the first COLOURED pour commits, which
    /// retro-colours the brief pre-commit tail via `tauStart = 0`. At silence nothing ever commits,
    /// so the painter rests. init + reseed call it.
    private func resetColorBreaks() {
        colorBreaks.removeAll(keepingCapacity: true)
        lineDomIdx = -1
        lastSwitchTau = 0
        colorBreakCounter = 0
        currentLineOffset = SIMD2<Float>(0, 0)
    }

    /// Push a breakpoint (the painter-clock value at a dominant-stem switch + the new LINEAR colour +
    /// a bounded new-pour jump offset). The jump is a fixed-magnitude vector rotated by the golden angle
    /// per switch (non-cumulative → never drifts off canvas; well-separated → a clear gap every switch).
    /// Evicts the oldest when the ring is full — the 16 most-recent switches always cover the live tail.
    ///
    /// Skein.5.1: the FIRST pour of a painting carries NO jump — a jump separates a new pour from
    /// the previous one, and there is none; the painting starts on the natural trajectory.
    private func pushColorBreak(tauStart: Float, color: SIMD3<Float>) {
        let off: SIMD2<Float>
        if colorBreaks.isEmpty {
            off = SIMD2<Float>(0, 0)
        } else {
            colorBreakCounter &+= 1
            let seedAngle = Float(seed & 0xFFFF) / Float(0xFFFF) * 2 * .pi
            let ang = seedAngle + Float(colorBreakCounter) * Self.breakJumpGoldenAngle
            // Skein.5: the section REGION LEAN adds to the golden-angle jump — every pour committed
            // inside a section starts displaced toward that section's patch (repeated sections revisit
            // and build density). Both terms are bounded + non-cumulative (≤ 0.05 + 0.085 UV), so the
            // line still never drifts off canvas; lean = 0 (no structure / low confidence) is the
            // byte-identical Skein.4.1 jump.
            off = SIMD2<Float>(cos(ang), sin(ang)) * Self.breakJumpMagnitude + m5.sectionLean
        }
        currentLineOffset = off
        if colorBreaks.count >= Self.maxColorBreaks { colorBreaks.removeFirst() }
        colorBreaks.append(SkeinBreakGPU(
            tauStart: tauStart,
            colR: color.x,
            colG: color.y,
            colB: color.z,
            offX: off.x,
            offY: off.y))
    }
}

// MARK: - SkeinState math helpers

/// Local math helpers in a same-file extension — keeps the main type body within the SwiftLint
/// `type_body_length` budget; `private` members of a type are visible to same-file extensions of that
/// type (SE-0169), so `_tick`/`spawnBurst` still reach these.
extension SkeinState {

    /// Map the per-track seed to a pair of trajectory phase offsets in [0, 2π). Same seed → same
    /// offsets → same painting (the §5.7 determinism property).
    func applySeed(_ seedValue: UInt32) {
        seedPhaseX = Float(seedValue & 0xFFFF) / Float(0xFFFF) * 2 * .pi
        seedPhaseY = Float((seedValue >> 16) & 0xFFFF) / Float(0xFFFF) * 2 * .pi
    }

    /// The CPU mirror of `skeinPainterPos(t)` in Skein.metal, with the per-track seed phase
    /// offsets added. Kept in sync by review (the static-source guard asserts the shader still
    /// declares `skeinPainterPos`). Used to freeze a burst's flick point + throw direction.
    func painterPos(_ tau: Float) -> SIMD2<Float> {
        let x = 0.5
            + 0.300 * sin(0.220 * tau + 0.0 + seedPhaseX)
            + 0.110 * sin(0.950 * tau + 1.7 + seedPhaseX)
            + 0.045 * sin(2.300 * tau + 4.2 + seedPhaseX)
        let y = 0.5
            + 0.280 * cos(0.190 * tau + 2.3 + seedPhaseY)
            + 0.120 * cos(1.070 * tau + 5.1 + seedPhaseY)
            + 0.040 * cos(2.620 * tau + 0.9 + seedPhaseY)
        return SIMD2(x, y)
    }

    /// Dominant stem → line colour / flow / viscosity + the pour-commit state machine (called from
    /// `_tick`, lock held). DISCRETE argmax of smoothed energy — never a colour-space blend, so the
    /// continuous line is never a 50/50 mud; below the warmup floor the canvas rests (prior hue kept).
    ///
    /// Skein.4.1: a dominant-stem switch starts a genuinely NEW pour (new colour + a displaced jump —
    /// the breakpoint ring; the redrawn tail freezes each segment at its lay-time colour). The
    /// dominant ARGMAX flickers far faster than a pour can read (Matt M7 2026-06-09: 63 switches /
    /// 44 s, median pour 0.2 s), so a new pour COMMITS only on a SUSTAINED, DECISIVE change: the
    /// current pour must have lasted `minPourTau`, and the challenger must lead the incumbent by the
    /// hysteresis margin. The first pour commits immediately. Bursts stay ungated (the accents).
    ///
    /// Skein.5: a confident SECTION BOUNDARY also starts a fresh pour without a dominant switch
    /// ("the drop hits → the painter grabs a new container toward the section's region") — floored
    /// at `boundaryPourMinTau` so a boundary right after a switch never chops pours into confetti
    /// (the D-150 long-pour intent). Colours are mood-tinted AT LAY TIME and frozen.
    func updateDominantLine(stems: StemFeatures, stemMix: Float) {
        var domIdx = 0
        var domVal = stemEnergySmoothed[0]
        for i in 1..<4 where stemEnergySmoothed[i] > domVal { domVal = stemEnergySmoothed[i]; domIdx = i }
        guard stemMix > 0.001 else { lineFlow = 0; lineVisc = 0; jitter = 0; return }

        let committed: Bool
        if lineDomIdx == -1 {
            // Skein.5.1: a brief settle before the first commit — the colour is chosen from ~¼ s of
            // smoothed evidence, not one frame's argmax; the retro-colour hides the wait entirely.
            committed = painterTau >= Self.firstPourSettleTau
        } else if domIdx != lineDomIdx
            && (painterTau - lastSwitchTau) >= Self.minPourTau
            && stemEnergySmoothed[domIdx] > stemEnergySmoothed[lineDomIdx] * Self.pourSwitchHysteresis {
            committed = true
        } else {
            committed = m5.boundaryPourPending > 0.5
                && (painterTau - lastSwitchTau) >= Self.boundaryPourMinTau
        }
        if committed {
            // Skein.5.1: the FIRST commit retro-colours the whole pre-commit tail (tauStart 0 —
            // every tail sample, including the negative-ctau birth window, resolves to this pour),
            // so the painting's first stroke is already the lead stem's colour. White never paints.
            let isFirstPour = lineDomIdx == -1
            pushColorBreak(tauStart: isFirstPour ? 0 : painterTau,
                           color: moodTinted(paletteLinear[domIdx]))
            lineDomIdx = domIdx
            lastSwitchTau = painterTau
            m5.boundaryPourPending = 0
        }
        // Skein.5.1: during the first-pour settle no pour exists yet — nothing to colour or width.
        guard lineDomIdx >= 0 else { lineFlow = 0; lineVisc = 0; jitter = 0; return }
        // Colour / flow / viscosity all reflect the COMMITTED pour (lineDomIdx) — the whole pour is
        // coherent, and the width doesn't breathe with a louder non-committed stem mid-pour. The
        // rendered colour is the breakpoint's, FROZEN at lay-time (the canvas archives the mood arc).
        lineCol = moodTinted(paletteLinear[lineDomIdx])
        // Arousal → pour width (slight): vigorous music pours a slightly fuller line.
        lineFlow = stemEnergySmoothed[lineDomIdx] * stemMix
            * (1.0 + Self.arousalWidthGain * max(0, m5.moodArousal))
        let domCentroid = centroid(of: SkeinStem(rawValue: lineDomIdx) ?? .drums, stems: stems)
        lineVisc = clamp(1.0 - domCentroid, 0, 1) * stemMix

        // Local jitter ← high-band energy / onset rate (a fast continuous primitive distinct from
        // the per-beat onset accents and the slow painter speed — one primitive per layer, FA #67).
        let highBand = stems.vocalsBand1 + stems.otherBand1
        jitter = clamp(highBand * 0.5 * stemMix, 0, 1)
    }

    /// Per-stem onset → splatter bursts (called from `_tick`, lock held; canvas warm). The
    /// emission TRIGGER stays per-stem onset (the accent layer, unchanged); Skein.5 scales only
    /// the DENSITY envelope: arousal (vigorous music flicks more) and the section-boundary pulse
    /// (the drop lands → a brief splatter flurry).
    func spawnOnsetBursts(dev: [Float], stems: StemFeatures, aspect: Float) {
        let refractory = Self.onsetRefractory
            / (1.0 + Self.arousalDensityGain * max(0, m5.moodArousal)
                   + Self.sectionDensityGain * m5.sectionPulse)
        for i in 0..<4 {
            let active = dev[i] > Self.onsetDevThreshold
            let pastRefractory = (painterTau - lastBurstTau[i]) > refractory
            if active && pastRefractory {
                spawnBurst(stem: i, stems: stems, aspect: aspect)
                lastBurstTau[i] = painterTau
            }
        }
    }

    func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let tt = clamp((x - e0) / (e1 - e0), 0, 1)
        return tt * tt * (3 - 2 * tt)
    }
    func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float { min(max(x, lo), hi) }
    func mix(_ x0: Float, _ x1: Float, _ frac: Float) -> Float { x0 + (x1 - x0) * frac }

    /// sRGB → linear (the standard EOTF). Decodes a display-space palette colour to the linear
    /// value the shader outputs, so the `.bgra8Unorm_srgb` store round-trips back to the display
    /// colour (FA #71). Applied once per palette entry at init.
    static func srgbToLinear(_ col: SIMD3<Float>) -> SIMD3<Float> {
        func decode(_ val: Float) -> Float {
            val <= 0.04045 ? val / 12.92 : pow((val + 0.055) / 1.055, 2.4)
        }
        return SIMD3(decode(col.x), decode(col.y), decode(col.z))
    }

    // MARK: - Per-stem feature accessors (same-file extension — see the type_body_length note above)

    func centroid(of stem: SkeinStem, stems: StemFeatures) -> Float {
        switch stem {
        case .drums: return stems.drumsCentroid
        case .bass: return stems.bassCentroid
        case .vocals: return stems.vocalsCentroid
        case .other: return stems.otherCentroid
        }
    }

    func attackRatio(of stem: SkeinStem, stems: StemFeatures) -> Float {
        switch stem {
        case .drums: return stems.drumsAttackRatio
        case .bass: return stems.bassAttackRatio
        case .vocals: return stems.vocalsAttackRatio
        case .other: return stems.otherAttackRatio
        }
    }
}

// MARK: - SkeinState structural-section signal (Skein.ENGINE.3, D-151)

/// The live structural-section channel (read accessors + the `_tick` ingest helper) in a same-file
/// extension — `private` members of a type are visible to same-file extensions (SE-0169), so `_tick`
/// reaches `ingestStructure` and the accessors reach the private fields, while the class body stays
/// within the SwiftLint `type_body_length` budget (the same reason the math helpers are split out).
/// STORED only: nothing here drives geometry/colour/width and none of it reaches the GPU buffer, so
/// the render is byte-identical to pre-ENGINE.3. Skein.5 consumes the stored signal for the bias.
extension SkeinState {

    /// The live structural-section index most recently delivered to `tick` via the
    /// `RenderPipeline.latestStructuralPrediction` bridge (0 until the first prediction arrives /
    /// after reseed). Thread-safe.
    public var currentSectionIndex: UInt32 { lock.withLock { structSectionIndex } }

    /// The current section's start time (s) and the prediction confidence (0–1), as last delivered.
    /// Exposed for Skein.5 + the ENGINE.3 plumbing test. Thread-safe.
    public var currentSectionStartTime: Float { lock.withLock { structSectionStartTime } }
    public var sectionConfidence: Float { lock.withLock { structConfidence } }

    /// True for exactly the one frame on which the delivered section index changed (a detected
    /// section-boundary crossing); false on the first observation and after reseed. Skein.5 will key
    /// the structural anticipation on this — ENGINE.3 only proves it fires. Thread-safe.
    public var didCrossSectionBoundaryThisFrame: Bool { lock.withLock { structBoundaryChanged } }

    /// Ingest the live structural-section prediction (called from `_tick`, lock held). STORES the
    /// section index / start-time / confidence and raises a one-frame boundary flag when the section
    /// index changes. The `StructuralAnalyzer` increments `sectionIndex` monotonically within a track
    /// (reset to 0 on track change, mirrored in `reseed`), so "changed" detects exactly a boundary
    /// crossing.
    func ingestStructure(_ structure: StructuralPrediction) {
        if structInitialized {
            structBoundaryChanged = structure.sectionIndex != structSectionIndex
        } else {
            structInitialized = true   // first observation re-baselines; not a crossing
            structBoundaryChanged = false
        }
        structSectionIndex = structure.sectionIndex
        structSectionStartTime = structure.sectionStartTime
        structConfidence = structure.confidence
    }
}

// MARK: - SkeinState — Skein.5 mood / structure / anticipation

/// The Skein.5 musicality layer (SKEIN_DESIGN §1.3 / §1.5; same-file extension for the same
/// `type_body_length` reason as the others). Musical roles, one sentence each (CLAUDE.md
/// Authoring Discipline — articulated before authoring):
///   • MOOD — the paint being laid warms + saturates and the painter quickens when the song lifts;
///     cools + calms in dark passages. Tint is applied AT LAY TIME and frozen (breakpoints +
///     bursts), so the held canvas archives the song's emotional arc.
///   • STRUCTURE — a confident section boundary makes the painter grab a fresh pour displaced
///     toward that section's own patch (repeated `sectionIndex mod slots` → the same patch —
///     revisit + build density) and briefly flurries the splatter. Confidence-gated: ambiguous
///     material keeps the pure allover read.
///   • ANTICIPATION — the painter's hand coils (slows) over the last fraction of each beat and
///     darts forward (flicks) at the wrap: beat PHASE drives motion, never raw onset (FA #33).
///     Cold-start-safe by construction — a wrong cached phase reads as a mistimed hesitation
///     (small continuous motion offset), not a wrong-beat firing.
///   • LOCUS — a faint luminous pour-point makes "where the paint comes from" legible; display-only
///     (comp fragment), build-flagged, OFF by default.
///
/// FA #67 audit (layer × primitive × timescale): the painter MOTION path is ONE visual channel
/// consuming broadband-dev (s) + arousal envelope (~10 s) + beat phase (sub-s) — multiple
/// timescales into one channel is fine; the rule forbids one timescale into two channels. The
/// splatter TRIGGER stays per-stem onset (the accent); arousal/section-pulse only scale its
/// density envelope. No two visual layers share a primitive timescale.
extension SkeinState {

    /// Skein.5 per-frame musicality state — grouped so the class body carries ONE stored property.
    struct MusicalityState {
        var moodValence: Float = 0          // EMA of features.valence [-1, 1]
        var moodArousal: Float = 0          // EMA of features.arousal [-1, 1]
        var sectionWarm: Float = 0          // per-section warmth emphasis (± small valence bias)
        var sectionLean = SIMD2<Float>(0, 0)        // current region lean (EMA toward target)
        var sectionLeanTarget = SIMD2<Float>(0, 0)  // this section's patch offset (conf-scaled)
        var sectionPulse: Float = 0         // boundary density pulse, decays exp(τ≈2.5 s)
        var boundaryPourPending: Float = 0  // 1 at a confident boundary → forces a fresh pour
        var prevBeatPhase: Float = 0        // beatPhase01 last frame (wrap detection)
        var flickEnv: Float = 0             // flick release envelope, decays exp(τ≈90 ms)
        var speedFactor: Float = 1          // diagnostic: last anticipation factor (tests)
    }

    // MARK: Skein.5 constants

    /// Painter-locus default: OFF (build flag — flip only via the init parameter; production
    /// constructs SkeinState without it, so the locus never ships on unless deliberately enabled).
    public static var defaultLocusEnabled: Bool { false }

    /// Mood EMA time constant (s) — a slow global modulator (§1.3), far below any rhythmic rate.
    static var moodTau: Float { 4.0 }
    /// Valence → warmth: per-channel multiplicative tint gains (R warms up / B cools down with +v).
    /// Multiplicative on vivid linear colours — NEVER the `mix(cream, hue, sat)` anti-pattern; a
    /// bounded ±18 % tint cannot push the dark/vivid palette into pale-dominant territory.
    static var moodWarmR: Float { 0.18 }
    static var moodWarmG: Float { 0.04 }
    static var moodCoolB: Float { 0.16 }
    /// Valence → saturation around luma: +v saturates, −v restrains — floored well above pale-wash.
    static var moodSatGain: Float { 0.20 }
    static var moodSatFloor: Float { 0.85 }
    /// Arousal → painter speed (×[0.7, 1.3] over arousal ∈ [-1, 1]) and splatter density / width.
    static var arousalSpeedGain: Float { 0.30 }
    static var arousalDensityGain: Float { 0.50 }
    static var arousalWidthGain: Float { 0.15 }
    /// Anticipation (FA #33): wind-up depth over the last (1 − windupStart) of the beat, flick
    /// release gain + decay. Windup slows the hand to ~0.55×; the flick briefly surges to ~1.9×.
    static var windupStart: Float { 0.70 }
    static var windupDepth: Float { 0.45 }
    static var flickGain: Float { 0.90 }
    static var flickTau: Float { 0.09 }
    /// Structure bias (all conf-gated): lean radius (≤ this, scaled by confidence), lean approach
    /// EMA, boundary pulse decay, pulse → splatter-density gain, per-section warmth emphasis, the
    /// region-slot count (sectionIndex mod slots → repeated sections revisit the same patch), and
    /// the minimum dwell before a boundary may force a fresh pour (keeps D-150 long pours intact).
    static var sectionLeanRadius: Float { 0.085 }
    static var sectionLeanTau: Float { 2.5 }
    static var sectionPulseTau: Float { 2.5 }
    static var sectionDensityGain: Float { 1.2 }
    static var sectionWarmBias: Float { 0.10 }
    static var sectionSlots: Int { 5 }
    static var boundaryPourMinTau: Float { 1.0 }
    /// Confidence gate (smoothstep lo→hi): below lo the structural bias is exactly zero.
    static var sectionConfLo: Float { 0.25 }
    static var sectionConfHi: Float { 0.55 }
    /// Skein.5.1: the FIRST pour commits only after this much painter-clock settle (≈ a quarter
    /// second of music through the 0.3 s stem EMA), so its colour reflects the actual lead stem,
    /// not one frame's instantaneous argmax (the D-150 decisiveness principle applied to the first
    /// commit). Invisible to the viewer: the retro-colour (`tauStart = 0`) paints the settle
    /// window's trajectory in the committed colour the moment it commits.
    static var firstPourSettleTau: Float { 0.25 }

    // MARK: Skein.5 tick helpers (called from `_tick`, lock held)

    /// EMA-smooth valence/arousal from the read-only FeatureVector (FA #25 — never written back).
    func updateMood(features: FeatureVector, dt: Float) {
        let alpha = min(dt / Self.moodTau, 1.0)
        m5.moodValence += (clamp(features.valence, -1, 1) - m5.moodValence) * alpha
        m5.moodArousal += (clamp(features.arousal, -1, 1) - m5.moodArousal) * alpha
    }

    /// Section-boundary bias: on a confident boundary set the pulse, the fresh-pour flag, the
    /// section's lean target (seed + sectionIndex-slot deterministic — §5.7) and its warmth
    /// emphasis; every frame decay the pulse and EMA-approach the lean.
    func updateSectionBias(dt: Float, stemMix: Float) {
        m5.sectionPulse *= exp(-dt / Self.sectionPulseTau)
        m5.boundaryPourPending *= exp(-dt / 2.0)   // an unconsumed boundary kick expires
        let confGate = smoothstep(Self.sectionConfLo, Self.sectionConfHi, structConfidence)
        if structBoundaryChanged && confGate > 0.001 && stemMix > 0.001 {
            m5.sectionPulse = max(m5.sectionPulse, confGate)
            if confGate >= 0.3 { m5.boundaryPourPending = 1.0 }
            let slot = Int(structSectionIndex) % Self.sectionSlots
            let seedAngle = Float(seed & 0xFFFF) / Float(0xFFFF) * 2 * .pi
            let ang = seedAngle + Float(slot) * Self.breakJumpGoldenAngle
            m5.sectionLeanTarget = SIMD2<Float>(cos(ang), sin(ang)) * (Self.sectionLeanRadius * confGate)
            m5.sectionWarm = (slot % 2 == 0 ? 1.0 : -1.0) * Self.sectionWarmBias * confGate
        }
        let alpha = min(dt / Self.sectionLeanTau, 1.0)
        m5.sectionLean += (m5.sectionLeanTarget - m5.sectionLean) * alpha
    }

    /// Beat-anticipation speed factor: coil (slow) on the rising edge of `beatPhase01`, release
    /// into a flick (brief surge) at the wrap. Returns 1.0 at silence (stemMix → 0) so the silence
    /// pour line stays byte-identical (the Skein.1 continuity gate).
    func anticipationFactor(features: FeatureVector, dt: Float, stemMix: Float) -> Float {
        let phase = clamp(features.beatPhase01, 0, 1)
        if m5.prevBeatPhase - phase > 0.5 { m5.flickEnv = 1.0 }   // wrap = the beat lands → release
        m5.prevBeatPhase = phase
        m5.flickEnv *= exp(-dt / Self.flickTau)
        let windup = smoothstep(Self.windupStart, 1.0, phase)
        let factor = 1.0 - Self.windupDepth * windup + Self.flickGain * m5.flickEnv
        return mix(1.0, factor, stemMix)
    }

    /// Mood-tint a LINEAR palette colour (lay-time; frozen into breakpoints/bursts). Valence (plus
    /// the per-section warmth emphasis) warms/cools multiplicatively and scales saturation around
    /// luma. v = 0 ⇒ exact identity (existing tests and the silence path are byte-identical).
    func moodTinted(_ linear: SIMD3<Float>) -> SIMD3<Float> {
        let val = min(max(m5.moodValence + m5.sectionWarm, -1), 1)
        return Self.moodTint(linear, valence: val)
    }

    /// The pure mood-tint math (static so the Skein.5.3 palette-library separability gate
    /// exercises the EXACT production transform): multiplicative warm/cool on R/B + saturation
    /// scaled around luma, clamped. Identity at valence = 0.
    static func moodTint(_ linear: SIMD3<Float>, valence: Float) -> SIMD3<Float> {
        if abs(valence) < 1e-5 { return linear }
        var col = linear * SIMD3<Float>(1 + Self.moodWarmR * valence,
                                        1 + Self.moodWarmG * valence,
                                        1 - Self.moodCoolB * valence)
        let luma = col.x * 0.2126 + col.y * 0.7152 + col.z * 0.0722
        let sat = max(Self.moodSatFloor, 1 + Self.moodSatGain * valence)
        col = SIMD3<Float>(repeating: luma) + (col - SIMD3<Float>(repeating: luma)) * sat
        return SIMD3<Float>(min(max(col.x, 0), 1), min(max(col.y, 0), 1), min(max(col.z, 0), 1))
    }

    // MARK: Skein.5 test-facing accessors (thread-safe)

    /// Smoothed mood values as consumed by the tint/vigour routing.
    public var moodValenceSmoothed: Float { lock.withLock { m5.moodValence } }
    public var moodArousalSmoothed: Float { lock.withLock { m5.moodArousal } }
    /// The current structural region lean (UV offset added to each new pour) and boundary pulse.
    public var sectionLeanCurrent: SIMD2<Float> { lock.withLock { m5.sectionLean } }
    public var sectionPulseCurrent: Float { lock.withLock { m5.sectionPulse } }
    /// Last frame's anticipation speed factor (wind-up < 1, flick > 1; 1 at silence).
    public var anticipationFactorCurrent: Float { lock.withLock { m5.speedFactor } }
}
