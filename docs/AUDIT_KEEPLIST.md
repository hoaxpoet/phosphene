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
  QualityReelAnalyzer, UtilityCostTableUpdater, InstrumentFamilyDumper (IFC.5 per-family
  activity diagnostic — the ad-hoc surface for eyeballing family firing on a clip).

**Intentional dead-looking code (gated dev instrumentation — keep):**
- IOI histogram + `dumpHistogram` — DSP.1 baseline capture, gated behind `BEATDETECTOR_DUMP_HIST=1` (D-075).
- `ARACHNE_DIAG` / `ARACHNE_M7_DIAG` blocks — opt-in instrumentation, compiled only with `-D` flags.
- `includeMilkdropPresets` setting — placeholder until Phase MD ships.

**Retained history (keep — not dead weight):**
- `archive/` — old CLAUDE snapshots, architectural blueprints, V4 audits, and `electron-prototype`.
  The prototype is the primary-source artifact behind CLAUDE.md's Audio Data Hierarchy rule ("Learned
  in the Electron prototype and validated across every preset since"). swiftlint-excluded on purpose;
  slimming it is a deferred repo-size decision (Matt owns) — NOT an audit delete.

## Removed 2026-06-14 (D-163 follow-up — decision-backed, not "no references found")

Deleted because the path each served was abandoned by an explicit decision (not an empty reference
search — that signal is what produced this doc's false positives):
- CoreML stem toolchain (`tools/convert_stem_model.py`, `tools/test_stem_model.py`) — D-009 rejected
  CoreML. The live stem path (`extract_umx_weights.py` → `.bin`) is unaffected; the
  `tools/test_umx_weights.py` constants comment was updated.
- `Scripts/convert_beatnet_weights.py` — last BeatNet-derived artifact (D-077 pivot; weights dir
  already gone). The BeatNet section in `docs/CREDITS.md` was historicized to match.

## Unconfirmed — verify with Matt before cutting

- Inception-era spikes (`tools/audio-capture-test.swift`, `tools/audio-tap-test.swift`) — not compiled
  by any target and the capture-method decision shipped, BUT the only "unused" signal is no-references,
  which is exactly what misfired above. Could be kept probes. Ask before cutting.

## Before you delete anything

1. Is it an `executableTarget`? → it is a tool; check its `// STATUS:` marker. Not dead.
2. Is it a preset? → check `certified` in its `.json` sidecar + `git log`. Certified = keep.
3. Does a doc say it was "already removed"? → verify on disk; docs drift.
4. Still think it is dead? → it is on the "genuinely dead" list above, or raise it with Matt. Do not
   cut off inference alone.
