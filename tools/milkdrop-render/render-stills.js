// Still-grabber for jelly showoff parade port. Avoids render.js's webm base64 stack-blow.
// Grabs N PNG stills over the sim window. Decorrelated bass/treble so the spring-jelly swings.
// Usage: node render-stills.js <out_dir> <preset.json>
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');

const W = 960, H = 720;
const STILL_TIMES = [2.0, 3.5, 5.0, 6.5, 8.0, 9.5, 11.0, 12.5]; // seconds of sim time

(async () => {
  const outDir = process.argv[2], presetFile = process.argv[3];
  fs.mkdirSync(outDir, { recursive: true });
  const preset = JSON.parse(fs.readFileSync(presetFile, 'utf8')).preset;

  const browser = await puppeteer.launch({
    headless: 'new',
    protocolTimeout: 120000,
    args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl',
      '--autoplay-policy=no-user-gesture-required', `--window-size=${W},${H}`],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: W, height: H });
  page.on('pageerror', (e) => console.log('  [page error]', e.message));

  await page.setContent(`<!doctype html><html><body style="margin:0">
    <canvas id="c" width="${W}" height="${H}"></canvas></body></html>`);
  await page.addScriptTag({ path: path.join(__dirname, 'node_modules/butterchurn/lib/butterchurn.min.js') });

  const musicB64 = fs.readFileSync(path.join(__dirname, 'music.wav')).toString('base64');
  const setupOk = await page.evaluate(async (w, h, b64) => {
    try {
      const BC = window.butterchurn && (window.butterchurn.default || window.butterchurn);
      const canvas = document.getElementById('c');
      const ac = new (window.AudioContext || window.webkitAudioContext)();
      const bin = atob(b64); const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      const musicBuf = await ac.decodeAudioData(bytes.buffer);
      const gain = ac.createGain(); gain.gain.value = 2.0;   // hot — these presets expect loud input
      const viz = BC.createVisualizer(ac, canvas, { width: w, height: h, pixelRatio: 1 });
      viz.connectAudio(gain);
      window.__ac = ac; window.__musicBuf = musicBuf; window.__gain = gain;
      window.__viz = viz; window.__canvas = canvas;
      return 'ok';
    } catch (e) { return 'setup err: ' + e.message; }
  }, W, H, musicB64);
  if (setupOk !== 'ok') { console.log('setup fail', setupOk); await browser.close(); process.exit(1); }

  await page.evaluate((p) => {
    window.__viz.loadPreset(p, 0.0);
    const src = window.__ac.createBufferSource();
    src.buffer = window.__musicBuf; src.connect(window.__gain); src.start(0);
  }, preset);

  // One continuous real-time setTimeout loop (rAF is unreliable headless); capture at target times.
  const FPS = 30;
  const captureFrames = STILL_TIMES.map((t) => Math.round(t * FPS));
  const dataUrls = await page.evaluate(async (fps, capFrames, lastFrame) => {
    const dt = 1000 / fps, out = {};
    for (let i = 0; i <= lastFrame; i++) {
      window.__viz.render();
      if (capFrames.includes(i)) out[i] = window.__canvas.toDataURL('image/png');
      await new Promise((r) => setTimeout(r, dt));
    }
    return out;
  }, FPS, captureFrames, captureFrames[captureFrames.length - 1]);

  STILL_TIMES.forEach((t, i) => {
    const du = dataUrls[captureFrames[i]];
    if (!du) return;
    const fn = path.join(outDir, `t${String(t).replace('.', '_')}.png`);
    fs.writeFileSync(fn, Buffer.from(du.split(',')[1], 'base64'));
    console.log('wrote', fn);
  });
  await browser.close();
  console.log('done');
})();
