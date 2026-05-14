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

    // MARK: - GPU resources

    /// UMA buffer of 2048 `SIMD2<Float>` particle positions in world XZ.
    /// Phase 1: written once at init, read once at bake. Phase 2: written
    /// per frame by the SPH-lite update pass.
    public let particleBuffer: MTLBuffer

    /// UMA r16Float 512×512 texture carrying the baked height field.
    /// Sampled at fragment texture slot 10 of the ray-march G-buffer pass.
    /// Linear filter + clamp-to-zero (`access::sample` in the .metal side).
    public let heightTexture: MTLTexture

    // MARK: - Internal

    private let bakePipeline: MTLComputePipelineState
    private let device: MTLDevice

    /// Bake parameters mirrored on the GPU side via a 16-byte struct.
    private struct BakeUniforms {
        var worldOriginXZ: SIMD2<Float>     // (worldOriginX, worldOriginZ)
        var worldSpan: Float                // worldSpan
        var smoothMinW: Float               // smoothMinW
        var spikeBaseRadius: Float          // spikeBaseRadius
        var apexSmoothK: Float              // apexSmoothK
        var particleCount: UInt32           // particleCount
        var pad0: UInt32                    // 16-byte align
    }

    // MARK: - Init

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

        // Particle buffer: 2048 × 8 bytes = 16 KiB. UMA shared storage so
        // the kernel reads from CPU-written memory without a blit.
        let particleStride = MemoryLayout<SIMD2<Float>>.stride
        let bufferLength = Self.particleCount * particleStride
        guard let buf = device.makeBuffer(length: bufferLength,
                                          options: .storageModeShared) else {
            particleLogger.error("FerrofluidParticles: particle buffer allocation failed")
            return nil
        }
        self.particleBuffer = buf

        // Height texture: r16Float, 512×512, UMA shared, read-write so the
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

        // Compute pipeline from the engine library's `ferrofluid_height_bake`
        // kernel. The kernel lives in `Renderer/Shaders/FerrofluidParticles.metal`.
        guard let fn = library.makeFunction(name: "ferrofluid_height_bake") else {
            particleLogger.error("FerrofluidParticles: ferrofluid_height_bake function not found")
            return nil
        }
        do {
            self.bakePipeline = try device.makeComputePipelineState(function: fn)
        } catch {
            particleLogger.error("FerrofluidParticles: bake pipeline creation failed: \(error)")
            return nil
        }

        // Populate initial particle positions at voronoi-equivalent XZ.
        writeInitialParticlePositions()
    }

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

    /// Encode the bake compute dispatch into the caller's command buffer
    /// without committing. Used by the test harness to bundle the bake with
    /// the subsequent render dispatch in a single command buffer.
    public func encodeBake(into commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            particleLogger.error("FerrofluidParticles.encodeBake: makeComputeCommandEncoder returned nil")
            return
        }
        encoder.setComputePipelineState(bakePipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        var uniforms = BakeUniforms(
            worldOriginXZ: SIMD2(Self.worldOriginX, Self.worldOriginZ),
            worldSpan: Self.worldSpan,
            smoothMinW: Self.smoothMinW,
            spikeBaseRadius: Self.spikeBaseRadius,
            apexSmoothK: Self.apexSmoothK,
            particleCount: UInt32(Self.particleCount),
            pad0: 0)
        encoder.setBytes(&uniforms,
                         length: MemoryLayout<BakeUniforms>.stride,
                         index: 1)
        encoder.setTexture(heightTexture, index: 0)

        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(
            width: (Self.heightTextureSize + 15) / 16,
            height: (Self.heightTextureSize + 15) / 16,
            depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }

    // MARK: - Test seam

    /// Snapshot the particle positions. Public for unit tests; not part of
    /// the GPU contract.
    public func snapshotParticlePositions() -> [SIMD2<Float>] {
        let ptr = particleBuffer.contents().bindMemory(
            to: SIMD2<Float>.self, capacity: Self.particleCount)
        return Array(UnsafeBufferPointer(start: ptr, count: Self.particleCount))
    }

    /// Compute the canonical Phase 1 initial position for a particle index.
    /// Public so tests can verify the bake input without re-reading GPU memory.
    public static func canonicalInitialPosition(forIndex i: Int) -> SIMD2<Float> {
        let layout = canonicalGridLayout()
        let row = i / layout.columns
        let col = i % layout.columns
        let cellCoord = SIMD2<Int32>(Int32(col), Int32(row))
        let offset = voronoiCellOffset(cell: cellCoord)
        // Map (col + offset.x, row + offset.y) from scaled-space [0..cols] /
        // [0..rows] to world XZ [worldOriginX, +span] / [worldOriginZ, +span].
        let scaledX = Float(col) + offset.x
        let scaledZ = Float(row) + offset.y
        let normalisedX = scaledX / Float(layout.columns)
        let normalisedZ = scaledZ / Float(layout.rows)
        let worldX = worldOriginX + normalisedX * worldSpan
        let worldZ = worldOriginZ + normalisedZ * worldSpan
        return SIMD2(worldX, worldZ)
    }

    // MARK: - Private: initial positions

    private struct GridLayout {
        let columns: Int
        let rows: Int
        var capacity: Int { columns * rows }
    }

    /// Canonical Phase 1 grid: **80 × 75 = 6000 cells** (no trim). X spacing
    /// `worldSpan / 80 = 0.25 world units` matches Phase A's
    /// `voronoi_smooth(scale = 4)` cell side exactly; Z spacing
    /// `worldSpan / 75 = 0.267 world units` adds a ~7 % anisotropy that's
    /// not visible at the camera tilt (the eye doesn't compare X vs Z cell
    /// spacing across a tilted ground plane). Particles overlap their tent
    /// base at this spacing (peak base radius 0.15 → diameter 0.30 > 0.25
    /// spacing) for wall-to-wall coverage — Matt's "peaks touch
    /// base-to-base" spec, finally satisfied at the empirical density.
    private static func canonicalGridLayout() -> GridLayout {
        GridLayout(columns: 80, rows: 75)
    }

    /// Populate the particle buffer with the canonical Phase 1 positions.
    /// Mirrors `canonicalInitialPosition(forIndex:)` for the actual write.
    private func writeInitialParticlePositions() {
        let ptr = particleBuffer.contents().bindMemory(
            to: SIMD2<Float>.self, capacity: Self.particleCount)
        for i in 0 ..< Self.particleCount {
            ptr[i] = Self.canonicalInitialPosition(forIndex: i)
        }
    }

    // MARK: - Private: Voronoi cell offset (mirror of MSL `voronoi_cell_offset`)

    /// Ported from `Presets/Shaders/Utilities/Texture/Voronoi.metal`'s
    /// `voronoi_hash_int` + `voronoi_cell_offset`. Required so the Phase 1
    /// initial particle XZ positions match the cell-center coordinates a
    /// `voronoi_smooth` pass would emit (Matt's Q1 confirmation
    /// 2026-05-14): "hex grid + per-cell `voronoi_cell_offset` hash". The
    /// 32-bit `Int32` math matches MSL's `int` width semantics.
    private static func voronoiCellOffset(cell: SIMD2<Int32>) -> SIMD2<Float> {
        let cx = cell.x &* 1453 &+ cell.y &* 2971
        let cy = cell.x &* 3539 &+ cell.y &* 1117
        let qx = (cx ^ (cx >> 9)) &* 0x45D9_F3B
        let qy = (cy ^ (cy >> 9)) &* 0x45D9_F3B
        let masked = SIMD2<Int32>(qx & 0xFFFF, qy & 0xFFFF)
        return SIMD2(Float(masked.x), Float(masked.y)) / 65535.0
    }
}
