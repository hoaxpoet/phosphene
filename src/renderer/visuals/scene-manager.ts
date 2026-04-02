import * as fs from 'fs';
import * as path from 'path';
import { SceneMetadata, SceneParams } from '../../shared/types';

const DEFAULT_DURATION = 30;
const CROSSFADE_DURATION = 2.5;

const DEFAULT_PARAMS: SceneParams = {
  beat_zoom: 0.08,
  beat_rot: 0.03,
  base_zoom: 0.04,
  base_rot: 0.01,
  decay: 0.955,
  beat_sensitivity: 1.0,
  beat_source: 'composite',
};

interface Scene {
  name: string;
  fragmentShader: string;
  metadata: SceneMetadata;
  duration: number;
  params: SceneParams;
}

export class SceneManager {
  private scenes: Scene[] = [];
  private currentIndex: number = -1;
  private previousIndex: number = -1;
  private sceneStartTime: number = 0;
  private transitionStartTime: number = -1;
  private isTransitioning: boolean = false;

  constructor(shaderDir: string) {
    this.loadScenes(shaderDir);
    if (this.scenes.length === 0) {
      throw new Error('No shaders found in ' + shaderDir);
    }
    this.currentIndex = Math.floor(Math.random() * this.scenes.length);
    this.sceneStartTime = performance.now() / 1000;
    console.log(`[Phosphene] Loaded ${this.scenes.length} scenes. Starting with: ${this.currentScene.name}`);
  }

  private loadScenes(dir: string): void {
    const files = fs.readdirSync(dir).filter(f => f.endsWith('.glsl'));

    for (const file of files) {
      const glslPath = path.join(dir, file);
      const jsonPath = path.join(dir, file.replace('.glsl', '.json'));

      const fragmentShader = fs.readFileSync(glslPath, 'utf-8');

      let metadata: SceneMetadata = {
        name: file.replace('.glsl', ''),
        family: 'abstract',
      };

      if (fs.existsSync(jsonPath)) {
        try {
          metadata = JSON.parse(fs.readFileSync(jsonPath, 'utf-8'));
        } catch (e) {
          console.warn(`[Phosphene] Failed to parse metadata for ${file}:`, e);
        }
      }

      // Extract per-preset params from metadata, falling back to defaults
      const params: SceneParams = {
        beat_zoom: metadata.beat_zoom ?? DEFAULT_PARAMS.beat_zoom,
        beat_rot: metadata.beat_rot ?? DEFAULT_PARAMS.beat_rot,
        base_zoom: metadata.base_zoom ?? DEFAULT_PARAMS.base_zoom,
        base_rot: metadata.base_rot ?? DEFAULT_PARAMS.base_rot,
        decay: metadata.decay ?? DEFAULT_PARAMS.decay,
        beat_sensitivity: metadata.beat_sensitivity ?? DEFAULT_PARAMS.beat_sensitivity,
        beat_source: metadata.beat_source ?? DEFAULT_PARAMS.beat_source,
      };

      this.scenes.push({
        name: metadata.name,
        fragmentShader,
        metadata,
        duration: metadata.duration || DEFAULT_DURATION,
        params,
      });
    }
  }

  get currentScene(): Scene {
    return this.scenes[this.currentIndex];
  }

  get currentParams(): SceneParams {
    return this.scenes[this.currentIndex].params;
  }

  getSceneProgress(now: number): number {
    const elapsed = now - this.sceneStartTime;
    return Math.min(1.0, elapsed / this.currentScene.duration);
  }

  getTransitionMix(now: number): number {
    if (!this.isTransitioning) return -1;
    const elapsed = now - this.transitionStartTime;
    const t = Math.min(1.0, elapsed / CROSSFADE_DURATION);
    if (t >= 1.0) {
      this.isTransitioning = false;
      this.previousIndex = -1;
    }
    return t * t * (3 - 2 * t);
  }

  update(now: number): void {
    const elapsed = now - this.sceneStartTime;
    if (!this.isTransitioning && elapsed >= this.currentScene.duration) {
      this.nextScene(now);
    }
  }

  nextScene(now: number): void {
    this.previousIndex = this.currentIndex;
    this.transitionStartTime = now;
    this.isTransitioning = true;

    if (this.scenes.length > 1) {
      let next: number;
      do {
        next = Math.floor(Math.random() * this.scenes.length);
      } while (next === this.currentIndex);
      this.currentIndex = next;
    }

    this.sceneStartTime = now;
    console.log(`[Phosphene] Scene transition → ${this.currentScene.name} (decay=${this.currentParams.decay}, beat_sens=${this.currentParams.beat_sensitivity})`);
  }
}
