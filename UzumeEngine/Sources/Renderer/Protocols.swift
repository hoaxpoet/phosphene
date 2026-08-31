// Protocols — Dependency injection interface for the render pipeline.
// Extracted from RenderPipeline to enable test doubles.

import Metal
import MetalKit

// MARK: - Rendering

/// Abstraction over the Metal render pipeline.
///
/// Concrete implementation: `RenderPipeline`.
public protocol Rendering: AnyObject, MTKViewDelegate, Sendable {
    /// Replace the active render pipeline state (e.g., when switching presets).
    func setActivePipelineState(_ newState: MTLRenderPipelineState)
}
