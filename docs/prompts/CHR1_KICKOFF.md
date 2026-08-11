# Increment CHR.1 — Stave: measurement, references, design doc

**Type:** docs (preset design; no shader, no sidecar, no engine code)
**Phase:** MD.6 (active per MD.0 / D-215) · inspired-by uplift #8 of 10 toward the C′ 10+10
first-release bundle (D-114 / D-115-as-amended)
**Inspiration source:** `Martin - charisma` — butterchurn built-in at
`~/mdrender/builtins/Martin - charisma.json`, rendered still + GIF in `~/mdrender/gallery/`
**Backlog:** this is CHR.1 of the 4-increment plan in `docs/presets/STAVE_PLAN.md`
(in-repo, delivered alongside this prompt — read its §0 for the concept rationale, which is
not repeated in full here)

**Objective.** After this session there exists a committed
`docs/presets/STAVE_DESIGN.md` and a curated, lint-clean
`docs/VISUAL_REFERENCES/stave/` folder, and three questions have **measured** answers from
real session captures: (1) are the four stems decorrelated enough on real music to read as
four separate voices, (2) does the beat-grid surface in buffer(5) populate on the pass shape
this preset will use, and (3) does the CPU-side history-ring default survive contact with the
measured stem-feature update behaviour. No `.metal`, no `.json`, no engine source change.
The name "Stave" is the DECISION-NEEDED #1 default from the backlog — see §10; file under it
unless Matt has said otherwise by session start.

**The concept, one sentence (Gate 1 form, to be refined by measurement, not replaced):**
Four luminous traces — one per stem — are drawn live across a beat-ruled dark field, each
plotting its own instrument's energy deviation, so the listener sees drums, bass, vocals and
the rest as four voices moving against the bar grid, converging and diverging as the
arrangement does.

**Why this concept was chosen (context, so the session doesn't re-litigate it):** it is
signal-plotting — the marks on screen *are* the audio. It cannot fail the two gates that
killed the last two candidates (a self-running movie; an autonomous medium the music can only
nudge), because there is no scene and no medium: silence flatlines the traces, which is
correct behaviour. The D-121 divergence axis is the dominant motion model — the source draws
decorative one-signal Lissajous curves, identical in species on every track; Stave draws four
per-stem plots on a beat-locked grid, different on every track. Milkdrop structurally cannot
do this (no stems, no beat grid); it is the most literal possible use of the capability gap.

---

## 2. Skill invocations

- `preset-session` — at session start. This is a preset increment even though docs-only:
  the skill's audio-data hierarchy and session-start checklist govern the driver table you
  will write in the design doc.
- `closeout` — at the end, before any commit is called final.
- **Not** `shader-authoring` — no MSL is written this session. If you find yourself wanting
  it, you have exceeded scope.

---

## 3. Read first

In this order:

1. `docs/presets/STAVE_PLAN.md` §0 (the concept, capability mapping, source mechanics table,
   and the pre-answered history-mechanism question).
2. `docs/MILKDROP_STRATEGY.md` §13 (the operative Phase MD workflow — gallery pick →
   design-before-code → D-116 discipline → M7 + D-121).
3. `docs/presets/WITCHLIGHT_DESIGN.md` — the structural template for the doc you are writing,
   **especially §2 (the measurement section)**, which is the shape task 3 must produce.
4. `docs/SHADER_CRAFT.md` §2.0 (concept-viability gate) and §12.6 (discipline rule + D-121
   side-by-side requirement).
5. `PhospheneEngine/Sources/Shared/SpectralHistoryBuffer.swift` — header comment only (the
   buffer(5) layout: beat_times[16], downbeat_times[8], bpm, lock_state, tonal_fifths rings).
6. `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift` — the `StemFeatures` struct
   block (floats 1–40: per-stem energy/rel/dev/onset_rate/centroid/attack_ratio/slope).
7. `docs/ENGINEERING_PLAN.md` §Phase MD → MD.6 done-when (the gates CHR.3 will be held to —
   the design doc must not promise anything that can't clear them).
8. `docs/VISUAL_REFERENCES/witchlight/README.md` — the annotation convention, including how
   the source render is used as simultaneous positive register anchor and path anti-reference.

Do **not** read `MILKDROP_STRATEGY.md` §§1–12 (historical), `MILKDROP_ARCHITECTURE.md`, or
any transpiler-era material.

---

## 4. Pre-flight invariants

Each failed check stops the session before task 1.

1. Fresh branch off current `origin/main`: `claude/chr1-stave-design`. `git status --porcelain`
   clean before task 0 — with one allowed exception: `docs/presets/STAVE_PLAN.md` and
   `docs/prompts/CHR1_KICKOFF.md` may be present untracked (they are delivered into the
   working tree alongside this prompt). Task 0 commits them; nothing else may be dirty.
   **If `docs/presets/STAVE_PLAN.md` is missing from the working tree, stop and report —
   do not reconstruct it from memory or from this prompt's summary of it.**
2. `swift test --package-path PhospheneEngine --filter DocIntegrityTests` green on the branch
   point. Red → that is a DOC.6 rotation problem, not this session; report and stop.
3. `~/mdrender/builtins/Martin - charisma.json` exists, and
   `~/mdrender/gallery/Martin - charisma.png` + `.gif` exist (the register anchor artifacts).
4. `~/Documents/phosphene_sessions/` contains ≥ 3 session capture directories each carrying
   `stems.csv`, `features.csv`, `raw_tap.wav`, and `session.log` (verified present as of
   2026-08-11 — e.g. `2026-08-10T17-34-29Z`). If fewer than 3 *qualifying* captures exist
   after task 1's inventory, stop and ask Matt to record what's missing rather than measuring
   on an unrepresentative set.
5. `docs/presets/STAVE_DESIGN.md` and `docs/VISUAL_REFERENCES/stave/` do not exist yet.
   If a differently-named variant exists, Matt answered DECISION-NEEDED #1 — use his name
   everywhere this prompt says Stave.

---

## 5. Tasks

### Task 0 — Land the plan + prompt docs

`git add` and commit `docs/presets/STAVE_PLAN.md` and `docs/prompts/CHR1_KICKOFF.md` as the
branch's first commit, so every in-tree reference this session makes resolves for future
sessions and for DocIntegrity link checking.

**Done when:** both files tracked; `swift test --package-path PhospheneEngine --filter
DocIntegrityTests` still green.

### Task 1 — Capture inventory and selection

Inventory `~/Documents/phosphene_sessions/`: for each capture, note duration, source type
(live capture vs local file — `session.log` says), and musical register (read the log's track
metadata; listen to `raw_tap.wav` spot-checks if ambiguous). Select **three** spanning
registers: one dense full-band mix, one electronic/rock local file, one sparse acoustic or
jazz. Prefer recent captures (post-DYN.7, so the mood/dynamics fields reflect current code).
The `fixturegen-so_what` and `fixturegen-love_rehab` directories are known route-coverage
fixtures — usable if they qualify, but at least one selection must be a full-length real
session, not a fixture clip.

**Done when:** a three-row selection table (capture id, duration, source type, register,
why chosen) is written — it becomes design-doc §2.0.

### Task 2 — Beat-grid surface verification

On the three captures, verify the buffer(5) beat surface this preset will consume:
`beat_times[16]` and `downbeat_times[8]` populate (not all-infinity), `bpm` nonzero, and
`lock_state` reaches locked, for the planned-session path; and characterize the reactive-mode
fallback (live capture without a BeatGrid: `bpm 0` — the gridlines must then derive from the
`beat_phase01` ring instead). Also verify **binding reach**: the SpectralHistoryBuffer header
says buffer(5) is bound unconditionally in *direct-pass* encoders — confirm from
`RenderPipeline.swift` (read, don't modify) that the `feedback` + `particles` pass shape this
preset will use can read it, or name the CPU-side alternative (the `ParticleGeometry` tick
already receives beat data CPU-side on that template — cite how Witchlight/Meniscus got beat
timing and match it).

**Done when:** design-doc §2.1 states, with evidence per capture: grid available yes/no per
path, the reactive fallback spec, and where this preset reads beat data from (GPU buffer(5)
vs CPU tick), citing the precedent preset that proves the chosen path.

### Task 3 — The load-bearing measurement: per-stem liveness and decorrelation

The concept lives or dies here. From the three captures' recorded per-frame stem features
(`stems.csv`; if a needed column is absent, replay `raw_tap.wav` through the production
pipeline the way `AGC3RealAudioReplayTests` does — measure the real pipeline, never synthetic
audio, FA #27):

a. **Per-stem liveness.** For each stem × capture: p5/p50/p95 and range of `x_energy_rel`
   and `x_energy_dev`. Known traps to check against, not assume: D-185 measured near-flat
   mid/treb deviations on real music; WL.1 measured `vocalsPitchConfidence` nonzero on 4.5 %
   of live frames. A stem whose `energy_rel` excursion is visually negligible at trace scale
   is a dead trace — name it.
b. **Cross-stem decorrelation.** Pairwise correlation of the four stems' `energy_rel` series
   per capture (windowed, not whole-track — a chorus correlates everything; the question is
   whether *sections* exist where the voices separate). If drums/bass/other track each other
   above ~0.9 through most of a dense mix, four traces collapse into one visually.
c. **Preset-facing latency.** Pick sharp audible events (a drum hit at a known timestamp in
   `raw_tap.wav`); measure the lag to the corresponding movement in the recorded stem
   features, per path (live capture vs local file). TRK.2 measured 5–10 s on the *tracker*
   path for live stems — what matters here is what the *preset-facing* features see and when.
   A multi-second live lag doesn't kill the concept (local files are the primary session
   type) but it must be in the doc as a stated limitation, not discovered at M7.

**Done when:** design-doc §2.2 carries the tables and a one-line verdict per capture:
**four traces** / **three traces + vocals-gated fourth** / **re-scope**.

### Task 4 — HARD STOP if the verdict is re-scope

If task 3's verdict on ≥ 2 of 3 captures is that the voices do not separate: **stop and
report.** Do not write a design doc around a failed premise, and do not spend rounds tuning
the amplitude mapping to force separation — §2.0's prescribed response to a failed concept
gate is re-scope with Matt, not iteration (the D-102 / FA #58 lesson). Report the tables,
the failure shape, and 2–3 re-scope directions (e.g. two traces — drums + everything-melodic;
or trace-count driven by arrangement density) as material for Matt's call.

Otherwise: state "task 4 gate passed" in the log and continue.

### Task 5 — History-mechanism confirmation

Confirm the backlog's pre-answered default: the `ParticleGeometry` class keeps its own
CPU-side per-stem rings (4 × ~480 samples, the `WitchlightStroke` trail pattern) — no
SpectralHistoryBuffer extension, no GPU-contract change. The check: the measured stem-feature
update rate from task 3 supports a smooth trace at the design's scroll speed (state the
screen-seconds window; ~8 s matches buffer(5)'s ring convention and the source's echo decay).

**Done when:** design-doc §architecture names the mechanism and ring parameters. If the
default is overturned (it should not be — overturning means the update rate is too coarse
for any CPU ring, which would also kill a GPU ring), file the infra increment as **CHR.1b**
with its own scope in the EP, do NOT build it this session, and note that CHR.2+ renumber
behind it.

### Task 6 — Reference curation

Curate `docs/VISUAL_REFERENCES/stave/` per D-064 / D-065 / D-066 (naming
`NN_<scale>_<descriptor>.(jpg|png)`, `_AIGEN` suffix if any generated image is used,
license-verified positives per the WL.1 precedent):

- `00` — the source render still (from `~/mdrender/gallery/`), annotated per the Witchlight
  convention as **positive on register** (dotted trace luminance, sparkle-grid dark field,
  echo smear, trace-on-black composition) and **anti-reference on path and coupling** (the
  Lissajous curve species and the single-full-mix-signal motion).
- 3–5 positives across the registers the design needs: long-exposure oscilloscope
  photography, seismograph/polygraph strip charts, multi-channel chart recorders, music
  engraving/stave imagery. Each earns its place by isolating one mandatory trait.
- Anti-references as needed — at minimum one for "graph paper" (a grid that reads as static
  chrome rather than as the beat) and one for "EKG screensaver" (clinical trace rendering
  with no musical life).
- README with mandatory-traits table.

**Done when:** `swift run --package-path PhospheneTools CheckVisualReferences` reports zero
warnings for the folder. Do not commit the butterchurn JSON or any source preset file into
the references folder (D-116 bullet 4 — renders of it are fine, the file is not).

### Task 7 — Write `docs/presets/STAVE_DESIGN.md`

WL.1 structure. Sections, with the increment-specific content each must carry:

1. **Concept + musical role** — the Gate 1 sentence, refined by task 3's verdict (if the
   verdict was three-traces+gated, the sentence says so — the doc describes what will ship,
   not the aspiration). D-121 divergence axis stated: dominant motion model, with the
   two-track demonstration (source: same curve species on any track; Stave: different traces
   per track and per instrument) named as the planned side-by-side evidence for CHR.4.
2. **§2 Measurement** — tasks 1–3 and 5 verbatim (selection table, grid verification, stem
   tables + verdicts, latency findings, ring parameters). This section is the increment's
   most reusable output; write it for the next author, not just this preset.
3. **Drivers table** — per D-026, deviation primitives only, never absolute energy:
   trace *y* = `x_energy_rel` centred on the trace's rest line (silence = flatline at rest,
   by construction); trace hue = shared `tonal_fifths` base with a fixed per-stem offset;
   gridlines from beat_times (or the task-2 fallback), downbeats weighted heavier; backdrop
   tint = valence/arousal, slow and subordinate; trace alpha rides overall volume (the
   source's own `modwavealphabyvolume` behaviour, honoured). Every row a QG.1 route
   candidate with a named CHR.3 response band (QG.5).
4. **Motion model + temporal contract** — scroll speed in screen-seconds (stated number);
   the one-frame driver→trace response, with the arithmetic that makes the MEN.3e
   medium-lag class structurally moot for this preset — *state it explicitly so CHR.3's
   M7 has it on hand*; what changes at section scale (the arrangement-density observation
   from task 3b, if the data supports one).
5. **Three-part bar.**
6. **Flash budget** — dotted traces on a dark ground is a low-flash concept; state the
   ceilings now (default to the WL.2 measured envelope: 0.00 flashes/s, peak full-frame
   mean luma ≤ 0.35, max Δluma/frame ≤ 0.06) unless a measurement argues otherwise. CHR.3
   builds the harness against these numbers from day one (the Meniscus lesson — D-157 gate
   existed only from cert; not again).
7. **Silence + degraded behaviour** — flatlines at rest lines on a calm non-black field;
   what the preset shows during the D-019 warmup; reactive-mode grid fallback per task 2.
8. **Grounding audit** — per the WL.1 convention; any rating ≤ 3 is surfaced in the closeout
   for Matt, never silently resolved.
9. **Registration plan** — the CHR.3 checklist pointer: family `waveform`,
   passes `["feedback","particles"]`, `feedback_pixel_format`, `inspired_by` block to the
   §13 schema (`source_form`: butterchurn built-in; `sha256` of the JSON actually read),
   `ParticleGeometryRegistry` (D-097), count 28 → 29, orchestrator metadata, QG.1 routes +
   QG.5 bands, flash harness membership, golden-or-exempt per the black-ground particle
   precedent (check Filigree/CymaticSand and match).

**Done when:** doc committed; every claim in §2 traceable to a table in it; no section
promises anything MD.6's done-when can't hold CHR.3 to.

### Task 8 — File the decision

File the concept + divergence-axis decision in `docs/DECISIONS.md` — next free D-number
(re-derive: `grep -ho '^## D-[0-9]*' docs/DECISIONS.md docs/DECISIONS_HISTORY.md | sort -t- -k2 -n | tail -1`;
216 was the next free number as of MD.0 but parallel sessions consume them; DocIntegrityTests fails on
holes and duplicates). Content: the Gate 1 sentence, the D-121 axis, the task-3 verdict, the
history-mechanism call, and the Waveform-scaffold disposition question flagged as pending
(DECISION-NEEDED #2 in the backlog — Matt's call at CHR.4, not now).

**Done when:** entry exists; DocIntegrityTests green.

### Task 9 — Closeout

Invoke the `closeout` skill; produce the 8-part report with the verbatim
`Scripts/closeout_evidence.sh` block as §2. Increment-specific additions: the task-3 stem
tables and verdicts verbatim; the task-4 gate statement; any grounding rating ≤ 3; the
CHR.2 carry-forward (the look-spike question CHR.2 must answer first: *do four traces read
as four instruments* — with the fixtures named).

---

## 6. Do NOT

- **No `.metal`, no `.json` sidecar, no engine source change.** Docs, references, measurement
  harness reads only. If a measurement needs code, it is an env-gated diagnostic test or an
  offline script — never a production change.
- **Do not extend `SpectralHistoryBuffer` or any GPU contract.** The 706 reserved floats do
  not fit 4×480 rings; the CPU-ring default exists precisely to avoid this. Overturning the
  default files CHR.1b; it does not build it (infra is never bundled — skill invariant).
- **Do not measure on synthetic audio.** FA #27. Real captures or replay of real
  `raw_tap.wav` through the production pipeline only.
- **Do not tune anything to make the stems decorrelate.** Task 3 measures; task 4 stops.
  Forcing separation via amplitude gain is the D-102 pattern with extra steps.
- **Do not touch `Waveform.json`** or anything about the Waveform scaffold (DECISION-NEEDED
  #2 is Matt's, at CHR.4).
- **Do not commit any butterchurn JSON or `.milk` content** (D-116 bullet 4; the PUB.1
  `source.milk` deletion is the precedent). Rendered stills are fine.
- **Do not add autonomous motion to the design.** No drift, no ambient animation, no
  self-running background life beyond the slow mood tint. The traces' motion *is* the
  signal; a design line that adds motion "so it isn't boring in quiet passages" is the
  movie failure this source was chosen to avoid. Quiet passages flatlining IS the design.
- **Do not resolve the preset name beyond applying the default** (§10).

---

## 7. Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
```

Increment-specific:

```
swift test --package-path PhospheneEngine --filter DocIntegrityTests
swift run --package-path PhospheneTools CheckVisualReferences
```

All expected green. The full engine suite must pass **unchanged** — this session adds no
production code, so any test movement is a scope violation, not a regression to fix.

---

## 8. Commit message templates

Small commits per logical step, local-only. Push only on Matt's explicit "yes, push".

```
[CHR.1] docs: land STAVE_PLAN.md + CHR1 kickoff prompt
[CHR.1] docs: capture selection + beat-grid surface verification (design §2.0–2.1)
[CHR.1] docs: per-stem liveness + decorrelation measurement (design §2.2)
[CHR.1] refs: stave/ visual references curated (source anchor + N positives)
[CHR.1] docs: STAVE_DESIGN.md — concept, drivers, temporal contract, flash budget
[CHR.1] decisions: D-2XX — Stave concept + D-121 divergence axis (fill number at run time)
```

---

## 9. Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim
`Scripts/closeout_evidence.sh` block as §2. Name additionally: the three capture ids and
their verdicts, the task-4 gate result, DocIntegrity + CheckVisualReferences results, and
the CHR.2 carry-forward question.

---

## 10. DECISION-NEEDED

**#1 — Preset name (carried from the backlog; default applies).** What should this preset
be called in the catalog?

- **Stave** *(recommended, and the default this prompt files under)* — a musical staff:
  beat-ruled lines with voices drawn across them. Names both the grid and the traces.
- **Quartet** — names the four-voices concept directly; reads slightly wrong on tracks where
  the vocals trace gates off.
- **Telemetry** — names the plotting register; colder, instrument-panel rather than musical.

**Default if no reply:** Stave. Renaming after CHR.1 is one mechanical commit; after CHR.3
registration it touches goldens — decide before CHR.3 if the default doesn't sit right.

*(DECISION-NEEDED #2, the Waveform-scaffold retirement, is deliberately NOT posed this
session — it is filed as pending in task 8 and goes to Matt at CHR.4, when its register is
actually served by a certified preset.)*
