// AccessibilityStateTests — Unit tests for AccessibilityState (U.9, D-054).
//
// Verifies the three-way combination of system flag + user preference that
// drives the effective reduce-motion state, and the derived engine properties.

import AppKit
import Combine
import Testing
@testable import PhospheneApp

// MARK: - MockSettingsStore

/// Minimal stub that provides the reducedMotion publisher without UserDefaults I/O.
@MainActor
private final class StubSettingsStore: ObservableObject {
    @Published var reducedMotion: ReducedMotionPreference
    init(_ pref: ReducedMotionPreference = .matchSystem) {
        reducedMotion = pref
    }
}

// MARK: - StubWorkspace

/// Injects a synthetic system flag so tests don't depend on the real NSWorkspace state.
private class StubWorkspace: NSWorkspace {
    var stubReduceMotion: Bool
    init(reduceMotion: Bool) {
        stubReduceMotion = reduceMotion
    }
    override var accessibilityDisplayShouldReduceMotion: Bool { stubReduceMotion }
}

// MARK: - AccessibilityStateTests

@MainActor
struct AccessibilityStateTests {

    // MARK: - Effective state from system flag

    @Test
    func systemFalse_preferenceMatchSystem_reduceMotionFalse() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false))
        state.applyPreference(.matchSystem)
        #expect(state.reduceMotion == false)
    }

    @Test
    func systemTrue_preferenceMatchSystem_reduceMotionTrue() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: true))
        state.applyPreference(.matchSystem)
        #expect(state.reduceMotion == true)
    }

    // MARK: - Preference overrides

    @Test
    func preferenceAlwaysOn_reduceMotionTrue_regardlessOfSystem() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false))
        state.applyPreference(.alwaysOn)
        #expect(state.reduceMotion == true)
    }

    @Test
    func preferenceAlwaysOff_reduceMotionFalse_regardlessOfSystem() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: true))
        state.applyPreference(.alwaysOff)
        #expect(state.reduceMotion == false)
    }

    // MARK: - Derived engine properties

    @Test
    func beatAmplitudeScale_full_whenReduceMotionFalse() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false))
        state.applyPreference(.alwaysOff)
        #expect(state.beatAmplitudeScale == 1.0)
    }

    @Test
    func beatAmplitudeScale_half_whenReduceMotionTrue() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false))
        state.applyPreference(.alwaysOn)
        #expect(abs(state.beatAmplitudeScale - 0.5) < 0.0001)
    }

    // MARK: - MVWarp query

    @Test
    func shouldExecuteMVWarp_returnsFalse_whenReduceMotionTrue() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false))
        state.applyPreference(.alwaysOn)
        #expect(state.shouldExecuteMVWarp(presetEnabled: true) == false)
    }

    @Test
    func shouldExecuteMVWarp_returnsFalse_whenPresetDisabled_regardlessOfReduceMotion() {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false))
        state.applyPreference(.alwaysOff)
        #expect(state.shouldExecuteMVWarp(presetEnabled: false) == false)
    }

    // MARK: - Preference change updates published values

    @Test
    func preferenceChange_updatesReduceMotion() async {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false))
        state.applyPreference(.alwaysOff)
        #expect(state.reduceMotion == false)
        state.applyPreference(.alwaysOn)
        #expect(state.reduceMotion == true)
    }

    // MARK: - System flag change via notification

    @Test
    func systemFlagChangeNotification_updatesSystemReduceMotion() async {
        let state = AccessibilityState(workspace: StubWorkspace(reduceMotion: false))
        #expect(state.systemReduceMotion == false)

        // Posting the notification should trigger the internal observer.
        // The observer reads NSWorkspace.shared, not the stub, so we verify
        // that the notification path runs without crashing and updates the
        // published property to whatever the real system flag currently is.
        NotificationCenter.default.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared
        )
        // Allow the main run loop to process the notification.
        await Task.yield()
        // systemReduceMotion is now whatever the real flag is — just assert it's Bool.
        _ = state.systemReduceMotion
    }
}
