# BeatBench ground-truth session — 2026-07-27T12-58-56Z

The full 15-track beat-match testing playlist, streamed from Spotify and captured
by `SessionRecorder`. Source of the 4 tap-derived BeatBench fixtures (GT.1 hybrid)
and the seed for the live-replay scoring path (GT.3).

Session dir: `~/Documents/phosphene_sessions/2026-07-27T12-58-56Z/` (raw_tap.wav +
features.csv + stems.csv + stems/ + session.log). **Not in the repo** — local-only,
like the audio fixtures.

## Vitals

- Duration ~5322 s (~88.7 min); 318,384 feature frames; continuous.
- Tap healthy throughout: `band=healthy peak≈-7.5 dBFS deadTap=false rate=48000`. The
  brief `silent` at 13:02:47–49 is pre-playback (no signal yet), recovered to `active`
  before track 1. No BUG-057 wedge.
- `SOURCE=spotifyPreFetched`, 15 tracks, grids from the 30 s previews (prep phase);
  the raw_tap holds the real full-length audio.

## Per-track tap windows

Segment boundaries from `track_elapsed_s` resets, track identity confirmed by median
`grid_bpm` fingerprint (robust to the 2 spurious splits — an 8.4 s Billie Jean pre-roll
fragment + a 2.3 s tail). Windows are seconds into raw_tap.wav.

| # | Track | Suite | tap start→end (s) | preview grid_bpm |
|---|---|---|---|---|
| 1 | Billie Jean | 1 | 0.0 → 300.8 | 117.0 |
| 2 | Around the World (studio 7:09, not the corpus Alive medley) | 1 | 300.8 → 732.3 | 121.3 |
| 3 | Stayin' Alive | 1 | 732.3 → 1016.8 | 103.7 |
| 4 | Superstition | 1 | 1016.8 → 1283.4 | 100.3 |
| 5 | Take Five | 2 | 1283.4 → 1614.3 | 166.4 |
| 6 | Money | 2 | 1614.3 → 1994.6 | 123.2 |
| 7 | **Solsbury Hill** (→ fixture) | 2 | 1994.6 → 2256.6 | 102.5 |
| 8 | Pyramid Song | 2 | 2256.6 → 2544.4 | 70.0 |
| 9 | **Bohemian Rhapsody** (→ fixture) | 3 | 2544.4 → 2900.0 | 71.0 |
| 10 | Dance Yrself Clean | 3 | 2900.0 → 3437.5 | 98.0 |
| 11 | **YYZ** (→ fixture; Rush, 10/8) | 2 | 3437.5 → 3703.9 | 141.1 |
| 12 | **Bleed** (→ fixture) | 4 | 3703.9 → 4146.3 | 174.6 |
| 13 | Giorgio by Moroder | 3 | 4146.3 → 4692.6 | 113.2 |
| 14 | The Girl from Ipanema | 5 | 4692.6 → 5012.0 | 128.4 |
| 15 | Clair de Lune | 5 | 5012.0 → 5320.0 | 79.6 |

The 4 bold tracks were extracted to `BEATBENCH_FIXTURES_DIR` as Float32 WAV
(`ffmpeg -ss … -t … -c copy`) and hashed into the manifest.

## Benchmark-relevant observations (not session faults)

The prep-phase 3-way BPM disagreements (full-mix grid vs drums-stem vs MIR autocorr)
are exactly the hard cases the suites exist to measure — recorded here as the pre-GT.3
baseline expectation, **not** defects:

- **Bleed** — grid 174.6 vs drums 115.1 (34 %): the full-mix grid tracks a subdivision
  while the drums stem tracks the quarter-note. The category-4 lever (TRK.2).
- **Pyramid Song** — grid 70.0 vs drums 164.3 (57 %): grouped/rubato-adjacent.
- **Stayin' Alive** — grid 103.7 (correct) vs drums 152.4 (32 %).
- **Clair de Lune** — grid 79.6 vs drums 69.8, MIR 138.5: true rubato, no stable grid
  (the category-5 "decline honestly" case).
- `mir_bpm` clusters ~134–138 across many tracks — a known full-mix autocorrelation
  fallback quirk; the grid is the trusted value.

YYZ (Rush) was added as a 16th-slot benchmark track for its 10/8 odd meter (suite 2).
