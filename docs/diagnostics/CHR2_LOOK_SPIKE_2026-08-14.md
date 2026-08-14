# CHR.2 — Stave look spike: the two-half gate, answered (2026-08-14)

**Increment:** CHR.2 (MD.6 uplift #8 candidate, source `Martin - charisma`).
**Status:** spike rendered and gated. Nothing registered — preset count stays 28, no
sidecar, no golden, no `certified` flag. The verdict is the deliverable; the code is
`PhospheneEngine/Tests/PhospheneEngineTests/Presets/StaveLookSpike.swift` and is
proposed as CHR.3's skeleton (see §7).

**The driver, settled by Matt 2026-08-13 and used unchanged here:**

| layer | driver | latency |
|---|---|---|
| trace position | band split — rhythm `subBass+lowBass`, melodic `midHigh+highMid+high`, each EMA-centred | ≈0.3 s |
| trace colour + weight | per-stem — `drums+bass` vs `vocals+other` | ≈3.0 s (measured, §4) |

---

## 0. ⚠ Correction to CHR.1's §4 table — read before citing it

`CHR1_STEM_DECORRELATION_2026-08-11.md` §4's common-mode table has **shifted track
labels**, and the corrected figures were never committed to this repo. The CHR.2 prompt
carried corrected numbers; this increment settled the conflict by **re-measuring from
`stems.csv` directly** rather than trusting either source. The re-measurement reproduces
the prompt's figures exactly (Bohemian Rhapsody 93.4 %, Take Five 82.9 %) and contradicts
the committed table (which assigns Take Five 93.0 %).

**Consequence for anyone resuming:** CHR.1 §5 bullet 3 asserts *"Jazz is the worst
(Take Five, 93.0 %)"*. That is the label shift showing. Take Five is **among the
easiest** cases. Do not repeat the "jazz is hardest" reasoning. A correction banner has
been added to the CHR.1 file.

**Corrected common-mode share** (fraction of each per-stem trace's motion that is the
mix's shared loudness envelope; null ≈22 %), all 15 full-length tracks of
`beat-match-test-session`, measured this increment:

| track | common-mode | | track | common-mode |
|---|---|---|---|---|
| Bohemian Rhapsody | **93.4 %** | | YYZ | 87.4 % |
| Superstition | **93.1 %** | | Giorgio by Moroder | 87.1 % |
| Stayin' Alive | 92.5 % | | Billie Jean | 86.3 % |
| Dance Yrself Clean | 91.6 % | | The Girl From Ipanema | 84.6 % |
| Around the World | 89.9 % | | Take Five | **82.9 %** |
| Bleed | 88.7 % | | Solsbury Hill | 81.2 % |
| Money | 88.4 % | | | |
| Pyramid Song | 88.1 % | | | |
| Clair De Lune | 88.0 % | | | |

---

## 1. Capture set (task 1) — picked from the re-measurement

| capture | why | measured |
|---|---|---|
| **Bohemian Rhapsody** | the corpus's genuine worst common-mode case | 93.4 % common mode |
| **Bleed** | low-excursion end — where a trace-amplitude floor is needed | p95\|R\| 0.514, p95\|M\| 0.062 |
| **Dance Yrself Clean** | high-excursion end | p95\|R\| 1.908, p95\|M\| 0.110 |
| **Clair De Lune** | sparse material, legibility at the easy end | 88.0 % common mode |

Bleed↔Dance Yrself Clean bound a **3.7× rhythm-trace excursion span** that one fixed
gain has to survive. (The prompt anticipated ~7×; measured on the summed EMA-centred
pairs the span is 3.7× on rhythm and 1.8× on melodic.)

⚠ Jazz was **not** picked as a hard case — see §0.

---

## 2. What the measurement said before a pixel was drawn

Three findings that shape how the renders must be read.

### 2.1 The melodic trace is 4.4–17.5× quieter than the rhythm trace

| | std R (rhythm) | std M (melodic) | ratio |
|---|---|---|---|
| Bohemian Rhapsody | 0.415 | 0.083 | 5.0× |
| Bleed | 0.280 | 0.041 | 6.8× |
| Dance Yrself Clean | 0.823 | 0.062 | 13.2× |
| Clair De Lune | 0.394 | 0.069 | 5.7× |
| corpus range | 0.215–0.823 | 0.026–0.083 | 4.4–17.5× |

At a shared gain the melodic trace is a flat line. **Per-trace gain is therefore not a
tuning choice, it is a precondition** for the melodic voice existing on screen at all.
The spike uses fixed gains (rhythm ×0.54, melodic ×3.72, chosen so the corpus-median p95
lands at ~0.35 NDC) so the gate can see whether one fixed pair survives the span.

### 2.2 The divergence ratio that justified the two-trace concept is mostly amplitude

CHR.1 §7a gated direction A on `divergence = std(R−M) / mean(std R, std M)` = 1.88
against a 1.45 independence null. But that statistic inflates toward 2.0 whenever
`std R ≫ std M`, with no anti-correlation involved. Recomputed on the **drawn**
(gain-normalised) traces — which is what a viewer sees — it collapses onto
`√(2(1−r))`, i.e. it carries no information beyond `r`:

| track | div (raw) | div (as drawn) | r | √(2(1−r)) |
|---|---|---|---|---|
| Bohemian Rhapsody | 1.73 | 1.49 | −0.080 | 1.47 |
| Dance Yrself Clean | 1.86 | 1.46 | +0.041 | 1.39 |
| Clair De Lune | 1.77 | 1.52 | −0.155 | 1.52 |
| **Bleed** | 1.57 | **0.78** | **+0.695** | 0.78 |
| The Girl From Ipanema | 1.89 | 1.53 | +0.030 | 1.39 |

**This is not bad news for the concept, but it relocates the evidence.** The real
support for "two voices" is `r` itself, which sits at **−0.27…+0.27 on 13 of 15
tracks** — near-independent, which is exactly the property wanted. What does *not*
survive is the stronger "see-saw / converge-and-diverge" claim: the anti-correlation is
small (worst −0.27) and **Bleed is a measured counter-example at r +0.695**, where the
two traces genuinely do move together.

### 2.3 The traces land on the beat with no systematic lag — but loosely

The driver decision was made to buy in-time marks; task 3 says verify it. Offset from
each beat gridline to the nearest local maximum of each trace, on the **render clock**:

| track | beats | trace | median offset | IQR | \|off\| < 80 ms |
|---|---|---|---|---|---|
| Bohemian Rhapsody | 374 | R | 0 ms | 216 ms | 32 % |
| Bohemian Rhapsody | 374 | M | 0 ms | 199 ms | 28 % |
| Bleed | 927 | R | 0 ms | 133 ms | 52 % |
| Superstition | 421 | R | 0 ms | 182 ms | 44 % |
| Clair De Lune | 382 | R | 16 ms | 317 ms | 19 % |
| Dance Yrself Clean | 515 | R | −98 ms | 249 ms | 17 % |

**Median ≈ 0 ms on every track: the band driver delivered what it was chosen for — no
systematic latency against the grid.** But the traces carry more extrema than there are
beats (Bleed: 1605 peaks vs 927 beats), so "nearest peak" is biased toward zero and the
informative columns are the IQR and the <80 ms rate. Those say the correspondence is
**loose**: a continuous trace wiggles between beats as well as on them.

⚠ **Instrument note — not a defect, a wrong axis.** `accumulatedAudioTime` is
**energy-weighted by definition** (`+= max(0, energy) * deltaTime`, ARCHITECTURE.md
§1276), so it advances far slower than wall-clock and at a rate that varies with the
music: Dance Yrself Clean accumulates 42.5 s across 537 s of playback, ~12×. That is the
documented behaviour. The mistake was mine — measuring these offsets on it first, which
read 1–14 ms, a false pass by roughly that same factor. **A time-series plot needs a
uniform time axis, so it must use `time` (the render clock); `accumulatedAudioTime` is an
animation phase, not a clock.** Every figure above is on `time`.

---

## 3. Gate half 1 — geometry: **PASS on 3 of 4, with two qualifications**

180-frame sequences per capture at 1067×750, 20 Hz plot, 8 s scrolling window.

**Frames are not committed** — `.gitignore:105` excludes `docs/diagnostics/**/*.jpg`, and
that policy is deliberate (repo-size). Regenerate any of them with:

```
python3 <slice script>                      # see §9, one-off, stdlib only
STAVE_SESSION=/tmp/stave_slices/<slug> STAVE_COLOUR=0|1 \
STAVE_OUT=/tmp/phosphene_visual/stave_spike/<slug>_<flat|colour> \
STAVE_COUNT=180 STAVE_STRIDE=3 STAVE_WARMUP=1200 \
  swift test --package-path PhospheneEngine --filter StaveLookSpike
```

| capture | two voices? | grid reads as beat? | traces land on gridlines? | fixed gain survives? |
|---|---|---|---|---|
| **Bohemian Rhapsody** | **yes** — distinct shapes, repeated crossings | yes, 9.4 lines/window at 71 bpm | median 0 ms, IQR 216 ms | melodic clips at peaks |
| **Clair De Lune** | **yes** — the clearest read of the four | partly — CV 0.20, whole regions unruled | median 6/−16 ms, IQR 250–317 ms | yes |
| **Dance Yrself Clean** | **yes** — rhythm spikes against a near-flat melodic | yes, 13.0 lines/window at 97 bpm | median −98 ms, IQR 249 ms | **no — clips off frame repeatedly** |
| **Bleed** | **no — the two traces collapse into one flat band** | reads as **graph paper**: 22.9 lines/window at 172 bpm | median 0 ms, IQR 133 ms | yes (nothing to clip) |

**Qualification 1 — Bleed is a genuine miss, and it was predicted.** §2.2 measured Bleed at
`r +0.695` / drawn divergence 0.78, the one track in the corpus where the two band traces
move together. The render matches the number exactly: both traces hug the centreline as a
single hairy band, and no amount of looking separates them into voices. This is the
concept's worst case and it is not fixable by tuning — it is what the material does.

**Qualification 2 — one fixed gain does not survive the excursion span.** Dance Yrself
Clean's rhythm trace leaves the top of the frame on every kick group, and Bohemian
Rhapsody's melodic trace clips at peaks (its p95 is 1.7× the corpus median the gain was
set from). A per-trace running normaliser would fix it, at the cost of destroying
absolute-amplitude comparison between quiet and loud passages — a real design trade, not
a bug, and CHR.3's to decide.

**What did NOT survive: the "converge and diverge" story.** §2.2 shows the divergence
statistic that justified it is dominated by the rhythm/melodic amplitude mismatch and
collapses onto `√(2(1−r))` once both traces are drawn at visible scale. What the renders
do support is **near-independence** — two lines going their own way, crossing often. That
is a good picture. It is not the band locking together and pulling apart, and the concept
sentence should stop claiming it.

**The beat grid is real.** Derived from `beatPhase01` wraps, the gridline rate matches
`grid_bpm` exactly on every track that has one (71/71, 97/98, 172/174.6) with inter-beat
CV 0.02–0.13. The grid is not decoration. Its problem is density, not accuracy: above
~150 bpm it stops reading as a pulse and starts reading as ruling.

---

## 4. Gate half 2 — colour: **FAIL as instrument identity; it works only as a label**

The evidence is the flat/coloured pair on the **identical frame** of Clair De Lune
(`clairdelune_flat/stave_seq_0090.png` vs `clairdelune_colour/stave_seq_0090.png`). Same
geometry, same frame; the only difference is whether the shader uses the stem channel.

**What the colour does deliver.** It separates the two traces decisively. In the flat
control the two white lines are ambiguous wherever they cross; in the coloured version
amber and cyan are followable throughout. The stem-driven brightness and weight are also
visible — segments thicken and brighten in bursts (clearest on Bohemian Rhapsody and
Dance Yrself Clean).

**Why that is not instrument identity.**

1. **The hue is a static label assigned by the position driver, not by the audio.** Amber
   is "the trace driven by `subBass+lowBass`", cyan is "`midHigh+highMid+high`". It never
   changes. A viewer learns which line is which — they learn nothing about what is playing.
2. **The label is asserted even where the instruments do not exist.** Clair De Lune is
   solo piano. Its traces are still labelled `drums+bass` and `vocals+other`. Both labels
   are false, and nothing in the image tells the viewer so.
3. **The decisive measurement: colour and position on the same mark are uncorrelated at
   the moment the mark is drawn.** Cross-correlating each trace's position driver against
   its own colour driver:

| capture | pair | best lag | r at that lag | **r at lag 0** |
|---|---|---|---|---|
| Bohemian Rhapsody | rhythm | 5.5 s | +0.748 | **−0.084** |
| Bohemian Rhapsody | melodic | 5.5 s | +0.315 | **−0.145** |
| Bleed | rhythm | 5.4 s | +0.770 | **+0.049** |
| Dance Yrself Clean | rhythm | 5.4 s | +0.875 | **−0.081** |
| Clair De Lune | rhythm | 5.4 s | +0.886 | **+0.150** |
| Clair De Lune | melodic | 5.4 s | +0.198 | **−0.018** |

   ⚠ **These renders are on the pre-BUG086.1 capture, where the stem lag is 5.4 s.**
   Re-measured on a post-fix capture (`2026-08-12T19-06-54Z`, current code) the lag is
   **3.0 s** — matching the driver table — with `r at lag 0` **+0.251** (rhythm) and
   **+0.005** (melodic). So CHR.3 would face a 3.0 s offset, not 5.4 s. The direction of
   the finding does not change: **a mark's colour is describing a moment about three
   seconds before the mark's own position, which on an 8 s window is 38 % of the screen
   away.** At lag 0 the melodic trace's colour carries essentially zero information about
   its own geometry.

**Honest summary, as the prompt asked for it.** Choosing band-driven position bought marks
that land on the beat, and it worked — median offset 0 ms. The price was exactly what was
predicted: instrument identity moved out of the geometry and into hue, and hue cannot
carry it. What a viewer can decode from the colour is *"which of the two traces is this"*
and *"this group is loud right now (three seconds ago)"*. What they cannot decode is which
instruments a trace is carrying. **This is a re-scope trigger, not a tuning prompt.**

---

## 5. Motion gate

`Scripts/motion_gate.sh stave <seq>` on all four coloured sequences (180 frames each):

| capture | mean / stdev | median / max | spikes >3× | frozen |
|---|---|---|---|---|
| Clair De Lune | 3.26 / 0.48 | 3.20 / 4.17 | **0 / 179** | 0 / 179 |
| Bohemian Rhapsody | 4.97 / 0.46 | 4.88 / 6.22 | **0 / 179** | 0 / 179 |
| Dance Yrself Clean | 6.17 / 0.67 | 6.00 / 7.74 | **0 / 179** | 0 / 179 |
| Bleed | 6.43 / 0.36 | 6.39 / 7.26 | **0 / 179** | 0 / 179 |

**Verdict: smooth, and the tool's verdict is directly usable here.** Read as a sequence
the traces translate coherently right-to-left; features persist across frames and no
structure pops. **Signal or defect: neither is flagged — there is nothing to adjudicate.**
The FTR caveat (that `motion_gate.sh` scores a beat-stepped preset's beats as jitter) does
**not** apply to Stave: its motion is continuous scrolling, not per-beat stepping, so the
frame-difference signal is steady by construction and the low stdev (0.36–0.67 against
means of 3.3–6.4) is a true smoothness reading rather than a masked one. The one thing the
gate cannot see is the §3 clipping, because a trace leaving the frame changes the
frame-difference signal no more than a trace inside it.

No reference set exists at `docs/VISUAL_REFERENCES/stave/` (CHR.1 correctly withheld it
under its task-4 hard stop), so `Scripts/compare_render.sh stave` cannot run and no
per-trait reference verdict table exists for this increment. That is a stated gap, not an
oversight — curating references is CHR.1's unfinished half and belongs with CHR.3.

---

## 6. Verdict

| gate half | verdict |
|---|---|
| **1 — geometry** | **PASS on 3 of 4 captures.** Two band-driven traces read as two voices. Bleed is a measured, predicted miss. The grid is genuinely the beat. Two fixable qualifications (fixed gain clips; dense grids read as graph paper). The "converge and diverge" claim does not survive and should be dropped. |
| **2 — colour** | **FAIL.** Stem-driven colour separates the traces but cannot carry instrument identity, because at 3.0 s it is uncorrelated with the geometry it is colouring, and because the hue label is assigned by frequency band rather than by what is playing. |

Half 2 failing triggers **DECISION-NEEDED #1** — Matt's call, no default (see the session
prompt §10). Material for it is in §8.

---

## 7. Disposition of the spike code

`PhospheneEngine/Tests/PhospheneEngineTests/Presets/StaveLookSpike.swift`, test target
only. **Proposed as CHR.3's skeleton**, with three defects already found and fixed in it
that CHR.3 would otherwise have rediscovered:

1. **`packed_float4` in the MSL vertex struct.** A plain `float4` is 16-byte aligned,
   padding the struct to a 48-byte stride against Swift's 28. The first renders came out
   as large mis-coloured triangles; magenta and yellow in a flat-*white* control was the tell.
2. **Alpha blending, not additive.** ~160 near-collinear ribbon quads saturate to white
   under additive blending long before the trace is legible.
3. **Plot at 20 Hz, not 60.** The analyser behind these bands updates at ~10 Hz, so a
   per-render-frame plot draws duplicate points whose segment direction is numerical noise;
   the degenerate-segment guard in the vertex shader is the second half of that fix.

Plus one instrument correction that is not spike-specific and will bite anything that
plots a time series: **`accumulatedAudioTime` advances ~12× slower than real time** in
these captures. Every trace and every latency figure must use `time`, the render clock.

**Known cosmetic defect, not chased:** the very first captured frame of a sequence renders
as a degenerate wedge (visible only in `dyc_flat/stave_seq_0000.png`); frame 1 onward is
correct. It is a first-upload transient and was left alone — the spike's job is the verdict.

Nothing is registered: no `.metal` under `Sources/Presets/Shaders` (`PresetLoader`
enumerates `.metal`, not `.json`, so a production shader file alone would have made this a
29th preset), no sidecar, no golden, no `certified` flag. **Preset count stays 28.**

---

## 8. Material for DECISION-NEEDED #1 — what should carry instrument identity?

Not a recommendation; Matt picks. Framed in what a viewer sees.

**A — drop the identity claim.** Two traces, low against high, no instrument story. The
preset becomes "the shape of the low end against the shape of the top end", and the concept
sentence changes to match. *For:* it is what the spike actually delivers, and it delivers it
well on 3 of 4 tracks. *Against:* the pitch loses the thing that made it Phosphene-only —
"Milkdrop structurally cannot have stems" was half the D-121 divergence argument. The beat
grid still carries the other half.

**B — move identity to weight or texture instead of hue.** Dotted against solid, thick
against thin. *For:* cheap; the source's own register is a dotted trace, so it is in
keeping; and the spike shows weight modulation IS visible where brightness alone is subtle.
*Against:* it does not touch the actual defect. Whatever channel carries the stem signal,
it is still 3.0 s behind the mark it is decorating. This changes the medium, not the lag.

**C — revisit the driver.** Stem-driven position puts identity back into the geometry, at
the cost of traces sitting ~3 s off in-time gridlines. Matt weighed this on 2026-08-13 and
chose against it. **The spike's new evidence for reopening it:** the cost of the current
split is now measured rather than assumed — colour and position are *uncorrelated at the
moment of drawing* (r −0.15…+0.25), which is a stronger statement than "the colour is a bit
late". If identity matters more than in-time marks, C is the only option that delivers it.
If in-time marks matter more, A is honest and B is decoration.

**A fourth option the spike surfaced, offered for completeness:** keep the split, but stop
drawing the stem channel *on the traces*. Put the slow stem information somewhere slow —
a field tint or backdrop that is allowed to lag — and let the traces be purely
band-driven and purely in-time. This removes the false pairing of a fast mark with a slow
colour without giving up either driver.


---

## 9. Reproducing the measurements

All four scripts are stdlib-only, read-only, and were not committed (no production code
changed this increment). Each is described well enough to rewrite from this file:

1. **slice** — split `beat-match-test-session` into one small session dir per gate track
   under `/tmp/stave_slices/<slug>/` (features.csv + stems.csv + a one-line session.log).
   Track boundaries come from `WIRING: trackChangeCallback FIRED current='...'`; the log
   stamps ISO-8601 UTC and `wallclock_s` is CFAbsoluteTime (unix − 978307200). Needed
   because re-parsing 281 MB in Swift per render dominates the runtime.
2. **common-mode / driver stats** (§0, §1, §2.1) — per track: common-mode share of the four
   per-stem `energyRel` series against their own mean, plus std / p95 / `r` for the
   EMA-centred band traces. EMA mirrors `BandDeviationTracker` (decay 0.9989, warmup 0.9 ×
   180 frames, ceiling 2.0, `(v − ema) × 2`). Validated by recomputing `bassRel` from
   `bass` and correlating against the recorded `bassRel` column: r 0.91–0.99 on 14 of 15
   tracks (Money 0.67, the one outlier, unexplained and not chased).
3. **divergence decomposition** (§2.2) — the same traces, with `div` recomputed on the
   drawn (gain-normalised) pair and compared against `√(2(1−r))`.
4. **grid alignment** (§2.3) and **colour lag** (§4) — nearest-local-maximum offset from
   each `beatPhase01` wrap, and a 0–6 s lag sweep of `r(position driver, colour driver)`.
   Both on `time`, never `accumulatedAudioTime`.
