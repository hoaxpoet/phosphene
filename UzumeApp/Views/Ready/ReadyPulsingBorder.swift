// ReadyPulsingBorder — Ambient pulsing border overlay for ReadyView (U.5).
//
// Indicates the engine is live and listening for audio. When reduceMotion is
// true, shows a static border at 0.4 opacity per UX_SPEC §6.1 accessibility note.

import SwiftUI

// MARK: - ReadyPulsingBorder

/// An animated stroke overlay that pulses to indicate the engine is live.
///
/// Place as an overlay on the full-bleed ReadyView background. The border
/// insets 24 pt from the window edge and uses the accent color.
struct ReadyPulsingBorder: View {

    let reduceMotion: Bool

    @State private var phase: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.accentColor, lineWidth: 2)
            .opacity(currentOpacity)
            .padding(24)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 2.5)
                    .repeatForever(autoreverses: true)
                ) {
                    phase = true
                }
            }
    }

    private var currentOpacity: Double {
        if reduceMotion { return 0.4 }
        return phase ? 0.6 : 0.2
    }
}

#if DEBUG
#Preview("Animating") {
    ReadyPulsingBorder(reduceMotion: false)
        .frame(width: 480, height: 320)
        .background(Color.black)
}

#Preview("Reduced motion") {
    ReadyPulsingBorder(reduceMotion: true)
        .frame(width: 480, height: 320)
        .background(Color.black)
}
#endif
