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

        return view
    }

    /// Updates the MTKView when SwiftUI state changes.
    func updateNSView(_ nsView: MTKView, context: Context) {
        // No dynamic SwiftUI state to push into the view yet.
    }
}
