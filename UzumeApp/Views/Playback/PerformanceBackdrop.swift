// PerformanceBackdrop — Shared backdrop ensuring ≥4.5:1 contrast for overlay text.
//
// Strategy: .ultraThinMaterial (blurred) + UzumeAppColor.Performance.backdropTint.
// The blur desaturates and averages the preset frame underneath; the tint — 45%
// black — then guarantees that `UzumeAppColor.textPrimary` at full luminance reads
// ≥4.5:1 against the effective backdrop, regardless of what the preset is rendering.
//
// The 45% is a MEASURED result, not a palette choice: `PresetContrastCertification-
// Tests` simulates exactly this composite against real preset frames. tokens.css'
// `--color-scrim` is 72% black and is NOT a drop-in substitute — swapping it changes
// what was measured. The corner is `UzumeRadius.standard` (10), the same value this
// modifier has always used.

import SwiftUI

// MARK: - PerformanceBackdrop

/// ViewModifier that applies the standard Uzume overlay backdrop.
///
/// Usage:
/// ```swift
/// myView.modifier(PerformanceBackdrop())
/// ```
struct PerformanceBackdrop: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Vibrancy blur — smooths the preset image below into an average.
                    Rectangle().fill(.ultraThinMaterial)
                    // Additional opaque tint to guarantee the contrast floor.
                    UzumeAppColor.Performance.backdropTint
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: UzumeRadius.standard))
    }
}

extension View {
    /// Apply the standard performance backdrop (blur + dark tint + rounded corners).
    func performanceBackdrop() -> some View {
        modifier(PerformanceBackdrop())
    }
}
