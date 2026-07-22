# Phosphene — Decision Log

Each decision records the what, why, and any relevant context that would prevent a future contributor from re-litigating it. Numbering is permanent and entries are never deleted — superseded decisions are marked as such with a pointer to the replacement, and inactive entries (shipped long ago, no longer cited by an active decision) rotate to `DECISIONS_HISTORY.md`, where they remain searchable under their D-numbers.

## Index

| D-### | Status | One-liner |
|---|---|---|
| D-002 | Accepted | Core Audio process taps are the default capture path |
| D-009 | Accepted | No CoreML; MPSGraph + Accelerate for all ML inference |
| D-014 | Proposed | Orchestrator as explicit scoring/policy system |
| D-019 | Accepted | Stem-routing warmup fallback pattern for compute presets |
| D-018 | Accepted | SessionManager degrades to ready on any preparation failure |
| D-020 | Accepted | Architecture-stays-solid for ray-march scene presets (Option A) — subject preset Glass Brutalist retired, see D-186 |
| D-022 | Accepted | IBL ambient tinted by `lightColor` so mood shifts are visible |
| D-026 | Accepted | Preset shaders drive from audio deviation, not absolute energy |
| D-027 | Accepted | Per-vertex feedback warp (mv_warp) as opt-in render pass |
| D-029 | Accepted | Preset motion sources are alternative paradigms, not composable layers |
| D-030 | Accepted | SpectralHistoryBuffer as unconditional GPU contract at buffer(5) |
| D-032 | Accepted (amended D-080) | Preset scoring weights and multiplicative penalty structure |
| D-033 | Accepted | Transition policy: structural-boundary priority, energy-scaled crossfades |
| D-044 | Accepted | SwiftUI accessibility identifiers: static constants + binding, not traversal |
| D-045 | Accepted | Utility library naming: unprefixed snake_case, no legacy renaming |
| D-051 | Accepted | UserFacingError in engine Shared; condition-ID toast semantics |
| D-054 | Accepted | AccessibilityState architecture and beat-clamp boundary |
| D-053 | Accepted | PresetScoringContext gains excludedFamilies + qualityCeiling, backward-compatible |
| D-057 | Accepted | Frame Budget Manager: governor design, OR-gate, tier targets |
| D-058 | Accepted | U.6b live-adaptation keyboard semantics and undo architecture |
| D-059 | Accepted | ML dispatch scheduling: scheduler design, budget signal, deferral caps |
| D-064 | Accepted | Visual references library structure, exemptions, lint tool, quality reel |
| D-065 | Accepted | Composite-preset image counts; AI-generated anti-reference carve-out |
| D-067 | Accepted | Certification pipeline placement, lightweight exemptions, manual gate |
| D-073 | Accepted | Per-section `maxDuration` linger factors inverted (Option B) |
| D-074 | Accepted | Diagnostic preset orchestrator semantics |
| D-075 | Accepted | Tempo BPM via sub_bass-only onsets + trimmed-mean IOI |
| D-077 | Accepted | Phase DSP.2 pivot from BeatNet to Beat This! |
| D-078 | Accepted | Diagnostic hold semantics; prepared-BeatGrid authority |
| D-079 | Accepted | Sample rate captured once per tap install; literal 44100 banned |
| D-080 | Accepted | Stem-affinity scoring uses deviation primitives + mean formula |
| D-092 | Accepted | Arachne staged WORLD + WEB port |
| D-097 | Accepted | Particle preset architecture: siblings, not subclasses |
| D-099 | Accepted | Engine MSL FeatureVector/StemFeatures extended to match preset preamble |
| D-101 | Accepted | `stems.drums_beat` as canonical particles-family beat-reactivity field |
| D-LM-buffer-slot-8 | Accepted | Fragment buffer slot 8 reserved for per-preset CPU-driven state |
| D-111 | Accepted (amended ×2) | Phase MD license posture: provenance + attribution + takedown |
| D-113 | Accepted | Phase MD posture reframe: inspired-by, not derivative-of |
| D-114 | Accepted | Phase MD release model: 20-preset first-release bundle |
| D-119 | Accepted | Product brand identity: Milkdrop-influenced modern platform |
| D-121 | Accepted | Phase MD visual-divergence rule |
| D-122 | Accepted | Phase MD kill-switch / re-evaluation triggers |
| D-123 | Accepted | `family` taxonomy aligned to cream-of-crop themes; D-120 superseded |
| D-127 | Accepted | Stage rig retired; aurora reflection via direct audio uniforms |
| D-LM-palette-library | Accepted (amended ×2) | Curated 18-palette library for Lumen Mosaic cell colour |
| D-LM-cream-rescission | Accepted | Anti-cream rule rescinded; pale-tone-share compositional ceiling instead |
| D-128 | Accepted | Local-file playback uses in-process AVAudioEngine, not process tap |
| D-137 | Accepted | Dragon Bloom: feedback-native uplift, not literal Milkdrop copy |
| D-138 | Accepted | Dragon Bloom: faithful butterchurn render-loop port, certified |
| D-139 | Accepted | Fata Morgana: faithful mirage port + bar-sway stem uplift, certified |
| D-142 | Accepted | Canvas-hold accumulation is identity CONFIG of brush-on-feedback paradigm |
| D-143 | Accepted | Marks-on-top + per-preset canvas-clear are brush-on-feedback CONFIG |
| D-145 | Accepted | Nimbus beat-grid live phase deferred to its own project |
| D-146 | Accepted | BUG-027 fix: per-band EMA pivot for band deviations |
| D-147 | Accepted | Gated slot-6 marks-on-top buffer + Skein.3 stem-colour contract |
| D-148 | Accepted | BUG-029 fix: AGC loudness meter eased in per track start |
| D-149 | Accepted | Canvas alpha carries decaying wetness, read by Skein comp fragment |
| D-150 | Accepted | Colour-breakpoint ring freezes pour-line colour per-segment |
| D-151 | Accepted | Gated setStructuralPrediction bridge delivers live section signal to presets |
| D-152 | Accepted | Skein musicality: lay-time mood, structural pour offsets, anticipation τ-warping |
| D-153 | Accepted | FBS Stage 1: first-NOTE-anchored cached-tempo beat pulse, never drift-corrected |
| D-154 | Accepted (FFO ban retired by amendment) | Beat-irregularity exclusion mechanism; pulse becomes slow 4-beat heave |
| D-155 | Accepted | Skein palette library: five Matt-curated palettes, deterministic per-track picker |
| D-156 | Accepted (amended) | Invisible handoff from bridge pulse to live beat |
| D-157 | Accepted | Regional beat punch: bounded spike-field regions, steady global luminance |
| D-158 | Accepted (amended) | Vocals-pitch hue route was the flasher; aurora transitions slowed |
| D-159 | Accepted | Skein certification: lightweight rubric, FNV-1a seed, canvas soak |
| D-160 | Accepted | FBS Stage 2: punch height follows passage loudness [0.30, 1.0] |
| D-161 | Accepted | Rulebook restructure + CLAUDE.md token-budget ratchet |
| D-162 | Accepted | Doc rotation mechanized (rotate_docs.sh); budgets gated by DocIntegrityTests |
| D-163 | Accepted | Audit keep-list + executableTarget STATUS markers guard dead-code audits |
| D-164 | Accepted | Photosensitivity flash-safety enforced by measurement (cert gate now) + runtime clamp (A-next); single-pass harness validly covers 2/7 presets, rest deferred to a real-pipeline harness (clamp half closed by D-166) |
| D-165 | Accepted | Silent-tap family: detect don't churn — only rebuild a never-delivered tap; pause-suppressed card; self-healing > manual remediation |
| D-166 | Accepted | Photosensitivity runtime clamp NOT pursued (amends D-164) — the certification gate is the enforcement mechanism; pipeline has no single clamp chokepoint (8 present paths), all shipped presets ≤ 1 flash/s; `RayMarchPipeline:94` OR-flag slot reserved |
| D-167 | Accepted | Thermal + Low Power Mode feed a quality floor into the D-057 budget governor (CLEAN.4.6): applied level = `max(timing, thermalFloor)` pre-empts the GPU's own throttle; FBM stays `ProcessInfo`-free; serious→no-bloom, critical→step-0.75, LPM→≥no-SSGI; ultra/recording still exempt |
| D-168 | Accepted | ARCHITECTURE Module Map completeness gated by DocIntegrityTests (CLEAN.7.3) — backfilled 62 undocumented files incl. 4 certified presets; D-161 "violated twice → mechanize" applied |
| D-169 | Accepted | Defer public-release-readiness work (extended a11y settings 7.7, cold-install resilience 7.8) until there's a public build; daily single-user dev use is covered by the existing a11y/robustness basics |
| D-170 | Reversed | Section detection (McFee/Ellis spectral clustering, SECDET) — built + live-tested, then **removed** 2026-06-24: structurally local-file-only (streaming has only a 30 s preview) and below the perceptual bar (live F@3 ≈ 0.29–0.41); the "no-ML" rationale was a misreading of D-009 (= no-CoreML). Planner equal-slices. See §Reversal. |
| D-171 | Accepted | Nacre — faithful port of butterchurn `$$$ Royal - Mashup (431)` (iridescent jello-mirror) onto a dedicated custom-warp+comp mv_warp branch (`RenderPipeline+Nacre`, mirroring Fata Morgana / D-139; `isNacre` discriminator). Faithful base first (NACRE.2b); the 3 greenlit uplifts deferred to NACRE.3+. Corrected source decode (mv_a-0 grid doesn't advect; volume-gated core seed; bassDev kick). **CERTIFIED NACRE.4** — connection lands via a downbeat camera push. |
| D-172 | Accepted | Floret — faithful port of butterchurn `suksma - Rovastar - Sunflower Passion` onto the dedicated `RenderPipeline+Floret` mv_warp branch (`isFloret`, the D-171 register). z² conformal warp + 1/r² vortex swirl + 3-fold radial-pulse kaleidoscope comp; motion = beat-lock downbeat magnify + energy swell + bass spin + bass-onset kick. **CERTIFIED FLORET.4** (Matt live M7). Drum sparkle tried + removed (camouflaged into the bright field). |
| D-173 | Accepted | Glaze — faithful port of butterchurn `Flexi + stahlregen - jelly showoff parade` onto the dedicated `RenderPipeline+Glaze` mv_warp branch (`isGlaze`, the D-171 register). A 3-mass spring-mass "jelly" (bass↔other stem anchor + fullness lift) drags a swirl-poke across an accreting field; 3-level blur-pyramid emboss/sheen + per-stem accents (drums punch / vocals glow) + HDR bloom; connection lands via a discrete downbeat camera push. The catalog's first physics-of-the-beat preset. **CERTIFIED GLAZE.8** (Matt live M7). |
| D-174 | Accepted | Filigree — physarum agent-network preset (`PhysarumGeometry`, a `ParticleGeometry` sibling per D-097; Kintsugi gold-on-black). Energy drives merge/divide (LOUD → fine/busy/bright web; QUIET → few calm cells) + a per-beat hit pulse + a rare re-seed burst. **Substrate verdict (Matt-accepted): physarum carries a loose energy-accompaniment, not tight event-sync** — tightly-synced cell merge/divide is reaction-diffusion's domain (a separate future preset). **CERTIFIED PHYS.5** (Matt live M7) — the first certified compute-agent-network preset. |
| D-175 | Accepted | Ricercar — contrapuntal visual-music painting preset (Fischinger / color-organ; Bach BWV 565 showcase, reusable). Ricercar.2 lands the flowing-colour-field SUBSTRATE: Skein's canvas-hold mv_warp reconfigured to a curl-noise flow warp + **decay toward a LIGHT GROUND** (a per-prefix `ricercar_warp_fragment` override — preset-side, no engine work) so the field breathes back to light at rest (silence-non-black, D-037) and matches the `02_meso` ink-plume reference. Hand-fed colour masses; voices/audio/cert at Ricercar.3.x→.7. Uncertified. **★ Substrate concept SUPERSEDED by D-176.** |
| D-176 | Accepted | Ricercar concept REVISED (Matt, 2026-06-29) — **the orchestra painting itself**: each section gets a painterly IDENTITY (colour + weight + texture + material), sync rides on top. Built on **Skein's marks-on-top painterly engine** (the elegant/luminous sibling — graceful composed strokes + Fantasia jewel-palette on a light canvas, vs Skein's chaotic earthy drip; FA #73 reuse). Abandons the D-175 flowing-colour substrate (a passive field reads as slick wallpaper, not art) AND the Filigree agent-voices + Ricercar.3.x engine bridge (use Skein's overlay marks → **no engine touch**). Five register-archetype sections. Design center = the per-section identity table in RICERCAR_DESIGN §CONCEPT. |
| D-177 | Accepted (finding; build deferred) | Instrument-family CAPTURE is feasible via on-device audio-tagging **RECOGNITION (not separation)**. Spike (2026-06-29, PANNs CNN14 on Sym5 + a Beethoven wind octet): family-level activity captures + **discriminates** strings/brass/woodwinds/percussion, tracks the music, reports absence — a leap over 4-stem (→"other") + register-proxy. Separation is unsolved for orchestra (0–4.5 dB SDR). Ceilings: family-level only, cross-family confusion on sustained timbres, buried families approximate. Scoped as a ~Beat This!-scale MPSGraph increment (`docs/INSTRUMENT_FAMILY_CAPTURE_SCOPING.md`); **DEFERRED to a fresh session pending Matt's comparison with a competing musicality idea.** Resolves Ricercar's instrument-capture hold (D-176). |
| D-178 | Accepted | Phase TONAL — continuous harmonic state via the Tonal Interval Vector (TIV; Bernardes 2016). A weighted 12-point complex DFT of the **already-computed** chroma vector per MIR frame → 5 FeatureVector floats (fifths phase, thirds phase, consonance, tension, harmonic flux). **No new ML, no new DSP stage** (consumer of `MIRPipeline.latestChroma`), 5 reclaimed pads. The palette-coherence + long-arc channel (hue on the circle of fifths, tonal tension → slow macro state), NOT a sync channel — relationships never labels, hue never brightness. TONAL.0 capability-audited (`docs/TONAL_ANALYSIS_SCOPING.md`); **Matt GO (2026-07-08), first preset = Nacre.** |
| D-179 | Accepted | Skills architecture (DOC.9) — increment-type-scoped protocols move from always-loaded CLAUDE.md to `.claude/skills/*/SKILL.md` (progressive disclosure): closeout, defect-handling, doc-pruning, preset-session, shader-authoring. CLAUDE.md keeps cross-increment invariants + one-line pointers; each skill is canonical for what it owns and a pointer for what handbooks own. Admission test amended: skills are the preferred demotion target for increment-type-scoped rules. `DocIntegrityTests.skillIntegrity` gates presence/frontmatter/citations. CLAUDE.md 6,701 → 3,164 est. tokens. |
| D-180 | Accepted | Per-preset audio route-coverage gate (QG.1) — every preset declares its audio routes in an `audio_routes` sidecar manifest (`{route, primitive, kind}`, SHADER_CRAFT §17.1); `RouteCoverageTests` replays canonical real-audio fixtures and asserts each declared primitive fires per its kind's floor (continuous: non-constant; accent: ≥1 rising crossing/fixture; structural: ≥1 section boundary in the set). Certification requires a non-empty manifest whose routes are all green. **A red route is the gate working — file it as a defect, never tune the floor.** Mechanizes the per-route firing evidence that was a prose closeout obligation (the `vocalsPitchConfidence`-at-0%-for-5-months class). §Rationale below. |
| D-181 | Accepted | The mid-session render-comparison sheet (`Scripts/compare_render.sh`) is the mandatory pre-commit perception step for preset increments (QG.2, mechanizing REVIEW.1's 35 %-compliance prose rule). Before every tuning commit: composite the newest `RENDER_VISUAL=1` frames against the curated references, Read the sheet, write a verdict table (`trait \| reference filename \| PASS/FAIL \| what differs`), anti-reference rows mandatory. Reader-is-the-eyes — no CLIP/dHash auto-score (D-064). Enforced via `docs/PRESET_SESSION_CHECKLIST.md` Part 1 step 5; sheet is the canonical closeout §3 artifact. |
| D-182 | Accepted | Per-paradigm multi-frame harness templates (QG.4) — every rendering paradigm gets a named, env-gated (`HARNESS_TEMPLATES=1`) reference harness driving the same dispatch path the live app uses, built on a shared `HarnessTemplateCore` spine, so PRESET_SESSION_CHECKLIST's "write the multi-frame harness FIRST" is a copy-adapt not a from-scratch build: `mv_warp`→`AuroraVeilMVWarpAccumulationTest` (re-based on the core), `staged`→`StagedPathHarnessTemplate` (Arachne), `ray_march`→`RayMarchPathHarnessTemplate` (Lumen Mosaic), `feedback`→`FeedbackPathHarnessTemplate` (Membrane). Each captures a final-frame dHash golden + a paradigm liveness metric; each A/B-validated (a mis-bound slot / skipped pass reddens it). Env-gated, not in the default parallel run — wired into `closeout_evidence.sh`. §Rationale below. |
| D-183 | Accepted | Signal health monitor (ASH.1) — `SignalHealthMonitor` classifies input-chain health continuously from the raw pre-AGC tap into `SignalHealth` {peakBand (healthy ≥ −12 / low −15…−12 / critical dBFS), deadTap (`.silent` past a 45 s confirm, gated to process-tap modes), sampleRateMismatch (default-output outside 44.1/48 kHz)}, published to session.log + debug overlay on change. **Observes only — never steers tap recovery** (D-165 acts; D-183 classifies). Realtime-safe ingest; classification/emit off-thread. Turns the RUNBOOK triage catalog into running code. ASH.1 = engine + debug surfacing; user-facing surfacing + degraded-audio certify/record policy are ASH.2. |
| D-184 | Accepted | Signal-health surfacing + post-session chain analyzer (ASH.2). (1) **One user-facing toast**: a once-per-session `band=low` nudge (reuses `audioLevelsLow` — Spotify "Normalize Volume" copy, generic otherwise). `deadTap` is NOT toasted — the existing `AudioStallOverlayView` card already covers it earlier (~10 s) and more prominently (Matt's call); `sampleRateMismatch` stays overlay/log-only. (2) **`ChainAnalyzer`** (Shared) grades every finished session dir → `chain_health.json` + a `CHAIN_HEALTH: verdict=<clean\|degraded\|broken> reasons=[…]` line, run in-process at `SessionRecorder.finish()` and out-of-process via `Scripts/analyze_session_chain.sh` (retroactive grading). Verdict driven by raw_tap peak + SIGNAL_HEALTH/DRM/dead-tap log scans. (3) **Empirical finding**: the Love Rehab sub-bass onset count is **AGC-invariant** (attenuation, dynamic compression, hard limiting, −50 dB all hold ~11/5 s) — it is REPORTED, never gated. Normalization is caught by the PEAK check, not onsets. **Does not gatekeep playback** — surfaces and continues. |
| D-185 | Accepted | Aurora Veil reauthored as a **faithful nimitz "Auroras" port** (AV.7). Supersedes the AV.5 footprint direction, which reserved this D-number but was never written and never shipped. Successive AV.2–AV.6 accretions (footprint `F(x)`, 3-column parallax, band undulation, drum kink, traveling waves) were each a negotiation away from the working reference (FA #65) and each cost fidelity; all were deleted. Kept: nimitz's real 3D ray march, `triNoise2d`, running-average smear, per-step H(z) palette, his `bg`/`stars`, and his constants. Re-framed to a **static upward sky** (no horizon/ground/reflection; the camera pan was removed because it made the view-indexed stars scintillate). Reactivity is three non-competing axes: **stars→downbeat** (`bar_phase01`, gated by `pulse_amp01`, flash-safe by sparse footprint), **brightness→mood envelope** (`arousal`, clamped 0.85–1.15) with a subordinate smoothed-bass lift (`bass_att_rel`), **colour→mood** (`valence` → whole-palette phase). nimitz's source is CC-BY-NC-SA; shipped credited with Matt's explicit approval. |
| D-186 | Accepted | Glass Brutalist preset retired (GBRETIRE.1, 2026-07-19). Ray-march "brutalist corridor" concept fails the viability gate: D-020 deliberately makes the concrete audio-static, so the hero subject can never be an instrument; also 2006-tier fidelity. All preset code/tests/docs/visual-refs deleted; production count 27 → 26. See D-186 section for full rationale. |
| D-187 | Accepted | Phase RMENV — ray-march render environment as an opt-in, byte-identical shared capability: multi-light deferred lighting (up to 4; `SceneUniforms` 128→240 B), selectable IBL environment (`ibl_env`, default/gallery), and per-preset background (miss path renders the environment). Each capability is inert (byte-identical goldens) unless a preset opts in via `scene_lights`/`environment`. Fixes the "chrome reads as putty" limit that parked Kinetic Sculpture. **Intended first consumer Kinetic Sculpture was retired before opting in (KSRETIRE.1 / D-188); the capability is retained for a future consumer.** See D-187 section. |
| D-188 | Accepted | Kinetic Sculpture preset retired (KSRETIRE.1, 2026-07-20). After multiple redesigns (chrome-in-a-gallery read as a "tinker toy"; a psychedelic-iridescent pivot drifted into a different concept) the preset never found the right direction; Matt stopped it. A fresh psychedelic-geometry preset will be authored separately. **Phase RMENV (D-187) engine work is retained** for a future consumer. All KS preset code/tests/docs/visual-refs deleted; production count 26 → 25 (certified 14 — unchanged by this retirement; Aurora Veil certified at AV.7 / D-185). See D-188 section. |
| D-189 | Accepted | Truchet Loom added (PG.4.1) — a `direct`-pass multiscale curved-Truchet op-art weave (family `geometric`), the first Phase PG psychedelic-geometry preset. **Density-mapping hero**: a smoothed `spectral_flux` sets a continuous global subdivision level, so busy passages shatter the weave into nested sub-tiles and sparse passages merge them into large sweeping arcs. Ported (not derived, FA #73) from IQ's two-quarter-arc Truchet SDF + Carlson's ½-scale recursion (Shadertoy 4t3BW4). Smoothing lands via a new single-float `flux_smoothed` EMA slot (idx 3390) in `SpectralHistoryBuffer` (reused reserved region; read directly, no new binding). Drift ← `arousal` speed on an `f.time` baseline (alive at silence, D-037). `certified:false` — reviewable v1. Preset count 25 → 26. (Landed on `main` after rmenv's PR #21; originally authored as D-186 on a stale base, renumbered to D-189 at integration.) See D-189 section. |
| D-190 | Accepted | Truchet Loom rhythm + colour (PG.4.2) — three routes on distinct primitives/layers (FA #67). **Per-beat tile flips**: a bounded ~22 % hash-selected subset re-route their arc each beat, seeded by a new monotonic `beat_index` counter (SpectralHistory slot 3391, incremented on each `beat_phase01` wrap) so the re-routing EVOLVES; crossfaded over `beat_phase01`; gated by `pulse_amp01` (silent at cold-start). Orientation-swap keeps ink steady → measured beat luminance swing 0.0055 (D-157, not a strobe). **Per-path hue teams** ← `spectral_centroid` (coarse-region quantised hues → coloured ribbons). **Bounded path glow** ← `bass_dev` (drop-able). `beat_index` follows the D-189 reserved-slot pattern (no new binding). Golden regenerated. Automated gate now 3/4 (in-source `bass_dev` makes L2 pass). Preset count unchanged (26). See D-190 section. |
| D-191 | Accepted | Truchet Loom breakup polish (PG.4.3, scoped) — the §A2 "breakup" layer: (1) hue-team block edges **domain-warped** by a cheap single-octave value noise (`tl_vnoise`) so boundaries WANDER organically instead of a hard square grid; (2) subtle static paper grain. **Perf lesson:** the first cut used `fbm4` (perlin3d ×2/pixel) → p99 8.87 ms (over budget) — replaced with a 4-tap value noise (~8× cheaper), p95 ≈ 2.2 ms. **HELD for post-M7** (surfaced to Matt): deeper nesting toward cap 4 (Matt chose Restrained/cap 3 at PG.4.1) + curl-warp organic flow. Golden regenerated. `certified:false`. See D-191 section. |
| D-192 | Accepted | Audio-visual coupling metric — cross-correlation of per-frame visual delta vs. energy envelope (lags 0–500 ms, peak Pearson r + lag + sliding-window stationarity), `CouplingReportTests`, **report-first, no gate**. QG.3 baseline showed the offline single-fragment/zeroed-state render made 11/13 presets static; measurement substrate unblocked by [D-193]. Report always attached to preset closeouts, never asserted against; low coupling means "not measured as present," never "preset is bad" (M7 seat stays the coupling authority). §Rationale below. |
| D-193 | Accepted | Coupling measurement substrate — extract the photosensitivity flash gate's headless multi-pass render into a shared `MultiPassRenderHarness` (one faithful render, two consumers: flash gate + coupling report, FA #66) and drive it with the REAL reconstructed-fixture train (FA #27). Makes coupling measurable for ALL 13 certified presets (was 2). Finding: 11/13 clear their own noise floor; the floor is PER-PRESET (feedback presets autocorrelate → higher floor), not global; Nacre + Ferrofluid Ocean read weak for proxy/render-fidelity reasons, NOT defects. **QG.3.2 gate = warning tier, not a hard cert blocker** (a hard gate would false-red the two M7-approved weak-reading presets); validate the proxy against M7 felt-coupling before any blocking gate. Matt's call (QG.3.1, "make measurable first"). §Rationale below. |
| D-196 | Accepted | Cymatic Resonance CR.1 maquette landed (count 25 → 26; `certified:false`). First `direct`+`post_process` preset — a resonant-plate Chladni nodal figure selected live by spectral centroid (mode-complexity ladder), `bassDev` snap-to-simple, derived-normal relief + GGX + jewel emissive on deep black, strong oblique tilt, through ACES + bloom. **Engine:** slot-6 per-preset state now reaches the `direct`+`post_process` scene pass (`PostProcessChain.runScenePass` threads `presetFragmentBuffer` at fragment index 6 — zero-risk, that path had no production consumer before CR). **★ Concept-gate correction #5 (found at the maquette):** the plus basis forces an anti-diagonal nodal line for OPPOSITE-parity (m,n), so the design's adjacent-pair ladder carried the forbidden diagonal (incl. the fundamental); fixed by the SAME-parity `(m,m+2)` family `(1,3)…(11,13)`. Perf 1080p full-chain p95 ≈ 1–2.6 ms. Pending Matt's live M7. §Rationale below. |
| D-195 | Accepted | Motion review gate (`Scripts/motion_gate.sh`) — the temporal counterpart to the D-181 still sheet. The still harness only rendered 3 disconnected frames, so jitter/pop/strobe/freeze were invisible until live M7 (the exact Truchet miss, D-194). The gate turns a preset's MOTION into a frame-to-frame magnitude signal (spike count = jitter, ~0 = freeze) + sampled frames the reader views as a sequence + a pointer to `target_animated.gif`. Reader-is-the-eyes (D-064): spike count is evidence, not an auto-pass. Deps ffmpeg+python3 only. Mandated in `PRESET_SESSION_CHECKLIST.md` Part 1 step 7 (pre-M7); closeout evidence for preset increments. Sequence feed reuses `renderFrame` in `PresetVisualReviewTests`. §Rationale below. |
| D-194 | Accepted | Truchet Loom RETIRED (TLRETIRE.1) — first live M7 (2026-07-21) rejected it fundamentally: the square Truchet lattice + discrete per-beat flips read as a visible grid that jitters ("looks like a bug"), it matched none of the curated flowing-scallop references (hero `01_macro_labyrinth_floor.jpg`), and it never delivered "psychedelic geometry" ("I don't understand what this is or why this is psychedelic geometry"). The design doc's mechanic (blocky Truchet tiling, ported from IQ/Carlson) and its curated references (flowing fine-line scallop op-art) were two different aesthetics — the concept was scrapped, not tuned. Built PG.4.1–4.3 (D-189/190/191) all deleted: preset `.metal`/`.json`, `TruchetLoom{Density,RhythmColour}Tests`, `truchet_loom/` refs, `PG_4_TRUCHET_LOOM.md` design doc, and the `SpectralHistoryBuffer` `flux_smoothed`/`beat_index` reserved slots (built for it, no other consumer). Count 26 → 25. ★ Lesson: reference images are the source of truth for the LOOK; validate that a "port algorithm X" instruction actually produces the reference look BEFORE building; stills lied about the living result. Second PG-phase preset to die at M7 on a fidelity/concept miss (after Kinetic Sculpture / D-188). |

---

## D-002: Core Audio taps as default capture path

**Status:** Accepted

Default capture uses `AudioHardwareCreateProcessTap` (macOS 14.2+). ScreenCaptureKit was explored and abandoned.

**Reason:** ScreenCaptureKit (`SCStream` with `capturesAudio = true`) delivers video frames but zero audio callbacks on macOS 15+. Root cause unknown. Core Audio taps work reliably and are purpose-built for audio tapping.

**Note:** The capture architecture remains provider-oriented (`AudioInputRouter` abstracts `.systemAudio`, `.application`, `.localFile`). The provider model is preserved for future fallback paths and testability.

---

## D-009: No CoreML dependency (MPSGraph + Accelerate)

**Status:** Accepted (replaced D-008a: CoreML for ML inference)

All ML inference uses MPSGraph (GPU, Float32) for stem separation and Accelerate/vDSP for mood classification. The CoreML framework was removed entirely in Phase 3.7.

**Reason:** CoreML's ANE path outputs Float16 requiring ~420ms conversion overhead. MPSGraph runs Float32 throughout, eliminates the conversion bottleneck, and achieves 142ms warm predict (4.4× faster than CoreML's ~620ms). CoreML also could not convert HTDemucs or Open-Unmix's full pipeline due to complex tensor ops.

---

## D-014: Orchestrator as explicit scoring/policy system

**Status:** Proposed

The Orchestrator will be a scored decision model with explicit inputs (energy trajectory, section confidence, stem salience, visual fatigue, preset novelty, transition compatibility, performance cost) and testable golden-session fixtures.

**Reason:** The Orchestrator is the product's key differentiator. It cannot remain a black box or a stub. Explicit policy with curated test fixtures is the only way to catch regressions in show quality.

---

## D-019: Stem routing warmup fallback pattern for compute presets

**Status:** Accepted

Compute kernels that route `StemFeatures` to visual parameters must handle the ~10s warmup window before live stems are available. The accepted pattern: detect zero stems via `smoothstep(0.02, 0.06, totalStemEnergy)` and mix between FeatureVector 6-band fallback values and true stem values. When total stem energy is below the lower threshold, pure FeatureVector routing applies (identical behavior to the pre-stem implementation). When above the upper threshold, full stem routing applies.

**Reason:** In ad-hoc mode and at the start of each track in session mode, `StemFeatures` is `.zero` for up to 10–15 seconds. A kernel that reads zero stems without fallback produces flat, unresponsive visuals during this window. The smoothstep crossfade makes the transition invisible — the kernel degrades gracefully to full-mix frequency analysis rather than going dark.

**Implication for new particle/compute presets:** Any preset that uses `buffer(3)` for stem routing should implement this pattern or an equivalent. The crossfade range (0.02–0.06) is intentionally narrow so the transition completes within the first few update cycles once stems arrive.

---

## D-018: SessionManager degrades to ready on any preparation failure

**Status:** Accepted

If `PlaylistConnector.connect()` throws, `SessionManager` transitions to `ready` with an empty plan. If `SessionPreparer.prepare()` completes with some failed tracks, `SessionManager` transitions to `ready` with a partial plan. The manager never becomes stuck in `connecting` or `preparing`.

**Reason:** Metadata degradation principle: Phosphene must be functional at every tier. An empty or partial session plan means the engine runs in reactive mode for uncached tracks — a worse experience than a full session, but a valid one. Surfacing a hard failure from the session lifecycle would force the UI to handle an error state that has no natural recovery path short of starting over.

**Implication for tests:** Tests that verify degradation behavior must cover both failure modes (connector failure → empty plan, resolver failure → partial plan) independently.

---

## D-020: Architecture-stays-solid for ray-march scene presets (Glass Brutalist Option A)

**Status:** Accepted — but its subject preset (Glass Brutalist) was **retired GBRETIRE.1 / D-186** (2026-07-19). The rule itself still governs any *future* architectural ray-march preset; the D-020 permanence constraint is precisely what made Glass Brutalist non-viable (an audio-static scene can never make an instrument the hero subject). See D-186.

For ray-march scenes that depict identifiable architecture (corridors, rooms, structures with implied permanence), audio reactivity must NOT deform the architecture itself. Walls, pillars, beams, floors, and ceilings stay static. Music drives only the *light* in the scene (intensity, colour), the *atmosphere* (fog density), the *camera* (constant-speed dolly), and at most a single secondary deformation that reads as spatial rather than structural (Glass Brutalist's glass-fin position, which widens/narrows the open path between fins).

**Reason:** Three iterations of bass-driven beam dipping, pillar squeezing, and fin Y-stretching all produced the same complaint: the scene reads as broken or rubber. Architecture has implied permanence; visibly warping a concrete cross-beam on every kick drum collapses the spatial illusion. Real-world music reactivity in spaces (clubs, cathedrals, light shows) modulates lighting and mist, never the building. Phosphene's deferred PBR pipeline already gives us the mechanism — modulate `lightColor`, `lightIntensity`, `fogFar`, and IBL ambient, leave geometry alone.

**Implication for ray-march preset authors:** `sceneSDF` should be audio-independent or limited to a single, intentionally subtle non-architectural element. Modulation of lighting/atmosphere happens in the shared Swift render path (`drawWithRayMarch`) reading from `RayMarchPipeline.BaseSceneSnapshot` so per-frame modulation is additive on the JSON baseline. If a preset needs SDF-side modulation that material classification must agree with (e.g. Glass Brutalist's fin X-position), pass it via a free `SceneUniforms` lane that both `sceneSDF` and `sceneMaterial` read from — never re-evaluate sub-SDFs at a different shape in `sceneMaterial` than in `sceneSDF`, or material boundaries will flip at deformed edges.

---

## D-022: IBL ambient is tinted by `lightColor` so mood shifts are visible

**Status:** Accepted

`raymarch_lighting_fragment` multiplies its computed IBL ambient term by `scene.lightColor.rgb` before adding it to direct light. The same tint is applied to fog colour.

**Reason:** Indoor ray-march scenes are dominated by IBL ambient — the direct scene light only catches surfaces facing it (often a small fraction of the visible frame). Modulating only the direct light's `lightColor` (e.g. by `valence`) leaves most of the rendered pixels colour-unchanged. Multiplying the ambient by `lightColor.rgb` makes the mood-driven palette shift visible across every concrete surface, not just light-facing ones. At rest `lightColor ≈ (1, 0.95, 0.88)` so the multiply is near-identity; under modulation it propagates through the whole scene.

---

## D-026: Preset shaders drive from audio deviation, not absolute energy

**Status:** Accepted (Phase MV-1)

Preset shader code must drive visual parameters from deviation-from-AGC-center (`f.bassRel`, `f.bassDev`, `stems.vocalsEnergyDev`, etc.) rather than from absolute energy values (`f.bass`, `f.bassAtt`, `stems.vocalsEnergy`). Absolute thresholds like `smoothstep(0.22, 0.32, f.bass)` are explicitly disallowed in new preset code.

**Reason:** `BandEnergyProcessor` implements Milkdrop-style AGC: output = raw / runningAverage × 0.5. This inherently means raw output magnitudes depend on recent loudness history, not acoustic loudness. A kick that peaks at `bass = 0.35` during a sparse section will peak at `bass = 0.22` during a busy section because the running-average divisor rose — the kick is equally loud acoustically but AGC scaled it down. Preset v3.3 of Volumetric Lithograph hit this exact failure mode: `smoothstep(0.22, 0.32, f.bass)` missed every other kick on Love Rehab (session 2026-04-16T18-56-59Z), producing a phantom 65 BPM rhythm on a 125 BPM track. Deviation (`bass - 0.5`, or `bassRel` in the new convention) is stable across mix density because both numerator and denominator track together.

Milkdrop documents this convention in its preset authoring guide: "1 is normal, below 0.7 quiet, above 1.3 loud" — authors universally write `zoom = zoom + 0.1 * (bass - 1.0)`, never `if (bass > 0.22)`. We adopt the same convention scaled to our 0.5-centered AGC.

**Implication:** existing presets written with absolute thresholds are grandfathered but should be migrated. New preset code review must reject absolute-threshold patterns. CLAUDE.md's "Proven Audio Analysis Tuning" section documents the primitive vocabulary authors should use.

---

## D-027: Milkdrop-style per-vertex feedback warp as an opt-in render pass

**Status:** Accepted (Phase MV-2)

A new `mv_warp` render pass implements Milkdrop's per-vertex warp mesh — 32×24 grid, per-vertex UV displacement computed from preset-authored `mvWarpPerFrame()` + `mvWarpPerVertex()` functions, sampled against a persistent feedback texture. Any preset can opt in by adding `"mv_warp"` to its `passes` array.

**Reason:** Research documented in [MILKDROP_ARCHITECTURE.md](MILKDROP_ARCHITECTURE.md) established that Milkdrop's "musical feel" comes from feedback-based motion accumulation, not from rich audio analysis (Milkdrop's audio vocabulary is a strict subset of ours). 9 of 11 Phosphene presets prior to MV-2 do not use any feedback loop; ray-march presets render from scratch each frame and show only instantaneous audio state. Six iterations of Volumetric Lithograph (v3 → v4.2) attempted to make a ray-march preset feel musical via increasingly elaborate audio drivers and failed every time. The gap is mechanical: without feedback, simple audio cannot compound into organic motion.

The existing `feedback` pass is kept for Starburst/Membrane but is semantically narrower (single global zoom+rot per frame, not per-vertex spatial modulation). `mv_warp` is a new pass with a different contract, not a replacement.

**Authoring approach:** MV-2a (per-preset Metal warp functions, same pattern as `sceneSDF`/`sceneMaterial`). Faster to ship than an equation-language parser (MV-2b). An equation-language importer for real Milkdrop `.milk` presets is tracked as a potential future increment only if Metal-function authoring becomes the demonstrated blocker.

**Implication:** ray-march preset authoring pattern shifts. A scene's 3D geometry becomes static (not deformed with audio); all audio-driven motion goes through the mv_warp pass. Audio reacts to the *image* of the scene rather than its geometry. This matches Milkdrop's architecture exactly and preserves our 3D-rendering advantage.

**Scope correction (2026-04-17, see D-029):** The "ray-march preset authoring pattern shifts" framing above was over-broad. mv_warp is one of several *alternative* motion-source paradigms, not a universal requirement for ray-march presets. It does not compose with a moving world-space camera (see D-029 for the incompatibility diagnosis and the VL revert).

**Implementation notes (landed 2026-04-17, commit `c8cd558f`):**
- `MVWarpState` uses `@unchecked Sendable` because `MTLTexture` protocol has no `Sendable` conformance in Swift 6.0. The struct is only mutated under `mvWarpLock`.
- `SceneUniforms` is defined in `mvWarpPreamble` behind `#ifndef SCENE_UNIFORMS_DEFINED` so direct (non-ray-march) presets compile; the ray-march preamble wraps its own definition in the same guard to prevent redefinition for ray-march + mv_warp combos.
- `mvWarpPerFrame()` + `mvWarpPerVertex()` must be implemented in every preset that includes `mv_warp` in its passes — the engine does not provide a default (see `Shaders/MVWarp.metal` for the engine-library default implementations that `PresetLoader` falls back to via the default engine library).
- Ray-march + mv_warp handoff: `drawWithRayMarch` detects `.mvWarp` in `activePasses` and renders to `warpState.sceneTexture` instead of the drawable; `drawWithMVWarp` is called next and handles drawable presentation. `sceneAlreadyRendered: true` is passed in this case.

---

## D-029: Preset motion sources are alternative paradigms, not composable layers

> **⚠ RE-EVALUATE (audit 2026-05-13).** Recent staged-composition work (Arachne V.7.7B — WORLD + COMPOSITE stages) and the open multi-preset-per-song planner direction may strain the "paradigms are alternatives, not composable layers" framing. Staged composition explicitly composes ray-march WORLD + COMPOSITE fragment overlay; multi-preset-per-song planning is the bigger unfinished product axis (per memory note `feedback_multi_preset_per_song.md`). Schedule a re-evaluation session when the multi-preset planner spec lands.

**Status:** Accepted (2026-04-17)

Each preset picks exactly one motion-source paradigm from the following catalogue. The engine supports all of them via the `passes` array, but mixing them within a single preset is either incoherent or actively broken.

| Paradigm | Motion comes from | Example presets | Passes |
|----------|-------------------|-----------------|--------|
| **Milkdrop mv_warp** | Per-vertex UV feedback accumulator — "the warp mesh is the camera" | *(future direct-fragment presets; optionally static-camera ray march)* | `mv_warp` (± `direct` / `ray_march` without camera motion) |
| **Particle system** | Compute-kernel sprite integration in world space | Starburst (Murmuration) | `feedback` + `particles` |
| **Feedback composite** | Single global zoom/rotation per frame + persistent texture | Membrane | `feedback` |
| **Ray-march camera flight** | Translating/rotating a 3D camera through an SDF scene; motion compounds via spatial traversal | VolumetricLithograph, KineticSculpture, GlassBrutalist (static variant) | `ray_march` + `post_process` (+ `ssgi`) |
| **Mesh shader animation** | GPU-authored procedural geometry evolution | FractalTree | `mesh_shader` |
| **Direct-fragment modulation** | Time + audio into a single fragment shader; no persistence | Waveform, Plasma, Nebula | `direct` |

**Reason:** The MV-2 rollout (D-027) attempted to add mv_warp on top of VolumetricLithograph's forward camera dolly. The result was severe vertical smearing at rest: mv_warp's feedback accumulator pins previous-frame pixels to UV coordinates, but the moving world-space camera re-projects those same world points to different UV coordinates each frame, so `0.96 × previous + 0.04 × current` bleeds camera-motion history across the screen. See CLAUDE.md Failed Approaches #32.

The same bug applies — more subtly — to any ray-march preset that translates or rotates its camera. It applies partially to particle systems (particles already integrate state, so stacking mv_warp over them double-integrates and smears trails into mush).

**Rule:** Paradigms may not be stacked. The only legitimate compositions are:
- `mv_warp` + static-camera `ray_march` — a 3D SDF backdrop receives Milkdrop-style 2D warp on top. Narrow use case; none implemented as of 2026-04-17.
- `ray_march` + `post_process` + `ssgi` — standard ray-march compositing (not a motion-source mix).
- `feedback` + `particles` — Starburst's original and current pattern; feedback here is a trail decay for the particle render, not an independent motion source.

**Implication for PresetLoader:** the current mutual-exclusion routing in `compileShader()` (meshShader → mvWarp → rayMarch → standard) enforces the rule by construction and should be kept. A future static-camera `ray_march + mv_warp` preset remains supported by the existing `compileMVWarpShader` branch (it already handles the ray-march variant).

**Implication for preset authors:** do not reach for `mv_warp` as a universal "add musicality" switch. Ask first what the preset's motion source is. If it's a moving camera or a particle system, mv_warp will fight it. If it's a static 2D or static-camera 3D scene with no inherent compounding, mv_warp is one valid choice (feedback and mesh-shader animation are others).

**Reverts and documentation changes:**
- Starburst.json: `["mv_warp"]` → `["feedback", "particles"]`. Stale `mvWarpPerFrame`/`mvWarpPerVertex` removed.
- VolumetricLithograph.json: `["ray_march", "post_process", "mv_warp"]` → `["ray_march", "post_process"]`. `mvWarpPerFrame`/`mvWarpPerVertex` and the unused `vl_pitchHueShift` helper removed.
- CLAUDE.md Failed Approaches #32 rewritten to describe the camera/feedback incompatibility rather than the old "ray march needs feedback" claim.
- CLAUDE.md "Do not" rule reframed from "always implement mv_warp" to "do not stack mv_warp on a moving camera."
- D-027 scope-corrected with a forward pointer to this entry.


---

## D-030: SpectralHistoryBuffer as unconditional GPU contract at buffer(5)

**Status:** Accepted (2026-04-19)

A pre-allocated `.storageModeShared` MTLBuffer (16 KB, 4096 Float32) carrying per-frame MIR history is bound unconditionally at fragment buffer index 5 in all direct-pass encoders (`drawDirect`, `drawParticleMode`, `drawSurfaceMode`). The class is `SpectralHistoryBuffer` in the Shared module; it conforms to `SpectralHistoryPublishing` for test injection.

**Layout:**
```
[0..479]    valence trail         (-1..1, raw)
[480..959]  arousal trail         (-1..1, raw)
[960..1439] beat_phase01 history  (0..1, sawtooth)
[1440..1919] bass_dev history     (0..1)
[1920..2399] vocals_pitch_norm    (0..1, log2(hz/80)/log2(10), 0=unvoiced/low confidence)
[2400]      write_head            (integer as Float, 0..479)
[2401]      samples_valid         (integer as Float, capped at 480)
[2402..4095] reserved             (zeroed; future consumers)
```

**Why:** Phosphene's MV-3 extensions (D-028) added ~26 new per-frame primitives with no real-time observability. `SessionRecorder` (D-025) captures them offline to CSV but there's no live view during preset authoring. An always-bound history ring at buffer(5) lets `instrument`-family presets render recent MIR state trivially and creates the foundation for any future preset that wants short-term history without new plumbing. 16 KB on UMA is negligible.

**Why buffer(5) and not buffer(4):** buffer(4) is already occupied by `SceneUniforms` in ray march G-buffer, lighting, and SSGI passes. Buffer(5) is the first truly unused slot across all pass types. CLAUDE.md GPU Contract documentation was wrong (listed buffer(0)=FFT, buffer(4–7)=future) — corrected in this increment.

**First consumer:** `SpectralCartograph` preset — four-panel diagnostic instrument showing FFT spectrum, deviation meters, V/A plot, and scrolling feature graphs.

**Implication:** future additions to the history layout (e.g., per-stem onset rate history) can consume slots [2402..4095] without breaking existing consumers. Ray march presets currently skip buffer(5); it is available to them if needed.


---

## D-032: Preset scoring weights and penalty structure (Increment 4.1)

**Status:** Accepted (2026-04-20). **Amended 2026-05-06 by D-080 rule 5** — `cutEnergyThreshold` raised from 0.7 → 0.85 (reserves hard cuts for true climax moments only); see D-080 for the QR.2 rationale. The four sub-score weights, the multiplicative-penalty structure, and the fatigue cooldowns (60 / 120 / 300 s) remain unchanged.

`DefaultPresetScorer` combines four sub-scores into a final [0, 1] total using fixed weights and two multiplicative penalties.

**Sub-score weights:** `mood = 0.30`, `tempoMotion = 0.20`, `stemAffinity = 0.25`, `sectionSuitability = 0.25`. Sum = 1.0, so `raw` is already in [0, 1] without normalisation — any sub-score is directly readable as a fraction of the total budget.

**Why mood gets the highest weight (0.30):** Mood is the single axis with the most perceptual surface area. A wrong emotional tone undermines the entire visual experience even when tempo and stem affinity are well-matched. Valence → colour temperature and arousal → visual density are the two most directly observable mismatches; together they justify the extra 5 points over the other dimensions.

**Why tempoMotion gets the lowest weight (0.20):** BPM metadata is often missing (nil in `TrackProfile`) and the scorer maps nil to neutral 0.5 to avoid penalising presets on missing data. A nil-safe neutral degrades information, so this dimension earns less influence. When BPM is available it is valuable; when absent, the other three dimensions carry the decision.

**Why stemAffinity and sectionSuitability share 0.25 each:** Both are equally important for the product's stated purpose (intentional visual sequencing). Stem affinity makes the preset feel musically responsive; section suitability makes timing feel deliberate. Equal weighting avoids one outweighing the other given the uncertainty in both.

**Multiplicative penalties:** `familyRepeatMultiplier` (0.2× for consecutive same-family) and `fatigueMultiplier` (smoothstep over 60/120/300s cooldown) are multiplicative, not additive, so they compose cleanly. A 0.2× family-repeat penalty on a 0.9 raw score gives 0.18, not 0.7 (which additive would). This ensures highly-penalised presets lose to even mediocre competitors — the intended behaviour.

**Exclusions are separate from penalties:** `excluded = true` always produces `total = 0` and populates `exclusionReason`. This keeps "why is this at zero" answerable from the breakdown: "excluded for cost" vs "penalised to near-zero by fatigue and repeat" are different problems with different remedies.

**Fatigue cooldown windows:** `.low = 60s`, `.medium = 120s`, `.high = 300s`. These are the smallest values that created observable variety in internal playlist test sessions without causing visually jarring avoidance patterns (every session felt different, no preset disappeared for so long that its return felt jarring). `smoothstep` rather than a linear ramp avoids an abrupt "fully available" cliff.

**How to apply:** The `internal static let` constants (`weightMood`, `weightTempoMotion`, `weightStemAffinity`, `weightSectionSuitability`, `familyRepeatPenalty`, `fatigueCooldown`) are the only place these values are defined — adjust there to tune globally. The `PresetScoreBreakdown` struct surfaces all sub-scores for introspection and future calibration tooling.

**Scarcity-via-cooldown pattern (Stalker, Increment 3.5.7):** `fatigue_risk: "high"` is the correct lever to make a preset feel rare and surprising without adding per-preset logic. Stalker's 300 s cooldown means it appears at most once per 5 minutes in a continuous session, which is intentional — a predator that appears too often stops feeling predatory. The listening-pose capability justifies scarcity: it needs time between appearances to retain its perceptual impact.

---

## D-033: Transition policy design — structural boundary priority and energy-scaled crossfades (Increment 4.2)

**Status:** Accepted (2026-04-20)

`DefaultTransitionPolicy` answers the "when + how" question. Two trigger paths, strict priority order.

**Structural boundary (preferred):** Fires when `StructuralPrediction.confidence ≥ 0.5` and the predicted next boundary is within 2.5 s (the `LookaheadBuffer` window). `scheduledAt` is offset before the boundary so a crossfade or morph completes exactly at it; a cut is scheduled at the boundary itself. Confidence threshold 0.5 was chosen as the midpoint of the [0, 1] range — the analyzer produces values above this for tracks with detectable periodic structure (ABAB or verse/chorus patterns), and values below for ambient or through-composed material.

**Duration-expired fallback:** Fires when `elapsedPresetTime ≥ preset.duration`. `scheduledAt = captureTime` (transition now). Confidence reports 1.0 because the trigger is deterministic, not a probabilistic prediction.

**Why structural boundary beats the timer:** Section boundaries are the musically correct moment to switch visuals. The timer fires regardless of where we are in the track structure. When both conditions are true simultaneously (preset is overdue AND a boundary is imminent), the structural path produces a less jarring result — it aligns with what the listener hears.

**Style selection:** The current preset's `transitionAffordances` constrain the palette. Within that palette, energy drives preference: above `cutEnergyThreshold = 0.7` the policy prefers `.cut` (fast, punchy — appropriate at peaks), below it prefers `.crossfade` (slow blend — appropriate for relaxed passages). Default fallback when no affordances are declared: `.crossfade`.

**Crossfade duration scaling:** Linear interpolation between `baseCrossfadeDuration = 2.0s` (energy=0) and `minCrossfadeDuration = 0.5s` (energy=1). This gives the visually desired behaviour — slow, deliberate fades during quiet passages; quick, energetic ones during peaks.

**Family-repeat avoidance is NOT in TransitionPolicy:** The `DefaultPresetScorer` already applies a 0.2× family-repeat penalty during ranking (D-032). TransitionPolicy receives a ranked list and picks from the top — no duplicate logic needed.

**`TransitionDecision` is a pure value type:** trigger, scheduledAt, style, duration, confidence, rationale. No callbacks, no side effects. Callers schedule the transition externally from the returned struct.

**How to apply:** Tune the four `static let` constants in `DefaultTransitionPolicy` (`structuralConfidenceThreshold`, `lookaheadWindow`, `baseCrossfadeDuration`, `minCrossfadeDuration`, `cutEnergyThreshold`) to adjust timing behaviour globally. The `TransitionDeciding` protocol allows injection of test doubles or alternative implementations without changing callers.


---

## D-044 — SwiftUI accessibility identifiers: static constants + binding, not tree traversal (Increment U.1)

**Status:** Accepted (2026-04-22)

**Context:** Increment U.1 required tests that verify each session-state view carries the correct `accessibilityIdentifier` — needed for UI automation (XCUITest, Accessibility Inspector). The first implementation used `NSHostingController` + `NSWindow` rendering + `accessibilityChildren()` traversal via ObjC dynamic dispatch (`NSSelectorFromString`). All 6 rendering-based tests failed.

**Root cause:** On macOS, SwiftUI only materialises the accessibility tree when an active accessibility client queries it (VoiceOver, Accessibility Inspector, XCUITest harness). In `xcodebuild test` unit tests there is no client — `NSHostingView.accessibilityChildren()` returns an empty array regardless of RunLoop cycles, window visibility, or ObjC dispatch approach. This is a platform behaviour, not a SwiftLint or concurrency issue.

**Decision:** Each view exposes `static let accessibilityID: String`. The view body applies `.accessibilityIdentifier(Self.accessibilityID)`. Unit tests check the static constant directly; the binding is enforced by construction (if the modifier is removed, UI automation breaks — caught by human review or XCUITest, not unit tests).

**Rule:** Do not attempt accessibility tree traversal from `xcodebuild test` unit tests. Use static constants for identifier contracts. Accessibility tree verification belongs in XCUITest (future Milestone A acceptance suite), not unit tests.


## D-045 — V.1 utility library naming: unprefixed snake_case, no legacy collision renaming (Increment V.1)

**Status:** Accepted (2026-04-22)

**Context:** Increment V.1 adds two utility trees — 9 Noise files and 9 PBR files — into `Sources/Presets/Shaders/Utilities/`. The legacy `ShaderUtilities.metal` already contains functions such as `perlin2D`, `cookTorranceBRDF`, `fresnelSchlick` (camelCase convention). The new utilities use `perlin2d`, `brdf_ggx`, `fresnel_schlick` (snake_case convention). The question was whether to rename existing functions to `legacy_*`, prefix new ones, or leave both coexisting.

**Pre-flight finding:** MSL is case-sensitive. `perlin2d` vs `perlin2D` are distinct symbols. A complete audit of all 9 Noise and 9 PBR new function names found zero name-space collisions with any existing `ShaderUtilities.metal` function. No renaming was required.

**Decision:** New V.1 utilities use clean snake_case names with no prefix. Legacy ShaderUtilities functions are unchanged. Both coexist in the preamble without collision. Future V.3+ authoring vocabulary will use the V.1 snake_case names as the primary interface; legacy camelCase names remain available for backward compatibility with existing preset code.

**Rule:** When adding new preamble functions, use snake_case to distinguish from the legacy camelCase ShaderUtilities layer. Only apply `legacy_*` prefix if a true case-insensitive collision exists (none found in V.1). Do not rename existing working functions — preset shaders referencing them would break.

---

## D-051 — UserFacingError in engine Shared module; condition-ID toast semantics (Increment U.7)

**Status:** Accepted (2026-04-24)

**Context:** U.7 introduces a typed error taxonomy (`UserFacingError`, 29 cases) and a condition-ID mechanism for idempotent, auto-dismissing toasts. Two placement questions arose.

**Decision 1 — UserFacingError in engine `Shared` module (not `PhospheneApp`).**
`UserFacingError` maps internal states (silence, network loss, rate limiting, DRM, etc.) to presentation metadata (`severity`, `presentationMode`, `conditionID`). These states originate in engine modules (`Audio`, `Session`, `Orchestrator`). Placing the enum in `Shared` lets engine code reference it without creating an upward dependency on the app layer. `Localizable.strings` and `LocalizedCopy` remain in `PhospheneApp` — the engine defines the error identity; the app defines the human copy.

**Decision 2 — `presentationMode` as a property, not a type hierarchy.**
`UserFacingError` exposes `presentationMode: PresentationMode` (`.inline` / `.toast` / `.banner` / `.fullScreen`) instead of sub-classing or using associated-value enums per mode. The view layer switches on `presentationMode` to route to `ToastView`, `TopBannerView`, or `PreparationFailureView`. This keeps routing logic in Swift, not in a protocol hierarchy, and makes adding a new presentation mode a one-line enum change rather than a protocol conformance.

**Decision 3 — Condition-ID semantics on `PhospheneToast`.**
Persistent degradation toasts (silence, low input level) must not stack on repeated triggers and must auto-dismiss on recovery. The chosen mechanism: `PhospheneToast.conditionID: String?` + `ToastManager.dismissByCondition(_:)` + `PlaybackErrorConditionTracker`. The tracker is separate from `ToastManager` so `PlaybackErrorBridge` can check "is this condition already displayed?" without coupling to `ToastManager`'s internal queue representation. The condition ID for silence is `"silence.extended"` (derived from `UserFacingError.silenceExtended.conditionID`).

**Decision 4 — 15s silence threshold (was 30s in `SilenceToastBridge`).**
`UX_SPEC §9.4` specifies >15s sustained silence triggers the degradation toast. The prior `SilenceToastBridge` fired at 30s, which was a pre-U.7 stub value. `PlaybackErrorBridge` corrects this to match the spec.

**Rejected alternative:** Store condition state in `ToastManager` itself (no separate tracker). Rejected because `ToastManager` would then need to be queried by `PlaybackErrorBridge` both to check state and to enqueue — creating a tighter coupling that makes unit testing harder (two concerns in one object).

## D-054 — AccessibilityState architecture and beat-clamp boundary (Increment U.9)

**Status:** Accepted (2026-04-24)

**Context:** U.9 requires three coordinated changes: (1) gate mv_warp and SSGI execution when reduce-motion is active, (2) clamp beat-pulse amplitude to 0.5× when reduce-motion is active, (3) integrate the user's `ReducedMotionPreference` setting with the system `NSWorkspace.accessibilityDisplayShouldReduceMotion` flag into a single source of truth.

**Decision — AccessibilityState:**
`AccessibilityState` (`@MainActor final class ObservableObject`) is the single source of truth. It combines `NSWorkspace.accessibilityDisplayShouldReduceMotion` (observed via `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`) with `ReducedMotionPreference` from `SettingsStore`. The three-way logic:
- `.matchSystem` → `reduceMotion = systemReduceMotion`
- `.alwaysOn` → `reduceMotion = true`
- `.alwaysOff` → `reduceMotion = false`

`SessionStateViewModel` takes `accessibilityState: AccessibilityState` at init; `PlaybackChromeViewModel` subscribes via injected `AnyPublisher<Bool, Never>`. This keeps both view models unit-testable via stub publishers without depending on real NSWorkspace state.

**Decision — beat-clamp boundary:**
The beat-clamp is applied in `RenderPipeline.draw(in:)` to the local `FeatureVector` copy, before it is passed to `renderFrame`. Affected fields: `beatBass`, `beatMid`, `beatTreble`, `beatComposite`. NOT clamped: `beatPhase01`, `beatsUntilNext` — these are BeatPredictor timing primitives that drive anticipatory animation timing, not pulse amplitude.

Placement at the `draw` boundary means all downstream paths (direct, mesh, ray-march, mv_warp, ICB) share the same clamped vector without each needing to know about reduce-motion state.

**Decision — mv_warp gate:**
`frameReduceMotion: Bool` on `RenderPipeline` (set by app layer from `AccessibilityState.reduceMotion`). Checked at top of `drawWithMVWarp()` — when true, `drawMVWarpReducedMotion()` renders a single frame without feedback accumulation (avoids both the motion and the GPU cost of the warp pass).

**Decision — SSGI gate:**
`reducedMotion: Bool` on `RayMarchPipeline`. SSGI pass fires only when `ssgiEnabled && !reducedMotion`. SSGI is the temporally-accumulating screen-space pass most likely to cause discomfort; skipping it costs no visual quality under reduce-motion because the feedback smear is the discomfort source.

**Deferred:** Strict photosensitivity mode (flash frequency analysis + blanking); SSGI temporal accumulation gate distinct from the frame-level `reducedMotion` flag.

## D-053 — PresetScoringContext extended with excludedFamilies + qualityCeiling; defaults preserve backward compat (Increment U.8)

**Status:** Accepted (2026-04-24)

**Context:** U.8 Settings adds two user-configurable gates that must influence preset selection: a family blocklist and a quality ceiling. These gates belong in `PresetScoringContext` (the immutable snapshot passed to `DefaultPresetScorer`) rather than in the scorer's internal logic, so the context remains the single source of truth for session state at scoring time.

**Decision:** Add `excludedFamilies: Set<PresetCategory> = []` and `qualityCeiling: QualityCeiling = .auto` to `PresetScoringContext`, both with defaults. All existing callers that omit the new params continue to compile and behave identically (empty blocklist, auto ceiling). `DefaultPresetScorer.exclusionReason` checks `excludedFamilies` first, then applies `qualityCeiling.complexityThresholdMs(for:)` as the budget cap (`.ultra` returns nil → no complexity gate; `.performance` returns 12 ms → stricter than the frame budget).

**`QualityCeiling` placement:** New enum in `Orchestrator` module (not `Presets`). It maps to scoring logic (complexity thresholds) rather than to visual/preset metadata. `PresetScoringContext` already imports `Orchestrator`-local types, so no new cross-module dependencies are introduced.

**`PresetScoringContextProvider` (Part C):** Reads `settingsStore.excludedPresetCategories` and `settingsStore.qualityCeiling` and propagates them through `build()`. This is the only call site that needs updating — all other `PresetScoringContext` constructions (engine tests, golden session tests) use the defaults.


## D-057 — Frame Budget Manager: governor design, OR-gate pattern, tier targets, and scope limits (Increment 6.2)

**Status:** Accepted (2026-04-25)

**Decision — Per-tier configuration targets:**
Tier 1 (M1/M2) uses `targetFrameMs = 14.0` ms with `overrunMarginMs = 0.3` ms. Tier 2 (M3+) uses `targetFrameMs = 16.0` ms with `overrunMarginMs = 0.5` ms. Tier 1 has a tighter target because M1/M2 have less headroom at 60fps — the 14ms target gives the Core Audio tap and Swift overhead ~2.6ms of slack. Tier 2's 16ms target matches the V-sync period exactly; the 0.5ms margin accounts for frame-presentation jitter.

**Decision — Asymmetric hysteresis:**
3 consecutive overruns to downshift; 180 consecutive sub-budget frames to upshift. The asymmetry is intentional: downshift must be fast (users notice dropped frames immediately) but upshift must be slow (a single lucky frame after 2s of budget pressure should not restore full quality and cause another drop). 180 frames = 3 seconds at 60fps. A "hysteresis band" frame (within the overrun threshold but not low enough to count as recovery) resets both counters — it is neither progress nor regression.

**Decision — OR-gate for SSGI suppression (reducedMotion):**
`RayMarchPipeline.reducedMotion` was previously a single mutable Bool set by both the a11y path (via `AccessibilityState`) and the governor path (via `applyQualityLevel`). The problem: governor recovery calling `reducedMotion = false` would silently override an active accessibility preference. The fix introduces two private flags — `a11yReducedMotion` and `governorSkipsSSGI` — with dedicated setters and a computed `reducedMotion = a11yReducedMotion || governorSkipsSSGI`. This guarantees that a user who needs reduced motion for medical reasons cannot have SSGI re-enabled by the governor recovering from a transient performance blip. The OR-gate is a formal architectural guarantee, not a runtime check.

**Decision — Governor exempt under QualityCeiling.ultra:**
When `SettingsStore.qualityCeiling == .ultra`, `FrameBudgetManager` is initialised with `enabled: false`. `observe()` becomes a no-op and always returns `.full`. This respects the user's explicit preference for maximum visual quality at the cost of potential frame drops. The exemption is set once at `VisualizerEngine.init()` by reading `UserDefaults` directly (the engine init predates `SettingsStore`); a `SettingsStore` observer to live-toggle this is deferred.

**Decision — Governor never modifies `activePasses`:**
The frame budget governor operates exclusively through five scalar properties: `governorSkipsSSGI` (Bool), `bloomEnabled` (Bool), `stepCountMultiplier` (Float), `activeParticleFraction` (Float), `densityMultiplier` (Float). It never adds, removes, or reorders entries in `RenderPipeline.activePasses`. This constraint keeps the governor from invalidating MTLRenderCommandEncoder setup paths — pass gating at the encoder level would require rebuilding the entire render graph. Instead each subsystem degrades gracefully in-place: SSGI is skipped inside `RayMarchPipeline`'s lighting pass via `ssgiEnabled && !reducedMotion`; bloom is bypassed within `PostProcessChain.runBloomAndComposite` without removing the post-process pass itself.

**Decision — densityMultiplier is a no-op on M1/M2 vertex fallback:**
`MeshGenerator.densityMultiplier` is passed to the object and mesh shader stages at buffer(1) on M3+ hardware. On M1/M2, `MeshGenerator` dispatches a standard vertex pipeline (fullscreen triangle or instanced geometry); the buffer(1) write still occurs but no shader reads it. The M1/M2 fallback draws a fixed geometry count. This is acceptable because M1/M2 are Tier 1 devices — they reach `.reducedMesh` only under severe sustained load, at which point the larger gains from SSGI-off + bloom-off + reduced ray march steps are already in effect. A dedicated M1/M2 vertex-count reduction path is out of scope for 6.2.

**Decision — One-frame governor lag by design:**
`commandBuffer.addCompletedHandler` fires asynchronously after GPU completion. The handler bounces to `@MainActor` and calls `applyQualityLevel`, which takes effect at the start of the next `draw(in:)` call. This means the governor reacts to frame N's timing during frame N+1 setup. A zero-lag architecture would require predicting budget violations before encoding, which is not feasible. The one-frame lag is invisible at 60fps and eliminates any risk of the governor mutating render state mid-encoding.

## D-058 — U.6b live-adaptation keyboard semantics: architecture and undo semantics

### Context

Increment U.6b wires the seven `PlaybackActionRouter` keyboard actions stubbed in U.6. Several architectural decisions were required:

**(a) Family boost is additive on the final 0–1 score, not multiplicative on sub-scores.**

`context.familyBoosts[family] ?? 0` is added to `raw * familyMult * fatigueMult` before clamping, keeping it fully independent of the four-weight structure established in D-032. A multiplicative approach would compound with the fatigue and repeat penalties in non-obvious ways; an additive approach on the final score is transparent ("always +0.3 for this family, regardless of other factors"). Boost is capped at 0.3 and idempotent (pressing `+` twice gives 0.3, not 0.6).

**(b) `undoLastAdaptation()` restores `livePlan` only, NOT the boost/exclusion state.** **⚠ RE-EVALUATE (audit 2026-05-13):** flagged as deliberate-but-surprising — a user who pressed `-` to dislike a family and then `⌘Z` to undo may expect both the swap AND the preference to revert. Current rationale (rationale paragraph below) is sound but worth a UX check the next time live adaptation is exercised on a real session.

`adaptationHistory` stores `PlannedSession` snapshots, which are the plan. Preference state (`familyBoosts`, `temporaryFamilyExclusions`, `sessionExcludedPresets`) is intentionally NOT reverted by undo. Rationale: a user who pressed `-` to dislike a family and then `⌘Z` to undo the preset swap did not express a desire to re-include that family — they may just want to go back to the previous visual. Clearing preference state on undo would be surprising. Users who want to fully reverse a `-` can wait 10 minutes for the exclusion to expire.

**(c) `LiveAdaptationToastBridge` default changed to `true` for fresh installs.**

The `isEnabled` check now reads `UserDefaults.standard.object(forKey:)` first. If the key is absent (new install), it returns `true`. If the key is present (user has explicitly set it either way), it reads the stored bool. This preserves existing users' explicit choice while shipping the feature on by default.

**(d) `adaptationHistory` capacity is 8.**

Typical in-session adaptation depth is 2–4 actions (a couple of `+`/`-` presses and maybe one reshuffle). 8 entries covers the 99th percentile of realistic use and keeps memory overhead trivially small. Entries are plain `PlannedSession` values (a handful of structs); 8 × ~2 KB ≈ 16 KB maximum.

**(e) Adaptation preference state lives on `DefaultPlaybackActionRouter`, not `VisualizerEngine`.**

The spec draft suggested placing U.6b state on `VisualizerEngine+Orchestrator`, but this would make app-layer unit tests impossible without a Metal context. Following the protocol-first / injectable-closures pattern already established in `PlanPreviewViewModel` and `PlaybackChromeViewModel`, all preference state (`familyBoosts`, `temporaryFamilyExclusions`, etc.) lives on the router. The engine reads it back at plan-build time via the `adaptationFields(at:)` snapshot method. This keeps the router fully unit-testable with pure Swift.

---

## D-059 — ML Dispatch Scheduling: scheduler design, budget signal, deferral caps (Increment 6.3)

### Context

`MLDispatchScheduler` coordinates MPSGraph stem separation with render-loop frame timing. When the GPU is stressed by a heavy ray-march+SSGI frame, a 142ms stem-separation burst landing on top of it causes a visible double-jank. The scheduler defers the 5s separation timer to a lighter moment rather than firing blindly.

**(a) Scheduler reads `recentMaxFrameMs` rather than `FrameBudgetManager.currentLevel`.**

`currentLevel` reflects long-term hysteresis: it can remain degraded for 180 frames after the renderer has actually recovered (per D-057's asymmetric upshift window). For ML scheduling we need the tighter "is the render clean right now?" signal. `recentMaxFrameMs` is the worst frame in the last 30-frame rolling window — it falls immediately when jank clears, giving the scheduler accurate real-time feedback. Using `currentLevel` would defer ML dispatches for up to 3 seconds after recovery, which is not useful.

**(b) `maxDeferralMs`: 2000 ms Tier 1, 1500 ms Tier 2. `requireCleanFramesCount`: 30 Tier 1, 20 Tier 2.**

Stem features from the 5s background cycle already lag real audio by 5–10 seconds (Increment 3.5.4.9 — per-frame analysis from cached waveforms continues regardless). Adding 2 s of ML deferral extends that lag to at most 7–12 s, which is within the acceptable range for preset routing freshness. Tier 2 (M3+) gets a tighter 1500 ms cap because jank is rarer on M3+ hardware; when it does occur, recovery is faster and the scheduler can react sooner.

**(c) Deferral always retries — never drops.**

A dropped stem dispatch means stems go completely stale for a full 5 s cycle, producing a visible freeze-and-jump in stem-driven preset visuals (the original defect fixed by Increment 3.5.4.9). Retrying every 100 ms with a hard force-dispatch ceiling guarantees stems are refreshed within `maxDeferralMs` of when they were requested, accepting one over-budget frame to prevent multi-second stem freeze.

**(d) Scheduler exempt under `QualityCeiling.ultra`.**

Recording mode wants consistent ML cadence at all times — frame consistency is more important than jank avoidance when producing a diagnostic capture. `enabled = false` when ultra; every `decide()` call returns `.dispatchNow` immediately.

**(e) `FrameTimingProviding` protocol for testability; single rolling buffer.**

The scheduler reads `recentMaxFrameMs` / `recentFramesObserved` via `FrameTimingProviding`, which both `FrameBudgetManager` and test stubs conform to. There is no parallel timing collection in the scheduler itself — `FrameBudgetManager.observe(_:)` records every frame into a 30-slot circular buffer shared by both the governor hysteresis logic and the ML scheduler. This is a single source of truth; duplicating the buffer would create divergence risk.

## D-064 — Increment V.5: visual references library structure, rubric-exempt classification, lint tool placement, and quality reel capture approach

### Context

Increment V.5 creates `docs/VISUAL_REFERENCES/` — the fidelity contract enforcing per-preset trait requirements across V.7+ authoring sessions. Four design decisions required recording.

### Decisions

**(a) Per-preset README structure: full-rubric vs lightweight variant.**

Two README variants were introduced. **Full-rubric** applies to the 9 artistic presets (Arachne, FerrofluidOcean, FractalTree, GlassBrutalist, Gossamer, KineticSculpture, Membrane, Starburst, VolumetricLithograph). The README carries three rubric sections (mandatory 7/7, expected ≥2/4, strongly preferred ≥1/4) matching `SHADER_CRAFT.md §12`. **Lightweight** applies to 4 presets: Plasma (demoscene hypnotic, family `hypnotic`), Waveform (family `waveform`, diagnostic spectrum view), Nebula (family `particles`, stylized particle system), SpectralCartograph (family `instrument`, diagnostic instrumentation panel). Lightweight READMEs replace the three rubric sections with a single "Stylization contract" listing what *does* matter: color modulation by audio energy, audio coverage, and readability at silence and peak. The four-layer detail cascade and 3+ material count are not meaningful requirements for these presets.

Membrane (family `fluid`, passes `feedback`) was classified as full-rubric because it is an artistic feedback-loop fluid preset with depth potential for meso/micro detail and material variation, despite being a simpler render path than a ray march preset.

**(b) Rubric-exempt list and rationale.**

The four lightweight presets and their exemption reasons:
- **Plasma** (`hypnotic/direct`): Demoscene interference-pattern aesthetic; the "3 distinct materials" and "4-layer detail cascade" requirements are undefined for a 2D colour-field shader. The relevant contract is: hue/saturation modulation must remain readable at silence vs peak energy.
- **Waveform** (`waveform/direct`): Diagnostic spectrum visualiser. Rubric does not apply; the relevant contract is legibility and colour accuracy at all signal levels.
- **Nebula** (`particles/direct`): Stylized particle system. No geometry cascade or material system; the particle render path doesn't support PBR materials. The relevant contract is palette coherence and emission density tied to energy.
- **SpectralCartograph** (`instrument/direct`): Four-panel MIR diagnostic. This is an instrument, not an aesthetic preset. The rubric has no meaningful application. The relevant contract is readability and correctness of displayed MIR data.

**(c) Lint tool placement: PhospheneTools (new package) vs PhospheneEngine (existing).**

The `CheckVisualReferences` lint CLI was placed in a new `PhospheneTools/` package rather than in `PhospheneEngine/Sources/`. Rationale: the lint check has no runtime dependency on the PhospheneEngine module graph (Audio, DSP, ML, Renderer, etc.); bundling it in PhospheneEngine would add build-time cost to a tool with no coupling to that code. A separate lightweight package (`PhospheneTools/Package.swift`) depends only on `swift-argument-parser`. This also establishes the package location for future `PhospheneTools/MilkdropTranspiler` (Phase MD.1+), consistent with `ENGINEERING_PLAN.md §Phase MD`.

The lint tool discovers presets by replicating `PresetLoader`'s flat filesystem scan (`Shaders/*.metal`, excluding `ShaderUtilities.metal`), so the preset list is always authoritative without importing the runtime module. This avoids hardcoding and keeps the lint correct even as new presets are added.

Default mode: fail-soft (prints warnings, exits 0). `--strict` flag: exits non-zero on any warning. The default flips to strict in V.6 once Matt's curation is complete; the decision is documented here to prevent the flip from being forgotten.

**(d) Quality reel capture: QuickTime, not in-engine pipeline.**

The quality reel (`docs/quality_reel.mp4`) is captured using macOS QuickTime Screen Recording (Cmd+Shift+5). An in-engine capture pipeline (ScreenCaptureKit video output, AVAssetWriter, frame-paced recording loop) was explicitly ruled out. Phosphene already uses ScreenCaptureKit for audio; adding simultaneous video output introduces a cross-cutting concern: frame-pacing interaction with the Metal render loop, `AVAssetWriter` initialization timing, drawable-size locking (see Failed Approach #28), and file-handling at session boundaries. These concerns have nothing to do with V.5's curation-framework scope. QuickTime delivers adequate quality (H.264 1080p60) with zero engine risk. The no-in-engine-capture decision is enforced in `RUNBOOK.md § Recording the quality reel`.

### What Was Rejected

- **Plasma and Waveform as full-rubric with a "2D exemption" on the cascade**: Creates a half-measured rubric that's harder to verify than a clean lightweight/full split. The distinction is clearer as a discrete variant than as per-rule exemptions.
- **Nebula as full-rubric (borderline)**: Nebula uses a `particles` pass, which has no PBR material system or geometry detail cascade. Treating it as full-rubric would require fabricating rubric compliance for requirements the render path fundamentally doesn't support.
- **Bash script for the lint check**: A bash script would hardcode the preset list (drift risk when new presets land) or use `find` + string manipulation to discover them (fragile). Swift CLI reads the same `Shaders/` directory that `PresetLoader` reads; the canonical preset list can never drift.
- **PhospheneEngine/Sources/CheckVisualReferences/**: Placing the tool inside PhospheneEngine was the V.4 pattern (`UtilityCostTableUpdater`). Rejected here because that tool needs `ArgumentParser` only and has zero runtime coupling; a new lightweight `PhospheneTools` package communicates the separation clearly and sets the precedent for Phase MD tooling.

---

## D-065 — §2.3 amendment: composite-preset image counts and AI-generated anti-reference carve-out

**Status:** Accepted

### Context

`SHADER_CRAFT.md §2.1` step 2 (established in D-064 / Increment V.5) specifies "3–5 reference images" per preset. `§2.3` of the same document requires that references be "curated, not AI-generated." Two divergences from these rules surfaced during Ferrofluid Ocean reference curation (V.9, pre-implementation):

1. **Composite-preset image count.** Ferrofluid Ocean's traits are not contained in any single photographable subject. The §10.3 spec borrows from ferrofluid lab macro, salt flats, dark coastlines, lotus leaves, sculpture lighting, storm photography, and underwater photography. Each trait requires its own dedicated reference; the resulting folder contains 11 images, well past the §2.1 "3–5" target. Trimming would require collapsing distinct-trait references into composites, forcing Claude Code sessions to read traits from images that aren't dedicated to teaching them.

2. **Anti-reference sourcing.** The anti-reference slot (`05_anti_*`) depicts a *failure mode* of the preset, not a target. For Ferrofluid Ocean the most pedagogically useful anti-reference is "ferrofluid that has lost its Rosensweig spike topology and become a generic chrome blob" — a phenomenon that does not occur in nature and therefore cannot be photographed. The alternatives are an AI-generated image of the failure mode, or a v1-baseline frame capture from the preset's existing implementation; the v1 capture is the long-term right answer but is not available pre-implementation.

### Decisions

**(a) Image count target softened from "3–5" to "3–5 typical, more permitted for composite presets, each image must isolate a distinct trait."**

`SHADER_CRAFT.md §2.1` step 2 amended. The 3–5 target is preserved as the default expectation; composite presets earn additional images by per-image trait justification, not by padding. The lint tool (`CheckVisualReferences`, D-064) is unchanged — it does not enforce a count ceiling, only that each preset has a populated folder with conformant filenames.

**(b) §2.3 amended to permit AI-generated images in the anti-reference slot only, under a narrow carve-out.**

Carve-out conditions:
- Only the anti-reference slot (`05_anti_*`).
- Filename must carry the `_AIGEN` suffix (e.g. `05_anti_chrome_blob_AIGEN.jpg`) so the AI provenance is visible in any session prompt that cites the file.
- README annotation must state that *every* trait of the image is anti — there is no partial-trust read of any visual property.
- README Provenance section must record a replacement plan, typically a v1-baseline frame capture, to be substituted when the preset's first implementation ships.

The carve-out does not extend to any other slot (`01_macro_*` through `04_specular_*`, `06_palette_*`, `07_atmosphere_*`, `08_lighting_*`, `09_*`). Real photography or controlled in-engine capture remains mandatory for those slots.

**(c) "Actively disregard" annotation convention promoted to a rule-level requirement.**

Reference annotations must specify three things, not two: (1) which traits are mandatory, (2) which are decorative, and (3) which traits of the image must be *actively disregarded* by Claude Code sessions reading the folder. The third category is added because real photography routinely contains structural cues that read as directives but are not — e.g. the radial vein pattern in a lotus-leaf droplet reference is not a directive about spike arrangement, and the colored gels in studio ferrofluid macros are not directives about palette. Without explicit disregard annotations, the more references a folder accumulates, the more confounders Claude Code sessions ingest. The Ferrofluid Ocean folder demonstrates the pattern; future preset folders inherit the convention.

### What Was Rejected

- **Hard image-count ceiling (e.g. "≤8 images per folder").** Would force composite presets to collapse distinct-trait references into composites, defeating the purpose of per-image annotation. The right enforcement is per-image trait justification, not a count.
- **Blanket AI-generation permission.** Would erode the §2.3 "curated > generated" intent in the cases where it actually matters (the target-trait slots). Confining the carve-out to the anti-reference slot preserves the rule's force everywhere it's pedagogically meaningful.
- **No `_AIGEN` suffix; AI-provenance only in the README.** Filename suffix is enforceable by lint and visible in session prompts; README-only disclosure is forgettable.
- **Permanent acceptance of AI-generated anti-references.** The replacement-plan requirement (v1-baseline capture once the preset ships) ensures AI generation is a stopgap, not a permanent feature of the reference library.

---

## D-067 — V.6 certification pipeline: module placement, lightweight exemptions, manual gate, and fallback behavior (Increment V.6)

**Status:** Accepted

### (a) Module placement: Presets, not Renderer

The rubric analyzer lives in `Sources/Presets/Certification/`, not `Sources/Renderer/`. The Renderer module depends on Presets (for `PresetDescriptor`), but not vice versa. Placing `FidelityRubric` in Renderer would require Renderer to circularly import Presets, or would force `PresetDescriptor` out of Presets. Placing it in Presets keeps the dependency graph acyclic and requires no `Package.swift` changes.

### (b) Lightweight profile exemptions

Plasma, Waveform, Nebula, and SpectralCartograph use a 4-item lightweight rubric (L1 silence, L2 deviation primitives, L3 perf, L4 frame match) instead of the full 15-item ladder. These presets are either 2D spectrum visualizers (Waveform/Plasma) or diagnostic panels (SpectralCartograph) where detail cascade, 3D material count, and triplanar texturing are inapplicable by design. The exemption is declared per-preset via `"rubric_profile": "lightweight"` in the JSON sidecar. `DefaultFidelityRubric` routes to a separate 4-item evaluation path. See D-064 for the original classification rationale.

### (c) `certified` is manual-only

The `certified: Bool` field is never set to `true` by automation. `meetsAutomatedGate` captures what the static/runtime analyzer can verify; the `certified` field is exclusively Matt's signal after a reference-frame match review against `docs/VISUAL_REFERENCES/<preset>/`. The two flags are intentionally separate so a preset can pass all automatable items and still await manual review. `RubricResult.isCertified = meetsAutomatedGate && certified`.

### (d) All-uncertified fallback: warn, do not throw

When all presets score 0 (all uncertified, toggle off), `DefaultSessionPlanner` already has a `noEligiblePresets` path that emits a `PlanningWarning` and falls back to the cheapest non-excluded preset. No new error case is needed. The window between V.6 landing and Matt's first certification flip is handled by this existing ladder — users with the toggle off get the cheapest preset rather than an error.

---

## D-073 — `maxDuration` per-section linger factors inverted (Option B); diagnostic class added (V.7.6.C calibration)

**Date:** 2026-05-03

**Context:** V.7.6.2 shipped the `maxDuration` framework (formula in `PresetMaxDuration.swift`, computed property on `PresetDescriptor`, multi-segment walk in `SessionPlanner`). V.7.6.C is the calibration pass against the §5.3 reference table. Matt reviewed the printed table at the §5.2 default coefficients.

**Problems Matt flagged:**

1. **Spectral Cartograph is diagnostic, not aesthetic.** The framework was treating it as a normal preset and giving it a finite ceiling. Diagnostics should remain in place until manually switched — they have a different operational role (instrument-family observability) and the segment scheduler should never insert a boundary mid-diagnostic.
2. **Per-section linger model was inverted.** Original §5.2 had `ambient=0.30` (shortest) and `peak=0.80` (longest), on the theory that low-variance audio gives the preset less to chew on. Matt's intuition is the opposite: ambient sections are exactly where you'd want a preset to *linger* — meditative, contemplative, a switch would feel disruptive.

**Decision:**

(1) **Add diagnostic class.** New `is_diagnostic` JSON field on `PresetDescriptor` (default `false`). When true, `maxDuration(forSection:)` short-circuits to `.infinity`. Spectral Cartograph is flagged true (only diagnostic in the catalog). Implementation is one boolean and one short-circuit; no formula change. The broader "diagnostic presets are manual-switch only / never auto-selected" semantic (Scorer hard-exclusion + LiveAdapter no-override) is **out of V.7.6.C scope**, scheduled as V.7.6.D.

(2) **Invert per-section linger to Option B.** Two models considered: Option A — linger on slow only (ambient=0.80, peak=0.30); Option B — linger on emotional cores (ambient=0.80, peak=0.75) with transitional sections shortened (buildup=0.40, bridge=0.35). Matt picked Option B: ambient and peak both linger because they're the emotional-core moments of a song; buildup and bridge are transitional moments where preset changes feel natural. Final table: `ambient=0.80, peak=0.75, comedown=0.65, buildup=0.40, bridge=0.35`. Default (section=nil) stays 0.5. Field renamed `sectionDynamicRange` → `sectionLingerFactor` to reflect that values are now author-set per-section weights, not derived from audio variance.

(3) **No formula coefficient changes.** `baseDurationSeconds=90`, `motionPenalty=-50`, `fatiguePenalty=-30`, `densityPenalty=-15`, `sectionAdjustBase=0.7`, `sectionLingerWeight=0.6` all unchanged. The original V.7.6.2 agent's calibration notes (Glass Brutalist ~30s intuition; Gossamer feels long for limited compositional variation; Murmuration computes same as Glass Brutalist) were observations, not directives. Matt's V.7.6.C review note: *"Note that you are grading presets that are all not certified and VERY far from ready."* Tuning the formula to one uncertified outlier optimises for an artistic target the preset hasn't reached yet. If a future certified Glass Brutalist genuinely cycles every 30s, declaring `natural_cycle_seconds: 30` is the right tool, not a coefficient warp.

**Why no Glass Brutalist `naturalCycleSeconds` cap landed in V.7.6.C:** The 30s intuition was from the V.7.6.2 agent, not directly from Matt. Matt's review explicitly flagged that the presets are uncertified and far from ready. Adding a cap now would lock in a number that's likely wrong for the certified version of the preset.

**§5.3 reference table is now authoritative against current production sidecars.** Old §5.3 had several stale metadata values (e.g. Plasma motion 0.85 vs actual 0.5, Nebula 0.50 vs actual 0.30); the V.7.6.C rewrite reflects what's actually in the JSON. Stalker dropped (no production assets in `Shaders/`); Fractal Tree added.

**Implementation:** `PresetMaxDuration.swift` (formula + linger factors), `PresetDescriptor.swift` (`isDiagnostic` field + CodingKeys + decode), `SpectralCartograph.json` (`is_diagnostic: true`), `MaxDurationFrameworkTests.swift` (reference table + diagnostic test + Option B ordering test + `isDiagnostic` default test), `docs/presets/ARACHNE_V8_DESIGN.md` §5.2/§5.3/§5.4 updated.

**Verification:** 912 engine tests / 97 suites green. App build succeeds. SwiftLint 0 violations on touched files. GoldenSessionTests not regenerated — default-section maxDuration unchanged at lingerFactor=0.5 (multiplier 1.0); planner sequences identical.

**Rule:** Per-section weights in the `maxDuration` framework are author-set linger factors, not audio-variance signals. Naming reflects that. Future calibration sessions tune the per-section table by intuition, not by computing audio variance from track preparation data.

**Rule:** Diagnostic presets (`is_diagnostic: true`) are exempt from segment scheduling and (per the V.7.6.D follow-up) auto-selection. They are operational tools, not aesthetic content. Spectral Cartograph is the prototype; future diagnostics use the same flag.

**Rule:** Do not coefficient-tune the `maxDuration` formula to an uncertified preset's intuition target. Use `natural_cycle_seconds` for outliers only when the visual genuinely has a fixed cycle. If the artistic target moves with certification, the coefficient-tuned value will become wrong.

## D-074 — Diagnostic preset orchestrator semantics (V.7.6.D)

> **⚠ RE-EVALUATE (audit 2026-05-13).** Categorical exclusion of diagnostic presets from scoring + live adaptation + reactive mode. Currently the only diagnostic preset is Spectral Cartograph, and there is no realistic scenario where it would be auto-selected — so the rule is over-general for the one consumer it has. Worth a revisit when a second diagnostic preset ships, or when the manual-switch path is exercised in a way that surfaces friction.

**Date:** 2026-05-03

**Context:** V.7.6.C (D-073) added the `is_diagnostic` flag with one effect — `maxDuration(forSection:)` returns `.infinity` so `SessionPlanner` never inserts a segment boundary mid-diagnostic. The broader semantic — diagnostics are operational tools, not aesthetic content, so they must never be auto-selected, never receive a mid-track override, and only render via manual switch — was scoped as a V.7.6.D follow-up.

**Decision:** Extend the flag's effect into the Orchestrator at three surfaces:

1. **`DefaultPresetScorer` hard exclusion.** A new gate runs *first* in `exclusionReasonAndTag`, before the certification check, and returns `excludedReason: "diagnostic"` with `total: 0`. Unlike `includeUncertifiedPresets`, there is no settings toggle that re-enables diagnostics for auto-selection — the gate is categorical.
2. **`DefaultLiveAdapter` emission-site guard.** The mood-override path's `guard let (topPreset, topScore) = ranked.first, …` is extended with `!topPreset.isDiagnostic`. The Scorer change already gives diagnostics `total = 0`, but the explicit guard at the emission site is harder to regress when the scoring math changes.
3. **`DefaultReactiveOrchestrator` defensive filter.** The `ranked.first` selection becomes `ranked.first(where: { !$0.0.isDiagnostic })` so a degenerate catalog (e.g. all-zero scoring tie containing diagnostics) cannot resurrect one.

`SessionPlanner` and the multi-segment walker inherit the gate transparently because they consume `PresetScoring` — no planner-level change needed; tests confirm diagnostics never appear in `plan.tracks[].preset`.

**Manual-switch path is unchanged.** `PlaybackActionRouter` and the keyboard / dev surfaces operate on `PresetDescriptor` directly without going through scoring. The exclusion is auto-only by design — diagnostics like Spectral Cartograph remain reachable through the existing manual paths.

**Implementation:** `PresetScorer.swift` (new diagnostic exclusion as first gate), `LiveAdapter.swift` (one-line guard on the override-emission `guard`), `ReactiveOrchestrator.swift` (`first(where:)` filter), `OrchestratorDiagnosticExclusionTests.swift` (7 tests covering scorer, adapter, planner, reactive, and the manual-switch positive case).

**Verification:** 919 engine tests / 98 suites; 918 pass — the single failure is the pre-existing flaky `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` (network timing under load, unrelated). App build succeeds. SwiftLint 0 violations on touched files. `GoldenSessionTests` unchanged — diagnostic presets were already absent from production goldens (Spectral Cartograph carries `certified: false`), so the additional gate is a no-op against current sequences.

**Rule:** Diagnostic presets are categorically excluded from auto-selection at every Orchestrator surface. The exclusion fires before certification, before family boost, before any user toggle. The only path that renders a diagnostic is manual switch on the renderer/keyboard surface, which bypasses scoring entirely.

**Rule:** When a flag has both a data-model effect and an Orchestrator-policy effect (like `is_diagnostic`), implement the data-model effect first (here: `maxDuration` short-circuit, V.7.6.C / D-073) and the policy effect second (here: scorer + adapter exclusions, V.7.6.D / D-074). Splitting keeps each commit's blast radius small and lets each layer's tests be written and reviewed independently.

---

## D-075 — Tempo BPM via sub_bass-only onset timestamps + trimmed-mean IOI (DSP.1)

**Date:** 2026-05-03

**Context:** The IOI histogram in `BeatDetector+Tempo.swift` was producing systematic tempo errors on real music — Failed Approach #17 ("autocorrelation half-tempo, known octave error") in CLAUDE.md. The DSP.1 increment was originally scoped as IOI histogram half/double voting (a scoring pass over harmonic candidates {0.5×, 0.667×, 1×, 1.5×, 2×} of the histogram peak). A diagnostic harness (`PhospheneEngine/Sources/TempoDumpRunner` + `Scripts/analyze_tempo_baselines.py`) capturing per-band onset timestamps on three reference clips (Love Rehab @ 125 BPM, So What @ 136 BPM, There There rock-syncopated) revealed the failures were not classical octave errors and that voting could not fix them.

**Two diagnoses surfaced:**

1. **Fusion frame-aliasing.** `recordOnsetTimestamps` consumed `bandFlux[0] + bandFlux[1]` (sub_bass + low_bass summed into a single threshold gate). Per-band cooldowns in `detectOnsets` (400 ms each) are independent across bands. A 60 Hz kick fires flux events in *both* bands at slightly different frames — the kick fundamental peaks first, the harmonic peaks one or two FFT-hop frames later. With sub_bass firing at frame 19 and low_bass firing at frame 18 of the next kick, the OR-stream produces alternating 18-frame (418 ms) and 19-frame (441 ms) IOIs for a true 441 ms (136 BPM) beat. Per-band fixtures showed clean meanIOI 440 ms for so_what's sub_bass alone; the fused stream's meanIOI was 322 ms.

2. **Histogram-mode quantization bias toward faster BPMs.** The histogram bucketed by `Int(round(60/ioi)) - 60` — integer BPM. BPM bucket widths *grow* with BPM in period space (the 144 BPM bucket spans 414–420 ms; the 136 BPM bucket spans 437–443 ms). So an evenly-quantized stream of 18-frame (418 ms) and 19-frame (441 ms) IOIs lands more events in the 144 bucket than the 136 bucket even when the underlying tempo is 136. Picking the histogram mode systematically biased toward 144.

**Decision — two changes shipped together as DSP.1 (commit `bbad760f`):**

1. **Source IOI timestamps from sub_bass `result.onsets[0]` only.** `recordOnsetTimestamps(onsets:bandFlux:)` now `guard onsets[0] else { return }`. Never OR with low_bass. The 400 ms `detectOnsets` cooldown gives clean kick-rate IOIs without bass-note pollution, and using a single band avoids the inter-band frame-aliasing entirely. Tracks with empty sub_bass fall through to the autocorrelation tempo path (`estimateTempo`) — graceful degradation, not silent failure.

2. **Replace histogram-mode BPM with trimmed-mean IOI (`computeRobustBPM`).** Compute median IOI over the 10 s window, drop IOIs outside [0.5×, 2×] median (rejecting outliers from dropped beats or fills), take the mean of the inliers, BPM = `60 / meanIOI`. The 80–160 octave clamp is preserved. Mean is FP-precise — meanIOI 440 ms maps to 60/0.440 = 136.36 BPM, exactly matching the audio. The histogram is still built (cheaply) for the diagnostic dump only; the BPM selection bypasses it.

**Reference-track results (pre-DSP.1 → post-DSP.1):**

| Track | True BPM | Pre | Post | Status |
|---|---|---|---|---|
| Love Rehab (Chaim) | 125 | 117 / 152 (cycling) | 122–126 | ±1 BPM |
| So What (Miles Davis) | 136 | 152 | 135–138 | ±2 BPM |
| There There (Radiohead) | ~86 (syncopated) | 144 | 137–140 | unfixed (kick rate, not meter) |

There There remains wrong because the bass kick is not on every beat — the histogram correctly reads the kick-pattern interval, but for syncopated rock the underlying meter is half that. This is a syncopation limitation outside DSP.1's scope and is the load-bearing motivation for DSP.2 (BeatNet, D-076 reserved).

**Alternatives considered:**

- **Voting over harmonic candidates (original DSP.1 scope).** Rejected after diagnosis — the failures aren't octave errors. love_rehab's histogram peak was 117 BPM, with autocorrelation independently agreeing at 117.45 BPM conf 0.93 across the run. Both methods read the same skewed evidence; voting over {58.5, 78, 117, 175.5, 234} cannot recover 125 because none of those are 125. The voting math was structurally inapplicable.
- **Fuse with hysteresis.** Keep the OR-of-bands but require sub_bass+low_bass agree within X frames before firing. Rejected — adds a tunable parameter without solving the underlying frame-aliasing; per-band cooldowns in `detectOnsets` already enforce within-band kick rate.
- **Band-picker (P75 of sub_bass vs low_bass, use whichever is louder).** Implemented and tested mid-iteration. Did not help — the picker oscillates frame-to-frame near the boundary, producing the same staggering artifacts as fusion.
- **300 ms minimum spacing widened from 150 ms.** Implemented mid-iteration and reverted. With sub_bass-only sourcing, the 400 ms `detectOnsets` cooldown already enforces clean spacing; the `recordOnsetTimestamps` guard is defensive only, and 150 ms is sufficient.
- **TempoCNN.** AGPL — incompatible with Phosphene's MIT license.
- **Sound Analysis framework.** Genre-classification, not beat-tracking — orthogonal to BPM estimation.
- **aubio integration.** A native C library would be a real dependency the project has not taken on. Deferred to DSP.2's "stay within Swift / MPSGraph idiom" path; if BeatNet underperforms, aubio becomes a fallback option to revisit then.

**Consequences:**

- DSP.1 ships a tempo improvement for kick-on-the-beat tracks (electronic, jazz, most pop). Reference fixtures so_what and love_rehab are now within ±2 BPM of metadata; both were 10–20 % off pre-DSP.1.
- The histogram remains in the codebase for diagnostic-dump use only. Future tempo work should not re-introduce histogram-mode picking; mean-of-inlier-IOIs is the baseline.
- Tracks where the bass kick is not on every beat (syncopated rock, swing, hip-hop with off-beat kicks) remain unsolved. These motivate DSP.2 (BeatNet via MPSGraph). DSP.1 is the floor; DSP.2 raises the ceiling.
- The diagnostic harness (`TempoDumpRunner`, `analyze_tempo_baselines.py`, fetched 30 s preview fixtures) becomes permanent regression infrastructure for DSP.2 and any future tempo work. The fixtures themselves are gitignored (`Tests/Fixtures/tempo/`) — preview clips are licensed; users run `Scripts/fetch_tempo_fixtures.sh` locally to populate them.
- Failed Approach #17 in CLAUDE.md needs amendment: the "autocorrelation half-tempo" framing is inaccurate. The real failure was fusion-induced frame aliasing plus histogram-mode quantization bias, both of which are now fixed for the kick-on-the-beat case. Tracks where DSP.1 still fails (syncopated rock) fail for a *different* reason than #17 originally described — that's a beat-tracking-vs-tempo-estimation distinction belonging to DSP.2.

**Rule:** Tempo estimators that operate on inter-onset intervals must source events from a single, well-cooled band. Fusing onset events across bands (even by summing flux) creates frame-aliased spurious IOIs.

**Rule:** Do not bucket continuous quantities by integer-rounded BPM when the natural quantization is frame-period (in time, not BPM). Compute robust statistics (median, trimmed mean) directly on the period samples.

**Rule:** When a hypothesized failure mode (here: half-tempo octave error) is documented in `CLAUDE.md` and an increment is scoped against it, the *first* commit should be diagnostic instrumentation that captures the actual failure shape — not implementation of the fix. The DSP.1 voting work would have shipped uselessly without the per-band onset diagnostic that revealed the real bugs. Diagnostic-first applies even when the documented failure mode is widely known to the team.

---

## D-077 — Phase DSP.2 pivot from BeatNet to Beat This!

**2026-05-04.** Phase DSP.2 retargets the offline beat / downbeat path from BeatNet (Heydari & Duan, 2021 — CRNN + particle filter cascade, CC-BY-4.0) to Beat This! (Foscarin et al., ISMIR 2024 — transformer encoder, MIT). The product reason is single-sentence: complex meters are a load-bearing requirement for Phosphene's beat lock (Pyramid Song 16/8, Money 7/4, Schism 7/8, swing tracks like So What), and BeatNet's particle filter is a known weak point on irregular meters whereas Beat This!'s self-attention captures whole-bar context.

**Alternatives considered:**

* **BeatNet (incumbent).** CRNN + particle filter, ~0.4 M params, native streaming mode (~84 ms latency), particle filter is the bottleneck on 5/4, 7/8, swing. Octave-error history per `docs/diagnostics/DSP.1-baseline-there_there.txt`. Stays vendored as a fallback per D-076 retirement note.
* **All-In-One** (Kim et al., ISMIR 2023). Joint beat / downbeat / section-boundary transformer. Strictly more capable than Beat This! for Phosphene's needs (would also retire `StructuralAnalyzer` / `NoveltyDetector`), but two-axis scope creep in a single increment is too risky. Reserved as a follow-up; if All-In-One supersedes Beat This! later, the Sessions 2–7 architecture in this increment was designed to swap the model with no upstream / downstream changes.
* **madmom DBN beat tracker.** Offline DBN over autocorrelation; classical baseline. Older numbers, no MPS-graph-portable model, requires the full madmom Python runtime. Not viable.
* **Beat Transformer / BEAST.** Research code; no shipped pre-trained weights with a usable license. Not viable.

**Architectural placement:** Beat This! runs once per track during `SessionPreparer.prepareTrack` on the cached 30 s preview clip (the existing pre-analysis budget absorbs ~100–300 ms of transformer inference per track on M1). Output is cached on `TrackProfile` as a new `BeatGrid` value type (`beats`, `downbeats`, `bpm`, `timeSignature`, `confidence`, `modelVariant`). The live audio path *does not* run a transformer; instead, a new `LiveBeatDriftTracker` cross-correlates `BeatDetector`'s sub_bass onset stream against the cached grid in a ±50 ms phase window and emits a smooth drift estimate. `FeatureVector.beatPhase01` and `beatsUntilNext` are then computed analytically from `playbackTime + drift` against the cached grid — no contract change for any existing preset shader.

**Replaces:** `BeatPredictor` (deleted in Session 7); `BeatDetector+Tempo.computeRobustBPM` as the primary BPM source (kept only as ad-hoc reactive-mode fallback). `BeatDetector` itself stays — its onset stream is the input to the live drift tracker and continues to feed `StemAnalyzer` rich metadata. `StructuralAnalyzer` / `NoveltyDetector` are unchanged in this increment.

**License & attribution:** Beat This! ships under MIT (cleaner than BeatNet's CC-BY-4.0 attribution requirement). Attribution lives in `docs/CREDITS.md` and the shipped app's About surface; details locked in Session 1.

**Cleanup committed alongside this decision:** the in-flight BeatNet preprocessor stub (`PhospheneEngine/Sources/DSP/LogSpectrogram.swift`), the vendored filterbank corner triples (`PhospheneEngine/Sources/DSP/Resources/beatnet_filterbank.json`), the `dump_logspec_reference.py` reference dump script, and the `love_rehab_logspec_reference.json` test fixture were deleted. The architecture audit (`docs/diagnostics/DSP.2-architecture.md`) was renamed to `DSP.2-beatnet-archive.md` and marked superseded. The BeatNet weight set under `PhospheneEngine/Sources/ML/Weights/beatnet/` is retained.

**Spec drift discipline.** The trigger for the pivot was a Session-2-of-DSP.2 audit pass that found the BeatNet architecture doc had paraphrased the FFT spec (claimed `fft_size=2048` next-pow2; madmom's actual default is `fft_size=frame_size=1411` with `include_nyquist=False`). This is the second time in a row (D-075 trimmed-mean IOI fix was the first) that paraphrased-from-prose specs landed code that diverged silently from the reference. The Beat This! port adds a per-stage golden-test gate at every pipeline boundary (Session 2 preprocessor; Session 4 layer-by-layer numerical match) so any future drift fails fast at the right stage, not three sessions downstream.

---

## D-078 — Diagnostic hold semantics and prepared-BeatGrid authority (DSP.3.1/3.2)

**2026-05-05.** Establishes two standing conventions for the diagnostic environment and the beat-grid lifecycle.

### Convention 1: Diagnostic hold pins the visual surface, not the planner

`VisualizerEngine.diagnosticPresetLocked` suppresses `LiveAdaptation.presetOverride` (the mood-derived preset switch emitted by `DefaultLiveAdapter`) but has no effect on:

- `livePlan` — the planned session remains loaded and continues to evolve via structural-boundary rescheduling (`updatedTransition`).
- `mirPipeline.liveDriftTracker` — beat tracking and lock state continue accumulating.
- `SpectralHistoryBuffer` — all slots including session_mode [2420] continue updating.
- `applyPresetByID(_:)` / `nextPreset()` / `previousPreset()` — manual surface controls always work.

The hold strips `presetOverride` from `LiveAdaptation` before it patches `livePlan`, so the plan itself is not dirtied. Structural-boundary rescheduling (`updatedTransition`) is never suppressed — planned end times of upcoming tracks can still shift in response to detected section boundaries.

**Motivation:** A diagnostic observer needs the engine to stay on Spectral Cartograph long enough to confirm the beat-lock transition. Without the hold, `DefaultLiveAdapter` evicts Spectral Cartograph within ~60 seconds because its orchestrator score is 0.0 (`is_diagnostic: true` excludes it from scoring). The hold prevents that eviction without disturbing any state the observer is trying to measure.

**Rule:** Diagnostic hold is a display-layer suppression, not a session-state freeze. Never implement it by pausing the planner, the drift tracker, or the MIR pipeline. Hold means "don't switch away from what I'm looking at"; not "pause everything else."

### Convention 2: Prepared BeatGrid is authoritative; reactive beat tracking is fallback only

When `mirPipeline.liveDriftTracker.hasGrid == true`, `MIRPipeline.buildFeatureVector` drives `beatPhase01` and `beatsUntilNext` from the cached grid plus live drift estimate. `BeatPredictor` is bypassed on the grid path and runs only when `hasGrid == false`.

The grid is installed early: `_buildPlan(seed:)` calls `resetStemPipeline(for: plan.tracks.first?.track)` immediately after `livePlan` is stored, before the user presses play. The drift tracker is loaded and ready to match onsets from the very first beat of the session.

**Motivation:** Before DSP.3.2, the BeatGrid was only installed on the first track-change event (after the first audio callback). In the `.ready → .playing` window, `hasGrid` was false and Spectral Cartograph showed `○ REACTIVE` even for a fully-prepared Spotify session — visually indistinguishable from a truly reactive ad-hoc session. The pre-fire call closes that window.

**Rule:** Any code path that calls `_buildPlan()` should ensure `resetStemPipeline(for:)` fires for the first track when a BeatGrid is available. `extendPlan()` and `regeneratePlan()` both delegate to `_buildPlan()` and are already covered. The `is_diagnostic` flag on `SpectralCartograph.json` causes the orchestrator scorer to return 0.0, preventing auto-selection while keeping the preset reachable via manual controls.

**Implementation:** Commit `56359c07`. Audit context: `docs/diagnostics/DSP.3-beat-sync-test-environment-audit.md`.

---

## D-079 — Sample rate is captured once per tap install; literal `44100` is a CI-banned constant (Phase QR.1)

**2026-05-06.** Closes the recurrence of Failed Approach #29 (the *Audio MIDI Setup* layer) at the *code* layer — Failed Approach #52. The 2026-05-06 multi-agent codebase review (Architect H1; Audio+DSP D1, D3, A2, B1; ML #1+#2) traced five live-tap consumers in `PhospheneApp` that hardcoded `sampleRate: 44100` regardless of the actual Core Audio tap rate. On a 48 kHz tap (the macOS Audio MIDI Setup default) every site silently produced wrong-rate data: stems were 8.8 % time-stretched and pitch-shifted before separation, biasing every downstream stem-feature analysis the orchestrator scores against. Compounding the rate plumbing, `tapSampleRate` was mutated from the audio thread without a synchronization barrier — cross-core visibility for an unsynchronized 8-byte field is not guaranteed on Apple Silicon, producing wrong-tempo grids ~1-in-1000 sessions invisible in tests.

### Rules

1. **`tapSampleRate` is captured once per tap install and read through a synchronization barrier.** `VisualizerEngine.tapSampleRate` is now backed by `_tapSampleRate` under `tapSampleRateLock` (NSLock). The audio callback writes via `updateTapSampleRate(_:)`; consumers on `stemQueue` and `analysisQueue` read via the lock-guarded property. The value is stable for the lifetime of a tap install; on capture-mode switching the new tap's first callback writes the new rate. (Architect H1.)
2. **Literal `44100` is banned outside an explicit allowlist.** Allowlisted call sites are: `StemSeparator.modelSampleRate` (the model's native 44100 Hz output rate), `BeatThisPreprocessor.sourceSampleRate` (Beat This! native 22050 Hz, allowlist also covers the Beat This! source rate), procedural-audio fixture generators in `Diagnostics/SoakTestHarness+AudioGen.swift`, default-argument boilerplate in `StemSampleBuffer` / `StemAnalyzer` / `PitchTracker` (production callers always pass an explicit value; defaults exist only so tests / fixture code can instantiate without threading a rate through), and the test target's fixture audio. Every other occurrence is a regression. `Scripts/check_sample_rate_literals.sh` runs in CI and fails loud on any non-allowlisted hit.
3. **`StemSampleBuffer` must use the rate-aware overload at every consumer.** The buffer's stored init rate (44100 Hz) sizes capacity conservatively; the *retrieval* size depends on the actual tap rate. `snapshotLatest(seconds:sampleRate:)` and `rms(seconds:sampleRate:)` are the canonical APIs; the no-rate overloads route through them at the buffer's stored rate (legacy behaviour preserved for tests). The five live-tap consumers in `PhospheneApp` thread `tapSampleRate` through every call.
4. **Octave correction is halving-only across the entire tempo path.** `BeatDetector+Tempo.computeRobustBPM` and `BeatDetector+Tempo.estimateTempo` previously contained `if bpm < 80 { bpm *= 2 }` branches that doubled any sub-80 estimate to 150. This contradicts `BeatGrid.halvingOctaveCorrected` (halving-only by design — Pyramid Song genuinely runs at ~68 BPM and any track in [40, 80) BPM must survive). Both branches deleted; halving (`if bpm > 160 { bpm /= 2 }`) preserved. (Audio+DSP A2.)
5. **`MIRPipeline.elapsedSeconds` is `Double`-precision.** A long-session `+= deltaTime` accumulator at Float precision reaches ULP ≈ 240 µs at 30 minutes — smaller than the ±30 ms tight-match window in `LiveBeatDriftTracker` but a guaranteed monotonic drift over hours of listening. `elapsedSeconds` (and the related `lastOnsetRateTime` / `lastRecordTime` accumulators) now store as `Double`; consumers cast to `Float` once at the FeatureVector / CSV write site. `LiveBeatDriftTracker.update(playbackTime:)` parameter widened to `Double` to keep the precision through onset matching and lock-state computation. (Audio+DSP D3.)
6. **`KineticSculpture.metal` drives mercury-melt sminK from deviation primitives.** Pre-QR.1 `f.sub_bass * 0.28 + f.bass * 0.10` thresholded raw AGC-normalized energy with an unset / unreliable sub-band (`f.sub_bass` is rarely set in fixtures or in real tracks where bass is wide-band) weighted with an arbitrary 2.8× factor. Replaced with a continuous-energy baseline plus deviation accent: `0.06 + f.bass * 0.16 + f.bass_dev * 0.05`. The bass term is Layer 1 of the audio data hierarchy (continuous, primary visual driver); the deviation term is the per-onset accent and stays within the "beat ≤ 2× continuous" rule enforced by `PresetAcceptanceTests`. (Audio+DSP B1.)

### Coverage gap (acknowledged)

The actual `tapSampleRate` capture path runs in `VisualizerEngine`, which cannot be instantiated in SPM tests (Metal + audio tap dependency). `Tests/.../Integration/TapSampleRateRegressionTests.swift` covers the load-bearing structural path — the rate-aware `StemSampleBuffer` API the app threads through — and prevents the most common regression mode (silent reversion to 44100 in the buffer/RMS path). App-target coverage is a follow-up; the lint gate plus structural tests are the standing defence.

### Capture-mode rate change (deferred)

If a capture-mode switch (CaptureModeSwitchCoordinator) re-installs the tap with a different rate, the `_tapSampleRate` field updates on the next audio callback under lock — readers see the new rate within one frame. Dependent buffers (`StemSampleBuffer`, `StemAnalyzer`) keep their original sizing, which is conservative (44100 init covers up to 13.78 s on a 48 kHz tap; every consumer requests ≤ 10 s). A tear-down and re-init on rate change is technically cleaner but the cascading orchestrator effects are out-of-scope for this increment; revisit if real-world capture-mode switches expose problems.

### Failed Approaches (D-079)

- **#29 (recurrence at the code layer): hardcoded `44100` consumed live tap audio.** Five sites identified; all fixed in this increment.
- **#52: literal `44100` regression in tap-consuming code paths.** Now CI-gated. Default-argument boilerplate retained on the explicit allowlist (`StemSampleBuffer`, `StemAnalyzer`, `PitchTracker`) for test ergonomics; production wiring overrides every default.

---

## D-080 — Stem-affinity scoring uses deviation primitives + mean formula (Phase QR.2)

**2026-05-06.** Closes Failed Approaches #53 (AGC-saturated stem-affinity clamped sum) and #54 (reactive `TrackProfile.empty` adversarial penalty). The 2026-05-06 multi-agent codebase review (Orchestrator O1) showed `DefaultPresetScorer.stemAffinitySubScore` accumulated raw AGC-normalized energies across declared affinities and clamped to [0,1]. Because AGC centers each energy field at ~0.5, any preset declaring 2+ stems saturated at ~1.0 on almost all music — the 25% stem-affinity weight did no differentiation work. The same review showed `DefaultReactiveOrchestrator` constructed scoring contexts with `TrackProfile.empty.stemEnergyBalance == StemFeatures.zero`, causing presets with declared affinities to score 0 in stem affinity (zero-balance → devSum = 0) while neutral presets scored 0.5 — the most musically-engaged catalog members were the most penalized in reactive mode.

### Rules

1. **`stemAffinitySubScore` uses deviation primitives (MV-1, D-026) and mean formula.** Score = `mean(max(0, stemEnergyDev[stem]))` over declared affinities, clamped [0, 1]. Dev fields are already on `StemFeatures` floats 17–24. This formula produces score > 0.5 only during genuinely above-average stem transients, making stem affinity a true tiebreaker rather than an always-on bonus or always-on penalty.

2. **Zero-balance guard: `StemFeatures.zero` returns neutral 0.5.** When `stemEnergyBalance == .zero` (EMA not yet converged — typically the first 10 s of live play, or pre-analyzed sessions where devs are near zero), return 0.5 for all presets. This prevents the adversarial penalty: stem-affinity presets are never scored *below* neutral during the unconverged phase.

3. **`DefaultLiveAdapter` has a 30 s per-track mood-override cooldown.** `DefaultLiveAdapter` is now a `final class @unchecked Sendable` (not a struct) with `NSLock`-guarded `lastOverrideTimePerTrack: [TrackIdentity: TimeInterval]`. The first override on any track fires immediately; subsequent overrides within 30 s of the last are suppressed with a `moodDivergenceDetected` event. The cooldown resets on track change (new key in the dictionary).

4. **`minBoundaryScoreGap = 0.05`: boundary-only switch gate tightened.** `DefaultReactiveOrchestrator.compareAndDecide` previously allowed a boundary to trigger a switch when `confidence >= 0.5` regardless of score gap. New gate: `confidence >= 0.5 && scoreGap > minBoundaryScoreGap(0.05)`. Prevents switches when the current preset is already the best option.

5. **`cutEnergyThreshold` raised from 0.7 → 0.85.** Reserves hard-cut transitions for true climax moments (arousal-derived energy > 0.85).

6. **`recentHistory` capped at 50 entries.** `DefaultSessionPlanner` trims the history deque after append; prevents unbounded memory growth in long sessions.

7. **Live `StemFeatures` wired into reactive mode after 10 s.** `VisualizerEngine.applyReactiveUpdate()` passes `pipeline.currentStemFeatures()` as `liveStemFeatures` once `elapsed >= 10.0 s`. Before 10 s the zero-balance guard returns neutral 0.5 for all presets; after 10 s real dev values differentiate stem-affinity presets from neutral presets.

### Consequence for planned sessions

Pre-analyzed `TrackProfile.stemEnergyBalance` is populated from `StemFeatures` snapshots whose EMA has converged over the 30-second preview — dev fields are near zero. This means stem affinity is neutral (0.5) for all presets in planned-session scoring. The 25% weight is now shared equally, and mood + section + tempo dominate planned-session selection. Golden session sequences updated accordingly in `GoldenSessionTests.swift`.

### Implementation

`Sources/Orchestrator/PresetScorer.swift`: `stemAffinitySubScore` + `stemEnergyDeviation` helper. `Sources/Orchestrator/LiveAdapter.swift`: struct → class, `cooldownLock` + `lastOverrideTimePerTrack`. `Sources/Orchestrator/ReactiveOrchestrator.swift`: `minBoundaryScoreGap`, `liveStemFeatures` protocol parameter. `Sources/Orchestrator/TransitionPolicy.swift`: `cutEnergyThreshold` 0.7 → 0.85. `Sources/Orchestrator/SessionPlanner+Segments.swift`: history trim. `PhospheneApp/VisualizerEngine+Orchestrator.swift`: live stem wiring. Tests: `StemAffinityScoringTests.swift` (5 new), `LiveAdapterTests.swift` (+3 cooldown tests), `GoldenSessionTests.swift` (sequences regenerated), `PresetScorerTests.swift` (assertion updated).

---

## D-092 — V.7.7B Arachne staged WORLD + WEB port (filed 2026-05-07)

**Context.** V.7.7A migrated Arachne onto the V.ENGINE.1 staged-composition scaffold but shipped placeholder fragments (vertical gradient + 12-spoke + concentric-ring overlay) and silently dropped the binding for the per-preset fragment buffers (`ArachneWebGPU` at slot 6, `ArachneSpiderGPU` at slot 7) that the legacy mv_warp / direct paths relied on. The V.7.7-redo six-layer `drawWorld()` and the V.7.8 chord-segment `arachneEvalWeb()` survived in the source file as dead reference code attached to the retired `arachne_fragment`. V.7.7B's job was a mechanical port — promote the dead code into the dispatched path; do not write new shader content.

**Decision 1: bind `directPresetFragmentBuffer` / `…Buffer2` at slots 6 / 7 in the staged dispatch.** `RenderPipeline+Staged.encodeStage` now consults the same `directPresetFragmentBufferLock`-guarded fields the legacy `RenderPipeline+MVWarp.drawWithMVWarp` consults (`PhospheneEngine/Sources/Renderer/RenderPipeline+MVWarp.swift:350`). Bound per-frame uniformly across every stage of a staged preset — both WORLD and COMPOSITE see the same `ArachneState` snapshot, so any sampling decision in COMPOSITE is consistent with what WORLD rendered. The harness mirror (`PresetVisualReviewTests.encodeStagePass`) accepts an optional `arachneState:` parameter and binds the same slots when non-nil; "Staged Sandbox" passes nil. Engine `encodeStage` was promoted from `private` to `internal` solely as a test seam (`StagedPresetBufferBindingTests` drives it directly without an `MTKView`).

**Why slot 6/7 instead of new slots.** Reusing the existing setter API (`setDirectPresetFragmentBuffer`, `setDirectPresetFragmentBuffer2`) lets the same `ArachneState` allocation flow through every dispatch path the engine supports — mv_warp, direct, and now staged. New per-preset buffers must use slots ≥ 8 (or extend `RenderPipeline` with `directPresetFragmentBuffer3` / `4`); never overload 6 / 7 for a different purpose. CLAUDE.md §GPU Contract Details / Buffer Binding Layout reserves them.

**Decision 2: reuse `drawWorld()` and `arachneEvalWeb()` as free functions across legacy + staged paths rather than fork them.** Both were already free `static` functions in `Arachne.metal`; the staged WORLD and COMPOSITE fragments call into them as-is. No edits to either. Forking would have doubled the maintenance surface for any future tuning (silk material polish, drop refraction, gravity sag). The free-function shape costs nothing — Metal inlines them at compile time.

**Decision 3: delete the legacy `arachne_fragment` (and the V.7.7A placeholder fragments) after the port.** The legacy fragment body becomes the new `arachne_composite_fragment` with two changes only: (a) signature replaces `[[buffer(1)]] fft` + `[[buffer(2)]] wave` with `texture2d<float, access::sample> worldTex [[texture(13)]]` (those FFT / waveform buffers were accepted but never read in the legacy fragment); (b) `bgColor = drawWorld(uv, moodRow, moodRow.z)` becomes `bgColor = worldTex.sample(arachne_world_sampler, uv).rgb` so COMPOSITE samples the WORLD stage's offscreen output instead of recomputing the forest inline. Every other line is byte-identical to the retired fragment — the V.7.5 v5 web walk + drop accumulator + spider silhouette + mist + dust motes blocks pass through unchanged. Net file shrink: 962 → 898 LOC. (The prompt estimated 480; the estimate assumed completely fresh hand-written staged fragments rather than mechanical lift, and the COMPOSITE body is unavoidably ~240 lines because the V.7.5 anchor + pool web walk + drop material + spider + post-process layers are all real.)

**Decision 4: app-layer `case .staged:` allocates `ArachneState` and wires the slot-6/7 buffers.** The prompt's STOP CONDITION #2 anticipated this — V.7.7A's migration removed the `desc.name == "Arachne"` block from the staged branch in `VisualizerEngine+Presets.applyPreset`, so the engine binding fix alone would have read silently-zero buffers at runtime. The block now mirrors the mv_warp branch above it: `ArachneState(device: context.device)` → `setDirectPresetFragmentBuffer(state.webBuffer)` (slot 6) → `setDirectPresetFragmentBuffer2(state.spiderBuffer)` (slot 7) → `setMeshPresetTick { … state.tick(...) }`. The shared cleanup at the top of `applyPreset` already nils `arachneState` and detaches both buffers, so preset switches stay clean.

**Why the prompt's spec was an under-spec.** The prompt's SCOPE listed the four sub-items inside `Sources/Renderer/RenderPipeline+Staged.swift`, the harness, and `Arachne.metal`, but did not call out the `case .staged:` app-layer change — the prompt's STOP CONDITION #2 documented the scenario as a contingent diagnosis ("If the buffer is unbound, … V.7.7A may have stopped calling `setDirectPresetFragmentBuffer()` for staged presets"). It had stopped, so the wiring landed alongside the shader port in Commit 2 to keep the runtime functional from the moment the new fragments shipped.

**Failed Approach motivation.** Failed Approach #49 ("constant-tuning on a renderer structurally missing compositing layers") is the architectural reason V.7.7A → V.7.7B exists: V.7.5 spent six commits tweaking constants on a 2D fragment that lacked the references' compositing layers; the staged scaffold *is* the unwound version, and V.7.7B is the mechanical step that drops the V.7.5 v5 visual baseline back onto it. Future tuning (refractive drops, biology-correct build) lands on the staged scaffold in V.7.7C / V.7.7D, not by re-working the legacy fragment.

**Verification.** `swift test --package-path PhospheneEngine --filter "StagedComposition|StagedPresetBufferBinding|PresetRegression|ArachneSpiderRender|ArachneState"` — 5 suites green. `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "renderStagedPresetPerStage"` — Arachne WORLD + COMPOSITE PNGs land at non-placeholder size (377 KB / 1.16 MB). `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` — clean. `swiftlint lint --strict` — 0 violations on touched files. Golden hashes regenerated: Arachne `0xC6168E8F87868C80` across all three fixtures (regression renders COMPOSITE with `worldTex` unbound → foreground over zero backdrop), Spider forced `0x461E3E1F07870C00`, "Staged Sandbox" added at `0x000022160A162A00`. Pre-existing `ProgressiveReadinessTests` flakes under full-suite parallel @MainActor load (already documented in CLAUDE.md) trip independently of this increment.

**Files changed (commit 1 — engine + harness binding):**
- `PhospheneEngine/Sources/Renderer/RenderPipeline+Staged.swift` — `encodeStage` reads slots 6/7; visibility `private` → `internal` (test seam).
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetVisualReviewTests.swift` — `encodeStagePass` + `renderStagedFrame` accept optional `ArachneState`; `renderStagedPresetPerStage` constructs warmed state for Arachne.
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/StagedPresetBufferBindingTests.swift` (new) — synthetic shader sentinel test, slot 6 + slot 7.

**Files changed (commit 2 — shader port + app wiring + golden hashes):**
- `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` — `arachne_world_fragment` + `arachne_composite_fragment` ported; legacy `arachne_fragment` and V.7.7A placeholder block deleted; 962 → 898 LOC.
- `PhospheneApp/VisualizerEngine+Presets.swift` — `case .staged:` allocates `ArachneState` and binds slots 6/7 + tick (mirrors mv_warp branch).
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift` — Arachne hash + "Staged Sandbox" hash regenerated.
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift` — spider forced hash regenerated, comment updated.
- `docs/ENGINEERING_PLAN.md` — V.7.7B section flipped to ✅; carry-forward chain (V.7.7C / V.7.7D / V.7.10) restated.
- `docs/DECISIONS.md` — this entry.
- `docs/RELEASE_NOTES_DEV.md` — V.7.7B entry.
- `CLAUDE.md` — Module Map, GPU Contract / Buffer Binding Layout, What NOT To Do, Recent landed work.

**Test count delta:** +2 new tests (`StagedPresetBufferBindingTests`).

## D-097 — Particle preset architecture: siblings, not subclasses (Increment DM.0, filed 2026-05-08)

**Status:** Accepted 2026-05-08.

**Context.** Drift Motes (DM.1) was scoped against the assumption that Murmuration's `Particles.metal` + `ProceduralGeometry` constituted reusable particle infrastructure for the `["feedback", "particles"]` pass set. Implementation discovered they're a single-tenant Murmuration implementation: `ProceduralGeometry` looks up the `particle_update` / `particle_vertex` / `particle_fragment` MSL functions by name (no per-preset override mechanism); `VisualizerEngine.makeParticleGeometry` constructs a single instance with Murmuration-tuned config (5000 particles, decay rate 0, drag 0.8); `Particles.metal`'s fragment shader hardcodes the bird-silhouette colour `(0.02, 0.02, 0.03)`. Plugging Drift Motes into this dispatch would render Murmuration's flock kernel over Drift Motes' sky backdrop — the literal Failed Approach #1 ("Murmuration v2") called out in `DRIFT_MOTES_DESIGN.md §6`.

**Two paths considered.**

(a) **Parameterized common pipeline.** Extend `ProceduralGeometry` to accept per-preset kernel names and a richer `ParticleConfiguration` (kernel-name, vertex-name, fragment-name, recycle bounds, emission rules, hue-baking strategy, decay semantics, drag, …). Murmuration and Drift Motes would both flow through this single class.

(b) **Sibling conformers via protocol.** Introduce a minimal `ParticleGeometry` protocol (compute dispatch, render dispatch, governor gate). `ProceduralGeometry` conforms without behavior change. Drift Motes ships its own conformer in DM.1; future particle presets do the same. The render pipeline schedules dispatch through the protocol; preset-specific concerns (kernel names, particle count, sprite shape, hue-baking, recycle bounds) live inside each conformer.

**Decision: (b).** Murmuration and Drift Motes are different enough that parameterizing one pipeline to host both bloats the configuration interface with a union of disjoint concepts — Murmuration's homePos generation, decay-rate-0 persistence, drum-driven turning waves vs. Drift Motes' recycle bounds, emission position derivation, per-emission hue baking from `vocalsPitchHz`. Future particle presets (snowfall, sparks, rain, wave spray, dust storms — each plausible) would each add another disjoint concern, producing a configuration interface that no single preset uses fully and every preset has to defend itself against. Protocol-based conformance lets each preset express itself cleanly while sharing only what genuinely is shared (the `Particle` struct memory layout — 64 bytes, `packed_float4 color` — and the buffer-then-dispatch convention).

**What was rejected: parameterized common pipeline.** The configuration surface required to express both Murmuration and Drift Motes is large and would only grow with future particle presets. "Siblings, not subclasses" generalizes correctly; parameterized common pipeline does not. Subclassing-style parameterization also forces shared lifecycle assumptions (single instance, app-lifetime persistence, per-preset reset semantics) that are accidental to Murmuration today and may not hold for future presets — better to leave each conformer to manage its own lifecycle.

**Surface.** `ParticleGeometry` is `AnyObject, Sendable` with three members: `update(features:stemFeatures:commandBuffer:)` for the per-frame compute dispatch, `render(encoder:features:)` for the per-frame render dispatch, and `activeParticleFraction: Float { get set }` for the D-057 frame-budget governor gate. The protocol does not expose buffer or pipeline state — encapsulation is the point; the engine schedules through methods, not buffer access. The protocol is not generic over particle type (the `Particle` struct is fixed and shared across all conformers).

**Engine wiring.** `RenderPipeline.particleGeometry` is `(any ParticleGeometry)?`. `RenderPipeline.setParticleGeometry(_:)` accepts any conformer. `FeedbackDrawContext.particles`, `drawDirect(...)` and `drawParticleMode(...)` parameter types are widened identically. `VisualizerEngine.makeParticleGeometry` returns `(any ParticleGeometry)?`. The dispatch sites (`particles?.update(...)`, `particles?.render(...)`, `particleGeometry?.activeParticleFraction = ...`) are byte-identical; only the static type changes. Murmuration is the only conformer at end of DM.0.

**Verification.** `PresetRegressionTests` passes with all 14 presets × 3 fixtures green — Murmuration's dHash is bit-identical pre- and post-DM.0. `xcodebuild -scheme PhospheneApp build` succeeds. Engine sources contain zero remaining `ProceduralGeometry` concrete-type references outside `Geometry/ProceduralGeometry.swift` and doc-comments (verified by `grep -rn ProceduralGeometry PhospheneEngine/Sources/`). `Particles.metal` and the `Particle` struct memory layout are byte-identical across the increment.

**What DM.1 picks up.** Drift Motes ships a `DriftMotesGeometry: ParticleGeometry` conformer with its own particle buffer, `motes_update` compute kernel, `motes_vertex` / `motes_fragment` render functions, recycle-bounds + emission-position derivation, and (in Session 2) per-particle hue baking from `vocalsPitchHz`. `VisualizerEngine.makeParticleGeometry` gains a Drift Motes branch alongside the existing Murmuration branch — a small, focused factory addition rather than a parameterization of shared infrastructure.

## D-099 — Engine MSL `FeatureVector` / `StemFeatures` extended to match preset preamble (Increment DM.2, filed 2026-05-08)

**Decision.** `PhospheneEngine/Sources/Renderer/Shaders/Common.metal` now declares `FeatureVector` at 192 bytes / 48 floats and `StemFeatures` at 256 bytes / 64 floats — byte-identical to the layouts in `PresetLoader+Preamble.swift`. Pre-DM.2, both engine MSL structs were stuck at the pre-MV-1 / pre-MV-3 sizes (32 floats / 128 bytes and 16 floats / 64 bytes respectively), even though the Swift sources of truth (`AudioFeatures+Analyzed.swift` and `StemFeatures.swift`) had been at the larger sizes since MV-1 / MV-3.

**Context.** DM.2 Task 1 specifies that `motes_update` (engine library) reads `f.mid_att_rel` (FV float 32 = byte offset 128) for the cold-stems hue-shift fallback and `stems.vocals_pitch_hz` / `stems.vocals_pitch_confidence` (StemFeatures floats 41–42 = byte offset 160–164) for the warm-stems pitch hue. With the pre-DM.2 engine MSL layouts, neither field was readable — the kernel could only see the first 32 / 16 floats. The Swift binding always uploads the full `MemoryLayout<…>.stride` (192 / 256 bytes) so the trailing fields were on the device but unreachable from the engine kernels.

**Two paths considered.**

(a) **Extend the engine MSL struct definitions to match the preset preamble.** Pure additive change — first 32 / 16 floats keep their original offsets, new fields appear after. Murmuration's `particle_update`, MVWarp's vertex/fragment, and `feedback_warp_fragment` all read only fields in the original tail, so their byte access is unchanged.

(b) **Pass `mid_att_rel` and `vocals_pitch_hz` through `DriftMotesConfig` (buffer 4) as Swift-prepared floats.** Avoids touching `Common.metal` but conflates "kernel tuning constants" (the existing `DriftMotesConfig` content) with "per-frame audio drivers" (a categorically different concern), and requires the Swift side to reach into `latestFeatures` / `latestStems` to denormalise the per-frame values.

**Decision: (a).** The engine MSL has been a layout liar since MV-1 / MV-3 landed — every engine-library shader was working from a smaller view of the same buffer than presets see. Correcting it is a one-time additive change that preserves byte-identical reads for every existing consumer (verified by golden-hash regression: Murmuration's `0x07449B6727773FF8`/`0x0B449A4727373FF8`/`0x0744936727773FF8` and every other preset's hashes are unchanged). Path (b) would have wedged the audio-coupling concern into a config buffer that exists for kernel tuning constants, and would have had to be reverted later when DM.3's drum dispersion shock wants to read `stems.drums_beat` / `stems.drums_energy_dev` from the same kernel.

**What was rejected.** Adding a third "audio passthrough" buffer slot for engine kernels — would have created a third copy of the same data already in buffers 1 and 3, and added a Swift-side denormalisation step every frame.

**Murmuration invariant preserved.** All 15 preset golden hashes regenerated identically to the post-DM.1 baseline (`UPDATE_GOLDEN_SNAPSHOTS=1` run produced byte-identical output for every preset other than Drift Motes). `Particles.metal`, `ProceduralGeometry.swift`, `ParticleGeometry.swift`, and `RenderPipeline*.swift` are byte-identical to their post-DM.1 state — Common.metal is not in the prompt's "byte-identical to DM.1" invariant list, and the change is purely a struct-extension correction.

**Carry-forward.** Engine library shaders can now read the full FV / StemFeatures surface. DM.3 will use this for emission-rate scaling (`f.mid_att_rel`) and drum dispersion shock (`stems.drums_beat`, `stems.drums_energy_dev`) without further struct edits. Future `Particles*` engine kernels also benefit — MV-1 deviation primitives, MV-3a per-stem rich metadata, and MV-3b beat phase are now in scope.

**Note:** V.7.7C.5 (WORLD-reframe) reserved D-099 in spec text with an "or next-available ID" escape clause. DM.2 filed first; V.7.7C.5 lands as D-100.

## D-101 — `stems.drums_beat` as the canonical particles-family beat reactivity field (Increment DM.3, filed 2026-05-08)

**Decision.** Particles-family presets that need a per-frame "beat just hit" signal route to `stems.drums_beat` (the BeatDetector envelope on the drums stem, gated by `smoothstep(0.30, 0.70, stems.drums_beat)` for clean event detection) rather than `stems.drums_energy_dev` (the AGC-deviation primitive). `stems.drums_energy_dev` remains available for continuous proportional accents — when "more drums than the AGC running average" is the right semantic — but the canonical event field for kick-driven impulses is `drums_beat`.

**Context.** DM.1's carry-forward block named `stems.drums_energy_dev` as the dispersion-shock driver. DM.2's carry-forward block silently corrected this to `stems.drums_beat` with no explanation. DM.3 ships dispersion shock against `drums_beat` per the corrected guidance. This entry records the rationale so the next particles-family preset doesn't relitigate it.

**Why `drums_beat`, not `drums_energy_dev`.**

- **`drums_beat` is event-shaped.** The BeatDetector emits a triangular envelope rising on onset and decaying over ~200 ms via `pow(0.6813, 30/fps)`. Smoothstepping against (0.30, 0.70) gives a clean "this frame is part of a beat impulse" gate that fires for a bounded number of frames per event.
- **`drums_energy_dev` is continuous-shaped.** `(drumsEnergy − EMA) × 2.0` clamped to non-negative reads as "more drums than running average" — useful for sustained percussion intensity (e.g. a hi-hat-heavy section) but not for picking out individual kicks. Smoothstepping against it produces a duty-cycle proportional to onset density, not a pulse per onset.
- **VolumetricLithograph precedent (D-026 Note).** `smoothstep(0.30, 0.70, stems.drums_beat)` is already the canonical gate for "drum onset accent" in `VolumetricLithograph.metal`. The dispersion shock in `motes_update` reuses the exact same form for the same semantic.
- **Absolute-threshold smoothstep is D-026-allowed on stem onset signals.** D-026 targets *FeatureVector raw bands* (`f.bass`, `f.mid`, `f.treb`) where AGC normalisation makes absolute thresholds non-portable across tracks and within-track sections. `stems.drums_beat` is post-onset-detection, post-cooldown, in event coordinates — a 0.30 threshold means "this is in the rising half of the envelope," which is the same musical event regardless of AGC state. The deviation-primitive rule does not extend to envelopes that are already event-coordinate by construction.

**What was rejected.**

- **Reading `stems.drums_beat > some_value` directly** without the smoothstep — works but produces ratchet motion (the impulse magnitude jumps from 0 to gain at threshold, with no rising edge). The smoothstep gives a smoother visual onset that matches the envelope's natural shape.
- **Routing to `f.beat_bass` or `f.beat_composite`** (FV onsets) — these are the pre-stem-separation onset signals and bias toward whatever instrument carries the lowest energy in the kick range. `stems.drums_beat` benefits from the stem separation pass already isolating the drum content. For particles-family presets that have access to `stems`, the stem-isolated signal is the right choice.

**Murmuration relationship.** Murmuration's `particle_update` already reads `stems.drums_beat` via the D-019 stem-warmup blend (`mix(fm_beat, stems.drums_beat, stemBlend)`). DM.3's dispersion shock follows the same route in `motes_update`, but unblended — the dispersion shock fires only when stems are warm enough for the smoothstep gate to trip, so a D-019 blend is redundant (cold stems = `drums_beat = 0` = no dispersion).

**Carry-forward.** Future particles-family presets needing a "kick-driven impulse" should route to `stems.drums_beat` with the canonical `smoothstep(0.30, 0.70, ...)` gate. `stems.drums_energy_dev` remains the right choice for continuous percussion-intensity drivers (e.g. flock-density modulation by sustained percussion).

## D-LM-buffer-slot-8 — Fragment buffer slot 8 reservation for per-preset CPU-driven state (Increment LM.0, filed 2026-05-08)

**Status.** Accepted.

**Decision.** Reserve fragment buffer slot 8 as a third per-preset CPU-driven state buffer, alongside the existing slots 6 and 7. New `RenderPipeline.directPresetFragmentBuffer3` storage + `setDirectPresetFragmentBuffer3(_:)` setter mirror the slot 6 / 7 setter pattern exactly. Bound at fragment slot 8 in every per-frame uniform binding site that already binds slots 6 / 7 (staged composition, mv_warp scene-to-texture) **plus** the direct-pass (`drawDirect`) and the ray-march **lighting** pass (`RayMarchPipeline.runLightingPass`). The G-buffer pass (`RayMarchPipeline.runGBufferPass`) intentionally does NOT bind slot 8 — only lighting consumes it today.

**Context.** Phase LM (Lumen Mosaic) is the first preset to need a third per-preset state buffer beyond what slots 6 (`ArachneState.webBuffer` / `GossamerState.wavePool`) and 7 (`ArachneState.spiderBuffer`) already reserve. Lumen Mosaic's planned `LumenPatternState` (336 B — 4 light agents + 4 patterns + small scalars per `Lumen_Mosaic_Rendering_Architecture_Contract.md` §"Required uniforms / buffers") encodes per-frame CPU-driven state that the fragment shader reads to compute analytic backlight emission per Voronoi cell. The rendering contract calls out slot 8 explicitly (Decision F.1: "Bind at slot 8 in the same per-frame uniform contract as slots 6 and 7").

LM.0 is pure infrastructure; no shader code lands in this increment. The slot is wired so LM.1 (the first Lumen Mosaic shader) can bind state via the new setter and the lighting fragment can read `LumenPatternState` directly.

**Why slot 8, not a different mechanism.**

- **Mirrors the slot 6 / 7 contract.** Slots 6 and 7 are already the documented "per-preset fragment buffer #1 / #2" reservations (CLAUDE.md GPU Contract). Adding slot 8 as "per-preset fragment buffer #3" extends the same idiom with no new abstraction. Future authors who already know how to use slot 6 / 7 immediately know how to use slot 8.
- **Shared resource, first consumer is Lumen Mosaic.** The slot is not Lumen-Mosaic-specific. Any future preset that needs a third per-frame state buffer binds via `setDirectPresetFragmentBuffer3`. Lumen Mosaic is the first consumer because it is the first preset to outgrow slots 6 / 7.
- **No struct extensions to `Common.metal`.** Extending `FeatureVector` or `StemFeatures` to carry the new state would force a byte-layout migration (cf. D-099) and pay a regression cost on every preset's golden hash. A dedicated slot is cheaper and additive.
- **Per-frame uniform binding contract is uniform across stages.** Same rule as slots 6 / 7: in staged-composition presets, slot 8 is bound at every stage of the staged dispatch (WORLD, COMPOSITE, etc.) — both stages see the same snapshot. This avoids state divergence across stages.

**Why the G-buffer pass is excluded from slot 8 binding.**

Lumen Mosaic's pattern state is consumed by the lighting fragment (per Decision F.1: emission-dominated path with Option α — lighting pass multiplies albedo by emission gain when matID == 1). The G-buffer pass writes albedo / depth / normal / matID and does not need the pattern state. Excluding the G-buffer pass keeps that pass's binding surface stable and minimises the chance of slot 8 leaking into shaders that don't need it. If a future preset turns out to need slot 8 in the G-buffer pass, that is an additive change to `RayMarchPipeline+Passes.swift`'s `runGBufferPass` (and a follow-up entry to this decision).

**What was rejected.**

- **Extending `FeatureVector` or `StemFeatures` with the new fields.** Forces a byte-layout migration (cf. D-099) and regenerates every preset's golden hash. A dedicated slot is cheaper and additive.
- **A new G-buffer channel for emission state.** Per the rendering contract (§sceneSDF/sceneMaterial Option β), this is heavier infrastructure work and unnecessary while Option α (matID == 1 emission gain) holds.
- **Binding at a higher slot index (e.g. 16+) to leave headroom.** Slot 8 is the next contiguous slot after 6 / 7 and pre-noise textures (4–8). The TextureManager binds noise *textures* at slots 4–8, not buffers — Metal's buffer and texture argument-binding spaces are independent. Slot 8 in the buffer space is free.
- **Making slot 8 ray-march-only.** The prompt initially considered this fallback. Mirroring the slot 6 / 7 contract (staged + mv_warp + direct + ray-march lighting) keeps a future direct-pass-only preset that needs a third state buffer eligible without further engine changes.

**Rule.** Future presets that need a third per-frame state buffer bind via `setDirectPresetFragmentBuffer3(_:)` and read at fragment slot 8. **Do not** overload slots 6 / 7 / 8 for a different purpose; if a fourth state buffer becomes necessary, extend `RenderPipeline` with `directPresetFragmentBuffer4` / `5` and document the slot in CLAUDE.md GPU Contract. The G-buffer pass binding remains stable; only the lighting pass plus the staged / mv_warp / direct paths bind slot 8.

**Carry-forward.** LM.1 implements `LumenPatternEngine` (CPU-side state + setter call) + `LumenMosaic.metal` (lighting fragment reads `LumenPatternState` at `[[buffer(8)]]`). No further engine changes expected for Lumen Mosaic; if LM.5 promotes silhouette occluder masks per Decision B.2 they ride the same slot or a future slot 9 — to be filed at LM.5 if needed.

---


> **Phase MD bloc (D-103 → D-122) — REVISIT banner (planned at DOC.0 2026-05-13, landed at DOC.4 2026-06-11).**
> Twenty strategy decisions filed in one day (2026-05-12) without empirical input from the work they govern; ten were amended same-day, D-120 was reverted within 24 h (now in `DECISIONS_HISTORY.md`; lessons = CLAUDE.md Failed Approaches #59/#60). Since filing, the empirical evidence the bloc lacked has arrived: Dragon Bloom (D-137/D-138) and Fata Morgana (D-139) shipped + certified as faithful-port uplifts, and four Phosphene-original presets certified (Nimbus, Murmuration, Skein, Ferrofluid Ocean). Treat each D-1xx entry below as a forecast pending re-derivation against that evidence; the bloc re-evaluation belongs to the next Phase MD planning session, not to a pruning pass.

*(RB.2-2, 2026-06-11: the unexecuted Phase-MD planning subset — D-103–D-110, D-112, D-115–D-118 — moved to `DECISIONS_HISTORY.md`; the banner below now covers the surviving posture/legal commitments: D-111, D-113, D-114, D-119, D-121, D-122.)*

## D-111 — Phase MD license posture: MIT-derivative with provenance + attribution + takedown (Strategy Decision I, filed 2026-05-12; amended 2026-05-12 to remove counsel-review gating; amended 2026-05-12 — inspired-by reframe revises attribution schema, retires notification protocol)

**Rule.** Transpiled Milkdrop-origin presets ship under Phosphene's MIT licence, with provenance metadata + attribution per the following protocol:

1. Each transpiled preset's JSON sidecar carries a `milkdrop_source` block:
   ```json
   "milkdrop_source": {
     "filename": "<original .milk filename>",
     "author": "<author from filename pattern, best-effort>",
     "theme": "<cream-of-crop theme directory>",
     "sha256": "<SHA256 of source .milk file>",
     "pack": "projectM-visualizer/presets-cream-of-the-crop"
   }
   ```
2. `docs/CREDITS.md` carries a "Milkdrop preset attribution" section enumerating every shipped preset's source. Pattern mirrors the existing Open-Unmix HQ and Beat This! ML weight attributions.
3. Phosphene commits to honoring takedown requests routed through the projectM team (per the pack's stated takedown path).

**Risk-acceptance (amendment 2026-05-12).** Matt as project lead accepts residual legal risk on the basis of (a) the pack's two-decade public posture and four years as projectM's default with no significant copyright dispute on record, (b) the bounded downside (worst plausible outcome is takedown → preset removed from next release), and (c) Phosphene's good-faith provenance + attribution + takedown protocol. **Phase MD work is NOT gated on counsel review.** Counsel review remains available as optional asynchronous due-diligence — the `docs/MILKDROP_COUNSEL_BRIEF.md` artifact stays in tree as the outgoing-communication brief — but is not a precondition for any Phase MD increment. The risk-acceptance is contingent on the scope conditions documented in the brief (no `.milk` file redistribution, no commercialization, no claim of original authorship); a material scope change reopens the question.

**Why.** The cream-of-crop pack's curator (ISOSCELES) asserts public-domain-by-convention with a projectM-managed takedown path. The pack has been the default for projectM releases since 2022 with no significant copyright dispute on record. The CREDITS.md attribution pattern is the natural template (Open-Unmix HQ, Beat This! ML weights already follow it). Counsel review as a *gating* mechanism trades a small additional reduction in residual risk for an unbounded delay to development; the project's posture (per Matt 2026-05-12) is that the residual risk does not warrant the gate.

**Carry-forward.** `docs/CREDITS.md` "Milkdrop preset attribution" section exists as a placeholder; populated when MD.5 ships its first port. Counsel review remains available at Matt's discretion; the brief stays in tree as historical context. **Note: D-111 is one of the decisions slated for substantive revision in the upcoming inspired-by reframe addendum (see `prompts/MD-strategy-addendum-prompt.md`); the addendum may further refine the attribution + provenance schema under the inspired-by framing.**

**Amendment 2026-05-12 (inspired-by reframe — attribution schema renamed; notification protocol retired).** Under the inspired-by reframe (D-113 / `MILKDROP_STRATEGY.md` §12), the operative legal framing is "inspired by," not "derivative of." Each Milkdrop-inspired Phosphene preset's JSON sidecar carries an `inspired_by` block in place of `milkdrop_source`:

```json
"inspired_by": {
  "milkdrop_filename": "<original .milk filename>",
  "original_artist": "<author from filename pattern, best-effort>",
  "pack": "projectM-visualizer/presets-cream-of-the-crop",
  "sha256": "<SHA256 of source .milk file>"
}
```

The `theme` field is dropped (no longer load-bearing once tier assignment retires per D-103 amendment). `CREDITS.md` section is renamed to "Milkdrop-inspired preset attribution" and populated as inspired-by uplifts ship. The provenance + attribution + takedown protocol (CREDITS.md enumeration + projectM-routed takedown) stays in force as the MIT licence's responsibility-of-the-redistributor posture, contingent on the scope conditions in the brief (no `.milk` redistribution, no commercialization, no claim of original authorship). The **pre-release notification protocol** (notifying original Milkdrop preset authors of each Phosphene port before public release) is **retired for the pre-community phase** per D-113 / `MILKDROP_STRATEGY.md` §12.8 — rationale: until preset development opens to community contributors, all uplifts are authored by Matt + Claude Code, and notification before community-authoring infrastructure exists is a checkbox exercise. Trigger to reopen: when Phosphene opens preset development to community contributors. The inspired-by framing materially reduces the substantive-similarity surface compared to a port, but the discipline rule (D-116 / `SHADER_CRAFT.md §12.6`) is the load-bearing authoring-time constraint that operationalizes the framing.

---

## D-113 — Phase MD posture reframe: inspired-by, not derivative-of (Strategy Addendum, filed 2026-05-12)

**Rule.** The operative legal and creative framing for Phase MD is **"inspired by,"** not "derivative of." Every Milkdrop-influenced Phosphene preset is a **new creation** that takes inspiration from a source preset's concept and aesthetic, implemented from scratch on Phosphene's primitives. The transpiler / mechanical-port framing committed to under the base strategy (`docs/MILKDROP_STRATEGY.md` §§1–11) is retired.

The reframe is operative on three axes:

1. **Legal posture.** Phosphene asserts externally that its Milkdrop-influenced presets are inspired-by works, not derivatives. The CREDITS.md attribution stays (renamed to "Milkdrop-inspired preset attribution"); the substantial-similarity discipline rule (D-116 / `SHADER_CRAFT.md §12.6`) becomes the load-bearing authoring-time constraint.
2. **Scale.** Initial planning target widens from ~35 presets (base strategy §5) to **~200 inspired-by uplifts**. At ~2–3 days per preset to certification, this is a multi-year work stream, not a finite phase.
3. **Release model.** Phosphene's first release ships at **20 presets** total (D-114).

**Why.** Matt's 2026-05-12 post-sign-off review of the base strategy reframed the work after recognizing that the derivative-port model (a) over-stated Phosphene's substantive overlap with source presets (Phosphene presets are authored on different primitives — mv_warp + ray_march + V.1–V.4 utilities + MV-3 capabilities — and read as Phosphene works that *honor* source concepts, not as Milkdrop ports with a Phosphene frontend), (b) created an authoring tax (transpiler authoring + per-preset D-026 audit + tier-stratified rubric application) that did not match the actual per-preset session shape, and (c) limited the catalog ceiling artificially (35 presets cap was a transpiler-budgeting artifact; the inspired-by framing has no such cap).

**Notification protocol — retired for pre-community phase.** The base strategy's I.1 license posture committed to projectM-routed takedown but did not commit to a pre-release notification protocol; iterative discussion had suggested one. Under the inspired-by reframe, **notification protocol is retired** until Phosphene opens preset development to community contributors. Rationale: until then, all uplifts are authored by Matt + Claude Code, and notification before community-authoring infrastructure exists is a checkbox exercise. Trigger to reopen: community-contribution rollout (separate phase, separate prompt). See `MILKDROP_STRATEGY.md` §12.8.

**Carry-forward.** Drives the amendments on D-103 (single tier), D-105 (single `family` value), D-106 (single Settings toggle), D-110 (transpiler retired), D-111 (`inspired_by` schema + notification deferral), D-112 (HLSL-free constraint dissolves). Drives the new decisions D-114 (release model), D-115 (release-bundle composition), D-116 (discipline rule), D-117 (catalog-ratio framing), D-118 (read-only analysis tool scope). See `docs/MILKDROP_STRATEGY.md` §12 for the full addendum.

---

## D-114 — Phase MD release model: 20-preset first-release bundle (Strategy Addendum, filed 2026-05-12)

**Rule.** Phosphene's first public release ships when the production catalog reaches **20 M7-certified presets** (full V.6 rubric, `rubric_profile` matched per preset). The 20 are a mix of Phosphene-native + Milkdrop-inspired (composition per D-115). After first release, ongoing uplift batches ship at a cadence to be set by release planning (weekly / monthly / quarterly — separate decision, not in this addendum).

**Why.** 20 is the minimum bundle size at which:

1. A 60–90 minute listening session can rotate presets without repetition fatigue (the Phase 4 family-repeat penalty + 50-preset history window already handle within-bundle rotation, but 20 is the floor that makes the rotation feel varied).
2. Every preset in the bundle can clear M7 review in a feasible work window (with ~14 Phosphene-native presets already authored and ~10 inspired-by uplifts targeted, the gap to 20 is bounded).
3. The catalog presents a coherent product, not a tech demo (1 certified preset, Lumen Mosaic alone, is below the product threshold).

**Current state vs threshold (2026-05-12):**

- **Certified (1):** Lumen Mosaic (cert flipped at LM.7, 2026-05-12).
- **Production-but-not-all-certified (~12):** Arachne, Aurora Veil (pending Phase AV), Fractal Tree, Gossamer, Murmuration, Nebula, Plasma, Spectral Cartograph (diagnostic — excluded from auto-selection per D-074), Stalker, Starburst, Volumetric Lithograph, Waveform. Each is one M7 + cert review away from the bundle. (Glass Brutalist retired GBRETIRE.1 / D-186 — its D-020 permanence constraint blocked the instrument-as-hero role. Kinetic Sculpture retired KSRETIRE.1 / D-188 — never found the right direction across multiple redesigns.)
- **Gap to 20:** 6+ presets, source TBD per D-115.

**Carry-forward.** Drives the work-prioritization shape over the next several months: Phase G-uplift (cert reviews on the ~14 production-but-not-certified members) + Phase AV / Phase CC + the first inspired-by uplift batch (initial seed list per D-112 amendment). Post-release cadence decision lives in a future release-planning prompt; D-114 covers only the bundle threshold, not the rhythm after.

---

## D-119 — Phosphene product brand identity: Milkdrop-influenced modern platform (Strategy Addendum follow-up, filed 2026-05-12)

**Rule.** Phosphene's product identity is **"Milkdrop-influenced modern platform"** — a music-visualization product whose catalog is intentionally majority-Milkdrop-inspired, drawing on the 25-year Milkdrop preset tradition as Phosphene's primary aesthetic well, layered with Phosphene's modern capabilities (stems via Open-Unmix HQ, beat phase via Beat This!, ray-march scenes, `mv_warp` per-vertex feedback, PBR materials, MV-3 audio analysis surface). This is the committed product identity going forward.

**Implications.**

1. **Catalog ratio target (D-117 amendment).** Steady-state catalog ratio is **≥ 50% inspired-by, ~60–70% expected, upper bound ~80%** to preserve Phosphene-native distinctiveness. The "deferred until ~40 presets" framing of the original D-117 retires.
2. **First-release bundle composition (D-115 amendment).** Default recommendation shifts from balanced 10+10 to inspired-by-forward — new default **7+13** (Phosphene-native + Milkdrop-inspired); alternatives 5+15 (bolder) or 10+10 (fallback).
3. **External communication.** When Phosphene marketing copy / repo description / about-screen text gets authored, it names Milkdrop influence explicitly — not as background acknowledgement but as the defining aesthetic choice. The CREDITS.md "Milkdrop-inspired preset attribution" section becomes load-bearing user-facing content, not just a legal footnote.
4. **D-107 brand-fit criterion narrows.** "Brand fit" for ray-march-composing inspired-by uplifts (formerly D-107 Hybrid candidate criteria) is no longer about avoiding overlap with Phosphene-native catalog members — the catalog is meant to be Milkdrop-forward. Brand fit reduces to "does this register expand the Milkdrop-influenced character of the catalog?" with internal-competition concerns retired.

**Why.** Two alternatives were on the table:

- **"Phosphene-native with Milkdrop accents."** Would have required a hard ceiling on inspired-by share (~25%) and aggressive Phase G-uplift / Phase AV / Phase CC throughput to keep parity. Matches the original §3 strategy's implicit framing.
- **"Milkdrop-influenced modern platform."** Committed brand identity. Matches the actual work distribution — Phase MD is the long-tail catalog-growth engine; Phosphene-native phases are the differentiating but slower work stream.

Matt picked the second 2026-05-12 in response to the adversarial review's call for an explicit brand commitment. The pick acknowledges the empirical work distribution and avoids the "catalog accidentally drifts Milkdrop-forward without a brand framing to support it" failure mode the adversarial review flagged.

**Carry-forward.**

- D-115 composition recommendation amended (7+13 default; see D-115 amendment block).
- D-117 catalog-ratio framing amended (target ≥ 50% inspired-by, no longer deferred; see D-117 amendment block).
- Phosphene marketing / About / repo-description copy reflects the framing when authored. None of this exists in the repo yet; flagged for the eventual marketing-copy authoring session.
- D-107 brand-fit criterion narrows per the implication above (no separate amendment block — the criterion was authored under the unstated "Phosphene-native default" assumption; D-119 surfaces the assumption and inverts it).

---

## D-121 — Phase MD visual-divergence rule (Strategy Addendum follow-up, filed 2026-05-12; amends D-116 + SHADER_CRAFT.md §12.6 bullet 3)

**Rule.** D-116 bullet 3 of the substantial-similarity discipline rule (lives in `SHADER_CRAFT.md §12.6`) is rewritten from permissive ("the visual structure may differ from the source") to load-bearing:

> **"3. The Phosphene preset's rendered output MUST differ measurably from the source on at least one of: dominant motion model, palette character, primary feature stack, or compositional structure."**

**M7 review test (mandatory for Milkdrop-inspired presets).** Render the Phosphene preset on a shared test track; render the source `.milk` on the same track in projectM (or comparable Milkdrop-compatible renderer); place renders side-by-side. The M7 reviewer (Matt) writes a one-paragraph divergence rationale in the closeout naming **which axis diverges and how**. A preset that cannot articulate a divergence on at least one of the four axes does **not** certify; the remediation is to rewrite under closer discipline, not to tune (Failed Approach #49 precedent — tuning constants on a structurally broken renderer).

**Why.** The original D-116 bullet 3 was permissive ("may differ"), leaving the rendered-output axis unprotected. Bullets 1 / 2 / 4 enforce code-side similarity (no equations copy-pasted, no shader logic ported line-for-line, no `.milk` redistribution); the rendered-output axis is the more legally significant for copyright in software UI and visual works, but had no enforcing rule. The `inspired_by` provenance block + CREDITS.md attribution establish **knowledge of** and **access to** the source preset — both elements of a substantial-similarity case. Without enforced visual divergence, that documentation increases legal exposure relative to silently shipping aesthetically-similar output. The strengthened bullet 3 + the side-by-side M7 test operationalise the visual axis.

Failed Approach #48 is the precedent at the per-preset level (Arachne V.7 rendered output landed at the named anti-reference `10_anti_neon_stylized_glow.jpg` despite passing the §10.1-faithful authoring path; substantive similarity to the anti-reference was caught at M7 review, not at authoring). D-121's enforcement applies the same lesson at the cross-product level: catch the source-similarity case at M7 review by mandatory side-by-side comparison, not by trusting the code-side discipline to produce visual divergence automatically.

**Carry-forward.**

- `SHADER_CRAFT.md §12.6` bullet 3 + M7 checklist rewritten in the same commit as this decision.
- Phase MD per-preset closeout reports for Milkdrop-inspired uplifts include a divergence rationale citing one of the four axes.
- The rule is reusable for any future reference-anchored authoring outside Phase MD where the same anti-reference convergence risk applies (Failed Approach #48 generalisation). For Phase MD specifically the M7 test is mandatory; for other phases it remains author + reviewer discretion.

---

## D-122 — Phase MD kill-switch / re-evaluation triggers (Strategy Addendum follow-up, filed 2026-05-12)

**Rule.** Phase MD halts and re-evaluates on any of four explicit triggers:

1. **Milestone trigger (heartbeat).** After the **10th inspired-by preset** ships (i.e., immediately after the first-release bundle if 10+ inspired-by are in it), conduct an explicit "Phase MD health check" review covering:
   - Discipline-rule application across the 10 presets (D-116 / D-121).
   - Catalog character against brand commitment (D-119).
   - Orchestrator scheduling on the D-120 property taxonomy — is the family / concept / paradigm-repeat surface producing varied sessions?
   - Any community signal received (takedown, comment, request).

2. **Takedown signal.** First takedown notice or substantive copyright complaint routed through the projectM team or directly to Phosphene. Halt new inspired-by authoring; investigate; respond per D-111 amendment takedown protocol; reopen the legal posture analysis.

3. **Discipline-rule failure.** First M7 review that rejects an inspired-by preset for substantive-similarity reasons (D-116 / D-121 violation). Halt and review whether the discipline rule needs to tighten further (additional bullets, stricter visual-divergence axes, tighter M7 procedure).

4. **Catalog-ratio drift.** Inspired-by share of the production catalog falls below ~50% or rises above ~80% before the second release bundle (or comparable explicit milestone). Review whether the work-distribution model is healthy (Phosphene-native authoring keeping pace; inspired-by authoring not over-running).

**Each trigger produces an explicit review session with documented outcome:** *proceed* (continue Phase MD as-is), *adjust* (revise specific decisions; file amendments), *halt* (suspend Phase MD pending resolution). The outcome lands as a follow-up decision (or amendment to D-119 / D-122) in `docs/DECISIONS.md`.

**Why.** The base strategy had counsel review as a checkpoint at the start of Phase MD (D-111 original I.1 posture). The 2026-05-12 amendment retired the gate (counsel review remained optional async due diligence; not a precondition). D-122 fills the resulting gap — a 200-preset commitment without checkpoints is a multi-year branch with no integration. The four triggers cover the three substantive risk axes (legal, discipline, scale) plus a milestone heartbeat.

The adversarial review's specific framing was: *"What's the trigger to abandon Phase MD entirely?"* D-122 answers that question without requiring Phase MD to fail catastrophically before re-evaluation — the milestone trigger fires whether or not anything is wrong, on the principle that ten presets is the right unit to look back from.

**Carry-forward.**

- ENGINEERING_PLAN.md Phase MD section gets the four triggers documented as gates.
- The MD.6 "long-tail work stream" increment gets the milestone-10 trigger as its first checkpoint.
- D-119 / D-117 / D-116 / D-121 each name D-122 as their explicit re-evaluation surface — a follow-up that violates the rule in any of those decisions fires the discipline-rule-failure trigger.



---

## D-123 — `family` taxonomy aligned to cream-of-crop themes; D-120 metadata superseded (filed 2026-05-13)

**Rule.** Phosphene's `PresetCategory` enum mirrors the cream-of-crop Milkdrop pack's 10 aesthetic theme directories + 1 `transition` slot. Diagnostic presets (`is_diagnostic: true`) carry no `family`; the field is optional on `PresetDescriptor`.

**Final enum (11 cases):**

> `waveform`, `fractal`, `geometric`, `particles`, `hypnotic`, `supernova`, `reaction`, `drawing`, `dancer`, `sparkle`, `transition`

**What changed and why.**

Pre-D-123: `PresetCategory` had 14 cases — 9 cream-of-crop themes + 4 Phosphene-specific additions (`abstract`, `fluid`, `organic`, `instrument`) + 1 unused `transition`. The 5 unused cream-of-crop slots (`supernova`, `reaction`, `drawing`, `dancer`, `transition`) were aspirational for Phase MD.

The 4 Phosphene-specific additions were doing catch-all work:
- `abstract` — 3 presets (Murmuration, Ferrofluid Ocean, Kinetic Sculpture) with nothing visually in common. Classic "didn't know where else to put it" bucket.
- `instrument` — 2 diagnostic presets (Spectral Cartograph, Staged Sandbox). Category error: developer tools shouldn't share an enum with aesthetic content.
- `fluid` — 2 presets (Membrane, Volumetric Lithograph) with limited visual overlap; same-register Milkdrop presets would file under `hypnotic` or `geometric` per cream-of-crop convention, creating permanent label-source inconsistency once Phase MD ingests inspired-by uplifts.
- `organic` — 2 presets (Arachne, Gossamer) with shared concept (web) more than shared visual style.

With Phase MD planning to ingest a large body of inspired-by presets from a pack already organized by cream-of-crop conventions, custom Phosphene categories create permanent label-source inconsistency: identical visual registers get different labels depending on origin. The cream-of-crop taxonomy is battle-tested against ~9,800 presets over 20+ years; the right move is to mirror it exactly and reassign Phosphene-originals into its themes.

**Reassignment of the 15 production presets:**

| Preset | Pre-D-123 | D-123 |
|---|---|---|
| Waveform | waveform | waveform |
| Plasma | hypnotic | hypnotic |
| Nebula | particles | particles |
| Glass Brutalist | geometric | geometric |
| Lumen Mosaic | geometric | geometric |
| Fractal Tree | fractal | fractal |
| Kinetic Sculpture | abstract | **geometric** |
| Murmuration | abstract | **particles** |
| Ferrofluid Ocean | abstract | **geometric** |
| Volumetric Lithograph | fluid | **geometric** |
| Membrane | fluid | **reaction** |
| Arachne | organic | **drawing** |
| Gossamer | organic | **sparkle** |
| Spectral Cartograph | instrument | **(none — diagnostic)** |
| Staged Sandbox | instrument | **(none — diagnostic)** |

The 4 subjective reassignments (Membrane / VL / Ferrofluid Ocean / Gossamer) were Matt's call 2026-05-13. Each had ≥ 2 plausible homes; whichever was picked defines the boundary of that category for future presets.

**Schema change.** `PresetDescriptor.family` becomes `PresetCategory?` (was non-optional with `.waveform` fallback). Missing `family` in JSON now decodes as nil, which is also the correct value for diagnostics. The scorer treats `nil` family as: no family boost, no family-repeat penalty, no fatigue history match — diagnostics are gated upstream by `is_diagnostic` anyway, but the defensive logic is in place for any non-diagnostic preset that ships without a declared family.

**D-120 superseded.** D-120 added `concept_tags` and `motion_paradigm` to enable diversity-scheduling penalties at the orchestrator. The wiring was rejected on the basis that Phosphene's planner is multi-preset-per-song and should pick the best SET of presets per song without "avoid back-to-back same X" penalties (memory: `feedback_multi_preset_per_song.md`). Without the wiring, the labels served only descriptive purposes that overlap with `family` — a single well-chosen label is preferable to three. The 5 D-120 commits (`a2e8a6aa..5f29aefe`) were reverted in `0981ca4f` on the same day they landed.

**Catalog clustering observation.** Post-D-123, **5 of 13 aesthetic presets are in `geometric`** (Glass Brutalist, Kinetic Sculpture, Lumen Mosaic, Volumetric Lithograph, Ferrofluid Ocean). The `GoldenSessionTests` regenerated sequences now show the planner producing same-preset repeats (`Membrane × 3` in Session A) and family-repeat-penalty cascades because the catalog is small relative to the family clustering. This is not a planner bug — it's a real symptom of "we don't have enough viable presets yet" surfaced by the taxonomy cleanup. The fix is more presets, not orchestrator changes (Matt 2026-05-13).

**Carry-forward.**

- No further taxonomy work until the catalog grows substantially (next ~20–30 presets from Phase MD inspired-by + new originals).
- The unused cream-of-crop categories (`supernova`, `dancer`, `transition`) remain reserved for Phase MD uplifts and new originals.
- Phase MD inspired-by uplifts ingest into the matching cream-of-crop category on a 1:1 basis — no translation layer needed.
- `GoldenSessionTests` Session A and Session C expected sequences are now anchored to the D-123 catalog state; future taxonomy changes will require regeneration.

---

## D-127 — §5.8 stage rig retired; aurora reflection retained via direct audio uniforms (V.9 Session 4.5c, 2026-05-14)

**Status:** Accepted (2026-05-14)

### Context

D-125 introduced the `SHADER_CRAFT.md §5.8` stage-rig recipe — 4-6 orbital point lights with per-light palette / intensity / orbital phase, carried via slot-9 fragment buffer + Swift `FerrofluidStageRig` state class. D-126 amended D-125's GPU consumption from Cook-Torrance per-light loop to mirror-reflects-procedural-sky, with `rm_ferrofluidSky` reading the slot-9 buffer's per-light fields as aurora-band parameters. The slot-9 buffer + `FerrofluidStageRig` machinery survived the D-126 amendment.

Matt directed (2026-05-14, this session): "We have already had this conversation about replacing the stage rig with something else. ... The change was from 'stage lighting' to just the aurora reflection." The aurora reflection mechanic (procedural sky overlay the substrate mirror-reflects) stays; the stage-rig framework (orbital lights, slot-9 buffer, `FerrofluidStageRig` class, per-light palette/intensity/phase machinery, JSON `stage_rig` block) is retired.

The discipline failure that preceded this decision is documented inline in the V.9 Session 4.5c prompt under the new "do not assert that a previously-documented mechanism is wired without verifying Matt's current intent" rule. Matt had communicated the deprecation in prior sessions; this session's prompt (V.9 Session 4.5b) preserved the rig in its "what stays unchanged" block; Claude carried the prompt's claim forward without verifying.

### Decisions

**(a) The §5.8 stage rig is removed.** D-125's slot-9 fragment buffer ABI is gone. D-125's `FerrofluidStageRig` Swift class is gone. D-125's `PresetDescriptor.StageRig` decoder and JSON `stage_rig` block are gone. D-125's preamble `StageRigState` MSL struct declarations are gone. The `directPresetFragmentBuffer4` setter on `RenderPipeline` is gone.

**(b) Aurora reflection is preserved via direct audio uniforms.** `rm_ferrofluidSky` continues to be sampled at the reflection vector by the `matID == 2` branch in `raymarch_lighting_fragment`. Aurora content is rebuilt from audio uniforms passed directly into the lighting fragment (V.9 Session 4.5c Phase 1; implementation lands in the next session). Specifically:

- **Hue** ← `vocals_pitch_hz` (perceptual log-scale, confidence-gated at ≥ 0.6) with mood-valence fallback below the confidence threshold. Decision per Matt's 2026-05-14 sign-off ("vocals-pitch with mood fallback").
- **Intensity** ← `drums_energy_dev` smoothed 150 ms τ (same recipe as the retired rig's smoother).
- **Drift** ← curtain azimuth advances at `accumulated_audio_time × arousal × coef`. Slow; pauses at silence.
- **Live-stems gate** ← `smoothstep(0.02, 0.10, totalStemEnergy)` so silence shows the base purple sky only.

The musical contract (vocals → hue, drums → intensity, arousal → motion) is preserved; only the implementation abstraction changes from "orbital point lights with per-light buffer" to "direct audio uniforms read by the sky function."

**(c) D-125 and D-126 are marked HISTORICAL.** The decisions remain in `docs/DECISIONS.md` for the project archaeology but their implementations are gone. Future readers tracing the aurora-reflection mechanism should land on D-127 (this entry) for the current implementation pattern, not D-125 / D-126.

**(d) Phase 2c particle force model is rejected at the same time.** The Leitl-style XZ scatter/drift force model implemented in V.9 Session 4.5b Phase 2c does not produce the wave-undulation character the preset wants. Phase 2c is retired; Session 4.5c Phase 3 replaces it with wave-coherent particle motion aligned to the Gerstner-wave gradient. Phase 2a (spatial-hash bake) and Phase 2b (per-frame compute dispatch hook) infrastructure carries forward unchanged — only the force model is replaced.

### Reason

Real-music testing of Session 4.5b Phase 2c on the Love Rehab session capture (`/Users/braesidebandit/Documents/phosphene_sessions/2026-05-14T18-17-51Z`) flagged that:

1. The XZ-scatter / radial-drum-impulse / tangential-rotation force model produces visible scatter, not the *ocean undulation* the preset's design intent calls for.
2. The deviation-only audio gating produces "frozen" visuals during sustained-volume music (which is most of any song) — energy deviations sit near zero except at transient moments.
3. The §5.8 stage rig's orbital-light abstraction is the wrong primitive for "aurora reflection" — orbital geometry doesn't add musical meaning, and the per-light buffer adds infrastructure overhead without payoff.

The replacement design (direct audio uniforms feeding the sky function + baseline+modulation audio routing + wave-coherent particle motion) is structurally simpler, has no orbital-position state machine, and routes audio more directly into perceived motion.

### What was rejected

- **Keep the rig and just tune coefficients.** Matt had already deprecated the rig in prior session communications; carrying the implementation forward against his stated intent was the discipline failure that led to this decision.
- **Mood-only aurora hue (no vocals pitch coupling).** Considered briefly; rejected because aurora-as-mood-only reads as static ambient lighting rather than song-specific musical content. Matt's sign-off (2026-05-14): "Vocals-pitch with mood fallback. I am willing to try your approach; I hope it works out well." (The fallback to mood-only is available if the vocals-pitch coupling reads as too jittery on real music.)
- **Retain the slot-9 buffer ABI for a hypothetical future consumer.** No second consumer was ever planned. Removing the ABI now is cheaper than maintaining placeholder infrastructure.

### Forward references

- V.9 Session 4.5c Phase 1 — direct audio → aurora routing in `rm_ferrofluidSky` (the next session implements).
- V.9 Session 4.5c Phase 2 — baseline + deviation audio routing rework + warmup smoothness fix.
- V.9 Session 4.5c Phase 3 — wave-coherent particle motion (replaces Phase 2c).
- D-125 + D-126 are now historical; cite D-127 for the current aurora-reflection implementation pattern.

---

## D-LM-palette-library — Curated 18-palette library for Lumen Mosaic cell colour (Increment LM.4.7, filed 2026-05-18; amended 2026-05-18 — selection granularity per-song, not per-session; amended 2026-05-18 — anti-repeat window widened from N=1 to N=3 after Matt's M7 session)

**Status.** Accepted (paperwork-only; implementation lands at Increment LM.4.7).

**Decision.** Lumen Mosaic's per-cell colour source changes from LM.4.6's pure uniform random RGB (with LM.7's per-track chromatic-projected tint) to a **library of 18 hand-authored 12-colour palettes**. The Orchestrator selects one palette **per song** by drawing from a probability distribution biased on the per-track mood (valence + arousal). Within a song, every visible cell samples uniformly from the drawn palette's 12 entries. The per-track seed perturbs **sampling order** within the palette — which 12-bucket a given cell lands in — and never perturbs palette membership. Per-song selection biases against immediate repeats: a song will not draw the same palette as the immediately previous song (the previous palette is removed from the candidate set before the weighted draw); other anti-repeat penalties (last-N, family clustering) are not applied.

The 18 palettes are:

- **Vol. I (7):** Autumnal, Refn Glow, Glacier, Art Deco, Abyssal Bioluminescence, Kintsugi, Carnival.
- **Vol. II (6):** Holi, Geode, Rothko Chapel, Tropical Aviary, Persian Miniature, Ukiyo-e.
- **Plate 14:** Cathedral Lights (the cream-rescission proof point — see D-LM-cream-rescission).
- **Plates 15–18:** Cycladic, Ming Porcelain, Tenebrism, Obsidian.

**Context.** Decision E.2 (4 hand-picked mood-quadrant palette banks) was retired 2026-05-09 on Matt's monotony objection: *"four hand-picked palettes will lead to a very monotonous preset."* LM.4.6 — pure uniform random RGB per cell — replaced it after extended iteration through LM.4.5.x's HSV-with-rules attempts. Matt's verdict on LM.4.6 (2026-05-12) was *"Working. It's close enough. I'm giving up the fight on colors"* — explicitly the white flag, not a positive endorsement. The documented LM.4.6 trade-off (shader file header, ENGINEERING_PLAN Increment LM.4.6, D-LM-7 amendment) is that uniform random sampling produces **statistically identical panel aggregates** across tracks (different specific cell colours, same distribution shape — law of large numbers). LM.7's per-track chromatic-projected tint mitigated this at the aggregate level but did not give each session a distinct **palette character**; every track still looked like a sample from the same uniform RGB cube with a small chromatic offset.

The 2026-05-17 palette exploration conversation produced 18 hand-authored palettes with distinct named characters (mossy stained-glass for Autumnal, warm-neon-shadow for Refn Glow, frozen-blue-on-snow for Glacier, lacquer-and-gold for Art Deco, deep-sea bioluminescent emerald for Abyssal Bioluminescence, gold-on-black-cracked-porcelain for Kintsugi, saturated-festival for Carnival, magenta-yellow-cyan-powder for Holi, mineral-crystal-section for Geode, oxblood-and-charcoal for Rothko Chapel, parrot-feather for Tropical Aviary, manuscript-mineral-pigments for Persian Miniature, woodblock-mineral-flat for Ukiyo-e, jewel-tones-with-cream-highlights for Cathedral Lights, white-ground-with-cobalt for Cycladic, porcelain-and-cobalt for Ming Porcelain, near-black-with-single-warm-highlight for Tenebrism, black-with-iridescent-flash for Obsidian).

**Why the library defuses the original E.2 monotony objection.**

- **Library size (18 ≠ 4).** Four palettes meant any frequent listener saw the same four moods cycle predictably. Eighteen palettes drawn one-per-song means even a five-track listening run traverses five palettes; longer listening runs traverse most of the library.
- **Mood biases selection probability, never deterministic mapping.** The retired E.2 form was "mood quadrant → palette." The library form is "mood → probability distribution over the eligible 17 palettes (after the immediate-repeat exclusion)" — every eligible palette has non-zero probability everywhere in the mood plane, with the distribution shape favouring palettes whose character aligns with the per-track mood. A low-valence high-arousal track is more likely to draw Rothko Chapel or Tenebrism than Carnival, but Carnival is not excluded.
- **Per-song selection, not per-session.** Per-song palette change makes the palette part of how *each track* feels rather than how the *session* feels — a long playlist visibly traverses many palette characters, supporting the multi-preset-per-song product axis (see `feedback_multi_preset_per_song.md`). The previous palette is removed from the candidate set on the next track; the weighted draw runs over the remaining 17. Per-cell variety within a track comes from the seed-driven sampling-order perturbation within the palette plus the existing LM.3.2 band-routed beat-driven dance.

**Orchestrator selection model.**

Each palette declares an **explicit (valence, arousal) anchor** — a 2D point in mood space — as part of its Swift declaration. The weight function is a Gaussian over Euclidean distance from the anchor to the current track's (valence, arousal):

```
weight(palette_i, mood) = exp( -‖mood − anchor_i‖² / (2 × σ²) )
P(palette_i | mood) ∝ weight(palette_i, mood)        for palette_i ∈ candidate set
```

The candidate set is `library \ {previous_palette}` — the immediately previous song's palette is removed before the weighted draw. The first song of a session has no previous palette and draws from the full library of 18.

`σ` (kernel width) is a tunable file-scope constant; default ~0.35 in normalised mood-space units `[-1, +1]` per axis. Tighter σ → mood-fit dominates and most songs draw their highest-affinity palette; looser σ → variety dominates and mood becomes a soft bias. The default lands variety-leaning: even a very-low-valence-very-high-arousal track has non-zero probability of drawing Cathedral Lights, but Tenebrism / Rothko Chapel / Obsidian are much more likely.

The draw is **stable per (track, previous-palette)** — the same `(track identity, previous palette)` always produces the same palette, deterministic via a hash seeded by the track ID. This makes session replay reproducible and makes BUG-014 verification straightforward.

**Per-song sampling.**

Cells sample uniformly from the drawn palette's 12 entries: `cell_palette_idx = lm_hash_u32(cell_id ^ step ^ track_seed ^ section_salt) % 12`. The LM.3.2 team/period beat-step ratchet is preserved — cells advance their palette index on rising-edge of their assigned band's beat — but the index is into the 12-entry palette array, not into the full RGB cube. Per-track seed perturbs sampling order so that consecutive tracks drawing the same palette would (in principle, though the anti-repeat rule prevents this) show distinct cell-by-cell colour layouts; in practice the same-palette case is prevented by the anti-repeat rule and the seed perturbs the within-palette mapping across the (rare) case of returning to a palette later in the playlist.

**Relationship to retired decisions.**

- **E.2 (REVIVED in palette-library form).** Original E.2 (4 mood-quadrant banks) is retired in shape but preserved in spirit: the library architecture is the version that defuses the monotony objection.
- **E.3 (procedural IQ-cosine `palette()`) is superseded** by the library as the cell-colour mechanism for Lumen Mosaic. The `palette()` utility may still appear elsewhere in the engine; it is not the LM.4.7 cell-colour path.
- **D-LM-7 (per-track aggregate-mean RGB tint with chromatic projection)** is superseded for Lumen Mosaic — the LM.4.7 path doesn't need it because the drawn palette is already character-distinct. The chromatic-projection math remains in the codebase only if a future preset needs the same shape; the constant `kTintMagnitude` retires with LM.4.7.
- **D.4 / D.6** are superseded for Lumen Mosaic — the cell-colour generator is now palette-table-driven, not `accumulated_audio_time`-driven (D.4) and not pure hash → RGB (D.6).

**What was rejected.**

- **Per-session selection (one palette for the whole playlist).** Initially documented in the 2026-05-18 paperwork session; reversed in same-day amendment after Matt clarified "one palette per song." Per-song selection makes the palette part of how each track feels and supports the multi-preset-per-song product axis. Per-session would mean a 5-track playlist shows one palette identity even though we have 18 — wastes the curated variety.
- **No anti-repeat rule (pure mood-weighted draw, consecutive repeats allowed).** Rejected because two consecutive tracks drawing the same palette stutter visually — same Voronoi cell colours twice in a row reads as "the preset didn't change" rather than as a deliberate mood emphasis. The immediate-previous-palette exclusion is the smallest mechanism that prevents the stutter without aggressive anti-repeat penalties pushing the draw away from mood-fit.
- **Anti-repeat over a longer window (last-N exclusion for N > 1).** Initially rejected on the prediction that 17 eligible + Gaussian-over-distance weighting would give high palette-character drift without stronger anti-repeat. **Amended 2026-05-18 (post-implementation M7 session):** the prediction was wrong. Matt's 5-track M7 session (Love Rehab → There, There → Pyramid Song → Money → So What) showed within-quadrant clustering — two consecutive tracks whose preview-clip moods landed in the same neighborhood drew two *different* palettes from the same 4–5-palette cluster and read as "the preset didn't change much." The N=1 rule only prevents the exact-same palette twice; it does nothing about "two different palettes that look similar." Window widened to **`kAntiRepeatWindow = 3`** (last-3 exclusion). Library has 18 palettes, so even N=3 leaves 15 mood-weighted candidates per draw — the mood-fit cost per slot is small (the Gaussian is wide enough that the third-highest candidate within a quadrant has comparable mass to the first). The 30 % anti-repeat-induced reduction in mood-fit fidelity, against a library of 18 quadrant-balanced palettes, was the right trade. Re-evaluate at the next M7 review if Matt observes mood-fit erosion.
- **Procedurally-generated palettes (synthesised at session start from a few mood parameters).** Considered; would scale to infinite palettes but loses the hand-authored named character that makes each palette distinct. The conversation's "Cathedral Lights" / "Refn Glow" / "Holi" identities are not reachable by a 4-parameter procedural generator without re-inventing the curation work as a procedural-tuning pass.
- **Hard mood → palette mapping (single palette per mood quadrant).** Replays the E.2 monotony failure — predictable cycling, no surprise.
- **No mood bias at all (uniform random palette draw).** Rejected because sad-music-bright-palette and happy-music-dark-palette mismatches are jarring even when individual palettes are good; biasing the distribution costs nothing and preserves variety.
- **Affinity vector over multiple mood axes** (per-axis weights for valence / arousal / energy / etc.). Considered; more expressive but more authoring overhead per palette. The 2D (valence, arousal) anchor is the simplest declaration that captures the qualitative differences between palettes (warm-low-arousal Rothko Chapel vs cold-high-arousal Glacier vs warm-high-arousal Carnival).
- **Affinity derived from palette statistics (no explicit declaration).** Rejected because it removes the per-palette tuning surface — Matt cannot override "Cathedral Lights reads as low-arousal-moderate-valence" if the statistics-derived anchor disagrees. Explicit anchors are an authoring decision; statistics-derived is an inference Phosphene does not need.
- **Larger library (30+ palettes).** Deferred; 18 is the curated count from the 2026-05-17 conversation. Future palette additions are a separate increment under the rule below.

**Rule.** New palette additions require Matt M7 review per palette and a DECISIONS.md amendment citing this D-number. Palette removals are also gated on Matt sign-off — palettes are part of the session-to-session identity of the preset, and silently removing one changes what a returning user sees.

**Carry-forward.** Increment LM.4.7 (ENGINEERING_PLAN.md) is the implementation. The increment ships `LumenMosaicPaletteLibrary.swift` with the 18 palettes as `[SIMD3<Float>]` constants of length 12 + a per-palette `moodAnchor: SIMD2<Float>`, an orchestrator weight function + per-song draw site + previous-palette tracking, an `lm_cell_palette` rewrite that indexes into the per-song palette via cell hash + step + per-track seed, slot-8 GPU ABI extension to carry the 12-colour palette (36 floats or equivalent), rewritten `LumenPaletteSpectrumTests` asserting palette membership (every cell colour matches one of the 12 palette entries to within float epsilon), and the LM.9 pale-tone-share gate (per D-LM-cream-rescission) passing for all 18 palettes mechanically.

---

## D-LM-cream-rescission — Anti-cream project rule rescinded; replaced by pale-tone-share compositional ceiling (Increment LM.4.7, filed 2026-05-18)

**Status.** Accepted (paperwork-only; mechanical enforcement lands at Increment LM.4.7).

**Decision.** The CLAUDE.md project rule that prohibited muted / pastel / cream-haze palettes (introduced after Matt's 2026-05-09 LM.2 verdict and the parallel LM.4.5 v1 rejection) is **rescinded as a categorical exclusion**. It is replaced by a **compositional rule** with mechanical enforcement:

- **Pale tones** (defined as cells whose linear RGB has `min(R, G, B) > 0.65` — cream, ivory, pearl, bone, pale-pink, pale-azure, pale-mint, pale-anything where every channel is in the upper third) are **permitted as structural highlight**.
- **Pale tones are forbidden as dominant ground.** A panel where pale cells exceed **30 %** of total cells (the dominant-area fraction at the standard ~30-visible-cell Voronoi layout) is rejected. This is the mechanical gate.
- **The retired LM.2 / LM.4.5 v1 failure mode is still explicitly forbidden** — mood-tint formulas of the form `mix(cream, hue, sat)` that pull every cell toward a desaturated baseline regardless of input remain an anti-pattern in shader authoring. The distinction is now compositional, not categorical: pale colours appearing in the palette is fine; pale colours **dominating the panel** is not.

**Context.** The 2026-05-09 CLAUDE.md rule ("No muted palettes (mandatory)" + the DO NOT bullet "Do not ship muted, pastel, or cream-haze palettes") was drafted in response to LM.2's all-tinted-cream output and LM.4.5 v1's pastel guardrail that biased every cell toward low-saturation cream regardless of intended palette. Both failure modes shared the same shape — the **whole panel** read as cream — and the rule that landed conflated "panel-dominantly-cream" with "cream-appears-anywhere." Six months of preset authoring under that rule made the conflation visible: real stained-glass references (Sainte-Chapelle, Chartres), Ming porcelain references, Persian-miniature illuminations, and dozens of other historical visual languages use pale highlights against deep jewel-tone or near-black grounds. The blanket prohibition foreclosed all of those palettes.

The 2026-05-17 palette exploration produced **Cathedral Lights** as a deliberate test case. Its design-intent classification (per the Cathedral Lights HTML's "Roles" legend) is 7 ground colours (jewel tones) + 4 light colours + 1 anchor; the design narrative groups Cathedral cream, beeswax honey, pearl ivory, and sky pane as the "light" register. **Erratum (filed at amendment time, 2026-05-18):** under the rule's own definition (linear RGB `min(R, G, B) > 0.65`), only two of those four entries are actually pale — Cathedral cream `F2DEAC` (min channel 0.675) and pearl ivory `EDE4D1` (min channel 0.820). Beeswax honey `E8B95B` has B=0.357 (not pale) and sky pane `87B4D9` has R=0.529 (not pale). The realised pale-share under uniform sampling is therefore `2/12 ≈ 16.7 %`, not the `4/12 ≈ 33 %` originally cited in this paragraph. The earlier intuition argument confused the design-narrative "light" group with the rule's mechanical definition; the rule itself was correctly defined, and Cathedral Lights passes the 30 % ceiling comfortably (~17 % expected pale-share, well clear of 30 %). The 30 % calibration point remains correct as the boundary above which a panel starts reading as cream-dominant; Cathedral Lights stays inside that boundary even at peak hash-draw variance.

**The compositional rule (the load-bearing distinction a future preset author must read).**

- **Cream as accent against saturated ground = permitted.** The visual language is *"deep jewel tones interrupted by points of cream-coloured light"* — Cathedral Lights, Ming Porcelain, Persian Miniature, Cycladic at the pale-rich end, and any future palette that places pale highlights in the < 30 % minority. The pale cells read as **structural highlight**: the lit pieces of glass in a stained-glass window, the pearlescent dots in a Mughal manuscript, the lime-wash of a Cycladic structure against the sea.
- **Cream as dominant surface = rejected.** A panel where the eye reads "this is mostly cream/pale with some colour" is the LM.2 failure mode. Mechanically: > 30 % of cells with `min(R, G, B) > 0.65`. The pale-tone-share gate (LM.9, see D-LM-palette-library carry-forward) enforces this per fixture frame.

**Mechanical enforcement.**

- **Per fixture frame:** classify each cell by its linear RGB. Pale if `min(R, G, B) > 0.65`; not pale otherwise.
- **Gate:** reject the fixture if `pale_cell_count / total_cells > 0.30`.
- **Where it runs:** the LM.9 certification gate set, applied to every Lumen Mosaic palette in the library (D-LM-palette-library) and to every future palette addition.
- **Calibration point:** Cathedral Lights passes at ~17 % nominal pale-cell share (2 of 12 palette entries pale under the rule's linear-RGB definition; see Erratum in the Context section above). At the 30 % ceiling, ~13 percentage points of margin remain for hash-draw variance — comfortable. A palette with > 4 pale entries out of 12 (i.e. > 33 % palette pale-share under the rule's definition) will trip the gate on most hash draws and is rejected at palette-author time.

**Why a hard ceiling rather than a soft penalty.**

A soft scoring penalty (e.g. "pale-share weighted into orchestrator score") would let cream-haze palettes survive on tie-breakers. The LM.2 failure mode is the kind of regression that needs a hard floor; allowing it back in by score is the original failure mode by another name. The 30 % ceiling is below the boundary where a panel starts reading as cream-dominant (≥ ~40 % is unambiguously cream-haze; the 25–35 % band is the structural-highlight register) and gives ~5 percentage points of margin for hash-draw variance against the Cathedral Lights calibration point.

**What was rejected.**

- **Keeping the categorical anti-cream rule.** Forecloses every stained-glass / porcelain / miniature / Cycladic palette. The 2026-05-17 palette exploration produced five palettes (Cathedral Lights, Cycladic, Ming Porcelain, plus Persian Miniature and Ukiyo-e at the pale-rich end) that would all have been excluded — and Matt accepted each as ship-worthy on visual preview.
- **A higher pale-tone-share ceiling (40 %, 50 %).** Tested against the LM.2 failure-mode threshold; cream-haze starts reading at ~40 % and above. 30 % is the calibrated ceiling that admits structural-highlight palettes (Cathedral Lights at ~25 %, others below) and rejects cream-dominant panels (≥ ~40 %).
- **A lower ceiling (20 %, 15 %).** Excludes Cathedral Lights and any palette with a deliberate large pale-highlight share. The cream-rescission is what makes those palettes shippable; tightening the ceiling reproduces the original rule at a different threshold without solving the underlying conflation.
- **HSV-domain definition of "pale" instead of linear-RGB `min(R, G, B) > 0.65`.** HSV-pale (`S < 0.25 ∧ V > 0.85`) and linear-RGB-pale agree on the obvious cases but diverge at the pale-saturated edge (pale magenta, pale teal). The linear-RGB definition catches both achromatic-pale and chromatic-pale-with-all-channels-high; the HSV definition lets chromatic-pale-with-high-V through. The LM.2 failure mode is panel-wide low-channel-variance; the linear-RGB form maps more directly onto that failure.

**Rule.** The pale-tone-share ceiling (≤ 0.30) is the project's compositional rule on cream / pale in Phosphene presets going forward. Authoring guidance (CLAUDE.md, SHADER_CRAFT.md) is updated to reflect this. The categorical "Do not ship muted, pastel, or cream-haze palettes" wording is retired; the parallel CLAUDE.md DO NOT bullet is rewritten under this decision. The mood-tint anti-pattern (`mix(cream, hue, sat)`) remains forbidden as a shader-authoring shape — but as an anti-pattern in the implementation, not as a categorical exclusion of pale colours from the palette space.

**Scope.** This decision governs Lumen Mosaic at LM.4.7 directly. It applies project-wide to any preset that exposes a per-cell or per-shard discrete colour register — future palette-based presets inherit the same gate. Continuous-colour presets (ray-march scenes, fluid simulations, plasma-family) are not in scope; their colour discipline lives in SHADER_CRAFT.md material cookbook recipes (e.g. mat_chitin, mat_oceanWater) where the relevant rule is per-recipe saturation and roughness, not aggregate pale-share.

**Carry-forward.** Increment LM.4.7 (ENGINEERING_PLAN.md) implements the pale-tone-share gate in `LumenPaletteSpectrumTests` (or wherever the LM.9 cert gates land in code) and verifies it passes for all 18 palettes in the library — Cathedral Lights being the calibration point. The CLAUDE.md DO NOT bullet is updated in this same paperwork session. The Visual Quality Floor pointer is updated to refer to the pale-tone-share rule rather than the retired no-muted-palettes rule.


## D-128 — Local-file playback uses an in-process AVAudioEngine, not the Core Audio process tap (LF.1, 2026-05-27)

**Status:** Accepted (2026-05-27).

**Context.** The Core Audio process-tap path (`AudioHardwareCreateProcessTap`) has accumulated several documented pain points: DRM-triggered silent zeros (FA #22 / SilenceDetector / D-022 tap-reinstall scheduler), screen-capture permission as a hard prerequisite for non-zero delivery (FA #22), scrub-induced teardown requiring backoff-installed recovery (ARCH §Audio Capture), and no first-class playhead. The process-tap also assumes Phosphene is a passive observer of audio someone else is playing — `PRODUCT_SPEC.md` codifies the "Phosphene does not control playback" principle, and the streaming path strictly observes it. LF.1 is the first spike in an LF.1 → LF.4 discovery arc exploring whether Phosphene playing local files itself — owning the playhead, decode path, and analysis tap — bypasses those problems for that specific source.

**Decision.** A new `InputMode.localFilePlayback(URL)` case routes to a `LocalFilePlaybackProvider` class that:

1. Opens an `AVAudioFile` (Float32 planar at the file's native rate — 44100 Hz for love_rehab.m4a).
2. Drives an `AVAudioEngine` graph: `AVAudioPlayerNode → engine.mainMixerNode → outputNode`.
3. Installs the analysis tap on the **player node's output bus (bus 0)**, pre-mixer and pre-volume. The user's output-volume control does not affect the analysis signal.
4. Forwards interleaved float32 PCM through the existing `onAudioSamples` callback so the downstream `UMARingBuffer` / FFT / MIR / stem pipeline is source-agnostic. The provider manually interleaves planar L/R into the L/R/L/R layout `SystemAudioCapture` delivers (matching `AudioInputRouter.startFilePlayback`'s pattern for the existing `.localFile` diagnostic mode).
5. Loops at EOF (re-schedules the file via `AVAudioPlayerNode.scheduleFile`'s completion handler), matching the existing `.localFile` mode's `file.framePosition = 0` behavior.
6. Observes `AVAudioEngineConfigurationChange` and restarts on fire (best-effort from beginning; mid-track resumption deferred).

`AudioInputRouter`'s tap-reinstall scheduler (`+SignalState.swift`) is mode-gated so it is dormant in both `.localFile` and `.localFilePlayback` modes — those modes have no process tap to reinstall, and silence in a played file is real musical silence, not a teardown.

The launch path reads `PHOSPHENE_LOCAL_FILE_PLAYBACK` at app start (`.task` modifier on `ContentView` in `PhospheneApp.swift`). When the env var points at a readable file, `VisualizerEngine.startLocalFilePlayback(url:)` flips `localFilePlaybackActive`, starts the LF provider, runs the stem pipeline, and transitions `SessionManager` to ad-hoc / `.playing`. `startAudio()` (the process-tap launch path that `PlaybackView.setup()` calls unconditionally) checks `localFilePlaybackActive` first and short-circuits — without this guard, the systemAudio tap install would call `AudioInputRouter.stopInternal()` and tear down the LF provider milliseconds after it started. `ContentView`'s permission gate also checks `localFilePlaybackActive` so the visualizer renders even on a fresh install where screen-capture permission was never granted.

**Coexistence with existing `.localFile(URL)` mode.** The new case is a sibling, not a replacement. `.localFile(URL)` is preserved byte-identical: it feeds PCM into the analysis pipeline at near-real-time without playing audio through speakers. `SoakTestHarness` (D-060) and `CaptureModeReconciler`'s settings toggle (D-052) continue to use `.localFile`. `SoakTestHarnessTests` is the regression gate — green after LF.1 lands. Future increments (LF.2+) might converge the two cases, but the LF.1 spike preserves the diagnostic path intact.

**Relationship to the PRODUCT_SPEC.md "Phosphene does not control playback" principle.** This decision intentionally and narrowly amends the principle for the local-file source. The streaming path (Apple Music, Spotify) is untouched — Phosphene continues to passively observe audio the user controls in their streaming app. The local-file path is the exception: when Phosphene plays a local file itself, it owns the playhead because the file has no separate playback owner to coordinate with. The scope of the amendment is the new `.localFilePlayback` mode only; the principle stands for every other source. If LF.4 graduates this spike to a shipping feature, the UX_SPEC.md surfaces (settings audio-source picker, drag-and-drop, etc.) will need to make the playback-controlling-app distinction explicit so the user is not surprised by Phosphene producing sound for local files but not for streaming.

**Rejected alternatives.**

- **Reuse the existing `.localFile(URL)` case + add a "play through speakers" flag.** Conflates the diagnostic-injection contract (used by `SoakTestHarness` since 7.1) with the user-facing playback contract. Adding a flag risks accidental playback during soak runs and complicates the SoakTestHarness regression gate. Sibling cases keep both contracts byte-identical and let each evolve independently.

- **Use `AVAudioFile` + `AVAudioEngine` but route through the same backing implementation as `.localFile`.** Same conflation problem, plus the existing `.localFile` implementation uses a `Task.detached` polling loop with `Task.sleep(for:)` — appropriate for diagnostic injection but a poor fit for real-time playback where `AVAudioEngine`'s own scheduling is the right tool.

- **Hijack the process-tap path to play audio in Phosphene's own process.** Possible in principle (Core Audio aggregate devices can include both inputs and outputs), but defeats the entire premise of the spike — the goal was to bypass the process-tap path's documented problems, not work around them.

- **A separate top-level `PlaybackSource` abstraction parallel to `InputMode`.** Premature. The spike scope is "does owning playback work end-to-end" — adding a new abstraction is LF.4 work if the spike succeeds. LF.1 reuses `InputMode` because that's the smallest change that proves the concept.

**Verification (manual + automated).** The LF.1 closeout's manual verification reports a clean run on `love_rehab.m4a`: 1684 features.csv frames over 28.96 s (matching the fixture's 29.93 s with the expected ~1 s startup gap), raw_tap.wav at the file's native 44100 Hz with healthy RMS ≈ 0.31 (max amplitude 1.0 — Love Rehab's mastered peaks), session.log clean of any "Tap reinstall scheduled" / "CGRequestScreenCaptureAccess" / "DRM silence" lines, and an installed live BeatGrid at 118.5 BPM matching the track's true tempo within rounding. The two new regression tests `test_scheduleNextReinstall_isNoOpInLocalFilePlaybackMode` and `test_scheduleNextReinstall_isNoOpInLocalFileMode` lock the mode-gate behavior so a future tap-reinstall edit cannot re-enable scheduling for either mode.

**Out of scope (deferred).** Per the LF.1 prompt:
- ~~Stem separation pre-analysis of the full track (LF.2).~~ **Done in LF.2 — see D-129.**
- Persistent content-keyed stem cache (LF.3).
- Folder ingestion, M3U import, playlist semantics (LF.4).
- Drag-and-drop UI, settings audio-source picker, output-device routing (LF.4).
- Crossfade / gapless segue (LF.4).
- ID3/Vorbis tag extraction, album art display (LF.4).
- `SessionManager` integration (LF.4).
- ~~A/B comparison vs. process-tap on the same audio (LF.1.5).~~ **Done in LF.1.5 — see empirical characterization below.**
- Concurrency hardening of `tapSampleRate` propagation (separate ongoing task).
- ~~Format-coverage testing across MP3 / FLAC / M4A / AAC (LF.2).~~ **Done in LF.2 — see D-129.**

**Empirical characterization (LF.1.5, 2026-05-27).** A/B comparison on `love_rehab.m4a` (host: Mac mini M2 Pro, system default output Apogee Duet 3 at 48 kHz) — `docs/diagnostics/LF1.5_AB_COMPARISON_2026-05-27.md`. Verdict: **characterizable deltas**, all explainable by known structural differences; no unexpected divergence. Headline numbers (LF vs tap, middle 80 % of active window):

- **BPM agreement:** LF 118.7 / tap 118.0 (Δ = 0.67 BPM, well within ±3). Both paths share the same ~6 BPM offset vs the track's true 125 BPM tempo, a Beat This! short-window characteristic that is path-independent.
- **Sample rate:** LF 44100 Hz (file native), tap 48000 Hz (system default). Unavoidable structural delta; FFT bin width scales with the rate ratio, which shifts `spectralCentroid` (single-fixture: ~22 % in normalized units, LF 0.087 / tap 0.068) and propagates downstream into `MoodClassifier` outputs (valence +34 %, arousal -38 %). **Corpus-scale update (CENSUS.3, 993 tracks, 2026-07-08): the cross-path centroid skew measures ~9 % — the single-fixture 22 % over-stated it.** Cross-path *absolute* mood comparison is NOT valid; cross-path *relative* mood comparison within a session IS valid.
- **Volume / amplitude:** LF pre-mixer at ~0 dBFS, tap post-output at ~-8 dBFS (2.5× quieter). AGC compresses but does not fully eliminate this level difference: load-bearing bands all skew tap-lower by 17–24 % (subBass -17 %, bass -24 %, treble -23 %, mid noise-floor) in the same direction proportional to the level ratio. This is consistent with the AGC's running-average converging to a lower baseline on the quieter input. The volume-level skew on the tap path is a known property of the existing process-tap architecture (`RUNBOOK.md §Audio levels too low`); the LF path does not have this dependency by construction.

**Implications for downstream LF increments.** Within the tolerance Phosphene's downstream consumers need, the load-bearing musical metrics (BPM, subBass, sub-bass onset rate) agree across paths. Stems extracted from either path will be analyzed against a consistent beat reference. The cross-path centroid + mood deltas are SR-driven and path-stable (re-running the same fixture on the same path gives the same numbers), so the LF arc can proceed without compensating for them at the analysis layer. Single-fixture characterization — cross-track variance is LF.2 territory.

---

## D-137 — Dragon Bloom: feedback-native UPLIFT (strands ← stems), not a literal Milkdrop copy (Dragon Bloom, 2026-06-02)

### Context

Matt M7 on Spike 2 (session `2026-06-02T13-37-09Z`) confirmed bilateral symmetry (no clipart) but flagged "not really seeing petals." Reading `source.milk` (and confirming in a faithful butterchurn reference — `tools/dragon_bloom_reference/`) established that **Spike 1's mechanic is structurally different from the reference's** (flat polar ring vs. 3 tumbling 3-D spectral strands + a 5-fold `sin(ang·5)^5` per-pixel petal warp + a chromatic colour-separation warp shader, smeared through heavy feedback). See DRAGON_BLOOM_PLAN §0.

Matt then reframed the work: **"This is an UPLIFT specifically for Phosphene. Recommend an approach to translating this preset to Phosphene's platform and taking better advantage of the technologies that are part of Phosphene but were not a part of Milkdrop/Butterchurn."** — i.e., translate the preset's *identity*, do not slavishly reproduce Milkdrop's line-drawing + HLSL-warp mechanics.

### Decision

Uplift Dragon Bloom in Phosphene's **mv_warp feedback register** (D-027 — the original's charm is procedural feedback, and this is Phosphene's most-proven capability), uplifting along three axes Phosphene is strong and Milkdrop was weak:

1. **Strands ← real stems (headline musical uplift).** Milkdrop drives its 3 custom waves by mid/bass/treble FFT bands; Phosphene has stem separation. The 3 bloom strands map to **drums / bass / vocals** (Matt's pick, 2026-06-02); `other` tints the palette. Each arm of the bloom is legibly an instrument. Driven via deviation primitives (D-026); stems available frame-1 via StemCache.
2. **HDR-glow strands + ACES tonemap** (vs Milkdrop's 8-bit clamped additive).
3. **valence + spectral-centroid warm palette + per-stem tinting** (the former Spike 3).

Kept: bilateral symmetry (D-136 fold), mv_warp feedback, bass breathing, and the chromatic colour-separation (ported into the compose pass; the hand-written GLSL in `tools/dragon_bloom_reference` `fixWarpShader` is the reference spec).

**Explicitly rejected (Matt agreed): a full ray-march / 3-D volumetric rebuild.** It changes the preset's identity, is the high-fidelity-hero register that has repeatedly stalled (Drift Motes D-102, Ferrofluid, Aurora Veil), and the original's magic — feedback — is already native to mv_warp. A 3-D depth exploration, if ever wanted, is a separate spike, not the main path.

### Rationale

Choosing the feedback register over a 3-D rebuild trades maximal use of Phosphene's hero tech for **fidelity reliability** — the consistent failure mode (FA #58/#61/#62) is overreaching on hero-material/3-D fidelity. The uplift still uses distinctly-Phosphene capabilities (stem separation, HDR, mood-driven palette, mv_warp) that Milkdrop lacked, so it is a genuine platform uplift, not a port. The stems→strands mapping is the load-bearing musical-role upgrade (per `feedback_audio_layer_one_primitive`: one primitive per layer — each strand consumes one stem).

### Engine surfaces (modest — far short of a ray-march rebuild)

- A path to **draw the 3 strands** (the `per_point` projected points): prototype the cheapest faithful option first (procedural-vertex strand geometry vs. fragment splat). Per-pixel min-distance over the full high-frequency strand curve is too expensive (~512 samples × 3 strands × all pixels), so geometry/procedural-vertex is the likely path.
- A **chromatic colour-transform in the mv_warp compose pass** (small shader addition).

### Build (layered; each verified against the faithful live oracle + gif/still)

L1 strands ← drums/bass/vocals (HDR glow) · L2 `per_pixel` petal warp → `mvWarpPerVertex` · L3 chromatic transform in compose · L4 decay/echo/invert blend · L5 valence/centroid palette + per-stem tint. Offline verification extends the diag harness to load the real recorded tap (`raw_tap.wav`), not the synthetic sine.

### Gate

Per-layer Matt M7 against the faithful live reference + `01_target.png`/`target_animated.gif`. The reference harness (`tools/dragon_bloom_reference/`) is the comparison oracle; its warp-shader fix (hand-written GLSL) is what makes it faithful.

---

## D-138 — Dragon Bloom: faithful butterchurn render-loop port + music response, certified (Dragon Bloom, 2026-06-02)

### Context

D-137's layered uplift (L1–L5) reached a warm symmetric bloom but L4 ("rich warm FILL") turned into a multi-hour struggle: the render kept diverging from the live butterchurn oracle (pale/washed, under-filled, then over-bright/flat, then jittery). **Root cause was method, not difficulty:** the work was patching Phosphene's `mv_warp` — a *structurally different* feedback engine — to imitate butterchurn one divergence at a time, instead of replicating butterchurn's render loop wholesale by reading its source. Each fix corrected one symptom and exposed the next. (Promoted to a Failed Approach — see CLAUDE.md FA #70.)

### Decision

Replicate butterchurn's custom-warp render loop verbatim for Dragon Bloom (read from `tools/dragon_bloom_reference/butterchurn.min.js`), then layer the Phosphene music-response uplift on top. **Dragon Bloom is certified** (Matt live M7 across 5 Spotify tracks + a local file, 2026-06-02 sessions `…20-59-52Z` → `…21-46-36Z`).

### The butterchurn render loop (durable reference — these are the load-bearing facts)

Per frame: **swap prev↔target → warp(prev) into target → draw waves normal-alpha ON TOP of target → target IS next frame's feedback; comp (echo/gamma/invert) is display-only.** Specifics verified in the bundle:

1. **No decay on custom-warp presets.** `fDecay` is applied ONLY in the *default* warp (`ret = sample(prev)·decay`). A preset with a custom warp shader sets `warpColor=(1,1,1,1)` and does `fragColor = ret·vColor` = no decay; the custom shader self-regulates the feedback via its normalise + R→G→B transfer (the B-fade). Phosphene was double-decaying → starved edges (pale background), field converged to the instantaneous wave draw (no accumulation).
2. **8-bit feedback textures (`UNSIGNED_BYTE` RGBA, CLAMP_TO_EDGE, LINEAR).** The per-frame clamp is load-bearing — at no-decay it holds the field at a saturated equilibrium. A float (rgba16f) buffer over-accumulates to pale near-white. (Earlier I made it float thinking 8-bit caused the pale wash; the opposite is true once the loop is correct.)
3. **Custom waves blend NORMAL-alpha** (`wavecode_*_bAdditive=0`; the global `bAdditiveWaves=1` is for the built-in waveform only), drawn directly onto the warped target. Additive piled the centre-converging strands into a white core (→ black after invert).
4. **Comp is display-only.** echo (orient-1 horizontal flip, alpha 0.5) → `ret *= gammaAdj` (1.07, a MULTIPLY not pow) → `if(brighten) ret=sqrt(ret); if(darken) ret=ret*ret` (both set ⇒ **cancel**) → `if(invert) ret=1-ret`.
5. **Bilateral symmetry comes from the video echo** (horizontal mirror at comp), NOT strand mirroring. So 3 waves, not 6 mirrored instances.
6. **`fWaveAlpha` is the built-in-waveform alpha, not custom waves.** Custom-wave alpha = per-point `a` × `bModWaveAlphaByVolume` ramp.
7. **butterchurn feeds 6×-boosted audio** (tap ≈ −18 dB); `bModWaveAlphaByVolume`'s 0.71/1.30 bounds assume that scale — so Phosphene's raw stem energies are boosted 6× before the ramp (else quiet stems gate the waves to ~0).
8. **The warp is a 32×24 vertex mesh** (`warpUVs` per mesh vertex, interpolated) — Phosphene's `mvWarpPerVertex` grid matches it. A per-fragment recompute is both unfaithful and costs trig per pixel; use the mesh.

### Music response (D-137 uplift, on top of the faithful loop)

- **Each arm is an instrument** (headline): drums/bass/vocals → strand length (`mod`) + brightness (`modVol`).
- **Breathing (primary continuous):** the warp zoom expands on loud bass and settles when it thins (reformulated from source `per_pixel_8`, which pinned at the 1.05 cap and never breathed).
- **Per-arm transient flare (accent):** each arm brightens on its own stem's deviation (D-026) — smeared by the feedback.
- **Beat pulse (accent, at the comp/DISPLAY stage so it punches through the no-decay feedback instead of being smeared):** a smoothed attack/decay envelope on `beatComposite` (shaped to its strong peaks; the drums-stem dev was too noisy on the process-tap and caused flicker) drives a subtle per-beat pump (4% zoom) + brighten (12%).
- **Tumble on `accumulated_audio_time`** (energy-weighted, pauses at silence) instead of free-running wall-clock (FA #33).

### Engine changes (Dragon-Bloom-scoped; other mv_warp presets byte-identical — PresetRegression)

- `mvWarp_fragment`: full warp transfer (normalise + hue-zoom resample + R→G→B transfer) gated by `chromaticMix`; **no decay** on the custom-warp path.
- `mvWarp_blit_fragment`: faithful comp (echo + gamma + invert) + the beat-pulse pump/brighten, via a float4 `post` uniform (`setMVWarpPost`; `(0,0,1,0)` ⇒ identity for other presets).
- `drawWithMVWarp`: for presets with a scene-geometry overlay (Dragon Bloom), warp-no-decay → strands normal-alpha on top → blit (skips the scene + decayed-compose path). Smoothed beat envelope (`mvWarpBeatEnv`) computed per-frame.
- Strand pipeline blend → normal alpha; feedback textures → 8-bit (`feedbackFormat` reverted to the drawable format).

### Pitfall recorded

The float→8-bit revert must change BOTH the pipeline format (`PresetLoader.feedbackFormat`) AND the app's `MVWarpPipelineBundle.feedbackFormat` — a mismatch (8-bit pipeline rendering into a float texture) is an attachment-format mismatch that **stalls the GPU (beachball) at the preset transition**, not a clean error.

## D-139 — Fata Morgana: faithful butterchurn mirage port + coordinated bar-sway stem uplift, certified (Fata Morgana, 2026-06-03)

### Context

Second butterchurn port after Dragon Bloom (D-138). `martin [shadow harlequins shape code] - fata morgana` is a **mirage** — starfield night sky, a glowing cycling horizon, and a reflective rippling neon floor. Render loop replicated wholesale from source per FA #70: a custom feedback **WARP** (blur-driven swirl + lattice, bakes its own `×0.98−0.02` decay), a custom procedural **COMP** (the mirage projection — perspective floor, horizon glow, grid stars, water reflection; display-only, fully replaces fixed-function gamma/darken/echo), a wide-ish **blur1**, and custom **SHAPES** drawn on top of the warped target (= the feedback). Per frame: `warp(prev) → blur → shapes-on-top → comp → swap`.

### Decision

Ship Fata Morgana as a **certified** preset (Matt live M7 across the iterative movement-tuning sessions 2026-06-03, closing on `…17-08-42Z`). The faithful port is uplifted with stem separation; the visual identity is **three neon spectra (drums/bass/vocals) swaying over the water in time with the bars**.

### Faithful-port facts (durable; verified against butterchurn source)

- **Warp:** line-for-line from the converted JSON — `rot = dot(blur1, roam_sin)·16`, displacement `0.2·luma·rotate(p, rot)` (calmed to `0.15` in the uplift — see below), texsize lattice, `ret = main(uv1)·0.98 − 0.02`.
- **`zoom = 1.05`** comes from `pixel_eqs` (`a.zoom=1.05`), which overrides `baseVals.zoom=0.9999`. It is faithful — content flows outward 5%/frame, and the zoom feedback of the shapes is what forms the concentric neon rings.
- **Custom comp fully replaces fixed-function.** `gammaadj`/`darken`/`echo`/`invert` are the DEFAULT-comp body (`butterchurn.js` ~3550, `if shaderText.length === 0`); a custom comp does NOT apply them. The mirage's horizon-glow colour is `(0.02/(0.02+|xf|))·slow_roam_sin` — `slow_roam_sin = 0.5+0.5·sin(time·{.005,.008,.013,.022})`.
- **blur1** is a separable gaussian stored at ~0.25 res (`blurRatios[0]=[0.5,0.25]`), spanning ~±4 source texels — MODERATE, not wide. The warp derives its swirl direction from blur1, so blur width governs **rings vs ribbons**: too wide → coherent large-scale swirl twists the zoom-echo rings into smeared ribbons. (An early over-wide ×6 blur was the smear; corrected to ×2 ≈ ±4 texels.)
- **Grid stars** are gated by `pw_noise_lq` — a POINT-WRAP (nearest-sampled) random texture, so the lit cells scatter into a starfield. Sampling smooth Perlin instead gives a regular diagonal Moiré lattice.

### Three durable engine/port lessons (promoted to CLAUDE.md Failed Approaches)

1. **sRGB round-trip for sRGB-naive ports (FA #71).** butterchurn writes to an sRGB-naive WebGL canvas (shader output = display value). Phosphene's drawable is `.bgra8Unorm_srgb`, so Metal sRGB-ENCODES the comp output → lifted blacks / washed midtones. Fix: sRGB-DECODE the comp output so the target's encode round-trips back to the source's display values. Only the final comp→drawable write needs it (the feedback textures are linear `.bgra8Unorm`, matching butterchurn's 8-bit clamp).
2. **`time` magnitude, not phase, drove the "gray horizon" (FA #71 corollary).** `slow_roam_sin`'s slowest period is ~21 min, so it only leaves the pale opening quarter once `time` reaches the hundreds of seconds. The oracle was sampled minutes in (saturated, spectrum-cycling); a fresh render sat in the pale quarter. Fix: phase-seed the glow clock (`+400 s` base) so it opens mid-cycle; plus a **per-session random jitter** (~one 21-min period) so every session opens on a different horizon hue (a deliberate, Matt-requested divergence — butterchurn itself has no such jitter).
3. **MSL `FeatureVector`/`StemFeatures` fields are snake_case (FA #72).** Using the Swift name (`f.beatPhase01`) in `.metal` silently fails to compile and the preset is **dropped from the loader** (`PresetLoaderCompileFailureTest` count 18→17 caught it). The fields are `f.beat_phase01`, `f.bar_phase01`, `st.drums_energy_dev`, etc.

### Music uplift (the design Matt converged on over the movement-tuning pass)

The journey is instructive (each step is a recorded session): per-onset size **bursts** read as "too excited / more bursts than beats" (drums_beat + dev fire on every onset); a per-blob **bar-direction reversal** was "lost among the many spectra"; a whole-field **downbeat zoom breath** synced but wasn't the vision. The converged design:

- **COUNT:** the source's 4/1/5-instance shapes were a crowd (chaos). Cut to **ONE instance per instrument** (drums/bass/vocals) + the faint central echo — 3 bright spectra.
- **MOTION — coordinated bar sway (headline):** the 3 spectra share a horizontal sway `A·cos(π·swayClock)`, `swayClock` advancing **+1 per bar** (accumulated `barPhase01` deltas, downbeat wrap handled) → a 2-bar cosine that turns at each downbeat. **Phase-offset** so they stay balanced: drums (phase 0) and vocals (phase 1.0) are anti-phase (one swings right while the other swings left), bass (phase 0.5) weaves centre — at every downbeat they sit right/centre/left, never bunched. Frozen when no bar grid is present.
- **POSITION:** base `y < 0.5` puts them above the horizon (the comp samples the sky at feedback `v ∈ [0 top, 0.5 horizon]`, and a shape's `v` equals its `y`, so `y > 0.5` reads as IN the water).
- **BRIGHTNESS:** one gentle pulse per GRID beat (`pow(1−beat_phase01, 4)`, not per-onset `drums_beat`) + per-stem `_energy_dev` for instrument identity.
- **Swirl calmed** to `0.15·luma` (from the faithful `0.2`) so the swaying spectra streak less (Matt-requested).

### Authoring lesson (durable)

**Few coordinated subjects beat many independent ones for a legible musical gesture.** A bar-synced motion on 11 independent orbits is invisible (chaos); the same gesture on 3 phase-coordinated subjects reads clearly. When a coupling "isn't reading," check subject COUNT and COORDINATION before increasing amplitude. (Project-scope twin of FA #67 one-primitive-per-layer.)

### Files

`FataMorgana.metal`, `FataMorgana.json` (certified:true), `RenderPipeline+FataMorgana.swift`, `RenderPipeline.swift` (sway/glow state), `RenderPipeline+PresetSwitching.swift` (per-session glow jitter), `FataMorganaMVWarpAccumulationTest.swift` (diag feeds beat/bar phase), `FidelityRubricTests.swift` + `PresetDescriptorRubricFieldsTests.swift` (cert ground-truth sets). Other mv_warp presets byte-identical (PresetRegression).

---

## D-142 — Canvas-hold accumulation is the no-decay / identity CONFIG of the mv_warp brush-on-feedback paradigm (Skein.ENGINE.1, 2026-06-05)

**Date:** 2026-06-05. **Status:** implemented (Skein.ENGINE.1); pending Matt's sign-off (the increment gate). Establishes the persistent, lossless paint canvas for the `Skein` action-painting preset (`docs/presets/SKEIN_DESIGN.md`).

**Context.** Skein needs a feedback canvas that *accumulates* marks without decaying or resampling them — paint lands, stays, and is occluded only by later opaque paint-over-paint (the temporal-integral canvas, `SKEIN_DESIGN.md §1.4 / §5`). This is architecturally the **no-decay / identity configuration of Dragon Bloom's brush-on-feedback loop** (D-135 / D-138): warp the previous frame, then composite new geometry normal-alpha on top. Skein differs only in setting the warp to **identity** (paint doesn't move) and decay **off** (paint persists). The Skein design doc (§3 gap report, §8 #5) and plan (locked decision #5) had anticipated this would need an **explicit new "canvas-hold mode" added to the mv_warp family** (an engine addition).

**The ENGINE.1 audit superseded that framing.** Canvas-hold is reachable as **pure per-preset CONFIG of the existing mv_warp machinery — no PhospheneEngine source change, no new warp mode** — exactly as the design's own §0 / §5.1 already characterize it ("a configuration of existing machinery, not a new paradigm"). The four properties and where each is set on the Dragon Bloom path:
- **Identity warp** — the preset's `mvWarpPerVertex` returns `uv` unchanged + `mvWarpPerFrame` zoom=1/rot=0/offsets=0 (`Skein.metal`); the engine `mvWarp_vertex` already calls the preset functions.
- **No decay** — the preset's `mvWarpPerFrame` returns `decay = 1.0`; the shared `mvWarp_fragment`'s `decayMul = (chromaticMix > 0) ? 1.0 : in.decay` (`PresetLoader+WarpPreamble.swift:206`) resolves to `in.decay = 1.0`.
- **No R→G→B transfer** — `mvWarpChromatic = 0` (the default; `RenderPipeline.swift:50`), which collapses both the hue-zoom resample (`sUV = mix(baseUV, zoomedUV, 0)`) and the colour transfer (`mix(cr, warm, 0)`) to identity. The app already sets `setMVWarpChromatic(0.0)` for any preset with no scene-geometry overlay (`VisualizerEngine+Presets.swift:397`).
- **Marks-on-top** — the existing `setSceneGeometry` strands-on-top mechanism (D-138). Not exercised live at ENGINE.1 (Skein ships no marks yet); Skein.1 wires its real marks through this same path.

**No-decay is NOT bound to the colour transfer.** The decisive line `decayMul = (chromaticMix > 0.0) ? 1.0 : in.decay` lets a preset choose no-decay (`pf.decay=1.0`) **without** the transfer (`chromaticMix=0`) — they are independent. Net: under identity + no-decay + no-transfer, `mvWarp_fragment` returns the previous canvas **byte-for-byte**. `SkeinCanvasHoldTest` proves this empirically — **whole-frame Hamming 0 across 130 hold frames** (256×256, sRGB feedback) through the live scene → warp → blit → swap dispatch path, confirming the sRGB 8-bit round-trip and identity-at-pixel-centers are both exact. 8-bit is therefore lossless (`SKEIN_DESIGN.md §5.5`); no linear-format or nearest-sampler override was needed.

**Decision.** Canvas-hold accumulation is ratified as the **no-decay / identity configuration of the mv_warp brush-on-feedback paradigm (D-135 / D-138)** — a sibling of Dragon Bloom (`passes: ["direct","mv_warp"]`), explicitly **not** paradigm-stacking and **not a D-029 concern**. It is realized as a preset recipe + this decision record, **not** a new engine mode — which fully satisfies the intent of plan decision #5 ("a legible canvas-hold precedent; a clean sibling of Dragon Bloom; not an overload of the narrow `feedback`/Membrane path") with no redundant engine code. Every other mv_warp preset is **byte-identical by construction** (no shared engine/app/shader code was touched; the full 1388-test engine suite + `PresetRegressionTests` are green; the D-137 beachball risk is moot because no shared format/binding/transfer changed).

**Deferred to Skein.1 (flagged, not done here).** (a) **[RESOLVED by D-143, Skein.ENGINE.1.1.]** The app overloads "has a scene-geometry pipeline ⟹ Dragon Bloom `chromatic=1.0` + comp invert/echo/gamma" (`VisualizerEngine+Presets.swift:381-399`), and `PresetLoader.makeSceneGeometryPipeline` hard-codes the `dragon_bloom_strand_*` function names (`PresetLoader.swift:852`); when Skein.1 adds marks-on-top, both must be de-entangled per-preset. (b) Skein is the first **light-canvas** preset, so the design's "ground stays light" (§1.2) is in genuine tension with the white playback chrome — a bright cream ground drops white-text WCAG contrast to ~4.23:1 (`PresetContrastCertificationTests`). ENGINE.1 uses a darkened *toned-ground* placeholder to clear the gate; the real resolution (darker chrome backdrop for light presets, dark chrome text, or a toned ground) is a Skein.1+ palette/UX decision. (c) `family: painterly` (+ the `PresetCategory` enum case) is a product-taxonomy decision deferred to Skein.1; ENGINE.1 ships Skein with no `family` (nil is valid — SpectralCartograph / Staged Sandbox precedent).

## D-143 — Marks-on-top + per-preset canvas-clear are CONFIG of the mv_warp brush-on-feedback paradigm (Skein.ENGINE.1.1, 2026-06-05)

**Date:** 2026-06-05. **Status:** implemented (Skein.ENGINE.1.1); pending Matt's sign-off (the increment gate). Clears the "Deferred to Skein.1 (a)" de-entanglement D-142 flagged, and makes Skein **render live for the first time**.

**Context.** D-142 established canvas-hold as the no-decay / identity CONFIG of the mv_warp brush-on-feedback paradigm (D-135 / D-138) but noted the marks-on-top half (D-138 "marks composited normal-alpha on top of the held frame") was still hard-wired to Dragon Bloom in three places — so Skein, though it shipped the canvas-hold recipe, **could not draw a single mark** and the marks-on-top path produced a **black** canvas (no cream ground). The three couplings (verified file:line in the ENGINE.1.1 audit):
1. `PresetLoader.makeSceneGeometryPipeline` hard-coded `dragon_bloom_strand_vertex/_fragment` — every other preset got `sceneGeometryState = nil` → no marks. (Its doc comment also stale-claimed "additive blend"; the code is **normal alpha**.)
2. The app `.mvWarp` apply branch keyed ALL of `setMVWarpChromatic(1.0)` + `setMVWarpPost(invert 1 / echo 0.5 / gamma 1.07)` + `setSceneGeometry(…1536/3/lineStrip)` — and, in the render loop, the comp **beat pump** — on `sceneGeometryState != nil`. Any marks preset inherited Dragon Bloom's colour-cycling + comp + draw params + beat pump.
3. The mv_warp canvas clear (`clearWarpTexturesToBlack`) was hard-coded black; on the marks-on-top path Pass 0 (the background fragment) is **skipped** (`drawWithMVWarp`), so a marks preset's ground could only be black.

**Decision.** The D-138 marks-on-top mechanism is now reachable by ANY mv_warp preset as pure per-preset CONFIG — no new engine pass — generalising D-138 the way D-142 generalised D-135's feedback loop. Dragon Bloom is one instance, Skein another:
- **Geometry functions** resolve per-prefix (`<prefix>_geometry_vertex/_fragment`, prefix from `fragment_function`), mirroring the `<prefix>_warp_fragment` precedent (D-139). Dragon Bloom keeps `dragon_bloom_strand_*` via a legacy fallback (its library is the only one that defines those symbols) → byte-identical; presets without overlay functions still get `nil`.
- **Draw params + chromatic + comp + beat pump** come from a new optional **`marks` descriptor block** (`vertex_count`, `instance_count`, `primitive`, `chromatic`, `comp{invert,echo,gamma}`, `beat_pulse`). The app reads it when a preset has a geometry overlay. Dragon Bloom's block carries its exact prior literals verbatim → byte-identical. The comp beat pump is now gated by `marks.beat_pulse` (was `sceneGeometryState != nil`); Dragon Bloom is the only `strandsOnTop` preset today, so all existing presets are byte-identical.
- **Canvas clear colour** is per-preset on `MVWarpPipelineBundle` / `MVWarpState` → `clearWarpTextures(to:)`, sourced from `marks.canvas_clear` (linear RGB; omitted → black). Black for every existing preset → byte-identical; Skein clears to its cream ground (carried across drawable-resize on `MVWarpState`).

Every other mv_warp preset (Fata Morgana, Gossamer) has no geometry overlay → the `else` branch → chromatic 0 + comp identity + black clear, exactly as before. **Gated byte-identical:** `PresetRegressionTests` + `DragonBloomMVWarpAccumulationTest` + `FataMorganaMVWarpAccumulationTest` green; no shared mv_warp format/transfer/binding changed (the D-137 beachball risk is moot).

**Skein renders live.** `skein_fragment` is now the flat cream/toned GROUND only; the fixed test disc moved to a `skein_geometry_*` fullscreen-triangle overlay drawn normal-alpha on top with `chromatic=0`. Live, the ground comes from the per-preset canvas clear (Pass 0 skipped) and the disc from the overlay each frame; identity warp + no decay hold it losslessly. The disc is **hard-edged** so the per-frame redraw is idempotent (a partial-alpha AA fringe would re-blend toward teal every frame and creep for hundreds of frames; real Skein.1 marks are drawn once as the painter moves, so they keep their AA). `SkeinCanvasHoldTest`'s marks-on-top test proves — through the live scene→warp→overlay→blit→swap path — that the disc lands on a **cream** (not black) ground, `chromatic=0` holds **whole-frame Hamming-0 across 130 frames** while a `chromatic=1.0` control cycles, and the DB/FM accumulation tests stay green.

**Acceptance/Contrast.** Skein joins the Dragon-Bloom / Fata-Morgana **readable-form** exemption (its readable content is the overlay, invisible to the fragment-only harness). It is **not** exempted from non-black / no-white-clip / contrast — its cream ground genuinely passes those (white-text WCAG ≈ 4.9:1 on the toned ground). The light-ground-vs-white-chrome tension D-142(b) flagged remains a Skein.1+ palette/UX decision; `family: painterly` (D-142(c)) remains deferred.

**Deferred (unchanged).** The wandering painter + swept-capsule pour (marks that ACCUMULATE a line) are Skein.1 — ENGINE.1.1 ships only the static test disc through the now-wired overlay. Palette/UX (b) and `family` (c) per D-142.

**References.** `PresetLoader.makeSceneGeometryPipeline`; `PresetDescriptor.MarksConfig`; `VisualizerEngine+Presets.swift` `.mvWarp` branch + `mvWarpMarksPrimitive`; `RenderPipeline+MVWarp.swift` (`clearWarpTextures`, beat-pump gate); `RenderPipeline+PresetSwitching.swift` (`setMVWarpPost beatPulse:`); `MVWarpTypes.swift` (`canvasClearColor`); `Skein.metal` / `Skein.json` (`marks` block); `SkeinCanvasHoldTest`. Supersedes D-142's "Deferred to Skein.1 (a)".

## D-145 — Nimbus beat-grid live phase: deferred to its own project (number reserved at the NB renumbering; entry filed retroactively at DOC.4)

**Date:** 2026-06-05 (reserved) / 2026-06-11 (filed) · **Increment:** NB.9 cert review · **Status:** Accepted — the deferral stands; the project has not started

> **DOC.4 integrity note (2026-06-11):** the number was claimed at the 2026-06-05 renumbering ("the beat-grid project moved to D-144 / D-145" — see D-144's header note) and has been cited ever since (D-144, FidelityRubricTests' Nimbus cert comment, memory), but the entry itself was never written. This retroactive stub records the decision as it was made so the citations resolve; it adds nothing not already decided.

**Decision.** Nimbus's M7 surfaced two findings; the mood half became D-144. The beat half — the cached beat grid's live phase is unreliable at track start (the FA #69 / Cold-Start Phase Contract structural limit) — is NOT a Nimbus defect and was deferred to its own future project, accepted as a known limitation at Nimbus certification. Any such project starts from the Cold-Start Phase Contract's premise constraints (human-tap reference / full-track local-file analysis / manual calibration — never another short-window signal).

**References.** D-144 (the renumbering + the mood half), CLAUDE.md §Cold-Start Phase Contract + Failed Approach #69, the NB.9 cert closeout.

## D-146 — BUG-027 fix scope: per-band EMA pivot on the FeatureVector band deviation (mirror the stem path); document the stem-energy offset (AGC2.2)

**Date:** 2026-06-05. **Status:** decided (Matt's AGC2.2 call); implementation = AGC2.3; validation + catalog M7 = AGC2.4. Refines D-026 (the deviation-primitive contract).

**Context.** BUG-027: the `FeatureVector` positive deviation primitives (`bassDev`/`midDev`/`trebDev`) are derived against a **fixed 0.5 pivot** (`MIRPipeline.swift:334-339`), but the AGC normalises the **total 6-band energy** to 0.5 (`BandEnergyProcessor.swift:204,213`), so each band centres at `0.5 × its fraction of total` — well below 0.5 for any non-dominant band. AGC2.1 measured the consequence on 4 real sessions, both capture paths, 4 spectral classes (`docs/diagnostics/AGC2_1_DEVIATION_CENTRING_2026-06-05.md`).

**Evidence (AGC2.1).** `bassDev` fires 2–8 % of active frames; **`midDev`/`trebDev` fire ~0 % on every session, both paths — including a genuinely mid-rich acoustic track (Elliott Smith) and a treble-rich jazz track (Mingus)**; the mid band's centre rises 0.03 → 0.10 with spectral focus but never nears 0.5. Structural, not genre-correlated. The **stem** deviation path fires 56–77 % because it already pivots on a **per-stem EMA** (`StemAnalyzer.swift:277-298`), not a fixed 0.5 — the working pattern ships side-by-side with the broken one. Raw `{stem}Energy` centres ~0.25–0.45 (≠ 0.5), which bites consumers reading the raw value (Nimbus `bloom`, D-144 r1.6).

**Decision (Matt's call — "fix band cue, document stems").**
1. **FeatureVector band path — engine fix.** Replace the fixed-0.5 pivot with a **per-band reference that tracks each band's own recent level**, mirroring `StemAnalyzer`'s per-stem EMA (seed-from-first-non-zero per SAR.1; reset on track change). `bassRel/midRel/trebRel` (and the `*AttRel` family) become "relative to this band's own average," and `*Dev = max(0, rel)` fires when the band is above its own norm — **alive for every band**. The **total-energy AGC is untouched**: raw `f.bass/f.mid/f.treble` and the cross-band relative-energy information are unchanged, so non-deviation consumers and the overall "look" are unaffected. The exact normalisation (additive `(x − avg)·2` vs a scale-free relative form) is an AGC2.3 detail, settled against the recorded sessions to guarantee both firing (the ≥ 20 % gate) and usable amplitude across bass/mid/treble; the default is to mirror the stem path.
2. **Stem path — no engine change + documentation.** The stem *deviation* path is already correct (per-stem EMA, fires 56–77 %) — leave it. Document the raw `{stem}Energy` ~0.30 centre as an authoring fact and recalibrate the few consumers that read the raw value per-consumer (Nimbus already did, D-144 r1.6). Capture in `SHADER_CRAFT.md §14.1`.

**Rejected.**
- **(a) Per-band AGC** (each band its own AGC denominator → band value centres 0.5): also changes the raw band *values* every preset reads (`f.treble` baseline 0.005 → 0.5) and **erases the "which band dominates" information** the 6-band total-energy AGC deliberately preserves (`BandEnergyProcessor.swift:40,122`). Largest blast radius; rejected for collateral on non-deviation consumers and on the catalog's baseline look.
- **(c) Document only:** leaves mid/treble "punch" unavailable to every preset — even the signed `midRel` centres −0.87, so the signed form is also weak for mid/treble. Rejected as it permanently caps the catalog's per-band reactivity.

**Consequences.**
- `RelDevTests`' formula pin (`bassRel == (bass − 0.5)·2`) is **deliberately updated** in AGC2.3 to the new EMA-relative semantics (signed `*Rel` now centres ~0), with the rationale in the diff — never edited silently to green a red bar.
- The positive deviation cue moves from "fires rarely on a strong transient (~3 %)" to "fires when above the band's own average (~50 %)" — the *intended* D-026 behaviour, but a real change in feel for any preset implicitly relying on the rare firing. **`PresetRegressionTests` golden hashes shift across the 11 deviation-consuming presets; surfaced + re-banked with Matt's approval at AGC2.4, alongside a catalog M7 on both paths.**
- Mid/treble `*Dev` remain quieter in absolute terms than `bassDev` (those bands are quieter post-AGC); authors driving motion from `midDev`/`trebDev` may need a larger gain than for `bassDev` — documented in `SHADER_CRAFT.md §14.1`.

**References.** BUG-027 (`KNOWN_ISSUES.md`); AGC2.1 evidence (`docs/diagnostics/AGC2_1_DEVIATION_CENTRING_2026-06-05.md`); D-026 (deviation-primitive contract this refines); D-144 r1.6 (manifestation-B preset-scope band-aid); Failed Approach #31 (absolute thresholds on AGC values — same family).

**AMENDED — implemented (AGC2.3 → 2.5, 2026-06-06).** Landed as the **additive** per-band EMA (`BandDeviationTracker`); the scale-free form was rejected at AGC2.3 (prototype: unbounded spikes, e.g. bass dev p90 reached 7.2). No golden-hash drift (the regression fixtures feed hand-built FeatureVectors, bypassing the live derivation). A cold-start **two-speed warmup + value ceiling** was added in **AGC2.4.1** after the M7 found the per-band EMA seeded from the session-start AGC spike and — since `MIRPipeline.reset()` is never called per track — stayed poisoned ~3-4 min; a live-path test now guards it (FA #66). BUG-027 marked **Resolved**. The AGC `f.bass` cold-start spike itself (which pops/drops continuous-energy presets like Ferrofluid Ocean) was split out as **BUG-029** — it is *not* a deviation issue and AGC2's warmup does not touch `f.bass`.

---

## D-147 — Skein.ENGINE.1.2 (gated slot-6 marks-on-top buffer) + the Skein.3 stem→colour contract

**Date:** 2026-06-05. **Status:** decided + implemented (Skein.3). Palette signed off by Matt. Consumes D-135 / D-138 (brush-on-feedback), D-142 / D-143 (canvas-hold + per-preset marks-on-top), D-026 (deviation primitives), D-019 (stem warmup).

**Context.** Skein.1/2 stayed pure closed-form (Path A) and deferred the CPU-side `SkeinState` + a per-preset overlay buffer to "ENGINE.1.2, when the stateful painter genuinely needs it." Skein.3 (per-mark stem colour frozen at lay-time, onset-driven burst spawning, per-track seed, per-stem flow integrators) is that consumer — none of it is synthesizable in the closed-form fragment.

**The ENGINE.1.2 decision (audit-driven — Option A unavailable).** The prompt hypothesized Option A (pure config: the slot-6 `directPresetFragmentBuffer` already reaches the overlay fragment). The audit **falsified it** with file:line evidence: Skein renders via the marks-on-top `strandsOnTop` branch (`RenderPipeline+MVWarp.swift:212`), which **skips** `renderSceneToTexture` (`:217`) — the *only* site that binds fragment slot 6 (`RenderPipeline+MVWarpScene.swift:43-44`, for Gossamer/Arachne *scene* fragments). Pass 2's `strandsOnTop` branch (`encodeMVWarpScenePass:77-79`) calls `drawSceneGeometryOverlay`, which binds only `features`@vtx0 + `stems`@vtx1 (`RenderPipeline+SceneGeometry.swift:36-37`) — **no fragment buffer**. So the overlay fragment could not see slot 6 on this path. **Decision: Option B (gated binding), the lightest form** — a gated `if let presetBuf = directPresetFragmentBuffer { setFragmentBuffer(index:6) }` in the `strandsOnTop` branch, affecting only Dragon Bloom + Skein. **Byte-identical:** Dragon Bloom sets no `directPresetFragmentBuffer` (nil → no bind); Fata Morgana uses its own `renderFataMorgana` branch (never reaches `encodeMVWarpScenePass`). `SkeinState.swift` follows the established `GossamerState` pattern (no engine touch beyond the one gated binding).

**The Skein.3 stem→colour contract.**
1. **One stable, well-separated, vivid colour per stem over cream** (drums / bass / vocals / harmonic-other). Palette is **open** (legibility, not specific hues, is the binding constraint — README); Matt signed off on **Full Fathom Five** (charcoal / oxblood / ochre / teal) 2026-06-05.
2. **Opaque compositing, never mud.** The fragment outputs the **topmost** mark's colour (paired `bestCover`/`bestCol` max), never a blend of two stem colours (the dead-mat anti-ref). Each onset burst is mono-colour, frozen at its stem at lay-time.
3. **Per-stem onset = `*_energy_dev` activity, not `*_beat`.** Only `drums_beat` is a real pulse; the other `*_beat` are reserved-zero. Onsets derive from rising activity on each stem's `*_energy_dev` (D-026) in CPU state — the history the closed-form fragment cannot see. Throttled-while-active (refractory-limited), not rising-edge-only, so sparse real onsets still lay enough colour to read.
4. **Dominant-stem line colour = discrete argmax** of smoothed per-stem energy_dev (never a colour-space EMA, which passes through the mud midpoint).
5. **sRGB decode (FA #71).** The `.bgra8Unorm_srgb` canvas sRGB-encodes on store, so the palette is treated as display-space and sRGB-**decoded** to linear before packing — without it, dark stems lift to washed mid-tones and become unreadable (measured: drums/bass painted 0 → 933/2905 after the decode).
6. **§1.5 track-change reset.** A new track paints its own canvas: reseed the painter from the new track identity (FNV-1a title|artist — same track → same painting, §5.7) and wipe the canvas to cream (`clearMVWarpCanvasToGround`, gated to Skein).

**Rejected.** **(Option A)** pure config — empirically unavailable (the overlay fragment never sees slot 6 on the strandsOnTop path). **(Mood/structure/anticipation in Skein.3)** out of scope (Skein.5); no valence/arousal written anywhere (FA #25). **(`*_beat` for per-stem onsets)** only drums_beat is real.

**Consequences.**
- `SkeinState` is the sixth `*State.swift` (registry). The gated slot-6 binding is now a registry capability ("per-preset fragment buffer reaching the marks-on-top overlay fragment").
- Route-firing evidence (PresetSessionReplay, real Mingus session): drums 55.7 % / bass 30.4 % / vocals 68.7 % / harmony 68.4 % / energy 77.9 %. Viscosity ← centroid and flick-sharpness ← attackRatio are **not SR.1-measurable** (SessionFrame records no centroid/attackRatio) — stated, not asserted (PT.1).
- `family: painterly` + the `PresetCategory` case + cert (`certified`, `rubric_profile`) remain deferred to Skein.6.

**References.** SKEIN_DESIGN §5.2–5.4 / §1.5 / §5.7; SKEIN_PLAN Skein.3; D-142 / D-143 (canvas-hold + marks-on-top); D-135 / D-138 (Dragon Bloom brush-on-feedback); Failed Approach #71 (sRGB double-encode); RENDER_CAPABILITY_REGISTRY (slot-6 marks-on-top row); SHADER_CRAFT §18.8.

---

## D-148 — BUG-029 fix approach: ease the AGC loudness meter in at each track start (seed-from-first-audible + hold-through-silence); AGC3.2

**Date:** 2026-06-05. **Status:** decided (Matt's AGC3.2 call); implementation = AGC3.3; validation + catalog M7 = AGC3.4. Sibling of D-146 (the AGC2 deviation fix) — both are cold-start fixes touching the `BandEnergyProcessor` family, at different layers (D-146 = the deviation EMA pivot; D-148 = the AGC band values themselves).

**Context.** BUG-029: at every track onset preceded by silence, `BandEnergyProcessor`'s total-energy AGC denominator (`agcRunningAvg`, which is *not* reset per track) has decayed toward zero across the inter-track silence — or seeded at `1e-6` off the session-start pre-roll — so the first audible frame over-scales and `f.bass` spikes to an absolute ~3.5–4.0 (steady ~0.25 = 11–17×). Continuous-energy presets reading `f.bass` directly (Ferrofluid Ocean's `1.0 + 0.8·clamp(f.bass,0,1)`) pop to their clamp ceiling then collapse. AGC3.1 measured it on a real 5-track LF session (`tools/agc3/measure_coldstart_spike.py`; `docs/diagnostics/AGC3_1_COLDSTART_SPIKE_2026-06-05.md`).

**Evidence (AGC3.1).** The spike is **per-track** (not one-time — refutes the BUG-025 shelving premise), gated by the silent pre-roll (every onset with *any* gap spiked; the one zero-gap onset did not); the **inter-track** instances last *longer* (0.9–1.2 s, slow AGC rate) than session-start (0.10 s, fast warmup); `fo_spike_strength` pins to 1.800 (+40–55 % height pop). The per-stem path does **not** spike because `StemAnalyzer.reset()` re-seeds each stem's processor per track — a working in-codebase precedent.

**Decision (Matt's call — option (a), "ease the meter in per track").** Smooth the arrival by easing the loudness meter into each track instead of cold-starting and over-reacting to the first sound. Implementation (AGC3.3, Claude's engineering choice *within* (a)) touches **only** cold-start/silence inside `BandEnergyProcessor`:
1. **Seed-from-first-audible.** Defer the AGC seed until the first frame with non-zero energy (don't seed `1e-6` off leading silence). The first audible frame seeds `agcRunningAvg` from its own energy → the meter starts at a sane level (slightly muted on a loud onset transient) and eases to steady, instead of dividing by ~0. Mirrors `StemAnalyzer` / SAR.1 / `BandDeviationTracker`.
2. **Hold-through-silence.** When a frame is near-silent *relative to the running average* (`totalRawEnergy < 0.02·agcRunningAvg`), hold the running average instead of decaying it toward zero. So an inter-track silence no longer leaves a tiny denominator for the next onset to over-scale against. Output is ~0 during the silence either way.

**Steady-state guarantee.** For continuous audible input (frame-0 energy > `1e-6`, no sub-2 % frames) the code path is **byte-identical** to the prior algorithm — same seed, same EMA, same rate schedule — so the total-energy AGC's mix-density-stability response (D-026) is untouched. Behaviour changes **only** at/below the near-silence floor (where output is ~0) and in the immediate post-silence ease-in window. A live-path test reproduces the spike un-fixed and asserts it gone (FA #66).

**Rejected.**
- **(b) Cap the jump at track start** — clip the over-reaction without easing in. Simpler, but the first loud hit still reads strong (just not a full white-out); less smooth than (a). The AGC3.1 evidence (per-track recurrence; the longer inter-track instances) favours the smoother arrival.
- **(c) Per-preset** — each preset softens its own track-start response. No shared-engine risk, but every author must remember it forever and shipped presets stay un-fixed; the evidence shows the artifact is at the shared-meter source, where one fix benefits every `f.bass` consumer.

**Consequences.**
- Touches the shared loudness meter feeding every preset + the deviation primitives → catalog M7 on both paths at AGC3.4 (Ferrofluid Ocean first), even though the change is cold-start-only.
- The per-stem `BandEnergyProcessor` gets the same change; BUG-018 (stem cold-start deviation ceiling — a separate StemAnalyzer-layer seed) must stay green; verified at AGC3.3.
- `PresetRegressionTests` golden hashes feed hand-built FeatureVectors (bypass the live AGC) → expected no drift; verified at AGC3.4.
- Streaming-path validation deferred to the AGC3.4 M7 (no streaming multi-track session existed at AGC3.1; the session-start mode is path-independent, the inter-track mode depends on the source app's gap).

**References.** BUG-029 (`KNOWN_ISSUES.md`); AGC3.1 evidence (`docs/diagnostics/AGC3_1_COLDSTART_SPIKE_2026-06-05.md`); D-146 (sibling AGC2 deviation-layer cold-start fix); D-026 (deviation-primitive / mix-density-stability contract the steady-state guarantee protects); BUG-018 / SAR.1 (seed-from-first-non-zero precedent); BUG-025 (the shelved sibling this re-justifies); Failed Approach #66 (live-path test parity), #31 (AGC-cold-start family).

## D-149 — Skein.ENGINE.2 wetness channel: the canvas ALPHA carries decaying wetness (approach A), read by a Skein-owned comp fragment (Skein.4 sheen)

**Date:** 2026-06-08. **Status:** decided + landed (Skein.ENGINE.2 + Skein.4; commits `255fcc64`/`c5192d28`/`ba62e1ef`/`23060d11`). The wet-now / dry-past legibility device (`SKEIN_DESIGN §1.4`): fresh paint glistens, the accumulated past is matte, so the eye tracks the musical *now*.

**Context.** Skein needs a transient per-pixel "wetness" signal — stamped to ~1 where paint lands this frame, decaying toward 0 each frame (the decay **pausing at silence**), readable at the display stage — to drive a wet specular highlight. The constraint: the canvas-hold **RGB is the lossless permanent paint record** (the ENGINE.1 Hamming-0 invariant); drying must be a **read-time effect on a separate channel**, never a destructive per-frame multiply on the RGB (`SKEIN_DESIGN §5.5`). And every other mv_warp preset must stay **byte-identical** (the D-137 preset-transition-beachball pitfall). The session prompt framed it as a cut-line: if ENGINE.2 needs more than a *gated additive signal + a gated read*, stop and certify matte-only.

**Decision — approach A (canvas ALPHA channel), in the cleanest form (Skein-owned fragments).** The audit found the per-prefix override mechanism (`PresetLoader.swift:689`/`:691`, used already by Fata Morgana) lets Skein own its warp + comp fragments **without touching one line of shared GPU code**:
1. **Storage = the feedback texture's ALPHA channel.** Skein's feedback is `.bgra8Unorm_srgb`, whose **alpha is linear 8-bit** (sRGB encodes RGB only) — ideal for wetness. RGB stays the lossless permanent paint record.
2. **Stamp = the existing overlay's alpha-over blend.** `skein_geometry_fragment` already returns `float4(bestCol, bestCover)`; the overlay blend is `.add` / `sourceAlpha` / `oneMinusSourceAlpha` on **both** colour AND alpha (`RenderPipeline+SceneGeometry.swift` / `PresetLoader.swift:886`) → solid fresh paint stamps A→1. **No new stamp code.**
3. **Decay = `skein_warp_fragment`** (the `<prefix>_warp_fragment` override): holds RGB **byte-identically** (identity sample — the same RGB the shared `mvWarp_fragment` produced) and decays A by `wetnessDecay` each frame. **Pauses at silence:** `wetnessDecay = exp(-rate·dt·stemMix)` from `SkeinState` (the `accumulated_audio_time` semantics — at silence stemMix→0 → factor→1 → wetness holds). **Not a new audio primitive** — reuses the existing silence gate (FA #67).
4. **Read = `skein_comp_fragment`** (the `<prefix>_comp_fragment` override): reads canvas RGB + wetness A from the already-bound compose texture and renders the wet/dry sheen (Skein.4: GGX specular gated by wetness, normal from the canvas luminance gradient, dry → matte+desaturate). **No new blit binding.**

Plumbing: one gated `mvWarpWetnessDecay` uniform (mirror of `mvWarpChromatic`), bound at warp-fragment `buffer(1)`, default 1.0; only `skein_warp_fragment` declares buffer(1), so the shared `mvWarp_fragment` ignores it and FM never runs the standard warp pass → **byte-identical for every other preset by construction**.

**Rejected — approach B (dedicated R8 ping-pong texture).** The plan's fallback. It keeps the RGB hold provably intact too, but needs a new texture + a stamp mechanism (the overlay writes RGBA to the compose texture, *not* a separate R8, so B forces MRT on the shared overlay pass that Dragon Bloom also runs, or a wasteful re-dispatch of the marks) + a decay pass + a gated blit binding. Approach A gives the same "read-time effect on a separate channel" (alpha *is* separate from RGB) with **no new texture, no new pass, and the shared `mvWarp_fragment` literally untouched** — strictly less code and less risk. The session prompt leaned B for "zero risk to the RGB hold," but A's RGB risk is also nil (Skein's RGB warp code is the identity sample), so A dominates.

**Cut-line: NOT invoked.** ENGINE.2 is a gated additive uniform + Skein-owned warp/comp fragments + a gated `.a` read — **no shared feedback-texture format change, no new render pass, no mv_warp loop reshape.** Skein certifies *with* the sheen (not matte-only).

**Consequences.**
- The `SkeinCanvasHoldTest` whole-canvas Hamming-0 lossless-hold check is re-scoped to **RGB-only** — the RGB channels are the lossless record; ALPHA legitimately carries decaying wetness (at silence it is held too). A new `SkeinWetnessTest` proves stamp≈1 / monotone decay under music / holds-at-silence through the live path.
- The Skein.4 sheen gates the specular on a **paint-present mask** (distance from the cream ground) so the bare canvas (whose A also seeds at 1 from the clear) reads matte — wet *paint*, not a wet *floor*.
- Bloom-on-wet-specular is deferred (it needs a pass / governor state at the blit); the in-shader glint gives the sparkle without a new pass (cut-line-conscious).
- DB/FM/Starburst byte-identical: `PresetRegressionTests` (20 presets × 3 conditions) + the DB/FM MVWarp accumulation suites green; `PresetLoaderCompileFailure` count intact.

**References.** `SKEIN_DESIGN.md §1.4` (wet-now/dry-past), `§5.2` (per-frame pass structure), `§5.5` (drying = read-time on a separate channel); `SKEIN_PLAN.md` (Skein.ENGINE.2 + Skein.4 + the cut-line); D-142 (canvas-hold = config of the brush-on-feedback paradigm), D-147 (the ENGINE.1.2 slot-6 overlay binding), D-137/D-138/D-139 (the per-prefix override precedent), D-026 (deviation/silence-gate), FA #67 (one primitive per layer), FA #71 (sRGB at the blit), FA #66 (live-path test parity), FA #72 (silent MSL drop guard); `SHADER_CRAFT.md §18.9` (the wet/dry sheen craft).

## D-150 — Skein.4.1 colour-per-stroke: a colour-breakpoint ring freezes the pour-line colour per-segment and starts a displaced NEW pour on a dominant-stem switch

**Date:** 2026-06-09. **Status:** decided + landed (Skein.4.1; pending Matt's M7). **Defect (Matt M7, session `2026-06-09T14-19-14Z`):** "the colour of the line changes sometimes in the middle of a stroke. In reality, a new line in a different colour would appear because the painter needs to grab or use a new paint container."

**Context.** The pour LINE is redrawn closed-form every frame from the recent painter polyline (a ~40-frame tail, `skein_geometry_fragment` Layer A), coloured by a SINGLE `lineCol` = the current dominant stem (SkeinState discrete argmax). So when the dominant stem switches, the whole redrawn tail — the recent ~40 frames of already-laid line — recolours. The bursts were already correct (each `SkeinBurstGPU` freezes its stem colour at spawn); only the continuous line recoloured. **Matt's product call (option 2 over the simpler option 1):** a colour change should read as a genuinely NEW pour (the painter grabbing a new paint container), not a continuous line whose colour merely changes at a seam.

**Decision — a per-pour breakpoint ring in `SkeinUniforms` (approach A), carrying both a frozen colour AND a bounded position jump.** On each dominant-stem **change**, SkeinState pushes a breakpoint `(painterTau-at-change, new linear colour, new-pour offset)` into a small fixed ring (16 entries, evict-oldest), packed as an **additive tail** of the slot-6 `SkeinUniforms` buffer (`SkeinBreakGPU`, 24 B each, after the fixed `bursts[48]`; `pad0`→`breakCount`). The fragment, per tail sample, looks up the latest breakpoint with `tauStart ≤ sample-τ` (`skeinLineLookupAt`) → that sample's lay-time **colour + offset**:
1. **Colour freeze.** A tail segment laid before a switch keeps the old colour; one laid after gets the new. The already-baked canvas (held losslessly) was already correct — only the live tail recoloured, and now it does not.
2. **New pour (the jump).** Each breakpoint carries a small **bounded, non-cumulative** position offset — a fixed-magnitude (0.05 UV) vector rotated by the golden angle per switch (seeded → §5.7 determinism; non-cumulative → never drifts off canvas; golden-angle → consecutive pours always well-separated). The new-colour line is drawn at `painterPos + offset_new`, the old at `painterPos + offset_old`. The segment that would BRIDGE two different pours (different breakpoint `start`) is **not drawn** → a clean gap. So a colour change reads as the painter lifting and starting a fresh drip elsewhere. Bursts flick from the painter's jumped position too (their throw direction still from the un-offset path, so the jump never spikes it).

**Coverage is byte-identical to Skein.4's union SDF (no rings regression).** With ONE per-frame radius, `max over per-capsule coverage ≡ 1 − smoothstep(min segDist − r)` — so tracking the nearest *drawn* segment to pick its frozen colour does NOT change the coverage value. The M7-round-3/4 no-rings fix (one union SDF, one radius, blurred wetness) is untouched; `test_sheen_noConcentricRings` stays green (8.68 < 13).

**Rejected — option 1 (continuous path, colour frozen per-segment, no jump).** Simpler and lower-risk (it fixes the literal "recolours the whole stroke" complaint), but Matt's words ("a NEW line would appear") asked for a genuine new pour. A pure temporal gap (no jump) was also rejected: at slow/pooling movement neighbouring capsules overlap and FILL any same-path gap, so only a spatial jump reliably reads as a new pour at all speeds.

**Rejected — option B (per-frame colour written into the canvas, no history).** The tail is redrawn closed-form each frame; there is no single "lay frame" for a tail sample to write a colour into. The breakpoint ring is the clean way to know each sample's lay-time colour, exactly mirroring the per-burst colour freeze.

**Byte-identical guarantee.** `SkeinUniforms` is SkeinState's own slot-6 buffer; no other preset binds it. The MSL/Swift structs match byte-for-byte (the ring is an additive tail; `breakCount` reuses the former `pad0`). `PresetRegressionTests` (20 presets × 3 conditions) + the DB/FM MVWarp accumulation suites stay byte-identical; `PresetLoaderCompileFailure` count intact (no silent MSL drop, FA #72).

**Consequences.**
- At silence only the white baseline breakpoint exists (offset 0) → the byte-identical pre-4.1 continuous white line; the silence pour-line continuity gate stays 1.000.
- New gate `test_lineColorFreeze_keepsColourAndStartsNewPour` drives two ordered real-stem slices across a dominant switch through the live path and asserts the pre-switch line KEEPS its colour (X≫Y at the old offset), the post-switch line is the new colour (Y≫X at the new offset), and the new pour is displaced (a real jump; the new pour is at the jumped offset, not the un-jumped path).
- The continuous-path continuity invariant is now **per-pour**, not whole-tail (the line is intentionally broken at switches) — this only affects with-audio rendering; the gated continuity test runs at silence (one pour) and is unaffected.

**M7-round-2 (Matt, live, 2026-06-09, session `2026-06-09T16-23-21Z`): "the lines are very short rather than a long continuous dripping/pouring across the canvas." Added a minimum-pour dwell + hysteresis on the pour switch.** The pour COLOUR is the dominant-stem argmax, which flickers far faster than a pour can read — measured on the session: **63 dominant switches / 44 s, median pour 0.2 s (Δτ 0.34), 79 % under 0.5 s.** Each tiny pour, with the new-pour jump, became a short displaced segment instead of a long stroke. Fix: a new pour now COMMITS only on a *sustained, decisive* change — the current pour must have lasted `minPourTau = 3.0` τ (≈ half-a-canvas minimum at the trajectory's ~0.15 UV/τ; typical pours run longer), AND the challenger must lead the incumbent's smoothed energy by `pourSwitchHysteresis = 1.25×` (no flicker between near-equal stems). The first pour commits immediately; the **bursts still fire per-stem onset, ungated** (they are the accents). Validated on the session: **63 → 10 pours, ~4 s average.** The line colour/flow/viscosity now all follow the *committed* pour (not the instantaneous argmax), so each pour is coherent. This gates the existing dominant-switch event — **not a new audio route** (FA #67 holds). Side effect on the test surface: with long continuous lines the splatter droplets connect to the line (one >500 px component), so the `distinctBlobs` separable-satellite count is no longer a reliable gate (it was already session-fragile per `SHADER_CRAFT §18.8`) — demoted to a diagnostic; the onset→splatter firing is gated directly on the per-stem spawn tally + busy≫calm. The bake/hold check is now colour-agnostic (the longer first pour can be a low-spread stem like charcoal).

**References.** `SKEIN_DESIGN.md §1.2` (the dominant-stem line records who leads); `SHADER_CRAFT.md §18.8` (the colour-per-stroke + new-pour craft note); the per-burst colour freeze (D-147, `SkeinBurstGPU.colR/G/B`); D-149 (the Skein-owned warp/comp fragments this builds beside); FA #66 (live-path test parity), FA #67 (one primitive per layer — the jump reuses the existing dominant-switch event, not a new audio route), FA #71 (sRGB-decoded palette), FA #72 (silent MSL drop guard); the open product decision (option 1 continuous-frozen vs option 2 new-pour) — Matt chose option 2.

---

## D-151 — Skein.ENGINE.3: a gated `RenderPipeline.setStructuralPrediction` bridge delivers the live structural-section signal to the preset tick (CPU-only, byte-identical)

**Date:** 2026-06-09. **Status:** decided + landed (Skein.ENGINE.3, local `main`). **Type:** engine increment (a small gated analysis→render→tick channel). **Matt chose option (a)** at the Skein.5 scoping — a *deliberate engine increment* for real section-awareness over an in-state proxy / deferral, honouring infra-before-preset (FA #59/#60).

**Context.** The live `StructuralPrediction` (`{ sectionIndex, sectionStartTime, predictedNextBoundary, confidence }`, `MIRPipeline.latestStructuralPrediction`, refreshed per frame by `StructuralAnalyzer.process`) was DSP/orchestrator-only — it did not reach the preset tick. Skein.5's structure sub-feature needs it. The split (Skein.ENGINE.3 prerequisite of Skein.5) keeps the *signal plumbing* separate from the *visual bias* (never bundled — FA #59/#60).

**Decision — a separate, lock-guarded, default-inert store on `RenderPipeline`, mirroring the `setMood`/`latestFeatures` value-injection bridge (option (A)).** `RenderPipeline.setStructuralPrediction(_:)` writes a backing `storedStructuralPrediction` under a dedicated `structuralPredictionLock`; the lock-guarded computed `latestStructuralPrediction` (default `.none`) is the read accessor. `SkeinState.tick` gains a `structure: StructuralPrediction = .none` parameter; the Skein mesh-preset-tick closure (`VisualizerEngine+Presets.swift`) reads `pipeline.latestStructuralPrediction` and passes it in. The `meshPresetTick` callback **type is unchanged** (`(FeatureVector, StemFeatures)`), so no other preset's wiring is touched → byte-identical by construction. CPU-only: structure is **NOT** a `FeatureVector`/`Common.metal` field (no D-099 migration) and is never written to the GPU buffer; `SkeinState` stores it in pure-CPU fields plus a one-frame `didCrossSectionBoundaryThisFrame` flag (set when `sectionIndex` changes; re-baselined on the first observation and on `reseed`).

**This increment delivers + proves the signal ONLY. The structural VISUAL (palette emphasis, pour density, region lean) is Skein.5** — the shipped behaviour after ENGINE.3 is **visually identical to today** (the signal is delivered but unused). That is the byte-identical guarantee in action.

**Call site — the per-frame MIR publish (`setFeatures` site), not the `setMood` site.** The setter is called from `VisualizerEngine+Audio.swift` right after `pipeline.setFeatures(fv)` (where `mir.process` two lines above just refreshed `mir.latestStructuralPrediction`), **not** inside `publishMoodResult` alongside `setMood` as the session prompt's recon suggested. Rationale (the audit's deliberate refinement): the `setFeatures` site is **unconditional per-frame** — the `setMood` path early-returns when the mood classifier is absent or `classify` throws, which would intermittently stall the section signal — and structure is conceptually a per-frame MIR output (a sibling of `setFeatures`), not an accumulated mood-classifier result. Both honour the binding constraint (route through `RenderPipeline`; never read `mirPipeline` on the render thread). Resets to `.none` on preset switch (the `applyPreset` teardown, beside `setMVWarpWetnessDecay(1.0)`); track change is covered by the per-frame push (`MIRPipeline.reset` → `.none`) plus `SkeinState.reseed` clearing its own section tracking.

**Rejected — option (B): extend the `meshPresetTick` callback signature** to `(FeatureVector, StemFeatures, StructuralPrediction)`. Cleaner conceptually but touches `RenderPipeline` (the type), `+Draw` (the call), `+PresetSwitching` (the setter), both `VisualizerEngine*` wirings, `SkeinState`, and the test, and forces every future mesh-preset tick to carry structure — higher blast radius for no functional gain over (A), which is provably thread-safe (the `setMood` lock proves it).

**Byte-identical guarantee.** The setter defaults to `.none` and **only `SkeinState` reads it**; no shared GPU code, no feedback-format change, no `FeatureVector` change, no GPU buffer write. `PresetRegressionTests` (20 presets × 3 conditions) + the Dragon Bloom / Fata Morgana MVWarp accumulation suites stay byte-identical; `PresetLoaderCompileFailure` count intact (FA #72). Even Skein's own render is byte-identical: the stored structure lives in CPU-only fields that `writeToGPU` never touches.

**Consequences.**
- New gate `SkeinStructureSignalTests` (FA #66, live path): drives the real `setStructuralPrediction`/`latestStructuralPrediction` bridge on a real `RenderPipeline`, invokes the stored `meshPresetTick` exactly as `RenderPipeline+Draw.swift:120` does, and asserts the section index/confidence reach `SkeinState` and that a `sectionIndex` increment raises the boundary flag for exactly one frame; plus a `reseed`-clears-tracking gate.
- `SkeinState`'s structural accessors + the `ingestStructure` helper + the `centroid`/`attackRatio` per-stem accessors moved to a same-file extension to keep the class body within the SwiftLint `type_body_length` budget (the file's documented pattern).
- Skein.5's structure sub-feature now depends on this signal (it consumes `currentSectionIndex` / `didCrossSectionBoundaryThisFrame` / `sectionConfidence`, gated on `confidence`).

**References.** The `setMood`/`latestFeatures` value-injection bridge (D-024 / D-025, FA #25 — the never-write-back-mood rule); D-027 (mv_warp, the path Skein rides); D-137 (the gated-or-beachball byte-identical discipline); FA #59/#60 (infra before preset, never bundled); FA #66 (verify the live path, not just a unit); `RENDER_CAPABILITY_REGISTRY.md` ("structural-section signal reaches the preset tick" → Supported, gated/byte-identical); `SKEIN_PLAN.md` / `ENGINEERING_PLAN.md` (the Skein.ENGINE.3 rows). Skein.5 consumes it next.

## D-152 — Skein.5 musicality layer: mood frozen at lay-time, structure biased through pour offsets, anticipation as τ-warping, locus display-only

**Date:** 2026-06-09 · **Increment:** Skein.5 · **Status:** Ratified

**Decision.** The Skein.5 sub-features each route through a mechanism chosen so the lossless canvas-hold invariants survive:

1. **Mood is applied AT LAY TIME and frozen.** `SkeinState` EMA-smooths `features.valence/arousal` (τ = 4 s, FA #25 — never written back) and `moodTinted(_:)` warms/cools + saturates the LINEAR palette colour at the moment a breakpoint or burst is pushed. The tint is multiplicative on vivid colours (bounded ±18 % R / ∓16 % B, saturation floor 0.85) — never the `mix(cream, hue, sat)` anti-pattern — so the pale-tone ceiling is structurally safe (measured pale share 0.003). Because the canvas holds losslessly, lay-time freezing means **the finished painting archives the song's emotional arc** — a chorus's strokes stay warm after the song cools. Valence = 0 ⇒ exact identity (silence + all pre-Skein.5 tests byte-identical).
2. **The structural region lean routes through the existing per-pour breakpoint offsets** — never a per-frame displacement of the painter position. The closed-form tail is REDRAWN every frame, so any per-frame position modulation would repaint the 40-frame tail shifted (smear); a pour-start offset is captured once and frozen (the Skein.4.1 mechanism). On a confident boundary (`confidence` smoothstep-gated 0.25→0.55; below ⇒ exactly zero bias, the pure allover read): a density pulse (refractory ÷ (1 + 1.2·pulse), τ = 2.5 s decay), a boundary-forced fresh pour (floored at 1.0 τ dwell so D-150 long pours survive), and a lean target at `seed + (sectionIndex mod 5) · goldenAngle`, radius ≤ 0.085 UV, EMA-approached (τ = 2.5 s) — repeated section slots revisit the same patch and build density. Per-section warmth emphasis (± 0.10 valence-equivalent, alternating slot parity) rides the same gate.
3. **Anticipation is τ-speed warping** (FA #33 — beat PHASE, not onset): wind-up `1 − 0.45·smoothstep(0.70, 1, beatPhase01)`, flick release `+0.90·exp(−t/90 ms)` at the wrap. KEY property: τ-warping keeps every tail sample exactly ON the trajectory curve — samples move ALONG the curve, never laterally — so the held line cannot smear, by construction. `mix(1, factor, stemMix)` ⇒ exactly 1.0 at silence (the Skein.1 continuity gate byte-holds). Cold-start-safe: a wrong cached phase reads as a mistimed hesitation, not a wrong-beat firing.
4. **The locus is display-only at the comp stage.** The prompt's suggested site (`skein_geometry_fragment`) would BAKE the glow into the held canvas permanently; the correct site is `skein_comp_fragment` (display-only, the FA #70 contract). Plumbing: the blit pass gains a gated `bindCompStagePresetBuffer` (the slot-6 preset buffer at fragment buffer 1 — the ENGINE.2 inert-binding precedent; nil ⇒ nothing bound, every other preset byte-identical). The glow carries a soft occlusion shadow ring (an object hovering above a surface casts one) so it reads on cream AND on paint. Build-flagged via `SkeinState(locusEnabled:)`, default `false`; gate `test_locus_displayOnly` proves canvas byte-identical flag-on vs flag-off.

**FA #67 audit.** The painter MOTION path is ONE visual channel consuming three timescales (broadband-dev s-scale, arousal ~10 s envelope, beat-phase sub-s) — multiple timescales into one channel is allowed; the rule forbids one timescale into two channels. The splatter TRIGGER stays per-stem onset; arousal/pulse only scale its density envelope (the MM global-envelope lesson).

**Evidence (live path, real stems).** Mood: warmth(R−B) 106.4 warm vs 81.4 cool, coverage +24 % with +arousal, pale 0.003. Structure: spawns 88→144 across a boundary on IDENTICAL tiled audio; lean 0.083 ≤ 0.085; conf 0.05 ⇒ all-zero bias. Anticipation: wind-up mean 0.649 / flick mean 1.627; silence exactly 1.0 every frame. Locus: 24-pixel localized blit glow, canvas byte-identical. All prior Skein gates + DB/FM + PresetRegression + loader count green; BUG-035 fixed first so the consumed signal is sane past 600 frames.

**References.** D-147 (stem palette), D-149 (wetness), D-150 (colour-per-stroke + min-dwell), D-151 (the structure bridge this consumes), BUG-035 (the dedup fix gating this increment), FA #25/#33/#67/#70, SKEIN_DESIGN §1.3/§1.5/§8, SHADER_CRAFT §18.10.

**AMENDED 2026-06-09 (Skein.5.1, Matt M7 on session `2026-06-09T22-35-09Z`: "a different white line pattern at track start… white disturbs the colour palette").** The Skein.1-era white-baseline pour is retired: the breakpoint ring now starts EMPTY (no white baseline); the shader draws no line at all until the first coloured pour commits (`breakCount == 0` skips Layer A); the first commit waits a short settle (`firstPourSettleTau = 0.25` τ ≈ ¼ s of smoothed evidence — the D-150 decisiveness principle applied to the first commit, replacing the one-frame argmax that picked flicker colours) and then RETRO-COLOURS the whole pre-commit tail via `tauStart = 0` — the painting's first stroke appears already in the lead stem's colour, continuous from the start point (the first pour carries no jump; jumps separate pours and there is no previous pour). The painter CLOCK now pauses at true silence (`activity = max(stemMix, smoothstep(0.01, 0.04, fvEnergy))` multiplying paint speed — the wetness-pause semantics): no music, no paint; a mid-track pause freezes the painter instead of slowly drawing. The Skein.1 "white line accumulates at silence" invariant is deliberately retired; the inverted gates are `!hasWhiteTexel` (calm-stem + real-stem runs) and `silence-run painted == 0`. The white squiggle's root cause: at canvas birth most of the 40-frame tail resolved to the white-baseline era (including negative-ctau samples), baking a tail-length white piece the lossless canvas kept forever, displaced from the first coloured pour by its jump — different each track via the per-track seed.

## D-153 — FBS Stage 1: a steady, first-NOTE-anchored, cached-tempo beat pulse (`pulsePhase01`/`pulseAmp01`) drives Ferrofluid Ocean's spike punch; never drift-corrected

**Date:** 2026-06-09 · **Increment:** FBS Stage 1 · **Status:** Ratified (pending Matt's Stage-1 read on a live session)

**Decision.** FFO's spike height drops the `0.8 × clamp(f.bass)` per-frame term (the "frozen spikes" root cause — the AGC holds `f.bass` near-constant; motion std 0.044–0.09 on bass-light material — and the residual post-BUG-038 sparkle source) and instead punches on a new engine primitive, `BeatPulseClock` → `FeatureVector` floats 40–41 (reclaimed `_pad4`/`_pad5`, byte-identical layout for fields 1–39):

1. **Anchor = the track's first NOTE** (silence→sound, 3-frame confirm, backdated to the run's first frame) — Matt's correction over "first strong hit," Stage-0-verified: music starts on the one; the silence→signal transition is the cleanest detectable event and is robust to quiet/building intros. Cross-clock PCM gate: anchor lands ~2 ms from the raw-tap first note on the purpose-recorded Cherub session.
2. **Tempo = the cached BeatGrid BPM** — the trustworthy half of the grid (Stage 0: ~1 % err, reproducible ×6 captures). Grid PHASE is cross-capture-unstable and is NOT consumed.
3. **Dead steady, never corrected** — deliberately independent of `LiveBeatDriftTracker` (its correction wanders 50–90 ms over the opening and broke Love Rehab's good start). A steady pulse wrong-by-a-hair beats a wandering pulse right-on-average. Stage 3 may add a bar-boundary handoff; nothing corrects Stage 1.
4. **`pulseAmp01` gates** (0 before the first note / across > 0.5 s sustained silence; 1 while music plays; ~250 ms ramps) — no punching into a silent room. Stage 2 scales it by live energy.
5. **Envelope in the shader** (rise 8 % of the beat, decay to 85 %, rest): headroom-capped at spike strength 1.62, under the CSP.3.5 Lipschitz `/6` ceiling 1.64. One-primitive-per-layer preserved (FA #67): swell×arousal (slow), spikes×pulse (per-beat), aurora×drums-smoothed (hit envelope). No Layer-4 onset signals consumed (those fire ~97 % of frames — BUG-038's root).

**Evidence (real sessions, live dispatch path).** `BeatPulseClockTests` (9): anchor 2 ms vs PCM; every pulse interval == grid period (cumulative drift ~0 vs the tracker's 50–90 ms); envelope motion std 0.198/0.212/0.182 (Lotus/Cherub/SZ2) vs the old term's 0.044 on the frozen streaming case. `FerrofluidPulseLivePathTests`: 110 continuous frames of the real Lotus session through SDF G-buffer → lighting → bloom, paired per-frame A/B delta — punch-window |δ| = 29.3 luma, rest-window 0.0 (beat-locked, zero between-beat flicker by construction). Golden hashes unchanged; full suite green modulo the documented pre-existing set.

**Known limitations (stated, not hidden).** Mid-playlist gapless segues anchor at the track-change instant, not a musical "one" (best-effort); the anchored phase is perceptually-convincing, not provably the downbeat (FA #69's structural limit stands); the toggle off-arm no longer restores the historical `f.bass` drive (Layer 2 is the pulse in both arms).

**References.** FBS kickoff (`docs/prompts/FFO_BEAT_SYNC_KICKOFF.md`), Stage 0 findings (`docs/diagnostics/FBS_STAGE0_FINDINGS_2026-06-09.md`), BUG-038 (the flicker pre-step), FA #4/#27/#66/#67/#69, D-099 (struct-extension pattern), CSP.3.x (the spike-driver history this supersedes).

## D-154 — FBS course-correction: beat-irregular tracks are hard-excluded from beat-locked presets (FFO never sees them); the pulse becomes a SLOW 4-beat heave

**Date:** 2026-06-10 · **Increment:** FBS.S2 · **Status:** Ratified (Matt's product direction, 2026-06-10)

**Context.** The Stage-1 live verdict (session `2026-06-10T03-02-32Z`, addendum in `FBS_STAGE0_FINDINGS_2026-06-09.md`) was negative on a streaming playlist: the per-beat punch from an arbitrary anchor (gapless track switches) read as a robotic metronome, and Pyramid Song — rubato, no steady beat — regressed (confident regular thump on an irregular song). Matt also corrected scope: the pulse was always the COLD-START bridge, not the whole-track driver. His direction: *"Not all songs are a fit for FFO… exclude them, they should never see the FFO preset. Slow pulse probably works for (1). We can gradually improve… iteratively, incrementally over time."*

**Decision.**

1. **Beat-regularity hard exclusion at the preset picker.** `assessBeatIrregularity(gridBPM:drumsBPM:barConfidence:)` (Session/BPMMismatchCheck.swift): octave-folded disagreement between the full-mix and drums-stem Beat This! grids > 10 %, OR grid bar-confidence < 0.2, ⇒ irregular. Calibrated on the real cached catalog (38 tracks): kept tracks fold to ≤ 9.2 % (Love Rehab 0.7, There There 0.4, Money 0.6, Cherub 9.2); excluded ≥ 11.3 % (Pyramid 17.4, SZ2 11.3, Tras 3 13.3, Mingus 49). The MIR estimator is NOT consulted (it disagrees 8–11 % even on solid-beat tracks — cannot discriminate). Octave folding keeps legitimate half/double-time drum grids regular (119.8 vs 60.7 → 2.6 %). Plumbing: `TrackProfile.beatIrregular: Bool?` (optional — old persisted profiles decode as unknown) + `PresetDescriptor.requiresRegularBeat` (`requires_regular_beat`, set on FerrofluidOcean.json) + a `beat_irregular` hard exclusion in `DefaultPresetScorer`. Reaches ALL selection paths: planner (initial + regenerate), reactive (`evaluate(currentTrackBeatIrregular:)` — also evicts FFO if it is current when the gate fires), mood-override repatch (plan profile carries the flag). Manual preset selection is deliberately unaffected. nil/unknown = permissive — exclusion requires evidence.
2. **Slow pulse: the cycle is FOUR beats** (`BeatPulseClock.pulseBeats = 4`), ~2 s at 120 BPM. A per-beat punch from an arbitrary phase is maximally falsifiable; at 4-beat rate the same error reads as a gentle oceanic heave at a musical rate, and sub-1 % tempo error smears phase 4× slower. Fixed 4 beats, NOT the grid's detected meter (meter detection is itself unreliable; the pulse claims no downbeat alignment).
3. **Iterate incrementally** (Matt's framing): no big-bang handoff build; FFO improves over small increments, each with a live look.

**Known gaps (stated).** Swing feel is invisible to the gate — So What's estimators agree perfectly (135.5/135.5, conf 1.0) yet a metronome pulse isn't that song's pulse; catching it needs a different signal (future iteration). The Mingus track (Matt's best-performing for the OLD continuous-bass FFO) is excluded by the gate (49 % fold) — flagged to Matt explicitly. The 10 % threshold sits in a thin observed gap (9.2 vs 11.3) — tune as data accumulates.

**Evidence.** `BeatRegularityExclusionTests` (real catalog values; scorer + reactive exclusion; FFO sidecar flag gate). `BeatPulseClockTests` updated to the 4-beat period (all real-session gates still green: anchor 2 ms, zero wander, motion ≥ frozen baseline). `FerrofluidPulseLivePathTests` green with the slow pulse (punch |δ| = 31.1 luma, rest 0.0 through the live dispatch). Full suite: only the documented timing flakes (SoakTestHarness / MetadataPreFetcher wall-clock budgets under parallel load — both pass isolated).

**References.** D-153 (the pulse), FBS Stage-1 verdict addendum, FA #57 (gates specced against real data — the calibration table), Matt 2026-06-10.

> **AMENDED 2026-06-11 (FBS.S5c — the FFO ban is RETIRED).** Matt watched FFO on Pyramid Song — the gate's canonical catch — in session `2026-06-11T01-56-22Z` and ruled: *"Remove the FFO ban for Pyramid Song - it looks and moves great!"* Asked retire-entirely vs soften-to-preference; **Matt picked retire entirely.** The session data explains why the ban's premise failed: the live drift tracker **LOCKED on Pyramid at te 5.4 s** (faster than any regular track that session; locked for 61 % of the segment) — the 47.7 % grid-vs-drums disagreement that flagged the track condemned the drums-stem estimate, not the 70 BPM grid FFO actually uses (Pyramid genuinely sits at ~68–70 BPM). Both gate catches Matt has watched (Pyramid, Mingus) looked good, and the post-D-156/157/158 FFO degrades gracefully on unreliable beats (gentle global heave; per-beat punches only after lock or the 10 s window). **Implementation:** `requires_regular_beat` removed from `FerrofluidOcean.json` — no production preset declares it. The MECHANISM (descriptor flag, scorer/planner/reactive hard exclusion, `assessBeatIrregularity` → `TrackProfile.beatIrregular` signal) stays, tested via synthetic presets, available to future presets and as diagnostic data. `test_realFFOSidecar_doesNotDeclareRequiresRegularBeat` pins the retirement — re-adding the flag to FFO requires a new product decision. The D-154 known-gaps list (swing invisibility, threshold tuning) is moot for FFO while no preset declares the flag.

**Date:** 2026-06-10 · **Increment:** Skein.5.3 · **Status:** Ratified (Matt's curation + picker choice, 2026-06-10)

**Decision.** Skein paints each track in ONE palette chosen from a curated library, replacing the single Full Fathom Five register:

1. **The library** (`SkeinPaletteLibrary.candidates`, display sRGB): `fathom` (the shipped default, index 0), `nocturne` (ink blue-black / deep violet / moonlit gold / ice blue), `jewel` (deep violet / crimson / saffron / emerald), `inkpop` (near-black / cobalt / hot orange / magenta), `electric` (violet charcoal / magenta / acid orange / cyan). Matt curated from six rendered candidates on identical seed-0 real-stem paintings; `terra` (umber/rust/gold/sage) was cut.
2. **Fixed role grammar** — in EVERY palette: drums = the darkest ink, bass = the deep heavy saturated weight, vocals = the warm bright lead, other = the contrast accent. The colour→stem vocabulary stays learnable across palettes even as hues change (the trade-off that otherwise argues against a library).
3. **Picker = per-track, deterministic** (Matt's choice over mood-matched): `SkeinPaletteLibrary.entry(forTrackSeed:)` = `seed % count`, fed by the SAME FNV-1a track identity that seeds the painter trajectory — the same song always paints the same painting in the same colours (§5.7 extends to colour), and a playlist rotates the library naturally. LIBRARY MODE engages only when `SkeinState` is constructed without an explicit palette (the live app path); explicit palettes (every test fixture, the contact-sheet candidates) stay pinned forever, and `reseed` re-picks only in library mode. Seed 0 → `fathom`, so all no-palette fixtures are byte-identical to pre-library behaviour.
4. **Curation gates** (`SkeinPaletteLibraryTests`, always-on): every entry stays pairwise-separable — including vs the cream ground — at the rendered-display level across the FULL Skein.5 mood-tint swing (valence −1…+1 through the EXACT production transform, `SkeinState.moodTint` extracted static for this); pale-tone ceiling per ink; role grammar (drums darkest); `fathom == defaultPalette` byte-equality; picker determinism + reseed re-pick + explicit-mode pinning.

**Trade-off accepted.** Per-palette character variation (e.g. nocturne's violet bass vs fathom's oxblood) means M7/cert evidence must sample multiple palettes; Skein.6's ≥5-track M7 naturally covers ≥5 palette draws via distinct tracks.

**References.** D-147 (stem palette + the legibility binding constraint), D-150/D-152 (the colour-freeze + lay-time mood tint the library rides), D-LM-palette-library (the Lumen Mosaic precedent Matt pointed at), SKEIN_DESIGN §1.2 ("the palette is open — a tunable"), SHADER_CRAFT §18.8.

## D-155 — Skein.5.3 palette library: five Matt-curated palettes, fixed role grammar, deterministic per-track picker

> **Restored at DOC.4 (2026-06-11):** this entry was accidentally deleted by the parallel FBS.S5c commit (`5ac5ad90`, 2026-06-11) while the adjacent D-154 amendment was edited — found by the DOC.4 cross-reference sweep (`git log -S` evidence). Text restored verbatim from `5ac5ad90~1`, including the 5.3b amendment.

**Date:** 2026-06-10 · **Increment:** Skein.5.3 · **Status:** Ratified (Matt's curation + picker choice, 2026-06-10)

**Decision.** Skein paints each track in ONE palette chosen from a curated library, replacing the single Full Fathom Five register:

1. **The library** (`SkeinPaletteLibrary.candidates`, display sRGB): `fathom` (the shipped default, index 0), `nocturne` (ink blue-black / deep violet / moonlit gold / ice blue), `jewel` (deep violet / crimson / saffron / emerald), `inkpop` (near-black / cobalt / hot orange / magenta), `electric` (violet charcoal / magenta / acid orange / cyan). Matt curated from six rendered candidates on identical seed-0 real-stem paintings; `terra` (umber/rust/gold/sage) was cut.
2. **Fixed role grammar** — in EVERY palette: drums = the darkest ink, bass = the deep heavy saturated weight, vocals = the warm bright lead, other = the contrast accent. The colour→stem vocabulary stays learnable across palettes even as hues change (the trade-off that otherwise argues against a library).
3. **Picker = per-track, deterministic** (Matt's choice over mood-matched): `SkeinPaletteLibrary.entry(forTrackSeed:)` = `seed % count`, fed by the SAME FNV-1a track identity that seeds the painter trajectory — the same song always paints the same painting in the same colours (§5.7 extends to colour), and a playlist rotates the library naturally. LIBRARY MODE engages only when `SkeinState` is constructed without an explicit palette (the live app path); explicit palettes (every test fixture, the contact-sheet candidates) stay pinned forever, and `reseed` re-picks only in library mode. Seed 0 → `fathom`, so all no-palette fixtures are byte-identical to pre-library behaviour.
4. **Curation gates** (`SkeinPaletteLibraryTests`, always-on): every entry stays pairwise-separable — including vs the cream ground — at the rendered-display level across the FULL Skein.5 mood-tint swing (valence −1…+1 through the EXACT production transform, `SkeinState.moodTint` extracted static for this); pale-tone ceiling per ink; role grammar (drums darkest); `fathom == defaultPalette` byte-equality; picker determinism + reseed re-pick + explicit-mode pinning.

**Trade-off accepted.** Per-palette character variation (e.g. nocturne's violet bass vs fathom's oxblood) means M7/cert evidence must sample multiple palettes; Skein.6's ≥5-track M7 naturally covers ≥5 palette draws via distinct tracks.

**References.** D-147 (stem palette + the legibility binding constraint), D-150/D-152 (the colour-freeze + lay-time mood tint the library rides), D-LM-palette-library (the Lumen Mosaic precedent Matt pointed at), SKEIN_DESIGN §1.2 ("the palette is open — a tunable"), SHADER_CRAFT §18.8.

## D-156 — FBS.S3: after ~10 s the pulse hands off invisibly to the live drift-tracker beat (per-beat punches — the energetic steady state); the slow bridge covers only the opening

**Date:** 2026-06-10 · **Increment:** FBS.S3 · **Status:** Ratified (implements Matt's "slow pulse for the start… we need something more energetic" direction, 2026-06-10)

**Decision.** `BeatPulseClock` becomes a two-state machine:

1. **Bridge (track open):** unchanged D-153/D-154 behaviour — first-note anchor, cached tempo, slow 4-beat heave, never corrected. Covers the window where the live tracker wanders and the stems converge.
2. **Handoff (once, per track):** after `handoffAfterS` (10 s) past the anchor, the pulse swaps its phase source to `LiveBeatDriftTracker`'s per-beat `beatPhase01` — but ONLY at a frame where BOTH the outgoing bridge phase and the incoming live phase sit in the punch envelope's REST window (≥ 0.85 of the cycle, where the envelope is zero — the constant mirrors the decay-end in `fo_spike_strength`; both sides are cross-annotated). The envelope is zero on each side of the swap ⇒ **the seam is invisible by construction**, no crossfade needed.
3. **Steady state:** per-beat punches following the live beat — including its small continuous corrections, which at punch rate read as timing breath, not stutter (the gross corrections happen in the opening, which the bridge covers). Grid cleared mid-track ⇒ falls back to the bridge metronome rather than going dark. `resetAnchor()` (track change) returns to the bridge, so every track re-opens slow.

Reactive mode with no grid: no live phase is offered, the bridge keeps running (no handoff). The MIRPipeline pulse update moves AFTER the drift-tracker block so the live phase is current-frame.

**Evidence (real session replay, `loverehab_handoff_2026-06-10T14-55-32Z` fixture — 40 s of Love Rehab with the recorded live `beatPhase01`).** `test_handoff_swapsToLiveBeat_invisibly_onRealSession`: handoff fires ≥ 10 s, in the rest window on both sides; post-handoff phase equals the recorded live phase exactly; the envelope's max frame-to-frame step around the swap stays within its natural attack slope (bound 0.65 — sized for real frame-time jitter; a bad mid-punch swap would step ≈ 1.0); the bridge ticked at exactly the slow 4-beat period before the swap. Plus no-grid/no-handoff and per-track reset gates. Live-path GPU suite green.

**Known risk (stated).** The steady state inherits the live tracker's quality: on tracks where its phase is wrong or breathing visibly, the per-beat punches will show that. That is the next live read's question — and the gate (D-154) already keeps the worst tracks (beat-irregular) off FFO entirely.

**References.** D-153 (the pulse), D-154 (exclusion + slow bridge), FBS kickoff §Stage 3, Matt 2026-06-10.

**AMENDED 2026-06-10 (Skein.5.3b — Matt's round-1 curation rejection + round-2 re-curation).** Round 1 was rejected on process and content: the candidates were invented hue sets (not AbEx-anchored), all shared a warm-gold lead (too similar), "nocturne" wasn't cool, and the canvas GROUND had been held fixed silently — "Why does the background color of the canvas need to be beige for all color palettes?" The redo: (1) **the ground is part of the palette** — `Entry.ground`, plumbed end-to-end (SkeinState carries + re-picks it per track; a `float4` LINEAR ground rides the slot-6 buffer as a second additive tail at offset 2752 so the comp paint-mask tracks it; a gated `mvWarpCanvasGroundOverride` makes the canvas wipe AND the resize re-clear use the track's ground; nil ⇒ byte-identical for every other preset); (2) **every entry is anchored on a NAMED work** (`Entry.anchor`); (3) the role grammar generalises to *drums = the starkest structural ink VS THE GROUND* (black on light, bone on dark); (4) gates are ground-aware (separability vs THIS entry's ground across the mood swing — caught two real collisions during tuning; grounds decisively light/dark; ≤1 pale highlight ink). **Final Matt-curated library (round 2): `fathom` (Full Fathom Five, cream) + `poles` (Blue Poles, dark indigo) + `nocturne` (all-cool night slate) + `ember` (Rothko Four Darks in Red, maroon-black).** Round-2 cut `autumn`/`convergence`: "both too similar to one another and to fathom" — on a pale ground with a black structural ink the GROUND dominates the gestalt, so multiple light palettes collapse into one impression; a future light-ground candidate must differ at the ground level, not the inks. Process lesson recorded in memory `feedback-palette-curation-process`.

> **AMENDED 2026-06-10 (FBS.S3.1, same day) — two defects from Matt's live read (session `2026-06-10T17-21-49Z`):**
> 1. **The rest-window swap condition was structurally broken.** Bridge and live phase derive from the SAME tempo, so their relative offset is frozen — the narrow phase-window coincidence either fires every cycle or NEVER. Money: **zero eligible frames in 63 s**; the track stayed on the bridge for its entire playback (Matt: "It never moved over… only the pulse was present"). Love Rehab et al. simply drew lucky offsets. Replaced with an **envelope-floor condition** (both envelopes < 0.15): the bridge's low-envelope span covers > 1 full live cycle of time, so a joint-low frame exists in EVERY bridge cycle — guaranteed, with the seam step bounded by the floor. Regression-locked by `test_handoff_firesOnMoney_theStructuralCounterexample` (replays Money's recorded series; red under the old condition).
> 2. **The per-beat punch attack read as FLASHING.** The 0.08-of-cycle attack spans ~37 ms at song tempo = 1–2 frames — a near-single-frame spike-height + reflected-light step. Measured: 8–10 envelope steps > 0.65/min on every handed-off track — and ZERO on Money, the one track with no flashing complaint (the bridge's 4-beat attack is gentle). Attack lengthened to 0.20 of the cycle (~100 ms at 120 BPM) — still a punch, never a frame-strobe. `BeatPulseClock.envelope` is now the cross-annotated CPU authority for the shader envelope shape.
> The track-start aurora warmup (BUG-041/S2.2) remains in place; this session's session-wide flashing is attributed to the punch attack on the Money-control evidence — Matt's next look adjudicates.

## D-157 — FBS: the beat punch gets a spatial footprint — each beat, smoothly-bounded REGIONS of the spike field punch (~⅓, re-drawn per beat); the global frame luminance stays steady

**Date:** 2026-06-10 · **Increment:** FBS.S4 · **Status:** Ratified (Matt chose option B: "B is good")

**Context.** The first full-session video (BUG-039 recovery) enabled a pixel-level census: 373 flash events across every track at ~beat cadence. The forensics ablation matrix was conclusive — full replica 69 flash steps on the So What window; **pulse OFF → 0**; aurora OFF / light frozen → unchanged. The flashing IS the global beat punch: the whole spike field leaping each beat swung the entire frame's mean luminance 6–84 (0–255) — geometry-as-rhythm reading as luminance-as-strobe, while the same mechanism was the beat-sync Matt praised on Money.

**Decision.** `fo_spike_strength` gains a position argument and multiplies the punch envelope by a **smooth per-beat regional mask**: value noise over xz (patch scale ~2.5 wu, smoothstep band 0.55–0.80 ≈ ⅓ of the field active), domain-shifted by `pulse_beat_index` (new FV float 42, reclaimed `_pad6`; counted by `BeatPulseClock` — metronome cycles on the bridge, live wraps after handoff, reset per track). Baseline posture and the swell are untouched; the punch cap drops 1.62 → 1.55 to keep the mask's added height-field gradient inside the CSP.3.5 Lipschitz /6 budget.

**Acceptance (the same instrument that convicted the punch).** Re-render of the convicting So What window: whole-frame flash steps **69 → 1** (total magnitude 734 → 6.4); localized punch motion **preserved and strong** (top block deltas ≈ 65 with the punch vs ≈ 22 ambient); no white-pixel bursts (Lipschitz margin held); live-path paired A/B: global punch |δ| 28 → 8.7 luma with rest-window exactly 0 (still beat-locked). All FBS suites + goldens green.

**References.** D-153/D-154/D-156 (the pulse), BUG-039 (the video evidence chain), the 2026-06-10 forensics commits, Matt's option-B pick.

## D-158 — FBS.S5: the remaining flasher was the vocals-pitch → aurora-HUE route (proven by ablation); aurora transitions slow to Matt's 8–10 s (hue CPU-side τ≈3 s EMA + intensity τ 2.7/3.3 s), and the bridge heave goes back to GLOBAL with regional punches only after the handoff

**Date:** 2026-06-10 · **Increment:** FBS.S5 · **Status:** Implemented per Matt's three S4 directives (session `2026-06-10T19-13-14Z` read); awaiting his live read

**Context.** After D-157, flashing was "still present, prominent on some tracks" (census ~150 → 79 clustered events). The decisive S4 finding: on the So What te 31–41 window the VIDEO showed 72–84-luma flashes but the forensics replica reproduced almost nothing — the flasher lived in an un-replicated route. The replica's known gap was vocals pitch → aurora hue (`vocalsPitchHz`/`vocalsPitchConfidence` never set in the harness), and Matt independently perceived "aurora color shifting too quickly."

**The proof (S5 forensics, before any fix).** Replicating the two pitch fields from `stems.csv` took the replica from 1 → **13** whole-frame flash steps on So What 31–41 and 0 → **15** on Lotus 45–51; a new `aurora-hue` ablation arm (zeroing ONLY those two fields) restored 1 / 0. Mechanism, visible in the recorded data: pitch confidence crosses the hue gate boundary (smoothstep 0.5→0.7) **~9×/s** on real music (90 crossings in the 10 s So What window), snapping `palettePhase` between the pitch phase and the valence fallback (up to 0.4 of palette phase = across palette stops); at curtain intensity 2.5–5.5 reflected across the whole mirror substrate, each snap stepped the entire frame's luminance.

**Decisions (Matt's directives, implemented).**
1. **Aurora hue moves CPU-side behind a τ ≈ 3 s EMA** (`RenderPipeline.auroraHueStep`, pure fn; same composite pitch/valence math the shader ran per-pixel, now smoothed and shipped as `StemFeatures.auroraPalettePhase`, float 45, reclaimed `_sfPad3`, renderer-transient). A hue transition completes in ~9 s; gate flapping averages to a stable intermediate hue. The fix kills the proven flasher BY DESIGN of the requested character change.
2. **Aurora intensity transitions slow to the same window**: `auroraDriverStep` rise τ 0.45 → 2.7 s, fall 1.2 → 3.3 s (~8 s up / ~10 s down at 3τ). Soft-knee + BUG-041 warmup unchanged. The brightness becomes a slow swell following the track's drum-energy arc, not individual hits.
3. **The bridge heave is GLOBAL again; regional punches only after the handoff** ("the slow opening heave was not visible with regional coverage" + "keep the regional punches"). `BeatPulseClock` ships `regionalBlend01` — 0 on the bridge, ramping 0 → 1 over one 4-beat span after the handoff (no coverage cliff) — via FV float 43 (reclaimed `_pad7`); `fo_spike_strength` mixes `mix(1.0, mask, blend)`. The global per-beat strobe cannot return: blend is 1 by the time per-beat punches drive the envelope (the strobe was a post-handoff phenomenon; bridge-only Money drew no flash complaint in S3).

**Not slowed (explicitly).** The orbit-drift hue rotation (round-61's 2.5 s base revolution on `accumulated_audio_time` ≈ 25–37 s wall-clock per full cycle, ~8–12 s between palette stops) already sits in the directed regime and was Matt-tuned across rounds 55→61; it is untouched.

**Acceptance (the convicting instrument, post-fix).** Four windows of session `2026-06-10T19-13-14Z` re-rendered with full pitch replication: So What 31–41 **13 → 1** flash steps, Lotus 45–51 **15 → 0**, Love Rehab 28–38 **1**, There There 2–10 **0** — with localized punch deltas preserved (top blocks ~45–63). Live-path A/B: the global bridge punch moves the spike field |δ| = 25.3 luma at the heave, 0.0 at rest. New gates: `AuroraHueDriverTests` (flap immunity ≤ 0.005/frame, 8–10 s step response pinned, converged targets match the shader formula), `test_regionalBlend_zeroOnBridge_rampsToOneAfterHandoff` (real Love Rehab session replay). `features.csv` gains trailing `pulse_beat_index`/`pulse_regional_blend01` so future replicas are exact.

**References.** D-153/D-154/D-156/D-157 (the pulse chain), BUG-041 (aurora intensity hardening — stands, was not the flasher), FBS.S5 forensics commits, `docs/prompts/FBS_S5_CONTINUITY.md`.

> **AMENDED 2026-06-10 (FBS.S5b — Matt's pick from the `2026-06-10T20-26-37Z` read).** The live read: flashing "mostly gone" (census 79 → 13 events / 154 s) but the global heave's opening window read as unsynced ("the feeling of sync is mostly lost during this 10s interval"). Census + ablation on the new session attributed the residual cold-start events to **the global bridge heave itself** (pulse OFF → 0; aurora/hue/light → unchanged) — the same whole-frame mechanism D-157 cured mid-track, re-admitted in openings by directive 3; the mid-track paired one-frame blips (3 in 154 s) do not reproduce in the replica (suspected video-encode, not render). Matt chose **C + A** from the presented options:
> - **(C) Intensity τ reverted to 0.45/1.2 s** — the brightness shimmer returns (it was measured flash-safe by the S3.2 gates + S4 ablation and was never the flasher); the HUE stays slow (τ 3 s, the actual fix). Decision §2 above is superseded for intensity; §1 (hue) stands.
> - **(A) Early handoff** (amends D-156's fixed 10 s window): when `LiveBeatDriftTracker` reports LOCKED, the handoff window opens at **4 s** (`BeatPulseClock.handoffEarliestS`; envelope-floor seam condition unchanged); the 10 s window remains the unlocked fallback. Measured on the read session: first lock at te 7.0–8.5 s on all five tracks → expect ~2–3 s earlier handoffs, shrinking both the unsynced window and the heave's flash exposure.
> Gates: `test_earlyHandoff_firesSoonAfter4s_whenTrackerLocked` (real-session replay, locked → handoff in [4, 7) s, seam-safe); forensics windows on the read session unchanged post-revert (cold start 2 steps — the heave, by design until handoff; mid-track 1/1). Full suite 1429 green, app build OK, lint 0.

## D-159 — Skein.6 certification: lightweight rubric, FNV-1a seed ratified, coverage bound amended to never-solid/never-near-empty, canvas soak replaces the audio-path harness for §5.5

**Date:** 2026-06-10 · **Increment:** Skein.6 · **Status:** ✅ **CERTIFIED 2026-06-11** — Matt M7 PASS ("It looks great. Ready to certify", session `2026-06-11T01-56-22Z`). The pre-flip session review surfaced **BUG-046** (the structure sub-feature riding BUG-042's note-scale junk at conf 0.78–0.95 on streaming material — the "structure inert on junk" cert premise held only on local-file material); Matt's pick (a 10 wall-s boundary-spacing guard in `SkeinState`) landed before the flip. First `painterly`-family certified preset.

**Context.** Skein's look was Matt-approved at the 5.4 eyeball gate (three live sessions, 2026-06-10, post-round-2 tune). Skein.6 is gates + docs + the D-142(c) deferred engine touch — no behavioural change. Four certification decisions fell out of making the §5.5/§5.7 contracts executable:

1. **Rubric profile = `lightweight`** (the README rubric-tension flag's expected outcome; Dragon Bloom / D-064 precedent — §12.2/§12.3 assume surface-shaded 3D geometry a 2D painterly feedback preset doesn't have). The automated lightweight gate reads `false` on L2 *by construction*: Skein's deviation primitives (`stems.*EnergyDev`, `midAttRel`, D-026) are consumed CPU-side in `SkeinState` and reach the shader pre-computed via the slot-6 buffer, invisible to the MSL-source heuristic (the Lumen Mosaic slot-8 precedent). Locked in `FidelityRubricTests.expectedAutomatedGate`; Matt's M7 is the load-bearing gate per SHADER_CRAFT §12.1.

2. **Seed source ratified as FNV-1a `title|artist`** (`lumenTrackSeedHash` → `currentSkeinSeed()`), NOT the track SHA-256 the §5.7/§1 design wording proposed. The FNV-1a seed produced every painting Matt approved (Skein.3 → 5.4); rewiring to SHA-256 would silently change every track's painting for zero determinism gain. Design doc + README wording amended; the determinism property itself is unchanged (same track → same seed → same painting).

3. **Coverage bound amended — Matt's decision (2026-06-10, presented with measurements): the approved density stands; §5.7's "typical track ends 60–80 %" is retired** as a pre-implementation estimate. Measured on the approved sessions through the live dispatch path at 900×600: 39 % @ 9 s, 74 % @ 29 s, 80.2 % @ 43 s (longest approved single track), plateau ≈ 87 % @ 100 s — a full track ends ~85–90 %, ground always breathing through (~10–15 %), late paint layering over earlier paint. Live-video cross-check at 29 s confirms harness/live parity. **Coverage fraction is RESOLUTION-DEPENDENT** — the droplet AA radius floor (`max(drr, px·1.5)`) widens sub-pixel satellites at small render targets: the same run reads 94.7 % at 200×200 vs 80.2 % at 900×600. The automated gate (`test_cert_coverageBound`) therefore renders at 600×400 with thresholds calibrated there: < 95 % (never solid; measured 89.6 % on the densest input — tiled multi-track real stems, no wipes) and > 40 % (never near-empty). Any future Skein coverage measurement must state its render size.

4. **The §5.5 soak runs the CANVAS, not the audio path.** `SoakTestHarness` is the headless audio-path harness (memory + frame timing, no render) — it cannot observe canvas banding/drift. The §5.5 gate is `test_cert_soak_twoHourCanvasHold` (`SKEIN_SOAK=1`, ~10 min wall): 432,000 frames = 120 simulated minutes through the live mv_warp dispatch path — 15 min real stems (thin-paint layering), 90 min silence (whole-canvas RGBA byte-identity = the lossless-hold claim at hours scale; wetness alpha holds at silence), 15 min real stems (painting resumes, never-white, ground corner intact). 16-bit canvas fallback only if this gate fails (stop-and-report, not a silent format swap — D-137 GPU-stall-trap territory).

Plus the D-142(c) deferred engine touch: **`PresetCategory.painterly`** + `Skein.json` `family: "painterly"` (audited blast radius: enum case + displayName + count test + sidecar; UI iterates `allCases`, no exhaustive switches elsewhere; orchestrator family logic nil-safe → Skein simply starts participating in family boosts/cooldowns once certified).

**Gates landed.** `test_cert_coverageBound` (180 s live-path run, real tiled stems, 600×400); §5.7 determinism formalised as dHash ≤ 8 across two same-seed live-path runs in `test_seedDeterminismAndReseed` (byte-identity stays the stronger assert; full-track evidence 2×10,800 frames pixel-diff 0 / hamming 0); golden dHash entry in `PresetRegressionTests` (three fixtures identical — static ground, the Nimbus pattern); the §5.5 soak above.

**References.** D-142/D-143 (canvas-hold), D-147 (routing), D-149/D-150/D-152/D-155 (sheen/colour/musicality/palettes), D-064 (lightweight precedent), Matt's coverage pick 2026-06-10, `SKEIN_DESIGN.md §5.7` amendment, `docs/VISUAL_REFERENCES/skein/README.md` rubric resolution.

## D-160 — FBS Stage 2: the beat-punch HEIGHT follows passage loudness (smoothed total stem energy → height scale [0.30, 1.0]); the beat keeps the timing, energy sets only the size

**Date:** 2026-06-11 · **Increment:** FBS.S6 (Stage 2 of the FBS kickoff) · **Status:** Implemented per the Matt-approved kickoff §Stage 2 + his "Sure proceed" (2026-06-11); awaiting his live read

**Context.** The kickoff's Stage 2 contract: per-punch height from live energy — loud → tall, soft → small, a small floor so every beat registers while music plays, nothing at silence (the existing amp gate). Matt's observed motivator: So What's bass+piano intro got the same full-strength punches as the band sections ("too energetic until piano/bass" — S3.1 read).

**Signal selection (measured, not assumed).** On sessions `2026-06-11T01-56-22Z` / `2026-06-10T20-26-37Z`: the AGC'd FeatureVector band sum is FLAT (~0.25) across So What's entire dynamic arc — useless, exactly as FA #31 predicts. The **total stem energy** (drums+bass+vocals+other — the same sum the FFO sky's live gate reads) separates 4×: intro 0.33–0.35 vs band 0.8–1.5; Love Rehab / Pyramid open ≥ 1.1 (no false quiet on strong openings); Lotus ramps 0.64 → 1.3.

**Mechanism.** CPU driver `RenderPipeline.punchEnergyStep` — **symmetric τ 2.5 s EMA** (an asymmetric fast-rise variant was built first and MEASURED WRONG: So What's intro stem sum is bursty — median 0.22, p90 1.28 — and a 0.8 s rise peak-followed the bursts, putting the "quiet" intro at height 0.67 and collapsing the contrast to 1.5×; symmetric 2.5 s tracks the passage mean: intro 0.40 / band 0.99, contrast 2.5×). Ships as `StemFeatures.totalEnergySmoothed` (float 46, reclaimed `_sfPad4`, renderer-transient). Shader mapping in `fo_spike_strength`: `height = mix(0.30, 1.0, smoothstep(0.25, 1.0, total_energy_smoothed))` multiplying the punch term — scale ≤ 1 only reduces, the 1.55 Lipschitz cap holds. Applies to the bridge heave too (quiet openings heave gently). Per-hit drama remains the aurora drums driver's job (0.45 s rise) — no timescale is doubled (FA #67 audit: punch layer = beat phase + passage-loudness size; swell = arousal; aurora = drums-dev sub-second + slow hue).

**Acceptance.** Pure-fn gates (`PunchEnergyDriverTests`): glide-never-step, 3τ transitions, and the real So What fixture replay (intro height 0.40 < 0.5, band 0.97 > 0.85, contrast 2.4×). Live-path pixel gate (`FerrofluidPulseLivePathTests`): same punch frame at intro-level vs loud envelope → punch effect 20.6 vs 48.7 luma (2.4×), floor keeps quiet beats registering. Forensics A/B on the quiet-intro window (new `punch-height` arm pins pre-Stage-2 full height): So What 0–8 s flash steps 3 → 1 (magnitude 27 → 14) — Stage 2 also shrinks the residual cold-start heave flashing. Full suite 1430 green, app build OK, lint 0.

**Open dial (Matt's, at his read):** the floor (how small the quietest punch is — currently 30 % height) and the loud threshold are product constants; both are single numbers in the shader mapping.

---

## D-161: Rulebook restructure + always-loaded token-budget ratchet (RB.1 → RB.3)

**Status:** Accepted (2026-06-11)

The RB series replaced the failure → prose-rule → bigger-rulebook loop with a slim always-loaded core plus mechanized gates and read-on-demand references. Matt's per-entry review (context: `docs/diagnostics/RB1_FA_DN_EXPLANATIONS.md`; audit inventory: `docs/diagnostics/RB1_RULEBOOK_AUDIT.md`) cut CLAUDE.md from ~22,300 to ~6,900 estimated tokens: Failed Approaches 49 → 6 (FA #4 absorbed into §Audio Data Hierarchy in constraint-based form), Do-NOT bullets 57 → 1, ten pointer sections merged into §Handbook Index, preset-session discipline → `PRESET_SESSION_CHECKLIST.md`, U.11 build/test notes → RUNBOOK §Engineering notes; DECISIONS.md 161 → 68 active entries (93 archived to `DECISIONS_HISTORY.md`); ENGINEERING_PLAN completed narratives pre-2026-06-01 → `ENGINEERING_PLAN_HISTORY.md` (headers stay as the status record).

**Standing ratchet rules** (installed in CLAUDE.md §Increment Completion Protocol; budget gated by `DocIntegrityTests`):

1. **Token budget:** CLAUDE.md ≤ 7,000 estimated tokens (`wc -w` × 1.35), one-in-one-out — adding above the cap requires demoting or retiring equal mass in the same commit.
2. **Admission test:** a new always-loaded rule must name the specific mistake it prevents and why no deterministic gate can express it; otherwise it goes to a handbook, a session checklist, or a gate.
3. **Violated twice → mechanize:** the second documented violation of a prose rule converts it — the fix increment ships the gate and demotes the prose to a pointer.

**Reason:** instruction-following degrades as the simultaneously-active rule count grows, and the transcript record shows prose rules failing while loaded (REVIEW.1: README-before-edit at 35 % compliance; BUG-036's three realtime-allocation sites written with the no-alloc bullet in context; the FA #66 fixture/live class recurring with the rule present). Gates and feedback loops beat prose; judgment rules earn always-loaded slots only when they must fire at decision time, before any artifact exists that a gate could check.

## D-162: Doc rotation is mechanized; budgets are gated

**Status:** Accepted (DOC.6, 2026-06-12)

The pruning-pass prose convention failed twice (measured 2026-06-12: EP narratives four weeks past the RB.3 window; KNOWN_ISSUES 71% resolved-history; release notes unrotated at 696 KB). Per D-161 rule 3, it converts to mechanism: `Scripts/rotate_docs.sh` performs the EP §Recently Completed, KNOWN_ISSUES §Resolved, and release-notes monthly rotations deterministically; DocIntegrityTests gates the budgets (EP narrative age ≤ 14 days, KNOWN_ISSUES §Resolved ≤ 50 KB, pre-current-month release-notes content ≤ 50 KB — the active file keeps the current month, which alone measured 72 KB at filing, so the byte budget gates rotation debt rather than whole-file size) and index completeness (DECISIONS §Index, KNOWN_ISSUES §Open Index). Closeout evidence runs the gates. Rotated content moves verbatim to history files and stays searchable; nothing is deleted. The judgment-requiring pruning items (CLAUDE.md section demotion, DECISIONS shipped+uncited rotation) remain manual on the same cadence.

## D-163: Audit keep-list + executableTarget STATUS markers guard dead-code audits

**Status:** Accepted (2026-06-14)

A repo-wide over-engineering audit (2026-06-14) flagged three *certified, planner-pickable* presets (Murmuration, Dragon Bloom, Fata Morgana) and a *deliberately-retained* diagnostic tool (ColdStartVerifier — kept per "keep the tools" at the 2026-05-25 cold-start revert) as dead code. The root cause was a documentation/memory gap, not a code problem: nothing distinguished *active* / *retained-diagnostic* / *actually-dead*, so status was inferable only by guessing — and the "zero production importers" heuristic is structurally wrong for the two classes it hit (CLI tools have no importers by design; a quiet certified preset has no recent commits yet is live). **Decision:** every `executableTarget` carries a `// STATUS: active-tool | retained-diagnostic` marker near the top of its entry file (self-describing files), and `docs/AUDIT_KEEPLIST.md` is the read-first register before any deletion — listing the certified presets, the eight tool CLIs, and the gated dev instrumentation that look dead but are kept, plus an honest "genuinely dead" list whose removal is a separate decision. Per the D-161 admission test this is a judgment rule that must fire at audit time, before any artifact a gate could check exists; rather than spend an always-loaded CLAUDE.md slot (the file sits at ~98.7 % of its token cap), it lives at the source + a read-on-demand doc + memory, adding zero CLAUDE.md mass. A second recurrence would, per D-161 rule 3, justify mechanizing (e.g. a gate that fails when a doc claims a file was deleted that is still on disk, or that shields `certified: true` presets from delete-lists) — premature on first occurrence. Filed alongside a doc-drift correction: `ENGINEERING_PLAN_HISTORY.md` claimed `Scripts/convert_beatnet_weights.py` was already removed when it was still on disk; the D-163 follow-up then actually deleted it (with the dead CoreML stem converter/test pair) and historicized the BeatNet `CREDITS.md` attribution.

## D-164: Photosensitivity flash-safety is an enforced, certifiable invariant — measurement gate now, runtime clamp next

**Status:** Accepted (2026-06-16)

The only open *safety* gap (audit **G9**, P1; the strict-photosensitivity mode **D-054/U.9** deferred). Flash-safety was per-preset/manual convention only (`SHADER_CRAFT` "never edge-trigger on `drums_beat`" + the FFO anti-references) with **no enforced output-side clamp**; distribution (CLEAN.2.5a hardened runtime + notarization path) made it real. **Standard:** Harding / WCAG 2.3.1 general flash — a *flash* is a pair of opposing relative-luminance changes ≥ 10 % where the darker state is < 0.80; unsafe is **> 3 flashes/s** over a large area.

**Decision (Matt, 2026-06-16, two AskUserQuestion picks):** enforce by **measurement now (certification gate), runtime clamp as a deliberate A-next follow-up** — i.e. the hybrid, staged over two increments, *not* a look-altering runtime clamp bundled now (which would force a golden regen + M7 re-review of every certified preset and risk softening the hand-tuned FBS beat-luminance motion of D-157/D-158). The gate is non-destructive, reuses the measurement idea from the FBS flash census, and *proves* the shipping presets safe or finds the ones that aren't.

**What shipped (CLEAN.7.6):** `FlashAnalyzer` (pure Harding/WCAG analyzer on a full-frame relative-luminance sequence; 8 synthetic self-checks pin the semantics) + `PhotosensitivityCertificationTests` (renders each certified preset over a synthetic worst-case 4.5 Hz beat train, measures rendered full-frame luminance, fails cert at > 3 flashes/s).

**Forced-partial finding (the reason this is staged, not complete).** Three premises in the kickoff were false against the repo and were surfaced to Matt before building: (1) the FBS "373-events" A/B *video* was never committed (only 3-band feature CSVs survive) → the analyzer's correctness proof is the synthetic self-check, not a recorded A/B; (2) the `Fixtures/fbs` CSVs are 3-band energy extracts carrying none of the beat/deviation/stem signals that cause flashing, and are not `SessionDataLoader`-compatible; (3) `PresetSessionReplay` is an `executableTarget` the test suite cannot import. The deeper finding came from running the gate: the lightweight single-pass harness drives **only the `FeatureVector`**, so it validly measures only presets that read their music response from it in the fragment pass — **Ferrofluid Ocean and Murmuration (both measured SAFE, 0 flashes/s).** The other five certified presets render **static** here because their music response arrives via paths the harness does not run — CPU follower-state buffers (Lumen Mosaic, Nimbus), the rayMarch multi-pass G-buffer chain (Dragon Bloom, Fata Morgana), or feedback-texture history (Skein). A static render is **never asserted "safe"** (a vacuous pass is the cardinal sin for a safety gate, CLEAN.0); those five are tracked in `unmeasurableInHarness` and the gate **fails loud on drift** (a known-static preset that starts responding, a responsive one that regresses to static, or a new certified preset that renders static). Matt's call (third AskUserQuestion): **ship the partial gate now, fold the rest into A-next** — valid flash-safety for the static set requires the **A-next headless real-`RenderPipeline` harness** (followers ticked + feedback + multi-pass), which is also where the runtime clamp lands. Further documented blind spots (all A-next): full-frame mean only (no regional/area-gating), no saturated-red-flash channel, normal certified regime only.

**Runtime clamp (A-next) — superseded by [D-166] (2026-06-17): evaluated under CLEAN.7.6d and *not pursued* (the certification gate is the enforcement mechanism).** As scoped, it would have been a final full-screen luminance slew-limiter at `RenderPipeline.draw(in:)` *before* the `onFrameRendered` recorder hook, transparent below the danger band; gated behind the OR-flag pattern reserved at `RayMarchPipeline:94` (never assign `reducedMotion` directly). It will move goldens and **requires an M7 re-review of every certified preset** — its own M7 sitting, not a bundle.

**References.** Audit G9 (`CODE_AUDIT_2026-06-13.md:181` + Part C CLEAN.7.6), D-054/U.9 (the deferred strict mode this resolves), D-157/D-158 (the FBS regional-punch / hue-route fixes that made the certified beat-luminance safe — the metric must pass that motion, not flatten it), FA #73 (reuse the forensics machinery, don't rebuild), the kickoff `docs/prompts/CLEAN_7.6_PHOTOSENSITIVITY_KICKOFF.md`.

## D-165: Silent-tap family — detect, don't churn; only rebuild a never-delivered tap

**Status:** Accepted (2026-06-17)

The streaming process tap can deliver persistent silence (a wedged `coreaudiod`; a stale Screen-Recording grant after a re-signed rebuild — BUG-055) or freeze (a device swap stalls the IO-proc — BUG-058). Instrumented live sessions (2026-06-17) corrected two earlier beliefs: the silence is often **environmental, not a Phosphene bug** — but the `.silent → reinstall` recovery was itself **harmful**. It fired on *any* sustained silence, including a user pause, churning the tap; intermittently a recreate came up created-but-dead and never recovered (the visualizer froze with live audio playing). Three decisions:

1. **The reinstall machine only rebuilds a tap that NEVER delivered audio this session** (`SilenceDetector.hasEverDetectedSignal`, RMS-thresholded, reset per `start(mode:)`). A session that *has* had audio and then goes silent is a pause — the working tap is left alone and resumes on its own when audio returns. This keeps recovery for a genuinely broken cold install (BUG-055 / wedged daemon) while removing the pause-churn + dead-tap lottery. Validated 2026-06-17: 3/3 clean pause/resume recoveries on the same tap generation, zero churn. (Supersedes the prior ARCHITECTURE "reinstall on any prolonged silence" behaviour.) The **device-change** reinstall (`SystemAudioCapture.performReinstall`, CLEAN.1.5) is a separate path and is NOT gated — a real default-output change genuinely needs a new tap.

2. **A user-facing detector surfaces "no useful audio is reaching the visualizer" instead of a silent flatline.** `PlaybackErrorBridge` runs a ~1 Hz freshness poll and raises a prominent non-blocking `AudioStallOverlayView` card (a fix ladder) after ~10 s of no fresh audio while playing — catching **both** failure modes: RMS≈0 (`.silent`) AND a frozen IO-proc (tap frame count stops advancing). It is **suppressed on a likely pause** (the same `hasEverDetectedSignal` signal: callbacks advancing + `.silent` + session has had audio) so it only fires on a genuine break, and auto-clears on recovery. Implemented as a **bespoke Bool-driven overlay, not a new `UserFacingError` case** — an enum case plus a presentation mode nothing dispatches on would be ceremony and would churn the 29-case coverage test; the copy is externalized directly.

3. **Doctrine (`feedback_self_healing_over_manual_remediation`): the manual fix-ladder card is a fallback, not the fix.** The end-state must not make a user run Terminal commands or toggle System Settings panes — the user-friendly answer is the app **self-healing** (decision 1) plus stable signing (CLEAN.2.5b). The card is the developer / safety-net surface until then; soften its copy before any public build.

**References.** BUG-057/055/058 (`KNOWN_ISSUES.md`), the kickoffs `docs/prompts/SILENT_TAP_DETECTOR_KICKOFF.md` + `BUG-057_TAP_REINSTALL_SILENCE_KICKOFF.md`, ARCHITECTURE §Audio Capture (tap recovery) + §Module Map (`PlaybackErrorBridge`), UX_SPEC §7.5, memory `feedback_self_healing_over_manual_remediation`. FA #73 (reuse `PlaybackErrorBridge` + the existing reinstall machinery — no parallel detector, no new reinstall path).

## D-166: Photosensitivity runtime clamp not pursued — the certification gate is the enforcement mechanism (amends D-164)

**Status:** Accepted (2026-06-17)

Closes the "runtime clamp (A-next)" half of [D-164] with a decision **not to build it**. CLEAN.7.6d opened to implement the clamp; two facts surfaced once the work started, and Matt chose (two AskUserQuestion picks) to stop at the cert gate.

**Trip-point pick.** Where a clamp *would* engage was set at the **medical limit, 3 flashes/s** (WCAG 2.3.1) — the option transparent to every current preset, acting only on genuinely seizure-risk content. This sets the bar for any future reopening; it is not itself built.

**Why the clamp is not built.**
1. **The cert gate already enforces the 3/s line on everything we ship.** CLEAN.7.6 / 7.6b / 7.6c brought `PhotosensitivityCertificationTests` to **7/7 ENFORCED** — every certified preset is proven ≤ 3/s under a 4.5 Hz beat + stem drive sharper than real music. Phosphene ships *only* certified presets, so shipped content is covered without a runtime clamp. Stage-1 peak-flashes/s, all 7: FFO / Murmuration / Nimbus / Lumen Mosaic / Skein **0.00**, Fata Morgana **0.50**, Dragon Bloom **1.00** — none within a third of the limit.
2. **A uniform clamp is a pipeline-wide change disproportionate to its residual value.** D-164 assumed the clamp could be "a final full-screen pass at `draw(in:)`." The real pipeline has **no single chokepoint**: `renderFrame` (`RenderPipeline+Draw.swift:126`) fans out to **8 terminal paths** (meshShader, rayMarch, postProcess, icb, feedback, mvWarp, staged, drawDirect), each acquiring and presenting *its own* drawable. A uniform clamp means rerouting all 8 through a shared final-target → clamp → present tail — touching every certified preset with regression risk, plus an always-paid per-frame luminance readback + extra pass — for a net that never visibly engages on any shipped content. Its only residual value is content the cert gate cannot see (unfinished pre-cert presets; a theoretical live track past the synthetic worst case). Matt judged the cert gate sufficient and the invasive change unjustified.

**Go-forward.** The **certification gate is the photosensitivity enforcement mechanism** — not a runtime clamp. New certified presets must pass `PhotosensitivityCertificationTests`; its multi-pass set fails loud if a new preset renders static without joining the harness (D-164). The `RayMarchPipeline:94` OR-flag slot stays **reserved**. Reopen only on a new premise — shipping un-certified / user-authored presets, or live arbitrary-source rendering — and reopen *with the 8-path reroute cost in hand* (this entry), do not re-derive it. A non-altering **live monitor** (detect-but-don't-correct) was offered and also declined for now.

**References.** Amends [D-164] (the "runtime clamp A-next" line this closes). Audit G9 (`CODE_AUDIT_2026-06-13.md` §G9 / CLEAN.7.6d), `RENDER_CAPABILITY_REGISTRY §9`, the runtime kickoff `docs/prompts/CLEAN_7.6b_PHOTOSENSITIVITY_RUNTIME_KICKOFF.md` (superseded for the clamp half). D-054/U.9 (the original strict-mode deferral), D-157/D-158 (the certified beat-luminance motion the cert gate must pass, not flatten).

## D-167: Thermal + Low Power Mode feed a quality floor into the frame-budget governor (CLEAN.4.6)

**Status:** Accepted (2026-06-18)

Wires `ProcessInfo` thermal state + Low Power Mode into the [D-057] frame-budget governor so visual load drops *ahead* of the GPU's own thermal throttle, and the user's Low Power Mode choice is respected. Closes audit **G4** (GAP-4) — previously zero `thermalState`/`lowPowerMode` references anywhere.

**Mechanism.** `FrameBudgetManager` gains a `thermalFloor: QualityLevel`; the applied level is `max(currentLevel, thermalFloor)` — independent of the timing hysteresis. A rising thermal state therefore pre-empts the downshift (no waiting for the 3 timing-overrun detection), and clearing it restores quality *immediately* (the timing `currentLevel` was never raised, so no 180-frame recovery wait). The governor stays `ProcessInfo`-free and pure: the listener reads `ProcessInfo` and calls `setThermalFloor`. `VisualizerEngine` observes `thermalStateDidChangeNotification` + `NSProcessInfoPowerStateDidChange`, maps via the pure static `FrameBudgetManager.qualityFloor(thermalState:lowPowerMode:)`, and seeds the floor at FBM creation (in case the app launches already hot / in LPM). The new floor takes effect on the next `observe(_:)` — under render load, the next frame (~16 ms, far ahead of the seconds-scale thermal build-up).

**Mapping (tunable policy).** thermal `.nominal`/`.fair` → `.full` (no floor); `.serious` → `.noBloom` (drop SSGI + bloom); `.critical` → `.reducedRayMarch` (+ 0.75× ray-march steps). Low Power Mode imposes at least `.noSSGI` and never weakens a stronger thermal floor (`max`). Chosen for "meaningful GPU/power relief without gutting the look"; only visible under thermal stress, and tunable in one function.

**Scope.** The `QualityCeiling.ultra` recording exemption (D-057(d), `enabled == false`) still bypasses the floor — recording deliberately wants full quality; overriding that under thermal stress is a separate decision (reopen if fanless recording-under-thermal becomes real). The mechanism is unit-tested (the floor clamps the applied level without touching the timing state; timing can still downshift below the floor; the floor survives `reset()`; the mapping is correct). The actual thermal-induced pre-emption needs **device validation under load** — the Mac mini's active cooling rarely throttles, so this matters mainly for fanless deployment.

**References.** Extends [D-057] (the budget governor). Audit G4 / CLEAN.4.6 (`CODE_AUDIT_2026-06-13.md`). `FrameBudgetManager.swift`, `VisualizerEngine+InitHelpers.swift`, `RENDER_CAPABILITY_REGISTRY` (budget-governor row).

## D-168: ARCHITECTURE Module Map completeness is a gated invariant (CLEAN.7.3)

**Status:** Accepted (2026-06-18)

The Module Map (`ARCHITECTURE.md`) is the per-file behavioural reference read before grep-ing the codebase. Its "every file" claim was unenforced and drifted: the 2026-06-13 audit (T14) found 18 undocumented files; by 2026-06-18 it was **62** — including four entire CERTIFIED presets (Skein, Murmuration, Dragon Bloom, Fata Morgana) and recent infra (FlashAnalyzer, DefaultOutputDeviceMonitor, ConcurrencyAuditProbe, the streaming-artwork cluster). An incomplete "read this before grep-ing" index is worse than none — it reads as authoritative while silently omitting whole subsystems.

**Decision (Matt, via the CLEAN.7.3 scoping question).** Backfill all 62 entries AND mechanize completeness with a gate — rather than a one-time backfill (band-aid; would re-drift) or folding it into CLEAN.7.5. This is the [D-161] ratchet rule 3 ("violated twice → mechanize") applied: the prose contract failed at least twice, so it converts to a test.

**Mechanism.** `DocIntegrityTests.moduleMapCompleteness` walks every `.swift` / `.metal` under `PhospheneEngine/Sources` + `PhospheneApp/` and reds if a file's name-minus-extension is not a substring of the `## Module Map` section. Diagnostic/tooling modules and utility trees are documented as ONE group entry that NAMES its files (the established V.1-noise-tree convention), so a group entry satisfies the gate for all its files. **Accepted ceiling:** substring membership, not entry-line parsing — a short common stem (`main`, `Audio`) can match spuriously, so the gate is permissive (it never false-reds an unrelated increment — the BUG-049 lesson) and targets the real failure mode: a whole file/subsystem added with no mention. Tighten only if spurious passes ever bite.

**Ongoing obligation.** Every new source file under those two roots now needs a one-line Module-Map entry (or a mention in its module's group entry) or the suite reds — folded into the closeout doc-update step the Increment Completion Protocol already requires.

**References.** Extends [D-161] (the ratchet) + [D-162] (DocIntegrityTests as the doc-gate home). CLEAN.7.3 / audit T14 (`CODE_AUDIT_2026-06-13.md`). `DocIntegrityTests.swift`, `ARCHITECTURE.md §Module Map`.

## D-169: Defer public-release-readiness work (extended a11y settings, cold-install resilience) until there is a public build

**Status:** Accepted (2026-06-18)

CLEAN.7.7 (live Reduce-Transparency + Increase-Contrast) and CLEAN.7.8 (cold-install / resource-bootstrap resilience) are **deferred — not built — until Phosphene has a public build.** Both are public-release-readiness features: HIG accessibility-setting support beyond the basics (7.7), and degraded-but-honest first-run for fresh installs (7.8). Phosphene has no public build and no users beyond the developer; the accessibility + robustness BASICS that serve daily single-user dev use are already in place — Reduce Motion is wired + live (`AccessibilityState`, observing `accessibilityDisplayOptionsDidChangeNotification`), VoiceOver labels exist (`AccessibilityLabels`), and the photosensitivity notice + flash-safety certification (G9) are done. Wiring Reduce-Transparency / Increase-Contrast + cold-install resilience for users who do not yet exist is YAGNI.

**Trigger to revisit:** a public-build / release-readiness pass, OR the developer personally running macOS with those accessibility settings enabled (then it degrades a real daily experience and is worth doing).

**Scope.** This defers the audit *gaps* GAP-15 (7.7) and GAP-12 (7.8). It does NOT remove or weaken any shipped accessibility behavior — Reduce Motion's current art + chrome calming stays as-is. Establishes the standing principle: **don't build public-release-readiness features for users who don't exist yet; the bar for daily single-user dev use is the existing basics.**

**References.** CLEAN.7.7 / GAP-15, CLEAN.7.8 / GAP-12 (`CODE_AUDIT_2026-06-13.md`). Matt's call, 2026-06-18.

## D-170: Section detection via McFee/Ellis spectral clustering on a beat-synced 252-bin log-CQT

**Status:** Reversed (2026-06-24) — built (SECDET.1–.6), validated offline, live-tested 3×, then **removed**.

**Reversal (2026-06-24).** Section-aligned transitions were removed and the McFee/Ellis detector + the `~/phosphene_section_lab/` workspace deleted; the planner equal-slices for every track. Two decisive reasons: **(1) Structurally local-file-only.** Section detection needs the whole track, but streaming — Phosphene's primary path — only exposes a 30 s preview before playback (no full-track file exists), so the feature could only ever serve local-file playback, and **no detector, supervised or not, changes that.** **(2) Below the perceptual bar even there.** Live-tested on real tracks it landed at F@3 ≈ 0.29–0.41 — roughly half the transitions wrong, which reads as "awful." Beat-grid-granularity tuning lifts the *offline oracle* to only ~0.58; "feels aligned" needs ~0.70+, which requires a **supervised** model. **★ Premise correction:** the "no-ML / unsupervised" rationale that steered this whole approach was a **misreading** — [D-009] is "no *CoreML*" (use MPSGraph), NOT "no ML." Phosphene already ships supervised nets (Beat This!, Open-Unmix) via MPSGraph; Matt never prohibited ML. If section-aligned visuals on *local files* are ever wanted, the right path is a supervised section model ported to MPSGraph (a Beat-This!-scale effort), not more DSP. The SECDET doc history (this entry, the ENGINEERING_PLAN rows, the release notes) is kept so this isn't re-attempted from scratch on the same false premise.

---
*Original decision (now reversed) follows for the record:*


Phosphene's section detector was novelty-only (Foote checkerboard on a chroma+spectral SSM — `StructuralAnalyzer` / `NoveltyDetector`). Novelty finds *change* points and ignores *repetition*, but a chorus is defined by repeating — so it over-fires on sub-section fills/riffs and under-fires on uniform-loud material (verse≈chorus timbre → no local contrast). This is a structural limit of the novelty *principle*, not a tuning bug (TISMIR 2020 survey), and it is why live transitions never tracked section breaks even after the LFPLAN.1–.8 plumbing was proven correct.

**Decision (Matt, 2026-06-22 directive "identify sections within songs — get this right FIRST").** Replace the offline/cached section source with **McFee & Ellis 2014 Laplacian spectral clustering** (the algorithm in `librosa.segment` / MSAF `scluster`): a k-NN recurrence graph (repetition) fused with a local sequence diagonal (contiguity) → normalized Laplacian → eigen-cluster → section labels → boundaries at label changes. Repetition-aware; fixes both novelty failure modes; produces recurrence labels (the recurring chorus gets the same label) the AI-VJ wants. Fully on-device: pure DSP + Accelerate (CQT/MFCC + LAPACK symmetric eig + hand-rolled Lloyd's k-means). **No ML / no CoreML** ([D-009] preserved) — the chosen methods are unsupervised, so no training corpus is needed; a standard annotated corpus is used only for parameter validation.

**The load-bearing feature finding.** Recurrence must be built on the **full 252-bin log-CQT in dB** (`bins_per_octave=36, n_bins=252`), NOT folded 12-chroma. 12-chroma discards register/voicing → label thrashing → over-segmentation; switching to 252-CQT lifted studio-pop F@3 from 0.36 to 0.82 on the held-out probe. CRP chroma, auto-k, Serrà SF, and CBM were all tested and dropped; **k = 5 fixed** (matches the ~6–10-section use case and beats auto-k, which over-segments studio pop).

**Validation (offline, against ground truth — never live).** Faithful McFee k=5 (252-CQT) beats Foote novelty by ~55–80% on F@3 across three datasets: SALAMI-IA (433 live tracks, F@3 0.29 vs 0.18), Isophonics-Beatles (174 studio tracks, 0.412 vs 0.230), and held-out Nirvana (0.61 vs 0.475). Lab bench + evidence: `~/phosphene_section_lab/` (`BASELINE.md`, `tune_corpus.py`, `precompute.py`). Live-session iteration was retired after it ate 4 sessions — the lab Python is the oracle; the Swift port is correct when its boundaries + F-scores reproduce the lab's on the same tracks.

**Port (SECDET epic, staged).** Stages A (features: beat-synced 252-CQT + 13 MFCC @ 22050 — SSM corr 0.9995 / MFCC corr 1.0), B (graph + LAPACK eigensolve + k-means + boundary merge — F@3 vs lab = 1.000), and C (perf — the flagged ≈2 min/track CQT was a *debug* artifact, 2.7 s in release, so no recursive-CQT port [SECDET.3a]; wire-in [SECDET.3b] — `SectionDetector` replaces `strongBoundaryTimes` in `SessionPreparer.analyzePreview`, validated end-to-end on raw PCM at F@3 = 1.000) are done. **C.4 call (folded here, no separate D-number):** the live `StructuralAnalyzer`'s *boundary* role is retired — section boundaries come from the cached batch detector (like the BeatGrid); its section-*count* role stays (`sectionIndex` → `estimatedSectionCount`, equal-slice fallback), and `boundaryTimestamps`/`boundaryNoveltyScores` remain for diagnostics, unread. The cache schema bump is done (SECDET.3c, v4 → v5). **Stage D done (SECDET.4):** the Swift detector scores **F@3 ≈ 0.41 vs hand-annotated ground truth** on real tracks (Nirvana 0.55 / Beatles 0.40 over a 20-track subset), landing at the lab's published acceptance target (0.61 / 0.41); it reproduces the lab boundaries exactly on most tracks, with a ~0.05 aggregate gap on clustering-sensitive tracks from the kernel-CQT's non-bit-identical features (the recursive CQT would close it — deferred, the bar is met). **Live test 1 → SECDET.5 (full-track beats):** the first live run exposed that **Beat This! truncates its beat grid to a fixed ~30 s window** (`BeatThisModel.tMax` = 1500 frames), so McFee — which beat-syncs on that grid — only segmented the first 30 s of a 282 s track (→ coverage gate → equal slices). Not a detector bug (SECDET.4 used full-track librosa beats); the gap was *beat coverage*, not tracker quality. Fix: `SectionDetector.fullTrackBeats` extends the grid past its last beat at the median inter-beat period so the beat-sync spans the whole track — synthetic beats beyond the tracked region suffice for the recurrence pooling. Offline A/B: 30 s-capped grid + extension scores F@3 0.48, ≥ the full-beat baseline. (Chunking Beat This! over the full track stays the heavier alternative if a tempo-varying track ever needs it.) **Offline port + the full-track-beats fix are validated; the live re-test is the remaining step.** Output contract preserved throughout: `TrackProfile.sectionStartTimes` → the planner is untouched.

**References.** SECDET kickoff `~/phosphene_section_lab/PORT_KICKOFF.md`; McFee & Ellis ISMIR 2014; supersedes the novelty-only section role of `StructuralAnalyzer` (offline path) and the LFPLAN.8 strength-filter dead end. [D-009] (no CoreML). `docs/ENGINEERING_PLAN.md §Phase SECDET`.

## D-171: Nacre — faithful port of `$$$ Royal - Mashup (431)` onto a dedicated custom-warp+comp mv_warp branch (NACRE.2b)

**Decision.** Port the iridescent jello-mirror character of the butterchurn builtin `$$$ Royal - Mashup
(431)` as the certified preset **Nacre**, faithful base FIRST (this increment), the 3 greenlit 2026
uplifts (stem-instrument routing, real thin-film iridescence on HDR, smooth-Voronoi cells) deferred to
NACRE.3+ AFTER Matt's live M7 confirms the base reads as (431) (FA #65 — do not pre-empt/subtract from
the reference before it's proven). Sibling, NOT subclass, of Dragon Bloom ((220)) — a different register
(molten iridescent metal / oil-on-water) despite the shared author/name (D-097).

**Architecture — a dedicated draw branch, mirroring Fata Morgana (D-139), not the 2a convention path.**
The look is a custom feedback warp (reading per-frame uniforms + a wide-blur unsharp) plus a
fully-replacing comp. The shared `encodeMVWarpPass` binds `chromatic@0`/`wetness@1` and no per-frame
uniform to the warp fragment, so overloading it would risk the byte-identity guarantee for every other
mv_warp preset. Instead: `RenderPipeline+Nacre.swift` (`drawWithNacre`/`renderNacre`: warp → comp →
swap), dispatched by a one-field `isNacre` discriminator on `MVWarpPipelineBundle`/`MVWarpState`
(checked before the FM blur heuristic, since Nacre uses no blur target). `NacreUniforms` (96 B) is
computed CPU-side per frame and bound at fragment buffer(1) of both passes (the FM pattern) — so 2a's
`NacreState` (the convention-path comp buffer + `directPresetFragmentBuffer` wiring) was deleted (one
mechanism). The shared path is byte-identical (PresetRegression + DB/FM accumulation green).

**Faithful-base choices (the corrected decode + the renders that drove them):**
- **Seed folded into the warp, volume-gated.** (431)'s only drawn geometry is a `wave_a 0.001`
  `modwavealphabyvolume` waveform whose role is to inject fresh palette-coloured content. Ported as a
  palette-tinted central core seed in the warp, gated by overall energy — faithful `modwavealphabyvolume`
  AND the "core brightness ← volume" musical route. A *constant* core floods the frame to opaque warm
  metal over ~16 s (anti-reference); gating keeps the silence ground dark (D-019) and makes the core
  pulse with audio. No separate waveform-geometry draw (the line is negligible-as-geometry).
- **`mv_x/mv_y` with `mv_a 0` does NOT advect** (it's the hidden Milkdrop debug-grid; the plan §4 was a
  misread, FA #73). Advection = zoom 1.009 + the slow roam sines only.
- **Bass kick from `bassDev`**, not (431)'s `bass_thresh` absolute-threshold hysteresis (FA #31).
- **Feedback clamped to `[0,1]`** (the source's 8-bit-UNORM store) — the unsharp + rectified grain bloom
  to white on an unclamped HDR buffer (the kickoff's documented fallback). `.rgba16Float` is kept for the
  NACRE.3 iridescence uplift's headroom but today carries `[0,1]`. Comp→drawable uses the FM sRGB-decode
  so the near-black ground survives the sRGB encode.
- **Cell scale is set by the unsharp blur WIDTH** (and grain frequency), not the comp's sine frequency:
  smooth feedback → big glassy cells, high-freq feedback → oil-slick flecks. A single wide inline gaussian
  stands in for (431)'s 3-level blur pyramid (deferred, NACRE_PLAN §9).

**Status / coverage.** **CERTIFIED NACRE.4** (Matt's live M7 — the connection lands via a display-stage
downbeat camera push; flash-safe + rubric-passed). Production coverage: `NacreMVWarpAccumulationTest`
(non-black + no-white-out at silence over the live `renderNacre` path) + the multi-pass flash harness.
`certified: true`. Exempt from `PresetAcceptanceTests` single-frame invariants (feedback-branch preset,
like DB/FM).

**References.** `docs/prompts/NACRE_2B_KICKOFF.md`; `docs/presets/NACRE_PLAN.md §10`;
`docs/VISUAL_REFERENCES/nacre/source_shaders.txt`. [D-138] (butterchurn render-loop facts), [D-139]
(Fata Morgana custom-warp+comp+branch template), [D-097] (siblings not subclasses), [D-026]/[D-019].

---

## D-172: Floret — faithful port of `Sunflower Passion` onto a dedicated mv_warp branch (FLORET.4)

**Decision.** Port butterchurn's `suksma - Rovastar - Sunflower Passion` as the certified preset **Floret**,
on its own `RenderPipeline+Floret` dedicated draw branch (`isFloret` discriminator) — the same
custom-warp+comp register as Nacre (the D-171 register). NOT a literal sunflower: a breathing, colour-cycling
3-fold radial fractal bloom on black. Faithful base first (FLORET.2b), then the M7-driven motion bundle.

**Architecture.** `floret_warp_fragment` = z² conformal feedback fold + energy-scaled 1/r² internal vortex
swirl + 4 colour-cycling seed-discs + `[0,1]` clamp; `floret_comp_fragment` = a 3-fold radial-pulse
unsharp-high-pass kaleidoscope + bass spin + downbeat camera push + bass-onset radial-shockwave kick +
sRGB-decode. `.rgba16Float` feedback (Nacre register). BUG-061-safe reduced-motion path.

**Motion (Matt's live M7, 5 rounds).** One primitive per channel (FA #67): beat-lock downbeat magnify ←
cached `barPhase01`; energy swell ← avg-stem EMA; bass spin ← `bassDev`; internal vortex swirl (energy-
scaled). **★ Drum sparkle was tried + REMOVED** — fine bright-points camouflage into an already-busy bright
field; a whole-field displacement (the bass kick) reads where points don't (FLORET_PLAN §12).

**Status.** **CERTIFIED FLORET.4** (Matt: "looks good"). Flash-safe (multi-pass harness, 0.00 flashes/s).
Exempt from `PresetAcceptanceTests` single-frame invariants (feedback-branch preset).

**References.** `docs/presets/FLORET_PLAN.md §12`. [D-171] (the cert register), [D-139], [D-157]/[D-158]
(flash-safe beat motion), [D-026]/[D-019].

---

## D-173: Glaze — faithful port of `jelly showoff parade` onto a dedicated mv_warp branch (GLAZE.8)

**Decision.** Port butterchurn's `Flexi + stahlregen - jelly showoff parade` as the certified preset
**Glaze**, on its own `RenderPipeline+Glaze` dedicated draw branch (`isGlaze` discriminator) — the D-171
custom-warp+comp register. The catalog's **first physics-of-the-beat preset**: a 3-mass damped spring chain
*integrates* the audio into smooth physical momentum (sidesteps FA #4/#31 by construction).

**Architecture.** A 3-mass spring (CPU) anchored by bass↔other stem opposition (lateral) + fullness (lift)
drags a radial swirl-poke across an accreting feedback field; `glaze_warp_fragment` advects+decays+seeds
(the seed band rides the spring tail Y to fill the field); `glaze_comp_fragment` = a 3-level blur-pyramid
emboss/sheen + display-only HDR glossy bloom + the discrete downbeat camera push. Per-stem accents: drums
poke-punch, vocals glow. `.rgba16Float` feedback; BUG-061-safe reduced-motion path.

**Durable craft rules (earned on Glaze).** (1) **Sharpening is DISPLAY-only, never in the fed-back warp** —
an unsharp high-pass with feedback gain > 1 compounds into grain on a float buffer (the 8-bit source
quantises it; we can't); generalises to any mv_warp feedback preset (FA #64). (2) **Validate brightness/wash
at PLAYBACK LENGTH** (thousands of frames), never a 25 s render — the wash is a slow base-accumulation creep
over minutes. (3) **Connection on a smooth/integrated coupling needs a DISCRETE beat-locked visible motion on
top** (the downbeat camera push), not tuning the smooth layer harder (the Nacre precedent).

**Status.** **CERTIFIED GLAZE.8** (Matt's live M7 — the downbeat push lands the connection). Flash-safe
(multi-pass harness, 0.00 flashes/s). Stem-agnostic (`stem_affinity` empty). Exempt from
`PresetAcceptanceTests` single-frame invariants (feedback-branch preset).

**References.** `docs/presets/GLAZE_PLAN.md §7`. [D-171] (the cert register), [D-139], [D-157]/[D-158],
[D-026]/[D-019], [D-097].

---

## D-174: Filigree — physarum agent-network preset, certified as a loose energy-accompaniment (PHYS.5)

**Decision.** Ship **Filigree** — a living slime-mold network (physarum / neural web / river-delta) in the
Kintsugi palette (gold veins on pure black) — as the catalog's **first certified compute-agent-network
preset**. The form is the song's energy: the fine searching-web is the resting state, continuous energy
brightens/quickens it, structural peaks bloom consolidated veins (the inverse of the original sketch — chosen
from rendered evidence; FA #58, the form carries the music).

**Architecture.** `PhysarumGeometry` — a `ParticleGeometry` sibling (D-097, NOT a new render primitive) —
drives a 3-kernel physarum loop (`physarum_reset → _agents → _diffuse`, own MSL, no CC-BY-NC-SA source
copied) over an atomic deposit accumulator + ping-pong `r16Float` trail, drawn in particle mode. The
`Filigree.metal` `filigree_ground_fragment` is just the pure-black backdrop the trail covers. Audio coupling
(energyEnv / hitEnv from `stems.*EnergyDev`) is computed CPU-side in `PhysarumGeometry` and reaches the kernel
via `PhysConfig`, so the MSL-source rubric heuristic can't see it (`expectedAutomatedGate` false — the
Skein/Lumen slot-buffer precedent; Matt's M7 is the load-bearing gate).

**The substrate verdict (Matt-accepted, after 3 connection M7s).** Polarity: LOUD → fine/busy/bright web
(divide), QUIET → few calm cells (merge). The re-seed bursts on an energy surge to land the "divide" on a
musical moment; a per-beat `hit` pulse + a calm baseline keep motion event-driven, not frantic churn. But
physarum **ratchets to coarse irreversibly** (5 attempts confirmed; the only "divide" is a trail-wipe
re-seed), and on sustained-loud material the surge burst fires rarely and is redundant with the continuous
loud=fine read → it reads as **a loose energy-accompaniment, not tight event-sync.** Matt accepted that
verdict and certified on that basis. **Tightly-synced bidirectional cell merge/divide is reaction-diffusion's
domain → a separate future preset.**

**Status.** **CERTIFIED PHYS.5** (Matt's live M7). `certified: true` + FidelityRubric `certifiedPresets` +
`multiPassMeasured` + a real `renderFiligree` flash test (0.00 flashes/s, SAFE).

**References.** `docs/presets/FILIGREE_DESIGN.md`. [D-097] (siblings not subclasses / `ParticleGeometry`),
[D-026]/[D-019], [D-157]/[D-158] (flash-safe), [D-159] (Skein CPU-side-coupling rubric precedent).

## D-175: Ricercar — contrapuntal visual-music painting; substrate decays to a light ground, not black (Ricercar.2)

**Decision.** Register **Ricercar** — a contrapuntal visual-music painting preset (Fischinger / color-organ
lineage; showcased on Bach BWV 565, built reusable) — and land its flowing-colour-field **substrate** first.
Ricercar reuses Skein's canvas-hold mv_warp machinery (D-142/D-143) but reconfigured: a divergence-free
curl-noise **flow warp** (`mvWarpPerVertex` returns `uv + curl(...)`) so deposited colour advects and merges,
instead of Skein's identity hold. `certified: false` (voices, audio routing, and cert arrive Ricercar.3.x→.7).

**The load-bearing refinement — decay toward a LIGHT GROUND, not black.** A flowing field needs decay < 1 (the
§1.4 "moving present with a fading memory," Matt-confirmed 2026-06-29), but the shared `mvWarp_fragment` decays
`prev × decay` → toward **black**, which fails silence-non-black (D-037) at rest. Ricercar therefore supplies
its own `ricercar_warp_fragment` (the per-prefix `<prefix>_warp_fragment` override — the `skein_warp_fragment` /
D-149 precedent; preset-side, auto-resolved by `PresetLoader.makeWarpPipelines`, **no engine work**, every other
mv_warp preset byte-identical) that advects AND blends toward a light ground: `mix(ground, prev, decay)`. The
field breathes back to light when idle → **D-037 satisfied by construction**, and it matches the `02_meso`
ink-plume-on-near-white reference. This refines RICERCAR_DESIGN §4's "pure preset config" to "pure preset config
+ one per-prefix warp-fragment override."

**Ricercar.2 scope.** Substrate only — colour is **hand-fed** (three drifting LOW/MID/HIGH lane-coloured masses
in `ricercar_geometry_fragment`; Path A / closed-form `f(features.time)`, no CPU state, no per-track seed yet).
The gate-before-the-gate (RICERCAR_DESIGN §7): does it read as flowing, merging painterly colour? Preset count
24 → 25.

**Status.** Accepted (Ricercar.2). Substrate spike; not certified.

**References.** `docs/presets/RICERCAR_DESIGN.md`, `docs/VISUAL_REFERENCES/ricercar/`. [D-142]/[D-143]
(canvas-hold mv_warp), [D-149] (per-prefix `<prefix>_warp_fragment` override precedent), [D-037]
(silence-non-black), [D-026] (deviation primitives — the later audio increments).

## D-176: Ricercar concept revision — the orchestra painting itself, per-section painterly identity on Skein's engine

**Decision (Matt, 2026-06-29, after the Ricercar.2 substrate spike).** Replace Ricercar's concept. The
original — abstract weaving "voices" on a flowing colour-field substrate — is abandoned: a *passive* flowing
field reads as slick wallpaper, not art (the spike's smooth-blob + glossy-ribbon attempts both confirmed it;
clean procedural primitives — blobs, ribbons, gradients — plateau at "wallpaper" and structurally cannot be
*painterly*, which needs texture, ragged/feathered edges, pressure-taper, visible media).

**The locked concept.** Ricercar is **the orchestra painting itself**: each orchestral section has a distinct
painterly **identity — colour + weight + texture + material** — and the painting builds **in sync** with the
music. *Identity is the soul; sync is the second layer* (Matt's framing: "colour, weight, texture, and other
qualities per section of the orchestra, then the ability to sync"). Spirit of *Fantasia* (art emerging, the
music as the invisible painter), elegant + luminous — **not** a depicted artist (3D representational, declined),
**not** Skein's chaos.

**Architecture: build on Skein, don't reinvent (FA #73).** Skein's marks-on-top mv_warp engine (D-142/143/149)
already renders per-mark colour + viscosity/texture + weight + wet/dry sheen as convincing paint (M7-loved).
Ricercar = the **elegant/luminous sibling**: graceful *composed* strokes building a picture (vs Pollock drip)
on a **light** canvas with a luminous **Fantasia jewel-palette** (vs Skein's earthy drip). Section = frequency
**REGISTER** (no instrument separation, §6) — five register-archetypes (basses / brass / violas / violins /
flutes), each differing on *every* axis (colour / weight / texture / gloss / gesture) so the material reads the
section before the hue does.

**Consequences.** (1) The **Ricercar.2 flowing-colour substrate (D-175) is SUPERSEDED** — `Ricercar.metal` /
`.json` / `RicercarSubstrateTest` are rebuilt next increment (git history retains the spike; the
`ricercar_warp_fragment` decay-to-ground trick may or may not carry, TBD at build). (2) **Filigree compute-agent
voices + the Ricercar.3.x engine bridge are DROPPED** — section-marks use Skein's marks-on-top overlay, not
compute-agents, which removes the *only* engine touch (no `ParticleGeometry.rendersToFeedbackTexture`, no
`RenderPipeline+Draw` reroute; the RENDER_CAPABILITY_REGISTRY "Missing" feedback-canvas+agent-deposit row is no
longer on Ricercar's critical path). (3) RICERCAR_DESIGN.md §CONCEPT carries the revision + the five-section
identity table (the design center); the original §1.1 / §1.4 / §0 are marked superseded.

**Status.** Accepted (concept). Next: rewrite the increment plan around per-section painterly marks on Skein's
engine, then build — design spine recorded first (design upstream of code).

**References.** RICERCAR_DESIGN.md §CONCEPT (the five-section table). [D-142]/[D-143]/[D-149] (Skein painterly
engine, reused), [D-175] (the superseded substrate spike), [D-097] (siblings not subclasses — Ricercar is
Skein's sibling), [D-026] (deviation primitives), §6 (no instrument separation — load-bearing).

## D-177: Instrument-family capture feasible via on-device recognition (not separation) — scoped, deferred

**Finding (Matt-directed spike, 2026-06-29).** Phosphene cannot capture orchestral instrument families: 4-stem
Open-Unmix collapses all pitched orchestral content to "other," and register-bands are a weak proxy. This caps
the musicality of orchestral presets (Ricercar's whole concept, D-176 — Matt is holding its quality bar on it).

**The reframe.** Do NOT *separate* (isolate each family's audio — unsolved for orchestra: 2025 research, even
purpose-built family separators get 0–4.5 dB SDR; "MSS for classical music is an unsolved problem"). *Recognize*
instead — multi-label instrument **activity** detection, a tractable supervised problem with pretrained AudioSet
taggers (PANNs).

**Evidence.** PANNs CNN14 on two public-domain clips: (A) Sym5 i. (string-dominant) — strings captured strongly
+ dynamically (peak 0.74), brass correctly localized at the horn entry (t≈24 s); (B) Beethoven wind octet (no
strings) — Brass 0.58 / Clarinet 0.16 / Flute 0.13 top tags, and it **discriminates brass-led vs woodwind-led
moments within the ensemble** (brass 0.64↔0.06 as woodwinds go 0.04↔0.53), timpani ~0 (correct absence).
Family-level capture + discrimination + absence detection all work — a categorical leap over the status quo.
**Ceilings:** family-level only (over-calls specific instruments), cross-family confusion on sustained timbres,
buried families approximate (mitigate by driving off each family's own deviation, D-026).

**Architecture.** Supervised net via MPSGraph (D-009 = no-*CoreML* only; Beat This! / Open-Unmix precedent), run
on the 30 s preview clip (no live-latency constraint on the primary signal). Portability low-risk for a CNN.
Likely production pick: a MobileNet-class tagger (MobileNetV1-PANN / YAMNet) for budget + clean licensing.

**Decision.** Adopt **recognition (not separation)** as the path to instrument capture; **scope it as a discrete
~Beat This!-scale increment** (`docs/INSTRUMENT_FAMILY_CAPTURE_SCOPING.md` — work breakdown, candidate models,
risks, reproduction); **DEFER the build to a fresh session pending Matt's comparison with a competing musicality
idea** (Matt, 2026-06-29). Not committed to the roadmap until that comparison resolves.

**Status.** Accepted (finding + direction); build deferred pending the plan comparison.

**References.** `docs/INSTRUMENT_FAMILY_CAPTURE_SCOPING.md` (the plan). [D-176] (Ricercar — the consuming preset
+ its hold), [D-009] (no-CoreML / MPSGraph), [D-026] (deviation primitives). arXiv 2505.17823 (separation
unsolved), arXiv 1912.10211 (PANNs).

## D-178: Phase TONAL — continuous harmonic state via the Tonal Interval Vector (TIV) — GO (Matt, 2026-07-08)

**Problem (TONAL.0 audit, 2026-07-08).** The pipeline has energy, beats, stems, centroid, pitch, mood — and **nothing about harmony as a position.** NACRE.3's "hue ← harmony" is actually centroid deviation (a brightness proxy); MITOSIS.2c's hue swings on the same proxy; K-S key estimation is F#-minor-biased (CENSUS.3: 35 %, median conf 0.53). Symbolic chord/key labels were correctly deferred at MV-3 (heavy, ML-shaped, unnecessary for visuals).

**The approach.** The **Tonal Interval Vector** (Bernardes et al. 2016, ← Harte tonal centroid + Chew spiral array): a weighted 12-point complex DFT of the chroma vector per MIR frame → position on the circle of fifths, consonance, tension against a decaying tonal center, harmonic-change flux. **No labels, no model, no new ML.**

**Scope guard.** TONAL is the **palette-coherence + long-arc channel**, NOT a sync channel (the MILKDROP_ARCHITECTURE finding stands — richness doesn't buy beat-connection). Related keys → related colours (hue on the circle of fifths); tonal tension → slow macro state; harmonic flux → an accent subordinate to the Audio Data Hierarchy (continuous energy stays primary). Design rule for all consumers: **relationships, never labels** (no note/chord names user-facing) and the medium is **hue/palette/motion, never brightness** (the NACRE lesson).

**The three decisions (code evidence in the scoping doc):** (1) **Chroma reuse — YES**, a 12-bin chroma is already computed per frame (`ChromaExtractor` → `MIRPipeline.latestChroma`, already consumed by `StructuralAnalyzer`), so TONAL.1 is a **consumer, not a new DSP stage**. Documented defect: the fold floors at 500 Hz (drops bass) → the likely root of the K-S F#-minor bias, which TIV *may* inherit as a phase offset (validated against §8.5 key ground truth). (2) **Float budget — exactly 5 contiguous FeatureVector pads** (`_pad8`…`_pad12`, floats 44–48); take all 5, zero slack. (3) **Input — full-mix existing chroma** (do-least); the consonance gate absorbs percussion/noise; stem-fed chroma parked (5–10 s latency + App→DSP boundary).

**Decision.** Adopt TIV as the harmonic-state representation; **scope as 4 increments** (TONAL.0 audit → .1 `TonalAnalyzer` infra → .2 dumper + corpus calibration → .3 first-preset M7). Infra and preset increments never bundled. **Matt GO (2026-07-08)**; first-preset consumer = **Nacre** (its description already claims harmony-hue → real TIV closes an honesty gap and is the cleanest "real signal vs proxy" M7).

**Status.** Accepted (Matt go/no-go, 2026-07-08). TONAL.1 (`TonalAnalyzer` infra) code-complete 2026-07-08 — floats 44–48 populated, 192 B held. TONAL.2a `TonalDumper` + TONAL.2b corpus calibration done 2026-07-08: 1000-track pilot (2.66M frames) validated TIV (per-genre consonance classical>jazz>…>hiphop), recalibrated the consonance gate (floor 0.12→0.05 — the placeholder sat at the corpus median), saturation p99s documented for TONAL.3 (`docs/diagnostics/TONAL_PILOT_REPORT.md`). No preset reads the floats yet. TONAL.1b (Cartograph fifths-phase + consonance trace rows) code-complete 2026-07-08. TONAL.3 (Nacre consumption — hue ← `tonal_phase_fifths` circle-of-fifths, saturation ← `tonal_consonance`) **M7 SIGNED OFF 2026-07-10 (round 2, Matt "looks good")** — Nacre keeps certification with the real harmony coupling. Round 1 read as "not sure" (harmony was active but MASKED by the faithful time rotation — ~13.7 palette cycles/song vs harmony's ±0.5); round 2 made harmony SET the hue position (clock demoted so a vamp holds). **Durable lesson: an additive-nudge-on-a-full-rotation is invisible — a harmony hue signal must SET the palette position, not offset a clock.** The whole TONAL phase (.0–.3) is complete; parked round-3 levers: tension→dispersion (fixture-breadth), widen mapping if too subtle.

**References.** `docs/TONAL_ANALYSIS_SCOPING.md` (the plan + TIV math + the three decisions with file:line). [D-026] (deviation/reset discipline), [D-099] (FeatureVector/MSL contract), [D-009] (no-CoreML — TONAL adds no ML), [D-171] (Nacre — candidate consumer). Bernardes et al. 2016 (TIV); Harte et al. 2006 (HCDF); Chew 2000 (spiral array).

## D-179: Skills architecture — increment-type-scoped protocols become progressively-disclosed skills (DOC.9, 2026-07-09)

**Problem.** CLAUDE.md is loaded into *every* session regardless of what the session does. At the D-161 cap it sat at ~6,700 estimated tokens, and much of that mass was increment-type-scoped: the full Increment Completion Protocol (fires only at closeout), the Defect Handling Protocol (fires only on a `BUG-*`/P0-P2), the pruning-pass procedure (fires every tenth increment), the five-layer Audio Data Hierarchy + Cold-Start Phase Contract and the reference-porting Failed Approaches (fire only during preset/shader work). A non-preset engine session paid the full token cost of preset-authoring lore it would never use, and vice-versa.

**Decision.** Move each increment-type-scoped protocol into a Claude Code skill under `.claude/skills/<name>/SKILL.md`, which the harness loads only when the matching work begins (progressive disclosure). Five skills:

- **`closeout`** — the 8-part closeout report, mandatory `ENGINEERING_PLAN.md` + `RENDER_CAPABILITY_REGISTRY.md` updates, commit format, stop-and-report triggers. (The **no-push rule stays always-loaded in CLAUDE.md** — safety-critical, fires at any commit, not just closeout.)
- **`defect-handling`** — evidence-before-implementation, the instrument→diagnose→fix→validate→release-notes process, fix-increment doc obligations, domain artifact table, manual-validation requirements.
- **`doc-pruning`** — the five-pass pruning procedure + the D-161 ratchet. (The **token cap stays one-lined in CLAUDE.md** — it governs CLAUDE.md itself and its `DocIntegrityTests` gate is unchanged.)
- **`preset-session`** — canonical home (moved from CLAUDE.md) of the Audio Data Hierarchy Layers 2–5b, the Cold-Start Phase Contract, the one-primitive-per-layer routing rule, FA #27/#31/#67, and the preset-scoped escalation thresholds. Step 0 still points to `docs/PRESET_SESSION_CHECKLIST.md`, which stays canonical (not absorbed).
- **`shader-authoring`** — GPU contract / quality-floor pointers, `mv_warp` obligations, and the desk-research/reference-porting discipline (FA #64/#65/#73).

**What stays in CLAUDE.md.** Cross-increment invariants only: the 6-line Audio Data Hierarchy headline (continuous-energy-primary, D-026 deviation, beat constraints), the no-push and token-cap safety rules, the general Authoring Discipline rules, Code Style, Handbook Index, Development Constraints. Migrated sections become 2–4-line pointers naming the skill and when it auto-applies. Relocated Failed Approaches keep gap-table rows so `#N` citations still resolve.

**Two rules this establishes.** (1) **Canonical-vs-pointer:** a skill is *canonical* for the protocol it owns and a *pointer* for what a handbook owns — duplicated prose between a skill and a handbook (or CLAUDE.md) is a bug; pick one home. (2) **Admission-test amendment (D-161 rule 2):** skills are now the *preferred demotion target* for an increment-type-scoped rule that fails the always-loaded admission test — ahead of handbooks/checklists — because they load exactly when the matching work happens.

**Enforcement.** `DocIntegrityTests.skillIntegrity` (DOC.9) gates: the five dirs each have a `SKILL.md`; frontmatter `name` matches the dir and `description` is non-empty ≤ 500 chars; every `docs/…` path token in a skill body resolves; every `D-###`/`FA #N` citation resolves (reusing the existing resolvers); and CLAUDE.md `.claude/skills/<name>` pointers reference only existing skills. `.claude/skills/` is un-gitignored — it is committed project source as of DOC.9.

**Outcome.** CLAUDE.md dropped from ~6,701 to ~3,164 estimated tokens (well under the 4,500 target and the 7,000 cap), with no cross-increment invariant lost.

**References.** `docs/ENGINEERING_PLAN.md` (DOC.9 row). [D-161] (rulebook ratchet / admission test — amended here), [D-162] (`rotate_docs.sh`, invoked by the `doc-pruning` skill). `.claude/skills/{closeout,defect-handling,doc-pruning,preset-session,shader-authoring}/SKILL.md`.

---

## D-180: Per-preset audio route-coverage gate (QG.1, 2026-07-09)

**Context.** SR.1 built `PresetSessionReplay` after the AV.2.x cascade: 12+ increments shipped over Aurora Veil's Route 1 (vocals-pitch hue) while it fired 0 % of frames for ~5 months, every closeout claiming "the route works." SR.1 made the evidence *available* (a replay report per session) but kept it a **prose obligation** — a closeout still had to remember to run it, cite it, and be honest. Nothing failed a build when a route went dead. The failure class was diagnosable but not *gated*.

**Decision.** Mechanize per-route firing evidence as a standing test.

1. **`audio_routes` manifest** (SHADER_CRAFT §17.1). Every preset's JSON sidecar declares its routes: `{ "route": "<behaviour>", "primitive": "<FeatureVector/StemFeatures field>", "kind": "continuous|accent|structural" }`. Decoded onto `PresetDescriptor.audioRoutes`. The manifest is the routing contract; **audit before declaring** — a declared route the shader doesn't read is as wrong as an unread route left undeclared (backfill enumerated each preset's `.metal` preamble *and* its CPU driver — `RenderPipeline+<Preset>.swift` / `<Preset>State.swift` / `<Preset>Geometry.swift`, where mv_warp and geometry presets consume most primitives).
2. **`RouteCoverageTests`** replays the canonical fixture set (`Fixtures/route_coverage/` — the three tempo fixtures through the production separation + analysis chain, FA #27) and asserts per route, per fixture: **continuous** = non-constant (stddev > 1e-5 — a liveness floor, not an amplitude bar; low-but-varying is a fixture-breadth note, not a defect); **accent** = ≥ 1 rising crossing above 0.02 per fixture (calibrated to the smallest-range accent primitive, `bassAttRel`); **structural** = the section index changes on ≥ 1 fixture (the set must contain a boundary). Un-gated (0.73 s over 145 routes) so the gate is always enforced.
3. **Certification wiring.** `FidelityRubricTests.certifiedPresetsDeclareAudioRoutes` requires a non-empty manifest for every certified preset; `RouteCoverageTests` independently reddens if any declared route is dead. Together: a preset cannot be certified without a manifest whose every route demonstrably fires on real music. `AudioRouteSchemaTests` rejects a `primitive` with no recordable CSV column (typo / unrecordable field).

**The load-bearing principle: a red route is the gate working.** When `RouteCoverageTests` reddens, the route's primitive did not fire — file it in `KNOWN_ISSUES.md` as a route defect. **Never tune a floor to make it pass.** The one red surfaced during authoring (Nacre `bass_onset_kick`) was investigated to ground before acting: `bassAttRel` was demonstrably alive (7 rising crossings above 0.05 on there_there, sd 0.038) — a threshold-*calibration* artifact (an attack-relative deviation peaks below an energy-dev spike), not a dead route. The fix was to calibrate the accent threshold to the corpus's smallest-range primitive with the evidence documented, not to special-case the preset. Distinguishing "calibration against verified-alive data" from "tuning to hide a defect" is the discipline: verify the primitive is alive *first*, adjust the floor only if it is.

**Infrastructure built to reach the primitives (QG.1a–c).** `FixtureSessionCaptureGenerator` extended to write the features half offline (BeatGridAnalyzer grid install → FFTProcessor → MIRPipeline → MoodClassifier at the production cadence → `SessionRecorder.csvRow`); SessionRecorder CSV headers promoted to shared constants (a private generator copy had gone stale when IFC.4 appended columns); `SessionColumnSeries` added for by-name column access; 10 FeatureVector primitives that presets consume but the CSV never recorded appended to the features schema.

**Coverage boundary (honest limitation, QG.1.1).** The offline `StemAnalyzer` fixture cannot populate VisualizerEngine-CPU-computed `StemFeatures` fields (`cachedBassProportion`, `totalEnergySmoothed`, `auroraPalettePhase`, `auroraOrbitAzimuth`, `drumsEnergyDevSmoothed`) or `accumulatedAudioTime` (app-layer clock). Routes depending on these — Ferrofluid Ocean's spike-height and aurora, Dragon Bloom's tumble clock — are real live routes but unverifiable by this fixture mechanism, so they are **documented, not declared** (declaring would false-red a healthy route and mislabel it a defect). Verifying them needs a live-session fixture; sparse/bright-material fixtures (where `high`/`highMid`/`treble_att` and structural-confidence would exercise harder) are the same follow-up. `structural` coverage rides on `there_there` alone containing a boundary; `section_confidence` stays 0 on ≤30 s clips.

**References.** `docs/diagnostics/QG1_REPLAY_AUDIT.md` (Task 1 feasibility audit), SHADER_CRAFT §17.1, `docs/ENGINE/SESSION_REPLAY.md` (SR.1), [D-026] (deviation primitives), [D-177/IFC.4] (the appended-column staleness this surfaced). `docs/ENGINEERING_PLAN.md` (QG.1 row).
## D-181: Render-comparison sheet as the mandatory pre-commit perception step (QG.2)

**Context.** CLAUDE.md / PRESET_SESSION_CHECKLIST.md carried the prose rule "mid-session sanity checks are side-by-side comparisons against the named references." REVIEW.1 measured 35 % compliance — Claude Code mostly skipped it and self-judged "looks reasonable." Per the D-161 ratchet (violated twice → mechanize), the rule converts to a gate + a script.

**Decision.** `Scripts/compare_render.sh <preset> [session-dir]` composites the newest `RENDER_VISUAL=1` frames for a preset against every image in `docs/VISUAL_REFERENCES/<preset>/` into ONE sheet — reference left, render frames right, filenames burned into each panel — and prints the path. (No ImageMagick on the dev box; the compositor is a repo-native `swift` script, `Scripts/compare_render_composite.swift`, mirroring `PresetVisualReviewTests.buildContactSheet`.) Before EVERY tuning commit, a preset session must run it, **Read** the sheet, and write a **verdict table**: one row per mandatory trait from the reference README — `trait | reference filename | PASS/FAIL | what differs (one sentence)`. Anti-reference rows are mandatory. A FAIL must change the next action; committing with an unexplained FAIL requires stating why in the commit body.

**Scope guard.** No auto-scoring (no CLIP / dHash-vs-reference metric): the reader is Claude's eyes, and an uncalibrated similarity proxy would invite verdicts on a broken proxy ([D-064]). The sheet composites existing outputs only — no in-engine capture pipeline ([D-064](d)).

**Enforcement.** `docs/PRESET_SESSION_CHECKLIST.md` Part 1 step 5 (the canonical surface the `preset-session` skill points at); the sheet is the canonical closeout §3 artifact (CLAUDE.md §3); `Scripts/closeout_evidence.sh` surfaces the sheet path when a session produced one.

**References.** REVIEW.1 (compliance measurement), [D-161] (rulebook ratchet — violated-twice-mechanize), [D-064] (reference-README rubric + no-auto-score). `docs/PRESET_SESSION_CHECKLIST.md`, `Scripts/compare_render.sh`.

## D-182: Per-paradigm multi-frame harness templates (QG.4, 2026-07-10)

**Context.** PRESET_SESSION_CHECKLIST Part 2 obligation 1 requires "write or extend the multi-frame harness FIRST — verify the live path is reachable from a test before any shader work." The rule exists because three Aurora Veil increments shipped green on single-frame `preset.pipelineState` tests while smearing in live playback: single-frame tests verify instantaneous output only and cannot catch a frame-to-frame accumulation regression. But only `mv_warp` had a reference harness (`AuroraVeilMVWarpAccumulationTest`); an author working a `staged` / `ray_march` / `feedback` preset had to build the multi-frame harness from scratch, so in practice the obligation was skipped and the smear class stayed open for those paradigms.

**Decision.** Give every rendering paradigm a named, env-gated reference harness that drives the *same dispatch path the live app uses*, all built on one shared spine so the obligation becomes a copy-adapt from a named template:

- `HarnessTemplateCore.swift` — the shared spine: `HARNESS_TEMPLATES=1` gate, zeroed silence audio buffers (fft/wave/stem/history), capture-texture alloc + one-shot clear + BGRA / rgba16Float readback, the per-frame silence FeatureVector, and metric hooks (non-degeneracy incl. half-float NaN, luma, and a dHash/Hamming pair byte-identical to `ArachneSpiderRenderTests` so goldens compare across the suite).
- `mv_warp` → `AuroraVeilMVWarpAccumulationTest` — re-based on the core (byte-identical assertions), scene → warp → compose → swap.
- `staged` → `StagedPathHarnessTemplate` (subject Arachne) — world → composite through the production `encodeStage` with slot-6 (web) / slot-7 (spider) bound; per-stage non-degenerate (non-constant + non-NaN + signal) + composite dHash golden.
- `ray_march` → `RayMarchPathHarnessTemplate` (subject Lumen Mosaic) — the live `RayMarchPipeline.render` seam (BUG-034 128-step parity): G-buffer → lighting → composite → post; non-degenerate + luma floor (BUG-016 guard) + composite dHash golden.
- `feedback` → `FeedbackPathHarnessTemplate` (subject Membrane, the only pure surface-mode feedback preset) — production `runWarpPass` → additive composite → ping-pong swap for 60 frames; the accumulator must stay between the D-037 non-black floor and saturation.

**A/B validation (each template catches a broken dispatch).** staged: unbinding the sampled world input (slot 13) → constant-dark composite → non-constant check fails. ray_march: unbinding the slot-8 follower → BUG-016 black cells (meanLuma 0.47→0.15) → golden trips (Hamming 33). feedback: skipping the compose pass → accumulator decays to 0.0 → the D-037 floor fails. Each was reddened then restored; goldens are hardware-specific (D-039, Apple Silicon / macOS 14+).

**Scope guard — env-gated, not in the default run.** Some subjects (60 frames × real pipelines) exceed the fast-gate timing budget, so all four gate on `HARNESS_TEMPLATES=1` (they skip in <1 ms in the default `swift test`) and are surfaced for preset increments via `closeout_evidence.sh` rather than folded into the parallel battery. Templates use production presets only (no bespoke harness `.metal`, FA #27 spirit).

**References.** `PRESET_SESSION_CHECKLIST.md` Part 2 obligation 2 (names all four), `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` §8, [D-037] (feedback non-black floor), [D-039] (hardware-specific golden dHash), BUG-016 (unloaded-palette black cells), BUG-034 (ray-march production-parity budget). `docs/ENGINEERING_PLAN.md` (QG.4 row).
## D-183: Signal health monitor — classify the input chain, don't just recover it (ASH.1, 2026-07-10)

**Context.** The RUNBOOK's signal-chain triage (peak-band levels, the output-device permission-invalidation trap, the sample-rate family) was a *manual* catalog — a human read `raw_tap.wav` after the fact. Two of the three failure modes fail silently at runtime: a default-output change invalidates the Screen-Recording grant and the tap keeps delivering zeros with no UI signal (the trap behind much of BUG-057's diagnosis cost), and a 96 kHz interface forces a resample the stem pipeline assumes away. [D-165] built *recovery* (the tap-reinstall backoff) but not *observability* — nothing classified the chain while it ran.

**Decision.** `SignalHealthMonitor` (engine, `public`) classifies input-chain health continuously from the raw pre-AGC tap. A rolling 5 s peak window plus the tap signal state produce one `SignalHealth` value — `peakBand` (healthy ≥ −12 dBFS / low −15…−12 / critical, the RUNBOOK bands), `deadTap`, `sampleRateMismatch` — published on state change to `session.log` (`SIGNAL_HEALTH:` line) and the debug overlay. ASH.1 is engine + debug surfacing only; user-facing surfacing and the "refuse to certify/record on degraded audio" product question are ASH.2.

**Boundaries that keep it honest.**
- **Observe, never steer.** The monitor does not touch `SilenceDetector`, the reinstall backoff, or AGC — that coupling is a future decision, not this increment. D-165 *acts*; D-183 *classifies*. They read the same silence signal for different jobs.
- **`deadTap` is a duration verdict, not a counter reach.** It fires after `.silent` persists ~45 s (past the [3,10,30]s reinstall backoff), gated to process-tap modes. This catches both the cold broken tap (`!hasEverDetectedSignal`) AND the mid-session device-switch trap (where `hasEverDetectedSignal == true`, so D-165's reinstall correctly stays its hand) — duration is the only discriminator observable from a zero stream that covers both. Accepted limitation: a very long deliberate pause also trips it; disambiguating pause-vs-dead from zeros alone is impossible, and the response is ASH.2's call.
- **Pre-AGC by construction.** Peak measures absolute level, which AGC normalizes away downstream — so the tap is the only place the reading is meaningful (same rationale as `InputLevelMonitor`, which grades quality green/yellow/red; `SignalHealthMonitor` is the sibling that adds the two failure-mode *flags* the level grade can't express).
- **Realtime discipline.** `ingest` is allocation-free per buffer (one vDSP peak reduction); classification, the CoreAudio output-rate query, and the `onHealthChanged` emit all run on a non-realtime queue.

**References.** [D-165] (silent-tap recovery — the machinery this observes but does not touch), `InputLevelMonitor` (peak/spectral quality grade sibling), RUNBOOK §"Signal health monitor" + §"Audio levels too low" + §"App captures silence" (the detector-to-remediation map), `docs/CAPABILITY_REGISTRY/AUDIO.md`, `docs/ENGINEERING_PLAN.md` (ASH.1 row). Follow-up: ASH.2 (user-facing surfacing + degraded-audio certification policy).

## D-184: Signal-health surfacing + post-session chain analyzer (ASH.2, 2026-07-10)

**Context.** [D-183] built the classifier but surfaced it only to `session.log` + the debug overlay. A user whose chain is degraded still lost quality silently, and no session artifact carried a chain verdict — so an M7 review, reel recording, or fidelity closeout could run on degraded audio with nothing flagging it.

**Decision.** Three pieces, none of which gatekeep the user's music (Phosphene degrades gracefully; it surfaces and continues):

1. **One user-facing toast.** A once-per-session `band=low` nudge (DECISION-NEEDED opt 1 — a single unobtrusive nudge, never repeated), reusing the existing `audioLevelsLow` case: the Spotify "Normalize Volume" remediation when the source is Spotify, generic otherwise. Wired in `PlaybackErrorBridge` off `engine.$signalHealth`. `sampleRateMismatch` stays overlay/log-only (remediation too setup-specific for a toast; RUNBOOK carries it).

2. **`ChainAnalyzer`** (Shared, `public`) grades a finished session dir and writes `chain_health.json` + a `CHAIN_HEALTH: verdict=<clean|degraded|broken> reasons=[…]` line. It runs **in-process** at the end of `SessionRecorder.finish()` (so every session self-grades) and **out-of-process** via `Scripts/analyze_session_chain.sh <dir>` (retroactive grading of old dirs) — one analyzer, two callers. Verdict inputs: raw_tap.wav peak (broken < −15, degraded −15…−12), and session.log scans for `SIGNAL_HEALTH deadTap=true` (broken), `band=low/critical`, `DRM silence`, and tap reinstalls (degraded). Missing artifacts are noted, never fatal — a pre-ASH dir grades on whatever is present.

**Boundaries that keep it honest.**
- **`deadTap` is card-only, not a second toast.** The `AudioStallOverlayView` fix-ladder card (D-165, `PlaybackErrorBridge` freshness poll) already raises at ~10 s of no-fresh-audio while playing, more prominently than a 45 s toast would, and already names the re-grant-Screen-Recording remediation. Adding a toast is redundant double-surfacing the codebase deliberately avoids (Matt's call). The `deadTap` signal still feeds the analyzer verdict.
- **★ The Love Rehab onset count is REPORTED, never gated — because it is AGC-invariant.** Task 3 was specced to catch a normalized/low-quality reel by counting sub-bass onsets against the validated 11-per-5 s reference (RUNBOOK step 4). This was **empirically falsified**: attenuating a real Love Rehab capture (−26 dB), dynamic-compressing + hard-limiting it (a faithful Spotify-Normalize model), and even −50 dB gain **all left the `beatBass` onset count at ~11-12/5 s**. That is AGC + spectral-flux onset detection working as designed (D-026: level-independent rhythm) — the onset count is a rhythm-density fingerprint, not a degradation signal; it only collapses on true signal loss (which peak/dead-tap already catch). **What actually catches normalization is the PEAK check** (Spotify Normalize lowers peak below −12 dBFS — RUNBOOK step 1). The analyzer records the onset median as an informational metric the reel operator can eyeball, but no verdict depends on it. Corollary: do not re-attempt an onset-count degradation detector on any AGC-normalized signal.
- **Does not gatekeep.** Playback, preparation, and session start never block on health state. No system or source-app setting is auto-changed. No Settings pane for thresholds — constants with doc comments.

**References.** [D-183] (the classifier this surfaces), [D-165] (the silent-tap card that owns dead-tap remediation), [D-026] (AGC deviation primitives — why onsets are level-invariant), `Scripts/analyze_session_chain.sh`, `docs/RUNBOOK.md` §"Recording the quality reel" (verdict=clean requirement) + §"Post-session chain analyzer", `docs/PRESET_SESSION_CHECKLIST.md` (M7/reel evidence rule), `docs/ARCHITECTURE.md §Module Map` (`ChainAnalyzer.swift`).

---

## D-185: Aurora Veil reauthored as a faithful nimitz "Auroras" port (AV.7, 2026-07-19)

**Status.** Accepted. Supersedes the AV.5 footprint direction, which cited this D-number in `AURORA_VEIL_DESIGN.md` but was never written up and never shipped.

**Context.** Aurora Veil had churned across AV.2 → AV.6 without reaching certification. Each round added machinery on top of the nimitz recipe it was originally derived from: a Lawlor footprint `F(x)` to carve negative space, three parallax columns, a traveling band undulation, a rare-event drum kink, per-march-step traveling waves, and eight audio routes later curated to three. The shader also quietly drifted from the reference itself — the 3D ray march was flattened into a fake 2D column, `triNoise2d` grew a global `mm2(time * 0.10)` rotation nimitz never had, and the final gain was raised 1.8 → 2.4. The result read, in Matt's words, as "the right look, wrong expression" — a full-field wash. This is Failed Approach #65 in its purest form: components of a working reference negotiated away one at a time, each defensible in isolation, cumulatively fatal.

**Decision.** Stop deriving and port the reference.

1. **Faithful port.** nimitz (@stormoid), "Auroras", Shadertoy `XtGGRt` (2017), retyped into MSL with his algorithm and constants intact: the real 3D ray march (`ro`/`rd`, sampling `bpos.zx`), five-octave domain-warped triangular noise, the running-average smear (`avgCol = mix(avgCol, col2, 0.5)`) that turns noise into ribbon, the per-march-step `sin()` H(z) palette (Lawlor & Genetti, WSCG 2011), his `bg()`/`stars()`, his horizon fade and 1.8 gain. Every AV.2–AV.6 addition deleted. Adapted only for the harness: `iTime` → `f.time`, `gl_FragCoord` → `in.position.xy`, `iResolution` → baked 1080p, y-flip.

2. **Upward sky framing** (Matt, live review). The reflection branch and horizon are removed and the camera is pitched up (`kAuroraPitchUp = 0.60`) so the frame is sky end-to-end — vertical ray curtains overhead, matching the Lofoten-style references. **The camera pan was deleted, not merely slowed**: `stars()` is indexed by view direction, so any camera motion makes the whole starfield scintillate. Removing the pan fixed "stars twinkle too much" and "don't like the slow camera movement" with one change.

3. **Three non-competing reactivity axes** (one primitive per axis, per the routing rule):
   - **Stars → beat.** `bar_phase01` (downbeat, cached grid — not raw onsets), gated by `pulse_amp01` so it is silent at cold-start and silence, near-unison with a small per-star spread. Flash-safe *by footprint*: stars are sparse pinpoints, so even a unison pulse barely moves global luminance — measured 0.00 flashes/s.
   - **Brightness → mood envelope.** `f.arousal`, clamped to 0.85–1.15, plus a **subordinate** lift from `bass_att_rel` (`kBassLift = 0.20`).
   - **Colour → mood.** `f.valence` shifts the whole palette phase (±0.5 rad).

**Empirical findings worth keeping.**

- **★ Mood envelopes, not deviation primitives, are the right driver for a *gentle* response.** Measured on real captures: `bass_dev` is spiky (p50 = 0, max 2.3, 4× the frame-jerk of `bass_att_rel`); `mid_dev`/`treb_dev` are near-flat on real music (p95 ≈ 0.07 / 0.01) — too weak to drive anything. `arousal` and `valence` are smooth, well-distributed envelopes. Deviation primitives are correct for *transients*; they are the wrong tool when the brief is "gentle."
- **★ `bass_att_rel` is the gentle deviation primitive.** It is attack-enveloped upstream, so it satisfies the L2 continuous-energy gate (D-026) *and* stays smooth — no CPU-side EMA state required.
- **★ A crown-only colour shift is perceptually invisible.** nimitz's `exp2(-i * 0.065 - 2.5)` weighting means high march-steps contribute almost nothing to the final pixel. A hue shift applied to the crown is mathematically real and visually zero; it must be applied to the whole palette to be seen.
- **★ Beat-sync legibility is a property of the grid, not only the mapping.** On School of Seven Bells (dense reverb-washed dream-pop) the phase signals wrapped at rates inconsistent with the 153 BPM grid and `drift_ms` swung to −90 ms; the same star mapping read as correctly locked on Cherub Rock. Diagnose "not synced" against a percussive track before treating it as a shader bug.
- **A clamp truncates the driver it bounds.** Capping the breathe at 1.15 shrank the mood swing until a +11% bass lift rivalled it. When a bounded driver stops dominating its accent, lower the accent — do not relax the gate.

**Licensing.** nimitz's Shadertoy source is CC-BY-NC-SA; Phosphene is MIT. Matt's explicit call (2026-07-19) was to ship the port credited, accepting the terms for this non-commercial project. Attribution to nimitz and to Lawlor & Genetti is carried in the shader header and the sidecar `author` field.

**Certification.** Certified 2026-07-19 on Matt's M7 sign-off across five live sessions. Automated gate `[✓] 3/4` (L4 is manual by definition); flash-safety MEASURED at 0.00 flashes/s; `PresetRegressionTests` goldens regenerated (the old hashes were 32–38 Hamming bits away — a different image by design, not drift).

**References.** [D-026] (deviation primitives), [D-029] (one rendering paradigm per preset), [D-037] (silence never renders black), [D-067] (lightweight rubric), [D-157] (bounded per-beat footprint + steady luminance), FA #65 (do not negotiate away a working reference), `docs/presets/AURORA_VEIL_DESIGN.md` §5.11, `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` §1.1 (the recipe), nimitz Shadertoy `XtGGRt`, Lawlor & Genetti (WSCG 2011).

## D-186: Glass Brutalist preset retired (GBRETIRE.1, 2026-07-19)

**Status:** Accepted (Matt's call, 2026-07-19).

**Decision.** Glass Brutalist is retired in its entirety. All preset code (`GlassBrutalist.metal`, `GlassBrutalist.json`), its dedicated tests (`GlassBrutalistTests`, `RayMarchSDFDiagnosticTests` — CPU SDF evaluation of the Glass Brutalist corridor — and the `GlassBrutalistValidationTests` JSON-validation suite inside `RayMarchDiagnosticTests`), and its visual reference set (`docs/VISUAL_REFERENCES/glass_brutalist/`) are deleted. Recover from git history if a future architectural ray-march preset revives the concept. `PresetLoaderCompileFailureTest.expectedProductionPresetCount` drops **27 → 26**.

**Context — why the concept is non-viable, not just under-developed.** Glass Brutalist was the original ray-march scene preset (its Option-A design is the subject of D-020). Two structural problems make it fail the preset viability bar rather than a tuning target:

1. **D-020 permanence forecloses the musical role.** D-020 (architecture-stays-solid) was adopted precisely because three iterations of bass-driven beam/pillar/fin deformation all read as "broken or rubber." The rule leaves music driving only light, fog, camera, and a single subtle glass-fin slide — the concrete itself is *deliberately audio-static*. That makes an instrument (or any musical subject) structurally incapable of being the hero of the scene: the hero is a static building, and the audio reactivity is confined to ambient lighting garnish. Phosphene's preset bar (iconic visual subject with a *load-bearing* musical role) cannot be met by a scene whose defining subject is contractually forbidden from responding to the music.
2. **2006-tier fidelity.** The board-form-concrete-corridor look reads as a mid-2000s demoscene interior, below the current visual quality floor; a rebuild (V.12 scope) was considered and abandoned.

**What survives.** D-020 stays Accepted — the architecture-stays-solid *rule* still governs any future architectural ray-march preset; it is annotated with a pointer to this retirement. The shared ray-march infrastructure (`RayMarchPipeline`, the deferred PBR path, `RayMarch.metal` / `IBL.metal` / `PresetDescriptor+SceneUniforms`, the generic `SceneUniformsConstructionTests` in `RayMarchDiagnosticTests`) is untouched — Kinetic Sculpture and Volumetric Lithograph still use it. The `.ssgi` pass declaration stays on the GPU contract though no production preset currently declares it (Glass Brutalist was the only one). `SceneUniforms.cameraForward.w` remains a preset-specific free lane (D-020's mechanism); it is simply unused now that its one consumer is gone.

**What was rejected.**

- **Keep it as a "reusable ray-march reference."** The shared ray-march path is the reusable asset and it survives independently; the Glass Brutalist implementation adds nothing the path doesn't already carry (siblings-not-subclasses, D-097). Keeping deleted-concept code as "infrastructure" is a named anti-pattern.
- **Rebuild the fidelity (V.12) and keep the concept.** Even at higher fidelity the D-020 constraint keeps the musical role hollow. Fidelity was the smaller of the two problems.

**Rule.** Glass Brutalist is gone. A future architectural ray-march preset starts from a new spec that either (a) solves the instrument-as-hero problem within D-020, or (b) proposes a deliberate D-020 exception with Matt's sign-off — not from undoing this deletion.

**Carry-forward.** GBRETIRE.1 executed under this decision. `docs/ENGINEERING_PLAN.md` roster survey + Recently-Completed updated; `docs/CAPABILITY_REGISTRY/PRESETS.md`, `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`, `docs/ARCHITECTURE.md` Module Map, and `docs/RELEASE_NOTES_DEV.md` all drop Glass Brutalist. GoldenSessionTests fixtures regenerated deterministically (Waveform, the sole `waveform`-family preset, inherits the mellow-jazz slots GB used to win — the same sole-family clustering already documented for Membrane; not a planning regression).

## D-187: Phase RMENV — ray-march render environment (multi-light + gallery IBL + backdrop)

**Status:** Accepted (Matt's call, 2026-07-20 — chose the engine investment over shipping Kinetic Sculpture as luminous glowing-wire).

> **Retention note (KSRETIRE.1 / D-188, 2026-07-20):** Kinetic Sculpture — the intended first consumer named throughout this decision — was retired before it opted into RMENV. The Phase RMENV engine work (multi-light `SceneUniforms`, `ibl_env`/gallery, per-preset background, `MultiLightSceneUniformsTests` + `IBLEnvironmentTests`) is **retained** as a completed opt-in capability with **no production consumer yet**; it awaits a future ray-march preset. Nothing below is reverted.

**Decision.** Add ray-march render-environment capability as a **shared, opt-in, byte-identical** engine feature, benefiting every ray-march preset (Lumen Mosaic, Ferrofluid Ocean, future architectural presets), with Kinetic Sculpture as the intended first consumer at KSRB.2 (retired before opting in — see retention note above):
1. **Multi-light deferred lighting** (RMENV.1) — up to 4 point lights (key/rim/fill/accent). `SceneUniforms` grows 128→240 B (light1/2/3 + `lightingParams`, appended after `sceneParamsB` so existing offsets never move); the lighting loop sums Cook-Torrance over `lightingParams.x` lights and shadows only light 0.
2. **Selectable IBL environment** (RMENV.2) — `PresetDescriptor.environment` selects `ibl_env` (0 = default interior, 1 = high-contrast gallery with HDR skylight strips) baked by `IBLManager(envType:)`, so a near-mirror has detail to reflect (fixes "chrome = putty").
3. **Per-preset background** (RMENV.3) — the miss path renders the environment (`lightingParams.y != 0`) so the visible backdrop matches the reflections.

**Why opt-in + byte-identical is the governing constraint.** Changing shared renderer code risks a catalog-wide golden re-baseline. Designing every capability so a preset that doesn't opt in produces bit-identical output (1-light loop is `0 + x`; env 0 bakes the same cubemap; bgEnv 0 keeps the sky path) means each increment's gate is simply "all existing ray-march goldens byte-identical" — verified green throughout (only Aurora Veil's pre-existing AV.6 drift). This is the model for future shared-renderer additions.

**GPU-contract note.** `SceneUniforms` is defined in four places that must stay in lockstep (`Common.metal`, `AudioFeatures+SceneUniforms.swift`, `PresetLoader+Preamble.swift`, `+WarpPreamble.swift`); a mismatch is silent memory corruption. Documented in ARCHITECTURE §Key Types / §GPU Contract.

**Deferred (was KSRB.2).** Production per-draw environment selection (a `RenderPipeline` IBLManager-per-envType cache + threading the descriptor's `environmentType` into `drawWithRayMarch`) — the render harnesses select per-preset today; production wiring was scoped for KSRB.2 but is **not yet built**, since KS was retired (KSRETIRE.1 / D-188) before opting in. It lands when a future ray-march preset consumes RMENV.

**Carry-forward.** RENDER_CAPABILITY_REGISTRY §3/§4 rows (multi-light, environment selection, per-preset background), SHADER_CRAFT §17 (`environment` key, multi-light `scene_lights`), ARCHITECTURE §Key Types, and `IBL.metal` updated. Tests: `MultiLightSceneUniformsTests`, `IBLEnvironmentTests`.

---

## D-188: Kinetic Sculpture preset retired (KSRETIRE.1, 2026-07-20)

**Status:** Accepted (Matt's call, 2026-07-20).

**Decision.** Kinetic Sculpture is retired in its entirety. All preset code (`KineticSculpture.metal`, `KineticSculpture.json`), its dedicated tests (`KineticSculptureTests`, the KS-only `KineticSculptureMotionGifHarness`), its design doc (`docs/presets/KINETIC_SCULPTURE_DESIGN.md`), and its visual reference set (`docs/VISUAL_REFERENCES/kinetic_sculpture/`) are deleted. `PresetLoaderCompileFailureTest.expectedProductionPresetCount` drops **26 → 25** (certified count 14, unchanged by this retirement — KS was never certified; Aurora Veil certified at AV.7). Recover from git history if a future concept revives it.

**Context — why retired, not tuned.** Matt stopped the preset after several redesigns failed to find the right direction: the chrome-in-a-gallery look (the KSRB.1 rebuild + the Phase RMENV material lift built to serve it) read as a "tinker toy," and a subsequent psychedelic-iridescent pivot drifted into a different concept entirely rather than fixing Kinetic Sculpture. This is a concept-direction failure, not a fidelity or infrastructure gap. A fresh **psychedelic-geometry preset** will be authored separately, from a new spec — not by reviving this deletion.

**What survives — Phase RMENV (D-187) is retained.** The multi-light deferred lighting (`SceneUniforms` light1/2/3 + `lightingParams`), selectable IBL environment (`ibl_env` / `ibl_gallery_env`, `IBLManager.envType`), per-preset background (`RayMarch.metal` miss path), and `PresetDescriptor.environment` — plus `MultiLightSceneUniformsTests` and `IBLEnvironmentTests` — are all **kept, untouched**. RMENV was built as a shared, opt-in, byte-identical capability (D-187); Kinetic Sculpture was only its *intended* first consumer. With KS gone the capability has **no production consumer yet** — that is intentional per Matt: RMENV awaits a future ray-march preset and must **not** be deleted as "dead." The shared ray-march path (`RayMarchPipeline`, deferred PBR, `RayMarch.metal` / `IBL.metal` / `PresetDescriptor+SceneUniforms`) also stays — Volumetric Lithograph and Test Sphere still use it.

**Wiring removed.** `expectedProductionPresetCount` 26 → 25; `FidelityRubricTests.expectedAutomatedGate` KS entry removed (KS absent from `certifiedPresets`, unchanged); `PresetRegressionTests` KS golden + KSRB.1 comment removed; `PresetVisualReviewTests` KS argument removed; `MaxDurationFrameworkTests` KS row removed; `GoldenSessionTests` KS `makePreset` dropped and the one affected golden regenerated (Session C track 2 falls KS → Membrane, the runner-up mid-energy fit — every other slot byte-identical, a single-slot runner-up substitution, not a planning regression); `SessionRecorderTests` log literal repointed off KS. Shared-path comments that had named only Kinetic Sculpture (`RayMarch.metal`, `IBL.metal` `ibl_proc_env`, `PresetDescriptor+SceneUniforms.swift`, app `VisualizerEngine+Audio.swift`) generalized.

**Carry-forward.** KSRETIRE.1 executed under this decision. `docs/ENGINEERING_PLAN.md` (KSRB.1 + RMENV entries annotated, Milestone D roster 26 → 25, KSRETIRE.1 Recently-Completed), `docs/CAPABILITY_REGISTRY/PRESETS.md`, `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` (RMENV rows note KS retired, capability awaits a consumer), `docs/ARCHITECTURE.md` Module Map, and `docs/RELEASE_NOTES_DEV.md` all updated. D-187 annotated with a retention note pointing here.

---

## D-189: Truchet Loom — multiscale curved-Truchet density-mapping weave (PG.4.1, 2026-07-20)

**Status.** Accepted. Reviewable v1 (`certified: false`); per-beat tile flips + per-path hue teams are PG.4.2, deeper nesting/polish PG.4.3 (`PG_4_TRUCHET_LOOM.md §A9`).

**Context.** First build of Phase PG (psychedelic geometry). Chosen as the phase opener for lowest fidelity risk: pure crisp 2D op-art with strong published prior art, and it proves the phase's distinctive **complexity-mapping** routing strategy (musical busyness → geometric density) that none of the other four PG presets use.

**Decision.**

1. **Port, don't derive (FA #73).** Arc SDF is IQ's canonical two-quarter-arc Truchet tile (per-cell hash → one of two orientations → distance to nearer of two corner-centred r=0.5 circles; pieces join edge-to-edge into continuous winding paths). Multiscale recursion follows Carlson's "Multi-Scale Truchet Patterns" ½-scale rule (successive tiles halved, smaller drawn on top). Cross-referenced to IQ's multiscale Truchet (Shadertoy `4t3BW4`); its source was Cloudflare-blocked from offline retrieval, so the recursion is **authored from the published rule + IQ's arc recipe**, not copied line-for-line — the borrowed load-bearing components are the arc math and the ½-scale hierarchy.

2. **Density hero = smoothed `spectral_flux` (D-026-safe).** A continuous global subdivision `level` is a soft-saturation of a smoothed flux — a monotonic map of a continuous variable, **never an absolute threshold on an AGC-normalized energy band** (FA #31). Busy → level rises → the weave shatters into nested sub-tiles; sparse → level falls → tiles merge into large arcs. Subdivision **crossfades** (per-parent-cell smoothstep of `level − L`, per-parent hash jitter) so it animates rather than pops, and spreads across the field like a wave. Recursion capped at depth 3 (Restrained default, DECISION-NEEDED §9).

3. **Smoothing lands in `SpectralHistoryBuffer`, not a new binding.** SpectralHistory has no flux ring; rather than add a slot-6 EMA state buffer (per-preset app-layer wiring, a new binding) the smoother is a **single CPU-side EMA float** (`flux_smoothed`, idx 3390, FPS-independent τ≈0.35 s) written in `append()` into the buffer's reserved region. buffer(5) is already bound unconditionally on the direct pass, so the shader reads it with zero new plumbing. The regression/visual harnesses bind a zeroed history → level = base → deterministic coarse weave.

4. **Drift = `arousal` speed on an `f.time` baseline.** One audio primitive on the drift layer (arousal); `f.time` is the non-reactive wall-clock baseline (advances at silence, so the loom always drifts — D-037), not a second driver (FA #67). Silence (flux ≈ 0) → coarse large-arc weave over a deep-cobalt ground (non-black).

**Empirical findings worth keeping.**

- **★ When the target primitive has no existing history ring, extend the already-bound history buffer's reserved region before adding a new per-preset binding.** A single reserved EMA float in buffer(5) delivered "smoothed, no flicker" with a ~6-line engine change and no app-layer wiring — vs a NimbusState/AuroraVeilState-style slot-6 class + apply-branch plumbing + harness parity work.
- **★ `spectral_flux` is an unusually well-matched hero** — it *literally measures* the thing being mapped (broadband busyness) and is a recordable continuous route (`RouteCoverageTests` green on both declared routes).

**References.** [D-026] (deviation primitives, no absolute thresholds), [D-029] (one paradigm — crisp `direct`, no feedback), [D-037] (silence non-black), [D-067] (lightweight rubric), [D-180] (audio-route manifest), FA #31 / FA #67 / FA #73, `docs/presets/psychedelic_geometry/PG_4_TRUCHET_LOOM.md` (design of record), IQ "Truchet tiles" (iquilezles.org/articles/truchet) + Shadertoy `4t3BW4`, C. Carlson "Multi-Scale Truchet Patterns" (christophercarlson.com).

---

## D-190: Truchet Loom rhythm + colour — per-beat flips, hue teams, glow (PG.4.2, 2026-07-20)

**Status.** Accepted. Builds on D-189 (PG.4.1). `certified: false`; PG.4.3 (deeper nesting, chromatic/grain/AA polish, possible curl-warp) remains.

**Context.** PG.4.1 shipped the density hero (smoothed `spectral_flux` → subdivision) + drift. PG.4.2 adds the §A3/§A4 rhythm + colour layers so the weave is a fuller readout of the arrangement: the beat re-routes the paths, brightness/harmony colour the ribbons.

**Decision.** Three routes, each on a distinct primitive/timescale (FA #67):

1. **Per-beat tile flips (rhythm).** On the cached-grid beat, a bounded ~22 % hash-selected subset of tiles re-route their Truchet arc. To make the subset EVOLVE beat to beat (not oscillate the same tiles), a new **`beat_index`** monotonic counter is added to `SpectralHistoryBuffer` (slot 3391), incremented CPU-side on each `beat_phase01` sawtooth wrap — same reserved-slot pattern as the D-189 flux EMA (no new binding). The flip crossfades over `beat_phase01` so it animates rather than pops, and is gated by `pulse_amp01` so cold-start/silence (where grid phase may be wrong) show the static weave. An orientation swap preserves per-cell ink, so global luminance stays steady — **measured beat luminance swing 0.0055** (D-157: bounded footprint + steady luminance, not a strobe).
2. **Per-path hue teams (colour).** Coarse spatial blocks (½ the base-tile frequency) get a **quantised** hue team; hues stay coherent along paths → coloured ribbons, not per-cell rainbow noise. `spectral_centroid` slowly phases the whole set. The deep-cobalt ground is fixed for op-art contrast.
3. **Bounded path glow (accent).** `bass_dev` drives a subtle additive glow weighted toward the freshly-subdivided (high-depth) ribbons. Explicitly drop-able if it competes at M7.

**Empirical findings worth keeping.**
- **★ The reserved-slot counter pattern generalises.** A monotonic per-beat index that a stateless direct fragment needs (to seed evolving per-beat state) is another single reserved float in `SpectralHistoryBuffer` — CPU detects the `beat_phase01` wrap, the shader reads one float. No slot-6 binding, no app wiring. (D-189 established this for a smoothed EMA; D-190 for an event counter.)
- **★ "Flip = orientation swap" is what makes per-beat motion D-157-safe.** Swapping a Truchet arc's orientation moves the ink without changing its area, so a bounded flipping subset barely moves global luminance (0.0055 swing measured) — the re-route reads as rhythm, never as a strobe. This is the general recipe for beat-locked motion on a coverage-based preset.
- Automated rubric gate rose to **3/4** (L1/L2/L3) once the in-source `bass_dev` read made the L2 deviation-primitive heuristic pass; the smoothed-flux hero remains invisible to that source scan (it lives in buffer 5). L4 (Matt's M7) is the load-bearing cert gate.

**References.** D-189 (PG.4.1 base + reserved-slot pattern), [D-026], [D-028] (`beat_phase01`), [D-037], [D-154]/[D-157] (beat-locked motion constraints), [D-180] (route manifest), FA #67 (one primitive per layer), `docs/presets/psychedelic_geometry/PG_4_TRUCHET_LOOM.md` §A3/§A4/§A9.

---

## D-191: Truchet Loom breakup polish — organic hue boundaries + grain (PG.4.3, scoped; 2026-07-21)

**Status.** Accepted. `certified: false`. A deliberately **scoped** PG.4.3: the §A2 "breakup" craft layer only, with the felt/density changes held for Matt's live M7.

**Context.** PG.4.3's design-doc scope (deeper nesting, finer motif variety, curl-warp, chromatic/grain/AA) is largely M7-gated: "deeper nesting" was explicitly conditional on "if peaks feel underwhelming at M7," and Matt chose **Restrained (cap 3)** at the PG.4.1 review; a curl-warp changes how the motion *feels*. Doing those before the preset's first live review risks polishing the wrong things (the mechanical-iteration failure mode). So PG.4.3 was scoped to the low-regret breakup work that improves the preset without pre-empting a decision Matt already made.

**Decision.**
1. **Organic hue-team boundaries.** The PG.4.2 hue teams snapped to a hard `floor()` square grid (a cosmetic defect flagged in the PG.4.2 closeout). The block-lookup coordinate is now domain-warped by a cheap single-octave value noise (`tl_vnoise` — 4 hash taps + smoothstep bilerp, centred) so team borders wander organically while regions stay coherent ("teams," not per-cell rainbow).
2. **Subtle paper grain.** A screen-anchored static grain (±0.014) on the final colour — the §A2 breakup scale — for a faint print texture that keeps the op-art crisp.

**Held for post-M7 (surfaced to Matt).** Deeper nesting toward cap 4 (reverses the Restrained pick); curl-warp organic flow (a felt-motion change). Both wait on the live review.

**Empirical findings worth keeping.**
- **★ Don't reach for fBM to warp a boundary.** The first cut used `fbm4` (4-octave `perlin3d`, ×2 per pixel) and blew p99 to 8.87 ms — over the 8 ms budget, on a preset whose whole premise is "very cheap 2D." A 4-tap single-octave value noise gives the same organic-boundary read at ~8× less cost (p95 2.2 ms). For a *soft displacement of a low-frequency field*, single-octave value noise is the right tool; fBM is for detail-rich surfaces (SHADER_CRAFT §3), not cheap domain warps. (FA #64-adjacent: measure perf on any per-pixel noise addition to a direct preset.)

**References.** D-189/D-190 (PG.4.1/4.2), [D-037], `docs/SHADER_CRAFT.md` §3 (noise) / §9 (perf budgets), `docs/presets/psychedelic_geometry/PG_4_TRUCHET_LOOM.md` §A2 (breakup scale) / §A9.


---

## D-192: Audio-visual coupling metric — cross-correlation of visual delta vs. energy, report-first (QG.3)

**Context.** "The motion tracks the music" was unmeasurable — closeouts asserted it, the M7 seat judged it, but no instrument put a number on it. QG.3 builds that instrument so a dead-coupled route (visual delta uncorrelated with energy) is at least *partially* measurable before a human looks.

**Metric.** Per replay frame, a scalar **visual delta** = mean |luma(frame i) − luma(frame i−1)| over the 64×64 reduced-resolution render (0..1), written to `coupling/<preset>_<fixture>_visual_delta.csv`. **Coupling** = cross-correlation of that series against the `features.csv` energy envelope (composite = mean of `bass`/`mid`/`treble`, plus each band) at lags 0–500 ms — reported per pair as peak Pearson r, lag at peak, and a stationarity note (r over non-overlapping 10 s windows: min/median/max, so chorus-only coupling is visible). Pure-Swift/Accelerate; no new dependencies. **Negative control** (bounds the noise floor): fixture A's energy against fixture B's rendered frames — real audio mismatched to real frames (FA #27, no hand-authored envelope). Producer: `CouplingReportTests` (diagnostic suite, no content assertions; gated `PHOSPHENE_COUPLING=1` — the sweep renders ~50k frames).

**Report-first, no gate — and why the gate (QG.3.1) is deferred.** Verdicts on an uncalibrated proxy are forbidden (PRESET_SESSION_CHECKLIST Part 2). The QG.3 baseline (`docs/diagnostics/QG3_COUPLING_BASELINE.md`) surfaced a blocking finding: the offline render harness (reused from `PresetRegressionTests`) renders **one fragment with zeroed aux state** (slot-6 CPU accumulators, feedback history texture, mv_warp marks buffer — none reconstructable from CSV), so **11 of 13 certified presets render fully static offline** (`visual_delta = 0`) — the same reason those presets record identical dHashes across `PresetRegressionTests`' fixtures. Only Ferrofluid Ocean and Murmuration produce measurable output; only Murmuration/`love_rehab` (peak r +0.30) clears the +0.08 noise floor. **A gate needs a population; the measurable population is 2.** Prerequisite for QG.3.1: a headless multi-pass/state-reconstructing render. Provisional floor when that lands: peak composite r ≥ 0.15 (≈2× the noise ceiling) — a hypothesis to re-derive, not a committed threshold.

**Noise-floor caveat (load-bearing).** Peak-over-lag Pearson r is positively biased — max over ~22 lag candidates of noisy correlations inflates above 0. The negative control measures this at +0.08 (mismatched real pairs), which is the noise ceiling any real coupling must clear. This is why the control is mandatory and why raw r ≈ floor reads as "coupling not measured as present."

**Scope guard.** Low coupling is **never** interpreted as "preset is bad" in any doc — it is "coupling not measured as present"; the M7 seat judges feel (manual-validation rule stands). No preset is tuned in response to its number. Below-floor presets are route/coupling-defect candidates (→ KNOWN_ISSUES), but every below-floor result in the QG.3 baseline is a render-substrate measurement gap, not a defect, so **no KNOWN_ISSUES entry is filed**. The report is attached to preset closeouts (`Scripts/closeout_evidence.sh` surfaces the baseline pointer), never asserted against.

**References.** `docs/diagnostics/QG3_COUPLING_BASELINE.md` (baseline table + control + recommended floor), `docs/diagnostics/QG1_REPLAY_AUDIT.md` (the "no headless render" gap this inherits), [D-180] (route-coverage gate + the CPU-computed StemFeatures fixture boundary), [D-193] (measurement substrate), `docs/ENGINE/SESSION_REPLAY.md` (SR.1 uncalibrated-proxy doctrine), FA #27 (no hand-authored envelopes). `CouplingReportTests.swift`.

## D-193: Coupling measurement substrate — shared multi-pass render, per-preset floor, warning-tier gate (QG.3.1)

**Context.** [D-192] shipped the coupling metric report-first and deferred the gate because the offline single-fragment/zeroed-state render made 11/13 certified presets render static (`visual_delta = 0`) — measurable for only 2. Matt's call (QG.3.1, "make measurable first; the gate flip becomes QG.3.2"): build the real render substrate, re-baseline, THEN recommend a floor.

**Decision — one shared faithful render.** The photosensitivity flash gate (`MultiPassFlashHarnessTests`) already drives all 10 multi-pass / feedback / follower presets headless through their REAL render loops with feedback persistence (mv_warp swap, rayMarch 128-step budget, ticked followers). Extract that render into a shared `MultiPassRenderHarness` parameterized by (drive train, per-frame pixel reducer). Two consumers now share ONE render (FA #66 — drive the live path, never reimplement): the flash gate (synthetic worst-case beat train → WCAG luminance → flash-rate) and the coupling report (REAL reconstructed-fixture train, FA #27 → luma field → visual delta). The 3 single-pass presets (Ferrofluid Ocean, Murmuration, Nimbus) read their response in one fragment (+ the ticked Nimbus CPU follower) and keep the single-fragment path. The flash gate's assertions are byte-identical after the extraction (verified: Dragon Bloom Δ0.904, Nacre 0.063–0.153, etc. unchanged).

**Finding — the distribution (all 13 measurable).** 11/13 clear their own noise floor with margin on at least one fixture (Skein +0.69, Dragon Bloom +0.47, Filigree +0.39, Lumen Mosaic +0.37, Fata Morgana +0.32, Murmuration +0.29, Mitosis +0.27, Floret +0.25, Nimbus +0.23, Cytokinesis +0.20, Glaze +0.13). Two read weak for PROXY reasons, not defects: **Nacre** (+0.05) couples via a subtle downbeat *camera push* that barely moves mean-abs frame delta; **Ferrofluid Ocean** (+0.08, at floor) is single-fragment-approximated (its faithful render needs post + a baked height field). Both are certified + M7-approved.

**The floor is PER-PRESET, not global.** Negative controls span −0.02…+0.13; Dragon Bloom's +0.13 is highest because long feedback trails autocorrelate the frame sequence (peak-over-lag r is also positively biased). A flat global floor would misjudge feedback presets. Judge each preset against its own control, on its best fixture (`there_there`/rock scores lowest everywhere — a low-dynamics fixture property, not a preset trait).

**Recommendation — QG.3.2 is a WARNING tier, not a hard cert gate.** A hard floor that catches genuinely-dead coupling would false-red the two M7-approved weak-reading presets — the "verdict on an uncalibrated proxy" failure this whole line of work exists to avoid ([D-064] doctrine). Ship QG.3.2 as a review flag (best-fixture peak r < 0.15 AND < control + 0.10 → "coupling not measured as present — review"), surfaced in closeout evidence, never a certification blocker. Validate the proxy against Matt's felt-coupling ordering (Nacre-low / Skein-high are the anchors) before any blocking gate. No KNOWN_ISSUES filed — no preset reads below its floor for a non-proxy reason.

**References.** `docs/diagnostics/QG3_COUPLING_BASELINE.md` (the QG.3.1 distribution + per-preset floors + recommendation), [D-192] (the metric), [D-180] (route coverage + StemFeatures fixture boundary), [D-171] (Nacre downbeat push — the camera-motion coupling the proxy under-reads), FA #66 (drive the live path), FA #27. `MultiPassRenderHarness.swift`, `CouplingReportTests.swift`, `MultiPassFlashHarnessTests.swift`.

---

## D-194: Truchet Loom retired — concept scrapped after first live M7 (TLRETIRE.1, 2026-07-21)

**Status.** Accepted. Retires the preset added at D-189/190/191 (PG.4.1/4.2/4.3). The preset's whole footprint is deleted; the reusable-looking `SpectralHistoryBuffer` slots built for it are removed too (no other consumer — a deleted concept does not earn "kernel waiting for the right concept" preservation, per CLAUDE.md §Authoring Discipline).

**Context.** Truchet Loom was the first Phase PG preset — a `direct` multiscale curved-Truchet weave whose subdivision depth tracked a smoothed `spectral_flux` (the "complexity-mapping" music idea). It shipped PG.4.1–4.3 green and `certified: false`. Its first live M7 (Matt, 2026-07-21) rejected it at the concept level, not the tuning level.

**Matt's M7 verdict (verbatim themes).** "I can see the square tiles used to construct the canvas." "Music causes the structure to jitter, which looks like a bug." "Any concept of loom is lost." "I don't understand what you are building and why this is 'psychedelic geometry.'" And on a proposed replacement look: "This doesn't sound interesting… I'm not interested in cheap. I'm interested in complex and meticulous, real craft and attention to detail."

**Root cause.** The design doc described the *look* with flowing fine-line scallop op-art references (`01_macro_labyrinth_floor.jpg`) but specified the *mechanic* as "port multiscale Truchet (IQ/Carlson)." Those are two different aesthetics — Truchet is a blocky geometric grid pattern; the references are flowing gridless line-art. The build followed the mechanic and drifted straight off the references. Both live complaints fall out of that: a Truchet weave IS a grid (so it "shows its tiles"), and "shatter into detail on busy music" means the pattern literally reshuffles (so it "jitters"). The clean stills hid both.

**Lessons worth keeping.**
- **★ Reference images are the source of truth for the LOOK.** A design-doc "port algorithm X" instruction must be validated to actually produce the reference look *before* building — a mechanic and a reference set can silently point at different aesthetics.
- **★ Stills lie about living presets.** Truchet's stills read as clean op-art; alive it was a jittering grid. Get MOTION + the real living behaviour in front of Matt early, and get the LOOK approved before wiring music (the KS spike-first lesson, re-learned).
- **★ Matt's craft bar: complex/meticulous/real-craft, not cheap.** "Deliverable / cheap / proven" is not a selling point for a preset direction; depth and detail are.
- Two PG-phase presets have now died at M7 on a fidelity/concept miss (Kinetic Sculpture, Truchet Loom) — the phase's "prove a routing strategy with a simple 2D mechanic" framing keeps under-delivering on craft; worth re-examining before building the remaining four.

**References.** D-189/190/191 (the retired preset), D-188 (Kinetic Sculpture retirement — the sibling M7-fidelity failure), CLAUDE.md §Authoring Discipline ("reusable infrastructure is not a defense for a failed concept"), `docs/PRESET_SESSION_CHECKLIST.md` Part 2 (musical-role + reference-grounding + stills-aren't-behaviours).

## D-195: Motion review gate — mechanize the pre-M7 temporal check (PG.MG, 2026-07-21)

**Status.** Accepted. Adds `Scripts/motion_gate.sh` + `PRESET_SESSION_CHECKLIST.md` Part 1 step 7. The temporal counterpart to the D-181 render-comparison sheet.

**Context / root cause it closes.** The still-review harness (`PresetVisualReviewTests` + `compare_render.sh`, D-181) renders exactly three disconnected frames per preset — `{silence,mid,beat}`. Temporal defects (jitter, structure-pop, strobe, freeze) leave no trace in a still sheet. Truchet Loom (D-194) passed still-review and jittered "like a bug" on its first live M7; that class of miss should never reach Matt's seat. The diagnosis that unblocked this: "I can't watch it move" was a false ceiling — frames extract, motion reconstructs from the sequence, and jitter is a measurable frame-to-frame delta (Matt, 2026-07-21: "extract every frame and piece together its motion… find the jitter through other data points").

**Mechanism.** `motion_gate.sh <preset> <frames-src>` accepts a video/gif or a directory of sequence PNGs (or the newest `RENDER_SEQUENCE` dump), then via ffmpeg computes the mean-luminance of each consecutive-frame difference — a per-frame motion-magnitude signal. Smooth flow → steady moderate values; jitter/pop/strobe → high-frequency spikes (`>3× median`); freeze → ~0. It stages ~8 evenly-spaced sample frames for the reader (Claude) to **view as a sequence** and points at the curated `target_animated.gif`. Verified end-to-end on `dragon_bloom/target_animated.gif` (0 spikes / 59 diffs — reads smooth, as a certified preset should).

**Boundaries.** Reader-is-the-eyes (D-064): the spike count is evidence; the smooth/on-concept/matches-reference **verdict is the reader's**, never an auto-pass. Deps are ffmpeg + python3 only (no ImageMagick — matches the dev box). The still sheet (D-181) is retained — the two are complementary (frame fidelity vs. temporal behaviour). The sequence **feed** — a contiguous `RENDER_SEQUENCE` dump — reuses `renderFrame` in `PresetVisualReviewTests`; it lands with the next preset that needs it (no preset in flight to render at authoring time). Existing certified presets regression-check today against their committed `target_animated.gif`.

**References.** D-181 (the still-sheet gate this parallels), D-064 (reader-is-the-eyes, no auto-scoring), D-194 (the Truchet miss it prevents), `PRESET_SESSION_CHECKLIST.md` Part 1 step 7 + Part 2 ("reference images are still moments; presets are behaviours over time").

## D-196: Cymatic Resonance CR.1 maquette — plate + hero brightness→figure (CR.1, 2026-07-22)

**Status.** Accepted. First `direct`+`post_process` preset. `certified:false` (clay maquette, SHADER_CRAFT §2.2); pending Matt's live M7. Count 25 → 26.

**What landed.** A resonant square plate whose Chladni nodal figure is selected live by the music's brightness. `CymaticResonance.metal` renders the **plus-basis** eigenmode superposition `φ = cos(mπξ)cos(nπη) + cos(nπξ)cos(mπη)` (PORTED, ref Shadertoy 4dXSD2 — NOT its minus combination), crossfading two adjacent modes on a fixed complexity ladder; the crisp nodal set is a distance-to-zero-isoline ridge with `fwidth` isotropic AA (§18.3), displaced into relief whose normal is a §18.9 central-difference of a smooth height field, lit by one warm key + GGX (the depth cue), jewel-emissive on a deep-black plate, strong oblique tilt, through the shared ACES + bloom chain. `CymaticResonanceState` (slot 6) holds the EMA-smoothed `spectral_centroid` → ladder position (HERO), the `bassDev` fast-attack snap envelope (snap-to-simple), and the `smoothstep(0.02,0.06,totalStemEnergy)` D-019 warmup gate. Deviation/centroid primitives only, one primitive per layer (FA #67 / #31).

**Engine change.** `PostProcessChain.render`/`runScenePass` gained an optional `presetFragmentBuffer` bound at scene-pass fragment index 6, and `RenderPipeline+PostProcess` threads the live `directPresetFragmentBuffer` into it. This path (`drawWithPostProcess` → `runScenePass`) had **no production consumer** before CR (every ray-march post_process preset bypasses it via `runBloomAndComposite` with an externally-lit texture), so the change is byte-identical for all existing presets. `PresetLoader` already compiles a `post_process` preset's primary `pipelineState` for `.rgba16Float` (the HDR scene texture) — CR is the first to exercise that. `PresetRegressionTests` gained a matching `renderPostProcessFrame` branch (zeroed slot-6 = deterministic silence fundamental) so direct+post_process presets are golden-gated.

**★ Concept-gate correction #5 (found at the maquette, the value of rendering early).** The plus basis was adopted (correction #1) to kill the minus basis's main-diagonal nodal line (ξ=η, present on every figure). But the plus basis forces the **anti-diagonal** nodal line (η=1−ξ) whenever m,n have **opposite parity** — verified: `max|φ|` along η=1−ξ is exactly 0 for (1,2),(2,3),(3,4)… and 2 for (1,3),(2,4),(3,5)…. The design's adjacent-pair ladder `(1,2)(1,3)(2,3)…` is riddled with opposite-parity modes — **including the fundamental (1,2)**, the silence rest state — so half its figures rendered the very spurious diagonal the plus↔minus switch was meant to remove (starkly visible in the first silence render). Fixed by switching the ladder to the **same-parity `(m,m+2)` family `(1,3)…(11,13)`**: 4-fold symmetric AND diagonal-free on both diagonals, monotonic complexity coarse→fine. Same-parity is the load-bearing property, not the specific family.

**Evidence.** Embodiment (production PostProcessChain path, `CymaticResonanceVisualTests`): ridge-coverage litFraction bright 0.140 > dim 0.054 (finer figure with brightness) > drop 0.051 (snap-to-simple); structural pixel-diff dim↔bright 17.1, bright↔drop 17.9 (a real geometric change, not a colour shift). Silence non-black + calm (maxLuma > 4, meanLuma ≈ 7). Perf 1080p full-chain GPU p50/p95/p99 = 1.05 / 2.35 / 5.56 ms (≪ 7 ms Tier-2). Motion gate (60-frame centroid ramp + drop): mean 3.87, one spike at the intentional drop, zero frozen frames.

**Deferred to CR.2/CR.3.** Materials + four-scale micro cascade (thin-film, sand-accumulation band, fbm grain, roughness breakup); secondary audio (`arousal` excitation, `spectral_centroid`→valence IBL hue, drum ridge shimmer); optional shallow DOF; certification. **Open M7 tunes (one-line each):** does the (currently magenta-dominant) jewel palette read on the figure, and is the 11-step ladder length right.

**References.** `docs/presets/psychedelic_geometry/PG_CR_CYMATIC_RESONANCE.md` (Part A design of record + the concept-gate correction table, now #1–#5), D-029 (direct_time_modulation), D-019 (warmup), D-026 (deviation primitives), D-037 (non-black silence), SHADER_CRAFT §18.9 (derived normal) / §18.3 (isotropic AA) / §6.4 (bloom).
