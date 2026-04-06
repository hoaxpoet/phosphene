// RenderPipeline — MTKViewDelegate that drives the render loop.
// Clears to a time-varying color to prove the loop is alive at display refresh rate.

import Metal
import MetalKit

public final class RenderPipeline: NSObject, MTKViewDelegate, Sendable {
    private let context: MetalContext
    private let startTime: CFAbsoluteTime

    public init(context: MetalContext) {
        self.context = context
        self.startTime = CFAbsoluteTimeGetCurrent()
        super.init()
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Resize handling will be added when feedback textures are introduced.
    }

    public func draw(in view: MTKView) {
        // Wait for an available frame slot (triple buffering).
        context.inflightSemaphore.wait()

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            context.inflightSemaphore.signal()
            return
        }

        // Signal the semaphore when the GPU finishes this frame.
        commandBuffer.addCompletedHandler { [semaphore = context.inflightSemaphore] _ in
            semaphore.signal()
        }

        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            commandBuffer.commit()
            return
        }

        // Time-varying clear color — slowly cycles through deep, saturated hues
        // (Phosphene's color philosophy: rich colors emerging from darkness).
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let hue = elapsed.truncatingRemainder(dividingBy: 12.0) / 12.0
        let (red, green, blue) = hueToRGB(hue)
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: red * 0.6,
            green: green * 0.6,
            blue: blue * 0.6,
            alpha: 1.0
        )
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            commandBuffer.commit()
            return
        }
        // No draw calls yet — just the clear color proves the render loop is alive.
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Color Utility

    /// Convert hue (0–1) to RGB. Saturation and brightness are both 1.0.
    private func hueToRGB(_ hue: Double) -> (Double, Double, Double) {
        let segment = hue * 6.0
        let fraction = segment - segment.rounded(.down)
        switch Int(segment) % 6 {
        case 0: return (1.0, fraction, 0.0)
        case 1: return (1.0 - fraction, 1.0, 0.0)
        case 2: return (0.0, 1.0, fraction)
        case 3: return (0.0, 1.0 - fraction, 1.0)
        case 4: return (fraction, 0.0, 1.0)
        default: return (1.0, 0.0, 1.0 - fraction)
        }
    }
}
