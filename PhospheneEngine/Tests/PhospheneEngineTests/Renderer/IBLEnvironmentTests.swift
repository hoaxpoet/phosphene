// IBLEnvironmentTests — RMENV.2 gallery-environment bake.
//
// Proves the `envType` selector actually changes the baked IBL cubemap (a bug
// that left envType inert would make a preset's gallery opt-in a no-op
// while still looking plausible). The complementary guarantee — envType 0 is
// byte-identical to pre-RMENV — is covered by PresetRegressionTests staying green
// on every ray-march preset.

import Testing
import Metal
import Foundation
@testable import Renderer

@Suite("RMENV.2 — gallery IBL environment")
struct IBLEnvironmentTests {

    @Test("Gallery env (1) bakes a different irradiance cubemap than default (0)")
    func galleryDiffersFromDefault() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("IBLEnvironmentTests: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)

        let env0 = try IBLManager(context: ctx, shaderLibrary: lib, envType: 0)
        let env1 = try IBLManager(context: ctx, shaderLibrary: lib, envType: 1)
        #expect(env0.envType == 0)
        #expect(env1.envType == 1)

        // Read the +Y face (index 2 — the ceiling, where the gallery's bright
        // skylight strips diverge most from the default warm ceiling). rgba16Float
        // = 8 bytes/texel; any byte difference proves the bake responded to envType.
        let face   = 2
        let size   = IBLManager.irradianceFaceSize
        let bpr    = size * 8
        let region = MTLRegionMake2D(0, 0, size, size)
        var b0 = [UInt8](repeating: 0, count: size * bpr)
        var b1 = [UInt8](repeating: 0, count: size * bpr)
        env0.irradianceMap.getBytes(&b0, bytesPerRow: bpr, bytesPerImage: size * bpr,
                                    from: region, mipmapLevel: 0, slice: face)
        env1.irradianceMap.getBytes(&b1, bytesPerRow: bpr, bytesPerImage: size * bpr,
                                    from: region, mipmapLevel: 0, slice: face)

        #expect(b0 != b1, "gallery envType (1) must bake a different cubemap than default (0)")
    }
}
