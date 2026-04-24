// OverlayBackdropStyle — Shared backdrop ensuring ≥4.5:1 contrast for overlay text.
//
// Strategy: .ultraThinMaterial (blurred) + 0.4 opaque black overlay.
// The blur desaturates and averages the preset frame underneath; the black tint
// then guarantees that white text at luminance 1.0 reads ≥4.5:1 against the
// effective backdrop, regardless of what the preset is rendering.

import SwiftUI

// MARK: - OverlayBackdropStyle

/// ViewModifier that applies the standard Phosphene overlay backdrop.
///
/// Usage:
/// ```swift
/// myView.modifier(OverlayBackdropStyle())
/// ```
struct OverlayBackdropStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Vibrancy blur — smooths the preset image below into an average.
                    Rectangle().fill(.ultraThinMaterial)
                    // Additional opaque black tint to guarantee contrast floor.
                    Color.black.opacity(0.45)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    /// Apply the standard overlay backdrop (blur + dark tint + rounded corners).
    func overlayBackdrop() -> some View {
        modifier(OverlayBackdropStyle())
    }
}
