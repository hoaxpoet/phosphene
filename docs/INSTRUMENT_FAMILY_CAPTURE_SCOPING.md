# Instrument-Family Capture — Scoping Proposal

**Status:** Scoped + feasibility-spiked 2026-06-29 (D-177). **GREENLIT — in build.** IFC.1 (model + license) ✅ and IFC.2 (MPSGraph port + numerical parity on the two spike clips) ✅ 2026-06-30 — see §12. Next is IFC.3 (per-family mapping + normalization). This doc is self-contained — a fresh session should be able to execute from it.

---

## 1. The problem

Phosphene drives visuals from **4-stem separation** (Open-Unmix → vocals / drums / bass / other) + **frequency-register bands** (3-band + 6-band energy). On orchestral / acoustic-ensemble music this fails: all pitched content collapses into **"other,"** so the engine cannot tell which **instrument family** (strings / brass / woodwinds / percussion) is playing. Register-bands are a weak proxy — a low note is a low note whether it's a cello or a tuba.

This caps the musicality of any preset that wants to respond to the *orchestra*, not just the spectrum. It is the load-bearing constraint on **Ricercar** ("the orchestra painting itself," D-176 — each section a painterly identity), and Matt is explicitly **holding** Ricercar's quality bar on it. But the capability is **reusable** — instrument-family awareness would benefit any acoustic/orchestral preset.

## 2. The reframe — recognition, not separation

Do **not** try to *separate* (isolate each family's audio). That is unsolved for orchestra: a 2025 study trained dedicated family separators and got **0.0–4.5 dB SDR** (poor-to-unusable); the authors state "MSS for classical music is an unsolved problem" ([arXiv 2505.17823](https://arxiv.org/html/2505.17823v1)).

Instead **recognize** — detect which families are *active*, moment to moment. This is **multi-label instrument activity detection**, a tractable supervised problem with pretrained models (e.g. PANNs trained on AudioSet, [arXiv 1912.10211](https://arxiv.org/pdf/1912.10211)). You don't need clean audio per family; you need a per-family **activity signal** over time. That is exactly what drives a per-section visual.

## 3. The evidence (spike, 2026-06-29)

Ran **PANNs CNN14** (AudioSet-pretrained, 527 classes) on two complementary public-domain clips, 2 s window / 1 s hop, per-family activity from the relevant AudioSet classes.

**Clip A — Beethoven Symphony No. 5, i. (string-dominant).** Top tags: Music 0.73, **Violin 0.61, Bowed string 0.34, Cello 0.30, Orchestra 0.26**, Brass 0.06, French horn 0.04. Per-family: strings strong + dynamic (peak 0.74, range 0.71, tracks the music); **brass correctly time-localized** — spikes to 0.19 at t≈24 s, the famous horn transition — but low absolute level; woodwinds/timpani faint (masked by dense strings).

**Clip B — Beethoven Wind Octet Op. 103 (winds + horns, NO strings).** Top tags: **Brass 0.58, Trumpet 0.37, French horn 0.21, Trombone 0.17, Clarinet 0.16, Flute 0.13**, strings 0.026. And it **discriminates within the ensemble**:

| moment | brass | woodwinds | reality |
|---|---|---|---|
| t≈6 s | **0.64** | 0.04 | horns leading |
| t≈11 s | 0.06 | **0.53** | clarinets/oboes leading |
| t≈28 s | **0.80** | 0.02 | brass tutti |
| t≈38 s | 0.10 | **0.39** | woodwinds leading |

Brass peak 0.80, woodwinds 0.53 — both highly dynamic, trading the lead correctly; timpani ~0 (none present — correct absence).

**Verdict:** family-level instrument capture **works** — the model tracks whichever families are prominent, discriminates between them moment-to-moment, and reports absence. A categorical leap over 4-stem (→"other") or register-proxy. The "everything is other" problem is gone.

**Honest ceilings (the same evidence):**
- **Family-level, not individual** — over-calls specific instruments (tagged trumpet/trombone on a horn octet). Trust strings / brass / woodwinds / percussion; not oboe-vs-clarinet.
- **Cross-family confusion** on sustained timbres (a legato wind passage briefly read as "strings," Clip B t≈12). Transient — smoothing + per-family deviation handles it.
- **Buried secondary families** under a dominant one stay approximate (drive off each family's *own* deviation to surface them — the D-026 trick).

## 4. Proposed approach

On-device audio-tagging net → per-frame instrument-family activity → **deviation-normalized per-family signals** in the feature pipeline, consumed by presets as section drivers.

- **Where it runs:** on the **30 s preview clip** as pre-analysis (the Beat This! / Open-Unmix pattern), so there is **no live-latency constraint** on the primary signal. Optional live refinement via the Core Audio tap is a later, harder extension.
- **Normalization:** raw probabilities are dominated by the loudest family; emit each family's **deviation from its own running mean** (mirrors `*_energy_dev`, D-026) so even a faint-but-present entry (Clip A's brass at t≈24) becomes a clean trigger.
- **Taxonomy:** map AudioSet instrument classes → families. Start with **strings / brass / woodwinds / percussion** (+ a low/bass split if needed to feed Ricercar's five register-archetype sections).

## 5. Architecture fit

- **Supervised net via MPSGraph** — the established on-device ML path (D-009 prohibits only *CoreML*; Beat This! and Open-Unmix already run on MPSGraph). Reuses the existing log-mel front-end + MPSGraph infrastructure.
- **Portability is low-risk for a CNN** — CNN14 is conv2d / batchnorm / log-mel / global-pool / linear, the same op family already ported. Transformer taggers (AST/PaSST) are higher-accuracy but need attention-op coverage — verify before choosing.

## 6. Candidate models (selection is an early task)

| Model | ~Params | Accuracy | License (verify) | Notes |
|---|---|---|---|---|
| **PANNs CNN14** | ~80 M | mAP 0.43 (spiked here) | Apache-2.0 repo (weights TBV) | proven in the spike; largest |
| **PANNs MobileNetV1** | ~5 M | mAP ~0.39 | same repo | much lighter; likely the production pick |
| **YAMNet** (Google) | ~3.7 M | AudioSet | Apache-2.0 (clean) | MobileNet, cleanest license, lighter |
| **AST / PaSST** | ~85 M | SOTA | MIT-ish | best accuracy; transformer ops to verify |

Decision drivers: **license for commercial shipping**, perf/size budget (Tier-1 M1), MPSGraph op coverage. The spike used CNN14 for accuracy; production likely wants a **MobileNet-class** net (MobileNetV1-PANN or YAMNet).

## 7. Work breakdown (phased — each its own increment)

1. **Model + license selection.** Pick the net (§6); **clear weight licensing** for a commercial product (PANNs/YAMNet weights; AudioSet ontology is CC-BY). Gate before any porting.
2. **MPSGraph port + front-end parity.** Convert the net; reproduce the log-mel front-end; **numerically validate** against the PyTorch reference on the spike clips (the contact-sheet of this increment is a per-family activity match).
3. **Per-family activity + normalization.** AudioSet-class → family mapping; temporal smoothing; per-family deviation normalization (D-026 pattern). Emit a small per-family activity vector.
4. **Pipeline integration.** Surface the per-family signals into `FeatureVector` / `StemFeatures` (GPU contract update); compute during pre-analysis on the preview clip; (optional) live tap refinement.
5. **Validation.** Orchestral fixtures (the BWV 565 target + varied clips spanning string / brass / wind / tutti); a diagnostic surface (per-family activity logging, mirroring the spike) — the closeout cites per-family firing evidence.
6. **Preset consumption.** Wire Ricercar's section drivers to per-family activity (the drive-layer swap — the visual engine is already agnostic to the source); document the reuse path for other presets.

## 8. Effort & what it unlocks

- **Effort:** ~**Beat This!-scale** ML increment — multiple sessions. The model port + numerical validation is the bulk; integration follows the established stem/beat pre-analysis pattern.
- **Unlocks:** Ricercar's *real* per-section capture (resolves Matt's hold); reusable instrument-aware musicality for any acoustic/orchestral preset; a new feature axis (instrument-family activity) in the pipeline.

## 9. Risks / open questions for the fresh session

- **Quality ceiling is inherent** (§3): family-level only, cross-family confusion on sustained timbres, buried families approximate. The consuming preset must be forgiving (evocative, not a transcription) — design around it.
- **Weight licensing** for commercial shipping — must clear in step 1, could force a model change or a re-train on a permissively-licensed dataset.
- **Perf budget** — CNN14 is heavy; a MobileNet/YAMNet-class net is the likely pick; confirm Tier-1 (M1) cost on the preview clip.
- **MPSGraph op coverage** — low risk for CNN, verify for transformers.
- **Streaming = preview-only** primary signal (30 s); live refinement is optional and harder (tap latency + windowing).
- **Taxonomy granularity** — 4 families, or 5 to match Ricercar's sections, or finer? (finer is less reliable, §3.)

## 10. Spike reproduction (for the fresh session)

The 2026-06-29 spike is reproducible:
- `pip install panns_inference` (pulls torchlibrosa/librosa; `torch` already in `tools/.venv`). **Note:** `panns_inference` auto-downloads weights via `wget` (absent on macOS) — manually `curl` the labels CSV + checkpoint into `~/panns_data/` (`class_labels_indices.csv` from the `qiuqiangkong/audioset_tagging_cnn` repo; `Cnn14_mAP=0.431.pth` from zenodo record 3987831).
- Script: `/tmp/panns_spike.py` (clipwise top-tags + 2 s/1 s per-family sweep). Clips: Sym5 i. + Wind Octet Op. 103 (public-domain, archive.org/Musopen — see the URLs in the session log).
- These artifacts are **dev-only, not committed** to the repo.

## 11. References

- [Source Separation of Small Classical Ensembles: Challenges and Opportunities (arXiv 2505.17823)](https://arxiv.org/html/2505.17823v1) — separation is unsolved for orchestra.
- [PANNs: Large-Scale Pretrained Audio Neural Networks (arXiv 1912.10211)](https://arxiv.org/pdf/1912.10211) — the recognition approach.
- `docs/presets/RICERCAR_DESIGN.md` §CONCEPT + §6 (the consuming preset + the no-instrument-separation constraint). `DECISIONS.md` D-177 (this finding), D-009 (no-CoreML / MPSGraph), D-026 (deviation primitives).

## 12. Build status (the §7 work breakdown, as executed)

| # | Increment | Status |
|---|---|---|
| 1 | Model + license | ✅ IFC.1 (2026-06-30) — PANNs MobileNetV1; weights CC-BY-4.0 (Zenodo 3987831), code MIT (reimplemented), AudioSet CC-BY |
| 2 | MPSGraph port + front-end parity | ✅ IFC.2 (2026-06-30) — numerical parity on both spike clips |
| 3 | Per-family activity + normalization | ✅ IFC.3 (2026-06-30) — `InstrumentFamilyActivity` + taxonomy + D-026 tracker |
| 4 | Pipeline integration (+ attribution notice) | ✅ IFC.4 (2026-06-30) — `InstrumentFamilyAnalyzer` runs in `analyzePreview`; series on `CachedTrackData`; StemFeatures floats 48–55 + Metal mirror + CSV; live sample-by-position; CREDITS PANNs section |
| 5 | Validation | ✅ IFC.5 (2026-06-30) — `InstrumentFamilyDumper` + production-path validation on real audio + full-orchestra corpus (strings-dominant / brass / brass↔woodwind trade), all firing correctly (see §13) |
| 6 | Preset consumption (Ricercar drive-layer swap) | pending |

**IFC.2 result (numerical parity vs the PyTorch reference, both spike clips):** front-end log-mel **1.5e-5 dB**, network probs **1.7e-7** (logits 4.8e-6), end-to-end **1.4e-7** with the top class matching, per-family activity **4.2e-7** across 6 musical windows. The model reproduces the spike's discrimination — sym5 strings 0.51–0.57; octet@8s woodwind-led (0.397 > 0.113), @14s/@17s brass tutti (0.55/0.64), strings ≈ 0.04 (correct near-absence).

**Durable build learnings (IFC.2):**
- **Export the front-end as data, don't reimplement librosa.** The PANNs checkpoint already contains the torchlibrosa STFT basis (`spectrogram_extractor.stft.conv_real/imag.weight`, the Hann-windowed DFT matrices) and the librosa mel filterbank (`logmel_extractor.melW`). Shipping these as `.bin` tensors makes the entire Swift front-end exact matmuls (reflect-pad → frame → `conv_real/imag` matmul → power → `melW` matmul → `10·log10`), which killed the single biggest parity risk (FFT normalization / mel-filterbank reproduction). Proven in Python first (max abs diff 1.9e-6 vs the model's internal log-mel) before a line of Swift.
- **The PANNs MobileNetV1 variant downsamples via AvgPool, not strided conv** — every conv is stride-1 pad-1 (3×3) or 1×1; the stride lives in an `AvgPool2d(stride)` between the depthwise conv and the pointwise conv. Get this order right or the shapes drift.
- **Grouped (depthwise) convolution is the only op beyond the existing CNN ports** and it works in MPSGraph via `MPSGraphConvolution2DOpDescriptor.groups` with HWIO weights `[kH,kW,1,inC]` (PyTorch `[inC,1,3,3]` rearranged). No op-coverage gap.
- **Fix T = 201 (the 2 s inference window)** so the graph has a fixed input shape; this is the natural per-family unit and avoids dynamic-shape pooling/reduction headaches.
- Reproduce: `tools/.venv/bin/python tools/convert_panns_weights.py` (weights → `Sources/ML/Weights/panns_mobilenetv1/`) and `tools/panns_reference.py` (reference + test fixtures; needs `~/panns_data/MobileNetV1_mAP=0.389.pth` + the two clips, dev-only/uncommitted).

**IFC.3 — the orchestral family taxonomy (AudioSet 527-class → 4 families).** Single source of truth: `tools/panns_reference.py` FAMILIES ↔ `InstrumentFamily.audioSetClasses` (Swift), cross-checked in tests. The spike's keyword set under-covered woodwinds (it matched only Flute + a mis-spelled "Wind instrument, woodwind"); the corrected set adds the catch-all + saxophone.

| family | AudioSet indices | notes |
|---|---|---|
| strings | 189–194, 199 | bowed-string core + harp |
| brass | 185–188 | Brass / French horn / Trumpet / Trombone — **excludes** vehicle/air/train/foghorn (308/318/331/401) |
| woodwinds | 195–198 | `195 Wind instrument, woodwind instrument` catch-all (oboe/bassoon have no dedicated class) + Flute/Saxophone/Clarinet |
| percussion | 161,164,168,169,171,179–182 | orchestral set anchored on Timpani (169); Percussion/Drum/Bass-drum/Cymbal + the mallet family |

- **Normalization mirrors `BandDeviationTracker` (D-026), not a new design** — per-family smoothing EMA (decay 0.5, ~1.4 windows at the 1 s hop) then a slower running-mean pivot (decay 0.9, ~10 s) with `rel = (value − avg)·gain`, `dev = max(0, rel)`, seed-from-first-non-zero, `reset()` on track change. `devGain` is a placeholder (2.0, the band convention) to be tuned against the real per-family p99 in IFC.6 ([[project_deviation_primitive_real_range]]).
- **5-section split deferred to IFC.6** — Ricercar's five register-archetype sections (e.g. low vs high strings) is a product-shaping choice best decided alongside the preset, not baked into the base taxonomy.

**IFC.4 — pipeline integration (the build, as executed).**

- **The one design decision — what the live frame reads (resolved: option b, cached time-series sampled by playback position).** The preview activity is Layer 5a (available frame 1, NOT time-aligned to live playback). A per-clip *snapshot* (option a) would collapse the whole 30 s into one set of 4 values and destroy the section-to-section trading that is the feature's entire purpose (Clip B's brass@6s vs woodwinds@11s) — so it was rejected. The live frame reads the **cached per-window series sampled by `mir.elapsedSeconds`** (`InstrumentFamilyActivity.sample`, nearest-window-clamped at the 1 s hop). **Alignment caveat (documented, deferred to IFC.6):** the 30 s preview may not be the section currently playing, and tracks run longer than the preview — past the series end the sample clamps to the last window. A small phase error reads as a small offset, not a wrong family. Empty series (non-orchestral / cache-miss / cleared on track change) → `.zero`, the no-activity fallback. Option c (live PANNs on the Core Audio tap, Layer 5b) stays out of scope (harder; optional later).
- **GPU contract.** 4 families × {smoothed `Activity`, positive-deviation `ActivityDev`} = 8 floats fit the existing 256-byte StemFeatures padding (reclaimed `_sfPad6`…`_sfPad13`, floats 48–55; 9 pad floats remain) — **no resize.** `@frozen` Swift struct + both Metal mirrors (`PresetLoader+Preamble`, `Common.metal`) + the ARCHITECTURE layout block updated together; `CommonLayoutTest` still locks 256 bytes. Fields are renderer-transient (excluded from Codable, like the FFO aurora floats). Expose `*ActivityDev` as the trigger, never the absolutes (Failed Approach #31).
- **Where it runs.** `InstrumentFamilyAnalyzer` (PANNs-backed, injected like `BeatGridAnalyzing`) runs inside `analyzePreview` as Step 8 with a `panns` TIMING stage; the series is stored on `CachedTrackData.instrumentFamilySeries` (in-memory only — **not** persisted to `PersistentStemCache` this increment; disk-cache reload yields an empty series → clean zero fallback. Disk persistence is a documented IFC.6-or-later follow-up). Wired on both the streaming (`SessionPreparer`) and local-file (`runLocalFilePreparation`) paths.
- **Live write/clear (anti-leak, §What NOT To Do).** `resetStemPipeline` clears the series + zeroes the pipeline family activity **unconditionally** on every track-change path, then the cache-hit branch reinstalls. `MIRPipeline` can't hold the series (DSP can't import ML), so the per-frame sampling lives in the app's `processAnalysisFrame` using `mir.elapsedSeconds`, writing via `RenderPipeline.setInstrumentFamilyActivity` (preserved across the ~5 s live `setStemFeatures` pushes, same contract as `cachedBassProportion`).
- **`devGain` stays 2.0** (the placeholder) — tuning against the real per-family p99 is IFC.6, not this increment.

## 13. IFC.5 — validation (partial: pipeline ✅, orchestral corpus pending)

**Diagnostic surface (✅).** `InstrumentFamilyDumper` (`executableTarget`, retained-diagnostic) decodes a clip → runs the **production** `InstrumentFamilyAnalyzer` (44.1 kHz decode → resample 44.1→32 kHz → 2 s/1 s windows → PANNs → D-026 tracker) → prints the per-window strings/brass/woodwinds/percussion activity table + leader-per-window, `--out` writes JSON. This exercises the **resample path IFC.2's parity did not cover** (parity fed 32 kHz directly). Run: `swift run --package-path PhospheneEngine InstrumentFamilyDumper --audio <clip> [--start s --duration s --out j.json]`.

**Production-path validation on real audio (✅, 2026-06-30).** Ran the dumper on the committed tempo fixtures (real recordings). Firing is musically correct:
- **`so_what.m4a` (Miles Davis — muted trumpet lead + alto sax + ride/drums):** **brass leads** most windows (peak smoothed 0.42 / dev 0.50 at t≈9 s), **percussion** surfaces at the ride/drum-fill moments (dev 0.31–0.32), woodwinds track brass lower (the sax under the trumpet), **strings ≈ 0** (correct — no strings in the quintet). Real acoustic **brass discrimination** confirmed on a real recording — the capability generalizes beyond the two spike clips.
- **`money.m4a` / `love_rehab.m4a` (electric / electronic):** all orchestral families near-zero — **correct absence-reporting** (PANNs does not false-fire strings/brass on guitars/synths).
- **`pyramid_song.m4a` (subtle piano/strings):** near-zero — matches the documented "buried families stay approximate" ceiling (§3).
- **Observation → IFC.6 note:** on near-silent-family material the leader-picker flaps on 0.00–0.01 dev noise; a consuming preset must gate on a small `dev` floor (couples to the `devGain` p99 tuning).

**Orchestral corpus (✅, 2026-06-30 — Matt authorized re-fetching public-domain clips).** Ran the production dumper end-to-end on public-domain orchestral/ensemble recordings (dev-only, uncommitted like the spike clips; **re-fetchable URLs below** so a cleared `/tmp` never re-blocks). Firing matches the spike's promised discrimination:
- **Strings-dominant — Beethoven Sym 5 i.** (Musopen): **strings lead** the string theme (peak smoothed 0.30 / dev 0.48 at t≈9 s), brass/woodwinds/percussion ≈ 0. `https://archive.org/download/LvB_5_1/lvb-sym-5-1.mp3`
- **Wind ensemble, brass↔woodwind TRADE — Mozart "Gran Partita" K.361** (13 winds, no strings): the money case. **Woodwinds lead** their entries via deviation (t=11–14 dev **0.38–0.40**; t=22–24 dev 0.14–0.18), **brass leads** the horn tuttis (t=16 dev 0.15; t=27 dev **0.40**; t=36–37 dev 0.10–0.23) — the trade the spike documented (octet brass@6s ↔ woodwinds@11s). Note the brass **absolute** saturates high (0.4–0.75) across the whole ensemble (the "over-calls specific instruments" ceiling §3) — the **deviation** column is what correctly surfaces the moment-to-moment lead, live proof of why the design drives off `dev` not absolutes (Failed Approach #31). `https://archive.org/download/mozartmusicw3412/07_Serenade%20%27Gran%20Partita%27.mp3`
- **Documented ceiling — Mozart Clarinet Concerto K.622 Adagio** (solo clarinet OVER strings): strings correctly lead (the string orchestra, 0.34/0.54) and the sustained solo clarinet stays weak — the "sustained wind over strings reads as strings" cross-family confusion (§3). A clean woodwind-LEAD needs a winds-only texture (the Gran Partita above), not a concerto with string accompaniment. `https://archive.org/download/clarinet-concerto/02%20Adagio.mp3`

**Verdict:** the production path reproduces the spike's family discrimination on real orchestral audio — strings-dominant, brass-led, and the brass↔woodwind trade all fire correctly through the D-026 deviation. IFC.5 done. The consuming preset (IFC.6) must gate the leader on a small `dev` floor (the near-zero-material leader-flap) and lives with the two ceilings (buried/sustained families approximate; drive off deviation, forgiving/evocative not transcription).
</content>
