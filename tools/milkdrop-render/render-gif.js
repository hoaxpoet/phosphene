// Milkdrop reference harness — butterchurn → animated GIF + strong-audio still PNG.
// Uses the proven setTimeout render loop (not rAF/MediaRecorder) + ffmpeg.
// Usage: node render-gif.js <out_dir> <preset.milk|.json> [more...]
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');
const puppeteer = require('puppeteer');
const converter = require('milkdrop-preset-converter');

async function convert(milkText) { return await converter.convertPreset(milkText); }

const W = 640, H = 480;            // render size
const FPS = 30, SECS = 4;          // real-time render duration
const CAP_EVERY = 2;               // capture every Nth frame -> 15fps gif
const GIF_W = 420;

(async () => {
  const outDir = process.argv[2];
  const files = process.argv.slice(3);
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl',
      `--window-size=${W},${H}`],
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
      // decode the real-music clip
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
  console.log('setup:', setupOk);
  if (setupOk !== 'ok') { await browser.close(); process.exit(1); }

  let ok = 0, fail = 0;
  for (const f of files) {
    const name = path.basename(f).replace(/\.(milk|json)$/, '');
    const gifPath = path.join(outDir, name + '.gif');
    if (fs.existsSync(gifPath)) { ok++; continue; }
    try {
      const preset = f.endsWith('.json')
        ? JSON.parse(fs.readFileSync(f, 'utf8')).preset
        : await convert(fs.readFileSync(f, 'utf8'));
      // Render real-time via setTimeout; capture frames as dataURLs.
      const frames = await page.evaluate(async (p, fps, secs, every) => {
        try {
          window.__viz.loadPreset(p, 0.0);
          // fresh music source per preset (one-shot), feeding butterchurn's analyser
          const src = window.__ac.createBufferSource();
          src.buffer = window.__musicBuf; src.connect(window.__gain); src.start(0);
          const total = fps * secs, dt = 1000 / fps, out = [];
          for (let i = 0; i < total; i++) {
            window.__viz.render();
            if (i % every === 0) out.push(window.__canvas.toDataURL('image/png'));
            await new Promise((r) => setTimeout(r, dt));
          }
          try { src.stop(); } catch (e) {}
          return out;
        } catch (e) { return { err: e.message }; }
      }, preset, FPS, SECS, CAP_EVERY);
      if (!Array.isArray(frames)) { console.log('FAIL', name, frames.err); fail++; continue; }
      // Write frames, ffmpeg -> gif, keep a mid still.
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gif-'));
      frames.forEach((du, i) => fs.writeFileSync(
        path.join(tmp, `f${String(i).padStart(3, '0')}.png`),
        Buffer.from(du.split(',')[1], 'base64')));
      const pal = path.join(tmp, 'pal.png');
      const capFps = FPS / CAP_EVERY;
      execFileSync('ffmpeg', ['-y', '-framerate', String(capFps), '-i', path.join(tmp, 'f%03d.png'),
        '-vf', `scale=${GIF_W}:-1:flags=lanczos,palettegen`, pal], { stdio: 'ignore' });
      execFileSync('ffmpeg', ['-y', '-framerate', String(capFps), '-i', path.join(tmp, 'f%03d.png'),
        '-i', pal, '-lavfi', `scale=${GIF_W}:-1:flags=lanczos[x];[x][1:v]paletteuse`, gifPath], { stdio: 'ignore' });
      // strong-audio still = a late frame (trails developed)
      const stillSrc = path.join(tmp, `f${String(Math.floor(frames.length * 0.7)).padStart(3, '0')}.png`);
      if (fs.existsSync(stillSrc)) fs.copyFileSync(stillSrc, path.join(outDir, name + '.png'));
      fs.rmSync(tmp, { recursive: true, force: true });
      const kb = Math.round(fs.statSync(gifPath).size / 1024);
      console.log('OK  ', name, `(${kb}KB gif)`);
      ok++;
    } catch (e) { console.log('FAIL', name, String(e.message).slice(0, 80)); fail++; }
  }
  console.log(`\n=== ${ok} ok, ${fail} failed ===`);
  await browser.close();
})();
