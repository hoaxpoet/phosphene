// RenderPipeline — MTKViewDelegate that drives the audio-reactive render loop.
// Binds FFT magnitude and PCM waveform UMA buffers to a full-screen fragment shader.

import Metal
import MetalKit
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "RenderPipeline")

public final class RenderPipeline: NSObject, MTKViewDelegate, @unchecked Sendable {

    // MARK: - Metal State

    private let context: MetalContext
    private let pipelineState: MTLRenderPipelineState

    // MARK: - Audio Buffers (UMA zero-copy — written by audio thread, read by GPU)

    private let fftMagnitudeBuffer: MTLBuffer   // 512 floats from FFTProcessor
    private let waveformBuffer: MTLBuffer       // 2048 interleaved floats from AudioBuffer

    // MARK: - Timing

    private let startTime: CFAbsoluteTime
    private var lastFrameTime: CFAbsoluteTime

    // MARK: - Init

    /// Create the render pipeline with audio buffer bindings.
    ///
    /// - Parameters:
    ///   - context: Metal context (device, queue, semaphore).
    ///   - shaderLibrary: Compiled shader library for pipeline state creation.
    ///   - fftBuffer: UMA buffer containing 512 FFT magnitude bins (from FFTProcessor).
    ///   - waveformBuffer: UMA buffer containing interleaved stereo PCM (from AudioBuffer).
    public init(
        context: MetalContext,
        shaderLibrary: ShaderLibrary,
        fftBuffer: MTLBuffer,
        waveformBuffer: MTLBuffer
    ) throws {
        self.context = context
        self.fftMagnitudeBuffer = fftBuffer
        self.waveformBuffer = waveformBuffer
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.lastFrameTime = self.startTime

        // Create render pipeline state: fullscreen_vertex → waveform_fragment.
        self.pipelineState = try shaderLibrary.renderPipelineState(
            named: "waveform",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "waveform_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device
        )

        super.init()
        logger.info("RenderPipeline initialized with audio-reactive shader")
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Resize handling will be added when feedback textures are introduced.
    }

    public func draw(in view: MTKView) {
        // Wait for an available frame slot (triple buffering).
        context.inflightSemaphore.wait()

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            context.inflightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [semaphore = context.inflightSemaphore] _ in
            semaphore.signal()
        }

        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            commandBuffer.commit()
            return
        }

        // Black background — visuals emerge from darkness (Phosphene color philosophy).
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            commandBuffer.commit()
            return
        }

        // Timing.
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = Float(now - startTime)
        let deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now

        // Build FeatureVector with timing info.
        // Full band energy / onset analysis comes in later increments (DSP module).
        var features = FeatureVector(time: elapsed, deltaTime: deltaTime)

        // Bind shader pipeline and audio buffers.
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)

        // Draw full-screen triangle (3 vertices, generated in vertex shader).
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
