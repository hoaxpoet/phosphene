// SourceChoice — the one tile for choosing a music source. (DS.2)
//
// Replaces the two near-identical tile implementations that encoded this family
// separately — one in the connector picker, one private to the local-source
// screen (D-233). They shared a layout and a "Title. Subtitle." accessible
// label, and differed only in hover behaviour and trailing content.
//
// The component is presentation only. It receives a display model and an
// affordance and owns nothing:
// - It never constructs a `NavigationLink`. The `.navigation` affordance draws
//   the chevron and the interactive treatment; the CONSUMER wraps the tile, so
//   `ConnectorPickerViewModel` keeps sole ownership of `connectorPath`.
// - `ConnectorType` keeps its title / subtitle / symbol. Those are product
//   content and are passed in, not looked up here.
//
// Every presentation value comes from the DS.1 tokens; there is no appearance
// branch because Uzume is always dark (D-232).

import SwiftUI

// MARK: - SourceChoice

/// A single music-source tile: an icon, a title, a supporting line, and one of
/// four affordances (navigate, act, unavailable, unavailable-with-a-way-out).
struct SourceChoice: View {

    // MARK: - Affordance

    /// A secondary button offered on an unavailable tile — the Curator's way out
    /// of the condition the tile is reporting (e.g. "Open Apple Music").
    struct Recovery {
        let label: String
        let action: () -> Void

        init(label: String, action: @escaping () -> Void) {
            self.label = label
            self.action = action
        }
    }

    /// What choosing this source does.
    enum Affordance {
        /// Pushes a connector flow. The consumer wraps the tile in a
        /// `NavigationLink`; this component only draws the chevron.
        case navigation
        /// Opens a panel in place — the three local-source pickers.
        case action(() -> Void)
        /// Cannot be chosen right now. `reason` replaces the subtitle, so the
        /// tile states its condition rather than promising what it cannot honour.
        case unavailable(reason: String, recovery: Recovery?)
    }

    // MARK: - Display model

    let systemImage: String
    let title: String
    let subtitle: String
    let accessibilityID: String
    let affordance: Affordance

    @State private var isHovered: Bool = false

    // MARK: - Body

    var body: some View {
        interactiveWrapper
            .accessibilityIdentifier(accessibilityID)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                AccessibilityLabels.sourceChoiceLabel(title: title, detail: detail)
            )
            .accessibilityHint(AccessibilityLabels.sourceChoiceHint(hintKind))
    }

    /// `.action` is the only affordance that owns its own button — `.navigation`
    /// is wrapped by the consumer and `.unavailable` is not actionable at all.
    @ViewBuilder
    private var interactiveWrapper: some View {
        switch affordance {
        case .action(let run):
            Button(action: run) { tile }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
        case .navigation:
            tile
                .onHover { isHovered = $0 }
        case .unavailable:
            tile
        }
    }

    // MARK: - Tile

    private var tile: some View {
        HStack(spacing: UzumeSpace.x4) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: UzumeSpace.x8)
                .foregroundColor(isAvailable ? UzumeAppColor.textPrimary : UzumeAppColor.textDisabled)

            VStack(alignment: .leading, spacing: UzumeSpace.x1) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isAvailable ? UzumeAppColor.textPrimary : UzumeAppColor.textDisabled)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(isAvailable ? UzumeAppColor.textTertiary : UzumeAppColor.textDisabled)
            }

            Spacer()

            trailing
        }
        .padding(UzumeSpace.x4)
        .background(
            RoundedRectangle(cornerRadius: UzumeAppRadius.md).fill(fill)
        )
        .contentShape(RoundedRectangle(cornerRadius: UzumeAppRadius.md))
    }

    /// Chevron for navigation, the recovery button for an unavailable tile that
    /// offers one, nothing for an action tile (an action is not a sub-flow).
    @ViewBuilder
    private var trailing: some View {
        switch affordance {
        case .navigation:
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(UzumeAppColor.textDisabled)
        case .action:
            EmptyView()
        case .unavailable(_, let recovery):
            if let recovery {
                Button(recovery.label) { recovery.action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Derived presentation

    private var isAvailable: Bool {
        if case .unavailable = affordance { return false }
        return true
    }

    /// The supporting line: the subtitle when the source can be chosen, the
    /// reason when it cannot.
    private var detail: String {
        if case .unavailable(let reason, _) = affordance { return reason }
        return subtitle
    }

    private var fill: Color {
        guard isAvailable else { return UzumeAppColor.surface }
        return isHovered ? UzumeAppColor.surfaceSelected : UzumeAppColor.surfaceRaised
    }

    private var hintKind: AccessibilityLabels.SourceChoiceKind {
        switch affordance {
        case .navigation:  return .navigation
        case .action:      return .action
        case .unavailable: return .unavailable
        }
    }
}

// MARK: - Previews

#Preview("Four affordances") {
    VStack(spacing: UzumeSpace.x3) {
        SourceChoice(
            systemImage: "music.note.list",
            title: "Apple Music",
            subtitle: "Read your current Apple Music playlist",
            accessibilityID: "preview.navigation",
            affordance: .navigation
        )
        SourceChoice(
            systemImage: "folder.fill",
            title: "Folder",
            subtitle: "Read every supported file in alphabetical order",
            accessibilityID: "preview.action",
            affordance: .action {}
        )
        SourceChoice(
            systemImage: "music.note.list",
            title: "Apple Music",
            subtitle: "Read your current Apple Music playlist",
            accessibilityID: "preview.unavailable",
            affordance: .unavailable(reason: "Open Apple Music first", recovery: nil)
        )
        SourceChoice(
            systemImage: "music.note.list",
            title: "Apple Music",
            subtitle: "Read your current Apple Music playlist",
            accessibilityID: "preview.unavailable.recovery",
            affordance: .unavailable(
                reason: "Open Apple Music first",
                recovery: .init(label: "Open Apple Music") {}
            )
        )
    }
    .padding(UzumeSpace.x6)
    .background(UzumeAppColor.canvas)
}
