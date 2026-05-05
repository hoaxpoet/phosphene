// PlaybackShortcutRegistry — Single source of truth for all in-session keyboard shortcuts.
//
// Spec deviation from UX_SPEC §7.4 vs §7.7:
// UX_SPEC §7.4 lists `?` for plan-preview overlay. §7.7 says `Shift+?` for help overlay.
// On US keyboards `?` physically requires Shift, making a bare-`?` binding ambiguous.
// Decision: Shift+? = help overlay (ShortcutHelpOverlayView). Plain `P` = plan preview.
// Documented in DECISIONS.md D-049.

import AppKit
import Foundation
import Orchestrator

// MARK: - ShortcutCategory

/// Logical grouping for display in ShortcutHelpOverlayView.
enum ShortcutCategory: String, CaseIterable {
    case playback       = "Playback"
    case liveAdaptation = "Live Adaptation"
    case developer      = "Developer"
}

// MARK: - PlaybackShortcut

/// One entry in the registry: a key + modifier combination mapped to an action.
struct PlaybackShortcut: Identifiable {
    let id: String               // Stable string ID for tests and coverage checks.
    let key: String              // Printable character or AppKit key code name.
    let modifiers: NSEvent.ModifierFlags
    let label: String            // Human-readable description for help overlay.
    let category: ShortcutCategory
    let action: @MainActor () -> Void

    // MARK: - Matching

    /// Returns true when the event matches this shortcut's key + modifiers.
    func matches(event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers else { return false }
        let exactMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return chars.lowercased() == key.lowercased() && exactMods == modifiers
    }
}

// MARK: - PlaybackShortcutRegistry

/// Declarative registry of all in-session keyboard shortcuts.
///
/// Build one instance at `PlaybackView.onAppear` and pass it to `PlaybackKeyMonitor`.
/// `ShortcutHelpOverlayView` reads `.shortcuts` to render the help table.
@MainActor
final class PlaybackShortcutRegistry {

    // MARK: - Properties

    let shortcuts: [PlaybackShortcut]

    // MARK: - Init

    // swiftlint:disable function_body_length
    /// Build the registry.
    ///
    /// - Parameters:
    ///   - actionRouter: Router for live-adaptation actions.
    ///   - onToggleFullscreen: Toggle fullscreen (⌘F).
    ///   - onMoveToSecondaryDisplay: Move to secondary display (⌘⇧F).
    ///   - onToggleOverlay: Toggle chrome visibility (Space).
    ///   - onToggleDebug: Toggle debug overlay (D).
    ///   - onHandleEsc: Esc — exit fullscreen or show end-session confirm.
    ///   - onShowHelp: Show shortcut help overlay (⇧?).
    ///   - onShowPlanPreview: Show plan-preview sheet (P).
    init(
        actionRouter: any PlaybackActionRouter,
        onToggleFullscreen: @escaping @MainActor () -> Void,
        onMoveToSecondaryDisplay: @escaping @MainActor () -> Void,
        onToggleOverlay: @escaping @MainActor () -> Void,
        onToggleDebug: @escaping @MainActor () -> Void,
        onHandleEsc: @escaping @MainActor () -> Void,
        onShowHelp: @escaping @MainActor () -> Void,
        onShowPlanPreview: @escaping @MainActor () -> Void,
        onToggleDiagnosticHold: (@MainActor () -> Void)? = nil,
        onToggleForceSpider: (@MainActor () -> Void)? = nil,
        onDebugNextPreset: (@MainActor () -> Void)? = nil,
        onDebugPreviousPreset: (@MainActor () -> Void)? = nil,
        onDecreaseBeatPhaseOffset: (@MainActor () -> Void)? = nil,
        onIncreaseBeatPhaseOffset: (@MainActor () -> Void)? = nil
    ) {
        var all = Self.buildShortcuts(
            actionRouter: actionRouter,
            onToggleFullscreen: onToggleFullscreen,
            onMoveToSecondaryDisplay: onMoveToSecondaryDisplay,
            onToggleOverlay: onToggleOverlay,
            onToggleDebug: onToggleDebug,
            onHandleEsc: onHandleEsc,
            onShowHelp: onShowHelp,
            onShowPlanPreview: onShowPlanPreview
        )
        if let fn = onToggleDiagnosticHold {
            all.append(PlaybackShortcut(
                id: "toggleDiagnosticHold",
                key: "l",
                modifiers: [],
                label: "Toggle diagnostic preset hold",
                category: .developer,
                action: fn
            ))
        }
        if let fn = onDecreaseBeatPhaseOffset {
            all.append(PlaybackShortcut(
                id: "decreaseBeatPhaseOffset",
                key: "[",
                modifiers: [],
                label: "Beat phase −10 ms (calibration)",
                category: .developer,
                action: fn
            ))
        }
        if let fn = onIncreaseBeatPhaseOffset {
            all.append(PlaybackShortcut(
                id: "increaseBeatPhaseOffset",
                key: "]",
                modifiers: [],
                label: "Beat phase +10 ms (calibration)",
                category: .developer,
                action: fn
            ))
        }
        #if DEBUG
        if let fn = onToggleForceSpider {
            all.append(PlaybackShortcut(
                id: "debugForceSpider",
                key: "s",
                modifiers: [.command, .shift, .option],
                label: "Force spider easter egg (debug)",
                category: .developer,
                action: fn
            ))
        }
        // Cmd+] / Cmd+[ : direct preset cycle that bypasses the orchestrator
        // entirely (rotates through PresetLoader.presets ignoring cert state,
        // scoring, and family-repeat penalties). For visual iteration during
        // preset development. Survives only as long as the orchestrator's
        // next preset switch — at the next track boundary or live adaptation,
        // the planned preset takes back over.
        if let next = onDebugNextPreset {
            all.append(PlaybackShortcut(
                id: "debugNextPreset",
                key: "]",
                modifiers: [.command],
                label: "Cycle to next preset (debug)",
                category: .developer,
                action: next
            ))
        }
        if let prev = onDebugPreviousPreset {
            all.append(PlaybackShortcut(
                id: "debugPreviousPreset",
                key: "[",
                modifiers: [.command],
                label: "Cycle to previous preset (debug)",
                category: .developer,
                action: prev
            ))
        }
        #endif
        shortcuts = all
    }
    // swiftlint:enable function_body_length

    // MARK: - Shortcut Table

    // swiftlint:disable:next function_parameter_count function_body_length
    private static func buildShortcuts(
        actionRouter: any PlaybackActionRouter,
        onToggleFullscreen: @escaping @MainActor () -> Void,
        onMoveToSecondaryDisplay: @escaping @MainActor () -> Void,
        onToggleOverlay: @escaping @MainActor () -> Void,
        onToggleDebug: @escaping @MainActor () -> Void,
        onHandleEsc: @escaping @MainActor () -> Void,
        onShowHelp: @escaping @MainActor () -> Void,
        onShowPlanPreview: @escaping @MainActor () -> Void
    ) -> [PlaybackShortcut] {
        [
            // MARK: Playback
            PlaybackShortcut(
                id: "fullscreenToggle",
                key: "f",
                modifiers: [.command],
                label: "Toggle fullscreen",
                category: .playback,
                action: onToggleFullscreen
            ),
            PlaybackShortcut(
                id: "fullscreenSecondary",
                key: "f",
                modifiers: [.command, .shift],
                label: "Move to secondary display",
                category: .playback,
                action: onMoveToSecondaryDisplay
            ),
            PlaybackShortcut(
                id: "overlayToggle",
                key: " ",
                modifiers: [],
                label: "Toggle overlay chrome",
                category: .playback,
                action: onToggleOverlay
            ),
            PlaybackShortcut(
                id: "moodLock",
                key: "m",
                modifiers: [],
                label: "Toggle mood lock",
                category: .playback,
                action: { actionRouter.toggleMoodLock() }
            ),
            PlaybackShortcut(
                id: "endSession",
                key: "\u{1B}", // ESC
                modifiers: [],
                label: "Exit fullscreen / end session",
                category: .playback,
                action: onHandleEsc
            ),
            PlaybackShortcut(
                id: "helpOverlay",
                key: "?",
                modifiers: [.shift],
                label: "Show keyboard shortcuts",
                category: .playback,
                action: onShowHelp
            ),
            PlaybackShortcut(
                id: "planPreview",
                key: "p",
                modifiers: [],
                label: "Preview the plan",
                category: .playback,
                action: onShowPlanPreview
            ),

            // MARK: Live Adaptation
            PlaybackShortcut(
                id: "moreLikeThis",
                key: "+",
                modifiers: [],
                label: "More of this style",
                category: .liveAdaptation,
                action: { actionRouter.moreLikeThis() }
            ),
            PlaybackShortcut(
                id: "lessLikeThis",
                key: "-",
                modifiers: [],
                label: "Less of this style",
                category: .liveAdaptation,
                action: { actionRouter.lessLikeThis() }
            ),
            PlaybackShortcut(
                id: "reshuffleUpcoming",
                key: ".",
                modifiers: [],
                label: "Reshuffle upcoming tracks",
                category: .liveAdaptation,
                action: { actionRouter.reshuffleUpcoming() }
            ),
            PlaybackShortcut(
                id: "presetNudgeNext",
                key: "\u{F703}", // →
                modifiers: [],
                label: "Nudge to next preset style",
                category: .liveAdaptation,
                action: { actionRouter.presetNudge(.next, immediate: false) }
            ),
            PlaybackShortcut(
                id: "presetNudgePrev",
                key: "\u{F702}", // ←
                modifiers: [],
                label: "Nudge to previous preset style",
                category: .liveAdaptation,
                action: { actionRouter.presetNudge(.previous, immediate: false) }
            ),
            PlaybackShortcut(
                id: "presetCutNext",
                key: "\u{F703}", // →
                modifiers: [.shift],
                label: "Cut to next preset immediately",
                category: .liveAdaptation,
                action: { actionRouter.presetNudge(.next, immediate: true) }
            ),
            PlaybackShortcut(
                id: "presetCutPrev",
                key: "\u{F702}", // ←
                modifiers: [.shift],
                label: "Cut to previous preset immediately",
                category: .liveAdaptation,
                action: { actionRouter.presetNudge(.previous, immediate: true) }
            ),
            PlaybackShortcut(
                id: "rePlan",
                key: "r",
                modifiers: [.command],
                label: "Re-plan full session",
                category: .liveAdaptation,
                action: { actionRouter.rePlanSession() }
            ),
            PlaybackShortcut(
                id: "undoAdaptation",
                key: "z",
                modifiers: [.command],
                label: "Undo last adaptation",
                category: .liveAdaptation,
                action: { actionRouter.undoLastAdaptation() }
            ),

            // MARK: Developer
            PlaybackShortcut(
                id: "debugToggle",
                key: "d",
                modifiers: [],
                label: "Toggle debug overlay",
                category: .developer,
                action: onToggleDebug
            )
        ]
    }

    // MARK: - Lookup

    /// Returns the shortcut whose `id` matches, or nil.
    func shortcut(withID id: String) -> PlaybackShortcut? {
        shortcuts.first { $0.id == id }
    }
}
