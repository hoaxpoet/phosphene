# Lumen Mosaic — Claude Code Session Prompts

This document contained the session prompts for Phase LM. **Phase LM CLOSED 2026-05-12**: Lumen Mosaic certified at LM.7 (D-LM-7) after LM.6 (D-LM-6) landed earlier the same day. The historical prompts have been compressed to a summary table; reach for git history (or the `prompts/LM.6-prompt.md` file still in the repo) if you need the original prompt text for any landed increment.

**Cleaned up 2026-05-12 (cert sweep).** This rev reflects the actual landed state of the preset: LM.4.6 contract + LM.6 cell-depth gradient + optional hot-spot + LM.7 per-track aggregate-mean tint with chromatic projection. The earlier cleanup note ("LM.6 = specular sparkle") was aspirational; corrected here to match the actual landed shape.

---

## Decisions in force at cert time (LM.7)

Per [`LUMEN_MOSAIC_DESIGN.md §3`](LUMEN_MOSAIC_DESIGN.md):

- **A.1** Lumen Mosaic — preset name
- **C.1/2 (drifted)** ~30 cells across — `kCellDensity = 15` after LM.3.2 round 2
- **D.6** Pure uniform random RGB per cell, keyed on `(cellHash, beat-step counters, per-track seed, section salt)` (LM.4.6)
- **E.4** Direct hash → RGB; section salt via `bassCounter / 64` is the only mood-correlated mutation (LM.4.6)
- **F.1** Slot 8 fragment buffer (`directPresetFragmentBuffer3`)
- **F.2** LM.6 cell-depth gradient + optional hot-spot (D-LM-6) — albedo-only modulations in `sceneMaterial`
- **F.3** LM.7 per-track aggregate-mean RGB tint with chromatic projection (D-LM-7)
- **G.1** Fixed camera, panel oversize 1.50×
- **H.1** Standalone preset

**Retired:** B.1 (4-agent analytical contributions — scaffolding-only since LM.3.2), D.1, D.4, D.5 (old LM.5 / LM.7 / LM.8 framings — all retired with the pattern engine at LM.4.4), E.1, E.2, E.3.

---

## Phase LM increment ledger

For each landed or retired increment, retrieve the original session prompt from git history (`git log --diff-filter=A -- LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md` or `git show <pre-cleanup-commit>:docs/presets/LUMEN_MOSAIC_CLAUDE_CODE_PROMPTS.md`) if needed. The landed-work paragraphs in `CLAUDE.md` and `ENGINEERING_PLAN.md` capture the substantive history; the prompts themselves are session artifacts, not authoritative documents.

| Increment | Outcome | Commit / status |
|---|---|---|
| LM.0 | Slot 8 infrastructure | ✅ `6388e881` |
| LM.1 | Static-backlight panel scaffold | ✅ landed |
| LM.2 | 4 audio-driven light agents — muted output | ⚠ rejected; slot-8 binding + agent dance reused at LM.3 |
| LM.3 | D.4 per-cell `palette()` keyed on `accumulated_audio_time × kCellHueRate` — cells did not visibly cycle (BUG-012) | ⚠ rejected |
| LM.3.1 | Agent-position-driven static-light field — spotlit blobs dominated | ⚠ rejected |
| LM.3.2 | D.5 band-routed beat-driven dance — HSV palette, 4 teams, rising-edge counters | ✅ M7 pass 2026-05-10 |
| LM.4 | Pattern engine v1 (idle / radial_ripple / sweep) — triggers wrong source | ⚠ rejected |
| LM.4.1 | Ripple density + bleach-out 3-line calibration | ⚠ superseded by LM.4.3 |
| LM.4.3 | BeatGrid-driven triggers replacing FFT-band edges | ⚠ superseded by LM.4.4 |
| LM.4.4 | **Pattern engine retired entirely** | ✅ 2026-05-11 |
| LM.4.5 (v1 → .3) | Five rejected palette redesigns over a day | ⚠ all superseded by LM.4.6 |
| LM.4.6 | **Pure uniform random RGB per cell (D.6)** — Matt: "Working. It's close enough." | ✅ `c0f9ccf3` + `888bb856` |
| ~~LM.5~~ | ~~Pattern engine v2~~ | ⊘ retired by LM.4.4 |
| LM.6 | **Cell-depth gradient + optional hot-spot** — two albedo-only modulations in `sceneMaterial` (depth gradient: centre→edge brightness; hot-spot: centre 30 % pinpoint additive on cell's own hue). **NOT Cook-Torrance** — the earlier "specular sparkle via Cook-Torrance" framing was aspirational and abandoned per LM.3.2 round-7 / Failed Approach lock. D-LM-6. | ✅ landed 2026-05-12 |
| LM.7 | **Per-track aggregate-mean RGB tint with chromatic projection.** `trackTint = (rawTint - mean(rawTint)) × kTintMagnitude (0.25)` from `trackPaletteSeed{A,B,C}`. Each track plays at a visibly distinct aggregate panel mean. D-LM-7. | ✅ landed 2026-05-12 |
| ~~LM.8~~ | ~~Mood-quadrant palette banks~~ | ⊘ retired 2026-05-09 |
| Cert | Matt M7 sign-off on real-music session `2026-05-12T17-15-14Z`. `LumenMosaic.json` `certified: true`. `"Lumen Mosaic"` ∈ `FidelityRubricTests.certifiedPresets`. Phase LM CLOSED. | ✅ landed 2026-05-12 |

---

## Cert closeout (no separate session prompt)

Cert landed jointly with LM.7 in the LM.7 session prompt itself (no standalone BUG-004 prompt was needed — the cert flip was small enough to be folded into LM.7's increment scope). The earlier plan for a `BUG-004_LM_certification_session_prompt.md` artifact was retired: it would have been a separate Claude Code session, but the LM.7 prompt naturally absorbed the cert verification step. Future cert sessions for AV / CC / Phase G-uplift presets can follow the same pattern (fold the cert flip into the final increment of the preset's phase rather than building a standalone cert session).

A separate **BUG-004 closure session** did run 2026-05-12 after LM.7 to formally retire the bug ticket: it expanded `GoldenSessionTests.makeRealCatalog()` 11 → 15 production presets, added a `Session D` regression test (`sessionD_lumenMosaicWinsFirstSegment`) that locks Lumen Mosaic winning at least one orchestrator slot under a plausible mood profile, fixed the stale `MatIDDispatchTests.kLumenEmissionGain` constant (4.0 → 1.0 post-LM.3.2-round-4), and filed the closure across `docs/QUALITY/KNOWN_ISSUES.md` + `docs/RELEASE_NOTES_DEV.md` + `docs/ENGINEERING_PLAN.md` + `CLAUDE.md`. That session's commit is `81d6b8f3 [BUG-004] Tests + docs: closure — Lumen Mosaic is first certified preset; orchestrator now exercises real cert state`. Lesson: bug-ticket closure can be a useful separate session even when the underlying fix shipped earlier — it's where the verification-surface gap (synthetic-cert fixture in `GoldenSessionTests`) gets caught.

---

## Cross-increment notes

### Performance regression discipline

`PresetPerformanceTests` is the cert gate. p95 ≤ 3.7 ms at Tier 2 / ≤ 4.5 ms at Tier 1. Target the cheapest ray-march preset in the catalog — this preserves headroom for AV / CC / V.12 ray-march work.

### D-026 enforcement

Every audio-routing edit must pass `grep -n 'f\.bass[^_]\|f\.mid[^_]\|f\.treble[^_]' PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.metal PhospheneEngine/Sources/Presets/Lumen/LumenPatternEngine.swift`. The grep must return zero matches outside the documented `f.beatBass` / `f.beatMid` / `f.beatTreble` rising-edge usage (which is event-shaped, not energy-shaped, and is the only sanctioned exception in this preset).

### Matt-review boundaries

The recurring process error from LM.2 / LM.3 / LM.3.1 (marking ✅ on commit landing, then watching the visual scope get rejected at production review) was the lesson that produced the "every increment is ⏳ until Matt approves on real music" rule. Phase LM closed at LM.7 (2026-05-12) — Matt M7 sign-off on real-music session `2026-05-12T17-15-14Z`. Any future Phase LM polish increments (none planned at cert time) should follow the same rule.

### Documentation keep-up

Documentation drift is silent regression. Every landed increment should update CLAUDE.md, DECISIONS.md (if a decision was filed), ENGINEERING_PLAN.md, and this document. The cumulative diff across Phase LM should be a self-contained audit trail; do not let it accumulate. A doc-drift audit was run as part of the LM.7 cert sweep (correcting stale "LM.6 = Cook-Torrance specular sparkle" references across `LUMEN_MOSAIC_DESIGN.md`, `Lumen_Mosaic_Rendering_Architecture_Contract.md`, `VISUAL_REFERENCES/lumen_mosaic/README.md`, this file, and ENGINEERING_PLAN.md carry-forwards).

### Anti-pattern audit (run as part of LM.7 cert verification — passed)

Verified at cert (2026-05-12):

- **No raw `f.bass` / `f.mid` / `f.treble` reads** in `LumenMosaic.metal` or `LumenPatternEngine.swift`. The `f.beatBass` / `f.beatMid` / `f.beatTreble` rising-edge usage is the documented exception (event-shaped).
- **No `smoothstep(0.22, 0.32, f.bass)` style absolute-threshold gates.** Uses D-026 deviation patterns and event-shaped beat counters.
- **No hardcoded BPM assumptions.** Uses `f.beat_phase01` / `f.barPhase01` as authority; team counters fire on band rising-edges which `BeatDetector` already gates.
- **No camera motion.** Camera position is JSON-fixed (G.1).
- **No SDF deformation from audio.** `sceneSDF` is audio-independent (D-020).
- **No second-bounce ray tracing.** Backlight is via direct per-cell hash → RGB (D.6) + LM.7 per-track chromatic-projected tint.
- **No reproducing the reference image's content.** References are for guidance.
- **Panel edges never visible.** Verified against 16:9 / 4:3 / 21:9 at LM.7 cert review (`kPanelOversize = 1.50`).
- **No cream baseline / pastel pull.** Direct hash → RGB has no path to pastels by construction; LM.7 chromatic projection prevents achromatic-aligned seeds from washing toward cream / black. Verified by `LumenPaletteSpectrumTests` Suite 7.
- **Per-cell colour identity stays.** `sceneMaterial` reads per-cell colour from the hash → RGB function; LM.7 tint shifts the sampling window per track but every cell still independently rolls a colour.
- **No pattern engine resurrection.** LM.4.4 retired `LumenPatterns.swift`; the `LumenPattern` GPU struct is preserved for ABI continuity only.
- **Agent intensity/color fields stay unused** by the shader. The 4 `LumenLightAgent` slots survive on the GPU buffer for ABI; the LM.3.1 agent-driven backlight character is retired.
- **LM.6 modulation in `sceneMaterial`, not the lighting fragment.** The matID==1 lighting path still skips Cook-Torrance entirely. LM.6 = albedo-only depth gradient + optional hot-spot, driven by Voronoi `f1/f2`. **The earlier "LM.6 includes Cook-Torrance specular pass" framing was aspirational and abandoned per the LM.3.2 round-7 / Failed Approach lock — corrected as part of the cert sweep.** The rubric's "hero specular highlight ≥ 60% of frames" Preferred check is satisfied by the LM.6 hot-spot (every cell, every frame — it's per-pixel Voronoi-driven, not stochastic), not by a Cook-Torrance pass.
- **LM.7 chromatic projection present.** `trackTint = (rawTint - mean(rawTint)) × kTintMagnitude` — the mean subtraction is mandatory; verified by `test_achromaticAlignedSeed_doesNotWash`.

The cert verification was folded into the LM.7 increment scope; no separate audit-file artifact (`LM-9-audit-passed.txt`) was needed. The cumulative pass record lives in `docs/RELEASE_NOTES_DEV.md` `[dev-2026-05-12-b]`.
