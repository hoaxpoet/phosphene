// DashboardComposerTests — Wiring + composite behaviour for DASH.6.
//
// All tests require MTLCreateSystemDefaultDevice(); they are skipped via
// withKnownIssue when no Metal device is available (CI without a GPU).
//
// Composite is tested against an offscreen `MTLTexture` rather than a real
// `CAMetalDrawable` (CAMetalDrawable cannot be constructed without a
// CAMetalLayer-backed view). The composer exposes a public
// `composite(into:drawableTexture:)` overload for this purpose.

import CoreGraphics
import Foundation
import Metal
import Testing
@testable import Renderer
@testable import Shared

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Helpers

@MainActor
private func makeComposer() -> DashboardComposer? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    do {
        let context = try MetalContext()
        let library = try ShaderLibrary(context: context)
        return DashboardComposer(
            device: device,
            shaderLibrary: library,
            pixelFormat: context.pixelFormat
        )
    } catch {
        return nil
    }
}

private func makeOffscreenDrawableTexture(
    device: MTLDevice,
    width: Int,
    height: Int,
    pixelFormat: MTLPixelFormat
) -> MTLTexture? {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: pixelFormat,
        width: width,
        height: height,
        mipmapped: false
    )
    desc.storageMode = .shared
    desc.usage = [.renderTarget, .shaderRead]
    return device.makeTexture(descriptor: desc)
}

/// Encode a clear pass that wipes the texture to RGBA(0,0,0,0). The composite
/// pipeline uses `loadAction = .load`, so any test that reads the drawable
/// after composite needs the dst to start at zero — otherwise blending against
/// an undefined initial state contaminates the assertion.
private func clearTexture(
    _ tex: MTLTexture,
    queue: MTLCommandQueue
) {
    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = tex
    rpd.colorAttachments[0].loadAction = .clear
    rpd.colorAttachments[0].storeAction = .store
    rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    guard let buf = queue.makeCommandBuffer(),
          let enc = buf.makeRenderCommandEncoder(descriptor: rpd) else { return }
    enc.endEncoding()
    buf.commit()
    buf.waitUntilCompleted()
}

/// Find the brightest pixel in a rectangular region. Returns the maximum of
/// (r, g, b, a) across the region — useful when the exact glyph / chrome
/// pixel-grid placement varies with font fallback.
private func maxChannelInRect(
    bytes: [UInt8],
    width: Int,
    rect: (x0: Int, y0: Int, x1: Int, y1: Int)
) -> Int {
    var maxV: UInt8 = 0
    for y in rect.y0..<rect.y1 {
        for x in rect.x0..<rect.x1 {
            let idx = (y * width + x) * 4
            // BGRA layout
            for k in 0..<4 where bytes[idx + k] > maxV {
                maxV = bytes[idx + k]
            }
        }
    }
    return Int(maxV)
}

private func makeBeat(bpm: Float, lockState: Int = 2, sessionMode: Int = 2) -> BeatSyncSnapshot {
    BeatSyncSnapshot(
        barPhase01: 0.25, beatsPerBar: 4, beatInBar: 2, isDownbeat: false,
        sessionMode: sessionMode, lockState: lockState, gridBPM: bpm,
        playbackTimeS: 1.0, driftMs: 5.0
    )
}

private func makeStems(drumsRel: Float = 0.3) -> StemFeatures {
    var s = StemFeatures.zero
    s.drumsEnergyRel = drumsRel
    s.bassEnergyRel = 0.1
    s.vocalsEnergyRel = -0.2
    s.otherEnergyRel = 0.05
    return s
}

private func makePerf(observed: Int = 30, frameMs: Float = 8.0) -> PerfSnapshot {
    PerfSnapshot(
        recentMaxFrameMs: frameMs,
        recentFramesObserved: observed,
        targetFrameMs: 14.0,
        qualityLevelRawValue: 0,
        qualityLevelDisplayName: "full",
        mlDecisionCode: 1,
        mlDeferRetryMs: 0
    )
}

// MARK: - Suite

@Suite("DashboardComposer")
@MainActor
struct DashboardComposerTests {

    // MARK: - (a) init

    @Test("init returns non-nil when Metal is available")
    func init_returnsNonNil_whenMetalAvailable() throws {
        try withKnownIssue(isIntermittent: true) {
            let composer = makeComposer()
            #expect(composer != nil, "DashboardComposer should construct on a Metal-capable host")
        } when: {
            MTLCreateSystemDefaultDevice() == nil
        }
    }

    // MARK: - (b) update is idempotent on equal snapshots

    @Test("update is idempotent when snapshots are unchanged")
    func update_idempotent_whenSnapshotsUnchanged() throws {
        try withKnownIssue(isIntermittent: true) {
            guard let composer = makeComposer() else {
                Issue.record("Metal device unavailable")
                return
            }
            composer.enabled = true
            let beat = makeBeat(bpm: 125)
            let stems = makeStems()
            let perf = makePerf()

            composer.update(beat: beat, stems: stems, perf: perf)
            let firstCount = composer.frameRebuildCount
            composer.update(beat: beat, stems: stems, perf: perf)
            let secondCount = composer.frameRebuildCount

            #expect(firstCount == 1, "first update should trigger one rebuild")
            #expect(secondCount == 1, "equal-snapshot update must short-circuit")
        } when: {
            MTLCreateSystemDefaultDevice() == nil
        }
    }

    // MARK: - (c) any input change rebuilds

    @Test("update rebuilds when any input changes (beat / stems / perf)")
    func update_rebuilds_whenAnyInputChanges() throws {
        try withKnownIssue(isIntermittent: true) {
            guard let composer = makeComposer() else {
                Issue.record("Metal device unavailable")
                return
            }
            composer.enabled = true
            let beat0 = makeBeat(bpm: 125)
            let stems0 = makeStems(drumsRel: 0.3)
            let perf0 = makePerf(observed: 30, frameMs: 8.0)

            composer.update(beat: beat0, stems: stems0, perf: perf0)
            let baseline = composer.frameRebuildCount

            // Change only beat.
            composer.update(beat: makeBeat(bpm: 130), stems: stems0, perf: perf0)
            #expect(composer.frameRebuildCount == baseline + 1, "beat change must rebuild")

            // Change only stems (relative to the previous applied beat).
            composer.update(beat: makeBeat(bpm: 130), stems: makeStems(drumsRel: 0.5), perf: perf0)
            #expect(composer.frameRebuildCount == baseline + 2, "stems change must rebuild")

            // Change only perf.
            composer.update(
                beat: makeBeat(bpm: 130),
                stems: makeStems(drumsRel: 0.5),
                perf: makePerf(observed: 60, frameMs: 12.0)
            )
            #expect(composer.frameRebuildCount == baseline + 3, "perf change must rebuild")
        } when: {
            MTLCreateSystemDefaultDevice() == nil
        }
    }

    // MARK: - (d) disabled composer is a no-op for composite

    @Test("composite is a no-op when composer is disabled")
    func composite_withDisabledComposer_isNoOp() throws {
        try withKnownIssue(isIntermittent: true) {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue(),
                  let composer = makeComposer()
            else {
                Issue.record("Metal device unavailable")
                return
            }
            composer.enabled = false
            // Push a non-trivial snapshot so the layer is dirty if updates were
            // honoured (they should not be — `update` short-circuits when disabled).
            composer.update(beat: makeBeat(bpm: 125), stems: makeStems(), perf: makePerf())
            #expect(composer.frameRebuildCount == 0, "disabled composer must not rebuild")

            guard let target = makeOffscreenDrawableTexture(
                    device: device, width: 320, height: 240, pixelFormat: .bgra8Unorm),
                  let buf = queue.makeCommandBuffer()
            else {
                Issue.record("Metal command buffer / texture allocation failed")
                return
            }

            // Sample target before composite.
            let beforeBytes = readPixels(target)

            composer.composite(into: buf, drawableTexture: target)
            buf.commit()
            buf.waitUntilCompleted()

            let afterBytes = readPixels(target)
            #expect(beforeBytes == afterBytes, "disabled composite must not write to drawable")
        } when: {
            MTLCreateSystemDefaultDevice() == nil
        }
    }

    // MARK: - (e) update + composite produces non-zero alpha in top-right

    @Test("update then composite produces non-zero alpha in top-right region")
    func update_thenComposite_producesNonZeroAlphaInTopRight() throws {
        try withKnownIssue(isIntermittent: true) {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue(),
                  let composer = makeComposer()
            else {
                Issue.record("Metal device unavailable")
                return
            }
            composer.enabled = true
            // Use the production drawable size so placement reads top-right.
            let width = 1920
            let height = 1080
            composer.resize(to: CGSize(width: width, height: height))

            // Forced-dispatch fixture — non-trivial PERF state so the bar /
            // status colour give us an unambiguous painted pixel band.
            let perf = PerfSnapshot(
                recentMaxFrameMs: 11.0,
                recentFramesObserved: 30,
                targetFrameMs: 14.0,
                qualityLevelRawValue: 0,
                qualityLevelDisplayName: "full",
                mlDecisionCode: 3,            // forceDispatch
                mlDeferRetryMs: 0
            )
            composer.update(beat: makeBeat(bpm: 125), stems: makeStems(drumsRel: 0.4), perf: perf)

            guard let target = makeOffscreenDrawableTexture(
                    device: device, width: width, height: height, pixelFormat: .bgra8Unorm),
                  let buf = queue.makeCommandBuffer()
            else {
                Issue.record("Metal command buffer / texture allocation failed")
                return
            }

            // Wipe target to (0,0,0,0) so loadAction=.load reads a defined dst.
            clearTexture(target, queue: queue)

            composer.composite(into: buf, drawableTexture: target)
            buf.commit()
            buf.waitUntilCompleted()

            // Scan a rectangle inside the top-right card region for ANY painted
            // pixel — exact glyph placement varies with font fallback, so a
            // single-point sample is too brittle.
            let bytes = readPixels(target)
            let maxV = maxChannelInRect(
                bytes: bytes, width: width,
                rect: (x0: width - 600, y0: 40, x1: width - 50, y1: 600)
            )
            #expect(maxV > 0, "top-right card region must contain painted pixels (max channel = \(maxV))")
        } when: {
            MTLCreateSystemDefaultDevice() == nil
        }
    }

    // MARK: - (f) resize recomputes placement

    @Test("resize recomputes placement so 4K drawable still paints top-right")
    func resize_recomputesPlacement() throws {
        try withKnownIssue(isIntermittent: true) {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue(),
                  let composer = makeComposer()
            else {
                Issue.record("Metal device unavailable")
                return
            }
            composer.enabled = true
            let width = 3840
            let height = 2160
            composer.resize(to: CGSize(width: width, height: height))
            composer.update(beat: makeBeat(bpm: 125), stems: makeStems(), perf: makePerf())

            guard let target = makeOffscreenDrawableTexture(
                    device: device, width: width, height: height, pixelFormat: .bgra8Unorm),
                  let buf = queue.makeCommandBuffer()
            else {
                Issue.record("Metal command buffer / texture allocation failed")
                return
            }

            clearTexture(target, queue: queue)

            composer.composite(into: buf, drawableTexture: target)
            buf.commit()
            buf.waitUntilCompleted()

            let bytes = readPixels(target)
            let maxV = maxChannelInRect(
                bytes: bytes, width: width,
                rect: (x0: width - 800, y0: 40, x1: width - 50, y1: 800)
            )
            #expect(maxV > 0, "4K top-right card region must contain painted pixels (max channel = \(maxV))")
        } when: {
            MTLCreateSystemDefaultDevice() == nil
        }
    }
}

// MARK: - Pixel helpers (file-local)

private func pixelAt(_ x: Int, _ y: Int, in bytes: [UInt8], width: Int)
    -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
    let idx = (y * width + x) * 4
    return (bytes[idx], bytes[idx + 1], bytes[idx + 2], bytes[idx + 3])
}

private func readPixels(_ texture: MTLTexture) -> [UInt8] {
    let count = texture.width * texture.height * 4
    var bytes = [UInt8](repeating: 0, count: count)
    texture.getBytes(&bytes,
                     bytesPerRow: texture.width * 4,
                     from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                     mipmapLevel: 0)
    return bytes
}
