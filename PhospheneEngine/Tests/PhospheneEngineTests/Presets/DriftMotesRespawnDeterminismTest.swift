// DriftMotesRespawnDeterminismTest — Verify the DM.2 hue-baking contract.
//
// Per-particle hue is sampled at emission time (kernel's respawn branch in
// `motes_update`) and never modified afterward. Three properties hold:
//
//   1. Within-life invariance — once baked, a particle's `colorRGB` is
//      bit-identical for the rest of its life. Stepping the kernel forward
//      without triggering a respawn does not perturb the colour.
//   2. Respawn does change hue — across many natural respawns under
//      non-zero stems, the per-particle hue distribution shows real
//      variation; the field is not painting every particle the same.
//   3. Cold-stems vs warm-stems variance — a 60-frame run with
//      `StemFeatures.zero` produces a tightly clustered hue distribution
//      (per-particle hash jitter around the warm-amber base); a 60-frame
//      run with realistic stems and a pitch sweep across the vocal
//      register produces a far wider distribution. The ratio is at least
//      2× — proves the D-019 blend is contributing real signal at warm
//      stems instead of being a numeric no-op.
//
// Structurally mirrors `DriftMotesNonFlockTest`: a single `MetalContext` +
// `ShaderLibrary` + `DriftMotesGeometry`, dispatched against synthesized
// `FeatureVector` / `StemFeatures` fixtures via the public `update(...)`
// API. Determinism comes from the kernel reading no wall-clock time and
// the geometry seeding particles from particle index alone.

import Testing
import Metal
@testable import Renderer
@testable import Shared

// MARK: - Helpers

private enum DMRespawnTestError: Error { case metalSetupFailed }

@discardableResult
private func dispatch(
    geometry: DriftMotesGeometry,
    features: FeatureVector,
    stems: StemFeatures,
    queue: MTLCommandQueue
) throws -> MTLCommandBuffer {
    guard let cmdBuf = queue.makeCommandBuffer() else {
        throw DMRespawnTestError.metalSetupFailed
    }
    geometry.update(features: features, stemFeatures: stems, commandBuffer: cmdBuf)
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()
    return cmdBuf
}

private func snapshot(buffer: MTLBuffer, count: Int) -> [Particle] {
    let ptr = buffer.contents().bindMemory(to: Particle.self, capacity: count)
    return (0..<count).map { ptr[$0] }
}

private func variance(_ values: [Float]) -> Float {
    guard !values.isEmpty else { return 0 }
    let mean = values.reduce(0, +) / Float(values.count)
    let sumSq = values.reduce(Float(0)) { acc, v in
        let d = v - mean
        return acc + d * d
    }
    return sumSq / Float(values.count)
}

private func makeWarmStems(pitchHz: Float, confidence: Float = 0.9) -> StemFeatures {
    var stems = StemFeatures.zero
    // Push every stem energy well above the D-019 0.06 saturation threshold
    // so the blend = 1.0 and the warm-stem hue source is fully selected.
    stems.vocalsEnergy = 0.6
    stems.drumsEnergy  = 0.5
    stems.bassEnergy   = 0.4
    stems.otherEnergy  = 0.5
    stems.vocalsPitchHz = pitchHz
    stems.vocalsPitchConfidence = confidence
    return stems
}

// MARK: - Test 1 — Within-life invariance.

@Test func test_driftMotes_withinLife_colorIsInvariant() throws {
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

    // Dispatch one frame so any particles with init `age` near `life`
    // respawn and pick up DM.2-baked hue. After that, age++ tracks frames
    // cleanly and we can identify slots that have NOT respawned.
    features.time = 0
    try dispatch(geometry: geometry, features: features, stems: .zero,
                 queue: ctx.commandQueue)

    let snapN = snapshot(buffer: geometry.particleBuffer, count: 800)

    // Step 30 more frames without changing fixtures.
    for frame in 1...30 {
        features.time = Float(frame) * dt
        try dispatch(geometry: geometry, features: features, stems: .zero,
                     queue: ctx.commandQueue)
    }

    let snapNplus30 = snapshot(buffer: geometry.particleBuffer, count: 800)

    // Identify slots where no respawn fired between captures: age strictly
    // increased by ~30 * dt with no reset to 0. Many slots qualify because
    // life is well-distributed across [lifeMin, lifeMin+lifeRange].
    var stableSlots = 0
    for i in 0..<800 {
        let ageBefore = snapN[i].age
        let ageAfter  = snapNplus30[i].age
        let elapsed   = Float(30) * dt
        // Allow a small numerical tolerance around 30 * dt.
        guard ageAfter > ageBefore,
              abs((ageAfter - ageBefore) - elapsed) < 1e-3 else {
            continue
        }
        stableSlots += 1
        // Color must be bit-identical across the life span.
        #expect(snapN[i].colorR == snapNplus30[i].colorR,
                "Slot \(i): colorR drifted within life — \(snapN[i].colorR) → \(snapNplus30[i].colorR)")
        #expect(snapN[i].colorG == snapNplus30[i].colorG)
        #expect(snapN[i].colorB == snapNplus30[i].colorB)
        #expect(snapN[i].colorA == snapNplus30[i].colorA)
    }
    #expect(stableSlots > 100,
            "Need at least 100 slots that did not respawn to make the within-life invariance check meaningful, found \(stableSlots).")
}

// MARK: - Test 2 — Respawn distribution under warm stems shows variation.

@Test func test_driftMotes_respawn_changesHueAcrossField() throws {
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

    // Sweep pitch over four octaves across 240 frames so successive respawns
    // bake hues spanning the full pitch→hue map. With life ∈ ~[5s, 15s],
    // 240 frames (4s) is enough for the steadily-aged slots seeded near
    // life to respawn at least once each.
    let frameCount = 240
    let pitchStartHz: Float = 110.0
    let pitchEndHz:   Float = 1760.0
    for frame in 0..<frameCount {
        let progress = Float(frame) / Float(frameCount - 1)
        let pitchHz = pitchStartHz * pow(pitchEndHz / pitchStartHz, progress)
        features.time = Float(frame) * dt
        try dispatch(geometry: geometry, features: features,
                     stems: makeWarmStems(pitchHz: pitchHz),
                     queue: ctx.commandQueue)
    }

    let snap = snapshot(buffer: geometry.particleBuffer, count: 800)
    let rValues = snap.map { $0.colorR }
    let gValues = snap.map { $0.colorG }
    let bValues = snap.map { $0.colorB }

    let rVar = variance(rValues)
    let gVar = variance(gValues)
    let bVar = variance(bValues)
    let combinedVar = rVar + gVar + bVar

    // Sanity: at least one channel must show meaningful variance. The DM.1
    // baseline (every particle warm-amber) has variance ≈ 0; D-019 + pitch
    // sweep should produce variance well above 1e-3.
    #expect(combinedVar > 1e-3,
            "Per-particle colour distribution is too tight — D-019 hue baking may not be firing. R-var=\(rVar), G-var=\(gVar), B-var=\(bVar)")
}

// MARK: - Test 3 — Warm-stems variance > 2× cold-stems variance.

@Test func test_driftMotes_warmStems_widerVarianceThanCold() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    func runFor(stemsProvider: (Int) -> StemFeatures) throws -> Float {
        let geometry = try DriftMotesGeometry(
            device: ctx.device,
            library: lib.library,
            particleCount: 800,
            pixelFormat: nil
        )
        let dt: Float = 1.0 / 60.0
        var features = FeatureVector.zero
        features.deltaTime = dt
        for frame in 0..<60 {
            features.time = Float(frame) * dt
            try dispatch(geometry: geometry, features: features,
                         stems: stemsProvider(frame), queue: ctx.commandQueue)
        }
        let snap = snapshot(buffer: geometry.particleBuffer, count: 800)
        let r = snap.map { $0.colorR }
        let g = snap.map { $0.colorG }
        let b = snap.map { $0.colorB }
        return variance(r) + variance(g) + variance(b)
    }

    // Cold stems: zero across the run. Hue source is the per-particle hash
    // jitter ± musicShift (which is also zero here).
    let coldVar = try runFor { _ in .zero }

    // Warm stems: pitch sweep over four octaves. Hue source is the
    // log-octave-wrap mapping in `dm_pitch_hue`.
    let warmVar = try runFor { frame in
        let progress = Float(frame) / 59.0
        let pitchHz: Float = 110.0 * pow(16.0, progress)
        return makeWarmStems(pitchHz: pitchHz)
    }

    let ratio = warmVar / max(coldVar, 1e-6)
    let diagnostic = "cold=\(coldVar), warm=\(warmVar), ratio=\(ratio)"
    #expect(ratio >= 2.0,
            "D-019 blend is not contributing real signal — variance ratio below the 2x floor. \(diagnostic)")
}
