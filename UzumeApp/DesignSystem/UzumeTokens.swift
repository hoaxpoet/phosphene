// UzumeTokens.swift — VENDORED COPY. Do not edit.
//
//   Source repo:   github.com/hoaxpoet/uzume-site
//   Source path:   DesignSystem/SwiftUI/Sources/UzumeDesignSystem/UzumeTokens.swift
//   Source commit: 03d5478
//   SHA-256:       3045c4695fb6cd7bcf47f75ac4adee132ab9ff7a2da97979bd1238a66afe07db
//
// Everything below this header is byte-identical to upstream and is verified by
// `Scripts/check_design_token_drift.sh`. D-228 makes uzume-site the design-system
// source of truth: the app consumes it and never authors it. App-only semantic
// roles live in `UzumeTokens+App.swift` — never add them here, or the drift check
// fails and the provenance claim stops being true.
//
// --- BEGIN VENDORED CONTENT (uzume-site@03d5478) ---
import AppKit
import SwiftUI

public enum UzumeColor {
    public static let canvas = Color(nsColor: .windowBackgroundColor)
    public static let surface = Color(nsColor: .controlBackgroundColor)
    public static let textPrimary = Color(nsColor: .labelColor)
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)
    public static let line = Color(nsColor: .separatorColor)
    public static let accent = adaptive(
        light: NSColor(red: 0.404, green: 0.325, blue: 0.843, alpha: 1),
        dark: NSColor(red: 0.498, green: 0.416, blue: 1.000, alpha: 1)
    )
    public static let violet = Color(red: 0.498, green: 0.416, blue: 1.000)
    public static let cyan = Color(red: 0.216, green: 0.839, blue: 0.753)
    public static let gold = Color(red: 0.961, green: 0.784, blue: 0.298)
    public static let ember = Color(red: 1.000, green: 0.420, blue: 0.290)
    public static let success = Color(nsColor: .systemGreen)
    public static let warning = Color(nsColor: .systemYellow)
    public static let danger = Color(nsColor: .systemRed)
    public static let information = Color(nsColor: .systemBlue)

    public static let performedLight = LinearGradient(
        stops: [
            .init(color: violet, location: 0),
            .init(color: cyan, location: 0.38),
            .init(color: gold, location: 0.68),
            .init(color: ember, location: 1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

public enum UzumeSpace {
    public static let x1: CGFloat = 4
    public static let x2: CGFloat = 8
    public static let x3: CGFloat = 12
    public static let x4: CGFloat = 16
    public static let x6: CGFloat = 24
    public static let x8: CGFloat = 32
    public static let x12: CGFloat = 48
}

public enum UzumeRadius {
    public static let compact: CGFloat = 6
    public static let standard: CGFloat = 10
    public static let prominent: CGFloat = 14
}

public extension View {
    func uzumeTint() -> some View { tint(UzumeColor.accent) }
}
