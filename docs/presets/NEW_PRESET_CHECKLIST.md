# New preset — every file you will touch

Lifecycle-ordered checklist of the registration points a preset crosses from
first sketch to certification (PUB.7, from the ultra review's touch-point
audit). The dual-entry test tables near the end are **deliberate fail-loud
gates** — they are the mechanism, not friction to refactor away.

Jargon: [docs/GLOSSARY.md](../GLOSSARY.md). Authoring discipline (read first):
[docs/PRESET_SESSION_CHECKLIST.md](../PRESET_SESSION_CHECKLIST.md).

## 1. Develop (nothing to register)

- [ ] `~/Library/Application Support/Phosphene/Presets/<Name>.metal` + `<Name>.json`
      — hot-reload dev loop, zero repo edits (CONTRIBUTING §dev loop).
      Or in-repo from the start: `PhospheneEngine/Sources/Presets/Shaders/`
      (auto-discovered at build; no pbxproj edit — the Shaders directory is a
      bundled SPM resource).

## 2. Land in-repo (2 files + references)

- [ ] `PhospheneEngine/Sources/Presets/Shaders/<Name>.metal`
- [ ] `PhospheneEngine/Sources/Presets/Shaders/<Name>.json` — schema:
      [SHADER_CRAFT §17](../SHADER_CRAFT.md#17-preset-metadata-format-json-sidecar).
      `certified: false`; non-empty `audio_routes`; mv_warp presets need
      `fragment_function`; Milkdrop-inspired presets need `inspired_by`.
- [ ] `docs/VISUAL_REFERENCES/<name>/` — copy `_TEMPLATE`; reference imagery
      with provenance/licensing rows (real photography or in-engine capture;
      AI images only in the anti-reference slot per D-065).
- [ ] Milkdrop-inspired only: a row in `docs/CREDITS.md` §Milkdrop-inspired
      preset attribution. **Never commit a `.milk` file.**

## 3. Make the automated gates green (no new files — they discover you)

- [ ] `RouteCoverageTests` — every `audio_routes` entry fires on the committed
      real-music fixtures. A red route is the gate working: fix the route or
      the declaration, never the floor.
- [ ] `FidelityRubricTests.expectedAutomatedGate` — the completeness assertion
      FAILS your PR with the value to paste until you add your preset's row
      (at its measured value, with a comment if `false`).
- [ ] `PresetLoaderCompileFailureTest` / full engine suite green;
      `swiftlint lint --strict` (`.metal` files are exempt from file-length).

## 4. Certification (maintainer-gated — see RUNBOOK §Certifying a preset)

- [ ] Maintainer's live M7 review on real music — the load-bearing gate.
- [ ] `certified: true` in the sidecar.
- [ ] `FidelityRubricTests.certifiedPresets` membership.
- [ ] `PhotosensitivityCertificationTests.multiPassMeasured` + a render
      function in `MultiPassFlashHarnessTests` for multi-pass/follower-state
      presets — measured 0.00 flashes/s (the static-render guard fails loud
      if you skip this).
- [ ] `OrchestratorCertifiedFilterTests` green — the preset now enters
      planning.

## 5. Stateful presets only (CPU-side simulation / particles)

A compute/particle preset additionally registers its geometry in the D-097
registry (`ParticleGeometryRegistry` — see how `Murmuration` / `Mitosis` /
`RicercarFlow` do it) and, today, touches up to three name-keyed sites in
`VisualizerEngine+Presets.swift` (`applyPreset`). Collapsing those into the
registry is queued work (R2); until then, copy the wiring of the closest
shipped sibling.

## 6. Docs

- [ ] `docs/ARCHITECTURE.md` §Module Map — one behavioural line per new Swift
      file (the D-168 gate fails the suite until you do).
- [ ] Optional but conventional: `docs/presets/<NAME>_DESIGN.md` for the
      design record.
