// MeshGenerator+RenderClock — the render-rate frame delta the FTR.14 glide runs on.
//
// WHY THIS IS A SEPARATE FILE AND A SEPARATE CLOCK. `BeatHold`'s glide needs wall-clock seconds
// since the last DRAW (~1/60 s). Nothing in the mesh draw path carried one, and
// `FeatureVector.time` advances at the ~10 Hz ANALYSIS rate on the local-file path (BUG-087) —
// using it is exactly the mistake that made FTR.13's "smooth ease" render as a two-sample
// staircase. Clock at the edge, pure math inside: this file owns the clock, `BeatHold` takes the
// delta as a parameter and stays deterministic under test.

import CoreFoundation
import Metal
import Shared

extension MeshGenerator {

    /// Seconds since the previous `draw`, clamped. The clamp covers the first frame, a preset
    /// switch, and a stall: an unclamped delta after a 2 s hitch would snap the glide to its
    /// target in one frame, which is the artifact this whole increment removes.
    func nextRenderDelta() -> Float {
        if let renderDeltaOverride { return renderDeltaOverride }
        let now = CFAbsoluteTimeGetCurrent()
        defer { lastDrawTime = now }
        guard lastDrawTime > 0 else { return 1.0 / 60.0 }
        return Float(min(max(now - lastDrawTime, 1.0 / 240.0), 1.0 / 15.0))
    }

    /// Feed a frame through the beat hold WITHOUT drawing it.
    ///
    /// Only for harnesses that render a subsampled strip of a capture: the hold needs every
    /// frame in order to see beat boundaries at all, and a harness that renders every
    /// seventh row would otherwise measure a hold driven by an aliased phase. Call this for
    /// the rows you skip; `draw` already feeds the rows you render.

    /// Advance the beat clock AND the glide, without drawing.
    ///
    /// For still-frame harnesses only: a single draw per drive condition captures the glide's
    /// first step from the previous condition rather than the geometry at this one. Call this
    /// repeatedly to settle, then draw. Distinct from ``advanceBeatHold(_:stems:)``, which
    /// advances only the BEAT clock and must not move the glide (a subsampled strip would
    /// otherwise glide at the wrong rate).
    public func advanceBeatHoldForSettling(_ features: FeatureVector, stems: StemFeatures = .zero) {
        let delta = nextRenderDelta()
        advanceAllHolds(features, stems: stems, delta: delta)
    }

    /// ⚠ EVERY hold, on every path. FTR.18 shipped a rendered A/B that measured nothing because
    /// `advanceBeatHold` left the glides on their frame-0 seed; FTR.30 repeated it by adding
    /// `arcHold` to `draw` alone, which made the buffer(7) wiring gate compare two unseeded arcs
    /// and read them as identical. A hold that is not advanced on undrawn frames is a hold whose
    /// state depends on the draw cadence.
    func advanceAllHolds(_ features: FeatureVector, stems: StemFeatures, delta: Float) {
        sectionHold.offerStems(stems)
        let section = sectionHold.update(features, renderDeltaTime: delta)
        // FTR.33 — and the growth stepper, for the same reason: it holds state across frames, so
        // a frame that is not drawn still has to reach it or its tier depends on the draw cadence.
        _ = advanceGrowthStep(section: section, live: features, delta: delta)
        arcHold.offerStems(stems)
        _ = arcHold.update(features, renderDeltaTime: delta)
        beatHold.offerStems(stems)
        _ = beatHold.update(features, renderDeltaTime: delta)
    }

    /// Advance both holds for a frame that is NOT drawn.
    ///
    /// ★ BOTH GLIDES ADVANCE WITH THE REAL DELTA, and the earlier `0` here was a bug that
    /// invalidated rendered A/Bs. The original reasoning — "a subsampled strip would otherwise
    /// glide at the wrong rate" — is backwards: a glide is a WALL-CLOCK filter, so it must advance
    /// with elapsed time on every frame whether or not that frame is rasterised. Passing 0 meant a
    /// strip rendered with `FT_SKIP` reached its first drawn row with both glides still sitting on
    /// their frame-0 SEED. Consequences that were each mistaken for something else:
    ///   • a rendered A/B looked fuller in a window whose measured correction was exactly 0.000;
    ///   • the level term the shader saw was near its seed, so a gate keyed on "level is low" was
    ///     wide open in a passage where level was actually 0.515.
    /// The beat CLOCK is unaffected either way — `update` advances it from `beatPhase01`
    /// regardless of the delta.
    ///
    /// ★★★ FTR.33 — THIS NOW DELEGATES, and the duplication it used to carry cost an increment
    /// for the THIRD time. This method and `advanceAllHolds` had the same body with a different
    /// delta source, so adding the FTR.33 growth stepper to one left the other silently short of
    /// it — and every undrawn row in the subsampled sequence harness comes through HERE. The
    /// stepper needs ~6 s of history before it will change tier, and on an 8-frame strip it saw
    /// 0.13 s, so it sat at its bottom tier for the whole render: the rendered sheet showed a
    /// small, sparse tree that held perfectly still, and both of those looked exactly like a
    /// calibration problem. One recalibration was spent on the wrong cause before the frames
    /// stopped matching the arithmetic. Two copies of "advance everything" is the defect; there
    /// is now one.
    public func advanceBeatHold(_ features: FeatureVector, stems: StemFeatures = .zero) {
        advanceAllHolds(features, stems: stems, delta: renderDeltaOverride ?? Float(1.0 / 60.0))
    }
}

// MARK: - FTR.28 the dance clocks

extension MeshGenerator {

    /// Substitute render-rate, phase-locked versions of both dance clocks into the vector every
    /// preset stage reads. Split out of `draw` to keep `MeshGenerator.swift` inside the 400-line
    /// budget — the same reason `+RenderClock` and `+Blend` exist.
    ///
    /// The tempo offered here is `BeatHold`'s when it has one, but `DancePhase` does not depend on
    /// it: that hold vouches for a tempo on only 13 % of frames on real captures, and gating the
    /// dance on it produced no lock at all. See `DancePhase` for the measurement.
    /// ★★★ FTR.31 — AND THE HOLDS MUST BE FED THE OUTPUT OF THIS, NOT THE RAW VECTOR.
    ///
    /// `BeatHold` detects a beat by watching `beatPhase01` wrap and measures the intervals between
    /// wraps to decide whether the grid is trustworthy. Fed the RAW field it watches a staircase —
    /// ~15 updates a second in steps of ~0.109 of a beat — and its intervals carry ±0.069 s of
    /// quantisation jitter on a 0.638 s beat.
    ///
    /// Fed the LOCKED phase, with `DancePhase`'s rate estimator corrected (see that type), the
    /// same hold on the same capture goes from vouching for a tempo on **0 of 3000 frames to
    /// 2650 of 3000 (88 %)**, at 0.2 % tempo error. That is what made "tips on the beat"
    /// buildable with machinery that has existed since FTR.10 — and it means the beat-step Matt
    /// chose at FTR.10 had never actually been engaging.
    func applyDanceClocks(to feat: inout FeatureVector,
                          live: FeatureVector,
                          renderDelta: Float) {
        let beatPeriod = beatHold.beatPeriodSeconds ?? 0
        // A bar clock is the signal that a grid exists at all; without one both phases read 0 and
        // the tree stands still, which is the cold-start phase contract.
        let hasGrid = live.beatsPerBar > 0.5
        feat.beatPhase01 = beatDance.advance(measured: hasGrid ? live.beatPhase01 : nil,
                                            periodSeconds: beatPeriod,
                                            deltaTime: renderDelta)
        feat.barPhase01 = barDance.advance(measured: hasGrid ? live.barPhase01 : nil,
                                           periodSeconds: beatPeriod * max(live.beatsPerBar, 1),
                                           deltaTime: renderDelta)
    }
}

// MARK: - FTR.33 the growth step

extension MeshGenerator {

    /// Advance the size's tier and bind it at object/mesh buffer(8).
    ///
    /// Slot 8 on the MESH stages is free — the ray-march path's `setDirectPresetFragmentBuffer3`
    /// uses slot 8 of the FRAGMENT encoder, a different pipeline, the same reasoning that made
    /// slots 4 and 5 safe at FTR.10/FTR.13.
    func bindGrowthStep(_ encoder: MTLRenderCommandEncoder,
                        section: FeatureVector,
                        live: FeatureVector,
                        delta: Float) {
        var growth = advanceGrowthStep(section: section, live: live, delta: delta)
        // KEPT, env-gated. This trace found the real cause of a stuck tier in one run after two
        // recalibrations chased the wrong one; a size channel whose state is invisible is a size
        // channel that gets debugged by guessing. `print` is deliberate — a diagnostic the
        // developer asks for by name, not engine logging (Logging.swift stays the app's).
        if ProcessInfo.processInfo.environment["FT_TRACE_GROWTH"] == "1" {
            let rank = min(max(section.spectralSectionRatio * 0.5, 0), 1)
            let numbers = String(
                format: "t=%.1f growth=%.3f rank=%.3f rise=%.2f | ",
                live.trackElapsedS,
                growth,
                rank,
                live.spectralLevelRise
            )
            print("[growth] " + numbers + growthStep.debugState)
        }
        encoder.setObjectBytes(&growth, length: MemoryLayout<Float>.stride, index: 8)
        encoder.setMeshBytes(&growth, length: MemoryLayout<Float>.stride, index: 8)
    }

    /// One frame of `ArrivalStep`, on the section-scale DENSITY RANK.
    ///
    /// `spectral_section_ratio` is DYN.2c's rank of this moment in the track's own density
    /// distribution, so the tier edges in `ArrivalStep` can be constants — see the argument
    /// there, and the two calibrations that had to fail first. The ×0.5 matches the convention
    /// the drifting `fullness` term used, where 1.0 means "this track's normal".
    ///
    /// FTR.18's limiter correction is deliberately NOT applied here: it existed because LEVEL
    /// dips as a band arrives on a limited master, and density is the signal that detected that
    /// inversion rather than suffering from it.
    @discardableResult
    func advanceGrowthStep(section: FeatureVector, live: FeatureVector, delta: Float) -> Float {
        let rank = min(max(section.spectralSectionRatio * 0.5, 0), 1)
        return growthStep.update(level: rank,
                                 arrival: live.spectralLevelRise,
                                 deltaTime: delta)
    }
}
