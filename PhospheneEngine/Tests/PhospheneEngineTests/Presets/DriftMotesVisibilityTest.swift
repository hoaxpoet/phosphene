// DriftMotesVisibilityTest — DM.3.1 spawn-Y geometry regression gate.
//
// M7 review of session `2026-05-08T22-01-07Z` showed that Drift Motes
// particles depleted to zero within ~10 seconds of preset start
// (empirically confirmed by sampling video.mp4 at engine t=86s, 96s,
// 141s, 201s — all but the first showed zero visible particles).
//
// Root cause: `dm_sample_emission_position` respawns particles at world-Y
// in [5.6, 8.0] but the vertex shader maps world-Y to clip-Y via
// `clipY = position.y * 2.2 / 8.0`, so visible Y stops at world-Y = 3.64.
// Respawned particles spawn 1.96–4.36 world-units ABOVE the visible top.
// Wind drift in y is only 0.059 m/s (wind = (-1, -0.2, 0) normalised ×
// 0.3); particles take 33–74 seconds to enter the visible region after
// respawn, but their lifetime is 5–9 seconds. Most particles die before
// they're ever visible. Steady-state visible count drops to zero.
//
// This test asserts the FIELD STAYS POPULATED across a 30-second
// simulated window. It samples visible-particle count at 1-second
// intervals from t=10s onward (post-init transient — initial uniform
// seed has plenty of visible particles for the first ~5–10 seconds; the
// failure mode is steady-state depletion AFTER the init clears).
//
// Before the fix: count drops to single digits or zero by t=15s.
// After the fix: count stabilises at >= 50 visible particles per frame.

import Testing
import Metal
@testable import Renderer
@testable import Shared

private enum DMVisTestError: Error { case metalSetupFailed }

@discardableResult
private func dispatchVis(
    geometry: DriftMotesGeometry,
    features: FeatureVector,
    stems: StemFeatures,
    queue: MTLCommandQueue
) throws -> MTLCommandBuffer {
    guard let cmdBuf = queue.makeCommandBuffer() else {
        throw DMVisTestError.metalSetupFailed
    }
    geometry.update(features: features, stemFeatures: stems, commandBuffer: cmdBuf)
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()
    return cmdBuf
}

/// Count particles whose clip-space position is inside [-1, +1]² AND that
/// are alive (age < life). Mirrors the vertex shader's visibility logic:
///   `clipX = positionX * 2.2 / 8.0`
///   `clipY = positionY * 2.2 / 8.0`
///   `pointSize = (life > 0 && age < life) ? 6.0 : 0.0` → 0-size = invisible
private func countVisible(buffer: MTLBuffer, count: Int) -> Int {
    let ptr = buffer.contents().bindMemory(to: Particle.self, capacity: count)
    let scale: Float = 2.2 / 8.0
    var visible = 0
    for i in 0..<count {
        let p = ptr[i]
        guard p.life > 0, p.age < p.life else { continue }
        let cx = p.positionX * scale
        let cy = p.positionY * scale
        if abs(cx) <= 1.0 && abs(cy) <= 1.0 {
            visible += 1
        }
    }
    return visible
}

@Test func test_driftMotes_visibleParticleCount_staysAboveFloor() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let geometry = try DriftMotesGeometry(
        device: ctx.device,
        library: lib.library,
        particleCount: 800,
        pixelFormat: nil
    )

    let dt: Float = 1.0 / 60.0
    var features = FeatureVector.zero
    features.deltaTime = dt

    // Run 30 simulated seconds. Sample visible count at t = 10, 11, …, 29 s.
    // Pre-t=10 is init transient (uniform-cube seed has ~160 particles
    // visible from frame 0; the failure mode is depletion AFTER the init
    // clears). Post-t=10 should be steady state.
    var samples: [Int] = []
    for frame in 0..<1800 {
        features.time = Float(frame) * dt
        try dispatchVis(geometry: geometry, features: features,
                        stems: .zero, queue: ctx.commandQueue)
        if frame >= 600 && frame % 60 == 0 {
            samples.append(countVisible(
                buffer: geometry.particleBuffer, count: 800))
        }
    }

    let minVisible = samples.min() ?? 0
    let maxVisible = samples.max() ?? 0
    let avgVisible = samples.reduce(0, +) / max(samples.count, 1)
    let diagnostic = "samples (t=10s..29s, 1s intervals): \(samples)  min=\(minVisible)  max=\(maxVisible)  avg=\(avgVisible)"
    // Print to stdout so re-running the test surfaces the actual steady-state
    // count without needing #expect to fire. Useful when retuning spawn-pad
    // constants or adjusting the kEmissionRateGain coefficient.
    print("[DriftMotesVisibility] \(diagnostic)")

    // Floor: ≥ 300 visible particles at every sample point. DM.3.3
    // retune: with the new full-width spawn + downward wind + 20–30 s
    // lifetime, steady state should be ~600–700 visible (out of 800
    // total — most of each particle's life is spent in view). The
    // 300 floor catches a regression where the field collapses back
    // to a corner cluster (DM.3.1's failure mode that M7 surfaced on
    // 2026-05-11) or where the spawn distribution gets too tight.
    // Pre-DM.3.3 floor was 50; bumped because the field is genuinely
    // more abundant now and 50 wouldn't catch a partial-regression.
    #expect(minVisible >= 300,
            "Drift Motes field depleting — visible particle count below 300-floor. \(diagnostic)")
}
