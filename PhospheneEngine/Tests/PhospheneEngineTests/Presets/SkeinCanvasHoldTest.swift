// SkeinCanvasHoldTest — Skein.1 canvas-hold + wandering-pour-line gate.
//
// Skein.ENGINE.1/1.1 established the LOSSLESS canvas-hold property (identity warp +
// no decay + no R→G→B transfer ⇒ the held canvas is carried BYTE-FOR-BYTE). Skein.1
// replaces the static test disc with a SINGLE white pour LINE traced by a wandering
// "painter" (a closed-form ergodic function of features.time), accumulating losslessly
// on the cream ground. This file proves, through the SAME live dispatch path the app uses
// (scene → warp → marks-on-top overlay → blit → swap, in a loop), that the line:
//   1. ACCUMULATES   — painted coverage grows monotonically (paint is laid, never lost).
//   2. HOLDS         — a texel painted early persists to the end (lossless hold under a
//                      MOVING mark), and an unpainted far corner stays byte-identical.
//   3. is CONTINUOUS — the laid line is a single connected component (no gaps between
//                      consecutive swept capsules; they share an endpoint by construction).
//
// Production-pipeline parity (CLAUDE.md "Test in the production-grade rendering pipeline.
// No shortcuts." + FA #66): NOT `preset.pipelineState` in isolation — the live warp +
// per-preset marks-on-top overlay, driven for N frames with features.time advancing.
//
// What this does NOT prove (Skein.2+): splatter / filaments / viscosity, audio coupling,
// wetness, palette beyond white-on-cream, mood. The chromatic=0-vs-1 distinguisher is the
// ENGINE.1.1 property (D-142/D-143) and is unchanged here; Skein.1 proves the moving-mark
// accumulation/hold/continuity above it.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Skein canvas-hold + pour line")
struct SkeinCanvasHoldTest {

    // MARK: - Static-source guards (cheap regression sentries)

    @Test("Skein.metal declares the canvas-hold mv_warp + fragment functions")
    func test_metalSource_declaresCanvasHoldFunctions() throws {
        let src = try String(contentsOf: Self.shaderURL("Skein.metal"), encoding: .utf8)
        #expect(src.contains("fragment float4 skein_fragment("),
                "Skein.metal missing skein_fragment entry point.")
        #expect(src.contains("MVWarpPerFrame mvWarpPerFrame("),
                "Skein.metal missing mvWarpPerFrame (D-027 canvas-hold contract).")
        #expect(src.contains("float2 mvWarpPerVertex("),
                "Skein.metal missing mvWarpPerVertex (D-027 canvas-hold contract).")
        // Identity + no-decay are the canvas-hold invariants — guard the literals.
        #expect(src.contains("return uv;"),
                "Skein.metal mvWarpPerVertex must be identity (return uv) for canvas-hold.")
        #expect(src.contains("pf.decay = 1.0"),
                "Skein.metal mvWarpPerFrame must set decay = 1.0 (no decay) for canvas-hold.")
        // Skein.ENGINE.1.1 (D-143): the mark is the marks-on-top overlay.
        #expect(src.contains("vertex SkeinGeoVertexOut skein_geometry_vertex("),
                "Skein.metal missing skein_geometry_vertex (marks-on-top overlay, D-143).")
        #expect(src.contains("fragment float4 skein_geometry_fragment("),
                "Skein.metal missing skein_geometry_fragment (marks-on-top overlay, D-143).")
        // Skein.1: the static test disc is REPLACED by the closed-form wandering pour line.
        // The painter trajectory must exist and the disc-stamp constants must be gone.
        #expect(src.contains("skeinPainterPos"),
                "Skein.metal missing skeinPainterPos (Skein.1 closed-form painter trajectory).")
        #expect(src.contains("constant FeatureVector& f [[buffer(0)]]"),
                "Skein.metal skein_geometry_vertex must read features@0 (Path A — the painter drives off features.time).")
        #expect(!src.contains("kSkeinStampColor"),
                "Skein.metal still declares the ENGINE.1.1 disc stamp — Skein.1 replaces it with the pour line.")
        // Skein.2: the splatter morphology — ragged-edge 2D fBM + the debug viscosity sweep.
        #expect(src.contains("skein_fbm2"),
                "Skein.metal missing skein_fbm2 (Skein.2 ≥4-octave ragged-edge 2D noise).")
        #expect(src.contains("skeinDebugViscosity"),
                "Skein.metal missing skeinDebugViscosity (Skein.2 debug viscosity sweep → Skein.3 centroid).")
        #expect(src.contains("hash_f01_4x"),
                "Skein.metal missing hash_f01_4x (Skein.2 deterministic per-droplet placement, §5.7).")
    }

    @Test("Skein.json declares canvas-hold config + a marks-on-top block (D-143)")
    func test_json_declaresCanvasHoldConfig() throws {
        let data = try Data(contentsOf: Self.shaderURL("Skein.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((json?["passes"] as? [String]) == ["direct", "mv_warp"],
                "Skein.json must declare passes: [\"direct\", \"mv_warp\"] (sibling of Dragon Bloom).")
        let decay = (json?["decay"] as? NSNumber)?.doubleValue
        #expect(decay == 1.0,
                "Skein.json decay must be 1.0 (no decay) to match mvWarpPerFrame.")
        // Skein needs chromatic=0 (lossless, non-cycling), no beat pump, and a cream ground.
        let marks = json?["marks"] as? [String: Any]
        #expect(marks != nil, "Skein.json must declare a `marks` block (marks-on-top config, D-143).")
        #expect((marks?["chromatic"] as? NSNumber)?.doubleValue == 0.0,
                "Skein.json marks.chromatic must be 0 (lossless, non-cycling canvas-hold).")
        #expect((marks?["beat_pulse"] as? Bool) == false,
                "Skein.json marks.beat_pulse must be false (a quiet held canvas — no audio until Skein.4).")
        let clear = marks?["canvas_clear"] as? [NSNumber]
        #expect(clear?.count == 3,
                "Skein.json marks.canvas_clear must be an RGB triple (the held cream ground).")
    }

    // MARK: - Pour line: accumulation + hold + continuity (the Skein.1 gate, live dispatch path)

    @Test("Pour line accumulates, holds losslessly under motion, and is continuous — live marks-on-top path")
    func test_pourLine_accumulatesHoldsContinuous() throws {
        guard let fx = try loadSkeinFixture() else { return }
        let w = 256, h = 256
        let checkpoints = [30, 75, 120, 179]
        // Square render (aspect 1.0) so the line width is isotropic and the connectivity mask
        // is clean. The painter advances with features.time → a new capsule lands each frame.
        let run = try runPourAccumulation(
            chromatic: 0, frames: 180, width: w, height: h, aspect: 1.0, startTime: 0.0,
            checkpoints: Set(checkpoints), fx: fx)

        // Skein.2: isolate the pour LINE from the splatter satellites. The line lives in a thin
        // corridor around the trajectory; far satellites are disconnected components by design.
        let line = pourLineCorridor(run.finalPixels, w: w, h: h, cream: run.creamRef,
                                    t0: -0.7, t1: 3.0, rV: 0.025)
        let whiteOK = hasWhiteTexel(run.finalPixels)
        print("""
        [skein_pour] 180 frames @ \(w)×\(h), chromatic=0, live scene→warp→overlay→blit→swap (Skein.2 splatter on):
          painted-count checkpoints \(run.checkpointFrames) = \(run.checkpointCounts)
          early painted texel \(run.earlyXY.map { "(\($0.0),\($0.1))" } ?? "none") still painted at end = \(run.earlyStillPaintedFinal)
          pour-LINE continuity (corridor) = \(String(format: "%.3f", line.continuity))  [in-corridor \(line.inCorridor) / satellites-outside \(line.outside)]
          far corner held (chromatic=0): frame0 \(run.creamRef) == final \(run.groundCornerFinal) ? \(run.creamRef == run.groundCornerFinal)
          ground corner cream = \(isCreamish(run.groundCornerFinal)) ; white texel present = \(whiteOK)
        """)

        // 1. ACCUMULATION — painted-pixel count is monotone non-decreasing (identity hold + no
        //    decay ⇒ paint never disappears) and strictly grows (the painter is laying the line).
        for i in 1..<run.checkpointCounts.count {
            #expect(run.checkpointCounts[i] >= run.checkpointCounts[i - 1],
                    "Painted count fell \(run.checkpointCounts[i-1]) → \(run.checkpointCounts[i]) — accumulation not lossless (paint vanished).")
        }
        #expect((run.checkpointCounts.last ?? 0) > (run.checkpointCounts.first ?? 0),
                "Painted count did not grow (\(run.checkpointCounts)) — the painter laid no new line.")

        // 2. HOLD UNDER MOTION — a texel painted early persists to the end (the laid line is held
        //    losslessly; it does not fade or drift while the painter moves on).
        #expect(run.earlyXY != nil, "No early painted texel found — the line did not render.")
        #expect(run.earlyStillPaintedFinal,
                "An early-painted texel was no longer painted at the end — the canvas-hold lost a laid mark.")
        //    and the UNPAINTED far corner is byte-identical frame-0 → final (the ENGINE.1.1
        //    lossless-hold property, now under a moving mark: unpainted texels never drift).
        #expect(run.creamRef == run.groundCornerFinal,
                "Far corner drifted \(run.creamRef) → \(run.groundCornerFinal) at chromatic=0 — the held canvas is not lossless.")

        // 3. CONTINUITY (pour LINE only) — the laid line is a single connected component (no gaps
        //    between consecutive capsules; they share an endpoint by construction). Skein.2 adds
        //    disconnected SATELLITES by design, so continuity is checked in the LINE corridor only;
        //    the satellites appear as paint OUTSIDE the corridor (asserted present, so the splatter
        //    is verified to render here too — it is exercised in depth by test_splatter_*).
        #expect(line.continuity >= 0.95,
                "Pour-line corridor continuity is only \(line.continuity) — the line has gaps (Skein.1 invariant regressed).")
        #expect(line.outside > 0,
                "No painted pixels outside the line corridor — the Skein.2 splatter satellites did not render.")

        // 4. CREAM GROUND held (not black) — the per-preset canvas clear (D-143) still carries.
        #expect(!isBlack(run.groundCornerFinal),
                "Ground corner is black — the cream canvas clear did not take. \(run.groundCornerFinal)")
        #expect(isCreamish(run.groundCornerFinal),
                "Ground corner is not cream-ish (bright, R≳G≳B). \(run.groundCornerFinal)")

        // 5. WHITE LINE — at least one fully-laid texel is white (the pour colour; palette is Skein.3).
        #expect(whiteOK, "No white texel found — the pour line did not render white-on-cream.")
    }

    // MARK: - Splatter: halo + bake/hold + viscosity response + new-mark count (the Skein.2 gate)

    @Test("Splatter bakes + holds, shows a dense-near satellite halo, opaque (not additive), and responds to viscosity — live path")
    func test_splatter_morphologyBakesHoldsViscosity() throws {
        guard let fx = try loadSkeinFixture() else { return }
        let w = 256, h = 256
        // Two windows of the debug viscosity sweep (period 12 s): THICK peak ~t6, THIN trough ~t12.
        // Both run the same live scene→warp→overlay→blit→swap path advancing features.time.
        let thick = try runPourAccumulation(
            chromatic: 0, frames: 180, width: w, height: h, aspect: 1.0, startTime: 4.5,
            checkpoints: [40, 179], fx: fx, capturePerFrame: true)
        let thin = try runPourAccumulation(
            chromatic: 0, frames: 180, width: w, height: h, aspect: 1.0, startTime: 10.5,
            checkpoints: [40, 179], fx: fx, capturePerFrame: true)

        let ts = splatterHaloAndSatellites(thick.finalPixels, w: w, h: h, cream: thick.creamRef,
                                           t0: 3.8, t1: 7.5, corridorRV: 0.025)
        let ns = splatterHaloAndSatellites(thin.finalPixels, w: w, h: h, cream: thin.creamRef,
                                           t0: 9.8, t1: 13.5, corridorRV: 0.025)

        // New-mark count (governor input): per-frame painted-count deltas.
        let deltas = zip(thick.perFrameCounts.dropFirst(), thick.perFrameCounts).map { $0 - $1 }
        let newMarkFrames = deltas.filter { $0 > 0 }.count
        let creamMin = Int(min(thick.creamRef[0], min(thick.creamRef[1], thick.creamRef[2])))

        print("""
        [skein_splatter] live scene→warp→overlay→blit→swap, 256×256:
          THICK (visc≈hi, startT 4.5): halo near/mid/far = \(ts.haloNear)/\(ts.haloMid)/\(ts.haloFar)  satellites=\(ts.satellites)  meanSatDist=\(String(format: "%.3f", ts.meanSatDist))  minCh=\(ts.minChannel)
          THIN  (visc≈lo, startT 10.5): halo near/mid/far = \(ns.haloNear)/\(ns.haloMid)/\(ns.haloFar)  satellites=\(ns.satellites)  meanSatDist=\(String(format: "%.3f", ns.meanSatDist))  minCh=\(ns.minChannel)
          new-mark count: \(newMarkFrames)/\(deltas.count) frames added marks; deltas[0..<8]=\(Array(deltas.prefix(8)))
          opaque check: creamMin=\(creamMin), thick minCh=\(ts.minChannel), thin minCh=\(ns.minChannel)
        """)

        // 1. SATELLITE HALO — dense near the line, sparse far (spatter, not a uniform field).
        #expect(ts.haloNear > ts.haloFar,
                "THICK satellites not dense-near/sparse-far (near \(ts.haloNear) ≤ far \(ts.haloFar)).")
        #expect(ns.haloNear > ns.haloFar,
                "THIN satellites not dense-near/sparse-far (near \(ns.haloNear) ≤ far \(ns.haloFar)).")

        // 2. DISTINCT SATELLITES (not a merged froth) — many disconnected blobs outside the line.
        #expect(ns.satellites > 20,
                "THIN produced only \(ns.satellites) distinct satellites — splatter not rendering as discrete dots.")

        // 3. VISCOSITY RESPONSE — thin/fine flings satellites WIDER + throws MORE of them than thick.
        //    meanSatDist (a per-satellite spread, trajectory-robust) is the cleanest discriminator.
        #expect(ns.meanSatDist > ts.meanSatDist,
                "Viscosity did not widen the spread: thin meanSatDist \(ns.meanSatDist) ≤ thick \(ts.meanSatDist).")
        #expect(ns.satellites > ts.satellites,
                "Satellite count did not respond to viscosity: thin \(ns.satellites) ≤ thick \(ts.satellites).")

        // 4. OPAQUE alpha-over, NOT additive — paint only brightens cream→white; no channel drops
        //    below cream's darkest channel (no mud / no darkening). (creamB ≈ 188; 12 tolerance.)
        #expect(ts.minChannel >= creamMin - 12,
                "A pixel darkened below cream (thick minCh \(ts.minChannel) < \(creamMin - 12)) — additive/muddy compositing.")
        #expect(ns.minChannel >= creamMin - 12,
                "A pixel darkened below cream (thin minCh \(ns.minChannel) < \(creamMin - 12)) — additive/muddy compositing.")

        // 5. SPLATTER BAKES + HOLDS — a satellite painted by the early checkpoint persists to the end.
        let earlyBuf = thick.checkpointPixels[40]
        #expect(earlyBuf != nil, "No early checkpoint captured for the bake/hold check.")
        if let earlyBuf = earlyBuf {
            let sat = firstSatellitePixel(earlyBuf, w: w, h: h, cream: thick.creamRef,
                                          t0: 3.8, t1: 7.5, corridorRV: 0.03)
            #expect(sat != nil, "No early satellite found outside the line corridor — splatter not laid early.")
            if let (sx, sy) = sat {
                let i = (sy * w + sx) * 4
                let f = thick.finalPixels
                let delta = abs(Int(f[i]) - Int(thick.creamRef[0]))
                          + abs(Int(f[i + 1]) - Int(thick.creamRef[1]))
                          + abs(Int(f[i + 2]) - Int(thick.creamRef[2]))
                #expect(delta > 45,
                        "An early-painted satellite at (\(sx),\(sy)) was lost by the end — splatter did not bake/hold (Δ \(delta)).")
            }
        }

        // 6. NEW-MARK COUNT exposed (the §6 governor input) — marks are added across the run.
        #expect(thick.perFrameCounts.count == 180, "Per-frame painted counts not captured for all frames.")
        #expect(newMarkFrames > 90,
                "Marks were added on only \(newMarkFrames)/\(deltas.count) frames — splatter/pour not accumulating.")
    }

    // MARK: - Pour-line accumulation contact sheet (env-gated eyeball artifact)

    @Test("Pour-line accumulation contact sheet (env-gated: SKEIN_VISUAL=1 / RENDER_VISUAL=1)")
    func test_pourLine_contactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SKEIN_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("SkeinCanvasHoldTest: SKEIN_VISUAL/RENDER_VISUAL not set, skipping contact sheet")
            return
        }
        guard let fx = try loadSkeinFixture() else { return }
        // 16:9 — the live viewport shape (aspect 1.777, the FeatureVector default) → isotropic width.
        // 960×540 (½ of 1080p) so the fine far-flung satellites read at a fair scale (270p under-samples
        // the 2–6 px dots that are 8–24 px in the live 1080p path).
        let w = 960, h = 540
        let dt: Float = 1.0 / 60.0
        // Frames at ~2 / 5 / 10 / 20 s of features.time — a single frame cannot show accumulation.
        let secs: [Float] = [2, 5, 10, 20]
        let checkpoints = secs.map { Int(($0 / dt).rounded()) }   // [120, 300, 600, 1200]
        let run = try runPourAccumulation(
            chromatic: 0, frames: (checkpoints.max() ?? 0) + 1, width: w, height: h,
            aspect: Float(w) / Float(h), startTime: 0.0, checkpoints: Set(checkpoints), fx: fx)

        let outDir = try makeOutputDir()
        var ordered: [[UInt8]] = []
        for (i, f) in checkpoints.enumerated() {
            guard let buf = run.checkpointPixels[f] else { continue }
            ordered.append(buf)
            try writeBGRAToPNG(buf, w: w, h: h,
                               url: outDir.appendingPathComponent(String(format: "skein_t%02.0fs.png", secs[i])))
        }
        try writeMontage(ordered, tileW: w, tileH: h,
                         url: outDir.appendingPathComponent("skein_contact_sheet.png"))

        let counts = checkpoints.map { run.checkpointPixels[$0].map { countPainted($0, cream: run.creamRef) } ?? -1 }
        let pct = counts.map { String(format: "%.1f%%", 100 * Float($0) / Float(w * h)) }
        print("""
        [skein_contact_sheet] live marks-on-top path (scene→warp→overlay→blit→swap), \(w)×\(h):
          output dir: \(outDir.path)
          checkpoints (s)        = \(secs)
          painted coverage       = \(counts) px  (\(pct))
          → skein_contact_sheet.png  +  skein_t02s/05s/10s/20s.png
        """)
        #expect(ordered.count == checkpoints.count, "Missing contact-sheet checkpoints — accumulation run came up short.")
    }

    // MARK: - Splatter viscosity-sweep contact sheet (env-gated: both poles, crisp)

    @Test("Splatter viscosity-sweep contact sheet (env-gated: SKEIN_VISUAL=1 / RENDER_VISUAL=1)")
    func test_splatter_viscositySweepContactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SKEIN_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("SkeinCanvasHoldTest: SKEIN_VISUAL/RENDER_VISUAL not set, skipping viscosity sweep")
            return
        }
        guard let fx = try loadSkeinFixture() else { return }
        let w = 960, h = 540
        // Independent fresh accumulations (each ~4 s from cream) centred on the viscosity-sweep poles,
        // so each tile is a near-constant-viscosity demonstration of ONE pole through the live path:
        //   THIN  (trough ~t12): finer line, MANY fine FAR-flung satellites (ref 03_micro).
        //   THICK (peak  ~t6):   fatter line/pools, FEWER bigger CLOSER droplets (refs 02 / 06).
        let poles: [(name: String, startT: Float)] = [("thin", 10.0), ("thick", 4.0)]
        let frames = 240
        let last = frames - 1
        var tiles: [[UInt8]] = []
        let outDir = try makeOutputDir()
        for pole in poles {
            let run = try runPourAccumulation(
                chromatic: 0, frames: frames, width: w, height: h, aspect: Float(w) / Float(h),
                startTime: pole.startT, checkpoints: [last], fx: fx)
            guard let buf = run.checkpointPixels[last] else { continue }
            tiles.append(buf)
            try writeBGRAToPNG(buf, w: w, h: h, url: outDir.appendingPathComponent("skein_visc_\(pole.name).png"))
        }
        try writeMontage(tiles, tileW: w, tileH: h,
                         url: outDir.appendingPathComponent("skein_viscosity_sweep.png"))
        print("""
        [skein_viscosity_sweep] live marks-on-top path, \(w)×\(h), independent fresh accumulations:
          output dir: \(outDir.path)
          poles (startT) = \(poles.map { "\($0.name)@\($0.startT)s" })
          → skein_viscosity_sweep.png  (thin | thick)  +  skein_visc_thin/thick.png
        """)
        #expect(tiles.count == poles.count, "Missing viscosity-sweep tiles — a pole run came up short.")
    }

    // MARK: - Fixture load

    private struct SkeinFixture {
        let mvWarp: PresetLoader.MVWarpCompiledPipelines
        let overlay: MTLRenderPipelineState
        let cream: MTLClearColor
        let ctx: MetalContext
    }

    /// Resolve the live Skein preset + its compiled mv_warp / overlay pipelines + the cream
    /// canvas-clear (sourced from the descriptor `marks.canvas_clear`, the same value the app
    /// feeds setupMVWarp). Returns nil (after `Issue.record`/skip) when the fixture is absent.
    private func loadSkeinFixture() throws -> SkeinFixture? {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("SkeinCanvasHoldTest: no Metal device — skipping")
            return nil
        }
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Skein" }) else {
            Issue.record("Skein preset not loaded — bundle resource not copied?")
            return nil
        }
        guard let mvWarp = preset.mvWarpPipelines else {
            Issue.record("Skein preset.mvWarpPipelines is nil — JSON passes array misconfigured.")
            return nil
        }
        // The per-preset scene-geometry overlay (skein_geometry_*) must have compiled via the
        // D-143 per-prefix lookup — this is the mechanism that draws the pour line on top.
        guard let overlay = mvWarp.sceneGeometryState else {
            Issue.record("Skein mvWarpPipelines.sceneGeometryState is nil — skein_geometry_* not resolved (D-143 per-prefix lookup).")
            return nil
        }
        guard let creamRGB = preset.descriptor.marks?.canvasClear else {
            Issue.record("Skein descriptor has no marks.canvas_clear — the held cream ground is unplumbed (D-143).")
            return nil
        }
        let cream = MTLClearColor(
            red: Double(creamRGB.x), green: Double(creamRGB.y), blue: Double(creamRGB.z), alpha: 1)
        return SkeinFixture(mvWarp: mvWarp, overlay: overlay, cream: cream, ctx: try MetalContext())
    }

    // MARK: - Accumulation driver (advances features.time → the painter moves)

    private struct PourResult {
        var checkpointFrames: [Int]            // sorted checkpoint frame indices
        var checkpointCounts: [Int]            // painted-pixel count at each checkpoint (in frame order)
        var checkpointPixels: [Int: [UInt8]]   // BGRA buffer at each checkpoint (for the contact sheet)
        var finalPixels: [UInt8]
        var creamRef: [UInt8]                  // frame-0 far corner (5,5) — the unpainted cream reference
        var groundCornerFinal: [UInt8]         // final far corner (must == creamRef under chromatic=0)
        var earlyXY: (Int, Int)?               // a texel painted by the first checkpoint
        var earlyStillPaintedFinal: Bool       // that texel still painted at the final frame
        var perFrameCounts: [Int]              // painted-pixel count per frame (Skein.2 new-mark governor input)
    }

    /// Drive the live marks-on-top dispatch path for `frames` frames, advancing features.time by
    /// a fixed Δt each frame (so the painter moves and consecutive capsules chain exactly). Each
    /// frame: warp(prev) → overlay(this frame's swept capsule on top) → blit → read → swap.
    /// Mirrors `drawWithMVWarp`'s strandsOnTop branch (Pass 0 skipped; the ground is the clear).
    private func runPourAccumulation(
        chromatic: Float, frames: Int, width: Int, height: Int, aspect: Float, startTime: Float,
        checkpoints: Set<Int>, fx: SkeinFixture, capturePerFrame: Bool = false
    ) throws -> PourResult {
        let device = fx.ctx.device, queue = fx.ctx.commandQueue
        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: fx.ctx.pixelFormat, width: width, height: height, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard var warpTex = device.makeTexture(descriptor: fbDesc),
              var composeTex = device.makeTexture(descriptor: fbDesc),
              let blitTex = device.makeTexture(descriptor: fbDesc)
        else { throw SkeinHoldError.textureFailed }
        // Held ground IS the cream canvas clear (not black) — the D-143 fix.
        try clearTextures([warpTex, composeTex], to: fx.cream, context: fx.ctx)
        try clearTextures([blitTex], to: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1), context: fx.ctx)

        let dt: Float = 1.0 / 60.0   // fixed 60 fps step → posPrev(t−Δt) == prev frame's posNow (chaining)
        func read(_ tex: MTLTexture) -> [UInt8] {
            var px = [UInt8](repeating: 0, count: width * height * 4)
            tex.getBytes(&px, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            return px
        }
        func pxAt(_ buf: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
            let i = (y * width + x) * 4
            return Array(buf[i..<i + 4])
        }

        var creamRef: [UInt8] = []
        var checkpointCounts: [Int] = []
        var checkpointPixels: [Int: [UInt8]] = [:]
        let sortedCp = checkpoints.sorted()
        var earlyXY: (Int, Int)? = nil
        var finalPixels: [UInt8] = []
        var perFrameCounts: [Int] = []

        for frameIdx in 0..<frames {
            var features = FeatureVector(
                time: startTime + Float(frameIdx) * dt, deltaTime: dt, aspectRatio: aspect)
            guard let cmd = queue.makeCommandBuffer() else { throw SkeinHoldError.cmdBufferFailed }
            // Pass 1: identity warp holds the previous canvas (warpTex → composeTex). chromatic=0
            // + decay=1.0 ⇒ a lossless copy of every unpainted texel.
            try encodeWarp(cmd: cmd, mvWarp: fx.mvWarp, warpTex: warpTex, composeTex: composeTex,
                           features: &features, chromatic: chromatic)
            // Pass 2: marks-on-top — draw this frame's swept capsule normal-alpha onto the held canvas.
            try encodeOverlay(cmd: cmd, overlay: fx.overlay, target: composeTex, features: &features)
            // Pass 3: blit (display-only, identity post) — faithful to the live present pass.
            try encodeBlit(cmd: cmd, mvWarp: fx.mvWarp, src: composeTex, dst: blitTex,
                           post: SIMD4<Float>(0, 0, 1, 0))   // invert0 echo0 gamma1 beat0 = identity
            cmd.commit()
            cmd.waitUntilCompleted()

            let canvas = read(composeTex)
            if frameIdx == 0 { creamRef = pxAt(canvas, 5, 5) }   // far corner — never reached by the painter
            if capturePerFrame { perFrameCounts.append(countPainted(canvas, cream: creamRef)) }
            if checkpoints.contains(frameIdx) {
                checkpointPixels[frameIdx] = canvas
                checkpointCounts.append(countPainted(canvas, cream: creamRef))
                if frameIdx == sortedCp.first, earlyXY == nil {
                    earlyXY = brightestPaintedXY(canvas, w: width, h: height, cream: creamRef)
                }
            }
            if frameIdx == frames - 1 { finalPixels = canvas }
            swap(&warpTex, &composeTex)
        }

        let groundCornerFinal = finalPixels.isEmpty ? [] : pxAt(finalPixels, 5, 5)
        var earlyStill = false
        if let (ex, ey) = earlyXY, !finalPixels.isEmpty {
            earlyStill = channelSumDelta(pxAt(finalPixels, ex, ey), creamRef) > 60
        }
        return PourResult(
            checkpointFrames: sortedCp, checkpointCounts: checkpointCounts,
            checkpointPixels: checkpointPixels, finalPixels: finalPixels, creamRef: creamRef,
            groundCornerFinal: groundCornerFinal, earlyXY: earlyXY, earlyStillPaintedFinal: earlyStill,
            perFrameCounts: perFrameCounts)
    }

    // MARK: - Pass encoders (mirror the live mv_warp dispatch path)

    private func encodeWarp(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        warpTex: MTLTexture, composeTex: MTLTexture, features: inout FeatureVector, chromatic: Float
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = composeTex
        desc.colorAttachments[0].loadAction = .clear   // the 32×24 grid covers every pixel; clear is moot
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw SkeinHoldError.encoderFailed }
        enc.setRenderPipelineState(mvWarp.warpState)
        var featuresCopy = features
        enc.setVertexBytes(&featuresCopy, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stems = StemFeatures.zero
        enc.setVertexBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 1)
        var sceneUni = SceneUniforms()
        enc.setVertexBytes(&sceneUni, length: MemoryLayout<SceneUniforms>.stride, index: 2)
        enc.setFragmentTexture(warpTex, index: 0)
        var chromaticCopy = chromatic
        enc.setFragmentBytes(&chromaticCopy, length: MemoryLayout<Float>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)   // 31×23 quads
        enc.endEncoding()
    }

    /// Pass 2 of the marks-on-top path: draw the overlay (Skein's swept-capsule pour) normal-alpha
    /// onto the held/warped canvas. `loadAction = .load` preserves the warped ground (only the
    /// capsule texels are blended in), exactly as `encodeMVWarpScenePass`'s strandsOnTop branch.
    private func encodeOverlay(
        cmd: MTLCommandBuffer, overlay: MTLRenderPipelineState, target: MTLTexture,
        features: inout FeatureVector
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .load     // keep the held ground; blend the capsule on top
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw SkeinHoldError.encoderFailed }
        enc.setRenderPipelineState(overlay)
        // drawSceneGeometryOverlay binds features@0 + stems@1; skein_geometry_vertex reads features@0
        // (the painter position is f(features.time) — Path A, no per-preset buffer). Bind both for parity.
        enc.setVertexBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stems = StemFeatures.zero
        enc.setVertexBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: 1)
        enc.endEncoding()
    }

    private func encodeBlit(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        src: MTLTexture, dst: MTLTexture, post: SIMD4<Float>
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = dst
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw SkeinHoldError.encoderFailed }
        enc.setRenderPipelineState(mvWarp.blitState)
        enc.setFragmentTexture(src, index: 0)
        var post = post
        enc.setFragmentBytes(&post, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    // MARK: - Texture clear

    private func clearTextures(_ texs: [MTLTexture], to clearColor: MTLClearColor, context: MetalContext) throws {
        guard let cmd = context.commandQueue.makeCommandBuffer() else { throw SkeinHoldError.cmdBufferFailed }
        for tex in texs {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = tex
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].clearColor = clearColor
            desc.colorAttachments[0].storeAction = .store
            if let enc = cmd.makeRenderCommandEncoder(descriptor: desc) { enc.endEncoding() }
        }
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    // MARK: - Frame analysis (paint coverage, continuity, colour)

    /// Sum of absolute B/G/R differences from the cream reference (alpha ignored). White-on-cream
    /// ⇒ painted texels are bright in every channel, so a painted pixel reads as a large delta.
    private func channelSumDelta(_ p: [UInt8], _ ref: [UInt8]) -> Int {
        abs(Int(p[0]) - Int(ref[0])) + abs(Int(p[1]) - Int(ref[1])) + abs(Int(p[2]) - Int(ref[2]))
    }

    /// Coverage meter: pixels distinctly different from the cream ground (delta > 45).
    private func countPainted(_ buf: [UInt8], cream: [UInt8]) -> Int {
        let cb = Int(cream[0]), cg = Int(cream[1]), cr = Int(cream[2])
        var n = 0, i = 0
        while i < buf.count {
            if abs(Int(buf[i]) - cb) + abs(Int(buf[i + 1]) - cg) + abs(Int(buf[i + 2]) - cr) > 45 { n += 1 }
            i += 4
        }
        return n
    }

    /// The most-painted texel (max delta from cream), if any clearly on the line (delta > 60).
    private func brightestPaintedXY(_ buf: [UInt8], w: Int, h: Int, cream: [UInt8]) -> (Int, Int)? {
        let cb = Int(cream[0]), cg = Int(cream[1]), cr = Int(cream[2])
        var best = 60, bx = -1, by = -1
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let d = abs(Int(buf[i]) - cb) + abs(Int(buf[i + 1]) - cg) + abs(Int(buf[i + 2]) - cr)
                if d > best { best = d; bx = x; by = y }
            }
        }
        return bx >= 0 ? (bx, by) : nil
    }

    /// Continuity metric: size of the largest 4-connected painted component / total painted pixels.
    /// A continuous line ⇒ ≈ 1.0; gaps between capsules ⇒ multiple components ⇒ a fraction below 1.
    private func largestPaintedComponentFraction(_ buf: [UInt8], w: Int, h: Int, cream: [UInt8]) -> Float {
        let cb = Int(cream[0]), cg = Int(cream[1]), cr = Int(cream[2])
        var painted = [Bool](repeating: false, count: w * h)
        var total = 0
        for idx in 0..<(w * h) {
            let i = idx * 4
            if abs(Int(buf[i]) - cb) + abs(Int(buf[i + 1]) - cg) + abs(Int(buf[i + 2]) - cr) > 45 {
                painted[idx] = true
                total += 1
            }
        }
        guard total > 0 else { return 0 }
        var visited = [Bool](repeating: false, count: w * h)
        var largest = 0
        var stack: [Int] = []
        for start in 0..<(w * h) where painted[start] && !visited[start] {
            var size = 0
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            while let p = stack.popLast() {
                size += 1
                let x = p % w, y = p / w
                if x > 0     { let q = p - 1; if painted[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if x < w - 1 { let q = p + 1; if painted[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if y > 0     { let q = p - w; if painted[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if y < h - 1 { let q = p + w; if painted[q] && !visited[q] { visited[q] = true; stack.append(q) } }
            }
            if size > largest { largest = size }
        }
        return Float(largest) / Float(total)
    }

    // MARK: - Pour-line corridor (Skein.2: isolate the LINE from the splatter satellites)

    /// Mirror of `skeinPainterPos` in Skein.metal (the Skein.1 closed-form trajectory). Kept in
    /// sync by review — the static-source guard asserts the shader still declares `skeinPainterPos`.
    /// Used ONLY to build the pour-LINE corridor so the Skein.1 continuity invariant can be checked
    /// on the line alone: Skein.2 adds disconnected SATELLITES by design, so whole-canvas continuity
    /// is intentionally < 1 now (the line is still gap-free; the satellites are separate components).
    private static func skeinPainterPos(_ t: Float) -> SIMD2<Float> {
        let x = 0.5 + 0.300 * sin(0.220 * t + 0.0)
                    + 0.110 * sin(0.950 * t + 1.7)
                    + 0.045 * sin(2.300 * t + 4.2)
        let y = 0.5 + 0.280 * cos(0.190 * t + 2.3)
                    + 0.120 * cos(1.070 * t + 5.1)
                    + 0.040 * cos(2.620 * t + 0.9)
        return SIMD2(x, y)
    }

    /// Pour-LINE continuity: build a corridor (union of discs of radius `rV` uv-units around the
    /// densely-sampled trajectory over [t0, t1]) and return the largest-4-connected-component
    /// fraction of painted pixels INSIDE it, plus the painted-in / painted-outside counts. Far
    /// satellites (outside the corridor) are excluded, so this is the Skein.1 "no gaps in the line"
    /// check, preserved under the Skein.2 splatter. (Test runs at aspect 1.0, so uv == fragment q.)
    private func pourLineCorridor(
        _ buf: [UInt8], w: Int, h: Int, cream: [UInt8], t0: Float, t1: Float, rV: Float
    ) -> (continuity: Float, inCorridor: Int, outside: Int) {
        var corridor = [Bool](repeating: false, count: w * h)
        let steps = max(1, Int((t1 - t0) * 600.0))   // ~600 samples/s — far finer than the 60 fps line spacing
        for s in 0...steps {
            let t = t0 + (t1 - t0) * Float(s) / Float(steps)
            let p = Self.skeinPainterPos(t)
            // Render-target row 0 = TOP = clip y +1 = uv.y 1.0, so pixel row → uv.y is FLIPPED.
            let minX = max(0, Int((p.x - rV) * Float(w)) - 1)
            let maxX = min(w - 1, Int((p.x + rV) * Float(w)) + 1)
            let minY = max(0, Int((1.0 - p.y - rV) * Float(h)) - 1)
            let maxY = min(h - 1, Int((1.0 - p.y + rV) * Float(h)) + 1)
            guard minX <= maxX, minY <= maxY else { continue }
            for py in minY...maxY {
                for px in minX...maxX {
                    let dx = (Float(px) + 0.5) / Float(w) - p.x
                    let dy = (1.0 - (Float(py) + 0.5) / Float(h)) - p.y
                    if dx * dx + dy * dy <= rV * rV { corridor[py * w + px] = true }
                }
            }
        }
        let cb = Int(cream[0]), cg = Int(cream[1]), cr = Int(cream[2])
        var painted = [Bool](repeating: false, count: w * h)
        var inC = 0, outC = 0
        for idx in 0..<(w * h) {
            let i = idx * 4
            if abs(Int(buf[i]) - cb) + abs(Int(buf[i + 1]) - cg) + abs(Int(buf[i + 2]) - cr) > 45 {
                painted[idx] = true
                if corridor[idx] { inC += 1 } else { outC += 1 }
            }
        }
        guard inC > 0 else { return (0, 0, outC) }
        var visited = [Bool](repeating: false, count: w * h)
        var largest = 0
        var stack: [Int] = []
        for start in 0..<(w * h) where painted[start] && corridor[start] && !visited[start] {
            var size = 0
            stack.removeAll(keepingCapacity: true)
            stack.append(start); visited[start] = true
            while let p = stack.popLast() {
                size += 1
                let x = p % w, y = p / w
                if x > 0     { let q = p - 1; if painted[q] && corridor[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if x < w - 1 { let q = p + 1; if painted[q] && corridor[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if y > 0     { let q = p - w; if painted[q] && corridor[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if y < h - 1 { let q = p + w; if painted[q] && corridor[q] && !visited[q] { visited[q] = true; stack.append(q) } }
            }
            if size > largest { largest = size }
        }
        return (Float(largest) / Float(inC), inC, outC)
    }

    /// Skein.2 splatter analysis against the line trajectory [t0,t1].
    ///  - haloNear/Mid/Far: painted-pixel COUNT in three distance bands OUTSIDE the line corridor
    ///    (the dense-near → sparse-far satellite-halo signature: near > far).
    ///  - satelliteComponents: # of disconnected painted blobs (≥2 px) outside the corridor — the
    ///    "distinct dots, not a merged froth" count (responds to viscosity: thin throws more).
    ///  - meanSatDist: mean distance (uv-units) of outside-painted pixels from the line — thin paint
    ///    flings satellites WIDER, so this is the cleanest trajectory-robust viscosity discriminator.
    ///  - minChannel: smallest single channel over the whole canvas. Paint only brightens cream→white
    ///    (normal-alpha), so nothing drops below cream's darkest channel → proves NOT additive (no mud).
    private func splatterHaloAndSatellites(
        _ buf: [UInt8], w: Int, h: Int, cream: [UInt8], t0: Float, t1: Float, corridorRV: Float
    ) -> (haloNear: Int, haloMid: Int, haloFar: Int, satellites: Int, meanSatDist: Float, minChannel: Int) {
        let steps = max(1, Int((t1 - t0) * 400.0))
        var samples: [SIMD2<Float>] = []
        samples.reserveCapacity(steps + 1)
        for s in 0...steps { samples.append(Self.skeinPainterPos(t0 + (t1 - t0) * Float(s) / Float(steps))) }
        let cb = Int(cream[0]), cg = Int(cream[1]), cr = Int(cream[2])
        var near = 0, mid = 0, far = 0, minCh = 255
        var distSum: Float = 0
        var outside = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let b = Int(buf[i]), g = Int(buf[i + 1]), r = Int(buf[i + 2])
                if b < minCh { minCh = b }; if g < minCh { minCh = g }; if r < minCh { minCh = r }
                if abs(b - cb) + abs(g - cg) + abs(r - cr) <= 45 { continue }   // not painted
                // Render-target row 0 = TOP = uv.y 1.0 → flip pixel row to painter uv-space.
                let ux = (Float(x) + 0.5) / Float(w), uy = 1.0 - (Float(y) + 0.5) / Float(h)
                var best = Float.greatestFiniteMagnitude
                for p in samples { let dx = ux - p.x, dy = uy - p.y; let d2 = dx * dx + dy * dy; if d2 < best { best = d2 } }
                let d = best.squareRoot()
                if d <= corridorRV { continue }   // the line itself, not a satellite
                outside[y * w + x] = true
                distSum += d
                if d < 0.06 { near += 1 } else if d < 0.11 { mid += 1 } else { far += 1 }
            }
        }
        let outCount = near + mid + far
        // Count disconnected satellite components (≥2 px, ignoring single-pixel AA specks).
        var visited = [Bool](repeating: false, count: w * h)
        var comps = 0
        var stack: [Int] = []
        for start in 0..<(w * h) where outside[start] && !visited[start] {
            var size = 0
            stack.removeAll(keepingCapacity: true)
            stack.append(start); visited[start] = true
            while let p = stack.popLast() {
                size += 1
                let x = p % w, y = p / w
                if x > 0     { let q = p - 1; if outside[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if x < w - 1 { let q = p + 1; if outside[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if y > 0     { let q = p - w; if outside[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if y < h - 1 { let q = p + w; if outside[q] && !visited[q] { visited[q] = true; stack.append(q) } }
            }
            if size >= 2 { comps += 1 }
        }
        return (near, mid, far, comps, outCount > 0 ? distSum / Float(outCount) : 0, minCh)
    }

    /// Find a strongly-painted SATELLITE pixel (delta > 80, clearly outside the line corridor) for
    /// the bake/hold check. Returns nil if none — i.e. no splatter was laid in this window.
    private func firstSatellitePixel(
        _ buf: [UInt8], w: Int, h: Int, cream: [UInt8], t0: Float, t1: Float, corridorRV: Float
    ) -> (Int, Int)? {
        let steps = max(1, Int((t1 - t0) * 300.0))
        var samples: [SIMD2<Float>] = []
        for s in 0...steps { samples.append(Self.skeinPainterPos(t0 + (t1 - t0) * Float(s) / Float(steps))) }
        let cb = Int(cream[0]), cg = Int(cream[1]), cr = Int(cream[2])
        for y in 2..<(h - 2) {
            for x in 2..<(w - 2) {
                let i = (y * w + x) * 4
                if abs(Int(buf[i]) - cb) + abs(Int(buf[i + 1]) - cg) + abs(Int(buf[i + 2]) - cr) <= 80 { continue }
                let ux = (Float(x) + 0.5) / Float(w), uy = 1.0 - (Float(y) + 0.5) / Float(h)   // flip row → uv.y
                var best = Float.greatestFiniteMagnitude
                for p in samples { let dx = ux - p.x, dy = uy - p.y; best = min(best, dx * dx + dy * dy) }
                if best.squareRoot() > corridorRV + 0.012 { return (x, y) }
            }
        }
        return nil
    }

    /// Whether any texel is white (the pour colour) — min(B,G,R) ≥ 235.
    private func hasWhiteTexel(_ buf: [UInt8]) -> Bool {
        var i = 0
        while i < buf.count {
            if buf[i] >= 235 && buf[i + 1] >= 235 && buf[i + 2] >= 235 { return true }
            i += 4
        }
        return false
    }

    // BGRA byte order. "Black" = all channels near 0; "cream" = bright with R≳G≳B (warm).
    private func isBlack(_ p: [UInt8]) -> Bool { p[0] < 12 && p[1] < 12 && p[2] < 12 }
    private func isCreamish(_ p: [UInt8]) -> Bool {
        let b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
        return r > 140 && g > 120 && b > 100 && r >= g && g >= b   // warm, bright
    }

    // MARK: - Contact-sheet PNG writers

    private func writeBGRAToPNG(_ bgra: [UInt8], w: Int, h: Int, url: URL) throws {
        var rgba = [UInt8](repeating: 0, count: bgra.count)
        for i in stride(from: 0, to: bgra.count, by: 4) {
            rgba[i] = bgra[i + 2]; rgba[i + 1] = bgra[i + 1]; rgba[i + 2] = bgra[i]; rgba[i + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: w * 4, space: cs, bitmapInfo: CGBitmapInfo(rawValue: info),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw SkeinHoldError.encoderFailed }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw SkeinHoldError.encoderFailed }
    }

    /// Tile checkpoint frames into one horizontal strip (dark-gray separators) for at-a-glance review.
    private func writeMontage(_ tiles: [[UInt8]], tileW: Int, tileH: Int, url: URL) throws {
        guard !tiles.isEmpty else { return }
        let sep = 4
        let bigW = tiles.count * tileW + (tiles.count - 1) * sep
        let bigH = tileH
        var out = [UInt8](repeating: 40, count: bigW * bigH * 4)
        for i in stride(from: 3, to: out.count, by: 4) { out[i] = 255 }   // opaque
        for (t, tile) in tiles.enumerated() {
            let x0 = t * (tileW + sep)
            for y in 0..<tileH {
                for x in 0..<tileW {
                    let src = (y * tileW + x) * 4
                    let dst = (y * bigW + (x0 + x)) * 4
                    out[dst] = tile[src]; out[dst + 1] = tile[src + 1]
                    out[dst + 2] = tile[src + 2]; out[dst + 3] = 255
                }
            }
        }
        try writeBGRAToPNG(out, w: bigW, h: bigH, url: url)
    }

    private func makeOutputDir() throws -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let stamp = iso.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let url = URL(fileURLWithPath: "/tmp/skein_pour_diag/\(stamp)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func shaderURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // /Presets/
            .deletingLastPathComponent()   // /PhospheneEngineTests/
            .deletingLastPathComponent()   // /Tests/
            .deletingLastPathComponent()   // /PhospheneEngine/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("PhospheneEngine/Sources/Presets/Shaders/\(name)")
    }
}

private enum SkeinHoldError: Error {
    case textureFailed
    case bufferFailed
    case cmdBufferFailed
    case encoderFailed
}
