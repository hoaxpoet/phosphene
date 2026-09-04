# PR.12 — the beat analyzer discards ~90 % of every track, and the evidence against fixing it was an artifact

**Matt, 2026-09-04:** *"you need to rethink the beat analyzer — it cannot throw away 80% or more of a
track"*, then *"the problem is beat averaging, which does not make sense if the tempo of the music
changes"*, then *"you should not be averaging BPM / tempo, you should be recording it over the
duration of the track so that visuals are better synced."*

All three are correct, and the last one describes a data structure Uzume already has.

## 1. What the code does

`BeatThisModel.tMax = 1500` frames = **exactly 30 s at 50 fps**, hard-clamped in `predictCore`.
**Nothing in the beat-grid path branches on local vs streaming.** A Spotify preview *is* 30 s, so the
clamp costs it nothing. A local FLAC is decoded in full, handed to the analyzer in full, and then
truncated.

Measured span of the shipping grid, per fixture: **6.7 %–11.4 % of the track.**

## 2. Why that produces drift — the mechanism, exactly

`BeatGrid.beats` holds real detected beat times. It is already a tempo record over the duration of
the track: consecutive beat times ARE the local tempo, and `BeatGrid.localTiming(at:)` uses them:

```swift
if idx + 1 < beats.count {
    period = beats[idx + 1] - beats[idx]   // real local period — follows the music
} else if bpm > 0 {
    period = 60.0 / bpm                    // the whole-track AVERAGE
}
```

So the system already does the right thing wherever beats exist. The averaged `bpm` is the fallback
for time **past the end of the beats array** — and the clamp ends that array at 30 s. A six-minute
track therefore gets 30 s of true tempo followed by 5.5 minutes of one averaged number, and a
constant period against varying music is a linear phase error. **That is PR.1's ramp** (11 of 13
*Low* segments, R² 0.63–0.91) and it is BUG-065.

`BeatGridResolver.computeBPM` is the averaging step: mean of the inlier inter-onset intervals across
the whole input. `computeMeter` then derives `beatsPerBar` **from that average** — which is why the
degenerate meters chased all session (bleed 4→2, money 7→1) are downstream of the averaging rather
than a separate defect.

## 3. The evidence against whole-track decoding was a measurement artifact

D-210, FT.4.1 and BUG-107 all rest on "full-track decode makes beat tracking worse", anchored on
bleed 115.00 → 123.62. **BeatBench trims the reference to each grid's own span** — so the 30 s grid
is scored on 30 s of music and the whole-track grid on six minutes. Not the same exam, and the
shorter one is the opening of the track, which is the most regular part. (FT.4 noticed a version of
this — *"only 4 of 9 tracks can be compared fairly"* — but the conclusion stood anyway.)

Scored over an **identical span** (the clamp's own first ~30 s), beat F-measure at ±70 ms:

| track | 30 s clamp | whole-track | clamp coverage |
|---|---:|---:|---:|
| billie_jean | 0.97 | **0.98** | 9.9 % |
| **bleed** | 0.99 | **1.00** | 6.7 % |
| bohemian_rhapsody | 0.47 | **0.49** | 8.2 % |
| clair_de_lune | 0.14 | **0.15** | 10.0 % |
| money | 0.44 | 0.43 | 6.8 % |
| pyramid_song | 0.52 | 0.52 | 9.9 % |
| solsbury_hill | 0.97 | **1.00** | 11.4 % |
| take_five | 0.99 | **1.00** | 9.1 % |
| yyz | 0.58 | **0.63** | 10.0 % |

**Equal or better on 8 of 9; one marginally worse (money, 0.44 → 0.43).** bleed — the track the
disqualification was built on — improves. There is no beat regression from decoding the whole track.

## 4. Two stitching mechanisms tested and rejected before this was found

Both null, both recorded so nobody retries them:

- **Edge taper** on the overlap-add (the standard answer to window-edge conditioning). bleed
  123.62 → 124.41. No effect.
- **Nearest-centre, no averaging at all** — each frame takes the prediction of the window whose
  centre it is closest to. bleed → 124.68. No effect.

The stitching was never the problem, which is what pointed at the scoring instead.

## 5. What this implies (not yet built)

1. **Analyse the whole track on the local-file path.** The audio is already there; the clamp is a
   streaming constraint applied where it does not apply.
2. **Stop letting an averaged BPM be load-bearing.** With beats spanning the track, `localTiming`
   never reaches its `60.0 / bpm` fallback and the drift has nowhere to come from. `bpm` survives as
   a display/summary value.
3. **`computeMeter` must stop deriving from the average** — it should use local period.
4. **Streaming needs a different answer.** 30 s really is all there is up front, so its improvement
   has to come from live adaptation, not offline analysis. One clamp cannot serve both paths.

Cost is real and unmeasured here: whole-track inference is ~10–14 model windows instead of one, on a
path that already misses its preparation budget by ~6.7× (D-242 / PREP.1). That trade is a product
decision, not an engineering one.


---

## 6. SHIPPED — the local path now analyses the whole track

Matt, 2026-09-04: *"fix the local path to analyze the whole track."*

`BeatGridAnalyzing.analyzeBeatGrid` gains `wholeTrack:`; a protocol extension keeps the old
two-argument form as the streaming-shaped call, so every existing call site (tests, BeatBench,
diagnostics) is untouched. `SessionPreparer.analyzePreview` gains `wholeTrackAudio: Bool = false`
and threads it to both grids (full-mix and drums). **Only the local-file call site passes `true`** —
`VisualizerEngine+LocalFilePlayback`, which is the same seam DYN.1c already uses for
`loudnessProfile` on the grounds that only that call site knows the decode was of the whole file.
Streaming is unchanged by construction: its input is a 30 s preview and there is nothing more to
analyse.

### Measured on Bowie's *Low*, all 11 tracks

| track | length | grid span before | before | grid span after | after |
|---|---:|---:|---:|---:|---:|
| 01 Speed Of Life | 167 s | 28 s | 16.8 % | 164 s | **98.0 %** |
| 02 Breaking Glass | 113 s | 29 s | 26.0 % | 110 s | **97.5 %** |
| 03 What In The World | 143 s | 30 s | 20.9 % | 142 s | **99.0 %** |
| 04 Sound And Vision | 183 s | 30 s | 16.1 % | 181 s | **98.8 %** |
| 05 Always Crashing | 214 s | 29 s | 13.6 % | 197 s | **92.2 %** |
| 06 Be My Wife | 177 s | 30 s | 16.8 % | 173 s | **98.0 %** |
| 07 A New Career | 173 s | 29 s | 16.9 % | 169 s | **97.7 %** |
| **08 Warszawa** | 384 s | 29 s | **7.6 %** | 369 s | **96.3 %** |
| 09 Art Decade | 227 s | 29 s | 12.8 % | 220 s | **97.0 %** |
| 10 Weeping Wall | 208 s | 30 s | 14.3 % | 203 s | **97.7 %** |
| 11 Subterraneans | 339 s | 29 s | 8.6 % | 335 s | **98.7 %** |

**Every track goes from 7.6–26 % covered to 92–99 % covered.** Past the covered span
`localTiming` falls back to the averaged BPM; that fallback now has almost nowhere to fire, so the
drift it caused has almost nowhere to come from.

### Cost — much smaller than feared

Beat-grid analysis over the whole album: **2.2 s → 5.1 s, +2.9 s total, ~0.26 s per track.** PREP.1
measured the local path at ~50 s/track, so this is **~0.5 % of the preparation budget**. My earlier
warning that "10–14 model passes instead of one" would meaningfully worsen preparation was wrong —
the windows are GPU inference and cheap.

### Gated

`WholeTrackGridWiringTests` asserts the default call stays clamped, an explicit request reaches the
analyzer, and a whole-track grid spans a five-minute input while a clamped one does not. The wiring
is what a refactor silently breaks, so that is what is gated.

### Not done here

- **`computeMeter` still derives `beatsPerBar` from the averaged `bpm`.** With beats now spanning
  the track it should use local period; until it does, the degenerate meters stay downstream of an
  average that matters much less than it did.
- **Streaming is untouched and still has the problem in its own form** — 30 s is all it gets, so its
  answer has to be live adaptation, not offline analysis.
- **No live confirmation.** Coverage and cost are measured; whether Matt *feels* the sync improve
  needs a session on the new build.
