import Testing
import Foundation
@testable import Renderer
@testable import Shared
@Suite("Temp VL perf")
struct TempVLPerf {
    @MainActor @Test("vl")
    func t() throws {
        guard let dims = ProcessInfo.processInfo.environment["VL_PERF"] else { return }
        let p = dims.split(separator: "x").compactMap { Int($0) }
        guard p.count == 2 else { return }
        var f: [FeatureVector] = []; var s: [StemFeatures] = []
        for i in 0..<30 {
            var v = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: Float(i)/60, deltaTime: 1.0/60)
            v.trackElapsedS = Float(i)/60; v.barPhase01 = Float(i % 60)/60; v.beatsPerBar = 4
            v.aspectRatio = Float(p[0]) / Float(p[1])
            f.append(v)
            var st = StemFeatures(); st.drumsEnergy = 0.3; st.bassEnergy = 0.3; st.otherEnergy = 0.2; s.append(st)
        }
        let h = MultiPassRenderHarness(width: p[0], height: p[1])
        _ = try h.render(preset: "Volumetric Lithograph", features: f, stems: s, settle: 4) { _ in 0 }
        var best = Double.infinity
        for _ in 0..<3 {
            let t0 = ProcessInfo.processInfo.systemUptime
            _ = try h.render(preset: "Volumetric Lithograph", features: f, stems: s, settle: 0) { _ in 0 }
            best = min(best, (ProcessInfo.processInfo.systemUptime - t0) * 1000 / 30)
        }
        print(String(format: "[vl-perf] %.2f ms/frame", best))
    }
}
