# Historical Dead Ends

This file catalogues dead APIs, deprecated frameworks, and one-time architectural dead-ends that no longer apply to active development. Entries live here when they describe **something that no longer exists** (an API that shut down, a framework that broke and is no longer relevant) rather than **a rule that prevents a recurring bug**.

The active-rule equivalents — Failed Approaches that catch real recurring patterns — live in `CLAUDE.md §Failed Approaches — Do Not Repeat`.

## Why this file exists

Two patterns were mixed in CLAUDE.md's Failed Approaches list:

1. **Dead APIs and frameworks:** "AcousticBrainz shut down 2022" / "Spotify Audio Features deprecated 2024" / "MediaRemote private framework banned post-macOS 15." These describe historical events. Useful as "don't go looking for this" pointers but not active behavioral rules.
2. **Active rules:** "Drive presets from audio deviation, not absolute energy" / "Never use synthetic audio in diagnostics" / "Beat onset is accent, never the primary motion driver." These describe rules that prevent recurring bugs today.

Mixing the two reduced the signal of every entry. The active rules stay in CLAUDE.md; the historical entries move here.

## Convention

Entries below preserve their original Failed Approach number from CLAUDE.md for cross-reference with git history. Each carries a one-line provenance footer recording when and why it moved here.

For entries describing **tech that may have evolved since the original observation** (BlackHole, ScreenCaptureKit audio, CoreML audio separation), the footer also records "last verified pre-macOS 26 / pre-CoreML 7.x." If a future session has reason to revisit, re-test against current platform versions before reinstating as an active Failed Approach.

---

## Audio capture dead ends

### #5 — BlackHole virtual audio driver

**Original entry:** BlackHole was broken on macOS Sequoia (macOS 15). Phosphene's needs were met without it via Core Audio taps (D-002).

> Moved to graveyard 2026-05-13 (DOC.3a). Last verified pre-macOS 26 / pre-BlackHole 0.6.x. Not actively blocking — D-002 Core Audio taps is the chosen architecture. Re-test against current platform if a future need to revisit virtual audio devices arises (e.g. browser-based Phosphene preview).

### #6 — Web Audio API AnalyserNode

**Original entry:** Web Audio API AnalyserNode broken for virtual audio devices on macOS.

> Moved to graveyard 2026-05-13 (DOC.3a). Phosphene is a native macOS app (D-001); Web Audio API is irrelevant to the current architecture. If a future browser-based companion target is scoped, re-test against then-current macOS + browser combinations.

### #7 — ScreenCaptureKit for audio-only capture

**Original entry:** Zero audio callbacks on macOS 15+/26 when using ScreenCaptureKit for audio-only capture (video discarded).

> Moved to graveyard 2026-05-13 (DOC.3a). Last verified pre-macOS 26.0; Apple has shipped substantial ScreenCaptureKit updates since the original observation. Not actively blocking — D-002 Core Audio taps via `AudioHardwareCreateProcessTap` is the chosen architecture. Re-test if a future need to capture audio + video together arises.

### #9 — MPNowPlayingInfoCenter for reading other apps' metadata

**Original entry:** `MPNowPlayingInfoCenter` only returns the host app's own Now Playing info on macOS — useless for reading Apple Music / Spotify metadata.

> Moved to graveyard 2026-05-13 (DOC.3a). Platform limitation by design; AppleScript polling is the working path (`Audio/StreamingMetadata`). No re-test expected — the API contract is intentional, not a bug.

### #11 placeholder

**Note:** #11 (MediaRemote private framework — "Operation not permitted from signed app bundles") stays in CLAUDE.md as an active Failed Approach because Apple's enforcement of private-framework restrictions is ongoing, and the rule still prevents a recurring bug ("don't reach for MediaRemote when AppleScript polling looks slow"). Cross-referenced here for completeness only.

---

## Metadata / streaming API dead ends

### #8 — AcousticBrainz

**Original entry:** Public API shut down 2022.

> Moved to graveyard 2026-05-13 (DOC.3a). Factual API death; no re-test possible (the service no longer exists). MusicBrainz (D-012) is the active free-tier metadata backbone.

### #10 — Spotify Audio Features endpoint

**Original entry:** `GET /v1/audio-features/{id}` deprecated November 2024; returns HTTP 403.

> Moved to graveyard 2026-05-13 (DOC.3a). Factual API deprecation; Spotify enforces 403. Phosphene's audio analysis is now self-computed via MIRPipeline + Beat This! (D-013, D-077). No re-test expected — Spotify will not restore the endpoint.

---

## ML / signal-processing dead ends

### #12 — HTDemucs CoreML conversion

**Original entry:** Complex tensor ops in HTDemucs block CoreML conversion.

> Moved to graveyard 2026-05-13 (DOC.3a). Last verified pre-CoreML 7.x. CoreML has matured significantly since the original observation (Apple shipped expanded complex-tensor support in iOS 17 / macOS 14, and MLX in 2024+). Not actively blocking — Phosphene uses Open-Unmix HQ via MPSGraph (D-009, D-010). Re-test if a future session has reason to revisit HTDemucs or other Demucs-family models for stem separation.

### #13 — End-to-end CoreML audio separation models

**Original entry:** No complex number support in CoreML blocks end-to-end audio separation models from converting.

> Moved to graveyard 2026-05-13 (DOC.3a). Last verified pre-CoreML 7.x. Same caveat as #12 — CoreML has evolved. Not actively blocking — MPSGraph path (D-009) is the chosen architecture for all ML audio processing. Re-test against current CoreML if a future need arises.

### #19 — Unweighted chroma accumulation

**Original entry:** Bin-count bias across pitch classes when accumulating chroma without bin-count normalisation.

> Moved to graveyard 2026-05-13 (DOC.3a). Calibration-specific learning; the correct approach (bin-count normalisation, weight = 1 / binsInPitchClass) is documented in CLAUDE.md §Audio Analysis Tuning §Chroma. No active rule needed — `ChromaExtractor.swift` implements the correct form by construction.

---

### #14 — Raw MLMultiArray.dataPointer with ANE Float16 outputs

**Original entry:** Raw `MLMultiArray.dataPointer` with ANE Float16 outputs — padded strides cause SIGSEGV.

> Moved to graveyard 2026-06-11 (DOC.4). A CoreML-API gotcha for an API Phosphene does not use: D-009 chose MPSGraph over CoreML for all ML inference, and no source file imports CoreML (verified at move time). Companion of #12/#13 above. Re-instate as an active Failed Approach only if a future session revisits CoreML.

### #20 — CoreML ANE outputs with bindMemory(to: Float.self)

**Original entry:** CoreML ANE outputs with `bindMemory(to: Float.self)` — Float16 misinterpreted as Float32.

> Moved to graveyard 2026-06-11 (DOC.4). Same rationale as #14: a CoreML-API gotcha; CoreML is unused (D-009, MPSGraph). Re-instate only if CoreML is revisited.

## Cold-start beat-phase derivation dead ends

### Six iterations on automated short-window cold-start beat-phase derivation (CS.1 → BSAudit.3, 2026-05-22 → 2026-05-25)

**The shared premise (now falsified):** "there is some automated signal in the first ~3 s of live tap audio that reliably tells us the audible beat phase of a novel track." Six iterations attempted to identify and use such a signal; each used a different mechanism; each failed in a different way. None converged on > 70 % of the 10-track reference catalog. The premise was retired under Matt's Choice A decision 2026-05-25.

| Iteration | Mechanism | Result | Why it failed | Reference |
|---|---|---|---|---|
| CS.1 | Trust cached `BeatGrid` phase from frame 1 (`offsetBy(0)`) | 3/10 PASS the ±50 ms / 90 % bar | Preview clip is a mid-song excerpt; preview-time clock ≠ track-time clock | [`KNOWN_ISSUES.md` BUG-017](QUALITY/KNOWN_ISSUES.md), CS.1 baseline |
| CS.1.y.2 | Phase-lock from first live sub-bass onsets | 0/10 PASS, reverted | Sub-bass detector fires on sub-bass *events* (bassline notes, 808s), off-beat on syncopated tracks. Confidence gate on cluster *tightness* can't distinguish on-beat cluster from off-beat cluster. | [CLAUDE.md Failed Approach #68](../CLAUDE.md#failed-approaches--do-not-repeat) |
| CS.1.y re-diagnosis | Beat This! on 3–5 s live tap | 1–3/10 viable, non-reproducible across captures | Short windows degrade Beat This!'s tempo + period estimation | `KNOWN_ISSUES.md` BUG-017 addendum (CS.1.y re-diagnosis) |
| CS.1.y.2-redo r1 | Beat This!@15 s snap (default horizon bug) | engine bug `horizon: 300`; refixed | Implementation bug — `horizon: 0` patch landed | `RELEASE_NOTES_DEV.md [dev-2026-05-23]` |
| CS.1.y.2-redo r2 | Beat This!@15 s snap | 4/7 cap2 pass, cross-capture unstable on cap3 + cap4; reverted | Beat This!@15s is per-capture stable but cross-capture unstable on 5–6 of 10 catalog tracks ([BSAudit.2 finding](CAPABILITY_REGISTRY/BEAT_SYNC.md#addendum--bsaudit2-path-a-findings-2026-05-24)) | `[dev-2026-05-24-a]` |
| BSAudit.3.impl | BPM-prior + broadband-peak phase acquisition + confidence-gated accents | 4/10 PASS-firing\|degraded on the new metric (fresh capture `2026-05-25T15-20-49Z`); architecture retained but ±60 ms / 3 s perceptual sub-goal retired | Broadband flux fires on pre-beat content (pad swells, vocal entries) — anchors off-beat on 5/10 tracks. Confidence accumulator doesn't back-pressure because periodic content at quarter-note rates reinforces *any* phase that matches the period. | [`BSAUDIT_3_VALIDATE_3_DIAG_2026-05-25.md`](diagnostics/BSAUDIT_3_VALIDATE_3_DIAG_2026-05-25.md) |

**The active rule that retired this dead-end pattern:** [CLAUDE.md Failed Approach #69](../CLAUDE.md#failed-approaches--do-not-repeat) — don't file iteration #7 on this defect without a fundamentally different premise. Any future cold-start beat-phase work requires either:
- A human-tap reference (BSAudit-FU-5 Path B — small CLI + ~4 min of Matt's taps for the 10-track catalog).
- Full-track local-file analysis (not currently available given the streaming-only constraint).
- Manual per-track calibration UX (not currently scoped).

Anything in the short-window-tap-audio family has been exhaustively explored.

**What lives in production today (AMENDED 2026-05-26):** the pre-BSAudit.3.impl baseline — cached BeatGrid install via `MIRPipeline.setBeatGrid`, `LiveBeatDriftTracker` in pre-impl form, `GridOnsetCalibrator` reinstated, ungated beat accents from frame 1. The BSAudit.3.impl runtime described in the table above was reverted on 2026-05-25 evening (`33cd57e9` / `6758a617` / `002b5f2b` / `35305b5e`) after Choice A's "doc-only closeout"; only the diagnostic tooling was retained per Matt's "yes, keep the tools" sign-off. The contract is documented in [CLAUDE.md §Cold-Start Phase Contract](../CLAUDE.md#cold-start-phase-contract) (rewritten 2026-05-26 to describe the post-revert state). The behavior at the design level: continuous-energy modulation from frame 1; beat accents fire from the cached grid from frame 1 (ungated; wrong-phase tracks fire wrong-phase accents); steady-state lock improves as the `LiveBeatDriftTracker` EMA converges.

> Moved to graveyard 2026-05-25 (BSAudit.3.close). Last verified against capture `2026-05-25T15-20-49Z`. AMENDED 2026-05-26 — the BSAudit.3.impl runtime that was the production architecture at graveyard time was reverted same evening; this dead-ends entry retains the historical iteration table since the structural lesson (no short-window automated signal converges) holds independent of which runtime is in place. The active rule (Failed Approach #69) catches the recurrence pattern; this entry catalogues the six historical iterations so future-Claude can see the dead-end shape at a glance. *(RB.2 note, 2026-06-11: the FA #69 entry was removed from CLAUDE.md in the rulebook purge; the operative ban lives on in CLAUDE.md §Cold-Start Phase Contract and in this file.)*

---

## RB.2 rulebook purge (2026-06-11)

Matt's per-entry review of every active Failed Approach and Do-NOT bullet (plain-English context: [`docs/diagnostics/RB1_FA_DN_EXPLANATIONS.md`](diagnostics/RB1_FA_DN_EXPLANATIONS.md); decisions given in-session 2026-06-11) removed the entries below from CLAUDE.md. Kept as active CLAUDE.md entries: FA #4 (pending Matt's relevance ruling), #27, #31, #64, #65, #67, #73, and the `@Published` write-or-clear bullet. Full original text of everything removed: git history (CLAUDE.md immediately before the `[RB.2]` purge commit). One line each:

- **FA #1 — IIR energy-difference beat detection.** Machine-gun false positives; superseded by Beat This! + per-band spectral flux.
- **FA #2 — Rising-edge accumulation.** Same dead technique family as #1.
- **FA #3 — Per-bin spectral-flux thresholds.** Untunable across genres; same superseded era.
- **FA #11 — MediaRemote private framework.** Blocked from signed bundles on macOS 15+; comments at the code sites remain.
- **FA #15 — Chroma from <500 Hz FFT bins.** Bin resolution too coarse for pitch; pre-history mood-pipeline note.
- **FA #16 — Raw 12-bin chroma into the mood MLP.** Model needs engineered features; pre-history note.
- **FA #17 — "Autocorrelation half-tempo" narrative (amended).** Misdiagnosis story; real fixes documented as D-075/D-077.
- **FA #18 — Median threshold on rectified flux.** Mostly-zeros signal → median ≈ 0; superseded era.
- **FA #21 — Empty-mixdown tap description = silence.** Now a comment at `SystemAudioCapture.buildTapDescription`.
- **FA #22 — Tap silent without screen-capture permission.** Code requests permission; RUNBOOK troubleshooting documents it.
- **FA #23 — Audio-deformed architecture reads broken.** D-020 + your M7 carry it.
- **FA #24 — Tint IBL ambient, not just the key light.** D-022; rendering fact.
- **FA #25 — Mood must take the `setMood` path to the GPU.** Embodied in `RenderPipeline`; no gate yet (noted follow-up).
- **FA #26 — Beat pulse from max of bands, not bass alone.** Shipped presets comply.
- **FA #28 — AVAssetWriter transient drawable-size lock.** Fix embodied in `SessionRecorder+Video` with counters.
- **FA #29 — 44.1 kHz assumption (environment layer).** `check_sample_rate_literals.sh` + RUNBOOK carry it.
- **FA #30 — Spotify volume normalization.** RUNBOOK setup fact.
- **FA #32 — Feedback pass required for compounding motion.** D-027 + Milkdrop doc + handbook.
- **FA #33 — Free-running `sin(time)` motion.** Handbook craft note.
- **FA #39 — No authoring without references.** Replaced by `docs/PRESET_SESSION_CHECKLIST.md`.
- **FA #48 — Spec-faithful but reference-divergent.** Workflow it patched was abandoned (V.8 pivot); contact-sheet practice lives in the checklist + replay infrastructure.
- **FA #49 — Structural gap vs. tuning gap.** Judgment heuristic; the absolute form over-restricted (Matt 2026-06-11).
- **FA #50 — Cross-band onset fusion biases IOI tempo.** Fixed in `BeatDetector` (D-075).
- **FA #51 — Histogram-mode BPM picking.** Fixed (`computeRobustBPM`, D-075).
- **FA #52 — Literal `44100` in live-rate paths.** CI script enforces (D-079).
- **FA #53 — Summed AGC stem energies saturate scoring.** Fixed in `PresetScorer` (D-080).
- **FA #54 — Empty-profile reactive scoring inversion.** Fixed (D-080).
- **FA #55 — Shadow `SettingsStore` instance.** `SettingsStoreEnvironmentRegressionTests` enforces.
- **FA #56 — Title+artist string matching.** `PlaybackChromeIndexBindingTests` enforces.
- **FA #57 — Spider trigger on impossible signal combination.** Arachne design doc carries the corrected trigger.
- **FA #58 — Concept without a musical role is untunable.** §Authoring Discipline + SHADER_CRAFT concept gate carry it.
- **FA #59 — Schema additions without a demonstrated consumer.** D-120 episode; strategy clause carries it.
- **FA #60 — Batch-filed strategy decisions.** Phase MD episode; strategy clause + REVISIT banner carry it.
- **FA #61 — Mirror-surface beams as point lights.** Handbook material fact (mirror-reflects-sky).
- **FA #62 — Decoration layers without a musical role.** §Authoring Discipline layer-scope rule carries it.
- **FA #63 — Authoring without the references README.** Replaced by `docs/PRESET_SESSION_CHECKLIST.md`.
- **FA #66 — Fixture/live dispatch-path parity.** Habit + infrastructure carry it (`useMeshPath` param, live-path tests in recent work); residue: after 2 rounds of fixture-clean/live-broken, check the test/prod gap first.
- **FA #68 — Sub-bass onsets are events, not beats.** BEAT_SYNC.md registry documents in full.
- **FA #69 — Cold-start beat-phase premise falsified ×6.** Ban lives in CLAUDE.md §Cold-Start Phase Contract + this file (above) + BEAT_SYNC.md.
- **FA #70 — Port a reference's loop wholesale.** Folded under kept FA #73; component facts in D-138.
- **FA #71 — Colour-space + clock audits when porting.** D-139 + handbook porting notes.
- **FA #72 — Swift camelCase names in MSL.** `PresetLoaderCompileFailureTest` catches the symptom (noted lint follow-up).

The §What NOT To Do list was reduced in the same review from 57 bullets to one (the `@Published` write-or-clear rule). The removed bullets were restatements of the FAs above, rules enforced by existing scripts/tests, facts embodied in shipped code (with doc comments at the sites), or duplicates of handbook/UX_SPEC/RUNBOOK canonical text — per-bullet context in the explanations doc.
