# PR.5 — Dragon Bloom's white-out: the tone-map hypothesis is falsified

**Matt's report (2026-09-04 roster review):** *"Washed out, extreme brightness. Reds look gorgeous.
Would like to see the same saturated color across the visible light spectrum"* — clarified as loss
of saturation from overexposure, not a request for spectrum cycling.

**My hypothesis, from PR's scoping: a missing tone-map.** Dragon Bloom calls no tone-mapping
operator, the drawable is `.bgra8Unorm_srgb`, and `DragonBloom.metal:129` claims its HDR additive
glow is *"tonemapped downstream"* when nothing downstream tone-maps. **That hypothesis is wrong.**

## 1. Measurement

`DragonBloomMVWarpAccumulationTest` (the existing production-dispatch harness for this preset;
`DRAGON_BLOOM_MVWARP_DIAG=1`). Its display post — invert 1.0 / echo 0.5 / gamma 1.07 — matches
`DragonBloom.json`'s `marks.comp` exactly, so `displayPixels` is what the listener sees.

| image | clipped | saturation (bright px) | near-white | mean luma |
|---|---:|---:|---:|---:|
| music **accumulator** (pre-display) | 10.6 % | **0.655** | 0.9 % | — |
| music **display** (shipping) | **91.4 %** | **0.141** | **65.4 %** | 0.929 |
| silence display (shipping) | 100 % | 0.000 | **100 %** | 1.000 |

**The accumulator is not blown.** It is dark and richly saturated (0.655). A tone-map compresses
highlights that are already above 1.0 — there aren't any to speak of. Adding one would not touch
this.

## 2. What actually whitens it

The display stage runs `invert = 1.0` — `bInvert` from the source Milkdrop preset, faithfully
ported, and its documented purpose is to *"flip the cool full-warp fill to warm"*
(`RenderPipeline+PresetSwitching.swift`). Invert maps `c → 1−c`. The accumulator is **mostly
near-black**, so most of the frame inverts to **near-white**. The warm colour survives only where
the accumulator carried strong colour.

Confirmed by rendering with `DRAGON_BLOOM_INVERT=0`:

| | invert 1.0 (shipping) | invert 0.0 |
|---|---:|---:|
| clipped | 91.4 % | **9.7 %** |
| saturation | 0.141 | **0.550** |
| near-white | 65.4 % | **1.8 %** |
| mean luma | 0.929 | **0.316** |

Every number moves the way Matt asked. **And it is still not the fix** — look at the images, not the
table. At invert 0 the frame is **blue/cyan**: the accumulator's native palette is cool, and the
invert is what makes Dragon Bloom warm at all. Turning it off trades "washed out and warm" for
"saturated and cold", which fails the preset's mandatory trait (*warm fiery palette — red/orange/
yellow with green accents*) and its faithful-port mandate.

Silence is the same story from the other end: at invert 1.0 silence renders **pure white** (D-037
says silence must never render black — it renders the opposite); at invert 0 it renders pure black,
violating D-037 directly. Neither end is shippable on its own.

## 3. Where the lever actually is

White appears **wherever the accumulator is near-black**. So the quantity to move is the
accumulator's *coverage* — how much of the frame carries colour before inversion — not the tone
curve and not the invert flag. Two candidate directions, neither measured yet:

1. **Raise accumulator coverage** so less of the frame is near-black going into the invert.
2. **Soften the invert** (partial rather than binary), trading some warmth for less white — this
   needs a render, because the warmth *is* the invert.

## 4. Honest bounds — this is not yet measured on Matt's material

The harness drives a **synthetic** waveform, which FA #27 explicitly warns does not reproduce real
pipeline noise or structure, and the PR.3d standing rule says a user-visible change is not
recommended until it has been measured on Matt's own audio. The direction here is large (saturation
0.141 → 0.550) and unlikely to reverse, but the *degree* on real music is unknown — and Dragon
Bloom is `direct + mv_warp`, so `SessionReplayHarness` cannot replay it from Matt's *Low* session
(the PR.10 blocker). **No fix is proposed from this increment.** The finding is the diagnosis:
tone-mapping is a dead end, and the white is inverted darkness.
