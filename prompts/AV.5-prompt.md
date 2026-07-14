# Increment AV.5 — Aurora Veil footprint reauthor (preset)

**Type:** preset (density-model reauthor)

**Objective.** After this session, Aurora Veil renders as **discrete, diaphanous, dancing aurora curtains with real negative space** in a dramatic multi-colour palette — the *desired expression* — instead of the shipped full-field "wash." The aurora emission is factored the Lawlor way, `emission = H(z) × F(x,y)`, with `F(x,y)` a real **footprint** (bright only along a few meandering curtain bands, dark between) advected by **curl-noise** (Wittens vortical motion) so the curtains curl, drift and fold with the music. The half-bar **star blink** Matt requested is integrated. Feasibility is already proven (AV.4 spike — see read-first); this session refines the spike into a certifiable preset and validates motion on a real track + live M7.

Why this exists: the nimitz full-field model, however good it *looks*, is the wrong *expression* — its `F(x,y)` is bright everywhere, so it fills the frame and no motion/undulation tweak can turn it into curtains. Aurora Veil was paused for exactly this; Matt confirmed the reauthor 2026-07-14.

---

## Skill invocations

- `preset-session` — **before** opening `AuroraVeil.metal` or its sidecar.
- `shader-authoring` — **before** any GPU/MSL edit.
- `closeout` — at the end.

## Read-first (in order)

1. `memory: project_aurora_veil_reauthor` (the decision, grounding, spike result, process lessons).
2. `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` §1.2 (Lawlor `H(z)×F(x,y)` + the **"do not put altitude in the noise call"** rule), §1.3 (Wittens curl-noise motion), §2.2 (failure-mode taxonomy), §2.3 (9-question authenticity rubric — the cert gate).
3. `docs/presets/AURORA_VEIL_DESIGN.md` §5 (rendering architecture — **must be amended for the footprint model before task 1**, see pre-flight).
4. `docs/VISUAL_REFERENCES/aurora_veil/AURORA_VEIL_README.md` + the reference set, including the new dramatic refs locked in pre-flight.
5. `PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.metal` — current AV.4 spike state (footprint `F(x)` via `fbm8` + `smoothstep(-0.05,0.22,·)`, `curl_noise` advection, half-bar star blink already wired). **This is the foundation to refine, not replace.**
6. `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/AuroraVeilMotionGifHarness.swift` — the motion feedback loop (`AURORA_GIF=1` → `/tmp/aurora_motion/aurora_dance.gif`). Motion is a GIF/live judgment; stills cannot show the dance.
7. Lawlor reference impl (for the footprint + march, port-not-reinvent, FA #73): paper `https://www.cs.uaf.edu/~olawlor/papers/2010/aurora/lawlor_aurora_2010.pdf`, Unity `https://github.com/olawlor/AuroraRendererUnity`, WebGL demo `http://lawlor.cs.uaf.edu/~olawlor/2019/AuroraRendererWebGL/`.
8. `docs/SHADER_CRAFT.md §17` (sidecar) + `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` (update at closeout).

---

## Pre-flight invariants (each failing check stops the session)

1. On a fresh branch off `main` (or the current AV working branch); `git status` clean except intended AV files.
2. **`AURORA_VEIL_DESIGN.md` §5 has been amended (in the planning seat, committed) to specify the footprint architecture** — the musical-role sentence, the temporal contract for the dance, and the three-part concept bar cleared. Design docs are never authored by Claude Code mid-session (authoring invariant). If this amendment is absent, STOP.
3. **Visual references locked (D-064):** the three dramatic aurora refs Matt provided 2026-07-14 (green sweeping curtains; Lofoten vertical rays; pink/green vertical rays w/ silhouette) are curated into `docs/VISUAL_REFERENCES/aurora_veil/` with `NN_<scale>_<descriptor>.jpg` names + annotations, and the README's anti-neon/green-only contract is updated for Matt's **dramatic multi-colour** choice (re-anchor "not festival" on structure — biological ray striation, translucency, negative space — not desaturation). If refs are not locked, STOP.
4. `curl_noise(float3,e)` (`Utilities/Noise/Curl.metal:21`) and `fbm8(float3,H)` (`Utilities/Noise/FBM.metal:44`) present.
5. Baseline green: `swift test --package-path PhospheneEngine --filter presetLoaderBuiltInPresetsHaveValidPipelines` passes.

---

## Numbered tasks (each has a done-when)

1. **Footprint curtain shaping.** Refine `F(x)` so curtains read as *draped sheets*, not uniform vertical bars: taper each curtain's brightness along its length, vary widths, let the footprint meander (fold) rather than run straight. Keep it the nimitz `H(z)×texture` × footprint-mask factorization (do NOT geometric-Gaussian it — that read as anti-ref `09`).
   **Done-when:** `AURORA_GIF=1` GIF shows ≥3 distinct curtains with dark negative space between, each with visible taper/fold, reading as aurora (ray texture intact).
2. **Curl motion refinement.** Tune `curl_noise` advection so curtains curl/drift/fold at aurora pace (multi-timescale: slow substrate drift + curtain fold over seconds + ray flicker). Amplitude audio-scaled (mid activity), gentle non-zero base at silence.
   **Done-when:** GIF frames 3 s apart show the curtains have visibly morphed/travelled (not just brightness changed); silence GIF still moves gently; D-037 silence non-black holds.
3. **Perspective drape (scope-gated — see DECISION).** If greenlit: march the view ray so curtains converge/drape with depth (Sagristà volumetric). Profile first.
   **Done-when:** curtains show depth convergence AND `PresetPerformanceTests` p95 ≤ Tier-1 4.0 ms; if the perf budget fails, revert this task and report (do not ship over-budget).
4. **Dramatic palette.** Green base → violet → magenta/pink crown by altitude (Lawlor `H(z)`, indexed by march-step/world-y — NOT by folding altitude into the noise, research §1.2). Vocals-pitch route shifts the bands.
   **Done-when:** GIF matches the dramatic refs' colour range; L2 stratification (lower-band G>B) holds; `FidelityRubricTests` green.
5. **Re-integrate audio routes + star blink.** Bass→brightness pulse, drums→rare-event curtain kink, vocals-pitch→palette shift, mid→motion amplitude (one primitive per axis, FA #67). Half-bar star blink (`f.bar_phase01`, per-star staggered, `stemMix`-gated) retained.
   **Done-when:** `AuroraVeilContinuousDominanceTest` green; `audio_routes` sidecar manifest declares every route; `RouteCoverageTests` all green (a red route is a real defect — file it, do not tune the floor).
6. **Real-audio motion validation.** Extend the harness (or add a real-audio variant) to drive the preset with a real fixture track through the production MIR path + a fixed BeatGrid; produce a GIF/MP4.
   **Done-when:** a real-audio motion artifact exists and the curtains visibly respond to the track's energy.
7. **HARD STOP — golden regeneration.** The density-model change will break `PresetRegressionTests` dHash goldens (expected — this is a deliberate visual change, not a refactor). Regenerate goldens ONLY after tasks 1–5 are visually signed off. **Stop and report before regenerating; wait for "go."**
8. **Closeout.** Invoke `closeout`; 8-part report.

---

## Do-NOT

- Do NOT restore full-field `F(x,y)` (bright-everywhere noise) — that IS the wash (the whole reason for the reauthor).
- Do NOT build curtains from clean geometric Gaussian beams — that read as the festival-spotlight anti-reference `09_anti_neon_festival_aurora.jpg` (this session's dead end).
- Do NOT fold altitude into the noise sample (`fbm(float3(x,y,z))`) — produces a monotonic top-to-bottom wash, not stratified bands (research §1.2 operational rule). Altitude lives only in the palette.
- Do NOT drive primary motion from raw live beats (Audio Data Hierarchy) or use free `sin(time)` decorative motion (FA #33) — motion is curl-advected substrate + audio-scaled amplitude.
- Do NOT re-add `mv_warp` — it smears this preset to mush (AV.2.2, `AuroraVeilMVWarpAccumulationTest`).
- Do NOT regenerate goldens before task 7's go.
- Do NOT push without Matt's "yes, push."

---

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
AURORA_GIF=1 swift test --package-path PhospheneEngine --filter AuroraVeilMotionGifHarness 2>&1
swift test --package-path PhospheneEngine --filter "AuroraVeilContinuousDominance|RouteCoverage|FidelityRubric|PresetPerformance" 2>&1
```

## Commit templates (small commits; local-only unless Matt says "yes, push")

```
[AV.5] Aurora Veil: footprint F(x) curtain shaping (taper/fold/meander)
[AV.5] Aurora Veil: curl-noise curtain motion (Wittens) + audio motion amp
[AV.5] Aurora Veil: dramatic H(z) palette (green→violet→magenta)
[AV.5] Aurora Veil: re-integrate audio routes + half-bar star blink + audio_routes manifest
[AV.5] Aurora Veil: regenerate PresetRegression goldens (post visual sign-off)
[AV.5] Docs: DESIGN §5 footprint architecture, RENDER_CAPABILITY_REGISTRY, EP entry, D-185
```

## Closeout

Invoke `closeout`; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions: state that the GIF/real-audio harness (not just stills) was the motion evidence; cite per-route firing from `RouteCoverageTests`; cite the 9-question authenticity rubric verdict; state Aurora Veil remains **code-complete pending live M7** (never "certified") until Matt confirms the dance on real music live.

---

## DECISION-NEEDED

**How vigorous should the aurora's dance be, and do we invest in true perspective drape (task 3)?**

- **Calm & ambient (Sigur-Rós register).** Curtains curl and fold slowly, breathing with the song; drama comes from colour and light, not speed. Skip perspective drape — 2D footprint curtains only. *Cheapest, safest, matches the original ambient intent.*
- **Active & sweeping (Recommended).** Curtains visibly sweep and fold with the music's energy, more like the dramatic refs; keep it 2D (no perspective march) unless a cheap drape proves out. *Best match to "dancing diaphanous ribbons" without a perf gamble.*
- **Full volumetric drape.** Add the Sagristà view-ray march so curtains converge/drape in 3D perspective — most realistic, but a real perf risk (may blow the 4.0 ms Tier-1 budget) and the largest scope.

**Recommendation:** Active & sweeping, 2D. It delivers the desired dancing expression at known cost; perspective drape can be a later polish increment if the 2D version reads flat.

**Default if no reply:** Active & sweeping, 2D (task 3 skipped).
