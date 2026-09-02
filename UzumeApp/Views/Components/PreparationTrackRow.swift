// PreparationTrackRow — one track in the detailed preparation view. (DS.4)
//
// Extracted from TrackPreparationRow. Before a track is heard the row reports the
// stage it is in; once Uzume has heard it, the row reports what it heard — tempo, key,
// mood, and a compact stem balance. Per-row failures (`previewNotFound`,
// `stemSeparationFailed`) are `.inlineOnRow` and render here; they have nowhere else
// to go. The accessible combined label/value contract is preserved.
//
// Surprise model: this shows what Uzume HEARD in music the listener chose — never
// which preset a track gets, nor what is coming next.

import Session
import Shared
import SwiftUI

// MARK: - PreparationTrackRow

/// One row in the detailed preparation list.
struct PreparationTrackRow: View {

    let row: RowData
    /// What Uzume heard, once the track is `.ready`. `nil` before that.
    let profile: TrackProfile?

    var body: some View {
        HStack(spacing: 12) {
            PreparationStatusIndicator(status: row.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(UzumeAppColor.textPrimary)
                    .lineLimit(1)

                Text(row.artist)
                    .font(.caption)
                    .foregroundColor(UzumeAppColor.textTertiary)
                    .lineLimit(1)

                Text(caption)
                    .font(.caption2)
                    .foregroundColor(captionColor)

                if case .downloading(let progress) = row.status, progress >= 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: UzumeAppColor.textTertiary))
                        .frame(height: 2)
                        .padding(.top, 2)
                }
            }

            Spacer()

            if let heard {
                StemBalanceMark(balance: heard.stemEnergyBalance)
            } else if let eta = row.etaSeconds, row.status.isInFlight {
                Text(etaText(eta))
                    .font(.caption2)
                    .foregroundColor(UzumeAppColor.textDisabled)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - What was heard

    /// The profile, only once the track is actually ready.
    private var heard: TrackProfile? {
        row.status == .ready ? profile : nil
    }

    /// "118 BPM · A minor · calm" — the discoveries, for a heard track.
    static func discoveries(_ profile: TrackProfile) -> String {
        var parts: [String] = []
        if let bpm = profile.bpm, bpm > 0 {
            parts.append(String(format: String(localized: "preparation.track.bpm"), Int(bpm.rounded())))
        }
        if let key = profile.key, !key.isEmpty {
            parts.append(prettyKey(key))
        }
        parts.append(moodWord(profile.mood))
        return parts.joined(separator: " \u{00B7} ")
    }

    /// "led by drums" — which stem carries the track.
    static func leadingStem(_ balance: StemFeatures) -> String {
        let stems: [(Float, String)] = [
            (balance.vocalsEnergy, "preparation.track.stem.vocals"),
            (balance.drumsEnergy, "preparation.track.stem.drums"),
            (balance.bassEnergy, "preparation.track.stem.bass"),
            (balance.otherEnergy, "preparation.track.stem.other"),
        ]
        guard let lead = stems.max(by: { $0.0 < $1.0 }), lead.0 > 0 else { return "" }
        let name = String(localized: String.LocalizationValue(lead.1))
        return String(format: String(localized: "preparation.track.stems_led_by"), name)
    }

    /// One word for the mood quadrant. Heard, not predicted.
    static func moodWord(_ mood: EmotionalState) -> String {
        switch mood.quadrant {
        case .happy: return String(localized: "preparation.track.mood.bright")
        case .calm:  return String(localized: "preparation.track.mood.calm")
        case .tense: return String(localized: "preparation.track.mood.restless")
        case .sad:   return String(localized: "preparation.track.mood.wistful")
        }
    }

    /// "F# minor" → "F♯ minor", "Db major" → "D♭ major".
    static func prettyKey(_ key: String) -> String {
        var pretty = key.replacingOccurrences(of: "#", with: "\u{266F}")
        if pretty.count >= 2, pretty.first.map({ ("A"..."G").contains(String($0)) }) == true,
           pretty.dropFirst().first == "b" {
            pretty.replaceSubrange(pretty.index(after: pretty.startIndex)...pretty.index(after: pretty.startIndex),
                                   with: "\u{266D}")
        }
        return pretty
    }

    // MARK: - Private

    private var caption: String {
        if let heard { return Self.discoveries(heard) }
        switch row.status {
        case .queued:
            return String(localized: "preparation.track.queued")
        case .resolving:
            return String(localized: "preparation.track.resolving")
        case .downloading(let pct) where pct < 0:
            return String(localized: "preparation.track.downloading")
        case .downloading(let pct):
            return "\(String(localized: "preparation.track.downloading")) — \(Int(pct * 100))%"
        case .analyzing(let stage):
            switch stage {
            case .stemSeparation, .mir, .beatGrid:
                return String(localized: "preparation.track.analyzing")
            case .caching:
                return String(localized: "preparation.track.caching")
            }
        case .ready:
            return String(localized: "preparation.track.ready")
        case .partial(let reason), .failed(let reason):
            // "Skipped — <reason>" per UX_SPEC §9.3 inline-row copy.
            return "Skipped \u{2014} \(reason)"
        }
    }

    private var captionColor: Color {
        switch row.status {
        case .ready:   return heard == nil ? UzumeAppColor.success : UzumeAppColor.textSecondary
        case .partial: return UzumeAppColor.warning
        case .failed:  return UzumeAppColor.danger
        default:       return UzumeAppColor.textDisabled
        }
    }

    var accessibilityLabel: String {
        if let heard {
            let lead = Self.leadingStem(heard.stemEnergyBalance)
            let tail = lead.isEmpty ? "" : ", \(lead)"
            return "\(row.title) by \(row.artist). \(Self.discoveries(heard))\(tail)"
        }
        return "\(row.title) by \(row.artist). \(caption)"
    }

    var accessibilityValue: String {
        if case .downloading(let pct) = row.status, pct >= 0 {
            return "\(Int(pct * 100)) percent"
        }
        return ""
    }

    private func etaText(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "~\(Int(seconds))s"
        }
        return "~\(Int(seconds / 60))m"
    }
}

// MARK: - StemBalanceMark

/// Four thin bars — vocals, drums, bass, other — each in its own spectrum colour so
/// the balance reads at a glance. Decorative: the row's label carries the lead stem.
private struct StemBalanceMark: View {
    let balance: StemFeatures

    var body: some View {
        let energies = [balance.vocalsEnergy, balance.drumsEnergy, balance.bassEnergy, balance.otherEnergy]
        let peak = max(0.001, energies.max() ?? 0)
        let colours = [UzumeAppColor.violet, UzumeAppColor.ember, UzumeAppColor.gold, UzumeAppColor.cyan]
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(colours[index])
                    .frame(width: 4, height: 3 + 11 * CGFloat(energies[index] / peak))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
