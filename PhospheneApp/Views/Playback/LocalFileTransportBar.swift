// LocalFileTransportBar — LF.5.fix D-LF5-3 + GAP C redesign (2026-05-28).
//
// Hover-revealed transport for local-file sessions. Per .impeccable.md design
// context: coral is action (the play/pause focal disc); purple is ambient
// presence (soft purple-tinted shadow behind the bar); skip/stop glyphs sit
// at `--text-muted`, brighten to `--text-body` on hover. Custom geometric
// Shape glyphs replace SF Symbols so the bar stops reading as Spotify
// chrome. Solid `--surface-raised` replaces `.ultraThinMaterial` — kills the
// glassmorphism AI tell. The coral disc is the 10% focal weight per the
// 60-30-10 hierarchy rule.
//
// Brand colour values come from `DashboardTokens` (Shared module) which
// already maps the `.impeccable.md` OKLCH spec to sRGB NSColors — single
// source of truth for the palette across SwiftUI chrome.

import Shared
import SwiftUI

// MARK: - LocalFileTransportBar

struct LocalFileTransportBar: View {

    static let accessibilityID = "phosphene.playback.lfTransport"

    let isPaused: Bool
    let onStop: () -> Void
    let onPrev: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            MutedTransportButton(
                glyph: AnyShape(StopGlyph()),
                tooltip: String(localized: "playback.transport.stop.tooltip"),
                a11yLabel: String(localized: "playback.transport.stop.a11y"),
                action: onStop
            )
            MutedTransportButton(
                glyph: AnyShape(PrevGlyph()),
                tooltip: String(localized: "playback.transport.prev.tooltip"),
                a11yLabel: String(localized: "playback.transport.prev.a11y"),
                action: onPrev
            )
            PlayPauseTransportButton(
                isPaused: isPaused,
                action: onPlayPause,
                tooltip: String(localized: isPaused
                    ? "playback.transport.play.tooltip"
                    : "playback.transport.pause.tooltip"),
                a11yLabel: String(localized: isPaused
                    ? "playback.transport.play.a11y"
                    : "playback.transport.pause.a11y")
            )
            MutedTransportButton(
                glyph: AnyShape(NextGlyph()),
                tooltip: String(localized: "playback.transport.next.tooltip"),
                a11yLabel: String(localized: "playback.transport.next.a11y"),
                action: onNext
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: DashboardTokens.Color.surfaceRaised))
                .shadow(
                    color: Color(nsColor: DashboardTokens.Color.purpleGlow).opacity(0.55),
                    radius: 28,
                    x: 0,
                    y: 0
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: DashboardTokens.Color.border).opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}

// MARK: - PlayPauseTransportButton (coral disc — primary action)

private struct PlayPauseTransportButton: View {

    let isPaused: Bool
    let action: () -> Void
    let tooltip: String
    let a11yLabel: String

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Group {
                if isPaused {
                    PlayGlyph().fill(Color.white)
                } else {
                    PauseGlyph().fill(Color.white)
                }
            }
            .frame(width: 18, height: 18)
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(Color(nsColor: DashboardTokens.Color.coral))
                    .brightness(isHovered ? 0.06 : 0)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .help(tooltip)
        .accessibilityLabel(a11yLabel)
    }
}

// MARK: - MutedTransportButton (skip / stop — muted, no background until hover)

private struct MutedTransportButton: View {

    let glyph: AnyShape
    let tooltip: String
    let a11yLabel: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            glyph
                .fill(Color(nsColor: isHovered
                    ? DashboardTokens.Color.textBody
                    : DashboardTokens.Color.textMuted))
                .frame(width: 16, height: 16)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.06 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .help(tooltip)
        .accessibilityLabel(a11yLabel)
    }
}

// MARK: - Custom geometric glyphs

/// Filled square. ◼
private struct StopGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let inset = rect.width * 0.18
            path.addRect(rect.insetBy(dx: inset, dy: inset))
        }
    }
}

/// Right-pointing equilateral triangle. ▶
/// Apex shifted slightly right to optically centre the mass inside the disc.
private struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let inset = rect.width * 0.16
            let region = rect.insetBy(dx: inset, dy: inset * 0.6)
            let opticalOffset = region.width * 0.06    // mass-balance shift
            path.move(to: CGPoint(x: region.minX + opticalOffset, y: region.minY))
            path.addLine(to: CGPoint(x: region.maxX, y: region.midY))
            path.addLine(to: CGPoint(x: region.minX + opticalOffset, y: region.maxY))
            path.closeSubpath()
        }
    }
}

/// Two vertical bars. ❚❚
private struct PauseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let insetY = rect.height * 0.16
            let region = rect.insetBy(dx: 0, dy: insetY)
            let barWidth = region.width * 0.24
            let gap = region.width * 0.18
            let leftX = region.midX - gap / 2 - barWidth
            let rightX = region.midX + gap / 2
            path.addRect(CGRect(x: leftX, y: region.minY, width: barWidth, height: region.height))
            path.addRect(CGRect(x: rightX, y: region.minY, width: barWidth, height: region.height))
        }
    }
}

/// Left-pointing triangle + vertical bar on its left. ⏮
private struct PrevGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let inset = rect.width * 0.14
            let region = rect.insetBy(dx: inset, dy: inset)
            let barWidth = region.width * 0.18
            // Vertical bar on the left
            path.addRect(CGRect(x: region.minX, y: region.minY, width: barWidth, height: region.height))
            // Triangle pointing left; right edge anchors at region.maxX
            let triLeftEdge = region.minX + barWidth + region.width * 0.06
            path.move(to: CGPoint(x: region.maxX, y: region.minY))
            path.addLine(to: CGPoint(x: triLeftEdge, y: region.midY))
            path.addLine(to: CGPoint(x: region.maxX, y: region.maxY))
            path.closeSubpath()
        }
    }
}

/// Right-pointing triangle + vertical bar on its right. ⏭
private struct NextGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let inset = rect.width * 0.14
            let region = rect.insetBy(dx: inset, dy: inset)
            let barWidth = region.width * 0.18
            // Triangle pointing right; left edge anchors at region.minX
            let triRightEdge = region.maxX - barWidth - region.width * 0.06
            path.move(to: CGPoint(x: region.minX, y: region.minY))
            path.addLine(to: CGPoint(x: triRightEdge, y: region.midY))
            path.addLine(to: CGPoint(x: region.minX, y: region.maxY))
            path.closeSubpath()
            // Vertical bar on the right
            path.addRect(CGRect(x: region.maxX - barWidth, y: region.minY, width: barWidth, height: region.height))
        }
    }
}
