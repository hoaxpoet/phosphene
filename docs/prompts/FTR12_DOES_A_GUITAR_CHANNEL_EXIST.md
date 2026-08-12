# Increment FTR.12 — does a guitar channel exist at all?

**Type:** engine measurement / diagnostics. **No preset change. No shader edit.**

**Objective.** After this session there is a committed, re-runnable measurement that answers one question with a table: *is there any per-stem feature Phosphene already computes that separates a guitar from the drums on real material?* Today the answer is assumed rather than known — Fractal Tree's tips have been routed to `other_onset_rate` since FTR.8 on the strength of a single track. A "no" is a **complete and successful result** for this increment: it retires the guitar ambition on measured grounds instead of funding a fourth attempt at it.

Matt's words that opened this, 2026-08-11, session `2026-08-11T23-52-49Z` (*Seven Nation Army*): *"Guitar is barely registering."* His call on how to proceed, taken the same day, from three options: **measure across captures first, before touching the preset.**

---

## 1. Skills to invoke

* `session-forensics` — before touching any capture or diagnostic CLI.
* `preset-session` — **only if** you end up reading `FractalTree.metal` for context. You should not need to edit it.
* `closeout` — at the end.

Do **not** invoke `shader-authoring`. If you find yourself needing it, the increment has drifted out of scope — stop and say so.

## 2. Read first

1. `docs/ENGINEERING_PLAN.md` §FTR.11 — the three findings that produced this increment, including the +0.71 measurement. Do not re-derive them.
2. `docs/QUALITY/KNOWN_ISSUES.md` **BUG-086** and **BUG086.3** — the stem-latency picture changed on 2026-08-12 (the 2.9 s pass was withdrawn as a false pass and the corpus reclassified as streaming). Read this **before** designing the measurement, not after.
3. `docs/diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md` §7b, §8 — the method that measured stem lag three independent ways, and the CHR.1 finding that 65–93 % of each stem trace is the shared loudness envelope. **CHR.1 asked a neighbouring question and got a discouraging answer; read it before assuming this one is open.**
4. `PhospheneEngine/Sources/DSP/StemAnalyzer.swift` — `analyze(stemWaveforms:fps:)` is the entry point; note every feature it produces.
5. `PhospheneEngine/Sources/ML/StemSeparator.swift` — `separate(audio:channelCount:sampleRate:)`, and the **~10 s fixed model window** (`modelFrameCount = 431`) that forces chunking.
6. `PhospheneEngine/Tests/PhospheneEngineTests/DSP/TrunkTrajectoryReportTests.swift` — the shape to copy: decode a real file, run the real production objects over it, print a report, assert only what is mechanically checkable.

## 3. Pre-flight invariants

Each of these stops the session if it fails.

* `Scripts/closeout_evidence.sh` is ALL GREEN before task 1.
* `Scripts/link_fixtures.sh` has been run if this is a fresh worktree.
* HEAD descends from `947b52c3` (PR #83, FTR.11).
* **FTR.11 is unverified live.** Matt's M7 on the stepped frame is still outstanding. This increment does not depend on it and must not wait for it — but do not describe Fractal Tree as fixed in any doc you touch.
* The live MIR analysis rate is **~10 Hz**, not the 60 Hz render rate. `features.csv`/`stems.csv` rows are per RENDER frame. Any per-frame alpha means `τ = 1/(α·10)`. Four increments shipped with this wrong.

## 4. Tasks

### Task 1 — build the offline stem measurement path

Decode a local file → chunk to the model's ~10 s window → `StemSeparator.separate` → `StemAnalyzer.analyze` → per-feature series. Copy the `TrunkTrajectoryReportTests` shape (env-gated on an audio path, reports rather than asserts a verdict).

**Offline, not capture replay, and that is the point.** The ten sessions on disk are four rock tracks Matt happened to play; they cannot answer a question about whether a feature generalises. Offline selection costs no live-session time and lets you choose the material the question needs.

**Done when** the harness produces per-feature series for a named local file and the drums/other series are visibly different from each other on a track where they should be.

### Task 2 — pick the corpus, controls first

At least **six** tracks, and the controls are the whole design, not padding:

* **≥ 2 negative controls — tracks with NO guitar at all** (electronic, orchestral, solo piano, a cappella). This is the decisive test: if `otherOnsetRate` on a guitarless track is distributionally indistinguishable from a guitar track, the feature is not reading guitar and no coefficient fixes that.
* **≥ 2 positive controls — clean, prominent, largely isolated guitar** (a solo acoustic or clean electric arrangement).
* **≥ 2 hard cases — distorted guitar in a dense rock mix**, which is where it has to work. *Seven Nation Army* and *Cherub Rock* are already measured; keep them for continuity.

The library is at `/Volumes/Extreme SSD/`. Name every track in the closeout with why it was chosen for its slot.

**Done when** the corpus table exists with a stated role per track, and the two guitarless controls are genuinely guitarless (check by ear, not by genre assumption).

### Task 3 — the measurement

For every stem feature `StemAnalyzer` produces (`otherOnsetRate`, `otherEnergyDev`, `otherEnergyRel`, `otherEnergySlope`, and the IFC.4 instrument-family series if it is reachable offline), per track:

* correlation with the **drums control** feature of the same kind;
* the feature's own distribution (p05 / p50 / p95, distinct-value count);
* the guitarless-control comparison — same statistics, so "does this look different when no guitar is present" is answerable by reading one table.

**Stem-vs-stem correlations are lag-immune** — both series come from the same separation pass, so a shared latency cancels. That is why this survives BUG-086. **Any comparison against a non-stem series (a FeatureVector field, the beat grid) is NOT lag-immune and must carry an explicit lag sweep** — the FTR.11 trunk-vs-stem numbers swept 0–5 s for exactly this reason.

**Done when** the table exists for every feature × track and is committed as a diagnostics doc.

### Task 4 — STOP AND REPORT

Write the verdict as one sentence before proposing anything: *"<feature> separates guitar from drums on N of M tracks"* — or *"no feature does."*

**Do not proceed to any preset recommendation in the same breath.** If a feature does separate, the routing decision is Matt's and needs its own increment. If none does, the recommendation is to retire the guitar claim from `FractalTree.json`'s description, the reference README and the plan — also Matt's call.

**Done when** the sentence is written, the table is committed, and Matt has been asked.

## 5. Do NOT

* **Do not change the preset.** No `.metal` edit, no sidecar route change, no coefficient. That is the whole reason this increment is scoped as measurement.
* **Do not widen the tips coefficient to make the guitar "register."** Measured on *Seven Nation Army*, `otherOnsetRate` is **+0.71 with `drumsOnsetRate`** — widening it amplifies the drums under a label that says guitar.
* **Do not re-attempt per-note guitar onset DETECTION.** MEL.1 measured it: grid coherence 31 % for guitar against a 41 % drums control, and FA #68 generalises the spectral-onset family. This increment asks the weaker question — rate and envelope — deliberately.
* **Do not treat a plausible-looking rate as validation.** Run the drums control first and believe a weak result only after the control says the method works on material where the answer is known. (`[[feedback_control_stem_before_building_driver]]` — MEL.1 burned a session on this exact mistake.)
* **Do not conclude from the four rock captures already on disk.** They are one genre; the question is about generalisation.
* **Do not certify Fractal Tree.** FTR.5 is Matt's and he has not given it.

## 6. Verification

```
swiftlint lint --strict --config .swiftlint.yml
```

```
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
```

```
swift test --package-path PhospheneEngine
```

Increment-specific — the new report over one track from each corpus slot:

```
FTR12_AUDIO="/Volumes/Extreme SSD/<path>.mp3" swift test --package-path PhospheneEngine --filter GuitarChannel
```

## 7. Commits

`[FTR.12] <component>: <description>`, small and per logical step. Suggested: the offline harness; the corpus table; the findings doc; the plan entry.

Push only on Matt's explicit "yes, push". Push to a BRANCH and open a PR — never directly to `main`, which requires `fast-gate`.

## 8. Closeout

Invoke the `closeout` skill. 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

* the corpus table with the role of each track;
* the full feature × track correlation table, including the guitarless controls;
* the one-sentence verdict from task 4;
* explicitly, which claims in the repo the result **invalidates** — FTR.8's `+0.14 with drums` is a single-track figure and this increment either generalises it or retires it.

State plainly that no preset behaviour changed.

---

## 9. DECISION-NEEDED (carry-over from FTR.11, one line of code)

**Question:** should the Fractal Tree trunk's motion gate be measured per second or per beat?

The gate asserts the held trunk turns ≤ 0.6 times a second. On *Carry The Zero* (94 BPM) it measures 0.52 and passes; on *Seven Nation Army* (124 BPM) it measures 0.66 and **fails**. Per beat both are **0.32** — a beat-held value can only change on a beat, so the per-second unit carries the tempo and the bar is silently stricter on faster songs for no musical reason.

* **A — switch to turns per beat (recommended).** The bar means the same thing on every track. Nothing about what you see changes; this is a measurement unit, not preset behaviour.
* **B — keep per second, accept it is red on fast tracks.** Honest, and leaves a permanently failing check that a future session will be tempted to "fix" without understanding it.

**Default if no reply:** leave it red and unchanged. Changing a metric in the increment it goes red is how FTR.6 shipped a regression past a green gate, so it does not move without an explicit yes.
