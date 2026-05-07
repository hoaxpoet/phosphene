Increment BUG-010 — Stem-separation quality audit (Open-Unmix HQ).
Investigation increment. NOT a fix. Output: a measurement report and a
decision on whether to keep, tune, or replace the current stem separator.

Authoritative bug record: file as new entry in
docs/QUALITY/KNOWN_ISSUES.md (BUG-010, Domain `ml.stems`).
Predecessors: BUG-007.4 / 007.5 / 007.6 / 007.8 (beat-sync precision
work) — those landed first because beat sync was the dominant residual
sync issue. BUG-010 is the next-tier audit: stem quality is upstream of
preset selection and per-stem visual modulation.

────────────────────────────────────────
DIAGNOSIS RECAP (read this carefully — investigation must not be skipped)
────────────────────────────────────────
Phosphene currently uses Open-Unmix HQ (vendored MPSGraph implementation,
~135.9 MB of weights in `PhospheneEngine/Sources/ML/Weights/`) to separate
the 30 s Spotify preview into 4 stems: vocals / drums / bass / other.
The stems feed:
  • `StemFeatures` (per-stem energy, attack ratios, onset rates) — drives
    preset scoring (`stemAffinity` sub-score) and per-stem visual modulation
    (Arachne spider trigger, Stalker gait, Volumetric Lithograph emphasis).
  • `drumsBeatGrid` — Beat This! re-run on drums-only stem; logged but
    NOT consumed at runtime (DSP.4 diagnostic).
  • Visual modulators in shaders (`stems.drums_energy_dev`, etc.).

Stems do **not** feed the drift tracker or grid timing — beat sync is
unaffected by stem quality. But stem quality directly affects:
  • Preset selection — orchestrator's `stemAffinitySubScore` reads
    `StemFeatures.*EnergyDev`. Noisy stems → wrong dev values → wrong
    preset for the section.
  • Visual fire timing — presets that key on `bassEnergyDev` or
    `drumsEnergyDev` (Arachne, Stalker, Volumetric Lithograph) fire on
    stem-derived events. Leakage / noise in the stem can fire the visual
    on cross-stem content (e.g. snare bleeding into bass stem fires
    bass-driven visuals on snare hits).

User raised the question after the 2026-05-07T22-00-00Z bass-forward
playlist session: "I suspect that stem separation is also really poor
in Phosphene at the moment and this is also impacting beat sync
precision." Beat sync is fixed (BUG-007.8); stem quality has not been
quantitatively measured against ground truth. We do not know whether
Open-Unmix HQ is "good enough" or whether it's the next bottleneck.

This audit produces the measurement that lets us decide.

────────────────────────────────────────
SCOPE — INVESTIGATION ONLY
────────────────────────────────────────
In scope:
- Build a measurement harness that runs Phosphene's `StemSeparator`
  against a small MUSDB18 subset (3–5 tracks checked into Git LFS).
- Compute SDR (Signal-to-Distortion Ratio), SIR (Source-to-Interferences),
  SAR (Sources-to-Artifacts) per stem against MUSDB18 ground truth.
  These are industry-standard separation quality metrics.
- Compute attack-time accuracy: run our `BeatDetector` on the produced
  drums stem and on the MUSDB18 ground-truth drums stem; compare onset
  timestamps.
- Compute cross-stem leakage: spectral correlation between Phosphene's
  vocals stem and ground-truth drums + bass + other (high correlation =
  leakage; near-zero = clean separation).
- Produce a diagnostic report at
  `docs/diagnostics/BUG-010-stem-separation-baseline.md`.
- File BUG-010 in `KNOWN_ISSUES.md` with one of three outcomes (see
  decision matrix below).

Out of scope:
- Replacing Open-Unmix HQ. If the audit shows poor quality, file
  BUG-011 with a specific replacement scope (e.g. Demucs HT v4) — do
  not preemptively start integration work in this increment.
- Changing the production stem-separation pipeline. The audit reads
  `StemSeparator` outputs; it does not modify them.
- Adding stem quality metrics to the runtime pipeline (no on-the-fly
  SDR measurement during playback). This is offline benchmarking.
- Auditing Beat This! quality. That's tracked separately (BUG-008).
- Auditing audio source quality (preview vs tap). That's tracked under
  BUG-007.9 candidate (hybrid runtime recalibration).

────────────────────────────────────────
WHAT TO BUILD
────────────────────────────────────────
1. **MUSDB18 subset fixture** in
   `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/musdb18_subset/`:
   - 3–5 tracks from MUSDB18 (the standard separation benchmark dataset).
   - Each track: `mixture.wav`, `vocals.wav`, `drums.wav`, `bass.wav`,
     `other.wav`. All stereo, 44.1 kHz, 16-bit PCM.
   - Pick tracks that span genres relevant to Phosphene's target use
     (electronic, rock, hip-hop, ambient). Avoid the test split tracks
     used by the original Open-Unmix paper — different distribution.
   - Total fixture size ~50–80 MB; use Git LFS.
   - License compatibility: MUSDB18 is research-use-only — annotate
     this clearly in the fixture README and gate tests behind
     `STEM_AUDIT=1` env var so they don't run in normal CI.

2. **`StemQualityAuditor` CLI** in
   `PhospheneEngine/Sources/StemAuditRunner/main.swift`:
   - Mirrors the existing `TempoDumpRunner` / `BeatThisActivationDumper`
     pattern (swift-argument-parser executable).
   - Args: `--musdb-dir <path>`, `--report-dir <path>`,
     `--track <name>` (optional — default: all tracks in the dir).
   - For each track:
     a. Load `mixture.wav` (full song, decode to Float32 stereo).
     b. Take a 10 s slice (matches StemSeparator's expected window).
     c. Run `StemSeparator.separate(audio:channelCount:sampleRate:)`.
     d. Load corresponding 10 s slices of ground-truth stems.
     e. Compute SDR / SIR / SAR per stem using the standard `museval`
        formulas (implementable directly with vDSP — no Python needed).
     f. Run `BeatDetector` on Phosphene's drums output AND ground-truth
        drums; compute onset-timing F1 score (matched within ±50 ms).
     g. Compute leakage: spectral cosine similarity between Phosphene's
        vocals stem and ground-truth drums + bass + other.
   - Output: per-track JSON + aggregate Markdown summary table.

3. **Diagnostic report** at
   `docs/diagnostics/BUG-010-stem-separation-baseline.md`:
   - Methodology (MUSDB18 subset, metric definitions, harness setup).
   - Per-track table: SDR / SIR / SAR / onset F1 / leakage per stem.
   - Aggregate table across all tracks.
   - Comparison to published Open-Unmix HQ baseline (the original paper
     reports drums SDR ~5.85 dB on MUSDB18 test set — we should land
     near that on our subset if the port is faithful).
   - Comparison to alternatives (cite Demucs HT v4 baseline ~9.5 dB
     drums SDR, BS-RoFormer ~10+ dB).
   - Decision: keep / tune / replace (see decision matrix below).

4. **`BUG-010` entry in KNOWN_ISSUES.md** with:
   - Status: Resolved (audit complete) or Open (decision deferred).
   - The measured metrics from the report.
   - The decision and rationale.
   - If decision is "replace": link to a follow-up BUG-011 with scoped
     replacement work. Do NOT do that work in this increment.

────────────────────────────────────────
METRICS — IMPLEMENTATION NOTES
────────────────────────────────────────
**SDR / SIR / SAR.** Standard `museval` formulas. The simplest
implementation is the BSS-Eval v3 formulation: project the estimated
stem onto the ground-truth source space, decompose into target / interference / artifact components, ratio in dB. Reference Python
implementation is `museval` (Python package); we re-implement in Swift.
~80 LOC of vDSP. Verify against the published Open-Unmix paper's
reported numbers as a sanity check.

**Onset-timing F1.** Run `BeatDetector` (the live one) on both the
Phosphene-produced drums stem and the ground-truth drums stem. Get
timestamp lists from `result.onsets[0]`. Compute F1 with ±50 ms match
window. Phosphene-produced onsets that have no ground-truth match
within ±50 ms are false positives; missed ground-truth onsets are
false negatives.

**Leakage.** Compute spectral magnitude vectors (FFT over the full
10 s slice) for each Phosphene stem and each ground-truth stem.
Cosine similarity between Phosphene[vocals] and ground-truth[drums]:
high value = drum content leaking into the vocals stem. We expect:
  • Phosphene[vocals] vs GT[vocals]: very high (~0.9+).
  • Phosphene[vocals] vs GT[drums]: low (~0.1 or lower).
  • Phosphene[drums] vs GT[bass]: low (kicks ARE in bass-band so some
    correlation is expected; >0.4 is concerning).

**Tolerances.** SDR is reported in dB; tolerance is ±0.5 dB across
runs (Open-Unmix is deterministic given the same input + weights).
Onset F1 should be ≥ 0.7 on MUSDB18 tracks where the drums are clearly
audible.

────────────────────────────────────────
DECISION MATRIX
────────────────────────────────────────
After running the audit, classify Open-Unmix HQ's measured drums-stem
SDR (the most relevant metric for Phosphene's beat / dynamics use):

  ≥ 6.0 dB drums SDR  →  KEEP. Open-Unmix HQ is acceptable for
                          Phosphene's needs. Document the baseline,
                          close BUG-010.

  4.0 – 6.0 dB        →  MARGINAL. Identify failure modes (which genres
                          / track types fail). File BUG-011 with
                          scoped tuning if a clear fix exists; close
                          BUG-010 with the data.

  < 4.0 dB drums SDR   →  REPLACE. Open-Unmix HQ underperforms its own
                          published baseline OR the per-stem-leakage
                          numbers indicate broken separation. File
                          BUG-011 with replacement scope (Demucs HT v4
                          is the realistic candidate — vendor MPSGraph
                          weights, similar Swift port pattern as our
                          BeatThisModel work). Close BUG-010 with the
                          data and link to BUG-011.

The published Open-Unmix HQ baseline on MUSDB18 test split is:
  vocals SDR ~6.32 dB, drums SDR ~5.85 dB, bass SDR ~5.23 dB, other ~4.02 dB.
If Phosphene's port lands near these numbers (within ±0.5 dB), the
port is faithful and the question becomes "is the architecture good
enough" rather than "is the port broken." If we're significantly below
the baseline, the port has a bug to fix before we can evaluate the
architecture.

────────────────────────────────────────
FILES LIKELY TO TOUCH / CREATE
────────────────────────────────────────
NEW:
- `PhospheneEngine/Sources/StemAuditRunner/main.swift` — CLI executable.
- `PhospheneEngine/Sources/StemAuditRunner/Metrics.swift` — SDR / SIR /
  SAR / leakage / onset F1 implementations. ~250 LOC of vDSP.
- `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/musdb18_subset/` —
  3–5 MUSDB18 tracks (mixture + 4 stems each), via Git LFS.
- `PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/musdb18_subset/README.md`
  — provenance, license, gating instructions.
- `Scripts/run_stem_audit.sh` — convenience wrapper for invoking the
  CLI on the fixture set.
- `docs/diagnostics/BUG-010-stem-separation-baseline.md` — the audit
  report.

EDITED:
- `PhospheneEngine/Package.swift` — add `StemAuditRunner` target alongside
  the existing `TempoDumpRunner` / `BeatThisActivationDumper`.
- `docs/QUALITY/KNOWN_ISSUES.md` — file BUG-010 with status + outcome.
- `docs/RELEASE_NOTES_DEV.md` — add an entry under the current dev
  release header.

DO NOT touch in this increment:
- `PhospheneEngine/Sources/ML/StemSeparator.swift` or any other
  StemSeparator code. The audit reads its outputs; it does not modify
  the separator itself.
- The runtime stem pipeline (`VisualizerEngine+Stems.swift`).
- The production preset metadata that consumes `StemFeatures`.

────────────────────────────────────────
DONE WHEN
────────────────────────────────────────
[ ] MUSDB18 subset fixture committed via Git LFS, with README citing
    the dataset's research-use license terms and the gating env var.
[ ] `StemAuditRunner` CLI builds and runs against the fixture set.
[ ] SDR / SIR / SAR / leakage / onset F1 metrics computed for all
    tracks × all 4 stems.
[ ] Diagnostic report at
    `docs/diagnostics/BUG-010-stem-separation-baseline.md` includes:
    methodology, per-track table, aggregate table, comparison to
    published Open-Unmix HQ baseline, comparison to alternative
    architectures, decision (keep / tune / replace) with rationale.
[ ] `BUG-010` entry filed in `KNOWN_ISSUES.md` with status reflecting
    the decision.
[ ] If decision is "tune" or "replace": follow-up BUG-011 filed in
    `KNOWN_ISSUES.md` with scoped fix work. Do NOT begin BUG-011 in
    this increment.
[ ] `swift test --package-path PhospheneEngine` green except the
    documented baseline flakes.
[ ] `swiftlint lint --strict` reports zero violations on touched files.
[ ] `swift run --package-path PhospheneEngine StemAuditRunner --help`
    prints the expected argument set.
[ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`
    clean (BUG-010 should not affect the app target — engine-only work).
[ ] `RELEASE_NOTES_DEV.md` updated.
[ ] Commit follows the standard `[BUG-010] <component>: <description>`
    format. Local commit only — do not push without explicit Matt
    approval.

────────────────────────────────────────
SUCCESS CRITERIA
────────────────────────────────────────
"Success" for this audit is producing the data, not a specific quality
score. The audit succeeds when:

  - The CLI runs end-to-end on the fixture set and produces deterministic
    metric output (re-running the same input produces identical numbers
    to within floating-point tolerance).
  - The SDR numbers measured on Phosphene's port land within ±0.5 dB of
    the published Open-Unmix HQ baseline on the same MUSDB18 tracks. If
    they don't, the port has a bug — investigate and fix BEFORE making
    the keep / tune / replace decision (the decision is meaningless on
    a broken port).
  - The diagnostic report is complete and ends with a clear decision +
    rationale.
  - If "replace" is the decision: BUG-011 has a concrete replacement
    candidate (architecture, weights vendoring path, expected effort)
    and a measured baseline of the alternative's published metrics on
    MUSDB18.

────────────────────────────────────────
NOTES FOR THE NEXT SESSION
────────────────────────────────────────
- This is the first quantitative audit Phosphene has done of any ML
  component. The infrastructure (CLI runner pattern, metric library,
  fixture handling) sets the precedent for future audits of other ML
  paths — the BeatThis port already has fixture-based tests, but
  there's no comparable infrastructure for stem separation. Build the
  pattern carefully so future audits can reuse it.
- MUSDB18 has 50 train + 50 test tracks. We only need 3–5 for a
  representative sample. Pick tracks that span: dense electronic,
  acoustic rock, hip-hop with prominent vocals, ambient/sparse.
  Document the choices in the fixture README so the audit is
  reproducible by anyone with MUSDB18 access.
- Do NOT use Phosphene's existing track fixtures (love_rehab,
  so_what, etc.) — those are unsuitable because we don't have ground-
  truth stems for them. MUSDB18 is the canonical benchmark; using it
  makes our numbers comparable to published research.
- Open-Unmix HQ runs at 44.1 kHz internally. MUSDB18 is 44.1 kHz
  stereo. No resampling needed.
- The 10 s window matches StemSeparator's MPSGraph batch size. For
  full-song SDR comparable to published numbers, you'd loop over
  10 s slices of the full track and aggregate. For a first audit, a
  single representative 10 s slice per track is enough to reveal
  whether the port is broken / the architecture is acceptable.
- If "replace with Demucs HT v4" comes up: the existing BeatThisModel
  port (PhospheneEngine/Sources/ML/BeatThisModel*.swift) is the most
  analogous prior work. Demucs HT v4 has a published checkpoint, the
  Hybrid Transformer architecture is implementable in MPSGraph, and
  the vendoring + weight-conversion pattern is identical to what
  DSP.2 Sessions 1–8 did for Beat This!. Estimated effort: 2–3 weeks
  for a port if pursued. Do NOT preemptively start.
- Do NOT touch the production stem pipeline in this increment. The
  audit reads `StemSeparator` outputs offline. Any production change
  is BUG-011's territory.
- The fixture commit will be ~50–80 MB via Git LFS. Confirm `.gitattributes`
  has `*.wav filter=lfs diff=lfs merge=lfs -text` covering the
  fixture path. The repo already uses LFS for ML weights (135 MB) so
  this is just an extension.
- Numbers reported in the published Open-Unmix paper are on the full
  test split (50 tracks); our 3–5-track subset will have noisier
  averages. Don't expect exact match to paper — within ±1 dB is
  acceptable for a faithful port on a small subset. Outside that
  range is a port-bug signal.
- Report should explicitly call out which tracks the audit chose,
  why, and what use cases each covers. A future "expand to N tracks"
  follow-up can keep the same harness and just add fixtures.
