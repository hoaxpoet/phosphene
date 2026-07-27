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

## Setup

```bash
/opt/homebrew/bin/python3.12 -m venv tools/beatbench/.venv
tools/beatbench/.venv/bin/pip install librosa soundfile
```

Python 3.12 specifically — system Python is 3.14, which fewer MIR packages support.
The venv is gitignored; the annotations it produces are committed.

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
| librosa | **working** | Onset-envelope DP beat tracking. Genuinely independent of Beat This!, but weak where it matters most: no downbeats at all, and a near-constant-tempo assumption that suits suite 1 and misreads suites 2/3. |
| madmom | **not working on this machine** | RNN + DBN; the backend we actually want (different algorithm family, handles odd meters via `beats_per_bar`, produces downbeats). |

### madmom — what was tried, and what is left

madmom 0.16.1 (2018) is the last release and predates numpy 2. Two install attempts
were made on Python 3.12, then stopped per the program's two-strikes rule (plan §7):

1. `pip install --no-build-isolation madmom` after `numpy<2` + Cython — compiled
   (rc=0) but failed at import: `ModuleNotFoundError: pkg_resources` (setuptools ≥81
   removed it). Fixed by pinning `setuptools<81`, which exposed the next failure.
2. Force-reinstalled `numpy==1.26.4` and rebuilt madmom — still
   `ImportError: numpy.core.multiarray failed to import`, i.e. the Cython extensions
   were not actually rebuilt against the pinned numpy. Installing librosa then pulled
   numpy back to 2.x, so the extensions are ABI-mismatched either way.

Untried options, in the order worth attempting when someone returns to this:

- madmom from GitHub master (`pip install git+https://github.com/CPJKU/madmom`), which
  carries numpy-2 fixes not in the 2018 PyPI release;
- a dedicated venv pinned to `numpy<2` with **no** librosa in it, so nothing upgrades
  numpy underneath the compiled extensions;
- Python 3.10/3.11, closer to what madmom was built against.

**Consequence while madmom is missing:** the reference cross-check is weakest exactly
where the suites are hardest — odd meters (2), tempo changes (3), and downbeats
everywhere. Matt's taps remain the primary ground truth and are unaffected; the
cross-check simply flags fewer tap errors on those tracks, so more of them land in
the "arbitrate by ear" pile rather than being auto-confirmed.
