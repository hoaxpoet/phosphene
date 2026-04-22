// PlaybackView — Shown when SessionManager.state == .playing.
// Absorbs the full MetalView + overlay chrome from the pre-U.1 ContentView verbatim.
// U.6 adds auto-hiding overlay chrome and keyboard shortcut polish.

import Renderer
import SwiftUI

// MARK: - PlaybackView

/// Full-bleed Metal visualizer with preset name badge, audio signal badge,
/// and debug overlay. Keyboard shortcuts: right/space = next preset,
/// left = previous, D = debug, C = capture, R = MIR record, G = G-buffer.
@MainActor
struct PlaybackView: View {
    static let accessibilityID = "phosphene.view.playing"

    @EnvironmentObject private var engine: VisualizerEngine

    var body: some View {
        ZStack {
            MetalView(context: engine.context, pipeline: engine.pipeline)

            if let name = engine.currentPresetName {
                Text(name)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(8)
                    .background(.black.opacity(0.4))
                    .cornerRadius(6)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if engine.audioSignalState == .silent {
                NoAudioSignalBadge()
            }

            if engine.showDebugOverlay {
                DebugOverlayView(engine: engine)
            }
        }
        .focusable()
        .frame(minWidth: 800, minHeight: 600)
        .accessibilityIdentifier(Self.accessibilityID)
        .onAppear {
            engine.startAudio()
        }
        .onKeyPress(.rightArrow) {
            engine.nextPreset()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            engine.previousPreset()
            return .handled
        }
        .onKeyPress(.space) {
            engine.nextPreset()
            return .handled
        }
        .onKeyPress("d") {
            engine.toggleDebugOverlay()
            return .handled
        }
        .onKeyPress("c") {
            engine.toggleCapture()
            return .handled
        }
        .onKeyPress("r") {
            engine.toggleRecording()
            return .handled
        }
        .onKeyPress("g") {
            engine.debugGBufferMode.toggle()
            return .handled
        }
    }
}

// MARK: - NoAudioSignalBadge

/// Non-intrusive badge shown when the audio tap is delivering silence —
/// the typical symptom of DRM-triggered silencing on protected streams.
/// Auto-dismissed when the signal recovers (driven by `engine.audioSignalState`).
private struct NoAudioSignalBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 11))
            Text("No audio signal")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5))
        .cornerRadius(6)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
