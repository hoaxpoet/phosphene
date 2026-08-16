// StaveReplay — the session-CSV loader Stave's harnesses replay real music through.
//
// What is left of CHR.2's `StaveLookSpike`. That spike's job was a VERDICT, and it delivered
// one (`docs/diagnostics/CHR2_LOOK_SPIKE_2026-08-14.md`): band-driven geometry passed,
// stem-driven colour failed, and Matt re-scoped the preset at D-216. CHR.3 then lifted the
// spike's geometry into the production `Renderer/Geometry/StaveTrace.swift`, carrying its
// four fixed defects across as comments, so the spike class itself was deleted rather than
// left to shadow the production type of the same name.
//
// This loader survives because both CHR.3 harnesses need it: `StaveFieldTintSpike` (the D4
// field-tint gate) and `StaveRenderHarnessTests` (the production-path render).
//
// ⚠ Written out explicitly rather than reusing `SessionReplayHarness`: that harness is
// ray-march-only and does not map `midHigh` / `highMid` / `high` at all, so replaying the
// melodic trace through it would feed ZERO and the trace would read as dead — the exact
// instrument failure recorded against Faraday.
//
// ⚠ Session slices fed to this loader must be written with LF line endings. Swift treats
// "\r\n" as a SINGLE `Character`, so `split(whereSeparator: { $0 == "\n" || $0 == "\r" })`
// does not split a CRLF file at all and this returns zero frames (CHR.3, first slice run).

import Foundation
@testable import Renderer
@testable import Shared

enum StaveSpikeError: Error { case functionNotFound, bufferAllocationFailed }

// MARK: - Replay

/// One `features.csv` + `stems.csv` frame, carrying ONLY the fields this spike drives from.
/// Written out explicitly rather than reusing `SessionReplayHarness`: that harness is
/// ray-march-only and does not map `midHigh` / `highMid` / `high` at all, so replaying the
/// melodic trace through it would have fed it ZERO and the trace would have read as dead —
/// the exact instrument failure recorded against Faraday.
struct StaveReplayFrame {
    var features = FeatureVector(time: 0, deltaTime: 1.0 / 60.0, accumulatedAudioTime: 0)
    var stems = StemFeatures.zero
    var track = ""
}

enum StaveReplay {

    static func load(session: URL, aspect: Float) -> [StaveReplayFrame] {
        guard let featureText = try? String(contentsOf: session.appendingPathComponent("features.csv"),
                                            encoding: .utf8),
              let stemText = try? String(contentsOf: session.appendingPathComponent("stems.csv"),
                                         encoding: .utf8) else { return [] }
        let bounds = trackBounds(session.appendingPathComponent("session.log"))
        let featureLines = featureText.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        let stemLines = stemText.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let featureHeader = featureLines.first, let stemHeader = stemLines.first else { return [] }
        let featureIndex = columnIndex(featureHeader)
        let stemIndex = columnIndex(stemHeader)

        var out: [StaveReplayFrame] = []
        out.reserveCapacity(featureLines.count)
        for (featureLine, stemLine) in zip(featureLines.dropFirst(), stemLines.dropFirst()) {
            let ff = featureLine.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let sf = stemLine.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard ff.count > 20, sf.count > 20 else { continue }
            func f(_ name: String) -> Float { value(ff, featureIndex, name) }
            func s(_ name: String) -> Float { value(sf, stemIndex, name) }

            var frame = StaveReplayFrame()
            frame.features = FeatureVector(time: f("time"), deltaTime: f("deltaTime"),
                                           accumulatedAudioTime: f("accumulatedAudioTime"))
            frame.features.bass = f("bass"); frame.features.mid = f("mid"); frame.features.treble = f("treble")
            frame.features.subBass = f("subBass"); frame.features.lowBass = f("lowBass")
            frame.features.midHigh = f("midHigh"); frame.features.highMid = f("highMid")
            frame.features.high = f("high")
            frame.features.beatPhase01 = f("beatPhase01")
            frame.features.aspectRatio = aspect
            frame.stems.drumsEnergyRel = s("drumsEnergyRel"); frame.stems.bassEnergyRel = s("bassEnergyRel")
            frame.stems.vocalsEnergyRel = s("vocalsEnergyRel"); frame.stems.otherEnergyRel = s("otherEnergyRel")
            // Raw per-stem energy, for the CHR.3 field-tint spike's share drive. The `Rel`
            // columns above are each centred on their OWN 10 s EMA (StemAnalyzer), which is
            // why they cannot carry sustained section identity — see StaveFieldTintSpike.
            frame.stems.drumsEnergy = s("drumsEnergy"); frame.stems.bassEnergy = s("bassEnergy")
            frame.stems.vocalsEnergy = s("vocalsEnergy"); frame.stems.otherEnergy = s("otherEnergy")
            frame.track = track(at: f("wallclock_s"), bounds)
            out.append(frame)
        }
        return out
    }

    private static func columnIndex(_ header: Substring) -> [String: Int] {
        var index: [String: Int] = [:]
        for (i, name) in header.split(separator: ",").map(String.init).enumerated() { index[name] = i }
        return index
    }

    private static func value(_ fields: [String], _ index: [String: Int], _ name: String) -> Float {
        guard let i = index[name], i < fields.count else { return 0 }
        return Float(fields[i]) ?? 0
    }

    /// Track boundaries, so a per-track verdict is a per-track render. `wallclock_s` is
    /// CFAbsoluteTime; the log stamps ISO-8601 UTC.
    private static func trackBounds(_ log: URL) -> [(Float, String)] {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var out: [(Float, String)] = []
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard line.contains("trackChangeCallback FIRED"),
                  let close = line.firstIndex(of: "]"),
                  let start = line.range(of: "current='"),
                  let end = line.range(of: "' currentArtist=") else { continue }
            let stamp = String(line[line.index(after: line.startIndex)..<close])
            guard let date = formatter.date(from: stamp) else { continue }
            out.append((Float(date.timeIntervalSinceReferenceDate), String(line[start.upperBound..<end.lowerBound])))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    private static func track(at wallclock: Float, _ bounds: [(Float, String)]) -> String {
        var name = ""
        for (time, title) in bounds where time <= wallclock { name = title }
        return name
    }
}
