# Increment DBN.1 — Bar-pointer-model decoder: desk research + spec doc

**Type:** docs / desk research (**no engine code**) · beat-sync program (D-202), phase DBN

**Objective.** After this session `docs/design/DBN_DECODER_SPEC.md` exists: a written, paper-cited
specification of a bar-pointer-model decoder that turns Beat This! per-frame beat/downbeat
activations into beats + downbeats + per-segment tempo + a posterior confidence — complete enough
that DBN.2 can implement it without reopening a paper, with every constant either sourced to an
equation or explicitly marked a tunable with a default and a rationale. No decoder code is written
this session.

---

## 1. Why this increment exists, and what the baseline says it must fix

Phase TRK is **parked** (D-206, Matt 2026-07-30: "park the tracker, go DBN next session"). Two
levers were measured against the same frozen single-BPM grid and neither closed BUG-065: TRK.1's
type-2 controller regressed the real fixture, and TRK.2 was falsified — **only ~15–25 % of detected
onsets, from any band or stem, land within ±50 ms of a beat**, so FA #68 generalises to the whole
spectral-onset family. The problem is upstream of the tracker.

**Read the GT.3 baseline before assuming what the decoder is for.** The measured baseline (D-205,
`docs/diagnostics/BEATBENCH_BASELINE_2026-07-30.md`) inverted the program's original priority:

| axis | baseline | verdict |
|---|---|---|
| beat F-measure, suite 1 | 0.97 | **already meets the ≥ 0.95 target** |
| suite-2 beats (AMLt) | 1.00 / 1.00 / 0.88 / 0.75 / 0.21 | 3 of 5 already pass the ratified ≥ 0.85 bar |
| **`beatsPerBar`** | plausible on **2 of 9** tracks (Take Five reads 2, is 5; Solsbury Hill and Money read 1, are 7) | **this is the work** |
| **downbeat F** | **0.13–0.26** everywhere except Billie Jean's 0.90 | **this is the work** |

D-205 states it plainly: "The program's §1 targets led with beat F — the axis that was mostly
already working." So **the decoder's payoff is meter and downbeats, not beat times.** A spec that
optimises beat placement and treats bar position as a by-product would be aimed at the wrong
target. Meter is also a **hard gate**, not report-only (D-205 product call 2), because certified
presets already consume bar position — Nacre's and Glaze's downbeat pushes are each that preset's
connection layer (D-171, D-173), so a wrong bar-1 degrades visuals users see.

Why the incumbent cannot get there: `BeatGridResolver` peak-picks each frame independently, then
infers one BPM by trimmed-mean IOI and `beatsPerBar` by `round(median_downbeat_IOI / beat_period)`
— a meter estimate built on top of a downbeat stream that scores 0.13–0.26. A sequence decoder
makes bar position part of a *jointly decoded path* instead of a post-hoc division.

**This is a spec-only increment on purpose.** The cautionary case is the BeatNet pivot (D-077): a
paraphrased FFT spec produced diverging code three sessions downstream before anyone noticed.
Writing the spec first, with equation citations, is the countermeasure.

**Authoring-invariant note.** Design docs are normally authored in Matt's seat before
implementation. `DBN_DECODER_SPEC.md` is the sanctioned exception — the ratified plan defines
DBN.1 as a Claude Code session whose done-when is "spec doc committed". It is an engineering
specification; product-level choices inside it go to Matt as DECISION-NEEDED items at closeout.

---

## 2. Skill invocations

| When | Skill |
|---|---|
| **Before reading any paper or reference implementation — mandatory opener** | `reference-port` |
| Before touching any beat-path thinking — mandatory opener | `beat-sync-session` |
| Before quoting or reasoning from any baseline number | `beatbench` |
| When reaching for the activation dumper or a recorded session | `session-forensics` |
| At the end, before committing | `closeout` |

`reference-port` §1 (license gate) is checked **before** reading a reference to port it, not after.

---

## 3. Read-first (exact paths, in order)

1. `docs/diagnostics/BEATBENCH_BASELINE_2026-07-30.md` — **the offline baseline.** Read this before
   the papers. It is what the decoder has to beat.
2. `docs/DECISIONS.md` — **D-205** (ratified per-suite targets, and why meter is a hard gate),
   **D-077** (license precedent), **D-206** (why TRK is parked)
3. `docs/BEAT_SYNC_PROGRAM_PLAN.md` — **§DBN only**, plus §1 constraints and §2
4. `PhospheneEngine/Sources/DSP/BeatGridResolver.swift` — the incumbent, in full (~120 lines). The
   spec must state, per stage, what the decoder replaces and what it keeps.
5. `PhospheneEngine/Sources/ML/BeatThisModel.swift` — the **activation contract**: `tMax = 1500`
   frames, 50 fps (hop 441 @ 22050 Hz), sigmoid-applied beat + downbeat streams. The decoder's
   input format is fixed by this file; do not invent a different one.
6. `PhospheneEngine/Sources/DSP/BeatGrid.swift` — the output type the decoder must produce today
   (DBN.4 generalises it; DBN.1 specs against the current shape and *notes* what DBN.4 needs)
7. `PhospheneEngine/Sources/BeatBench/Metrics.swift` — how F, AMLt, CMLt and meter correctness are
   actually computed, so the spec's success claims use the harness's definitions
8. `docs/diagnostics/BEATBENCH_LIVE_BASELINE_2026-07-30.md` — context only (the live path is TRK/RLG
   territory, not DBN.1's), but it is where BUG-065's drift curves now live across 15 tracks

---

## 4. Pre-flight invariants (a failed check stops the session)

- `git log --oneline -1` on `main` is `249dffe9` or later; working tree clean.
- `swiftlint lint --strict --config .swiftlint.yml` → **0 violations**.
- `swift test --package-path PhospheneEngine` → green.
- `docs/DECISIONS.md` contains **both** D-205 (BeatBench targets) and **D-206** (phase TRK parked).
  If either is missing the branch is stale — stop.
- BeatBench fixtures at `~/phosphene_beatbench_fixtures` and ground truth at
  `PhospheneEngine/Tests/Fixtures/beatbench/groundtruth/` (9 tracks). If ground truth is absent,
  stop — the whole point of specing against the baseline is that the baseline is reproducible.
- **`BeatGridResolver` is unmodified and `PHOSPHENE_BEAT_PLL` is still default-off.** If either has
  changed, another session has touched the beat path — stop and reconcile.

---

## 5. Tasks

1. **License gate, before reading to port.** Record, in the spec's header, the license position for
   every source consulted: the papers, madmom's implementation, and Beat This!'s post-processing.
   Per D-077 and the `reference-port` table: implement **clean-room from the papers**; madmom may be
   run as an offline annotator but no madmom code is read-to-copy and no CC-NC weights ship.
   **Done-when:** a license section names each source, its license, and whether it may inform code,
   only validate output, or neither. If any licence is unclear, **stop and surface it**.

2. **State the target in baseline numbers, first.** Open the spec with the specific cells DBN must
   move: `beatsPerBar` 2/9 → the D-205 bar of ≥ 3/4 on suite 2, and downbeat F off the 0.13–0.26
   floor — plus the explicit non-goal that suite-1 beat F (0.97) and the three passing suite-2 AMLt
   scores must not regress. **Done-when:** the section exists with the numbers quoted from the
   baseline doc, and every later design choice can be traced back to one of them.

3. **State space.** Specify the bar-pointer state space (bar position × tempo) from Krebs et al.
   2015: position discretisation, the tempo grid (range and spacing — log or linear, state which
   and cite), and how the meter hypothesis set {3, 4, 5, 6, 7, 9, 12} maps onto it. Given task 2,
   be explicit about how a 7-beat bar is represented and how the decoder chooses between meters.
   **Done-when:** the state count for a 30 s window at 50 fps is computed and written down, and the
   memory and Viterbi cost that follows are stated as numbers, not adjectives.

4. **Transition model.** Specify bar-position advancement and the tempo-transition distribution.
   The **tempo-change penalty** is the category-3 lever (plan §DBN) — give it a name, a default, a
   range, and one line on what a listener would see at each end. Note that D-205 **deferred suite 3**
   as not measurable offline, so this tunable ships with a documented default and is validated later,
   not tuned now. **Done-when:** transition probabilities written as equations with paper citations;
   the penalty appears in the tunables table with all four fields.

5. **Observation model.** Specify how the per-frame beat and downbeat probabilities become
   observation likelihoods — including the non-beat state's likelihood, where paraphrase most often
   goes wrong. Because downbeat F is the weak axis, state explicitly how much the decoder is allowed
   to lean on the downbeat stream versus inferring bar position from beat structure alone.
   **Done-when:** cited to an equation; the treatment of the sigmoid outputs (used directly,
   log-domain, floored?) is unambiguous.

6. **Output contract.** Specify the outputs — beats, downbeats, per-segment tempo, `beatsPerBar`,
   and a **posterior confidence** — and map each onto today's `BeatGrid` fields. Where the current
   type cannot carry something (per-segment tempo is the obvious one), record it as an explicit
   **DBN.4 requirement** rather than quietly dropping it. Note that D-205 found `barConfidence`
   untrustworthy today (Clair de Lune reads 0.55 and should read near zero) — say what the decoder's
   posterior confidence is expected to do better, without claiming it solves suite 5 (that is CNF).
   **Done-when:** a field-by-field table from decoder output → `BeatGrid`, with gaps assigned to DBN.4.

7. **Ground the spec in one real activation dump.** Run `BeatThisActivationDumper` on `money.wav`
   (7/4 ~123 BPM — reads `beatsPerBar` 1 today, and one of the tracks D-205 names) and confirm from
   the actual numbers that the spec's input assumptions hold: frame rate, length, value range, and
   **whether the downbeat stream carries enough signal for meter inference at all**. If it does not,
   that is the single most important finding of this session and it changes DBN.2's shape — say so
   plainly rather than specing around it. **Done-when:** the dump's summary statistics are quoted in
   the spec and any assumption they contradict is corrected in the spec, not footnoted.

8. **Verification plan for DBN.2.** List the synthetic activation cases DBN.2's unit suite must
   cover (clean 4/4, 7/4, tempo ramp, tempo step, silence, noise floor) and the performance budget
   (< 50 ms for a 30 s activation window on M1). Name which BeatBench cells DBN.3 will A/B.
   **Done-when:** the section exists; DBN.2's prompt can be written from it without reopening this task.

9. **Assemble the DECISION-NEEDED list.** Collect every choice whose answer changes what a listener
   sees or feels, written in product-level language with a recommendation and a default.
   **Done-when:** the list exists and nothing on it requires Matt to know an implementation detail.

---

## 6. Do NOT

- **Do not write decoder code.** Not a prototype, not a sketch, not "just the state space struct".
  A spec validated by code written in the same session is not validated.
- **Do not modify `BeatGridResolver`, `BeatGrid`, or `BeatThisModel`.** DBN.3 wires the decoder in
  behind `BEATGRID_DECODER=dbn|peak`; DBN.4 generalises the grid.
- **Do not re-derive or re-ratify the BeatBench targets.** They are D-205, settled. Cite them.
- **Do not copy madmom code or vendor CC-NC weights** (D-077). Clean-room from the papers.
- **Do not paraphrase a formula from memory.** Cite the equation ("Eq. 4 of Krebs et al. 2015"). If
  you cannot cite it, say so in the doc rather than writing a plausible-looking restatement
  (`reference-port` §2; the D-077 cautionary case).
- **Do not touch cold-start phase** (Cold-Start Phase Contract, FA #69) or the live path — DBN is
  the offline grid.
- **Do not reopen phase TRK** or re-propose an onset-evidence change (D-206).
- **Do not promote beats to primary motion** (D-004).
- **Do not claim a category is won.** No category is claimed without a BeatBench number, and DBN.1
  produces no numbers beyond the task-7 dump (`beatbench` skill).

---

## 7. Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
swift test --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter DocIntegrityTests 2>&1
```

Plus the task-7 dump:

```
swift run --package-path PhospheneEngine BeatThisActivationDumper --audio ~/phosphene_beatbench_fixtures/money.wav --out /tmp/money_activations.json
```

No engine code changes, so the app build is unaffected — run it anyway if any Swift file was touched.

---

## 8. Commit messages

Format `[DBN.1] <component>: <description>`; small commits per logical step (license gate → baseline
targets → state space + transition → observation + output → activation grounding → decision list).
Local-only; **push only on Matt's explicit "yes, push"**.

---

## 9. Closeout

Invoke the `closeout` skill; produce the 8-part report with the verbatim
`Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- the **license position table** from task 1;
- the **baseline cells DBN must move** from task 2, restated in the closeout;
- the **state-count and Viterbi-cost numbers** from task 3 (so "CPU-trivial" is a number);
- the **`money.wav` activation summary** from task 7, and any spec assumption it corrected —
  especially if the downbeat stream turns out too weak for meter inference;
- the **DECISION-NEEDED list** from task 9, surfaced in the closeout body, not buried in the doc;
- an explicit **"no behavioural change to beat sync"** statement — DBN.1 ships no runtime
  behaviour, so no BeatBench before/after table is due (the benchmark obligation's other branch);
- BUG-065 status stated from the **KNOWN_ISSUES row**, not narrative recall.

---

## 10. DECISION-NEEDED

**Question:** when the decoder cannot confidently tell what the bar is, should the visuals guess a
downbeat anyway or stop marking bars until it is sure?

Bar position is what Nacre's and Glaze's downbeat camera pushes ride on (D-171, D-173), and today
the meter is wrong on 7 of 9 measured tracks — so this is currently happening a lot, invisibly.

- **Always commit to a best guess (today's behaviour).** Every track gets a downbeat accent. On the
  7-in-9 where the meter is wrong, that accent lands on an arbitrary beat — a push that feels
  almost-but-not-quite tied to the music, which is the "connected but not tight" complaint already
  on file for GLAZE.7.
- **Decline when unsure — no bar accent until the decoder is confident.** On odd or ambiguous
  material the downbeat push simply does not fire; those presets keep their beat-level motion and
  lose only the bar-level gesture. Nothing lands wrong, but some tracks get a visibly plainer
  reading than they do now.
- **Decline, and let each preset choose a fallback.** Same as above, except a preset may substitute
  a bar-free gesture (e.g. an every-4-beats push) rather than going quiet. More expressive, but it
  is per-preset work and lands after DBN, not with it.

**Recommendation: decline when unsure.** It matches the call you already made in D-205 — meter is a
hard gate, not report-only, precisely because a wrong bar-1 degrades what users see — and "success =
declining honestly" is already the program's stated position for category 5. A missing accent reads
as restraint; a wrong one reads as broken.

**Default if no reply:** DBN.1 specs the confidence output so that *either* policy is implementable
without a redesign, records the choice as open, and re-raises it at DBN.3 when there are A/B numbers
showing how often "unsure" actually fires.
