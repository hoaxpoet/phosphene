// DarkVibrancyView — NSVisualEffectView locked to vibrant-dark, regardless
// of system appearance (DASH.7.2).
//
// Phosphene's brand context (`.impeccable.md`) is unambiguous: "Theme: Dark.
// Phosphene runs in dim rooms, often on a TV." SwiftUI's `.regularMaterial`
// is system-appearance-adaptive — on macOS Light it renders a beige/grey
// surface that fails contrast for the dashboard text. This view forces
// the panel to render `vibrantDark` always.
//
// macOS-specific note from `.impeccable.md`:
//   Materials: use `NSVisualEffectView` (.hudWindow or .underWindowBackground)
//   for overlapping panels, not opaque surfaces.
// We use `.hudWindow` because the dashboard is an overlapping HUD-style
// panel that floats over the visualizer.

import AppKit
import SwiftUI

struct DarkVibrancyView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = NSAppearance(named: .vibrantDark)
    }
}
