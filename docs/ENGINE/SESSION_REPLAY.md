# Session Replay — Diagnostic Infrastructure

`PresetSessionReplay` is a Swift executable target inside `PhospheneEngine/` that takes a recorded session directory + a preset name and emits a canonical evidence pack. **Every preset closeout that asserts an audio-coupled route works, or that the rendered output belongs in the same visual family as the references, must cite an evidence pack produced by this tool.** Hand-wave assertions ("Route X works", "reads in the same visual conversation as ref 01") are gate-bypass language and are no longer acceptable in closeouts.

Authoring history: SR.1, 2026-05-20. Motivated by the AV.2.x cascade — 12+ increments shipped over a route (Route 1 vocals-pitch hue) that was firing 0 % of frames the entire time (PT.1 surfaced the bug after 5 months of "tests green" closeouts). The diagnostic infrastructure that would have caught the gap immediately did not exist before SR.1.

---

## Invocation

```
swift run --package-path PhospheneEngine PresetSessionReplay \
    --session  /path/to/2026-05-20T01-23-03Z \
    --preset   aurora_veil \
    [--output  /tmp/replay/<session>_<preset>] \
    [--motion-grid-count 600] \
    [--rubric-frame-count 24] \
    [--max-events-per-route 6] \
    [--references-dir docs/VISUAL_REFERENCES/aurora_veil]
```

Outputs (default destination `/tmp/phosphene_replay/<session>_<preset>/`):

```
replay_report.md            # Canonical evidence pack — Markdown
events/<route>/event_NN.png # Video frames extracted at the N strongest events per route
motion_grid/grid_NNN.png    # Uniform-grid frames for motion-band analysis (motion-grid-count)
rubric_grid/grid_NNN.png    # Frames graded against the per-Q visual rubric (rubric-frame-count)
```

Open the report with `open <output>/replay_report.md`.

---

## What the report contains

Sections, in order:

1. **Session metadata** — frame count, duration, inferred FPS, video presence.
2. **Route firing** — per-route gate-crossing statistics. The load-bearing column is `Firing %` — a route at 0 % did not fire during the session, full stop. For routes with smoothstep gates, both LO and HI threshold firing rates are reported.
3. **Audio events + rendered frames** — for each route, the strongest N events with the rendered video frame extracted at that timestamp. Manual side-by-side inspection: if the route fires but the frame looks identical to the surrounding frames, the visual coupling is not landing.
4. **Motion-band analysis** — frame-delta frequency-decomposition into substorm / substrate / pulsation / sub-second bands. Subject to Nyquist of the sampled grid (default 600 frames over a ~132-s session gives Nyquist ≈ 2.25 Hz; sub-second 5–10 Hz is below Nyquist and aliases).
5. **Visual rubric (calibrated)** — per-question image-processing proxies scored against (a) the preset's reference set, (b) anti-references, (c) sampled rendered frames. Per-Q verdicts: `withinFamily` ≤ 1 σ of reference mean; `onFringe` 1–2 σ; `outsideFamily` > 2 σ; `readsLikeAntiReference` = render closer to an anti-ref than to any reference; `uncalibrated` = proxy too scattered across the reference set to grade. **Uncalibrated is an honest verdict; it means the proxy isn't reliable enough to assert against the render, NOT that the render is OK.**
6. **Discipline footer** — explicit statement of what the report verifies vs. what it doesn't. Closeouts citing the report must restrict claims to what's verified.

---

## What the report does and does not verify

**Verified.**

- Per-route input statistics across the entire session.
- % of frames where each route's gate condition fires (load-bearing for "the route works").
- Audio-event timestamps + rendered frames at those timestamps (manual inspection for visual coupling).
- Frame-delta motion energy by timescale band (subject to Nyquist of the sampled grid).
- Per-question rubric proxy scores for the rendered output + reference set (where proxies are calibrated).
- σ-distance of the rendered output from the reference family centroid per question.

**Not verified.**

- Whether the audio-driven visual response feels musically correct — Matt's L4 review.
- Fidelity to reference photographs as pixel-level match — only family-bar via the proxies.
- Sub-second flicker if the sampled grid's Nyquist is below 10 Hz.
- Codec-compression effects on high-frequency motion energy (recorded H.264 mp4 vs live render).
- Proxies flagged `uncalibrated` — the rubric explicitly withholds a verdict rather than asserting on a broken proxy.

If a closeout cites this report as evidence that "the route works," the claim must be restricted to what this report verifies (firing rates, audio-event frames present). A claim that the route produces a "visible response" requires either manual inspection of the event-aligned frames OR a follow-up SR.2+ check that quantifies the visual response.

---

## Adding a new preset

Each preset registers two things:

1. **Routes** — `RouteSpec` definitions in `Sources/PresetSessionReplay/<Preset>Routes.swift`. Each route is named, gated, and its input scalar is extracted by a closure that receives a `SessionFrame`. Gates must replicate the shader's exact firing condition; document any duplicated gate constants with a back-pointer to the shader / state file so they stay in sync (SR.2 will centralize constants).
2. **Rubric** — `RubricQuestion` definitions in `Sources/PresetSessionReplay/<Preset>Rubric.swift`. Each question is one image-processing proxy. Proxies are heuristics; the calibration step decides which are reliable.

Then add a case to `PresetSessionReplay.swift::resolvePreset` (and a sibling `resolveRubric` if you generalize beyond Aurora Veil). Run the harness against the preset's existing reference set, inspect the report, and iterate on proxies that come back `uncalibrated` until enough Qs grade reliably for the preset's M7 review to lean on the evidence pack.

---

## Discipline rule

A closeout that asserts an audio-coupled route works must cite per-route firing evidence from the session's `features.csv` / `stems.csv` (or equivalent) — frame counts, threshold-crossing percentages, video-frame extracts at the audio events. "Visually verified" without that evidence is gate-bypass language. When the diagnostic doesn't exist for a question, the closeout says "cannot verify X" instead of asserting it. Building the missing diagnostic is the next increment, not a future task.

Cross-reference: `CLAUDE.md` "Diagnostic infrastructure precedes fidelity claims."

---

## SR.1 known limitations

These are documented as honest limitations, not deferred work:

- **Q5 (emissive compositing) proxy** falls back to a constant 0.5 when no "star-class" pixels are detected in either bright-aurora or dark-sky regions at canonical analysis resolution (480×320). The framework correctly flags this `uncalibrated` rather than asserting a verdict. SR.2 should refine to count actual stars per image.
- **Reference selection per question.** The current calibration uses all references for every question; some references (e.g., `02` for Aurora Veil — palette-only, not a shape reference) shouldn't anchor shape-related proxies. README annotations already say so; SR.2 should add per-Q reference selection.
- **Single preset registered** — Aurora Veil. Other presets need their own `<Preset>Routes.swift` + `<Preset>Rubric.swift`.
- **Naive O(N²) DFT** in `MotionBandAnalyzer` and `SpatialFFT`. Fine at SR.1 scale; switch to vDSP if the harness scales past ~10 k samples per analysis.
- **No automated visual-grading verdict for the report** — only per-Q numbers + verdicts. A future SR.2 could synthesize an overall pass/fail recommendation from the per-Q verdicts; currently the reader interprets the table.
- **Gate-constant duplication** — Aurora Veil's gate thresholds are duplicated in `AuroraVeilRoutes.swift` from `AuroraVeil.metal` + `AuroraVeilState.swift`. Documented with a "MUST stay in sync" comment + cross-references; SR.2 should centralize constants.

---

## What this replaces

**Before SR.1.** Closeouts asserted "the route works" based on test-suite pass + author judgment. Tests pass because they check pipeline correctness (FFT processor produces values, audio buffer accumulates samples), not whether routes fire under live audio. PT.1 was the existence proof: `vocalsPitchConfidence` was 0 % across every Aurora Veil session for ~5 months while closeout after closeout claimed the route worked.

**After SR.1.** Closeouts cite the replay report. "Route 1 fires 23.28 % of frames on session X" replaces "Route 1 works." "Q3 verdict: reads-like-anti-reference vs the curated reference set" replaces "frames read in the same visual conversation as references." Honest claims, citable evidence, refutable assertions.

---

## See also

- `PhospheneEngine/Sources/PresetSessionReplay/` — implementation
- `CLAUDE.md` "Diagnostic infrastructure precedes fidelity claims" discipline rule
- `docs/presets/AURORA_VEIL_RESEARCH_AV3X_2026-05-20.md` — the AV.3.x design dossier that surfaced the cascade-of-failures and motivated SR.1
- AV.2.x cascade release notes (`docs/RELEASE_NOTES_DEV.md` entries `[dev-2026-05-18-c]` through `[dev-2026-05-20-a]`) — the empirical case for why this infrastructure became mandatory
