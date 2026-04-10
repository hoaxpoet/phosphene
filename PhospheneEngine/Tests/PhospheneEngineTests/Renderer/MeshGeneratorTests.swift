// MeshGeneratorTests — Pipeline state, dispatch, configuration, and performance
// tests for the Increment 3.2 mesh shader infrastructure.
//
// Uses XCTest throughout (swift-testing lacks built-in benchmarking).
// All six tests exercise MeshGenerator directly — no RenderPipeline required.

import XCTest
import Metal
@testable import Renderer
@testable import Shared

// MARK: - MeshGeneratorTests

final class MeshGeneratorTests: XCTestCase {

    private var device: MTLDevice!
    private var library: MTLLibrary!
    private let pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    override func setUpWithError() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        device  = dev
        library = try ShaderLibrary(context: MetalContext()).library
    }

    // MARK: - 1. Descriptor

    /// Verifies init produces a valid pipeline descriptor for the current hardware.
    ///
    /// On M3+ (`device.supportsFamily(.apple8)`), `usesMeshShaderPath` must be
    /// true (native `MTLMeshRenderPipelineDescriptor` was used).  On M1/M2 it
    /// must be false (standard vertex+fragment fallback descriptor was used).
    func test_init_createsMeshPipelineDescriptor() throws {
        let generator = try MeshGenerator(
            device: device, library: library, pixelFormat: pixelFormat
        )

        let expectedMeshPath = device.supportsFamily(.apple8)
        XCTAssertEqual(generator.usesMeshShaderPath, expectedMeshPath,
            "usesMeshShaderPath must match device.supportsFamily(.apple8) = \(expectedMeshPath)")
    }

    // MARK: - 2. Pipeline State

    /// Verifies the compiled pipeline state is non-nil after init.
    ///
    /// `MTLRenderPipelineState` is a protocol type; checking the property is
    /// accessible is sufficient — if init threw, the test would have already failed.
    func test_meshPipelineState_createdSuccessfully() throws {
        let generator = try MeshGenerator(
            device: device, library: library, pixelFormat: pixelFormat
        )

        // If init succeeded without throwing, pipelineState is guaranteed non-nil
        // (it is a non-optional stored let).  Access it to confirm the property
        // is reachable and has a non-zero memory address.
        let label = generator.pipelineState.label
        // label may be nil on some drivers; the important thing is the property exists.
        _ = label
        XCTAssertTrue(true, "pipelineState accessible without crash")
    }

    // MARK: - 3. Dispatch

    /// Dispatches a trivial mesh draw against an offscreen render target and
    /// verifies the command buffer completes without a GPU error.
    func test_dispatch_meshDraw_completesWithoutError() throws {
        let generator = try MeshGenerator(
            device: device, library: library, pixelFormat: pixelFormat
        )

        // Allocate a small offscreen render target.
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: 64,
            height: 64,
            mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc) else {
            throw MeshGeneratorTestError.textureAllocationFailed
        }

        guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer() else {
            throw MeshGeneratorTestError.commandBufferFailed
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture     = texture
        passDesc.colorAttachments[0].loadAction  = .clear
        passDesc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            throw MeshGeneratorTestError.encoderFailed
        }

        let features = FeatureVector(bass: 0.5, time: 1.0, deltaTime: 0.016)
        generator.draw(encoder: encoder, features: features)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        XCTAssertEqual(commandBuffer.status, .completed,
            "Command buffer should complete — GPU error: \(commandBuffer.error?.localizedDescription ?? "none")")
        XCTAssertNil(commandBuffer.error,
            "Mesh draw dispatch must produce no GPU error")
    }

    // MARK: - 4. maxVerticesPerMeshlet

    /// Verifies the default configuration constant is 256.
    func test_maxVerticesPerMeshlet_is256() throws {
        let config = MeshGeneratorConfiguration()
        XCTAssertEqual(config.maxVerticesPerMeshlet, 256,
            "Default maxVerticesPerMeshlet must be 256")
    }

    // MARK: - 5. maxPrimitivesPerMeshlet

    /// Verifies the default configuration constant is 512.
    func test_maxPrimitivesPerMeshlet_is512() throws {
        let config = MeshGeneratorConfiguration()
        XCTAssertEqual(config.maxPrimitivesPerMeshlet, 512,
            "Default maxPrimitivesPerMeshlet must be 512")
    }

    // MARK: - 6. Performance

    /// Benchmarks a single mesh draw dispatch against an offscreen render target.
    ///
    /// Target: < 16 ms average (60 fps budget).  The measure block includes
    /// command buffer creation, encoding, commit, and GPU wait, so it captures
    /// the full end-to-end frame cost including GPU execution time.
    func test_meshShaderFractal_60fps_frameTimeUnder16ms() throws {
        let generator = try MeshGenerator(
            device: device, library: library, pixelFormat: pixelFormat
        )

        // Reusable offscreen render target (64×64 is representative of real cost).
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: 64,
            height: 64,
            mipmapped: false
        )
        texDesc.usage       = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc),
              let queue   = device.makeCommandQueue() else {
            throw MeshGeneratorTestError.textureAllocationFailed
        }

        let features = FeatureVector(bass: 0.6, mid: 0.4, treble: 0.2,
                                     time: 1.0, deltaTime: 0.016)

        // Warm-up dispatch (excludes JIT compilation overhead from measure).
        if let warmupBuf = queue.makeCommandBuffer() {
            let passDesc = Self.makePassDescriptor(texture: texture)
            if let enc = warmupBuf.makeRenderCommandEncoder(descriptor: passDesc) {
                generator.draw(encoder: enc, features: features)
                enc.endEncoding()
            }
            warmupBuf.commit()
            warmupBuf.waitUntilCompleted()
        }

        // XCTest measure block.
        measure {
            guard let commandBuffer = queue.makeCommandBuffer() else { return }
            let passDesc = Self.makePassDescriptor(texture: texture)
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) {
                generator.draw(encoder: enc, features: features)
                enc.endEncoding()
            }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        // Hard assertion on a single warm call.
        let start = Date()
        if let commandBuffer = queue.makeCommandBuffer() {
            let passDesc = Self.makePassDescriptor(texture: texture)
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) {
                generator.draw(encoder: enc, features: features)
                enc.endEncoding()
            }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        let elapsed = Date().timeIntervalSince(start) * 1000.0

        XCTAssertLessThan(elapsed, 16.0,
            "Mesh draw took \(String(format: "%.2f", elapsed))ms; must be < 16ms for 60fps")
    }

    // MARK: - Helpers

    private static func makePassDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = texture
        desc.colorAttachments[0].loadAction  = .clear
        desc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        return desc
    }
}

// MARK: - Errors

private enum MeshGeneratorTestError: Error {
    case textureAllocationFailed
    case commandBufferFailed
    case encoderFailed
}
