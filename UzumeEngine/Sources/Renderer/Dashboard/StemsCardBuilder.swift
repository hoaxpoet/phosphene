// StemsCardBuilder — Maps a `StemEnergyHistory` snapshot to a
// `DashboardCardLayout` for the STEMS card.
//
// Pure function: no Metal, no allocations beyond the resulting layout.
// Safe to call every frame.
//
// Row order (.impeccable Beat-panel precedent — percussion first):
//   DRUMS / BASS / VOCALS / OTHER.
//
// All four rows are `.timeseries` with range −1.0 ... 1.0. Each row's
// most-recent sample is the rightmost pixel of the sparkline; no separate
// numeric readout is emitted (the sparkline IS the readout — Sakamoto-liner-
// notes principle from `.impeccable.md`).
//
// Colour: `Color.teal` per the project's semantic-colour rule:
//   Teal = analytical/precision — preparation progress, MIR data, **stem indicators**.
// Coral was used in DASH.4-7; corrected to teal in DASH.7.1 brand-alignment
// pass (D-088).

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
        .timeseries(
            label: label,
            samples: samples,
            range: -1.0 ... 1.0,
            valueText: "",                        // sparkline is the value (D-088)
            fillColor: DashboardTokens.Color.teal // stem indicators are teal (D-088)
        )
    }
}
