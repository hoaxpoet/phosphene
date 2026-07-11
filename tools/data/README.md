# tools/data

Corpus and calibration artifacts for the corpus tools (`CorpusCensusRunner`,
`TonalDumper`, `tools/census_report.py`).

- `corpus_manifest.csv.gz` — full per-track manifest of the analysis corpus
  (27,639 tracks; produced by `tools/corpus_manifest.py scan`).
- `corpus_pilot_1000.csv` — deterministic seed-42 stratified 1,000-track
  pilot sample (produced by `tools/corpus_manifest.py pilot`).
- `mood_scaler.json` — MoodClassifier input-feature means/scales from the
  CENSUS pilot run (see `docs/diagnostics/CENSUS_PILOT_REPORT.md`).

The audio the manifests describe lives on the maintainer's corpus volume
(`/Volumes/Extreme SSD`), not in the repo — the manifests are metadata only.

To regenerate:

```bash
python3 tools/corpus_manifest.py scan --root "/Volumes/Extreme SSD" --out /tmp/corpus_manifest.csv
python3 tools/corpus_manifest.py pilot --manifest /tmp/corpus_manifest.csv --out tools/data/corpus_pilot_1000.csv
```
