---
name: reference-port
description: Invoke before implementing any algorithm from a paper or external reference implementation (DSP, ML, decoding). Covers license gates, spec-fidelity discipline, and activation-level verification. The porting skill for the beat-sync program (D-202) and any reference-derived engine work.
---

# reference-port — porting algorithms from papers and reference implementations

Load before writing a line of a ported algorithm. Three gates: is it license-clean to port, is the port spec-faithful, and does a numerical test prove it matches the reference. Shader/GLSL porting discipline (colour space, clock, loop-wholesale) lives in `shader-authoring`; this skill is for DSP/ML/decoding algorithm ports.

## 1. License gate

Check the license **before** reading the reference to port it. Portability is by the reference's license, and separately by whether trained weights ship.

| Source kind | Rule | Precedent |
|---|---|---|
| MIT / BSD code | Portable into the product with attribution (retain the copyright line; note the source in a code comment + the design doc). | Beat This! (MIT) port, D-077 |
| AGPL code | **Never** ships in the product — incompatible with Phosphene's MIT license. Do not port, do not vendor. | TempoCNN rejected as AGPL (DECISIONS D-077) |
| CC-NC / non-commercial model weights | **Never** ship. A permissively-licensed *port of an algorithm* is fine; shipping restricted *weights* is not. | madmom's CC-NC models never ship (DECISIONS D-077) |
| Restricted tool, used offline only | Running a restricted tool (madmom DBNBeatTracker, a PyTorch reference) as an **offline annotation / cross-check tool** is fine — its output informs ground truth or validates a port, and nothing from it ships. | madmom + Beat This! reference as offline annotators (plan §GT.2, D-202) |

When in doubt about a license, stop and surface it to Matt rather than porting on assumption.

## 2. Spec fidelity

Paraphrased-from-prose specs land code that diverges silently from the reference. This has bitten twice — the D-075 trimmed-mean IOI fix, then the **BeatNet pivot (D-077)**: a DSP.2 audit found the architecture doc had paraphrased the FFT spec (`fft_size=2048` next-pow2) when madmom's actual default was `fft_size=frame_size=1411, include_nyquist=False`. The wrong spec had already produced diverging code three sessions downstream. That is the cautionary case.

- **Cite formulas to the paper equation, never paraphrase from memory.** "Eq. 4 of Krebs et al. 2015" — not a prose restatement. If you cannot cite the equation, you do not yet understand it well enough to port it.
- **Every ported constant carries a source citation or an explicit tunable marker.** Either `// paper §3.2, transition penalty λ = 100` or `// our tunable, default X` — never an unattributed magic number. A constant with neither provenance is a bug waiting to be mistuned.
- **Spec docs precede code.** The decoder-family increments author a written spec (from the papers) with every constant sourced-or-marked before implementation (plan DBN.1). Resolve the DECISION-NEEDED list with Matt before writing the port.

## 3. Verification methodology — the DSP.2 S8 pattern

A port is not done until a numerical test proves it matches the reference, boundary by boundary. This is how the Beat This! port converged (four bugs — frontend block order, stem reshape, BN1d padding, RoPE pairing — each invisible end-to-end but caught at a stage boundary).

- **Dump the reference's intermediate activations and commit them as fixtures.** `BeatThisActivationDumper` (Swift-side diagnostic) and the Python reference produce per-stage/per-frame activations; the committed fixture is the golden (e.g. `docs/diagnostics/DSP.2-S8-python-activations.json` + the audio fixture). The engine exposes a `predictDiagnostic(...)` path as the layer-diff anchor.
- **Stage-match tests, not just end-to-end.** The `BeatThisLayerMatch` test family asserts per-stage min/max/mean within tolerance at every pipeline boundary; per-bug regression gates (`BeatThisBugRegression`, `BeatThisStemReshape`, `BeatThisRoPEPairing`) lock each fixed divergence. End-to-end coverage alone hides which stage drifted. Follow this shape for a new port; don't copy the test code — mirror the per-boundary structure against the new reference's stages.
- **Fail loud on missing fixtures (QR.3 doctrine).** A fixture-presence gate (`BeatThisFixturePresenceGate` precedent) **reds the suite when a fixture is absent — it never skips.** A silently-skipped verification is a supply-chain hole; the port must be un-verifiable-loudly, not quietly-unverified.
- **When a Python reference exists, build the `tools/` venv cross-check first, port second.** The venv reference is what generates the activation fixtures and reconciles annotations; standing it up before porting means the port has a target to match from line one.
