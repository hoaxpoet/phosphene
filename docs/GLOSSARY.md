# Glossary — internal shorthand you'll meet in these docs

Phosphene was built by a two-member team (Matt + Claude Code) and the docs
were written for them first. This page decodes the shorthand; nothing here
is needed to *run* the project, only to read its history.

| Term | Meaning |
|---|---|
| **D-###** | A numbered engineering decision in [DECISIONS.md](DECISIONS.md) (older ones in DECISIONS_HISTORY.md). Docs cite decisions by number; the index at the top of DECISIONS.md resolves them. |
| **Increment ID** (`LF.5`, `PUB.3`, `NACRE.4`…) | One unit of work in [ENGINEERING_PLAN.md](ENGINEERING_PLAN.md) — `<PHASE>.<n>`. Commit messages carry the ID in brackets: `[LF.5] Session: …`. |
| **M7** | The maintainer's **live visual review with real music** — the load-bearing quality gate for presets. Automated gates are the floor; M7 is the bar. "M7-passed" / "pending M7" in docs refers to this. |
| **Certification** | A preset joining the production rotation the AI orchestrator plans with: M7 sign-off + `certified: true` + fail-loud test-table membership (rubric, flash harness) + green `audio_routes`. Uncertified presets are still runnable via Settings → *Show uncertified presets*. |
| **FA #N** | "Failed Approach" — a numbered do-not-repeat entry (CLAUDE.md carries the index; full text in HISTORICAL_DEAD_ENDS.md and topic docs). |
| **BUG-###** | A defect in [QUALITY/KNOWN_ISSUES.md](QUALITY/KNOWN_ISSUES.md) (resolved ones rotate to KNOWN_ISSUES_HISTORY.md). |
| **Closeout** | The end-of-increment protocol: evidence block (full test battery), doc updates, commit. See `.claude/skills/closeout/`. |
| **Deviation primitives** (`bassDev`, `bassRel`, `*EnergyDev`…) | The continuous-energy fields presets are driven from: each band/stem measured against its own running average (D-026/D-146), not an absolute threshold. The most important design rule in the project — see CLAUDE.md §Audio Data Hierarchy. |
| **BeatGrid** | The cached per-track beat/downbeat timeline from offline Beat This! analysis. Beat-locked motion is valid ONLY on this grid, never on raw live onsets (±80 ms jitter). |
| **FeatureVector / StemFeatures** | The two per-frame GPU structs every shader reads (buffer(2) / buffer(3)) — field maps in [ARCHITECTURE.md §Key Types](ARCHITECTURE.md#key-types-shared-module). |
| **Rendering paradigms** | `direct` (single fragment), `mv_warp` (Milkdrop-style feedback warp: warp → compose → blit), `ray_march` (G-buffer + SSGI), `mesh`/particles (CPU-side geometry + compute), `staged` (multi-stage composition). A preset declares its paradigm via `passes` in the sidecar. |
| **Sidecar** | The preset's `.json` metadata file next to its `.metal` — schema in [SHADER_CRAFT.md §17](SHADER_CRAFT.md#17-preset-metadata-format-json-sidecar). |
| **Reactive mode** | Playback with no pre-analysis (no cached BeatGrid/stems) — live analysis only. The degrade path when preparation fails or for ad-hoc sessions. |
| **Layer 1–5** | The audio-data hierarchy (spectrum/waveform textures → spectral features → beat events → pre-analyzed vs. real-time stems). Canonical in the `preset-session` skill. |
| **Tap** | The Core Audio process tap (`AudioHardwareCreateProcessTap`) capturing system audio for streaming sessions. Requires the Screen Recording permission (audio only is captured). |
| **AGC** | Automatic gain control — per-band normalization so features are level-independent. Never compare AGC-normalized values against absolute thresholds. |
| **Oracle** | A reference implementation rendered live for side-by-side comparison during a port (e.g. butterchurn for Milkdrop-inspired presets — `tools/milkdrop-render/`). |
| **Contact sheet** | A grid of harness-rendered frames (`RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests`) for offline visual review. |
| **Session artifacts** | The per-session capture directory (`session.log`, `features.csv`, `stems.csv`, `raw_tap.wav`, `chain_health.json`) diagnostics work from. |
