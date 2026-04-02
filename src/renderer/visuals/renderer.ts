import * as THREE from 'three';
import { AudioUniforms, SceneParams } from '../../shared/types';

const VERTEX_SHADER = `
void main() {
  gl_Position = vec4(position, 1.0);
}
`;

function createSpectrumTexture(): THREE.DataTexture {
  const data = new Float32Array(512);
  const tex = new THREE.DataTexture(data, 512, 1, THREE.RedFormat, THREE.FloatType);
  tex.minFilter = THREE.LinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.needsUpdate = true;
  return tex;
}

function createWaveformTexture(): THREE.DataTexture {
  const data = new Float32Array(1024);
  // Initialize centered at 0.5 (silence)
  data.fill(0.5);
  const tex = new THREE.DataTexture(data, 1024, 1, THREE.RedFormat, THREE.FloatType);
  tex.minFilter = THREE.LinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.needsUpdate = true;
  return tex;
}

function createMaterial(fragmentShader: string, prevFrameTexture: THREE.Texture, spectrumTexture: THREE.DataTexture, waveformTexture: THREE.DataTexture): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    vertexShader: VERTEX_SHADER,
    fragmentShader,
    uniforms: {
      // Audio
      u_time: { value: 0.0 },
      u_bass: { value: 0.0 },
      u_mid: { value: 0.0 },
      u_treble: { value: 0.0 },
      u_volume: { value: 0.0 },
      u_bass_att: { value: 0.0 },
      u_mid_att: { value: 0.0 },
      u_treb_att: { value: 0.0 },
      u_beat: { value: 0.0 },
      u_beat_bass: { value: 0.0 },
      u_beat_mid: { value: 0.0 },
      u_beat_treble: { value: 0.0 },
      // 6-band
      u_sub_bass: { value: 0.0 },
      u_low_bass: { value: 0.0 },
      u_low_mid: { value: 0.0 },
      u_mid_high: { value: 0.0 },
      u_high_mid: { value: 0.0 },
      u_high: { value: 0.0 },
      // Spectrum & waveform textures
      u_spectrum: { value: spectrumTexture },
      u_waveform: { value: waveformTexture },
      // Scene
      u_resolution: { value: new THREE.Vector2(window.innerWidth, window.innerHeight) },
      u_scene_progress: { value: 0.0 },
      u_fps: { value: 60.0 },
      u_prev_frame: { value: prevFrameTexture },
      // Per-preset params
      u_beat_zoom: { value: 0.08 },
      u_beat_rot: { value: 0.03 },
      u_base_zoom: { value: 0.04 },
      u_base_rot: { value: 0.01 },
      u_decay: { value: 0.955 },
    },
  });
}

function updateMaterialUniforms(material: THREE.ShaderMaterial, uniforms: AudioUniforms, params: SceneParams): void {
  material.uniforms.u_time.value = uniforms.u_time;
  material.uniforms.u_bass.value = uniforms.u_bass;
  material.uniforms.u_mid.value = uniforms.u_mid;
  material.uniforms.u_treble.value = uniforms.u_treble;
  material.uniforms.u_volume.value = uniforms.u_volume;
  material.uniforms.u_bass_att.value = uniforms.u_bass_att;
  material.uniforms.u_mid_att.value = uniforms.u_mid_att;
  material.uniforms.u_treb_att.value = uniforms.u_treb_att;
  // Route beat signal based on beat_source, apply sensitivity
  let beatSignal: number;
  switch (params.beat_source) {
    case 'bass': beatSignal = uniforms.u_beat_bass; break;
    case 'mid': beatSignal = uniforms.u_beat_mid; break;
    case 'treble': beatSignal = uniforms.u_beat_treble; break;
    default: beatSignal = uniforms.u_beat_raw; break;
  }
  material.uniforms.u_beat.value = Math.min(1.0, beatSignal * params.beat_sensitivity);
  // Per-band beats always available (unscaled by sensitivity)
  material.uniforms.u_beat_bass.value = uniforms.u_beat_bass;
  material.uniforms.u_beat_mid.value = uniforms.u_beat_mid;
  material.uniforms.u_beat_treble.value = uniforms.u_beat_treble;
  material.uniforms.u_sub_bass.value = uniforms.u_sub_bass;
  material.uniforms.u_low_bass.value = uniforms.u_low_bass;
  material.uniforms.u_low_mid.value = uniforms.u_low_mid;
  material.uniforms.u_mid_high.value = uniforms.u_mid_high;
  material.uniforms.u_high_mid.value = uniforms.u_high_mid;
  material.uniforms.u_high.value = uniforms.u_high;
  material.uniforms.u_resolution.value.set(uniforms.u_resolution[0], uniforms.u_resolution[1]);
  material.uniforms.u_scene_progress.value = uniforms.u_scene_progress;
  material.uniforms.u_fps.value = uniforms.u_fps;
  // Per-preset params
  material.uniforms.u_beat_zoom.value = params.beat_zoom;
  material.uniforms.u_beat_rot.value = params.beat_rot;
  material.uniforms.u_base_zoom.value = params.base_zoom;
  material.uniforms.u_base_rot.value = params.base_rot;
  material.uniforms.u_decay.value = params.decay;
}

export class VisualRenderer {
  private renderer: THREE.WebGLRenderer;
  private scene: THREE.Scene;
  private camera: THREE.OrthographicCamera;
  private geometry: THREE.PlaneGeometry;
  private material: THREE.ShaderMaterial;
  private mesh: THREE.Mesh;

  private rtA: THREE.WebGLRenderTarget;
  private rtB: THREE.WebGLRenderTarget;
  private pingPong: boolean = false;

  private copyScene: THREE.Scene;
  private copyMaterial: THREE.ShaderMaterial;

  private spectrumTexture: THREE.DataTexture;
  private waveformTexture: THREE.DataTexture;

  constructor(canvas: HTMLCanvasElement, fragmentShader: string) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false });
    this.renderer.setPixelRatio(window.devicePixelRatio);
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.autoClear = false;

    this.scene = new THREE.Scene();
    this.camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.geometry = new THREE.PlaneGeometry(2, 2);

    const pw = Math.floor(window.innerWidth * window.devicePixelRatio);
    const ph = Math.floor(window.innerHeight * window.devicePixelRatio);
    const rtOpts = { minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, format: THREE.RGBAFormat };
    this.rtA = new THREE.WebGLRenderTarget(pw, ph, rtOpts);
    this.rtB = new THREE.WebGLRenderTarget(pw, ph, rtOpts);

    this.spectrumTexture = createSpectrumTexture();
    this.waveformTexture = createWaveformTexture();
    this.material = createMaterial(fragmentShader, this.rtB.texture, this.spectrumTexture, this.waveformTexture);
    this.mesh = new THREE.Mesh(this.geometry, this.material);
    this.scene.add(this.mesh);

    this.copyScene = new THREE.Scene();
    this.copyMaterial = new THREE.ShaderMaterial({
      vertexShader: VERTEX_SHADER,
      fragmentShader: `
        uniform sampler2D u_tex;
        uniform vec2 u_res;
        void main() {
          gl_FragColor = texture2D(u_tex, gl_FragCoord.xy / u_res);
        }
      `,
      uniforms: {
        u_tex: { value: this.rtA.texture },
        u_res: { value: new THREE.Vector2(pw, ph) },
      },
    });
    this.copyScene.add(new THREE.Mesh(this.geometry, this.copyMaterial));

    window.addEventListener('resize', () => this.onResize());
  }

  setShader(fragmentShader: string): void {
    const readRT = this.pingPong ? this.rtA : this.rtB;
    const oldMaterial = this.material;
    this.material = createMaterial(fragmentShader, readRT.texture, this.spectrumTexture, this.waveformTexture);
    this.mesh.material = this.material;
    oldMaterial.dispose();
  }

  updateUniforms(uniforms: AudioUniforms, params: SceneParams): void {
    updateMaterialUniforms(this.material, uniforms, params);

    // Update spectrum texture data (512 floats)
    const specData = this.spectrumTexture.image.data as unknown as Float32Array;
    specData.set(uniforms.spectrumData);
    this.spectrumTexture.needsUpdate = true;

    // Update waveform texture data (1024 floats)
    const waveData = this.waveformTexture.image.data as unknown as Float32Array;
    waveData.set(uniforms.waveformData);
    this.waveformTexture.needsUpdate = true;
  }

  render(): void {
    const writeRT = this.pingPong ? this.rtB : this.rtA;
    const readRT = this.pingPong ? this.rtA : this.rtB;

    this.material.uniforms.u_prev_frame.value = readRT.texture;

    this.renderer.setRenderTarget(writeRT);
    this.renderer.clear();
    this.renderer.render(this.scene, this.camera);

    this.copyMaterial.uniforms.u_tex.value = writeRT.texture;
    this.renderer.setRenderTarget(null);
    this.renderer.clear();
    this.renderer.render(this.copyScene, this.camera);

    this.pingPong = !this.pingPong;
  }

  private onResize(): void {
    const w = window.innerWidth;
    const h = window.innerHeight;
    this.renderer.setSize(w, h);
    const pw = Math.floor(w * window.devicePixelRatio);
    const ph = Math.floor(h * window.devicePixelRatio);
    this.rtA.setSize(pw, ph);
    this.rtB.setSize(pw, ph);
    this.copyMaterial.uniforms.u_res.value.set(pw, ph);
    this.material.uniforms.u_resolution.value.set(w, h);
  }

  dispose(): void {
    this.renderer.dispose();
    this.material.dispose();
    this.copyMaterial.dispose();
    this.geometry.dispose();
    this.rtA.dispose();
    this.rtB.dispose();
    this.spectrumTexture.dispose();
    this.waveformTexture.dispose();
  }
}
