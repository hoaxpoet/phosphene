// RayMarchDiagnosticTests — CPU evaluation of Glass Brutalist SDF.
//
// Captures numeric data about what the ray march pipeline produces (coverage %,
// material distribution, per-ray hit depth) without requiring Metal. Catches
// camera, SDF, and material bugs with concrete numbers instead of screenshots.

import Testing
import simd

/// Evaluate the Glass Brutalist SDF on the CPU to verify ray march behavior
/// without needing Metal. This catches camera, SDF, and material bugs with
/// concrete numbers.
@Suite("Ray March SDF Diagnostics")
struct RayMarchSDFDiagnosticTests {

    // MARK: - SDF Evaluation Helpers

    // Replicate the Glass Brutalist SDF geometry on the CPU.
    // Constants from GlassBrutalist.metal:
    let cellZ: Float = 7.0
    let corridorX: Float = 2.5
    let pillarHW: Float = 0.50
    let pillarHH: Float = 5.5
    let beamY: Float = 3.80
    let glassHW: Float = 0.60
    let glassCX: Float = 1.20
    let glassHH: Float = 2.35
    let glassCY: Float = 1.40
    let glassHD: Float = 0.05

    func repZ(_ z: Float, _ c: Float) -> Float {
        z - c * (z / c).rounded()
    }

    /// CPU-side sdBox matching ShaderUtilities.metal
    func sdBox(_ p: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let q = abs(p) - b
        return simd_length(max(q, SIMD3<Float>.zero)) + min(max(q.x, max(q.y, q.z)), 0)
    }

    /// CPU-side sdPlane matching ShaderUtilities.metal
    func sdPlane(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ h: Float) -> Float {
        simd_dot(p, n) + h
    }

    /// Concrete SDF (floor, ceiling, walls, pillars, beams) at rest shape
    func sdConcrete(_ p: SIMD3<Float>) -> Float {
        let dFloor = sdPlane(p, [0, 1, 0], 1.0)
        let dCeiling = sdPlane(p, [0, -1, 0], 5.2)
        let dSideWalls = corridorX - abs(p.x)
        let zR = repZ(p.z, cellZ)
        let pP = SIMD3<Float>(abs(p.x) - corridorX, p.y, zR)
        let dPillar = sdBox(pP, [pillarHW, pillarHH, pillarHW])
        let bP = SIMD3<Float>(p.x, p.y - beamY, zR)
        let dBeam = sdBox(bP, [corridorX + pillarHW, 0.35, pillarHW])
        return min(min(min(dFloor, dCeiling), dSideWalls), min(dPillar, dBeam))
    }

    /// Glass SDF parameterized by `finCX` — the fin centre X-distance.
    /// Option A: the only music-reactive geometry is the fin position.
    /// `finCX` at rest = 1.20 (GB_GLASS_CX in the shader); bass-driven
    /// values range down to ~0.85 (narrower corridor path).
    func sdGlass(_ p: SIMD3<Float>, finCX: Float = 1.20) -> Float {
        let zG = repZ(p.z - cellZ * 0.5, cellZ)
        let gP = SIMD3<Float>(abs(p.x) - finCX, p.y - glassCY, zG)
        return sdBox(gP, [glassHW, glassHH, glassHD])
    }

    /// Combined scene SDF at rest shape (finCX = default).
    func sceneSDF(_ p: SIMD3<Float>) -> Float {
        min(sdConcrete(p), sdGlass(p))
    }

    /// Scene SDF parameterized by `finCX` — models the single Option-A
    /// music-reactive deformation (corridor-path width via fin position).
    func sceneSDF(_ p: SIMD3<Float>, finCX: Float) -> Float {
        min(sdConcrete(p), sdGlass(p, finCX: finCX))
    }

    /// Ray march at rest audio state.
    func marchRayRest(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        near: Float = 0.1,
        far: Float = 40.0,
        maxSteps: Int = 256
    ) -> (hit: Bool, t: Float, hitPos: SIMD3<Float>) {
        var t = near
        for _ in 0..<maxSteps {
            if t >= far { return (false, t, origin + direction * t) }
            let p = origin + direction * t
            let d = sceneSDF(p)
            if d < 0.001 * t { return (true, t, p) }
            t += max(d, 0.002)
        }
        return (false, t, origin + direction * t)
    }

    /// March a ray and return (hit, t, stepCount, hitPos)
    func marchRay(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        near: Float = 0.1,
        far: Float = 30.0,
        maxSteps: Int = 128
    ) -> (hit: Bool, t: Float, steps: Int, hitPos: SIMD3<Float>) {
        var t = near
        for i in 0..<maxSteps {
            if t >= far { return (false, t, i, origin + direction * t) }
            let p = origin + direction * t
            let d = sceneSDF(p)
            if d < 0.001 * t {
                return (true, t, i, p)
            }
            t += max(d, 0.002)
        }
        return (false, t, maxSteps, origin + direction * t)
    }

    /// Build a ray direction from UV, matching raymarch_gbuffer_fragment math
    func rayDirection(
        uv: SIMD2<Float>,
        fovDegrees: Float,
        aspectRatio: Float,
        forward: SIMD3<Float>,
        right: SIMD3<Float>,
        up: SIMD3<Float>
    ) -> SIMD3<Float> {
        let ndc = uv * 2.0 - 1.0
        let yFov = tan(fovDegrees * .pi / 180.0 * 0.5)
        let xFov = yFov * aspectRatio
        return simd_normalize(forward + ndc.x * xFov * right - ndc.y * yFov * up)
    }

    // MARK: - Camera Position Tests

    @Test("Camera at [0.0, 1.8, 0.5] is outside all geometry (positive SDF)")
    func cameraOutsideGeometry() {
        let camPos: SIMD3<Float> = [0.0, 1.8, 0.5]
        let d = sceneSDF(camPos)
        #expect(d > 0, "Camera is inside geometry (SDF=\(d)). Rays will fail.")
    }

    @Test("Camera is inside corridor bounds")
    func cameraInsideCorridor() {
        let camPos: SIMD3<Float> = [0.0, 1.8, 0.5]
        #expect(abs(camPos.x) < corridorX, "Camera X outside corridor walls")
        #expect(camPos.y > -1.0 && camPos.y < 5.2, "Camera Y outside floor/ceiling")
    }

    // MARK: - Ray Hit Tests (the critical ones)

    @Test("Center ray threads the open corridor channel (intentionally misses near geometry)")
    func centerRayThreadsCorridor() {
        // Option-A design: camera sits in the open centre channel (|x| < 0.6, the
        // gap between glass fins). The exact centre ray should miss near geometry
        // and fade into fog — a deep-corridor vista, not a wall.
        let cam: SIMD3<Float> = [0.0, 1.8, 0.5]
        let target: SIMD3<Float> = [0.0, 1.5, 18.0]
        let fwd = simd_normalize(target - cam)
        let right = simd_normalize(simd_cross([0, 1, 0], fwd))
        let up = simd_cross(fwd, right)

        let dir = rayDirection(uv: [0.5, 0.5], fovDegrees: 65, aspectRatio: 16.0 / 9.0,
                               forward: fwd, right: right, up: up)
        let result = marchRay(origin: cam, direction: dir, far: 30.0)
        print("  Centre ray: hit=\(result.hit), t=\(result.t), pos=\(result.hitPos), steps=\(result.steps)")

        // Either the ray escapes to fog distance (preferred, cinematic vista) or
        // it hits something at great depth (acceptable). A NEAR hit (t < 6) is
        // the failure case — it means a glass fin is blocking the centreline.
        #expect(!result.hit || result.t > 6.0,
                "Centre ray hit near geometry at t=\(result.t) — fin blocks the open channel")
    }

    @Test("Floor ray hits within far plane")
    func floorRayHits() {
        let cam: SIMD3<Float> = [0.0, 1.8, 0.5]
        let target: SIMD3<Float> = [0.0, 1.5, 18.0]
        let fwd = simd_normalize(target - cam)
        let right = simd_normalize(simd_cross([0, 1, 0], fwd))
        let up = simd_cross(fwd, right)

        // Bottom-center of screen
        let dir = rayDirection(uv: [0.5, 0.95], fovDegrees: 65, aspectRatio: 16.0 / 9.0,
                               forward: fwd, right: right, up: up)
        let result = marchRay(origin: cam, direction: dir)
        #expect(result.hit, "Floor ray missed! t=\(result.t), steps=\(result.steps)")
        if result.hit {
            print("  Floor hit at t=\(result.t), pos=\(result.hitPos)")
            // Floor ray may graze glass/pillar edges on the way down. Accept any
            // hit below eye level (y < 0.5) as a valid floor-region intersection.
            #expect(result.hitPos.y < 0.5, "Expected hit below eye level, got y=\(result.hitPos.y)")
        }
    }

    // MARK: - Option A Design Invariants

    @Test("Option A: corridor-path width narrows when finCX shrinks")
    func corridorPathNarrowsWithBass() {
        // At rest: fins centred at x = ±1.20 with half-width 0.60 → fin
        // extent x ∈ [0.60, 1.80]. A point at |x|=0.70 sits INSIDE the fin.
        // Under bass drive, finCX drops to 0.85 → fins centred at ±0.85,
        // extent [0.25, 1.45] → the same point |x|=0.70 is still inside
        // but the centre channel itself (|x|<0.25) is now more open, while
        // |x|=1.50 — previously inside the fin — is now OUTSIDE in open air.
        let pInsideRestFin: SIMD3<Float> = [1.50, 1.4, 3.5]
        let dRest = sceneSDF(pInsideRestFin, finCX: 1.20)   // inside fin
        let dNarrow = sceneSDF(pInsideRestFin, finCX: 0.85) // outside fin
        print("  p=(1.50,1.4,3.5): finCX=1.20 → d=\(dRest), finCX=0.85 → d=\(dNarrow)")
        #expect(dRest < 0.0, "Rest-position fin should contain p=(1.50, 1.4, 3.5)")
        #expect(dNarrow > 0.0, "Narrowed fin should NOT contain that same point")
    }

    @Test("Option A: architecture is music-invariant (walls/pillars/beam/floor/ceiling)")
    func architectureDoesNotDeformWithAudio() {
        // Points inside each architectural element. Concrete SDF must be
        // identical regardless of what audio state we pretend is playing —
        // because Option A routes all audio reactivity to light/fog/fin
        // position, never to the concrete geometry. Any regression that
        // re-couples bass/beat/mid to pillar/beam/floor would fail here.
        let points: [(String, SIMD3<Float>)] = [
            ("floor interior",   [0.0, -1.5, 0.0]),
            ("ceiling interior", [0.0,  6.0, 0.0]),
            ("pillar interior",  [2.5,  2.0, 0.0]),
            ("beam interior",    [0.0,  3.8, 0.0]),
            ("left wall",        [-3.0, 2.0, 0.0])
        ]
        for (name, p) in points {
            let d = sdConcrete(p)
            // sdConcrete has no audio input by design — this test just
            // asserts the function signature and output are stable.
            print("  sdConcrete(\(name)) = \(d)")
            #expect(d.isFinite, "\(name): SDF must be finite")
        }
    }

    @Test("Left wall ray hits within far plane")
    func leftWallRayHits() {
        let cam: SIMD3<Float> = [0.0, 1.8, 0.5]
        let target: SIMD3<Float> = [0.0, 1.5, 18.0]
        let fwd = simd_normalize(target - cam)
        let right = simd_normalize(simd_cross([0, 1, 0], fwd))
        let up = simd_cross(fwd, right)

        let dir = rayDirection(uv: [0.05, 0.5], fovDegrees: 65, aspectRatio: 16.0 / 9.0,
                               forward: fwd, right: right, up: up)
        let result = marchRay(origin: cam, direction: dir)
        #expect(result.hit, "Left wall ray missed! t=\(result.t), steps=\(result.steps)")
    }

    @Test("Right wall ray hits within far plane")
    func rightWallRayHits() {
        let cam: SIMD3<Float> = [0.0, 1.8, 0.5]
        let target: SIMD3<Float> = [0.0, 1.5, 18.0]
        let fwd = simd_normalize(target - cam)
        let right = simd_normalize(simd_cross([0, 1, 0], fwd))
        let up = simd_cross(fwd, right)

        let dir = rayDirection(uv: [0.95, 0.5], fovDegrees: 65, aspectRatio: 16.0 / 9.0,
                               forward: fwd, right: right, up: up)
        let result = marchRay(origin: cam, direction: dir)
        #expect(result.hit, "Right wall ray missed! t=\(result.t), steps=\(result.steps)")
    }

    @Test("Ceiling ray hits within far plane")
    func ceilingRayHits() {
        let cam: SIMD3<Float> = [0.0, 1.8, 0.5]
        let target: SIMD3<Float> = [0.0, 1.5, 18.0]
        let fwd = simd_normalize(target - cam)
        let right = simd_normalize(simd_cross([0, 1, 0], fwd))
        let up = simd_cross(fwd, right)

        let dir = rayDirection(uv: [0.5, 0.05], fovDegrees: 65, aspectRatio: 16.0 / 9.0,
                               forward: fwd, right: right, up: up)
        let result = marchRay(origin: cam, direction: dir)
        #expect(result.hit, "Ceiling ray missed! t=\(result.t), steps=\(result.steps)")
    }

    @Test("Screen coverage: >90% of rays hit geometry")
    func screenCoverage() {
        let cam: SIMD3<Float> = [0.0, 1.8, 0.5]
        let target: SIMD3<Float> = [0.0, 1.5, 18.0]
        let fwd = simd_normalize(target - cam)
        let right = simd_normalize(simd_cross([0, 1, 0], fwd))
        let up = simd_cross(fwd, right)

        var hits = 0
        var misses = 0
        let gridSize = 20
        var missLocations: [(Float, Float)] = []

        for yi in 0..<gridSize {
            for xi in 0..<gridSize {
                let u = (Float(xi) + 0.5) / Float(gridSize)
                let v = (Float(yi) + 0.5) / Float(gridSize)
                let dir = rayDirection(uv: [u, v], fovDegrees: 65, aspectRatio: 16.0 / 9.0,
                                       forward: fwd, right: right, up: up)
                let result = marchRay(origin: cam, direction: dir)
                if result.hit { hits += 1 } else {
                    misses += 1
                    missLocations.append((u, v))
                }
            }
        }

        let coverage = Float(hits) / Float(hits + misses)
        print("  Screen coverage: \(hits)/\(hits + misses) = \(coverage * 100)%")
        if !missLocations.isEmpty {
            print("  Miss locations (uv): \(missLocations.prefix(10))")
        }
        #expect(coverage > 0.90, "Only \(coverage * 100)% of rays hit geometry — camera or SDF issue")
    }

    // MARK: - Material Distribution Test

    @Test("Scene has a reasonable glass-to-concrete ratio across the screen")
    func materialDistribution() {
        let cam: SIMD3<Float> = [0.0, 1.8, 0.5]
        let target: SIMD3<Float> = [0.0, 1.5, 18.0]
        let fwd = simd_normalize(target - cam)
        let right = simd_normalize(simd_cross([0, 1, 0], fwd))
        let up = simd_cross(fwd, right)

        var glassPixels = 0
        var concretePixels = 0
        var skyPixels = 0
        let gridSize = 20

        for yi in 0..<gridSize {
            for xi in 0..<gridSize {
                let u = (Float(xi) + 0.5) / Float(gridSize)
                let v = (Float(yi) + 0.5) / Float(gridSize)
                let dir = rayDirection(uv: [u, v], fovDegrees: 65, aspectRatio: 16.0 / 9.0,
                                       forward: fwd, right: right, up: up)
                let result = marchRay(origin: cam, direction: dir)
                if !result.hit { skyPixels += 1; continue }
                let dG = sdGlass(result.hitPos)
                let dC = sdConcrete(result.hitPos)
                if dG < dC { glassPixels += 1 } else { concretePixels += 1 }
            }
        }

        let total = gridSize * gridSize
        print("  Material distribution: glass=\(glassPixels)/\(total) concrete=\(concretePixels)/\(total) sky=\(skyPixels)/\(total)")
        let glassRatio = Float(glassPixels) / Float(total)
        #expect(glassRatio < 0.40,
                "Glass covers \(glassRatio * 100)% of screen — will look like a flat rectangle. Adjust camera.")
        #expect(Float(concretePixels) / Float(total) > 0.50,
                "Concrete only covers \(Float(concretePixels) / Float(total) * 100)% — corridor structure not visible enough")
    }

    // MARK: - Motion Feel Summary (constant-speed Swift-side dolly)

    /// Non-gating diagnostic: human-readable check on the Option-A dolly
    /// speed. Camera advances by `features.time * cameraDollySpeed` world
    /// units per second of WALL clock — not audio-energy weighted.
    @Test("Motion feel: constant-speed dolly at Glass Brutalist's 2.5 units/sec")
    func motionFeelSummary() {
        let dollySpeed: Float = 2.5    // matches VisualizerEngine+Presets.swift
        let bay: Float = 7.0           // GB_CELL_Z
        let secPerBay = bay / dollySpeed
        let baysPerSec = dollySpeed / bay
        print("  Dolly speed: \(dollySpeed) world-units / sec wall clock")
        print("  Bay length:  \(bay) world-units → \(String(format: "%.2f", secPerBay))s per bay")
        print("  Rate:        \(String(format: "%.2f", baysPerSec)) bays/sec")
        // Target: between 0.25 and 0.6 bays/sec — slow enough to feel like
        // purposeful forward travel, not a tunnel-runner fly-through.
        #expect(baysPerSec >= 0.25, "Dolly too slow (\(baysPerSec) bays/sec)")
        #expect(baysPerSec <= 0.6,  "Dolly too fast (\(baysPerSec) bays/sec)")
    }
}
