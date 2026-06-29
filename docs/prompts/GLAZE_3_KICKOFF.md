# GLAZE.3 Kickoff — base audio coupling (make the jelly move with the music + fill the contour field)

**Paste "Resume GLAZE.3 — follow docs/prompts/GLAZE_3_KICKOFF.md" to start the session.**

Glaze is a faithful Phosphene port of the Milkdrop/butterchurn preset `Flexi + stahlregen - jelly
showoff parade` (glossy "wet jelly" contour-gel). Branch `claude/nice-rubin-9c10c7` (pushed; HEAD
`ad42eb4`). The faithful BASE is built, grain-fixed, and M7-confirmed "beautiful" by Matt. This
increment wires the audio so the field moves with the music and the full contour field fills in.

---

## 0. THE one rule — read before writing any code

**The grain root cause is solved by a structural rule that MUST be preserved: sharpening is
DISPLAY-only, never in the fed-back warp.** An unsharp/high-pass term in the warp feedback loop has
gain > 1 and compounds into razor-filament grain on our float buffer (the Milkdrop source only
survives it via 8-bit storage quantization, which we can't replicate). The warp advects + decays +
seeds (smooth); the comp embosses for display (never fed back). **Do not add any sharpening/high-pass
into the warp loop.** See `docs/presets/GLAZE_PLAN.md §grain-root-cause` + `[[project_glaze_preset]]`.

Second rule (faithful-first, FA #65): the source's own audio coupling is the map. Adopt it; adapt only
to Phosphene's deviation primitives (D-026). Drive motion from **deviation** (`f.bassDev`,
`f.trebleDev`, `*EnergyDev`), NEVER absolute thresholds on AGC-normalized energy (FA #31).

## 1. Current state — GLAZE.2b.2 is DONE (faithful base, grain-fixed)

The base renders the glossy contour-gel: a 3-mass spring chain (CPU, `GlazeSpring` in
`RenderPipeline+Glaze.swift`) drives a fragment-stage swirl-poke; butterchurn's exact per-vertex
`zoomexp` radial zoom + 4-term warp ripple accrete nested rings; a structure SEED (a curve = the
source's `wave_a 0.207` waveform role) + faint low-freq noise floor; the comp does multi-scale unsharp
emboss from a 3-level blur pyramid (¼/⅛/1⁄16 res) + palette + contrast + sRGB. **Grain GONE** (the §0
rule). GPU perf excellent (p99 4.4 ms, 0% over budget).

**The base is currently AUDIO-INDEPENDENT** — the spring anchor + seed are pure time-driven idle. That
is why at silence it reads **band-like** (one wavy band of contours, not the oracle's full field) and
why it looked identical regardless of signal quality in the M7. **Wiring audio is what fills the field
+ adds the reactivity** — that is this increment.

Two open LOOK gaps from M7 (tune these along the way, they're not blockers): the **ground reads green**
(the comp's `+1.0` lift over a dark feedback — lower it / darken the ground toward the oracle); and the
**field is band-like at silence** (the audio-driven seed/poke sweeping the frame is what fills it).

## 2. The goal — wire the §6 base audio routes, one at a time

`docs/presets/GLAZE_PLAN.md §6` is the routing table (one-primitive-per-layer, FA #67). The source's
own coupling (frame_eqs): `x1 = .5 + 1.5*(bassEMA − trebEMA)`, `y1 = .5 + energyEMA` — the spring
**anchor** is audio-driven; the chained masses lag/bounce/settle (the jelly). Today the anchor is
`computeGlazeUniforms`'s time-sine idle; replace it with audio:

| Visual layer | Route | Source eq |
|---|---|---|
| Spring anchor X (lateral swing) | `f.bassDev` one dir − `f.trebleDev` other dir (EMA-smoothed) | `xx1`/`xx2` → `x1` |
| Spring anchor Y (lift) | avg-energy envelope (EMA) | `yy1` → `y1` |
| (all field motion) | — the spring integrates the anchor (smooth overshoot; sidesteps FA #4/#31 by construction) | the chain |
| (warp poke + seed location) | — driven by the spring tail (`q4`/`q5`) → the seed sweeps the frame → fills the field | pixel_eqs |
| Palette hue | time [+ optional small chroma/centroid-deviation nudge, Nacre.3 precedent] | `hue_shader` |

The spring is a natural rhythm integrator — drive the **anchor**, let physics make the motion. The
seed currently is a time-sine curve; to fill the field, drive its position/shape with the audio (or
the spring-tail poke), OR bind the real waveform (buffer 2) as the seed (the source's literal `wave_a`)
— decide by render-compare which fills the contour field cleanly without reintroducing grain (§0).

## 3. Read-first (mandatory — before any .metal/.swift)

1. `docs/PRESET_SESSION_CHECKLIST.md` — the mandatory opener (musical role, temporal contract,
   production-grade testing, evidence-based closeout).
2. `docs/presets/GLAZE_PLAN.md` — esp **§grain-root-cause** (the §0 rule), **§6** (routing), **§0**
   (greenlit scope: base + uplifts A/B/C *after* base cert), §1 (musical role), §2 (temporal contract).
3. `docs/VISUAL_REFERENCES/glaze/` — `README.md` (trait annotations + anti-references), the oracle
   `target_animated.gif` + stills, `source_shaders.txt` (the decoded port artifact). The oracle is
   real-music-driven — that full contour field is the GLAZE.3 target (audio fills it).
4. `[[project_glaze_preset]]` (memory) — the grain lesson, the new-preset gate-registration list, the
   sidecar-decode gotcha, the worktree-build M7 path.
5. CLAUDE.md §Audio Data Hierarchy + D-026 (deviation primitives) + the cold-start phase contract.
6. The code: `RenderPipeline+Glaze.swift` (`computeGlazeUniforms` — where the routes land; `GlazeSpring`),
   `Glaze.metal` (the warp seed + comp).

## 4. Session-review facts (from 2026-06-26T22-31-56Z — use for replay evidence)

Drive routing tuning from a recorded session's `features.csv`/`stems.csv` (the `PresetSessionReplay`
diagnostic), NEVER synthetic envelopes (FA #27). The M7 session
`/Users/braesidebandit/Documents/phosphene_sessions/2026-06-26T22-31-56Z` (School of Seven Bells,
153 BPM) is a clean reference:
- **Audio is healthy + rich**: bass to 2.46 (dev to 2.25), all four stem energies + `*EnergyDev` active
  (73–88% nonzero, ranges to ~2.3–2.5), no NaN/Inf in 4093 frames. Plenty to drive the routes.
- **★ Per-stem BEATS are dead except drums**: `drumsBeat` active (97%), but `bassBeat`/`vocalsBeat`/
  `otherBeat` are identically 0 across the session. **Not a GLAZE.3 blocker** (GLAZE.3 uses bands +
  energy-deviation, not stem-beats), but it IS load-bearing for **uplift A (GLAZE.5, per-stem routing)**:
  route per-stem transients via `*EnergyDev`, not the dead `*Beat` channels. Confirm with Matt whether
  the dead stem-beats are by-design or a gap before GLAZE.5.

## 5. Approach + discipline

- **One route at a time**, render-compare + session-replay evidence per route; audit the
  one-primitive-per-layer table (§6) after each (FA #67 — don't route two layers off one primitive at
  one timescale).
- **Production-grade test path**: the `GlazeMVWarpAccumulationTest` (env-gate `GLAZE_MVWARP_DIAG=1`)
  drives the live `renderGlaze` warp→comp→swap loop; extend it for the audio routes (drive
  `features.csv` rows, assert per-route firing). Keep the non-black + no-white-out gate green.
- **Grain watch (§0)**: after each route, re-render at 600 frames and confirm NO grain returns (audio
  shouldn't reintroduce a high-pass into the warp loop).
- **M7 the look live**: build the WORKTREE app (not the primary — Glaze is branch-only), play a local
  file, ⌘] to "Glaze". Exact path + steps in `docs/presets/GLAZE_M7_BRIEF.md`. Matt's eye is the gate.
- **After every M7 round write one sentence**: "what I now believe about why this is/ isn't working."
- **Closeout protocol** (CLAUDE.md): `Scripts/closeout_evidence.sh` block, update GLAZE_PLAN §7 +
  ENGINEERING_PLAN + the Module Map if files change, KNOWN_ISSUES if a defect is filed. New-preset gate
  note: Glaze is already registered (count/acceptance-exemption/Module-Map) — no re-registration needed.
- **Do not push without Matt's "yes, push."** Local `main`/branch commits stay local until he approves.

## 6. After GLAZE.3

GLAZE.4 = tune the base (incl. the green ground) to base-cert / Matt's M7 sign-off. THEN the greenlit
uplifts (FA #65, base-confirmed first): **GLAZE.5 = A** per-stem instrument routing (mind §4 — use
`*EnergyDev`, the stem-beats are dead); **GLAZE.6 = B** HDR glossy bloom (re-unclamp + display-stage
bloom; flash-safe via the multi-pass harness); **GLAZE.7 = C** shiver mode; GLAZE.8 = certification.

**TL;DR:** Glaze's faithful base is built + grain-fixed + "beautiful" but audio-blind. Wire the §6
spring-anchor routes (bass/treble → lateral, energy → lift) off deviation primitives, one at a time,
with session-replay evidence — the audio-driven spring/seed is what fills the full contour field + makes
the jelly bounce. NEVER put sharpening in the warp loop (the grain rule). Faithful-first; M7-gated.
