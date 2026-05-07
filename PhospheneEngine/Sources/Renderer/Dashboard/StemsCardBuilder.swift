// StemsCardBuilder — Maps a `StemFeatures` snapshot to a `DashboardCardLayout`
// for the STEMS card (DASH.4).
//
// Pure function: no Metal, no allocations beyond the resulting layout.
// Safe to call every frame. Wiring into `RenderPipeline` / `PlaybackView`
// is DASH.6 scope, not DASH.4.
//
// Row order (.impeccable Beat-panel precedent — percussion first):
//   DRUMS / BASS / VOCALS / OTHER.
//
// All four rows are `.bar` (signed-from-centre) with range −1.0 ... 1.0.
// `*EnergyRel` (MV-1 / D-026) is centred at 0 with typical envelope ±0.5;
// the wider range gives headroom for loud transients without clipping.
// Positive deviation fills right of centre (kick = louder than AGC average);
// negative fills left (duck = quieter than average); zero draws no fill —
// the stable "absence-of-signal" state.
//
// Uniform `Color.coral` across all four rows in v1 (D-084). Per-stem palette
// tuning is reserved for a DASH.4.1 amendment if the artifact eyeball flags
// monotony — direction (left vs right of centre) is the load-bearing signal,
// not colour.
//
// No clamping at the builder layer: `.bar` row variant clamps to `range`
// defensively in `drawBarFill`. Test (e) regression-locks this.

import CoreGraphics
import Shared

#if canImport(AppKit)
import AppKit
#endif

/// Maps a `StemFeatures` snapshot to a `DashboardCardLayout` for the STEMS card.
public struct StemsCardBuilder: Sendable {

    public init() {}

    public func build(
        from stems: StemFeatures,
        width: CGFloat = 280
    ) -> DashboardCardLayout {
        let drums = makeRow(label: "DRUMS", value: stems.drumsEnergyRel)
        let bass = makeRow(label: "BASS", value: stems.bassEnergyRel)
        let vocals = makeRow(label: "VOCALS", value: stems.vocalsEnergyRel)
        let other = makeRow(label: "OTHER", value: stems.otherEnergyRel)

        return DashboardCardLayout(
            title: "STEMS",
            rows: [drums, bass, vocals, other],
            width: width
        )
    }

    private func makeRow(label: String, value: Float) -> DashboardCardLayout.Row {
        .bar(
            label: label,
            value: value,
            valueText: String(format: "%+.2f", value),
            fillColor: DashboardTokens.Color.coral,
            range: -1.0 ... 1.0
        )
    }
}
