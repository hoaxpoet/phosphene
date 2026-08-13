// MeshGenerator — Mesh shader pipeline state management for Increment 3.2.
//
// Owns both the native Metal mesh shader pipeline (M3+, apple8 family) and
// the standard vertex shader fallback (M1/M2).  Detects hardware capability
// at init time and selects the appropriate pipeline transparently, so presets
// never need to branch on hardware tier.
//
// Usage (infrastructure shader):
//   let gen = try MeshGenerator(device: ctx.device, library: shaderLib.library,
//                               pixelFormat: ctx.pixelFormat)
//
// Usage (preset shader compiled by PresetLoader):
//   let gen = MeshGenerator(device: ctx.device, pipelineState: preset.pipelineState,
//                           configuration: .init(meshThreadCount: 64))
//
//   // Each frame inside a render pass:
//   gen.draw(encoder: encoder, features: currentFeatures, stems: currentStems)

import CoreFoundation
import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "MeshGenerator")

// MARK: - MeshGeneratorConfiguration

/// CPU-side configuration for the mesh generator.
///
/// `maxVerticesPerMeshlet` and `maxPrimitivesPerMeshlet` are the per-meshlet
/// upper bounds that preset authors should use when declaring their MSL
/// `mesh<>` template parameters.  MeshGenerator's built-in infrastructure
/// shader uses a smaller triangle (3V, 1P) for testing; these constants govern
/// production preset geometry.
///
/// `meshThreadCount` must match the `max_total_threads_per_threadgroup` attribute
/// on the preset's `[[mesh]]` function.  `objectThreadCount` must match the
/// `max_total_threads_per_threadgroup` attribute on the `[[object]]` function.
public struct MeshGeneratorConfiguration: Sendable {
    /// Maximum vertices per meshlet — must match the MSL `mesh<>` first template parameter.
    public let maxVerticesPerMeshlet: Int
    /// Maximum primitives per meshlet — must match the MSL `mesh<>` second template parameter.
    public let maxPrimitivesPerMeshlet: Int
    /// Threads per mesh threadgroup — must match `[[mesh, max_total_threads_per_threadgroup(N)]]`.
    /// Default 3 matches the infrastructure test triangle shader.
    public let meshThreadCount: Int
    /// Threads per object threadgroup — must match `[[object, max_total_threads_per_threadgroup(N)]]`.
    /// Default 1 is correct for all current preset object shaders.
    public let objectThreadCount: Int

    public init(
        maxVerticesPerMeshlet: Int = 256,
        maxPrimitivesPerMeshlet: Int = 512,
        meshThreadCount: Int = 3,
        objectThreadCount: Int = 1
    ) {
        self.maxVerticesPerMeshlet  = maxVerticesPerMeshlet
        self.maxPrimitivesPerMeshlet = maxPrimitivesPerMeshlet
        self.meshThreadCount        = meshThreadCount
        self.objectThreadCount      = objectThreadCount
    }
}

// MARK: - MeshGenerator

/// Manages the mesh shader pipeline and dispatches draw calls.
///
/// On M3+ (`device.supportsFamily(.apple8)`), a `MTLMeshRenderPipelineDescriptor`
/// is compiled using `mesh_object_shader` + `mesh_shader` + `mesh_fragment`.
/// On M1/M2, a standard `MTLRenderPipelineDescriptor` using
/// `mesh_fallback_vertex` + `mesh_fragment` is compiled instead — the
/// draw call falls back to `drawPrimitives` automatically.
///
/// Both paths produce a single `MTLRenderPipelineState` stored in
/// `pipelineState`.  The `draw(encoder:features:)` method selects the
/// appropriate GPU command based on `usesMeshShaderPath`.
public final class MeshGenerator: @unchecked Sendable {

    // MARK: - Public Properties

    /// Active configuration (maxVerticesPerMeshlet, maxPrimitivesPerMeshlet, thread counts).
    public let configuration: MeshGeneratorConfiguration

    /// `true` when the hardware supports native mesh shaders (apple8 family, M3+).
    /// `false` on M1/M2, where the vertex fallback pipeline is used.
    public let usesMeshShaderPath: Bool

    /// Compiled render pipeline state — either a mesh pipeline (M3+) or a
    /// standard vertex+fragment pipeline (M1/M2 fallback).
    public let pipelineState: MTLRenderPipelineState

    // MARK: - Frame Budget Governor Gate (D-057)

    /// Mesh density multiplier for the frame-budget governor.
    /// Default `1.0` = full geometry. `0.5` = reduced density.
    ///
    /// On M3+ (native mesh shader path), this value is passed to the object and
    /// mesh stages via `setObjectBytes`/`setMeshBytes` at buffer index 1 so
    /// preset shaders can opt-in to read it and adjust their geometry emission.
    /// On M1/M2 (vertex fallback: fullscreen triangle), this flag is a documented
    /// no-op — the triangle vertex count is fixed. Set by `RenderPipeline.applyQualityLevel`.
    /// See D-057(e) for rationale on why the M1/M2 path is accepted as a no-op.
    public var densityMultiplier: Float = 1.0

    // MARK: - Beat-Held FeatureVector (FTR.10)

    /// Sample-and-hold on the cached beat grid, bound at object/mesh buffer(4).
    ///
    /// A stateless object shader cannot make a value hold between beats and step on the
    /// beat, so the snapshot lives here — one per generator, advanced by `draw`. See
    /// ``BeatHold`` for the trust conditions; while they are unmet it tracks the live
    /// vector, so a preset that reads buffer(4) degrades to continuous rather than frozen.
    /// FTR.14 — GLIDING, not stepped. The beat still latches the target; the visible value
    /// chases it continuously on the RENDER clock and never holds still. Matt's M7 on FTR.13:
    /// *"the tree looks like it's dancing the robot — I don't like the stepped changes."*
    /// FTR.13's 1/3-beat ease was driven off `beatPhase01`, which updates at ~10 Hz on the
    /// local-file path (BUG-087) — 2.1 samples of ease then 4.3 samples of stillness per beat.
    /// τ = 1/4 beat: at 94–124 BPM that is 160–120 ms, so ~86 % of the travel happens inside
    /// one beat while the value never actually arrives, which is what removes the freeze.
    private var beatHold = BeatHold(glideBeats: 0.25)

    /// FTR.16 — SECTION-SCALE glide of the same vector, bound at object/mesh buffer(6).
    ///
    /// Matt's M7 on FTR.14: *"the growing and shrinking of the trunk and canopy feels random,
    /// completely divorced from what's going on in the music."* Measured cause: the size read
    /// LEVEL rank, and on a limited master level moves OPPOSITE to density
    /// (`r(trunk, spectral_density) = −0.641`), so the tree shrank as the arrangement grew. His
    /// call: size should follow how dense/full the sound is.
    ///
    /// Density needs a much longer τ than the beat glide provides — measured over three captures
    /// it turns 3.6 times a second at its own rate (the restlessness FTR.3f banned from
    /// continuous geometry) and ~0.8/s at τ ≈ 5 s, which is the band the level rank it replaces
    /// occupied. A SEPARATE slot rather than a new `FeatureVector` field on purpose: a layout
    /// change would ripple into every parallel worktree's `CommonLayoutTest`, and this needs no
    /// new data — only the same data on a slower clock.
    private var sectionHold = BeatHold(glideSeconds: 5.0)

    /// FTR.14 — render-clock state. The delta arithmetic that reads these lives in
    /// `MeshGenerator+RenderClock.swift`; see that file for why the clock is separate from
    /// `BeatHold`'s math.
    var lastDrawTime: CFAbsoluteTime = 0

    /// REPLAY OVERRIDE — set by offline harnesses to the capture's own frame delta. Without it
    /// the glide is unverifiable offline: wall-clock deltas in a test are the harness's render
    /// speed, not the captured session's, and a slow harness frame converges the glide in one
    /// frame then leaves it static — reproducing the FTR.13 staircase in the MEASUREMENT while
    /// production glides correctly. Production leaves this `nil`.
    public var renderDeltaOverride: Float?

    /// Advance the beat clock AND the glide, without drawing.
    ///
    /// For still-frame harnesses only: a single draw per drive condition captures the glide's
    /// first step from the previous condition rather than the geometry at this one. Call this
    /// repeatedly to settle, then draw. Distinct from ``advanceBeatHold(_:stems:)``, which
    /// advances only the BEAT clock and must not move the glide (a subsampled strip would
    /// otherwise glide at the wrong rate).
    public func advanceBeatHoldForSettling(_ features: FeatureVector, stems: StemFeatures = .zero) {
        let delta = nextRenderDelta()
        sectionHold.offerStems(stems)
        _ = sectionHold.update(features, renderDeltaTime: delta)
        beatHold.offerStems(stems)
        _ = beatHold.update(features, renderDeltaTime: delta)
    }

    public func advanceBeatHold(_ features: FeatureVector, stems: StemFeatures = .zero) {
        sectionHold.offerStems(stems)
        _ = sectionHold.update(features, renderDeltaTime: 0)
        beatHold.offerStems(stems)
        // renderDeltaTime 0: advance the BEAT clock only. These rows are not drawn, so the
        // glide must not advance for them or a subsampled strip would glide at the wrong rate.
        _ = beatHold.update(features, renderDeltaTime: 0)
    }

    /// `true` while the snapshot at buffer(4) is frozen between beats. Diagnostic only — a
    /// harness reporting "the trunk still slides" needs to be able to tell a preset that is
    /// not stepping from a hold that never engaged.
    public var beatHoldIsStepping: Bool { beatHold.isStepping }

    // MARK: - Private

    private let device: MTLDevice

    // MARK: - Init (infrastructure shader)

    /// Create a mesh generator, selecting the appropriate pipeline for the hardware.
    ///
    /// Compiles the infrastructure mesh shader from the provided `library`
    /// (`mesh_object_shader`, `mesh_shader`, `mesh_fragment`, `mesh_fallback_vertex`).
    /// Use the `init(device:pipelineState:configuration:)` overload for preset shaders
    /// already compiled by `PresetLoader`.
    ///
    /// - Parameters:
    ///   - device: Metal device for pipeline and buffer creation.
    ///   - library: Compiled Metal library containing the infrastructure mesh functions.
    ///   - pixelFormat: Output pixel format for pipeline state creation.
    ///   - configuration: Per-meshlet vertex/primitive limits. Defaults to 256V/512P/3T.
    public init(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat,
        configuration: MeshGeneratorConfiguration = .init()
    ) throws {
        self.device        = device
        self.configuration = configuration

        let supportsMesh = device.supportsFamily(.apple8)
        self.usesMeshShaderPath = supportsMesh

        if supportsMesh {
            self.pipelineState = try Self.compileMeshPipeline(
                device: device, library: library, pixelFormat: pixelFormat
            )
            logger.info("MeshGenerator: native mesh shader path (apple8+)")
        } else {
            self.pipelineState = try Self.compileFallbackPipeline(
                device: device, library: library, pixelFormat: pixelFormat
            )
            logger.info("MeshGenerator: vertex fallback path (pre-apple8)")
        }
    }

    // MARK: - Init (preset shader — pre-compiled by PresetLoader)

    /// Create a mesh generator wrapping a pre-compiled pipeline state.
    ///
    /// Use this initialiser for preset shaders that were already compiled by
    /// `PresetLoader.compileMeshShader`.  The pipeline state contains the correct
    /// shader functions for the current hardware tier (mesh on M3+, vertex fallback
    /// on M1/M2) — `MeshGenerator` simply wraps it and drives the draw dispatch.
    ///
    /// - Parameters:
    ///   - device: Metal device (used to detect hardware tier for dispatch selection).
    ///   - pipelineState: Pre-compiled pipeline state from `PresetLoader`.
    ///   - configuration: Per-meshlet limits and thread counts.  `meshThreadCount` must
    ///     match the preset's `[[mesh, max_total_threads_per_threadgroup(N)]]` attribute.
    public init(
        device: MTLDevice,
        pipelineState: MTLRenderPipelineState,
        configuration: MeshGeneratorConfiguration = .init()
    ) {
        self.device             = device
        self.configuration      = configuration
        self.usesMeshShaderPath = device.supportsFamily(.apple8)
        self.pipelineState      = pipelineState
        logger.info("MeshGenerator: wrapped preset pipeline (mesh path: \(device.supportsFamily(.apple8)))")
    }

    // MARK: - Draw

    /// Encode a mesh draw command into the given render encoder.
    ///
    /// Sets the pipeline state and dispatches geometry.  On M3+ this calls
    /// `drawMeshThreadgroups` (object → mesh → fragment) using thread counts from
    /// `configuration`; on M1/M2 this calls `drawPrimitives(.triangle)` with the
    /// fallback vertex shader.
    ///
    /// On M3+, `FeatureVector` is bound at buffer(0) for all three shader stages
    /// (object, mesh, fragment) so preset shaders can read audio data at any stage.
    /// On M1/M2, only the fragment stage binding is set (object/mesh stages are not
    /// active with the vertex fallback pipeline).
    ///
    /// The encoder must already have a valid render pass active.
    ///
    /// - Parameters:
    ///   - encoder: Active render command encoder.
    ///   - features: Current audio feature vector — bound at buffer(0) for all stages.
    /// - Parameter stems: per-stem features, bound at buffer(3) on every mesh-pipeline
    ///   stage (FTR.4). **Until this existed, mesh presets were blind to stems in the one
    ///   stage that decides geometry.** `RenderPipeline.drawWithMeshShader` has always bound
    ///   them at FRAGMENT buffer(3), so a mesh preset could colour by stem but not SHAPE by
    ///   stem — the object shader, which computes branch counts and thread dispatch, had no
    ///   access. That blocked Fractal Tree from routing its tips to the guitar (D-212 /
    ///   FTR.4), and it blocks every future mesh preset the same way. Shared renderer code:
    ///   binding here means every mesh preset inherits it.
    ///
    /// FTR.10 also binds a beat-held copy of `features` at object/mesh buffer(4) — see
    /// ``BeatHold``. Shared renderer code again: any mesh preset can make a layer step on
    /// the beat by reading buffer(4) instead of buffer(0).
    public func draw(encoder: MTLRenderCommandEncoder,
                     features: FeatureVector,
                     stems: StemFeatures = .zero) {
        encoder.setRenderPipelineState(pipelineState)
        var feat = features
        var stemFeat = stems
        // FTR.10 — advance the beat hold on EVERY frame, drawn or not, so the snapshot at
        // buffer(4) reflects the real beat boundaries and not the draw cadence.
        // FTR.13 — offer the stems BEFORE update: `update` is the one place the beat boundary
        // is detected, and it latches both sides there.
        beatHold.offerStems(stems)
        let renderDelta = nextRenderDelta()
        var heldFeat = beatHold.update(features, renderDeltaTime: renderDelta)
        var heldStemFeat = beatHold.glidingStemFeatures
        // FTR.16 — one delta, both holds: two clocks would drift apart within a track.
        sectionHold.offerStems(stems)
        var sectionFeat = sectionHold.update(features, renderDeltaTime: renderDelta)

        if usesMeshShaderPath {
            // Bind features to all mesh-pipeline stages so preset shaders can read
            // audio data from the object, mesh, or fragment stage as needed.
            encoder.setObjectBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)
            encoder.setMeshBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)
            // Pass density multiplier at buffer(1) so preset mesh shaders can
            // opt-in to reduce geometry emission. D-057.
            var density = densityMultiplier
            encoder.setObjectBytes(&density, length: MemoryLayout<Float>.stride, index: 1)
            encoder.setMeshBytes(&density, length: MemoryLayout<Float>.stride, index: 1)
            // FTR.4 — StemFeatures at buffer(3), matching the slot the fragment stage and
            // every non-mesh path already use. Same slot everywhere is the contract.
            encoder.setObjectBytes(&stemFeat, length: MemoryLayout<StemFeatures>.stride, index: 3)
            encoder.setMeshBytes(&stemFeat, length: MemoryLayout<StemFeatures>.stride, index: 3)
            // FTR.10 — the beat-driven FeatureVector at buffer(4). Same struct as buffer(0).
            // FTR.14: it is no longer FROZEN between beats — the beat latches the target and
            // this value glides toward it on the render clock, so a preset reading slot 4 gets
            // motion that is beat-directed but never still. Read slot 0 for the raw live value.
            // Slot 4 is SceneUniforms on the ray-march FRAGMENT path only — the mesh pipeline
            // never binds that.
            encoder.setObjectBytes(&heldFeat, length: MemoryLayout<FeatureVector>.stride, index: 4)
            encoder.setMeshBytes(&heldFeat, length: MemoryLayout<FeatureVector>.stride, index: 4)
            // FTR.13 — the beat-held StemFeatures at buffer(5), symmetric with 0/4: slot 3 is
            // live, slot 5 is held on the same beats and eased on the same curve. A per-stem
            // route that must not change between beats reads 5. Slot 5 is SpectralHistory on
            // the DIRECT-PASS FRAGMENT encoder only — the mesh pipeline never binds that, the
            // same reasoning that made slot 4 safe at FTR.10.
            let heldStemLength = MemoryLayout<StemFeatures>.stride
            encoder.setObjectBytes(&heldStemFeat, length: heldStemLength, index: 5)
            encoder.setMeshBytes(&heldStemFeat, length: heldStemLength, index: 5)
            // FTR.16 — the section-scale vector at buffer(6). Same struct as buffer(0)/(4) on a
            // ~5 s glide, for layers that answer to song structure rather than to beats.
            let sectionLength = MemoryLayout<FeatureVector>.stride
            encoder.setObjectBytes(&sectionFeat, length: sectionLength, index: 6)
            encoder.setMeshBytes(&sectionFeat, length: sectionLength, index: 6)
        }
        encoder.setFragmentBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)

        if usesMeshShaderPath {
            // Native mesh dispatch using per-preset thread counts from configuration.
            encoder.drawMeshThreadgroups(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerObjectThreadgroup: MTLSize(
                    width: configuration.objectThreadCount, height: 1, depth: 1
                ),
                threadsPerMeshThreadgroup: MTLSize(
                    width: configuration.meshThreadCount, height: 1, depth: 1
                )
            )
        } else {
            // Vertex fallback: fullscreen triangle, 3 vertices.
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }

    // MARK: - Private Pipeline Compilation

    /// Compile the native mesh render pipeline (M3+).
    private static func compileMeshPipeline(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        guard let meshFn = library.makeFunction(name: "mesh_shader") else {
            throw MeshGeneratorError.functionNotFound("mesh_shader")
        }
        guard let fragmentFn = library.makeFunction(name: "mesh_fragment") else {
            throw MeshGeneratorError.functionNotFound("mesh_fragment")
        }
        // Object shader is optional; nil skips the object stage.
        let objectFn = library.makeFunction(name: "mesh_object_shader")

        let descriptor = MTLMeshRenderPipelineDescriptor()
        descriptor.objectFunction   = objectFn
        descriptor.meshFunction     = meshFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        let (state, _) = try device.makeRenderPipelineState(descriptor: descriptor, options: [])
        return state
    }

    /// Compile the vertex-shader fallback pipeline (M1/M2).
    private static func compileFallbackPipeline(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        guard let vertexFn = library.makeFunction(name: "mesh_fallback_vertex") else {
            throw MeshGeneratorError.functionNotFound("mesh_fallback_vertex")
        }
        guard let fragmentFn = library.makeFunction(name: "mesh_fragment") else {
            throw MeshGeneratorError.functionNotFound("mesh_fragment")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction   = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

// MARK: - Errors

/// Errors thrown by `MeshGenerator.init`.
public enum MeshGeneratorError: Error, Sendable {
    /// A required Metal function was not found in the shader library.
    case functionNotFound(String)
    /// Pipeline state creation failed (Metal validation error details in associated value).
    case pipelineCreationFailed(String)
}
