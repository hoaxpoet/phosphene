# CLEAN.3.7 — Kickoff: Resolve the sample-rate contract (live-tap → analysis), [GAP-2]

## Why this is next

With Phase 5 closed (CLEAN.5.5) and **CLEAN.7.6 / G9 (flash-safety)** running in a parallel session, **CLEAN.3.7 ([GAP-2])** is the last un-started item in Matt's approved June scope (Phases 0/1/2/5 + gaps G1/G2/G7/G8/G9 — G1 is code-complete pending a manual swap test, G7/G8 shipped in Phase 1). It is a **DSP-correctness increment with no M7 visual review**, so it runs cleanly in parallel with the visual G9 work (M7 review bandwidth is the binding constraint, not Claude's).

The audit (`CODE_AUDIT_2026-06-13.md:174`, G2) rated this **P1/P2** and explicitly said it **"needs trace."** A pre-kickoff trace (below) was done — it suggests the streaming path is **already rate-aware**, which means this is most likely a **doc-reconcile + latent-default-trap cleanup + a verification gate**, NOT a resample fix. That reframing is the point of 3.7a: confirm or refute the trace with real evidence before changing any audio code.

## Current state (VERIFIED 2026-06-16 — re-check before trusting; code drifts)

| Aspect | State |
|---|---|
| **Tap rate** | `SystemAudioCapture.sampleRate` starts at `48000` (`SystemAudioCapture.swift:72`); `readTapFormat` overwrites it with the **actual** `format.mSampleRate` read from `kAudioTapPropertyFormat` (`:278`); on a read failure it **keeps 48 kHz and warns** (`:282`). So the tap reports the real hardware rate (typically 48 kHz on macOS). |
| **The "44.1 kHz" doc** | `Audio/Protocols.swift:111` — *"sampleRate: Sample rate in Hz (will be resampled to 44100 if different)."* This is on `StemSeparating.separate(...)` — it is the **stem separator's** internal contract, **not** a global pipeline assumption. The audit's "documents 44.1 kHz resample, resampler only in local-file path" misattributes it. |
| **Stem path** | `StemSeparator.modelSampleRate = 44100` (`StemSeparator.swift:51`); `separate()` resamples when `abs(sampleRate - 44100) > 1` (`:150–155`). **Resamples — correct.** Open-Unmix HQ expects 44.1 kHz / nFFT 4096 (`:48`). |
| **Beat This! path** | `BeatThisPreprocessor.sampleRate = 22050` (`:60`); `process()` resamples when input ≠ 22050 (`:170–172`). **Resamples — correct.** |
| **Streaming FFT/MIR** | The callback passes the **real tap rate** through: `VisualizerEngine+Audio.swift:85` (`sampleRate: rate`), `:110` (`fft.processStereo(..., sampleRate: rate)`). Bin→Hz is parameterized: `SpectralAnalyzer.swift:110`, `ChromaExtractor.swift:137` (`binResolution = sampleRate / fftSize`), `BandEnergyProcessor` band-cutoff→bin uses the passed rate. **Rate-aware — bins are correct for whatever rate is passed.** |
| **The latent trap (the real finding)** | **Inconsistent hardcoded defaults.** Most DSP/Audio signatures default `sampleRate: Float = 48000` (`FFTProcessor.swift:110/191`, `SpectralAnalyzer:104`, `MIRPipeline:143`, `ChromaExtractor:130`, `BandEnergyProcessor:182`, `BeatDetector:165`) — but `PitchTracker.swift:103` and `StemAnalyzer.swift:164` default `= 44100`. Any construction/call site that **omits** the rate silently assumes a fixed value, and the two camps disagree. This — not the streaming FFT path — is where a wrong rate can hide. |
| **Existing coverage** | `Tests/.../Integration/TapSampleRateRegressionTests.swift` and `StemSampleBufferRateTests.swift` already exist. **Read both first** — know what's already locked before adding. |
| **Sample-rate lint** | `Scripts/check_sample_rate_literals.sh` (D-079) gates raw rate literals. The defaults above may be a known carve-out — check, and don't break the lint. |

## Scope

**In:** CLEAN.3.7 — (a) **trace & decide** whether the live-tap (and local-file) path delivers the correct rate to every rate-sensitive stage, with real-session evidence; (b) **reconcile the doc** so it matches code (audit done-when); (c) **remove the latent inconsistent-default trap**; (d) **lock it with a regression gate**. **Out:** adding a resample to the streaming path *unless 3.7a proves a stage runs at the wrong rate* (a needless RT-path resample costs CPU and quality); the stem/beat-this internal resamples (already correct); G1 device-swap (CLEAN.1.5, manual gate only); anything M7/visual.

## The work

### 3.7a — Trace & decide (diagnosis; commit findings + verdict, then stop if a fix is non-trivial)
Per the Defect Handling Protocol (evidence before implementation) and the audit's "needs trace":
- **Follow the rate end-to-end on the streaming path:** `SystemAudioCapture.readTapFormat` → `AudioInputRouter` → `VisualizerEngine+Audio.makeAudioSampleCallback` → `FFTProcessor.processStereo` → the **MIRPipeline construction + every sub-analyzer** (`SpectralAnalyzer`, `ChromaExtractor`, `BandEnergyProcessor`, `BeatDetector`, `PitchTracker`, `StemAnalyzer`) → `StemSeparator.separate` → `BeatThisPreprocessor`. At each rate-sensitive consumer, confirm the **actual tap rate is passed**, not a hardcoded default. **Highest-risk question:** are `MIRPipeline` / `PitchTracker` / `StemAnalyzer` constructed with the live tap rate, or do they fall back to their `= 48000` / `= 44100` defaults? (The 48000-vs-44100 split is the smoking-gun candidate.)
- **Do the same for the local-file path** (44.1 kHz files via `LocalFilePlaybackProvider`): confirm the file's real rate reaches every stage.
- **Use real evidence, not synthetic audio** (FA #27): a captured streaming-session `features.csv` and/or a unit trace of the construction sites. Confirm against the artifact — do not assert from reading alone.
- **Verdict in `KNOWN_ISSUES.md`:** real defect (a stage consuming the wrong rate on a live path) vs. doc-drift + latent-default-trap only. **If a real defect → escalate to the multi-increment Defect Protocol** (instrument → diagnose → fix → validate); commit the trace and stop. If no live defect, proceed to 3.7b/c in this increment.

### 3.7b — Reconcile the doc + remove the inconsistent-default trap (assuming 3.7a finds no live defect)
- **Doc (audit done-when "doc matches code"):** make `Audio/Protocols.swift:111` unambiguous that 44.1 kHz is the **stem separator's** internal resample target, not a pipeline rate; document the real per-stage contract in `docs/ARCHITECTURE.md §Audio Analysis Tuning` — FFT/MIR run at the **tap's actual rate** end-to-end; stems resample to 44.1 kHz; Beat This! to 22.05 kHz.
- **Kill the default trap:** the `sampleRate: Float = 48000` / `= 44100` defaults are a footgun (omitting the arg silently picks a rate; the two camps disagree). Engineering call — pick one: **(i)** remove the defaults so every call site must pass the real rate (compile-time forcing, strongest), or **(ii)** route all stages through one shared source of truth (the tap's rate / a single `analysisSampleRate`). Do **not** leave two different magic defaults. Keep `readTapFormat`'s 48 kHz **fallback** (`:282`) sane.
- Re-run `check_sample_rate_literals.sh`; keep D-079 honest.

### 3.7c — Lock it with a gate
- Extend `TapSampleRateRegressionTests` / `StemSampleBufferRateTests` (after reading what they cover): assert (1) the live-tap rate propagates to FFT + MIR + the stem/beat-this entry points; (2) **bin→Hz is computed from the real rate** — feed the same buffer as 48 kHz vs 44.1 kHz and assert a band cutoff (e.g. 250 Hz bass/mid) lands on a **different** bin index, proving no stage hardcodes; (3) if defaults were removed, the construction sites pass the live rate.
- Keep the new assertions **GPU-free** where possible so they can join the CI fast-gate `--filter` allow-list (the CLEAN.5.1/5.5c pattern; `--filter` matches the **type** name).

## Rules / pitfalls
- **Diagnosis-first — do not add a streaming-path resample unless 3.7a proves a stage runs at the wrong rate.** The default hypothesis from the trace is "already rate-aware"; a needless resample degrades quality and burns RT-thread CPU.
- **Real-music evidence, not synthetic** (FA #27) for any "is it actually wrong" claim — captured `features.csv`, not hand-authored envelopes.
- **RT-thread discipline:** any change near `makeAudioSampleCallback` stays allocation-free (CLEAN.4.1 / BUG-036 territory).
- **Don't weaken D-079** (`check_sample_rate_literals.sh`).
- **Per-stage, not global:** the fix is "every rate-sensitive stage uses the *same actual* rate," not "force everything to 44.1 kHz" — the FFT/MIR running at 48 kHz is fine *as long as the bin math uses 48 kHz*.

## Closeout (per CLAUDE.md Increment Completion Protocol)
- `Scripts/closeout_evidence.sh` block (bootstrap worktree fixtures first; the streaming-session artifact is the domain evidence for `dsp.*`).
- Visually verifiable only if a feature-correctness fix lands — otherwise state "not visually verifiable."
- Update `docs/ENGINEERING_PLAN.md` (CLEAN.3.7 row → done), `docs/diagnostics/CODE_AUDIT_2026-06-13.md` (Part B **G2** + Part C Phase 3 row), `docs/RELEASE_NOTES_DEV.md`, `docs/QUALITY/KNOWN_ISSUES.md` (the 3.7a verdict). `RENDER_CAPABILITY_REGISTRY.md` — N/A.
- Small commits (trace+verdict; doc reconcile; default-trap removal; gate). **Push requires Matt's "yes, push."**

## After this
Matt's approved June scope (Phases 0/1/2/5 + G1/G2/G7/G8/G9) is then complete pending the two manual gates — **G1** (output-device swap) and **G9** (flash-safety, in flight). The remaining pool is the rest of **Phase 3** (CLEAN.3.1–3.6, 3.8 — P2 hardening) and **Phase 4** (performance), both needing Matt's re-prioritization before pickup.
