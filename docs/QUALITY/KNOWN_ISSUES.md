# Phosphene — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

## Open Index

*(RECON.2 reconciliation pass, 2026-08-03 — the 2026-08-03 production audit found this
index disagreeing with its own entry bodies. Three entries left §Open: **BUG-080**
and **BUG-071** were stamped resolved/closed *in place* while still indexed as open,
and **BUG-041** closed as stale on Matt's call. One entry was added: **BUG-084**,
promoted out of a BUG-041 inline aside so it would survive that closure. **BUG-060
moved the other way** — Matt reported the hang has recurred, which falsifies its
"likely resolved" status. Everything in this table is now open work; nothing in it
is already fixed.)*

*(Merge note, RECON.9, 2026-08-03 — `origin/main` moved 12 commits while this pass was
in flight and landed three defects of its own. **BUG-081** (app beachball, genuinely open)
joins the table below; **BUG-082** and **BUG-083** were already resolved when they landed,
so they went straight to §Resolved under the convention above rather than being indexed as
open. That parallel session hit the same number collision from the other side — its notes
record a 080 → 082 renumber — and this branch renumbered its own new entry to **BUG-084**
for the same reason. BUG-081 and BUG-060 are the same hang class; they are cross-linked.)*

*(Progress pass, 2026-08-07 — **two entries left §Open, both fully resolved**: **BUG-079**
(release-config test build; the DBN.2 budget it was hiding measures 17.9 ms in release against a
50 ms plan figure) and **BUG-078** (the `AVAudioPlayerNode` teardown trap — root-caused as a
concurrent-`start()` overwrite, fixed in `f68efb67`/PR #62, closed on Matt's live local-file
session `2026-08-07T19-10-25Z`). Nothing else changed state. The working order for what remains
is in [`ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md) §Immediate Next Increments item 5 —
**sorted by whether the work is doable, not by severity label**, because most of the remaining
P1/P2 headline items are blocked on an artifact that only a live failure can produce and cost
nothing while they wait. The one method note worth carrying: BUG-078 sat for a week on "nobody
has captured the trap" while 25 matching `.ips` reports sat in
`~/Library/Logs/DiagnosticReports/`. **Before filing another sighting of an intermittent crash,
read the crash reports already on disk.**)*

| ID | Sev | Domain | One-liner |
|---|---|---|---|
| BUG-099 | P2 · open, product decision needed | preset.witchlight / performance | **Witchlight reaches ~30 fps at 3840×2160 after BUG-098's 8.2× fix, against 60 fps at 1080p.** `CLAUDE.md` promises 60 fps **at 1080p**, which is met with headroom, so this is a decision about what the product promises at fullscreen rather than a defect against the stated target. The remaining 4K cost is **balanced** — bloom 5.4 ms, three star layers 4.9 ms, beads/particles/feedback 6.0 ms — so there is no further micro-optimisation available that does not change what the preset looks like. **Two routes, both visible to the user:** drop or cheapen a star layer (the three-layer parallax is a documented WL.2 feature and the depth read would go with it), or drive `setDirectRenderScale` below 1.0 as Nimbus already does at 0.5× (trades crispness in stars and beads for ~4× headroom, and the machinery exists). ⚠ Note Witchlight is the only preset measured that is anywhere near the budget; the next most expensive at 4K is Volumetric Lithograph at 16.44 ms. Matt's call |
| BUG-098 | **P1** · **FIXED 2026-08-19 (PERF.2 + PERF.3), 8.2× measured. ✅ 1080p target met with margin; ⚠ 4K ≈ 30 fps, still 2× over** | preset.witchlight / performance | **Witchlight's sky ran ~64 Perlin evaluations per pixel across the whole frame — most of them multiplied by zero, the rest for detail that never reached the image.** Measured live at 4K on `2026-08-19T14-25-55Z`: **273.88 ms median GPU, 11.2 fps, 16× over budget**, while six other presets in the same session held 59–60 fps (Arachne 3.27 ms … Volumetric Lithograph 16.44 ms) — 84× Arachne, so a defect and not a cost. Two causes, both fixed: **(a)** `witchlight_bloom` computed `fbm8` + `warped_fbm` for EVERY pixel then multiplied by `body = exp(-r*r*70)`, a lobe a sixth of the frame wide — ~530 M Perlin evaluations per 4K frame to produce black; fixed with an early return at `body < 1e-3` (below an 8-bit LSB: 2.4e-4 vs 3.9e-3), **151.2 → 31.8 ms**, output identical to every printed digit. **(b)** the surviving noise was still 64 evaluations for what the code's own comment calls *"low-frequency structure only … one soft mass rather than cloud detail"*; replaced with `fbm4` + a one-level `fbm4` warp (**20 evaluations**), the same remedy `VolumetricLithograph.metal:634` applies to the same function for the same reason — **31.8 → 18.4 ms**, sky luma 9.22 → 9.23 and lit share 2.49 % → 2.51 %. **Total 151.2 → 18.4 ms (8.2×).** Extrapolated to production: **~8 ms at 1800×1200 (60 fps with headroom, target met)** and **~33 ms at 3840×2160 (≈30 fps, still 2× over)**. ⚠ The residual is now balanced — bloom 5.4 ms, stars 4.9 ms, beads/particles/feedback 6.0 ms — so there is no further shader win that does not change the look; closing the 4K gap needs a product decision (fewer star layers, or `setDirectRenderScale` as Nimbus already does at 0.5×), tracked as **BUG-099** |
| BUG-097 | **P1** · **FIXED 2026-08-18, validated on three real sessions + a new gate** | preset.witchlight / frame-rate-coupling | **A frame-time clamp meant for physics stability was corrupting a MUSICAL measurement, and Witchlight dropped most of its off-beat accents on exactly the sessions where the frame rate was worst.** `WitchlightPath.advance` clamps `dt` to 1/30 s so an integrator cannot take a wild step after a stall — correct for the integrators, wrong for the four quantities that measure how long something LASTED: `timeSinceWrap` (→ `barPeriod`), `gridSilentFor`, and the two refractories. WL.9 gates the off-beat pulse on `barPeriod / beatsPerBar >= 0.55 s`, so under load a 94 BPM bar measured **1.80 s against a true 2.55 s** and the pulse was never emitted. On `2026-08-18T16-10-38Z` — 48.8 % of frames over the cap, 38 % of elapsed time discarded — the preset fired **6 off-beat pulses in 110 s** where the meter implies ~130. **Fixed** by splitting `clockDt` (real elapsed time) from `dt` (the clamped integrator step). Validated on three real sessions: 6 → **105**, 50 → **149**, and the already-healthy session 79 → **83**, i.e. every one lands at the designed ~3:1 and the healthy case barely moves — the signature of a fix rather than a re-tune. Flare alignment on the worst session also rose 36 % → 54 % within 10 % of a beat. ⚠ It was invisible to the whole suite because every committed fixture replays at a steady ~60 Hz and never approaches the cap; `offBeatPulseSurvivesHeavyFrames` now drives at 50 ms frames and **was confirmed to fail (0 pulses) on the pre-fix code** |
| BUG-095 | P1 · **FIXED 2026-08-17; M7 CONFIRMED LIVE 2026-08-18, twice** (WL.13 — Witchlight keeps its second pole, locally) | dsp.tonal / cross-preset-regression | **A source-side EMA in `TonalAnalyzer` outlived the reason it was added, and all four consumers were smoothing an already-smoothed angle — cutting Witchlight's hero driver's travel by up to 4×.** Removing it was correct for Nacre, Cymatic and Fractal Tree (Matt on Nacre, 2026-08-18: *"looks fine"*) but wrong for Witchlight, which had been tuned AND certified against the cascade. `WitchlightTuning.phasePreTau` restores that second pole locally. **Live-confirmed on `2026-08-18T16-10-38Z`: Matt *"Looks good overall"*, stroke measured at 42 heading turns against 74 pre-fix and 50 on the certified build.** ⚠ Note his sign-off covers the STROKE and the ribbon, not the beat accents — that session was the worst BUG-097 case measured (6 off-beat pulses in 110 s), so the accents were largely absent from what he judged |
| BUG-096 | **RESOLVED 2026-08-18 (FTR.31) — and the original diagnosis was WRONG** | dsp.beat / calibration | **`BeatHold` was never the problem: it was being fed a staircase, and then fed a phase whose own rate estimator was 4× too fast.** Filed claiming the hold's trust gate (8 intervals within 20 % spread) was too strict for a 14.6 Hz phase. What FTR.31 measured instead: the hold engages **instantly on a clean synthetic clock** (tempo 0.6375 s, `isStepping` true), so the gate is fine. On real captures it reported 0/3000 frames because `DancePhase`'s self-rate measured **dφ/dt per RENDER frame** on a phase that only changes on analysis updates — a 0.109 jump in one 17 ms frame reads as **6.5 cycles/s on a 1.57 Hz beat**. The lock still pulled the phase onto the beat (so the gait measured fine, in-step +0.799) but it free-ran 4× fast between corrections and crossed zero far too often; anything counting those crossings as beats saw ~0.15 s intervals, below `periodRange`'s 0.25 s floor, and discarded every one. **Fix: rate = EMA(advance)/EMA(elapsed) — a frame with no update contributes 0 to the numerator and its dt to the denominator, which is what a staircase requires.** Same capture, after: **2650/3000 frames (88 %)** at 0.2 % tempo error. ⚠ **Two claims made against this entry are retracted:** that the FTR.10 beat-step "has been engaging on ~1 frame in 8" (it was engaging on ~none, for a reason that is now fixed), and that the tolerance needed relaxing (it did not). Detail below |
| BUG-094 | P2 · **root-caused + probe-verified 2026-08-17; FIX NOT APPLIED — changes a certified preset's look, Matt's call** | preset.meniscus / primitive-contract | **Meniscus reads `arousal` as if it were 0…1 when its contract is −1…+1, discarding the entire calm half of the primitive.** `MeniscusStemDrops.swift:219` computes the MEN.4a musical-arc lift as `max(0, min(features.arousal, 1))`, which clamps rather than maps — and `MeniscusCamera.swift:106` repeats it for the camera envelope, so the preset discards the calm half twice. On calm material that zeroes the lift for a large fraction of the track — measured **35 % of frames on `so_what`** (arousal −0.393…+0.519) — collapsing `arcEnvelope`, then `density`, until the backbeat-gated **vocals region places 0 drops across the whole track**. Masked until now because MEN.4a was calibrated on one capture where arousal never went negative (its own code comment records the range as *0.19 → 0.52 → 0.27*), and because the committed QG.1 fixtures happen to bottom out at −0.077. It surfaced only when BUG-090's regenerated fixtures carried today's mood output. **Probe-verified:** replacing the clamp with a map (`(clamp(arousal,−1,1)+1)/2`) takes so_what's vocals region **0 → 24 drops** and turns the whole Meniscus suite green (14 tests / 9 suites). Probe reverted, not committed. **Not applied because it changes what a CERTIFIED preset looks like** — more drops on calm material — which is a product call, not a test fix. Needs Matt's pick and an M7. ⚠ **Transferable:** any consumer of a bipolar primitive that writes `max(0, x)` is silently discarding half its range. Worth grepping the other presets |
| BUG-093 | **P1** · open, evidence-only | preset.fidelity | **Fractal Tree's geometry DOES move with the music by every measure available, and Matt still reports no clear connection — after nine live rejections.** Measured after 12 s on `2026-08-17T20-01-01Z`: `reach` spans 0.680, the size term 0.360, visible **trunk length 0.151 clip space ≈ 164 px of 1080**, branch spread 20°→34°, and the FTR.25 tip spark fires 0.37/s on events. So this is NOT a dead-channel or dead-route problem, and BUG-092 (which briefly claimed it was) is retracted on that point. **What IS established about the signals it tracks:** `spectral_surge`, which drives size, scores **0.25× event-versus-random specificity — it moves DOWN when the ear notices something** (FTR15 §9); `spectral_section_ratio`, which drives growth, is a slow density RANK, not a loudness or arrangement reading; `spectral_flux`, which drives the spread, is broadband change that fires as often between events as on them (1.50×). **The tree therefore moves a great deal while tracking three quantities that do not correspond to what a listener notices** — that is the standing hypothesis and it is consistent with every rejection in FTR.15→FTR.27, including the two where a more event-aligned driver was tried and rejected for its motion cost (FTR.24: 10.7× peak velocity). ⚠ **Do not open another tuning increment against this.** The next move needs a changed premise about WHICH quantity the tree should follow, and that is a product decision. Detail: `docs/diagnostics/FTR15_SIZE_READS_LEVEL_2026-08-13.md` §§8–11 |
| BUG-092 | P3 · **RE-SCOPED 2026-08-17, hours after filing — the original headline was WRONG** | preset.fidelity / documentation-drift | **Fractal Tree's declared `growth` route reads `arousal`, and `arousal` is INERT: it loses its own `max()` on 100 % of frames.** The shader computes `reach = max(0.10 · arousalReach, fullness) · musicGate`; measured after 12 s on `2026-08-17T20-01-01Z`, `0.10 · arousalReach` spans **0.032** against `fullness`'s **0.646** and never wins. So the sidecar's `growth ← arousal` is a manifest entry with no visible effect — the FTR.2 false-route class, which QG.1 cannot catch because `arousal` does *vary* (just at 3 % of the competing term's amplitude). `arousal` is separately near-constant within a track (mean 0.446…0.475, sd 0.048…0.069, same 0.26…0.51 bounds on five captures across three builds), which is fine for a MOOD classifier and is why nobody noticed. ⚠ **WHAT THIS ENTRY ORIGINALLY CLAIMED AND GOT WRONG:** that arousal was the preset's primary growth driver and that its flatness explained nine live rejections of "no clear connection". False. I measured the primitive's flatness and never checked its COEFFICIENT. Growth's real driver is `spectral_section_ratio` (span 0.646) and the visible trunk length swings **0.151 clip space ≈ 164 px of 1080** after 12 s — the geometry moves across two thirds of its range. **The connection complaint remains UNEXPLAINED**; see BUG-093. Fix here is small and cosmetic: either delete the inert arousal term and the route, or give it a coefficient that can compete — Matt's call, since one of those changes what he sees. Detail below |
| BUG-091 | **P1** · instrumentation landed 2026-08-17; awaiting one reproduction | app.session / pipeline-wiring | **A single local file is selected, preparation succeeds, and NO PLAYBACK EVER STARTS — the session runs with every audio field exactly 0.0.** Matt, 2026-08-17. Measured on `2026-08-17T17-19-19Z`: 1262 frames over 84 s of render clock, and `playback_time_s` / `track_elapsed_s` / `accumulatedAudioTime` / `bass` / `mid` / `treble` / `pulse_amp01` / `beatPhase01` each hold **exactly one distinct value, 0.0**, for the whole session. Preparation is healthy — stem-cache hit, BeatGrid installed (94.1 BPM, 47 beats), plan built. **The discriminator is a diff against the working local-file session 1.5 h earlier (`16-19-13Z`, same file, same OS build):** the working run logs `WIRING: provider.start INSTANCE` and an AVAudioEngine node tap (`TAP_BUFFER: requested=1024 delivered=4410 → 10 Hz`) and NO process tap; the failed run has an identical preparation sequence with `provider.start` **absent**, an unexplained 8 s gap, and then `TAP: startCapture → createProcessTap` — the SYSTEM-AUDIO path — installed twice. `resetStemPipeline caller=other` has exactly one call site (`handleLocalFileReady`), so that function ran and cleared all three of its guards, then never reached the router start. **Root cause NOT asserted** (BUG-061's rule): the strongest candidate is the `catch` around `audioRouter.start(mode:.localFilePlayback)`, which logs to `os_log` only and calls `endSession()` → `currentSource = nil` → `startAudio()`'s LF.4 guard misses → the tap is installed and `stopInternal()` tears the provider down. **Unconfirmable from the artifacts: the app's `lfLogger` output is not retained** (`log show --predicate 'subsystem == "com.phosphene.app"'` over the window returns zero lines), which is itself the reason an 84 s silent session left no trace of its cause. Instrumentation for exactly that is now in (see below). Detail below |
| BUG-090 | P2 · **resolved 2026-08-17 — cause (a), and it concealed a real regression** | test-infrastructure / fixture-drift | **Regenerating the QG.1 route-coverage fixtures from their own committed audio produces different values on EVERY row, and reds three gates belonging to other presets — one of them CERTIFIED.** `FixtureSessionCaptureGenerator` still runs clean (18 s, three clips, real audio through the production chain) and its output is usable — it carries the new `spectral_level_rise` column live on all three tracks (nonzero 80–100 %, sd 0.17–0.35) and `RouteCoverageTests` reads **209 routes / 21 presets, 0 red** with it installed. But every features.csv row differs from the committed copy, and with the regenerated set in place `MeniscusStemDropsTests` ("the beat-locked regions never go dead", so_what) and `WitchlightPathTests` ("the smoothed harmonic phase travels the distance §2.3 measured", all three tracks) both fail. **Two candidate causes, not yet separated: (a) the pipeline's output has genuinely moved since the fixtures were captured at QG.1.3 — in which case those two gates are measuring a stale baseline and the drift is the finding; or (b) the generator is not deterministic** (it runs MPSGraph stem separation and the Beat This! grid). **Discriminator, for whoever picks this up: run the generator TWICE and diff its own two outputs.** Identical ⇒ (a), the pipeline moved. Different ⇒ (b), and the fixtures cannot be regenerated at all until it is made deterministic. **Consequence today:** any FeatureVector column added after QG.1.3 cannot be route-covered — tracked as `RouteCoverageTests.columnsPostdatingFixtures`, currently holding `spectral_level_rise`. Filed rather than fixed because re-baselining a certified preset's gate as a side effect of an unrelated increment is not a quiet call |
| BUG-089 | P2 · **root-caused + fixed 2026-08-17 (same day it shipped); consumer REVERTED** | dsp.calibration / test-adequacy | **`spectral_level_rise` shipped with a 22× ANALYSIS-RATE dependence, and its own rate-invariance test passed.** The rise was measured against a trailing MINIMUM over 0.15 s — a statistic with a hidden sample-count term, because a higher rate spans more frames of a noisier per-frame level (shorter hop = shorter RMS window) so the floor digs deeper. Same audio: **0.04 fires/s at 15.8 Hz vs 0.89/s at 59.4 Hz**, i.e. near-dead on local files and hyperactive on the tap (BUG-087's two rates). FTR.24 calibrated its consumer on a 15.8 Hz capture and shipped it to the 59.4 Hz path, where it took total travel 8.72 → 31.88 and **peak velocity 1.62 → 17.37**; Matt rejected it on sight — *"Much worse now as the motion is herky-jerky. Looks defective. Considerable regression."* ★★★ **The test-adequacy lesson is the transferable half: `levelRise_sameStepFiresAtBothAnalysisRates` asked only whether a synthetic +12 dB step fires at 10 Hz and 51 Hz — a step that large saturates the band at any rate, so the test could not fail. A rate-invariance test must compare a DISTRIBUTION on realistic material (fire rate, duty cycle, mean), not whether one enormous input survives.** Fixed by replacing the trailing minimum with a FIXED-LAG difference on a 40 ms pre-smoothed level (no sample-count term): the two real paths now agree within 12 %. Gated by `levelRise_distributionMatchesAcrossAnalysisRates` (duty and mean within 1.6×; do not widen). The FTR.24 consumer was reverted for a separate reason — see `docs/diagnostics/FTR15_SIZE_READS_LEVEL_2026-08-13.md` §10 — so the field currently has NO consumer. Detail below |
| BUG-085 | P1 · HANG.1–2 complete 2026-08-05; remains open | renderer / app.hang | **App intermittently hangs hard in `CAMetalLayer.nextDrawable`; window unresponsive, force-quit required.** The live stack proves a main-thread drawable request blocked at 0 % CPU after healthy frames, but the cause remains unknown; direct render-path leakage, the capture hook, preset-swap skip, inflight semaphore, GPU completion, display sleep, and occlusion have been ruled out. **HANG.1 instrumentation is merged to `main` via PR #37 (`c54a2e7c`)**. HANG.2 completed a full-track control plus a 10 min 36 s Witchlight soak with 34,811/34,811 drawables balanced and no stalls or imbalances, refuting a deterministic per-frame leak but not identifying the intermittent owner. **THE INSTRUMENTED CAPTURE NOW EXISTS (2026-08-05, session `2026-08-05T21-21-03Z`, Fractal Tree / Cherub Rock)** — and every lifecycle counter is BALANCED at the moment of the hang: `drawable=12045/12045`, `unique_presented=6012/6012`, `command_completed=6012/6012`, `failures=0`, `unpresented=0`, one request outstanding (`pending=frame:6013,site:mesh.descriptor`). The app held ZERO drawables and CoreAnimation still would not vend one, which independently confirms HANG.2's soak: there is no app-side leak, and the owner is outside the app. Two captures 98 s apart are byte-identical on those counters — a PERMANENT block, not a long stall. See the detail section. |
| BUG-081 | P2 | app.hang | **3 instances now** (2026-08-03 ×1, 2026-08-04 ×2). | **App beachballed ~78 s into session `2026-08-03T22-54-06Z` and needed a force-quit; no `.ips` exists** (force-quit produces none) and `session.log` ends mid-normal-operation with no fatal. **Evidence-only — no root cause asserted.** What the capture DOES establish: the renderer was healthy to the last frame — steady 60 fps, Fractal Tree at **0.18 ms GPU against a 0.7 ms budget**, no degradation trend across 3756 frames; background ML load rising but modest (`stem_analyzer_ms` 0 → 3.4). **Ruled out by test:** FTR.2's shader overflowing the mesh primitive limit via a bad `branch_count` — no non-finite values in the capture and `branch_count` never exceeds 59 against the 63 ceiling. A frozen UI with a live render loop points away from the preset, but that is inference and BUG-061's rule forbids acting on it. **Same class as BUG-060** (force-quit hang, render loop died, no stack captured, never reproduced) — two instances now, both blocked on the same missing artifact. **Next evidence:** `sample PhospheneApp 10 -file ~/Desktop/phosphene-hang.txt` run DURING the beachball, before force-quitting |
| BUG-088 | P3 | preset.fidelity / documentation-drift | **Aurora Veil's `audio_routes` manifest does not describe the preset, and it is CERTIFIED.** It declares 5 routes; `pulseAmp01` is declared `kind: continuous` but the shader uses it as a **silence gate** (`aurora_stars(rd, f.bar_phase01, f.pulse_amp01)`, "fades the twinkle to zero at silence") — measured pinned at 1.000 with **zero p5–p95 range**, which is correct gate behaviour and useless as a driver. And it **omits three routes the code actually reads**: `drumsEnergyDev` (ALIVE, 61 % nonzero — the only live stem input, so QG.1 route coverage is blind to it) and `vocalsPitchHz` / `vocalsPitchConfidence` (**0.1 % nonzero**). Net: the manifest overstates coupling. Surfaced by Matt's M7 2026-08-12 — *"I don't really see how the preset responds to music beyond the flickering of the stars once per bar. The veil is just aurora-ing."* Measurement explains it exactly: of everything Aurora Veil reads, only `barPhase01` has large dynamic range. Tool: `Scripts/check_route_liveness.py`. Detail below |
| BUG-087 | P2 · **partial fix 2026-08-13 (10 → 16.4 Hz); ≥40 Hz NOT met — audio arrival rate is the ceiling, not slicing** | audio.capture / calibration | **Local-file playback runs the whole MIR chain at 10 Hz where streaming runs it at 51 Hz — a 5.1× rate loss on the primary development session type.** `LocalFilePlaybackProvider` asks for `installTap(bufferSize: 1024)` (≈47 Hz) and AVAudioEngine ignores it, delivering **0.1-second** buffers instead — 4414 frames measured at 44.1 kHz, 4808/4810 at 48 kHz. `processAnalysisFrame` runs once per audio callback with no time gate, so the callback rate *is* the analysis rate: every `FeatureVector` field — bands, deviation primitives, `beatPhase01`, centroid, flux, mood inputs — updates at 10 Hz on local files. Proven a fixed *duration* rather than a frame count by the rate-independence discriminator (both sample rates land on 0.1 s). This is the same 10 Hz the FTR program hit from the preset side. Diagnosis only — no fix code. Detail below |
| BUG-086 | P2 · **RESOLVED 2026-08-12** (`e6c188e6`) | dsp.stem / calibration | **Every per-stem feature reaches presets ≈5.4 s behind the audio, on the local-file path, in steady state — while the beat grid beside it is time-aligned to ≈0.3 s.** Root cause is read, not inferred: separation runs on a fixed 10 s chunk (`modelFrameCount = 431` — the exported Open-Unmix model cannot take a shorter one) every **5 s**, and `runPerFrameStemAnalysis` starts its read window **5 s into** that chunk to buy one separation period of runway. So `lag = chunkLength − startOffset ≥ separationPeriod`, exactly. Measured three independent ways, agreeing: 5.4 s on 39 of 40 stem × track pairs. Affects every stem-driven preset, Aurora Veil's `other_energy_dev` anchor included. Diagnosis only — no fix code, per the multi-increment process. Detail: `docs/diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md` §7b + §8 |
| BUG-084 | P3 | dsp.stem | **`StemAnalyzer` deviation reaches 35 where the primitive's real ceiling is ~3.4** — suspected divide-by-near-zero against a not-yet-converged per-track EMA baseline (the stem-side twin of the BUG-027 / AGC2.4.1 cold-start family). No product impact today: FFO's aurora is defended by the FBS.S3.2 soft knee (35 → 1.64), which is what let BUG-041 close. Filed 2026-08-03 (RECON.2) so it survives that closure — the *input* is wrong even though the output is defended. Unreproduced; fixtures retained |
| BUG-070 | P2 | audio.capture / resource-management | **Fix landed 2026-07-12 (PUB.6), pending live validation** — a FAILED device-change tap reinstall left `_isCapturing=true` with zero callbacks: engine health detectors starved (SignalHealthMonitor.evaluate is sample-driven → deadTap never confirms) and the router's recovery restart blocked at the alreadyCapturing guard; only the app-layer poll-based stall card surfaced it. Fix: the catch now clears `_isCapturing` (recovery unblocked) and keeps the monitor as a diagnostic beacon; the false "create steps stopped the monitor" comment corrected. Residual OPEN half: the 3-queue lifecycle interleave (device-change reinstall vs silence-recovery vs user stop) stays unserialized — static-only evidence; restructuring the G1-validated (12/12) path without a reproduced artifact is the BUG-063 pattern. Existing breadcrumbs (per-step diagnostics + install generation) are the instrumentation; serialize only if a live session shows an interleave |
| BUG-076 | P2 | dsp.beat | **Prep grid is window-position unstable on Bleed (Meshuggah) — a third of 30 s windows give a wrong tempo, and Spotify's preview lands on one.** CORRECTED 2026-07-30 after direct measurement (the original filing inferred a universal 3:2 mis-lock from a single session-log value; that was wrong). Measured across nine 30 s windows of the full track: six read ~115 BPM (correct — matches madmom 115.0, librosa 115.0, drums-stem 115.1), but three read 121.1 / 166.1 / 242.7 — a **2.11× spread**, including non-metrical values. `beatsPerBar` swings 2/3/4 on a 4/4 track and `barConfidence` sits at 0.14–0.64. **Control:** Billie Jean over the same windows is 116.9–117.3 with beatsPerBar 4 and barConfidence 1.00 throughout — so this is dense-transient-specific, not universal, and the existing confidence signal already flags it. The session's 174.6 was the preview excerpt landing in the unstable region. Evidence: `docs/diagnostics/BEATBENCH_BASELINE_2026-07-30.md`; reproduce with `BeatBench --audio <clip> --seconds 30`. Category-4 target for Phase DBN (a sequence decoder over the full activation timeline should not be excerpt-dependent); Phase FT removes the 30 s premise for local files |
| BUG-065 | P3 | dsp.beat | **Live BeatGrid phase drifts off the audible beat over a track** — the cached grid has the right BPM but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it: drift grows ~11 ms (track start) → **50–70 ms (mid/late-track)**, and **28 % of frames exceed the ~60 ms perceptual window** (evidence: session `2026-06-29T12-43-51Z`, Cherub Rock 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; lock_state=2 only 67 %-within-60 ms). **Caps how frame-locked beat-driven presets can feel** — the live example is Glaze's GLAZE.7 downbeat push (reads connected but not *tight*; tightest early, loosens as the track plays). NOT a functional break (phase is approximately right). **NEW EVIDENCE — session `2026-07-30T15-39-21Z` (Lumen Mosaic, 80.45 BPM 4/4). Matt: "feels a little laggy, otherwise working as intended." This is the strongest case yet and it is WORSE than the 2026-06-29 baseline:** **50 % of frames exceed the ~60 ms perceptual window** (baseline 28 %), `lock_state == 2` only 63 % of frames, and drift **grows monotonically across the session** — by 10 s window: **0 / 6 / 8 / 52 / 70 / 59 / 68 / 104 / 119 ms**. `grid_bpm` is rock-constant at 80.45, so the BPM is right and it is purely the PHASE slipping. Frame rate is NOT the cause and was ruled out first: p50 59.9 fps, only 0.08 % of frames below 30 fps, and `frame_cpu_ms` p50 actually IMPROVED to 11.06 (from 17.30 on `2026-07-27T16-31-01Z`). The "lag" a listener feels is the visual falling up to ~119 ms behind the audible beat late in the track, not stutter. Confirms the mechanism in the original report — the tracker BOUNDS drift without TIGHTENING it — and strengthens the case for the suggested live re-lock / cached-BPM-error correction. In scope for the beat-sync program (D-202).

**Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is **mid-track drift convergence** — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session |
| AUDIT-2026-06-09 | P2/P3 | audit backlog | Full-codebase audit findings not individually filed |
| BUG-060 | P3 | renderer / app.hang | App hang requiring force-quit: render loop died one frame after a `preset → Gossamer` switch (`22-10-50Z`); no stack captured. **RECURRED (Matt, 2026-08-03)** — this falsifies the "likely resolved by NACRE.2b" status, so the preset-apply race is fixed but is **not** the hang mechanism. Needs a `sample`/stack capture on the next occurrence; do not re-run the non-recurrence watch |
| BUG-058 | P3 | audio.capture / resource-management | RARE intermittent: a mid-session output-device swap *occasionally* freezes the tap (`performReinstall` doesn't complete; stale-buffer freeze, not silence). G1 device-swap recovery is otherwise robust (validated 12/12, 2026-06-17); the single freeze was un-reproduced — likely a `coreaudiod`-settling transient. Instrumented |
| BUG-056 | P3 | local-file / audio | Local-file playback restarts the track from the top on an output-device change (AVAudioEngine teardown/restart, no resume-from-position) |
| BUG-055 | P2 | app.ui / permission | Silent system-audio tap after a rebuild: stale Screen-Recording grant; `CGPreflightScreenCaptureAccess` returns stale-`true` → app shows "ready", renders a flatline. **Symptom half RESOLVED 2026-06-17** (`a0a9ded`, silent-tap detector + fix-ladder card) — the app now explains the failure instead of lying. **Durable root still OPEN and externally BLOCKED** on CLEAN.2.5b: a stable signing identity needs a paid Apple Developer membership. Detector half closes on Matt's manual UX validation of the card |
| BUG-054 | P3 | dsp.key | Key detection has never been accurate enough to use — 1024-pt FFT can't resolve semitones < 1 kHz, full-mix chroma, no constant-Q. Non-load-bearing today |
| BUG-036 | P2 | audio.capture / performance | Heap allocations on the real-time audio thread (three sites) |
| BUG-028 | P2 | dsp.beat | Beat-grid live phase imperfect on ~half of tracks |
| BUG-077 | P3 | dsp.beat / api-contract | **`BeatGridResolver.snapToBeats` diverges from the Beat This! reference post-processor** — the reference moves *every* downbeat prediction to the closest beat unconditionally; we discard any candidate beyond `snapFrames = 2` (40 ms). Found at DBN.1 while auditing the resolver against the paper. **Currently harmless and NOT the cause of the low downbeat F** — measured, 100 % of candidates survive the gate (median distance 0.0 ms), so nothing is being discarded today (the real cause is a near-degenerate downbeat *stream*, see `docs/design/DBN_DECODER_SPEC.md` §2.1). Filed because it is a genuine spec-fidelity divergence of the D-077 class that will bite the moment downbeat timing loosens — e.g. on a track whose downbeat peaks sit a frame or two off the beat. Fix is one comparison; do it in DBN.3 when the resolver is being touched anyway, not as a standalone change |


---

## Open

---

### BUG-099 — Witchlight reaches ~30 fps at 4K after the 8.2× fix; closing the rest is a product decision (2026-08-19)

**Status: open. Needs Matt's call, not more optimisation.**

BUG-098 took Witchlight from 273.88 ms to an extrapolated ~33 ms at 3840×2160 (8.2× measured in
the harness, 151.2 → 18.4 ms). That **meets the stated target with headroom** — `CLAUDE.md`
promises 60 fps *at 1080p*, and 1800×1200 extrapolates to ~8 ms — but a 4K panel still runs at
about 30 fps.

**Why there is no third shader fix.** After PERF.2/PERF.3 the remaining 4K cost is balanced
rather than dominated:

| component | 4K cost |
|---|---|
| beads / particles / feedback | 6.0 ms |
| bloom | 5.4 ms |
| three star layers | 4.9 ms |

Nothing here is waste of the kind BUG-098 found (noise multiplied by zero, or octaves that never
reached the image). Halving any of these means removing something the preset draws.

**Two routes, both visible to the user — which is why this is Matt's:**

1. **Drop or cheapen a star layer.** The three-layer parallax is a documented WL.2 feature — the
   near layer crossing frame in ~4 minutes and outpacing the far ones ~13:1 is what gives the
   backdrop its depth. Removing one takes ~1.6 ms and some of that read.
2. **`setDirectRenderScale` below 1.0**, as Nimbus already does at 0.5× for exactly this reason
   (a heavy volumetric whose cost scales with on-screen pixels). ~4× headroom, traded against
   crispness in the stars and bead cores — and the stars are sub-pixel to ~2 px by design
   (WL.2-e), so they are the part most likely to suffer.

⚠ **Context for the decision: Witchlight is an outlier, not a symptom.** In the same 4K session
the next most expensive preset measured was Volumetric Lithograph at 16.44 ms, and the rest sat
at 3.27–4.94 ms. Six of seven measured presets hold 59–60 fps at 4K unaided.

⚠ **Also unresolved and cheaper to act on:** the app renders 1920×1080 while idle and drops to
**900×600** one second after a session starts. Every performance judgement made before
2026-08-19 — including two Witchlight sign-offs — was at 0.54 MP, a quarter of the target. That
default deserves its own decision.

---

### BUG-098 — Witchlight is over the frame budget in production, and it is the only measured preset that is (2026-08-19)

**Status: FIXED (PERF.2 + PERF.3, 2026-08-19), 8.2× measured end to end. ✅ The 60 fps @ 1080p
target is met with headroom (~8 ms at 1800×1200). ⚠ Fullscreen 4K is ~33 ms (≈30 fps) and the
remaining gap is a product decision, not a shader one — see BUG-099.** Filed after Matt asked
the right question — *"Are all presets supposed to run at 60 fps? If so, isn't this something you
can verify?"* — which turned out to have no instrument behind it.

**Per-preset GPU cost, 10 recorded sessions, `frame_gpu_ms`:**

| preset | frames | median | p90 | p99 |
|---|---|---|---|---|
| **Witchlight** | 12 109 | **13.75 ms** | **65.50 ms** | 82.37 ms |
| Nacre | 1 791 | 1.73 ms | 2.84 ms | 76.82 ms |
| Stave | 3 372 | 0.35 ms | 2.85 ms | 57.44 ms |
| Fractal Tree | 26 887 | 0.16 ms | 1.03 ms | 11.31 ms |

Witchlight's *median* consumes 82 % of the 16.7 ms budget and its p90 is 4× over. Everything else
measured is two orders of magnitude cheaper.

**It is a plateau, not a spike.** On `2026-08-18T16-10-38Z` the cost steps from 15.9 ms to ~60 ms
at t≈25 s and holds ~60 ms for the remaining 85 s. On `2026-08-18T18-04-06Z` the same preset on
the same track steps to ~12 ms and holds. Two stable regimes, 5× apart.

✅ **The 5× WAS resolution, and the `RENDER_TARGET` line settled it in one session.** Cost is
very close to linear in pixels: Witchlight measured 22.5 ms/MP at 900×600, 30.3 at 1800×1200 and
33.0 at 3840×2160. Every earlier "looks good" session — including two Witchlight sign-offs — ran
at **900×600 (0.54 MP), a quarter of the 1080p target**, which is the app's own default once a
session starts (it renders 1920×1080 while idle and drops to 900×600 one second after playback
begins). That default is why this went unseen for so long, and is worth its own decision.

**ROOT CAUSE (2026-08-19).** `witchlight_bloom` evaluated `fbm8` + `warped_fbm` — ~64 Perlin
evaluations — for every pixel, then multiplied by `body = exp(-r*r*70)`, which is ~0 outside a
ball a sixth of the frame wide. ~530 M Perlin evaluations per 4K frame to produce black.
**Fixed** with an early return when `body < 1e-3`: 151.2 → 31.8 ms/frame at 4K in the harness
(4.9×), visually identical on every WL.2 gate figure.

⚠ **Do NOT build an offline 1080p frame-budget gate until that is answered.** At 1080p Witchlight
plausibly measures the cheap ~12 ms and the gate passes, while the real session ran at ~60 ms.
That is precisely the BUG-097 failure class: a harness that does not reproduce the production
condition is not testing production, and it would issue a green certificate over the defect.

⚠ **Coverage: 4 of 29 presets.** Only four have enough continuous frames in the recordings to
attribute, and they were selected by which presets Matt happened to leave on screen — a preset
that is slow for two seconds before switching away is invisible to this method. **The other 25
are unmeasured, not passing.** The only pre-existing performance test renders a *single* frame
with no per-preset budget.

**Method note worth keeping.** The first pass used `deltaTime` and concluded three presets were
"rock solid at 16.7 ms". That is vsync: 16.7 ms means the frame waited for the 60 Hz refresh, and
says nothing about headroom. `frame_gpu_ms` is the column that answers the question, and it
separates the same four presets by ~80×. A metric that cannot distinguish a preset using 0.16 ms
from one using 13.75 ms was never going to find this.

---

### BUG-097 — A physics frame-time clamp corrupts a musical measurement: Witchlight loses two thirds of its off-beat accents when frames get heavy (2026-08-18)

**Status: FIXED 2026-08-18 (WL.14), on Matt's instruction. Validated on three real sessions and
gated by a new test that was confirmed to fail on the pre-fix code.**

**The fix.** `advance` now derives `clockDt` — real elapsed time, unclamped — alongside the
clamped `dt`, and the four quantities that measure a DURATION use it: `timeSinceWrap`
(→ `barPeriod`), `gridSilentFor`, `flareRefractoryRemaining`, `offBeatRefractoryRemaining`. The
integrators keep the clamp, which is what it was written for.

| session | frames over cap | off-beats before | after |
|---|---|---|---|
| `2026-08-18T16-10-38Z` | 48.8 % | 6 | **105** |
| `2026-08-18T14-09-35Z` | 25.3 % | 50 | **149** |
| `2026-08-17T15-23-17Z` | 0.2 % | 79 | **83** |

All three land at the designed ~3:1, and **the already-healthy session barely moves** — the
signature of a fix rather than a re-tune. Flare alignment on the worst session rose 36 % → 54 %.

**The gate that was missing.** `offBeatPulseSurvivesHeavyFrames` drives the path at 16.7 ms and
50 ms frames and asserts the off-beat:downbeat ratio stays above 2:1. Reintroducing the defect
takes it to **0 pulses**, so it demonstrably catches this rather than merely passing beside it.

⚠ **STILL UN-VALIDATED LIVE.** The fix only changes behaviour when frames go long, and no
recorded session yet carries it under load: the 2026-08-18 18:04 session ran the pre-fix WL.13
binary and was healthy anyway (0.0 % of frames over the cap, accents already at 2.95:1). The
bad case is evidenced offline only — 6 → 105 off-beat pulses replaying
`2026-08-18T16-10-38Z`. A loaded session on a WL.14 build is still owed before this is closed
with confidence.

**A hypothesis raised and falsified while checking this (recorded so it is not re-run).** Stroke
liveliness differed sharply between sessions — 22.9 turns/min at 30 fps vs 34.7/min at 60 fps —
which looked like the same clamp slowing the phase EMAs, since they still use the clamped `dt`.
It is not: switching those EMAs to real time moves the turn count by **1** on both sessions
(42→43, 93→94). The EMAs are fine and the difference is session content. `dt` remains correct
for the integrators.

**How it was found.** Matt's BUG-095 M7 reported Witchlight as *"less coupled to the beat"*. The
A/B on that session showed the beat events were bit-identical between builds, so the phase fix
was exonerated — but the probe also showed **50 downbeat bursts and 50 off-beat pulses**, a 1:1
ratio where 4/4 should give 3:1. That anomaly is this bug, and it is unrelated to BUG-095.

**Mechanism.** `WitchlightPath.advance` begins:

```swift
let dt = min(max(deltaTime > 0 ? deltaTime : 1.0 / 60.0, 1.0 / 240.0), 1.0 / 30.0)
```

The 1/30 s ceiling is correct for what it was written for — integrators must not take a huge step
after a stall. The defect is that **one consumer of `dt` is not a physics integrator**:

```swift
timeSinceWrap += dt
if barDownbeatNow { barPeriod = timeSinceWrap; timeSinceWrap = 0 }
```

`barPeriod` is how long a bar lasted, and WL.9 gates the off-beat pulse on it:
`offBeatsAllowed = barPeriod / beatsPerBar >= offBeatMinBeatSeconds` (0.55 s). Clamping `dt`
makes a heavy-framed bar *measure* shorter than it was, so a 94 BPM track can be misread as too
fast for an off-beat pulse to read — and the pulse is simply not emitted.

**Measured, two sessions, same track (`Carry The Zero`, 94.1 BPM, true bar 2.55 s):**

| session | frames > 33.3 ms | elapsed time discarded | measured bar period | downbeats : off-beats |
|---|---|---|---|---|
| `2026-08-17T15-23-17Z` | 0.2 % | 19.4 % | 2.52 s (1/28 short) | 28 : 79 — **2.8:1**, correct |
| `2026-08-18T14-09-35Z` | **25.3 %** | **28.8 %** | **1.80 s (33/50 short)** | 50 : 50 — **1:1** |

**Causally confirmed, not inferred.** Raising the cap alone on the affected session, changing
nothing else: `offBeatsAllowed` rejections **101 → 3**, off-beat pulses **50 → 149**. 149:50 is
the 3:1 the meter implies. Two earlier hypotheses were tested and **falsified** first — the meter
(`beatsPerBar` is 4 in every session) and the WL.11 drift compensation (disabling it changed
nothing) — and the raw `barPhase01` wrap intervals in the CSV are a clean 2.45–2.65 s under both
the wall clock and summed `deltaTime`, which is what localised the fault to the clamp rather than
to the grid.

⚠ **Two things make this worse than its size suggests.**
1. **It is self-reinforcing and points the wrong way.** More load → more long frames → fewer
   accents. The preset reads least musical exactly when the machine is most stressed, which is
   also when a viewer is most likely to blame the preset.
2. **No gate can see it.** The committed fixtures replay at a steady synthetic frame rate and
   never approach the cap, so every WL gate passes while production silently drops accents. This
   is the `SessionReplayHarness` failure class again: the harness is not reproducing the
   production time base.

**Likely fix, and why it is not applied here.** Accumulate the musical clock from the unclamped
`deltaTime` (keeping the clamp for the integrators), or clamp far higher for that one use. It is
close to a one-line change, but it roughly **triples the off-beat accent rate** on affected
sessions — a visible change to a CERTIFIED preset, so it needs Matt's pick and an M7 rather than
being folded into an unrelated increment. Worth checking whether any other preset accumulates a
musical quantity from a clamped `dt`.

---

---

### BUG-096 — RESOLVED (FTR.31): the hold was fine; the phase feeding it was not (2026-08-17, resolved 2026-08-18)

**Status: RESOLVED in FTR.31. The original diagnosis was wrong in a way worth keeping, because it
sent two increments down the wrong road.**

**What was filed.** That `BeatHold`'s trust gate — eight beat intervals whose spread is ≤ 20 % of
the mean — was too strict for a `beatPhase01` arriving at 14.6 Hz in 0.109-beat steps, and that the
fix belonged in the tolerance, the phase's delivery rate, or wrap detection.

**What was actually true.** The hold engages **immediately on a clean clock**: fed a smooth 60 Hz
phase it reports a tempo of 0.6375 s with `isStepping` true within nine beats. The gate is correct.

The real cause was in `DancePhase`, which FTR.28 wrote to work around this very bug. Its self-rate
estimator measured **dφ/dt per render frame** — but the measured phase is a staircase that changes
only on an analysis update, so a 0.109 jump inside one 17 ms frame reads as **6.5 cycles per second
on a 1.57 Hz beat**. The lock's correction still dragged the phase onto the beat, which is why the
gait measured well (in-step r +0.799, coordination R² 0.85) and why the error stayed hidden for
three increments. But between corrections the phase free-ran four times too fast and was yanked
back, crossing zero far more often than once per beat — and anything counting those crossings as
beats saw intervals of ~0.15 s, under `periodRange`'s 0.25 s floor, and threw every one away.

**The fix, one expression:** rate = `EMA(advance) / EMA(elapsed)`, both smoothed with the same τ.
A frame with no update contributes 0 to the numerator and its dt to the denominator, which is
exactly what a staircase requires. Measured on the same capture, the same hold:

| | before | after |
|---|---|---|
| frames where `BeatHold` vouched for a tempo | **0 / 3000** | **2650 / 3000 (88 %)** |
| tempo error vs the grid | — | **0.2 %** (0.6365 s vs 0.6378 s) |
| sway in step with the bar | +0.799 | **+0.991** (decoy +0.043) |
| coordination R² | 0.85 | **0.98** |

**⚠ Two claims made in this entry's name are retracted.** (1) That the FTR.10 beat-step "has been
engaging on ~1 frame in 8" — it was engaging on approximately none, for a reason that is now fixed,
and FTR.29's decision to supersede it on the trunk was taken partly on that number. (2) That the
gate's tolerance needed relaxing — it did not, and relaxing it would have masked this.

**★ The transferable lesson: a per-frame derivative of a signal that updates slower than the frame
rate measures the UPDATE CADENCE, not the signal.** Third instance of that family in four days —
BUG-089's trailing minimum, FTR.28's 0.133 s "dominant period", and this. When a quantity is
sampled coarser than it is consumed, every rate taken from it needs a window, not a difference.

---

### BUG-095 — Double-smoothed harmonic phase: a source EMA outlived its reason and every consumer was smoothing twice (2026-08-17)

**Status: FIXED in code — `TonalAnalyzer` now emits `phaseFifths` RAW. Full engine suite green
(1862 tests / 284 suites). ⚠ Witchlight is CERTIFIED and this changes its motion: needs an M7.**

**What happened.** `2861140e [FTR.3g]` (2026-08-04) added a vector EMA to the circle-of-fifths
phase inside `TonalAnalyzer`, because Fractal Tree read the field straight into hue. On
2026-08-16 `acc3c935 [FTR.19]` gave Fractal Tree its own `CircularPhaseSmoother` (D-209) —
superseding the reason the source EMA existed — but nobody removed it. **All four consumers
already smooth this angle themselves**, so all four were smoothing an already-smoothed value:

| consumer | its own circular EMA |
|---|---|
| Witchlight | τ = 1.5 s (`WitchlightPath.advanceHarmonicPhase`, D-198) |
| Nacre | ~0.9 s (`RenderPipeline+Nacre.swift:129`) |
| Cymatic | `hueTau` (`CymaticSandGeometry.swift:310`) |
| Fractal Tree | D-209 `CircularPhaseSmoother` (`MeshGenerator.swift:269`) |

A cascaded second pole does not merely lengthen the time constant — it attenuates *fast* motion
far harder, which is why the worst loss landed on the track whose harmony moves most.

**Measured, 30 s per track, total wrapped phase in circles (design: 2.1 / 1.7 / 15.4):**

| track | double-smoothed | source RAW (fixed) | design §2.3 |
|---|---|---|---|
| so_what | 0.72 | **2.09** | 2.1 |
| there_there | 1.00 | **1.80** | 1.7 |
| love_rehab | 3.77 | **15.10** | 15.4 |

love_rehab heading monotonicity recovers 0.24 → 0.38. **The §2.3 constants needed no
re-derivation — they were right all along**, and the fix reproduces them to within 2 %.

**The first wrong fix.** *Re-deriving the §2.3 constants* to make the gate green would have
laundered a 4× regression in a certified preset's hero driver. The second candidate — removing
Witchlight's own EMA — is treated below.

⚠ **The fixture rate is NOT the production rate, and this nearly produced a wrong conclusion.**
`TonalAnalyzer`'s α = 0.065 is a fixed *per-frame* factor, so its time constant depends on how
often analysis runs. `FixtureSessionCaptureGenerator` emits at **43.07 Hz** (1024 frames at
44.1 kHz), where α = 0.065 is τ ≈ **0.36 s**. Live analysis runs at **10.0–16.4 Hz** (BUG-087),
where the same α is τ ≈ **0.94–1.54 s** — so the source comment's *"τ ≈ 1.5 s at the ~10 Hz
analysis rate"* was accurate for production, and every τ figure in the sweep below is a
**fixture-rate** number. The first draft of this entry asserted the comment was "stale, off by
4×". It was not; the fixtures and production simply run the analyzer at different rates, which
is its own fixture-fidelity problem and is why a per-frame α is the wrong construction. Every
other smoother in that file takes `deltaTime`.

**Why the fix is still the source EMA and not Witchlight's.** In production the double-smoothing
was ~1.5 s (source) *plus* 1.5 s (Witchlight) — worse than the fixtures show, so the defect is
real and the direction of the fix is unchanged. But the choice between the two candidates turns
on rate-robustness rather than on the sweep: removing **Witchlight's** EMA leaves every consumer
sharing one source pole whose length is set by the analysis rate, and that rate is actively
moving (BUG-087 took it 10.0 → 16.4 Hz, and raising it further is an open increment). Removing
the **source** EMA leaves each consumer on its own `deltaTime`-based pole at the τ it was
designed and measured with, identical at any rate. Measured at fixture rate the Witchlight-side
fix also overshoots outright — 6.66 / 5.90 / 30.69 circles with love_rehab monotonicity
collapsing to **0.03**, a tangle, which is the preset's own anti-reference
`10_anti_tangled_scribble_ball` — and a τ sweep (0 / 0.3 / 0.6 / 0.9 / 1.2 / 1.5) found no
consumer τ reproducing the design figures, because the defect is the extra *pole*, not the
time constant.

**How it hid, and the order of events.** The committed QG.1 fixtures were captured *before*
FTR.3g, so their `tonal_phase_fifths` column is raw and every gate kept passing against a
pipeline that no longer existed (BUG-090). `WitchlightPathTests`' own comment describes it as
*"the check that caught a stray second smoothing stage cutting the travel by 2.5×"* — it was
built for exactly this failure and was blinded by its own fixture. Note the dates:
**FTR.3g 08-04 → Witchlight certified 08-07 → FTR.19 08-16.** Matt's certification M7 was on
the double-smoothed build, so this fix moves Witchlight *away* from what he signed off and
*toward* what its design doc specifies. That is why it needs a fresh M7 rather than being
treated as a restoration. Nacre is the opposite case — certified 2026-06-26, before FTR.3g, so
for Nacre this restores the behaviour it was certified with.

**Blast radius checked:** full engine suite 1862/1862 green, including the Nacre, Cymatic and
Fractal Tree suites; Fractal Tree's hue holds 87.5–101.6° across its drive frames, its D-209
smoother doing the job unaided.

**FOLLOW-UP (M7, 2026-08-18): the engine fix was right and the preset fix was wrong, and only
Matt's eye could separate them.** On the corrected single pole he reported Witchlight as
*"slightly less coupled to the beat … drifts a bit more out of sync over time"* (Nacre: *"looks
fine"*). Replaying his session `2026-08-18T14-09-35Z` through the production path under BOTH
code paths returned **bit-identical** beat behaviour — 50 downbeat bursts, 50 off-beat pulses,
flares within 10 % of a beat 86 % of the time, pen speed swing 4.13× — with **heading turns
50 → 74** the single moved quantity. The complaint was real and it was about LEGIBILITY, not
timing: unchanged accents against a stroke wandering 50 % more.

Cause: Witchlight was tuned and certified (2026-08-07) *during* the double-smoothed window, so
the cascade was the response Matt approved. `WitchlightTuning.phasePreTau` now makes that second
pole explicit and local to Witchlight; the analyzer stays raw for every other consumer. ⚠ Note
that raising `phaseTau` instead **cannot** substitute — it saturates at 68 turns however high it
goes, the same "a cascade is not a longer single pole" asymmetry that caused this defect.

Knock-on, fixed in the same increment: the calmer stroke sweeps fewer pixels, dropping ribbon
share 0.406 % → 0.368 % against a 0.40 % floor (WL.2-g) that had only 1.5 % headroom. Widening
the halo's falloff 2.8 → 2.1 *within* the existing sprite quad gives 0.433 % and 16 distinct
beads (up from 13) — the shading remedy the gate itself prescribes, and pointedly NOT
`WL_HALO_EXTENT`, which WL.2-j had to cut for fusing beads.

---

### BUG-094 — Meniscus clamps `arousal` to 0…1 when its contract is −1…+1, and a beat-locked region goes dead on calm material (2026-08-17)

**Status: root-caused and probe-verified. Fix NOT applied — it changes what a certified preset
looks like, which is Matt's call.**

**The defect.** `MeniscusStemDrops.swift:219` computes the MEN.4a musical-arc lift as:

```swift
let lift = max(0, min(features.arousal, 1))
```

`arousal`'s declared contract is **−1 (calm) to +1 (energetic)** (`AudioFeatures+Analyzed.swift`).
This clamps rather than maps, so the entire calm half of the primitive is discarded — every
negative frame reads as identical to "not calm at all".

**What it costs.** On `so_what` (Miles Davis, quiet modal jazz) today's mood output runs
−0.393…+0.519 with **35 % of frames negative**. Those all collapse to zero, `arcEnvelope`
(τ 6 s) sits low, `density = 0.35·arcEnvelope + 0.65·arrangement` never rises, and the
backbeat-gated **vocals region places 0 drops across the entire track** — which
`MeniscusStemDropsTests` correctly calls a dead route, since those three regions are beat-locked
and absolute.

**Why it stayed hidden.** MEN.4a was calibrated on a single capture where arousal never went
negative — its own comment records the range as *"arousal 0.19 → 0.52 → 0.27"* — so the clamp
never engaged. And the committed QG.1 fixtures bottom out at −0.077, roughly 0 % negative. The
defect only surfaced when BUG-090's regenerated fixtures carried today's mood output, after
DYN.6.2/DYN.7 refit the classifier.

**Probe (reverted, not committed).** Replacing the clamp with a map:

```swift
let lift = (max(-1, min(features.arousal, 1)) + 1) * 0.5
```

takes so_what's vocals region **0 → 24 drops** and turns the whole Meniscus suite green
(14 tests / 9 suites), with the other two tracks unaffected in kind.

**Why the fix is not applied here.** It makes a **certified** preset place more drops on calm
material — a visible change to what Matt sees, and therefore a product call plus an M7, not a
test fix. Applying it as a side effect of a fixture investigation is exactly the laundering
BUG-090 was filed to prevent.

**The sweep found a SECOND site, in the same preset.** `MeniscusCamera.swift:106` does the
identical thing to its own envelope:

```swift
arousalEnvelope += (max(0, min(features.arousal, 1)) - arousalEnvelope) * …
```

So Meniscus discards the calm half of `arousal` twice — once for drop density, once for camera
motion. Both need the same correction, and both change what a certified preset looks like.

**The codebase already has the correct idiom, two files away.** The orchestrator maps the same
primitive properly:

```swift
SessionPlanner.swift:327    let energy       = max(0, min(1, 0.5 + 0.4 * profile.mood.arousal))
PresetScorer.swift:277-279  let targetTemp   = max(0, min(1, 0.5 + 0.4 * valence))
                            let targetDensity = max(0, min(1, 0.5 + 0.4 * arousal))
```

`0.5 + 0.4 · x` centres the bipolar range on 0.5 and keeps both halves. That is the shape the
Meniscus sites should have used.

⚠ **Also checked and NOT affected.** `RayMarchPipeline+MetalFX.swift:183–184` writes
`max(0, valence)` / `max(0, -valence)` — that is a deliberate split of a bipolar signal into two
unipolar channels (warm and cool), which loses nothing. And the deviation family (`*Dev`) is
`max(0, *Rel)` **by definition**, not by accident. No MSL-side instances. The rule is not
"`max(0, …)` is wrong" — it is "clamping a bipolar primitive to one side of zero throws away
half of it".
### BUG-093 — The tree moves plenty and still reads as disconnected; the drivers track the wrong quantities (2026-08-17)

**Status: P1, evidence only, and deliberately NOT a tuning ticket.**

**Why this exists.** After nine live rejections of one complaint across FTR.15 → FTR.27, two
explanations have now been ruled out by measurement rather than argument:

1. **"The visual is not moving enough."** Ruled out. After 12 s on `2026-08-17T20-01-01Z`: `reach`
   span 0.680, size span 0.360, **visible trunk length span 0.151 clip space ≈ 164 px at 1080p**,
   spread 20°→34°, tip spark firing 0.37/s. The tree traverses two thirds of its geometric range.
2. **"A primary channel is dead."** Ruled out (BUG-092, retracted on that point): the inert term is
   `arousal`, whose coefficient is 0.10 inside a `max()` it never wins — removing or fixing it
   changes nothing about how much the tree moves.

**What remains, and it is a routing-semantics problem rather than a calibration one.** Every
quantity the geometry follows has been measured against what a listener notices, and none of them
correspond:

| channel | driver | what it actually measures | event specificity |
|---|---|---|---|
| size | `spectral_surge` | this moment's rank in the track's loudness distribution, off a τ 0.76 s follower | **0.25× — moves DOWN at events** |
| growth | `spectral_section_ratio` | a slow τ20 s density rank against the track's normal | not event-scaled at all |
| canopy angle | `spectral_flux` | broadband spectral change | 1.50× — fires as often between events as on them |
| tip light | `spectral_level_rise` | pre-AGC level rise (FTR.25) | event-aligned, but only 0.37/s |

**So the standing hypothesis is: the tree moves a lot while tracking three quantities that are not
what a listener attends to.** That is consistent with every rejection in the arc, including the two
where a genuinely event-aligned driver WAS tried and rejected for its motion cost — FTR.24 put one
on size and multiplied peak velocity 10.7× (*"herky-jerky… looks defective"*).

**⚠ Do not open another tuning increment against this.** Six size formulations, two accent
placements, three spread routes and a detector rewrite have all been tried. The next move needs a
changed premise about WHICH musical quantity the tree should follow — arrangement? section
boundaries? a beat-grid-derived structure? — and that is a product decision for Matt, not a
coefficient.

**Verification criteria for any future attempt:** a driver whose event specificity exceeds 2× AND
whose total travel stays within 25 % of the FTR.23 baseline, measured on one capture, before any
live review is requested.

---

### BUG-092 — Fractal Tree's declared `growth` route is inert: `arousal` loses its own `max()` on every frame (2026-08-17, RE-SCOPED same day)

**Status: P3, evidence only. This entry was filed with a WRONG headline and corrected hours later;
the correction is the more useful half.**

**⚠ WHAT I FILED FIRST, AND WHY IT WAS WRONG.** The original entry claimed `arousal` was the
preset's primary growth driver, that it flatlines after 12 s, and that this explained nine live
rejections of *"the tree grows and shrinks with no clear connection to the music"*. The flatness is
real. **The rest was false, because I measured the primitive and never checked its COEFFICIENT.**

The shader computes:

```metal
reach = saturate(max(0.10f * arousalReach, fullness) * musicGate)
```

Measured after 12 s on `2026-08-17T20-01-01Z`:

| term | p05 | p95 | span |
|---|---|---|---|
| `0.10 × arousalReach` | 0.038 | 0.070 | **0.032** |
| `fullness` (= `spectral_section_ratio × 0.5`) | 0.316 | 0.961 | **0.646** |
| `musicGate` (from `spectral_surge`) | 0.294 | 1.000 | 0.707 |
| resulting `reach` | 0.270 | 0.950 | **0.680** |

**`arousal` wins that `max()` on 0.0 % of frames.** It is not a dead driver; it is an inert term.
And the growth channel is not dead at all — `reach` spans 0.680, and the visible trunk length spans
**0.151 clip space ≈ 164 px of 1080**.

**The actual defect, which is small.** The sidecar declares `growth ← arousal`, and that route has
no visible effect. This is the FTR.2 false-manifest class, and QG.1 route coverage cannot catch it:
the gate asks whether a declared primitive VARIES (it does, faintly), not whether it survives the
arithmetic it feeds. `arousal`'s within-track flatness — mean 0.446…0.475, sd 0.048…0.069, the same
0.258…0.509 bounds on five captures across three builds and two audio paths — is unremarkable for a
*mood* classifier and is why it went unnoticed for the whole FTR program.

**Two fixes, both Matt's call because one changes what he sees:** delete the inert term and its
route (honest, no visual change), or raise its coefficient so a track's mood biases the tree's
resting size (a visible change, and the thing the route was presumably *meant* to do).

**★ The transferable lesson, which is why this entry is kept rather than quietly deleted: measuring
a PRIMITIVE's range says nothing about whether it reaches the picture.** Check the coefficient and
the surrounding arithmetic — a term inside a `max()` against something ten times larger is decor.
This is the same species as FTR.24's model/shader mismatch (glide order) three days earlier.

---

### BUG-091 — A single local file selected: preparation succeeds, playback never starts, every audio field is exactly zero (2026-08-17)

**Status: instrumentation increment landed. Root cause NOT asserted — one reproduction with the
new breadcrumbs will name the branch.**

**Expected.** Selecting one local file plays it: `LocalFilePlaybackProvider` starts via
`audioRouter.start(mode: .localFilePlayback(url))`, the AVAudioEngine node tap feeds the chain
(BUG-087: ~10–16 Hz on this path), `playback_time_s` advances, and no Core Audio **process** tap
is installed.

**Actual** (`2026-08-17T17-19-19Z`, *03- Carry The Zero.flac*): 1262 frames / 84 s of render
clock, and every audio-derived field holds **exactly one distinct value, 0.0**:

| field | distinct values | value |
|---|---|---|
| `playback_time_s`, `track_elapsed_s`, `accumulatedAudioTime` | 1 | 0.0 |
| `bass`, `mid`, `treble`, `pulse_amp01`, `beatPhase01`, `spectral_level_rise` | 1 | 0.0 |
| `time` (render clock) | 1262 | advances normally |

So this is not a frozen playback clock with audio flowing, nor a stalled renderer: **no audio
samples ever reached the analysis chain.**

**The discriminator — a working session 1.5 h earlier, same file, same OS build (26.5.1 / 25F80).**

| | `16-19-13Z` (works) | `17-19-19Z` (fails) |
|---|---|---|
| preparation, BeatGrid, plan | identical | identical |
| `WIRING: provider.start INSTANCE` | **present** | **ABSENT** |
| `TAP_BUFFER: requested=1024 delivered=4410 (10 Hz)` — AVAudioEngine node tap | present | absent |
| `TAP: startCapture → createProcessTap` — system-audio path | **absent** | **present, twice** |
| gap between preparation and `→ready` | none (same second) | **8 s** |
| `playback_time_s` span | 0.1 → 34.1 s | 0.0 → 0.0 |

**What that pins down.** `resetStemPipeline(caller: .other)` has exactly ONE call site —
`handleLocalFileReady()` — and it appears in the failed log. So that function ran, cleared all
three of its guards (LF source, URL present, not a duplicate `.ready`), reached `buildPlan()`, and
then never got to the router start.

**Candidate mechanism, deliberately NOT asserted as root cause** (BUG-061: do not infer a cause
from "the path requires X, so X held"): the `catch` around
`audioRouter.start(mode: .localFilePlayback(url))` logs via `lfLogger.error` only, then calls
`sessionManager.endSession()`, which sets `currentSource = nil`. With no local-file source,
`startAudio()`'s LF.4 guard — whose own comment warns that `start(.systemAudio)` would
`stopInternal()` the provider — no longer fires, so the process tap is installed and any provider
is torn down. That chain reproduces every observation, including the two tap installs and the
silence, but the first link is unverified.

**Why it could not be verified from the capture, which is a defect in its own right.** Every
branch in `handleLocalFileReady()` that can end in silence returns without writing to
`session.log`, and its failure path logs only to `os_log` — which is not retained here: a
`log show --last 4h --predicate 'subsystem BEGINSWITH "com.phosphene"'` over the failure window
returns **zero lines**. An 84-second silent session left no evidence of its own cause.

**Instrumentation added (this increment, no fix):**
- every early return in `handleLocalFileReady()` names itself in `session.log`, with the actual
  `currentSource`, `isLocalFile` and URL;
- the `router as? AudioInputRouter` cast — which silently gated the *entire* start — is now a
  logged `guard`;
- the LF start failure writes the error text and the `→ endSession` consequence to `session.log`;
- `startAudio()` logs which path it took **and what `currentSource` was** when it chose the tap;

**⚠ A sixth breadcrumb was attempted in `AudioInputRouter.start(mode:)` and ABANDONED — twice
over, for two independent reasons worth recording.** (1) It first read `activeMode` to report
"replacing=<previous mode>". `activeMode` takes the router's `NSLock`, `start()` is reachable from
the file-ended completion path that already holds it, and NSLock is not recursive — **all three
`SessionLifecycleChurnTests` watchdogs timed out at 5 s. A LOG LINE caused a hang-class failure,
and the churn suite is the only reason it did not ship.** Never take a lock in `start()`.
(2) The lock-free version was then dropped as well: `AudioInputRouter.swift` sits at **exactly**
its 400-line lint cap, so any addition needs a file split, and the line was redundant anyway —
`startAudio()`'s new breadcrumb plus the existing `TAP: startCapture` lines already identify the
mode. If a future increment does need it there, split the file rather than trimming a comment.

**Verification criteria (written before any fix):**
1. Automated: a regression test that drives `handleLocalFileReady()` with a local-file source and
   asserts the router ends in `.localFilePlayback` mode — and that a subsequent `startAudio()`
   does NOT replace it with `.systemAudio`.
2. Manual (required — this is a UX-flow and audio-path defect): select a single local file, confirm
   audible playback, and confirm the capture shows `provider.start INSTANCE`, a `TAP_BUFFER` node-tap
   line, no `createProcessTap`, and `playback_time_s` advancing.

---

### BUG-090 — The QG.1 route-coverage fixtures cannot be regenerated: today's generator output reds two other presets' gates (2026-08-17)

**Status: evidence only. No fix attempted, and deliberately so — see the last paragraph.**

**What was tried and why.** FTR.25 declares a route on `spectral_level_rise`, a `FeatureVector`
column added after the fixtures were captured at QG.1.3. QG.1 therefore cannot verify it: the
fixtures are recorded CSVs with no audio beside them. `FixtureSessionCaptureGenerator`'s own header
says *"Regenerate + re-copy when the CSV schema appends columns"*, so that was the first move, not
the allowance.

**The generator works.** 18 s, three vendored clips through the production chain, and the new
column is live on all three: `love_rehab` nonzero 100 % / sd 0.242, `so_what` 99 % / 0.346,
`there_there` 80 % / 0.165. With the regenerated set installed, `RouteCoverageTests` reads
**209 routes across 21 presets, 0 red**.

**But every row differs from the committed copy**, and two other presets' gates fail with it:

| gate | preset | failure |
|---|---|---|
| `MeniscusStemDropsTests` — "the beat-locked regions never go dead" | Meniscus | `perRegion[region] == 0` on `so_what` |
| `WitchlightPathTests` — "the smoothed harmonic phase travels the distance §2.3 measured" | **Witchlight (CERTIFIED)** | `circles` outside 0.7–1.4 × target on all three tracks |

**Two candidate causes, not separated.** (a) The pipeline's output has genuinely moved since
QG.1.3 — in which case those gates are asserting against a stale baseline and the drift is itself
the finding. (b) The generator is not deterministic; it runs MPSGraph stem separation and the
Beat This! grid, neither of which has been checked for run-to-run stability here.

**Discriminator, one command:** run the generator twice into different directories and diff its own
two outputs. Identical ⇒ (a), the pipeline moved, and the two gates need re-baselining as their own
increment with Matt's sign-off (Witchlight is certified). Different ⇒ (b), and the fixtures cannot
be regenerated at all until the generator is made reproducible.

**Consequence today.** Any `FeatureVector` column added after QG.1.3 cannot be route-covered.
Tracked explicitly as `RouteCoverageTests.columnsPostdatingFixtures`, which currently holds
`spectral_level_rise` and prints a FIXTURE GAP line on every run.

**Why this was filed rather than fixed.** Re-baselining a certified preset's gate as a side effect
of an unrelated preset increment is not a quiet call, and "my change went green after I regenerated
a shared fixture" is how a real regression gets laundered. The fixtures stay as committed.

**UPDATE — discriminator run, and the drift fully localised (CHR.3g, 2026-08-17).**

**The discriminator answers (a): the generator IS deterministic.** Run twice into separate
directories, all six outputs are **byte-identical** (`cmp` clean on features.csv and stems.csv
for all three tracks). So the fixtures CAN be regenerated reproducibly, and the two failing
gates are asserting against a stale baseline rather than against noise.

**The drift is not broad — it is five columns in two analyzers.** Comparing the committed
fixtures against the regenerated set, per column, as mean |delta| over the shared rows:

| column | love_rehab | so_what | there_there |
|---|---|---|---|
| `tonal_tension` | 63 % of range | 38 % | 50 % |
| `harmonic_flux` | 55 % | 36 % | 58 % |
| `valence` | 24 % | 25 % | 46 % |
| `tonal_phase_fifths` | 20 % | 9 % | 9 % |
| `arousal` | 17 % | 18 % | 43 % |

**Everything else is stable.** 67 of 72 shared feature columns moved < 1 % of range, and
**stems.csv is completely unchanged — 0 of 52 columns on all three tracks.** Bands, deviation
primitives, beat, pulse, section and every per-stem field are identical.

**The causes are named in git, and all are intentional.** The fixtures were captured at
`cc1dfcd1` (QG.1.3). Since then: `2861140e [FTR.3g] Seed the density baseline, **smooth the
harmonic phase**`, `c5b491ba [TONAL.2b] calibrate TonalAnalyzer gate from the 1000-track pilot`,
`86169538 [DYN.6]` / `21651962 [DYN.6.2] MoodClassifier: refit the flux scaler on corpus
statistics`, `a91a7915 [DYN.7] Mood: the prepared mood and the live mood become one
measurement`. Each landed with its own increment. **This is not a regression.**

**Both failures trace to exactly those columns**, confirmed by reproducing them with the
regenerated set installed:

- **Witchlight** — its hero driver IS `tonalPhaseFifths`, and the gate asserts how far the
  smoothed harmonic phase travels. `circles` now falls **below** 0.7 × target on all three
  tracks, which is the expected direction: FTR.3g deliberately *smoothed* that phase, and
  smoothing reduces travel. The gate encodes a pre-FTR.3g target.
- **Meniscus** — `MeniscusStemDrops` gates drop placement on `features.arousal`
  (`MeniscusStemDrops.swift:219`, the MEN.4a musical-arc lift). Arousal moved 17–43 % of range,
  so a beat-locked region that used to fire on `so_what` no longer does. Its stems are
  identical, which is why the stem-side explanation never fitted.

**Also found:** the committed fixtures predate more than `spectral_level_rise`. The regenerated
set adds **six** columns — the whole DYN block (`spectral_density`, `_slow`, `spectral_surge`,
`spectral_section_ratio`) plus `spectral_level_rise` (FTR.24) and `waveform_occupancy`
(CHR.3c). So the fixture gap currently blocks route coverage for three separate increments'
primitives, not one.

**RESOLVED (same day).** Regenerating was safe and reproducible, and **neither failing gate was
a stale baseline — both were real defects the frozen fixtures had been hiding** (BUG-094
Meniscus, BUG-095 double-smoothed phase). With both fixed, the regenerated fixtures are
committed and the full suite is green at 1862/1862. Drift is now **four** columns — `arousal`,
`valence` (both moved by the DYN mood work) and `harmonic_flux`, `tonal_tension` — each traced
to an intentional change, plus the six new columns above. `tonal_phase_fifths`, the fifth
drifted column, is **gone from the list**: it was the regression, not drift.
`RouteCoverageTests.columnsPostdatingFixtures` is now **empty** — every column added since
QG.1.3 is present and covered, and the gate reads 199 routes / 20 presets, 0 red.

**One thing regenerating did NOT unblock, and the reason was misdiagnosed.** Stave's
`waveformOccupancy` route was recorded as blocked by BUG-090. It is not: the regenerated
fixtures carry `waveform_occupancy`, but it is **0.0000 with zero variance on all three
tracks**, because the model is ticked in the render path while the generator runs only the MIR
pipeline. That is the **QG.1.1** limitation. Stave's certification is still blocked, and the
fix is a generator change (tick the occupancy model during capture), not a fixture refresh.

**FOLLOW-UP (CHR.3h, same day): the two failures are NOT the same kind of thing, and only one
is a re-baseline.** Investigated separately rather than treated as one fixture chore:

- **Witchlight — ⚠ THIS CALL WAS WRONG, and it is the most useful thing in this entry.** CHR.3h
  read the gate as a stale baseline: `circles` fell below 0.7 × target on all three tracks, which
  is the direction FTR.3g predicts, so the constant was assumed to predate the change and the
  preset was assumed sound. **It was a real regression** — filed as BUG-095 and fixed. The
  reasoning failed in a specific, repeatable way: *a plausible mechanism that predicts the
  direction of a change was accepted as an explanation for its magnitude.* FTR.3g does predict
  less travel; it does not predict **4×**, and nothing checked whether the size was consistent
  with one extra smoothing stage rather than two. The measurement that settled it took one
  command — regenerate the fixtures with the source EMA disabled and read the number: 2.09 /
  1.80 / 15.10 against a design of 2.1 / 1.7 / 15.4, i.e. the constant was never stale at all.
  **Re-deriving the target would have written the regression into the doc as the new truth**, on
  a certified preset, with the gate that was built to catch exactly this failure reporting green.
- **Meniscus — a REAL DEFECT, now filed as BUG-094.** Not a stale target at all: it clamps
  `arousal` to 0…1 when the contract is −1…+1, so on calm material the arc lift dies and a
  beat-locked region goes silent. The gate was right to fail. **Re-baselining it would have
  laundered a genuine bug in a certified preset** — which is precisely the outcome this defect
  was originally filed to avoid, arrived at from the opposite direction.

---

### BUG-089 — `spectral_level_rise` shipped with a 22× analysis-rate dependence; its rate-invariance test passed (2026-08-17)

**Status: root-caused and fixed the same day, in the increment that shipped it (FTR.24a). The
consumer that exposed it was reverted separately.**

**How it surfaced.** Matt's live M7 on `2026-08-17T15-23-17Z`: *"Much worse now as the motion is
herky-jerky. Looks defective. Considerable regression."* Measured on that capture, the shipped
Fractal Tree size term against the build it replaced:

| | evt/rand | travel | peak \|v\| | jerk p99 |
|---|---|---|---|---|
| FTR.23 base only | 0.27× | 8.72 | 1.62 | 23 |
| FTR.24 with the accent | 2.37× | **31.88** | **17.37** | **589** |

**Root cause (read, not inferred).** `advanceLevelRise` measured the rise as
`levelDB − min(levelDB over the last 0.15 s)`. A minimum over a time window is not
rate-invariant: raise the analysis rate and (a) the window spans more frames, (b) each frame's
level is noisier because the hop — and therefore the RMS window — is shorter. Both push the
floor down, so the same music produces a larger rise at a higher rate. Measured on one capture's
`raw_tap.wav`, decoded once and analysed at four rates with the shipped constants:

| analysis rate | fires/s | non-zero | mean | floor window |
|---|---|---|---|---|
| 10.0 Hz | 0.03 | 16 % | 0.012 | 2 frames |
| 15.8 Hz (local files) | 0.04 | 37 % | 0.031 | 2 frames |
| 30.0 Hz | 0.26 | 61 % | 0.086 | 4 frames |
| 59.4 Hz (the tap) | **0.89** | 85 % | 0.184 | 9 frames |

FTR.24 calibrated against the 15.8 Hz column and Matt played back through the 59.4 Hz one.

**★★★ The test-adequacy finding, which is the part that generalises.** The suite HAD a
rate-invariance test and it was green. It asked whether a synthetic **+12 dB** step still fires at
10 Hz and 51 Hz — and a step that large saturates the band at every rate, so no rate dependence of
any magnitude could have failed it. **A rate-invariance test must compare a DISTRIBUTION on
realistic material — fire rate, duty cycle, mean — not whether one enormous input survives.** The
replacement (`levelRise_distributionMatchesAcrossAnalysisRates`) drives a repeating multi-size
amplitude pattern for 24 s of wall time at both real rates and asserts duty cycle and mean within
1.6×. It fails on the old formulation by a factor of 22.

**Fix.** A statistic with no sample-count term: a FIXED-LAG difference,
`preSmoothedLevelDB(t) − preSmoothedLevelDB(t − 0.15 s)`, where the level carries a short 40 ms
pre-smoothing so per-frame noise stops scaling with the hop (and ~19× shorter than the 0.76 s
`levelSmoothingTau` whose transient-erasing is why this field exists at all). Band re-derived to
2–7 dB, because a lag difference is a smaller number than a rise off a minimum — **swapping the
statistic without re-deriving the band is how the first version shipped.** The two real paths now
sit within 12 % (0.35 vs 0.41 fires/s; mean 0.098 vs 0.109).

**Residual.** The 10 Hz end is still ~2× off the others. It is the pre-BUG-087-partial-fix rate
and no current path runs there; if one ever does, the level needs a fixed-DURATION RMS window
rather than a per-hop one.

---

### BUG-085 — Main thread hangs in `CAMetalLayer.nextDrawable` ~3.6 min into a session (2026-08-04)

**P1 · renderer / app.hang / resource-management.**

**Expected.** The app renders continuously for the length of a session; the window stays responsive.

**Actual.** ~3.6 minutes in, the app freezes hard — no rendering, no UI response, force-quit required. Matt has now hit this repeatedly ("froze again").

**Evidence — a stack, at last.** Matt left the frozen app running instead of force-quitting, so `sample 42392 5` captured it live. **100 % of 4250 samples on a single stack, 0.0 % CPU:**

```
RenderPipeline.draw(in:) → renderFrame → drawWithFeedback → drawParticleMode
  → MTKView.currentRenderPassDescriptor → MTKView.currentDrawable
  → CAMetalLayer nextDrawable → CAMetalLayerPrivateNextDrawableLocked
  → _dispatch_semaphore_wait_slow → semaphore_timedwait_trap
```

Every other thread is idle — audio, caulk, CVDisplayLink all in normal waits. **No thread holds a Metal command buffer, waits on `waitUntilCompleted`, or blocks on a mutex.** So this is not a GPU hang and not a cross-thread deadlock: the drawable pool is exhausted and nothing is returning drawables to it. Because the main thread never returns to the run loop, the window is dead rather than merely frozen mid-frame.

**Reproduction.** Not deterministic yet. Observed on session `2026-08-04T17-49-50Z` (Witchlight, "Hummer"), 12,911 frames ≈ 3.6 min. Frame timings were **steady right up to the final frame** — `frame_cpu_ms` p50 20.80, `frame_gpu_ms` p50 10.62 across the last 50 — with no upward drift. An abrupt stop after healthy frames is the signature of pool exhaustion (leak N drawables, run fine until the pool empties, then block forever), not of a progressive stall.

**Probably not a new defect, and probably not Witchlight's.** The ~3.6 min timing matches the **unreproduced "~3.7 min crash"** logged against Volumetric Lithograph certification, and BUG-060 is a one-off hang filed with "no stack captured". All three are plausibly one bug. Nothing in the stack is preset-specific below `drawParticleMode`, which every `particles` preset shares.

**Already ruled out.**
- `drawParticleMode` leaking directly — it acquires and unconditionally `present`s on every path.
- The inflight semaphore — the hang is *past* `context.inflightSemaphore.wait()`, so a slot was available.
- A GPU hang or a stuck completion handler — no thread is waiting on either.

**Failure class.** `resource-management` (a finite pool acquired without a guaranteed release path).

**Suspected direction, NOT yet confirmed.** Something acquires a drawable outside the committed command buffer's lifetime, or retains `drawable.texture` past presentation. The session-recording hook in `draw(in:)` reads `view.currentDrawable` a second time and hands `drawable.texture` to a consumer, which is the shape of thing that would do it — but that is a hypothesis, and three hypotheses have already died on this preset today. It gets confirmed against an artifact before any fix.

**Investigation so far (2026-08-04) — leading hypothesis, still UNPROVEN.**

Ruled out by inspection after the stack: the capture hook does not retain the drawable (it blits into a separate texture inside the same command buffer, and with video recording off — as this session's log confirms — `ensureCaptureTexture` returns nil so it does nothing at all); the `willRenderActiveFrame` preset-swap skip still commits its command buffer, so skipped frames do not leak; and **display sleep is excluded** — `pmset -g log` shows `coreaudiod` held `PreventUserIdleDisplaySleep` for the full 33 minutes spanning the freeze.

**What that leaves, and it is a real gap regardless of this hang:** the app has **no occlusion handling of any kind**. `MetalView.swift` sets `view.isPaused = false` and nothing anywhere observes `NSApplication.occlusionState`, `windowDidMiniaturize`, or window visibility. Rendering therefore continues into a layer that may not be composited — and a `CAMetalLayer` whose window is minimised or fully occluded stops recycling drawables, which makes `nextDrawable` block exactly as observed. It fits every measured fact: hard block, 0 % CPU, nothing else holding, healthy frames right up to the stop.

**REFUTED 2026-08-04 — do not spend time here again.** Matt ran the repro and left the instance alive; sampled at **7 min 11 s elapsed**, twice past the ~3.6 min mark, with every `PhospheneApp` window reporting `onScreen=false` via `CGWindowList`. The app was **not hung**: 0 of 4145 main-thread samples in `nextDrawable`, 49 % CPU, session still live (stem separation running). The control is the decisive part — **the draw loop was entirely absent** (0 samples in `RenderPipeline.draw`, `MTKView draw`, `drawParticleMode`, `currentDrawable`). When the window is not composited macOS stops the draws rather than letting them block, so rendering-into-an-uncomposited-layer is not a state this app can reach, and occlusion cannot be the cause. The missing occlusion handling is still a (minor) gap, but it is **not** this bug.

**Pre-HANG.1 conclusion (2026-08-04).** The original capture stands unexplained: main thread hard-blocked in `nextDrawable` at 0 % CPU with every other thread idle, ~3.6 min in, after frames that were healthy to the last one. Drawables are being retained by something that is not the render path, not the capture hook, not the preset-swap skip, not the inflight semaphore, and not window state. At that point there was no current hypothesis; the next step was instrumentation that counts drawables acquired against command buffers completed, rather than another guess.

**Status 2026-08-05 — HANG.1 + HANG.2 COMPLETE; BUG-085 remains OPEN.** Instrumentation merged to
`main` through PR #37 (source `f81c36cb`, merge `c54a2e7c`); the required `fast-gate` passed.
HANG.1 gathered no reproduction and made no diagnosis or fix claim. Every
drawable-facing render path now routes its existing `currentRenderPassDescriptor`,
`currentDrawable`, and `present` calls through `DrawableLifecycleProbe`, which correlates the
request site and unique drawable identity with its command buffer's commit and completion.
An independent watchdog writes a balance heartbeat to `session.log` every 600 completions,
logs command-buffer failures or completed frames with unpresented acquisitions immediately,
and emits `DRAWABLE_LIFECYCLE STALL` after a request remains pending for 500 ms. The watchdog
does not depend on the blocked render/main thread, so the next reproduction will identify the
exact request site and the last known acquired/presented/completed balance. State-machine tests
cover balanced duplicate lookups, pending-site/age capture, and failed unpresented completion.
`Scripts/capture_hang.sh` now extracts the lifecycle lines explicitly.

**HANG.2 non-reproduction control (2026-08-05).** Two visible Witchlight/local-file runs
completed cleanly: a full 6 min 50 s Hummer control (24,866 frames) and a 10 min 36 s soak
through two track transitions (35,297 frames at the final snapshot). Both passed the original
~3.6-minute / 12,911-frame failure point. The final durable lifecycle heartbeat balanced
34,811 unique acquisitions with 34,811 presentations, with zero command-buffer failures,
unpresented acquisitions, stalls, or imbalances; process memory remained stable. This refutes
a deterministic per-frame drawable leak and a fixed ~3.6-minute exhaustion time. It does not
identify the intermittent owner and does not justify a render change. Full evidence:
`docs/diagnostics/BUG085_HANG2_SOAK_2026-08-05.md`. On the next live freeze, leave the process
running and execute `Scripts/capture_hang.sh` before force-quit.

**The original note, kept for the record:**

**It was NOT confirmed, and was not fixed on that basis** (the BUG-063/064 rule: no fix for an unreproduced hypothesis). Reproduction was attempted and could not be completed headlessly — the render loop only runs with an active session, and `osascript` lacks assistive access on this machine, so the window could not be driven from a script.

**Next reproduction.** Do not schedule another identical soak: HANG.2 established the clean
control. If the app freezes during ordinary use, leave it running and execute
`Scripts/capture_hang.sh` before force-quit; the capture includes the last 20
`DRAWABLE_LIFECYCLE` records, the blocked request site, and acquired/presented/committed/completed
balances. Do not repeat the occlusion experiment; that hypothesis is refuted above.

**`Scripts/capture_hang.sh` added** so the next freeze is captured in one command instead of improvised: stack, process state (0 % CPU distinguishes a block from a spin), window occlusion state, power-event log, and the session tail. **Run it BEFORE force-quitting** — a force-quit destroys the only evidence, which is why BUG-060 sat unactionable for months.

**Phase verification.** HANG.1 automated criteria are complete: lifecycle state-machine tests
cover balanced duplicate lookups, pending request site/age, and failed unpresented completion;
the app suite, renderer golden hashes, strict lint, documentation gates, and CI `fast-gate`
passed. HANG.2's ≥10-minute particle-preset soak and full-track manual run are complete; both
were clean non-reproductions. The minimised-window check is retired because the occlusion
hypothesis was experimentally refuted. BUG-085 remains open pending a frozen instrumented
capture.

---

**2026-08-05 — THE FROZEN INSTRUMENTED CAPTURE, at last.** Session `2026-08-05T21-21-03Z`
(Fractal Tree on Cherub Rock, local file). Matt left the app frozen; two independent runs of
`Scripts/capture_hang.sh` 98 s apart are preserved at
`~/Documents/phosphene_sessions/_freeze_captures/bug085_20260805T224531Z/` and
`…T224709Z/`.

**The stack is the same block, at a different site.** `drawWithMeshShader` →
`instrumentedRenderPassDescriptor` → `currentRenderPassDescriptor` → `currentDrawable` →
`nextDrawable` → `semaphore_timedwait_trap`, 100 % of samples, 0 % CPU. The 2026-08-04
capture blocked in `drawParticleMode`; this one in the MESH path. **The hang is not
preset-path-specific** — it is whichever path happens to ask for the drawable.

**What the instrumentation proves, and it is the important part.** The final heartbeat before
the freeze:

```
DRAWABLE_LIFECYCLE heartbeat frames=6013 descriptor=5905/5906 drawable=12045/12045
  unique_presented=6012/6012 command_completed=6012/6012 failures=0 unpresented=0
  pending=frame:6013,site:mesh.descriptor,age_ms:8
```

Every pair balances. **The app was holding ZERO drawables when `nextDrawable` blocked
forever.** That is not starvation-by-leak; CoreAnimation declined to vend a drawable to a
client that owed it nothing. HANG.2's 34,811/34,811 soak said the same thing from the
negative side; this says it from inside an actual freeze. **Direct app-side leakage is now
refuted twice, by independent methods — stop looking there.**

**Permanent, not slow.** The two captures 98 s apart report the identical frame (6013), site,
counters and `age_ms:8`. The `age_ms` is frozen because the heartbeat writer itself never ran
again — the render thread never took another step in 98 seconds.

**Only the render thread died.** `session.log` continues past the hang: stem separations 18
and 19 logged at 22:43:52 and 22:43:57, `SIGNAL_HEALTH` steady at −0.5 dBFS, `deadTap=false`.
Audio, ML and the analysis queues all ran on normally. Any hypothesis requiring a
process-wide stall (priority inversion on a shared lock, GPU device loss) is inconsistent
with this.

**Occlusion again NOT supported, and beware the tool.** `window_state.txt` shows the render
window (13229) `onScreen=true`, `alpha=1.0`, `901x633`, **COMPOSITED**. The other eight
windows it flags are `1920x30` and `1080x30` — menu-bar windows for secondary displays.
`capture_hang.sh` labelled every one of them "this is the BUG-085 occlusion condition",
which reads as confirmation of a hypothesis that was already refuted. (Label fixed in the
same increment as this note.)

**No display event.** `power.txt` has no display-sleep, wake, or reconfiguration entry
anywhere near the freeze; the only traffic is `coreaudiod` assertion churn five minutes
earlier.

**One lead, explicitly NOT a finding.** The stall began at 22:43:51, ~1 s before stem
separation #18. Stem separation is MPSGraph GPU work on a 5 s timer, so GPU contention
starving the compositor is mechanically plausible — but 17 prior separations in the same
session ran through cleanly, so this is a hypothesis to test, not a cause. A test would
suppress stem separation for a full session and see whether the freeze class survives;
BUG-061's rule forbids acting on it before that.

**What is now excluded:** app-side drawable leakage (twice), occlusion, display sleep,
preset-path specificity, and any process-wide stall. **What remains:** why CoreAnimation
withholds a drawable from a client holding none.

---

### BUG-070 — Failed tap reinstall leaves untruthful capture state; engine detectors starved (2026-07-12)

**P2 · audio.capture / resource-management.** From the 2026-07-11 ultra review (concurrency + audio dimensions); root cause verified in code at PUB.6.

**Expected:** after a failed device-change reinstall, the capture object's state reflects reality (not capturing), engine-side health classification can still fire, and a recovery restart can proceed.
**Actual (pre-fix):** `performReinstall`'s catch did nothing — its comment claimed "the create steps already tore down + stopped the monitor on failure," which was false on both counts. End state: `_isCapturing=true`, monitor running, zero IO callbacks → `SignalHealthMonitor.evaluate` (sample-driven, `ingest` window boundaries) never runs so `deadTap` never confirms; the router's `.silent` recovery is likewise callback-starved; `startCapture` recovery blocked by the alreadyCapturing guard. Only the app-layer Mode-B stall card (1 Hz poll on the tap frame count, ~10 s dwell) surfaced it — detection existed, engine truth and recovery did not.
**Fix (landed, PUB.6):** catch clears `_isCapturing` (unblocks stopCapture+startCapture recovery), monitor deliberately left running as a diagnostic beacon (later fires land in the SKIP branch and breadcrumb), comment corrected.
**Verification criteria:** automated — engine builds; audio suites green (a real failed reinstall cannot be staged headless: Core Audio create-step failures need a live device transition). Manual (pending): a live device-swap session confirming normal reinstalls still work (the G1 12/12 behaviour), and — if a reinstall failure can be provoked — the stall card appears AND a subsequent session restart recovers cleanly.
**Residual (documented, deliberately open):** the 3-queue lifecycle interleave (device-change reinstall vs silence-recovery reinstall vs user stop) is real but static-only evidence; the per-step breadcrumbs + install-generation probes are the instrumentation. Serialize ONLY on a reproduced interleave artifact — restructuring the G1-live-validated path on theory is the BUG-063 class.

---

### BUG-077 — `BeatGridResolver.snapToBeats` diverges from the Beat This! reference post-processor (2026-07-30)

**P3 · dsp.beat / api-contract.** Found at DBN.1 while auditing the resolver against the paper it implements.

**Expected:** `BeatGridResolver` implements Beat This!'s minimal post-processor. That post-processor's third step is *"move all downbeat predictions to the closest beat prediction"* — unconditional, no distance limit (Foscarin et al., ISMIR 2024).

**Actual:** `snapToBeats` applies `if nearestDist <= maxDistance`, where `maxDistance` comes from `snapFrames = 2` (40 ms at 50 fps). Any downbeat candidate further than 40 ms from the nearest beat is **discarded** rather than snapped.

**Currently harmless, and explicitly NOT the cause of the low downbeat F.** Measured at DBN.1 (`DownbeatStreamDiagnosticTests`): **100 % of downbeat candidates survive the gate** on money, billie_jean and solsbury_hill (median distance to nearest beat 0.0 ms; take_five 94 %). Nothing is being discarded today. The real cause of the 0.13–0.26 downbeat F is a near-degenerate downbeat *stream* — the model emits a confident downbeat on 69–90 % of beats on odd-meter tracks — documented in [`docs/design/DBN_DECODER_SPEC.md`](../design/DBN_DECODER_SPEC.md) §2.1. **This entry exists so a future session does not re-derive the divergence and mistake it for the defect.**

**Why file it anyway:** it is a genuine spec-fidelity divergence of the D-077 class (a paraphrased post-processor silently dropping data the reference keeps), and it becomes live the moment downbeat timing loosens — a track whose downbeat peaks sit two or three frames off the beat would have those downbeats deleted rather than snapped, and `computeMeter` would then divide a decimated set.

**Fix:** one comparison. Do it in **DBN.3**, when the resolver is being touched for the decoder A/B anyway — not as a standalone change, since it alters grid output and would need its own golden regeneration for no current behavioural gain.

**Verification criteria.** Automated: a resolver unit test with a downbeat candidate placed >40 ms from any beat, asserting it is snapped rather than dropped. Regression: `BeatGridResolver` goldens + the BeatBench offline-grid table unchanged on all 9 ground-truthed tracks (the fix should be a no-op on today's fixtures — if it is not, that is itself the finding).

---

### BUG-076 — Prep grid is window-position unstable on Bleed (a third of 30 s windows read wrong) (2026-07-27, CORRECTED 2026-07-30)

**Domain tag:** dsp.beat (grid tempo/meter). **Severity:** P2 — one track, but it is the defining case for category 4 (dense transients) and it demonstrates the program's central premise concretely.
**Status:** **Open — deferred by design, do not fix in isolation.** Owned by the beat-sync program (D-202): Phase DBN should dissolve it (a sequence decoder over the full activation timeline is not excerpt-dependent) and Phase FT removes the 30 s premise for local files. A targeted per-track patch here would be tuning against one fixture. *(Status line added at RECON.2, 2026-08-03 — this was the only §Open entry without one, so its disposition lived in prose and the index row alone.)*
**Resolved:** —

**CORRECTION (2026-07-30).** As first filed this bug claimed the grid "locks to a non-metrical tempo (3:2)" on Bleed, generalising from a single number in a session prep log (`bpm=174.6`) without re-measuring. Direct measurement at GT.3 falsified that: run on the fixture, the grid reads **115.00** — the correct value. The real defect is **sensitivity to which 30 s window is analysed**, which the original filing missed entirely. Recorded rather than quietly rewritten, because the mistake is instructive: a logged value is one sample, not a characterisation.

**Expected:** the prep grid returns the same, musically valid tempo regardless of which excerpt of a track it is given.

**Actual — nine 30 s windows of `bleed.wav`:**

| offset | BPM | beatsPerBar | barConfidence |
|---|---|---|---|
| 0 s | **115.00** ✓ | 4 | 0.50 |
| 30 s | 121.10 ✗ | 2 | 0.59 |
| 60 s | 116.88 ✓ | 2 | 0.62 |
| 90 s | **242.71** ✗ | 3 | 0.32 |
| 120 s | **166.09** ✗ | 3 | 0.45 |
| 150 s | 115.38 ✓ | 3 | 0.14 |
| 180 s | 115.07 ✓ | 2 | 0.48 |
| 210 s | 115.15 ✓ | 4 | 0.60 |
| 240 s | 114.92 ✓ | 2 | 0.64 |

Six of nine correct; three wrong across a **2.11× spread**. Ground truth is unambiguous — Matt's taps 226.7 (2:1 of the pulse), madmom 115.0, librosa 115.0, session drums-stem 115.1. `beatsPerBar` also swings 2/3/4 on a track that is 4/4 throughout.

**Control (matters — it bounds the defect):** Billie Jean over the same offsets reads 116.88 / 117.04 / 117.12 / 117.25 / 117.17, `beatsPerBar` 4 and `barConfidence` **1.00** at every window. So this is not a general instability; it is specific to dense-transient material where the activation function has energy at several subdivisions. Notably `barConfidence` already separates the two cases (0.14–0.64 vs 1.00) — the existing signal knows.

**Why the session logged 174.6:** the prep path analyses the 30 s Spotify preview, a mid-track excerpt, which fell in the unstable region. This is the plan's §2 premise made concrete: a grid built once from one arbitrary 30 s excerpt and extrapolated.

**Reproduction:** `swift run BeatBench --audio ~/phosphene_beatbench_fixtures/bleed.wav --seconds 30` for the whole file, or cut a window with `ffmpeg -ss <offset> -t 30` and pass that. Fixture sha256 in `Tests/Fixtures/beatbench/manifest.json`.

**Suspected failure class:** `algorithm` — `BeatGridResolver` peak-picking a dominant period from Beat This! activations without a sequence model. Palm-muted 16ths put comparable energy at several metrical levels, so the winner depends on the excerpt.

**Verification criteria (written before any fix):**
1. Automated: BeatBench window-sweep over Bleed — ≥ 8/9 windows within 5 % of a valid metrical level of 115.0, spread < 1.1×. Baseline is 6/9 and 2.11×.
2. No regression: suite 1 stays green (DBN.3 hard gate); Billie Jean's window sweep must remain flat.
3. Manual: Matt confirms beat-driven motion reads on-pulse on Bleed.

**Do not fix in isolation.** The fix is the Phase DBN sequence decoder (and Phase FT, which removes the 30 s premise for local files). A per-track heuristic would be the peak-pick patching the program exists to retire.

### BUG-065 — Live BeatGrid phase drifts off the audible beat over a track (mid-track drift convergence) (2026-06-29)

P3, `dsp.beat`. (Renumbered from BUG-064 on the GLAZE.8→main merge — BUG-064 was already assigned to the Lumen freeze; this beat-sync bug forked the number on `claude/nice-rubin-9c10c7`.)

**Expected:** the live beat phase stays within the ~60 ms perceptual window across a whole track, so frame-locked beat-driven motion (e.g. Glaze's GLAZE.7 downbeat push) reads tight start-to-finish.

**Actual:** the cached grid has the right BPM, but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it — drift grows ~11 ms (track start) → 50–70 ms (mid/late-track), with 28 % of frames exceeding ~60 ms. Evidence: session `2026-06-29T12-43-51Z` (Cherub Rock, 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; `lock_state=2` only 67 %-within-60 ms). NOT a functional break (phase is approximately right); it caps how *tight* beat-locked presets can feel (the live example: GLAZE.7 reads connected but loosens as the track plays).

**Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is mid-track drift *convergence* — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session.

**Status 2026-07-30 — OPEN. Root cause proven (TRK.1); both attempted fixes stopped at their own gates.**

- **TRK.1 (`07dd3bd9`) proved the mechanism.** The drift is a *ramp*, not noise: linear fit **−1.493 ms/s at R² = 0.844** on session `2026-07-30T15-39-21Z` (Hummer, 80.45 BPM), `grid_bpm` rock-constant ⇒ a **0.149 %** cached-grid period error (0.12 BPM). The legacy tracker is a first-order EMA on phase error — proportional-only, which has zero steady-state error against a step but *constant* error against a ramp. It can bound drift; it can never null it. That is exactly "bounds without tightening". A type-2 (PI) controller was implemented behind `PHOSPHENE_BEAT_PLL` and **failed real-fixture validation** — `LiveDriftValidationTests` (loveRehab) maxAbsDrift **101.5 ms** (limit 50), beat alignment **0.05** (limit 0.80). Default-off. **Strike 1 on the gain-tuning premise; do not retune gains against sub-bass evidence.**
- **TRK.2 stopped at its evidence gate — the drums-stem premise is FALSIFIED.** The proposed fix was to change the *evidence* (drums-stem onsets instead of sub-bass) rather than the gains. Measured on four captures with the production `StemSeparator` + a separate `BeatDetector` instance (D-075), bias-corrected: drums-stem sub_bass onsets landing within ±50 ms of a grid beat vs the full mix — love_rehab **16.9 % vs 42.2 %**, Hummer **11.0 % vs 14.4 %**, `bleed.wav` **22.4 % vs 22.3 %**, billie_jean **25.5 % vs 24.5 %**. Worse on two, a wash on two, *including Bleed* — the category-4 track the whole argument rested on. Best drums band anywhere: +2.5 pp, inside noise. **Larger finding:** across every capture, band and stem, only **~15–25 % of detected onsets land within ±50 ms of a beat** — FA #68 generalises, the spectral onset-detector family is weak beat evidence wherever it runs. **Second, independent blocker:** the live stem path (`VisualizerEngine+Audio.swift` `runPerFrameStemAnalysis`) deliberately carries **5–10 s of latency** with a sawtooth re-anchor every ~5 s, so drums onsets cannot be timestamped correctly by the tracker without a separate design that threads their true tap time through. No production code was changed. Evidence + reproduction: [`docs/diagnostics/TRK2_DRUMS_STEM_EVIDENCE_2026-07-30.md`](../diagnostics/TRK2_DRUMS_STEM_EVIDENCE_2026-07-30.md); instrument: `DrumsOnsetEvidenceTests` (env-gated).
- **Corroborated at scale by the GT.3 live baseline (2026-07-30).** `docs/diagnostics/BEATBENCH_LIVE_BASELINE_2026-07-30.md` measures the drift curve across 15 streamed tracks, and the growth this bug describes is the norm, not one capture: billie_jean 26 → 118 ms, stayin_alive 60 → 285 ms, money 20 → 241 ms, superstition 26 → 94 ms, clair_de_lune 39 → 135 ms by 30 s window. Only giorgio_by_moroder and pyramid_song hold flat. The program's live suite-1 target is **p90 < 30 ms**; the measured p90 is 102 ms on billie_jean and 269 ms on stayin_alive. This is systemic to the frozen single-BPM grid premise.
- **PARKED — Matt 2026-07-30 (D-206): "park the tracker, go DBN next session."** Two evidence sources and one controller topology have now been measured against the same frozen single-BPM grid, and the evidence layer has no headroom left. BUG-065 stays **open and bounded** (the visual falls up to ~119 ms behind late in a track; not a functional break); `PHOSPHENE_BEAT_PLL` stays default-off. Phase TRK is parked and TRK.3 has no content. The defect is now expected to be addressed — if at all — as a side effect of phase **DBN** replacing the frozen single-BPM grid premise, not by further tracker work. **Do not reopen TRK without a changed premise about the *grid*, not the tracker.**


---

### AUDIT-2026-06-09 — Full-codebase audit backlog (P2/P3 findings not individually filed)

**Status:** Open — index entry (P3 backlog only as of PUB.3: all four formerly-open P2 bullets below verified fixed in code, 2026-07-11). The 2026-06-09 six-agent full-codebase audit (~92k lines, all findings verified at file:line, cross-checked against this tracker and CLAUDE.md FAs) produced 6 P1s, 17 P2s, ~40 P3s. The P1s and three highest-impact P2s are filed individually below (BUG-030 … BUG-037). Everything else lives in **[`docs/diagnostics/CODE_AUDIT_2026-06-09.md`](../diagnostics/CODE_AUDIT_2026-06-09.md)** — treat that document as the evidence record when picking up any item. Remaining P2s in brief (full detail + fix shapes in the audit doc):

- ✅ **RESOLVED (CLEAN.3.2, 2026-06-17; re-verified in code at PUB.3)** — reactive orchestrator hard-exclusion filtering now present (`ReactiveOrchestrator.swift:~220`, exclusion-aware selection with the every-preset-excluded edge handled).
- ✅ **RESOLVED (CLEAN.3.3, 2026-06-17; re-verified at PUB.3)** — zero-duration fallback now routes through the scored/excluded path (`SessionPlanner+Segments.swift:~129`).
- ✅ **RESOLVED (CLEAN.3.x, 2026-06-17; re-verified at PUB.3)** — cooldown reset on track/session boundary (`LiveAdapter.swift:~369-378`).
- ✅ **RESOLVED (CLEAN.3.5, 2026-06-17; re-verified in code at PUB.3)** — in-memory StemCache now has an LRU cap (`maxEntries` + touch-on-track-change eviction, `StemCache.swift:~89-101`).
- **OAuth correctness (re-entrant `login()` leak, refresh double-spend, P3 hardening)** — ✅ **RESOLVED 2026-06-14 (CLEAN.2.2, commit `13cec8b`, integrated `a6f1288`).** Matt's live check passed: Spotify playlist loaded with no problems on the integrated `main` build — the refresh path exercised end-to-end against real Spotify, no regression. The fresh-login `state` guard is unit-test-proven + standard OAuth on unchanged callback routing (accepted without a forced interactive login per Matt 2026-06-14, since a silent refresh does not hit the consent round-trip). `SpotifyOAuthTokenProvider`: a second `login()` while one was pending overwrote `pendingContinuation` (orphaning the first caller until the 5-min timeout) + armed a stray timeout against the wrong attempt → now coalesces concurrent logins onto one in-flight attempt (`pendingContinuations` array; `finishLogin()` cancels the timeout on every resume path); concurrent `acquire()` each fired their own silent refresh, double-spending the rotating refresh token → now dedups onto a single in-flight `refreshTask`; + P3s (OAuth `state` CSRF/replay guard, form-body percent-encoding of `+ & = /` that `.urlQueryAllowed` leaked, Keychain-save failures logged not swallowed, callback `scheme == phosphene` + host validation). `SpotifyOAuthTokenProviderTests` green (4 new regressions).
- ✅ **RESOLVED (CLEAN.2.1, 2026-06-14)** — Spotify client secret baked into the built Info.plist. Removed `SpotifyClientSecret` from `Info.plist` + `Phosphene.xcconfig` and deleted its only consumer, the D-068 client-credentials `DefaultSpotifyTokenProvider`. The production flow already used OAuth Authorization Code + PKCE (`SpotifyOAuthTokenProvider`), which needs no secret; no build-bundled secret remains. OAuth login E2E confirmed by Matt 2026-06-14 on the integrated `main` build (no regression). See `RELEASE_NOTES_DEV.md [dev-2026-06-14-d]`.
- ✅ **RESOLVED (CLEAN.2.3, 2026-06-14)** — honest-UI dead controls (audit T5), each Matt's product call. **2.3.1:** the "Use Apple Music instead" no-op `{ }` cross-link (+ its dismiss-only mirror) now drive a real `NavigationStack` switch via `ConnectorPickerViewModel.switchConnector(to:)` (wire). **2.3.2:** the `.localFile` "coming later" capture mode (lying + no-op) removed — enum case, picker row, false string, and the now-unreachable reconciler/coordinator branches (remove; supersedes the `.localFile` branch of D-052). **2.3.3:** the disabled "Swap preset" context-menu stub hidden behind `#if ENABLE_PRESET_SWAP` until U.5b (hide). Commits `7800b72` / `d40cfad` / `6e983c8`. `RELEASE_NOTES_DEV.md [dev-2026-06-14-f]`.
- ✅ **RESOLVED (CLEAN.4.4, 2026-06-17)** — three renderer over-allocation / cache-key items from audit T7 (the `2026-06-13` audit's restatement of these P3s). (1) **PSO cache key** (`ShaderLibrary` cached by `name` alone, ignoring `pixelFormat`/`supportICB`): **finding = LATENT, not a live bug** — every production caller uses a **unique** name compiled once at init, preset multi-pass PSOs bypass the cache (`PresetLoader` → `device.makeRenderPipelineState`), and `supportICB: true` is test-only, so nothing currently collides; keyed correctly anyway by `PipelineKey(name, pixelFormat.rawValue, supportICB)` so a future name-reuse can't return the wrong-format PSO. (2) **wasted particle-mode warp pass** + (3) **unconditional feedback textures**: both gated to surface-mode feedback presets via `RenderPipeline.activePresetSamplesFeedback` — non-feedback + particle-mode presets allocate zero ping-pong (freed on `setFeedbackParams(nil)`), and particle mode skips the warp. Output-preserving (PresetRegression goldens byte-identical). Gates: `ShaderLibraryTests` +2, `DrawableResizeRegressionTests` +3. `RELEASE_NOTES_DEV.md [dev-2026-06-17-215601]`. (T7's remaining items — sceneTexture aliasing, resize stale-size, ray-march /height NaN, DynamicTextOverlay race — **were closed by CLEAN.4.3 and CLEAN.4.5, both completed 2026-06-18**; see `docs/diagnostics/CODE_AUDIT_2026-06-13.md`, where they are marked ✅, and `ENGINEERING_PLAN_HISTORY.md`. *Corrected at RECON.2, 2026-08-03: this line previously read "stay open under CLEAN.4.3/4.5", and since both increments have rotated out of the live plan the pointer was unresolvable from here — it read as open work with no owner.*)
- ✅ **RESOLVED (CLEAN.2.3.4, 2026-06-14)** — localization gate only scanned `PhospheneApp/Views/`. `check_user_strings.sh` ROOTS widened to `PhospheneApp/ViewModels` + `ContentView.swift`, pattern extended with a connection-state `.error("…")` arm (`logger.error` excluded); the bypassing copy (Spotify/AppleMusic error strings, ConnectorType tiles, ReadyViewModel duration/source, ContentView fallback, PreparationProgressView subtitle, PlanPreviewTransitionView labels) externalized to `Localizable.strings`. Gate header documents its honest scope limit (literal-prefix matcher — lowercase/interpolated fragments still rely on review). Commit `46d836b`.

P3 categories indexed in the audit doc: ~25 latent bugs (incl. OAuth refresh double-spend + form-encoding gaps [Resolved CLEAN.2.2, see above], PSO cache key, mv_warp buffer(5) omission, PostProcessChain texture aliasing, malformed-sidecar swallowing, Arachne listening-pose FA #57-gate, >2-channel LF corruption, ~94 Hz vs 60 fps chroma hysteresis), ~11 perf items (autocorrelation 2×/frame, drums FFT 2×/frame, mono STFT 2×/track, serial prep pipeline, wasted particle-mode warp pass, unconditional feedback textures), dead code, and 6 in-code doc-drift items.


---

**GT.3 addendum (2026-07-30) — the ramp is systemic, and one track is 14× worse.** BeatBench session-replay over the 15-track `beat-match-test-session` fits `drift_ms` against time for every track. Each is a linear **ramp**, confirming the TRK root cause (a period error a proportional-only controller can bound but never null) across the whole catalog rather than one capture:

| track | period error | R² | unlocks at | confident-wrong |
|---|---|---|---|---|
| **YYZ** | **+2.070 %** | **0.99** | 47 s | **90.8 %** |
| Dance Yrself Clean | −0.149 % | 0.79 | 58 s | 81.4 % |
| Bohemian Rhapsody | +0.126 % | 0.93 | 0 s | 76.9 % |
| Money | −0.081 % | 0.93 | 122 s | 64.1 % |
| Stayin' Alive | +0.083 % | 0.89 | 48 s | 84.0 % |
| (10 others) | < 0.07 % | — | — | 0–53 % |

**YYZ is the extreme case and it is real, not an artifact** (R² 0.99 over 15,898 frames): a 2.07 % period error accumulates to **4.8 seconds — about 11 beats — by the end of a 266 s track**, while `lock_state == 2` for 92 % of frames. The engine reports "locked" while eleven beats out of phase. Note Dance Yrself Clean's −0.149 % matches the period error TRK measured exactly.

**Two things this reframes.** (1) *Time-to-lock was the wrong metric.* Drift on these tracks starts **inside** the ±70 ms window (YYZ 52.7 ms, Dance Yrself 29.0 ms) and walks out, so "time to lock" reads 0 s and looks healthy; the informative number is **time-to-unlock**, and **13 of 15 tracks leave the window and never return** — only Solsbury Hill and Giorgio stay in. (2) *The suite-1 live target is far off.* Billie Jean's p90 is **102 ms** against a target of < 30 ms.

Evidence: [`BEATBENCH_LIVE_BASELINE_2026-07-30.md`](../diagnostics/BEATBENCH_LIVE_BASELINE_2026-07-30.md). Reproduce: `BeatBench --mode session-replay --session <dir>`.

### BUG-081 — App beachballs during session preparation; no crash report produced (2026-08-03)

**P2 · unclassified · OPEN — evidence only, root cause NOT established.** Reported by Matt from session `2026-08-03T22-54-06Z`; had to force-quit.

**Expected.** The app stays responsive throughout playlist preparation.

**Actual.** The UI froze/beachballed ~78 s into the session and required force-quit. Because it was force-quit rather than crashed, **no `.ips` exists** — the user and system DiagnosticReports directories contain no PhospheneApp report at all, and `session.log` ends mid-normal-operation at `22:55:24` with no fatal, assertion, or error line.

**What the artifacts DO establish — the renderer was healthy to the last frame.** From `features.csv` (3756 frames, ending t=82.1 s), by sixth of the session:

| segment | frame_cpu_ms | frame_gpu_ms | deltaTime |
|---|---|---|---|
| 1/6 | 11.51 | 2.91 | 47.8 ms (startup) |
| 4/6 | 1.53 | 0.15 | 16.7 ms |
| 6/6 | 6.84 | 0.18 | 16.7 ms |

Steady 60 fps, Fractal Tree costing **0.18 ms GPU against its 0.7 ms Tier 2 budget**, no degradation trend. Background load was rising but modest (`stem_analyzer_ms` 0 → 3.4, `mir_pipeline_ms` 0.84 → 2.09); `session.log` shows stem separation 10 in progress.

**Ruled out.** FTR.2's mesh shader overflowing the primitive limit via a bad `branch_count` — the hypothesis was tested and **falsified**: no non-finite values in the capture, and derived `branch_count` never exceeds 59 against the 63 ceiling. (A grep appearing to show `nan` was matching "co**nan**ce" in `tonal_consonance`.)

**Not yet established.** Everything else. A frozen UI with a healthy render loop points away from the preset and toward the main thread or the preparation pipeline, but that is an inference, not evidence — do not act on it (BUG-061 rule).

**Sub-finding, FIXED 2026-08-04 (`17ac02fc`): a crashed session left an unreadable `raw_tap.wav`.** The stub header declares a `data` size of 0 and the real sizes were patched in only on the 30 s cap or a graceful `finish()` — so every standard reader saw an empty file. Session `2026-08-04T20-23-15Z` had **28.8 MB of intact float samples behind a header claiming zero bytes**, making the capture useless for diagnosing the crash that produced it. `patchRawTapHeader` now also runs about once per second of audio. **NOT gated by a test:** `RawTapHeaderRecoveryTests` could not be made to run (constructing a recorder and abandoning it mid-capture either crashed the test process with signal 5 or produced no file); the fix reuses the existing patch routine and `test_rawTapCapture_persistsAfterDurationCap` still passes, but there is no regression guard. Worth a second attempt with fresh context.

**Next evidence needed — the one thing that would settle it.** A `sample` of the process while it is hung, which captures the blocked main-thread stack:

```
sample PhospheneApp 10 -file ~/Desktop/phosphene-hang.txt
```

Run it *during* the beachball, before force-quitting. Without a blocked stack there is no way to distinguish a deadlock from a GPU stall from a preparation-pipeline wedge.

**Note.** Signal health was `critical` (−24 dBFS) for the session's first ~50 s before reaching green; unlikely to be related but recorded because the session is otherwise the only artifact.

---

### BUG-088 — Aurora Veil's route manifest does not describe the preset (2026-08-12)

**Diagnosis only, no fix.** Found because BUG-086's `dsp.stem` manual gate was aimed at
Aurora Veil and returned nothing — for a reason that had nothing to do with BUG-086.

#### How the wrong preset got picked (the process failure, recorded first)

The gate was aimed here on a stale note calling `other_energy_dev` Aurora Veil's
"song-defining anchor, never drop it." **Git contradicts it**: added at `e7cd6e3a`
(AV.2.2f), dropped at `e305839a` (AV.2.h, "drop 5 routes"), and **AV.7 / D-185 reauthored
the preset as a nimitz *Auroras* port onto mood envelopes rather than deviation
primitives** — deliberately, for a GENTLE preset. Aurora Veil declares **no stem route at
all**, so no stem-latency change could ever have shown up in it. A human review was spent
on a question a CSV could have answered first. `Scripts/check_route_liveness.py` exists so
that does not recur: **run it before aiming any manual review at a preset.**

#### Expected behavior

A preset's `audio_routes` manifest enumerates the primitives it reads, with a `kind` that
describes how each is used. QG.1 / D-180 route coverage depends on it being accurate.

#### Actual behavior — measured on capture `2026-08-12T19-57-29Z`

| route | declared | verdict | detail |
|---|---|---|---|
| `star_beat_twinkle` / `barPhase01` | ✅ accent | **ALIVE** | range 901 / 1000 |
| `star_beat_twinkle` / `pulseAmp01` | ✅ **continuous** | **DEAD** | pinned 1.000, p5–p95 range **0.000** |
| `veil_breathe` / `arousal` | ✅ | ALIVE | range 0.178 |
| `veil_breathe` / `bassAttRel` | ✅ | ALIVE | range 0.287, near-entirely negative |
| `mood_colour` / `valence` | ✅ | ALIVE | range 0.453 |
| `drumsEnergyDev` | ❌ **undeclared** | ALIVE | 61 % nonzero, p95 0.997 |
| `vocalsPitchHz` | ❌ **undeclared** | SPARSE | **0.1 % nonzero** |
| `vocalsPitchConfidence` | ❌ **undeclared** | SPARSE | **0.1 % nonzero** |

**`pulseAmp01` is not misbehaving.** The shader uses it as a silence gate, and a gate
pinned at 1.000 through music is exactly right. The defect is the **declaration**:
`kind: continuous` reads as a driver, and WL.1 already measured this primitive as a silence
gate with no dynamic range and ruled it out as a hero driver. That lesson did not propagate
into this manifest.

**The real gaps** are the three undeclared reads. `drumsEnergyDev` is Aurora Veil's only
live stem input and QG.1 cannot see it; the vocals-pitch pair is garnish at 0.1 % — WL.1
measured the same primitive at 4.5 % and called it garnish there too.

#### Suspected failure class

`documentation-drift` primarily (manifest vs code), `calibration` secondarily (a primitive
declared as a driver that cannot drive).

#### Matt's M7, and what it does and does not mean

> *"I don't really see how the preset responds to music beyond the flickering of the stars
> once per bar. The veil is just aurora-ing."* (2026-08-12)

The measurement explains it precisely: **only `barPhase01` has large dynamic range.**
Everything else is a slow narrow mood envelope (0.18–0.45) or effectively dead. The bar
flicker he sees *is* `star_beat_twinkle` working.

**Whether that is a defect or the design is Matt's call, not a measurement.** AV.7 / D-185
chose mood envelopes over deviation primitives for a GENTLE preset and Matt certified it on
2026-07-19. "Reads as uncoupled" may be the intended register. What is objectively wrong is
the manifest. Flagged, not resolved.

#### Verification criteria (before any fix)

- The manifest matches what the code reads — ideally mechanized, since a hand-maintained
  list drifted here on a certified preset.
- `kind` distinguishes a **gate** from a **driver**, so a silence gate cannot be declared as
  continuous coupling again.
- `RouteCoverageTests` sees `drumsEnergyDev` for Aurora Veil after the fix.
- If Matt decides the coupling itself is too weak, that is a **separate** preset increment
  with its own M7 — not a manifest fix.

#### Related

**⇄ BUG-086** — this is why that entry's `dsp.stem` gate is still owed. Re-aimed at
**Skein**, verified first: 20 of 28 routes ALIVE, **all eight stem-deviation routes alive**
(`painter_speed` and `flick_trigger` on all four stems, ranges 0.60–1.39), zero DEAD.

### BUG-087 — Local-file playback analyses at 10 Hz where streaming analyses at 51 Hz (AVAudioEngine ignores the tap `bufferSize`) (2026-08-11)

Found while chasing a `beatPhase01` discrepancy across captures. **Diagnosis increment
only — no fix code.**

#### Expected behavior

The MIR chain analyses at a comparable rate whichever way audio arrives.
`LocalFilePlaybackProvider` requests `installTap(onBus: 0, bufferSize: 1024, …)`, which at
44.1–48 kHz is ≈43–47 Hz.

#### Actual behavior

**Local-file playback analyses at 10.0 Hz. Streaming analyses at 51.1 Hz.** A 5.1× rate
loss, on the session type used for essentially all development and all preset work.

#### Reproduction steps

Any local-file session vs any streaming session. Measured across the whole capture corpus
(10 local-file captures, 1 streaming).

#### Session artifacts

`beatPhase01` advance rate × the CSV's own frame rate gives the analysis rate directly:

| capture | path | audio Hz | analysis Hz | implied buffer |
|---|---|---|---|---|
| `2026-08-11T01-07-17Z` | local | 44 100 | 9.99 | **4414 frames** |
| `2026-08-11T23-52-49Z` | local | 48 000 | 9.98 | **4808 frames** |
| `2026-08-11T23-44-40Z` | local | 48 000 | 9.98 | **4810 frames** |
| `beat-match-test-session` | streaming | 48 000 | **51.11** | **939 frames** |

All ten local-file captures read 15.2–16.8 % (16.7 % on eight of ten). The streaming capture
reads 85.4 %.

**The discriminator that makes this a diagnosis and not a correlation:** if the tap delivered
a fixed *frame count*, the analysis rate would differ between the 44.1 kHz and 48 kHz
captures. It does not — 4414 frames at 44.1 kHz and 4808 at 48 kHz are both **exactly 0.1 s**.
The buffer is duration-based, so the `bufferSize: 1024` request is being ignored, not merely
rounded. The streaming path's 939 frames ≈ the 1024 the system tap actually honours.

⚠ **Path and date are perfectly confounded in the corpus** (the sole streaming capture is
2026-07-27; every local-file capture is 2026-08-07 or later), so the *captures alone* cannot
separate "local-file path" from "something regressed in August". The code and the
rate-independence discriminator are what settle it, plus the streaming capture's
`TAP: startCapture: ENTER → createProcessTap` lines, which no local-file capture has — they
are genuinely different audio sources, not the same source at two dates.

#### Suspected failure class

`calibration` — intent (1024 frames) versus reality (~4800), unverified at the boundary.
`api-contract` secondarily: AVFoundation treats `installTap`'s `bufferSize` as a hint, and
nothing here checks what was actually delivered.

#### Root cause (read from source)

- `PhospheneEngine/Sources/Audio/LocalFilePlaybackProvider.swift:292` —
  `player.installTap(onBus: 0, bufferSize: 1024, format: tapFormat)`. AVAudioEngine honours
  this loosely and delivers ~0.1 s buffers on macOS.
- `PhospheneApp/VisualizerEngine+Audio.swift` `processAnalysisFrame` — invoked once per audio
  callback via `analysisQueue.async`, with **no time-based gate**, and it derives
  `effectiveFps = 1 / dt` from the callback interval. So the callback rate *is* the analysis
  rate, and `dt` correctly reports 0.1 s; nothing is lying, the rate is simply low.
- `handleTapBuffer` is **not** at fault: it resizes `interleavedScratch` when a buffer exceeds
  the 1024-frame allocation, so no samples are dropped. Checked, because a scratch sized 1024
  against a 4800-frame buffer would have been the more serious bug.

#### Impact

Every `FeatureVector` consumer on the local-file path sees 10 Hz: bands, the D-026 deviation
primitives, `beatPhase01`, centroid, flux, and the mood classifier's inputs. This is the same
10 Hz the FTR program discovered from the preset side and carried as a preset-authoring fact;
it is a pipeline property, and it is path-specific.

**For a beat-ruled scrolling preset (Stave / the CHR series) it is a design input**, not a
footnote: gridlines and trace samples would arrive in 100 ms steps on the path that preset
would mostly run on.

**A lead was recorded here and is now REFUTED (2026-08-12).** It read: this may also explain
BUG-086's local-file stem/band correlation of r 0.19–0.46 against streaming's 0.70–0.94, since
stems and bands would be sampled on different clocks. Both halves failed. Stems and bands are
on the **same** clock within a path (streaming `beatPhase01` 85.4 % / stems 97.1 %; local
16.7 % / 14.6–16.0 %), so the proposed mechanism does not exist. And step-holding the streaming
capture's series down to 10 Hz — injecting this defect into strong-r data — barely changes the
result (r 0.788→0.783 … 0.937→0.938, 5.4 s lag intact). **10 Hz does not explain BUG-086's weak
correlation**, and this fix should not be expected to improve it. Kept as a record so the lead
is not re-run; detail in BUG-086's refuted-hypothesis list.

#### Verification criteria (written before any fix)

- Automated: assert the delivered buffer's `frameLength` against what was requested at the
  `installTap` boundary, so an ignored hint fails loudly instead of silently costing 5× rate.
- Automated: an analysis-rate floor measured from a real capture, the same shape as
  `Scripts/measure_stem_latency.py` — `beatPhase01` advance × CSV fps ≥ target.
- Manual: any fix raises the update rate of every deviation primitive on the local-file path,
  which is felt on every preset. M7-class observation required; a 5× change in feature update
  rate is not a silent change.

#### Fix attempted — PARTIAL, and the remedy was wrong (BUG087.2/.3, 2026-08-13)

**Measured on capture `2026-08-13T13-15-36Z`: 10.0 Hz → 16.4 Hz. The ≥ 40 Hz done-when is
NOT met**, and not for a tuning reason.

**What landed and works.** `BUG087.2` moved the analysis time base off wall-clock onto the
audio each callback carried (`frames / rate`) — behaviour-neutral, verified by the full suite
moving **zero** existing expectations, and a prerequisite for producing several analysis
frames per callback. `BUG087.3` slices each delivered buffer into 1024-frame pieces.

**Why it falls short.** Slicing raised the *computation* rate to ~47 Hz but not the rate a
preset observes. All five slices of a buffer complete within microseconds — they process
already-buffered audio, not audio arriving in real time — so the render loop samples ~1.6 of
them as distinct values and supersedes the rest. The gap distribution is bimodal and
unambiguous: **39 % of value changes are 1 render frame apart, 55 % are 5–6 frames
(84–101 ms) apart.** A burst against a 100 ms arrival period.

> **The binding constraint is how often audio ARRIVES, not how finely it is sliced.** A preset
> cannot observe more distinct values per second than buffers are delivered, when every slice
> of a buffer lands at the same instant.

**Kept anyway (Matt's call):** effective rate 10 → 16.4 Hz (+64 %), and fresher values — the
last slice reflects the newest 1024 samples rather than a position inside a 4410-frame buffer,
a latency gain even where the rate did not move. Cost: ~5× the per-callback allocation on the
audio thread, landing at ~47/s — the rate the system-tap path has always run at.

**The remaining route is smaller buffers from AVAudioEngine** — manual rendering mode, an
`AUAudioUnit` render block with a smaller `maximumFramesPerSlice`, or tapping a different
node. BUG087.1 measured that a plain `installTap(bufferSize:)` request is ignored. **Filed as
its own increment, not a follow-on commit. BUG-087 stays OPEN.**

⚠ A regression test here asserted `hz >= 40` from slice count and **passed**, while the live
capture measured 16.4 Hz — it was measuring the computation rate and calling it the delivered
rate. Renamed and re-scoped, because a green tick against a refuted claim is worse than no
test.

#### Related

**⇄ BUG-086** — same subsystem boundary, independent cause. The lead that this entry might
explain BUG-086's weak local-file correlation is **refuted** (see Impact). A fix here should
still re-run `Scripts/measure_stem_latency.py` on a local-file capture before and after — not
because the correlation is expected to improve, but so the claim is checked rather than assumed.

### BUG-086 — Per-stem features reach presets ≈5.4 s late; lag is structurally pinned to the separation period (2026-08-11)

Found while measuring driver viability for a plotting preset (CHR.1), where the
lag is disqualifying rather than cosmetic. **Diagnosis increment only — no fix
code.** Full measurement and method: `docs/diagnostics/CHR1_STEM_DECORRELATION_2026-08-11.md`
§7b (evidence) and §8 (root cause + the fix trade).

#### Expected behavior

Per-stem features (`{stem}Energy`, `…EnergyRel`, `…EnergyDev`, onset rate,
centroid, attack ratio, slope) describe the audio the listener is hearing now,
to within roughly the same tolerance as the real-time band features.

#### Actual behavior

They describe audio from **≈5.4 s ago**, steady state, on the local-file path.
The real-time band features (`bass`/`mid`/`treble`) are correct to 0.2–0.4 s, so
a preset reading both gets two clocks that disagree by 5 s.

#### Reproduction steps

Any local-file session ≥ 90 s. Measured on `beat-match-test-session` (16
full-length tracks) and `2026-08-11T01-07-17Z` (*Cherub Rock*).

#### Session artifacts

Three independent measurements, all agreeing, escalating in cleanliness:

1. Tap cross-correlation, cold start (30 s tap): bands peak at −0.30…+0.08 s;
   stems have no peak inside ±3 s, and a single broad unimodal peak at ≈10 s
   (r +0.58) when widened to ±20 s.
2. Tap cross-correlation, steady state (full 2.04 GB tap, four 60 s windows ≥ 90 s
   into a track): control `bass` peaks at **0.20–0.40 s** — alignment confirmed —
   while every stem peaks at **5.61 / 5.81 / 5.61 / 5.61 s**.
3. CSV-internal, no WAV: each stem feature against the time-aligned `bass+mid`
   sum, both at 60 Hz — **5.4 s on 39 of 40 stem × track pairs**, r up to +0.94.

Corroborates TRK.2's independent 5–10 s finding.

#### Suspected failure class

`calibration` — a deliberate offset whose cost was never measured, not a coding
error. Every line below does what it says it does.

#### Root cause (read from source, not inferred)

- `VisualizerEngine+Stems.swift:49` — `timer.schedule(deadline: .now() + 10, repeating: 5.0)`: separation every **5 s**.
- `VisualizerEngine+Stems.swift:166` — `stemSampleBuffer.snapshotLatest(seconds: 10, …)`: the chunk is the latest **10 s**, so chunk sample 0 is audio from 10 s ago and the chunk's end is "now".
- `VisualizerEngine+Audio.swift:333` — `let startSample = Int(5.0 * sampleRate)`: the per-frame read window starts **5 s into** the chunk, i.e. at audio already 5 s old, then advances at real time.

So `lag = chunkLength − startOffset`, and the read can only advance for
`chunkLength − startOffset` seconds before clamping at the chunk's end — which
must cover one separation period. Hence:

> **lag ≥ separationPeriod.** The 5 s head start is exactly the runway needed to
> survive one 5 s period. It is not slack.

**Chunk length is not a lever.** `StemSeparator.modelFrameCount = 431` is
commented "Fixed number of STFT frames the model expects" → `requiredMonoSamples
= 440320` ≈ 10 s at 44.1 kHz. Shortening the chunk needs a re-exported model.

#### The fix trade

Reducing lag means reducing the separation period, at one full inference per
period (cost fixed, because the model always consumes 10 s):

| period | resulting lag | inference duty |
|---|---|---|
| 5 s (today) | ≈5 s | ≈2.8 % |
| 2 s | ≈2 s | ≈7.1 % |
| 1 s | ≈1 s | ≈14.2 % |

`startSample` must move to `chunkLength − period` in the same change, or the read
clamps and the features freeze between separations (a stutter, which for a
plotting preset is worse than the lag).

⚠ **The 142 ms inference figure is the code comment at `VisualizerEngine+Stems.swift:211`,
not independently measured** — no session artifact records separation cost, so
the duty column is an estimate. Measuring it is step 1 of any fix increment.
⚠ `MLDispatchScheduler` (D-059) already defers dispatch when frames run over
budget, with a 2 s ceiling. At short periods deferral becomes common, so
worst-case lag is `period + deferral`, not `period`.

#### Verification criteria (written before any fix)

- Automated: the CSV-internal measurement above, as a gate — stem features must
  track the `bass+mid` band sum at a lag below the chosen target on a real
  capture. Reuses recorded sessions, no new fixtures.
- Automated: no regression in `stem_analyzer_ms` / frame budget; `MLDispatchScheduler`
  deferral rate recorded before and after.
- Manual: `dsp.stem` requires observed musical connection. Any change to stem
  timing is felt on every stem-driven preset — Aurora Veil (whose
  `other_energy_dev` route is load-bearing), Skein, Meniscus, FFO — so M7-class
  observation on at least Aurora Veil before it is called fixed.

#### Fix — code-complete 2026-08-11, NOT yet validated

Period 5.0 s → **2.0 s**, and the read start **derived** from it rather than being a
fourth independent literal:

```
stemChunkSeconds            10.0   (pinned to the model, asserted against
                                    StemSeparator.requiredMonoSamples)
stemSeparationPeriodSeconds  2.0   (was 5.0)
stemReadMarginSeconds        0.5   (slack for inference + D-059 deferral)
stemReadStartSeconds         7.5   (derived: chunk − period − margin)
→ nominal latency            2.5 s (was ≈5.4 s measured)
→ inference duty            ≈7 %   (was ≈2.8 %; estimate, see below)
```

Margin is deliberately > 0: clamping is **not** a stale freeze — the window pins to
the chunk's *newest* audio, so latency momentarily collapses toward zero and jumps
back when the next chunk lands, which reads as a glitch rather than a lag.

`STEM_SEPARATION: inference=…ms period=…s duty=…% nominal_latency=…s` now goes to
`session.log` every separation, so the duty estimate above becomes checkable from a
capture — it previously rested on a 142 ms figure that existed only in a code
comment, which is why the pre-fix cost was never verifiable.

`StemSeparationCadenceRegressionTests` (7 tests) asserts the *relationship* rather
than the values — runway ≥ period, margin > 0, latency < 3 s, read start derived,
chunk pinned to the model — so retuning the cadence stays free while re-breaking the
invariant does not.

**The gate was verified to bite, not merely to be green.** Setting the period back
to 5.0 and re-running fails the latency test with
`stemNominalLatencySeconds → 5.5 < 3.0` — so the suite would have caught the pre-fix
configuration. A green assertion that also passes against the defect is worthless;
this one was checked against it.

**Automated verification complete (2026-08-11):**

- `swiftlint --strict` — 0 violations, 503 files
- `xcodebuild build` — succeeded
- Engine suite — **1809/1810**; sole failure is the pre-existing DOC.6 rotation gate,
  identical to the branch point
- App target — **411/411** (404 before this change, plus the 7 new tests; no existing
  test moved). Required quitting a live `PhospheneApp` first — **BUG-072**.

**Measured latency is NOT yet verified, and the constants test does not verify it.**
`StemSeparationCadenceRegressionTests` gates the arithmetic that *produces* 2.5 s; it
cannot observe what the pipeline delivers. `Scripts/measure_stem_latency.py <capture>`
does, from a real session:

```
Scripts/measure_stem_latency.py ~/Documents/phosphene_sessions/<capture>
```

It cross-correlates each stem's `energyRel` against the time-aligned `bass+mid` band
sum (both at ~60 Hz, CSV only — no WAV, whose per-capture sample rate differs and
silently scaled the time axis by 8.8 % in an early version of this measurement),
reports per-stem lag with correlation strength, and PASS/FAILs against a 3.0 s
ceiling. Validated against the pre-fix corpus: 15 of 15 `beat-match-test-session`
segments report **5.4–5.5 s**, matching the original finding. It also detects a
pre-fix capture from the absence of `STEM_SEPARATION` and says so, so a stale capture
cannot be misread as a regression.

*Its verification-criteria form was corrected in building it.* This entry originally
specified "an automated gate". The lag is a live-pipeline property of the ML timer,
wallclock advance and `MLDispatchScheduler` deferral — no unit test can synthesize it,
and a synthetic one would be the green-test-measuring-the-wrong-thing trap. The honest
artifact is a measurement over a capture a human supplies.

#### Post-fix captures — two sessions, 2026-08-11 (`23-35-27Z`, `23-44-40Z`)

> **⚠ TWO CORRECTIONS, in order.**
>
> **(a)** This section first reported "measured lag 5.4 s → 2.9 s, PASS" from a single capture.
> That single-capture PASS rested on r 0.42/0.48 with no peak behind it and squeaked past a
> `MIN_R` floor of 0.40. The floor is **0.60** now, and no single short capture clears it.
>
> **(b)** The withdrawal then over-corrected. The 5.4 s baseline came from a **streaming**
> capture while every post-fix capture is **local-file**, so the two were never comparable —
> but the corpus also holds a *pre-fix local-file* capture, and comparing like with like the
> fix does hold: **5.2 s → 2.9/3.0 s across two independent post-fix captures.** Weak
> correlations make each number soft; three same-path captures agreeing does not.
>
> What remains genuinely unmeasured is the **streaming** path post-fix — the path the clean
> baseline came from. The duty figures are direct log readouts and unaffected throughout.

**Correlation quality tracks the PLAYBACK PATH, not capture length** (corrected 2026-08-11
after Matt pointed out the 16-track corpus is a *streaming* playlist, which this entry had
recorded as local files):

| real capture | path | duration | best r | best lag |
|---|---|---|---|---|
| `beat-match-test-session` (pre-fix) | **streaming** | 88 min | **0.70–0.94** | 5.4 s |
| `2026-08-11T01-07-17Z` (pre-fix) | local file | 255 s | 0.193 | 5.2 s |
| `2026-08-11T23-44-40Z` (post-fix) | local file | 137 s | 0.372 | 3.0 s |
| `2026-08-11T23-52-49Z` (post-fix) | local file | 102 s | 0.462 | 2.9 s |

Length is not the driver: the 255 s local-file capture reads *worse* than the 102 s one.

⚠ **`fixturegen-*` are not evidence.** They read r 0.886–0.975 at lag **0.0 s**, which is
tempting and wrong: they carry no `raw_tap.wav` and their logs say
`fixture=<file> stems=StemSeparator(MPSGraph)+StemAnalyzer hop=1024` — offline generation
runs where features and stems are computed in lockstep from the same file, so zero lag is an
artifact of the method. Excluded from every number here.

**Same-path comparison — this IS like-for-like, and the fix holds.** Local-file pre-fix
**5.2 s** → local-file post-fix **3.0 s and 2.9 s**, two independent captures agreeing,
against a predicted 5.4 → 2.5 s nominal shift. The correlations are weak on this path, so each
number alone is soft; three same-path captures agreeing on a ~2.2 s reduction is not.

**Why local-file correlations are weak (0.19–0.46) where streaming reads 0.70–0.94 is
UNEXPLAINED, after five tested and refuted hypotheses.** Listed so none is re-run:

1. *Clamping degrades the features* — refuted. Correlation on clamped vs unclamped frames is
   identical (drums 0.388 vs 0.381; bass 0.413 vs 0.368).
2. *The reference signal is too flat* — refuted. Post-fix reference SD is **higher** than
   pre-fix (0.118/0.142 vs 0.071/0.115).
3. *Capture length* — refuted. A 21 s streaming clip beats a 255 s local-file capture, and
   the 255 s capture reads worse than the 102 s one.
4. *The `MIN_R` threshold* — that was a tool defect (a false PASS), fixed, and not an
   explanation.
5. **BUG-087's 10 Hz analysis rate — refuted 2026-08-12.** This was recorded here as the
   most promising lead. Two tests killed it. First, stems and bands sit on the **same clock
   within a path** (streaming: `beatPhase01` 85.4 %, stems 97.1 %; local: 16.7 % and
   14.6–16.0 %), so the "different clocks" mechanism does not exist. Second, step-holding the
   *streaming* capture's band and stem series down to 10 Hz — injecting the local-file rate
   into strong-r data — **barely moves the result**: r 0.788→0.783, 0.822→0.824, 0.871→0.860,
   0.895→0.898, 0.898→0.897, 0.937→0.938, with the 5.4 s lag intact in every case. 10 Hz
   sampling does not destroy the correlation, and the tool resolves lag fine at 10 Hz.

**One observation, offered without a conclusion:** local-file analysis frames are ~5× rougher
step-to-step at their own analysis grid than streaming's (mean |Δ| / SD ≈ 0.63–0.69 vs 0.12),
consistent with the 5× longer interval. Rough signals correlate worse in principle — but
hypothesis 5 shows decimation alone does not reproduce the weakness, so roughness is not a
sufficient explanation either. No sixth hypothesis is offered.

**This is a measurement-precision question, not a question about whether the fix works.**
BUG086.1's validity rests on the same-path lag comparison (local-file pre-fix 5.2 s →
post-fix 2.9/3.0 s, two independent captures), which does not depend on explaining
correlation strength.

**Two hypotheses for the weak post-fix correlation were tested and both refuted**, recorded
so they are not re-run: (1) *clamping degrades the features* — correlation on clamped vs
unclamped frames is identical (drums 0.388 vs 0.381; bass 0.413 vs 0.368), so clamping costs
timing fidelity nothing measurable; (2) *the reference signal is too flat* — post-fix
reference SD is **higher** than pre-fix (0.118/0.142 vs 0.071/0.115). A third guess was not
made; the honest state is that short captures are below this measurement's resolution.

**What a like-for-like before/after needs:** the same 16-track BeatBench corpus replayed on a
fixed build. That is the only capture that has ever produced a clean number, and reusing it
makes the comparison identical-material rather than a different track at a different length.

Two findings that DO stand, both from direct `session.log` readouts:

| | assumed at BUG086.1 | **measured `23-35-27Z`** | **measured `23-44-40Z`** |
|---|---|---|---|
| inference per separation | 142 ms (a code comment) | **335 ms** median (284–649, n=33) | **478 ms** median (421–596, n=63) |
| inference duty at 2 s period | ≈7 % | **≈20.5 %** | **≈25.6 %** |
| preset-facing lag | 2.5 s nominal | inconclusive | inconclusive |

**1. Inference is 2.4–3.4× the assumed cost, so duty is 20–26 %, not ≈7 %.** This is exactly
the caveat this entry flagged — the 142 ms figure existed only in a code comment with no
artifact behind it, and it was wrong. Note the second capture is *higher* than the first
(478 ms vs 335 ms median, and its **minimum** 421 ms exceeds the first capture's median), so
inference cost is variable across material or system load, not a single constant.

**It is nonetheless sustainable, on the engine's own signal.** 33 separations over a 65 s
span against 33 expected, and 63 over 124 s in the second capture — both at the nominal 2 s
cadence: `MLDispatchScheduler` (D-059) is absorbing the
load with jitter, not falling behind. Frame-pacing comparison against pre-fix captures is
**inconclusive and should not be quoted** — the pre- and post-fix sessions ran different
presets (`frame_gpu_ms` p50 0.15–0.21 vs 6.71), so the difference is preset-confounded, not
attributable to the cadence. `deltaTime > 20 ms` is 3.51 % post-fix against a pre-fix range
of 1.75–3.88 %, i.e. inside the existing spread.

**2. The 0.5 s read margin is too small — the read window clamps on ~25 % of cycles.**
Separation-to-separation gaps measured 0/1/2/3/4 s (×2/6/16/5/3). Runway is
`period + margin` = 2.5 s, so the 3 s and 4 s gaps — 8 of 32 cycles — overrun it by 0.5–1.5 s
and the window pins at the chunk's newest audio until the next chunk lands. Worst-case
inference alone does it too: 2.0 + 0.649 = 2.649 s > 2.5 s.

**The margin was sized against the wrong quantity.** It was set to absorb inference time;
the binding constraint is *deferral-induced gap jitter*, which reaches 4 s.

**Recommendation: do not re-tune now — and this is now tested, not assumed.** The earlier
version of this paragraph argued clamping was probably imperceptible. It was then measured
directly: correlation on clamped frames matches unclamped frames (drums 0.388 vs 0.381; bass
0.413 vs 0.368), so clamping costs timing fidelity nothing detectable. It also costs no extra
latency — pinning to the newest audio makes latency momentarily *better*. Covering a 4 s gap needs `margin ≥ 2.0 s`, i.e.
**4.0 s nominal latency** — paying 1.1 s of permanent latency to remove a discontinuity that
no shipping preset can currently show, since every stem consumer today drives slow envelopes
where a sub-second freeze is imperceptible. **It becomes a real decision the moment a
stem-plotting preset ships** (Stave is exactly that), and it is recorded here so that
session does not rediscover it.

#### Streaming path validated — session `2026-08-12T19-06-54Z` (Matt, 2026-08-12)

**Both paths now measured post-fix, and the fix holds on each:**

| path | pre-fix | post-fix |
|---|---|---|
| streaming | **5.4 s** | **3.0 s** |
| local file | 5.2 s | 2.9 / 3.0 s |

**The latency model in BUG086.1 was wrong, and this capture proved it.** The design claimed
2.5 s nominal. Actual:

    latency = (stemChunkSeconds − stemReadStartSeconds) + inference

`latestSeparationTimestamp` is stamped **after** `separator.separate` returns, so the chunk's
newest sample is already one inference old when the read window begins walking it. Predicted
2.50 + 0.531 = **3.03 s**; measured **3.0 s**. Inference was priced as a duty cost only; it is
also a latency cost, one-for-one.

**Consequence: ≈3.0 s is the architectural floor at a 2 s period, not a number to tune
toward.** Getting materially below it needs a smaller or faster model, not a cadence change —
period 1 s would give 2.03 s latency at **53 % inference duty**, which the frame budget will
not carry.

**The 3.0 s ceiling in `Scripts/measure_stem_latency.py` is corrected to 3.5 s.** It was set
from the wrong nominal and sat exactly on the floor, so it failed a working pipeline. 3.5 s
accommodates measured p90 inference (868 ms → 3.37 s) and still fails the pre-fix 5.4 s
decisively. **This is not floor-tuning (QG.1 / D-179)** — the gate was mis-set against a wrong
model and the model is what changed; the regression it exists to catch still fails it.

**Inference cost is higher again, and trending:** median 335 → 478 → **531 ms** across three
post-fix captures of increasing length, duty **≈30 %**, with **37 of 479 separations over 1 s
and one at 7105 ms**. The trend and the multi-second outliers are unexplained and worth
watching — at 30 % duty this is competing with rendering, and `MLDispatchScheduler` is the only
thing absorbing it.

**Clamping is inherent, not a defect to fix.** 25 % of separation gaps exceed the 2.5 s runway
(gaps ran 0–9 s). Removing clamping entirely needs `runway ≥ max gap` ≈ 9 s, i.e. **≈9.5 s
latency — worse than the original defect.** Recorded so no future session tries to tune it out.

**One observation, unresolved:** on the *same tracks*, post-fix streaming correlation is lower
than pre-fix — Billie Jean 0.788 → 0.59, Around the World 0.822 → 0.63. Clamping is the
obvious suspect, but the within-capture test (refuted hypothesis 1 above) found clamped and
unclamped frames indistinguishable, so the two results are in tension. Not resolved, and no
sixth hypothesis offered.

#### `dsp.stem` manual gate — PASSED (Matt, 2026-08-12) → **RESOLVED**

Session `2026-08-12T20-03-41Z`, local-file path, on a build carrying the fix (27
`STEM_SEPARATION` lines). **Skein** active 20:03:59–20:04:36, then **Glaze** to session end.
Matt: *"Session with Skein (and a little bit of Glaze as well) looks good."*

**Target chosen by measurement, not memory** — the lesson of the first attempt. Skein declares
28 routes of which 18 are stem routes, and `Scripts/check_route_liveness.py` verified in this
capture: **22 ALIVE, 5 NARROW, 1 SPARSE, 1 ABSENT, zero DEAD**, including all eight
stem-deviation routes (`painter_speed` and `flick_trigger` on all four stems). Glaze is the
second-densest stem consumer (8 of 9 routes). So the observation was aimed where stem timing
is actually visible.

⚠ **The first attempt was aimed at Aurora Veil and returned nothing** — it declares no stem
route at all, picked on a stale note claiming `other_energy_dev` was its anchor. That is
**BUG-088**, and the tool above exists so it does not recur.

Honest scope: Skein had ~37 s of a 63 s session. It is a felt judgement on a short window,
which is what a `dsp.stem` gate is — not a measurement, and not a substitute for one. The
measurements are separate and complete (both paths, above).

**RESOLVED 2026-08-12.** Fix `e6c188e6` (`[BUG086.1] Stems: separation period 5 s → 2 s, read
start derived from it`), merged in PR #77 (`f84d1eed`). Latency 5.4 s → 3.0 s streaming,
5.2 s → 2.9/3.0 s local file, manual gate passed.

**Carried forward, not blocking:** inference cost is trending (335 → 478 → 531 ms median, duty
≈30 %, one 7105 ms outlier) and unexplained; ≈3.0 s is the architectural floor, so materially
lower needs a different model; and the weak local-file stem/band correlation remains
unexplained after five refuted hypotheses. None is a regression and none blocks closure — they
are watch items for whoever next touches the stem path.
2. **The `dsp.stem` manual gate.** Stem timing is felt on every stem-driven preset;
   Aurora Veil (`other_energy_dev` load-bearing), Skein, Meniscus and FFO all shift.
   Needs M7-class observation on at least Aurora Veil. No automated test substitutes.

#### Related

**⇄ BUG-084** is the other open `dsp.stem` calibration defect (deviation reaching
35 against a ~3.4 ceiling). Same subsystem, independent causes; a fix increment
touching `StemAnalyzer` timing should check it has not disturbed BUG-084's
fixtures.

### BUG-084 — `StemAnalyzer` deviation reaches 35 where the primitive's real ceiling is ~3.4 (suspected EMA divide-by-tiny) (2026-08-03)

**Severity:** P3. No known product impact today — the one consumer that could have been hurt (FFO's aurora intensity) is defended by the FBS.S3.2 soft knee, which caps 35 → 1.64. Filed because the *input* is wrong, not the output: any future consumer that reads a stem deviation without a soft knee inherits the bug, and the value silently poisons any statistic computed over stem deviations.
**Domain tag:** `dsp.stem` (deviation primitive / EMA convergence).
**Status:** **Open — unreproduced, not investigated.** Carried as an inline aside inside BUG-041 from 2026-06-10 until that entry closed as stale (RECON.2, 2026-08-03); filed properly here so it survives its parent's closure. This is the whole reason BUG-041 could be closed safely.
**Introduced:** unknown; present at least since 2026-06-10.
**Resolved:** —

**Expected.** Deviation primitives (`bassDev`/`drumsEnergyDev` and siblings, D-026) express a band's deviation from its own running EMA. Measured against real music they spike to roughly **3× with a p99 near 0.85** — the documented real range, and the basis for the "soft-saturate against p99, never against 1.0" rule (CLAUDE.md FA #73).

**Actual.** Session `2026-06-10T17-50-56Z` (So What) produced `dev = 35` — an order of magnitude past the primitive's observed ceiling, and 3–30× the track median across an all-stem burst.

**Suspected mechanism.** `StemAnalyzer` resets per track and its per-stem EMA re-seeds from near-zero. A deviation computed as a *ratio* against that not-yet-converged baseline divides by a near-zero denominator, so the quotient explodes during the convergence window. This is the same shape as the BUG-027 / AGC2.4.1 cold-start family that was fixed for the FeatureVector band devs; the stem-side twin may simply never have received the equivalent guard.

**Reproduction steps.** Not yet attempted. Start point: replay the `fbs/` fixtures that captured the burst (`stemsum_so_what_2026-06-11T01-56-22Z.csv` and siblings retained in `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/fbs/`) and log the raw pre-soft-knee deviation alongside the EMA denominator through the first ~10 s of a track.

**Suspected failure class:** `numerical` (divide-by-near-zero during EMA convergence).

**Verification criteria:**
- [ ] Raw stem deviation confirmed against the ~3.4 ceiling on the fixtures above, with the EMA denominator logged — i.e. mechanism *observed*, not inferred, per the evidence-before-implementation gate.
- [ ] If confirmed, a floor on the denominator (or the BUG-027-family guard) brings the primitive inside its documented range without changing musical response — the soft knee's output must not measurably move for normal values.
- [ ] No regression in FFO aurora behaviour (the soft knee stays; this fixes the input, not the defence).

**Manual validation required:** No, if the fix leaves the soft-kneed output unchanged for musical values — the automated FBS gates cover the visible surface. Yes if the fix alters aurora response at all.

**Related:** BUG-041 (closed as stale 2026-08-03 — this was its inline aside); BUG-027 / AGC2.4.1 (the FeatureVector-side twin, fixed); CLAUDE.md FA #73 and [[deviation-primitive-real-range]] for the documented real range.

---

### BUG-060 — One-off app hang: the render loop died on a `preset → Gossamer` switch; force-quit required; not reproduced (2026-06-18)

**Severity:** P3 (a full app hang requiring force-quit is P1-*impact*, but it was seen once and did not reproduce — Gossamer ran 3× clean the next session; filed as **monitored**, like BUG-058, pending a recurrence with a captured stack).
**Domain tag:** renderer / app.hang (suspected preset-apply or first-frame GPU hang on Gossamer).
**Status:** **OPEN — RECURRED (Matt, 2026-08-03; RECON.2).** The prior "likely resolved by NACRE.2b" status is **falsified as a complete explanation** and must not be restored without new evidence. Asked directly during the 2026-08-03 production audit whether the force-quit hang had been seen since mid-July, Matt confirmed it had. No session ID, preset, or stack was captured for the recurrence, so the *mechanism* is still undiagnosed — what changed is that the empty-`activePasses` guard is now known to be **insufficient**, which was the exact residual risk the previous status flagged ("the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains"). That residual is now the leading hypothesis rather than a footnote.

**What the recurrence changes.** Previously this entry was one clean session away from closing. It is now a live P3 with a *narrowed* hypothesis space: the preset-apply race is fixed and verified (BUG-061 is closed on its own evidence), so whatever hangs the render loop is **not** that race. Do not re-run the "confirm by non-recurrence" plan — it has already returned a negative. The next step is evidence capture, not another monitoring window.

**⇄ Same class as BUG-081 — two instances, one missing artifact (linked at RECON.9, 2026-08-03).** A parallel session independently filed **BUG-081** for a beachball ~78 s into session `2026-08-03T22-54-06Z` that also needed a force-quit and also produced no crash report, and reached the *same* conclusion this entry did, separately: force-quit yields no `.ips`, so the artifact must be taken **during** the hang via `sample`. Two sessions converging on that from different evidence is worth more than either alone. **Treat BUG-060 and BUG-081 as one investigation** — differences to keep in view: BUG-081's capture shows the renderer *healthy to the last frame* (steady 60 fps, Fractal Tree 0.18 ms GPU against a 0.7 ms budget, no degradation across 3756 frames) with background ML load rising, which points at a frozen **UI/main thread** rather than a dead render loop; BUG-060's original capture showed the render loop itself stopping one frame after a preset switch. Those may be one bug or two. **Whichever recurs first, capture the sample** — it resolves both. Do not assert a shared root cause before then (BUG-061's rule).

*Prior status, retained for the reasoning trail:* LIKELY RESOLVED by NACRE.2b's BUG-061 fix (2026-06-25), pending non-recurrence. BUG-061 confirmed the suspected **preset-apply race**: `applyPreset` clears `activePasses` to `[]` then republishes them at its end, while `draw(in:)` runs concurrently on the display-link thread; a frame in that window falls to `drawDirect` with the new preset's direct pipeline. Nacre's `.rgba16Float` pipeline made it a deterministic crash and exposed the mechanism; for an 8-bit preset like Gossamer it's the benign/intermittent stray frame seen here. The `willRenderActiveFrame` guard (skip frames while `activePasses` is empty) removes the stray `drawDirect` for ALL presets. Keep monitored until a few clean Gossamer-switch sessions confirm non-recurrence (the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains).
**Introduced:** Unknown (the apply-race predates NACRE.2b).
**Resolved:** Not resolved. The 2026-06-25 empty-passes guard fixed a real adjacent defect (BUG-061) but did not stop this hang.

**Expected:** switching presets (incl. Gossamer) never hangs the app.

**Actual (session `2026-06-17T22-10-50Z`):** the render loop was healthy — 60 fps, `frame_gpu_ms` 0.13–1.5 ms, no `deltaTime` gap — through the **last recorded frame (9459) at `22:14:01Z`**, which is **one second after `session.log`'s last event, `preset → Gossamer` at `22:14:00Z`**. `features.csv` then stops while the stem-separation / orchestrator threads keep logging for ~30 s more → a **render-path hang** (main or GPU), not an analysis stall (cf. BUG-043, a freeze-then-lurch) and not a tap freeze (cf. BUG-058). Video was OFF (BUG-050), so the recorder's video path is excluded. Matt force-quit from Xcode **without hitting Pause**, so no thread stacks were captured.

**Non-reproduction (session `2026-06-18T13-57-23Z`):** Gossamer was applied **3×** (13:58:35, 14:00:13, 14:00:36) and rendered clean; the session ended with a normal `SessionRecorder finished` shutdown. So the hang is rare/intermittent, not a deterministic Gossamer defect.

**Reproduction steps:** unknown trigger. Lead: a `preset → Gossamer` switch under live load (continuous stem separation running) — possibly transient GPU contention between the stem-separation MPSGraph and Gossamer's first-frame render, or a preset-apply race.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-17T22-10-50Z/` (features.csv ends at frame 9459 / `22:14:01Z`; session.log last line `preset → Gossamer`); clean counter-example `2026-06-18T13-57-23Z`.

**Suspected failure class:** `concurrency` or `render-state` (a hang, not a crash).

**Verification criteria (when diagnosable):**
- [ ] **On the next recurrence, capture a stack BEFORE force-quitting.** A hang produces no crash log, so there is nothing to recover afterwards — the artifact has to be taken while the app is still wedged. Two routes, either is sufficient:
  - **Launched from Xcode:** hit Pause (⏸), then capture the Debug-Navigator thread stacks (main thread + any thread in Metal/MPSGraph). Add `Debug → Capture GPU Frame` if a GPU hang is suspected.
  - **Launched normally (the likely case for a live session):** from Terminal, `sample PhospheneApp 10 -file ~/Desktop/phosphene_hang.txt` — ten seconds of stacks for every thread, no Xcode needed. `spindump` works too but needs sudo. This is the same instrument that diagnosed the BUG-059 deadlock class.
- [ ] Root cause identified from a captured stack; regression guard added.

*Note (RECON.2, 2026-08-03):* the earlier framing of this criterion assumed an Xcode-attached session, which is not how the recurrence was hit. The `sample` route above is the one that will realistically be available.

**Manual validation required:** Yes — a hang is felt, and only a captured stack diagnoses it.


---

### BUG-058 — Mid-session output-device swap freezes the tap: `performReinstall` (CLEAN.1.5 / G1) doesn't recover; visuals freeze on a stale buffer (2026-06-17)

**Severity:** P3 (downgraded from P2 2026-06-17 — see §Update. RARE intermittent: the G1 device-swap recovery is robust in the common case; a freeze was seen once and not reproduced across 12 subsequent swaps).
**Domain tag:** audio.capture / resource-management (`SystemAudioCapture.performReinstall`, `DefaultOutputDeviceMonitor`)
**Status:** Open — **instrumented + largely validated. G1 device-swap recovery confirmed ROBUST (12/12, 2026-06-17).** The single freeze (`14-28-30Z`, un-instrumented build) was NOT reproduced; breadcrumbs remain in place to pin it if it recurs. Distinct from BUG-057: that's a wedged `coreaudiod` feeding *all* taps zero; this is a rare race in the tap recreate during an OS device transition.
**Introduced:** Unknown — CLEAN.1.5 (`DefaultOutputDeviceMonitor → performReinstall`, 2026-06-13) added the device-change recovery, but its G1 manual validation was never performed; this is its first real test, and it fails. Possibly a macOS-26.5 Core Audio behavior (tap recreate during a device transition).
**Resolved:**

### Expected behavior
Switching the macOS default output mid-session (e.g., Duet 3 → Mac mini Speakers) reinstalls the tap against the new device and visuals keep animating (a brief glitch is acceptable) — what CLEAN.1.5 / G1 promises.

### Actual behavior
On the swap the visualizer freezes and never recovers. Session `2026-06-17T14-28-30Z` (instrumented build, healthy coreaudiod): the tap worked ~39 s (RMS 0.06, `signal quality → green`), then at the switch **`raw_tap.wav` stops at exactly 39.1 s while the session ran ~134 s** — the **IO proc stopped firing entirely.** The render loop coasted on the last buffer for ~95 s → `features.csv` tail is **constant nonzero** (`bass=0.16956, mid=0.00565, treble=0.00073`, identical across the final frames) = the Waveform preset shows a frozen flat line. **No `reinstall via device-change` success/FAILED line**, and **no `audio signal → silent`** (the buffer isn't RMS≈0, so `SilenceDetector` stays `.active` → `.silent → reinstall` never arms either). Both recovery paths miss.

### Reproduction steps
1. Cold-start streaming (Spotify); confirm visuals animate.
2. ~20–30 s in: System Settings → Sound → Output → switch device (Duet 3 ↔ Mac mini Speakers).
3. Observe: visuals freeze on the last frame, no recovery; `raw_tap.wav` stops at the switch; `features.csv` tail constant.

### Session artifacts
`~/Documents/phosphene_sessions/2026-06-17T14-28-30Z/` (the failure; `raw_tap.wav` 39.1 s of 134 s, frozen-buffer tail) + `…T14-15-28Z/` (prior run that ended at/before the switch — tap healthy throughout, failure not captured).

### Suspected failure class
`resource-management` / `api-contract` (pending instrumentation). Leading hypothesis: `performReinstall` **fired and ran `teardownTapResources()` (→ the clean IO-proc stop at 39.1 s), but the tap RECREATE stalled/hung** during the device transition (a `createProcessTap` / `createAggregateDevice` / `startDevice` blocking on macOS 26.5), never reaching the success or catch log. Alternative: the `DefaultOutputDeviceMonitor` listener never fired. The os_log lines that would distinguish these are `.info` → not persisted (`log show` empty), hence:

### Instrumentation (step 1 — landed 2026-06-17)
Added `session.log` breadcrumbs (via the existing `onCaptureDiagnostic` sink) the os_log path lacked: the **`DefaultOutputDeviceMonitor` callback firing** (`device-change monitor FIRED`), and **each step of `performReinstall`** (`ENTER → tearing down` / `teardown done` / `tap created` / `aggregate created` / `IO proc created` / success / FAILED / `SKIPPED (not capturing)`). The last breadcrumb before silence pins the exact stall point. No fix code; breadcrumb-only on the non-SPM-testable device-change path.

### Update 2026-06-17 — G1 device-swap recovery validated ROBUST (12/12); freeze un-reproduced

Instrumented re-test (session `2026-06-17T14-54-49Z`): **12 rapid back-and-forth output-device swaps (Duet 3 ↔ Mac mini Speakers), all 12 recovered cleanly** — each logged `device-change monitor FIRED → performReinstall: ENTER → … → reinstall via device-change gen=N` completing in < 1 s, with the new tap immediately recapturing real audio (RMS 0.05–0.49); motion preserved through the last frame; `raw_tap.wav` continuous (67 s). A prior single swap (`2026-06-17T14-49-23Z`) also recovered. Tally: **`monitor FIRED` = 12, reinstall completed = 12, FAILED = 0.** So `DefaultOutputDeviceMonitor → performReinstall` (CLEAN.1.5) is sound — **the G1 manual gate passes.** The one freeze (`14-28-30Z`) ran on the pre-breadcrumb build, minutes after a `sudo killall coreaudiod`, so the leading explanation is a **transient `coreaudiod`-settling race** in the tap recreate, not a systematic defect. Left Open at P3 with the breadcrumbs live: if a freeze recurs, the last `performReinstall:` line before silence pins the stalling Core Audio call.

### Verification criteria
- [x] Instrumentation (step 1): breadcrumbs landed; the happy path is fully captured (session `14-54-49Z`).
- [x] Manual (G1): swap the output device mid-session → visuals stay live, ≥ 2 devices, both directions — **PASSED 12/12 (2026-06-17).**
- [x] No regression: cold-start streaming still animates; BUG-057 workaround unaffected.
- [ ] (Open, low-priority) Reproduce + pin the rare freeze, *if* it recurs.

### Related
- **The open G1 / CLEAN.1.5 manual gate** — this *is* that gate failing. CLEAN.1.5 has unit tests for the monitor mechanism (`DefaultOutputDeviceMonitorTests`) but the live device-swap was never validated.
- BUG-057 (sibling silent-tap; different mechanism — wedged coreaudiod / pure-zero, vs this frozen-buffer / IO-proc-stopped). The planned granted-but-silent **detector** must catch THIS state too (no *fresh* audio / IO-proc-stopped), not just RMS≈0.
  - **Detector landed 2026-06-17** (see BUG-057 §Fix increment): `PlaybackErrorBridge`'s freshness poll catches THIS Mode-B state — `InputLevelMonitor.frameCount` ceasing to advance while `.silent` never fires — and raises the `AudioStallOverlayView` card. This bug stays its own (the rare freeze itself is still un-fixed); the detector just makes the frozen state visible + actionable instead of a silent frozen frame.
- Surfaced 2026-06-17 during the G1 manual test (run right after the BUG-057 coreaudiod fix).


---

### BUG-056 — Local-file playback restarts the track from the top when the macOS output device changes (`LocalFilePlaybackProvider` AVAudioEngine teardown/restart, no resume-from-position) (2026-06-16)

**Severity:** P3 (local-file robustness/UX — no crash, no data loss; a mid-track output swap loses playback position. Annoying, not blocking.)
**Domain tag:** local-file / audio (`LocalFilePlaybackProvider`, AVAudioEngine)
**Suspected failure class:** `resource-management` (the `AVAudioEngineConfigurationChange` handler tears the player down and restarts at frame 0 instead of resuming).
**Status:** Open — observed 2026-06-16; **re-confirmed live 2026-06-18** (session `2026-06-18T13-46-10Z`) during the BUG-059 device-swap validation: several swaps each restarted the track from the top (the engine teardown/restart now always completes cleanly — BUG-059 fixed — so this restart is the remaining, expected behavior). Not yet scheduled — awaiting Matt's prioritization call (resume-from-position is its own increment).
**Resolved:** —

**Expected:** changing the macOS output device during local-file playback continues the track from its current position (a brief audio glitch on the reconfigure is acceptable).
**Actual:** on an output-device change the provider runs a full teardown (`provider.teardown` → removeObserver / player.stop / player.removeTap / engine.stop) and the player restarts from position 0 — the song starts over. The visualizer keeps running; only the audio restarts.
**Reproduction steps:** play a local file; mid-playback change the macOS default output (System Settings → Sound → Output, or ⌥-click the menu-bar volume). The track restarts from the beginning.
**Session artifacts:** `2026-06-16T21-32-50Z` — `session.log` shows `provider.teardown … player.stop … engine.stop` at 21:33:57 and again at 21:34:12 (two output swaps), each followed by a restart from the top.
**Verification criteria (for the fix):**
- [ ] On an `AVAudioEngineConfigurationChange` (output change), the provider reconfigures and **resumes from the saved frame position** rather than restarting at 0.
- [ ] Manual: swap output mid-local-file → playback continues (≤ a small glitch), not a restart.

**Note:** distinct from **G1** (the *system-tap* reinstall on the streaming path — `DefaultOutputDeviceMonitor` / `performReinstall`); local-file uses AVAudioEngine and never engages the tap, so a local-file output-swap does NOT validate G1.


---

### BUG-055 — Silent system-audio tap after a rebuild: `CGPreflightScreenCaptureAccess()` returns stale-`true` (gate passes) but macOS silently denies the re-signed binary's tap → app shows "ready", renders a flatline, no guidance (2026-06-16)

**Severity:** P2 (no crash/data-loss, but a total loss of the core function — no visuals on any streaming / `.systemAudio` session — presented as "ready" with **no actionable feedback**; cost a ~90-minute live-debug session and recurs on every dev rebuild. Not P1: a workaround exists (re-grant + relaunch) and the local-file path is unaffected.)
**Domain tag:** app.ui / permission (TCC "Screen & System Audio Recording") — capture path `SystemAudioCapture` (`AudioHardwareCreateProcessTap`)
**Suspected failure class:** `api-contract` (`CGPreflightScreenCaptureAccess()` returns stale-`true` after a re-signed rebuild — the gate trusts an unreliable preflight) + `pipeline-wiring` (no "granted-but-zero-signal" fallback detection).
**Status:** Symptom RESOLVED 2026-06-17 (detector, validated) — the filed defect (silent flatline reported as "ready," **no guidance**) is addressed: the silent-tap detector surfaces an actionable card with a "re-grant Screen & System Audio Recording, then quit + relaunch" step (Mode A — same validated path; commit `a0a9ded`, surface validated by screenshot). The durable root (stable signing so the grant persists across rebuilds — CLEAN.2.5b) remains open/blocked on no paid Apple membership; end users on a stably-signed build won't hit the re-grant at all. Per Matt, the card is a fallback — the end-state goal is **no** user-facing Terminal/Settings step (self-healing; see BUG-057 §Fix increment + `feedback_self_healing_over_manual_remediation`).
**Resolved:** 2026-06-17 — user-facing symptom via the silent-tap detector (`a0a9ded`). Durable signing recurrence tracked separately as CLEAN.2.5b.

**Expected:** when a live `.systemAudio` session is shown, the tap captures the default output and drives the visuals; if capture is actually denied, the app surfaces an actionable "re-grant Screen Recording" state — never a silent flatline reported as "ready."
**Actual:** after rebuilding the (dev-signed, hardened-runtime) app, streaming sessions render **no motion**. The tap installs cleanly (`raw tap capture started sr=… ch=2`) and `signal quality → red: no signal` fires, but `PermissionMonitor` (→ `CGPreflightScreenCaptureAccess()`, `PhospheneApp/Permissions/`) reports **granted**, so the gate (`ContentView`) lets playback proceed. macOS silently denies the actual `AudioHardwareCreateProcessTap` because the rebuilt binary's code signature no longer matches the prior grant — a **denied process tap returns zeros, not an error** — so the tap delivers pure silence. Reproduced with both the Apogee Duet 3 and the built-in Mac-mini Speakers as default output (audio audibly playing on the tapped device). `tccutil reset ScreenCapture com.phosphene.app` cleared **32 orphaned grants** — one per dev rebuild (the dev signature churns every build; hardened-runtime makes the match strict, but Debug churns too).
**Reproduction steps:** rebuild the app, launch, start a streaming session, play audio to the macOS default output → green UI, zero visuals. `raw_tap.wav` RMS=0.0, `features.csv` bass/mid/treble all 0.0. **Fix:** `tccutil reset ScreenCapture com.phosphene.app` → relaunch → grant "Screen & System Audio Recording" → **quit + relaunch** (the grant applies only on a fresh launch).
**Session artifacts:** `2026-06-16T20-58-31Z` (Apogee Duet default) + `2026-06-16T21-15-42Z` (built-in Speakers default) — both `raw_tap.wav` RMS 0.0, all features 0, log `audio signal → silent`. **Contrast** `2026-06-16T21-32-50Z` (a local file on the *same* broken build): green −1 dBFS + full motion — isolating the fault to the tap/permission, not the audio source (local files are file-direct AVAudioEngine and bypass the Screen-Recording gate per `ContentView` LF.4).
**Suspected failure class:** `api-contract` + `pipeline-wiring` (see above).
**Verification criteria (for the fix):**
- [ ] **Detection:** while a session is "ready"/playing and the tap reads ~0 RMS for > N s, the app transitions to an actionable "Screen Recording may be stale — re-grant" state instead of a silent flatline (wire the existing `signal quality → red: no signal` detector to this). Unit-testable.
- [ ] The gate stops treating `CGPreflightScreenCaptureAccess()` alone as proof of working capture (it is unreliable after a re-sign).
- [ ] **Manual:** after a rebuild with a stale grant, the app guides the user to re-grant rather than showing a dead session.

**Durable fix:** dev-signing re-signs every build, so the grant never persists → this recurs every rebuild; the root fix is **stable signing (Developer ID / notarization — CLEAN.2.5b, blocked on no paid Apple membership)**. Related: G1 (CLEAN.1.5 output-device handling) and the `signal quality → red: no signal` detector (BUG-026 domain). Note: a *separate* silent-tap cause is environmental output-routing (audio playing on a device the tap isn't bound to) — this BUG is the distinct, real defect where audio IS on the tapped device but the permission is silently denied.

**Detector fix increment — landed 2026-06-17 (pending Matt's manual UX validation):** the **Detection** criterion above is satisfied by the shared silent-tap detector (see BUG-057 §Fix increment) — `PlaybackErrorBridge` raises the `AudioStallOverlayView` card on sustained RMS≈0 (Mode A) while playing, with "re-grant Screen & System Audio Recording, then quit + relaunch" in the on-card fix ladder, instead of a silent flatline reported as "ready." The durable signing fix (CLEAN.2.5b) is still separate and still blocked. Mark this bug `Resolved` (the detector half) after Matt's manual UX validation of the card.


---

### BUG-054 — Key detection has never been accurate enough to use in playback (chroma algorithm is fundamentally resolution-limited) (2026-06-16)

**Severity:** P3 (non-load-bearing *today* — `estimatedKey` is a debug/UI display value + a fallback; nothing in orchestration or any preset consumes key, and presets drive from energy/deviation, not key. No fps/crash/playback-correctness impact. Sev would rise to P2 if/when a feature is built to *use* key. Matt may rerank). Filed 2026-06-16 after the BUG-053 work surfaced it (Matt: "key has never been correct for as long as Phosphene has tracked it"). Investigation + fix design done this session; **filed for later, not scheduled.**
**Domain tag:** dsp.key (MIR chroma / key estimation)
**Suspected failure class:** `algorithm` (the chroma front-end is resolution-limited by construction) + `calibration` (full-mix input, no harmonic weighting).
**Status:** Open — design complete, **not scheduled** (Matt's call: track for later). Distinct from BUG-053 (that was the live MIR ignoring the *tap rate*; this is the chroma/key *algorithm* being inaccurate even at the correct rate).
**Resolved:** —

**Expected:** the detected musical key matches the track's actual key on clear tonal material (with a confidence gate so it surfaces only when trustworthy). Realistic ceiling: ~70–85 % exact + ~90 %+ within a fifth/relative — never 100 %.
**Actual:** key is reliably wrong. Black Hole Sun (G major) read **F** in session `2026-06-16T16-52-09Z`. Root causes (`ChromaExtractor.swift`, `SessionPreparer+Analysis.analyzeMIR`):
1. **1024-point FFT → ~43 Hz/bin.** A semitone near middle C is ~15 Hz — *under half a bin* — so C/C♯/D below ~1 kHz fall in the same bins; the analyzer can't resolve which semitone owns the energy in the register where the key lives. The `minFrequency = 500 Hz` floor (`ChromaExtractor.swift:63`) sidesteps the worst of it but then reads key off harmonics ≥ 500 Hz, which smear across pitch classes (overtones land on octave/fifth/major-third).
2. **Linear FFT bins → log pitch is the wrong transform** — the field uses a constant-Q transform (uniform log-frequency resolution).
3. **Full-mix chroma** — drums/percussion (broadband) pollute it; no harmonic/percussive split, even though Phosphene already computes stems.
4. **No harmonic summation / spectral whitening.**
Krumhansl-Schmuckler template matching at the end is fine; the chroma front-end is the bottleneck. The offline per-track pass (`analyzeMIR`) uses the *same* 1024-pt full-mix `ChromaExtractor`, so the cached key is equally wrong. No metadata fallback in normal use: only `SoundchartsFetcher` returns a key (env-gated, off by default); iTunes/MusicBrainz don't carry key; Spotify's audio-features (key) endpoint is deprecated for new apps.

**Reproduction steps:** play any track with a known key (e.g. Black Hole Sun = G); read the `key=` line in `~/phosphene_diag.log` (the MIR's own estimate, not metadata-overridden). It is reliably off, independent of sample rate.
**Session artifacts:** `2026-06-16T16-52-09Z` (Black Hole Sun, true G, read F). A labeled validation set is a prerequisite for the fix (see below).
**Verification criteria (for the eventual fix):**
- [ ] A **labeled ground-truth set** (~15–20 tracks, known keys) added as a test fixture; report **exact-match %** + **within-a-fifth/relative %** before and after.
- [ ] Post-fix exact-match clears an agreed bar (target ~70 %+ exact, ~90 %+ tolerant) on that set.
- [ ] Display/use is **confidence-gated** — a low-confidence estimate shows nothing rather than a wrong key.

**Fix approaches (design from this session; key is a per-track value → spend compute once, offline; exploit Phosphene's stems + offline budget):**
1. **Tier 1 (cheap, partial):** in the offline key pass, feed the **drums-removed / harmonic stem** signal (stems already exist → free HPSS), bump to an **8192-pt FFT** (or add harmonic summation), aggregate over the whole clip; keep Krumhansl. Likely "never right" → right on clear tonal tracks.
2. **Tier 2 (proper):** **constant-Q transform** → harmonic-weighted pitch-class profile (HPCP) + spectral whitening → refined templates (Temperley / Albrecht-Shanahan) over the whole track — the librosa-`chroma_cqt` / essentia-`KeyExtractor` design, built in Accelerate (no Swift MIR lib; on-device constraint). The real fix.
Recommended sequencing: Tier 1 measured against the labeled set first; escalate to Tier 2 only if it doesn't clear the bar. Confidence-gate either way.


---

### BUG-036 — Heap allocations on the real-time Core Audio thread at three sites (FFTProcessor, AudioBuffer.latestSamples, SessionRecorder raw tap) (2026-06-09)

**Severity:** P2 (violates the standing "do not allocate in the Core Audio IO proc callback" rule on every callback of every session; priority-inversion / glitch risk under memory pressure rather than observed breakage).
**Domain tag:** audio.capture / performance
**Status:** Open (mostly fixed) — sites 1 + 2 fixed + **validated in production** (2026-06-17, `58a37c0`; session `2026-06-17T20-52-27Z` — no audible glitch, steady 60 Hz cadence, worst gap 84 ms). Site 3 (raw-tap) + the analysis hand-off **parked** as an accepted low-risk residual (re-open the ring rework only if a stall/glitch implicates it — BUG-043 is not recurring; Matt 2026-06-17). See Progress.
**Introduced:** structural — predates the rule's enforcement attention; the "zero-alloc" header comments in both DSP files are currently false.
**Resolved:** — (sites 1 + 2 done; bug stays open until site 3 + the hand-off land)

**Expected:** the IO-proc path allocates nothing (CLAUDE.md What-NOT-To-Do).
**Actual (all three verified on the IO-proc call path via `VisualizerEngine+Audio.makeAudioSampleCallback`):**
1. `FFTProcessor.swift:149,193` — `process()` allocates a fresh `magnitudes` array per call; `processStereo` allocates a fresh `mono` array (called at `VisualizerEngine+Audio.swift:114`).
2. `AudioBuffer.swift:148` — `latestSamples` does 2048 per-element ring reads (`UMARingBuffer.read(at:)` precondition + modulo each) + an allocating `append` loop **under the same NSLock the write path takes**, per callback (`VisualizerEngine+Audio.swift:111`). RMS over the same samples is also computed 3× per callback (AudioBuffer `:179`, SilenceDetector `:106`, InputLevelMonitor `:185`).
3. `SessionRecorder+RawTap.swift:28` — `Data(bytes:count:)` copy + `queue.async` closure allocation per callback for the first 30 s of every session (entire session under `PHOSPHENE_FULL_RAW_TAP=1`).
Related P3 (same rule, rarer path): `AudioInputRouter+SignalState.swift:45` — tap-reinstall scheduling (locks, `DispatchWorkItem` alloc, os_log interpolation) runs on the RT thread on silence transitions.
**Session artifacts:** `docs/diagnostics/CODE_AUDIT_2026-06-09.md` (Audio/DSP P2 section).
**Suspected failure class:** `resource-management` (RT-safety).

**Progress (2026-06-17, `58a37c0`) — sites 1 + 2 landed; site 3 + hand-off deferred to BUG-043.** The three named allocations split into two groups by whether they cross the audio-thread boundary:
- **Sites 1 + 2 (RT-thread-local) — FIXED.** `FFTProcessor` reuses a pre-allocated `magnitudesScratch`; a new zero-alloc `processStereo(interleaved: UnsafeBufferPointer)` mixes L/R straight into the windowed-sample scratch (no `mono` array); the array overloads delegate to it. `AudioBuffer.latestSamples(into:)` fills a caller-owned buffer (the callback reuses a pre-allocated `interleavedScratch`). All scratch is touched only on the single RT thread → no lock needed (cf. D-079's cross-core `tapSampleRate`). FFT output is byte-identical (pointer↔array bit-equivalence test + unchanged FFT/Chroma/BeatDetector goldens).
- **Site 3 (raw-tap `Data()` + `queue.async`) + the analysis hand-off (`Array(...prefix())` + `analysisQueue.async`) — PARKED (accepted low-risk residual).** Both cross the thread boundary. Making them allocation-free safely requires a pre-allocated ring drained by a persistent consumer (the "pre-allocated ring for raw-tap" fix below): an unbounded→bounded hand-off is a cadence/concurrency change that lands directly on **BUG-043**'s analysis-stall surface. The hand-off allocates every callback — a *continuous but low-impact* RT-rule violation — and the fix is a real concurrency redesign. With **BUG-043 not recurring** after sites 1 + 2 (the forcing function is gone), the cost/benefit doesn't justify the rework now (Matt 2026-06-17); re-open if a future stall/glitch implicates the remaining allocations. (Originally deferred to sequence *with* BUG-043 per the `036 → re-test → 043` ordering; the re-test came back clean, so it's parked rather than queued.)

**Verification criteria:**
- [x] Automated (sites 1 + 2): `FFTProcessorTests.fftProcessorStereoPointerMatchesArrayPath` + `…ReuseIsStable`, `AudioBufferTests.audioBufferLatestSamplesIntoMatchesAllocating` — pre-allocated members, pointer path bit-for-bit == array path (incl. short/partial-fill + ring-wrap), scratch reuse stable over 64 calls.
- [x] Manual (sites 1 + 2): no audible-glitch regression + healthy analysis cadence — session `2026-06-17T20-52-27Z` (Matt): median Δt 0.0167 s (60 Hz) over 25,017 audible frames / 8 tracks, worst gap 84 ms, no freeze-lurch. (The stricter os-allocator Instruments proof is optional given byte-identical output + green tests + this cadence — not pursued, Matt's call.)
- [—] Automated (site 3 + hand-off): pre-allocated ring + allocation-free hand-off — PARKED with the remainder (see Progress); not required while BUG-043 stays quiet.


---


---

### BUG-028 — Beat-grid live phase imperfect on ~half of tracks (felt "behind the beat / wrong downbeat") (2026-06-05)

**Severity:** P2 (musical-feel ceiling across every beat-coupled preset; not a crash. Bounds Nimbus's beat axis — see M7 r1 below).
**Domain tag:** dsp.beat (grid phase)
**Status:** Open — diagnosed; elevated to its own project per Matt (**D-145**). Scoping note: `docs/diagnostics/BEAT_GRID_LIVE_PHASE_PROJECT_2026-06-05.md`. **Not to be fixed by per-preset tuning, and not by another short-window live-tap iteration (FA #69 — premise retired).**
**Introduced:** structural — the cached `BeatGrid` is built from the 30 s preview and its phase is cross-capture-unstable on live audio (BSAudit.2; CLAUDE.md §Cold-Start Phase Contract).
**Resolved:** —

**Expected:** beat-coupled visuals land on the audible downbeat across the catalog.
**Actual (Nimbus M7 r1, session `2026-06-05T18-26-37Z`):** grids **lock** (`lock_state`=2 ~84 %) with the **right tempo** (grid-vs-drums BPM < 1 % on most tracks), but live **phase** is imperfect — `drift_ms` ~10–35 ms (mixed sign) and meter assumed simple (Money 7/4 logged `beatsPerBar`=2). Reads as "behind the beat / wrong downbeat" on roughly half the tracks; locks well when phase happens to align (Superstition verse).
**Suspected failure class:** `algorithm` (cached-grid phase derivation) — a *new premise* is required (human-tap reference / full-track local analysis / per-track manual calibration), chosen with Matt in the D-145 design session before any increment.
**Verification criteria:** deferred to the D-145 project.


---

## Known Limitations (external / by-construction — not actionable defects)

Reclassified at PUB.3 (2026-07-11, ultra-review): these are bounded by external
APIs or by-construction constraints, kept for reference so contributors don't
mistake them for open work. BUG-005's UX-copy criterion is the one item that
could close via a small increment.

*Reading note (RECON.2, 2026-08-03):* the three entry **bodies** below still carry
`**Status:** Open` and unchecked verification boxes from before the PUB.3
reclassification. **This section header wins** — they are not counted in the open
defect total and none is scheduled work. The bodies are deliberately left intact
rather than rewritten, because their verification criteria are exactly what would
have to be met *if* an external API ever exposes what they need (a `time_signature`
source for BUG-013 and BUG-001) — rewriting them to "closed" would throw away the
reopening condition. Read `Status: Open` there as "unsolved", not "in the queue".

- **BUG-013** · dsp.beat — no `time_signature` source (Soundcharts doesn't expose it); meter wrong on some odd-meter tracks
- **BUG-001** · dsp.beat — Money 7/4 stays REACTIVE on the live path (odd-meter ceiling)
- **BUG-005** · session.ux — Spotify `preview_url` null for some tracks (API-side; degrade path exists)

---

### BUG-013 — Soundcharts does not expose `time_signature`; ML meter detection wrong on some odd-meter tracks

**Severity:** P2 (visual artifact on a subset of odd-meter tracks. Bar-locked motion presets (Ferrofluid Ocean) cycle at the wrong rate on tracks where the ML meter detector guesses wrong AND the metadata source can't override. Current production playlist only surfaces this on Pink Floyd's Money 7/4 → cycles at 5.85 s/cycle on Ferrofluid Ocean instead of the intended 20.5 s/cycle. Visual still reads as "ocean swell" per Matt's 2026-05-15T17-54-49Z review.)
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** Surfaced 2026-05-15 during Ferrofluid Ocean Round 25-26 metadata-override implementation.
**Resolved:** —

---

### Expected behavior

When `MetadataPreFetcher` returns a profile for a track, `PreFetchedTrackProfile.timeSignature` carries the track's time-signature numerator (3 for 3/4, 4 for 4/4, 7 for 7/4, etc.). `SessionPreparer.analyzePreview` overrides `BeatGrid.beatsPerBar` with this value before caching. Downstream consumers (FerrofluidMesh vertex shader's bar-locked wave cycling) use the correct meter.

### Actual behavior

`PreFetchedTrackProfile.timeSignature` is always nil in production. Soundcharts (the only metadata source in production that exposes audio features) does not return `time_signature` in its API response — verified by adding the decode field and observing zero hits in session.log (no `Using pre-fetched time signature: N/X` lines for any of Love Rehab, So What, There There, Pyramid Song, Money).

Result: `BeatGrid.beatsPerBar` retains the ML-detected value. For Money (actual 7/4), the ML detector classifies as `meter=2/X` — wave cycle is `6 × 60 × 2 / 123 = 5.85 s` instead of the intended `6 × 60 × 7 / 123 = 20.5 s`.

### Reproduction steps

1. Build app: `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
2. Start a Spotify-prepared session including Money by Pink Floyd.
3. Switch to Ferrofluid Ocean preset.
4. Observe wave cycle period during Money playback (~5.85 s, not the intended 20.5 s).
5. `grep "time signature" session.log` returns no matches.
6. `grep "BeatGrid installed" session.log` shows `meter=2/X` for Money.

**Minimum reproducer:** any Spotify-prepared session containing Money (or Pyramid Song's 16/8, or any other odd-meter track where the ML detector guesses wrong).

---

### Session artifacts

**Session directory:** `~/Documents/phosphene_sessions/2026-05-15T17-54-49Z/`

```log
[2026-05-15T17:57:01Z] BeatGrid installed: source=preparedCache, track='Money', bpm=123.2, beats=62, meter=2/X
```

No `Using pre-fetched time signature` lines exist in the file.

---

### Suspected failure class

`api-contract` — Soundcharts' audio-features endpoint doesn't expose `time_signature` (or strips it from the Spotify upstream they proxy). The Phosphene-side override mechanism is wired correctly (Round 26); it has no value to consume.

**Evidence for this class:** Decoder was added with `CodingKeys: time_signature` mapping; field stays nil on every track. ML override path fires (Round 25 / 26 code paths) but with nil input → no-op.

---

### Verification criteria

When this defect is resolved:

- [ ] `session.log` includes `Using pre-fetched time signature: N/X` lines for tracks where the value is known.
- [ ] Money's installed BeatGrid logs `meter=7/X`, not `meter=2/X`.
- [ ] Ferrofluid Ocean wave cycle on Money matches the intended `6 × 60 × 7 / 123 = 20.5 s` period.

**Manual validation required:** Yes — visual confirmation that Money's wave rolls at the calmer 20.5 s cadence.

---

### Fix scope

Three potential paths:

1. **Path B — per-track hardcoded overrides.** Maintain a small JSON config mapping `spotifyID → timeSignature` for known-tricky tracks. Works for the few odd-meter tracks Matt's playlists actually contain; doesn't scale. ~40 lines + manual curation.

2. **Add a different metadata source that exposes `time_signature`.** Spotify's `/audio-features` had the field but was deprecated for most apps in late 2024. AudD or AcousticBrainz might. Each new fetcher = ~150-300 lines of integration.

3. **Improve ML meter detection on odd-meter tracks.** Out of scope for Phosphene application code — would require either retraining Beat This! or post-processing the downbeat probabilities with a meter-specific search.

Current status: deferred. The Round 26 visual review accepted Money's 5.85 s cycle as "smooth and synced — solid." Revisit if/when a future playlist surfaces an odd-meter track where the visual reads wrong.

### Related

V.9 Session 4.5c Rounds 25-26 (metadata-override wiring), Round 21-24 (Gerstner bar-locked motion), BUG-001 (Money 7/4 live-path detection failure — different code path, related cause).


---

### BUG-001 — Money 7/4 stays REACTIVE on live path

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** DSP.3.5 (identified; pre-existing limitation of the 10-second live window)
**Resolved:** —

**Expected behavior:** After 20 seconds of playback (two retry attempts), Beat This! produces a usable BeatGrid for Money 7/4 and `lock_state` advances past UNLOCKED.

**Actual behavior:** Beat This! returns an empty grid on both the 10-second and 20-second attempts. The session stays in REACTIVE mode throughout. `grid_bpm=0` in `features.csv`.

**Reproduction steps:**
1. Start an ad-hoc reactive session (no Spotify preparation).
2. Play "Money" by Pink Floyd in Apple Music.
3. Switch to SpectralCartograph preset and observe mode label.
4. Observe "○ REACTIVE" for the full track.

**Minimum reproducer:** "Money" by Pink Floyd, ad-hoc reactive session.

**Session artifacts:**
- `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md` — contains the evidence and analysis.

**Suspected failure class:** calibration
**Evidence:** 10-second window at 120 BPM gives ~20 beats, which is insufficient for confident downbeat estimation on 7/4 irregular meter. The retry at 20 seconds sees the same 10-second snapshot (not a longer window), so it does not help. The 30-second Spotify-prepared path gives ~61 beats and reliably detects the meter.

**Verification criteria:**
- [ ] Connecting a Spotify playlist that includes "Money" results in a prepared BeatGrid with `beats_per_bar=7` in `KNOWN_ISSUES.md` test notes.
- [ ] Manual: beat grid ticks in SpectralCartograph align to perceived quarter notes.

**Fix scope:** The durable fix is not to tune the live path — it is to use a Spotify-prepared session. The live path (10-second window) is below the beat-count floor for irregular-meter tracks by construction. See `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md` for the evidence. A potential improvement (not yet planned) would be to extend the live-path snapshot to 20–30 seconds on the retry, but this carries a 1.5–2× memory cost per attempt.

**Related:** DSP.3.5, D-077


---

### BUG-005 — Spotify `preview_url` returns null for some tracks

**Severity:** P3
**Domain tag:** session.ux
**Status:** Open
**Introduced:** U.11 (discovered during integration testing)
**Resolved:** —

**Expected behavior:** `PreviewResolver` finds a 30-second preview for every track in a Spotify playlist and preparation completes for all tracks.

**Actual behavior:** Rights-restricted or region-locked tracks return `null` for `preview_url` from Spotify's `/items` endpoint. These tracks fall through to iTunes Search API, which also returns no preview for some of them. Affected tracks show `TrackPreparationStatus.noPreviewURL` in `PreparationProgressView`.

**Minimum reproducer:** Any playlist containing tracks by Mclusky, or region-restricted regional-exclusives.

**Session artifacts:** `session.log` `noPreviewURL` entries.

**Suspected failure class:** api-contract (external API limitation, not a Phosphene bug)

**Verification criteria:**
- [ ] `PreparationProgressView` shows a clear "No preview available" status for affected tracks rather than a spinner or error.
- [ ] Session proceeds to `.ready` state even when some tracks have no preview.

**Fix scope:** UX copy improvement only. The underlying limitation (no preview URL from either Spotify or iTunes) is not fixable by Phosphene. See Failed Approach #47.

**Related:** U.11, D-070, Failed Approach #47


---

## Pre-existing Flakes (non-blocking, test infrastructure only)

These test failures are pre-existing, environment-dependent, and do not indicate behavioral regressions. They are tracked here for completeness.

| Test | Condition | Workaround |
|---|---|---|
| `MemoryReporterTests` growth assertions | `phys_footprint` variance across system memory pressure states | Run with other apps quit; or skip with `SKIP_MEMORY_TESTS=1` |
| `PostProcessChainTests.test_fullChain_under2ms_at1080p` | GPU/CPU contention under the full parallel suite inflates a timed submit past the budget | Re-run in isolation to confirm before treating as a regression |
| `RayMarchPipelineTests.test_fullPipeline_under8ms_at1080p` | Same shape as above (wall-clock assertion around a GPU submit) | Re-run in isolation to confirm before treating as a regression |
| `StemSeparationPerformanceTests.test_separate_1SecondAudio_performance` | Same shape; MPSGraph submit under parallel load | Re-run in isolation to confirm before treating as a regression |

*(The three perf rows were added at RECON.2, 2026-08-03. They were declared "confirmed flake" during the BUG-080 investigation but never reached this table — so each run re-litigated them from scratch. **These are the known-flaky *shape*** — a single wall-clock sample around a GPU submit — that CLEAN.7.9→7.14 fixed elsewhere by asserting the **minimum of N warm samples** rather than one sample, or by removing the timing assumption entirely. Per the deterministic-over-budget-widening rule these three should get the same treatment rather than staying in this table; that is a small, well-precedented increment, not a mystery. Until then: a failure here is not evidence of a regression on its own.)*

**Resolved 2026-07-24 (TESTFLAKE.2)** — `SessionLifecycleGenerationTests.endThenRestart_staleOrphanDoesNotMutateNewSession` (never entered the table above — it failed on **every** full run, 3/3, while passing 3/3 in isolation in 2.7 s; the one suite TESTFLAKE.1's sweep missed). The test asserted the orphaned prep's *timing*: two 10 s `waitUntil` wall-clock polls plus a 2.5 s "sleep past 3 × 600 ms of session A's prep" gap. Under parallel load the case stretched to 73–89 s, the polls starved, and the assertions read session A's stale 3-track plan (`tracks.count → 3` vs 2) before session B's was installed. **The generation guard was verified correct first** (a load-only failure can be a real race): `streamingSessionGen`, the post-`await` staleness check, and every `currentPlan`/state write are all `@MainActor`-isolated with **no suspension point between check and act**, so check-then-act is atomic. Per the deterministic-over-budget-widening rule (CLEAN.7.9 → TESTFLAKE.1), the timing assumption is **removed, not widened**: `startSession` already returns with state + plan installed synchronously (so both polls were unnecessary — the tests now `await` it directly), and the 2.5 s sleep is replaced by awaiting session A's **actual** orphaned prep task, captured before `endSession()` drops the handle. The assertion is now the guard's promise — *whenever* the orphan fires, its completion is rejected — not *when* it fires. `SessionReadyWait` gained an `awaitPrepTask(_:)` overload for a captured handle, keeping the 120 s hang-cap race (a slip must not become a hang). Isolated 2.7 s → 0.042 s; green in 4 consecutive full-suite runs. Test-only, no production delta (`SessionManager` untouched). See `RELEASE_NOTES_DEV.md [dev-2026-07-24-164940]`.

**Resolved 2026-06-16 (CLEAN.7.14)** — `SSGITests.test_ssgi_performance_under1ms_at1080p` made contention-robust (it never entered the table above — it surfaced fresh under the full ~1479-test parallel `swift test` run, the same GPU-heavy parallel load the CLEAN.7.6 flash-safety suite added that exposed this whole flake family). It flaked **two** ways under contention, neither a real regression: (1) an `XCTest measure {}` block benchmarking the 1080p SSGI render **failed on relative standard deviation > 10 %** (XCTest's default bound; ~17.7 % observed) — pure variance; and (2) the real gate computed SSGI overhead as a **5-pair MEAN of (with − without) `Date()` timings**, which folds contention spikes straight into the average. Isolated, all 7 SSGI tests run in ~0.13 s. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10/7.11/7.12), the sub-1 ms gate is **kept, not loosened**: the `measure {}` benchmark is removed and overhead is computed from the **minimum of 8 warm samples per path** — contention can only ADD latency to a GPU submit, so each path's min is its clean true-cost floor and `minSSGI − minBase` is the clean overhead estimate, immune to a few starved samples. The SSGI render path is untouched; test-only, no production delta. (The structural twin — the single-sample ICB frame-perf gate `test_gpuDrivenRendering_cpuFrameTimeReduced` — is fixed the same way in **CLEAN.7.13**, consolidated onto this same branch.) See `RELEASE_NOTES_DEV.md [dev-2026-06-16-e]`.

**Resolved 2026-06-16 (CLEAN.7.13)** — `RenderPipelineICBTests.test_gpuDrivenRendering_cpuFrameTimeReduced` made contention-robust (it never entered the table above — it surfaced fresh under the full ~1469-test parallel `swift test` run during the CLEAN.7.12 closeout). Structurally identical to the CLEAN.7.10 flake: a **single-sample `Date()` wall-clock assertion around one warm ICB frame submit** (blit + compute + render), run inside the parallel suite — a saturated GPU/CPU inflates the lone submit past the 2 ms budget (the case-level time was a benign 0.277 s; the *timed inner submit* blew the gate), while isolated it passes in ~0.37 s. Per the deterministic-over-budget-widening rule (proven on CLEAN.7.9, applied to this exact shape on CLEAN.7.10), the 2 ms gate was **kept, not loosened**: the assertion now takes the **minimum of 8 warm samples** — contention can only ADD latency to a GPU submit, so the min is the clean estimate of true cost and is robust to a few starved samples. The `measure {}` variance block is unchanged. The ICB renderer path is untouched; test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-16-d]`.

**Resolved 2026-06-16 (CLEAN.7.12)** — `UMABufferExtendedTests.test_concurrentWriteRead_noDataRace` made deterministic (it never entered the table above — it surfaced fresh under the full ~1479-test parallel `swift test` run during the CLEAN.7.6 flash-safety closeout, which added GPU-heavy parallel tests that raised pool contention). The test dispatched 200 trivially-fast, lock-free blocks (100 writes + 100 reads to a `UMABuffer`) and asserted a **fixed 30 s** `DispatchGroup.wait(timeout:)` returned `.success`; under contention the GCD thread-pool drain latency exceeded the deadline → `.timedOut` (observed 34.9 s), while isolated the whole class runs in 0.048 s. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10/7.11), the deadline is **removed, not widened**: the test now `wait()`s with no timeout, returning exactly when the blocks drain — it cannot flake on elapsed time, and a genuine deadlock surfaces as a CI hang (same trade as CLEAN.7.11's `await …?.value`). Added a smoke-level post-condition — each writer wrote a distinct index, so after the barrier `buf[i] == Float(i)` for all i — catching gross corruption / lost writes; true data-race detection still requires TSan (per the file header). Test-only, no production delta (`UMABuffer` untouched). See `RELEASE_NOTES_DEV.md [dev-2026-06-16-c]`.

**Resolved 2026-06-15 (CLEAN.7.11)** — `ToastManagerTests.autoDismiss_afterDuration` removed from the table above. The test enqueued a `duration: 0.05` toast then slept a **fixed** wall-clock window (ratcheted 400 ms → 1000 ms and still flaking — CLEAN.2.3.8 closeout, 2026-06-15) before asserting `visibleToasts.isEmpty`; under @MainActor parallel-suite contention the auto-dismiss continuation could slip past the fixed window. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10), the budget is **removed, not widened**: the test now `await`s the actual auto-dismiss `Task` to completion via a new `#if DEBUG` seam `ToastManager.dismissTask(for:)`, so it blocks exactly until the dismissal lands and races no deadline — **this is the fix the row prescribed**. Behavioural intent preserved — a finite-duration toast auto-dismisses; an `.infinity` one schedules no task (early `guard`). Test-only, no production delta (`ToastManager` dismiss logic untouched). See `RELEASE_NOTES_DEV.md [dev-2026-06-15-g]`.

**Resolved 2026-06-14 (CLEAN.7.10)** — `RayIntersectorTests.test_rayTrace_1000Rays_under2ms` made contention-robust (it never entered the table above — it surfaced fresh on the Mac mini during the CLEAN.1 Phase-0 re-confirmation, having passed 1469/1469 on both prior integration closeouts). The failing line was a **single-sample `Date()` wall-clock assertion around one GPU command-buffer submit**, run inside the ~1469-test parallel suite — about the most contention-fragile shape there is: a saturated GPU/CPU inflates any one submit past the 2 ms budget, while isolated the whole class incl. this test runs in 0.42–0.54 s (5/5 green). Per the deterministic-over-budget-widening rule (proven on CLEAN.7.9), the 2 ms gate was **kept, not loosened**: the assertion now takes the **minimum of 8 warm samples** — contention can only ADD latency to a GPU submit, so the min is the clean estimate of true cost and is robust to a few starved samples. The ray-intersector path is untouched by CLEAN.1 (last modified in render increment 3.3); test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-14-a]`.

**Resolved 2026-06-13 (CLEAN.7.9)** — `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` removed from the table above. The wall-clock budget — ratcheted 3 s → 8.25 → 15 → 45 s across prior sessions without ever converging (16.1 s / 22.8 s observed under the ~1460-test parallel suite during the CLEAN.1.x closeouts) — was replaced by a deterministic behavioural assertion: the merged profile carries the fast fetcher's `energy` but **not** the slow fetcher's `bpm` (excluded by the 1 s timeout). The outcome depends only on the 1 s-vs-10 s ordering (the 1 s timer's continuation is enqueued ~9 s before the 10 s one — contention delays both, never inverts them), not on measured elapsed time, so it cannot flake under cooperative-pool contention. Renamed `fetch_networkTimeout_returnsFastResultNotSlow`; adversarially proven to trap a timeout that lets the slow result leak (`bpm → 999` fails `== nil`, a ~10 s block not a hang). Test-only; no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-13-b]`.

**Resolved in the 2026-06-01 hardening pass** (made deterministic — no longer wall-clock-dependent, removed from the table above): `FirstAudioDetectorTests` (ManualDelay), `AppleMusicConnectionViewModelTests` (bounded-yield state polling; never required Apple Music.app — uses `MockAppleMusicConnector`), `SessionManagerTests` lifecycle suite (`waitForReady` safety deadline 3 s → 15 s). `PreviewResolverTests` carries no wall-clock waits or `URLProtocol` stubs in current source — the earlier "rate-limit timing / `.serialized` applied" note did not match the code and was dropped.

---

## Resolved (recent)

*(PUB.3 pruning pass, 2026-07-11: 24 resolved entries moved here from §Open; BUG-013/001/005 reclassified to §Known Limitations. rotate_docs.sh files these to KNOWN_ISSUES_HISTORY.md after 14 days.)*

---

