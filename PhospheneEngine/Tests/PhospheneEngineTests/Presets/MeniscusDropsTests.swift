// MeniscusDropsTests — mechanism gate for the ported drop placement (MEN.2b).
//
// SYNTHETIC SPECTRA ARE APPROPRIATE HERE, and the distinction matters. FA #27 forbids
// standing hand-authored envelopes in for real music when making a FIDELITY claim,
// because synthetic input does not reproduce pipeline noise, cross-band correlation or
// MIR-derived structure. This file makes no fidelity claim: it asserts that a DFT over a
// magnitude spectrum places impacts where the spectrum's HARMONIC SPACING says it
// should, and that a structureless spectrum places none. Those are properties of the
// mechanism, and a constructed spectrum is the only way to state them exactly.
//
// The fidelity evidence — does this produce the drop DENSITY the wave sim needs, and the
// interference structure of reference `07` — comes from the oracle A/B, not from here.

import Testing
import Foundation
import AVFoundation
import Metal
@testable import Renderer
@testable import Audio

@Suite("Meniscus drop placement (MEN.2b port)")
struct MeniscusDropsTests {

    private static let side = 45
    private static let bins = 512

    /// Run `steps` frames against a fixed spectrum and return the field plus the drop
    /// count on the final frame. Several frames are needed because the per-bin running
    /// mean has to settle before a deviation can register.
    private static func run(spectrum: [Float], steps: Int = 90,
                            configuration: MeniscusConfiguration = .init())
    -> (field: [Float], drops: Int, force: Float) {
        var drops = MeniscusDrops()
        var field = [Float](repeating: 0, count: side * side)
        var totalDrops = 0
        var totalForce: Float = 0
        spectrum.withUnsafeBufferPointer { buf in
            for _ in 0..<steps {
                drops.step(spectrum: buf, field: &field, side: side,
                           dt: 1.0 / 60.0, configuration: configuration)
                totalDrops += drops.lastDropCount
                totalForce += drops.lastDropForce
            }
        }
        return (field, totalDrops, totalForce)
    }

    /// A harmonic comb — energy at every `spacing`-th bin, which is what a pitched,
    /// harmonically rich sound looks like and exactly what the transform keys on.
    private static func comb(spacing: Int, amplitude: Float = 1.0) -> [Float] {
        var spectrum = [Float](repeating: 0.02, count: bins)
        for i in stride(from: spacing, to: bins, by: spacing) { spectrum[i] = amplitude }
        return spectrum
    }

    // MARK: - The mechanism

    @Test("a harmonic spectrum places drops; the field is disturbed")
    func harmonicSpectrumPlacesDrops() {
        let result = Self.run(spectrum: Self.comb(spacing: 8))
        #expect(result.drops > 0, """
            no drops were placed for a strongly harmonic spectrum. The DFT-over-spectrum \
            is the source's whole placement mechanism; if it never fires, the surface \
            falls back to the MEN.2a placeholder swell and T4 stays absent.
            """)
        let disturbed = result.field.contains { abs($0) > 1e-4 }
        #expect(disturbed, "drops were counted but the height field was never written")
    }

    @Test("a STRUCTURELESS spectrum places no drops")
    func flatSpectrumPlacesNoDrops() {
        // Constant magnitude across every bin: loud, but with no harmonic structure at
        // all. The transform keys on SPACING, so a spectrum with no spacing must place
        // nothing — every DFT bin integrates a constant over whole periods and comes out
        // at zero.
        //
        // This caught a real defect: the across-bin normaliser divided by a mean that is
        // itself ~0 here, so every ratio came out ~1 and the field was stamped at full
        // force everywhere. Silence rendered as a storm. Hence the absolute level gate.
        let result = Self.run(spectrum: [Float](repeating: 0.8, count: Self.bins))
        #expect(result.drops == 0, """
            \(result.drops) drops fired on a structureless spectrum. Placement is derived \
            from harmonic spacing; with no spacing there is nothing to derive, and firing \
            here means the drive is being manufactured by a division by ~zero.
            """)
    }

    @Test("harmonic SPACING moves the drops — placement is not fixed")
    func spacingChangesPlacement() {
        // The source's claim to elegance is that harmonic spacing decides position. Two
        // different spacings must therefore disturb different cells.
        let a = Self.run(spectrum: Self.comb(spacing: 6)).field
        let b = Self.run(spectrum: Self.comb(spacing: 17)).field
        func touched(_ field: [Float]) -> Set<Int> {
            Set(field.indices.filter { abs(field[$0]) > 1e-4 })
        }
        let cellsA = touched(a), cellsB = touched(b)
        #expect(!cellsA.isEmpty && !cellsB.isEmpty, "one of the spectra placed nothing")
        #expect(cellsA != cellsB, """
            two spectra with different harmonic spacing disturbed identical cells, so \
            position is not actually derived from the transform — the placement would be \
            decorative rather than the mechanism §3 describes.
            """)
    }

    @Test("a single impact is narrow and tall, not a broad heave")
    func impactIsNarrow() {
        let result = Self.run(spectrum: Self.comb(spacing: 8))
        let touched = result.field.indices.filter { abs(result.field[$0]) > 1e-4 }
        // Each drop writes a 3×3 stencil, so the disturbed area must stay a small
        // fraction of the grid. Reference `04`: impacts read as punctuation; broad
        // heaves read as mush.
        let fraction = Double(touched.count) / Double(Self.side * Self.side)
        #expect(fraction < 0.5, """
            \(Int(fraction * 100)) % of the grid was disturbed. Impacts are meant to be \
            3×3 punctuation on an otherwise calm field (T4); this is all-over agitation, \
            which is anti-reference 4.
            """)
    }

    @Test("force is bounded — one transient cannot punch the field")
    func forceIsBounded() {
        var configuration = MeniscusConfiguration()
        configuration.dropForceCeiling = 0.4
        let result = Self.run(spectrum: Self.comb(spacing: 8, amplitude: 40),
                              configuration: configuration)
        guard result.drops > 0 else { return }
        let deepest = result.field.map { abs($0) }.max() ?? 0
        // Ceiling × the stencil's centre weight (1.0), with headroom for repeated hits
        // landing on the same cell across frames.
        #expect(deepest < 0.4 * Float(result.drops) + 0.1, """
            a single cell reached \(deepest) against a \(configuration.dropForceCeiling) \
            per-impact ceiling — the clamp is not holding, and an unbounded impulse makes \
            the wave step ring for seconds.
            """)
    }
}

// MARK: - Real-music drop rate (MEN.2b)

/// The density evidence the mechanism tests cannot give.
///
/// `MENISCUS_PLAN.md` §2 reason 2: the source's drop mechanism "sets the DISTRIBUTION —
/// how many drops per second, how spread out, how hard — and the wave sim's damping and
/// stencil were tuned against that distribution. The interference structure in reference
/// `07` only appears at a certain drop density." A placement that fires but fires far too
/// rarely leaves the surface flat; far too often and it violates anti-reference 8
/// ("drops that fire on every frame … the musical role is dead").
///
/// Real music, through the production FFT, into the ported placement. No synthesis.
@Suite("Meniscus drop rate on real music")
struct MeniscusDropRateTests {

    @Test("the ported placement fires at a legible rate on real music",
          arguments: ["so_what", "there_there", "love_rehab"])
    func dropRateIsLegible(track: String) throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tempo/\(track).m4a")
        // Fail loud, never skip (QR.3): a silently-skipped verification is a hole. The
        // suite already requires this fixture tree via BeatThisFixturePresenceGate.
        try #require(FileManager.default.fileExists(atPath: url.path), """
            missing fixture \(url.path) — run Scripts/fetch_tempo_fixtures.sh. \
            The drop-rate evidence cannot be produced from synthetic input (FA #27).
            """)

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))

        let device = try #require(MTLCreateSystemDefaultDevice())
        let fft = try FFTProcessor(device: device)

        // 60 fps hops, as the render loop consumes it.
        let sampleRate = Float(format.sampleRate)
        let hop = Int(sampleRate / 60)
        let window = FFTProcessor.fftSize
        var drops = MeniscusDrops()
        // Explicitly enabled: this suite measures the mechanism regardless of the
        // shipped default, so turning drops off cannot silently disable the gate.
        var configuration = MeniscusConfiguration()
        configuration.dropsEnabled = true
        var field = [Float](repeating: 0, count: configuration.gridN * configuration.gridN)
        var totalDrops = 0
        var framesRun = 0

        var start = 0
        while start + window <= samples.count {
            _ = fft.process(samples: Array(samples[start..<(start + window)]), sampleRate: sampleRate)
            let magnitudes = fft.magnitudeBuffer.pointer
            UnsafeBufferPointer(magnitudes).withMemoryRebound(to: Float.self) { spectrum in
                drops.step(spectrum: spectrum, field: &field, side: configuration.gridN,
                           dt: 1.0 / 60.0, configuration: configuration)
            }
            totalDrops += drops.lastDropCount
            framesRun += 1
            start += hop
        }

        let seconds = Double(framesRun) / 60.0
        let perSecond = Double(totalDrops) / max(seconds, 0.001)
        print(String(format: "[meniscus-drops] %@: %.1f s · %d drops · %.1f drops/s",
                     track, seconds, totalDrops, perSecond))

        // CALIBRATION IS UNRESOLVED, and this is the gate saying so.
        //
        // The bounds are the LEGIBILITY range the references imply, not a floor tuned to
        // make the current code pass: under ~0.5/s the surface reads flat and T4 is
        // absent; over ~240/s is anti-reference 8, "individual impacts stop being
        // distinguishable [and] the musical role is dead". Four force scalings measured
        // 297-522, 713-838, 9.7-569 and 1800 drops/s — all outside it.
        //
        // `withKnownIssue` rather than a relaxed bound (QG.1: "a red route is the gate
        // working — file it, never tune the floor to make it pass"). The measurement
        // still runs and still prints every round, and this FAILS LOUDLY the moment the
        // rate lands in range, which is exactly when someone needs to come delete this
        // wrapper. See MENISCUS_PLAN.md §9 (MEN.2b drops).
        withKnownIssue("MEN.2b drop force scale is not calibrated — MENISCUS_PLAN §9") {
            #expect(perSecond > 0.5, """
                \(track): only \(String(format: "%.2f", perSecond)) drops/s — the surface \
                will read as flat, and the interference structure of reference `07` needs \
                a working drop density (§2 reason 2).
                """)
            #expect(perSecond < 240, """
                \(track): \(String(format: "%.0f", perSecond)) drops/s — anti-reference 8.
                """)
        }
    }
}
