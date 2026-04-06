#!/usr/bin/env python3
"""
essentia_ground_truth.py — Generate ground-truth MIR features using Essentia.

Computes reference values for validating the Swift MIR pipeline accuracy.
This is an offline validation tool only — Essentia (AGPL) is NEVER linked
into PhospheneEngine or PhospheneApp.

Usage:
    pip install essentia
    python tools/essentia_ground_truth.py [--input audio.wav] [--output-dir tools/output]

If no input is provided, generates synthetic test signals and computes features.

Output:
    - ground_truth_spectral.json  — centroid, rolloff, flux for test signals
    - ground_truth_chroma.json    — 12-bin chroma for C major chord
    - ground_truth_tempo.json     — BPM estimation for kick patterns
"""

import argparse
import json
import numpy as np
import os
import sys

def check_essentia():
    """Check if essentia is available."""
    try:
        import essentia
        import essentia.standard as es
        return es
    except ImportError:
        print("Essentia not installed. Install with: pip install essentia")
        print("Essentia is AGPL-licensed and used for offline validation only.")
        sys.exit(1)

def generate_sine(freq, sample_rate=48000, duration=0.1):
    """Generate a sine wave."""
    t = np.arange(int(sample_rate * duration)) / sample_rate
    return np.sin(2 * np.pi * freq * t).astype(np.float32)

def generate_c_major_chord(sample_rate=48000, duration=0.1):
    """Generate C5+E5+G5 chord (matching Swift fixture)."""
    t = np.arange(int(sample_rate * duration)) / sample_rate
    freqs = [523.25, 659.25, 783.99]
    signal = np.zeros_like(t, dtype=np.float32)
    for f in freqs:
        signal += np.sin(2 * np.pi * f * t).astype(np.float32) / len(freqs)
    return signal

def generate_120bpm_kick(sample_rate=48000, duration=5.0):
    """Generate 120 BPM kick pattern."""
    n_samples = int(sample_rate * duration)
    signal = np.zeros(n_samples, dtype=np.float32)
    beat_interval = sample_rate * 60.0 / 120.0
    kick_duration = 200  # samples
    kick_freq = 60.0  # Hz

    next_kick = 0.0
    while int(next_kick) < n_samples:
        start = int(next_kick)
        for i in range(kick_duration):
            idx = start + i
            if idx >= n_samples:
                break
            t = i / sample_rate
            envelope = np.exp(-t * 50.0)
            signal[idx] += np.sin(2 * np.pi * kick_freq * t) * envelope
        next_kick += beat_interval
    return signal

def compute_spectral_features(es, signal, sample_rate=48000):
    """Compute spectral centroid, rolloff using Essentia."""
    w = es.Windowing(type='hann', size=1024)
    spectrum = es.Spectrum(size=1024)
    centroid = es.SpectralCentroidTime(sampleRate=sample_rate)
    rolloff = es.RollOff(sampleRate=sample_rate)

    frame = signal[:1024]
    windowed = w(frame)
    spec = spectrum(windowed)

    c = centroid(windowed)
    r = rolloff(spec)

    return {
        'centroid_hz': float(c),
        'rolloff_hz': float(r),
        'spectrum_size': len(spec),
    }

def compute_chroma(es, signal, sample_rate=48000):
    """Compute HPCP (chroma) using Essentia."""
    w = es.Windowing(type='hann', size=1024)
    spectrum = es.Spectrum(size=1024)
    spectral_peaks = es.SpectralPeaks(
        sampleRate=sample_rate,
        maxPeaks=20,
        magnitudeThreshold=0.001,
    )
    hpcp = es.HPCP(
        size=12,
        referenceFrequency=440.0,
        sampleRate=sample_rate,
    )

    frame = signal[:1024]
    windowed = w(frame)
    spec = spectrum(windowed)
    freqs, mags = spectral_peaks(spec)
    chroma = hpcp(freqs, mags)

    return {
        'chroma': [float(x) for x in chroma],
        'max_bin': int(np.argmax(chroma)),
        'pitch_names': ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'],
    }

def compute_tempo(es, signal, sample_rate=48000):
    """Compute tempo using Essentia's RhythmExtractor."""
    rhythm = es.RhythmExtractor2013(method='multifeature')
    bpm, beats, confidence, _, _ = rhythm(signal)

    return {
        'bpm': float(bpm),
        'beat_count': len(beats),
        'confidence': float(confidence),
        'beat_positions_seconds': [float(b) for b in beats[:20]],  # First 20
    }

def main():
    parser = argparse.ArgumentParser(description='Generate MIR ground truth using Essentia')
    parser.add_argument('--input', help='Input WAV file (optional, uses synthetic if omitted)')
    parser.add_argument('--output-dir', default='tools/output', help='Output directory')
    args = parser.parse_args()

    es = check_essentia()
    os.makedirs(args.output_dir, exist_ok=True)

    print("Generating ground-truth MIR features using Essentia...")

    # Spectral features on C major chord
    chord = generate_c_major_chord()
    spectral = compute_spectral_features(es, chord)
    print(f"  Spectral centroid: {spectral['centroid_hz']:.1f} Hz")
    print(f"  Spectral rolloff: {spectral['rolloff_hz']:.1f} Hz")

    with open(os.path.join(args.output_dir, 'ground_truth_spectral.json'), 'w') as f:
        json.dump(spectral, f, indent=2)

    # Chroma on C major chord
    chroma = compute_chroma(es, chord)
    print(f"  Chroma max bin: {chroma['max_bin']} ({chroma['pitch_names'][chroma['max_bin']]})")
    print(f"  Chroma vector: {[f'{x:.3f}' for x in chroma['chroma']]}")

    with open(os.path.join(args.output_dir, 'ground_truth_chroma.json'), 'w') as f:
        json.dump(chroma, f, indent=2)

    # Tempo on 120 BPM kick
    kick = generate_120bpm_kick(duration=10.0)
    tempo = compute_tempo(es, kick)
    print(f"  Estimated tempo: {tempo['bpm']:.1f} BPM (confidence: {tempo['confidence']:.2f})")

    with open(os.path.join(args.output_dir, 'ground_truth_tempo.json'), 'w') as f:
        json.dump(tempo, f, indent=2)

    # If input file provided, compute features on that too
    if args.input:
        loader = es.MonoLoader(filename=args.input, sampleRate=48000)
        audio = loader()
        print(f"\nInput file: {args.input} ({len(audio)/48000:.1f}s)")

        input_spectral = compute_spectral_features(es, audio)
        input_chroma = compute_chroma(es, audio)
        input_tempo = compute_tempo(es, audio)

        print(f"  Centroid: {input_spectral['centroid_hz']:.1f} Hz")
        print(f"  Tempo: {input_tempo['bpm']:.1f} BPM")
        print(f"  Key chroma max: {input_chroma['pitch_names'][input_chroma['max_bin']]}")

        with open(os.path.join(args.output_dir, 'ground_truth_input.json'), 'w') as f:
            json.dump({
                'spectral': input_spectral,
                'chroma': input_chroma,
                'tempo': input_tempo,
            }, f, indent=2)

    print("\nDone. Results in:", args.output_dir)

if __name__ == '__main__':
    main()
