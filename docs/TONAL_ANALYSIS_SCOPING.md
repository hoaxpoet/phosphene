# Tonal Interval Vector (TIV) Analysis — Scoping Proposal

**Status:** Scoped + capability-audited 2026-07-08 (TONAL.0; D-178 **Accepted**). **Matt GO (2026-07-08); first preset = Nacre (§7).** TONAL.1 in build. This doc is self-contained — a fresh session should be able to execute TONAL.1 from it. No Swift was touched in TONAL.0; every decision below carries code evidence (file:line), not a guess.

---

## 1. The problem

The pipeline computes energy, beats, stems, onsets, centroid, pitch, mood — and **nothing about harmony as a position**. The consequences are in the shipped record:

- **NACRE.3's "hue ← harmony" is actually centroid deviation** — a brightness proxy, not harmony (`Nacre.metal`; sidecar `description`). MITOSIS.2c's psychedelic hue swings on the same centroid proxy (energy-paced phase + `spectralCentroid` bias).
- **K-S key estimation exists but is treated as unreliable.** Nuance from the audit: the "key estimation is unreliable" note lives in *app-layer BUG-053 comments* (`VisualizerEngine.swift:602`, `VisualizerEngine+Audio.swift:183`), **not** in the estimator itself — `docs/CAPABILITY_REGISTRY/DSP_MIR.md:126` treats `ChromaExtractor` as `production-active`. But CENSUS.3 gives the objective read: **K-S is 35 % F#-minor-biased, median confidence 0.53** (`docs/diagnostics/CENSUS_PILOT_REPORT.md`). That distribution is a systematic-fold smell (§Decision 1).
- **Chord recognition (Tonic) was considered and correctly deferred at MV-3** — symbolic labels are heavy, ML-shaped, unnecessary for visuals.

The **Tonal Interval Vector** (TIV; Bernardes et al. 2016, descended from Harte's tonal centroid and Chew's spiral array) is the cheap continuous alternative: a 12-point weighted complex DFT of the chroma vector per MIR frame yields (a) position on the circle of fifths, (b) consonance, (c) tension against a decaying tonal center, (d) harmonic-change flux — **no labels, no model, no new ML**. A modulation becomes a hue drift; a departure-and-return becomes a rising-and-resolving scalar.

## 2. The reframe — relationships, not labels

TONAL is **not a sync channel.** The MILKDROP_ARCHITECTURE finding stands: analysis richness does not buy beat-connection — feel comes from feedback architecture. TONAL is the **palette-coherence and long-arc channel**:

- related keys → related colors (hue on the **circle of fifths**, not the chromatic circle);
- tonal tension → slow macro state (fog, camera drift, coherence);
- harmonic flux → an **accent**, subordinate to the Audio Data Hierarchy (continuous energy stays primary).

**Design rule for every consumer:** tonal signals encode **relationships, never labels** — no note names or chord symbols anywhere user-facing. And per the NACRE durable lesson, the medium is **hue / palette / motion, never brightness**.

## 3. The TIV math (Bernardes et al. 2016 — taken verbatim, not re-derived)

Per MIR frame, from the 12-element chroma vector `c(n)`, n = 0…11 (C…B):

1. **L1-normalize** the chroma: `c̄(n) = c(n) / Σ c(n)` (guard Σ = 0 → all-zero TIV → gated as silence).
2. **Weighted 12-point complex DFT**, coefficients k = 1…6:

   `T(k) = w(k) · Σ_{n=0}^{11} c̄(n) · exp(−j·2π·k·n / 12)`

3. **Weights `w(k)`** (verbatim, Bernardes 2016 / the TIVlib reference implementation — emphasize the consonant-interval axes; **do not re-derive**):

   | k | 1 | 2 | 3 | 4 (**thirds**) | 5 (**fifths**) | 6 |
   |---|---|---|---|---|---|---|
   | w(k) | 2 | 11 | 17 | 16 | 19 | 7 |

   k = 5 is the circle-of-fifths axis; k = 4 the major-thirds axis (the fifths phase is the hue driver; the thirds phase carries the major/minor lean fifths alone can't).

Normalization constant for magnitudes: `‖T‖_max = √(Σ_{k=1}^{6} w(k)²)` — a single pitch class or pure triad drives `‖T‖ → ‖T‖_max`; broadband noise drives it toward 0.

## 4. Derived signals (the FeatureVector floats)

| field | definition | range | role |
|---|---|---|---|
| `tonal_phase_fifths` | `arg T(5)` (radians, wrapped) | −π…π | **hue driver** — position on the circle of fifths |
| `tonal_phase_thirds` | `arg T(4)` (radians, wrapped) | −π…π | major/minor lean; secondary palette axis |
| `tonal_consonance` | `‖T‖ / ‖T‖_max` | 0…1 | saturation gate + **atonality/noise gate**: sustained low consonance decays all tonal signals to a neutral rest state (the 3.18 sustained-condition pattern) so presets never chase percussion or noise |
| `tonal_tension` | `‖T_fast − T_slow‖ / ‖T‖_max` — distance between a fast center-of-effect (~2 s decay) and a slow one (~20 s decay) | 0…1 | "how far from home." Both centers **reset on track change** (D-026 reset discipline) |
| `harmonic_flux` | smoothed frame-to-frame `‖T_t − T_{t−1}‖` (Harte HCDF) | 0…1 | spikes at chord changes. **Shipped raw**; per-preset `hitEnv`-style envelopes stay CPU-side preset code (the Filigree/Mitosis pattern), not pipeline state |

## 5. The three decisions (with code evidence)

### Decision 1 — Chroma reuse: **YES, TONAL.1 is a consumer, not a new DSP stage.**

A reusable 12-bin chroma vector already exists and is already computed once per frame:

- `ChromaExtractor.process(magnitudes:)` (`PhospheneEngine/Sources/DSP/ChromaExtractor.swift:246`) returns `Result.chroma` (`:299`); `MIRPipeline` exposes it as `latestChroma` (`MIRPipeline.swift:39`) and **already feeds it to a second consumer**, `StructuralAnalyzer.addFrame(chroma:)` (`StructuralAnalyzer.swift:174`).
- **Plug-in point:** register a `TonalAnalyzer` in `MIRPipeline` beside `structuralAnalyzer` (`MIRPipeline.swift:20`), call it in `process(...)` right after `let chroma = chromaExtractor.process(...)` (`:193`), passing `chroma.chroma`. No FFT recompute, no new fold.
- **STFT it inherits:** 1024-pt / 512-bin FFT, 46.875 Hz bin resolution (`FFTProcessor.swift:35`; `ChromaExtractor` constructed at `MIRPipeline.swift:159`), **~94 Hz frame cadence** (512-sample hop @ 48 kHz, `VisualizerEngine+Audio.swift:272`). Deterministic given identical magnitude input.
- **Free synergy:** `DSP_MIR.md:19` records that the per-frame chroma→novelty chain currently has **no live runtime consumer** (`production-orphan`). A live TIV path gives that already-running work its first reader.

**The documented defect (Decision 1's "if the fold is why K-S is unreliable" clause).** The fold floors at **`minFrequency = 500 Hz` (≈B4)** (`ChromaExtractor.swift:66`) — the entire bass register is discarded, by design: *"46.875 Hz spacing causes systematic pitch class bias (e.g., bins 2, 5, 10 all map to F#)"* (`:63`). This is the plausible root of CENSUS.3's **35 % F#-minor bias**. Two consequences for TIV:

1. **Root/bass-line harmony is invisible** — TIV sees only upper-harmonic chroma. Standard for chroma, but flag it (the parked "bass-stem TIV for root motion" is the upgrade).
2. **The F#-minor bias may bias `tonal_phase_fifths`.** Likely *less* damaging to TIV than to K-S: K-S peak-picks a single key over a 23 s accumulation, so a per-PC bias tips the winner; TIV uses all 12 PCs in a weighted DFT, so a systematic bias shifts the phase *offset* but should preserve the **relationships** (modulation Δ, flux) that are TONAL's actual product. **Unproven** — this is the primary validation risk, and §8.5 external key-DB ground truth is the hook that settles it (validate `tonal_phase_fifths` migration against known modulations before trusting the absolute).

### Decision 2 — Float budget: **exactly 5 contiguous pads available; take all 5, zero slack.**

`FeatureVector` is 48 floats / 192 B, 16-byte aligned (`AudioFeatures+Analyzed.swift:47`; asserted `UMABufferTests.swift:165`, `PipelineIntegrationTests.swift:202`). The tail holds **exactly 5 contiguous padding floats** — `_pad8`…`_pad12` (1-based floats 44–48, `:206`), zeroed in `init` (`:252`). (floats 35–38 = `beatPhase01`/`beatsUntilNext`/`barPhase01`/`beatsPerBar`, already promoted by MV-3b/S9, `:163`,`:171` — confirmed used.) `beatPhase01`/`barPhase01` are FeatureVector fields, so the five tonal floats share the correct home (full-mix MIR, not StemFeatures).

**Allocation** (rename `_pad8`…`_pad12`): `tonal_phase_fifths`, `tonal_phase_thirds`, `tonal_consonance`, `tonal_tension`, `harmonic_flux`.

- **Recommendation: keep all 5.** The spec's "if tight, cut `tonal_phase_thirds`" fallback is not needed — all 5 fit. Cutting thirds to preserve one pad of speculative headroom trades a real signal (the major/minor axis) for a "for later" slot — don't. **Consequence, flagged:** zero slack remains; the *next* FeatureVector field after TONAL forces a 192 B → resize (all preset preambles + both Metal mirrors + the two layout tests). A known, bounded, one-time tax — not TONAL's to pay.
- **Lockstep edit (TONAL.1), three places, byte-identical:** the Swift struct (`AudioFeatures+Analyzed.swift`, rename + wire in `init`), the **real** MSL preamble (`PresetLoader+Preamble.swift:70`), and the **already-stale** doc-comment mirror (`AudioFeatures+Analyzed.swift:42` — it lists a phantom `_pad7`, reclaimed long ago for `pulseRegionalBlend01`; fix it in the same commit). `CommonLayoutTest`/`UMABufferTests` stay at 192 B; the offset assertions don't touch the pad region, so goldens don't move.

### Decision 3 — Chroma input quality: **full-mix existing chroma (do-least). Stem/HPS/bass-octave parked.**

The three candidates and what the code says:

- **(a) full-mix + median-filter harmonic emphasis (HPS):** the existing fold has no HPS. Adding it means editing `ChromaExtractor`, which is *shared with K-S* — risk of shifting K-S. **Defer**: ship on raw full-mix chroma, and add HPS in TONAL.2 *only if* the corpus shows percussion breaking the consonance gate.
- **(b) live stem buffers, drums excluded:** the per-frame stem path **does** expose raw drums-excluded audio — `latestSeparatedStems` (`VisualizerEngine+Stems.swift:205`), sliced as 1024-sample windows at ~94 Hz (`VisualizerEngine+Audio.swift:327`), stems `[vocals, drums, bass, other]` so drums = index 1, use 0/2/3. **But two disqualifiers for TONAL.1:** (i) **5–10 s latency** is baked in (`DECISIONS.md:485`) — fine for a slow palette arc, wrong for flux accents; (ii) the stems live in the **App target** while `MIRPipeline` is in the **DSP package** — a `TonalAnalyzer` inside `MIRPipeline` cannot reach them without an architecture inversion. **Defer** to the parked "stem-fed chroma" item.
- **(c) full-mix raw (do-least):** this is what `ChromaExtractor` already does, and what `latestChroma` already carries. **Chosen.** The `tonal_consonance` gate is *designed* for exactly this input — percussion/noise → low `‖T‖` → signals decay to neutral. The architecture already absorbs the do-least case. And the 500 Hz fold floor already drops the kick fundamental, so bass-drum contamination is pre-attenuated.

**Low-frequency handling:** a finer bottom-octave pass is **not available** without a larger FFT (new DSP work) — the existing 46.875 Hz bins are exactly why the fold floors at 500 Hz. **Accept the 500 Hz floor**; TIV consumes the same upper-harmonic chroma. Root-motion invisibility is the flagged cost (Decision 1); the parked bass-stem TIV is the upgrade.

## 6. Float allocation summary

| slot (1-based) | old name | new field | signal |
|---|---|---|---|
| 44 | `_pad8` | `tonal_phase_fifths` | `arg T(5)` |
| 45 | `_pad9` | `tonal_phase_thirds` | `arg T(4)` |
| 46 | `_pad10` | `tonal_consonance` | `‖T‖/‖T‖_max` |
| 47 | `_pad11` | `tonal_tension` | fast/slow center distance |
| 48 | `_pad12` | `harmonic_flux` | smoothed HCDF |

Struct stays 48 floats / 192 B / 16-byte aligned. Zero pads remain.

## 7. Consumption thesis + candidate first preset (TONAL.3 — Matt picks)

TONAL.3 upgrades **one** certified preset's existing hue channel from the centroid-deviation proxy to the real signal: hue ← `tonal_phase_fifths` on a circle-of-fifths mapping, `tonal_consonance` gating saturation, `tonal_tension` as one slow secondary (FA #67 — one primitive per layer; flux accents are a *later* increment). The M7 claim is deliberately modest: **the palette travels with the song's harmony** — drifts when it modulates, holds when it vamps, and the same song transposed lands on shifted-but-related colors.

Two candidates where the channel already exists:

- **Nacre (recommended default).** Its sidecar `description` *already claims* "hue ← harmony" while actually using centroid deviation — so swapping to real TIV is the cleanest possible "does the real signal read better than the proxy" test **and** closes an honesty gap (the NACRE.5 rule: the description must match the shipped coupling). Single clean hue driver; it's a certified feedback preset whose multi-pass flash harness (NACRE.4) is already wired for the re-measure.
- **Mitosis.** MITOSIS.2c's "psychedelic" hue is energy-paced phase + centroid bias + a travelling spatial wave — more moving parts, and the deliberately swimmy psychedelic intent may *fight* a harmony-coherent palette.

**Matt's pick (2026-07-08): Nacre.**

**TONAL.2b-measured saturation targets for the Nacre coupling** (soft-saturate against the realized p99, NOT 1.0 — the deviation-primitive discipline): `tonal_consonance` → 0.32, `tonal_tension` → 0.163, `harmonic_flux` → 0.110. The consonance gate is already applied analyzer-side (`consonanceFloor` 0.05); the preset maps [floor…0.32] → [pale…saturated], and tension [0…0.163] → its slow secondary range.

## 8. Work breakdown (the phased increments)

| # | Increment | Gate |
|---|---|---|
| TONAL.0 | capability audit + this doc + go/no-go | **← here.** Done-when: doc committed, decisions carry code evidence, Matt's go/no-go + preset pick recorded, D-178 reserved |
| TONAL.1 | `TonalAnalyzer` in `MIRPipeline` (infra only, no preset touches) | **✅ code-complete 2026-07-08** — 6-test synthetic suite green, 192 B held, CSV columns + contract across all 3 mirrors, DocIntegrity Module Map row. Live-session CSV pending Matt's build |
| TONAL.1b | `SpectralCartograph` tonal trace row (fifths-phase wrapped trace + consonance) | **✅ code-complete 2026-07-08** — BR panel 3→5 rows (5TH φ teal + CONS pink), 2 new rings in `SpectralHistoryBuffer`'s reserved region (no resize), buffer round-trip test + app build green. Pending Matt's live view at the TONAL.3 listen |
| TONAL.2a | `TonalDumper` executable (retained-diagnostic) | **✅ code-complete 2026-07-08** — production MIR loop at 512-hop, `--audio`/`--manifest` modes, `TonalStats` pure math + 6 unit tests, lint 0, wiring smoke-tested. No constant changed |
| TONAL.2b | corpus calibration run + `TONAL_PILOT_REPORT.md` | **✅ done 2026-07-08** — 1000-track pilot (2.66M frames, 0 skips). Per-genre consonance ranks classical 0.18 > jazz 0.14 > … > hiphop 0.10 (measures real harmony). Gate recalibrated `consonanceFloor` 0.12→**0.05** / width 0.10→**0.03** (the 0.12 placeholder sat at the corpus median). Saturation p99s for TONAL.3: consonance **0.32**, tension **0.163**, flux **0.110**. See [`docs/diagnostics/TONAL_PILOT_REPORT.md`](diagnostics/TONAL_PILOT_REPORT.md) |
| TONAL.3 | Nacre consumption (hue ← fifths, saturation ← consonance) | **⏳ code-complete 2026-07-10, pending live M7** — proxy→real swap done, evidence-rendered (key change shifts the palette gold→teal), flash 0.50/s SAFE, route-coverage green, sidecar honesty updated. Tension→dispersion deferred to round 2 (fixture-breadth). Matt's ear is the gate (2 rounds max) |

**Infra and preset increments are never bundled** — TONAL.1 lands with *no preset reading the new floats.*

## 8.5 Relation to CENSUS + external key ground truth

Independent, free synergy: once TONAL.1 is in `MIRPipeline`, any census pass running MIRPipeline frames (CENSUS.4 or a re-run) picks up TIV columns at no extra cost, and the CENSUS §8.5 external key-DB enrichment later gives **ground truth to validate `tonal_phase_fifths`** against known keys — the settle-it hook for the F#-minor-bias risk (Decision 1). No coupling: the CENSUS measure-only scope guard is untouched.

## 9. Parked (recorded so TONAL.1's API anticipates them; do not spec until their trigger)

- **Chord/key symbolic events** — the MV-3-deferred item, unblocked cheaply by TIV (template match + Viterbi over tonal-centroid features → Orchestrator events at 200–500 ms). **Trigger:** an Orchestrator feature needing discrete harmonic events.
- **Key context from full-track offline TIV** — a per-track key/mode summary on `CachedTrackData` (the LF.2 offline path); palette-library selection could add a key bias (LM.4.7-style). **Trigger:** after §8.5 key ground truth validates the signal.
- **Stem-fed chroma** — drums-excluded fold (indices 0/2/3), optional bass-stem TIV for root motion, *if* a later engine change makes the App→DSP stem path cheap at MIR cadence (Decision 3 audit found it unsuitable now: 5–10 s latency + target boundary).
- **HPS harmonic emphasis** on the full-mix fold — **Trigger:** TONAL.2 corpus shows percussion breaking the consonance gate.

## 10. References

- **Bernardes, Cocharro, Caetano, Guedes, Davies (2016)** — *A multi-level tonal interval space for modelling pitch relatedness and musical consonance.* J. New Music Research. (TIV definition + the `w(k)` weights above.)
- **Harte, Sandler, Gasser (2006)** — *Detecting Harmonic Change in Musical Audio.* (Tonal centroid + HCDF = `harmonic_flux`.)
- **Chew (2000)** — *Towards a Mathematical Model of Tonality* (the Spiral Array — the ancestor of the fifths/thirds geometry).
- Internal: `ChromaExtractor.swift` (the reused fold), `MIRPipeline.swift` (the host), `AudioFeatures+Analyzed.swift` (FeatureVector), `docs/CAPABILITY_REGISTRY/DSP_MIR.md` (CA.1 chroma audit + the fold-floor drift), `docs/diagnostics/CENSUS_PILOT_REPORT.md` (K-S F#-minor bias). Decisions: **[D-178]** (this phase, Proposed), [D-026] (deviation/reset discipline), [D-099] (FeatureVector/MSL contract), [D-009] (no-CoreML — TONAL adds no ML), [D-171] (Nacre).
