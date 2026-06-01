// Milkdrop reference render harness — butterchurn + headless Chrome → WebM + thumbnail PNG.
// Usage: node render.js <out_dir> <preset1.milk|.json> [more...]
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');
const converter = require('milkdrop-preset-converter');

async function convert(milkText) { return await converter.convertPreset(milkText); }

const W = 960, H = 720, REC_MS = 5000;

(async () => {
  const outDir = process.argv[2];
  const files = process.argv.slice(3);
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await puppeteer.launch({
    headless: 'new',
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

  // Visualizer + loud, beat-pulsing synthetic audio (so presets hit energetic state).
  const setupOk = await page.evaluate((w, h) => {
    try {
      const BC = window.butterchurn && (window.butterchurn.default || window.butterchurn);
      const canvas = document.getElementById('c');
      const AC = window.AudioContext || window.webkitAudioContext;
      const ac = new AC();
      const buf = ac.createBuffer(1, ac.sampleRate * 2, ac.sampleRate);
      const d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1);   // full-amplitude broadband
      const noise = ac.createBufferSource(); noise.buffer = buf; noise.loop = true;
      const bass = ac.createOscillator(); bass.frequency.value = 70;        // sub-bass body
      const mid = ac.createOscillator(); mid.frequency.value = 520;
      const gain = ac.createGain(); gain.gain.value = 1.2;
      const lfo = ac.createOscillator(); lfo.frequency.value = 2.1;         // ~126 bpm beat pulse
      const lfoGain = ac.createGain(); lfoGain.gain.value = 0.8;
      lfo.connect(lfoGain); lfoGain.connect(gain.gain);
      noise.connect(gain); bass.connect(gain); mid.connect(gain);
      noise.start(); bass.start(); mid.start(); lfo.start();
      const viz = BC.createVisualizer(ac, canvas, { width: w, height: h, pixelRatio: 1 });
      viz.connectAudio(gain);
      window.__viz = viz; window.__canvas = canvas;
      return 'ok';
    } catch (e) { return 'setup err: ' + e.message; }
  }, W, H);
  console.log('setup:', setupOk);
  if (setupOk !== 'ok') { await browser.close(); process.exit(1); }

  let ok = 0, fail = 0;
  for (const f of files) {
    const name = path.basename(f).replace(/\.(milk|json)$/, '');
    const webmPath = path.join(outDir, name + '.webm');
    if (fs.existsSync(webmPath)) { console.log('skip', name); ok++; continue; }
    try {
      const preset = f.endsWith('.json')
        ? JSON.parse(fs.readFileSync(f, 'utf8')).preset
        : await convert(fs.readFileSync(f, 'utf8'));
      const res = await page.evaluate(async (p, recMs) => {
        try {
          window.__viz.loadPreset(p, 0.0);
          const stream = window.__canvas.captureStream(30);
          let mime = 'video/webm;codecs=vp9';
          if (!MediaRecorder.isTypeSupported(mime)) mime = 'video/webm;codecs=vp8';
          const rec = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 4e6 });
          const chunks = [];
          rec.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
          rec.start();
          const t0 = performance.now();
          let thumb = null;
          await new Promise((resolve) => {
            const loop = () => {
              window.__viz.render();
              const t = performance.now() - t0;
              if (t > recMs * 0.5 && !thumb) thumb = window.__canvas.toDataURL('image/png');
              if (t < recMs) requestAnimationFrame(loop); else { rec.stop(); }
            };
            rec.onstop = async () => {
              const blob = new Blob(chunks, { type: 'video/webm' });
              const ab = await blob.arrayBuffer();
              const b64 = btoa(String.fromCharCode(...new Uint8Array(ab)));
              resolve({ webm: b64, thumb });
            };
            requestAnimationFrame(loop);
          }).then((r) => { window.__out = r; });
          return 'ok';
        } catch (e) { return 'render err: ' + e.message; }
      }, preset, REC_MS);
      if (res !== 'ok') { console.log('FAIL', name, res); fail++; continue; }
      const out = await page.evaluate(() => window.__out);
      fs.writeFileSync(webmPath, Buffer.from(out.webm, 'base64'));
      if (out.thumb) fs.writeFileSync(path.join(outDir, name + '.png'),
        Buffer.from(out.thumb.split(',')[1], 'base64'));
      const kb = Math.round(fs.statSync(webmPath).size / 1024);
      console.log('OK  ', name, `(${kb} KB webm)`);
      ok++;
    } catch (e) { console.log('FAIL', name, e.message.slice(0, 80)); fail++; }
  }
  console.log(`\n=== done: ${ok} ok, ${fail} failed ===`);
  await browser.close();
})();
