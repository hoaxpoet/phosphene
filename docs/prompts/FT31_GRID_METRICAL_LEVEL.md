# Increment FT.3.1 — Is the grid on the right metrical level, and can we tell without ground truth?

**Type:** engine (DSP) · beat-sync program (D-202), phase FT
**Supersedes** the unbuilt half of [`FT3_BARLINE_FROM_ACCENTS.md`](FT3_BARLINE_FROM_ACCENTS.md) (its tasks 4–7,
the Swift port). That prompt's tasks 1–3 landed; this is the re-scope its task-2 result forced.

**Objective.** After this session we know whether a wrong metrical level — a grid running at
double or half the beat a listener would tap — is detectable **without ground truth**, and we
have a measured detector with a decline path, or a documented negative saying it is not
recoverable from the signals we have. Nothing changes what the user sees.

**ID note:** `FT.3.1`, not a re-used `FT.3`, because FT.3's tasks 1–3 already landed as
`d24d1163` / `de2c126a`. Reusing the bare ID would make those commits ambiguous under
`git bisect`. Say the word if you'd rather this be `FT.4`.

---

## 1. Why this exists — and why it is not a fifth swing at the same premise

FT.3 tasks 1–3 found the bar's **meter** on 6/6 ground-truthed and 8/8 unseen tracks, and
its **phase** on only 3/6. The two clean phase failures are `money` and `bleed`, and the
reason is not the accent method:

| track | truth BPM | grid BPM | grid/truth | CMLt | AMLt | **gap** | FT.3 phase |
|---|---|---|---|---|---|---|---|
| billie_jean | 117.44 | 116.88 | 1.00 | 0.97 | 0.97 | 0.00 | 100 % ✓ |
| take_five | 167.07 | 169.24 | 1.01 | 1.00 | 1.00 | 0.00 | 85 % ✓ |
| solsbury_hill | 102.44 | 102.68 | 1.00 | 1.00 | 1.00 | 0.00 | 14 % (GT suspect) |
| **money** | 60.97 | 116.19 | **1.91** | **0.00** | **0.88** | **0.88** | **0 %** |
| **bleed** | 226.72 | 115.00 | **0.51** | **0.03** | **0.84** | **0.81** | **16 %** |

Source: [`docs/diagnostics/BEATBENCH_BASELINE_2026-07-30.md`](../diagnostics/BEATBENCH_BASELINE_2026-07-30.md)
(CMLt/AMLt) and [`docs/diagnostics/FT3_BARLINE_TASKS_1_3_2026-07-31.md`](../diagnostics/FT3_BARLINE_TASKS_1_3_2026-07-31.md) (phase).

**The two tracks with a large AMLt−CMLt gap are exactly the two tracks where phase failed.**
AMLt accepts double/half readings and CMLt does not, so the gap already *names* a wrong
metrical level — offline, against ground truth. That is the changed premise: this is not
another attempt to read the bar out of a stream that has been shown four times not to carry
it (D-208). It is a different question about a different object, and BeatBench already
answers it where ground truth exists. **The open question is only whether it can be answered
blind.**

### The one fact that rules out the obvious fix

`BeatGrid.halvingThresholdBPM = 175`, halving-only; sub-80 doubling was deleted at QR.1
(BUG-009 — see `PhospheneEngine/Sources/DSP/BeatGrid.swift:162-191`). Look at what the two
failures need:

- **money** grid 116.19, wants **halving** to ~58.
- **bleed** grid 115.00, wants **doubling** to ~230.

Same BPM, opposite corrections. **No global BPM threshold can separate them**, and moving the
175 threshold down re-opens BUG-009 (fast rock at 158–174 halved to a half-rate visual pulse).
Whatever decides the level has to come from the audio content, not the tempo number. That is
the whole engineering content of this increment.

---

## 2. Skill invocations

| When | Skill |
|---|---|
| Before any beat-path work — mandatory opener | `beat-sync-session` |
| Before quoting, extending, or interpreting any BeatBench number | `beatbench` |
| At the end, before committing | `closeout` |

If a published metrical-level / tempo-octave method is adopted mid-session, load
`reference-port` at that point and take its license gate.

---

## 3. Read-first (exact paths, in order)

1. [`docs/diagnostics/FT3_BARLINE_TASKS_1_3_2026-07-31.md`](../diagnostics/FT3_BARLINE_TASKS_1_3_2026-07-31.md) — the finding that produced this increment; §"Why: the grid's beat is not the ground truth's beat"
2. [`docs/diagnostics/BEATBENCH_BASELINE_2026-07-30.md`](../diagnostics/BEATBENCH_BASELINE_2026-07-30.md) — the per-track CMLt/AMLt table; it is the label set
3. `PhospheneEngine/Sources/DSP/BeatGrid.swift:150-195` — `halvingThresholdBPM`, and the BUG-009 rationale for 175
4. `PhospheneEngine/Sources/DSP/BeatDetector+Tempo.swift:180-270` — the two halving sites that share that threshold (PUB.2)
5. `PhospheneEngine/Sources/BeatBench/Metrics.swift` — CMLt/AMLt as implemented; the `beatbench` skill for the windows
6. `docs/DECISIONS.md` — **D-205** (gate on AMLt not CMLt; *and* meter/downbeat is a hard gate — this increment is where those two collide), **D-207** (decline when unsure), **D-208** + FT.1 amendment (why the activation stream is out)

---

## 4. Pre-flight invariants (a failed check stops the session)

- Working tree clean; branched from a commit containing `de2c126a` (FT.3 tasks 1–3).
- `swiftlint lint --strict --config .swiftlint.yml` → **0 violations**.
- `swift test --package-path PhospheneEngine` → green (1717+ tests).
- `Scripts/closeout_evidence.sh` reports `lintscripts=0`.
- In a worktree: `Scripts/link_fixtures.sh` **and** `git lfs checkout` (the Beat This! weights
  arrive as ~128 B LFS pointers and fail with `BeatThisWeightError error 4`).
- `swift run BeatBench --self-test` passes, and `--mode offline-grid` reproduces the CMLt/AMLt
  column in the table above. **If it does not, the label set has moved — stop and re-measure
  rather than building a detector against a stale baseline.**

---

## 5. Tasks

1. **Establish the label set, and state how small it is.** From the BeatBench baseline: wrong
   level = {money, bleed}; right level = {billie_jean, take_five, solsbury_hill}; the rest
   (pyramid_song, yyz, bohemian_rhapsody, clair_de_lune) have no clean label because their
   CMLt is low for other reasons. **That is 2 positives and 3 negatives.** Any detector can be
   fitted to 2 positives, which is the exact failure this increment exists because of.
   **Done-when:** the label table exists with each track's inclusion or exclusion justified
   from its CMLt/AMLt, not from convenience.

2. **Build the synthetic control FIRST, before any detector.** Resample or re-grid a
   known-good track (billie_jean, take_five) to deliberately wrong levels — 2×, ½×, and as a
   negative control, unchanged — to get an unlimited supply of labelled cases the detector was
   not fitted to. **Done-when:** a generator exists and produces cases whose true level is
   known by construction. **This lands before task 3.** A detector measured only on 2 real
   positives is not measured.

3. **Determine whether the level is recoverable blind.** Candidate evidence, in rough order of
   how much the FT.3 data already supports it: beat-synchronous accent contrast at the
   candidate level vs its double/half (FT.3's own features already discriminate at 2× — that
   is *why* meter search tolerated the wrong level and phase did not); inter-onset-interval
   histogram structure; the ratio of accent energy on odd vs even beats (a half-time grid
   should show strong alternation, a double-time grid weak). Report what each achieves on the
   synthetic set **and** on the 5 real labels, separately. **Done-when:** a per-signal table
   exists over both sets. **Hard stop:** if nothing separates the synthetic 2× and ½× cases,
   say so plainly and stop — that is the result, and it is worth having.

4. **If task 3 separates: implement the detector with a decline path.** Output is
   `atNotatedLevel` / `atWrongLevel(factor:)` / `undetermined` — never a silent correction.
   Pure Swift + Accelerate, offline path only, no wiring. **Done-when:** it reproduces task 3's
   numbers, and `undetermined` is reachable and exercised by a test.

5. **Report the confusion matrix and the overlap, on both sets.** State plainly if the
   detector's confident-correct and confident-wrong scores overlap. DBN.2's did; FT.3 found
   the probe's own rule carried a meter-scaling bias nobody had checked for. **Done-when:**
   the matrix and the operating point are in the closeout, with overlap characterised.

6. **BeatBench, all five suites.** Even though nothing is wired, report whether the detector's
   verdict agrees with each track's AMLt−CMLt gap across the full benchmark, per the
   `beatbench` skill — no category claimed won without a number, regressions reported even
   where the target improves. **Done-when:** the five-suite table is in the closeout.

7. **Do NOT wire it into `BeatGridResolver`, `BeatDetector`, or playback.** No grid is
   corrected, no threshold is moved, nothing the user sees changes. Acting on the verdict is
   the next increment's decision and needs the §10 answer first.

---

## 6. Do NOT

- **Do not move `BeatGrid.halvingThresholdBPM`, and do not reintroduce sub-80 doubling.**
  Halving-only is a deliberate design (QR.1, BUG-009); money and bleed need opposite
  corrections at the same BPM, so a threshold change cannot be the fix and would regress
  fast rock. If the finding says doubling is needed, that is a DECISION-NEEDED, not a
  unilateral change.
- **Do not touch the downbeat activation stream.** Four levers failed there (D-208).
- **Do not re-open FT.3's port.** The bar-line estimator is blocked on this question, not the
  other way round.
- **Do not hand-edit any groundtruth JSON** (`beatbench` skill). `solsbury_hill`'s appears
  internally inconsistent — `meter_from_taps: 7` with downbeat taps ~12 tapped beats apart —
  and that goes to Matt as a ground-truth question, not a fix.
- **Do not tune on the 2 real positives and report that as accuracy.** Task 2's synthetic set
  is the honest measure.
- **Do not promote beats to primary motion** (D-004).
- **Two-strikes rule applies** (`beat-sync-session` §4): two failed validation attempts on the
  same premise → stop, write findings, surface a DECISION-NEEDED.

---

## 7. Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
swift test --package-path PhospheneEngine 2>&1
Scripts/closeout_evidence.sh
```

Plus the increment's own gates:

```
swift run BeatBench --self-test
swift run BeatBench --mode offline-grid
swift test --package-path PhospheneEngine --filter MetricalLevel
```

---

## 8. Commit messages

Format `[FT.3.1] <component>: <description>`; small commits per logical step (label set →
synthetic control → signal comparison → detector → confusion matrix → BeatBench table).
Local-only; **push only on Matt's explicit "yes, push".**

---

## 9. Closeout

Invoke the `closeout` skill; 8-part report with the verbatim `Scripts/closeout_evidence.sh`
block as §2. Increment-specific additions:

- the **label table** from task 1, with the 2-positive limitation stated, not buried;
- the **synthetic control** design and its results, reported separately from the real labels;
- the **per-signal comparison** from task 3;
- the **confusion matrix + overlap characterisation** from task 5;
- the **five-suite BeatBench table** from task 6, or an explicit "no behavioral change to
  beat sync" if nothing is wired (expected);
- BUG/decision status stated from the **authoritative row**, not narrative recall.

---

## 10. DECISION — ANSWERED (D-210, Matt 2026-07-31: "decline the bar, keep the beat")

**Resolved before the session starts.** On a track detected as wrong-level, presets get **no bar
position** and fall back to their energy-driven behaviour; the beat layer is untouched. This
extends D-207's "a meter *or* no confident bar" contract with a second decline reason. Ratified
as **D-210** — read it before task 4, because it sets what the detector is *for*: a detector that
declines correctly is a win even if it never corrects anything, so task 4's `undetermined` and
`atWrongLevel` paths matter more than any correction factor. **Correction is explicitly not
chosen** and returns as an option only if task 5's confusion matrix shows a near-zero
confident-wrong rate. The original question and its options are kept below as the rationale.

**Question:** when Phosphene's beat grid is running at double or half the speed a listener
would tap, what should the visuals do?

This is not hypothetical — it happens on 2 of the 5 tracks we have clean ground truth for, and
it is why bar-locked accents land on the wrong beat. It also sits on a tension already inside
D-205: that decision gates beat *feel* on AMLt, on the explicit product grounds that a
half-or-double grid "still reads as locked" — while also making bar position a **hard** gate
because Nacre's and Glaze's downbeat pushes consume it. FT.3 measured those two as
incompatible: a grid at the wrong level still feels locked, and makes the bar line
unrecoverable.

- **Decline the bar, keep the beat.** On a track detected as wrong-level, presets stop getting
  a bar position and fall back to their energy-driven behaviour — Nacre's and Glaze's downbeat
  pushes simply don't fire. The pulse still feels locked (that is the AMLt argument). Nothing
  lands on the wrong beat; a couple of tracks lose one layer of punctuation.
- **Correct the level and keep the bar.** Attempt the 2× / ½× correction and carry on giving
  presets a bar. When it is right, odd-meter and dense tracks gain accents they don't have
  today. When it is wrong, every accent moves to the wrong beat for the whole track — which is
  what happens now, but confidently.
- **Change nothing.** Accept that on some tracks the bar accents land on an arbitrary beat.
  Costs nothing, and no user has reported it.

**Recommendation: decline the bar, keep the beat.** It matches D-207's existing contract that
the system returns a meter *or* no confident bar, it cannot make anything worse than today,
and losing a downbeat push on two tracks is a far smaller cost than a confidently wrong one on
a track we mis-corrected. Correcting the level only becomes worth arguing for once task 5's
confusion matrix shows the confident-wrong rate is near zero.

**Chosen (Matt, 2026-07-31): decline the bar, keep the beat → D-210.**
