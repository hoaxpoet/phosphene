// SkeinStructureSignalTests — Skein.ENGINE.3 (D-151).
//
// Prove the live `StructuralPrediction` signal reaches `SkeinState.tick` end-to-end through the
// gated `RenderPipeline` bridge, byte-identically for every other preset (the store defaults to
// `.none` and only Skein reads it). There is NO visual bias in ENGINE.3 — that is Skein.5; these
// tests prove the SIGNAL arrives and that a section-boundary crossing is observable.
//
// FA #66 (verify the live path, not just a unit): the tests drive the SAME store and the SAME
// `meshPresetTick` invocation indirection the live render loop uses —
//   • `RenderPipeline.setStructuralPrediction(_:)` / `.latestStructuralPrediction` on a REAL pipeline
//     (the analysis-queue write / render-thread read bridge — `VisualizerEngine+Audio.swift`);
//   • the stored `meshPresetTick` closure, invoked exactly as `RenderPipeline+Draw.swift:120` does
//     (`meshPresetTickLock.withLock { meshPresetTick }?(features, stems)`);
//   • `SkeinState.tick(deltaTime:features:stems:structure:)` ingestion.
// The only replicated piece is the app-layer closure BODY (the 2-line
// `state.tick(..., structure: pipeline.latestStructuralPrediction)` glue in
// `VisualizerEngine+Presets.swift`, which lives in the app target and is verified to compile by the
// app build); the closure here is kept byte-identical to that production wiring.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Skein structural-section signal plumbing (ENGINE.3)")
struct SkeinStructureSignalTests {

    enum HarnessError: Error { case bufferAllocationFailed }

    /// Build a real `RenderPipeline` (the bridge store lives on it). Mirrors
    /// `CSP3DataPlumbingTests.makePipeline` — the established stem-bridge round-trip precedent.
    private static func makePipeline() throws -> RenderPipeline {
        let context = try MetalContext()
        let library = try ShaderLibrary(context: context)
        let stride = MemoryLayout<Float>.stride
        guard let fft = context.makeSharedBuffer(length: 512 * stride),
              let wave = context.makeSharedBuffer(length: 2048 * stride) else {
            throw HarnessError.bufferAllocationFailed
        }
        return try RenderPipeline(context: context, shaderLibrary: library,
                                  fftBuffer: fft, waveformBuffer: wave)
    }

    /// Invoke the stored mesh-preset tick exactly as the render loop does (RenderPipeline+Draw:120).
    private func invokeTick(_ p: RenderPipeline, _ features: FeatureVector, _ stems: StemFeatures) {
        let tick = p.meshPresetTickLock.withLock { p.meshPresetTick }
        tick?(features, stems)
    }

    /// Wire the Skein tick closure BYTE-IDENTICALLY to the production wiring
    /// (`VisualizerEngine+Presets.swift` Skein branch): read the structure from the gated bridge,
    /// pass it into `tick`, push the wetness decay. Returns nothing — the closure is stored on `p`.
    private func wireSkeinClosure(_ p: RenderPipeline, _ skein: SkeinState) {
        let renderPipeline = p
        p.setMeshPresetTick { [weak skein, weak renderPipeline] features, stems in
            guard let skein else { return }
            skein.tick(deltaTime: features.deltaTime, features: features, stems: stems,
                       structure: renderPipeline?.latestStructuralPrediction ?? .none)
            renderPipeline?.setMVWarpWetnessDecay(skein.wetnessDecay)
        }
    }

    // MARK: - 1. The gated bridge store

    @Test("RenderPipeline.setStructuralPrediction round-trips; defaults to .none (inert for all presets)")
    func test_bridgeStore_roundTripsAndDefaultsNone() throws {
        let pipeline = try Self.makePipeline()
        // Inert default — this is the byte-identical guarantee for every non-Skein preset.
        #expect(pipeline.latestStructuralPrediction == StructuralPrediction.none)

        let p = StructuralPrediction(sectionIndex: 3, sectionStartTime: 12.5,
                                     predictedNextBoundary: 20.0, confidence: 0.8)
        pipeline.setStructuralPrediction(p)
        #expect(pipeline.latestStructuralPrediction == p,
                "bridge store did not round-trip: \(pipeline.latestStructuralPrediction)")

        // The preset-switch reset (mirrors setMVWarpWetnessDecay(1.0) in the applyPreset teardown).
        pipeline.setStructuralPrediction(.none)
        #expect(pipeline.latestStructuralPrediction == StructuralPrediction.none)
    }

    // MARK: - 2. The live path — bridge → tick closure → SkeinState

    @Test("Live path: a StructuralPrediction set on the pipeline reaches SkeinState via the tick closure")
    func test_livePath_structureReachesSkeinState() throws {
        let pipeline = try Self.makePipeline()
        guard let skein = SkeinState(device: pipeline.context.device, seed: 0) else {
            Issue.record("SkeinState allocation failed"); return
        }
        wireSkeinClosure(pipeline, skein)

        // Analysis-side write, then invoke the stored tick the way the render loop does.
        pipeline.setStructuralPrediction(StructuralPrediction(sectionIndex: 2, sectionStartTime: 8,
                                                              predictedNextBoundary: 16, confidence: 0.7))
        let fv = FeatureVector(time: 0, deltaTime: 1.0 / 60.0, aspectRatio: 1.0)
        invokeTick(pipeline, fv, .zero)   // structure ingest is unconditional → silence stems are fine

        #expect(skein.currentSectionIndex == 2,
                "section index did not reach SkeinState: \(skein.currentSectionIndex)")
        #expect(abs(skein.sectionConfidence - 0.7) < 1e-5,
                "confidence did not reach SkeinState: \(skein.sectionConfidence)")
        #expect(abs(skein.currentSectionStartTime - 8) < 1e-5,
                "section start time did not reach SkeinState: \(skein.currentSectionStartTime)")
    }

    // MARK: - 3. The one-frame boundary flag

    @Test("A section-index increment raises the boundary flag for exactly one frame (live path)")
    func test_boundaryFlag_firesOneFrameOnSectionChange() throws {
        let pipeline = try Self.makePipeline()
        guard let skein = SkeinState(device: pipeline.context.device, seed: 0) else {
            Issue.record("SkeinState allocation failed"); return
        }
        wireSkeinClosure(pipeline, skein)
        let dt: Float = 1.0 / 60.0
        func tick(section: UInt32, frame: Int) {
            pipeline.setStructuralPrediction(StructuralPrediction(sectionIndex: section,
                                                                  sectionStartTime: Float(frame) * dt,
                                                                  confidence: 0.9))
            invokeTick(pipeline, FeatureVector(time: Float(frame) * dt, deltaTime: dt, aspectRatio: 1.0), .zero)
        }

        // Frame 0: first observation re-baselines — NOT a crossing.
        tick(section: 0, frame: 0)
        #expect(!skein.didCrossSectionBoundaryThisFrame, "first observation should not be a boundary")
        #expect(skein.currentSectionIndex == 0)

        // Frame 1: section increments → boundary fires.
        tick(section: 1, frame: 1)
        #expect(skein.didCrossSectionBoundaryThisFrame, "section 0→1 should raise the boundary flag")
        #expect(skein.currentSectionIndex == 1)

        // Frame 2: same section → flag clears (one-frame).
        tick(section: 1, frame: 2)
        #expect(!skein.didCrossSectionBoundaryThisFrame, "boundary flag must be one-frame (cleared on the next tick)")
        #expect(skein.currentSectionIndex == 1)

        // Frame 3: another increment → fires again.
        tick(section: 2, frame: 3)
        #expect(skein.didCrossSectionBoundaryThisFrame, "section 1→2 should raise the boundary flag")
        #expect(skein.currentSectionIndex == 2)
    }

    // MARK: - 4. reseed clears the structural-section tracking

    @Test("reseed (track change) clears the section tracking — no spurious boundary on a new track")
    func test_reseed_clearsStructureTracking() throws {
        let context = try MetalContext()
        guard let skein = SkeinState(device: context.device, seed: 0) else {
            Issue.record("SkeinState allocation failed"); return
        }
        let dt: Float = 1.0 / 60.0
        let fv = FeatureVector(time: 0, deltaTime: dt, aspectRatio: 1.0)

        // Advance the old track to section 5 (direct tick — this is a SkeinState-only concern).
        skein.tick(deltaTime: dt, features: fv, stems: .zero,
                   structure: StructuralPrediction(sectionIndex: 5, sectionStartTime: 40, confidence: 0.9))
        #expect(skein.currentSectionIndex == 5)

        // Track change: reseed must clear the section tracking back to the baseline.
        skein.reseed(99)
        #expect(skein.currentSectionIndex == 0, "reseed did not clear the section index")
        #expect(!skein.didCrossSectionBoundaryThisFrame)

        // The new track's first observation (section 0) must NOT report a spurious crossing — even
        // though the OLD track ended on section 5, reseed re-baselined `structInitialized`.
        skein.tick(deltaTime: dt, features: fv, stems: .zero,
                   structure: StructuralPrediction(sectionIndex: 0, sectionStartTime: 0, confidence: 0.1))
        #expect(!skein.didCrossSectionBoundaryThisFrame,
                "new track's first section must re-baseline, not fire a boundary")
        #expect(skein.currentSectionIndex == 0)
    }
}
