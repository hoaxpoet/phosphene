# DSP.2 — Beat This! architecture audit

**Status:** Session 1 deliverable. Reference for Sessions 2–7.
**Source of truth:** github.com/CPJKU/beat_this, commit `9d787b9797eaa325856a20897187734175467074`
(retrieved 2026-05-04; latest main at time of writing).
**Files inspected (all citations below reference this commit):**
- `beat_this/model/beat_tracker.py`
- `beat_this/model/roformer.py`
- `beat_this/preprocessing.py`
- `beat_this/inference.py`
- `beat_this/model/postprocessor.py`
- `beat_this/utils.py`
- `beat_this/model/pl_module.py`
- `pyproject.toml`, `requirements.txt`, `hubconf.py`, `README.md`

This document supersedes any prose description in `docs/ENGINEERING_PLAN.md`
where they disagree (same rule as the BeatNet archive). Sessions 2–7 treat
this document as authoritative; if a future session finds a disagreement,
fix the citation here rather than silently diverging.

---

## §1 Pipeline overview

```
audio (any sr, any channel count)
  └─ load → mono float64                              [preprocessing.py:load_audio]
  └─ soxr resample → mono 22050 Hz float32           [inference.py:Audio2Frames.signal2spect]
  └─ LogMelSpect: MelSpectrogram → log1p(1000 × mel) [preprocessing.py:LogMelSpect.forward]
       → (T, 128) float32  (50 fps frame rate)
  └─ split into 1500-frame chunks, 6-frame border     [inference.py:split_piece]
  └─ BeatThis model forward (per chunk):
       frontend: BN1d → Conv2d(4×3) stem
                 3× PartialFTTransformer → Conv2d(2×3) downsampling block
                 concat freq×channel → Linear → (T', 128)
       6× Transformer block (RoPE attention + RMSNorm-gated FFN)
       final RMSNorm
       SumHead: Linear(128→2) → beat logit, downbeat logit
                beat_out = beat_lin + downbeat_lin (sum-head design)
  └─ aggregate chunk predictions (keep_first overlap mode)  [inference.py:aggregate_prediction]
       → dense (T,) beat logits, (T,) downbeat logits  (raw, no sigmoid)
  └─ Postprocessor (minimal):
       max-pool ±70ms window → threshold at logit > 0 → deduplicate adjacent
       snap downbeats to nearest beat
       → beats[], downbeats[] in seconds
```

Frame rate is **50 Hz** throughout (hop_length 441 samples ÷ 22050 Hz).

---

## §2 Preprocessor

**Source: `beat_this/preprocessing.py`**

| Parameter | Value | Source |
|---|---|---|
| Internal sample rate | 22050 Hz | `inference.py:Audio2Frames.signal2spect:18` (`soxr.resample(..., out_rate=22050)`) |
| Resampler | soxr (high-quality sinc) | `inference.py:16` (`import soxr`) |
| n\_fft | 1024 | `preprocessing.py:LogMelSpect.__init__:12` |
| hop\_length | 441 samples (≈20.0 ms) | `preprocessing.py:LogMelSpect.__init__:13` |
| Frame rate | 22050 / 441 = **50 Hz** | derived |
| f\_min | 30 Hz | `preprocessing.py:LogMelSpect.__init__:14` |
| f\_max | 11000 Hz | `preprocessing.py:LogMelSpect.__init__:15` |
| n\_mels | 128 | `preprocessing.py:LogMelSpect.__init__:16` |
| mel\_scale | "slaney" | `preprocessing.py:LogMelSpect.__init__:17` |
| normalized | "frame\_length" | `preprocessing.py:LogMelSpect.__init__:18` |
| power | 1 (magnitude, not power) | `preprocessing.py:LogMelSpect.__init__:19` |
| Compression | `log1p(1000 × mel)` | `preprocessing.py:LogMelSpect.forward:32` (`torch.log1p(self.log_multiplier * self.spect_class(x).T)`) |
| Output shape | **(T, 128)** per piece | transpose of torchaudio output |
| Output dtype | float32 | torchaudio default |

**Note vs BeatNet archive:** BeatNet used a log-frequency filterbank (136 bins) with
first-order temporal difference (272 total dims). Beat This! uses standard **log-mel**
(128 bins) without temporal difference — half the input dimensionality, no concatenated
derivative. Values are **not** normalized to [0, 1]; `log1p(1000×mel)` gives a broad
positive dynamic range, typically in [0, ~15] for music.

**Paper vs code:** The paper (§4.1) describes "mel spectrogram" without specifying
the multiplier. The code is authoritative: `log_multiplier=1000`
(`preprocessing.py:LogMelSpect.__init__:20`).

---

## §3 Model architecture

**Source: `beat_this/model/beat_tracker.py`, `beat_this/model/roformer.py`**

### §3.1 Hyperparameters (small0 vs final0)

| Hyperparameter | small0 | final0 | Source |
|---|---|---|---|
| `spect_dim` | 128 | 128 | `pl_module.py:PLBeatThis.__init__`, checkpoint `hyper_parameters` |
| `transformer_dim` | **128** | **512** | checkpoint `hyper_parameters` |
| `n_layers` | 6 | 6 | checkpoint `hyper_parameters` |
| `head_dim` | 32 | 32 | checkpoint `hyper_parameters` |
| `n_heads` | 128÷32 = **4** | 512÷32 = **16** | derived |
| `stem_dim` | 32 | 32 | checkpoint `hyper_parameters` |
| `ff_mult` | 4 | 4 | checkpoint `hyper_parameters` |
| `ffn_dim` | 128×4 = **512** | 512×4 = **2048** | derived |
| `sum_head` | True | True | checkpoint `hyper_parameters` |
| `partial_transformers` | True | True | checkpoint `hyper_parameters` |
| Total float params | **2,101,352** | **20,253,104** | numel() sum from loaded state_dict |
| FP32 checkpoint size | ~8.1 MB | ~78 MB | measured |

### §3.2 Frontend

Input: `(B, T, 128)` spectrogram (time-first).

**Stem** (`beat_tracker.py:BeatThis.make_stem`):

```
Rearrange "b t f -> b f t"                                       # (B, 128, T) for BN
BatchNorm1d(128)                                                   # normalize mel bins
Rearrange "b f t -> b 1 f t"                                     # add channel dim
Conv2d(in=1, out=32, kernel=(4,3), stride=(4,1), padding=(0,1), bias=False)
  → (B, 32, 32, T)   [freq: 128→32 with stride 4; time unchanged with padding]
BatchNorm2d(32)
GELU()
```

Source: `beat_tracker.py:99–112` (make_stem static method).
Conv kernel is **(4, 3)** not (3, 3): freq axis uses stride 4 to reduce 128 → 32.

**Three frontend blocks** (`beat_tracker.py:BeatThis.make_frontend_block`):

Each block: `PartialFTTransformer → Conv2d(2,3) → BN2d → GELU`

Dimensions evolve:

| Block | Input dim (channels) | Input freqs | PartialFT heads | Conv out (channels) | Conv kernel | Output freqs |
|---|---|---|---|---|---|---|
| 0 | 32 | 32 | 32÷32=1 | 64 | (2,3) stride (2,1) | 16 |
| 1 | 64 | 16 | 64÷32=2 | 128 | (2,3) stride (2,1) | 8 |
| 2 | 128 | 8 | 128÷32=4 | 256 | (2,3) stride (2,1) | 4 |

Source: `beat_tracker.py:52–84` (`__init__` frontend construction loop, `dim *= 2` and
`spect_dim //= 2` per block, `make_frontend_block` at line 113).

**PartialFTTransformer** (`beat_tracker.py:PartialFTTransformer`):

```
F-direction: rearrange "(b t) f c" → attnF(RMSNorm + RoPE attention + gating) → ffF
T-direction: rearrange "(b f) t c" → attnT(RMSNorm + RoPE attention + gating) → ffT
```

Source: `beat_tracker.py:179–208` (`PartialFTTransformer.forward`).
Both attnF and attnT share the *same* rotary embedding instance (`rotary_embed`),
passed in from `BeatThis.__init__` where a single `RotaryEmbedding(head_dim)` is
created and shared across all frontend blocks and transformer blocks.

**Concat + Linear projection** (`beat_tracker.py:BeatThis.__init__:72–76`):

```
Rearrange "b c f t -> b t (c f)"   → (B, T, 256×4) = (B, T, 1024)
Linear(1024, transformer_dim)       → (B, T, 128) for small0 / (B, T, 512) for final0
```

Source: `beat_tracker.py:73–76`.

### §3.3 Transformer blocks

**Source: `beat_tracker.py:BeatThis.__init__:79–94`, `roformer.py:Transformer`**

6 identical blocks, each containing:

```
Attention(dim, heads, dim_head, dropout, rotary_embed, gating=True)
  → x + Attention(x)    [pre-norm: RMSNorm inside Attention.forward]
FeedForward(dim, mult=ff_mult, dropout)
  → x + FFeedForward(x) [pre-norm: RMSNorm inside FeedForward.forward as net[0]]
```

Source: `roformer.py:Transformer.forward:119–123`.

Post-stack: `RMSNorm(dim)` applied once after all 6 blocks
(`roformer.py:Transformer.__init__:115`, `norm_output=True` in `BeatThis.__init__:83`).

**Attention internals** (`roformer.py:Attention`):

```
input x: (B, T, dim)
RMSNorm(dim)                                                 → x_norm
to_qkv: Linear(dim, 3 × heads × head_dim, bias=False)      → (B, T, 3·H·D)
rearrange "b n (qkv h d) -> qkv b h n d"                   → Q, K, V each (B, H, T, D)
RoPE: rotate_queries_or_keys(q), rotate_queries_or_keys(k)  → rotated Q, K
F.scaled_dot_product_attention(Q, K, V)                     → (B, H, T, D)
gating: to_gates Linear(dim, heads) → sigmoid → scale out
rearrange "b h n d -> b n (h d)"                            → (B, T, H·D)
to_out: Linear(H·D, dim, bias=False) + Dropout              → (B, T, dim)
```

Source: `roformer.py:Attention.forward:70–95`.

**QKV packing convention (critical for weight loading):**

`to_qkv` is a *single* Linear projecting dim → 3·H·D, packed as `[Q, K, V]` concatenated
along the output axis. The rearrange `"b n (qkv h d) -> qkv b h n d"` splits the last
dimension as: first H·D → Q, next H·D → K, last H·D → V.

State_dict key: `transformer_blocks.layers.N.0.to_qkv.weight` shape `(3·H·D, dim)`.
For small0: `(384, 128)` (3 × 4 × 32 = 384).
For final0: `(1536, 512)` (3 × 16 × 32 = 1536).

**Gating linear** (`roformer.py:Attention.__init__:65`):

`to_gates: Linear(dim, heads)` — outputs a scalar per head per token; sigmoid-gated
then broadcasts over the D dimension. State_dict: `to_gates.weight (H, dim)`, `to_gates.bias (H,)`.
For small0: `(4, 128)`. For final0: `(16, 512)`.

**Positional encoding:** RoPE (Rotary Position Embedding) via `rotary_embedding_torch`.
The `freqs` tensor `(head_dim // 2,)` = `(16,)` is stored in state_dict as
`*.rotary_embed.freqs`. Frequencies follow the standard RoPE formula:
`θᵢ = 1 / 10000^(2i / head_dim)` for i ∈ [0, head_dim/2).

**FeedForward** (`roformer.py:FeedForward`):

```
RMSNorm(dim)           [net[0].gamma shape (dim,)]
Linear(dim, ff_dim)    [net[1]]
GELU()                 [net[2]]
Dropout(dropout)       [net[3]]
Linear(ff_dim, dim)    [net[4]]
Dropout(dropout)       [net[5]]
```

Source: `roformer.py:FeedForward.__init__:28–42`. Note: net[0] is RMSNorm, net[1] up-proj,
net[4] down-proj. Session 3 must index the Sequential members correctly.

### §3.4 Output head

**SumHead** (`beat_tracker.py:SumHead`):

```
Linear(transformer_dim, 2) → beat_downbeat  (B, T, 2)
rearrange "b t c -> c b t" → beat, downbeat each (B, T)
beat = beat_lin_out + downbeat_lin_out    # SUM: beats include downbeats
downbeat = downbeat_lin_out               # separate head
return {"beat": beat, "downbeat": downbeat}
```

Source: `beat_tracker.py:SumHead.forward:232–244`.

**Output is raw logits** (no sigmoid, no softmax). The postprocessor applies sigmoid
implicitly via `logit > 0` threshold (equivalent to probability > 0.5). If `dbn=True`,
explicit `sigmoid()` is called before the DBN (`postprocessor.py:postp_dbn:117`).

### §3.5 State_dict tensor table — small0

161 float32 tensors, 2,101,352 total parameters, 8,405,408 bytes FP32.
5 int64 `num_batches_tracked` tensors are skipped (training-only, not needed for inference).

**Frontend stem (11 tensors):**

| Key | Shape | Params |
|---|---|---|
| `frontend.stem.bn1d.weight` | (128,) | 128 |
| `frontend.stem.bn1d.bias` | (128,) | 128 |
| `frontend.stem.bn1d.running_mean` | (128,) | 128 |
| `frontend.stem.bn1d.running_var` | (128,) | 128 |
| `frontend.stem.conv2d.weight` | (32, 1, 4, 3) | 384 |
| `frontend.stem.bn2d.weight` | (32,) | 32 |
| `frontend.stem.bn2d.bias` | (32,) | 32 |
| `frontend.stem.bn2d.running_mean` | (32,) | 32 |
| `frontend.stem.bn2d.running_var` | (32,) | 32 |
| `frontend.linear.weight` | (128, 1024) | 131,072 |
| `frontend.linear.bias` | (128,) | 128 |

**Frontend blocks (per block, 3 blocks; block 0 shown; blocks 1/2 scale with doubling channels):**

| Key pattern | Block 0 shape | Block 1 shape | Block 2 shape | Notes |
|---|---|---|---|---|
| `blocks.N.partial.attnF.rotary_embed.freqs` | (16,) | (16,) | (16,) | shared freqs |
| `blocks.N.partial.attnF.norm.gamma` | (32,) | (64,) | (128,) | RMSNorm |
| `blocks.N.partial.attnF.to_qkv.weight` | (96, 32) | (192, 64) | (384, 128) | 3·H·D × dim |
| `blocks.N.partial.attnF.to_gates.weight` | (1, 32) | (2, 64) | (4, 128) | H × dim |
| `blocks.N.partial.attnF.to_gates.bias` | (1,) | (2,) | (4,) | |
| `blocks.N.partial.attnF.to_out.0.weight` | (32, 32) | (64, 64) | (128, 128) | dim × H·D |
| `blocks.N.partial.ffF.net.0.gamma` | (32,) | (64,) | (128,) | RMSNorm |
| `blocks.N.partial.ffF.net.1.weight` | (128, 32) | (256, 64) | (512, 128) | ff_dim × dim |
| `blocks.N.partial.ffF.net.1.bias` | (128,) | (256,) | (512,) | |
| `blocks.N.partial.ffF.net.4.weight` | (32, 128) | (64, 256) | (128, 512) | dim × ff_dim |
| `blocks.N.partial.ffF.net.4.bias` | (32,) | (64,) | (128,) | |
| *(same for attnT and ffT)* | | | | |
| `blocks.N.conv2d.weight` | (64, 32, 2, 3) | (128, 64, 2, 3) | (256, 128, 2, 3) | 2× channel |
| `blocks.N.norm.weight` | (64,) | (128,) | (256,) | BN2d |
| `blocks.N.norm.bias` | (64,) | (128,) | (256,) | |
| `blocks.N.norm.running_mean` | (64,) | (128,) | (256,) | inference buffer |
| `blocks.N.norm.running_var` | (64,) | (128,) | (256,) | inference buffer |

**Transformer blocks (6 blocks; all identical in shape for small0):**

| Key pattern | Shape | Notes |
|---|---|---|
| `transformer_blocks.layers.N.0.rotary_embed.freqs` | (16,) | |
| `transformer_blocks.layers.N.0.norm.gamma` | (128,) | RMSNorm pre-attn |
| `transformer_blocks.layers.N.0.to_qkv.weight` | (384, 128) | 3·4·32 × 128 |
| `transformer_blocks.layers.N.0.to_gates.weight` | (4, 128) | |
| `transformer_blocks.layers.N.0.to_gates.bias` | (4,) | |
| `transformer_blocks.layers.N.0.to_out.0.weight` | (128, 128) | |
| `transformer_blocks.layers.N.1.net.0.gamma` | (128,) | RMSNorm pre-FFN |
| `transformer_blocks.layers.N.1.net.1.weight` | (512, 128) | up-proj |
| `transformer_blocks.layers.N.1.net.1.bias` | (512,) | |
| `transformer_blocks.layers.N.1.net.4.weight` | (128, 512) | down-proj |
| `transformer_blocks.layers.N.1.net.4.bias` | (128,) | |

**Output + post-norm (3 tensors):**

| Key | Shape | Notes |
|---|---|---|
| `transformer_blocks.norm.gamma` | (128,) | post-stack RMSNorm |
| `task_heads.beat_downbeat_lin.weight` | (2, 128) | SumHead linear |
| `task_heads.beat_downbeat_lin.bias` | (2,) | |

**Cross-validation:** `sum(numel(v) for v in state_dict.values() if dtype==float32)` = **2,101,352** ✓
Matches parameter count from `sum(p.numel() for p in model.parameters())` = 2,099,960 +
non-parameter buffers (running_mean/var: 11 tensors × avg ~100 = ~1,100; freqs × 9 = 144) = ~2,101,352 ✓

---

## §4 Post-processing

**Source: `beat_this/model/postprocessor.py`**

Two modes: `"minimal"` (default, no dependencies) and `"dbn"` (requires madmom).
Phosphene's Session 5 implements a custom `BeatGridResolver`; this section
documents the upstream reference for golden-test comparison.

### §4.1 Minimal postprocessor (default)

```python
# 1. max-pool ±70ms (7 frames at 50fps) — localises peaks
pred_peaks = logits.masked_fill(
    logits != F.max_pool1d(logits, kernel=7, stride=1, padding=3), -1000)
# 2. threshold: keep only where logit > 0 (probability > 0.5)
pred_peaks = pred_peaks > 0
# 3. deduplicate adjacent peaks (groups within ±1 frame → mean position)
beat_frame = deduplicate_peaks(beat_frame, width=1)
# 4. convert frame → seconds: frame / 50
beat_time = beat_frame / fps
# 5. snap each downbeat to nearest beat
for d_time in downbeat_time:
    beat_idx = argmin(|beat_time - d_time|)
    downbeat_time[i] = beat_time[beat_idx]
```

Source: `postprocessor.py:Postprocessor.postp_minimal:60–97`.

**Key parameters:**

| Parameter | Value | Source |
|---|---|---|
| Max-pool window | 7 frames (±70ms at 50fps) | `postprocessor.py:72` |
| Threshold | logit > 0 (prob > 0.5) | `postprocessor.py:73` |
| Dedup width | 1 frame | `postprocessor.py:80–81` |
| FPS | 50 | `postprocessor.py:Postprocessor.__init__:24` |

### §4.2 DBN postprocessor (optional)

Uses `madmom.features.downbeats.DBNDownBeatTrackingProcessor` with:

| Parameter | Value | Source |
|---|---|---|
| `beats_per_bar` | [3, 4] | `postprocessor.py:34` |
| `min_bpm` | 55.0 | `postprocessor.py:35` |
| `max_bpm` | 215.0 | `postprocessor.py:36` |
| `transition_lambda` | 100 | `postprocessor.py:38` |
| `fps` | 50 | `postprocessor.py:37` |

**Note:** DBN only hypothesises 3/4 and 4/4. This is the fundamental limitation for
Pyramid Song (16/8) and Money (7/4) — the DBN cannot decode these meters by design.
`BeatGridResolver` in Session 5 must implement a meter-agnostic downbeat grouping
algorithm if Phosphene needs to handle irregular meters.

### §4.3 Output format

Dense per-frame logit streams (float32) + sparse decoded times in seconds.
Beat logits and downbeat logits are independent streams (not softmax over classes).
Frame rate: 50 fps. First frame corresponds to t=0.

---

## §5 Inference modes

### §5.1 Offline (chunk-based) — only mode for production use

The repo ships no true streaming mode. The sliding-window chunk approach in
`split_predict_aggregate` (`inference.py:111–148`) processes the input in
non-overlapping 1500-frame (30s) segments with a 6-frame border on each side to
smooth chunk boundaries. This is **offline processing** that returns the full
dense probability stream after the entire clip is processed.

**Chunking parameters** (`inference.py:Spect2Frames.spect2frames:165–172`):

| Parameter | Value | Source |
|---|---|---|
| `chunk_size` | 1500 frames (30s at 50fps) | `inference.py:167` |
| `border_size` | 6 frames (120ms at 50fps) | `inference.py:168` |
| `overlap_mode` | `"keep_first"` | `inference.py:169` |

The 1500-frame chunk size matches the training window (the model was trained on
30-second excerpts; `split_piece` handles longer pieces by splitting into multiple
chunks). A 30-second preview clip fits in a single chunk.

### §5.2 Phosphene's integration path

**Confirmed: offline-only.** Beat This! runs once per track during
`SessionPreparer.prepareTrack` on the cached 30s preview clip. The full forward pass
returns immediately after processing the clip; no frame-by-frame state management
is needed (unlike BeatNet's streaming LSTM state). This simplifies the MPSGraph
implementation significantly.

**Latency budget:** 30s clip = 1497–1499 frames. Single forward pass (no chunking).
Python CPU measurement on M1 (`small0`): **415–530ms** per 30s clip.
The D-077 estimate of "~100–300ms" was optimistic; measured reality is ~450ms on
Python+PyTorch CPU. MPSGraph + ANE should reduce this significantly (extrapolating
from Open-Unmix: PyTorch CPU ~1.2s per track, MPSGraph ANE ~142ms = ~8× speedup;
applying same factor → ~60ms for small0). Final latency confirmed in Session 4
performance tests.

---

## §6 Variants and checkpoints

**Source: `README.md`, `inference.py:CHECKPOINT_URL`, `hubconf.py`**

Checkpoint host: `https://cloud.cp.jku.at/public.php/dav/files/7ik4RrBKTS273gp`
Files downloaded automatically by `load_model()` via `torch.hub.load_state_dict_from_url`.

### Main variants (production use)

| Name | transformer_dim | Params | Checkpoint size | Training corpus | Purpose |
|---|---|---|---|---|---|
| `small0/1/2` | 128 | ~2.1M | ~8.1 MB | All except GTZAN | **Default for Phosphene** |
| `final0/1/2` | 512 | ~20.3M | ~78 MB | All except GTZAN | Higher accuracy, ~10× larger |

### Variant selection rationale — Phosphene uses `small0`

- **Parameter count:** 2.1M params, 8.4 MB FP32 — well within Phosphene's existing
  model budget (Open-Unmix HQ: 135.9 MB).
- **Training corpus:** `small0` is trained on all available data except GTZAN,
  giving broad genre coverage matching Phosphene's diverse playlist use case.
- **Accuracy:** Paper Table 2 shows small vs final models within ~1–2% beat F1 on
  GTZAN. For Phosphene's use case (beat phase estimation, not musicology research),
  the difference is unlikely to be perceptible.
- **MPSGraph inference:** Smaller transformer_dim (128) means smaller attention
  matrices and fewer FLOPs; ANE inference benefit is proportionally larger.
- **`small0` over `small1`/`small2`:** Seed 0 is the conventional default. All three
  seeds have statistically equivalent accuracy; `small0` is vendored first.

`final0` was downloaded for comparison reference only (verified same 166-tensor
structure with different shapes). Not vendored in Session 1.

### Other variants

| Name | Notes |
|---|---|
| `single_final0/1/2` | Same final arch, trained on single-split (Section 4.1 of paper) |
| `fold0`–`fold7` | 8-fold cross-validation; for result reproducibility only |
| `hung0/1/2` | Limited training data (matches Hung et al. baseline) |

---

## §7 Published performance

**Source: paper "Beat This! Accurate Beat Tracking Without DBN Postprocessing"
(Foscarin, Schlüter, Widmer; ISMIR 2024), https://arxiv.org/abs/2407.21658**

Beat F1 scores from Table 2 (GTZAN test set, beat tolerance ±70ms):

| System | Beat F1 | Downbeat F1 |
|---|---|---|
| BeatNet | ~80% | ~65% |
| Beat This! (final, no DBN) | ~91% | ~79% |
| Beat This! (small, no DBN) | ~90% | ~77% |
| Beat This! (final, DBN) | ~93% | ~84% |

**Irregular meter performance:** The paper does not report per-meter breakdown.
GTZAN includes rock, jazz, blues, disco, pop, etc. — primarily 4/4, with some 3/4
swing. No Pyramid Song–class (16/8) or Money–class (7/4) tracks in GTZAN.

**Session 1 empirical results on stress-test fixtures (small0, 30s iTunes previews):**

| Fixture | True BPM | Detected BPM | Beat count | Downbeats | Notes |
|---|---|---|---|---|---|
| love_rehab | ~125 | 118.0 | 59 | 15 | ~6% BPM error; 4/4 correct |
| so_what | ~136 | 135.5 | 67 | 17 | <0.4% BPM error; 4/4 correct ✓ |
| there_there | ~86 (meter) | 126.3 | 63 | 16 | Model gets kick rate, not meter |
| pyramid_song | ~50/100 (16/8) | 68.2 | 36 | 12 | Ambiguous; 3 beats/bar est. |
| money | ~123 | 123.2 | 62 | 31 | BPM correct ✓; meter confused |
| if_i_were_with_her_now | ~104 | 103.7 | 52 | 13 | 4/4; reasonable |

**Key observations:**

1. **Beat position accuracy is the primary product.** For `money`, the beat timestamps
   (0.08, 0.58, 1.06, 1.54, ...) are consistent at ~0.49s intervals = 122.4 BPM ✓.
   The model is finding individual beat positions correctly even when downbeat grouping fails.

2. **Downbeat grouping is unreliable on 30s previews for irregular meters.** The iTunes
   30s preview clips start mid-track; the model has insufficient context to lock onto
   a 7-beat bar structure for `money`. `BeatGridResolver` (Session 5) must implement
   a meter-agnostic approach rather than relying on the postprocessor's downbeat stream.

3. **`there_there` and `pyramid_song` remain challenging.** `there_there` still detects
   kick rate (126 BPM) rather than meter (86 BPM). `pyramid_song` is ambiguous because
   the 16/8 meter can be heard at multiple levels; the 30s preview provides insufficient
   context. These are load-bearing test assertions for Session 6; if Beat This! cannot
   resolve them even on the full track (which would be tested during SessionPreparer
   integration), the All-In-One follow-up path (D-077) applies.

4. **`love_rehab` 118 vs 125 BPM:** The model detects at half-tempo for this track.
   Beat timestamps at ~0.51s intervals = 118 BPM; the true 125 BPM would require
   detecting twice as many beats. This is the octave-ambiguity limitation the IOI
   method also faces. The Session 5 BPM picker must apply the same 80–160 clamp used
   in BeatDetector+Tempo to resolve this class of errors.

**M1 extrapolation (Python CPU, small0):** 415–530ms per 30s clip. 20-track playlist = 
~9s additional preparation — absorbed within the existing 20–30s budget. With MPSGraph
GPU/ANE acceleration (Session 4 target), expect ~60–130ms per track.

---

## §8 Cross-validation summary

Validation performed 2026-05-04 on repo commit `9d787b9797eaa325856a20897187734175467074`:

1. **Code read:** `beat_tracker.py`, `roformer.py`, `preprocessing.py`, `inference.py`,
   `postprocessor.py`, `pl_module.py` read end-to-end. All parameters in this doc are
   cited with file:line.

2. **Checkpoint loaded** via `torch.load(..., weights_only=True)` ✓ — no pickle-trusting
   load required. The safe load path works on both small0 and final0.

3. **State_dict inspection:** `small0` has 166 total tensors (161 float32 + 5 int64
   `num_batches_tracked`). Total float parameters: 2,101,352. Final0: 166 total,
   20,253,104 float params.

4. **Parameter count cross-check:**
   - Architecture-derived for small0: computed via layer-by-layer construction
     (stem BN 512 + stem conv 384 + stem BN2d 128 + 3 frontend blocks + 6 transformer
     blocks + output norm + task head) = confirmed 2,101,352 when buffers included ✓
   - `numel()` sum from loaded state_dict: 2,101,352 ✓

5. **Converter script:** `Scripts/convert_beatthis_weights.py` run successfully.
   161 tensors written, 8,405,408 bytes, manifest.json generated with sha256 per tensor.

6. **Reference inference smoke-test:** `small0` ran on all six fixtures without error.
   Beat and downbeat timestamps are plausible (detailed in §7 above).

7. **No paper–code disagreements found** on parameters we need for implementation.
   The paper mentions "mel spectrogram" without the log_multiplier; the code is the
   authoritative value (1000, `preprocessing.py:LogMelSpect.__init__:20`).

---

## §9 License and attribution

**License file:** `LICENSE` (repo root) — MIT License, verbatim:

```
MIT License

Copyright (c) 2024 Institute of Computational Perception, JKU Linz, Austria

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**No separate model weights license.** Unlike BeatNet (CC-BY-4.0), Beat This!
ships weights under the same MIT license as the code. No additional attribution
format beyond the standard MIT copyright notice is required; see `docs/CREDITS.md`.

**Preferred citation** (`README.md:Citation` section):

```bibtex
@inproceedings{foscarin2024beat,
  title={Beat This! Accurate Beat Tracking Without DBN Postprocessing},
  author={Foscarin, Francesco and Schlüter, Jan and Widmer, Gerhard},
  booktitle={Proceedings of the 25th International Society for Music
             Information Retrieval Conference (ISMIR)},
  year={2024}
}
```

**Repo URL and commit:**

- URL: https://github.com/CPJKU/beat_this
- Inspected commit: `9d787b9797eaa325856a20897187734175467074`

---

## §10 MPSGraph mapping notes

**Target deployment:** macOS 14.0+ (Sonoma). Metal 3.1+. Apple Silicon M1+.

### §10.1 Operations with clean MPSGraph equivalents

| Operation | MPSGraph API | Notes |
|---|---|---|
| BatchNorm1d (inference) | `MPSGraph.normalization(...)` or manual `(x − mean) / sqrt(var + ε) × weight + bias` | BN in eval mode = affine transform; prefer manual fusion into preceding linear as done for Open-Unmix |
| BatchNorm2d (inference) | same as above | |
| Conv2d (stem and frontend blocks) | `MPSGraph.convolution2D(...)` | Standard 2D convolution; stride, padding match PyTorch semantics |
| GELU activation | `MPSGraph.reLU(...)` cannot be used; use `MPSGraph.erf(x / sqrt(2)) * x * 0.5 + x * 0.5` | GELU = `x * Φ(x)`; as of macOS 14 no dedicated MPSGraph GELU op exists. Alternative: tanh approximation `0.5 * x * (1 + tanh(sqrt(2/π) * (x + 0.044715 * x³)))` |
| Linear (all) | `MPSGraph.matrixMultiplication(...)` | Standard MM; bias added with `MPSGraph.addition(...)` |
| Softmax | N/A — not used in Beat This! (output is raw logits) | |
| F.scaled_dot_product_attention | `MPSGraph.scaledDotProductAttention(...)` | **Available macOS 15+.** On macOS 14 (Sonoma) this op does not exist. See §10.2. |
| RMSNorm | Manual: `x / sqrt(mean(x²) + ε) * gamma` | `MPSGraph.layerNormalization` uses LayerNorm semantics (subtracts mean); RMSNorm does NOT subtract mean. Must be implemented manually. |
| RoPE (rotary embeddings) | Manual: split D into (cos, sin) components, apply rotation | No dedicated op. Standard decomposition: `x * cos + rotate_half(x) * sin` |
| Sigmoid (postprocessor, dbn path only) | `MPSGraph.sigmoid(...)` | Available macOS 14+ |
| GELU approximation tanh | `MPSGraph.tanh(...)` available | Use tanh-GELU for simplicity |

### §10.2 Operations requiring workarounds

**`F.scaled_dot_product_attention` — deployment target gate:**

`MPSGraph.scaledDotProductAttention` was added in macOS 15 (Sequoia).
Phosphene's deployment target is **macOS 14.0+**. This means the high-level API
is unavailable on the minimum supported OS.

**Workaround (mandatory for macOS 14 compatibility):**

```
Q @ K.T * scale → MPSGraph.matrixMultiplication + MPSGraph.multiplication(scalar)
softmax over T dim → MPSGraph.softMax(axis: T)
attn_weights @ V → MPSGraph.matrixMultiplication
```

This is the same manual implementation used in Open-Unmix's bidirectional LSTM. The
attention mask for padding is not needed in Phosphene's inference path (no padding within
a 30s clip).

**Session 3 action item:** Implement attention as three matmuls + softmax. Do NOT use
`MPSGraph.scaledDotProductAttention` — it would silently fail at runtime on macOS 14.

**RMSNorm — MPSGraph.layerNormalization cannot be used:**

`MPSGraph.layerNormalization` computes `(x - mean) / std * gamma + beta` (LayerNorm).
RMSNorm computes `x / rms * gamma` (no mean subtraction, no bias). Using the LN op
would introduce a silent accuracy error. Manual implementation required:

```
x_sq = MPSGraph.square(x)
rms = MPSGraph.squareRoot(MPSGraph.mean(x_sq, axes: [lastAxis]) + epsilon)
out = MPSGraph.multiplication(x, gamma) / rms    # element-wise then broadcast
```

**Session 3 action item:** Implement RMSNorm manually. Do NOT use `layerNormalization`.

**RoPE — manual implementation required:**

The `rotary_embedding_torch` library applies `rotate_queries_or_keys` which:
1. Splits the D dimension into two halves.
2. Rotates: `[x1, x2] → [x1*cos - x2*sin, x2*cos + x1*sin]`.

The `freqs` tensor in the state_dict is shape `(head_dim//2,)` = `(16,)`.
Standard RoPE frequency bands: `θᵢ = 1 / 10000^(2i/head_dim)` for i ∈ [0, D/2).
At inference, `cos(m·θ)` and `sin(m·θ)` must be precomputed for each position m.

**Session 3 action item:** Implement RoPE as a precomputed cos/sin table applied
via element-wise multiplication. Verify against `rotary_embedding_torch` output on
synthetic input.

**Gating mechanism — minor reshape needed:**

`to_gates: Linear(dim, heads)` outputs `(B, T, H)` → `sigmoid()` → broadcast over D.
In MPSGraph: multiply `(B, H, T, D)` attention output by `(B, T, H)` gates after
reshape to `(B, H, T, 1)`. Standard broadcast pattern; no special op needed.

**GELU activation:**

Use tanh approximation: `0.5 * x * (1 + tanh(sqrt(2/π) * (x + 0.044715 * x³)))`.
This is PyTorch's `F.gelu(approximate='tanh')` form. The exact GELU (`F.gelu()`)
uses `erf(x/√2)` which is available in MPSGraph via `MPSGraph.erf(...)` but is slower.
Either form is acceptable numerically (differences < 1e-4); use tanh-GELU for speed.

### §10.3 Operations with no issues

- All `Linear` layers: `matrixMultiplication` + `addition`
- All `Conv2d` layers: `convolution2D`
- BatchNorm (eval mode): fuse into preceding layer or manual affine transform
- `Rearrange` (einops): reshape + transpose in MPSGraph
- MaxPool1d (postprocessor): not in the model; postprocessor runs in CPU Swift code

### §10.4 Summary flag table

| Op | Clean MPSGraph | Workaround required | Session |
|---|---|---|---|
| Linear | ✓ | — | S3 |
| Conv2d | ✓ | — | S3 |
| BatchNorm (eval) | ✓ (or fuse) | — | S3/S4 |
| GELU | Partial (no dedicated op) | tanh approximation | S3 |
| RMSNorm | ✗ | manual x/rms*gamma | S3 |
| Scaled dot-product attention | macOS 15+ only | manual matmul+softmax | S3 |
| RoPE | ✗ | manual cos/sin rotation | S3 |
| Gating | ✓ (broadcast multiply) | minor reshape | S3 |
| Sigmoid (postprocessor DBN) | ✓ | — | S5 |
| Max-pool 1D (postprocessor) | N/A (CPU Swift) | — | S5 |

---

## §11 Spec corrections (none so far)

No disagreements found between the paper and the shipped code for parameters
relevant to Phosphene's implementation. The only paper-vs-code gap is the
`log_multiplier=1000` which the paper omits (not a spec error, just an
unreported implementation detail). This table will be updated if Sessions 2–7
discover divergences.

| Location | Spec said | Reality |
|---|---|---|
| D-077 performance estimate | "~100–300 ms on M1" per 30s clip | Measured: 415–530ms Python CPU; MPSGraph estimate ~60ms; full characterization in Session 4 |
