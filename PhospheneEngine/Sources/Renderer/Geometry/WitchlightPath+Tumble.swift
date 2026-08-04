// WitchlightPath+Tumble.swift — the drawing plane's orientation.
//
// Split out of `WitchlightPath.swift` at WL.3 for the 400-line lint. It earns its own file:
// this is the code behind the single defect that three consecutive M7s reported as "it makes
// the same shape every time", and the reasoning for the bound is longer than the bound.

import Foundation

// MARK: - Plane tumble (WL.3)

extension WitchlightPath {

    /// WL.3 — the tumble is BOUNDED, and this is the fix for "it makes the same shape every
    /// time" (Matt, three M7s running).
    ///
    /// `tumbleYaw` used to be `0.055 * tumbleClock`: **unbounded**, rotating the drawing
    /// plane forever at 0.055 rad/s and passing through edge-on every ~57 s. Beads sit at
    /// `z = 0`, so pitch maps y→z and yaw then folds that z back into x; at yaw = 90° both
    /// screen axes become proportional to the same coordinate and **the entire figure
    /// collapses to a line**. Near edge-on, every figure looks like the same diagonal lens
    /// regardless of what the pen drew — and because the collapse runs on a wall clock, every
    /// track collapses identically at the same moment.
    ///
    /// That is what made the preset look like it drew one shape. It did not: zeroing the
    /// tumble and re-rendering the three fixtures produced three obviously different legible
    /// figures (a sweeping curve into a loop, an S-curve with a closed circle, a hook with a
    /// tight spiral) from the SAME motion model. The long-standing WL.2 open decision — "the
    /// stroke does not read as a figure, cause is mechanism-level `θ ≈ k·φ̄`" — was wrong; the
    /// path was fine and the projection was destroying it.
    ///
    /// Bounded to ±26° of yaw so `cos(yaw) ≥ 0.90` and the plane never approaches edge-on.
    /// The tumble still reads as depth — that is its job — it just can no longer flatten the
    /// drawing. `sessionPhase` varies the starting orientation per session so a repeat play is
    /// the same figure seen from a different angle (Matt's call, 2026-08-04).
    public var tumbleYaw: Float { 0.45 * sin(0.031 * tumbleClock + sessionPhase) }
    public var tumblePitch: Float { 0.45 * sin(0.041 * tumbleClock + sessionPhase * 1.7) }
    public var tumbleRoll: Float {
        tumbleHandedness * 0.19 * sin(0.027 * tumbleClock + sessionPhase * 0.6 + 1.1)
    }
}
