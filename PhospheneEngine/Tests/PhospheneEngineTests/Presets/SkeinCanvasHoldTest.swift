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

    @Test("Pour line accumulates, holds losslessly, is continuous, and is NEVER white; the painter rests at silence — live marks-on-top path")
    func test_pourLine_accumulatesHoldsContinuous() throws {
        guard let fx = try loadSkeinFixture() else { return }
        let w = 256, h = 256
        let checkpoints = [30, 75, 120, 179]
        // Skein.5.1: the line only exists once a COLOURED pour commits (white-baseline era retired),
        // so this gate drives REAL stem frames — but CALM ones (every per-stem dev below the onset
        // threshold) so no bursts spawn: the painting is the pour line alone, and the corridor
        // continuity check stays exact. Calm frames keep stemMix warm (AGC energies ~0.3/stem), so
        // the first pour commits immediately and the whole line draws in that pour's colour at
        // offset 0 (the first pour carries no jump) — on the corridor's natural trajectory.
        guard let session = Self.firstRecordedSession(),
              let all = loadStemFrames(session, maxFrames: 6000), all.count > 400 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping pour-line gate (real audio: feedback_synthetic_audio)")
            return
        }
        let calm = all.filter {
            max(max($0.drumsEnergyDev, $0.bassEnergyDev), max($0.vocalsEnergyDev, $0.otherEnergyDev))
                < SkeinState.onsetDevThreshold
        }
        guard calm.count >= 60 else {
            Issue.record("Session \(session.lastPathComponent) has only \(calm.count) all-calm stem frames — cannot isolate the pour line.")
            return
        }
        let stems = (0..<180).map { calm[$0 % calm.count] }   // tile real calm frames
        let run = try runPourAccumulation(
            chromatic: 0, frames: 180, width: w, height: h, aspect: 1.0, startTime: 0.0,
            checkpoints: Set(checkpoints), fx: fx, stemFrames: stems)

        // The pour LINE lives in a thin corridor around the (seed-0) trajectory. τ-range from the
        // real painter clock (paint speed varies with the calm frames' broadband dev).
        let line = pourLineCorridor(run.finalPixels, w: w, h: h, cream: run.creamRef,
                                    t0: -0.7, t1: run.finalPainterTau + 0.05, rV: 0.035)
        let whitePresent = hasWhiteTexel(run.finalPixels)

        // Skein.5.1 SILENCE REST: with no stems at all, nothing commits and the painter clock
        // pauses — the canvas stays pure cream (the old behaviour drew a white line forever).
        let silent = try runPourAccumulation(
            chromatic: 0, frames: 120, width: w, height: h, aspect: 1.0, startTime: 0.0,
            checkpoints: [119], fx: fx)
        let silentPainted = silent.checkpointCounts.last ?? -1

        print("""
        [skein_pour] 180 calm real-stem frames @ \(w)×\(h), live scene→warp→overlay→blit→swap (line only):
          painted-count checkpoints \(run.checkpointFrames) = \(run.checkpointCounts)   finalTau = \(String(format: "%.2f", run.finalPainterTau))
          early painted texel \(run.earlyXY.map { "(\($0.0),\($0.1))" } ?? "none") still painted at end = \(run.earlyStillPaintedFinal)
          pour-LINE continuity (corridor) = \(String(format: "%.3f", line.continuity))  [in-corridor \(line.inCorridor) / outside \(line.outside)]
          far corner held: frame0 \(run.creamRef) == final \(run.groundCornerFinal) ? \(run.creamRef == run.groundCornerFinal)
          white texel present = \(whitePresent)   silence-run painted = \(silentPainted)
        """)

        // 1. ACCUMULATION — painted-pixel count is monotone non-decreasing and strictly grows.
        for i in 1..<run.checkpointCounts.count {
            #expect(run.checkpointCounts[i] >= run.checkpointCounts[i - 1],
                    "Painted count fell \(run.checkpointCounts[i-1]) → \(run.checkpointCounts[i]) — accumulation not lossless (paint vanished).")
        }
        #expect((run.checkpointCounts.last ?? 0) > (run.checkpointCounts.first ?? 0),
                "Painted count did not grow (\(run.checkpointCounts)) — the painter laid no new line.")

        // 2. HOLD UNDER MOTION — an early-painted texel persists; the unpainted far corner is
        //    RGB-byte-identical frame-0 → final (ENGINE.2 re-scope: A carries wetness, RGB is the
        //    lossless record — and the wetness test owns the A assertions).
        #expect(run.earlyXY != nil, "No early painted texel found — the line did not render.")
        #expect(run.earlyStillPaintedFinal,
                "An early-painted texel was no longer painted at the end — the canvas-hold lost a laid mark.")
        #expect(Array(run.creamRef.prefix(3)) == Array(run.groundCornerFinal.prefix(3)),
                "Far-corner RGB drifted \(run.creamRef) → \(run.groundCornerFinal) at chromatic=0 — the held canvas RGB is not lossless.")

        // 3. CONTINUITY (pour LINE) — the laid line is a single connected ribbon along the
        //    trajectory corridor (calm frames ⇒ no satellites; first pour ⇒ offset 0).
        #expect(line.continuity >= 0.95,
                "Pour-line corridor continuity is only \(line.continuity) — the line has gaps (Skein.1 invariant regressed).")

        // 4. CREAM GROUND held (not black) — the per-preset canvas clear (D-143) still carries.
        #expect(!isBlack(run.groundCornerFinal),
                "Ground corner is black — the cream canvas clear did not take. \(run.groundCornerFinal)")
        #expect(isCreamish(run.groundCornerFinal),
                "Ground corner is not cream-ish (bright, R≳G≳B). \(run.groundCornerFinal)")

        // 5. NEVER WHITE (Skein.5.1 — the Matt M7 2026-06-09 defect, inverted from the old Skein.1
        //    assertion): no laid texel is white; the line is in a palette colour from its first frame.
        #expect(!whitePresent,
                "A white texel was laid — the white-baseline pour regressed (the painter must never pour white).")

        // 6. THE PAINTER RESTS AT SILENCE — no stems ⇒ no commits, clock paused ⇒ pure cream canvas.
        #expect(silentPainted == 0,
                "\(silentPainted) painted pixels at silence — the painter must rest (no music, no paint).")
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
        // BUG-049 fragility class: the largest stems.csv on disk can be a header-only STUB (the
        // recorder appends one on every app/test launch), so scan all sessions for the first with
        // usable frames instead of hard-depending on the single largest — and skip loudly, never
        // red, when none has any: the session SET is environment, not evidence about the code.
        var found: (session: URL, stems: [StemFeatures])?
        for candidate in Self.recordedSessionsBySize() {
            if let stems = loadStemFrames(candidate, maxFrames: 2400), stems.count > 200 {
                found = (candidate, stems)
                break
            }
        }
        guard let (session, stems) = found else {
            print("SkeinCanvasHoldTest: no recorded session with usable stems.csv frames under ~/Documents/phosphene_sessions — skipping real-stem routing test (local-only: real audio required, feedback_synthetic_audio)")
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

        // 3. ONSET BURSTS FIRE PER STEM — every stem with onsets produces bursts. This is the
        //    session-ROBUST "splatter, not just a line" check. The separate-satellite-blob COUNT
        //    (`an.distinctBlobs`, kept as a diagnostic above) is too session-dependent to gate on:
        //    most droplets are flicked AS the painter pours so they connect to the skein (Pollock-
        //    correct), and since Skein.4.1 M7-round-2 the line is now LONG continuous pours (minPourTau),
        //    which absorb droplets into one >500 px component → separable far-satellites can be ~0 even
        //    though the splatter is firing fine. The firing is proven directly by the per-stem spawn
        //    tally + busy≫calm (route) + stems-present (distinct colours render); the dot SHAPE by the
        //    roundness gate when separable blobs exist.
        #expect(spawnsFull.allSatisfy { $0 > 0 },
                "A stem produced no onset bursts over the run (\(spawnsFull)) — the onset→splatter route is dead for a stem.")

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

        // 6b. NEVER WHITE (Skein.5.1) — canvas birth + real stems is exactly the track-start
        //     scenario of Matt's M7 defect: the first stroke must already be a palette colour.
        #expect(!hasWhiteTexel(run.finalPixels),
                "A white texel was laid on a real-stem run — the white-baseline pour regressed.")

        // 7. BAKE + HOLD — an early-painted pixel persists to the end (lossless held paint). Use a
        //    colour-AGNOSTIC strongly-painted finder (max delta from cream), not a saturated-only one:
        //    since M7-round-2 the longer first pour can be a low-colour-spread stem (e.g. drums =
        //    charcoal) through frame 60, which a `spread > 40` finder would miss — the canvas-hold
        //    property is colour-independent, so any strongly-painted texel proves it.
        if let early = run.checkpointPixels[60] {
            let cp = brightestPaintedXY(early, w: w, h: h, cream: run.creamRef)
            #expect(cp != nil, "No early painted pixel found — nothing laid early.")
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

    // MARK: - Skein.5.4: two painting techniques — independent flicks + pour drips (spawn layer)

    /// Spawn-frame audit: tick a fresh SkeinState over a stem slice and, on every frame the burst
    /// counter advances, measure each NEW mark's distance to the painter's pour position THAT frame
    /// (spawn and the read share the same post-advance painterTau — exact, not approximate).
    /// Drips that yield to a full ring don't advance the counter, so suffix(delta) is always the
    /// newly-appended marks.
    private static func spawnAudit(
        _ slice: [StemFeatures], frames: Int, device: MTLDevice, palette: [SIMD3<Float>]
    ) throws -> (flickDists: [Float], dripDists: [Float], flicks: Int, drips: Int) {
        guard let st = SkeinState(device: device, seed: 0, palette: palette)
        else { throw SkeinHoldError.bufferFailed }
        let dt: Float = 1.0 / 60.0
        var flickDists: [Float] = [], dripDists: [Float] = []
        for fi in 0..<frames {
            let before = st.totalBurstsSpawned
            let features = FeatureVector(time: Float(fi) * dt, deltaTime: dt, aspectRatio: 1.0)
            st.tick(deltaTime: dt, features: features, stems: slice[fi % slice.count])
            let delta = st.totalBurstsSpawned - before
            guard delta > 0 else { continue }
            let pp = st.currentPainterPourPosition
            for mark in st.activeBurstMarks.suffix(delta) {
                let d = mark.pos - pp
                let dist = (d.x * d.x + d.y * d.y).squareRoot()
                if mark.isDrip { dripDists.append(dist) } else { flickDists.append(dist) }
            }
        }
        let flicks = st.spawnsPerStem.reduce(0, +)
        return (flickDists, dripDists, flicks, st.totalBurstsSpawned - flicks)
    }

    @Test("Skein.5.4 techniques: flicks land FAR from the painter (independent gesture), drips shed BESIDE the line at a rate ∝ pour volume — live tick path, real stems")
    func test_splatterTechniques_flickPlacementAndPourDrips() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 2400), stems.count > 400 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping splatter-techniques gate (real audio: feedback_synthetic_audio)")
            return
        }
        let palette = SkeinState.defaultPalette
        let dev = fx.ctx.device

        // Run 1: the real session as-played (both techniques under natural music).
        let real = try Self.spawnAudit(Array(stems.prefix(1500)), frames: min(stems.count, 1500),
                                       device: dev, palette: palette)
        // Runs 2 + 3: the busiest vs calmest 240-frame slices, tiled — high pour volume (high
        // sustained devs → high lineFlow) vs low. Identical frame count, so the drip-count gap
        // is the volume response (Matt: drip density "depends on the volume of the pour").
        let busyCalm = Self.busiestAndCalmestSlices(stems, window: 240)
        let busy = try Self.spawnAudit(busyCalm.busy, frames: 900, device: dev, palette: palette)
        let calm = try Self.spawnAudit(busyCalm.calm, frames: 900, device: dev, palette: palette)

        let allFlickDists = real.flickDists + busy.flickDists + calm.flickDists
        let allDripDists = real.dripDists + busy.dripDists + calm.dripDists
        let minFlick = allFlickDists.min() ?? -1
        let maxDrip = allDripDists.max() ?? -1
        print("""
        [skein54_techniques] session \(session.lastPathComponent), live tick path:
          real run: flicks \(real.flicks) / drips \(real.drips)
          busy tile: flicks \(busy.flicks) / drips \(busy.drips)   calm tile: flicks \(calm.flicks) / drips \(calm.drips)
          flick distance from painter: min \(String(format: "%.3f", minFlick)) over \(allFlickDists.count)
          drip distance from painter:  max \(String(format: "%.3f", maxDrip)) over \(allDripDists.count)
        """)

        // (a) FLICK INDEPENDENCE — every flick lands ≥ ~0.18 UV from the painter's pour position
        //     ("away from the line is best"; spawn-time min-distance 0.20 minus the push-out edge case).
        #expect(!allFlickDists.isEmpty, "No flicks spawned across three runs — the onset route died.")
        #expect(minFlick >= 0.18,
                "A flick landed \(minFlick) UV from the painter (< 0.18) — flicks must be independent of the line.")

        // (b) DRIP RATE ∝ POUR VOLUME — the high-flow tile sheds clearly more drips than the
        //     low-flow tile over the same frame count.
        #expect(busy.drips > 0, "The high-flow tile shed no drips — the pour-drip spawner is dead.")
        #expect(busy.drips > calm.drips,
                "High-flow tile shed \(busy.drips) drips ≤ low-flow \(calm.drips) — drip rate is not following pour volume.")

        // (c) DRIP PROXIMITY — every drip lands within ~0.03 UV of the line (the painter's pour
        //     position at shed time; dripMaxPerpOffset 0.020 + margin).
        #expect(!allDripDists.isEmpty, "No drips spawned across three runs — cannot verify drip proximity.")
        #expect(maxDrip <= 0.03,
                "A drip landed \(maxDrip) UV from the line (> 0.03) — drips must hug the pour.")
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
        //
        // RECALIBRATED 13 → 16 at Skein.5.4 (the ONLY sanctioned bar adjustment of that increment,
        // flagged in its closeout): the lobed impact blots + heavier drips have LARGER smooth
        // interiors than the old confetti dots, so more blot-interior texels enter this proxy's
        // sample and the wet-fresh sheen over them legitimately raises the mean local range
        // (~13.4 measured, verified ring-free at pixel zoom in the Skein.5.4 prior session). The
        // ring-defect signature is unchanged at ~27.6 (the round-4 A/B) — 16 still rejects it
        // with margin while admitting the bigger smooth blots.
        #expect(maxRing < 16.0,
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

    // MARK: - Colour-per-stroke (Skein.4.1): a dominant switch freezes the old colour + starts a new pour

    @Test("Line colour is frozen per-segment: a dominant-stem switch keeps the already-laid paint's colour and starts a displaced new pour — live path")
    func test_lineColorFreeze_keepsColourAndStartsNewPour() throws {
        guard let fx = try loadSkeinFixture() else { return }
        // Build a two-phase REAL-stem sequence with a clean dominant-stem SWITCH: the window where one
        // stem most strongly leads, then the window where a DIFFERENT stem most strongly leads. The
        // frames are real (feedback_synthetic_audio / FA #27 — never hand-authored); we only ORDER two
        // real slices to guarantee a switch (the same thing busiestAndCalmestSlices does for its route).
        // Phases are long enough that the Skein.4.1 M7-round-2 minPourTau dwell is satisfied during
        // phase A and the post-switch pour (phase B) is long enough to sample (the new pour only
        // COMMITS on a sustained, decisive change, so a short phase B would never switch).
        //
        // NOT every session contains two stem-dominated windows (a vocals+bass-only song never lets
        // `other` or `drums` lead) — so search the recorded sessions, largest first, for one that does,
        // instead of hard-depending on the single largest session (which changes every time Matt
        // listens; the gate went red on new session data 2026-06-09).
        let window = 140, phaseA = 120, phaseB = 130
        let palette = SkeinState.defaultPalette
        // The binding constraint is the SECOND stem's decisiveness — the post-switch pour only
        // commits if the challenger leads the incumbent by the 1.25× hysteresis — so rank the
        // sessions by their 2nd-ranked lead, not merely take the first with two positive leads.
        // Decisiveness alone is not enough, though: a maximally decisive candidate can land its
        // committed switch so close to a pour boundary that the pre/post sampling windows
        // (≥ 3·dτ each side, inside the pour's reign and the probe canvas) are infeasible — an
        // artifact of which sessions happen to exist on disk, not a colour-freeze defect (a
        // 2026-06-11 evening session turned the gate red exactly this way). Walk the ranked
        // candidates and take the FIRST whose switch is also SAMPLE-ABLE, verified by a CPU-only
        // dry run of the same tick sequence (`switchSampleInfeasibility` — tick never reads the
        // GPU back, so the dry run predicts the live run's windows exactly).
        typealias Candidate = (session: URL, slices: [(slice: [StemFeatures], lead: Float)], a: Int, b: Int, lead2: Float)
        var candidates: [Candidate] = []
        for candidate in Self.recordedSessionsBySize() {
            guard let stems = loadStemFrames(candidate, maxFrames: 6000), stems.count > 400 else { continue }
            let leads = (0..<4).map { Self.mostDominatedSlice(stems, stem: $0, window: window) }
            let ranked = leads.enumerated().sorted { $0.element.lead > $1.element.lead }
            guard ranked.count >= 2, ranked[0].element.lead > 0, ranked[1].element.lead > 0 else { continue }
            candidates.append((candidate, leads, ranked[0].offset, ranked[1].offset, ranked[1].element.lead))
        }
        candidates.sort { $0.lead2 > $1.lead2 }
        var picked: Candidate?
        var seq: [StemFeatures] = []
        for candidate in candidates {
            let candidateSeq = Array(candidate.slices[candidate.a].slice.prefix(phaseA))
                + Array(candidate.slices[candidate.b].slice.prefix(phaseB))
            guard candidateSeq.count == phaseA + phaseB else { continue }
            if let reason = switchSampleInfeasibility(seq: candidateSeq, device: fx.ctx.device, palette: palette) {
                print("[skein_colorfreeze] rejecting \(candidate.session.lastPathComponent): \(reason)")
                continue
            }
            picked = candidate
            seq = candidateSeq
            break
        }
        guard let pick = picked else {
            // BUG-049 verification criterion (1): the gate must never go red on session-SET content —
            // which captures exist on disk is environmental (stub captures append on every app/test
            // run; real captures come and go with Matt's listening), not evidence about the
            // colour-freeze code. Skip LOUDLY with the reason (never silently); per-candidate
            // rejection reasons are printed above. The gate's teeth are unchanged once it arms.
            print("""
            SkeinCanvasHoldTest: skipping colour-freeze gate — no recorded session yields a \
            sample-able dominant-stem switch (\(Self.recordedSessionsBySize().count) session(s) \
            on disk, \(candidates.count) with two stem-dominated \(window)-frame slices; rejection \
            reasons above). Record a real listening session to arm this gate \
            (real audio: feedback_synthetic_audio).
            """)
            return
        }
        let session = pick.session
        let stemA = pick.a, stemB = pick.b
        print("[skein_colorfreeze] picked \(session.lastPathComponent): stemA=\(stemA) lead \(pick.slices[stemA].lead), stemB=\(stemB) lead \(pick.slices[stemB].lead)")

        let w = 256, h = 256
        guard let skein = SkeinState(device: fx.ctx.device, seed: 0, palette: palette) else {
            throw SkeinHoldError.bufferFailed
        }
        // Live dispatch path (scene→warp→overlay→blit→swap), recording the painter clock + dominant
        // stem each frame; capture the final canvas (composeTex). Seed 0 ⇒ the test's skeinPainterPos
        // mirror (phx=phy=0) matches the shader trajectory; the per-pour OFFSET comes from the ring.
        let device = fx.ctx.device, queue = fx.ctx.commandQueue
        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: fx.ctx.pixelFormat, width: w, height: h, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]; fbDesc.storageMode = .shared
        guard var warpTex = device.makeTexture(descriptor: fbDesc),
              var composeTex = device.makeTexture(descriptor: fbDesc),
              let blitTex = device.makeTexture(descriptor: fbDesc) else { throw SkeinHoldError.textureFailed }
        try clearTextures([warpTex, composeTex], to: fx.cream, context: fx.ctx)
        try clearTextures([blitTex], to: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1), context: fx.ctx)

        let dt: Float = 1.0 / 60.0
        var taus: [Float] = [], doms: [Int] = []
        var probeCanvas = [UInt8](repeating: 0, count: w * h * 4)
        var probeTau: Float = 0
        var probeCaptured = false
        var committedDom = -1
        var switchFrame: Int?
        for (fi, stem) in seq.enumerated() {
            var features = FeatureVector(time: Float(fi) * dt, deltaTime: dt, aspectRatio: 1.0)
            skein.tick(deltaTime: dt, features: features, stems: stem)
            taus.append(skein.painterTau); doms.append(skein.lineDominantStem)
            let domNow = skein.lineDominantStem
            if committedDom < 0 { committedDom = domNow }   // first committed pour (−1 until settle)
            else if switchFrame == nil && domNow >= 0 && domNow != committedDom { switchFrame = fi }
            guard let cmd = queue.makeCommandBuffer() else { throw SkeinHoldError.cmdBufferFailed }
            try encodeWarp(cmd: cmd, mvWarp: fx.mvWarp, warpTex: warpTex, composeTex: composeTex,
                           features: &features, chromatic: 0, wetnessDecay: skein.wetnessDecay)
            try encodeOverlay(cmd: cmd, overlay: fx.overlay, target: composeTex,
                              features: &features, skeinBuffer: skein.skeinBuffer)
            try encodeBlit(cmd: cmd, mvWarp: fx.mvWarp, src: composeTex, dst: blitTex,
                           post: SIMD4<Float>(0, 0, 1, 0), skeinBuffer: skein.skeinBuffer)
            cmd.commit(); cmd.waitUntilCompleted()
            // Skein.5.4 probe timing (Matt-approved, 2026-06-10): capture the canvas ~28 frames
            // after the switch COMMITS — late enough that the post-switch pour has drawn through
            // the 25·dτ probe window, early enough that the independent flicks (which now
            // legitimately land anywhere, including over the old line) have not yet overpainted
            // the pre-switch segment. The defect this gate guards — instant recolour of the laid
            // tail AT the switch — manifests immediately, so the early probe is a SHARPER test of
            // the same property. (End-of-run probing read X=28/Y=32 from flick overpaint while the
            // freeze itself was intact — main baseline X=61/Y=0, same session.)
            let probeFrame = switchFrame.map { min($0 + 28, seq.count - 1) } ?? (seq.count - 1)
            if !probeCaptured && fi >= probeFrame {
                composeTex.getBytes(&probeCanvas, bytesPerRow: w * 4,
                                    from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                probeTau = skein.painterTau
                probeCaptured = true
            }
            swap(&warpTex, &composeTex)
        }

        // Resolve the switch from the breakpoint ring: the final pour vs the prior different-colour pour.
        let cream = Array(probeCanvas[(5 * w + 5) * 4 ..< (5 * w + 5) * 4 + 4])
        let bps = skein.colorBreakpoints
        guard let lastBP = bps.last,
              let priorBP = bps.dropLast().reversed().first(where: { dist3($0.color, lastBP.color) > 0.05 })
        else {
            Issue.record("Only one colour pour — the concat did not switch the dominant stem (domEnd=\(doms.last ?? -1), breakpoints=\(bps.count)).")
            return
        }
        func palIndex(_ linear: SIMD3<Float>) -> Int? {
            (0..<palette.count).first { dist3(SkeinState.srgbToLinear(palette[$0]), linear) < 0.06 }
        }
        guard let domA = palIndex(priorBP.color), let domB = palIndex(lastBP.color), domA != domB else {
            Issue.record("Breakpoint colours did not map to two distinct palette stems (\(priorBP.color) / \(lastBP.color)).")
            return
        }
        let offA = priorBP.offset, offB = lastBP.offset
        let colA255 = SIMD3<Float>(palette[domA].x * 255, palette[domA].y * 255, palette[domA].z * 255)
        let colB255 = SIMD3<Float>(palette[domB].x * 255, palette[domB].y * 255, palette[domB].z * 255)
        let tauSwitch = lastBP.tauStart
        let tauFinal = taus.last ?? 0
        let dtau = max(tauFinal - (taus.dropLast().last ?? 0), 1e-4)
        let jump = offB - offA
        let jumpMag = (jump.x * jump.x + jump.y * jump.y).squareRoot()

        // Sample the line colour along the trajectory at a known pour offset (painterPos(tau) + off).
        func tally(_ tauLo: Float, _ tauHi: Float, _ off: SIMD2<Float>) -> (x: Int, y: Int, cream: Int) {
            var cx = 0, cy = 0, cc = 0
            let n = 60
            for s in 0...n {
                let tau = tauLo + (tauHi - tauLo) * Float(s) / Float(n)
                switch sampleLineClass(probeCanvas, w: w, h: h, uv: Self.skeinPainterPos(tau) + off,
                                       x255: colA255, y255: colB255, cream: cream) {
                case 0: cx += 1
                case 1: cy += 1
                default: cc += 1
                }
            }
            return (cx, cy, cc)
        }
        // pre-switch window: inside the prior (A) pour's reign and baked; post-switch: the new (B) pour.
        let preLo = max(tauSwitch - 25 * dtau, priorBP.tauStart + 2 * dtau)
        let preHi = tauSwitch - 3 * dtau
        let postLo = tauSwitch + 3 * dtau
        let postHi = min(tauSwitch + 25 * dtau, probeTau)   // probe canvas only extends to capture τ
        // Safety net only: candidate selection already rejected unsample-able switches via the
        // `switchSampleInfeasibility` dry run, which mirrors this arithmetic. If this fires, the
        // dry run and the live loop have DIVERGED — fix the parity, don't widen the windows.
        guard preHi - preLo >= 3 * dtau, postHi - postLo >= 3 * dtau else {
            Issue.record("Switch landed too close to a pour boundary to sample (preLo=\(preLo) preHi=\(preHi) postLo=\(postLo) postHi=\(postHi)) — selection dry run and live loop diverged.")
            return
        }
        let pre = tally(preLo, preHi, offA)
        let post = tally(postLo, postHi, offB)
        let postAtA = tally(postLo, postHi, offA)   // the new pour is NOT on the un-jumped (offA) path

        print("""
        [skein_colorfreeze] session \(session.lastPathComponent), live path \(w)×\(h), switch stem \(domA)→\(domB):
          breakpoint ring: \(bps.map { "(τ\(String(format: "%.2f", $0.tauStart)) col\(String(format: "%.2f/%.2f/%.2f", $0.color.x, $0.color.y, $0.color.z)) off\(String(format: "%.3f,%.3f", $0.offset.x, $0.offset.y)))" }.joined(separator: " "))
          dominant: frame60=\(doms[min(60, doms.count - 1)]) → end=\(doms.last ?? -1)   tauSwitch=\(String(format: "%.2f", tauSwitch)) dtau=\(String(format: "%.4f", dtau))
          new-pour jump |offB−offA| = \(String(format: "%.3f", jumpMag))  (offA \(offA) offB \(offB))
          PRE-switch @offA   X=\(pre.x) Y=\(pre.y) cream=\(pre.cream)    [expect X≫Y — old paint KEEPS its colour]
          POST-switch @offB  X=\(post.x) Y=\(post.y) cream=\(post.cream)   [expect Y≫X — the new colour]
          new-pour displaced: @offB Y=\(post.y) vs @offA Y=\(postAtA.y)   [expect offB≫offA — a NEW pour, not a continuation]
        """)

        // The concat must have switched the visible dominant stem (else the test proves nothing).
        #expect((doms.last ?? -1) != doms[min(60, doms.count - 1)],
                "Dominant stem did not switch (frame60=\(doms[min(60, doms.count - 1)]) end=\(doms.last ?? -1)) — test setup failed.")
        // 1. COLOUR FREEZE (the headline — inverse of the recolour bug): pre-switch line KEEPS colour A.
        #expect(pre.x >= 6 && pre.x > pre.y * 2,
                "Pre-switch line is not colour A (X=\(pre.x) Y=\(pre.y)) — the already-laid stroke recoloured on the switch (the Skein.4.1 defect).")
        // 2. NEW COLOUR: the post-switch line reads colour B.
        #expect(post.y >= 6 && post.y > post.x * 2,
                "Post-switch line is not colour B (X=\(post.x) Y=\(post.y)) — the new pour did not take the new colour.")
        // 3. NEW POUR DISPLACED (Matt's option 2): a real jump, and the new pour is at the jumped offset.
        #expect(jumpMag > SkeinState.breakJumpMagnitude * 0.5,
                "No new-pour jump recorded (|offB−offA|=\(jumpMag)) — a colour change must start a displaced new pour.")
        #expect(post.y > postAtA.y,
                "The new pour sits on the un-jumped path, not the jumped position (offB Y=\(post.y) vs offA Y=\(postAtA.y)) — it reads as a continuation, not a new pour.")
    }

    /// CPU-only pre-flight for the colour-freeze gate's candidate selection: replay `seq` through
    /// a fresh SkeinState exactly as the live-path loop above will (tick is pure CPU state plus a
    /// shared-buffer write — no GPU pass feeds back into it, so the dry run predicts the live
    /// run's painter clock, dominant stem, and breakpoint ring exactly) and report why the
    /// post-run colour sampling would be impossible. `nil` means the candidate's switch is
    /// sample-able and may carry the gate. This rejects only SETUP infeasibility (no committed
    /// switch, unmappable breakpoints, windows < 3·dτ); the colour-freeze assertions themselves
    /// still run, unweakened, on the picked candidate. MUST mirror the live loop's switch/probe
    /// bookkeeping and window arithmetic verbatim — divergence re-opens the boundary-artifact red
    /// this selection filter exists to prevent (2026-06-11).
    private func switchSampleInfeasibility(
        seq: [StemFeatures], device: MTLDevice, palette: [SIMD3<Float>]) -> String? {
        guard let skein = SkeinState(device: device, seed: 0, palette: palette) else {
            return "SkeinState init failed"
        }
        let dt: Float = 1.0 / 60.0
        var taus: [Float] = []
        var doms: [Int] = []
        var committedDom = -1
        var switchFrame: Int?
        var probeTau: Float = 0
        var probeCaptured = false
        for (fi, stem) in seq.enumerated() {
            let features = FeatureVector(time: Float(fi) * dt, deltaTime: dt, aspectRatio: 1.0)
            skein.tick(deltaTime: dt, features: features, stems: stem)
            taus.append(skein.painterTau)
            doms.append(skein.lineDominantStem)
            let domNow = skein.lineDominantStem
            if committedDom < 0 { committedDom = domNow }
            else if switchFrame == nil && domNow >= 0 && domNow != committedDom { switchFrame = fi }
            let probeFrame = switchFrame.map { min($0 + 28, seq.count - 1) } ?? (seq.count - 1)
            if !probeCaptured && fi >= probeFrame {
                probeTau = skein.painterTau
                probeCaptured = true
            }
        }
        guard (doms.last ?? -1) != doms[min(60, doms.count - 1)] else {
            return "dominant stem never visibly switches (frame60=\(doms[min(60, doms.count - 1)]) end=\(doms.last ?? -1))"
        }
        let bps = skein.colorBreakpoints
        guard let lastBP = bps.last,
              let priorBP = bps.dropLast().reversed().first(where: { dist3($0.color, lastBP.color) > 0.05 })
        else { return "only one colour pour — no committed switch (breakpoints=\(bps.count))" }
        func palIndex(_ linear: SIMD3<Float>) -> Int? {
            (0..<palette.count).first { dist3(SkeinState.srgbToLinear(palette[$0]), linear) < 0.06 }
        }
        guard let domA = palIndex(priorBP.color), let domB = palIndex(lastBP.color), domA != domB else {
            return "breakpoint colours do not map to two distinct palette stems (\(priorBP.color) / \(lastBP.color))"
        }
        let tauSwitch = lastBP.tauStart
        let tauFinal = taus.last ?? 0
        let dtau = max(tauFinal - (taus.dropLast().last ?? 0), 1e-4)
        let preLo = max(tauSwitch - 25 * dtau, priorBP.tauStart + 2 * dtau)
        let preHi = tauSwitch - 3 * dtau
        let postLo = tauSwitch + 3 * dtau
        let postHi = min(tauSwitch + 25 * dtau, probeTau)
        guard preHi - preLo >= 3 * dtau, postHi - postLo >= 3 * dtau else {
            return "switch lands too close to a pour boundary to sample "
                + "(preLo=\(preLo) preHi=\(preHi) postLo=\(postLo) postHi=\(postHi))"
        }
        return nil
    }

    // MARK: - Skein.5: mood — valence warms the laid palette, arousal quickens/densifies

    @Test("Mood: +valence warms the laid paint (R↑ B↓), +arousal covers faster — live path, real stems")
    func test_mood_warmthAndVigour() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 1200), stems.count > 400 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping mood gate (real audio: feedback_synthetic_audio)")
            return
        }
        let w = 256, h = 256, frames = 900
        // Same REAL stems + same seed; only the smoothed-classifier-style mood inputs differ —
        // the high/low valence + high/low arousal fixtures the Skein.5 done-when names.
        let warm = try runPourAccumulation(
            chromatic: 0, frames: frames, width: w, height: h, aspect: 1.0, startTime: 0,
            checkpoints: [], fx: fx, seed: 7, stemFrames: stems,
            drive: MusicalityDrive(valence: 0.8, arousal: 0.8))
        let cool = try runPourAccumulation(
            chromatic: 0, frames: frames, width: w, height: h, aspect: 1.0, startTime: 0,
            checkpoints: [], fx: fx, seed: 7, stemFrames: stems,
            drive: MusicalityDrive(valence: -0.8, arousal: -0.8))

        // Painted-pixel statistics (≠ cream): mean R − mean B (warmth), coverage, pale share.
        func stats(_ px: [UInt8], cream: [UInt8]) -> (warmth: Float, painted: Int, paleShare: Float) {
            var rSum = 0, bSum = 0, n = 0, pale = 0
            let cb = Int(cream[0]), cg = Int(cream[1]), cr = Int(cream[2])
            for i in stride(from: 0, to: px.count, by: 4) {
                let pd = abs(Int(px[i]) - cb) + abs(Int(px[i + 1]) - cg) + abs(Int(px[i + 2]) - cr)
                guard pd > 60 else { continue }
                rSum += Int(px[i + 2]); bSum += Int(px[i])
                if min(Int(px[i]), Int(px[i + 1]), Int(px[i + 2])) > 165 { pale += 1 }   // linear ~0.65 in bytes
                n += 1
            }
            guard n > 0 else { return (0, 0, 0) }
            return (Float(rSum - bSum) / Float(n), n, Float(pale) / Float(n))
        }
        let sWarm = stats(warm.finalPixels, cream: warm.creamRef)
        let sCool = stats(cool.finalPixels, cream: cool.creamRef)
        print("""
        [skein5_mood] session \(session.lastPathComponent), \(frames)f live path \(w)×\(h):
          WARM (+v +a): warmth(R−B)=\(String(format: "%.1f", sWarm.warmth))  painted=\(sWarm.painted)  pale=\(String(format: "%.3f", sWarm.paleShare))  τ=\(String(format: "%.2f", warm.finalPainterTau))  marks=\(warm.totalBurstsSpawned)
          COOL (−v −a): warmth(R−B)=\(String(format: "%.1f", sCool.warmth))  painted=\(sCool.painted)  pale=\(String(format: "%.3f", sCool.paleShare))  τ=\(String(format: "%.2f", cool.finalPainterTau))  marks=\(cool.totalBurstsSpawned)
        """)
        #expect(sWarm.painted > 500 && sCool.painted > 500,
                "Runs painted too little to compare (warm \(sWarm.painted) / cool \(sCool.painted)).")
        // 1. WARMTH: the +valence canvas reads warmer than the −valence one (R−B balance shift).
        #expect(sWarm.warmth > sCool.warmth + 5.0,
                "+valence did not warm the laid palette (warm R−B \(sWarm.warmth) vs cool \(sCool.warmth)).")
        // 2. VIGOUR — RE-PROBED at Skein.5.4 (Matt-approved, 2026-06-10): flicks now scatter over
        //    the WHOLE canvas (the independent-technique change), so total painted area saturates
        //    similarly in both runs and the old ≥1.10× coverage margin measured placement, not
        //    vigour (1.285× pre-5.4 → 1.078× post, same session, both runs painting 2.3× more).
        //    Measure the two mechanisms +arousal actually drives — the painter travels farther
        //    (speed ×0.7–1.3) and throws more marks (refractory ÷(1+0.5a), τ-clocked drips) —
        //    plus keep coverage as a DIRECTION check (no diluted margin).
        #expect(warm.finalPainterTau > cool.finalPainterTau * 1.10,
                "+arousal did not quicken the painter (τ warm \(warm.finalPainterTau) vs cool \(cool.finalPainterTau)).")
        #expect(warm.totalBurstsSpawned > cool.totalBurstsSpawned,
                "+arousal did not densify the marks (spawns warm \(warm.totalBurstsSpawned) vs cool \(cool.totalBurstsSpawned)).")
        #expect(sWarm.painted > sCool.painted,
                "+arousal covered LESS canvas (painted warm \(sWarm.painted) vs cool \(sCool.painted)).")
        // 3. PALE GUARD (CLAUDE.md pale-dominant rule): the mood tint never washes the paint pale.
        #expect(sWarm.paleShare < 0.30 && sCool.paleShare < 0.30,
                "Mood tint pushed pale share over the ceiling (warm \(sWarm.paleShare) / cool \(sCool.paleShare)).")
    }

    // MARK: - Skein.5: structure — a confident boundary leans new pours + flurries the splatter

    @Test("Structure: a confident section boundary pulses density, leans new pours, and is fully off at low confidence — live tick path")
    func test_structure_boundaryBias() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let raw = loadStemFrames(session, maxFrames: 6000), raw.count > 400 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping structure gate (real audio: feedback_synthetic_audio)")
            return
        }
        // Tile ONE single-dominant 120-frame REAL slice so (a) pre/post-boundary audio content is
        // IDENTICAL (any density change is the pulse, not the music) and (b) the dominant stem
        // never switches naturally (any new pour at the boundary is the boundary's).
        let slice = Self.mostDominatedSlice(raw, stem: Self.mostActiveStem(raw), window: 120).slice
        let boundaryFrame = 600, total = 1200
        let dt: Float = 1.0 / 60.0

        func run(confidence: Float) throws -> (skein: SkeinState, spawnsPre: Int, spawnsPost: Int, breaksAtBoundary: Int) {
            guard let skein = SkeinState(device: fx.ctx.device, seed: 0) else { throw SkeinHoldError.bufferFailed }
            var spawnsAt480 = 0, spawnsAt600 = 0, spawnsAt720 = 0, breaksBefore = 0
            for fi in 0..<total {
                let features = FeatureVector(time: Float(fi) * dt, deltaTime: dt, aspectRatio: 1.0)
                let structure = StructuralPrediction(
                    sectionIndex: fi < boundaryFrame ? 0 : 1,
                    sectionStartTime: fi < boundaryFrame ? 0 : Float(boundaryFrame) * dt,
                    predictedNextBoundary: 0,
                    confidence: confidence)
                skein.tick(deltaTime: dt, features: features, stems: slice[fi % slice.count],
                           structure: structure)
                if fi == 479 { spawnsAt480 = skein.totalBurstsSpawned }
                if fi == 599 { spawnsAt600 = skein.totalBurstsSpawned; breaksBefore = skein.colorBreakpoints.count }
                if fi == 719 { spawnsAt720 = skein.totalBurstsSpawned }
            }
            return (skein, spawnsAt600 - spawnsAt480, spawnsAt720 - spawnsAt600,
                    skein.colorBreakpoints.count - breaksBefore)
        }

        let hi = try run(confidence: 0.8)
        let lo = try run(confidence: 0.05)
        let leanMag = (hi.skein.sectionLeanCurrent.x * hi.skein.sectionLeanCurrent.x
                     + hi.skein.sectionLeanCurrent.y * hi.skein.sectionLeanCurrent.y).squareRoot()
        let loLean = (lo.skein.sectionLeanCurrent.x * lo.skein.sectionLeanCurrent.x
                    + lo.skein.sectionLeanCurrent.y * lo.skein.sectionLeanCurrent.y).squareRoot()
        print("""
        [skein5_structure] tiled single-dominant slice, boundary @\(boundaryFrame), live tick path:
          conf 0.8:  spawns pre/post = \(hi.spawnsPre)/\(hi.spawnsPost)  lean=\(String(format: "%.3f", leanMag))  newBreaks=\(hi.breaksAtBoundary)
          conf 0.05: spawns pre/post = \(lo.spawnsPre)/\(lo.spawnsPost)  lean=\(String(format: "%.3f", loLean))  newBreaks=\(lo.breaksAtBoundary)
        """)
        // 1. FLURRY: identical tiled audio, so post-boundary bursts > pre-boundary bursts is the pulse.
        #expect(hi.spawnsPost > hi.spawnsPre,
                "The boundary did not flurry the splatter (pre \(hi.spawnsPre) vs post \(hi.spawnsPost)).")
        // 2. LEAN: new pours lean toward the section's patch — nonzero, but bounded (allover intact).
        #expect(leanMag > 0.02 && leanMag <= SkeinState.sectionLeanRadius + 1e-4,
                "Section lean out of range (\(leanMag)) — expected (0.02, \(SkeinState.sectionLeanRadius)].")
        // 3. FRESH POUR: the boundary commits a new pour (a breakpoint lands in the boundary window).
        #expect(hi.breaksAtBoundary >= 1,
                "No fresh pour at the confident boundary (breakpoints +\(hi.breaksAtBoundary)).")
        // 4. CONFIDENCE GATE: at low confidence the bias is exactly zero — the pure allover read.
        #expect(lo.skein.sectionPulseCurrent == 0 && loLean == 0 && lo.breaksAtBoundary == 0,
                "Low-confidence structure leaked bias (pulse \(lo.skein.sectionPulseCurrent), lean \(loLean), breaks +\(lo.breaksAtBoundary)).")
    }

    // MARK: - BUG-046: section-boundary spacing guard (Skein.6, Matt-approved)

    /// The parked section-detector defect (BUG-042) machine-guns boundaries every ~1.7 s at HIGH
    /// confidence on busy streaming material (M7 session `2026-06-11T01-56-22Z`: conf 0.78–0.95 —
    /// the confidence gate alone does NOT filter it). Unguarded, that re-arms the flurry pulse
    /// continuously (≈2× the Matt-tuned spatter rate) and chops pours at ~1–1.7 τ (the rejected
    /// D-150 "lines too short" character). The guard: boundaries within `minSectionSpacingS`
    /// (10 wall-s) of the last ACCEPTED boundary are ignored wholesale. This gate replays tonight's
    /// cadence (a boundary every 100 frames ≈ 1.7 s, conf 0.9) against a sparse control (one
    /// boundary) on IDENTICAL tiled single-dominant real audio: pour count and spatter rate must
    /// stay near the control, and real (sparse) boundaries must still land.
    @Test("BUG-046: note-scale boundary junk is spacing-guarded — machine-gun sections ≈ sparse; real boundaries still land — live tick path")
    func test_structure_boundarySpacingGuard() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let raw = loadStemFrames(session, maxFrames: 6000), raw.count > 400 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping spacing-guard gate (real audio: feedback_synthetic_audio)")
            return
        }
        let slice = Self.mostDominatedSlice(raw, stem: Self.mostActiveStem(raw), window: 120).slice
        let total = 1800   // 30 s
        let dt: Float = 1.0 / 60.0

        func run(sectionIndex: @escaping (Int) -> Int) throws -> (breaks: Int, spawns: Int) {
            guard let skein = SkeinState(device: fx.ctx.device, seed: 0) else { throw SkeinHoldError.bufferFailed }
            for fi in 0..<total {
                let features = FeatureVector(time: Float(fi) * dt, deltaTime: dt, aspectRatio: 1.0)
                let structure = StructuralPrediction(
                    sectionIndex: UInt32(sectionIndex(fi)), sectionStartTime: 0,
                    predictedNextBoundary: 0, confidence: 0.9)
                skein.tick(deltaTime: dt, features: features, stems: slice[fi % slice.count],
                           structure: structure)
            }
            return (skein.colorBreakpoints.count, skein.totalBurstsSpawned)
        }

        let machineGun = try run { $0 / 100 }      // a "section" every 1.67 s — the BUG-042 junk shape
        let sparse = try run { $0 / 1200 }         // one boundary at 20 s — a real section change
        print("[skein_bug046] 30 s identical tiled audio: machine-gun breaks=\(machineGun.breaks) spawns=\(machineGun.spawns)  vs sparse breaks=\(sparse.breaks) spawns=\(sparse.spawns)")

        // 1. POURS: the guard caps boundary-forced pours at the 10 wall-s spacing (≈3 accepted in
        //    30 s) — far below the unguarded ~17 (one per junk boundary). Long pours survive.
        #expect(machineGun.breaks <= 6,
                "Machine-gun boundaries chopped \(machineGun.breaks) pours in 30 s — the spacing guard is not holding (unguarded ≈ 17).")
        // 2. SPATTER: the tuned rate survives — at most a modest elevation over the sparse control
        //    (unguarded the permanently re-armed pulse runs ≈ 2× the control).
        #expect(Float(machineGun.spawns) <= Float(sparse.spawns) * 1.5,
                "Machine-gun boundaries elevated spatter \(machineGun.spawns) vs control \(sparse.spawns) — the flurry pulse is being re-armed past the guard.")
        // 3. REAL BOUNDARIES STILL LAND: the sparse run's boundary commits its fresh pour
        //    (first-pour + the boundary pour) — the guard must not eat designed behaviour.
        #expect(sparse.breaks >= 2,
                "The sparse (real) boundary did not land a fresh pour (breaks \(sparse.breaks)) — the guard over-suppresses.")
    }

    /// The stem index with the highest total positive deviation over the session (the slice picker's
    /// anchor for a single-dominant tile).
    private static func mostActiveStem(_ stems: [StemFeatures]) -> Int {
        var sums = [Float](repeating: 0, count: 4)
        for s in stems {
            sums[0] += max(0, s.drumsEnergyDev); sums[1] += max(0, s.bassEnergyDev)
            sums[2] += max(0, s.vocalsEnergyDev); sums[3] += max(0, s.otherEnergyDev)
        }
        return sums.enumerated().max { $0.element < $1.element }?.offset ?? 0
    }

    // MARK: - Skein.5: anticipation — wind-up into the beat, flick at the wrap (FA #33)

    @Test("Anticipation: the painter slows into each beat and surges at the wrap; silence is exactly neutral — live tick path")
    func test_anticipation_windupFlick() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let raw = loadStemFrames(session, maxFrames: 2000), raw.count > 400 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping anticipation gate (real audio: feedback_synthetic_audio)")
            return
        }
        guard let skein = SkeinState(device: fx.ctx.device, seed: 0) else { throw SkeinHoldError.bufferFailed }
        let dt: Float = 1.0 / 60.0, bpm: Float = 120
        var windupSum: Float = 0; var windupN = 0
        var flickSum: Float = 0; var flickN = 0
        for fi in 0..<900 {
            let time = Float(fi) * dt
            var features = FeatureVector(time: time, deltaTime: dt, aspectRatio: 1.0)
            let beats = time * bpm / 60.0
            features.beatPhase01 = beats - floor(beats)   // the live BeatPredictor ramp shape
            skein.tick(deltaTime: dt, features: features, stems: raw[fi % raw.count])
            guard fi > 120 else { continue }   // past the stem warmup
            let factor = skein.anticipationFactorCurrent
            if features.beatPhase01 > 0.85 { windupSum += factor; windupN += 1 }
            if features.beatPhase01 < 0.10 { flickSum += factor; flickN += 1 }
        }
        let windupMean = windupN > 0 ? windupSum / Float(windupN) : 1
        let flickMean = flickN > 0 ? flickSum / Float(flickN) : 1
        print("[skein5_anticipation] 120 BPM ramp, real stems: windup mean \(windupMean) (n=\(windupN)), flick mean \(flickMean) (n=\(flickN))")
        // Wind-up: the hand slows in the last fraction of the beat…
        #expect(windupMean < 0.92, "No wind-up — factor \(windupMean) in the pre-beat window (expected < 0.92).")
        // …and the flick surges right after the wrap.
        #expect(flickMean > 1.05, "No flick — factor \(flickMean) right after the beat (expected > 1.05).")

        // Silence: exactly neutral (the Skein.1 silence-continuity contract) — factor == 1 every frame.
        guard let silent = SkeinState(device: fx.ctx.device, seed: 0) else { throw SkeinHoldError.bufferFailed }
        for fi in 0..<240 {
            let time = Float(fi) * dt
            var features = FeatureVector(time: time, deltaTime: dt, aspectRatio: 1.0)
            let beats = time * bpm / 60.0
            features.beatPhase01 = beats - floor(beats)
            silent.tick(deltaTime: dt, features: features, stems: .zero)
            #expect(silent.anticipationFactorCurrent == 1.0,
                    "Anticipation modulated the silence pour (factor \(silent.anticipationFactorCurrent) at frame \(fi)).")
        }
    }

    // MARK: - Skein.5: painter locus — display-only, build-flagged, OFF by default

    @Test("Locus: OFF by default; when flagged on, the glow is DISPLAY-ONLY — blit shows it, the held canvas is byte-identical")
    func test_locus_displayOnly() throws {
        #expect(SkeinState.defaultLocusEnabled == false, "The painter locus must ship OFF by default.")
        guard let fx = try loadSkeinFixture() else { return }
        let w = 192, h = 192, frames = 180
        func run(_ locus: Bool) throws -> PourResult {
            try runPourAccumulation(
                chromatic: 0, frames: frames, width: w, height: h, aspect: 1.0, startTime: 0,
                checkpoints: [], fx: fx, seed: 3, captureBlit: true,
                drive: MusicalityDrive(locusEnabled: locus))
        }
        let on = try run(true), off = try run(false)
        // 1. The held CANVAS is byte-identical — the locus never bakes (it would otherwise paint
        //    itself permanently; that is why it lives in the comp fragment, not the overlay).
        #expect(on.finalPixels == off.finalPixels,
                "The locus BAKED into the held canvas — it must be display-only (comp stage).")
        // 2. The BLIT (display) shows it: a localized region of pixels differs.
        var diff = 0
        for i in stride(from: 0, to: on.finalBlitPixels.count, by: 4) {
            if abs(Int(on.finalBlitPixels[i + 2]) - Int(off.finalBlitPixels[i + 2])) > 8 { diff += 1 }
        }
        print("[skein5_locus] blit pixels differing (locus on vs off): \(diff) of \(w * h)")
        #expect(diff > 20 && diff < (w * h) / 4,
                "Locus glow not visible (or not localized) in the display blit: \(diff) differing pixels.")
    }

    // MARK: - Skein.5 contact sheet (env-gated eyeball artifact)

    @Test("Skein.5 mood/locus contact sheet (env-gated: SKEIN_VISUAL=1 / RENDER_VISUAL=1)")
    func test_skein5_contactSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SKEIN_VISUAL"] == "1" || env["RENDER_VISUAL"] == "1" else {
            print("SkeinCanvasHoldTest: SKEIN_VISUAL/RENDER_VISUAL not set, skipping Skein.5 contact sheet")
            return
        }
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 1500), stems.count > 400 else { return }
        let w = 480, h = 480, frames = 1200
        // Panels: warm/calm × cool/vigorous corners + a locus panel (flag on).
        let drives: [(String, MusicalityDrive)] = [
            ("hiV_hiA", MusicalityDrive(valence: 0.8, arousal: 0.8)),
            ("hiV_loA", MusicalityDrive(valence: 0.8, arousal: -0.8)),
            ("loV_hiA", MusicalityDrive(valence: -0.8, arousal: 0.8)),
            ("loV_loA", MusicalityDrive(valence: -0.8, arousal: -0.8)),
            ("locus_on", MusicalityDrive(beatBPM: 120, locusEnabled: true))
        ]
        let dir = try makeOutputDir()
        var tiles: [[UInt8]] = []
        for (name, drive) in drives {
            let run = try runPourAccumulation(
                chromatic: 0, frames: frames, width: w, height: h, aspect: 1.0, startTime: 0,
                checkpoints: [], fx: fx, seed: 11, stemFrames: stems, captureBlit: true, drive: drive)
            let px = drive.locusEnabled ? run.finalBlitPixels : run.finalPixels
            tiles.append(px)
            try writeBGRAToPNG(px, w: w, h: h, url: dir.appendingPathComponent("skein5_\(name).png"))
        }
        try writeMontage(tiles, tileW: w, tileH: h, url: dir.appendingPathComponent("skein5_mood_montage.png"))
        print("[skein5_contact_sheet] wrote \(dir.path)/skein5_mood_montage.png (hiV_hiA | hiV_loA | loV_hiA | loV_loA | locus_on)")
    }

    /// Euclidean distance between two RGB triples (breakpoint-colour compare).
    private func dist3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b; return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
    }

    /// Classify the nearest painted pixel to `uv` (radius-2 search, Y-flipped) as colour X (0), colour
    /// Y (1), or neither/cream (-1) — reads the rendered line colour at a known trajectory position
    /// (painterPos(tau) + the pour's offset). BGRA byte order; `x255`/`y255` are display RGB × 255.
    private func sampleLineClass(_ buf: [UInt8], w: Int, h: Int, uv: SIMD2<Float>,
                                 x255: SIMD3<Float>, y255: SIMD3<Float>, cream: [UInt8]) -> Int {
        let cxp = Int((uv.x * Float(w)).rounded()), cyp = Int(((1 - uv.y) * Float(h)).rounded())
        let cb = Int(cream[0]), cg = Int(cream[1]), cr = Int(cream[2])
        var bestD = Int.max, bi = -1
        for dy in -2...2 {
            for dx in -2...2 {
                let x = cxp + dx, y = cyp + dy
                guard x >= 0, x < w, y >= 0, y < h else { continue }
                let i = (y * w + x) * 4
                if abs(Int(buf[i]) - cb) + abs(Int(buf[i + 1]) - cg) + abs(Int(buf[i + 2]) - cr) > 50 {
                    let dd = dx * dx + dy * dy
                    if dd < bestD { bestD = dd; bi = i }
                }
            }
        }
        guard bi >= 0 else { return -1 }   // cream (no painted pixel near the sampled position)
        let rr = Float(buf[bi + 2]), gg = Float(buf[bi + 1]), bb = Float(buf[bi])
        let dX = (rr - x255.x) * (rr - x255.x) + (gg - x255.y) * (gg - x255.y) + (bb - x255.z) * (bb - x255.z)
        let dY = (rr - y255.x) * (rr - y255.x) + (gg - y255.y) * (gg - y255.y) + (bb - y255.z) * (bb - y255.z)
        guard min(dX, dY) < 90 * 90 else { return -1 }   // painted but neither X nor Y (some other stem)
        return dX <= dY ? 0 : 1
    }

    /// The `window`-frame slice where `stem` most strongly LEADS (mean over the window of dev[stem] −
    /// max(other dev)). Real frames only — used to order two real slices into a clean dominant switch.
    private static func mostDominatedSlice(_ stems: [StemFeatures], stem: Int, window: Int)
        -> (slice: [StemFeatures], lead: Float) {
        guard stems.count > window else { return (stems, 0) }
        func lead(_ s: StemFeatures) -> Float {
            let d = [max(0, s.drumsEnergyDev), max(0, s.bassEnergyDev),
                     max(0, s.vocalsEnergyDev), max(0, s.otherEnergyDev)]
            let others = (0..<4).filter { $0 != stem }.map { d[$0] }.max() ?? 0
            return d[stem] - others
        }
        var sum: Float = 0
        for i in 0..<window { sum += lead(stems[i]) }
        var best = sum, bestIdx = 0
        for i in window..<stems.count {
            sum += lead(stems[i]) - lead(stems[i - window])
            if sum > best { best = sum; bestIdx = i - window + 1 }
        }
        return (Array(stems[bestIdx..<bestIdx + window]), best / Float(window))
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
        // Skein.5.1: at silence the painter rests (no line at all), so the sheet drives CALM real
        // stem frames — the pour line alone, in its committed colour, never white.
        guard let session = Self.firstRecordedSession(),
              let all = loadStemFrames(session, maxFrames: 6000), all.count > 400 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping contact sheet (real audio)")
            return
        }
        let calm = all.filter {
            max(max($0.drumsEnergyDev, $0.bassEnergyDev), max($0.vocalsEnergyDev, $0.otherEnergyDev))
                < SkeinState.onsetDevThreshold
        }
        guard calm.count >= 60 else {
            print("SkeinCanvasHoldTest: too few calm frames — skipping contact sheet")
            return
        }
        let frames = (checkpoints.max() ?? 0) + 1
        let stems = (0..<frames).map { calm[$0 % calm.count] }
        let run = try runPourAccumulation(
            chromatic: 0, frames: frames, width: w, height: h,
            aspect: Float(w) / Float(h), startTime: 0.0, checkpoints: Set(checkpoints), fx: fx,
            stemFrames: stems)

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
        // Skein.6 cert formalisation (§5.7 headline): the final canvas is dHash-stable across
        // the two full live-path runs, within the PresetRegressionTests tolerance (≤ 8 of 64).
        // Byte-identity (asserted below) is the stronger property; the dHash form is the named
        // cert gate, kept explicit so a future relaxation of byte-identity (e.g. a GPU/driver
        // nondeterminism) still has the §5.7 contract to answer to. Full-track-length evidence
        // (2 × 10,800 frames, pixel-diff 0, hamming 0) was captured at Skein.6 closeout.
        let dSame = (Self.dHash64(a1, w: w, h: h) ^ Self.dHash64(a2, w: w, h: h)).nonzeroBitCount

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
        #expect(dSame <= 8, "Final-canvas dHash unstable across two same-seed live-path runs (hamming \(dSame) > 8).")
        // 2. The seed actually perturbs the trajectory — a different seed paints differently.
        #expect(cross > 50, "Different seeds produced near-identical paintings (\(cross) px) — the seed does not reach the trajectory.")
        // 3. RESEED clears the live painter state (the §1.5 track-change reset).
        #expect(st.painterTau == 0, "reseed did not reset painterTau (\(st.painterTau)).")
        #expect(st.totalBurstsSpawned == 0, "reseed did not clear the burst ring (\(st.totalBurstsSpawned)).")
    }

    // MARK: - Skein.6 certification: coverage bound + full-track determinism dHash (§5.7)

    /// The §5.7 cert coverage invariant, at the TRACK-LENGTH scale the other gates don't reach
    /// (the remaining §5.7 invariants are standing gates: silence-non-black =
    /// PresetAcceptanceTests invariant 1 + the silence runs above; beat-ratio = the busy≫calm
    /// spawn gate in `test_realStem_colourSeparationAndRouting`; determinism =
    /// `test_seedDeterminismAndReseed`'s two-run byte-identity + dHash).
    ///
    /// Renders one typical-track-length (180 s @ 60 fps) live-path run on REAL recorded stems
    /// (tiled when the session is shorter — the tile preserves real dynamics) at a live-window
    /// scale. Coverage fraction is RESOLUTION-DEPENDENT (the droplet AA radius floor
    /// `max(drr, px·1.5)` widens sub-pixel satellites at small targets — measured +10–17 pts
    /// at 200×200 vs 900×600), so this gate renders at 600×400 and its thresholds are
    /// calibrated at that size. Matt's cert decision (2026-06-10, Skein.6 / D-159): the
    /// approved post-round-2-tune density stands; the §5.7 "ends 60–80 %" band was a
    /// pre-implementation estimate, superseded by never-solid / never-near-empty:
    ///   • NEVER SOLID — ground always breathes through (the anti_dead_mat failure mode).
    ///     Measured on the approved sessions at 900×600: 80.2 % at the longest approved
    ///     single track (43 s), plateau ≈ 87 % at 100 s.
    ///   • NEVER NEAR-EMPTY — a full track of dense material paints well past half the canvas.
    @Test("Skein.6 cert: track-length coverage bound (never solid, never near-empty) — live path, real stems")
    func test_cert_coverageBound() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 10_800), stems.count > 600 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping cert coverage test")
            return
        }
        let w = 600, h = 400   // live-window scale + aspect (coverage thresholds calibrated here)
        let frames = 10_800    // 180 s at 60 fps — a typical track
        let quarter = frames / 4
        let cps: Set<Int> = [quarter - 1, 2 * quarter - 1, 3 * quarter - 1, frames - 1]
        // Library mode = the live path (seed picks palette + ground together). Seed 4 → index 0
        // (fathom, the cream default) — deterministic, and the coverage counter's ground
        // reference works for any entry either way.
        let run = try runPourAccumulation(
            chromatic: 0, frames: frames, width: w, height: h, aspect: Float(w) / Float(h),
            startTime: 0.0, checkpoints: cps, fx: fx, stemFrames: stems, libraryPaletteSeed: 4)

        let total = Float(w * h)
        let covSeries = zip(run.checkpointFrames, run.checkpointCounts)
            .map { "f\($0)=\(String(format: "%.1f", Float($1) / total * 100))%" }
            .joined(separator: "  ")
        let finalCoverage = Float(run.checkpointCounts.last ?? 0) / total
        print("[skein_cert] coverage \(covSeries)  (\(stems.count) real frames tiled to \(frames), \(w)×\(h), session \(session.lastPathComponent))")
        // Env-gated eyeball artifact: the four checkpoint canvases as a montage (M7 prep).
        if ProcessInfo.processInfo.environment["SKEIN_VISUAL"] == "1"
            || ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" {
            let tiles = run.checkpointFrames.compactMap { run.checkpointPixels[$0] }
            let dir = try makeOutputDir()
            let url = dir.appendingPathComponent("skein6_cert_coverage_montage.png")
            try writeMontage(tiles, tileW: w, tileH: h, url: url)
            print("[skein_cert] checkpoint montage → \(url.path)")
        }

        // NEVER SOLID: a tiled multi-track replay with no per-track wipes is the densest input
        // the live app can ever exceed, so the ceiling is a regression tripwire on the approved
        // emission rates, not a product target.
        #expect(finalCoverage < 0.95, "Canvas painted \(finalCoverage * 100)% — reads as a solid over-covered mat (anti_dead_mat / density regression).")
        #expect(finalCoverage > 0.40, "Canvas only \(finalCoverage * 100)% painted after a full track of dense material — near-empty (density regression).")
    }

    // MARK: - Skein.6 certification: multi-hour canvas soak (§5.5 verify-don't-assume)

    /// The §5.5 soak: the 8-bit canvas under identity-hold must show no banding/drift over a
    /// MULTI-HOUR session. (The generic `SoakTestHarness` is the headless audio-path harness —
    /// memory + frame timing, no render — so it cannot observe the canvas; this gate runs the
    /// live mv_warp dispatch path instead, the same scene→warp→overlay→blit→swap loop the app
    /// dispatches, for a simulated 2-hour session.)
    ///
    /// Env-gated (`SKEIN_SOAK=1`, ~8–10 min wall): 432,000 frames = 120 simulated minutes.
    ///   Phase A — 15 min of tiled REAL stems: paint accumulates (the thin-paint layering §5.5
    ///             worries about: repeated alpha-over at the same texels).
    ///   Phase B — 90 min of silence: after a 60 s settle (the silence gate is an EMA —
    ///             stemMix decays over seconds, by design), the painter clock pauses and the
    ///             whole canvas (RGB paint record + wetness ALPHA, which holds at silence)
    ///             must be BYTE-IDENTICAL from the settled baseline to phase end — the
    ///             lossless-hold claim at the hours scale. Drift/banding would show here.
    ///   Phase C — 15 min of tiled real stems again: painting resumes (bursts fire),
    ///             never-white holds, coverage never shrinks.
    @Test("Skein.6 soak: 2-hour simulated session — lossless 8-bit hold, no banding/drift (SKEIN_SOAK=1)",
          .enabled(if: ProcessInfo.processInfo.environment["SKEIN_SOAK"] == "1"))
    func test_cert_soak_twoHourCanvasHold() throws {
        guard let fx = try loadSkeinFixture() else { return }
        guard let session = Self.firstRecordedSession(),
              let stems = loadStemFrames(session, maxFrames: 10_800), stems.count > 600 else {
            print("SkeinCanvasHoldTest: no recorded session — skipping soak")
            return
        }
        let device = fx.ctx.device, queue = fx.ctx.commandQueue
        let w = 200, h = 200
        let phaseA = 54_000, phaseB = 324_000, phaseC = 54_000   // 15 + 90 + 15 min @ 60 fps
        let frames = phaseA + phaseB + phaseC
        guard let skein = SkeinState(device: device, seed: 4) else { throw SkeinHoldError.bufferFailed }
        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: fx.ctx.pixelFormat, width: w, height: h, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard var warpTex = device.makeTexture(descriptor: fbDesc),
              var composeTex = device.makeTexture(descriptor: fbDesc),
              let blitTex = device.makeTexture(descriptor: fbDesc) else { throw SkeinHoldError.textureFailed }
        try clearTextures([warpTex, composeTex], to: fx.cream, context: fx.ctx)
        try clearTextures([blitTex], to: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1), context: fx.ctx)

        let dt: Float = 1.0 / 60.0
        func read(_ tex: MTLTexture) -> [UInt8] {
            var px = [UInt8](repeating: 0, count: w * h * 4)
            tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            return px
        }
        var creamRef: [UInt8] = []
        var holdSnapshot: [UInt8] = []       // canvas at the first phase-B frame
        var maxHoldDiff = 0                  // worst per-checkpoint byte diff across phase B
        var coverageEndA = 0
        var burstsEndB = 0
        let t0 = Date()
        for frameIdx in 0..<frames {
            let inSilence = frameIdx >= phaseA && frameIdx < phaseA + phaseB
            var features = FeatureVector(time: Float(frameIdx) * dt, deltaTime: dt, aspectRatio: 1.0)
            let stemFrame = inSilence ? StemFeatures.zero : stems[frameIdx % stems.count]
            skein.tick(deltaTime: dt, features: features, stems: stemFrame)
            guard let cmd = queue.makeCommandBuffer() else { throw SkeinHoldError.cmdBufferFailed }
            try encodeWarp(cmd: cmd, mvWarp: fx.mvWarp, warpTex: warpTex, composeTex: composeTex,
                           features: &features, chromatic: 0, wetnessDecay: skein.wetnessDecay)
            try encodeOverlay(cmd: cmd, overlay: fx.overlay, target: composeTex,
                              features: &features, skeinBuffer: skein.skeinBuffer)
            try encodeBlit(cmd: cmd, mvWarp: fx.mvWarp, src: composeTex, dst: blitTex,
                           post: SIMD4<Float>(0, 0, 1, 0), skeinBuffer: skein.skeinBuffer)
            cmd.commit()
            cmd.waitUntilCompleted()

            if frameIdx == 0 {
                let c = read(composeTex)
                creamRef = Array(c[(5 * w + 5) * 4..<(5 * w + 5) * 4 + 4])
            }
            if frameIdx == phaseA - 1 { coverageEndA = countPainted(read(composeTex), cream: creamRef) }
            // The hold baseline is taken AFTER a 60 s settle window, not at the first silent
            // frame: the silence gate is an EMA (stemMix decays over seconds — the Skein.5.1
            // design), so the painter clock + wetness decay legitimately run a few seconds
            // into phase B. The first soak run proved this empirically: a one-time 2342-byte
            // settle in the first checkpoint interval, then ZERO further change from B+10 min
            // to B+89 min. The §5.5 claim is about SUSTAINED silence, so the baseline is the
            // settled canvas.
            let settleFrames = 3600   // 60 s at 60 fps
            if frameIdx == phaseA + settleFrames { holdSnapshot = read(composeTex) }
            // Phase-B checkpoints every simulated 10 min + the last B frame: FULL byte-identity
            // (RGB + ALPHA — wetness holds at silence too) against the settled baseline. A
            // count-only comparison could hide an oscillation inside a constant diff count;
            // byte-level comparison against one fixed baseline cannot.
            if inSilence, frameIdx > phaseA + settleFrames,
               (frameIdx - phaseA) % 36_000 == 0 || frameIdx == phaseA + phaseB - 1 {
                let now = read(composeTex)
                var diffRGB = 0, diffA = 0
                var i = 0
                while i < now.count {
                    if now[i] != holdSnapshot[i] || now[i + 1] != holdSnapshot[i + 1]
                        || now[i + 2] != holdSnapshot[i + 2] { diffRGB += 1 }
                    if now[i + 3] != holdSnapshot[i + 3] { diffA += 1 }
                    i += 4
                }
                maxHoldDiff = max(maxHoldDiff, diffRGB + diffA)
                let mins = (frameIdx - phaseA) / 3600
                print("[skein_soak] B+\(mins)min hold-diff rgb=\(diffRGB)px alpha=\(diffA)px  (\(String(format: "%.1f", -t0.timeIntervalSinceNow / 60))min wall)")
            }
            if frameIdx == phaseA + phaseB - 1 { burstsEndB = skein.totalBurstsSpawned }
            if frameIdx == frames - 1 {
                let final = read(composeTex)
                let coverageEndC = countPainted(final, cream: creamRef)
                print("""
                [skein_soak] DONE \(frames)f (\(String(format: "%.1f", -t0.timeIntervalSinceNow / 60))min wall)
                  coverage endA=\(coverageEndA) endC=\(coverageEndC) px  maxHoldDiff=\(maxHoldDiff)px
                  bursts endB=\(burstsEndB) endC=\(skein.totalBurstsSpawned)
                """)
                // 1. LOSSLESS HOLD AT HOURS SCALE (§5.5): after the 60 s EMA settle, 89 min of
                //    silence changes NOTHING — RGB paint record and wetness alpha byte-identical.
                //    (No corner/"unreachable texel" check: at soak scale flicks legitimately
                //    reach the whole canvas — mirror-then-push-out placement — so no texel is
                //    structurally unpaintable; the whole-canvas B-phase identity IS the
                //    unpainted-ground drift check.)
                #expect(maxHoldDiff == 0, "Canvas changed \(maxHoldDiff) px during the settled 89-min silence hold — 8-bit identity-hold is NOT lossless (16-bit fallback territory; STOP and report).")
                // 2. Long-session integrity: never white, painting resumed after the hold.
                #expect(!hasWhiteTexel(final), "White texel after 2-h soak — never-white invariant broke at scale.")
                #expect(skein.totalBurstsSpawned > burstsEndB, "No bursts after the silence hold — painting did not resume in phase C.")
                #expect(coverageEndC >= coverageEndA, "Coverage shrank across the soak (\(coverageEndA) → \(coverageEndC)) — paint was lost.")
            }
            swap(&warpTex, &composeTex)
        }
    }

    /// 9×8 luma dHash (the PresetRegressionTests form): one bit per adjacent horizontal cell pair.
    private static func dHash64(_ bgra: [UInt8], w: Int, h: Int) -> UInt64 {
        var cells = [Float](repeating: 0, count: 9 * 8)
        for cy in 0..<8 {
            for cx in 0..<9 {
                let x0 = cx * w / 9, x1 = (cx + 1) * w / 9
                let y0 = cy * h / 8, y1 = (cy + 1) * h / 8
                var sum: Float = 0
                var n = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let i = (y * w + x) * 4
                        sum += 0.114 * Float(bgra[i]) + 0.587 * Float(bgra[i + 1]) + 0.299 * Float(bgra[i + 2])
                        n += 1
                    }
                }
                cells[cy * 9 + cx] = n > 0 ? sum / Float(n) : 0
            }
        }
        var hash: UInt64 = 0
        for cy in 0..<8 {
            for cx in 0..<8 where cells[cy * 9 + cx + 1] > cells[cy * 9 + cx] {
                hash |= 1 << UInt64(cy * 8 + cx)
            }
        }
        return hash
    }

    // MARK: - Real-stem palette contact sheet (env-gated: candidate palettes for Matt sign-off)

    /// Skein.5.3: the candidates are the curated library (`SkeinPaletteLibrary.candidates`) —
    /// the Skein.3 A/B/C trio grew into the six-entry library with a fixed role grammar
    /// (drums darkest / bass deep / vocals warm-bright / other contrast accent), each entry
    /// regression-locked by `SkeinPaletteLibraryTests`.
    private static var candidatePalettes: [(name: String, colors: [SIMD3<Float>])] {
        SkeinPaletteLibrary.candidates.map { ($0.name, $0.colors) }
    }

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
        // SKEIN_SHEET_FRAMES overrides the render length (e.g. 300 ≈ 5 s for an early-canvas
        // mark-anatomy panel where individual flicks are still separable — Skein.5.4 sheets).
        let frames = min(stems.count, Int(env["SKEIN_SHEET_FRAMES"] ?? "") ?? 1400)
        let outDir = try makeOutputDir()
        // Render the SAME real-stem sequence (seed 0) with each candidate palette so Matt compares
        // legibility/character on identical paint, through the live path.
        var tiles: [[UInt8]] = []
        for (idx, cand) in Self.candidatePalettes.enumerated() {
            // Skein.5.3b: LIBRARY MODE per entry — the seed picks palette AND ground together,
            // and the canvas clears to that entry's ground (light or dark), the live path.
            let run = try runPourAccumulation(
                chromatic: 0, frames: frames, width: w, height: h, aspect: Float(w) / Float(h),
                startTime: 0.0, checkpoints: [frames - 1], fx: fx,
                stemFrames: stems, libraryPaletteSeed: UInt32(idx))
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
          → skein_palette_candidates.png + one PNG per library entry
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
        var finalPainterTau: Float = 0             // painter clock at the last frame (corridor τ-range)
        var totalBurstsSpawned = 0                 // marks thrown over the run (flicks + drips —
                                                   //   the Skein.5.4 vigour-mechanism probe)
    }

    /// Skein.5 fixture drive: mood (constant smoothed-classifier-style valence/arousal), an
    /// optional beat-phase sawtooth (what the live BeatPredictor's `beatPhase01` ramp looks like
    /// at a steady BPM), an optional per-frame StructuralPrediction, and the locus build flag.
    /// Stems stay REAL replayed frames — these are the controlled fixture INPUTS the Skein.5
    /// done-when names (high/low valence, high/low arousal, a section boundary, a beat ramp).
    struct MusicalityDrive {
        var valence: Float = 0
        var arousal: Float = 0
        var beatBPM: Float = 0
        var structure: ((Int) -> StructuralPrediction)?
        var locusEnabled = false
    }

    /// Drive the live marks-on-top dispatch path for `frames` frames, advancing features.time by
    /// a fixed Δt each frame (so the painter moves and consecutive capsules chain exactly). Each
    /// frame: warp(prev) → overlay(this frame's swept capsule on top) → blit → read → swap.
    /// Mirrors `drawWithMVWarp`'s strandsOnTop branch (Pass 0 skipped; the ground is the clear).
    private func runPourAccumulation(
        chromatic: Float, frames: Int, width: Int, height: Int, aspect: Float, startTime: Float,
        checkpoints: Set<Int>, fx: SkeinFixture, capturePerFrame: Bool = false,
        seed: UInt32 = 0, palette: [SIMD3<Float>]? = nil, stemFrames: [StemFeatures] = [],
        captureWetness: Bool = false, captureBlit: Bool = false,
        drive: MusicalityDrive = MusicalityDrive(),
        libraryPaletteSeed: UInt32? = nil
    ) throws -> PourResult {
        let device = fx.ctx.device, queue = fx.ctx.commandQueue
        // Skein.3: the painter clock + onset-burst ring + per-stem colour live in SkeinState, bound
        // at fragment slot 6 of the overlay (the ENGINE.1.2 strands-on-top binding). The harness
        // ticks it each frame exactly as the live app's setMeshPresetTick does. `stemFrames` are
        // REAL replayed StemFeatures (feedback_synthetic_audio: never hand-authored envelopes); an
        // empty array drives StemFeatures.zero (silence → the pour line only, no onset bursts).
        //
        // Skein.5.3b: `libraryPaletteSeed` runs the state in LIBRARY MODE (the live path) — the
        // seed picks palette AND ground together, and the canvas clears to that entry's ground
        // (light or dark), exactly as the live track-change clear does. Default = explicit
        // palette + the classic cream (every pre-existing gate pinned, byte-identical).
        let skeinMaybe: SkeinState?
        if let libSeed = libraryPaletteSeed {
            skeinMaybe = SkeinState(device: device, seed: libSeed, locusEnabled: drive.locusEnabled)
        } else {
            skeinMaybe = SkeinState(device: device, seed: seed,
                                    palette: palette ?? SkeinState.defaultPalette,
                                    locusEnabled: drive.locusEnabled)
        }
        guard let skein = skeinMaybe else { throw SkeinHoldError.bufferFailed }
        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: fx.ctx.pixelFormat, width: width, height: height, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard var warpTex = device.makeTexture(descriptor: fbDesc),
              var composeTex = device.makeTexture(descriptor: fbDesc),
              let blitTex = device.makeTexture(descriptor: fbDesc)
        else { throw SkeinHoldError.textureFailed }
        // Held ground IS the canvas clear (not black) — the D-143 fix; Skein.5.3b: in library
        // mode the clear is the ENTRY's ground (mirrors the live setMVWarpCanvasGround path).
        let groundClear: MTLClearColor
        if libraryPaletteSeed != nil {
            let gl = skein.groundLinear
            groundClear = MTLClearColor(red: Double(gl.x), green: Double(gl.y),
                                        blue: Double(gl.z), alpha: 1.0)
        } else {
            groundClear = fx.cream
        }
        try clearTextures([warpTex, composeTex], to: groundClear, context: fx.ctx)
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
            let time = startTime + Float(frameIdx) * dt
            var features = FeatureVector(
                valence: drive.valence, arousal: drive.arousal,
                time: time, deltaTime: dt, aspectRatio: aspect)
            // Skein.5: an optional steady-BPM beat-phase ramp (the shape the live BeatPredictor
            // publishes) for the anticipation wind-up/flick fixture.
            if drive.beatBPM > 0 {
                let beats = time * drive.beatBPM / 60.0
                features.beatPhase01 = beats - floor(beats)
            }
            // Tick SkeinState with this frame's REAL stems (or silence). Advances painterTau (the
            // audio-modulated painter clock), detects per-stem onsets → burst ring, and writes the
            // slot-6 buffer the overlay fragment reads. Same call the live setMeshPresetTick makes.
            let stems = stemFrames.isEmpty ? StemFeatures.zero : stemFrames[frameIdx % stemFrames.count]
            skein.tick(deltaTime: dt, features: features, stems: stems,
                       structure: drive.structure?(frameIdx) ?? .none)
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
            // Pass 3: blit (display-only, identity post) — faithful to the live present pass,
            // including the Skein.5 buffer-1 binding (the display-only locus reads it).
            try encodeBlit(cmd: cmd, mvWarp: fx.mvWarp, src: composeTex, dst: blitTex,
                           post: SIMD4<Float>(0, 0, 1, 0),   // invert0 echo0 gamma1 beat0 = identity
                           skeinBuffer: skein.skeinBuffer)
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
            finalBlitPixels: finalBlitPixels, checkpointBlitPixels: checkpointBlitPixels,
            finalPainterTau: skein.painterTau, totalBurstsSpawned: skein.totalBurstsSpawned)
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
        src: MTLTexture, dst: MTLTexture, post: SIMD4<Float>,
        skeinBuffer: MTLBuffer? = nil
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
        // Skein.5: the live blit binds the per-preset buffer at fragment buffer 1 (the display-only
        // painter locus reads SkeinUniforms there). Mirror it for dispatch-path parity (FA #66).
        if let skeinBuffer {
            enc.setFragmentBuffer(skeinBuffer, offset: 0, index: 1)
        }
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
        recordedSessionsBySize().first
    }

    /// All recorded sessions with a non-empty stems.csv, largest first. Tests whose assertion
    /// depends on a *property* of the session content (e.g. the colour-freeze gate needs two
    /// stem-dominated slices) iterate this list instead of hard-depending on the single largest
    /// session — every new live session Matt records changes which session is largest, and a
    /// session-fragile gate goes red on data, not code (the Skein.4.1 `distinctBlobs` lesson).
    private static func recordedSessionsBySize() -> [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/phosphene_sessions")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: nil) else { return [] }
        func stemsSize(_ url: URL) -> Int {
            let path = url.appendingPathComponent("stems.csv").path
            guard FileManager.default.fileExists(atPath: path) else { return 0 }
            return ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
        }
        return entries.filter { stemsSize($0) > 0 }.sorted { stemsSize($0) > stemsSize($1) }
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
