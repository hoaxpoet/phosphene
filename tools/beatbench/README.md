# tools/beatbench — offline reference annotations (GT.2)

Independent beat/downbeat annotations to reconcile against Matt's taps. Where the
two agree within 70 ms the result becomes BeatBench ground truth; disagreements go
to Matt to arbitrate by ear (BEAT_SYNC_PROGRAM_PLAN.md §GT.2).

## License position

madmom and librosa run here as **offline annotation tools only**. No madmom code
and no CC-NC madmom model weights ship in the product; nothing here is linked into
PhospheneEngine or PhospheneApp. This is the permitted case in the `reference-port`
skill §1 (same precedent as the AGPL Essentia ground-truth tool).

## Why Beat This! is deliberately NOT a backend

Beat This! **is Phosphene's own grid model** (`BeatGridAnalyzer` = BeatThisPreprocessor
+ BeatThisModel + BeatGridResolver, D-077). Annotating with it and then scoring
Phosphene's grid against those annotations would be circular — it measures "did we
port the model correctly" (already covered by the DSP.2 S8 layer-match tests), not
"is the beat right". Ground truth has to come from outside that loop: human taps
plus a *different* algorithm family.

## Setup — two venvs, deliberately

madmom's compiled Cython extensions are pinned to numpy 1.x, and installing librosa
pulls numpy 2.x, which silently breaks them. Keeping the two backends in separate
venvs is what makes both work at once.

```bash
# librosa
/opt/homebrew/bin/python3.12 -m venv tools/beatbench/.venv
tools/beatbench/.venv/bin/pip install librosa soundfile

# madmom — order and flags both matter (see "madmom install" below)
/opt/homebrew/bin/python3.12 -m venv tools/beatbench/.venv-madmom
tools/beatbench/.venv-madmom/bin/pip install --upgrade pip "setuptools<81" wheel
tools/beatbench/.venv-madmom/bin/pip install "numpy<2" cython
tools/beatbench/.venv-madmom/bin/pip install --no-build-isolation --no-cache-dir \
    --no-binary madmom "git+https://github.com/CPJKU/madmom"
```

Python 3.12 specifically — system Python is 3.14, which fewer MIR packages support.
Both venvs are gitignored; the annotations they produce are committed.

## Running

```bash
export BEATBENCH_FIXTURES_DIR=~/phosphene_beatbench_fixtures
tools/beatbench/.venv/bin/python tools/beatbench/reference_annotate.py --list-backends
tools/beatbench/.venv/bin/python tools/beatbench/reference_annotate.py --backend librosa
tools/beatbench/.venv/bin/python tools/beatbench/reference_annotate.py --tracks bleed,take_five
```

Output: `PhospheneEngine/Tests/Fixtures/beatbench/reference/<track>.<backend>.json`
(existing files are skipped unless `--force`).

## Backend status

| Backend | State | Notes |
|---|---|---|
| madmom `0.17.dev0` | **working** (own venv) | RNN + DBN. The authoritative backend: a different algorithm family from Beat This!, produces downbeats, and decodes odd meters via `beats_per_bar=[3,4,5,7]`. Slow — roughly real-time, two networks per track — so run it detached. |
| librosa `0.11` | **working** (own venv) | Onset-envelope DP beat tracking. Fast, but no downbeats and a near-constant-tempo assumption: reliable on suite 1, misleading on suites 2/3. Treat as the weaker second opinion. |

### madmom install — the four causes, in order

madmom predates numpy 2 and fights modern packaging. Each failure had a distinct
cause; the flags in the setup block above are exactly what each one demanded:

1. `ModuleNotFoundError: pkg_resources` — setuptools ≥ 81 removed it → pin `setuptools<81`.
2. `numpy.core.multiarray failed to import` — extensions built against the wrong
   numpy → pin `numpy<2` **before** installing madmom, with `--no-build-isolation`.
3. `numpy.dtype size changed, Expected 96 … got 88` — 96 bytes is numpy 2's dtype, so
   pip had reused a **cached wheel** built during an earlier attempt → `--no-cache-dir`.
4. `BackendUnavailable: Cannot import 'mesonpy'` — `--no-binary :all:` forced *numpy*
   to build from source too → scope it: `--no-binary madmom`.

Keep madmom in its own venv. Installing librosa beside it upgrades numpy to 2.x and
re-breaks the compiled extensions with failure (2).

### Running madmom

Real-time-ish, so detach it and poll:

```bash
nohup tools/beatbench/.venv-madmom/bin/python tools/beatbench/reference_annotate.py \
    --backend madmom > ~/phosphene_beatbench_fixtures/madmom_run.log 2>&1 &
```
