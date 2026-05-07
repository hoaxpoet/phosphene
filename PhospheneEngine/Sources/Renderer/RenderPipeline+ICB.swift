// RenderPipeline+ICB — GPU-driven indirect command buffer render path (Increment 3.5).
//
// `drawWithICB` is a render path parallel to `drawDirect`, `drawWithFeedback`,
// `drawWithPostProcess`, and `drawWithMeshShader`.  A Metal compute kernel
// (`icb_populate_kernel`) reads the current FeatureVector and encodes 1–N draw
// commands into an indirect command buffer.  The CPU then calls
// `executeCommandsInBuffer` once — all draw decisions were made on the GPU.
//
// Priority in renderFrame(): mesh → postProcess → ICB → feedback → direct.

import Metal
@preconcurrency import MetalKit
import Shared
import os.log

private let icbLogger = Logger(subsystem: "com.phosphene.renderer", category: "ICB")

// MARK: - ICBConfiguration

/// Configuration for the GPU-driven indirect command buffer render path.
public struct ICBConfiguration: Sendable {

    /// Maximum number of draw command slots the GPU may populate per frame.
    ///
    /// Slot 0 is always active (base layer).  Higher slots activate as cumulative
    /// bass + mid + treble energy rises above their linearly spaced thresholds.
    public var maxCommandCount: Int

    /// Creates an ICB configuration.
    ///
    /// - Parameter maxCommandCount: Maximum GPU-encoded draw calls per frame.
    ///   Defaults to 16.  Must be ≥ 1.
    public init(maxCommandCount: Int = 16) {
        precondition(maxCommandCount >= 1, "maxCommandCount must be at least 1")
        self.maxCommandCount = maxCommandCount
    }
}

// MARK: - IndirectCommandBufferState

/// Owns all Metal objects required for one frame of GPU-driven ICB rendering.
///
/// `IndirectCommandBufferState` is created once per preset switch (or once for the
/// lifetime of the app) and reused every frame.  The ICB itself is reset each frame
/// via a blit encoder pass before the compute kernel populates it.
public final class IndirectCommandBufferState: @unchecked Sendable {

    // MARK: - Properties

    /// The indirect command buffer populated by `icb_populate_kernel` each frame.
    public let icb: MTLIndirectCommandBuffer

    /// Compute pipeline state for the ICB population kernel.
    public let computePipeline: MTLComputePipelineState

    /// Argument buffer wrapping the ICB handle for the compute encoder (buffer slot 0).
    /// Populated once at init time via `MTLArgumentEncoder.setIndirectCommandBuffer`.
    public let icbArgumentBuffer: MTLBuffer

    /// Shared UMA buffer for the GPU-written active command count (UInt32 atomic).
    /// Zeroed by the blit pass each frame; read back by tests after GPU completion.
    public let commandCountBuffer: MTLBuffer

    /// UMA buffer holding the current frame's `FeatureVector` (128 bytes).
    ///
    /// `MTLRenderCommandEncoder.setFragmentBytes` is NOT inherited by ICB commands
    /// when `inheritBuffers = true` — only `setFragmentBuffer` bindings are.
    /// The CPU writes into this buffer each frame before calling `executeCommandsInBuffer`.
    public let featureVectorBuffer: MTLBuffer

    /// UMA buffer holding the current frame's `StemFeatures` (64 bytes).
    /// Same rationale as `featureVectorBuffer` above.
    public let stemFeaturesBuffer: MTLBuffer

    /// The configuration this state was created with.
    public let configuration: ICBConfiguration

    // MARK: - Init

    /// Create ICB state from a compiled shader library.
    ///
    /// - Parameters:
    ///   - device: Metal device.
    ///   - library: Compiled shader library containing `icb_populate_kernel`.
    ///   - configuration: ICB configuration (max command count).
    /// - Throws: `ICBError` if any Metal object allocation fails.
    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: ICBConfiguration = .init()
    ) throws {
        self.configuration = configuration

        // 1. Compile the populate kernel.
        guard let populateFunction = library.makeFunction(name: "icb_populate_kernel") else {
            throw ICBError.missingFunction("icb_populate_kernel")
        }
        self.computePipeline = try device.makeComputePipelineState(function: populateFunction)

        // 2. Create the indirect command buffer.
        //    inheritPipelineState + inheritBuffers = true so commands only call
        //    draw_primitives — all pipeline and buffer state comes from the encoder.
        let icbDescriptor = MTLIndirectCommandBufferDescriptor()
        icbDescriptor.commandTypes = [.draw]
        icbDescriptor.inheritPipelineState = true
        icbDescriptor.inheritBuffers = true
        icbDescriptor.maxVertexBufferBindCount = 0    // all inherited from encoder
        icbDescriptor.maxFragmentBufferBindCount = 0  // all inherited from encoder

        guard let icbObj = device.makeIndirectCommandBuffer(
            descriptor: icbDescriptor,
            maxCommandCount: configuration.maxCommandCount,
            options: []
        ) else {
            throw ICBError.makeICBFailed
        }
        self.icb = icbObj

        // 3. Build the argument buffer that wraps the ICB reference for the kernel.
        //    The MSL kernel declares `device ICBContainer &icbContainer [[buffer(0)]]`
        //    where ICBContainer is a struct with `command_buffer cmdBuf [[id(0)]]`.
        //    makeArgumentEncoder(bufferIndex: 0) reflects the struct layout so the
        //    CPU can write the ICB handle into the correct byte offset.
        let argEncoder = populateFunction.makeArgumentEncoder(bufferIndex: 0)
        let argLength = max(argEncoder.encodedLength, 8)  // guard against zero-length
        guard let argBuf = device.makeBuffer(
            length: argLength,
            options: .storageModeShared
        ) else {
            throw ICBError.makeBufferFailed
        }
        argEncoder.setArgumentBuffer(argBuf, offset: 0)
        argEncoder.setIndirectCommandBuffer(icbObj, index: 0)  // ICBContainer.cmdBuf [[id(0)]]
        self.icbArgumentBuffer = argBuf

        // 4. Command count buffer: a single UInt32 the GPU writes atomically.
        guard let countBuf = device.makeBuffer(
            length: MemoryLayout<UInt32>.size,
            options: .storageModeShared
        ) else {
            throw ICBError.makeBufferFailed
        }
        self.commandCountBuffer = countBuf

        // 5. FeatureVector buffer (UMA): ICB inheritBuffers only inherits setFragmentBuffer
        //    bindings, not inline setFragmentBytes data. A persistent UMA buffer lets the
        //    CPU write the current frame's features and the GPU read them via inheritance.
        guard let fvBuf = device.makeBuffer(
            length: MemoryLayout<FeatureVector>.stride,
            options: .storageModeShared
        ) else {
            throw ICBError.makeBufferFailed
        }
        self.featureVectorBuffer = fvBuf

        // 6. StemFeatures buffer (UMA): same rationale as featureVectorBuffer.
        guard let sfBuf = device.makeBuffer(
            length: MemoryLayout<StemFeatures>.stride,
            options: .storageModeShared
        ) else {
            throw ICBError.makeBufferFailed
        }
        self.stemFeaturesBuffer = sfBuf

        icbLogger.info(
            "IndirectCommandBufferState created (maxCommandCount: \(configuration.maxCommandCount))"
        )
    }

    // MARK: - GPU-Written Count

    /// Number of draw commands the GPU encoded in the most recent `drawWithICB` call.
    ///
    /// Valid to read only after the command buffer containing the compute pass has
    /// completed (i.e., after `commandBuffer.waitUntilCompleted()`).
    public var lastCommandCount: Int {
        commandCountBuffer.contents()
            .assumingMemoryBound(to: UInt32.self)
            .pointee
            .asInt
    }
}

// MARK: - ICBError

/// Errors thrown when `IndirectCommandBufferState` cannot be initialised.
public enum ICBError: Error, Sendable {
    /// `device.makeIndirectCommandBuffer` returned nil.
    case makeICBFailed
    /// `device.makeBuffer` returned nil.
    case makeBufferFailed
    /// A required Metal shader function is missing from the library.
    case missingFunction(String)
}

// MARK: - RenderPipeline ICB Draw Path

extension RenderPipeline {

    // MARK: - Preset Switching (ICB)

    /// Attach ICB state to the render loop.
    ///
    /// Pass a non-nil state to enable GPU-driven draw dispatch when the active passes
    /// include `.icb`.  Pass `nil` to detach.
    /// Thread-safe — can be called from any queue.
    public func setICBState(_ state: IndirectCommandBufferState?) {
        icbLock.withLock {
            icbState = state
        }
        icbLogger.info("ICB state \(state != nil ? "attached" : "detached")")
    }

    // MARK: - ICB Render Path

    // swiftlint:disable function_parameter_count
    // `drawWithICB` takes 6 parameters — the minimal render-pass context,
    // matching the convention used by `drawDirect` and `drawSurfaceMode`.

    /// GPU-driven indirect command buffer render pass.
    ///
    /// Three-phase loop per frame:
    ///   1. **Blit pass** — Reset all ICB command slots; zero the command count buffer.
    ///   2. **Compute pass** — `icb_populate_kernel` writes draw commands for the
    ///      active slots and increments the atomic counter.
    ///   3. **Render pass** — The active pipeline + audio buffers are set on the
    ///      encoder (inherited by all ICB commands), then
    ///      `executeCommandsInBuffer` dispatches the GPU-encoded draws.
    ///
    /// - Parameters:
    ///   - commandBuffer:  Active command buffer to encode all three passes into.
    ///   - view:           MTKView providing the current drawable.
    ///   - features:       Audio feature vector (time/delta pre-filled by `draw(in:)`).
    ///   - stemFeatures:   Per-stem features from the background separation pipeline.
    ///   - activePipeline: The compiled scene preset pipeline state.
    ///   - icbState:       ICB state (indirect command buffer + compute pipeline).
    @MainActor
    func drawWithICB(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        icbState: IndirectCommandBufferState
    ) {
        let maxCount = icbState.configuration.maxCommandCount

        // Phase 1: Blit — reset ICB slots and zero the command count.
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.resetCommandsInBuffer(icbState.icb, range: 0..<maxCount)
            blit.fill(
                buffer: icbState.commandCountBuffer,
                range: 0..<MemoryLayout<UInt32>.size,
                value: 0
            )
            blit.endEncoding()
        }

        // Phase 2: Compute — GPU populates ICB based on live audio state.
        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setComputePipelineState(icbState.computePipeline)
            // buffer(0): argument buffer containing the ICB reference.
            compute.setBuffer(icbState.icbArgumentBuffer, offset: 0, index: 0)
            // buffer(1): current FeatureVector (bass/mid/treble drive slot activation).
            compute.setBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 1)
            // buffer(2): atomic command count written by the kernel.
            compute.setBuffer(icbState.commandCountBuffer, offset: 0, index: 2)
            // Declare ICB write access for Metal's dependency tracker.
            compute.useResource(icbState.icb, usage: .write)

            // One thread per command slot — fits comfortably in a single threadgroup.
            let tpg = min(
                maxCount,
                icbState.computePipeline.maxTotalThreadsPerThreadgroup
            )
            compute.dispatchThreads(
                MTLSize(width: maxCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tpg, height: 1, depth: 1)
            )
            compute.endEncoding()
        }

        // Phase 3: Render — execute ICB with inherited pipeline and buffers.
        //
        // `inheritBuffers = true` only propagates `setFragmentBuffer` bindings to ICB
        // commands — inline `setFragmentBytes` data is NOT inherited.  Write FeatureVector
        // and StemFeatures into the pre-allocated UMA buffers before binding them.
        memcpy(
            icbState.featureVectorBuffer.contents(),
            &features,
            MemoryLayout<FeatureVector>.stride)
        var stems = stemFeatures
        memcpy(
            icbState.stemFeaturesBuffer.contents(),
            &stems,
            MemoryLayout<StemFeatures>.stride)

        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }

        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction  = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Set pipeline + audio buffer bindings — all inherited by every ICB command.
        // activePipeline must have been compiled with supportIndirectCommandBuffers = true.
        encoder.setRenderPipelineState(activePipeline)
        encoder.setFragmentBuffer(icbState.featureVectorBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        encoder.setFragmentBuffer(icbState.stemFeaturesBuffer, offset: 0, index: 3)

        // Bind noise textures at slots 4–8.  These are encoder-level bindings,
        // accessible to ICB shaders that declare [[texture(4..8)]] parameters.
        bindNoiseTextures(to: encoder)

        // Declare ICB read access for Metal's dependency tracker.
        // Use the stages-aware overload (macOS 13+, our target is 14+).
        encoder.useResource(icbState.icb, usage: .read, stages: [.vertex, .fragment])

        // Execute all slots; reset slots are silently skipped by the GPU.
        encoder.executeCommandsInBuffer(icbState.icb, range: 0..<maxCount)

        encoder.endEncoding()
        compositeDashboard(commandBuffer: commandBuffer, view: view)
        commandBuffer.present(drawable)
    }
    // swiftlint:enable function_parameter_count
}

// MARK: - UInt32 Convenience

private extension UInt32 {
    var asInt: Int { Int(self) }
}
