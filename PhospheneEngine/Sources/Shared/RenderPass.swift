// RenderPass — Render-graph pass types shared between the Presets and Renderer modules.
//
// A preset declares its render passes in the `"passes"` JSON sidecar key.
// `RenderPipeline.renderFrame` walks the active passes array and dispatches to the
// first pass whose subsystem is available, replacing the old priority-ordered boolean
// flag chain (useFeedback / useMeshShader / usePostProcess / useRayMarch / useICB).
//
// Adding a new capability requires only: a new `RenderPass` case, one `drawWithX`
// method in `RenderPipeline`, and one `case` in `applyPreset`. No more flag explosion.

// MARK: - RenderPass

/// A single render pass declared in a preset's JSON sidecar.
///
/// Presets declare their render passes as an ordered array under the `"passes"` JSON key:
///
/// ```json
/// { "passes": ["feedback", "particles"] }
/// { "passes": ["mesh_shader"] }
/// { "passes": ["ray_march", "post_process"] }
/// ```
///
/// `RenderPipeline.renderFrame` iterates the active passes array and executes the first
/// pass whose required subsystem is available, falling back to `.direct` if none match.
///
/// **Backward compatibility:** if no `"passes"` key is present in the JSON, `PresetDescriptor`
/// synthesises the array from the legacy `use_feedback`, `use_particles`, `use_mesh_shader`,
/// `use_post_process`, and `use_ray_march` boolean fields.
public enum RenderPass: String, Codable, Sendable, CaseIterable {

    /// Standard fullscreen fragment shader rendered directly to the drawable.
    /// The default and fallback path — requires no subsystem setup.
    case direct

    /// Milkdrop-style feedback loop: warp previous frame → additive composite → blit.
    /// Requires `FeedbackParams` to be set and feedback textures to be allocated.
    case feedback

    /// GPU compute particle system rendered on top of the preset each frame.
    /// Always appears alongside `feedback` — drives particle-mode vs. surface-mode
    /// selection within `drawWithFeedback`.
    case particles

    /// Metal mesh shader path (M3+) or vertex-fallback path (M1/M2).
    /// Requires a `MeshGenerator` to be attached to the pipeline.
    case meshShader = "mesh_shader"

    /// HDR post-process chain: scene → bright pass → Gaussian bloom → ACES → drawable.
    /// Stand-alone: requires a `PostProcessChain`.
    /// Combined with `rayMarch`: the ray march pipeline uses the chain for bloom.
    case postProcess = "post_process"

    /// Deferred ray march: G-buffer → PBR lighting → ACES/bloom composite.
    /// Requires a `RayMarchPipeline` and a compiled G-buffer pipeline state.
    /// Optionally paired with `postProcess` for bloom.
    case rayMarch = "ray_march"

    /// GPU-driven indirect command buffer: compute-populated draw commands.
    /// Requires `IndirectCommandBufferState` to be attached.
    case icb

    /// Screen-space global illumination pass (Increment 3.17).
    /// Approximates short-range diffuse indirect light bounces using the G-buffer.
    /// Must appear alongside `rayMarch` — inserts between the lighting pass and the
    /// composite pass in `RayMarchPipeline.render(...)`.
    case ssgi
}
