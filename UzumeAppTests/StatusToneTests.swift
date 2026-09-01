// StatusToneTests — every severity in both source vocabularies maps to a tone. (DS.3)
//
// The point of `StatusTone` is that there is exactly one answer to "what does this
// severity look like". These tests are the ratchet on that: they pin each mapping,
// and they fail if a case is added to either source enum without a tone being chosen
// for it (Swift's exhaustive switch fails the build first, which is the real guard —
// these pin the *choices*, not just the coverage).

import Shared
import Testing
@testable import UzumeApp

// MARK: - StatusToneTests

@Suite("StatusTone")
@MainActor
struct StatusToneTests {

    // MARK: - ErrorSeverity → StatusTone

    @Test("every ErrorSeverity maps to a tone", arguments: [
        (ErrorSeverity.info, StatusTone.info),
        (.warning, .warning),
        (.degradation, .warning),   // D-235 — degradation reads as caution, not alarm
        (.fatal, .danger),
    ])
    func errorSeverityMapping(severity: ErrorSeverity, expected: StatusTone) {
        #expect(StatusTone.from(severity) == expected)
    }

    // MARK: - UzumeToast.Severity → StatusTone

    @Test("every UzumeToast.Severity maps to a tone", arguments: [
        (UzumeToast.Severity.info, StatusTone.info),
        (.warning, .warning),
        (.degradation, .warning),   // D-235 — was the danger red before DS.3
    ])
    func toastSeverityMapping(severity: UzumeToast.Severity, expected: StatusTone) {
        #expect(StatusTone.from(severity) == expected)
    }

    // MARK: - Consistency

    /// The conflict DS.3 exists to remove: `degradation` rendered yellow on the
    /// full-screen surfaces and red in toasts. Both vocabularies must now agree.
    @Test func degradation_readsTheSameInBothVocabularies() {
        #expect(StatusTone.from(ErrorSeverity.degradation) == StatusTone.from(UzumeToast.Severity.degradation))
    }

    /// Colour may support but never replace text or icon (COMPONENTS.md § Trust
    /// explanation), so every tone owes a symbol.
    @Test func everyToneCarriesASymbol() {
        for tone in StatusTone.allCases {
            #expect(!tone.symbol.isEmpty)
        }
    }
}
