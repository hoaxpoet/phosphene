// ContentView — Main visualizer view with keyboard-driven preset navigation.

import Renderer
import SwiftUI

// MARK: - ContentView

/// Root view displaying the Metal visualizer with a preset name overlay.
///
/// Keyboard controls:
/// - Right arrow / Space: next preset
/// - Left arrow: previous preset
/// - D: toggle debug overlay
/// - C: toggle feature capture
/// - R: toggle MIR recording
struct ContentView: View {
    @StateObject private var engine = VisualizerEngine()

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

            // Debug overlay — toggle with 'D' key.
            if engine.showDebugOverlay {
                DebugOverlayView(engine: engine)
            }
        }
        .focusable()
        .frame(minWidth: 800, minHeight: 600)
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
    }
}
