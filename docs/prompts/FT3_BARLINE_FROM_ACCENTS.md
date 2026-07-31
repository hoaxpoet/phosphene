# Increment FT.3 — Bar position from beat-synchronous accents (local files)

**Type:** engine (DSP) · beat-sync program (D-202), phase FT

**Objective.** After this session the engine can derive `beatsPerBar` **and the bar-line
phase** for a local file from beat-synchronous accent features, with a decline path, validated
against ground truth on tracks that were not used to design it. This is the changed premise
D-208 asked for: the bar is recovered from the audio at the known beat times, **not** from
Beat This!'s downbeat activation stream.

---

## 1. Why this exists — and the one number that justifies it

Four independent levers failed to get bar position out of the downbeat activations: a
different onset source (TRK.2, D-206), an unbiased decoder (DBN.2), a 10× larger model
(MDL.1, D-208), and 13–25× more context (FT.1). D-208 concluded the evidence is thin.

**It is thin in that stream, not in the audio.** The bar-line probe
(`docs/diagnostics/BARLINE_PROBE_2026-07-31.md`, `tools/barline_probe.py`) scored **6 / 6**
on the ground-truthed catalogue against **2 / 6** for both the incumbent resolver and the
DBN.2 decoder — recovering all three odd meters (money 7, solsbury_hill 7, take_five 5) that
every prior lever missed.

The premise change is that **beats are already good** (suite-1 F 0.97), so on a local file the
problem is not "find the metrical structure" but "given 400–1000 reliable beat times, which of
them are bar lines" — a periodicity-and-phase search over a tiny integer space.

**Read the probe doc's three caveats before writing any code.** They are the shape of this
increment: the meter-set restriction was made after seeing results, the margins are wildly
uneven, no single feature works alone, and **phase was never measured at all**.

---

## 2. Skill invocations

| When | Skill |
|---|---|
| Before any beat-path work — mandatory opener | `beat-sync-session` |
| Before quoting or claiming any benchmark number | `beatbench` |
| At the end, before committing | `closeout` |

Not a port — the method is ours, so `reference-port` does not apply. If a published accent /
metrical-salience method is adopted mid-session, load it then and take the license gate.

---

## 3. Read-first (exact paths, in order)

1. `docs/diagnostics/BARLINE_PROBE_2026-07-31.md` — **the whole basis for this increment**,
   including the caveats that define its tasks
2. `tools/barline_probe.py` — the reference implementation of the statistic and the
   permutation null; the Swift port must reproduce its numbers
3. `docs/DECISIONS.md` — **D-208** (+ its FT.1 amendment: why the downbeat stream is out),
   **D-207** (meter set fixed at {3,4,5,7}; decoder declines when unsure), **D-170** (the
   local-file-only scope limit that sank section detection)
4. `PhospheneEngine/Sources/DSP/BeatGridResolver.swift` — where `beatsPerBar` is set today
   (`round(median_downbeat_IOI / beat_period)`), which this replaces for local files
5. `PhospheneEngine/Sources/ML/BeatThisTiledInference.swift` — FT.1's full-track tiler, the
   source of the beat times this consumes
6. `PhospheneEngine/Tests/PhospheneEngineTests/ML/FullTrackMeterTests.swift` — the
   `PHOSPHENE_BEATS_DUMP` hook that produced the probe's input

---

## 4. Pre-flight invariants (a failed check stops the session)

- `git log --oneline -1` on `main` is `7dc822e6` or later; working tree clean.
- `swiftlint lint --strict --config .swiftlint.yml` → **0 violations**.
- `swift test --package-path PhospheneEngine` → green (1717+ tests).
- `Scripts/closeout_evidence.sh` reports `lintscripts=0` — the CI-parity step exists (CI.1).
- Ground truth present at `PhospheneEngine/Tests/Fixtures/beatbench/groundtruth/` and fixtures
  at `~/phosphene_beatbench_fixtures`.
- **The probe reproduces 6/6** before anything is ported. If it does not, the basis has moved —
  stop and re-measure rather than porting a number that no longer holds.

---

## 5. Tasks

1. **Re-establish the result on tracks that did not design it.** The probe's meter-set
   restriction to {3,4,5,7} was made *after* seeing the first table, which is exactly how a
   result gets tuned into existence. Re-run the probe on **`so_what`, `around_the_world`,
   `stayin_alive`, `superstition`, `there_there`, `girl_from_ipanema`, `giorgio_by_moroder`,
   `dance_yrself_clean`** — none of which have ground truth yet, so score what you can by ear
   or by their published meters and treat disagreements as data, not failures.
   **Done-when:** a table for the unseen tracks exists. **Hard stop:** if the method's accuracy
   on unseen tracks is materially worse than 6/6, say so plainly and stop — that is the
   result, and porting it anyway would be building on a tuned number.

2. **Measure PHASE, not just meter.** The probe never checked *which* beat is the bar line. A
   correct meter on the wrong phase is visually identical to being wrong. Score the chosen
   phase against the ground-truth downbeat times (`downbeats_s` in the groundtruth JSON).
   **Done-when:** a per-track phase-accuracy column exists alongside meter. **If phase is
   wrong where meter is right, that is the headline finding of this increment** — report it as
   such rather than proceeding to port.

3. **Design the combination rule, and defend it against the DBN.2 failure mode.** `low_energy`
   and `flux` each get 4/6 but *different* fours. Whatever combines them — max, vote, weighted
   sum, per-feature z-score then max — must be checked for a bias that scales with meter,
   because that is exactly what derailed DBN.2 twice (D-208 §9.6/§9.7). **Done-when:** the rule
   is stated, and a synthetic test shows a feature set with **no** bar information scores every
   meter equally under it.

4. **Port to Swift as `BarLineEstimator` (DSP).** Input: beat times + the decoded audio.
   Output: `beatsPerBar`, bar-line phase, per-meter margin, and a **decline** flag — matching
   D-207's contract that the result is "a meter *or* no confident bar". Pure Swift + Accelerate,
   offline path only. **Done-when:** the Swift implementation reproduces the Python probe's
   per-track margins to within 1e-3 on all 9 ground-truthed tracks. That parity check is the
   gate; a re-derivation that "looks right" is not acceptable (the D-077 lesson).

5. **Set the decline threshold from the margin distribution.** Solsbury Hill's +0.052 and
   Bohemian's +0.133 are thin, so a threshold that keeps them may admit noise, and one that
   excludes noise may refuse them. Report the distribution and the operating point, and state
   plainly if correct and incorrect margins overlap — DBN.2's did, and pretending otherwise is
   worse than declining. **Done-when:** threshold set from data with the overlap characterised.

6. **BeatBench A/B, local path.** Compare `beatsPerBar` correctness and downbeat F against the
   incumbent resolver on all ground-truthed tracks, per the `beatbench` skill: no category
   claimed won without a number, regressions reported even when the target improves.
   **Done-when:** the before/after table is in the closeout.

7. **Do NOT wire it into playback.** Integration is FT.2's territory and needs its own
   re-scope. FT.3 delivers the estimator and its evidence; nothing changes what the user sees.

---

## 6. Do NOT

- **Do not touch the downbeat activation stream.** Four levers have failed there (D-208); this
  increment exists precisely because the bar is elsewhere.
- **Do not widen the meter set** beyond D-207's {3,4,5,7} — that is a product decision, and the
  probe already showed that admitting 2 lets a sub-bar periodicity win.
- **Do not wire into `BeatGridResolver` or playback.** FT.2, after its re-scope.
- **Do not claim a category win without a BeatBench number** (`beatbench` skill).
- **Do not tune on the ground-truthed nine and report that as accuracy.** Task 1's unseen
  tracks are the honest measure; the nine designed the method.
- **Do not promote beats to primary motion** (D-004) — this improves an accent-layer signal.
- **Do not attempt streaming.** Structurally local-file-only; see §8.

---

## 7. Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
swift test --package-path PhospheneEngine 2>&1
Scripts/closeout_evidence.sh
```

Plus the probe parity check:

```
~/phosphene-ml-env/bin/python tools/barline_probe.py \
  --beats-dir /tmp/barprobe --fixtures ~/phosphene_beatbench_fixtures
swift test --package-path PhospheneEngine --filter BarLineEstimator
```

---

## 8. Commit messages

Format `[FT.3] <component>: <description>`; small commits per logical step (unseen-track
re-measure → phase measurement → combination rule → Swift port + parity → threshold → A/B).
Local-only; **push only on Matt's explicit "yes, push"**.

---

## 9. Closeout

Invoke the `closeout` skill; 8-part report with the verbatim `Scripts/closeout_evidence.sh`
block as §2. Increment-specific additions:

- the **unseen-track table** from task 1, and an explicit statement of how it compares to the
  6/6 that was measured on the designing set;
- the **phase-accuracy column** from task 2;
- the **combination rule** and its no-bar-information control from task 3;
- the **Python↔Swift parity numbers** from task 4;
- the **margin distribution + overlap characterisation** from task 5;
- the **BeatBench A/B table** from task 6;
- BUG/decision status stated from the **authoritative row**, not narrative recall.

---

## 10. DECISION-NEEDED

**Question:** this can only ever help local files. Is that worth building?

The method needs the whole track. Streaming — Phosphene's primary path — exposes a 30 s
preview before playback, and no version of this changes that. **That is the exact property
that got section detection removed** (D-170: *"structurally local-file-only… the feature could
only ever serve local-file playback, and no detector, supervised or not, changes that"*).

The difference from D-170 is the second half of its reasoning: section detection was *also*
below the perceptual bar on local files (F@3 ≈ 0.29–0.41). This is 6/6 on meter, against 2/6
for everything shipped. But the scope limit is identical, so the same question applies.

- **Build it (FT.3 as specified).** Local-file playback gets correct bar position on odd-meter
  and ambiguous material, so Nacre's and Glaze's downbeat pushes land on the real bar-1 instead
  of an arbitrary beat. Streaming is unchanged — it keeps declining, per D-207.
- **Build only the measurement, not the engine component.** Finish tasks 1–3 (unseen tracks,
  phase, combination rule) so the finding is properly established and recorded, and stop before
  the Swift port. Cheaper, and leaves a real result banked if beat-sync is later revisited.
- **Don't.** Beat-sync has absorbed a lot of sessions for four negatives; a local-file-only
  win may not be where the next effort belongs, and presets are the visible surface.

**Recommendation: build only the measurement (tasks 1–3), then re-decide.** Task 1 is the one
that matters — the 6/6 was measured on the same nine tracks that shaped the method, and until
it survives unseen tracks the case for the port is not made. That is one session, and it either
justifies the engine work or saves it.

**Default if unanswered:** run tasks 1–3, stop before the port, and bring the numbers back.
