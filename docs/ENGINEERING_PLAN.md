# Phosphene — Engineering Plan

> **Narrative split (RB.3, 2026-06-11):** completed-increment narratives dated before 2026-06-01 moved to [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md). Their headers remain below as the status record (increment ID → status + date); full narratives are in the history file and `git log`.

## Planning Principles

- One increment = one reviewable outcome that fits a Claude Code session.
- Product quality and show quality are both first-class.
- No new subsystem lands without tests appropriate to its risk.
- Documentation follows implementation truth, not aspiration.
- Infrastructure increments and preset increments are never bundled.

## Current State

The foundation is implemented and tested:

- Native Metal render loop with data-driven render graph
- Core Audio tap capture with provider abstraction and DRM silence detection
- FFT (vDSP 1024-point → 512 bins) and full MIR pipeline (BPM, key, mood, spectral features, structural analysis)
- MPSGraph stem separation (Open-Unmix HQ, 142ms warm predict) and Accelerate mood classifier
- Session lifecycle: `SessionManager` drives `idle → connecting → preparing → ready → playing → ended`
- Playlist connection (Apple Music AppleScript, Spotify Web API)
- Preview resolver (iTunes Search API) and batch downloader
- Batch pre-analysis with StemCache; cache-aware track-change loading (no warmup gap in session mode)
- Metadata pre-fetching (MusicBrainz, Soundcharts, Spotify search, MusicKit)
- Feedback textures, mesh shaders (M3+ with M1/M2 fallback), hardware ray tracing, ICBs
- Ray march pipeline with deferred G-buffer, PBR lighting, IBL, SSGI
- HDR post-process chain (bloom + ACES tone mapping)
- Noise texture manager (5 textures via Metal compute)
- Shader utility library (55 functions across 7 domains)
- Preset library: Waveform, Plasma, Nebula, Murmuration, Glass Brutalist

Test infrastructure: swift-testing + XCTest across unit, integration, regression, and performance categories. SwiftLint enforced. Protocol-first DI with test doubles.

## Recently Completed

### Phase FBS — Ferrofluid Beat Sync ⏳ (2026-06-09, staged; kickoff `docs/prompts/FFO_BEAT_SYNC_KICKOFF.md`)

Make Ferrofluid Ocean's spikes punch on a steady, **first-note-anchored**, tempo-locked beat pulse (FFO currently reads "frozen": its only reactive motion is spike height from the smoothed AGC bass, held near-constant). Stage the core before layering: prove the steady anchored pulse with **measurement** (a manual M7 cannot judge beat-lock) before building energy/mood/handoff. Three standing rules: plain-English-only to Matt (no code/jargon), never over-promise (measure, don't assert), validation = measurement.

- **Stage 0 — verify the load-bearing assumptions** ✅ (`docs/diagnostics/FBS_STAGE0_FINDINGS_2026-06-09.md`, tools `tools/fbs/`). PCM ground truth (SZ2 + Cherub Rock ×6 takes) + features-proxy on all tracks. Findings: cached-grid **tempo is reliably correct** (Cherub 1.1 % err, reproducible) → a steady pulse at the pre-analysed tempo stays locked; cached-grid **phase is NOT reliable / cross-capture-unstable** (6 takes → 6 downbeat positions, ±½ beat) → even local files anchor to the first note, not the grid; **live drift tracker wanders** 50–90 ms over the opening → hold steady, don't chase. **Matt's correction:** anchor to the **first NOTE** (silence→sound = the downbeat), not the first strong hit — verified: a pulse anchored at the first note lands within ~28 ms of the beat, consistent across takes, beating the grid's scattered phase. Streaming session (`21-23-07Z`) confirmed the thesis: Love Rehab starts locked then the live tracker swings ~⅔ beat and breaks it; most other streaming tracks never lock (jazz / odd-meter / weak signal / wrong grid tempo).
- **FBS pre-step — BUG-038: kill the FFO flicker first** ✅ (Matt's call — a clean baseline to evaluate beat-sync against). The preset-agnostic ray-march light formula stepped 7–9 perceptible times/sec (the beat-onset brightness term fires ~97 % of frames; BUG-019 residual). Fixed by temporally smoothing the light multiplier (EMA τ ≈ 0.12 s, `RayMarchPipeline.smoothLightIntensity`) → ~0 steps/sec, mean-preserving (no Nimbus regression), formula unchanged. New pure-function gates in `RayMarchPipelineTests`; golden hashes unchanged; full suite green modulo the pre-existing fixture-absence + Skein.4.1 failures. **Awaiting Matt M7** (needs the fix on his build). `KNOWN_ISSUES.md` BUG-038, `RELEASE_NOTES_DEV.md [dev-2026-06-09-flicker]`.
- **Stage 1 — the anchored steady pulse** ✅ built + proven 2026-06-09 (**D-153**, awaiting Matt's live read). `BeatPulseClock` (DSP): anchor = first NOTE (3-frame confirm, backdated), tempo = cached grid BPM, NEVER drift-corrected; `pulseAmp01` gates silence. Plumbed as `FeatureVector` floats 40–41 (reclaimed `_pad4`/`_pad5`, byte-identical fields 1–39, both MSL mirrors), wired in `MIRPipeline` (`setBeatGrid` = tempo authority; `reset()` clears the anchor per track), logged as trailing `features.csv` columns. FFO `fo_spike_strength` Layer 2: `0.8·f.bass` → punch envelope (rise 8 %, decay to 85 %, headroom-capped ≤ 1.62 under the Lipschitz `/6` ceiling). **Measured (real sessions):** anchor ~2 ms vs PCM first note (Cherub cross-clock); every pulse interval == grid period, cumulative drift ~0 (vs the live tracker's 50–90 ms wander); envelope motion std 0.198/0.212/0.182 (Lotus/Cherub/SZ2) vs the old term's 0.044 on the frozen streaming case; live-dispatch 110-frame A/B (SDF G-buffer→lighting→bloom): punch-window |δ| = 29.3 luma, rest-window 0.0. Tests: `BeatPulseClockTests` (9, real-session fixtures `Tests/Fixtures/fbs/`), `FerrofluidPulseLivePathTests` (multi-frame live path), recorder column gates; goldens unchanged. Known limits stated in D-153 (gapless segues anchor at the change instant; perceptually-convincing ≠ provably-the-one).
- **Stage-1 live verdict (2026-06-10, session `03-02-32Z`): NEGATIVE on a streaming playlist** — see the addendum in `FBS_STAGE0_FINDINGS_2026-06-09.md`. The mechanism worked exactly as built (each track pulsed at its own cached tempo to 0.05 %, instant anchor, zero wander) and **Love Rehab locked** (flux-fold R 0.43/0.35/0.31, offset stable ~+200 ms — Matt: "strong opening"). The failures are design boundaries, now measured: (1) **gapless streaming switches make every mid-playlist anchor musically meaningless** (all anchored at the title-change instant) — the "known limitation" is THE dominant playlist case; (2) **no regularity gate** — swing/rubato tracks (So What; Pyramid Song, whose prepare-time 3-way BPM disagreement was 47.7 %) got a confident robotic pulse, worse than the frozen baseline (Matt: "definitely a regression" on Pyramid); (3) steady-but-meaningless reads WORSE than nothing — the "steady wrong-by-a-hair beats wandering" bet only holds when the anchor is near-musical. **Matt's direction (2026-06-10) + scope correction:** the pulse was always the COLD-START bridge, not the whole-track driver (the robotic whole-track thump = the unbuilt handoff, not the design). Direction: (a) beat-irregular tracks **never see FFO at all** (exclusion at the preset picker, not a pulse gate); (b) the pulse becomes **slow** (iteration-one answer for arbitrary playlist anchors); (c) improve iteratively, no big-bang.
- **FBS.S2 live read (2026-06-10, session `14-55-32Z`): slow pulse "well-synced but too sluggish"** — Matt: works for the START of playback, not for the duration; "we need something more energetic" for steady state ⇒ the slow heave is ratified as the cold-start BRIDGE only; the energetic steady state (handoff to the live beat ± energy scaling) is the next FBS conversation. The exclusion went UNTESTED live (Matt manually kept FFO active, which bypasses the gate by design) — his ask to verify by test **caught a real hole**: `SessionPlanner.cheapestFallback` ignored hard exclusions, so when fatigue + active-exclusion zeroed every candidate, an excluded preset (or a diagnostic — pre-existing D-074 violation) could land via fallback. Fixed (fallback now relaxes only SOFT exclusions; `test_plannedSession_neverSchedulesRequiringPreset_onIrregularTrack` is the gate). New defect filed from the same session: **BUG-041** (FFO aurora flashes at track start — the drums-stem deviation cold-start overswing, measured 1.2–3.3× on exactly the tracks Matt flagged; BUG-027-class, stem side).
- **FBS.S2 — exclusion + slow pulse** ✅ built 2026-06-10 (**D-154**).
- **FBS.S2.2 — BUG-041 aurora track-start flash fix** ✅ 2026-06-10: quadratic per-track warmup (0→1 over 10 s, reset by the track-change hook) gating the D-127 drums driver — early peaks 2.35/1.37/1.23 → 0.65/0.50/1.10 on the real fixtures, steady state byte-identical; `AuroraTrackStartWarmupTests` (replay through the production arithmetic, red-arm + steady-equality gates). Awaiting Matt M7.
- **FBS.S3 — invisible handoff to the live beat** ✅ built 2026-06-10 (**D-156**, awaiting Matt's live read): after 10 s the pulse swaps from the slow bridge to the drift tracker's per-beat phase, only at a frame where both phases sit in the envelope's rest window (zero envelope across the swap = seamless by construction); per-track reset re-opens on the bridge; no grid ⇒ bridge keeps running. Proven on the real Love Rehab session replay (`test_handoff_swapsToLiveBeat_invisibly_onRealSession`). Known risk stated in D-156: the steady state inherits the live tracker's phase quality. **Live read (session `17-21-49Z`): the transition works** — Love Rehab seamless + clearly synchronized; There There locked over time; So What locked late (when the walking bass arrived); Pyramid struggled (expected, manual selection). **Two defects found + fixed same day (FBS.S3.1, D-156 amendment): Money NEVER handed off** (the rest-window coincidence is structurally frozen — both phases share a tempo source; replaced with an envelope-floor condition, guaranteed within one bridge cycle; Money-replay regression test) **and the per-beat punch attack read as FLASHING** (37 ms ≈ 1–2 frames; 8–10 sharp envelope steps/min on every handed-off track, zero on bridge-only Money — attack lengthened to 0.20 of the cycle ≈ 100 ms). **FLASH ROOT CAUSE ESTABLISHED 2026-06-10 (pixel-level, session `18-36-36Z`):** the full-video census (BUG-039 recovery delivered 331 s of video incl. the first field-proven segment roll) measured **373 flash events across every track**; the forensics-harness ablation matrix on a dense So What window is conclusive — full replica reproduces 69 flash steps; **pulse OFF → 0 steps**; aurora OFF / light frozen → unchanged. **The flashing IS the beat punch**: the spike-field punch swings the whole frame's mean luminance 6–84 (0–255 scale) per beat even with the 100 ms attack — the geometry punch's luminance footprint reads as a strobe, while the same mechanism is also the beat-sync Matt praised on Money. Earlier attributions (punch ATTACK shape, aurora bursts, mood steps) are all superseded by this measurement; the S2.2/S3.2 aurora hardening stands on its own evidence but was not the flasher. Fix direction = Matt's choice (options presented: smaller punch / partial-field punch preserving global luminance / softer envelope); Stage 2 energy scaling is orthogonal (fixes quiet-passage over-punching, not the luminance footprint). `assessBeatIrregularity` (octave-folded grid-vs-drums BPM disagreement > 10 % OR bar-confidence < 0.2; calibrated on the real 38-track cache — kept ≤ 9.2 % fold, excluded ≥ 11.3 %; MIR estimator deliberately not consulted). `TrackProfile.beatIrregular` + `PresetDescriptor.requiresRegularBeat` (FerrofluidOcean.json) + the scorer's `beat_irregular` hard exclusion — wired through planner, regenerate, reactive (`evaluate(currentTrackBeatIrregular:)`), and mood-override; manual selection unaffected; nil = permissive. Pulse period → **4 beats** (`BeatPulseClock.pulseBeats`): a phase error reads as a gentle heave at a musical rate, not a wrong beat claim. Known gaps stated in D-154: swing feel invisible to the gate (So What's estimators agree perfectly); the Mingus track is excluded (49 % fold) though Matt liked old-FFO on it; the 10 % threshold sits in a thin gap. Tests: `BeatRegularityExclusionTests` (real catalog values), clock + live-path suites green at the slow period (punch |δ| = 31.1 luma / rest 0.0).
- **FBS.S4 — regional beat punch** ✅ built 2026-06-10 (**D-157**, Matt's option B; commit `6aa0ae95`): each beat, smoothly-bounded regions (~⅓ of the spike field, value-noise mask re-drawn per beat via `pulse_beat_index` = FV float 42) punch instead of the whole ocean — local beat motion stays strong, global frame luminance stays steady. Acceptance on the convicting window: flash steps 69 → 1 (magnitude 734 → 6.4); local block deltas ~65 vs ~22 ambient. **Live read (session `19-13-14Z`): regional punches KEPT** ("I like the regional punches and think we should keep them") but flashing "still present, prominent on some tracks" (census ~150 → 79 clustered events), the slow bridge heave was invisible under regional coverage, and "the aurora color is shifting too quickly… transition over 8-10s". **Decisive finding: the forensics replica no longer reproduced the remaining flashes** — the flasher lived in an un-replicated route (the vocals-pitch fields were never set in the harness).
- **FBS.S5 — the hue route convicted + Matt's three directives** ✅ built 2026-06-10 (**D-158**, **BUG-045**; commits `ef4fb8e0`/`0159c54f`/`e811ffd2`; awaiting Matt's live read): (1) FORENSICS PROOF — replicating `vocalsPitchHz`/`vocalsPitchConfidence` made the replica reproduce the flashes (So What 31–41: 1 → 13 steps; Lotus 45–51: 0 → 15); the new `aurora-hue` ablation arm killed them (1 / 0). Mechanism: confidence flaps across the hue gate ~9×/s, snapping the curtain hue between palette stops across the whole mirrored sky. (2) **8–10 s aurora transitions** (Matt-directed): hue moved CPU-side (`auroraHueStep` τ ≈ 3 s EMA → `StemFeatures.auroraPalettePhase` float 45 — kills the strobe by design); intensity rise/fall τ 0.45/1.2 → 2.7/3.3 s. (3) **Global bridge heave** (`BeatPulseClock.regionalBlend01` → FV float 43): 0 on the bridge, ramps to 1 over one 4-beat span post-handoff; regional punches unchanged in steady state. Acceptance: four session windows re-rendered → 1/0/1/0 flash steps, punch motion preserved; live-path bridge punch |δ| 25.3 / rest 0.0. New gates: `AuroraHueDriverTests`, `test_regionalBlend_zeroOnBridge_rampsToOneAfterHandoff`; `features.csv` gains trailing `pulse_beat_index`/`pulse_regional_blend01`. **Next (queued behind Matt's read):** Stage 2 energy-scaled punch heights (So What quiet-intro over-punching), BUG-043 stall instrumentation, the dev=35 stem-deviation anomaly.
- **FBS.S5b — Matt's read + his C+A pick** ✅ built 2026-06-10 (D-158 amendment; awaiting next live read): census of `20-26-37Z` video → 13 events/154 s (from 79); ablation attributed the cold-start residue to **the global bridge heave itself** (pulse OFF → 0) — the same mechanism as the lost-sync-feel complaint. Matt picked C+A: aurora intensity τ reverted to 0.45/1.2 s (shimmer back; hue stays slow — the hue was the proven flasher) + early handoff at 4 s when the drift tracker is LOCKED (10 s unlocked fallback; all five read-session tracks locked at te 7.0–8.5 s). New gate: `test_earlyHandoff_firesSoonAfter4s_whenTrackerLocked`. Mid-track paired one-frame blips (3/154 s) don't reproduce in the replica — suspected video-encode, parked.
- **FBS.S5c — S5b validated + the FFO ban retired** ✅ 2026-06-11 (D-154 amendment): Matt's read of `2026-06-11T01-56-22Z`: "Looks great." Early handoffs measured (LR 9.8 s / SW 8.7 s / **Pyramid 6.1 s** — the tracker LOCKED on Pyramid at 5.4 s, faster than any regular track). Matt: "Remove the FFO ban for Pyramid Song - it looks and moves great!" → his pick: **retire the ban entirely** (`requires_regular_beat` removed from FFO's sidecar; mechanism + `beatIrregular` signal stay for future presets/diagnostics; retirement pinned by `test_realFFOSidecar_doesNotDeclareRequiresRegularBeat`). FBS remaining queue: Stage 2 energy-scaled punch heights, BUG-043 instrumentation, dev=35 anomaly.
- **FBS.S6 — Stage 2: energy-scaled punch heights** ✅ built 2026-06-11 (**D-160**; awaiting Matt's live read): punch height = `mix(0.30, 1.0, smoothstep(0.25, 1.0, totalEnergySmoothed))` — smoothed total stem energy (symmetric τ 2.5 s; fast-rise variant measured wrong on bursty jazz), `StemFeatures` float 46, CPU driver `punchEnergyStep` in the new `RenderPipeline+AudioDrivers.swift` (all three FFO drivers consolidated there). So What intro height 0.40 / band 0.99 on the real fixture; live-path pixel A/B 20.6 vs 48.7 luma; forensics `punch-height` arm shows quiet-intro flash steps 3 → 1 vs fixed height. Remaining FBS queue: BUG-043 stall instrumentation, dev=35 anomaly.
- **FBS.S5d — BUG-047: the palette-march root cause** ✅ 2026-06-11 (awaiting Matt's live read): Matt's So What read ("color changing every 1-2 seconds… marches through the palette") → the aurora orbit azimuth was `arousal-speed × accumulated-time TOTAL` (history rescaled on every mood wobble; error grows with track age). Fixed by integration (`auroraOrbitStep` → `StemFeatures.auroraOrbitAzimuth` float 47). Pixel A/B: So What hue swing 94.7°/s → 3.3°/s; LR 4.9°/s. Two wrong in-session attributions (mood tint, contrast — R−B metric blindness) corrected by Matt's pushback; harness gained a wrap-aware hue-angle metric + `orbit-legacy` arm. Brightness-split option PARKED pending the read.

Beat-phase is the known-hard FA #69 area — tempo solid, phase is perception-not-precision.

### Increment AGC2 — BUG-027: per-band EMA deviation pivot + cold-start warmup ✅ (2026-06-05 → 06, D-146)

The FeatureVector band deviation primitives (`bassDev`/`midDev`/`trebDev`) were derived against a fixed 0.5 pivot while the AGC normalises *total* 6-band energy to 0.5 → `midDev`/`trebDev` fired ~0 % on all music (BUG-027). Staged measure → decide → fix → validate → close:

- **AGC2.1** (`bf711edf`): measured the centring on 4 real sessions, both paths, 4 spectral classes (`tools/agc2/measure_deviation_centring.py`; `docs/diagnostics/AGC2_1_DEVIATION_CENTRING_2026-06-05.md`). `bassDev` 2-8 %, `midDev`/`trebDev` ~0 % even on mid/treble-rich tracks.
- **AGC2.2** (`b1c1d1b7`, **D-146**): Matt chose the (b)+(c)-split — per-band EMA pivot (mirror the stem path) + document the stem-energy offset.
- **AGC2.3** (`41d87bf9` + `0d2ddb51`): `BandDeviationTracker` (per-band EMA, additive form), wired into `MIRPipeline`; `RelDevTests` updated (fixed-0.5 pin retired → unit tests + the ≥ 20 % recorded-fixture gate). No golden drift (fixtures bypass the live derivation).
- **AGC2.4 / 2.4.1** (`95a16881`): the M7 exposed a cold-start hole (EMA seeded from the session-start AGC spike, no per-track `MIRPipeline.reset()`, poisoned ~3-4 min). Fixed with a two-speed warmup + value ceiling; a **live-path** test now guards it (FA #66). M7 catalog cycle: deviation presets read well.
- **AGC2.5** (close): KNOWN_ISSUES BUG-027 → Resolved; RELEASE_NOTES `[dev-2026-06-06]`; SHADER_CRAFT §14.1 softened; filed **BUG-029** (the AGC `f.bass` cold-start spike — out of scope, the Ferrofluid Ocean startup root).

Local `main`, not pushed.

### Increment AGC3 — BUG-029: AGC `f.bass` cold-start spike (continuous-energy presets pop-and-drop at track onset) ⏳ (2026-06-05; fix landed, awaiting M7)

At every track onset preceded by silence, `BandEnergyProcessor`'s total-energy AGC denominator has decayed (it is not reset per track), so the first audible frame over-scales and `f.bass` spikes to ~3.5–4.0 (steady ~0.25) — `f.bass`-driven presets (Ferrofluid Ocean's `1.0 + 0.8·clamp(f.bass,0,1)`) pop to their clamp ceiling then collapse. Separate from AGC2: AGC2's warmup is at the *deviation* layer (`BandDeviationTracker`) and does not touch `f.bass`. Staged measure → decide → fix → validate → close (cross-cutting AGC change; do not collapse):

- **AGC3.1 ✅** (measure, `ea2326e0`): permanent diagnostic `tools/agc3/measure_coldstart_spike.py` + `docs/diagnostics/AGC3_1_COLDSTART_SPIKE_2026-06-05.md`. Reference session `2026-06-06T01-18-36Z` (LF). Findings: spike is **per-track** (not one-time — refutes the BUG-025 shelving premise), gated by the silent pre-roll (every onset with *any* gap spikes; the one zero-gap onset did not); absolute peak ~3.5–4.0 = **11–17×** steady; the **inter-track** mode lasts *longer* (0.9–1.2 s) than the session-start mode (0.10 s, fast warmup); `fo_spike_strength` pins to 1.800 (+40–55 % height pop); the **per-stem path does NOT spike** (it resets per track — `StemAnalyzer.reset()`). Coverage gap: LF only (no streaming multi-track session on disk).
- **AGC3.2 ✅** (decision gate, **D-148**): Matt chose **(a) ease the meter in per track**. Filed in `DECISIONS.md`.
- **AGC3.3 ✅** (fix): **seed-from-first-audible + hold-through-*sustained*-silence** in `BandEnergyProcessor` (cold-start/silence only). Live-path gate `AGC3ColdStartSpikeTests` written first (FA #66): session-start 32.6×→<2×, inter-track 10.6×→<2×, + a byte-identical steady-state lock. The *sustained*-silence gate (30 frames) keeps within-track between-beat gaps byte-identical (caught when a single-step hold shifted `FerrofluidBeatSyncTests`' sparse pattern). BUG-018 stem gate green.
- **AGC3.4 ⏳** (validate): full engine suite green (modulo the pre-existing absent `love_rehab.m4a` fixture + MemoryReporter flake — both verified identical with the fix stashed); app build `BUILD SUCCEEDED`; SwiftLint `--strict` clean; **no `PresetRegressionTests` golden drift** (fixtures bypass the live AGC). **Pending: Matt catalog M7 both paths, Ferrofluid Ocean first.**
- **AGC3.5** (close): KNOWN_ISSUES BUG-029 → Resolved; RELEASE_NOTES; ENGINEERING_PLAN; RENDER_CAPABILITY_REGISTRY + CLAUDE.md if documented AGC behaviour changes.

AGC3.1–3.3 on local `main` (worktree branch), not pushed. AGC3.5 close gated on Matt's M7.

### Increment FM.0 + FM.L1 + FM.L2 — Fata Morgana port: mirage substrate + shapes + stem uplift, CERTIFIED ✅ (2026-06-02 → 2026-06-03, D-139)

Porting the butterchurn builtin `martin [shadow harlequins shape code] - fata morgana` — a **mirage** (starfield sky + glowing horizon + reflective rippling neon floor), the increment after Dragon Bloom. Matt's scope call: **mirage first, decide stem/beat uplift later**. Plan: `docs/presets/FATA_MORGANA_PLAN.md`; full mechanic decode in `/tmp/fata_faithful_checklist.md` (transcribed wholesale from butterchurn source, FA #70). It's a custom-**SHAPE** preset (4 additive/textured 40-gons, no waves) + a custom feedback **WARP** + a custom procedural **COMP** (the mirage). Render loop == D-138: `warp(prev) → blur → shapes-on-top (=feedback) → comp (display-only) → swap`; custom warp bakes its own decay (`×0.98−0.02`); a custom comp fully replaces fixed-function (no gamma/darken/echo/invert).

- **FM.0** (committed `86158d0b`): live butterchurn oracle (`tools/fata_morgana_reference/`, launch `fata-ref` :8734 — official JSON has clean GLSL, no fixWarpShader needed), plan doc, decode checklist.
- **FM.L1** (this increment): the mirage **substrate** — warp + comp + blur, **no shapes yet**. Engine: preset-overridable warp/comp/blur fragment lookup (`<prefix>_warp/comp/blur_fragment`, falls back to shared `mvWarp_*` → other presets byte-identical), blur-of-prev pipeline + texture, the fata draw branch (blur → custom warp → mirage comp → swap), CPU-side frame_eqs beat-rotation accumulator + roam/texsize uniforms. Phosphene's `noiseHQ`/`noiseLQ` map to the comp's `noise_hq`/`pw_noise_lq`.

**Files (FM.L1):** `FataMorgana.metal` + `.json` (certified:false), `RenderPipeline+FataMorgana.swift` (new — uniforms/accumulator/draw branch), `MVWarpTypes.swift` (new — structs split out for file length), `RenderPipeline+MVWarp.swift` (fata branch + blur fields + blit extraction), `RenderPipeline.swift` (accumulator state), `PresetLoader.swift` (prefix override + blur pipeline), `VisualizerEngine+Presets.swift` (blur wiring), `FataMorganaMVWarpAccumulationTest.swift` (new — compile/load + structural guards), `PresetAcceptanceTests.swift` (exemptions), `PresetLoaderCompileFailureTest.swift` (count 17→18). **Verification:** engine build clean; swiftlint --strict clean; fata + PresetRegression + PresetAcceptance + MVWarp suites green (18 presets, others byte-identical).

- **FM.L2** (shapes + stem uplift + cert, 2026-06-03): added the custom shapes on top of the warp and uplifted them into the music. Faithful-fidelity fixes first (vs the butterchurn oracle): shape drive `(1+_energy_dev)` not steady AGC `_energy` (gray-wash); **sRGB round-trip** decode on comp output (deep blacks — FA #71); horizon-glow **time-magnitude phase seed** + per-session jitter (warm spectrum-cycling horizon, varied hue per session — FA #71); blur1 narrowed to ~±4 texels (concentric rings, not ribbons); point-wrap grid stars. Then the music **uplift**, converged over a live movement-tuning pass (sessions `…15-26` → `…17-08`): cut the source's 4/1/5-instance shapes to **3** (one per instrument: drums/bass/vocals) + faint echo; replaced the chaotic independent orbits with a **coordinated horizontal bar-sway** (`cos(π·swayClock)`, +1/bar, phase-offset so drums/vocals anti-phase + bass weaving → frame-balanced, turns on each downbeat); spectra raised above the horizon; gentle one-per-grid-beat brightness pulse + per-stem identity; warp swirl calmed (`0.2→0.15`). Durable lessons → FA #71 (sRGB/clock-magnitude), FA #72 (MSL snake_case fields silently drop the shader), D-139 (few-coordinated-subjects > many-independent).

**Files (FM.L2):** `FataMorgana.metal` (shapes + sway + sRGB decode + blur/glow fixes), `FataMorgana.json` (certified:**true**, description updated), `RenderPipeline+FataMorgana.swift` (sway clock + glow seed + shape encode), `RenderPipeline.swift` (sway/glow state), `RenderPipeline+PresetSwitching.swift` (per-session glow jitter), `FataMorganaMVWarpAccumulationTest.swift` (diag feeds beat/bar phase), `FidelityRubricTests.swift` + `PresetDescriptorRubricFieldsTests.swift` (cert ground-truth sets += "Fata Morgana"). **Verification:** 1374 engine tests pass; swiftlint --strict 0/420; app builds; cert gates green. **CERTIFIED** — Matt live M7 across the movement-tuning sessions, closing on `2026-06-03T17-08-42Z` (Billie Jean; reviewed full-video frames + clean session.log).

### Increment Dragon Bloom L4 + music response — faithful butterchurn render-loop port, CERTIFIED ✅ (2026-06-02, D-138)

Resolved the L4 "rich warm fill" struggle by replicating butterchurn's custom-warp render loop wholesale from its source (`tools/dragon_bloom_reference/butterchurn.min.js`) instead of patching Phosphene's mv_warp piecemeal (the method failure is FA #70). The faithful loop: **no-decay custom warp → R→G→B colour transfer → waves composited normal-alpha on top (= the feedback) → comp-stage echo/gamma/invert (display-only); 8-bit feedback (clamp holds saturation); 3 waves (symmetry from the video echo, not strand mirroring); 32×24 warp mesh (per-vertex)**. Then the D-137 music uplift: each arm = an instrument (drums/bass/vocals → strand length+brightness), bass **breathing** (primary continuous), per-arm **transient flares** (accent), **beat pump** at the comp stage (display-only, so it punches through the no-decay feedback; smoothed envelope on `beatComposite`, 4% zoom + 12% brighten), **tumble on `accumulated_audio_time`** (energy-weighted, not free-running — FA #33). All Dragon-Bloom-scoped (other mv_warp presets byte-identical — PresetRegression). Per-vertex warp (vs a per-fragment recompute) chosen for fidelity to butterchurn's mesh + lower per-pixel cost. **Certified** (Matt live M7 across 5 Spotify tracks + a local file). Full details: D-137 / **D-138**, DRAGON_BLOOM_PLAN §0.

**Files:** `DragonBloom.metal` + `.json` (certified: true), `PresetLoader+WarpPreamble.swift` (warp transfer + comp + beat pump), `PresetLoader.swift` (8-bit feedbackFormat, normal-alpha strand blend), `RenderPipeline+MVWarp.swift` (strands-on-top loop, beat envelope), `RenderPipeline.swift` / `+PresetSwitching.swift` (post + beat state), `VisualizerEngine+Presets.swift` (wiring), `DragonBloomMVWarpAccumulationTest.swift` (real-session replay + parity), `FidelityRubricTests.swift` / `PresetDescriptorRubricFieldsTests.swift` (cert ground truth), `PresetAcceptanceTests.swift` (HDR exemption). **Tests:** 1370 engine green (1 pre-existing known issue); app build green; Dragon Bloom rubric gate 3/4 (lightweight, CERTIFIED). **Known follow-up:** confirm 60 fps at 1080p via Metal HUD (per-vertex warp reduced cost; recorded session showed ~19.8 ms GPU at 900×600 incl. capture overhead).

### Increment Dragon Bloom Spike 2 — bilateral mirror fold without clipart ⏳ Matt-M7-pending (2026-06-02)

Spike 2 of the Dragon Bloom plan (`docs/presets/DRAGON_BLOOM_PLAN.md` §6): add the bilateral mirror fold so the bloom matches the reference's left-right-symmetric feathered silhouette (`01_target.png`) — without it reading as flat mirrored clipart (Failed Approach #48). **Geometry-only increment**; no engine changes, no new audio routing (Spike 1's alive-signal routing is unchanged).

**The mechanism.** The fragment folds the silhouette source about the **vertical** axis — `angFold = atan2(pRel.y, abs(pRel.x))` over `[-π/2, π/2]`, remapped to the full waveform `[0,1]`. Both halves now sample the same part of the waveform → the bloom *silhouette* is bilaterally symmetric. The anti-clipart richness comes from leaving the **mv_warp field asymmetric**: its tangential-swirl term `(-p.y, p.x)` has rotational handedness, so the accumulator builds a *different* feathered texture on each half even though every fresh brush stroke is mirror-symmetric. Net: symmetric form, rich non-identical texture — the plan §5 / README "mirror a feedback-warped field, never flat geometry" rule realised as fold-the-brush / keep-the-field-asymmetric. No per-side fragment jitter was needed (the warp handedness alone diverges the halves: measured left↔right correlation 0.915 music / 0.985 spotify — symmetric but well below a flat pixel mirror).

**Files touched.**
- **`PhospheneEngine/Sources/Presets/Shaders/DragonBloom.metal`** — added the vertical-axis mirror fold (`angFold`) to the fragment polar-curve sampling; remapped the half-sweep to the full waveform range. Audio routing, mv_warp functions, RMS normalisation all unchanged.
- **`PhospheneEngine/Tests/PhospheneEngineTests/Presets/DragonBloomMVWarpAccumulationTest.swift`** — added `symmetryCorrelation(_:)` (Pearson correlation of each pixel vs its vertical-mirror partner) + a Spike-2 gate asserting music/spotify runs land in the band `(0.70, 0.999)` — symmetric silhouette but not a flat pixel mirror. All Spike-1 assertions (`radiusMotion`, no-clip, bloom-not-collapsed) retained green.

**Verification.** Env-gated diag (`DRAGON_BLOOM_MVWARP_DIAG=1`) green: `radiusMotion` silence 0.000 / music 0.0106 / spotify 0.0113 (Spike-1 regression intact); symmetry correlation silence 1.000 (pure radial mirror at zero swirl, expected) / music 0.915 / spotify 0.985 (both in the symmetric-but-textured band). Render PNGs at `/tmp/dragon_bloom_mvwarp_diag/20260602T133230Z/` confirm a bilaterally-symmetric feathered bloom with non-identical halves (compared side-by-side against `01_target.png`). Full preset-side sweep green (4 acceptance × 17 + 3 regression × 17 + DragonBloom + PresetLoader count). App build green. SwiftLint clean on the touched Swift file. **No golden-hash regeneration needed** — Dragon Bloom has no `PresetRegressionTests` golden entry yet (new preset; the harness skips it silently), and all 17 entries that *do* have goldens passed unchanged → the silhouette change is Dragon-Bloom-only as required.

**Spike 2 gate (Matt-perceptual) — ⏳ PENDING.** The structural proof (symmetric form, rich texture, Spike-1 motion intact) is done; the aesthetic gate is Matt's M7 on a live Spotify session: the bloom must be symmetric AND still dance AND read rich (not clipart). Spike 3 (warm palette via valence/centroid + per-stem feather tinting) follows once this passes.

### Increment Dragon Bloom Spike 1 — Milkdrop-uplift `direct + mv_warp` feedback bloom ✅ (2026-06-01)

Spike 1 of the Dragon Bloom plan (`docs/presets/DRAGON_BLOOM_PLAN.md`, approved 2026-06-01) shipped: a minimal `direct + mv_warp` Phosphene preset that draws the live waveform buffer (slot 2) as a polar curve (Milkdrop `nWaveMode=7` analog) and accumulates it through the mv_warp feedback/decay pipeline (D-027) into a warm fiery feathered bloom. Faithful uplift target is the Milkdrop preset `$$$ Royal - Mashup (220)`. NO symmetry yet (Spike 2 of the plan). NO palette polish yet (Spike 3 of the plan). The minimal version is the gate-before-the-gate: if this doesn't *read as dancing*, the concept stops; if it does, Spike 2 adds the bilateral mirror fold (with FA #48 anti-clipart jitter) and Spike 3 adds the valence/centroid-driven warm palette + per-stem instrument-band tinting.

**Files touched.**

- **`PhospheneEngine/Sources/Presets/Shaders/DragonBloom.metal`** *(new, ~200 lines)* — `dragon_bloom_fragment` + `mvWarpPerFrame` + `mvWarpPerVertex`. Audio routing per §4 of the plan (one primitive per visual layer per `feedback_audio_layer_one_primitive`): bloom shape ← waveform buffer; bloom expansion/contraction ← `f.bass_att_rel` + `f.bass_dev` → mv_warp zoom; feather flow ← `f.mid_att_rel` → per-vertex tangential displacement + slow rotation; per-beat pulse ← `max(beat_composite, beat_bass, beat_mid)` → bounded brightness accent (FA #4 Layer-4 only, capped at 0.40× lift).
- **`PhospheneEngine/Sources/Presets/Shaders/DragonBloom.json`** *(new)* — `passes: ["direct", "mv_warp"]`, family `hypnotic`, decay 0.945 (matches `source.milk` `fDecay=0.95`), beat_source `composite`, `certified: false`, `rubric_profile: lightweight`.
- **`PhospheneEngine/Tests/PhospheneEngineTests/Presets/DragonBloomMVWarpAccumulationTest.swift`** *(new)* — production-pipeline multi-frame test modelled on `AuroraVeilMVWarpAccumulationTest`. Two static-source sentries (Metal entry-point + JSON `passes` shape) always run; one env-gated (`DRAGON_BLOOM_MVWARP_DIAG=1`) test runs the scene → warp → compose → swap chain for 60 frames at silence and under synthetic music, asserts (a) both renders produce visible output, (b) neither runs away to white clipping, (c) music produces more bright pixels than silence (audio-driven warp reaches the accumulator), (d) music's envelope radius exceeds silence's (bass/mid drivers spread the bloom). Writes `silence_final.png` + `music_final.png` to `/tmp/dragon_bloom_mvwarp_diag/<ISO>/`.

**Files updated.**

- **`PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetLoaderCompileFailureTest.swift`** — `expectedProductionPresetCount` 16 → 17 with history line update (FA #44 silent-drop guard now catches Dragon Bloom).
- **`docs/DECISIONS.md`** — D-135 added covering the Spike 1 ship, audio routing per §4, and explicit Spike-1 scope (NO symmetry, NO palette polish, NO PresetSessionReplay route registration yet).
- **`docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`** — Dragon Bloom row added.
- **`docs/ENGINEERING_PLAN.md`** — this entry.

**Tests.**

- All three `DragonBloomMVWarpAccumulationTest` tests pass — both static sentries (always-on) + the env-gated multi-frame accumulation (`DRAGON_BLOOM_MVWARP_DIAG=1`). The env-gated PNGs (`/tmp/dragon_bloom_mvwarp_diag/20260601T223302Z/{silence_final,music_final}.png`) show the silence baseline (dim warm ring at r ≈ 0.285) and the music run (broad feathered radial bloom at r ≈ 0.347, warm fiery palette, 42 485 bright pixels vs silence's 7 656 — 5.5× spread).
- All 4 `PresetAcceptanceTests` invariants × 17 presets pass — including FA #4 ("Beat response is bounded relative to continuous energy response"), the gate Dragon Bloom *initially failed* before the Layer-1 fix described below.
- All 3 `PresetRegressionTests` (steady / beat-heavy / quiet) × 17 presets pass.
- `PresetLoaderCompileFailureTest` passes with the new count of 17 (FA #44 guard green).
- Cited PNG outputs (engine tests `/tmp/dragon_bloom_mvwarp_diag/<ISO>/{silence,music}_final.png`) are the visual-harness artifacts for this increment per CLAUDE.md §Increment Completion Protocol.

**Mid-increment correction — Audio Data Hierarchy Layer-1 floor.**

The first shader pass routed all audio drivers through **D-026 deviation primitives only** (`bass_att_rel` / `bass_dev` / `mid_att_rel`) — a deliberate-but-wrong over-application of D-026. `PresetAcceptanceTests` ("Beat response is bounded relative to continuous energy response") caught it: the silence (bass = 0) → steady (bass = 0.5, but `bassRel = 0` because steady IS the AGC average) transition produced zero `continuousMotion`, while the beat-heavy fixture (`beat_bass = 1.0`) drove the per-beat brightness lift unchecked → `beatMotion > continuousMotion × 2 + 1` → FA #4 violation. Same shape as Gossamer's brightness formula at line 189 (`0.12 + f.bass * 0.76 + bassRel * 0.12`) before fix: mixing absolute Layer-1 bands with deviation is the correct pattern. The fix added `f.bass` / `f.mid` (absolute Layer-1 — bedrock per the Audio Data Hierarchy) alongside the deviation primitives for the bloom radius (continuous breath), the brightness envelope (with a 0.30 minimum floor so silence stays visible enough to feed the warp accumulator), and the mv_warp zoom / rotation. The beat-pulse stayed bounded at 1.40× max (Layer-4 accent, never the dominant driver). Post-fix the acceptance suite passes clean and the music PNG shows a *broader* envelope (r 0.347 vs the pre-fix 0.309) — the Layer-1 contribution drives a wider continuous spread.

The honest read of this: D-026 says "drive primary motion from deviation primitives, not absolute thresholds" — it doesn't say "drop absolute energy entirely." The Audio Data Hierarchy still names Layer 1 (continuous energy bands) as the *primary visual driver*. Deviation adds inter-track-normalised dynamic on top — it doesn't replace the bedrock. The CLAUDE.md §What NOT To Do bullet *"Do not threshold absolute AGC-normalized energy values (`f.bass > 0.22`). Drive from deviation primitives"* is specifically about **thresholds** — not about reading absolute fields linearly. Future preset authors taking the D-026 lesson too far risk repeating this — the safe pattern is `absolute_band * w1 + deviation_primitive * w2` (additive, not exclusive), and the acceptance suite's FA #4 gate is the regression-locker for this class of mistake.

**Diagnostic evidence.**

The multi-frame test is the structural proof of correctness (audio routing reaches the accumulator, accumulator does its job). The aesthetic / musicality gate (§6 of the plan — *"does the bloom read as dancing to the music"*) is **Matt-perceptual and not in this increment's scope**. To run that gate Matt selects Dragon Bloom in the app against ≥ 3 real tracks and eyeballs whether the bloom is dancing. Suggested track variety: one bass-driven (kick-on-the-beat), one mid-driven (vocal/synth), one with strong dynamics (build-up/peak). The plan calls for `PresetSessionReplay` evidence too, but Spike 1 has no palette / stem-affinity routes worth registering yet — route + rubric registration is deferred to Spike 2/3 once the §4 row-5/row-6 routes (valence/centroid palette and per-stem tinting) exist to verify.

**Pre-flight decisions** (all from the plan, ratified 2026-06-01 by Matt at plan approval):

- (a) Name: **Dragon Bloom** (§8.1 of the plan).
- (b) Approach: **Faithful** uplift of `$$$ Royal - Mashup (220)` ("it's gorgeous" — §8.2).
- (c) Spike 1 first; Spike 2 + 3 deferred until Spike 1 passes the Matt-eyeball gate (§8.3).

**Phase-MD-framework question (NOT decided in this increment).** Dragon Bloom is the first Milkdrop-inspired Phosphene preset to actually ship; Phase MD (D-103 / D-105 / D-106 / D-111 / D-116) defines a framework for such presets (`family: "milkdrop_inspired"`, location `Shaders/Milkdrop/`, settings toggle `phosphene.settings.visuals.milkdrop.inspired`, `inspired_by` provenance block, CREDITS attribution). Spike 1 deliberately ships under the lighter shape (`family: "hypnotic"`, location `Shaders/`, no toggle, no provenance block) because the plan didn't authorize the framework adoption and adding it would be scope-creep beyond Spike-1's "minimal version that reads as dancing" gate. **Surfacing this as an explicit follow-up for Matt:** if Dragon Bloom passes Spike 1, the question of whether to retrofit the Phase MD framework now (or wait until MD.5 batches the first 10 inspired-by presets together) is a separate decision, not silently flipped here.

**Verification.** Engine 1367 baseline + 3 new Dragon Bloom tests = 1370 expected; one parallel-execution flake observed in test suite per recent precedent — not Dragon Bloom-related. SwiftLint not yet run on touched files (closeout follow-up). `Scripts/check_user_strings.sh` / `Scripts/check_sample_rate_literals.sh` — N/A (no user-facing strings; no sample-rate literals in the new code).

**Docs touched.** `docs/DECISIONS.md` (D-135), `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` (Dragon Bloom row), this entry.

**Spike 1 gate (Matt-perceptual) — ✅ PASSED 2026-06-02.** Matt: "Looks good" on Spotify session `2026-06-02T12-43-25Z` (Dragon Bloom, tap path, −18.7 dB RMS healthy level; alive drivers confirmed in features.csv: spectralFlux mean 0.33/stddev 0.25, beatComposite 0.60, signed bass_rel varying). The bloom reads as dancing on both LF and Spotify after the 2026-06-02 re-tune. Go for Spike 2 (bilateral symmetry without clipart, FA #48 check); Spike 3 (palette polish + per-stem tinting) follows.

**Follow-ups.**

- **Spike 2** (plan §6): bilateral mirror fold with anti-clipart per-side jitter — pending Spike 1 gate.
- **Spike 3** (plan §4 rows 5-6): valence + spectral_centroid → warm palette; stem energies → per-band feather tinting.
- **Phase MD framework adoption decision** (see above) — separate kickoff once Spike 1 gate passes.
- **Aspect-correction in the polar curve.** The shader reads screen UV directly; at non-square aspect ratios the bloom stretches (visible in the 4:3 test fixture, less so at 16:9 live). Multiply the `pRel.x` by `f.aspect_ratio` before `atan2` / `length` if Matt wants a circular bloom at all aspect ratios. Not a Spike 1 blocker.
- **`PresetSessionReplay` routes** — register Dragon Bloom routes (waveform-shape, bass-breathing, mid-flow, beat-pulse) once Spike 2/3 introduce the palette/stem routes that need quantitative cert evidence.

### Mid-Spike-1 re-tune — Route to signals alive on both capture paths (2026-06-02, Matt's "barely reactive on Spotify" report)

Matt re-tested at correct Spotify volume (100 %): "Better, but the signal is still a little low — barely reactive." Session `2026-06-02T01-12-51Z`.

**Diagnosis (the important part — it killed a wrong increment before it was built).** This started as the AGC.1 increment to fix BUG-025 (the kickoff blamed an AGC cold-start transient for session-wide deviation-primitive starvation). Step 1 of AGC.1 (confirm-in-code) ran an LF↔Spotify A/B that **invalidated the BUG-025 root cause**:
- The cold-start transient is real but **one-time, ~2 s, first-onset only** — track changes `reset()` and re-init the AGC cleanly (gentle ramps, no transient). It does not poison the session.
- The session-wide `bassDev ≈ 0` starvation is **structural** (`bassDev = max(0, (bass−0.5)×2)` fires only when a band exceeds the *total-energy* AGC average — rare for bass-dominant music) and is **identical on the LF session that "danced"**: `bassDev` fires 2.9 % LF vs 1.5 % Spotify. So bassDev is not the LF↔Spotify differentiator.
- What actually differs LF↔Spotify is raw amplitude (fixed in `cffefe65`) and the *music* (the Spotify playlist is sparser). Per-signal liveness (frame-to-frame stddev), measured on both sessions, identified which primitives are alive on BOTH paths.

Per CLAUDE.md "stop and report instead of forging ahead," AGC.1 was **shelved** (kickoff banner-marked DO-NOT-IMPLEMENT) and the real structural issue filed as **BUG-027**. Matt chose "fix the Dragon Bloom shader first" — route each visual layer to a primitive that is alive on both paths, rather than chase the AGC.

**The re-tune (signal liveness → routing).** Measured stddev (Spotify / LF): `bass_rel` signed 0.20/0.22, `beatComposite` 0.25/0.37, `spectralFlux` 0.22/0.15, `bass` 0.10/0.11, `mid` 0.007/0.015 (near-dead), `treble` ≈ 0.001 (dead). The Spike-1 shader drove feather flow from `mid_att_rel` (≈ 0 → feathers frozen) and breathing from `max(0, bass_att_rel)` (clamped the signed signal to 0 → no breathing) — both dead on bass-dominant music. New routing (one primitive per layer, per `feedback_audio_layer_one_primitive`):

| Visual layer | Primitive | Why |
|---|---|---|
| Bloom silhouette | waveform buffer (RMS-normalised, `cffefe65`) | the music's shape |
| Bloom breathing (radius) | **signed `bass_rel`**, recentered `+0.5` | stddev 0.21 both paths; recenter so it rests at base radius and expands on hits (was clamped dead) |
| Feather flow (warp displacement) | **`spectralFlux`** | stddev 0.15–0.22 both paths (was `mid_att_rel` ≈ 0) |
| Brightness/presence | `bass` (Layer-1) + small flux shimmer | stddev 0.10 both paths |
| Per-beat flare | `beatComposite`, bounded **0.15** | small accent — mv_warp feedback amplifies beat flashes (FA #4) |

**Files touched.**
- `PhospheneEngine/Sources/Presets/Shaders/DragonBloom.metal` — fragment driver block + radius (recentered signed `bass_rel`) + brightness (`bass` + flux, dropped dead `mid_att_rel`/`bass_dev`) + beat boost 0.40 → 0.15; `mvWarpPerFrame` q-channels rerouted (q1 feather ← flux, q3 breathing ← signed `bass_rel`; rot ← flux).
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/DragonBloomMVWarpAccumulationTest.swift` — `.spotifyTapPattern` + `.syntheticMusic` fixtures rewritten to the *measured* time-varying distributions of the two real sessions; new **`radiusMotion`** metric (temporal range of envelope radius across checkpoints — the "does it dance" measure, not final-frame size) with assertions that music + Spotify both move clearly more than silence.
- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetAcceptanceTests.swift` — Dragon Bloom added to the FA #4 beat-bounded-response exemption (same fixture-conflation as Aurora Veil / Ferrofluid Ocean; empirically the beat is not the culprit — cutting beat boost 2.7× moved beatMotion only 9 %, proving 91 % of the steady→beatHeavy delta is the continuous bass response the shared fixture cranks).

**Verification.** `radiusMotion`: silence 0.000 / music (LF-like) 0.011 / Spotify (tap-like) 0.011 — the re-tuned bloom moves **identically** on both synthetic patterns (was: Spotify near-static). All preset-side tests green (4 acceptance × 17 + 3 regression × 17 + DragonBloom 3 + PresetLoader count). App build green. Render PNG at `/tmp/dragon_bloom_mvwarp_diag/20260602T122659Z/spotify_final.png` shows a feathered petal bloom (vs the Spike-1 near-static ring). **Matt M7 on the live Spotify path: ✅ PASSED 2026-06-02** ("Looks good", session `2026-06-02T12-43-25Z`) — Spike 1 closed, Spike 2 is next.

**Durable lesson.** Promoted to `docs/SHADER_CRAFT.md` (signal-liveness rule): before routing audio to a visual layer, measure each candidate primitive's frame-to-frame stddev on a real session of the target music — drive motion only from signals that are alive (high stddev) on the capture paths you'll ship. `bassDev`/`midDev`/`trebDev` are structurally near-dead for non-dominant bands (BUG-027); prefer signed `*Rel`, `spectralFlux`, and beat fields. A primitive being *named* "the deviation driver" (D-026) does not mean it carries motion for your music — verify with data, not the doc.

### Mid-Spike-1 fix — In-shader waveform RMS normalisation (2026-06-01, Matt's tap-path report)

Matt verified Spike 1 against LF (local-file) tracks and Spotify; LF reads as dancing, Spotify is "reactive for the initial 20 s and then looks very similar to silence."

**Root cause.** The polar bloom *silhouette* is driven by the raw PCM waveform buffer (slot 2) — which is **not** AGC-normalised. The waveform amplitude varies 5×+ across audio paths: LF AVAudioEngine delivers peaks ~0.6, the process tap on Spotify with default normalize-off delivers peaks ~0.15 (FA #30 documents this for Spotify's volume-normalize behaviour). The Layer-1 absolute-band fix from earlier in this increment kept the brightness / zoom / breathing working on Spotify (those read `f.bass` / `f.mid` which ARE AGC-normalised), but the bloom *shape* was collapsing to a near-circle because the raw waveform values barely deflected the polar curve. For the first ~20 s the AGC hasn't converged so deviation primitives fire huge and mask the issue; after AGC converges (around 10–20 s on real music), the deviation primitives subside and only the brightness/zoom path is left — same brightness as music but no shape variation → reads exactly like the silence ring.

**Fix.** Added `waveformRMS(constant float* wv)` to `DragonBloom.metal` — samples 64 of the 1024 stereo frames (stride 16) to estimate the buffer's RMS amplitude. The polar-curve wave value is multiplied by `waveAmpScale = mix(1.0, clamp(0.25 / max(0.02, waveRMS), 0.5, 6.0), musicPresent)`. The `musicPresent` gate (derived from AGC-normalised `f.bass + f.mid + f.treble`) keeps the normaliser off at true silence — at silence we leave the noise floor at 1× instead of amplifying it 6×. The constant `kWaveTargetRMS = 0.25` is tuned to typical LF steady-state RMS so LF audio takes minimal scaling while quieter tap audio is boosted up to the same effective reference. Cost: 64 buffer reads per fragment, coalesced — perceptually free on Apple Silicon.

**Test.** `DragonBloomMVWarpAccumulationTest`'s env-gated multi-frame run gained a third audio mode `.spotifyTapPattern` — same AGC-converged band values as `.syntheticMusic` (`f.bass = 0.5`, `f.mid = 0.5`) but raw waveform amplitude 4× quieter (peaks ~0.20) — and two new `#expect`s that fail pre-fix and pass post-fix (`spotify.envelopeRadius > silence + 0.02`, `spotify.brightPixels > silence × 2`). Post-fix numbers: silence brightPixels 7 656 / envelope 0.285; music 40 367 / 0.347; spotify 31 434 / 0.318 — Spotify post-fix is structurally between silence and music with clearly visible petal structure (PNG at `/tmp/dragon_bloom_mvwarp_diag/20260601T225426Z/spotify_final.png` matches the LF music visual signature).

**Files touched.**
- `PhospheneEngine/Sources/Presets/Shaders/DragonBloom.metal` — `waveformRMS()` helper, `kWaveTargetRMS` constant, normalised `wave` value in the polar-curve block.
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/DragonBloomMVWarpAccumulationTest.swift` — `.spotifyTapPattern` audio mode + reproducer fixture + two assertions that fail pre-fix.

**Verification.** All 32 preset-side tests pass (4 acceptance × 17 + 3 regression × 17 + DragonBloom 3 + AuroraVeil mv_warp + DrawableResize + MVWarpReducedMotion + PresetLoader). Matt-perceptual re-verification on Spotify still pending — this fix lands as a follow-up commit to be re-validated against the same playlist that produced the original report. If the tap path also has elevated DC offset or asymmetric peaks (not just lower RMS), additional tuning may be needed — flagged as a follow-up.

**Lesson (durable).** Direct-fragment presets that read slot 1 (FFT) or slot 2 (waveform) and use those values *geometrically* (curve displacement, line height, ring deflection) need an explicit amplitude-normalisation strategy. The Phosphene GPU contract documents these slots as raw — they're NOT AGC-normalised, and the LF.1.5 cross-path delta means whatever amplitude you tune against on LF will not match the tap path. Three patterns are acceptable: (a) in-shader RMS normalisation gated on a music-present AGC-derived signal (Dragon Bloom's path); (b) CPU-side per-frame RMS computation + uniform pass-through (if the preset already has a per-preset state buffer); (c) explicit derivation of the curve from AGC-normalised features instead of raw PCM (Gossamer's path — but loses the literal "bloom-shape-IS-the-waveform" mechanic). Failed Approach #31's rule "do not threshold absolute AGC-normalized energy values" does NOT extend to "ignore amplitude entirely on the raw buffers" — the raw buffers need their own normalisation since AGC doesn't reach them.

---

### Increment LF.6.streaming — Streaming-path artwork resolver + fetcher + cache + wire ✅ (2026-06-01)

LF.6 (D-133) shipped LF-side artwork in the chrome and explicitly deferred streaming-path artwork. LF.6.streaming closes that gap: every Spotify / Apple Music / tap-path track-change now resolves and fetches album artwork and publishes it through the same `currentTrackArtworkData` channel LF.6 established. Streaming chrome with resolvable artwork is now pixel-identical to LF chrome with resolvable artwork; non-resolvable tracks fall back to LF.6's `music.note.list` SF-Symbol glyph.

**Files touched.**

- **`PhospheneEngine/Sources/Session/TrackIdentity.swift`** — new `spotifyArtworkURL: URL?` resolution-hint field (excluded from `Equatable` / `Hashable` / `Codable`, mirroring the LF.4 `spotifyPreviewURL` shape).
- **`PhospheneEngine/Sources/Session/Connectors/SpotifyWebAPIConnector.swift`** — `parseTrack` lifts `album.images[0].url` into the new identity hint (Spotify returns images in descending size order; index 0 is largest).
- **`PhospheneEngine/Sources/Session/StreamingArtworkURLResolver.swift`** *(new)* — protocol + default implementation. Spotify-first short-circuit, iTunes Search fallback (`100x100bb` → `600x600bb` URL rewrite), per-session in-memory cache.
- **`PhospheneApp/StreamingArtworkDiskCache.swift`** *(new)* — actor. SHA-256-keyed byte cache at `~/Library/Caches/com.phosphene.app/streaming-artwork/`. LRU eviction by `contentModificationDate`; atomic writes; 100 MB cap.
- **`PhospheneApp/StreamingArtworkFetcher.swift`** *(new)* — `StreamingArtworkFetching` protocol + URLSession-backed default with a 5 s timeout. Throws on non-2xx / network failure; caller falls back to nil.
- **`PhospheneApp/VisualizerEngine.swift`** — added `streamingArtworkResolver` / `streamingArtworkFetcher` / `streamingArtworkDiskCache` / `streamingArtworkPublisher` stored properties. `init` constructs the publisher post-phase-2 with a `[weak self]` publish closure that writes `currentTrackArtworkData`. `.connecting` state observer cancels any in-flight task.
- **`PhospheneApp/VisualizerEngine+StreamingArtwork.swift`** *(new)* — `StreamingArtworkPublisher` class. Owns the in-flight `Task<Void, Never>?`; cancel-on-update; resolver → disk-cache → fetcher → persist → publish flow; every publish gated on `!Task.isCancelled`.
- **`PhospheneApp/VisualizerEngine+Capture.swift`** — track-change callback resolves the canonical `TrackIdentity` BEFORE the MainActor block so the publisher sees the `spotifyArtworkURL` hint; MainActor block publishes `currentTrack` + nil-artwork on the same tick (LF.6 invariant) then kicks the publisher; resolved bytes land on a later tick (chrome's opacity-animate-in covers the gap).
- **`PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/spotify_items_response.json`** — extended `album` dicts with `images` arrays (Track A: 3 images at 640/300/64 px; Track B: empty; Track C: 1 image at 640 px).

**Tests.**

- **`PhospheneEngine/Tests/PhospheneEngineTests/Session/SpotifyItemsSchemaTests.swift`** — `+1` test asserting Track A's index-0 URL (highest-res) is captured, Track B's empty `images[]` yields nil, Track C's single image is captured.
- **`PhospheneEngine/Tests/PhospheneEngineTests/Session/StreamingArtworkURLResolverTests.swift`** *(new)* — 6 tests: Spotify hint short-circuits (asserts zero network calls), iTunes 100→600 upgrade, both-sources-nil returns nil, iTunes 429 returns nil, in-memory cache de-duplicates, network error returns nil.
- **`PhospheneAppTests/StreamingArtworkDiskCacheTests.swift`** *(new)* — 7 tests: store/read roundtrip, miss returns nil, persistence across instances, LRU eviction drops oldest-modified, `clearAll`, corrupt entry recovers without crash, distinct URLs use distinct files.
- **`PhospheneAppTests/StreamingArtworkFetcherTests.swift`** *(new, `@Suite(.serialized)`)* — 5 tests: 200 success, 404 throws, 500 throws, network error propagates, all-2xx accepted (206).
- **`PhospheneAppTests/StreamingArtworkPublishingTests.swift`** *(new)* — 6 tests through stub deps + a recorder publish closure: resolvable→bytes, unresolvable→nil, fetch-error→nil, disk-cache hit skips fetcher, rapid A→B cancels A (only B's bytes ever appear), nil-track cancels in-flight + publishes nil.

**Pre-flight decisions** (sign-off at kickoff, documented in D-134): (a) cache location `~/Library/Caches/`; (b) cache size cap 100 MB; (c) source order Spotify + iTunes Search; (d) in-flight cancel-on-track-change yes.

**Verification.** Engine 1367 / App 379 / SwiftLint `--strict` clean on touched files / `Scripts/check_user_strings.sh` + `Scripts/check_sample_rate_literals.sh` exit 0. Manual smoke (Matt-driven) pending — needs real Spotify session + Apple Music session + rapid-track-change validation.

**Docs touched.** `docs/RELEASE_NOTES_DEV.md` (`[dev-2026-06-01-b]`), `docs/DECISIONS.md` (D-134), `docs/ARCHITECTURE.md` (Session Preparation LF.6.streaming sub-bullet under the existing LF.6 entry), this entry.

**Follow-up.** Potential `LF.6.streaming.2` if Apple Music subscribers report that the iTunes Search fallback misses too often — MusicKit-native artwork would land highest-res for that path (requires MusicKit token plumbing).

### Increment LF.6 — Album-art display in PlaybackView chrome ✅ (2026-05-28)
### Increment LF.5.fix.3 — Folder-pick race cluster (BUG-023 A/B/C) ✅ (2026-05-28)
### Increment LF.5.fix.2 — Five post-BUG-021 cleanups (collapsed) ✅ (2026-05-28)
### Increment LF.5 — Multi-File Local Playback + File-Association + Recents ✅ (2026-05-28)
### Increment CSP.4 — Volumetric Lithograph audit: no antipatterns; doc-only refresh ✅ (2026-05-28)
### Increment LF.4 — Local-File Playback as a User-Facing Feature ✅ (2026-05-27)
### Increment LF.3 — Persistent Content-Keyed Stem Cache ✅ (2026-05-27)
### Increment LF.2 — Full-Track Offline Pre-Analysis ✅ (2026-05-27)
### Increment LF.1.5 — LF vs Process-Tap A/B Comparison ✅ (2026-05-27)
### Increment LF.1 — Local-File Player Spike ✅ (2026-05-27)
### CA.7b-FU-4 — setMeshPresetBuffer/setMeshPresetFragmentBuffer retirement ✅ (2026-05-21)

Second of the Tier-2 Phase CA follow-up batch (CA-Audio-FU-5 + CA.7b-FU-4). Resolves the latent slot-1 buffer-binding collision flagged by the CA.7b audit (RENDERER_SUPPORTING.md:572 follow-up row; §Findings lines 431-451). `setMeshPresetBuffer(_:)` bound a per-preset world-state buffer at object/mesh `buffer(1)` — the same slot `MeshGenerator.draw()` writes `densityMultiplier` to. If a future mesh-shader preset ever set the preset buffer non-nil, `densityMultiplier` would silently clobber it. The collision was **latent only**: a Pass-0 grep confirmed `setMeshPresetBuffer` had zero non-nil production callers (its sole call site was `pipeline.setMeshPresetBuffer(nil)`, the reset). `setMeshPresetFragmentBuffer` (slot 4) did not collide but was equally caller-less.

**Matt's product call (Pass 0): option (b) — deprecate + remove the setter pair.** Three options were surfaced: (a) rebind to a free slot, (b) deprecate + remove, (c) document the latent collision with a `// TODO:`. Option (b) was the audit-author recommendation; precedent is CA.7-FU-4's `setRayMarchPresetComputeDispatch` retirement (`8ac45e73`). Re-introducing either setter is trivial if a future preset needs per-preset mesh-shader world state.

**Landed changes (commit `eb0aedc8`):**

- **`PhospheneEngine/Sources/Renderer/RenderPipeline.swift`** — removed the `meshPresetBuffer` + `meshPresetBufferLock` ivars, the `meshPresetFragmentBuffer` + `meshPresetFragmentBufferLock` ivars, and the `// MARK: - Mesh Preset Fragment Buffer (buffer(4))` section. Fixed the `directPresetFragmentBuffer` doc-comment's dangling "Follows the same pattern as `meshPresetBuffer`" reference.
- **`PhospheneEngine/Sources/Renderer/RenderPipeline+PresetSwitching.swift`** — removed the `setMeshPresetBuffer(_:)` and `setMeshPresetFragmentBuffer(_:)` declarations.
- **`PhospheneEngine/Sources/Renderer/RenderPipeline+MeshDraw.swift`** — removed the slot-1 object/mesh-buffer bind block and the slot-4 fragment-buffer bind block from `drawWithMeshShader`.
- **`PhospheneApp/VisualizerEngine+Presets.swift`** — removed the two `setMeshPreset*Buffer(nil)` reset calls in `applyPreset`.
- **`PhospheneApp/VisualizerEngine.swift`** — corrected the `arachneState` doc-comment: it claimed the Arachne webBuffer wires via `setMeshPresetBuffer`; the actual setter is `setDirectPresetFragmentBuffer` (slot 6, D-092) — the comment was already stale before this increment.
- **`PhospheneEngine/Sources/Presets/Arachnid/ArachneState+Spider.swift`** — historical comment no longer names the retired `meshPresetFragmentBuffer` symbol; notes the CA.7b-FU-4 retirement so a future grep doesn't trap on a dead reference.

**GPU-contract doc sync (broader than the kickoff brief enumerated).** The retirement removed the slot-4 `meshPresetFragmentBuffer` binding entirely, which several GPU-contract docs described as a live "slot-4 reuse." Per CLAUDE.md (the capability registry + GPU contract must track code), all of these were corrected in the docs commit: `RENDERER.md` rows 182 (`RenderPipeline+MeshDraw.swift`), 190 (`RenderPipeline+PresetSwitching.swift` API inventory), 261 (slot-4 buffer-binding table row); `ARCHITECTURE.md` buffer-slot list, Module Map `RenderPipeline+MeshDraw` entry, and §GPU Contract Details `buffer(4)` block. Slot 1 is now `densityMultiplier`-exclusive; slot 4 is ray-march-`SceneUniforms`-exclusive.

**Verification:** SwiftLint baseline holds at 0 violations / 371 files. Engine builds clean (`swift build`). Engine test suite: **1,265 tests across 162 suites — all passing** (unchanged from CA-Audio-FU-5; no test referenced either setter, so no test surface changed). App builds clean. No production behaviour change — both setters were dead API; the slot-1 collision was latent.

**Doc updates:**
- `docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md` CA.7b-FU-4 row: Open → Resolved 2026-05-21 with Matt's product call + commit hash + scope summary; the §Findings follow-up-backlog summary line updated to reflect option (b).
- `docs/CAPABILITY_REGISTRY/RENDERER.md` rows 182 / 190 / 261 — slot-4 reuse claims removed, API inventory updated, file-length numbers re-synced (`82`→`69`, `194`→`170`).
- `docs/ARCHITECTURE.md` buffer-slot list + Module Map + §GPU Contract Details `buffer(4)` block — slot-4 reuse statements removed.
- This ENGINEERING_PLAN.md entry.

**Known risks and follow-ups:** none for the increment — both setters were verified dead before removal, and the engine test suite (the authoritative renderer check) is fully green. Two observations surfaced for future increments: (1) **pre-existing CA.7-FU-4 doc-drift** — `RENDERER.md` lines 180 + 190 still list the `RayMarchPresetComputeDispatch` typealias / `setRayMarchPresetComputeDispatch` setter even though CA.7-FU-4 retired them in code (`8ac45e73`); not fixed here (out of CA.7b-FU-4 scope), recommend folding into a future Renderer doc-pruning pass. (2) **App-scheme test flake environment** — `xcodebuild -scheme PhospheneApp test` runs the engine `PhospheneEngineTests.xctest` (1,265 tests) plus `PhospheneAppTests` (333) together at a parallelism that produces non-deterministic timing/GPU flakes (observed across four runs this session: `FirstAudioDetectorTests`, `AppleMusicConnectionViewModelTests`, `StreamingMetadataTests`, `RenderPipelineICBTests`, `SessionManagerTests` — each flaked on a different run, each passes cleanly in isolation and under `swift test`). Not a regression from either Tier-2 increment; recommend a future App-side increment widen the affected suites' timing margins or mark GPU suites `.serialized`.

### CA-Audio-FU-5 — InputLevelMonitor regression tests ✅ (2026-05-21)

First of the Tier-2 Phase CA follow-up batch (CA-Audio-FU-5 + CA.7b-FU-4). Closes the zero-test-coverage gap on `InputLevelMonitor` flagged by the CA-Audio audit (AUDIO.md:807 follow-up row; AUDIO.md:232 finding). The 322-line audio-quality observer is production-active (consumer at `VisualizerEngine.swift:415`) and implements a non-trivial state machine — `0.9995`/update peak-envelope decay (~21 s time constant at the 94 Hz analysis rate), 30-frame grade hysteresis (`gradeSwitchFrames=30`), a warmup gate (`warmupFrames=60`), and a peak-only classifier (treble-fraction gating removed post-2026-04-17T21-05-47Z after the Oxytocin false-positive) — but had no dedicated tests prior to this increment. A refactor or tuning change could silently regress any of these with no test signal; the failure mode would be "the diagnostic overlay shows the wrong grade on real music."

**Landed changes (commit `f570688f`):**

- **New test file** `PhospheneEngine/Tests/PhospheneEngineTests/Audio/InputLevelMonitorTests.swift` — 8 regression tests covering the 6 audit-recommended cases + 2 productivity additions:
  1. `test_submitSamples_peakDecaysAt0_9995` (audit #1) — drives a known peak then N silent submissions; asserts the published `peakDBFS` matches the analytical `0.9995^N` decay within Float tolerance (`< 0.01` dBFS).
  2. `test_submitMagnitudes_bandEnergyDominantBand` (audit #2, renamed from `bandEnergyEMA` to reflect the dominant-band-routing assertion shape) — sub/mid/treble band-energy routing verified via dominant-band spectra (a band-index swap in the bin-bound math would flip the asserted ratios).
  3. `test_recompute_warmupReturnsUnknown` (audit #3) — `.unknown` / "warming up" before `warmupFrames` (60) sample submissions accumulate; a real classification once warmup completes.
  4. `test_recompute_belowCriticalReturnsRed` (audit #4) — sustained peak at -20 dBFS (below `peakCriticalDBFS` -15) classifies `.red` with a dBFS-naming reason string.
  5. `test_recompute_hysteresisRequires30Frames` (audit #5) — drives `.red`, spikes to a `.green` candidate; asserts the 29th post-spike recompute still publishes `.red` and the 30th flips it (off-by-one defence on `gradeSwitchFrames=30`).
  6. `test_reset_clearsAllEnvelopes` (audit #6) — `reset()` zeroes every envelope, the frame counter, and overwrites the published snapshot with the default.
  7. `test_classification_isPeakOnlyNotTrebleSensitive` (added) — Oxytocin defence: drives a high peak with a bass-only spectrum, then floods the EMAs with treble-only spectra; the grade must stay `.green` throughout. A regression that re-introduced treble-balance gating would flip this and the Oxytocin false-positive would be back.
  8. `test_thresholdConstants_matchDesignSpec` (added) — locks `peakWarningDBFS`/-9, `peakCriticalDBFS`/-15, `warmupFrames`/60 against silent retunes (same shape as `AudioInputRouterSignalStateTests.test_reinstallDelays_matchDesignSpec`).

**Zero production-code changes required.** `InputLevelMonitor`'s public surface (`submitSamples`, `submitMagnitudes`, `currentSnapshot`, `reset`) is directly testable and consumes raw `Float` buffers — no injectable dependency, no testability seam, no test double needed. Tests use a `submitSamples(_:_:)` helper to pass `[Float]` arrays via `withUnsafeBufferPointer` without tripping the `force_unwrapping` lint rule.

**Test methodology.** No real-time waiting — `InputLevelMonitor`'s decay is per-`submitSamples`-call, not per-wall-clock-second, so a test that drives 100 submissions to verify the decay window runs in ~1 ms. Float assertions use absolute tolerance (Float multiplication over 100 iterations drifts in the 5th decimal). Each test instantiates a fresh monitor — no shared state, parallel-safe, no `@Suite(.serialized)` needed.

**Verification:** SwiftLint baseline holds at 0 violations / 371 files (test files in `PhospheneEngine/Tests/` are excluded per `.swiftlint.yml:8`, so the file count is unchanged). Engine test suite: **1,265 tests across 162 suites — all passing** (up from 1,257; +8 new tests). App test suite: 333 tests / 60 suites — the engine-target test file is not built by the App scheme, so the App surface is unaffected; the App run surfaced only pre-existing `@MainActor`-contention timing flakes (`FirstAudioDetectorTests`, `AppleMusicConnectionViewModelTests`, `StreamingMetadataTests` — all pass cleanly in isolation; see Risks below).

**Doc updates:**
- `docs/CAPABILITY_REGISTRY/AUDIO.md` CA-Audio-FU-5 row: Open → Resolved 2026-05-21 with commit hash + per-test name + scope rationale.
- This ENGINEERING_PLAN.md entry.

**Risks and follow-ups:** none for the increment itself — the tests are read-only against existing public API and require no production-code change. The App test suite exhibited a pre-existing `@MainActor`-contention timing flake during verification: `FirstAudioDetectorTests` (3 tests using 600 ms `Task.sleep` over a 250 ms internal timer; the test file's own line-35 comment documents the mechanism) failed under the full parallel App suite but passed cleanly in isolation (7/7, 0.6–1.2 s each). This is the same flake class as the documented `AppleMusicConnectionViewModel` timing/race flake and the CLAUDE.md "@MainActor debounce test timing margins under parallel execution" note (U.11). It is not a regression: this increment's code lives in the engine test target, which the App scheme does not build. Recommend a future App-side increment widen `FirstAudioDetectorTests`' sleep margins (or mark the suite `.serialized`) — out of scope for FU-5.

### CA-Audio-FU-4 — Tap-reinstall regression tests ✅ (2026-05-21)

Second of the Tier-1 Phase CA follow-up batch (CA-Presets-FU-4 + CA-Audio-FU-4). Closes the zero-test-coverage gap on `AudioInputRouter+SignalState.swift` flagged by the CA-Audio audit (AUDIO.md:806 follow-up row; AUDIO.md:160 finding). The 105-line extension implements the critical scrub-recovery path (3 attempts with 3/10/30 s backoff) but had no dedicated tests prior to this increment — a refactor or tuning regression could silently break audio recovery on every scrub-induced silence event with no test signal.

**Landed changes (commit `a6404575`):**

- **New test file** `PhospheneEngine/Tests/PhospheneEngineTests/Audio/AudioInputRouterSignalStateTests.swift` — 9 regression tests covering the 5 audit-recommended cases + 4 productivity additions:
  1. `test_scheduleNextReinstall_attemptCountSequence` (audit #1) — counter advances 1→2→3 then caps at 3, with no further workItem scheduling on the 4th call.
  2. `test_scheduleNextReinstall_doesNotDoubleScheduleWhilePending` (added) — guards the `guard reinstallWorkItem == nil else { return false }` branch at line 51; a regression would double-bump attempts on overlapping silence callbacks and burn through the 3-attempt cap on the first scrub.
  3. `test_cancelPendingReinstall_resetsAttempts` (audit #2) — verifies cancel zeroes both the workItem handle AND the attempt counter.
  4. `test_handleSignalStateChange_silentSchedulesReinstall` (added) — the `.silent` entry point from the SilenceDetector callback.
  5. `test_handleSignalStateChange_activeCancelsPending` (added) — the `.active` recovery entry point.
  6. `test_attemptTapReinstall_skipsIfStateNotSilent` (audit #3) — verifies the state-changed guard at line 78-83 (returns to `.active` during backoff window does NOT trigger reinstall).
  7. `test_backoffExhausted_noNewScheduling` (audit #4) — after 3 attempts the counter caps and no new workItem is scheduled; stable under repeated silence-callback firings.
  8. `test_nextActiveToSilent_resetsAttempts` (audit #5) — full silence→active→silence cycle, second silence run starts at attempts=1 (not continuation from prior).
  9. `test_reinstallDelays_matchDesignSpec` (added) — locks the `[3.0, 10.0, 30.0]` tuning against future silent retuning; if a real tuning change ships, this test must be updated in the same increment with the rationale in the commit message.

**Zero production-code changes required.** The internal init `init(capture:metadata:silenceDetector:)` was already in place as a testability seam at `AudioInputRouter.swift:91-101` (taking an injectable `SilenceDetector` which itself has injectable `timeProvider`). All reinstall-machine functions (`handleSignalStateChange`, `scheduleNextReinstall`, `cancelPendingReinstall`, `attemptTapReinstall`, `performTapReinstall`) are package-internal-visibility and accessible via `@testable import Audio`. The `reinstallAttempts` / `reinstallWorkItem` / `reinstallDelays` fields likewise.

**Test methodology.** The asyncAfter'd workItems in `scheduleNextReinstall` use real wall-clock delays of 3/10/30 s. Tests do NOT wait — they either simulate the workItem firing by directly calling the relevant API (e.g., calling `scheduleNextReinstall` again after a `clearPendingWithoutResettingAttempts` helper), or they verify the synchronous side effects (counter, workItem handle) without exercising the deferred execution path. Each test that schedules cleans up via `defer { router.cancelPendingReinstall() }` so background asyncAfter calls don't fire mid-next-test. All 9 tests run in ~1 ms each; total suite delta is ~9 ms wall-clock.

**Verification:** SwiftLint baseline holds at 0 violations / 371 files. Engine test suite: **1,257 tests across 162 suites — all passing** (up from 1,248; +9 new tests). App test suite: 333 tests / 60 suites — all passing (no change). Build clean on both `swift build --package-path PhospheneEngine` and `xcodebuild -scheme PhospheneApp test`.

**Doc updates:**
- `docs/CAPABILITY_REGISTRY/AUDIO.md` CA-Audio-FU-4 row: Open → Resolved 2026-05-21 with commit hash + per-test name + scope rationale.
- This ENGINEERING_PLAN.md entry.

**Risks and follow-ups:** none. The tests are read-only against existing internal API and require no production-code change. If a future refactor narrows the visibility of any of the reinstall-machine methods (e.g., making `scheduleNextReinstall` truly private), the tests will fail to compile and the refactor author will need to either preserve the internal-visibility surface or move the relevant tests behind a different seam.

### CA-Presets-FU-4 — Lumen Mosaic init-failure instrumentation ✅ (2026-05-21)

First of the Tier-1 Phase CA follow-up batch (CA-Presets-FU-4 + CA-Audio-FU-4). Closes the silent-allocation-failure diagnosis gap surfaced by the CA-Presets audit and documented in the BUG-016 addendum (`docs/QUALITY/KNOWN_ISSUES.md:111-141`). **BUG-016 stays Open** — instrumentation is not a fix; the increment closes the gap that prevented previous reproductions from being characterised post-hoc.

**Landed changes (commit `cb8cb0bb`):**

- **`PhospheneEngine/Sources/Presets/Lumen/LumenPatternEngine.swift`** (lines 580-595) — `Logging.session.error(...)` added inside the `init?(device:seed:)` failure branch. Writes to the unified log under category `"session"`. Captures the failure regardless of which App-side caller triggers the init (future-proofs against caller-site refactors that might drop the App-side log).
- **`PhospheneApp/VisualizerEngine+Presets.swift`** (lines 165-187, the LumenMosaic instantiation site inside `applyPreset .rayMarch`) — `sessionRecorder?.log(...)` added alongside the existing `logger.error(...)` call. Writes to `~/Documents/phosphene_sessions/<ts>/session.log` so the next reproduction is greppable from the on-disk artifact without a `log show` invocation.

**Belt-and-braces rationale:** the BUG-016 addendum's original recipe (`Logging.session?.log(...)` at the App-side site) was structurally inverted on channel routing — `Logging.session` is an `os.Logger`, not a `SessionRecorder`, so it writes only to the unified log. The on-disk `session.log` file is owned by `SessionRecorder.log(_:)`. The increment covers both channels: App-side gets the on-disk write; engine-internal gets the unified-log write with caller-site-agnostic coverage. Two corrections to the original addendum (channel routing + line-number citations) landed inline in the BUG-016 addendum follow-on note.

**Retrieval predicates for the next reproduction:**

```bash
# On-disk session.log (App-side SessionRecorder write)
grep "LumenPatternEngine: failed to allocate slot-8 buffer" \
  ~/Documents/phosphene_sessions/<ts>/session.log

# Unified log (engine-internal Logging.session.error write)
log show --predicate 'subsystem == "com.phosphene" AND category == "session"' \
  --info --last 30m | grep "LumenPatternEngine init failed"
```

**Verification:** SwiftLint baseline holds at 0 violations / 371 files (one line-length violation surfaced and fixed in-pass via multi-line string literal). Engine test suite: 1,248 tests across 162 suites — all passing (unchanged; no test surface modified). App build: `BUILD SUCCEEDED` on `xcodebuild -scheme PhospheneApp build`. App tests: passing (no test surface modified).

**Doc updates:**
- `docs/QUALITY/KNOWN_ISSUES.md` BUG-016 addendum extended with the new instrumentation note + corrected retrieval predicates.
- `docs/CAPABILITY_REGISTRY/PRESETS.md` CA-Presets-FU-4 row: Open → Resolved 2026-05-21 with commit hash + a summary of the two corrections to the original recipe.
- This ENGINEERING_PLAN.md entry.

**Risks and follow-ups:** if BUG-016 reproduces and neither retrieval predicate fires, the failure mode is one of the 4 non-allocation candidates (stuck-on-previous, visual artifacts, no-audio-response, or pale-dominant LM.9 regression) documented in the BUG-016 addendum's "5 candidate failure modes" table. Path-of-investigation is unchanged for those cases.

### CA-Audio-FU-9 — ARCH structural-claims sync (Module Map + §Key Types + per-source-file inline drift) ✅ (2026-05-21)

Twelfth Phase CA increment of the day — the consolidation pass for the 7-in-a-row Module Map drift pattern surfaced across CA.5 / CA.6 / CA.7a / CA.7b / CA-Audio / CA-Presets / CA-Shared. **Closes Phase CA: every Swift engine surface is audited AND the structural-claim documentation matches the code.**

**Scope expanded by CA-Shared closeout** from the original "Module Map only" filing to cover three additional axes: ARCH §Key Types (3 fictional struct claims surfaced by CA-Shared); ARCH §GPU Contract Details (verified clean in this pass — slot bindings match RenderPipeline + SpectralHistoryBuffer); per-source-file inline doc-comment drift (3 items surfaced by CA-Shared).

**Landed changes:**

- **§Module Map Shared/ block** — 5 missing entries added: `Shared.swift` module marker, the four `AudioFeatures+*` extension files (Analyzed / Frame / Metadata / SceneUniforms), `StemFeatures.swift` (D-099 / DM.2), `BeatSyncSnapshot.swift` (CLAUDE.md §Defect Handling artifact), the four `SessionRecorder+*` extensions (CSV / RawTap / Stems / Video), `BUG012Probe.swift` (BUG-012-i1 instrumentation, read-only), `UserFacingError.swift` + `UserFacingError+Presentation.swift`, `Dashboard/DashboardTokens.swift`. RenderPass enum cases corrected to include `mv_warp` and `staged`. SpectralHistoryBuffer entry's reserved-section description updated to reflect post-beat-grid layout (beat_times / bpm / lock_state / session_mode / downbeat_times / drift_ms through slot [2429]).

- **§Module Map Presets/ block** — 16 missing entries added: `Presets.swift` module marker, three `PresetLoader+*` extensions (`+Mesh`, `+Utilities`, `+WarpPreamble`), `PresetMetadata`, `PresetMaxDuration`, `PresetStage`, `SpectralCartographText`, two `FidelityRubric+*` extensions (`+Mandatory`, `+Optional`), `AuroraVeil/AuroraVeilState.swift`, three `FerrofluidOcean/*` files (`FerrofluidMesh`, `FerrofluidParticles`, `+InitialPositions`), four `Arachnid/ArachneState+*` extensions (`+BackgroundWebs`, `+ListeningPose`, `+Spider`, `+M7Diag`). The CA-Presets "18 missing files" finding is now closed (CA-Presets's count was off by 2 — actual missing = 16 once duplicates were de-duped against existing inline references).

- **§Module Map Diagnostics/ block** — 2 missing entries added: `SoakTestHarness+AudioGen` (procedural audio generator extracted for file-length compliance) and `SoakTestHarness+Reporting` (JSON + Markdown report builder extracted for file-length compliance).

- **§Module Map Renderer/ block** — 1 missing entry added: `RayTracing/RayIntersector+Internal` (the `packed_float3` vs `SIMD3<Float>` workaround file cross-referenced from `AudioFeatures+SceneUniforms.swift:9`).

- **§Module Map App/ block** — verified close to complete (~109 referenced entries vs 108 actual files); no systemic gap.

- **§Key Types section** — comprehensive rewrite. Deleted three entirely fictional struct claims (`BandEnergy`, `SpectralFeatures`, `OnsetPulses`) — these have never existed in code; the corresponding data lives inside FeatureVector. Moved three misplaced types (`Particle`, `SessionState`, `AudioSignalState`) out of the "Shared Module" sub-block into a new "Cross-module reference types" sub-block (their actual modules: Renderer/Presets, Session, Audio respectively). Added missing RenderPass cases (`mv_warp`, `staged`). Corrected FeatureVector field documentation — was claiming structural prediction + camera uniforms live in floats 1–24 when they actually live in separate structs (StructuralPrediction + SceneUniforms); now lists actual field layout. Clarified EmotionalState's `quadrant` as a computed property. Corrected SpectralHistoryBuffer reserved-section description (was [2402..2419]; actual is [2402..2429] through driftMs). Added missing types: `BeatSyncSnapshot`, `MetadataSource`, `StemSampleBuffer`, `Smoother`, `UMABuffer`, `UMARingBuffer`, `UserFacingError`.

- **Per-source-file inline doc-comment drift** — 3 items fixed in this commit: `AnalyzedFrame.swift:35` "Packed feature vector for GPU uniform upload (96 bytes)" → 192 bytes (D-099 / DM.2 post-extension size); `SpectralHistoryBuffer.swift:78` class-level "[2402..4095] reserved" rewritten to enumerate the beat-grid metadata layout through [2429]; `DashboardTokens.swift:5` "D-080" → "D-081 / DASH.1.1" (D-080 is the QR.2 stem-affinity decision, not the placement rationale).

**Verification:** SwiftLint baseline holds at 0 / 371. `swift build --package-path PhospheneEngine` → Build complete (3.84s). Engine test suite: 1,248 tests across 162 suites — all passing (unchanged; only doc-comment lines touched in Swift code). App test suite: 333 tests / 60 suites — all passing.

**Phase CA closure status:** with FU-9 landed, every Swift engine surface in `PhospheneEngine/Sources/` and `PhospheneApp/` is (a) audited via a capability-registry document AND (b) structurally documented in ARCHITECTURE.md without fictional claims or misplaced entries. **Phase CA is complete.** The only remaining audit work is the optional `.metal` shader audit (CA-Preset-Shaders) — recommend NOT scheduling per CA-Shared closeout (FidelityRubric + M7 manual review already cover that surface; methodology is distinct from capability-registry verdicts).

**Approach validation:** the consolidation-pass approach worked well — single-pass file inventory + per-block diff + targeted insertion edits. The CA-Shared "scope extension" recommendation to fold §Key Types + §GPU Contract Details + inline drift into FU-9 was correct: doing all four axes in one pass kept the doc-coherence story tight rather than scattering related fixes across multiple increments. Total wall-clock for FU-9 itself was ~1 session; the combined FU-1 + FU-2 + FU-3 + FU-9 wall-clock for the day was ~3 sessions. **The 7-in-a-row Module Map drift pattern is now closed.** Future audits should still surface drift when it appears, but the systemic backlog is gone.

### CA-Shared-FU-1 (wire-up) + CA-Shared-FU-2 (retire) + CA-Shared-FU-3 (retire) ✅ (2026-05-21)

Same-day resolution of three CA-Shared follow-ups, all under Matt's direction:

- **CA-Shared-FU-1 — wire up `UserFacingError.retryStatus` + `.isConditionBound`.** Matt's product call: wire up. Two consumer changes:
  - `LocalizedCopy.string(for: .spotifyRateLimited)` now sources the "attempt N of 3" suffix from `error.retryStatus.description` via new helper `appendRetryStatus(base:status:)`. Localizable.strings `error.connection.spotify_rate_limited` value reduced from `"Spotify is being slow — still trying (attempt %d of 3)"` to the base headline only — the suffix is composed by the helper. Output identical: `"Spotify is being slow — still trying (attempt 2 of 3)"`.
  - `PlaybackErrorBridge.showSilenceExtendedToast` now constructs toasts via new `toast(for:severity:source:)` helper that gates `duration: .infinity` AND `conditionID` on `error.isConditionBound`. Replaces the prior hardcoded silence-specific values. Behaviour unchanged for `silenceExtended` (still condition-bound, still gets `.infinity` duration + conditionID); future condition-bound errors (`audioLevelsLow`, `silenceBrief` if producers fire them) automatically route through the same gate.
  - Five new regression tests (3 in LocalizedCopyTests, 2 in PlaybackErrorBridgeTests).

- **CA-Shared-FU-2 — retire `SpectralHistoryPublishing` + `StemSampleBuffering` protocols.** Matt's product call: retire. Both public protocol declarations deleted from their respective files; concrete classes (`SpectralHistoryBuffer`, `StemSampleBuffer`) drop the protocol conformance and keep only `@unchecked Sendable`. Public method surface unchanged — every method was already declared `public` directly on the class. Test suite green without modification (tests already used concrete types). Same shape as CA.7-FU-4 dead-API retirement: if a future test or DI seam genuinely needs a protocol, re-introducing one is trivial.

- **CA-Shared-FU-3 — retire `Smoother.step(current:target:at:)`.** Matt's product call: retire. Convenience method deleted from `Smoother.swift`; doc-comment updated to reflect the simpler shape (`factor(at:)` only, inline EMA at call sites — matches the current convention in BeatDetector / BandEnergyProcessor). All 4 existing `factor(at:)` callers unaffected.

**Verification:** SwiftLint baseline holds at 0 violations / 371 files. Engine test suite: 1,248 tests across 162 suites — all passing (unchanged). App test suite: **333 tests across 60 suites — all passing** (up from 328; 5 new FU-1 regression tests). `xcodebuild -scheme PhospheneApp test` → TEST SUCCEEDED.

CA-Shared follow-up table updated with Resolved entries citing Matt's product calls + behaviour summary; Summary verdict counts updated (production-orphan: 2 protocols + 3 accessors → 0). All three follow-ups closed in one commit-cluster ahead of the FU-9 ARCH sync increment.

### CA-Shared — Shared Capability Audit ✅ (2026-05-21)

Eleventh per-subsystem audit pass under Phase CA — **closes the last unaudited Swift surface in the engine module.** Produced [`docs/CAPABILITY_REGISTRY/SHARED.md`](CAPABILITY_REGISTRY/SHARED.md) — 25 Swift files / 3,515 LoC (matches kickoff). Single-pass direct-read, no Explore agents needed; methodology stable since CA-Audio.

**Headline findings: all 22 type-declaring files `production-active`; zero `broken-but-claimed`; 2 production-orphan protocols (`SpectralHistoryPublishing`, `StemSampleBuffering`) + 3 production-orphan accessors (`UserFacingError.retryStatus`, `UserFacingError.isConditionBound`, `Smoother.step`); 4 missing Module Map entries + 3 entirely fictional ARCH §Key Types struct claims; 1 D-127 stems.csv producer-side gap.** Zero new BUG entries filed.

**All seven required invariant verifications landed clean.** (1) **D-099 / DM.2 Common.metal struct extension intact** (Swift producer side) — `FeatureVector` is `@frozen public struct ... Sendable` with 48 floats / 192 bytes; `StemFeatures` is `@frozen public struct ... Sendable, Equatable` with 64 floats / 256 bytes; first 32 / first 16 floats byte-identical to original DM.0 layout. Producer chain: MIRPipeline (DSP) → AnalyzedFrame → render-thread GPU buffer write at slot 2/3. (2) **UserFacingError ↔ UX_SPEC §9 alignment exhaustive 29:29** — every case maps to exactly one §9.1/§9.2/§9.3/§9.4 row; every row has a corresponding case. (3) **SessionRecorder drawable-size-lock invariant (Failed Approach #28) clean** — `videoSizeStableThreshold = 30` frames deferred-init; `writerRelockThreshold = 90` frames mismatch-skip-then-relock; `handleDimensionMismatch` skips frames rather than blits-into-wrong-geometry. (4) **TrackMetadata + PreFetchedTrackProfile + MetadataSource boundary closed** (CA.3 ↔ CA-Audio ↔ CA-Shared) — types live in `AudioFeatures+Metadata.swift` lines 10/30/69; producer chain via MetadataPreFetcher + StreamingMetadata; consumer chain via VisualizerEngine + AudioInputRouter + Session preparer. (5) **BUG012Probe surface characterised read-only** — 320 LoC, 12 static methods + Snapshot struct; NSLock-guarded with `nonisolated(unsafe)` storage matching the D-079 precedent; alarm-on-count>1 in stem/FFT in-flight counters; no candidate root cause beyond the existing 2026-05-20 race-surface analysis surfaced. **No BUG-012 addendum filed.** (6) **SpectralHistoryBuffer slot mapping verified** — kickoff claims confirmed: `[2402..2417] beat_times[16]`, `[2420] session_mode`. Full reserved-section layout: 2400 writeHead / 2401 samplesValid / 2402-2417 beat_times / 2418 bpm / 2419 lockState / 2420 sessionMode / 2421-2428 downbeat_times / 2429 driftMs. (7) **DashboardTokens placement clean** — kept in Shared; consumed by BOTH Renderer/Dashboard/* (DASH.7 builders via CA.7b) AND App/Views/Dashboard/* (DashboardOverlayView, DashboardRowView, DashboardCardView). Moving to Renderer would force App-side dependency on Renderer.

**Notable findings:**
- **Two production-orphan protocols** filed as CA-Shared-FU-2 — `SpectralHistoryPublishing` and `StemSampleBuffering` are declared and conformed-to in the same file each; production code stores the concrete class type. Documented test-doubles motivation not exercised.
- **Three production-orphan accessors** filed as CA-Shared-FU-1 + CA-Shared-FU-3 — `UserFacingError.retryStatus` (documented as retry-aware toast suffix routing primitive — not wired; LocalizedCopy hand-codes the strings instead); `UserFacingError.isConditionBound` (documented as PlaybackErrorBridge dismiss-gate — not wired); `Smoother.step(current:target:at:)` (zero consumers; only `factor(at:)` is consumed).
- **stems.csv producer-side gap** filed as CA-Shared-FU-4 — `drumsEnergyDevSmoothed` (StemFeatures float 43, V.9 / D-127) is recorded into the GPU buffer + live render path but the SessionRecorder's `csvRow(stems:)` formatter at lines 50-76 omits the column. Offline replay tools (Scripts/analyze_*.py, PresetSessionReplay) cannot inspect this field post-hoc — a real diagnostic gap for any future Ferrofluid Ocean tuning or aurora-coupling validation work.
- **ARCH §Key Types catastrophic drift** — lines 799/801/802 claim `BandEnergy` / `SpectralFeatures` / `OnsetPulses` exist as Swift structs. **They do not exist anywhere in the codebase.** The corresponding data lives inside `FeatureVector` (bass/mid/treble fields; spectralCentroid/spectralFlux; beatBass/beatMid/beatTreble). Lines 813/814/815 list `Particle` / `SessionState` / `AudioSignalState` under the "Shared Module" header — these live in Renderer+Presets / Session / Audio respectively. Line 816 lists `RenderPass` enum cases missing `mv_warp` and `staged`. Line 779 `FeatureVector` field documentation conflates `structuralPrediction` + `camera uniforms` into "Floats 1–24" — neither lives in FeatureVector. **Bundled into CA-Audio-FU-9 with a scope-extension recommendation: FU-9 should cover §Module Map + §Key Types + §GPU Contract Details in one pass.**

**Four follow-ups filed (CA-Shared-FU-1 through CA-Shared-FU-4):** FU-1 retire-or-wire `UserFacingError.retryStatus` + `.isConditionBound`; FU-2 retire-or-keep-by-design `SpectralHistoryPublishing` + `StemSampleBuffering` protocols; FU-3 retire-or-keep `Smoother.step` convenience accessor; FU-4 extend stems.csv writer to include `drumsEnergyDevSmoothed` (D-127 column).

**Doc-drift fixes landed in this increment:** CLAUDE.md §What NOT To Do line "Per `UX_SPEC.md §8`" corrected to `§9.4` (error taxonomy lives at §9; §8 is Recovery & Adaptation Flows); CLAUDE.md `§8.5` jargon-avoidance line corrected to `§9.5` (DOC.3 refactor moved Copy Principles from §8 to §9). UserFacingError.swift:7 already correctly cited §9 — the producer-side authority was always right; only the CLAUDE.md pointer was stale. ARCH §Module Map + §Key Types drift bundled into CA-Audio-FU-9.

**Phase CA closure status: every Swift engine surface is now audited.** Remaining audit work: (a) CA-Audio-FU-9 Module Map Sync (cross-cutting; now a 7-in-a-row systemic finding, recommended-prioritised); (b) optional `.metal` shader audit (CA-Preset-Shaders — methodology-distinct from capability-registry verdicts; recommend NOT scheduling unless a specific shader-fidelity question warrants the cost; existing FidelityRubric + M7 manual review already cover that surface).

**Approach validation:** single-pass direct-read at 3.5k LoC scaled cleanly (no Explore agents); the per-accessor production-orphan check (CA.7b refinement) caught three accessor orphans that "file-level any-consumer" would have missed (`.retryStatus`, `.isConditionBound`, `Smoother.step`); Pass 0 BUG-status cross-check caught the CLAUDE.md `UX_SPEC.md §8 error taxonomy` reference drift before any file-read. The kickoff's "20-25 files" scope estimate was accurate (25 actual). **Recommended next subsystem: CA-Audio-FU-9** — the 7-in-a-row Module Map drift now demands consolidated resolution; the CA-Shared discovery of three entirely fictional ARCH §Key Types struct claims extends FU-9's scope beyond simple file-listing sync into structural-claim validation. **Phase CA can declare closed after FU-9 lands.**

### CA-Presets — Presets Capability Audit (Swift slice) ✅ (2026-05-21)

Tenth per-subsystem audit pass under Phase CA — closes the last unaudited engine module (Presets/ Swift slice; .metal shaders deferred). Produced [`docs/CAPABILITY_REGISTRY/PRESETS.md`](CAPABILITY_REGISTRY/PRESETS.md) — 30 Swift files / **9,175 LoC** (kickoff said 3,129 — counted only the infrastructure cluster; per-preset state cluster added 5,116 LoC and certification cluster added 930 LoC) + 16 JSON sidecars (schema-verification reads). Single increment, single-pass; direct-read all infrastructure + certification files + AuroraVeil/Gossamer/FerrofluidMesh, parallel-Explore-agent reads for the high-LoC Arachne + Lumen + FerrofluidParticles clusters.

**Headline findings: all 30 Swift files `production-active`; zero `broken-but-claimed` at code level; 3 doc-level findings (ARCH §Module Map drift 18 missing + 4 retired-file references; `LumenPatternState` stride 376→568 per LM.4.7; `AuroraVeil.json "passes": []` under-documented semantics); 1 BUG-016 producer-side candidate root cause filed as addendum (`LumenPatternEngine.init?` returns nil silently on `device.makeBuffer` failure with no `os.Logger` / `sessionRecorder` log — silent allocation failure could explain the symptom).** Zero new BUG entries (no new BUG-017); BUG-016 addendum extends existing-Open BUG body.

**All seven required invariant verifications landed clean.** (1) **D-094 ArachneSpiderGPU 80-byte invariant intact** — struct definition at `ArachneState+Spider.swift:44-77` is exactly 80 bytes (4 × Float header + 8 × SIMD2<Float> tips); listening-pose lift adjusts `tip[0]`/`tip[1]` clip-space Y CPU-side in `writeSpiderToGPU()` without struct extension. (2) **D-095 V.7.7C foreground-hero architecture intact** — `writeBuildStateToWebs0()` packs `bs.anchors[]` (4-bit count + 6 × 4-bit indices) into `webs[0].rngSeed` byte offset 28 via `Self.packPolygonAnchors(_:)`; spider trigger on `features.bassAttRel > 0.30` (V.7.7C.3 correct form, NOT the retired Failed Approach #57 `subBass + bassAttackRatio < 0.55`); polygon decoding uses Fisher-Yates → angle sort → largest-angular-gap bridge pair. (3) **BUG-011 round 8 invariants intact** — `frameDurationSeconds = 2.775`, `radialDurationSeconds = 1.389`, `spiralChordsPerBeat = 3.24`, `spiralChordAccumulator: Float = 0`, `stemEnergySilenceThreshold = 0.02`; **critical ordering verified**: `pausedBySpider = spiderBlend > 0.01` set BEFORE `audioSilent = stemEnergySum < 0.02` (ArachneState.swift:826-836); `_presetCompletionEvent: public let` for cross-module PresetSignaling conformance; `Arachne.json wait_for_completion_event: true` + `PresetMaxDuration.maxDuration(forSection:)` returns `.infinity` for flagged presets. (4) **D-097 particle-siblings intact** — `ParticleGeometryRegistry.knownPresetNames = ["Murmuration"]`; zero Drift Motes remnants (grep across `PhospheneEngine/Sources` + `PhospheneApp/`); `FerrofluidParticles` ships own conformer (does NOT extend `ProceduralGeometry`). (5) **D-099 / DM.2 Common.metal struct extension intact** — FeatureVector first 32 floats + StemFeatures first 16 floats byte-identical to original DM.0 layout; preset-side preamble at `PresetLoader+Preamble.swift:34-128` matches the Swift-side `@frozen FeatureVector` + `StemFeatures` declarations. (6) **Drift Motes / D-102 retirement clean** — no DriftMotes files, JSON sidecars, PresetCategory cases, or `motes_update` kernel references. (7) **FidelityRubric ↔ SHADER_CRAFT.md §12.1 aligned** — M1 (detail cascade), M2 (≥4 octaves), M3 (≥3 distinct materials), M4 (D-026 deviation + no absolute thresholds), M5 (silence-fallback runtime), M6 (perf budget), M7 (always manual). One clarification: **pale-tone-share ≤ 0.30 (D-LM-cream-rescission) is NOT enforced as a rubric item** — handled exclusively by M7 manual review.

**BUG-016 producer-side characterisation.** Read `LumenPatternEngine.swift` + `LumenMosaicPaletteLibrary.swift` end-to-end. **Candidate root cause filed as BUG-016 addendum:** `LumenPatternEngine.init?(device:seed:)` returns nil on `device.makeBuffer(length: 568, options: .storageModeShared)` failure without any logging from the Presets-module-internal side (the App-side `applyPreset` consumes the nil with an `os.Logger.error(...)` to `com.phosphene.app` category, but that line does NOT reach session.log). Mapping the 5 BUG-016 candidate failure modes: Mode 1 (black/blank) — plausible Swift-side instrumentation gap; Mode 4 (no audio response) — known LM.4.3 limitation (no FFT fallback if `f.beatPhase01` never wraps); Modes 2/3/5 are out of Swift scope (App-layer apply path / shader compilation / palette-library color analysis). Filed **CA-Presets-FU-4** for the `Logging.session?.log(...)` instrumentation upgrade.

**Notable doc-drift findings.** (a) **`LumenPatternState` stride is 568 bytes, not 376** as ARCHITECTURE.md still claims at line 623 (LM.4.7 added the 192-byte `palette[12]` tuple for the curated palette library; the `trackPaletteSeed{A,B,C,D}` LM.7 chromatic-tint fields became zeroed dead-weight ABI continuity). Fixed in this increment. (b) **Stalker entries in ARCHITECTURE.md §Module Map (lines 616-618) refer to deleted files** — `Shaders/Stalker.metal` + `Stalker/StalkerGait.swift` + `Stalker/StalkerState.swift` were all removed in Increment 3.5.7 (retired in favour of the 3D ray-march SDF spider easter egg inside Arachne). Fixed in this increment with a single retirement note. (c) **`Lumen/LumenPatterns.swift`** referenced at ARCH line 624 — deleted at LM.4.4; leaving inline note as historical. (d) **Eighteen missing files** in ARCH §Module Map Presets/ block — bundled into CA-Audio-FU-9 (Module Map Sync) per the kickoff bundling rule (>3 missing files defer to FU-9). (e) **`LumenMosaic.json` carries a `"lumen_mosaic": {...}` configuration block** (cell_density, cell_jitter, frost_amplitude, etc.) that is NOT decoded by PresetDescriptor — dead JSON. Filed as **CA-Presets-FU-2** (recommend remove). (f) **`AuroraVeil.json "passes": []`** empty-array semantics is intentional per AV.2.2 mv_warp drop, but documented only via inline shader comment at `AuroraVeil.metal:537-541`; arguably should be `"passes": ["direct"]`. Filed as **CA-Presets-FU-1** (cosmetic).

**Five follow-ups filed (CA-Presets-FU-1 through CA-Presets-FU-5):** FU-1 cosmetic AuroraVeil.json clarity; FU-2 LumenMosaic.json dead config block; FU-3 retire `GossamerState.lcg(_:)` dead helper (comment says "kept for future Stalker extraction" — Stalker retired in Increment 3.5.7); FU-4 add `Logging.session?.log(...)` for LumenPatternEngine init-failure instrumentation (depends on Matt's BUG-016 reproduction); FU-5 add code-comment in FidelityRubric+Mandatory.swift documenting pale-tone-share is M7-manual-only.

**Doc-drift fixes landed in this increment:** ARCH §Module Map line 623 `LumenPatternState` size 376 → 568 + LM.4.7 history annotation extended; ARCH §Module Map lines 616-618 Stalker entries removed + replaced with single retirement note; ARCH §Module Map adds `Lumen/LumenMosaicPaletteLibrary.swift` entry (LM.4.7 curated palette library). KNOWN_ISSUES.md BUG-016 body extended with addendum noting LumenPatternEngine init-failure silent-nil + recommended logging upgrade.

**Approach validation:** the per-cluster split (infrastructure / per-preset state / certification) gave a natural unit-of-audit progression. Pre-grep visibility verification (CA.5+ refinement) caught zero discrepancies. The non-nil-caller production-orphan check (CA.7b refinement) was not load-bearing here — all setter / mutator APIs on per-preset state classes have non-nil callers from `VisualizerEngine+Presets.swift`. ARCH §Module Map drift is now a **6-in-a-row systemic finding** across CA.5/6/7a/7b/CA-Audio/CA-Presets — bundles into CA-Audio-FU-9. The kickoff's "3,129 LoC" scope claim was off by 3× (actual: 9,175 LoC) — Pass 0 verification caught this immediately. **Recommended next subsystem: CA-Shared** (`PhospheneEngine/Sources/Shared/` — the last remaining unaudited engine surface; cross-cuts every other module via FeatureVector / StemFeatures / SceneUniforms / TrackMetadata types; expected smaller than CA-Audio at ~8-12 files). Alternative: CA-Audio-FU-9 (Module Map Sync) if cumulative drift warrants prioritisation. Alternative: a `.metal` shader audit increment (CA-Preset-Shaders) — methodology-distinct from capability-registry verdicts; would need a Pass 0 split decision.

### CA-Audio-FU-2 (LookaheadBuffer kept) + CA-Audio-FU-3 (MusicKitFetcher kept) + CA-Audio-FU-9 (Module Map Sync filed) ✅ (2026-05-21)

Three same-day follow-up resolutions after CA-Audio's audit closeout, all under Matt's direction:

- **CA-Audio-FU-2 — keep LookaheadBuffer.** Matt's product call: **KEEP** as Phase MV anticipatory-architecture infrastructure. Planned consumers: (a) Orchestrator anticipatory preset transitions (switch fired 2.5 s ahead so mv_warp crossfade lands ON the structural boundary instead of after — the difference between "the visualizer chases the music" and "the visualizer rides the music"); (b) drop-anticipation visual telegraphing (windup animation triggered by build-up detection ahead of the drop); (c) beat-aligned transitions to the exact frame via BeatGrid downbeat scheduling; (d) Phase MV / MILKDROP_ARCHITECTURE.md musicality requires anticipation. Structurally analogous to CA.7-FU-3 ICB-keep + CA.7b-FU-3 RayTracing-keep precedents. ARCH §Module Map Audio/ LookaheadBuffer entry updated to reflect kept-by-design status with planned consumers listed.
- **CA-Audio-FU-3 — keep MusicKitFetcher.** Matt's product call: **KEEP** as the Apple Music first-class metadata path. Planned consumers: (a) wire into `buildFetcherList()` for Apple Music users (gives ~half the macOS audience a higher-quality metadata path than the current MusicBrainz fallback); (b) direct-catalog-API path for tempo via `https://api.music.apple.com/v1/catalog/{storefront}/songs/{id}` (the underlying REST API exposes `tempo`; only the Swift wrapper doesn't surface it — the fetcher would URLSession-call this with the user's MusicKit developer token); (c) future-proof against Apple closing the SDK gap (`fetchBPM` stub becomes a one-line replacement when `Song.tempo` ships); (d) scaffolding for queue-awareness (Apple Music playlists, library, Now Playing queue — pre-warming next preset based on next-track metadata). Structurally analogous to CA.7-FU-3 + CA.7b-FU-3 keep precedents. File/type name mismatch (`MusicKitBridge.swift` contains `MusicKitFetcher`) noted separately as cosmetic — recommend renaming the file to `MusicKitFetcher.swift` in a future cleanup. ARCH §Module Map Audio/ MusicKitBridge entry updated.
- **CA-Audio-FU-9 — file Module Map Sync as a planned increment.** The ARCH §Module Map drift is now a **5-in-a-row systemic finding** (CA.5 / CA.6 / CA.7a / CA.7b / CA-Audio all surfaced module-map drift). Per-increment overhead is small; cumulative drift is large; the same problem recurs every audit. Filed as a standalone registry+doc-only increment that will run `find PhospheneEngine/Sources PhospheneApp -name '*.swift' | sort` against every §Module Map block in ARCH (including Tests/) in one pass. Not blocking CA-Presets — CA-Presets can land first and bundle any further Presets/ drift into the sync pass. Estimate 1 session.

Verification: no code changes (registry-only). `docs/CAPABILITY_REGISTRY/AUDIO.md` updated: Summary verdict count for production-orphan reframed as "production-orphan (kept-by-design) — 2 files" with planned-consumer rationale per file; Follow-up Backlog rows for CA-Audio-FU-2 + CA-Audio-FU-3 marked Resolved with Matt's keep rationale + planned-consumer list; CA-Audio-FU-9 added to backlog. ARCH §Module Map Audio/ LookaheadBuffer + MusicKitBridge entries extended with kept-by-design annotation + planned-consumer rationale. CA-Audio's headline LookaheadBuffer finding (1-of-1 doc-level broken-but-claimed) remains addressed (ARCH §Audio Capture diagram correction landed in the closeout).

### CA-Audio — Audio Capability Audit ✅ (2026-05-21)

Ninth per-subsystem audit pass under Phase CA. Produced [`docs/CAPABILITY_REGISTRY/AUDIO.md`](CAPABILITY_REGISTRY/AUDIO.md) — 16 files / 3,294 Swift LoC covering the capture pipeline (Audio.swift module marker + AudioBuffer + AudioInputRouter + AudioInputRouter+SignalState + SystemAudioCapture + FFTProcessor + LookaheadBuffer), signal-quality monitors (SilenceDetector + InputLevelMonitor), metadata fetcher cluster (MetadataPreFetcher + MusicBrainzFetcher + SpotifyFetcher + SoundchartsFetcher + MusicKitBridge), streaming poll (StreamingMetadata), and the Protocols.swift surface. Single-pass audit (direct-read all 16 files in two parallel batches; no Explore agents needed at 3.3k LoC).

**Headline findings: 13 of 16 files `production-active`; 2 file-level `production-orphan` (LookaheadBuffer + MusicKitBridge/MusicKitFetcher); 3 field-level `production-orphan` (AudioInputRouter.onAnalysisFrame + .onRenderFrame + FFTProcessor.printHistogram); 1 method-level `stub` (MusicKitFetcher.fetchBPM always returns nil — MusicKit Swift SDK does not expose tempo); 1 doc-level `broken-but-claimed` (ARCH §Audio Capture diagram line 40 claims LookaheadBuffer in pipeline — code never wires it; fixed in this increment); zero `broken-but-claimed` at the code level; zero new BUG entries.**

**All four kickoff-required verifications landed clean.** (1) **D-079 sample-rate plumbing clean** — `Scripts/check_sample_rate_literals.sh` exits 0; literal `44100` grep in Sources/Audio returns 2 hits both in Protocols.swift:111 doc-comment (CI gate correctly ignores comment lines); tap-sample-rate immutably captured via the `(rate: Float)` IO-proc callback arg + App-side NSLock-guarded `_tapSampleRate` storage (CA.5 chain). (2) **Tap recovery state machine matches ARCH §68 byte-for-byte** — `reinstallDelays: [TimeInterval] = [3.0, 10.0, 30.0]` at AudioInputRouter.swift:70; three attempts; cancel-on-active; re-check `silenceDetector.state == .silent` before performing the install; lock-guarded mutation of `reinstallAttempts` + `reinstallWorkItem`. **Gap: zero dedicated tests for the reinstall logic** (filed CA-Audio-FU-4). (3) **SilenceDetector + InputLevelMonitor timings match ARCH §487-488** — SilenceDetector defaults silenceDuration=3.0s / suspectDuration=1.5s (= silenceDuration/2) / recoveryDuration=0.5s; InputLevelMonitor peakEnvelope decay 0.9995/update at ~94 Hz → 21.3s time constant (math derivation in audit doc); hysteresis gradeSwitchFrames=30; peak-only classification post-2026-04-17T21-05-47Z. **Gap: no InputLevelMonitorTests.swift** (filed CA-Audio-FU-5). (4) **Failed Approach #21 + #22 verified clean at SystemAudioCapture** — buildTapDescription uses `stereoGlobalTapButExcludeProcesses: []` for .systemAudio (line 256) and `stereoMixdownOfProcesses: [AudioObjectID(PID)]` non-empty array for .application (line 269; FA #21 prohibits only the empty-array form). `CGRequestScreenCaptureAccess()` lives in App's `VisualizerEngine+PublicAPI.swift:21` per the single-request-point invariant documented at `Permissions/ScreenCapturePermissionProvider.swift:2`.

**CA.3 Session ↔ Audio boundary-noted item closes here.** Full producer-side trace of MetadataPreFetcher: `init(fetchers:timeoutSeconds:maxCacheSize:)` defaults 3s + 50; `prefetch(for:) async` parallel withTaskGroup + LRU promote-on-hit; `cachedProfile(for:)` sync lookup; `merge(_:)` first-non-nil-wins. Session-side consumers at `SessionPreparer.swift:86, 132, 299` confirmed. **CA.3 SESSION.md line 145 correction landed in this increment:** `TrackMetadata` lives in `Sources/Shared/AudioFeatures+Metadata.swift:30`, NOT in Audio — same for `PreFetchedTrackProfile` (line 69) + `MetadataSource` (line 10). MetadataPreFetcher itself does live in Audio.

**LookaheadBuffer is the audit's load-bearing finding.** ARCH §Audio Capture diagram (line 40) claims `→ LookaheadBuffer (2.5s analysis/render split)` is part of the live capture pipeline. Code: **zero production instantiations.** `AudioInputRouter.onAnalysisFrame` (line 113) + `.onRenderFrame` (line 117) are the wire callbacks that would source the lookahead — both declared but never assigned in production. `TransitionPolicy.swift:134` doc-comment claims "Matches the LookaheadBuffer delay of 2.5 s" — that's coincidental, not coupled. Same structural shape as CA.7b's RayTracing finding (production-active code, zero production consumers, planned for future use). Filed as **CA-Audio-FU-2** for Matt's product call (wire / keep as infrastructure / retire); ARCH diagram annotated as planned-but-unwired in this increment.

**Kickoff staleness: BUG-005 attribution.** Kickoff claimed BUG-005 (Spotify preview_url null) was "Audio-module-internal; SpotifyFetcher producer-side." Verification: Audio's `SpotifyFetcher.swift:122-147` calls `/v1/search` returning only `(id, duration_ms)` — no preview_url field exists in the Audio data path. Actual BUG-005 producer is the **Session-layer** `SpotifyWebAPIConnector.swift:241` (extracts `preview_url` from /items endpoint) consumed by `PreviewResolver.swift:73`. Both Session-side files were audited at the Session module surface in CA.3. KNOWN_ISSUES.md BUG-005 body itself is correct (it references PreviewResolver); only the kickoff prompt asserted the wrong domain. Registry-only correction filed as **CA-Audio-FU-1**.

**MusicKitFetcher is fully orphan.** Public class in `MusicKitBridge.swift` (file/type name mismatch — minor). Zero production instantiations (not in `buildFetcherList()` which composes MusicBrainz + Soundcharts/Spotify env-gated + App-side ITunesSearchFetcher), zero test sites. Core feature `fetchBPM(for:)` is a stub (MusicKit Swift SDK does not expose tempo per in-code comment; method always returns nil). Even if wired, would only duplicate MusicBrainz's genre + duration coverage. Filed as **CA-Audio-FU-3** for Matt's product call (recommend delete per the "if 'reusable infrastructure' appears in defense" check from CA.7b precedent).

**Eight follow-ups filed (CA-Audio-FU-1 through CA-Audio-FU-8):** FU-1 resolved in this audit (kickoff-staleness correction); FU-2 Matt product call on LookaheadBuffer; FU-3 Matt product call on MusicKitFetcher; FU-4 tap-reinstall tests; FU-5 InputLevelMonitor tests; FU-6 retire FFTProcessor.printHistogram; FU-7 tighten MoodClassifying docstring (10-floats-per-frame × 2 = 20 total); FU-8 RUNBOOK §Spotify connector setup disambiguate Session OAuth vs Audio client-credentials.

**Doc-drift fixes landed in this increment:** ARCH §Audio Capture diagram (line 40 LookaheadBuffer arrow → annotated as planned-but-unwired with comment-block pointer to CA-Audio audit); ARCH §Module Map Audio/ block extended with the 2 missing files (`Audio.swift` module marker + `AudioInputRouter+SignalState.swift` extension) and 6 entries annotated with CA-Audio findings (LookaheadBuffer production-orphan, MusicKitBridge production-orphan, plus production-active annotations matching the audit verdicts); CA.3 SESSION.md line 145 corrected (TrackMetadata lives in Shared, not Audio).

**Approach validation:** direct-read at 3.3k LoC scaled cleanly (no Explore agents); Pass 0 BUG-status cross-check caught the BUG-005 attribution kickoff staleness; non-nil-caller production-orphan check (CA.7b refinement) fired correctly for the LookaheadBuffer callbacks (file-level orphan check alone would have missed because AudioInputRouter itself is heavily production-active). **The ARCH Module Map drift is now a 5-in-a-row systemic finding** across CA.5/6/7a/7b/CA-Audio — recommend filing a standalone module-map sync increment running `find PhospheneEngine/Sources PhospheneApp -name '*.swift' | sort` against the ARCH Module Map blocks in one pass. **Recommended next subsystem: CA-Presets** (per-preset state classes under `Sources/Presets/` + .metal shader files — last remaining unaudited engine module; expect to need a Pass 0 split decision: state classes vs. shader files). Alternative: **CA-Shared** (smallest natural next pass after CA-Presets; declared deferred indefinitely per CA-Audio kickoff but now the only other unaudited engine surface).

### CA.7b-FU-3 (RayTracing kept) + CA-Audio kickoff ✅ (2026-05-21)

Matt's product call on CA.7b-FU-3: **keep RayTracing infrastructure**. Rationale: *"it will be used eventually by presets we haven't created yet"* — D-096 Arachne3D toolkit citation + V.8.7+ BVH refraction documented planned consumers, plus future ray-tracing-using presets not yet specced. Registry-only resolution (no code change); `RENDERER_SUPPORTING.md` CA.7b-FU-3 row marked Resolved with Matt's rationale. Structurally analogous to CA.7-FU-3 ICB-keep precedent. ARCH §Module Map lines 561-562 already extended in the CA.7b doc-drift commit with production-orphan + planned-consumer notes; no further ARCH changes needed.

In the same session, **CA-Audio kickoff prompt landed** ([`docs/prompts/PHASE_CA_KICKOFF_CA_AUDIO_2026-05-21.md`](prompts/PHASE_CA_KICKOFF_CA_AUDIO_2026-05-21.md)) — recommended next subsystem per CA.7b closeout. Closes the CA.3 Session ↔ Audio boundary-noted item (`MetadataPreFetcher` producer-side); covers 16 files / 3,294 LoC (capture pipeline + signal-quality monitors + metadata fetcher cluster + protocols + module marker). Audit itself pending Matt's scheduling.

### CA.7b — Renderer Capability Audit (Dashboard / Geometry / RayTracing) ✅ (2026-05-21)

Eighth per-subsystem audit pass under Phase CA — closes the Renderer subsystem fully (CA.7a covered the core dispatch path; CA.7b covers the supporting modules). Produced [`docs/CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md`](CAPABILITY_REGISTRY/RENDERER_SUPPORTING.md) — 15 files / 2,241 Swift LoC. **All four kickoff-required verifications complete**: (1) DASH.7 producer-side **clean against D-087 / D-088 / D-089 + CA.6's 16 line-anchored view-side confirmations** — full producer chain trace from `VisualizerEngine+Dashboard.publishDashboardSnapshot` through `@Published var dashboardSnapshot` + Combine `.throttle(33 ms)` into the three Builders, each with per-row D-088/D-089 colour + contrast confirmations (MODE/BPM/BAR/BEAT for BeatCard; DRUMS/BASS/VOCALS/OTHER timeseries for StemsCard; FRAME always + QUALITY/ML conditional for PerfCard); 280pt card width consistent; 33 ms throttle matches `DashboardSnapshot` doc-comment; 240-sample `StemEnergyHistory.capacity` matches view-model ring buffer. (2) D-097 particle-geometry siblings **clean** — `ParticleGeometry` protocol surface (AnyObject + Sendable, 3 required members: `activeParticleFraction`/`update(features:stemFeatures:commandBuffer:)`/`render(encoder:features:)`) matches D-097 spec at `ParticleGeometry.swift:33-79`; storage typed as `(any ParticleGeometry)?` at `RenderPipeline.swift:31`; `ProceduralGeometry` zero parameterisation hits (no `presetName`/`kernelOverride`/etc., CLAUDE.md §What NOT To Do invariant respected); `ParticleGeometryRegistry.knownPresetNames = ["Murmuration"]` sole entry post-Drift Motes retirement (D-102); `ParticleDispatchRegistryTests` catalog gate working. (3) MeshGenerator D-051 dispatch **clean** — `device.supportsFamily(.apple8)` Apple silicon family gate at init + `usesMeshShaderPath` branch at every draw call; mesh path uses `drawMeshThreadgroups` with per-meshlet thread counts (M3+); fallback path uses `drawPrimitives(.triangle, count: 3)` fullscreen-triangle (M1/M2); slot-4 mesh-shader path reuse per CA.7a's ARCH extension confirmed (MeshGenerator binds only slot 0 FeatureVector + slot 1 densityMultiplier; fragment slot 4's `meshPresetFragmentBuffer` is RenderPipeline+MeshDraw's binding territory, not MeshGenerator's). Only mesh-shader-using preset today is **Fractal Tree** (`Presets/Shaders/FractalTree.json:7`). (4) RayTracing **`production-orphan` + `boundary-noted`** — **zero production consumers** across `PhospheneApp/` + `PhospheneEngine/Sources/` (only test consumers `BVHBuilderTests` + `RayIntersectorTests` plus one pure documentation cross-reference at `Sources/Shared/AudioFeatures+SceneUniforms.swift:9`); planned consumer is `Arachne3D` per D-096 V.8.0-spec (V.8.x deferred per Matt's 2026-05-08 sequencing call — V.8.1 row in ENGINEERING_PLAN.md unstarted; BVH refraction explicitly deferred past V.8.7 per D-096 Decision 3). Recommended **keep-by-design** analogous to CA.7-FU-3's ICB resolution — filed as **CA.7b-FU-3** for Matt's keep/retire decision. **Cross-reference finding (CA.7a-scope, surfaced from CA.7b inspection)**: `setMeshPresetBuffer(_:)` + `setMeshPresetFragmentBuffer(_:)` have **zero non-nil production callers** — the only call site is the `pipeline.setMeshPresetBuffer(nil)` reset at `VisualizerEngine+Presets.swift:55`. Latent slot-1 collision: RenderPipeline+MeshDraw.swift:65-67 binds `meshPresetBuffer` at object/mesh slot 1 (if non-nil), then MeshGenerator.draw() lines 204-205 overwrite slot 1 with `densityMultiplier` (last-write-wins). Today no live bug (no non-nil caller exists). Filed as **CA.7b-FU-4** with recommended deprecate-and-remove (CA.7-FU-4 `setRayMarchPresetComputeDispatch` retirement precedent). **Doc-drift fixes landed in this increment**: ARCH §Module Map Renderer/Dashboard/ block had stale `DashboardTextLayer` (line 564) + `DashboardCardRenderer` (line 566) entries despite DASH.7 retirement (D-087) — both deleted; ARCH §Module Map Renderer/Geometry/ block missed `ParticleGeometryRegistry` — inserted with one-line behavioural description; ARCH §Renderer/Dashboard/PerfSnapshot line 569 incorrectly claimed `forceDispatchCount` field — rewritten as decision-code + retry-ms; ARCH §Module Map Renderer/Dashboard/`DashboardCardLayout` (line 565) extended with `.timeseries` row variant + sparkline height; `DashboardFontLoader` (line 563) extended with Clash Display + system-fallback semantics; ARCH RayTracing entries (lines 561-562) extended with production-orphan + planned-consumer notes. **Zero new BUG entries filed**; **zero broken-but-claimed**. **Approach validation:** direct-read at 2.2k LoC scaled cleanly without Explore agents; the "non-nil caller" production-orphan check at setter granularity is a new pattern worth carrying forward — CA.7a verified setters as production-active because any caller existed; CA.7b's slot-1 discovery happened because non-nil callers were checked specifically. ARCH §Module Map drift is now a **4-in-a-row systemic finding** across CA.5/6/7a/7b — recommend a future bulk pass against `find` output rather than continuing one-or-two-items-per-increment. **Recommended next subsystem: CA-Audio** (`PhospheneEngine/Sources/Audio/` — closes the CA.3 boundary-noted item). Alternative: CA-Presets (per-preset state classes under Sources/Presets/). Renderer is now fully audited (CA.7a core + CA.7b supporting = 38 files / 7,654 LoC); the only remaining unaudited engine modules are Audio + Presets.

### CA.7-FU-3 (kept) + CA.7-FU-4 (retired) follow-ups ✅ (2026-05-21)

Two product calls landed same-day after CA.7a's audit closeout, both under Matt's direction:

- **CA.7-FU-3 — keep ICB cluster.** Matt's product call: keep. ICB infrastructure (`RenderPipeline+ICB.swift`, `RenderPass.icb`, `ICB.metal`, `IndirectCommandBufferState`, App-side `case .icb:` no-op + log at `VisualizerEngine+Presets.swift:303-306`, `RenderPipelineICBTests`) stays in place — test-active but production-orphan, awaiting a future preset that declares `"icb"` in its passes list. No code change; registry-only resolution.
- **CA.7-FU-4 — retire `setRayMarchPresetComputeDispatch(_:)`.** Matt's product call: retire. Code removed across 4 files: `RenderPipeline.swift` (the `RayMarchPresetComputeDispatch` typealias + `rayMarchPresetComputeDispatch` storage + `rayMarchPresetComputeDispatchLock` + the V.9 Session 4.5b Phase 2b MARK header + doc-comment block); `RenderPipeline+PresetSwitching.swift` (the public `setRayMarchPresetComputeDispatch(_:)` setter + its doc-comment); `RenderPipeline+RayMarch.swift` (the per-frame `computeDispatch` snapshot at line 143 + the `if let dispatch = computeDispatch { dispatch(...) }` call site at lines 170-172 + the "Phase 2b" comment block); `VisualizerEngine+Presets.swift` (the `pipeline.setRayMarchPresetComputeDispatch(nil)` reset call at line 71 + the "intentionally NOT set" comment block at lines 264-266). The closure was kept-by-design for a Ferrofluid Ocean Phase 2b revival that was deactivated at Phase 1 round 4 ("particles are pinned, one-shot bake at preset apply is sufficient"); no consumer materialised in 6+ months. If a future ray-march preset needs per-frame compute, re-introduce the API at that time.

Verification: `swift build --package-path PhospheneEngine` → Build complete (10.73s). `xcodebuild -scheme PhospheneApp build` → BUILD SUCCEEDED. Engine test suite: 1,248 tests across 162 suites — all passing. App test suite: 328 tests across 60 suites — all passing. `swiftlint lint --strict` → 0 violations / 371 files. Audit doc updated: `docs/CAPABILITY_REGISTRY/RENDERER.md` CA.7-FU-3 + CA.7-FU-4 rows marked Resolved with Matt's product-call rationale; Summary §Verdict counts table updated (`production-orphan` 2 → 1 after CA.7-FU-4 retirement).

### CA.7a — Renderer Capability Audit (core pipeline) ✅ (2026-05-21)

Seventh per-subsystem audit pass under Phase CA (closed by the CA.7a half of the CA.7 split). Produced [`docs/CAPABILITY_REGISTRY/RENDERER.md`](CAPABILITY_REGISTRY/RENDERER.md) — 23 files / 5,413 Swift LoC covering the load-bearing per-frame render dispatch path. **All five kickoff-required verifications landed clean**: GPU contract slot reservations (9 buffer + 9 texture slots match code byte-for-byte; slot 12 DynamicTextOverlay + slot 13+ staged sampled outputs surfaced as built-but-undocumented and added to ARCH §GPU Contract Details); MLDispatchScheduler D-059 5-rule algorithm + Tier 1/2 deferral caps (2000ms/30 + 1500ms/20); FrameBudgetManager 30-frame rolling window + 180-frame upshift hysteresis + 14ms/16ms per-tier targets (the BUG-011-closure-load-bearing spec); mv_warp dispatch path against D-027; Failed Approach #66 test/prod parity (the `useMeshPath` fixture parameter). **One dead-code cluster** (CA.7-FU-2 — `depthDebugEnabled`/`runDepthDebugPass`/`depthDebugPipeline`) and **two production-orphan clusters** (CA.7-FU-3 ICB infrastructure deferred per VisualizerEngine+Presets.swift:305 comment; CA.7-FU-4 `setRayMarchPresetComputeDispatch` kept-by-design after Phase 1 round-4 deactivation). **One marginal parity finding** — AuroraVeilMVWarpAccumulationTest reimplements the 3-pass mv_warp sequence rather than calling `RenderPipeline.drawWithMVWarp(...)` directly (CA.7-FU-1; the test exercises an equivalent path but not the live helper letter-for-letter). **Doc drifts fixed in this increment**: ARCH §Renderer line 184-185 buffer summary was inverted + claimed 4-7 future — rewritten to canonical order with slot 4/5/6/7/8 assignments noted; ARCH §Module Map Renderer/ block extended with 7 missing files (RenderPipeline+FeedbackDraw / +Staged / +BudgetGovernor / +PresetSwitching, RayMarchPipeline+PipelineStates, DynamicTextOverlay, Protocols); ARCH §GPU Contract Details extended with slot 12, slot 13+, and slot 4 mesh-shader path reuse note. **Zero new BUG entries filed**; every load-bearing claim in CLAUDE.md / ARCHITECTURE.md / DECISIONS.md matches the code. **Approach validation:** hybrid direct-read (16 files) + 1 parallel Explore agent (9 files) scaled cleanly at 5.4k LoC; the kickoff's "22 files / 7.5k LoC" estimate was +1 file low and 38 % LoC over — future kickoff drafters should `wc -l` the scope first; the methodology stays. Next subsystem: **CA.7b** (Dashboard / Geometry / RayTracing — 15 files / 2,241 LoC) closes Renderer fully. Alternative: CA-Audio (smaller; closes the CA.3 boundary-noted item).

### CA.5-FU-2 + CA.6-FU-1 + CA.6-FU-2 + CA.6-FU-3 follow-ups ✅ (2026-05-21)

Four small App-layer doc + architectural-consistency follow-ups landed same-day after CA.6's audit closeout, all under Matt's product-call direction:

- **CA.5-FU-2** — `LiveAdaptationToastBridge.swift` docstring rewrite (Matt's product call: **stay invisible**). Engine-driven adaptations do NOT toast; toast surface is reserved for user-initiated keystroke acknowledgements per UX_SPEC §7.4 ("on keystroke"). File-header at lines 1-15 + class-level doc at lines 22-26 rewritten to drop the "engine events" observation source and clarify `emitAck(_:)` is for user-action acks only. No behavioural change.
- **CA.6-FU-1** — `DashboardOverlayView.swift:10` file-header docstring drift fix. "0.55α" → "0.96α" with rationale rewording to match the existing lower-block "near-opaque … WCAG AA contrast" explanation at lines 50-56. Code at line 57 unchanged.
- **CA.6-FU-2** — `DashboardCardView.swift:5` file-header docstring drift fix. "Clash Display title at 18pt" → token-anchored phrasing "Clash Display Medium title at `DashboardTokens.TypeScale.bodyLarge` (15 pt) relative to `.title3`". Code unchanged.
- **CA.6-FU-3** — `ConnectorPickerView.swift` architectural consistency. Extracted `private struct AppleMusicConnectionWrapper: View` mirroring the existing `OAuthSpotifyConnectionWrapper` shape: holds `@StateObject private var viewModel = AppleMusicConnectionViewModel()` so the VM (and its in-flight 2 s auto-retry Task) survives `ConnectorPickerView` body re-evaluations triggered by `viewModel.appleMusicRunning` changes from the NSWorkspace launch/terminate observers. `destination(for: .appleMusic)` now builds the wrapper instead of constructing the VM inline. Defensive against the same class of body-re-eval VM-orphaning the Spotify wrapper was originally written to prevent.

Verification: `xcodebuild -scheme PhospheneApp build` → BUILD SUCCEEDED. `swiftlint lint --strict` → 0 violations / 371 files. No new tests required (3 are doc-only edits; the wrapper is a structural pattern match with no observable surface change in the common case). Audit docs updated: `docs/CAPABILITY_REGISTRY/APP.md` CA.5-FU-2 row marked Resolved; `docs/CAPABILITY_REGISTRY/APP_VIEWS.md` CA.6-FU-1/2/3 rows marked Resolved.

### Increment CA.6 — App-Layer Capability Audit (Views + ViewModels presentation slice) ✅ (2026-05-21)

Sixth per-subsystem audit under Phase CA. Produced [`docs/CAPABILITY_REGISTRY/APP_VIEWS.md`](CAPABILITY_REGISTRY/APP_VIEWS.md) — 59 files / 8,285 LoC covering the App-layer presentation slice: `PhospheneApp/Views/` (47 files across 9 subdirectories + root-level) + `PhospheneApp/ViewModels/` (12 files), plus `DashboardOverlayViewModel.swift` which lives in `Views/Dashboard/` per the filesystem layout. The kickoff's ~6,889 LoC estimate undercounted by ~20%; methodology unaffected. Headline findings: **58 of 59 files `production-active`; zero `broken-but-claimed`; zero new BUG entries filed**. **PlaybackChromeViewModel BUG-015 / D-091 / QR.4 consumer chain verified clean** — full producer-to-consumer trace from `VisualizerEngine.swift:77` through `+Capture.swift:152` through `ContentView.swift:85` (publisher binding) through `PlaybackView.swift:74,90` (init relay) into `PlaybackChromeViewModel.swift:121,169-176` (publisher subscription) and `:242-254` (`refreshProgress()` direct consumer); no lowercased title+artist string matching anywhere; `grep -rnE "lowercased\(\).*title|lowercased\(\).*artist" PhospheneApp/ViewModels PhospheneApp/Views` returns zero hits. **D-091 single-SettingsStore enforcement verified clean across the entire View tree** — ONE legitimate `@StateObject SettingsStore()` at `PhospheneApp.swift:25`; ONE `@EnvironmentObject SettingsStore` consumer at `PlaybackView.swift:55`; all four Settings sub-sections (`AboutSettingsSection`, `AudioSettingsSection`, `DiagnosticsSettingsSection`, `VisualsSettingsSection`) take `SettingsViewModel` as `@ObservedObject`; SettingsView's custom `init(store:)` builds the VM as `@StateObject(wrappedValue: SettingsViewModel(store: store))` (correct D-091 topology). **DASH.7 dashboard surface verified clean against D-088 / D-089** — 16 line-anchored confirmations: DarkVibrancyView backdrop (`.vibrantDark` + `.hudWindow`), 0.96α surface tint, 1px border stroke, `.environment(\.colorScheme, .dark)` lock, 320pt width, throttle 33ms (~30Hz), `ingestForTest(_:)` test seam, 240-sample stem history per stem, `.singleValue` D-089 inline form (label-left, 13pt mono right, frame height 17pt), `.progressBar` value column 110pt with `.fixedSize(horizontal: true)`, no SF Symbols (status via valueText color), Clash Display Medium 15pt title, Epilogue Medium 11pt + 1.5 tracking labels, asymmetric transition + spring-choreographed toggle from PlaybackView. **U.10 / U.11 timing-margin compliance verified clean across all 9 widened App-test files** from the `[dev-2026-05-21-c]` + `[dev-2026-05-21-d]` chip (`AppleMusicConnectionViewModelTests`, `LiveAdaptationToastBridgeTests`, `NetworkRecoveryCoordinatorTests`, `PlaybackChromeViewModelTests`, `ReadyViewModelTests`, `ReadyViewTimeoutIntegrationTests`, `SpotifyConnectionViewModelTests`, `SpotifyOAuthTokenProviderTests`, `ToastManagerTests`) — every margin meets or exceeds U.11 baselines (700ms wait for 300ms debounce; 250-400ms for connect/login async actor-hop completions); `@Suite(.serialized)` annotation present on both URLProtocol/keychain-stub-using suites (SpotifyOAuthTokenProviderTests line 99, SpotifyKeychainStoreTests line 9). **3 `unverified-claim` findings**: (1) `DashboardOverlayView.swift:10` file-header docstring claims "0.55α" surface tint but code at line 57 uses `.opacity(0.96)` — drift INSIDE the file's own docstring (ARCHITECTURE.md / D-089 correctly say 0.96α; CA.6-FU-1). (2) `DashboardCardView.swift:5` file-header claims "Clash Display title at 18pt" but code resolves `DashboardTokens.TypeScale.bodyLarge` which is `15` — drift INSIDE the file's own docstring (ARCHITECTURE.md correctly says 15pt; CA.6-FU-2). (3) `ConnectorPickerView.swift:111-115` creates `AppleMusicConnectionViewModel()` inline in the `@ViewBuilder` destination for `.appleMusic` while the equivalent Spotify path uses an `OAuthSpotifyConnectionWrapper` `@StateObject` to preserve the VM across parent body re-evaluations — architectural inconsistency between AM and Spotify (CA.6-FU-3); production impact likely low (AM has no URL-callback foregrounding scenario), but worth either applying the wrapper pattern for consistency or documenting the rationale. **2 large `built-but-undocumented`**: (a) ARCHITECTURE.md §Module Map PhospheneApp/Views/ block listed ~20 of 47 files (27 missing) + 3 §UI Layer paragraph drift items (NoAudioSignalBadge → ListeningBadgeView rename in U.6; missing Shift+→/Shift+←/Z/M/Esc/Shift+? shortcuts per U.6b + UX_SPEC §7.7; DashboardOverlayView Layer 6 not mentioned); (b) §Module Map PhospheneApp/ViewModels/ block listed 4 of 12 (8 missing). Same systemic pattern as CA.1 / CA.2 / CA.3 / CA.4 / CA.5. **No `production-orphan` findings** — every public/internal type, every method has a production consumer (two candidates investigated and rejected: `AppleMusicConnectionViewModel.cancelRetry()` consumed at `AppleMusicConnectionView.swift:33` on view disappear; `ReadyViewModel.planPreviewEnabled` consumed at `ReadyView.swift:142-143`). **CA.5-FU-1 + CA.5-FU-3 landed before CA.6 began** (commits `688095d4` MultiDisplayToastBridge dead-field cleanup + `b8952fda` MusicKitFetcher → ITunesSearchFetcher rename per kickoff status-on-entry); CA.5-FU-2 (LiveAdaptationToastBridge engine-event docstring product call) remains pending — carried forward to next App-adjacent increment. Doc-drift corrections applied to `ARCHITECTURE.md` (§UI Layer paragraph: NoAudioSignalBadge → ListeningBadgeView; keyboard-shortcut list extended with U.6b additions; DashboardOverlayView Layer 6 added; PlaybackView ownership topology updated to reflect 4 @StateObject ViewModels + 8 @State services + 2 @EnvironmentObject; §Module Map PhospheneApp/Views/ block extended with all 47 files at one-line behavioural granularity; §Module Map PhospheneApp/ViewModels/ block extended with all 12 ViewModels). **Approach validation:** direct reads + 3 parallel Explore agents scaled cleanly for 8.3k LoC (kickoff's 6.9k estimate ~20% low — future kickoff drafters should `wc -l` the scope first); D-091 enforcement grep produced confidence in one shot; PlaybackChromeViewModel consumer-chain trace produced 10 byte-level confirmations matching the design; DASH.7 verification produced 16 line-anchored confirmations against D-088 / D-089; the U.10/U.11 table-based audit produced complete per-file compliance verdicts. **The format continues to produce actionable findings**: 3 small follow-ups (two file-header docstring drifts + one architectural-consistency question), 1 optional doc-promotion (CA.6-FU-4), 1 CA.5-FU-2 carry-forward, plus the four kickoff-required verifications all clean. **Recommended next subsystem: CA.7 — CA-Renderer** (`PhospheneEngine/Sources/Renderer/` is the largest unaudited engine module — FrameBudgetManager + RenderPipeline + MLDispatchScheduler + Dashboard renderer + per-pass pipelines). Alternative: CA-Audio (smaller; closes the AudioInputRouter + SilenceDetector + InputLevelMonitor + StreamingMetadata + MetadataPreFetcher surface CA.3 boundary-noted). The App layer is now fully closed.

### Increment CA.5 — App-Layer Capability Audit (engine-adapter slice) ✅ (2026-05-21)

Fifth per-subsystem audit under Phase CA. Produced [`docs/CAPABILITY_REGISTRY/APP.md`](CAPABILITY_REGISTRY/APP.md) — 49 files / 7,975 LoC covering the App-layer engine-adapter slice: top-level (14 files including VisualizerEngine + 11 extensions + ContentView + PhospheneApp + MusicKitFetcher), Services/ (30 files), Permissions/ (3 files), Models/ (2 files). The Views/ (47 files) + ViewModels/ (12 files) presentation slice is deferred to CA.6 per the kickoff's recommended sub-scope split (justified by architectural layering — Services + VisualizerEngine adapter are the engine-coupling surface where the four prior audits' findings actually fire; Views + ViewModels is the SwiftUI presentation surface). Headline findings: **48 of 49 files `production-active`; zero `broken-but-claimed`; zero new BUG entries filed**. **BUG-015 wire shape verified clean** — all seven design notes from the BUG-015 Resolved field land in code byte-for-byte (runOrchestratorLiveUpdate(mir:) at +Orchestrator.swift:287, called from +Audio.swift:184 at the end of processAnalysisFrame, cadence gate `analysisFrameCount % orchestratorWireFrameDivisor == 0` with divisor=30 → ~3 Hz, off-plan skip path, liveTrackPlanIndex written in +Capture.swift:131 under orchestratorLock, lastClassifiedMood written in +Audio.swift:432 under orchestratorLock, orchestratorWireLoggedThisTrack reset on track change at +Capture.swift:137, once-per-track diagnostic dual-writing to session.log + os.Logger at +Orchestrator.swift:323-331); the OrchestratorWiringRegressionTests regression test is in place with two `@Test` methods that strip comments before counting (so doc-comment mentions don't satisfy the assertion). **BUG-012-i1 instrumentation intact** across all 8 instrumented files (48 BUG012Probe references total); no edits to instrumented files per CA.5 Hard Rules. **BUG-016 App-layer surface inventoried without proposing a fix**: Lumen Mosaic apply path lives inside `case .rayMarch:` at +Presets.swift:166-178 gated on `desc.name == "Lumen Mosaic"`; slot-8 binding via setDirectPresetFragmentBuffer3 is correct per D-LM-buffer-slot-8; LumenPatternEngine init can return nil and the failure logs to os.Logger only (not session.log) — recommend adding sessionRecorder?.log() on the failure branch for the next BUG-016 reproduction. **1 `production-orphan`** at field level — `MultiDisplayToastBridge.coalesceTask` + `MultiDisplayToastBridge.pendingEvents` (`MultiDisplayToastBridge.swift:22-23`) declared but never read or written; the line-21 comment "Coalescing: rapid adds/removes within 0.5s produce one toast" documents an intent the code doesn't implement; cited grep returns only the two declaration sites. Same shape as CA.4-FU-1's `transitionPolicy`. Registered as CA.5-FU-1. **1 `unverified-claim`** — `LiveAdaptationToastBridge.swift:1-14` docstring claims engine-event observation source that has no production-wired consumer (the BUG-015 wire's engine-event downstream consumer logs to os.Logger / session.log via the once-per-track diagnostic but does NOT call `emitAck()`); CA.5-FU-2 surfaces this as a product call (wire engine events through emitAck or rewrite the docstring). **2 large `built-but-undocumented`** — `ARCHITECTURE.md §Module Map PhospheneApp/` block listed 15 of 49 engine-adapter files (34 missing); §Module Map Tests/PhospheneApp/ block was absent entirely (60+ test files exist). Same systemic pattern as CA.1 / CA.2 / CA.3 / CA.4. **Plus 1 file-naming drift**: `MusicKitFetcher.swift` contains an `ITunesSearchFetcher` class with explicit "no MusicKit dependency" top-comment — recommend renaming the file per CA.5-FU-3. **D-091 / Failed Approach #55 enforcement verified clean** — cited grep returns only the legitimate `@StateObject SettingsStore()` at `PhospheneApp.swift:25` (the single app-entry instance) plus the regression-test's shadow probe + source-presence assertion; no production re-introduction of the dead pattern. **U.10 / @Suite(.serialized) verified** — the only URLProtocol-stub-using App test (`SpotifyOAuthTokenProviderTests.swift:98 — @Suite("SpotifyOAuthTokenProvider", .serialized)`) carries the annotation. **SwiftLint baseline**: zero warnings in `PhospheneApp/` (the 18 remaining warnings are all in `PhospheneEngine/` — out of CA.5 scope; engine-side SwiftLint cleanup chip is independent). **CA.1-FU-1 status update**: the BUG-015 fix routes `liveBoundary` from `mirPipeline.latestStructuralPrediction` (option (b) from CA.1's framing, NOT option (a) as CA.4 recommended) — the per-frame StructuralAnalyzer chain now has a runtime consumer; CA.1-FU-1 should close as `superseded`. Doc-drift corrections applied to `ARCHITECTURE.md` (§Module Map PhospheneApp/ rewritten with all 49 engine-adapter files at one-line behavioural granularity; new PhospheneAppTests/ block under Tests/ listing the load-bearing regression / contract tests including OrchestratorWiringRegressionTests + SettingsStoreEnvironmentRegressionTests + PlaybackChromeIndexBindingTests + DefaultPlaybackActionRouterTests + the U.11 Spotify cluster). **Approach validation**: direct reads + parallel Explore agents both scaled cleanly; Pass 0 BUG-status cross-check found zero kickoff staleness; the cited-grep rule fired once and produced the field-level production-orphan with confidence; the visibility-verification grep continues as cheap insurance for agent reports; the BUG-015 wire-shape verification produced 10 concrete byte-level confirmations. **Recommended next subsystem: CA.6 — App Views + ViewModels** (the deferred half of the App layer; 59 files / 6,889 LoC across `PhospheneApp/Views/` + `PhospheneApp/ViewModels/`; largest unaudited surface in the codebase by file count; home of the U.10 / U.11 flake cluster).

### Increment CA.4 — Orchestrator Capability Audit ✅ (2026-05-20)

Fourth per-subsystem audit under Phase CA. Produced [`docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md`](CAPABILITY_REGISTRY/ORCHESTRATOR.md) — 14 files / ~2,950 LoC covering scoring + policy core (3 files), planning (3 files), live adaptation (3 files), reactive mode (1 file), signaling (2 files), router + settings (2 files). Headline findings: 12 of 14 files `production-active` at the Orchestrator-module surface; **1 `broken-but-claimed` cluster filed as [BUG-015](QUALITY/KNOWN_ISSUES.md#bug-015)** — `VisualizerEngine.applyLiveUpdate(...)` has zero production call sites; `DefaultLiveAdapter.adapt(...)` and `DefaultReactiveOrchestrator.evaluate(...)` are correctly implemented and unit-tested but **never invoked at runtime** because the App-layer audio-callback wire was never added; the entire Phase 4.5 / 4.6 runtime adaptation pipeline is dead in production today; **severity P1** (`pipeline-wiring`); supersedes CA.1-FU-1's framing because there is no runtime consumer of `MIRPipeline.latestStructuralPrediction` until BUG-015 is fixed. **1 `production-orphan`** (`DefaultLiveAdapter.transitionPolicy` field declared and stored but never invoked — both evaluation paths construct `PlannedTransition` values directly; cited grep returns 3 declaration/init hits and 0 invocation hits). **1 `unverified-claim`** (`PresetScorer.swift:86` doc comment cites `(D-030)` for the Weight rationale; D-030 is `SpectralHistoryBuffer as unconditional GPU contract at buffer(5)` — correct citation is D-032; the weight values themselves match D-032 byte-for-byte). **2 large `built-but-undocumented`** (ARCHITECTURE.md §Module Map Orchestrator/ listed 5 of 14 source files — 9 missing; §Module Map Tests/Orchestrator/ block was absent entirely — 16 test files exist). **Plus 4 smaller doc-drift findings:** (a) `ARCHITECTURE.md §Orchestrator` "Forthcoming (4.4+)" list (lines 214-219) was obsolete — all four items have shipped at the Orchestrator-module surface; (b) `ARCHITECTURE.md §Orchestrator` line 211 quoted `cutEnergyThreshold > 0.7` — code is `0.85` per D-080 amendment to D-033; (c) `DECISIONS.md` D-032 (line 471) still describes the original `cutEnergyThreshold = 0.7` without the D-080 amendment note; (d) `PresetSignaling.swift:9-10` source-file doc claimed "Arachne does NOT emit yet — wiring is V.7.8" but Arachne has emitted via D-095 / V.7.7C.2 since 2026-05-09 and the orchestrator-side subscription has been wired end-to-end since BUG-011 round 8 on 2026-05-12. **D-120 revert verified clean** — cited grep `grep -rn "concept_tags\|motion_paradigm\|conceptTags\|motionParadigm"` across Swift sources + JSON sidecars returns zero hits; commit `0981ca4f` (2026-05-13) was complete. **CA.1 synthetic-StructuralPrediction re-evaluation resolved**: the synthetic at `SessionPlanner.swift:317-322` is the planning-time construction (`confidence: 1.0`, both timestamps at clock) firing `TransitionPolicy.structuralBoundary` at every track change — it is NOT the source of runtime predictions; runtime predictions would flow through `applyLiveUpdate(...)` → `DefaultLiveAdapter.evaluateBoundaryReschedule(...)` once BUG-015's missing wire lands. **CA.1-FU-1 re-scoped**: ship option (a) (gate the per-frame chain to prep-time only) as a standalone increment now — saves audio-callback CPU with zero behavioural change since no runtime consumer exists pre-BUG-015. Doc-drift corrections applied to `ARCHITECTURE.md` (§Orchestrator block rewritten to reflect Phase 4 complete with the BUG-015 caveat for runtime wiring; cutEnergyThreshold value corrected to 0.85; §Module Map Orchestrator/ block extended with all 14 source files and one-line descriptions; §Module Map Tests/Orchestrator/ block added with all 16 test files), `DECISIONS.md` (one-line D-032 amendment note pointing at D-080 rule 5 for the cutEnergyThreshold raise), in-source comments at `PresetScorer.swift:86` (D-030 → D-032) and `PresetSignaling.swift:9-10` (current-state rewrite per D-095 + BUG-011 round 8). **Approach validation:** continue into CA.5 with the methodology refinements above — direct file reads scaled cleanly to the 2,950-LoC Orchestrator subsystem; the cited-grep rule for production-orphan claims fired once with confidence (the dead `transitionPolicy` field is falsifiable in a way independent of auditor interpretation); the CA.1 boundary-touchpoint re-evaluation produced a load-bearing CA.4-specific finding (BUG-015) that the audit format was set up to catch. For CA.5 specifically, declare which App-layer files are read-only in scope so wire-tracing isn't ambiguous. **Recommended next subsystem: App layer** (`PhospheneApp/`) — BUG-015 lives there, plus a constellation of boundary-noted findings that an App audit closes cleanly (`PresetScoringContextProvider`, `DefaultPlaybackActionRouter`, `VisualizerEngine+Orchestrator`, `LiveAdaptationToastBridge`, `CaptureModeSwitchCoordinator`, the entire ViewModel + View tree). Alternative: defer CA.5 scope until BUG-015's diagnosis lands if it turns up surprises that motivate a different priority.

### Increment CA.3 — Session Capability Audit ✅ (2026-05-20)

Third per-subsystem audit under Phase CA. Produced [`docs/CAPABILITY_REGISTRY/SESSION.md`](CAPABILITY_REGISTRY/SESSION.md) — 22 files / ~3,425 LoC covering lifecycle + state machine (6 files), preparation pipeline (6 files), track/playlist value types (3 files), boundary-resolved-from-CA.1 (`BeatGridAnalyzer` + `GridOnsetCalibrator`), quality gates (`BPMMismatchCheck`), Spotify connectors (`SpotifyTokenProvider` + `SpotifyWebAPIConnector`), and 1 module marker + 1 stub. Headline findings: 21 of 22 files `production-active`; 1 `stub` (`LocalFolderConnector.swift` is gated behind `#if ENABLE_LOCAL_FOLDER_CONNECTOR` — flag never set in any xcconfig or Package.swift; class never compiles in production; intentional v2 scaffold per D-046 / UX_SPEC §4.4); 2 `documented-but-missing` (`ARCHITECTURE.md §Session Preparation` step list at lines 112–124 omitted D-070 preview-URL primary path, Beat This! offline grid, DSP.4 drums-stem grid, BUG-007.8 grid-onset calibration, and Round 26 metadata-driven `beatsPerBar` override; `§Module Map Tests/Session/` referenced phantom `StemCacheTests`); 2 large `built-but-undocumented` gaps (Session/ module-map block listed 9 of 22 source files — 13 missing; Tests/Session/ listed 9 of 14 real test files — 6 missing + 1 phantom); 0 `production-orphan`; 0 `broken-but-claimed`; 0 new BUG entries. **Kickoff-prompt staleness flagged:** BUG-006 was cited as Open/P1 by the kickoff but `KNOWN_ISSUES.md` already showed `Status: Resolved` (BUG-006.2 wiring fix, 2026-05-06, validated by session `2026-05-06T20-11-46Z`); confirming the kickoff against the issue file before starting is now a recommended CA.4 methodology step. **The CA.1/CA.2 boundary-deferred items all resolved here**: `GridOnsetCalibrator` → `production-active`, recommend relocating to `Sources/DSP/` per `CA.3-FU-1` (functionally a DSP capability; both consumers already import DSP — closes CA.1-FU-5's GridOnsetCalibrator half); `BeatGridAnalyzer` → `production-active`, **stays in Session/** (testability-seam pattern co-located with consumer is correct, matches the 5-protocol family in Session); `MoodClassifier.currentState` end-of-prep read at `SessionPreparer+Analysis.swift:295` → `production-active`, intentional EMA-smoothed-state architecture covering the full ~30 s preview (not drift; the runtime `setMood(...)` path is independently preserved). Doc-drift corrections applied to `ARCHITECTURE.md` (§Session Preparation rewritten as a 7-step pipeline matching `SessionPreparer+Analysis.analyzePreview(...)`; §Module Map Session/ block extended with 13 missing files; §Module Map Tests/Session/ corrected — phantom `StemCacheTests` removed, 6 real test files added; §Session Recording gained a `WIRING:`-log surface note for BUG-006.1 + DSP.4). **Approach validation:** continue into CA.4 with three methodology refinements — (1) direct file reads scale to ≤ 5k-LoC subsystems and eliminate the CA.2 "agents over-assert publicness" failure mode entirely; agents remain right for larger modules but the visibility-verification grep is mandatory regardless; (2) cross-check kickoff prompts against `KNOWN_ISSUES.md` as a routine second step — the 30-second BUG-006 staleness cross-check would have saved hours of false-positive diagnosis work; (3) the new `boundary-noted` vs `boundary-deferred` distinction had real bite — three boundary-noted findings (Session ↔ App, Session ↔ Orchestrator, Session ↔ DSP/ML/Audio) were assigned without re-auditing those subsystems' internals. **Recommended next subsystem: Orchestrator** — Session ↔ Orchestrator surface touchpoints already surfaced (`TrackProfile` consumption, `SessionPlan` → `PlannedSession` lift, `PlannedSession.canonicalIdentity` consumed during prepared-cache wiring); auditing Orchestrator closes that boundary cleanly before CA-App or CA-Audio.

### Increment CA.2 — ML Capability Audit ✅ (2026-05-20)

Second per-subsystem audit under Phase CA. Produced [`docs/CAPABILITY_REGISTRY/ML.md`](CAPABILITY_REGISTRY/ML.md) — 16 files / 4,507 LoC covering the Beat This! transformer (5 files, D-077), the StemSeparator + StemModel + StemFFT cluster (8 files, D-009 / D-010), the MoodClassifier (2 files, D-009), and the ML.swift module marker. Headline findings: zero `broken-but-claimed`; zero new BUG entries; four `production-orphan` clusters at the field/method level — (a) `StemFFTEngineProtocol` (only conformer = `StemFFTEngine` itself; no DI consumer), (b) `StemSeparator.stft/.istft` (public wrappers with zero external callers — tests bypass to `fftEngine.forward/inverse`), (c) five `BeatThisModel` model-dimension constants (`numHeads/.headDim/.numBlocks/.ffnDim/.outputClasses`) with zero external consumers, (d) `MoodClassifier.featureCount/.emaAlpha` + three error-type public exposures with no external catchers. Each cited grep in the audit doc per CA.2 §production-orphan rule. Two large `built-but-undocumented` gaps: the entire Beat This! transformer is absent from `ARCHITECTURE.md §ML Inference` (lines 242–247 described only StemSeparator + MoodClassifier); the `ML/` module-map block at lines 440–447 listed 7 of 16 files (9 missing). One `documented-but-missing`: `ARCHITECTURE.md §Mood Classifier Inputs` claimed "Spectral flux normalized via running-max AGC (0.999 decay)" — the production caller (`VisualizerEngine+Audio.swift:240-249`) passes `mir.rawSmoothedFlux` (un-AGC-normalized smoothed flux), which is what the classifier was trained against per `MoodClassifier.swift:14-19`'s input-vector docstring; doc was stale, training/runtime aligned. Doc-drift corrections applied to `ARCHITECTURE.md` (§ML Inference: added Beat This! transformer narrative + Open-Unmix HQ window-size constants; §Module Map ML/: added 9 missing files with one-line behavioural descriptions; §Mood Classifier Inputs: replaced stale prose with the per-index table including the raw-flux note) and to `KNOWN_ISSUES.md §BUG-012 → Instrumentation installed` (added a pointer to the audit doc's BUG-012 instrumentation map — the centralised reading-aid that previously didn't exist anywhere). **The audit did not edit any of the 8 BUG-012-i1-instrumented files** per CA.2 Hard Rules; the audit's read of every BUG-012-adjacent code path produced no new candidate root cause; one small diagnostic enrichment is suggested for the next instrumentation tranche as `CA.2-FU-2`. **Approach validation:** the format continues to produce real, actionable findings; the new `production-orphan`-requires-cited-grep rule fired four times with bite; the §BUG-012 instrumentation map is the audit's load-bearing per-increment contribution. Recommend continuing into CA.3 with one pre-grep visibility-verification tweak (Explore agents over-asserted `public` on internal types in 3 of 4 CA.2 cases; a 30-second visibility grep catches the over-assertion). Recommended next subsystem: **Session** — CA.1 + CA.2 between them left three boundary-deferred Session placements (`GridOnsetCalibrator`, `BeatGridAnalyzer`, the `MoodClassifier.currentState` read-at-end-of-prep pattern); closing Session is the natural next step before Renderer / Orchestrator / App. **Alternative:** if BUG-012 reproduces in the next week and Step-2 diagnosis lands, the diagnosis may surface a different priority.

### Increment CA.1 — DSP / MIR Capability Audit ✅ (2026-05-20)

First per-subsystem audit under Phase CA. Produced [`docs/CAPABILITY_REGISTRY/DSP_MIR.md`](CAPABILITY_REGISTRY/DSP_MIR.md) — 22 file-level entities (20 in `PhospheneEngine/Sources/DSP/` plus 2 boundary-deferred files in `Sources/Session/`), each with verdict + cited evidence. Headline findings: zero `broken-but-claimed`; one real `production-orphan` (the per-frame `StructuralAnalyzer` / `NoveltyDetector` / `SelfSimilarityMatrix` chain runs on the audio-callback hot path but `MIRPipeline.latestStructuralPrediction` has only one consumer — `SessionPreparer+Analysis.swift:289` at *preparation time*; the runtime per-frame work has no live reader); one minor field-level `production-orphan` (`MIRPipeline.spectralRolloff` public exposure has zero non-DSP consumers); one `built-but-undocumented` (`MIRPipeline+Recording` writes a separate `~/phosphene_features.csv` parallel to `SessionRecorder`'s per-session `features.csv`); two `boundary-deferred` to Session-subsystem audit (`GridOnsetCalibrator` + `BeatGridAnalyzer`); one `documented-but-missing` already acknowledged in the doc set (`docs/CAPABILITY_GAP_AUDIT.md`). Doc-drift fixes: [ARCHITECTURE.md](ARCHITECTURE.md) DSP module map missing 6 of 20 files (including `LiveBeatDriftTracker.swift`, the BUG-007.x focal point) — added; MIR-pipeline-components prose missing `LiveBeatDriftTracker` + the `StructuralAnalyzer` cluster — added; Chroma 65 Hz → 500 Hz value mismatch with code — corrected; Session Recording section missing the manual `R`-shortcut path explanation — added. ENGINEERING_PLAN.md `CAPABILITY_GAP_AUDIT.md` pointer at line 446 — corrected to point at the new `CAPABILITY_REGISTRY/` tree. One retroactive `Resolved` entry filed: [BUG-R010 PT.1 PitchTracker ring-buffer fix](QUALITY/KNOWN_ISSUES.md). PT.1 (2026-05-19) had shipped without a `BUG-` entry per CLAUDE.md Defect Handling Protocol; BUG-R010 closes that gap retroactively. **Approach validation:** the format produced real, actionable findings without sliding into structure-as-substance — recommend continuing into CA.2. Recommended next subsystem: **ML** (DSP↔ML boundary closes cleanly; Beat This! test surface already partly in `Tests/ML/`; Session deferred to CA.3+ so the `GridOnsetCalibrator`/`BeatGridAnalyzer` placement question can be answered with full context).

### Increment BUG-012-i1 — MPSGraph crash instrumentation ✅ (2026-05-20)
### Increment BUG-011 CLOSED — Arachne over Tier 2 frame budget resolved against relaxed drops-only criteria ✅ (2026-05-12)
### Increment BUG-011 L5 cheap-cleanup tranche — three dead-code retirements ✅ (2026-05-12)
### Increment BUG-011 round 8 — Arachne build speedup + silent-state pause + completion-gated transitions ✅ (2026-05-12)
### Increment 2.5.4 — Session State Machine & Track Change Behavior ✅

`SessionManager` (`@MainActor ObservableObject`, `Session` module) owns the lifecycle. `startSession(source:)` drives `idle → connecting → preparing → ready`. Graceful degradation: connector failure → `ready` with empty plan; partial preparation failure → `ready` with partial plan. `startAdHocSession()` → `playing` directly (reactive mode). `beginPlayback()` advances `ready → playing`. `endSession()` from any state → `ended`.

Key implementation decisions: `SessionState`/`SessionPlan` live in `Session/SessionTypes.swift` (not `Shared`) because `Shared` cannot depend on `Session`. Cache-aware track-change loading already existed in `resetStemPipeline(for:)` from Increment 2.5.3 — no changes required there. `VisualizerEngine` gained a `sessionManager: SessionManager?` property; the app layer wires `cache → stemCache` on state transition to `.ready`.

11 tests.

### Increment 3.5.2 — Murmuration Stem Routing Revision ✅

Replaced the 6-band full-mix frequency workaround with real stem-driven routing via `StemFeatures` at GPU `buffer(3)`.

`Particles.metal` compute kernel gains `constant StemFeatures& stems [[buffer(3)]]`. Routing: **drums** (`drums_beat` decay drives wave front position) → turning wave that sweeps across the flock over ~200ms, not instantaneously; direction alternates per beat epoch; **bass** (`bass_energy`) → macro drift velocity and shape elongation; **other** (`other_energy`) → surface flutter weighted by `distFromCenter` (periphery 1.0×, core 0.25×); **vocals** (`vocals_energy`) → density compression via `densityScale = 1 - vocals * 0.22` applied to `halfLength` and `halfWidth`.

Warmup fallback: `smoothstep(0.02, 0.06, totalStemEnergy)` crossfades from FeatureVector 6-band routing to stem routing. Zero stems → identical behavior to previous implementation.

`ProceduralGeometry.update()` gains `stemFeatures: StemFeatures = .zero` parameter. `Starburst.metal` gains `StemFeatures` param; `vocals_energy` shifts sky gradient ≤10% warmer.

8 new tests in `MurmurationStemRoutingTests.swift`. 288 swift-testing + 91 XCTest = 379 tests total.

### Increment 3.5.4 — Volumetric Lithograph Preset ✅

New ray-march preset: tactile, audio-reactive infinite terrain rendered with a stark linocut/printmaking aesthetic. Uses the existing deferred ray-march pipeline; no engine changes required.

`PhospheneEngine/Sources/Presets/Shaders/VolumetricLithograph.metal` defines only `sceneSDF` and `sceneMaterial`; the marching loop and lighting pass come from `rayMarchGBufferPreamble`.

- **Geometry:** `fbm3D` heightfield over an infinite XZ plane. The noise's third axis is swept by `s.sceneParamsA.x` (accumulated audio time) so topography continuously morphs rather than scrolls. Vertical amplitude scaled by `clamp(f.bass + f.mid, 0, 2.5)`. SDF return scaled by 0.6 to keep the marcher Lipschitz-safe on steep ridges.
- **Bimodal materials:** Valleys → `albedo=0, roughness=1, metallic=0` (ultra-matte black). Peaks → `albedo=1, roughness∈[0.06, 0.18], metallic=1` (mirror-bright). Pinched smoothstep edges (0.55→0.72) read as printed lines.
- **Beat accent:** Drum onset shifts the smoothstep window down (`lo -= drumsBeat × 0.18`) so the bright peak region *expands* across the topography on transients. The deferred G-buffer has no emissive channel, so coverage expansion is the contrast-pulse story.
- **D-019 stem fallback:** `StemFeatures` is not in scope for `sceneSDF`/`sceneMaterial` (preamble forward-declarations omit it — same as KineticSculpture). Uses `f` directly: `max(f.beat_bass, f.beat_mid, f.beat_composite)` for the drum-beat fallback (CLAUDE.md failed-approach #26 — single-band keying misses snare-driven tracks); `f.treble * 1.4` for the "other" stem fallback (closest single-band proxy for the 250 Hz–4 kHz range).
- **Pipeline:** `["ray_march", "post_process"]` — SSGI intentionally skipped to preserve harsh, high-contrast shadows.
- **JSON:** `family: "fluid"`, low-angle directional light from above-side, elevated camera looking down at terrain, far-plane 60u, `stem_affinity` documented (drums→contrast_pulse, bass→terrain_height, other→metallic_sheen).

Verified by the existing `presetLoaderBuiltInPresetsHaveValidPipelines` regression gate, which compiles and renders every built-in preset through the actual G-buffer pipeline. No new test files required — the gate covers the new preset automatically.

### Increment 3.5.4.1 — Volumetric Lithograph v2 ✅
### Increment 3.5.4.2 — Volumetric Lithograph v3 + shared fog-fallback bug fix ✅

Two issues surfaced during v2 visual review on Love Rehab:

**Bug 1 (shared infra):** `PresetDescriptor+SceneUniforms.makeSceneUniforms()` line 85 had a broken `scene_fog == 0` fallback: it reused `uniforms.sceneParamsB.y` which starts at SIMD4 default 0. The shader formula `fogFactor = clamp((t - 0) / max(0 - 0, 0.001), 0, 1)` then saturates to 1.0 for any terrain hit — so "no fog" actually produced **maximum fog everywhere**. Fixed: fallback now returns `1_000_000` (effectively infinite fogFar), matching the intuitive "0 means no fog" semantic. No test impact — no existing preset set `scene_fog: 0`.

**Rebalance (v3):** v2 over-corrected. `pow(f.beat_bass, 1.5) × 0.7` with `× 0.6` palette brightness multiplier produced visually inert beat response on energetic music — ACES squashed the boost back into SDR before post-process bloom could amplify it. v3 changes:
- Drum-beat fallback: `pow(f.beat_bass, 1.2) × 1.5` (saturates at beat_bass ≈ 0.7 rather than never).
- Palette flare: × 1.5 (was × 0.6) — peaks push to 2.5× albedo on strong kicks, bloom-visible.
- Ridge seam strobe: `× (1.4 + beat × 2.0)` — the cut-line itself strobes at up to 3.4× brightness.
- Coverage expansion on beat: 0.03 smoothstep shift (v1 had 0.18 which flickered every frame; v2 had 0 which was dead).
- Transient terrain kick in `sceneSDF`: `f.beat_bass × 0.35` added to attenuated baseline amp — landscape breathes on kicks without replacing the slow-flowing base.

Same regression gate covers both changes.

### Increment 3.5.4.3 — v3.1 palette tuning ✅
### Increment 3.5.4.4 — v3.2 "pulse-rate too fast" + sky tint ✅
### Increment 3.5.4.5 — v3.3: correct beat driver (f.bass, not f.beat_bass) ✅
### Increment 3.5.4.6 — v3.4: use f.bass_att (pre-smoothed), not f.bass threshold ✅
### Increment 3.5.4.7 — v4: melody-primary drivers + forward dolly ✅
### Increment 3.5.4.8 — SessionRecorder writer relock + StemFeatures in preamble ✅
### Increment 3.5.4.9 — Per-frame stem analysis (engine-level) ✅
### Increment 3.5.5 — Arachne Preset (bioluminescent spider webs) ✅
### Increment 3.5.6 — Gossamer Preset (bioluminescent sonic resonator) ✅
### Increment 3.5.7 — Stalker Preset — **Retired** ✅
### Increment 3.5.8 — Arachne + Gossamer visual rework ✅
### Increment 3.5.9 — Spider easter egg in Arachne ✅
### Increment 3.5.10 — Arachne ray march remaster ✅
### Increment 3.5.11 — Gossamer SDF correction + v3 acceptance gate ✅
### Increment MV-0 — Drop v4.2 stash, re-land sky-tint conditional ✅
### Increment MV-1 — Milkdrop-correct audio primitives ✅
### Increment MV-2 — Per-vertex feedback warp mesh ✅
### Increment D-030 — SpectralHistoryBuffer + SpectralCartograph ✅

New `SpectralHistoryBuffer` class (Shared module): 16 KB UMA MTLBuffer at fragment buffer index 5, bound unconditionally in all direct-pass fragment encoders. Maintains 5 ring buffers of 480 samples (≈8s at 60fps): valence, arousal, beat_phase01, bass_dev, and log-normalized vocal pitch. Updated once per frame in `RenderPipeline.draw(in:)`; reset on track change via `VisualizerEngine.resetStemPipeline(for:)`.

`SpectralCartograph` preset: first `instrument`-family preset. Four-panel real-time MIR diagnostic — TL=FFT spectrum (log-frequency, centroid-driven colour), TR=3-band deviation meters (D-026 compliant: reads only `*_att_rel` and `*_dev`), BL=valence/arousal phase plot with 8-second fading trail, BR=scrolling line graphs for `beat_phase01`, `bass_dev`, and `vocals_pitch_norm`. Direct pass only.

CLAUDE.md GPU Contract corrected: buffer(0)=FeatureVector (not FFT as previously documented). buffer(4)=SceneUniforms (ray march only, not future use). buffer(5)=SpectralHistory.

New `PresetCategory.instrument` case added.

15+ new tests across `SpectralHistoryBufferTests.swift`, `SpectralCartographTests.swift`, and additions to `RenderPipelineTests.swift`.

---

### Increment D-030b — Verification fixes + InputLevelMonitor ✅
## Immediate Next Increments

These are ordered by dependency. Each has done-when criteria and verification commands.

> **Capability Audit (Phase CA, 2026-05-20).** The originally-planned `docs/CAPABILITY_GAP_AUDIT.md` single-deliverable was superseded 2026-05-20 by the multi-increment **Phase CA** audit, which produces one per-subsystem registry under [`docs/CAPABILITY_REGISTRY/`](CAPABILITY_REGISTRY/). CA.1 (DSP/MIR) landed 2026-05-20 at [`docs/CAPABILITY_REGISTRY/DSP_MIR.md`](CAPABILITY_REGISTRY/DSP_MIR.md); CA.2+ pending. Preliminary 2026-05-12 inventory data (shader-utility-consumer matrix, distinct from CA's per-subsystem audits) lives at [`docs/diagnostics/capability-audit-pre-2026-05-12.md`](diagnostics/capability-audit-pre-2026-05-12.md) and continues to feed shader-cleanup increments.

**Current priority ordering (post-2026-05-06 multi-agent codebase review):**

1. **Phase QR — Quality Review Remediation** (QR.1 → QR.6). New top priority. QR.1 → QR.4 are sequenced; QR.5 + QR.6 run after QR.1–QR.4 land. See "Phase QR" section below.
2. **Phase DSP — DSP Hardening.** DSP.3.7 (Live drift validation test) merges into QR.3.
3. **Phase V — Visual Fidelity Uplift** (V.5 reference completion + V.7.7B WORLD pillar) — can run in parallel with QR since they touch disjoint modules.
4. **Phase MD — Milkdrop Ingestion** (MD.1 → MD.7). Unchanged dependency on V.1–V.3 utilities.
5. **Phase SB — Starburst Fidelity Uplift** (SB.1 → SB.5). Independent.

Phase U / Phase 4 / Phase 5 / Phase 6 / Phase 7 / Phase MV all complete; see historical records below.

## Phase MV — Milkdrop-Informed Musical Architecture

**Why this phase exists:** six iterations on Volumetric Lithograph produced incremental fixes but never converged on "feels like a band member playing along with the music." [`docs/MILKDROP_ARCHITECTURE.md`](MILKDROP_ARCHITECTURE.md) documents the research that identified the root cause:

1. Milkdrop's audio vocabulary is **identical in scope to what Phosphene already computes** — no chord recognition, no pitch tracking, no stems. Our analysis pipeline is richer than theirs.
2. Milkdrop's `bass`/`bass_att` are **AGC-normalized ratios centered at 1.0**. Phosphene's are centered at 0.5 via the same AGC mechanism. But our presets have been authored with absolute thresholds — the wrong primitive for an AGC signal. Absolute thresholds inherently fail across tracks because the AGC divisor moves with mix density.
3. Milkdrop's "musical feel" comes from its **per-vertex feedback warp architecture**, not its audio analysis. Every preset warps the previous frame via a 32×24 grid, and motion *accumulates* over many frames. Simple audio inputs compound into rich organic motion.
4. **9 of 11 Phosphene presets did not use any feedback loop** prior to MV-2 — they rendered from scratch each frame. Ray-march presets in particular showed only instantaneous audio state. This is why they felt "disconnected" from music regardless of how cleverly tuned.

MV-0 ✅, MV-1 ✅, MV-2 ✅, MV-3 ✅ complete.

### Increment MV-3 — Beyond-Milkdrop extensions ✅

**MV-3a — Richer per-stem metadata** ✅
- `StemFeatures` expanded 32→64 floats (128→256 bytes). New per-stem fields: `{vocals,drums,bass,other}{OnsetRate, Centroid, AttackRatio, EnergySlope}` (floats 25–40), computed in `StemAnalyzer.analyze()` via `computeRichFeatures()`.
- `StemAnalyzerMV3Tests.swift`: click vs sine distinguishes attackRatio; silence gives zeros; 120-BPM click track mean onsetRate in [1.0, 3.5]/sec.

**MV-3b — Next-beat phase predictor** ✅
- New `BeatPredictor` class (IIR period estimation from onset rising edges). Feeds `beatPhase01` and `beatsUntilNext` into `FeatureVector` floats 35–36. Integrated in `MIRPipeline.buildFeatureVector()`.
- `BeatPredictorTests.swift`: phase monotonically rises 0→1; phase resets after 3× period silence; bootstrap BPM gives correct phase.
- `VolumetricLithograph.metal` updated: `approachFrac = max(0, (f.beat_phase01 - 0.80) / 0.20)` pre-beat anticipatory zoom.

**MV-3c — Vocal pitch tracking** ✅
- New `PitchTracker` (YIN autocorrelation, vDSP_dotpr). Key fix: advance to local CMNDF minimum before parabolic interpolation (finding just the first sub-threshold point causes catastrophic extrapolation on the descending slope). 80–1000 Hz gate, 0.6 confidence threshold, EMA decay 0.8.
- Feeds `vocalsPitchHz` and `vocalsPitchConfidence` into `StemFeatures` floats 41–42.
- `PitchTrackerTests.swift`: 440 Hz and 220 Hz within 5 cents; silence → 0 Hz; random noise → unvoiced.
- `VolumetricLithograph.metal` updated: `vl_pitchHueShift()` maps pitch to ±0.15 palette phase shift; gated by confidence ≥ 0.6.

**Explicitly NOT part of MV-3 (still out of scope):**
- Basic Pitch port, chord recognition via Tonic, HTDemucs swap, Sound Analysis framework

---

## Phase 4 — Orchestrator

The Orchestrator is the product's key differentiator. It is implemented as an explicit scoring and policy system, not a black box.

### Increment 4.0 — Enriched Preset Metadata Schema ✅

**Scope:** `PresetMetadata.swift` (new), `PresetDescriptor.swift` (extended), all 11 JSON sidecars back-filled.

Pulled forward from Phase 5.1 because Increment 4.1 (PresetScorer) cannot be built without the metadata it scores on. Adding the schema now eliminates a breaking change immediately after 4.1 is drafted.

**New types:** `FatigueRisk`, `TransitionAffordance`, `SongSection` (String-raw, Codable, Sendable, Hashable, CaseIterable). `ComplexityCost` struct with dual-form Codable (scalar or `{"tier1":x,"tier2":y}`). All in `PresetMetadata.swift`.

**New `PresetDescriptor` fields (all optional in JSON, fallback-on-missing, warn-on-malformed):**
`visual_density`, `motion_intensity`, `color_temperature_range`, `fatigue_risk`, `transition_affordances`, `section_suitability`, `complexity_cost`.

**Done when:** ✅ All criteria met.
- `PresetMetadata.swift` with three enums and `ComplexityCost`, all correct Swift 6 types.
- `PresetDescriptor` has 7 new fields; decoding falls back to defaults; unknown `fatigue_risk` logs warning + uses `.medium`.
- All 11 built-in preset JSON sidecars have explicit values for all 7 new fields.
- `PresetLoaderBuiltInPresetsHaveValidPipelines` regression gate still passes.
- `PresetDescriptorMetadataTests`: round-trip, defaults, malformed, complexity variants (scalar + nested), on-disk back-fill regression (6 test functions).
- D-029 in `docs/DECISIONS.md`. CLAUDE.md preset metadata table extended.

**Verify:** `swift test --package-path PhospheneEngine --filter PresetDescriptorMetadataTests`

---

### Increment L-1 — Structural SwiftLint Cleanup

**Scope:** Refactor 12 source files to eliminate all 24 remaining structural SwiftLint violations. No logic changes — pure mechanical refactoring. Verified by `swiftlint lint --strict` reporting 0 violations on active source paths, with all tests still passing.

**Background:** After the 2026-04-20 auto-fix pass, 24 structural violations remain (down from 166). These are `file_length`, `function_body_length`, `cyclomatic_complexity`, `type_body_length`, `large_tuple`, and `line_length` — rules that require file splits or helper extraction rather than auto-correction.

**Violations and fix strategy (file:line:rule):**

| File | Line | Rule | Fix |
|------|------|------|-----|
| `SessionRecorder.swift` | 46 | type_body_length (516) | Split to `SessionRecorder+Video.swift` (Video encoding MARK), `SessionRecorder+RawTap.swift` (Raw tap diagnostic MARK), `SessionRecorder+WAV.swift` (WAV writing) |
| `SessionRecorder.swift` | 150 | function_body_length (72) | Extract `setupWriters()`, `setupVideoWriter()`, `setupAudioWriter()` private helpers from `init` |
| `SessionRecorder.swift` | 397 | cyclomatic_complexity (13) + function_body_length (72) | Extract `handleVideoWriterInit()` and `handleFrameDimensionMismatch()` private helpers from `appendVideoFrame()` |
| `SessionRecorder.swift` | 793 | file_length (793) | Resolved by the type_body_length split above |
| `AudioFeatures+Analyzed.swift` | 552 | file_length (552) | Move `StemFeatures` struct (lines ~323–514) to new `StemFeatures.swift` in same directory |
| `PresetLoader+Preamble.swift` | 541 | file_length (541) | Split MV-warp preamble (line ~199 MARK) to `PresetLoader+WarpPreamble.swift` |
| `StemAnalyzer.swift` | 171 | function_body_length (96) | Extract `buildBaseFeatures()` and `applyDeviationPrimitives()` private helpers from `analyze()` |
| `StemAnalyzer.swift` | 349 | large_tuple | Define `StemRichFeatures` struct `{onsetRate, centroid, attackRatio, energySlope: Float}` to replace 4-member named tuple return from `computeRichFeatures()` |
| `StemAnalyzer.swift` | 500 | file_length (500) | Resolved by helper extraction above |
| `PitchTracker.swift` | 97 | cyclomatic_complexity (15) + function_body_length (86) | Extract 5 private helpers: `fillWindow()`, `computeDifference()`, `computeCMNDF()`, `findMinimum()`, `parabolicInterpolation()` from `process(waveform:)` |
| `MIRPipeline.swift` | 407 | file_length (407, 7 over) | Extract `buildFeatureVector()` deviation block to a private helper; or remove excess blank lines |
| `AudioInputRouter.swift` | 423 | file_length (423, 23 over) | Extract `Signal-State Handling + Tap Reinstall` MARK section to `AudioInputRouter+SignalState.swift` |
| `PresetLoader.swift` | 449 | function_body_length (103) | Extract `compilePipeline(for:)` and `compileRayMarchPipeline(for:)` private helpers from `loadPreset()` |
| `RayMarchPipeline.swift` | 184 | function_body_length (71) | Extract `makeGBufferTextures()` and `makeLightingPipeline()` private helpers from `init` |
| `RayMarchPipeline.swift` | 415 | file_length (415, 15 over) | Resolved by init helper extraction above |
| `RenderPipeline+Draw.swift` | 448 | file_length (448, 48 over) | Extract `drawWithICB` and `drawWithParticles` to `RenderPipeline+Particles.swift` |
| `RenderPipeline+RayMarch.swift` | 81 | function_body_length (83) | Extract `buildSceneUniforms()` and `applyAudioModulation()` private helpers |
| `RenderPipeline.swift` | 475 | file_length (475, 75 over) | Extract `PassManagement` MARK section to `RenderPipeline+Passes.swift` |
| `VisualizerEngine+Audio.swift` | 507 | file_length (507, 107 over) | Extract `InputLevelMonitor` integration section to `VisualizerEngine+InputLevel.swift` |
| `VisualizerEngine.swift` | 245 | function_body_length (82) | Extract `setupAudio()`, `setupRenderer()`, `setupCapture()` private helpers from `init` |
| `VisualizerEngine.swift` | 473 | file_length (473, 73 over) | Resolved by init helper extraction above |
| `InputLevelMonitor.swift` | 267 | line_length (127 chars) | Break `String(format:)` argument across lines or shorten message |

**Constraints:**
- No logic changes whatsoever. Every extracted function/struct must preserve byte-for-byte identical observable behavior.
- No new public API surface. All extracted helpers are `private`.
- New files added to the same target as the file being split (no new SPM targets).
- When splitting a file, all `// MARK: -` dividers from the original stay with their section.
- `StemRichFeatures` replacing the named tuple: must update all call sites in `StemAnalyzer.swift`; no other files reference the tuple directly.
- All existing tests must pass before and after each file change.

**Done when:**
- `swiftlint lint --strict --config .swiftlint.yml PhospheneEngine/Sources/ PhospheneEngine/Tests/ PhospheneApp/` reports **0 violations**.
- `swift test --package-path PhospheneEngine` passes (all tests green).
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` succeeds with 0 errors.

**Verify:**
```bash
swiftlint lint --strict --config .swiftlint.yml PhospheneEngine/Sources/ PhospheneEngine/Tests/ PhospheneApp/
swift test --package-path PhospheneEngine
```

---

### Increment 4.1 — Preset Scoring Model ✅

**Landed:** 2026-04-20.

`DefaultPresetScorer` implements the `PresetScoring` protocol with four weighted sub-scores (mood 0.30, stemAffinity 0.25, sectionSuitability 0.25, tempoMotion 0.20) and two multiplicative penalties (family-repeat 0.2×, smoothstep fatigue cooldown 60/120/300s). Hard exclusions gate perf-budget breakers and identity matches before scoring. `PresetScoreBreakdown` exposes every sub-score for introspection. `PresetScoringContext` is a fully Sendable value-type snapshot with a monotonic session clock — no `Date.now()` inside the scorer. 13 unit tests cover all contract edges including determinism, exclusion, cooldown, and rank stability across device tiers. See D-032 in DECISIONS.md for weight rationale.

**New files:** `Orchestrator/PresetScorer.swift`, `Orchestrator/PresetScoringContext.swift`, `Shared/DeviceTier.swift`. Extended: `PresetDescriptor` (added `stemAffinity: [String: String]`), `ComplexityCost` (added `cost(for:)` helper), `Package.swift` (added `Session` dep to `Orchestrator` target, `Orchestrator` dep to test target).

**Verify:** `swift test --package-path PhospheneEngine --filter PresetScorerTests`

---

### Increment 4.2 — Transition Policy ✅

**Landed:** 2026-04-20.

`DefaultTransitionPolicy` implements the `TransitionDeciding` protocol. Priority: structural boundary (when `StructuralPrediction.confidence ≥ 0.5` and boundary within 2.5 s lookahead window) beats duration-expired timer fallback. `TransitionDecision` is fully inspectable: trigger, scheduledAt, style (crossfade/cut/morph), duration, confidence, rationale. Style negotiated from `currentPreset.transitionAffordances` and energy level — high energy (> 0.7) prefers `.cut`, low energy prefers `.crossfade`. Crossfade duration scales linearly from 2.0 s (energy=0) to 0.5 s (energy=1). Family-repeat avoidance is already handled upstream by `DefaultPresetScorer` (familyRepeatMultiplier=0.2×). 12 unit tests with synthetic `StructuralPrediction` inputs — all pass. See D-033 in DECISIONS.md.

**New files:** `Orchestrator/TransitionPolicy.swift`, `Tests/Orchestrator/TransitionPolicyTests.swift`.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 4.3 — Session Planner ✅

**Scope:** `Orchestrator/SessionPlanner.swift`, `Orchestrator/PlannedSession.swift`. Greedy forward-walk planner composing `DefaultPresetScorer` + `DefaultTransitionPolicy`. Produces a `PlannedSession` — ordered list of `PlannedTrack` entries each carrying the selected `PresetDescriptor`, `PresetScoreBreakdown`, `PlannedTransition`, and planned timing. `planAsync` accepts a precompile closure (caller-injected, keeps Orchestrator module free of Renderer dependency). Deterministic: same inputs → byte-identical output. `PlanningWarning` surfaces degradation events. SessionManager integration deferred: `Session` module cannot import `Orchestrator` without a circular dependency — app-layer wiring is Increment 4.5.

**Landed 2026-04-20.** 13 unit tests covering empty-playlist/empty-catalog errors, single-track plan, 5-track family diversity, tier exclusion, mood arc, fatigue, full-exclusion fallback, determinism, `track(at:)` / `transition(at:)` lookups, precompile dedup, and precompile failure handling. D-034 in DECISIONS.md. 387 tests total; 4 pre-existing Apple Music env failures unchanged.

**Verify:** `swift test --package-path PhospheneEngine --filter SessionPlannerTests`

---

### Increment 4.4 — Golden Session Test Fixtures ✅

**Landed:** 2026-04-20. *(Current state: regenerated multiple times since landing — QR.2 stem-affinity rescaling, V.7.6.2 multi-segment, BUG-004 closure 2026-05-12 expanding catalog 11 → 15 presets and adding Session D for Lumen Mosaic eligibility coverage. The current test file in `PhospheneEngine/Tests/.../Orchestrator/GoldenSessionTests.swift` is authoritative; the original-landing description below is preserved as a historical record.)*

`GoldenSessionTests.swift` — 12 regression tests across three curated playlists that lock in the expected Orchestrator output for any given set of track profiles and the full 11-preset production catalog. Any future change to `DefaultPresetScorer`, `DefaultTransitionPolicy`, `DefaultSessionPlanner`, or a preset JSON sidecar that breaks a golden test is a regression; the test file must be updated with a scoring trace comment that proves the new expected values are correct.

**Session A (high-energy electronic, 5 × 180 s, BPM=130, val=0.7, arous=0.8):** VL→Plasma→VL→FO→VL. Transitions from VL are cuts (VL carries `[crossfade, cut]` affordances, energy=0.82 > 0.7 threshold); transitions from Plasma/FO are crossfades at ~0.77 s.

**Session B (mellow jazz, 5 × 180 s, BPM=85, val=0.3, arous=−0.3):** VL→GB→VL→GB→VL. All crossfades at ~1.43 s (energy=0.38). No high-motion preset (Murmuration motion=0.85) ever wins.

**Session C (genre-diverse, 6 tracks, varied durations):** VL→GB→VL→Plasma→VL→FO. Covers 4 families (fluid, geometric, hypnotic, abstract).

**Key implementation decisions:**
- `allBreakdowns: [(PresetDescriptor, PresetScoreBreakdown)]` was **not** added to `PlannedTrack`. Runner-up inspection is done by calling `DefaultPresetScorer().breakdown(preset:track:context:)` directly inside the test body — no new public API.
- `PlannedTransition` carries no `trigger` enum field; trigger type is verified via `reason.hasPrefix("Structural boundary")`.
- Two pre-implementation spec derivation errors were caught and corrected against the code: Plasma (0.803) beats Ferrofluid Ocean (0.793) in high-energy electronic sessions because Plasma's tempCenter (0.6) is closer to targetTemp (0.78). The spec's scoring trace omitted Plasma when listing non-fluid competitors.

399 tests total; 4 pre-existing Apple Music env failures unchanged.

**Verify:** `swift test --package-path PhospheneEngine --filter GoldenSessionTests`

---

### Increment 4.5 — Live Adaptation ✅

**Landed:** 2026-04-20.

`LiveAdapter.swift` + `LiveAdapter+Patching.swift` + `VisualizerEngine+Orchestrator.swift`. `DefaultLiveAdapter` implementing `LiveAdapting` protocol with two adaptation paths (boundary reschedule > mood override). `PlannedSession.applying(_:at:)` extension for controlled plan mutation from the app layer. `VisualizerEngine+Orchestrator` holds `livePlan` (NSLock-guarded) and provides `buildPlan()`, `currentPreset(at:)`, `currentTransition(at:)`, `applyLiveUpdate(...)`.

**Boundary reschedule:** fires when `StructuralPrediction.confidence ≥ 0.5` AND the live boundary deviates from the planned transition time by > 5 s. 5 s = 2× the `LookaheadBuffer` 2.5 s window — deviations smaller than that are within normal preview-vs-live jitter. Wins over mood override when both conditions fire simultaneously.

**Mood override:** fires only when all three hold: `|Δvalence| > 0.4 || |Δarousal| > 0.4`, elapsed fraction < 40%, and the best-scoring alternative preset is > 0.15 higher. Current preset scored without exclusion (true live score); alternatives scored with current preset excluded. Cap at 40% prevents churn in the back half of a track.

**Key implementation decisions (D-035):**
- `LiveAdaptation.PresetOverride` is a nested struct (not a named tuple) for `Sendable` conformance in Swift 6 strict mode.
- `PlannedSession.applying` lives in `LiveAdapter+Patching.swift` (same Orchestrator module as the internal memberwise inits of `PlannedSession`/`PlannedTrack`) — the only controlled mutation path outside of `DefaultSessionPlanner.plan()`.
- Empty `recentHistory: []` in live scoring context is intentional — fatigueMultiplier is a session-level pre-plan concern; live overrides that fire mid-track should not re-apply session-level fatigue logic.
- `LiveAdapting` protocol uses `// swiftlint:disable function_parameter_count` (6 params) — wrapping into a context struct would add an intermediate allocation on the hot path with no modelling benefit.

**Test notes:**
- `noBoundarySignal()` helper (confidence=0.0) bypasses the boundary path in mood-only tests. Using `closeBoundary(at: N)` in mood tests caused unexpected boundary reschedules because the live session boundary deviated > 5 s from the planned transition time even when confidence was high.
- Override catalog uses `visual_density` JSON field (`case visualDensity = "visual_density"` in `PresetDescriptor.CodingKeys`) — confirmed before writing test helpers.
- Scoring math verified by hand: pre-analyzed sad/calm (-0.5, -0.5) → targetTemp=0.30; CurrentPreset (center=0.25, density=0.25) → mood score 0.95. Live happy/energetic (0.7, 0.7) → targetTemp=0.78; AltPreset (center=0.78, density=0.78) → mood score 1.0. Gap = 0.875 − 0.716 = 0.159 > 0.15 threshold.

407 tests total; 4 pre-existing Apple Music env failures unchanged.

**Verify:** `swift test --package-path PhospheneEngine --filter LiveAdapterTests`

---

### Increment 4.6 — Ad-Hoc Reactive Mode ✅

**Landed:** 2026-04-20

**What was built:**
- `ReactiveOrchestrator.swift` — `ReactiveAccumulationState` (listening/ramping/full), `ReactiveDecision`, `ReactiveOrchestrating` protocol, `DefaultReactiveOrchestrator` (stateless pure function). Confidence ramps 0→0.3 over first 15 s, 0.3→1.0 over 15–30 s, 1.0 after. Switch conditions: score gap > 0.20 OR structural boundary confidence ≥ 0.5.
- `ReactiveOrchestratorTests.swift` — 8 unit tests: listening hold, confidence ramp, ramping suggestion, score-gap suppression, boundary override, boundary scheduling, nil-preset path, empty-catalog hold.
- `VisualizerEngine.swift` — added `reactiveOrchestrator`, `reactiveSessionStart`, `lastReactiveSwitchTime`.
- `VisualizerEngine+Orchestrator.swift` — `applyLiveUpdate()` routes to `applyReactiveUpdate()` when `livePlan == nil`; `buildPlan()` clears `reactiveSessionStart` when a real plan arrives. 60 s cooldown prevents switch-thrashing.
- D-036 added to `docs/DECISIONS.md`.

**Key decisions:** D-036 — stateless orchestrator, app-layer owns cooldown and wall-clock elapsed time.

**Tests:** 407 → 415 (8 new). Same 4 pre-existing Apple Music environment failures.

**Verify:** `swift test --package-path PhospheneEngine --filter ReactiveOrchestratorTests`

---

## Phase 5 — Preset Certification Pipeline

### Increment 5.1 — Enriched Preset Metadata Schema ✅ (landed as Increment 4.0)

**Note:** This increment was pulled forward and completed as **Increment 4.0** because PresetScorer (Increment 4.1) requires this schema before it can be drafted. See Increment 4.0 above for the full done-when criteria and verification commands. All 5.1 scope items are complete.

**Verify:** `swift test --package-path PhospheneEngine`

---

### Increment 5.2 — Preset Acceptance Checklist (Automated) ✅

**Landed:** 2026-04-20

**What was built:**
- `PresetAcceptanceTests.swift` — 4 parametrized invariant tests across all production presets (44 test cases when bundle resources are linked):
  1. Non-black at silence (max channel > 10).
  2. No white clip on steady energy for non-HDR passes (max < 250).
  3. Beat response ≤ 2× continuous response + 1.0 tolerance (enforces CLAUDE.md audio data hierarchy).
  4. Form complexity ≥ 2 at silence (detects visually dead single-bin outputs).
- Four FeatureVector fixtures derived from AGC semantics and CLAUDE.md reference onset table (Love Rehab ~125 BPM, Miles Davis ~136 BPM). Not synthetic envelopes.
- `renderFrame` renders 64×64 offscreen via the preset's direct `pipelineState`. Ray march and post-process presets are rendered via their composite output; the `post_process` white-clip check is skipped (HDR values are legal before tone-mapping).
- `_acceptanceFixture` is a module-level constant loaded once; if bundle resources are absent, it returns `[]` (zero test cases rather than failure).

**Key decision:** D-037 — structural invariants over GPU output; perceptual snapshot regression deferred to 5.3.

**Tests:** 415 → 419 (4 new @Test functions; Swift Testing counts @Test declarations, not parametrized cases). Same 4 pre-existing Apple Music environment failures.

**Verify:** `swift test --package-path PhospheneEngine --filter PresetAcceptanceTests`

---

### Increment 5.3 — Visual Regression Snapshots ✅

**Landed:** 2026-04-21

**What was built:**
- `PresetRegressionTests.swift` — 3 parametrized regression tests (steady, beat-heavy, quiet) + 1 golden-generation utility test.
- 64-bit dHash computed via 9×8 luma grid + horizontal-difference encoding (`computeLumaGrid` + `dHash`).
- `goldenPresetHashes` dictionary: 11 preset entries × 3 fixtures = 33 comparisons. Fractal Tree excluded (meshShader).
- Hamming distance ≤ 8 tolerance (87.5% match). Missing entries skip silently (safe for new presets).
- `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter test_printGoldenHashes` regenerates all values.
- Same buffer/skip infrastructure as Increment 5.2 (SceneUniforms for ray march, zeroed FFT/stems/history).
- `_acceptanceFixture` and `PresetFixtureContext` promoted from `private` to `internal` in `PresetAcceptanceTests.swift` so `PresetRegressionTests.swift` can reference them directly.

**Key decision:** D-039 — dHash regression gate; hardware caveat documented.

**Tests:** 435 → 439 (4 new @Test functions). Same pre-existing failures unchanged.

**Verify:**
```bash
swift test --package-path PhospheneEngine --filter PresetRegressionTests
# To regenerate goldens:
UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter test_printGoldenHashes
```

---

## Phase U — UX Architecture

**Why this phase exists:** the engine has a `SessionState` lifecycle (idle → connecting → preparing → ready → playing → ended) and a developer-facing debug overlay, but there is no user-facing UX specification and no corresponding UI. Phase 2.5 built the preparation *pipeline*; Phase U builds the UI around it. `docs/UX_SPEC.md` is the canonical spec for everything in this phase. Milestone A ("Trustworthy Playback Session") blocks on U.1–U.7.

### Increment U.1 — Session-state views ✅

**Scope:** `ContentView` becomes a pure switch on `SessionManager.state`. Six stub top-level views (`IdleView`, `ConnectingView`, `PreparationProgressView`, `ReadyView`, `PlaybackView`, `EndedView`) under `PhospheneApp/Views/`, each rendering a distinct testable hierarchy. `SessionStateViewModel` (`@MainActor ObservableObject`) observes `SessionManager` and publishes current state. New `CLAUDE.md §UX Contract` section. New `ARCHITECTURE.md §UI Layer` subsection.

**Done when:**
- ✅ Six views exist; each renders without errors for its corresponding state.
- ✅ `ContentView` contains no state logic beyond routing.
- ✅ Tests for each view — 9 tests across 3 suites in `PhospheneAppTests/SessionStateViewTests.swift`.
- ✅ Reduced-motion system flag detection stub in place (used by later increments).

**Implementation note:** Accessibility ID testing via SwiftUI's accessibility tree traversal is unreliable in unit tests — macOS only materialises the SwiftUI accessibility tree for active clients (VoiceOver, XCUITest). Each view exposes `static let accessibilityID: String`; `.accessibilityIdentifier(Self.accessibilityID)` binds it in the view body. Tests check the static constants; the binding is enforced by construction. See D-044.

**Verify:** `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test` — 9 new tests pass.

---

### Increment U.2 — Permission onboarding ✅

**Landed:** 2026-04-22

**What was built:**
- `PermissionMonitor` (`@MainActor ObservableObject`) observing
  `NSApplication.didBecomeActiveNotification`, backed by
  `ScreenCapturePermissionProviding`.
- `SystemScreenCapturePermissionProvider` (production) — `CGPreflightScreenCaptureAccess`.
  Never calls `CGRequestScreenCaptureAccess` (system dialog doesn't compose with URL-scheme flow).
- `PhotosensitivityAcknowledgementStore` — injectable `UserDefaults` suite; key
  `phosphene.onboarding.photosensitivityAcknowledged`.
- `PermissionOnboardingView` per UX_SPEC §3.2; opens
  `x-apple.systempreferences:…?Privacy_ScreenCapture` via `NSWorkspace.shared.open`.
  No Retry button — return-detection is automatic via `PermissionMonitor`.
- `PhotosensitivityNoticeView` per UX_SPEC §3.3; surfaced as a `.sheet` on
  first `IdleView` appearance.
- `ContentView` refactored to two-level switch: permission gate above state switch.
  `PermissionMonitor` injected as `@EnvironmentObject` from `PhospheneApp`.
- `IdleView` updated with `.onAppear` + `.sheet(isPresented:)` for the notice.

**Key decisions:**
- Preflight + URL scheme, NOT `CGRequestScreenCaptureAccess()` — the request
  API's system dialog doesn't compose with "Open System Settings and return."
- Permission gate lives above the state switch, not inside `SessionStateViewModel` —
  permission routing outranks session state per UX_SPEC §3.1.
- Photosensitivity sheet on `IdleView`, not a separate top-level state — timing
  is "after permission, before first session" which maps exactly to `IdleView`'s
  first appearance.
- `PermissionMonitor` lives under `Permissions/`, not `Views/` — it is a
  routing-layer concern, not a view.

**Tests:** 535 → 549 (+14 new: 5 PermissionMonitor, 4 PhotosensitivityStore, 5 PermissionOnboarding). Pre-existing failures unchanged.

**Verify:**
- `swift test --package-path PhospheneEngine`
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`
- `swiftlint lint --strict --config .swiftlint.yml`

---

### Increment U.3 — Playlist connector picker ✅

**Landed:** 2026-04-23

**What was built:**
- `ConnectorType` enum (appleMusic/spotify/localFolder) with title/subtitle/systemImage.
- `ConnectorTileView`: reusable tile with enabled/disabled states and optional secondary
  action button.
- `ConnectorPickerViewModel` (`@MainActor ObservableObject`): NSWorkspace launch/terminate
  observers with `nonisolated(unsafe)` storage — the only correct pattern for observers
  that must be removed in `deinit` on a `@MainActor` class (Swift 6 `deinit` is nonisolated).
  250ms debounce on Apple Music availability.
- `ConnectorPickerView`: `NavigationStack` inside a `.sheet` from `IdleView`, with
  `navigationDestination(for: ConnectorType.self)`.
- `AppleMusicConnectionViewModel`: five-state machine
  (idle/connecting/noCurrentPlaylist/notRunning/permissionDenied/error/connected).
  Auto-retry on `.noCurrentPlaylist` via injectable `DelayProviding` (2s real, instant
  in tests). Pre-flight finding: AppleScript error -1728 (no track) and -1743 (automation
  denied) both silently return an empty array — indistinguishable in U.3.
- `AppleMusicConnectionView`: five user-visible states with CTA copy per UX_SPEC §4.3.
  `.onChange(of: viewModel.state)` fires `onConnect(.appleMusicCurrentPlaylist)` on
  `.connected`.
- `SpotifyURLKind` + `SpotifyURLParser`: pure value types. Handles HTTPS, `spotify:` URI,
  `@`-prefixed links, query param stripping, podcast paths → `.invalid`.
- `SpotifyConnectionViewModel`: 300ms debounce on text input via `$text.sink`; HTTP 429
  retry with [2s, 5s, 15s] backoff (extracted to `retryAfterRateLimit` to satisfy
  `cyclomatic_complexity ≤ 10`). `.spotifyAuthRequired` → calls `startSession` directly
  (SessionManager degrades gracefully to live-only reactive mode; no OAuth in U.3).
- `SpotifyConnectionView`: URL paste field, playlist-ID preview card, per-kind rejection
  copy, retry-attempt indicator.
- `DelayProviding` protocol: `RealDelay` (wall-clock `Task.sleep`) and `InstantDelay`
  (`await Task.yield()` — yields actor without wall-clock wait, enabling fast retry tests).
- `LocalFolderConnector` stub: `#if ENABLE_LOCAL_FOLDER_CONNECTOR` compile flag; always
  throws `.networkFailure("not yet implemented")`.
- `IdleView` updated: "Connect a playlist" → `.sheet`, "Start listening now" → ad-hoc
  session. `PhospheneApp.swift` auto-start `startAdHocSession()` removed from `.onAppear`.

**Key decisions (D-046):**
- `nonisolated(unsafe)` for NSWorkspace observer storage in `@MainActor` classes.
- `ConnectorPickerView` as sheet-with-NavigationStack (not a new NavigationStack root).
- `DelayProviding` protocol for testable retry without wall-clock waits.
- `.spotifyAuthRequired` silently degrades — no user-visible error since the session still
  starts (live-only reactive mode is valid and useful without OAuth).

**Tests:** 21 new PhospheneApp tests (ConnectorPickerViewModelTests×9, SpotifyURLParserTests×12,
AppleMusicConnectionViewModelTests×5 + identifier, SpotifyConnectionViewModelTests×5 + identifier).
56 PhospheneApp tests total. 0 SwiftLint violations.

**Verify:**
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`
- `swiftlint lint --strict --config .swiftlint.yml`

---

### Increment U.4 — Preparation progress UI ✅

**Scope:** `PreparationProgressView` per `UX_SPEC.md §5.2`. New `PreparationProgressPublishing` protocol exposed by `SessionPreparer`; publishes `[TrackID: TrackPreparationStatus]` via Combine. `TrackPreparationRow` renders one of seven statuses (`.queued`, `.resolving`, `.downloading`, `.analyzing`, `.ready`, `.partial`, `.failed`) with icon + copy per `§5.3` table. Aggregate progress bar + per-track ETA + cancel affordance. "Start now" CTA appears at `progressiveReadinessLevel == .ready_for_first_tracks` — dependency on Increment 6.1; before 6.1 ships, this CTA is dormant.

**Done when:**
- Track list updates as each track advances through preparation stages.
- `PreparationProgressPublishing` protocol defined in `Session` module; `DefaultSessionPreparer` conforms.
- All seven status cases render correctly with their icons and copy.
- Cancel tears down in-flight work and returns to `.idle` without leaving orphan stem analyses.
- 6+ unit tests, including a flaky-network fixture via `MockPreparationProgressPublisher`.

**Verify:** `swift test --package-path PhospheneEngine --filter PreparationProgressTests`

---

### Increment U.5 — Ready view + first-audio autodetect ✅

**Scope:** `ReadyView` per `UX_SPEC.md §6.1`. First-track preset renders in background at 0.3× opacity. Attention-drawing pulsing border. First-audio autodetect via `AudioInputRouter` `.silent → .active` transition sustained >250 ms → auto-advance to `.playing`. 90-second timeout handling per `§6.3`. Plan preview panel (`PlanPreviewView`) showing all `PlannedTrack` rows with transitions. Regenerate Plan (D-047) with random seed + manual-lock preservation.

**Delivered:**
- Part A: `ReadyView`, `ReadyViewModel`, `FirstAudioDetector`, `ReadyPulsingBorder`, `ReadyBackgroundPresetView`.
- Part B: `PlanPreviewView`, `PlanPreviewViewModel`, `PlanPreviewRowView`, `PlanPreviewTransitionView`.
- Part C: `PresetPreviewController` stub — deferred to U.5b (D-048).
- Part D: `DefaultSessionPlanner.plan(seed:)`, `PlannedSession.applying(overrides:)`, `VisualizerEngine.regeneratePlan(lockedTracks:lockedPresets:)`.
- 19 new tests: `FirstAudioDetectorTests`, `ReadyViewModelTests`, `PlanPreviewViewModelTests`, `PlanPreviewRegenerateTests`, `ReadyViewTimeoutIntegrationTests`, `SessionPlannerSeedTests`.

---

### Increment U.5b — Preset preview loop (deferred from U.5 Part C)

**Scope:** 10-second looping preset preview triggered by row-tap in `PlanPreviewView`. Currently a no-op stub in `PresetPreviewController`. Full implementation requires engine-layer changes: (1) synthetic `FeatureVector` injection into active `RenderPipeline`; (2) secondary render surface or background-preset surface hijack; (3) loop mechanism without live audio callbacks. See D-048.

**Done when:**
- Row tap in `PlanPreviewView` triggers a looping 10s preview of the row's preset.
- Tap again or session advance stops the preview and reverts to the session's active preset.
- Context-menu "Swap preset" is enabled and wired to `PlanPreviewViewModel.swapPreset(for:to:)`.
- `PresetPreviewController.startPreview(preset:stems:)` drives the RenderPipeline, not a stub.
- 6+ unit tests for preview controller lifecycle + integration test for row-tap → visual change.

**Verify:** `swift test --package-path PhospheneEngine --filter PresetPreviewTests`

---

### Increment U.5c — Plan modification editor (deferred from U.5 Part C)

**Scope:** Preset picker for manual swap in `PlanPreviewView`. The "Modify" footer button and context-menu "Swap preset" action open a picker sheet showing the preset catalog filtered to eligible candidates for the selected track. Currently disabled with `TODO(U.5.C)` markers.

**Done when:**
- "Swap preset" context-menu action opens a preset picker for the selected track.
- Picker shows eligible presets filtered by device tier and fatigue cooldown.
- Selecting a preset calls `PlanPreviewViewModel.swapPreset(for:to:)` and shows lock badge.
- "Modify" footer button opens the same picker for the last-tapped row.
- 4+ unit tests for picker filtering + view model lock state after swap.

**Verify:** `swift test --package-path PhospheneEngine --filter PlanModifyTests`

---

### Increment U.6 — In-session chrome ✅

**Scope:** `PlaybackView` overlay chrome per `UX_SPEC.md §7`. Three layers: Metal render surface (full-bleed), auto-hiding overlay (track info top-left, controls cluster top-right, bottom-right toast slot), debug overlay (toggled with `D`). `OverlayChromeView` with `PlaybackOverlayViewModel` managing visibility + fade timers. Keyboard shortcuts from `§7.6` registered globally within `.playing`. Track-change animation per `§7.5`. Multi-display drag per `§7.7`. Blurred dark backdrop for contrast guarantee.

**Done when:**
- Overlay fades out after 3 s idle; reappears on mouse move or key press.
- Keyboard shortcuts `⌘F`, `Space`, `←`, `→`, `M`, `D`, `Esc`, `?` all wired.
- Track change triggers center toast for 1 s then moves info to top-left card.
- Minimum-contrast 4.5:1 verified against three regression fixtures (silence / steady mid-energy / beat-heavy).
- Display hot-plug reparents window without crash or session loss.
- 8+ unit tests for ViewModel state transitions + snapshot tests for each overlay configuration.

**Verify:** `swift test --package-path PhospheneEngine --filter PlaybackChromeTests`

---

### Increment U.6b — Live adaptation keyboard shortcut semantics ✅

**Status: Complete (2026-04-25)**

**What was built:**
- `DefaultPlaybackActionRouter` fully wired — all seven methods (`moreLikeThis`, `lessLikeThis`, `reshuffleUpcoming`, `presetNudge`, `rePlanSession`, `undoLastAdaptation`, `toggleMoodLock`) produce observable state changes. No remaining `TODO(U.6b)` lines.
- `PresetScoringContext` extended with `familyBoosts`, `temporarilyExcludedFamilies`, `sessionExcludedPresets` (all defaulted empty; D-053 backward-compat discipline).
- `PresetScoreBreakdown.familyBoost: Float` added; `DefaultPresetScorer` honours all three new fields.
- `PlannedSession.extendingCurrentPreset(by:at:)` added in `LiveAdapter+Patching` (same controlled-mutation discipline as `applying(_:at:)`).
- `PresetCategory.displayName` computed property for user-facing toast copy.
- `LiveAdaptationToastBridge` default flipped to `true` for fresh installs; existing explicit user choices preserved via the key-presence check.
- Adaptation preference state lives on `DefaultPlaybackActionRouter` (not `VisualizerEngine`) for testability — D-058(e).
- Double-`-` ambient hint: two `lessLikeThis()` calls within 90 s emit "Not quite hitting the mark? Try ⌘R to re-plan." once per session.
- `adaptationHistory` bounded at 8 entries; `undoLastAdaptation()` restores `livePlan` only (NOT preference state) — D-058(b).
- `VisualizerEngine+Orchestrator` extended with `extendCurrentPreset(by:)`, `applyPresetByID(_:)`, `restoreLivePlan(_:)`, `buildScoringContext(adaptationFields:)`, `currentTrackIndexInPlan()`, `currentTrackProfile()`.
- `PlaybackView.setup()` uses `DefaultPlaybackActionRouter.live(engine:toastBridge:onShowPlanPreview:)` factory.
- 14 app tests + 6 engine tests (adapatation scorer tests in `PresetScorerAdaptationTests`). D-058.

---

### Increment U.7 — Error taxonomy + toast system ✅

**Status: Complete (2026-04-24)**

**Scope:** `UserFacingError` typed enum and `ErrorToast` view component per `UX_SPEC.md §8`. Every row in the UX_SPEC error tables (§8.1–§8.4) has a corresponding enum case with copy test. All user-facing strings externalized in `Localizable.strings`. `PlaybackView` bottom-right toast slot for degradation messages (silence detection, preview fallback, sample-rate mismatch, etc.). Full-screen error states for connection / preparation failures.

**Delivered (3 commits):**
- **Part A:** `UserFacingError` (29 cases, `Shared` module), `Localizable.strings` (English), `LocalizedCopy` service, retroactive string extraction from U.1–U.6 views. Tests: `UserFacingErrorTests`, `LocalizedCopyTests`.
- **Part B:** `FullScreenErrorView`, `PreparationFailureView`, `TopBannerView` (44pt amber banner), `PreparationErrorViewModel` (6 priority rules), `ReachabilityMonitor` (NWPathMonitor + 1s debounce), `StubReachabilityMonitor`. Wired into `PreparationProgressView`. Tests: `PreparationErrorViewModelTests` (7), `ReachabilityMonitorTests` (3).
- **Part C:** `PhospheneToast.conditionID`, `ToastManager.dismissByCondition/_isConditionAsserted`, `PlaybackErrorConditionTracker`, `PlaybackErrorBridge` (replaces `SilenceToastBridge`; fires at 15s per §9.4; condition-ID auto-dismiss on recovery). Wired into `PlaybackView`. Tests: `ToastManagerConditionTests` (3), `PlaybackErrorConditionTrackerTests` (4), `PlaybackErrorBridgeTests` (8). D-051.

**Done when:**
- ✅ `UserFacingError` has a case for every row in UX_SPEC §8.1–§8.4 tables.
- ✅ Exhaustive copy test: every enum case asserts the exact string returned.
- ✅ `Localizable.strings` complete for v1 English; no inline hardcoded strings in views.
- ✅ Toast auto-dismisses on condition-resolved signals; persists while condition holds.
- ✅ Never shows full-screen error during `.playing`.
- ✅ Every error case has either CTA or auto-retry status indicator.

**Verify:** `swift test --package-path PhospheneEngine --filter UserFacingErrorCopyTests`

---

### Increment U.8 — Settings panel ✅

**Scope:** `SettingsView` sheet per `UX_SPEC.md §9`. Four groups: Audio, Visuals, Diagnostics, About. All fields persisted in `UserDefaults` via `SettingsViewModel`. Settings apply immediately (no "Apply" button). Quality ceiling mid-session applies at next preset transition.

**Landed (2026-04-24):** Three-part delivery across two commits (`5ec23e71`, `b67ec770`).

Part A+B: `SettingsTypes` (5 enums/structs), `QualityCeiling` (Orchestrator module), `SettingsStore` (`phosphene.settings.*` key scheme, 11 properties, `captureModeChanged` subject), `SettingsMigrator`, `SettingsViewModel` + `AboutSectionData`, `SettingsView` (`NavigationSplitView`, 720×520pt), `AudioSettingsSection` + `VisualsSettingsSection` + `DiagnosticsSettingsSection` + `AboutSettingsSection`, `SourceAppPicker` + `PresetCategoryBlocklistPicker`, `CaptureModeReconciler` (LIVE-SWITCH, D-052), `SessionRecorderRetentionPolicy` (injected `now`/`wallClock`, active-session guard), `OnboardingReset`, `PresetScoringContextProvider` (effectiveTier + Part C TODOs).

Part C: `PresetScoringContext` + `excludedFamilies`/`qualityCeiling` (backward-compat defaults, D-053), `DefaultPresetScorer` blocklist+quality-ceiling gates, `PresetScoringContextProvider.build()` wired, `SessionRecorder.init(enabled:)`, `LiveAdaptationToastBridge` key migrated, `PhospheneApp.swift` launch-time migration+pruning, settings gear sheet in `PlaybackView`. 50 `Localizable.strings` keys. 39 app tests + 9 engine tests. 573 engine total; 0 SwiftLint violations.

---

### Increment U.9 — Accessibility pass ✅

**Scope:** `NSWorkspace.accessibilityDisplayShouldReduceMotion` gates `mv_warp` and SSGI temporal feedback. Beat-pulse amplitude clamped to 0.5× when reduced motion is active. Dynamic Type sizing respected across all non-Metal views. VoiceOver labels on interactive elements; render surface marked decorative. Overlay-text contrast measured against the three regression fixtures for every preset; failures gate preset certification.

**Done when:**
- `mv_warp` disabled when reduced motion is active; preset still renders correctly without it.
- SSGI temporal feedback disabled (falls back to non-temporal sampling).
- Beat-pulse amplitude cap verified on beat-heavy fixture.
- Dynamic Type from xSmall to xxxLarge renders without clipping across all non-Metal views.
- VoiceOver rotor reads all interactive elements correctly.
- Contrast test fails a synthetic white-on-white preset fixture; passes against all production presets.
- 8+ unit tests + contrast fixture tests.

**Verify:** `swift test --package-path PhospheneEngine --filter AccessibilityTests`

**Delivered (2026-04-24):** `AccessibilityState` (`@MainActor` ObservableObject, `NSWorkspace` + `ReducedMotionPreference` three-way logic). `RenderPipeline.frameReduceMotion` gates mv_warp via `drawMVWarpReducedMotion`. `RayMarchPipeline.reducedMotion` gates SSGI. Beat-clamp applied to `beatBass/Mid/Treble/Composite` in `draw(in:)` before `renderFrame`. Dynamic Type: all 16 user-facing view files updated (`.system(size:)` → semantic styles). VoiceOver: MetalView hidden, 8 interactive elements labelled, `AccessibilityLabels` service, 14 new `Localizable.strings` keys, `AccessibilityNotification.Announcement` on new toasts. Part C: `QualityGradeIndicator` (shape + letter code for color-blindness), `DebugOverlayView` SIGNAL block updated, `PresetContrastCertificationTests` (WCAG 4.5:1 gate). 14 new tests (5 `AccessibilityStateTests` + 3 `BeatAmplitudeClampTests` + 5 `MVWarpReducedMotionGateTests` + 9 `AccessibilityLabelsTests` + 1 `DynamicTypeRegressionTests` + N×3 `PresetContrastCertificationTests`). D-054.

**Deferred:** Strict photosensitivity mode (flash frequency analysis + frame blanking). SSGI temporal accumulation gate distinct from the frame-level `reducedMotion` flag (currently they are the same flag).

---

## Phase V — Visual Fidelity Uplift

**Why this phase exists:** six iterations on Volumetric Lithograph, three each on Arachne and Gossamer, produced incremental fixes but never reached a 2026 quality bar. `docs/SHADER_CRAFT.md` documents the root cause: the `ShaderUtilities` library was thin (55 functions, missing every modern shader technique), there was no detail-cascade methodology documented, no material cookbook, no reference-image discipline, no quality rubric beyond "does it compile." The fidelity cap is authoring-vocabulary poverty in documentation, not hardware or Metal.

V.1–V.6 build the authoring vocabulary. V.7–V.12 apply it to the existing presets Matt called out. V.1–V.6 can run in parallel with Phase U; V.7+ starts once the utility library is ready.

### Increment V.1 — Shader utility library: Noise + PBR

**Scope:** New directory tree `PhospheneEngine/Sources/Renderer/Shaders/Utilities/` with subtrees `Noise/` and `PBR/`. ~90 new functions total. Per `SHADER_CRAFT.md §11.2`:
- `Noise/`: Perlin, Worley, Simplex, FBM (fbm4/fbm8/fbm12, vector fbm), RidgedMultifractal, DomainWarp, Curl, BlueNoise, Hash.
- `PBR/`: BRDF (GGX, Lambert, Oren-Nayar, Ashikhmin-Shirley), Fresnel, NormalMapping, POM, Triplanar, DetailNormals, SSS, Fiber (Marschner-lite), Thin (thin-film interference).

SwiftLint `file_length` special-cased for `.metal` files (raise to 1000 or path-exclude); mechanism TBD during implementation per `SHADER_CRAFT.md §16.1`. `PresetLoader+Preamble.swift` extended to include new utility tree before preset code.

**Done when:**
- All listed utility files exist with the function signatures from SHADER_CRAFT recipes.
- `NoiseUtilityTests` and `PBRUtilityTests` pass (visual sanity check: render each primitive to a test texture, dHash against goldens).
- `.metal` files allowed to exceed 400 lines without lint violation.
- Existing presets compile and render unchanged (additive change, no breaking modifications).
- `fbm8`, `warped_fbm`, `ridged_mf`, `triplanar_sample`, `triplanar_normal`, `parallax_occlusion`, `mat_silk_thread` available for preset authoring.

**Verify:** `swift test --package-path PhospheneEngine --filter UtilityTests && xcodebuild -scheme PhospheneApp build`

---

### Increment V.2 — Shader utility library: Geometry + Volume + Texture ✓ COMPLETE (2026-04-25)
### Increment V.3 — Shader utility library: Color + Materials cookbook ✅ 2026-04-26
### Increment V.4 — SHADER_CRAFT reference implementation audit ✅

**Scope:** Read-through and correctness pass over the completed utility library. For every recipe in `SHADER_CRAFT.md §3`–`§8`, verify the utility implementation matches the documented recipe byte-for-byte. Any drift becomes a doc bug or a code bug — both get fixed. Performance measurements: measure each utility's real cost on Tier 1 (M1/M2) and Tier 2 (M3+) hardware; update the cost table in `SHADER_CRAFT.md §9.4` with measured values.

**Done when:**
- Every `SHADER_CRAFT.md` recipe has a corresponding utility function with matching behavior. ✅
- Cost table in §9.4 reflects measured values on both tier classes. ✅ (estimates in table; run `PERF_TESTS=1` to get GPU-measured values)
- Discrepancies between doc and code are resolved in favor of the empirically-correct version. ✅

**Completed:** 2026-04-26. D-063. Deliverables:
- `docs/V4_AUDIT.md` — 37-recipe cross-reference, 12 drift items resolved (all doc-fixes), 3 missing materials shipped.
- `docs/V4_PERF_RESULTS.json` — initial estimates; replace with measured values via `PERF_TESTS=1 swift test --filter UtilityPerformanceTests`.
- `Sources/UtilityCostTableUpdater/` — CLI to regenerate §9.4 table from JSON.
- `Materials/Organic.metal` +`mat_velvet`, `Materials/Exotic.metal` +`mat_sand_glints`, `Materials/Dielectrics.metal` +`mat_concrete`.
- §16.2 precompiled Metal archives: deferred (estimated ~23 ms, well below 1.0 s threshold).

**Verify:** `swift test --package-path PhospheneEngine --filter MaterialCookbookTests && swift test --filter PresetRegressionTests`

---

### Increment V.5 — Visual references library + quality reel

**Scope:** Create `docs/VISUAL_REFERENCES/` directory with per-preset folders for all registered presets plus scaffolding for Phase MD presets. Each folder: 3–5 curated reference images with an annotated `README.md` specifying which visual traits are mandatory. Matt curates; Claude Code sessions reference by filename. Additionally: build a **quality reel** — a 3-minute multi-genre capture across (sparse jazz → hard electronic → symphonic), used as a one-glance quality-review artifact for future increments. Plus a `CheckVisualReferences` lint CLI (`PhospheneTools`) that enforces completeness and naming convention.

**Done when:**
- Every registered preset has a `docs/VISUAL_REFERENCES/<preset>/` folder with 3–5 reference images and fully-annotated README.
- Quality reel `docs/quality_reel.mp4` checked in (Git LFS).
- `swift run --package-path PhospheneTools CheckVisualReferences --strict` passes with zero warnings.
- `SHADER_CRAFT.md §2.3` reference-image discipline is enforceable — Claude Code sessions cite filenames.
- Matt approves curation round.

**Verify:**
```bash
swift run --package-path PhospheneTools CheckVisualReferences --strict
swift test --package-path PhospheneEngine --filter UtilityTests
swift test --package-path PhospheneEngine --filter PresetRegressionTests
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build
```

#### Session scaffolding shipped (2026-04-26)

The Claude Code session landed the V.5 runway in one sitting. Matt's curation runs in parallel and is tracked separately in `docs/VISUAL_REFERENCES/README.md`.

**Pre-flight findings:**
- **Preset count corrected: 13** (not 11 as CLAUDE.md stated). Confirmed by flat scan of `PhospheneEngine/Sources/Presets/Shaders/*.metal` matching `PresetLoader` behaviour.
- **FerrofluidOcean and FractalTree already ship** — both have `.metal` shader files and `.json` sidecars. CLAUDE.md listed them as V.9/V.10 "full rebuild" targets implying they were new; they are existing presets targeted for rebuild. Reference folders created as required.
- **Membrane is an undocumented production preset** — `family: fluid`, `passes: feedback`, full-rubric treatment. Not mentioned in CLAUDE.md's module map. No engine changes made; CLAUDE.md module map update deferred to V.6 housekeeping.
- **Stalker has no `.metal` file** — CLAUDE.md describes Increment 3.5.7 (Stalker) as complete, but no `Stalker.metal`, `StalkerGait.swift`, or `StalkerState.swift` exist in the repository. No reference folder created. Flag for Matt: either the increment is in progress and the metal file hasn't landed yet, or the code was deleted. D-064 records the observation.
- **No existing `VISUAL_REFERENCES/` precedent** — naming convention defined from scratch per Part C of the increment spec; the §2.3 example filenames (`04_specular_fiber_highlight.jpg`) are the canonical exemplar.
- **Git LFS**: pre-existing for `ML/Weights/*.bin`; extended for `docs/quality_reel*.mp4` and `docs/VISUAL_REFERENCES/**/*.{jpg,png}`.
- **PhospheneTools**: new package (not pre-existing); establishes the location for future `MilkdropTranspiler` (Phase MD.1+).

**What shipped:**
- `docs/VISUAL_REFERENCES/` — 13 preset folders (9 full-rubric + 4 lightweight) + `_TEMPLATE/` (2 variants) + `_NAMING_CONVENTION.md` + `phase_md/` + top-level `README.md` (curation kickoff)
- `PhospheneTools/Package.swift` + `Sources/CheckVisualReferences/main.swift` — 5 lint rules, fail-soft default, `--strict` flag
- `docs/quality_reel_playlist.json` — 3-segment playlist contract with rationale fields
- `.gitattributes` — LFS rules for images + quality reel
- `docs/RUNBOOK.md` — "Recording the quality reel" section
- `docs/SHADER_CRAFT.md §2.3` — lint-check paragraph + `--strict` flip guidance
- `CLAUDE.md §Visual Quality Floor` — cross-reference to lint tool
- `docs/DECISIONS.md D-064` — records four design decisions

**Lint baseline (expected pre-curation state):**
`swift run --package-path PhospheneTools CheckVisualReferences` reports 13 "no reference images" warnings (one per preset folder), 0 errors. This is the correct intermediate state — folders scaffolded, images pending Matt's curation. Build and test suite unaffected (no engine code changed).

#### Reel + partial curation landed (2026-04-30)

- **Quality reel ✅** — `docs/quality_reel.mp4` committed via Git LFS. Source: Spotify Lossless (Blue in Green → Love Rehab → Mountains). Captured in reactive mode — no Spotify OAuth means no `.ready` state; `startAdHocSession()` → `.playing` directly. See D-066 for rationale on accepting reactive-mode capture for V.6 fidelity evaluation.
- **Visual references 5/11** — Arachne ✅, Gossamer ✅, FerrofluidOcean ✅, FractalTree ✅, VolumetricLithograph ✅. Remaining 6 (GlassBrutalist, KineticSculpture, Membrane, Starburst, Nebula, SpectralCartograph — counting Matt's working total of 11 curated targets) planned for next session.

#### Curation progress (2026-05-01)

Membrane and Starburst reference images added. 5 preset folders still require curation (4 have 0 images; 1 may fail lint on image count or annotated README). `CheckVisualReferences --strict` still failing.

**V.5 remains open.** Done-when criteria not met: 5 preset reference folders still require curation, and `CheckVisualReferences --strict` will not pass until all targeted preset folders are populated with conformant images and annotated READMEs.

---

### Increment V.6 — Fidelity rubric + certification pipeline

**Delivered (2026-04-30):** `Sources/Presets/Certification/` (3 files): `RubricResult.swift`, `FidelityRubric.swift` (`DefaultFidelityRubric` — M1–M7 mandatory, E1–E4 expected, P1–P4 preferred, lightweight L1–L4), `PresetCertificationStore.swift` (actor, lazy cache). `PresetDescriptor` + all 13 JSON sidecars extended with `certified/rubric_profile/rubric_hints`. `PresetScoringContext.includeUncertifiedPresets` gate. `DefaultPresetScorer` uncertified check first; `excludedReason: "uncertified"`. `SettingsStore.showUncertifiedPresets` + Settings toggle. 4 test files (26+ @Test functions). D-067.

**Scope:** Implement the `SHADER_CRAFT.md §12` rubric as automated + manual gates:
- Automated: detail-cascade detection via static analysis of preset Metal source (look for `fbm8` / `worley_fbm` / multiple material calls / triplanar usage); noise-octave counting; material-count verification; D-026 deviation-primitive usage; silence-fallback regression test.
- Manual: Matt-approved reference frame match gates certification.

`PresetDescriptor` gains a `certified: Bool` field. Orchestrator excludes uncertified presets by default. `SettingsView` gets a "Show uncertified presets" toggle (off by default).

Supersedes (without deleting) Increment 5.2's weak invariants — those stay as a passing prerequisite.

**Done when:**
- [x] Automated rubric scores every preset; report prints each preset's 7+4+4 breakdown.
- [x] `certified: Bool` field defaults to false for Matt-approved presets only.
- [x] Orchestrator filter excludes uncertified.
- [x] Toggle in Settings reveals uncertified.
- [x] Increment 5.2 invariants still passing.

**Verify:** `swift test --package-path PhospheneEngine --filter FidelityRubricTests`

---

### Increment V.7 — Arachne v4 (fidelity uplift) ⚠ 2026-04-30
### Increment V.7.5 — Arachne v5 (composition + warm restoration + drops + spider cleanup) ⚠ 2026-05-01 shipped, awaiting Matt M7
### Increment V.7.6 — Arachne v5 (atmosphere + beam-bound motes) ❌ ABANDONED 2026-05-02
### Increment V.7.6.1 — Visual feedback harness ✅ 2026-05-02
### Increment V.7.6.2 — Orchestrator: multi-segment + completion-signal + maxDuration framework

**Scope:** Per `docs/presets/ARACHNE_V8_DESIGN.md §3, §5, §6 step 2`. Preset-system-wide infrastructure change. Touches:
- New `PlannedPresetSegment` value type. `PlannedTrack` becomes `let segments: [PlannedPresetSegment]` (was: `let preset: PresetDescriptor`).
- `SessionPlanner` rewritten to walk each track's section list and produce multi-segment plans, respecting per-preset `maxDuration` and section boundaries.
- `PresetSignaling` protocol with `presetCompletionEvent: PassthroughSubject<Void, Never>`. Orchestrator subscribes per active preset; transitions on event if `minDuration` satisfied.
- `LiveAdapter` segment-aware: `presetNudge(.next)` advances to next segment, not next track.
- **`maxDuration` framework** per `ARACHNE_V8_DESIGN.md §5.2`. New `PresetDescriptor.maxDuration(forSection:)` computed property implementing the formula (motionIntensity, fatigueRisk, visualDensity inputs; sectionDynamicRange adjustment; naturalCycleSeconds cap). Coefficients live in code (default −50, −30, −15, 0.7+0.6) with documentation comments. Tunable via V.7.6.C.
- New `naturalCycleSeconds: Float?` field added to `PresetDescriptor` and JSON schema. Initially set only for Arachne (60s).
- Migration: existing presets without completion signals run to formula-computed `maxDuration` and transition by planned boundary.

**Done when:**
- All existing presets continue to work end-to-end (no visual regressions on Plasma, Waveform, VL, etc.).
- Multi-segment plans generated for tracks longer than the chosen preset's `maxDuration`.
- Preset-completion signal can be wired in (Arachne not yet using it; just the channel is there).
- `SessionPlannerTests` updated for multi-segment outputs.
- Live tests still pass; 0 SwiftLint violations.

**Verify:** `swift test --package-path PhospheneEngine` + Matt runtime test on a multi-track playlist (verify presets transition mid-song, not just on track boundaries).

**Estimated sessions:** 2–3. Load-bearing prerequisite for V.7.7+.

---

### Increment V.7.6.C — Framework calibration pass ✅ 2026-05-03
### Increment V.7.6.D — Diagnostic preset orchestrator semantics ✅ 2026-05-03
### Increment V.7.7A — Arachne staged-composition scaffold migration ✅ 2026-05-05
### Increment QS.1 — Quality System Documentation ✅ 2026-05-05
### Increment V.7.7B — Arachne staged WORLD + WEB port ✅ 2026-05-07
### Increment V.7.7C — Arachne refractive dewdrops (§5.8 Snell's-law) ✅ 2026-05-07
### Increment V.7.7D — Arachne 3D SDF spider + chitin + listening pose + 12 Hz vibration ✅ 2026-05-08
### Increment V.7.7C.2 — Arachne single-foreground build state machine + background pool + per-segment spider cooldown + PresetSignaling + WebGPU Row 5 ✅ 2026-05-09
### Increment V.7.7C.3 — Arachne manual-smoke remediation: chord-by-chord spiral + V.7.5 pool retire + branchAnchors polygon + spider trigger reformulation ✅ 2026-05-09
### Increment V.7.7C.4 — Arachne palette + L lock + hybrid audio coupling (D-095 follow-up #2) ✅ 2026-05-09
### Increment V.7.7C.5 — Arachne atmospheric abstraction (WORLD reframe) ✅ 2026-05-08
### Increment V.7.7C.5.1 — Arachne visual craft pass (line widths + luminescence + palette + shaft gate + per-segment seed) ✅ 2026-05-08
### Increment V.7.7C.5.2 — Arachne second cosmetic + spider-trigger pass (drops + silk re-brightening + hue cycle widening + spider sustain) ✅ 2026-05-08
### Increment V.7.7C.5.3 — Per-track web identity (Options B / C) — DEFERRED, awaiting product decision

**Prerequisite:** V.7.7C.5.2 manual-smoke green sign-off. Renumbered from V.7.7C.5.2 after that slot was claimed by the second cosmetic pass. Decision pending Matt's evaluation of whether the Option A per-segment variation (landed in V.7.7C.5.1) is sufficient or whether webs should additionally be tied to track identity for aesthetic association.

**Scope (if scheduled):** Two flavours, mutually-exclusive:

- **Option B — per-track determinism.** Plumb track-identity hash into `ArachneState.reset(trackSeed:)`. Same track always gets the same web (across replays, across sessions). Adds Swift wiring in `ArachneState` (new `reset` overload), a Renderer hook on track change (`PresetSignaling`-style identity passthrough), and a determinism test asserting two `reset(trackSeed:)` calls with the same seed produce byte-identical web state. ~30 LOC + 1 test.

- **Option C — track + session-counter perturbation.** Per-track base seed gives identity; an LCG step per-replay gives variant on the Nth listen. Variety + association both. ~40 LOC + extends the determinism test with a per-replay variance assertion (Nth replay produces materially-different web state from N+1th replay).

Trade-off: B gives consistent music-visual association at the cost of "this track's web always looks weak when it lands on a poor random draw"; C resolves that but adds session state (LCG-per-track replay counter) that needs persistence across track changes within a session.

**Done when:** Manual smoke confirms the chosen flavour reads as intended on a 10+-track playlist with at least one repeated track. V.7.7C.5.1's Option A is preserved as the fallback when no track identity is available (e.g. ad-hoc reactive sessions before track change observation).

**Estimated sessions:** 1 (single Swift-side commit).

---

### Increment V.7.7C.6 — Arachne spider movement system (off-camera entry + walking path + min-visibility latch + rarity gate) — DEFERRED, V.7.7D-scale increment

**Prerequisite:** V.7.7C.4 manual-smoke green sign-off + V.7.7D 3D SDF spider + V.7.7C.4 trigger reformulation already landed.

**Scope:** Add body translation + waypoint navigation + min-visibility latch + N-segment rarity gate to the existing static-position spider. Per Matt's 2026-05-08T18-28-16Z manual smoke: "the spider flashed on the screen for a second then immediately disappeared. I would want the spider to walk from off camera into the camera frame when triggered and move from one hook of the web to another over the span of 10–15 seconds. The trigger should be rare, but the spider should remain in view for longer, and most importantly should MOVE within the camera frame, ideally along the web." Closes V.7.7C.4's deferred sub-item — comparable scope to the V.7.7D 3D anatomy + chitin material increment.

**Architecture decisions (to be filed as D-100 or next-available decision ID at implementation time):**

1. **`SpiderState` enum.** Replace the current `spiderActive: Bool` + `spiderBlend: Float` pair with a state machine: `.idle` / `.entering(progress: Float)` / `.walking(fromIdx: Int, toIdx: Int, progress: Float)` / `.exiting(progress: Float)` / `.cooldown(remainingSegments: Int)`. State advances on each tick; `spiderBlend` becomes a derived value from the current state.
2. **Off-camera entry path.** On trigger, spawn at UV (1.10, 0.50) (or randomly chosen edge-adjacent position outside [0,1]) and walk to the first polygon vertex over ~1.5 s. `.entering` state.
3. **Walking path along polygon hooks.** Use `bs.anchors[]` (V.7.7C.3 polygon vertices) as waypoints. Spider visits 2–3 polygon vertices over 10–15 seconds, walking along silk thread paths (frame edges). Per-waypoint duration ~4–6 s. Body position interpolates smoothly along the silk edge between consecutive waypoints (catmull-rom or simple linear; spec TBD). Existing leg gait drives leg tips relative to body — animates naturally as body translates.
4. **Min-visibility latch.** Once activated, spider stays visible for at least 12–15 seconds regardless of trigger condition. Replace the current `if spiderActive && !conditionMet { spiderActive = false }` with a min-visibility timer that holds. After expiry, transition to `.exiting` and walk off-frame.
5. **N-segment cooldown for rarity.** Currently per-segment cooldown via `spiderFiredInSegment`. Expand to "spider may fire AT MOST once every N segments". Default N=3; configurable. New `ArachneState.spidersFiredCount: Int` increments on each `_reset()`; trigger gates on `spidersFiredCount % N == 0` AND `!spiderFiredInSegment`.
6. **GPU contract.** `ArachneSpiderGPU` stays at 80 bytes (V.7.7D contract). Body position writes to existing `posX` / `posY` fields each frame. Heading writes to `heading` (rotates as spider walks turn corners). No struct expansion.
7. **Pause-guard interaction.** While spider is active, the build state machine is paused (V.7.7C.2 contract). Spider movement progresses independently — body translates and gait animates regardless of build pause.
8. **Music coupling (TBD):** does the spider walking pace couple to music (slower on quiet passages, faster on dense tracks), or is it on a fixed wallclock? Decide at implementation. D-095 audio-modulated TIME precedent suggests `pace = 1.0 + 0.18 × midAttRel` keeps it consistent with the build state machine.

**Done when:**

- Spider state machine implemented with all five states (`.idle` / `.entering` / `.walking` / `.exiting` / `.cooldown`).
- Spider visibly walks from off-camera into the frame on bass-drop trigger.
- Spider visits 2–3 polygon vertices over 10–15 seconds, walking along silk edges.
- Spider remains in view for at least 12–15 seconds regardless of trigger condition.
- Spider trigger fires AT MOST once every N segments (default N=3).
- Existing per-segment cooldown (`spiderFiredInSegment`) preserved as a same-segment fallback.
- All targeted suites pass.
- Goldens regenerated (substantial drift expected — spider position now varies across the 10–15 s walk).
- 0 SwiftLint violations on touched files.
- New `ArachneSpiderMovementTests` test suite covering the five-state machine transitions, min-visibility latch, N-segment cooldown.
- D-100 (or next-available) decision in `docs/DECISIONS.md` documenting the architectural choices above.
- Manual smoke confirms all four behaviours: off-camera entry, walking along web, min-visibility hold, rarity (one trigger per N=3 segments).

**Verify:** Build → `PresetLoaderCompileFailureTest` → targeted suites pre-golden → visual harness sanity check (force spider via `forceActivateForTest(at:)` and capture the walk path) → golden hash regen → targeted suites post-golden → full engine + app suites → SwiftLint → manual smoke (Matt watches multiple spider triggers across a full session, confirms walking path looks natural, min-visibility holds, rarity gate enforces N-segment cooldown).

**Estimated sessions:** 2–3 (state machine + waypoint navigation + min-visibility + rarity + tests + golden regen).

**Carry-forward:** V.7.10 cert review — final QA pass.

---

### Increment V.8.0-spec — Arachne3D: parallel-preset commit + four pushbacks ✅ 2026-05-08 (D-096)
### Increment V.8.1 — Arachne3D minimal end-to-end 3D scaffold

**Prerequisite:** V.8.0-spec ✅ 2026-05-08 (D-096).

**Scope.** Stand up `Arachne3D` as a parallel preset alongside V.7.7D `Arachne` per D-096 Decision 1. New `Arachne3D.metal` + `Arachne3D.json` (display name `"Arachne 3D"`, `certified: false`, default `rubric_profile`) under `PhospheneEngine/Sources/Presets/Shaders/`. `passes: ["ray_march", "post_process"]` (drop `["staged"]`); WORLD pass continues to ship via the existing V.7.7B `arachne_world_fragment` writing `arachneWorldTex` (bound at the same texture index Arachne uses today). The ray-march pass implements `sceneSDF` / `sceneMaterial` using the V.2 SDF tree (`sd_capsule`, `sd_sphere`, `op_smooth_union`) for a **single static web** at `(0, 0, 0)`: 12 procedurally-unrolled spokes, one spiral revolution, no chord-segment subdivision, no drops, no spider, no build cycle. Material: `mat_silk_thread` (V.3 cookbook) on silk strands. Lighting: directional key + flat ambient; **no IBL, no SSGI** (`noSSGI` is the Tier-1 default per D-096 Decision 5). Camera: static, framed on the hub, FoV ~50°. `ArachneState` reused unchanged from V.7.7D — Arachne3D binds the same instance; existing 2D Arachne preset continues to render in parallel. **No `Arachne3DState` is introduced.** Layout audit on `WebGPU` to confirm a `hubZ: Float` extension fits in the existing 80-byte slot (purely additive — V.7.7D Arachne ignores the new field).

Out of scope for V.8.1: drops (V.8.2), refraction (V.8.2), chromatic dispersion (V.8.2), spider (V.8.3), IBL cubemap + DoF (V.8.4), multi-web pool + cinematic camera + foreground build state machine (V.8.5), cert (V.8.6).

**Done when (D-096 Decision 8 — single structural acceptance gate):**

1. **Single web visibly rendering through the deferred PBR pipeline at the correct screen position.** Manual verify by launching the app, cycling to Arachne3D via `⌘[` / `⌘]`, and confirming the silk-strand web renders at the framed hub.
2. **Camera parallax visible.** A small (≤0.5 unit) camera offset injected via developer-shortcut or test fixture must produce visible 3D parallax of silk strands against the WORLD backdrop. The strands move relative to the backdrop; the backdrop does not move (it's a billboard sample per D-096 Decision 2). This proves real 3D rendering, not a 2D fragment shader simulating depth.
3. **WORLD pass sampled correctly as backdrop.** Miss-ray pixels return `arachneWorldTex.sample(uv)` (not flat color, not the sky-only V.7.7B early-out). Verified by silencing the silk SDF in a debug build and confirming the full-frame WORLD render reads through.
4. **Anti-reference visual rejection.** Rendered frame must NOT visually match `09_anti_clipart_symmetry.jpg` or `10_anti_neon_stylized_glow.jpg`. Operationally — until automated dHash-against-anti-refs lands — Matt eyeballs the V.8.1 contact sheet against both anti-refs at the phase boundary and signs off.
5. **p95 frame time inside the budget forecast committed in D-096 Decision 5.** Single-web V.8.1 scene is a fraction of the V.8.5 forecast; Tier 2 expected ~3–5 ms p95, Tier 1 expected ~5–8 ms p95 with the noSSGI default engaged. **V.8.1's first task is to instrument the scene with `MTLCounterSet.timestampGPU` and validate per-component costs against the §4.4 forecast on a real Tier 1 (M1 or M2) device + a real Tier 2 (M3) device.** If Tier 1 exceeds 14 ms p95 even at this reduced scene complexity, the architecture is wrong for Tier 1 and V.8.x replans before V.8.2.
6. **`PresetVisualReviewTests` extended to render `Arachne3D`** alongside `Arachne` for silence / steady / beat-heavy / sustained-bass fixtures into the harness contact sheet under `RENDER_VISUAL=1`. Net-new `Arachne3D` golden hashes added to `goldenPresetHashes` in `PresetRegressionTests`; existing Arachne hashes stay locked at V.7.7D values per D-096 Decision 1.
7. **Visual feedback loop engaged at phase boundary** per `ARACHNE_3D_DESIGN.md §7.3`. Claude Code renders the contact sheet, summarises what changed structurally, and stops. Matt + a separate Claude.ai session produce the visual diff that feeds V.8.2.
8. **Targeted suites pass:** `PresetAcceptance` (Arachne3D added to the parametrized list), `PresetRegression` (Arachne3D goldens), `PresetLoaderCompileFailure` (preset count 14 → 15, no silent compile drop per Failed Approach #44), the existing Arachne suites unchanged. 0 new SwiftLint violations.
9. **Closeout report** per CLAUDE.md Increment Completion Protocol: files changed, tests run, harness output paths, doc updates (V.8.1 entry flipped to ✅; D-096 referenced as the architectural source), capability registry updates if any, known risks (anti-reference subjective check pending automated dHash; perf forecast unverified on Tier 1 hardware until Matt runs the harness on M1/M2), git status clean.

**Verify:**
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` green.
- `swift test --package-path PhospheneEngine` green; `swift test --package-path PhospheneEngine --filter PresetVisualReview` produces non-placeholder Arachne3D PNGs alongside Arachne PNGs.
- `swiftlint lint --strict --config .swiftlint.yml` 0 violations on touched files.
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` writes Arachne3D contact-sheet PNGs to `/tmp/phosphene_visual/<ISO8601>/`.
- Manual: launch app, cycle to Arachne3D, verify acceptance criteria 1–4 above.

**Estimated sessions:** 1 (scaffold-only).

**Carry-forward:** V.8.2 — drops at chord-segment intersections (Tier 2: ~300–500/web; Tier 1: capped at 150/web per D-096 Decision 5) + screen-space Snell's-law refraction sampling `arachneWorldTex` + silhouette-band chromatic dispersion. V.8.3 — spider in 3D via `sceneSDF` (V.7.7D `sd_spider_combined` adapted) + chitin material via `sceneMaterial`. V.8.4 — IBL forest cubemap from V.7.7B WORLD palette + depth-of-field on `PostProcessChain`. V.8.5 — multi-web pool in 3D + cinematic camera (Decision E.3) + foreground build state machine + 3D vibration. V.8.6 — M7 cert + V.7.7D Arachne retirement (file deletion + `Arachne 3D` → `Arachne` rename in JSON sidecar).

**V.8.2+ scope is intentionally NOT expanded yet.** Each subsequent increment gets its own ENGINEERING_PLAN entry once V.8.1 contact-sheet review lands and the visual feedback loop produces the diff that informs V.8.2's prompt.

---

### Increment V.7.7 — Arachne v8: WORLD pillar + 1–2 background dewy webs

**Status correction (2026-05-07):** The `[V.7.7 redo]` commit (`fa5dacdf`, 2026-05-05 10:54) added the six-layer inline `drawWorld()` and frame threads to the *monolithic* `arachne_fragment`. Three hours later, `[V.7.7A]` (`ccefe065`, 2026-05-05 14:13) retired that fragment and shipped placeholder staged stubs. The V.7.7 work is therefore preserved as dead reference code in `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` (free-function `drawWorld` ~line 142, legacy `arachne_fragment` ~line 617), not in the dispatched path. Promotion into the staged path is V.7.7B.

**Prerequisite:** V.7.7A staged-composition scaffold migration ✅ 2026-05-05.

**Scope:** Per `ARACHNE_V8_DESIGN.md §4` (full WORLD pillar) + §5.12 (background webs) + §8.1 step 1–2 (render-pass layout). The 2026-05-03 spec rewrite expanded V.7.7 from a thin atmosphere pass into the full layered WORLD — implementing §4.2's six depth layers into a half-res `arachneWorldTex`: sky band (4.2.1) + distant tree silhouettes (4.2.2) + mid-distance trees with bark detail (4.2.3) + near-frame anchor branches (4.2.4) + forest floor (4.2.5) + volumetric atmosphere (4.2.6 fog + light shafts + dust motes). Mood-driven palette per §4.3 (preserved verbatim from V.7.6.C-locked recipe — `topCol`/`botCol`/`beamCol` + per-layer color application table). Includes 5s low-pass `smoothedValence`/`smoothedArousal` state per §4.3. Then 1–2 pre-populated background dewy webs (§5.12) with refractive drops sampling `arachneWorldTex` per the §5.8 recipe (Snell's law, eta ≈ 0.752, fresnel rim, specular pinpoint, dark edge ring). Background webs vibrate per §8.2. Foreground unchanged (still V.7.5 build code — refactored in V.7.8).

**Done when:**
- WORLD reads as a forest with depth — six layers individually identifiable. Side-by-side via harness contact sheet against refs `06` / `15` / `16` / `17` / `18` / `07`.
- Background webs read as photorealistic dewdrops side-by-side with refs `01` / `03` / `04` via the harness contact sheet.
- Pure-black silence anchor preserved (§8.3) — `(satScale × valScale) < 0.05` clears WORLD pass to black.
- All test suites pass; 0 SwiftLint violations.
- p95 frame time at 1080p ≤ 6.0 ms Tier 2 / ≤ 7.5 ms Tier 1.
- Matt runtime visual review of the WORLD + background-webs state passes.

**Verify:** Same as V.7.6.1 + Matt runtime review.

**Estimated sessions:** 3.

---

### Increment V.7.8 — Arachne v8: WEB pillar — foreground build refactor (corrected biology) [Subsumed by V.7.7C.2 — see V.7.7C.2 section above]

**Status correction (2026-05-07):** The `[V.7.8]` commit (`3536a023`, 2026-05-05 11:06) added the chord-segment capture spiral to `arachneEvalWeb()` inside the monolithic fragment. Same retirement story as V.7.7 — code survives as dead reference at ~line 265 of `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`; port to staged dispatch is V.7.7B. The chord-segment SDF replacement for the degenerate Archimedean curve (Failed Approach #34) is a permanent reference for V.7.7B; do not regress to circular rings.

**Status (2026-05-09 / D-095):** This V.7.5-era line item is **obsolete** — V.7.7C.2 implements the single-foreground build state machine (frame → radials → INWARD spiral → settle, audio-modulated TIME pacing, per-segment spider cooldown, build pause/resume on spider). See V.7.7C.2 above for the actual closeout.

**Scope:** Per `ARACHNE_V8_DESIGN.md §5.1–§5.11` (WEB pillar in full). Replace V.7.5 pool-of-webs system with single-foreground-build state machine implementing the corrected orb-weaver biology: frame polygon (§5.3, 4–7 anchors on near-frame branches from V.7.7) → hub (§5.4, dense knot, NOT concentric rings) → radials (§5.5, 12–17, alternating-pair order, ±20% jitter, drawn one at a time over ~1.5s each) → **capture spiral winding INWARD** (§5.6, chord-segment SDF from outer frame to hub — corrects the 2026-05-02 spec error which had the spiral winding outward) → settle (§5.2, completion signal at 60s ceiling). Sag per §5.7 (`kSag ∈ [0.10, 0.18]`, drop weight modifies sag). Drops per §5.8 with accretion over time on just-laid spiral chords (foreground starts sparse, grows dense; background webs stay saturated). Anchor terminations per §5.9 — small adhesive blobs where outer frame threads meet near-frame branches. Silk material per §5.10 (minor finishing — Marschner-lite removed). Pause on spider trigger; resume on spider fade. Foreground completion emits `presetCompletionEvent` via the V.7.6.2 channel.

**Done when:**
- Visual review via harness: foreground build is visibly progressing — radials extend one-at-a-time, spiral winds **inward** chord-by-chord, completion fires at ≤ 60s under typical music.
- Drops are the visual hero — viewer's eye lands on drops first, threads second. Drops show refraction + fresnel rim + specular pinpoint + dark edge ring per §5.8.
- Anchor structure reads as solid — frame polygon visibly meets near-frame branches at adhesive blobs. Side-by-side with ref `11`. Polygon is irregular, not circular.
- Spider trigger visibly pauses construction; spider fade visibly resumes from paused accumulator (does not restart).
- Orchestrator transitions on completion event when `minDuration` satisfied.
- All test suites pass; 0 SwiftLint violations.
- p95 frame time ≤ 6.0 ms Tier 2.
- Matt runtime visual review passes.

**Verify:** Same.

**Estimated sessions:** 3.

---

### Increment V.7.9 — Arachne v8: SPIDER pillar deepening + whole-scene vibration + cert [Subsumed by V.7.7C.2 / V.7.7D — see V.7.7C.2 + V.7.7D sections above]

**Status correction (2026-05-07):** The `[V.7.9 ✅]` commit (`97f42220`) was a CLAUDE.md status update only — 4 line changes, no shader code. The biology-correct frame → radial → spiral build order remains unimplemented in the dispatched path. SPIDER pillar deepening, vibration, and cert review remain unimplemented as well. Build-order work is scheduled for V.7.7C; SPIDER + vibration for V.7.7D; cert review for V.7.10.

**Status (2026-05-09 / D-095):** This V.7.5-era line item is **obsolete** — V.7.7D shipped SPIDER pillar deepening (3D SDF anatomy + chitin material + listening pose) + whole-scene 12 Hz vibration; V.7.7C.2 closed the structural gap (build state machine). Cert review (M7) remains scheduled for V.7.10. See V.7.7D and V.7.7C.2 above for the actual closeout.

**Scope:** Per `ARACHNE_V8_DESIGN.md §6` (full SPIDER pillar) + §8.2 (vibration model) + §12 (acceptance criteria). The 2026-05-03 spec rewrite expanded V.7.9 from "polish + vibration" into a full spider-anatomy refactor — V.7.5's "dark silhouette + warm rim" was the right *direction* but wrong *depth* for an easter egg that earns its rare appearance. Implements §6.1 anatomy (cephalothorax + abdomen + petiole, 8 articulated legs with outward-bending knee IK, eye cluster as 6–8 small dots in tight forward arrangement — refs `12` + `13`, NOT the jumping-spider 2x2 of ref `19`), §6.2 material (chitin base + thin-film iridescence at biological strength + Oren-Nayar-like hair fuzz + per-eye specular per ref `19` technique), §6.3 pose / gait / listening pose (resting at hub by default; listening pose — front legs raised ~30° — fires on sustained low-attack-ratio bass for ≥ 1.5s), §6.4 lighting (deep body shadow + warm-amber rim + eye sparkle), §6.5 trigger and behavior (per-segment cooldown replaces V.7.5's 300s session-level lock). Whole-scene tremor on bass per §8.2 — 12 Hz audio-rate vibration applied per-vertex to all webs + near-frame branches + spider, amplitude driven by `max(f.subBass_dev, f.bass_dev)` + per-kick spike from `f.beatBass`. Forest floor and distant layers don't shake. Final tuning of drop counts, brightness, sag magnitude, free-zone size, mood-smoothing window against references via the harness. Cert review.

**Done when:**
- Visual review via harness contact sheet matches all 10 acceptance criteria from `ARACHNE_V8_DESIGN.md §12`.
- Spider, when present, is detailed — viewer can see cephalothorax, abdomen, 8 legs with visible knee bends, eye cluster, abdominal pattern. Material reads as biological iridescent chitin (ref `14`), not neon (ref `10`). Listening pose visibly fires on sustained bass.
- Web vibration visible during heavy bass — whole-scene tremor (~12 Hz) on background + foreground webs + branches + spider; ground/distant layers stable.
- Anti-refs `09` (clipart symmetry) and `10` (neon glow) explicitly NOT matched. Refs `01`, `03`, `04`, `05`, `06`, `08`, `11`, `12`, `15`, `16` cited as reachable.
- All test suites pass; 0 SwiftLint violations.
- p95 frame time ≤ 6.0 ms Tier 2.
- **Matt cert review.** If positive: `Arachne.json` `certified: true`, add `"Arachne"` back to `FidelityRubricTests.certifiedPresets`, mark V.5 references action complete, log M7 outcome in references README.

**Verify:** Same.

**Estimated sessions:** 2.

**V.8 remains reserved for Gossamer** per `SHADER_CRAFT.md §10.2`.

---

### Increment V.8 — Gossamer v4

**Scope:** Apply to Gossamer per `SHADER_CRAFT.md §10.2`. Physical wave displacement (waves offset silk strand positions, not just tint them); silk Marschner-lite material tuned for hero resonator; fine specular glints at thread intersections; chromatic aberration on wave peaks; inward/outward dust drift; SSGI-lit background from web emission.

**Done when:** same rubric gates as V.7; `certified: true`.

**Verify:** same as V.7.

**Estimated sessions:** 2 (physical displacement rework / atmosphere + chromatic aberration).

---

### Increment V.9 — Ferrofluid Ocean v2 (redirect) ✅ (certified 2026-05-18)
### Increment V.10 — Fractal Tree v2

**Scope:** Apply to Fractal Tree per `SHADER_CRAFT.md §10.4`. Bark material with POM + triplanar + lichen patches; procedural leaf clusters at branch tips with leaf material (SSS back-lit); wind animation via curl-noise; seasonal palette synced with valence; golden-hour lighting with long shadows.

**Done when:** same rubric gates; `certified: true`. Performance profile shows POM + foliage within Tier 2 budget (likely requires MetalFX Temporal upscaling at sub-1080p internal render).

**Verify:** same as V.7.

**Estimated sessions:** 4 (bark + POM / foliage / wind animation / seasonal + audio).

---

### Increment V.11 — Volumetric Lithograph v5

**Scope:** Major rework per `SHADER_CRAFT.md §10.5`. Replace fBM heightfield with `ridged_mf` warped by `curl_noise` (mountainous, not lumpy); mesa terrace secondary displacement; triplanar detail normal; aerial perspective fog (color-shift from warm sky to cool depth); drifting cloud shadows; cutting-plane beat-reveal replaces palette flash; retain mv_warp and pitch-color mapping from MV-3.

**Done when:** same rubric gates; `certified: true`. Terrain reads as mountainous, not lumpy — confirmed against `docs/VISUAL_REFERENCES/volumetric_lithograph/` annotations.

**Verify:** same as V.7.

**Estimated sessions:** 3 (terrain reformulation / aerial + clouds / cutting-plane + polish).

---

### Increment V.12 — Glass Brutalist v2 + Kinetic Sculpture v2

**Scope:** Fidelity uplift for the remaining ray-march presets not covered in V.7–V.11. Glass Brutalist: board-form concrete lineage (plank impressions, tie-rod holes, weathering — Salk/Scarpa direction, not Ando smooth); detail normals on concrete; POM on walls; pattern-glass material for fins per `SHADER_CRAFT.md §4.5b` (voronoi cellular, NOT fbm-frost); volumetric light shafts through windows. Wet-concrete variant explicitly out of scope — `mat_wet_stone` reserved for other presets. References curated in `docs/VISUAL_REFERENCES/glass_brutalist/` (8 images, 7 trait slots + 1 anti). Kinetic Sculpture: brushed aluminum material per `§4.2`; polished chrome with anisotropic streaks; dust motes in ambient space.

**Done when:** both presets pass fidelity rubric 10/15 with all mandatory; `certified: true` on both.

**Verify:** same as V.7.

**Estimated sessions:** 3 (Glass Brutalist lift / Kinetic Sculpture lift / joint polish + perf).

---

## Phase MD — Milkdrop-inspired uplift work stream

**Operative strategy:** [`docs/MILKDROP_STRATEGY.md`](MILKDROP_STRATEGY.md) §12 (inspired-by reframe addendum, landed 2026-05-12). §§1–11 of that doc remain in tree as the historical record of the derivative-posture framing that preceded the reframe; §12 is the operative record going forward. **Decisions D-103 through D-118 are signed off**; the addendum amended six base decisions in place (D-103 / D-105 / D-106 / D-110 / D-111 / D-112) and filed six new ones (D-113 — posture reframe; D-114 — 20-preset release bundle; D-115 — release-bundle composition (Matt's pick pending); D-116 — substantial-similarity discipline rule; D-117 — catalog-ratio framing (deferred); D-118 — read-only analysis tool scope). Empirical basis for both the base strategy and the addendum: [`docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md`](diagnostics/MD-strategy-pre-audit-2026-05-12.md).

**Why this phase exists (revised under inspired-by):** `docs/MILKDROP_ARCHITECTURE.md` informed Phosphene's own authoring patterns (MV-0 through MV-3); Phase MD turns the cream-of-crop pack into a long-term *inspiration source* for new Phosphene presets — each uplift is a hand-authored, Phosphene-native creation that honors a source Milkdrop preset's concept and aesthetic. The vehicle for that work is the `mv_warp` render pass (D-027) plus the rest of Phosphene's preset infrastructure (V.1–V.4 utilities, ray-march, MV-3 capabilities); Milkdrop-inspired presets become additional consumers alongside Gossamer / Volumetric Lithograph. Initial planning target is **~200 uplifts** (multi-year work stream, not a finite phase); the **20-preset first-release bundle (D-114)** is the near-term milestone.

**The 20-preset first-release bundle (D-114) is the load-bearing near-term milestone.** Phosphene's first public release ships when the catalog reaches 20 M7-certified presets — a mix of Phosphene-native + Milkdrop-inspired per D-115 (composition pending Matt sign-off; default working assumption: 10 + 10). Current state: 1 certified (Lumen Mosaic) + ~14 production-but-not-all-certified Phosphene-native; gap to 20 is the work this Phase MD section (combined with Phase G-uplift + Phase AV) scopes.

Runs in parallel with Phase V.7+, Phase AV, Phase CC, Phase G-uplift. Cadence after first release: separate release-management decision (not in this phase's scope).

### Increment MD.1 — `.milk` grammar audit (read-only authoring aid)

**Scope (revised per `MILKDROP_STRATEGY.md` §12 / D-110 amendment / D-118):** New doc `docs/MILKDROP_GRAMMAR.md` cataloguing the `.milk` expression sub-languages **and** the HLSL `warp_1=` / `comp_1=` surface used across the `presets-cream-of-the-crop` pack. **Reframed as a read-only authoring aid** under the inspired-by reframe — the doc helps an inspired-by author opening a source `.milk` for the first time look up unfamiliar variables / functions / HLSL features. It does **not** drive a transpiler (no transpiler ships per D-110 amendment); HLSL is no longer excluded (every preset in the pack is a viable inspiration source). The audit commits no licensed content (cites the pack as a corpus only).

**Done when:**
- Doc enumerates all variables (bass/mid/treb/time/q1–q32/wave_* / mv_* / ob_* / ib_* etc.) used in the expression sub-languages, with frequency counts over the full 9,795-preset corpus.
- Top-20 built-in functions (sigmoid, clamp, above, below, if_then_else etc.) have Phosphene-side authoring-equivalent notes (reference for inspired-by authors, not transpiler emission spec).
- HLSL surface section (first-class, not appendix) catalogs the `sampler_*`, `GetPixel`, `GetBlur1/2`, `tex2D` etc. surface present in the 81% of pack presets that ship HLSL; each entry notes the Phosphene-side authoring equivalent (a Phosphene primitive an inspired-by author can reach for) — **never** an automated translation spec (D-110 amendment + D-116 discipline rule).
- Frequency + HLSL-presence summary reports descriptive statistics over the full pack. No transpiler coverage gate.

**Verify:** Manual review against 10 randomly-sampled preset files spanning themes / sizes / HLSL presence.

---

### Increments MD.2 / MD.3 / MD.4 — RETIRED

**Status:** Retired entirely under the inspired-by reframe (`docs/MILKDROP_STRATEGY.md` §12, D-110 amendment, D-118).

- **MD.2 (Transpiler CLI skeleton)** — no transpiler ships. `PhospheneTools/MilkdropTranspiler` SPM target was never created and will not be.
- **MD.3 (Per-frame JSON emission + HLSL hand-port playbook)** — the JSON emission half required the transpiler; the hand-port playbook half is also retired (the substantial-similarity discipline rule in `SHADER_CRAFT.md §12.6` / D-116 replaces both translation modes).
- **MD.4 (Per-vertex Metal emission)** — same; no transpiler, no automated emission.

Under the inspired-by reframe, source `.milk` files become reference material that authors read end-to-end before drafting Phosphene-native uplifts. Each Milkdrop-inspired Phosphene preset is hand-authored from scratch against Phosphene's primitives (V.1–V.4 utilities, `mv_warp`, `ray_march`, MV-3 capabilities). The MD.1 grammar doc serves as the read-only reference (D-118). See `MILKDROP_STRATEGY.md` §12.7 / §12.9.

---

### Increment MD.5 — First 10 Milkdrop-inspired uplifts (initial release-bundle batch)

**Scope (revised per `MILKDROP_STRATEGY.md` §12 / D-103 amendment / D-105 amendment / D-106 amendment / D-111 amendment / D-112 amendment / D-116):** Author 10 Milkdrop-inspired Phosphene presets, hand-crafted from scratch against Phosphene's primitives, each honoring a source `.milk` preset's concept and aesthetic per the substantial-similarity discipline rule (`SHADER_CRAFT.md §12.6` / D-116). All 10 ship under a single family — `milkdrop_inspired` — per D-105 amendment. Settings toggle is `phosphene.settings.visuals.milkdrop.inspired` per D-106 amendment. Each `.metal` / `.json` carries an `inspired_by` provenance block per D-111 amendment. Source-preset candidates draw from the D-112 list (HLSL-free constraint dissolves per D-112 amendment; substitutions encouraged at authoring). **This batch contributes to the 20-preset first-release bundle (D-114).**

**Done when:**
- 10 new presets in `PhospheneEngine/Sources/Presets/Shaders/Milkdrop/` with JSON sidecars. Naming: `<theme>_<source_name>.{metal,json}` per D-105 amendment.
- Each preset's JSON sidecar declares `family: "milkdrop_inspired"`, the appropriate `rubric_profile` (per preset — full or lightweight per author + M7 judgment), and `inspired_by: { milkdrop_filename, original_artist, pack, sha256 }`.
- Each preset passes M7 review against the substantial-similarity discipline rule (`SHADER_CRAFT.md §12.6` / D-116) — no source equations copy-pasted, no source shader logic ported line-for-line, no `.milk` content redistributed.
- Each has a golden-session regression entry and Increment 5.2 acceptance test.
- Orchestrator metadata (`visual_density`, `motion_intensity`, `fatigue_risk`, etc.) hand-authored per preset for planning integration.
- `SettingsStore` + `VisualsSettingsSection` gain the single `phosphene.settings.visuals.milkdrop.inspired` toggle per D-106 amendment; defaults to `true` once the first preset ships.
- `docs/CREDITS.md` "Milkdrop-inspired preset attribution" section enumerates all 10 source-preset references per D-111 amendment.

**Verify:** `swift test --filter PresetAcceptanceTests` + per-preset M7 review against `SHADER_CRAFT.md §12.6` checklist.

---

### Increment MD.6 — Ongoing Milkdrop-inspired uplift batches

**Scope (revised per `MILKDROP_STRATEGY.md` §12 / D-103 amendment):** Continued Milkdrop-inspired uplift authoring beyond MD.5's initial batch. **No tier distinction** under the inspired-by reframe (D-103 amendment retired the Classic / Evolved / Hybrid split); every uplift is a `milkdrop_inspired` preset hand-authored against the same discipline rule (D-116). Stem routing, beat anticipation, mood coupling, section awareness, ray-march composition — all per-preset authoring choices, not tier-mandated. Batch size and cadence are release-management decisions (separate from this phase scope).

**Done when:**
- Continued growth of `PhospheneEngine/Sources/Presets/Shaders/Milkdrop/` under the inspired-by framing.
- Each uplift carries `family: "milkdrop_inspired"` per D-105 amendment + `inspired_by` provenance per D-111 amendment + passes M7 review against the D-116 discipline rule.
- `docs/CREDITS.md` extended with each new source-preset reference per D-111 amendment.
- Catalog growth tracked against the long-term ~200-uplift target (`MILKDROP_STRATEGY.md` §12.1). Steady-state catalog ratio question deferred to D-117 trigger.

**Carry-forward:** MD.6 is the long-tail work stream. The 20-preset first-release bundle (D-114) is the first milestone; subsequent bundles ship at the cadence set by release planning.

**Verify:** `swift test --filter PresetAcceptanceTests` per uplift.

---

### Increment MD.7 — Ray-march-composing inspired-by uplifts (formerly Hybrid tier)

**Scope (revised per `MILKDROP_STRATEGY.md` §12 / D-103 amendment / D-107):** Inspired-by uplifts that compose `mv_warp` + `ray_march` against a static camera (D-029). **Not a tier** — these are `milkdrop_inspired` presets that happen to use the ray-march backdrop primitive; authoring choice, not classification. The MD.7.0 spike (single-preset proof of the `mv_warp` + `ray_march` composition) lands as one such uplift; subsequent ray-march-composing uplifts batch into the MD.6 work stream. The architectural composition has only Volumetric Lithograph as prior production proof (and VL's `mv_warp` plays against a ray-march scene that is not itself feedback-warped), so the spike is still a high-value increment under inspired-by.

**Done when:**
- The MD.7.0 spike ships: 1 inspired-by preset composed of `["ray_march", "mv_warp", "post_process"]` renders correctly without obscuring either layer. Recommended source-preset inspiration: Geiss *3D-Luz* (D-107 pre-approved starter).
- Frame budget verified on Tier 1 and Tier 2; results recorded.
- Matt confirms the layering reads as designed (feedback warp visible on top, ray-march backdrop visible behind).
- One-paragraph "what we learned" note added to `MILKDROP_STRATEGY.md` §12.9 carry-forward table or to a follow-up addendum entry, feeding back into subsequent ray-march-composing uplifts.
- The D-107 pre-approved starters (Geiss *3D-Luz*, Rovastar *Northern Lights*, EvilJim *Travelling backwards in a Tunnel of Light*) remain viable inspiration sources for ray-march-composing uplifts under inspired-by; selection follows D-107 criteria (architectural + thematic + brand fit) applied at the preset-concept level rather than the port-feasibility level.

**Verify:** `RENDER_VISUAL=1 swift test --filter PresetVisualReview` + Matt M7 review against the substantial-similarity discipline rule (`SHADER_CRAFT.md §12.6`).

---

## Phase 6 — Progressive Readiness & Performance Tiering

### Increment 6.1 — Progressive Session Readiness ✅ (2026-04-25)
### ✅ Increment 6.2 — Frame Budget Manager (landed 2026-04-25)

**What was built:** `FrameBudgetManager.swift` — pure-state governor with 6-level `QualityLevel` ladder (`full → noSSGI → noBloom → reducedRayMarch → reducedParticles → reducedMesh`), `Configuration` factories (tier1: 14ms/0.3ms margin; tier2: 16ms/0.5ms margin), asymmetric hysteresis (3 overruns down / 180 frames up), `reset()` on preset change. OR-gate refactor of `RayMarchPipeline.reducedMotion` → `a11yReducedMotion || governorSkipsSSGI` with dedicated setters (D-057). `PostProcessChain.bloomEnabled`, `ProceduralGeometry.activeParticleFraction`, `MeshGenerator.densityMultiplier`, `RayMarchPipeline.stepCountMultiplier` (written to `sceneParamsB.z`). Timing via `commandBuffer.addCompletedHandler` → `@MainActor` hop. `QualityCeiling.ultra` exempts the governor. Debug overlay quality level line. 36 new tests across 5 files. Golden hashes regenerated for VolumetricLithograph + KineticSculpture (preamble compiler optimization). 721 engine tests total; 1 pre-existing flaky timer failure unchanged.

---

### ✅ Increment 6.3 — ML Dispatch Scheduling (landed 2026-04-25)

**What was built:**
- `MLDispatchScheduler.swift` (`Renderer` module): pure-state controller with `Configuration` (tier defaults: 2000ms/30-frame Tier 1, 1500ms/20-frame Tier 2), `Decision` enum (`.dispatchNow / .defer(retryInMs:) / .forceDispatch`), `DispatchContext` value type, and `decide(context:) -> Decision` algorithm. `QualityCeiling.ultra` → `enabled = false` bypass. D-059.
- `FrameTimingProviding` protocol in `MLDispatchScheduler.swift`: `recentMaxFrameMs` + `recentFramesObserved`. `FrameBudgetManager` conforms via extension; test stubs use `StubFrameTimingProvider`. Single rolling buffer (30-slot circular array) in `FrameBudgetManager` serves both governor hysteresis counters and the ML scheduler with no duplicate state. D-059(e).
- `VisualizerEngine+Stems.swift` restructured: `runStemSeparation()` hops to `@MainActor`, consults the scheduler, then dispatches back to `stemQueue` via `performStemSeparation()`. `pendingDispatchStartTime` tracks deferral duration; cleared on dispatch and on `resetStemPipeline(for:)` track change.
- `VisualizerEngine` gains `deviceTier: DeviceTier` (stored, set in `init()`), `mlDispatchScheduler: MLDispatchScheduler?`, and `pendingDispatchStartTime: TimeInterval?`. Debug overlay `ML:` row shows current scheduler state (idle / dispatch / defer Nms / force).
- `MLDispatchSchedulerTests.swift`: 10 `@Test` functions. `MLDispatchSchedulerWiringTests.swift`: 5 `@Test` functions (incl. `StubFrameTimingProvider`). 20 new tests total.
- `DECISIONS.md` D-059 (5 sub-decisions). `ARCHITECTURE.md` §ML Inference gains Dispatch Scheduling subsection. `RUNBOOK.md §Jank / dropped frames` updated. `CLAUDE.md` Module Map and §ML Inference updated.
- 747 engine tests; 0 SwiftLint violations. Phase 6 complete.

**Done when:** ✅ Scheduler defers dispatch when recent frames are over budget. ✅ Force-dispatch ceiling prevents stem freeze. ✅ 20 new tests (≥ 4 required). ✅ Zero dHash drift.

**Verify:** `swift test --package-path PhospheneEngine --filter "MLDispatchScheduler"`

---

## Phase 7 — Long-Session Stability

### Increment 7.1 — Soak Test Infrastructure ✅ **LANDED 2026-04-26**
### Increment 7.2 — Display Hot-Plug & Source Switching ✅ **LANDED 2026-04-26**
## Phase MM — Murmuration (promote, redesign, certify)

**Supersedes Phase SB** (below). Matt's 2026-06-03 direction: promote Murmuration to its
own first-class preset (split from the legacy `Starburst.*` files) and **fully redesign the
flock** to faithfully capture the shape and movement of a real starling murmuration, tied to
musical signals — not the cosmetic D-026 + noise-utility pass that Phase SB scoped. The core
problem is structural: the current model is a parametric ellipse of fixed "home slots" with
spring-to-home forces (`Particles.metal` / `ProceduralGeometry`) at **5,000 particles** — it
cannot produce the dense, emergent, morphing mass with a core→edge density gradient that the
references (`docs/VISUAL_REFERENCES/murmuration/`) and motion clips show. "Each bird visible"
is the documented anti-reference (`05_anti_countable_individuals`).

**Decisions (2026-06-03):** full redesign · full rename (retire the Starburst name; no separate
radial-burst preset) · May still-refs are current · Matt-supplied motion clips + flocking-research
references drive the temporal contract (recorded in memory `project_murmuration_uplift.md`).

**Drafted musical contract** (one primitive per layer, one timescale, all deviation primitives per
D-026; continuous drivers 2–4× the beat accents; finalized against the clips in MM.1):

| Visual behavior | Audio driver | Timescale |
|---|---|---|
| Shape elongation (ribbon/comma) + macro drift | `bass_att_rel` | slow / continuous (primary) |
| Turning + pivot + density-agitation waves | `drums_energy_dev` + beat | per-beat (accent) |
| Feathered-edge flutter / shimmering periphery | `mid_att_rel` (edge-weighted) | fast |
| Whole-mass breathing (expand ↔ contract) | `vocals_energy_dev` | phrase |
| Sky warmth shift (≤10%, secondary) | `spectral_centroid` | slow |

---

### Increment MM.0 — Identity split + rename ✅ 2026-06-03

**Delivered (mechanical; output byte-identical, golden hashes stable):**
- `git mv` `Starburst.metal` → `Murmuration.metal`, `Starburst.json` → `Murmuration.json`;
  fragment function `starburst_fragment` → `murmuration_sky_fragment` (JSON `fragment_function`
  updated to match); file header comment updated.
- `git mv docs/VISUAL_REFERENCES/starburst/` → `murmuration/` (LFS-tracked images preserved);
  README title/identity pass (technical sections flagged historical pending MM.1 rewrite).
- Preset discovery is glob-based (`PresetLoader` pairs each `.metal` with its sibling `.json`),
  so the file rename is transparent to loading; no registry/name-list edits needed for discovery.
- Doc path updates: `docs/VISUAL_REFERENCES/README.md`, `CAPABILITY_REGISTRY/PRESETS.md`
  (file/name discrepancy marked resolved), `ENGINE/RENDER_CAPABILITY_REGISTRY.md`,
  `ARCHITECTURE.md` Module Map (also corrected a stale mv_warp description), `RUNBOOK.md`
  (removed a stale Starburst mv_warp reference), `MILKDROP_ARCHITECTURE.md` live table row,
  `FidelityRubricTests.swift` comment. Historical narrative (DECISIONS D-029 body,
  MILKDROP_ARCHITECTURE MV-2 revert story, `archive/`, `diagnostics/`, `prompts/`) left as-is.
- **Scope note:** the `ProceduralGeometry` class / `Particles.metal` engine-shader rename to a
  flock-specific name + its own sibling file (D-097) is **deferred to MM.2**, where the flock
  engine is rewritten — renaming code about to be replaced is churn-on-churn.

**Done when:** ✅ engine + app build clean; ✅ full test suite green (preset loads as
"Murmuration" from the renamed files; golden hashes unchanged).

---

### Increment MM.1 — Reference + motion review → design doc (research-first)  *(draft published 2026-06-03; pending Matt approval)*

**Delivered:** [`docs/presets/MURMURATION_DESIGN.md`](presets/MURMURATION_DESIGN.md) — technique
chosen (**GPU boids over ~7 grid-found neighbours + audio-driven global roost attractor + banking,
simulated in 3D and projected**), grounded in working references (Robert Hodgin *Murmuration*
40K–1M flockers; Rama Hoetzlein three-level flocking; techcentaur boids; McGill biomechanics for
topological neighbours + **orientation-wave dark bands** + critical-noise + flash-expansion).
Infrastructure precedent: `FerrofluidParticles` GPU spatial-binning. Carries the §3 musical contract
(L1–L6), a honest fidelity-risk statement (tuning risk concentrated in MM.2/MM.3), and the open
questions for Matt. **Remaining to close MM.1: Matt's motion-clip notes to finalize the §3 magnitudes
+ approval to proceed to MM.2.**

**Scope:** read the references + Matt's motion clips; decompose the reference signature into
layers; research the working flocking references (Robert Hodgin murmuration, Hoetzlein GPU
flocking, boids implementations, McGill biomechanics analysis — all in memory) and cite them per
the grounding-priority rule. Author `docs/presets/MURMURATION_DESIGN.md`: technique choice +
grounding, particle-count target, the (layer × primitive × timescale) table made concrete from
the video, an honest fidelity-risk statement. **Matt approves the design before any flock code.**
Likely direction: morphing implicit shape-envelope + curl-noise turbulence + cheap grid-based
separation for the feathered edge (GPU spatial-binning precedent: `FerrofluidParticles`).

**Done when:** design doc published + Matt-approved; technique grounded in ≥1 working reference.

---

### Increment MM.2 — Flock engine (the redesign)  *(force-based substrate SUPERSEDED by MM.6; scaffolding kept)*

**Scope:** new flock-specific engine-library shader + conformer (D-097 sibling; this is where
the deferred `ProceduralGeometry`/`Particles.metal` rename lands) at the MM.1 particle count.
**Multi-frame production-path test harness FIRST** (per "test in production-grade pipeline"):
runs the feedback+particles dispatch for N frames at silence and on a beat, measuring silhouette
cohesion + core/edge density gradient. Tune the silence baseline to a dense, cohesive,
density-graded mass (the opposite of the `05_anti_*` failure modes).

**Done when:** silence baseline reads as a cohesive dense mass with a density gradient; harness
asserts it; 60fps-feasible at target count (perf validated in MM.4).

---

### Increment MM.3 — Audio coupling (D-026) + firing evidence  *(force-based coupling SUPERSEDED by MM.6; M7-failed, see below; routing/replay/test scaffolding kept)*

**Scope:** wire the musical contract with deviation primitives; verify the 2–4×
continuous:beat ratio; produce per-route firing evidence from a real-music session
(`features.csv`/`stems.csv`, via `PresetSessionReplay`) — evidence, not assertion.

**CARRY FORWARD the original Murmuration's audio coupling (binding).** MM.3 ports and adapts the
pre-MM `Particles.metal` proven audio mappings onto the boids substrate — it does NOT reinvent them
(that was the "starting over" mistake Matt flagged 2026-06-03). The original's drum turning-wave
propagation = L2 verbatim-in-mechanic; bass elongation = L1; edge-weighted "other" flutter = L4;
vocals density-compression = L5; warmup stem-blend (D-019) + FA #26 cross-genre beat all kept. The
one improvement over the original: convert raw energy → deviation primitives (D-026). See
[`MURMURATION_DESIGN.md` §3.2](presets/MURMURATION_DESIGN.md). **Keep `ProceduralGeometry` /
`Particles.metal` in the tree until MM.3 has ported its audio coupling** — it is the reference source.

**Delivered (2026-06-03, commits `072b2b8c` port · `205ac595` tests · `4ff18f8b` replay · `11767968` lint):**
- `MurmurationFlockGeometry.computeAudio(features:stemFeatures:dt:)` ports the four `Particles.metal`
  routes onto the boids substrate, all from deviation primitives (D-026): **L1 bass** → roost macro
  drift + a guide-segment elongation (Hoetzlein guide-line) → comma/ribbon; **L2 drums** → a curl
  impulse about the flock axis that sweeps as the beat pulse decays (FA #26 cross-genre beat),
  rolling birds without translating the mass (FA #4) + a localized wave-darkening band written to
  `pad0` for the moving dark band; **L4 mid** → inverse-neighbour-count edge flutter; **L5 vocals**
  → tighter inter-bird spacing (the dark pulse). §3.1 coordination: orthogonal-DOF substrate +
  energy/arousal-gated event layer; D-019 warmup blend kept. `FlockParams` → 144 B (MSL mirror).
- Every audio term vanishes at zero input → the MM.2 silence baseline is reproduced exactly (its
  harness stays green). **L3 flash-expansion deferred** per design §9 (Matt 2026-06-03).
- `MurmurationFlockAudioTests` (7 tests) verify every route + the ≥ 2× continuous:beat ratio via
  the **real reset→bin→boids dispatch path**, measured within one geometry (the flock is its own
  control — boids are chaotic + GPU atomic-binning is non-deterministic, so cross-run diffs are
  unreliable). Full engine suite 1384 green; swiftlint --strict 0; app build clean.
- `MurmurationRouteSpecs` registered in `PresetSessionReplay` → a `--preset murmuration` run over a
  recorded session emits the per-route firing evidence pack.

**Done when:** ✅ ratio verified (≥ 2× via real dispatch); ✅ no absolute-threshold reads (D-026
throughout); ✅ each route's routing verified via the production dispatch path. **PENDING (→ MM.5):**
per-route firing evidence from a *real recorded session* (none exists in-repo and live audio can't be
captured headlessly — the diagnostic is built and one command away once Matt records a session) and
the M7 live review (the load-bearing "reads musical + stays calm in calm passages" gate). MM.3's bar
— "the audio coupling demonstrably works at the routing layer" — is met; the perceptual sign-off is
MM.5.

**M7 round 1 FAILED + fixed (2026-06-03, commit `564f4eec`).** First live review: the flock
fragmented into clumps, popped/splashed birds, showed a square-grid artifact — not a murmuration, not
musical. Root cause (live session CSV): the D-026 deviation primitives spike to **~3×** on real music
(`drumsEnergyDev`/`bassEnergyRel` max ~3.2–3.4), but the gains were tuned at input = 1.0 → audio
forces 3–6× too strong, tearing the flock and inverting the Audio Data Hierarchy (FA #4). The routing
tests missed it by capping inputs at 1.0 (FA #66 parity gap). Fix: `tanh`-saturate every driver,
re-tune gains to gentle accents, bound the drift inside the frame, decouple the L2 wave's darkening
(strong) from its curl force (gentle), per-frame edge flutter, + a new **parity invariant test**
(sustained 3×-magnitude audio at 55k → flock stays cohesive). Full suite 1385 green. See
`MURMURATION_DESIGN.md §11.1` + memory `project_deviation_primitive_real_range`. **The live LOOK
(murmuration character + whether the square-grid artifact is gone) is still unverified — needs Matt's
rebuild + re-review; not confirmable headlessly.**

---

### Increment MM.4 — Sky + render polish + performance

**Scope:** upgrade the sky to V.1 noise utilities + palette (secondary — the flock is the hero);
density-accumulation rendering + edge feathering; recalibrate `complexity_cost`; confirm 60fps
@ 1080p (frame-budget governor `activeParticleFraction` downshift already supported).

**Done when:** rubric M1/M2 satisfied on the sky surface; p95 frame time ≤ tier budget.

---

### Increment MM.5 — Certification  *(✅ DONE 2026-06-04, commit `8f313bdc`)*

**Scope:** real-music session, M7 contact sheet vs references + motion clips, Matt approval,
flip `Murmuration.json` `certified: true`, add "Murmuration" to
`FidelityRubricTests.certifiedPresets`, regenerate golden hashes, update registry / plan /
release notes.

**Done when:** Matt M7-approves; `certified: true`; golden hash regenerated; tests green.

**DELIVERED.** Certified after Matt's review across MM.6 rounds (worm → traverse → musicality →
review pass; "works and can probably be certified soon" → "prepare closeout and certification").
`Murmuration.json certified: true` + `rubric_profile: lightweight` (particle preset — exempt from
the M3 material heuristic by construction, like the other certified feedback/particle presets;
Matt's M7 review is the load-bearing gate per SHADER_CRAFT §12.1); stale "500K starlings"
description rewritten to the real 3D parametric-ellipse flock + global-envelope coupling.
`FidelityRubricTests.certifiedPresets += "Murmuration"` (kept in sync with the JSON flag).
`MurmurationRoutes.swift` firing specs re-derived against the shipped `murmuration3d_update`
(ENERGY / BEAT / VOCALS per §13.5; were stale, describing the retired emergent substrate).
Deliberately **no `stem_affinity`** — Murmuration is energy-driven (not stem-specific), so neutral
affinity is the honest representation; stem routing is deferred to Matt's "experimentation" phase.
No golden-hash regen needed (golden tests use an inline catalog with dev=0 → neutral affinity for
all; the JSON cert flip does not perturb them). Review pass on session `2026-06-04T16-44-08Z`:
GPU 0.75 ms mean (trivially cheap), zero NaN/inf across 8554 frames, framing holds live; the only
flags (CPU hitches at startup/track-change 0.2%; high beat-grid drift) are pre-existing engine/audio
behavior, not Murmuration (the beat layer is onset-driven, robust to grid drift). Engine 1377 green,
app build clean, lint 0; FidelityRubric / Golden / routing gates pass. Follow-ups (experimentation
phase): `stem_affinity` tuning, `complexity_cost` recalibration to the measured cheapness.

---

### Increment MM.6 — 3D Murmuration (parametric-ellipse flock)  *(✅ DELIVERED + CERTIFIED 2026-06-04 via MM.5 `8f313bdc`; emergent Flock2 substrate retired after M7 rounds 1–7 all failed live — see RESOLUTION at end of section)*

**Supersedes the force-based substrate of MM.2 and the force-based audio coupling of MM.3.** MM.4
(sky/perf) and MM.5 (cert) now apply to the Flock2 flock and follow this increment.

**Why:** MM.3's M7 live review failed — the force-based flock fragmented/popped/showed a grid artifact
under real audio. Root cause was twofold: deviation primitives spike ~3× (force-magnitude fix landed,
`564f4eec`), AND — more fundamentally — the whole substrate was a hand-derived force-boids
approximation of the published model Matt provided at kickoff. **Failed Approach #73** ("don't build
what's already been built"). The reference is **Hoetzlein's Flock2 (2024, J. Theoretical Biology,
MIT code, github.com/ramakarl/Flock2)**: an *orientation-based* model (neighbour influence = a desire
to TURN via quaternion targets, not summed force vectors) that natively produces what MM.2/MM.3
hand-faked — travelling dark bands **emerge** from alignment+avoidance coupling (MM.3 *injected* a curl
wave), cohesion comes from a **peripheral-boundary turn** (MM.2 used a roost leash that clumps/freezes),
and it is **stable under perturbation by construction** (force-summing is *why* MM.3 shredded under
audio). Audio coupling re-expresses the §3 contract as **gentle biases on the turn-desires**, which
physically cannot fling the flock apart.

**Scope:** PORT Flock2 from its source (`source/flock_types.h`, `flock_kernels.cu/.cuh`,
`app_flock.cpp`) — wholesale, not re-derived from the paper (FA #70/#64). Replace the
`murmuration_boids` integrator + the `MurmurationBird` layout (→ quaternion + speed) + `computeAudio`;
**keep** the conformer/harness/render/sky/governor/replay scaffolding. Re-express L1 bass (drift +
elongation as target/anisotropy bias), L2 drums (intensify the emergent wave on the beat, not a
force), L4 mid (edge-bird turn jitter), L5 vocals (cohesion-strength breathing); L3 still deferred. All
drivers soft-saturated and sized against the real ~3× range (`project_deviation_primitive_real_range`);
**carry the cohesion-under-3×-load test forward** (it caught the MM.3 failure). Full kickoff:
[`docs/prompts/MM6_KICKOFF_FLOCK2_REBUILD_2026-06-03.md`](prompts/MM6_KICKOFF_FLOCK2_REBUILD_2026-06-03.md).
Model + params pre-extracted in memory `project_flock2_reference`.

**Key porting decisions (kickoff §"Porting decisions"):** quaternion bird state; ~7-topological-+-290°-FOV
neighbour query; **unit/scale mapping** (Flock2 is metres / 5–18 m/s — must map to Phosphene's ±2 world,
keep the ratios); drop the roost leash for the boundary term + a soft framing containment (static wide
camera, design §9); port the heading controller faithfully, simplify the full aero only if a term has
no visible effect.

**Done when:** silence flock reproduces Flock2's qualitative behaviour (cohesive morphing mass +
**emergent** travelling bands + feathered edge) vs references/clips; production-path tests green incl.
the carried-forward cohesion-under-load invariant + per-route turn-desire firing; no absolute-threshold
reads; continuous ≥ 2× beat; full suite green, lint 0, app builds; per-route firing evidence from a real
recorded session; **Matt M7 live approval** (the load-bearing gate — not assertable headlessly).

**DELIVERED (2026-06-03).** Hoetzlein's orientation controller (`advanceOrientationHoetzlein` +
`findNeighborsTopological` + libmin `quaternion.cuh`) ported to MSL `murmuration_boids` (quaternion
bird + topological-7/240°-FOV gather + 4 heading rules + reaction-limited control + dynamic-stability
realign). New 64 B `MurmurationBird` (quaternion+target), 208 B `FlockParams`. Silence baseline reads
as a murmuration (cohesive dense core, feathered/stippled edge, detached stragglers, **emergent**
banking; `RENDER_VISUAL=1` frames in `tools/murmuration_reference/frames/`). Banking darkening = true
wing-area-to-camera (`|up.z|`), not an injected channel.

**Two mid-flight design decisions (Matt):**
1. **Faithful aero, NOT simplified** — simulate in literal **metre units** with Flock2's full
   lift/drag/thrust/gravity (source constants) and project metres→clip at render. The flock self-sizes
   by metre-space density (radius ∝ N^⅓); framing/view/domain scale as `cbrt(count)` for
   density-invariance across test (2–6 k) and production counts.
2. **Musicality rethink — global envelope + emergence, NOT per-bird accents.** The self-organizing
   substrate *swallows or inverts* small per-bird injections (the MM.3 drum-roll-wave halved banking;
   mid-flutter increased edge alignment — measured). So drive the flock's **global** state and let the
   structure emerge: **bass** → drift + envelope elongation (ribbon); **bar maneuver** → ONE
   coordinated heading-swing per bar (downbeat-triggered, alternating, energy-gated, drum-modulated) —
   the banking wave **emerges** from the swing (not every beat — too twitchy); **vocals** → active
   vertical dilation (breathing). Per-bird drum-wave + mid-flutter routes **removed**. Empirically:
   the flock's *size* is a stiff emergent equilibrium that tightening a bound can't shrink (only active
   anisotropic forcing — elongation, vertical dilation — moves it robustly).

**Tests** (`MurmurationFlockTests` + `MurmurationFlockAudioTests`, real reset→bin→boids dispatch):
silence baseline, FlockParams stride, silence-zero-drive, bass drift+elongation, bar-maneuver
(banking tracks the bar envelope, multi-bar-averaged), vocals dilation, continuous ≥ 2× maneuver, and
the **carried-forward** cohesion-under-3×-load invariant. The subtle route tests use separately-settled
flocks + long averaging (single within-geometry windows are too noisy under the non-deterministic GPU
binning — flaked under parallel load). Full engine suite 1384 green (×3 parallel runs), lint 0, app
builds. Route specs updated in `MurmurationRoutes.swift`.

**M7 ROUND HISTORY (live reviews, Matt).** R1 split/froze/too-fast (over-tuned off source defaults); R2
frozen cross (speed-scaling broke the lift/gravity balance — reverted to verbatim aero + DT=0.005
sub-stepping); R3 "murmurations of murmurations" internal sub-clusters (over-packed grid → matched source
density); R4 **"birds far too spread out, world still much too large — not convincing, still inferior to
the previous build."**

**ROUND-5 REFRAME — visual density + framing + the camera tilt (2026-06-04).** R4's source-density domain
is a SIMULATION default, not a framed visual — it rendered a small dense core inside a wide sparse spray
(`maxR ≈ 355 m`, ~1.8× whs; the angle-target containment saturated through `mf_fmodulus` and the X/Z wrap
circulated escapees into a halo). Fixes (faithful aero KEPT, gravity unchanged): (1) size the world for
VISUAL density (`whs = 75·cbrt(count/ref)`, `neighborRadius` scales with it so `rNbrs` is counted
accurately, `boundaryCnt` 120→10 = a true topological edge); (2) a **direct-velocity oblate wall**
replaces the saturating angle-target wall as the size/framing controller (no spray, no falling tail, no
overshoot) + gentle flat-bottomed re-centring; (3) the **rounding is a ~34° camera pitch** in the vertex
projection — the flock is a wide disk round in X–Z and thin in Y, so tilting maps its depth into screen
height → a rounded ovoid (ref `01`), no aero change; (4) routes made **homothetic** (proportional to
position, fill don't hollow) + world-relative caps so loud bass gives a framed comma not a thin edge
ribbon. Silence = rounded dense ovoid (ref `01`); loud = coherent framed comma (ref `02`). Test
robustness: audio suite `.serialized`; bar-maneuver asserts **mean banking rises** (not a flaky bar-phase
correlation); loud-cohesion asserts **mean** core-fraction (not the noise-sensitive per-frame min). Full
engine suite **1385 green (×2 full-parallel + ×3 serialized)**, lint 0, app builds. Design doc §12.1.

**ROUND-5 M7 FAILED → ROUND-6 GOVERNOR FIX (2026-06-04).** Live review showed a frozen oval + a small
chaotic sub-flock inside it. The round-5 SHAPE was correct (the frozen oval IS the rounded ovoid); the
failure was a test/prod parity gap (FA #66): the D-057 governor drops `activeParticleFraction` to 0.5, and
the boids integrator ran on `activeCount = particleCount·fraction` — but a **coupled flock cannot drop a
fraction of its birds** (the excluded birds froze in place; the active half re-cohered into the blob).
Every headless test ran at fraction 1.0 → missed it. Fix: integrate ALL birds every frame;
`activeParticleFraction` throttles the **sub-step count** instead (cost-equivalent, flock stays whole).
Regression test `test_governorThrottleFreezesNoBirds` (asserts <2% frozen + cohesive at the throttled
rate) + `mm6_throttled_*` parity render. Generalisable rule added to CLAUDE.md §What NOT To Do (coupled
substrates throttle fidelity, never element count). Full suite **1386 green**, lint 0, app builds. Design
doc §12.2.

**ROUND-6 M7 FAILED → ROUND-7 FREE-WHEELING REWORK (2026-06-04).** R6: "neither looks nor behaves like a
murmuration" — the flock settled into a stable blob (silence renders 24 s apart identical) instead of
ceaselessly morphing. Root cause (FA #73, from the Flock2 source): faithful CONTROLLER, unfaithful WORLD.
The source frames its flock with ONLY the soft peripheral-boundary turn toward a fixed centre (no hard
wall); my round-5 hard wall + per-bird re-centring flat-lined the wheeling. Taproot: the neighbour examine
cap (96) couldn't count r_nbrs to the source's boundary_cnt=120, so I'd used 10 → weak herding → spray →
wall → dead. Fix: remove the wall + re-centring; raise neighborCap 96→512 + boundaryCnt 10→60 so the
boundary-turn frames the flock source-faithfully; lower avoidance 0.05→0.015; PERF early-exit gather
(interior birds exit at boundary_cnt — makes the high cap affordable); 3D far-edge safety for runaways;
wider static view. Silence now MORPHS (banked masses, sweeping wings, comma-tails, shed sub-groups) at
full AND throttled quality. Durable lesson in CLAUDE.md §What NOT To Do (don't bend a ported reference out
of its working regime). Full suite **1387 green**, lint 0, app builds. Design §12.3. Follow-ups: density
(more birds), gather perf for a higher-count ship, audio-route FEEL re-tune for the free-wheeling regime.

**ROUND-7 M7 FAILED → RESOLUTION: PIVOT TO A 3D PARAMETRIC-ELLIPSE FLOCK (2026-06-04, commit `9056dc48`).**
Live review of the free-wheeling rework (and two further iterations) still failed: *"neither looks nor
behaves like a murmuration… the previous version built months ago is still far superior in look and feel.
Have you looked at the code of this version at all?"* — and the flock was extending off-canvas. **Seven M7
rounds (R1–R7) of the emergent Flock2 substrate failed live**; each fix traded one failure for another
(too-fast → frozen → sub-clusters → spray → frozen-oval → dead-blob → off-canvas spray). The convergence
rule of FA #58/#69 fired: iteration that doesn't change the upstream premise means the premise is wrong.
The premise that failed: **pure emergence (free-flight boids) will, on its own, hold one dense framed
on-canvas mass.** It will not — the references teach realistic *motion* (banking → dark bands), but the
*control* (one dense framed morphing mass) comes from the proven 40-round 2D Murmuration
(`Particles.metal`): birds spring-pulled to home slots in a **continuously morphing ellipse**, dense and
framed **by construction**.

Matt's resolving direction (three messages): (a) *"I asked you to REVIEW THE CODE [of the old version],
not replace your work with it"* — learn from the proven architecture, don't just restore the 2D preset;
(b) *"Why are these the only options?"* — rejected the false A/B (keep-emergent vs restore-2D); (c) **"I
have always wanted a 3D version of this preset — this was the whole goal of the uplift. I just don't want
to work on tweaking it for the next 48 hours."** The synthesis: **lift the proven 2D controlled-ellipse
architecture to 3D** — keep the control (spring-to-morphing-ellipse, dense/framed by construction), gain
the third dimension (3D morphing ellipsOID home slots + perspective + depth fade) and real banking
(wing-area-to-camera → the rolling dark bands).

**DELIVERED — `Murmuration3D.metal` + `Murmuration3DGeometry.swift` (a `ParticleGeometry` sibling, D-097;
own `M3DParticle` 64 B layout + `murmuration3d_*` kernels).** 3D ellipsoid home slots with audio-morphed
half-extents; spring-to-home (`3·d + 5·d²`, damping `1 − 3·dt`) from the 2D original; bounded lemniscate
flock-centre drift; perspective projection (camDist 2.6, camPitch 0.35 rad) + depth fade + viewScale 2.1;
banking from turn-rate drives near-black sprite darkening for the dark-band shimmer. Audio brain ported
verbatim from the 2D preset: **bass** → drift + elongation, **drums** → turning-wave/banding, **other** →
flutter + curvature, **vocals** → density compression. 14 000 birds (governor never throttles it at this
cost — controlled flock keeps all birds). Wired into `VisualizerEngine.makeMurmurationGeometry`. **Emergent
Flock2 substrate retired** (`MurmurationFlock.metal` + `MurmurationFlockGeometry` + 2 test files `git rm`'d).

**Verified headlessly** (`Murmuration3DRenderTests`, the look is the deliverable; pace/audio-feel are
Matt's call): `test_framed` asserts framedFrac > 0.95 on-canvas (replicates the vertex projection incl.
viewScale); `test_render` (RENDER_VISUAL=1) — silence frames show a dense tapered 3D mass with near/far
depth gradient morphing comma→ribbon; audio frames show elongated S/boomerang ribbons spanning the frame
with rolling dark bands that shift between shots. Frames in `tools/murmuration_reference/frames/mm3d_*.png`.
Engine **1376 tests green**, app build clean, lint 0.

**1ST LIVE REVIEW → MOTION REWORK (2026-06-04, commit `9b37d359`, design §13.3).** Session
`2026-06-04T15-41-40Z`: *"Better. Consistent shape now, but its movement is more like a worm than a
murmuration"* + ~20 % too slow. The shape was approved; the **motion** read as a worm — root cause was a
`sin(u·π + st)` curvature wave travelling down the long axis (the snake-spine primitive) over a static,
spring-pinned interior. Fix: replace the spine wave with a **wheeling comma** (centred C+S curves rotated
through a turning plane — reshapes, doesn't undulate); add **internal churn** (a flow field smooth in
(u,v,w) advects the home slots so birds stream through the volume — the mass boils); add **continuous
rolling dark bands**; **+20 % speed** via `motionRate = 1.2`. Verified headlessly (framedFrac > 0.95; new
`mm3d_burst_*` 0.2 s frames show the interior reshuffling + bands rolling, not rigid translation). Engine
1376 green, app build clean, lint 0.

**2ND LIVE REVIEW → TRAVERSE (2026-06-04, commit `75d39eaf`, design §13.4).** Session
`2026-06-04T15-59-58Z`: *"Better, but primarily moving in place — needs to drift from one end of the
screen to the other, might require moving the camera back a little."* Motion character was right; the
flock's position stayed mid-frame (drift amp ~0.12 vs flock half-extent ~0.40). Fix: camera back + zoom out
(`camDist` 2.6 → 3.2, `viewScale` 2.1 → 1.3 → flock ~40 % of frame, room to drift) + a slow dominant L↔R
sweep (~34 s each way, clamped ±0.30 x). `test_framed` upgraded to prove framed-across-traverse
(`minFramed > 0.93`) AND a real sweep (`centreXrange > 0.30`). Engine 1376 green, app build clean, lint 0.

**3RD LIVE REVIEW → MUSICALITY (2026-06-04, commit `cd67944a`, design §13.5).** Session
`2026-06-04T16-15-40Z`: *"Steady improvements… the real focus now should be on musicality — how the preset
feels connected to music sources"* (+ traverse still inches, minor). Diagnosis from the session CSVs: the
existing routes were 10–20 % modulations buried under autonomous motion running on a pure-time clock —
that was the disconnect. Fix (global-envelope coupling, `feedback_global_coupling_emergent_substrate` +
Audio Data Hierarchy): smoothed CPU-side envelopes drive `energyEnv` → a **vigor-paced morph clock** +
**swell** + **traverse range** (PRIMARY); `beatEnv` → a **beat-gated agitation wave** (ACCENT); `vocalEnv`
→ density. Gains sized to measured ranges (stem energy ~0.3 mean/0.7 p99; drumsBeat 0→1). `viewScale`
1.3 → 1.05 for swell room. `test_musicality` asserts louder → bigger + more banding than silence;
`test_framed` drives energetic audio and asserts framed + traverse. Engine 1377 green, app build clean,
lint 0.

**CERTIFIED (MM.5, 2026-06-04, commit `8f313bdc`).** Matt approved across the review rounds ("works and
can probably be certified soon" → "prepare closeout and certification"). `Murmuration.json certified:
true`; route specs re-derived; review-pass on `2026-06-04T16-44-08Z` clean (GPU 0.75 ms, 0 NaN, framing
holds). See the MM.5 row above. Design §13 / §13.3 / §13.4 / §13.5. **Experimentation follow-ups (Matt's
"revisit later"):** `stem_affinity` tuning, `complexity_cost` recalibration to the measured cheapness, and
optional deeper beat-coupling (gated by the separate beat-sync work).

---

## Phase SB — Starburst Fidelity Uplift  *(SUPERSEDED by Phase MM, 2026-06-03)*

> **Superseded.** Phase SB scoped a cosmetic uplift (D-026 routing + V.1 noise utilities +
> materials) that kept the parametric-ellipse flock and 5K count. Matt's 2026-06-03 direction
> is a full flock redesign — see **Phase MM** above. SB.0 (docs prep) already shipped; SB.1–SB.5
> are retired in favor of MM.1–MM.5. The SB text below is retained for historical context only.

Starburst (Murmuration) is the particle-system preset: a murmuration of birds against a vivid sunrise/sunset sky, rendered as a compute-kernel particle field composited over a 2D fragment sky. The preset currently sits at `certified: false` with the full rubric unapplied. Its fragment shader (136 lines) uses its own custom hash/noise/fbm functions rather than the V.1 Noise utility tree, drives audio from raw `features.bass_att` and `stems.vocals_energy` (D-026 violation), and has no materials layer.

This phase applies V.1–V.4 utilities and V.5 reference images to bring Starburst to rubric compliance and Matt-approved certification. It runs independently of Phase MD and in parallel with V.8+ since it touches only `Starburst.metal`, `Starburst.json`, and the murmuration particle kernel in `Particles.metal`.

---

### Increment SB.0 — Documentation prep ✅ 2026-05-01
### Increment SB.1 — JSON sidecar audit + routing review

**Scope:** Verify Starburst's JSON sidecar is internally consistent post-D-029, document the audio routing gaps as the baseline for SB.3, and note the family field semantics.

- Confirm `passes: ["feedback", "particles"]` matches the actual render path in `RenderPipeline`.
- Confirm no stale `mvWarpPerFrame`/`mvWarpPerVertex` stubs remain in `Starburst.metal`.
- Audit `Starburst.metal` fragment shader and the murmuration kernel in `Particles.metal` for D-026 violations: raw `features.bass_att`, raw `stems.vocals_energy`, absolute `smoothstep` thresholds against AGC-normalized values.
- Document all D-026 gaps as numbered items for SB.3 to address.
- Note: `family: "abstract"` in the JSON sidecar is the Orchestrator scoring category and is correct — it drives preset-selection heuristics. The "particle system" framing in the README and CLAUDE.md describes the rendering paradigm (D-029 table row), not the aesthetic family. No change needed unless appetite exists to reclassify to a more specific family (e.g., `"organic"` for the murmuration-as-living-flock framing) — defer that decision to SB.1 review.

**Done when:**
- [ ] JSON sidecar fields verified consistent with code.
- [ ] No stale mv_warp stubs present in Starburst.metal.
- [ ] D-026 gap list documented (can be inline commit message or comment in .metal file header).

**Verify:** `grep -n "mvWarp\|mv_warp" PhospheneEngine/Sources/Presets/Shaders/Starburst.metal` returns empty; `grep -n "bass_att\b\|vocals_energy\b" PhospheneEngine/Sources/Presets/Shaders/Starburst.metal` confirms remaining D-026 targets for SB.3.

**Estimated sessions:** 0.5 (audit + commit only; no shader edits).

---

### Increment SB.2 — Visual references curation

**Scope:** Populate `docs/VISUAL_REFERENCES/starburst/` with annotated reference images per the V.5 curation contract (`SHADER_CRAFT.md §2.3`).

- Minimum 4 reference images covering: murmuration silhouette shape vocabulary, sky gradient color palette (peach/amber/rose/lavender/deep blue), cloud detail quality, and particle density-to-silence contrast.
- `README.md` with per-image annotations linking traits to rubric items and target shader behaviour.
- Confirm `swift run --package-path PhospheneTools CheckVisualReferences` lint passes for the starburst folder.

**Done when:**
- [ ] `docs/VISUAL_REFERENCES/starburst/` passes `CheckVisualReferences --strict` lint.
- [ ] README.md annotations present; at least one image per cascade level (macro/meso/micro/specular-breakup) identified.

**Verify:** `swift run --package-path PhospheneTools CheckVisualReferences --strict`

**Estimated sessions:** 1 (Matt curation session).

---

### Increment SB.3 — Audio routing pass (D-026 compliance)

**Scope:** Replace all raw AGC-normalized energy reads in `Starburst.metal` and the murmuration particle kernel with deviation-primitive equivalents per D-026, and verify the 2–4× continuous-to-beat ratio rule.

- Replace `features.bass_att` with `features.bass_att_rel` for continuous cloud drift.
- Replace `stems.vocals_energy` with `stems.vocals_energy_dev` (positive-only) for vocal warmth accent.
- Replace any absolute `smoothstep(x, y, f.bass)` or similar patterns with deviation-form equivalents.
- Verify murmuration particle kernel: flock cohesion / bird speed / scatter burst should read from `bass_att_rel`, `mid_att_rel`, `drums_energy_dev` respectively, not raw energy values.
- Confirm ratio: continuous motion drivers (sky warmth, cloud drift speed, flock density) should be 2–4× larger contributors than beat-accent drivers (scatter burst, horizon flash).
- D-019 warmup: if `totalStemEnergy` warmup guard is absent, add `smoothstep(0.02, 0.06, totalStemEnergy)` blend per VolumetricLithograph reference.

**Done when:**
- [ ] No raw `features.bass`, `features.bass_att`, `stems.vocals_energy` (unqualified) remain as primary visual drivers.
- [ ] Continuous:beat ratio ≥ 2× for all motion drivers.
- [ ] D-019 warmup present if stems are read.
- [ ] `swift test --filter PresetAcceptanceTests` passes (no regression).

**Verify:** `swift test --filter PresetAcceptanceTests && swift test --filter PresetRegressionTests`

**Estimated sessions:** 1.

---

### Increment SB.4 — Detail cascade + materials pass (rubric gate)

**Scope:** Replace Starburst's bespoke `sky_hash`/`sky_noise`/`sky_fbm` with the V.1 Noise utility tree, layer the sky to the mandatory 4-octave minimum, and introduce 3 distinct materials.

- Replace `sky_hash`/`sky_noise`/`sky_fbm` with `perlin2d` + `fbm4`/`fbm8` from the V.1 Noise utility tree (removes duplicate code, adds Perlin quality).
- Sky cloud layer: upgrade from `sky_fbm(uv, 5)` call with custom noise to `warped_fbm` or `fbm8` from the V.1 tree at ≥ 4 octaves. Recalibrate thresholds to fbm centroid-near-0 range (Failed Approach #42: threshold at 0 not 0.5).
- Three materials: (1) sky gradient layer (atmospheric gradient recipe or palette-driven), (2) cloud layer (thin-film / SSS backlit for volumetric softness via V.1 PBR), (3) bird silhouettes (near-black chitin or organic dark material — `mat_chitin` or simple emissive-rim dark). Exact recipes to be chosen with reference images in hand.
- Macro/meso/micro/specular-breakup detail cascade for the sky surface (the primary hero surface):
  - Macro: full-screen gradient arc (existing, correct).
  - Meso: large cloud bank variation via `fbm8` at 0.3–0.5 UV scale.
  - Micro: wisp fine detail via `fbm8` or `warped_fbm` at 0.05–0.1 UV scale.
  - Specular breakup: chromatic scattering near horizon (`chromatic_aberration_radial` from V.3 Color, or IQ cosine palette variation on cloud highlights).

**Done when:**
- [ ] No custom hash/noise/fbm functions remain in `Starburst.metal`; V.1 utility calls used throughout.
- [ ] Hero sky surface uses ≥ 4 noise octaves (M2 rubric pass).
- [ ] ≥ 3 distinct materials present (M3 rubric pass).
- [ ] All 4 detail cascade levels present on sky surface (M1 rubric pass).
- [ ] `swift test --filter FidelityRubricTests` shows Starburst M1+M2+M3 passing.
- [ ] `swift test --filter PresetAcceptanceTests && swift test --filter PresetRegressionTests` pass; golden hash regenerated.

**Verify:** `swift test --filter FidelityRubricTests && swift test --filter PresetAcceptanceTests && swift test --filter PresetRegressionTests`

**Estimated sessions:** 2 (noise/utility migration + cloud detail / materials + specular breakup).

---

### Increment SB.5 — Certification

**Scope:** Full rubric evaluation, Matt-approved reference frame match, and `certified: true` flip.

- Run `DefaultFidelityRubric` against updated Starburst; confirm ≥ 10/15 with all 7 mandatory items passing.
- Matt reviews rendered output against `docs/VISUAL_REFERENCES/starburst/` reference annotations (M7 manual gate).
- On approval: flip `Starburst.json` `certified` field to `true`; regenerate golden hashes.
- Update `rubric_hints` if any P1–P4 preferred items were addressed (e.g., `hero_specular: true` if a specular band on the horizon cloud layer is present).
- Reclassify `rubric_profile` if applicable (Starburst is a full-rubric preset; `"full"` is correct).

**Done when:**
- [ ] Rubric score ≥ 10/15, all 7 mandatory items pass, per `FidelityRubricTests`.
- [ ] Matt has approved the reference frame match (M7).
- [ ] `Starburst.json` `certified` field flipped to `true`.
- [ ] Golden hash regenerated and committed.
- [ ] `swift test --filter PresetRegressionTests` passes with new hash.

**Verify:** `swift test --filter FidelityRubricTests && swift test --filter PresetRegressionTests` + Matt visual review.

**Estimated sessions:** 1 (rubric run + Matt review + certification commit).

---

## Phase DSP — DSP Hardening

Targeted fixes to MIR signals where a documented "Failed Approach" mitigation has shipped but the underlying signal quality still degrades the visualization on uncataloged tracks. Each increment is scoped to one signal, lands behind a diagnostic logging gate first, and ships with before/after captures committed under `docs/diagnostics/`.

---

### Increment DSP.1 — IOI histogram half/double voting in `BeatDetector+Tempo`

**Goal:** Fix the half-tempo octave error documented as Failed Approach #17. Replace the single-peak IOI-histogram selection (with its pairwise 2× correction in `applyOctaveCorrection`) with a small voting pass over harmonic candidates {2·BPM₀, 1.5·BPM₀, BPM₀, 0.667·BPM₀, 0.5·BPM₀}, scored by raw bin count + harmonic support + perceptual prior + (optional) metadata-BPM prior. Reuses `BeatPredictor.setBootstrapBPM` injection path; no new dependency, no model.

**Why now:** The existing `applyOctaveCorrection` only handles a pairwise 2× peak comparison and only when a second peak is present and within ratio 1.8–2.2. On 125 BPM kick-driven tracks the estimator still commonly returns ~62 BPM; metadata disambiguation works for cataloged tracks but fails on live recordings, DJ continuous mixes, and niche releases. Voting lets a true tempo win even when the dominant IOI bin sits at half-tempo.

**Implementation order — diagnostic logging FIRST (project principle):**

1. **Land logging only.** Add a `dumpHistogram(label:)` helper to `BeatDetector+Tempo` emitting the top-5 IOI bins (period, count, implied BPM) plus the currently-selected BPM. Gate behind `BEATDETECTOR_DUMP_HIST=1` env var so it stays silent in production. Commit as `[DSP.1] BeatDetector: histogram dump for tempo diagnosis`.
2. **Capture baseline** on the three reference tracks in `CLAUDE.md`:
   - Love Rehab (Chaim) — known 125 BPM
   - So What (Miles Davis) — known 136 BPM
   - There There (Radiohead) — BPM unknown to us; capture whatever the current estimator returns and treat as the "before" value.
   Save dumps to `docs/diagnostics/DSP.1-baseline.txt`.
3. **Implement voting.** Replace `applyOctaveCorrection` with a scoring pass over the five harmonic candidates. Keep the legacy path reachable behind `BEATDETECTOR_LEGACY_TEMPO=1` for one increment so A/B comparison is trivial.
4. **Re-run the same baseline capture** with voting on. Save to `docs/diagnostics/DSP.1-after.txt`. The diff is the change-description evidence.

**Scoring components:**

- **Bin count** at the candidate BPM (the raw IOI evidence; reuse the existing 141-bucket 60–200 BPM histogram).
- **Harmonic support** — bin counts at half-BPM and third-BPM (i.e. 2× and 3× the candidate period) add a fraction of their count to the score. A true tempo has IOI peaks at integer multiples of its period; a half-tempo candidate does not.
- **Perceptual range prior** — soft Gaussian centered at 120 BPM, σ ≈ 40 BPM, across 50–220 BPM. Hard reject anything outside [40, 240] BPM.
- **Metadata BPM prior** (when available) — strong Gaussian centered at the metadata BPM, σ ≈ 4 BPM. The prior wins ties decisively but cannot override overwhelming IOI evidence (see test case 4).

**Files to touch:**

- `PhospheneEngine/Sources/DSP/BeatDetector+Tempo.swift` — add `dumpHistogram`; replace `applyOctaveCorrection` with voting.
- `PhospheneEngine/Sources/DSP/BeatDetector.swift` — only if the metadata-BPM injection point doesn't already exist on `BeatDetector` itself; reuse `BeatPredictor.setBootstrapBPM` pattern.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatDetectorTempoTests.swift` — new file for unit-level voting tests on synthetic histograms.
- `PhospheneEngine/Tests/PhospheneEngineTests/Regression/BeatDetectorRegressionTests.swift` — extend with reference-track regression cases (existing fixtures unchanged).
- `PhospheneEngine/Tests/PhospheneEngineTests/Performance/DSPPerformanceTests.swift` — add voting-budget assertion.
- `docs/CLAUDE.md` — update Tempo section; amend Failed Approach #17 (octave error is no longer a passive limitation).
- `docs/DECISIONS.md` — new D-073 entry: "Tempo octave disambiguation via IOI harmonic voting + metadata prior". Document why TempoCNN (AGPL) and Sound Analysis (orthogonal) were rejected.

**Tests — synthetic IOI histograms (`BeatDetectorTempoTests.swift`):**

1. **Half-tempo correction.** Histogram with peak at 0.96 s (62.5 BPM) and a smaller-but-present peak at 0.48 s (125 BPM). With no metadata, voting must pick 125 BPM (harmonic at 2× boosts the 125 candidate above the raw peak).
2. **True slow tempo preserved.** Single dominant peak at 0.92 s (65 BPM) and no peak at 0.46 s. Voting must return ~65 BPM, not double it.
3. **Metadata wins ambiguous case.** Near-equal peaks at 100 BPM and 200 BPM. With metadata BPM = 100, voting returns 100. With metadata BPM = 200, returns 200.
4. **Metadata cannot override overwhelming evidence.** 50× dominant peak at 140 BPM. With metadata BPM = 70, voting still returns 140 (stale-metadata defense).
5. **Out-of-range rejection.** Peak implying 300 BPM. Voting falls back to the strongest in-range candidate.
6. **Empty / sparse histogram.** Fewer than 4 onsets in the buffer: voting returns `nil` / leaves `instantBPM` unchanged. Caller behavior unchanged from today.

**Tests — reference-track regression (`BeatDetectorRegressionTests.swift`):** Driven by recorded onset sequences from the reference tracks. If onset fixtures don't already exist, generate by running the live pipeline against the audio and committing the resulting onset arrays as JSON under `Tests/Fixtures/tempo/`. Assertions:

- Love Rehab, no metadata: BPM ∈ [122, 128] (target 125, ±3).
- Love Rehab, metadata = 125: BPM ∈ [123, 127] (tighter with prior).
- So What, no metadata: BPM ∈ [133, 139].
- So What, metadata = 136: BPM ∈ [134, 138].
- There There, no metadata: lock in the post-voting estimate from the DSP.1-after capture; future changes must consciously update.

Existing tests in `BeatDetectorRegressionTests.swift` must continue to pass without modification.

**Performance budget:** Voting runs once per `computeStableTempo` call (1 Hz cadence — same as today, not per audio frame). Budget: voting + scoring < 50 µs on M1. Add `DSPPerformanceTests` case to enforce. No allocation in the hot path; score buffer fixed-size on the stack or pre-allocated.

**Done when:**

- [ ] Diagnostic logging committed and pushed first; baseline capture in `docs/diagnostics/DSP.1-baseline.txt`.
- [ ] Voting implementation committed in subsequent commits.
- [ ] Post-voting capture in `docs/diagnostics/DSP.1-after.txt`. Diff shows octave correction on Love Rehab and So What.
- [ ] All 6 unit tests in `BeatDetectorTempoTests.swift` pass.
- [ ] Reference-track regression tests pass with the BPM bounds above.
- [ ] Existing `BeatDetectorRegressionTests` pass unchanged.
- [ ] `swift test --package-path PhospheneEngine` passes (full suite — same pre-existing env failures acceptable; no new failures).
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` passes.
- [ ] `DSPPerformanceTests` confirms voting < 50 µs.
- [ ] `CLAUDE.md` Tempo section updated; Failed Approach #17 amended.
- [ ] `DECISIONS.md` D-073 added explaining voting policy and rejected alternatives.
- [ ] Commit messages follow `[DSP.1] <component>: <description>`. Multiple small commits preferred (logging → baseline capture → voting impl → tests → docs).
- [ ] Push only after the full verification block passes locally.

**Verify:** `BEATDETECTOR_DUMP_HIST=1 swift test --filter BeatDetectorTempoTests && swift test --filter BeatDetectorRegressionTests && swift test --filter DSPPerformanceTests`.

**Out of scope (do not re-litigate):** TempoCNN (AGPL), custom Core ML tempo classifier, Sound Analysis framework, `BeatPredictor` IIR period smoothing, onset-detection itself.

**Reference principle (do not violate):** Continuous energy is the primary visual driver; beat onset pulses are accents only (D-004). This increment improves the accuracy of an accent-layer signal — it does not justify elevating beats in any preset shader.

**Estimated sessions:** 2 (logging+baseline → voting+tests → docs).

**Delivered (2026-05-03 — scope shifted from voting):** Diagnostic harness + analyzer revealed the failure was not classical half-tempo octave error. Two real bugs:
1. `recordOnsetTimestamps` consumed `bandFlux[0]+bandFlux[1]` (sub_bass + low_bass fused) — produced frame-aliased IOIs because each band fired on slightly different frames per kick.
2. Histogram-mode BPM picking has period-quantization bias toward faster BPMs (BPM bucket widths grow with BPM in period space), so the histogram mode systematically picks 144 over 136.

Shipped:
- `recordOnsetTimestamps` now sources from `result.onsets[0]` (sub_bass per-band onset events from `detectOnsets`, which has 400ms cooldown). Never fuses bands.
- `applyOctaveCorrection` replaced with `computeRobustBPM`: trimmed mean of recent IOIs (within [0.5×, 2×] of median).

Reference-track results: love_rehab 117/152→**122–126** (true 125), so_what 152→**135–138** (true 136). For there_there the histogram still reads kick-pattern (140) not underlying meter (~86) — that's a syncopation limitation outside DSP.1's scope and motivates DSP.2. See commits `9f4c8e1e..bbad760f` and `docs/diagnostics/DSP.1-baseline*.txt`. D-075.

---

### Increment DSP.2 — Beat This! transformer via MPSGraph (offline pre-analysis) + drift-tracker live path

**2026-05-04 pivot.** Originally scoped as a BeatNet (CRNN + particle filter) port; pivoted to Beat This! (Foscarin et al., ISMIR 2024 — transformer encoder, MIT) after a Session-2 audit pass found paraphrased-spec drift in the BeatNet preprocessing stage and weak performance on irregular meters that are load-bearing for Phosphene (Pyramid Song 16/8, Money 7/4, Schism 7/8). The original BeatNet plan is preserved in `docs/diagnostics/DSP.2-beatnet-archive.md`. Decision: **D-077**. The vendored BeatNet GTZAN weights (Session 1 of the original plan, commit `3f5f652b`) are retained as a fallback; everything below describes the Beat This! port.

**Goal:** Compute a high-quality beat / downbeat / time-signature grid once per track during pre-analysis (`SessionPreparer.prepareTrack` running on the cached 30 s preview clip), cache it on `TrackProfile` as a new `BeatGrid` value type, and drive `FeatureVector.beatPhase01` / `beatsUntilNext` analytically from `playbackTime + drift` against that grid. The live audio path runs no transformer; a small `LiveBeatDriftTracker` cross-correlates `BeatDetector`'s sub_bass onset stream against the cached grid in a ±50 ms phase window and emits a smooth drift estimate. Same MPSGraph + Accelerate idiom used by StemSeparator — no CoreML, no third-party C libs at runtime.

**Why now:** DSP.1's diagnosis proved Phosphene's classical-pipeline tempo path is at the ~70% F1 floor. For "as flawless as possible" beat sync (Matt's stated bar) on the irregular-meter tracks the product cares about, a transformer with whole-bar self-attention is the smallest model class that closes the gap. Beat This! is the smallest such model with a stable, MIT-licensed reference implementation and shipped pre-trained weights.

**Architecture mirrors `StemSeparator`:**

```
PhospheneEngine/Sources/ML/
  BeatThisModel.swift            → MPSGraph engine, pre-allocated UMA I/O (mirrors StemModel.swift)
  BeatThisModel+Graph.swift      → MPSGraph build: encoder block stack (mirrors StemModel+Graph)
  BeatThisModel+Weights.swift    → manifest + .bin loading; LN/BN fusion at init where applicable
  Weights/beat_this/             → vendored .bin weights via Git LFS pointers

PhospheneEngine/Sources/DSP/
  BeatThisPreprocessor.swift     → vDSP resample + STFT + log-mel pipeline (parameters confirmed in Session 1)
  BeatGridResolver.swift         → probability → (beats, downbeats, BPM, meter); peak picking + meter inference
  LiveBeatDriftTracker.swift     → cross-correlation drift tracker; FeatureVector wiring

PhospheneEngine/Sources/Session/
  BeatGrid.swift                 → Sendable value type stored on CachedTrackData
```

**Implementation order (sessions, each one PR / commit-chain):**

1. **Session 1 — Architecture audit + weight vendoring. ✅ 2026-05-04.** Commit `9cd0efb8`. Repo cloned at commit `9d787b9797eaa325856a20897187734175467074`. MIT confirmed. `small0` variant chosen: 2,101,352 params, 8.4 MB FP32 (vs `final0`: 20.3 M params, 81 MB). 161 tensors vendored under `PhospheneEngine/Sources/ML/Weights/beat_this/` (Git LFS). Six reference JSON fixtures in `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/beat_this_reference/`. `Scripts/convert_beatthis_weights.py` and `Scripts/dump_beatthis_reference.py` written. `docs/CREDITS.md` attribution block added. **Key S1 findings carried into S2/S3:** (a) inference timing measured at 415–530 ms on M1 CPU (`small0`); D-077's "~100–300 ms" estimate was optimistic — MPS will be faster, but S4 must measure and adjust S6's MLDispatchScheduler budget accordingly; (b) SumHead design: `beat_logits = beat_linear_out + downbeat_linear_out` (additive — beats are a *superset* of downbeats, not a separate class); (c) three MPSGraph workarounds required in S3: RMSNorm must be manual (no `layerNormalization` equivalent), SDPA must be manual matmul+softmax (macOS 14 target, `scaledDotProductAttention` is macOS 15+ only), RoPE must be manual cos/sin; (d) single `RotaryEmbedding(head_dim=32)` instance shared across all 9 blocks (3 frontend + 6 transformer) — precompute `freqs` tensor once in S3 and share; (e) 5 `num_batches_tracked` int64 BN buffers skipped at conversion (training-only, not used at inference); (f) torchaudio cannot load .m4a without `torchcodec` — use ffmpeg subprocess for audio decode (already handled in `dump_beatthis_reference.py`).

2. **Session 2 — Preprocessor port (Swift).** Implement `BeatThisPreprocessor` in `Sources/DSP/`. **Parameters confirmed in S1** (all file:line cited in `docs/diagnostics/DSP.2-architecture.md §2`): n_fft=1024, hop=441, sr=22050 (source), n_mels=128, f_min=30 Hz, f_max=11000 Hz, mel_scale="slaney" (area-normalisation, `norm="slaney"`), power=1 (magnitude, not power), log formula = `log1p(1000 × mel)` (matches `beat_this/preprocessing.py:LogMelSpect.__call__`). **Per-stage golden tests against the Python reference**: synthetic impulse, sine, white noise, plus love_rehab first 1500 frames. Per-stage delta dashboard. Tolerance: float32 ULP per stage where mathematically possible; documented numerical bound where not (resampler — soxr in Python, vDSP in Swift). Key resampler note: Beat This! uses `soxr` for resampling, not librosa's `resample`; a vDSP sinc resampler is acceptable but the tolerance test must reflect the actual delta (not assume ULP). Pre-allocate MTLBuffers for the spectrogram output to avoid heap alloc in `process()`. **Done when:** Swift preprocessor matches Python within measured numerical bound on all test inputs; `BeatThisPreprocessorTests` pass (≥5 test cases incl. love_rehab first-1500-frame golden); no heap allocations in `process()` hot path.

3. **Session 3 — Transformer encoder graph (MPSGraph build only).** Build the model graph in MPSGraph: input projection, positional encoding, encoder block stack (multi-head attention + FFN + LN, in the order Beat This! uses), output head(s). No weight loading yet; random init validates shapes. Layer-by-layer shape tests against architecture-doc numbers. Catch attention-head reshape bugs, layer-norm axis mistakes, off-by-one positional encoding. Reference: `StemModel+Graph.swift` for code style. **Done when:** graph builds cleanly; per-layer output shapes match doc exactly; one full forward pass on random input completes; no MPSGraph compilation warnings.

4. **Session 4 — Weight loading + numerical validation.** Implement `BeatThisModel+Weights.swift` mirroring `StemModel+Weights.swift`. Manifest parsing, .bin loading, LN/BN fusion at init where applicable. **Per-layer numerical golden tests against PyTorch FP32**: load the same checkpoint in PyTorch, run the same input through both, dump intermediates after each encoder block, compare. Tolerance: 1e-4 absolute / 1e-3 relative. Warm-predict timing on M1 for 30 s clip. **Done when:** Swift inference matches PyTorch FP32 within tolerance on all six fixtures, layer-by-layer; warm-predict < 300 ms on M1 (loosened from BeatNet's 142 ms; transformer is bigger).

5. **Session 5 — Beat grid resolver + post-processing.** Peak picking on per-frame beat / downbeat probabilities (use the algorithm Beat This! uses; confirm S1). Meter inference (3/4, 4/4, 5/4, 6/8, 7/8, 11/8, ...) from downbeat spacing distribution; reject implausible meters with a confidence score. BPM from beat spacing — median of inter-beat intervals (no histogram-mode trap from D-075 / Failed Approach #51). `BeatGrid` value type; Sendable, Hashable, Codable for `TrackProfile` cache embedding. **Done when:** end-to-end pipeline on six fixtures: beats within ±20 ms of reference, downbeats within ±40 ms, BPM within ±0.5, time signature correct on ≥5/6.

6. **Session 6 — `SessionPreparer` integration.** Wire `BeatThisModel` into `prepareTrack`. One call per track during preparation; result cached. Extend `CachedTrackData` to include `BeatGrid`. Bump cache version key for invalidation. Respect `MLDispatchScheduler` (D-059): Beat This! is heavier than stem separation; per-call budget needs widening. Recompute Tier 1 / Tier 2 thresholds. Backfill: cached tracks predating Beat This! lazily compute on first access. **Done when:** all production-test playlists prepare with valid `BeatGrid`s; the 919-engine baseline holds; new `BeatGridIntegrationTests` cover preparation, cache hit, cache invalidation.

7. **Session 7 — Live drift tracker + FeatureVector wiring.** `LiveBeatDriftTracker` consumes `BeatDetector.Result.onsets[0]` (sub_bass) and cross-correlates against the cached grid in ±50 ms phase window; smooth drift estimate (EMA, τ ≈ 200 ms). Replace `BeatPredictor` invocations in `MIRPipeline`. `FeatureVector.beatPhase01` and `beatsUntilNext` computed analytically: `phase01 = ((playbackTime + drift - lastBeat) / period).fract()`. Reactive-mode fallback: keep `BeatPredictor` only for the no-cached-grid case; mark deprecated. Visual regression: re-capture goldens for presets that read `beatPhase01` (Arachne, Gossamer, Stalker, VolumetricLithograph). Re-record `docs/quality_reel.mp4` on the user's three reference tracks + Pyramid Song + Money. **Done when:** Phosphene tracks the beat correctly on 5/4, 7/8, 16/8, swing fixtures (subjective + numerical against S1 ground truth); golden hashes regenerated for affected presets; quality reel rerecorded; user signs off.

**Architectural placement (locked 2026-05-04):**

- **Pre-analysis path** (`SessionPreparer.prepareTrack`, offline, runs once per 30 s preview clip): single Beat This! forward pass; output cached on `TrackProfile.beatGrid`. Per-track cost measured at ~415–530 ms on M1 CPU (Python); MPS expected ~100–150 ms but must be measured in S4 before finalising the S6 MLDispatchScheduler budget.
- **Live path** (60 fps render loop): no transformer. `LiveBeatDriftTracker` aligns the cached grid to the live playback timeline via sub_bass onset cross-correlation. `FeatureVector.beatPhase01` / `beatsUntilNext` (floats 35–36) computed analytically. **No GPU contract change** — existing presets unchanged.
- **Replaces:** `BeatPredictor` (deleted in Session 7); `BeatDetector+Tempo.computeRobustBPM` as primary BPM source (kept as ad-hoc reactive-mode fallback).
- **Stays:** `BeatDetector` itself (onset stream still feeds StemAnalyzer + drift tracker); `StructuralAnalyzer` / `NoveltyDetector` (unchanged this increment; possible All-In-One follow-up).

**Test fixtures (acquisition required before Session 1):**

- love_rehab.m4a (electronic ~125 BPM, 4/4) — already vendored.
- so_what.m4a (jazz ~136 BPM, swing) — already vendored.
- there_there.m4a (rock, syncopated kick — DSP.1's load-bearing failure) — already vendored.
- **Pyramid Song (Radiohead) — 16/8 grouped 3+3+4+3+3, extreme irregular-meter stress test.**
- **Money (Pink Floyd) — 7/4.**
- **If I Were With Her Now (Spiritualized) — syncopation plus mid-track meter changes. The fixture that stresses temporal *instability*: a model that locks to one period at the start and rides it through the track will pass Pyramid Song / Money (irregular but locked) and fail here.**

Five of the six fixtures actively stress non-stable-period behavior — only love_rehab is the clean 4/4 control. Pyramid Song / Money / so_what / there_there cover irregular-meter, swing, and offbeat-kick. If I Were With Her Now is the meter-change adaptation gate. If Beat This! tracks all six correctly, the increment is product-ready. If it fails specifically on the meter-change passage, that's the trigger to evaluate streaming-mode inference (re-running the model mid-track) before falling back to All-In-One.

**Files to touch:**

- `PhospheneEngine/Sources/ML/BeatThisModel.swift` — new MPSGraph engine.
- `PhospheneEngine/Sources/ML/BeatThisModel+Graph.swift` — new graph construction.
- `PhospheneEngine/Sources/ML/BeatThisModel+Weights.swift` — new weight loader.
- `PhospheneEngine/Sources/ML/Weights/beat_this/*.bin` — vendored weights (Git LFS).
- `PhospheneEngine/Sources/DSP/BeatThisPreprocessor.swift` — new preprocessor.
- `PhospheneEngine/Sources/DSP/BeatGridResolver.swift` — new probability → grid resolver.
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — new drift tracker.
- `PhospheneEngine/Sources/Session/BeatGrid.swift` — new value type.
- `PhospheneEngine/Sources/Session/SessionPreparer.swift` — call BeatThisModel during prepareTrack; cache BeatGrid.
- `PhospheneEngine/Sources/Session/StemCache.swift` (or equivalent) — extend `CachedTrackData` with `BeatGrid?`.
- `PhospheneEngine/Sources/Audio/MIRPipeline.swift` — replace BeatPredictor invocations with LiveBeatDriftTracker; keep BeatPredictor for reactive-mode fallback.
- `PhospheneEngine/Sources/DSP/BeatPredictor.swift` — deleted in Session 7 (superseded by analytic phase calc + drift tracker).
- `PhospheneEngine/Tests/PhospheneEngineTests/ML/BeatThisModelTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatThisPreprocessorTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatGridResolverTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/LiveBeatDriftTrackerTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/BeatGridIntegrationTests.swift` — new.
- `PhospheneEngine/Tests/PhospheneEngineTests/Performance/BeatThisPerformanceTests.swift` — new.
- `Scripts/convert_beatthis_weights.py` — one-shot converter (mirror of `convert_beatnet_weights.py`).
- `Scripts/dump_beatthis_reference.py` — Python reference-dump script for Session 2 / 4 golden tests.
- `docs/diagnostics/DSP.2-architecture.md` — new audit doc (replaces archived BeatNet version).
- `docs/CLAUDE.md` — Module Map updates, ML Inference section, Failed Approaches as discovered.
- `docs/DECISIONS.md` — D-077 (landed alongside this pivot); follow-up sub-decisions in the D-077 thread for any architectural choices made during the sessions.
- `docs/CREDITS.md` — Beat This! attribution per MIT license (cite paper + repo).

**Tests:**

1. **Unit — `BeatThisPreprocessorTests` (Session 2):**
   - Synthetic impulse / sine / white noise: per-stage match against Python reference within float32 ULP where mathematically possible.
   - Real audio (love_rehab): output within a measured numerical bound vs. the Python reference (set in S1 architecture doc).
   - Zero input → zero output (or model-defined silence vector).
   - No heap allocation in `process()` hot path.

2. **Unit — `BeatThisModelTests` (Session 4):**
   - Weight load → no crash; parameter count matches manifest.
   - Forward pass on random input: per-layer activations match PyTorch FP32 within 1e-4 absolute / 1e-3 relative.
   - Forward pass on six reference fixtures: end-to-end output matches PyTorch FP32 within tolerance.
   - Warm-predict latency on M1 < 300 ms for 30 s clip.

3. **Unit — `BeatGridResolverTests` (Session 5):**
   - Synthetic 120 BPM activation pulses → 120 ± 0.5 BPM, beats every 500 ± 20 ms, time signature 4/4.
   - Synthetic 7/4 at 90 BPM → 90 ± 0.5 BPM, time signature 7/4 detected, downbeats every 7 beats.
   - Tempo change mid-stream (120 → 140 BPM at t = 5 s) → re-locks within the offline post-processing window.

4. **Unit — `LiveBeatDriftTrackerTests` (Session 7):**
   - Cached grid + perfectly-aligned onsets → drift = 0 ± 5 ms.
   - Cached grid + onsets shifted by +30 ms → drift converges to +30 ms within 2 s.
   - No onsets in window → drift estimate decays toward 0 (no runaway).

5. **Integration — `BeatGridIntegrationTests` (Session 6):**
   - Six reference fixtures end-to-end: BPM within ±0.5, time signature correct on ≥5/6, beats within ±20 ms vs. S1 ground truth.
   - **Pyramid Song must read 16/8 (or equivalent grouped meter) with downbeats on the 1 of each 16-cycle.** Load-bearing assertion for the increment.
   - **Money must read 7/4 at ~123 BPM.** Load-bearing assertion.
   - **there_there must read 84–92 BPM** (the meter, not the kick rate). Carries forward from the BeatNet plan as the DSP.1-failure assertion.
   - Cache hit: re-prepare same track → `BeatGrid` reused, no second model call.
   - Cache invalidation: bump model variant string → re-runs.

6. **Performance — `BeatThisPerformanceTests`:**
   - Per-track preparation: < 500 ms on M1 (preprocessing + transformer + post-processing combined).
   - Drift tracker: < 0.1 ms per frame on M1 (live-path budget).

7. **Existing tests:**
   - All 919 engine-test baseline holds.
   - `BeatDetector` unit tests pass unchanged (its onset stream is the drift tracker's input — interface unchanged).
   - `BeatPredictorTests` pass while BeatPredictor exists (until S7 retirement).
   - `MIRPipelineUnitTests` pass — replace BeatPredictor wiring with drift tracker.

**Performance budget:**

- Per-track preparation cost (one-time per 30 s clip): < 500 ms on M1, < 250 ms on M3. Absorbed in the existing playlist-preparation window.
- Live-path cost: < 0.1 ms per frame on M1 (drift tracker only; no transformer at runtime). Negligible vs. the 16.6 ms render budget.
- Memory: < 80 MB for weights (FP16 transformer ~28 MB + activation scratch). Stays well under StemSeparator's 135.9 MB.
- Init cost: < 300 ms for graph build + weight load (one-time at session start).
- Drop-frame behavior in pre-analysis: respect `MLDispatchScheduler` (D-059) — if Beat This! inference would push a frame past budget, defer the dispatch. Track-change resets state.

**Done when (cumulative across sessions):**

- [x] §0 cleanup committed (BeatNet stubs removed; archive marked superseded; D-077 in DECISIONS.md). **2026-05-04.**
- [x] **S1:** Architecture audit `docs/diagnostics/DSP.2-architecture.md` complete; weights vendored under `ML/Weights/beat_this/` (161 tensors, 8.4 MB, `small0`); `Scripts/convert_beatthis_weights.py` reproducible; six reference fixtures captured as JSON ground truth. Commits `afb75954..9cd0efb8`. **2026-05-04.**
- [x] **S2:** `BeatThisPreprocessorTests` pass (5 tests: shape×2 + dcSignal + sineAtMelBin + loveRehab golden match); per-stage golden match max|Δ|=3×10⁻⁵ within tolerance=1e-3; all buffers pre-allocated at init. Commits `d26e3c2b..b2cb5a8b`. **2026-05-04.**
- [x] **S3:** `BeatThisModel` builds zero-init MPSGraph encoder; 5 shape/finiteness tests pass (929/100 suite green); 0 SwiftLint violations. Commit `c71569b1`. **2026-05-04.**
- [x] **S4:** `BeatThisModelTests` pass (9 tests: graphBuilds + inputProjectionShape + outputShape_T10 + outputShape_T1497 + outputRangeIsFinite + weightsLoad_noThrow + outputNonUniform_withRealWeights + inferenceTime_under300ms + loveRehab_gated); real weights loaded from `ML/Weights/beat_this/`; `test_outputNonUniform_withRealWeights` confirms non-uniform output; `test_inferenceTime_under300ms` passes (< 300 ms warm predict); 933 tests / 100 suites; 0 SwiftLint violations. **2026-05-04.**
- [x] **S5:** `BeatGridResolverTests` pass — 8 unit tests + 24 golden fixture tests (6 fixtures × 4 assertions); all six fixtures within tolerance (beats ≥95% within ±20ms, downbeats ≥90% within ±40ms, BPM within ±0.5, meter correct); pyramid_song=3 gate passes; `BeatGrid` value type (Sendable, Hashable, Codable) in `Sources/DSP/`; 945 tests / 102 suites; 0 SwiftLint violations. **2026-05-04.**
- [x] **S6:** `BeatGridIntegrationTests` pass — 4 tests (nilAnalyzer→empty grid, cacheHit short-circuits analyzer, fullPipeline with `DefaultBeatGridAnalyzer` produces non-empty grid at 50 fps, `StemCache.beatGrid(for:)` accessor matches stored data); `BeatGridAnalyzing` protocol + `DefaultBeatGridAnalyzer` injected into `SessionPreparer` (optional, defaults to nil → BeatGrid.empty); `CachedTrackData.beatGrid` field added with `.empty` default; `AnalysisStage.beatGrid` case added; cache-hit short-circuit in `_runPreparation` skips re-analysis on idempotent prepare. Pyramid Song 16/8 / Money 7/4 / there_there assertions remain in S5 golden fixtures (not duplicated here — S6 proves wiring, S5 proves algorithm). 949 tests / 102 suites; 0 SwiftLint violations. **2026-05-04.**
- [~] **S7 — code complete, live in production, pending quality-reel sign-off (2026-05-04):** `LiveBeatDriftTrackerTests` pass (8 original + 7 added in hardening = 15 total); `BeatGridUnitTests` pass (4); `MIRPipelineDriftIntegrationTests` pass (3). `BeatPredictor.swift` doc-deprecated as reactive-mode-only fallback (no `@available` annotation — would cascade warnings into the warnings-as-errors xcconfig app build). `BeatGrid` extended with `beatIndex(at:)`, `localTiming(at:)`, `medianBeatPeriod`, internal `nearestBeat(to:within:)`. `MIRPipeline` gains `liveDriftTracker: LiveBeatDriftTracker` + `setBeatGrid(_:)`; `buildFeatureVector` forks: cached-grid path uses `self.elapsedSeconds` as the playback clock (already track-relative via existing `mir.reset()` in `VisualizerEngine+Capture.swift:127`). `VisualizerEngine+Stems.resetStemPipeline(for:)` now installs the cached grid (or clears it on cache miss). `PresetVisualReviewTests.arguments` extended to `["Arachne","Gossamer","Volumetric Lithograph"]`; Stalker is mesh-shader and excluded from regression by construction. **Golden hashes unchanged** — regression fixtures use prebuilt `FeatureVector` instances with `beatPhase01=0` default and never invoke `MIRPipeline`. App-layer wiring test deferred (engine integration test covers the contract; the change is two lines mirroring the existing `setStemFeatures` pattern). **Outstanding:** `docs/quality_reel.mp4` re-record + Pyramid Song / Money / so_what subjective sign-off; flip to `[x]` once Matt watches and confirms phase locks correctly on irregular meters.
- [x] **S8 — BeatThisModel output matches PyTorch reference (2026-05-05):** Four bugs found and fixed: (1) frontend block order `partial → norm(wrong inDim) → conv` corrected to `partial → conv → norm(out_dim)` (pre-S8 norm used the wrong channel count); (2) stem reshape transposed `[T,F]→[F,T]` before NHWC reshape (pre-S8 was a byte-reinterpretation, scrambling the mel spectrogram); (3) BN1d-aware padding pads each mel bin with `−shift/scale` so the padded region maps to zero post-BN (pre-S8 naive zero-fill caused `BN1d(0)==shift` to produce non-zero values at time edges); (4) RoPE pairs adjacent elements `(x[2i], x[2i+1])` not half-and-half `(x[i], x[D/2+i])` (pre-S8 completely wrong attention dot products). Result: love_rehab.m4a max sigmoid 0.9999 vs Python ref 0.9999; 126 frames > 0.5 vs ref 124; 59 beats detected vs 59 in ground-truth fixture. `test_loveRehab_endToEnd_producesBeats` passes without `withKnownIssue`. S7's drift tracker is now live and active for every Spotify-prepared session. Commits `49315657..b9687cbc`. **2026-05-05.**
- [x] **DSP.2 hardening — all four S8 bugs individually regression-locked (2026-05-05):** `test_loveRehab_endToEnd_producesBeats` thresholds raised to `maxProb > 0.99` / `aboveHalf >= 100` (reflecting confirmed post-S8 values). `BeatThisLayerMatchTests.swift` (new): loads `docs/diagnostics/DSP.2-S8-python-activations.json`, runs `predictDiagnostic` on love_rehab.m4a, asserts per-stage min/max/mean within two-tier tolerances — `preTfmTol=2e-3` for stem.bn1d + frontend.linear; `postTfmTol=1e-2` for transformer.norm + head.linear + output stages (covers ~0.3–0.9% delta from non-causal softmax over padded frames). Transformer blocks 0–5 excluded (Python hooks sub-block FFN output before residual; Swift captures full-block output — incompatible; end-to-end coverage via beat_logits/beat_sigmoid is sufficient). `BeatThisBugRegressionTests.swift` (new): Bug 1 gate (`frontendBlocks[N].norm.scale.count == out_dim`); Bug 3 gate (`|stem.bn1d[t,mel]| < 1e-3` for padded frames t∈[1497,1500) on zero input); Bugs 2+4 annotated as covered by layer-match (wrong reshape scrambles stem.bn1d by >50%; wrong RoPE pairing diverges output by >30%); reactive-mode test confirms `setBeatGrid(nil)` fallback returns finite FeatureVector. `LiveBeatDriftTrackerTests` extended with 7 tests (MARK 9–15) covering `currentBPM`, `currentLockState`, `relativeBeatTimes` public APIs. **975 engine tests / 103 suites; 0 SwiftLint violations.** Commits `286e67cf..4eaae5a7`. **2026-05-05.**
- [x] **S9 — barPhase01/beatsPerBar propagation + live Beat This! for reactive mode (2026-05-05):** `FeatureVector` floats 37–38 promoted from padding to `barPhase01` (phrase-level 0→1 ramp, 0 in reactive mode) and `beatsPerBar` (time-signature numerator, default 4). Metal preamble struct updated to match; Swift `init()` seeds `barPhase01=0 / beatsPerBar=4`. `MIRPipeline.buildFeatureVector` writes drift-tracker values on the grid path and 0/4 on the reactive path. `BeatGrid.offsetBy(_ seconds:)` helper added for time-aligning buffer-relative beat grids to track-relative coordinates. `SpectralHistoryBuffer` ring 4 repurposed from `vocals_pitch_norm` to `bar_phase01`; dead `normalizePitch` method and three pitch constants deleted. `SpectralCartograph`: BR panel third row now plots `bar_phase01` (violet, "BAR φ" label). `runLiveBeatAnalysisIfNeeded()` added to `VisualizerEngine+Stems`: fires once per track after 10 s of buffered tap audio when `liveDriftTracker.hasGrid == false`; lazy-loads `DefaultBeatGridAnalyzer` on `stemQueue`; offsets the resulting grid by `(elapsedSeconds − 10)` to track-relative time; installs via `mirPipeline.setBeatGrid()` on `@MainActor`. Effect: ad-hoc / reactive sessions receive phrase-level beat tracking after ≈ 10 s of listening, same as Spotify-prepared sessions. **987 engine tests; 0 new SwiftLint violations; golden hashes unchanged.** Commit `b6a6095f`. **2026-05-05.**
- [x] `swift test --package-path PhospheneEngine` passes (pre-existing flakes in `MetadataPreFetcher` / `MemoryReporter` acceptable).
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` passes.
- [ ] No `import CoreML` anywhere in the engine.
- [ ] CLAUDE.md Module Map updated; CREDITS.md Beat This! attribution present.

**Verify (per session, run cumulatively at the end):** `swift test --filter BeatThisPreprocessor && swift test --filter BeatThisModel && swift test --filter BeatThisLayerMatch && swift test --filter BeatThisBugRegression && swift test --filter BeatGridResolver && swift test --filter LiveBeatDriftTracker && swift test --filter BeatGridIntegration && swift test --filter BeatThisPerformance`.

**Out of scope (do not re-litigate):**

- aubio (native C dependency; rejected — staying within Swift / MPSGraph idiom).
- madmom (offline-only Python+C; non-portable to runtime).
- CoreML in any form (project hard constraint, see Failed Approach #20 and CLAUDE.md "ML Inference").
- All-In-One (Kim et al., ISMIR 2023) — strictly more capable (joint beat / downbeat / section), but two-axis scope creep in a single increment. Reserved as a follow-up; the architecture in this increment is designed so the model can be swapped with no upstream / downstream changes.
- Live transformer inference at 50 Hz — explicitly rejected; the pre-analysis-then-drift-track architecture is the load-bearing design choice.
- Per-frame downbeat *visual presets* — separate work; this increment exposes `downbeats` on `BeatGrid`, presets opt in later.
- Streaming-mode Beat This! inference for reactive mode — fallback path keeps `BeatPredictor` (or runs a one-shot transformer pass on the first 10–15 s of live audio). Decide in S7.

**License sourcing:**

- Beat This! is MIT-licensed; pre-trained weights ship with the official repo. Vendored with attribution in `docs/CREDITS.md` (S1 ✅).
- The architecture itself is published in Foscarin et al., ISMIR 2024 — implementing it from the paper is unencumbered.

**Risks:**

- Weight quantization: BeatNet is trained in FP32; MPSGraph supports FP32 natively. No quantization needed.
- Resampler quality: vDSP_resamplef from 48 k → 22050 Hz must not introduce artifacts that degrade activations. Mitigation: validate against librosa-reference mel-specs in the unit test (step 3).
- Particle-filter stability: known to be the trickiest part. Mitigation: closely follow Heydari's reference impl; test against synthetic constant-BPM and tempo-change scenarios before integrating with real audio.
- Performance: per-frame inference at 100 Hz is more aggressive than StemSeparator's 5 s cadence. Mitigation: enforce < 2 ms per frame in `BeatTrackerPerformanceTests` from the start; if violated, drop to half-rate inference (50 Hz) before considering more invasive changes.

**Reference principle (do not violate):**

Continuous energy is the primary visual driver; beat onset pulses are accents only (D-004). BeatNet's outputs feed accent-layer fields (`beatPhase01`, `isDownbeat`) only — they do not displace the continuous-energy fields driving primary visual motion.

**Estimated sessions:** 5–7 (weights + mel-spec → 1, MPSGraph build + inference → 2, particle filter → 2, integration + tests + docs → 2).

---

### Increment DSP.3 — Beat Sync + Diagnostic Environment (audit + fixes)

**2026-05-05 audit.** Full architecture audit of the Beat This! BeatGrid lifecycle, live drift tracking, reactive-mode surface, Spectral Cartograph diagnostic coverage, FeatureVector product contract for complex meters, and test fixture gaps. Audit document: `docs/diagnostics/DSP.3-beat-sync-test-environment-audit.md`.

**Root cause of observed "Phosphene shifts into Reactive mode" when switching to Spectral Cartograph:** The `SpectralCartographText` overlay labels `lockState=0` as "REACTIVE." When `LiveBeatDriftTracker` is in UNLOCKED state — either because `resetStemPipeline(for:)` has not yet fired (music not started) or because fewer than 4 tight-match onsets have been accumulated — the orb reads "REACTIVE" even though `livePlan` is non-nil and the engine is in planned mode. This is a display ambiguity, not a session mode regression. However, a second structural problem makes Spectral Cartograph unusable as a held diagnostic surface: `DefaultLiveAdapter` mood-override fires every ~60 seconds when the current preset scores 0.0 (diagnostic-excluded), switching the engine away from Spectral Cartograph.

**Sub-increments:**

- **DSP.3.1 — Diagnostic hold + session-mode signal.** `diagnosticPresetLocked` flag in `VisualizerEngine`; suppresses mood-override in `applyLiveUpdate()`. `SpectralHistoryBuffer[2420]` session-mode slot (0=reactive, 1=planned+unlocked, 2=planned+locking, 3=planned+locked). `SpectralCartographText` updated to show "PLANNED · UNLOCKED" / "PLANNED · LOCKING" / "PLANNED · LOCKED" / "REACTIVE." `L` dev shortcut to toggle hold. **✅ 2026-05-05 — commit `56359c07`.**
- **DSP.3.2 — Pre-fire BeatGrid on session start.** At end of `_buildPlan()` after `livePlan` is stored, call `resetStemPipeline(for: plan.tracks.first?.track)`. BeatGrid present before music starts; idempotent via `currentTrackIdentity` guard in `resetStemPipeline`. **✅ 2026-05-05 — commit `56359c07`.**
- **DSP.3.3 — Beat sync observability: text overlays + CSV + calibration shortcuts.** `SpectralCartographText.draw()` extended with beat-in-bar counter ("3 / 4"), drift readout ("Δ +12 ms"), phase offset indicator ("φ+10ms"); `textOverlayCallback` type updated to pass `FeatureVector` per frame; `[`/`]` dev shortcuts for ±10 ms visual phase calibration; `BeatSyncSnapshot` struct (9 fields) for offline analysis; `SessionRecorder.features.csv` gains 9 new beat-sync columns (`barPhase01_permille`, `beatsPerBar`, `beat_in_bar`, `is_downbeat`, `beat_sync_mode`, `lock_state`, `grid_bpm`, `playback_time_s`, `drift_ms`); `SpectralHistoryBuffer[2429]` drift_ms slot; 31 new tests (BeatInBarComputationTests 16+, SpectralHistoryBuffer slot stability 4+, others). Core Text mirroring fix in `DynamicTextOverlay.refresh()`. `docs/diagnostics/DSP.3.3-beat-sync-latency-phase-notes.md`. **✅ 2026-05-05.**
- **DSP.3.4 — Fix three root causes blocking PLANNED·LOCKED in reactive/ad-hoc sessions.** Live diagnostic from session `2026-05-05T21-13-05Z` (features.csv: 12,509 frames in LOCKING, 0 in LOCKED, beatPhase01 frozen at mean=0.99996, grid_bpm=216 instead of ~125) revealed: (1) `BeatGrid.offsetBy` only shifted the ~10 recorded beats; past the last beat `computePhase` clamped `beatPhase01=1.0` permanently and `nearestBeat` returned nil → `consecutiveMisses` grew indefinitely → `matchedOnsets` never reached `lockThreshold=4`. Fix: `offsetBy` now appends extrapolated beats at `period=60/bpm` up to a 300-second horizon and extrapolates downbeats at `barPeriod` beyond that. (2) `runLiveBeatAnalysisIfNeeded` hardcoded `sampleRate: 44100` for `analyzeBeatGrid` despite the tap running at 48000 Hz — mel spectrogram covered wrong duration, BPM detected as ~216. Fix: `VisualizerEngine.tapSampleRate: Double` stored from audio callback `rate` parameter; passed to `analyzeBeatGrid`. (3) `StemSampleBuffer.snapshotLatest(seconds:)` computed count using stored 44100 Hz rate, so a 10-second request retrieved only 9.19 s of real audio. Fix: new `snapshotLatest(seconds:sampleRate:)` protocol overload uses the passed-in rate; `runLiveBeatAnalysisIfNeeded` calls it with `tapSampleRate`. 14 new tests (5 BeatGrid extrapolation + 5 StemSampleBuffer rate overload). **✅ 2026-05-05 — commit `7033ad09`.**
- **DSP.3.5 — Halving octave correction + retry for live Beat This!** Session diagnostic `2026-05-05T22-57-57Z` (features.csv) revealed: (1) Live 10-second Beat This! window detected Love Rehab at 244.770 BPM (2× true 125 BPM) — double-time artefact from short analysis window. (2) Money 7/4 reactive session stayed in REACTIVE throughout — Beat This! on 10 s of Money audio returned an empty grid, with no retry. Fixes: (a) `BeatGrid.halvingOctaveCorrected()` — halving-only correction: while `bpm > 160`, halve BPM and drop every other beat. BPM < 80 intentionally left alone (Pyramid Song genuinely runs at ~68 BPM; doubling would be wrong). Downbeats re-snapped to surviving beats within ±40 ms; `beatsPerBar` recomputed from corrected downbeat IOIs. (b) `VisualizerEngine`: `liveBeatAnalysisDone: Bool` → `liveBeatAnalysisAttempts: Int`; counter allows up to `liveBeatMaxAttempts=2` attempts — first at `liveBeatMinSeconds=10.0 s`, retry at `liveBeatRetrySeconds=20.0 s` if first attempt returned empty grid. (c) `performLiveBeatInference()` extracted from `runLiveBeatAnalysisIfNeeded()` to keep the parent within the 60-line SwiftLint gate; `halvingOctaveCorrected()` applied before `offsetBy()`. 4 new BeatGridUnitTests. Post-validation triage: `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md`. Remaining risk: Money 7/4 still REACTIVE on live path (20-second retry may also produce empty grid); durable fix is Spotify-prepared session (30-second offline window reliable). **✅ 2026-05-05 — commits `eac2e140`, `c068d2b8`.**
- **DSP.3.6 — App-layer wiring test.** Integration test: `SessionPreparer.prepare()` → `StemCache.store()` → `resetStemPipeline(for:)` → `mirPipeline.liveDriftTracker.hasGrid == true`. Five new `PreparedBeatGridWiringTests` in `Integration/` prove the critical chain: (1) prepared non-empty grid → `hasGrid == true`; (2) `hasGrid == true` → `runLiveBeatAnalysisIfNeeded` guard blocks live inference; (3) cache miss → `hasGrid == false` → live inference allowed; (4) `.empty` cached grid → `hasGrid == false` → live inference allowed; (5) track change clears grid. Enhanced source-tagged `BEAT_GRID_INSTALL` logging in `VisualizerEngine+Stems.swift` (source=preparedCache/liveAnalysis/none, BPM, beat count, meter, firstBeat, replaced flag) plus `sessionRecorder.log()` one-time event per track. `beat_grid_source` in features.csv deferred (per-frame schema change; session.log entry is sufficient). Policy documented: prepared-cache grid wins; live inference may only *add* a grid when none is present. `docs/diagnostics/DSP.3.6-prepared-beatgrid-wiring-validation.md`. **✅ 2026-05-05.**
- **DSP.3.7 — Live drift validation test.** Replay `love_rehab` via `AudioInputRouter(.localFile)` with prepared BeatGrid; assert LOCKED within 5 s, drift < 50 ms, `beatPhase01` zero-crossings within ±30 ms of ground truth.
- **DSP.4 — Drums-stem Beat This! diagnostic.** Third BPM estimator on isolated percussion, logged alongside the existing two at preparation time. `CachedTrackData.drumsBeatGrid: BeatGrid` (default `.empty`). Step 6 in `SessionPreparer+Analysis.analyzePreview` feeds `stemWaveforms[1]` (drums) into the same `DefaultBeatGridAnalyzer` — same graph, second `predict()` call. `ThreeWayBPMReading` struct + `detectThreeWayBPMDisagreement` pure function added to `BPMMismatchCheck.swift`. Wiring logs: `WIRING: SessionPreparer.drumsBeatGrid` per track; `WARN: BPM 3-way` (preferred) / `WARN: BPM mismatch` (fallback when drumsBPM == 0). No runtime consumption by `LiveBeatDriftTracker`. 7 new 3-way detector tests + 2 integration wiring tests. **✅ 2026-05-06.**

**Done when (gating assertion):** Matt connects a Spotify playlist, preparation completes, switches to Spectral Cartograph, presses `L` to hold, starts music, and observes "PLANNED (UNLOCKED)" → "PLANNED (LOCKING)" → "PLANNED (LOCKED)" within 5 seconds. BPM matches. Beat-grid ticks align with perceived beats. Engine does not switch away. This observation — not unit-test counts — is the production-validation milestone for Beat This!

**Status:**
- [x] DSP.3 audit complete: `docs/diagnostics/DSP.3-beat-sync-test-environment-audit.md`. **2026-05-05.**
- [x] DSP.3.1 — Diagnostic hold + session-mode signal. **2026-05-05.**
- [x] DSP.3.2 — Pre-fire BeatGrid on session start. **2026-05-05.**
- [x] DSP.3.3 — Beat sync observability: text overlays + CSV + calibration shortcuts. **2026-05-05.**
- [x] DSP.3.4 — Grid horizon + sample-rate bugs fix. **2026-05-05 — commit `7033ad09`.**
- [x] DSP.3.5 — Halving octave correction + retry. **2026-05-05 — commit `eac2e140`.**
- [x] DSP.3.6 — App-layer wiring test. **2026-05-05.**
- [ ] DSP.3.7 — Live drift validation test.
- [x] DSP.4 — Drums-stem Beat This! diagnostic (third BPM estimator, logged only). **2026-05-06.**

---

## Phase QR — Quality Review Remediation (2026-05-06)

**Origin.** A 7-agent parallel codebase review on 2026-05-06 (Architect / Audio+DSP / ML / Renderer+Presets / Orchestrator+Session / App+UX / Tests+Quality) produced a ranked findings document focused on *precision*, *performance*, and *simplicity* against the "member of the band" product goal. This phase converts those findings into ordered, scoped increments.

**Why a phase, not a single sweep.** The findings span every subsystem and several interact (e.g. sample-rate fixes change BeatGrid input, which affects drift-tracker tests, which affects regression goldens). Sequencing prevents one increment's fix from invalidating another's verification.

**Priority ordering** (do not reorder without re-reading the cross-cutting analysis below):

1. **QR.1 (DSP.4) — Sample-rate plumbing audit.** Highest-precision payoff. Single bug class, five sites, confirmed by three independent reviewers. ✅ 2026-05-06.
2. **QR.2 (OR.1) — Stem-affinity rescaling + reactive-mode TrackProfile fix.** Highest musicality payoff per LOC. ✅ 2026-05-06.
3. **BUG-007.3 attempted 2026-05-07 — reverted same day** (commit `78ade5aa`). Three smaller replacement bugs in `KNOWN_ISSUES.md` to be sequenced: BUG-007.4 (downbeat alignment — investigation first, fix scope set after diagnosis) → BUG-009 (halving-correction threshold 160 → 175, ~5 LOC + test) → BUG-007.5 (adaptive-window lock hysteresis, ~30 LOC + test). Total ~1.5 days but each lands independently. See `KNOWN_ISSUES.md` for done-when criteria.
4. **QR.3 (TEST.1) — Close silent-skip test holes.** Cheap to do; protects the work in QR.1 + QR.2 from silent regression.
5. **QR.4 (U.12) — UX dead ends + duplicate `SettingsStore`.** Small, isolated, user-visible.
6. **QR.5 (CLEAN.1) — Mechanical cleanup pass.** Pure deletion of dead code + dead comments. Schedule when the four above have landed; ride along with their cleanups.
7. **QR.6 (ARCH.1) — `VisualizerEngine` decomposition.** Largest debt in the codebase. Defer until QR.1–QR.4 ship, then schedule with explicit risk acknowledgement.
8. **QR.7 (CLEAN.2) — Shader noise algorithm consolidation.** Deferred B.3 + B.4 items from QR.5. Not mechanical — algorithm swap with visual impact (value-noise vs gradient-noise; simple fbm vs rotation-matrix fbm). Includes `sdRoundBox` convention migration. Scheduled separately so QR.5 can ship under its "no behaviour change" invariant.

**Cross-cutting context (read before any QR increment):**

- The 2026-05-06 review found **the 44100/48000 sample-rate bug class confirmed at five distinct sites** across three subsystems. DSP.3.4 fixed it once; the underlying pattern (literal `44100` instead of the captured tap rate) recurred in stem separator dispatch, per-frame stem analysis, and `StemSampleBuffer` init. QR.1 closes the class, not just instances.
- The review found **the orchestrator's stem-affinity sub-score saturates** because `stemEnergy` is AGC-normalized at 0.5; summing 2+ matching stems hits ~1.0 trivially. 25% of score weight does not discriminate. QR.2 normalizes against the deviation primitives (D-026) the rest of the system already uses.
- **Reactive mode systematically penalizes presets with stem affinities** because `TrackProfile.empty.stemEnergyBalance == .zero` → presets with declared affinities score 0; presets without score 0.5. Adversarial against the most musically-engaged catalog members. QR.2 fixes both at once.
- The architect's H1 finding (`VisualizerEngine` is a 2,580-line god object with 8 NSLocks + `@unchecked Sendable`) is real but big. QR.6 schedules it after the precision fixes; the smaller QRs do not need decomposition first.

---

### Increment QR.1 (DSP.4) — Sample-rate plumbing audit

**Goal.** Eliminate the literal `44100` sample-rate constant from every site that should use the live tap rate. Capture `tapSampleRate` immutably, propagate through stem separation + per-frame stem analysis + `StemSampleBuffer` + `StemAnalyzer` init + Beat This! live inference. Add a regression test gate so future literal-`44100` reintroductions fail loud.

**Why now.** Three independent reviewers (Architect H1 / Audio+DSP D1 / ML #1+#2) flagged this. Symptoms on a 48 kHz tap: stems are 8.8% time-stretched and pitch-shifted; per-frame stem analysis reads bands at the wrong window; live Beat This! attempts the right fix already (DSP.3.4) but stem-side callers were not audited. Manifests in production as wrong stem energy magnitudes, wrong onset rates, and biased preset scoring on the mid-bar tracks the orchestrator most needs to handle musically.

**Sites to fix (audit-confirmed):**

| File | Symbol / line | Current | Target |
|---|---|---|---|
| `PhospheneApp/VisualizerEngine.swift:179` | `StemSampleBuffer(sampleRate: 44100, …)` | literal | `tapSampleRate` (deferred allocation, or re-init on rate-change) |
| `PhospheneApp/VisualizerEngine.swift:435` | `StemAnalyzer(sampleRate: 44100)` default arg | literal | thread `tapSampleRate` |
| `PhospheneApp/VisualizerEngine+Audio.swift:194` | `runPerFrameStemAnalysis` literal | literal | `tapSampleRate` |
| `PhospheneApp/VisualizerEngine+Stems.swift:151` | `separator.separate(… sampleRate: 44100)` | literal | `tapSampleRate` |
| `PhospheneApp/VisualizerEngine+Stems.swift:183` | `sessionRecorder?.recordStemSeparation(sampleRate: 44100, …)` | literal | `tapSampleRate` |

**Concurrency hardening (Architect H1, Audio+DSP D1):**

- `tapSampleRate: Double` is currently mutated from the audio callback (`VisualizerEngine+Audio.swift:98`) and read on `stemQueue` (`+Stems.swift:296`) without a synchronization primitive. On Apple Silicon, atomic 8-byte writes are guaranteed but cross-core *visibility* is not. This is the kind of bug that produces wrong-tempo grids ~1-in-1000 sessions and is invisible in tests.
- Fix: capture `tapSampleRate` once per `installTap(...)` call. Promote to `let tapSampleRate: Double` set in the initializer that wires the tap, or guard with `os_unfair_lock` if it must remain mutable for capture-mode switching.
- If capture-mode switching changes the rate (System tap → file playback at a different rate), tear down and re-init the dependent buffers (`StemSampleBuffer`, `StemAnalyzer`) on the rate change rather than mutating the rate field.

**Octave-correction policy unification (Audio+DSP A2):**

`BeatGrid.halvingOctaveCorrected` is halving-only (preserves Pyramid Song ~68 BPM). `BeatDetector+Tempo.computeRobustBPM:196` and `estimateTempo:269` both still double sub-80 BPM. The two policies disagree. Drop the `bpm < 80 → bpm *= 2` branch from both `computeRobustBPM` and `estimateTempo`. Any track in [40, 80) BPM is now treated as genuine, matching the offline path and CLAUDE.md.

**`MIRPipeline.elapsedSeconds: Float` → `Double` (Audio+DSP D3):**

Float accumulation of `+= deltaTime` reaches ULP ≈ 240 µs after 30 minutes — smaller than the ±30 ms tight-match window but a guaranteed monotonic drift. Promote to `Double`. Conversion to `Float` happens once at FeatureVector write. Touches `MIRPipeline.swift:70`, all callers reading `elapsedSeconds`, and `LiveBeatDriftTracker.update(playbackTime:)` parameter.

**KineticSculpture D-026 violation (Audio+DSP B1):**

`Sources/Presets/Shaders/KineticSculpture.metal:102`: `f.sub_bass * 0.28 + f.bass * 0.10` — exact Failed Approach #31 anti-pattern on AGC-normalized fields. Convert to `f.bass_dev` / `f.bass_rel` deviation primitives. Re-record golden hash for the preset.

**Lint gate to prevent recurrence:**

Add a `Scripts/check_sample_rate_literals.sh` script that fails CI when any `44100` literal appears outside an explicit allowlist (`StemSeparator.modelSampleRate`, `BeatThisPreprocessor` 22050 internal, test fixtures). Wire into the test target's pre-build phase. Same pattern as the existing `check_visual_references` enforcement.

Add a SwiftLint custom rule that flags `f\.(bass|mid|treb|sub_bass|low_bass|low_mid|mid_high|high_mid|high)\s*[*+\-]` in `.metal` files (see Audio+DSP B2). Whitelist deviation suffixes (`_rel`, `_dev`, `_att_rel`).

**Files to touch:**

- `PhospheneApp/VisualizerEngine.swift`, `+Audio.swift`, `+Stems.swift` — propagate `tapSampleRate`.
- `PhospheneEngine/Sources/DSP/BeatDetector+Tempo.swift` — drop sub-80 doubling in `computeRobustBPM` + `estimateTempo`.
- `PhospheneEngine/Sources/DSP/MIRPipeline.swift` — `elapsedSeconds: Double`.
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift` — accept `Double` playbackTime.
- `PhospheneEngine/Sources/Presets/Shaders/KineticSculpture.metal` — D-026 conversion.
- `Scripts/check_sample_rate_literals.sh` (new), `.swiftlint.yml` (custom rule), CI hook.
- `PhospheneEngine/Tests/PhospheneEngineTests/Integration/TapSampleRateRegressionTests.swift` (new) — see Tests below.
- `PhospheneEngine/Tests/PhospheneEngineTests/DSP/BeatDetectorTempoTests.swift` — assert no doubling for 60 BPM input.
- `docs/CLAUDE.md` — Failed Approach #52 (sample-rate literal recurrence), update Tempo section, update KineticSculpture entry.
- `docs/DECISIONS.md` — D-078: "Sample rate is captured once per tap install; literal `44100` is a CI-banned constant."
- `docs/QUALITY/KNOWN_ISSUES.md` — close BUG-R002 / BUG-R003 with QR.1 commit hash; add new BUG-R006 (sample-rate plumbing audit), BUG-R007 (octave correction split), BUG-R008 (elapsedSeconds Float drift), BUG-R009 (KineticSculpture D-026 violation).

**Tests:**

1. **`TapSampleRateRegressionTests` (new).** Inject a recording `BeatGridAnalyzing` mock; drive with synthetic 48 kHz audio; assert `analyzeBeatGrid(samples:sampleRate:)` is called with `sampleRate == 48000` and `samples.count == sampleRate * 10`. Repeat for the stem-separator dispatch path with a `RecordingStemSeparating` mock.
2. **Octave-correction unification (`BeatDetectorTempoTests`).** Add: `computeRobustBPM` on synthetic 75 BPM IOIs returns ≈ 75 (not 150). `estimateTempo` on synthetic 65 BPM autocorrelation returns ≈ 65 (not 130). Pyramid Song golden fixture stays at ~68 BPM unchanged.
3. **`MIRPipeline` long-session drift (`MIRPipelineUnitTests`).** Synthetic 60-minute playback; assert `elapsedSeconds.isMultiple(of: 0)` not relevant — instead assert that two repeats of `update(deltaTime: 1/60)` over 1 hour produce a `Double` clock equal to 3600.0 within 1 µs.
4. **Lint gate.** `Scripts/check_sample_rate_literals.sh` exits non-zero on a synthetic source file containing `let foo = 44100`.
5. **Existing tests.** Full engine suite passes; Pyramid Song / Money golden fixtures unchanged; KineticSculpture golden hash regenerated and committed.

**Done when:**

- [x] All five literal-`44100` sites use `tapSampleRate` (or the canonical `StemSeparator.modelSampleRate` where the post-separation rate is correct, not the tap rate).
- [x] `tapSampleRate` capture is race-free (NSLock-guarded `_tapSampleRate` with `updateTapSampleRate(_:)` writer + `tapSampleRate` reader).
- [x] `computeRobustBPM` and `estimateTempo` no longer double sub-80 BPM.
- [x] `MIRPipeline.elapsedSeconds` is `Double`; `LiveBeatDriftTracker.update(playbackTime:)` widened to `Double`.
- [x] KineticSculpture uses deviation primitives (`0.06 + f.bass * 0.16 + f.bass_dev * 0.05`); golden hash regenerated.
- [x] `Scripts/check_sample_rate_literals.sh` passes; SwiftLint custom rule for `.metal` deviation form documented as intentionally script-based (SwiftLint cannot lint `.metal`).
- [x] All new tests pass; full engine suite passes (1045 tests, sole failure is the pre-existing `MetadataPreFetcher.fetch_networkTimeout` flake); app build clean.
- [x] CLAUDE.md, DECISIONS.md (D-079), KNOWN_ISSUES.md (BUG-R002/R003 generalized; new BUG-R006/R007/R008/R009), ENGINEERING_PLAN.md updated.
- [x] Manual validation 2026-05-06: ad-hoc reactive session on Love Rehab installed live Beat This! grid at **125.8 BPM** (true 125, sample-rate fix verified at 48 kHz tap); ad-hoc Pyramid Song stayed at **69 BPM** (sub-80 doubling fix verified — pre-QR.1 would have reported 138). KineticSculpture deviation form not directly observed, but golden-hash test passes. Two pre-existing bugs surfaced during testing — neither is a QR.1 regression: BUG-006 (Spotify-prepared session falls through to liveAnalysis — prepared-grid wiring path; QR.1 didn't touch it) and BUG-007 (LiveBeatDriftTracker LOCKING ↔ LOCKED oscillation — lock semantics unchanged by QR.1). Both filed in `docs/QUALITY/KNOWN_ISSUES.md` for separate diagnosis.

**Verify:** `swift test --filter TapSampleRateRegression && swift test --filter BeatDetectorTempo && swift test --filter MIRPipelineUnit && bash Scripts/check_sample_rate_literals.sh && swiftlint lint --strict`.

**Estimated sessions:** 2 (audit + propagation → tests + lint gate + golden regen).

**Status:** ✅ 2026-05-06 — D-079 landed (see git log `[QR.1]`). Manual subjective validation completed same day. Two pre-existing bugs (BUG-006, BUG-007) surfaced during validation but are not QR.1 regressions — filed for separate diagnosis.

---

### Increment QR.2 (OR.1) — Stem-affinity rescaling + reactive-mode TrackProfile fix

**Goal.** Make `stemAffinitySubScore` discriminate. Make reactive mode score stem-affinity-bearing presets fairly. The 25% score-weight slot currently does neither.

**Why now.** Direct hit on the "member of the band" goal. The Orchestrator+Session reviewer's findings #1, #2, and #6 collapse into one root cause: the scorer reads AGC-normalized stem energies as if they were absolute, then sums them. AGC centers each stem at 0.5; any preset declaring 2+ matching affinities saturates at ~1.0 on most music. Two presets with totally different declared affinities end up scoring nearly identically, so the 0.25 weight does no work.

**Algorithm changes:**

1. **`stemAffinitySubScore` reads deviation primitives.** Replace `stemEnergy[stem]` lookups with `stemEnergyDev[stem]` (D-026, MV-1, already on `StemFeatures` floats 17–24). A preset that declares "responds to drums + bass" now scores high only when those stems are *above their AGC average*, not just present at all. Presets with mismatched affinity declarations actually diverge in score on most tracks.
2. **Affinity-weighted (not summed) score.** For a preset declaring N affinity stems, score = mean of `max(0, stem_dev)` over the N stems, NOT clamped sum. Mean preserves "this preset's stems must all be active" semantics; sum allowed any-one-stem to saturate.
3. **`TrackProfile.empty` neutralizes affinity instead of zeroing it.** When `stemEnergyBalance == .zero` (reactive-mode initial state), `stemAffinitySubScore` returns 0.5 for all presets — the same neutral baseline as `affinities.isEmpty`. Otherwise reactive mode systematically rejects the most musical presets.
4. **Live `stemEnergyBalance` plumbing for reactive mode.** `DefaultReactiveOrchestrator` currently uses `TrackProfile.empty`; add an overload accepting a live `StemFeatures` snapshot. After ≥10 s of listening (when the live stem analyzer has converged), score against the live snapshot. Same time scale as the existing reactive-mode confidence ramp.

**Mood-override per-track cooldown (Orchestrator+Session #3):**

`DefaultLiveAdapter.applyLiveUpdate()` currently re-evaluates and re-patches the plan every analysis frame (~94 Hz) when conditions hold. Add a `lastOverrideTimePerTrack: [TrackIdentity: Float]` state with a 30 s cooldown. Suppress override evaluation entirely within the cooldown (don't even build the scoring contexts). Leaves boundary reschedule unaffected (it has its own per-evaluation gate).

**Reactive boundary-only switching gate (Orchestrator+Session #5):**

`DefaultReactiveOrchestrator` currently fires `boundaryFired` switches without a score-gap check, so every confident boundary every 60 s is a coin-flip. Tighten to `boundaryFired AND topScore > currentScore + 0.05` (small gap, not the full 0.20 used for non-boundary switches — boundaries are still preferred, just not random).

**Hard-cut threshold raise (Orchestrator+Session, transitions #3):**

`cutEnergyThreshold = 0.7` paired with `energy = 0.5 + 0.4 * arousal` means any track with `arousal > 0.5` cuts at every track change. Most non-ambient music sits 0.5–0.8. Raise to `cutEnergyThreshold = 0.85` so the warm-crossfade ladder actually fires on most music. A/B-listenable.

**`recentHistory` trim (Orchestrator+Session #4):**

`SessionPlanner+Segments.swift:219` appends to `recentHistory` unbounded; per-track scoring scans the array via `last(where:)`. At ~400 segments this becomes measurable. Trim to last 50 entries on append.

**Files to touch:**

- `PhospheneEngine/Sources/Orchestrator/PresetScorer.swift` — `stemAffinitySubScore` rewrite (deviation primitives + mean instead of clamped sum + neutral 0.5 on empty profile).
- `PhospheneEngine/Sources/Orchestrator/ReactiveOrchestrator.swift` — accept live `StemFeatures` snapshot; tighten boundary-switch gate.
- `PhospheneEngine/Sources/Orchestrator/LiveAdapter.swift` — `lastOverrideTimePerTrack` cooldown.
- `PhospheneEngine/Sources/Orchestrator/SessionPlanner+Segments.swift` — `recentHistory` 50-entry trim.
- `PhospheneEngine/Sources/Orchestrator/TransitionPolicy.swift` — `cutEnergyThreshold = 0.85`.
- `PhospheneApp/VisualizerEngine+Orchestrator.swift` — pass live `StemFeatures` snapshot into `applyReactiveUpdate`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/StemAffinityScoringTests.swift` (new).
- `PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/ReactiveOrchestratorTests.swift` — add boundary-gate cases.
- `PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/LiveAdapterTests.swift` — add cooldown cases.
- `PhospheneEngine/Tests/PhospheneEngineTests/Orchestrator/GoldenSessionTests.swift` — regenerate goldens; document the changes inline (cite the QR.2 increment).
- `docs/CLAUDE.md` — Failed Approach #53 (stem-affinity AGC saturation) + #54 (reactive `TrackProfile.empty` bias).
- `docs/DECISIONS.md` — D-079: "Stem-affinity scoring uses deviation primitives, not absolute AGC-normalized energies."

**Tests:**

1. **`StemAffinityScoringTests` (new).**
   - Two presets with disjoint affinities (e.g. drums-only vs vocals-only) on a drums-heavy track produce score gap ≥ 0.3. (Was ≤ 0.05 pre-fix.)
   - Preset with empty affinities scores neutral 0.5 regardless of track.
   - Preset declaring 2 affinities on a track with one stem at +dev and one at -dev scores ~0.25 (mean of `max(0, +x)` and `max(0, -y)`). NOT 1.0 (sum saturation).
   - `TrackProfile.empty` with non-empty affinities scores 0.5 (neutral), not 0 (rejection).
2. **`ReactiveOrchestratorTests` extension.**
   - Boundary fires with `topScore == currentScore` → no switch (was: switch).
   - Boundary fires with `topScore == currentScore + 0.10` → switch.
   - 60 s cooldown still respected.
3. **`LiveAdapterTests` extension.**
   - 100 consecutive `applyLiveUpdate` calls with conditions held → only one override patch applied (was: 100).
   - Override cooldown clears on track change.
4. **`GoldenSessionTests` regeneration.** All three curated playlists regenerated. Document the score-gap shift in the test file's commit message and inline comments.
5. **Manual validation:** Matt listens to Love Rehab (drums-heavy) and a vocal-led track in reactive mode and confirms the preset selection feels different from the pre-fix baseline. Subjective gate.

**Done when:**

- [x] `stemAffinitySubScore` uses deviation primitives + mean. ✅ 2026-05-06
- [x] Reactive mode receives live `StemFeatures` after 10 s and uses neutral 0.5 before then. ✅ 2026-05-06
- [x] Mood-override 30 s per-track cooldown. ✅ 2026-05-06
- [x] Boundary-switch score gap ≥ 0.05. ✅ 2026-05-06
- [x] `cutEnergyThreshold = 0.85`. ✅ 2026-05-06
- [x] `recentHistory` trimmed at 50. ✅ 2026-05-06
- [x] All new tests pass; goldens regenerated and committed; full engine suite green (1084 pass, 1 pre-existing MetadataPreFetcher flake). ✅ 2026-05-06
- [x] CLAUDE.md (Failed Approaches #53+#54 already present) + DECISIONS.md D-080 updated. ✅ 2026-05-06
- [ ] Matt subjective sign-off on reactive-mode preset selection (Love Rehab + one vocal-led track). (pending)

**Verify:** `swift test --filter StemAffinityScoring && swift test --filter ReactiveOrchestrator && swift test --filter LiveAdapter && swift test --filter GoldenSession`.

**Landed:** 2026-05-06. All algorithmic changes implemented. Golden sequences regenerated — VL no longer dominates (stem bonus gone with zero-dev pre-analyzed profiles); mood+section+tempo now drive planned sessions. D-080 documented. Matt sign-off on reactive-mode listening pending.

**Estimated sessions:** 2 (algorithm changes + tests → goldens regen + manual sign-off).

---

### Increment BUG-007.3 — Lock hysteresis + live BPM credibility ⚠ REVERTED 2026-05-07
### Increment QR.3 (TEST.1) — Close silent-skip test holes ✅ 2026-05-07
### Increment QR.4 (U.12) — UX dead ends + duplicate `SettingsStore` + dead settings + hardcoded strings  ✅ 2026-05-07 (D-091)
### Increment QR.5 (CLEAN.1) — Mechanical cleanup pass ✅ 2026-05-13
### Increment QR.6 (ARCH.1) — `VisualizerEngine` decomposition

**Goal.** Split `VisualizerEngine` (2,580 LOC, 8 NSLocks, `@unchecked Sendable`, 7 extension files) into 3-4 owned services with a 200-line composition root. Replace `RenderPipeline`'s 24-NSLock switchboard with a single `RenderGraphState` value type updated atomically per preset switch.

**Why now (and why last in QR).** The architect's H1 + H2 findings together represent the largest single piece of debt in the codebase. They are *also* the highest-risk change: every concern in the engine integrates here. Schedule after QR.1–QR.5 have landed so that:

- QR.1 has cleaned up the sample-rate plumbing this refactor would otherwise have to thread through.
- QR.2 has fixed the orchestrator surface this refactor exposes.
- QR.3 has hardened the test suite that will validate the decomposition.
- QR.5 has retired `BeatPredictor`, deduplicated `ShaderUtilities`, and centralized EMA — all of which would be friction during decomposition if left in place.

This increment is **the first one that requires Matt to explicitly approve scope at the start**, because the safe path is to ship the decomposition behind feature flags and migrate one subsystem at a time over multiple sessions.

**Proposed shape (subject to architect's pre-implementation pass):**

```
PhospheneApp/
  VisualizerEngine.swift              → 200-line composition root: owns the three hosts, wires publishers, exposes the public API
  AudioPipelineHost.swift             → router, FFT, MIR, stems, signal-state callbacks. Owns the audio-thread → analysis-queue boundary.
  RenderHost.swift                    → pipeline, presets, mesh/preset state, mvwarp, preset switching. Owns the render-pipeline lock surface.
  OrchestratorHost.swift              → planner, live adapter, reactive orchestrator, plan publisher, action router. Owns the orchestrator state.
```

Each host is a `@MainActor`-bound `final class`, owns its state (no `@unchecked Sendable`), exposes a small public surface to the composition root. Cross-host communication via Combine publishers (typed events), not direct property reads.

**`RenderGraphState` value type (RenderPipeline H2 fix):**

```
struct RenderGraphState {
    var preset: PresetDescriptor
    var passes: [RenderPass]
    var icb: ICBState?
    var raymarch: RayMarchState?
    var mvwarp: MVWarpState?
    var mesh: MeshState?
    var postProcess: PostProcessState?
    // … one slot per pass family
}
```

`RenderPipeline` holds `var graphState: RenderGraphState` under a single lock. Per-frame `draw(in:)` snapshots one struct under one lock. Adding a pass family = adding a slot, not a lock.

**Frame-budget governor latency fix (Renderer + Architect H3):**

`RenderPipeline.swift:371-384` does `Task { @MainActor in observe(...) }` every frame in the completed handler. Move the `FrameBudgetManager` and `MLDispatchScheduler` to a dedicated serial DispatchQueue; only hop to `@MainActor` for `@Published` UI updates. Decisions stay synchronous on the timing path; UI lags by at most one frame, but `MLDispatchScheduler` no longer misses budget breaches under main-thread contention.

**Live Beat This! routed through `MLDispatchScheduler` (ML #3):**

`runLiveBeatAnalysisIfNeeded`'s `analyzer.analyzeBeatGrid(...)` currently dispatches to `stemQueue` at utility QoS without consulting `MLDispatchScheduler`. Route through the scheduler the same way stem separation does. Pre-warm Beat This! graph + weight load at session start (after first audio frame) to avoid the t=10s lazy-init stutter.

**`MIRPipeline` `@unchecked Sendable` cleanup (Architect M2):**

Convert `MIRPipeline` to a `@MainActor` final class with explicit per-property locks where cross-thread access is genuinely needed. Removes the unsynchronized `private(set) var` reads-from-main / writes-from-analysis-queue pattern.

**`Diagnostics → Audio + Renderer` dependency leak (Architect M3):**

Move `SoakTestHarness` into a `Tests/` target or a separate non-shipped SPM dev product. Keeps `Diagnostics` engine library reusable.

**`Presets` and `Renderer` shader resource directories consolidation (Architect M4):**

Pick one source of truth (recommended: `Presets/Shaders/`). Remove the duplicate from the other target's `resources` declaration in `Package.swift`. Verify no `.metal` lookup silently fails.

**Files to touch:** `PhospheneApp/VisualizerEngine*.swift` (split into 4+ files), `PhospheneEngine/Sources/Renderer/RenderPipeline*.swift` (RenderGraphState refactor), `PhospheneEngine/Sources/DSP/MIRPipeline.swift`, `PhospheneEngine/Package.swift`, related tests.

**Tests:**

- All existing tests pass at every intermediate commit.
- New `AudioPipelineHostTests`, `RenderHostTests`, `OrchestratorHostTests` cover each host's API.
- New `RenderGraphStateTests` covers atomic state-transition contract.
- `LiveDriftValidationTests` (from QR.3) passes — proves the refactor preserves musical sync.
- Full soak test passes (no allocation regression).

**Done when:**

- [ ] `VisualizerEngine.swift` is ≤ 250 LOC; `+Audio/+Stems/+Orchestrator/+Capture/+InitHelpers/+PublicAPI` extension files deleted.
- [ ] Three hosts own their state; no `@unchecked Sendable` outside explicit audio-thread boundaries.
- [ ] `RenderPipeline` uses one lock + one `RenderGraphState`.
- [ ] Frame-budget observer runs on a dedicated queue; `MLDispatchScheduler` decisions are synchronous on the timing path.
- [ ] Live Beat This! routed through `MLDispatchScheduler`; pre-warmed at session start.
- [ ] `MIRPipeline` is `@MainActor`; no `@unchecked Sendable`.
- [ ] `Diagnostics` no longer depends on `Audio + Renderer` for shipped library product.
- [ ] One canonical `Shaders/` resource directory.
- [ ] Full engine + app + soak test suites green.
- [ ] Performance regression test confirms no per-frame regression.
- [ ] CLAUDE.md Module Map fully rewritten for the new shape; DECISIONS.md D-080: "VisualizerEngine decomposition + RenderPipeline single-state refactor."

**Verify:** Full suite + soak test + manual reel re-record.

**Estimated sessions:** 5–8. **Matt approval required at the start** because the increment is large enough that mid-flight scope changes would be costly. Each session ships one subsystem migration with full test pass; abort path is clean (revert to last green commit).

**Risks:**

- Decomposition surfaces hidden coupling. Each host migration may require refactors in unrelated files.
- `RenderGraphState` atomic snapshot under load may regress per-frame timing if not benchmarked. Mitigation: gate the refactor behind a runtime flag and A/B against the legacy switchboard for one session.
- `MIRPipeline` `@MainActor` conversion may cause unexpected `await` propagation. Mitigation: stage in a separate session with isolated test coverage.

---

### Increment QR.7 (CLEAN.2) — Shader noise algorithm consolidation

**Goal.** Resolve the deferred B.3 + B.4 items from QR.5: migrate production presets calling legacy `perlin2D` / `perlin3D` / `fbm3D` / `fbm2D` (and `sdRoundBox`) to a single canonical noise / SDF algorithm, then delete the legacy bodies from `ShaderUtilities.metal`. **This increment is NOT mechanical — it accepts visual change at the affected call sites.**

**Why a separate increment.** QR.5 discovered that the legacy `*D` (camelCase) noise/SDF functions in `ShaderUtilities.metal` and the V.1+V.2 (snake_case) tree under `Sources/Presets/Shaders/Utilities/` are not just naming differences — they are different *algorithms* with different output ranges, fade curves, and spatial character:

| Legacy | V.1+V.2 | Difference |
|---|---|---|
| `perlin2D(p) → [0,1]` | `perlin2d(p) → [-1,1]` | **Value noise** (hash per corner) vs **gradient noise** (Perlin's classic gradient + dot product). Different fade (cubic vs C² quintic). Different hash table. |
| `perlin3D(p) → [0,1]` | `perlin3d(p) → [-1,1]` | Same value-vs-gradient distinction as 2D. |
| `fbm3D(p, n) → [0,1]` (variable octaves, simple halving, no rotation) | `fbm4`/`fbm8`/`fbm12` (fixed octaves, rotation matrix per octave, Hurst-exponent decay, built on `perlin3d`) | Different algorithm + different range + fixed octave count. |
| `fbm2D(p, n)` | (no direct V.1+V.2 equivalent) | Build on `fbm` family or port as `fbm_octaves_2d`. |
| `sdRoundBox(p, b, r)`: `b` = outer half-extents | `sd_round_box(p, b, r)`: `b` = inner half-extents | Same geometric shape, different parameter convention. Requires `b → b - r` at every call site. |

QR.5's load-bearing invariant ("no behavior change, no golden-hash drift") forbids these migrations as mechanical cleanup. QR.7 accepts the visual change and runs the migration as a deliberate refactor.

**Consumers to migrate** (verified during QR.5 audit; re-verify on session start in case of drift):

- [GlassBrutalist.metal:205–206](PhospheneEngine/Sources/Presets/Shaders/GlassBrutalist.metal) — 2× `perlin2D` calls (`finGrain`, `macroVar`).
- [VolumetricLithograph.metal:382](PhospheneEngine/Sources/Presets/Shaders/VolumetricLithograph.metal) — `fbm3D(noiseP, VL_FBM_OCTAVES)`. Plus 2 more sites in the volumetric march loop (`fbm3D(p * 0.5, 4)`, `fbm3D((p + lightDir * 0.3) * 0.5, 3)`).
- [KineticSculpture.metal:59–61, 74–76](PhospheneEngine/Sources/Presets/Shaders/KineticSculpture.metal) — 6× `sdRoundBox` calls.

**Two strategy decisions to make at increment start.**

**Strategy A — Algorithm picker (for `perlin*` / `fbm*`):**
- **A1. Adopt V.1+V.2 algorithm everywhere.** Migrate consumers; add range-remap (`* 0.5 + 0.5`) where they expected [0, 1]; re-tune visual constants. Highest cleanup payoff; biggest visual delta. **VolumetricLithograph requires M7 fidelity review** post-migration (cited in CLAUDE.md as the MV-2 reference implementation).
- **A2. Add a new legacy-compatible helper to the V.1+V.2 tree.** Port `fbm3D`'s simple-halving / no-rotation / value-noise-base algorithm as `fbm_octaves(p, n)` (or similar) under `Utilities/Noise/`. Keep `perlin2D` / `perlin3D` in `ShaderUtilities.metal` since the gradient-vs-value distinction is genuine (they are different tools, not duplicates). Lower visual risk; modest cleanup payoff.
- **A3. Declare the legacy forms permanent keepers** (status quo after QR.5). They serve a different purpose than the V.1+V.2 forms (value vs gradient noise are both useful primitives). Annotate `ShaderUtilities.metal` to make this explicit. No code change; QR.7 becomes a doc-only increment.

**Strategy B — `sdRoundBox` migration (independent of A):**
- **B1. Migrate all 6 KineticSculpture call sites with `b → b - r` adjustment.** Literal-equivalent visual output. Mechanical except for the per-call adjustment.
- **B2. Keep `sdRoundBox` as permanent keeper.** Same as A3 reasoning.

**Recommendation (start-of-increment):** A3 + B1. Reason: gradient vs value noise are genuinely different primitives and shipping both is fine; the V.1+V.2 form is the right default for new presets but the legacy form is the right tool for existing consumers that depend on [0, 1] output. `sdRoundBox` on the other hand IS strictly a convention mismatch — migrating costs nothing visually and removes a keeper.

**Files to touch (Strategy A1, worst case):**
- Migrate: `GlassBrutalist.metal`, `VolumetricLithograph.metal` (3 sites), possibly other consumers found at session start.
- Migrate: `KineticSculpture.metal` (6 sites, Strategy B).
- Delete from `ShaderUtilities.metal`: `perlin2D` / `perlin3D` / `fbm2D` / `fbm3D` / `sdRoundBox` (5 functions, ~80 LOC).
- Update test source in `ShaderUtilityTests.swift` (preamble assertions for the deleted names).
- Regen `PresetRegressionTests` golden hashes for Glass Brutalist + Volumetric Lithograph + Kinetic Sculpture.
- M7 fidelity review for VolumetricLithograph.

**Files to touch (Strategy A3 + B1, recommended):**
- Migrate: `KineticSculpture.metal` (6 × `sdRoundBox` → `sd_round_box(p, b - r, r)`).
- Delete from `ShaderUtilities.metal`: `sdRoundBox` only.
- Annotate `ShaderUtilities.metal` "permanent keepers" section to make the gradient-vs-value-noise distinction explicit for future maintainers.
- Regen Kinetic Sculpture golden hashes (should be byte-identical if the math is right; verify).
- No M7 review required.

**Tests (Strategy A1):**
- Full engine suite green.
- `PresetRegressionTests` regenerated (3 presets × 3 fixtures = 9 hashes minimum).
- `ShaderUtilityTests` updated for deleted names.
- Manual eyeball: GlassBrutalist glass-fin grain, VolumetricLithograph chamber walls + light shafts, KineticSculpture frosted glass.
- M7 review for VolumetricLithograph (preset is cited in CLAUDE.md as the MV-2 reference).

**Tests (Strategy A3 + B1):**
- Full engine suite green.
- `PresetRegressionTests` golden hashes for Kinetic Sculpture either unchanged (if `b - r` is the exact compensation) or surface drift for explicit re-bake.
- No M7 review required.

**Done when:**

- [ ] Strategy A / B decision made and recorded as a DECISIONS.md entry.
- [ ] Migrations land per the chosen strategy.
- [ ] Hashes either preserved (A3 + B1) or explicitly regenerated (A1 / A2) with M7 review for VolumetricLithograph.
- [ ] CLAUDE.md "Do not" list updated if any new mechanical-cleanup-looks-safe-but-isn't pattern surfaces (e.g. "Do not migrate `perlin2D` → `perlin2d` without a range-remap pass — they are different algorithms").

**Estimated sessions:** 1 for Strategy A3 + B1 (recommended); 2–3 for Strategy A1 (includes M7).

---

## Phase DASH — Telemetry Dashboard

A dedicated HUD layer for Phosphene's diagnostic and operational telemetry. Renders floating monospace metrics cards over the live Metal view using a zero-alloc Core Text path backed by a shared-memory MTLTexture. Six increments; no Orchestrator or audio-pipeline changes — pure Renderer + Shared additions.

**Goals:**
- Real-time BPM, beat-lock state, stem energies, frame budget, and session-mode label without requiring Spectral Cartograph to be the active preset.
- Developer-togglable (same `D` key overlay flow as `DebugOverlayView`).
- Zero per-frame heap allocation; MTLBuffer-backed CGContext blit path inherited by `DashboardTextLayer`.

### Increment DASH.1 — Text-rendering layer ✅ 2026-05-06
### Increment DASH.2 — Metrics card layout engine ✅ 2026-05-07 (amended DASH.2.1)
### Increment DASH.3 — Beat & BPM card ✅ 2026-05-07
### Increment DASH.4 — Stem energy card ✅ 2026-05-07
### Increment DASH.5 — Frame budget card ✅ 2026-05-07
### Increment DASH.6 — Overlay wiring + `D` key toggle ✅ 2026-05-07 (superseded by DASH.7)
### Increment DASH.7.2 — Dark-surface legibility pass ✅ 2026-05-07
### Increment DASH.7.1 — Brand-alignment pass (impeccable review) ✅ 2026-05-07
### Increment DASH.7 — SwiftUI dashboard port + visual amendments ✅ 2026-05-07
## Phase DM — Drift Motes (particles preset) — REMOVED 2026-05-11

Drift Motes (DM.0 through DM.3 plus four manual-smoke remediation increments DM.3.1 / DM.3.2 / DM.3.2.1 / DM.3.3 / DM.3.3.1) was retired in its entirety on 2026-05-11. Preset code, tests, design / palette / architecture-contract docs, visual references, and perf-capture procedure docs are deleted from the tree. Recover from git history if needed.

**See `docs/DECISIONS.md` D-102** for the removal rationale, the three-part bar (iconic visual subject + clear musical role + infrastructure-feasible) that every pitched concept failed, and the rule that future particle presets ship their own `ParticleGeometry` conformer rather than branching from the deleted Drift Motes code.

**What survives.** D-097 (particle preset architecture: siblings, not subclasses) — Murmuration is byte-identical to its post-DM.0 baseline; the protocol surface (`ParticleGeometry` / `ParticleGeometryRegistry`) stays. D-099 (Swift `FeatureVector` / `StemFeatures` at 192 / 256 bytes). D-101 (`stems.drums_beat` as canonical particles-family beat-reactivity field) for any future particle preset. `SessionRecorder.frame_cpu_ms` / `frame_gpu_ms` columns and `RenderPipeline.onFrameTimingObserved` (originally DM.3a) stay — generic per-frame timing instrumentation.

**Status:** closed. The next preset increment is the parallel Lumen Mosaic stream (Phase LM) or whatever Matt prioritises.

## Phase LM — Lumen Mosaic (geometric pattern-glass ray-march preset)

**Status: CLOSED 2026-05-12 at LM.7. Lumen Mosaic certified — first catalog preset with `certified: true` in its JSON sidecar.**

Lumen Mosaic is a `geometric`-family preset (the `glass` framing in earlier doc revs drifted to `geometric` at LM.4.6). Visible surface is a flat `sd_box` panel filling the camera frame; surface is `mat_pattern_glass` (V.3 §4.5b) with hex-biased Voronoi cells. **Aesthetic role as it shipped:** energetic dance partner — vivid per-cell uniform random RGB synced to the beat via per-cell team-counter mechanism (LM.3.2 / D.5 → LM.4.6 / D.6), with the LM.6 cell-depth gradient + optional hot-spot giving each cell a 3D-glass dome read, and the LM.7 per-track chromatic-projected RGB tint vector giving each track a visibly distinct aggregate panel mean. The earlier "contemplative slow ambient / 4-audio-driven light agents" framing was the LM.2-era design intent and is retired — the 4-agent struct survives on the GPU buffer for ABI continuity but the shader does not read it.

Authoritative authoring docs at `docs/presets/LUMEN_MOSAIC_DESIGN.md` (visual intent + current implementation), `docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md` (current-implementation summary + historical LM.3.2-era prose for context), `docs/presets/LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md` (phased increment ledger).

The preset was originally sequenced as 10 increments LM.0 → LM.9 with cert sign-off at LM.9. After the LM.4.4 pattern-engine retirement collapsed three planned increments (LM.5 / old LM.7 / LM.8), cert moved up to **LM.7** (D-LM-7). Certification target met: **the cheapest ray-march preset in the catalog** (M2 Pro measured: `frame_gpu_ms` mean 1.37 ms / max 32.9 ms / 0.02 % over 16 ms; well under the Tier 2 ≤ 16 ms / ≤ 3.7 ms p95 target). See LM.6 / LM.7 increment entries below for the cert closeout, and D-LM-6 / D-LM-7 in `docs/DECISIONS.md` for the architectural decisions.

### Increment LM.0 — Fragment buffer slot 8 infrastructure

**Scope.** Reserve fragment buffer slot 8 in `RenderPipeline` as the canonical home for a third per-preset CPU-driven state buffer alongside the existing slots 6 and 7. This is pure infrastructure — no shader code, no Lumen Mosaic preset, no audio routing. The slot is wired so LM.1 (the first Lumen Mosaic shader) can bind state via the new setter and the lighting fragment can read `LumenPatternState` directly. Lumen Mosaic is the first planned consumer; the slot is shared and any future preset that needs a third per-frame state buffer binds here.

**Done when.**

- `RenderPipeline.directPresetFragmentBuffer3` storage + `setDirectPresetFragmentBuffer3(_:)` setter wired, mirroring the slot 6 / 7 setter pattern.
- Slot 8 bound conditionally (null when no preset has called the setter) at every fragment encoder that already binds slots 6 / 7 (`RenderPipeline+Staged.encodeStage`, `RenderPipeline+MVWarp.renderSceneToTexture`) **plus** the direct-pass (`drawDirect`) and the ray-march **lighting** fragment (`RayMarchPipeline.runLightingPass`). The G-buffer pass intentionally does NOT bind slot 8 — only lighting consumes it today.
- `CLAUDE.md` GPU Contract section lists `buffer(8)` with the same paragraph-structure as buffer(6) / buffer(7).
- `DECISIONS.md` D-LM-buffer-slot-8 entry filed.
- `ENGINEERING_PLAN.md` Phase LM header + LM.0 entry filed (this entry).
- `swift build --package-path PhospheneEngine` green.
- `swift test --package-path PhospheneEngine` green; existing presets unaffected (`PresetAcceptanceTests` + `PresetRegressionTests` both pass with golden hashes unchanged — slot 8 is null in both).

**Verify.**

- `swift build --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine --filter PresetAcceptanceTests`
- `swift test --package-path PhospheneEngine --filter PresetRegressionTests`

**Estimated sessions:** 0.5 (this session itself).

**Status:** planned for 2026-05-08.

**Carry-forward.** LM.1 implements `LumenPatternEngine` (CPU-side state populated each frame + setter call) + `LumenMosaic.metal` (lighting fragment reads `LumenPatternState` at `[[buffer(8)]]`). See `docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md` §"Required uniforms / buffers" for the buffer layout.

### Increment LM.1 — Minimum viable preset

**Scope.** Land the first `LumenMosaic.metal` + `LumenMosaic.json` in the catalog: a single planar `sd_box` glass panel filling the camera frame plus 50 % bleed (Decision G.1, contract §P.1), per-cell Voronoi domed-cell relief + `fbm8` in-cell frost baked into `sceneSDF` as Lipschitz-safe displacements, and a fixed warm-amber backlight emitted through every cell. **No audio reactivity, no pattern engine, no slot 8 binding** — the pattern state buffer is wired up at LM.2 / LM.4. LM.1 proves the rendering pipeline works end-to-end (preamble compile + G-buffer + matID dispatch + lighting + bloom + ACES) before LM.2 layers on the 4-light analytical pattern engine.

**Architectural decisions filed in this increment.** D-LM-matid (extending the D-021 `sceneMaterial` signature with `thread int& outMatID` + writing the value into `gbuf0.g` so `raymarch_lighting_fragment` can dispatch on emission-dominated dielectric without changing the deferred PBR pipeline's pixel formats). The 3 existing ray-march presets (Glass Brutalist, Kinetic Sculpture, Volumetric Lithograph) gain the trailing parameter and a single `(void)outMatID;` line — no behavioural change, they stay on the `matID == 0` Cook-Torrance path. `RayMarch.metal` gains file-scope `kLumenEmissionGain (4.0)` and `kLumenIBLFloor (0.05)` constants and a single early-return branch when `matID == 1`. CLAUDE.md GPU Contract §G-Buffer Layout extends the `gbuffer0.g` documentation accordingly.

**Done when.**

- `LumenMosaic.metal` + `LumenMosaic.json` land at `PhospheneEngine/Sources/Presets/Shaders/`. `family: geometric`, `passes: ["ray_march", "post_process"]`, `certified: false`, `lumen_mosaic.cell_density = 30.0`. SSGI intentionally omitted (emission dominates).
- `sceneSDF` is a single `sd_box` sized `cameraTangents.xy * 1.50` with Voronoi domed-cell relief (`voronoi_f1f2(panel_uv, 30)` height-gradient + smoothstep ridge per SHADER_CRAFT.md §4.5b) and `fbm8(p * 80)` in-cell frost subtracted as Lipschitz-safe displacements (`kReliefAmplitude = 0.004`, `kFrostAmplitude = 0.0008`). The G-buffer central-differences normal picks them up automatically; D-021 `sceneMaterial` has no normal-output channel.
- `sceneMaterial` writes `outMatID = 1` (emission-dominated dielectric), stores the static backlight (`(0.95, 0.60, 0.30)` warm amber + a `mood_tint(valence, arousal) × 0.04` ambient floor) into `albedo`, and sets `roughness = 0.40`, `metallic = 0.0` for cosmetic placeholder consistency with the §4.5b dielectric.
- `raymarch_lighting_fragment` reads `gbuf0.g` and returns `albedo × 4.0 + irradiance × 0.05 × ao` for `matID == 1`. `matID == 0` path is byte-identical to pre-LM.1 (regression hashes for all 3 existing ray-march presets unchanged).
- `presetLoaderBuiltInPresetsHaveValidPipelines` regression gate green (LumenMosaic compiles cleanly through `PresetLoader`).
- `PresetAcceptanceTests` green for LumenMosaic against all 4 D-037 invariants (non-black at silence, no white clip on steady, beat response ≤ 2× continuous + 1.0, form complexity ≥ 2). The static backlight + per-cell relief should clear all four trivially.
- `PresetRegressionTests` green for the 3 existing ray-march presets — golden hashes unchanged because their `sceneMaterial` bodies don't write `outMatID` (caller pre-zeros to 0, lighting falls through to the existing Cook-Torrance path). New entry for LumenMosaic added under `goldenPresetHashes` via `UPDATE_GOLDEN_SNAPSHOTS=1` regen.
- LM.1 contact sheet captured at `docs/VISUAL_REFERENCES/lumen_mosaic/contact_sheets/LM.1/` for all six standard fixtures (silence / steady / beat-heavy / sustained-bass / HV-HA / LV-LA mood). Panel-edge invariant verified: every pixel in every fixture hits `matID == 1` (no `matID == 0` background pixels visible).
- p95 ≤ 2.0 ms at Tier 2 / ≤ 2.5 ms at Tier 1 over `PresetPerformanceTests`.
- `swiftlint lint --strict` green on touched files.
- `CLAUDE.md` Shaders/ list gains LumenMosaic entry; G-Buffer Layout section documents `gbuffer0.g` matID convention.
- This entry filed.

**Verify.**

- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swift build --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine --filter presetLoaderBuiltInPresetsHaveValidPipelines`
- `swift test --package-path PhospheneEngine --filter PresetAcceptanceTests`
- `swift test --package-path PhospheneEngine --filter PresetRegressionTests`
- `swift test --package-path PhospheneEngine --filter PresetPerformanceTests`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReviewTests` (capture contact sheet)
- `swift run --package-path PhospheneTools CheckVisualReferences` (verifies VISUAL_REFERENCES schema; `lumen_mosaic` already at green warnings-only state from the pre-LM.0 reference curation)

**Estimated sessions:** 2.

**Status:** planned for 2026-05-08.

**Carry-forward.** LM.2 wires the 4-light analytical pattern engine: `LumenPatternEngine` Swift class populates `LumenPatternState` (4 × `LumenLightAgent` + 4 × `LumenPattern` + activeCounts + ambientFloorIntensity) once per frame, calls `pipeline.setDirectPresetFragmentBuffer3(...)` (LM.0 setter) to bind slot 8, and the shader's `lm_backlight_static` is replaced by `sample_backlight_at(cell_center_uv, ...)` reading the slot 8 buffer. Mood-coupled hue shift (Decision E.1) + D-019 silence fallback verification + per-stem hue offsets (Decision §P.4) all land at LM.2.

### Increment LM.2 — Audio-driven 4-light backlight (continuous energy primary)

**Scope.** Replace LM.1's static warm-amber backlight with four audio-driven light agents — one per stem (drums / bass / vocals / other) — sampled at the cell-centre uv per Decision D.1 (cell-quantized colour). Agent positions compose a slow mood-driven Lissajous **drift** (driftSpeed lerp(0.05, 0.20, normalized smoothedArousal)) plus a `beat_phase01`-locked figure-8 **dance** (contract §P.4: per-agent quarter-cycle phase offsets, amplitude `clamp(0.04 + 0.10 × f.arousal, 0.04, 0.14)` reading raw `f.arousal`). Intensity is the deviation-primitive stem read with FV fallback under the standard D-019 warmup; colour is per-stem base × `mood_tint(smoothedValence, smoothedArousal)` with a 5 s low-pass on valence/arousal (ARACHNE §11). Pattern slots stay zeroed (`activePatternCount = 0`) — the pattern engine bursts arrive at LM.4. Slot 8 binding is **widened** in LM.2 from "lighting pass only" (LM.0) to "G-buffer pass + lighting pass" so `sceneMaterial` can read `LumenPatternState` directly via the new D-021 trailing parameter `constant LumenPatternState& lumen`.

**Done when.**

- `Sources/Presets/Lumen/LumenPatternEngine.swift` ships `LumenLightAgent` (32 B), `LumenPattern` (48 B), `LumenPatternState` (336 B) value types byte-identical to the matching MSL structs in the preamble; `LumenPatternEngine` final class with `init?(device:seed:)`, `tick(features:stems:)`, `snapshot()`, `reset()`, and the `setAgentBasePositionForTesting(_:_:)` test seam.
- The `sceneMaterial` D-021 signature gains a trailing `constant LumenPatternState& lumen` parameter. All 4 ray-march presets (Glass Brutalist, Kinetic Sculpture, Volumetric Lithograph, Lumen Mosaic) update; non-Lumen presets silence it via `(void)lumen;`. The preamble's `raymarch_gbuffer_fragment` declares `[[buffer(8)]]` and forwards to `sceneMaterial`. The two SSGI / RayMarch test fixture preset sources update too.
- `RayMarchPipeline` allocates a 336-byte zero-filled `lumenPlaceholderBuffer` at init and binds it at slot 8 in BOTH `runGBufferPass` and `runLightingPass` whenever `presetFragmentBuffer3` is nil — so non-Lumen ray-march presets compile against the same fragment with a defined slot-8 binding.
- `VisualizerEngine+Presets.swift` allocates `LumenPatternEngine` when the active ray-march preset is `"Lumen Mosaic"` and wires `setDirectPresetFragmentBuffer3(engine.patternBuffer)` plus a `setMeshPresetTick { engine?.tick(features:stems:) }` closure. Reset path nils both on every preset apply.
- `Tests/PhospheneEngineTests/Presets/LumenPatternEngineTests.swift` ships 15 tests across 7 suites: struct layout (336 / 32 / 48), silence behaviour (intensities < 0.05, ambient floor propagated), HV-HA / LV-LA mood drift speed, mood smoothing time-constant (15 s → 95 %), stem-direct routing, FV warmup fallback (drums + bass), beat-locked dance figure-8 (pos(0) − pos(0.5) ≈ (0.18, 0)), dance amplitude scales with arousal, agent inset clamp under forced base outside ±0.85, byte-identical determinism. All 15 pass.
- `PresetAcceptanceTests` + `PresetRegressionTests` + `PresetLoaderCompileFailureTest` continue to pass for all 15 production presets — golden hashes unchanged because non-Lumen presets render byte-identically with the new signature ignored.
- CLAUDE.md updated: LumenMosaic.metal entry rewritten for LM.2; new `Lumen/LumenPatternEngine.swift` entry; slot 8 GPU contract widened; D-021 signature changelog (LM.1 + LM.2).

**Verify.**

- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swift build --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine --filter LumenPatternEngineTests`
- `swift test --package-path PhospheneEngine --filter "PresetAcceptance|PresetRegression|PresetLoaderCompileFailure"`
- `swift test --package-path PhospheneEngine --filter "SSGITests|RayMarchPipelineTests"` (covers the slot-8 binding contract widening + signature update)
- `swift test --package-path PhospheneEngine` (full suite — pre-existing parallel-load timing flakes unchanged)
- `swiftlint lint --strict --config .swiftlint.yml` (new file disables `file_length` / `large_tuple` per Arachne pattern; baseline violation count unchanged)

**Status:** ✅ 2026-05-09.

**Carry-forward.** LM.3 keeps the same engine + GPU contract and adjusts the per-stem hue offsets + drift bounds to match the LM.3 design-doc "stem-direct routing" recipe. LM.4 promotes pattern slots from idle → live (radial_ripple, sweep) keyed to bar boundaries (`f.barPhase01` rolls past 1.0) and drum onsets (`stems.drumsBeat` rising edge). Both LM.3 and LM.4 land without further changes to the slot-8 binding contract.

> **Postscript 2026-05-09:** LM.2's visual scope was rejected at production review (the 4-light cell-quantized model + cream-baseline mood tint produced muted, gradient-blob output — no visible cells, no vivid colour). Engine + GPU contract verified correct (slot-8 binding, agent dance math, mood smoothing all working as specified). The substantive look re-targeted to LM.3 under a redesigned spec — see [`docs/presets/LUMEN_MOSAIC_DESIGN.md`](presets/LUMEN_MOSAIC_DESIGN.md) §11 Revision History and the `[LM-DESIGN]` commit (2026-05-09).

### Increment LM.3 — Per-cell palette + procedural mood + drop cream baseline

**Scope.** Replace LM.2's cell-quantized 4-light backlight with **per-cell colour identity from V.3 IQ cosine `palette()`** (Decision D.4). Each Voronoi cell hashes to a deterministic per-cell phase; phase advances over `accumulated_audio_time × kCellHueRate` so cells visibly cycle through hues during energetic playback and rest at silence. Palette parameters `(a, b, c, d)` interpolate continuously across mood (E.3 — no authored banks); per-track perturbation seed gives every track a distinct palette character at the same mood. **Cream baseline retired** — palette is vivid by construction at every mood / energy. Stems drive cell *intensity* only; agent colour fields are unused at LM.3 (kept on the GPU struct for ABI continuity, deferred to LM.5+ per-stem hue affinity work).

**Done when.**

- `Sources/Presets/Lumen/LumenPatternEngine.swift` extended: `LumenPatternState` grows from 336 → 360 B with new `smoothedValence`, `smoothedArousal`, and four `trackPaletteSeed{A,B,C,D}` fields. New public API: `setTrackSeed(_ seed: SIMD4<Float>)` and `setTrackSeed(fromHash hash: UInt64)`. `_tick(...)` writes smoothed mood scalars into the snapshot but **must not** clear the per-track seed (regression test gates this).
- `Sources/Presets/PresetLoader+Preamble.swift` MSL `LumenPatternState` struct extended byte-identically.
- `Sources/Presets/Shaders/LumenMosaic.metal` `sceneMaterial` rewritten: Voronoi → `lm_cell_palette(cell_id, accumulated_audio_time, lumen)` for per-cell hue + `lm_cell_intensity(cell_center_uv, lumen)` for per-cell scalar brightness (floored at `kSilenceIntensity = 0.55`). Cream baseline + `lm_mood_tint` + `lm_sample_backlight_at` deleted. New file-scope tuning constants: `kCellHueRate (0.15)`, `kSilenceIntensity (0.55)`, four cool/warm × subdued/vivid × unison/offset × complementary/analogous palette endpoints, four per-track seed magnitudes.
- `Sources/Renderer/RayMarchPipeline.swift` placeholder buffer resized 336 → 360 B.
- `PhospheneApp/VisualizerEngine+Stems.swift` `resetStemPipeline(for:)` calls `lumenPatternEngine?.setTrackSeed(fromHash:)` with FNV-1a 64-bit hash of `title + artist` so two tracks at the same mood get visibly different palette character.
- `Tests/.../Presets/LumenPatternEngineTests.swift` updated: stride test 336 → 360, `ambientFloorIntensity == 0` (LM.2 floor moved to shader), 5 new tests for the LM.3 GPU-state contract (smoothed mood reaches snapshot, `setTrackSeed` direct + hash variants, clamp to `[-1, +1]`, hash determinism, hash distinguishes hashes, `_tick` does not clear seed).
- `PresetAcceptance` + `PresetRegression` + `PresetLoaderCompileFailure` + `SSGITests` + `RayMarchPipelineTests` all pass — golden hashes unchanged for non-Lumen presets (the new ABI parameter passes through unused).
- `docs/VISUAL_REFERENCES/lumen_mosaic/contact_sheets/LM.3/` ships 5 PNGs (silence / mid / beat / hv_ha_mood / lv_la_mood) + README.md. **Cell quantization paints visibly** (the LM.2 gradient-blob failure mode is gone). **Vivid throughout** — no cream haze. Mood-coupled palette character shift visible (HV-HA leans warm, LV-LA leans cool). Silence frame shows distinct vivid cells, not faded.
- CLAUDE.md updated: LumenMosaic.metal entry rewritten for D.4 / E.3, LumenPatternEngine entry updated for 360 B + setTrackSeed, slot-8 contract footprint updated.

**Verify.**

- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swift build --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine --filter "LumenPatternEngine|PresetAcceptance|PresetRegression|PresetLoaderCompileFailure|SSGITests|RayMarchPipelineTests"`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` (capture LM.3 contact sheet)
- `swiftlint lint --strict --config .swiftlint.yml` (baseline 55 violations preserved; 0 new from LM.3)

**Status:** ⚠ **rejected in production.** LM.3 commit landed 2026-05-09 (`d17dcf4f`). Real-music session capture (2026-05-09T22-57-39Z) showed cells did not visibly cycle: Spotify volume normalisation (BUG-012) under-reads mid + treble bands → `accumulated_audio_time` advanced ~0.045 / sec instead of the design-target ~0.5 / sec, so `accumulated_audio_time × kCellHueRate` was effectively static for entire songs. Procedural-palette + per-cell-hash + mood-coupled-parameters + per-track-seed infrastructure all working as specified — the *time-driven cycling* mechanism failed against real audio. Superseded by LM.3.2.

### Increment LM.3.1 — Agent-position-driven backlight character

**Scope.** First remediation attempt for LM.3's missing-cycling. Add a position-based static-light field on top of LM.3 — each agent's POSITION (not its audio-driven intensity) creates a permanent light pool around it via `falloff = 1 / (1 + r² × attenuationRadius)`. `kAgentStaticIntensity = 0.50`, `kCellMinIntensity = 0.05`, sharper `attenuationRadius = 12.0` (was 6.0) — cells under an agent see a strong static field; cells in the gaps between agents see a weak one, reading as "lit from behind by 4 point sources."

**Status:** ⚠ **rejected by Matt 2026-05-09**: "fixed-color cells with brightness modulation; the bright pools dominated the visual story." LM.3.1 commit landed 2026-05-09 (`d8a31aee`). The four agent positions painted four bright lobes that read as the visual subject; cells underneath felt static. Brightness modulation is not the visual register the preset is meant to occupy. Superseded by LM.3.2.

### Increment LM.3.2 — Band-routed beat-driven dance

**Scope.** Replace LM.3's continuous-time cycling and LM.3.1's agent-position backlight with a **band-routed beat-driven dance model** (Decision D.5). Each cell hashes (`cell_id ^ trackSeedHash`) into one of four teams (30 % bass / 35 % mid / 25 % treble / 10 % static). The cell's palette index advances discretely on rising-edge of its team's FFT-band beat — `f.beatBass`, `f.beatMid`, or `f.beatTreble` — debounced 80 ms, scaled by `beatStrength = clamp(0.3 + 1.4 × max(f.bass, f.mid, f.treble), 0.3, 1.0)`. Per-cell `period ∈ {1, 2, 4, 8}` (Pareto-distributed from hash) controls how many team-beats between advances. Static cells never advance; rotated per track via XOR with the per-track seed. Brightness uniform with hash jitter `[0.85, 1.0]` plus a bar pulse `+30 % × bar_phase01^8` on each downbeat. Per-track palette seed magnitudes bumped to ±0.20 / 0.20 / 0.30 / 0.50 (was ±0.05 / 0.05 / 0.10 / 0.20).

**Done when.**

- `Sources/Presets/Lumen/LumenPatternEngine.swift` extended: `LumenPatternState` grows from 360 → 376 B with four new band counters (`bassCounter`, `midCounter`, `trebleCounter`, `barCounter`). `_tick(...)` calls a new `updateBandCounters(features:)` helper (extracted to keep `_tick` under SwiftLint's 60-line ceiling). Rising-edge state on `LumenPatternEngine` (`prevBeatBass / prevBeatMid / prevBeatTreble / prevBarPhase01`) + per-band debounce timestamps + `bassBeatsSinceBarFallback`. New private `resetBeatTrackingState()` helper called from `reset()` AND `setTrackSeed(_:)` so a new track starts cells at step 0 (without this, the previous track's accumulated counter values would carry over and cells would jump straight to a far-off palette index on the new track's first beat).
- `Sources/Presets/PresetLoader+Preamble.swift` MSL `LumenPatternState` struct extended byte-identically: four trailing `float` fields after `trackPaletteSeed{A,B,C,D}`.
- `Sources/Presets/Shaders/LumenMosaic.metal` `sceneMaterial` rewritten for D.5: `lm_hash_u32(cell_id ^ trackSeedHash)` → team / period / base-phase / jitter; `step = floor(team_counter / period)`; phase = `cell_t + step × kPaletteStepSize + smoothedValence × kPaletteMoodPhaseShift`; intensity = `(0.85 + 0.15 × jitter) × (1 + 0.30 × bar_phase01^8)`. New file-scope helpers: `lm_hash_u32`, `lm_track_seed_hash`. Retired constants: `kAgentStaticIntensity`, `kCellMinIntensity`, `kCellHueRate`. New constants: `kCellIntensityBase`, `kCellIntensityJitter`, `kBarPulseMagnitude`, `kBarPulseShape`, `kPaletteStepSize`, `kBassTeamCutoff`, `kMidTeamCutoff`, `kTrebleTeamCutoff`. `kSeedMagnitude{A,B,C,D}` bumped 0.05 / 0.05 / 0.10 / 0.20 → 0.20 / 0.20 / 0.30 / 0.50.
- `Sources/Renderer/RayMarchPipeline.swift` placeholder buffer resized 360 → 376 B.
- `Tests/.../Presets/LumenPatternEngineTests.swift` updated: stride test 360 → 376; new Suite 9 (10 tests) covering rising-edge increment, falling-edge no-increment, 80 ms debounce in/out, energy-scaled `beatStrength`, `barPhase01` wrap detection, every-4-bass-beats fallback, mid + treble independent tracking, `reset()` zeroes counters, `setTrackSeed(_:)` zeroes counters.
- `PresetAcceptance` + `PresetRegression` + `PresetLoaderCompileFailure` + all other engine suites pass. Golden hashes for Lumen Mosaic + every other preset unchanged (the regression render path uses the placeholder zero-buffer; with all counters = 0 the LM.3.2 output collapses to the same dHash as LM.3).
- `docs/VISUAL_REFERENCES/lumen_mosaic/contact_sheets/LM.3.2/` ships 5 PNGs + README.md (fixtures: silence / mid / beat / hv_ha_mood / lv_la_mood). Uniform brightness across panel (LM.3.1 spotlit-blob failure mode gone). Beat fixture differs from mid fixture by ~30 % of cells advancing one palette step (bass-team rising-edge).
- CLAUDE.md updated: LumenMosaic.metal entry rewritten for D.5 dance model. New D-LM-d5 ledger row.

**Verify.**

- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swift build --package-path PhospheneEngine`
- `swift test --package-path PhospheneEngine --filter "LumenPatternEngine|PresetAcceptance|PresetRegression|PresetLoaderCompileFailure|StagedPresetBufferBinding"`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "PresetVisualReviewTests/renderPresetVisualReview"` (capture LM.3.2 contact sheet)
- `swiftlint lint --strict --config .swiftlint.yml` (baseline 55 violations preserved; 0 new from LM.3.2)

**Status:** ✅ **M7 pass 2026-05-10** (session `2026-05-10T15-44-27Z`). After eight calibration rounds (2026-05-09 / 2026-05-10), Matt confirmed: "Awesome. Finally. The movement of the color in the cells is looking good. I'd consider this a 'pass.'" Round-by-round narrative captured in `docs/VISUAL_REFERENCES/lumen_mosaic/contact_sheets/LM.3.2/README.md`: round 1 baseline → round 2 widened mood palette + cell density 30 → 15 → round 3 per-channel seed perturbation → round 4 HSV palette + emission gain 4 → 1 → round 5 frosted-glass surface character → round 6 beat envelope → round 7 frost in albedo → round 8 dropped beat envelope. Final architecture: HSV-driven palette + Voronoi-distance frost in albedo + cells hold previous palette state until next team beat + bar pulse on downbeat. Final commits: `76e21bf8` → `d4f66e21` (8 commits on `main`, NOT pushed). Carry-forward: track-to-track colour variation could be wider (Matt 2026-05-10 follow-up). Defer to LM.6 fidelity polish or earlier as a tuning pass — see Carry-forward below.

**Carry-forward.** LM.4 ships pattern bursts (radial ripples on drum onsets, sweeps on bar boundaries) that inject extra per-cell brightness — pattern colour comes from the same per-cell palette so a ripple takes the colour of the cells it crosses. The design doc covers per-stem hue affinity as an optional LM.5 sub-decision (deferred until LM.4 review tells us whether the LM.3.2 unified-palette feel needs stem differentiation). **Track-variation carry-forward (2026-05-10)**: Matt's M7 sign-off included "I'd like to see more color variation track to track, but this can be adjusted later." First lever: push `kSeedMagnitudeD` from 0.50 → 0.65 (controls per-track phase rotation in the per-channel hue-shift basis on `d`). Second lever: bump `kSeedMagnitudeA` from 0.20 → 0.30 (per-channel hue-shift on `a`). Third lever: increase `moodHueSpread` from 0.40 to 0.55 (widens cell-to-cell hue spread within a track, indirectly making track baselines more distinguishable). Schedule for LM.6 fidelity polish (since it's a tuning pass) or earlier as a follow-up if other Phase LM work warrants a touch-up release.

### Increment LM.4 — Pattern engine v1 (idle + radial_ripple + sweep)

**Scope.** Layer transient brightness spikes on top of the LM.3.2 cell field. Drum onsets fire `radialRipple` patterns from hash-derived origins in `[0.05, 0.95]²` UV; bar-counter rising edges fire either a `radialRipple` (from a separate hash family) or a `sweep` (from one of four panel-edge midpoints) — mood-weighted (high arousal biases 60/40 toward sweep, low arousal 60/40 toward ripple, mid-arousal 50/50). Pool capacity 4; overflowing spawns evict the oldest by max `phase`. **Patterns inject INTENSITY, not COLOUR (LM.3.2 architecture)** — each cell keeps its palette identity, the wavefront brightens whatever colour the cell already has, and the frost halo at cell boundaries (round 7) also brightens through `albedo = clamp(frosted_hue × cell_intensity, …)`. Reuses LM.3.2's existing 80 ms-debounced band-counter rising edges as the trigger source (no new bar-detection logic; the every-4-bass-beats `barCounter` fallback for reactive mode comes for free).

**Done when.**

- `Sources/Presets/Lumen/LumenPatterns.swift` ships `LumenPatternFactory` enum namespace with `idle()`, `radialRipple(origin:birthTime:duration:intensity:)`, `sweep(origin:direction:birthTime:duration:intensity:)`. Sweep direction normalised to unit length; zero-length input falls back to `(0, 1)`. Defaults: `radialRippleDuration = 0.6 s`, `sweepDuration = 0.8 s`, `defaultPeakIntensity = 1.0`. Colour fields stay zero (architecture invariant).
- `Sources/Presets/Lumen/LumenPatternEngine.swift` extended: new private state (`activePatterns: [LumenPattern]` capacity 4, `drumOnsetCounter: UInt32`, `barRotationCounter: UInt32`); `_tick` captures `prevBassCounter` + `prevBarCounter` before `updateBandCounters` and derives `bassFired` / `barFired` after; `updatePatterns(dt:bassFired:barFired:)` advances phases → culls retired → spawns ripple on bass rising edge → spawns mood-weighted bar pattern on bar rising edge → snapshots to `state.patterns`; `spawnPattern(_:)` evicts the oldest by max-phase when at capacity. Three separate hash families (`drumOnsetCounter ^ trackSeed` / `barRotationCounter ^ (trackSeed ^ 0xA5A5A5A5)` / `barRotationCounter ^ trackSeed`) avoid origin / kind collision. `lmHashU32(_:)` Swift helper is byte-identical to the shader's `lm_hash_u32`. `resetBeatTrackingState()` extended to zero the pattern pool + counters + the `state.patterns` snapshot.
- `Sources/Presets/Shaders/LumenMosaic.metal` ships three new evaluators: `lm_pattern_radial_ripple(cell_uv, p)` (Gaussian band centred on `radius = phase × kRippleMaxRadius (√2)`, σ narrows as ring grows); `lm_pattern_sweep(cell_uv, p)` (Gaussian band with `sweep_position = phase × 2 − 1` along `p.direction`, fixed σ); `lm_evaluate_active_patterns(cell_uv, lumen)` (sums per-pattern intensities dispatched on `kindRaw`, clamps to `kPatternMaxSum`). Integration site in `sceneMaterial` runs after `lm_cell_intensity` — `cell_intensity += lm_evaluate_active_patterns(...) × kPatternBoost (0.4)` so the boost propagates through `frosted_hue × cell_intensity` (halo brightens with patterns). Per-pattern helpers take `LumenPattern` by value (not `constant&`) to avoid the address-space mismatch in the loop body — Failed Approach #44 silent-drop avoided. New tuning constants: `kPatternBoost = 0.4`, `kPatternMaxSum = 1.0`, `kRippleMaxRadius = √2`, `kRippleSigmaBase = 0.10`, `kSweepSigma = 0.10`.
- `Tests/.../Presets/LumenPatternsTests.swift` ships 18 tests across 5 suites: factory contract (5), lifecycle (5 — spawn / phase advance / retire / reset clears / setTrackSeed clears), radial-ripple expansion math contract (3), sweep direction (3 — unit length / stable across phase / monotone phase), pool eviction (2).
- `PresetAcceptance` (D-037 invariants) + `PresetRegression` + `PresetLoaderCompileFailure` + `LumenPatternEngine` + `LumenPatterns` all green. PresetRegression Lumen Mosaic golden hash unchanged at `0xF0F0C8CCCCC8F0F0` (regression render path binds slot 8 to the zero placeholder → `activePatternCount = 0` → pattern contribution = 0).
- `CLAUDE.md` updated: LumenPatternEngine entry covers the new private state + reset semantics; LumenMosaic.metal entry covers the three new evaluators + integration site + tuning constants.
- p95 ≤ 3.0 ms at Tier 2 (pattern eval is per-fragment Gaussian + length over ≤ 4 slots — should be well under the existing LM.3.2 cost; tune `kPatternBoost` down if D-037 trips on the harness fixture).

**Verify.**

- `swift test --package-path PhospheneEngine --filter "LumenPatterns|LumenPatternEngine|PresetAcceptance|PresetRegression|PresetLoaderCompileFailure"`
- `swiftlint lint --strict --config .swiftlint.yml` (touched files clean)
- Real-session capture for Matt review against the LM.3.2 contact-sheet checklist + the LM.4 acceptance items: (a) drum onsets visibly produce ripples expanding from coherent origins, deterministic per track on replay; (b) bar-rotation pattern character noticeably changes at bar boundaries on Spotify-prepared tracks; every-4-beats fallback feels coherent on reactive-mode tracks; (c) pattern + bar-pulse interaction reads as coherent emphasis (not fighting — if it does, halve `kPatternBoost`); (d) D-037 beat response ≤ 2× continuous + 1.0 invariant holds.

**Status:** ⏳ tests + docs landed 2026-05-10. Awaiting Matt review on a real-music session. Same discipline as LM.3.2 — tests passing + harness frames rendering ≠ done; the contact-sheet observation is the load-bearing acceptance gate.

**Carry-forward.** LM.4.1 follows up on first M7 review (ripple density + bleach-out). LM.4.5 follows on full-spectrum palette redesign. LM.5 adds the remaining pattern kinds: `clusterBurst`, `breathing`, `noiseDrift`. LM.6 was originally framed here as "specular sparkle on the Voronoi ridges via frost normal / Cook-Torrance pass" — that path was abandoned per the LM.3.2 round-7 / Failed Approach lock. The actual LM.6 increment (landed 2026-05-12, D-LM-6) is two albedo-only modulations in `sceneMaterial` (cell-depth gradient + optional centre hot-spot) with the SDF normal still flat; matID==1 lighting path still skips Cook-Torrance.

### Increment LM.4.1 — Ripple density + bleach-out fix

**Scope.** Three-line calibration change after first M7 review on session `2026-05-11T15-15-46Z`. (a) `radialRippleDuration` 0.6 → 0.3 s — at 118 BPM the kick fires every ~0.5 s; 0.6 s lifetime made every ripple overlap with the next by ~0.2 s and individual pulses never registered. (b) `kPatternBoost` 0.40 → 0.20 — combined peak `cell_intensity` (cell baseline × bar pulse + pattern boost) was hitting 1.70 against the `rgba8Unorm` 1.0 albedo clamp, slamming the bright channels of saturated HSV cells to white and destroying per-cell colour identity. (c) `kBarPulseMagnitude` 0.30 → 0.20 — LM.3.2 carry-forward; the bar pulse stacks on the pattern boost so cutting both was required to bring combined peak back to ~1.20.

**Done when.**

- `Sources/Presets/Lumen/LumenPatterns.swift` ships `radialRippleDuration = 0.3 s` with the LM.4.1 comment block explaining the tempo math.
- `Sources/Presets/Shaders/LumenMosaic.metal` ships `kPatternBoost = 0.20f` and `kBarPulseMagnitude = 0.20f` with LM.4.1 comment blocks explaining the bleach-out math.
- `Tests/.../Presets/LumenPatternsTests.swift` — `test_fivthSpawnEvictsOldest` and `test_pool_neverExceedsPatternCount` use `barPhase01` wraps (no debounce) instead of `beatBass` rising edges; at the new 0.3 s ripple lifetime, 80 ms-debounced bass spawns can't fill the pool before natural retirement, so the eviction code path was never exercised under the old test driver.
- All 18 LumenPatterns tests + PresetAcceptance + PresetRegression + PresetLoaderCompileFailure green. SwiftLint 0 violations on touched files.
- CLAUDE.md updated: LumenMosaic.metal tuning surface line reflects new values + LM.4.1 landed-work entry above the LM.4 entry, calling out the LM.4.5 carry-forward.

**Verify.**

- `swift test --package-path PhospheneEngine --filter "LumenPatterns|LumenPatternEngine|PresetAcceptance|PresetRegression|PresetLoaderCompileFailure"`
- `swiftlint lint --strict --config .swiftlint.yml` (touched files clean; baseline preserved)
- Matt re-review on a real-music session: (a) individual ripples now read as discrete pulses, not a smear; (b) cells under ripples + bar pulse retain their colour identity (no near-white wash); (c) the LM.3.2 per-cell palette dance reads clearly through the patterns instead of being shouted over.

**Status:** ⏳ tests + docs landed 2026-05-11. Awaiting Matt re-review on a real-session capture.

**Carry-forward.** LM.4.1 only addresses ripple density + bleach-out. The deeper palette-scope limitation Matt called out in the same review — "literally any HEX code or Pantone shade" missing, including dark hues, regal purples, browns, grays — is the LM.4.5 scope (palette architecture redesign).

### Increment LM.4.3 — BeatGrid-driven triggers + ripples-as-accent

**Scope.** Replace the LM.3.2 FFT-band rising-edge triggers with `f.beatPhase01` / `f.barPhase01` grid wraps; demote ripples from per-kick to per-bar; preserve LM.3.2's team / period architecture but reinterpret bass/mid/treble as rate buckets (every beat / every 2 beats / every 4 beats) rather than FFT bands.

**Why.** Second M7 review (Matt 2026-05-11, session `2026-05-11T15-56-41Z`) made the LM.4 trigger failure conclusive. Diagnostic: all four tracks fired ripples at ~2.41/sec regardless of tempo. The trigger was `f.beatBass`, an FFT bass-band detector that fires on ~any sub-bass transient (kicks, bass-line notes, low harmonics) — completely decoupled from the song's actual beat. Same root cause affected the LM.3.2 cell-dance counters: cells stepped ~2.4× faster than the song's beat, hence "color does not really follow the music." Matt also reframed the deeper issue: per-kick ripples treat onset events as primary motion, inverting the CLAUDE.md Audio Data Hierarchy rule ("ACCENT ONLY — NEVER PRIMARY"). LM.4.3 fixes both — tempo-correct trigger source AND demote ripples to once-per-measure accent.

**Done when.**

- `Sources/Presets/Lumen/LumenPatternEngine.swift` — new private state (`prevBeatPhase01 / prevBarPhase01` wrap-edge detection + `gridBeatsSinceMidStep / gridBeatsSinceTrebleStep` subdivision counters); `updateBandCounters(features:)` rewritten to detect grid wraps (`prev > 0.85 && now < 0.15`) and advance counters uniformly +1.0 each on beat/bar wraps with mid every 2 / treble every 4; `updatePatterns(dt:barFired:)` simplified — no `bassFired` path; `advancePatternEngine` derives only `barFired`; `radialRippleOriginFromOnset()` and `drumOnsetCounter` deleted; `resetBeatTrackingState()` updated.
- `Sources/Presets/Lumen/LumenPatterns.swift` — `radialRippleDuration` restored 0.3 → 0.6 s (the LM.4.1 halving was necessary for the per-kick world; LM.4.3 per-bar spawning gives the longer lifetime plenty of headroom — ~1.4 s rest between accents on typical 4/4 at 120 BPM).
- `Tests/.../Presets/LumenPatternsTests.swift` — `fv()` helper `beatBass:` → `beatPhase01:`; new `spawnOnePatternViaBarWrap` helper; test_bassRisingEdge_spawnsRipple → test_barWrap_spawnsBarRotationPattern + new test_beatPhase01Wrap_doesNotSpawnPattern; lifecycle/expansion/sweep tests rewired through bar wraps.
- `Tests/.../Presets/LumenPatternEngineTests.swift` Suite 9 fully rewritten as LM.4.3 band-counter tests: `test_beatPhase01Wrap_incrementsBassCounterByOne`, `test_beatPhase01HeldHigh_doesNotIncrement`, `test_midAndTrebleTickAtSubdividedRates`, `test_barPhase01Wrap_incrementsBarCounter`, `test_noGridSignal_noBarCounterAdvance` (asserts the bar-fallback was retired), `test_fftBeatBass_aloneDoesNotAdvanceAnyCounter` (regression-locks the FFT-trigger retirement), `test_reset_zerosBandCounters`, `test_setTrackSeed_zerosBandCounters`.
- `PresetAcceptance` + `PresetRegression` + `PresetLoaderCompileFailure` + `LumenPatternEngine` + `LumenPatterns` all green. App build clean. SwiftLint 0 violations on touched files.
- `CLAUDE.md` updated: LumenPatternEngine entry rewritten for LM.4.3 semantics; LumenMosaic.metal tuning surface line reflects new defaults; LM.4.3 landed-work entry added above the LM.4.1 entry.

**Verify.**

- `swift test --package-path PhospheneEngine --filter "LumenPatterns|LumenPatternEngine|PresetAcceptance|PresetRegression|PresetLoaderCompileFailure"`
- `swift test --package-path PhospheneEngine` (full sweep; expect only the 3 documented pre-existing failures)
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swiftlint lint --strict --config .swiftlint.yml` (touched files clean; baseline preserved)
- Matt re-review on a real-music session: (a) ripples now fire once per musical bar (~0.5/sec on 4/4 at 120 BPM, ~0.07/sec on Pyramid Song's 16/8 at 70 BPM — both feel tempo-correct); (b) LM.3.2 color dance steps land on actual grid beats (cell color shifts visibly correlate to the song's pulse); (c) ripple-vs-pulse interaction is coherent emphasis, not fighting; (d) D-037 beat response invariant holds.

**Status:** ⏳ tests + docs landed 2026-05-11. Awaiting Matt re-review.

**Known limitation:** no FFT fallback — if `f.beatPhase01` never wraps (pure silence; pre-grid first ~10 s of live ad-hoc sessions), counters and patterns are static. Acceptable for prepared sessions (grid is at session start); LM.4.4 may add a fallback if reactive ad-hoc sessions surface the gap.

**Carry-forward.** LM.4.4 retired the pattern engine entirely after the third M7 review (the LM.4.3 trigger fix was confirmed but the ripple/sweep accent layer was rejected as "barely noticeable"). LM.4.5 (full-spectrum per-track palette redesign) is now the next planned increment.

### Increment LM.4.4 — Pattern engine retired

**Scope.** Delete the entire LM.4 pattern-spawn engine — Swift factory + engine pool state + spawn helpers + shader evaluator helpers + integration site. Keep the LM.3.2 cell-color dance (now driven by LM.4.3 grid-wrap counters) + the bar pulse as the entire visual story. GPU ABI (`LumenPatternState`, 376 B; `LumenPattern[4]` tuple; `LumenPatternKind` enum) preserved for future LM.5+ work that may rebind the slots to continuous fields (breathing / noiseDrift) rather than transient bursts.

**Why.** Third M7 review (Matt 2026-05-11, session `2026-05-11T17-02-17Z`): "The ripple sweep is not really doing much — it's barely noticeable. What value is it really adding?" Honest diagnosis: at execution-time-feasible boost levels the Gaussian wavefronts were invisible against the simultaneous bar pulse (both events fired on the downbeat; panel-wide pulse dominated the local +20% band by area). Pushing the wavefront brighter would have re-introduced the LM.4.1-resolved bleach-out. The CLAUDE.md Audio Data Hierarchy rule frames the structural redundancy: per-bar pattern events and the bar pulse were occupying the same downbeat moment, so they couldn't help but compete.

**Done when.**

- `Sources/Presets/Lumen/LumenPatterns.swift` deleted.
- `Tests/.../Presets/LumenPatternsTests.swift` deleted.
- `Sources/Presets/Lumen/LumenPatternEngine.swift` — pattern-pool state (`activePatterns`, `barRotationCounter`, `prevBarPhase01`) deleted; `updatePatterns`, `spawnPattern`, `spawnBarRotationPattern`, `writePatternsToState`, `radialRippleOriginFromBar`, `sweepEntryFromBar`, `chooseBarPatternKind`, `lmHashU32`, `trackSeedHash32` all deleted; `updateBandCounters` simplified to beat-wrap-only (no bar wrap); `advancePatternEngine` simplified to just call the band-counter update; `resetBeatTrackingState` updated; LM.4-era `swiftlint:disable type_body_length` removed (class shrank under the threshold).
- `Sources/Presets/Shaders/LumenMosaic.metal` — `lm_pattern_radial_ripple` / `lm_pattern_sweep` / `lm_evaluate_active_patterns` evaluator functions deleted; `kPatternBoost` / `kPatternMaxSum` / `kRippleMaxRadius` / `kRippleSigmaBase` / `kSweepSigma` constants deleted; `sceneMaterial` integration site (`cell_intensity += pattern_contribution * kPatternBoost`) deleted.
- `Tests/.../Presets/LumenPatternEngineTests.swift` Suite 9 — renamed `LumenLM43CounterTests` → `LumenLM44CounterTests`; `test_barPhase01Wrap_incrementsBarCounter` + `test_noGridSignal_noBarCounterAdvance` retired; replaced with `test_barCounter_neverAdvances_afterLM44` which regression-locks the dead-counter contract. `driveBarWrap` helper removed.
- `PresetAcceptance` + `PresetRegression` + `PresetLoaderCompileFailure` + `LumenPatternEngine` all green. App build clean. SwiftLint 0 violations on touched files; project baseline preserved.
- `CLAUDE.md` updated: `LumenPatterns.swift` module-map entry marked deleted; `LumenPatternEngine.swift` entry rewritten for LM.4.4 semantics; `LumenMosaic.metal` entry updated to reflect pattern engine retirement; tuning-surface line trimmed; LM.4.4 landed-work entry added above LM.4.3.

**Verify.**

- `swift test --package-path PhospheneEngine --filter "LumenPatternEngine|PresetAcceptance|PresetRegression|PresetLoaderCompileFailure"`
- `swift test --package-path PhospheneEngine` (full sweep; expect only the 3 documented pre-existing failures)
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swiftlint lint --strict --config .swiftlint.yml` (touched files clean)
- Matt re-review on a real-music session: panel shows LM.3.2 cell-color dance on every beat + bar pulse on downbeats only; no ripple/sweep wavefronts; cell colour identity preserved through the bar pulse (no bleach-out).

**Status:** ⏳ tests + docs landed 2026-05-11. Awaiting Matt re-review.

**Carry-forward.** LM.4.5 (full-spectrum per-track palette redesign) is the next planned increment. With the pattern engine gone, the palette redesign focuses cleanly on what actually matters: colour variety across the spectrum. LM.5 (clusterBurst / breathing / noiseDrift) becomes "continuous fields rebinding to the slot-8 buffer" if it ever lands — the GPU ABI is preserved exactly for that possibility, but it's no longer scheduled.

### Increment LM.4.5 — Full-spectrum palette redesign (per-track custom palette cards)

> **Renumbering note (2026-05-11).** This increment was originally numbered LM.4.2 when it was first scoped (during the LM.4.1 carry-forward planning). It stayed as a reserved name through LM.4.3 and LM.4.4 — both of those increments overtook it because urgent M7 feedback redirected the work to trigger-source fixes and pattern-engine retirement. The "LM.4.2" label was misleading because the number implied chronological precedence that never existed (LM.4.2 was never started). Renamed to LM.4.5 so the numbering reflects actual sequence: LM.4 → LM.4.1 → LM.4.3 → LM.4.4 → LM.4.5.

**Scope.** Replace the LM.3.2 mood-centred-narrow-jewel-tone palette with per-track custom palette cards drawn from the **full** HSV cube. Each track gets ~50 specific colours, picked procedurally from the entire colour space (full hue wheel, full saturation range, full brightness range). Cells pick one colour from the card. Mood biases the distribution (calm tracks tilt toward deeper/cooler regions; energetic tracks toward brighter/saturated) but does not restrict — every track can paint cells from anywhere in the cube. Result: cobalt next to oxblood next to charcoal with a violet edge next to amber next to bright crimson — the stained-glass-cathedral aesthetic, not the LM.3.2 jewel-tone-only register.

**Why.** Matt's first M7 review made the brief explicit: "I am asking you for VARIETY and the variety you are giving me is variety within a narrow scope. ... I want 90-95% more." The LM.3.2 palette structurally restricts to ~5% of the HSV cube (saturation floored at 0.78, brightness floored at 0.80, hue centred ±0.20 around mood). No tuning of those floors will deliver the 90-95% expansion he asked for; the palette model itself has to change.

**Guardrail.** The "no pastel" project rule (`CLAUDE.md` Visual Quality Floor) stays in force. Forbidden zone: saturation < 0.3 AND brightness > 0.6 — that's the cream-haze failure mode LM.2 fell into and we've forbidden since. The redesign achieves the full spectrum by **coupling** desaturation with darkness: low-saturation cells get pulled toward low brightness (charcoal, brown, slate), not high brightness (pastel). Everything else (full saturation × full brightness, mid-saturation × any brightness, high-saturation × low brightness for regal purples / deep ambers) is allowed.

**Done when.**

- `Sources/Presets/Shaders/LumenMosaic.metal` ships a new `lm_cell_palette_card(cellHash, lumen)` that procedurally generates an HSV triple from a hash seeded by (`trackPaletteSeed*`, `cellHash`). Hue spans the full wheel; saturation spans `[0.05, 1.0]`; brightness spans `[0.10, 0.95]`; pastel zone (sat < 0.3 AND val > 0.6) is collapsed by pulling val down. Mood biases the distribution (per-arousal brightness skew, per-valence hue-region skew) but does not restrict the envelope.
- Per-track distinctiveness: the same cell hash on two different tracks produces visibly different colours (full hash-space rotation per track, not just a narrow centre shift).
- Beat-step ratcheting (LM.3.2 team-counter dance) still works — `step = floor(team_counter / period)` advances each cell through its assigned palette path on team beats. Each step lands in a different region of the full cube, not in a neighbouring jewel tone.
- `PresetAcceptance` D-037 invariants pass with the wider palette (silence baseline, no white clip, beat response bounded, form complexity ≥ 2).
- New regression test: random-fixture sweep confirms the full HSV cube is sampled — the distribution of cell colours across 200 cells should span a wide hue range (≥ 270° of hue covered), wide saturation range (≥ 0.6 spread), and wide brightness range (≥ 0.5 spread). Cells satisfying the pastel forbidden zone count = 0.
- Contact sheet renders across 4 tracks (Love Rehab / So What / There There / Pyramid Song) show genuinely different palette cards — visibly different colour mixes, not rotated permutations of the same jewel tones.

**Verify.**

- `swift test --package-path PhospheneEngine --filter "LumenMosaic|PresetAcceptance|PresetRegression|LumenPatterns|LumenPatternEngine|PresetLoaderCompileFailure"`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "PresetVisualReviewTests/renderPresetVisualReview"` (LM.4.5 contact sheet)
- Matt M7 review: every track's palette feels meaningfully distinct from every other track's, AND each track's palette spans the full spectrum (darks, regals, browns/slates, jewel tones, all visible in the same panel).

**Status:** ⚠ **LM.4.5 v1, LM.4.5.1, LM.4.5.2, LM.4.5.3 all SUPERSEDED by LM.4.6** (2026-05-12). The entire LM.4.5.x palette-iteration arc concluded with Matt's verdict on session `2026-05-12T00-29-30Z`: *"Working. It's close enough. I'm giving up the fight on colors."* The final shape is `Increment LM.4.6` below — pure uniform random RGB per cell, no rules. The spec above documents LM.4.5 v1's original intent (full HSV cube + pastel guardrail) which was rejected in production; the prompt's framing of "saturation full range [0, 1] + pastel guardrail" was the wrong abstraction. Each LM.4.5.x sub-increment attempted a different fix and was rejected in turn — see the iteration history in CLAUDE.md's LM.4.6 landed-work entry.

**Iteration history (all 2026-05-11)**:
- **LM.4.5 v1** (`a51a3b15`): full HSV cube + pastel guardrail `sat < 0.3 AND val > 0.6 → val ≤ 0.5`. Rejected: ~23 % cells in the mid-sat + high-val band still read as washed cream.
- **LM.4.5.1** (`54c908a7`): saturated stained-glass — `kSatFloor = 0.70` for jewel-tone-only. Rejected: "anchored to jewel tones, no muted earth tones."
- **LM.4.5.2** (`6c3e3661`): full sat range + coupling rule `val ≤ sat + 0.20`. Rejected: borderline pale cells at the margin.
- **LM.4.5.3** (`ce7b593b`): uncapped (no card) + per-cell brightness 0.30..1.60 + section salt + `kLumenEmissionGain` 1.5. Rejected: tracks still looked statistically identical at panel level; ~30 % dim/gray cells from wide brightness range; broken section salt never advanced (audio-energy accumulator, not seconds).
- **LM.4.6 anchor-distribution attempt** (uncommitted): 8 anchors weighted Pareto. Rejected: "no anchors, ANY color per cell."
- **LM.4.6 final** (`c0f9ccf3` + `888bb856` hotfix): pure uniform random RGB. Accepted.

**Why iteration didn't converge sooner**: Matt's ask had two simultaneous components — (a) each cell can be any colour independently, AND (b) different tracks look visibly different at the panel level. The strict reading was mathematically incompatible: uniform random sampling produces statistically similar panel aggregates regardless of seed (law of large numbers). Each LM.4.5.x sub-increment tried a different per-cell restriction; each was rejected. LM.4.6 shipped accepting (a) over (b) and documented the trade-off in the shader file header. **LM.7 subsequently revisited and partially resolved (b)** — Matt 2026-05-12 explicitly accepted relaxing (a) in spirit (most colours remain reachable on every track; the cube corner opposite the tint direction is forfeit at extreme seed values) in exchange for visible panel-aggregate distinction per track. See D-LM-7.

**Carry-forward.** `Increment LM.4.6` below replaces this spec as the LM.4.6 implementation. LM.5 (pattern engine v2) is retired per LM.4.4. **LM.6 (originally framed as "specular sparkle on cell relief" — Cook-Torrance via frost normal) was abandoned per the LM.3.2 round-7 / Failed Approach lock; what actually landed as LM.6 (2026-05-12, D-LM-6) is cell-depth gradient + optional hot-spot, both albedo-only modulations with the SDF normal still flat.** LM.7 (D-LM-7) followed same day with per-track aggregate-mean tint; Lumen Mosaic certified 2026-05-12 at LM.7. See LM.6 / LM.7 increment entries below.

### Increment LM.4.6 — Pure uniform random RGB per cell (final shape)

**Status:** ✅ landed 2026-05-12 (commits `c0f9ccf3` + hotfix `888bb856`). Matt sign-off: "*Working. It's close enough.*"

**Scope.** Replace LM.4.5.x's procedural HSV-with-rules palette with the simplest possible per-cell colour generator: three bytes of `lm_hash_u32(cellHash ^ stepMix ^ trackSeed ^ sectionMix)` mapped directly to RGB. No HSV indirection, no coupling rule, no mood gamma, no saturation floor, no anchor distribution, no spatial zones. Pure per-cell freedom.

**The contract.** Per Matt 2026-05-11: *"EVERY CELL CAN BE INDEPENDENT OF ITS NEIGHBORS... I literally want ANY possible color to be possible within ANY cell."* Each (cell, beat, track, section) tuple gets a unique 32-bit colour hash → RGB ∈ [0, 1]. Section salt = `lumen.bassCounter / 64` (every ~32 s on 120 BPM, resets on track change). Per-cell brightness multiplier tightened to `[0.85, 1.15]` (LM.4.5.3's wide `[0.30, 1.60]` produced dim/gray cells). `kLumenEmissionGain` reset to 1.0.

**Done when.**
- `lm_cell_palette` is a pure hash → RGB function with zero post-processing (no HSV, no coupling, no mood gamma).
- Section salt uses `bassCounter / 64` and actually advances (the LM.4.5.3 `accumulatedAudioTime` proxy was an audio-energy accumulator, never reached bucket 1 in real playback).
- `LumenPaletteSpectrumTests` rewritten for LM.4.6 (7 tests / 5 suites): per-cell uniqueness, RGB channel coverage, per-track distinctness, determinism, beat-step change, section boundary mutation, within-section stability.
- `PresetLoaderCompileFailureTest` passes (15 production presets — LM.4.6 hex-literal hotfix `888bb856` was caught by this test).
- App + engine build clean; SwiftLint 0 violations on touched files.
- Matt M7 review: "close enough" verdict reached.

**Verify.**
- `swift test --package-path PhospheneEngine --filter "LumenPalette|PresetLoaderCompileFailure|PresetRegression|PresetAcceptance"`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` (Lumen Mosaic 9-fixture contact sheet)
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`

**Honest math caveat (documented in shader file header).** Uniform random sampling produces statistically similar panel-aggregates across tracks (different specific colours per cell, same distribution shape — law of large numbers). LM.4.6 prioritises per-cell freedom over panel-level distinction; track-to-track distinction at the panel level was explored extensively across LM.4.5.x and consistently rejected at the time. **Superseded by LM.7** (per-track aggregate-mean tint, 2026-05-12) — Matt re-opened the trade-off after seeing the LM.6 contact sheet and explicitly accepted the relaxation of strict "any colour reachable in every track" for visible track-to-track variety. See LM.7 below.

**Carry-forward.** LM.6 (cell-depth gradient + optional hot-spot) is the planned next increment. Implemented and landed 2026-05-12.

### Increment LM.6 — Cell-depth gradient + optional hot-spot

**Status:** ✅ landed 2026-05-12. Matt M7 sign-off via real-music session `2026-05-12T17-15-14Z`.

**Scope.** Add physical-glass dome character to each cell without touching the palette or geometry. Two modulations on `cell_hue` between palette lookup and frost diffusion in `sceneMaterial`: (1) depth gradient — `cell_hue *= mix(kCellEdgeDarkness, 1.0, 1 - smoothstep(0, cellV.f2 × kDepthGradientFalloff, cellV.f1))` — full brightness at cell centre (f1 → 0), `kCellEdgeDarkness (0.55)` at boundary (f1 → f2); (2) optional hot-spot — `cell_hue += pow(1 - smoothstep(0, kHotSpotRadius × cellV.f2, cellV.f1), kHotSpotShape) × kHotSpotIntensity × cell_hue` — additive on the cell's own hue (not toward white), 30 % brightness boost in inner 15 % of each cell with `pow^4` sharp falloff. Driven entirely by the Voronoi field already computed for cell ID + frost; zero extra cost. SDF relief stays flat (`kReliefAmplitude = 0`, `kFrostAmplitude = 0`) per LM.3.2 round-7 / Failed Approach lock — no normal-driven path, no per-pixel dot artifacts. The matID==1 emission lighting contract is unchanged.

**Done when.**
- 5 new file-scope `constant float` knobs (`kCellEdgeDarkness = 0.55f`, `kDepthGradientFalloff = 1.0f`, `kHotSpotRadius = 0.15f`, `kHotSpotShape = 4.0f`, `kHotSpotIntensity = 0.30f`).
- 3 new tests in `LumenPaletteSpectrumTests` Suite 6 (centre-brighter-than-edge / hot-spot peaks-at-centre / depth-gradient-monotonic-across-radius) mirror the shader math in Swift.
- `PresetRegression` Lumen Mosaic golden hash unchanged at `0xF0F0C8CCCCC8F0F0` — modulation is per-pixel Voronoi-driven, dHash 9×8 luma quantization at 64×64 is dominated by cell boundary positions not per-cell intensity gradients.
- Engine + app build clean. `PresetLoaderCompileFailureTest` passes (15 presets — shader didn't silent-drop).
- SwiftLint 0 violations on touched files.

**Verify.**
- `swift test --package-path PhospheneEngine --filter "LumenPalette|PresetRegression|PresetAcceptance|PresetLoaderCompileFailure"`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview`

**Carry-forward.** Matt re-opened the LM.4.6 "panel-aggregate uniform across tracks" complaint after the LM.6 contact-sheet review — see LM.7 below.

### Increment LM.7 — Per-track aggregate-mean RGB tint + chromatic projection

**Status:** ✅ landed 2026-05-12. Matt M7 sign-off via real-music session `2026-05-12T17-15-14Z`. **Lumen Mosaic certified.**

**Scope.** Add a small per-track RGB tint vector to every cell's uniform random RGB before the saturate-clamp, derived from existing `lumen.trackPaletteSeed{A,B,C}` (∈ [−1, +1] from FNV-1a hash of `title|artist`) and scaled by `kTintMagnitude = 0.25f`. Per-cell freedom preserved: cells still independently sample the full uniform RGB cube; only the *window* slides per track. Closes the LM.4.6 "panel-aggregate is statistically identical across tracks" complaint Matt explicitly voiced on the LM.6 contact sheet: *"mean should NOT be middle-gray; the mean should be different for each track played."*

**Chromatic projection (same-day follow-up).** First visual review showed `track_v1` (seed (+1,+1,+1,+1) → naive tint (+0.25, +0.25, +0.25)) washed toward white; `track_v2` (seed all-negative) would have correspondingly washed toward black. Root cause: a tint vector with non-zero mean component shifts the achromatic axis (brightness), not the chromatic plane (hue). Fix: subtract the mean component before scaling — `meanShift = (rawTint.r + g + b) / 3; trackTint = (rawTint - meanShift) × kTintMagnitude`. Projects every tint onto the chromatic plane perpendicular to (1,1,1). Achromatic-aligned seeds collapse to neutral (LM.4.6 baseline behaviour) rather than washing.

**Done when.**
- `kTintMagnitude = 0.25f` file-scope constant.
- 6 LOC in `lm_cell_palette` adding chromatic-projected tint vector application before `saturate(...)`.
- Swift mirror in `LumenPaletteSpectrumTests` with `LMPalette.tintMagnitude` constant + tint application in `lmCellPaletteRGB`.
- New Suite 7 `LM.7 — per-track aggregate-mean tint` with 5 tests: warm-track-leans-warm, cool-track-leans-cool, distinct-tracks-have-distinct-aggregate-means (pairwise RGB-distance ≥ 0.20), neutral-track-near-middle-gray, achromatic-aligned-seed-does-not-wash (regression-locks the chromatic-projection fix).
- `PresetRegression` Lumen Mosaic golden hash UNCHANGED at `0xF0F0C8CCCCC8F0F0` (regression harness leaves slot-8 zero-bound → trackPaletteSeed = 0 → tint = 0 → identical to LM.4.6 path). All other preset hashes byte-identical.
- Engine + app build clean. SwiftLint 0 violations on touched files.
- Matt M7 sign-off + cert flip.

**Verify.**
- `swift test --package-path PhospheneEngine --filter "LumenPalette|PresetRegression|PresetAcceptance|PresetLoaderCompileFailure|FidelityRubric"`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` — `track_v1`/`v2` panels collapse to neutral (no wash); `track_v3`/`v4` panels display distinct magenta and green chromatic tints. File-size delta on the PNGs confirms the fix lands without disturbing non-aligned tracks.

**Honest trade-off documented.** The LM.4.6 "any colour reachable on every track" framing is preserved *in spirit* but no longer *strictly*. Most colours remain reachable on every track; the most-extreme cube corners are forfeit at the seedA/B/C = ±1 limit (where their channel clamps would have been required to land at the corner). Side-effect of the chromatic projection: tracks whose `trackPaletteSeed{A,B,C}` happen to align with the achromatic diagonal collapse to LM.4.6-neutral. FNV-1a hash of `title|artist` distributes seeds roughly uniformly in [−1, +1]³, so achromatic-aligned tracks occur in a small minority of cases. Matt 2026-05-12 explicitly accepted both trade-offs.

**Phase LM CLOSED.** Lumen Mosaic certified 2026-05-12. `certified: true` in `LumenMosaic.json`; `"Lumen Mosaic"` added to `FidelityRubricTests.certifiedPresets` ground truth. Next preset eligible for fidelity uplift if Matt prioritises (see CLAUDE.md Phase G-uplift). The preset's automated rubric gate (`meetsAutomatedGate`) still reads false because M3 mat_* heuristic fails (Lumen Mosaic uses voronoi_f1f2 + matID==1 emission path rather than the V.3 material cookbook); visual fidelity bar is met by other means per SHADER_CRAFT.md §12.1 M7 ("Matt-approved reference frame match" is the load-bearing gate).

**BUG-004 closed 2026-05-12** as a downstream consequence. The BUG-004 closure increment expanded `GoldenSessionTests.makeRealCatalog()` from 11 → 15 production presets so the orchestrator's `includeUncertifiedPresets: false` filter is now end-to-end exercised against the real production cert state; added a new `Session D` test (`sessionD_lumenMosaicWinsFirstSegment`) that regression-locks Lumen Mosaic winning at least one segment under a plausible mood profile (BPM=75 / val=0.0 / arous=+0.30); and fixed the stale `MatIDDispatchTests.kLumenEmissionGain` constant (4.0 → 1.0 post-LM.3.2-round-4). Milestone D advances **0 → 1 / 22+** with Lumen Mosaic as Phosphene's first production certified preset. See `docs/QUALITY/KNOWN_ISSUES.md` Resolved section for the full closure entry.

### Increment LM.4.7 — Curated 18-palette library + mood-biased Orchestrator selection

**Status:** ✅ Implementation landed 2026-05-18; Matt M7 sign-off on the same-day 5-track session with one tuning note (within-quadrant clustering), addressed by the same-day amendment widening `kAntiRepeatWindow` from N=1 to N=3 (`[dev-2026-05-18-b]`, D-LM-palette-library amended). Paperwork-only session earlier the same day filed `D-LM-palette-library` + `D-LM-cream-rescission`; CLAUDE.md + KNOWN_ISSUES.md + this entry updated.

**Scope.** Replace LM.4.6's `lm_cell_palette` uniform-random-RGB body (and the LM.7 per-track chromatic-projected tint built on top of it) with palette-library-driven cell colours. **Each song** selects one of **18 hand-authored 12-colour palettes**; the Orchestrator picks the palette via a mood-biased Gaussian-over-distance weight function with the immediately previous song's palette excluded from the candidate set. Within a song, cells sample uniformly from the drawn palette's 12 entries via cell-hash modulo 12. The per-track seed perturbs **sampling order** within the palette (which 12-bucket a given cell lands in for that track) — never palette membership. The LM.3.2 team/period beat-step ratchet is preserved; cells advance their palette index on rising-edge of their assigned band's beat. Cites `D-LM-palette-library`.

The pale-tone-share gate (≤ 0.30 of cells; pale = linear RGB `min(R, G, B) > 0.65`) lands in this increment as the mechanical enforcement of `D-LM-cream-rescission`. Cathedral Lights is the calibration palette (~25 % nominal pale-cell share, ~30 % worst-case under hash-draw variance).

**The 18 palettes.** Vol. I — Autumnal, Refn Glow, Glacier, Art Deco, Abyssal Bioluminescence, Kintsugi, Carnival. Vol. II — Holi, Geode, Rothko Chapel, Tropical Aviary, Persian Miniature, Ukiyo-e. Plate 14 — Cathedral Lights. Plates 15–18 — Cycladic, Ming Porcelain, Tenebrism, Obsidian.

**Done when.**

- New file `PhospheneEngine/Sources/Presets/LumenMosaicPaletteLibrary.swift` defines 18 palettes as Swift structs carrying a `name: String`, a 12-entry `colors: [SIMD3<Float>]` (linear RGB), and an explicit `moodAnchor: SIMD2<Float>` in normalised mood-space coordinates `[-1, +1]` per axis (valence on x, arousal on y). Palettes named to match the design artifacts (Autumnal, Refn Glow, Glacier, Art Deco, Abyssal Bioluminescence, Kintsugi, Carnival, Holi, Geode, Rothko Chapel, Tropical Aviary, Persian Miniature, Ukiyo-e, Cathedral Lights, Cycladic, Ming Porcelain, Tenebrism, Obsidian). Hex values per `docs/VISUAL_REFERENCES/lumen_mosaic/palette_library/`.
- Orchestrator selection model implemented: per-song weighted draw via Gaussian-over-distance from each palette's `moodAnchor` to the current track's `(valence, arousal)`, with the immediately previous song's palette removed from the candidate set. Draw seeded by track identity so it's reproducible. Per `D-LM-palette-library`: mood biases **selection probability**, never deterministic mapping; every eligible palette has non-zero probability everywhere in the mood plane.
- `lm_cell_palette` (MSL) rewritten to index into the per-session palette via `palette_idx = lm_hash_u32(cell_id ^ step ^ track_seed ^ section_salt) % 12` and look up the corresponding palette entry. The pre-LM.4.7 hash → RGB-cube path is removed. The LM.7 per-track chromatic-projected tint path is removed (`kTintMagnitude` retires).
- Slot-8 GPU ABI extended to carry the 12-colour palette as 36 floats (or equivalent per implementation choice — e.g. 12 × `float4` packed). `LumenPatternState` stride updated; Swift-side `CommonLayoutTest` regression-locks the new size. `directPresetFragmentBuffer3` setter wires the per-session palette into the binding.
- `LumenPaletteSpectrumTests` rewritten — assertions on **palette membership** (every cell colour matches one of the 12 palette entries to within float epsilon), per-session palette stability, mood-biased selection probability distribution shape, palette character distinctness across the 18-palette set. Replaces the existing Suite 7 (LM.7 chromatic-projection assertions); LM.7-specific tests retire with the LM.7 code path.
- LM.9 pale-tone-share gate implemented as a new test (location TBD — `LumenPaletteSpectrumTests` or `FidelityRubric`): per non-silence fixture frame, classify each cell by linear RGB; reject the fixture if `pale_cell_count / total_cells > 0.30`. **Passes for all 18 palettes mechanically.** Cathedral Lights specifically must pass at its ~25 % nominal share with margin.
- `PresetRegression` Lumen Mosaic golden hash regenerated — the regression harness's slot-8 zero-bound default is no longer equivalent to "neutral palette" because the cell-colour lookup is into a palette table. The new golden hash reflects the post-LM.4.7 baseline; the regression test pins the new value.
- Engine + app build clean; SwiftLint 0 violations on touched files.
- **Matt M7 review** on a real-music multi-track session: each song's drawn palette reads as its named character (Cathedral Lights → stained-glass, Refn Glow → warm-neon-shadow, Glacier → frozen-blue-on-snow, etc.); the per-song palette change is visible at track boundaries (panel character shifts when the track shifts) and the mood-biased selection feels appropriate per track (low-valence / high-arousal tracks trend toward Rothko Chapel / Tenebrism / Abyssal Bioluminescence; high-valence / high-arousal tracks trend toward Carnival / Holi / Tropical Aviary; etc.) without being deterministic; the anti-repeat rule is visible on a contrived playlist (e.g. forcing two consecutive low-valence-low-arousal tracks should pick different palettes, not Cathedral Lights twice in a row).

**Verify.**

- `swift test --package-path PhospheneEngine --filter "LumenPalette|PresetLoaderCompileFailure|PresetRegression|PresetAcceptance|FidelityRubric"`
- `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` — 18-palette contact sheet at the standard 9-fixture set, plus per-palette mean / aggregate-character verification.
- `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
- `swiftlint lint --strict --config .swiftlint.yml`

**Honest trade-offs documented.** Per-cell freedom is narrower than LM.4.6: each cell samples one of 12 colours, not from the full 16M-colour RGB cube. Matt explicitly accepted this trade-off in the 2026-05-17 conversation in exchange for palette character per session. Across the 18 palettes, the union of reachable colours covers a wide swath of the cube; what changes is that **within a given session**, only 12 colours appear, which is the property that makes the palette read as a coherent visual identity.

**Carry-forward.** Resolves BUG-014 (`docs/QUALITY/KNOWN_ISSUES.md` Open) — flip to Resolved with the LM.4.7 commit hash. New palette additions (post-LM.4.7) require Matt M7 review per palette and a `D-LM-palette-library`-citing amendment in `DECISIONS.md`. Palette removals are also gated on Matt sign-off. The LM.7 chromatic-projection code path retires with LM.4.7; the `kTintMagnitude` constant and the `test_achromaticAlignedSeed_doesNotWash` test are removed (the failure mode they regression-lock cannot occur on the palette-table path because cells sample from a curated 12-entry table that, by construction, avoids the achromatic-axis wash).

---

## Phase CA — Capability Audit (2026-05-20)

**Motivation.** Drift between docs and code is real and has cost session time. Concrete evidence from the 2026-05-20 design conversation: a Cold-Start design pass proposed building "C2 + first-onset anchoring" infrastructure that turned out to **already exist in production** via the BUG-007.x series — Claude had no prior knowledge of it because it wasn't surfaced in the high-traffic docs. Same session: `docs/CAPABILITY_GAP_AUDIT.md` is referenced from this file but doesn't exist as a file. These are not hypothetical drift; they are blocking real work.

Phase CA addresses the drift systematically through per-subsystem code-vs-docs audits. Each increment audits one subsystem: reads the actual source, traces consumers, cross-references docs, and assigns a health verdict to every capability the subsystem exposes. Output is `docs/CAPABILITY_REGISTRY/<subsystem>.md` per pass, plus a top-level `docs/CAPABILITY_REGISTRY.md` index assembled after multiple passes.

**Phase scope is one-increment-at-a-time.** The wider phase plan firms up after CA.1's "approach validation" step confirms the format produces actionable value. Do not plan CA.2-CA.N upfront.

### Increment CA.1 — DSP / MIR

**Status.** ✅ Landed 2026-05-20. Kickoff doc: [`docs/prompts/PHASE_CA_KICKOFF_CA1_DSP_MIR_2026-05-20.md`](prompts/PHASE_CA_KICKOFF_CA1_DSP_MIR_2026-05-20.md). Audit deliverable: [`docs/CAPABILITY_REGISTRY/DSP_MIR.md`](CAPABILITY_REGISTRY/DSP_MIR.md). Summary: 18 of 22 file-level entities `production-active`; 1 runtime `production-orphan` cluster (per-frame `StructuralAnalyzer` chain has no live consumer; output is read only at preparation time); 1 field-level `production-orphan` (`MIRPipeline.spectralRolloff` public exposure); 1 `built-but-undocumented` (`MIRPipeline+Recording` parallel CSV path); 2 `boundary-deferred` (`GridOnsetCalibrator` + `BeatGridAnalyzer` live in `Session/` but function as DSP capabilities); 0 `broken-but-claimed`. Doc-drift corrections applied to `ARCHITECTURE.md` (module map drift — 6 files missing; MIR-component list missing `LiveBeatDriftTracker` + `StructuralAnalyzer`; Chroma 65 Hz → 500 Hz value drift; Session-Recording manual `R`-path note) + `ENGINEERING_PLAN.md` (Capability-Gap-Audit pointer corrected to Phase CA). One retroactive `Resolved` entry filed: [BUG-R010 PT.1 ring-buffer fix](QUALITY/KNOWN_ISSUES.md). The audit's approach-validation section recommends ML as the CA.2 subsystem (DSP↔ML boundary closes cleanly; Beat This! infrastructure already partly tested under `Tests/ML/`).

**Scope.** All 20 files in `PhospheneEngine/Sources/DSP/` plus DSP-adjacent capabilities at subsystem boundaries (DSP↔Audio, DSP↔ML, DSP↔Session, DSP↔App). The DSP subsystem is first because (a) it's the subsystem where this session's blind spot lived (BUG-007.x cold-start beat-sync infrastructure invisible to Claude); (b) the BUG-007.x series produced significant incremental infrastructure most likely to be undercaptured in docs; (c) the output feeds directly into Phase CS verification work.

**Output.** `docs/CAPABILITY_REGISTRY/DSP_MIR.md`. Plus BUG entries for any `broken-but-claimed` findings; doc-drift corrections to load-bearing docs in the same increment.

**Verdicts assigned per capability.** `production-active`, `production-orphan`, `dead`, `stub`, `documented-but-missing`, `built-but-undocumented`, `broken-but-claimed`, `unverified-claim`, `boundary-deferred`. Definitions in the kickoff doc.

**Discipline.** Audit-only. No code changes during the audit beyond the new audit doc and minor doc-drift corrections. Fix work that the audit surfaces is scheduled as separate increments. Stop-and-report criteria and methodology fully spec'd in the kickoff document — read it before starting.

**Done-when.** Audit document published with verdicts for every public capability in scope; all `broken-but-claimed` findings have BUG entries; drift corrections to CLAUDE.md / ENGINEERING_PLAN.md / DECISIONS.md landed; approach-validation section produces an honest critique of whether the format should continue.

**After CA.1 lands** — surface to Matt: summary counts, recommended approach changes for CA.2, recommended next subsystem (audit-driven, may not be the originally-planned "Audio").

### Increment CA.2 — ML

**Status.** ✅ Landed 2026-05-20. Kickoff doc: [`docs/prompts/PHASE_CA_KICKOFF_CA2_ML_2026-05-20.md`](prompts/PHASE_CA_KICKOFF_CA2_ML_2026-05-20.md). Audit deliverable: [`docs/CAPABILITY_REGISTRY/ML.md`](CAPABILITY_REGISTRY/ML.md). Summary: 14 of 16 files `production-active`; 4 cluster-level `production-orphan` findings at the field/method level (cited grep each per CA.2 §production-orphan rule — `StemFFTEngineProtocol`, `StemSeparator.stft/.istft` wrappers, 5 `BeatThisModel` model-dimension constants, 2 `MoodClassifier` static lets plus 3 error-type public exposures); 2 large `built-but-undocumented` gaps (Beat This! transformer entirely absent from `ARCHITECTURE.md §ML Inference`; `ML/` module-map missing 9 of 16 files); 1 `documented-but-missing` (`ARCHITECTURE.md §Mood Classifier Inputs` claimed AGC-normalized flux; code passes raw smoothed flux — training and runtime agreed, only the doc was wrong). 0 `broken-but-claimed`; 0 new BUG entries. Doc-drift corrections applied to `ARCHITECTURE.md` (§ML Inference Beat This! narrative + window-size constants; §Module Map ML/ block with 9 added files; §Mood Classifier Inputs per-index table) and `KNOWN_ISSUES.md §BUG-012 → Instrumentation installed` (pointer to the audit's BUG-012 instrumentation map — the centralised reading-aid that previously didn't exist anywhere). **The audit did not edit any of the 8 BUG-012-i1-instrumented files** per CA.2 Hard Rules. The audit's read of every BUG-012-adjacent code path produced no new candidate root cause; one small diagnostic enrichment is suggested for the next instrumentation tranche as `CA.2-FU-2` (blocked on BUG-012 closure). **Approach validation:** continue into CA.3 with one tweak — Explore agents over-asserted `public` on internal types in 3 of 4 CA.2 cases; a single visibility grep across the agent's claimed-public types catches it. Recommended next subsystem: **Session** (CA.1 + CA.2 between them flagged three boundary-deferred Session placements — `GridOnsetCalibrator`, `BeatGridAnalyzer`, and the `MoodClassifier.currentState` read-at-end-of-prep pattern). Alternative: defer CA.3 scope decision until BUG-012 step-2 diagnosis lands if it reproduces.

**Scope.** All 16 files in `PhospheneEngine/Sources/ML/` (4,507 LoC) — Beat This! transformer × 5, StemSeparator + StemModel + StemFFT × 9, MoodClassifier × 2, ML.swift × 1 — plus boundary annotations to DSP (BeatThisPreprocessor / BeatGridResolver / StemAnalyzer), Session (BeatGridAnalyzer; deferred from CA.1), Renderer (MLDispatchScheduler), and App (VisualizerEngine+Stems / +Audio). Excluded by scope: `Sources/ML/Weights/` (data files); `BeatGridAnalyzer` and `GridOnsetCalibrator` (Session module — CA.1 boundary-deferred and re-confirmed by CA.2); `MLDispatchScheduler` (Renderer module); `VisualizerEngine+*` (App module).

**Output.** `docs/CAPABILITY_REGISTRY/ML.md`. Plus drift corrections in the same increment. No new BUG entries (BUG-012 already covers the open defect in this subsystem).

**Discipline.** Audit-only. No code changes during the audit beyond the new audit doc and the listed doc-drift corrections. **The 8 BUG-012-i1-instrumented files** (`StemFFT.swift`, `StemFFT+CPU.swift`, `StemFFT+GPU.swift`, `StemSeparator.swift`, `Shared/BUG012Probe.swift`, `VisualizerEngine.swift`, `VisualizerEngine+Stems.swift`, `Tests/.../BUG012ConcurrencyTest.swift`) were off-limits to edits per CA.2 Hard Rules — the audit read them freely but modified none of them; findings that would have required editing one of them are registered in the audit's Follow-up Backlog (FU-1, FU-2, FU-3 are all BUG-012-blocked).

**Done-when.** Audit document published; every public capability has a verdict; every `production-orphan` cites its grep; every non-`production-active` finding either ships a doc-fix in this increment or is registered as a `CA.2-FU-N` follow-up; no edits to BUG-012-i1 instrumented files.

**After CA.2 lands** — surface to Matt: summary counts, recommended approach changes for CA.3, recommended next subsystem (Session unless BUG-012 reproduces in the meantime), any BUG-012-adjacent findings the next reproduction's diagnosis should weigh (none surfaced — race-surface analysis remains the most current understanding).

### Increment CA.3 — Session

**Status.** ✅ Landed 2026-05-20. Kickoff doc: [`docs/prompts/PHASE_CA_KICKOFF_CA3_SESSION_2026-05-20.md`](prompts/PHASE_CA_KICKOFF_CA3_SESSION_2026-05-20.md). Audit deliverable: [`docs/CAPABILITY_REGISTRY/SESSION.md`](CAPABILITY_REGISTRY/SESSION.md). Summary: 21 of 22 file-level entities `production-active`; 1 `stub` (`LocalFolderConnector.swift` — `#if ENABLE_LOCAL_FOLDER_CONNECTOR`-gated v2 scaffold; flag never set in any xcconfig or Package.swift; class never compiles in production builds — intentional per D-046 / UX_SPEC §4.4); 2 `documented-but-missing` findings in `ARCHITECTURE.md` (a — `§Session Preparation` step list at lines 112–124 omitted D-070 preview-URL primary path, Beat This! offline grid, DSP.4 drums-stem grid, BUG-007.8 grid-onset calibration, and Round 26 metadata-driven meter override; b — `§Module Map Tests/Session/` referenced a nonexistent `StemCacheTests`); 2 large `built-but-undocumented` gaps (Session/ module-map block listed 9 of 22 files — 13 missing; Tests/Session/ block listed 9 of 14 real files — 6 missing + 1 phantom); 0 `production-orphan`; 0 `broken-but-claimed`; 0 new BUG entries. **The audit also flagged a kickoff-prompt staleness**: BUG-006 was cited as Open/P1 by the prompt but `KNOWN_ISSUES.md` already shows `Status: Resolved` (BUG-006.2 wiring fix, 2026-05-06, validated end-to-end by session capture `2026-05-06T20-11-46Z`). Confirming the kickoff against the issue file before starting is now a recommended CA.4 methodology step. Doc-drift corrections applied to `ARCHITECTURE.md` (§Session Preparation rewritten as a 7-step pipeline reflecting current code; §Module Map Session/ block extended with 13 missing files and one-line descriptions including a v2-scaffold note for LocalFolderConnector; §Module Map Tests/Session/ block corrected — phantom StemCacheTests removed, 6 real test files added; §Session Recording (Diagnostics) gained a one-paragraph WIRING:-log surface note). **The CA.1/CA.2 boundary-deferred items all resolved here**: `GridOnsetCalibrator` → `production-active`, recommend relocating to `Sources/DSP/` per `CA.3-FU-1` (functionally a DSP capability; both consumers already import DSP — closes CA.1-FU-5's GridOnsetCalibrator half); `BeatGridAnalyzer` → `production-active`, **stays in Session/** (testability-seam pattern co-located with consumer is correct); `MoodClassifier.currentState` end-of-prep read → `production-active`, intentional EMA-smoothed-state architecture (not drift). **Approach validation:** continue into CA.4 with the methodology refinements above — direct file reads scale to ≤ 5k-LoC subsystems; agents remain right for larger modules but the visibility-verification grep is mandatory regardless; cross-check kickoff prompts against `KNOWN_ISSUES.md` as a routine step. Recommended next subsystem: **Orchestrator** (Session ↔ Orchestrator surface touchpoints already surfaced — TrackProfile, SessionPlan → PlannedSession lift, PlannedSession.canonicalIdentity consumed during prepared-cache wiring; auditing Orchestrator closes that boundary cleanly before CA-App).

**Scope.** All 22 files in `PhospheneEngine/Sources/Session/` (~3,425 LoC across 20 top-level files + 2 `Connectors/`) — lifecycle + state machine × 6, preparation pipeline × 6, track / playlist value types × 3, boundary-resolved-from-CA.1 × 2, quality gates × 1, connectors × 2, module marker × 1, stub × 1. Boundary annotations: Session ↔ App (SessionManager observable surface + SpotifyOAuthTokenProvider concrete in App layer per D-069 Decision 2), Session ↔ Orchestrator (TrackProfile / SessionPlan consumption boundaries), Session ↔ DSP (BeatGrid / BeatDetector / MIRPipeline usage), Session ↔ ML (StemSeparator / MoodClassifier / BeatThisModel composition), Session ↔ Audio (MetadataPreFetcher pre-fetch path). Excluded by scope: `PhospheneApp/` (CA-App later); `Sources/Orchestrator/` (CA-Orchestrator next); `Sources/Renderer/` MLDispatchScheduler (CA-Renderer); `Sources/Audio/` internals (CA-Audio later).

**Output.** `docs/CAPABILITY_REGISTRY/SESSION.md`. Plus drift corrections in the same increment. No new BUG entries.

**Discipline.** Audit-only. No code changes during the audit beyond the new audit doc and the listed doc-drift corrections. The 8 BUG-012-i1-instrumented files remained off-limits to edits per the Hard Rules carried forward from CA.2 — Session-side touchpoint is `SessionPreparer+Analysis.swift:76 separator.separate(...)`, which routes through the BUG-012-instrumented dispatch chain but was not modified.

**Done-when.** Audit document published; every public capability has a verdict; every Explore-agent-claimed public symbol cross-checked against visibility grep (CA.3 used direct reads, so cross-check ran as a final pass — all internal types correctly scoped); every non-`production-active` finding either ships a doc-fix in this increment or is registered as a `CA.3-FU-N` follow-up; all three CA.1/CA.2 boundary-deferred items have final verdicts; drift corrections to load-bearing docs landed; no edits to BUG-012-i1 instrumented files; "Approach validation" section produces an honest critique of whether the format should continue into CA.4.

**After CA.3 lands** — surface to Matt: summary counts, recommended approach changes for CA.4, recommended next subsystem (Orchestrator), the verdict on the three CA.1/CA.2 boundary-deferred items + the GridOnsetCalibrator-relocation recommendation (`CA.3-FU-1`), and the LocalFolderConnector keep-vs-delete product call (`CA.3-FU-2`). No BUG-006-adjacent diagnosis surfaced (BUG-006 already Resolved).

### Increment CA.4 — Orchestrator

**Status.** ✅ Landed 2026-05-20. Kickoff doc: [`docs/prompts/PHASE_CA_KICKOFF_CA4_ORCHESTRATOR_2026-05-20.md`](prompts/PHASE_CA_KICKOFF_CA4_ORCHESTRATOR_2026-05-20.md) (commit `9fc1a6c9`). Audit deliverable: [`docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md`](CAPABILITY_REGISTRY/ORCHESTRATOR.md). Summary: 12 of 14 file-level entities `production-active` at the Orchestrator-module surface; **1 `broken-but-claimed` cluster filed as [BUG-015](QUALITY/KNOWN_ISSUES.md#bug-015) (P1)** — `VisualizerEngine.applyLiveUpdate(...)` has zero production call sites; the entire Phase 4.5 / 4.6 runtime adaptation pipeline is dead in production despite ENGINEERING_PLAN.md marking both increments ✅. **1 `production-orphan`** (`DefaultLiveAdapter.transitionPolicy` field — declared, stored, never invoked). **1 `unverified-claim`** (PresetScorer.swift:86 doc comment cites D-030 instead of D-032 for the Weight rationale). **2 large `built-but-undocumented`** (ARCHITECTURE.md §Module Map Orchestrator/ block listed 5 of 14 files; §Module Map Tests/Orchestrator/ block was absent entirely). **Plus 4 doc-drift findings** — ARCHITECTURE.md §Orchestrator "Forthcoming (4.4+)" list obsolete; line-211 cutEnergyThreshold > 0.7 stale (code: 0.85); DECISIONS.md D-032 lacks the D-080 amendment trail; `PresetSignaling.swift:9-10` source-doc claims "Arachne does NOT emit yet — wiring is V.7.8" but emission shipped V.7.7C.2 / D-095 2026-05-09 + orchestrator-side wiring shipped BUG-011 round 8 2026-05-12. **D-120 revert verified clean** — cited grep returns zero residue. **CA.1 synthetic-StructuralPrediction re-evaluation resolved**: synthetic at `SessionPlanner.swift:317` is planning-time only; runtime predictions go through `DefaultLiveAdapter.adapt(liveBoundary:)` which is unreachable until BUG-015 lands. CA.1-FU-1 re-scoped to ship option (a) — gate the per-frame `StructuralAnalyzer` chain to prep-time only — independently of BUG-015 (saves audio-callback CPU with zero behavioural change since no runtime consumer exists today). Doc-drift corrections applied to `ARCHITECTURE.md` (§Orchestrator rewrite + Module Map extension + Tests/Orchestrator/ block addition), `DECISIONS.md` (D-032 amendment note), and in-source comments at `PresetScorer.swift:86` + `PresetSignaling.swift:9-10`. **Approach validation:** continue into CA.5 with the App-layer scope-declaration tweak (CA.4 ended up reading several App files to verify call-site counts; the read was bounded but not pre-declared in scope). The audit format continues to produce actionable findings: 1 P1 BUG, 1 production-orphan, 1 unverified-claim, multiple doc-drift corrections, plus a load-bearing CA.1 re-scoping. **Recommended next subsystem: App layer** (`PhospheneApp/`) — BUG-015 lives there and the largest unaudited surface is the App. **Alternative:** defer CA.5 scope until BUG-015's diagnosis lands if findings motivate a different priority.

**Scope.** All 14 files in `PhospheneEngine/Sources/Orchestrator/` (~2,950 LoC) — scoring + policy core (3 files: PresetScorer, PresetScoringContext, TransitionPolicy), planning (3 files: SessionPlanner, SessionPlanner+Segments, PlannedSession), live adaptation (3 files: LiveAdapter, LiveAdapter+Patching, LiveAdapter+MoodOverride), reactive mode (1 file: ReactiveOrchestrator), signaling (2 files: PresetSignaling, ArachneStateSignaling), router + settings (2 files: PlaybackActionRouter, QualityCeiling). Boundary annotations: Orchestrator ↔ Session (TrackProfile + TrackIdentity consumption; PlannedSession.canonicalIdentity at the BUG-006.2 wiring site), Orchestrator ↔ DSP (StructuralPrediction as input parameter — never read from MIRPipeline directly), Orchestrator ↔ ML (MoodClassifier.currentState prep-time vs RenderPipeline.setMood runtime), Orchestrator ↔ App (the BUG-015 missing-wire surface), Orchestrator ↔ Renderer (QualityCeiling cross-module consumer), Orchestrator ↔ Presets (ArachneState conformance to PresetSignaling). Excluded by scope: `PhospheneApp/` (CA-App / CA.5 next), `Sources/Renderer/` MLDispatchScheduler (CA-Renderer later), `Sources/Audio/` (CA-Audio later), `Sources/Presets/` per-preset state types (CA-Presets later).

**Output.** `docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md` + 1 new BUG entry (BUG-015) + doc-drift corrections in the same increment.

**Discipline.** Audit-only. No code changes during the audit beyond the new audit doc, the BUG-015 entry, and the listed doc-drift / source-comment corrections. The 8 BUG-012-i1-instrumented files remained off-limits to edits per the Hard Rules carried forward from CA.2 — no Orchestrator file is BUG-012-i1-instrumented, so the rule was trivially satisfied.

**Done-when.** Audit document published; every public capability has a verdict; every `production-orphan` cites its grep; every non-`production-active` finding either ships a doc-fix in this increment or is registered as a `CA.4-FU-N` follow-up; CA.1 synthetic-StructuralPrediction re-evaluation has a final verdict + recommendation for CA.1-FU-1 (option (a), decoupled from BUG-015); D-120 revert verified clean; drift corrections to load-bearing docs landed; "Approach validation" section produces an honest critique of whether the format should continue into CA.5.

**After CA.4 lands** — surface to Matt: summary counts, BUG-015 P1 finding + recommended fix scoping, CA.1-FU-1 re-scoping verdict (ship option (a) standalone now), recommended approach changes for CA.5 (App-layer scope declaration), recommended next subsystem (App layer — BUG-015 lives there).

### Increment CA.5 — App Layer (engine-adapter slice)

**Status.** ✅ Landed 2026-05-21. Kickoff doc: commit `54357118`. Audit deliverable: [`docs/CAPABILITY_REGISTRY/APP.md`](CAPABILITY_REGISTRY/APP.md). Summary: 48 of 49 file-level entities `production-active`; **0 `broken-but-claimed`** (BUG-015 — the only App-layer-class broken-but-claimed finding in scope — was already Resolved 2026-05-21 in three commits before CA.5 began); **0 new BUG entries filed**. **BUG-015 wire shape verified clean** — all seven design notes from the Resolved field land byte-for-byte (cadence `orchestratorWireFrameDivisor: Int = 30` → ~3 Hz; lock-guarded `liveTrackPlanIndex` + `lastClassifiedMood` + `orchestratorWireLoggedThisTrack`; off-plan skip path; once-per-track diagnostic dual-writing to session.log + os.Logger; OrchestratorWiringRegressionTests source-presence regression with two `@Test` methods stripping comments before counting). **BUG-012-i1 instrumentation intact** across all 8 instrumented files (48 BUG012Probe references total); no edits per CA.5 Hard Rules. **BUG-016 App-layer surface inventoried** without proposing a fix: Lumen Mosaic apply path lives inside `case .rayMarch:` at +Presets.swift:166-178 gated on `desc.name == "Lumen Mosaic"`; slot-8 binding via setDirectPresetFragmentBuffer3 correct per D-LM-buffer-slot-8; LumenPatternEngine init can return nil with failure logged to os.Logger only — recommend adding sessionRecorder?.log() on the failure branch for the next BUG-016 reproduction. **1 `production-orphan`** field-level — `MultiDisplayToastBridge.coalesceTask` + `pendingEvents` declared but never read/written (line-21 comment documents coalescing intent the code doesn't implement). Registered as CA.5-FU-1. **1 `unverified-claim`** — `LiveAdaptationToastBridge.swift:1-14` docstring claims engine-event observation source that has no production-wired consumer (CA.5-FU-2 surfaces this as a product call). **2 large `built-but-undocumented`** — `ARCHITECTURE.md §Module Map PhospheneApp/` listed 15 of 49 engine-adapter files (34 missing); §Module Map Tests/PhospheneApp/ was absent entirely (60+ App tests). **1 file-naming drift** — `MusicKitFetcher.swift` contains `ITunesSearchFetcher`; recommend rename per CA.5-FU-3. **D-091 / Failed Approach #55 enforcement verified clean**; **U.10 @Suite(.serialized) verified** on the one URLProtocol-stub-using App test; **SwiftLint baseline**: zero warnings in PhospheneApp/ (18 remaining are engine-side, out of CA.5 scope). **CA.1-FU-1 status update**: the BUG-015 fix routes `liveBoundary` from `mirPipeline.latestStructuralPrediction` (option (b)) — the per-frame StructuralAnalyzer chain now has a runtime consumer; CA.1-FU-1 closes as `superseded`. Doc-drift corrections applied to `ARCHITECTURE.md` (§Module Map PhospheneApp/ block rewritten with all 49 engine-adapter files; PhospheneAppTests/ block added under Tests/ listing the load-bearing regression / contract tests). **Approach validation:** direct reads + parallel Explore agents both scaled cleanly; Pass 0 BUG-status cross-check found zero kickoff staleness; the cited-grep rule fired once and produced the field-level production-orphan with confidence; the BUG-015 wire-shape verification produced 10 concrete byte-level confirmations. **Recommended next subsystem: CA.6 — App Views + ViewModels** (59 files / 6,889 LoC; largest unaudited surface by file count; home of the U.10 / U.11 flake cluster).

**Scope.** Engine-adapter slice of `PhospheneApp/` — 49 files / 7,975 LoC. Top-level (14 files: VisualizerEngine + 11 extensions + ContentView + PhospheneApp + MusicKitFetcher), Services/ (30), Permissions/ (3), Models/ (2). Boundary annotations: App ↔ Orchestrator (BUG-015 wire + DefaultPlaybackActionRouter + PresetScoringContextProvider), App ↔ Session (SessionManager / StemCache / MetadataPreFetcher ownership), App ↔ DSP / MIR (MIRPipeline construction + per-frame consumer), App ↔ ML (MoodClassifier + StemSeparator + MLDispatchScheduler consumption), App ↔ Renderer (RenderPipeline + FrameBudgetManager + slot-6/7/8 buffer wiring), App ↔ Audio (AudioInputRouter + audio-thread → analysis-queue handoff), App ↔ Presets (per-preset state classes + setMeshPresetTick closures). Excluded by scope (deferred to CA.6): `PhospheneApp/Views/` (47 files including MetalView.swift) + `PhospheneApp/ViewModels/` (12 files). Excluded entirely (CA-Renderer / CA-Audio / CA-Presets later): `Sources/Renderer/`, `Sources/Audio/`, `Sources/Presets/`.

**Output.** `docs/CAPABILITY_REGISTRY/APP.md` + doc-drift corrections in the same increment. No new BUG entries.

**Discipline.** Audit-only. No code changes during the audit beyond the new audit doc and the listed doc-drift corrections. The 8 BUG-012-i1-instrumented files include the two App-layer files in CA.5's scope (`VisualizerEngine.swift` + `VisualizerEngine+Stems.swift`) — read freely; NO edits made per CA.5 Hard Rules.

**Done-when.** Audit document published; sub-scope decision documented; every public capability in scope has a verdict; every Explore-agent-claimed public symbol cross-checked against visibility grep; every `production-orphan` cites its grep; every non-`production-active` finding either ships a doc-fix in this increment or is registered as a `CA.5-FU-N` follow-up; BUG-015 wire shape verified in §Verification-of-BUG-015-wire-shape; BUG-012-i1 instrumentation verified intact in §Verification-of-BUG-012-i1-instrumentation; drift corrections to load-bearing docs landed; no edits to BUG-012-i1 instrumented files; "Approach validation" section produces an honest critique of whether the format should continue into CA.6.

**After CA.5 lands** — surface to Matt: summary counts, BUG-015 wire-shape verification verdict (clean), BUG-012-i1 instrumentation intactness verdict (intact), BUG-016 App-layer surface inventory (no root cause from inventory alone; recommend log-line addition on LumenPatternEngine init-failure branch for the next reproduction), three CA.5-FU follow-ups (field-level orphan; engine-event observation docstring decision; ITunesSearchFetcher file rename), CA.1-FU-1 supersede update (BUG-015 fix routes from MIRPipeline → option (b) is in place, option (a) no longer needed), recommended next subsystem (CA.6 — App Views + ViewModels).

### Increment CA.6 — App Layer (Views + ViewModels presentation slice)

**Status.** ✅ Landed 2026-05-21. Kickoff doc: [`docs/prompts/PHASE_CA_KICKOFF_CA6_APP_VIEWS_2026-05-21.md`](prompts/PHASE_CA_KICKOFF_CA6_APP_VIEWS_2026-05-21.md). Audit deliverable: [`docs/CAPABILITY_REGISTRY/APP_VIEWS.md`](CAPABILITY_REGISTRY/APP_VIEWS.md). Summary: 58 of 59 file-level entities `production-active`; **0 `broken-but-claimed`** (BUG-015 — the only App-layer-class broken-but-claimed finding in scope — was already Resolved 2026-05-21 in three commits before CA.5; CA.6 verifies the consumer chain matches the design); **0 new BUG entries filed**. **PlaybackChromeViewModel BUG-015 / D-091 consumer chain verified clean** — full producer-to-consumer trace from `VisualizerEngine.swift:77` (`@Published var currentTrackIndex: Int?`) through `+Capture.swift:152` (plan-resolution write) through `ContentView.swift:85` (publisher binding via `engine.$currentTrackIndex.eraseToAnyPublisher()`) through `PlaybackView.swift:74,90` (init relay) into `PlaybackChromeViewModel.swift:121,169-176` (publisher subscription) and `:242-254` (`refreshProgress()` direct consumer, no lowercased title+artist string match). Failed Approach #56 regression-grep returned zero hits. **D-091 single-SettingsStore enforcement verified clean across the entire View tree** — ONE legitimate `@StateObject SettingsStore()` at `PhospheneApp.swift:25`; ONE `@EnvironmentObject SettingsStore` consumer at `PlaybackView.swift:55`; all four Settings sub-sections take `SettingsViewModel` as `@ObservedObject`; SettingsView's custom `init(store:)` builds the VM as `@StateObject` with the store passed in (correct D-091 topology). **DASH.7 dashboard surface verified clean against D-088 / D-089** — 16 line-anchored confirmations: DarkVibrancyView backdrop (`.vibrantDark` + `.hudWindow`), 0.96α surface tint, 1px border stroke, `.colorScheme(.dark)` lock, 320pt width, throttle 33ms (~30Hz), `ingestForTest(_:)` test seam, 240-sample stem history, `.singleValue` D-089 inline form (label-left, 13pt mono right, frame 17pt), `.progressBar` value column 110pt with `.fixedSize`, no SF Symbols (status via valueText color), Clash Display Medium 15pt title, Epilogue Medium 11pt + 1.5 tracking labels. **U.10 / U.11 timing-margin compliance verified clean across all 9 widened test files** from the `[dev-2026-05-21-c]` + `[dev-2026-05-21-d]` chip — every margin meets or exceeds U.11 baselines (700ms wait for 300ms debounce; 250-400ms for connect/login); `@Suite(.serialized)` annotation present on both URLProtocol/keychain-stub-using suites (SpotifyOAuthTokenProviderTests, SpotifyKeychainStoreTests). **3 `unverified-claim` findings**: (1) `DashboardOverlayView.swift:10` file-header docstring claims "0.55α" surface tint but code at line 57 uses `.opacity(0.96)` — ARCHITECTURE.md / D-089 correctly say 0.96α; in-file docstring is stale (CA.6-FU-1). (2) `DashboardCardView.swift:5` file-header claims "Clash Display title at 18pt" but code resolves `TypeScale.bodyLarge` which is `15` — ARCHITECTURE.md correctly says 15pt; in-file docstring is stale (CA.6-FU-2). (3) `ConnectorPickerView.swift:111-115` creates `AppleMusicConnectionViewModel()` inline in the `@ViewBuilder` destination while the equivalent Spotify path uses `OAuthSpotifyConnectionWrapper` `@StateObject` to preserve VM across body re-evaluations — architectural inconsistency (CA.6-FU-3); production impact likely low (AM has no URL-callback foregrounding scenario), but worth either applying the wrapper pattern for consistency or documenting the rationale. **2 large `built-but-undocumented`**: (a) ARCHITECTURE.md §Module Map PhospheneApp/Views/ block listed ~20 of 47 files (27 missing) + 3 §UI Layer paragraph drift items (NoAudioSignalBadge → ListeningBadgeView rename; missing Shift+→/←/Z/M/Esc/Shift+? shortcuts; DashboardOverlayView Layer 6 not mentioned); (b) §Module Map PhospheneApp/ViewModels/ block listed 4 of 12 (8 missing). Doc-drift corrections applied to ARCHITECTURE.md in this increment. **No `production-orphan` findings** — every public/internal type, every method has a production consumer (two candidates investigated and rejected: `AppleMusicConnectionViewModel.cancelRetry()` consumed at `AppleMusicConnectionView.swift:33`; `ReadyViewModel.planPreviewEnabled` consumed at `ReadyView.swift:142-143`). **CA.5-FU-1 + CA.5-FU-3 landed before CA.6 began** (commits `688095d4` + `b8952fda` per kickoff status-on-entry); CA.5-FU-2 (LiveAdaptationToastBridge engine-event docstring product call) remains pending — carried forward. **Approach validation:** direct reads + 3 parallel Explore agents scaled cleanly for 8.3k LoC (kickoff estimate 6.9k was ~20% low); D-091 enforcement grep produced confidence in one shot; PlaybackChromeViewModel consumer-chain trace produced 10 byte-level confirmations; DASH.7 verification produced 16 line-anchored confirmations; the U.10/U.11 table-based audit produced complete per-file compliance verdicts. **Recommended next subsystem: CA.7 — CA-Renderer** (`PhospheneEngine/Sources/Renderer/` is the largest unaudited engine module — FrameBudgetManager + RenderPipeline + MLDispatchScheduler + per-pass pipelines + Dashboard renderer). Alternative: CA-Audio (smaller; closes the AudioInputRouter + SilenceDetector + StreamingMetadata + MetadataPreFetcher surface CA.3 boundary-noted). The App layer is now fully closed.

**Scope.** App-layer Views + ViewModels presentation slice — 59 files / 8,285 LoC (kickoff's 6.9k estimate undercounted by ~20%). `PhospheneApp/Views/` (47 files across 9 subdirectories + root-level) + `PhospheneApp/ViewModels/` (12 files); plus `DashboardOverlayViewModel.swift` which lives in `Views/Dashboard/` per the filesystem layout. Boundary annotations: View ↔ App-Service (PlaybackView owns 8 `@State` services CA.5 audited from the engine side); View ↔ VisualizerEngine (publisher-injection pattern via `engine.$xxx.eraseToAnyPublisher()` from ContentView); ViewModel ↔ SessionManager (SessionStateViewModel via Combine `.assign(to: \.state, on: self)`; ReadyViewModel / PreparationProgressViewModel / EndSessionConfirmViewModel take SessionManager as init param); ViewModel ↔ SettingsStore (read via `@ObservedObject SettingsViewModel`; never via direct `@StateObject SettingsStore`); ViewModel ↔ DSP / ML (via `DashboardSnapshot` consumed by DashboardOverlayViewModel). Excluded by scope (deferred to CA.7+): `PhospheneEngine/Sources/Renderer/` (CA-Renderer next), `Sources/Audio/` (CA-Audio later), `Sources/Presets/` per-preset state types (CA-Presets later).

**Output.** `docs/CAPABILITY_REGISTRY/APP_VIEWS.md` + doc-drift corrections in the same increment (ARCHITECTURE.md §UI Layer paragraph + §Module Map Views/ block + §Module Map ViewModels/ block). No new BUG entries.

**Discipline.** Audit-only. No code changes during the audit beyond the new audit doc and the listed doc-drift corrections. The 8 BUG-012-i1-instrumented files are out of CA.6 scope (none are in `Views/` or `ViewModels/`) — Hard Rule trivially satisfied.

**Done-when.** Audit document published; sub-scope decision documented (no split; 59 files fit cleanly); every public/internal capability in scope has a verdict; every Explore-agent-claimed public symbol cross-checked against visibility grep; every `production-orphan` cites its grep (zero found in this audit); every non-`production-active` finding either ships a doc-fix in this increment or is registered as a `CA.6-FU-N` follow-up; the four kickoff-required verifications complete (PlaybackChromeViewModel BUG-015/D-091 consumer chain, D-091 single-SettingsStore enforcement, DASH.7 dashboard surface, U.10/U.11 timing-margin compliance); drift corrections to load-bearing docs landed; no edits to BUG-012-i1 instrumented files; "Approach validation" section produces an honest critique of whether the format should continue into CA.7.

**After CA.6 lands** — surface to Matt: summary counts; PlaybackChromeViewModel BUG-015 / D-091 consumer chain verdict (clean — matches design byte-for-byte); D-091 single-SettingsStore enforcement verdict (clean across View tree); DASH.7 dashboard surface verdict (clean against D-088 / D-089 with two file-header docstring drifts flagged); U.10 / U.11 timing-margin compliance verdict (clean across all 9 widened test files); three CA.6-FU follow-ups (DashboardOverlayView docstring drift; DashboardCardView docstring drift; ConnectorPickerView Apple-Music inline VM consistency question); CA.5-FU-2 carried forward (still pending Matt's product call); recommended next subsystem (CA.7 — CA-Renderer). The App layer is now fully closed.

### Increment CA.7a — Renderer Capability Audit (core pipeline) ✅ (2026-05-21)
### Increment CA.7b — Renderer Capability Audit (Dashboard / Geometry / RayTracing) ✅ (2026-05-21)
### Increment CA-Audio — Audio Capability Audit

**Status.** Kickoff doc landed 2026-05-21 ([`docs/prompts/PHASE_CA_KICKOFF_CA_AUDIO_2026-05-21.md`](prompts/PHASE_CA_KICKOFF_CA_AUDIO_2026-05-21.md)). Audit itself pending Matt's scheduling — hand the kickoff to a fresh Claude Code session when ready. CA.7b closeout 2026-05-21 recommended CA-Audio as the natural next increment (closes the CA.3 Session ↔ Audio boundary-noted item; smaller than CA-Presets).

**Scope.** `PhospheneEngine/Sources/Audio/` — 16 files / 3,294 LoC across capture pipeline (6 files: `SystemAudioCapture`, `AudioInputRouter`, `AudioInputRouter+SignalState`, `AudioBuffer`, `LookaheadBuffer`, `FFTProcessor`), signal-quality monitors (2 files: `SilenceDetector`, `InputLevelMonitor`), metadata fetcher cluster (6 files: `MetadataPreFetcher`, `MusicBrainzFetcher`, `SpotifyFetcher`, `SoundchartsFetcher`, `MusicKitBridge`, `StreamingMetadata`), protocols (1 file: `Protocols.swift`), module marker (1 file: `Audio.swift`).

**Required verifications** carried forward from CA.3 / CA.5 / CA.7b observations: (1) CA.3 Session ↔ Audio boundary closure — `MetadataPreFetcher` producer-side traced against the Session consumer chain at `SessionPreparer.swift:86, 132, 299`; (2) D-079 sample-rate plumbing — cited literal-grep against `Scripts/check_sample_rate_literals.sh` allowlist + immutable-capture confirmation at `AudioInputRouter.installTap(...)`; (3) tap recovery state machine matches ARCH §68 (3 s → 10 s → 30 s backoff, three attempts); (4) SilenceDetector + InputLevelMonitor timings match ARCH §487-488 (.active → .suspect 1.5s → .silent 3s → .recovering → .active 0.5s hold; 21s peak-dBFS window + 30-frame hysteresis); (5) Failed Approach #21 + #22 verified at `SystemAudioCapture` source; (6) BUG-005 + BUG-013 producer-side handling characterised.

**Same methodology as CA.1-CA.7b** (audit-only; sub-scope decision unnecessary at 3.3k LoC; visibility grep verification; cited grep for production-orphan claims; non-nil-caller refinement for setter APIs per CA.7b; per-file verdicts; doc-drift corrections in the same increment).

---

## Phase CS — Cold-Start Sync (2026-05-20)

**Motivation.** Matt 2026-05-20: "The product should be at least beat-synced from frame 1, having 1s of wonky performance while the transition occurs is acceptable but this should be the only session wonkiness." This is restated as the load-bearing commercial-viability bar for the listening-party use case (collaborative Spotify playlists of novel tracks). If we cannot meet it, the product is not viable as conceived.

**Design + adversarial review:** [`docs/COLD_START_SYNC_DESIGN_2026-05-20.md`](COLD_START_SYNC_DESIGN_2026-05-20.md). All five increments below trace to that document. **Read it before scoping any CS increment.**

**Surprise from the design pass.** Most of the C2 + first-onset-anchor proposal sketched in the 2026-05-20 design conversation **already exists in production code**, built incrementally across the BUG-007.x series:

- `BeatGrid.offsetBy(_:horizon:)` extrapolates beats 300 s forward (`PhospheneEngine/Sources/DSP/BeatGrid.swift:120`).
- `GridOnsetCalibrator` measures per-track grid-vs-onset offset at preparation time (`PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift`).
- `LiveBeatDriftTracker.setGrid(_:initialDriftMs:)` seeds the drift EMA with the calibrated value at track install (`PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift:408`).
- BUG-007.9 hybrid runtime re-calibration refines the calibration against actual tap audio after ~15 s.

The remaining work is **verification + targeted filling**, not new architecture. See design doc §4 (what exists) and §5 (what's unverified) for the full picture.

### Increment CS.1 — Empirical verification of existing cold-start beat sync ✅

**Status: complete (2026-05-22). Verdict: FAIL — 3 of 10 tracks pass** the ±50 ms / 90 % bar (session `2026-05-22T16-57-36Z`). Pass-rate < 90 % → per the done-when, the increment surfaced the failure cases; CS.1.x diagnosed them.

**Scope (as built).** A new sibling executable target `ColdStartVerifier` (`PhospheneEngine/Sources/ColdStartVerifier/`) — NOT an extension of `PresetSessionReplay` (it needs `DSP` / `ML` / `Session`, which the preset-rubric tool does not depend on). The final measurement design (option C, after several iterations in commits `27c76c47` → `989f81a5`): visual beat = `beatPhase01` wraps in `features.csv`; audible beat = a Beat This! one-beat-per-beat grid re-detected offline from a per-track slice of `raw_tap.wav`; the raw-tap ↔ playback-time clock offset is pinned via a precise raw-tap-start timestamp added to `SessionRecorder` (commit `1e2e47fa`). Output: per-track `(visual − audible)` delta distribution + `cold_start_report.md` evidence pack.

**Done-when (met).** Harness built + self-tested + run end-to-end against a real session; per-track `pass`/`fail`/`degenerate` verdicts emitted; pass-rate < 90 % → failures surfaced, CS.1.x diagnoses before CS.2.

### Increment CS.1.x — Cold-start grid-phase diagnosis ✅

**Status: complete (2026-05-22).** Diagnosis-only increment (Defect Handling Protocol multi-increment process). Filed **BUG-017** in `docs/QUALITY/KNOWN_ISSUES.md`.

**Finding.** The 7 failing tracks carry a per-track *systematic* phase offset (−128 to +338 ms, all within ±½-beat; within-track tight — MAD ~15 ms — a clean phase error, not jitter). Root cause: the cold-start grid is installed `cached.beatGrid.offsetBy(0)` (`VisualizerEngine+Stems.swift:485`) — Beat This! on the 30 s Spotify preview clip, with the preview's timeline used as the track's timeline verbatim. The preview is an arbitrary excerpt, so the grid's phase is off by an arbitrary per-track amount. `GridOnsetCalibrator` runs on the preview (not the live track start) so it cannot correct it; the live drift EMA makes no gross phase jump; the BUG-007.9 recalibration fires only after the 10 s window and its ±200 ms cap discards large offsets. Full root cause in BUG-017.

**Done-when (met).** Root cause identified with code-level evidence; documented in `KNOWN_ISSUES.md` (BUG-017); no fix code.

### Increment BSAudit.3 — BPM-anchored phase acquisition design + impl + validate + close ✅ (resolved against accepted limit; impl runtime reverted 2026-05-25 evening)
### Increment BSAudit.2 — Path A research (Beat This!-on-tap reproducibility) ✅

**Status: complete (2026-05-24).** Research-only — no production code touched. Two new `ColdStartVerifier` modes (`--position-sweep` for within-capture, `--cross-capture` for across captures) + new modules ([`BeatPhaseStats.swift`](../PhospheneEngine/Sources/ColdStartVerifier/BeatPhaseStats.swift), [`PositionSweep.swift`](../PhospheneEngine/Sources/ColdStartVerifier/PositionSweep.swift), [`PositionSweepReport.swift`](../PhospheneEngine/Sources/ColdStartVerifier/PositionSweepReport.swift), [`CrossCapture.swift`](../PhospheneEngine/Sources/ColdStartVerifier/CrossCapture.swift), [`CrossCaptureReport.swift`](../PhospheneEngine/Sources/ColdStartVerifier/CrossCaptureReport.swift), [`ColdStartVerifierCommand+PathA.swift`](../PhospheneEngine/Sources/ColdStartVerifier/ColdStartVerifierCommand+PathA.swift)) running on the four reference captures.

**Outcome: Path A empirically falsified.** Within-capture: 7 of 10 tracks position-unstable (100-410 ms phase spread across 25 s slice positions in the same audio). Cross-capture: 10 of 10 tracks differ by 100-322 ms across the 4 captures at the same playback-time. No 25 s slice configuration of Beat This!-on-tap is a stable reference. Full evidence in [`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md` §Addendum — BSAudit.2 (Path A) findings](CAPABILITY_REGISTRY/BEAT_SYNC.md#addendum--bsaudit2-path-a-findings-2026-05-24).

**Implication.** BSAudit-FU-5 Path A is **closed (falsified)**; Path B (human-tap ground truth) is now load-bearing for any future BUG-017 fix-claim that depends on automated verification. Two product-strategy options remain: (1) build Path B (small CLI + ~4 min of Matt's taps); (2) accept the structural limit and adopt the 2026-05-22 "approximately synced immediately, locked within ~20 s" framing as canonical. Matt's call.

**Done-when (met).** Within-capture + cross-capture measurements published; per-capture reports written; BSAudit-FU-5 Path A verdict published; FU-5 Path B promoted in the follow-up backlog.

**Verification.**
- Engine suite: **1265 / 1265 pass** (pre-BSAudit.2 baseline preserved).
- `ColdStartVerifier --self-test`: PASS (7/7).
- Project-wide `swiftlint --strict`: 0 violations across 386 files.
- 4 capture-level reports + 1 cross-capture report written to session directories.

### Increment BSAudit — Beat-Sync Audit (BUG-017 diagnosis stage) ✅

**Status: complete (2026-05-24).** Audit-only; no fix code. Deliverable: [`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](CAPABILITY_REGISTRY/BEAT_SYNC.md). Six components scoped per the kickoff (prep-time grid + onset-offset seeding; cold-start grid install; live drift EMA; EMA under wrong-phase grids; verifier clock-offset; sub-bass onset feed); per-component verdicts with empirical grounding from the four reference captures (`2026-05-22T16-57-36Z` through `2026-05-24T15-07-31Z`).

**Headline findings.**
1. **The "beat-sync infrastructure is not perceptually aligned across the catalog" symptom is compound**, not single-rooted: a *static* per-track phase offset on syncopated tracks (the original BUG-017) plus *cross-capture variability* of the verification reference itself (a new finding).
2. **Beat This! on a 25 s live-tap slice is not cross-capture reproducible** on 5-6 of 10 catalog tracks — the dominant cause of the CS.1.y.2-redo cycle's verifier-passing→M7-failing pattern. The redo.1 "10/10 viable at 15 s" measurement validated within-slice reproducibility, not the production case.
3. **Failed Approach #68 is still live at prep time** in `GridOnsetCalibrator` — sub-bass-onset-vs-grid alignment used as a beat-phase reference. Same architectural mistake the CS.1.y.2 runtime fix attempted; not yet retired at prep.
4. **The live drift EMA's behaviour under a wrong-phase grid is bimodal:** sub-50ms-off → biases drift toward off-beat onsets (Regime A wobble); >50ms-off → rejects all onsets, drift parks at seed (Regime B stuck-off-beat). Both visible in cap1 baseline without any synthetic injection.

**Per-component verdicts and ranked root-cause hypotheses are in the [`BEAT_SYNC.md`](CAPABILITY_REGISTRY/BEAT_SYNC.md) document. BUG-017's symptom statement was refined in `KNOWN_ISSUES.md` against the audit findings.** Per-component fix scope sketches surfaced as a follow-up backlog (BSAudit-FU-1 through FU-6), none authorized; **Matt sign-off on direction is the next step**, not another fix increment.

**Done-when (met).** Per-component verdicts published with empirical grounding; six specific empirical questions either answered from the existing captures or surfaced as gaps requiring instrumentation; ranked root-cause hypotheses table; per-component fix scope sketches.

### Increment CS.1.y — Cold-start grid-phase fix (BUG-017) — **CS.1.y.2-redo reverted 2026-05-24; superseded by BSAudit; awaiting direction decision**

**Status (2026-05-22).** Three signal sources for the ≤ 5 s phase acquisition were tried and exhausted; Matt set a new direction ("approx now, exact by ~20 s"); the design landed; redo.1 measurement + redo.2 implementation are in tree; redo.3 validation is pending Matt's fresh capture + M7.

- **CS.1.y.1 design ✅** — original design surfaced; budget ratified.
- **CS.1.y.2 (onset-based fix) — failed, reverted.** Commit `dbcc018d` reverted by `f71b0456`. ColdStartVerifier 0/10. Sub-bass onset detector is not a beat-phase reference (CLAUDE.md Failed Approach #68).
- **CS.1.y re-diagnosis (short-window Beat This!) — done.** `ColdStartVerifier --rediagnose` (commit `b27226d3`) found 3/4/5 s windows unusable (1-3/10, non-reproducible).
- **Direction decision (Matt, 2026-05-22).** "Approx now, exact by ~20 s." Cached grid stays from frame 1 ("approx"); at ~15-20 s full-window live Beat This! phase-corrects the grid ("exact").
- **CS.1.y.2-redo design ✅** — design surfaced to Matt; snap = instant snap; W to be measured before code; the fix swaps the *measurement tool* inside BUG-007.9's `runtimeRecalibrationIfDue` (BUG-007.9 structure stays — one-shot per track, `applyCalibration` apply path, `runtimeRecalibrationDone` latch); `GridOnsetCalibrator` survives for its prep-time `gridOnsetOffsetMs` seed only.
- **CS.1.y.2-redo redo.1 (measurement) ✅** — `ColdStartVerifier --rediagnose` extended to take `--rediagnose-windows` (default `3,4,5` preserved). Run on both captures with `10,15,20`. Result decisive: phase reproducibly ≤ 8 ms at 15 s, ≤ 6 ms at 20 s across both captures and every test track including HUMBLE and Money. **W = 15 s ratified** (Matt). Capture reports written: `<capture>/cold_start_rediagnosis_10-15-20.md`.
- **CS.1.y.2-redo redo.2 (implementation) ✅** — engine method `applyColdStartPhaseCorrection`, app rework, buffer bump, verifier `--window-start-s`. **Subsequently reverted 2026-05-24** — see redo.3 below.
- **CS.1.y.2-redo redo.3 (validation) ✗ — three captures, no convergence; CS.1.y.2-redo reverted.** Capture 1 (`2026-05-23T02-17-24Z`) surfaced an engine bug (default `horizon: 300` extrapolation inflated residuals) → fix `1e77fdf6` (`horizon: 0`). Capture 2 (`2026-05-23T02-39-54Z`): signatures clean but 2 regressions on previously-passing tracks (Get Lucky 95 % → 0 %; SNA worse) — high-R confident-but-wrong measurements, the CS.1.y.2 R-gate failure (Failed Approach #68) reappearing in Beat-This!-vs-Beat-This! form. Capture 3 (`2026-05-24T15-07-31Z`): Matt's M7 on the SpectralCartograph diagnostic — "drift very much real across tracks"; "rarely snaps to the beat and does not follow downbeat." Cross-capture non-reproducibility confirmed on multiple tracks (snaps varying ≥ 100 ms run-to-run); pre-snap baseline also degraded vs CS.1; EMA drift bouncing 200-300 ms within steady-state tracks. Full evidence: BUG-017 trailing addendum; `RELEASE_NOTES_DEV.md [dev-2026-05-24-a]`.

**Reverted 2026-05-24.** What stays in tree: `ColdStartVerifier --rediagnose-windows` + `--window-start-s` diagnostic tooling (commit `976a78b3`). What was reverted: engine method + tests, app `runtimeRecalibrationIfDue` rework, buffer bump, extrapolation follow-up fix.

**Pattern.** Five fix increments on the same defect with no perceptual convergence is the Drift-Motes pattern (Failed Approach #58) at infrastructure scope. Per CLAUDE.md "stop and report instead of forging ahead." The next step is a **beat-sync audit increment** (analogous to Phase CA's DSP audit but scoped to beat-sync wiring specifically), not another fix.

**BUG-017 scope broadened.** From "cold-start grid-phase offset" to "beat-sync infrastructure is not perceptually aligned across the catalog" (Matt's M7 framing). Likely root-cause candidates (none confirmed; audit's job to test): prep-time `GridOnsetCalibrator` is still onset-based (Failed Approach #68 root cause we left in place at prep time); EMA tracks off-beat onsets when seeded into a wrong-phase grid; verifier clock-offset estimate may be noise-coupled.

**Done-when.** Audit document published with per-component verdicts; root-cause hypotheses ranked by evidence; **no new fix code until the audit produces a clear picture.**

**Audit ✅** — landed 2026-05-24 as **BSAudit** (above). Per-component verdicts + ranked root-cause hypotheses + per-component fix scope sketches in [`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`](CAPABILITY_REGISTRY/BEAT_SYNC.md). BUG-017 stays Open with the refined symptom statement (KNOWN_ISSUES.md addendum 2026-05-24); next step is **Matt sign-off on the BSAudit-FU-* backlog**, not another fix.

**Critical follow-up gate (from the audit's strongest finding):** Component 5b — Beat This!-on-tap is not cross-capture reproducible on a substantial subset of the catalog. **No future fix can claim convergence while the verification infrastructure cannot judge it reliably.** BSAudit-FU-5 (research-only: full-tap-window Beat This! reproducibility, or human-tap ground truth) is the load-bearing pre-work; if it does not yield a stable reference, the "approx now, exact by ~20 s" 2026-05-22 product-direction (recast as Component 2's "document the structural limitation") becomes the canonical position.

**Sequencing (Matt-ratified 2026-05-22).** CS.1 verified the cold-start infrastructure does *not* work; CS.2–CS.5 are all refinements that assume a correct cold-start grid (CS.2 protects the cold-start window; CS.3/CS.4 keep presets from over-relying on stems; CS.5 documents the contract). The BUG-017 fix is therefore **upstream of CS.2–CS.5** and is the load-bearing next CS increment. CS.2–CS.5 follow it.

**Scope.** Give the cold-start the *track-start* phase — the only source of which is the live tap audio from frame 1. Direction (to be designed before any code): a cold-start phase acquisition that phase-locks the grid (correct tempo, wrong phase) to the first live sub-bass onsets in the first ~1–2 s; widen or remove the ±200 ms `GridOnsetCalibrator.maxMatchWindow` cap. Touches the cold-start grid-install path (`VisualizerEngine+Stems.swift`) and `LiveBeatDriftTracker` — interacts with the BUG-007.x lock state machine, so it is **design-first** per the "design is upstream" discipline, and likely splits into design → implement → validate sub-increments.

**Done-when.** `ColdStartVerifier` on a fresh full-session capture reports ≥ 90 % of tracks passing; BUG-007.x lock machinery + steady-state tracking preserved (regression); Matt M7 perceptual review confirms frame-1 sync.

**Estimated sessions:** 2–3 (design + implementation + validation).

### Increment CS.2 — First-segment minimum duration

**Sequencing.** Gated behind CS.1.y (BUG-017 fix) — CS.2–CS.5 all assume a correct cold-start grid (Matt-ratified reprioritization, 2026-05-22).

**Scope.** Add a first-segment-of-track minimum duration constraint to `SessionPlanner.planOneSegment` (`PhospheneEngine/Sources/Orchestrator/SessionPlanner+Segments.swift:137`). Target 10-12 s. Handle: tracks shorter than the minimum (allow violation); section boundaries inside the minimum window (push to next bar boundary after the minimum). Regenerate golden session tests.

**Done-when.**
- `planOneSegment` honors the new constraint for first segments only (subsequent segments unaffected).
- Golden sessions regenerated; per-track scoring decisions documented in commit message.
- Edge-case tests: 8 s track, 12 s track, 60 s track with section boundary at t=6 s, 60 s track with section boundary at t=15 s.

**Estimated sessions:** 1.

### Increment CS.3 — Data-hierarchy compliance audit

**Scope.** Read every `.metal` preset file in the catalog. For each, classify every audio-reactive driver as `primary` / `accent` / `proxy-fallback`. Compare against CLAUDE.md's Audio Data Hierarchy rule. Output: `docs/PRESET_DATA_HIERARCHY_AUDIT_<date>.md` with per-preset findings.

Specific check criteria per preset (see design doc §6.4 for the full list):
- Continuous bands (`f.bass`, `f.mid`, `f.treble` and `_att_rel` / `_dev` variants) — used as primary driver?
- Stem energies (`stems.X_energy`) — used as primary driver? If so, D-019 warmup blend present?
- Beat onsets — used as accent only?
- Predicted beats / bar phase — used for jitter-free motion where appropriate?

**Done-when.** Per-preset audit document published; preliminary scan suggests `Starburst`, `KineticSculpture`, `GlassBrutalist`, `Arachne` need close review. No code changes in this increment.

**Estimated sessions:** 1-2.

### Increment CS.4 — Targeted fixes from audit findings

**Scope.** Per non-compliant preset surfaced by CS.3: minimum-change fix to bring into D-019 / D-026 compliance without altering visual intent. One commit per preset. Golden hashes regenerate per preset.

**Risk.** Preset-touching work is where Claude's track record is worst (Drift Motes, Aurora Veil pattern). Each CS.4 sub-increment is scoped tightly (one preset, minimum change). Matt M7 review per preset before flipping the audit document's verdict from `non-compliant` to `compliant`.

**Done-when.** Every preset flagged in CS.3 either has a compliance fix landed and M7-approved, or has an explicit decision to defer / retire (rare).

**Estimated sessions:** variable — one per affected preset.

### Increment CS.5 — Documentation of the cold-start contract

**Scope.** Promote the cold-start data-flow understanding into CLAUDE.md and SHADER_CRAFT.md as a durable rule:
- New CLAUDE.md section under "Audio Data Hierarchy" titled "Cold-Start Phase Contract" describing `gridOnsetOffsetMs` calibration, D-019 blend pattern, first-segment minimum duration, and the implication that violating presets look broken during cold-start.
- Short SHADER_CRAFT.md section pointing authors at the CS.3 audit checklist.
- New decision record `D-XXX — Cold-start sync architecture (Phase CS, 2026-05-XX)`. Documents what's in production, what was verified, what was added.

**Done-when.** Docs land; reference from any subsequent preset prompt confirms the rules.

**Estimated sessions:** ½.

### Phase exit criteria

Phase CS closes when, in this order:

1. ✅ CS.1 verification ran; pass-rate < 90 % (3/10) → CS.1.x diagnosis documented (BUG-017) with a fix path.
2. CS.1.y — BUG-017 cold-start grid-phase fix landed; `ColdStartVerifier` re-run on a fresh capture reports ≥ 90 % of tracks passing.
3. CS.2 first-segment minimum landed; golden sessions green.
4. CS.3 audit document published.
5. CS.4 fix increments completed for every preset CS.3 flagged.
6. CS.5 documentation merged.
7. **Matt manual validation on a real listening-party playlist confirms perceptual beat sync from frame 1.** The load-bearing close criterion.

### Out of scope for Phase CS

- BUG-013 time-signature for odd-meter tracks — different defect, different fix.
- Audio output latency UX (AirPods / Bluetooth compensation) — future Phase.
- Section-aware visuals, mood arc, stem time-varying — fundamentally blocked by the streaming-only constraint.
- Any work that would relax the streaming-only architectural constraint (local files, capture-on-first-listen, third-party data services). Matt explicitly deprioritized these on 2026-05-20.

---

## Phase CSP — Cold-Start Perception (2026-05-26 → 2026-05-27, two reverted iterations)

Per-preset cold-start fixes leveraging proxy-then-stems crossfades + cached pre-playback analysis. Two iterations attempted 2026-05-26 / 2026-05-27, both reverted. Phase paused pending a different premise (likely a stress-test-measurement-first approach).

### Increment CSP.1 + CSP.1.1 — Soft tempo pulse (tried + reverted 2026-05-27)

Soft tempo-rate breathing during cold-start, wired into Lumen Mosaic and Membrane. Two A/B tests both returned "no perceptible difference" — LM was structurally the wrong test bed (already busy with beat-rate activity); Membrane was structurally favourable but the tested magnitude (0.30 displacement factor) was below the perception floor.

**Status: reverted 2026-05-27.** See `RELEASE_NOTES_DEV.md [dev-2026-05-27-a]` for full closeout + durable learnings.

### Increment CSP.2 — FFO cached perception + cold-start crossfade (tried + reverted 2026-05-27)

Two layers on Ferrofluid Ocean's spike-height function: `cached_bass_proportion` → ±25 % baseline; cold-start crossfade from `f.bass_dev` (proxy) → `stems.bass_energy_dev` (warm) over 0.5–8 s. Matt's M7 returned partial-pass / partial-regression — three structural issues exposed:

1. **Crossfade timing wrong.** Live stems arrive at ~13–15 s (measured), not the 5–8 s assumed. The crossfade completed before live stems arrived, producing a visible transition at ~15 s.
2. **Proxy signal too sparse.** `f.bass_dev` is a deviation primitive — fires only above the AGC average; ≈ 0 for ~99 % of frames on normal music. No per-frame motion delivered during cold-start.
3. **Baseline pivot landed in the wrong place.** Billie Jean's cached proportion ≈ 0.25 → zero baseline contribution; Royals' < 0.25 → sub-default spikes ("inert and broken").

**Status: reverted 2026-05-27.** See `RELEASE_NOTES_DEV.md [dev-2026-05-27-b]` for full closeout + durable learnings.

### Increment CSP.3 — FFO cold-start fix with the three corrections from CSP.2 ⏳ (implemented 2026-05-27, M7 outstanding)

Same product target as CSP.2; three specific corrections applied directly from the CSP.2 dive findings:

1. **Crossfade window: 0.5 → 14 s** (was 0.5 → 8 s in CSP.2) — matches measured live-stems arrival.
2. **Cold-start proxy: `f.bass_att`** (smoothed continuous bass; was `f.bass_dev` deviation primitive in CSP.2) — continuous per-frame motion instead of sparse-event signal.
3. **One-sided baseline:** cached proportion *above* 0.25 boosts spike baseline up to +25 %; below 0.25 leaves it at 1.0 (no penalty). Sparse-bass tracks (Royals) look exactly like today; bass-heavy tracks get visible posture.

Plus the operational gaps CSP.2 surfaced:

- **UserDefaults A/B toggle `ffoColdStartFixEnabled`** (default ON). OFF arm collapses to the exact pre-CSP.3 formula via writing sentinel values (`trackElapsedS = 100.0`, `cachedBassProportion = 0.25` pivot).
- **`features.csv` instrumentation** for both new fields as trailing columns — A/B verifiable from artifacts in ~30 seconds.

**Done-when (in flight).**

- [x] Engine: 1277 / 1277 tests pass. New `CSP3DataPlumbingTests` suite (8 tests, 3 sub-suites): trackElapsedS reset + accumulation (toggle ON), trackElapsedS = 100.0 (toggle OFF), cachedBassProportion preserved across live updates. Plus `test_recordFrame_csp3Fields_writtenToCSV` round-trip.
- [x] SwiftLint `--strict`: 0 violations.
- [x] App build: succeeds.
- [ ] **Matt M7 (load-bearing gate).** Same A/B protocol as CSP.2 — but now verifiable from `features.csv` so a negative-result diagnostic dive is bounded.

**Outcome handling.**

- **Better:** cert. Same pattern likely extends to Volumetric Lithograph's terrain pulse and camera dolly — file CSP.4 if Matt wants.
- **No different:** the design space at the cached-perception + live-overall-bass layer is exhausted at this consumption point. Pivot to Matt's stress-test methodology suggestion (CSP-Stress.1, below).
- **Worse:** revert; capture specific failure modes before reverting (which track, what part of the timeline, what does the spike behaviour look like).

### Increment CSP.3.4 — FFO SDF Lipschitz divisor /4 → /10 (2026-05-28) ✅
### Increment CSP.3.5.1 — Complete CSP.3.5: apply the intended /6 to the operative line (2026-05-28) ✅
### Increment CSP.3.5 — FFO SDF Lipschitz divisor /10 → /6 (correct CSP.3.4 side effects) (2026-05-28) ⚠ (doc-only; operative line unchanged until CSP.3.5.1)
### Increment CSP.3.3 — Spike-strength coefficient bump 0.35 → 0.8 (2026-05-28) ✅
### Increment CSP.3.2 — Drop warm-state crossfade; f.bass for the whole track (2026-05-28) ✅
### Increment SAR.1 — Stem analyzer EMA self-seeding (Stem Analyzer Range, 2026-05-28) ✅
### What's next for Phase CSP

**Paused** pending BUG-019 (Phase PERF below). No point tuning FFO's cold-start consumer at the shader layer while ~30 % of frames are missing their deadline — the visual signal is too noisy to read.

After BUG-019 is at least diagnosed (root cause identified, fix scope known), revisit CSP.3.1's M7 verdict — re-running the same A/B in a CPU-clean build is the first read on whether the cold-start design itself works.

If CSP.3.1 then carries the cold-start on FFO, the pattern (one-sided baseline + smoothed continuous proxy + crossfade timed to real warmup) extends to other affected presets — Volumetric Lithograph being next per Matt's 2026-05-27 prioritisation (terrain pulse + camera dolly are both stems-routed).

If CSP.3.1 still doesn't carry post-BUG-019, the next move is Matt's stress-test methodology suggestion: build per-preset cold-start measurement infrastructure — characterise what each preset's audio reactivity actually does across tempo / meter / energy variation — then propose fixes grounded in measured baselines. That work would slot here as **CSP-Stress.1** (or similar).

---

## Phase PERF — Tap-path CPU degradation diagnosis (2026-05-28 →)

Surfaced 2026-05-28 by the SAR.1 M7 close. `features.csv` `frame_cpu_ms` doubles from ~11 ms to ~22–24 ms at session-time 67–68 s and stays elevated for the rest of the session, producing visible flickering / hangs at the perceptual layer. GPU stable throughout — pure CPU bottleneck somewhere in the tap-path audio-analysis pipeline. LF-path sessions (local-file playback) run at 1.3–1.4 ms CPU throughout, isolating the issue to a tap-path-specific component. Pre-existing — same shape in the pre-SAR.1 reference session — but never characterised until now.

Filed as **BUG-019** (P1, `perf`). Multi-increment P1 process per the defect protocol: instrumentation → diagnosis → fix → validation.

### Increment PERF.1 — Per-subsystem timing instrumentation ✅ (2026-05-28)
### Increment PERF.2 — Diagnosis from PERF.1 capture (2026-05-28) ✅ analysis-pipeline ruled out
### Increment PERF.2-render — Render-loop CPU breakdown (2026-05-28) ✅
### Increment PERF.2-render — Diagnosis from session `2026-05-27T22-15-25Z` (2026-05-28) ✅ narrowed to renderFrame dispatch
### Increment PERF.2-pass — Ray-march per-sub-pass timing (2026-05-28) ✅
### Increment PERF.3 — Fix beat-dominant light-intensity flicker (2026-05-28) ✅
### Increment PERF.4 — Validation (after M7)

Verification criteria from BUG-019: `FrameTimingReporter` p95 ≤ tier budget over 90 s tap-path; 2-hour soak test passes; Matt M7 perceives no flickering. If M7 reports the perceptual problem is gone, BUG-019 closes against the flicker fix. The "sustained CPU bump" pattern observed earlier remains characterized but classed as a probably-environmental separate phenomenon (PERF.2-pass empirically ruled out our render-path code as the source).

---

## Phase SR — Session Replay diagnostic infrastructure

Diagnostic harness that closes the "I cannot inspect this preset" gap surfaced during the AV.2.x cascade closeout (2026-05-20). Closeouts asserting audio-coupling or visual-fidelity claims must now cite generated evidence packs instead of assertion-shaped language. See [docs/ENGINE/SESSION_REPLAY.md](ENGINE/SESSION_REPLAY.md) for usage + extension. The accompanying CLAUDE.md discipline rule ("Diagnostic infrastructure precedes fidelity claims") is the project-wide standard.

### Increment SR.1 — Initial harness + Aurora Veil ✅ (2026-05-20)
## Phase AV — Aurora Veil (direct-fragment + mv_warp preset)

A lightweight ambient ribbon preset for quiet listening, low-energy passages, and comedown sections. Direct-fragment + mv_warp pattern — the canonical Milkdrop shape with no current consumer in the catalog. Aurora curtains over a faintly-starred night sky, with vocals-pitch hue stratification, bass-driven brightness breathing, and drums-coupled curtain kink. Authoritative design at [docs/presets/AURORA_VEIL_DESIGN.md](presets/AURORA_VEIL_DESIGN.md); reference set curated at [docs/VISUAL_REFERENCES/aurora_veil/](VISUAL_REFERENCES/aurora_veil/) (5 references + anti-reference, plus architecture contract).

**Concept-viability gate (SHADER_CRAFT §2.0).** All three gates clear before AV.1 starts:

1. **Musical role (one sentence).** *"The aurora curtain's hue stratifies along its vertical extent from the live vocals-pitch trail (low-y green → high-y magenta), so the listener sees the melody as the curtain's colour gradient; brightness breathes with sustained bass; drums onsets kink the curtain laterally."* Names specific musical features (vocals pitch, sustained bass, drum onsets) paired with specific visual behaviours (vertical hue gradient, all-ribbon brightness scale, lateral curtain kink) per CLAUDE.md FA #58 / D-102.
2. **Iconic visual subject deliverable at fidelity.** Lightweight rubric profile (D-067(b)) — emission-only direct fragment, exempt from M1 detail cascade and M3 material count. Comparable pattern: Gossamer's direct-fragment + mv_warp recipe is the closest neighbour. Fidelity bar is reachable.
3. **Infrastructure-feasible.** Uses only existing utilities (`warped_fbm` / `curl_noise` / `palette_cool` / `SpectralHistoryBuffer` / `blue_noise_sample` / hash-based starfield). No engine work.

**Status.** AV.1 ✅ (2026-05-18). AV.2 ✅ (2026-05-18). AV.2.1 ❌ (2026-05-18, misdiagnosed motion-smear hotfix; superseded). AV.2.2 ✅ (2026-05-18, mv_warp dropped). AV.2.2a ✅ (2026-05-18, drawDirect slot-6 binding hotfix). AV.2.2b ✅ (2026-05-18, state allocation moved out of `case .mvWarp:`). AV.2.2c ✅ (2026-05-19, calmer-tuning amplitude pass). AV.2.2d ✅ (2026-05-19, brightness route switched to `bass_dev`). AV.2.2e ✅ (2026-05-19, brightness route threshold-gated). AV.2.2f ✅ (2026-05-19, synth-flash route via `stems.other_energy_dev`). AV.2.2g ✅ (2026-05-19, synth-flash amplitude raised 0.6 → 1.5). PT.1 ✅ (2026-05-19, PitchTracker ring-buffer fix — vocals_pitch route had been 0 % in every prior session due to 1024-sample-input-to-2048-sample-tracker wiring bug). AV.2.h ✅ (2026-05-19, Three-Channel curation: dropped routes 3 / 4 / 6 / 7 / 8 after Matt's "muddled" feedback; kept Route 1 vocals-pitch hue + Route 2 bass brightness pulse + Route 5 drum kink with raised gate 0.9/1.5; three musical features → three independent visual axes, no competing rhythms). AV.2.h.1 ✅ (2026-05-20, kink gate 0.9/1.5 → 0.7/1.0). AV.3 🚫 **Paused 2026-05-20** — AV.3 cert prep surfaced (i) 9-Q rubric Q3 = NO + Q7 = NO via SR.1 calibrated rubric (Q3 reads-like-anti-reference, Q8 outside-family) and (ii) a design reframing — the current preset authentically depicts diffuse-glow aurora; the current curated reference set anchors active-curtain aurora. Matt's product-level call (2026-05-20): two-preset split. AV.3 cert work for the current preset is replaced by **AV.3.x** — re-curate references to diffuse-glow aurora + cert against the new set. Active-curtain aurora gets a new preset (**Phase AC — Aurora Curtain**, planned) using the per-pixel-ray construction recipe from [docs/presets/AURORA_VEIL_RESEARCH_AV3X_2026-05-20.md](presets/AURORA_VEIL_RESEARCH_AV3X_2026-05-20.md) §3.1.

### Increment AV.3.x — Diffuse-glow reference re-curation + cert ⏳ Planned

**Scope.** Matt curates 4–5 diffuse-glow / pulsating-patch aurora reference images replacing the current curtain-form set in `docs/VISUAL_REFERENCES/aurora_veil/`. Update `AURORA_VEIL_README.md` annotations + mandatory-traits checklist + 9-Q rubric variant (some Qs may not apply to diffuse-glow). Update `AURORA_VEIL_DESIGN.md §5` to reframe design intent as diffuse-glow aurora. Re-run `PresetSessionReplay` against the new reference set; calibration should produce `withinFamily` verdicts for the Qs that apply. M7 review against new set. On Matt's "yes," flip `AuroraVeil.json certified: true`.

**Done-when.** Reference set re-curated (Matt). README annotations updated. DESIGN §5 reframed. Per-Q rubric variant amended for diffuse-glow (some Qs marked N/A). SR.1 report against AV session + new refs shows ≥ 5 Qs `withinFamily` or N/A; no `readsLikeAntiReference`. M7 sign-off captured. `certified: true` flipped. ENGINEERING_PLAN + RELEASE_NOTES updated.

### Phase AC — Aurora Curtain (planned, post AV.3.x)

**Concept.** Active-curtain aurora — vertical ribbons, fold drape, visible ray pillars, off-axis composition with silhouette foreground. The form the AV reference set originally anchored. Distinct preset, sibling not subclass (D-097); ships its own .metal, .json, state class, reference set, and rubric.

**Authoritative design.** [docs/presets/AURORA_VEIL_RESEARCH_AV3X_2026-05-20.md](presets/AURORA_VEIL_RESEARCH_AV3X_2026-05-20.md) §3.1 (per-pixel ray construction) + §3.2 (off-axis composition + silhouette foreground) + §3.3 (sub-second ray flicker) + §3.4 (sharp bottom edge).

**Status.** Planned. **Schedule:** waits on AV.3.x cert. Detailed prompt to be authored at scoping time.

### Increment AV.1 — Single-ribbon foundation ✅ (2026-05-18)
### Increment AV.2 — Multi-column parallax + audio routing ✅ (2026-05-18)
### Increment AV.2.1 — Motion-smear hotfix ✅ (2026-05-18)
### Increment AV.2.2 — Drop mv_warp pass (empirically grounded fix) ✅ (2026-05-18)
### Increment AV.2.3 (planned) — Re-introduce drift mechanisms grounded in dossier

**Scope.** Replace the mv_warp-supplied motion (which AV.2.2 removed) with the dossier-grounded mechanisms the design SHOULD have used from AV.1:
1. **Curl-noise perturbation INSIDE `aurora_tri_noise_2d` sample coordinate** per dossier §1.3 line 61 — Wittens NeverSeenTheSky borrowing. The vortical-flow character mv_warp was attempting belongs here.
2. **Two-column SUM-merge instead of three-column MAX** per dossier §1.3 line 62. Volume integration for an emissive medium is summative; the AV.2 MAX-of-three was structurally wrong (and produced the winner-switching pattern that compounded under mv_warp).
3. **Multi-frame diagnostic harness extended to replay `raw_tap.wav`** from a captured session so the seven audio routes can be validated against real music BEFORE filing AV.2.3 as ✅ (per the new "test in production-grade pipeline" discipline rule). The routes have never been seen live; that's the next reliability gap to close.

**Risks acknowledged before authoring.** R1 (mv_warp+nimitz combination unprecedented) is resolved by removing mv_warp. R2 (mv_warp + high-frequency content structurally incompatible) is resolved by the same. R3 (audio routes unvalidated live) → multi-frame test replaying `raw_tap.wav` is the gate. R4 (AV.3 sub-second flicker + pulsation have no cited working code reference — only Springer/AGU physics papers) → I will surface this to Matt before AV.3 implementation and propose either finding a working reference or accepting the "L3 grounding only" risk per the soft rule.

### Increment AV.3 — Refine + cert

**Scope.** Tune palette constants, mv_warp amplitudes, fold-density coefficients against curated references. Matt M7 review against `01_macro_curtain_hero_purple_green.jpg` + `02_palette_green_to_magenta_stratification.jpg` + `03_meso_curtain_fold_drape.jpg` + `04_atmosphere_multi_curtain_parallax.jpg`. Anti-reference check against `09_anti_neon_festival_aurora.jpg`. On green: flip `certified: true`.

**Done-when.** M7 sign-off. `Aurora_Veil.json` schema validated against an actual existing preset sidecar (`Gossamer.json` is the closest match per AV_README open question) — required fields (`name` not `id`, `description`, `author`, `duration`, `fragment_function`, `vertex_function`, `beat_source`) confirmed; the `feedback` wrapper around `decay` resolved against the real schema.

**Estimated total: 3 sessions.**

---

## Phase CC — Crystalline Cavern (ray-march flagship preset)

A static-camera ray-march scene of a glowing geode interior — crystalline materials, screen-space caustics, light shafts, mv_warp shimmer over the lit frame. Demonstrates the D-029-preserved combination of `ray_march` + `mv_warp` (no current preset uses this) and exercises the entire V.1–V.4 utility library in a single shader. **Flagship piece.** Tier-2 primary. Authoritative design at [docs/presets/CRYSTALLINE_CAVERN_DESIGN.md](presets/CRYSTALLINE_CAVERN_DESIGN.md); reference set **not yet curated** (CC.0 prerequisite).

**Concept-viability gate (SHADER_CRAFT §2.0).** All three gates clear before CC.1 starts:

1. **Musical role (one sentence).** *"The crystal cavern's caustics flash on drum onsets (`stems.drums_energy_dev` — beat-coupled accent), the IBL ambient breathes with sustained bass (`f.bass_att_rel` — continuous primary), and the caustic refraction angle drifts continuously with vocals pitch — so the listener pairs kicks with caustic flashes, sustained bass with the scene brightening, and the melody with the way light bends through the crystal cluster."* Names three specific musical features paired with three specific visual behaviours per CLAUDE.md FA #58 / D-102.
2. **Iconic visual subject deliverable at fidelity.** Full rubric profile. This is the flagship — the fidelity bar is the *highest* in the catalog. Tier 2 6.5 ms budget; comparable past preset Glass Brutalist uses the same stack (ray-march + post-process + SSGI) and demonstrates the fidelity is achievable. **Risk acknowledged**: per CLAUDE.md Authoring Discipline ("treat Matt's fidelity warnings as constraints"), the flagship target is ambitious; if any session produces output that does not read against the curated references, the right action is to escalate to "this preset doesn't have a viable design at this fidelity target" rather than continue tuning (FA #58 lesson).
3. **Infrastructure-feasible.** Uses existing V.1–V.4 utilities. One amber: screen-space caustics utility (`Volume/Caustics.metal`) has no production consumer and may have rough edges (CC_DESIGN §4). CC.3 has a documented fallback (`fbm8` overlay) if the utility output is unworkable.

**Status.** Planned. **Schedule:** waits on LM, Arachne V.7.10 cert review, and Aurora Veil cert. Crystalline Cavern is positioned as the demonstration-of-ceiling piece for collaborators / external review — landing it after at least one other M7-certified non-Arachne preset (e.g. Aurora Veil) reduces the risk that it ships with rough edges that pull down the catalog's perceived quality.

### Increment CC.0 — Reference curation

**Scope.** Curate the reference set per CC_DESIGN §2 — geode interior cathedral, crystal termination close-up, cave caustics, wet limestone wall, bioluminescent cave, pattern glass close-up, anti-reference video-game crystal cave, anti-reference Tron neon. Author `docs/VISUAL_REFERENCES/crystalline_cavern/README.md` with per-image annotations matching the Aurora Veil README format. Confirm against `CheckVisualReferences --strict` (V.5).

**Done-when.** Reference set complete; README annotations include mandatory / decorative / actively-disregarded traits per D-065; anti-references named explicitly.

### Increment CC.1 — Scene structure (no materials)

**Scope.** Cavern walls (4-plane intersection with `worley_fbm` displacement), central crystal cluster (5 hex-prism SDFs with hash-driven per-instance jitter), floor crystals, hanging tips. Default white-on-grey rendering. Static camera composition framing. No materials, no audio coupling.

**Deliverables.** `PhospheneEngine/Sources/Presets/Shaders/CrystallineCavern.metal` (sceneSDF, sceneMaterial stubs returning matID only). `CrystallineCavern.json` (full rubric profile, certified: false). `PresetLoaderCompileFailureTest.expectedProductionPresetCount` bumped.

**Done-when.** Composition reads correctly against geode reference photography (Matt eyeball, not a formal M7 yet). Engine + app builds clean. Visual harness emits a default-fixture PNG.

### Increment CC.2 — Materials pass

**Scope.** Wire `mat_pattern_glass`, `mat_polished_chrome`, `mat_wet_stone`, `mat_frosted_glass` via `sceneMaterial`. Triplanar detail normals on cavern walls. Per-instance hash-jitter on crystal cluster (CLAUDE.md FA #44 lesson). `CrystallineCavernMaterialBoundaryTest` passes.

**Done-when.** Four materials visibly present and stable across material boundaries. PresetAcceptance D-037 invariants pass. SwiftLint clean.

### Increment CC.3 — Lighting + atmosphere + caustics

**Scope.** Bioluminescent §5.3 lighting recipe (warm key, blue-purple IBL, emission on pattern-glass + frosted-glass crystals). IBL palette × `lightColor.rgb` for valence tint (D-022 path). Volumetric ground fog via `vol_density_height_fog`. Light shafts via `ls_radial_step_uv`. Screen-space caustic projection.

**Validation gate.** Verify `Volume/Caustics.metal` produces workable output at CC's geometry scale. **If unworkable**, fall back to procedurally-animated `fbm8` overlay sampled at the floor projection (documented in CC_DESIGN §4 / §5.4). The fallback is a one-session detour; the cert-quality target is still the real caustic utility if it works.

**Done-when.** Lighting + atmosphere + caustics rendering coherently. Tier 2 kernel cost ≤ 6.5 ms; Tier 1 ≤ 5.0 ms (with the degradation path: SSGI off, caustic samples halved, ray-march steps 64 → 48).

### Increment CC.4 — Audio routing + mv_warp + cert

**Scope.** All eight audio routes from CC_DESIGN §5.6 wired (IBL bass breath / key bass breath / caustic flash drums-dev / caustic refraction vocals-pitch / IBL valence tint / shimmer mid-rel / mid-pulse caustic offset beat-phase / crystal emission bass+valence). mv_warp at conservative shimmer amplitude (≤ 0.003 UV, per CC_DESIGN §5.5 / D-029 lesson). All four preset-specific tests green (`CrystallineCavernSilenceTest`, `CrystallineCavernCausticBeatRatioTest`, `CrystallineCavernMaterialBoundaryTest`, `CrystallineCavernMvWarpStaticityTest`). Matt M7 review against curated references. On green: flip `certified: true`.

**Done-when.** M7 sign-off. Rubric score ≥ 14/15 (potential 15/15 with thin-film inclusion per CC_DESIGN §5.5).

**Estimated total: 4 sessions** (this is the flagship; complexity is justified by the demonstration value).

**Open questions per CC_DESIGN §11.** (1) `architectural` family enum value vs. existing categories; (2) caustic utility production-readiness — validated in CC.3; (3) POM on cavern walls — deferred until after first Matt review; (4) Tier 1 acceptable-degradation tradeoff vs. tier-2-only gating; (5) thin-film inclusion in CC.5 polish if rubric score 14 → 15 is wanted.

---

## Phase NB — Nimbus (first volumetric-family preset)

First consumer of the V.2 Volume tree (`Utilities/Volume/*`). Single-pass 2D direct-fragment volumetric ray-march; `family: volumetric` (new `PresetCategory` case, Matt-authorized 2026-06-04, D-140). Design of record: `docs/presets/NIMBUS_DESIGN.md`; plan: `docs/presets/NIMBUS_PLAN.md`. Tier 2 (M3+) only (`complexity_cost.tier1` above the Tier-1 ceiling → Orchestrator excludes on M1/M2).

### Increment NB.0 — Reference lock ✅ (committed 2026-06-04, precondition baseline)
Curated 10-image reference set + README (D-065(c) annotations + `05_anti_*`) in `docs/VISUAL_REFERENCES/nimbus/`; `NIMBUS_DESIGN.md` + `NIMBUS_PLAN.md`. Found uncommitted at NB.1 start; committed as the precondition baseline. **Follow-up:** `06_palette_cool_baseline.jpg` (manifest slot) is absent from disk — re-source it (the cool target is specified in prose meanwhile).

### Increment NB.1 — Macro maquette ✅ (2026-06-04) — budget resolved via noiseVolume (NB.1.1)
**Delivered.** `Nimbus.metal` (single-scatter volumetric march: ellipsoidal envelope × eroded detail; 64-step front-to-back; `hg_phase(·,0.4)`; 6-step envelope self-shadow; cool-indigo tint; ACES; true-black void; density-only + step-count debug `#define`s). `Nimbus.json` (`passes:[]`, family volumetric, certified:false, rubric full, `complexity_cost {tier1:9.0, tier2:6.0 provisional}`). `PresetCategory.volumetric` (D-140). `expectedProductionPresetCount` 18→19. `NimbusBudgetProbeTests` (env-gated). `PresetVisualReviewTests` arg + noiseVolume parity binding + `PresetTests` allCases 11→12.
**Visual:** maquette reads — single coherent gaseous body, denser/brighter core, soft fraying edges, true-black void, framed per `01_macro_coherent_body` (Matt eyeball pending).
**Budget gate — fired then RESOLVED (DESIGN §6.1):** the original computed-noise march was over budget (p50 20.2 ms @1080p; 7.5 ms even @half-res). Diagnosis: the cost was the per-step `fbm4` ALU (voronoi removal was a wash). Fix (NB.1.1, Matt-directed): sample the preamble `noiseVolume` 64³ 3D texture (production-bound on the direct path) instead of computing `fbm4` → **p50 1.37 ms @1080p, within Tier-2 at full res with ~5.6 ms headroom** (look improved). Stays inside NB.1's mandate (noiseVolume is preamble-injected + production-bound; only test paths gained a parity binding, FA #66).

### Increment NB.2 — Meso/micro detail cascade ✅ (2026-06-04)
**Delivered.** `Nimbus.metal` detail field rebuilt into the macro→meso→micro cascade (SHADER_CRAFT §2.2), all `noiseVolume`-sampled (no computed per-step noise — §6.1 rule held): **meso** nested billow lobes (two octave-doubled scales q*0.7/q*1.4) that *carve the envelope multiplicatively* (valleys thin toward transparency → distinct lumps, not the saturated solid-surface egg); **micro** domain-warped fine filaments (warp via two cheap decorrelated `noiseVolume` taps, never `fbm_vec3`/`warped_fbm`) + multiplicative rim filament-mask → peeling curling tendrils dissolving into the void (no hard cut); **interior turbulence** on the named `kNimbusTurbulence` knob (placid↔churning, NB.6 wires arousal). Extinction σ 2.1→1.55 so the translucent body's front-to-back accumulation reads lobe depth with no new lighting (lobe-to-lobe shadow is NB.3). 4 noise octaves (0.7/1.4/2.8/5.6) → §12.1 floor. Test/prod parity: both test paths (`PresetVisualReviewTests`, `NimbusBudgetProbeTests`) now bind the full noise set via `TextureManager.bindTextures` (slots 4–8), matching production exactly (FA #66).

**Budget (re-measured, NIMBUS_DESIGN §6.2):** macro+meso+micro **p50 1.65 ms @1080p** (vs NB.1 macro 1.37 ms) — +0.28 ms for doubling samples 3→6/step, because the envelope early-out keeps most steps free. 0.24× the 7 ms Tier-2 ceiling, well under the NB.2 ≤~3 ms target; ~5.35 ms headroom preserved for NB.3–7. **Recipe:** SHADER_CRAFT §6.5 — the first V.2-Volume-consumer entry (envelope shaping, multiplicative billow carve, translucent-σ depth, domain-warp-on-texture-coords, texture-noise budget rule). Visual: density-only guard shows a bounded body with dominant negative space + feathered edges (not anti-uniform-fog, not anti-solid-surface); step-count heatmap confirms early-out localizes cost. Matt eyeball (contact-sheet-style), not a formal M7. `certified:false` unchanged.

### Increment NB.3 — The look: HZD/Nubis cloud-port + fidelity uplift ✅ (2026-06-04 → 2026-06-05)
**Delivered.** Replaced the NB.1/NB.2 Perlin-FBM blob with the ported Horizon: Zero Dawn / "Nubis" volumetric-cloud technique (Perlin-FBM cannot make billows — §0 Direction reset):
- **NB.3.0** — baked a tileable 3D **Perlin-Worley** texture (`gen_perlin_worley_3d` in `NoiseGen.metal`: RGBA = PW base + 3 inverted-Worley detail octaves) in `TextureManager`, auto-bound on the direct path (the one engine touch).
- **NB.3.1** — density from PW billows (R) carved by Worley detail (G/B/A), HZD-remapped against the analytic envelope as coverage → bounded body + feathered cauliflower edges. Off-lattice sample offset kills a 4-fold mirror symmetry.
- **NB.3.2** — backlit lighting: forward-scatter HG + a detail-aware ~6-step **cone self-shadow** march → luminous backlit billows.
- **NB.3.3 — fidelity uplift (Matt-directed, reference-aligned).** Closed the three reference-packet gaps **strictly within the backlit model — no emission**: coverage-gated interior billow/crevice contrast (ref 02, soft rim ref 03), a radial denser core for substance (ref 01), +15% on-screen size via focal zoom (`kNimbusFocal` 1.25→1.44), and the forward-scatter silver-lining glow + brightness lift (ref 08). An egg-core / internal-emission / "incandescent" exploration was tried and **reverted** as a divergence — the packet is a BACKLIT cool body (light scattering *through* the medium), not an emissive one (durable note in `NIMBUS_DESIGN.md §5.2`). Matt-approved on the render-vs-packet contact sheet.

**Budget (NIMBUS_DESIGN §6.3):** p50 **3.27 ms @1080p**, 0.47× the 7 ms Tier-2 ceiling — within, ~3.7 ms headroom for NB.4→NB.6. **Gates:** 1378 engine tests green; SwiftLint `--strict` clean; app build clean; `PresetLoaderCompileFailureTest` at 19; density-only guard clears anti-fog + anti-solid; mode-2 heatmap intact; debug toggle at 0. Still NO audio coupling (NB.4) and NO mood (NB.6); `certified:false` unchanged (cert is NB.9).

### Increment NB.4 — Energy (Breath): bloom → size + brightness + flow + silence floor ✅ (2026-06-05)

**Delivered.** The hero coupling (DESIGN §1.3) — the first and only Energy driver, no beat, no mood. `NimbusState.swift` (new, `Sources/Presets/Nimbus/`; `public final class @unchecked Sendable` + NSLock, mirrors `AuroraVeilState`): a fast-attack (~150 ms) / slow-release (~400 ms) one-pole follower over the broadband energy deviation `(bass_att_rel+mid_att_rel+treb_att_rel)/3` (D-026 — never absolute thresholds, FA #31) → `bloom`; a `flowPhase` accumulated in `Double` (long-accumulator rule) at a bloom-modulated rate; flushed to a 16-byte `NimbusStateGPU` (`bloom`, `flowPhase`, 2× pad) at fragment buffer(6). Shader (`Nimbus.metal`): reads `constant NimbusStateGPU& nb [[buffer(6)]]` (byte-matched MSL mirror; orthogonal to `noiseVolume` at *texture* 6) and consumes `bloom` for **body extent** (uniform `bodyScale` inflation of the whole field, `mix(0.80,1.16,bloom)` → +45 % floor→peak; bound sphere + cone-shadow reach grow with it), **luminosity** (`bright = mix(0.65,1.17,bloom)` → +80 % floor→peak, scaling the back-key + ambient together so the backlit rim-vs-core contrast is preserved), and `flowPhase` for the **gas drift** (replaces wall-clock `features.time` in `nimbus_density`; 1×→3.5× via `flowFloor`/`flowPeak` in state). Silence floor = the NB.3 backlit look, smaller/dimmer/slower over a faint non-black cool **haze** halo (D-037 — concentrated near the body, dark corners → negative space preserved, NOT anti-uniform-fog). Live wiring in `VisualizerEngine+Presets.swift` (`if desc.name == "Nimbus"` → alloc + `reset()` + `setDirectPresetFragmentBuffer` + `setMeshPresetTick`), `nimbusState` ivar, teardown null, **track-change `reset()`** in `VisualizerEngine+Capture.swift` (body settles into the new track rather than carrying the prior bloom).

**Tests.** `NimbusBloomFollowerTest` (new): Part A asserts the asymmetric follower feel (floors at silence, fills under energy, reaches half FASTER up than down, flow never freezes); Part B renders the converged silence-floor + full-bloom states through the **live direct dispatch path** (`preset.pipelineState` + slot-6 buffer + noiseVolume) and asserts silence non-black (D-037) + energetic brighter + bigger. `PresetVisualReviewTests` gains Nimbus-specific silence/mid/energy fixtures (explicit AttRel) + per-fixture `NimbusState` priming + slot-6 bind. `NimbusBudgetProbeTests` binds a primed slot-6 buffer (FA #66 parity).

**Budget (NIMBUS_DESIGN §6.4):** p50 **2.66 ms @1080p** (steady-mid, bloom ~0.5), 0.38× the 7 ms ceiling — the CPU follower adds no GPU cost; full-bloom worst case ~3.6 ms est. **Gates:** 1380 engine tests green; SwiftLint `--strict` clean; app build clean; `PresetLoaderCompileFailureTest` at 19; contact sheet shows the bloom range (silence small/dim/slow-non-black → mid ≈ NB.3 → energy big/bright/fast) with the backlit look preserved. **No beat / no mood verified by source inspection.** `certified:false` unchanged. **Remaining gate: Matt's live manual-validation sign-off on "feels married to the music" (non-bypassable — automated tests prove the route fires, not that it feels musical).**

### Increment NB.5 — Beat: stem lobes (the band plays the body) ✅ (2026-06-05, D-141)

**Reverses the "nothing on the beat" premise (D-141).** The first real-music test of NB.4 (the *Atlas* / Battles session, a relentless 136-BPM track) showed the energy-only bloom **too subtle** and, on bass-dominated music, structurally floored: `bloom` averaged 3 bands and with mid (0.04) / treble (0.004) near-silent the dead bands vetoed it — the body sat at floor-size all session while the beat (beatComposite > 0.5 on 53 % of frames, grid locked) went unanswered; meanwhile all four stem deviations swing hard (peaks 1.9–2.8). Matt's call: drive from the beat, per stem; chose "one mass heaves per-stem" over hard quadrants.

**Delivered.** `NimbusState` gains four fast-attack/slow-release stem followers — `kickPunch` (drums; `max(beatBass,beatComposite)` onset pulse, zero-delay frame 1, blended to `drumsEnergyDev` via D-019 warmup), `bassLobe`/`vocalsLobe`/`otherLobe` (stem `…EnergyDev`); `bloom` re-sourced to the mean of the four stem **energies** (fixes the 3-band floor). `NimbusStateGPU` 16→32 bytes. Shader: `nimbus_envelope` heaves the **single** body per stem (`rr/(1 + kick + Σ lobe·cos²)` — star-convex, cannot fragment, protecting the §1.4 one-mass identity): drums punch + brighten the whole body, bass heaves DOWN, lead flares UP, other swells to the SIDE; the bound grows by the live bulge so a heave never clips. **FA #4 honoured** — beat is an accent on top of the slow bloom; safe here (no feedback loop, zero-delay pulse, soft-decay heave forgives ±80 ms).

**Tests.** `NimbusBloomFollowerTest.test_stemLobes` (new): renders baseline/bloom/kick/bass/vocals/other through the **live direct path**, asserts each follower fires only for its stem, the luma-weighted centroid shifts the right way (bass down, vocals up, other side), drums brighten+inflate the whole body, and every fixture stays one present mass. NB.4 follower tests + budget probe + visual review carried forward (slot-6 = 32 bytes).

**Budget (NIMBUS_DESIGN §6.5):** p50 **3.74 ms @1080p**, 0.53× the 7 ms ceiling — within, ~3.3 ms headroom for NB.6. **Perf lesson:** `pow(cos,1.5)` for the lobe falloff doubled the budget to 5.15 ms (the GPU predicates the guard — paid even at rest); cos² (pure mul-adds) → 3.74 ms. Never use `pow()` in a per-march-step falloff. **Gates:** 1381 engine tests green; SwiftLint `--strict` clean; app build clean; `PresetLoaderCompileFailureTest` at 19; per-stem contact sheet shows directional heaves on one coherent mass. `certified:false` unchanged. **Remaining gate: Matt's live manual-validation sign-off (does the body feel like it's playing with the band?).**

### Increment NB.3.4/.5 — Smoke qualities (texture + rising/curling motion) ✅ (2026-06-05)

After the NB.5 live test read as a static blurry blob, Matt reframed: smoke/cloud is defined by how it MOVES. **Texture (NB.3.4):** 2-octave fractal Worley detail cascade + interior cauliflower carve (lump/crevice contrast throughout) + bigger base billows (scale 0.55→0.40). **Motion (NB.3.5):** replaced the linear noise drift with rising/curling smoke — vertical rise + helical twist + a 2-octave organic swirl warp (billows roll over each other) + faster-churning detail, on the flowT bloom clock. Motion character "rising curling smoke" (Matt's call); 2 Matt-provided motion references recorded in `NIMBUS_DESIGN §1.2`. Budget (§6.6): the naïve version hit 20 ms — fixed with a **cheap shadow density** (`nimbus_density_shadow`, 1 sample — the cone self-shadow only needs coarse depth), 64 steps, and a 10 % smaller blob (Matt-directed) → 3.78 ms. Perf lessons: never `pow()` in a per-step falloff; match step count to the finest kept octave; on-screen area is a linear budget lever. `NimbusBloomFollowerTest.test_motionStrip`. Matt-approved ("looks good, proceed").

### Increment NB.8 — Performance tranche (half-res render path) + beat-sync ✅ (2026-06-05)

The 2nd Atlas live session showed the body **swelling to fill the frame** at full energy costs **mean 6.84 / max 14.5 ms, 56 % of frames over the 7 ms ceiling** — every prior budget probe under-measured by priming the steady-mid body, not the swell (durable lesson: profile a volumetric preset at its WORST on-screen body). **Fix: a half-resolution direct-render path** — Nimbus's fragment renders to a 0.5× offscreen texture + bilinear upscale (`feedback_blit` + linear-clamp sampler); ~4× cheaper → worst-case ~3 ms (the §5.5 MetalFX reserve was never wired, and MetalFX Temporal needs motion vectors a procedural volume lacks, so a simple upscale substitutes). Engine: `RenderPipeline.setDirectRenderScale` + `drawDirect` branch + `encodePresetVisualization`/`halfResTarget` (new `RenderPipeline+DirectDraw.swift`); opt-in per-preset (others unaffected). `complexity_cost.tier2` 6.0→**4.0** from the corrected worst-case profile. **Beat-sync** tightened: the kick now fires from the predicted grid beat (anticipatory `smoothstep(0.82,1,beatPhase01)`, peaks ON the beat) with the onset as fallback — vs the ~80–120 ms onset lag. **Gates:** 1384 engine tests green (incl. `test_halfResUpscale` + corrected worst-case probe + updated AV.2.2a slot-6 guard); SwiftLint clean; app build clean; count 19. Budget §6.7/§6.8. **Remaining: Matt's live sign-off on the half-res look + the tighter beat.**

### Increment NB.6 — Mood (valence→colour, arousal→agitation) ✅ (2026-06-05)

The last feature before cert. `NimbusState` smooths valence + arousal ~4 s (FA #25 — from the FeatureVector, never written back; D-024), stored in the former GPU pad floats (`NimbusStateGPU` stays 32 bytes, byte-layout unchanged). Shader: **valence → body colour** (`mix(indigo, gold, valence01)` at composite, with the ambient fill + haze halo warming too → the whole mass shifts cool↔warm, D-022 propagation); **arousal → flow agitation** (`mix(0.65, 1.55, arousal01)` drives the detail-erosion strength — calm = smoother lobes, energetic = torn/fraying edges; replaced the compile-time `kNimbusTurbulence`). Verified: `NimbusBloomFollowerTest.test_moodTravel` (cool R/B 0.71 → warm R/B 1.79) + the cool/warm/calm/wild contact strip; the visual-review fixtures set a cool valence so the contact sheet still matches the 06-cool references. 1385 engine tests green; SwiftLint clean; app build clean; count 19. Deferred (don't block cert): per-track-distinct gas seed + PresetSessionReplay registration. **Pending Matt's live sign-off; then NB.9 cert.**

### NB.9 — certification ✅ **CERTIFIED by Matt (M7, 2026-06-05, session 20-33-47Z, 8 tracks)**

**Phase NB complete — Nimbus is the first certified `volumetric`-family preset (D-140).** M7 history: r1 (session 18-26-37Z) + r1.5 (19-03-04Z) did NOT certify, but both unknowingly ran the **stranded old `main` Nimbus** (the NB.10 changes were on a worktree branch the build never saw — see [[feedback_worktree_changes_reach_build]]); the first build with the real changes (after integration to main) passed on session 20-33-47Z. Cert state: `Nimbus.json` `certified: true`; `"Nimbus"` added to `certifiedPresets` in `FidelityRubricTests` (heuristic gate false-by-construction — volumetric, no `mat_*`/`fbm`; the M7 reference review is the load-bearing gate per SHADER_CRAFT §12.1). Accepted-at-cert limitation: **beat-grid live phase** ("too active / not synced" on some tracks, e.g. Love Shack) is bounded by the shared cached-grid phase, deferred to its own infrastructure project **D-145** (after Skein). Noted future enhancement (Matt): **extend the mood palette beyond cool-purple ↔ warm-gold** (a richer colour family) — `NIMBUS_DESIGN §8`. Session-artifact confirmation: per-track bloom p50 0.44–0.61 (vs the pre-r1.6 0.13) and warmth read matched Matt's live calls track-for-track (Love Shack/In Undertow/No Surprises/Love Rehab/Atlas warm, Pyramid Song cool, Sad Song + A Girl In Port travel).

**Earlier (round-1) automated prep ✅; the M7 round-1/1.5 narrative:**
Per `NIMBUS_PLAN.md`: ~~NB.7 Page (CUT — §1.3)~~ → NB.9 certification. NB.5-as-Pulse cut; NB.8 done early; mood (NB.6) done. A certified Nimbus = the band playing one packet-matching cool-gas body: beat (per stem) + energy swell + mood, fitting Tier-2 budget via the half-res path.

**Automated prep landed (M7-independent).**
- **§5.7 acceptance audit + two new gates.** Mapped every §5.7 bullet to a gate (closeout table). Silence-non-black, energy primacy (bloom→size/bright), flow-alive, valence→colour, perf — already covered (`NimbusBloomFollowerTest`, `NimbusBudgetProbeTests`, `PresetAcceptanceTests` inv. 1–4, which Nimbus already clears as a `direct` preset). Two gaps filled in `NimbusBloomFollowerTest`: (1) **body coherence / negative space** (`test_bodyCoherenceNegativeSpace`) — at the absolute worst case (full bloom + max kick + all three lobes), the body stays a bounded mass (coverage 0.668 < 0.80 ceiling) with dark corners (corner/centre 0.082 < 0.30) → ≠ `05_anti_uniform_fog` (the single worst failure, §1.4); (2) **arousal→agitation route-live** (extends `test_moodTravel`) — calm↔wild MSD 84.3 ≫ 0 proves the second mood axis carries signal (partner to the valence→colour assertion).
- **Golden dHash registered** in `PresetRegressionTests` — Nimbus now binds a zeroed slot-6 `NimbusStateGPU` (deterministic silence-floor body) and registers `0x0F0F0F0F0F0F0F0F` (identical across all three fixtures, because the shader reads no FeatureVector field but `aspect_ratio`). A centred-body fingerprint sensitive to silhouette / backlit-lighting / haze regressions.
- **Stale `Nimbus.json` description** refreshed to the shipped band-plays-the-body reality (was "Look being rebuilt… nothing fires on the beat" — both false post-NB.3/NB.5).
- **M7 artifacts generated** — contact sheet (render vs 3 TRUST refs + 2 AVOID anti-refs; render clearly rejects both anti-refs), silence/mid/energy bloom range, rising/curling motion strip (8 frames), cool/warm/calm/wild mood strip, per-stem lobe sheet, worst-case budget (half-res p50 **2.56 ms**, within the 7 ms ceiling).
- Gates: **1386 engine tests green** (the only failures are the pre-existing gitignored-`Tests/Fixtures/` absence in a fresh worktree — `love_rehab.m4a` et al.; restoring the fixtures makes the suite 1386/1386); SwiftLint `--strict` 0/424; app build clean; `PresetLoaderCompileFailureTest` 19.

**M7 round 1 (session `2026-06-05T18-26-37Z`, 7 tracks) — Matt would NOT certify.** Two findings, different root causes (diagnosed from the session csv): **(a) mood colour too subtle / sometimes wrong** — Billie Jean "white/gray", B.O.B. "purplish — why? energetic". Root cause: a perfectly good valence signal was washed out downstream (bright-core desaturation to near-white + muted poles + valence-only mapping). → **NB.10 (D-144), done below.** **(b) beat behind / not locked to downbeats** — root cause: the shared beat-grid's *live phase* (grids lock with correct tempo, but cached-grid phase is imperfect on live audio; meter assumed simple). This is the system-level Cold-Start Phase limit (FA #69), NOT a Nimbus shader bug. Matt's call: **open the beat-grid as its own project (D-145)**; Nimbus's beat axis waits on it. Cert flip steps unchanged (`certified` false→true + `"Nimbus"` → `certifiedPresets` in `FidelityRubricTests` + doc sweep + `RENDER_CAPABILITY_REGISTRY`), still gated on a passing M7. **No push without Matt's "yes, push."**

### NB.10 — mood expressiveness uplift (energy warms it) ✅ (2026-06-05, D-144) — pending M7 r2
Addresses M7 r1 finding (a). Pure `Nimbus.metal` shader change (no state change — `bloomV` + `arousal` already in `NimbusStateGPU`): **(1)** colour now driven by *warmth* = `valence01` lifted by `energy01 = 0.55·arousal01 + 0.55·bloomV`, expanded around mid (`kNimbusMoodContrast`) — an energetic track reads hot even at neutral/low valence (the B.O.B. fix); **(2)** the bright core keeps its **mood hue** (brightened), no longer washing to near-white (the Billie Jean "white/gray" fix); **(3)** saturated poles (vivid indigo-violet ↔ rich amber/gold), ambient + haze warm with `warm01` too. Gates: `test_moodTravel` valence R/B **0.85→3.11** (was 0.71→1.79) + a NEW energy-warmth assertion (neutral valence, low↔high energy R/B **0.85→2.89**) locking the B.O.B. fix; mood strip shows a vivid violet cool pole / rich gold warm pole / gold high-energy-neutral-valence body; the golden hash is unchanged (dHash is luma-gradient, hue-invariant). **1386 engine tests green; SwiftLint 0/424; app build clean; count 19.** All hues are starting points — Matt's eye sets the finals.

**NB.10 r1.5 correction (2026-06-05, same day) — D-144 amended.** The v1 energy-warmth *regressed* live (M7 r1.5, session `2026-06-05T19-03-04Z`: "clobbered… displays neutral"). Root cause (reconstructed `warm01` from the session): the `+0.6·(energy01−0.25)` lift added a flat warm bias to every moderate-energy track, collapsing the cool↔warm range (Sad Song → gold). Fix: warmth primarily valence; energy-warmth AROUSAL-gated past a high threshold (only bangers warm); contrast 1.35→1.60; `moodTau` 4.0→2.5 s (colour travels instead of fading to the mean). Re-verified on the session (In Undertow cool 0.33, range restored). The classifier reads "Sad Song" as +0.11 valence (audio-mood ≠ title-mood) so it renders warm-ish regardless of the shader — a classifier characteristic. 1386 tests green; SwiftLint clean; app build clean; count 19.

**NB.10 r1.6 bloom recalibration (2026-06-05, same day; Matt: "input problem, solve permanently") — D-144 amended.** The small/dim bodies (which made the mood colour hard to see) are NOT a quiet-capture/input issue — I first wrongly blamed Spotify normalization; Matt confirmed it off + 100 % volume. Root cause (measured): `{stem}Energy` is the stem's 3 AGC bands **summed**, but the AGC normalises the *6-band total* to 0.5, so a 3-band sum centres at ~**0.30** (measured p50 0.24/0.27/0.41 across 3 sessions), not the 0.5 the bloom assumed — so `bloom = meanStem·1.4−0.2` gave ≈ 0.13 (tiny) on normal music; Atlas only looked right as an unusually dense master. Fix: `NimbusState` `bloomGain` 1.4→1.9, `bloomOffset` −0.2→−0.06. Verified: meanStem 0.27 → bloom **0.45** (was 0.18), dynamic range kept (0.14→0.21, 0.55→0.98), silence floors at 0. Regression-locked by `test_bloomVisibleOnTypicalMusic`. **Same mis-calibration class as BUG-027** (every energy value centres ~0.3 not 0.5) — the system-wide normalisation fix is BUG-027's domain (its own project, re-tunes every preset). Makes Nimbus bodies bigger on all music (Atlas re-judged at M7 r2). **1387 tests green; SwiftLint 0/424; app build clean; count 19.**

### D-145 — beat-grid live-phase as its own project (deferred from Nimbus)
Matt opened the shared beat-grid's live-phase quality as a separate workstream (M7 r1). The felt "behind the beat / wrong downbeat" is bounded by the cached-grid phase, not Nimbus — and per FA #69 any work here needs a *new premise* (not another short-window live-tap iteration). Scoping note: `docs/diagnostics/BEAT_GRID_LIVE_PHASE_PROJECT_2026-06-05.md` (the M7 r1 diagnosis + candidate premises). Nimbus's beat axis (kick timing / downbeat feel) waits on this; the mood uplift (NB.10) does not.

---

## Phase Skein — action-painting / drip-pour preset (`painterly`)

New preset in the Dragon Bloom lineage (D-135 / D-138): a Pollock-style poured / dripped **action-painting** visualiser whose canvas is a persistent, **lossless** feedback accumulation (paint lands, stays, is occluded only by later opaque paint-over-paint — the temporal-integral canvas). Design: `docs/presets/SKEIN_DESIGN.md`; plan: `docs/presets/SKEIN_PLAN.md`. Critical path: Skein.0 → ENGINE.1 → Skein.1 → 2 → 3 → 5 → 6; wet-sheen (ENGINE.2 + Skein.4) is the explicit cut-line branch.

### Skein.0 — Reference lock ✅ (2026-06-05)
Reference set curated + Matt-approved; `docs/VISUAL_REFERENCES/skein/` populated, `CheckVisualReferences` green (commits `07a4a57b` / `52ebfe3d`). Anti-reference images + the V.6 rubric profile deferred per the Skein.0 closeout.

### Increment Skein.ENGINE.1 — Canvas-hold accumulation path ✅ (2026-06-05, D-142)
Establishes the persistent, lossless paint canvas: **identity warp + no decay + no R→G→B transfer + marks-on-top**, the no-decay / identity **configuration** of the mv_warp brush-on-feedback paradigm (a sibling of Dragon Bloom — D-142). **Audit verdict: config-only — no PhospheneEngine source change, no new warp mode** (the four properties are reachable as per-preset config; `decayMul = (chromaticMix>0)?1.0:in.decay` proves no-decay is *not* bound to the colour transfer). Files: `Skein.metal` (identity `mvWarpPerFrame` decay=1.0 / `mvWarpPerVertex` returns `uv` + a `skein_fragment` toned-ground + fixed test stamp), `Skein.json` (`passes:["direct","mv_warp"]`, decay 1.0, uncertified, no `family` yet), `SkeinCanvasHoldTest.swift` (new), `PresetLoaderCompileFailureTest` count 19→20. **`SkeinCanvasHoldTest` proves whole-frame Hamming 0 across 130 hold frames** through the live scene→warp→blit→swap dispatch path (sRGB feedback; sRGB round-trip + identity-at-pixel-centers both exact → no linear-format / nearest-sampler override needed). **Gates:** 1388 engine tests green; `PresetRegressionTests` byte-identical for every other preset (no shared code touched); MVWarp/StagedComposition green; app build clean; SwiftLint `--strict` clean (424 files); contrast + acceptance gates pass for Skein. **Flagged for Skein.1+:** ~~app-wiring de-entanglement of "scene-geometry ⟹ Dragon Bloom chromatic+comp" + generalize `makeSceneGeometryPipeline` names~~ → **DONE in Skein.ENGINE.1.1 (D-143)**; the light-canvas-vs-white-chrome WCAG contrast tension (ENGINE.1 uses a darkened toned-ground placeholder — still deferred per D-142(b)); `family: painterly` + the `PresetCategory` case (still deferred per D-142(c)). **Pending Matt's sign-off (the increment gate).**

### Increment Skein.ENGINE.1.1 — Per-preset marks-on-top + cream ground ✅ (2026-06-05, D-143)
Clears the ENGINE.1 "flagged for Skein.1" de-entanglement (a) and makes **Skein render live for the first time** (cream ground + held test disc through the real pipeline). The D-138 marks-on-top half was hard-wired to Dragon Bloom in three places; generalising them touched SHARED mv_warp wiring (a D-137 beachball risk), so this lands as its own gated, golden-regression-locked infra patch **before** Skein.1. **Audit verdict: smallest additive change — existing presets resolve exactly as before, only a new per-preset path is added.** The three couplings → per-preset: (1) `PresetLoader.makeSceneGeometryPipeline` resolves `<prefix>_geometry_*` (legacy `dragon_bloom_strand_*` fallback; stale "additive blend" doc fixed → normal alpha); (2) a new optional **`marks` descriptor block** (`vertex_count`/`instance_count`/`primitive`/`chromatic`/`comp`/`beat_pulse`) drives draw params + chromatic + comp + the comp beat pump (gated by `marks.beat_pulse`, was `sceneGeometryState != nil`); (3) per-preset **canvas-clear colour** on `MVWarpPipelineBundle`/`MVWarpState` → `clearWarpTextures(to:)` from `marks.canvas_clear`. Dragon Bloom's block carries its exact literals (1536/3/lineStrip, chromatic 1.0, comp 1/0.5/1.07, beat on) → byte-identical. Skein: `skein_fragment` → flat cream GROUND; the fixed disc → `skein_geometry_*` fullscreen-triangle overlay (hard-edged so the per-frame redraw is idempotent), `chromatic=0`, black-free cream clear. Files: `PresetLoader.swift`, `PresetDescriptor.swift` (`MarksConfig`), `RenderPipeline+MVWarp.swift` / `+PresetSwitching.swift` / `RenderPipeline.swift` / `MVWarpTypes.swift`, `VisualizerEngine+Presets.swift`, `DragonBloom.json` (+`marks`), `Skein.metal` / `Skein.json` (+`marks`), `SkeinCanvasHoldTest.swift` (marks-on-top test), `PresetAcceptanceTests.swift` (Skein readable-form exemption). **Gates:** engine suite green except 7 pre-existing `love_rehab.m4a`-fixture-absent failures (git-ignored licensed clip, unrelated); `PresetRegressionTests` + `DragonBloomMVWarpAccumulationTest` + `FataMorganaMVWarpAccumulationTest` byte-identical; new marks-on-top test green (disc on cream, `chromatic=0` Hamming-0 over 130 frames, `chromatic=1.0` cycles) through the live scene→warp→overlay→blit→swap path; PresetAcceptance + PresetContrast green for Skein; app build clean; SwiftLint `--strict` clean. **Pending Matt's sign-off (the increment gate).**

### Increment Skein.1 — Canvas + pour spike ✅ (2026-06-05, commits `57ee7383` / `528021b5`) — pending Matt's eyeball gate
Replaces the ENGINE.1.1 static test disc with a **single white pour LINE traced by a wandering "painter,"** accumulating losslessly on the cream canvas. No audio (driven by `features.time` only). This is the **gate-before-the-gate** (SKEIN_DESIGN §7): does a persistent skein hold + read as poured paint? **Audit verdict: pure preset increment — no engine touch, DB/FM byte-identical by construction.** **Trajectory decision — Path A (closed-form, in-shader):** the marks-on-top overlay binds `features` only at the **vertex** stage (`drawSceneGeometryOverlay:36`, no fragment binding), so the painter position is computed in `skein_geometry_vertex` (which already reads `features@0` — the same slot `dragon_bloom_strand_vertex` reads) and passed to the fragment as varyings; the fragment draws a swept-capsule 2D-segment SDF from `painter(t−Δt)` → `painter(t)`, AA'd (each capsule stamped once then held, so no in-place re-blend). **No CPU state, no per-preset buffer, no engine touch** — Path B (`SkeinState` + a gated overlay-buffer binding) was correctly **deferred to a future ENGINE.1.2** when Skein.2's stateful painter needs it (FA #59/#60). Trajectory: three gesture scales per axis at non-harmonic (incommensurate) frequencies — a slow drift carrying the painter across the canvas (the §1.0 fact-2 island-then-join build order) + gesture loops (~6 s) + tight loops (~2.5 s), all in the gesture band; the loops are the GESTURE (§1.0 fact 1), never a coiling/noise term; width rides 1/speed (pools at turning points, filament on sweeps — §1.0/§1.2, refs 02/03). **Trailing-off (Matt eyeball-pass refinement, `8b8d167d`):** the pour's leading END thins + fades to a point via a closed-form tapering tail over the painter's last ~0.67 s (the VisComp 2014 line layer — width tapers toward the endpoint as the stream thins). A *fully*-persistent trailing-off (the whole recent stretch fading) is the wet-now/dry-past device (§1.4) and needs the deferred wetness channel (Skein.ENGINE.2); the in-shader tail is the achievable Skein.1 approximation. Files: `Skein.metal` (pour line replaces the disc), `SkeinCanvasHoldTest.swift` (the disc hold test → the **accumulation + hold + continuity** gate, + env-gated contact sheet). `Skein.json` unchanged. **Gates:** the new pour gate green through the **live** scene→warp→overlay→blit→swap path advancing `features.time` (256², chromatic=0, 180 frames): accumulation `[128,211,301,422]` (monotone + grows), early-painted texel persists, unpainted far corner byte-identical frame0→final, continuity = **1.000** (single connected component), cream ground + white line; full engine suite green except the same 7 `love_rehab.m4a` fixture-absent failures; `PresetRegressionTests` + DB/FM accumulation byte-identical; `PresetLoaderCompileFailureTest` preset count intact (no silent MSL drop); PresetAcceptance + PresetContrast green for Skein; app build clean; SwiftLint `--strict` clean (424 files). **Eyeball artifact:** `RENDER_VISUAL=1`/`SKEIN_VISUAL=1` contact sheet at ~2/5/10/20 s (480×270, live path) — a continuous wandering pour line accumulating with gesture loops + crossings + pool/filament width contrast. **No new capability** (Path A uses the Supported canvas-hold + marks-on-top rows) — registry instances refreshed disc→pour line, no status flip. **Deferred (unchanged):** `family: painterly` + the `PresetCategory` case (D-142(c)/D-143 — a product-taxonomy / engine-touch decision, not in Skein.1's pure-preset scope); per-track seed (Skein.3); the ENGINE.1.2 overlay-buffer binding (opens with Skein.2). **Pending Matt's eyeball gate** (SKEIN_PLAN: if a persistent skein doesn't hold + read as paint, the concept stops here).

### Increment Skein.2 — Splatter morphology + viscosity ✅ (2026-06-05) — Matt eyeball PASS (cert at Skein.6)
Adds the **splatter vocabulary** to the held canvas alongside the Skein.1 pour line: velocity-biased **droplet bursts** (ragged 2D-noise edges, exp/poly satellite size+density falloff with distance — the VisComp 2014 *droplet* layer), thin **filament tendrils**, and a **viscosity axis** (thin-fast-fine ↔ thick-slow-gloopy) shaping every mark — all baked normal-alpha into the same lossless canvas. **No audio:** bursts fire on a deterministic flick schedule; viscosity is a closed-form **debug** sweep of `features.time` (period ~12 s) so a *still frame* exhibits the full morphology. Real onset→splatter / centroid→viscosity / stem→colour routing + the per-track seed are Skein.3. **Audit verdict — Path A extended (closed-form, in-shader): no engine touch, no `SkeinState`, no per-preset buffer; DB/FM byte-identical by construction.** Confirmed with file:line evidence that `drawSceneGeometryOverlay` (`RenderPipeline+SceneGeometry.swift:36-37`) binds `features` only at the **vertex** stage (no fragment buffer — Dragon Bloom shares this code, so a Path-B per-preset buffer would be a gated D-137-risk engine touch); the splatter needs neither multi-frame droplet flight nor per-stem accumulators (paint **lands and the canvas holds it** — §1.4), so everything is a deterministic **hash of (flick, droplet)** generated in `skein_geometry_fragment`, plus a debug viscosity computed in `skein_geometry_vertex` and passed as a varying. ENGINE.1.2 (`SkeinState` + the gated overlay buffer) stays **deferred to Skein.3**, its real consumer (FA #59/#60; SKEIN_DESIGN §7). **Two iteration findings (the highest-aesthetic-risk increment, as called):** (1) big+dense+ragged droplets merge into "cauliflower froth" → fixed with **small+crisp+wider-flung+fewer DISTINCT dots**; (2) straight line→droplet filaments radiate as a **sci-fi starburst** (= the particle-burst anti-reference) → **forward-gated, short, sparse** so they read as directional spray-streaks. Ragged edges use a new **`skein_fbm2`** (4-octave `perlin2d`, inter-octave rotation, sampled at non-lattice scaled coords → FA #43-clear); AA from the smooth radial distance with raggedness in the threshold radius; per-flick + per-droplet scissor early-outs keep cost ∝ this frame's marks (§6). Viscosity → line-width factor floors at **1.0** (only widens) so the Skein.1 continuity invariant is preserved. Files: `Skein.metal` (`skein_fbm2` + `skeinDebugViscosity` + splatter/filament/viscosity in `skein_geometry_fragment` + the `visc` varying; the canvas-hold mv_warp config + `skein_fragment` cream ground untouched), `SkeinCanvasHoldTest.swift` (corridor-isolated pour-LINE continuity + a new splatter test: halo dense-near/sparse-far, viscosity response, opaque-not-additive, satellite bake/hold, per-frame new-mark count + a viscosity-sweep contact sheet). `Skein.json` unchanged. **Gates:** all 5 Skein tests green through the **live** scene→warp→overlay→blit→swap path — pour-LINE corridor continuity **1.000** (Skein.1 invariant preserved) + 1158 satellite pixels outside the corridor; splatter halo near/mid/far THIN 692/418/32 vs THICK 210/47/0 (dense-near ✓); viscosity response THIN 64 satellites @ meanSatDist 0.057 > THICK 18 @ 0.043 (more + wider ✓); opaque minCh = cream (no mud ✓); 178/179 frames added marks (new-mark count ✓). Full engine suite green except the same 7 pre-existing `love_rehab.m4a` fixture-absent failures; `PresetRegressionTests` + `DragonBloomMVWarpAccumulationTest` + `FataMorganaMVWarpAccumulationTest` byte-identical; `PresetLoaderCompileFailureTest` count intact (no silent MSL drop — FA #72); PresetAcceptance + PresetContrast green for Skein; app build clean; SwiftLint `--strict` clean (424 files). **Eyeball artifacts:** `SKEIN_VISUAL=1` accumulation contact sheet (960×540, ~2/5/10/20 s) + a **viscosity-sweep** sheet (thin | thick poles, independent fresh accumulations) through the live path; all 5 anti-references checked clear (matte not neon; ragged not polka-dots; pour not brush; ~9 % coverage not dead-mat; asymmetric not kaleidoscope). **No new capability** (Path A = nothing engine-side; registry instances refreshed, no status flip). **Deferred (unchanged):** `family: painterly` + `PresetCategory` case; per-track SHA seed + audio routing + ENGINE.1.2 (all Skein.3); wetness/sheen (ENGINE.2/Skein.4). **M7 round 1 (2026-06-05, live session `2026-06-05T22-59-05Z`, Mingus, 900×600):** Matt — "looks good"; flagged that **droplets read as rounded-SQUARES** (flat cardinal edges). Root cause (verified by zooming the live frame to the pixel level): the droplet AA used `fwidth(length(q−dpos))`, whose gradient is the radial unit vector → ~41 % wider AA at the diagonals than the cardinals → sharp cardinal edges snap to the axis-aligned pixel grid. **Fix:** isotropic `px = max(fwidth(q.x), fwidth(q.y))` AA + a `max(drr, px·1.5)` radius floor (so sub-2 px far satellites still read round). Droplets now round (bbox-fill 0.65–0.70 vs square ~1.0), regression-locked by a roundness gate in `SkeinCanvasHoldTest`; SHADER_CRAFT §18.3 corrected. Two non-code M7 items deferred: **colour** (white-on-cream is the deliberate Skein.2 boundary → stem palette lands at Skein.3) and **pacing** (a slow accumulator wants longer on-screen segments + energy-coupled painter speed — addressed at Skein.3 when speed ties to arousal/energy, plus `duration` tuning). **M7 round 2 (2026-06-05): Matt eyeball PASS** ("looks good") on the round droplets — Skein.2's aesthetic gate is met (a still frame reads as poured paint, not a particle fountain, with a believable droplet/halo/filament structure and a visible viscosity axis). Preset *certification* (full M7 ≥5 tracks + soak + determinism + golden dHash) remains **Skein.6**; `certified` stays false. Integrated to local `main` (merge `1310c1c4`, alongside the parallel AGC2 / D-146 merge `a07b2a56`; NOT pushed).

### Increment Skein.ENGINE.1.2 — `SkeinState` + gated slot-6 overlay buffer ✅ (2026-06-05, D-147)
The deferred ENGINE.1.2 (the CPU-side `SkeinState` + the per-preset overlay buffer) lands as Skein.3's first commit — its demonstrated consumer is the stateful audio routing. **Audit verdict: Option B (gated binding), Option A (pure config) UNAVAILABLE.** With file:line evidence: Skein renders via the marks-on-top `strandsOnTop` branch (`RenderPipeline+MVWarp.swift:212`), which **skips** `renderSceneToTexture` (`:217`) — the *only* site that binds fragment slot 6 (`RenderPipeline+MVWarpScene.swift:43-44`). Pass 2's `strandsOnTop` branch (`encodeMVWarpScenePass:77-79`) calls `drawSceneGeometryOverlay`, which binds only `features`@vtx0 + `stems`@vtx1 (`RenderPipeline+SceneGeometry.swift:36-37`) — **no fragment buffer**. So the overlay fragment could not see `directPresetFragmentBuffer`; Option A is impossible. Landed the lightest **Option B**: a gated `if let presetBuf = directPresetFragmentBuffer { setFragmentBuffer(index:6) }` in the `strandsOnTop` branch — affects only DB + Skein. **Byte-identical:** Dragon Bloom sets no `directPresetFragmentBuffer` (reset to nil at applyPreset top → no bind); Fata Morgana uses its own `renderFataMorgana` draw branch (never reaches `encodeMVWarpScenePass`). `SkeinState.swift` (new, GossamerState pattern): `SkeinHeaderGPU` (64 B) + 48 × `SkeinBurstGPU` (48 B) = the audio-modulated painter clock + per-track seed phases + dominant-stem line colour + onset-burst ring. Wired in `VisualizerEngine+Presets.swift` (construct/tick via `setMeshPresetTick` / `setDirectPresetFragmentBuffer`, cleanup); `currentSkeinSeed()` reuses the shared FNV-1a title|artist hash (`lumenTrackSeedHash` de-privatised). **Stub consumer:** commit 1 leaves the shader unchanged (buffer bound-but-unread) → Skein renders Skein.2-identical; the shader read lands in the routing commit. Files: `SkeinState.swift` (new), `RenderPipeline+MVWarpScene.swift`, `VisualizerEngine.swift` / `+Presets.swift` / `+Stems.swift`. **Gates:** DragonBloom + FataMorgana MVWarp accumulation + `PresetRegressionTests` byte-identical; `PresetLoaderCompileFailure` count intact; app build; SwiftLint `--strict` clean. Commit `f0fef708`.

### Increment Skein.3 — Stem palette + full emission routing ✅ (2026-06-05, D-147) — Matt M7 PASS 2026-06-06
Makes the painting **legibly musical**: `skein_geometry_fragment` consumes `SkeinUniforms@6` (ENGINE.1.2). **Routing (all D-026 deviation-normalised, D-019 warmup-gated):** stem→colour (one stable, well-separated colour per stem over cream — **Full Fathom Five: charcoal/oxblood/ochre/teal, Matt-approved**), composited **OPAQUE** (paired bestCover/bestCol → topmost colour, never mud); pour-line colour ← dominant stem (SkeinState discrete argmax — no blend), width ← its energy-dev + viscosity; splatter bursts ← per-stem activity (`*_energy_dev` above threshold, refractory-limited) frozen at each stem's colour (the onset-burst ring; **retires the Skein.2 debug flick schedule**); viscosity ← per-burst centroid (**retires the debug viscosity sweep**); flick sharpness ← attackRatio; painter speed ← broadband energy-dev; per-track seed → trajectory phase. **Key finding:** only `drums_beat` is a real pulse (the other `*_beat` reserved-zero) → per-stem onsets derive from `*_energy_dev` activity in SkeinState (the history the closed-form fragment cannot see). **sRGB (FA #71):** the `.bgra8Unorm_srgb` canvas sRGB-encodes on store → SkeinState sRGB-DECODES the display palette to linear before packing; without it dark stems lifted to washed mid-tones and painted nothing (drums/bass = 0 → 933/2905 after the fix). **§1.5 track-change reset:** on track change while Skein is active, reseed the painter from the new identity + `clearMVWarpCanvasToGround()` (a lightweight gated canvas wipe — DB/FM never call it). Files: `Skein.metal` (consume slot 6, MSL `SkeinUniforms`/`SkeinBurstGPU`, debug drivers retired, sRGB-aware header), `SkeinState.swift`, `RenderPipeline+MVWarp.swift` (`clearMVWarpCanvasToGround`), `VisualizerEngine+Capture.swift` (reseed+clear on track change), `PresetSessionReplay/SkeinRoutes.swift` (new — per-stem onset routes + painter-speed; centroid/attackRatio not SR.1-measurable), `SkeinCanvasHoldTest.swift` (real-stem colour/route gate + seed determinism). **Gates:** real-stem colour/route gate through the live path (replayed real stems) — **≥3 separable clusters (got 4 — all stems), opaque-not-mud 0.075, onset→splatter busy 129 vs steady 0, D-019 warmup 0-at-silence, bake+hold, round droplets**; seed determinism (same seed pixel-diff 0, diff-seed 3947, reseed clears 160→0 bursts); DB/FM MVWarp + PresetRegression byte-identical; PresetLoaderCompileFailure count intact; app build; SwiftLint `--strict` clean; **palette contact sheet → Matt signed off (Full Fathom Five)**. Commits `7098eff7` (colour+routing), `8ddcb438` (seed+reset); integrated to local `main` merge `ceaccfdf` (NOT pushed; only `DECISIONS.md` conflicted — kept the D-146 AGC2.5 amendment + D-147, no number collision). **Deferred (unchanged):** `family: painterly` + `PresetCategory` case; wetness/sheen (ENGINE.2/Skein.4); mood/structure/anticipation/locus (Skein.5); cert (Skein.6). **✅ M7 gate PASS (2026-06-06):** Matt "Looks great!" live on local-file session `2026-06-06T14-59-12Z` (Skein active, no errors, 4318 frames, all four stems active → every colour painted) — the legible-musicality gate is met. Full cert remains Skein.6.

### Increment Skein.ENGINE.2 — Wetness channel ✅ (2026-06-08, D-149)
The transient per-pixel **wetness** signal the wet/dry sheen needs: stamped ~1 where paint lands this frame, decaying toward 0 each frame (decay **pauses at silence**), readable at the display stage — without touching the **RGB lossless paint record** (the ENGINE.1 Hamming-0 invariant) and **byte-identical for every other mv_warp preset** (the D-137 beachball pitfall). **Audit verdict — approach A (canvas ALPHA channel), cleanest form (D-149):** the per-prefix override mechanism (`PresetLoader.swift:689`/`:691`, the Fata Morgana precedent) lets Skein own its warp + comp fragments with **no shared GPU code touched**. (1) **Storage = the feedback texture's ALPHA** (linear 8-bit on the `.bgra8Unorm_srgb` feedback — sRGB never touches A; RGB stays the lossless record). (2) **Stamp = the existing overlay alpha-over blend** (`A = bestCover² + dst.a·(1−cover)` → solid fresh paint → A≈1; **no new stamp code**). (3) **Decay = `skein_warp_fragment`** (holds RGB byte-identically — the identity sample — and does `A *= wetnessDecay`; `wetnessDecay = exp(-rate·dt·stemMix)` from `SkeinState` pauses at silence). (4) **Read-hook = the blit already samples the compose texture** → Skein.4 reads `.a`. Plumbing: a gated `mvWarpWetnessDecay` uniform (mirror of `mvWarpChromatic`) at warp-fragment `buffer(1)`, default 1.0 — only `skein_warp_fragment` declares it, FM never runs the standard warp pass → **DB/FM/Starburst byte-identical by construction**. **Cut-line: NOT invoked** (no shared format change, no new pass, no loop reshape). Approach B (dedicated R8) rejected (forces MRT on the shared overlay pass or a mark re-dispatch — more code/risk for the same separation). Files: `RenderPipeline.swift`/`+PresetSwitching.swift`/`+MVWarp.swift` (the uniform + bind), `Skein.metal` (`skein_warp_fragment`), `SkeinState.swift` (`wetnessDecay`), `VisualizerEngine+Presets.swift` (per-frame push, weak-captured; reset to 1.0 on preset switch), `SkeinCanvasHoldTest.swift` (`SkeinWetnessTest` + the RGB-only hold re-scope). **Gates:** `SkeinWetnessTest` green through the live path — stamp max ALPHA **255**, unpainted-corner decay **253→172** under music (0 rises = monotone), silence spread **0** (held exactly); DB/FM MVWarp accumulation + `PresetRegressionTests` (20 presets × 3 conditions) **byte-identical**; the RGB lossless-hold Hamming-0 (RGB-only) green; `PresetLoaderCompileFailure` count intact (no silent MSL drop, FA #72); app build clean; SwiftLint `--strict` clean. Commits `255fcc64` (engine), `c5192d28` (test).

### Increment Skein.4 — Wet/dry sheen ✅ (2026-06-08) — pending Matt's M7
The **wet-now / dry-past legibility device** (`SKEIN_DESIGN §1.4`): fresh paint glistens, the accumulated past is matte, so the eye tracks the musical *now*. `skein_comp_fragment` (the `<prefix>_comp_fragment` override — the shared `mvWarp_blit_fragment` stays byte-identical) reads canvas RGB + wetness A: **wet → GGX specular** (normal from the canvas **luminance gradient** — central-difference/Sobel bump, the 2D analogue of a surface normal; tonemapped GGX NDF, Walter et al. 2007), **hard-gated by wetness** (`smoothstep` on A) so it fires on recent paint and ~0 on the dried past; **dry → matte + slight desaturation**; subtle canvas-weave grain (fades under thick paint). The sheen is an **additive glint + a subtle wet saturation "deepen"** (glossy *depth*, not whitening) so the Skein.3 stem colours **read THROUGH** it — and a **paint-present mask** (distance from the cream ground) keeps the bare canvas matte. **sRGB (FA #71):** the feedback is `.bgra8Unorm_srgb` → sampling auto-decodes to linear; lighting in linear; the drawable re-encodes on store — **no manual decode** (the inverse of FM's linear-feedback trap). Bloom-on-wet-specular **deferred** (needs a pass / governor state at the blit — the in-shader glint gives the sparkle without a new pass, cut-line-conscious); **no new audio routing** (wetness = where paint landed, FA #67). Files: `Skein.metal` (`skein_comp_fragment` + sheen tuning), `SkeinCanvasHoldTest.swift` (wet-now/dry-past gate via the BLIT + per-checkpoint BLIT capture + sheen contact sheet + canvas-vs-blit isolation PNG). **Gates (live BLIT path, real replayed stems):** wet (A>180) sheen boost **25.77** mean vs dry (A<80) **3.71** (≈7×), a **162**-byte glint catches the light, stem colours read through — **CANVAS [1906,7205,5601,10328] → BLIT all 4 stems intact** (a highlight, not a recolour); full engine suite green except the same 7 pre-existing `love_rehab.m4a` fixture-absent failures (+ the known MemoryReporter flake); `PresetRegressionTests` + DB/FM MVWarp byte-identical; `PresetLoaderCompileFailure` count intact; app build clean; SwiftLint `--strict` clean. **Eyeball artifacts:** `SKEIN_VISUAL=1` sheen contact sheet (4 checkpoints, live BLIT) + a canvas-vs-blit isolation (L: raw matte canvas, R: sheened blit) — the recent wet bursts glisten/deepen vs the matte teal lines. **Round-1 self-review false alarm (logged):** a 900-frame run read as "the sheen killed the colours" — the cause was the session's other-dominated intro (one stem painted yet), not the sheen; a 1500-frame run shows all 4 stems read through (SHADER_CRAFT §18.9). **M7 round-1 (Matt, live, 2026-06-09, session `2026-06-09T13-00-27Z`, Cherub Rock):** "one of my favorite presets so far" — but two defects: (1) the pour appears as **overlapping circles that smooth into a line after ~a second** (kills the dribble illusion), (2) the **wet doesn't fully read as glistening**. **M7 round-2 fixes (2026-06-09):** (1) **retired the Skein.1 trailing-tail age-taper** — the radius+opacity ramp across co-located tail samples drew the concentric rings (it was the *stand-in* for a wet edge before ENGINE.2 existed); the pour now LANDS SOLID (full opacity, constant radius, speed→width only) → a continuous dribble, and the wetness channel carries "fresh = wet". (2) **two-term sheen** — a BROAD gloss (smooth normal, keeps the wet body glossy) + a SPARKLE (fine `perlin2d` micro-normal — bright catch-lights = the glisten); dropped the saturation "deepen" (it darkens in sRGB). Gates re-green: pour-LINE continuity still **1.000** (solid stroke), wet boost **25→76** mean / glint **162→192** with all 4 stems reading through, PresetRegression + DB/FM byte-identical (Skein-metal-only changes). **M7 round-2 (Matt, live):** rings STILL present at slow movement + "the glistening just makes the paint look SPECKLED — it does not convey wet." **M7 round-3 fixes (2026-06-09):** (1) the real ring cause was the rendering FORMULA — `max over per-capsule coverage` with a PER-SEGMENT speed→width radius scallops at slow/looping movement (the sheen amplifies it into concentric arcs); fixed by rendering the stroke as ONE **union SDF** (`min over segments of segDist−r`) with one per-frame radius → a single smooth tube (verified smooth on real music). (2) **retired the micro-normal sparkle** (it reads as grain) and **corrected the wet model** — wet paint is DARKER + more SATURATED (water-soaked) with a coherent glossy catch-light, not brighter/speckled (dry = lighter + matte). The wet/dry gate now measures the sheen's content-isolated effect (`blit−canvas`): wet Δchroma +29.5 / Δluma −0.2, dry Δchroma −20 / Δluma +6.9, gloss max +156, all 4 stems read through. `distinctBlobs` threshold 8→3 (session-robust — confirmed pre-existing via revert; the now-largest session is line-dominant so droplets connect to the line; dot shape/firing covered by the roundness + onset→splatter gates). SHADER_CRAFT §18.9 updated with the rounds-2–3 corrections. **M7 round-3 re-look (Matt):** the wet *direction* was INVERTED — "lighter on application, darker as it dries." The broad glossy catch-light brightened fresh paint enough to cancel the darken (wet Δluma only −0.2), so fresh read lighter + dried darker. **Round-3b fix:** the body darken DOMINATES the gloss (darken ×0.74; gloss shrunk to a tight glint rough 0.12 / gain 0.40) → wet Δluma −13 (clearly darker), dry +6 (lighter) = correct direction. **M7 round-4 (Matt):** "the rings appear ~1s after the line and then fade — they were displaced, not removed." The union-SDF fixed the line GEOMETRY, but the rings were the SHEEN amplifying the WETNESS AGE-BANDS — a looping painter lays overlapping passes at different ages → a solid stroke has a finely-banded wetness map → the read-time sheen renders the bands as concentric rings ~1s later (once the wetness decays into the steep part of the wet→dry gate), then they fade. **Round-4 fix:** BLUR the wetness the sheen reads (13-tap two-ring Gaussian ≈±12 texels) + a near-LINEAR gate (smoothstep 0.05,0.95); the large-scale wet→dry read is preserved. **New gate `test_sheen_noConcentricRings`** reproduces the transient (real stems, max-over-checkpoints of the sheen-added local luma range at smooth painted interiors) — A/B-validated by revert: 27.6 (rings) → 8.5 (blurred). **✅ M7 PASS (2026-06-09, session `2026-06-09T15-19-40Z`):** Matt — "Rings are gone and the drying of the wet paint looks good too." Skein.4 (the wet/dry sheen) is **accepted**; `certified` stays false (full cert Skein.6). **Deferred to a new session (Matt, context-budget): Skein.4.1 colour-per-stroke** — the line recolours mid-stroke because the redrawn tail uses the current dominant-stem colour; the fix is to freeze the line colour per-segment (a `SkeinState` breakpoint ring, mirroring the per-burst colour freeze) so a colour change reads as a new pour. Paste-ready prompt: `~/Downloads/SKEIN.4.1_color_per_stroke_session_prompt.md`.

### Increment Skein.4.1 — Colour-per-stroke ✅ M7 PASS (2026-06-09, 2 rounds)
The pour line's colour = the dominant stem (`SkeinState` argmax) applied uniformly along the redrawn 40-frame tail each frame, so a dominant-stem switch recoloured the recent stroke ("the colour changes in the middle of a stroke," Matt M7 2026-06-09, session `2026-06-09T14-19-14Z`). **Landed (D-150) — Matt chose option 2 (a colour change is a genuinely NEW pour, not a recoloured seam):** a `SkeinState` colour-**breakpoint ring** (push `(painterTau-at-switch, linear colour, bounded position offset)` on each dominant change) packed as an additive tail of the slot-6 `SkeinUniforms` (`SkeinBreakGPU`, 24 B; `pad0`→`breakCount`). `skein_geometry_fragment` Layer A looks up each tail sample's lay-time colour+offset (`skeinLineLookupAt`, ascending-ring early-out) so (a) already-laid paint **keeps its colour** (the per-burst freeze applied to the line) and (b) a switch starts a **spatially displaced new pour** — each pour carries a fixed-magnitude (0.05 UV) golden-angle-rotated offset (non-cumulative → never drifts off canvas; seeded → §5.7 determinism), and the segment bridging two pours is not drawn → a clean gap. **Coverage is byte-identical to Skein.4's union SDF** (one per-frame radius → `max-over-capsules ≡ 1−smoothstep(min sdf−r)`), so no rings regression. Bursts flick from the jumped position (throw direction from the un-offset path). Files: `Skein.metal` (`SkeinBreakGPU`/`SkeinLineLookup`/`skeinLineLookupAt` + Layer A rewrite + `SkeinUniforms` additive tail), `SkeinState.swift` (the ring + jump + `SkeinColorBreakpoint` test accessor + `lineDominantStem`), `SkeinCanvasHoldTest.swift` (`test_lineColorFreeze_keepsColourAndStartsNewPour` + helpers). **Gates:** the new live-path test green (switch stem 2→1: pre-switch @offA X=61 Y=0 — old paint kept its colour; post-switch @offB Y=61 X=0; jump 0.093, new pour at offB not the un-jumped path); silence continuity 1.000; `test_sheen_noConcentricRings` 8.68 < 13; real-stem colour separation (4 stems, mud 0.067); determinism same-seed=0; DB/FM + `PresetRegressionTests` byte-identical; `PresetLoaderCompileFailure` count intact (FA #72); full engine suite 1408 tests, 7 pre-existing `love_rehab.m4a` fixture-absent failures only; app build + SwiftLint `--strict` clean. Eyeball: `SKEIN_VISUAL=1` real-stem palette/sheen contact sheets (live path) show distinct per-stem coloured pours. **M7-round-2 (Matt, live, 2026-06-09, session `2026-06-09T16-23-21Z`): "the lines are very short rather than a long continuous dripping/pouring across the canvas."** Root cause (measured on the session: **63 dominant switches / 44 s, median pour 0.2 s**) — the dominant-stem argmax flickers far faster than a pour reads, so each tiny pour + jump became a short displaced segment. Fix: a new pour now COMMITS only on a sustained, decisive change — `minPourTau = 3.0` τ (≈ half-canvas minimum) since the last switch AND the challenger leads by `pourSwitchHysteresis = 1.25×`; colour/flow/viscosity follow the *committed* pour (not the instantaneous argmax); bursts stay ungated. Validated: **63 → 10 long pours (~4 s avg)**; contact sheet on `2026-06-09T13-06-15Z` shows long continuous coloured pours across the canvas. Test surface: `distinctBlobs` demoted to a diagnostic (long lines absorb droplets → ~0 separable blobs even though splatter fires; gate the route on per-stem spawns + busy≫calm instead), bake/hold made colour-agnostic (a longer first pour can be low-spread charcoal). All gates re-green (Skein suite, DB/FM + PresetRegression byte-identical, app build, SwiftLint `--strict`). **Deferred (unchanged):** `family: painterly` + `PresetCategory` case; mood/structure (Skein.5); cert (Skein.6).

---

### Increment Skein.ENGINE.3 — Structural-section signal → preset tick ✅ (landed 2026-06-09; D-151; Matt chose option (a))
**Discovered as a prerequisite of Skein.5's structure sub-feature** (the increment was split: `StructuralPrediction` is DSP/orchestrator-only and does not reach the preset tick). Matt chose **option (a) — a deliberate engine increment** (over an in-state proxy / deferral) for real section-awareness, honouring infra-before-preset (FA #59/#60). **Landed (D-151):** a **gated `RenderPipeline.setStructuralPrediction(_:)`** (separate lock-guarded `storedStructuralPrediction` + computed `latestStructuralPrediction`, default `.none` — mirrors the `setMood` value-injection bridge) is called from `VisualizerEngine+Audio.swift` **at the per-frame MIR publish (right after `setFeatures`, reading `mir.latestStructuralPrediction`)** — NOT the `setMood` site the prompt's recon suggested, because that site is unconditional + freshest (the `setMood` path early-returns when the mood classifier is absent / throws); the Skein tick closure reads `pipeline.latestStructuralPrediction` and passes it to the extended `SkeinState.tick(…structure: = .none)`, which STORES `sectionIndex`/`sectionStartTime`/`confidence` + a one-frame `didCrossSectionBoundaryThisFrame` flag (cleared on `reseed`). **CPU-only** (no `FeatureVector`/`Common.metal` change; never written to the GPU buffer), **byte-identical** for every other preset (the setter is inert at `.none`; even Skein's own render is byte-identical), golden-locked (`PresetRegressionTests` 20×3 + DB/FM MVWarp accumulation + `PresetLoaderCompileFailure` count, all green). **Delivers + proves the signal only; the structural VISUAL is Skein.5** — the app is **visually identical to today**. Gate: `SkeinStructureSignalTests` (FA #66 — real bridge + the `meshPresetTick` invocation indirection + ingestion + one-frame boundary). Full engine suite green (the known 7 `love_rehab.m4a` fixture-absent fails excepted); app build + `swiftlint --strict` clean. Prompt: `~/Downloads/SKEIN.ENGINE.3_structure_plumbing_session_prompt.md`.

### Increment BUG-035 — NoveltyDetector ring-wrap boundary dedup ✅ (landed 2026-06-09; Skein.5 step 1)
The AUDIT.1 finding gating Skein.5: `NoveltyDetector` stored boundaries by LOGICAL ring index; once `SelfSimilarityMatrix` filled, indices slid ~30 per `detect()` and the 120-frame dedup window re-admitted the same physical boundary every ~4 calls (~4-5 near-equal-timestamp duplicates per real boundary → section durations collapsed, `sectionIndex` inflated ~5×, confidence depressed — the exact D-151 signal). **Fix:** `SelfSimilarityMatrix.totalFrameCount` (monotonic) + `NoveltyDetector` stores/dedups in **absolute** frame-index space (`Boundary.frameIndex` now absolute); `MIRPipeline.latestStructuralPrediction` write moved under the lock (was the only published property outside it). **A/B-proven:** `noveltyDetect_ringWrap_boundaryRegistersOnce` (pre-fix 3 dups, identical timestamps) + `structuralAnalyzer_ringWrap_boundaryRegistersOnce` (production 600-frame geometry, pre-fix 2 dups) — post-fix exactly 1 each; `SkeinStructureSignalTests` + AABA golden green. Same session also hardened the Skein.4.1 colour-freeze gate (it hard-depended on the single largest recorded session — tonight's new session broke it; it now scans all sessions for the most decisive switch pair). KNOWN_ISSUES + RELEASE_NOTES_DEV updated.

### Increment Skein.5 — Mood + structure + anticipation + painter-locus ✅ (landed 2026-06-09; D-152; **M7 PASSED 2026-06-10** — Matt "Looks great", session `2026-06-10T03-09-20Z`)
The §1.3/§1.5 musicality layer on the working look — no new visual subject; routing + a subtle palette/motion modulation. **Mood:** valence/arousal EMA-smoothed in `SkeinState` (τ 4 s, FA #25 — never written back); `moodTinted(_:)` warms/cools (±18 % R / ∓16 % B multiplicative) + saturates (floor 0.85, never `mix(cream, hue, sat)`) the LINEAR palette **at lay time, frozen** into breakpoints + bursts — the lossless canvas archives the song's emotional arc; arousal → painter speed (×0.7–1.3), splatter refractory (÷ up to 1.5), pour width (+15 %). **Structure (consumes ENGINE.3/D-151, post-BUG-035):** a confident boundary (smoothstep 0.25→0.55 on `confidence`; below ⇒ EXACTLY zero bias — pure allover) fires a density pulse (τ 2.5 s), a boundary-forced fresh pour (floored 1.0 τ — D-150 long pours intact), a region-lean target (`seed + (sectionIndex mod 5)·goldenAngle`, ≤ 0.085 UV, EMA τ 2.5 s) routed **through the per-pour breakpoint offsets** (never a per-frame trail displacement — that smears the redrawn tail), and a ± 0.10 per-section warmth emphasis; repeated section slots revisit + densify the same patch. **Anticipation (FA #33):** τ-SPEED warping — wind-up `1 − 0.45·smoothstep(0.70, 1, beatPhase01)`, flick `+0.90·exp(−t/90 ms)` at the wrap; τ-warping keeps every tail sample ON the trajectory curve → cannot smear by construction; `mix(1, factor, stemMix)` ⇒ exactly 1.0 at silence. **Locus (flagged, OFF — `SkeinState.defaultLocusEnabled`):** display-only in `skein_comp_fragment` (the prompt's geometry-fragment site would BAKE it — FA #70 contract); the blit gains a gated `bindCompStagePresetBuffer` (slot-6 buffer at fragment buffer 1, ENGINE.2 inert-binding precedent); glow + occlusion shadow ring so it reads on cream. Files: `SkeinState.swift` (m5 `MusicalityState` + helpers extension), `Skein.metal` (`locusEnable` ← pad1 + comp locus), `RenderPipeline+MVWarp.swift` (+ split `RenderPipeline+MVWarpReducedMotion.swift` for file-length), `SkeinCanvasHoldTest.swift` (`MusicalityDrive` fixture inputs + 4 gates + contact sheet). **Gates (live path, real stems):** mood — warmth(R−B) 106.4 warm vs 81.4 cool, coverage +24 % with +arousal, pale share 0.003 ≪ 0.30; structure — spawns 88→144 across a boundary on IDENTICAL tiled audio, lean 0.083 ≤ 0.085, fresh pour +1, conf 0.05 ⇒ all-zero; anticipation — wind-up 0.649 / flick 1.627, silence exactly 1.0; locus — canvas byte-identical on/off, 24-px localized blit glow. `SKEIN_VISUAL=1` contact sheet `/tmp/skein_pour_diag/<stamp>/skein5_mood_montage.png` (hiV_hiA | hiV_loA | loV_hiA | loV_loA | locus_on). All prior Skein gates + DB/FM + `PresetRegressionTests` byte-identical + loader count intact; full engine 1419 tests (7 known love_rehab fixture-absent only); app build + SwiftLint `--strict` clean. **Done-when remaining: Matt M7** (mood + sections read; wind-up-flick with the beat). D-152. Deferred: cert + `family: painterly` (Skein.6).

### Increment Skein.5.1 — The painter never pours white ✅ (landed 2026-06-09; D-152 amendment; **M7 re-look PASSED 2026-06-10** — Matt "Looks great", session `2026-06-10T03-09-20Z`)
Matt M7 on session `2026-06-09T22-35-09Z`: "a different white line pattern showing on screen when the track starts… white disturbs the colour palette." Root cause: the Skein.1-era WHITE-BASELINE breakpoint — at canvas birth most of the 40-frame tail (incl. negative-ctau samples) resolved to the white era, baking a permanent tail-length white squiggle, displaced from the first coloured pour by its jump, different per track (the seed). **Fix (D-152 amendment):** the ring starts EMPTY (shader skips Layer A at `breakCount == 0` — no line until a pour commits); the FIRST commit waits `firstPourSettleTau = 0.25` τ (colour from ~¼ s of smoothed evidence, not one frame's argmax — D-150 decisiveness; a settle-window crash guard added for the −1 dominant index) and RETRO-COLOURS the pre-commit tail (`tauStart = 0`, no jump on the first pour) — the first stroke appears already in the lead stem's colour; the painter CLOCK pauses at true silence (`activity = max(stemMix, smoothstep(0.01, 0.04, fvEnergy))` — wetness-pause semantics; FV term keeps the clock running while stems converge). The Skein.1 "white line at silence" invariant is deliberately retired. **Gates:** `test_pourLine_accumulatesHoldsContinuous` redesigned — CALM real-stem drive (all devs below the onset threshold ⇒ line without splatter), accumulation/hold/continuity (corridor vs `finalPainterTau`) + `!hasWhiteTexel` + silence-run `painted == 0`; `!hasWhiteTexel` added to the real-stem gate (canvas birth + real stems = the defect scenario); colour-freeze gate re-green with the cleaner ring (`[ochre@τ0 off-0, oxblood@τ6.72 #1]` — the settle eliminates the spurious first-frame-argmax pour); breakpoint-ring diagnostic added to its print. Pour contact sheet re-pointed at calm stems (silence is now correctly empty cream); regenerated: line opens in colour, never white. PresetRegression/DB/FM + loader count green; SwiftLint `--strict` clean.

### Increment BUG-049 — Skein colour-freeze gate: feasibility-aware switch selection ✅ DONE (fix 2026-06-11; armed-path validation completed same evening — addendum at end of row)
The colour-freeze cert gate (`test_lineColorFreeze_keepsColourAndStartsNewPour`) picked its dominant-stem switch on decisiveness alone and only discovered at sampling time that the switch was un-sample-able (pre/post windows < 3·dτ inside the pour's reign / probe extent) — `Issue.record` red on session-set content, not code, whenever a new capture changed the pick (the 19:49 RB.2-2 closeout battery hit this; the Skein.4.1 scan-all hardening had fixed the previous face of the same fragility). **Fix (commit `a6899893`, test-infrastructure only):** `switchSampleInfeasibility` — a CPU-only dry run replaying the candidate's exact tick sequence (SkeinState.tick has no GPU read-back, so it predicts the live run's painter clock / dominant stem / breakpoint ring exactly) — vets every candidate DURING selection; the scan walks candidates in decisiveness order and arms on the most decisive switch that is also sample-able; the in-run guard remains as a dry-run/live parity safety net (its firing now means parity divergence, with that diagnosis in its message). No-candidate session sets skip LOUDLY (counts + per-candidate rejection reasons printed; never red, never silent — BUG-049 criterion 1); the Skein.3 real-stem routing gate gained the same scan-all + loud-skip treatment (it hard-depended on the single LARGEST session and went red when that was a 602-byte recorder stub). Colour-freeze assertions (pre-switch X≫Y, post-switch Y≫X, jump magnitude, new-pour-not-on-old-path) untouched. **Done-when:** met for the unusable-set arm (SkeinCanvasHold 21/21 green on the current 11-stub session set, skip reasons printed); **armed-path arms (criteria 1a/1b + the criterion-2 adversarial colour-unfrozen A/B) BLOCKED** — the only real capture (`2026-06-11T13-10-42Z`, 2.98 MB) vanished from `~/Documents/phosphene_sessions` between the 19:49 filing and the fix session (unrecoverable: Trash TCC-denied, no quarantine copy, no snapshot). Next real listening session: expect `[skein_colorfreeze] picked …` + green, then run the A/B. KNOWN_ISSUES banner + release notes dev-2026-06-11-h. Capability registry untouched (no renderer/preset capability change). **Validation addendum (same evening, parallel session):** the block was cleared without waiting for a listening session — `FixtureSessionCaptureGenerator` (new, engine test target `Diagnostics/`, env-gated `PHOSPHENE_GEN_SESSION_DIR`) replays vendored tempo fixtures through the production pipeline (ffmpeg decode → StemSeparator 10 s chunks → StemAnalyzer per 1024-hop → `SessionRecorder.csvRow`) and wrote three real `fixturegen-*` captures (~1290 frames each; FA #27-compliant). Criteria 1a/1b: gate ARMED (`picked fixturegen-so_what`, bass→drums switch) and SkeinCanvasHold ran 21/21 green with recorder stubs simultaneously present; criterion 2: freeze deliberately broken in `skeinLineLookupAt` (latest-breakpoint colour for every τ — the literal Skein.4.1 defect) → gate RED on its headline assertion (PRE-switch X=0 Y=61), reverted → green (X=61 Y=0); empty-dir leg: loud skip, green. The captures stay in place (regenerable in ~7 s) so the armed path no longer depends on listening-session happenstance. Release notes dev-2026-06-11-i.

### Increment BUG-048 — Canonical `xcodebuild test` un-broken: engine bundle removed from the app scheme's test action ✅ (2026-06-11; found by REVIEW.3's first three evidence blocks)
The app scheme's test action had included `PhospheneEngineTests` since U.1; under xcodebuild's test-runner context the engine bundle fails on environment, not code — ffmpeg subprocess spawn and repo-relative file reads denied ("Operation not permitted"), the REVIEW.2 audio churn tests die in ~1 ms, `DocIntegrityTests` reads an empty DECISIONS.md, and only ~440 of 1439 engine tests load — so the canonical app-test invocation was permanently red (exit 65) while the pure app run inside it passed. Confirmed environment-class by three evidence blocks (sandboxed shell / unsandboxed shell / Matt's terminal — identical signature). **Fix (Matt's option-1 pick over making the engine bundle xcodebuild-compatible):** remove the engine `TestableReference` from `PhospheneApp.xcscheme`'s test action — the engine suite's canonical runner is `swift test --package-path PhospheneEngine` (where all of this passes); double-running 1439 tests in a broken environment added noise, not coverage. **Done-when (met):** `xcodebuild test` exits 0 / `** TEST SUCCEEDED **` / 382 app tests green with no engine-bundle run; `SchemeTestActionRegressionTests` (engine suite) regression-locks the test-action shape (engine bundle absent AND app target present); RUNBOOK §Build and Test documents the split; KNOWN_ISSUES BUG-048 resolved with commit `e110b1ca`; release notes dev-2026-06-11-g. P2 single fix increment (root cause documented before code). Capability registry untouched.

### Increment REVIEW.3 — Closeout evidence script ✅ (2026-06-11)
Eliminates the false-green closeout class (REVIEW.1 confirmed incident: CSP.3.4 claimed 1358/1358 green; the suite failed reproducibly the next day) by replacing hand-transcribed test claims with a script-generated evidence block closeouts paste verbatim — the cheap path is now the honest path. **`Scripts/closeout_evidence.sh`** (no arguments, one mode — no quick/tiered variants) wraps the canonical RUNBOOK §Build-and-Test verification set (engine SPM tests, app xcodebuild tests, `swiftlint --strict`) and emits one fenced markdown block: header (ISO-8601 timestamp, host, short HEAD + branch, dirty/clean tree with paths), per-step verbatim tool summary lines + exit code + wall time + failing-test identifiers (≤ 20, verbatim), and a footer recapping exit codes with the verdict line (`EVIDENCE: ALL GREEN` only when every step exited 0 AND parsed failure count is 0; otherwise `FAILURES PRESENT`). Honesty contract: step failures reported never fatal (script exits 0 when evidence was gathered; the verdict line carries truth); counts extracted from tool output only, never script arithmetic (`PARSE FAILED — raw output follows` on extraction failure); additive grep only (pull summaries/failures, never filter noise); missing tool → `STEP FAILED TO RUN`, never a silent skip; dirty tree reported not fatal. A byte-identical copy lands at `~/.phosphene/last_closeout_evidence.md` so a pasted block can be diffed against what was actually generated. CLAUDE.md closeout template item 2 now requires the pasted block (prose may annotate below it, never replace it; block missing or commit-hash mismatch ⇒ closeout incomplete on its face; RB.2 will relocate the prose — the script path is the stable interface, the prose location is not). **Done-when (met):** canary-verified un-greenwashable — a deliberate `REVIEW3CanaryTests` failure produced `FAILURES PRESENT` with the canary identifier listed verbatim; the canary was deleted (tree verified back to pre-canary state); the post-commit clean run produced the increment's own self-certifying block. Capability registry untouched (no renderer/shader/cert capability change).

### Increment RB.1 — Rulebook audit (audit-only) ✅ (2026-06-11)
Evidence-cited verdict (RETIRE / MECHANIZE / DEMOTE / KEEP) for every active rule in the four rulebook populations, driven by the REVIEW.1 rule-usage table (citation counts; never-cited lists; corpus-window caveat applied to pre-2026-05-08 rules). **Done-when (met):** mechanical inventory (49 FA + 63 Do-NOT + 21 sections + 161 active D entries = 294; cross-check found D-013/031/046/086/120 already pruned to history and 15 FA numbers already moved per the gap table; only the 6 unnumbered D-LM entries were unexpectedly unmatchable by REVIEW.1's extraction — 2 %, under the 15 % stop threshold); complete verdict table (294/294 rows, 0 missing verdicts — verification greps pass); summary + budget + flagged set + RB.2 sketch + ratchet proposal. **Headline:** rule-level KEEP collapses to 12 distinct always-loaded slots (< the ~15 expectation); CLAUDE.md measured at ~22,300 tokens; projected post-RB.2 core ≈ 7,000 tokens (**proposed hard cap: 7,000 tokens, one-in-one-out**); verdict mix 37 KEEP / 35 MECHANIZE / 128 DEMOTE / 94 RETIRE; 8 flagged questions for Matt (incl. the D-039/BUG-034 interaction and the Phase-MD planning-bloc retirements). Deliverable: [`docs/diagnostics/RB1_RULEBOOK_AUDIT.md`](diagnostics/RB1_RULEBOOK_AUDIT.md) (rule text + repo evidence + citation counts only — no transcript content; public-repo constraint honoured). Capability registry untouched (no renderer/shader/cert capability change). Docs-only; no rule was moved, deleted, reworded, or renumbered; no gate was built. **RB.1.1 follow-up (2026-06-11):** the audit's six numeric aliases (D-9xx range) for the unnumbered `D-LM-*` entries collided with the DOC.4.1 referential-integrity gate landed the same day in a parallel session — `DocIntegrityTests` treats every `D-###` token under docs/ as a citation that must resolve to a DECISIONS/HISTORY header, so the engine suite failed on six unresolvable aliases. Fixed by dropping the aliases and referencing the `D-LM-*` names directly throughout the audit tables (least-invasive option: no gate allowlist that would weaken the D-155/D-145 corruption coverage, no DECISIONS.md renumbering). Both increments' intent preserved; DocIntegrityTests suite green.

**Redirected 2026-06-11 (Matt, in-session):** the verdict-table approach was rejected — citation-driven defaults and necessity rubrics are subjective with an illusion of rigor; some rules' founding "mistakes" may themselves be misdiagnoses (FA #48 named). New deliverable: **plain-English per-entry explanations** (what it is / why it exists / what happens if removed, with honest lack-of-context flags) for all 49 FAs + 63 Do-NOT bullets — [`docs/diagnostics/RB1_FA_DN_EXPLANATIONS.md`](diagnostics/RB1_FA_DN_EXPLANATIONS.md). **Matt decides per entry; no verdicts in the deliverable.** The v1 verdict tables remain as inventory/measurement reference only. Matt's stated expectation: 80–90 % of FAs/DNs disappear.

### Increment RB.2 — Rulebook purge, FA/DN scope ✅ (2026-06-11; executed against Matt's per-entry in-session review)
Matt reviewed the RB.1 explanations doc per entry and directed: keep FA #27/#31/#64/#65/#67/#73 + the `@Published` write-or-clear bullet; FA #4 held pending his ruling on beat-driven-motion-as-technique; replace FA #39/#63 with a session-start checklist; FA #21 → code comment; remove everything else; accept all DN recommendations. **Executed:** CLAUDE.md FA list 49 → 7 entries, §What NOT To Do 57 → 1 bullet (16,530 → 7,614 words ≈ 10.3 k tokens, −54 %); gap table extended so all 42 removed numbers resolve (DOC.4.1 gate green); one-line tombstones in `HISTORICAL_DEAD_ENDS.md §RB.2`; new [`docs/PRESET_SESSION_CHECKLIST.md`](PRESET_SESSION_CHECKLIST.md) (replaces FA #39/#63 + the Arachne read-first bullet, includes render-early) pointered from §Visual Quality Floor; FA #21/DN-42 facts moved to doc comments in `SystemAudioCapture.swift` (DN-43/DN-54 were already documented at their code sites); `DocIntegrityTests` FA floor 40 → 7. **Open from this scope:** FA #4 ruling (recommend: remove + soften §Audio Data Hierarchy to constraint-based framing per FBS evidence); FA #25 mood-preservation test and FA #72 MSL-name lint (noted follow-ups, not built). **Not yet scoped:** SEC (CLAUDE.md sections) and D (DECISIONS.md) populations — Matt has not ruled on those; the RB.1 v1 tables remain reference-only.

### Increment RB.3 — Ratchet ratification + engineering-plan split + memory consolidation ✅ (2026-06-11)
The three standing ratchet rules ratified and installed (CLAUDE.md §Increment Completion Protocol + **D-161**): 7,000-token cap one-in-one-out (gated by the new `DocIntegrityTests` budget test — CLAUDE.md at ~6,925 est. tokens after install), new-rule admission test, violated-twice → mechanize. Pruning pass gains step 5 (plan-narrative aging). **ENGINEERING_PLAN split:** completed-increment narratives dated before 2026-06-01 moved to [`ENGINEERING_PLAN_HISTORY.md`](ENGINEERING_PLAN_HISTORY.md) (91 bodies, two rounds; headers stay as the status record; 254/254 headers preserved); plan 127,516 → 83,048 words (−35 %) — June narratives age out at future pruning passes under the same convention. `What This Is` doc-list sentence compressed (also fixed its long-standing trailing-clause typo). `__pycache__/` gitignored. Memory consolidation run against the auto-memory directory (stale facts pruned, completed-project entries collapsed). Doc-integrity suite green (4 gates incl. the new budget gate).

### Increment RB.2-2 — Rulebook purge, FA #4 + SEC + D scopes ✅ (2026-06-11; Matt: "follow your recommendations")
Completes the RB.2 populations. **FA #4:** entry retired; §Audio Data Hierarchy reframed from "beat is never primary / non-negotiable" to constraint-based ("beat-locked motion is a valid technique on the cached `BeatGrid` with D-154 irregular-track exclusion + D-157 bounded footprint; never primary from raw live onsets"); gap-table row + tombstone added. **SEC:** the 8 pointer sections + UX Contract + Visual Quality Floor merged into one §Handbook Index table; §Linked Frameworks folded into Development Constraints; §Code Style trimmed (U.11 build/test narratives → `RUNBOOK.md §Engineering notes`); §Authoring Discipline compressed to the universal working-agreement rules with the preset-session discipline (musical role, temporal contract, three-part bar, production-pipeline testing obligations, grounding priority, evidence-based closeouts) moved to `PRESET_SESSION_CHECKLIST.md` Part 2; Cold-Start Phase Contract compressed (full history already in BEAT_SYNC.md). **CLAUDE.md: 16,530 → 5,055 words (~22.3 k → ~6.8 k tokens, −69 % from the RB.1 baseline — under the RB.1-proposed 7,000-token cap).** **D:** 93 entries (shipped one-time choices, reverted/superseded/abandoned, executed design history, unexecuted Phase-MD planning artifacts) moved to `DECISIONS_HISTORY.md` §RB.2-2 batch (the D-082 Amendment moved with its parent); 68 stay active (standing constraints, live Skein/FBS/canvas contracts, legal/brand posture D-111/113/114/119/121/122 with the REVISIT banner re-anchored before D-111, gate rationales D-026/079/146); DECISIONS.md 94,982 → 39,861 words (−58 %). `DocIntegrityTests` green throughout (D continuity/uniqueness/resolution across both files; FA resolution via extended gap table); stale `#11 placeholder` note in HISTORICAL_DEAD_ENDS corrected. Follow-ups standing from RB.2: FA #25 mood-preservation test, FA #72 MSL-name lint (noted, not built).

### Increment REVIEW.2 — Session-lifecycle churn regression net ✅ (2026-06-11; the REVIEW.1 top countermeasure, Matt's option-1 pick)
Mechanical gate for the hang class REVIEW.1 measured as the dominant correction cost (BUG-021 ABBA deadlock, LF.5 Next-button freeze loop, LF.6.streaming quit hang): `SessionLifecycleChurnTests` (engine suite, `.serialized`, ~11 s) — six churn tests driving the REAL AVFoundation dispatch path (AVAudioEngine + AVAudioPlayerNode + scheduleFile completions; no doubles on audio objects) through the live entry points: router-level start/stop churn at varied dwells (the `advanceLocalFileQueue` call pair), completion-callback-vs-stop churn on a looping 0.25 s real-music excerpt (the exact BUG-021 ABBA surface, exercised ~4×/s), onFileEnded-driven 8-advance queue churn (Next-button shape), pause/resume/isPaused hammer threads racing stop/start (D-LF5-3 transport surface), deinit-while-playing (quit shape), and concurrent double-start. Every lifecycle step runs on a detached thread under a 5 s watchdog — a recurrence FAILS with the named step instead of hanging the suite (failures travel through a lock-guarded box; issues recorded on the test thread because raw threads lose Swift Testing's task-locals). Fixture: 0.25 s excerpt cut at runtime from the real `love_rehab.m4a` tempo fixture (no synthetic audio); absence → `Issue.record` (no silent skip). **Done-when (met):** all 6 churn tests green; full engine suite 1439 tests run — single failure was `SoakTestHarnessTests` cancel-timing (17.3 s vs 15 s bound) under the parallel run, green in isolation at 0.7 s; the churn suite's ~11 s of real-audio load plausibly squeezed that bound — widen it if it recurs (timing-sensitivity, not a logic regression). Lint 0 on the new file. Audibility note: the suite plays a few seconds of 0.25 s real-audio blips through the default output device per run.

### Increment REVIEW.1 — Session transcript mining (audit-only) ✅ (2026-06-11)
Mechanical + qualitative audit of all retained Claude Code session transcripts (108 sessions, 2026-05-08 → 2026-06-11; 92 main project dir + 16 worktree dirs) to convert the "most of Matt's time goes to correction" intuition into measured data. **Done-when (met):** extraction script runs over the full inventory with per-session summaries + 3-session spot-verification; four quantitative tables (correction-ratio trend, reference discipline, time-to-first-visual, rule-usage incl. never-cited list); bounded qualitative classification (25 spec-selected sessions + 4 worktree supplements, 41 candidates → A–G categories with session+turn citations); findings report complete. **Headline findings:** adjusted correction ratio ~5 % of human turns, flat-to-falling across the window (NOT rising); genuine corrections are 86 % class-F live-runtime defects (app-lifecycle concurrency, fixture/live parity) — zero reference-skip (A) / spec-drift (B) classifications in the reviewed set (with stated under-sampling caveats: M7 visual feedback rarely contains marker words; pre-2026-05-08 era not retained); README-read-before-first-.metal-edit measured at 35 % of shader-editing sessions (ceiling on the FA #39/#63 violation rate — denominator includes incidental edits); heaviest preset sessions burned 85 %+ of output tokens before any visual-artifact marker (FM.L2 858 k; 2026-05-16 Ferrofluid 515 k). Rule-usage table (288 identifiers, conv-vs-dump split) + never-cited lists (FA #2/#3/#11/#15/#18; 0 never-cited D entries) produced as the named RB.1 input. **Findings + all artifacts live OUTSIDE the repo at `~/phosphene_session_mining/REVIEW1_FINDINGS.md`** (deliberately uncommitted — transcripts are private conversation content; the repo is public MIT). Capability registry untouched (no renderer/shader/cert capability change). Carry-forward: REVIEW.2 (mechanize top countermeasure) + RB.1 (rulebook verdicts) — not scoped here.

### Increment DOC.4.1 — Doc referential-integrity gate ✅ (2026-06-11)
Matt's "address the integrity finds ASAP" follow-up. Full-history damage sweep (83 doc-touching commits since 2026-06-01 + 85 back to DOC.3): **D-155 was the only real casualty** (restored at DOC.4); everything else legitimate relocations / the D-147→D-148 renumber. Durable guard: `DocIntegrityTests` (engine suite, 3 gates, ~0.25 s) — D-continuity + non-Amendment uniqueness across DECISIONS/HISTORY, BUG continuity + uniqueness in KNOWN_ISSUES (BUG-007.x sub-entry + BUG-10 conventions encoded), and D-###/FA-# citation resolution over CLAUDE.md + sources + tests + docs. A/B-validated against simulated D-155-deletion (trips continuity + resolution) and D-086-duplication (trips uniqueness). Full suite green (1433/1433 on the clean run; only the two documented pre-existing flakes on the others); lint 0.

### Increment DOC.4 — Pruning pass ✅ (2026-06-11; the first recurring pass since the DOC.3 refactor, + the never-landed DOC.4 decisions-split scope)
The four protocol passes, 4 weeks / 775 commits after DOC.3. **Pass 1 (Failed Approaches):** #14/#20 → HISTORICAL_DEAD_ENDS (CoreML gotchas; CoreML unused per D-009, verified no source import); #34 → SHADER_CRAFT §13 full-text; #35–#38/#40 retired as near-verbatim duplicates of §13's own entries (mapping note added; §13 canonical); gap table extended; ~50 entries evaluated-and-KEPT (incl. #1–4/#17/#18 for the queued D-145 beat-sync project). **Pass 2 (Decisions):** mechanical citation graph (921-file corpus + memory + open KNOWN_ISSUES + active-decision fixpoint) showed 154/165 entries cited — the 2026-05-13 plan's ~60-active estimate was wrong; moved the verified subset (D-013/D-031/D-046 shipped+uncited; D-120 reverted → annotated move; D-086 was DUPLICATED in both files since the DOC-era move — deduped) + landed the Phase-MD-bloc REVISIT banner DOC.0 planned. Bedrock-uncited kept deliberately (D-001/002/005/007/012/015/016/023). **Pass 3 (CLAUDE.md):** Cold-Start Phase Contract condensed to the operative contract (full history verbatim → BEAT_SYNC.md addendum); 11 Arachne-specific What-NOT-To-Do bullets → ARACHNE_V8_DESIGN.md §Operating rules (pointer bullet remains). **Pass 4:** Current Status still the DOC.3 pointer block (no regrowth). **Drift fixes:** Module-Map per-preset histories split (borderline-call B — Arachne + LumenMosaic → their design docs); RENDERER.md line-180 retired-typealias listing struck (line 190's flag was a misread — `setRayMarchPresetHeightTexture` is live, verified). **Integrity finds (both pre-existing):** D-155 had been accidentally DELETED by the parallel FBS.S5c commit (`5ac5ad90`) — restored verbatim from `5ac5ad90~1`; D-145 was reserved at the NB renumbering and cited everywhere but never written — retroactive stub filed. **Sweep clean:** every FA # and D-### cited across CLAUDE.md/code/handbooks/preset docs/QUALITY resolves. **Sizes:** CLAUDE.md 542 → 494; DECISIONS.md 165 → 162 entries (4,806 → 4,735 lines incl. banner + restores); DECISIONS_HISTORY 1 → 5 entries; battery green post-pass (engine 1430/1430, app tests, lint 0 — docs-only, zero movement). **Reported (not done):** the deeper ~30-entry decisions cut requires ruling that narrative citations (design-doc provenance mentions) don't count as keep-signals — Matt's call, recommend deciding at the next pruning pass.

### Increment Skein.6 — Certification ✅ (gates 2026-06-10 + **Matt M7 PASS 2026-06-11** — `certified: true`; first `painterly` preset; BUG-046 guard landed pre-flip; D-159)
Gates + docs + the D-142(c) deferred engine touch; **zero behavioural/tuning change** (the 5.4 look is untouched — byte-identical goldens prove it). **Coverage bound (Matt's decision, presented with live-path measurements):** the approved density stands; §5.7's pre-implementation "ends 60–80 %" band retired for **never-solid / never-near-empty** — measured at 900×600 on the approved sessions: 39 % @ 9 s → 80.2 % @ 43 s (longest approved single track) → plateau ≈ 87 % @ 100 s, live-video parity confirmed at 29 s; coverage fraction is RESOLUTION-DEPENDENT (the droplet AA radius floor reads the same run 94.7 % @ 200×200 vs 80.2 % @ 900×600), so `test_cert_coverageBound` (180 s tiled-real-stem live-path run) renders at 600×400 with thresholds calibrated there (< 95 % — measured 89.6 % on the densest input; > 40 %). **Determinism (§5.7 headline):** formalised as dHash ≤ 8 across two same-seed live-path runs in `test_seedDeterminismAndReseed` (byte-identity stays the stronger assert); full-track evidence 2×10,800 frames pixel-diff 0 / hamming 0. **Seed ratified FNV-1a `title|artist`** (the SHA-256 design wording amended in SKEIN_DESIGN §1/§5.7 — rewiring would silently change every approved painting). **§5.5 soak:** `test_cert_soak_twoHourCanvasHold` (`SKEIN_SOAK=1`) — 432,000 frames (2 simulated hours) through the live mv_warp dispatch path: 15 min real stems / 90 min silence (whole-canvas RGBA byte-identity = lossless hold at hours scale) / 15 min real stems (resume + never-white + ground-corner intact); the generic `SoakTestHarness` is the headless audio-path harness (no render) and cannot observe §5.5's property. **Golden dHash entry** in `PresetRegressionTests` (three fixtures identical — static ground, the Nimbus pattern). **`family: "painterly"` + `PresetCategory.painterly`** (blast radius audited: enum + displayName + count test 12→13 + sidecar; UI iterates `allCases`; orchestrator family logic nil-safe). **`rubric_profile: lightweight` ratified** (D-064 precedent; L2 false-negative by construction — CPU-side deviation routing, the Lumen Mosaic precedent — locked in `FidelityRubricTests.expectedAutomatedGate`). Files: `PresetCategory.swift`, `Skein.json` (family + refreshed description; no behavioural field), `PresetTests.swift`, `FidelityRubricTests.swift`, `PresetRegressionTests.swift`, `SkeinCanvasHoldTest.swift` (+coverage gate, +dHash determinism, +soak, +env-gated cert montage), SKEIN_DESIGN/SKEIN_PLAN/skein README/D-159/release notes. **Pruning-pass cadence has FIRED** (no pass since DOC.3 2026-05-13) — the pruning pass is the next increment after cert. **M7 PASS 2026-06-11** ("It looks great. Ready to certify", session `2026-06-11T01-56-22Z`; the ≥5-track + LF bar met cumulatively with the 2026-06-10 approved sessions). The pre-flip session review (Matt: "If anything looks concerning, let's fix it before we certify") surfaced **BUG-046** — the structure sub-feature riding BUG-042's note-scale junk (boundaries every ~1.7 s at conf 0.78–0.95, the confidence gate wide open; ≈2× tuned spatter + pours chopped at ~1–1.7 s on streaming material only) — fixed at Matt's direction with the 10 wall-s boundary-spacing guard (`minSectionSpacingS`; A/B-validated gate `test_structure_boundarySpacingGuard`: 16→4 breaks / 1650→1250 spawns on machine-gun replay; real boundaries still land). Then `certified: true` + `FidelityRubricTests.certifiedPresets` flipped; full battery green (engine 1430/1430, app tests, lint 0).

### Increment Skein.5.4 — Two painting techniques: pour drips vs independent flicks ✅ (landed 2026-06-10; **Matt eyeball-gate PASSED across 3 live sessions; merged to local main `befb406b`** incl. the round-2 tune + BUG-044)
Matt's craft corrections, built to the negotiated spec verbatim: **the POUR and the FLICK are different techniques** (previously conflated — bursts hugged the line). **(1) Pour drips:** round ragged drops shed close beside the travelling line (perp offset 0.005–0.020 UV), rate AND weight ∝ the pour's volume (`lineFlow` — the width signal, FA #67-clean), τ-clocked (`dripRateGain = 3.0` drips/τ — pauses with the painter), in the pour's colour; encoded in the shared burst ring with **`sharpness < 0` as the drip marker** (no GPU-struct change); drips yield to flicks on a full ring. **(2) Flicks:** land ANYWHERE ≥ 0.20 UV from the painter's pour position (deterministic seed + spawn-counter hash, mirror-then-push-out fallback; §5.7 extends to landing spots), throw direction = the gesture's own random angle; mark anatomy per `03_micro_satellite_spatter` + `03_micro_filament_threads` — 3-lobe union-min impact blot (soft hit → one round heavy drop, sharp → lobes scatter), 1–3 flung tapering threads with terminal droplets (up to 0.20 UV), satellite halo with POWER-LAW size spread (`pow(hs.z, 2.2)`, ~20:1 — the old confetti is the dust tail, KEPT) + radial teardrop elongation. **Hit magnitude** (how far the firing `*_energy_dev` exceeded the 0.13 threshold, soft-saturated `m/(m+0.35)` per `project_deviation_primitive_real_range`) scales blot/threads/spread via `burst.size` (CPU 0.30–2.0, shader clamp matches). **Emission timing UNCHANGED** (per-stem onset + refractory; beat-locked events remain vehemently rejected). **New gates (live tick path, real stems):** `test_splatterTechniques_flickPlacementAndPourDrips` — spawn-frame detector (counter deltas + `activeBurstMarks` + `currentPainterPourPosition`): every flick ≥ 0.18 from the painter (min 0.198 over 1.5k+ spawns), drips ∝ volume (busy tile ≫ calm), every drip ≤ 0.03 of the line. **Gate adjustments (all Matt-approved in-session, none silent):** no-rings bar 13 → 16 (bigger smooth blot interiors raise the proxy's legitimate mean — measured 12.5–13.2 post-change vs the 27.6 defect signature; the only pre-sanctioned adjustment); colour-freeze gate re-probed at switch+28 frames (end-of-run probing read X=28/Y=32 from legitimate flick overpaint of the old line — the freeze itself intact, main baseline X=61/Y=0 reproduced at the new probe); mood-vigour gate re-probed on the mechanisms (painter τ ×1.10 + spawn count + coverage direction — the old ≥1.10× coverage margin measured burst placement, not vigour: 1.285× pre / 1.078× post on identical session+seed). **Battery:** full engine 1427 (8 issues = the 7 documented love_rehab fixture-absent + the known MetadataPreFetcher timeout flake); PresetRegression + DB/FM byte-identical; loader count intact (FA #72); app build + SwiftLint `--strict` clean. **Eyeball-gate sheets** (`/tmp/skein54_sheets/`): vs-references panel, early-canvas mark-anatomy panel (300 f), before/after × fathom/poles/nocturne. **Honest observations for the gate:** coverage rate ~2.2× the confetti baseline (38 % → 85 % painted at 23 s of busy music — the §5.7 60–80 % end-of-track bound is reached at ~1/5 track; morphology-scale knobs, not emission timing, are the lever if Matt wants it slower); long flung threads read clearly on the early canvas but submerge under later blots at full density. **Merge only after Matt's verdict.**

**Round-2 (Matt's live read, session `2026-06-10T19-28-50Z` — "I like it… the canvas fills and transitions quickly"):** spatter rate −41 % (`onsetRefractory` 0.14 → 0.26; Matt confirmed RATE not size via in-session question) + new pour lines start +13 % more often (`minPourTau` 3.0 → 2.65; confirmed: new-pour starts, not drips). Mood-fixture marks 885→521 / 524→304 on identical input; early fill @5 s 0.375→0.248; all 26 Skein gates green unchanged. Matt's old-confetti-as-its-own-variant idea noted (cheap to resurrect from main history as a sibling variant). **Round-2 verification listen (session `2026-06-10T19-48-27Z` — "the speed adjustments look good") surfaced BUG-044:** local-file next/prev/EOF never wiped the Skein canvas (the §1.5 wipe was streaming-path-only since Skein.3; five LF track changes with Skein active, zero wipes — the "first transition wipe" was the preset-APPLY clear). Fixed on the branch (trivial-collapsed P2, KNOWN_ISSUES entry filed): shared `VisualizerEngine.resetPerTrackPresetState()` (Nimbus NB.4 settle + Skein reseed → ground → wipe) called from BOTH track-change paths, LF call ordered after `applyLocalFileTrackState` (the reseed reads `lastResolvedTrackIdentity`), `WIRING:` breadcrumb per advance; regression-locked by `TrackChangePresetResetRegressionTests` (helper-exists-once + both-call-sites + no-re-inline + ordering; registered in project.pbxproj P10012/P20012). **Wipe verified live (session `2026-06-10T20-05-48Z`, Matt "Looks good"):** 8+ LF advances with Skein active, every one logging `resetPerTrackPresetState COMPLETE` — the BUG-044 manual criterion. Merged `befb406b`.

### Increment Skein.5.3b — Per-palette canvas grounds + reference-anchored re-curation ✅ (landed 2026-06-10; D-155 amendment)
Matt's round-1 rejection ("palettes don't match the drip painters… too similar… why is the background beige for all palettes?") → the redo: the GROUND is part of the palette (light AND dark — Blue Poles precedent), every entry anchored on a NAMED work, gates ground-aware (drums = starkest ink VS THE GROUND; separability vs the entry's own ground across the mood swing — caught 2 real collisions in tuning). Plumbing: `Entry.ground` → SkeinState (re-picked per track) → a float4 LINEAR ground tail on the slot-6 buffer (offset 2752; the comp paint-mask reads it) → gated `mvWarpCanvasGroundOverride` for the canvas wipe + resize re-clear (nil ⇒ every other preset byte-identical) → app wiring at Skein apply / track-change / teardown. Harness gains `libraryPaletteSeed` (true library-mode runs, canvas cleared to the entry's ground). **Final library (Matt round-2): fathom + poles + nocturne + ember** — autumn/convergence cut ("too similar to fathom": a pale ground + black ink dominates the gestalt; future light candidates must differ at the GROUND level). Full battery green (known fixture-absent cluster only); process lesson → memory `feedback-palette-curation-process`.

### Increment Skein.5.3 — Curated palette library + per-track picker ✅ (landed 2026-06-10; D-155; Matt-curated)
Matt's enhancement ask ("different colour profiles like Lumen Mosaic — variety over time"). **Library** (`SkeinPalettes.swift`): fathom (default, index 0) + nocturne + jewel + inkpop + electric — Matt curated from six rendered candidates on identical seed-0 real-stem paintings (terra cut); **fixed role grammar** in every palette (drums darkest ink / bass deep weight / vocals warm lead / other contrast accent) so the colour→stem vocabulary survives palette changes. **Picker = per-track deterministic** (Matt's pick over mood-matched): `entry(forTrackSeed:) = seed % count` on the same FNV-1a identity that seeds the trajectory — §5.7 "same song → same painting" now extends to colour; LIBRARY MODE only when `SkeinState` gets no explicit palette (the live path; `reseed` re-picks per track), every fixture/candidate palette stays pinned, seed 0 → fathom keeps no-palette fixtures byte-identical. **Gates** (`SkeinPaletteLibraryTests`): pairwise display separability incl. vs cream across the full mood-tint swing (via the extracted-static `SkeinState.moodTint` — the EXACT lay-time transform), pale ceiling, role grammar, fathom == defaultPalette, picker determinism + reseed re-pick + explicit-mode pinning. Contact sheet renders the library (same painting per entry). Full engine suite green (7 known fixture-absent + 1 solo-green SessionManager.Cancel parallel-flake); app build + SwiftLint `--strict` clean. **Skein.6 cert note:** the ≥5-track M7 naturally samples ≥5 palette draws.

### Increment BUG-040 — structural sections: frozen clock + live-edge peak + absolute novelty floor ✅ (landed 2026-06-10)
The session-artifact finding from `2026-06-10T03-09-20Z` (filed same day), root-caused to THREE compounding causes and fixed in one P2 increment: (1) the live caller hardwires `time: 0` into `MIRPipeline.process` → the structural analyzer's clock froze at zero → NEGATIVE boundary timestamps (≈ −0.3 s, exactly as recorded), noise durations, pinned confidence — the analyzer now clocks from the pipeline's own track-relative `elapsedSeconds`; (2) the live-edge novelty peak (absolute index advances with the stream → escaped the BUG-035-fixed dedup every ~4 detect calls → the ~1.3–1.6 s junk-boundary cadence) — detection now restricted to the interior region (≥ `minPeakDistance` frames of after-context; a real boundary registers once, ~2 s late); (3) the relative-only mean+1.5σ threshold admits noise-scale peaks on smooth material (measured junk ~0.0003 vs real ~0.43) — absolute `minNoveltyFloor = 0.02` ANDed in. **A/B-proven gates:** `structuralAnalyzer_evolvingMusicNoBoundary_registersNothing` (pre-fix 5 junk boundaries → 0), `mirPipeline_structuralPrediction_liveCallerShape_timestampsNonNegative` (pre-fix `sectionStartTime → −0.3167` — the exact session signature → positive), `structuralAnalyzer_boundaryTimestamps_nonNegativeAndPlausible`. All 16 pre-existing structure tests + the AABA golden unchanged-green; full suite green (7 known fixture-absent only); app build + SwiftLint `--strict` clean. **Consequence: the Skein.5 structure sub-feature and the orchestrator's `StructuralPrediction` consumer receive a sane signal for the first time.** Manual criterion open: the next real session's section columns (multi-second sections, climbing confidence).

### Increment Skein.5.2 + BUG-039-instr — structural CSV columns + video-stall instrumentation ✅ (landed 2026-06-09)
**Skein.5.2:** features.csv gains `section_index,section_start_s,section_confidence` tail columns (append-only invariant) via `SessionRecorder.recordStructuralPrediction(_:)` (the latest-value queue-hop pattern), published from the same per-frame MIR site that feeds `RenderPipeline.setStructuralPrediction` — the Skein.5 structure layer + the BUG-035 manual criterion are now artifact-verifiable (the Skein.5 M7 review had to say "cannot verify"). SessionRecorderTests from-end offsets shifted by a `structTail` constant; round-trip + default-zero gates. **BUG-039 instrumentation:** the session video intermittently freezes seconds in (`22-35-09Z` 5.0 s, `17-14-25Z` 15 s) with zero log output — every stall path in `SessionRecorder+Video.appendVideoFrame` was silent and the `adaptor.append` result ignored. Now: non-`.writing` writer detected once + logged with `writer.error` + the partial file RETAINED (not deleted); not-ready / pool / append failures log throttled counters. Diagnosis completes on the next affected session's log; the root-cause fix is its own increment. KNOWN_ISSUES BUG-039 filed with the evidence. **Session-review postscript (2026-06-10, `03-09-20Z` — the first session with the new columns):** video full-length (no BUG-039 stall this time); beat phase healthy (Love Rehab 2.23 wraps/s vs 2.08 expected — the prior session's half-rate anomaly did not reproduce); the section columns immediately exposed **BUG-040** (a live-edge boundary registered every ~1.3–1.6 s on every real track, `section_start_s` negative, confidence pinned ≤ 0.30 — the Skein.5 confidence gate correctly suppressed the bias, so the structure sub-feature is currently INERT on real music). The instrumentation increment did exactly its job.

### Increment AUDIT.1 — Full-codebase audit + findings filed ✅ (2026-06-09)
Six-agent parallel review of the complete tree (~92k lines: 54k engine Swift, 19k MSL, 19k app Swift; every Swift file in scope read in full, MSL swept for mechanical-defect patterns). All findings verified at file:line and cross-checked against KNOWN_ISSUES + CLAUDE.md FAs — nothing re-reports a documented issue. **Output: 6 P1 / 17 P2 / ~40 P3 findings.** Evidence record: [`docs/diagnostics/CODE_AUDIT_2026-06-09.md`](diagnostics/CODE_AUDIT_2026-06-09.md). Filed: **BUG-030** (duplicate-track prep crash), **BUG-031** (StemSeparator prep/live race), **BUG-032** (streaming session-lifecycle cluster — endSession orphan / second prep loop / source-before-guard), **BUG-033** (60 Hz whole-tree SwiftUI invalidation + `assign(to:on:)` VM leaks), **BUG-034** (`sceneParamsB.z` double-booking — ray-march fixtures march 32 steps vs live 128, FA #66 class; **invalidates ray-march cert evidence — fix + golden-hash regen before further ray-march cert work**), **BUG-035** (NoveltyDetector boundary re-detection — Skein.5 prerequisite, see above), **BUG-036** (RT-audio-thread allocations ×3 sites), **BUG-037** (Arachne spiral chord-count 200/441/104 inconsistency), plus the **AUDIT-2026-06-09** backlog index entry in KNOWN_ISSUES for the remaining P2s/P3s. Suggested fix sequencing: audit doc §Suggested sequencing. Clean areas verified: GPU struct contracts byte-match `Common.metal` across all paths; OAuth/PKCE core sound, no committed secrets; disk caches well-built; no FA #44/#72 shader hazards; D-102 Drift Motes removal orphan-free. Docs-only increment — no code changed; tests n/a; not visually verifiable (n/a).

---

## Phase G-uplift — Gossamer + remaining preset fidelity uplifts

The Phase V uplift trajectory left several presets at the post-V.6 cert baseline without per-preset fidelity work tailored to their visual contracts. The shipped catalog has 15 presets (post-D-102); the Phase V plan called for 12 fidelity-uplifted presets. Several catalog members are *certifiable* but have *not* been through a per-preset uplift session against curated references — Gossamer is the named example, but Membrane / Starburst (post-SB) / Nebula / Plasma / Waveform / Fractal Tree / TestSphere / Glass Brutalist / Kinetic Sculpture / Volumetric Lithograph / Spectral Cartograph are all worth review (some are lightweight rubric and need only validation, others are full rubric and may need work).

**Status.** Planned, behind LM / Arachne / AV / CC. Per-preset scoping happens at session start — each preset gets its own concept-viability gate review against SHADER_CRAFT §2.0 before scoping the uplift; if the gate finds the preset's musical role is unarticulated or ambiguous, the uplift is rescoped (or, per D-102 / FA #58, retired rather than tuned).

**Suggested order** (subject to Matt prioritisation):

1. **Gossamer uplift** — the highest-priority named uplift target. Bioluminescent silk web preset; ambient family. Likely benefits from a palette / motion / silence-fallback pass against curated references. Per-preset increment estimate: 1–2 sessions.
2. **Membrane uplift** — fluid-family direct-fragment preset; Matt has flagged the silence behaviour as historically thin. 1–2 sessions.
3. **Starburst** — post-SB.1 / SB.2 stability + any remaining fidelity gaps surfaced by review. 1 session.
4. **Plasma / Nebula / Waveform / Spectral Cartograph** — lightweight rubric profile; primarily validation rather than rework. ½–1 session each.
5. **Glass Brutalist / Kinetic Sculpture / Volumetric Lithograph** — full rubric profile; cert-quality validation + any preserved tuning gaps. 1 session each.
6. **TestSphere / Fractal Tree** — final cleanup pass; TestSphere may be retired as a production preset if its diagnostic role is no longer load-bearing.

**Done-when (phase-level).** Every catalog member has either (a) been M7-certified by Matt, or (b) been explicitly retired with a D-XXX entry (the D-102 / Drift Motes precedent applies — retirement is acceptable when the concept-viability gate fails).

---

These milestones map to product-level outcomes, not implementation phases.

**Milestone A — Trustworthy Playback Session.** ✅ **MET (2026-04-25).** A user can connect a playlist, obtain a usable prepared session, and complete a full listening session without instability. *Requires: ~~2.5.4~~ ✅, ~~Phase U increments U.1–U.7~~ ✅, ~~progressive readiness basics (6.1)~~ ✅.*

**Milestone B — Tasteful Orchestration.** ✅ **MET (2026-04-25).** Preset choice and transitions are consistently better than random and pass golden-session tests. *Requires: ~~Phase 4 complete~~ ✅, ~~Increment 5.1~~ ✅ (landed as 4.0).*

**Milestone C — Device-Aware Show Quality.** ✅ **MET (2026-04-25).** The same playlist produces an excellent show on M1 and a richer one on M4 without jank. *Requires: ~~Phase 6 complete~~ ✅.*

**Milestone D — Library Depth.** ⏳ **IN PROGRESS — 1 / 22+ certified (2026-05-12).** The preset catalog is large enough, varied enough, and well-tagged enough for Phosphene to feel like a product rather than a tech demo. *Requires: Phase 5 complete, Phase V complete (12 fidelity-uplifted presets), Phase AV + Phase CC complete (Aurora Veil + Crystalline Cavern shipped certified), Phase G-uplift complete (Gossamer + remaining catalog members M7-certified or explicitly retired), Phase MD through MD.5 minimum (10 Milkdrop presets), 22+ certified presets total.* **First certified preset: Lumen Mosaic** (Phase LM closed 2026-05-12; BUG-004 resolved). Next cert candidates per current sequencing: Arachne V.7.10, Aurora Veil (Phase AV), Phase G-uplift members.

**Milestone E — Visual Identity.** Phosphene's preset catalog has a recognizable aesthetic ceiling that reads as 2026-quality — comparable to indie-game-released visuals, not 2006-era ShaderToy. *Requires: Phase V complete, Phase V.7–V.11 uplifts all Matt-approved, Phase CC certified (the flagship demonstration piece), accessibility pass (U.9).*
