# WL.7 — Witchlight: make it feel tied to the music

**Status:** the ONLY open question. Everything else about this preset is settled or gated.
**Matt, 2026-08-05, after six M7 rounds:** *"You have not addressed 'still not tied to the music,' which is the most important thing."*

Certification depends on this and nothing else. He has said plainly: *"it needs to feel connected to the music, otherwise it is not a Phosphene preset I will certify."*

---

## 1. Read this before touching anything

**The single most likely explanation has NOT been tested, and it is cheap to test.**

`reframe` (`WitchlightPath+Events.swift`) chases the centroid of the **whole 30 s trail** on a 3 s follow constant, and fits `viewScale` to the **RMS radius**. RMS under-covers extremes — for a roughly linear stroke it is ~0.6 of true extent — so with `framedRadius = 0.62` the furthest bead sits at ≈ **1.03 of the half-frame, just outside the edge.**

Matt, sixth M7: *"the ribbon is moving faster than the camera can catch up, leaving the front of the ribbon out of frame for much of the run."*

**The head is where every music coupling is most visible** — the flare fires there, the newest beads are brightest there, and both the WL.4 breath and the WL.5 energy gate show most strongly there. If the head is off-frame for much of the run, *the coupling is real and invisible*.

**Test this before adding any more coupling.** Render a session, overlay the head position per frame, and measure what fraction of frames have it outside the visible rect. If it is high, fix framing first and re-ask Matt — the answer may already be built.

## 2. What is already coupled (all of it verified live, all of it gated)

| route | primitive | timescale | gate |
|---|---|---|---|
| pen heading | `tonalPhaseFifths` | 1–30 s | `headingTurnsPerTrail` ≥ 1.20 |
| pen speed | `arousal` | 10–60 s | `penSpeedSwing` ≥ 1.45 (measures 2.54–2.58) |
| ribbon breath (thickness + brightness) | `bassAtt` | **per frame** | `ribbonBreathSwing` ≥ 0.45 (measures 1.000) |
| pen advance gate (stops in silence) | `bassAtt` via `energyBreath` | per frame | `penHoldsStillInSilence` |
| bead hue | `tonalPhaseFifths` frozen | at emission | — |
| bead promotion | `barPhase01` | per bar | — |
| head flare | `bassDev` | per event | — |
| nebula hue | `valence` | 30 s+ | — |

Adding a ninth route is probably NOT the answer. Four rounds of adding coupling did not move his verdict.

## 3. What has been tried, and what each attempt actually proved

- **WL.2-i** — background was frozen (0.16 px/s); pen-speed swing 1.22–1.33× → 2.54–2.58×; emission moved per-time → per-distance. *Proved: the speed route was shallow, not dead.*
- **WL.2-j** — beads had fused into a glow tube since WL.2-g. **`ribbonShare` DOUBLED as the defect worsened** (0.687 % separated → 1.636 % fused). *Proved: a luminance gate cannot police fusion.*
- **WL.3** — "same shape every time" was the **projection**, not the motion model: unbounded `tumbleYaw` turned the drawing plane edge-on every ~57 s. Zeroing the tumble gave three obviously different figures from the same code. *Retracted a decision parked since WL.2. Proved: check the display path before re-scoping a generator.*
- **WL.4** — the preset had **no per-frame energy coupling at all**; added the breath. *Proved: necessary, not sufficient.*
- **WL.5** — the pen advanced at a constant rate regardless of audio, AND **`silent` was unreachable** (`stemTotal <= 0 && mixEnergy <= 0`; stems hold stale values, so it was never true — every silence behaviour was dead code). *Proved: a whole branch can be dead for months without anyone noticing.*
- **WL.6** — star field decoupled from audio (his call: the room should not react). Camera framing attempted **three times and reverted** — see below.

## 4. The framing trap — three failed attempts, do not repeat blind

| attempt | ribbon share | distinct beads |
|---|---|---|
| baseline | 0.489 % | 23 |
| head-weighted target (0.6/0.4), follow 3 s → 1.2 s, fit max extent × 1.12 | 0.277 % | **4** |
| + `framedRadius` 0.62 → 0.86 | 0.344 % | — |
| + fit/centre on newest 40 % of beads | 0.355 % | — |

**The tension:** fitting a 30 s trail into frame necessarily makes the drawing small, and small beads stop reading as beads — the WL.2-j distinctness gate catches that, correctly. Framing the head and keeping beads legible are in **direct conflict while the visible trail is 30 s**.

Untried, each with a real cost:
- shorten `trailSeconds` (**a concept constant — Matt's call, do not change unilaterally**);
- scale bead size with `viewScale` (**explicitly rejected at WL.2-f** — read that reasoning before reconsidering: it made beads go sub-pixel exactly as the trail filled out);
- frame a recent window with a **larger** `framedRadius` than 0.86 (only 0.86 was tried).

## 5. Process rules — these cost Matt three wasted sessions today

1. **Verify the code is in a build he can run BEFORE asking him to judge.** He tested "WL.5" twice against `main`, which did not contain it, and reported "looks unchanged" — correctly. Merge to `main`, confirm his checkout pulled it, and check a marker symbol is present. There is a memory note about exactly this trap; it was ignored.
2. **Never run background jobs that launch the app while he is testing.** A stray `closeout_evidence.sh` runs `xcodebuild test`, which SIGTERMs his running instance. That produced a fake "freeze" that wasted a diagnosis cycle.
3. **His primary checkout is the only one he builds.** Do not propose a two-checkout workflow; he has said so explicitly.
4. **Do not tune a constant to make a gate pass.** `ribbonShare` has now been inflated by a defect three separate times and fought a correct change a fourth. Peak luma and distinct-bead count are the assertions that mean something.

## 6. State

- All 21 Witchlight/QG.5 gates green; 0 lint; flash budget unmoved (peak mean luminance 0.0081).
- WL.5 is **on `main`** (PR #36, `aec624d2`). WL.6 is committed on `claude/witchlight-ribbon-luminance-237ef5` and **needs pushing + merging**.
- `certified: false`. Six of eight routes remain unbanded.
- **BUG-085** (P1, `nextDrawable` hang, ~3.6 min, stack captured) is unrelated and still has **no hypothesis** — occlusion was refuted. Separate work.
