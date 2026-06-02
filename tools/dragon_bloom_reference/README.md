# Dragon Bloom — live Milkdrop reference (butterchurn)

Stands up the **actual** `$$$ Royal - Mashup (220)` Milkdrop preset
(`docs/VISUAL_REFERENCES/dragon_bloom/source.milk`) running in
[butterchurn](https://github.com/jberg/butterchurn) (open-source WebGL Milkdrop)
so the Dragon Bloom port can be compared **frame-by-frame against the true
reference**, not just the single still `01_target.png`.

Approved by Matt 2026-06-02 ("stand up the live reference"). This is the
reference loop the faithful port iterates against.

## Why this exists

Reading `source.milk` revealed the reference mechanic is **not** Spike 1's flat
polar-waveform ring. See `docs/presets/DRAGON_BLOOM_PLAN.md` §"Mechanic decode".
The live reference confirms the mechanic visually and is the comparison target.

## Regenerate

```bash
cd tools/dragon_bloom_reference
npm init -y && npm install milkdrop-preset-converter butterchurn
# 1. Convert source.milk -> butterchurn JSON (already committed as dragon_ref_preset.json):
cp ../../docs/VISUAL_REFERENCES/dragon_bloom/source.milk source.milk
node convert.js                       # writes dragon_ref_preset.json
# 2. Vendor the UMD bundle + supply an audio file to drive it:
cp node_modules/butterchurn/lib/butterchurn.min.js .
cp <a real session>/raw_tap.wav audio.wav     # any 30 s session tap works
```

Then serve the directory and open it in the preview browser. A `.claude/launch.json`
config named `dragon-ref` runs `python3 -m http.server` on port 8733 against this
dir (adjust `--directory`). Use `preview_start dragon-ref` → `preview_screenshot`.

## The warp-shader fix (load-bearing — learned 2026-06-02)

The offline `milkdrop-preset-converter` (Node) **mistranslated the custom HLSL
warp shader** (`source.milk` `warp_1..21`, the chromatic colour-separation
feedback shader): every operator in the shader body became `bvecN(..) && bvecN(..)`
(e.g. `(uv-0.5)*zoom + 0.5` → `bvec2((uv-0.5)*zoom) && bvec2(0.5)`). The
feedback warp was therefore garbage and the harness rendered **crisp strands with
no feathering** — nothing like `target_animated.gif`. The shader-converter wasm
evidently does not run under Node 25.

`index.html` repairs this at load via `fixWarpShader()`: the converter's
wrapper/ABI (`main_shader_sentinel(uv)` → `shader_body`; `sampler_main`,
`uv_orig`, `texsize`, `sampler_noise_lq` uniforms) is intact, so we splice in a
**hand-written GLSL body** that is a faithful translation of the HLSL
`warp_1..21`. With it, the harness reproduces the warm dense feathered bloom of
the references (matches `01_target.png` + the gif's dense frames). **This warp
shader is the entire reason the preset reads as a warm feathered bloom rather
than bare strands** — it is the chromatic feedback that fills + colours the frame.

## Harness notes (learned 2026-06-02)

- **Boost the audio ~6×** (`window.__boost`, default 6.0 in `index.html`). The
  recorded tap is ~−18 dB — far below butterchurn's level scale. The preset's
  per-pixel `zoom *= min(1.05, max(1, max(bass,treb)))` only counteracts the
  baseline inward zoom (0.99951) when bands exceed 1.0, so quiet input collapses
  the bloom to a central blob on a white field.
- **`bInvert=1` in the source inverts the empty/dark frame to WHITE.** The
  faithful-looking dark-background reference (matching `01_target.png`'s tone)
  is seen with invert **off** — set `p.baseVals.invert=0` before `loadPreset`.
  `01_target.png` appears to have been captured non-inverted.
- The audio graph must reach `destination` (through a near-silent gain) or the
  analyser is never pulled and butterchurn renders silence.
- `window.__status` exposes `{ready, ctxState, elapsed, audioRMS, err}` for
  `preview_eval` polling.
