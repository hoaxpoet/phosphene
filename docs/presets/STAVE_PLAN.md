# Stave (charisma uplift) — plan + itemized backlog (CHR series)

**Repo home:** `docs/presets/STAVE_PLAN.md` (the `<NAME>_PLAN.md` convention — Nacre, Glaze,
Meniscus, Dragon Bloom precedents). A mirror exists in the Claude.ai project
(`claude/CHARISMA_BACKLOG.md`); **this repo copy is canonical** — Claude Code sessions read
this path, never the project mirror.
**Inspiration source:** `Martin - charisma` (butterchurn built-in, `~/mdrender/builtins/`).
**Phase:** MD.6 (active increment per MD.0 / D-215). Counts toward the C′ 10+10 first-release
bundle — this is inspired-by uplift **#8 of 10**.
**Preset name:** Stave (DECISION-NEEDED #1 default; see the kickoff prompt's §10).
**Authored:** 2026-08-11, this seat. Run each CHR.n as its own Claude Code session, in order.
The CHR.1 session prompt is `docs/prompts/CHR1_KICKOFF.md`, committed alongside this plan.

---

> ## ⚠ CHR.1 AMENDMENT (2026-08-11) — read before trusting §0 or CHR.2 below
>
> **CHR.1 ran and its central premise did not survive measurement.** This block records
> what changed; §0 and the CHR.2/.3/.4 bodies are left as authored, because they are the
> record of what was planned and why. Where they conflict with this block, this block wins
> (the `MILKDROP_STRATEGY.md` §12→§13 convention).
>
> **1. Four traces do not read as four voices.** Measured on 3 captures / 8 full-length
> tracks / 6 registers: **65–93 % of each trace's motion is the mix's shared loudness
> envelope** (rotation-control null ≈22 %), and the four collapse into two groups —
> `drums~bass` r +0.81…+0.98 and `vocals~other` r +0.80…+0.99, on every track in every
> register. Jazz was the *worst* case (Take Five, 93 %), not the best. §0's "four separate
> voices" sentence is therefore **falsified**, and CHR.1 task 1's own stated verdict option
> `re-scope` is the one that fired.
>
> **2. Matt's re-scope call: two traces — rhythm (`drums+bass`) vs melodic
> (`vocals+other`).** That grouping was then gated on its own terms and **passed**: median
> `r(R,M)` +0.756, divergence ratio 0.75 against a 1.45 independence null (so the gap between
> the traces is 49–96 % of the motion each trace makes), and `r` swings *within* tracks
> (+0.32 → +0.91), which makes converge-and-diverge measured behaviour rather than an
> aspiration. **The concept survives at two traces, not four.**
>
> **3. The driver decision is OPEN and blocks CHR.2.** Task 3c measured the preset-facing
> per-stem features at **≈5.4 s behind the audio** while the beat grid this preset rules its
> field with is time-aligned to ≈0.3 s. Filed as **BUG-086** and fixed in **BUG086.1**
> (separation period 5 s → 2 s, read start derived; latency now **2.5 s**) — but at 2.5 s the
> stem traces would still sit visibly off in-sync gridlines on an ~8 s plot. The alternative
> is a time-aligned 6-band split of the same rhythm-vs-melodic axis (lag ≈0.3 s, `r` +0.055,
> divergence 1.88) which separates *further* but trades instruments for registers and has no
> converge/diverge story. ~~**Matt's call; CHR.2 does not start until it lands.**~~
>
> > **✅ SETTLED by Matt 2026-08-13 — split the job.** Trace **position** from the
> > time-aligned band split (rhythm `subBass+lowBass`, melodic `midHigh+highMid+high`, each
> > EMA-centred, ≈0.3 s); trace **colour + weight** per-stem (`drums+bass` vs
> > `vocals+other`, ≈3.0 s). Recorded here at CHR.2 — the decision was carried only in the
> > CHR.2 session prompt, so CHR.2's own pre-flight check for it ("the amendment block
> > records the driver as resolved") could not pass against this file. Same failure mode as
> > item 6 below: **a decision that is not in git is not deliverable to a worktree session.**
> >
> > **CHR.2 ran and gated this driver.** Position half passed (median trace-to-beat offset
> > 0 ms); colour half **failed** (colour and position on the same mark are uncorrelated at
> > lag 0). See [`CHR2_LOOK_SPIKE_2026-08-14.md`](../diagnostics/CHR2_LOOK_SPIKE_2026-08-14.md).
> >
> > **✅ RESOLVED — Matt 2026-08-14, option D (D-216). The stem channel comes OFF the
> > traces and onto the field.** Traces carry only band-derived, in-time information;
> > stems move to a surface with no per-beat commitment (field tint / backdrop / grid
> > luminance) where 3 s of lag is invisible. **Accepted consequence: the preset can no
> > longer say "this trace is the drums" — the concept sentence is now *low against high,
> > ruled by the beat, in a room the stems tint.*** CHR.3 is unblocked; build to this.
>
> > **⚠ Also corrected at CHR.2:** item 2's divergence-ratio evidence (0.75 vs a 1.45 null)
> > and its "converge and diverge" reading do not survive — the statistic is dominated by
> > the rhythm/melodic amplitude mismatch. What survives is near-independence. And CHR.1
> > §4's common-mode table has shifted track labels; **"jazz was the worst case" is false**.
>
> **4. What CHR.1 did NOT produce.** No `STAVE_DESIGN.md`, no `docs/VISUAL_REFERENCES/stave/`,
> no `DECISIONS.md` entry — all correctly withheld under task 4's hard stop rather than
> written around a failed premise. CHR.1's measurement output is
> [`docs/diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md`](../diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md),
> written register-general so it outlives whichever driver is chosen. **CHR.1 must be re-run
> for its design-doc half** once the driver is settled.
>
> **5. Unverified and unchased, flagged for whoever resumes.** No live-streaming capture
> exists in the corpus, so CHR.1 task 2's reactive-mode (`bpm 0`) fallback is **still
> unverified** — the plan asked for one live-streaming capture and none was available.
> `beatsPerBar` is **not stable within a track** (Pyramid Song 1, Bleed 2, Giorgio 2 *and* 3,
> Billie Jean 4 in one segment and 3 in another), so §CHR.1's "heavier weight on downbeats"
> cannot assume a fixed bar length. And `beatPhase01` advances on 98.7–99.0 % of frames in the
> 2026-07-27 capture but only 13.4–16.7 % in the 2026-08 captures — one of those two
> behaviours is wrong.
>
> **6. Why this plan was not read during CHR.1.** It was delivered **untracked into the
> primary checkout**, while the session ran in a git worktree that never saw it, and the
> prompt variant the session actually received named the Claude.ai project mirror
> (`claude/CHARISMA_BACKLOG.md`) instead of this path and **omitted Task 0** (which exists in
> the committed `CHR1_KICKOFF.md` and would have tracked both files first). The on-disk
> pre-flight's "if `STAVE_PLAN.md` is missing from the working tree, stop and report" guard
> was also absent from the delivered variant, so nothing fired. **Committing these two docs is
> the fix; a plan that is not in git is not deliverable to a worktree session.**

---

## 0. The concept, and why it passes the gate the last two candidates failed

Matt's rejection criteria, now two deep: a preset must not run its own movie (Khazad-Dum), and
must have more than a little chance of dancing with the music (reaction-diffusion). Charisma
passes both **by construction**: the image is signal-plotting. Nothing is depicted; the marks on
screen *are* the audio. There is no autonomous system to nudge and no scene to watch — if the
music stops, the traces flatline, which is the correct behaviour, not a failure mode.

**The Phosphene concept (one sentence, Gate 1 form):** Four luminous traces — one per stem —
are drawn live across a beat-ruled dark field, each trace plotting its own instrument's energy
deviation, so the listener sees drums, bass, vocals and the rest as four separate voices moving
against the bar grid, converging and diverging as the arrangement does.

**The divergence axis (D-121, named now, not at cert):** dominant motion model. The source's
traces are decorative oscilloscope Lissajous figures — the same species of curve on any track,
driven by one full-mix scalar. Phosphene's traces are **four per-stem signal plots on a
beat-locked grid** — a capability Milkdrop structurally cannot have (no stems, no beat grid).
Same register (dotted luminous traces, sparkle-grid dark field, echo smear); different and
demonstrably music-derived motion. Trivially provable in the side-by-side: play two different
tracks — the source draws the same family of curves, ours draws visibly different traces per
track and per instrument.

**Source mechanics, measured from the JSON (record in the design doc as the register anchor):**
`wave_mode 4`, `wave_dots 1` (dotted traces), `additivewave 1`, `decay 0.5` + `echo_alpha 0.5,
echo_orient 3` (the mirrored smear), `modwavealphabyvolume 1` (trace alpha rides volume —
keep this; it is the source's own silence behaviour), 1 enabled custom wave (352 samples),
4 shapes, warp 709 chars / comp 5126 chars (the comp shader is the sparkle-grid field).
No `.milk` on disk; provenance per §13 (`source_form` = butterchurn built-in, sha256 of that JSON).

**Capability fit (why this source, per Matt's "best adapted to Phosphene" criterion):**

| Source fakes / lacks | Phosphene has, proven, today |
|---|---|
| One full-mix waveform | Four stems: per-stem energy / rel / dev / onset_rate / attack_ratio (StemFeatures floats 1–40, D-026/D-028) |
| No tempo model — grid is decoration | `beat_times[16]`, `downbeat_times[8]`, bpm, lock_state — **already GPU-visible in buffer(5)** (SpectralHistoryBuffer) |
| Random per-frame colour | `tonal_fifths` harmonic hue (D-178, proven in CR.1.2), also already in buffer(5) |
| Echo/decay smear via framebuffer hacks | Real `feedback` pass with declared pixel format |
| — | Mood (valence/arousal) rings in buffer(5) for slow backdrop tint |

**Family:** `waveform` (zero certified members — this fills a register *and* is the pack's most
capability-hungry waveform preset). **Rendering shape:** `["feedback", "particles"]` on the
Filigree/Witchlight/Meniscus template — `ParticleGeometry` emits the trace geometry CPU-side,
feedback carries the echo smear. Fifth consumer of the most-exercised template in the codebase;
no new render pass, no new fragment-buffer slot, no GPU-contract change.

**The one engineering question, pre-answered with a default:** four traces need per-stem
*history* (a trace is a time series), and StemFeatures is instantaneous. Do **not** extend
SpectralHistoryBuffer — 4 stems × 480 samples = 1,920 floats does not fit the 706 reserved
floats at [3390..4095], so that path is a GPU-contract change. Default: **the `ParticleGeometry`
class keeps its own CPU-side per-stem ring** (4 × ~480 floats, trivial) exactly as
`WitchlightStroke` keeps its trail — no engine surface touched. CHR.1 confirms or overturns
this with a measurement; overturning it makes an infra increment that must land separately
(never bundled into the preset session).

---

## The backlog

Four increments. Each is one Claude Code session. Do not merge them into fewer sessions —
WL bundled spike+authoring and paid for it across ten increments; MEN split them and certified
in five (still eleven rounds — see the do-nots that encode why).

---

### CHR.1 — Measurement, references, design doc (docs only; no shader, no sidecar)

**Skills:** `preset-session` at start (it governs planning of audio routing even pre-code);
`closeout` at end.

**Objective.** After this session there is a committed `docs/presets/CHARISMA_DESIGN.md` (name
TBD per DECISION-NEEDED #1 — file under the chosen preset name) and a curated
`docs/VISUAL_REFERENCES/<name>/` folder, and the three questions below have measured answers.
No `.metal`, no `.json`, no engine code.

**Read first:** `MILKDROP_STRATEGY.md` §13 · `SHADER_CRAFT.md` §2.0 + §12.6 ·
`docs/presets/WITCHLIGHT_DESIGN.md` (the structural template, esp. its §2 measurement section) ·
EP §Phase MD MD.6 done-when · `PhospheneEngine/Sources/Shared/SpectralHistoryBuffer.swift`
header · `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift` StemFeatures block.

**Tasks.**

1. **Measure per-stem feature liveness on real captures** (the WL.1 §2 discipline — this
   increment's most reusable output). On ≥3 real session captures spanning registers (one
   live-streaming, one local-file, one sparse/acoustic): for each of the four stems, the range,
   p5/p95 and time-structure of `x_energy_rel` / `x_energy_dev`, and whether the four stems are
   visibly *decorrelated* enough to read as four voices (if drums/bass/other track each other
   >0.9, four traces collapse to one visually — measure it, don't assume). Known traps to check
   against, already documented: mid/treb deviations near-flat on real music (D-185); live stem
   path latency (TRK.2 measured 5–10 s on the *tracker* path — measure what the *preset-facing*
   StemFeatures actually see and when); `vocalsPitchConfidence` nonzero on only 4.5% of live
   frames (WL.1). **Done when:** a table per capture per stem, in the design doc, with a stated
   verdict: four traces / three traces + vocals-gated fourth / re-scope.
2. **Verify the beat-grid surface.** Confirm `beat_times[16]` / `downbeat_times[8]` /
   `lock_state` populate on the same captures (they are written for the `instrument` family —
   confirm they're live for a `waveform`-family preset bound at buffer(5), which the header says
   is unconditional in direct passes; **confirm the same holds on the feedback+particles path**,
   since that is our pass shape). Decide the reactive-mode fallback (no BeatGrid → `bpm 0`):
   gridlines from `beat_phase01` ring instead. **Done when:** the fallback is specified in the
   design doc with the measured evidence.
3. **Settle the history mechanism.** Confirm the CPU-side ring default (§0) against the
   measured stem-feature update rate; state the ring length and sample rate the traces need
   (~8 s at 60 fps matches buffer(5)'s convention). **Done when:** design doc §architecture
   names the mechanism; if it overturns the default, a separate infra increment is filed as
   CHR.1b with its own scope and this backlog's numbering shifts.
4. **Curate references** per D-064/D-065/D-066: the source render + GIF as register anchor
   (positive on: dotted trace luminance, sparkle-grid field, echo smear, dark ground; **anti-
   reference on: the decorative Lissajous path and the single-signal motion**) plus real-world
   positives — long-exposure oscilloscope photography, seismograph/polygraph strips, music
   engraving/stave imagery if the name lands there. 3–5 references, annotated README, zero
   `CheckVisualReferences` warnings. **Done when:** lint green.
5. **Write the design doc**, WL.1 structure: concept + musical role sentence (§0 above, refined
   by the measurements) · drivers table (per-stem trace = `x_energy_rel` centered at the trace's
   rest line, per D-026 — never absolute energy; trace hue = `tonal_fifths` offset per stem;
   gridlines = beat_times, heavier weight on downbeats; backdrop tint = valence/arousal, slow,
   subordinate) · motion model + temporal contract (traces scroll at fixed screen-seconds —
   state the window; a trace responds within one frame of its driver, so the MEN.3e
   medium-lag question is structurally moot — *say so*, with the beat-period arithmetic) ·
   three-part bar · flash budget (dotted traces on dark ground: state ceilings now — peak
   full-frame mean luma and max Δluma/frame at the WL.2 values unless measurement argues
   otherwise) · silence behaviour (flatlines at rest lines, calm non-black field, source's
   `modwavealphabyvolume` honoured) · grounding audit · registration plan. **Done when:**
   doc committed; any grounding rating ≤3 is surfaced to Matt, not resolved silently.
6. **File the D-number** for the concept + divergence axis (next free — verify with the
   DocIntegrity grep; 216 was next at MD.0 but parallel sessions move it — the bare number
   here is deliberate, since writing it as a citation would reference a decision that was
   never filed and DocIntegrityTests rejects that).

**Do NOT:** open a `.metal` file · touch `Waveform.json` (see DECISION-NEEDED #2) · extend
`SpectralHistoryBuffer` or any GPU contract · commit any butterchurn JSON (D-116 bullet 4).

**Verify:** `swift test --package-path PhospheneEngine --filter DocIntegrityTests` ·
`swift run --package-path PhospheneTools CheckVisualReferences` · `swiftlint lint --strict`.

---

### CHR.2 — Motion-gated look spike (throwaway allowed; verdict before shading)

**Skills:** `preset-session`, `shader-authoring` (before any MSL), `closeout`.

> **⚠ AMENDED by the CHR.1 amendment block above.** The four-trace gate below is superseded:
> four traces were measured and do not separate. The gate is now the **two-trace** question,
> and **CHR.2 is blocked until Matt settles the driver** (stems at 2.5 s vs the time-aligned
> 6-band split). Text updated in place; the "four instruments" framing is retired, not deferred.

**Objective.** Answer, on the CHR.1 captures, before any material/shading work: **do two
traces read as rhythm versus melody — and does the gap between them read as the arrangement
pulling apart?** This is the Witchlight lesson (WL.2 carry-forward: "a motion-gated look-spike
answering the concept question before any shading — not a tuning round"), and the D-201/D-194
lesson that stills lie about the living result.

**Tasks.**

1. Minimal `ParticleGeometry` implementation: CPU history rings → **2** line-strip traces
   (rhythm = `drums+bass`, melodic = `vocals+other`, or the band equivalent if Matt picks the
   time-aligned driver), flat colour, no glow, no backdrop, no echo. Beat gridlines as plain
   verticals. **2 rings, not 4** — halves the §0 history footprint, which was already trivial.
2. Render against all CHR.1 captures. Include **Take Five** (the worst measured case, 93 %
   common mode) and **Giorgio by Moroder** (lowest excursion, p95−p5 ≈ 0.26–0.36, where a
   trace-amplitude floor is needed) — a spike that only looks good on the easy captures has
   not answered the gate.
3. **The gate, answered in writing with rendered evidence:** do the two traces read as two
   *voices* rather than two parallel copies of one line? Is the measured divergence — 49–96 %
   of each trace's own motion scale — actually **visible** at trace scale, and does it read as
   the band locking together and pulling apart? Does the grid read as *the beat* rather than as
   graph paper? **Do the traces land on the gridlines** (this is where the residual driver
   latency shows, and it is the reason the driver decision precedes this session)? One verdict
   per capture.
4. **Stop and report.** The verdict is Matt's gate. If it fails, §2.0's prescribed response is
   re-scope (trace count, layout, amplitude mapping) — not tuning rounds against a failed read.

**Done when:** verdict table + renders in the report; Matt has said go. Spike code may be
kept as the CHR.3 skeleton or discarded — either is fine; the *verdict* is the deliverable.

**Do NOT:** shading, bloom, echo, palette work (that is CHR.3 — resist making the spike
pretty) · more than one session (if the spike doesn't answer the gate in one session, that
is itself a finding for Matt).

**Verify:** render harness output attached; no production registration yet — no golden, no
sidecar, count stays 28.

---

### CHR.3 — Authoring: the full preset against the design doc

**Skills:** `preset-session`, `shader-authoring`, `closeout`.

**Objective.** `<Name>.metal` + `<Name>.json` registered and code-complete: the CHR.2 skeleton
carried to the design doc's visual register — dotted trace luminance, echo smear via the
feedback pass, sparkle-grid field, harmonic hue, downbeat-weighted grid — with routes declared
and gates green. `certified: false` at end of session, pending M7.

> **⚠ AMENDED by D-216 (Matt 2026-08-14).** Build to the CHR.2 verdict, not to the text below
> wherever they disagree:
> - **Traces carry band-derived, in-time information ONLY.** No per-stem channel on a trace —
>   not hue, not weight, not brightness. That pairing is what failed gate half 2.
> - **Stems drive the FIELD** — tint / backdrop / grid luminance — where a 3.0 s lag is
>   invisible. This is where `drums+bass` vs `vocals+other` now lives.
> - **The concept sentence is "low against high, ruled by the beat, in a room the stems
>   tint."** Not instrument voices. Do not reintroduce per-mark instrument identity.
> - **Per-trace gain normalisation is needed** — one fixed gain clips (Dance Yrself Clean).
>   Decide the trade against absolute-amplitude comparison explicitly.
> - **Dense grids read as graph paper** above ~150 bpm (Bleed: 22.9 lines per 8 s window).
>   Downbeat weighting cannot assume a fixed bar — `beatsPerBar` is not stable within a track.
> - **Bleed is a known, unfixable miss** (r +0.695, the two traces collapse). Do not spend
>   rounds on it.
> - Three spike defects are already solved in `StaveLookSpike.swift` — `packed_float4` vertex
>   stride, alpha-not-additive blending, 20 Hz plot + degenerate-segment guard. Lift them.
> - Plot on `time`, never `accumulatedAudioTime` (energy-weighted, ~12× slow, music-dependent).

**Tasks (compressed — the session expands from the design doc, which is authoritative):**

1. Registration per `docs/presets/NEW_PRESET_CHECKLIST.md`: sidecar with `family: "waveform"`,
   `passes: ["feedback", "particles"]`, `feedback_pixel_format` declared, `inspired_by` block
   per §13 schema (butterchurn `source_form`, sha256 of the JSON actually read), orchestrator
   metadata hand-authored, `ParticleGeometryRegistry` case (D-097). Count 28 → 29;
   `expectedProductionPresetCount` updated.
2. `audio_routes` manifest (QG.1/D-180) — **≥4** routes under the amended two-trace scope.
   **Per D-216 the route split is: 2 × trace amplitude (bands, fast) + grid/downbeat (fast)
   + stem-driven field tint (slow).** Not the ≥6 this line originally specified for four
   traces, and not a per-trace stem route. `RouteCoverageTests` green on the committed fixtures, or a red
   route filed as a defect — **never tune the floor** (QG.1/D-179).
3. QG.5 response bands on the four trace routes — each trace's excursion band stated and
   asserted, so "trace moves but too little to see" fails a test instead of an M7.
4. Flash budget measured against the design doc ceilings; `MultiPassFlashHarnessTests` render
   function + `PhotosensitivityCertificationTests.multiPassMeasured` membership in one commit
   (the Meniscus lesson: the D-157 gate exists from day one, not added at cert).
5. Golden regression entry (black-ground particle preset — check the Filigree/CymaticSand
   precedent for whether a golden is registered or exempted, and match it).
6. QG.2 render-comparison sheet at closeout.

**Done when:** full engine suite + app build + `swiftlint --strict` green; routes green;
flash measured inside budget; sidecar decodes (QG.7 now rejects unknown keys — the §13
`inspired_by` schema is the allowlisted form); closeout report with per-route firing evidence.

**Do NOT:** touch `Waveform.json` (DECISION-NEEDED #2 is Matt's, filed at cert not before) ·
add engine surfaces — if the preset needs one, that is a DECISION-NEEDED, stop · exceed the
design doc's temporal contract chasing "more motion" (the traces' motion *is* the signal;
if it looks dead, the driver mapping is wrong — go back to the CHR.1 table, don't add
autonomous animation. **Adding any self-running motion is the movie failure this preset was
chosen to avoid and is out of scope at any tuning depth.**)

---

### CHR.4 — Certification: live M7 + D-121 side-by-side

**Skills:** `preset-session`, `closeout`.

**Objective.** `certified: true`, or a documented rejection with the defect isolated by
measurement (the WL.2-e..g discipline: measure our frame against the source's numbers before
proposing any fix).

**Tasks.**

1. Matt's live M7 on real music — at least one dense mix and one sparse track (the **two-voice
   rhythm-vs-melodic** read is the concept, per the amendment block; a sparse track is where
   it's most legible, a dense one where it's most at risk). Add a **jazz** track: Take Five
   measured the highest common mode of the whole corpus (93 %), so it is the concept's genuine
   worst case, which neither "dense" nor "sparse" captures.
2. The D-121 side-by-side: our render next to the source's on the same track, plus **the
   two-track demonstration** (§0): source draws the same curve family on both tracks, ours
   draws different traces — that *is* the divergence rationale paragraph, with images.
3. On sign-off: cert flip, `FidelityRubricTests.certifiedPresets` membership,
   `expectedAutomatedGate` row at its measured value, CREDITS.md row, EP + RELEASE_NOTES_DEV
   entries, D-number cross-references.
4. File DECISION-NEEDED #2 (Waveform scaffold disposition) with Matt now that its register
   is served by a certified preset.

**Done when:** cert suite green; closeout filed; **inspired-by count reaches 8 of 10** toward
the C′ bundle — record the two remaining slots against the shortlist (`disconnected`,
`diamond cutter` — motion strips in `~/mdrender/_contactsheets/motion2.jpg`).

---

## DECISION-NEEDED (both are Matt's; neither blocks CHR.1 starting)

**#1 — Preset name.** The file, class and catalog name (source-named files contradict D-113;
see §13). Options, in product terms:
- **Stave** *(recommended)* — a musical staff: beat-ruled lines, voices drawn across it.
  Short, names both the grid and the traces, sits naturally beside Meniscus/Nacre/Skein.
- ~~**Quartet**~~ — **retired by measurement (CHR.1).** It named the four-voices concept, and
  there are two. Not a naming judgement; the thing it named does not exist.
- **Telemetry** — names the plotting register; colder, more instrument-panel than music.
**Default if no reply:** Stave. CHR.1 files under the default and renaming later is one
mechanical commit (before CHR.3 registration, free; after, it touches goldens).

**#2 — The Waveform scaffold.** `Waveform.json` ("64-bar FFT spectrum analyzer", uncertified,
last touched only by global sweeps) becomes fully superseded when this preset certifies — same
family, same register, strictly more capable. Retire at CHR.4 (the GBRETIRE/KSRETIRE shape,
count back to 28), or keep as the family's minimal second member for rotation variety.
**Recommendation:** retire at CHR.4; it is a scaffold, not a sibling. **Default:** no action
until Matt calls it — it costs nothing while it waits.

---

## Sequencing note

CHR.1 is runnable today; nothing upstream blocks it. The only cross-project collision to watch:
the RECON follow-up queue's zero-consumer capability deletions (Matt's 2026-08-03 call) — none
of the surfaces this preset uses (feedback, particles template, buffer(5), StemFeatures) is on
that list, and the scene-rendering cluster it does name (RMENV/IBL/SSGI) is one this preset
deliberately avoids. No conflict; proceed.
