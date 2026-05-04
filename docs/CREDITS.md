# Credits

Phosphene is MIT-licensed (see `LICENSE`). It bundles third-party model
weights and reference code under their own licenses, listed below.
Downstream redistributors must preserve these notices.

---

## BeatNet — beat / downbeat tracking weights

**Used in:** `PhospheneEngine/Sources/ML/Weights/beatnet/` (vendored
weights), `Scripts/convert_beatnet_weights.py` (converter — derived
from BeatNet's published architecture).

**Source:** Mojtaba Heydari, Frank Cwitkowitz, Zhiyao Duan.
*BeatNet: CRNN and Particle Filtering for Online Joint Beat, Downbeat,
and Meter Tracking.* Proceedings of the 22nd International Society for
Music Information Retrieval Conference (ISMIR), 2021.

**Repository:** https://github.com/mjhydri/BeatNet

**Specific artifact:** `src/BeatNet/models/model_1_weights.pt` (GTZAN-
trained variant), retrieved from the `main` branch on 2026-05-03.

**License:** Creative Commons Attribution 4.0 International
(CC-BY-4.0) — https://creativecommons.org/licenses/by/4.0/legalcode

**Attribution (CC-BY-4.0 §3(a)) — required wherever the weights or
derivative code are distributed:**

> BeatNet weights © Mojtaba Heydari et al., used and modified under
> the Creative Commons Attribution 4.0 International License
> (CC-BY-4.0). Source: https://github.com/mjhydri/BeatNet. Original
> publication: Heydari, M., Cwitkowitz, F., Duan, Z. *BeatNet: CRNN
> and Particle Filtering for Online Joint Beat, Downbeat, and Meter
> Tracking.* ISMIR 2021. Modifications: PyTorch state_dict converted
> to flat float32 little-endian binary tensors with accompanying
> JSON manifest for MPSGraph inference. No model parameters were
> retrained or fine-tuned.

**Modifications (per CC-BY §3(a)(1)(B)):** original `.pt` checkpoint
re-encoded to one `.bin` file per tensor + `manifest.json`. Tensor
values are byte-identical to the source after dtype + endianness
normalization. No retraining or fine-tuning.

**Disclaimer (CC-BY §5):** the weights are distributed as-is. The
authors disclaim warranties to the maximum extent permitted by law.
See license text for the full disclaimer.

---

## Beat This! — beat / downbeat tracking weights

**Used in:** `PhospheneEngine/Sources/ML/Weights/beat_this/` (vendored
weights), `Scripts/convert_beatthis_weights.py` (converter),
`Scripts/dump_beatthis_reference.py` (reference fixture generator).

**Source:** Francesco Foscarin, Jan Schlüter, Gerhard Widmer.
*Beat This! Accurate Beat Tracking Without DBN Postprocessing.*
Proceedings of the 25th International Society for Music Information
Retrieval Conference (ISMIR), 2024.

**Repository:** https://github.com/CPJKU/beat_this

**Specific artifact:** `small0` variant checkpoint
(`beat_this-small0.ckpt`, downloaded via `torch.hub` from the JKU
cloud), at commit `9d787b9797eaa325856a20897187734175467074`,
retrieved 2026-05-04.

**License:** MIT — https://opensource.org/licenses/MIT

```
Copyright 2024 Institute of Computational Perception, JKU Linz, Austria

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Preferred citation:**

```bibtex
@inproceedings{foscarin2024beat,
  title={Beat This! Accurate Beat Tracking Without DBN Postprocessing},
  author={Foscarin, Francesco and Schl{\"u}ter, Jan and Widmer, Gerhard},
  booktitle={Proceedings of the 25th International Society for Music
             Information Retrieval Conference (ISMIR)},
  year={2024}
}
```

**Modifications:** PyTorch Lightning checkpoint re-encoded to one `.bin`
file per tensor + `manifest.json`. Five training-only `num_batches_tracked`
int64 buffers omitted (not used at inference). All float32 tensor values
are byte-identical to the source after endianness normalization. No
retraining or fine-tuning.

---

## Open-Unmix HQ — stem separation weights

**Used in:** `PhospheneEngine/Sources/ML/Weights/` (vendored weights
for `vocals`, `drums`, `bass`, `other`).

**Source:** Fabian-Robert Stöter, Stefan Uhlich, Antoine Liutkus,
Yuki Mitsufuji. *Open-Unmix — A Reference Implementation for Music
Source Separation.* Journal of Open Source Software, 2019.

**Repository:** https://github.com/sigsep/open-unmix-pytorch

**License:** MIT (code) — model weights distributed under the same
permissive terms via `umxhq` package on PyPI / Zenodo.

**Modifications:** PyTorch state_dict → flat `.bin` per-tensor with
JSON manifest for MPSGraph inference (mirrors the BeatNet treatment
above). BatchNorm folded into the preceding linear layer at
MPSGraph init time, not at conversion.

---

## Other dependencies

System frameworks (Apple): Metal, MetalKit, MetalPerformanceShadersGraph,
AVFoundation, Accelerate, ScreenCaptureKit, MusicKit. Used under the
terms granted by Apple to macOS developers; no separate attribution
required.

---

If you ship a derivative of Phosphene, you must:

1. Preserve the MIT notice in `LICENSE`, the BeatNet CC-BY notice, and
   the Beat This! MIT notice in this file.
2. Make this `CREDITS.md` (or an equivalent compilation of the
   notices) reachable from a user-visible surface — e.g. an "About"
   panel — alongside license text or hyperlinks.
3. Note any modifications you make to the bundled weights.

Open an issue if you spot a missing attribution.
