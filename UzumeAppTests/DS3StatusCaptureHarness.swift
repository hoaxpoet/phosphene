// DS3StatusCaptureHarness — renders every status surface in every tone to PNG
// for the DS.3 M7 review page. (DS.3 task 2 / task 9)
//
// Gated on UZUME_DS3_CAPTURE=1 so a normal `xcodebuild test` never writes files.
// Follows the HARNESS_TEMPLATES=1 pattern already used by the engine suite.
//
//   UZUME_DS3_CAPTURE=1 UZUME_DS3_DIR=docs/reviews/DS.3/before \
//     xcodebuild -scheme UzumeApp -destination 'platform=macOS' test \
//     -only-testing:UzumeAppTests/DS3StatusCaptureHarness
//
// Why rendered rather than driven through a live session: several tones are not
// reachable from any real failure — `UzumeToast.Severity` has no `fatal`, and the
// banner's `info`/`fatal` arms exist only after DS.3 gives it a severity at all.
// Rendering covers the whole map; the reachability of each state is recorded in
// CAPTURES.md next to the image.

import SwiftUI
import Testing
@testable import UzumeApp
@testable import Shared

// MARK: - DS3StatusCaptureHarness

@Suite("DS.3 status capture harness", .enabled(if: ProcessInfo.processInfo.environment["UZUME_DS3_CAPTURE"] == "1"))
@MainActor
struct DS3StatusCaptureHarness {

    @Test("render every status surface in every tone")
    func captureAll() throws {
        let dir = try outputDirectory()

        for (name, view) in Self.surfaces() {
            try render(view, to: dir.appendingPathComponent("\(name).png"))
        }

        try Self.accessibilityRows()
            .joined(separator: "\n")
            .appending("\n")
            .write(to: dir.appendingPathComponent("a11y.txt"), atomically: true, encoding: .utf8)
    }

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
        let dismissLabel = String(localized: "a11y.preparation.topBanner.dismiss.label")
        let dismissNote = "\(bannerDismissIdentifier) — NEVER RENDERED (no construction site passes onDismiss)"
        rows.append("banner dismiss button\t\(dismissLabel)\t\(dismissNote)")

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
    static let bannerDismissIdentifier   = NoticeBanner.dismissID

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

    private func render(_ view: AnyView, to url: URL) throws {
        let renderer = ImageRenderer(content: view.preferredColorScheme(.dark))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.renderFailed(url.lastPathComponent)
        }
        try png.write(to: url)
    }

    private func outputDirectory() throws -> URL {
        guard let raw = ProcessInfo.processInfo.environment["UZUME_DS3_DIR"] else {
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
