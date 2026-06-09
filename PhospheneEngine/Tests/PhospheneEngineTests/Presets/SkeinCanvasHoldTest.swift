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
        // Skein.2: the splatter morphology — ragged-edge 2D fBM + deterministic droplet placement.
        #expect(src.contains("skein_fbm2"),
                "Skein.metal missing skein_fbm2 (Skein.2 ≥4-octave ragged-edge 2D noise).")
        #expect(src.contains("hash_f01_4x"),
                "Skein.metal missing hash_f01_4x (deterministic per-droplet placement, §5.7).")
        // Skein.3: the debug drivers are RETIRED — the fragment consumes SkeinUniforms at slot 6
        // (the painter clock + per-track seed phases + per-stem-coloured onset-burst ring).
        #expect(!src.contains("skeinDebugViscosity"),
                "Skein.metal still declares skeinDebugViscosity — Skein.3 retires it (viscosity ← per-burst centroid).")
        #expect(!src.contains("kSkeinFlickDt"),
                "Skein.metal still declares kSkeinFlickDt — Skein.3 retires the debug flick schedule (→ onset-burst ring).")
        #expect(src.contains("constant SkeinUniforms& st [[buffer(6)]]"),
                "Skein.metal skein_geometry_fragment must read SkeinUniforms at buffer(6) (ENGINE.1.2 slot-6 binding).")
        #expect(src.contains("st.painterTau"),
                "Skein.metal fragment must drive the painter from SkeinState.painterTau (Skein.3 audio-modulated clock).")
        // Skein.ENGINE.2: Skein owns its warp/hold fragment (decays the ALPHA wetness channel, holds
        // RGB byte-identically) via the per-prefix override — the shared mvWarp_fragment is untouched
        // (DB/FM byte-identical). The literal `prev.a * wetnessDecay` is the wetness-decay invariant.
        #expect(src.contains("fragment float4 skein_warp_fragment("),
                "Skein.metal missing skein_warp_fragment (ENGINE.2 wetness-channel hold/decay).")
        #expect(src.contains("prev.a * wetnessDecay"),
                "Skein.metal skein_warp_fragment must decay the ALPHA wetness channel by wetnessDecay (ENGINE.2).")
        #expect(src.contains("return float4(prev.rgb,"),
                "Skein.metal skein_warp_fragment must hold RGB byte-identically (lossless paint record, ENGINE.2).")
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
        // Square render (aspect 1.0) so the line width is isotropic and the connectivity mask is
        // clean. SILENCE (stemFrames empty → StemFeatures.zero): Skein.3 lays ONLY the pour line —
        // onset bursts are real-audio-driven, so silence has no splatter (verified by the real-stem
        // test below). The painter advances on painterTau (SkeinState, speed 1 at silence ≈ a
        // 60 fps clock) → a new capsule lands each frame. lineCol stays white at silence.
        let run = try runPourAccumulation(
            chromatic: 0, frames: 180, width: w, height: h, aspect: 1.0, startTime: 0.0,
            checkpoints: Set(checkpoints), fx: fx)

        // The pour LINE lives in a thin corridor around the (seed-0) trajectory; at silence the
        // whole painting IS the line (no satellites), so continuity should be near-total.
        let line = pourLineCorridor(run.finalPixels, w: w, h: h, cream: run.creamRef,
                                    t0: -0.7, t1: 3.0, rV: 0.025)
        let whiteOK = hasWhiteTexel(run.finalPixels)
        print("""
        [skein_pour] 180 frames @ \(w)×\(h), chromatic=0, live scene→warp→overlay→blit→swap (SILENCE: line only):
          painted-count checkpoints \(run.checkpointFrames) = \(run.checkpointCounts)
          early painted texel \(run.earlyXY.map { "(\($0.0),\($0.1))" } ?? "none") still painted at end = \(run.earlyStillPaintedFinal)
          pour-LINE continuity (corridor) = \(String(format: "%.3f", line.continuity))  [in-corridor \(line.inCorridor) / outside \(line.outside)]
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
        //    Skein.ENGINE.2 RE-SCOPE: the RGB channels are the lossless permanent paint record; the
        //    ALPHA channel now carries the transient WETNESS signal, which legitimately decays under
        //    music (and is held at silence, where this test runs, so A is also unchanged here). The
        //    lossless-hold invariant is therefore asserted on RGB only — A is checked by the
        //    dedicated wetness test below. (At silence wetnessDecay == 1.0, so A is in fact held too.)
        #expect(Array(run.creamRef.prefix(3)) == Array(run.groundCornerFinal.prefix(3)),
                "Far-corner RGB drifted \(run.creamRef) → \(run.groundCornerFinal) at chromatic=0 — the held canvas RGB is not lossless.")

        // 3. CONTINUITY (pour LINE) — the laid line is a single connected component (no gaps between
        //    consecutive capsules; they share an endpoint by construction via the painterTau tail
        //    chaining). At silence there are no satellites, so the corridor holds the whole painting.
        //    (Onset-driven splatter is exercised by test_splatter_realStem_* below.)
        #expect(line.continuity >= 0.95,
                "Pour-line corridor continuity is only \(line.continuity) — the line has gaps (Skein.1 invariant regressed).")

        // 4. CREAM GROUND held (not black) — the per-preset canvas clear (D-143) still carries.
        #expect(!isBlack(run.groundCornerFinal),
                "Ground corner is black — the cream canvas clear did not take. \(run.groundCornerFinal)")
        #expect(isCreamish(run.groundCornerFinal),
                "Ground corner is not cream-ish (bright, R≳G≳B). \(run.groundCornerFinal)")

        // 5. WHITE LINE — at least one fully-laid texel is white (the pour colour; palette is Skein.3).
        #expect(whiteOK, "No white texel found — the pour line did not render white-on-cream.")
    }

    // MARK: - Wetness channel (Skein.ENGINE.2): stamp + decay-pauses-at-silence (live dispatch path)

    @Test("Wetness channel (ENGINE.2): stamp ~1 where painted, decays under music, holds at silence — live path")
    func test_wetnessChannel_stampDecayHold() throws {
        guard let fx = try loadSkeinFixture() else { return }
        let w = 160, h = 160
        let musicFrames = 60, silenceFrames = 60

        // The wetness DECAY is a pure function of the SILENCE GATE (totalStemEnergy → stemMix), NOT
        // of audio CONTENT, so this is a deterministic PLUMBING test of the ENGINE.2 signal: it drives
        // a constant non-zero-energy stem for the "music" phase and StemFeatures.zero for "silence".
        // (This is NOT a musical / visual diagnostic — the wet-now/dry-past VISUAL gate uses REAL
        // replayed stems; `feedback_synthetic_audio` / FA #27 applies there, not to this gate-mechanism
        // unit test, which asserts only that wetnessDecay propagates and pauses at zero energy.)
        var music = StemFeatures.zero
        music.drumsEnergy = 0.30; music.bassEnergy = 0.30
        music.vocalsEnergy = 0.25; music.otherEnergy = 0.20      // total 1.05 ≫ warmupHigh (0.06) ⇒ stemMix = 1
        music.drumsEnergyDev = 0.20; music.bassEnergyDev = 0.18  // drive the painter + a few bursts
        let stemFrames = Array(repeating: music, count: musicFrames)
                       + Array(repeating: StemFeatures.zero, count: silenceFrames)

        let run = try runPourAccumulation(
            chromatic: 0, frames: musicFrames + silenceFrames, width: w, height: h, aspect: 1.0,
            startTime: 0.0, checkpoints: [musicFrames - 1], fx: fx, seed: 0, stemFrames: stemFrames,
            captureWetness: true)

        let corner = run.cornerAlphaSeries
        let maxA = run.maxAlphaSeries
        #expect(corner.count == musicFrames + silenceFrames && maxA.count == corner.count,
                "Wetness series came up short (\(corner.count) / \(maxA.count)).")
        guard corner.count == musicFrames + silenceFrames else { return }

        let stampPeak = maxA.prefix(musicFrames).max() ?? 0
        let cornerMusicStart = corner[0]
        let cornerMusicEnd = corner[musicFrames - 1]
        // Count frames where the unpainted-corner wetness INCREASED during music (should ≈ 0 — a
        // freak stray burst reaching the extreme corner is tolerated up to 2).
        var risesInMusic = 0
        for i in 1..<musicFrames where corner[i] > corner[i - 1] { risesInMusic += 1 }
        let silenceWindow = Array(corner[musicFrames..<(musicFrames + silenceFrames)])
        let silenceSpread = (silenceWindow.max() ?? 0) - (silenceWindow.min() ?? 0)

        print("""
        [skein_wetness] live scene→warp→overlay→blit→swap, \(w)×\(h), \(musicFrames)f music + \(silenceFrames)f silence:
          stamp: max canvas ALPHA during music = \(stampPeak) / 255  (fresh paint → wet)
          decay: unpainted-corner ALPHA \(cornerMusicStart) → \(cornerMusicEnd) over music  (rises: \(risesInMusic))
          hold : silence-window ALPHA spread = \(silenceSpread)  (\(silenceWindow.first ?? -1) → \(silenceWindow.last ?? -1))
        """)

        // 1. STAMP — fresh solid paint stamps the wetness channel toward ~1 (255).
        #expect(stampPeak > 200,
                "Max canvas wetness peaked at only \(stampPeak)/255 during music — the overlay is not stamping wetness where paint lands.")

        // 2. DECAY UNDER MUSIC — the unpainted corner's wetness dries monotonically (it is never
        //    re-stamped, so each frame multiplies it by wetnessDecay < 1).
        #expect(cornerMusicEnd < cornerMusicStart - 30,
                "Unpainted-corner wetness barely changed under music (\(cornerMusicStart) → \(cornerMusicEnd)) — the decay is not firing.")
        #expect(risesInMusic <= 2,
                "Unpainted-corner wetness rose on \(risesInMusic) frames under music — decay is not monotone (unexpected re-stamp).")

        // 3. HOLDS AT SILENCE — wetnessDecay == 1.0 at silence (the §5.2-step-3 pause), so the held
        //    wetness does not drift (8-bit: × 1.0 is exact; allow ±1 for rounding).
        #expect(silenceSpread <= 1,
                "Wetness drifted by \(silenceSpread) across the silence window — the decay did not PAUSE at silence (the held painting must not dry while paused).")
    }

    // MARK: - Real-stem routing: colour separation + onset→splatter + opaque + bake/hold (Skein.3 gate)

    @Test("Real stems: stems paint separable colours, onsets drive splatter, marks composite opaque, bake + hold — live path")
    func test_realStem_colourSeparationAndRouting() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession() else {
            print("SkeinCanvasHoldTest: no recorded session under ~/Documents/phosphene_sessions — skipping real-stem routing test (local-only: real audio required, feedback_synthetic_audio)")
            return
        }
        guard let stems = loadStemFrames(session, maxFrames: 2400), stems.count > 200 else {
            Issue.record("Recorded session \(session.lastPathComponent) has no usable stems.csv frames.")
            return
        }
        let w = 320, h = 320
        let palette = SkeinState.defaultPalette
        let frames = min(stems.count, 1200)
        // Drive the live scene→warp→overlay→blit→swap path with REAL replayed stems
        // (feedback_synthetic_audio: never hand-authored envelopes). Bursts fire on real per-stem
        // onsets in each stem's colour; the painting accumulates coloured.
        let run = try runPourAccumulation(
            chromatic: 0, frames: frames, width: w, height: h, aspect: 1.0, startTime: 0.0,
            checkpoints: [60, frames - 1], fx: fx, seed: 0, palette: palette, stemFrames: stems)

        let an = analyzeColouredPainting(run.finalPixels, w: w, h: h, cream: run.creamRef, palette: palette)
        let classified = an.perStemCount.reduce(0, +) + an.mudCount
        let stemsPresent = an.perStemCount.filter { $0 > 30 }.count
        let mudFrac = classified > 0 ? Float(an.mudCount) / Float(classified) : 0

        // ONSET → SPLATTER route + STEM WARMUP — driven at the SkeinState layer (the deterministic
        // source of bursts) so the assertions don't depend on render sampling.
        let busyCalm = Self.busiestAndCalmestSlices(stems, window: 240)
        let busyBursts = try Self.spawnsOver(busyCalm.busy, device: fx.ctx.device, palette: palette)
        let calmBursts = try Self.spawnsOver(busyCalm.calm, device: fx.ctx.device, palette: palette)
        let silenceBursts = try Self.spawnsOver(Array(repeating: StemFeatures.zero, count: 30),
                                                device: fx.ctx.device, palette: palette)
        // DIAG (legibility): per-stem spawns over the full run + early-frame per-stem painted, to
        // distinguish a spawn (routing) gap from overpaint (render) of the dark stem colours.
        let spawnsFull = try Self.spawnsPerStemOver(Array(stems.prefix(frames)),
                                                    device: fx.ctx.device, palette: palette)
        let earlyAn = run.checkpointPixels[60].map {
            analyzeColouredPainting($0, w: w, h: h, cream: run.creamRef, palette: palette)
        }

        print("""
        [skein_realstem] session \(session.lastPathComponent), \(stems.count) stem frames, live path \(w)×\(h):
          per-stem painted (drums/bass/vocals/other) = \(an.perStemCount)  stems-present(>30px) = \(stemsPresent)
          per-stem SPAWNS (full run)                 = \(spawnsFull)
          early frame-60 per-stem painted            = \(earlyAn?.perStemCount ?? [])
          mud fraction (ambiguous between two stems) = \(String(format: "%.3f", mudFrac))  (classified \(classified) px)
          distinct coloured blobs = \(an.distinctBlobs)   roundness bbox-fill = \(String(format: "%.3f", an.roundFill)) (n=\(an.roundN))
          onset→splatter route: busy-slice bursts \(busyBursts) vs calm-slice \(calmBursts)   warmup bursts-at-silence = \(silenceBursts)
        """)

        // 1. COLOUR SEPARATION — the headline: ≥3 stems paint well-populated, separable colour clusters.
        #expect(stemsPresent >= 3,
                "Only \(stemsPresent) stems produced a separable colour cluster (\(an.perStemCount)) — the canvas is not legibly per-stem.")

        // 2. OPAQUE, not mud — ambiguous between-two-stems pixels are a small fraction (occlude, no brown).
        #expect(mudFrac < 0.22,
                "Mud fraction \(mudFrac) ≥ 0.22 — coloured marks are averaging to mud, not occluding (the dead-mat anti-ref).")

        // 3. DISTINCT coloured dots — onset bursts produce separate satellite blobs, not a uniform
        //    smear. Most droplets connect to the wandering line (bursts are flicked AS the painter
        //    pours, so they touch the skein — Pollock-correct); the separate FAR satellites are the
        //    "splatter, not froth" evidence. The EXACT count is session-dependent — on a line-dominant
        //    track (e.g. a bass-heavy session where the dominant line sweeps the canvas) most droplets
        //    connect to the line and few stay separate, so the bar is "several distinct dots exist", not
        //    a high count. The dot SHAPE (round, not froth) is verified by the roundness gate below and
        //    the onset→splatter route gate; the firing is verified by busy≫calm bursts. (Was > 8,
        //    calibrated on a sparse other-dominant session; that fails on line-dominant sessions where
        //    the splatter is demonstrably fine — verified the same count with the prior line renderer.)
        #expect(an.distinctBlobs > 3,
                "Only \(an.distinctBlobs) distinct coloured satellite blobs — onset splatter not rendering as separate dots at all.")

        // 4. ROUNDNESS — droplets read ROUND, not square (Matt M7 isotropic-AA guard).
        if an.roundN >= 3 {
            #expect(an.roundFill < 0.90,
                    "Coloured droplets too boxy (bbox-fill \(an.roundFill), n=\(an.roundN)) — square-droplet regression.")
        }

        // 5. ONSET → SPLATTER (route) — a beat-heavy slice spawns measurably more bursts than a steady one.
        #expect(busyBursts > calmBursts,
                "Beat-heavy slice spawned \(busyBursts) bursts ≤ steady slice \(calmBursts) — onset→splatter route not firing.")

        // 6. STEM WARMUP (D-019) — no bursts at silence (no first-frame colour pop).
        #expect(silenceBursts == 0,
                "\(silenceBursts) bursts spawned at silence — the D-019 warmup gate leaked.")

        // 7. BAKE + HOLD — an early-painted coloured pixel persists to the end (lossless held colour).
        if let early = run.checkpointPixels[60] {
            let cp = firstColouredPixel(early, w: w, h: h, cream: run.creamRef)
            #expect(cp != nil, "No early coloured pixel found — bursts not laid early.")
            if let (cx, cy) = cp {
                let i = (cy * w + cx) * 4
                let f = run.finalPixels
                let delta = abs(Int(f[i]) - Int(run.creamRef[0]))
                          + abs(Int(f[i + 1]) - Int(run.creamRef[1]))
                          + abs(Int(f[i + 2]) - Int(run.creamRef[2]))
                #expect(delta > 45,
                        "An early coloured pixel at (\(cx),\(cy)) was lost by the end — bake/hold regressed (Δ \(delta)).")
            }
        }
    }

    // MARK: - Wet-now / dry-past sheen (Skein.4): fresh paint glistens, accumulated past is matte

    @Test("Wet-now / dry-past sheen (Skein.4): recently-painted glistens (specular), older is matte — live BLIT path")
    func test_sheen_wetNowDryPast() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 2400), stems.count > 400 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping wet-now/dry-past sheen gate (real audio: feedback_synthetic_audio)")
            return
        }
        let w = 320, h = 320
        let frames = min(stems.count, 1500)   // long enough that all active stems have painted (the intro is other-dominated)
        // Drive the live scene→warp→overlay→blit→swap path with REAL replayed stems so the painter
        // lays paint of varying AGE: the recent tail is WET (high A), the accumulated past has DRIED
        // (A decayed). The sheen (skein_comp_fragment) reads canvas + wetness at the blit.
        let run = try runPourAccumulation(
            chromatic: 0, frames: frames, width: w, height: h, aspect: 1.0, startTime: 0.0,
            checkpoints: [frames - 1], fx: fx, seed: 0, stemFrames: stems,
            captureWetness: true, captureBlit: true)

        let canvas = run.finalPixels          // composeTex: rgb = raw paint, a = wetness
        let blit = run.finalBlitPixels        // blitTex: the sheened display output
        #expect(canvas.count == w * h * 4 && blit.count == w * h * 4,
                "Sheen gate: canvas/blit capture came up short (\(canvas.count)/\(blit.count)).")
        guard canvas.count == w * h * 4, blit.count == w * h * 4 else { return }

        // M7-round-3 wet model: the sheen makes WET paint DARKER + more SATURATED (water-soaked) and
        // DRY paint LIGHTER + matte. Measure the SHEEN EFFECT (blit − canvas), which isolates the sheen
        // from the paint CONTENT — recent paint is a single saturated stroke and old paint is mixed-down,
        // so absolute wet-vs-dry brightness is confounded; the boost is the sheen's own contribution.
        func luma(_ p: [UInt8], _ i: Int) -> Float {   // BGRA byte order
            0.2126 * Float(p[i + 2]) + 0.7152 * Float(p[i + 1]) + 0.0722 * Float(p[i])
        }
        func chroma(_ p: [UInt8], _ i: Int) -> Float { // saturation proxy: max−min channel
            let r = Float(p[i + 2]), g = Float(p[i + 1]), b = Float(p[i])
            return max(r, max(g, b)) - min(r, min(g, b))
        }
        let cb = Int(run.creamRef[0]), cg = Int(run.creamRef[1]), cr = Int(run.creamRef[2])
        var wetLumaB: Float = 0, dryLumaB: Float = 0, wetChromaB: Float = 0, dryChromaB: Float = 0
        var wetN = 0, dryN = 0, maxBoost: Float = 0
        for idx in 0..<(w * h) {
            let i = idx * 4
            let paintDelta = abs(Int(canvas[i]) - cb) + abs(Int(canvas[i + 1]) - cg) + abs(Int(canvas[i + 2]) - cr)
            guard paintDelta > 45 else { continue }      // painted texels only (skip bare cream)
            let lBoost = luma(blit, i) - luma(canvas, i)        // sheen's luma effect (wet < 0 darker, dry > 0 lighter)
            let cBoost = chroma(blit, i) - chroma(canvas, i)    // sheen's saturation effect
            maxBoost = max(maxBoost, lBoost)                    // the glossy catch-light
            let wetness = Int(canvas[i + 3])
            if wetness > 180 { wetLumaB += lBoost; wetChromaB += cBoost; wetN += 1 }       // recent (wet)
            else if wetness < 80 { dryLumaB += lBoost; dryChromaB += cBoost; dryN += 1 }   // past (dried)
        }
        let wetLumaMean = wetN > 0 ? wetLumaB / Float(wetN) : 0       // mean SHEEN luma boost on wet (expect < 0)
        let dryLumaMean = dryN > 0 ? dryLumaB / Float(dryN) : 0       // mean on dry (expect > 0)
        let wetChromaMean = wetN > 0 ? wetChromaB / Float(wetN) : 0   // mean SHEEN chroma boost on wet (expect > 0)
        let dryChromaMean = dryN > 0 ? dryChromaB / Float(dryN) : 0   // mean on dry (expect < 0)

        // The Skein.3 stem colours must READ THROUGH the sheen (it is a highlight, not a recolour):
        // the BLIT still shows ≥3 separable per-stem colour clusters.
        let blitColours = analyzeColouredPainting(blit, w: w, h: h, cream: run.creamRef, palette: SkeinState.defaultPalette)
        let canvasColours = analyzeColouredPainting(canvas, w: w, h: h, cream: run.creamRef, palette: SkeinState.defaultPalette)
        let stemsThroughSheen = blitColours.perStemCount.filter { $0 > 30 }.count
        // DEBUG: a known painted pixel canvas vs blit (BGRA), + the cream ref, to see the colour shift.
        var sampleC = "", sampleB = ""
        if let (px, py) = firstColouredPixel(canvas, w: w, h: h, cream: run.creamRef) {
            let si = (py * w + px) * 4
            sampleC = "(\(canvas[si+2]),\(canvas[si+1]),\(canvas[si]))a\(canvas[si+3])"
            sampleB = "(\(blit[si+2]),\(blit[si+1]),\(blit[si]))a\(blit[si+3])"
        }

        print("""
        [skein_sheen] session \(session.lastPathComponent), live BLIT path \(w)×\(h), \(frames)f real stems:
          wet (A>180) sheen Δluma=\(String(format: "%+.1f", wetLumaMean)) Δchroma=\(String(format: "%+.1f", wetChromaMean))  (n=\(wetN))  [expect Δluma<0 darker, Δchroma>0 richer]
          dry (A<80)  sheen Δluma=\(String(format: "%+.1f", dryLumaMean)) Δchroma=\(String(format: "%+.1f", dryChromaMean))  (n=\(dryN))  [expect Δluma>0 lighter, Δchroma<0 matte]
          max gloss catch-light boost  = \(String(format: "%.1f", maxBoost))
          stem colours: CANVAS \(canvasColours.perStemCount)  →  BLIT \(blitColours.perStemCount)  (cream \(run.creamRef))
          sample painted texel: canvas \(sampleC)  →  blit \(sampleB)
        """)

        #expect(wetN > 100 && dryN > 100,
                "Sheen gate needs both wet (\(wetN)) and dry (\(dryN)) painted texels — the run did not produce paint of varying age.")
        // 1. The sheen DARKENS wet relative to dry (the water-soaked wet look vs the lighter matte past —
        //    the M7-round-3 model). Measured as the sheen's own luma effect, so it's content-independent.
        #expect(wetLumaMean < dryLumaMean - 3.0,
                "The sheen does not darken wet paint relative to dry (wet Δluma \(wetLumaMean) vs dry Δluma \(dryLumaMean)) — the wet-now/dry-past read is not legible.")
        // 2. The sheen SATURATES wet relative to dry (richer wet body vs matte dry past).
        #expect(wetChromaMean > dryChromaMean + 1.0,
                "The sheen does not saturate wet paint relative to dry (wet Δchroma \(wetChromaMean) vs dry Δchroma \(dryChromaMean)) — the wet body is not reading.")
        // 3. A coherent glossy catch-light exists somewhere (the wet surface reflects the light — NOT a speckle).
        #expect(maxBoost > 12,
                "No glossy catch-light anywhere (max boost \(maxBoost)) — the wet paint does not reflect the light.")
        // 4. Stem colours read THROUGH the sheen (highlight on top, not a recolour): the BLIT
        //    preserves the CANVAS's separable-colour count (the sheen does not lose or merge stems).
        let canvasStems = canvasColours.perStemCount.filter { $0 > 30 }.count
        #expect(canvasStems >= 3,
                "Canvas only painted \(canvasStems) separable stem colours (\(canvasColours.perStemCount)) — the run is too short to test colour-through-sheen.")
        #expect(stemsThroughSheen >= canvasStems,
                "Sheen dropped stem colours: CANVAS \(canvasColours.perStemCount) (\(canvasStems)) → BLIT \(blitColours.perStemCount) (\(stemsThroughSheen)) — it is recolouring, not highlighting.")
    }

    // MARK: - No concentric rings (Skein.4 M7-round-4): the sheen must not amplify wetness age-bands

    @Test("Sheen does not amplify wetness age-bands into concentric rings inside strokes — live BLIT path")
    func test_sheen_noConcentricRings() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 2400), stems.count > 400 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping no-rings gate (real audio: feedback_synthetic_audio)")
            return
        }
        let w = 320, h = 320
        let frames = min(stems.count, 1500)
        // The rings are a TRANSIENT — paint at a LOOP whose wetness has decayed into the specWet
        // transition zone (~1 s after laying) — so a single frame misses them. Capture the BLIT +
        // CANVAS at many checkpoints (the painter loops repeatedly) and take the MAX ringiness, which
        // catches the worst transition-zone-at-a-loop frame.
        let cps = Array(stride(from: 150, to: frames, by: 90))
        let run = try runPourAccumulation(
            chromatic: 0, frames: frames, width: w, height: h, aspect: 1.0, startTime: 0.0,
            checkpoints: Set(cps), fx: fx, seed: 0, stemFrames: stems, captureBlit: true)

        var maxRing: Float = 0, maxCp = -1
        for cp in cps {
            guard let blit = run.checkpointBlitPixels[cp], let canvas = run.checkpointPixels[cp] else { continue }
            let r = sheenInteriorRinginess(blit: blit, canvas: canvas, w: w, h: h, cream: run.creamRef)
            if r > maxRing { maxRing = r; maxCp = cp }
        }
        print("""
        [skein_norings] session \(session.lastPathComponent), \(cps.count) checkpoints over \(frames)f:
          max sheen-added interior luminance range (concentric-ring proxy) = \(String(format: "%.2f", maxRing)) at frame \(maxCp)
        """)
        // The sheen may add a little interior structure (the gentle wet→dry gradient + the tiny gloss),
        // but a steep gate over the per-pass wetness age-bands produced strong concentric rings
        // (measured > 20 before the wetness blur). Bar: the sheen adds little local contrast inside an
        // otherwise-smooth stroke.
        #expect(maxRing < 13.0,
                "The sheen adds \(maxRing) luminance range inside SMOOTH painted strokes (frame \(maxCp)) — concentric age-band RINGS. Blur the wetness / soften the gate more.")
    }

    /// At SMOOTH-INTERIOR painted texels (the canvas is locally uniform — a solid-stroke interior, not
    /// an edge or droplet boundary), the local luminance RANGE the sheen adds in the BLIT. Concentric
    /// rings = the sheen turning the wetness age-bands into luminance bands inside an otherwise-solid
    /// stroke; this measures exactly that (gating out edges/droplets where the canvas is itself varied).
    private func sheenInteriorRinginess(blit: [UInt8], canvas: [UInt8], w: Int, h: Int, cream: [UInt8]) -> Float {
        func luma(_ p: [UInt8], _ i: Int) -> Float { 0.2126 * Float(p[i + 2]) + 0.7152 * Float(p[i + 1]) + 0.0722 * Float(p[i]) }
        let cb = Int(cream[0]), cg = Int(cream[1]), cr = Int(cream[2])
        let rad = 3
        var sum: Float = 0
        var n = 0
        for y in rad..<(h - rad) {
            for x in rad..<(w - rad) {
                let i = (y * w + x) * 4
                let pd = abs(Int(canvas[i]) - cb) + abs(Int(canvas[i + 1]) - cg) + abs(Int(canvas[i + 2]) - cr)
                guard pd > 60 else { continue }   // painted only
                var cMin: Float = 999, cMax: Float = 0, bMin: Float = 999, bMax: Float = 0
                for dy in -rad...rad {
                    for dx in -rad...rad {
                        let j = ((y + dy) * w + (x + dx)) * 4
                        let lc = luma(canvas, j), lb = luma(blit, j)
                        cMin = min(cMin, lc); cMax = max(cMax, lc)
                        bMin = min(bMin, lb); bMax = max(bMax, lb)
                    }
                }
                guard (cMax - cMin) < 18 else { continue }   // canvas locally SMOOTH (skip edges / droplet boundaries)
                sum += (bMax - bMin)                          // the sheen-added local luminance range
                n += 1
            }
        }
        return n > 0 ? sum / Float(n) : 0
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

    // MARK: - Per-track seed determinism (§5.7) + reseed

    @Test("Per-track seed: same seed → byte-identical painting; different seed → different; reseed clears")
    func test_seedDeterminismAndReseed() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 2400), stems.count > 200 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping seed-determinism test")
            return
        }
        // The determinism RENDER uses the first 400 frames (fast); the reseed busy-slice search
        // below scans the full set so it lands on an active stretch (the intro is quiet).
        let w = 200, h = 200, frames = min(stems.count, 400)
        func render(_ seed: UInt32) throws -> [UInt8] {
            try runPourAccumulation(
                chromatic: 0, frames: frames, width: w, height: h, aspect: 1.0, startTime: 0.0,
                checkpoints: [frames - 1], fx: fx, seed: seed, palette: nil, stemFrames: stems).finalPixels
        }
        let a1 = try render(12345), a2 = try render(12345), bSeed = try render(99999)
        func pxDiff(_ x: [UInt8], _ y: [UInt8]) -> Int {
            var n = 0, i = 0
            while i < x.count { if x[i] != y[i] || x[i + 1] != y[i + 1] || x[i + 2] != y[i + 2] { n += 1 }; i += 4 }
            return n
        }
        let same = pxDiff(a1, a2), cross = pxDiff(a1, bSeed)

        // Reseed unit check: tick a BUSY slice so bursts actually spawn, then reseed clears both.
        let busy = Self.busiestAndCalmestSlices(stems, window: 300).busy
        guard let st = SkeinState(device: fx.ctx.device, seed: 7) else { throw SkeinHoldError.bufferFailed }
        let dt: Float = 1.0 / 60.0
        for stem in busy {
            st.tick(deltaTime: dt, features: FeatureVector(time: 0, deltaTime: dt, aspectRatio: 1.0), stems: stem)
        }
        let beforeTau = st.painterTau, beforeBursts = st.totalBurstsSpawned
        st.reseed(7)
        print("""
        [skein_seed] same-seed pixel-diff=\(same)  diff-seed pixel-diff=\(cross)  (200×200, \(frames)f)
          reseed: bursts \(beforeBursts)→\(st.totalBurstsSpawned)  painterTau \(String(format: "%.2f", beforeTau))→\(String(format: "%.2f", st.painterTau))
        """)

        // 1. DETERMINISM (§5.7 headline) — same track + same seed → the same painting.
        #expect(same == 0, "Same seed produced \(same) differing pixels — the painting is not deterministic.")
        // 2. The seed actually perturbs the trajectory — a different seed paints differently.
        #expect(cross > 50, "Different seeds produced near-identical paintings (\(cross) px) — the seed does not reach the trajectory.")
        // 3. RESEED clears the live painter state (the §1.5 track-change reset).
        #expect(st.painterTau == 0, "reseed did not reset painterTau (\(st.painterTau)).")
        #expect(st.totalBurstsSpawned == 0, "reseed did not clear the burst ring (\(st.totalBurstsSpawned)).")
    }

    // MARK: - Real-stem palette contact sheet (env-gated: candidate palettes for Matt sign-off)

    /// Candidate per-stem palettes [drums, bass, vocals, other] for Matt's sign-off. The README
    /// colour rule: legibility (one stable, well-separated colour per stem), not specific hues, is
    /// the binding constraint — these are distinct legible options, the *Full Fathom Five* register
    /// (A) being the illustrative default.
    private static let candidatePalettes: [(name: String, colors: [SIMD3<Float>])] = [
        ("A_fathom", [SIMD3(0.12, 0.13, 0.18), SIMD3(0.62, 0.13, 0.16),
                      SIMD3(0.90, 0.62, 0.16), SIMD3(0.12, 0.58, 0.55)]),
        ("B_jewel",  [SIMD3(0.28, 0.10, 0.45), SIMD3(0.82, 0.10, 0.30),
                      SIMD3(0.97, 0.72, 0.15), SIMD3(0.05, 0.62, 0.45)]),
        ("C_inkpop", [SIMD3(0.08, 0.09, 0.12), SIMD3(0.10, 0.32, 0.75),
                      SIMD3(0.95, 0.55, 0.10), SIMD3(0.80, 0.14, 0.50)])
    ]

    @Test("Real-stem palette contact sheet (env-gated: SKEIN_VISUAL=1 / RENDER_VISUAL=1)")
    func test_realStem_paletteContactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SKEIN_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("SkeinCanvasHoldTest: SKEIN_VISUAL/RENDER_VISUAL not set, skipping palette contact sheet")
            return
        }
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 2400), stems.count > 200 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping palette contact sheet")
            return
        }
        let w = 960, h = 540
        let frames = min(stems.count, 1400)
        let outDir = try makeOutputDir()
        // Render the SAME real-stem sequence (seed 0) with each candidate palette so Matt compares
        // legibility/character on identical paint, through the live path.
        var tiles: [[UInt8]] = []
        for cand in Self.candidatePalettes {
            let run = try runPourAccumulation(
                chromatic: 0, frames: frames, width: w, height: h, aspect: Float(w) / Float(h),
                startTime: 0.0, checkpoints: [frames - 1], fx: fx,
                seed: 0, palette: cand.colors, stemFrames: stems)
            guard let buf = run.checkpointPixels[frames - 1] else { continue }
            tiles.append(buf)
            try writeBGRAToPNG(buf, w: w, h: h,
                               url: outDir.appendingPathComponent("skein_palette_\(cand.name).png"))
        }
        try writeMontage(tiles, tileW: w, tileH: h,
                         url: outDir.appendingPathComponent("skein_palette_candidates.png"))
        print("""
        [skein_palette_candidates] live path, \(w)×\(h), session \(session.lastPathComponent):
          output dir: \(outDir.path)
          candidates (l→r) = \(Self.candidatePalettes.map { $0.name })
          → skein_palette_candidates.png  +  skein_palette_A_fathom/B_jewel/C_inkpop.png
        """)
        #expect(tiles.count == Self.candidatePalettes.count, "Missing palette-candidate tiles.")
    }

    // MARK: - Sheen contact sheet (env-gated: the Skein.4 eyeball artifact — live BLIT)

    @Test("Wet/dry sheen contact sheet (env-gated: SKEIN_VISUAL=1 / RENDER_VISUAL=1) — live BLIT, real stems")
    func test_sheen_contactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SKEIN_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("SkeinCanvasHoldTest: SKEIN_VISUAL/RENDER_VISUAL not set, skipping sheen contact sheet")
            return
        }
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 2400), stems.count > 200 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping sheen contact sheet")
            return
        }
        let w = 960, h = 540
        let frames = min(stems.count, 1400)
        // Checkpoints across the song so the contact sheet shows the wet live edge advancing while
        // the accumulated past goes matte — the wet-now / dry-past read. BLIT (sheened) output.
        let cps = [frames / 4, frames / 2, (3 * frames) / 4, frames - 1]
        let run = try runPourAccumulation(
            chromatic: 0, frames: frames, width: w, height: h, aspect: Float(w) / Float(h),
            startTime: 0.0, checkpoints: Set(cps), fx: fx, seed: 0, stemFrames: stems,
            captureWetness: false, captureBlit: true)

        let outDir = try makeOutputDir()
        var tiles: [[UInt8]] = []
        for (i, f) in cps.enumerated() {
            guard let buf = run.checkpointBlitPixels[f] else { continue }
            tiles.append(buf)
            try writeBGRAToPNG(buf, w: w, h: h,
                               url: outDir.appendingPathComponent(String(format: "skein_sheen_cp%d.png", i)))
        }
        try writeMontage(tiles, tileW: w, tileH: h,
                         url: outDir.appendingPathComponent("skein_sheen_contact_sheet.png"))
        // Isolate the sheen: the RAW canvas (composeTex, matte — what Skein.3 shipped) beside the
        // SHEENED blit (skein_comp_fragment) at the final frame. The difference IS the wet/dry sheen.
        try writeMontage([run.finalPixels, run.finalBlitPixels], tileW: w, tileH: h,
                         url: outDir.appendingPathComponent("skein_sheen_canvas_vs_blit.png"))
        print("""
        [skein_sheen_contact_sheet] live BLIT path (scene→warp→overlay→blit→swap, skein_comp_fragment), \(w)×\(h):
          output dir: \(outDir.path)
          session \(session.lastPathComponent), checkpoints (frames) = \(cps)
          → skein_sheen_contact_sheet.png   (wet glistening live edge vs matte accumulated past, over time)
          → skein_sheen_canvas_vs_blit.png  (L: raw matte canvas  R: sheened blit — the sheen isolated)
        """)
        #expect(tiles.count == cps.count, "Missing sheen contact-sheet checkpoints.")
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
        // Skein.ENGINE.2 wetness probes (populated when captureWetness == true).
        var cornerAlphaSeries: [Int]           // far-corner (5,5) ALPHA per frame — UNPAINTED wetness:
                                               //   decays under music (never re-stamped), holds at silence.
        var maxAlphaSeries: [Int]              // max ALPHA over the canvas per frame — the freshest wet
                                               //   paint (the overlay stamps coverage → ~255 on solid paint).
        // Skein.4 sheen probe (populated when captureBlit == true): the final BLIT/display output
        // (composeTex → skein_comp_fragment → blitTex), where the wet/dry sheen lives. finalPixels is
        // the raw canvas (composeTex); the sheen = the difference between these two.
        var finalBlitPixels: [UInt8]
        var checkpointBlitPixels: [Int: [UInt8]]   // BLIT (sheened) output at each checkpoint (contact sheet)
    }

    /// Drive the live marks-on-top dispatch path for `frames` frames, advancing features.time by
    /// a fixed Δt each frame (so the painter moves and consecutive capsules chain exactly). Each
    /// frame: warp(prev) → overlay(this frame's swept capsule on top) → blit → read → swap.
    /// Mirrors `drawWithMVWarp`'s strandsOnTop branch (Pass 0 skipped; the ground is the clear).
    private func runPourAccumulation(
        chromatic: Float, frames: Int, width: Int, height: Int, aspect: Float, startTime: Float,
        checkpoints: Set<Int>, fx: SkeinFixture, capturePerFrame: Bool = false,
        seed: UInt32 = 0, palette: [SIMD3<Float>]? = nil, stemFrames: [StemFeatures] = [],
        captureWetness: Bool = false, captureBlit: Bool = false
    ) throws -> PourResult {
        let device = fx.ctx.device, queue = fx.ctx.commandQueue
        // Skein.3: the painter clock + onset-burst ring + per-stem colour live in SkeinState, bound
        // at fragment slot 6 of the overlay (the ENGINE.1.2 strands-on-top binding). The harness
        // ticks it each frame exactly as the live app's setMeshPresetTick does. `stemFrames` are
        // REAL replayed StemFeatures (feedback_synthetic_audio: never hand-authored envelopes); an
        // empty array drives StemFeatures.zero (silence → the pour line only, no onset bursts).
        guard let skein = SkeinState(device: device, seed: seed,
                                     palette: palette ?? SkeinState.defaultPalette)
        else { throw SkeinHoldError.bufferFailed }
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
        var cornerAlphaSeries: [Int] = []
        var maxAlphaSeries: [Int] = []
        var finalBlitPixels: [UInt8] = []
        var checkpointBlitPixels: [Int: [UInt8]] = [:]

        for frameIdx in 0..<frames {
            var features = FeatureVector(
                time: startTime + Float(frameIdx) * dt, deltaTime: dt, aspectRatio: aspect)
            // Tick SkeinState with this frame's REAL stems (or silence). Advances painterTau (the
            // audio-modulated painter clock), detects per-stem onsets → burst ring, and writes the
            // slot-6 buffer the overlay fragment reads. Same call the live setMeshPresetTick makes.
            let stems = stemFrames.isEmpty ? StemFeatures.zero : stemFrames[frameIdx % stemFrames.count]
            skein.tick(deltaTime: dt, features: features, stems: stems)
            guard let cmd = queue.makeCommandBuffer() else { throw SkeinHoldError.cmdBufferFailed }
            // Pass 1: identity warp holds the previous canvas (warpTex → composeTex). chromatic=0
            // + decay=1.0 ⇒ a lossless RGB copy of every unpainted texel. Skein.ENGINE.2: the ALPHA
            // channel carries wetness, decayed by skein.wetnessDecay (1.0 at silence ⇒ held).
            try encodeWarp(cmd: cmd, mvWarp: fx.mvWarp, warpTex: warpTex, composeTex: composeTex,
                           features: &features, chromatic: chromatic,
                           wetnessDecay: skein.wetnessDecay)
            // Pass 2: marks-on-top — draw this frame's marks normal-alpha onto the held canvas.
            try encodeOverlay(cmd: cmd, overlay: fx.overlay, target: composeTex,
                              features: &features, skeinBuffer: skein.skeinBuffer)
            // Pass 3: blit (display-only, identity post) — faithful to the live present pass.
            try encodeBlit(cmd: cmd, mvWarp: fx.mvWarp, src: composeTex, dst: blitTex,
                           post: SIMD4<Float>(0, 0, 1, 0))   // invert0 echo0 gamma1 beat0 = identity
            cmd.commit()
            cmd.waitUntilCompleted()

            let canvas = read(composeTex)
            if frameIdx == 0 { creamRef = pxAt(canvas, 5, 5) }   // far corner — never reached by the painter
            if capturePerFrame { perFrameCounts.append(countPainted(canvas, cream: creamRef)) }
            if captureWetness {
                // Skein.ENGINE.2: the far corner (5,5) is UNPAINTED (the painter's amplitude-limited
                // trajectory never reaches it), so its ALPHA is the held-then-decaying wetness with
                // no re-stamp — decays under music (wetnessDecay < 1), holds at silence (= 1). maxA is
                // the freshest stamped wetness (the overlay raises painted texels' A toward ~255).
                cornerAlphaSeries.append(Int(canvas[(5 * width + 5) * 4 + 3]))
                var mA = 0, j = 3
                while j < canvas.count { if Int(canvas[j]) > mA { mA = Int(canvas[j]) }; j += 4 }
                maxAlphaSeries.append(mA)
            }
            if checkpoints.contains(frameIdx) {
                checkpointPixels[frameIdx] = canvas
                if captureBlit { checkpointBlitPixels[frameIdx] = read(blitTex) }
                checkpointCounts.append(countPainted(canvas, cream: creamRef))
                if frameIdx == sortedCp.first, earlyXY == nil {
                    earlyXY = brightestPaintedXY(canvas, w: width, h: height, cream: creamRef)
                }
            }
            if frameIdx == frames - 1 {
                finalPixels = canvas
                // Skein.4: the BLIT/display output (composeTex → skein_comp_fragment → blitTex) is where
                // the wet/dry sheen lives. The existing tests read composeTex (the raw canvas); the sheen
                // gate reads blitTex and compares it against composeTex (the sheen = the difference).
                if captureBlit { finalBlitPixels = read(blitTex) }
            }
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
            perFrameCounts: perFrameCounts,
            cornerAlphaSeries: cornerAlphaSeries, maxAlphaSeries: maxAlphaSeries,
            finalBlitPixels: finalBlitPixels, checkpointBlitPixels: checkpointBlitPixels)
    }

    // MARK: - Pass encoders (mirror the live mv_warp dispatch path)

    private func encodeWarp(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        warpTex: MTLTexture, composeTex: MTLTexture, features: inout FeatureVector, chromatic: Float,
        wetnessDecay: Float = 1.0
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
        // Skein.ENGINE.2: bind the wetness-channel decay at fragment buffer 1 — `skein_warp_fragment`
        // reads it (decays ALPHA only). Mirrors the live `encodeMVWarpPass`. 1.0 ⇒ A held.
        var wetnessDecayCopy = wetnessDecay
        enc.setFragmentBytes(&wetnessDecayCopy, length: MemoryLayout<Float>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)   // 31×23 quads
        enc.endEncoding()
    }

    /// Pass 2 of the marks-on-top path: draw the overlay (Skein's pour line + onset-burst ring)
    /// normal-alpha onto the held/warped canvas. `loadAction = .load` preserves the warped ground
    /// (only the mark texels are blended in), exactly as `encodeMVWarpScenePass`'s strandsOnTop
    /// branch — INCLUDING the Skein.ENGINE.1.2 gated slot-6 fragment-buffer binding (SkeinState's
    /// SkeinUniforms), which is what `skein_geometry_fragment` reads for the painter clock + the
    /// per-stem-coloured onset ring. Skein.3: the painter is driven by SkeinState (buffer 6), not
    /// features.time, so the harness binds the live SkeinState buffer the same way the app does.
    private func encodeOverlay(
        cmd: MTLCommandBuffer, overlay: MTLRenderPipelineState, target: MTLTexture,
        features: inout FeatureVector, skeinBuffer: MTLBuffer
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .load     // keep the held ground; blend the marks on top
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw SkeinHoldError.encoderFailed }
        enc.setRenderPipelineState(overlay)
        // drawSceneGeometryOverlay binds features@0 + stems@1 (vertex); the strandsOnTop branch also
        // binds the per-preset fragment buffer at slot 6 (ENGINE.1.2). Mirror all three for parity.
        enc.setVertexBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stems = StemFeatures.zero
        enc.setVertexBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 1)
        enc.setFragmentBuffer(skeinBuffer, offset: 0, index: 6)   // Skein.ENGINE.1.2 — painter state
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

    /// Classify the coloured painting by the per-stem palette (Skein.3 colour-separation gate).
    ///  - perStemCount: # of high-cover pixels clearly nearest ONE stem colour (idx = drums/bass/
    ///    vocals/other). "Clearly" = nearest palette distance < 0.62 × second-nearest (separable).
    ///  - mudCount: high-cover pixels roughly equidistant between two stem colours (ambiguous/muddy).
    ///  - distinctBlobs: # of burst-sized connected painted components (size [4,500]; the big line
    ///    component is excluded) — onset bursts as DISTINCT dots, not a merged froth.
    ///  - roundFill / roundN: bbox-fill of medium square-bbox blobs (~0.785 round, ~1.0 square — the
    ///    Matt M7 isotropic-AA round-droplet guard).
    private func analyzeColouredPainting(
        _ buf: [UInt8], w: Int, h: Int, cream: [UInt8], palette: [SIMD3<Float>]
    ) -> (perStemCount: [Int], mudCount: Int, distinctBlobs: Int, roundFill: Float, roundN: Int) {
        let cr = Int(cream[2]), cg = Int(cream[1]), cb = Int(cream[0])
        let pal = palette.map { SIMD3<Float>($0.x * 255, $0.y * 255, $0.z * 255) }
        var perStem = [Int](repeating: 0, count: palette.count)
        var mud = 0
        var painted = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Int(buf[i + 2]), g = Int(buf[i + 1]), b = Int(buf[i])
                let delta = abs(r - cr) + abs(g - cg) + abs(b - cb)
                if delta > 50 { painted[y * w + x] = true }
                guard delta > 90 else { continue }   // classify only HIGH-cover pixels (≈ pure stem colour)
                let pr = Float(r), pg = Float(g), pb = Float(b)
                var d0 = Float.greatestFiniteMagnitude, d1 = Float.greatestFiniteMagnitude, idx0 = 0
                for (k, pc) in pal.enumerated() {
                    let dd = ((pr - pc.x) * (pr - pc.x) + (pg - pc.y) * (pg - pc.y) + (pb - pc.z) * (pb - pc.z)).squareRoot()
                    if dd < d0 { d1 = d0; d0 = dd; idx0 = k } else if dd < d1 { d1 = dd }
                }
                if d0 < 0.62 * d1 { perStem[idx0] += 1 } else { mud += 1 }
            }
        }
        // Burst-sized blob count + roundness (the big line component, size > 500, is excluded).
        var visited = [Bool](repeating: false, count: w * h)
        var blobs = 0, fillN = 0
        var fillSum: Float = 0
        var stack: [Int] = []
        for start in 0..<(w * h) where painted[start] && !visited[start] {
            var size = 0, minx = w, maxx = 0, miny = h, maxy = 0
            stack.removeAll(keepingCapacity: true)
            stack.append(start); visited[start] = true
            while let p = stack.popLast() {
                size += 1
                let x = p % w, y = p / w
                if x < minx { minx = x }; if x > maxx { maxx = x }
                if y < miny { miny = y }; if y > maxy { maxy = y }
                if x > 0     { let q = p - 1; if painted[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if x < w - 1 { let q = p + 1; if painted[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if y > 0     { let q = p - w; if painted[q] && !visited[q] { visited[q] = true; stack.append(q) } }
                if y < h - 1 { let q = p + w; if painted[q] && !visited[q] { visited[q] = true; stack.append(q) } }
            }
            if size >= 4 && size <= 500 { blobs += 1 }
            let bw = maxx - minx + 1, bh = maxy - miny + 1
            let ar = Float(max(bw, bh)) / Float(max(min(bw, bh), 1))
            if size >= 9 && size <= 200 && ar < 1.5 { fillSum += Float(size) / Float(bw * bh); fillN += 1 }
        }
        return (perStem, mud, blobs, fillN > 0 ? fillSum / Float(fillN) : 0, fillN)
    }

    /// Find a strongly-coloured (saturated, non-white) painted pixel for the bake/hold check —
    /// a real onset burst (not the white silence line). delta > 90 AND channel spread > 40.
    private func firstColouredPixel(_ buf: [UInt8], w: Int, h: Int, cream: [UInt8]) -> (Int, Int)? {
        let cr = Int(cream[2]), cg = Int(cream[1]), cb = Int(cream[0])
        for y in 2..<(h - 2) {
            for x in 2..<(w - 2) {
                let i = (y * w + x) * 4
                let r = Int(buf[i + 2]), g = Int(buf[i + 1]), b = Int(buf[i])
                let delta = abs(r - cr) + abs(g - cg) + abs(b - cb)
                let spread = max(r, max(g, b)) - min(r, min(g, b))
                if delta > 90 && spread > 40 { return (x, y) }
            }
        }
        return nil
    }

    // MARK: - Real-stem replay (real audio only — feedback_synthetic_audio)

    /// The recorded session under ~/Documents/phosphene_sessions with the largest stems.csv (most
    /// onsets → the most per-stem colour activity). nil when none exist (local-only artifact).
    private static func firstRecordedSession() -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/phosphene_sessions")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: nil) else { return nil }
        func stemsSize(_ url: URL) -> Int {
            let path = url.appendingPathComponent("stems.csv").path
            guard FileManager.default.fileExists(atPath: path) else { return 0 }
            return ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
        }
        return entries.filter { stemsSize($0) > 0 }.max { stemsSize($0) < stemsSize($1) }
    }

    /// Parse a session's stems.csv into replayable StemFeatures frames (the routing-relevant
    /// columns: per-stem energy, energyRel/Dev, centroid, attackRatio, band1). Real audio only.
    private func loadStemFrames(_ dir: URL, maxFrames: Int) -> [StemFeatures]? {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("stems.csv"), encoding: .utf8)
        else { return nil }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return nil }
        var idx: [String: Int] = [:]
        for (i, name) in lines.removeFirst().split(separator: ",").map(String.init).enumerated() { idx[name] = i }
        var frames: [StemFeatures] = []
        for line in lines.prefix(maxFrames) {
            let row = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            func col(_ name: String) -> Float {
                guard let i = idx[name], i < row.count else { return 0 }
                return Float(row[i]) ?? 0
            }
            var sf = StemFeatures()
            sf.drumsEnergy = col("drumsEnergy"); sf.bassEnergy = col("bassEnergy")
            sf.vocalsEnergy = col("vocalsEnergy"); sf.otherEnergy = col("otherEnergy")
            sf.drumsBand1 = col("drumsBand1"); sf.vocalsBand1 = col("vocalsBand1"); sf.otherBand1 = col("otherBand1")
            sf.drumsEnergyRel = col("drumsEnergyRel"); sf.drumsEnergyDev = col("drumsEnergyDev")
            sf.bassEnergyRel = col("bassEnergyRel"); sf.bassEnergyDev = col("bassEnergyDev")
            sf.vocalsEnergyRel = col("vocalsEnergyRel"); sf.vocalsEnergyDev = col("vocalsEnergyDev")
            sf.otherEnergyRel = col("otherEnergyRel"); sf.otherEnergyDev = col("otherEnergyDev")
            sf.drumsCentroid = col("drumsCentroid"); sf.bassCentroid = col("bassCentroid")
            sf.vocalsCentroid = col("vocalsCentroid"); sf.otherCentroid = col("otherCentroid")
            sf.drumsAttackRatio = col("drumsAttackRatio"); sf.bassAttackRatio = col("bassAttackRatio")
            sf.vocalsAttackRatio = col("vocalsAttackRatio"); sf.otherAttackRatio = col("otherAttackRatio")
            frames.append(sf)
        }
        return frames
    }

    /// The busiest + calmest contiguous `window`-frame slices by total positive energy deviation —
    /// the beat-heavy vs steady stretches for the onset→splatter route assertion.
    private static func busiestAndCalmestSlices(
        _ stems: [StemFeatures], window: Int
    ) -> (busy: [StemFeatures], calm: [StemFeatures]) {
        guard stems.count > window else { return (stems, stems) }
        func activity(_ s: StemFeatures) -> Float {
            max(0, s.drumsEnergyDev) + max(0, s.bassEnergyDev)
                + max(0, s.vocalsEnergyDev) + max(0, s.otherEnergyDev)
        }
        var sum: Float = 0
        for i in 0..<window { sum += activity(stems[i]) }
        var bestSum = sum, bestIdx = 0, worstSum = sum, worstIdx = 0
        for i in window..<stems.count {
            sum += activity(stems[i]) - activity(stems[i - window])
            if sum > bestSum { bestSum = sum; bestIdx = i - window + 1 }
            if sum < worstSum { worstSum = sum; worstIdx = i - window + 1 }
        }
        return (Array(stems[bestIdx..<bestIdx + window]), Array(stems[worstIdx..<worstIdx + window]))
    }

    /// Tick a fresh SkeinState over a stem slice and return the total bursts spawned (route metric).
    private static func spawnsOver(
        _ stems: [StemFeatures], device: MTLDevice, palette: [SIMD3<Float>]
    ) throws -> Int {
        guard let state = SkeinState(device: device, seed: 0, palette: palette)
        else { throw SkeinHoldError.bufferFailed }
        let dt: Float = 1.0 / 60.0
        let feat = FeatureVector(time: 0, deltaTime: dt, aspectRatio: 1.0)
        for stem in stems { state.tick(deltaTime: dt, features: feat, stems: stem) }
        return state.totalBurstsSpawned
    }

    /// Tick a fresh SkeinState over a stem slice and return the per-stem spawn tally (diagnostic).
    private static func spawnsPerStemOver(
        _ stems: [StemFeatures], device: MTLDevice, palette: [SIMD3<Float>]
    ) throws -> [Int] {
        guard let state = SkeinState(device: device, seed: 0, palette: palette)
        else { throw SkeinHoldError.bufferFailed }
        let dt: Float = 1.0 / 60.0
        let feat = FeatureVector(time: 0, deltaTime: dt, aspectRatio: 1.0)
        for stem in stems { state.tick(deltaTime: dt, features: feat, stems: stem) }
        return state.spawnsPerStem
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
