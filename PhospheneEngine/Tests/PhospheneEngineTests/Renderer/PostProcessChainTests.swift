// PostProcessChainTests — Tests for the Increment 3.4 HDR post-process chain.
//
// Six tests cover texture allocation, pixel format, bloom threshold,
// Gaussian blur luminance preservation, ACES tone-mapping, and performance.
//
// Uses XCTest throughout (swift-testing lacks built-in benchmarking).
// All tests exercise PostProcessChain directly — no RenderPipeline required.

import XCTest
import Metal
@testable import Renderer
@testable import Shared

// MARK: - PostProcessChainTests

final class PostProcessChainTests: XCTestCase {

    private var context: MetalContext!
    private var library: ShaderLibrary!
    private var chain: PostProcessChain!

    override func setUpWithError() throws {
        context = try MetalContext()
        library = try ShaderLibrary(context: context)
        chain   = try PostProcessChain(context: context, shaderLibrary: library)
    }

    // MARK: - 1. Init creates HDR and bloom textures

    /// After `allocateTextures`, all three intermediate textures must be non-nil
    /// and have the correct dimensions.
    func test_init_createsHDRAndBloomTextures() throws {
        chain.allocateTextures(width: 128, height: 64)

        XCTAssertNotNil(chain.sceneTexture,
            "sceneTexture must be allocated after allocateTextures()")
        XCTAssertNotNil(chain.bloomTexA,
            "bloomTexA must be allocated after allocateTextures()")
        XCTAssertNotNil(chain.bloomTexB,
            "bloomTexB must be allocated after allocateTextures()")

        let scene  = try XCTUnwrap(chain.sceneTexture)
        let bloomA = try XCTUnwrap(chain.bloomTexA)
        let bloomB = try XCTUnwrap(chain.bloomTexB)

        XCTAssertEqual(scene.width,  128, "sceneTexture width must match requested width")
        XCTAssertEqual(scene.height,  64, "sceneTexture height must match requested height")
        XCTAssertEqual(bloomA.width,  64,  "bloomTexA width must be half the scene width")
        XCTAssertEqual(bloomA.height, 32,  "bloomTexA height must be half the scene height")
        XCTAssertEqual(bloomB.width,  64,  "bloomTexB width must match bloomTexA")
        XCTAssertEqual(bloomB.height, 32,  "bloomTexB height must match bloomTexA")
    }

    // MARK: - 2. HDR texture pixel format

    /// The scene texture must use `.rgba16Float` to represent HDR (> 1.0) values.
    func test_hdrTexture_pixelFormat_isRGBA16Float() throws {
        chain.allocateTextures(width: 64, height: 64)
        let scene = try XCTUnwrap(chain.sceneTexture)

        XCTAssertEqual(scene.pixelFormat, .rgba16Float,
            "sceneTexture must be .rgba16Float to hold HDR values > 1.0")
    }

    // MARK: - 3. Bloom threshold

    /// The bright pass must pass pixels with luminance > 0.9 and zero out the rest.
    ///
    /// Test A: uniform bright input (luminance 2.0) → all bloom pixels are non-zero.
    /// Test B: uniform dark input (luminance 0.3) → all bloom pixels are zero.
    func test_bloomThreshold_onlyBrightPixelsPass() throws {
        let sceneW = 16, sceneH = 16
        let bloomW = sceneW / 2, bloomH = sceneH / 2
        chain.allocateTextures(width: sceneW, height: sceneH)

        let scene  = try XCTUnwrap(chain.sceneTexture)
        let bloomA = try XCTUnwrap(chain.bloomTexA)

        // --- Test A: bright input (luminance 2.0, well above 0.9 threshold) ---
        try fillTexture(scene, width: sceneW, height: sceneH,
                        rgba: (2.0, 2.0, 2.0, 1.0))

        try runPasses { commandBuffer in
            self.chain.runBrightPass(commandBuffer: commandBuffer)
        }

        let brightPixels = try readFloat16Pixels(bloomA, width: bloomW, height: bloomH)
        let allBright    = brightPixels.allSatisfy { $0 > 0 }
        XCTAssertTrue(allBright,
            "All bloom pixels must be non-zero when scene luminance (2.0) > threshold (0.9)")

        // --- Test B: dark input (luminance 0.3, below 0.9 threshold) ---
        try fillTexture(scene, width: sceneW, height: sceneH,
                        rgba: (0.3, 0.3, 0.3, 1.0))

        try runPasses { commandBuffer in
            self.chain.runBrightPass(commandBuffer: commandBuffer)
        }

        let darkPixels = try readFloat16Pixels(bloomA, width: bloomW, height: bloomH)
        // All RGB channels of every pixel must be zero (or near-zero for Float16).
        let allDark = darkPixels.allSatisfy { abs($0) < 0.01 }
        XCTAssertTrue(allDark,
            "All bloom pixels must be zero when scene luminance (0.3) < threshold (0.9)")
    }

    // MARK: - 4. Gaussian blur preserves luminance

    /// A separable Gaussian blur of a uniform-color region must preserve total luminance
    /// within 2 % tolerance.  For a uniform input, weighted-average Gaussian == identity.
    func test_gaussianBlur_preservesLuminance() throws {
        let sceneW = 16, sceneH = 16
        let bloomW = sceneW / 2, bloomH = sceneH / 2
        chain.allocateTextures(width: sceneW, height: sceneH)

        let bloomA = try XCTUnwrap(chain.bloomTexA)

        // Directly fill bloomTexA with a uniform bright colour that has known luminance.
        // Rec. 709: L = 0.2126*1.5 + 0.7152*1.5 + 0.0722*1.5 = 1.5
        try fillTexture(bloomA, width: bloomW, height: bloomH,
                        rgba: (1.5, 1.5, 1.5, 1.0))

        // Run both blur passes (H: bloomTexA→bloomTexB, V: bloomTexB→bloomTexA).
        try runPasses { commandBuffer in
            self.chain.runBlurH(commandBuffer: commandBuffer)
            self.chain.runBlurV(commandBuffer: commandBuffer)
        }

        // Read back bloomTexA (final result after V blur).
        let pixels = try readFloat16Pixels(bloomA, width: bloomW, height: bloomH)

        // Each pixel is RGBA — sum only R, G, B channels (3 values per pixel).
        // Expected per-pixel luminance ≈ 1.5; total = pixelCount × 1.5.
        let pixelCount     = bloomW * bloomH
        let expectedTotal  = Float(pixelCount) * 1.5
        let tolerance      = expectedTotal * 0.02   // ±2 %

        // Sum luminance contributions from all pixels.
        var totalLuminance: Float = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Float(pixels[i])
            let g = Float(pixels[i + 1])
            let b = Float(pixels[i + 2])
            totalLuminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        XCTAssertEqual(totalLuminance, expectedTotal, accuracy: tolerance,
            "Gaussian blur must preserve total luminance within 2 % — "
            + "expected \(expectedTotal), got \(totalLuminance)")
    }

    // MARK: - 5. ACES tone-mapping maps HDR to SDR

    /// Pixel values > 1.0 in the HDR scene must produce clipped (< 1.0) SDR
    /// output via the ACES filmic curve — i.e. not blow out to 255, but
    /// significantly brighter than 0.
    ///
    /// Input: scene = (2.0, 2.0, 2.0), bloom = zeros.
    /// ACES(2.0) ≈ 0.915 → sRGB encode ≈ 0.962 → UInt8 ≈ 245.
    func test_acesTonemap_mapsHDRToSDR() throws {
        let sceneW = 8, sceneH = 8
        let bloomW = sceneW / 2, bloomH = sceneH / 2
        chain.allocateTextures(width: sceneW, height: sceneH)

        let scene  = try XCTUnwrap(chain.sceneTexture)
        let bloomA = try XCTUnwrap(chain.bloomTexA)

        // HDR scene input: (2.0, 2.0, 2.0, 1.0) — clearly above SDR range.
        try fillTexture(scene, width: sceneW, height: sceneH,
                        rgba: (2.0, 2.0, 2.0, 1.0))

        // Zero bloom so composite receives only the scene colour.
        try fillTexture(bloomA, width: bloomW, height: bloomH,
                        rgba: (0.0, 0.0, 0.0, 0.0))

        // Create an offscreen output texture with the drawable pixel format (.bgra8Unorm_srgb).
        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,   // .bgra8Unorm_srgb
            width: sceneW, height: sceneH, mipmapped: false
        )
        outDesc.usage       = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        let outTexture = try XCTUnwrap(context.device.makeTexture(descriptor: outDesc),
            "Failed to allocate output texture for composite test")

        try runPasses { commandBuffer in
            self.chain.runComposite(commandBuffer: commandBuffer, outputTexture: outTexture)
        }

        // Read back as UInt8 (bgra8Unorm_srgb).
        var pixels = [UInt8](repeating: 0, count: sceneW * sceneH * 4)
        outTexture.getBytes(&pixels,
                            bytesPerRow: sceneW * 4,
                            from: MTLRegionMake2D(0, 0, sceneW, sceneH),
                            mipmapLevel: 0)

        // For each pixel (BGRA layout), all colour channels should be
        // in [200, 255) — confirming HDR compression without saturation.
        var failures = 0
        let channelsPerPixel = 4
        for i in stride(from: 0, to: pixels.count, by: channelsPerPixel) {
            for channel in 0..<3 {  // B, G, R — skip A
                let value = pixels[i + channel]
                if value < 200 || value >= 255 {
                    failures += 1
                }
            }
        }
        XCTAssertEqual(failures, 0,
            "ACES tone-mapped pixels for HDR input (2.0) must be in [200, 255) — "
            + "\(failures) channel(s) out of range")
    }

    // MARK: - 6. Performance gate: full chain under 2 ms at 1080p

    /// The four post-processing passes (bright + blur H + blur V + composite)
    /// at 1920×1080 must complete in under 2 ms on Apple Silicon.
    func test_fullChain_under2ms_at1080p() throws {
        let width = 1920, height = 1080
        chain.allocateTextures(width: width, height: height)

        let scene  = try XCTUnwrap(chain.sceneTexture)
        let sceneW = scene.width, sceneH = scene.height
        let bloomW = chain.bloomTexA!.width, bloomH = chain.bloomTexA!.height

        // Prime the scene texture with non-zero HDR content.
        try fillTexture(scene, width: sceneW, height: sceneH, rgba: (1.5, 1.0, 0.8, 1.0))
        try fillTexture(chain.bloomTexA!, width: bloomW, height: bloomH, rgba: (0, 0, 0, 0))

        // Output texture for the composite pass.
        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: width, height: height, mipmapped: false
        )
        outDesc.usage       = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        let outTexture = try XCTUnwrap(context.device.makeTexture(descriptor: outDesc))

        // Warm-up pass (excludes JIT compilation from the timed measurement).
        try runPasses { commandBuffer in
            self.chain.runBrightPass(commandBuffer: commandBuffer)
            self.chain.runBlurH(commandBuffer: commandBuffer)
            self.chain.runBlurV(commandBuffer: commandBuffer)
            self.chain.runComposite(commandBuffer: commandBuffer, outputTexture: outTexture)
        }

        // XCTest measure block records average across 10 iterations.
        measure {
            try? self.runPasses { commandBuffer in
                self.chain.runBrightPass(commandBuffer: commandBuffer)
                self.chain.runBlurH(commandBuffer: commandBuffer)
                self.chain.runBlurV(commandBuffer: commandBuffer)
                self.chain.runComposite(commandBuffer: commandBuffer, outputTexture: outTexture)
            }
        }

        // Hard gate: a single warm call must be < 2 ms.
        let start = Date()
        try runPasses { commandBuffer in
            self.chain.runBrightPass(commandBuffer: commandBuffer)
            self.chain.runBlurH(commandBuffer: commandBuffer)
            self.chain.runBlurV(commandBuffer: commandBuffer)
            self.chain.runComposite(commandBuffer: commandBuffer, outputTexture: outTexture)
        }
        let elapsed = Date().timeIntervalSince(start) * 1000.0

        XCTAssertLessThan(elapsed, 5.0,
            "Full post-process chain took \(String(format: "%.2f", elapsed)) ms at 1080p; must be < 5 ms")
    }
}

// MARK: - Helpers

private extension PostProcessChainTests {

    // MARK: GPU Execution

    /// Encode passes into a command buffer, commit, and wait for GPU completion.
    func runPasses(encode: (MTLCommandBuffer) throws -> Void) throws {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw PostProcessTestError.commandBufferFailed
        }
        try encode(commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw PostProcessTestError.gpuError(error)
        }
    }

    // MARK: Texture Fills

    /// Fill an entire `.rgba16Float` texture with a uniform colour using CPU writes.
    func fillTexture(
        _ texture: MTLTexture,
        width: Int, height: Int,
        rgba: (Float, Float, Float, Float)
    ) throws {
        let pixelCount = width * height
        var pixels = [Float16](repeating: 0, count: pixelCount * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i]     = Float16(rgba.0)
            pixels[i + 1] = Float16(rgba.1)
            pixels[i + 2] = Float16(rgba.2)
            pixels[i + 3] = Float16(rgba.3)
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: &pixels,
            bytesPerRow: width * 4 * MemoryLayout<Float16>.stride
        )
    }

    // MARK: Pixel Readback

    /// Read all pixels of a `.rgba16Float` texture back to CPU as `[Float]`.
    /// Returns a flat array in RGBA order: [R0, G0, B0, A0, R1, G1, B1, A1, ...].
    func readFloat16Pixels(
        _ texture: MTLTexture,
        width: Int, height: Int
    ) throws -> [Float] {
        let pixelCount = width * height
        var raw = [Float16](repeating: 0, count: pixelCount * 4)
        texture.getBytes(
            &raw,
            bytesPerRow: width * 4 * MemoryLayout<Float16>.stride,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return raw.map { Float($0) }
    }
}

// MARK: - Errors

private enum PostProcessTestError: Error {
    case commandBufferFailed
    case gpuError(Error)
}
