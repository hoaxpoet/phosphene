# Phosphene — Project Brief & Requirements

## Overview

Phosphene is a next-generation real-time music visualizer for macOS — a spiritual successor to Milkdrop and ProjectM, built to exploit modern GPU hardware, richer audio analysis, and eventually, machine learning.

It captures system audio and generates psychedelic, audio-synchronized visuals. Unlike Milkdrop (designed in 2001 for a Pentium III, limited to a handful of coarse audio floats), Phosphene gives shaders access to the full frequency spectrum and raw waveform as GPU textures, plus derived features like spectral centroid and continuous spectral flux. Shaders can map hundreds of individual frequency bins to visual elements, draw oscilloscope-quality waveforms, and respond to musical texture — not just volume.

The long-term vision: a visualizer that learns. It observes what you listen to, notices which visuals you linger on versus skip, and over time develops a personalized relationship between your music and its visual expression.

The name references the visual phenomenon of perceiving light and patterns without external visual stimulus — exactly what this software does with sound.

## Core Use Cases

1. **Listening party backdrop**: Friends gather, each brings a 20-minute mix. Phosphene runs fullscreen on a TV or projector, producing synchronized visuals while people sit and listen together.
2. **Ambient accompaniment**: Solo listening — reading, working, unwinding — with visuals on a secondary display or in a window.
3. **Creative enhancement**: Psychedelic visuals to accompany music under the influence of cannabis or psychedelics, or simply to unlock a more immersive listening experience for anyone.

## Target Audience

Musically engaged adults who care about the listening experience. Comfortable installing software from GitHub, running terminal commands, and configuring permissions. Not a mass-market consumer app — a tool for enthusiasts.

---

## V1 Scope: Audio-Reactive Visualizer

### What V1 Does

- Captures system audio via macOS ScreenCaptureKit (native system audio loopback)
- Performs real-time frequency analysis: 3-band IIR, 6-band IIR, FFT spectrum, raw waveform
- Provides shaders with rich audio data: continuous energy bands, full spectrum texture, waveform texture, spectral features, and beat onset pulses
- Renders WebGL/GLSL shader-based visuals with Milkdrop-style feedback (previous frame texture, zoom, rotation, decay)
- Per-shader visual tuning via metadata (feedback params, beat response, beat source selection)
- Transitions between visual scenes at per-scene intervals with smooth crossfades
- Runs in both fullscreen and windowed modes
- Provides a hidden control overlay (appears on hover/keystroke, disappears otherwise)

### What V1 Does NOT Do

- No music identification (no Shazam, no Spotify API)
- No metadata awareness (artist, song, lyrics, album art)
- No learning or adaptation (V1 is purely reactive)
- No user-configurable scene timing (per-scene defaults only, no UI settings for V1)
- No cross-platform support (macOS only)
- No mobile version

---

## Technical Architecture

### Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| App shell | Electron 41+ | Cross-platform potential, easy distribution, native OS access. 41+ required for ScreenCaptureKit audio loopback. |
| Rendering | WebGL + Three.js + custom GLSL shaders | Rich visual possibilities, GPU-accelerated, large shader ecosystem |
| Audio capture | ScreenCaptureKit (native macOS API) | Apple's recommended API for system audio capture on macOS 14+. No virtual audio driver required. |
| Audio analysis | IIR filters + FFT + spectral features in renderer process | Real-time frequency separation, spectrum/waveform textures, derived features, onset detection |
| Language | TypeScript + Swift | TypeScript for app logic and shaders; Swift for the native `audio_tap` ScreenCaptureKit helper |
| Build | electron-builder | macOS .dmg packaging for distribution |

### Audio Pipeline

```
System Audio (Spotify, Apple Music, etc.)
    ↓
macOS ScreenCaptureKit (system audio loopback)
    ↓
audio_tap (native Swift binary, streams raw float32 stereo PCM at 48kHz to stdout)
    ↓
Electron Main Process (spawns audio_tap, reads stdout)
    ↓
IPC → Renderer Process (audio-data events, raw Buffer chunks)
    ↓
AudioAnalyzer (analyzer.ts) — per-sample processing:
  ├─ IIR 3-band: bass (20–250 Hz), mid (250–4000 Hz), treble (4000–20000 Hz)
  ├─ IIR 6-band: sub_bass, low_bass, low_mid, mid_high, high_mid, high
  └─ Accumulate PCM samples into ring buffer for FFT and waveform texture
    ↓
AudioAnalyzer — per-frame processing:
  ├─ RMS per band → AGC normalization → instant + attenuated smoothing
  ├─ FFT (1024-point) → u_spectrum texture (512 magnitude bins, log-scaled)
  ├─ Waveform ring buffer → u_waveform texture (1024 samples)
  ├─ Spectral features: centroid (brightness), continuous flux (rate of change)
  └─ Onset detector: per-band spectral flux → grouped beat pulses
    ↓
Scene Manager:
  ├─ Routes per-shader beat source (beat_source metadata)
  └─ Passes per-preset params as uniforms
    ↓
Shader Uniforms (updated per frame)
```

### Audio Data Hierarchy — Design Philosophy

**The core insight that distinguishes Phosphene from a naive visualizer:**

Milkdrop's visual magic comes from continuous audio energy driving the feedback loop — not from beat detection. When a kick drum hits, `u_bass` rises instantly because it IS the audio energy. There's zero detection delay, zero jitter. The visual response is coupled directly to the sound.

Phosphene's audio data is organized in layers of decreasing synchronization fidelity:

1. **Continuous energy bands** (`u_bass`, `u_mid`, `u_treble`, 6-band uniforms): The primary driver of visual motion. These are the audio signal itself, smoothed and normalized. Feedback zoom, rotation, color shifts, and geometry should be driven primarily by these values. They are perfectly synchronized by definition.

2. **Spectrum and waveform textures** (`u_spectrum`, `u_waveform`): The richest data available — what makes Phosphene possible on modern GPUs where Milkdrop wasn't. Shaders can map individual frequency bins to visual elements (a ring of particles where each particle's size is a frequency bin, terrain where height IS the spectrum, color gradients mapped to harmonic content). The waveform enables oscilloscope-style drawing and geometry deformation. Perfectly synchronized — computed directly from the current frame's audio samples.

3. **Spectral features** (`u_centroid`, `u_flux`): Derived characteristics of the sound. Centroid captures "brightness" (high when cymbals/vocals dominate, low during bass-heavy passages). Continuous flux captures rate of spectral change (high during busy rhythmic passages, near-zero during sustained notes). Useful for modulating color temperature, visual complexity, scene behavior.

4. **Beat onset pulses** (`u_beat`, `u_beat_bass`, `u_beat_mid`, `u_beat_treble`): Discrete accent events. These add punch — a momentary spike on a detected onset. They should NEVER be the dominant driver of visual motion because they have inherent timing jitter (±80ms) from threshold-crossing detection and can't match the perfect synchronization of continuous values. Use them for accent effects: a flash of brightness, a momentary burst of particles, a brief color shift.

**Rule of thumb for shader authors**: `base_zoom` and `base_rot` (continuous energy) should be 2–4x larger than `beat_zoom` and `beat_rot` (onset pulses). The continuous values do the heavy lifting; the beat adds spice.

#### Why ScreenCaptureKit instead of BlackHole

The original plan used BlackHole (virtual audio loopback driver) with the Web Audio API. This approach failed on macOS Sequoia 15.6.1 due to two issues:

1. **BlackHole loopback broken on Sequoia**: BlackHole 0.6.1's `DoIOOperation` has a timing guard that zeros out the read buffer when `WriteMix` hasn't been called recently enough. CoreAudio's IO scheduling changed in Sequoia, causing this guard to always trigger — the ring buffer receives audio but `ReadInput` never returns it.

2. **Chromium Web Audio API can't read from virtual devices on macOS**: Even when BlackHole was working, Chromium's `getUserMedia` opens the device successfully but delivers silence for virtual audio devices. This is a known Chromium limitation on macOS.

The ScreenCaptureKit approach is better in every way:
- **No virtual driver dependency** — uses Apple's native system audio capture API
- **No Audio MIDI Setup configuration** — no Multi-Output Device needed
- **Process-tap capable** — future versions can capture audio from specific apps (e.g., Spotify only) via `AudioHardwareCreateProcessTap`
- **Apple-supported** — the recommended path forward for system audio on macOS

#### audio_tap Binary

`assets/audio_tap` is a compiled Swift binary that uses ScreenCaptureKit to capture system audio and stream it as raw float32 stereo PCM at 48 kHz to stdout. Source is at `assets/audio_tap.swift`.

**Permissions required**: The binary must be granted "Screen & System Audio Recording" permission in System Settings > Privacy & Security. This is a one-time setup per machine.

**Rebuilding**: If the binary needs recompilation (e.g., after macOS SDK updates):
```bash
swiftc -o assets/audio_tap assets/audio_tap.swift \
  -framework ScreenCaptureKit -framework CoreMedia
```

Note: macOS Command Line Tools (as of early 2026) have a `SwiftBridging` modulemap bug. If compilation fails with "redefinition of module 'SwiftBridging'", run:
```bash
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap.bak
```

### Audio Analysis — Current Implementation

#### AGC (Automatic Gain Control)

All frequency band values are normalized using Milkdrop-style average-tracking AGC before being sent to shaders. This ensures consistent visual reactivity regardless of source volume or genre:

- A slow running average (~5s adaptation time) tracks the "baseline" level per band
- Output = `raw / runningAverage * 0.5`, so average levels map to ~0.5, loud moments reach 0.8–1.0, quiet moments sit at 0.2–0.3
- Two-speed warmup: fast initial adaptation (0.95 rate) stabilizes in ~1s, then switches to moderate rate (0.992) for ~2s settling
- 6-band AGC normalizes against total energy (not per-band), preserving relative differences between bands

#### Smoothing

Two smoothing tiers are computed per frame for the 3-band values, all FPS-independent via `pow(rate, 30/fps)`:

- **Instant** (`u_bass`, `u_mid`, `u_treble`): Fast smoothing for tight audio-reactive motion. Per-band rates: bass 0.65, mid/treble 0.75.
- **Attenuated** (`u_bass_att`, `u_mid_att`, `u_treb_att`): Heavy smoothing (0.95 rate) for slow, flowing motion — analogous to Milkdrop's `_att` values.

The 6-band values use the same per-band smoothing rates as their parent 3-band tier (low bands get bass smoothing, high bands get treble smoothing).

### Uniform Data Available to Shaders

Each frame, the audio analysis module produces and passes the following as shader uniforms:

**Time & resolution:**

| Uniform | Type | Description |
|---------|------|-------------|
| `u_time` | float | Elapsed time in seconds |
| `u_resolution` | vec2 | Viewport resolution in pixels |
| `u_fps` | float | Current smoothed FPS |
| `u_scene_progress` | float | Progress through current scene, 0.0–1.0 |

**3-band instant (AGC-normalized, fast-smoothed) — primary visual drivers:**

| Uniform | Type | Description |
|---------|------|-------------|
| `u_bass` | float | Low frequency energy (20–250 Hz), 0–1 |
| `u_mid` | float | Mid frequency energy (250–4000 Hz), 0–1 |
| `u_treble` | float | High frequency energy (4000–20000 Hz), 0–1 |
| `u_volume` | float | Overall amplitude (average of bass/mid/treble), 0–1 |

**3-band attenuated (slow, for flowing motion):**

| Uniform | Type | Description |
|---------|------|-------------|
| `u_bass_att` | float | Heavily smoothed bass, 0–1 |
| `u_mid_att` | float | Heavily smoothed mid, 0–1 |
| `u_treb_att` | float | Heavily smoothed treble, 0–1 |

**6-band (fine-grained, AGC-normalized):**

| Uniform | Type | Description |
|---------|------|-------------|
| `u_sub_bass` | float | 20–80 Hz (kick drums, 808s) |
| `u_low_bass` | float | 80–250 Hz (bass guitar, low synths) |
| `u_low_mid` | float | 250–1000 Hz (snare body, guitar, vocals) |
| `u_mid_high` | float | 1000–4000 Hz (snare crack, hi-hats, presence) |
| `u_high_mid` | float | 4000–8000 Hz (cymbals, air) |
| `u_high` | float | 8000+ Hz (sibilance, sparkle) |

**Spectrum and waveform textures — the richest audio data (v0.2):**

| Uniform | Type | Description |
|---------|------|-------------|
| `u_spectrum` | sampler2D | FFT magnitude spectrum as a 1D texture (512 bins from 1024-point FFT). Each texel's red channel = magnitude of that frequency bin, log-scaled and normalized. Sample with `texture2D(u_spectrum, vec2(freq_position, 0.5))`. Low frequencies at left (x=0), high at right (x=1). |
| `u_waveform` | sampler2D | Raw time-domain waveform as a 1D texture (1024 samples). Each texel's red channel = sample amplitude, centered at 0.5 (silence), ranging 0–1. Sample with `texture2D(u_waveform, vec2(sample_position, 0.5))`. Enables oscilloscope drawing, geometry deformation, and direct waveform visualization. |

**Spectral features (v0.2):**

| Uniform | Type | Description |
|---------|------|-------------|
| `u_centroid` | float | Spectral centroid, normalized 0–1. Measures the "brightness" or "center of mass" of the frequency spectrum. High when treble/cymbals dominate, low during bass-heavy passages. Useful for color temperature shifts and visual complexity modulation. |
| `u_flux` | float | Continuous spectral flux, normalized 0–1. Measures the rate of change across the entire spectrum. High during busy, rhythmic passages. Near-zero during sustained notes or silence. Distinct from beat detection — this is a smooth, continuous value, not a discrete pulse. Useful for modulating particle emission rates, line thickness, overall visual energy. |

**Beat onset pulses (accent layer — not primary visual driver):**

| Uniform | Type | Description |
|---------|------|-------------|
| `u_beat` | float | Per-shader beat pulse, mapped from beat_bass/mid/treble based on `beat_source` metadata, scaled by `beat_sensitivity`. Spikes to 1.0 on onset, exponentially decays. |
| `u_beat_bass` | float | Bass-band onset pulse (sub_bass + low_bass). 0–1 decaying. |
| `u_beat_mid` | float | Mid-band onset pulse (low_mid + mid_high). 0–1 decaying. |
| `u_beat_treble` | float | Treble-band onset pulse (high_mid + high). 0–1 decaying. |

**Feedback & per-preset params (from scene JSON metadata):**

| Uniform | Type | Description |
|---------|------|-------------|
| `u_prev_frame` | sampler2D | Previous frame's rendered output — enables Milkdrop-style feedback |
| `u_beat_zoom` | float | How much beat pulse drives zoom (accent — should be smaller than base_zoom) |
| `u_beat_rot` | float | How much beat pulse drives rotation (accent) |
| `u_base_zoom` | float | How much continuous bass energy drives zoom (primary driver) |
| `u_base_rot` | float | How much continuous energy drives rotation (primary driver) |
| `u_decay` | float | Feedback frame decay multiplier (0.85–0.95 typical) |

### Beat Detection — Current State

**Status**: Onset detector implemented and validated. Per-band beat pulses wired to uniforms with per-shader routing via `beat_source` metadata. Beat is positioned as an accent layer — continuous energy bands are the primary visual driver.

#### Onset detector (`src/renderer/audio/onset-detector.ts`)

Uses spectral flux on the 6-band IIR RMS values — detects *changes* in per-band energy rather than absolute levels.

Per frame, for each of 6 bands:
1. Compute spectral flux: `max(0, currentRMS - previousRMS)` (half-wave rectified)
2. Store flux in a circular buffer (50 frames ≈ 0.8s at 60fps)
3. Compute adaptive threshold: `median(buffer) × 1.5`
4. Onset fires when flux > threshold AND cooldown has elapsed
5. Per-band cooldowns: low bands (sub_bass, low_bass) = 400ms, mid bands = 200ms, high bands = 150ms

Onsets are grouped into three beat pulses:
- `u_beat_bass`: fires when sub_bass OR low_bass has onset (grouped 400ms cooldown)
- `u_beat_mid`: fires when low_mid OR mid_high has onset (grouped 200ms cooldown)
- `u_beat_treble`: fires when high_mid OR high has onset (grouped 150ms cooldown)
- `u_beat_raw` / composite: fires when ANY band has onset (400ms cooldown)

Pulse decay: `pow(0.6813, 30/fps)` per frame — reaches 0.1 in ~200ms at 60fps.

Per-shader routing: scene metadata `beat_source` field selects which grouped pulse maps to `u_beat`, then scaled by `beat_sensitivity`.

#### Validated onset counts (cross-genre)

| Track | sub_bass | low_bass | low_mid | mid_high | high_mid | high | total |
|-------|----------|----------|---------|----------|----------|------|-------|
| Love Rehab (electronic, ~125 BPM) | 11 | 10 | 20 | 4 | 0 | 1 | 46 |
| So What (jazz, ~136 BPM) | 5 | 2 | 5 | 6 | 2 | 1 | 21 |
| There There (rock, syncopated) | 6 | 7 | 21 | 18 | 16 | 5 | 73 |

These counts are per 5-second window with 400ms low-band cooldowns.

#### Previous approaches tried and abandoned

1. **IIR energy-difference flux** (3-band): Machine-gun firing — IIR filters smear onsets over many frames
2. **Rising-edge accumulation**: IIR filters don't produce clean rise-then-flat patterns — energy oscillates
3. **FFT-based spectral flux** (1024-point, per-bin, dual-rate EMA thresholds): Threshold tuning intractable — too many parameters, different settings needed per genre
4. **Beat-dominant visual design** (beat_zoom >> base_zoom): Onset pulses have inherent ±80ms jitter, which the feedback loop amplifies. Feels out of sync. Continuous energy values are perfectly synchronized because they ARE the audio.

### Visual Scene System

#### Milkdrop-style Feedback Architecture

Every shader operates on the same core visual loop inherited from Milkdrop:

1. **Read previous frame** via `u_prev_frame` (sampler2D)
2. **Apply feedback transforms**: zoom and rotation, driven primarily by continuous energy, with beat accents
3. **Multiply by decay** (`u_decay`, typically 0.85–0.95) — creates trails and persistence
4. **Composite new elements** on top of the decayed/transformed previous frame
5. **Output** becomes next frame's `u_prev_frame`

The per-preset params control feedback personality:

- **High decay (0.95)**: Long trails, smooth evolution, ambient feel
- **Low decay (0.85)**: Short trails, snappy response, aggressive feel
- **High base_zoom/base_rot**: Strong continuous motion from audio energy (primary driver)
- **Moderate beat_zoom/beat_rot**: Accent pulses on top of continuous motion (secondary)

**Scene** = a GLSL fragment shader + a JSON metadata sidecar defining its visual behavior, timing, and beat response.

The scene manager (`scene-manager.ts`) handles:

1. **Scene registry**: Auto-discovers `.glsl` shader files in the shaders directory, each with a `.json` metadata sidecar
2. **Scene sequencing**: Random selection (no immediate repeats)
3. **Scene timing**: Per-scene preferred duration from metadata. Default: 30s.
4. **Crossfade transitions**: 2.5-second crossfade with smoothstep easing
5. **Per-preset params**: Extract feedback and beat params from metadata, pass as uniforms
6. **Beat source routing**: Read `beat_source` from metadata, map appropriate grouped pulse to `u_beat`

### V1 Visual Scenes (Target: 10–14 shaders)

Variety across three aesthetic families, with a mix of band-energy-driven and spectrum/waveform-driven shaders.

**Fluid / Organic**
- Aurora Bands ✅ — curtain-like bands per 6-band frequency, gentle vertical drift, no beat response
- Nebula Flow ✅ — reaction-diffusion nebula
- Fractal noise flow fields (driven by bass energy and spectral centroid for color)

**Geometric / Fractal**
- Kaleidoscope ✅ — 6-fold mirrored sacred geometry, beat rotation accents
- Instrument Rings ✅ — concentric rings per 6-band frequency
- Mandelbrot/Julia set zoom (zoom speed from bass, color palette from centroid)
- Sacred geometry (Flower of Life, pulsing to continuous energy)

**Abstract / Expressionist**
- Spectrum Pulse ✅ — pulsing orb with frequency rings, beat accents
- Waveform Ribbons ✅ — layered frequency ribbons
- **Spectrum Landscape** (new, v0.2) — terrain where height IS the spectrum texture, camera flies through
- **Oscilloscope** (new, v0.2) — classic waveform visualization with artistic treatment, showcases u_waveform
- Color field (Rothko-like blocks shifting with spectral centroid)

**Color Philosophy**
- Rich, saturated palettes — not pastel, not washed out
- Full spectrum: deep purples, electric blues, hot oranges, neon greens
- Each scene defines its own palette, but palettes should shift and breathe with the audio
- Dark backgrounds dominate — the visuals emerge from darkness
- Gradients are first-class: smooth color transitions, not hard edges
- Spectral centroid can modulate palette warmth (low = cool blues/purples, high = warm oranges/pinks)

### UI / Controls

**Default state**: No visible UI. The window is 100% visuals.

**Hidden overlay**: Triggered by mouse movement or a keystroke (e.g., `Space` or `Escape`). Overlay appears with a semi-transparent dark background and shows:

- Audio level meter (confirm signal is being received)
- Scene name
- Fullscreen toggle (also via `F` key)
- Quit button (also via `Cmd+Q`)

**Keyboard shortcuts (always active, no overlay required):**

| Key | Action |
|-----|--------|
| `F` | Toggle fullscreen |
| `Space` | Toggle overlay visibility |
| `N` | Skip to next scene (with transition) |
| `Escape` | Show overlay / exit fullscreen |
| `Cmd+Q` | Quit |

### Windowed vs. Fullscreen

- App launches in windowed mode (reasonable default size, e.g., 1280×720)
- User can toggle fullscreen with `F` key
- Fullscreen uses the display the window is currently on (important for multi-monitor setups with projectors)
- Window is freely resizable; shaders use `u_resolution` to adapt
- Window title bar hidden in fullscreen, visible in windowed mode

---

## Project Structure

```
phosphene/
├── package.json
├── tsconfig.json
├── electron-builder.yml
├── assets/
│   ├── audio_tap              # Compiled Swift binary — ScreenCaptureKit system audio capture
│   └── audio_tap.swift        # Source for audio_tap
├── src/
│   ├── main/
│   │   └── index.ts           # App entry, window creation, spawns audio_tap, IPC bridge
│   ├── renderer/
│   │   ├── index.html         # Shell HTML
│   │   ├── index.ts           # Renderer entry, render loop
│   │   ├── audio/
│   │   │   ├── analyzer.ts         # PCM → IIR bands → AGC → smoothing → FFT → spectral features
│   │   │   └── onset-detector.ts   # Per-band spectral flux onset detection → beat pulses
│   │   ├── visuals/
│   │   │   ├── renderer.ts         # Three.js / WebGL setup, fullscreen quad, feedback texture ping-pong
│   │   │   ├── scene-manager.ts    # Scene lifecycle, transitions, sequencing, per-preset params, beat routing
│   │   │   └── shaders/            # GLSL fragment shaders + JSON metadata sidecars
│   │   │       ├── spectrum-pulse.glsl / .json     # Pulsing orb (abstract)
│   │   │       ├── kaleidoscope.glsl / .json       # Sacred geometry spiral (geometric)
│   │   │       ├── aurora-bands.glsl / .json       # Per-frequency aurora curtains (fluid)
│   │   │       ├── nebula-flow.glsl / .json        # Reaction-diffusion nebula (fluid)
│   │   │       ├── instrument-rings.glsl / .json   # Concentric 6-band rings (geometric)
│   │   │       └── waveform-ribbons.glsl / .json   # Layered frequency ribbons (abstract)
│   │   └── ui/
│   │       └── overlay.ts     # Hidden control overlay (planned for v0.4)
│   └── shared/
│       └── types.ts           # Shared type definitions (AudioUniforms, SceneMetadata, SceneParams)
└── README.md                  # Setup instructions
```

---

## Setup & Distribution

### Prerequisites (documented in README)

1. **macOS 14+** (Sonoma or later — required for ScreenCaptureKit system audio)
2. **Node.js 18+** (for building from source)
3. **Screen & System Audio Recording permission** granted to `assets/audio_tap`:
   - System Settings > Privacy & Security > Screen & System Audio Recording
   - Click +, press Cmd+Shift+G, navigate to `<project>/assets/audio_tap`
   - Toggle ON

No virtual audio driver (BlackHole, Soundflower, etc.) is required.

### Install & Run

```bash
git clone https://github.com/hoaxpoet/phosphene.git
cd phosphene
npm install
npm start          # Development mode
npm run build      # Package as .dmg
```

### README Must Include

- What Phosphene is (one paragraph)
- Screenshots/GIF of visuals
- Screen & System Audio Recording permission setup instructions
- Build and run instructions
- Keyboard shortcuts
- How to contribute (adding new shaders)
- License (MIT)

---

## Release Plan

### v0.1 — Proof of Life ✅ COMPLETE
**Goal**: Audio in, visuals out. Confirm the pipeline works end to end.

- Electron app opens, captures system audio via ScreenCaptureKit
- IIR 3-band + 6-band filtering with AGC normalization
- Milkdrop-style feedback architecture (u_prev_frame, zoom, rotation, decay)
- Per-preset params system via JSON metadata

**Achieved beyond original scope**: 6-band analysis, AGC, attenuated smoothing, scene manager with crossfade transitions, 6 working shaders, per-preset params, beat onset detection with per-shader routing.

### v0.2 — Rich Audio Data + Rebalanced Visuals 🔄 IN PROGRESS
**Goal**: Give shaders the richest possible audio data. Visuals feel tightly synchronized because they're driven by continuous audio energy, with spectrum/waveform textures enabling new visual possibilities.

**Completed**:
- Scene manager with auto-discovery, crossfade transitions (2.5s smoothstep), random sequencing
- 6 shaders across 3 aesthetic families
- Per-preset params system (beat_zoom, beat_rot, base_zoom, base_rot, decay, beat_sensitivity, beat_source)
- Beat onset detection: per-band spectral flux with adaptive median threshold, validated across genres
- Per-shader beat routing via beat_source metadata
- All shaders clamp output with `min(color, vec3(1.0))` to prevent white clipping

**Remaining work — spectrum and waveform textures**:
1. Accumulate PCM samples into a ring buffer in analyzer.ts (1024 samples for FFT, 1024 for waveform)
2. Implement 1024-point FFT (radix-2). Compute magnitude of first 512 bins. Log-scale and normalize to 0–1.
3. Upload spectrum magnitudes as a 512×1 float texture (`u_spectrum`) each frame
4. Upload waveform ring buffer as a 1024×1 float texture (`u_waveform`) each frame
5. In renderer.ts, create the two DataTextures and update them per frame before the shader draw call

**Remaining work — spectral features**:
6. Compute spectral centroid from FFT magnitudes: `sum(bin * magnitude[bin]) / sum(magnitude[bin])`, normalize to 0–1. Pass as `u_centroid` float uniform.
7. Compute continuous spectral flux: `sum(max(0, magnitude[bin] - prev_magnitude[bin]))` across all bins, normalize against running average. Pass as `u_flux` float uniform.

**Remaining work — rebalance presets**:
8. Update all shader JSON metadata: multiply `base_zoom` and `base_rot` by 3, divide `beat_zoom` and `beat_rot` by 3. Continuous energy becomes the dominant visual driver, beat becomes accent.

**Remaining work — new shaders showcasing rich data**:
9. Spectrum Landscape shader: terrain heightmap from `u_spectrum`, fly-through camera, color from centroid
10. Oscilloscope shader: draw `u_waveform` as a glowing line with artistic treatment (thickness from volume, color from centroid)

**Implementation order**: Steps 1–5 (textures), then 6–7 (features), then 8 (rebalance), then 9–10 (new shaders). Each step is a separate Claude Code task with a clear done condition.

**Cross-genre validation targets** (beat detection — already validated):
1. Electronic (Chaim — "Love Rehab"): sub_bass ~11/5s
2. Jazz (Miles Davis — "So What"): sub_bass ~5/5s, not continuous
3. Rock (Radiohead — "There There"): sub_bass ~6/5s, syncopated
4. Ambient: minimal onsets

**Success criteria**: Play any genre for 5 minutes. Visuals feel tightly synchronized because primary motion tracks continuous audio energy. Spectrum-based shaders reveal musical detail that band-energy shaders can't. Beat accents add punch without dominating.

### v0.3 — Visual Polish + Scene Library (2–3 weeks)
**Goal**: Enough variety and visual quality to use at a real listening party.

- 10–14 shaders across all three aesthetic families
- Mix of band-energy-driven and spectrum/waveform-driven shaders
- Color palettes refined — rich, saturated, psychedelic
- Spectral centroid modulates palette warmth across scenes
- Transition smoothness polished
- Shaders use `u_scene_progress` for evolution over their lifetime
- Per-shader base/beat param ratios tuned per aesthetic

**Success criteria**: Run it for a full 20-minute mix. No visual gets boring. Transitions feel natural. At least 3 shaders use spectrum/waveform textures in visually distinct ways.

### v0.4 — UI + Fullscreen + Distribution (1–2 weeks)
**Goal**: Usable by friends without hand-holding.

- Hidden overlay UI (audio level meter, scene name, fullscreen toggle)
- All keyboard shortcuts working
- Fullscreen/windowed mode with multi-monitor support
- electron-builder produces installable .dmg
- README with full setup documentation
- GitHub repo public

**Success criteria**: Send the repo link to Thai. He installs it, grants Screen Recording permission, runs Phosphene with zero help.

### v1.0 — First Public Release
**Goal**: Stable, performant, delightful. The best open-source music visualizer on macOS.

- Performance optimization (consistent 60fps at 1080p on Apple Silicon)
- Edge case handling (no audio input, device disconnection, sleep/wake)
- Bug fixes from v0.4 user testing
- At least 10 polished shaders (mix of band-energy and spectrum/waveform driven)
- Versioned release on GitHub with .dmg download
- Contribution guide for shader authors (template, uniform reference, testing instructions)

---

## Future Roadmap (Post-V1)

### v1.x — Music Awareness
**Goal**: Phosphene knows what you're listening to.

- Integrate with Spotify Web API or Apple Music API to identify currently playing track
- Pull metadata: artist, album, year, genre, tempo (BPM), energy, valence
- Use genre/mood to influence scene selection (e.g., prefer fluid shaders for ambient, geometric for electronic)
- Use BPM to set base animation speeds (rotation rates, drift speeds tuned to tempo)
- Display song info in the overlay (artist, track name, album art)
- Autocorrelation-based tempo estimation as fallback when no API is available

### v2.x — Adaptive Intelligence
**Goal**: Phosphene learns from you.

This is where Phosphene diverges from Milkdrop/ProjectM entirely. The visualizer develops a personalized model of the listener's preferences.

**Behavioral signals**:
- Which scenes does the user watch through vs. skip (`N` key)?
- How long does the user spend with each shader/music combination?
- Does the user return to the same scenes for similar music?
- Time of day, listening session duration, genre patterns

**Local learning model**:
- All data stays on-device — no cloud, no telemetry
- Scene affinity scores: per-shader preference weights, updated over time
- Genre-to-scene mapping: learned associations between musical characteristics and preferred visuals
- Session context: time-of-day preferences (energetic scenes in evening, ambient in morning)

**Adaptive behavior**:
- Scene selection weighted by learned preferences instead of random
- Transition timing adapts to musical structure (longer scenes for ambient, shorter for high-energy)
- Color palette selection influenced by genre associations
- "Shuffle" mode respects learned preferences while still introducing variety

**User controls**:
- Heart/skip buttons in overlay for explicit preference signals
- "Surprise me" mode that deliberately picks low-familiarity scenes
- Preference reset option
- Export/import preference profiles

### v3.x — Contextual Visuals
**Goal**: Visuals respond to meaning, not just sound.

- Lyrics awareness (pull lyrics from Genius or Musixmatch API)
- Thematic visual responses (e.g., water imagery for ocean-themed lyrics, fire for intensity)
- Artist-associated visual signatures (color palettes, geometric styles)
- AI-generated visual prompts based on song metadata + lyrics + audio features
- Harmonic-percussive audio separation: harmonic content drives smooth flowing motion, percussive content drives sharp accents (cleaner separation than beat detection alone)

### v4.x — Generative Canvas
**Goal**: Each song produces a unique visual artifact.

- "Painting mode": a blank canvas that builds a composition over the duration of a song
- Musical structure awareness (verse/chorus/bridge detection) drives composition phases
- Each song produces a unique, exportable image
- AI-directed layout, color, and form based on musical structure
- Gallery view of past paintings, organized by artist/genre/date
- Print-resolution export

### vNext — Platform & Community
- Windows support (WASAPI loopback for audio capture)
- Mobile companion app (iOS) — receives audio features over local network, renders locally
- User-configurable scene timing and transition styles
- Community shader gallery — browse, install, and rate shaders
- Shader editor with live preview (hot-reload .glsl with audio input)
- App-specific audio capture via `AudioHardwareCreateProcessTap` (capture Spotify only, etc.)
- VR/spatial computing output (Apple Vision Pro)

---

## Development Constraints

- **Budget**: Claude Code Max subscription ($100/month). No paid APIs, no cloud infrastructure for V1.
- **Team**: Matt (product/design direction) + Claude Code (implementation). Friends contribute post-v1.0.
- **Platform**: macOS only for V1. Mac mini is the primary development and deployment target.
- **Performance target**: 60fps at 1080p resolution. Shaders must be optimized for real-time rendering. FFT and texture uploads must not cause frame drops.
- **Dependencies**: Minimize external dependencies. No system-level dependencies required. FFT should be implemented in TypeScript (no native module dependency) or use a lightweight JS library.

---

## Resolved Decisions

1. **License**: MIT. Fully open for friend collaboration and community contributions.
2. **GitHub org**: Personal repo under Matt's GitHub account.
3. **Shader contributions**: Yes — standard shader template, testing harness, and clear contribution docs so friends can add scenes by dropping in a `.glsl` file.
4. **Audio capture strategy**: ScreenCaptureKit via a native Swift helper binary (`audio_tap`). Requires "Screen & System Audio Recording" permission. No virtual audio driver needed.
   - **Primary path (default)**: ScreenCaptureKit system audio loopback — works out of the box on macOS 14+
   - **Future: process tap**: `AudioHardwareCreateProcessTap` for app-specific capture (e.g., capture only Spotify)
   - **Legacy fallback**: BlackHole / Loopback support as optional manual mode for users who prefer it
5. **Scene timing**: Varies by scene. Each shader declares a preferred duration in its metadata. Future releases will expose this as a user-configurable setting.
6. **Electron version**: 41+ required. Earlier versions have broken ScreenCaptureKit audio loopback integration.
7. **Audio analysis approach**: IIR band-pass filters in the renderer process (not Web Audio API AnalyserNode). This avoids Chromium's broken virtual device handling and gives direct control over frequency separation.
8. **Visual feedback architecture**: Milkdrop-style previous-frame feedback with per-shader zoom, rotation, and decay parameters. This is the core visual identity of Phosphene.
9. **Audio data hierarchy**: Continuous energy bands are the primary visual driver (perfectly synchronized). Spectrum/waveform textures are the richest data (also perfectly synchronized). Beat onset pulses are accent effects only (inherent ±80ms jitter). This hierarchy was learned the hard way — beat-dominant designs feel out of sync, while continuous-energy-dominant designs feel locked to the music.
10. **Beat detection algorithm**: Spectral flux with adaptive median threshold, per-band onset detection with band-appropriate cooldowns (400ms low, 200ms mid, 150ms high). Pulse decay `pow(0.6813, 30/fps)`. Energy-threshold, rising-edge, FFT-based, and beat-dominant approaches were tried and abandoned.
11. **Per-shader beat customization**: Each shader declares `beat_source` in its JSON metadata. Geometric shaders typically use "bass", fluid shaders use "composite" or set beat_sensitivity to 0.
12. **Spectrum/waveform as textures**: The richest audio data goes to the GPU as textures, not reduced to scalar uniforms. This is the key architectural advantage over Milkdrop — modern GPUs can process 512+ frequency bins per fragment, enabling visual detail that was impossible in 2001.
13. **Learning stays local**: All future preference learning and adaptation will be on-device only. No cloud, no telemetry, no data leaves the machine.

---

## Appendix: Shader Development Reference

### Fragment Shader Template

```glsl
#ifdef GL_ES
precision mediump float;
#endif

// Time & resolution
uniform float u_time;
uniform vec2 u_resolution;
uniform float u_scene_progress;

// 3-band audio (fast-smoothed, AGC-normalized, 0–1) — PRIMARY VISUAL DRIVERS
uniform float u_bass;
uniform float u_mid;
uniform float u_treble;
uniform float u_volume;

// 3-band attenuated (slow-smoothed — use for flowing, ambient motion)
uniform float u_bass_att;
uniform float u_mid_att;
uniform float u_treb_att;

// 6-band audio (AGC-normalized, 0–1)
uniform float u_sub_bass;   // 20–80 Hz
uniform float u_low_bass;   // 80–250 Hz
uniform float u_low_mid;    // 250–1000 Hz
uniform float u_mid_high;   // 1000–4000 Hz
uniform float u_high_mid;   // 4000–8000 Hz
uniform float u_high;       // 8000+ Hz

// Spectrum & waveform textures — RICHEST AUDIO DATA
uniform sampler2D u_spectrum;   // 512 bins, sample x=0 (low freq) to x=1 (high freq)
uniform sampler2D u_waveform;   // 1024 samples, red channel = amplitude centered at 0.5

// Spectral features
uniform float u_centroid;   // Spectral brightness, 0–1
uniform float u_flux;       // Rate of spectral change, 0–1

// Beat (accent layer — source determined by beat_source in scene metadata)
uniform float u_beat;        // Mapped per-shader: spikes to 1.0 on onset, decays
uniform float u_beat_bass;   // Bass-only onset pulse
uniform float u_beat_mid;    // Mid-only onset pulse
uniform float u_beat_treble; // Treble-only onset pulse

// Feedback (Milkdrop-style)
uniform sampler2D u_prev_frame;

// Per-preset params (from scene JSON metadata)
uniform float u_beat_zoom;   // Zoom on beat (ACCENT — keep smaller than base_zoom)
uniform float u_beat_rot;    // Rotation on beat (ACCENT)
uniform float u_base_zoom;   // Continuous zoom from audio energy (PRIMARY)
uniform float u_base_rot;    // Continuous rotation from audio energy (PRIMARY)
uniform float u_decay;       // Feedback decay rate (0.85–0.95 typical)

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;

    // === FEEDBACK ===
    // Continuous energy is the PRIMARY driver. Beat is an accent on top.
    float zoom = 1.0 + u_base_zoom * u_bass + u_beat_zoom * u_beat;
    float rot = u_base_rot * u_mid + u_beat_rot * u_beat;
    vec2 feedUV = uv - 0.5;
    feedUV /= zoom;
    float ca = cos(rot); float sa = sin(rot);
    feedUV = vec2(feedUV.x*ca - feedUV.y*sa, feedUV.x*sa + feedUV.y*ca);
    feedUV += 0.5;
    vec3 prev = texture2D(u_prev_frame, feedUV).rgb * u_decay;

    // === NEW ELEMENTS ===
    vec3 newColor = vec3(0.0);

    // Example: read spectrum texture (frequency bin at 25% = ~3kHz)
    // float specVal = texture2D(u_spectrum, vec2(0.25, 0.5)).r;

    // Example: read waveform texture (draw oscilloscope)
    // float waveY = texture2D(u_waveform, vec2(uv.x, 0.5)).r;
    // float waveDist = abs(uv.y - waveY);
    // newColor += vec3(1.0) * smoothstep(0.02, 0.0, waveDist);

    // Example: use spectral centroid for color temperature
    // float hue = mix(0.6, 0.05, u_centroid); // blue when dark, orange when bright

    // === COMPOSITE ===
    vec3 color = prev + newColor;
    color = min(color, vec3(1.0)); // Prevent white clipping from feedback accumulation

    gl_FragColor = vec4(color, 1.0);
}
```

### Adding a New Shader

1. Create a new `.glsl` file in `src/renderer/visuals/shaders/`
2. Create a matching `.json` metadata file alongside it
3. Use the standard uniform interface and feedback pattern above
4. The scene manager auto-discovers shaders by scanning the directory — no manual registration needed
5. Remember: `base_zoom`/`base_rot` should be 2–4x larger than `beat_zoom`/`beat_rot`

### Scene Metadata Format

```json
{
  "name": "Kaleidoscope",
  "family": "geometric",
  "duration": 25,
  "description": "Sacred geometry spiral — explosive beat rotation",
  "author": "Matt",
  "beat_source": "composite",
  "beat_zoom": 0.05,
  "beat_rot": 0.05,
  "base_zoom": 0.12,
  "base_rot": 0.06,
  "decay": 0.91,
  "beat_sensitivity": 1.2
}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | yes | — | Display name shown in overlay |
| `family` | string | yes | — | Aesthetic family: `"fluid"`, `"geometric"`, `"abstract"` |
| `duration` | number | no | 30 | Preferred scene duration in seconds |
| `description` | string | no | — | Brief description of the visual |
| `author` | string | no | — | Shader author for credits |
| `beat_source` | string | no | `"bass"` | Which onset signal drives `u_beat`: `"bass"`, `"mid"`, `"treble"`, `"composite"` |
| `beat_zoom` | number | no | 0.03 | How much beat pulse drives zoom (accent — keep smaller than base_zoom) |
| `beat_rot` | number | no | 0.01 | How much beat pulse drives rotation (accent) |
| `base_zoom` | number | no | 0.12 | How much continuous bass energy drives zoom (primary driver) |
| `base_rot` | number | no | 0.03 | How much continuous energy drives rotation (primary driver) |
| `decay` | number | no | 0.955 | Feedback decay per frame. 0.85 = short trails. 0.95 = long trails. |
| `beat_sensitivity` | number | no | 1.0 | Multiplier on beat pulse. 0.0 = ignore beats. Range 0–3.0. |

### Performance Guidelines

- Avoid deep loops in fragment shaders (keep iteration counts reasonable)
- Use `smoothstep` over `if/else` for GPU-friendly branching
- Texture lookups (prev_frame, spectrum, waveform) are fast on modern GPUs — use them freely
- Feedback is essentially free (one texture read + multiply) — always use it
- Spectrum texture: reading all 512 bins in a loop is fine on Apple Silicon. On older GPUs, sample selectively.
- Target: shader must maintain 60fps at 1920×1080 on Apple Silicon GPU
