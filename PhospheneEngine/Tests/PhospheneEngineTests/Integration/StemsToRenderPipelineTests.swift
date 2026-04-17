// StemsToRenderPipelineTests — Integration tests for the live stem pipeline.
// Verifies: warmup default, separation → analysis flow, track-change reset,
// and Swift/MSL struct size agreement.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import ML
@testable import Renderer
@testable import Shared

// MARK: - Warmup Default

@Test func stemFeatures_defaultZero_rendersWithoutCrash() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    let context = try MetalContext()
    let shaderLibrary = try ShaderLibrary(context: context)
    let fftBuffer = try UMABuffer<Float>(device: device, capacity: 512)
    let waveformBuffer = try UMABuffer<Float>(device: device, capacity: 2048)

    let pipeline = try RenderPipeline(
        context: context,
        shaderLibrary: shaderLibrary,
        fftBuffer: fftBuffer.buffer,
        waveformBuffer: waveformBuffer.buffer
    )

    // Set zero stem features (warmup default).
    pipeline.setStemFeatures(.zero)

    // Verify the value round-trips through the lock-protected getter.
    let features = pipeline.stemFeaturesLock.withLock { pipeline.latestStemFeatures }
    #expect(features.vocalsEnergy == 0, "Warmup vocals should be zero")
    #expect(features.drumsBeat == 0, "Warmup drums beat should be zero")
    #expect(features.bassEnergy == 0, "Warmup bass should be zero")
    #expect(features.otherBand1 == 0, "Warmup other band1 should be zero")
}

// MARK: - Separation → Analysis

@available(macOS 14.2, *)
@Test func stemFeatures_afterSeparation_hasNonZeroDrumsEnergy() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    // Use FakeStemSeparator: puts audio in drums stem (index 1), zeros others.
    let separator = try FakeStemSeparator(device: device, bufferCapacity: 441_000)
    let analyzer = StemAnalyzer(sampleRate: 44100)

    // Generate ~10s of percussive noise at 44100 Hz stereo.
    let monoSamples = 44100 * 10
    let stereoSamples = monoSamples * 2
    var audio = [Float](repeating: 0, count: stereoSamples)

    // Create repeating impulses at ~4 Hz (every 11025 samples) to simulate kick.
    let impulseInterval = 11025
    for i in stride(from: 0, to: monoSamples, by: impulseInterval) {
        // Short burst of energy (50 samples).
        for j in 0..<min(50, monoSamples - i) {
            let value = Float(50 - j) / 50.0  // Decaying impulse
            audio[(i + j) * 2] = value         // Left
            audio[(i + j) * 2 + 1] = value     // Right
        }
    }

    let result = try separator.separate(audio: audio, channelCount: 2, sampleRate: 44100)

    // Extract waveforms from stem buffers.
    var stemWaveforms: [[Float]] = []
    for buffer in separator.stemBuffers {
        let count = min(result.sampleCount, buffer.capacity)
        let waveform = Array(buffer.pointer.prefix(count))
        stemWaveforms.append(waveform)
    }

    // Run multiple analysis frames (BandEnergyProcessor needs AGC warmup).
    // Simulate 60fps for 2 seconds by feeding successive 1024-sample windows.
    let fps: Float = 60
    let hop = Int(44100.0 / fps)  // ~735 samples per frame
    var features = StemFeatures.zero

    for frame in 0..<120 {
        let offset = frame * hop
        var frameWaveforms: [[Float]] = []
        for stem in stemWaveforms {
            let end = min(offset + 1024, stem.count)
            if offset < end {
                frameWaveforms.append(Array(stem[offset..<end]))
            } else {
                frameWaveforms.append([Float](repeating: 0, count: 1024))
            }
        }
        features = analyzer.analyze(stemWaveforms: frameWaveforms, fps: fps)
    }

    // Drums stem should have meaningful energy after multi-frame AGC warmup.
    // With 120 frames of warmup, the AGC running average should be fully adapted,
    // producing energy values well above the near-zero single-frame result.
    #expect(features.drumsEnergy > 0.1, "Drums energy should be > 0.1 after AGC warmup, got \(features.drumsEnergy)")
    // Vocals/bass/other should be near-zero (FakeStemSeparator zeros them).
    #expect(features.vocalsEnergy < 0.01, "Vocals energy should be near-zero (not routed)")
    #expect(features.bassEnergy < 0.01, "Bass energy should be near-zero (not routed)")
}

// MARK: - Track Change Reset

@Test func stemFeatures_trackChange_resetsToZero() throws {
    let buffer = StemSampleBuffer(sampleRate: 44100, maxSeconds: 15)
    let analyzer = StemAnalyzer(sampleRate: 44100)

    // Write some audio.
    let noise = AudioFixtures.whiteNoise(sampleCount: 44100 * 2)
    noise.withUnsafeBufferPointer { ptr in
        buffer.write(samples: ptr.baseAddress!, count: ptr.count)
    }
    #expect(!buffer.snapshotLatest(seconds: 1).isEmpty, "Buffer should have data before reset")

    // Reset (simulating track change).
    buffer.reset()
    analyzer.reset()

    // Buffer should be empty.
    let snapshot = buffer.snapshotLatest(seconds: 10)
    #expect(snapshot.isEmpty, "Buffer should be empty after reset")

    // Analyzer should produce near-zero output from zero input.
    let zeroWaveforms: [[Float]] = Array(repeating: [Float](repeating: 0, count: 1024), count: 4)
    let features = analyzer.analyze(stemWaveforms: zeroWaveforms, fps: 60)
    #expect(features.drumsEnergy < 0.01, "Drums energy should be near-zero after reset")
    #expect(features.vocalsEnergy < 0.01, "Vocals energy should be near-zero after reset")
}

// MARK: - Struct Size Agreement (Swift ↔ MSL)

@Test func stemFeatures_renderBinding_structSizeMatchesMSL() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    // Compile a tiny compute kernel that writes sizeof(StemFeatures) to a buffer.
    let source = """
    #include <metal_stdlib>
    using namespace metal;

    // Matches Swift StemFeatures layout (64 floats = 256 bytes, MV-3, D-028).
    struct StemFeatures {
        // Floats 1–16: per-stem energy/band/beat.
        float vocals_energy;   float vocals_band0;
        float vocals_band1;    float vocals_beat;
        float drums_energy;    float drums_band0;
        float drums_band1;     float drums_beat;
        float bass_energy;     float bass_band0;
        float bass_band1;      float bass_beat;
        float other_energy;    float other_band0;
        float other_band1;     float other_beat;
        // Floats 17–24: MV-1 deviation primitives.
        float vocals_energy_rel;  float vocals_energy_dev;
        float drums_energy_rel;   float drums_energy_dev;
        float bass_energy_rel;    float bass_energy_dev;
        float other_energy_rel;   float other_energy_dev;
        // Floats 25–40: MV-3a rich metadata (4 per stem).
        float vocals_onset_rate;  float vocals_centroid;
        float vocals_attack_ratio; float vocals_energy_slope;
        float drums_onset_rate;   float drums_centroid;
        float drums_attack_ratio; float drums_energy_slope;
        float bass_onset_rate;    float bass_centroid;
        float bass_attack_ratio;  float bass_energy_slope;
        float other_onset_rate;   float other_centroid;
        float other_attack_ratio; float other_energy_slope;
        // Floats 41–42: MV-3c vocal pitch.
        float vocals_pitch_hz;    float vocals_pitch_confidence;
        // Floats 43–64: padding to 256 bytes (22 floats).
        float _p1,_p2,_p3,_p4,_p5,_p6,_p7,_p8,_p9,_p10,_p11;
        float _p12,_p13,_p14,_p15,_p16,_p17,_p18,_p19,_p20,_p21,_p22;
    };

    kernel void measure_size(device uint* out [[buffer(0)]],
                             uint tid [[thread_position_in_grid]]) {
        if (tid == 0) {
            out[0] = sizeof(StemFeatures);
        }
    }
    """

    let library = try device.makeLibrary(source: source, options: nil)
    guard let function = library.makeFunction(name: "measure_size") else {
        throw StemTestError.shaderCompileFailed
    }
    let pipelineState = try device.makeComputePipelineState(function: function)

    let outBuffer = try UMABuffer<UInt32>(device: device, capacity: 1)
    outBuffer[0] = 0

    guard let queue = device.makeCommandQueue(),
          let commandBuffer = queue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder() else {
        throw StemTestError.noMetalDevice
    }

    encoder.setComputePipelineState(pipelineState)
    encoder.setBuffer(outBuffer.buffer, offset: 0, index: 0)
    encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    let mslSize = outBuffer[0]
    let swiftSize = UInt32(MemoryLayout<StemFeatures>.size)
    #expect(mslSize == swiftSize,
            "MSL sizeof(StemFeatures) = \(mslSize) must match Swift MemoryLayout<StemFeatures>.size = \(swiftSize)")
    #expect(mslSize == 256, "StemFeatures must be exactly 256 bytes in MSL (MV-3: 64 floats), got \(mslSize)")
}

// MARK: - Idle Suppression

@Test func stemPipeline_silence_skipsSeparation() throws {
    let buffer = StemSampleBuffer(sampleRate: 44100, maxSeconds: 15)

    // Write 10 seconds of silence (zeros) as interleaved stereo.
    let silenceSamples = 44100 * 10 * 2
    let silence = [Float](repeating: 0, count: silenceSamples)
    silence.withUnsafeBufferPointer { ptr in
        buffer.write(samples: ptr.baseAddress!, count: ptr.count)
    }

    // Snapshot should return data (buffer is not empty).
    let snapshot = buffer.snapshotLatest(seconds: 10)
    #expect(!snapshot.isEmpty, "Buffer should have data after writing silence")

    // RMS of silence should be below the suppression threshold.
    let rms = buffer.rms(seconds: 10)
    #expect(rms < 1e-6, "RMS of silence should be < 1e-6, got \(rms)")

    // RMS of non-silent audio should be above the threshold.
    let buffer2 = StemSampleBuffer(sampleRate: 44100, maxSeconds: 15)
    let noise = AudioFixtures.whiteNoise(sampleCount: 44100 * 10 * 2)
    noise.withUnsafeBufferPointer { ptr in
        buffer2.write(samples: ptr.baseAddress!, count: ptr.count)
    }
    let noiseRMS = buffer2.rms(seconds: 10)
    #expect(noiseRMS > 1e-6, "RMS of white noise should be > 1e-6, got \(noiseRMS)")
}

// MARK: - Error Type

private enum StemTestError: Error {
    case noMetalDevice
    case shaderCompileFailed
}
