# Murmuration motion reference clips

Drop folder for the murmuration motion-reference video(s) that drive the Phase MM temporal
contract (see `docs/presets/MURMURATION_DESIGN.md` §3 / §9.1).

## How to use

1. Drop one or more clips in this directory. **Any name, `.mp4` or `.mov` both fine** (e.g.
   `clip1.mp4`). Raw video + the `frames/` directory are git-ignored — they are not committed.
2. Claude extracts frames with `ffmpeg` (e.g. 2 fps to `frames/`) and reads them to analyze:
   shape morphing, density gradient, how orientation waves propagate, drift speed, and the
   calm-vs-event rhythm. Findings feed the §3 magnitudes for MM.3 tuning.

Example extraction (run by Claude):
```
ffmpeg -i clip1.mp4 -vf fps=2 frames/clip1_%04d.png
```

The committed artifact from this analysis is a written motion breakdown in the design doc, not the
frames themselves.
