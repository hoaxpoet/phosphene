// StemsCardBuilder — Maps a `StemEnergyHistory` snapshot to a
// `DashboardCardLayout` for the STEMS card (DASH.7 — supersedes DASH.4's
// signed-from-centre `.bar` design after Matt's live-toggle review found the
// bars didn't read rhythmic separation across stems clearly).
//
// Pure function: no Metal, no allocations beyond the resulting layout.
// Safe to call every frame.
//
// Row order (.impeccable Beat-panel precedent — percussion first):
//   DRUMS / BASS / VOCALS / OTHER.
//
// All four rows are `.timeseries` with range −1.0 ... 1.0 (matches the
// envelope of `*EnergyRel` from MV-1 / D-026: typical ±0.5, headroom for
// loud transients). The valueText shows the most recent sample in the
// `%+.2f` Milkdrop-convention signed format.
//
// Uniform `Color.coral` v1 — the rhythm pattern across time carries the
// signal, not per-stem hue. Per-stem palette tuning reserved for a future
// amendment if monotony reads on the live review.
//
// Empty history (no samples yet) produces empty `samples: []` rows with
// valueText `—` — the timeseries renderer draws nothing, the chrome row
// stays present (stable absence-of-information surface).

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

/// Maps a `StemEnergyHistory` snapshot to a `DashboardCardLayout` for the STEMS card.
public struct StemsCardBuilder: Sendable {

    public init() {}

    public func build(
        from history: StemEnergyHistory,
        width: CGFloat = 280
    ) -> DashboardCardLayout {
        let drums = makeRow(label: "DRUMS", samples: history.drums)
        let bass = makeRow(label: "BASS", samples: history.bass)
        let vocals = makeRow(label: "VOCALS", samples: history.vocals)
        let other = makeRow(label: "OTHER", samples: history.other)

        return DashboardCardLayout(
            title: "STEMS",
            rows: [drums, bass, vocals, other],
            width: width
        )
    }

    private func makeRow(label: String, samples: [Float]) -> DashboardCardLayout.Row {
        let valueText: String
        if let last = samples.last {
            valueText = String(format: "%+.2f", last)
        } else {
            valueText = "—"
        }
        return .timeseries(
            label: label,
            samples: samples,
            range: -1.0 ... 1.0,
            valueText: valueText,
            fillColor: DashboardTokens.Color.coral
        )
    }
}
