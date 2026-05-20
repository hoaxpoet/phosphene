// RouteSpec.swift — Generic preset-route analysis primitives.
//
// A "route" is one (audio primitive → visual response) mapping in a preset.
// SR.1 measures routes at the input layer: for each frame, did the route's
// gate condition fire? How strong was the input? Over the whole session,
// what fraction of frames did the route fire on, and what was the per-event
// distribution?
//
// SR.1 deliberately does NOT measure the visual output (yet). The visual
// half of the audio→visual map is harder: it requires per-frame inspection
// of the rendered output. That's component 2/3 of the dossier (audio-event
// montage + motion-band analysis) and lands here in subsequent modules.
//
// This file defines:
//   1. RouteSpec — the description of one route (name, gate logic, value
//      extractor) that runs over a stream of SessionFrames.
//   2. RouteFiringReport — per-route firing statistics computed across the
//      session.
//   3. Helpers (smoothstep) that match the shader-side primitives exactly.
//
// The point of doing this in Swift inside the package: route specs SHOULD
// be defined alongside the preset's Swift state class wherever possible, so
// gate constants stay in sync. AuroraVeilRoutes.swift demonstrates the
// pattern.

import Foundation

/// Description of one audio→visual route in a preset.
///
/// `inputValue` extracts a single scalar from a frame's audio state — the
/// quantity the route is gated on (e.g., `bassDev`, `drumsEnergyDev`, or a
/// derived value like `pitchConfident && abs(smoothedPitchNorm - 0.5) > 0.05`).
///
/// `gateThreshold` is the value above which the route is considered to be
/// firing. For routes with a smoothstep gate (e.g. `smoothstep(0.30, 0.55,
/// bassDev)`), use the LOW edge — that's the point above which the route's
/// visual response becomes non-zero.
///
/// `partialGateThreshold` is an optional intermediate level (e.g. the
/// smoothstep HIGH edge above which the route reaches its full visual
/// response). Reported separately so we can distinguish "input crossed the
/// floor but only partially" from "input crossed the ceiling and the route
/// fired at full amplitude."
public struct RouteSpec: Sendable {
    public let name: String
    public let description: String
    public let inputName: String   // human-readable name of the primitive
    public let gateThreshold: Float
    public let partialGateThreshold: Float?

    /// Extracts the route's input scalar from a frame. May incorporate
    /// stem-warmup blending, CPU-side smoothing, or any other per-frame
    /// transform the shader applies before its gate check.
    public let inputValue: @Sendable (SessionFrame) -> Float

    public init(
        name: String,
        description: String,
        inputName: String,
        gateThreshold: Float,
        partialGateThreshold: Float? = nil,
        inputValue: @Sendable @escaping (SessionFrame) -> Float
    ) {
        self.name = name
        self.description = description
        self.inputName = inputName
        self.gateThreshold = gateThreshold
        self.partialGateThreshold = partialGateThreshold
        self.inputValue = inputValue
    }
}

/// Aggregate firing statistics for one route over one session.
public struct RouteFiringReport: Sendable {
    public let route: RouteSpec
    public let totalFrames: Int
    public let firingFrames: Int         // input >= gateThreshold
    public let partialFiringFrames: Int? // input >= partialGateThreshold (if set)
    public let inputMin: Float
    public let inputMax: Float
    public let inputMean: Float
    public let inputP50: Float
    public let inputP90: Float
    public let inputP99: Float

    public var firingPercent: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(firingFrames) / Double(totalFrames) * 100.0
    }

    public var partialFiringPercent: Double? {
        guard let pf = partialFiringFrames, totalFrames > 0 else { return nil }
        return Double(pf) / Double(totalFrames) * 100.0
    }
}

/// Analyzer that scans a session and emits per-route firing reports.
public enum RouteAnalyzer {

    public static func analyze(
        route: RouteSpec,
        session: SessionData
    ) -> RouteFiringReport {
        let values = session.frames.map(route.inputValue)
        let firing = values.filter { $0 >= route.gateThreshold }.count
        let partial = route.partialGateThreshold.map { thresh in
            values.filter { $0 >= thresh }.count
        }
        let sorted = values.sorted()
        let mean = values.reduce(0, +) / Float(max(values.count, 1))

        func percentile(_ pct: Double) -> Float {
            guard !sorted.isEmpty else { return 0 }
            let idx = min(sorted.count - 1, max(0, Int(pct * Double(sorted.count - 1))))
            return sorted[idx]
        }

        return RouteFiringReport(
            route: route,
            totalFrames: values.count,
            firingFrames: firing,
            partialFiringFrames: partial,
            inputMin: sorted.first ?? 0,
            inputMax: sorted.last ?? 0,
            inputMean: mean,
            inputP50: percentile(0.50),
            inputP90: percentile(0.90),
            inputP99: percentile(0.99)
        )
    }
}

// MARK: - Shader-side primitive replicas

/// Replica of the shader-side `smoothstep(lo, hi, x)` (GLSL/MSL semantics).
///
/// MSL produces `0` for `x <= lo`, `1` for `x >= hi`, smooth Hermite cubic
/// in-between. Replicated here so route value extractors can match the
/// shader exactly when computing post-gate amplitudes.
@inlinable
public func smoothstep(_ lo: Float, _ hi: Float, _ x: Float) -> Float {
    guard hi > lo else { return x >= lo ? 1 : 0 }
    let scaled = max(0, min(1, (x - lo) / (hi - lo)))
    return scaled * scaled * (3 - 2 * scaled)
}

/// D-019 stem-warmup window blend. Matches every preset shader that follows
/// the Gossamer pattern (`stemMix = smoothstep(0.02, 0.06, totalStemEnergy)`).
@inlinable
public func stemWarmupBlend(_ totalStemEnergy: Float, low: Float = 0.02, high: Float = 0.06) -> Float {
    smoothstep(low, high, totalStemEnergy)
}
