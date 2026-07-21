# Multi-Instrument Separation for Broad Formats (incl. Classical) — Research Memo

**Date:** 2026-06-29
**Status:** Research / strategy memo. **Not a committed increment.** No code, no tests, no `ENGINEERING_PLAN`/`DECISIONS` edits made — this is a proposal surface for Matt's review. Where it says "would land," it means *if scoped into an increment later*.
**Scope:** how to "solve multi-instrument audio separation for a broad range of file formats (MP3/M4A/FLAC) including classical music," at and beyond the current state of the art, mapped onto Phosphene's existing architecture.

---

## TL;DR

The task name hides its own trap: it assumes the goal is *separation into named instruments*. Two reframes make it tractable, and they are the whole memo.

1. **Separate what you ask for, not a fixed list.** "Stems" (drums/bass/vocals/other) is a Western-pop vocabulary; a string quartet has none of those four. Any fixed output taxonomy is guaranteed to fail on some genre. The escape is *query/condition-based* separation — feed the mixture **plus a query** (label, text, example clip, timbre embedding) and get *that* source. One mechanism, unbounded vocabulary. This dissolves "including classical."
2. **Phosphene needs control signals, not clean audio.** Perceptual separation (clean isolated tracks) is the hard, often-unsolvable target. Visuals need only a *per-voice time-varying envelope* correlated with that voice's activity — a far weaker requirement, and weaker requirements are where "works on everything" lives.

Together: **a universal decomposition with a guaranteed floor and an opportunistic ceiling.** The floor always returns something drivable on any file in any genre; the ceiling returns clean stems when content cooperates. Breadth comes from a content-adaptive *router*, not one heroic model.

This is already Phosphene's central design rule (Audio Data Hierarchy): continuous energy/spectral = primary driver, stems = supplementary (Layers 1–3 default, Layer 5 stems supplementary). The proposal is to **widen "supplementary" from a 4-slot pop array into a decomposition ladder, and keep the spectral floor load-bearing.**

---

## 1. The format layer is mostly already solved

Decoding MP3/M4A/FLAC → 44.1 kHz float PCM is done (LF.1–LF.6 local-file pipeline, `AVAudioFile` + magic-byte sniffing). Two notes:

- **Lossy formats pre-damage the separator's evidence.** MP3/AAC discard psychoacoustically-masked partials and add quantization noise / pre-echo — exactly the spectral cues separation relies on. A model trained on clean WAV degrades on 128 kbps MP3. Mitigations by cost: (a) **codec-augment training** (mix MP3/AAC artifacts into the training set — cheap, standard, high ROI); (b) a light restoration/bandwidth-extension front-end; (c) operate on robust features. (a) is the one to keep.
- **True decode gaps are only Ogg Vorbis and Opus-in-Ogg** (Core Audio decodes raw Opus packets but not the Ogg container, and Vorbis not at all) → ffmpeg/libsndfile fallback. FLAC decodes natively but Apple's AudioFile path does a slow full-file scan on first read — immaterial for 30 s clips.

**Conclusion:** "broad formats" is roughly a day of work plus the codec-robustness nuance. It is *not* where the difficulty is. The difficulty is multi-instrument + classical.

---

## 2. The decomposition ladder

Six tiers, universal-but-coarse → specific-but-fragile. Maturity labels separate the deployable from the speculative.

| Tier | Technique | What it gives | Genre reach | On-device cost | Maturity |
|---|---|---|---|---|---|
| **0 — Universal floor** | Spectral/MIR (have it), **HPSS**, **NMF**, **multi-pitch salience** (deep-salience / `basic-pitch`), **instrument-activity tagging** (PANNs/PaSST), **CASA grouping cues** | Always-available drivable envelopes / salience fields; "which instrument, how strong, when" | **All** audio, no training | Trivial–low | Production-ready (mostly classical DSP) |
| **1 — Supervised stems** | **HT-Demucs v4** (4-stem; 6-stem +guitar+piano), SCNet, BS-RoFormer | Clean named stems | Pop/rock/electronic sweet spot; fails on classical | Med (see §4 for runtime) | Deployable |
| **2 — Conditioned / query** | **Banquet** (label query), **AudioSep/LASS** (text query), one-shot audio query | Arbitrary instrument by description | Any, incl. classical instruments | Med | Research→early-deployable |
| **3 — Knowledge injection** | **Score-informed** separation; **metadata→query** generation | Strong-prior separation where blind fails | Classical especially | Med + alignment | Research, classical-proven |
| **4 — Generative / self-trained** | **Diffusion/score-based** (MSDM); **MixIT** (unsupervised); test-time adaptation; neural-codec domain | Arbitrary source count; hallucinated detail; trains without isolated stems | Any | High (not real-time today) | Frontier |
| **5 — Look before you compute** | Read **object/immersive** (Atmos/MPEG-H), multichannel, shipped stems from the container | Free separation | Subset of content | Negligible | Available where present |

### Tier 0 — the universal floor (the safety net)

The cues humans actually use, none requiring ML or training:

- **HPSS** (spectrogram median filtering): harmonic (sustained pitched — strings/winds/voice/pads) vs percussive (transients — drums, attacks, bow-strokes). Works identically on techno and a symphony.
- **NMF**: factor the spectrogram into K additive components; unnamed but often note/instrument-aligned. Deterministic, tiny.
- **Multi-pitch salience / multi-f0**: a pitch×time energy field — for classical this *is* a rich driver, no separation needed.
- **Instrument-activity tagging** with time resolution: classification, not separation, so it survives dense orchestral overlap; yields a labeled per-frame activity vector.
- **CASA grouping cues** (Bregman): common f0/harmonicity, common onset/offset, **common modulation** (a violin's vibrato AM/FMs all its partials together — a powerful, underused handle), spatial position. Compute "stream salience" with no ML. Especially apt for classical.

### Tier 1 — supervised stems (pop/rock)

HT-Demucs v4 (MIT, public weights) is the best open option; 6-stem variant adds guitar+piano (piano weak). BS-RoFormer/Mel-RoFormer sit ~2–3 dB SDR higher but have no maintained Apple port and license ambiguity on the top weights — not worth it for visualization. **Runtime/effort caveats: see §4 — this is a deliberate port, not a drop-in.**

### Tier 2 — conditioned / query (dissolves the taxonomy)

- **Banquet** (`query-bandit`, ISMIR'24): label-conditioned single decoder, ~25 M params, stem-agnostic; approaches 6-stem Demucs, beats it on guitar/piano, extracts rare stems (reeds, organ).
- **AudioSep / LASS** ("Separate Anything You Describe"): natural-language query via CLAP embeddings, zero-shot instrument separation. "Separate the clarinet," literally.
- **One-shot audio query**: example clip of the target timbre → separate by similarity.

### Tier 3 — knowledge injection (the classical key)

- **Score-informed separation** (Ewert/Müller lineage; EUSIPCO 2025 targets synthetic→real classical): align score to audio, use "which instrument plays which note when" as a strong prior. Dramatically beats blind separation on classical. Scores often retrievable (IMSLP) from metadata.
- **Metadata→query generation**: tags say "Beethoven String Quartet No. 14" → auto-issue queries {violin I, violin II, viola, cello} to the Tier-2 separator. The file's own metadata becomes the conditioning. Cross-angle synthesis: decode → read tags → generate queries → conditioned separation.

### Tier 4 — generative / self-trained frontier ("what might be possible")

- **Diffusion / score-based separation** (MSDM): generative prior over sources, separate by posterior sampling. Arbitrary source count, *hallucinates* plausible detail where masking fails, *inpaints* spectral content destroyed by overlap or lossy coding. Today Slakh-scale, not real-time.
- **Unsupervised MixIT**: train separation from *unlabeled* mixtures (mix two mixtures, separate, remix to match) — no ground-truth stems. Directly attacks the classical data wall (unlimited unlabeled classical, ~zero isolated orchestral stems). Caveats: over-separates, cost scales with source count.
- **Test-time adaptation**: offline analysis with the whole track → few-shot adapt to *this* recording/hall before committing the plan.
- **Neural-codec / foundation-rep domain**: EnCodec/DAC tokens or MERT embeddings as a more-separable space; cluster into streams.

### Tier 5 — look before you compute

Object/immersive audio (Atmos/MPEG-H) ships instruments/groups as separate objects/beds; multichannel FLAC can carry near-isolated sections; some releases ship stems. Check whether the file is *already* separable from its structure before ML-separating. Increasingly the cleanest "separation" is a demux.

---

## 3. Classical, specifically

**Why pop separators fail:** (1) taxonomy mismatch — no drums/bass/vocals; a 4-head model shoves the orchestra into "other" and mislabels strings as "vocals"; (2) data scarcity — almost no isolated-instrument classical multitracks to train on; (3) timbral confusability — violin/viola, flute/oboe share spectral envelopes; (4) acoustic mismatch — shared room, reverb, bleed vs dry studio multitrack.

**Honest yardstick — the Cadenza classical task:** the baseline runs **eight separate per-instrument models**, trains on *synthesized* ensembles, evaluates on *real* anechoic recordings (URMP/Bach10), scores HAAQI ≈ 0.5 (mediocre), and *still can't split Violin I from Violin II*. That is today's ceiling.

**The layered answer:**

1. **Detect** classical (cheap tagging: instrumentation, percussion-absence, spectral profile).
2. **Floor (Tier 0):** spatial cues pay off here — orchestras are physically laid out in stereo (first violins left, celli right), so direction-of-arrival separation *works* where it can't on mono-panned pop — plus HPSS, multi-pitch salience, activity detection. Always produces good drivers.
3. **Ceiling (opportunistic):** Tier-3 score/metadata queries when score/tags exist; Tier-2 language queries otherwise.
4. **Frontier:** Tier-4 generative/MixIT as it matures.
5. **Expectation-setting:** you will *not* get clean isolated orchestral stems. You *will* get reliable, musically-meaningful per-section/per-salience control signals — which is all Phosphene needs (Reframe 2).

---

## 4. HT-Demucs status — corrected history (read before recommending a stem upgrade)

The earlier breezy "HT-Demucs-6s via MLX, sub-second, just do it" understated real frictions documented in this repo. Corrected:

- **Original objection (real at the time):** HTDemucs could not be converted to CoreML — `view_as_complex` (complex tensors in its STFT/iSTFT) + dynamic-shape `int`-cast ops; both `torch.jit.trace → coremltools` and `torch.onnx.export → CoreML` failed. Open-Unmix's LSTM converted cleanly → Open-Unmix HQ shipped. (Archived plan Increment 3.x; `DECISIONS.md` D-009; `HISTORICAL_DEAD_ENDS.md` #12.)
- **That objection is formally retired.** CoreML was removed entirely (D-009 / Phase 3.7); everything is hand-built MPSGraph now (Open-Unmix *and* Beat This!). Dead-end #12 graveyarded 2026-05-13: *"Not actively blocking … re-test if a future session has reason to revisit HTDemucs."* The `BUG-010` audit prompt already names **Demucs HT v4 the realistic candidate**, says the **Hybrid Transformer is implementable in MPSGraph**, and that the **weight-conversion pattern is identical to the Beat This! port**.
- **What actually stands in its place — a cost + a gate, not a blocker:**
  - **Cost:** adopting HT-Demucs means either a **full hand-port of the Hybrid Transformer to MPSGraph** (Beat-This-scale effort) *or* taking on **MLX as a second ML runtime** alongside MPSGraph. MLX is not free — it's a new inference path and dependency, in tension with the single-runtime / minimize-dependencies posture (D-009's spirit). Frame it as a deliberate port.
  - **Gate:** the swap was conditioned on the **BUG-010 quality audit** of whether Open-Unmix is the bottleneck (drums-SDR thresholds: ≥6 keep / 4–6 marginal / <4 replace; Open-Unmix published baseline ~5.85 dB drums). **No completed resolution to BUG-010 is found in the tracker** — so "is replacement even justified" appears unrun, not decided.
  - **Window mismatch:** current `StemSeparator` is a fixed 10 s MPSGraph window with no tiling; HT-Demucs segments at ~7.8 s with overlap-add — a real pipeline change, not just a weight swap.

**Recommendation for the stem tier:** run BUG-010 first (cheap, gates everything). Only if it shows Open-Unmix is the bottleneck does the HT-Demucs port/MLX-dependency decision become live — and even then, much of the "multi-instrument incl. classical" win comes from Tiers 0/2/3, *not* from a bigger pop-stem model.

---

## 5. The unifying architecture

A content-adaptive router (mixture-of-experts):

1. **Decode** (native-first + ffmpeg fallback) → 44.1 kHz float PCM; record codec provenance.
2. **Probe** — cheap audio-tagging → genre / instrumentation / recording-type / source-count + confidence; check container for object/multichannel separability (Tier 5).
3. **Route** — pop/rock/electronic → Tier 1 stems (+ Tier 0 always); classical/orchestral/acoustic → Tier 0 spatial+salience+activity, + Tier 3 when score/tags allow; unknown/sparse → Tier 2 query.
4. **Fuse** — every path emits the **same interface**: a set of named-or-anonymous streams, each a time-varying energy/salience envelope + confidence. Visuals consume *that*, never raw stems. Low confidence → weight toward the Tier-0 floor.
5. **Exploit the offline budget** — pre-analysis has no real-time constraint, so run several experts and ensemble.

**The load-bearing commitment is a stable "drivable stream" interface** between decomposition and presets, so the back-end can swap/upgrade experts (Open-Unmix → HT-Demucs → query → generative) without touching a shader. That contract + the ladder + the router + the floor is what solves it "for a broad range" — no single model has to.

This generalizes the existing `StemFeatures` contract: today it is 4 fixed channels; the proposal is N named-or-anonymous streams + per-stream confidence, with the existing spectral primitives (`bassRel`/`bassDev`/…) as the guaranteed floor consumers fall back to.

---

## 6. Where I'd land it

- **Pragmatic (shippable):** native-first decode (+ codec-augmented model); Tier-1 stems for pop *only after* BUG-010 justifies it; a non-pop **detector** that routes to the existing spectral floor + adds HPSS and multi-pitch salience (Tier 0). That alone makes the system *not fail* on anything and adds instrument channels for pop — ~80% of the perceived win, most of it in Tier 0 DSP you can build without a new ML runtime.
- **Visionary (frontier):** Tier-2 language/label queries (AudioSep/Banquet) for arbitrary-instrument reactivity; Tier-3 metadata→score-informed for classical; watch Tier-4 (diffusion/MixIT) for the eventual single-model universal separator.

**Through-line:** you already decided continuous energy is primary and stems are supplementary. "Solving multi-instrument including classical" isn't a bigger stem model — it's promoting *supplementary* from a 4-slot pop array into a content-adaptive ladder that always degrades to the spectral floor. Breadth → floor; richness → ladder; taxonomy problem → queries; classical → knowledge-injection + spatial cues; clean stems → a happy special case, not the load-bearing assumption.

---

## 7. Open questions / risks for Matt

- **BUG-010 is the real first move** and appears unrun. Without it, any stem-model swap is unjustified spend.
- **New-runtime decision (MLX) vs hand-port (MPSGraph)** is a genuine architecture fork with dependency-policy weight (D-009). Neither is free; both deserve an explicit decision, not a default.
- **Tier 0 is underused and cheap.** HPSS + multi-pitch salience + activity tagging are mostly classical-DSP/Accelerate work — high ROI, no new ML dependency, and they're what make classical "work." Strong candidate for the first increment.
- **The "drivable stream" interface is the keystone.** Get the contract right (N streams + confidence + the spectral floor) before adopting any new model, or every model swap touches presets.
- **Manual/musical validation still gates anything user-visible** (per CLAUDE.md): stem-visual coupling and classical behavior need listening at volume, not just SDR.

---

## Sources

- Separate Anything You Describe (AudioSep / LASS) — https://arxiv.org/abs/2308.05037 · https://github.com/Audio-AGI/AudioSep
- Banquet — stem-agnostic query-based separation (ISMIR'24) — https://arxiv.org/abs/2406.18747 · https://github.com/kwatcharasupat/query-bandit
- Multi-Source Diffusion Models (generation + separation) — https://arxiv.org/abs/2302.02257
- Unsupervised Sound Separation via Mixture Invariant Training (MixIT) — https://arxiv.org/abs/2006.12701
- Score-informed Source Separation: synthetic-to-real for classical (EUSIPCO 2025) — https://arxiv.org/abs/2503.07352
- Demucs / HT-Demucs — https://github.com/facebookresearch/demucs · Apple-Silicon port: https://github.com/ssmall256/demucs-mlx
- BS-RoFormer — https://arxiv.org/abs/2309.02612 · MoisesDB (beyond 4 stems) — https://arxiv.org/pdf/2307.15913
- Cadenza Challenge — Rebalancing Classical (baseline + data) — https://cadenzachallenge.org/docs/cadenza2/Rebalancing%20Classical/rebalance_baseline

**Internal references:** `DECISIONS.md` D-009/D-010 · `HISTORICAL_DEAD_ENDS.md` #12/#13 · `prompts/BUG-010-prompt.md` · `docs/ENGINEERING_PLAN_HISTORY.md` (10 s window truncation) · LF.1–LF.6 (`ARCHITECTURE.md` §Audio Capture / §Session Preparation) · Audio Data Hierarchy (`CLAUDE.md`).
