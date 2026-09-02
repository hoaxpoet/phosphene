// ReviewCaptureHarness+Preparation — the build-specific half of the preparation captures.
//
// The scenarios in ReviewCaptureScenarios.swift are the same before and after DS.4;
// what differs is how many appearances the view has (one before, one per preference
// after) and which component declares the row labels. This file is the seam: it is
// the only part of the harness the DS.4 view rebuild replaced.
//
// AFTER flavour: two appearances (mysterious / detailed), labels read off
// `PreparationTrackRow` and `PreparationAperture`.

import Session
import SwiftUI
@testable import UzumeApp

// MARK: - Variants

enum PreparationCaptureVariants {
    static let all: [PreparationCaptureVariant] = [
        PreparationCaptureVariant(suffix: "mysterious", preference: .mysterious),
        PreparationCaptureVariant(suffix: "detailed", preference: .detailed),
    ]

    /// Injects the two environment objects the view reads: an isolated settings
    /// store carrying the preference, and a fresh accessibility state (motion on).
    @MainActor
    static func wrap(_ view: AnyView, preference: PreparationViewPreference?) -> AnyView {
        let suite = UserDefaults(suiteName: "io.uzume.capture.\(UUID().uuidString)") ?? .standard
        let store = SettingsStore(defaults: suite)
        store.preparationView = preference ?? .mysterious
        return AnyView(view.environmentObject(store).environmentObject(AccessibilityState()))
    }
}

// MARK: - Declared labels

enum PreparationRowAccessibility {
    struct RowCase {
        let name: String
        let status: TrackPreparationStatus
        var profile: TrackProfile?
    }

    @MainActor
    static func rows(tracks: [TrackIdentity], heard: [TrackProfile]) -> [String] {
        let cases: [RowCase] = [
            RowCase(name: "queued", status: .queued),
            RowCase(name: "resolving", status: .resolving),
            RowCase(name: "downloading (indeterminate)", status: .downloading(progress: -1)),
            RowCase(name: "downloading 40%", status: .downloading(progress: 0.4)),
            RowCase(name: "analyzing", status: .analyzing(stage: .stemSeparation)),
            RowCase(name: "caching", status: .analyzing(stage: .caching)),
            RowCase(name: "ready (profile not yet published)", status: .ready),
            RowCase(name: "ready — heard", status: .ready, profile: heard[0]),
            RowCase(name: "partial — stems", status: .partial(reason: "Stems unavailable")),
            RowCase(name: "failed — preview", status: .failed(reason: "Preview not available")),
        ]
        return cases.map { rowCase in
            let track = tracks[0]
            let data = RowData(
                id: track, title: track.title, artist: track.artist, status: rowCase.status, etaSeconds: nil
            )
            let row = PreparationTrackRow(row: data, profile: rowCase.profile)
            return "track row — \(rowCase.name)\t\(row.accessibilityLabel)\t\(row.accessibilityValue)\t(none)"
        }
    }
}

enum PreparationScreenAccessibility {
    /// Elements the screen declares beyond the rows and buttons. After DS.4: the
    /// cave is one accessibility element carrying every fact the light conveys.
    @MainActor
    static func rows() -> [String] {
        let canStart = String(localized: "a11y.preparing.aperture.can_start")
        let heard = String(format: String(localized: "preparation.heard_count_other"), 3, 8)
        let failed = String(format: String(localized: "preparation.failed_count_other"), 2)
        let hint = String(localized: "a11y.preparing.failed_count.hint")
        let apertureID = PreparationAperture.accessibilityID
        let one = PreparationAperture.accessibilityLabel(heard: 1, total: 8)
        let three = PreparationAperture.accessibilityLabel(heard: 3, total: 8)
        return [
            "aperture (mysterious) — before start\t\(one)\t\t\(apertureID)",
            "aperture (mysterious) — can start\t\(three)\t\(canStart)\t\(apertureID)",
            "heard line (mysterious)\t\(heard)\t\t(none)",
            "failed count line (mysterious)\t\(failed) — hint: \(hint)\t\t\(PreparationProgressView.failedCountID)",
            "header title\t(removed — DS.4)\t\t(none)",
            "header subtitle\t(removed — DS.4)\t\t(none)",
            "progress bar\t(removed — DS.4)\t\t(none)",
        ]
    }
}

extension ReviewCaptureHarness {
    /// The banner's dismiss button was deleted at DS.4 (DEAD-002): nothing to declare.
    static func bannerDismissRows() -> [String] {
        ["banner dismiss button\t(removed — DEAD-002 decided at DS.4)\t(none)"]
    }
}
