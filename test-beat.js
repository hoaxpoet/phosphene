/**
 * Beat detection test: feeds synthetic audio (120 BPM kick drum)
 * through the analyzer and verifies beat pulses fire at correct intervals.
 *
 * Run: node test-beat.js
 */

const SAMPLE_RATE = 48000;
const BPM = 120;
const BEAT_INTERVAL_SAMPLES = Math.floor(SAMPLE_RATE * 60 / BPM); // 24000 samples per beat
const KICK_DURATION_SAMPLES = Math.floor(SAMPLE_RATE * 0.05); // 50ms kick
const TOTAL_SECONDS = 10;
const TOTAL_SAMPLES = SAMPLE_RATE * TOTAL_SECONDS;
const FPS = 60;
const SAMPLES_PER_FRAME = Math.floor(SAMPLE_RATE / FPS); // 800

// === Reproduce the analyzer logic ===

const SMOOTHING = 0.82;
const ATT_SMOOTHING = 0.95;

// Beat detection params
const BEAT_AVG_RATE = 0.96;
const BEAT_THRESHOLD_BASE = 1.15;
const BEAT_THRESHOLD_RISE = 0.3;
const BEAT_THRESHOLD_DECAY = 0.95;
const BEAT_MIN_INTERVAL_MS = 180;
const BEAT_PULSE_DECAY = 0.85;

// Filter coefficients
const bassAlpha = Math.exp(-2 * Math.PI * 250 / SAMPLE_RATE);
const trebleAlpha = Math.exp(-2 * Math.PI * 4000 / SAMPLE_RATE);

// State
let bassLpState = 0, trebleHpState = 0, prevSample = 0;
let bassAccum = 0, midAccum = 0, trebleAccum = 0, volumeAccum = 0, accumCount = 0;
let smoothBass = 0, smoothMid = 0, smoothTreble = 0, smoothVolume = 0;
let attBass = 0, attMid = 0, attTreble = 0;
let beatAvg = 0, beatThresholdBoost = 0, beatPulse = 0, lastBeatTime = -1000;
let fps = 60;

// FPS-independent smoothing
const fpsRatio = 30.0 / fps;
const sm = Math.pow(SMOOTHING, fpsRatio);
const smAtt = Math.pow(ATT_SMOOTHING, fpsRatio);
const smBeatAvg = Math.pow(BEAT_AVG_RATE, fpsRatio);
const smThreshDecay = Math.pow(BEAT_THRESHOLD_DECAY, fpsRatio);
const smPulseDecay = Math.pow(BEAT_PULSE_DECAY, fpsRatio);

// Generate synthetic audio: kick drum = 60Hz sine burst
function generateKick(sampleIndex) {
  const posInBeat = sampleIndex % BEAT_INTERVAL_SAMPLES;
  const t = sampleIndex / SAMPLE_RATE;
  let sample = 0;

  // Kick drum: 60Hz burst on each beat
  if (posInBeat < KICK_DURATION_SAMPLES) {
    const kt = posInBeat / SAMPLE_RATE;
    sample += Math.sin(2 * Math.PI * 60 * kt) * 0.5 * Math.exp(-kt * 40);
  }

  // Sustained bass (100Hz, always present)
  sample += Math.sin(2 * Math.PI * 100 * t) * 0.15;

  // Sustained mid (400Hz + 800Hz guitar/keys, always playing)
  sample += Math.sin(2 * Math.PI * 400 * t + Math.sin(t * 3) * 0.5) * 0.12;
  sample += Math.sin(2 * Math.PI * 800 * t) * 0.08;

  // Hi-hat on off-beats
  const offBeatPos = (sampleIndex + Math.floor(BEAT_INTERVAL_SAMPLES / 2)) % BEAT_INTERVAL_SAMPLES;
  if (offBeatPos < Math.floor(SAMPLE_RATE * 0.02)) {
    sample += (Math.random() - 0.5) * 0.25 * Math.exp(-offBeatPos / SAMPLE_RATE * 80);
  }

  // Background noise
  sample += (Math.random() - 0.5) * 0.03;

  return sample;
}

// Process audio in frames like the real app does
const beatFirings = [];
let frameTime = 0;

for (let frame = 0; frame < FPS * TOTAL_SECONDS; frame++) {
  frameTime = frame / FPS;
  const frameStartSample = frame * SAMPLES_PER_FRAME;

  // Process samples for this frame
  for (let s = 0; s < SAMPLES_PER_FRAME; s++) {
    const sampleIdx = frameStartSample + s;
    if (sampleIdx >= TOTAL_SAMPLES) break;

    const sample = generateKick(sampleIdx);

    // Band separation (same as analyzer.ts)
    bassLpState = bassLpState * bassAlpha + sample * (1 - bassAlpha);
    const bassSample = bassLpState;
    trebleHpState = trebleAlpha * (trebleHpState + sample - prevSample);
    prevSample = sample;
    const trebleSample = trebleHpState;
    const midSample = sample - bassSample - trebleSample;

    bassAccum += bassSample * bassSample;
    midAccum += midSample * midSample;
    trebleAccum += trebleSample * trebleSample;
    volumeAccum += sample * sample;
    accumCount++;
  }

  // Flush accumulators (same as getUniforms)
  if (accumCount > 0) {
    const rawBass = Math.sqrt(bassAccum / accumCount);
    const rawMid = Math.sqrt(midAccum / accumCount);
    const rawTreble = Math.sqrt(trebleAccum / accumCount);

    bassAccum = 0; midAccum = 0; trebleAccum = 0; volumeAccum = 0; accumCount = 0;

    const scaledBass = Math.min(1.0, rawBass * 13.0);
    const scaledMid = Math.min(1.0, rawMid * 15.0);
    const scaledTreble = Math.min(1.0, rawTreble * 25.0);

    smoothBass = smoothBass * sm + scaledBass * (1 - sm);
    smoothMid = smoothMid * sm + scaledMid * (1 - sm);
    smoothTreble = smoothTreble * sm + scaledTreble * (1 - sm);

    // Beat detection
    // Use RAW (unscaled, unclamped) bass RMS for beat detection —
    // the scaled values clip at 1.0, destroying the dynamic range
    // needed to distinguish kicks from sustained bass
    const beatEnergy = rawBass;
    beatAvg = beatAvg * smBeatAvg + beatEnergy * (1 - smBeatAvg);

    const threshold = (BEAT_THRESHOLD_BASE + beatThresholdBoost) * Math.max(beatAvg, 0.02);
    const frameTimeMs = frameTime * 1000;

    // Skip first 1 second to let running average stabilize
    if (beatEnergy > threshold && (frameTimeMs - lastBeatTime) > BEAT_MIN_INTERVAL_MS && frameTime > 1.0) {
      beatPulse = 1.0;
      lastBeatTime = frameTimeMs;
      beatThresholdBoost = BEAT_THRESHOLD_RISE;
      beatFirings.push(frameTime);
    }
  }

  beatThresholdBoost *= smThreshDecay;
  beatPulse *= smPulseDecay;
}

// Analysis
console.log(`\n=== Beat Detection Test: ${BPM} BPM Synthetic Kick ===`);
console.log(`Expected beats: ${TOTAL_SECONDS * BPM / 60} (every ${60/BPM}s)`);
console.log(`Detected beats: ${beatFirings.length}`);
console.log(`\nBeat timestamps:`);

const intervals = [];
for (let i = 0; i < beatFirings.length; i++) {
  const interval = i > 0 ? (beatFirings[i] - beatFirings[i-1]).toFixed(3) : '-';
  console.log(`  ${beatFirings[i].toFixed(3)}s  (interval: ${interval}s)`);
  if (i > 0) intervals.push(beatFirings[i] - beatFirings[i-1]);
}

if (intervals.length > 0) {
  const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
  const expectedInterval = 60 / BPM;
  const error = Math.abs(avgInterval - expectedInterval) / expectedInterval * 100;
  console.log(`\nAverage interval: ${avgInterval.toFixed(3)}s`);
  console.log(`Expected interval: ${expectedInterval.toFixed(3)}s`);
  console.log(`Detected BPM: ${(60 / avgInterval).toFixed(1)}`);
  console.log(`Error: ${error.toFixed(1)}%`);

  // Check regularity
  const deviations = intervals.map(i => Math.abs(i - avgInterval));
  const maxDeviation = Math.max(...deviations);
  console.log(`Max deviation from average: ${(maxDeviation * 1000).toFixed(0)}ms`);
  console.log(`\nResult: ${error < 5 && beatFirings.length >= TOTAL_SECONDS * BPM / 60 * 0.8 ? 'PASS ✓' : 'FAIL ✗'}`);
} else {
  console.log('\nResult: FAIL ✗ (no beats detected)');
}
