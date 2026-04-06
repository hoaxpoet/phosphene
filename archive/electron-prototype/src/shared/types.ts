export interface AudioUniforms {
  u_time: number;
  u_bass: number;
  u_mid: number;
  u_treble: number;
  u_volume: number;
  u_bass_att: number;
  u_mid_att: number;
  u_treb_att: number;
  u_beat_raw: number;     // Composite beat pulse (any band onset), 0–1
  u_beat_bass: number;    // Bass-only onset pulse, 0–1
  u_beat_mid: number;     // Mid-only onset pulse, 0–1
  u_beat_treble: number;  // Treble-only onset pulse, 0–1
  u_sub_bass: number;
  u_low_bass: number;
  u_low_mid: number;
  u_mid_high: number;
  u_high_mid: number;
  u_high: number;
  u_resolution: [number, number];
  u_scene_progress: number;
  u_fps: number;
  u_centroid: number;            // Spectral centroid, normalized 0–1
  u_flux: number;                // Continuous spectral flux, normalized 0–1
  spectrumData: Float32Array;   // 512 log-scaled FFT magnitudes, 0–1
  waveformData: Float32Array;   // 1024 samples centered at 0.5
}

export type BeatSource = 'bass' | 'mid' | 'treble' | 'composite';

export interface SceneParams {
  beat_zoom: number;        // How much to zoom on beat (0.0–0.3)
  beat_rot: number;         // How much to rotate on beat (0.0–0.1)
  base_zoom: number;        // Zoom from sustained bass (0.0–0.1)
  base_rot: number;         // Rotation from sustained audio (0.0–0.05)
  decay: number;            // Feedback decay (0.9–0.99)
  beat_sensitivity: number; // Multiplier for beat pulse (0.0–8.0)
  beat_source: BeatSource;  // Which band's onset drives u_beat
}

export interface SceneMetadata {
  name: string;
  family: 'fluid' | 'geometric' | 'abstract';
  duration?: number;
  description?: string;
  author?: string;
  // Per-preset motion params (optional, defaults provided)
  beat_zoom?: number;
  beat_rot?: number;
  base_zoom?: number;
  base_rot?: number;
  decay?: number;
  beat_sensitivity?: number;
  beat_source?: BeatSource;
}
