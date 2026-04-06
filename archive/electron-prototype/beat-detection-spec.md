# Beat Detection Architecture — v0.2 Spec Addendum

## Problem Statement

V0.1's beat detection (simple bass energy threshold) only works for music with prominent kick drums. V0.2 needs beat/onset detection that works across genres — electronic, hip-hop, jazz, classical, ambient — and handles tempo changes within a song.

## Key Insight: Separate Onset Detection from Beat Response

The system has two distinct layers:

1. **Onset Detection Engine** (shared, runs once per frame): Analyzes audio and produces a set of raw onset signals across multiple frequency bands. This is genre-agnostic signal processing.

2. **Beat Response Config** (per-shader): Each shader declares which onset signals it cares about and how to map them to its `u_beat` uniform. This is aesthetic tuning.

---

## Layer 1: Onset Detection Engine (`src/renderer/audio/onset-detector.ts`)

Runs every frame. Produces a struct of onset signals that ALL shaders can read from.

### Algorithm: Spectral Flux with Adaptive Threshold

Spectral flux is more robust than raw energy thresholding because it detects *changes* in spectral content, not absolute levels. A sustained loud bass note won't keep triggering — only the attack will.

#### Per-frame pipeline:

```
Raw PCM samples (from IPC)
    ↓
FFT (1024-point, Hanning window)
    ↓
Split into frequency bands:
  - sub_bass:  20–80 Hz    (kick drums, 808s)
  - bass:      80–250 Hz   (bass guitar, low synths)
  - low_mid:   250–1000 Hz (snare body, guitar, vocals)
  - mid:       1000–4000 Hz (snare crack, hi-hats, presence)
  - treble:    4000–16000 Hz (cymbals, air, sibilance)
    ↓
For EACH band, compute spectral flux:
  flux = sum of max(0, current_magnitude[bin] - previous_magnitude[bin])
  (half-wave rectification — only detect increases, not decreases)
    ↓
For EACH band, maintain adaptive threshold:
  threshold = median(flux_history, last ~0.5s) * sensitivity_multiplier
  onset_detected = flux > threshold
    ↓
Output: OnsetSignals struct (one boolean + one float per band per frame)
```

#### Why spectral flux over energy threshold:
- Energy threshold triggers on sustained loud passages (false positives)
- Energy threshold misses quiet onsets in sparse music (false negatives)
- Spectral flux responds to *change*, which is what humans perceive as rhythm
- Per-band flux means a hi-hat hit registers in treble without the bass band firing

### OnsetSignals struct (produced every frame):

```typescript
interface OnsetSignals {
  // Per-band onset detection (boolean: did an onset occur this frame?)
  sub_bass_onset: boolean;
  bass_onset: boolean;
  low_mid_onset: boolean;
  mid_onset: boolean;
  treble_onset: boolean;

  // Per-band flux values (float 0-1, normalized against recent history)
  // These are continuous — useful for shaders that want smooth reactivity
  // rather than binary triggers
  sub_bass_flux: number;
  bass_flux: number;
  low_mid_flux: number;
  mid_flux: number;
  treble_flux: number;

  // Composite onset: ANY band detected an onset this frame
  // Weighted sum of per-band onsets — useful as a general-purpose trigger
  composite_onset: boolean;
  composite_strength: number; // 0-1, how strong the onset was across all bands
}
```

### Adaptive threshold details:

- Use a **circular buffer** per band (~50 frames of flux history at 60fps ≈ 0.8 seconds)
- Threshold = `median(buffer) * sensitivity` where sensitivity defaults to 1.5
- Median is more robust than mean (outliers from big hits don't inflate the threshold)
- This naturally adapts to quiet vs. loud passages and different genres
- Apply a **cooldown** per band: after an onset fires, suppress that band for ~100ms (6 frames at 60fps) to prevent double-triggers

---

## Layer 2: Beat Response Config (per-shader)

Each shader's `.json` metadata sidecar gets a new optional `beatConfig` field that describes how onset signals map to the shader's `u_beat` uniform.

### BeatConfig schema:

```json
{
  "name": "Fluid Flow",
  "family": "fluid",
  "duration": 30,
  "beatConfig": {
    "sources": ["sub_bass", "bass"],
    "mode": "onset",
    "sensitivity": 1.5,
    "decayRate": 0.92,
    "peakValue": 1.0,
    "useFlux": false
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `sources` | string[] | `["sub_bass", "bass"]` | Which frequency bands to listen to. Options: `"sub_bass"`, `"bass"`, `"low_mid"`, `"mid"`, `"treble"`, `"composite"` |
| `mode` | string | `"onset"` | `"onset"` = binary trigger from onset detection. `"flux"` = continuous normalized flux value (smoother, less punchy) |
| `sensitivity` | number | 1.5 | Multiplier on the adaptive threshold for this shader's onset detection. Lower = more triggers, higher = only big hits. Range: 0.5–3.0 |
| `decayRate` | number | 0.92 | Per-frame exponential decay for u_beat after a trigger. 0.9 = fast decay (~10 frames). 0.95 = slow decay (~30 frames). 0.85 = very snappy. |
| `peakValue` | number | 1.0 | What u_beat jumps to on onset. Can be < 1.0 for subtler shaders. |
| `useFlux` | boolean | false | If true, u_beat = smoothed flux value (continuous) instead of onset-triggered decay (pulsed). Good for ambient/evolving shaders that shouldn't "pop". |

### How the scene manager computes u_beat per shader:

```
each frame:
  onsetSignals = onsetDetector.analyze(pcmData)

  for each active shader:
    config = shader.metadata.beatConfig (or defaults)

    if config.mode == "flux":
      // Smooth, continuous mode — good for ambient shaders
      raw = average of config.sources flux values from onsetSignals
      u_beat = lerp(u_beat_previous, raw, 0.3)  // smooth it

    else if config.mode == "onset":
      // Punchy, trigger mode — good for geometric/beat-driven shaders
      triggered = ANY of config.sources had onset this frame
      if triggered:
        u_beat = config.peakValue
      else:
        u_beat = u_beat_previous * config.decayRate
```

### Example configs for different shader aesthetics:

**Kaleidoscope (geometric, beat-driven):**
```json
"beatConfig": {
  "sources": ["sub_bass"],
  "mode": "onset",
  "sensitivity": 1.3,
  "decayRate": 0.88
}
```
Listens only to deep kick drums. Snappy decay. Punchy rotation pulses.

**Nebula (fluid, ambient):**
```json
"beatConfig": {
  "sources": ["bass", "low_mid", "mid"],
  "mode": "flux",
  "sensitivity": 1.5,
  "decayRate": 0.95,
  "useFlux": true
}
```
Listens broadly. Uses continuous flux, not triggers. Slow, breathing motion.

**Waveform Ribbons (abstract, responsive):**
```json
"beatConfig": {
  "sources": ["composite"],
  "mode": "onset",
  "sensitivity": 1.2,
  "decayRate": 0.91
}
```
Composite = reacts to ANY onset across all bands. Medium decay. Works with any genre because it picks up whatever rhythmic element is most prominent.

---

## Implementation Order for Claude Code

Build this in 4 discrete steps. Each step should be a separate Claude Code task with a clear "done" condition.

### Step 1: FFT + Spectral Flux engine (no shaders involved)
- Add FFT computation to analyzer.ts (use a simple radix-2 FFT or import `fft.js`)
- Split FFT output into 5 frequency bands
- Compute half-wave rectified spectral flux per band per frame
- Log flux values to console
- **Done when**: Console output shows flux values that visibly spike when you clap or play music with clear beats

### Step 2: Adaptive threshold + onset detection
- Add circular buffer per band for flux history
- Compute adaptive threshold (median * sensitivity)
- Add cooldown logic
- Produce the OnsetSignals struct each frame
- Log onset booleans to console
- **Done when**: Console shows onset=true that matches audible beats across at least 2 genres (try electronic AND acoustic/jazz)

### Step 3: BeatConfig + per-shader u_beat computation
- Add BeatConfig to scene metadata schema
- Scene manager reads beatConfig, computes u_beat per shader using the onset/flux logic above
- Wire u_beat into existing shader uniforms
- **Done when**: Existing spectrum-pulse shader visibly pulses on beats with default config

### Step 4: Add 2-3 shaders with different beatConfigs
- One punchy geometric shader (onset mode, sub_bass source)
- One smooth fluid shader (flux mode, broad sources)
- One composite-driven shader
- Scene transitions with crossfade
- **Done when**: Playing music cycles through shaders that each respond differently to the same audio

---

## Testing approach

The hardest part of beat detection to test is "does it feel right?" Here's a practical protocol:

1. **Electronic (clear beats):** Daft Punk — "Around the World". Should trigger cleanly on every kick.
2. **Hip-hop (sparse, heavy bass):** Kendrick Lamar — "HUMBLE." Sub-bass onsets should land on the 808 hits.
3. **Jazz (complex rhythm):** Miles Davis — "So What." Onset should pick up ride cymbal + bass, NOT trigger continuously on held notes.
4. **Classical (dynamics, no drums):** Beethoven — Symphony No. 5, 1st movement. Onsets should fire on the famous "da-da-da-DUM" motif attacks, not on sustained strings.
5. **Ambient (minimal rhythm):** Brian Eno — "Music for Airports." Very few onsets should fire. Flux mode should show gentle undulation.

If it works on these 5, it'll work on most music.
