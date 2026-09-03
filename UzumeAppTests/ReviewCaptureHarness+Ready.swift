// ReviewCaptureHarness+Ready — the DS.5 ready screens, rendered for the M7 page.
//
//   TEST_RUNNER_UZUME_CAPTURE=1 TEST_RUNNER_UZUME_CAPTURE_SET=ready \
//   TEST_RUNNER_UZUME_CAPTURE_DIR=docs/reviews/DS.5/after \
//     xcodebuild -scheme UzumeApp -destination 'platform=macOS' test \
//     -only-testing:UzumeAppTests/ReviewCaptureHarness
//
// Rendered with reduced motion on so the cave holds still and the capture is
// deterministic; the live captures next to these show it moving.

import Audio
import Combine
import Orchestrator
import Session
import Shared
import SwiftUI
import Testing
@testable import UzumeApp

// MARK: - Harness entry

extension ReviewCaptureHarness {
    @Test("render the two ready screens (DS.5)")
    func captureReadyScreens() async throws {
        guard Self.captureSet.contains("ready") else { return }
        let dir = try outputDirectory()
        let character = PreparationCharacter(profiles: ReadyCaptureScenario.heardProfiles(20))
        for (name, view) in ReadyCaptureScenario.surfaces(character: character) {
            try await render(view, to: dir.appendingPathComponent("\(name).png"))
        }
        try ReadyCaptureScenario.accessibilityRows()
            .joined(separator: "\n")
            .appending("\n")
            .write(to: dir.appendingPathComponent("a11y-ready.txt"), atomically: true, encoding: .utf8)
    }
}

// MARK: - Scenarios

enum ReadyCaptureScenario {
    static let frame = CGSize(width: 960, height: 600)

    @MainActor
    static func surfaces(character: PreparationCharacter) -> [(String, AnyView)] {
        let signal = CurrentValueSubject<AudioSignalState, Never>(.silent)
        let plan = CurrentValueSubject<PlannedSession?, Never>(nil)
        let origins: [(String, SessionOrigin?)] = [
            ("ready-streaming-appleMusic", .playlist(.appleMusicCurrentPlaylist)),
            ("ready-streaming-spotify", .playlist(.spotifyCurrentQueue)),
            ("ready-streaming-fallback", nil),
        ]
        var out: [(String, AnyView)] = origins.map { name, origin in
            (name, AnyView(
                ReadyView(
                    origin: origin,
                    character: character,
                    sessionManager: SessionManager.testInstance(),
                    audioSignalStatePublisher: signal.eraseToAnyPublisher(),
                    planPublisher: plan.eraseToAnyPublisher(),
                    onBeginPlayback: {},
                    reduceMotion: true
                )
                .frame(width: frame.width, height: frame.height)
            ))
        }
        out.append(("ready-localFile-countdown", AnyView(
            LocalFileCountdownView(
                character: character,
                reduceMotion: true,
                onBegin: {},
                onEndSession: {}
            )
            .frame(width: frame.width, height: frame.height)
        )))
        return out
    }

    /// The labels the two screens DECLARE, one row per element — the same contract
    /// convention as the status and preparation rows.
    @MainActor
    static func accessibilityRows() -> [String] {
        let pressPlay = String(localized: "ready.press_play")
        let fallback = String(localized: "ready.source.fallback")
        let beginNow = String(localized: "ready.begin_now_button")
        let beginHint = String(localized: "a11y.ready.begin_now.hint")
        let endSession = String(localized: "ready.end_session_button")
        let beats = LocalFileCountdownView.beats
            .map(LocalFileCountdownView.accessibilityLabel)
            .joined(separator: " / ")
        return [
            "surface\tdeclared VoiceOver label\taccessibility identifier",
            "ready headline (streaming)\t\(String(localized: "ready.headline"))\t\(ReadyView.headlineID)",
            "press play — Apple Music\t\(String(format: pressPlay, "Apple Music"))\t(none)",
            "press play — Spotify\t\(String(format: pressPlay, "Spotify"))\t(none)",
            "press play — no source\t\(String(format: pressPlay, fallback))\t(none)",
            "begin now button\t\(beginNow) — hint: \(beginHint)\t\(ReadyView.beginNowButtonID)",
            "end session button (streaming)\t\(endSession)\t\(ReadyView.endSessionButtonID)",
            "countdown numeral — 3 / 2 / 1\t\(beats) (each announced)\t\(LocalFileCountdownView.countID)",
            "end session button (countdown)\t\(endSession)\t\(LocalFileCountdownView.endSessionButtonID)",
            "preview the plan button\t(removed — DS.5, D-240)\t(none)",
            "pulsing border\t(removed — DS.5)\t(none)",
        ]
    }

    static func heardProfiles(_ count: Int) -> [TrackProfile] {
        (0..<count).map { i in
            var balance = StemFeatures.zero
            balance.drumsEnergy = 0.3 + 0.4 * Float(i % 3) / 2
            balance.vocalsEnergy = 0.2 + 0.3 * Float((i + 1) % 2)
            balance.bassEnergy = 0.4
            balance.otherEnergy = 0.3
            let mood = EmotionalState(valence: Float(i % 4) / 2 - 0.75, arousal: Float((i * 3) % 5) / 2 - 1)
            return TrackProfile(
                bpm: 90 + Float(i * 7 % 50),
                key: "A minor",
                mood: mood,
                spectralCentroidAvg: 0.3 + 0.4 * Float(i % 5) / 4,
                stemEnergyBalance: balance,
                beatIrregular: i % 6 == 0
            )
        }
    }
}
