// DeviceTier — Apple Silicon chip generation for Orchestrator device-aware scoring.

// MARK: - DeviceTier

/// Apple Silicon tier used by the Orchestrator to apply per-device complexity budgets.
///
/// - `tier1`: M1, M2 — baseline performance envelope.
/// - `tier2`: M3, M4 — enhanced performance envelope with headroom for richer effects.
public enum DeviceTier: String, Sendable, Hashable, CaseIterable, Codable {
    /// M1, M2 — baseline.
    case tier1
    /// M3, M4 — enhanced.
    case tier2

    /// Target frame budget in milliseconds (60 fps).
    ///
    /// Both tiers share the 60 fps budget; tier2 has architectural slack
    /// that allows it to run presets whose `complexityCost.tier2` stays
    /// within budget even when `complexityCost.tier1` would exceed it.
    public var frameBudgetMs: Float {
        switch self {
        case .tier1: return 16.6
        case .tier2: return 16.6
        }
    }
}
