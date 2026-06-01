# Dragon Bloom — Visual References

**Target:** a faithful Phosphene uplift of the Milkdrop preset `$$$ Royal - Mashup (220)`
(cream-of-crop `Dancer/Petals/`). Matt's name + "faithful" framing, 2026-06-01.

## Target read
A warm, **bilaterally-symmetric feathered bloom** — fiery red/orange/yellow petal/moth
forms radiating from a center, with rich flowing feedback texture. Calm-but-alive; the
bloom breathes and the feathers stream with the music. See `01_target.png` (faithful
butterchurn still, real-music-driven) and `target_animated.gif` (motion).

## Source mechanic (`source.milk`)
- `nWaveMode=7` waveform, `fWaveScale=1.286`, `wave_r/g/b=0.65`
- Feedback: `fDecay=0.95`, `fVideoEchoAlpha=0.5`, `zoom=0.9995`, `warp=0.01`, `rot=0`
- **`nMotionVectorsX/Y = 12/9`** — the motion-vector flow field that creates the feathering
- Bilateral symmetry; little per-frame equation reactivity — **the audio comes through the
  waveform shape itself + feedback dynamics.**

## Mandatory traits
- Warm fiery palette (red/orange/yellow) with green accents; symmetric bloom silhouette.
- **Rich feedback texture** — the feathered flow is what carries it. The symmetry works
  ONLY because the texture is rich; flat mirrored shapes = Failed Approach #48 (clipart
  symmetry, the Arachne anti-reference). Mirror a feedback-warped field, never flat geometry.

## Build pointers
- **Plan:** `docs/presets/DRAGON_BLOOM_PLAN.md` (feasibility-researched; mv_warp / D-027).
- **Code reference:** Starburst (`direct + mv_warp` preset) — the pattern to build from.
- **Faithful** (Matt 2026-06-01): match the warm symmetric feathered bloom closely.
