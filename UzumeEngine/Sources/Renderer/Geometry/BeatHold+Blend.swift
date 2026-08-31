// BeatHold+Blend — the element-wise snapshot blend behind the glide.
//
// Split from `BeatHold.swift` when it crossed the 400-line lint bar. Kept together because the
// two functions share one non-obvious property: `FeatureVector` and `StemFeatures` are all-Float
// by construction, so the blend walks their raw storage rather than naming 47 and 58 fields that
// a newly-added property could silently escape. `BeatHoldTests.blendedStructsAreFloatOnly` is the
// guard that keeps that true.

import Foundation
import Shared

extension BeatHold {

    /// Element-wise lerp of two snapshots.
    ///
    /// `FeatureVector` is 47 stored properties and every one is a `Float` (verified by
    /// `BeatHoldTests.everyFeatureVectorFieldIsFloat`, which fails if a non-`Float` field is
    /// ever added), so the blend runs over the raw float storage instead of 47 hand-written
    /// lines that a new field would silently escape.
    ///
    /// CLOCKS ARE NOT BLENDED. `time`, `beatPhase01`, `barPhase01` and `pulseBeatIndex` are
    /// copied from the live frame: a phase lerped across its 1 → 0 wrap runs BACKWARDS, and a
    /// consumer reading a clock wants the real one. (The pre-FTR.13 hard hold froze these too,
    /// so this is strictly better, not a new obligation.)
    static func lerp(
        _ from: FeatureVector, _ to: FeatureVector, _ weight: Float,
        clocksFrom live: FeatureVector
    ) -> FeatureVector {
        // t == 0 is the beat frame itself and must return the PREVIOUS value — the ease starts
        // from where the eye already was. Returning `b` there put a one-frame snap on every
        // beat, i.e. precisely the artifact FTR.13 exists to remove; caught by
        // `BeatHoldTests.blendedStructsAreFloatOnly`.
        var out = weight <= 0 ? from : to
        if weight > 0 && weight < 1 {
            let count = MemoryLayout<FeatureVector>.size / MemoryLayout<Float>.size
            withUnsafeMutableBytes(of: &out) { destination in
                withUnsafeBytes(of: from) { nearBytes in
                    withUnsafeBytes(of: to) { farBytes in
                        let output = destination.bindMemory(to: Float.self)
                        let near = nearBytes.bindMemory(to: Float.self)
                        let far = farBytes.bindMemory(to: Float.self)
                        for i in 0..<count {
                            output[i] = near[i] + (far[i] - near[i]) * weight
                        }
                    }
                }
            }
        }
        out.time = live.time
        out.beatPhase01 = live.beatPhase01
        out.barPhase01 = live.barPhase01
        out.pulseBeatIndex = live.pulseBeatIndex
        return out
    }

    /// `lerp` for the stem side. `StemFeatures` is 58 stored properties and every one is a
    /// `Float` (gated by `BeatHoldTests.everyStemFeaturesFieldIsFloat`); it carries no clocks,
    /// so nothing needs restoring from a live frame.
    static func lerpStems(
        _ from: StemFeatures, _ to: StemFeatures, _ weight: Float
    ) -> StemFeatures {
        guard weight > 0, weight < 1 else { return weight <= 0 ? from : to }
        var out = to
        let count = MemoryLayout<StemFeatures>.size / MemoryLayout<Float>.size
        withUnsafeMutableBytes(of: &out) { destination in
            withUnsafeBytes(of: from) { nearBytes in
                withUnsafeBytes(of: to) { farBytes in
                    let output = destination.bindMemory(to: Float.self)
                    let near = nearBytes.bindMemory(to: Float.self)
                    let far = farBytes.bindMemory(to: Float.self)
                    for i in 0..<count {
                        output[i] = near[i] + (far[i] - near[i]) * weight
                    }
                }
            }
        }
        return out
    }

    // MARK: - Private
}
