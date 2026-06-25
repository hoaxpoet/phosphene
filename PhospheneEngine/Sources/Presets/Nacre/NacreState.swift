// NacreState — per-frame comp-stage uniforms for the Nacre preset (NACRE.2, $$$ Royal
// - Mashup (431) uplift). Mirrors the SkeinState pattern (a per-preset MTLBuffer bound
// at the mv_warp comp/blit stage via setDirectPresetFragmentBuffer → bindCompStagePresetBuffer
// → fragment buffer(1)), but far simpler: one flat uniforms struct, no ring buffers.
//
// The signature look (radial-pulse + emboss→iridescence + smooth-Voronoi cells) is a
// DISPLAY-stage transform in `nacre_comp_fragment`, which has no direct FeatureVector
// access — so the time + audio/spectral drive it needs is precomputed here each frame.
//
// NACRE.2a: only `time` + a couple of known-safe deviation primitives are populated, to
// prove the plumbing end-to-end. NACRE.2b wires the full stem-instrument routes.

import Metal
import Shared
import os.log

private let nacreLog = Logger(subsystem: "com.phosphene.engine", category: "Nacre")

// MARK: - NacreUniformsGPU

/// Comp-stage uniforms — 16 floats = 64 bytes (all 4-byte floats, no SIMD-alignment
/// surprises; stride is exactly 64). Must match `struct NacreUniforms` in Nacre.metal
/// byte-for-byte.
struct NacreUniformsGPU {
    var time: Float = 0          // wall-clock-accumulated time (radial-pulse + slow palette phase)
    var coreEnergy: Float = 0    // vocals → central-core brightness (NACRE.2b)
    var coreShape: Float = 0     // waveform/overall energy → core form (NACRE.2b)
    var bassSwell: Float = 0     // bass deviation → cell swell (NACRE.2b)
    var drumsSparkle: Float = 0  // drums deviation → rim sparkle (NACRE.2b)
    var trebleGrain: Float = 0   // treble attack-rel → rim grain (NACRE.2b)
    var iriShift: Float = 0      // harmonic "other" → iridescence band shift (NACRE.2b)
    var hueDrive: Float = 0      // spectral centroid → iridescence hue base (NACRE.2b)
    var cellScale: Float = 0     // overall energy → Voronoi cell density (NACRE.2b)
    var pad0: Float = 0
    var pad1: Float = 0
    var pad2: Float = 0
    var pad3: Float = 0
    var pad4: Float = 0
    var pad5: Float = 0
    var pad6: Float = 0
}

// MARK: - NacreState

/// Owns the Nacre comp-stage uniforms buffer (bound at fragment slot 1 of the mv_warp
/// blit pass) and advances the slow time bed each frame.
///
/// Thread-safe: `tick()` and `nacreBuffer` can be accessed from any queue (the render-loop
/// tick hook calls `tick`; the encoder reads `nacreBuffer`). Mirrors `SkeinState`'s
/// `@unchecked Sendable` + `NSLock` idiom (sync callbacks alongside async API).
public final class NacreState: @unchecked Sendable {

    // MARK: - Properties

    /// GPU buffer bound at fragment buffer(1) of the comp/blit pass (via
    /// `setDirectPresetFragmentBuffer` → `bindCompStagePresetBuffer`).
    public let nacreBuffer: MTLBuffer

    private let lock = NSLock()
    private var accumTime: Float = 0
    private var uniforms = NacreUniformsGPU()

    // MARK: - Init

    /// Allocate the comp-stage uniforms buffer. Returns `nil` if allocation fails.
    public init?(device: MTLDevice) {
        let size = MemoryLayout<NacreUniformsGPU>.stride
        guard let buf = device.makeBuffer(length: size, options: .storageModeShared) else {
            nacreLog.error("NacreState: failed to allocate nacreBuffer (\(size) bytes)")
            return nil
        }
        nacreBuffer = buf
        writeToGPU()
    }

    // MARK: - Public API

    /// Update the comp-stage uniforms for one rendered frame, then flush to the GPU buffer.
    /// Call once per frame from the render-loop tick hook (`setMeshPresetTick`).
    ///
    /// NACRE.2a populates `time` + a couple of known-safe deviation primitives to validate
    /// the plumbing; NACRE.2b adds the full stem-instrument routes.
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        lock.withLock {
            // Wall-clock time bed (faithful to (431)'s time-driven palette/roam — alive at
            // silence). NACRE.2b may energy-weight if it reads mechanical (FA #33).
            accumTime += max(0, deltaTime)
            var next = NacreUniformsGPU()
            next.time = accumTime
            next.coreEnergy = max(0, features.midRel)   // 2a placeholder → 2b: stems.vocalsEnergy
            next.bassSwell  = max(0, features.bassDev)  // 2a placeholder → 2b: stems.bassEnergyDev
            uniforms = next
        }
        writeToGPU()
    }

    // MARK: - GPU Flush

    private func writeToGPU() {
        let snap = lock.withLock { uniforms }
        nacreBuffer.contents().bindMemory(to: NacreUniformsGPU.self, capacity: 1)[0] = snap
    }
}
