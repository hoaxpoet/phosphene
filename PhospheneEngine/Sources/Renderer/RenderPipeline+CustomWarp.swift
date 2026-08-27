// RenderPipeline+CustomWarp — the plumbing the four custom-warp presets share.
//
// Nacre, Floret, Glaze and Fata Morgana each drive their own feedback loop (D-139):
// a preset-authored warp fragment, a signature comp, and a swap. Those loops genuinely
// differ — Glaze runs an extra pass, Fata Morgana adds a blur target and shapes — so
// each preset keeps its own `render<Preset>`. What they do NOT differ in is the
// scaffolding either side of it, which is collected here (RECON.23):
//
//   · acquire drawable → render into it → present   (`drawCustomWarp`)
//   · reduced motion: comp the CURRENT feedback, no warp, no swap
//
// Both were four and three verbatim copies respectively before this file existed.

import Metal
@preconcurrency import MetalKit
import Shared

extension RenderPipeline {

    /// Live entry point shared by the custom-warp presets: acquire the drawable, run the
    /// preset's own render into it, present. `render` takes the target texture so the live
    /// drawable path and the offscreen diag harness run the EXACT same render code
    /// (FA #66 — no reimplemented test path).
    @MainActor
    func drawCustomWarp(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        site: String,
        render: (MTLTexture) -> Void
    ) {
        guard let drawable = instrumentedDrawable(
            from: view, commandBuffer: commandBuffer, site: site
        ) else { return }
        render(drawable.texture)
        instrumentedPresent(drawable, on: commandBuffer)
    }

    /// Reduced-motion (U.9 / a11y) frame for a custom-warp preset: the preset's signature
    /// comp of the CURRENT, un-advanced feedback — no warp pass and no swap, so nothing
    /// accumulates and nothing moves.
    ///
    /// This exists rather than reusing the shared `drawMVWarpReducedMotion` because that
    /// renders a preset's DIRECT pipeline straight to the drawable, and these presets
    /// compile their direct pipeline for an `.rgba16Float` feedback format — a 16-float
    /// pipeline against an 8-bit drawable is an attachment-format mismatch that crashes
    /// (BUG-061). The comp (blit) pipeline is compiled for the drawable format, so routing
    /// reduced motion through it is both crash-safe and the correct "static frame" the
    /// U.9 contract asks for.
    ///
    /// `uniforms` is the preset's own uniform struct, passed by value and bound at
    /// fragment buffer(1) exactly as its comp shader expects.
    @MainActor
    func renderCustomWarpReducedMotion<Uniforms>(
        commandBuffer: MTLCommandBuffer,
        warpState: MVWarpState,
        target: MTLTexture,
        uniforms: Uniforms
    ) {
        var uni = uniforms
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = target
        desc.colorAttachments[0].loadAction  = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(warpState.blitPipeline)        // the preset's comp (drawable format)
        enc.setFragmentTexture(warpState.warpTexture, index: 0)   // current feedback, NOT advanced
        enc.setFragmentBytes(&uni, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
}
