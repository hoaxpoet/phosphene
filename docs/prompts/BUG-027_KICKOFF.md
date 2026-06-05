# BUG-027 Kickoff — The deviation primitives centre below 0.5, so `*Dev` is structurally near-dead for non-dominant bands

> Hand this to a new Claude Code session verbatim. Do not summarise.
>
> **Suggested project/phase tag:** `AGC2` (the old `AGC.1` is shelved/retired — its kickoff
> `docs/prompts/AGC1_KICKOFF.md` is banner-marked DO-NOT-IMPLEMENT because it chased the wrong
> root cause; see "Why the obvious patch is wrong" below). Confirm or rename the tag with Matt
> before committing anything.

---

## TL;DR

`bassDev`/`midDev`/`trebDev` (FeatureVector) and the raw `{stem}Energy` values (StemFeatures) are
**mis-calibrated against a 0.5 centre that the AGC does not actually produce per band.** The AGC
normalises the **total 6-band energy** to 0.5, so any single band — or any 3-band sub-sum — centres
*below* 0.5 (measured: individual bands ~0.22–0.25; a stem's 3-band sum ~0.24–0.41). The deviation
formula `xDev = max(0, (x − 0.5) × 2)` therefore fires on **< 3 % of frames** for a non-dominant
band, and consumers that assume `{stem}Energy ≈ 0.5` under-drive their visuals. D-026 calls the
deviation primitives "the primary above-average motion driver" — for most bands on most music, they
are near-dead. **This is a load-bearing-design-doesn't-do-what-it-says bug, P2, and it has already
bitten two shipped presets.**

**This is NOT a quick patch.** It needs a measured-evidence-first design decision with Matt
(three candidate approaches, real M7 blast radius across 11+ presets, golden-hash regression).
The plan below is deliberately staged: **measure → decide with Matt → fix → validate → release**.
Do not skip to a fix.

---

## What this is

[BUG-027](../QUALITY/KNOWN_ISSUES.md#bug-027) was filed 2026-06-02 during the BUG-025 A/B
correction and **re-confirmed 2026-06-05** (Nimbus NB.10 r1.6). Severity **P2**, domain
`dsp.beat` (deviation-primitive derivation / calibration). It is the structural issue the
BUG-025 misdiagnosis was pointing at, and it is explicitly tagged in KNOWN_ISSUES as
*"Candidate for its own project (cf. the beat-grid D-145 pattern)."* This kickoff is that project.

### The mechanism (read carefully — the whole fix decision turns on this)

1. The AGC in `BandEnergyProcessor` normalises against **total energy across all 6 bands**:
   `totalRawEnergy = raw6.reduce(0, +)` (`BandEnergyProcessor.swift:204`), EMA at `:207–211`,
   `agcScale = 0.5 / agcRunningAvg` (`:213`). The AGC target is **0.5 for the total**, not 0.5
   per band.
2. So an individual band's normalised output centres at `0.5 × (that band's fraction of total
   energy)`. A band carrying, say, 25 % of total energy centres at ~0.125; a bass band carrying
   ~half the energy on bass-dominant music centres at ~0.25.
3. The deviation primitives are derived downstream with a **fixed 0.5 pivot**:
   `MIRPipeline.swift:334–342` — `fv.bassRel = (fv.bass − 0.5) × 2.0`, `fv.bassDev = max(0, fv.bassRel)`
   (and `midRel/midDev`, `trebRel/trebDev`, the `*AttRel` family).
4. Result: for any band that centres below 0.5, `bassRel` is **mostly negative**, so the
   positive-only `bassDev` clamp fires almost never. Measured downstream of clean AGC resets,
   both capture paths:

   ```
                   bass mean   bassRel mean   bassDev fires
   LF (Atlas)        0.254       −0.49          2.9 %
   Spotify           0.222       −0.55          1.5 %
   ```

### Two manifestations — the fix must consider BOTH

| # | Path | Site | Symptom |
|---|------|------|---------|
| **A** | FeatureVector band deviation | `MIRPipeline.swift:334–342` (pivot) + `BandEnergyProcessor` (total-energy AGC) | `bassDev`/`midDev`/`trebDev` near-dead for any non-dominant band on real music. |
| **B** | StemFeatures raw energy | `StemAnalyzer.swift:221–224` — `vocalsE/drumsE/bassE/otherE = result.bass + result.mid + result.treble` (a 3-band sum of an AGC-normalised stem) | The raw `{stem}Energy` centres at ~0.30 (measured p50 0.24/0.27/0.41 across 3 Nimbus sessions). Consumers assuming a 0.5 centre under-drive (Nimbus's `bloom` → tiny dim bodies on normal music). |

> **Nuance to verify, not assume:** the *stem deviation* fields (`vocalsEnergyDev` etc.,
> `StemAnalyzer.swift:244–247`) are computed via `updateEMAsAndComputeDeviations`, i.e. against
> **per-stem EMAs**, not the fixed-0.5 pivot. So manifestation B's *deviation* path may already
> be doing something close to "approach (a) per-stem," while the *raw energy* value still centres
> at ~0.30. Map this precisely in the measurement increment — the per-stem EMA pattern may be the
> template for fixing manifestation A. Do not state this as fact until you've read the code.

### Already bitten two shipped presets (this is why it matters)

- **Dragon Bloom** (2026-06-02 re-tune): Spike 1 drove feather flow from `mid_att_rel` (≈ 0 →
  frozen feathers) and breathing from `max(0, bass_att_rel)` (clamped dead → no breathing) on
  bass-dominant music. Fix at *preset* scope: rerouted to signed `bass_rel`, `spectralFlux`, beat
  — i.e. fix-scope option (c) applied by hand. This is the proof that the document-and-steer
  workaround works, and the origin of the signal-liveness rule in `SHADER_CRAFT.md §14.1`.
- **Nimbus** (2026-06-05 NB.10 r1.6): `bloom = meanStem·1.4 − 0.2` mapped the real ~0.30 stem-
  energy centre to bloom ≈ 0.13 → tiny dim bodies on all normal music; only the unusually-dense
  Atlas master looked right. Fixed locally by recalibrating `bloomGain 1.4→1.9`, `bloomOffset
  −0.2→−0.06` (`NimbusState.swift`; D-144 amendment; `test_bloomVisibleOnTypicalMusic`). A local
  band-aid for the system-wide root cause.

Every future preset author who reaches for a `*Dev` primitive or a raw `{stem}Energy` value pays
for this until it's fixed at the engine, or until the limitation is documented loudly enough that
nobody reaches for it.

---

## Why the obvious patch is wrong (read before theorising)

The shelved `AGC.1` increment (`docs/prompts/AGC1_KICKOFF.md`, **DO-NOT-IMPLEMENT banner**) blamed
a **cold-start transient** poisoning the AGC EMA and proposed transient-rejection. An LF↔Spotify
A/B disproved that premise:

- The cold-start transient is **real but one-time, ~2 s, first-onset only**; track changes
  `reset()` and re-init cleanly. It does **not** poison the session.
- The `bassDev ≈ 0` starvation is **structural** (the fixed-0.5 pivot vs total-energy
  normalisation, above) and is **identical on the LF session that "danced"** (`bassDev` fires
  2.9 % LF vs 1.5 % Spotify). It is not a capture-path bug and not a convergence bug.

**Do not re-open transient rejection.** The structural cause is the 0.5 pivot, full stop.

---

## Read these first, before doing anything else

1. **[`docs/QUALITY/KNOWN_ISSUES.md` § BUG-027](../QUALITY/KNOWN_ISSUES.md)** — the full entry,
   the measured firing rates, the 6-band means, the three fix-scope options (a/b/c), and the
   verification criteria. **This is the source of truth; this kickoff expands it, never overrides
   it.** If they disagree, KNOWN_ISSUES wins and you fix this kickoff.
2. **`PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift`** — the entire `process(...)` method
   (`:192–248`). Note `:204` (total-energy reduce), `:207–211` (the EMA), `:213` (`0.5 /
   agcRunningAvg`), and the comment at `:122` ("Running average for 6-band AGC (total energy, not
   per-band)"). **The total-not-per-band design is intentional and load-bearing for mix-density
   stability (D-026) — do not break it casually; understand why it exists before changing it.**
3. **`PhospheneEngine/Sources/DSP/MIRPipeline.swift:294–342`** — the deviation derivation. The
   0.5 pivot lives here. `fv.bass` (`:304`-ish) is the AGC-normalised value from
   `BandEnergyProcessor`.
4. **`PhospheneEngine/Sources/DSP/StemAnalyzer.swift:215–247`** — the stem 3-band energy sums
   (`:221–224`) and the per-stem deviation assignment (`:244–247`, via
   `updateEMAsAndComputeDeviations`). Manifestation B lives here.
5. **`PhospheneEngine/Tests/PhospheneEngineTests/DSP/RelDevTests.swift`** — **the contract test you
   must not silently break.** It pins: `bassRel == (bass − 0.5) × 2.0` exactly; `bassDev ≥ 0`;
   stem `*EnergyDev ≥ 0`; amplitude-independence. If the chosen fix changes the pivot/derivation,
   these tests must be *deliberately and visibly* updated with the new semantics, with Matt's
   sign-off — never edited quietly to make a red bar green.
6. **`docs/DECISIONS.md` D-026** — the deviation-primitive contract this refines. The
   `(x − 0.5) × 2` convention and the mix-density-stability rationale are the design you're
   correcting, not discarding.
7. **`docs/SHADER_CRAFT.md §14.1` (Signal liveness)** — the durable rule born from this bug, with
   the worked stddev table. Fix-scope option (c) is already encoded here.
8. **`docs/prompts/AGC1_KICKOFF.md`** — read the **banner only** (top ~10 lines) to understand why
   transient rejection is the wrong tree. Skip the body.
9. **`docs/DECISIONS.md` D-144** (the r1.6 amendment) + **`NimbusState.swift`** `bloomGain` /
   `bloomOffset` — manifestation B's local band-aid, and the durable lessons (a)–(d) at the foot
   of the Nimbus memory: *energy as an additive bias destroys a hue axis's range; a 4 s mood EMA
   crushes to the per-track mean; "small/dim/weak response" is almost never a capture-level
   problem — measure the driver's real p50 from the session CSV and calibrate to **that**.*
10. **CLAUDE.md** — §Audio Data Hierarchy (Layer 1 vs Layer 2; this bug starves Layer 2),
    Failed Approach #31 (absolute thresholds on AGC values — same family of "AGC normalisation has
    non-obvious per-band consequences"), and the **Defect Handling Protocol** + **"Decisions
    presented to Matt must be framed in product-level language"** rule (both binding here).
11. **Reference sessions for measurement** (do not synthesise — Failed Approach #27):
    - `~/Documents/phosphene_sessions/2026-06-01T22-37-01Z/` — LF (Atlas), bass-dominant.
    - `~/Documents/phosphene_sessions/2026-06-02T01-12-51Z/` — Spotify, bass-dominant.
    - Plus any recent Nimbus sessions (for the stem-energy p50 0.24/0.27/0.41 figures). If these
      session directories are absent on this machine, **stop and ask Matt to record fresh ones**
      across a spectrally varied set (bass-dominant, mid-rich, treble-rich, full-mix) on both
      paths — the decision depends on real distributions, not one genre.

---

## Hard rules

1. **Multi-increment P2 protocol (CLAUDE.md Defect Handling).** This is P2 with catalog-wide blast
   radius. Do **not** request the trivial-P1 collapse — it does not qualify (root cause needs a
   design decision; > 5 lines; real architectural risk). Run the staged plan below.
2. **Measure before you decide; decide with Matt before you fix.** The single biggest lesson from
   the last two presets (Nimbus r1.6, Dragon Bloom re-tune) and from Failed Approach #60 (don't
   batch decisions without empirical input): **reconstruct the real driver distribution from the
   session CSVs first.** The (a)/(b)/(c) choice is Matt's, made on measured evidence, framed in
   product language — not a number you pick.
3. **Do not pick the approach yourself.** Present (a)/(b)/(c) to Matt **in user-visible terms,
   with benefits/trade-offs and a recommendation** (the binding CLAUDE.md rule — see "Decision
   points for Matt" below). If you catch yourself defaulting to (a) because it's "cleanest
   semantically," stop — that's an engineering preference, not a product call.
4. **Preserve the total-energy AGC unless Matt picks (a).** The total-not-per-band design gives
   mix-density stability (D-026). Approaches (b) and (c) keep it; only (a) changes it. Don't change
   it as a side effect of either other path.
5. **Never silently regenerate golden hashes.** `PresetRegressionTests` hashes depend on the AGC's
   steady-state behaviour. (a) and (b) **will** shift them across the 11 deviation-consuming
   presets. Surface the diff and the cause; regenerate only with Matt's explicit per-batch
   approval, after the M7 sweep, not before.
6. **`RelDevTests` is the contract; update it deliberately, never quietly** (rule 5 of "Read
   these first").
7. **Manual M7 validation is mandatory across the deviation-consuming catalog** (these `.metal`
   files read `*_dev` / `EnergyDev`): Arachne, Aurora Veil, Dragon Bloom, Ferrofluid Ocean,
   Gossamer, Kinetic Sculpture, Spectral Cartograph, Volumetric Lithograph, Fata Morgana, Nimbus,
   plus the shared material libs (`Dielectrics.metal`, `Metals.metal`). Verify the current list
   yourself (`grep -rlE "_dev|EnergyDev" PhospheneEngine/Sources/Presets/**/*.metal`) — it grows.
   No automated metric substitutes for Matt confirming the catalog reads right and nothing
   regressed.
8. **`KNOWN_ISSUES.md` (Resolved + commit) and `RELEASE_NOTES_DEV.md` updates are mandatory** per
   the Defect Handling Protocol, plus `ENGINEERING_PLAN.md` and (if a primitive's semantics change)
   `SHADER_CRAFT.md §14.1` and CLAUDE.md's "What NOT To Do".
9. **Stop and report** the moment any of these fire (CLAUDE.md): the reference sessions are missing;
   the measured distributions contradict this kickoff; the fix would require broader changes than
   the chosen approach authorised; a golden hash shifts you didn't expect; or you find yourself
   producing structure as a substitute for an answer.

---

## Staged plan

### AGC2.1 — Instrument & measure (commit, then STOP)

**Goal:** produce the evidence table that grounds Matt's decision, and leave it as a permanent
diagnostic artifact. No production code change.

1. Build a measurement harness (extend `PresetSessionReplay` per `docs/ENGINE/SESSION_REPLAY.md`,
   or a focused script that reads the reference sessions' `features.csv` / `stems.csv`). For each
   real session and each capture path, report:
   - **Per band** (`bass/mid/treble`, and ideally the 6-band): real centre (p50/mean), and
     `*Dev` firing rate (% of frames > a small ε), and signed `*Rel` stddev.
   - **Per stem** (`vocals/drums/bass/other`): raw `{stem}Energy` centre (p50), `*EnergyDev`
     firing rate, `*EnergyRel` stddev — to confirm/deny the manifestation-B nuance (does the
     per-stem EMA already centre the *deviation* near 0, even though the raw energy centres at
     ~0.30?).
   - Cross-path consistency (LF vs Spotify) so the decision isn't genre/path-specific.
2. Confirm the BUG-027 numbers reproduce (band `*Dev` < 3 %; stem energy ~0.30). If they don't,
   **stop and surface** — the premise has moved.
3. Write the table into the increment's working notes and `KNOWN_ISSUES.md` (extend the BUG-027
   evidence). Commit (`[AGC2.1] dsp: measure deviation-primitive centring across real sessions`).
   **Stop. Bring the evidence to Matt.**

### AGC2.2 — Decision gate with Matt (no code)

Present the three approaches **in product language** (see next section), with the AGC2.1 evidence
and a recommendation. Matt picks one (or "(c) for now, revisit"). File the decision in
`DECISIONS.md` — **grep `^## D-` for the next free number first** (D-144 is the current max; D-145
is claimed by the beat-grid project though its header may not be landed yet → next NEW number is
likely **D-146**, but verify). Record the chosen approach, the evidence, and the rejected options.

### AGC2.3 — Fix (test-before-fix)

Implement the chosen approach. **Write the failing regression test first, watch it fail, then fix.**
- New automated gate (from KNOWN_ISSUES verification criteria): *on a recorded bass-dominant
  fixture, the chosen "above-average bass" primitive fires on ≥ 20 % of frames.*
- Update `RelDevTests` to the new semantics if the pivot/derivation changed — visibly, with the
  rationale in the diff.
- Keep manifestation A and B coherent: if you fix the band pivot, decide explicitly whether the
  stem raw-energy path (B) is fixed in the same increment or recalibrated per-consumer, and say so.

### AGC2.4 — Validation (full sweep + catalog M7)

- Full engine suite green. App build green.
- `PresetRegressionTests` golden hashes: surface every shift with its cause; regenerate only with
  Matt's approval.
- **Matt M7 across the deviation-consuming catalog** on a multi-track session, both paths: each
  preset reads as appropriately reactive; none regresses. (Sample-then-expand is acceptable if
  Matt prefers — propose Dragon Bloom + Nimbus + Aurora Veil + Volumetric Lithograph as the
  sample, since their authors will catch a regression fastest.)

### AGC2.5 — Release notes & close

`KNOWN_ISSUES.md` BUG-027 → `Resolved` + commit hash + ticked verification boxes;
`RELEASE_NOTES_DEV.md` new entry naming every affected preset; `ENGINEERING_PLAN.md` increment
rows; `SHADER_CRAFT.md §14.1` updated if `*Dev` semantics changed (and if so, soften or retire the
"prefer signed `*Rel`" guidance accordingly). Closeout report per CLAUDE.md. Commit locally to
`main`; **do not push without Matt's explicit "yes, push."**

---

## Decision points for Matt (AGC2.2 — frame in product language)

> The CLAUDE.md binding rule: Matt is product/design lead. Each option must say **what the user
> sees/feels**, with benefits/trade-offs and a recommendation he can ratify without doing
> engineering math. The phrasings below are a starting point — sharpen them with the AGC2.1
> evidence (e.g. "today the bass 'punch' signal fires on 2 % of frames; option B raises it to
> ~X %").

**The question:** *Today, the visual cue that means "this band just hit harder than usual" almost
never fires except for whichever band is loudest. Should we fix that in the engine, and how
aggressively?*

- **(a) Give every frequency band its own loudness reference.** *What Matt sees:* every preset that
  reacts to per-band punch (bass thumps, cymbal sizzle, vocal swells) gets livelier and more
  even-handed across the whole catalog, on all music. *Trade-off:* this changes the baseline
  "feel" of every existing preset — their certified reference frames all shift, so all ~11 presets
  need a fresh look from you, and we re-bank every regression snapshot. Most thorough, biggest
  blast radius.
- **(b) Keep the current loudness machine, but teach the "above-average?" test where each band
  actually sits.** *What Matt sees:* the same liveliness win as (a) — quiet bands' punches start
  registering — with less risk of shifting the overall look, because the underlying loudness/zoom
  behaviour is untouched. *Trade-off:* still shifts golden hashes and still wants a catalog M7,
  but the visual change is more contained. **(Provisional recommendation, pending AGC2.1 — best
  liveliness-for-risk balance.)**
- **(c) Change nothing in the engine; document the limitation and route authors to the signal that
  already works.** *What Matt sees:* no change to any current preset; we write down that the
  positive "above-average" signals are only reliable for the dominant band and steer every future
  preset to the signed version (Dragon Bloom and Nimbus already do this). *Trade-off:* zero risk,
  zero regression — but the limitation stays forever and every new author has to remember the rule.
  **(Safe fallback if the catalog-wide M7 blast radius of (a)/(b) isn't worth it right now.)**

A real fourth option is **"(b) now for the FeatureVector path, (c) documented for stems"** or any
split — the AGC2.1 evidence may show manifestation B is already adequately centred via the
per-stem EMAs, in which case only A needs an engine change. Bring the split to Matt explicitly.

---

## Done-when (from KNOWN_ISSUES verification criteria + protocol)

- [ ] **AGC2.1 evidence table** produced from ≥ 2 real sessions across both capture paths and a
      spectrally varied track set; BUG-027 numbers reproduced or the premise-shift surfaced.
- [ ] **Matt has chosen** (a)/(b)/(c)/split on that evidence; the decision is filed in
      `DECISIONS.md` (next free D-number).
- [ ] **Automated:** on a recorded bass-dominant fixture, the chosen "above-average bass" primitive
      fires on **≥ 20 %** of frames (vs ~2 % today). *(Skip only if Matt chose (c) — then the gate
      is "the signal-liveness doc + cheat-sheet steer authors away from `*Dev`.")*
- [ ] **Automated:** `RelDevTests` pass (or are deliberately updated to the new semantics with
      Matt's sign-off).
- [ ] Full engine suite green; app build green.
- [ ] `PresetRegressionTests` golden hashes: no drift, OR every shift surfaced and Matt-approved.
- [ ] **Manual M7:** Matt confirms the deviation-consuming catalog reads as appropriately reactive
      and nothing regressed, on both paths.
- [ ] `KNOWN_ISSUES.md` BUG-027 marked `Resolved` (commit hash); `RELEASE_NOTES_DEV.md`,
      `ENGINEERING_PLAN.md`, and (if semantics changed) `SHADER_CRAFT.md §14.1` + CLAUDE.md updated.
- [ ] Closeout report filed. Local commit on `main`; not pushed without "yes, push."

---

## What NOT to do

- **Do not re-open cold-start transient rejection** (the shelved `AGC.1` approach). The cause is
  the 0.5 pivot vs total-energy normalisation, not a transient.
- **Do not pick (a)/(b)/(c) yourself or present it as an engineering menu.** Measure, then frame it
  for Matt in product terms with a recommendation (binding CLAUDE.md rule).
- **Do not break the total-energy AGC** as a side effect of (b) or (c). Only (a) touches it.
- **Do not silently regenerate golden hashes or quietly edit `RelDevTests`** to get green.
- **Do not synthesise the measurement audio.** Use the recorded reference sessions (Failed
  Approach #27); if they're missing, ask Matt to record real ones.
- **Do not collapse the multi-increment protocol.** P2 + catalog-wide blast radius; the decision
  gate is the point.
- **Do not forge ahead past a contradiction.** If AGC2.1 shows the distributions differ from this
  kickoff, stop and report — the premise moved and the plan needs Matt.
