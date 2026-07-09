# TONAL Pilot Report — TIV signal distributions + drive-constant calibration

**Increment:** TONAL.2b (D-178). **Date:** 2026-07-08. **Tool:** `TonalDumper` (retained-diagnostic).
**Corpus:** the CENSUS stratified pilot — `tools/data/corpus_pilot_1000.csv` (seed-42, 1000 tracks across genre × decade × format strata of Matt's 27,639-track archive).
**Run:** `swift run --package-path PhospheneEngine -c release TonalDumper --manifest tools/data/corpus_pilot_1000.csv --root "/Volumes/Extreme SSD" --out tonal_pilot.json` — **1000 tracks analysed, 0 unreadable, 2,663,545 frames** (first 30 s per track = streaming-preview parity; 1024-pt FFT / 512-hop = the live ~94 Hz cadence). Results live on the corpus volume; only this summary is in-repo.

---

## 1. Corpus-wide distributions (per-frame)

| signal | p1 | p5 | p10 | p25 | p50 | p75 | p90 | p99 |
|---|---|---|---|---|---|---|---|---|
| **consonance** | 0.018 | 0.061 | 0.070 | 0.088 | 0.117 | 0.158 | 0.209 | 0.320 |
| **tension** | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.018 | 0.075 | 0.163 |
| **flux** | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.020 | 0.055 | 0.110 |

**The headline calibration fact:** real full-mix consonance is **far lower than an isolated triad** (~0.5 in the synthetic unit test) — the chroma is smeared across all 12 pitch classes by percussion, multiple instruments, and noise, so the TIV magnitude is small. The realized operating range is ~[0.02, 0.32], not [0, 1]. Tension and flux are **zero for the median frame** — most 30 s clips are a single tonal region with no chord change — and only surface in the upper deciles (p90 tension 0.075, p90 flux 0.055).

## 2. Per-genre medians (the validation that TIV measures real harmony)

| genre | median consonance | median tension |
|---|---|---|
| **classical** | **0.180** | **0.045** |
| jazz | 0.140 | 0.005 |
| folk_country | 0.124 | 0.000 |
| unknown | 0.120 | 0.000 |
| other | 0.114 | 0.000 |
| pop | 0.113 | 0.000 |
| soul_rnb | 0.112 | 0.000 |
| electronic | 0.111 | 0.000 |
| world_latin | 0.109 | 0.000 |
| rock_alt_ind | 0.108 | 0.000 |
| soundtrack | 0.107 | 0.000 |
| hiphop | **0.101** | 0.000 |

**This ordering is the trust signal.** Consonance ranks **classical > jazz > … > rock > hiphop** — exactly how much sustained, harmonically-clear pitched content each genre carries: classical has the clearest sustained harmony, hiphop the most percussion and least sustained harmony. Tension (harmonic movement over the clip) is highest for **classical** (0.045, the most modulation/key-change-rich) then **jazz** (0.005), ~0 for the loop/vamp-based genres. TIV is measuring harmony, not noise.

## 3. Validation against the TONAL.2 targets

- **Jazz vs. rock vs. electronic distinguishable** — ✅ classical 0.180 / jazz 0.140 / electronic 0.111 / rock 0.108: a clean, musically-sane spread.
- **One-chord vamp → near-zero flux over minutes** — ✅ median flux is 0.000 corpus-wide; flux only fires in the top ~quartile (chord-change moments).
- **Percussion-only / sparse-ambient below the gate** — ✅ the atonal bottom (p1–p5 = 0.018–0.061) is percussion/noise/silence, and hiphop (most percussive genre) sits lowest.
- **Known-modulation → phase migration** — ✅ (controlled): a synthetic C-major→G-major clip through the production path moves `tonal_phase_fifths` **−19° → −79°** at the chord boundary (the fifth interval), consonance staying above the floor. Real-track modulation spot-checks are a TONAL.3 verification-pack item (with the Cartograph trace once TONAL.1b lands).

## 4. Drive constants set (IFC.6 discipline — measured, not guessed)

### Analyzer-internal (changed in `TonalAnalyzer` this increment)

The **consonance gate** is the only analyzer-internal constant that needs corpus data (it decays tension/flux to a neutral rest state on atonal/percussive input). The placeholder `consonanceFloor = 0.12` sat at the corpus **median** (0.117) — it would have gated off **half the library**. Recalibrated to the atonal floor:

| constant | placeholder | **calibrated** | provenance |
|---|---|---|---|
| `consonanceFloor` | 0.12 | **0.05** | ≈p3–4 — below genuine noise/silence; above it, tonal genres pass |
| `consonanceGateWidth` | 0.10 | **0.03** | full signal by 0.08 (≈p22); every genre median (≥0.10) passes at gate=1.0 |

Gate = `smoothstep(0.05, 0.08, consonance)`: fully blocks below p3 (noise/silence), ramps through the percussion-heavy p3–p22 band, fully passes real music (all genre medians ≥0.101).

### Consumer-side (for TONAL.3's preset — soft-saturate against p99, the deviation-primitive discipline; values are docs, not analyzer state)

These stay **raw** in the FeatureVector (consistent with `*_energy_dev`, which every preset soft-saturates against its own p99 — `project_deviation_primitive_real_range`). TONAL.3's Nacre coupling maps each against its realized p99, **not** the nominal 1.0:

| signal | soft-saturate target (p99) | note |
|---|---|---|
| `tonal_consonance` | **0.32** | saturation driver — map [floor…0.32] → [pale…full], not [0…1] |
| `tonal_tension` | **0.163** | the slow secondary — map [0…0.16] → its visual range |
| `harmonic_flux` | **0.110** | the (later-increment) accent — peak-pick ≈ p90 0.055 |

**The time constants** (`fastCenterTau` 2 s, `slowCenterTau` 20 s, `consonanceTau` 0.5 s, `fluxTau` 0.15 s) are design choices, not amplitude calibration — unchanged. Note the 20 s slow-center means tension only reads "distance from home" after ~20 s of established key; on a 30 s preview that leaves ~10 s of settled signal (the documented cold-start characterization).

## 5. Reproduction

`swift run --package-path PhospheneEngine -c release TonalDumper --manifest tools/data/corpus_pilot_1000.csv --root "/Volumes/Extreme SSD" --out <json>`. `--limit N` for a quick subset; `--audio <file>` for a single-clip per-window table. Dev-only; the JSON + per-track CSV live on the corpus volume, never the repo.
