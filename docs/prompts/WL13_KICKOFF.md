# WL.13 kickoff — paste this into a fresh session

Implement **WL.13**. The full spec is in the repo and is the authority:

**`docs/prompts/WL13_THE_FIGURE_IS_THE_SONGS.md`** — read it end to end before doing anything. It carries the objective, the skills to invoke, the read-first list, pre-flight invariants, six numbered tasks with done-when criteria, a mid-session hard stop, an explicit Do-NOT list with evidence, verification commands, and Matt's decision.

---

## What this is, in one paragraph

Matt asked whether the ribbon's path is actually influenced by the music or is the same shape every song. Measured answer: the music *does* steer it, but **two of three test tracks draw almost the identical trajectory** (heading correlation r = +0.995, against a control of r = 1.000 that proves the metric can detect sameness). The mechanism is pinned: steering is `curvatureGain · phaseFromHome`, so while the harmony sits on one side of its running tonal home the curvature holds one sign and the pen winds a coil. It reverses only when the harmony crosses home — and sign-crossing rate tracks monotonicity inversely across all three fixtures.

## Matt has already decided the approach — option C

> "also, option C for task 2"

Make the sense of tonal **home adapt faster**, so even small harmonic moves register as direction changes. The figure stays entirely harmony-driven; **no second audio driver is introduced**. `homeTau` (currently 12 s) is the primary lever.

**Task 2 still runs.** It no longer decides *whether* to do C — it decides whether C is **honest on a given track**. One fixture is modal jazz (two chords for the whole tune); if a track's harmony genuinely never moves, adapting home faster manufactures reversals the music does not contain. The closeout must say which tracks are which, per fixture, rather than quietly shipping invented motion. Matt keeps the final call; the obligation is to tell him.

## The single biggest risk, stated up front

**WL.2 diagnosed almost exactly this and was wrong.** It parked "the stroke does not read as a figure, cause is mechanism-level `θ ≈ k·φ̄`" as an open decision for weeks with a standing do-not-tune — and WL.3 refuted it entirely: the path was fine, and an unbounded `tumbleYaw` was collapsing the projection every ~57 s.

What makes this finding different is that the correlation is computed on `path.heading`, **upstream of tumble, projection, camera and scale**, with a control at r = 1.000. **Task 1 verifies that in one run anyway.** Do not skip it. If nulling the tumble changes the correlations, the diagnosis above is wrong and the session stops there.

## State you cannot infer from the repo

- **Witchlight is CERTIFIED** (2026-08-07, WL.CERT — the 18th certified preset, `certified: true`). Matt signed off the look, the pulse, the framing and the drift compensation across WL.7–WL.12. **Anything you change can un-certify it.** The Do-NOT list is not advisory.
- `main` is at `d814f0e6` or later. Branch from it; **never push to `main` directly** — it is the one route that skips `fast-gate`.
- **Push only on Matt's explicit "yes, push"**, then PR. Same for merging.
- **`xcodebuild … test` SIGTERMs a running `PhospheneApp`.** Run `pgrep PhospheneApp` first; if Matt is testing, skip it and say so. `Scripts/closeout_evidence.sh` runs that step — same guard applies. This has already cost a wasted diagnosis cycle once.
- **CI is slow and gets cancelled.** `runs-on: macos-26` (required — the Xcode 26 SDK marks Metal protocol types `Sendable`; macos-14 red-builds every target). Jobs have queued 40+ minutes. `concurrency: cancel-in-progress` means **every new push to the branch cancels the in-flight run** — batch pushes rather than pushing repeatedly.
- **The DOC.6 rotation gate is date-driven** and has turned `main` red twice on a calendar boundary with no code change. If `DocIntegrityTests` fails on "entries older than 14 days", run `Scripts/rotate_docs.sh` — it is mechanical and verbatim.
- **Recorded sessions for validation** live in `~/Documents/phosphene_sessions/2026-08-0*/` (10 with `features.csv`). Use them: the committed fixtures are ~21 s and this is a slow-timescale property. `WitchlightSpeedSweep` takes `WITCHLIGHT_SESSIONS=<dirA>:<dirB>`; `WitchlightBeatAlignmentProbe` takes `WITCHLIGHT_SESSION=<dir>`.
- **`Scripts/link_fixtures.sh`** symlinks gitignored fixtures into a worktree; without it ~21 engine tests fail environmentally.

## Two habits this preset's history rewards

1. **Measure through the production object on real material — never a re-implementation.** A Python model of one term reported a 1.57× pen-speed swing where the real path gives ~10×; the model had omitted a 7× multiplier sitting on the same product. A fixture gate reported 17.9× and was rationalised as a metric artifact when it was the actual signal. **A number that disagrees with your model is the signal.**
2. **Prove every new gate can go red.** This preset has shipped two gates that measured nothing — an edge-on check pinned at a constant 1.000, and a pumping metric that returned an identical number at every setting. Task 5 requires a falsification test for the new correlation gate, and it is not optional.

## Start here

1. Invoke the **`preset-session`** skill.
2. Read `docs/prompts/WL13_THE_FIGURE_IS_THE_SONGS.md`.
3. Run the pre-flight invariants. Do not start Task 1 until they hold.
