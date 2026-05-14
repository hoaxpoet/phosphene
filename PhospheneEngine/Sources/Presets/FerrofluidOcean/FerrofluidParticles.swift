// swiftlint:disable file_length
// FerrofluidParticles — Phase 1 scaffolding for V.9 Session 4.5b particle motion.
//
// Owns the GPU-side resources that feed a baked height texture into the
// FerrofluidOcean ray-march scene SDF. Phase 1 is **scaffolding only**:
// particle positions are computed once at init time at the same XZ
// coordinates a `voronoi_smooth` cell-center pass would emit (rectangular
// scaled-space integer cells + per-cell `voronoi_cell_offset` hash), and a
// one-shot compute dispatch bakes the height field. The substrate visual
// reading is therefore structurally equivalent to Phase A's inline
// `voronoi_smooth`-based `fo_ferrofluid_field` — the geometric source has
// moved from "inline math in sceneSDF" to "texture sample in sceneSDF", but
// the shape is the same hex-pack pyramid field with organic non-uniformity.
//
// Phase 2 will add an SPH-lite particle update compute pass + audio forces
// that move the particles per frame; Phase 3 tunes against the
// `docs/VISUAL_REFERENCES/ferrofluid_ocean/` reference set. See the V.9
// Session 4.5b prompt for the phase contract.
//
// Bound at fragment texture slot 10 of the ray-march G-buffer pass via
// `RenderPipeline.setRayMarchPresetHeightTexture`. Non-Ferrofluid ray-march
// presets receive the zero-filled `RayMarchPipeline.ferrofluidHeightPlaceholderTexture`
// so the preamble's `[[texture(10)]]` declaration is always satisfied.
//
// **Scope discipline (Failed Approach #58 / #62):** every constant below
// has a *load-bearing* role in producing the Phase A-equivalent surface.
// No decoration, no premature flexibility. Phase 2 may grow new constants
// for motion physics; Phase 1 does not.

import Foundation
import Metal
import simd
import Shared
import os.log

private let particleLogger = Logger(subsystem: "com.phosphene.presets", category: "FerrofluidParticles")

// MARK: - FerrofluidParticles

/// Owns the particle buffer + height texture + bake compute pipeline for
/// Ferrofluid Ocean V.9 Session 4.5b. Construct once per preset apply;
/// `bakeHeightField(commandQueue:)` runs a one-shot compute dispatch that
/// blocks the caller until the texture is populated.
///
/// Thread-safety: this class is constructed and `bake` is invoked from
/// `@MainActor` on the preset-apply path. The exposed `heightTexture` /
/// `particleBuffer` are read by GPU command encoders thereafter and not
/// mutated again at Phase 1 (particles are static).
public final class FerrofluidParticles: @unchecked Sendable {

    // MARK: - Locked parameters (Phase 1)

    /// Particle count: original spec was 2048 ("medium density"); **density
    /// pass 2026-05-14 bumped to 6000** after Matt's review of the tuned
    /// contact sheet flagged the static spikes as still too sparse vs the
    /// Phase A `voronoi_smooth` reference. The earlier "medium ~2000"
    /// framing was a forecast before the Phase A render was available; in
    /// practice, 2048 particles in the 20-world-unit patch produce ~0.44 wu
    /// spacing, leaving ~0.13 wu gaps between peak bases at the tuned 0.15
    /// peak radius. Phase A's `voronoi_smooth(scale = 4)` places cells at
    /// 0.25 wu spacing → peaks overlap base-to-base. Matching that density
    /// over the 20×20 patch needs 80 × 75 = 6000 cells (X spacing 0.25 wu
    /// matches Phase A exactly; Z spacing 0.267 wu adds a ~7 % anisotropy
    /// that's invisible at the camera tilt). Phase 2 per-frame bake cost
    /// scales linearly: ~0.6 ms per bake on Apple Silicon at 6000 particles
    /// × 1024² texels, well within the 60 fps frame budget.
    public static let particleCount: Int = 6000

    /// Height texture: original spec 512² → 1024² (Matt 2026-05-14
    /// fullscreen/4K product addendum) → 2048² (smoothness pass
    /// 2026-05-14) → **4096² (texel-grid pass 2026-05-14)**. Matt's
    /// zoomed-in beat-heavy screenshot confirmed visible texel-grid
    /// staircasing in the bilinear-sampled height field. At 2048² the
    /// ratio was 1.6 screen pixels per texel at 1080p — texel grid
    /// dominated screen sampling. At 4096² the ratio drops to 0.78
    /// screen pixels per texel; multiple texels are bilinear-averaged
    /// per screen pixel and the staircase falls below the rendered-pixel
    /// scale. Texture memory: 4096² × 2 B = 32 MB. Phase 1 bake cost
    /// (one-shot) ~10 ms — still fine. Phase 2 per-frame bake would be
    /// ~10 ms — significant fraction of the 16.67 ms 60 fps budget;
    /// revisit at Phase 2 perf gate (likely needs spatial-hash binning
    /// to keep per-frame cost bounded, which Leitl's actual recipe
    /// already uses).
    public static let heightTextureSize: Int = 4096

    /// World-XZ rectangle the texture covers. Generous around the camera's
    /// visible patch (camera at (0, 4, -2.5) looking at (0, 0, 2.0)) so the
    /// texture's clamp-to-zero edge sits well outside the rendered frame.
    public static let worldOriginX: Float = -10.0
    public static let worldOriginZ: Float = -8.0
    public static let worldSpan: Float = 20.0

    /// Quilez polynomial smooth-min weight. Original spec was Leitl's
    /// `w = 0.1` default; **tuning pass 2026-05-14 dropped to 0.02** after
    /// Matt's review of the static contact sheet flagged the smoothed-out
    /// peaks (the V.9 prompt explicitly permitted this revisit: "Revisit
    /// only if rendering shows peaks merging or staying too discrete").
    /// `0.02` produces a much sharper smooth-min transition between
    /// adjacent particles — closer to Phase A's `voronoi_smooth k = 32`
    /// effective smoothness band of ~0.008 world units. Phase 2 motion
    /// may require bumping back up to avoid pop-in artifacts as particles
    /// move past each other; revisit at Phase 2 STOP gate.
    public static let smoothMinW: Float = 0.02

    /// Spike base radius in world units. The bake produces a tent-shaped
    /// peak at each particle that falls to zero at `spikeBaseRadius`.
    /// **Tuning pass 2026-05-14 dropped from 0.25 → 0.15** to match Phase
    /// A's effective world-unit peak radius (`voronoi_smooth(scale = 4.0)`
    /// with `kSpikeRadius = 0.6` scaled-space units → 0.6 / 4 = 0.15
    /// world units). Wider radii overlap neighbouring particles into a
    /// continuous mound rather than discrete spikes (Matt's 2026-05-14
    /// review: "peak tips not present, dark troughs not present").
    public static let spikeBaseRadius: Float = 0.15

    /// Apex-rounding parameter for `almostIdentity` smoothing on the
    /// soft-min output. **Tuning pass 2026-05-14 dropped from 0.1 → 0.03**
    /// to keep peak tips razor-sharp per `04_specular_razor_highlights.jpg`.
    /// Leitl's 0.1 reads as ferrofluid peaks on his demo scale; at
    /// Phosphene's larger world patch the same 0.1 rounded apexes that
    /// should be near-conical for sharp specular catches.
    public static let apexSmoothK: Float = 0.03

    // MARK: - Spatial-hash grid (Phase 2a)

    /// Uniform-grid side length over the world patch. 64 × 64 = 4096 cells.
    /// Cell size in world units = `worldSpan / cellGridSide` = 0.3125 wu
    /// (about 2× `spikeBaseRadius`). Each cell holds 1-2 particles in
    /// equilibrium at Phase 1 density; motion headroom is the per-cell
    /// slot count below.
    public static let cellGridSide: Int = 64

    /// Maximum particles per cell. Phase 1 static density sees 1-2/cell;
    /// 16 slots gives 8-16× headroom for Phase 2 motion (particle clusters
    /// from SPH pressure under bass impulses). Overflow is silently dropped
    /// at the bin kernel level — guard rails added per CLAUDE.md
    /// "no allocation in the IO callback" spirit applied to the GPU path.
    public static let cellSlotCapacity: Int = 16

    // MARK: - Particle state (Phase 2b)

    /// Per-particle state mirrored byte-for-byte on the GPU side. Position
    /// is world-XZ; velocity is world-XZ per second. Padded to 16 bytes so
    /// SIMD loads / `device float4` reads stay 16-byte aligned.
    public struct Particle: Equatable {
        public var positionX: Float
        public var positionZ: Float
        public var velocityX: Float
        public var velocityZ: Float

        public init(positionX: Float, positionZ: Float, velocityX: Float = 0, velocityZ: Float = 0) {
            self.positionX = positionX
            self.positionZ = positionZ
            self.velocityX = velocityX
            self.velocityZ = velocityZ
        }

        public var position: SIMD2<Float> { SIMD2(positionX, positionZ) }
        public var velocity: SIMD2<Float> { SIMD2(velocityX, velocityZ) }
    }

    // MARK: - GPU resources

    /// UMA buffer of 6000 `Particle` structs (position + velocity in world
    /// XZ). 16 bytes per particle × 6000 = 96 KiB. Phase 2b: written once
    /// at init, then per frame by the SPH-lite update pass.
    public let particleBuffer: MTLBuffer

    /// UMA buffer of per-cell occupancy counts (`atomic_uint`, one per
    /// cell). Reset every bake; bin kernel atomically increments. Sized
    /// `cellGridSide² × sizeof(UInt32)` = 16 KB. (Phase 2a.)
    public let cellCountBuffer: MTLBuffer

    /// UMA buffer of per-cell particle index slots (`uint`, capacity ×
    /// per-cell). Bin kernel writes the particle index at the
    /// pre-increment count's slot. Sized
    /// `cellGridSide² × cellSlotCapacity × sizeof(UInt32)` = 256 KB.
    /// (Phase 2a.)
    public let cellSlotBuffer: MTLBuffer

    /// UMA r16Float 512×512 texture carrying the baked height field.
    /// Sampled at fragment texture slot 10 of the ray-march G-buffer pass.
    /// Linear filter + clamp-to-zero (`access::sample` in the .metal side).
    public let heightTexture: MTLTexture

    // MARK: - Internal

    private let bakePipeline: MTLComputePipelineState
    private let resetCellsPipeline: MTLComputePipelineState
    private let binParticlesPipeline: MTLComputePipelineState
    private let updateParticlesPipeline: MTLComputePipelineState
    private let device: MTLDevice

    /// Bake parameters mirrored on the GPU side via a 32-byte struct.
    /// (Phase 2a extended with grid metadata.)
    private struct BakeUniforms {
        var worldOriginXZ: SIMD2<Float>     // (worldOriginX, worldOriginZ)
        var worldSpan: Float                // worldSpan
        var smoothMinW: Float               // smoothMinW
        var spikeBaseRadius: Float          // spikeBaseRadius
        var apexSmoothK: Float              // apexSmoothK
        var particleCount: UInt32           // particleCount
        var cellGridSide: UInt32            // cellGridSide
        var cellSlotCapacity: UInt32        // cellSlotCapacity
        var pad0: UInt32                    // 16-byte align
        var pad1: UInt32                    // 16-byte align
    }

    /// Per-frame update uniforms for `ferrofluid_particle_update`. Phase 2c
    /// extends with the four audio inputs (bass / drums-smoothed / other /
    /// arousal), `accumulated_audio_time` for rotational drift, and grid
    /// metadata (cell side / capacity / world XZ patch + the canonical-
    /// grid rows/columns) for spatial-hash neighbour lookup and on-the-fly
    /// canonical-position recomputation. 64 bytes, 16-byte aligned.
    private struct UpdateUniforms {
        var dt: Float
        var particleCount: UInt32
        var accumulatedAudioTime: Float
        var arousal: Float

        var bassEnergyDev: Float
        var drumsEnergyDevSmoothed: Float
        var otherEnergyDev: Float
        var pressureBaseRadius: Float

        var worldOriginXZ: SIMD2<Float>
        var worldSpan: Float
        var cellGridSide: UInt32

        var cellSlotCapacity: UInt32
        var gridColumns: UInt32
        var gridRows: UInt32
        var pad0: UInt32
    }

    // MARK: - CPU-side smoothing state (Phase 2c)

    /// Smoothed `stems.drumsEnergyDev` envelope (150 ms τ). Drives the drums
    /// shock-impulse force without edge-triggering, satisfying
    /// `Scripts/check_drums_beat_intensity.sh` + Failed Approach #4 (beat
    /// onsets are never a primary motion driver). Guarded by `lock` because
    /// the per-frame closure is captured weakly and may be called from
    /// non-MainActor threads.
    private var smoothedDrumsEnergyDev: Float = 0
    private let lock = NSLock()

    // MARK: - Init

    // Sequential GPU resource allocation with consistent error-handling
    // produces a body slightly over the 60-line cap — fragmenting into
    // helpers would split the resource-acquire / pipeline-create flow
    // without making either part more readable.
    // swiftlint:disable function_body_length

    /// Construct the particles + height texture for Ferrofluid Ocean.
    ///
    /// - Parameters:
    ///   - device: Metal device for buffer / texture / pipeline creation.
    ///   - library: Compiled engine `Renderer` library containing the
    ///     `ferrofluid_height_bake` kernel.
    /// - Returns: `nil` if any GPU allocation fails. The caller logs and
    ///   falls back to the placeholder height texture (substrate renders
    ///   without spikes — Gerstner swell only).
    public init?(device: MTLDevice, library: MTLLibrary) {
        self.device = device

        // Particle buffer: 6000 × 16 bytes = 96 KiB. UMA shared storage so
        // the kernel reads from CPU-written memory without a blit.
        let particleStride = MemoryLayout<Particle>.stride
        let bufferLength = Self.particleCount * particleStride
        guard let buf = device.makeBuffer(length: bufferLength,
                                          options: .storageModeShared) else {
            particleLogger.error("FerrofluidParticles: particle buffer allocation failed")
            return nil
        }
        self.particleBuffer = buf

        // Spatial-hash buffers (Phase 2a). Count buffer: one UInt32 per
        // cell, atomically incremented by the bin kernel. Slot buffer:
        // capacity UInt32s per cell, holding particle indices. Both UMA
        // shared so the bin kernel atomically writes and the bake kernel
        // reads in the same dispatch.
        let cellCount = Self.cellGridSide * Self.cellGridSide
        let cellCountBytes = cellCount * MemoryLayout<UInt32>.stride
        guard let countBuf = device.makeBuffer(length: cellCountBytes,
                                               options: .storageModeShared) else {
            particleLogger.error("FerrofluidParticles: cell count buffer allocation failed")
            return nil
        }
        self.cellCountBuffer = countBuf

        let slotBytes = cellCount * Self.cellSlotCapacity * MemoryLayout<UInt32>.stride
        guard let slotBuf = device.makeBuffer(length: slotBytes,
                                              options: .storageModeShared) else {
            particleLogger.error("FerrofluidParticles: cell slot buffer allocation failed")
            return nil
        }
        self.cellSlotBuffer = slotBuf

        // Height texture: r16Float, NxN, UMA shared, read-write so the
        // compute kernel can write and the G-buffer fragment can sample.
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float,
            width: Self.heightTextureSize,
            height: Self.heightTextureSize,
            mipmapped: false)
        texDesc.storageMode = .shared
        texDesc.usage = [.shaderRead, .shaderWrite]
        guard let tex = device.makeTexture(descriptor: texDesc) else {
            particleLogger.error("FerrofluidParticles: height texture allocation failed")
            return nil
        }
        self.heightTexture = tex

        // Compute pipelines from the engine library. All three kernels
        // live in `Renderer/Shaders/FerrofluidParticles.metal`.
        guard let bakeFn = library.makeFunction(name: "ferrofluid_height_bake") else {
            particleLogger.error("FerrofluidParticles: ferrofluid_height_bake function not found")
            return nil
        }
        guard let resetFn = library.makeFunction(name: "ferrofluid_reset_cell_counts") else {
            particleLogger.error("FerrofluidParticles: ferrofluid_reset_cell_counts function not found")
            return nil
        }
        guard let binFn = library.makeFunction(name: "ferrofluid_bin_particles") else {
            particleLogger.error("FerrofluidParticles: ferrofluid_bin_particles function not found")
            return nil
        }
        guard let updateFn = library.makeFunction(name: "ferrofluid_particle_update") else {
            particleLogger.error("FerrofluidParticles: ferrofluid_particle_update function not found")
            return nil
        }
        do {
            self.bakePipeline = try device.makeComputePipelineState(function: bakeFn)
            self.resetCellsPipeline = try device.makeComputePipelineState(function: resetFn)
            self.binParticlesPipeline = try device.makeComputePipelineState(function: binFn)
            self.updateParticlesPipeline = try device.makeComputePipelineState(function: updateFn)
        } catch {
            particleLogger.error("FerrofluidParticles: pipeline creation failed: \(error)")
            return nil
        }

        // Populate initial particle positions at voronoi-equivalent XZ.
        writeInitialParticlePositions()
    }

    // swiftlint:enable function_body_length

    // MARK: - Public API

    /// Run the one-shot bake compute dispatch and block until the texture is
    /// populated. Synchronous: the caller (preset-apply on `@MainActor`)
    /// expects the texture to be ready before the next frame draws. The
    /// dispatch is ~1 ms on Apple Silicon at 512×512 × 2048 particles, so
    /// blocking is acceptable on the preset-switch path.
    ///
    /// Idempotent: calling more than once re-bakes from the current particle
    /// buffer contents. Phase 1's particles never change, so the second
    /// invocation produces a byte-identical texture; useful only for tests.
    public func bakeHeightField(commandQueue: MTLCommandQueue) {
        guard let cmdBuf = commandQueue.makeCommandBuffer() else {
            particleLogger.error("FerrofluidParticles.bakeHeightField: makeCommandBuffer returned nil")
            return
        }
        encodeBake(into: cmdBuf)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        if let err = cmdBuf.error {
            particleLogger.error("FerrofluidParticles.bakeHeightField: command buffer error: \(err)")
        }
    }

    /// Encode the bake compute dispatch chain into the caller's command buffer
    /// without committing. Three kernels run in sequence inside one encoder:
    ///   1. `ferrofluid_reset_cell_counts` — zero out the per-cell occupancy
    ///      counters before the next bin pass.
    ///   2. `ferrofluid_bin_particles` — each particle thread atomically
    ///      writes its index to its spatial-hash cell's slot list.
    ///   3. `ferrofluid_height_bake` — each texel thread looks up the 3×3
    ///      cells around its world XZ, soft-mins distances to the bounded
    ///      neighbour particles, applies the linear cone, writes height.
    ///
    /// All three kernels share one `BakeUniforms` constant; the encoder is
    /// torn down at the end. Used by the test harness to bundle the bake
    /// with the subsequent render dispatch in a single command buffer.
    public func encodeBake(into commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            particleLogger.error("FerrofluidParticles.encodeBake: makeComputeCommandEncoder returned nil")
            return
        }
        var uniforms = BakeUniforms(
            worldOriginXZ: SIMD2(Self.worldOriginX, Self.worldOriginZ),
            worldSpan: Self.worldSpan,
            smoothMinW: Self.smoothMinW,
            spikeBaseRadius: Self.spikeBaseRadius,
            apexSmoothK: Self.apexSmoothK,
            particleCount: UInt32(Self.particleCount),
            cellGridSide: UInt32(Self.cellGridSide),
            cellSlotCapacity: UInt32(Self.cellSlotCapacity),
            pad0: 0,
            pad1: 0)

        // Pass 1: reset cell counts to zero. One thread per cell.
        encoder.setComputePipelineState(resetCellsPipeline)
        encoder.setBuffer(cellCountBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms,
                         length: MemoryLayout<BakeUniforms>.stride,
                         index: 1)
        let cellCount = Self.cellGridSide * Self.cellGridSide
        let resetTPG = MTLSize(width: 64, height: 1, depth: 1)
        let resetGroups = MTLSize(width: (cellCount + 63) / 64, height: 1, depth: 1)
        encoder.dispatchThreadgroups(resetGroups, threadsPerThreadgroup: resetTPG)

        // Metal's `MTLComputeCommandEncoder` does NOT serialize consecutive
        // dispatches by default — they may execute concurrently. The bin
        // kernel writes cell counts that the bake kernel reads, so without
        // explicit barriers the bake races against bin and reads stale /
        // mid-write counts. Insert `memoryBarrier(scope: .buffers)` between
        // each dependent dispatch pair.
        encoder.memoryBarrier(scope: .buffers)

        // Pass 2: bin each particle into its cell via atomic fetch-add.
        encoder.setComputePipelineState(binParticlesPipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms,
                         length: MemoryLayout<BakeUniforms>.stride,
                         index: 1)
        encoder.setBuffer(cellCountBuffer, offset: 0, index: 2)
        encoder.setBuffer(cellSlotBuffer, offset: 0, index: 3)
        let binTPG = MTLSize(width: 64, height: 1, depth: 1)
        let binGroups = MTLSize(width: (Self.particleCount + 63) / 64, height: 1, depth: 1)
        encoder.dispatchThreadgroups(binGroups, threadsPerThreadgroup: binTPG)

        encoder.memoryBarrier(scope: .buffers)

        // Pass 3: per-texel bake reads 3×3 cells around its XZ.
        encoder.setComputePipelineState(bakePipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms,
                         length: MemoryLayout<BakeUniforms>.stride,
                         index: 1)
        encoder.setBuffer(cellCountBuffer, offset: 0, index: 2)
        encoder.setBuffer(cellSlotBuffer, offset: 0, index: 3)
        encoder.setTexture(heightTexture, index: 0)
        let bakeTPG = MTLSize(width: 16, height: 16, depth: 1)
        let bakeGroups = MTLSize(
            width: (Self.heightTextureSize + 15) / 16,
            height: (Self.heightTextureSize + 15) / 16,
            depth: 1)
        encoder.dispatchThreadgroups(bakeGroups, threadsPerThreadgroup: bakeTPG)

        encoder.endEncoding()
    }

    /// Encode a single particle-update compute dispatch into the caller's
    /// command buffer. Phase 2c: integrates audio forces (pressure / drums
    /// impulse / rotational drift) + equilibrium spring + damping into
    /// each particle's velocity, then advances `position += velocity × dt`
    /// via semi-implicit Euler. `audio` carries the per-frame uniforms;
    /// when zero (silence), only equilibrium + damping run → particles
    /// settle to canonical positions (gentle baseline drift only).
    ///
    /// Reads the spatial-hash buffers populated by the most recent bake
    /// pass to find neighbour particles for pressure forces. **Callers
    /// must encode a bake before each update** so the spatial-hash
    /// reflects the current positions (`encodePerFrameUpdate` handles the
    /// ordering: bake → update → bake).
    public func encodeUpdate(into commandBuffer: MTLCommandBuffer,
                             dt: Float,
                             audio: UpdateAudio = .silent) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            particleLogger.error("FerrofluidParticles.encodeUpdate: makeComputeCommandEncoder returned nil")
            return
        }
        let layout = Self.canonicalGridLayout()
        var uniforms = UpdateUniforms(
            dt: dt,
            particleCount: UInt32(Self.particleCount),
            accumulatedAudioTime: audio.accumulatedAudioTime,
            arousal: audio.arousal,
            bassEnergyDev: audio.bassEnergyDev,
            drumsEnergyDevSmoothed: audio.drumsEnergyDevSmoothed,
            otherEnergyDev: audio.otherEnergyDev,
            pressureBaseRadius: Self.spikeBaseRadius * 2.0,
            worldOriginXZ: SIMD2(Self.worldOriginX, Self.worldOriginZ),
            worldSpan: Self.worldSpan,
            cellGridSide: UInt32(Self.cellGridSide),
            cellSlotCapacity: UInt32(Self.cellSlotCapacity),
            gridColumns: UInt32(layout.columns),
            gridRows: UInt32(layout.rows),
            pad0: 0)
        encoder.setComputePipelineState(updateParticlesPipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms,
                         length: MemoryLayout<UpdateUniforms>.stride,
                         index: 1)
        encoder.setBuffer(cellCountBuffer, offset: 0, index: 2)
        encoder.setBuffer(cellSlotBuffer, offset: 0, index: 3)
        let tpg = MTLSize(width: 64, height: 1, depth: 1)
        let groups = MTLSize(width: (Self.particleCount + 63) / 64, height: 1, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: tpg)
        encoder.endEncoding()
    }

    /// Per-frame closure entry point. Encodes bake → update → bake into the
    /// caller's command buffer. The first bake populates the spatial-hash
    /// from the previous frame's positions so the update kernel can compute
    /// pressure forces from neighbour lookups; update advances positions by
    /// the integrated force model; the second bake refreshes the height
    /// texture for the G-buffer pass that follows.
    ///
    /// Phase 2c reads `features` / `stems` to derive audio uniforms:
    ///   - `stems.bassEnergyDev`           → pressure radius scale
    ///   - `stems.drumsEnergyDev` (smoothed CPU-side, 150 ms τ) → radial impulse
    ///   - `stems.otherEnergyDev`          → tangential rotation rate
    ///   - `features.arousal`              → global force magnitude scale
    ///   - `features.accumulatedAudioTime` → energy-paused time axis
    public func encodePerFrameUpdate(into commandBuffer: MTLCommandBuffer,
                                     dt: Float,
                                     features: FeatureVector,
                                     stems: StemFeatures) {
        let audio = lock.withLock { () -> UpdateAudio in
            let tauSeconds: Float = 0.150
            let alpha = min(dt / tauSeconds, 1.0)
            let target = max(0, stems.drumsEnergyDev)
            smoothedDrumsEnergyDev += (target - smoothedDrumsEnergyDev) * alpha
            return UpdateAudio(
                accumulatedAudioTime: features.accumulatedAudioTime,
                arousal: max(-1, min(1, features.arousal)),
                bassEnergyDev: max(0, stems.bassEnergyDev),
                drumsEnergyDevSmoothed: smoothedDrumsEnergyDev,
                otherEnergyDev: max(0, stems.otherEnergyDev))
        }
        // bake (re-populates spatial hash from current positions) → update
        // (consumes hash for pressure neighbour lookup) → bake (refreshes
        // height texture from updated positions for the G-buffer pass).
        encodeBake(into: commandBuffer)
        encodeUpdate(into: commandBuffer, dt: dt, audio: audio)
        encodeBake(into: commandBuffer)
    }

    /// Per-frame closure entry point (Phase 2b compatibility — no audio).
    /// Retained so older Phase 2b call sites still link; production wiring
    /// in `VisualizerEngine+Presets.swift` uses the audio-aware overload.
    public func encodePerFrameUpdate(into commandBuffer: MTLCommandBuffer, dt: Float) {
        encodeBake(into: commandBuffer)
        encodeUpdate(into: commandBuffer, dt: dt, audio: .silent)
        encodeBake(into: commandBuffer)
    }

    /// CPU-side bundle for audio uniforms; lets `encodeUpdate` stay
    /// non-`Sendable`-throwing while the closure-driven path packages
    /// audio inputs upstream.
    public struct UpdateAudio: Sendable {
        public let accumulatedAudioTime: Float
        public let arousal: Float
        public let bassEnergyDev: Float
        public let drumsEnergyDevSmoothed: Float
        public let otherEnergyDev: Float
        public static let silent = UpdateAudio(
            accumulatedAudioTime: 0,
            arousal: 0,
            bassEnergyDev: 0,
            drumsEnergyDevSmoothed: 0,
            otherEnergyDev: 0)
    }

    // MARK: - Test seam

    /// Snapshot the particle positions. Public for unit tests; not part of
    /// the GPU contract.
    public func snapshotParticlePositions() -> [SIMD2<Float>] {
        let ptr = particleBuffer.contents().bindMemory(
            to: Particle.self, capacity: Self.particleCount)
        return Array(UnsafeBufferPointer(start: ptr, count: Self.particleCount)).map { $0.position }
    }

    /// Snapshot full particle state (position + velocity). Public for tests.
    public func snapshotParticles() -> [Particle] {
        let ptr = particleBuffer.contents().bindMemory(
            to: Particle.self, capacity: Self.particleCount)
        return Array(UnsafeBufferPointer(start: ptr, count: Self.particleCount))
    }

    /// Test-only: stamp a constant velocity onto every particle. Used by
    /// Phase 2b verification (inject a known drift velocity, run N updates,
    /// confirm positions advanced by `velocity × N × dt`). Phase 2c
    /// replaces this with audio-force-driven velocity from the compute
    /// kernel; production code paths never call this directly.
    public func seedVelocityForTesting(_ velocity: SIMD2<Float>) {
        let ptr = particleBuffer.contents().bindMemory(
            to: Particle.self, capacity: Self.particleCount)
        for i in 0 ..< Self.particleCount {
            ptr[i].velocityX = velocity.x
            ptr[i].velocityZ = velocity.y
        }
    }

    // Note: `canonicalInitialPosition(forIndex:)`, the canonical grid
    // layout, and the CPU `voronoi_cell_offset` hash port live in
    // `FerrofluidParticles+InitialPositions.swift` (extracted to satisfy
    // SwiftLint's 400-line file cap after the Phase 2a spatial-hash
    // additions). The split is mechanical; semantics are unchanged.
}
