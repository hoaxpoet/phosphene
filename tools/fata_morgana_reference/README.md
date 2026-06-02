# Fata Morgana — live Milkdrop reference (butterchurn)

Stands up the **actual** `martin [shadow harlequins shape code] - fata morgana` Milkdrop preset running
in [butterchurn](https://github.com/jberg/butterchurn) so the Phosphene port can be compared
**frame-by-frame against the true reference**. Direct successor to `tools/dragon_bloom_reference/`
(D-137/D-138); the faithful-port discipline is **CLAUDE.md FA #70**.

Approved by Matt 2026-06-02 ("mirage first, decide uplift later"). This is the comparison gate the
faithful mirage port iterates against. Plan: `docs/presets/FATA_MORGANA_PLAN.md`. Full mechanic decode:
`/tmp/fata_faithful_checklist.md`.

## Unlike Dragon Bloom — clean GLSL, no warp-shader fix

The preset is a **butterchurn builtin** (the official `butterchurn-presets` pack), so its converted JSON
(`fata_ref_preset.json`, committed) has **clean GLSL warp/comp shaders** — there is NO `fixWarpShader`
hack here (the Dragon Bloom reference needed one because that preset was converted with the broken Node
`milkdrop-preset-converter`). `index.html` loads `fata_ref_preset.json`'s `.preset` directly.

## What it is

A **mirage**: starfield sky + glowing horizon + reflective rippling neon floor. 4 custom SHAPES (40-gons;
no waves) + a custom feedback WARP shader + a custom procedural COMP shader (the mirage). See the plan.

## Regenerate

```bash
cd tools/fata_morgana_reference
# 1. preset JSON (committed) came from the butterchurn-presets builtin:
#    /private/tmp/mdrender/builtins/martin [shadow harlequins shape code] - fata morgana.json  (the .preset key)
# 2. Vendor the UMD bundle + a real session tap to drive it:
cp <butterchurn>/lib/butterchurn.min.js .
cp <a real session>/raw_tap.wav audio.wav     # any 30 s session tap works
```

Then serve and open in the preview browser. A `.claude/launch.json` config named `fata-ref` runs
`python3 -m http.server` on port 8734 against this dir. Use `preview_start fata-ref` →
`preview_screenshot`. `window.__status` exposes `{ready, ctxState, elapsed, audioRMS, bufDur}` for polling.

## Harness notes

- **Boost the audio ~6×** (`?boost=` URL param, default 6.0). The recorded tap is ~−18 dB; the shapes'
  `rad *= {bass,mid,treb}_att` collapse to ~0 on quiet input otherwise (D-138 finding; butterchurn feeds
  6×-boosted audio).
- 640×480 (4:3) — Milkdrop's projection assumes it. Phosphene renders 16:9; the oracle is the comparison
  reference, not a hard aspect lock (see the plan's aspect note).
