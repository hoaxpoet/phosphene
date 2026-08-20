// ParticleGeometry — Protocol for per-preset particle compute+render pipelines.
//
// Particle presets are siblings, not subclasses. Each owns its own compute+render
// pipeline. The render loop schedules dispatch through this protocol; conformers
// hide their kernel names, vertex/fragment functions, and per-preset configuration.
//
// Murmuration's `ProceduralGeometry` is the first conformer (decay-rate-0 flock
// with hardcoded bird silhouette). Future particle presets define their own
// conformer rather than parameterizing a shared pipeline.
//
// See `docs/DECISIONS.md` D-097 and `CLAUDE.md` "Particle preset architecture".

import Metal
import Shared

// MARK: - ParticleGeometry

/// A particle compute+render pipeline owned by a single particle preset.
///
/// The render pipeline calls `update(...)` once per frame to integrate particle
/// state (compute pass) and `render(...)` once per frame to draw particles into
/// the active render encoder. Conformers own their own particle buffer, compute
/// pipeline state, and render pipeline state — the protocol does not expose any
/// of those internals.
///
/// The `Particle` struct memory layout (64 bytes, `packed_float4 color`) is shared
/// across all conformers and lives in `Particles.metal` / `ProceduralGeometry.swift`.
/// Conformers do not reinvent the struct layout.
///
/// Conformers must be reference types (the engine stores them by reference and
/// attaches/detaches them across queues). `Sendable` permits attach/detach from
/// any queue via `RenderPipeline.setParticleGeometry(_:)`.
public protocol ParticleGeometry: AnyObject, Sendable {

    /// Frame-budget governor gate (D-057): fraction of particles that receive
    /// compute updates each frame.
    ///
    /// Range `[0.0, 1.0]`. `1.0` = all particles updated. Set by
    /// `RenderPipeline.applyQualityLevel(_:)` when the budget governor downshifts
    /// past `QualityLevel.reducedParticles`. Conformers reduce dispatch count
    /// proportionally; undispatched particles keep their previous values.
    var activeParticleFraction: Float { get set }

    /// Compute pass: advance one frame of particle state.
    ///
    /// Encodes a compute command into the provided command buffer. The caller
    /// commits the command buffer; conformers must not commit it themselves.
    ///
    /// Called from `RenderPipeline.renderFrame(...)` once per frame, before any
    /// render pass executes.
    ///
    /// - Parameters:
    ///   - features: Current audio feature vector (FeatureVector).
    ///   - stemFeatures: Per-stem features. All-zero during the first ~10 s
    ///     warmup window; conformers must blend through `smoothstep(0.02, 0.06,
    ///     totalStemEnergy)` per D-019 if they read stem fields.
    ///   - commandBuffer: Active command buffer to encode the compute pass into.
    func update(
        features: FeatureVector,
        stemFeatures: StemFeatures,
        commandBuffer: MTLCommandBuffer
    )

    /// Size the geometry's own offscreen targets to the drawable, if it has any.
    ///
    /// Default no-op: most conformers draw straight into the caller's encoder and own no
    /// resolution-dependent textures, so they need nothing here. Conformers that DO keep an
    /// internal target (a trail, an accumulation buffer) must implement this, because a fixed
    /// internal size is not a smaller version of the picture — it is a BLURRIER one.
    ///
    /// **This exists because of a real defect (RICERCAR-WIRE.2).** `RicercarEchoGeometry`
    /// allocated its trail once at the configuration's default 1280×720 and never followed the
    /// drawable. Matt ran it at 3840×2160, and every thin calligraphic mark went through a 3×
    /// linear upscale — his M7 was *"looks good … blurry, should be substantially more clear and
    /// crisp."* The same fixed size also made the display pass's bloom radius, computed in TRAIL
    /// texels, 3× too wide on screen, and pinned the ground's aspect at 1.78 while the window was
    /// 1.13. One wrong number, three visible symptoms.
    ///
    /// Called once per frame immediately before ``update(features:stemFeatures:commandBuffer:)``,
    /// with the current drawable size. Implementations must be cheap when the size is unchanged.
    func ensureAllocated(width: Int, height: Int)

    /// Render pass: draw all particles into the active render encoder.
    ///
    /// Called from `RenderPipeline.drawDirect(...)` and
    /// `RenderPipeline.drawParticleMode(...)` after the preset's sky/backdrop
    /// fragment has been drawn. The encoder is already configured with the
    /// frame's clear/load actions; conformers do not begin or end the encoder.
    ///
    /// - Parameters:
    ///   - encoder: Active render command encoder owned by the render pipeline.
    ///   - features: Current audio feature vector (forwarded to vertex shaders
    ///     that may read it).
    func render(
        encoder: MTLRenderCommandEncoder,
        features: FeatureVector
    )
}

// MARK: - Default

public extension ParticleGeometry {

    /// No-op for the conformers that own no resolution-dependent target.
    func ensureAllocated(width: Int, height: Int) {}
}
