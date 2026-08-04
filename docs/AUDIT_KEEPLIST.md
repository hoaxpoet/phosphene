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
  PRESET_SESSION_CHECKLIST), SoakRunner (run_soak_test.sh), TempoDumpRunner (dump_tempo_baselines.sh),
  **BeatBench** (the beat-sync benchmark — D-202 program measurement surface, driven by the
  `beatbench` skill and `Scripts/beatbench_*`), **TapCapture** (raw-tap capture for offline
  signal-health work), **ChainHealthAnalyzer** (ASH.2 / D-184, driven by
  `Scripts/analyze_session_chain.sh`, which exits non-zero unless the verdict is clean).

  *(The three bolded targets were added at RECON.4, 2026-08-03. They ship in `Package.swift` but
  had never been registered here — so this register, whose whole job is to stop a future audit
  cutting live tools on a no-references signal, was itself missing 3 of 14 targets. Separately:
  `ChainHealthAnalyzer/main.swift` is the one engine target with no `// STATUS:` marker, which the
  convention below requires — add it when that file is next touched.)*
- `retained-diagnostic`: ColdStartVerifier (cold-start phase-correction *runtime* reverted 2026-05-25;
  tool kept per "keep the tools", BEAT_SYNC.md §Cold-Start), BeatThisActivationDumper,
  QualityReelAnalyzer, UtilityCostTableUpdater, InstrumentFamilyDumper (IFC.5 per-family
  activity diagnostic — the ad-hoc surface for eyeballing family firing on a clip),
  CorpusCensusRunner (CENSUS.2 batch corpus-analysis harness — drives the existing pipeline
  over Matt's local archive to produce the calibration census; zero production importers),
  TonalDumper (TONAL.2 / D-178 — runs the production MIRPipeline TIV path over a clip or the
  CENSUS pilot to measure the tonal-signal distributions and set TonalAnalyzer's drive constants
  from percentiles; zero production importers, `TonalStats` pure math unit-tested).

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
4. **Is it a test fixture?** → **a source grep CANNOT prove a fixture unused.** `Package.swift`
   declares five fixture directories as *directory-level* `.copy(...)` resources —
   `Regression/Fixtures`, `Fixtures/beat_this_reference`, `Fixtures/fbs`,
   `Fixtures/panns_reference`, `Fixtures/route_coverage` — so every file inside is bundled
   wholesale and resolved at **runtime** by `Bundle.module.url(forResource:)`. Tests routinely
   build that name by interpolation, e.g.
   `AuroraTrackStartWarmupTests:23` → `"drumsdev_\(name)_2026-06-10T14-55-32Z"`. The literal
   filename appears **nowhere** in source, so `grep drumsdev_so_what` returns zero references
   for a fixture that four tests depend on. **The only valid check is running the suite.**
   *(Learned the hard way at RECON.1, 2026-08-03: three `fbs/` CSVs were deleted on a
   zero-references signal and took out all four `AuroraTrackStartWarmupTests` — the BUG-041
   regression guards. Restored at RECON.6.)*
5. **Is it a reference image or curated design material?** → it has no code consumer *by
   construction*, so "no references" is meaningless. Check the reference READMEs — e.g.
   `docs/VISUAL_REFERENCES/_pg_spares/` is Matt's alternate set, cited by three of them.
6. Still think it is dead? → it is on the "genuinely dead" list above, or raise it with Matt. Do not
   cut off inference alone.

**The pattern behind 4 and 5:** "no references found" is only evidence for code that is
*referenced by name in source*. For anything resolved at runtime, bundled by directory, or
consumed by a human, the signal is not just weak — it is systematically absent, and it will
read as a confident zero.

**The mirror-image error: references found, wrongly attributed.** A grep tells you a string
appears somewhere; it never tells you what *depends* on it. RECON's audit grepped fixture
names across the test tree, found `pyramid_song`, `yyz`, `money` and others, and concluded
the required-fixture set was "at least eight" with the fetch script covering only three —
which went into the RUNBOOK. Opening the consumers showed the required set was exactly the
three already present: the other names belonged to **BeatBench** (fixtures living outside
the repo, env-gated, own sha256 gate), to **env-gated diagnostic harnesses**, or to
**synthetic stub paths** in unit tests (`/private/var/tmp/money.m4a` against a test double).
Three unrelated systems, one grep, one wrong conclusion — and it was written into a doc
people follow before anyone opened a single hit.

So the rule runs both directions: **a count is not evidence.** Zero hits does not prove
unused; N hits does not prove required. Open the consumer and find out what it does with
the file — and if the claim is about what a build or test *needs*, the run is the arbiter.
Both errors above (deleting live fixtures on a zero, inventing missing ones on an N) came
from the same audit in the same week, and both were caught by running the suite.
