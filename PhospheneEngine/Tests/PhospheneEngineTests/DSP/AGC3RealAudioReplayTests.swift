// AGC3RealAudioReplayTests — BUG-029 / AGC3.5. Replays a REAL captured tap through the
// production FFT → MIRPipeline path and asserts the cold-start `f.bass` spike stays bounded.
//
// Why real audio (FA #27): the synthetic step-onset in AGC3ColdStartSpikeTests does NOT
// reproduce the spike — a step's first audible frame IS the full sustained level, so the
// seed is correct. REAL onsets have an ATTACK RAMP: the first audible frame is a small
// leading edge, so the seed is tiny and the slow warmup EMA lags the imminent full transient
// → the 16-20x spike (Wake Up 20x, KITM 16x; sessions 2026-07-09T02-04-02Z / T17-35-12Z).
// A synthetic fixture that misses this is exactly how BUG-029 was falsely closed once.
//
// Point AGC3_REAL_WAV at a captured `raw_tap.wav` (hard-onset track) to run; skipped otherwise.

import Foundation
import AVFoundation
import Testing
import Shared
@testable import Audio
@testable import DSP

@Test func agc3_realAudioReplay_hardOnset_doesNotSpike() throws {
    guard let path = ProcessInfo.processInfo.environment["AGC3_REAL_WAV"], !path.isEmpty else {
        print("AGC3RealAudioReplay: AGC3_REAL_WAV unset — skipping (point it at a hard-onset raw_tap.wav)")
        return
    }
    let url = URL(fileURLWithPath: path)
    let mono = try decodeMono(url)
    let sr = 44100  // tap capture rate
    let fftSize = 1024
    let fft = try FFTMagnitudeKernel(fftSize: fftSize)
    let mir = MIRPipeline(binCount: fftSize / 2, sampleRate: Float(sr), fftSize: fftSize)
    let fps = Float(sr) / Float(fftSize)

    var bass: [Float] = []
    var allBandMax: [Float] = []   // max across the 6 bands each frame — the AGC-blowup signature
    var offset = 0
    while offset + fftSize <= mono.count {
        for i in 0..<fftSize { fft.windowed[i] = mono[offset + i] }
        fft.computeMagnitudes()
        let fv = mir.process(magnitudes: fft.magnitudes, fps: fps, time: Float(bass.count) / fps, deltaTime: 1.0 / fps)
        bass.append(fv.bass)
        allBandMax.append(max(fv.subBass, fv.lowBass, fv.lowMid, fv.midHigh, fv.highMid, fv.high))
        offset += fftSize
    }
    // AGC-blowup signature: at the pre-fix spike frame ALL bands inflate together (lowBass 4.2,
    // lowMid 2.1 …). Physical normalized bands sit ≤ ~1.5. The convergence spike lands anywhere in
    // the first ~1.5 s (this replay: f.bass 2.4 at 0.51 s with the fix OFF), so the window must span
    // it — a 0.5 s window missed the peak and let the bug slip past the gate.
    let coldN = Int(1.5 * fps)
    let coldPeakBand = allBandMax.prefix(coldN).max() ?? 0
    print(String(format: "  cold-start (first 1.5s) worst-band peak = %.2f (fix OFF ≈ 2.4+, fix ON ≈ 0.6)", coldPeakBand))

    // Onset = first 3 s; steady = 10-40 s (matches tools/agc3/measure_coldstart_spike.py).
    let onsetN = Int(3 * fps), loN = Int(10 * fps), hiN = min(Int(40 * fps), bass.count)
    let onsetPeak = bass.prefix(onsetN).max() ?? 0
    let steadyVals = Array(bass[min(loN, bass.count)..<hiN]).sorted()
    let steady = steadyVals.isEmpty ? 0 : steadyVals[steadyVals.count / 2]  // median
    let ratio = steady > 0 ? onsetPeak / steady : 0
    let peakIdx = bass.prefix(onsetN).enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
    print(String(format: "AGC3RealAudioReplay: onsetPeak=%.3f @t=%.2fs steady=%.3f ratio=%.1fx (frames=%d)",
                 onsetPeak, Float(peakIdx) / fps, steady, ratio, bass.count))

    // The gate is the AGC-scale BLOWUP, not the onset/steady ratio. A track with a loud
    // intro (Wake Up's opening riff) legitimately reads f.bass ~0.85 vs a quieter later steady
    // — that's real dynamics FFO should follow, not the bug. The bug is the non-physical global
    // AGC-scale explosion: at the pre-fix spike frame ALL bands rail together (worst band 4.3).
    // Correct behaviour keeps every band within the physical normalized range during the
    // convergence window. This cleanly separates the artifact (≥3×) from real beats (≤~1.5).
    #expect(steady > 0.01, "sanity: steady f.bass non-zero")
    #expect(coldPeakBand < 2.0,
            "BUG-029: cold-start AGC-scale blowup — worst band \(coldPeakBand) in the first 0.5 s must stay physical (< 2.0; pre-fix 4.3)")
}

/// Decode any AVFoundation-readable file to a mono Float32 array at its native rate.
private func decodeMono(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let fmt = file.processingFormat
    let frames = AVAudioFrameCount(file.length)
    guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return [] }
    try file.read(into: buf)
    let n = Int(buf.frameLength)
    guard let ch = buf.floatChannelData else { return [] }
    let chCount = Int(fmt.channelCount)
    var mono = [Float](repeating: 0, count: n)
    for i in 0..<n {
        var s: Float = 0
        for c in 0..<chCount { s += ch[c][i] }
        mono[i] = s / Float(chCount)
    }
    return mono
}
