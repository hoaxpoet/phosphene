# DSP.2 — BeatNet architecture audit

**Status:** Session 1 deliverable. Reference for Sessions 2–7.
**Source of truth:** github.com/mjhydri/BeatNet @ `main`, commit pushed 2026-04-13.
**Files inspected:** `src/BeatNet/BeatNet.py`, `src/BeatNet/model.py`, `src/BeatNet/log_spect.py`, `src/BeatNet/models/model_1_weights.pt`.

This document supersedes the prose architecture description in
`docs/ENGINEERING_PLAN.md` Increment DSP.2 step 4 where they disagree
(see "Spec corrections" at the end).

---

## 1. Pipeline overview

```
audio (any sr, any channel count)
  └─ resample → mono 22050 Hz                    [Phosphene: vDSP_resamplef]
  └─ frame: win 1411 samp (~64 ms), hop 441 samp (~20 ms, 50 fps)
  └─ STFT: zero-pad to 2048-pt, magnitude
  └─ log-frequency filterbank: 24 bands/octave,
       fmin 30 Hz, fmax 17000 Hz, norm_filters=True   → 136 filters
  └─ logarithmic compression: log(1 + spec)
  └─ positive first-order temporal difference
       (concatenated → doubles feature dim)            → 272-dim per frame
  └─ BDA CRNN: Conv1d → Linear0 → LSTM (2 layer, h=150) → Linear → softmax
  └─ per-frame 3-class probabilities [beat, downbeat, no_beat]
  └─ particle filter (Stage 3, Session 5–6) over (period, phase)
  └─ outputs: BPM, beatPhase01, downbeatProbability
```

Frame rate is **50 Hz**, not 100 Hz. The session prompt and
`ENGINEERING_PLAN.md` Increment DSP.2 said "~10 ms hop / 100 Hz / 81 mel
bins" — those numbers come from a different beat-tracker reference and
do not match BeatNet's shipped configuration. Phosphene must follow the
BeatNet numbers below for bit-equivalence with the published weights.

---

## 2. Preprocessor (Session 2)

Implementation note: BeatNet uses `madmom` for preprocessing. Phosphene
must reimplement in Swift (vDSP / Accelerate) since `madmom` is a
Python+C library and not part of the runtime budget. The numbers below
match `BeatNet.__init__` and `LOG_SPECT.__init__` overrides verbatim.

| Parameter | Value | Source |
|---|---|---|
| Internal sample rate | 22050 Hz | `BeatNet.py:67` |
| Hop length | 441 samples (≈20.000 ms) | `BeatNet.py:68` (`int(20*0.001*22050)`) |
| Window length | 1411 samples (≈64.0 ms) | `BeatNet.py:69` (`int(64*0.001*22050)`) |
| FFT length | 2048 (next pow2 ≥ win) | `madmom.audio.stft.ShortTimeFourierTransformProcessor` default |
| Filterbank | log-frequency, 24 bands/octave | `LOG_SPECT(n_bands=[24])` per `BeatNet.py:71` |
| fmin / fmax | 30 Hz / 17000 Hz | `LOG_SPECT.__init__:31` |
| Filter norm | norm_filters=True | `LOG_SPECT.__init__:31` |
| Magnitude compression | `log(1 + |X|)` | `LogarithmicSpectrogramProcessor(mul=1, add=1)` |
| Temporal diff | first-order, positive-only, ratio=0.5, hstack | `SpectrogramDifferenceProcessor` |
| Output dim | **272** = 2 × 136 filters | observed; matches `BDA(dim_in=272, ...)` |

The "×2" comes from horizontally concatenating `[log_spec, positive_diff]`
in the SpectrogramDifferenceProcessor stack. The preprocessor must
preserve this layout: bins `[0..135]` are log-magnitudes; `[136..271]`
are positive temporal differences.

Online-mode framing uses centered frames (madmom `FramedSignalProcessor`
default `origin=0`); streaming mode shifts origin by one hop, producing
an ~84 ms latency as noted in `BeatNet.py:155`. Phosphene's live path
must match the streaming-mode origin so per-frame outputs land on the
same activation timeline as published evals.

---

## 3. BDA model (Sessions 3–4)

Constructor: `BDA(dim_in=272, num_cells=150, num_layers=2, device)` from
`BeatNet.py:81`. `num_cells` is the LSTM hidden size; `num_layers` is the
LSTM stack depth.

### 3.1 Layer-by-layer

```
input               x: (B, T, 272)                         per frame T=1 in stream mode

# reshape: torch.reshape(x, (-1, 272))      → (B*T, 272)
# unsqueeze + transpose to (B*T, 1, 272)    [conv-channel axis = 1]
conv1   Conv1d(in=1, out=2, kernel=10, stride=1, padding=0)
                    out: (B*T, 2, 263)                     263 = 272 - 10 + 1
        ReLU + MaxPool1d(kernel=2, stride=2)
                    out: (B*T, 2, 131)                     131 = floor(263 / 2)
# flatten last two dims
                    flat: (B*T, 262)                       262 = 2 * 131

linear0 Linear(in=262, out=150)             ReLU is applied implicitly via
                    out: (B*T, 150)                        the conv branch's ReLU; see note
# reshape back to (B, T, 150)

lstm    LSTM(input=150, hidden=150, num_layers=2,
             batch_first=True, bidirectional=False)
                    out:    (B, T, 150)
                    hidden: (2, B, 150)   carried frame-to-frame
                    cell:   (2, B, 150)   carried frame-to-frame

linear  Linear(in=150, out=3)
                    out: (B, T, 3) → transpose → (B, 3, T)

softmax Softmax(dim=0)                      class axis after transpose
                    out: 3-vector per frame: [beat, downbeat, no_beat]
```

Note on `linear0` activation: the published model.py applies ReLU only
inside `F.max_pool1d(F.relu(self.conv1(x)), 2)`. There is no separate
ReLU between `linear0` and the LSTM — the projection is linear. MPSGraph
build must replicate this faithfully; do not insert a hidden ReLU.

Note on `softmax(dim=0)`: after the `transpose(1, 2)` the tensor is
`(B, 3, T)`. `dim=0` softmax in BeatNet's eval path operates on the
class axis after the caller drops the batch dim — this is the
canonical normalization across {beat, downbeat, no_beat}. Phosphene's
graph should softmax over the 3-class dim explicitly; do not copy
`dim=0` literally without accounting for the `[0]` indexing in
`activation_extractor_*` (`pred = self.model(feats)[0]`). After that
indexing the softmax dim is the class axis (dim 0 of the 2-D tensor).

### 3.2 Tensor shapes (state_dict)

Verified against `model_1_weights.pt` (GTZAN-trained, 1,612,179 bytes
on disk including pickle overhead):

| Key | Shape | Bytes (FP32) |
|---|---|---|
| `conv1.weight` | (2, 1, 10) | 80 |
| `conv1.bias` | (2,) | 8 |
| `linear0.weight` | (150, 262) | 157,200 |
| `linear0.bias` | (150,) | 600 |
| `lstm.weight_ih_l0` | (600, 150) | 360,000 |
| `lstm.weight_hh_l0` | (600, 150) | 360,000 |
| `lstm.bias_ih_l0` | (600,) | 2,400 |
| `lstm.bias_hh_l0` | (600,) | 2,400 |
| `lstm.weight_ih_l1` | (600, 150) | 360,000 |
| `lstm.weight_hh_l1` | (600, 150) | 360,000 |
| `lstm.bias_ih_l1` | (600,) | 2,400 |
| `lstm.bias_hh_l1` | (600,) | 2,400 |
| `linear.weight` | (3, 150) | 1,800 |
| `linear.bias` | (3,) | 12 |
| **Total** | 14 tensors | **1,609,300 bytes (402,325 params)** |

LSTM weight rows are concatenated PyTorch-convention `[i, f, g, o]`
gates: 4 × hidden = 4 × 150 = 600. MPSGraph's `LSTM` op consumes the
same `[i, f, g, o]` ordering, so no reordering is required at load —
mirrors `StemModel+Weights.swift` for Open-Unmix.

### 3.3 Hidden-state handling

`BDA.__init__` initialises `self.hidden = torch.zeros(2, 1, 150)` and
`self.cell = torch.zeros(2, 1, 150)`. These persist across forward
calls in stream/realtime modes — i.e., the LSTM state carries from one
frame to the next. Phosphene's per-frame inference must:

1. Allocate two `(num_layers, 1, hidden)` = `(2, 1, 150)` UMA buffers
   for h and c, zero-initialised.
2. Pass them as graph inputs each frame; receive updated h, c as graph
   outputs; copy back to the same buffers.
3. Reset to zero on track change (mirrors `StemModel`'s reset on stem
   change).

### 3.4 Output meaning

After `softmax`, the 3-vector covers `[beat, downbeat, no_beat]` per
frame. The eval path takes `pred[:2, :]` — only beat (col 0) and
downbeat (col 1) are forwarded to the particle filter; the no-beat
class is implicit. Phosphene can either pass the full 3-vector to the
particle filter or drop class 2 — the prompt's "downbeat / beat /
no-beat" wording is correct.

Note: the paper §III lists the classes as `[no_beat, beat, downbeat]`
in some places. The shipped state_dict ordering is what the runtime
must follow — verified by the eval path using `pred[:2, :]` with the
filter expecting `[beat_prob, downbeat_prob]` columns, which means the
network's class axis is `[beat, downbeat, no_beat]` (or equivalent —
the loaded weights define what each output index means; do not
reorder).

---

## 4. Particle filter (Sessions 5–6)

Source: `src/BeatNet/particle_filtering_cascade.py` (24 KB; not
re-derived here). Key facts for downstream sessions:

* **Frame rate:** 50 fps. `particle_filter_cascade(... fps=50)` set in
  `BeatNet.__init__:74`.
* **Two-stage cascade:** beat-period particles, then downbeat-meter
  particles conditioned on the beat estimate. Phosphene's Session 5–6
  port must keep the cascade structure.
* **Particle count:** the upstream impl uses ~1500 beat particles
  + downbeat particles per beats-per-bar hypothesis; Phosphene's
  performance budget (< 0.5 ms / frame on M1) likely allows 500–800.
  Sessions 5–6 to calibrate.
* **State spaces:** beat phase ∈ [0, period), period ∈ [0.3 s, 1.5 s] —
  i.e. tempo ∈ [40, 200] BPM. Confirm via the upstream code at port time.

The Phosphene port stays pure-Swift. No Python at runtime. Particle
filter does not use the GPU; it runs on the same `mlQueue` (utility
QoS) as MPSGraph inference.

---

## 5. Variants

Three pre-trained checkpoints ship in the repo:

| Variant | File | Training corpus | Use |
|---|---|---|---|
| 1 | `model_1_weights.pt` | GTZAN | **Default — most general** |
| 2 | `model_2_weights.pt` | Ballroom | Dance / strict-meter material |
| 3 | `model_3_weights.pt` | Rock_corpus | Rock-specific |

Architecture is identical across variants — `BDA(272, 150, 2)`. Only
the weight values differ. Per Matt's direction (Session 1 prompt
exchange), only **variant 1 (GTZAN)** is vendored under
`PhospheneEngine/Sources/ML/Weights/beatnet/`. Variants 2 and 3 are
documented for future sessions but not converted. To add either,
re-run `Scripts/convert_beatnet_weights.py` with `--variant ballroom`
or `--variant rock_corpus` against the corresponding `.pt`. Output
filenames are unprefixed so a second variant in the same directory
would overwrite the first; route additional variants to a sibling
directory (`beatnet/ballroom/`, etc.) when adding them.

---

## 6. License

Repo-wide license: **CC-BY-4.0** (Creative Commons Attribution 4.0
International) — not MIT as the increment spec assumed. Permissive for
commercial use, modification, and redistribution; requires attribution
per §3(a) of the license text. Vendored weights and the converter
script carry this license; Phosphene's MIT license is unaffected (CC-BY
is non-copyleft). Attribution lives in `docs/CREDITS.md` and must also
be reachable from the shipped app's About surface (Session 7 / U-series
follow-up).

---

## 7. Cross-validation summary

The architecture audit was bottom-up validated by:

1. Reading `model.py` end-to-end (both eval forward and train forward).
2. Cross-checking `BeatNet.py` instantiation: `BDA(272, 150, 2, ...)`.
3. Loading `model_1_weights.pt` via `torch.load(..., weights_only=True)`
   and dumping every key + shape. All 14 tensors match expectations
   exactly.
4. Computing the parameter count from the architecture
   (`22 + 39450 + 181200 + 181200 + 453 = 402325`) and comparing to
   `numel()` summed over the loaded state_dict (also 402,325). Match.

This is the architecture Phosphene must replicate. Sessions 2–7 should
treat this document as authoritative; if any future session finds a
disagreement, fix `model.py` references in this doc rather than
silently diverge.

---

## 8. Spec corrections

`docs/ENGINEERING_PLAN.md` Increment DSP.2 contains assertions that
turned out to be wrong (or, generously, taken from the paper figure
rather than the shipped code). Closing-commit fixes:

| Location | Spec said | Reality |
|---|---|---|
| Step 3 | "22050 Hz internal rate, 2048-pt STFT, hop 220 samples (10 ms), 81 mel bins" | 22050 Hz ✓; 2048-pt STFT ✓; hop **441** samples (20 ms), **272-dim** log-freq filterbank with diff (24 bands/octave, fmin 30, fmax 17000), **not** 81 mel bins |
| Step 4 | "two 1D conv layers (kernels 3, 64 filters) → bidirectional GRU 1-layer (hidden 25)" | **one** Conv1d (1→2 ch, kernel 10), Linear0 projection (262→150), **LSTM** (not GRU), **2-layer** (not 1), **unidirectional** (not bidirectional), hidden **150** (not 25) |
| Step 5 | Activation rate "~10 ms mel-frame" → "<2 ms / frame on M1" | Activation rate is ~20 ms (50 fps), so per-frame budget can be relaxed to < 2 ms / 20 ms = 10 % of frame budget for inference. The < 2 ms target stays sensible. |
| License | "MIT-licensed" | **CC-BY-4.0**. Compatible with Phosphene's MIT but requires §3(a) attribution. |

These are doc-only corrections; no code is yet written that depends
on the wrong values. Land alongside this audit in the closing commit.
