// ReviewCaptureHarness+Preparation — the build-specific half of the preparation captures.
//
// The scenarios in ReviewCaptureHarness.swift are the same before and after DS.4;
// what differs is how many appearances the view has (one before, one per preference
// after) and which component declares the row labels. This file is the seam: it is
// the only part of the harness the DS.4 view rebuild replaces.
//
// BEFORE flavour: one appearance, labels read off `TrackPreparationRow`.

import Session
import SwiftUI
@testable import UzumeApp

// MARK: - Preference (pre-DS.4 placeholder — the build has no such setting)

enum PreparationViewPreference { case single }

// MARK: - Variants

enum PreparationCaptureVariants {
    static let all: [PreparationCaptureVariant] = [
        PreparationCaptureVariant(suffix: "", preference: nil),
    ]

    @MainActor
    static func wrap(_ view: AnyView, preference: PreparationViewPreference?) -> AnyView { view }
}

// MARK: - Declared labels

enum PreparationRowAccessibility {
    @MainActor
    static func rows(tracks: [TrackIdentity], heard: [TrackProfile]) -> [String] {
        let cases: [(String, TrackPreparationStatus)] = [
            ("queued", .queued),
            ("resolving", .resolving),
            ("downloading (indeterminate)", .downloading(progress: -1)),
            ("downloading 40%", .downloading(progress: 0.4)),
            ("analyzing", .analyzing(stage: .stemSeparation)),
            ("caching", .analyzing(stage: .caching)),
            ("ready", .ready),
            ("partial — stems", .partial(reason: "Stems unavailable")),
            ("failed — preview", .failed(reason: "Preview not available")),
        ]
        return cases.map { name, status in
            let track = tracks[0]
            let data = RowData(id: track, title: track.title, artist: track.artist, status: status, etaSeconds: nil)
            let row = TrackPreparationRow(row: data)
            return "track row — \(name)\t\(row.accessibilityLabel)\t\(row.accessibilityValue)\t(none)"
        }
    }
}

enum PreparationScreenAccessibility {
    /// Elements the screen declares beyond the rows and buttons. Before DS.4: the
    /// header and progress bar carry no accessibility label of their own.
    static func rows() -> [String] {
        [
            "header title\tPreparing your session\t\t(none)",
            "header subtitle\t8 tracks\t\t(none)",
            "progress bar\t(no label — a bare Capsule, invisible to VoiceOver)\t\t(none)",
        ]
    }
}

extension ReviewCaptureHarness {
    /// The banner's dismiss button: wired but never rendered (DEAD-002).
    static func bannerDismissRows() -> [String] {
        let dismissLabel = String(localized: "a11y.preparation.topBanner.dismiss.label")
        let note = "\(NoticeBanner.dismissID) — NEVER RENDERED (no construction site passes onDismiss)"
        return ["banner dismiss button\t\(dismissLabel)\t\(note)"]
    }
}
