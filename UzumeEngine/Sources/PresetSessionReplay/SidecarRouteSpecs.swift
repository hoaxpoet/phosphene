// SidecarRouteSpecs — build replay route specs from a preset's `audio_routes`
// sidecar manifest (SR.2 / RECON.21).
//
// WHY THIS EXISTS. Replay route specs used to be hand-written Swift, one file
// per preset (`AuroraVeilRoutes`, `MurmurationRoutes`, `SkeinRoutes`). That
// stalled coverage at 3 of 26 presets, because each new preset cost a ~90-line
// file plus a registry edit — and the files duplicated gate constants their own
// headers admitted had to be "kept in sync by code review".
//
// Meanwhile QG.1 (D-179) already requires every preset to declare its routes in
// the sidecar, `AudioRoutePrimitives` already maps each primitive to its recorded
// CSV column, and `RouteCoverageTests` already asserts they fire. This reads that
// same manifest, so a preset becomes replayable by shipping the sidecar entry it
// is required to ship anyway — zero new Swift per preset.
//
// WHAT IT MEASURES, AND WHAT IT DOES NOT. Two things the sidecar cannot express,
// stated rather than guessed at:
//
//   1. **Gate thresholds.** A sidecar route says `kind`, not the shader's
//      smoothstep edges. Specs built here use the per-kind floors QG.1 already
//      defends (`accent` → 0.02, the rising-crossing threshold; `continuous` →
//      just above zero, since the assertion is that it varies at all). Those are
//      COVERAGE thresholds, not the preset's real gate. A hand-written spec that
//      encodes the actual edges measures something strictly sharper, and where
//      one exists it still wins (see `PresetSessionReplay.resolvePreset`).
//
//   2. **Multi-primitive arithmetic.** 38 of 121 declared routes list several
//      primitives, and the sidecar does not say how the shader combines them —
//      Skein's painter speed takes `mean(max(0, ·))` of four stem deviations
//      while its stem-mix gate takes their SUM. Rather than invent a combining
//      rule, this emits ONE spec per (route, primitive) pair, labelled with both.
//      The report then reads per route, per input, which is honest about what was
//      measured. Deriving a single combined scalar is what a hand-written spec is
//      for.

import Foundation
import Presets

public enum SidecarRouteSpecs {

    /// Per-kind gate thresholds, mirroring the QG.1 floors in `RouteCoverageTests`
    /// so replay and the coverage gate agree on what "fired" means.
    enum KindGate {
        /// `accent`: a rising crossing above this counts as a firing. Matches
        /// `RouteCoverageTests.accentThreshold`.
        static let accent: Float = 0.02
        /// `continuous` / `structural`: the assertion is that the primitive moves
        /// at all, so any non-trivial magnitude counts.
        static let continuousFloor: Float = 1e-5
        /// `gate` (BUG-088): an enable, not a driver. A silence gate sitting pinned open
        /// through a whole track is CORRECT, so the question is only whether it ever OPENS.
        /// Matches `RouteCoverageTests.gateOpenFloor`.
        static let gateOpen: Float = 0.9
    }

    /// One resolved route input: the spec to report under, and the column to read.
    public struct ResolvedInput: Sendable {
        public let spec: RouteSpec
        public let column: String
        public let scale: Float
    }

    /// Build specs for `descriptor`'s declared routes.
    ///
    /// Throws nothing: a primitive absent from `AudioRoutePrimitives.map` is
    /// skipped and reported in `unmapped` rather than failing the run — the QG.1
    /// schema gate already fails those at build time, so here they are a
    /// diagnostic note, not a wall.
    public static func resolve(
        descriptor: PresetDescriptor
    ) -> (inputs: [ResolvedInput], unmapped: [String]) {
        var inputs: [ResolvedInput] = []
        var unmapped: [String] = []

        for route in descriptor.audioRoutes {
            guard let mapping = AudioRoutePrimitives.map[route.primitive] else {
                unmapped.append("\(route.route)/\(route.primitive)")
                continue
            }
            let gate: Float
            switch route.kind {
            case .accent:                   gate = KindGate.accent
            case .continuous, .structural:  gate = KindGate.continuousFloor
            case .gate:                     gate = KindGate.gateOpen
            }
            let spec = RouteSpec(
                name: "\(route.route) ← \(route.primitive)",
                description: "Declared \(route.kind.rawValue) route from the preset's "
                           + "audio_routes sidecar. Gate is the QG.1 \(route.kind.rawValue) "
                           + "coverage floor (\(gate)), NOT the shader's own edge — this "
                           + "measures whether the input is live, not the visual amplitude.",
                inputName: route.primitive,
                gateThreshold: gate,
                partialGateThreshold: nil,
                inputValue: nil)
            inputs.append(ResolvedInput(spec: spec, column: mapping.column, scale: mapping.scale))
        }
        return (inputs, unmapped)
    }

    /// Analyse every resolved input against a session's recorded columns.
    ///
    /// Reads through `SessionColumnSeries` rather than `SessionFrame`: the latter
    /// carries 16 fields, while a declared primitive may be any recorded column.
    /// A column absent from the session yields a zero-frame report, which reads in
    /// the output as "not recorded here" rather than "did not fire".
    public static func analyze(
        inputs: [ResolvedInput],
        columns: SessionColumnSeries
    ) -> [RouteFiringReport] {
        inputs.map { input in
            guard let raw = columns.floatSeries(input.column) else {
                return RouteAnalyzer.analyze(route: input.spec, values: [])
            }
            let values = raw.map { ($0 ?? 0) * input.scale }
            return RouteAnalyzer.analyze(route: input.spec, values: values)
        }
    }
}

// MARK: - Sidecar lookup

/// Finds a preset's JSON sidecar by its declared `name`.
///
/// The CLI takes a human preset name (`--preset "Volumetric Lithograph"`, or the
/// `aurora_veil` style the old registry accepted), so matching normalises both
/// sides: lowercased, with spaces, underscores and hyphens removed. That accepts
/// every spelling the previous hand-written registry did, without a registry.
public enum SidecarLocator {

    public static func descriptor(forPresetNamed name: String) -> PresetDescriptor? {
        guard let shadersURL = PresetLoader.bundledShadersURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: shadersURL, includingPropertiesForKeys: nil)
        else { return nil }

        let wanted = normalise(name)
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let descriptor = try? JSONDecoder().decode(PresetDescriptor.self, from: data)
            else { continue }
            if normalise(descriptor.name) == wanted { return descriptor }
        }
        return nil
    }

    /// Every preset name that has a sidecar, for error messages and tests.
    public static func allPresetNames() -> [String] {
        guard let shadersURL = PresetLoader.bundledShadersURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: shadersURL, includingPropertiesForKeys: nil)
        else { return [] }
        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let decoded = try? JSONDecoder().decode(PresetDescriptor.self, from: data)
                else { return nil }
                return decoded.name
            }
            .sorted()
    }

    private static func normalise(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
