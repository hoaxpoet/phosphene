# Kickoff — Port `martin [shadow harlequins shape code] - fata morgana` (butterchurn → Phosphene)

**Goal:** bring the Milkdrop/butterchurn preset **`martin [shadow harlequins shape code] - fata morgana`** into Phosphene as a **certified** preset, uplifted to Phosphene's stems + beat — following the Dragon Bloom precedent (**D-137 / D-138**, the most recently certified preset and the direct template for this work).

---

## 0. THE one rule — read this before writing any code

**Replicate butterchurn's render loop WHOLESALE by reading its source. Do NOT patch Phosphene's `mv_warp` piecemeal and tune the divergences.** This is **CLAUDE.md Failed Approach #70** and the entire lesson of the Dragon Bloom port (D-138): bending Phosphene's differently-shaped feedback engine to *imitate* butterchurn one symptom at a time took hours of traded divergences (pale → over-bright → jitter → a GPU-stall hang); the moment the actual butterchurn source was read, every divergence resolved fast and consistently.

**Read these first, in order:**
1. `CLAUDE.md` FA #70 (the method rule) + FA #39/#63 (don't author without reading references) + the Audio Data Hierarchy section.
2. `docs/DECISIONS.md` **D-138** — the durable butterchurn render-loop facts (they carry over): per-frame loop = **swap → warp(prev) → draw waves/shapes normal-alpha ON TOP → that IS the feedback; comp (echo/gamma/invert) is display-only**; **custom-warp presets apply NO decay** (`warpColor=1`); **8-bit feedback** (the per-frame clamp holds the saturated equilibrium — float over-accumulates pale); **symmetry from the video echo, not geometry mirroring**; the warp is a **32×24 vertex mesh**; butterchurn feeds **6×-boosted audio**.
3. `docs/DECISIONS.md` **D-137** — the uplift framing (translate the preset's *identity* onto Phosphene's platform — stems, HDR, mood palette — faithful FIRST, then adapt).
4. The Dragon Bloom implementation as the template: `PhospheneEngine/Sources/Presets/Shaders/DragonBloom.metal` + `.json`, `PresetLoader+WarpPreamble.swift` (the injected warp transfer + comp), `RenderPipeline+MVWarp.swift` / `+MVWarpScene.swift` (the loop + waves-on-top + beat pump), and the diag `DragonBloomMVWarpAccumulationTest.swift` (real-session CSV replay).
5. The live reference harness `tools/dragon_bloom_reference/` (how to stand up a faithful butterchurn oracle + the `fixWarpShader` lesson: the offline converter mistranslates custom HLSL warp/comp shaders — hand-fix them).

---

## 1. Stand up the live oracle FIRST (before any port code)

- Obtain the preset's `.milk` source. Convert to butterchurn JSON and stand up a **live butterchurn page rendering the actual preset**, driven by a real session's `raw_tap.wav` — mirror `tools/dragon_bloom_reference/` exactly (`convert.js`, the vendored `butterchurn.min.js`, `index.html`, the `dragon-ref`-style `.claude/launch.json` entry, `preview_start` → `preview_screenshot`). Use a real recorded session for the audio (e.g. one under `~/Documents/phosphene_sessions/` — note these are TCC-protected; the recording must be copied somewhere the sandbox can read, as happened in the Dragon Bloom session).
- **Apply the converter fix:** custom warp/comp HLSL shaders come through as garbage (`bvecN(..) && bvecN(..)`); hand-write the correct GLSL body, splicing it into the converter's wrapper (see `fixWarpShader` in `tools/dragon_bloom_reference/index.html`).
- This live oracle is the comparison gate for every layer. Compare frame-by-frame, not against a single still. Matt's live M7 against the oracle is the load-bearing certification gate.

## 2. Decode the mechanic — read `source.milk` line by line

The preset name says "**shape code**" → it almost certainly uses **`shapecode_N`** (custom SHAPES: filled / textured / bordered N-gons with per-instance transforms), which is a **DIFFERENT butterchurn feature than Dragon Bloom's custom WAVES** (line-strip strands). Confirm from the source — do not assume; "fata morgana" (a mirage) suggests shimmering/refractive/atmospheric, but the mechanic comes from the code, not the name.

Build a complete checklist (like `/tmp/db_faithful_checklist.md` did for Dragon Bloom) of **every** element: baseVals (decay, zoom, rot, warp, `fVideoEcho*`, `fGammaAdj`, `bBrighten/bDarken/bSolarize/bInvert`, wave/shape/`modwavealpha` settings), `per_frame_*`, `per_pixel_*` (the warp mesh), the custom **warp shader** (`warp_N`), the custom **comp shader** (`comp_N` — check `PSVERSION_COMP`; Dragon Bloom used the *fixed-function* comp, but this one may ship a custom HLSL comp = an extra display-only port), every `shapecode_N` block (sides / textured / additive / thickOutline / border / `shape_N_per_frame*` / `per_point*`), and any `wavecode_N`.

## 3. Reuse vs net-new — surface scope to Matt BEFORE building (three-part bar)

**Reusable from D-138 (substantial):** the mv_warp custom-warp loop (no-decay warp + the colour-transfer fragment gated by `chromaticMix`), the comp at the blit (`setMVWarpPost` echo/gamma/invert + the beat pump), 8-bit `feedbackFormat`, the **scene-geometry overlay draw path** (`RenderPipeline+SceneGeometry.swift` / `encodeMVWarpScenePass` strands-on-top branch), the real-session-replay diag harness pattern, and the format-match + gating discipline.

**Likely NET-NEW: a custom-SHAPE draw path.** Phosphene's scene-geometry overlay currently draws line-strip strands. Shapes are filled/textured n-gons (per-instance transform, additive vs normal blend, optional border, optional sampling of the previous frame as a texture). That is a new engine surface — a shape geometry conformer + shader — analogous to but distinct from the strand path. Read butterchurn's `CustomShape` draw (vertex/color/texture/blend math) and port it. **If `comp_N` is a custom HLSL shader, that's a second new port** (display-only, like the warp shader).

**Apply the concept-viability / three-part bar (CLAUDE.md Authoring Discipline) and surface the infrastructure scope to Matt before building:** (1) iconic subject deliverable at fidelity, (2) clear musical role, (3) infra-feasible. If the shape path is a large lift, get sign-off on the approach first. Don't silently expand scope (Increment Completion Protocol "stop and report").

## 4. Faithful port (replicate the loop, verify against the oracle each layer)

- `passes: ["direct", "mv_warp"]`, reusing the D-138 infrastructure + the new shape path. Port every checklist element verbatim. **6× audio boost** where the source's volume-modulated terms expect it.
- Stand up the diag harness (clone `DragonBloomMVWarpAccumulationTest`): real-session `features.csv` + `stems.csv` replay (NEVER synthetic envelopes — `feedback_synthetic_audio`), render through the **live dispatch path** (scene → warp → scene-pass → blit → swap; production-grade testing rule), write `/tmp` PNGs, compare to the oracle. Matt M7 per layer.
- **Watch the D-138 pitfalls:** pipeline format must match texture format or the GPU stalls (beachball at the preset transition); the 8-bit feedback clamp is load-bearing; all shared-pipeline additions gated so other mv_warp presets stay byte-identical (`PresetRegression`).

## 5. Uplift to Phosphene (AFTER faithful replication)

Map the preset's audio drivers onto Phosphene's **stems + beat** (the D-137 move). Faithful FIRST, then adapt. **One primitive per visual layer**, continuous energy primary / beats accent (Audio Data Hierarchy). The Dragon Bloom music response is the template: each visual element an instrument (drums/bass/vocals), energy-driven "breathing", a **comp-stage beat pump** (display-only, so it punches through the no-decay feedback — smoothed envelope, NOT raw per-frame; the drums-dev driver was too noisy on the process-tap), and motion on `accumulated_audio_time` (energy-weighted, not free-running — FA #33). Articulate the one-sentence musical role of the hero element before authoring.

## 6. Certify + closeout (full Increment Completion Protocol)

Matt live M7 across several real tracks (Spotify + a local file). Then: a **new plan doc** `docs/presets/FATA_MORGANA_PLAN.md`; **DECISIONS** entry (grep `^## D-` for the next number — D-139 as of this writing); **CLAUDE.md** durable learnings + any new Failed Approach; **ENGINEERING_PLAN** increment row; **RENDER_CAPABILITY_REGISTRY** (the shape draw path = a new capability row); the cert flag in the JSON + add the preset to the `certifiedPresets` ground-truth sets in `FidelityRubricTests.swift` and `PresetDescriptorRubricFieldsTests.swift`; any HDR/format exemptions in `PresetAcceptanceTests.swift`. Confirm 60 fps at 1080p (Metal HUD, `MTL_HUD_ENABLED=1`). Commit locally to `main`; **do not push without Matt's explicit "yes, push."** swiftlint `--strict` (split helpers to a new file if `file_length > 400` for `.swift`).

---

**TL;DR:** stand up the live oracle → read the `.milk` + butterchurn source and checklist every element → decide reuse (D-138 mv_warp loop) vs net-new (custom-shape draw path; possibly a custom comp shader) and clear the scope with Matt → replicate the loop faithfully, verifying each layer against the oracle via a real-audio diag → uplift to stems/beat → certify + full closeout. The cardinal rule the whole way: port the loop wholesale from the source; never patch-and-tune the divergences (FA #70).
