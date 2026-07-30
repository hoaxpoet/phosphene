# Increment TRK.2 — Beat-drift evidence upgrade: drums-stem onsets

**Type:** fix (BUG-065, domain `dsp.beat`) · beat-sync program (D-202)

**Objective.** After this session the live beat-drift tracker matches against **drums-stem onsets** once live stems stabilise, instead of raw sub-bass flux, with sub-bass retained as the pre-stem and fallback evidence. This exists so the drift controller integrates *beat* evidence rather than *bassline* events — the reason the TRK.1 period controller failed validation. TRK.2 is an **evidence** change; whether the TRK.1 controller is then enabled is a separate, later decision.

---

## 1. Why this increment exists (read this first — it is the whole premise)

TRK.1 (commit `07dd3bd9`) proved the root cause of BUG-065 and then **failed validation**. Both halves matter:

**Proven.** The drift is a *ramp*, not noise — linear fit **−1.493 ms/s at R² = 0.844** on session `2026-07-30T15-39-21Z`, with `grid_bpm` constant at 80.45. The BPM is right; the phase slips, implying a **0.149 %** period error (0.12 BPM). The legacy tracker is a first-order EMA on phase error — a proportional-only controller, which has zero steady-state error against a *step* but **constant error against a ramp**. It can bound drift, never null it. That is exactly BUG-065's "bounds without tightening", and it is why a period term is required.

**Failed.** The type-2 (PI) controller was implemented behind `PHOSPHENE_BEAT_PLL` and **regressed real data badly**: `LiveDriftValidationTests` (loveRehab) went to maxAbsDrift **101.5 ms** (limit 50) and beat alignment **0.05** (limit 0.80). A synthetic once-per-beat ramp suite said "improved" (12 → 9 ms) — it could not exhibit the failure. The period term integrates noisy sub-bass onsets into a runaway.

**The changed premise (this increment).** Sub-bass onsets are **events, not beats** — FA #68, and they fire on bassline notes and 808s, off-beat on syncopated material. An integrating loop fed that signal integrates the wrong thing. Do not retune gains against sub-bass; change the evidence. One failed validation attempt is already logged against the gain-tuning premise (beat-sync two-strikes rule).

---

## 2. Skill invocations

| When | Skill |
|---|---|
| Before any code change (this is BUG-* work) | `defect-handling` |
| Before touching any beat-path code — mandatory opener | `beat-sync-session` |
| Before interpreting or claiming any benchmark number | `beatbench` |
| When replaying recorded sessions / choosing a CLI | `session-forensics` |
| At the end, before committing | `closeout` |

---

## 3. Read-first (exact paths, in order)

1. `docs/BEAT_SYNC_PROGRAM_PLAN.md` — **§TRK.2 only** (line ~103) plus §1 suite table
2. `docs/QUALITY/KNOWN_ISSUES.md` — BUG-065 entry, including the 2026-07-30 evidence block
3. `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — `processOnsetLocked`, `applyPeriodControllerLocked`, `advanceDriftPerFrameLocked`, and the tunables block
4. `PhospheneEngine/Sources/DSP/MIRPipeline.swift` — the tracker's owner and per-frame driver (the integration point for stem evidence)
5. `PhospheneEngine/Tests/PhospheneEngineTests/Integration/LiveDriftValidationTests.swift` — the real-fixture replay gate that caught TRK.1
6. `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatDriftRampTrackingTests.swift` — read the header scope note; it documents why the synthetic suite is not a closure gate

---

## 4. Pre-flight invariants (a failed check stops the session)

- `git log --oneline -1` on `main` is `07dd3bd9` or later; working tree clean.
- `swiftlint lint --strict --config .swiftlint.yml` → **0 violations**.
- `swift test --package-path PhospheneEngine` → green with `PHOSPHENE_BEAT_PLL` **unset** (legacy path untouched; 205 DSP/beat tests pass).
- `PHOSPHENE_BEAT_PLL=1 swift test --package-path PhospheneEngine --filter LiveDriftValidation` → **fails** (maxAbsDrift ~101 ms). This failure is the TRK.1 finding and must still reproduce; if it does not, stop — the premise has changed.
- BeatBench fixtures present at `~/phosphene_beatbench_fixtures` (13 files incl. `bleed.wav`, the category-4 case).

---

## 5. Tasks

1. **Confirm the evidence gap before changing anything.** Using a recorded session with stems (`2026-07-30T15-39-21Z` has `stems.csv`), measure how sub-bass onsets and drums-stem onsets each align to the cached grid. **Done-when:** a printed comparison exists showing, for the same capture, per-onset |offset-to-nearest-grid-beat| distributions for both sources. If drums-stem onsets are *not* measurably better aligned, **stop and report** — TRK.2's premise is unproven and the increment should not proceed.

2. **Plumb drums-stem onsets to the tracker.** Extend the tracker's update path to accept a drums-stem onset alongside the existing sub-bass onset, and drive it from `MIRPipeline`. Sub-bass remains the pre-stem and fallback source. **Done-when:** the tracker compiles with both evidence sources, legacy behaviour is byte-identical when no stem onset is supplied, and a unit test asserts that identity.

3. **Crossfade on stem availability.** Switch evidence when live stems stabilise (~10 s), mirroring the stem pipeline's own live handoff rather than inventing a second timing rule. **Done-when:** a test drives the handoff and asserts no discontinuity in `drift` across the switch.

4. **Replay validation — the real gate.** Re-run `LiveDriftValidationTests` and the recorded-session replays with drums-stem evidence, flag **off** and **on**. **Done-when:** a before/after table exists for both flag states. **Hard stop:** if the flag-on path still regresses the real fixture, do **not** tune gains — write findings and stop; that is the second strike on the controller premise and needs Matt's sign-off on a changed premise.

5. **BeatBench table.** Per the benchmark obligation, produce a before/after table across all five suites, or an explicit "no behavioural change ships" statement if the flag stays default-off. **Done-when:** the table (or the statement) is in the closeout. Load the `beatbench` skill first — no category is claimed won without a number, and regressions are reported even when the target suite improves.

---

## 6. Do NOT

- **Do not enable `PHOSPHENE_BEAT_PLL` by default.** It regresses real data today. Runtime behaviour ships flagged with a one-increment A/B (program house rule §4).
- **Do not tune the PI gains against sub-bass evidence.** That premise already has one failed validation attempt; a second without a changed premise violates the two-strikes rule.
- **Do not fuse onset bands.** Drums-stem onsets are a *separate detector instance*, not a fused band (D-075). Tempo/IOI stays sub-bass-only.
- **Do not touch cold-start phase.** This is steady-state mid-track convergence. Short-window cold-start phase derivation is retired (Cold-Start Phase Contract, FA #69) and out of scope.
- **Do not treat `BeatDriftRampTrackingTests` as a closure gate.** It cannot exhibit the live failure; it is a controller-property test only.
- **Do not promote beats to primary motion** (D-004) — this improves an accent-layer signal.
- **Do not request a live capture or M7** in this increment. Replay-first; live validation is TRK.3.

---

## 7. Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
PHOSPHENE_BEAT_PLL=1 swift test --package-path PhospheneEngine --filter "Beat|Drift" 2>&1
```

---

## 8. Commit messages

Format `[TRK.2] <component>: <description>`; small commits per logical step (evidence measurement → plumbing → crossfade → validation). Local-only; **push only on Matt's explicit "yes, push"**.

---

## 9. Closeout

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- the task-1 onset-alignment comparison (sub-bass vs drums-stem),
- the flag-off / flag-on replay table from task 4,
- the BeatBench table or the explicit no-behavioural-change statement,
- BUG-065 status stated from the **KNOWN_ISSUES row**, not from narrative recall.

---

## 10. DECISION-NEEDED (only if task 4's hard stop fires)

**Question:** the drift controller still misbehaves on real captures after the evidence upgrade — how do you want to spend the next session?

- **Take the full decoder path (DBN).** Replaces the frozen single-BPM grid premise rather than patching the tracker around it. Biggest fix, several sessions, and it is what the program says solves categories 2–4.
- **Ship the evidence upgrade alone, leave drift bounded.** Beat-locked presets keep feeling slightly loose late in a track, but nothing regresses and the work banks.
- **Park BUG-065.** It is a P3 that caps tightness rather than breaking anything; spend the time on presets instead.

**Recommendation:** ship the evidence upgrade alone, then decide on DBN with its numbers in hand.
**Default if no reply:** ship the evidence upgrade, leave the flag off, and park the controller.
