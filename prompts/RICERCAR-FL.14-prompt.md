# Increment RICERCAR-FL.14 — staccato vs legato line character (preset increment)

**Objective.** After this session, Ricercar's glowing light-lines read their INSTRUMENT'S ARTICULATION: staccato / percussive material (sharp attacks) paints **shorter, choppier lines**; legato / sustained material (strings, held notes) paints **longer, more flowing lines**. Per-colour, driven by each stem's attack character. Matt's ask (2026-07-09, on Beethoven): *"I'd like to see some distinction between staccato and legato instruments/sections … staccato rhythms could be visually improved with shorter, more choppy lines, while the strings can be more flowing as applicable."*

This is a CHARACTER refinement on top of the FL.13 per-colour-motion baseline — NOT a motion or paradigm change.

## Skills to invoke
- `preset-session` — BEFORE opening `RicercarFlow.metal` or `RicercarFlowGeometry.swift` (read the checklist + audio hierarchy).
- `shader-authoring` — BEFORE editing the `.metal` (GPU contract, quality floor).
- `closeout` — at the end (8-part report + `Scripts/closeout_evidence.sh` block).

## Read first (in order)
1. `docs/presets/RICERCAR_DESIGN.md` §FANTASIA REBUILD — the FL.10→FL.13 arc (esp. the FL.12/FL.13 entries: why the beat was removed, the hybrid per-colour motion, the genre constraint).
2. Memory `[[ricercar-and-instrument-capture]]` — full status + the FL.14 signal findings + design challenge (below, restated).
3. `PhospheneEngine/Sources/Renderer/Geometry/RicercarFlowGeometry.swift` — the conformer: per-frame envelopes, the per-family `fam` hybrid env, `driftAngle[4]`, `makeConfig`, particle seed (life/age), the ping-pong HDR trail + decay.
4. `PhospheneEngine/Sources/Renderer/Shaders/RicercarFlow.metal` — `FlowConfig`/`FlowParticle` (STRUCT MIRROR — Swift + MSL must match field-for-field, all 4-byte scalars, no alignment trap), `ricercar_flow_update` (advect + wrap + respawn), decay/point/display passes.
5. `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/RicercarFlowRenderTests.swift` + `Diagnostics/RicercarFluidVideoHarness.swift` — the gate + the real-audio video harness (env-gated; `RICERCAR_BPM=<bpm>` installs a fixed grid; drives the geometry with production analysis).
6. Session artifacts to mine for the signal: `/Users/braesidebandit/Documents/phosphene_sessions/2026-07-09T17-29-02Z/` (Beethoven) + `…17-26-36Z/` (Nirvana) — `stems.csv` has the per-stem attack columns.

## Pre-flight invariants (each failure stops the session)
- Branch: the FL work lives on **`claude/ricercar-rework`** (primary checkout `/Users/braesidebandit/Documents/Projects/phosphene`) at head **`3a11bfa`** = FL.13, also on origin. Continue there (or a worktree that merges it). Do NOT start fresh off `main` (main lacks FL.6→FL.13). Verify `git log --oneline -1` shows `[RICERCAR-FL.13] … per-colour motion from separated stems (hybrid)`.
- Gates green at head: `swiftlint … --strict` = 0; `xcodebuild -scheme PhospheneApp build` = SUCCEEDED; `swift test --filter RicercarFlowRenderTests` = pass.
- `FlowConfig` Swift↔MSL layout is currently matched (24 scalar floats + 4 uints after the FL.13 per-family drift fields). Any new field must be added to BOTH mirrors in the same position.

## The signal (measured, don't re-derive)
`stems.csv` carries per-stem articulation signals — the staccato/legato discriminator already exists, no new DSP:
- **`<stem>AttackRatio`** (cols: drums=29, bass=33, vocals=37, other=41). Baseline **~1.0**, peaks **~3.0**. HIGH = sharp/percussive/staccato; LOW/sustained = legato. These reach `StemFeatures` — CONFIRM the exact field names (`drumsAttackRatio` etc.) in `Sources/Shared/StemFeatures.swift` and that they're populated on the GPU path (if not on `StemFeatures`, that's a prerequisite plumb — surface it before task 3).
- Also available per stem: `OnsetRate` (~2, rhythmic density), `EnergySlope`, `Centroid`.
- FL.13 already maps each COLOUR to a stem (hybrid): strings←(vocals|strings), brass←(bass|brass), woodwinds←(other|woodwinds), percussion←(drums|percussion). Reuse this mapping — each colour reads ITS stem's AttackRatio.

## The design challenge (solve this first — it's the crux)
"Shorter, choppier lines" vs "longer, flowing lines" is about **per-colour TRAIL LENGTH / continuity**, but the current trail is a SINGLE shared `rgba16Float` texture with ONE global `decay` — you cannot decay one colour's trail differently in a shared texture. Candidate mechanisms (pick one, justify it; a still frame + the harness video judge it):
- **Per-family particle LIFE** — staccato colours get short life (respawn fast → short line segments); legato colours long life (long continuous ribbons). Life is per-particle in the buffer; modulate at respawn from the family's smoothed AttackRatio env. Cheapest, no new texture.
- **Per-family deposit continuity** — staccato colours deposit intermittently (dashed/broken line); legato deposit continuously. Risk: reintroduces a "flicker" — verify it doesn't read as the herky-jerky Matt rejected.
- **Per-family motion coherence/step** — staccato = more turbulent / shorter coherent runs; legato = laminar long arcs. (Turbulence is currently global — would need per-family.)
- Per-family trail textures — powerful but HEAVY (4× the trail memory + passes); only if the cheaper options can't deliver.

## Numbered tasks
1. **Confirm the AttackRatio signal on the GPU path.** Verify `StemFeatures` exposes per-stem AttackRatio (and it's non-zero in the two session `stems.csv`). **Done-when:** the field names are confirmed in `StemFeatures.swift` and a one-line note records whether a plumb is needed. If a plumb is needed, it's task 1.x (its own commit) before task 3.
2. **Add a per-family articulation env** in `RicercarFlowGeometry.advanceEnvelopes` — smoothed per-colour AttackRatio (map each colour to its stem's attack, like the hybrid activity env; ~0.3 s smoothing so line character shifts gracefully, not per-note jitter). **Done-when:** a `currentArticulation` test hook returns a per-family SIMD4 that rises on percussive input and sits low on sustained.
3. **Implement the chosen line-character mechanism** so staccato colours paint shorter/choppier lines and legato colours longer/flowing. Keep FL.13's smooth per-colour MOTION intact (do NOT pause/stutter motion — FA: FL.12 herky-jerky). **Done-when:** the flow gate stays green AND the render visibly differentiates a high-attack family (short segments) from a low-attack family (long ribbons).
4. **Validate on real audio** via `RicercarFluidVideoHarness` on the Beethoven corpus track (`/Volumes/Extreme SSD/S/…/18 Symphony No.7…mp3`, `RICERCAR_BPM=143.2`) AND ideally a rock track — extract frames, confirm staccato-vs-legato reads. **Done-when:** contact-sheet / video frames show the distinction; sync report INTENSITY r still positive.
5. **Stop and report to Matt with frames/video BEFORE claiming done** — this is a felt/visual call he judges live (the harness can't run Open-Unmix, so the band-stem articulation is live-only). Recommend, let him confirm.

## Do NOT
- Do NOT re-introduce a global beat pulse into MOTION or a global brightness bloom — Matt rejected it as herky-jerky/disruptive (FL.12 live read). The grid-beat env is kept computed + unit-tested ONLY for a possible future *non-disruptive* accent; do not wire it to the render without Matt's ask.
- Do NOT break FL.13's per-colour hybrid MOTION (each colour = its own stem, band-stem|family max). Articulation is additive character, not a re-architecture.
- Do NOT drive line character off the laggy instrument-family capture ALONE (dead on rock — Nirvana strings/brass/woodwinds ≈ 0); use the per-stem AttackRatio (real-time) as primary, family as the orchestral fallback (mirror the FL.13 hybrid).
- Do NOT flip `certified` — Ricercar is uncertified; certification (Gate 6 §8) is a separate future increment.
- Do NOT touch parallel-session noise on the primary checkout (untracked `*.premerge-bak`, CENSUS, etc.).

## Verification commands
```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine --filter RicercarFlowRenderTests 2>&1
RICERCAR_VIDEO=1 RICERCAR_SECONDS=16 RICERCAR_BPM=143.2 RICERCAR_AUDIO="/Volumes/Extreme SSD/S/Soundtracks/[2007] - The Darjeeling Limited/18 Symphony No.7 In A (Op 92) - Allegro Con Brio.mp3" swift test --package-path PhospheneEngine --filter RicercarFluidVideoHarness 2>&1
```
(Worktree caveat: ~21 engine fixture tests fail environmentally — app build + lint + the Ricercar/flow tests + the harness are the trustworthy signals.)

## Commit + closeout
- Small commits: `[RICERCAR-FL.14] <component>: <desc>` via `git commit -F` (message FILE, not `-m` with backticks). Local commits on `claude/ricercar-rework`; **push only on Matt's explicit "yes, push"** — then FF the primary checkout (`git -C <primary> merge --ff-only <sha>`) so his live build has it ([[worktree-changes-reach-build]]).
- Closeout: invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Update RICERCAR_DESIGN §FANTASIA REBUILD (FL.14 entry), ENGINEERING_PLAN (FL.14 row), and memory `[[ricercar-and-instrument-capture]]`.
- The gate is **Matt's live eye** (staccato reads choppy, legato reads flowing, motion still smooth) — not the green tests. State it as "code-complete, pending live look."
