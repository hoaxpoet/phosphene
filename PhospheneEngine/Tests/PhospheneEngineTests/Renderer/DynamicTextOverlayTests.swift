// DynamicTextOverlayTests — Unit tests for DynamicTextOverlay and SpectralCartographText.

import Metal
import Testing
@testable import Renderer
@testable import Presets

@Suite("DynamicTextOverlay")
struct DynamicTextOverlayTests {

    private var device: MTLDevice {
        MTLCreateSystemDefaultDevice()!
    }

    // MARK: - Init

    @Test("init creates non-nil overlay on real device")
    func init_createsOverlay() throws {
        let overlay = DynamicTextOverlay(device: device)
        #expect(overlay != nil)
    }

    @Test("texture has correct dimensions")
    func texture_dimensions() throws {
        let overlay = try #require(DynamicTextOverlay(device: device))
        #expect(overlay.width  == 2048)
        #expect(overlay.height == 1024)
        #expect(overlay.texture.width  == 2048)
        #expect(overlay.texture.height == 1024)
    }

    @Test("texture pixel format is rgba8Unorm")
    func texture_pixelFormat() throws {
        let overlay = try #require(DynamicTextOverlay(device: device))
        #expect(overlay.texture.pixelFormat == .rgba8Unorm)
    }

    // MARK: - Refresh

    @Test("refresh invokes callback")
    func refresh_invokesCallback() throws {
        let overlay = try #require(DynamicTextOverlay(device: device))
        var callbackFired = false
        overlay.refresh { _, _ in callbackFired = true }
        #expect(callbackFired)
    }

    @Test("refresh passes correct canvas size")
    func refresh_canvasSize() throws {
        let overlay = try #require(DynamicTextOverlay(device: device))
        var receivedSize: CGSize = .zero
        overlay.refresh { _, size in receivedSize = size }
        #expect(receivedSize.width  == 2048)
        #expect(receivedSize.height == 1024)
    }

    @Test("multiple refresh calls do not crash")
    func refresh_multipleCallsAreSafe() throws {
        let overlay = try #require(DynamicTextOverlay(device: device))
        for _ in 0..<10 {
            overlay.refresh { ctx, size in
                SpectralCartographText.draw(in: ctx, size: size, bpm: 120, lockState: 2)
            }
        }
    }
}

@Suite("SpectralCartographText")
struct SpectralCartographTextTests {

    private var device: MTLDevice {
        MTLCreateSystemDefaultDevice()!
    }

    @Test("draw does not crash at bpm=0 lockState=0 (reactive mode)")
    func draw_reactiveModeNoCrash() throws {
        let overlay = try #require(DynamicTextOverlay(device: device))
        overlay.refresh { ctx, size in
            SpectralCartographText.draw(in: ctx, size: size, bpm: 0, lockState: 0)
        }
    }

    @Test("draw does not crash at bpm=120 lockState=2 (locked)")
    func draw_lockedModeNoCrash() throws {
        let overlay = try #require(DynamicTextOverlay(device: device))
        overlay.refresh { ctx, size in
            SpectralCartographText.draw(in: ctx, size: size, bpm: 120, lockState: 2)
        }
    }

    @Test("draw does not crash at extreme bpm values")
    func draw_extremeBPMNoCrash() throws {
        let overlay = try #require(DynamicTextOverlay(device: device))
        for bpm: Float in [0, 40, 60, 120, 180, 240, 999] {
            overlay.refresh { ctx, size in
                SpectralCartographText.draw(in: ctx, size: size, bpm: bpm, lockState: 1)
            }
        }
    }
}
