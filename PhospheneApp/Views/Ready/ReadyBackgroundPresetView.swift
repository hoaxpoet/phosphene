// ReadyBackgroundPresetView — Background visual layer for ReadyView (U.5).
//
// TODO(U.5.C): Replace the gradient placeholder with a live preset preview once
// the engine grows a preview render path (Increment U.5b). The background should
// render the first planned track's preset at 0.3× opacity per UX_SPEC §6.1.
//
// Part C DEFERRED (U.5b): The engine uses a single RenderPipeline with no
// supported path for synthetic FeatureVector injection or secondary render
// surfaces. Adding a preview loop requires a dedicated engine increment — see
// DECISIONS.md D-048 and ENGINEERING_PLAN.md Increment U.5b for rationale.

import SwiftUI

// MARK: - ReadyBackgroundPresetView

/// Gradient placeholder at 0.3× opacity.
///
/// Replace with a live preset preview when Increment U.5b lands.
struct ReadyBackgroundPresetView: View {

    var body: some View {
        LinearGradient(
            colors: [
                Color(white: 0.08),
                Color(white: 0.04),
                Color(white: 0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .opacity(0.3)
        .ignoresSafeArea()
    }
}
