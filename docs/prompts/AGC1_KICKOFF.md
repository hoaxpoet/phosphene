# AGC.1 Kickoff — Fix BUG-025 (AGC EMA poisoning by cold-start transient)

> **⚠️ SHELVED 2026-06-02 — DO NOT IMPLEMENT. Read this banner before anything below.**
> During AGC.1 step 1 (confirm-the-diagnosis-in-code), an LF↔Spotify A/B comparison disproved the premise this kickoff is built on. The BUG-025 cold-start transient is **real but one-time and ~2 s** (first onset only; track changes re-init cleanly), and it does **NOT** cause the session-wide deviation-primitive starvation this kickoff blames it for. That starvation is **structural** (fixed-0.5 deviation pivot vs total-energy AGC normalisation) and is **identical on LF** (`bassDev` fires 2.9 % LF vs 1.5 % Spotify). Implementing Approach A here would fix only the 2 s flash — not worth a cross-cutting AGC change touching 8 presets.
> - The corrected diagnosis lives in `docs/QUALITY/KNOWN_ISSUES.md` BUG-025 (downgraded P2→P3) + the new **BUG-027** (the real structural issue).
> - The "muted on Spotify" symptom that motivated all this was addressed at preset scope by the 2026-06-02 Dragon Bloom re-tune (route to signals alive on both paths).
> - If AGC work is ever revived, start from BUG-027's fix-scope options (per-band EMA / recentered pivot / document-and-steer), NOT from this kickoff's transient-rejection approach.
>
> The text below is preserved as the (now-invalidated) scoping record only.

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this is

[BUG-025](../QUALITY/KNOWN_ISSUES.md#bug-025) was filed 2026-06-01 during the Dragon Bloom Spike 1 debug session and confirmed across two independent Spotify sessions (2026-06-01T22-57-10Z at 50 % Spotify volume, 2026-06-02T01-12-51Z at 100 % Spotify volume). Severity P2, domain `dsp.beat` (calibration). The headline:

> The single global AGC EMA in `BandEnergyProcessor` absorbs extreme amplitude transients (bass values 50× steady-state) in the first ~10–15 frames after `signal quality → active`. The EMA running-average stays inflated for the rest of the session, holding `bassRel` mean at ≈ −0.48 and firing `bassDev` on only 1.8 % of frames instead of the expected 30–50 %. All eight production presets that read deviation primitives (`bassDev`, `midDev`, `trebDev`, `bass_att_rel`, `mid_att_rel`, `treb_att_rel`) per D-026 are visibly less reactive on Spotify than on LF — Layer-2 of the Audio Data Hierarchy is structurally dead on the tap path.

This increment is **the fix**. Diagnosis is complete (two reference sessions, identical transient shape and magnitude regardless of input level, AGC code mapped). The work is implementation + regression test + validation.

## Why this is next

1. **Blast radius.** Eight production presets read deviation primitives per D-026: Arachne, Aurora Veil, Dragon Bloom, Ferrofluid Ocean, Gossamer, Kinetic Sculpture, Spectral Cartograph, Volumetric Lithograph. The D-026 routing — *"Drive primary motion from deviation primitives, not absolute thresholds"* — is the canonical Layer-2 contract for all eight. With BUG-025 active, the bottom 50 % of dynamic range that those primitives are supposed to encode is unreachable on every Spotify session. Every preset author who tunes for "Spotify feels muted compared to LF" is paying for this bug.

2. **Surfaced and isolated.** Matt's 2026-06-02 100 %-Spotify session proved BUG-025 reproduces independently of BUG-026 (the in-app volume slider issue). At healthy signal level (Peak −4.8 dB, RMS −18.4 dB), the cold-start transient is unchanged: bass = 3.3 → 11.58 → 7.33 across frames 310–321, identical shape and magnitude to the previous session's 11.0 peak at frame 262. **The bug is in the AGC, not downstream of any input-level fix.**

3. **Dragon Bloom Spike 1 is held on this.** The Spike 1 gate (§6 of the Dragon Bloom plan — Matt-perceptual "does the bloom dance to the music") cannot pass on Spotify until the deviation primitives Dragon Bloom reads (`bass_att_rel`, `bass_dev`, `mid_att_rel`) become functional on that path. The Spike 1 follow-up commit (`cffefe65`) addressed raw-waveform amplitude normalisation; this increment addresses the orthogonal deviation-primitive starvation.

4. **The fix is contained.** Single Swift file (`BandEnergyProcessor.swift`), one EMA-update site. Existing tests at `BandEnergyProcessorTests` and `RelDevTests` cover steady-state behaviour; new tests need to cover transient rejection only. No architectural changes; no GPU contract changes; no cross-cutting refactors.

## Read these first, before doing anything else

1. **[`docs/QUALITY/KNOWN_ISSUES.md` § BUG-025](../QUALITY/KNOWN_ISSUES.md)** — the full BUG entry with reproduction steps, evidence from both sessions, and verification criteria. **Read the confirmation-session block in full** — it isolates BUG-025 from BUG-026 and quantifies the AGC starvation in numbers.

2. **`PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift`** lines 120–211 — the AGC EMA implementation. Read the entire `processFrame(...)` body. Note especially:
   - **Lines 135 / 138:** `agcRateFast = 0.95` (warmup, frames 0–60) and `agcRateModerate = 0.992` (after). These are the two EMA poles.
   - **Line 205:** `let agcRate = frameCount < Self.warmupFastFrames ? Self.agcRateFast : Self.agcRateModerate` — the per-frame rate switch.
   - **Line 208:** `agcRunningAvg = max(totalRawEnergy, 1e-6)` — initialisation to the first sample's total energy on `frameCount == 0`.
   - **Line 211:** `let agcScale: Float = agcRunningAvg > 1e-10 ? 0.5 / agcRunningAvg : 0` — produces the normalised output. AGC target is 0.5.
   - **Line 204:** `let totalRawEnergy = raw6.reduce(0, +)` — the EMA tracks total energy across all 6 bands, not per-band. **Important**: the fix must not break this global-not-per-band design.

3. **`PhospheneEngine/Sources/DSP/BandEnergyProcessor.swift`** lines 251–260 — the `reset()` method. Currently called from `MIRPipeline.reset()` (line 396 of `MIRPipeline.swift`) on track change. Zeros `agcRunningAvg`, allowing the next session's transient to dominate the EMA on the next `processFrame` call.

4. **`PhospheneEngine/Sources/DSP/MIRPipeline.swift`** lines 333–342 — the deviation-primitive derivation. `bassRel = (bass − 0.5) × 2`; `bassDev = max(0, bassRel)`. **Important**: `bass` here is the AGC-normalised value (line 304: `bass: ctx.energy.bass` from `BandEnergyProcessor`). The fix changes how `bass` converges; deviation math is downstream and untouched.

5. **`PhospheneEngine/Sources/Audio/InputLevelMonitor.swift`** lines 38–96 + 248–296 — the signal-quality classifier. **It does NOT feed back to the AGC** (decoupled read-only diagnostic). The fix may optionally couple them (Approach C below); evaluate the tradeoff.

6. **CLAUDE.md §Audio Data Hierarchy** (the entire section, top of CLAUDE.md). This is the load-bearing design rule the BUG-025 fix is restoring on the tap path. Layer 1 (continuous energy) is the bedrock and is unaffected by BUG-025; Layer 2 (deviation primitives) is what BUG-025 starves; Layer 4 (beat onset) is unaffected.

7. **`docs/ARCHITECTURE.md` § Audio Analysis Tuning** → the "AGC behaviour" subsection (search for "Milkdrop-style average-tracking"). Documents the current two-speed warmup design. The fix updates this section.

8. **`docs/DECISIONS.md` D-026** — the deviation-primitives decision. The semantic contract `bassRel = (x − 0.5) × 2` is fixed by D-026; the fix must preserve it.

9. **Failed Approach #31** (CLAUDE.md) — *"Absolute thresholds on AGC-normalized energy"*. The fix MUST NOT break the existing rule. The fix changes how AGC converges; it does not change what shaders are allowed to do with AGC values downstream.

10. **Recorded reference sessions for validation:**
    - `~/Documents/phosphene_sessions/2026-06-01T22-57-10Z/` — Spotify 50 % volume + Apogee Duet 3. Cold-start transient at frame 262 (bass max 12.8).
    - `~/Documents/phosphene_sessions/2026-06-02T01-12-51Z/` — Spotify 100 % volume + Apogee Duet 3. Cold-start transient at frame 315 (bass max 11.6).
    Both contain `raw_tap.wav` for replay; both contain `features.csv` for golden-comparison.

## Hard rules for this fix

1. **Multi-increment protocol per CLAUDE.md.** This is P2 with all five Defect Handling Protocol steps documented. Trivial-P1 collapse is acceptable here per CLAUDE.md *"if a defect is trivial (< 5 lines of change, root cause obvious from existing artifacts, no architectural risk — requires Matt's explicit approval to collapse), the fix process uses separate increments"* — get Matt's explicit go/no-go on collapse before starting. If approved, fix + tests + docs land in one commit; if not approved, split into:
   - **AGC.1.diag** — one commit: add diagnostic-only test that captures the EMA's running-average trajectory across the reference session's first 600 frames. No production code change.
   - **AGC.1.fix** — one commit: the EMA update change + the regression test that asserts the EMA stays bounded during the transient. Manual M7 validation on LF + Spotify by Matt.

2. **Test BEFORE the fix.** Write the regression test that catches BUG-025 first; verify it fails against the current state; then implement the fix; then verify it passes.
   - Shape: extend `BandEnergyProcessorTests` with a new `coldStartTransientRejection` test. Inject the recorded transient (frames 310–321 of `2026-06-02T01-12-51Z`, or a synthesised copy: `bass = 3.3, 6.6, 10.9, 11.4, 10.97, 11.58, 10.45, 10.07, 9.09, 8.55, 7.92, 7.33`) followed by 120 steady-state frames at bass ≈ 0.5. Assert that after the transient window, the AGC EMA running average is within 30 % of the steady-state baseline (not 200 % as today).
   - **Mandatory companion test**: verify that the existing AGC convergence behaviour on a normal (no-transient) input is unchanged. Use the existing `agcConvergenceAtSteadyState` test in `BandEnergyProcessorTests` as the regression-locker.

3. **The fix MUST be a single contained change in `BandEnergyProcessor.swift`.** Do not refactor the AGC into per-band EMAs in this increment (out of scope; would invalidate all golden-hash regression baselines for 8 presets). Do not introduce per-preset overrides (out of scope; D-026 is the load-bearing contract). Do not couple the AGC to the InputLevelMonitor unless Matt has chosen Approach C below.

4. **Eight presets need M7 validation post-fix.** Do not declare the increment done without Matt confirming that on a multi-track Spotify session, EACH of {Arachne, Aurora Veil, Dragon Bloom, Ferrofluid Ocean, Gossamer, Kinetic Sculpture, Spectral Cartograph, Volumetric Lithograph} reads as appropriately reactive — and on a multi-track LF session, NONE has visibly regressed. The fix is upstream of every preset's shader; a small change here is a big change downstream.

5. **Do not silently change golden-hash regression baselines.** `PresetRegressionTests` use hashes that depend on the AGC's steady-state behaviour. If the fix changes steady-state behaviour even slightly (it shouldn't, but might via the AGC initialisation path), the hashes will shift. Do not regenerate hashes without Matt's explicit approval — surface the diff first.

6. **`docs/RELEASE_NOTES_DEV.md` + `docs/QUALITY/KNOWN_ISSUES.md` updates are mandatory** per the Defect Handling Protocol. The RELEASE_NOTES entry names the eight affected presets; the KNOWN_ISSUES entry's `Resolved` field gets the commit hash.

## Decision points for Matt (required before starting)

### Decision 1 — Fix approach

Five candidates with user-facing tradeoffs. **My recommendation is Approach A** — it's the most targeted, the lowest regression risk, and the diagnosis directly points at "extreme outliers poison EMA."

> **Important:** the cold-start transient (bass = 3.3 → 11.58 → 7.33 at frames 310–321) arrives AFTER the `signal quality → active` transition (around frame 300 in both sessions). So Approach C alone (gate AGC on `active`) does not solve the problem — the spike happens post-active. Any approach must address the transient itself, not just delay AGC startup.

#### Approach A — Transient rejection on the EMA update *(recommended)*

> *"When the incoming sample is more than N× the current running average during the first M frames after `active`, reject it from the EMA update (carry the previous average forward instead)."*

- **What the user sees:** Spotify reactivity matches LF reactivity by ~1 second into each session. No visible artifacts. Tracks that genuinely open at extreme volume (rare; needs to actually exceed 3× a building average) take ≤ 1 second longer to feel responsive than they do today.
- **Implementation:** ≈ 10 lines in the `processFrame` EMA update. New constants `agcTransientRejectMultiplier` (proposed 3.0) and `agcTransientRejectFrames` (proposed 60).
- **Tuning risk:** picking the threshold. 3× is conservative; 5× is permissive. The reference sessions show the transient as 50× steady-state, so any multiplier in [2, 10] catches it.
- **Regression risk:** very low — outside the transient window, the EMA is byte-identical to current behaviour.

#### Approach B — Warmup-from-clean (delayed initialisation)

> *"Don't initialise the AGC running average from the first sample. Hold it at a neutral value for the first 60 frames; then initialise to the median of those 60 frames."*

- **What the user sees:** the first ~1 second of every session has either no AGC normalisation (presets see raw band values directly) or AGC normalisation against a constant baseline. The bloom / brightness / reactivity feels different for the first second of every session, then snaps to the right behaviour.
- **Implementation:** ~ 25 lines (need to buffer the first 60 frames). New constant `agcInitMedianWindow` (proposed 60).
- **Regression risk:** medium — every session's first second changes shape. Eight presets to re-validate. Plausibly the right design (no transient → no problem), but the visible behavioural transition at frame 60 may be a worse user experience than today's slowly-recovering-from-transient.

#### Approach C — Couple AGC updates to `signal quality → active`

> *"Don't run the EMA update until `InputLevelMonitor.signalQuality` reaches `.green`."*

- **What the user sees:** identical to Approach B for the warmup-shape question. **DOES NOT SOLVE the transient on its own** because the transient arrives after `active` in both reference sessions. Useful only in combination with A or B.
- **Recommendation:** do not pursue alone. Could be a follow-up after A or B lands.

#### Approach D — Slower initial alpha

> *"Reduce `agcRateFast` from 0.95 to 0.99 (slower learning) during the first 60 frames."*

- **What the user sees:** the AGC takes 3–4 seconds to converge instead of 1 second. The transient still gets absorbed but less aggressively, so its tail is shorter.
- **Implementation:** 1-line constant change. Lowest risk.
- **Effectiveness:** **only partial** — the transient at 50× steady-state would still be partially absorbed and would still inflate the EMA, just by less. The reference session's `bassRel` mean of −0.48 might drop to perhaps −0.25, which is better but still has structurally-negative deviation primitives.

#### Approach E — Robust statistics (median EMA)

> *"Replace the mean EMA with a running-median estimator (transient-robust by construction)."*

- **What the user sees:** in principle the cleanest result. In practice, median-of-running-window is more complex to implement and the steady-state characteristics differ from the current mean EMA — every preset's steady-state perception shifts.
- **Implementation:** ~ 50 lines for a running-quantile data structure. New tests for the data structure itself.
- **Regression risk:** high — fundamentally changes the AGC's statistical profile. Eight preset golden hashes likely shift.
- **Recommendation:** out of scope for AGC.1; revisit if A doesn't hold up.

#### My recommendation, plain English

Approach A. It's the targeted answer to the diagnosed problem ("extreme outliers poison EMA"), it preserves all current AGC behaviour outside the transient window, it has the smallest regression footprint across the 8 affected presets, and its tuning constant has a wide acceptable range (any value in [2, 10] would catch the observed transient). If it doesn't pass M7 validation on the multi-preset sweep, fall back to Approach B; revisit E only if both A and B fail.

### Decision 2 — Manual M7 validation scope

Two options:

- **Full sweep:** Matt sits through a multi-track Spotify session per preset (8 presets × ≈ 60 s each ≈ 8 minutes of focused viewing), and a parallel multi-track LF session check (another 8 minutes). Total: ≈ 20 minutes of focused review. Highest confidence.
- **Sample:** Matt validates Dragon Bloom + 2 other presets that Matt knows well (e.g., Aurora Veil + Volumetric Lithograph). The remaining 5 ride on the automated tests and golden hashes. Faster.

**My recommendation:** sample (Dragon Bloom + Aurora Veil + Volumetric Lithograph). If any of the three behave unexpectedly, expand to full sweep. Dragon Bloom is the new preset that motivated the fix; Aurora Veil and VL are well-characterised long-running presets whose authors will catch a regression most reliably.

### Decision 3 — Trivial-P1 collapse

Per the Hard Rules section above. **My recommendation: collapse.** The diagnosis is documented in BUG-025 across two sessions, the fix is contained, and the multi-increment protocol exists for situations where instrumentation is needed to surface the failure — here the failure is already surfaced in the reference sessions. One commit for the fix + tests + KNOWN_ISSUES + RELEASE_NOTES is cleaner than three commits when there's no diagnostic gap to fill.

## Phased plan (assuming Decision 1 = A, Decision 2 = sample, Decision 3 = collapse)

1. **Confirm the diagnosis once more in code.** Read `BandEnergyProcessor.processFrame` carefully (the agent's exploration report described it; re-verify the line numbers and the EMA semantics in your own read). If anything differs from the kickoff (line numbers shifted, an EMA constant has changed), surface and pause.

2. **Write the failing regression test.** Two cases in `BandEnergyProcessorTests`:
   - `test_coldStartTransientRejection_holdsEMAStable`: feed 12 transient frames (the recorded shape from `2026-06-02T01-12-51Z` frames 310–321), then 120 steady-state frames at the AGC convergence target. Assert that after the steady-state window the EMA's running average is within ±30 % of the steady-state input. Currently fails (the EMA is ~200 % of steady-state).
   - `test_steadyStateConvergence_unchanged`: feed 600 frames of constant non-transient input. Assert AGC output `bass` ∈ [0.45, 0.55] across the last 60 frames. This must pass both before and after the fix. Regression-locker for the existing convergence behaviour.

3. **Implement Approach A.** New constants in `BandEnergyProcessor`:
   ```swift
   private static let agcTransientRejectMultiplier: Float = 3.0
   private static let agcTransientRejectFrames: Int = 60
   ```
   In `processFrame` EMA update:
   ```swift
   let withinRejectionWindow = frameCount < Self.agcTransientRejectFrames
   let isTransient = totalRawEnergy > agcRunningAvg * Self.agcTransientRejectMultiplier
   if frameCount == 0 {
       agcRunningAvg = max(totalRawEnergy, 1e-6)
   } else if withinRejectionWindow && isTransient {
       // Carry previous average forward; do not let cold-start outliers poison the EMA.
   } else {
       agcRunningAvg = agcRate * agcRunningAvg + (1 - agcRate) * totalRawEnergy
   }
   ```
   Code review the boundary case where `agcRunningAvg = 1e-6` from initialisation (so `× 3 = 3e-6`) — any sample > 3e-6 would be rejected at frame 1. Fix: either skip rejection on frame 1 (`frameCount >= 1` in the condition) or use a noise-floor minimum reject threshold. Recommend the former.

4. **Verify the failing test now passes.** Run `swift test --filter BandEnergyProcessorTests`. Both new tests pass; all existing tests still pass.

5. **Run the broader preset-side sweep.** `swift test --filter "PresetAcceptance|PresetRegression|PresetLoader"` — 4 acceptance × 17 + 3 regression × 17 + count gate. Confirm zero regressions. If golden hashes shift, STOP and surface to Matt before regenerating — the AGC change should be a no-op in steady state, so shifted hashes mean the fix has unintended steady-state effects.

6. **Build the app.** `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`.

7. **Matt M7 validation.** Sample sweep (Dragon Bloom + Aurora Veil + Volumetric Lithograph) on a multi-track Spotify session and a multi-track LF session. Matt confirms each preset reads as expected on both paths.

8. **Update docs:**
   - `docs/QUALITY/KNOWN_ISSUES.md` BUG-025: `Status: Resolved`, `Resolved: <date>, commit <hash>`, fill the verification-criteria checkboxes.
   - `docs/RELEASE_NOTES_DEV.md`: new entry `[dev-YYYY-MM-DD-X]` naming the eight affected presets and citing the reference sessions.
   - `docs/ARCHITECTURE.md` § Audio Analysis Tuning AGC subsection: add the transient-rejection behaviour to the AGC description.
   - `CLAUDE.md` § What NOT To Do: add a single bullet pointing at the new constants — *"Do not write to `agcTransientRejectMultiplier` or `agcTransientRejectFrames` outside the BandEnergyProcessor unit tests. The rejection window is calibrated to the empirical Spotify cold-start pattern; changing the multiplier will affect all 8 deviation-consuming presets."*

9. **Commit + push decision.** Local commit on `main` per CLAUDE.md. Do not push without Matt's "yes, push."

## Done-when criteria

The increment is done when ALL of the following are true:

- [ ] `test_coldStartTransientRejection_holdsEMAStable` passes (new regression test).
- [ ] `test_steadyStateConvergence_unchanged` passes (regression-locker for existing behaviour).
- [ ] All 17 `PresetAcceptanceTests` × 4 invariants pass.
- [ ] All 17 `PresetRegressionTests` × 3 fixtures pass with no golden-hash drift, OR if drift is present, Matt has explicitly approved the new hashes.
- [ ] Full engine test sweep passes (≥ 1369 / 1370 tolerance for known flakes).
- [ ] App build green.
- [ ] Matt M7 sample sweep (Dragon Bloom + Aurora Veil + Volumetric Lithograph) on Spotify shows each preset reads as appropriately reactive.
- [ ] Same M7 sweep on LF shows no regression.
- [ ] `bassDev fires` percentage on a fresh Spotify session exceeds 20 % of frames over the post-active window (sanity floor).
- [ ] BUG-025 entry in `KNOWN_ISSUES.md` is marked `Resolved` with commit hash.
- [ ] `docs/RELEASE_NOTES_DEV.md` entry written.

## Stretch scope (only if Matt explicitly opts in)

- **BUG-026 follow-up:** the "quiet input" toast (sibling bug, P2). Once the AGC is robust to transients, a "tap input is structurally too quiet" warning becomes more useful — currently the AGC's mis-convergence would mask a quiet-signal warning. Worth considering as the next increment after AGC.1.
- **Per-band EMA migration:** the AGC currently tracks total energy across all 6 bands. A per-band EMA would normalise each band independently and make `bassDev` independent of mid/treble content. Out of scope for AGC.1, but worth noting in `ENGINEERING_PLAN.md` as a future Phase DSP / Phase AGC item.

## What success looks like

A multi-track Spotify session captured immediately after the fix lands shows:
- `bassRel` distribution roughly centred on zero across post-active frames.
- `bassDev` fires on ≥ 20 % of frames (vs 1.8 % today).
- The cold-start transient is rejected from the EMA — `agcRunningAvg` after the transient is within 30 % of the steady-state input.
- All eight deviation-consuming presets show the same dynamic-range behaviour on Spotify as they do on LF.
- Dragon Bloom Spike 1 passes its Matt-perceptual "dancing to the music" gate on Spotify without any further shader work.
