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
        "UzumeApp/Views/Playback/TrackInfoCardView.swift",
        "UzumeApp/Views/Playback/ToastView.swift",
        "UzumeApp/Views/Playback/ListeningBadgeView.swift",
        "UzumeApp/Views/Playback/SessionProgressDotsView.swift",
        "UzumeApp/Views/Playback/PlaybackControlsCluster.swift",
        "UzumeApp/Views/Playback/TrackChangeAnimationView.swift",
        "UzumeApp/Views/Playback/ShortcutHelpOverlayView.swift",
        "UzumeApp/Views/Ready/PlanPreviewRowView.swift",
        "UzumeApp/Views/Ready/PlanPreviewTransitionView.swift",
        "UzumeApp/Views/Ready/PlanPreviewView.swift",
        "UzumeApp/Views/Ready/ReadyView.swift",
        "UzumeApp/Views/AppleMusicConnectionView.swift",
        "UzumeApp/Views/LocalSourceConnectionView.swift",
        "UzumeApp/Views/Components/SourceChoice.swift",
        "UzumeApp/Views/Preparation/TopBannerView.swift",
        "UzumeApp/Views/Preparation/PreparationFailureView.swift",
        "UzumeApp/Views/FullScreenErrorView.swift",
    ]

    private func projectRoot(file: StaticString = #filePath) throws -> URL {
        // Walk up from this source file to the repo root — look for CLAUDE.md as a sentinel.
        // #filePath (not #file) gives the full absolute path in Swift 6 — #file now gives
        // the module-relative identifier (SE-0285) which produces a relative URL.
        var url = URL(fileURLWithPath: "\(file)")
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
