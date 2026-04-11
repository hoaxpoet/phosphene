// RenderPipelineICBTests — Tests for the Increment 3.5 GPU-driven ICB render path.
//
// Six tests cover ICB creation, GPU-side population, execution, per-frame reset,
// zero-audio minimum draw behaviour, and a CPU-frame-time performance gate.
//
// All tests use XCTestCase (consistent with PostProcessChainTests) because the
// performance test requires XCTest.measure {}.

import XCTest
import Metal
@testable import Renderer
@testable import Shared

// MARK: - RenderPipelineICBTests

final class RenderPipelineICBTests: XCTestCase {

    private var context: MetalContext!
    private var library: ShaderLibrary!

    override func setUpWithError() throws {
        context = try MetalContext()
        library = try ShaderLibrary(context: context)
    }

    // MARK: - 1. ICB created with correct max command count

    /// `IndirectCommandBufferState` must create an ICB whose slot capacity matches
    /// the `maxCommandCount` in the supplied `ICBConfiguration`.
    func test_createICB_maxCommandCount_matchesConfig() throws {
        let config = ICBConfiguration(maxCommandCount: 8)
        let state  = try IndirectCommandBufferState(
            device: context.device,
            library: library.library,
            configuration: config
        )

        XCTAssertEqual(state.configuration.maxCommandCount, 8,
            "ICBConfiguration.maxCommandCount must be preserved in IndirectCommandBufferState")

        // The ICB is always non-nil when init succeeds (throws on failure).
        XCTAssertNotNil(state.icb,
            "IndirectCommandBuffer must be non-nil after successful init")

        // The command count buffer must be exactly 4 bytes (one UInt32).
        XCTAssertEqual(state.commandCountBuffer.length, MemoryLayout<UInt32>.size,
            "commandCountBuffer must be 4 bytes (one UInt32)")
    }

    // MARK: - 2. Compute kernel populates ICB with non-zero commands

    /// After running `icb_populate_kernel` with non-zero audio energy, the GPU-written
    /// command count must be ≥ 1 (slot 0 is unconditionally active).
    func test_computeShader_populatesICB_nonZeroCommands() throws {
        let config = ICBConfiguration(maxCommandCount: 4)
        let state  = try IndirectCommandBufferState(
            device: context.device,
            library: library.library,
            configuration: config
        )

        // Build features with strong energy across all bands.
        var features       = FeatureVector.zero
        features.bass      = 0.8
        features.mid       = 0.6
        features.treble    = 0.4

        try runComputePass(state: state, features: &features)

        // After GPU completes, at least one command must have been encoded
        // (slot 0 is unconditionally active regardless of energy).
        XCTAssertGreaterThan(state.lastCommandCount, 0,
            "icb_populate_kernel must encode at least 1 command with non-zero audio energy")
    }

    // MARK: - 3. ICB executes without error

    /// A full drawWithICB pipeline — blit reset, compute populate, render execute —
    /// must complete with `.completed` status and no error.
    func test_executeICB_completesWithoutError() throws {
        let config = ICBConfiguration(maxCommandCount: 4)
        let state  = try IndirectCommandBufferState(
            device: context.device,
            library: library.library,
            configuration: config
        )

        // ICB-inherited pipeline state MUST have supportIndirectCommandBuffers = true.
        // Without this flag the GPU raises a page fault when executing ICB commands.
        let pipelineState = try library.renderPipelineState(
            named: "waveform_icb_test",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "waveform_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device,
            supportICB: true
        )

        // Create offscreen render target so we don't need a CAMetalLayer drawable.
        let size    = 16
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: size, height: size, mipmapped: false
        )
        texDesc.usage       = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let renderTarget = context.device.makeTexture(descriptor: texDesc) else {
            throw ICBTestError.metalSetupFailed
        }

        var features    = FeatureVector.zero
        features.bass   = 0.5
        features.mid    = 0.3
        features.treble = 0.2

        // Encode a standalone ICB sequence (blit + compute + render).
        try runICBSequence(
            state: state,
            features: &features,
            pipelineState: pipelineState,
            renderTarget: renderTarget
        )

        // No assertion beyond "no throw" — completion without error IS the test.
    }

    // MARK: - 4. ICB resets between frames

    /// The blit pass must zero the command count buffer before the compute pass runs.
    /// If reset is working, running two back-to-back frames with different energy
    /// levels produces the correct (not stale) count each time.
    func test_icb_resetBetweenFrames() throws {
        let config = ICBConfiguration(maxCommandCount: 8)
        let state  = try IndirectCommandBufferState(
            device: context.device,
            library: library.library,
            configuration: config
        )

        // Frame A: high energy — expects multiple active slots.
        var featuresHigh       = FeatureVector.zero
        featuresHigh.bass      = 1.0
        featuresHigh.mid       = 1.0
        featuresHigh.treble    = 1.0

        try runComputePass(state: state, features: &featuresHigh)
        let countAfterHighEnergy = state.lastCommandCount

        // Frame B: silence — expects exactly 1 active slot (slot 0 only).
        var featuresSilence = FeatureVector.zero
        try runComputePass(state: state, features: &featuresSilence)
        let countAfterSilence = state.lastCommandCount

        // After the reset pass, the count must reflect only the most recent frame,
        // not an accumulation of counts from both frames.
        XCTAssertGreaterThan(countAfterHighEnergy, 0,
            "High-energy frame should produce at least one active command")
        XCTAssertEqual(countAfterSilence, 1,
            "Silence frame must produce exactly 1 command (slot 0 is unconditionally active)")
        XCTAssertLessThanOrEqual(countAfterSilence, countAfterHighEnergy,
            "Silence count must not exceed high-energy count — reset must clear stale values")
    }

    // MARK: - 5. Zero audio produces minimum draw calls

    /// With an all-zero `FeatureVector`, only slot 0 should be active.
    /// All other slots have energy 0, which never exceeds their threshold (> 0).
    func test_icb_withZeroAudio_minimumDrawCalls() throws {
        let config = ICBConfiguration(maxCommandCount: 16)
        let state  = try IndirectCommandBufferState(
            device: context.device,
            library: library.library,
            configuration: config
        )

        var features = FeatureVector.zero
        try runComputePass(state: state, features: &features)

        XCTAssertEqual(state.lastCommandCount, 1,
            "Zero audio must produce exactly 1 active command (the unconditional base layer)")
    }

    // MARK: - 6. Performance gate: CPU frame time acceptable for GPU-driven rendering

    /// Encoding one full ICB frame (blit + compute + render) must complete in under
    /// 2 ms (CPU + GPU) on Apple Silicon — comparable to the PostProcess chain gate.
    ///
    /// Uses `XCTest.measure {}` to sample 10 iterations and report average.
    func test_gpuDrivenRendering_cpuFrameTimeReduced() throws {
        let config = ICBConfiguration(maxCommandCount: 16)
        let state  = try IndirectCommandBufferState(
            device: context.device,
            library: library.library,
            configuration: config
        )

        let pipelineState = try library.renderPipelineState(
            named: "waveform_icb_perf",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "waveform_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device,
            supportICB: true
        )

        let size    = 256
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: size, height: size, mipmapped: false
        )
        texDesc.usage       = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let renderTarget = context.device.makeTexture(descriptor: texDesc) else {
            throw ICBTestError.metalSetupFailed
        }

        var features   = FeatureVector.zero
        features.bass  = 0.8
        features.mid   = 0.6

        // Warm-up: exclude JIT compilation latency from the measurement.
        try runICBSequence(
            state: state,
            features: &features,
            pipelineState: pipelineState,
            renderTarget: renderTarget
        )

        // XCTest measure block — 10 iterations, reports average.
        measure {
            try? self.runICBSequence(
                state: state,
                features: &features,
                pipelineState: pipelineState,
                renderTarget: renderTarget
            )
        }

        // Hard gate: a single warm call must be < 2 ms.
        let start = Date()
        try runICBSequence(
            state: state,
            features: &features,
            pipelineState: pipelineState,
            renderTarget: renderTarget
        )
        let elapsed = Date().timeIntervalSince(start) * 1000.0

        XCTAssertLessThan(elapsed, 2.0,
            "ICB frame (blit + compute + render) took \(String(format: "%.2f", elapsed)) ms; must be < 2 ms")
    }
}

// MARK: - Helpers

private extension RenderPipelineICBTests {

    // MARK: - Compute-Only Pass (for count verification)

    /// Encode blit-reset + compute-populate for `state` and wait for GPU completion.
    /// Does NOT encode a render pass — used by tests that only need to inspect
    /// `state.lastCommandCount`.
    func runComputePass(
        state: IndirectCommandBufferState,
        features: inout FeatureVector
    ) throws {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw ICBTestError.commandBufferFailed
        }

        let maxCount = state.configuration.maxCommandCount

        // Blit: reset ICB + zero count.
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.resetCommandsInBuffer(state.icb, range: 0..<maxCount)
            blit.fill(
                buffer: state.commandCountBuffer,
                range: 0..<MemoryLayout<UInt32>.size,
                value: 0
            )
            blit.endEncoding()
        }

        // Compute: populate ICB.
        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setComputePipelineState(state.computePipeline)
            compute.setBuffer(state.icbArgumentBuffer, offset: 0, index: 0)
            compute.setBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 1)
            compute.setBuffer(state.commandCountBuffer, offset: 0, index: 2)
            compute.useResource(state.icb, usage: .write)

            let tpg = min(
                maxCount,
                state.computePipeline.maxTotalThreadsPerThreadgroup
            )
            compute.dispatchThreads(
                MTLSize(width: maxCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tpg, height: 1, depth: 1)
            )
            compute.endEncoding()
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw ICBTestError.gpuError(error)
        }
    }

    // MARK: - Full ICB Sequence (offscreen render)

    /// Encode a full blit + compute + render ICB sequence to `renderTarget`.
    /// Uses `executeCommandsInBuffer` to exercise the GPU-driven draw path.
    func runICBSequence(
        state: IndirectCommandBufferState,
        features: inout FeatureVector,
        pipelineState: MTLRenderPipelineState,
        renderTarget: MTLTexture
    ) throws {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw ICBTestError.commandBufferFailed
        }

        let maxCount = state.configuration.maxCommandCount

        // Phase 1: Blit reset.
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.resetCommandsInBuffer(state.icb, range: 0..<maxCount)
            blit.fill(
                buffer: state.commandCountBuffer,
                range: 0..<MemoryLayout<UInt32>.size,
                value: 0
            )
            blit.endEncoding()
        }

        // Phase 2: Compute populate.
        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setComputePipelineState(state.computePipeline)
            compute.setBuffer(state.icbArgumentBuffer, offset: 0, index: 0)
            compute.setBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 1)
            compute.setBuffer(state.commandCountBuffer, offset: 0, index: 2)
            compute.useResource(state.icb, usage: .write)

            let tpg = min(
                maxCount,
                state.computePipeline.maxTotalThreadsPerThreadgroup
            )
            compute.dispatchThreads(
                MTLSize(width: maxCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tpg, height: 1, depth: 1)
            )
            compute.endEncoding()
        }

        // Phase 3: Render — execute ICB with inherited pipeline + stub buffers.
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture     = renderTarget
        rpd.colorAttachments[0].loadAction  = .clear
        rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            throw ICBTestError.metalSetupFailed
        }

        // Stub FFT + waveform buffers for inherited fragment shader bindings.
        let fftBuf = context.makeSharedBuffer(length: 512  * MemoryLayout<Float>.stride)!
        let wavBuf = context.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!

        // Write FeatureVector + StemFeatures into the state's UMA buffers.
        // setFragmentBytes is NOT inherited by ICB commands (only setFragmentBuffer is).
        memcpy(state.featureVectorBuffer.contents(), &features,
               MemoryLayout<FeatureVector>.stride)
        var stems = StemFeatures.zero
        memcpy(state.stemFeaturesBuffer.contents(), &stems,
               MemoryLayout<StemFeatures>.stride)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBuffer(state.featureVectorBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(fftBuf,                    offset: 0, index: 1)
        encoder.setFragmentBuffer(wavBuf,                    offset: 0, index: 2)
        encoder.setFragmentBuffer(state.stemFeaturesBuffer,  offset: 0, index: 3)

        encoder.useResource(state.icb, usage: .read, stages: [.vertex, .fragment])
        encoder.executeCommandsInBuffer(state.icb, range: 0..<maxCount)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw ICBTestError.gpuError(error)
        }
    }
}

// MARK: - Errors

private enum ICBTestError: Error {
    case commandBufferFailed
    case metalSetupFailed
    case gpuError(Error)
}
