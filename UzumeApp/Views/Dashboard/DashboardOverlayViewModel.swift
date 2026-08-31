// DashboardOverlayViewModel — Subscribes to engine snapshots, throttles to
// ~30 Hz, maintains stem-energy history, and publishes the three card
// `DashboardCardLayout` values consumed by `DashboardOverlayView` (DASH.7).
//
// The view model owns:
//   • A Combine subscription on `VisualizerEngine.$dashboardSnapshot`,
//     throttled with `.throttle(for: .milliseconds(33))` (~30 Hz).
//   • An in-memory ring per stem (drums / bass / vocals / other) of recent
//     `*EnergyRel` values, sized at `StemEnergyHistory.capacity` (240 samples).
//   • The latest `DashboardCardLayout` outputs from each builder, exposed
//     as `@Published var layouts: [DashboardCardLayout]`.

import Combine
import Foundation
import Renderer
import Shared

@MainActor
final class DashboardOverlayViewModel: ObservableObject {

    // MARK: - Published

    /// Three card layouts in display order: BEAT / STEMS / PERF.
    /// Replaces wholesale on each throttled snapshot tick.
    @Published private(set) var layouts: [DashboardCardLayout] = []

    // MARK: - Private state

    private let beatBuilder = BeatCardBuilder()
    private let stemsBuilder = StemsCardBuilder()
    private let perfBuilder = PerfCardBuilder()
    private var cancellables: Set<AnyCancellable> = []
    private var stemHistory = MutableStemHistory()

    // MARK: - Public throttle (overridable for tests)

    static let throttleInterval: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(33)

    // MARK: - Init

    /// Production init — subscribes to the engine's `$dashboardSnapshot`.
    init(snapshotPublisher: AnyPublisher<DashboardSnapshot?, Never>) {
        snapshotPublisher
            .compactMap { $0 }
            .throttle(
                for: Self.throttleInterval,
                scheduler: DispatchQueue.main,
                latest: true
            )
            .sink { [weak self] snapshot in
                self?.apply(snapshot)
            }
            .store(in: &cancellables)
    }

    /// Test seam — apply a snapshot synchronously without going through the
    /// throttled subscription. Tests use this to drive the view model
    /// deterministically.
    func ingestForTest(_ snapshot: DashboardSnapshot) {
        apply(snapshot)
    }

    // MARK: - Apply

    private func apply(_ snapshot: DashboardSnapshot) {
        stemHistory.append(stems: snapshot.stems)
        let history = stemHistory.snapshot()
        let cardWidth: CGFloat = 280
        layouts = [
            beatBuilder.build(from: snapshot.beat, width: cardWidth),
            stemsBuilder.build(from: history, width: cardWidth),
            perfBuilder.build(from: snapshot.perf, width: cardWidth)
        ]
    }
}

// MARK: - MutableStemHistory

/// Internal CPU ring buffer for recent stem-energy samples. Held by the
/// view model; snapshotted into the immutable `StemEnergyHistory` value
/// type at each throttled redraw.
private struct MutableStemHistory {
    private var drums: [Float] = []
    private var bass: [Float] = []
    private var vocals: [Float] = []
    private var other: [Float] = []

    private let capacity = StemEnergyHistory.capacity

    mutating func append(stems: StemFeatures) {
        Self.push(&drums, value: stems.drumsEnergyRel, capacity: capacity)
        Self.push(&bass, value: stems.bassEnergyRel, capacity: capacity)
        Self.push(&vocals, value: stems.vocalsEnergyRel, capacity: capacity)
        Self.push(&other, value: stems.otherEnergyRel, capacity: capacity)
    }

    private static func push(_ array: inout [Float], value: Float, capacity: Int) {
        if array.count == capacity {
            array.removeFirst()
        }
        array.append(value)
    }

    func snapshot() -> StemEnergyHistory {
        StemEnergyHistory(drums: drums, bass: bass, vocals: vocals, other: other)
    }
}
