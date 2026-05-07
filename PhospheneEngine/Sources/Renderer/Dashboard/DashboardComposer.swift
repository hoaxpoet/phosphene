// DashboardComposer — Lifecycle owner of the Telemetry dashboard cards (DASH.6).
//
// Owns one `DashboardTextLayer` (the shared MTLBuffer-backed bgra8 canvas), the
// three card builders (BEAT/STEMS/PERF), and one alpha-blended `MTLRenderPipelineState`
// that samples the layer texture into a top-right viewport on the drawable.
//
// Per-frame contract:
//   1. `update(beat:stems:perf:)` — called once per frame on `@MainActor` from
//      `VisualizerEngine`. Rebuilds card layouts and paints the chrome+text into
//      the layer's CGContext. Cheap pass-through when `enabled == false` or when
//      all three snapshots compare equal to the previous frame.
//   2. `composite(into:drawable:)` — called from `RenderPipeline.renderFrame`
//      AFTER the preset has finished writing to the drawable but BEFORE
//      `commandBuffer.present`. Encodes one render pass with `loadAction = .load`
//      that samples the layer texture into a top-right viewport.
//   3. `resize(to:)` — called from `mtkView(_:drawableSizeWillChange:)` so the
//      composer can recompute placement (the layer's pixel dimensions are derived
//      from the drawable's contentsScale, not hardcoded 2×).
//
// CPU/GPU lifetime: the layer is shared-storage UMA — CPU writes in `update()`
// are immediately visible to the GPU. Both the CPU rasterization and the GPU
// sample are scheduled into the same `MTLCommandBuffer` because `update()` is
// called immediately before `composite()` in the same render tick. No explicit
// synchronization is required (same lifetime guarantee as `DynamicTextOverlay`).
//
// The `enabled: Bool` flag is `nonisolated(unsafe)` — flipped from `@MainActor`
// on the `D` toggle and read on the render thread inside `composite()`. A bool
// is naturally atomic on Apple Silicon; tearing is impossible.

import CoreGraphics
import Metal
@preconcurrency import MetalKit
import Shared
import os.log

#if canImport(AppKit)
import AppKit
#endif

private let composerLog = Logger(subsystem: "com.phosphene.renderer", category: "DashboardComposer")

@MainActor
public final class DashboardComposer {

    // MARK: - Constants

    /// Layer canvas width in points. Sized for a 280pt card + 16pt insets.
    public static let defaultLayerWidth: CGFloat = 320
    /// Layer canvas height in points. Three stacked cards (BEAT≈190, STEMS≈158,
    /// PERF≈126 — see `DashboardCardLayout.height`) + 2 × `Spacing.cardGap` +
    /// top/bottom margin, with comfortable headroom for v1 retuning.
    public static let defaultLayerHeight: CGFloat = 660
    /// Outer margin from drawable's top/right edges to the layer.
    public static let outerMargin: CGFloat = DashboardTokens.Spacing.lg

    // MARK: - Public API

    /// User toggle, bound to the existing `D` shortcut via
    /// `VisualizerEngine.dashboardEnabled`. False = no card rendering, no GPU
    /// work, no CPU rebuilds. Both the toggle (PlaybackView's `D` action) and
    /// the per-frame `update`/`composite` calls run on `@MainActor`, so a plain
    /// stored property suffices.
    public var enabled: Bool = false

    /// Internal counter incremented every time `update()` actually rebuilds the
    /// card layouts and repaints the layer. Tests assert this stays flat across
    /// repeated calls with equal snapshots.
    internal private(set) var frameRebuildCount: Int = 0

    private let layerWidthPt: CGFloat
    private let layerHeightPt: CGFloat
    private let textLayer: DashboardTextLayer
    private let beatBuilder = BeatCardBuilder()
    private let stemsBuilder = StemsCardBuilder()
    private let perfBuilder = PerfCardBuilder()
    private let cardWidth: CGFloat
    private let compositePipelineState: MTLRenderPipelineState

    /// Last applied snapshots. `update()` short-circuits when all three compare
    /// equal to the previous frame's values. `StemFeatures` does not (and must
    /// not — D-085, GPU-shared `@frozen`) conform to `Equatable`, so the
    /// rebuild-skip uses a private `memcmp` over `MemoryLayout<StemFeatures>.size`.
    private var lastBeat: BeatSyncSnapshot = .zero
    private var lastStems: StemFeatures = .zero
    private var lastPerf: PerfSnapshot = .zero
    private var hasLastSnapshot: Bool = false

    /// Drawable size in pixels. Used to position the top-right viewport.
    private var drawableSizePx: CGSize = .zero

    // MARK: - Init

    /// Create a composer.
    ///
    /// - Parameters:
    ///   - device: Metal device used to allocate the layer + composite pipeline.
    ///   - bundle: Bundle to search for Epilogue fonts. Pass nil to use the
    ///     Renderer module bundle. Tests pass `Bundle(for: ...)` to drive the
    ///     font fallback path.
    ///   - layerWidth: Layer canvas width in points (default 320).
    ///   - layerHeight: Layer canvas height in points (default 660).
    public init?(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        pixelFormat: MTLPixelFormat,
        bundle: Bundle? = nil,
        layerWidth: CGFloat = defaultLayerWidth,
        layerHeight: CGFloat = defaultLayerHeight
    ) {
        let resolution = DashboardFontLoader.resolveFonts(in: bundle)
        // Pick a generous default contentsScale (2×) for the layer's pixel
        // backing — `resize(to:)` reallocates with the actual scale once the
        // drawable size is known. Without this default, tests that never call
        // `resize` still get a non-degenerate layer.
        let scale: CGFloat = 2.0
        guard let layer = DashboardTextLayer(
            device: device,
            width: Int(layerWidth * scale),
            height: Int(layerHeight * scale),
            fontResolution: resolution
        ) else {
            composerLog.error("DashboardComposer: text layer allocation failed")
            return nil
        }

        guard let pipeline = Self.makeCompositePipelineState(
            device: device,
            shaderLibrary: shaderLibrary,
            pixelFormat: pixelFormat
        ) else {
            composerLog.error("DashboardComposer: composite pipeline state creation failed")
            return nil
        }

        self.layerWidthPt = layerWidth
        self.layerHeightPt = layerHeight
        self.textLayer = layer
        self.cardWidth = layerWidth - 2 * DashboardTokens.Spacing.md
        self.compositePipelineState = pipeline
        composerLog.info("DashboardComposer ready: \(Int(layerWidth))×\(Int(layerHeight)) pt")
    }

    /// Per-frame snapshot push. Cheap pass-through when `enabled == false` or
    /// when all three snapshots compare equal to the previous frame.
    public func update(
        beat: BeatSyncSnapshot,
        stems: StemFeatures,
        perf: PerfSnapshot
    ) {
        guard enabled else { return }
        if hasLastSnapshot && snapshotsEqual(beat: beat, stems: stems, perf: perf) {
            return
        }
        lastBeat = beat
        lastStems = stems
        lastPerf = perf
        hasLastSnapshot = true
        frameRebuildCount &+= 1

        repaintLayer(beat: beat, stems: stems, perf: perf)
    }

    /// Encode the alpha-blended top-right composite. No-op when
    /// `enabled == false`. Caller is responsible for ensuring the drawable's
    /// texture is `.shaderRead` compatible (Metal default for layer-backed
    /// MTKView drawables). Convenience wrapper that unpacks the drawable's
    /// texture and forwards to `composite(into:drawableTexture:)`.
    public func composite(
        into commandBuffer: MTLCommandBuffer,
        drawable: CAMetalDrawable
    ) {
        composite(into: commandBuffer, drawableTexture: drawable.texture)
    }

    /// Encode the composite directly against an offscreen `MTLTexture`. Used
    /// by the production drawable path (above) and by tests (which cannot
    /// construct a real `CAMetalDrawable`).
    public func composite(
        into commandBuffer: MTLCommandBuffer,
        drawableTexture: MTLTexture
    ) {
        guard enabled else { return }
        let drawableTex = drawableTexture
        let drawableW = CGFloat(drawableTex.width)
        let drawableH = CGFloat(drawableTex.height)
        guard drawableW > 0 && drawableH > 0 else { return }

        textLayer.commit(into: commandBuffer)

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawableTex
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Compute viewport: top-right of the drawable, sized to the layer's
        // pixel dimensions. `outerMargin` is in points; convert to pixels using
        // the layer's own pixel-per-point ratio (allocated to match the
        // drawable's contentsScale via `resize`).
        let layerPxW = CGFloat(textLayer.texture.width)
        let layerPxH = CGFloat(textLayer.texture.height)
        let pxPerPt = layerPxW / layerWidthPt
        let marginPx = Self.outerMargin * pxPerPt
        let originX = drawableW - layerPxW - marginPx
        let originY = marginPx
        let viewport = MTLViewport(
            originX: Double(max(0, originX)),
            originY: Double(max(0, originY)),
            width: Double(min(layerPxW, drawableW)),
            height: Double(min(layerPxH, drawableH)),
            znear: 0.0,
            zfar: 1.0
        )

        encoder.setViewport(viewport)
        encoder.setRenderPipelineState(compositePipelineState)
        encoder.setFragmentTexture(textLayer.texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Recompute the layer's pixel dimensions to match the drawable's
    /// contentsScale. Call from `RenderPipeline.mtkView(_:drawableSizeWillChange:)`.
    public func resize(to drawableSize: CGSize) {
        guard drawableSize.width > 0 && drawableSize.height > 0 else { return }
        drawableSizePx = drawableSize
        // The drawable size is already in pixels (MTKView convention), but the
        // dashboard works in points. Estimate pxPerPt from the drawable's
        // shorter dimension vs a canonical 1080p logical size.
        // In practice, MTKView.drawableSize tracks the layer's contentsScale
        // exactly, so we can reallocate at a fixed 2× until evidence shows
        // otherwise — this keeps text crisp without overcommitting memory.
        let scale: CGFloat = max(1.0, min(3.0, drawableSize.height / 1080.0 * 2.0))
        let newW = Int(layerWidthPt * scale)
        let newH = Int(layerHeightPt * scale)
        guard newW != textLayer.texture.width || newH != textLayer.texture.height else { return }
        textLayer.resize(width: newW, height: newH)
        // Force a rebuild on next update — the canvas is fresh.
        hasLastSnapshot = false
    }

    // MARK: - Private — painting

    private func repaintLayer(
        beat: BeatSyncSnapshot,
        stems: StemFeatures,
        perf: PerfSnapshot
    ) {
        textLayer.beginFrame()

        let renderer = DashboardCardRenderer()
        let cgContext = textLayer.graphicsContext

        // Layer-internal coordinates are in points. The CGContext's CTM is set
        // up so y=0 is the top edge.
        let layouts: [DashboardCardLayout] = [
            beatBuilder.build(from: beat, width: cardWidth),
            stemsBuilder.build(from: stems, width: cardWidth),
            perfBuilder.build(from: perf, width: cardWidth)
        ]

        var cursorY: CGFloat = DashboardTokens.Spacing.md
        let originX: CGFloat = DashboardTokens.Spacing.md
        for layout in layouts {
            renderer.render(
                layout,
                at: CGPoint(x: originX, y: cursorY),
                on: textLayer,
                cgContext: cgContext
            )
            cursorY += layout.height + DashboardTokens.Spacing.cardGap
        }
        // commit() runs inside composite() so the GPU sample lands on the same
        // command buffer as the CPU write — same lifetime guarantee as
        // DynamicTextOverlay.
    }

    // MARK: - Private — equality

    private func snapshotsEqual(
        beat: BeatSyncSnapshot,
        stems: StemFeatures,
        perf: PerfSnapshot
    ) -> Bool {
        guard perf == lastPerf else { return false }
        guard bytewiseEqual(beat, lastBeat) else { return false }
        return bytewiseEqual(stems, lastStems)
    }

    /// `BeatSyncSnapshot` and `StemFeatures` do not (and must not — the latter
    /// is `@frozen` GPU-shared, the former is a Sendable value type intended
    /// for instrumentation, neither warrants a public `Equatable` conformance
    /// for this internal use) conform to `Equatable`. Compare bytewise instead.
    private func bytewiseEqual<T>(_ lhs: T, _ rhs: T) -> Bool {
        var lhsCopy = lhs
        var rhsCopy = rhs
        return withUnsafeBytes(of: &lhsCopy) { lhsBytes in
            withUnsafeBytes(of: &rhsCopy) { rhsBytes in
                lhsBytes.count == rhsBytes.count
                    && memcmp(lhsBytes.baseAddress, rhsBytes.baseAddress, lhsBytes.count) == 0
            }
        }
    }

    // MARK: - Private — pipeline construction

    private static func makeCompositePipelineState(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        guard let vertexFn = shaderLibrary.function(named: "dashboard_composite_vertex"),
              let fragmentFn = shaderLibrary.function(named: "dashboard_composite_fragment")
        else {
            composerLog.error("DashboardComposer: composite functions not found in shader library")
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        // Premultiplied source — the layer's CGContext produces premultiplied
        // alpha. Using `.sourceAlpha` would double-multiply; `.one` is correct.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            composerLog.error("DashboardComposer: pipeline create failed: \(String(describing: error))")
            return nil
        }
    }
}
