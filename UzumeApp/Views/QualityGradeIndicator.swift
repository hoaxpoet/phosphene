// QualityGradeIndicator — Colored dot + letter code for signal quality. (U.9 Part C)
//
// Pairs color with an unambiguous letter (G/Y/R/?) so the grade is legible
// to color-blind users even if color distinctions are lost.
//
// Usage:
//   QualityGradeIndicator(quality: snap.quality)
//     .font(.system(size: 11, weight: .bold, design: .monospaced))

import Audio
import SwiftUI

// MARK: - QualityGradeIndicator

/// Signal quality badge combining a color-coded SF Symbol with a letter grade.
///
/// Safe for color-blind users: the letter (G / Y / R / ?) is the primary
/// discriminant; the color reinforces it but is not load-bearing.
struct QualityGradeIndicator: View {

    let quality: SignalQuality

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .foregroundColor(gradeColor)
            Text(letterCode)
                .foregroundColor(gradeColor)
        }
    }

    // MARK: - Private

    private var symbolName: String {
        switch quality {
        case .green:   return "circle.fill"
        case .yellow:  return "triangle.fill"
        case .red:     return "square.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var gradeColor: Color {
        switch quality {
        case .green:   return .green
        case .yellow:  return .yellow
        case .red:     return .red
        case .unknown: return .white.opacity(0.5)
        }
    }

    private var letterCode: String {
        switch quality {
        case .green:   return "G"
        case .yellow:  return "Y"
        case .red:     return "R"
        case .unknown: return "?"
        }
    }
}
