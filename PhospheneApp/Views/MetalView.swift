// MetalView — NSViewRepresentable wrapping MTKView with RenderPipeline as delegate.

import SwiftUI
import MetalKit
import Renderer

struct MetalView: NSViewRepresentable {
    let context: MetalContext
    let pipeline: RenderPipeline

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

    func updateNSView(_ nsView: MTKView, context: Context) {
        // No dynamic SwiftUI state to push into the view yet.
    }
}
