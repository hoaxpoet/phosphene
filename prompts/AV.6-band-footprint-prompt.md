# Increment AV.6 (band-footprint rebuild) — Aurora Veil: rebuild F(x,z) as a localized auroral band

**Type:** preset. **Branch:** `claude/aurora-veil-streak-core-4bad40` (pushed; start at `2b6c1286`).

**Objective.** After this session the footprint `F(x,z)` reads as a **coherent auroral band** (an arc/curve across the ground plane) with **striations across its width**, not the isotropic mottle it is today — verified by the F-map spike *before* it is wired through the march. Downstream: an **overhead curtain** (Matt, Q1) hanging from just above the frame — green base above a dark horizon, rays ascending to a violet crown, `ref_240` — occupying **part** of the frame against dominant dark sky, colour separating by elevation, pebbly ray texture gone. Gates stay green; the exposure/tone-map is re-derived from measurement, not carried over.

**Decisions locked (Matt, 2026-07-17):** Q1 = **overhead curtain** (return camera toward the locked ~1.02 pitch; the band, being at distance, separates colour by elevation without needing the wide horizon window). Q2 = **author the palette from `ref_240`** (base/mid/crown RGB), replacing nimitz's pale-cyan cosine midtone.

---

## Why this increment exists (the spike result — do NOT re-derive)

The F-map spike (`kAuroraDebug == 2`, committed at `2b6c1286`) rendered the footprint alone as a flat 2-D map. Findings, measured:

1. **F is NOT dense everywhere** (an earlier hypothesis, falsified by the render). It has ample negative space. The real defect is **no coherent band structure**: the concentration field is a patchy isotropic blotch field — aurora scattered as **islands**, not an arc.
2. **F has no directional striation** — isotropic granular mottle. In a footprint-extrusion march, F's fine detail *becomes the rays' cross-section*, so isotropic mottle extrudes into the crumbly/pebbly rays fought all last session.
3. **F's amplitude is tiny**: raw triNoise ≈ **0.03** against its **0.55** clamp ceiling. This is the root of the whole prior session's exposure gymnastics (gain 9 + tone scale 68 just to lift it). Fix F's amplitude and the exposure math gets sane.

**FA #73, one level deep:** nimitz's `triNoise2d` is designed to be sampled **along a view ray crossing it**, where the running-average smear turns it into streaks. We use it as a **static 2-D footprint map** — so it never becomes streaks, it stays mottle. AV.5 ported the shape not the traversal; AV.6 ported the traversal but not the footprint. This increment ports the footprint.

---

## 1. Skills to invoke

- `preset-session` — **before** opening the `.metal` file or any sidecar.
- `shader-authoring` — **before** editing GPU code.
- `closeout` — at the end.

## 2. Read-first (in order)

1. This prompt, fully.
2. `PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.metal` at HEAD — the footprint (`aurora_footprint`), the distance march (`aurora_march`), and the F-map spike branch (`kAuroraDebug == 2`).
3. `docs/presets/AURORA_VEIL_DESIGN.md` §5.11 (streak-field architecture + the AV.6 exposure/palette/instrumentation notes) and **§5.12 if Matt has authored the band spec** (see DECISION-NEEDED — this must exist before task 2).
4. `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` §1.1–1.2 (nimitz recipe + Lawlor `H(z)×F(x,y)`) and **§1.3** (band/oval flux structure).
5. Reference: `/tmp/aurora_ref/ref_240.png` (overhead curtain target), `/tmp/av_seq/` (4 fps sequence, t≈238 s — the *ascending* motion), corona `/tmp/aurora_ref/ref_030.png`. Re-extract if gone: `ffmpeg -i /tmp/av_ref.mov -vf fps=1,scale=640:-1 /tmp/aurora_ref/ref_%03d.png` and `ffmpeg -ss 238 -i /tmp/av_ref.mov -vf fps=4,scale=480:-1 -frames:v 8 /tmp/av_seq/s_%02d.png`.

## 3. Pre-flight invariants (a failed check stops the session)

- On branch `claude/aurora-veil-streak-core-4bad40`, clean tree, HEAD at or descended from `2b6c1286`, upstream pushed.
- `swift test --package-path PhospheneEngine --filter "AuroraVeilSilence|AuroraVeilContinuousDominance|AuroraVeilPitchHue|RouteCoverage|FidelityRubric"` → green (37/37 in the last session's run set).
- `swiftlint lint --strict --config .swiftlint.yml` → 0 violations.
- The F-map spike renders: set `kAuroraDebug = 2.0`, `AURORA_GIF=1 swift test … --filter AuroraVeilMotionGifHarness`, and confirm `/tmp/aurora_motion/f0060.png` shows the red/green footprint map (reproduce the "islands, no band" baseline before changing anything).
- **§5.12 band spec exists in the design doc** (Matt-authored — the one remaining prerequisite; framing/palette are already decided, see §10). If absent → stop; do not author design strategy mid-session.

## 4. Numbered tasks (each has a done-when)

1. **Baseline the spike.** Render F alone (`kAuroraDebug = 2`) at HEAD. **Done-when:** you have reproduced the islands-of-mottle map and can state F's current peak amplitude numerically.

2. **Rebuild F as a band — SPIKE FIRST, wire second (go/no-go gate).** Author a new `aurora_footprint` whose concentration is a **localized band**: a meandering curve in the xz plane (curl-advected for drift/dance) × an **across-band profile** (bright core, soft edges), × **striations across the band's width** (fine ridged detail that will extrude into ray cross-sections) — per §5.12. Keep raw amplitude near its ceiling (fix finding 3). **Render F alone via the spike and confirm it reads as an arc with across-width striations against dark negative space — do NOT wire it through the march until the F-map looks right.** **Done-when:** the `kAuroraDebug = 2` map shows a discrete band with striations (attach the frame); F peak ≈ its ceiling, not ~5%.

3. **Wire F through the march + recalibrate exposure.** Turn debug to `1` (grayscale density), then `0`. Re-measure `dlum` on `f0060` (**invert sRGB** — see §5.11 gotcha; the harness writes sRGB PNGs), set `kToneFloor ≈ measured avg`, `kToneScale ≈ 0.9/(peak−floor)`. **Cap the exposure so no channel clips to white** — `PresetAcceptanceTests` "does not clip to white" asserts **max channel < 250**; the AV.6 core failed it at 252 (the crown/bright-ray wash). Keep the scale (and any core-bleach) below that ceiling. **Done-when:** color render shows a single coherent curtain of ascending rays over dominant dark sky; grayscale shows bright rays on true black (YMIN≈16 limited-range); no pebbly texture; `PresetAcceptanceTests` max-channel < 250 (was 252).

4. **Author the palette from the footage** (Matt approved, Q2). Sample RGB from `ref_240` at base / mid / crown, fit `H(z)`; replace nimitz's cosine (its midtone `(0.47,0.76,0.89)` is a desaturated cyan-white — *his* look, not the footage's). **Done-when:** crown reads violet, base saturated green, matched against `ref_240` in a vstack.

5. **Camera framing — overhead curtain** (Matt approved, Q1). Return `kLookPitch` toward the locked ~1.02 (zenith just above the frame) and confirm the band, now at distance, still separates colour by elevation *without* the wide horizon window. **Done-when:** framing matches `ref_240` (overhead curtain, dark horizon low); stratification gate green.

6. **Gates.** Full green set + lint + app build (see §7). **Done-when:** all pass; silence form (bandPeak, darkFraction) and continuous-dominance ratio still within their thresholds; `PresetAcceptanceTests` (incl. "does not clip to white", max channel < 250) green.

7. **HARD STOP — goldens.** `PresetRegressionTests` dHash goldens will differ. **Do not regenerate.** Produce the M7 review frames + motion GIF and **stop and report** for Matt's live-M7 sign-off before any golden regen.

## 5. Do-NOT

- Do **not** keep isotropic `triNoise2d` as the *footprint map* (that is the defect; §1.1 finding). It may still be used as the **across-band striation** texture, but band structure comes first.
- Do **not** chase exposure before the F-map reads as a band — the exposure pain was a symptom of F at 5% amplitude, not a tuning problem.
- Do **not** regenerate `PresetRegressionTests` goldens without Matt's M7 sign-off (task 7).
- Do **not** author the §5.12 design/band spec mid-session — that is Matt's seat (skill invariant). If missing, stop.
- Do **not** re-open the solved pieces without cause: exposure recipe, continuous-dominance rebalance (kink bounded per D-157, bass swing), the ported IQ-cosine indexed by step/altitude, and the sRGB instrumentation. Reuse them.
- Keep `audio_routes` wired; `RouteCoverage` must stay green (vocals→hue, bass→brightness, mid→motion, drums→kink, downbeat→star blink).
- Worktree note: tempo/BeatThis + SessionLifecycle tests fail *environmentally* in worktrees — the AV-filtered gates + app build + lint are the trustworthy signal, not the full suite.

## 6. Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -project PhospheneApp.xcodeproj -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail -3
swift test --package-path PhospheneEngine --filter "AuroraVeilSilence|AuroraVeilContinuousDominance|AuroraVeilPitchHue|RouteCoverage|FidelityRubric|PresetAcceptance|presetLoaderBuiltInPresetsHaveValidPipelines" 2>&1
```

Note: `PresetAcceptanceTests` ("does not clip to white", max channel < 250) is **added to the gate filter** — the AV.6 core failed it at 252 and the prior AV gate set missed it. `PresetRegressionTests` dHash stays out (goldens are the M7-gated hard stop, task 7).

Visual feedback loop:
```
AURORA_GIF=1 swift test --package-path PhospheneEngine --filter AuroraVeilMotionGifHarness   # → /tmp/aurora_motion/, use f0060.png (swell peak)
ffmpeg -i /tmp/aurora_motion/f0060.png -vf signalstats,metadata=print -f null - 2>&1 | grep -iE "YMIN|YAVG|YMAX"
# dlum (linear) = (((Y-16)/219)+0.055)/1.055)^2.4  — PNGs are sRGB; do NOT read Y as linear
```

## 7. Commit templates

`[AV.6] Aurora Veil: <band F | exposure recalibrate | footage palette | camera framing> — <desc>`

Small commits per logical step. Branch is pushed; push follow-ups only on Matt's explicit "yes, push".

## 8. Closeout

Invoke `closeout`; produce the 8-part report. In a worktree the full `Scripts/closeout_evidence.sh` emits environmental failures (tempo/BeatThis/SessionLifecycle) — state that and paste the trustworthy signal instead: the AV-filtered gate run + `xcodebuild … build` + `swiftlint --strict`, with the commit hash. Include the F-map spike frame and the `ref_240` vstack as visual evidence. Update `AURORA_VEIL_DESIGN.md` §5.11/§5.12 with the final constants and any new finding.

---

## 10. DECISION-NEEDED — RESOLVED (Matt, 2026-07-17)

**Q1 — framing/colour → A, overhead curtain.** A nearby curtain hanging from just above the frame, green base above a dark horizon, rays ascending to a violet crown (`ref_240`). Returns to the locked "zenith just above the frame" framing. The band decouples colour-separation from the camera window, so this no longer costs the colour read.

**Q2 — palette source → yes, author from the footage.** Fit `H(z)` from `ref_240` RGB (base/mid/crown), replacing nimitz's pale-cyan cosine midtone. The video is the fidelity target.

**Still open — Matt's seat, before the session runs:** author **§5.12** (the band-footprint spec) in `AURORA_VEIL_DESIGN.md` and commit it. Per the authoring invariant, Claude Code does not write the design strategy mid-session; task 2 hard-stops if §5.12 is absent. The band's musical-role sentence + temporal contract carry over from §5.11 (curl-advected drift = the dance; ascending rays; bass flare; rare drum-kink fold; half-bar star blink) — §5.12 needs the *structure* spec: band curve, across-width profile, striation source, amplitude target (near the 0.55 ceiling, not ~0.03).
