# Ferrofluid Ocean — Camera Angle + Reflection Adjustments

Continuation of V.9 Session 4.5c Phase 1 visual completion (rounds 16-32, 2026-05-15). Picks up after round 32 lands and Matt confirms the round-32 visual via capture review.

## Where we are

Round 32 (commit `f3fe9ed1`) is the latest visual change. Visual review pending.

End-of-session calibration:

- **Mesh G-buffer path** (since round 12, Phase 1 step B): tessellated 256×256 quad mesh + vertex displacement from a pre-baked height texture. NOT the SDF path. See [FerrofluidMesh.metal](../../PhospheneEngine/Sources/Renderer/Shaders/FerrofluidMesh.metal) and [FerrofluidMesh.swift](../../PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidMesh.swift).
- **Density**: 3025 particles in a 55 × 55 isotropic grid over the 20 × 20 wu world patch. Spike base radius 0.17 wu, bases nearly touch. Cone profile is `(max(0, 1 - r/R))²` (squared) — sharp pointed tips, smooth flare to substrate. See [FerrofluidParticles.swift](../../PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidParticles.swift) and the `ferrofluid_height_bake` kernel in [FerrofluidParticles.metal](../../PhospheneEngine/Sources/Renderer/Shaders/FerrofluidParticles.metal).
- **Spike strength**: constant `kFerrofluidSpikeStrength = 2.0` in [FerrofluidMesh.metal](../../PhospheneEngine/Sources/Renderer/Shaders/FerrofluidMesh.metal). NO per-frame audio coupling (round 20 design pivot — waves carry music response, not spikes).
- **Wave motion**: Gerstner waves bar-locked to musical tempo. 4 superposed waves, amplitudes summing 0.60 wu, one full cycle per `kGerstnerBarsPerCycle = 6.0` bars. `tempoScale = bpm / 60` passed via `MeshUniforms` from `mirPipeline.liveDriftTracker.currentBPM`. Time source is `features.time` (pure wall-clock — NOT `accumulated_audio_time`, which is energy-weighted and produced the 20-30s AGC-settling jerk fixed in round 24). `amplitudeMul = presenceGate × 0.85` constant (round 23 dropped arousal coupling). At Love Rehab (4/4 @ 118 BPM): 12.2 s/cycle. At Money (currently meter=2/X per ML detection): 5.85 s/cycle.
- **Material composition** in `fluid_shading` ([RayMarch.metal](../../PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal) line ~592):
  - Layer 1 (specular): `kFluidSpecularWeight = 0.0` — disabled per Matt's "no white tips, aurora is the only color source"
  - Layer 2 (ambient): `rm_ferrofluidSky(Rview, features, stems, scene) × kFluidAmbientWeight (0.3)` — the substrate mirror-reflects the aurora-carrying procedural sky
  - Layer 3 (fresnel): `kFluidFresnelWeight = 0.0` — disabled per Matt's "gray at peak tops doesn't belong" (round 32)
  - Layer 4 (iridescence): unchanged at 0.005 — essentially invisible
- **Aurora curtain** (`rm_ferrofluidSky`):
  - Elevation: 0.0 (horizon) — lights spike sides (Rview roughly horizontal), substrate-between (Rview ≈ +0.31) misses the curtain
  - Vertical thickness: 0.35
  - Azimuth wedge: floor 0.30, peak 0.75 (~70° localized region orbits with `accumulated_audio_time × arousal-mapped speed`)
  - Intensity: `1.0 baseline + 1.5 × drums_energy_dev_smoothed` (peak signal 3.25; × ambient 0.3 = 0.975 → saturated neon at peaks)
  - Hue: 3-stop aurora-realistic palette pink (1.00, 0.20, 0.55) → green (0.10, 1.00, 0.30) → purple (0.45, 0.10, 1.00), `t = kCurtainBasePhase (0.50) + palettePhase (±0.20 from vocals_pitch_hz with valence fallback) + 0.10 × sin(curtainAzimuth × 0.5)` — range 0.20-0.80 reaches all three primaries
  - Live-stems silence gate via `totalStemEnergy smoothstep(0.02, 0.10, ...)`

## What's TODO

Two coupled changes for the next session.

### 1. Camera-angle change (no-sky framing)

Matt's `2026-05-15T18-12-04Z`: "if the sky is going to be visible in the scene, shouldn't it be night sky with aurora curtain(s) visible? Otherwise, my desire is to change the camera angle so none of the sky is visible." With the aurora-as-reflection mechanic (rounds 27-32), the sky function `rm_ferrofluidSky` is generating audio-reactive aurora content but it's only visible through the mirror reflection. Direct sky-above-horizon view shows the pale base sky gradient that doesn't match the substrate's reflected aurora content. References `01_macro_*` / `02_meso_*` / `04_specular_*` all frame close-up with no horizon visible — they're the hero substrate references and the right composition target.

**Current camera** (in [FerrofluidOcean.json](../../PhospheneEngine/Sources/Presets/Shaders/FerrofluidOcean.json) `scene_camera`):
- Position: `(0, 2.5, -4.0)`
- Target: `(0, 0.3, 3.0)`
- FOV: 55°
- ~18° down angle, horizon visible in upper half of frame

**Target camera** (proposed — verify against references):
- Tilt down ~35-45° (camera-to-target vector has Y component dominating Z)
- Move camera CLOSER to the patch (current 6-7 wu camera-to-patch distance shows the whole patch; references show close-up framing covering only 4-6 wu of substrate)
- Maintain wide enough FOV (55° is fine; can stay) to show the lattice character

**Concrete starting numbers to try** (subject to visual review):
- Position: `(0, 3.5, -1.5)` — camera moved closer + raised slightly
- Target: `(0, 0.0, 1.0)` — target lower + closer
- FOV: 55° (unchanged)
- Approximate down-angle: ~50°

These are starting points. Likely need 1-2 capture-review iterations to land the right framing.

### 2. Re-tune reflection on spike sides for the new camera

Changing camera angle changes which Rview values the substrate samples. Specifically:
- At steeper down-angle, the camera's view direction (-V) is more vertical (closer to +Y)
- Flat substrate (N=+Y) reflects -V → Rview ≈ (-V).xy with Y flipped. At steeper angle, Rview has higher |R.y| (more vertical reflection)
- Result: flat substrate Rview points MORE toward zenith (R.y → +1), AWAY from horizon
- Spike sides (tilted N) still catch horizontal-ish reflections, but the geometry is different

The current curtain elevation 0.0 (horizon) was tuned for the ~18° camera. With a steeper camera, the relationships shift:
- Substrate-between will catch HIGHER elevations of the sky → closer to zenith. baseSky highSky = (0.05, 0.035, 0.10) × 0.3 = (0.015, 0.011, 0.030) ≈ near-black ✓ (good — still dark)
- Spike sides may catch DIFFERENT elevations depending on their tilt vs the new view angle

After the camera change, capture and check:
- Does the aurora rim still appear on spike sides? Or has the curtain elevation moved out of the spike-side reflection band?
- If aurora is missing, tune `kCurtainElevation` until spike sides catch it (could be slightly above horizon, e.g., 0.1-0.2)
- If aurora bleeds onto substrate-between (which would now be reflecting upward at higher R.y), need to tune curtain to NOT be at the substrate-between's reflected elevation
- The curtain thickness (`kCurtainStripeThickness = 0.35`) and azimuth window may also want adjustment for the new framing

Other tunables that may need post-camera revisit:
- `kCurtainBaselineIntensity` / `kCurtainModulationIntensity` — brighter or dimmer depending on close-up scale
- `kFluidAmbientWeight` (currently 0.3) — at close-up scale, more pixels are aurora-lit so ambient weighting affects perceived brightness
- `kCurtainBasePhase` (currently 0.50) — close-up changes which hues dominate the frame

## How to know it's done

Per Matt's references and previous reviews:

- [ ] No sky visible at top of frame (close-up framing)
- [ ] Substrate-between-spikes is near-black (pitch-black per references)
- [ ] Spike SIDES show saturated aurora rim color (pink / green / purple cycling with music)
- [ ] Spike TIPS / apex are dark — no white sheen, no gray cyan
- [ ] Aurora rim cycles through all three primaries over a song (not stuck in one hue family)
- [ ] Audio coupling visible: drum hits pulse rim brightness; vocals pitch shifts rim hue; curtain orbits the bright rim around the spike field over ~30-60s

## What NOT to do

- Don't reintroduce the white specular layer (`kFluidSpecularWeight = 0` is load-bearing per Matt's "aurora is the only color source")
- Don't reintroduce fresnel weight > 0 (cyan-tinted white at grazing angles reads as "gray at peak tops")
- Don't tint specular by env (round 29 — produced green/yellow tips, the wrong direction)
- Don't use `accumulated_audio_time` for ANY new motion — it's energy-weighted, not a clock (round 24 finding); use `features.time` if you need a monotonic clock
- Don't bump curtain elevation back to high values — round 30 found that lights the WRONG surfaces (substrate-between catches it instead of spike sides)
- Don't bump ambient weight above ~0.5 — round 30 found that bleeds base-sky purple onto substrate-between (lost the pitch-black character)

## Known issues (do not investigate unless explicitly requested)

- **BUG-012** — MPSGraph `EXC_BAD_ACCESS` at `StemFFTEngine.runForwardGraph()` under sustained force-dispatch. Pre-existing; not touched by Phase 1 work. See `docs/QUALITY/KNOWN_ISSUES.md`.
- **BUG-013** — Soundcharts metadata source does not expose `time_signature`. Verified empirically. Money keeps ML-detected meter=2/X; wave cycles at 5.85 s/cycle instead of intended 20.5 s/cycle. Matt accepted as "smooth and synced — solid" at the round-26 review.

## Reference files to read first

Before authoring anything in the next session:

1. `docs/VISUAL_REFERENCES/ferrofluid_ocean/README.md` — the curated reference set + per-image annotations (mandatory trait checklist + anti-references). Failed Approach #63 — don't author from prompt text alone; READ THE README.
2. This file (you're reading it)
3. The last few rounds' commit messages: `git log --oneline f3fe9ed1~10..f3fe9ed1` — round-by-round narrative
4. `git diff bea09bc8 f3fe9ed1 -- PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal` — the material reflectivity arc (rounds 29-32)
5. Round 32's commit `f3fe9ed1` — current state of constants

## Discipline reminders

From CLAUDE.md `Authoring Discipline`:

- **The next response to pushback must change the answer, not justify it.** Multiple rounds in this session went the wrong direction first (round 29 env-tinted specular, round 28's over-bright aurora) and were corrected only when Matt's specific feedback forced the diagnosis. If a follow-up isn't producing the answer Matt wants, surface the architecture-level concern instead of producing another tuning iteration.
- **Limit variables — one visible change per commit.** Camera-angle change is one variable. Curtain-elevation re-tune is another. Commit separately; STOP gate between visual reviews. The capture-review-iterate loop has been efficient at ~1 commit per round.
- **Decisions presented to Matt in product-level language, not engineering jargon.** "Tilt the camera so no sky is visible" not "set scene_camera.target.y from 0.3 to -0.5." Numbers are Claude's responsibility; visual outcomes are Matt's.
