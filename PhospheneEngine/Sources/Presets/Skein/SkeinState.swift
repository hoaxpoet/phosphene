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
    var pad1: Float
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
                 palette: [SIMD3<Float>] = SkeinState.defaultPalette) {
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
        resetColorBreaks()   // seed the line-colour ring with the white baseline (Skein.4.1)
        writeToGPU()
    }

    // MARK: - Public API

    /// Update the painter integrators + onset-burst ring for one rendered frame, then flush.
    ///
    /// Call once per frame from the render-loop tick hook (setMeshPresetTick) before the overlay
    /// draw reads buffer(6).
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        lock.withLock { _tick(deltaTime: deltaTime, features: features, stems: stems) }
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
            resetColorBreaks()   // clear the line-colour ring + re-seed the white baseline (Skein.4.1)
            lineFlow = 0; lineVisc = 0; jitter = 0
            for i in 0..<4 {
                stemEnergySmoothed[i] = 0
                lastBurstTau[i] = -1
            }
        }
        writeToGPU()
    }

    // MARK: - Private: seed → trajectory phase

    /// Map the per-track seed to a pair of trajectory phase offsets in [0, 2π). Same seed → same
    /// offsets → same painting (the §5.7 determinism property).
    private func applySeed(_ seedValue: UInt32) {
        seedPhaseX = Float(seedValue & 0xFFFF) / Float(0xFFFF) * 2 * .pi
        seedPhaseY = Float((seedValue >> 16) & 0xFFFF) / Float(0xFFFF) * 2 * .pi
    }

    // MARK: - Private: tick (called while holding lock)

    private func _tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        let dt = max(deltaTime, 0.001)

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

        // Painter speed ← broadband energy deviation (mean of the four positive devs), with an
        // FV fallback (midAttRel) during warmup. NOT arousal (Skein.5).
        let broadbandDev = (dev[0] + dev[1] + dev[2] + dev[3]) * 0.25
        let speedStem = Self.paintSpeedBase + Self.paintSpeedGain * broadbandDev
        let speedFV = Self.paintSpeedBase + 1.5 * max(0, features.midAttRel)
        let paintSpeed = mix(speedFV, speedStem, stemMix)
        painterTauStep = dt * paintSpeed
        painterTau += painterTauStep

        // Dominant stem → line colour (DISCRETE argmax of smoothed energy — never a colour-space
        // blend, so the continuous line is never a 50/50 mud). Below the warmup floor the canvas
        // rests; keep the prior colour. Line flow + viscosity from the dominant stem.
        var domIdx = 0
        var domVal = stemEnergySmoothed[0]
        for i in 1..<4 where stemEnergySmoothed[i] > domVal { domVal = stemEnergySmoothed[i]; domIdx = i }
        // Only switch the line colour once the canvas is warm; below the floor keep the prior hue.
        if stemMix > 0.001 {
            // Skein.4.1: a dominant-stem switch starts a genuinely NEW pour (new colour + a displaced
            // jump — the breakpoint ring; the redrawn tail then freezes each segment at its lay-time
            // colour, so the line no longer recolours along its length). But the dominant ARGMAX
            // flickers far faster than a pour can read (Matt M7 2026-06-09: "the lines are very short
            // rather than a long continuous dripping/pouring" — measured 63 switches / 44 s, median pour
            // 0.2 s). So a new pour COMMITS only on a SUSTAINED, DECISIVE change: the current pour must
            // have lasted `minPourTau` (the long-stroke guarantee), and the challenger must lead the
            // incumbent by the hysteresis margin (no flicker between near-equal stems). The first pour
            // commits immediately. The bursts still fire per-stem onset, ungated (they are the accents).
            let committed: Bool
            if lineDomIdx == -1 {
                committed = true
            } else {
                committed = domIdx != lineDomIdx
                    && (painterTau - lastSwitchTau) >= Self.minPourTau
                    && stemEnergySmoothed[domIdx] > stemEnergySmoothed[lineDomIdx] * Self.pourSwitchHysteresis
            }
            if committed {
                pushColorBreak(tauStart: painterTau, color: paletteLinear[domIdx])
                lineDomIdx = domIdx
                lastSwitchTau = painterTau
            }
            // Colour / flow / viscosity all reflect the COMMITTED pour (lineDomIdx), so the whole pour
            // is coherent — the colour the breakpoint ring renders + a matching width/viscosity — and
            // the width doesn't breathe with a louder non-committed stem mid-pour.
            lineCol = paletteLinear[lineDomIdx]
            lineFlow = stemEnergySmoothed[lineDomIdx] * stemMix
            let domCentroid = centroid(of: SkeinStem(rawValue: lineDomIdx) ?? .drums, stems: stems)
            lineVisc = clamp(1.0 - domCentroid, 0, 1) * stemMix

            // Local jitter ← high-band energy / onset rate (a fast continuous primitive distinct
            // from the per-beat onset accents and the slow painter speed — one primitive per
            // layer, FA #67). 4–8 kHz air/high-mid.
            let highBand = stems.vocalsBand1 + stems.otherBand1
            jitter = clamp(highBand * 0.5 * stemMix, 0, 1)
        } else {
            lineFlow = 0; lineVisc = 0; jitter = 0
        }

        // Per-stem ACTIVITY → splatter burst (energy_dev above threshold, rate-limited by the
        // refractory → a busier stem flicks more). The burst is frozen at the painter's current
        // position, in the stem's colour, with size from attackRatio and viscosity from centroid.
        // Gated by warmup so silence lays nothing.
        if stemMix > 0.001 {
            for i in 0..<4 {
                let active = dev[i] > Self.onsetDevThreshold
                let pastRefractory = (painterTau - lastBurstTau[i]) > Self.onsetRefractory
                if active && pastRefractory {
                    spawnBurst(stem: i, stems: stems, aspect: features.aspectRatio)
                    lastBurstTau[i] = painterTau
                }
            }
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
        let col = paletteLinear[stem]

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

    // MARK: - Private: painter trajectory (mirrors skeinPainterPos in Skein.metal + seed phases)

    /// The CPU mirror of `skeinPainterPos(t)` in Skein.metal, with the per-track seed phase
    /// offsets added. Kept in sync by review (the static-source guard asserts the shader still
    /// declares `skeinPainterPos`). Used to freeze a burst's flick point + throw direction.
    private func painterPos(_ tau: Float) -> SIMD2<Float> {
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

    // MARK: - Private: per-stem feature accessors

    private func centroid(of stem: SkeinStem, stems: StemFeatures) -> Float {
        switch stem {
        case .drums: return stems.drumsCentroid
        case .bass: return stems.bassCentroid
        case .vocals: return stems.vocalsCentroid
        case .other: return stems.otherCentroid
        }
    }

    private func attackRatio(of stem: SkeinStem, stems: StemFeatures) -> Float {
        switch stem {
        case .drums: return stems.drumsAttackRatio
        case .bass: return stems.bassAttackRatio
        case .vocals: return stems.vocalsAttackRatio
        case .other: return stems.otherAttackRatio
        }
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
                pad1: 0,
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

    /// Clear the line-colour ring and seed it with the white baseline at τ = 0, zero offset (the
    /// cold/warmup line colour, the continuous un-jumped pour). Every tail sample laid before the first
    /// dominant-stem switch resolves to white-no-jump; at silence only this baseline exists, so the
    /// silence pour line is the byte-identical pre-Skein.4.1 continuous white line. init + reseed call it.
    private func resetColorBreaks() {
        colorBreaks.removeAll(keepingCapacity: true)
        colorBreaks.append(SkeinBreakGPU(tauStart: 0, colR: 1, colG: 1, colB: 1, offX: 0, offY: 0))
        lineDomIdx = -1
        lastSwitchTau = 0
        colorBreakCounter = 0
        currentLineOffset = SIMD2<Float>(0, 0)
    }

    /// Push a breakpoint (the painter-clock value at a dominant-stem switch + the new LINEAR colour +
    /// a bounded new-pour jump offset). The jump is a fixed-magnitude vector rotated by the golden angle
    /// per switch (non-cumulative → never drifts off canvas; well-separated → a clear gap every switch).
    /// Evicts the oldest when the ring is full — the 16 most-recent switches always cover the live tail.
    private func pushColorBreak(tauStart: Float, color: SIMD3<Float>) {
        colorBreakCounter &+= 1
        let seedAngle = Float(seed & 0xFFFF) / Float(0xFFFF) * 2 * .pi
        let ang = seedAngle + Float(colorBreakCounter) * Self.breakJumpGoldenAngle
        let off = SIMD2<Float>(cos(ang), sin(ang)) * Self.breakJumpMagnitude
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
}
