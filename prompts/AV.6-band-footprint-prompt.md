# Increment AV.6 (band-footprint rebuild) — Aurora Veil: rebuild F(x,z) as a localized auroral band

**Type:** preset. **Branch:** `claude/aurora-veil-streak-core-4bad40` (pushed; **start at `0effa12d`** — the band is already built and wired; see PROGRESS below).

**Objective.** After this session the footprint `F(x,z)` reads as a **coherent auroral band** (an arc/curve across the ground plane) with **striations across its width**, not the isotropic mottle it is today — verified by the F-map spike *before* it is wired through the march. Downstream: an **overhead curtain** (Matt, Q1) hanging from just above the frame — green base above a dark horizon, rays ascending to a violet crown, `ref_240` — occupying **part** of the frame against dominant dark sky, colour separating by elevation, pebbly ray texture gone. Gates stay green; the exposure/tone-map is re-derived from measurement, not carried over.

**Decisions locked (Matt, 2026-07-17):** Q1 = **overhead curtain** (return camera toward the locked ~1.02 pitch; the band, being at distance, separates colour by elevation without needing the wide horizon window). Q2 = **author the palette from `ref_240`** (base/mid/crown RGB), replacing nimitz's pale-cyan cosine midtone.

---

## PROGRESS — the band is built; the open problem is now the RAY GENERATOR (2026-07-17, start at `0effa12d`)

Tasks 1–3 below are largely **done** on the branch. What was built and what remains:

- ✅ **Band footprint** (`83252b66`). `F(x,z)` is now a localized meandering band (soft-edged strip, true dark negative space above/below) — NOT the isotropic mottle. Verified on the F-map spike. Two load-bearing fixes: (1) band membership runs on **gently-drifted** coords — the full curl advection (±0.5) was larger than the band half-width (0.2) and scattered the strip into all-over mottle; (2) striations **modulate** a lit band body (`kBandFloor`), they do not supply its brightness (the nimitz noise averages ~0.03 → band×noise was dim filigree).
- ✅ **Amplitude fixed + exposure sane** (`0effa12d`). Band dlum peak **0.54 / avg 0.12 at gain 1.0** (old core: 0.014 / 0.001 at gain 9). Gain drops 9 → ~1.7; **the floor-subtract tone map is no longer load-bearing** — the band carries its own negative space. All the earlier exposure gymnastics were compensating for the 5 %-amplitude footprint; that's gone.
- ✅ **Colour separation reads.** Wired through the march, the H(z) gradient gives green base → violet crown with dark corners.
- ❌ **THE OPEN PROBLEM — rays.** Through the march the curtain is **fog, not filaments**. No amount of footprint noise fixed it (nimitz tri-noise flat or marched, AV.5 included).

**Root cause (the insight of the whole AV.6 arc — reasoned, confirm with a render first):** the march sweeps the footprint **RADIALLY** — `uv = rd.xz · t`, so as a ray climbs, its sample point walks outward along `rd.xz`. Any footprint detail that is **high-frequency in that radial direction de-coheres** as the ray marches across it, and the running-average smear averages it to fog. That is why *every* noise-as-footprint approach fogged. Filaments only survive if they are **low-frequency RADIALLY** (coherent along the ray) and **high-frequency TANGENTIALLY** (distinct across the curtain).

**THE next task — build the ray generator in a convergence-aligned frame.** Decompose the footprint sample into **radial / tangential** coordinates about the zenith/vanishing point (the convergence the camera looks toward). Put the filament ridges in the **tangential** coordinate (many thin lines across the curtain) and keep them **coherent/low-freq radially** (so they extrude into rays, not dots). Sharp-edged (aurora, not fog); irregular/meandered so they're organic, not spotlight beams (FM #14). Spike it first: confirm the marched output shows distinct rays over the band before tuning colour/exposure. Only then re-derive palette-from-footage (Q2), overhead framing (Q1), final exposure, and gates.

Everything below (§1–§10) is the original plan; tasks 1–3 are now the PROGRESS above. Task 2's "does F read as a band" go/no-go is **passed**; the new go/no-go is "do the marched rays read as filaments, not fog."

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
3. `docs/presets/AURORA_VEIL_DESIGN.md` §5.11 (streak-field architecture + the AV.6 exposure/palette/instrumentation notes). No §5.12 to wait on — the reference video is the spec (correction 2026-07-17; see §3/§5).
4. `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` §1.1–1.2 (nimitz recipe + Lawlor `H(z)×F(x,y)`) and **§1.3** (band/oval flux structure).
5. Reference: `/tmp/aurora_ref/ref_240.png` (overhead curtain target), `/tmp/av_seq/` (4 fps sequence, t≈238 s — the *ascending* motion), corona `/tmp/aurora_ref/ref_030.png`. Re-extract if gone: `ffmpeg -i /tmp/av_ref.mov -vf fps=1,scale=640:-1 /tmp/aurora_ref/ref_%03d.png` and `ffmpeg -ss 238 -i /tmp/av_ref.mov -vf fps=4,scale=480:-1 -frames:v 8 /tmp/av_seq/s_%02d.png`.

## 3. Pre-flight invariants (a failed check stops the session)

- On branch `claude/aurora-veil-streak-core-4bad40`, clean tree, HEAD at or descended from `2b6c1286`, upstream pushed.
- `swift test --package-path PhospheneEngine --filter "AuroraVeilSilence|AuroraVeilContinuousDominance|AuroraVeilPitchHue|RouteCoverage|FidelityRubric"` → green (37/37 in the last session's run set).
- `swiftlint lint --strict --config .swiftlint.yml` → 0 violations.
- The F-map spike renders: set `kAuroraDebug = 2.0`, `AURORA_GIF=1 swift test … --filter AuroraVeilMotionGifHarness`, and confirm `/tmp/aurora_motion/f0060.png` shows the red/green footprint map (reproduce the "islands, no band" baseline before changing anything).
- The **reference video is the spec** (`/tmp/aurora_ref/ref_240.png`, `/tmp/av_seq/`). The band is shader engineering, authored by Claude against the video — there is **no separate design doc to wait on** (correction, Matt 2026-07-17: the earlier "§5.12 must be Matt-authored" gate was wrong; that rule is for creative direction, which the video + Q1/Q2 already give).

## 4. Numbered tasks (each has a done-when)

1. **Baseline the spike.** Render F alone (`kAuroraDebug = 2`) at HEAD. **Done-when:** you have reproduced the islands-of-mottle map and can state F's current peak amplitude numerically.

2. **Rebuild F as a band — SPIKE FIRST, wire second (go/no-go gate).** Author a new `aurora_footprint` whose concentration is a **localized band**: a meandering curve in the xz plane (curl-advected for drift/dance) × an **across-band profile** (bright core, soft edges), × **striations across the band's width** (fine ridged detail that will extrude into ray cross-sections) — per §5.12. Keep raw amplitude near its ceiling (fix finding 3). **Render F alone via the spike and confirm it reads as an arc with across-width striations against dark negative space — do NOT wire it through the march until the F-map looks right.** **Done-when:** the `kAuroraDebug = 2` map shows a discrete band with striations (attach the frame); F peak ≈ its ceiling, not ~5%.

3. **Wire F through the march + recalibrate exposure.** Turn debug to `1` (grayscale density), then `0`. Re-measure `dlum` on `f0060` (**invert sRGB** — see §5.11 gotcha; the harness writes sRGB PNGs), set `kToneFloor ≈ measured avg`, `kToneScale ≈ 0.9/(peak−floor)`. **Done-when:** color render shows a single coherent curtain of ascending rays over dominant dark sky; grayscale shows bright rays on true black (YMIN≈16 limited-range); no pebbly texture; **no channel clips — `PresetAcceptanceTests` "does not clip to white" asserts max channel < 250** (the earlier core failed at 252).

4. **Author the palette from the footage** (Matt approved, Q2). Sample RGB from `ref_240` at base / mid / crown, fit `H(z)`; replace nimitz's cosine (its midtone `(0.47,0.76,0.89)` is a desaturated cyan-white — *his* look, not the footage's). **Done-when:** crown reads violet, base saturated green, matched against `ref_240` in a vstack.

5. **Camera framing — overhead curtain** (Matt approved, Q1). Return `kLookPitch` toward the locked ~1.02 (zenith just above the frame) and confirm the band, now at distance, still separates colour by elevation *without* the wide horizon window. **Done-when:** framing matches `ref_240` (overhead curtain, dark horizon low); stratification gate green.

6. **Gates.** Full green set + lint + app build (see §7). **Done-when:** all pass; silence form (bandPeak, darkFraction) and continuous-dominance ratio still within their thresholds; `PresetAcceptanceTests` (incl. "does not clip to white", max channel < 250) green.

7. **HARD STOP — goldens.** `PresetRegressionTests` dHash goldens will differ. **Do not regenerate.** Produce the M7 review frames + motion GIF and **stop and report** for Matt's live-M7 sign-off before any golden regen.

## 5. Do-NOT

- Do **not** keep isotropic `triNoise2d` as the *footprint map* (that is the defect; §1.1 finding). It may still be used as the **across-band striation** texture, but band structure comes first.
- Do **not** chase exposure before the F-map reads as a band — the exposure pain was a symptom of F at 5% amplitude, not a tuning problem.
- Do **not** regenerate `PresetRegressionTests` goldens without Matt's M7 sign-off (task 7).
- Do **not** wait on a Matt-authored design spec — the video is the spec; the band/ray structure is engineering (corrected 2026-07-17). Surface only genuine *product* choices (a new look/register decision), not shader-architecture choices.
- Do **not** re-open the solved pieces without cause: exposure recipe, continuous-dominance rebalance (kink bounded per D-157, bass swing), the ported IQ-cosine indexed by step/altitude, and the sRGB instrumentation. Reuse them.
- Keep `audio_routes` wired; `RouteCoverage` must stay green (vocals→hue, bass→brightness, mid→motion, drums→kink, downbeat→star blink).
- Worktree note: tempo/BeatThis + SessionLifecycle tests fail *environmentally* in worktrees — the AV-filtered gates + app build + lint are the trustworthy signal, not the full suite.

## 6. Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -project PhospheneApp.xcodeproj -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail -3
swift test --package-path PhospheneEngine --filter "AuroraVeilSilence|AuroraVeilContinuousDominance|AuroraVeilPitchHue|RouteCoverage|FidelityRubric|PresetAcceptance|presetLoaderBuiltInPresetsHaveValidPipelines" 2>&1
```

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
