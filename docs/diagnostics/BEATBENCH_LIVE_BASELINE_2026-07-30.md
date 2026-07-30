# BeatBench live-path replay — beat-match-test-session

Two classes of number, kept apart deliberately:

- **drift p50/p90/p99, lock %, time-to-lock, confident-wrong** come from the
  tracker's own `drift_ms` residual. Available for every track, and directly
  comparable to BUG-065's evidence — but self-reported: a grid locked
  confidently to the wrong pulse still reports small drift.
- **F / AMLt** compare recovered live beats against GT.2 ground truth, and are
  only computed where the fixture was segmented from this same session. For a
  corpus rip the streamed master is a different recording, so scoring it would
  produce confident nonsense.

| track | suite | dur | drift p50 | p90 | p99 | lock % | unlocks at | confident-wrong | F | AMLt |
|---|---|---|---|---|---|---|---|---|---|---|
| billie_jean | 1 | 292s | 74 | 102 | 118 | 95% | 91s | 53.8% | — | — |
| around_the_world | — | 431s | 40 | 59 | 78 | 75% | 225s | 7.2% | — | — |
| stayin_alive | — | 284s | 133 | 269 | 285 | 95% | 48s | 84.0% | — | — |
| superstition | — | 267s | 31 | 81 | 101 | 82% | 207s | 15.2% | — | — |
| take_five | 2 | 331s | 26 | 89 | 114 | 99% | 288s | 12.5% | — | — |
| money | 2 | 380s | 156 | 233 | 238 | 84% | 122s | 64.1% | 0.27 | 0.44 |
| solsbury_hill | 2 | 262s | 26 | 56 | 77 | 95% | stays in | 2.6% | 0.26 | 0.54 |
| pyramid_song | 2 | 288s | 38 | 77 | 92 | 50% | 18s | 19.3% | 0.17 | 0.29 |
| bohemian_rhapsody | 3 | 356s | 231 | 368 | 368 | 35% | 0s | 76.9% | 0.13 | 0.34 |
| dance_yrself_clean | — | 537s | 589 | 726 | 732 | 42% | 58s | 81.4% | — | — |
| yyz | 2 | 266s | 2324 | 4373 | 4799 | 92% | 47s | 90.8% | 0.41 | 0.22 |
| bleed | 4 | 442s | 46 | 63 | 100 | 73% | 189s | 11.2% | 0.42 | 0.09 |
| giorgio_by_moroder | — | 546s | 8 | 42 | 52 | 56% | stays in | 0.0% | — | — |
| girl_from_ipanema | — | 319s | 42 | 171 | 192 | 88% | 5s | 33.4% | — | — |
| clair_de_lune | 5 | 308s | 66 | 128 | 138 | 88% | 156s | 52.4% | — | — |

Drift figures are |drift_ms|. The program's live suite-1 target is p90 < 30 ms.

## Drift by 30 s window (the BUG-065 curve)

A single percentile hides drift that grows across a track, which is exactly
what BUG-065 describes. Each cell is p90 |drift_ms| in that window.

- **billie_jean**: 26 → 48 → 63 → 93 → 102 → 106 → 98 → 118 → 86 → 82
- **around_the_world**: 60 → 69 → 71 → 60 → 41 → 39 → 47 → 78 → 71 → 50 → 51 → 40 → 40 → 40 → 40
- **stayin_alive**: 60 → 97 → 95 → 129 → 141 → 164 → 154 → 209 → 285 → 274
- **superstition**: 26 → 10 → 24 → 33 → 48 → 55 → 71 → 94 → 84
- **take_five**: 35 → 36 → 31 → 48 → 42 → 18 → 47 → 44 → 55 → 96 → 114 → 84
- **money**: 20 → 40 → 44 → 76 → 81 → 158 → 178 → 171 → 230 → 234 → 241 → 233 → 233
- **solsbury_hill**: 30 → 45 → 26 → 31 → 23 → 30 → 57 → 59 → 77
- **pyramid_song**: 91 → 77 → 82 → 64 → 64 → 55 → 17 → 21 → 35 → 20
- **bohemian_rhapsody**: 111 → 20 → 131 → 167 → 194 → 231 → 267 → 311 → 319 → 360 → 368 → 368
- **dance_yrself_clean**: 51 → 68 → 107 → 284 → 463 → 547 → 581 → 587 → 589 → 637 → 732 → 726 → 726 → 726 → 726 → 726 → 726 → 726
- **yyz**: 53 → 433 → 1081 → 1792 → 2606 → 3085 → 3716 → 4362 → 4799
- **bleed**: 49 → 43 → 26 → 39 → 56 → 63 → 90 → 104 → 30 → 60 → 48 → 46 → 46 → 46 → 46
- **giorgio_by_moroder**: 21 → 41 → 43 → 34 → 21 → 54 → 48 → 45 → 51 → 46 → 39 → 1 → 1 → 1 → 1 → 1 → 1 → 1 → 1
- **girl_from_ipanema**: 82 → 39 → 20 → 28 → 33 → 47 → 52 → 128 → 165 → 182 → 192
- **clair_de_lune**: 39 → 25 → 13 → 35 → 57 → 95 → 94 → 132 → 135 → 130 → 123

- `billie_jean` — drift only — fixture is a different master than what was streamed
- `around_the_world` — no ground truth — track not tapped at GT.2
- `stayin_alive` — no ground truth — track not tapped at GT.2
- `superstition` — no ground truth — track not tapped at GT.2
- `take_five` — drift only — fixture is a different master than what was streamed
- `dance_yrself_clean` — no ground truth — track not tapped at GT.2
- `giorgio_by_moroder` — no ground truth — track not tapped at GT.2
- `girl_from_ipanema` — no ground truth — track not tapped at GT.2
- `clair_de_lune` — drift only — fixture is a different master than what was streamed
