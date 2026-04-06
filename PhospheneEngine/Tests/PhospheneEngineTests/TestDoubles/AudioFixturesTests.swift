// AudioFixturesTests — Verify deterministic audio test data generators.

import Testing

@Test func sineWaveAmplitudeRangeMinus1To1() {
    let wave = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 0.1)

    #expect(!wave.isEmpty)
    for sample in wave {
        #expect(sample >= -1.0)
        #expect(sample <= 1.0)
    }

    // A full-amplitude sine should reach close to ±1.
    let maxAbs = wave.map { abs($0) }.max() ?? 0
    #expect(maxAbs > 0.99)
}

@Test func silenceAllZeros() {
    let silence = AudioFixtures.silence(sampleCount: 512)

    #expect(silence.count == 512)
    for sample in silence {
        #expect(sample == 0)
    }
}

@Test func whiteNoiseNonZeroRMS() {
    let noise = AudioFixtures.whiteNoise(sampleCount: 4096, seed: 42)

    #expect(noise.count == 4096)

    // RMS should be non-zero for noise.
    let sumOfSquares = noise.reduce(Float(0)) { $0 + $1 * $1 }
    let rms = (sumOfSquares / Float(noise.count)).squareRoot()
    #expect(rms > 0.01)
}

@Test func impulseExactlyOneNonZeroSample() {
    let impulse = AudioFixtures.impulse(sampleCount: 256, position: 100)

    #expect(impulse.count == 256)

    let nonZeroCount = impulse.filter { $0 != 0 }.count
    #expect(nonZeroCount == 1)
    #expect(impulse[100] == 1.0)
}

@Test func mixStereoLengthIs2xMono() {
    let left = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 0.01)
    let right = AudioFixtures.sineWave(frequency: 880, sampleRate: 48000, duration: 0.01)
    let stereo = AudioFixtures.mixStereo(left: left, right: right)

    #expect(stereo.count == left.count * 2)

    // Verify interleaving: even indices = left, odd = right.
    for i in 0..<left.count {
        #expect(stereo[i * 2] == left[i])
        #expect(stereo[i * 2 + 1] == right[i])
    }
}
