BEAT_SYNC_PROGRAM_PLAN.md — Program plan: beat-match & music-sync across the five hard categories

Status: DRAFT — awaiting Matt ratification (becomes a DECISIONS.md entry + ENGINEERING_PLAN.md phases on GO) Date: 2026-07-26 Origin: Matt's five-category brief (2026-07-26) + the strategy session preceding this plan. Realizes the D-145 "beat-sync elevated to its own project" direction. Ratified inputs (Matt, 2026-07-26): ground truth = human taps + reference-tool cross-check; rolling live grid is research-gated before any engine code; local-file and streaming paths proceed in parallel; new skills are specced here and authored as the first increment after plan approval.

1. Program goal and measurable targets

Phosphene's beat-match and music-sync must handle five categories of material. Each category gets a benchmark suite with named tracks and a numeric bar. No increment in this program may claim a category win without a benchmark number — the verifier-passing→M7-failing pattern (CS.1 → BSAudit.3, six iterations) is the documented cost of skipping this.

#	Category	Suite tracks (new + existing catalog)	Target (proposed — finalized against GT.3 baseline, DECISION D-B)
1	Baseline 4/4, strong pulse	Billie Jean, Around the World, Stayin' Alive, Superstition (+ love_rehab, Cherub Rock, Get Lucky, Everlong)	Beat F-measure ≥ 0.95 offline; live phase error p90 < 30 ms held across the full track (closes BUG-065's 50–70 ms mid-track wander); downbeat correct
2	Odd meters	Take Five (5/4), Money (7/4), Solsbury Hill (7/4), Pyramid Song (grouped 16/8) (+ So What)	Meter decoded correctly on ≥ 3/4; beat F-measure ≥ 0.85; Money no longer REACTIVE on the live path (closes BUG-001 ceiling, BUG-013 workaround-by-decoding)
3	Mid-song tempo changes	Bohemian Rhapsody, Giorgio by Moroder, Dance Yrself Clean	Grid re-locks within ≤ 20 s of a tempo change (≤ 2 analysis windows); phase error back under 50 ms after re-lock; no confident wrong-tempo pulse during the transition
4	Dense transients / polyrhythm	Bleed (Meshuggah) (+ There There as the syncopation case)	Quarter-note grid tracked (not the herta subdivisions): beat F ≥ 0.80; There There reads ~86 BPM meter, not the ~140 kick rate
5	Ambiguous / rubato	Girl from Ipanema (weak-transient steady), Clair de Lune (true rubato) (+ Pyramid Song crossover)	Split target. Ipanema: tracked softly, F ≥ 0.80. Clair de Lune: confident-wrong rate ≈ 0 — beatConfidence stays below the accent threshold ≥ 90% of duration, visuals driven by energy/harmony layers. Success = declining honestly, not faking a beat

Category 5's second half is the inversion that makes the whole program honest: for true rubato the deliverable is a trustworthy confidence signal, not a beat. This upgrades D-154's binary exclusion into graded behavior.

Standing constraints (not re-litigated by this program):

D-004 / Audio Analysis Hierarchy: continuous energy is the primary visual driver; beats are accents. This program improves an accent-layer signal.
CLAUDE.md §Cold-Start Phase Contract + FA #69: no automated short-window (≤ ~15 s) cold-start beat-phase derivation. Cold start remains BeatPulseClock / first-note anchor. Everything here is steady-state tracking.
FA #68: onset-vs-grid alignment is never a beat-phase reference (it remains usable as drift evidence against an already-trusted grid).
D-075: never fuse onset bands for IOI timestamps.
2. Why the current architecture caps all five categories

One paragraph of grounding (full detail: ARCHITECTURE.md §Audio Analysis, BEAT_SYNC.md capability registry, BSAudit findings): today's premise is a constant-BPM grid built once from a 30 s preview clip — often a different recording than the audio being played (BSAudit.2's cross-capture instability root) — extrapolated to a 300 s horizon and aligned to the live tap by sub-bass onset matching whose EMA bounds drift without tightening it (BUG-065). Each category fails on a different edge of that premise: tempo changes are invisible to a frozen single-BPM grid; odd meters die in BeatGridResolver's peak-pick + median-IOI meter inference (Money logged beatsPerBar=2); gapless segues make anchors meaningless (FBS Stage-1 verdict); dense material saturates the sub-bass onset evidence; rubato gets either a robotic pulse or a hard exclusion. The per-component machinery (Beat This! weights, MPSGraph port, drift tracker, pulse clock) is largely sound — the program replaces the premise around it.

What is already proven and is kept: Beat This! offline tempo (~1% error, reproducible); first-note anchor (~28 ms, D-153); LF.2's same-bytes-analyzed-and-played property (phase correct by construction); the D-154 irregularity assessment (evolves, not deleted); all existing diagnostic CLIs.

3. Program map

Eight phases. GT and SK unblock everything; DBN and TRK are independent of each other; FT depends on DBN; RLG is research-gated; CNF consumes signals from DBN + RLG + TRK; MDL is optional headroom.

SK  (skills)          ──┐
GT  (ground truth)    ──┼──> DBN (decoder) ──> FT (full-track, local files)
                        │        │
                        ├──> RLG.0 (research gate) ──[GO/NO-GO]──> RLG.1–3 (rolling live grid)
                        │        │                                     │
                        ├──> TRK (tracker tightening)                  │
                        │        └──────────────┬──────────────────────┘
                        └──> MDL (model A/B)    v
                                           CNF (confidence + graded degradation)

Parallelism for Claude Code sessions: after GT.3, DBN and TRK and RLG.0 can run as interleaved workstreams (they touch disjoint code: BeatGridResolver vs LiveBeatDriftTracker vs offline tooling). FT is the local-file proving ground and lands category-3 wins even if RLG.0 returns NO-GO on streaming.

Per-category leverage: category 1 ← TRK; category 2 ← DBN (+RLG for live); category 3 ← FT (local) + RLG (streaming) + DBN's tempo-state model; category 4 ← DBN + TRK.2 + MDL; category 5 ← CNF.

4. Phase specs

Conventions for every increment (house rules, restated once): diagnostic logging lands first; new runtime behavior ships behind an env flag with an A/B path for one increment; commits [PHASE.N] component: description; closeout per the closeout skill; docs updated in the same increment (ARCHITECTURE.md, DECISIONS.md, KNOWN_ISSUES.md as applicable); the five-iteration stop rule applies program-wide — any increment that fails validation twice on the same premise stops and reports instead of iterating.

Phase SK — Author the program skills (1 session)

SK.1 — Author 4 new skills + 2 skill edits. Content specs in §6 of this doc. Skills land in the repo's skill directory alongside preset-session/closeout/etc. Done-when: each skill loads, its trigger description matches §6, and a dry-run session prompt for GT.1 correctly pulls beat-sync-session + session-forensics. No engine code.

Phase GT — Ground truth + benchmark harness (3–4 sessions + ~40 min of Matt's time)

GT.1 — Fixture acquisition + manifest. Acquire full-length local files for the 12 new tracks (Matt's library; commit nothing bulky — fixtures live outside the repo at a path given by BEATBENCH_FIXTURES_DIR, with a committed manifest of content hashes + expected durations, following the gitignored MP3/FLAC fixture pattern). Done-when: manifest committed; a presence-gate test fails loud (never skips — QR.3 doctrine) when the dir is absent, and passes on Matt's machine.

GT.2 — Tap-capture CLI + reference cross-check + reconciliation.

TapCapture CLI (swift-argument-parser, same family as TempoDumpRunner): plays a fixture, records Matt's keypress timestamps against the playback clock. Includes a latency-calibration round (tap to a generated metronome; median offset subtracted from all subsequent taps). Two passes per track: beats, then downbeats (or beat-taps + "1" annotation). ~40 min total for the catalog.
Reference-tool pass in tools/beatbench/ (Python venv): madmom DBNBeatTracker + the vendored Beat This! PyTorch reference produce independent annotations. License note: these run offline as annotation tools only — nothing from madmom (code or CC-NC models) ships in the product.
Reconciliation report: where taps and tools agree within 70 ms → ground truth; disagreements listed for Matt to resolve by ear (expected concentration: Bleed, Pyramid Song, Clair de Lune — for Clair de Lune the ground truth may legitimately be "no stable grid," which is the annotation).
Done-when: Tests/Fixtures/beatbench/<track>.groundtruth.json for all tracks; calibration offset documented; reconciliation report committed under docs/diagnostics/.

GT.3 — Scoring harness + baseline capture. BeatBench CLI: given a grid (offline JSON or a recorded session's features.csv) + ground truth, emit standard metrics (F-measure @±70 ms, Cemgil, CMLt/AMLt continuity, downbeat F) plus Phosphene-specific ones: phase-error-vs-time-in-track percentiles (the BUG-065 curve), time-to-lock, lock%, and confident-wrong rate (frames with high confidence AND phase error > 70 ms — the category-5 metric). Per-category suite definitions in a committed config. Then capture the current system's baseline across all five suites, offline grids + live replay of recorded sessions, published as docs/diagnostics/BEATBENCH_BASELINE_<date>.md. Done-when: baseline doc exists with a number in every cell of the §1 table; targets ratified or revised against it (DECISION D-B); harness runs in CI on synthetic fixtures (real-audio suites are local-only, env-gated).

Phase DBN — Sequence decoding replaces peak-picking (5–7 sessions)

DBN.1 — Desk research + spec doc (no code). Written spec of a bar-pointer-model decoder over Beat This! activations, from the papers (Krebs et al. 2015; Böck et al. DBN post-processing; Beat This! ISMIR 2024): state space (tempo × bar position), transition model (tempo-change penalty as an explicit tunable — this is the category-3 lever), observation model from per-frame beat/downbeat probabilities, meter hypothesis set {3, 4, 5, 6, 7, 9, 12}, output = beats + downbeats + per-segment tempo + posterior confidence. Spec-fidelity discipline per the reference-port skill (the BeatNet paraphrased-spec-drift lesson is the cautionary tale). License gate: implement from paper spec; no madmom code copied (activation-level algorithms, clean-room from the papers). Done-when: spec doc committed with every constant sourced or marked as a tunable with a default; DECISION-NEEDED list resolved with Matt.

DBN.2 — BeatActivationDecoder implementation. Pure Swift + Accelerate, DSP module, offline-path only (Viterbi over ≤ 50 fps frames is CPU-trivial next to the transformer). Unit-tested on synthetic activations: clean 4/4, 7/4, tempo ramp, tempo step, silence, noise-floor. Performance budget: < 50 ms for a 30 s activation window on M1. Done-when: unit suite green; budget test in DSPPerformanceTests.

DBN.3 — Wire as BeatGridResolver alternative, benchmark A/B. Env-flagged (BEATGRID_DECODER=dbn|peak); both paths produce grids from the same activations; BeatBench compares on all suites. Load-bearing gates: Take Five 5/4; Money 7/4 (~123 BPM); Solsbury Hill 7/4; Pyramid Song grouped meter; there_there 84–92 BPM; no regression on suite 1. Done-when: A/B table committed; decoder becomes default on win; peak-pick path retained one increment then deleted.

DBN.4 — Piecewise-tempo BeatGrid v2. Grid carries tempo segments instead of one BPM + 300 s extrapolation. API: localTiming/nearestBeat/beatIndex(at:) generalized; grid_bpm consumers audited (every preset + engine reader enumerated — this is a GPU-adjacent contract change, DECISION D-F on grid_bpm semantics: instantaneous-at-playhead vs whole-track median). Cache version bump + lazy backfill per the D-059/S6 pattern. Done-when: consumer audit table committed; all existing suites green; goldens regenerated where grid_bpm semantics changed.

Phase FT — Full-track analysis for local files (2–3 sessions, depends on DBN.4)

FT.1 — Beat This! sliding-window tiling. Lift the tMax = 1500 (~30 s) clamp for the offline path: tile the full track in ~30 s windows with 50% overlap, average activations in overlap regions, decode once over the stitched full-track activation timeline (this is where DBN pays off — a single decode over a full track handles Bohemian Rhapsody's structure natively). Cost: ~1 forward pass per 15 s of audio, offline prep only, MLDispatchScheduler-budgeted. Done-when: stitched-activation parity test (tiled vs single-window on a ≤ 30 s fixture, near-identical); full-track grid on Bohemian Rhapsody shows the tempo segments.

FT.2 — Local-file integration (LF.3 realized). prepareAndStartLocalFilePlayback uses the full-track piecewise grid; no extrapolation for local files; BeatPulseClock unchanged for cold start. Benchmark suite 3 on the local path is the acceptance gate. Done-when: suite-3 targets met on local files; suite 1/2 no-regression; session capture + M7.

FT is deliberately the proving ground: if RLG.0 returns NO-GO, categories 2 and 3 still land in full for local files, and streaming keeps the improved offline grids + TRK improvements.

Phase RLG — Rolling live grid for streaming (research-gated; 2–3 + 4–6 sessions)

RLG.0 — Offline reproducibility study (no engine code — the gate). Using existing recorded sessions' raw_tap.wav + new captures of suite-3 tracks streamed: simulate the rolling scheme offline — 25–30 s windows every 5–10 s, stitching, and an agreement gate (commit a phase/tempo update only when N consecutive overlapping windows agree within ~30 ms phase / 2% tempo; disagreement = hold current grid, lower confidence). Measure per-track: committed-update rate, agreement stability, phase error of the committed grid vs taps/PCM, tempo-change tracking latency on Giorgio/Bo Rhap captures. This directly re-tests BSAudit 5b with the stitching + gating design that 5b's raw per-window measurement lacked. GO bar (proposed, DECISION D-C): ≥ 80% of the regular-beat catalog sustains committed updates with phase error < 50 ms, and tempo changes are caught within 2 windows; NO-GO otherwise, findings documented, streaming falls back to FT + TRK + CNF scope. Done-when: study doc with per-track tables; Matt GO/NO-GO recorded as a DECISION.

Guard rail: this is not the FA #69 family (steady-state full-length windows, not cold-start short-window phase derivation) — but RLG.0 exists precisely so we never build the engine version on hope. If the study fails, we do not iterate window sizes more than once (five-iteration rule scoped to 2 here).

RLG.1 (GO only) — RollingBeatTracker engine component. Window scheduler on the analysis queue (respecting MLDispatchScheduler), trailing-buffer inference, stitcher + agreement gate as validated in RLG.0, env-flagged, fully session-logged (every window: tempo/phase/agreement verdict → session.log + features.csv columns). Done-when: unit + replay tests reproduce RLG.0's numbers through the engine code path.

RLG.2 — Integration semantics. Rolling grid vs cached preview grid arbitration (rolling wins once committed); gapless segue behavior (grid continuity across title changes — no anchor resets); BeatPulseClock hands off to the first committed grid at a bar boundary (the FBS Stage-3 handoff, finally buildable against a trustworthy target); track-change resets. Done-when: segue capture shows continuous lock across a gapless boundary; cold-start contract untouched.

RLG.3 — Live validation + M7. Streaming captures across all five suites; BeatBench on the live path; M7 perceptual review. Done-when: suite 2/3 streaming targets met or gaps documented as bounded limitations.

Phase TRK — Live tracker tightens, not bounds (3–4 sessions, independent of DBN)

TRK.1 — Controller replacement, replay-first. Replace the bounded EMA with a PLL-style phase/period controller (or 2-state Kalman) whose correction gain is scheduled by match confidence — high confidence converges toward zero error, low confidence coasts on the grid (never chases, honoring the FBS "hold steady" lesson). Built and tuned entirely against recorded-session replay (LiveDriftValidationTests pattern + the BUG-065 Cherub capture) before any live run. Gate: Cherub drift-by-window ≤ 30 ms in every 10 s window (vs today's 11→70 ms growth). Done-when: replay gate green; env-flagged A/B in one live capture.

TRK.2 — Evidence upgrade: drums-stem onsets. Once live stems stabilize (~10 s), the tracker matches against drums-stem onsets instead of raw sub_bass (crossfade mirrors the stem pipeline's own live handoff). Sub_bass remains the pre-stem and fallback evidence. This is the category-4 live lever: Bleed's palm-muted 16ths saturate sub-bass flux; the drums stem carries the actual pulse. Done-when: suite-4 live matching improves on replay; D-075's no-band-fusing rule respected (drums-stem onsets are a different detector instance, not a fused band).

TRK.2 OUTCOME (2026-07-30) — PREMISE FALSIFIED, increment stopped at its evidence gate. Measured on four captures with the production StemSeparator + a separate BeatDetector instance (D-075), bias-corrected: drums-stem sub_bass onsets within ±50 ms of a grid beat vs full-mix sub_bass — love_rehab 16.9 % vs 42.2 %, Hummer 11.0 % vs 14.4 %, bleed.wav 22.4 % vs 22.3 %, billie_jean 25.5 % vs 24.5 %. Worse on two, a wash on two — including Bleed, the category-4 track this increment's argument rested on. Best drums band anywhere +2.5 pp (noise). No production code changed. Two consequences for the program: (a) the category-4 "drums stem carries the actual pulse" assumption in the leverage table above is not supported by measurement — category 4 leans on DBN and MDL, not TRK.2; (b) the ceiling generalises FA #68 — across every capture, band and stem only ~15–25 % of detected onsets land within ±50 ms of a beat, so ANY tracker whose evidence is a spectral onset flag inherits a ~75–85 % off-beat rate, whatever its controller topology. Separately, the live stem path (runPerFrameStemAnalysis) carries a deliberate 5–10 s latency with a ~5 s sawtooth re-anchor, so drums onsets cannot be timestamped by the tracker without a distinct design. Evidence: docs/diagnostics/TRK2_DRUMS_STEM_EVIDENCE_2026-07-30.md; instrument: DrumsOnsetEvidenceTests (env-gated PHOSPHENE_TRK2_EVIDENCE=1).

TRK.3 — Live validation + M7. BUG-065 closure gate: < 30 ms held across full tracks on suites 1 and 4. BUG-028's "behind the beat" feel re-reviewed. BLOCKED: TRK.1 failed replay validation (strike 1) and TRK.2's evidence upgrade is falsified, so there is nothing to validate live.

PROGRAM STATUS 2026-07-31 — THE EVIDENCE LEVERS ARE EXHAUSTED. Three increments have now established the same finding independently: TRK.2 falsified onsets as a source of beat evidence (only ~15-25 % of onsets from ANY band or stem land within ±50 ms of a beat); DBN.2 removed the observation-model bias and found odd meters still won by hairline margins with a confidence signal that cannot separate right from wrong; MDL.1 ran a 10x larger checkpoint of the same family and got no cleaner downbeat stream, with the suite-4 track regressing (D-208). The downbeat evidence is thin, and it is not thin because of how it is read. CONSEQUENCE: categories 2 and 4 need a CHANGED PREMISE, not another pass at these levers. DBN.3 should NOT open as specified — A/B-ing the decoder against the incumbent would measure its known-wrong odd meters and non-separating margin rather than the decoder. Unexplored candidates: a different model family, a different training target, or sourcing bar position from something other than a downbeat activation stream. Phases GT/FT/RLG/CNF are unaffected; FT in particular still lands category-3 wins for local files independently of this.

PHASE TRK — PARKED (D-206, Matt 2026-07-30: "park the tracker, go DBN next session"). Both levers — controller topology (TRK.1) and evidence source (TRK.2) — were measured against the same frozen single-BPM grid and neither closes BUG-065. The evidence layer has no headroom left: only ~15–25 % of detected onsets from ANY band or stem land within ±50 ms of a beat, so a tracker fed an onset flag cannot be tuned into tightness. BUG-065 stays open and bounded; PHOSPHENE_BEAT_PLL stays default-off. The next beat-sync session opens phase DBN. Do not reopen TRK without a changed premise about the GRID, not the tracker.

Phase CNF — Confidence and graded degradation (3–4 sessions, after DBN + RLG.0/TRK signals exist)

CNF.1 — Confidence fusion + FeatureVector plumbing. Fuse into beatConfidence01 + tempoStability01: DBN posterior margin, RLG window-agreement rate (streaming), TRK onset-match rate, the existing D-154 grid-vs-drums disagreement. Float-budget audit first — pads through float 48 are consumed (TONAL); options: reclaim remaining pads if any, retire a dead field, or extend the vector (GPU contract change, both MSL mirrors, goldens) — DECISION D-D with the audit table in hand. Logged to features.csv regardless of plumbing choice. Done-when: confidence traces on the benchmark catalog separate suites 1–4 from Clair de Lune cleanly (ROC-style table in the closeout).

CNF.2 — D-154 evolves: binary gate → graded scaling. requiresRegularBeat presets keep the hard exclusion as the floor; beat-coupled presets gain confidence-scaled accent amplitude (per-preset opt-in, M7-gated, 2 rounds max per the PHYS escalation rule — preset increments never bundled with engine increments). Done-when: one pilot preset (Matt picks; Glaze or FFO are natural) reads correctly on a mixed playlist spanning suites 1 and 5.

CNF.3 — Rubato validation. Ipanema tracked softly (suite-5a target); Clair de Lune sessions show near-zero confident-wrong rate with visuals carried by energy/spectral/TONAL layers. Explicit anti-goal restated in the closeout: no beat pulse was faked. Done-when: suite-5 table green; M7 on both tracks.

Phase MDL — Model headroom, measured (1–2 sessions, optional, any time after GT.3)

MDL.1 — final0 offline A/B. Vendor Beat This! final0 (20.3 M params / 81 MB vs small0's 2.1 M / 8.4 MB), same conversion pipeline (Scripts/convert_beatthis_weights.py), benchmark A/B on all suites, offline prep only. Expected leverage: suites 2 and 4. Adopt only if deltas justify the weight size + prep latency (DECISION D-E); prep budget re-measured against the PREP parallelization wins. Done-when: A/B table; decision recorded.

5. Decision points (Matt), in order of arrival
ID	Decision	Arrives	Default recommendation
D-A	Ratify program: phases, naming, targets table	Now (this doc)	GO as written
D-B	Finalize per-suite numeric targets	After GT.3 baseline	Adjust to "meaningful delta over baseline," keep suite-1 bar absolute
D-C	RLG GO/NO-GO + the GO bar itself	After RLG.0	Bar as written in RLG.0
D-F	grid_bpm semantics under piecewise grids	DBN.4	Instantaneous-at-playhead (visuals should follow the current tempo)
D-D	FeatureVector budget route for confidence floats	CNF.1 audit	Whichever avoids a GPU contract change if a pad exists; else extend deliberately
D-E	Adopt final0 offline	MDL.1	RESOLVED as D-208 (2026-07-31): NOT adopted. 2/6 meter correct for both variants, degeneracy ratio 0.494 -> 0.475, bleed regresses, at 10x weights. Corollary: the evidence ceiling is not a capacity problem.
6. New Claude Code skills (authored in SK.1)

Four new skills + three edits. Rationale: every increment above will be run as a fresh Claude Code session from a session prompt; the skills are what keep 25+ sessions from re-deriving (or violating) the project's hard-won constraints. Specs below are the authoring contract for SK.1.

6.1 beat-sync-session (new — the mandatory opener)
Trigger description: "Invoke BEFORE any work on a dsp.beat increment — BeatDetector, BeatGridResolver/decoder, LiveBeatDriftTracker, RollingBeatTracker, BeatPulseClock, BeatGrid, or any BUG with domain tag dsp.beat. Covers the beat-sync constraint set, the banned approach families, and the benchmark obligation."
Content outline: (1) The constraint set verbatim: D-004 hierarchy, Cold-Start Phase Contract + FA #69 scope (what "short-window cold-start" bans and what steady-state tracking it does NOT ban), FA #68, D-075, the halving-only octave rule (BUG-009/D-079). (2) The dead-end map: one-table summary of the six cold-start iterations + FBS Stage-1 verdict with links to HISTORICAL_DEAD_ENDS.md — "if your idea resembles a row here, stop and say so." (3) The benchmark obligation: before/after BeatBench runs are part of done-when for any behavioral change; category-win claim rules. (4) The five-iteration stop rule and evidence-before-fix (defers to defect-handling for BUG-* work). (5) Pointer map: ARCHITECTURE.md §Audio Analysis, BEAT_SYNC.md capability registry, KNOWN_ISSUES dsp.beat entries, this plan.
6.2 beatbench (new — the measurement skill)
Trigger description: "Invoke when running, extending, or interpreting the BeatBench beat-sync benchmark — baseline captures, A/B comparisons, category-win claims, ground-truth or fixture changes."
Content outline: (1) Harness invocations (offline-grid mode, session-replay mode, live-capture mode) + fixture-dir env setup. (2) Metric definitions with the exact windows (F @±70 ms, Cemgil, CMLt/AMLt, downbeat F, phase-error-vs-time percentiles, time-to-lock, confident-wrong rate). (3) The five suites and their track lists. (4) Claim rules: what table must appear in a closeout; no cherry-picking windows; regressions on any suite are reported even when the target suite improves. (5) Ground-truth maintenance: how taps were captured, latency calibration, how to add a track (tap protocol + reconciliation), never editing groundtruth JSON by hand.
Kept separate from beat-sync-session so preset/UX increments that merely cite sync numbers load only this one.
6.3 reference-port (new — porting algorithms from papers/reference implementations)
Trigger description: "Invoke before implementing any algorithm from a paper or external reference implementation (DSP, ML, decoding). Covers license gates, spec-fidelity discipline, and activation-level verification."
Content outline: (1) License gates: MIT/BSD code portable with attribution; AGPL never (TempoCNN precedent); CC-NC model weights never ship (madmom models); annotation-tool use of restricted tools is fine offline. (2) Spec fidelity: the BeatNet paraphrased-spec-drift failure and the D-077 pivot as the cautionary case; every constant in a port carries a source citation or an explicit "our tunable" marker; no paraphrasing formulas from memory — cite the paper equation. (3) Verification methodology: the DSP.2 S8 pattern — dump reference-implementation activations (BeatThisActivationDumper precedent), commit as fixtures, layer/stage-match tests that fail loud on missing fixtures (QR.3 doctrine). (4) When a reference exists in Python: build the tools/ venv cross-check first, port second.
6.4 session-forensics (new — working with recorded sessions and diagnostic CLIs)
Trigger description: "Invoke when analyzing recorded Phosphene sessions (features.csv, stems.csv, raw_tap.wav, session.log) or choosing/using the diagnostic CLIs. Enforces replay-before-live."
Content outline: (1) Session directory anatomy + the columns that matter for beat work (drift_ms, lock_state, grid_bpm, beat phase, pulse columns). (2) CLI inventory with one-line invocations: TempoDumpRunner, ColdStartVerifier (+ its modes), PresetSessionReplay, BeatThisActivationDumper, BeatBench (once it exists), and which question each answers. (3) The replay-before-live rule: any tracker/decoder change is validated against recorded sessions before requesting a live capture or M7 — live captures and Matt's review time are the scarce resource. (4) Capture request protocol: what to ask Matt to record, naming, where sessions land.
6.5 Edits to existing skills
closeout: add a dsp.beat clause — closeouts for beat-sync increments must include the BeatBench before/after table (all five suites, not just the target suite) or an explicit "no behavioral change" statement.
defect-handling: add a pointer — dsp.beat defects use BeatBench as the evidence substrate for the evidence-before-implementation step; reference beat-sync-session for the constraint set.
session-prompt-author: no structural change; add the program's phase prefixes (GT/DBN/FT/RLG/TRK/CNF/MDL) to its increment-naming examples so prompts inherit them.
7. Risk register and stop rules
Risk	Guard
RLG becomes cold-start dead-end iteration #7	RLG.0 research gate with a pre-agreed numeric GO bar; steady-state-only framing; max 2 study iterations then NO-GO
DBN decoder regresses baseline 4/4 while chasing odd meters	Suite-1 no-regression is a hard gate in DBN.3; peak-pick path retained one increment for A/B
Piecewise grid breaks grid_bpm consumers silently	DBN.4 consumer audit table is a done-when artifact; goldens regenerated deliberately, never quietly
Benchmark ground truth is itself wrong (the BSAudit verifier lesson)	Taps + independent tool cross-check + reconciliation-by-ear; disagreements are data, not noise
Confidence floats force a rushed GPU contract change	CNF.1 audit-first with D-D decision before any struct edit
Program sprawl / lost context across 25+ Claude Code sessions	Every session opens with beat-sync-session; every increment maps to exactly one plan item; ENGINEERING_PLAN.md is updated per-increment per house convention
M7 bottleneck (Matt's review time)	Replay-first validation everywhere; M7 requested only at phase-validation increments (DBN.3, FT.2, RLG.3, TRK.3, CNF.2/3)

Program-wide stop rule: two failed validation attempts on the same premise within any increment → stop, write findings, surface a DECISION-NEEDED. No third attempt without Matt's sign-off on a changed premise.

8. Session budget and suggested running order
Phase	Sessions	Notes
SK.1	1	First — everything after benefits
GT.1–3	3–4	+~40 min Matt taps; blocks all claims
DBN.1–4	5–7	Workstream A
TRK.1–3	3–4	Workstream B (parallel with DBN)
RLG.0	2–3	Workstream C (parallel); GO/NO-GO
FT.1–2	2–3	After DBN.4
RLG.1–3	4–6	GO only
CNF.1–3	3–4	After DBN + RLG.0/TRK
MDL.1	1–2	Optional, opportunistic
Total	~24–34	RLG NO-GO saves 4–6

Suggested first six sessions: SK.1 → GT.1 → GT.2 → GT.3 → DBN.1 + RLG.0-part-1 → TRK.1-replay. By session six there are numbers on the board for every category and the two riskiest questions (window agreement, controller convergence) have empirical answers.

9. What this plan deliberately does not do
No changes to cold-start phase acquisition (contract stands; BeatPulseClock remains the bridge; RLG.2's handoff joins it, does not replace it).
No promotion of beats to primary visual driver (D-004).
No re-tuning of validated audio constants (AGC, band edges, cooldowns) except where an increment's spec names them.
No BeatNet revival, no TempoCNN (AGPL), no Sound Analysis framework (all previously rejected).
No new ML training. Fine-tuning Beat This! on failure categories is a possible future program, out of scope here.

On ratification (D-A): add a DECISIONS.md entry recording the program + this doc as its spec; transcribe phase stubs into ENGINEERING_PLAN.md; author SK.1 session prompt via session-prompt-author.