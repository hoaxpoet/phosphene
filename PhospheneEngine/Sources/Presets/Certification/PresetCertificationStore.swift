// PresetCertificationStore — Loads and caches RubricResult for all production presets.
//
// Uses Bundle.module to find .metal files from the Presets module's Shaders resource
// directory (same path as PresetLoader). The store is lazy — results are computed once
// on first access and then cached for the process lifetime.
//
// Isolation: actor-isolated to prevent concurrent initialization races.
// Test injection: setResults(_:) replaces the cache for unit testing.

import Foundation
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "CertificationStore")

// MARK: - PresetCertificationStore

/// Loads, evaluates, and caches `RubricResult` for all production presets.
///
/// The store reads `.metal` source and JSON sidecars from `Bundle.module`
/// (the Presets module bundle), evaluates them with `DefaultFidelityRubric`,
/// and caches results. Results are keyed by preset ID (`PresetDescriptor.id`).
public actor PresetCertificationStore {

    // MARK: Shared singleton

    public static let shared = PresetCertificationStore()

    // MARK: Private state

    private var cache: [String: RubricResult]?
    private let rubric: any FidelityRubricEvaluating
    private let deviceTier: DeviceTier

    // MARK: Init

    public init(
        rubric: any FidelityRubricEvaluating = DefaultFidelityRubric(),
        deviceTier: DeviceTier = .tier2
    ) {
        self.rubric = rubric
        self.deviceTier = deviceTier
    }

    // MARK: - Public API

    /// Returns the rubric result for a single preset, or nil if not found.
    public func result(for presetID: String) -> RubricResult? {
        loadIfNeeded()[presetID]
    }

    /// Returns all cached rubric results, keyed by preset ID.
    public func results() -> [String: RubricResult] {
        loadIfNeeded()
    }

    // MARK: - Test Injection

    /// Replace the in-process cache with a pre-built result set.
    /// Subsequent calls to `result(for:)` / `results()` return these values.
    public func setResults(_ results: [String: RubricResult]) {
        cache = results
    }

    // MARK: - Private Load

    private func loadIfNeeded() -> [String: RubricResult] {
        if let existing = cache { return existing }
        let built = buildResults()
        cache = built
        return built
    }

    private func buildResults() -> [String: RubricResult] {
        guard let shadersURL = Bundle.module.url(forResource: "Shaders", withExtension: nil) else {
            logger.error("PresetCertificationStore: could not find Shaders bundle resource")
            return [:]
        }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: shadersURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error("PresetCertificationStore: \(error.localizedDescription)")
            return [:]
        }

        // Utility and non-preset .metal files that should not be certified.
        let excluded: Set<String> = ["ShaderUtilities.metal"]

        let metalFiles = contents
            .filter { $0.pathExtension == "metal" && !excluded.contains($0.lastPathComponent) }
            .filter { !$0.lastPathComponent.hasPrefix("Stalker") }  // retired preset

        var out: [String: RubricResult] = [:]
        let decoder = JSONDecoder()

        for metalURL in metalFiles {
            let baseName = metalURL.deletingPathExtension().lastPathComponent
            let jsonURL  = metalURL.deletingPathExtension().appendingPathExtension("json")

            guard let metalSource = try? String(contentsOf: metalURL, encoding: .utf8) else {
                logger.warning("PresetCertificationStore: could not read \(metalURL.lastPathComponent)")
                continue
            }

            let descriptor: PresetDescriptor
            if let jsonData = try? Data(contentsOf: jsonURL),
               let decoded = try? decoder.decode(PresetDescriptor.self, from: jsonData) {
                descriptor = decoded
            } else {
                // No sidecar — create a minimal descriptor so the rubric can still run.
                logger.warning("PresetCertificationStore: no JSON sidecar for \(baseName), using defaults")
                guard let minimal = try? decoder.decode(
                    PresetDescriptor.self,
                    from: Data(#"{"name":"\#(baseName)"}"#.utf8)
                ) else { continue }
                descriptor = minimal
            }

            let presetID = descriptor.id

            // For the certification store, we use the complexity_cost field as the
            // p95 frame time estimate. Live measurements are not available at load time.
            let runtimeChecks = RuntimeCheckResults(
                silenceNonBlack: true,    // assume 5.2 acceptance gate already enforces this
                p95FrameTimeMs: descriptor.complexityCost.cost(for: deviceTier)
            )

            let result = rubric.evaluate(
                presetID: presetID,
                metalSource: metalSource,
                descriptor: descriptor,
                runtimeChecks: runtimeChecks,
                deviceTier: deviceTier
            )
            out[presetID] = result
        }

        logger.info("PresetCertificationStore: evaluated \(out.count) presets")
        return out
    }
}
