## Increment FTR.10 — Fractal Tree: step the trunk on the beat

**Type:** preset (shader + a small engine read of existing FeatureVector fields).

**Objective.** After this session the Fractal Tree trunk holds perfectly still between beats and steps to its new height ON the beat, instead of drifting continuously. Matt's words, 2026-08-11 session `2026-08-11T18-26-52Z`: *"The trunk is moving too much, which unfortunately makes the motion of the tips difficult to see. We need less motion — like tying movement to the songbeat."* Asked to choose between per-beat steps, per-bar steps, and continuous-but-smoother, **he chose steps on each beat** — that decision is taken, do not re-ask it.

---

### 1. Skills to invoke

- **`preset-session`** — BEFORE opening `FractalTree.metal` or its sidecar.
- **`shader-authoring`** — before GPU code.
- **`beat-sync-session`** — this is beat-locked motion on the cached grid; invoke before touching `beatPhase01` / `barPhase01`.
- **`closeout`** — at the end.

### 2. Read first

1. `docs/ENGINEERING_PLAN.md` — the **FTR.9 verdict + FTR.10 SPEC** entry (has the measurements and constraints; do not re-derive them).
2. `PhospheneEngine/Sources/Presets/Shaders/FractalTree.metal` — the object shader's growth block, and `base_len` in the mesh shader.
3. `docs/VISUAL_REFERENCES/fractal_tree/README.md` — the stylization contract and anti-references. **There is no image set by design** (Matt, 2026-08-03: build without references, judge live).
4. `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md` §Cold-Start Phase Contract.
5. `PhospheneEngine/Tests/PhospheneEngineTests/Presets/FractalTreeMeshRenderTest.swift` — the harness you must keep honest.

### 3. Pre-flight invariants

Each of these stops the session if it fails.

- PR #79 is merged, or this branch descends from it. `git log --oneline -1` shows FTR.9v or later.
- `Scripts/closeout_evidence.sh` is **ALL GREEN** before task 1. If not, fix that first — you are not starting from a clean base otherwise.
- `Scripts/link_fixtures.sh` has been run if this is a fresh worktree.
- **The live MIR analysis rate is ~10 Hz, not the 60 Hz render rate.** `features.csv` rows are per RENDER frame. Any per-frame alpha means `τ = 1/(α·10)`. Four increments shipped with this wrong — verify before quoting a rate.

### 4. Tasks

**Task 1 — measure the trunk's current motion on Matt's session.** Decompose `trunk = 0.27 + reach·0.13 + surge·0.32` and confirm the baseline: trunk **1.75 turns/s**, `surge·0.32` span 0.168 / 1.27 turns/s against `reach·0.13` span 0.109 / 0.80 turns/s.
**Done when** you have reproduced those figures from `2026-08-11T18-26-52Z` and can state which term you are changing.

**Task 2 — step the trunk on the beat.** The trunk holds its value between beats and re-samples on the beat boundary. Use the cached-grid phase already in the FeatureVector (`beatPhase01`, `beatsPerBar`, `pulse_beat_index`) — never raw live onsets.
**Done when** the held trunk measures **≤ 0.6 turns/s** on that session with the span within 10 % of the continuous version's 0.178 (measured: 0.51 / 0.173).

**Task 3 — the fallbacks, which are not optional.**
- **Beat-irregular tracks (D-154):** the grid is untrustworthy; fall back to continuous motion. A stepped trunk on a wrong grid is worse than a drifting one.
- **Cold start:** the grid can install with the right BPM and the WRONG phase, so early bars may step off-beat. The preset must not assume phase is right from frame 1.
- **No grid at all** (streaming / reactive): continuous.
**Done when** each path has a test and none of them renders a frozen trunk.

**Task 4 — keep the harness honest.** `FractalTreeMeshRenderTest` mirrors the shader's arithmetic; a mirror that models the OLD trunk measures a build that no longer exists. This has bitten three times (FTR.6's stale knee, the stems `time` filter, the missing `sectionRatio` in `recomputeDensity`).
**Done when** the mirror steps on the beat too, and the drive frames carry whatever new field you read.

**Task 5 — full-track regression.** `TrunkTrajectoryReportTests` on Cherub Rock and Hummer.
**Done when** motion is **no worse than FTR.9's 0.0292/s** (Cherub Rock) and the range stays 0.00…2.00 / trunk 0.00…1.00.

**Task 6 — pre-M7 motion gate. STOP AND REPORT after this.** Render a contiguous sequence and run `Scripts/motion_gate.sh fractal_tree <dir>`, **on a SINGLE-track capture** — a `LoudnessProfile` is per track, and a multi-track capture collapses the canopy to a sapling (FTR.9.1). View the frames and write the motion verdict: smooth? on-concept in motion? A stepped trunk is a new temporal character; the gate is the only thing that will show whether it reads as rhythmic or as stuttering.
**Done when** the verdict is written and Matt has been asked for the live M7.

### 5. Do NOT

- **Do not re-ask what "tied to the songbeat" means.** Answered: steps on each beat.
- **Do not add per-beat ACCENTS** — taps, flashes, pulses. Matt rejected beat-driven activity twice; this increment uses the beat to REMOVE motion, and adding activity re-treads retired ground.
- **Do not drive from raw live onsets** (±80 ms jitter). Cached `BeatGrid` only.
- **Do not touch the tips.** `other_onset_rate` (FTR.8) is settled; the point of this increment is to make the tips *visible*, not to change them.
- **Do not retune `sectionRatioTau`** (FTR.9) — the canopy is at 0.27 turns/s and Matt has not complained about it.
- **Do not lower a failing assertion to ship.** FTR.6 did exactly that with `tipSpread >= 5` and Matt saw the defect the assertion existed to catch. A red gate is the gate working.
- **Do not certify.** FTR.5 is Matt's call and he has not given it.

### 6. Verification

```bash
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
```

Increment-specific:

```bash
swift test --package-path PhospheneEngine --filter "FractalTree|BeatPulse|LiveDrift"
SECDET_AUDIO="/Volumes/Extreme SSD/S/Smashing Pumpkins/[1993] - Siamese Dream/01 Cherub Rock.mp3" \
  swift test --package-path PhospheneEngine --filter TrunkTrajectoryReport
FT_SESSION=<single-track session dir> RENDER_VISUAL=1 \
  swift test --package-path PhospheneEngine --filter sessionSequence
Scripts/motion_gate.sh fractal_tree <newest /tmp/phosphene_visual/fractal_tree_* dir>
```

### 7. Commits

`[FTR.10] <component>: <description>`, small and per logical step. Suggested: the stepped trunk; the fallbacks; the harness mirror; the docs.

**Do not push without Matt's explicit "yes, push".** Push to a BRANCH and open a PR — never directly to `main`, which requires `fast-gate`.

### 8. Closeout

Invoke the `closeout` skill. 8-part report, with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- the before/after trunk turns/s and span on Matt's session;
- the full-track `TrunkTrajectoryReport` figures for both tracks;
- the **motion verdict** from task 6 (a stepped trunk is a temporal change; a still sheet cannot judge it);
- which fallback paths are covered by which tests.

State plainly that this is **code-complete pending live M7**, never "resolved".
