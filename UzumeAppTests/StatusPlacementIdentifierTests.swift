// StatusPlacementIdentifierTests — pins the five status-placement accessibility
// identifiers across the DS.3 rename. (DS.3)
//
// Extends the DS.2 pattern (`SourceChoiceIdentifierTests`). DS.3 renamed both
// carrying components, and a rename is exactly the change that quietly takes an
// identifier with it.
//
// The identifiers keep their `preparation.*` spelling even though neither component
// is named for preparation any more: an identifier is a contract with whatever drives
// the UI, not a description of the type that happens to carry it. If these strings
// ever should change, that is its own increment with its own consumers to update —
// not a side effect of a component consolidation.

import Testing
@testable import UzumeApp

// MARK: - StatusPlacementIdentifierTests

@Suite("Status placement identifiers")
@MainActor
struct StatusPlacementIdentifierTests {

    // MARK: - NoticeBanner

    @Test func banner_hasExpectedID() {
        #expect(NoticeBanner.bannerID == "uzume.preparation.topBanner")
    }

    /// Pinned even though no construction site passes `onDismiss`, so this button has
    /// never rendered in a shipped build (KNOWN_ISSUES, DS.3 task 8). Deleting the
    /// identifier would break the contract; wiring the button is a behaviour change.
    /// It stays exactly as it is until someone decides whether the banner is dismissible.
    @Test func bannerDismiss_hasExpectedID() {
        #expect(NoticeBanner.dismissID == "uzume.preparation.topBanner.dismiss")
    }

    // MARK: - RecoveryScreen

    @Test func recoveryScreen_hasExpectedID() {
        #expect(RecoveryScreen.accessibilityID == "uzume.view.preparationFailure")
    }

    @Test func recoveryScreenPrimary_hasExpectedID() {
        #expect(RecoveryScreen.pickPlaylistButtonID == "uzume.preparationFailure.pickPlaylist")
    }

    @Test func recoveryScreenSecondary_hasExpectedID() {
        #expect(RecoveryScreen.reactiveButtonID == "uzume.preparationFailure.startReactive")
    }
}
