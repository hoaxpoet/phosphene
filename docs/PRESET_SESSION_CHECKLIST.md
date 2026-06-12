# Preset Session-Start Checklist

Run this at the **start** of any preset-related increment — authoring, uplift, tuning, or fix — before opening a `.metal` file. It replaces the former Failed Approaches #39 and #63 and the Arachne read-first bullet (RB.2, 2026-06-11). The reasoning: Claude Code has no visual feedback while writing shader code, so anchoring on the curated references and the preset's design history is the only reliable path to quality — and the transcript record shows prose rules alone did not make that happen (README-before-first-edit measured at 35 % compliance, REVIEW.1). A checklist at session start is the mechanism.

1. **Read `docs/VISUAL_REFERENCES/<preset>/README.md` cover to cover.** The README carries per-image trait-trustability annotations and disregard-this-property warnings that prompt text won't have. If no curated reference set exists for the preset: curate it first as part of the session, or escalate to Matt before authoring.
2. **Read each reference image's annotation.** Note the mandatory-traits checklist and the anti-references (what the preset must NOT look like).
3. **Read the preset's design doc if one exists** (`docs/presets/ARACHNE_V8_DESIGN.md`, `LUMEN_MOSAIC_DESIGN.md`, `SKEIN_DESIGN.md`, …). Per-preset operating rules and tuning history live there, not in CLAUDE.md.
4. **Cite specific reference filenames** in design comments wherever they motivate a design choice.
5. **Mid-session sanity checks are side-by-side comparisons against the named reference images** — never a self-judgment of "looks reasonable."
6. **Render early.** Produce a `RENDER_VISUAL=1` contact sheet before the first tuning commit. The heaviest historical preset sessions burned 85 %+ of their output tokens before any rendered evidence existed (REVIEW.1 §1.3); rendered evidence early is what ends tuning spirals.
