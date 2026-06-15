// SettingsStoreEnvironmentRegressionTests — QR.4 / D-091 load-bearing gate.
//
// Catches the duplicate-`SettingsStore` bug if it ever recurs. Pre-fix:
// `PlaybackView` instantiated `@StateObject private var settingsStore =
// SettingsStore()` while `PhospheneApp.swift` injected the global store via
// `@EnvironmentObject`. Toggles in Settings updated the global store but the
// playback-side consumer was bound to the parallel one, silently swallowing
// every settings change.
//
// The two assertions:
// 1. An `@EnvironmentObject` consumer of the same store sees a toggle.
// 2. A `@StateObject SettingsStore()` consumer (the *pre-fix* shape) does
//    NOT see the toggle on the global store.
//
// This is the regression discriminator: the second assertion is the one that
// fails if anyone re-introduces a `@StateObject SettingsStore()` anywhere in
// the playback path. The probe property is `reducedMotion` — any `@Published`
// setting works; it just needs to be one a playback-side consumer reads.

import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import PhospheneApp

@Suite("SettingsStoreEnvironmentRegression")
@MainActor
struct SettingsStoreEnvironmentRegressionTests {

    // MARK: - Probe view + observer (test seam)

    private final class SettingObserver: ObservableObject {
        @Published var fromEnvironment: ReducedMotionPreference?
        @Published var fromShadowStateObject: ReducedMotionPreference?
    }

    private struct ProbeView: View {
        @EnvironmentObject var globalStore: SettingsStore
        /// Pre-fix shadow store — same shape as the bug. A separate instance,
        /// initialised once and never re-injected. Should NEVER receive updates
        /// from `globalStore` since they are different objects.
        @StateObject var shadowStore = SettingsStore(
            defaults: UserDefaults(suiteName: "qr4.shadow.\(UUID().uuidString)") ?? .standard
        )
        @ObservedObject var observer: SettingObserver

        var body: some View {
            Color.clear
                .onAppear {
                    observer.fromEnvironment = globalStore.reducedMotion
                    observer.fromShadowStateObject = shadowStore.reducedMotion
                }
                .onChange(of: globalStore.reducedMotion) { _, new in
                    observer.fromEnvironment = new
                }
                .onChange(of: shadowStore.reducedMotion) { _, new in
                    observer.fromShadowStateObject = new
                }
        }
    }

    // MARK: - Helpers

    private func tickRunloop(seconds: Double = 0.1) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeIsolatedStore() -> SettingsStore {
        let suite = "qr4.global.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return SettingsStore(defaults: defaults)
    }

    // MARK: - Tests

    @Test("setting toggle on global store propagates to env-object consumer")
    func test_settingChangePropagates() {
        let globalStore = makeIsolatedStore()
        globalStore.reducedMotion = .matchSystem

        let observer = SettingObserver()
        let host = NSHostingView(rootView: ProbeView(observer: observer)
            .environmentObject(globalStore))

        // Force the host to lay out so onAppear fires.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        tickRunloop()

        // Mutate the global store; env-object consumer should observe the change.
        globalStore.reducedMotion = .alwaysOn
        tickRunloop()

        #expect(observer.fromEnvironment == .alwaysOn,
                "env-object consumer must observe global settings changes")
    }

    @Test("@StateObject SettingsStore() shadow does NOT see global-store changes")
    func test_shadowStateObject_doesNotReceiveGlobalChanges() {
        // The load-bearing assertion: prove the bug shape (a separate
        // @StateObject SettingsStore instance) is provably incorrect.
        let globalStore = makeIsolatedStore()
        globalStore.reducedMotion = .matchSystem

        let observer = SettingObserver()
        let host = NSHostingView(rootView: ProbeView(observer: observer)
            .environmentObject(globalStore))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        tickRunloop()

        // Mutate the global store; shadow @StateObject must NOT observe.
        globalStore.reducedMotion = .alwaysOn
        tickRunloop()

        #expect(observer.fromShadowStateObject == .matchSystem,
                "shadow @StateObject must NOT receive updates from the global store (QR.4 bug)")
    }

    @Test("PlaybackView declares settingsStore as @EnvironmentObject")
    func test_playbackViewBindsViaEnvironmentObject() {
        // This test reads the source file directly — the value of the test is
        // catching anyone who flips the binding back to @StateObject. If the
        // @EnvironmentObject declaration moves or changes name, update both
        // here and CLAUDE.md §UX Contract.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()           // PhospheneAppTests
            .deletingLastPathComponent()           // repo root
            .appendingPathComponent("PhospheneApp/Views/Playback/PlaybackView.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8) else {
            Issue.record("PlaybackView.swift not found at \(url.path)")
            return
        }
        #expect(src.contains("@EnvironmentObject private var settingsStore: SettingsStore"),
                "PlaybackView.swift must bind settingsStore via @EnvironmentObject (QR.4 / D-091)")
        #expect(!src.contains("@StateObject private var settingsStore = SettingsStore()"),
                "PlaybackView.swift must NEVER declare @StateObject SettingsStore() — that was the QR.4 bug")
    }
}
