# Phosphene — Developer Release Notes — 2026-04 (rotated monthly from the active [`RELEASE_NOTES_DEV.md`](RELEASE_NOTES_DEV.md) by `Scripts/rotate_docs.sh`; entries verbatim, newest-first)

---

## [dev-2026-04-25] Milestones A, B, C

**Increments:** U.1–U.11, 4.0–4.6, 5.2–5.3, 6.1–6.3, 7.1–7.2, V.1–V.6, MV-0–MV-3
**Type:** Multi-phase milestone delivery

Milestones A (Trustworthy Playback), B (Tasteful Orchestration), and C (Device-Aware Show Quality) all met on 2026-04-25.

**Highlights:**
- Full session lifecycle (idle → connecting → preparing → ready → playing → ended).
- Apple Music + Spotify OAuth connectors.
- Progressive session readiness (partial-ready CTA).
- Orchestrator: PresetScorer, TransitionPolicy, SessionPlanner, LiveAdapter, ReactiveOrchestrator.
- Frame budget governor + ML dispatch scheduler.
- V.1–V.3 shader utility library (Noise, PBR, Geometry, Volume, Texture, Color, Materials).
- V.6 fidelity rubric + certification pipeline.
- Phase U: permission onboarding, connector picker, preparation UI, playback chrome, settings panel, error taxonomy, toast system, accessibility.
- Beat This! architecture committed (DSP.2 scope).

**Known issues at milestone:**
- All presets uncertified (BUG-004). *(Resolved 2026-05-12 — Lumen Mosaic certified at LM.7; see `[dev-2026-05-12-d]`.)*
- Spotify preview_url null for some tracks (BUG-005).
- Test suite: 4 pre-existing Apple Music environment failures (unchanged).
