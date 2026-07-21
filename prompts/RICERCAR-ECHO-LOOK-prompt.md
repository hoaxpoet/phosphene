# RICERCAR-ECHO — the LOOK (collaborative session)

**This is a COLLABORATIVE, iterative aesthetic session with Matt. Not a spec to execute — a design loop.** The previous session solved the hard part (sync). This session makes it *beautiful and engaging*. Matt drives aesthetic direction; you propose, render, and show — he reacts. Work in small steps.

## Objective
Make the Ricercar-echo prototype's **look** rich and engaging enough that "a stoned person can look at it for 30 s" (Matt's bar). It currently reads "meh" / "pretty basic" — programmer-art marks. The goal is Fantasia *Toccata & Fugue* richness: painterly, atmospheric, hypnotic, with variety and depth.

## ★ How to work (these are load-bearing — the last session failed for days by ignoring them)
1. **Talk it out with Matt BEFORE building.** Every failure came from improvising a mechanism instead of discussing the concept first.
2. **SEE what you're drawing from.** Do NOT describe Fantasia from memory. Matt has a screen recording of the T&F segment (ask him for it / the path; last one was `~/Desktop/Screen Recording ....mov` — note macOS uses a U+202F narrow-no-break-space before "PM", so glob it: `ls ~/Desktop/*.mov`). Copy it to scratch, extract frames with ffmpeg (`ffmpeg -ss <sec> -i vid -vf "fps=2,scale=480:-1" out_%03d.png`), montage sequences, and STUDY the motion. **Reference 3:38 onward** (the counterpoint section Matt pointed to).
3. **Show frames/video, not descriptions.** Render, drop a clip in `/tmp/ricercar_fluid_diag/`, let Matt look. One visible change at a time — never ship an imperceptible tweak and ask him to re-test.
4. **"Inspired by, not a recasting of" Fantasia.** Take the spirit, don't reproduce its literal forms.

## ★ HARD CONSTRAINTS — do NOT break these
- **Sync is SOLVED. Do NOT touch the onset/emission logic.** Marks fire ONLY on note onsets — nothing on a timer, rate, or sustain-fill (Matt: any fill "puts marks where there are no notes"). The detector is a RELATIVE local transient `(levFast−levMed)/levMed` on the AGC band levels. Leave `advance()`'s onset block alone unless Matt explicitly asks.
- **NOT luminosity/neon.** Matt: "why are you obsessed with luminosity for this preset?" The T&F segment is PAINTERLY — soft, warm, atmospheric, colour-rich — not glowing neon. Don't reach for more bloom/exposure as the richness lever.
- **The background is the LEAST important thing.** Matt: "the look and the sync of the drawing is what will sell this preset." Focus on the MARKS (the drawing), not the ground.
- **Legato = long flowing line; staccato = short clip; pizz = dot.** Colour = the instrument section (PANNs family, dev-weighted; alive on orchestral). Keep these.

## What the LOOK work actually is (the marks)
Richness/variety/depth/motion IN THE MARKS and their weave. Candidate directions to discuss with Matt (don't just pick): more elegant/varied gesture shapes; a more brush/painterly stroke quality (soft, textured, tapered — some taper exists); depth/layering; how the legato lines *flow* and weave as counterpoint; colour interplay; how a mark is *born* and *dies*. The Fantasia marks are tiny, sparse, gestural, and elegant — study them.

## State
- **Branch `claude/ricercar-fl14-prompt-7de805`** (off the FL work; primary checkout is on `claude/ricercar-rework`). The echo prototype commits are `[RICERCAR-ECHO] …`. **UNPUSHED.** Verify `git log --oneline` shows the ECHO commits ending with the onset-only sync fix.
- **Uncoupled — NOT a selectable preset.** Driven only by the test harness. (Wiring it into the app for live testing is a separate step; only on Matt's ask.)
- Files: `PhospheneEngine/Sources/Renderer/Geometry/RicercarEchoGeometry.swift`, `PhospheneEngine/Sources/Renderer/Shaders/RicercarEcho.metal`, `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/RicercarFluidVideoHarness.swift` (holds `test_echoPrototypeVideo` + `test_echoSyncDiagnostic`). Skills: invoke `shader-authoring` before editing the `.metal`.

## Tools
- **Render a synced clip** (Matt watches this): `RICERCAR_ECHO=1 RICERCAR_SECONDS=60 RICERCAR_AUDIO="/Volumes/Extreme SSD/S/Soundtracks/[2007] - The Darjeeling Limited/18 Symphony No.7 In A (Op 92) - Allegro Con Brio.mp3" swift test --package-path PhospheneEngine --filter test_echoPrototypeVideo` → outputs `/tmp/ricercar_fluid_diag/ricercar_echo_<track>_with_music.mp4` (audio muxed) + PNG frames in `echo_frames/`. Copy to a clean name for Matt. ~2 min per 60 s render.
- **Fast diagnostic (no render)**: `RICERCAR_ECHO_DIAG=1 … --filter test_echoSyncDiagnostic` — marks/sec, density↔energy r, articulation split, opening trace. Use for anything measurable before a slow render.
- **Contact sheets** (to self-review the look without watching): sample frames from `echo_frames/` and `ffmpeg … tile=…`. You can VIEW png montages; you canNOT watch video-with-audio (Matt judges sync).
- Gates: `swiftlint lint --strict --config .swiftlint.yml` (RicercarEchoGeometry.swift is close to the 400-line cap — watch it) + `xcodebuild -scheme PhospheneApp build`. Shaders compile at test runtime via ShaderLibrary (auto-discovers `.metal`).

## Read first
1. Memory `[[ricercar-and-instrument-capture]]` — the RICERCAR-ECHO section (full journey, the sync solution, the Fantasia grounding, the "meh → look" handoff).
2. `git log --oneline` for the `[RICERCAR-ECHO]` commits (the arc: prototype → tiny sparks → colour=instrument → painterly ground → legato-flows → sync fixes).
3. The Fantasia recording (study it, per rule #2 above) before proposing any look direction.

## Process / closeout
- Small commits `[RICERCAR-ECHO] <component>: <desc>` via `git commit -F`. **Push only on Matt's explicit "yes, push."**
- The gate is **Matt's eye** on the rendered clip — not tests. State look changes as "rendered, pending Matt's look."
- If it gets stuck (imperceptible changes, thrashing, Matt frustrated): STOP, study the reference again, talk it out. Don't blind-iterate.
