// MetalView — NSViewRepresentable wrapping MTKView with RenderPipeline as delegate.

import MetalKit
import Renderer
import SwiftUI

// MARK: - MetalView

/// SwiftUI wrapper around `MTKView` for Metal rendering.
///
/// Bridges the Metal render pipeline into the SwiftUI view hierarchy.
/// The view draws continuously at the display refresh rate (60 or 120 Hz).
struct MetalView: NSViewRepresentable {

    /// Metal context providing device and pixel format.
    let context: MetalContext

    /// Render pipeline used as the MTKView delegate.
    let pipeline: RenderPipeline

    /// Creates and configures the underlying `MTKView`.
    func makeNSView(context nsViewContext: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.device)
        view.colorPixelFormat = context.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = pipeline

        // Draw at display refresh rate (60 or 120 Hz on ProMotion).
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        // Allow reading the drawable texture post-render. Required for the
        // SessionRecorder's blit-to-capture-texture path; without this, the
        // blit traps with "source texture is framebufferOnly" on first frame.
        // Minor cost: Metal cannot use tile memory optimizations for the
        // drawable. Acceptable at 60 fps on Apple Silicon.
        view.framebufferOnly = false

        // The render surface carries no semantic meaning for VoiceOver.
        view.setAccessibilityElement(false)

        return view
    }

    /// Updates the MTKView when SwiftUI state changes.
    func updateNSView(_ nsView: MTKView, context: Context) {
        // No dynamic SwiftUI state to push into the view yet.
    }
}
