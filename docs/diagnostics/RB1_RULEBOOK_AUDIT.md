# RB.1 — Rulebook Audit (verdict table)

**Date:** 2026-06-11 · **Increment:** RB.1 (audit-only; execution is RB.2, blocked on Matt's sign-off)
**Audit subject:** the four always-active / on-demand rule populations — CLAUDE.md Failed Approaches (FA), CLAUDE.md Do-NOT bullets (DN), CLAUDE.md sections (SEC), active `docs/DECISIONS.md` entries (D).
**Citation input:** REVIEW.1 rule-usage table (288 identifiers; `conv` = human/assistant conversation citations, the load-bearing signal; `total` includes file-dump inflation) + never-cited lists + correction-classification data. Citation *counts* only are reproduced here — no transcript content (public-repo constraint).
**Corpus window caveat (applies throughout):** transcript retention begins 2026-05-08. For any rule created before that (FA #1–#33, early D entries), "never cited" is weak evidence; such rows take `confidence: low` unless grep evidence independently settles the verdict.

---

## 1. Task 1 — Mechanical inventory

### 1.1 Populations and counts

| population | definition | count |
|---|---|---|
| FA | active numbered Failed Approach entries in CLAUDE.md | **49** (#1–4, #11, #15–18, #21–33, #39, #48–73) |
| DN | Do-NOT bullets: 57 in §What NOT To Do + 6 prohibition bullets embedded in other sections (numbered DN-58…DN-63 here) | **63** |
| SEC | `##`-level CLAUDE.md sections (each audited as a unit; §Cold-Start Phase Contract is a `###` subsection of SEC-6 and is verdicted inside that row) | **21** |
| D | active `## D-…` entries in docs/DECISIONS.md: 155 numbered (incl. D-076 reserved/abandoned) + 6 unnumbered `D-LM-*` (audit aliases D-901…D-906) | **161** |
| **total** | | **294** |

### 1.2 Mass measurements (method: `wc -w` × 1.35)

| file / section | words | est. tokens |
|---|---|---|
| CLAUDE.md (whole file, 494 lines) | 16,530 | **~22,300** |
| — §What NOT To Do | 3,607 | ~4,870 |
| — §Failed Approaches | ~8,000–9,400 (extraction estimate; entries are single very long lines) | ~11,000–12,700 |
| — §Authoring Discipline | ~4,000 (extraction estimate) | ~5,400 |
| docs/DECISIONS.md (on-demand, not always-loaded) | 94,982 | ~128,200 |

The FA + DN + Authoring Discipline sections jointly account for roughly **70–75 % of CLAUDE.md's always-loaded mass**.

### 1.3 Cross-check against REVIEW.1's identifier list

**Present in transcripts, absent from the current rulebook (already pruned — noted and skipped):**

- D-013, D-031, D-046, D-086, D-120 — confirmed present in `docs/DECISIONS_HISTORY.md` (moved at DOC.4 / earlier). Not audited.
- FA #14, #20, #34, #35, #36, #37, #38, #40, #41, #42, #43, #44, #45, #46, #47 — moved per the CLAUDE.md gap table (HISTORICAL_DEAD_ENDS / SHADER_CRAFT §13 / UX_SPEC §15 / RUNBOOK). Their transcript citations resolve via the gap table. Not audited.
- BUG-### identifiers — tracked in `docs/QUALITY/KNOWN_ISSUES.md`, not a rulebook population. Out of scope.

**Rulebook entries REVIEW.1's identifier extraction could not match:**

- All 63 DN bullets (unnumbered) — citation count **unmeasured** directly. REVIEW.1's key-phrase echo scan covers them indicatively (1 of 57 with zero echo). 52 of the 57 §What-NOT bullets duplicate or cross-reference a *measured* FA/D identifier, whose citation data drives their default.
- The 6 `D-LM-*` entries (unnumbered) — unmeasured.

**>15 % stop-rule assessment:** 69/294 (~23 %) of entries are not identifier-matchable, but the prompt pre-declares unnumbered Do-NOTs as expected-unmeasured ("citation count 'unmeasured', not zero"), and their verdicts below are driven by their measured parent identifiers or by grep evidence, not by absent citation data. The genuinely-unexpected unmatchable set is the 6 D-LM entries — **2 %**, well under threshold. Audit proceeds; this interpretation is recorded here for Matt's review.

**Enumeration variance note:** `grep -cE '^## D-' docs/DECISIONS.md` returns 162; per-header enumeration resolves 155 numbered + 6 D-LM = 161 distinct entries (the ±1 is a header-format variant around D-076's "(reserved, abandoned)" annotation). The verdict table uses the enumerated 161.

---

## 2. Task 2 — Verdict pass

Row format: `ID | one-line rule summary | citations (conv/total/sessions · last) | grep evidence | verdict | destination or gate spec | confidence`.

Verdict semantics per population: for FA/DN/SEC, KEEP = stays in always-loaded CLAUDE.md core. For the D population, DECISIONS.md is **not** always-loaded, so: KEEP = stays active **and** keeps a surfaced one-liner in the core (only rules of D-026's stature qualify); DEMOTE = stays active in DECISIONS.md (read on demand) or moves content to the named handbook; RETIRE = move to `DECISIONS_HISTORY.md` (the established convention for decisions; HISTORICAL_DEAD_ENDS.md is the destination for FA tombstones); MECHANIZE = a deterministic gate covers it (named).

“Consolidated” in a KEEP destination means the row shares one core slot with the named sibling — it is not an additional slot.

### 2.1 FA population (49)

| ID | rule summary | citations | grep evidence | verdict | destination / gate | conf |
|---|---|---|---|---|---|---|
| FA-1 | IIR 3-band energy-difference beat detection → machine-gun false positives | 0/2/2 · 06-10 | BeatDetector.swift is spectral-flux; no IIR detector in production; tempo = Beat This! (D-077) | RETIRE | HISTORICAL_DEAD_ENDS §ML/signal-processing; superseded by spectral-flux onsets + Beat This! | high |
| FA-2 | rising-edge accumulation defeated by IIR oscillation | 0/0/0 | same superseding architecture; never cited anywhere | RETIRE | same tombstone | high |
| FA-3 | per-bin spectral-flux thresholds intractable across genres | 0/0/0 | per-band P75 + cooldown onsets shipped; Beat This! owns tempo | RETIRE | same tombstone | high |
| FA-4 | beat-dominant visual design feels out of sync — beat is accent, never primary | 37/248/34 · 06-10 | judgment rule; duplicated by §Audio Data Hierarchy + DN-6 | KEEP | core — merge into §Audio Data Hierarchy as its canonical statement (one slot with DN-6) | high |
| FA-11 | MediaRemote private framework blocked from signed bundles (macOS 15+) | 0/0/0 | only explanatory comments remain (AudioInputRouter.swift, StreamingMetadata.swift); no usage | RETIRE | HISTORICAL_DEAD_ENDS §Metadata/streaming-API | high |
| FA-15 | chroma from <500 Hz FFT bins: resolution too coarse | 0/0/0 | grep `chroma` in engine finds only visual chromatic-aberration code; pre-corpus rule | DEMOTE | ARCHITECTURE §Audio Analysis Tuning (chroma notes) — fires only in MIR tuning work | low |
| FA-16 | raw 12-bin chroma as mood-MLP input unlearnable | 0/5/2 · 05-13 | MoodClassifier.swift ships engineered inputs; no raw-bin feed found; pre-corpus | DEMOTE | ARCHITECTURE §Audio Analysis Tuning + MoodClassifier code comment | low |
| FA-17 | "autocorrelation half-tempo" misdiagnosis (amended DSP.1 narrative) | 1/9/8 · 06-03 | superseded by D-075 (trimmed-mean IOI) + D-077 (Beat This!); durable rules live as FA-50/51 | RETIRE | HISTORICAL_DEAD_ENDS §ML/signal-processing (tombstone cites D-075/D-077) | high |
| FA-18 | median threshold on half-wave-rectified flux ≈ 0 | 0/0/0 | same superseding architecture | RETIRE | same tombstone | high |
| FA-21 | `CATapDescription(stereoMixdownOfProcesses: [])` = silence | 10/57/6 · 05-27 | correct API in use at SystemAudioCapture.swift:256 | DEMOTE | code comment at tap install + RUNBOOK; fires only in capture-path work | high |
| FA-22 | tap delivers zeros without screen-capture permission | 9/31/9 · 05-27 | CGRequestScreenCaptureAccess at VisualizerEngine+PublicAPI.swift:46; memory file exists | DEMOTE | RUNBOOK §troubleshooting + code comment at the preflight call | high |
| FA-23 | audio-deformed architecture reads broken/rubber (D-020) | 1/19/14 · 05-26 | D-020 active; SHADER_CRAFT §13 already hosts the sibling entries | DEMOTE | SHADER_CRAFT §13; preset-session locality | high |
| FA-24 | tinting `lightColor` alone leaves IBL-dominated pixels unchanged (D-022) | 3/21/8 · 05-16 | D-022 active; ray-march locality | DEMOTE | SHADER_CRAFT §13 | high |
| FA-25 | mood on a @Published overlay never reaches GPU without setMood path (D-024) | 0/97/9 · 06-10 | setMood + setFeatures mood-preservation present (RenderPipeline+PresetSwitching.swift:159–171) | MECHANIZE | unit test: `setFeatures` preserves valence/arousal across overwrites (Renderer test target); prose → code comment | high |
| FA-26 | beat-pulse keyed to beatBass alone misses snare-driven tracks | 2/48/5 · 06-05 | preset-authoring practice; DN-15 duplicates | DEMOTE | SHADER_CRAFT (beat-coupling cookbook) | high |
| FA-27 | synthetic audio can't reproduce real-pipeline noise/structure | 2/15/5 · 06-10 | memory `feedback_synthetic_audio.md`; PresetSessionReplay harness exists | DEMOTE | docs/ENGINE/SESSION_REPLAY.md preamble + RUNBOOK diagnostics — fires only when building diagnostics | high |
| FA-28 | locking AVAssetWriter to first drawable size corrupts late frames | 11/42/8 · 06-09 | fix embodied: SessionRecorder+Video.swift (`sameDimsStreak`, `writerRelockThreshold`) | DEMOTE | code comment (already embodied) + ARCHITECTURE capture notes; DN-14 dedupes into this | high |
| FA-29 | 44.1 kHz assumption when tap reports otherwise (environment layer) | 6/22/10 · 05-27 | code layer gated by `Scripts/check_sample_rate_literals.sh`; env guidance already in RUNBOOK | MECHANIZE | already-mechanized (script); RUNBOOK keeps the Audio-MIDI-Setup note | high |
| FA-30 | Spotify volume normalization compresses AGC headroom | 4/17/5 · 06-02 | rule text already names RUNBOOK | DEMOTE | RUNBOOK §Spotify setup | high |
| FA-31 | absolute thresholds on AGC-normalized energy (→ D-026 deviation primitives) | 14/88/34 · 06-10 | D-026 cited in 79/106 sessions — most load-bearing rule in corpus; BandDeviationTracker live | KEEP | core one-liner (one slot with DN-17 + D-026); diagnosis narrative stays in MILKDROP_ARCHITECTURE | high |
| FA-32 | instantaneous-only ray-march can't compound motion — mv_warp required (D-027) | 4/22/9 · 06-05 | mv_warp pass live; 4 preset sidecars use it | DEMOTE | SHADER_CRAFT (mv_warp section); DN-19 dedupes | high |
| FA-33 | free-running `sin(time)` motion reads mechanical | 16/192/35 · 06-10 | preset-authoring judgment; beat_phase01 alternatives documented | DEMOTE | SHADER_CRAFT §13 | high |
| FA-39 | authoring without curated reference images ships primitive output | 8/35/15 · 06-09 | REVIEW.1 §1.2: README-before-first-.metal-edit = 35 %; zero mechanical enforcement today | MECHANIZE | PreToolUse hook: warn on Edit/Write to `**/Shaders/**/*.metal` when no `VISUAL_REFERENCES/**/README.md` Read occurred this session (REVIEW.1 §4 candidate) | high |
| FA-48 | spec-faithful but anti-reference-matching output passes automated gates | 21/123/16 · 06-02 | D-071 mandates the M7-prep contact-sheet step | MECHANIZE | mandatory contact-sheet checkpoint field in the PRESET_SESSION.md template (post-hoc checkable via the REVIEW.1 extractor); judgment remainder → SHADER_CRAFT | high |
| FA-49 | all spec'd changes landed + output still far from refs ⇒ structural gap, stop tuning | 33/121/24 · 06-10 | judgment discriminator; reused at concept scope (FA-58) and infra scope (FA-69) | KEEP | core (compressed) | high |
| FA-50 | fusing sub_bass+low_bass onsets aliases IOIs (D-075) | 0/16/12 · 05-28 | fix embodied: `onsets[0]`-only sourcing in BeatDetector | DEMOTE | BEAT_SYNC.md + BeatDetector code comment; DN-39 dedupes | high |
| FA-51 | histogram-mode integer-BPM buckets bias fast (D-075) | 0/6/2 · 06-01 | `computeRobustBPM` trimmed-mean live | DEMOTE | BEAT_SYNC.md; DN-40 dedupes | high |
| FA-52 | literal `44100` in live-rate code paths (D-079) | 13/51/21 · 05-27 | `Scripts/check_sample_rate_literals.sh` enforces in CI | MECHANIZE | already-mechanized; prose → one-line pointer | high |
| FA-53 | summed AGC stem energies saturate affinity scoring (D-080) | 4/29/10 · 06-09 | fix embodied: PresetScorer uses stemEnergyDev + neutral 0.5 (lines 296–324) | DEMOTE | PresetScorer code comment + ARCHITECTURE orchestrator notes; DN-45 dedupes | high |
| FA-54 | `TrackProfile.empty` + affinity scorer adversarially inverts intent (D-080) | 1/6/5 · 05-21 | neutral-0.5-on-zero guard embodied | DEMOTE | same destination as FA-53; DN-46 dedupes | high |
| FA-55 | shadow `@StateObject SettingsStore()` swallows user toggles | 18/99/11 · 06-09 | SettingsStoreEnvironmentRegressionTests (3 assertions incl. source-text check) | MECHANIZE | already-mechanized; prose → one-line pointer | high |
| FA-56 | lowercased title+artist plan matching breaks on covers/encoding | 7/33/12 · 06-01 | PlaybackChromeIndexBindingTests; `currentTrackIndex` publisher live (VisualizerEngine.swift:109) | MECHANIZE | already-mechanized | high |
| FA-57 | spider trigger spec'd on acoustically-impossible primitive combination | 6/44/19 · 06-10 | Arachne operating rules already pointered to design doc at DOC.4 | DEMOTE | ARACHNE_V8_DESIGN.md §Operating rules | high |
| FA-58 | a preset whose subject has no load-bearing musical role is untunable | 32/181/38 · 06-10 | restated as SHADER_CRAFT §13 concept-viability gate + Authoring Discipline three-part bar | DEMOTE | SHADER_CRAFT §13 (canonical); core retains the Authoring-Discipline one-liner | high |
| FA-59 | schema additions without a demonstrated consumer | 3/39/10 · 06-10 | D-120 reverted, now in DECISIONS_HISTORY; strategy-scope clause carries the rule | RETIRE | HISTORICAL_DEAD_ENDS; superseded by §Authoring Discipline strategy-scope clause | high |
| FA-60 | batch-filed strategy decisions without empirical validation | 2/7/4 · 05-26 | strategy-scope clause cites + carries it; MD bloc has DOC.4 REVISIT banner | RETIRE | HISTORICAL_DEAD_ENDS; superseded by strategy-scope clause | high |
| FA-61 | colored beams on near-mirror as inverse-square point lights = invisible | 4/90/12 · 06-09 | D-125/D-126 reverted by D-127; material-craft rule | DEMOTE | SHADER_CRAFT material cookbook ("mirror reflects sky"); DN-21 dedupes | high |
| FA-62 | decoration layers without an articulated musical role | 1/104/14 · 06-05 | layer-scope rule already in Authoring Discipline | DEMOTE | SHADER_CRAFT §13; core keeps the layer-scope one-liner; DN-22 dedupes | high |
| FA-63 | authoring without reading the references README + per-image annotations | 13/55/21 · 06-10 | same enforcement surface as FA-39 | MECHANIZE | same PreToolUse hook (README-read check) | high |
| FA-64 | ≥2 failed structural fixes on a named problem ⇒ desk research, stop guessing | 19/61/21 · 06-10 | declared child of FA-73 in CLAUDE.md | DEMOTE | folded as a sub-bullet of the kept FA-73 core entry; full text SHADER_CRAFT §13 | high |
| FA-65 | don't negotiate away components of a working reference without rendering proof | 19/78/14 · 06-10 | declared child of FA-73 | DEMOTE | folded under FA-73; full text SHADER_CRAFT §13 | high |
| FA-66 | test fixtures must exercise the live GPU dispatch path | 43/267/28 · 06-10 | `useMeshPath` fixture param (round 57); multi-frame harness obligations; partially gated, judgment remainder | KEEP | core (one slot with DN-23 + the production-grade-testing Authoring-Discipline rule) | high |
| FA-67 | one audio primitive / one timescale per visual layer | 8/100/25 · 06-10 | memory file; (layer × primitive × timescale) table practice documented | DEMOTE | SHADER_CRAFT §13; DN-24 dedupes | high |
| FA-68 | sub-bass onsets are bassline events, not beats — never a phase reference | 31/229/10 · 06-10 | CS.1.y.2 reverted; cold-start contract lives in BEAT_SYNC.md | DEMOTE | BEAT_SYNC.md §Cold-Start | high |
| FA-69 | cold-start beat phase from short tap audio: premise falsified across 6 iterations | 41/177/12 · 06-10 | BSAudit.3.impl reverted (`33cd57e9`…); full contract history in BEAT_SYNC.md (DOC.4) | DEMOTE | BEAT_SYNC.md §Cold-Start; the operative ban survives as kept DN-16 one-liner | high |
| FA-70 | port a reference's render loop wholesale, not divergence-by-divergence | 20/102/12 · 06-10 | declared child of FA-73; butterchurn component facts durable in D-138 | DEMOTE | folded under FA-73; component facts D-138 / SHADER_CRAFT §18 | high |
| FA-71 | audit output colour-space convention + time-term magnitude when porting | 3/47/7 · 06-10 | D-139 carries the facts; Skein inverse case in SHADER_CRAFT §18.x | DEMOTE | SHADER_CRAFT §18 (porting) | high |
| FA-72 | Swift camelCase field names in MSL = silent compile fail + preset drop | 7/45/12 · 06-10 | symptom gate live (PresetLoaderCompileFailureTest production count); no name lint exists | MECHANIZE | new lint script: ban camelCase FeatureVector/StemFeatures field names in `.metal` (Scripts/); count gate already covers the symptom | high |
| FA-73 | don't rebuild a system that exists as a working, code-available reference | 11/62/3 · 06-04 | parent rule of #64/#65/#70 per CLAUDE.md; judgment; universal across session types | KEEP | core — consolidated reference-discipline entry absorbing #64/#65/#70 one-liners + DN-1/DN-2 | high |

**FA tallies:** KEEP 5 · MECHANIZE 9 · DEMOTE 27 · RETIRE 8.

### 2.2 DN population (63)

Citations column: bullets are unmeasured directly (REVIEW.1 echo scan is indicative only); where a bullet duplicates a measured rule, the parent's verdict drives it and the parent ID is shown.

| ID | bullet (first words) | citations | grep evidence | verdict | destination / gate | conf |
|---|---|---|---|---|---|---|
| DN-1 | rebuild from first principles a system that exists… | unmeasured; parent FA-73 11 conv | — | KEEP | consolidated into FA-73 core entry (same slot) | high |
| DN-2 | bend a faithfully-ported reference out of its working regime | unmeasured; FA-73-family | MM.6 §12.2/§12.3 + shipped Murmuration3D | DEMOTE | compressed into FA-73 core entry; full text SHADER_CRAFT §13 | high |
| DN-3 | block the render loop on network, ML, or metadata | unmeasured | engine invariant; no single gate expresses it | KEEP | core invariants list (unmechanizable: any new code path can violate) | high |
| DN-4 | allocate in the Core Audio IO proc callback | unmeasured | BUG-036 (AUDIT.1) found 3 RT-allocation sites — rule is live and violated | KEEP | core invariants list; realtime-safety lint is not practical today | high |
| DN-5 | use `.storageModeManaged` buffers | unmeasured | D-006 embodied; greppable token | MECHANIZE | SwiftLint custom regex / script banning `.storageModeManaged` | high |
| DN-6 | make beat onset the primary visual driver | unmeasured; parent FA-4 37 conv | — | KEEP | consolidated into §Audio Data Hierarchy slot (with FA-4) | high |
| DN-7 | hardcode shader paths | unmeasured | runtime preset discovery (D-007) embodied | MECHANIZE | lint: ban `Shaders/` path string literals outside PresetLoader | high |
| DN-8 | normalize 6-band AGC per-band | unmeasured | AGC implementation locality | DEMOTE | ARCHITECTURE §Audio Analysis Tuning + AGC code comment | high |
| DN-9 | pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the command line | unmeasured | duplicate of §Build & Test line; xcconfig embodies (D-016) | DEMOTE | dedupe into §Build & Test (already states it) | high |
| DN-10 | assume Now Playing metadata is available or accurate | unmeasured | metadata-fetcher locality | DEMOTE | ARCHITECTURE §Session Preparation (metadata priority) | high |
| DN-11 | use `[[thread_index_in_mesh]]` in MSL | unmeasured | greppable token; mesh-shader locality | MECHANIZE | lint: grep `.metal` for the non-existent attribute | high |
| DN-12 | deform architecture geometry with audio (D-020) | unmeasured; D-020 0 conv/35 s | D-020 active | DEMOTE | SHADER_CRAFT §13 (with FA-23) | high |
| DN-13 | write to `latestFeatures.valence`/`arousal` from MIR path | unmeasured; parent FA-25 | preservation code present | MECHANIZE | same test as FA-25 (setFeatures preserves mood) | high |
| DN-14 | lock AVAssetWriter to first observed drawable size | unmeasured; parent FA-28 11 conv | fix embodied | DEMOTE | dedupe into FA-28 destination (code comment + ARCHITECTURE) | high |
| DN-15 | key beat-pulse to a single onset band | unmeasured; parent FA-26 | — | DEMOTE | SHADER_CRAFT (with FA-26) | high |
| DN-16 | file another cold-start beat-phase iteration from short tap audio | unmeasured; parent FA-69 41 conv/12 s | BSAudit.3.impl revert commits | KEEP | core one-liner (rare-but-expensive: 6 failed iterations; unmechanizable — bans a premise, not a token) | high |
| DN-17 | threshold absolute AGC-normalized energy (D-026/D-146) | unmeasured; D-026 87 conv/79 s | BandDeviationTracker live | KEEP | consolidated into the D-026 core slot (with FA-31) | high |
| DN-18 | derive band deviation against a fixed 0.5 pivot (BUG-027/D-146) | unmeasured | live-path test `bandDeviation_recoversFromColdStart_liveMIRPipeline` exists | MECHANIZE | already-mechanized (named test); prose → SHADER_CRAFT §14.1 (already documented) | high |
| DN-19 | write new ray-march presets without mv_warp (D-027) | unmeasured; parent FA-32 | mv_warp live | DEMOTE | SHADER_CRAFT (with FA-32) | high |
| DN-20 | author a preset without reading README + references | unmeasured; parents FA-39/63 | REVIEW.1: 35 % compliance | MECHANIZE | the FA-39/63 PreToolUse hook | high |
| DN-21 | implement mirror-surface beams as point lights | unmeasured; parent FA-61 | D-127 | DEMOTE | SHADER_CRAFT material cookbook (with FA-61) | high |
| DN-22 | add decoration layers without musical role | unmeasured; parent FA-62 | — | DEMOTE | SHADER_CRAFT §13 (with FA-62); layer-scope one-liner stays in Authoring Discipline | high |
| DN-23 | assume fixture path = live dispatch path | unmeasured; parent FA-66 43 conv | `useMeshPath` param | KEEP | consolidated into FA-66 core slot | high |
| DN-24 | route one timescale into two visual layers | unmeasured; parent FA-67 | — | DEMOTE | SHADER_CRAFT §13 (with FA-67) | high |
| DN-25 | ship a hero surface with <4 octaves of noise | unmeasured | SHADER_CRAFT §12.1 mandatory; rubric proxies in FidelityRubricTests | DEMOTE | dedupe into SHADER_CRAFT §12.1 (already canonical) | high |
| DN-26 | ship <3 distinct materials | unmeasured | same | DEMOTE | dedupe into SHADER_CRAFT §12.1 | high |
| DN-27 | skip the coarse-to-fine authoring workflow | unmeasured | SHADER_CRAFT §2.2 canonical | DEMOTE | dedupe into SHADER_CRAFT §2.2 | high |
| DN-28 | show full-screen errors during `.playing` | unmeasured | UX_SPEC §9.4 canonical | DEMOTE | dedupe into UX_SPEC §9.4 | high |
| DN-29 | put transport controls in PlaybackView for streaming | unmeasured | UX_SPEC UX-2 canonical; LocalFileTransportBar exception live | DEMOTE | dedupe into UX_SPEC UX-2 (carries the LF.5 exception) | high |
| DN-30 | use jargon in user-facing strings | unmeasured | UX_SPEC §9.5 canonical; check_user_strings.sh covers externalization (not jargon) | DEMOTE | dedupe into UX_SPEC §9.5 | high |
| DN-31 | bypass the certification rubric on "feels done" | unmeasured | SHADER_CRAFT §12.1 canonical | DEMOTE | dedupe into SHADER_CRAFT §12.1 | high |
| DN-32 | ship pale-dominant panels (pale-share > 30 %) | unmeasured; D-LM-cream-rescission | pale-tone-share cert gates live at LM.9 | MECHANIZE | already-mechanized for certified presets (per-preset cert gates); authoring prose → SHADER_CRAFT | high |
| DN-33 | smoothstep thresholds > 0.3 on fbm8 | unmeasured; FA #42/#43 (moved) | SHADER_CRAFT §13 hosts the parents | DEMOTE | dedupe into SHADER_CRAFT §13 | high |
| DN-34 | sample fbm8 at scale 1.0 on unit geometry | unmeasured; FA #43 (moved) | same | DEMOTE | dedupe into SHADER_CRAFT §13 | high |
| DN-35 | Metal type names as MSL variable names (FA #44) | unmeasured; FA #44 25 conv/43 s (moved) | PresetLoaderCompileFailureTest covers symptom | MECHANIZE | lint: declarations shadowing MSL type keywords in `.metal` (pair with FA-72 lint) | high |
| DN-36 | assume Spotify schemas stable across renames (FA #45) | unmeasured; FA #45 5 conv (moved) | RUNBOOK §Spotify canonical | DEMOTE | dedupe into RUNBOOK §Spotify connector setup | high |
| DN-37 | use Spotify `fields` param on /items (FA #46) | unmeasured (moved parent) | same | DEMOTE | dedupe into RUNBOOK | high |
| DN-38 | re-derive discarded `preview_url` via iTunes (FA #47) | unmeasured (moved parent) | same | DEMOTE | dedupe into RUNBOOK | high |
| DN-39 | fuse cross-band onsets for IOI tempo (FA-50/D-075) | unmeasured; parent FA-50 | fix embodied | DEMOTE | BEAT_SYNC.md (with FA-50) | high |
| DN-40 | re-introduce histogram-mode BPM picking (FA-51/D-075) | unmeasured; parent FA-51 | fix embodied | DEMOTE | BEAT_SYNC.md (with FA-51) | high |
| DN-41 | write literal `44100` in live-rate paths (FA-52/D-079) | unmeasured; parent FA-52 13 conv | script in CI | MECHANIZE | already-mechanized (`check_sample_rate_literals.sh`) | high |
| DN-42 | mutate `tapSampleRate` from audio thread unsynchronized (D-079) | unmeasured | capture-once pattern embodied (D-061 lock) | DEMOTE | ARCHITECTURE audio-capture + code comment at tap install | high |
| DN-43 | double sub-80 BPM in any tempo path | unmeasured | `halvingOctaveCorrected` (BeatGrid.swift:185) is halving-only | DEMOTE | BEAT_SYNC.md + code comment at the function | high |
| DN-44 | store `MIRPipeline.elapsedSeconds` as Float | unmeasured | declared `Double` (MIRPipeline.swift:79) | MECHANIZE | one-line type-pin test (CommonLayoutTest pattern) | high |
| DN-45 | sum AGC-normalized stems for orchestrator scoring (FA-53) | unmeasured; parent FA-53 | fix embodied | DEMOTE | PresetScorer comment + ARCHITECTURE (with FA-53) | high |
| DN-46 | score reactive against `TrackProfile.empty` + affinity scorer (FA-54) | unmeasured; parent FA-54 | guard embodied | DEMOTE | same (with FA-54) | high |
| DN-47 | call `applyLiveUpdate` without per-track cooldown | unmeasured | 30 s cooldown embodied (LiveAdapter.swift:171, 370) | MECHANIZE | unit test pinning `moodOverrideCooldown ≥ 30 s` | high |
| DN-48 | instantiate a second SettingsStore (FA-55) | unmeasured; parent FA-55 18 conv | regression tests live | MECHANIZE | already-mechanized (SettingsStoreEnvironmentRegressionTests) | high |
| DN-49 | match plan entries via lowercased title+artist (FA-56) | unmeasured; parent FA-56 | regression test live | MECHANIZE | already-mechanized (PlaybackChromeIndexBindingTests) | high |
| DN-50 | write a @Published surface on one path without clearing the complementary path (BUG-024) | unmeasured; BUG-024 13 conv/7 s | app-layer pattern; no gate practical per-surface | DEMOTE | ARCHITECTURE app-layer conventions (fires only when adding @Published surfaces) | high |
| DN-51 | silently skip a test on a missing fixture | unmeasured | BeatThisFixturePresenceGate covers the known class | MECHANIZE | already-mechanized for fixtures (named gate); general rule → Code Style line | medium |
| DN-52 | touch Arachne without reading ARACHNE_V8_DESIGN §Operating rules | unmeasured | content already moved at DOC.4; bullet is a pointer | DEMOTE | ARACHNE_V8_DESIGN.md (pointer moves to PRESET_SESSION.md per-preset index) | high |
| DN-53 | bind non-preset buffers at fragment slots 6/7 (D-092) | unmeasured; D-092 12 conv/29 s | buffers 1–3 present (RenderPipeline.swift:367–385) | DEMOTE | ARCHITECTURE §GPU Contract (slot reservation table) | high |
| DN-54 | transition `wait_for_completion_event` presets on timers (BUG-011 r8) | unmeasured; BUG-011 245 conv (bug, not rule) | flag handling live (PresetDescriptor.swift:449, PresetMaxDuration.swift:84–101) | DEMOTE | ARCHITECTURE orchestrator §completion-gated segments + code comment | high |
| DN-55 | parameterize ProceduralGeometry for a new particle preset (D-097) | unmeasured; D-097 51 conv/48 s | ParticleGeometry protocol live | DEMOTE | SHADER_CRAFT particle-preset architecture (with D-097) | high |
| DN-56 | throttle a coupled substrate by element count (governor) | unmeasured | `test_governorThrottleFreezesNoBirds` exists | MECHANIZE | already-mechanized (named test); prose → SHADER_CRAFT particle section | high |
| DN-57 | extend Common.metal structs without golden-hash regen (D-099) | unmeasured; D-099 40 conv/48 s | CommonLayoutTest + PresetRegressionTests live | MECHANIZE | already-mechanized (CommonLayoutTest + golden-hash sweep); procedure note → ARCHITECTURE | high |
| DN-58 | (embedded, Increment Protocol) do not leave durable learnings only in chat | unmeasured | process rule | KEEP | within SEC-3 (kept section) | high |
| DN-59 | (embedded, Increment Protocol) do not push without Matt's explicit approval | unmeasured | process rule; high-cost failure | KEEP | within SEC-3 | high |
| DN-60 | (embedded, Defect Protocol) no code changes on P0/P1/P2 before evidence documented | unmeasured | process rule | KEEP | within SEC-4 | high |
| DN-61 | (embedded, Defect Protocol) no fix code in the diagnosis increment | unmeasured | process rule | KEEP | within SEC-4 | high |
| DN-62 | (embedded, Cold-Start Contract) do not iterate on cold-start phase derivation | unmeasured; duplicate of DN-16 | — | DEMOTE | dedupe — DN-16 retains the single core copy | high |
| DN-63 | (embedded, UX Contract) never `@StateObject SettingsStore()` in a view | unmeasured; duplicate of DN-48/FA-55 | regression test live | MECHANIZE | already-mechanized; dedupe into the FA-55 pointer | high |

**DN tallies:** KEEP 11 (of which 4 consolidate into FA/SEC slots and 4 live inside kept protocol sections) · MECHANIZE 17 · DEMOTE 35 · RETIRE 0.

### 2.3 SEC population (21)

| ID | section | citations | grep evidence | verdict | destination / RB.2 note | conf |
|---|---|---|---|---|---|---|
| SEC-1 | What This Is | 11/61/24 · 06-10 | product identity | KEEP | core; unchanged | high |
| SEC-2 | Build & Test | 2/15/8 · 06-10 | commands current | KEEP | core; absorbs DN-9 | high |
| SEC-3 | Increment Completion Protocol | 55/147/44 · 06-10 | process backbone | KEEP | core; carries DN-58/59 | high |
| SEC-4 | Defect Handling Protocol | 28/193/42 · 06-10 | mostly pointers to QUALITY/ | KEEP | core; carries DN-60/61; RB.2 may compress detail already duplicated in QUALITY/ | high |
| SEC-5 | Module Map | 163/1152/48 · 06-10 | already a 3-line pointer | KEEP | core; merge into single Handbook-Index block (RB.2) | high |
| SEC-6 | Audio Data Hierarchy (+ ###Cold-Start Phase Contract) | 40/331/60; cold-start 19/191/17 | the project's #1 design rule | KEEP | core; absorbs FA-4/DN-6 as canonical statement; cold-start subsection compresses to contract summary + DN-16 (history already in BEAT_SYNC.md) | high |
| SEC-7 | Audio Analysis Tuning | 13/101/26 | already a pointer | KEEP | core; merge into Handbook-Index | high |
| SEC-8 | Key Types | 21/203/30 | pointer | KEEP | core; Handbook-Index | high |
| SEC-9 | GPU Contract | 67/477/61 | pointer; heavily cited | KEEP | core; Handbook-Index; gains slot-reservation pointer (DN-53) | high |
| SEC-10 | Preset Metadata Format | 5/48/12 | pointer | KEEP | core; Handbook-Index | high |
| SEC-11 | Visual Quality Floor | 21/111/26 | pointer | KEEP | core; Handbook-Index | high |
| SEC-12 | Session Preparation Pipeline | 2/48/19 | pointer | KEEP | core; Handbook-Index | high |
| SEC-13 | UX Contract | 5/46/16 | 2 of 3 surfaced invariants are mechanized (FA-55 tests, check_user_strings.sh) | KEEP | core; shrink to pointer + tooltip rule (the one unmechanized invariant); fix §8/§9 numbering drift (appendix) | high |
| SEC-14 | ML Inference | 9/149/25 | pointer | KEEP | core; Handbook-Index | high |
| SEC-15 | Code Style | 17/45/17 | mixed: universal conventions + mechanized rules + U.11-era narratives | KEEP | core, trimmed: SwiftLint-covered rules → pointer; U.11 pbxproj/timing narratives → RUNBOOK/test-suite docs; universal conventions stay | high |
| SEC-16 | Failed Approaches | 73/421/53 | the audit's main subject | KEEP | core as a much smaller table (5 KEEP entries + gap-table pointer) per §2.1 verdicts | high |
| SEC-17 | Authoring Discipline | 68/347/53 | top-cited judgment rules; ~4 k words | KEEP | core for the universal discipline rules; preset-session operationalia split to PRESET_SESSION.md (RB.2) | high |
| SEC-18 | What NOT To Do | 43/200/40 | per-bullet verdicts §2.2 | KEEP | core as ~10-line invariants list per §2.2 verdicts | high |
| SEC-19 | Current Status | 29/117/22 | already trimmed to pointers (DOC.3) | KEEP | core; unchanged | high |
| SEC-20 | Linked Frameworks | 0/16/7 | one line; never conversationally cited | DEMOTE | ARCHITECTURE (framework list already implied by module map) | high |
| SEC-21 | Development Constraints | 0/14/6 | team/platform/perf/no-push facts | KEEP | core; absorbs D-001/D-003 one-liners | high |

**SEC tallies:** KEEP 20 · DEMOTE 1. (Section-KEEPs are structural skeleton — 8 of them are 2–4-line pointers slated to merge into one Handbook-Index block at RB.2.)

### 2.4 D population (161)

Verdict semantics reminder: RETIRE = move to DECISIONS_HISTORY.md (rationale preserved, nothing hard-deleted); DEMOTE = stays active in DECISIONS.md (on-demand) and/or content moves to the named handbook; KEEP = also surfaced in the always-loaded core; MECHANIZE = named gate covers the rule.

| ID | decision (gist) | citations | grep evidence / status | verdict | destination / gate | conf |
|---|---|---|---|---|---|---|
| D-001 | native macOS / Apple Silicon only | 1/14/6 | embodied; §Development Constraints carries it | RETIRE | DECISIONS_HISTORY; carrier = SEC-21 | high |
| D-002 | Core Audio taps as default capture path | 3/17/7 | SystemAudioCapture live; SCK dead end in HISTORICAL_DEAD_ENDS | DEMOTE | stays active (standing capture constraint) | high |
| D-003 | local-only processing | 0/4/4 | §Development Constraints "Learning stays local" carries it | RETIRE | DECISIONS_HISTORY; carrier = SEC-21 | high |
| D-004 | continuous energy is primary visual driver | 0/5/4 | fully duplicated by §Audio Data Hierarchy + FA-4 | RETIRE | DECISIONS_HISTORY; carrier = SEC-6 | high |
| D-005 | protocol-oriented cross-module design | 0/4/4 | Code Style carries it | RETIRE | DECISIONS_HISTORY; carrier = SEC-15 | high |
| D-006 | UMA `.storageModeShared` buffers | 0/3/3 | embodied; DN-5 lint proposed | MECHANIZE | the DN-5 lint; entry → history with pointer | high |
| D-007 | runtime preset discovery + hot reload | 0/4/4 | PresetLoader embodies | RETIRE | DECISIONS_HISTORY | high |
| D-008 | playlist-first session preparation | 1/25/6 | embodied; ARCHITECTURE §Session Prep documents | RETIRE | DECISIONS_HISTORY | high |
| D-009 | no CoreML — MPSGraph + Accelerate | 3/87/16 | grep: zero `import CoreML`; ML pointer cites D-009 | DEMOTE | stays active (standing ML constraint) | high |
| D-010 | Open-Unmix HQ as stem model | 1/37/13 | embodied (StemSeparator) | RETIRE | DECISIONS_HISTORY; ARCHITECTURE documents the model | high |
| D-011 | iTunes Search for preview resolution | 0/22/14 | embodied; FA #47 short-circuit in RUNBOOK | RETIRE | DECISIONS_HISTORY | high |
| D-012 | MusicBrainz metadata backbone | 0/6/5 | embodied | RETIRE | DECISIONS_HISTORY | high |
| D-014 | orchestrator = explicit scored policy system | 0/18/8 | standing design principle | DEMOTE | stays active (orchestrator locality) | high |
| D-015 | RenderPass enum over boolean flags | 0/5/5 | embodied | RETIRE | DECISIONS_HISTORY | high |
| D-016 | warnings-as-errors via xcconfig | 0/5/5 | embodied in Phosphene.xcconfig; misuse breaks the build | MECHANIZE | already-mechanized by construction (xcconfig + build failure); entry → history | high |
| D-017 | SessionState/SessionPlan live in Session module | 3/39/7 | embodied | RETIRE | DECISIONS_HISTORY | high |
| D-018 | SessionManager degrades to ready on prep failure | 5/67/17 | standing lifecycle rule | DEMOTE | stays active | high |
| D-019 | stem-routing warmup crossfade pattern | 39/734/62 · 06-10 | heavily-used standing preset pattern | DEMOTE | SHADER_CRAFT (authoring pattern) + stays active | high |
| D-020 | architecture-stays-solid in ray-march scenes | 0/64/35 | standing authoring rule; FA-23/DN-12 | DEMOTE | SHADER_CRAFT §13 (with FA-23) + stays active | high |
| D-021 | sceneMaterial signature contract | 5/60/17 | embodied GPU contract; ARCHITECTURE documents | RETIRE | DECISIONS_HISTORY | high |
| D-022 | IBL ambient tinted by lightColor | 40/445/25 | standing ray-march palette rule (FA-24) | DEMOTE | SHADER_CRAFT §13 + stays active | high |
| D-023 | tap reinstall on prolonged silence | 0/7/4 | embodied | RETIRE | DECISIONS_HISTORY | high |
| D-024 | mood injected only via setMood | 2/30/14 | preservation code present | MECHANIZE | FA-25 test; entry → history with pointer | high |
| D-025 | SessionRecorder runs continuously | 0/5/5 | embodied | RETIRE | DECISIONS_HISTORY | high |
| D-026 | presets drive from deviation primitives, not absolute energy | 87/1244/**79** · 06-10 | cited in 79/106 sessions — the most load-bearing rule in the corpus | KEEP | core one-liner (single slot with FA-31/DN-17); stays active in DECISIONS.md | high |
| D-027 | mv_warp as opt-in render pass | 29/279/43 | standing render contract; 4 presets use it | DEMOTE | stays active; ARCHITECTURE/SHADER_CRAFT document | high |
| D-028 | Apple-Silicon audio capability extensions (MV-1/MV-3) | 8/226/45 | shipped extensions; layout preserved per D-099 | RETIRE | DECISIONS_HISTORY | medium |
| D-029 | motion paradigms are alternatives, not layers | 32/256/34 | standing authoring rule | DEMOTE | SHADER_CRAFT + stays active | high |
| D-030 | SpectralHistoryBuffer unconditional at buffer(5) | 7/97/26 | embodied GPU contract | DEMOTE | ARCHITECTURE §GPU Contract + stays active | high |
| D-032 | preset scoring weights + penalties (amended by D-080) | 10/166/18 | standing orchestrator calibration | DEMOTE | stays active | medium |
| D-033 | transition policy design | 4/57/16 | standing orchestrator policy | DEMOTE | stays active | high |
| D-034 | greedy forward-walk session planning | 4/70/14 | embodied algorithm choice | RETIRE | DECISIONS_HISTORY | medium |
| D-035 | live adaptation as pure function | 3/78/20 | embodied structure | RETIRE | DECISIONS_HISTORY | medium |
| D-036 | reactive orchestrator stateless | 3/78/19 | embodied structure | RETIRE | DECISIONS_HISTORY | medium |
| D-037 | Preset Acceptance Checklist invariants | 14/165/28 | PresetAcceptanceTests live | MECHANIZE | already-mechanized (named suite); entry → history with pointer | high |
| D-038 | PresetCategory.organic | 1/8/7 | embodied enum | RETIRE | DECISIONS_HISTORY | high |
| D-039 | dHash visual regression gate (carries RE-EVALUATE flag, 2026-05-13) | 2/24/11 | PresetRegressionTests live; BUG-034 currently degrades ray-march golden evidence | MECHANIZE | already-mechanized; the RE-EVALUATE flag + BUG-034 interaction flagged for Matt (§3.3) | low |
| D-040 | spider easter-egg design | 2/24/12 | shipped; ARACHNE_V8_DESIGN carries | RETIRE | DECISIONS_HISTORY | high |
| D-041 | Arachne ray-march remaster | 0/15/12 | shipped; design doc carries | RETIRE | DECISIONS_HISTORY | high |
| D-042 | Gossamer spokes hand-designed, never formula-derived | 0/4/4 | shipped; G-uplift phase may revisit | RETIRE | DECISIONS_HISTORY (design doc / git carries; resurface at Gossamer uplift) | medium |
| D-043 | Arachne 2D SDF direct fragment (REVERTED by D-072) | 0/16/8 | explicitly reverted | RETIRE | DECISIONS_HISTORY | high |
| D-044 | a11y identifiers as static constants | 0/6/3 | embodied pattern | DEMOTE | UX_SPEC §15 test surface | medium |
| D-045 | shader utility naming: unprefixed snake_case | 1/64/13 | standing naming convention | DEMOTE | SHADER_CRAFT (naming) + stays active | high |
| D-047 | seeded tie-breaking for Regenerate Plan | 1/40/16 | embodied | RETIRE | DECISIONS_HISTORY | high |
| D-048 | defer 10 s preview loop to U.5b | 0/11/6 | stale deferral record | RETIRE | DECISIONS_HISTORY | high |
| D-049 | Shift+? help / P plan-preview keys | 1/11/5 | embodied; UX_SPEC documents | RETIRE | DECISIONS_HISTORY | high |
| D-050 | PlaybackActionRouter protocol placement | 10/91/13 | embodied | RETIRE | DECISIONS_HISTORY | medium |
| D-051 | UserFacingError in Shared + condition-ID toasts | 12/66/12 | standing UX error mechanism | DEMOTE | UX_SPEC §9 + stays active | medium |
| D-052 | capture-mode live-switch path | 9/90/20 | embodied | RETIRE | DECISIONS_HISTORY | medium |
| D-053 | excludedFamilies + qualityCeiling scoring gates | 0/59/16 | standing orchestrator surface | DEMOTE | stays active | medium |
| D-054 | AccessibilityState single source of truth + beat-clamp | 1/105/25 | standing a11y architecture | DEMOTE | UX_SPEC accessibility + stays active | medium |
| D-055 | V.2 utility library placement | 1/24/11 | embodied | RETIRE | DECISIONS_HISTORY | high |
| D-056 | progressive readiness architecture | 5/70/19 | embodied; ARCHITECTURE §Session Prep documents | RETIRE | DECISIONS_HISTORY | medium |
| D-057 | frame-budget governor: scalar modulations only | 6/208/45 | standing governor contract; DN-56 gate exists for the coupled-substrate corollary | DEMOTE | ARCHITECTURE render §governor + stays active | high |
| D-058 | U.6b live-adaptation keyboard semantics (RE-EVALUATE flag) | 6/72/13 | flag unresolved since 2026-05-13 | DEMOTE | UX_SPEC; the RE-EVALUATE flag goes to Matt (§3.3) | low |
| D-059 | ML dispatch scheduling | 17/130/23 | embodied; ARCHITECTURE §ML documents (CLAUDE.md already pointers) | DEMOTE | stays active | high |
| D-060 | soak test infrastructure | 2/64/18 | `run_soak_test.sh` + SoakTestHarness live | MECHANIZE | already-mechanized (harness exists); entry → history with pointer | high |
| D-061 | display hot-plug / source-switch resilience | 15/231/20 | embodied (grace window, locked tap rate) | RETIRE | DECISIONS_HISTORY (BUG-011 grace-window interplay noted in tombstone) | medium |
| D-062 | V.3 color/materials cookbook | 1/51/16 | embodied in Materials + SHADER_CRAFT | RETIRE | DECISIONS_HISTORY | high |
| D-063 | V.4 shader utility audit | 1/14/9 | executed audit | RETIRE | DECISIONS_HISTORY | high |
| D-064 | V.5 references library structure (full/lightweight rubric) | 2/63/17 | standing reference-curation structure (rubric_profile live) | DEMOTE | SHADER_CRAFT §2.3 + stays active | medium |
| D-065 | §2.3 amendment: composite images + AI anti-references | 13/157/23 | standing curation rule | DEMOTE | SHADER_CRAFT §2.3 + stays active | high |
| D-066 | Spotify as accepted canonical reel source | 0/3/3 | stale strategy record; reel context unclear | RETIRE | DECISIONS_HISTORY | low |
| D-067 | V.6 certification pipeline | 10/97/20 | standing cert structure (`certified` manual-only flag) | DEMOTE | SHADER_CRAFT §12 + stays active | high |
| D-068 | Spotify client-credentials connector | 7/47/9 | shipped; gotchas in RUNBOOK | RETIRE | DECISIONS_HISTORY | high |
| D-069 | Spotify OAuth PKCE | 9/68/10 | shipped | RETIRE | DECISIONS_HISTORY | high |
| D-070 | Spotify /items schema facts | 9/145/22 | shipped; RUNBOOK carries | RETIRE | DECISIONS_HISTORY | high |
| D-071 | Arachne V.7 M7 fail → references-anchored respec + contact-sheet step | 8/51/17 | the durable rule is FA-48's MECHANIZE (template field) | RETIRE | DECISIONS_HISTORY once the FA-48 template field exists (RB.2 sequencing) | high |
| D-072 | V.7.5 fidelity ceiling → compositing pivot | 10/72/24 | executed in V.8 | RETIRE | DECISIONS_HISTORY | high |
| D-073 | maxDuration linger-factor model (Option B) | 1/28/17 | standing orchestrator calibration | DEMOTE | stays active | medium |
| D-074 | diagnostic preset orchestrator semantics (RE-EVALUATE flag) | 2/96/21 | flag unresolved since 2026-05-13 | DEMOTE | stays active; flag goes to Matt (§3.3) | low |
| D-075 | sub-bass-only IOI + trimmed-mean BPM | 2/145/26 | embodied (FA-50/51) | DEMOTE | BEAT_SYNC.md + stays active | high |
| D-076 | (reserved) BeatNet via MPSGraph — ABANDONED by D-077 | 0/50/17 | explicitly abandoned | RETIRE | DECISIONS_HISTORY | high |
| D-077 | DSP.2 pivot to Beat This! | 5/142/29 | standing beat architecture | DEMOTE | BEAT_SYNC.md + stays active | high |
| D-078 | diagnostic hold semantics | 1/36/12 | standing behavior rule | DEMOTE | stays active | medium |
| D-079 | tap sample rate captured once per install; 44100 literal banned | 35/410/**58** | `check_sample_rate_literals.sh` in CI | MECHANIZE | already-mechanized; stays active as the gate's rationale | high |
| D-080 | stem-affinity scoring via deviation primitives | 30/415/38 | embodied in PresetScorer (FA-53/54) | DEMOTE | stays active; ARCHITECTURE orchestrator notes | high |
| D-081 | telemetry dashboard infrastructure | 1/25/8 | shipped (DASH era) | RETIRE | DECISIONS_HISTORY | high |
| D-082 | dashboard card layout engine | 1/48/10 | shipped | RETIRE | DECISIONS_HISTORY | high |
| D-083 | BEAT card binding | 0/50/7 | shipped | RETIRE | DECISIONS_HISTORY | high |
| D-084 | STEMS card binding | 0/13/7 | shipped | RETIRE | DECISIONS_HISTORY | high |
| D-085 | PERF card binding | 2/27/9 | shipped | RETIRE | DECISIONS_HISTORY | high |
| D-087 | DASH.7 SwiftUI dashboard port (supersedes D-086, already in history) | 4/103/16 | shipped | RETIRE | DECISIONS_HISTORY | high |
| D-088 | DASH.7.1 brand alignment | 24/202/21 | shipped | RETIRE | DECISIONS_HISTORY | medium |
| D-089 | DASH.7.2 legibility pass | 27/229/17 | shipped | RETIRE | DECISIONS_HISTORY | medium |
| D-090 | QR.3 silent-skip test holes closed | 2/28/13 | BeatThisFixturePresenceGate + DN-51 | MECHANIZE | already-mechanized; entry → history with pointer | high |
| D-091 | QR.4 dead-end views + SettingsStore collapse | 51/536/40 | executed cleanup; FA-55/56 regression tests carry the guards | RETIRE | DECISIONS_HISTORY | high |
| D-092 | Arachne staged WORLD+WEB + slots 6/7 reservation | 12/102/29 | slot reservation is live GPU contract (DN-53) | DEMOTE | slot-reservation → ARCHITECTURE §GPU Contract; Arachne narrative → design doc | high |
| D-093 | Arachne refractive dewdrops | 9/63/21 | shipped; design doc | RETIRE | DECISIONS_HISTORY | high |
| D-094 | Arachne 3D SDF spider + vibration | 21/149/37 | shipped; design doc | RETIRE | DECISIONS_HISTORY | high |
| D-095 | Arachne state machine + pool + cooldown | 27/414/47 | shipped; design doc §Operating rules | RETIRE | DECISIONS_HISTORY | high |
| D-096 | V.8.0 parallel-preset commit strategy | 5/92/24 | executed | RETIRE | DECISIONS_HISTORY | high |
| D-097 | particle presets: siblings, not subclasses | 51/467/**48** | standing particle architecture (DN-55) | DEMOTE | SHADER_CRAFT particle architecture + stays active | high |
| D-098 | DriftMotesNonFlockTest tolerances | 2/29/11 | Drift Motes code deleted (grep: zero files) | RETIRE | DECISIONS_HISTORY (protected code gone) | high |
| D-099 | engine MSL struct extension pattern (additive, golden-hash verify) | 40/310/48 | CommonLayoutTest + golden-hash sweep live (DN-57) | DEMOTE | ARCHITECTURE engine-MSL pattern + stays active; gates already cover the mechanical part | high |
| D-100 | Arachne §4 atmospheric reframe | 10/156/23 | shipped; design doc | RETIRE | DECISIONS_HISTORY | high |
| D-101 | `stems.drums_beat` canonical for particle beat reactivity | 14/107/15 | standing routing rule | DEMOTE | SHADER_CRAFT particle routing + stays active | high |
| D-102 | Drift Motes removed from catalog | 34/262/**52** | executed; lessons live as FA-58 + memory | RETIRE | DECISIONS_HISTORY | high |
| D-103 | Phase MD tier structure (AMENDED to inspired-by) | 19/195/20 | superseded by D-113 reframe | RETIRE | DECISIONS_HISTORY | medium |
| D-104 | Phase MD capability matrix per tier | 0/65/7 | planning artifact for unbuilt work; MD bloc carries DOC.4 REVISIT banner | RETIRE | DECISIONS_HISTORY | low |
| D-105 | Phase MD catalog presentation (AMENDED to one family) | 8/107/13 | superseded by reframe | RETIRE | DECISIONS_HISTORY | medium |
| D-106 | Phase MD settings exposure (AMENDED to one toggle) | 4/86/14 | superseded by reframe | RETIRE | DECISIONS_HISTORY | medium |
| D-107 | Phase MD hybrid candidate criteria | 0/64/12 | planning artifact | RETIRE | DECISIONS_HISTORY | low |
| D-108 | Phase MD per-stem hue affinity (optional) | 0/31/10 | capability never built | RETIRE | DECISIONS_HISTORY | low |
| D-109 | Phase MD section-awareness (optional) | 0/50/9 | capability never built | RETIRE | DECISIONS_HISTORY | low |
| D-110 | Phase MD transpiler scope retired | 10/215/14 | explicitly retired scope | RETIRE | DECISIONS_HISTORY | high |
| D-111 | license posture: inspired-by + attribution + takedown | 20/250/19 | standing legal posture for shipped ports (Dragon Bloom, Fata Morgana) | DEMOTE | stays active | high |
| D-112 | MD.5 candidate list (AMENDED to initial batch) | 18/155/15 | superseded framing | RETIRE | DECISIONS_HISTORY | medium |
| D-113 | inspired-by, not derivative, posture | 7/91/14 | standing brand/legal framing | DEMOTE | stays active | high |
| D-114 | release model: 20-preset first-release bundle | 7/85/20 | forecast-type commitment (FA #60 class); release planning will revisit | DEMOTE | stays active; flagged to Matt (§3.3) | low |
| D-115 | release-bundle composition 7+13 (AMENDED by D-119) | 11/113/23 | amended; default lives in D-119 | RETIRE | DECISIONS_HISTORY | medium |
| D-116 | substantial-similarity rule (AMENDED by D-121) | 6/152/21 | D-121 carries the operative rule | RETIRE | DECISIONS_HISTORY | high |
| D-117 | catalog-ratio framing (AMENDED by D-119) | 8/85/17 | amended away | RETIRE | DECISIONS_HISTORY | high |
| D-118 | skip in-engine read-only analysis tool | 11/105/15 | executed (tool skipped) | RETIRE | DECISIONS_HISTORY | high |
| D-119 | brand identity: Milkdrop-influenced modern platform | 5/97/16 | standing product identity; the evidence FA #60 wanted has since arrived (2 certified ports) | DEMOTE | stays active | high |
| D-121 | measurable visual divergence per port | 2/70/16 | standing rule for inspired-by presets | DEMOTE | stays active | high |
| D-122 | Phase MD kill-switch / re-evaluation triggers | 8/96/23 | standing triggers | DEMOTE | stays active | medium |
| D-123 | family taxonomy aligned to cream-of-crop themes | 25/169/30 | standing preset metadata taxonomy | DEMOTE | SHADER_CRAFT §17 + stays active | high |
| D-124 | Ferrofluid "ferrofluid replaces ocean" redirect | 51/412/33 | executed concept redirect; FFO shipped | RETIRE | DECISIONS_HISTORY | high |
| D-125 | §5.8 stage-rig contract (REVERTED by D-127) | 70/818/26 | explicitly reverted | RETIRE | DECISIONS_HISTORY | high |
| D-126 | matID==2 consumption paradigm (REVERTED by D-127) | 35/462/32 | explicitly reverted | RETIRE | DECISIONS_HISTORY | high |
| D-127 | stage rig retired; aurora reflection via direct audio uniforms | 20/368/39 | defines FFO's current aurora consumption; FBS work touches this surface now | DEMOTE | stays active (FFO design doc cross-ref) | medium |
| D-128 | local files use in-process AVAudioEngine | 31/118/15 | standing LF capture architecture | DEMOTE | stays active | high |
| D-129 | LF.2 blocking pre-analysis | 23/97/11 | embodied | RETIRE | DECISIONS_HISTORY | medium |
| D-130 | LF.3 persistent content-keyed stem cache | 24/137/13 | embodied | RETIRE | DECISIONS_HISTORY | medium |
| D-131 | LF.4 SessionManager integration + LRU | 16/122/12 | embodied | RETIRE | DECISIONS_HISTORY | medium |
| D-132 | LF.5 multi-file source + recents | 8/93/13 | embodied | RETIRE | DECISIONS_HISTORY | medium |
| D-133 | LF.6 album-art surface | 7/53/9 | embodied | RETIRE | DECISIONS_HISTORY | medium |
| D-134 | LF.6 streaming artwork resolver | 10/44/7 | embodied; BUG-024 lesson lives as DN-50 | RETIRE | DECISIONS_HISTORY | medium |
| D-135 | Dragon Bloom Spike 1 feedback bloom | 5/61/11 | superseded by the D-137/138 uplift line | RETIRE | DECISIONS_HISTORY | high |
| D-136 | Dragon Bloom bilateral symmetry | 10/45/4 | embodied | RETIRE | DECISIONS_HISTORY | medium |
| D-137 | Dragon Bloom feedback-native uplift | 13/340/11 | shipped preset design record | DEMOTE | Dragon Bloom design doc + stays active | medium |
| D-138 | faithful butterchurn render-loop port (component facts) | 23/184/10 | FA-70's durable component facts live here | DEMOTE | SHADER_CRAFT §18 porting + stays active | high |
| D-139 | Fata Morgana faithful port (sRGB/clock facts) | 22/242/13 | FA-71/72 reference it | DEMOTE | SHADER_CRAFT §18 + stays active | high |
| D-140 | `volumetric` PresetCategory | 12/67/8 | embodied enum (Nimbus certified) | RETIRE | DECISIONS_HISTORY | high |
| D-141 | Nimbus stem-driven beat lobes | 4/25/2 | shipped + certified | RETIRE | DECISIONS_HISTORY | medium |
| D-142 | canvas-hold as mv_warp CONFIG | 1/46/3 (recency) | standing render-engine config contract (Skein) | DEMOTE | stays active | medium |
| D-143 | marks-on-top + canvas-clear CONFIG | 0/57/3 (recency) | standing config contract | DEMOTE | stays active | medium |
| D-144 | Nimbus energy-warms-mood | 0/16/4 (recency) | shipped + certified; memory carries lessons | RETIRE | DECISIONS_HISTORY | medium |
| D-145 | Nimbus beat-grid live phase deferred to dedicated project | 3/38/4 (recency) | standing deferral; queued project | DEMOTE | BEAT_SYNC.md cross-ref + stays active | high |
| D-146 | per-band EMA pivot (BUG-027) | 0/19/5 (recency; load-bearing per current work) | live-path test guards (DN-18) | MECHANIZE | already-mechanized (named test); stays active as rationale | high |
| D-147 | Skein gated slot-6 + stem-colour contract | 1/31/3 (recency) | active Skein engine contract | DEMOTE | stays active | high |
| D-148 | BUG-029 AGC ease-in fix | 1/12/4 (recency) | shipped fix; release notes carry | DEMOTE | stays active short-term (FBS-adjacent surface); history candidate at next pruning pass | medium |
| D-149 | Skein wetness channel (canvas ALPHA) | 0/25/4 (recency; load-bearing per memory) | active engine contract | DEMOTE | stays active | high |
| D-150 | Skein colour-per-stroke breakpoint ring | 0/59/4 (recency) | active; certified preset depends on it | DEMOTE | stays active | high |
| D-151 | Skein structural-prediction bridge | 1/91/5 (recency) | active engine contract | DEMOTE | stays active | high |
| D-152 | Skein.5 musicality layer | 3/94/4 (recency) | active | DEMOTE | stays active | high |
| D-153 | FBS Stage 1 steady beat-pulse | 0/62/3 (recency; load-bearing per current FBS work) | active | DEMOTE | stays active | high |
| D-154 | FBS course-correction: beat-irregular exclusion | 3/71/3 (recency; amended per memory) | active | DEMOTE | stays active | high |
| D-155 | Skein palette library (Matt-curated) | 8/125/4 (recency) | active; DocIntegrityTests guard its presence | DEMOTE | stays active | high |
| D-156 | FBS ~10 s handoff to live drift-tracker | 0/40/3 (recency) | active | DEMOTE | stays active | high |
| D-157 | FBS beat-punch spatial footprint | 1/54/3 (recency) | active | DEMOTE | stays active | high |
| D-158 | FBS vocals-pitch → aurora-HUE | 4/105/3 (recency) | active | DEMOTE | stays active | high |
| D-159 | Skein.6 certification record | 4/59/2 (recency) | active cert record | DEMOTE | stays active | high |
| D-160 | FBS Stage 2 height-follows-loudness | 1/12/2 (recency) | active | DEMOTE | stays active | high |
| D-901 | (D-LM-buffer-slot-8) fragment slot 8 reserved for per-preset state | unmeasured | live GPU contract reservation | DEMOTE | ARCHITECTURE §GPU Contract slot table + stays active | high |
| D-902 | (D-LM-d5) LM band-routed beat dance | unmeasured | shipped; LM design doc (DOC.4 precedent) | RETIRE | DECISIONS_HISTORY; LUMEN_MOSAIC_DESIGN.md carries | high |
| D-903 | (D-LM-6) LM cell-depth gradient | unmeasured | shipped; design doc | RETIRE | DECISIONS_HISTORY | high |
| D-904 | (D-LM-7) LM per-track RGB tint projection | unmeasured | shipped; design doc | RETIRE | DECISIONS_HISTORY | high |
| D-905 | (D-LM-palette-library) curated 18-palette library, anti-repeat N=3 | unmeasured | operative in certified LM | DEMOTE | LUMEN_MOSAIC_DESIGN.md + stays active | high |
| D-906 | (D-LM-cream-rescission) pale-tone-share ceiling replaces anti-cream rule | unmeasured | operative project-wide palette rule (DN-32 gates) | DEMOTE | SHADER_CRAFT (palette rules) + stays active | high |

**D tallies:** KEEP 1 · MECHANIZE 9 · DEMOTE 65 · RETIRE 86.

---

## 3. Task 3 — Summary, budget, RB.2 sketch

### 3.1 Verdict counts

| population | KEEP | MECHANIZE | DEMOTE | RETIRE | total |
|---|---|---|---|---|---|
| FA | 5 | 9 | 27 | 8 | 49 |
| DN | 11 | 17 | 35 | 0 | 63 |
| SEC | 20 | 0 | 1 | 0 | 21 |
| D | 1 | 9 | 65 | 86 | 161 |
| **total** | **37** | **35** | **128** | **94** | **294** |

**KEEP reconciliation against the ~15 expectation.** 37 KEEP rows reduce to **12 distinct always-loaded rule slots** plus the structural section skeleton:

1. Beat-is-accent / Audio Data Hierarchy (FA-4 + DN-6 + SEC-6, one statement)
2. Deviation primitives (D-026 + FA-31 + DN-17, one statement)
3. Structural-gap-vs-tuning discriminator (FA-49)
4. Fixture/live dispatch-path parity + production-grade testing (FA-66 + DN-23)
5. Reference discipline parent rule (FA-73 + DN-1, absorbing #64/#65/#70/DN-2 as sub-bullets)
6. Never block the render loop (DN-3)
7. Never allocate in the IO proc (DN-4)
8. Cold-start beat-phase iteration ban (DN-16)
9–12. Four process rules embedded in kept protocol sections (DN-58 durable-learnings, DN-59 no-push, DN-60 evidence-first, DN-61 no-fix-in-diagnosis)

The remaining KEEP rows are the 20 section units (8 of which are 2–4-line pointers that RB.2 merges into a single Handbook-Index block) — skeleton, not rules. **Rule-level KEEP = 12 < 15.** ✓

### 3.2 Projected post-RB.2 mass and proposed token budget

Summing the KEEP material (identity + protocols + Audio Data Hierarchy + merged handbook index + trimmed Code Style + 5-entry FA table + ~10-line invariants list + universal Authoring-Discipline subset + status/constraints): **≈ 5,200 words ≈ 7,000 tokens** — a ~69 % reduction from today's 22,300.

**Proposed hard cap: 7,000 tokens (≈ 5,200 words, measured as `wc -w × 1.35`), enforced one-in-one-out.** Adding a rule above the cap requires demoting, mechanizing, or retiring another.

### 3.3 Flagged for Matt (all `confidence: low` rows + open flags)

Phrased at product level; each has a recommendation and a default.

1. **FA-15 / FA-16 (chroma + mood-input rules, pre-corpus).** These protect mood-classification quality, an area you experience as "does the colour mood match the song." The code grep was ambiguous about whether the protected pipeline still exists in the audited form. *Question: none for you to answer — this is a verification gap.* Recommendation: RB.2 verifies the chroma pipeline's current shape before moving these; default = DEMOTE to the audio-tuning handbook as written.
2. **D-039 dHash regression gate (RE-EVALUATE flag since 2026-05-13) + BUG-034.** The automated "did a preset's look change unexpectedly" tripwire is currently weakened: ray-march presets render differently in tests vs live (BUG-034), so its evidence for those presets isn't trustworthy until that bug is fixed. *Question: should BUG-034's fix be prioritized ahead of further ray-march preset work?* Recommendation: yes — it restores trust in the visual safety net. Default: keep current sequencing; the gate verdict (MECHANIZE/already) stands either way.
3. **D-058 (keyboard live-adaptation semantics) and D-074 (diagnostic preset behavior) carry RE-EVALUATE flags from 2026-05-13 that nobody has resolved.** *Question: do you still use the U.6b keyboard boosts and the diagnostic-hold behavior as designed?* Recommendation: resolve at next UX pass; default = leave active (DEMOTE verdicts stand).
4. **D-066 (Spotify as canonical reel source).** A stale strategy note about demo-reel production. *Question: is a demo reel still planned this way?* Recommendation: retire to history; default = RETIRE.
5. **Phase MD planning bloc (D-104/107/108/109 RETIRE-low rows).** These were forward plans for Milkdrop-port capabilities never built; the bloc already carries DOC.4's REVISIT banner. *Question: when the next Milkdrop-inspired preset is scoped, should planning restart from fresh evidence (the two certified ports) rather than these 2026-05-12 forecasts?* Recommendation: yes — retire the unexecuted planning entries, keep the posture/license/divergence rules (D-111/113/119/121/122, all DEMOTE-active). Default = RETIRE as tabled.
6. **D-114 (20-preset first-release bundle).** A product commitment made before most of the catalog existed. *Question: is 20 presets still the release bar?* Recommendation: revisit at release planning with the current certified count in hand; default = stays active unchanged.
7. **DN-51 (silent test skips) — confidence medium.** The named gate covers fixture-presence only; the general rule is judgment. Default: as tabled (gate + one Code Style line).
8. **D-148 (AGC ease-in) — medium.** Recent fix on a surface FBS still touches. Default: stays active; history candidate at the next pruning pass.

No KEEP overflow to flag (12 rule slots < 15).

### 3.4 RB.2 execution sketch (sketch only — not executed)

**File split:**
- **CLAUDE.md (slim core, ≤ 7,000 tokens):** identity, Build & Test, the two protocols, Audio Data Hierarchy (with the FA-4/D-026 canonical statements + compressed cold-start contract + DN-16), a single Handbook-Index block replacing the 8 pointer sections, trimmed Code Style, 5-entry Failed Approaches table + gap-table pointer, universal Authoring Discipline rules, ~10-line invariants list (DN-3/4 + mechanized-rule pointers), Current Status, Development Constraints.
- **docs/PRESET_SESSION.md (new; read-first for preset sessions):** preset-scope Authoring Discipline operationalia, the reference/README protocol (FA-39/63 hook description + manual fallback), the M7-prep contact-sheet checkpoint (FA-48), per-preset doc index (Arachne, LM, Skein, FFO, Dragon Bloom, Fata Morgana design docs), SHADER_CRAFT §13/§18 pointers.
- **docs/INFRA_SESSION.md (new; read-first for engine/DSP sessions):** BEAT_SYNC.md pointer + the beat-sync demotions (FA-50/51/68/69, DN-39/40/43), sample-rate and tap rules (FA-21/22, DN-42), orchestrator demotions (FA-53/54, DN-45/46/47/54), GPU-contract demotions (DN-53, D-901).

**Move list by destination:**
- `HISTORICAL_DEAD_ENDS.md` (tombstones): FA-1, 2, 3, 11, 17, 18, 59, 60.
- `DECISIONS_HISTORY.md`: the 86 D-RETIRE rows (§2.4).
- `SHADER_CRAFT.md` (§13 / §18 / cookbooks / §12.1 dedupes): FA-23, 24, 26, 32, 33, 58, 61, 62, 64, 65, 67, 70, 71; DN-2, 12, 15, 19, 21, 22, 24, 25, 26, 27, 31, 33, 34; D-019, 020, 022, 029, 045, 064, 065, 067, 101, 123, 138, 139, 906 content cross-refs.
- `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`: FA-50, 51, 68, 69; DN-39, 40, 43; D-075, 077, 145 cross-refs.
- `docs/ARCHITECTURE.md`: FA-15, 16, 28 notes; DN-8, 10, 42, 50, 53, 54; D-030, 057, 059, 080, 092 (slot table), 099, 901; SEC-20.
- `docs/RUNBOOK.md`: FA-21, 22 (troubleshooting), 27 (diagnostics), 29 env note, 30; DN-36, 37, 38 dedupes.
- `docs/UX_SPEC.md`: DN-28, 29, 30 dedupes; D-044, 051, 054, 058.
- `docs/presets/ARACHNE_V8_DESIGN.md`: FA-57; DN-52 pointer relocation.
- `docs/presets/LUMEN_MOSAIC_DESIGN.md`: D-902/903/904 narrative, D-905.
- Code comments: FA-21, 25, 28, 50, 53 sites; DN-42, 43 sites.

**MECHANIZE gate-build list (priority order):**
1. `Scripts/closeout_verify.sh` — re-runs suites, emits real pass/fail counts (REVIEW.1 P3; kills false-green closeouts).
2. Reference-README PreToolUse hook (FA-39/63/DN-20) — REVIEW.1 measured 35 % compliance; cheapest high-leverage gate.
3. MSL name lints: camelCase field names (FA-72) + type-keyword shadowing (DN-35) + `[[thread_index_in_mesh]]` (DN-11) — one script, three checks.
4. `setFeatures`-preserves-mood unit test (FA-25/DN-13/D-024).
5. `.storageModeManaged` lint (DN-5/D-006) + shader-path-literal lint (DN-7).
6. `elapsedSeconds`-is-Double type pin (DN-44) + `applyLiveUpdate` cooldown pin (DN-47).
7. First-visual budget checkpoint field in PRESET_SESSION.md template (REVIEW.1 P2) + M7-prep contact-sheet field (FA-48).
8. CLAUDE.md token-budget check script (ratchet rule 1).

**Session-prompt template changes:** preset kickoffs add "Read docs/PRESET_SESSION.md + the preset's VISUAL_REFERENCES README before any .metal edit"; engine/DSP kickoffs add "Read docs/INFRA_SESSION.md"; both templates gain the closeout-evidence (`closeout_verify.sh`) field.

### 3.5 Ratchet proposal (three standing rules for RB.2 to install)

1. **Token cap, one-in-one-out.** CLAUDE.md hard cap **7,000 tokens** (`wc -w × 1.35`), checked by script at every increment closeout that touches CLAUDE.md. Adding above the cap requires a same-commit demotion/retirement of equal or greater mass.
2. **New-rule admission test.** A new always-loaded rule must state, in the entry itself: (a) the specific prevented mistake, and (b) one line on why no deterministic gate can express it. Fails either → it goes to a handbook, a session file, or a gate instead.
3. **Violated-twice → mandatory mechanization.** The second documented violation of any prose rule converts it: the fix increment must ship the gate (script/test/lint/hook/template field) and demote the prose to a pointer, not extend the prose.

---

## Appendix — drift, not staleness (bug-shaped; handled per the doc-drift convention, not via RETIRE)

1. **DN-53 text vs code:** the bullet instructs extending RenderPipeline with `directPresetFragmentBuffer3/4` as a future action; `directPresetFragmentBuffer3` already exists (RenderPipeline.swift:367–385). Bullet text should be updated to reflect the present tense at RB.2 move time.
2. **SEC-13 §UX Contract numbering:** the section text says "copy principles (§8.5), the error taxonomy (§8)" while the What-NOT bullets correctly say §9.5/§9.4 ("was §8.5 pre-DOC.3"). The UX Contract section pointer is stale; trivial fix at RB.2.
3. **FA gap-table mapping note:** the #35–#40 → SHADER_CRAFT §13 mapping carries a numbering-mismatch note ("restated as §13 #35/#36/#38/#39/#42"); verify the §13 numbering when RB.2 moves additional entries into §13.
4. **D-039 / BUG-034 interaction:** the dHash gate is structurally sound but its ray-march evidence is currently invalidated by BUG-034 (fixtures march 32 steps vs live 128). Tracked in KNOWN_ISSUES; noted here because RB.2's MECHANIZE bookkeeping should not present the gate as fully trustworthy until BUG-034 lands.
