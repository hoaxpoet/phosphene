// RicercarEchoGeometry+Sizing — the trail follows the drawable (RICERCAR-WIRE.2).
//
// Split out of `RicercarEchoGeometry.swift` because adding it pushed that file past the 400-line
// lint cap. Sizing is a self-contained concern — allocate the ping-pong pair, clear it, swap it —
// so it is the natural seam rather than an arbitrary cut.
//
// ⚠ The defect this exists for: the trail was allocated ONCE at the configuration's 1280x720 and
// never followed the drawable, so at 3840x2160 every thin calligraphic mark went through a 3x
// linear upscale. Matt's M7: "looks good ... blurry, should be substantially more clear and crisp."
// Two further symptoms shared the one wrong number — the display pass computes its bloom offsets
// in TRAIL texels, so the bloom was 3x too wide on screen, and the painterly ground's `aspect` is
// derived from the configuration, so it stayed 1.78 while the window was 1.13.

import Metal

// MARK: - Drawable sizing

public extension RicercarEchoGeometry {

    /// Allocate the trail 1:1 with the drawable (RICERCAR-WIRE.2).
    ///
    /// ⚠ **A fixed internal size is not a smaller picture, it is a blurrier one.** Full symptom
    /// list and evidence: `ENGINEERING_PLAN.md` §RICERCAR-WIRE.2.
    ///
    /// A reallocation necessarily drops the trail, so marks vanish for a frame. That is correct on
    /// a resize and must not be "fixed" by keeping a stale-size texture.
    public func ensureAllocated(width: Int, height: Int) {
        let newW = max(1, width), newH = max(1, height)
        guard newW != configuration.width || newH != configuration.height else { return }
        guard let fresh = Self.makeTrail(device: device, width: newW, height: newH) else { return }
        trail = fresh
        cur = 0
        configuration = RicercarEchoConfiguration(
            width: newW, height: newH, maxGestures: configuration.maxGestures)
        Self.clear(trail: fresh, device: device)
    }

    /// The ping-pong pair. `nil` rather than a throw so a resize that cannot allocate keeps
    /// drawing at the old size instead of tearing down a running visual.
    static func makeTrail(device: MTLDevice, width: Int, height: Int) -> [MTLTexture]? {
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        td.usage = [.shaderRead, .renderTarget]
        td.storageMode = .private
        var texs: [MTLTexture] = []
        for _ in 0..<2 {
            guard let tex = device.makeTexture(descriptor: td) else { return nil }
            texs.append(tex)
        }
        return texs
    }

    static func clear(trail: [MTLTexture], device: MTLDevice) {
        guard let queue = device.makeCommandQueue(), let cmd = queue.makeCommandBuffer() else { return }
        for tex in trail {
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = tex
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            rpd.colorAttachments[0].storeAction = .store
            cmd.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        }
        cmd.commit(); cmd.waitUntilCompleted()
    }
}
