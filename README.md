# Uzume

Uzume is a native macOS music-visualization engine for Apple Silicon. It
connects to a playlist, pre-analyzes every track (ML stem separation + music
information retrieval on preview clips) before the music starts, and a
deterministic session planner sequences the whole visual session — which
visualizer accompanies each track, where transitions land, and the emotional
arc across the playlist. During playback, real-time analysis of the system
audio refines the plan as the music unfolds. Machine learning does the
listening; the planning is rules-based and reproducible.

Uzume does not control playback: you play music in your streaming app (or
from local files) while Uzume listens and performs the visual accompaniment.
The name is **Ame-no-Uzume** (oo-ZOO-meh), the kami whose planned, drummed
performance drew the sun back out of the cave — a session is planned, a
performance unfolds, and music is answered in light. Brand, naming evidence
and the design system live in the companion repo
[`hoaxpoet/uzume-site`](https://github.com/hoaxpoet/uzume-site).

See [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md) for the full product
definition.

## Requirements

- **Apple Silicon Mac** (performance target: 60 fps at 1080p)
- **macOS 14.0+** (Sonoma)
- **Xcode 26.5** (pinned in [.xcode-version](.xcode-version)) — Swift 6.0, Metal 3.1+

## Getting started

```bash
git clone https://github.com/hoaxpoet/uzume.git
cd uzume

# ML weights (~167 MB) ship as a GitHub Release asset, not repo content:
Scripts/fetch_weights.sh

# Build the app
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build

# Engine test suite (the canonical runner — do NOT use xcodebuild for engine tests)
swift test --package-path UzumeEngine

# App-target tests
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test

# Lint (force_cast/force_try/force_unwrapping are errors)
swiftlint lint --strict --config .swiftlint.yml
```

For the inner dev loop, `Scripts/test_fast.sh` runs the pure-logic core
(~1,000 tests in ~13 s), skipping GPU/ML/audio-fixture suites.

**Known test caveats on a fresh clone:**

- ~21 tempo tests exercise licensed audio fixtures that are deliberately not
  in the repo. `Scripts/bootstrap_fixtures.sh` restores them (re-fetches
  30-second preview clips from the iTunes Search API). `Scripts/test_fast.sh`
  is green without them.
- A handful of performance suites assert wall-clock budgets calibrated on an
  M-series Mac mini; on slower machines prefer `Scripts/test_fast.sh` +
  targeted `--filter` runs.

## Running it

- **No streaming account needed:** File → Open Local File (⌘O) plays local
  audio with the full analysis + visualization pipeline.
- **Streaming (Spotify/Apple Music):** Uzume taps system audio output,
  which requires the Screen Recording permission (audio only is captured).
  Spotify connector setup (bring-your-own client ID, PKCE — no secret) is in
  [docs/RUNBOOK.md](docs/RUNBOOK.md).
- **Developer gotcha:** every rebuild re-signs the binary and macOS silently
  orphans the Screen Recording grant — the tap goes silent while the app
  looks ready. Recovery: `tccutil reset ScreenCapture io.uzume.mac`,
  re-grant, relaunch. Or just develop against local-file playback, which
  needs no permission.

## Contributing presets

That's why this repo is public — see [CONTRIBUTING.md](CONTRIBUTING.md).
A preset is a Metal shader + JSON sidecar drop-in; you can develop and test
one end-to-end with local files and `swift test`, no accounts or extra
hardware required.

## Documentation map

| Doc | What it covers |
|---|---|
| [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md) | Product definition |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Module map, audio analysis, key types, GPU contract |
| [docs/SHADER_CRAFT.md](docs/SHADER_CRAFT.md) | Visual quality bar, shader technique, preset sidecar schema (§17) |
| [docs/PRESET_SESSION_CHECKLIST.md](docs/PRESET_SESSION_CHECKLIST.md) | The preset-authoring discipline |
| [docs/RUNBOOK.md](docs/RUNBOOK.md) | Build/test mechanics, connector setup, troubleshooting |
| [docs/UX_SPEC.md](docs/UX_SPEC.md) | UX contract and error taxonomy |
| [docs/ENGINEERING_PLAN.md](docs/ENGINEERING_PLAN.md) | Roadmap and increment history |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Numbered engineering decisions (D-###) |
| [docs/CREDITS.md](docs/CREDITS.md) | ML weights + Milkdrop-inspired preset attribution |
| [docs/GLOSSARY.md](docs/GLOSSARY.md) | The internal shorthand decoded (D-###, M7, increment IDs, …) |
| [docs/presets/YOUR_FIRST_PRESET.md](docs/presets/YOUR_FIRST_PRESET.md) | A complete working preset pair in ~60 lines (gate-verified to compile) |

This project is developed by Matt (product/design) with Claude Code doing the
implementation; the docs and `prompts/` directories reflect that working
process. Internal shorthand you'll meet in the docs is decoded in
[docs/GLOSSARY.md](docs/GLOSSARY.md) — the load-bearing three: `D-###` = a
numbered decision in DECISIONS.md; `[XX.n]` = an increment ID in
ENGINEERING_PLAN.md; "M7" = the maintainer's live visual review, the
load-bearing quality gate for presets.

## License

MIT — see [LICENSE](LICENSE). Milkdrop-inspired presets carry per-preset
attribution (see [docs/CREDITS.md](docs/CREDITS.md)); Uzume honors
takedown requests routed through the projectM team.
