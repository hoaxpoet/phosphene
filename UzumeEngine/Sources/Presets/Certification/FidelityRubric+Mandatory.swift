// FidelityRubric+Mandatory — M1–M7 evaluators, profile dispatchers, result assembly.

import Foundation
import Shared

// MARK: - Profile Dispatchers + Result Assembly

extension DefaultFidelityRubric {

    // MARK: Full Profile (M1–M7, E1–E4, P1–P4)

    func evaluateFullProfile(
        metalSource: String,
        descriptor: PresetDescriptor,
        runtimeChecks: RuntimeCheckResults,
        deviceTier: DeviceTier
    ) -> [RubricItem] {
        [
            evaluateM1(metalSource),
            evaluateM2(metalSource),
            evaluateM3(metalSource),
            evaluateM4(metalSource),
            evaluateM5(runtimeChecks),
            evaluateM6(descriptor, runtimeChecks, deviceTier),
            evaluateM7(descriptor),
            evaluateE1(metalSource),
            evaluateE2(metalSource),
            evaluateE3(metalSource, descriptor),
            evaluateE4(metalSource),
            evaluateP1(descriptor),
            evaluateP2(metalSource),
            evaluateP3(metalSource, descriptor),
            evaluateP4(metalSource),
        ]
    }

    // MARK: Lightweight Profile (L1–L4)

    func evaluateLightweightProfile(
        metalSource: String,
        descriptor: PresetDescriptor,
        runtimeChecks: RuntimeCheckResults,
        deviceTier: DeviceTier
    ) -> [RubricItem] {
        // L1 = silence fallback (M5 logic)
        // L2 = deviation primitives (M4 logic)
        // L3 = performance (M6 logic)
        // L4 = frame match (M7 logic, always manual)
        let l1 = evaluateM5(runtimeChecks)
        let l2 = evaluateM4(metalSource)
        let l3 = evaluateM6(descriptor, runtimeChecks, deviceTier)
        let l4 = evaluateM7(descriptor)

        return [
            RubricItem(
                id: "L1_silence_fallback",
                label: "Silence fallback",
                category: .mandatory,
                status: l1.status,
                detail: l1.detail
            ),
            RubricItem(
                id: "L2_deviation_primitives",
                label: "Deviation primitives",
                category: .mandatory,
                status: l2.status,
                detail: l2.detail
            ),
            RubricItem(
                id: "L3_performance",
                label: "Performance budget",
                category: .mandatory,
                status: l3.status,
                detail: l3.detail
            ),
            RubricItem(
                id: "L4_frame_match",
                label: "Reference frame match",
                category: .mandatory,
                status: l4.status,
                detail: l4.detail
            ),
        ]
    }

    // MARK: Result Assembly

    func buildResult(
        presetID: String,
        profile: RubricProfile,
        items: [RubricItem],
        certified: Bool
    ) -> RubricResult {
        let mandatory = items.filter { $0.category == .mandatory }
        let expected = items.filter { $0.category == .expected }
        let preferred = items.filter { $0.category == .preferred }

        let mandatoryPass = mandatory.filter { $0.status == .pass }.count
        let expectedPass = expected.filter { $0.status == .pass }.count
        let preferredPass = preferred.filter { $0.status == .pass }.count
        let total = mandatoryPass + expectedPass + preferredPass

        let maxScore: Int
        let meetsGate: Bool

        switch profile {
        case .full:
            maxScore = 15
            // M1–M6 must all pass (M7 is manual, excluded from automated gate).
            let automatableMandatory = mandatory.filter { $0.id != "M7_frame_match" }
            let allMandatoryPass = automatableMandatory.allSatisfy { $0.status == .pass }
            meetsGate = allMandatoryPass && expectedPass >= 2 && preferredPass >= 1

        case .lightweight:
            maxScore = 4
            // L1–L3 must all pass (L4 is manual).
            let automatableLight = mandatory.filter { $0.id != "L4_frame_match" }
            meetsGate = automatableLight.allSatisfy { $0.status == .pass }
        }

        return RubricResult(
            presetID: presetID,
            profile: profile,
            items: items,
            mandatoryPassCount: mandatoryPass,
            expectedPassCount: expectedPass,
            preferredPassCount: preferredPass,
            totalScore: total,
            maxScore: maxScore,
            meetsAutomatedGate: meetsGate,
            certified: certified
        )
    }
}

// MARK: - M1–M7 Evaluators

extension DefaultFidelityRubric {

    // MARK: M1: Detail Cascade

    /// Heuristic: at least 3 distinct scale values in noise calls, OR cascade markers present.
    private func evaluateM1(_ src: String) -> RubricItem {
        // Look for // macro, // meso, // micro, // specular discipline markers.
        let markerCount = [
            src.localizedCaseInsensitiveContains("// macro"),
            src.localizedCaseInsensitiveContains("// meso"),
            src.localizedCaseInsensitiveContains("// micro"),
            src.localizedCaseInsensitiveContains("// specular"),
        ].filter { $0 }.count

        if markerCount >= 3 {
            return RubricItem(
                id: "M1_detail_cascade",
                label: "Detail cascade",
                category: .mandatory,
                status: .pass,
                detail: "\(markerCount) of 4 cascade markers found (// macro/meso/micro/specular)"
            )
        }

        // Matches fbm8(p * 3.0), warped_fbm(p, N), ridged_mf(p, N, N), etc.
        let scalePattern = /(?:fbm\d+|warped_fbm|ridged_mf|perlin\dd|worley\dd|simplex\dd)\s*\([^)]*\*\s*([\d.]+)/
        let matches = src.matches(of: scalePattern)
        let distinctScales = Set(matches.compactMap { Float($0.output.1) }).count

        let status: RubricItemStatus = distinctScales >= 3 ? .pass : .fail
        let detail = markerCount > 0
            ? "\(markerCount)/4 cascade markers + \(distinctScales) distinct noise scales"
            : "\(distinctScales) distinct noise scales (need ≥3, or ≥3 cascade markers)"
        return RubricItem(
            id: "M1_detail_cascade",
            label: "Detail cascade",
            category: .mandatory,
            status: status,
            detail: detail
        )
    }

    // MARK: M2: ≥4 Octave Noise

    /// Detect the highest octave count across all hero-noise function calls.
    private func evaluateM2(_ src: String) -> RubricItem {
        var maxOctaves = 0

        // Explicit fbmN calls: extract N.
        let fbmPattern = /\bfbm([0-9]+)\s*\(/
        for match in src.matches(of: fbmPattern) {
            if let count = Int(match.output.1) {
                maxOctaves = max(maxOctaves, count)
            }
        }
        // warped_fbm internally uses fbm8 (V.1 DomainWarp.metal).
        if src.contains("warped_fbm(") { maxOctaves = max(maxOctaves, 8) }
        // ridged_mf default = 6 octaves (V.1 RidgedMultifractal.metal).
        if src.contains("ridged_mf(") { maxOctaves = max(maxOctaves, 6) }
        // worley_fbm = Worley blended with fbm8 internally (V.2 Worley.metal).
        if src.contains("worley_fbm(") { maxOctaves = max(maxOctaves, 6) }

        let status: RubricItemStatus = maxOctaves >= 4 ? .pass : .fail
        return RubricItem(
            id: "M2_octave_count",
            label: "≥4 noise octaves",
            category: .mandatory,
            status: status,
            detail: "max detected octave count: \(maxOctaves) (need ≥4)"
        )
    }

    // MARK: M3: ≥3 Distinct Materials

    /// Count distinct V.3 cookbook function callsites (not occurrences of the same one).
    private func evaluateM3(_ src: String) -> RubricItem {
        let found = Self.knownMaterialFunctions.filter { src.contains($0 + "(") }
        let status: RubricItemStatus = found.count >= 3 ? .pass : .fail
        let listSnippet = found.sorted().joined(separator: ", ")
        return RubricItem(
            id: "M3_material_count",
            label: "≥3 cookbook materials",
            category: .mandatory,
            status: status,
            detail: found.isEmpty
                ? "no mat_* cookbook calls found (need ≥3 distinct)"
                : "\(found.count) distinct: \(listSnippet)"
        )
    }

    // MARK: M4: Deviation Primitives

    /// Pass when source uses at least one D-026 deviation field AND contains no
    /// absolute-threshold anti-patterns (f.bass > 0.x outside comments).
    private func evaluateM4(_ src: String) -> RubricItem {
        let usedFields = Self.deviationPrimitiveNames.filter { src.contains($0) }

        // Check for absolute-threshold anti-patterns on non-comment lines.
        let nonCommentLines = src.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let absoluteThresholdPattern = /\bf\.(bass|mid|treb|treble)\s*[><]\s*0\.[0-9]/
        let hasAbsoluteThreshold = nonCommentLines.firstMatch(of: absoluteThresholdPattern) != nil

        let status: RubricItemStatus
        let detail: String

        if usedFields.isEmpty {
            status = .fail
            detail = "no deviation primitives found (bass_rel/dev, mid_rel/dev, etc. from D-026)"
        } else if hasAbsoluteThreshold {
            status = .fail
            detail = "\(usedFields.count) deviation fields found"
                + " but also has absolute-threshold pattern (f.band > 0.x) — D-026 violation"
        } else {
            status = .pass
            let sample = usedFields.prefix(4).joined(separator: ", ")
            detail = "uses: \(sample)\(usedFields.count > 4 ? " +" : "")"
        }

        return RubricItem(
            id: "M4_deviation_primitives",
            label: "Deviation primitives (D-026)",
            category: .mandatory,
            status: status,
            detail: detail
        )
    }

    // MARK: M5: Silence Fallback

    /// Runtime check: silence renders non-black (from Increment 5.2).
    private func evaluateM5(_ checks: RuntimeCheckResults) -> RubricItem {
        // Runtime check is the gate; D-019 warmup pattern is informational only.
        let status: RubricItemStatus = checks.silenceNonBlack ? .pass : .fail
        return RubricItem(
            id: "M5_silence_fallback",
            label: "Graceful silence fallback",
            category: .mandatory,
            status: status,
            detail: checks.silenceNonBlack
                ? "runtime: silence renders non-black"
                : "runtime: silence renders black (D-019 warmup missing or broken)"
        )
    }

    // MARK: M6: Performance Budget

    /// Pass when the descriptor's complexity_cost for the given tier is within budget.
    private func evaluateM6(
        _ descriptor: PresetDescriptor,
        _ checks: RuntimeCheckResults,
        _ tier: DeviceTier
    ) -> RubricItem {
        _ = checks
        let cost = descriptor.complexityCost.cost(for: tier)
        let budget = tier.frameBudgetMs
        let status: RubricItemStatus = cost <= budget ? .pass : .fail
        let budgetFmt = String(format: "%.1f", budget)
        let costFmt = String(format: "%.1f", cost)
        return RubricItem(
            id: "M6_performance",
            label: "Performance budget",
            category: .mandatory,
            status: status,
            detail: "\(tier) budget \(budgetFmt) ms; complexity_cost \(costFmt) ms"
        )
    }

    // MARK: M7: Reference Frame Match (always manual)

    private func evaluateM7(_ descriptor: PresetDescriptor) -> RubricItem {
        RubricItem(
            id: "M7_frame_match",
            label: "Matt-approved reference frame match",
            category: .mandatory,
            status: .manual,
            detail: "certified: \(descriptor.certified) — awaiting review against docs/VISUAL_REFERENCES/"
        )
    }
}
