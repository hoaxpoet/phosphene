// StatusTone — the app's single severity vocabulary. (DS.3, D-234)
//
// Before DS.3 three surfaces each mapped severity to colour inline and disagreed:
// the full-screen views returned a system yellow for `degradation`, the toast
// returned the danger red, and the banner ignored severity entirely and was always
// amber. `StatusTone` is the one place that answer lives.
//
// Every tone resolves to a `--color-status-*` triple from the vendored token source
// ([D-232]) plus one SF Symbol. Uzume is always dark, so each tone reads the dark
// block only — there is no appearance branch.
//
// Per `uzume-site` COMPONENTS.md § Trust explanation: status colour may support but
// never replace text or icon. Every tone therefore carries a symbol, and no surface
// is allowed to signal severity with colour alone.
//
// The two `from(_:)` mappings are the whole of the vocabulary. A status surface
// derives its tone through one of them and never switches on a severity itself.

import Shared
import SwiftUI

// MARK: - StatusTone

/// One of the four status roles the design system publishes.
///
/// `success` has no producer yet — neither `ErrorSeverity` nor `UzumeToast.Severity`
/// can express it, because both vocabularies describe things going wrong. It is
/// carried because the published role set is four, and the first non-error status
/// surface (a "ready" confirmation) needs it to exist rather than inventing it.
enum StatusTone: Equatable, CaseIterable {
    case info
    case success
    case warning
    case danger

    // MARK: - Token triple

    /// Text and icon colour.
    var foreground: Color {
        switch self {
        case .info:    return UzumeAppColor.Status.infoForeground
        case .success: return UzumeAppColor.Status.successForeground
        case .warning: return UzumeAppColor.Status.warningForeground
        case .danger:  return UzumeAppColor.Status.dangerForeground
        }
    }

    /// Field the tone sits on.
    var background: Color {
        switch self {
        case .info:    return UzumeAppColor.Status.infoBackground
        case .success: return UzumeAppColor.Status.successBackground
        case .warning: return UzumeAppColor.Status.warningBackground
        case .danger:  return UzumeAppColor.Status.dangerBackground
        }
    }

    /// Edge between field and canvas.
    var border: Color {
        switch self {
        case .info:    return UzumeAppColor.Status.infoBorder
        case .success: return UzumeAppColor.Status.successBorder
        case .warning: return UzumeAppColor.Status.warningBorder
        case .danger:  return UzumeAppColor.Status.dangerBorder
        }
    }

    /// SF Symbol carrying the tone without relying on colour.
    var symbol: String {
        switch self {
        case .info:    return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .danger:  return "xmark.circle"
        }
    }

    // MARK: - Mappings

    /// The engine's four-value vocabulary.
    ///
    /// `degradation` maps to `warning`, not `danger` (D-235): the severity's own
    /// definition is "Uzume is operating in degraded mode", which is explicitly not
    /// "the session cannot continue". Reserving `danger` for `fatal` keeps red
    /// meaningful — a red toast raised while the visuals are still playing teaches
    /// people to ignore red.
    static func from(_ severity: ErrorSeverity) -> StatusTone {
        switch severity {
        case .info:        return .info
        case .warning:     return .warning
        case .degradation: return .warning
        case .fatal:       return .danger
        }
    }

    /// The app's narrower three-value toast vocabulary.
    ///
    /// `UzumeToast.Severity` has no `fatal`; `PlaybackErrorBridge` folds `.fatal` into
    /// `.degradation` before a toast is built, so a toast's `degradation` covers both
    /// engine severities. It follows the same reading as `ErrorSeverity.degradation`.
    static func from(_ severity: UzumeToast.Severity) -> StatusTone {
        switch severity {
        case .info:        return .info
        case .warning:     return .warning
        case .degradation: return .warning
        }
    }
}
