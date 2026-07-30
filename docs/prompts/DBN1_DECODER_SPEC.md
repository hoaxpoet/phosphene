# Increment DBN.1 — Bar-pointer-model decoder: desk research + spec doc

**Type:** docs / desk research (**no engine code**) · beat-sync program (D-202), phase DBN

**Objective.** After this session `docs/design/DBN_DECODER_SPEC.md` exists: a written, paper-cited
specification of a bar-pointer-model decoder that turns Beat This! per-frame beat/downbeat
activations into beats + downbeats + per-segment tempo + a posterior confidence — complete enough
that DBN.2 can implement it without reopening a paper, with every constant either sourced to an
equation or explicitly marked a tunable with a default and a rationale. No decoder code is written
this session.

---

## 1. Why this increment exists, and why it is next

Phase TRK is **parked** (D-206, Matt 2026-07-30: "park the tracker, go DBN next session"). Two
levers were measured against the same frozen single-BPM grid and neither closed BUG-065:

- **TRK.1** proved the drift is a *ramp* (−1.493 ms/s at R² 0.844 ⇒ a 0.149 % cached-grid period
  error) but its type-2 controller regressed the real fixture (maxAbsDrift 101.5 ms vs limit 50).
- **TRK.2** was falsified by measurement: drums-stem onsets are not better beat evidence, and —
  the deciding number — **only ~15–25 % of detected onsets, from any band or stem, land within
  ±50 ms of a beat**. FA #68 generalises to the whole spectral-onset family.

So the problem is upstream of the tracker. DBN attacks the premise itself: `BeatGridResolver`
peak-picks each frame independently and then infers one BPM and one meter by median IOI, which is
why a tempo change is invisible, why Money logged `beatsPerBar=2`, and why dense material
saturates. A sequence decoder makes the grid a *jointly decoded path* rather than a set of
independent peaks.

**This is a spec-only increment on purpose.** The program plan's cautionary case is the BeatNet
pivot (D-077): a paraphrased FFT spec produced diverging code three sessions downstream before
anyone noticed. Writing the spec first, with equation citations, is the countermeasure.

**Authoring-invariant note.** Design docs are normally authored in Matt's seat before
implementation. `DBN_DECODER_SPEC.md` is the sanctioned exception — the ratified plan defines
DBN.1 as a Claude Code session whose done-when is "spec doc committed". It is an engineering
specification, not a product design doc; product-level choices inside it go to Matt as
DECISION-NEEDED items at closeout (task 7).

---

## 2. Skill invocations

| When | Skill |
|---|---|
| **Before reading any paper or reference implementation — mandatory opener** | `reference-port` |
| Before touching any beat-path thinking — mandatory opener | `beat-sync-session` |
| When reaching for the activation dumper or a recorded session | `session-forensics` |
| At the end, before committing | `closeout` |

`reference-port` §1 (license gate) is checked **before** reading a reference to port it, not after.

---

## 3. Read-first (exact paths, in order)

1. `docs/BEAT_SYNC_PROGRAM_PLAN.md` — **§DBN only** (line ~68), plus §1 constraints and §2
   ("Why the current architecture caps all five categories")
2. `PhospheneEngine/Sources/DSP/BeatGridResolver.swift` — the incumbent, in full (~120 lines). The
   spec must state, per stage, what the decoder replaces and what it keeps.
3. `PhospheneEngine/Sources/ML/BeatThisModel.swift` — the **activation contract**: `tMax = 1500`
   frames, 50 fps (hop 441 @ 22050 Hz), sigmoid-applied beat + downbeat streams. The decoder's
   input format is fixed by this file; do not invent a different one.
4. `PhospheneEngine/Sources/DSP/BeatGrid.swift` — the output type the decoder must produce today
   (DBN.4 generalises it later; DBN.1 specs against the current shape and *notes* what DBN.4 needs)
5. `docs/DECISIONS.md` — **D-077** (license precedent: Beat This! MIT portable, madmom CC-NC
   weights never ship, TempoCNN rejected as AGPL) and **D-206** (why TRK is parked)
6. `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md` — current capability state
7. `PhospheneEngine/Sources/BeatThisActivationDumper/Dumper.swift` — how to get real activations to
   reason against

---

## 4. Pre-flight invariants (a failed check stops the session)

- `git log --oneline -1` on `main` is `ba8e6cb3` or later; working tree clean.
- `swiftlint lint --strict --config .swiftlint.yml` → **0 violations**.
- `swift test --package-path PhospheneEngine` → green.
- `docs/DECISIONS.md` contains **D-206** (phase TRK parked). If it does not, the branch is stale —
  stop.
- BeatBench fixtures present at `~/phosphene_beatbench_fixtures` (13 files).
- **`PHOSPHENE_BEAT_PLL` is still default-off and `BeatGridResolver` is unmodified.** If either has
  changed, another session has touched the beat path — stop and reconcile.

---

## 5. Tasks

1. **License gate, before reading to port.** Record, in the spec's header, the license position for
   every source consulted: the papers themselves, madmom's implementation, and Beat This!'s
   post-processing. Per D-077 and the `reference-port` table: implement **clean-room from the
   papers**; madmom may be run as an offline annotation/cross-check tool but no madmom code is
   read-to-copy and no CC-NC weights ship. **Done-when:** a license section names each source, its
   license, and whether it may inform code, only validate output, or neither. If any source's
   licence is unclear, **stop and surface it** rather than proceeding on assumption.

2. **State space.** Specify the bar-pointer state space (bar position × tempo) from Krebs et al.
   2015: position discretisation, the tempo grid (range and spacing — log or linear, state which
   and cite), and how the meter hypothesis set {3, 4, 5, 6, 7, 9, 12} maps onto it. **Done-when:**
   the state count for a 30 s window at 50 fps is computed and written down, and the memory and
   Viterbi cost that follows from it are stated as numbers, not adjectives.

3. **Transition model — and name the category-3 lever explicitly.** Specify bar-position
   advancement and the tempo-transition distribution. **The tempo-change penalty is the single most
   consequential tunable in this spec** (plan §DBN): it decides whether the visuals chase a live
   band's drift or hold a steady pulse. Give it a name, a default, a range, and a one-line
   statement of what a listener would see at each end. **Done-when:** the transition probabilities
   are written as equations with paper citations, and the tempo-change penalty appears in the
   tunables table with all four fields.

4. **Observation model.** Specify how the per-frame beat and downbeat probabilities become
   observation likelihoods — including the non-beat state's likelihood, which is where paraphrase
   most often goes wrong. **Done-when:** cited to an equation; the treatment of the sigmoid outputs
   (used directly, log-domain, floored?) is unambiguous.

5. **Output contract.** Specify the decoder's outputs — beats, downbeats, per-segment tempo,
   `beatsPerBar`, and a **posterior confidence** — and map each onto today's `BeatGrid` fields.
   Where the current type cannot carry something (per-segment tempo is the obvious one), record it
   as an explicit **DBN.4 requirement** rather than quietly dropping it. **Done-when:** a
   field-by-field table from decoder output → `BeatGrid`, with the gaps named and assigned to
   DBN.4.

6. **Ground the spec in one real activation dump.** Run `BeatThisActivationDumper` on one fixture
   with a known-hard meter (`money.wav`, 7/4 ~123 BPM, is the plan's load-bearing case) and confirm
   from the actual numbers that the spec's input assumptions hold — frame rate, length, value
   range, and whether the downbeat stream is informative enough for meter inference at all.
   **Done-when:** the dump's summary statistics are quoted in the spec, and any assumption they
   contradict is corrected in the spec rather than in a footnote.

7. **Assemble the DECISION-NEEDED list for Matt.** Collect every choice in the spec whose answer
   changes what a listener sees or feels — at minimum the meter hypothesis set and the
   tempo-change-penalty default — and write them at the end of the spec in product-level language
   (what the user sees under each option), each with a recommendation and a default. **Done-when:**
   the list exists, and nothing on it requires Matt to know an implementation detail to answer.

8. **Verification-plan stub for DBN.2.** One short section listing the synthetic activation cases
   DBN.2's unit suite must cover (clean 4/4, 7/4, tempo ramp, tempo step, silence, noise floor) and
   the performance budget (< 50 ms for a 30 s activation window on M1). **Done-when:** the section
   exists; DBN.2's prompt can be written from it without reopening this task.

---

## 6. Do NOT

- **Do not write decoder code.** Not a prototype, not a sketch, not "just the state space struct".
  DBN.1 is spec-only; DBN.2 implements. A spec validated by code written in the same session is not
  validated.
- **Do not modify `BeatGridResolver`, `BeatGrid`, or `BeatThisModel`.** DBN.3 wires the decoder in
  behind `BEATGRID_DECODER=dbn|peak`; DBN.4 generalises the grid. Neither is this increment.
- **Do not copy madmom code, and do not vendor CC-NC weights** (D-077). Clean-room from the papers;
  madmom is an offline annotator only.
- **Do not paraphrase a formula from memory.** Cite the equation ("Eq. 4 of Krebs et al. 2015"). If
  you cannot cite it, you do not understand it well enough to spec it — say so in the doc rather
  than writing a plausible-looking restatement (`reference-port` §2; the D-077 cautionary case).
- **Do not touch cold-start phase.** Everything here is steady-state offline decoding (Cold-Start
  Phase Contract, FA #69).
- **Do not reopen phase TRK** or re-propose an onset-evidence change (D-206).
- **Do not promote beats to primary motion** (D-004) — this improves an accent-layer signal.
- **Do not claim a category is solved.** DBN.1 produces a spec; no category is won without a
  BeatBench number, and BeatBench does not exist yet (see §10).

---

## 7. Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
swift test --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter DocIntegrityTests 2>&1
```

Plus the task-6 dump:

```
swift run --package-path PhospheneEngine BeatThisActivationDumper --audio ~/phosphene_beatbench_fixtures/money.wav --out /tmp/money_activations.json
```

No engine code changes, so the app build is unaffected — but run it anyway if any Swift file was
touched for any reason.

---

## 8. Commit messages

Format `[DBN.1] <component>: <description>`; small commits per logical step (license gate → state
space + transition → observation + output → activation grounding → decision list). Local-only;
**push only on Matt's explicit "yes, push"**.

---

## 9. Closeout

Invoke the `closeout` skill; produce the 8-part report with the verbatim
`Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- the **license position table** from task 1, restated in the closeout;
- the **state-count and Viterbi-cost numbers** from task 2 (so the "CPU-trivial" claim in the plan
  is a number, not an assertion);
- the **`money.wav` activation summary** from task 6, and any spec assumption it corrected;
- the **DECISION-NEEDED list** from task 7, surfaced in the closeout body rather than buried in the
  doc;
- an explicit **"no behavioural change to beat sync"** statement (this is the beat-sync benchmark
  obligation's other branch — DBN.1 ships no runtime behaviour, so no BeatBench table is due);
- BUG-065 status stated from the **KNOWN_ISSUES row**, not narrative recall.

---

## 10. DECISION-NEEDED (surface at the START of the session, not the end)

**Question:** DBN.3's acceptance gate is a BeatBench A/B across all five suites — and BeatBench
does not exist yet. GT.2 (tap ground truth) and GT.3 (the scoring harness + baseline) are both
unstarted. How do you want the phase sequenced?

- **Do GT.2 + GT.3 first, then DBN.** ~40 minutes of your tapping time and 3–4 sessions before any
  decoder work starts — but every DBN claim afterwards arrives with a number attached, and the
  baseline is what tells us whether the decoder actually helped rather than just changed things.
- **Push DBN.1 + DBN.2 now, hit the wall at DBN.3.** Two sessions of real progress (spec, then a
  unit-tested decoder on synthetic activations) with no dependency on ground truth. DBN.3 then
  stalls until GT lands, and the decoder sits unproven on real music in the meantime.
- **DBN.1 only, then reassess.** One session, cheapest possible probe — the spec surfaces how much
  of the design is genuinely settled versus still open, and you decide with that in hand.

**Recommendation:** GT.2 + GT.3 first. The TRK phase is the argument for it — TRK.1 shipped a fix
that a synthetic suite called an improvement and real data called a 101 ms regression, and TRK.2
only resolved because a real measurement existed to resolve it. Building the decoder before the
scoreboard repeats exactly the mistake that cost TRK.1.

**Default if no reply:** run DBN.1 as written (it is useful under every sequencing choice and
blocks nothing), and re-raise the GT-vs-DBN.2 sequencing at its closeout.
