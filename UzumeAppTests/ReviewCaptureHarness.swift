// ReviewCaptureHarness — renders review surfaces to PNG for the M7 before/after pages.
//
// DS.3 built this for the status placements (every surface in every tone); DS.4
// generalised it rather than writing a second harness, adding the preparation screen
// in every reachable state. Gated on UZUME_CAPTURE=1 so a normal `xcodebuild test`
// never writes files. Follows the HARNESS_TEMPLATES=1 pattern of the engine suite.
//
//   TEST_RUNNER_UZUME_CAPTURE=1 TEST_RUNNER_UZUME_CAPTURE_DIR=docs/reviews/DS.4/before \
//     xcodebuild -scheme UzumeApp -destination 'platform=macOS' test \
//     -only-testing:UzumeAppTests/ReviewCaptureHarness
//
//   TEST_RUNNER_UZUME_CAPTURE_SET=status | preparation   (default: both)
//   (xcodebuild forwards only TEST_RUNNER_-prefixed variables to the test host.)
//
// Why rendered rather than driven through a live session: several states are not
// reachable from any real failure, and rendering covers the whole map; the
// reachability of each state is recorded in CAPTURES.md next to the image. The
// preparation captures drive the real `PreparationProgressView` through the same
// publisher protocol `SessionPreparer` implements, so what is rendered is the shipped
// view with scripted statuses — not a mock-up of it.

import Combine
import Session
import Shared
import SwiftUI
import Testing
@testable import UzumeApp

// MARK: - ReviewCaptureHarness

@Suite("Review capture harness", .enabled(if: ProcessInfo.processInfo.environment["UZUME_CAPTURE"] == "1"))
@MainActor
struct ReviewCaptureHarness {

    private static var captureSet: String {
        ProcessInfo.processInfo.environment["UZUME_CAPTURE_SET"] ?? "status,preparation"
    }

    @Test("render every status surface in every tone (DS.3)")
    func captureStatusSurfaces() async throws {
        guard Self.captureSet.contains("status") else { return }
        let dir = try outputDirectory()
        for (name, view) in Self.surfaces() {
            try await render(view, to: dir.appendingPathComponent("\(name).png"))
        }
        try Self.accessibilityRows()
            .joined(separator: "\n")
            .appending("\n")
            .write(to: dir.appendingPathComponent("a11y.txt"), atomically: true, encoding: .utf8)
    }

    @Test("render the preparation screen in every reachable state (DS.4)")
    func capturePreparationStates() async throws {
        guard Self.captureSet.contains("preparation") else { return }
        let dir = try outputDirectory()
        for scenario in PreparationScenario.all {
            for variant in PreparationCaptureVariant.all {
                let view = variant.wrap(scenario.makeView())
                let name = variant.filename(for: scenario.name)
                try await render(view, to: dir.appendingPathComponent("\(name).png"))
            }
        }
        try PreparationScenario.accessibilityRows()
            .joined(separator: "\n")
            .appending("\n")
            .write(to: dir.appendingPathComponent("a11y-preparation.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Status surfaces (DS.3)

    /// The accessibility label / identifier each status surface DECLARES, one row
    /// per surface. This is the declared contract, not literal VoiceOver speech —
    /// VO reads these strings through its own rotor and punctuation rules.
    static func accessibilityRows() -> [String] {
        var rows = ["surface\tdeclared VoiceOver label\taccessibility identifier"]

        let containerLabel = "(no explicit label — children read in order: icon, headline, body, buttons)"
        rows.append("full-screen (container)\t\(containerLabel)\t\(fullScreenIdentifier)")
        rows.append("full-screen primary CTA\tPick another playlist\t\(primaryButtonIdentifier)")
        rows.append("full-screen secondary CTA\tStart reactive mode\t\(secondaryButtonIdentifier)")

        for (label, error) in [("rate limited", UserFacingError.previewRateLimited),
                               ("slow first track", .preparationSlowOnFirstTrack(elapsedSeconds: 45)),
                               ("total timeout", .preparationTotalTimeout)] {
            rows.append("banner — \(label)\t\(LocalizedCopy.string(for: error))\t\(bannerIdentifier)")
        }
        rows.append(contentsOf: bannerDismissRows())

        for error in [UserFacingLocalFileError.unsupportedFormat, .unreadable, .m3uParseFailed, .emptyFolder] {
            rows.append("inline notice — \(error)\t\(error.localizedMessage)\t(none)")
        }

        for (severity, copy) in [(UzumeToast.Severity.info, "Display connected."),
                                 (.warning, "Display disconnected mid-session."),
                                 (.degradation, "Stem separation failed."),
                                 (.fatal, "No audio detected.")] {
            let label = AccessibilityLabels.toastLabel(copy: copy, severity: severity)
            rows.append("toast — \(severity)\t\(label)\t\(Self.toastAnnounceNote)")
        }

        return rows
    }

    private static let toastAnnounceNote =
        "(none — announced via AccessibilityNotification.Announcement on insert)"

    // MARK: - Identifiers under test
    //
    // Read off the component types, so a rename that moves a string shows up in
    // the captured a11y rows as well as in StatusPlacementIdentifierTests.

    static let fullScreenIdentifier      = RecoveryScreen.accessibilityID
    static let primaryButtonIdentifier   = RecoveryScreen.pickPlaylistButtonID
    static let secondaryButtonIdentifier = RecoveryScreen.reactiveButtonID
    static let bannerIdentifier          = NoticeBanner.bannerID

    // MARK: - Surfaces

    /// Every (filename, view) pair the review page shows. Names are stable across
    /// before/ and after/ so the page can pair them by filename alone.
    static func surfaces() -> [(String, AnyView)] {
        fullScreenSurfaces() + bannerSurfaces() + inlineSurfaces() + toastSurfaces()
    }

    private static func fullScreenSurfaces() -> [(String, AnyView)] {
        var out: [(String, AnyView)] = []

        // One error per severity the map distinguishes.
        let fullScreenCases: [(String, UserFacingError)] = [
            ("fullscreen-fatal-networkOffline", .networkOffline),
            ("fullscreen-fatal-allTracksFailed", .allTracksFailedToPrepare),
            ("fullscreen-warning-spotifyUnreachable", .spotifyUnreachable),
            ("fullscreen-degradation-stemSeparationFailed", .stemSeparationFailed(trackTitle: "Take Five")),
            ("fullscreen-info-emptyPlaylist", .emptyPlaylist),
        ]
        for (name, error) in fullScreenCases {
            out.append((name, AnyView(
                RecoveryScreen(
                    error: error,
                    primaryLabel: String(localized: "preparation.failure.pick_playlist_button"),
                    primaryAction: {},
                    secondaryLabel: String(localized: "preparation.failure.start_reactive_button"),
                    secondaryAction: {}
                )
                .frame(width: 720, height: 460)
            )))
        }

        return out
    }

    private static func bannerSurfaces() -> [(String, AnyView)] {
        var out: [(String, AnyView)] = []

        // The three errors routed to .topBanner, plus the two tones no routed
        // error currently reaches.
        let bannerCases: [(String, UserFacingError)] = [
            ("banner-rateLimited", .previewRateLimited),
            ("banner-slowFirstTrack", .preparationSlowOnFirstTrack(elapsedSeconds: 45)),
            ("banner-totalTimeout", .preparationTotalTimeout),
            ("banner-fatal-networkOffline", .networkOffline),
            ("banner-info-rePlanSucceeded", .rePlanSucceeded),
        ]
        for (name, error) in bannerCases {
            out.append((name, AnyView(
                NoticeBanner(error: error).frame(width: 720)
            )))
        }

        return out
    }

    private static func inlineSurfaces() -> [(String, AnyView)] {
        var out: [(String, AnyView)] = []

        // All four local-file errors.
        let inlineCases: [(String, UserFacingLocalFileError)] = [
            ("inline-unsupportedFormat", .unsupportedFormat),
            ("inline-unreadable", .unreadable),
            ("inline-m3uParseFailed", .m3uParseFailed),
            ("inline-emptyFolder", .emptyFolder),
        ]
        for (name, error) in inlineCases {
            out.append((name, AnyView(
                InlineNotice(message: error.localizedMessage, onDismiss: {})
                    .frame(width: 420)
                    .background(UzumeAppColor.canvas)
            )))
        }

        return out
    }

    private static func toastSurfaces() -> [(String, AnyView)] {
        var out: [(String, AnyView)] = []

        // Every severity the app enum carries.
        for toastCase in ToastCase.all {
            let (name, severity, copy) = (toastCase.name, toastCase.severity, toastCase.copy)
            out.append((name, AnyView(
                PerformanceToast(
                    toast: UzumeToast(severity: severity, copy: copy),
                    onDismiss: { _ in }
                )
                .frame(width: 360)
                .padding(16)
                .background(UzumeAppColor.canvas)
            )))
        }

        return out
    }

    /// Named rather than a 3-tuple so the capture list stays readable.
    struct ToastCase {
        let name: String
        let severity: UzumeToast.Severity
        let copy: String

        static let all: [ToastCase] = [
            ToastCase(name: "toast-info", severity: .info, copy: "Display connected."),
            ToastCase(name: "toast-warning", severity: .warning, copy: "Display disconnected mid-session."),
            ToastCase(name: "toast-degradation", severity: .degradation, copy: "Stem separation failed."),
            ToastCase(name: "toast-fatal", severity: .fatal, copy: "No audio detected."),
        ]
    }

    // MARK: - Rendering

    /// Renders through an offscreen AppKit window rather than `ImageRenderer`: the
    /// preparation list is a `LazyVStack` inside a `ScrollView`, and lazy containers
    /// only lay out inside a real hosting view. The run-loop hop lets the view's
    /// `@StateObject` view models receive their main-queue Combine deliveries.
    private func render(_ view: AnyView, to url: URL) async throws {
        let hosting = NSHostingView(rootView: view.preferredColorScheme(.dark))
        let size = hosting.fittingSize
        let bounds = CGRect(origin: .zero, size: size)
        hosting.frame = bounds
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * 2,
            pixelsHigh: Int(size.height) * 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw CaptureError.renderFailed(url.lastPathComponent) }
        rep.size = size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.renderFailed(url.lastPathComponent)
        }
        try png.write(to: url)
        window.contentView = nil
    }

    private func outputDirectory() throws -> URL {
        guard let raw = ProcessInfo.processInfo.environment["UZUME_CAPTURE_DIR"] else {
            throw CaptureError.missingOutputDirectory
        }
        let url = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : try projectRoot().appendingPathComponent(raw)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func projectRoot(file: StaticString = #filePath) throws -> URL {
        var url = URL(fileURLWithPath: "\(file)")
        for _ in 0..<10 {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("CLAUDE.md").path) {
                return url
            }
        }
        throw CaptureError.cannotLocateProjectRoot
    }

    enum CaptureError: Error {
        case missingOutputDirectory
        case cannotLocateProjectRoot
        case renderFailed(String)
    }
}
