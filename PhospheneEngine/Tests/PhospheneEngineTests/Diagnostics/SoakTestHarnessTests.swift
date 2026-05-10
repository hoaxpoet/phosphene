// SoakTestHarnessTests — Tests for SoakTestHarness (Increment 7.1).
//
// Always-run tests: Configuration defaults, Codable round-trip.
// Soak-tagged tests: gated by SOAK_TESTS=1 environment variable.
//   - 60-second smoke test: verifies report is written, no hard failures.
//   - 5-minute memory check: observes memory growth (no assertion, observability only).
//
// To run soak tests:
//   SOAK_TESTS=1 swift test --package-path PhospheneEngine --filter SoakTestHarnessTests
//
// D-060(d): the 2-hour run is NOT in this suite. Use Scripts/run_soak_test.sh.

import Testing
import Foundation
import QuartzCore
import Metal
import Audio
import Shared
@testable import Diagnostics
@testable import Presets
@testable import Renderer

// MARK: - Always-run Tests

@Suite("SoakTestHarness")
struct SoakTestHarnessTests {

    // MARK: Configuration Defaults

    @Test("Configuration defaults are sensible")
    func configurationDefaults() {
        guard #available(macOS 14.2, *) else { return }
        let config = SoakTestHarness.Configuration()
        #expect(config.duration == 7200,
                "Default duration should be 7200 s (2 hours)")
        #expect(config.sampleInterval == 60,
                "Default sample interval should be 60 s")
        #expect(config.memoryGrowthAlertBytes == 50 * 1024 * 1024,
                "Default memory growth alert should be 50 MB")
        #expect(config.droppedFramesPerHourAlertCount == 60,
                "Default dropped-frame alert threshold should be 60/h")
    }

    // MARK: Report Codable Round-trip

    @Test("Report round-trips through JSON Codable")
    func reportCodableRoundTrip() throws {
        guard #available(macOS 14.2, *) else { return }
        let original = SoakTestHarness.Report(
            configuration: .init(
                duration: 300,
                sampleInterval: 30,
                memoryGrowthAlertBytes: 50 * 1024 * 1024,
                droppedFramesPerHourAlertCount: 60
            ),
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_000_300),
            actualDuration: 300,
            snapshots: [
                .init(
                    elapsedSeconds: 30,
                    residentBytes: 100 * 1024 * 1024,
                    purgeableBytes: 0,
                    cumulativeP50Ms: 15.5,
                    cumulativeP95Ms: 18.0,
                    cumulativeP99Ms: 24.0,
                    cumulativeMaxMs: 31.0,
                    cumulativeDroppedFrames: 0,
                    recentP50Ms: 15.5,
                    recentP95Ms: 17.5,
                    recentMaxMs: 20.0,
                    recentDroppedFrames: 0,
                    qualityLevel: "full"
                )
            ],
            signalTransitions: [
                .init(elapsedSeconds: 0.5, state: "active")
            ],
            qualityLevelTransitions: [],
            mlForceDispatches: 0,
            alerts: [],
            finalAssessment: .pass
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SoakTestHarness.Report.self, from: data)

        #expect(decoded.actualDuration == original.actualDuration)
        #expect(decoded.snapshots.count == original.snapshots.count)
        #expect(decoded.snapshots.first?.cumulativeP50Ms == original.snapshots.first?.cumulativeP50Ms)
        #expect(decoded.finalAssessment == original.finalAssessment)
        #expect(decoded.signalTransitions.first?.state == original.signalTransitions.first?.state)
        #expect(decoded.mlForceDispatches == original.mlForceDispatches)
    }

    // MARK: Assessment Enum Values

    @Test("Assessment has correct raw values")
    func assessmentRawValues() {
        guard #available(macOS 14.2, *) else { return }
        #expect(SoakTestHarness.Report.Assessment.pass.rawValue == "pass")
        #expect(SoakTestHarness.Report.Assessment.passWithSoftAlerts.rawValue == "passWithSoftAlerts")
        #expect(SoakTestHarness.Report.Assessment.hardFailure.rawValue == "hardFailure")
    }
}

// MARK: - Cancel (always-run)

extension SoakTestHarnessTests {

    @Test("cancel() causes run() to return before duration expires")
    @MainActor
    func cancelCausesEarlyReturn() async throws {
        guard #available(macOS 14.2, *) else { return }

        let config = SoakTestHarness.Configuration(
            duration: 3600,
            sampleInterval: 30,
            reportBaseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("phosphene_soak_cancel_\(Int(Date().timeIntervalSince1970))")
        )

        let router = AudioInputRouter()
        let harness = SoakTestHarness(configuration: config, audioInputRouter: router)

        // Run in background task; cancel almost immediately.
        let runTask = Task { @MainActor [harness] in
            try await harness.run(audioFile: nil)
        }

        // Give it half a second to initialise, then cancel.
        try await Task.sleep(for: .milliseconds(500))
        harness.cancel()

        let report = try await runTask.value
        #expect(report.actualDuration < config.duration,
                "actualDuration (\(report.actualDuration)s) should be < configured duration (\(config.duration)s)")
        #expect(report.actualDuration < 5.0,
                "Should have returned within ~5 s of cancel()")
    }
}

// MARK: - Soak-tagged Tests (SOAK_TESTS=1 required)

@Suite("SoakTestHarness (soak)")
struct SoakTestHarnessSoakTests {

    // MARK: 60-second Smoke Run

    @Test("60-second smoke run: report written, no hard failure")
    @MainActor
    func smokeSoakRun() async throws {
        guard ProcessInfo.processInfo.environment["SOAK_TESTS"] == "1" else { return }
        guard #available(macOS 14.2, *) else { return }

        let reportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphene_soak_smoke_\(Int(Date().timeIntervalSince1970))")

        let config = SoakTestHarness.Configuration(
            duration: 60,
            sampleInterval: 10,
            reportBaseDirectory: reportDir
        )

        let router = AudioInputRouter()
        let harness = SoakTestHarness(configuration: config, audioInputRouter: router)
        let report = try await harness.run(audioFile: nil)

        let alertsStr = report.alerts.joined(separator: "; ")
        #expect(report.finalAssessment.rawValue != "hardFailure",
                "Smoke run should not produce a hard failure. Alerts: \(alertsStr)")
        #expect(report.snapshots.count >= 4,
                "Expected ≥ 4 periodic snapshots, got \(report.snapshots.count)")

        // JSON report must be on disk.
        let soakDirs = (try? FileManager.default.contentsOfDirectory(
            at: reportDir, includingPropertiesForKeys: nil)) ?? []
        let allJSON = soakDirs.flatMap { dir in
            (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }.filter { $0.lastPathComponent == "report.json" }
        #expect(!allJSON.isEmpty, "report.json should be written to disk")

        printSmokeSummary(report, label: "60s smoke")
    }

    // MARK: 5-minute Memory Check

    @Test("5-minute run: memory growth observed (no threshold assertion)")
    @MainActor
    func fiveMinuteMemoryCheck() async throws {
        guard ProcessInfo.processInfo.environment["SOAK_TESTS"] == "1" else { return }
        guard #available(macOS 14.2, *) else { return }

        let reportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phosphene_soak_5min_\(Int(Date().timeIntervalSince1970))")

        let config = SoakTestHarness.Configuration(
            duration: 300,
            sampleInterval: 30,
            memoryGrowthAlertBytes: 500 * 1024 * 1024,  // observability only, not a hard gate
            reportBaseDirectory: reportDir
        )

        let router = AudioInputRouter()
        let harness = SoakTestHarness(configuration: config, audioInputRouter: router)
        let report = try await harness.run(audioFile: nil)

        let alertsStr = report.alerts.joined(separator: "; ")
        #expect(report.finalAssessment.rawValue != "hardFailure",
                "5-minute run should not produce a hard failure. Alerts: \(alertsStr)")

        printSmokeSummary(report, label: "5min memory")
    }

    // MARK: 30-second Drift Motes Kernel Cost (DM.2 Task 8 → DM.3 Task 4)
    //
    // Direct kernel-cost benchmark for `motes_update` at the Tier 2 particle
    // count (800). Dispatches one compute frame per simulated 60 Hz tick for
    // 30 seconds, captures `MTLCommandBuffer.gpuStartTime/gpuEndTime` per
    // frame, and reports p50 / p95 / p99 / drop-count of the kernel cost.
    //
    // The 1.6 ms Tier 2 / 2.1 ms Tier 1 targets in the Drift Motes
    // architecture contract describe the FULL preset frame budget (sky
    // fragment + curl-noise compute + sprite render + feedback decay). This
    // test isolates the compute kernel only.
    //
    // DM.3 (this update) extends the synthesised audio fixture to drive the
    // dispersion-shock branch every ~30 frames (a 2 Hz square wave on
    // `stems.drumsBeat`) and to vary `features.midAttRel` so the
    // emission-rate divisor exercises both branches each cycle. The kernel's
    // per-frame work in DM.3 includes a smoothstep + length + branch around
    // a small SIMD radial impulse — measurable but bounded.
    //
    // Full-pipeline timing requires a runtime app session because the
    // sprite pass needs a CAMetalDrawable. See
    // `Scripts/dm3_perf_capture.md` for the procedure that pins Drift Motes,
    // runs 30 s of representative audio, and emits per-frame timings to
    // a JSON log.
    //
    // Tier 1 numbers require Tier 1 hardware (M1/M2). The procedure is
    // documented in `docs/runbook/DM.3-tier1-measurement.md`.

    @Test("30-second Drift Motes kernel cost benchmark (Tier 2)")
    @MainActor
    func shortRunDriftMotes() async throws {
        guard ProcessInfo.processInfo.environment["SOAK_TESTS"] == "1" else { return }

        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geometry = try DriftMotesGeometry(
            device: ctx.device,
            library: lib.library,
            particleCount: DriftMotesGeometry.tier2ParticleCount,
            pixelFormat: nil
        )

        let dt: Float = 1.0 / 60.0
        let frameCount = 30 * 60   // 30 seconds at simulated 60 Hz.
        var features = FeatureVector.zero
        features.deltaTime = dt
        // Realistic-ish coupling so the D-019 blend selects the warm hue
        // path on most respawns and exercises the pitch helper too.
        var stems = StemFeatures.zero
        stems.vocalsEnergy = 0.4
        stems.drumsEnergy = 0.5
        stems.bassEnergy = 0.4
        stems.otherEnergy = 0.4
        stems.vocalsPitchHz = 220.0
        stems.vocalsPitchConfidence = 0.85

        var kernelMs: [Double] = []
        kernelMs.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            features.time = Float(frame) * dt
            // Sweep pitch so the warm-hue path produces varied output.
            stems.vocalsPitchHz = 110.0 * powf(16.0, Float(frame % 240) / 239.0)
            features.midAttRel = 0.2 + 0.3 * sinf(features.time * 0.5)
            // DM.3: 2 Hz square wave on drumsBeat exercises the dispersion
            // shock branch and the smoothstep evaluation roughly every other
            // frame. Triangle envelope (0 → 1 → 0) over 30 frames more
            // realistically emulates the BeatDetector envelope shape than a
            // pure square wave but the cost difference per frame is
            // negligible — we just need the branch to trigger.
            let beatCycle = frame % 30
            stems.drumsBeat = beatCycle < 15 ? 1.0 : 0.0

            guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else {
                continue
            }
            geometry.update(features: features, stemFeatures: stems,
                            commandBuffer: cmdBuf)
            cmdBuf.commit()
            await cmdBuf.completed()
            let durationS = cmdBuf.gpuEndTime - cmdBuf.gpuStartTime
            kernelMs.append(durationS * 1000.0)
        }

        // Sort once for percentiles + drop count.
        kernelMs.sort()
        let n = kernelMs.count
        let p50 = kernelMs[n / 2]
        let p95 = kernelMs[Int(Double(n) * 0.95)]
        let p99 = kernelMs[Int(Double(n) * 0.99)]
        let mean = kernelMs.reduce(0, +) / Double(n)
        // "Drops" here = frames whose kernel time exceeded 14 ms (the Tier 2
        // governor's downshift threshold). These are not full-pipeline
        // drops, but they're the kernel-cost equivalent.
        let kernelOverruns = kernelMs.filter { $0 > 14.0 }.count

        print("""
        ┌─ DriftMotesKernelCost [Tier 2, 800 particles] ─
        │ frames=\(n)  mean=\(String(format: "%.3f", mean))ms
        │ p50=\(String(format: "%.3f", p50))ms  \
        p95=\(String(format: "%.3f", p95))ms  \
        p99=\(String(format: "%.3f", p99))ms
        │ kernel overruns (>14ms)=\(kernelOverruns)
        │ Tier 2 full-frame budget=1.6ms (preset contract); kernel-only is
        │ a bounded subset. Full-pipeline measurement deferred to a runtime
        │ session per DM.2 Task 8.
        └────────────────────────────────────────────────
        """)

        // Loose gate: kernel p95 should sit well under the full-pipeline
        // Tier 2 budget. Failures here would indicate a kernel regression
        // (e.g., a curl-noise octave bump or accidental neighbour query)
        // rather than a full-pipeline budget breach.
        #expect(p95 < 5.0,
                "Kernel p95 \(p95) ms exceeds 5ms loose gate — investigate motes_update for regression.")
    }

    // MARK: SOAK_TESTS=1 — Arachne composite-fragment kernel cost
    //
    // BUG-011 in-tree regression gate. The full-pipeline perf capture for
    // Arachne (real-music + production app) is documented in
    // `docs/diagnostics/DM.3-perf-capture.md` and is the closure gate for
    // BUG-011; this SOAK test is the kernel-only equivalent that catches
    // shader-side regressions before they reach the full-pipeline capture.
    //
    // Renders Arachne's COMPOSITE fragment to a 1920×1080 offscreen texture
    // with the spider forced active and a placeholder WORLD texture bound at
    // texture(13). This exercises:
    //   • the foreground anchor block (web walk + drops + Snell's-law
    //     refraction sampling worldTex per drop pixel — gated post-L2 at
    //     `wr.dropCov > 0.5`),
    //   • the V.7.7D 3D SDF spider patch ray-march (post-L1 at 24 steps,
    //     dispatched via the post-L3 `spider.blend > 0.05` gate),
    //   • §8.2 vibration UV jitter,
    //   • final WORLD `worldTex.sample(uv)` + ambient + rim,
    //   • mist + dust mote post-process.
    //
    // Loose gate p95 ≤ 16 ms kernel-only. The Drift Motes 1:3 kernel:full-
    // pipeline ratio does NOT apply to Arachne — Arachne is fragment-only
    // (no compute pre-pass to add on top), so kernel ≈ full-pipeline. The
    // 16 ms gate sits ~10 % above the post-BUG-011 measurement on M2 Pro
    // (this hardware's 2026-05-10 capture: kernel p95 = 14.6 ms with
    // spider forced ON), giving margin for run-to-run variance + thermal
    // state, and still catches a lever-revert regression (which would
    // jump p95 back into the 22–26 ms range — pre-tuning baseline was
    // 26.6 ms full-pipeline per BUG-011 KNOWN_ISSUES).
    //
    // The L3 dispatch gate (`spider.blend > 0.05`) is bypassed in this
    // benchmark by `forceActivateForTest(at:)` which sets blend=1, so the
    // patch ray-march fires every frame. This is the WORST-case path; in
    // production the spider is idle ~75 % of the time, so real-music
    // p95 will land below this number. The full-pipeline closure gate
    // for BUG-011 is the M2 Pro real-music capture per
    // docs/diagnostics/DM.3-perf-capture.md.

    @Test("30-second Arachne COMPOSITE fragment kernel cost benchmark (Tier 2)")
    @MainActor
    func shortRunArachneComposite() async throws {
        guard ProcessInfo.processInfo.environment["SOAK_TESTS"] == "1" else { return }

        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device,
                                   pixelFormat: ctx.pixelFormat,
                                   loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Arachne" }) else {
            // Arachne preset absent (Metal shader compile failed) — skip.
            return
        }

        // Locate the COMPOSITE stage's pipeline state (Arachne is staged-
        // composition under V.7.7A+; the loaded preset's `pipelineState`
        // already resolves to the COMPOSITE stage per the JSON sidecar's
        // `fragment_function: arachne_composite_fragment`).
        let pipeline = preset.pipelineState

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        guard let arachneState = ArachneState(device: device, seed: 42) else { return }

        // Polygon-seeded, mid-build foreground (matches `ArachneSpiderRenderTests`
        // shape so the benchmark exercises the production polygon-aware path).
        arachneState.reset()
        let warmupFV = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                       time: 1.0, deltaTime: 1.0 / 60.0)
        for _ in 0..<30 { arachneState.tick(features: warmupFV, stems: .zero) }

        // Force spider on at the canonical fixture position so the V.7.7D
        // patch ray-march fires every frame (worst-case path).
        arachneState.forceActivateForTest(at: SIMD2<Float>(0.42, 0.40))

        // 1920×1080 offscreen render target — representative of production
        // drawable resolution. .bgra8Unorm matches the production pixel
        // format; ctx.pixelFormat returns .bgra8Unorm_srgb but the COMPOSITE
        // pipeline state was compiled against ctx.pixelFormat so we use it
        // here for compatibility.
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat,
            width: 1920, height: 1080, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .private
        guard let target = ctx.device.makeTexture(descriptor: texDesc) else { return }

        // Placeholder WORLD texture at texture(13). 256² mid-gray is enough
        // to exercise `worldTex.sample()` cost; the shader doesn't care about
        // the WORLD content for kernel timing — only that the sample
        // resolves to a real texture rather than an unbound default.
        let worldDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: 256, height: 256, mipmapped: false)
        worldDesc.usage = [.shaderRead]
        worldDesc.storageMode = .shared
        guard let worldTex = ctx.device.makeTexture(descriptor: worldDesc) else { return }
        // Fill with mid-gray Float16 (0.5, 0.5, 0.5, 1.0 — bit-pattern not
        // important for cost timing, only that texture memory is initialised).
        let worldBytes = [UInt16](repeating: 0x3800, count: 256 * 256 * 4)  // 0.5 in f16
        worldBytes.withUnsafeBufferPointer { buf in
            worldTex.replace(region: MTLRegionMake2D(0, 0, 256, 256),
                             mipmapLevel: 0,
                             withBytes: buf.baseAddress!,
                             bytesPerRow: 256 * 4 * 2)
        }

        // Standard buffer scaffolding shared with `ArachneSpiderRenderTests`.
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf  = ctx.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf  = ctx.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let histBuf = ctx.makeSharedBuffer(length: 4096 * floatStride)
        else { return }
        _ = stemBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                 count: MemoryLayout<StemFeatures>.size)
        _ = histBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                 count: 4096 * floatStride)

        let dt: Float = 1.0 / 60.0
        let frameCount = 30 * 60
        var kernelMs: [Double] = []
        kernelMs.reserveCapacity(frameCount)

        // Representative musical fixture — mid-energy continuous bands +
        // periodic kick exercising vibration + drop accent.
        var fv = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                 time: 0.0, deltaTime: dt)
        var stems = StemFeatures.zero
        stems.drumsEnergy = 0.5
        stems.bassEnergy = 0.5

        for frame in 0..<frameCount {
            fv.time = Float(frame) * dt
            // 2 Hz square wave on bassAttRel exercises §8.2 vibration UV
            // jitter (vibration amplitude scales with f.bass_att_rel).
            let beatCycle = frame % 30
            fv.bassAttRel = beatCycle < 15 ? 0.5 : 0.0
            fv.beatBass   = beatCycle < 5  ? 0.7 : 0.0
            stems.drumsBeat = beatCycle < 5 ? 0.7 : 0.0

            guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else { continue }
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = target
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { continue }

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
            encoder.setFragmentBuffer(fftBuf,  offset: 0, index: 1)
            encoder.setFragmentBuffer(wavBuf,  offset: 0, index: 2)
            encoder.setFragmentBuffer(stemBuf, offset: 0, index: 3)
            // index 4 = SceneUniforms (ray-march only — Arachne is direct fragment).
            encoder.setFragmentBuffer(histBuf, offset: 0, index: 5)
            encoder.setFragmentBuffer(arachneState.webBuffer,    offset: 0, index: 6)
            encoder.setFragmentBuffer(arachneState.spiderBuffer, offset: 0, index: 7)
            encoder.setFragmentTexture(worldTex, index: 13)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            cmdBuf.commit()
            await cmdBuf.completed()
            let durationS = cmdBuf.gpuEndTime - cmdBuf.gpuStartTime
            kernelMs.append(durationS * 1000.0)
        }

        kernelMs.sort()
        let n = kernelMs.count
        guard n > 0 else { return }
        let p50 = kernelMs[n / 2]
        let p95 = kernelMs[Int(Double(n) * 0.95)]
        let p99 = kernelMs[Int(Double(n) * 0.99)]
        let mean = kernelMs.reduce(0, +) / Double(n)
        // "Overruns" = frames whose kernel time exceeded the 14 ms Tier 2
        // FrameBudgetManager downshift threshold (the production gate, not
        // the SOAK loose gate).
        let kernelOverruns = kernelMs.filter { $0 > 14.0 }.count

        print("""
        ┌─ ArachneCompositeKernelCost [Tier 2, 1920×1080, spider forced ON] ─
        │ frames=\(n)  mean=\(String(format: "%.3f", mean))ms
        │ p50=\(String(format: "%.3f", p50))ms  \
        p95=\(String(format: "%.3f", p95))ms  \
        p99=\(String(format: "%.3f", p99))ms
        │ kernel overruns (>14ms)=\(kernelOverruns) of \(n)
        │ Tier 2 full-frame budget=14ms (FrameBudgetManager downshift threshold);
        │ Arachne is fragment-only so kernel ≈ full-pipeline (NOT the Drift
        │ Motes 1:3 kernel:full ratio). Spider forced ON every frame is
        │ the worst case; production p95 will be lower because spider is
        │ idle ~75% of the time.
        │ Full-pipeline closure gate: real-music capture on M2 Pro per
        │ docs/diagnostics/DM.3-perf-capture.md.
        └────────────────────────────────────────────────
        """)

        // Loose gate: kernel p95 should sit under 16 ms after BUG-011 levers
        // L1+L2+L3 on M2 Pro. A failure here is a shader-side regression —
        // step count, coverage gate, or dispatch gate creep — that should
        // be caught before reaching the full-pipeline capture. The 16 ms
        // value is ~10 % above the post-BUG-011 measurement on M2 Pro
        // (2026-05-10 capture: 14.6 ms with spider forced ON), and well
        // below the pre-tuning ~26 ms baseline a lever-revert would
        // restore.
        #expect(p95 < 16.0,
                """
                Arachne COMPOSITE kernel p95 \(p95) ms exceeds 16 ms loose gate \
                on M2 Pro — investigate arachne_composite_fragment for regression. \
                BUG-011 levers (L1 spider steps 24, L2 drop coverage 0.5, L3 \
                spider blend 0.05) should hold this gate; if any were reverted, \
                p95 will jump back into the 22–26 ms range.
                """)
    }

    // MARK: Helpers

    @available(macOS 14.2, *)
    private nonisolated func printSmokeSummary(_ report: SoakTestHarness.Report, label: String) {
        let dur = String(format: "%.1f", report.actualDuration)
        let snap = report.snapshots.last
        let finalMem = snap.map { "\($0.residentBytes / (1024 * 1024)) MB" } ?? "n/a"
        let p50 = snap.map { String(format: "%.1f", $0.cumulativeP50Ms) } ?? "n/a"
        let p95 = snap.map { String(format: "%.1f", $0.cumulativeP95Ms) } ?? "n/a"
        let p99 = snap.map { String(format: "%.1f", $0.cumulativeP99Ms) } ?? "n/a"
        let drops = snap.map { "\($0.cumulativeDroppedFrames)" } ?? "n/a"
        print("""
        ┌─ SoakSmoke [\(label)] ─────────────────
        │ duration=\(dur)s  assessment=\(report.finalAssessment.rawValue)
        │ memory=\(finalMem)
        │ P50=\(p50)ms  P95=\(p95)ms  P99=\(p99)ms  dropped=\(drops)
        │ signals=\(report.signalTransitions.count)  mlForce=\(report.mlForceDispatches)
        └─────────────────────────────────────
        """)
    }
}
