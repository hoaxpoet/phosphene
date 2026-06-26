# Glaze — M7 review brief (GLAZE.2b.2 faithful base)

**What you're judging:** the faithful-base *look* — does it read as the glossy "wet jelly" contour-gel
(`docs/VISUAL_REFERENCES/glaze/`)? This is the **silence / time-driven base** (the spring idles on a time
anchor; palette rotates slowly). **Audio reactivity is GLAZE.3, not here** — so it won't react much to music
yet; judge the *register, structure, and sheen*, the Nacre-2b pattern (confirm the base, then wire audio).

Branch: `claude/nice-rubin-9c10c7` (pushed). Commits: `bcba561` (mechanism) → `7ce0f38` (tuning).

---

## The gap at a glance

`/tmp/glaze_m7/glaze_vs_oracle.png` (regenerate below) — current Glaze (left) vs the oracle (right). The two
big misses are obvious:
1. **No dark ground.** Glaze is uniformly lit (green); the oracle is bright rings on a **dark** ground. The
   field equilibrium is too high → no contrast, no valleys.
2. **Chaotic ribbons vs clean concentric rings.** Glaze has glossy embossed structure but it's chaotic/grainy;
   the oracle is clean nested "fingerprint" contours.

Regenerate the side-by-side:
```sh
GLAZE_MVWARP_DIAG=1 GLAZE_W=600 GLAZE_H=450 GLAZE_FRAMES=600 GLAZE_ENERGY=0 \
  swift test --package-path PhospheneEngine --filter test_glazeRender_diag    # writes a PNG (path in the log)
# then hstack it with docs/VISUAL_REFERENCES/glaze/02_contour_striation_field.png
```

## View it live (the real M7 — production render pipeline)

**⚠️ Run the WORKTREE build, not your usual app.** Glaze only exists on this worktree branch — your
primary/canonical app (on `main`) has no Glaze, which is why cycling showed nothing. A fresh worktree build
is ready (verified: its bundled `Glaze.metal` is byte-identical to the current source). Open it directly:

```sh
open ~/Library/Developer/Xcode/DerivedData/PhospheneApp-fjevhlmowimaxjdcdeahnfybpseg/Build/Products/Debug/PhospheneApp.app
```
(Or open *this worktree's* `PhospheneApp.xcodeproj` in Xcode → ⌘R — it uses the same DerivedData.) It's a
Debug build, so the preset-cycle shortcuts are live. *(Worktree builds can't do Spotify — use a local file.)*

1. Play a **local audio file** (the app's local-file feature). The base is time-driven, so it renders alive.
2. Press **⌘]** to cycle presets (bypasses the orchestrator; a toast names each — "Preset → Glaze"). It's
   one of 22; keep pressing until the toast says **Glaze** (uncertified, so the planner won't pick it itself;
   the manual cycle holds it for the track). ⌘[ goes back.
3. Compare against the motion reference: `docs/VISUAL_REFERENCES/glaze/target_animated.gif`.

## Tuning levers (so your feedback maps to a knob)

All in `PhospheneEngine/Sources/Presets/Shaders/Glaze.metal` unless noted. After any edit, re-render with the
command above (no app rebuild needed for the headless look).

| What you see | Lever | Now | Direction |
|---|---|---|---|
| **Field too bright / no dark ground** | `kGlazeWarpDecay` | 0.93 | ↓ (e.g. 0.88) = darker ground + shorter trails + more contrast |
| **Grainy vs smooth glossy membranes** | blur pyramid res `mk(4/8/16)` in `RenderPipeline+MVWarp.swift` | ¼·⅛·1⁄16 | wider (`mk(6/12/24)`) = smoother (Nacre membrane lesson) |
| **Rings chaotic / not concentric** | the **seed** (`yCurve` waveform + `dCurve` width) | a wiggly horizontal line | shape of the seed governs the contour topology — a cleaner/slower curve → cleaner rings; this is the least-settled lever |
| **Ring spacing / flow speed** | `kGlazeZoomExp` | 11.56 | ↑ = tighter edge flow; the source value is faithful |
| **Hue / palette** | `glazePalette(t)` | green→teal→violet sines | the 3 sine phases/rates set the colour cycle |
| **Overall contrast** | comp `ret*ret`/`sqrt` + the `+1.0` lift | faithful | the `+1.0` is the source's; lowering it darkens midtones |

## The honest state (FA #64)

The structure *mechanism* is solid and verified line-by-line against butterchurn's source (warp/comp HLSL +
the per-vertex `zoomexp` mesh). What's unsettled is the **seed shape** (point→radial-rays vs curve→contours)
and the **brightness/contrast** — I hit the limit of solo headless tuning (9 render cycles; can't judge "more
jelly" without your eye). The most likely high-impact moves: **drop the decay** (dark ground) and **simplify
the seed toward a single clean slow curve** (clean rings). Your call on direction.

## M7 questions

1. Does it read as the glossy contour-gel register at all, or is it the wrong family?
2. Biggest single miss — the bright/no-dark-ground, the chaotic-vs-clean-rings, or the grain?
3. Is the faithful direction worth continuing, or should the seed/structure approach change?
