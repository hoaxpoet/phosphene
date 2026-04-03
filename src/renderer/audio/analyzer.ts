import { AudioUniforms } from '../../shared/types';
import { OnsetDetector } from './onset-detector';

const SAMPLE_RATE = 48000;
const FFT_SIZE = 1024;
const SPECTRUM_BINS = FFT_SIZE / 2; // 512

// Per-band smoothing: bass faster for tight beat response, mid/treble smoother
const BASS_SM = 0.65;
const MID_SM = 0.75;
const TREB_SM = 0.75;

// Attenuated smoothing (slow, for smooth flowing motion — like Milkdrop's _att values)
const ATT_SMOOTHING = 0.95;

// 6-band cutoffs
const BAND_CUTOFFS = [80, 250, 1000, 4000, 8000];

export class AudioAnalyzer {
  private startTime: number = 0;
  private lastFrameTime: number = 0;

  // Instant smoothed values
  private smoothBass: number = 0;
  private smoothMid: number = 0;
  private smoothTreble: number = 0;
  private smoothVolume: number = 0;

  // Attenuated (heavily smoothed) values
  private attBass: number = 0;
  private attMid: number = 0;
  private attTreble: number = 0;

  // 6-band smoothed values
  private smoothBands: number[] = [0, 0, 0, 0, 0, 0];

  // AGC: Milkdrop-style average-tracking (not peak-tracking).
  // Output = raw / runningAverage * 0.5 → centers at ~0.5,
  // loud moments → 0.8-1.0, quiet moments → 0.2-0.3.
  private agcAvgBass: number = 0.001;
  private agcAvgMid: number = 0.001;
  private agcAvgTreble: number = 0.001;
  private agcAvgBands: number[] = [0.001, 0.001, 0.001, 0.001, 0.001, 0.001];

  // Frame counter (for AGC warmup)
  private frameCount: number = 0;

  // Onset detector (6-band spectral flux, also logs to console)
  private onsetDetector: OnsetDetector = new OnsetDetector();

  // Beat pulse state — each fires independently, decays per frame
  private pulseBass: number = 0;     // sub_bass OR low_bass onset
  private pulseMid: number = 0;      // low_mid OR mid_high onset
  private pulseTreble: number = 0;   // high_mid OR high onset
  private pulseComposite: number = 0; // any band onset, own cooldown
  private lastCompositeTime: number = 0;
  private lastBassTime: number = 0;
  private lastMidTime: number = 0;
  private lastTrebleTime: number = 0;
  // Grouped pulse cooldowns
  private static readonly BASS_COOLDOWN_MS = 400;
  private static readonly MID_COOLDOWN_MS = 200;
  private static readonly TREBLE_COOLDOWN_MS = 150;
  private static readonly COMPOSITE_COOLDOWN_MS = 400;
  // Pulse decay: pow(0.6813, 30/fps) per frame. At 60fps = 0.8254/frame → reaches 0.1 in 12 frames (200ms).
  private static readonly PULSE_DECAY = 0.6813;

  // Beat diagnostic: track averages and active% over 5-second windows
  private beatDiagStartTime: number = 0;
  private beatDiagFrames: number = 0;
  private beatDiagSumComposite: number = 0;
  private beatDiagSumBass: number = 0;
  private beatDiagSumMid: number = 0;
  private beatDiagSumTreble: number = 0;
  private beatDiagActiveComposite: number = 0;
  private beatDiagActiveBass: number = 0;
  private beatDiagActiveMid: number = 0;
  private beatDiagActiveTreble: number = 0;

  // Raw (pre-smoothing) values for diagnostic
  private lastRawBass: number = 0;
  private lastRawMid: number = 0;
  private lastRawTreble: number = 0;

  // IIR filter states
  private bassLpState: number = 0;
  private trebleHpState: number = 0;
  private prevSample: number = 0;
  private lpStates: number[] = [0, 0, 0, 0, 0];

  // Accumulators
  private bassAccum: number = 0;
  private midAccum: number = 0;
  private trebleAccum: number = 0;
  private volumeAccum: number = 0;
  private bandAccums: number[] = [0, 0, 0, 0, 0, 0];
  private accumCount: number = 0;
  private hasData: boolean = false;

  // Ring buffers for FFT and waveform (written per-sample, read per-frame)
  private fftRingBuffer: Float32Array = new Float32Array(FFT_SIZE);
  private fftRingPos: number = 0;
  private waveformRingBuffer: Float32Array = new Float32Array(FFT_SIZE);
  private waveformRingPos: number = 0;

  // Pre-computed Hanning window
  private hanningWindow: Float32Array = new Float32Array(FFT_SIZE);

  // FFT output arrays (reused each frame)
  private fftReal: Float64Array = new Float64Array(FFT_SIZE);
  private fftImag: Float64Array = new Float64Array(FFT_SIZE);
  private spectrumData: Float32Array = new Float32Array(SPECTRUM_BINS);
  private waveformData: Float32Array = new Float32Array(FFT_SIZE);

  // Previous frame's FFT magnitudes (for spectral flux)
  private prevSpectrumMags: Float32Array = new Float32Array(SPECTRUM_BINS);

  // Spectral features: centroid and flux
  private smoothCentroid: number = 0;
  private smoothFlux: number = 0;
  private fluxAgcAvg: number = 0.001;  // Running average for flux AGC normalization
  private featuresLoggedOnce: boolean = false;
  private featuresAudioDetectedTime: number = 0;

  // One-time FFT verification log
  private fftLoggedOnce: boolean = false;

  private lpAlphas: number[] = [];
  private fps: number = 60;

  async initialize(): Promise<boolean> {
    try {
      const { ipcRenderer } = require('electron');

      this.lpAlphas = BAND_CUTOFFS.map(f => Math.exp(-2 * Math.PI * f / SAMPLE_RATE));
      const bassAlpha = Math.exp(-2 * Math.PI * 250 / SAMPLE_RATE);
      const trebleAlpha = Math.exp(-2 * Math.PI * 4000 / SAMPLE_RATE);

      // Pre-compute Hanning window
      for (let i = 0; i < FFT_SIZE; i++) {
        this.hanningWindow[i] = 0.5 * (1 - Math.cos(2 * Math.PI * i / (FFT_SIZE - 1)));
      }

      let ipcCount = 0;
      ipcRenderer.on('audio-data', (_event: any, data: any) => {
        ipcCount++;
        if (ipcCount <= 3) {
          console.log(`[Phosphene] IPC #${ipcCount}: type=${typeof data}, constructor=${data?.constructor?.name}, length=${data?.length ?? data?.byteLength ?? 'N/A'}`);
        }

        // Handle multiple possible data types from Electron IPC
        let chunk: Buffer;
        if (Buffer.isBuffer(data)) {
          chunk = data;
        } else if (data instanceof Uint8Array) {
          chunk = Buffer.from(data.buffer, data.byteOffset, data.byteLength);
        } else if (data instanceof ArrayBuffer) {
          chunk = Buffer.from(data);
        } else {
          // Unknown type — try to convert
          chunk = Buffer.from(data);
        }

        if (!this.hasData && chunk.length > 0) {
          this.hasData = true;
          console.log(`[Phosphene] First audio chunk: ${chunk.length} bytes, first float: ${chunk.length >= 4 ? chunk.readFloatLE(0).toFixed(6) : 'N/A'}`);
        }

        for (let i = 0; i + 7 < chunk.length; i += 8) {
          const left = chunk.readFloatLE(i);
          const right = chunk.readFloatLE(i + 4);
          const sample = (left + right) * 0.5;

          // 3-band
          this.bassLpState = this.bassLpState * bassAlpha + sample * (1 - bassAlpha);
          const bassSample = this.bassLpState;
          this.trebleHpState = trebleAlpha * (this.trebleHpState + sample - this.prevSample);
          this.prevSample = sample;
          const trebleSample = this.trebleHpState;
          const midSample = sample - bassSample - trebleSample;

          this.bassAccum += bassSample * bassSample;
          this.midAccum += midSample * midSample;
          this.trebleAccum += trebleSample * trebleSample;
          this.volumeAccum += sample * sample;

          // 6-band
          const lpOutputs: number[] = [];
          for (let b = 0; b < 5; b++) {
            this.lpStates[b] = this.lpStates[b] * this.lpAlphas[b] + sample * (1 - this.lpAlphas[b]);
            lpOutputs.push(this.lpStates[b]);
          }
          const bandSamples = [
            lpOutputs[0],
            lpOutputs[1] - lpOutputs[0],
            lpOutputs[2] - lpOutputs[1],
            lpOutputs[3] - lpOutputs[2],
            lpOutputs[4] - lpOutputs[3],
            sample - lpOutputs[4],
          ];
          for (let b = 0; b < 6; b++) {
            this.bandAccums[b] += bandSamples[b] * bandSamples[b];
          }

          this.accumCount++;

          // Write mono sample into ring buffers for FFT and waveform
          this.fftRingBuffer[this.fftRingPos] = sample;
          this.fftRingPos = (this.fftRingPos + 1) & (FFT_SIZE - 1);
          this.waveformRingBuffer[this.waveformRingPos] = sample;
          this.waveformRingPos = (this.waveformRingPos + 1) & (FFT_SIZE - 1);
        }

      });

      this.startTime = performance.now();
      this.lastFrameTime = this.startTime;
      console.log('[Phosphene] Audio analyzer initialized (ScreenCaptureKit IPC mode)');
      return true;
    } catch (err) {
      console.error('[Phosphene] Audio initialization failed:', err);
      return false;
    }
  }

  getUniforms(width: number, height: number): AudioUniforms {
    const now = performance.now();
    const time = (now - this.startTime) / 1000.0;
    const dt = (now - this.lastFrameTime) / 1000.0;
    this.lastFrameTime = now;

    // FPS tracking (smoothed)
    if (dt > 0) {
      this.fps = this.fps * 0.95 + (1.0 / dt) * 0.05;
    }

    // FPS-independent smoothing: pow(baseRate, 30/fps)
    // At 60fps, pow(0.82, 0.5) ≈ 0.906 per frame
    // At 30fps, pow(0.82, 1.0) = 0.82 per frame — same visual result
    const fpsRatio = 30.0 / Math.max(this.fps, 1);
    const smBass = Math.pow(BASS_SM, fpsRatio);
    const smMid = Math.pow(MID_SM, fpsRatio);
    const smTreb = Math.pow(TREB_SM, fpsRatio);
    const smAtt = Math.pow(ATT_SMOOTHING, fpsRatio);
    this.frameCount++;

    if (this.accumCount > 0) {
      const rawBass = Math.sqrt(this.bassAccum / this.accumCount);
      const rawMid = Math.sqrt(this.midAccum / this.accumCount);
      const rawTreble = Math.sqrt(this.trebleAccum / this.accumCount);
      const rawVolume = Math.sqrt(this.volumeAccum / this.accumCount);

      // 6-band raw RMS
      const rawBands: number[] = [];
      for (let b = 0; b < 6; b++) {
        rawBands.push(Math.sqrt(this.bandAccums[b] / this.accumCount));
        this.bandAccums[b] = 0;
      }

      this.bassAccum = 0;
      this.midAccum = 0;
      this.trebleAccum = 0;
      this.volumeAccum = 0;
      this.accumCount = 0;

      this.lastRawBass = rawBass;
      this.lastRawMid = rawMid;
      this.lastRawTreble = rawTreble;

      // AGC: Milkdrop-style average-tracking.
      // Slow running average (~5s adaptation) represents the "baseline" level.
      // Output = raw / average * 0.5, so:
      //   average level → 0.5
      //   loud hit (2x avg) → 1.0
      //   quiet moment (0.5x avg) → 0.25
      // This preserves dynamics for all genres without fixed scale factors.
      // Two-speed AGC: fast initial (0.95) stabilizes in ~1s, then moderate (0.992) ~2s
      const agcBaseRate = this.frameCount < 120 ? 0.95 : 0.992;
      const agcRate = Math.pow(agcBaseRate, fpsRatio);

      this.agcAvgBass = this.agcAvgBass * agcRate + rawBass * (1 - agcRate);
      this.agcAvgMid = this.agcAvgMid * agcRate + rawMid * (1 - agcRate);
      this.agcAvgTreble = this.agcAvgTreble * agcRate + rawTreble * (1 - agcRate);

      const scaledBass = Math.min(1.0, rawBass / Math.max(this.agcAvgBass, 0.0005) * 0.5);
      const scaledMid = Math.min(1.0, rawMid / Math.max(this.agcAvgMid, 0.0005) * 0.5);
      const scaledTreble = Math.min(1.0, rawTreble / Math.max(this.agcAvgTreble, 0.0005) * 0.5);
      const scaledVolume = Math.min(1.0, (scaledBass + scaledMid + scaledTreble) / 3.0);

      // Feed raw (pre-AGC) 6-band RMS to onset detector
      const onsets = this.onsetDetector.process(rawBands.slice(), now);

      // Fire per-band beat pulses with cooldowns to prevent sub-band compounding
      // [0]=sub_bass [1]=low_bass [2]=low_mid [3]=mid_high [4]=high_mid [5]=high
      if ((onsets[0] || onsets[1]) && (now - this.lastBassTime) > AudioAnalyzer.BASS_COOLDOWN_MS) {
        const interval = this.lastBassTime > 0 ? (now - this.lastBassTime) / 1000 : 0;
        const timeSec = (now - this.startTime) / 1000;
        console.log(`[BASS PULSE] t=${timeSec.toFixed(3)}s interval=${interval.toFixed(3)}s`);
        this.pulseBass = 1.0;
        this.lastBassTime = now;
      }
      if ((onsets[2] || onsets[3]) && (now - this.lastMidTime) > AudioAnalyzer.MID_COOLDOWN_MS) {
        this.pulseMid = 1.0;
        this.lastMidTime = now;
      }
      if ((onsets[4] || onsets[5]) && (now - this.lastTrebleTime) > AudioAnalyzer.TREBLE_COOLDOWN_MS) {
        this.pulseTreble = 1.0;
        this.lastTrebleTime = now;
      }

      // Composite with its own cooldown
      if (onsets.some(o => o) && (now - this.lastCompositeTime) > AudioAnalyzer.COMPOSITE_COOLDOWN_MS) {
        this.pulseComposite = 1.0;
        this.lastCompositeTime = now;
      }

      // 6-band AGC: normalize to TOTAL energy, not per-band.
      // This preserves the relative difference between bands —
      // a band with more energy (synth in mid-high) is BRIGHTER
      // than a quiet band (sub-bass between kicks).
      let totalRawBand = 0;
      for (let b = 0; b < 6; b++) totalRawBand += rawBands[b];
      const avgRawBand = totalRawBand / 6;
      this.agcAvgBands[0] = this.agcAvgBands[0] * agcRate + avgRawBand * (1 - agcRate);
      const bandNorm = Math.max(this.agcAvgBands[0], 0.0003);
      for (let b = 0; b < 6; b++) {
        rawBands[b] = Math.min(1.0, rawBands[b] / bandNorm * 0.3);
      }

      // Per-band smoothing: bass fast for beat tightness, mid/treble smoother
      this.smoothBass = this.smoothBass * smBass + scaledBass * (1 - smBass);
      this.smoothMid = this.smoothMid * smMid + scaledMid * (1 - smMid);
      this.smoothTreble = this.smoothTreble * smTreb + scaledTreble * (1 - smTreb);
      this.smoothVolume = this.smoothVolume * smMid + scaledVolume * (1 - smMid);

      // Attenuated smoothing
      this.attBass = this.attBass * smAtt + scaledBass * (1 - smAtt);
      this.attMid = this.attMid * smAtt + scaledMid * (1 - smAtt);
      this.attTreble = this.attTreble * smAtt + scaledTreble * (1 - smAtt);

      // 6-band smoothing: low bands fast, high bands smooth
      const bandSmValues = [smBass, smBass, smMid, smMid, smTreb, smTreb];
      for (let b = 0; b < 6; b++) {
        this.smoothBands[b] = this.smoothBands[b] * bandSmValues[b] + rawBands[b] * (1 - bandSmValues[b]);
      }

    }

    // Decay all beat pulses (FPS-independent)
    const pulseDecay = Math.pow(AudioAnalyzer.PULSE_DECAY, fpsRatio);
    this.pulseBass *= pulseDecay;
    this.pulseMid *= pulseDecay;
    this.pulseTreble *= pulseDecay;
    this.pulseComposite *= pulseDecay;

    // Beat diagnostic: 5-second window stats
    if (this.beatDiagStartTime === 0) this.beatDiagStartTime = now;
    this.beatDiagFrames++;
    this.beatDiagSumComposite += this.pulseComposite;
    this.beatDiagSumBass += this.pulseBass;
    this.beatDiagSumMid += this.pulseMid;
    this.beatDiagSumTreble += this.pulseTreble;
    if (this.pulseComposite > 0.1) this.beatDiagActiveComposite++;
    if (this.pulseBass > 0.1) this.beatDiagActiveBass++;
    if (this.pulseMid > 0.1) this.beatDiagActiveMid++;
    if (this.pulseTreble > 0.1) this.beatDiagActiveTreble++;

    if ((now - this.beatDiagStartTime) >= 5000 && this.beatDiagFrames > 0) {
      const n = this.beatDiagFrames;
      const avg = (v: number) => (v / n).toFixed(2);
      const pct = (v: number) => (v / n * 100).toFixed(0) + '%';
      console.log(
        `[BEAT DIAG] 5s avg: u_beat_raw=${avg(this.beatDiagSumComposite)} u_beat_bass=${avg(this.beatDiagSumBass)} ` +
        `u_beat_mid=${avg(this.beatDiagSumMid)} u_beat_treble=${avg(this.beatDiagSumTreble)} | ` +
        `active(>0.1): ${pct(this.beatDiagActiveComposite)} ${pct(this.beatDiagActiveBass)} ` +
        `${pct(this.beatDiagActiveMid)} ${pct(this.beatDiagActiveTreble)}`
      );
      this.beatDiagStartTime = now;
      this.beatDiagFrames = 0;
      this.beatDiagSumComposite = this.beatDiagSumBass = this.beatDiagSumMid = this.beatDiagSumTreble = 0;
      this.beatDiagActiveComposite = this.beatDiagActiveBass = this.beatDiagActiveMid = this.beatDiagActiveTreble = 0;
    }

    // === FFT spectrum computation ===
    // Copy ring buffer (unwrap from write position) and apply Hanning window
    for (let i = 0; i < FFT_SIZE; i++) {
      const idx = (this.fftRingPos + i) & (FFT_SIZE - 1);
      this.fftReal[i] = this.fftRingBuffer[idx] * this.hanningWindow[i];
      this.fftImag[i] = 0;
    }

    // In-place radix-2 FFT
    this.fft(this.fftReal, this.fftImag);

    // Compute magnitudes for first 512 bins, find max for log normalization
    let maxMag = 0;
    for (let i = 0; i < SPECTRUM_BINS; i++) {
      const r = this.fftReal[i];
      const im = this.fftImag[i];
      const mag = Math.sqrt(r * r + im * im);
      this.spectrumData[i] = mag;
      if (mag > maxMag) maxMag = mag;
    }

    // Log-scale normalize: log(1 + mag) / log(1 + maxMag) → 0–1
    if (maxMag > 0) {
      const logMax = Math.log(1 + maxMag);
      for (let i = 0; i < SPECTRUM_BINS; i++) {
        this.spectrumData[i] = Math.log(1 + this.spectrumData[i]) / logMax;
      }
    }

    // === Waveform data ===
    // Copy ring buffer unwrapped, center at 0.5: output = sample * 0.5 + 0.5
    for (let i = 0; i < FFT_SIZE; i++) {
      const idx = (this.waveformRingPos + i) & (FFT_SIZE - 1);
      this.waveformData[i] = this.waveformRingBuffer[idx] * 0.5 + 0.5;
    }

    // === Spectral features: centroid and flux ===
    // Compute from log-scaled spectrum (already in spectrumData, 0–1 range)
    let weightedSum = 0;
    let magSum = 0;
    let rawFlux = 0;
    for (let i = 0; i < SPECTRUM_BINS; i++) {
      const mag = this.spectrumData[i];
      weightedSum += i * mag;
      magSum += mag;
      // Spectral flux: half-wave rectified difference from previous frame
      const diff = mag - this.prevSpectrumMags[i];
      if (diff > 0) rawFlux += diff;
      this.prevSpectrumMags[i] = mag;
    }

    // Centroid: normalized 0–1
    const rawCentroid = magSum > 0 ? (weightedSum / magSum) / (SPECTRUM_BINS - 1) : 0;

    // Flux AGC: same approach as band normalization (raw / runningAvg * 0.5, clamped 0–1)
    const fluxAgcRate = Math.pow(this.frameCount < 120 ? 0.95 : 0.992, fpsRatio);
    this.fluxAgcAvg = this.fluxAgcAvg * fluxAgcRate + rawFlux * (1 - fluxAgcRate);
    const scaledFlux = Math.min(1.0, rawFlux / Math.max(this.fluxAgcAvg, 0.0001) * 0.5);

    // Smooth both with mid/treble rate (0.75)
    this.smoothCentroid = this.smoothCentroid * smMid + rawCentroid * (1 - smMid);
    this.smoothFlux = this.smoothFlux * smMid + scaledFlux * (1 - smMid);

    // One-time verification log
    if (!this.fftLoggedOnce && this.hasData) {
      let specMin = Infinity, specMax = -Infinity;
      for (let i = 0; i < SPECTRUM_BINS; i++) {
        if (this.spectrumData[i] < specMin) specMin = this.spectrumData[i];
        if (this.spectrumData[i] > specMax) specMax = this.spectrumData[i];
      }
      let waveMin = Infinity, waveMax = -Infinity;
      for (let i = 0; i < FFT_SIZE; i++) {
        if (this.waveformData[i] < waveMin) waveMin = this.waveformData[i];
        if (this.waveformData[i] > waveMax) waveMax = this.waveformData[i];
      }
      console.log(`[FFT] spectrum range: min=${specMin.toFixed(4)} max=${specMax.toFixed(4)}, waveform range: min=${waveMin.toFixed(4)} max=${waveMax.toFixed(4)}`);
      this.fftLoggedOnce = true;
    }

    // One-time features verification log: 3 seconds after real audio detected
    if (!this.featuresLoggedOnce) {
      const hasAudio = this.smoothBass > 0.01 || this.smoothMid > 0.01 || this.smoothTreble > 0.01;
      if (hasAudio && this.featuresAudioDetectedTime === 0) {
        this.featuresAudioDetectedTime = now;
      }
      if (this.featuresAudioDetectedTime > 0 && (now - this.featuresAudioDetectedTime) >= 3000) {
        console.log(`[FEATURES] centroid=${this.smoothCentroid.toFixed(2)} flux=${this.smoothFlux.toFixed(2)}`);
        this.featuresLoggedOnce = true;
      }
    }

    return {
      u_time: time,
      u_bass: this.smoothBass,
      u_mid: this.smoothMid,
      u_treble: this.smoothTreble,
      u_volume: this.smoothVolume,
      u_bass_att: this.attBass,
      u_mid_att: this.attMid,
      u_treb_att: this.attTreble,
      u_beat_raw: this.pulseComposite,
      u_beat_bass: this.pulseBass,
      u_beat_mid: this.pulseMid,
      u_beat_treble: this.pulseTreble,
      u_sub_bass: this.smoothBands[0],
      u_low_bass: this.smoothBands[1],
      u_low_mid: this.smoothBands[2],
      u_mid_high: this.smoothBands[3],
      u_high_mid: this.smoothBands[4],
      u_high: this.smoothBands[5],
      u_centroid: this.smoothCentroid,
      u_flux: this.smoothFlux,
      u_resolution: [width, height],
      u_scene_progress: 0.0,
      u_fps: this.fps,
      spectrumData: this.spectrumData,
      waveformData: this.waveformData,
    };
  }

  getRawValues(): { rawBass: number; rawMid: number; rawTreble: number } {
    return {
      rawBass: this.lastRawBass,
      rawMid: this.lastRawMid,
      rawTreble: this.lastRawTreble,
    };
  }

  /** In-place radix-2 Cooley-Tukey FFT. Arrays must be power-of-2 length. */
  private fft(real: Float64Array, imag: Float64Array): void {
    const n = real.length;

    // Bit-reversal permutation
    for (let i = 1, j = 0; i < n; i++) {
      let bit = n >> 1;
      while (j & bit) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;

      if (i < j) {
        let tmp = real[i]; real[i] = real[j]; real[j] = tmp;
        tmp = imag[i]; imag[i] = imag[j]; imag[j] = tmp;
      }
    }

    // Butterfly stages
    for (let len = 2; len <= n; len <<= 1) {
      const halfLen = len >> 1;
      const angle = -2 * Math.PI / len;
      const wReal = Math.cos(angle);
      const wImag = Math.sin(angle);

      for (let i = 0; i < n; i += len) {
        let curReal = 1;
        let curImag = 0;

        for (let j = 0; j < halfLen; j++) {
          const a = i + j;
          const b = a + halfLen;
          const tReal = curReal * real[b] - curImag * imag[b];
          const tImag = curReal * imag[b] + curImag * real[b];

          real[b] = real[a] - tReal;
          imag[b] = imag[a] - tImag;
          real[a] += tReal;
          imag[a] += tImag;

          const nextReal = curReal * wReal - curImag * wImag;
          curImag = curReal * wImag + curImag * wReal;
          curReal = nextReal;
        }
      }
    }
  }
}
