# NACRE.2b Kickoff — port `$$$ Royal - Mashup (431)` faithfully, then uplift

**Paste "Resume NACRE.2b — follow docs/prompts/NACRE_2B_KICKOFF.md" to start the session.**

Bring the butterchurn preset **`$$$ Royal - Mashup (431)`** into Phosphene as a **certified** preset
named **Nacre**, faithful FIRST then uplifted to stems + beat — following the **Dragon Bloom (D-138)**
and **Fata Morgana (D-139)** butterchurn→Phosphene ports. This doc supersedes the earlier
`ROYAL_MASHUP_431_KICKOFF.md` (merged in) and the lighter first draft of this file.

> Lineage: `$$$ Royal - Mashup (220)` became **Dragon Bloom**. 431 shares the author/name, **not the
> look** — do NOT build "Dragon Bloom v2" (D-097: siblings, not subclasses).

## 0. THE one rule — read before writing any code

**Replicate butterchurn's render loop WHOLESALE by reading its source. Do NOT patch Phosphene's
`mv_warp`/comp piecemeal and tune the divergences** (CLAUDE.md FA #70 + #73 + #64; the whole Dragon
Bloom lesson). Read the reference, port the loop; never guess-and-tune.

## 0.5. Current state — NACRE.1 + NACRE.2a are DONE (on `main`, `9ff5a3e`)

This is a **resume at 2b**, not a from-scratch port. Already landed:
- **NACRE.1** — design + curated references: `docs/presets/NACRE_PLAN.md`, `docs/VISUAL_REFERENCES/nacre/`
  (incl. **`source_shaders.txt` — (431)'s verbatim warp + comp + per-frame eqs, already extracted**;
  `source_preset.json`; annotated GIF/stills).
- **NACRE.2a** — wiring + a STUB: `Shaders/Nacre.{metal,json}`, `Presets/Nacre/NacreState.swift`
  (`NacreUniforms` 64 B → comp buffer(1)), HDR opt-in in `PresetLoader.feedbackFormat`,
  `VisualizerEngine(+Presets)` wiring, `NacreMVWarpAccumulationTest` (static + compile guards). Green.

**Three 2a choices to CORRECT in 2b (they diverged from this spec — Matt's call is to align):**
1. 2a used the **shared decay warp** + deferred the blur. **431 has a CUSTOM warp shader** (unsharp via
   a 3-level blur pyramid + treble-gated grain + **0.9 decay INSIDE the warp**). 2b must add
   `nacre_warp_fragment` (with its own decay; do NOT also apply compose decay — D-138).
2. 2a took the lighter Skein convention path (no blur pipeline). **Use the Fata Morgana template** —
   it already ships the custom-warp + fully-replacing-custom-comp + **blur-of-prev pipeline** + uniform
   struct (`blurState` is renderer-wired in `RenderPipeline+MVWarp.swift`/`+FataMorgana.swift`).
3. **Feedback format: HDR-with-fallback (Matt).** Try `.rgba16Float` (already set) for unclamped
   iridescence/bloom; the white-out gate + oracle catch over-accumulation → **fall back to 8-bit** if the
   look breaks. (431's in-warp 0.9 decay may make HDR viable where Dragon Bloom's no-decay loop wasn't.)

## 1. The target — what 431 actually IS

An **iridescent refractive field** — read it as **molten iridescent metal / oil-on-water** with a
mother-of-pearl translucency: a gold-green viscous base with a reaction-diffusion crinkle and a
rainbow oil-slick / nacreous core. **NOT symmetric, NOT floral** (that's 220/Dragon Bloom). Closest
catalog cousin is **Ferrofluid Ocean** (reflective metal + thin-film iridescence) — but FFO is a 3D
ray-march; 431 is a 2D feedback+comp preset. Its own register. Three layers (verify every claim
line-by-line against `source_shaders.txt` / the JSON — FA #73):
1. **Custom warp (feedback transfer):** `prev = texture(sampler_main)`; unsharp-sharpen via the blur
   pyramid (`blur1*0.3 + blur2*0.4 + blur3*0.3`, high-pass); `*0.9` decay (INSIDE the warp);
   **treble-gated scrolling low-freq noise** (`treb_att` → grain); slight desaturate toward luma. The
   reaction-diffusion churn.
2. **Custom comp (display — but it IS the signature):** four expanding radial ripples
   (`fract(phase + time/18)`) → a luminance-gradient bump field (`dz`) + a max-brightness field
   (`ret1`); then **chromatic-dispersed sine interference** (`sin(uv1 + dz*{1.0,1.4,1.8})` per R/G/B →
   the iridescence), `inversesqrt` filaments for thin specular highlights, bump-lit + tinted by
   per-preset randoms + a slow roam. A heavy custom HLSL comp that renders the whole look (like Fata
   Morgana's fully-replacing comp — that path is SOLVED; reuse it).
3. **Default waveform:** `wave_mode 7`, additive, `wave_thick`, `modwavealphabyvolume`, colour drifting
   near-white via slow sines. A bright additive line threading the field.

**Source audio coupling (the faithful map for §7 uplift):** volume → waveform alpha; `treb_att` →
warp grain; `bass_att` → onset detector (`bass_thresh` snaps to 2.13) → `dx/dy_residual` positional
**jolts** (field kicks on bass); `mid_att` → `rg`→`q9`→`zoom += .1*q9` (mid → **zoom breath/surge**).

## 2. Read-first (mandatory — before any .metal)

1. **`docs/PRESET_SESSION_CHECKLIST.md`** cover to cover (governs the session).
2. **`CLAUDE.md`** §Audio Data Hierarchy + FA #70/#73/#64 + §Authoring Discipline.
3. **`docs/DECISIONS.md` D-137 + D-138 + D-139** (uplift framing + the butterchurn render-loop facts:
   swap → warp(prev) → waves on top → comp is display; custom-warp = no extra decay; 32×24 warp mesh;
   6×-boosted audio).
4. **Fata Morgana as the closest template** (the verified custom warp+comp+blur pattern):
   `FataMorgana.metal` + `.json` (read end-to-end — uv-origin flip + sRGB-write notes), `FATA_MORGANA_PLAN.md`,
   `PresetLoader+WarpPreamble.swift`, `RenderPipeline+MVWarp.swift`/`+FataMorgana.swift`/`+MVWarpScene.swift`,
   `DragonBloomMVWarpAccumulationTest.swift` (real-session CSV replay).
5. **`docs/presets/NACRE_PLAN.md`** + **`docs/VISUAL_REFERENCES/nacre/source_shaders.txt`** (already-extracted (431) shaders) + the reference dir.
6. **`tools/dragon_bloom_reference/`** — how to stand up a faithful butterchurn oracle + the
   `fixWarpShader` lesson (the converter mistranslates custom HLSL warp/comp → hand-fix the GLSL body).

## 3. Stand up the live oracle FIRST (before port code)

Mirror `tools/dragon_bloom_reference/` for 431: `convert.js`, vendored `butterchurn.min.js`,
`index.html` with the `fixWarpShader` splice, a `.claude/launch.json` `nacre-ref` entry,
`preview_start` → `preview_screenshot`. The converted preset is at
`tools/milkdrop-render/node_modules/butterchurn-presets/presets/converted/$$$ Royal - Mashup (431).json`
(or `royal_variants/$$$ Royal - Mashup (431).json`; regenerate the gallery via `tools/milkdrop-render/README.md`
if `~/mdrender` is gone). Drive it with a real session's `raw_tap.wav` (under `~/Documents/phosphene_sessions/`;
TCC-protected — copy somewhere the sandbox can read). **431 ships BOTH a custom warp AND a custom comp →
expect the converter to mistranslate both; hand-fix each GLSL body against `source_shaders.txt`.** This
oracle is the per-layer comparison gate — compare frame-by-frame, never against a single still. Matt's
live M7 against the oracle is the load-bearing certification gate.

## 4. Decode the mechanic — checklist EVERY element against the source

Build a faithful-port checklist (like Dragon Bloom's) from `source_shaders.txt` / the JSON. **Verify
§1's decode — do not trust it.** Cover: all `baseVals` (`decay`, `zoom`, `warp`, `warpscale`,
`warpanimspeed`, `wave_mode 7` + `additivewave`/`wave_thick`/`modwavealphabyvolume`/`wave_scale`/`wave_smoothing`,
`gammaadj`, `mv_*` — `mv_a:0` so the motion grid is NOT drawn); the full `frame_eqs_str` (the
`bass_thresh` onset detector, `dx/dy_residual` jolts, `rg`/`q9` zoom, the `wave_r/g/b` sines,
`decay -= .01*equal(mod(frame,6),0)`); `init_eqs_str`; **the custom warp** (unsharp + 0.9 decay +
treble noise + desat); **the custom comp** (ripples + bump + chromatic-dispersion filaments). Shapes +
custom waves are disabled — the only drawn geometry is the default waveform.

## 5. Reuse vs net-new — Fata Morgana is the structural template (VERIFIED)

FM (D-139) already ships exactly 431's pattern: `fata_morgana_warp_fragment` (custom feedback warp that
bakes its own decay, `pf.decay=1.0`, no compose decay), `fata_morgana_comp_fragment` (fully replaces
fixed-function), `fata_morgana_blur_fragment` (blur of prev), `FataUniforms` (CPU-computed comp
uniforms). 431 is **simpler than FM** (no custom shapes). So custom-warp + fully-replacing-custom-comp
is **not a new engine surface** — port 431's warp/comp bodies onto FM's structure. The **net-new** (confirm
each against `FataMorgana.metal`/`PresetLoader+WarpPreamble.swift`, surface the bundle to Matt — three-part bar):
1. **Built-in waveform** (`wave_mode 7` additive) — FM drew shapes, DB drew strands; neither drew a
   built-in waveform. Add a small additive-line draw (the only drawn geometry in 431).
2. **3-level blur pyramid** — 431's warp samples `blur1/2/3`. FM's blur may be single-level → extend to three.
3. **Low-freq noise texture** (`sampler_noise_lq`) for the treble-gated warp grain — confirm one is in
   the mv_warp texture set or bind one.
4. **A few comp/warp uniforms** beyond `FataUniforms`/`NacreUniforms` (`rand_frame`, `roam_*`,
   `slow_roam_*`, `treb_att`) — extend the struct (cheap; `NacreUniforms` already exists, extend it).

Three-part bar: (1) iconic subject at fidelity — the iridescent molten field; cite FFO as proof
iridescence is achievable but note FFO took ~69 rounds (Matt's fidelity-warning rule — pitch within the
achievable bar); (2) one-sentence musical role of the hero element; (3) infra-feasible — YES (FM path).

## 6. Faithful port — harness first, replicate the loop, verify each layer vs the oracle

**Harness FIRST** (checklist: multi-frame before shader work): extend `NacreMVWarpAccumulationTest`
with a real loop driving `RenderPipeline.renderMVWarpToTexture` (the shared headless seam) for ≥60
frames — **real-session `features.csv` + `stems.csv` replay, NEVER synthetic** (FA #27) — through the
live dispatch path (scene → warp → scene-pass → comp → blit → swap), write `/tmp` PNGs, compare to the
oracle. Assert non-black + no white-out (the HDR-fallback trip-wire). Produce an **early contact sheet
before tuning**. Then port every checklist element verbatim, **6× audio boost** on volume-modulated
terms. Watch D-138 pitfalls: **pipeline format must match texture format** (else GPU stall/beachball at
transition); with HDR-fallback, if the float buffer over-blooms, set `feedbackFormat` back to 8-bit; all
shared-pipeline additions gated so other mv_warp presets stay byte-identical (`PresetRegression`).

## 7. Uplift to Phosphene (AFTER faithful replication)

Map the source's drivers (§1) onto **stems + beat** (D-137). One primitive per layer; continuous
energy primary, beats accent. Starting map: **drums/bass-onset → the `dx/dy_residual` jolt** (on the
cached `BeatGrid`/drums energy-dev, not raw onsets — Layer-4: bound the footprint, steady global
luminance); **treble → grain** (warp noise); **mid/harmony → zoom breath**; **vocals → iridescence hue
(or the waveform)**. Motion on energy-weighted `accumulated_audio_time`, not free-running (FA #33).
Comp-stage beat accents are display-side (smoothed envelope, not raw per-frame). Articulate the
one-sentence musical role before authoring. (NACRE_PLAN §6 has the one-primitive-per-layer table.)

## 8. Certify + closeout (full Increment Completion Protocol)

Matt live M7 across several real tracks (Spotify + a local file) vs the oracle. Then: finalize
`NACRE_PLAN.md`; a **DECISIONS** entry (grep `^## D-` for the next number); **CLAUDE.md** durable
learnings + any new Failed Approach; **ENGINEERING_PLAN** row; **RENDER_CAPABILITY_REGISTRY** (a
custom-comp-shader port path = a capability row if newly built); flip `certified` in `Nacre.json` + add
"Nacre" to the ground-truth sets in `FidelityRubricTests.swift` + `PresetDescriptorRubricFieldsTests.swift`;
HDR/format exemptions in `PresetAcceptanceTests.swift` if HDR is kept. Confirm 60 fps at 1080p
(`MTL_HUD_ENABLED=1`). `swiftlint --strict`. `Scripts/closeout_evidence.sh` block. Commit `[NACRE.2b]…`;
**do not push without Matt's "yes, push."**

---

**TL;DR:** Nacre = a molten iridescent-metal / oil-slick / nacreous feedback preset, a DIFFERENT
register from Dragon Bloom despite the shared name. NACRE.1+2a are done (named, wired, stub on `main`);
2b **aligns to this spec**: add the **custom warp + 3-level blur pyramid on the Fata Morgana template**
(2a's shared-decay/convention path was the divergence to fix), stand up the **live oracle**, port the
warp+comp bodies verbatim, verify each layer vs the oracle on real-audio replay, then uplift to
stems/beat (drums→jolt, treble→grain, mid→zoom breath). Feedback = **HDR, fall back to 8-bit if it
over-blooms**. Cardinal rule: port the loop wholesale; never patch-and-tune (FA #70/#73).
