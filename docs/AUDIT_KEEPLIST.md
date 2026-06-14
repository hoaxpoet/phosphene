# Audit Keep-List — what looks dead but is deliberately kept

**Read this before flagging anything in this repo for deletion.** A 2026-06-14 over-engineering
audit flagged certified presets and a kept diagnostic tool as "dead" because the records did not
distinguish *active* / *retained-diagnostic* / *actually-dead*. This file is the first stop so that
does not recur. Convention recorded as **D-163**.

## The trap

The usual dead-code signal — "zero production importers" — is **structurally wrong** for two whole
classes of code here:

1. **Standalone tools / diagnostics** (`executableTarget`s). They are CLIs, not library code. They
   have zero production importers *by design*. That is not evidence they are unused.
2. **Certified presets that ship quietly.** A preset can be `certified: true`, planner-pickable, and
   untouched for weeks. "No recent commits" ≠ retired.

## The convention

Every `executableTarget` carries a `// STATUS:` marker near the top of its entry file:

- `active-tool` — wired into a Script / gate / checklist that runs regularly.
- `retained-diagnostic` — kept on purpose, run ad hoc (often tied to a premise whose *production
  runtime* was reverted; the *tool* stays).

If a file has a `// STATUS:` marker, it is not a delete candidate. If you still think it should go,
that is a product decision — raise it with Matt, do not infer it.

## Looks-dead-but-isn't register

**Certified presets — do NOT delete (`certified: true`, planner-pickable):**
- Murmuration (particles), Dragon Bloom (hypnotic), Fata Morgana (hypnotic). The RB.3 *memory*
  consolidation retired their *working-memory files* because they shipped — not the presets.

**Standalone tools (`executableTarget`s — zero production importers by design):**
- `active-tool`: CheckVisualReferences (visual-ref lint gate), PresetSessionReplay (mandatory per
  PRESET_SESSION_CHECKLIST), SoakRunner (run_soak_test.sh), TempoDumpRunner (dump_tempo_baselines.sh).
- `retained-diagnostic`: ColdStartVerifier (cold-start phase-correction *runtime* reverted 2026-05-25;
  tool kept per "keep the tools", BEAT_SYNC.md §Cold-Start), BeatThisActivationDumper,
  QualityReelAnalyzer, UtilityCostTableUpdater.

**Intentional dead-looking code (gated dev instrumentation — keep):**
- IOI histogram + `dumpHistogram` — DSP.1 baseline capture, gated behind `BEATDETECTOR_DUMP_HIST=1` (D-075).
- `ARACHNE_DIAG` / `ARACHNE_M7_DIAG` blocks — opt-in instrumentation, compiled only with `-D` flags.
- `includeMilkdropPresets` setting — placeholder until Phase MD ships.

## Genuinely dead (confirmed) — but deletion is a separate decision

These ARE dead, but per Matt (2026-06-14) nothing gets deleted off the audit that produced the false
positives above. List them, do not auto-cut:
- `Scripts/convert_beatnet_weights.py` — BeatNet abandoned at D-077; weights dir already gone.
  (ENGINEERING_PLAN_HISTORY claimed this was already removed; it is still on disk — corrected 2026-06-14.)
- Dead CoreML stem toolchain (`tools/test_stem_model.py`, `tools/convert_stem_model.py`) — D-009 removed the CoreML path.
- Inception-era spikes (`tools/audio-capture-test.swift`, `tools/audio-tap-test.swift`).
- `archive/` — old snapshots + electron prototype; unreferenced, swiftlint-excluded.

## Before you delete anything

1. Is it an `executableTarget`? → it is a tool; check its `// STATUS:` marker. Not dead.
2. Is it a preset? → check `certified` in its `.json` sidecar + `git log`. Certified = keep.
3. Does a doc say it was "already removed"? → verify on disk; docs drift.
4. Still think it is dead? → it is on the "genuinely dead" list above, or raise it with Matt. Do not
   cut off inference alone.
