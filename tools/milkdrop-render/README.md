# Milkdrop reference render harness

Renders Milkdrop `.milk` presets to PNG / animated GIF references for the Milkdrop uplift
work, via [butterchurn](https://github.com/jberg/butterchurn) (WebGL Milkdrop port) in
headless Chrome. Built 2026-06-01.

## Setup
```sh
cd tools/milkdrop-render
npm install butterchurn butterchurn-presets milkdrop-preset-converter puppeteer
# ffmpeg required for GIFs:  brew install ffmpeg
```

## Critical limitation (learned the hard way)
- **The runtime `.milk` converter (`milkdrop-preset-converter`) renders *arbitrary* pack
  presets POORLY** — dead/tiny geometry. Only the **100 pre-converted `butterchurn-presets`
  built-ins render faithfully** (they're a curated legends set: Geiss, Flexi, Aderrasi,
  Rovastar, Eo.S, $$$ Royal, Martin, …). Render those, not raw directory `.milk` files.
- **Headless video (MediaRecorder + `requestAnimationFrame`) does NOT work** — rAF doesn't
  fire in headless Chrome. `render-gif.js` uses a `setTimeout` render loop + `ffmpeg` instead.
- Feed **real music** (not synthetic noise) — presets are built for it and look dead otherwise.
  `render-gif.js` decodes `music.wav` (extract one via `ffmpeg -ss <t> -t 12 -i <track> -ac 1 -ar 22050 music.wav`).
- For faithful renders of *arbitrary* pack presets (incl. HLSL), use **projectM native**
  (`brew install projectm` → `projectMSDL`, point `~/.projectM/config.inp` `Preset Path` at a folder).

## Scripts
- `render.js <out> <preset.milk|.json> …` — single-still PNG per preset.
- `render-gif.js <out> <preset.milk|.json> …` — animated GIF + still PNG per preset (real-music-driven).
- `make-gallery.py` — build a scannable `index.html` grid from a GIF output dir.

## Render the legends gallery (the working flow)
```sh
node -e "const fs=require('fs'),bp=require('butterchurn-presets');const P=bp.getPresets?bp.getPresets():bp;fs.mkdirSync('builtins',{recursive:1});for(const[n,p]of Object.entries(P)){fs.writeFileSync('builtins/'+n.replace(/[\/\\\\:]/g,'-').slice(0,120)+'.json',JSON.stringify({preset:p}))}"
node render-gif.js gallery builtins/*.json
python3 make-gallery.py   # -> gallery/index.html
```
