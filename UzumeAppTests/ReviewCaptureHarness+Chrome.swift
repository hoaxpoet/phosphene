// ReviewCaptureHarness+Chrome — the DS.6 playback chrome, rendered for the M7 page.
//
//   TEST_RUNNER_UZUME_CAPTURE=1 TEST_RUNNER_UZUME_CAPTURE_SET=chrome \
//   TEST_RUNNER_UZUME_CAPTURE_DIR=docs/reviews/DS.6/<before|after> \
//     xcodebuild -scheme UzumeApp -destination 'platform=macOS' test \
//       -only-testing:UzumeAppTests/ReviewCaptureHarness
//
// The shipped `PlaybackChromeView` is driven through the real `PlaybackChromeViewModel`
// by scripted publishers — the same seam `PlaybackView` uses — over a stand-in for the
// live frame (the performed-light gradient, so the backdrop has something bright to
// blur). Reduced motion on so the pulse and the spinner hold still; the live captures
// beside these show them moving. The quiet timer never fires here (except for the
// `chrome-quiet` scenario, which lets it), so each capture is a settled state; the
// fade itself is a moment in an animation and is captured live, not rendered.

import Audio
import Combine
import Orchestrator
import Presets
import Session
import Shared
import SwiftUI
import Testing
@testable import UzumeApp

// MARK: - Harness entry

extension ReviewCaptureHarness {
    @Test("render the playback chrome in every reachable state (DS.6)")
    func captureChromeStates() async throws {
        guard Self.captureSet.contains("chrome") else { return }
        let dir = try outputDirectory()
        for (name, view) in try ChromeCaptureScenario.surfaces() {
            try await render(view, to: dir.appendingPathComponent("\(name).png"))
        }
        try ChromeCaptureScenario.accessibilityRows()
            .joined(separator: "\n")
            .appending("\n")
            .write(to: dir.appendingPathComponent("a11y-chrome.txt"), atomically: true, encoding: .utf8)
    }
}

// MARK: - Scenarios

/// A delay that never elapses, so the chrome's auto-hide cannot fire mid-capture.
private struct NeverDelay: DelayProviding {
    func sleep(seconds: Double) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

enum ChromeCaptureScenario {
    static let frame = CGSize(width: 960, height: 600)

    /// Every publisher the view model reads, held so a scenario can script them.
    @MainActor
    final class Feeds {
        let signal = CurrentValueSubject<AudioSignalState, Never>(.active)
        let track = CurrentValueSubject<TrackMetadata?, Never>(nil)
        let artwork = CurrentValueSubject<Data?, Never>(nil)
        let index = CurrentValueSubject<Int?, Never>(nil)
        let preset = CurrentValueSubject<String?, Never>(nil)
        let plan = CurrentValueSubject<PlannedSession?, Never>(nil)
        let readiness = CurrentValueSubject<ProgressiveReadinessLevel, Never>(.fullyPrepared)
        let source = CurrentValueSubject<SessionOrigin?, Never>(nil)
        let paused = CurrentValueSubject<Bool, Never>(false)
        let toasts = ToastManager()

        func makeViewModel(delay: any DelayProviding) -> PlaybackChromeViewModel {
            PlaybackChromeViewModel(
                audioSignalStatePublisher: signal.eraseToAnyPublisher(),
                currentTrackPublisher: track.eraseToAnyPublisher(),
                currentTrackArtworkDataPublisher: artwork.eraseToAnyPublisher(),
                currentTrackIndexPublisher: index.eraseToAnyPublisher(),
                currentPresetNamePublisher: preset.eraseToAnyPublisher(),
                livePlanPublisher: plan.eraseToAnyPublisher(),
                reduceMotionPublisher: Just(true).eraseToAnyPublisher(),
                progressiveReadinessPublisher: readiness.eraseToAnyPublisher(),
                currentSourcePublisher: source.eraseToAnyPublisher(),
                isLocalFilePausedPublisher: paused.eraseToAnyPublisher(),
                delay: delay
            )
        }
    }

    struct Scenario {
        let name: String
        let script: @MainActor (Feeds) -> Void
        var showTrackInformation = true
        var delay: any DelayProviding = NeverDelay()
        var afterBind: @MainActor (PlaybackChromeViewModel) -> Void = { _ in }
    }

    @MainActor
    static func all() throws -> [Scenario] {
        let plan = try makePlan(trackCount: 6)
        let streaming: @MainActor (Feeds) -> Void = { feeds in
            feeds.track.send(TrackMetadata(title: "Take Five", artist: "Dave Brubeck"))
            feeds.preset.send("Skein")
            feeds.plan.send(plan)
            feeds.index.send(2)
            feeds.source.send(.playlist(.appleMusicCurrentPlaylist))
        }
        let localFile: @MainActor (Feeds) -> Void = { feeds in
            streaming(feeds)
            feeds.source.send(.localFile(URL(fileURLWithPath: "/tmp/take_five.m4a")))
            feeds.artwork.send(artworkPNG())
        }
        return [
            Scenario(name: "chrome-streaming-planned", script: streaming),
            Scenario(name: "chrome-streaming-artwork", script: { feeds in
                streaming(feeds)
                feeds.artwork.send(artworkPNG())
            }),
            Scenario(name: "chrome-streaming-reactive", script: { feeds in
                streaming(feeds)
                feeds.plan.send(nil)
                feeds.index.send(nil)
            }),
            Scenario(name: "chrome-localFile-playing", script: localFile),
            Scenario(name: "chrome-localFile-paused", script: { feeds in
                localFile(feeds)
                feeds.paused.send(true)
            }),
            Scenario(name: "chrome-listening", script: { feeds in
                streaming(feeds)
                feeds.signal.send(.silent)
            }),
            Scenario(name: "chrome-stillPreparing", script: { feeds in
                streaming(feeds)
                feeds.readiness.send(.readyForFirstTracks)
            }),
            Scenario(name: "chrome-toast-info", script: { feeds in
                streaming(feeds)
                feeds.toasts.enqueue(UzumeToast(severity: .info, copy: "Display connected."))
            }),
            Scenario(name: "chrome-toast-warning", script: { feeds in
                streaming(feeds)
                feeds.toasts.enqueue(UzumeToast(severity: .warning, copy: "Display disconnected mid-session."))
            }),
            Scenario(name: "chrome-toast-degradation", script: { feeds in
                streaming(feeds)
                feeds.toasts.enqueue(UzumeToast(severity: .degradation, copy: "Stem separation failed."))
            }),
            Scenario(name: "chrome-toast-fatal", script: { feeds in
                streaming(feeds)
                feeds.toasts.enqueue(UzumeToast(severity: .fatal, copy: "No audio detected."))
            }),
            // The Space toggle: the only way to hide the chrome outright after DS.6.
            Scenario(name: "chrome-hidden", script: streaming, afterBind: { $0.toggleOverlay() }),
            // DS.6: after inactivity — End session alone (an InstantDelay lets the timer fire).
            Scenario(name: "chrome-quiet", script: localFile, delay: InstantDelay()),
            // DS.6: track information off — no card, no artwork, the toggle reads "Show".
            Scenario(name: "chrome-trackInfoHidden", script: localFile, showTrackInformation: false),
        ]
    }

    @MainActor
    static func surfaces() throws -> [(String, AnyView)] {
        try all().map { scenario in
            let feeds = Feeds()
            scenario.script(feeds)
            let viewModel = feeds.makeViewModel(delay: scenario.delay)
            scenario.afterBind(viewModel)
            let chrome = PlaybackChromeView(
                viewModel: viewModel,
                toastManager: feeds.toasts,
                showTrackInformation: .constant(scenario.showTrackInformation),
                onSettings: {},
                onEndSession: {}
            )
            return (scenario.name, AnyView(
                ZStack {
                    UzumeColor.performedLight
                    chrome
                }
                .frame(width: frame.width, height: frame.height)
            ))
        }
    }

    // MARK: - Declared labels and identifiers

    /// The labels the chrome DECLARES, one row per element — the same contract
    /// convention as the status, preparation and ready rows.
    @MainActor
    static func accessibilityRows() -> [String] {
        let card = AccessibilityLabels.trackInfoCardLabel(title: "Take Five", artist: "Dave Brubeck", preset: "Skein")
        let cardHint = String(localized: "a11y.trackInfoCard.hint")
        let settingsTip = String(localized: "playback.controls.settings.tooltip")
        let settingsHint = String(localized: "a11y.playback.settings.hint")
        let endTip = String(localized: "playback.controls.endSession.tooltip")
        let endHint = String(localized: "a11y.playback.endSession.hint")
        let endQuietHint = String(localized: "a11y.playback.endSession.hint.quiet")
        let showInfo = String(localized: "preparation.toggle_track_info.show")
        let hideInfo = String(localized: "preparation.toggle_track_info.hide")
        let showHint = String(localized: "a11y.playback.toggleTrackInfo.hint.show")
        let hideHint = String(localized: "a11y.playback.toggleTrackInfo.hint.hide")
        let preparing = String(localized: "playback.still_preparing")
        let preparingTip = String(localized: "playback.still_preparing.tooltip")
        let toggleID = PlaybackControlsCluster.toggleTrackInfoID
        let endID = PlaybackControlsCluster.endSessionID
        var rows = [
            "surface\tdeclared VoiceOver label\taccessibility identifier",
            "chrome (container)\t(no explicit label)\t\(PlaybackChromeView.accessibilityID)",
            "track info card\t\(card) — hint: \(cardHint)\t\(TrackInfoCardView.accessibilityID)",
            "artwork slot\t(hidden from VoiceOver — the card's combined label carries the track)"
                + "\t\(TrackInfoCardView.artworkSlotID)",
            "orchestrator state pill\t(removed — DS.6, D-241)\t(none)",
            "progress dots\t\(String(localized: "a11y.progressDots.label")) — value: Track 3 of 6"
                + "\t\(SessionProgressDotsView.accessibilityID)",
            "controls cluster (container)\t(no explicit label)\t\(PlaybackControlsCluster.accessibilityID)",
            "toggle track info (shown)\t\(hideInfo) — hint: \(hideHint)\t\(toggleID)",
            "toggle track info (hidden)\t\(showInfo) — hint: \(showHint)\t\(toggleID)",
            "settings button\t\(settingsTip) — hint: \(settingsHint)\t(none)",
            "end session button\t\(endTip) — hint: \(endHint)\t\(endID)",
            "end session button (quiet)\t\(endTip) — hint: \(endQuietHint)\t\(endID)",
            "still preparing indicator\t\(preparing) — hint: \(preparingTip)\t(none)",
            "listening badge\t\(String(localized: "a11y.listeningBadge.label"))\t\(ListeningBadgeView.accessibilityID)",
            "local transport (container)\t(no explicit label — children read in order)"
                + "\t\(LocalFileTransportBar.accessibilityID)",
            "transport — stop\t\(String(localized: "playback.transport.stop.a11y"))\t(none)",
            "transport — previous\t\(String(localized: "playback.transport.prev.a11y"))\t(none)",
            "transport — play\t\(String(localized: "playback.transport.play.a11y"))\t(none)",
            "transport — pause\t\(String(localized: "playback.transport.pause.a11y"))\t(none)",
            "transport — next\t\(String(localized: "playback.transport.next.a11y"))\t(none)",
        ]
        for (severity, copy) in [(UzumeToast.Severity.info, "Display connected."),
                                 (.warning, "Display disconnected mid-session."),
                                 (.degradation, "Stem separation failed."),
                                 (.fatal, "No audio detected.")] {
            let label = AccessibilityLabels.toastLabel(copy: copy, severity: severity)
            rows.append("toast — \(severity)\t\(label)\t(none — announced on insert)")
        }
        rows.append("")
        rows.append("identifier\tdeclared by")
        for (id, owner) in identifiers() { rows.append("\(id)\t\(owner)") }
        return rows
    }

    /// Every `uzume.playback.*` identifier the chrome declares, read off the types.
    @MainActor
    static func identifiers() -> [(String, String)] {
        [
            (PlaybackChromeView.accessibilityID, "PlaybackChromeView"),
            (TrackInfoCardView.accessibilityID, "TrackInfoCardView"),
            (TrackInfoCardView.artworkSlotID, "TrackInfoCardView"),
            (PlaybackControlsCluster.accessibilityID, "PlaybackControlsCluster"),
            (PlaybackControlsCluster.toggleTrackInfoID, "PlaybackControlsCluster (new — DS.6)"),
            (PlaybackControlsCluster.endSessionID, "PlaybackControlsCluster (new — DS.6)"),
            (SessionProgressDotsView.accessibilityID, "SessionProgressDotsView"),
            (ListeningBadgeView.accessibilityID, "ListeningBadgeView"),
            (LocalFileTransportBar.accessibilityID, "LocalFileTransportBar"),
            (ShortcutHelpOverlayView.accessibilityID, "ShortcutHelpOverlayView (Layer 4, not chrome)"),
        ]
    }

    // MARK: - Fixtures

    static func makePlan(trackCount: Int) throws -> PlannedSession {
        let json = """
        {"name":"Skein","family":"hypnotic","motion_intensity":0.5,
         "color_temperature_range":[0.3,0.7],"fatigue_risk":"medium",
         "complexity_cost":{"tier1":1.0,"tier2":1.0},
         "transition_affordances":["crossfade"]}
        """
        let preset = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        let tracks = (0..<trackCount).map {
            (TrackIdentity(title: "Track \($0)", artist: "Artist \($0)", duration: 180), TrackProfile.empty)
        }
        return try DefaultSessionPlanner().plan(tracks: tracks, catalog: [preset], deviceTier: .tier1)
    }

    /// A 96 × 96 gradient square standing in for album art.
    static func artworkPNG() -> Data? {
        let size = NSSize(width: 96, height: 96)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(red: 0.50, green: 0.42, blue: 1.0, alpha: 1),
                            NSColor(red: 1.00, green: 0.42, blue: 0.29, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: 45)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
