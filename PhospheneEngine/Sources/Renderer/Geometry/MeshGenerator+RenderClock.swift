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
}
