# Glaze — M7 review brief (GLAZE.3 base audio coupling)

**What you're judging (GLAZE.3, stem-drive round):** last round you saw it as "musical but loosely connected"
and asked for the Other stem. The jelly is now driven by the **separated stems** instead of the frequency bands
— the **bass stem and the Other (guitar/synth) stem pull it in opposite directions**, overall stem energy lifts
it (the bands were near-dead on your track: treble ~4% active, so the old motion rode a thin signal). The
structure **seed rides the jelly's height** so it sweeps the frame. Judge: **(a) is it more *connected* now**
— does the motion track the guitar/synth/bass you actually hear, vs the looser "feeling" before? (b) does it
still read as *physical* (momentum, not twitch); (c) still the glossy gel register. The **full-field-density vs
dark-ground** tuning (decay) is still deferred to GLAZE.4 — don't judge that as a fail.

**Wash-out — FIXED this round (GLAZE.4, `9371bad`).** The wash was a base brightness problem (the comp's flat
`+1.0` lift made every pixel bright, and the field crept to white over minutes); dropped the floor to 0.4 +
made the seed self-limiting → a **dark ground with the bright glossy structure standing out** (the oracle
register), and it now holds steady over a full track instead of washing. Validated at playback length this time
(8000-frame renders, both tracks: meanLuma 0.82/25 % saturated → 0.34/9.5 %). **The check: play a full track
(both a calm and a loud one) and watch for a couple of minutes — does it still wash out, or does it hold a dark
ground?** If it's now too DARK, that's one knob — `kGlazeCompLift` in `Glaze.metal` (raise toward 1.0 for a
brighter ground). The audio coupling (jelly moves with the guitar/synth) is unchanged and stands.

Branch: `claude/nice-rubin-9c10c7` (pushed through `be4c475`; GLAZE.4 `9371bad` local). The worktree app is rebuilt below.

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
was made for GLAZE.3 (`xcodebuild build` BUILD SUCCEEDED at `3d71fed`; the bundle below is current). Open it directly:

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

## M7 questions (GLAZE.3)

1. Does the jelly **move with the music** — and does it read as *physical* (momentum, overshoot, settle),
   not a mechanical per-beat twitch? (The spring integrates the audio; this is the core deliverable.)
2. Does the contour field **fill / develop** on loud sections vs the band-like silence base?
3. Is the **seed-rides-the-jelly** fill approach right, or should it bind the literal audio waveform instead?
4. For GLAZE.4: how much more fill do you want (raise `decay` toward 1.0 — fills more, lifts the ground +
   bloom risk), and where should the ground brightness land?
