/**
 * Diagnostic onset detector — logs onsets to console without driving any uniforms.
 *
 * Takes per-frame raw 6-band RMS values from analyzer.ts, computes spectral flux
 * (positive energy change), maintains a 50-frame circular buffer per band, and
 * fires onsets when flux exceeds median(buffer) * 1.5 with per-band cooldown.
 */

const BAND_NAMES = ['sub_bass', 'low_bass', 'low_mid', 'mid_high', 'high_mid', 'high'];
const NUM_BANDS = 6;
const BUFFER_SIZE = 50;
const THRESHOLD_MULT = 1.5;
// Per-band cooldowns: low bands need longer cooldowns because low-frequency
// sounds have longer energy envelopes (a kick at 125 BPM = ~480ms between hits)
const COOLDOWNS_MS = [400, 400, 150, 150, 100, 100];
const SUMMARY_INTERVAL_S = 5;

export class OnsetDetector {
  private prevRMS: number[] = [0, 0, 0, 0, 0, 0];
  private fluxBuffers: number[][] = [[], [], [], [], [], []];
  private fluxWritePos: number[] = [0, 0, 0, 0, 0, 0];
  private bufferFilled: boolean[] = [false, false, false, false, false, false];
  private lastOnsetTime: number[] = [0, 0, 0, 0, 0, 0];
  private startTime: number = 0;

  // Summary counters
  private summaryCounts: number[] = [0, 0, 0, 0, 0, 0];
  private lastSummaryTime: number = 0;

  /**
   * Call once per frame with the raw (pre-AGC) 6-band RMS values and current time.
   * Returns a boolean array indicating which of the 6 bands fired an onset this frame.
   */
  process(rawBands: number[], nowMs: number): boolean[] {
    if (this.startTime === 0) {
      this.startTime = nowMs;
      this.lastSummaryTime = nowMs;
    }

    const timeSec = (nowMs - this.startTime) / 1000;
    const fired: boolean[] = [false, false, false, false, false, false];

    for (let b = 0; b < NUM_BANDS; b++) {
      // Spectral flux: positive energy change only
      const flux = Math.max(0, rawBands[b] - this.prevRMS[b]);
      this.prevRMS[b] = rawBands[b];

      // Write to circular buffer
      if (this.fluxBuffers[b].length < BUFFER_SIZE) {
        this.fluxBuffers[b].push(flux);
      } else {
        this.fluxBuffers[b][this.fluxWritePos[b]] = flux;
        this.bufferFilled[b] = true;
      }
      this.fluxWritePos[b] = (this.fluxWritePos[b] + 1) % BUFFER_SIZE;

      // Only evaluate once buffer is full
      if (!this.bufferFilled[b]) continue;

      // Compute median of buffer
      const sorted = this.fluxBuffers[b].slice().sort((a, c) => a - c);
      const median = sorted[BUFFER_SIZE >> 1];
      const threshold = median * THRESHOLD_MULT;

      // Fire onset if flux exceeds threshold and cooldown elapsed
      if (flux > threshold && threshold > 0 && (nowMs - this.lastOnsetTime[b]) > COOLDOWNS_MS[b]) {
        this.lastOnsetTime[b] = nowMs;
        this.summaryCounts[b]++;
        fired[b] = true;

        // Find peak flux in buffer for context
        const peak = sorted[BUFFER_SIZE - 1];

        console.log(
          `[ONSET] t=${timeSec.toFixed(3)}s band=${BAND_NAMES[b]} ` +
          `flux=${flux.toFixed(6)} thresh=${threshold.toFixed(6)} peak=${peak.toFixed(6)}`
        );
      }
    }

    // 5-second summary
    if ((nowMs - this.lastSummaryTime) >= SUMMARY_INTERVAL_S * 1000) {
      const total = this.summaryCounts.reduce((a, c) => a + c, 0);
      const parts = BAND_NAMES.map((name, i) => `${name}=${this.summaryCounts[i]}`).join(' ');
      console.log(`[ONSET SUMMARY] 5s window: ${parts} total=${total}`);
      this.summaryCounts = [0, 0, 0, 0, 0, 0];
      this.lastSummaryTime = nowMs;
    }

    return fired;
  }
}
