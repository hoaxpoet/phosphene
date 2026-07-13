# Contributing to Phosphene

Phosphene is open to contributions with a specific focus: **presets** — the
visualizers themselves. Engine/app changes are welcome as issues first; the
core is small-team-maintained and changes there move through the project's
decision process.

## What a preset is

A preset is a two-file drop-in, auto-discovered at build time:

```
PhospheneEngine/Sources/Presets/Shaders/<Name>.metal   — the shader(s)
PhospheneEngine/Sources/Presets/Shaders/<Name>.json    — the sidecar (metadata + audio routing)
```

The sidecar schema is documented in
[docs/SHADER_CRAFT.md §17](docs/SHADER_CRAFT.md); look at a small shipped
preset (`Waveform`, `Plasma`) for the minimal shape and at `Skein` or `Nacre`
for the full-featured shape. Stateful presets (particle systems, CPU-side
simulation) additionally register a runtime — see how `Murmuration` does it.

New to the docs' shorthand (M7, D-###, increment IDs)? One page:
[docs/GLOSSARY.md](docs/GLOSSARY.md). Want pixels moving in five minutes?
[docs/presets/YOUR_FIRST_PRESET.md](docs/presets/YOUR_FIRST_PRESET.md) — a
complete working pair, gate-verified to compile. Landing it in-repo? Every
file you'll touch: [docs/presets/NEW_PRESET_CHECKLIST.md](docs/presets/NEW_PRESET_CHECKLIST.md).

## Before you write a shader

Read these two, in this order:

1. **[docs/PRESET_SESSION_CHECKLIST.md](docs/PRESET_SESSION_CHECKLIST.md)** —
   the authoring discipline: musical role first, the temporal contract, the
   concept bar. This is distilled from many failed presets; it will save you
   weeks.
2. **[docs/ARCHITECTURE.md §GPU Contract Details](docs/ARCHITECTURE.md)** —
   texture/buffer slot conventions and the pass preamble every shader builds
   against, plus §Key Types for the `FeatureVector`/`StemFeatures` fields
   your audio routes read.

The single most important design rule (learned empirically, many times):
**drive visuals primarily from continuous energy (the deviation primitives
`bassDev`/`bassRel` etc.), not from raw live beat detections.** Beat-locked
motion is valid only on the cached `BeatGrid`. The full hierarchy is in
[CLAUDE.md §Audio Data Hierarchy](CLAUDE.md).

## The development loop (no accounts required)

1. **Hot-reload (fastest):** drop your `.metal` + `.json` into
   `~/Library/Application Support/Phosphene/Presets/` (created on first
   launch) while the app runs — every save recompiles and swaps the preset
   in live. A broken save shows a toast and keeps the previous version
   running (full compiler diagnostics in the log:
   `log stream --predicate 'subsystem == "com.phosphene.presets"'`).
   Note: a `certified: true` flag in a hot-reload sidecar is honored locally
   without the repo's flash/rubric gates — leave it `false` while developing
   and use *Show uncertified presets* (below).
2. In-repo: place the pair in `PhospheneEngine/Sources/Presets/Shaders/` and
   build; broken shaders are logged and skipped, never crash the app.
3. **Contact sheets:** `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReviewTests`
   renders your preset against recorded real-music feature streams.
4. **Reference comparison:** `Scripts/compare_render.sh <preset>` diffs
   against your reference imagery.
5. **Live:** run the app, Settings → Visuals → *Show uncertified presets*,
   then File → Open Local File (⌘O). No streaming account, no Screen
   Recording permission.

## Gates your preset must pass

All runnable locally with `swift test --package-path PhospheneEngine`:

- **Route coverage** — every `audio_routes` entry in your sidecar must be
  exercised by the committed real-music fixtures (`RouteCoverageTests`).
- **Fidelity rubric** — the automated floor for visual quality
  (`FidelityRubricTests`); the bar itself is documented in
  [docs/SHADER_CRAFT.md](docs/SHADER_CRAFT.md).
- **Flash safety** — photosensitivity gate; certified presets must measure
  0 flashes/s under the harness.
- **Lint + full suite** — `swiftlint lint --strict`; the engine suite stays
  green (`file_length` is deliberately relaxed for `.metal` — a good
  ray-march shader legitimately runs 800–2000 lines).

## Certification lifecycle

`certified: false` is how you ship. Certification — joining the production
rotation the orchestrator plans with — is a maintainer step:

1. You submit the preset PR: shader + sidecar (`certified: false`), your
   `audio_routes`, and a reference folder under `docs/VISUAL_REFERENCES/<name>/`
   (copy `_TEMPLATE`) stating the visual target and its provenance/licensing.
2. Automated gates run in CI (and locally, above).
3. The maintainer runs a live review with real music ("M7" in the docs — the
   load-bearing gate; automated gates are the floor, not the bar) and, on
   sign-off, flips `certified: true` and adds the preset to the certified
   test tables (rubric + flash harness — these are deliberate fail-loud
   dual entries).

## Milkdrop-inspired presets

Porting the *concept* of a Milkdrop preset is welcome and has an established
posture ([docs/CREDITS.md](docs/CREDITS.md)): the preset is authored from
scratch on Phosphene's primitives, carries an `inspired_by` block in its
sidecar (source preset name, original artist, pack), and gets a row in
CREDITS.md. **Never commit a `.milk` file** — no source redistribution.

## Conventions

- Swift 6, strict concurrency; no `print()` (use `os.Logger`); protocol-first
  DI; every public API gets `///` docs. See [CLAUDE.md §Code Style](CLAUDE.md).
- Commit messages: `[<increment-id>] <component>: <description>` — for an
  external PR, use your preset name as the ID, e.g.
  `[MYPRESET.1] Preset: initial drop-in`.
- Small commits over one large commit.

## Questions

Open a GitHub issue. The docs are extensive but were written for the
maintainers first — if something on the contributor path is confusing,
that's a bug in the docs; please report it.
