# Increment AV.6 — Aurora Veil streak-core rebuild (preset)

**Type:** preset (core rendering rebuild)

**Objective.** After this session, Aurora Veil renders as a **mass of fine, translucent vertical streaks** — many thin rays hanging like a curtain, brightest at the lower edge (near white-green) and fading up through blue to a magenta crown, with stars punching through between the streaks and per-streak brightness variation — that **reads and moves like Matt's real-time reference footage**. This replaces the AV.5 rendering core, whose "volumetric march" was a bug'd port of nimitz that produces a smooth **wash** with no real filaments (root cause below), and the AV.5 soft-veil rework, which read as **blobby fog** ("amorphous blobs with volume and shadow" — Matt, 2026-07-14). The green→magenta palette, audio routes + manifest, half-bar star blink, perspective drape, and the real-audio GIF harness from AV.5 are **preserved**; only the aurora-generation core is rebuilt.

Why this exists: across AV.5 the aurora never contained real fine filaments. The march (`aurora_tri_noise_2d` sampled at `(screen-x FIXED per column, altitude)`) traces a *vertical slice* through low-frequency noise → a smooth gradient. Every "streak" Matt saw was the **footprint band mask**, not the march; when AV.5 replaced hard bands with soft fbm, the result was fog. Matt's correction: aurora **IS** streaky (he liked the streaky earlier iterations) — the failure was that the streaks were never *real fine translucent filaments*.

## Skill invocations

- `preset-session` — before opening `AuroraVeil.metal` or its sidecar.
- `shader-authoring` — before any GPU/MSL edit.
- `closeout` — at the end.

## Read-first (in order)

1. `memory: project_aurora_veil_reauthor` — the target (fine translucent vertical streaks), the wash-bug root cause, the direct-streak-field plan, and the footage-extraction workflow. **Load-bearing; read fully.**
2. **Reference footage** — `~/Desktop/Screen Recording 2026-07-14 at 1.41.13 PM.mov` (286 s @ 60 fps). The filename has a special character that breaks direct access — `cp` it to an ASCII path first (`find ~/Desktop -name '*1.41.13*' -print0 | while IFS= read -r -d '' f; do cp "$f" /tmp/av_ref.mov; done`), then `ffmpeg -i /tmp/av_ref.mov -vf fps=1,scale=640:-1 /tmp/aurora_ref/ref_%03d.png`. Study `ref_240`–`ref_260` (the streaky curtain — THE texture target), `ref_120` (calm arc), `ref_030` (overhead corona), and consecutive frames for real-time motion.
3. `docs/presets/AURORA_VEIL_DESIGN.md §5.11` (streak-field architecture — **must be amended before task 1**, see pre-flight) + §2.3 research authenticity rubric.
4. `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md §1.1` (nimitz recipe — note the **traversal** detail my AV.5 port got wrong: nimitz marches a view ray at an *angle* through a 3D volume, `triNoise2d(bpos.zx)`, so the ray crosses many filaments), §1.3 (Wittens curl motion), §1.4 (Theunissen abs-of-difference cheap streaks), §2.1–2.2 (signature + 15 failure modes).
5. `PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.metal` — current state. Identify what to KEEP (aurora_palette, star blink, drape `uvxP`, audio route plumbing, AuroraVeilState) vs REPLACE (raymarch_column + aurora_footprint → the new streak core).
6. `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/AuroraVeilMotionGifHarness.swift` — `AURORA_GIF=1` (synthetic) and `AURORA_REAL_GIF=1` (real love_rehab MIR) → GIFs in `/tmp/aurora_motion/`. **The real-audio GIF, compared frame-against-frame with `/tmp/aurora_ref/`, is the primary feedback loop.**

## Pre-flight invariants (each failing check stops the session)

1. On a fresh branch off the current AV working branch (`claude/quirky-feynman-b4b34e`) or `main` after AV.5 is integrated. `git status` clean except intended AV files.
2. **`AURORA_VEIL_DESIGN.md §5.11` authored + committed in the planning seat** specifying the **streak-field architecture** (fine vertical streaks, curtain envelope, concentration, translucent additive), the **musical-role sentence**, the **temporal contract for the streak motion** (shimmer / sideways travel / drift), and a cleared **three-part concept bar**. Design docs are never authored by Claude Code mid-session. If absent, STOP.
3. **Reference footage curated/locked (D-064):** the `.mov` provenance + a curated still set (the streaky-curtain, arc, and corona representative frames) recorded under `docs/VISUAL_REFERENCES/aurora_veil/` with annotations, and the README updated to note real-time footage is now the motion reference. If not locked, STOP.
4. Baseline green: `swift test --package-path PhospheneEngine --filter presetLoaderBuiltInPresetsHaveValidPipelines` passes.
5. Decide + record the **base state**: revert the AV.5 veil-fog commit (`d572762`, the rejected direction) so the core rebuild starts clean, keeping the palette / routes / star blink / drape / harness commits beneath it.

## Numbered tasks (each has a done-when)

1. **Establish the base.** Revert `d572762` (soft-veil fog) — keep everything beneath (palette, routes+manifest, star blink, drape, real-audio harness). Done-when: preset loads, `AURORA_REAL_GIF=1` renders, tree green except the expected PresetRegression goldens.
2. **Fine vertical-streak field.** Replace the wash-bug march with a core that generates a *mass of fine translucent vertical streaks*: high horizontal frequency (many thin streaks), vertically coherent (streaks run top-to-bottom), fine multi-octave detail, curl-warped so they wave/curve — either the correctly-ported angled view-ray march (`ro+rd·t`, sample `.zx`, FA #73) OR a direct 2D streak field (`noise(x·HIGH_freq + curl/warp, y·LOW_freq + time)`), whichever reliably matches `ref_240`. Done-when: `AURORA_GIF` GIF shows a mass of discrete fine streaks with **dark sky + stars visible between them**, flat/emissive (no bright-core-to-dark-edge volume shading), reading as `ref_240` not fog.
3. **Curtain envelope + concentration.** Brightest at the lower edge (near white-green), soft fade up (soft top); a large-scale concentration field so brightness varies across the curtain with real negative space around it (the aurora occupies part of the frame, not full-width). Done-when: framing matches `ref_240`/`ref_260` — a curtain of streaks against dominant dark sky, intense lower edge.
4. **Real-time motion.** Streaks **shimmer/flicker** (sub-second), bright regions **travel sideways along the curtain** (seconds), the whole form **drifts/undulates** (tens of seconds) — multi-timescale, curl-advected + audio-scaled (mid→motion amplitude), NOT raw beats (Audio Data Hierarchy), NOT free `sin(time)` (FA #33). Done-when: the `AURORA_REAL_GIF` motion, watched against the footage, reads as real aurora shimmer+travel (not a uniform scroll); silence still moves gently; D-037 non-black holds.
5. **Palette on the streak field.** Re-confirm green base → violet → magenta crown by altitude (naturalistic, Matt's AV.5 choice) with the intense near-white-green lower edge. Done-when: matches the footage colour range; L2 lower-band G>B holds; `FidelityRubricTests` green.
6. **Preserve AV.5 couplings.** Re-verify bass→brightness, mid→motion, drums→kink, vocals→hue, downbeat→star-blink all survive the rebuild; drape (`uvxP`) still applied. Done-when: `AuroraVeilContinuousDominance`, `RouteCoverage` (0 red), `AuroraVeilPitchHue`, `AuroraVeilSilence` all green; `audio_routes` manifest unchanged or updated to match.
7. **Real-audio validation.** Produce the `AURORA_REAL_GIF` artifact; compare against `/tmp/aurora_ref/` frames. Done-when: a real-audio motion artifact exists and streaks respond to the track's energy, reading in the same conversation as the footage.
8. **HARD STOP — golden regeneration.** The rebuild breaks `PresetRegressionTests` dHash goldens (expected). Regenerate ONLY after tasks 2–6 are visually signed off by Matt (live M7 on real music). Stop and report before regenerating; wait for "go."
9. **Closeout.** Invoke `closeout`; 8-part report; state that the GIF + real-audio + footage-frame comparison (not stills alone) was the evidence; cite RouteCoverage per-route firing and the 9-question authenticity rubric verdict; state Aurora Veil remains code-complete pending live M7 (never "certified") until Matt confirms the streaks + motion on real music live.

## Do-NOT

- Do NOT go soft/cloudy/fbm-fog — that is the rejected AV.5 veil (FM #8 "blurry pillow fog / volume and shadow"). Streaks are FINE, FLAT, EMISSIVE.
- Do NOT keep the wash-bug march (2D vertical-slice sample of low-freq noise) — it produces no real filaments. The streaks must be a genuine high-frequency structure.
- Do NOT lose translucency — stars/sky must show through between and within the streaks (additive, moderate opacity). Solid opaque streaks read as the "cartoon fill" (Matt's first AV.5 critique).
- Do NOT drive primary motion from raw live beats (Audio Data Hierarchy) or free `sin(time)` (FA #33) — motion is curl-advected + audio-scaled, multi-timescale.
- Do NOT re-add `mv_warp` (AV.2.2, `AuroraVeilMVWarpAccumulationTest`).
- Do NOT regenerate goldens before task 8's go; do NOT push without Matt's "yes, push."

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
AURORA_GIF=1 swift test --package-path PhospheneEngine --filter AuroraVeilMotionGifHarness 2>&1
AURORA_REAL_GIF=1 swift test --package-path PhospheneEngine --filter AuroraVeilMotionGifHarness 2>&1
swift test --package-path PhospheneEngine --filter "AuroraVeilSilence|AuroraVeilContinuousDominance|AuroraVeilPitchHue|RouteCoverage|FidelityRubric" 2>&1
```

Note (worktree): the tempo/BeatThis fixtures + SessionLifecycle concurrency tests fail environmentally in worktrees — app build + lint + the AV-filtered gates are the trustworthy signal. Runtime `makeLibrary` is stricter than xcodebuild's cached metallib: if the preset vanishes from the loader after a shader edit but the app "builds", grep for duplicate `constant`/function defs.

## Commit message templates (small commits; local-only unless Matt says "yes, push")

```
[AV.6] Aurora Veil: revert veil-fog core to streaky base (d572762)
[AV.6] Aurora Veil: fine vertical-streak field (translucent, high-freq)
[AV.6] Aurora Veil: curtain envelope + concentration (bright lower edge, negative space)
[AV.6] Aurora Veil: real-time streak motion (shimmer + travel + drift, audio-scaled)
[AV.6] Aurora Veil: regenerate PresetRegression goldens (post visual sign-off)
[AV.6] Docs: DESIGN §5.11 streak architecture, RENDER_CAPABILITY_REGISTRY, EP entry, D-186
```

## Closeout

Invoke `closeout`; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions: the footage-frame comparison was the visual evidence (not stills alone); per-route firing from `RouteCoverageTests`; the 9-question authenticity rubric verdict; Aurora Veil stays code-complete pending live M7 (never "certified") until Matt confirms the streaks + motion live.

## DECISION-NEEDED

Real aurora in the footage takes several forms — a **curtain of vertical streaks** (the section Matt pointed to), a calmer **horizontal arc**, and an overhead **radiating corona**. Which should Aurora Veil target?

- **Curtain of streaks only (Recommended).** Build the one form Matt flagged as the target — a hanging curtain of fine vertical streaks that shimmers and drifts. Cleanest, matches the explicit reference, one coherent look to nail.
- **Curtain + arc.** Also support a calmer horizontal-arc state (e.g. at low energy) that resolves into the streak curtain as energy rises — more range, more scope, two looks to get right.
- **Curtain + arc + corona.** Add the dramatic overhead radiating form at peaks — most variety, largest scope, real risk of the converging-rays reading as the festival-spotlight anti-reference (`09` / FM #14).

Recommendation: **Curtain of streaks only** — nail the explicit target first; arc/corona can be later increments if wanted.

Default if no reply: Curtain of streaks only.
