# Phosphene Full-System Audit & Clean-by-June Backlog — 2026-06-13

> **Status: APPROVED-SCOPE 2026-06-13 (Matt).** June-30 commit = **Phases 0, 1, 2, 5** plus
> elevated gaps **G1** (device route-change), **G2** (sample-rate), **G7/G8** (TSan + E2E),
> **G9** (photosensitivity); Phases 3–4 stretch; 6, bulk-7, 8 after June. Phase 0 reconciliation
> authorized ("full reconcile") — merge BUG-030, prune fully-merged worktrees — with the two
> diverged branches (Glass Brutalist `791857e2`, naughty-goldstine AGC3.6/FBS `46e40ed8`)
> returning to Matt for land/park/discard sign-off before they are touched. Implementation
> follows the increment protocol (tests + docs + evidence per increment; no remote push without
> approval). NOTE: G9/CLEAN.7.6 to be re-sequenced into the June commit during CLEAN.0.4.

## Method & scope

A 17-lane multi-agent audit (36 subagents, ~2.81M tokens, 1,177 tool uses, ~18 min) swept
the codebase + docs across four goals: **(1) stability/reliability/code-quality, (2)
performance, (3) core capabilities, (4) how the project is developed**. Every lane finding
was put through an independent adversarial verifier before admission.

- **181 raw findings → 134 confirmed, 39 refuted, 8 confirmed-but-low-value.**
- Severity of confirmed: **0 P0, 27 P1, 82 P2, 25 P3** (P1/P2 counts include duplicates —
  the concurrency family alone appears ~10× under different titles; deduped distinct issues
  are far fewer, see Part A).
- A completeness critic raised **16 risk classes no lane covered**; I independently verified
  these (Part B) — 11 confirmed, 3 corrected, 2 partial.

**Baseline (verified).** This worktree == `origin/main` == `b581b3aa`, clean (0/0 divergence)
— a solid, current baseline. Production code is **74,786 non-test Swift LOC across 364 files**
+ **19,135 Metal LOC** + 67,141 test-Swift LOC. There is **no CI** (`.github/workflows` absent).
Full raw findings live in this session's workflow output (`tasks/woujsn5i8.output`); the
actionable distillation is below.

## Executive summary — the seven things that matter

1. **One concurrency root cause dominates stability.** A single shared `StemSeparator` is
   driven **unlocked** from both the live-playback and session-prep paths (BUG-031), while
   `endSession()` orphans the prep task (BUG-032) and recovery spawns a *second* concurrent
   prep loop. ~10 findings, one root family (shared mutable instance + ungated session
   generation), plausibly feeding the long-standing BUG-012 MPSGraph crash. **Highest-severity
   cluster; must land as one instrument→fix→validate unit with the currently-missing race tests.**
2. **An app-layer compound P1:** a per-frame `@Published` dashboard snapshot invalidates the
   *entire* SwiftUI tree at 60 Hz even when hidden, and `assign(to:on:self)` retain cycles
   leak the session/playback view models so `deinit` never runs (BUG-033). Perf regression +
   leak in one, self-contained in the app layer.
3. **A distribution-blocker that is cheap to fix:** the Spotify **client secret is baked into
   the shipped `Info.plist`** (extractable from any binary; PKCE doesn't need it). Pull it forward.
4. **The lanes missed several real-world runtime-resilience holes** (Part B), two of them
   arguably P1: **audio output-device change mid-session** (AirPods connect / monitor unplug —
   *the* most common mid-session event — silently freezes visuals; no listener exists, verified)
   and a **sample-rate contract drift** (tap is 48 kHz, `Protocols.swift:111` documents 44.1 kHz
   "resampled," the only resampler is in the local-file path — the live-tap stem/FFT path may run
   at the wrong rate, verified). Also confirmed-absent: thermal/low-power adaptation and DSP
   NaN/Inf guards.
5. **Process debt is the quiet tax:** no CI (one manual `closeout_evidence.sh` gate); ~27
   worktrees with a **stranded P1 fix** (BUG-030's fix is only on `dreamy-bell`, not main); a
   **49 MB diagnostics PNG blob committed loose** (LFS covers `VISUAL_REFERENCES/**/*.png` but
   *not* `diagnostics/**/*.png` — verified) bloating every clone's history.
6. **Manual M7 visual review is the throughput ceiling, not engineering effort.** Every
   renderer/preset-facing fix (Arachne BUG-037, texture-aliasing, all capability work) needs
   Matt's eyes + golden regeneration. With ~17 days and a solo dev, this — not Claude's
   capacity — is why goal-3 capability work and the big decomposition fall after June.
7. **"Clean by June 30" is achievable for stability + security + honest-UI + CI, but not the
   full sweep.** Honest split below: Phases 0–2 + 5 are the realistic June commit; quality/perf
   (3–4) are stretch (M7-throttled); capability (6), bulk test-infra/docs (7), and decomposition
   (8) are after June. The full audit is delivered now regardless; the *backlog* marks timing.

## Reliability of this audit

Verification did its job — it refuted 39 of 181 lane findings (e.g., a MIRPipeline lock claim
that's *already fixed* on main) and corrected 3 of 16 critic gaps (GPU/display: a `DisplayManager`
observer **does** exist; reduce-motion: **is** partially wired; ML weights: a per-tensor `sha256`
manifest **does** exist). Treat the confirmed set as solid and the items flagged "needs deeper
trace" as leads, not facts.

---

## Part A — Verified findings, deduplicated (15 themes)

Each theme groups the confirmed findings sharing a root cause. `→ Pn` is the phase it lands in.

### Stability / reliability

- **T1. Session/stem concurrency family (BUG-031/032)** — `[P1]` → P1.
  Shared unlocked `StemSeparator` across live+prep (`StemSeparator.swift:174-220`, input/predict/output
  outside the lock that only `writeToBuffers:224-235` holds); `SessionManager.endSession():562-566`
  orphans `sessionPreparationTask` (no cancel, unlike `cancel():542-557`); `SessionPreparer.resumeFailedNetworkTracks:509-519`
  spawns a concurrent `_runPreparation` loop; `VisualizerEngine.sessionPreparationTask` ungated by
  session generation; `startSession` source-mutation-before-state-guard. **One root family.**
- **T2. App-layer 60 Hz invalidation + ViewModel retain leaks (BUG-033)** — `[P1]` → P1.
  Per-frame `@Published` dashboard snapshot → whole-tree SwiftUI re-eval at 60 Hz (even hidden);
  `assign(to:on:self)` retain cycles leak `SessionStateViewModel`/`PlaybackChromeViewModel` (deinit never runs).
- **T3. Silent-failure hardening (orchestrator/preset/render-init)** — `[P2]` → P3.
  `PostProcessChain`/`RayMarchPipeline` init failures `try?`-swallowed → broken preset applies anyway;
  `PresetLoader.loadDescriptor` collapses decode errors into default (malformed == missing);
  `PresetScorer.rank()` never filters exclusions (doc-comment contract violated) → reactive path takes
  `.first`; zero-duration track → `catalog.first` fallback bypasses every exclusion gate (can install a
  diagnostic preset, D-074 violation); mood-override cooldown never reset (permanently dead from 2nd play);
  Arachne chord-count constant 3-way inconsistent (CPU 200 / shader 441 / test 104 — BUG-037).
- **T4. Resource leaks: cache eviction, recorder, file handles** — `[P2]` → P3.
  Unbounded in-memory `StemCache` (~7 MB/track, no eviction vs 500 MB disk LRU) → multi-GB under track churn;
  `SessionRecorder` can stop appending while still reporting "running" (BUG-039, recovery landed, invariant missing);
  `openDiagnosticLog()` file handle never closed.
- **T5. Honest-UI: shipped-but-dead controls** — `[P2]` → P2.
  Settings "Local file" mode says "coming in a future update" though LF.5 shipped — selection is a silent
  no-op (`AudioSettingsSection`); two "Use Apple Music instead" footer buttons wired to `{}`
  (`ConnectorPickerView:149,223`); disabled "Swap preset" stub; localization gate only scans `Views/`,
  so ViewModel/ContentView strings bypass `check_user_strings.sh`.

### Performance

- **T6. Real-time audio-thread allocations + redundant DSP (BUG-036)** — `[P2]` → P4.
  Heap allocations on the Core Audio IO-proc at 3 sites (FFTProcessor per-frame array; `AudioBuffer.latestSamples`
  per-element ring read + allocating append under lock; SessionRecorder raw-tap `Data()` copy per callback for 30 s);
  drums FFT computed 2×/frame; autocorrelation recomputed ~85×/frame + lagged-array copies; mono STFT 2×;
  `StructuralAnalyzer`+`NoveltyDetector`+`SelfSimilarityMatrix` run every frame on the hot path with no live consumer.
- **T7. Renderer texture lifecycle, aliasing, over-allocation** — `[P2, some M7]` → P4.
  `PostProcessChain.sceneTexture` permanently aliases ray-march `litTexture` (standalone post-process renders to wrong
  texture); resize handler early-returns on alloc failure → passes left at stale size; feedback ping-pong (~32 MB @ 4K)
  + particle-mode warp pass allocated/run unconditionally even when never sampled; PSO cache keyed by name only
  (ignores pixelFormat/ICB); DynamicTextOverlay races in-flight frames; ray-march aspect guard divides by height (NaN at 0).

### Capability (goal 3)

- **T8. Beat-sync cold-start phase recovery** — `[P1, premise-blocked]` → P6 `[DEC]`.
  Cached BeatGrid installs with possibly-wrong phase; 3 onset-based phase references inherit FA #68 (onsets fire on
  events, not beats); Beat This! on raw tap not cross-capture reproducible (>100 ms drift); live EMA tracker capped at
  ±50 ms — cannot recover wrong-phase grids. **Automated derivation already falsified 6× and retired — needs a new
  premise (human-tap / full-track local analysis / manual calibration) surfaced to Matt before any work.**
- **T9. Structural analysis at section scale (BUG-042)** — `[P2]` → P6.
  Analyzer geometry is note-scale (6.4 s window, 85 ms checkerboard) → emits a "section" every ~1.5 s; orchestrator
  still consumes it. Re-express the stream at ~2 Hz section scale; recalibrate against real session streams (not synthetic).
- **T10. Engine render-capability gaps** — `[P1/P2, M7]` → P6.
  Missing: screen-space scene-texture sampling (blocks refractive 2D presets); per-stage anchor-position metadata
  (blocks Arachne v8 WEB pass); depth attachment for 2D staged presets; whole-scene shake; per-pass GPU timing
  attribution (governor can't scale individual stages). Documented-but-unshipped: light-shafts pass, mesh-shader RT.
  Stranded: Glass Brutalist preset. Unverified-live: Nimbus volumetric-fog 1.65 ms claim. Doc-drift: ARCHITECTURE
  Module Map missing 18 files; `LumenPatternState` stride documented 376 B, actual 568 B.

### Process / how-we-develop

- **T11. Baseline reconciliation: stranded fixes + worktree forest** — `[P1]` → P0 `[DEC]`.
  BUG-030 dup-track-crash fix stranded on `dreamy-bell-23528b` (`679363a9`,`4d95bf88`), issue still open on main;
  ~27 worktrees (incl. ~18 fully-merged) + duplicate tips (`confident-bassi`/`wizardly-galileo`@`791857e2`;
  `brave-newton`/`gifted-wright`@`415328ce`); diverged unmerged work — Glass Brutalist (`791857e2`+5),
  naughty-goldstine AGC3.6/FBS (`46e40ed8`); AUDIT-2026-06-09 P1/P2s not individually filed; no critical-path doc.
- **T12. CI/CD, gate enforcement, build reproducibility** — `[P1]` → P5.
  No automated CI; `closeout_evidence.sh` is the single manual gate; user-strings/sample-rate lints + evidence copy
  unenforced; DocIntegrityTests reports zero tests in Step 4; missing tempo fixtures silently kill 4+ tests in fresh
  worktrees; no build-reproducibility/toolchain pinning; RUNBOOK/RELEASE_CHECKLIST decoupled from real gates.
- **T13. Test-infra gaps + isolation fragility** — `[P1/P2]` → P1 (the P1-guarding tests) + P7 (bulk).
  No race/concurrency regression tests for the BUG-030/031/032 family; no ViewModel deinit/retain-cycle tests for
  BUG-033; SkeinCanvasHold depends on live session captures on disk (BUG-049); app-scheme sandbox blocks 1,439 engine
  tests (BUG-048); no frame-budget/per-frame-allocation regression; no visual/audio-coupling regression (BUG-038/041);
  220+ test files duplicate fixtures with no shared builders; no per-test tags.
- **T14. Documentation archival + drift** — `[P1/P2]` → P7 (small drift fixes June).
  `docs/diagnostics` (~50 MB) and `docs/prompts` grow with no archival automation; CLAUDE.md at the token-budget edge
  (~99%) with no demote candidate; ARCHITECTURE vs CAPABILITY_REGISTRY scope overlap; SHADER_CRAFT vs design-doc
  duplication; stale Module Map + stride.
- **T15. Security: secret exposure + OAuth correctness** — `[P2]` → P2.
  Spotify client secret in shipped `Info.plist`; re-entrant `login()` leaks continuation + arms stray timeout; refresh
  token double-spend (no in-flight dedup); duplicate token providers; `.urlQueryAllowed` corrupts `+` in auth codes;
  no OAuth `state` param; pagination follows API `next` URL without host validation (Bearer exposed to redirects);
  nil playlist response treated as success; unthrottled iTunes artwork resolver; Keychain save/load failures unchecked.

---

## Part B — Coverage gaps the lanes missed (verified 2026-06-13)

The completeness critic surfaced 16 risk classes outside the 17 lanes. I verified each against
the code; **status** records what I confirmed.

| # | Gap | Verified status | Rec. severity | Phase |
|---|-----|-----------------|---------------|-------|
| G1 | **Audio output-device change mid-session** (AirPods/monitor/DAC) freezes visuals silently | **CONFIRMED → FIXED + VALIDATED (CLEAN.1.5; Matt manual validation 2026-06-17):** `kAudioHardwarePropertyDefaultOutputDevice` listener → `performReinstall` keeps visuals live across an AirPods/monitor/DAC swap (12/12 swaps clean; the one un-reproduced freeze is the rare BUG-058 P3). Phase-1 device-route-change gate **closed.** | **P1** | P1 |
| G2 | **Sample-rate contract drift** — tap 48 kHz, `Protocols.swift:111` documents 44.1 kHz resample, resampler only in local-file path | **TRACED (CLEAN.3.7a → BUG-053):** live-tap STEM path resamples correctly (→44.1k); live-tap **MIR/FFT** runs bins at the wrong Nyquist when tap≠48k — the live `MIRPipeline` is frozen at the 48000 default (`VisualizerEngine.swift:740`; `process()` has no rate), so chroma/key shift ~1.5 semitones + bands ~8.8% at 44.1k. Masked at 48k. Fix + doc-reconcile + gate = the BUG-053 fix increment (architectural). | **P2** | P3 |
| G3 | **DSP NaN/Inf/denormal robustness** on audio→GPU path (silence/DC/0-length) | **RESOLVED CLEAN.4.5 (2026-06-18)** — silence/DC/0-len were latent-safe; NaN/Inf *input* (corrupted tap) was a live gap, now sanitized at the FFT entry points (`FFTProcessor` + `StemAnalyzer.computeMagnitudes`) + 2 regression tests. (Was: no `isNaN`/`isFinite` guards in DSP or Audio.) | P2 | P4 ✅ |
| G4 | **Thermal throttling & Low Power Mode** unaddressed on fanless 60 fps + MPSGraph load | **RESOLVED CLEAN.4.6 (2026-06-18, D-167)** — `FrameBudgetManager.thermalFloor` clamps the applied level (`max(timing, floor)`); `VisualizerEngine` observes thermal + LPM notifications → pure `qualityFloor` mapping; pre-empts the GPU throttle, floor survives preset reset. 5 unit tests; device validation pending. (Was: zero `thermalState`/`lowPowerMode` references.) | P2 | P4 ✅ |
| G5 | **GPU device-loss / drawable-invalid** under eviction or display teardown | **PARTIAL** — `DisplayManager` *does* observe `didChangeScreenParameters`; but MTLDevice-loss/command-buffer-error handling absent | P2 | P6 |
| G6 | **Disk-full / write-failure** in SessionRecorder + caches | **CONFIRMED → ADDRESSED (CLEAN.3.8, 2026-06-17):** recorder now `safeWrite`s (throwing + honest halt) + pre-flight `warnIfLowDiskSpace`; cache was already atomic+caught | P2 | P3 |
| G7 | **Dynamic concurrency validation** — no ThreadSanitizer scheme / stress harness | **CONFIRMED** — static review can't prove absence of races; needed to validate the P1 fixes | **P1** | P1 |
| G8 | **End-to-end session-lifecycle integration test** (connect→prepare→play→track-change→end→restart) | **CONFIRMED** — only per-VM unit + beat-grid wiring tests; the orphaning class lives exactly here | **P1** | P1 |
| G9 | **Photosensitivity flash-safety as an enforced invariant** (Harding/WCAG ≤3 flashes/s) | **ENFORCED — 7/7** (CLEAN.7.6 / D-164 + 7.6b Nimbus + **7.6c multi-pass**, 2026-06-16) — `FlashAnalyzer` + `PhotosensitivityCertificationTests` (single-pass: FFO + Murmuration + Nimbus) + `MultiPassFlashHarnessTests` + `RenderPipeline+MVWarpHeadless` (multi-pass headless: Lumen Mosaic rayMarch; Dragon Bloom / Fata Morgana / Skein mv_warp feedback) gate the full certified set — **all 7 measured SAFE (≤ 1 flash/s)** over a worst-case beat + stem train. (CLEAN.7.6/7.6b mislabelled DB+FM "rayMarch"; they are `["direct","mv_warp"]` feedback — corrected by 7.6c.) **CLEAN.7.6d (D-166): runtime clamp NOT pursued — the cert gate is the enforcement mechanism** (no single pipeline chokepoint — 8 present paths; all shipped presets ≤ 1 flash/s; `RayMarchPipeline:94` OR-flag slot reserved). Residual A-next (open): regional-area / saturated-red-flash channels | **P1 (safety)** | **CLOSED (7/7); clamp declined (D-166)** |
| G10 | **macOS entitlement / local threat model** — un-sandboxed app + system audio tap | **CONFIRMED** → ✅ **REVIEWED 2026-06-15 (CLEAN.2.4)** — posture documented in `docs/SECURITY_POSTURE.md`; sandbox-off rationale + minimal-exfiltration strength stated, hardened-runtime/notarization filed as CLEAN.2.5, m3u input validation filed as BUG-051. → **CLEAN.2.5a SHIPPED + VERIFIED 2026-06-15** (hardened runtime + `automation.apple-events` entitlement; build/sign verified `-o runtime`; manual Mac-mini gates verified session `2026-06-15T22-45-34Z` — tap green @ −6 dBFS under HR, Apple-Events accepted). **CLEAN.2.5b deferred** (Developer ID + notarization, blocked on a paid membership) → **GAP-10 fix half-landed, not fully closed.** | P2 | P2 |
| G11 | **ML weight integrity / LFS supply chain** (333 `.bin`) | **LARGELY REFUTED** → ✅ **RESOLVED 2026-06-16 (CLEAN.5.5)** — both narrow Qs were "no", now "yes": load-time `sha256` is validated in **both** on-disk loaders (`BeatThisModel+Weights` / `StemModel+Weights` via shared `WeightChecksum`, fail-loud `checksumMismatch`), and the stem manifest gained 172 per-tensor digests hashed from the **committed** bytes (`tools/add_stem_weight_checksums.py`). GPU-free `WeightChecksumTests` (reject / accept / completeness gate / real-loader happy path) on the CI fast gate; empirical one-byte tamper throws. MoodClassifier excluded (compiled-in arrays, no file). | P3 | P5 |
| G12 | **Cold-install / resource-bootstrap** (LFS absent, no weights/fixtures/permissions, empty defaults) | **PLAUSIBLE (untested)** — no first-run-degraded path verified | P2 | P7 |
| G13 | **Build reproducibility & toolchain pinning** (Package.resolved, Xcode/Swift, LFS-present check) | **CONFIRMED class** (decompose of the CI finding) | P2 | P5 |
| G14 | **Loose diagnostic artifacts bloating repo** (`docs/diagnostics` 50 MB) | **CONFIRMED** → ✅ **RESOLVED 2026-06-17 (CLEAN.7.4)** — prevention landed DOC.7 (`.gitattributes` LFS-tracks `docs/diagnostics/**/*.png`+`.jpg`; loose V9 PNGs pruned; 0 PNGs tracked in HEAD). History-rewrite to purge the 17 historical PNG blobs (35 MiB packed) **DECLINED** (Matt) — ≈ 3% of an LFS-dominated 1.2 GB clone, not worth force-pushing main amid parallel sessions. `rotate_docs.sh` §(d) now flags large non-LFS files in diagnostics/prompts for the manual pruning pass. | P2 | P7 done |
| G15 | **Reduce-Motion / reduce-transparency / contrast a11y** | **PARTIAL** — reduce-motion wired init-only (Ready border), not live/app-wide; transparency/contrast absent | P3 | P7 |
| G16 | **Memory-footprint absolute baseline + soak-growth ceiling** | **CONFIRMED** — `MemoryReporter` exists; no budget/regression gate on peak/steady-state RSS | P2 | P4 |

---

## Part C — Phased, incremented backlog

Tags: `[M7]` needs Matt visual review + golden regen · `[P1-proc]` multi-increment P1 protocol
(instrument→diagnose→fix→validate) · `[GAP-#]` from Part B · `[DEC]` needs a Part-D decision.
Timing: **June** (committed target) · **Stretch** (June if M7/capacity allows) · **After**.
IDs are proposed (`CLEAN.<phase>.<n>`); on approval they map into ENGINEERING_PLAN as Phase CLEAN.

### Phase 0 — Clean integrated baseline (June, blocks everything) `[DEC D1]`
| ID | Item | Done-when | Timing |
|----|------|-----------|--------|
| CLEAN.0.1 | Merge stranded BUG-030 fix from `dreamy-bell` (`679363a9`,`4d95bf88`) to main | on main; KNOWN_ISSUES BUG-030 = Resolved; dup-playlist repro green | June |
| CLEAN.0.2 | Triage diverged branches (Glass Brutalist `791857e2`+5; naughty-goldstine AGC3.6/FBS `46e40ed8`) | each = land / park / discard, recorded | June `[DEC]` |
| CLEAN.0.3 | Green-baseline verification on main | `closeout_evidence.sh` block: engine+app build, tests, swiftlint --strict, DocIntegrity all green; tempo-fixture-missing fixed | June |
| CLEAN.0.4 | File audit backlog as trackable issues + land this plan as ENGINEERING_PLAN Phase CLEAN + write critical-path sequencing doc | every P1/P2 pickable; plan rows exist | June |
| CLEAN.0.5 | Prune ~18 merged worktrees + duplicate tips; document a minimal worktree-hygiene rule | merged worktrees gone; rule in RUNBOOK | June `[DEC]` |

### Phase 1 — P1 correctness: concurrency, leaks, runtime resilience (June, core)
| ID | Item | Done-when | Timing |
|----|------|-----------|--------|
| CLEAN.1.1 | Instrument + diagnose BUG-031/032 family | logging/scaffolding exposes unlocked stem I/O + orphan hijack; root cause in KNOWN_ISSUES (commit, stop) | June `[P1-proc]` |
| CLEAN.1.2 | BUG-031 fix: serialize StemSeparator across live+prep (lock full input→predict→output, or per-path instance; return-by-value) | race regression test red-pre/green-post | June |
| CLEAN.1.3 | BUG-032 fix: cancel prep in `endSession`; gate prep by session generation; stop `resumeFailedNetworkTracks` second loop; fix source-mutation-before-guard | lifecycle + failure-path tests | June |
| CLEAN.1.4 | BUG-033 fix: decouple/throttle dashboard snapshot off per-frame + skip when hidden; `[weak self]` for assign | ViewModel deinit/retain tests; no 60 Hz tree invalidation | June |
| CLEAN.1.5 ✅ | `[GAP-1]` Audio output-device route-change handling | device-change listener → tap reinstall; manual AirPods/monitor swap keeps visuals live | **DONE + VALIDATED 2026-06-17** (Matt manual: 12/12 swaps keep visuals live; rare BUG-058 P3 the only residual). Phase-1 fully complete. |
| CLEAN.1.6 | `[GAP-7]` ThreadSanitizer scheme + concurrency stress harness (overlapping live+prep, rapid start/end churn) | TSan-clean under stress; validates 1.2–1.3 | June |
| CLEAN.1.7 | `[GAP-8]` E2E session-lifecycle integration test | drives connect→prepare→play→track-change→end→restart; would catch the orphan class | June |

### Phase 2 — Security + honest-UI (June)
| ID | Item | Done-when | Timing |
|----|------|-----------|--------|
| CLEAN.2.1 | Remove Spotify client secret from bundled `Info.plist` (PKCE) | secret absent from build; auth-code flow verified E2E | June |
| CLEAN.2.2 | OAuth correctness: fix re-entrant `login()` leak + stray timeout, refresh double-spend (in-flight dedup), consolidate token providers; + P3s (state param, encoding, host validation, Keychain checks) | tests for re-entrancy/refresh; providers unified | June |
| CLEAN.2.3 | Wire-or-hide dead UI (LF capture-mode picker, two "Use Apple Music" no-ops, Swap-preset stub) + close localization-gate bypass | no shipped no-op control; checker scans ViewModels/ContentView | June |
| CLEAN.2.4 | `[GAP-10]` macOS entitlement / local threat-model review ✅ **REVIEWED 2026-06-15** | documented posture: tap PID scope, hardened-runtime/library-validation, notarization; fixes filed → `docs/SECURITY_POSTURE.md`; filed **CLEAN.2.5** (hardened runtime + notarization, distribution planned) + **BUG-051** (m3u input validation, P3). Closes Phase 2. | June ✅ |
| CLEAN.2.5a | `[GAP-10 fix, HR half]` Enable hardened runtime + Apple Events entitlement (split from 2.5, Matt 2026-06-15) | HR on (app-target-scoped, signs `-o runtime`); `automation.apple-events` added; library validation left on; build + sign verified. Done-when: builds + signs green (✅) **+ manual Mac-mini gates** — launches under HR ✅, `.systemAudio` tap delivers audio ✅ (−6 dBFS, 11.4k live frames), Apple-Events entitlement accepted ✅ (session `2026-06-15T22-45-34Z`) | June ✅ (verified 2026-06-15) |
| CLEAN.2.5b | `[GAP-10 fix, signing half]` Developer ID signing + notarization + Gatekeeper test | switch `CODE_SIGN_IDENTITY` → Developer ID; `notarytool submit --wait` + `stapler staple`; `spctl --assess` + clean-account first launch; library validation stays on | **Deferred — blocked on a paid Apple Developer Program membership**; mechanical once cert + notarization key exist |

### Phase 3 — P2 quality hardening (June/Stretch)
| ID | Item | Done-when | Timing |
|----|------|-----------|--------|
| CLEAN.3.1 ✅ | Surface init failures (PostProcess/RayMarch refuse-or-fallback loudly; PresetLoader distinguishes malformed vs missing) | logged + observable; no silent broken preset | **DONE 2026-06-17** — `PresetLoader.decodeSidecar` splits missing (`.info`) vs malformed (`.error` + real decode error); `.postProcess` call-site now `do/catch` surfaces the real `PostProcessError` (rayMarch + shader-compile already loud). `PresetLoaderSidecarTests` (3). |
| CLEAN.3.2 ✅ | PresetScorer exclusion-filter contract + zero-duration `catalog.first` bypass | excluded/diagnostic presets can never install; test | **DONE 2026-06-17** — zero-duration fallback now picks the best *eligible* preset (shared `categoricallyEligiblePool`), never raw `catalog.first`; `rank()` doc states the `.first(where: { $0.1 > 0 })` install idiom + `ReactiveOrchestrator` tightened to it. Tests: `zeroDurationTrack_neverInstallsDiagnostic`, `rankContract_excludedKeptButNotInstallable`. |
| CLEAN.3.3 ✅ | Mood-override cooldown reset across repeat plays/sessions; report swallowed attempts | override survives 2nd play; test | **DONE 2026-06-17** — `cooldownAdaptation` now treats a backwards per-track clock (replay / new session reset it) as no active cooldown, so a stale timestamp can't permanently suppress override from play 2. Swallowed attempts already reported (the suppression `.moodDivergenceDetected` event is logged at `VisualizerEngine+Orchestrator:198`). Test: `moodOverrideCooldown_survivesReplay`. |
| CLEAN.3.4 ✅ | BUG-037 Arachne chord-count single source of truth (CPU/shader/test) | one constant; goldens regen | **DONE + VALIDATED 2026-06-18.** CPU `spiralChordsTotal` single source (hardcoded 441 + test's 104 retired; 200 cap → `maxSpiralChords=600`). M7 (2026-06-18T01) **failed** — real dominant cause was the build outliving its planned section; fix extended: `wait_for_completion_event` now spans sections (`planOneSegment`/`coveredUntil`). Matt re-validated 2026-06-18T14 — full web to completion, no pop. Tests `spiralChordCountHonoursProduct`, `spiralRevealClimbsPastOldCeiling`, `waitForCompletion_segmentSpansSections`. BUG-037 Resolved. |
| CLEAN.3.5 ✅ | StemCache eviction (size/LRU); close diag-log handle; retire dead helpers (`percentileOfBuffer`,`printHistogram`,`depthDebugEnabled`) | bounded cache; handle closed; dead code gone | **DONE 2026-06-17** — `StemCache` now LRU-bounded (`maxEntries`, default 64 ≈ 450 MB); `diagLog` closed before reopen + in `deinit`; the three dead helpers deleted. Test: `StemCacheEvictionTests`. |
| CLEAN.3.6 ✅ | SessionRecorder running-vs-actually-writing invariant (BUG-039 follow-through) | invariant asserted; recovery confirmed | **DONE 2026-06-17** — `finish()` now asserts the invariant (append-success counter → video-outcome summary + loud `BUG-039 invariant VIOLATED` on the silent-stop signature); recovery test extended to confirm appends resume. Tests: `test_bug039Invariant_silentStopPredicate`, `test_videoWriterDeath…`. BUG-039 closure still pends Matt's live multi-session confirm. |
| CLEAN.3.7a ✅ | `[GAP-2]` Trace & decide: does the live-tap path deliver the correct rate to every rate-sensitive stage? | **DONE 2026-06-16** — traced end-to-end; verdict = real (latent) defect, **BUG-053**: live MIR frozen at 48k (stem path correct). Refutes the "already rate-aware" hypothesis. | June |
| CLEAN.3.7-fix ✅ | `[GAP-2]` Fix the live-MIR rate wiring + reconcile doc + add regression gate (was 3.7b/c) | live MIR consumes the actual tap rate; doc matches code; gate locks it | **code-complete `91a973e` (2026-06-16); pending Matt's manual 44.1 kHz / LF-playback key check** before BUG-053 → Resolved |
| CLEAN.3.8 ✅ | `[GAP-6]` Disk-full / write-failure graceful degradation (recorder, caches) | capacity check + honest stop, no silent corruption | **DONE 2026-06-17** — SessionRecorder per-frame/log writes routed through `safeWrite` (throwing `write(contentsOf:)` + halt-on-failure, replacing the crash-prone non-throwing `FileHandle.write`); pre-flight `warnIfLowDiskSpace`. PersistentStemCache already safe (atomic + caught `store`). Tests: `test_diskGuard_capacityPredicate`, `test_diskGuard_haltStopsFurtherWrites`. |

### Phase 4 — Performance (June/Stretch, partly M7)
| ID | Item | Done-when | Timing |
|----|------|-----------|--------|
| CLEAN.4.1 ⏳ | BUG-036 remove RT-thread allocations (preallocate FFT buffers; allocation-free `latestSamples`; raw-tap copy off RT thread) | allocation-on-RT-thread regression test | **PARTIAL 2026-06-17 (`58a37c0`)** — sites 1+2 (FFT `magnitudesScratch` + zero-alloc `processStereo(interleaved:)`; `latestSamples(into:)`) done, pointer↔array byte-identical + 3 regression tests; site 3 (raw-tap) + analysis hand-off deferred to **BUG-043** (cross-thread → needs a pre-alloc ring + persistent-consumer drain). Pending Matt's no-glitch validation. |
| CLEAN.4.2 ✅ | Remove redundant DSP compute (drums FFT 2×, autocorrelation ~85×, mono STFT 2×) | single-compute; perf delta recorded | **DONE 2026-06-18.** Three output-preserving dedups: (A) `BeatDetector+Tempo` swept the autocorrelation range twice (`findBestLag` + the confidence loop) → one `autocorrelationSweep` accumulating best-lag + mean, offset pointers replacing the ~85 per-lag `Array(linear[...])` slice copies (zero per-call allocs); (B) `StemAnalyzer` discarded `analyzeStem`'s drums mags with `_` then recomputed an identical FFT → reuse the returned mags (−1 FFT/frame); (C) `StemSeparator` ran the identical 4096-pt STFT twice for mono input (`deinterleave` → `(audio, audio)`) → reuse the left STFT when `channelCount < 2` (−1 STFT/mono-track). Output-equivalent: 9 BeatDetector tempo/onset tests + StemAnalyzer suite green; new `test_separate_monoReusesStereoStft_outputUnchanged` proves mono ≡ stereo-duplicated (<1e-5). swiftlint 0. |
| CLEAN.4.3 ✅ | Renderer texture aliasing + resize stale-size fix (correctness-flavored) | standalone post-process renders correct texture; goldens regen | **DONE 2026-06-18 — output-preserving; goldens byte-identical, so NO regen and the `[M7]` tag was precautionary (same as 4.4).** (A) `PostProcessChain.runBloomAndComposite` clobbered `self.sceneTexture` with the external ray-march texture and never restored it (a standalone `.postProcess` preset then rendered into + leaked it) → save + `defer`-restore; passes still read the external texture during the call (identical output). (B) resize handler `return`ed on a feedback-alloc failure, stranding post-process/ray-march/mv_warp at the stale size → drop the feedback pair, fall through so the rest resize. (C) ray-march aspect guard checked `width` but divided by `height` (+inf at h=0) → guard the divisor. PresetRegression byte-identical (20×3); new `test_runBloomAndComposite_restoresOwnSceneTexture` (PostProcessChainTests 7/7); DrawableResize/RayMarch/BloomGate green; swiftlint 0. **Out of scope:** DynamicTextOverlay in-flight race (unfiled). |
| CLEAN.4.4 ✅ | Gate feedback ping-pong + particle-warp alloc/exec to presets that sample; fix PSO cache key (pixelFormat/ICB) | no wasted alloc/pass; cache key correct | **DONE 2026-06-17.** (A) PSO cache → `PipelineKey(name, pixelFormat, supportICB)` — **latent, not live** (unique names per caller; preset PSOs bypass the cache; `supportICB:true` test-only). (B) ping-pong + particle warp gated to surface-mode feedback (`activePresetSamplesFeedback`); freed on switch-away; particle-mode warp skipped. Output-preserving (PresetRegression goldens byte-identical). Gates: `ShaderLibraryTests`+2, `DrawableResizeRegressionTests`+3. **T7 remainder still open:** sceneTexture aliasing + resize stale-size → CLEAN.4.3 (M7); ray-march /height NaN → 4.3/4.5; DynamicTextOverlay in-flight race → unfiled (not confirmed in 4.4). |
| CLEAN.4.5 ✅ | `[GAP-3]` NaN/Inf robustness sweep on audio→GPU path | degenerate-audio (silence/DC/0-len) produces no NaN in SceneUniforms | **DONE 2026-06-18 — part latent, part live.** GPU-bound audio structs = FeatureVector (48 floats, buffer 0) + StemFeatures (buffer 3), both scanned field-by-field. **Silence/DC/cold-start already produce no NaN** (zero-sum conditionals + `1e-8` EMA floors) — done-when cases latent-safe. **But NaN/Inf in the *input samples* (corrupted tap — `NaN/1e-8 = NaN`, the floors can't catch it) propagated to both structs** — a live gap. Fixed by sanitizing at the FFT entry points (`FFTProcessor.process` + `processStereo(interleaved:)`; `StemAnalyzer.computeMagnitudes`): non-finite → 0, output-preserving for finite audio (PresetRegression byte-identical). Gates: 2 new degenerate-audio integration tests (both fail pre-fix on NaN-input). swiftlint 0. **Out of scope:** `GridOnsetCalibrator.computeMagnitudes` (preparation-time CPU calibration, not a per-frame GPU producer). |
| CLEAN.4.6 ✅ | `[GAP-4]` Thermal + Low Power Mode adaptation → budget governor | `thermalStateDidChange` pre-empts throttle; LPM respected | **DONE 2026-06-18 (D-167).** `FrameBudgetManager` gains `thermalFloor`; applied level = `max(currentLevel, thermalFloor)` → thermal pre-empts the timing downshift, clears immediately. FBM stays `ProcessInfo`-free; `VisualizerEngine` observes `thermalStateDidChange` + `NSProcessInfoPowerStateDidChange` → pure `qualityFloor(thermalState:lowPowerMode:)` (serious→no-bloom, critical→step-0.75, LPM→≥no-SSGI). 5 new FBM tests; engine + app build clean. Ultra/recording still exempt. **Manual gate:** device validation under real thermal load (Mac mini rarely throttles — matters for fanless). |
| CLEAN.4.7 | `[GAP-16]` Memory-footprint soak baseline + peak-RSS regression gate | steady-state + 2 h growth curve measured; gate added | After |

### Phase 5 — DevOps: CI/CD + gate enforcement (June, high leverage)
| ID | Item | Done-when | Timing |
|----|------|-----------|--------|
| CLEAN.5.1 ✅ | CI pipeline: build + engine/app tests + swiftlint --strict on push/PR | green on main; required check | ✅ 06-15 — **GREEN on `main` (run #4, `86c6532`)** after 3 CI-vs-dev env fixes (macos-26 for Sendable-Metal SDK; `#require` for swiftlint 0.63.3 drift; drop Apple-Music `PlaylistConnector`); the **required-check branch-protection toggle is the only part pending Matt** |
| CLEAN.5.2 ✅ | Bootstrap gitignored tempo fixtures (+ env) in CI and for fresh worktrees | parallel-session worktrees no longer silently red | ✅ 06-15 — `Scripts/bootstrap_fixtures.sh` (cp-from-primary → fetch fallback); CI fast gate runs no fixture tests so needs none |
| CLEAN.5.3 ✅ | Wire `check_user_strings.sh` + `check_sample_rate_literals.sh` + DocIntegrityTests; fix closeout Step-4 zero-tests reporting | lints enforced in CI; Step 4 reports real counts | ✅ 06-15 — both lints + DocIntegrity wired as CI steps; `closeout_evidence.sh` Step-4 stops printing "Executed 0 tests" for swift-testing-only suites |
| CLEAN.5.4 ✅ | `[GAP-13]` Build reproducibility: pin toolchain + Package.resolved + LFS-present check | documented reproducible build; missing-LFS fails fast | ✅ 06-15 — `.xcode-version` (26.5, exact-select-or-fail-loud), SwiftLint 0.63.2 pinned (portable binary, not `brew` latest), both `Package.resolved` committed + built with `-disableAutomaticPackageResolution` / `--only-use-versions-from-resolved-file`, `Scripts/check_lfs_smudged.sh` pre-build gate; **5.7's SHA-pin folded in** (`checkout@df4cb1c` = v6.0.3) |
| CLEAN.5.5 ✅ | `[GAP-11]` Verify ML weight loader validates `sha256`; extend coverage to stem manifest | load-time checksum gate confirmed/added | ✅ 06-16 — load-time `sha256` validated in both on-disk loaders (shared `WeightChecksum`, fail-loud `checksumMismatch`); 172 stem digests generated from committed bytes; GPU-free `WeightChecksumTests` (incl. completeness gate) on the CI fast gate; empirical one-byte tamper throws. **Phase 5 fully closed.** |
| CLEAN.5.6 ✅ | Reconcile RUNBOOK / RELEASE_CHECKLIST with real gate structure | docs match closeout + CI reality | ✅ 06-15 — RUNBOOK §Gate structure added (CI fast gate vs manual closeout) |
| CLEAN.5.7 ✅ | Keep GitHub Actions on a supported Node runtime (Node 20 actions deprecated 2026-06-16) | actions on Node 24; no deprecation warning | ✅ 06-15 — `actions/checkout@v4` → `@v6` (the only Node-based action; runs on Node 24). Exact-SHA pinning is CLEAN.5.4 |

### Phase 6 — Capability (goal 3) (After June; M7 + premise-gated)
| ID | Item | Timing |
|----|------|--------|
| CLEAN.6.1 | `[DEC]` Beat-sync cold-start: surface premise change to Matt (human-tap / full-track local / manual calibration). **Do NOT iterate the retired automated path.** | After |
| CLEAN.6.2 | BUG-042 re-express structural stream at ~2 Hz section scale; recalibrate vs real session streams; re-express BUG-035/040 tests | After |
| CLEAN.6.3 | Screen-space scene-texture sampling (unblocks refractive 2D) `[M7]` | After |
| CLEAN.6.4 | Per-stage anchor-position metadata (Arachne v8 WEB); depth attachment; whole-scene shake; per-pass GPU timing `[M7]` | After |
| CLEAN.6.5 | Land/verify Glass Brutalist; verify Nimbus fog live; wire-or-retire light-shafts + mesh-RT infra | After |
| CLEAN.6.6 | `[GAP-5]` GPU device-loss / drawable-invalid recovery | After |

### Phase 7 — Process: test-infra + docs + safety (June small / After bulk)
| ID | Item | Timing |
|----|------|--------|
| CLEAN.7.1 | BUG-049 SkeinCanvasHold isolation; BUG-048 app-scheme sandbox (1,439 engine tests) | June/Stretch |
| CLEAN.7.2 | Frame-budget/per-frame-allocation regression; visual/audio-coupling regression (BUG-038/041); shared fixture builders; per-test tags | After |
| CLEAN.7.3 | Doc-drift quick fixes: ARCHITECTURE Module Map; `LumenPatternState` 376→568 B; canvas-hold spec | June |
| CLEAN.7.4 ✅ | `[GAP-14]` Extend `rotate_docs.sh` to diagnostics/prompts; remediate the un-LFS'd 49 MB PNG blob | **DONE 2026-06-17 (`5fdb1a3`)** — rotate_docs §(d) report-only flag for large non-LFS files in diagnostics/prompts (red-armed). Blob: prevention landed DOC.7; history-rewrite **DECLINED** (Matt — 35 MiB packed ≈ 3% of an LFS-dominated clone, not worth a force-push). |
| CLEAN.7.5 | Resolve ARCHITECTURE↔CAPABILITY_REGISTRY + SHADER_CRAFT↔design-doc overlap; create a CLAUDE.md demote candidate to regain budget | After |
| CLEAN.7.6 | `[GAP-9]` `[DEC D-164]` Photosensitivity: certifiable flash-safety invariant — **measurement gate ✅ ENFORCED 7/7** (FFO + Murmuration [7.6] + Nimbus [7.6b] + Lumen Mosaic / Dragon Bloom / Fata Morgana / Skein [**7.6c** multi-pass headless], all SAFE, 2026-06-16); DB+FM are mv_warp feedback (not rayMarch — 7.6/7.6b mislabel, corrected by 7.6c). Output-side luminance clamp → **CLEAN.7.6d (D-166): NOT pursued** — cert gate is the enforcement mechanism | June ✅ (7/7) / clamp declined (D-166) |
| CLEAN.7.7 | `[GAP-15]` Live/app-wide Reduce-Motion + reduce-transparency + increase-contrast | After |
| CLEAN.7.8 | `[GAP-12]` Cold-install / resource-bootstrap resilience (degraded-but-honest first run) | After |

### Phase 8 — Large-unit decomposition (QR.6) (After June; XL; M7/soak-gated)
| ID | Item | Timing |
|----|------|--------|
| CLEAN.8.1 | Plan QR.6: map VisualizerEngine responsibilities + lock ownership; define seams + soak safety net | After |
| CLEAN.8.2 | Decompose VisualizerEngine (5.1k LOC, 8 NSLocks, @unchecked Sendable) — **after** BUG-031/032/033 stabilize the lock structure | After |
| CLEAN.8.3 | Decompose RenderPipeline switchboard (24 NSLocks); document pass ordering (closes state-aliasing risk) | After |
| CLEAN.8.4 | Modularize large preset-state files (ArachneState, SkeinState, LumenPatternEngine, LiveBeatDriftTracker) where it cuts real coupling | After |

---

## Part D — Decisions needed from Matt

- **D1. Worktree/branch reconciliation (blocks Phase 0).** Authorize: (a) merge BUG-030 fix to main;
  (b) prune ~18 fully-merged worktrees + duplicate tips; (c) disposition of the diverged branches
  carrying possibly-valuable unmerged work (**Glass Brutalist**, **naughty-goldstine AGC3.6/FBS**) —
  land, park, or discard. You know which worktrees are actively in use; I won't touch any without your go.
- **D2. June-30 committed scope.** The full audit is delivered; the *backlog* needs a ceiling.
  Recommendation: commit **Phases 0, 1, 2, 5** by June 30; treat **3, 4** as stretch (M7-throttled);
  **6, 7-bulk, 8** after June. Confirm or re-weight.
- **D3. Elevate which gaps into June?** Recommend folding **G1 (device route-change)**, **G2
  (sample-rate contract)**, **G7 (TSan)**, **G8 (E2E lifecycle)** into the June commit (already placed
  in P1/P3). Confirm — and decide whether **G9 (photosensitivity, safety/legal)** is a June priority or
  a tracked-after item.
- **D4. Cold-start beat-sync (T8/CLEAN.6.1).** Automated phase derivation is retired (falsified 6×).
  Any further beat-sync work needs a *new premise* (human-tap reference / full-track local-file analysis
  / manual per-track calibration UX). This is a product decision — flag if/when you want to scope it.

---

## Part E — Sequencing notes & risks

1. **Reconcile-before-fix is the gating risk.** BUG-031/032 touch the same `SessionPreparer` surface as
   the stranded BUG-030 fix; if Phase 0 doesn't land first, the fixes risk colliding with or re-implementing
   stranded work. (BUG-034 is already on main — only its golden-maintenance test-infra class remains.)
2. **The concurrency family is one root cause** — land instrument→fix→validate as a unit with the missing
   race/lifecycle tests + TSan (CLEAN.1.6); it plausibly also retires BUG-012.
3. **M7 visual review is the throughput ceiling.** Batch all `[M7]` items (BUG-037, texture fixes, capability)
   into a few review sittings; this is why goal-3 and decomposition are after June.
4. **Sequence perf/structural against shared files.** RT-audio (BUG-036) and the every-frame structural cluster
   share `StemAnalyzer`/`StemSeparator`/`NoveltyDetector` with the concurrency + BUG-042 work — land locking first,
   then allocations, then section-scale, or they thrash the same code.
5. **CI ideally precedes the heaviest fix volume** but needs a green baseline — hence Phase 5 mid-sequence;
   a minimal build+test CI could be pulled into Phase 0/1 to gate everything else if capacity allows.

---

## Appendix — refuted/corrected (transparency)

39 lane findings were refuted on verification (e.g., `MIRPipeline.latestStructuralPrediction` is **already**
lock-scoped on main — the audit-doc entry predates the fix). 3 of 16 critic gaps were corrected (G5 DisplayManager
exists; G11 sha256 manifest exists; G15 reduce-motion partially wired). Full per-finding verifier notes are in the
session workflow output (`tasks/woujsn5i8.output`) — not committed here to avoid the very repo-bloat G14 flags.
