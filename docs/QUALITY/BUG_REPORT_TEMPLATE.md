# Phosphene — Bug Report Template

Copy this template when filing a new defect in `KNOWN_ISSUES.md` or in a commit message. All fields are required for P0/P1; P2 requires all except "session artifacts" (provide when available); P3 may omit reproduction steps.

---

```
## BUG-XXX — [Short title]

**Severity:** P0 / P1 / P2 / P3
**Domain tag:** dsp.beat | dsp.stem | preset.fidelity | renderer | audio.capture | session.ux | perf | orchestrator | ml | docs
**Status:** Open | Diagnosed | Fix in progress | Resolved | Deferred | Won't fix
**Introduced:** [Increment ID or commit hash, if known]
**Resolved:** [Increment ID or commit hash; blank if open]

---

### Expected behavior

[One or two sentences. What should happen. Be specific — numbers, units, state names.]

### Actual behavior

[What actually happens. If it's intermittent, describe the frequency and triggering conditions. Include observed values where available.]

### Reproduction steps

1. [Step one — be concrete. E.g. "Connect Spotify playlist at https://open.spotify.com/..."]
2. [Step two]
3. [Observe: ...]

**Minimum reproducer:** [Shortest path to reproduce — single track, specific setting, or fixture file. "Any track" or "any Spotify playlist" if truly general.]

---

### Session artifacts

**Session directory:** `~/Documents/phosphene_sessions/<timestamp>/` (or "n/a — not yet captured")

Attach or reference the following (as applicable to the domain tag):

- `features.csv` — relevant columns and row range
- `session.log` — log lines around the failure (copy key lines below)
- `stems.csv` — relevant columns
- Contact sheet or screenshot path
- Diagnostic dump file (BeatThisActivationDumper output, histogram dump, etc.)
- Soak test report path

```log
[paste key log lines here]
```

---

### Suspected failure class

[One class from the taxonomy: algorithm | concurrency | api-contract | calibration | pipeline-wiring | resource-management | sample-rate | precision | test-isolation | sdf-geometry | render-state | regression | documentation-drift]

**Evidence for this class:** [One sentence. Why this class fits the observations.]

---

### Verification criteria

When this defect is resolved, the following must all pass:

- [ ] [Automated test or assertion — e.g. "`BeatGridUnitTests.test_halvingOctaveCorrection_doubletimeInput_halves` passes"]
- [ ] [Domain-specific artifact — e.g. "features.csv shows `lock_state=2` within 5 s on Love Rehab"]
- [ ] [Manual check where required — e.g. "Beats align to perceived kick drum at normal listening volume on Love Rehab and So What"]

**Manual validation required:** Yes / No
[If yes, describe what to listen for or look for. Subjective criteria belong here — not in automated tests.]

---

### Fix scope

[Brief note on whether this is a contained change or whether it may require architectural work. Used during triage to assign severity and process.]

### Related

- Decision: [D-XXX if applicable]
- Failed Approach: [#N if applicable]
- Increment: [increment IDs that are relevant]
```

---

## Notes on Completing the Template

**Expected vs. actual behavior** — state in terms of observable output, not implementation details. "Should reach PLANNED·LOCKED within 5 s" is a good expected behavior. "BeatGrid.computePhase should return values < 1.0" is an implementation detail, not an expected behavior.

**Session artifacts** — for beat-sync and stem defects, `features.csv` is the primary artifact. For render defects, a screenshot or contact sheet from `RENDER_VISUAL=1` is required. For crash/hang defects, include the crash log path.

**Verification criteria** — write these before the fix. A defect whose criteria were written after the fix was implemented has likely been under-specified. At minimum: one automated gate + one manual check for P0/P1 musical-feel defects.

**Failure class** — choose one. If two classes fit equally, choose the more specific one. "regression" is reserved for "previously worked, broken by a later change" — do not use it when the feature never worked.

**Trivial P1 collapse** — if filing a P1 that meets the criteria for single-increment treatment (< 5 lines, root cause obvious, no architectural risk), note this explicitly in "Fix scope" and get Matt's approval before collapsing steps.
