# Preset Certification-Readiness Audit — 2026-06-01

**Goal:** identify which uncertified presets are the best near-term bets to drive to M7 certification, to grow the certified catalog from 2 → ~5 and unblock planned-mode variety (BUG-021) + the multi-preset-per-song planner.

**Method + honest constraint.** The rigorous tool (`PresetSessionReplay`, SR.1) needs a recorded session *with video* per preset to score route-firing + calibrated rubric σ-distance to the reference family. **That data does not exist right now** — only 11 sessions remain on disk (retention pruned the rest) and just 1 has video. So this audit is **documentary** (each preset's actual M7 history, cert-attempt state, reference coverage, investment depth, documented blocking gap) plus **fresh static contact sheets** for the 4 presets the visual-review harness covers. The rigorous proxy/σ-distance confirmation is **deferred to step 1 of whichever preset is picked** (capture a real session → run the replay tool).

**Discipline note.** The ranking below is from *documented evidence* (M7 verdicts Matt recorded, cert-attempt states, reference coverage, round counts) — NOT from the audit author grading rendered frames. Visual readiness is Matt's M7 call; the contact sheets are for his eye to validate or override this ranking.

---

## Headline findings

1. **Certification is a hard, M7-gated grind.** Both certified presets took *dozens* of rounds — Lumen Mosaic "M7 pass after eight calibration rounds" (LM.3.2); Ferrofluid Ocean certified at round 69 (V.9 4.5c). Budget multiple M7 rounds per cert, not one.

2. **The two most-invested uncertified presets are the most M7-bruised — NOT the closest to cert.** This is a sunk-cost trap:
   - **Arachne** (60 commits, 20 refs) carries a *documented structural* fidelity gap: Failed Approaches #48 + #49 found the renderer produces "a stylized 2D bullseye visually distant from the references," and the references demand compositing layers the renderer structurally lacks (background pass + refraction + depth-of-field). D-072 pivoted to a "V.8 architecture" (compositing-anchored, not tuning). Its *most recent* work (BUG-011 rounds 4–8) was perf, not fidelity. A cert push here is a render-pass-building increment, not a tuning pass.
   - **Aurora Veil** reached the *closest* to an actual cert attempt (AV.3 cert-prep + M7 handoff), but with a trail of route-firing bugs (PT.1: `vocalsPitchConfidence` fired 0 % of frames for ~5 months under "tests green" closeouts), the mv_warp painterly-smear saga (AV.1/2/2.1 shipped broken), an uncommitted AV.2.h.1 carry-over set aside 2026-05-20, **and no reference README** (Failed Approach #63 blocker — must be curated before any AV authoring).

3. **The visual-review harness covers exactly Arachne, Aurora Veil, Gossamer, Volumetric Lithograph** (+ certified Lumen Mosaic). Fractal Tree / Kinetic Sculpture / Glass Brutalist / Membrane have reference sets but no harness entry — they're dormant.

---

## Per-preset readiness

| Preset | Refs | Investment | Last cert-relevant state | Documented gap / risk | Fresh sheet |
|---|---|---|---|---|---|
| **Volumetric Lithograph** | 7 + README | 8 commits, 18 PLAN | The mv_warp musicality **reference implementation** (D-027); in active harness | No documented structural wall | ✅ |
| **Gossamer** | 11 + README | 13 commits | "Comprehensive visual remaster"; explicitly flagged for a "Gossamer-class uplift phase" (78c6a547); active harness | Acknowledged remaining uplift work | ✅ |
| **Aurora Veil** | 5, **no README** | AV.1→AV.3 | Reached AV.3 **cert-prep + M7 handoff** (closest to a cert attempt) | Route-firing history (PT.1), mv-warp smear saga, uncommitted carry-over, **README missing (FA#63)** | ✅ |
| **Glass Brutalist** | 8 + README | 9 commits | Geometric; dormant (no harness entry) | Current state unknown (no fresh sheet) | ❌ |
| **Membrane** | 8 + README | 4 commits | Reaction family; dormant | Current state unknown | ❌ |
| **Arachne** | 20 + README | **60 commits** | V.7.9 ✅ / V.7.10 M7 pending; recent work was perf | **Structural** fidelity gap (FA#48/#49, D-072 V.8 pivot) — needs new render passes | ✅ |
| **Kinetic Sculpture** | 10 + README | **1 commit** | Geometric; minimal implementation | Early-stage shader; far from cert | ❌ |
| **Fractal Tree** | 15 + README | **1 commit** | Fractal; minimal implementation | Early-stage shader; far from cert | ❌ |

---

## CORRECTION (2026-06-01, post-review) — there is a documented cert ladder; follow it

The first draft of this audit anchored on *investment as a proxy for cert-proximity* and recommended the already-worked presets (VL / Gossamer). That was wrong on two counts, surfaced by Matt's pushback:

1. **Investment ≠ proximity to cert.** Arachne is the proof: most-invested (60 commits), furthest from cert (structural gap). Prior work can entrench problems rather than approach the bar.
2. **I missed a documented, ordered cert ladder.** D-072's system-wide "same visual conversation, not pixel-match" reframe + the `SHADER_CRAFT.md §10.x` uplift specs define an explicit sequence:

   | Rung | Preset | Spec | State |
   |---|---|---|---|
   | V.8 | Arachne | §10.1 (+ `ARACHNE_V8_DESIGN.md`) | structural pivot, stalled |
   | V.8 | Gossamer | §10.2 | remaster done, not certified |
   | V.9 | Ferrofluid Ocean | §10.3 | ✅ **certified** (round 69) |
   | **V.10** | **Fractal Tree** | **§10.4** | **next designated rung** |
   | V.11 | Volumetric Lithograph | §10.5 | after Fractal Tree |
   | V.12 | Glass Brutalist + Kinetic Sculpture | (specs TBD) | last |

   The ladder *deliberately* puts the low-code-investment preset (Fractal Tree, 1 fidelity commit) next — because its prerequisite work is what's done: **15 reference images + a session-ready annotated README + a written §10.4 uplift spec**, with zero entrenched fidelity debt.

3. **The VL claim was overstated.** VL has *never had an M7 review*; "the feedback-accumulation problem is already solved" conflated "the `mv_warp` pass is wired" with "the visual reads cert-ready." Retracted. VL is V.11 — after Fractal Tree.

## Recommendation (corrected) — follow the ladder: Fractal Tree (V.10) next

**Fractal Tree** is the best next cert target — not despite its low code-investment but *because* of it: the de-risking groundwork (complete reference set + §10.4 spec + ladder slot) is done, and there's no baked-in fidelity debt to un-stick. This is the "choose a preset that hasn't had much work" path, and it's also the documented plan.

**Honest risk (not soft-pedaled):** it's still a from-near-scratch *hero-fidelity* uplift — painterly translucent SSS leaves, golden-hour lighting, bark POM displacement — exactly the high-fidelity ambition that has been botched before. It's a multi-round M7 grind like every cert (Lumen Mosaic 8 rounds, FFO 69), not a quick win. The mitigants are real (complete references, written spec, the "same visual conversation" reframe) but the fidelity ceiling is high.

**Then:** Volumetric Lithograph (V.11), Glass Brutalist + Kinetic Sculpture (V.12), per the ladder.

**Not near-term:** Arachne (a V.8 render-pass build, not a tuning pass) and Aurora Veil (route-debt + missing README — off the V.10–V.12 ladder).

---

## Next step once a preset is picked

1. Capture a real session with the picked preset active + recording on (replaces the pruned session data).
2. Run `PresetSessionReplay` against it → route-firing % + calibrated rubric σ-distance to the reference family. This is the objective confirmation this audit couldn't run.
3. M7-prep contact sheet (D-071) → targeted uplift to close the *named* gaps → Matt M7 review → certify.

**Contact sheets for this audit:** `/tmp/phosphene_visual/20260601T183401/` (Arachne, Aurora_Veil, Gossamer, Volumetric_Lithograph — silence/mid/beat frames; Arachne also has a contact sheet).
