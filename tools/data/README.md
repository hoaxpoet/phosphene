# tools/data

Aggregate calibration artifacts for the corpus tools. Only **aggregate**
statistics are committed here; per-track corpus manifests are private and
stay local.

- `mood_scaler.json` — MoodClassifier input-feature means/scales from the
  CENSUS pilot run (aggregate only; see `docs/diagnostics/CENSUS_PILOT_REPORT.md`).

## Regenerating the private manifests (maintainer-local)

`corpus_manifest.csv.gz` and `corpus_pilot_1000.csv` were removed from the
repo at PUB.1 (they itemized a private music library). The tools that consume
them (`CorpusCensusRunner`, `TonalDumper`, `tools/census_report.py`) still
work — regenerate locally with the corpus volume mounted:

```bash
python3 tools/corpus_manifest.py scan --root "/Volumes/Extreme SSD" --out /tmp/corpus_manifest.csv
python3 tools/corpus_manifest.py pilot --manifest /tmp/corpus_manifest.csv --out tools/data/corpus_pilot_1000.csv
```

Both output paths are gitignored; do not re-commit them.
