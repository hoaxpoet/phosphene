// LumenPatterns — Pattern factories + per-kind tuning defaults for LM.4.
//
// `LumenPatternEngine` owns the active-pattern pool, advances `phase` per
// frame, dispatches spawn triggers (drum-onset rising edges + bar-counter
// rising edges), and writes the resulting `LumenPattern` snapshots into
// `LumenPatternState.patterns` for the shader. This file provides the
// stateless factories the engine uses to construct a new pattern at spawn
// time + the durations and peak-intensity defaults.
//
// `LumenMosaic.metal` evaluates patterns per-fragment via
// `lm_evaluate_active_patterns`, dispatching on `LumenPattern.kindRaw`.
//
// LumenPattern coordinate convention (LM.4):
//   - `origin` is in `[0, 1]²` UV space (panel-face, with origin at the
//     bottom-left of the visible frame).
//   - Sweep `direction` is a unit vector in the same space.
//   - The shader remaps the cell-centre uv from `panel_uv ∈ [-1, +1]` to
//     `[0, 1]` at the integration site before calling the per-pattern
//     evaluators — see the integration block in `sceneMaterial`.
//
// **Patterns inject INTENSITY, not COLOUR (LM.3.2 architecture).** The
// `colorR/G/B` fields on `LumenPattern` stay zero in LM.4: each cell already
// carries its own colour from `lm_cell_palette`, and pattern contributions
// brighten cells they cross. A ripple firing on a warm-red cell flashes
// warm-red; on a cool-cyan cell, cool-cyan. The frost halo at cell
// boundaries (round 7 frost) also brightens — intentional and visually
// correct (the halo glows when the wavefront crosses it).
//
// References:
//   docs/presets/LUMEN_MOSAIC_DESIGN.md §4.4 (intent — note the §4.4 prose
//     describing agent-position backlight is LM.3.1 era and superseded).
//   docs/CLAUDE.md (Audio Data Hierarchy — patterns are accent-only,
//     never the primary motion driver).

import Foundation
import simd

// MARK: - LumenPatternFactory

/// Stateless factories for the three LM.4 pattern kinds. The engine calls
/// these at spawn time to construct a snapshot it then advances frame-by-frame.
///
/// LM.5 will extend this with `clusterBurst`, `breathing`, and `noiseDrift`.
public enum LumenPatternFactory {

    /// Default lifetime for a radial ripple. Calibrated against ~120 BPM
    /// (one beat ≈ 0.5 s) — a kick fires a ripple that lasts just over one
    /// beat, long enough to read, short enough that successive kicks layer
    /// rather than smear.
    public static let radialRippleDuration: Float = 0.6

    /// Default lifetime for a sweep. Sweep position traverses [-1, +1]
    /// along the direction axis over `phase ∈ [0, 1]`; at 0.8 s the
    /// effective panel-traversal phase (where the wavefront is inside the
    /// `[0, 1]` UV region) takes ~0.4 s — half a beat at 120 BPM.
    public static let sweepDuration: Float = 0.8

    /// Peak pattern intensity injected into `cell_intensity`. The shader
    /// scales this by `kPatternBoost (0.4)` before adding to the per-cell
    /// intensity, so the effective peak contribution at the wavefront is
    /// ~0.4 above the LM.3.2 hash-jitter + bar-pulse baseline.
    public static let defaultPeakIntensity: Float = 1.0

    /// Idle pattern — zero everywhere, kindRaw = 0. Pool padding slot.
    public static func idle() -> LumenPattern { .idle }

    /// Radial ripple: an expanding ring of brightness from `origin`,
    /// narrowing as it grows. Auto-retires when `phase` exceeds 1.0.
    ///
    /// Engine-side: spawned on rising-edge of `f.beatBass` AND on
    /// bar-rotation events when the mood-weighted hash selects ripple.
    public static func radialRipple(
        origin: SIMD2<Float>,
        birthTime: Float,
        duration: Float = radialRippleDuration,
        intensity: Float = defaultPeakIntensity
    ) -> LumenPattern {
        var pattern = LumenPattern.idle
        pattern.originX = origin.x
        pattern.originY = origin.y
        // `direction` is unused by radial ripple (no axis); zeroed.
        pattern.directionX = 0
        pattern.directionY = 0
        pattern.colorR = 0; pattern.colorG = 0; pattern.colorB = 0
        pattern.phase = 0
        pattern.intensity = intensity
        pattern.startTime = birthTime
        pattern.duration = max(duration, 1e-3)
        pattern.kindRaw = LumenPatternKind.radialRipple.rawValue
        return pattern
    }

    /// Sweep: a linear wavefront entering at `origin` (typically a panel
    /// edge midpoint) and traversing toward the opposite edge along
    /// `direction`. The shader's `sweep_position = phase × 2 − 1` makes
    /// the wavefront cross the panel over the second half of the
    /// lifetime; the first half is a Gaussian-tail entry from below.
    ///
    /// Engine-side: spawned on bar-rotation events when the mood-weighted
    /// hash selects sweep.
    public static func sweep(
        origin: SIMD2<Float>,
        direction: SIMD2<Float>,
        birthTime: Float,
        duration: Float = sweepDuration,
        intensity: Float = defaultPeakIntensity
    ) -> LumenPattern {
        // Normalise direction. A zero-length direction would collapse the
        // Gaussian band to a horizontal line at projected = 0 — defensive
        // fallback to +Y so the sweep is never visually undefined.
        var dir = direction
        let len = simd_length(dir)
        if len > 1e-6 {
            dir /= len
        } else {
            dir = SIMD2<Float>(0, 1)
        }
        var pattern = LumenPattern.idle
        pattern.originX = origin.x
        pattern.originY = origin.y
        pattern.directionX = dir.x
        pattern.directionY = dir.y
        pattern.colorR = 0; pattern.colorG = 0; pattern.colorB = 0
        pattern.phase = 0
        pattern.intensity = intensity
        pattern.startTime = birthTime
        pattern.duration = max(duration, 1e-3)
        pattern.kindRaw = LumenPatternKind.sweep.rawValue
        return pattern
    }
}
