## Increment WL.13 — Witchlight: make the figure the song's, not the mechanism's

**Type:** preset (path generator — no new audio route, no shader work)

**Objective.** After this session, two harmonically-static songs no longer draw the same figure. The pen's tendency to wind a single coil whenever the harmony sits on one side of its tonal home is either fixed or — if Matt chooses — deliberately kept and compensated elsewhere. Either way the outcome is decided by measurement on real material, and the cross-track heading correlation is a standing gate.

---

### Matt's words, verbatim (2026-08-07)

> "Is the ribbon path the same regardless of song or is the path of the ribbon influenced by the music? If not, this is a big opportunity for the preset."

### The measurement that already exists — do NOT re-derive it

`WitchlightPathDivergenceProbe` (committed with this spec) drives the production path over the three fixtures and reports the figure each one produces:

```
                turns  heading travel   phase travel  monotonicity  at clamp  sign-crossings/s
so_what           8     12.00 rad        13.10          0.98         25 %      0.47
there_there      11     17.03 rad        11.31          0.88         38 %      0.23
love_rehab        1     11.01 rad        94.89          0.38         17 %      1.64

cross-track heading correlation (1.00 = same path regardless of music)
  so_what vs there_there    r = +0.995   <- nearly the same figure
  so_what vs love_rehab     r = -0.703
  there_there vs love_rehab r = -0.690
  CONTROL so_what vs itself r = +1.000   <- the metric can detect sameness
```

**The answer to Matt's question is "yes, but".** The music does steer the path — `love_rehab` draws a genuinely different figure, and the control proves the metric can detect sameness when it exists. But **two of three tracks draw almost the identical trajectory.**

**The mechanism is identified, not guessed.** Steering is `desired = curvatureGain · phaseFromHome`, so the SIGN of `phaseFromHome` is the sign of the curvature. While the harmony sits on one side of its running tonal home, curvature holds one sign and the pen winds a coil; it only reverses when the harmony crosses home. Sign-crossing rate and monotonicity are inversely related across all three fixtures (1.64/s → 0.38; 0.47/s → 0.98; 0.23/s → 0.88), and mean |phaseFromHome| is nearly identical across them (0.39 / 0.65 / 0.41) — **so it is not that the harmony is closer to home, it is that it stays on one side longer.**

`WITCHLIGHT_DESIGN.md` §3.1(b) already names the high-monotonicity state as the degenerate "circle" failure, and the two coiling tracks sit at the turn-rate clamp 25 % and 38 % of frames against 17 % for the one that draws a figure.

### The trap this increment must not fall into

**WL.2 diagnosed almost exactly this and was wrong.** It concluded "the stroke does not read as a figure; cause is mechanism-level `θ ≈ k·φ̄`", parked it as an open decision for weeks with a standing do-not-tune — and **WL.3 refuted it entirely**: the path was fine, and an unbounded `tumbleYaw` was collapsing the projection. Read `WITCHLIGHT_DESIGN.md` §3.3.1 and the WL.3 plan entry before believing any generator-level story, including the one above.

What makes this different: the correlation is computed on the **heading time-series**, upstream of tumble, projection, camera and scale. No display-path defect can produce r = +0.995 there. The control at r = 1.000 proves the metric can distinguish. That is why this is a path finding and not a framing one — but the session should still confirm it, cheaply, before building.

---

### 1. Skills to invoke

- **`preset-session`** — before touching any Witchlight source.
- **`closeout`** — at the end.
- `shader-authoring` is **not** required and should not be needed (see Do-NOT).

### 2. Read first

1. `docs/presets/WITCHLIGHT_DESIGN.md` §3.1 (the three mechanisms), §3.1(b) (the clamp and the circle-degeneracy warning), §2.3 (the measured ~10× cross-track harmonic-rate spread).
2. `PhospheneEngine/Sources/Renderer/Geometry/WitchlightPath+Pen.swift` — `advancePen`, the whole steer.
3. `PhospheneEngine/Sources/Renderer/Geometry/WitchlightPath.swift` — `advanceHarmonicPhase`, and `phaseFromHome` / `homeTau`.
4. `PhospheneEngine/Tests/PhospheneEngineTests/Presets/WitchlightPathDivergenceProbe.swift` — the harness above.
5. `docs/ENGINEERING_PLAN.md` §WL.2 and §WL.3 entries — the wrong diagnosis and its refutation, in that order.

### 3. Pre-flight invariants

1. `origin/main` contains the WL.12 merge; `swift test --filter Witchlight` → **26 tests pass** (25 + the divergence probe).
2. `swiftlint --strict` → 0 violations.
3. `WitchlightPathDivergenceProbe` reproduces the table above, **including CONTROL r = 1.000**. If the control is not 1.000, stop — the path has become non-deterministic and nothing else in this increment can be interpreted.

### 4. Tasks

**Task 1 — confirm this is a PATH finding, not a display finding, before changing anything.**
The correlation is on `path.heading`, upstream of every display stage, so it should be immune — verify that claim rather than assume it. Null the tumble (`sessionPhase`, handedness) and re-run: `r` must be unchanged. Cost: one run.
**Done when:** the cross-track correlations are identical with the tumble nulled, recorded in the closeout. If they are NOT, stop — the WL.3 story is repeating and the diagnosis above is wrong.

**Task 2 — establish what "flat harmony" actually is on these tracks.**
`so_what` is modal (famously two chords); `there_there` is not. Measure, per fixture: the distribution of `tonalPhaseFifths`, its rate, and how long `phaseFromHome` holds each sign (median dwell, not just crossing count). Distinguish **"the harmony genuinely does not move"** from **"the harmony moves but `homeTau` = 12 s tracks it so slowly that it never crosses home."**
**Done when:** the closeout states which of the two it is, per fixture, with numbers. **This decides whether the fix is legitimate or a lie** — if the harmony truly is static, making the pen reverse anyway is inventing motion the music does not have, and that is a different (product) decision, not a bug fix.

**Task 3 — sweep the levers that are NOT gain, on all three fixtures plus at least two recorded sessions.**
Candidates, in order of how little they invent: `homeTau` (12 s — how fast "home" tracks the music); the home estimator itself (a circular mean may be the wrong centre for modal material); `turnConfirmSeconds`. Report per setting: cross-track correlation matrix, monotonicity, clamp fraction, sign-crossing rate, `headingTurnsPerTrail` (must stay ≥ 1.20 — it is a live QG.5 band).
**Done when:** a table exists and any chosen value is justified by it.

**Task 4 — HARD STOP. Report before proceeding if any of these hold at the chosen setting:**
- `headingTurnsPerTrail` < 1.20 on any fixture (live band), or
- any pair still correlates above **r = 0.90**, or
- monotonicity rises on any fixture, or
- distinct bead cores < 13, head-off-frame > 2 %, or ribbon share < 0.40 % (WL.9b/WL.10 contracts — and ribbon share is already at 0.406 %, so it has almost no headroom).

**Task 5 — a standing gate, so this cannot silently return.**
Add cross-track heading correlation to the test suite with a ceiling, and **prove it can go red** (drive two fixtures through a deliberately harmony-blind steer and assert it trips). WL.12's precedent: a band that cannot fail is worse than no band. This preset has produced two dead gates already.
**Done when:** the gate exists, has a floor/ceiling derived from measurement, and has a falsification test.

**Task 6 — regression + render + docs.**
Full Witchlight suite, §5 flash budget, `RENDER_VISUAL=1` sequence reviewed by eye for figure quality (a metric will not tell you whether the new figure is *good*). `WITCHLIGHT_DESIGN.md` §3.1(b) updated with the mechanism and the outcome; `ENGINEERING_PLAN.md` WL.13 entry.

### 5. Do NOT

- **Do not raise `steerGain` or `curvatureGain`.** WL.2 measured this exhaustively: k = 1.1 → 2.6 → 5.0 changed the figure **not at all**, because past k ≈ 1 the clamp saturates and heading becomes a slew-rate-limited dither — *straighter*, not curvier. The clamp fractions above (25 %, 38 %) show it is already saturating.
- **Do not raise `minTurnRadius`.** §3.1(b) is explicit: if the clamp saturates, the gain comes down; the radius does not go up.
- **Do not add an audio route to "add variety".** The figure's claim is that it IS the harmony. Injecting a second driver to decorrelate the paths would make the drawing prettier and the claim false. If the harmony is genuinely static, that is a product decision for Matt (below), not a routing fix.
- **Do not touch the camera, the fit, the pulse, or `.metal`.** All four are M7-signed-off.
- **Do not touch `trailSeconds`** — concept constant, Matt's call.
- **Do not validate on fixtures alone.** Use recorded sessions too; the fixtures are 21 s and this is a slow-timescale property.

### 6. Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
swift test --package-path PhospheneEngine
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
swift test --package-path PhospheneEngine --filter WitchlightPathDivergence
swift test --package-path PhospheneEngine --filter "Witchlight|ResponseBand|RouteCoverage"
WITCHLIGHT_FLASH_BUDGET=1 swift test --package-path PhospheneEngine --filter WitchlightFlashBudget
RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter WitchlightMotionSequence
```

`xcodebuild … test` SIGTERMs a running `PhospheneApp` — check `pgrep PhospheneApp` first.

### 7. Commits

`[WL.13] Witchlight: <description>` — small commits per logical step. **Push only on Matt's explicit "yes, push".** PR; never direct to `main`.

### 8. Closeout

`closeout` skill, 8-part report, verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific: the Task 1 tumble-null result, the Task 2 flat-vs-slow-home verdict per fixture, the Task 3 sweep table, before/after correlation matrix, and the eyeball verdict on whether the new figures are actually *better* — not merely less correlated.

---

### DECISION-NEEDED — for Matt, at Task 2

**When a song's harmony barely moves, what should the drawing do?**

The preset's premise is that the figure IS the track's harmonic motion. Two of the three test tracks have very little of it — one is modal jazz, which is two chords for the whole tune — and the pen responds by winding a coil. Faithful, and repetitive: two different quiet-harmony songs look much the same.

- **Option A — leave it faithful.** A song whose harmony does not move draws a simple, coiling figure. Honest, and those songs will resemble each other.
- **Option B — let the drawing find variety elsewhere when the harmony is still.** The figure would differ between two modal songs, but part of the shape would no longer be "the harmony" — it would be something else standing in for it.
- **Option C — make the sense of "home" adapt faster**, so even small harmonic moves register as direction changes. The figure stays entirely harmony-driven and gets more varied — but on a track that genuinely never moves, it would invent wandering the music does not have.

**Recommendation: C, with A as the fallback if Task 2 shows the harmony truly is static.** C keeps the preset's central claim intact; the measurement in Task 2 is exactly what says whether C is honest on this material or whether it is inventing motion.

**Default if no reply:** run Task 2, and if it shows the harmony *does* move but `homeTau` is too slow to register it, take C; if the harmony is genuinely static, stop and report rather than take B unasked.
