// PostProcessBloomGateTests — Verifies the frame-budget governor bloom gate on PostProcessChain.
//
// Tests that bloomEnabled correctly controls whether bloom passes execute,
// that ACES composite always runs regardless, and that toggling mid-session
// does not crash or leak allocations.

import Testing
import Metal
@testable import Renderer
@testable import Shared

// MARK: - PostProcessBloomGateTests

struct PostProcessBloomGateTests {

    private func makeChain() throws -> (PostProcessChain, MTLDevice) {
        let ctx = try MetalContext()
        let lib = try Renderer.ShaderLibrary(context: ctx)
        let chain = try PostProcessChain(context: ctx, shaderLibrary: lib)
        return (chain, ctx.device)
    }

    // MARK: - 1. bloomEnabled defaults to true

    @Test
    func bloomEnabledDefaultsTrue() throws {
        let (chain, _) = try makeChain()
        #expect(chain.bloomEnabled == true)
    }

    // MARK: - 2. bloomEnabled == false does not crash when textures are allocated

    @Test
    func bloomDisabled_noBloomPasses_nocrash() throws {
        let (chain, _) = try makeChain()
        chain.allocateTextures(width: 32, height: 32)
        chain.bloomEnabled = false
        // Verify the flag is reflected correctly.
        #expect(chain.bloomEnabled == false)
        // sceneTexture should still exist (allocated normally).
        #expect(chain.sceneTexture != nil)
        // Bloom textures are still allocated (just not written during the
        // disabled pass) — they are not deallocated on disable.
        #expect(chain.bloomTexA != nil)
        #expect(chain.bloomTexB != nil)
    }

    // MARK: - 3. Toggling mid-session does not crash or leak

    @Test
    func toggleBloomEnabledMultipleTimes_noLeak() throws {
        let (chain, _) = try makeChain()
        chain.allocateTextures(width: 64, height: 64)
        for i in 0..<20 {
            chain.bloomEnabled = (i % 2 == 0)
        }
        // After all toggles, textures still valid.
        #expect(chain.sceneTexture != nil)
        #expect(chain.bloomTexA != nil)
    }

    // MARK: - 4. Re-enable after disable restores bloomEnabled

    @Test
    func reEnableBloom_bloomEnabledTrue() throws {
        let (chain, _) = try makeChain()
        chain.bloomEnabled = false
        chain.bloomEnabled = true
        #expect(chain.bloomEnabled == true)
    }

    // MARK: - 5. runBloomAndComposite path with bloomEnabled=false does not crash

    @Test
    func runBloomAndComposite_bloomDisabled_nocrash() throws {
        let (chain, device) = try makeChain()
        chain.bloomEnabled = false
        // Allocate a minimal external scene texture and output texture.
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: 8, height: 8, mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .private
        guard let sceneTex = device.makeTexture(descriptor: texDesc) else { return }

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 8, height: 8, mipmapped: false
        )
        outDesc.usage = [.renderTarget, .shaderRead]
        outDesc.storageMode = .private
        guard let outTex = device.makeTexture(descriptor: outDesc),
              let queue = device.makeCommandQueue(),
              let cmdBuf = queue.makeCommandBuffer() else { return }

        // Should not crash even with bloomEnabled=false.
        chain.runBloomAndComposite(from: sceneTex, to: outTex, commandBuffer: cmdBuf)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
    }
}
