# Phase MD — Pre-Strategy Audit (2026-05-12)

Audit run before authoring `docs/MILKDROP_STRATEGY.md`. Facts only;
recommendations live in the strategy doc.

## 0.1 — Pack accessibility

Cloned `https://github.com/projectM-visualizer/presets-cream-of-the-crop`
shallow into `/tmp/presets-cream-of-the-crop` for this session.

Top-level structure: 11 theme directories (Dancer, Drawing, Fractal,
Geometric, Hypnotic, Particles, Reaction, Sparkle, Supernova, Waveform,
plus a tiny `! Transition` directory of 4 files).

Total `.milk` files: **9,795**.

## 0.2 — License posture

`LICENSE.md` quoted in full (61-word file):

> Milkdrop presets were, in almost all cases, not released under any
> specific license. Theoretically, each preset author holds the full
> copyright on any released presets. Since the presets were freely
> released and have been used in so many packages and applications in
> the past two decades, it is safe to assume them to be in the public
> domain.
>
> If any preset author doesn't want their own creation in this
> repository, please contact the projectM team and we will remove the
> preset(s) from future releases.

Pack curator: ISOSCELES (per `README.md`). Original pack
(`https://www.patreon.com/posts/pack-nestdrop-91682111`) and historical
context blog post are referenced. The pack itself does not carry an
SPDX-identifiable license; the curator's stated posture is
public-domain-by-convention with a project-managed takedown path.

Open question for Matt: is "public-domain-by-convention with takedown"
acceptable for Phosphene's MIT-licensed catalog? Counsel review
recommended before MD.5 lands publicly. The CREDITS.md attribution
pattern used for the Open-Unmix HQ and Beat This! ML weights is the
natural template.

## 0.3 — mv\_warp consumer state

The prompt's framing — "mv\_warp has zero production consumers since
D-029 pulled it from Starburst and VolumetricLithograph" — is
**factually wrong**. Grep over `PhospheneEngine/Sources/Presets/Shaders/*.json`
for `"mv_warp"`:

```
PhospheneEngine/Sources/Presets/Shaders/Gossamer.json
```

CLAUDE.md confirms two consumers:

* **Gossamer** (Increment 3.5.6, 2026-04-XX): "mv\_warp trails accumulate
  wave echoes."
* **Volumetric Lithograph** (Increment MV-2, v4.1): "MV-2: mv\_warp pass
  adds temporal feedback accumulation."

VL's pass list is set in code rather than JSON ("Passes: ray\_march +
post\_process + mv\_warp" per CLAUDE.md). So the JSON grep undercounts.

This is significant for the strategy doc: Phase MD is **not** the
first production home for mv\_warp; it joins an existing pattern. The
risk surface is narrower than the "build a new pass and hope it
works" framing suggested. mv\_warp + ray-march composition has one
precedent (VL), which informs MD.7 hybrid scoping.

## 0.4 — MV-3 capability availability

All capabilities have real value paths:

| Capability | Type | Wiring path |
|---|---|---|
| `beatPhase01` | `FeatureVector` float 35 | `MIRPipeline.swift:324` (drift path) + `:337` (predictor path); CSV-logged |
| `vocalsPitchHz` | `StemFeatures` float 41 | `StemFeatures.swift:124`, populated in `StemAnalyzer` via `PitchTracker` |
| `onsetRate` (per stem) | `StemFeatures` floats 25/29/33/37 | `StemAnalyzer+RichMetadata.swift:78` |
| `attackRatio` (per stem) | `StemFeatures` floats 27/31/35/39 | `StemAnalyzer+RichMetadata.swift:51` |
| `energySlope` (per stem) | `StemFeatures` floats 28/32/36/40 | `StemAnalyzer+RichMetadata.swift:54` |
| `centroid` (per stem) | `StemFeatures` floats 26/30/34/38 | `StemAnalyzer.swift:283` |

No stubs. The strategy doc can treat MV-3 as a real surface to gate
mandatory/opt-in choices against.

## 0.5 — Paradigm distribution

The prompt's pre-audit heuristics needed refinement once the actual
file format was inspected (it grossly underestimated HLSL prevalence).
Final counts across all 9,795 files:

| Feature | Count | Share |
|---|---:|---:|
| `per_frame_NN` expression equations | 9,674 | 98.8 % |
| `per_pixel_NN` expression equations (warp grid) | 6,049 | 61.8 % |
| Embedded HLSL warp shader (`warp_1=`) | **7,924** | **80.9 %** |
| Embedded HLSL composite shader (`comp_1=`) | **7,971** | **81.4 %** |
| `shapecode_NN_*` shapes | 9,556 | 97.6 % |
| `wave_NN_per_frame` custom waveforms | 3,121 | 31.9 % |

PSVERSION distribution (HLSL revision indicator):

| PSVERSION | Count | Meaning |
|---:|---:|---|
| 2 | 4,739 | Embedded HLSL, Milkdrop 2.x compatible |
| 3 | 3,488 | Newer HLSL feature set |
| 4 | 21 | Most-modern HLSL |

**Major finding the prompt did not anticipate**: 81 % of the
cream-of-crop pack ships **literal HLSL pixel-shader source** in the
`.milk` file (in the `warp_1=…warp_NN=` and `comp_1=…comp_NN=` line
groups). The transpiler (MD.2) is not just an expression-language
translator — it must also handle HLSL → MSL cross-compilation, which
is a materially larger surface.

HLSL-free presets (the natural transpiler-proof MD.5 candidates):
**1,559 total**, distributed:

| Theme | HLSL-free count |
|---|---:|
| Fractal | 492 |
| Geometric | 265 |
| Dancer | 262 |
| Waveform | 180 |
| Reaction | 133 |
| Supernova | 120 |
| Particles | 64 |
| Drawing | 23 |
| Sparkle | 18 |
| Hypnotic | 1 |
| ! Transition | 1 |

File sizes (all 9,795): P10 = 6.3 KB, P50 = 11.0 KB, P90 = 19.2 KB,
max = 164.4 KB. The HLSL bloats them — HLSL-free presets median in
the low single-digit KB range (the smallest 20 are all under 1.2 KB).

## 0.6 — Sample preset characterizations

Eight representative presets sampled across themes. `pf` =
`per_frame_NN` count, `pp` = `per_pixel_NN` count, `warp_hlsl` =
`warp_NN=` line count (presence of HLSL), `wave_eqn` =
`wave_NN_per_frame` line count.

| Preset | Size | pf | pp | warp\_hlsl | wave\_eqn | Notes |
|---|---:|---:|---:|---:|---:|---|
| Fractal — Flexi *Wolfram's Rule 90* | 9.1 KB | 8 | 30 | 19 | 0 | Cellular automaton in HLSL (rule lookup in warp shader). Per-pixel grid + warp shader both populated. |
| Geometric — amandio c *Fume (NV)* | 5.0 KB | 3 | 0 | 18 | 0 | Pure HLSL — no per\_pixel grid, expression layer is just a 3-line setup. All visual logic in `warp_1=…warp_18=`. |
| Waveform — Waltra *Codex Machine 2* | 8.0 KB | 46 | 0 | 15 | 0 | Heavy per-frame expression state, all visual logic delegated to HLSL. |
| Reaction — cope *Drove through ghosts* | 5.8 KB | 7 | 0 | 26 | 0 | Reaction-diffusion in HLSL warp shader. |
| Dancer — suksma *Biotoxins on strings* | 10.5 KB | 61 | 0 | 46 | 16 | Custom waveform per-frame equations + heavy HLSL. Likely complex. |
| Particles — yin *Ocean of Light* | 13.4 KB | 40 | 0 | 0 | 48 | **HLSL-free.** Pure expression-language preset driven by 48-line waveform equations. Strong MD.5 candidate. |
| Hypnotic — suksma *water + god* | 15.2 KB | 67 | 23 | 20 | 10 | Everything everywhere — per\_pixel grid + custom waves + HLSL. Largest grammar surface in sample. |
| Supernova — Stahlregen + Flexi + Geiss + … *Complex Nova* | 6.8 KB | 8 | 1 | 16 | 0 | Multi-author collaboration; minimal per-frame state, HLSL-dominated. |

Pattern: post-2010 presets (PSVERSION ≥ 2) lean on HLSL almost
exclusively; the expression layer is reduced to per-frame variable
setup that the HLSL shader then consumes. Pre-HLSL presets (PSVERSION
implicit or = 1) use the per\_pixel warp grid as the primary motion
source — these are the simpler transpiler targets and align with the
1,559-preset HLSL-free subset above.

## 0.7 — Anomalies / scope-shaping facts

1. **HLSL prevalence (81 %) is the dominant scope risk.** The MD.2
   transpiler must either (a) restrict to the 1,559 HLSL-free presets,
   (b) hand-port the HLSL portion preset-by-preset, or (c) bring in an
   HLSL → MSL cross-compiler (SPIRV-Cross, naga, or similar).
   Recommendation in strategy doc Decision H.

2. **License posture is "public-domain-by-convention," not a clean
   SPDX licence.** Counsel review is appropriate before public commit
   per Decision I.

3. **mv\_warp is already a load-bearing pass in two presets** (Gossamer
   + VL). Phase MD's planned consumers are additive, not pioneering.
   Reduces architectural risk on MD.6 / MD.7.

4. **Theme directories ARE a useful family taxonomy** for the
   strategy doc's catalog story — Fractal / Geometric / Waveform /
   Reaction / Dancer / Drawing / Sparkle / Particles / Supernova /
   Hypnotic. Better than the 5-family breakdown the prompt sketched;
   maps directly to a `family` JSON value the orchestrator can score
   against.

5. **Shapes are nearly universal** (97.6 % of presets have at least
   one `shapecode_NN_*` block). The Milkdrop "shape" primitive (a
   filled polygon with per-frame equations driving position / colour /
   angle) doesn't have a one-to-one Phosphene analogue. Either the
   transpiler renders shapes as 2D triangle fans into a feedback layer
   (achievable), or shape-heavy presets are excluded from MD.5.

6. **The transpiler grammar surface has four distinct sub-languages**:
   - per-frame / per-frame-init expression language (numeric, C-like
     statements).
   - per-pixel grid expression language (same syntax, different scope:
     `x`, `y`, `rad`, `ang` per-grid-vertex).
   - per-shape / per-wave / per-shape-init / per-wave-init
     expressions (same syntax again).
   - Embedded HLSL pixel-shader source (a different language).

   The first three share a parser; the fourth is its own track.
   Decision H needs to address scope per sub-language.

## Closeout

Audit complete. Strategy doc drafted in
`docs/MILKDROP_STRATEGY.md` cites this file for the empirical claims.
The audit findings prompted two strategy-shaping revisions from the
pre-session framing:

- The transpiler is two parsers (expression + HLSL), not one;
  Decision H is reframed accordingly.
- mv\_warp has existing consumers; Phase MD is incremental on an
  existing surface, not pioneering. Risk surface for MD.6 / MD.7 is
  smaller than the prompt assumed.
