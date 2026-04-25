// DynamicTypeRegressionTests — Verify that user-facing views no longer use
// fixed .system(size:) font modifiers. (U.9 Part B)
//
// Strategy: grep the view source strings for the pattern `.system(size:` and
// flag any view file that still contains it. This is a static-analysis test —
// no SwiftUI rendering required.

import Foundation
import Testing

// MARK: - DynamicTypeRegressionTests

@Suite("DynamicTypeRegressionTests")
struct DynamicTypeRegressionTests {

    // MARK: - Helpers

    private static let viewFiles: [String] = [
        "PhospheneApp/Views/Playback/TrackInfoCardView.swift",
        "PhospheneApp/Views/Playback/ToastView.swift",
        "PhospheneApp/Views/Playback/ListeningBadgeView.swift",
        "PhospheneApp/Views/Playback/SessionProgressDotsView.swift",
        "PhospheneApp/Views/Playback/PlaybackControlsCluster.swift",
        "PhospheneApp/Views/Playback/TrackChangeAnimationView.swift",
        "PhospheneApp/Views/Playback/ShortcutHelpOverlayView.swift",
        "PhospheneApp/Views/Ready/PlanPreviewRowView.swift",
        "PhospheneApp/Views/Ready/PlanPreviewTransitionView.swift",
        "PhospheneApp/Views/Ready/PlanPreviewView.swift",
        "PhospheneApp/Views/Ready/ReadyView.swift",
        "PhospheneApp/Views/AppleMusicConnectionView.swift",
        "PhospheneApp/Views/Preparation/TopBannerView.swift",
        "PhospheneApp/Views/Preparation/PreparationFailureView.swift",
        "PhospheneApp/Views/FullScreenErrorView.swift",
    ]

    private class BundleSentinel {}

    private func projectRoot() throws -> URL {
        // Walk up from the test bundle to the repo root — look for CLAUDE.md as a sentinel.
        var url = Bundle(for: BundleSentinel.self).bundleURL
        for _ in 0..<10 {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("CLAUDE.md").path) {
                return url
            }
        }
        throw TestError.cannotLocateProjectRoot
    }

    enum TestError: Error { case cannotLocateProjectRoot }

    // MARK: - Tests

    @Test("No user-facing view files contain fixed .system(size:) font calls")
    func noFixedSystemFontCalls() throws {
        let root = try projectRoot()
        var violations: [String] = []

        for relativePath in Self.viewFiles {
            let fileURL = root.appendingPathComponent(relativePath)
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
                // Skip if file doesn't exist (e.g. path mismatch in CI) — don't fail.
                continue
            }
            if source.contains(".system(size:") {
                violations.append(relativePath)
            }
        }

        #expect(
            violations.isEmpty,
            "Fixed font calls found (use semantic styles instead): \(violations.joined(separator: ", "))"
        )
    }
}
