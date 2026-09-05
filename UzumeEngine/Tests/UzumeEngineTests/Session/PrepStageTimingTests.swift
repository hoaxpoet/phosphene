// PrepStageTimingTests — PREP.1 measurement scaffolding.
//
// Three risks worth pinning, and nothing else. The unit conversion is the same
// off-by-1e3 that PREPPERF.1's `PrepTimingTests` existed to guard: a timing
// artifact that silently reports seconds as milliseconds is worse than no
// artifact, because every conclusion drawn from it is wrong by 1000×. The
// backfill is what makes `ms_per_audio_s` meaningful on the stages that run
// before the decode knows the track's duration. And the disabled probe has to
// stay genuinely inert — it is on the shipping preparation path.

import Foundation
import Testing
@testable import Shared

@Suite("PREP.1 preparation stage timing")
struct PrepStageTimingTests {

    @Test("durations are recorded in milliseconds, not seconds")
    func recordsMilliseconds() throws {
        let sink = PrepStageSink(destination: URL(fileURLWithPath: "/dev/null"))
        let probe = PrepStageProbe(sink: sink, track: "t.flac", audioSeconds: 100)

        probe.measure("slept") { Thread.sleep(forTimeInterval: 0.05) }

        let row = try #require(sink.snapshot.first)
        #expect(row.wallMs > 40 && row.wallMs < 400, "50 ms should read as ~50, not 0.05 or 50000")
        #expect(row.audioSeconds == 100)
    }

    @Test("a disabled probe records nothing and still returns the body's value")
    func disabledProbeIsInert() {
        let probe = PrepStageProbe.disabled
        #expect(probe.isEnabled == false)
        #expect(probe.measure("noop") { 42 } == 42)
    }

    @Test("stages measured before the decode get the track's duration backfilled")
    func backfillsAudioSeconds() {
        let sink = PrepStageSink(destination: URL(fileURLWithPath: "/dev/null"))
        let probe = PrepStageProbe(sink: sink, track: "t.flac")

        probe.measure(PrepStage.contentHash) { }          // duration not yet known → 0
        let known = probe.notingAudioSeconds(240)
        known.measure(PrepStage.decode) { }

        #expect(sink.snapshot.count == 2)
        #expect(sink.snapshot.allSatisfy { $0.audioSeconds == 240 })
    }

    @Test("backfill leaves other tracks alone")
    func backfillIsPerTrack() {
        let sink = PrepStageSink(destination: URL(fileURLWithPath: "/dev/null"))
        PrepStageProbe(sink: sink, track: "a.flac").measure(PrepStage.contentHash) { }
        PrepStageProbe(sink: sink, track: "b.flac").measure(PrepStage.contentHash) { }

        _ = PrepStageProbe(sink: sink, track: "a.flac").notingAudioSeconds(120)

        let byTrack = Dictionary(uniqueKeysWithValues: sink.snapshot.map { ($0.track, $0.audioSeconds) })
        #expect(byTrack["a.flac"] == 120)
        #expect(byTrack["b.flac"] == 0)
    }

    @Test("csv carries a header and one line per row, with cores and per-audio-second cost")
    func csvShape() throws {
        let sink = PrepStageSink(destination: URL(fileURLWithPath: "/dev/null"))
        sink.append(PrepStageRow(
            track: "quoted \"name\".flac", stage: PrepStage.stemSeries,
            wallMs: 2000, cpuMs: 1000, audioSeconds: 100))

        let lines = sink.csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == "track,stage,wall_ms,cpu_ms,cpu_cores,audio_s,ms_per_audio_s")
        // 1000 ms CPU over 2000 ms wall = half a core; 2000 ms over 100 s of audio = 20 ms/s.
        #expect(lines[1].hasSuffix(",0.50,100.00,20.00"))
        #expect(lines[1].hasPrefix("\"quoted \"\"name\"\".flac\","), "commas in titles must not split columns")
    }
}
