# AV.6 continuation — Aurora Veil: exposure calibration on the convergence core

**Type:** preset (finish an in-flight core rebuild). **Branch:** `claude/aurora-veil-streak-core-4bad40`. **Start commit:** `275bc132` (WIP convergence core — compiles, `kAuroraDebug`/tone off, **NOT gate-passing**).

## One-line status
The **structure is solved** (rays now converge to the magnetic zenith — the corona/curtain perspective). The **only remaining blocker is exposure/contrast**: turn the correct-but-dim march into distinct bright rays on dark sky. This is a contained tuning problem — do NOT re-architect.

---

## Skills to invoke first
`preset-session`, `shader-authoring` (before touching `AuroraVeil.metal`), `closeout` (at the end).

## Read-first
1. This file, fully.
2. `PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.metal` at HEAD (`275bc132`) — the convergence core.
3. `docs/presets/AURORA_VEIL_DESIGN.md §5.11` (design intent). `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md §1.1–1.4`.
4. Reference frames already extracted to `/tmp/aurora_ref/` — `ref_240.png` (the streaky-curtain target), `ref_030.png` (overhead corona — shows the convergence explicitly). Source `.mov` at `/tmp/av_ref.mov` (re-extract with `ffmpeg -i /tmp/av_ref.mov -vf fps=1,scale=640:-1 /tmp/aurora_ref/ref_%03d.png` if gone).

---

## What is SOLVED (do NOT re-derive or replace)

**Perspective convergence to the magnetic zenith.** All four prior AV.6 cores (flat streaks, nimitz plane-stack march, dancing centers, distorted centers) read as a **flat horizontal band** because they inherited nimitz's horizon-band camera. The fix (desk-research-backed):
- Camera **looks up** (`kLookPitch`), so the world-vertical field axis projects to a vanishing point just above the frame.
- The march steps the footprint UV by **`stepUV = rd.xz / rd.y · dH`** per altitude shell (the **Wittens operator**). Looking up (`rd.y→1`) → `stepUV→0` → tight vertical ray converging to the zenith; toward the horizon → smear. This makes the rays **fan down / converge up** — the corona. Confirmed in the grayscale debug.
- Emission = **footprint `F(uv)` × deposition `D(h)`**; colour by **height** (green base at the descending ends → magenta crown at the converging top). This is the Lawlor & Genetti factorization. Height-based colour also means **no horizontal colour band** (an earlier failure).

Fallback checkpoints if you ever need them (both green-gated, better-*looking* but structurally a flat band): `49207b23` (volumetric march, Matt: "much better look overall"), `5995e9b1` (dancing centers).

---

## The BLOCKER — your job

The density this march produces is **genuinely tiny and low-contrast** — measured on `/tmp/aurora_motion/f0060.png` (synthetic swell peak) via `ffmpeg -i f.png -vf signalstats,metadata=print -f null -`:
- Raw density luminance (aurora at gain 13): **peak ~0.06, avg ~0.03, min ~0.01** — a narrow band sitting on a **non-zero floor** (that floor is the "murk").

**Goal:** distinct bright rays (→ ~0.9) on **true-black** negative space — not a uniform dim wash, not blown white.

### What was tried (don't repeat blindly)
- **Straight gain** → blown-white uniform or dim wash. Low contrast means gain alone can't separate rays from murk.
- **Floor-subtract tone map** `aurora *= max(lum-floor,0)*scale / lum` is the right tool, BUT I repeatedly **mis-set the floor above the actual per-frame peak → all black**. There is a `kToneFloor`/`kToneScale` scaffold already in the fragment (currently no-op). **MEASURE the real per-frame density first, then set floor just below peak.**
- **Concentration** (`kFpLo`/`kFpHi` smoothstep on `fbm4`, in `aurora_footprint`) to carve negative space: I **over-carved** (killed most of the aurora). `fbm4` is ~[-1,1]; the sampled region may not span much — measure coverage before trusting thresholds.
- The **running-average smear** (`kSmear`, `acc = mix(acc, d, 1-kSmear)`) + perspective `stepUV` blur the footprint horizontally → low contrast. Worth trying: sharper `D(h)`, less smear, or **max-accumulation instead of average** so bright filaments survive; or raise the footprint's ridge contrast.

### Likely-productive path
1. Turn on `kAuroraDebug = 1.0` (grayscale density) and calibrate the **density contrast in grayscale first**, decoupled from colour.
2. Read pixel stats numerically every iteration (`signalstats`). Set `kToneFloor` ≈ measured avg, `kToneScale` ≈ `0.9/(peak-floor)`. Verify the grayscale shows bright rays on black.
3. Only then turn debug off and confirm colour (green body, magenta crown, cyan-white cores).
4. Get negative space from the concentration carving *and/or* the tone floor — but confirm coverage numerically (aim: curtain occupies part of the frame, dominant dark sky).

---

## Instrumentation (already in the file — USE IT)
- `kAuroraDebug` constant → `1.0` returns grayscale density from the fragment; `0.0` to ship.
- Feedback loop:
  - `AURORA_GIF=1 swift test --package-path PhospheneEngine --filter AuroraVeilMotionGifHarness` → synthetic, **consistent** energy — use `f0060.png` (swell peak).
  - `AURORA_REAL_GIF=1 …` → real `love_rehab` MIR → `real_*.png`. (Some real frames are genuinely low-energy → dim; use synthetic `f0060` for exposure calibration.)
  - Output dir `/tmp/aurora_motion/`.
- **Read the numbers, don't eyeball exposure:** `ffmpeg -i /tmp/aurora_motion/f0060.png -vf signalstats,metadata=print -f null - 2>&1 | grep -iE "YMIN|YAVG|YHIGH|YMAX"`. I wasted many rounds guessing magnitudes wrong.
- Compare against `/tmp/aurora_ref/ref_240.png` via a vstack (`ffmpeg … vstack`).

## Gates (green before any sign-off)
```
swift test --package-path PhospheneEngine --filter "AuroraVeilSilence|AuroraVeilContinuousDominance|AuroraVeilPitchHue|RouteCoverage|FidelityRubric"
swift test --package-path PhospheneEngine --filter presetLoaderBuiltInPresetsHaveValidPipelines
swiftlint lint --strict --config .swiftlint.yml
```
- Silence stratification: upper band (uv.y 0.25) more magenta (R+B) than lower (0.65); lower green-dominant. Height-based colour handles this physically — verify it survives the exposure changes.
- **HARD STOP** before regenerating `PresetRegressionTests` dHash goldens — needs Matt's live-M7 sign-off first.
- Worktree note: tempo/BeatThis fixtures + SessionLifecycle tests fail *environmentally* in worktrees; the AV-filtered gates + app build + lint are the trustworthy signal.

## Audio routes (preserved — keep wired, RouteCoverage must stay green)
vocals→hue tint, bass→brightness pulse, mid→motion amp, drums→kink (`av.kinkAccumulator`), downbeat→half-bar star blink. `audio_routes` manifest unchanged.

## Matt's target (the essence)
Many bright **centers stretched upward** into rays, **moving, pulsing, and DISTORTED** (the distortion *is* the dance), different colours, dancing to the music while the **stars keep time**. Green-dominant, bright cyan-white cores, faint magenta crown, **dominant dark negative space** (curtain occupies part of the frame). The convergence core has the structure; the centers'/distortion behaviour can be layered back on once exposure reads.

## Discipline (I violated these last session — don't)
- **Instrument before theorizing** about exposure; read pixel numbers.
- **One change at a time, re-measure.** I changed two things between measure and apply and mis-set the floor → chased ghosts.
- **Do not swing architecture** on each review comment. The convergence core is correct; tune it.
- **Stop and report after 2 failed rounds** on the same root cause.

## Commit trail (all local, nothing pushed)
`275bc132` WIP convergence (HEAD) · `5995e9b1` distorted centers · `72c79255` dancing centers · `49207b23` volumetric march · `ee2db5ba` revert-to-streaky base. Pushing requires Matt's explicit "yes, push."
