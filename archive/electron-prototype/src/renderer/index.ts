console.log('[Phosphene] Renderer script loading...');
import { AudioAnalyzer } from './audio/analyzer';
import { VisualRenderer } from './visuals/renderer';
import { SceneManager } from './visuals/scene-manager';
import * as path from 'path';
import * as fs from 'fs';

const statusEl = document.getElementById('status')!;

function setStatus(msg: string): void {
  statusEl.textContent = msg;
  statusEl.classList.remove('hidden');
  console.log(`[Phosphene] ${msg}`);
}

function hideStatus(): void {
  statusEl.classList.add('hidden');
}

async function main(): Promise<void> {
  setStatus('Initializing audio...');

  const shaderDir = path.join(__dirname, 'visuals', 'shaders');

  let sceneManager: SceneManager;
  try {
    sceneManager = new SceneManager(shaderDir);
  } catch (err: any) {
    setStatus('Failed to load shaders: ' + err.message);
    console.error('[Phosphene] Shader load error:', err);
    return;
  }

  const canvas = document.createElement('canvas');
  document.body.appendChild(canvas);

  console.log('[Phosphene] Creating audio analyzer...');
  const analyzer = new AudioAnalyzer();
  console.log('[Phosphene] Calling initialize...');
  const audioReady = await analyzer.initialize();
  console.log('[Phosphene] Initialize returned:', audioReady);

  if (!audioReady) {
    setStatus('No audio input — check Screen Recording permission for audio_tap');
  } else {
    setStatus('Audio connected — visualizing');
    setTimeout(hideStatus, 3000);
  }

  const visualRenderer = new VisualRenderer(canvas, sceneManager.currentScene.fragmentShader);
  let activeShader = sceneManager.currentScene.fragmentShader;

  const { ipcRenderer } = require('electron');
  ipcRenderer.on('next-scene', () => {
    sceneManager.nextScene(performance.now() / 1000);
  });

  const diagLines: string[] = [];
  let diagStarted = false;
  let diagStartTime = 0;

  function frame(): void {
    const now = performance.now() / 1000;
    sceneManager.update(now);

    if (sceneManager.currentScene.fragmentShader !== activeShader) {
      visualRenderer.setShader(sceneManager.currentScene.fragmentShader);
      activeShader = sceneManager.currentScene.fragmentShader;
    }

    const uniforms = analyzer.getUniforms(window.innerWidth, window.innerHeight);
    uniforms.u_scene_progress = sceneManager.getSceneProgress(now);

    // Pass per-preset params alongside audio uniforms
    visualRenderer.updateUniforms(uniforms, sceneManager.currentParams);
    visualRenderer.render();

    // Diagnostic: capture 30 seconds of data once audio is detected
    const hasAudio = uniforms.u_bass > 0.01 || uniforms.u_mid > 0.01;
    if (hasAudio && !diagStarted) {
      diagStarted = true;
      diagStartTime = uniforms.u_time;
      console.log(`[Phosphene] Audio detected at ${uniforms.u_time.toFixed(1)}s — starting diagnostic capture`);
    }
    if (diagStarted && (uniforms.u_time - diagStartTime) < 30.0) {
      const beat = Math.min(1.0, uniforms.u_beat_raw * sceneManager.currentParams.beat_sensitivity);
      // Log ALL values the shader actually receives
      diagLines.push([
        (uniforms.u_time - diagStartTime).toFixed(3),
        uniforms.u_bass.toFixed(4), uniforms.u_mid.toFixed(4), uniforms.u_treble.toFixed(4),
        uniforms.u_bass_att.toFixed(4), uniforms.u_mid_att.toFixed(4), uniforms.u_treb_att.toFixed(4),
        uniforms.u_beat_raw.toFixed(4), beat.toFixed(4),
        uniforms.u_beat_bass.toFixed(4), uniforms.u_beat_mid.toFixed(4), uniforms.u_beat_treble.toFixed(4),
        uniforms.u_sub_bass.toFixed(4), uniforms.u_low_bass.toFixed(4), uniforms.u_low_mid.toFixed(4),
        uniforms.u_mid_high.toFixed(4), uniforms.u_high_mid.toFixed(4), uniforms.u_high.toFixed(4),
      ].join('\t'));
    } else if (diagStarted && diagLines.length > 0 && (uniforms.u_time - diagStartTime) >= 30.0) {
      const header = 'time\tbass\tmid\ttreble\tbass_att\tmid_att\ttreb_att\tbeat_raw\tbeat\tbeat_bass\tbeat_mid\tbeat_treble\tsub_bass\tlow_bass\tlow_mid\tmid_high\thigh_mid\thigh';
      const diagPath = path.join(__dirname, '..', '..', 'audio_diag.tsv');
      fs.writeFileSync(diagPath, header + '\n' + diagLines.join('\n'));
      console.log(`[Phosphene] Diagnostic written: ${diagPath} (${diagLines.length} frames)`);
      diagLines.length = 0;
    }

    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);
}

main().catch(err => {
  console.error('[Phosphene] Fatal error:', err);
  setStatus(`Error: ${err.message}`);
});
