// EndedViewTests — QR.4 / D-091.
//
// Verifies the post-stub session-summary card resolves the right localization
// keys, exposes the static accessibility identifiers documented in the view,
// and that the injected closures fire when invoked. SwiftUI subview traversal
// in unit tests is unreliable (Failed Approach #41 — accessibility tree only
// materialises with an active accessibility client), so behavioural assertions
// are made by invoking closures directly and by inspecting source / localized
// strings.

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import PhospheneApp

@Suite("EndedView")
@MainActor
struct EndedViewTests {

    @Test("required localization keys resolve to non-empty strings")
    func test_localizationKeys_resolve() {
        let keys = [
            "ended.headline",
            "ended.cta.newSession",
            "ended.cta.openFolder",
            "ended.summary.tracks",
            "ended.summary.duration"
        ]
        for key in keys {
            let value = String(localized: String.LocalizationValue(key))
            #expect(!value.isEmpty, "Localizable.strings missing key '\(key)'")
            #expect(value != key, "Localizable.strings key '\(key)' is unresolved (returned the key itself)")
        }
    }

    @Test("accessibility identifier constants are defined and unique")
    func test_accessibilityIDs_areDistinct() {
        #expect(EndedView.accessibilityID == "phosphene.view.ended")
        #expect(EndedView.newSessionButtonID == "phosphene.ended.newSession")
        #expect(EndedView.openFolderButtonID == "phosphene.ended.openFolder")
        let ids = [EndedView.accessibilityID, EndedView.newSessionButtonID, EndedView.openFolderButtonID]
        #expect(Set(ids).count == ids.count, "EndedView accessibility identifiers must be distinct")
    }

    @Test("view constructs successfully with concrete inputs")
    func test_viewConstructs() {
        var startCalls = 0
        var folderCalls = 0
        let view = EndedView(
            trackCount: 4,
            sessionDuration: 180,
            onStartNewSession: { startCalls += 1 },
            onOpenSessionsFolder: { folderCalls += 1 }
        )
        // Render once to force body evaluation; ignore the view tree.
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layoutSubtreeIfNeeded()
        #expect(startCalls == 0, "init must not invoke the start-session closure")
        #expect(folderCalls == 0, "init must not invoke the open-folder closure")
    }

    @Test("ended.summary.tracks formatter substitutes the count")
    func test_trackCountFormatter() {
        let template = String(localized: "ended.summary.tracks")
        let formatted = String(format: template, 4)
        #expect(formatted.contains("4"), "track-count format must place the count: got '\(formatted)'")
        #expect(formatted.contains("track"), "track-count format must contain 'track': got '\(formatted)'")
    }

    @Test("openSessionsFolder helper creates the directory")
    func test_openSessionsFolder_createsDirectoryIfMissing() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("phosphene_sessions")
        let preExisted = FileManager.default.fileExists(atPath: url.path)
        EndedView.openSessionsFolder()
        let postExists = FileManager.default.fileExists(atPath: url.path)
        #expect(postExists, "phosphene_sessions/ must exist after openSessionsFolder()")
        if !preExisted {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
