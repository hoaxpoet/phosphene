# MM.3 Kickoff — Murmuration audio coupling

**Phase:** MM (Murmuration promote + redesign + certify). **Increment:** MM.3.
**Date prepared:** 2026-06-03. **Predecessors:** MM.0 (rename), MM.1 (design doc), MM.2 (boids
flock engine + silence baseline) — all committed to local `main`, none pushed.

---

## Mission (one paragraph)

The Murmuration preset has a new **emergent GPU-boids flock** (MM.2) that, at silence, reads as a
dense, cohesive, density-graded, drifting starling mass. It currently has **zero audio coupling** —
it does not respond to music at all. MM.3 makes the flock respond to the music by **porting and
adapting the audio-coupling "brain" from the *original* Murmuration** (`Particles.metal`, the pre-MM
5K-ellipse flock) onto the new boids substrate. **This is a PORT, not a reinvention** (see §"#1
rule"). The end state: the flock behaves like another instrument in the band — bass is the wind that
drifts/stretches it, beats roll a dark orientation-wave across it, vocals make it breathe, mids
flutter its edge — while staying calm when the music is calm.

---

## Read first (binding — do not skip)

1. **`docs/presets/MURMURATION_DESIGN.md`** — the full design contract. Especially:
   - §2.1 motion findings (from real clips: shape vocabulary + timescales).
   - §3 musical contract (layers L1–L6, audio drivers, timescales).
   - **§3.1 signal coordination** — the flock is NOT six always-on drivers; it's a calm *substrate*
     (bass/vocals/mid, orthogonal DOF) + *punctuated events* (drum wave) arbitrated through one bus,
     energy-gated, **default under-react.** This is load-bearing — Matt's explicit worry was "too
     much happening at once." Honor it.
   - **§3.2 CARRY FORWARD the original's audio coupling** — the binding port list.
2. **`PhospheneEngine/Sources/Renderer/Shaders/Particles.metal`** — the ORIGINAL Murmuration audio
   brain. This is your reference source to port from. Read its `particle_update` kernel carefully:
   the drum **turning-wave propagation**, bass shape/drift, "other" edge-weighted flutter, vocals
   density-compression, and the warmup stem-blend are all here, with days of tuning in them.
3. **`docs/ENGINEERING_PLAN.md` → Phase MM → Increment MM.3** — done-when + the carry-forward note.
4. **`CLAUDE.md`** — Audio Data Hierarchy (continuous primary, beats accent only), D-026 (deviation
   primitives, never absolute thresholds), FA #26 (`max(beatBass, beatMid, beatComposite)`), FA #72
   (MSL fields are snake_case; Swift are camelCase), the "test in production-grade pipeline" rule,
   and "diagnostic infrastructure precedes fidelity claims."
5. **Memory `project_murmuration_uplift.md`** — full project history incl. the MM.2 course-correction.

---

## Current state — what exists (MM.2, all on local `main`)

- **`PhospheneEngine/Sources/Renderer/Shaders/MurmurationFlock.metal`** — the boids engine. Kernels
  `murmuration_reset_cells` → `murmuration_bin` (atomic) → `murmuration_boids`; render
  `murmuration_flock_vertex` / `murmuration_flock_fragment`. MSL structs `MurmurationBird` (48 B) and
  `FlockParams` (96 B). Forces: separation/alignment/cohesion over a 3×3×3 grid neighbourhood + a
  distance-scaled global roost leash (`roostWeight + roostFar·dist`, the anti-fragmentation fix) +
  wander + banking. Birds rendered as dark point sprites; per-bird `neighborCount` drives the
  core-dark / edge-feathered opacity.
- **`PhospheneEngine/Sources/Renderer/Geometry/MurmurationFlockGeometry.swift`** — the
  `ParticleGeometry` conformer. Swift mirrors of `MurmurationBird` / `FlockParams` /
  `MurmurationFlockConfiguration`. `update(features:stemFeatures:commandBuffer:)` encodes
  reset→bin→boids; **it already receives `features` AND `stemFeatures` but currently ignores the
  audio** — this is where MM.3 audio coupling goes. `roostTarget(time:)` is the current absolute
  procedural drift (MM.3 displaces it with bass). `makeParams(...)` builds `FlockParams`.
- **Wired into the app:** `PhospheneApp/VisualizerEngine.swift` `makeMurmurationGeometry` builds
  `MurmurationFlockGeometry`. The preset renders live (silence-inert).
- **Harness:** `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/MurmurationFlockTests.swift` —
  runs the REAL dispatch path; asserts the 30 s silence baseline stays cohesive / bounded / flying /
  core-dense / unified / framed. `RENDER_VISUAL=1` writes frames to
  `tools/murmuration_reference/frames/mm2_silence_*.png`.
- **Reference sources (keep until MM.3 ports them):** `Particles.metal` + `ProceduralGeometry.swift`
  (the original). Do not delete in MM.3 — they're the port source. Retiring them is a later cleanup.
- **Render path:** `RenderPipeline+Draw.swift` calls `particles?.update(features:stemFeatures:
  commandBuffer:)` then `RenderPipeline+FeedbackDraw.drawParticleMode` clears → draws the sky
  fragment → `particles.render(encoder:features:)`. (No feedback trail — crisp, per Matt.)

Current MM.2 silence tuning lives in `MurmurationFlockConfiguration` defaults (count 55 000, grid 24³,
cohesion 3.0/0.16, alignment 3.5/0.16, separation 7.0/0.075, roostWeight 1.0, roostFar 2.5, wander
0.34, maxSpeed 0.7, minSpeed 0.12). `kViewScale 1.3` in the shader vertex. Don't regress the silence
baseline while adding audio.

---

## The #1 rule: PORT the original, do NOT reinvent

The single biggest failure mode for this increment (Matt flagged it explicitly, 2026-06-03) is
**re-deriving the audio coupling from scratch** when the original `Particles.metal` already has a
tuned, advanced version. The original's mechanics ARE the design:

- **Drum turning-wave** (= contract L2): `beatEpoch = floor(t·2.5)`, per-epoch alternating `propDir`;
  `waveFront = 1 − beatPulse` sweeps a bird-flock coordinate; triangular bump
  `waveInfluence = max(0, 1 − |waveFront − birdCoord|/waveWidth)` applies a **perpendicular** turning
  force. Lift this mechanic onto the boids: a banking/turn impulse that propagates across a flock-axis
  coordinate so a dark orientation band rolls across the mass on the beat. (The boids `bank` field +
  render shading already make banking read as darkening — wire the wave into it.)
- **Bass → drift + shape elongation** (L1): displace the roost target (drift) and elongate the flock
  (anisotropic cohesion or an axis-scaled attractor) → comma/ribbon.
- **"Other"/mid → edge-weighted flutter** (L4): the original weighted by `distFromCenter`; on boids
  weight by inverse `neighborCount` (already computed per bird).
- **Vocals → density compression / "dark pulse"** (L5): tighten cohesion/separation radius → breathing.
- **Warmup stem-blend** (D-019): `smoothstep(0.02, 0.06, totalStemEnergy)` crossfade full-mix ↔ stem.
- **Cross-genre beat** (FA #26): `max(beatBass, beatMid, beatComposite)`, not `beatBass` alone.

**The ONE place you improve on the original:** convert raw AGC energy reads → **deviation primitives**
(D-026) — `bass_att_rel`, `drums_energy_dev`, `mid_att_rel`, `vocals_energy_dev`, etc. The original
violated D-026; the boids port fixes that. (Verify exact Swift field names in
`PhospheneEngine/Sources/Shared/AudioFeatures+Analyzed.swift` and the MSL names in
`Renderer/Shaders/Common.metal` — Swift camelCase, MSL snake_case, FA #72.)

---

## Implementation notes

- **Where audio enters:** `MurmurationFlockGeometry.update(...)` already has `features` +
  `stemFeatures`. Add audio fields to `FlockParams` (BOTH the Swift struct and the MSL struct in
  lockstep — `FlockParams` is passed via `setBytes` each frame, not a persistent GPU contract, so its
  size may change freely; just keep the two definitions byte-identical and re-check
  `MemoryLayout<FlockParams>.stride`). Compute the per-frame audio scalars (deviation primitives,
  warmup-blended, energy-gated per §3.1) CPU-side in `update()`/`makeParams`, pass them in, and
  consume them in `murmuration_boids`.
- **Coordination (§3.1) is mandatory:** continuous substrate (bass/vocals/mid) modulates smoothly;
  the drum wave is a punctuated, beat-quantized event; **scale the whole event layer by overall
  energy/arousal so the flock is near-pure-substrate (calm) in quiet passages.** Default to
  under-react. One primitive per layer, one timescale (FA #67).
- **L3 flash-expansion is DEFERRED** (Matt 2026-06-03). Build L1/L2/L4/L5 first; add L3 only once the
  base reads right.
- **Don't break the silence baseline:** with zero audio (warmup / silence), behaviour must equal the
  MM.2 baseline (the harness asserts it). Audio terms must vanish at zero input.
- **Magnitudes:** start from `MURMURATION_DESIGN.md` §3 (comma aspect ≤ ~3:1, wave traverse
  ~0.5–1.5 s alternating direction, breathing ±20–30 % over 4–8 s). Continuous : beat ≥ 2× (hierarchy).

---

## Verification / done-when

1. **Routing unit tests** (extend `MurmurationFlockTests`): inject non-zero stems via the real
   dispatch path and assert each route changes flock state the intended way (bass → elongation/drift;
   drum beat → a non-uniform turning response that propagates, not a uniform jump; mid → edge birds
   move more than core; vocals → tighter packing). Zero stems → identical to the MM.2 silence baseline
   (no freeze, no fragmentation — keep the 30 s cohesion/framed assertions green).
2. **Per-route firing EVIDENCE from a REAL session** (not assertion, not synthetic audio): run a real
   music session (or `PresetSessionReplay` over a recorded session) and show, from `features.csv` /
   `stems.csv` + extracted video frames, that each route fires on the musical events it should. Cite
   frame counts / threshold-crossing %. (CLAUDE.md "diagnostic infrastructure precedes fidelity
   claims"; "never synthetic audio for fidelity claims.")
3. **Continuous : beat ratio ≥ 2×** verified; no absolute AGC thresholds (D-026).
4. **Full engine suite green** (`swift test --package-path PhospheneEngine`), **swiftlint --strict 0
   violations**, **app builds** (`xcodebuild -scheme PhospheneApp -destination 'platform=macOS'
   build`). Murmuration golden hashes are unchanged by particle work (the regression test renders only
   the sky fragment) — confirm, don't regenerate unless you touch the sky.
5. **Matt M7 manual review in the live app on real music** — the load-bearing gate. Show it responds
   musically AND stays calm in calm passages (not busy). This is MM.5's cert gate; MM.3's bar is "the
   audio coupling demonstrably works and reads musical."
6. **Closeout report** per CLAUDE.md (files changed, tests, firing evidence, docs, plan/registry,
   risks). State which dispatch path the tests exercised.

---

## Discipline reminders (CLAUDE.md)

- **Port, don't reinvent** (the #1 rule above). If you find yourself designing a turning-wave from
  first principles, stop — read `Particles.metal` and lift it.
- **Verify against the artifact** before asserting. (The MM.2 process error was declaring the old
  flock "the anti-reference" without ever rendering it.)
- **Surface risk early**, don't flail: if 2 tuning rounds don't converge, stop and write "what I now
  believe about why it's failing" — if that sentence doesn't change between rounds, re-scope and ask.
- **Commit in small steps** to local `main` (`[MM.3] <component>: <desc>`). **Do not push** without
  Matt's explicit "yes, push."
- Audio is **accent over continuous** — beats never become the primary motion driver (FA #4).

---

## Git state at handoff

Local `main`, not pushed. Relevant commits: MM.0 rename `e3c5dafc`; MM.1 design `17ac3462` /
`f951a322` / `eaea96a3` / `208790c1`; MM.2 engine `30a6f844`, wiring `8dc48664`, freeze-fix
`90f82f20`, carry-forward docs `72d5f198`. Tree clean.
