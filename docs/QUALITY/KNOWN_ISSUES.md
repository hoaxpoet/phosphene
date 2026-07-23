# Phosphene — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

## Open Index

| ID | Sev | Domain | One-liner |
|---|---|---|---|
| BUG-071 | P1 | preset.fidelity / sdf-geometry | **Fractal Descent live M7 FAILED (session `2026-07-23T19-27-48Z`, Cherub Rock):** "deeply glitchy, camera moves OUT not IN." Root causes (confirmed from artifacts + repro renders): (1) **descent direction inverted** — `q=(p+c)*zoom` with zoom increasing collapses features toward a vanishing point (recede); confirmed by a phase-0.08 vs 0.90 sweep (features shrink as phase grows) and by `features.csv` (accAudioTime 0→8.15 → phase 0→0.98 monotonic = one-way recede, never wrapped); (2) **severe shimmer/aliasing** — full-res Mandelbox fine detail + the high-frequency iridescent thin-film rims alias under motion (no AA; MetalFX unwired; the §A8 motion-coherence cap was never added; the whole-frame motion-gate spike metric doesn't catch high-freq shimmer); (3) **descent too slow** — 0.12 rate gave <1 octave in 78 s. Fix: invert to `q=(p+c)/zoom` (fall in), tame/detune the thin-film + distance-fade fine detail, raise the rate. |
| BUG-070 | P2 | audio.capture / resource-management | **Fix landed 2026-07-12 (PUB.6), pending live validation** — a FAILED device-change tap reinstall left `_isCapturing=true` with zero callbacks: engine health detectors starved (SignalHealthMonitor.evaluate is sample-driven → deadTap never confirms) and the router's recovery restart blocked at the alreadyCapturing guard; only the app-layer poll-based stall card surfaced it. Fix: the catch now clears `_isCapturing` (recovery unblocked) and keeps the monitor as a diagnostic beacon; the false "create steps stopped the monitor" comment corrected. Residual OPEN half: the 3-queue lifecycle interleave (device-change reinstall vs silence-recovery vs user stop) stays unserialized — static-only evidence; restructuring the G1-validated (12/12) path without a reproduced artifact is the BUG-063 pattern. Existing breadcrumbs (per-step diagnostics + install generation) are the instrumentation; serialize only if a live session shows an interleave |
| BUG-065 | P3 | dsp.beat | **Live BeatGrid phase drifts off the audible beat over a track** — the cached grid has the right BPM but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it: drift grows ~11 ms (track start) → **50–70 ms (mid/late-track)**, and **28 % of frames exceed the ~60 ms perceptual window** (evidence: session `2026-06-29T12-43-51Z`, Cherub Rock 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; lock_state=2 only 67 %-within-60 ms). **Caps how frame-locked beat-driven presets can feel** — the live example is Glaze's GLAZE.7 downbeat push (reads connected but not *tight*; tightest early, loosens as the track plays). NOT a functional break (phase is approximately right). **Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is **mid-track drift convergence** — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session |
| AUDIT-2026-06-09 | P2/P3 | audit backlog | Full-codebase audit findings not individually filed |
| BUG-060 | P3 | renderer / app.hang | One-off app hang (force-quit required): render loop died one frame after a `preset → Gossamer` switch (`22-10-50Z`); NOT reproduced (Gossamer ran 3× clean in `13-57-23Z`); no stack captured. Monitored |
| BUG-058 | P3 | audio.capture / resource-management | RARE intermittent: a mid-session output-device swap *occasionally* freezes the tap (`performReinstall` doesn't complete; stale-buffer freeze, not silence). G1 device-swap recovery is otherwise robust (validated 12/12, 2026-06-17); the single freeze was un-reproduced — likely a `coreaudiod`-settling transient. Instrumented |
| BUG-056 | P3 | local-file / audio | Local-file playback restarts the track from the top on an output-device change (AVAudioEngine teardown/restart, no resume-from-position) |
| BUG-055 | P2 | app.ui / permission | Silent system-audio tap after a rebuild: stale Screen-Recording grant; `CGPreflightScreenCaptureAccess` returns stale-`true` → app shows "ready", renders a flatline, no guidance |
| BUG-054 | P3 | dsp.key | Key detection has never been accurate enough to use — 1024-pt FFT can't resolve semitones < 1 kHz, full-mix chroma, no constant-Q. Non-load-bearing today |
| BUG-051 | P3 | local-file / security | m3u entry paths resolved with no extension/traversal guard (bounded: no egress) |
| BUG-036 | P2 | audio.capture / performance | Heap allocations on the real-time audio thread (three sites) |
| BUG-041 | P2 | dsp.stem / preset.fidelity | FFO aurora flashes at track start (stem-deviation cold-start overswing) |
| BUG-028 | P2 | dsp.beat | Beat-grid live phase imperfect on ~half of tracks |


---

## Open

---

### BUG-071 — Fractal Descent: descent direction inverted + severe motion aliasing (2026-07-23)

**P1 · preset.fidelity / sdf-geometry · FIXES LANDED (direction, zoom target, anti-aliasing), live re-test pending.**

**Expected:** a continuous fall INTO an ever-elaborating fractal cathedral; stable under motion.
**Actual (Matt live M7, session `2026-07-23T19-27-48Z`, Cherub Rock):** "Deeply glitchy. The camera is moving out / away vs. in… at the beginning the music response was chaotic and the preset looked super broken. As the camera moved backward the visuals started to stabilize… the surface looked pixelated but running."

**Artifacts.** `features.csv`: `accumulatedAudioTime` 0 → 8.15 over ~78 s ⇒ descent phase (×0.12) reached only **0.98** — one-way, never wrapped, barely moved. `bassAttRel` mean −0.18 / max 0.33 (fold driver small and safe — not implicated). Repro renders: a phase 0.08 vs 0.90 sweep (`FD_PHASES` env on `test_descentContactSheet`) shows features **shrinking** as phase advances.

**Root causes.**
1. **Direction inverted** (`sdf-geometry`). `q = (p + c) * zoom` with zoom increasing maps every feature to `p = q₀/zoom − c`, collapsing them toward a vanishing point ⇒ a recede. **Fixed:** `q = (p + c) / zoom`, distance `DE(q) * zoom`. Verified by the same sweep now showing features grow.
2. **The scale descent targeted the fractal's ORIGIN — which is smooth.** A Mandelbox core has no detail at small scales, so falling inward runs out of structure and presses against a featureless wall (the inverted direction accidentally masked this: zooming *out* revealed more folds). **Partially fixed:** `FD_ZOOM_TARGET` moved to a boundary point where folded detail persists at every scale (same reason a Mandelbrot zoom targets the boundary, never the cardioid middle). Composition improved from "smooth wall" to "canyon between ornate walls."
3. **Severe motion aliasing / moiré — ADDRESSED at MFX.1 (2026-07-23), live re-test pending.** MetalFX Temporal is now wired as an opt-in ray-march capability (`upscale: "metalfx_temporal"` + `render_scale`). Presets supply `scenePrevPosition`; for FD's analytic scale descent the previous-frame position is a closed form, so motion vectors are EXACT. Measured A/B on the identical motion path: **24.6 % less temporal high-frequency energy, and FASTER — p50 5.2 ms vs 6.6 ms full-res** (rendering at 0.65 and reconstructing saves more than the scaler costs). **Cost contract learned:** the scaler runs ~8.5 ms at 1080p if used 1:1, which alone blows the budget — it only pays for itself when it upscales. Residual shimmer remains (24.6 % is a real but partial reduction); whether it is now acceptable is Matt's live call. Original text follows — Full-res Mandelbox detail plus view-dependent thin-film iridescence alias badly under the fall. Mitigations applied (distance detail roll-off, thin-film confined to near ridges + roughened) reduce but do not eliminate it. **This is an infrastructure gap:** §A8 assumed MetalFX Temporal upscale for exactly this anti-aliasing and it is **not wired in this engine** (flagged at FD.1 pre-flight, proceeded anyway). Without temporal AA or supersampling a ray-marched fractal at this detail density will shimmer. Note the whole-frame `motion_gate.sh` spike metric does **not** catch high-frequency shimmer — it passed 0 spikes while the live render shimmered.

**Also open:** the descent rate was far too slow (0.12 → 0.45); the canyon framing shows a bright grey sky-gap where rays miss the bounded object.

**Verification criteria.** Automated: golden + route-coverage + perf ≤ 7 ms. Manual (required): Matt live M7 on a loud track — direction reads as falling IN, and a judgement on whether residual shimmer is acceptable or blocks cert.

**Decision needed (Matt):** whether to fund an anti-aliasing capability (wire MetalFX Temporal — a scale-zoom *can* supply motion vectors — or supersample within budget), accept a softer/lower-detail look, or stop the preset.

---

### BUG-070 — Failed tap reinstall leaves untruthful capture state; engine detectors starved (2026-07-12)

**P2 · audio.capture / resource-management.** From the 2026-07-11 ultra review (concurrency + audio dimensions); root cause verified in code at PUB.6.

**Expected:** after a failed device-change reinstall, the capture object's state reflects reality (not capturing), engine-side health classification can still fire, and a recovery restart can proceed.
**Actual (pre-fix):** `performReinstall`'s catch did nothing — its comment claimed "the create steps already tore down + stopped the monitor on failure," which was false on both counts. End state: `_isCapturing=true`, monitor running, zero IO callbacks → `SignalHealthMonitor.evaluate` (sample-driven, `ingest` window boundaries) never runs so `deadTap` never confirms; the router's `.silent` recovery is likewise callback-starved; `startCapture` recovery blocked by the alreadyCapturing guard. Only the app-layer Mode-B stall card (1 Hz poll on the tap frame count, ~10 s dwell) surfaced it — detection existed, engine truth and recovery did not.
**Fix (landed, PUB.6):** catch clears `_isCapturing` (unblocks stopCapture+startCapture recovery), monitor deliberately left running as a diagnostic beacon (later fires land in the SKIP branch and breadcrumb), comment corrected.
**Verification criteria:** automated — engine builds; audio suites green (a real failed reinstall cannot be staged headless: Core Audio create-step failures need a live device transition). Manual (pending): a live device-swap session confirming normal reinstalls still work (the G1 12/12 behaviour), and — if a reinstall failure can be provoked — the stall card appears AND a subsequent session restart recovers cleanly.
**Residual (documented, deliberately open):** the 3-queue lifecycle interleave (device-change reinstall vs silence-recovery reinstall vs user stop) is real but static-only evidence; the per-step breadcrumbs + install-generation probes are the instrumentation. Serialize ONLY on a reproduced interleave artifact — restructuring the G1-live-validated path on theory is the BUG-063 class.

---

### BUG-065 — Live BeatGrid phase drifts off the audible beat over a track (mid-track drift convergence) (2026-06-29)

P3, `dsp.beat`. (Renumbered from BUG-064 on the GLAZE.8→main merge — BUG-064 was already assigned to the Lumen freeze; this beat-sync bug forked the number on `claude/nice-rubin-9c10c7`.)

**Expected:** the live beat phase stays within the ~60 ms perceptual window across a whole track, so frame-locked beat-driven motion (e.g. Glaze's GLAZE.7 downbeat push) reads tight start-to-finish.

**Actual:** the cached grid has the right BPM, but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it — drift grows ~11 ms (track start) → 50–70 ms (mid/late-track), with 28 % of frames exceeding ~60 ms. Evidence: session `2026-06-29T12-43-51Z` (Cherub Rock, 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; `lock_state=2` only 67 %-within-60 ms). NOT a functional break (phase is approximately right); it caps how *tight* beat-locked presets can feel (the live example: GLAZE.7 reads connected but loosens as the track plays).

**Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is mid-track drift *convergence* — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session.


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
- ✅ **RESOLVED (CLEAN.4.4, 2026-06-17)** — three renderer over-allocation / cache-key items from audit T7 (the `2026-06-13` audit's restatement of these P3s). (1) **PSO cache key** (`ShaderLibrary` cached by `name` alone, ignoring `pixelFormat`/`supportICB`): **finding = LATENT, not a live bug** — every production caller uses a **unique** name compiled once at init, preset multi-pass PSOs bypass the cache (`PresetLoader` → `device.makeRenderPipelineState`), and `supportICB: true` is test-only, so nothing currently collides; keyed correctly anyway by `PipelineKey(name, pixelFormat.rawValue, supportICB)` so a future name-reuse can't return the wrong-format PSO. (2) **wasted particle-mode warp pass** + (3) **unconditional feedback textures**: both gated to surface-mode feedback presets via `RenderPipeline.activePresetSamplesFeedback` — non-feedback + particle-mode presets allocate zero ping-pong (freed on `setFeedbackParams(nil)`), and particle mode skips the warp. Output-preserving (PresetRegression goldens byte-identical). Gates: `ShaderLibraryTests` +2, `DrawableResizeRegressionTests` +3. `RELEASE_NOTES_DEV.md [dev-2026-06-17-215601]`. (T7's remaining items — sceneTexture aliasing, resize stale-size, ray-march /height NaN, DynamicTextOverlay race — stay open under CLEAN.4.3/4.5.)
- ✅ **RESOLVED (CLEAN.2.3.4, 2026-06-14)** — localization gate only scanned `PhospheneApp/Views/`. `check_user_strings.sh` ROOTS widened to `PhospheneApp/ViewModels` + `ContentView.swift`, pattern extended with a connection-state `.error("…")` arm (`logger.error` excluded); the bypassing copy (Spotify/AppleMusic error strings, ConnectorType tiles, ReadyViewModel duration/source, ContentView fallback, PreparationProgressView subtitle, PlanPreviewTransitionView labels) externalized to `Localizable.strings`. Gate header documents its honest scope limit (literal-prefix matcher — lowercase/interpolated fragments still rely on review). Commit `46d836b`.

P3 categories indexed in the audit doc: ~25 latent bugs (incl. OAuth refresh double-spend + form-encoding gaps [Resolved CLEAN.2.2, see above], PSO cache key, mv_warp buffer(5) omission, PostProcessChain texture aliasing, malformed-sidecar swallowing, Arachne listening-pose FA #57-gate, >2-channel LF corruption, ~94 Hz vs 60 fps chroma hysteresis), ~11 perf items (autocorrelation 2×/frame, drums FFT 2×/frame, mono STFT 2×/track, serial prep pipeline, wasted particle-mode warp pass, unconditional feedback textures), dead code, and 6 in-code doc-drift items.


---

### BUG-060 — One-off app hang: the render loop died on a `preset → Gossamer` switch; force-quit required; not reproduced (2026-06-18)

**Severity:** P3 (a full app hang requiring force-quit is P1-*impact*, but it was seen once and did not reproduce — Gossamer ran 3× clean the next session; filed as **monitored**, like BUG-058, pending a recurrence with a captured stack).
**Domain tag:** renderer / app.hang (suspected preset-apply or first-frame GPU hang on Gossamer).
**Status:** **LIKELY RESOLVED by NACRE.2b's BUG-061 fix (2026-06-25) — pending non-recurrence.** BUG-061 confirmed the suspected **preset-apply race**: `applyPreset` clears `activePasses` to `[]` then republishes them at its end, while `draw(in:)` runs concurrently on the display-link thread; a frame in that window falls to `drawDirect` with the new preset's direct pipeline. Nacre's `.rgba16Float` pipeline made it a deterministic crash and exposed the mechanism; for an 8-bit preset like Gossamer it's the benign/intermittent stray frame seen here. The `willRenderActiveFrame` guard (skip frames while `activePasses` is empty) removes the stray `drawDirect` for ALL presets. Keep monitored until a few clean Gossamer-switch sessions confirm non-recurrence (the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains).
**Introduced:** Unknown (the apply-race predates NACRE.2b).
**Resolved:** Likely 2026-06-25 (NACRE.2b empty-passes guard); confirm by non-recurrence.

**Expected:** switching presets (incl. Gossamer) never hangs the app.

**Actual (session `2026-06-17T22-10-50Z`):** the render loop was healthy — 60 fps, `frame_gpu_ms` 0.13–1.5 ms, no `deltaTime` gap — through the **last recorded frame (9459) at `22:14:01Z`**, which is **one second after `session.log`'s last event, `preset → Gossamer` at `22:14:00Z`**. `features.csv` then stops while the stem-separation / orchestrator threads keep logging for ~30 s more → a **render-path hang** (main or GPU), not an analysis stall (cf. BUG-043, a freeze-then-lurch) and not a tap freeze (cf. BUG-058). Video was OFF (BUG-050), so the recorder's video path is excluded. Matt force-quit from Xcode **without hitting Pause**, so no thread stacks were captured.

**Non-reproduction (session `2026-06-18T13-57-23Z`):** Gossamer was applied **3×** (13:58:35, 14:00:13, 14:00:36) and rendered clean; the session ended with a normal `SessionRecorder finished` shutdown. So the hang is rare/intermittent, not a deterministic Gossamer defect.

**Reproduction steps:** unknown trigger. Lead: a `preset → Gossamer` switch under live load (continuous stem separation running) — possibly transient GPU contention between the stem-separation MPSGraph and Gossamer's first-frame render, or a preset-apply race.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-17T22-10-50Z/` (features.csv ends at frame 9459 / `22:14:01Z`; session.log last line `preset → Gossamer`); clean counter-example `2026-06-18T13-57-23Z`.

**Suspected failure class:** `concurrency` or `render-state` (a hang, not a crash).

**Verification criteria (when diagnosable):**
- [ ] **On the next recurrence: hit Pause (⏸) in Xcode BEFORE force-quitting**, and capture the Debug-Navigator thread stacks (main thread + any thread in Metal/MPSGraph) — the one artifact that locates a hang. Add a `Debug → Capture GPU Frame` if a GPU hang is suspected.
- [ ] Root cause identified from a captured stack; regression guard added.

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

### BUG-051 — m3u playlist entries resolve to arbitrary paths with no extension/traversal guard (2026-06-15)

**Severity:** P3 (defense-in-depth — the consequence is bounded by the no-egress local-file path; realized harm in the current single-user/no-telemetry architecture is ≈ nil). Filed by CLEAN.2.4 (GAP-10 threat model, `docs/SECURITY_POSTURE.md` §6).
**Domain tag:** local-file / security
**Status:** Open — filed 2026-06-15, not fixed (CLEAN.2.4 is doc-only). Fix is its own small increment.
**Resolved:** —

**Expected:** a `.m3u`/`.m3u8` entry resolves only to a readable **audio** file under an expected root.
**Actual:** `M3UParser.resolveURL` (`PhospheneEngine/Sources/Session/M3UParser.swift:138-147`) resolves `file://`, absolute (`/…`), and relative entries with **no extension filter and no path-traversal guard** — a hostile playlist can name `/Users/you/.ssh/id_rsa` or `../../etc/passwd`. The entry is readability-checked (`isReadableFile`) and handed to AVFoundation, which **fails to decode** a non-audio file; the path is never read back to the attacker, and the local-file path has **no network egress**, so nothing escapes. Bounded, hence P3.
**Reproduction steps:** open a `.m3u` whose body lists a readable non-audio absolute path; observe the entry is resolved + readability-checked before the audio decoder rejects it (no allow-list short-circuits it first).
**Session artifacts:** n/a (static input-validation finding; verified by code read, see `SECURITY_POSTURE.md` §6 + §verification).
**Suspected failure class:** `api-contract` (the parser's resolve contract admits non-audio / out-of-tree paths).
**Verification criteria (for the eventual fix):**
- [ ] Automated: a `.m3u` listing a non-audio extension and a `../`-traversal path resolves to **zero** entries (or throws `noEntriesResolved`); valid audio entries still resolve (extend `M3UParserTests`).
- [ ] Manual: opening a normal `.m3u` of `.m4a/.mp3/.flac` is unaffected.


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

### BUG-041 — FFO aurora flashes at track start: the drums-stem deviation driver overswings 1.2–3.3× during the per-track analyzer cold start (2026-06-10)

**Severity:** P2 (visible flashing in the first ~10 s of affected tracks on FFO; Matt flagged it on So What, There, There, and Lotus Flower in session `2026-06-10T14-55-32Z`). Same cold-start-deviation family as BUG-027/AGC2.4.1 (fixed for the FeatureVector band devs) — this is the STEM-side twin reaching the GPU through the aurora.
**Domain tag:** `dsp.stem` (deviation cold start) + `preset.fidelity` (FFO aurora intensity).
**Status:** **Fix landed 2026-06-10 (FBS.S2.2), then EXTENDED same day (FBS.S3.2)** after Matt's next read showed flashing at MID-TRACK timestamps too (session `17-50-56Z`: every flagged time coincides with an all-stem deviation burst, 3–30× track median — So What reached dev = 35). The track-start warmup was correct but insufficient in scope: the driver's response itself is now flash-proof — soft-knee input (`dev/(1+0.6·dev)`: musical values pass, bursts cap — 35 → 1.64) + asymmetric response (rise τ 0.45 s = a bloom, fall τ 1.2 s = afterimage), warmup gate retained. Gates: max per-frame output step ≤ 0.08 across the full So What series incl. the 35× burst; legacy-driver red arm proves the fixtures carry the defect. **Awaiting Matt's M7** *(PUB.3 flag, 2026-07-11: candidate close-as-stale — gates green a month; the FBS Stage-2 live validation 2026-06-11 is plausible covering evidence, but closing needs Matt's one-line confirm. The dev=35 upstream anomaly stays a separate open note either way.)* *(Note: dev = 35 is itself anomalous — deviation primitives normally max ~3.4; a StemAnalyzer EMA divide-by-tiny is suspected upstream and worth its own look. The soft knee defends the aurora regardless.)*
**Introduced:** structural — `StemAnalyzer` resets per track; its per-stem deviation EMA re-seeds and `drumsEnergyDev` overswings during convergence. The aurora consumes it through the D-127 smoother (`auroraDrumsSmoothed`, τ ≈ 150 ms) — fast enough to pass multi-Hz cold-start swings as visible intensity flashes. The Stage-1 spike-driver replacement removed the OTHER flicker source (`f.bass` jitter into spike geometry), making this one prominent.
**Resolved:** —

**Expected:** the aurora arrives smoothly when a track starts.

**Actual (session `2026-06-10T14-55-32Z`, first 10 s of each track, 150 ms-smoothed driver):** flagged tracks — Lotus Flower smoothed peak **2.35**, So What **1.23**, There, There **1.37** (smoothed jitter 0.45–0.91/s); unflagged — Love Rehab peak 0.23, jitter 0.02/s. The flashing maps exactly onto the measured overswing. Steady-state (10–20 s) values are far lower. The pulse, spike strength, and the BUG-038-smoothed light multiplier are all calm in the same windows (measured — they are excluded as causes).

**Reproduction steps:** play the 6-track streaming playlist on FFO; observe the aurora in the first ~10 s of So What / There, There / Lotus Flower; compare `stems.csv` `drumsEnergyDev` early-window values against the 10–20 s window.

**Session artifacts:** `~/Documents/phosphene_sessions/2026-06-10T14-55-32Z/` (`stems.csv` drums columns; the per-track table above).

**Suspected failure class:** `calibration` (deviation cold-start overswing, BUG-027 class) — consumed un-warmed by a brightness layer.

**Fix (FBS.S2.2):** a per-track quadratic warmup gate on the aurora's drums driver (`RenderPipeline.auroraDriverStep` — D-127 smoother × `warmup²`, 0 → 1 over 10 s, reset by the existing `resetAccumulatedAudioTime()` track-change hook). The gate is smallest exactly where the overswing peaks (2–6 s; Lotus's 2.35 spike lands on gate ≈ 0.16) and is ~1 once the analyzer has converged; steady state is byte-identical after 10 s. Measured on the session fixtures: early peaks 2.35/1.37/1.23 → **0.65/0.50/1.10**. Linear was tried and measured insufficient (Lotus still reached 1.23).

**Verification criteria:**
- [x] Automated (real-session replay through the production arithmetic, `AuroraTrackStartWarmupTests`): early-window (0–10 s) driver peak ≤ max(1.0, steady-state peak) on all three flagged tracks, red-arm reproduction of the flash on the two unambiguous ones, steady state byte-identical. *(Criterion AMENDED from the original "≤ 1.5× steady": Lotus's drums settle to ~0 steady — a steady-relative bound is unmeetable; So What's steady runs hot (1.64) so its early window is not anomalous. So What's perceived flashing is partly general drums-dev jitter on sparse jazz — a separate aurora-character question, noted, not chased here.)*
- [ ] Manual: Matt confirms the aurora arrives without flashing on So What / There, There / Lotus Flower track starts.

**Manual validation required:** Yes — felt visual artifact.

**Related:** BUG-027/AGC2.4.1 (the band-dev cold-start warmup — the fix pattern to mirror on the stem side or at the aurora's consumption point), BUG-029/AGC3 (the `f.bass` cold-start spike — same family, different path), D-127 (the aurora smoother), FBS (this became visible once the spike driver stopped flickering).


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

### BUG-068 — LF multi-file plan order diverges from the URL queue after a mid-queue preparation failure (2026-07-11)

**P1 · local-file / pipeline-wiring · ✅ RESOLVED 2026-07-11 (PUB.2, `22ded35` + `1ae6900`).** Fix: `SessionPreparationResult.orderedTracks` built by the `PrepOutcomes` accumulator (walk-order interleave of prepared identities and failure placeholders); both plan-assembly sites consume it. All three verification criteria met: regression `startLocalFiles_midQueueFailure_preservesURLQueueOrder` + no-failure control (existing ordering test), 53 session tests green, streaming site shares the ordered source. Found by the 2026-07-11 pre-publication ultra review; adversarially verified against the code. Diagnose+fix collapsed into one increment per Matt's Phase-1 go (the root cause is statically provable — no instrumentation step needed).

**Expected:** with a multi-file queue `[A, B, C]` where B fails preparation, `SessionPlan.tracks[i]` corresponds to `urls[i]` for every i — track 2's slot carries B's placeholder identity, so B's audio plays against B's (partial) identity and C's audio against C's identity/beat grid.
**Actual:** `SessionPreparer._runLocalFilePreparation` appends successes and failures to two separate arrays; `SessionManager.startLocalFiles` (`SessionManager.swift:472`) builds the plan as `cachedTracks + failedTracks` → plan `[A, C, B]` against playback order `[A, B, C]`. From the failure onward every track index pairs the wrong audio with identity, cached beat grid, stems, and chrome. The code comment "Order matches the original URL queue because the preparer walks in order" is false for any mid-queue failure. The streaming path (`SessionManager.swift:308`) has the same concatenation; consequence there is bounded (track matching is identity-based; only the planner's playlist-order arc degrades).
**Reproduction:** unit-level — 3-URL queue, delegate fails url[1] (see verification criteria). Live — any LF multi-file session where a non-final file has no preparable stems.
**Session artifacts:** none required — the defect is statically provable from the two cited sites; `WIRING: SessionPreparer.prepareLocalFile #n` log lines confirm walk order in any historical multi-file session.
**Suspected failure class:** `api-contract` (result type discards the input ordering the consumer depends on).
**Verification criteria (written before the fix):** (1) new regression test: 3-file queue with the middle file failing → plan order `[A, B(placeholder), C]`, and a control with no failure → order unchanged; (2) existing LF/session suites green; (3) streaming plan assembly uses the same order-preserving source. Manual: not required for the ordering fix itself (no musical-feel/visual change); any normal multi-file LF session doubles as a no-regression walk.


---

### BUG-069 — VisualizerEngine cross-thread analysis fields unguarded (`currentFamilySeries` Array race) (2026-07-11)

**P1 · app.engine / concurrency · ✅ RESOLVED 2026-07-11 (PUB.2, `3d89692`).** Fix: `analysisStateLock` accessors for the four VisualizerEngine fields (compound updates documented benign); `trackMetadataLock` for the MIRPipeline pair. Criteria met: all five fields lock-routed with guards documented, full engine+app suites green, TSan MIRPipeline spot-run clean. Found by the 2026-07-11 pre-publication ultra review; adversarially verified. Diagnose+fix collapsed into one increment per Matt's Phase-1 go (statically provable data race).

**Expected:** every field crossing MainActor ↔ `analysisQueue` is lock-guarded (the `tapSampleRate` pattern, `VisualizerEngine.swift:395–420`) or confined to one queue.
**Actual:** `currentFamilySeries: [InstrumentFamilyActivity]` (`VisualizerEngine.swift:452`) is reassigned on MainActor in `resetStemPipeline` (`+Stems.swift:482,517` — every track change) while `processAnalysisFrame` samples it at ~94 Hz on the serial analysis queue (`+Audio.swift:234`). A Swift Array reassignment concurrent with a read is memory-unsafe (CoW storage can be deallocated mid-read), not merely stale — a rare-crash class. Sibling unguarded crossings in the same class: `liveBeatAnalysisAttempts`, `runtimeRecalibrationDone` (MainActor reset in `resetStemPipeline` vs analysisQueue read/increment in `runLiveBeatAnalysisIfNeeded` / recalibration), `pendingDispatchStartTime` (stemQueue completion vs analysis-path reads). Related engine-side twin: `MIRPipeline.currentTrackName`/`currentArtistName` (`MIRPipeline.swift:97–98`) written from the app metadata callback, read on the analysis queue on the recording path — unguarded String race, same class.
**Reproduction:** timing-dependent; provable statically. TSan on a track-change-heavy session is the runtime discriminator (`Scripts/tsan_stress.sh`).
**Session artifacts:** none — no crash on record attributable yet (the point is to fix it before contributors' machines find it).
**Suspected failure class:** `concurrency`.
**Verification criteria (written before the fix):** (1) all five fields route through a lock (accessor pattern) or are queue-confined, with the guard documented on each; (2) full engine + app suites green; (3) TSan spot-run of the stem/analysis suites shows no new races on these fields. Manual: none (no behavioural change intended); benign bounded lost-update on `liveBeatAnalysisAttempts` reset-vs-increment is documented at the accessor.


---

### BUG-067 — Ricercar FL.5 fails the WCAG overlay-contrast gate on main (2026-07-09)

**P3 · preset.fidelity / regression · ✅ RESOLVED 2026-07-09 (Ricercar-rework merge).** Surfaced by the QG.1 pre-flight full battery; resolved by merging the FL.10 dark-ground flow-field.

**Expected:** `PresetContrastCertificationTests` requires white overlay text to clear WCAG 4.5:1 contrast over any preset frame + overlay backdrop.
**Actual (before):** Ricercar failed deterministically on all three fixtures — contrast **3.52 < 4.5** (`PresetContrastCertificationTests.swift:59/78/97`). Reproduced in isolation, not environmental, not flaky.
**Root cause:** main's Ricercar was the FL.5 fluid-dye state (a **light** warm ground → low contrast under white text), superseded by the `claude/ricercar-rework` branch (FL.10 glowing particle flow-field on a **dark** ground, M7-passed 2026-07-08 — see the ricercar-and-instrument-capture memory).
**Resolution:** merged `claude/ricercar-rework` to main (2026-07-09, merge `694bbc0`). The FL.5 fluid geometry (`RicercarFluid*`) was replaced by the FL.10 flow-field (`RicercarFlow*`) on a deep/dark ground; `PresetContrastCertificationTests` now passes for Ricercar in isolation (0.12 s). Ricercar remains `certified: false` (FL.10 M7-passed but not yet formally certified); a route-coverage manifest backfill is a spun-off follow-up.
**Failure class:** pre-existing regression on a superseded preset state, cleared by the intended replacement.


---

### QG.1.1 — Ricercar route-coverage: 4 family-capture reads (armed + green at QG.1.3)

**✅ RESOLVED 2026-07-09 (QG.1.3).** The 4 family-capture reads are armed and green. `FixtureSessionCaptureGenerator` now runs `InstrumentFamilyAnalyzer.analyzeFamilyActivity` over each clip and merges the per-frame `*Activity`/`*ActivityDev` into the stems rows (sampled by playback position, mirroring the live `setInstrumentFamilyActivity`); the 4 `*ActivityDev` routes are declared in `Ricercar.json`; the 3 route-coverage fixtures were regenerated (52-col stems.csv). `RouteCoverageTests`: **156 routes / 14 presets, 0 red**; `AudioRouteSchemaTests` green. The minimal variant held — PANN prob jitter clears the 1e-5 `continuous` floor on all 3 non-orchestral clips (audited per-column before declaring: strongest is `so_what`'s trumpet-led `brassActivityDev`, max 0.497; weakest is `love_rehab`'s `woodwindsActivityDev`, stddev 1.5e-4, still ~15× the floor). No orchestral fixture needed.

**NOTE · coverage-gap history (documented, not a defect).** The BUG-067 follow-up backfilled Ricercar's `audio_routes` manifest. Ricercar (FL.13 flow-field) reads **11** audio primitives; **7 were declared** at QG.1.2 (`flow_vigour` ← `bass/mid/trebDev`; `{strings,brass,woodwinds,percussion}_ribbon` ← the band-stem `{vocals,bass,other,drums}EnergyDev` half of each per-colour hybrid). The other **4 reads** — the family-capture half of each colour's hybrid — were deferred as not-yet-armed (QG1_REPLAY_AUDIT §not-yet-armed convention) and are armed at QG.1.3 (see RESOLVED above):

- The family-capture half of each colour's `max(band-stem dev, family-capture dev)` hybrid — `stringsActivityDev`, `brassActivityDev`, `woodwindsActivityDev`, `percussionActivityDev`. In the checked-in fixtures these columns are exactly 0 (stddev 0.00), so declaring them would red the un-gated battery. Not a dead route: each ribbon's visual behaviour is already gate-covered via its band-stem primitive.

**Root cause of the 0 (verified 2026-07-09):** the offline `FixtureSessionCaptureGenerator` runs only `StemAnalyzer.analyze` (no PANN). Family-capture is **Layer-5a preview-derived** — the `InstrumentFamilyAnalyzer` (PANNs MobileNetV1) sweep, injected live via `RenderPipeline.setInstrumentFamilyActivity` (IFC.4/D-177) — which the generator never runs, so `*Activity` is written as structural 0 **regardless of clip**. This is the same offline-can't-populate class as the existing QG.1.1 boundary, not merely a genre-of-fixture gap.

**Arm trigger:** extend `FixtureSessionCaptureGenerator` to run `InstrumentFamilyAnalyzer.analyzeFamilyActivity` offline (headless samples-in → activity-out, the path SessionPreparer uses) and merge per-frame `*Activity`/`*ActivityDev` into the stems rows — that alone makes the columns non-constant (PANN prob jitter) → the 4 routes clear the just-above-noise `continuous` floor. An orchestral `route_coverage` fixture then gives them real amplitude. Then declare the 4. **Do NOT tune the floor to pass them** (QG.1).

**FL.14 sequencing:** FL.14 (per-family articulation, on `claude/ricercar-fl14-prompt-7de805`, not yet on main) adds 4 more reads — `{vocals,bass,other,drums}AttackRatio` → `*_articulation` line-character routes. `AttackRatio` is alive on all genres, so those 4 **are** armable and should be declared in the FL.14 integration commit (manifest → 11 declared once FL.14 lands). Certifying Ricercar (`FidelityRubricTests.certifiedPresetsDeclareAudioRoutes`) requires a non-empty manifest — already satisfied.


---

### BUG-066 — MoodClassifier flux input ran 16× hot on the offline path; saturated on every track (2026-07-08)

**P2 · ml.mood / dsp.mir · ✅ RESOLVED 2026-07-08 (MOOD-FLUX.2, `1d61830`).** Matt signed off on the objective `--mood-ab` before/after evidence (no live M7 — an eyeball made no sense for a diffuse scoring change). Full record: [`docs/diagnostics/BUG-066-diagnosis.md`](../diagnostics/BUG-066-diagnosis.md).

**Expected:** the MoodClassifier z-scores its 10 inputs against the scaler fit on the **live** pipeline's features (`d586e57` retrained on live-annotated tracks); `spectralFlux` (mean 0.25, std 0.20) should land within a few sigma.
**Actual:** CENSUS.3 (n=993) measured the **offline** flux input mean at **8.06** — z ≈ **+38**; saturated on essentially every track. Band energies and centroid match the scaler within ~20 %.
**Root cause (corrected — NOT a train-vs-inference mismatch):** the model is correctly trained on live features (the live training CSV `~/phosphene_features_annotated.csv` flux mean 0.2516 = the scaler). The offline `SessionPreparer.analyzeMIR.computeFFTMagnitudes` **reimplemented the FFT magnitude formula** differently from the live `Audio/FFTProcessor`: `sqrt(power/fftSize)` = |FFT|/32 vs live `|FFT|×2/fftSize` = |FFT|/512 — a uniform **16×**. Same hop (1024). Flux is fed **raw** into the z-score ([MIRPipeline.swift:66](../../PhospheneEngine/Sources/DSP/MIRPipeline.swift)); bands are AGC-normalized and centroid/chroma are ratios → scale-invariant → they matched. Flux is the only exposed feature (the discriminator; pre/post ratio exactly 16.000, σ=0).
**Impact:** `TrackProfile.mood` (set by `analyzeMIR`) is 30 % of `DefaultPresetScorer` → offline preset selection ran on 9 effective features. The **live** mood path was always correct; no live regression.
**Failure class:** regression / pipeline-wiring (offline path drifted from the live FFT formula).
**Fix (MOOD-FLUX.2):** align the offline formula to live — `vDSP_zvabs` + `×2/fftSize` (in `SessionPreparer+Analysis.swift` + the `CorpusCensusRunner` mirror). **Validated:** flux z **+38 → +1.43**, uniform 16× correction, 103 mood/MIR/session-prep/spectral tests green incl. `MoodClassifierGolden` (classifier untouched — this is a feature-extraction fix); blast radius benign (mir_bpm 0/40 changed; key 6/40 empty→resolved, harmless; centroid ratio-invariant).
**Sign-off (2026-07-08):** the live M7 was retired as unfit for a diffuse scoring change; replaced by the objective `CorpusCensusRunner --mood-ab` before/after (80-track sample) — before, saturated flux railed arousal high for every track → non-discriminative "happy" (Beethoven adagios read euphoric); after, arousal spans [−0.87,+0.81], spread ~doubled, **32 % of tracks flip mood quadrant** in the correct direction (calm tracks read calm). Matt: "bug is resolved."


---

