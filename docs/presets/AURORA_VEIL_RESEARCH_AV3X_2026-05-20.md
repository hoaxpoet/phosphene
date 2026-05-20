## Aurora Veil — AV.3.x Design Dossier (2026-05-20)

Diagnosis + prescriptions for the structural-fidelity gap surfaced during AV.3 cert prep on 2026-05-20.

This dossier supersedes the AV.3 sequencing-assumption (cert against the AV.2.h state) and proposes the structural work that must land before Aurora Veil can pass M7. Subsequent prompts for AV.3.x.N increments will cite specific sections of this dossier; AV.3 itself remains parked at the cert-gate.

Companion documents:
- `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` — pre-AV.1 prior-art audit. Sections referenced by §-number below.
- `docs/presets/AURORA_VEIL_DESIGN.md` — authoritative design spec; §5 architecture pivot lands here too.
- `docs/VISUAL_REFERENCES/aurora_veil/AURORA_VEIL_README.md` — the per-reference annotations + 9-Q rubric checklist.

---

## Product-level summary (read this first)

**What's wrong.** Aurora Veil's live output reads as a **flat horizontal band of green/magenta glow** rather than as **discrete vertical curtains with visible ray pillars**. The references show distinct columnar ribbon structure (refs `03` / `04` are unambiguous); the live render homogenizes the noise field into a smooth band. The 9-Q rubric gate question **Q3 (vertical ray fine structure)** reads NO, which is cert-blocking. **Q7 (off-axis composition + silhouette foreground)** also reads NO. Q4 / Q6 are documented partials.

**Why it's wrong.** The shader has the four load-bearing nimitz elements *individually* (triangular noise, recursive domain warp, per-march-step palette, running-average smear) but **drops one element from the recipe**: per-pixel ray construction. Every screen pixel walks the same 50-step march in noise-space, so the only thing that varies vertically across the frame is colour stratification + envelope mask. There is no per-pixel column for the noise field to project vertical pillars onto. Q3 cannot close by tuning amplitudes/phases on the current renderer (Failed Approach #49 in CLAUDE.md — *"tuning constants on a renderer structurally missing a layer"*).

**What's needed.** A structural shader rewrite at `raymarch_column` so each fragment walks its own world-space vertical column derived from a per-pixel ray. This is the layer that's missing. Estimated 1-day session, mostly inside `AuroraVeil.metal` — no engine changes, no JSON schema changes, no new GPU bindings. The other 9-Q gaps (Q7 off-axis composition, Q4 sub-second flicker, Q6 sharp bottom edge) decompose into smaller follow-ups that can land sequentially after the Q3 structural fix.

**Decision Matt needs to make.** Which of three packagings for AV.3.x:

- **AV.3.x = single comprehensive increment** (1.5-2 sessions): close Q3 + Q7 + Q4 + Q6 in one structural pass + tuning pass. Riskier (compound regression surface), but single M7 walkthrough.
- **AV.3.x = strict sequencing** (3-4 sessions): one increment per Q-gap, M7 review between each. Lowest regression risk; longest calendar time.
- **AV.3.x = Q3 first, others deferred** (1 session): close only the structural Q3 gap, then re-walk 9-Q. If Q3 closes, Q7+Q4+Q6 may become acceptable partials. Smallest scope, fastest cert decision.

Recommended: **Q3 first, others deferred.** The Q3 structural rewrite is the only cert-blocking change. Q7 and Q4 may close as side-effects (per-pixel rays produce off-axis composition naturally if FOV is wide enough; the sub-second flicker prescription only fires meaningfully once the rays exist). The smallest scope that's still load-bearing is the best M7-walkthrough cost/benefit.

---

## Part 1 — Diagnosis

### 1.1 The visual gap, in one sentence

The references show **vertical curtain ribbons with crisp ray pillars** (refs `01`, `03`, `04`). The live render produces **a horizontally-banded smooth green/magenta glow** with no readable ribbon structure and no visible rays.

### 1.2 Evidence sources used

| Source | Date | Content | Path |
|---|---|---|---|
| Live session video | 2026-05-20T01-23-03Z | 132 s, AV.2.h live (pre AV.2.h.1) | `/Users/braesidebandit/Documents/phosphene_sessions/2026-05-20T01-23-03Z/video.mp4` |
| Live session frames | 2026-05-20 (extracted today) | 4 frames at 1080×688 | `/tmp/av3_live_frames/frame_001.png` ... `004.png` |
| Test fixture | 2026-05-20T12:42:13Z | silence / mid / beat at 1920×1280 | `/tmp/phosphene_visual/20260520T124213/Aurora_Veil_*.png` |
| References | curated 2026-05-08 | `01` / `02` / `03` / `04` + `09` anti-ref | `docs/VISUAL_REFERENCES/aurora_veil/` |

Live frames and test fixture are visually indistinguishable in structural character — confirms the test fixture is representative (no test/prod parity gap per CLAUDE.md FA #66) and rules out a fix-via-fixture-only path.

### 1.3 Honest 9-Q rubric assessment

Against refs `01` / `02` / `03` / `04` per research §2.3:

| # | Question | Read | Severity |
|---|---|---|---|
| 1 | Vertical stratification only? | **YES** | — |
| 2 | Green-dominant palette? | **YES** | — |
| 3 | Vertical ray fine structure? | **NO** | **Cert-blocking** |
| 4 | Multi-timescale motion? | Untestable in single frame; substrate drift active per shader; sub-second + pulsation absent | Documented partial / deferred |
| 5 | Emissive compositing? | **YES** | — |
| 6 | Soft top, sharp bottom? | **PARTIAL** | Acceptable |
| 7 | Off-axis composition + dark foreground? | **NO** | Borderline blocking — strongly weighs against family-bar pass |
| 8 | Brightness gradient within the curtain? | **PARTIAL** | Acceptable; tied to Q3 fix |
| 9 | No theatrical beam / ground-illum? | **YES** | — |
| anti-ref | Reads like `09` festival? | **NO — clearly not** | — |

Per the AV.3 prompt's stop-and-report rule, Q3 = NO is the cert-blocking trigger. Q7 = NO is structurally tied to the same root cause (see Part 2).

---

## Part 2 — Root cause

### 2.1 What the shader actually does

`AuroraVeil.metal::raymarch_column` (lines 302–358):

```msl
for (int i = 0; i < kAuroraSteps; i++) {
    float pt = 0.8 + pow(float(i), 1.4) * 0.002;          // ← step distance
    float rzt = aurora_tri_noise_2d(
        float2(columnUVx * foldScale, pt * foldScale),    // ← noise X = uv.x + offset, noise Y = pt
        driftSpeed, time);
    // ... palette × smear × decay accumulator
}
```

The march walks `i = 0..49`, sampling the 2D triangular noise field at `(columnUVx, pt)`. The screen pixel's **`uv.y` is not in the noise sample**; only `columnUVx` (which is `uv.x + horizontal offset + kink`) carries spatial information into the noise function. Every screen-row of pixels does the same march in noise-space — only the colour stratification (the `topness = 1 - smoothstep(0.05, 0.55, uv.y)` term) and the envelope mask (`smoothstep(0.02, 0.40, uv.y) × (1 - smoothstep(0.74, 0.84, uv.y))`) vary across screen-Y.

### 2.2 What the recipe specifies

Research §1.1 step 4 (nimitz "Auroras"):

> 50-step volumetric raymarch up a vertical column. **Step distance grows polynomially:** `pt = (0.8 + pow(i, 1.4) * 0.002 - ro.y) / (rd.y * 2.0 + 0.4)`. Cheaper at the bottom of the column (dense detail near the curtain base) and coarser at the top (where the diffuse red crown lives).

The original formula has `ro` (ray origin) and `rd` (ray direction) terms. The presence of `ro` and `rd` means each pixel has its **own ray**, derived from camera + screen position. Each pixel walks an actual world-space column rooted at a different camera ray.

When you compute `pt` with `ro.y` and `rd.y` terms, the *intersection point* of the ray with the noise field varies across screen-Y. Pixels near the screen-top have rays angled upward, so their march `pt` values span a different range than pixels near the screen-bottom. Critically, the **noise sample plane** (`bpos.zx` in nimitz, here `(columnUVx, pt)`) becomes a function of screen Y *through* the ray construction.

### 2.3 What this means visually

The reference photographs show vertical pillars because the auroral electron-flux footprint `F(x, y)` (Lawlor §1.2) has structure at multiple horizontal scales. A "ray pillar" is a region where `F(x, y)` is dense over a thin vertical column in world-space — i.e., dense over an `x` band that's narrow but extends across many `y` values.

In our renderer, the noise field IS structured (triangular noise with five octaves + domain warp gives crisp edges and biological asymmetry). But because every screen pixel samples the *same* march column, we never see the vertical extent of those features — only the integration along a single noise-space path. The result is a homogenized scalar emission per pixel that's primarily a function of `uv.x` (column anchor), with `uv.y` only modulating colour and envelope.

This is **Failed Approach #49** at the layer-level: tuning constants on the current shader (amplitude, phase rate, smear α, octave count) **cannot** close Q3, because the structural element that would project the noise field into vertical screen pillars is absent.

### 2.4 Why Q7 is the same root cause

Off-axis composition (Q7) in the references comes from:
- Curtains tilted at an angle relative to the camera (refs `01`, `03`, `04`)
- Concentration of the curtain on one side of the frame, not centered (refs `01` heavy-right, `04` heavy-right)
- A silhouette foreground (forest / lake / glacier — refs `01`, `03`, `04`)

The first two emerge naturally from a real per-pixel ray system: tilt the camera, and the curtains tilt with it. The third (silhouette foreground) is a separate compositing layer the current shader doesn't have.

A renderer that's centered-horizontal-band by construction (current state) cannot produce off-axis curtains by tuning. Same root-cause classification as Q3.

---

## Part 3 — Prescriptions

### 3.1 Q3 — Per-pixel ray construction (load-bearing, cert-blocking)

**The change.** Refactor `raymarch_column` so each fragment constructs its own ray `(ro, rd)` derived from `uv` and runs the polynomial step formula in full nimitz form:

```msl
// Per-pixel camera ray. Camera at (0, eyeHeight, -1) looking +z; screen UV
// maps to ray direction with vertical FOV ~60°.
float3 ro = float3(0.0, 0.10, 0.0);
float3 rd = normalize(float3(
    (uv.x - 0.5) * 1.6,           // horizontal screen → ray.x
    (0.5 - uv.y) * 1.0,           // vertical screen → ray.y (top of frame = up)
    1.0));

for (int i = 0; i < kAuroraSteps; i++) {
    float pt = (0.8 + pow(float(i), 1.4) * 0.002 - ro.y)
             / (rd.y * 2.0 + 0.4);
    float3 bpos = ro + rd * pt;

    // Noise sampled on the xz plane (the curtain's footprint in world).
    float rzt = aurora_tri_noise_2d(
        float2(bpos.x, bpos.z) * foldScale,
        driftSpeed, time);
    // ... rest unchanged
}
```

The 3-column architecture becomes **3 horizontal anchor offsets in world-space** (e.g., `bpos.x + colOffset`), not 3 columns of `uv.x` arithmetic. The `MAX` merge across the three samples per fragment stays.

**Grounding.** nimitz Shadertoy XtGGRt (CC-BY-NC-SA; algorithm reimplemented from research §1.1 description, not copied verbatim). The exact `(0.8 + pow(i, 1.4) * 0.002 - ro.y) / (rd.y * 2.0 + 0.4)` formula is the canonical published step distance. Toni Sagristà's Gaia Sky writeup ([rendering aurorae and nebulae](https://tonisagrista.com/blog/2024/rendering-aurorae-nebulae/)) and Roy Theunissen's breakdown both confirm the per-pixel ray structure as the load-bearing element.

**Expected visual delta.** Pixels at different screen-Y positions sample the noise field at different world-space points. The horizontal noise structure (where the triangular noise has high-density columns) now projects into the screen as **vertical pillars** because following one ray vertically through screen Y means moving through different `bpos.z` values (closer/farther) while `bpos.x` shifts gradually. A high-density region of the noise at one `x` coordinate stays high-density as the ray walks through it from camera-near to camera-far, producing a screen-vertical pillar.

**Cost.** ~30–50 lines of MSL, all inside `raymarch_column`. No engine changes. Plausibly the same 50 march steps and identical noise function calls — just different `pt` formula and different noise sample input. Tier 2 budget impact negligible.

**Risks.** (a) Ray system tuning (camera position, FOV) needs to land in the right ballpark — too narrow a FOV produces a thin tall band, too wide makes the curtain look flat. Reference `01` suggests vertical FOV ~50–60°. (b) The previous bottom-edge envelope (`smoothstep(0.02, 0.40, uv.y)`) may need rework since the curtain's screen-Y range is now determined by camera tilt + ray system, not by the envelope mask. Plan to remove the envelope mask entirely and let the ray system + the `exp_decay × smoothstep` factor in the march do the bottom-fade naturally (nimitz's `col *= clamp(rd.y * 15.0 + 0.4, 0, 1)` line — research §1.1 step 8). (c) Star compositing may need to move from screen-UV-based to world-space-projected — minor effort if it becomes an issue.

**Validation.** Re-render the test fixture; expect visible vertical pillars in the green body matching refs `03` / `04` density. Re-walk 9-Q rubric; Q3 should become YES. Re-run `AuroraVeilSilenceTest` + `AuroraVeilContinuousDominanceTest` + `AuroraVeilPitchHueTest`; regenerate `PresetRegression` golden hashes (expected to drift significantly — this is a structural rewrite).

### 3.2 Q7 — Off-axis composition + silhouette foreground

**The change.** Two sub-changes that can land together or separately:

1. **Camera tilt.** With the per-pixel ray system from §3.1, rotate the ray-construction so the curtain's vertical axis is not parallel to screen-Y. Practically: tilt the camera forward by ~5–10°, biasing the curtain to the upper portion of frame and producing an off-axis read. Reference `01` is the anchor — curtain occupies the upper-right two-thirds.
2. **Silhouette foreground layer.** Add a simple foreground occluder: a low-frequency noise band (or a hand-tuned smooth profile function) at the bottom of frame that masks aurora to `(0, 0, 0)` below a noisy horizon line. References `01` (forest), `03` (forest), `04` (glacial lake horizon) all have this. The simplest implementation is a procedural-noise horizon: `silhouette = step(noise(uv.x * 5.0) * 0.18 + 0.85, uv.y)` (occlude where uv.y > the noisy horizon-y). Returns 1.0 for sky/aurora, 0.0 for foreground.

**Grounding.** Reference photographs `01`, `03`, `04`. No procedural-aurora prior-art reference for the foreground specifically — it's a standard sky-rendering technique. The Wittens NeverSeenTheSky composition uses a smooth horizon line; multiple Shadertoy aurora pieces use a noise-based silhouette.

**Cost.** ~10–20 lines for the silhouette occluder. Camera tilt is a one-line change.

**Risks.** Camera tilt may interact badly with the polynomial step distance — too aggressive a tilt produces `rd.y → 0` and a divide-by-near-zero in `pt = (0.8 + step - ro.y) / (rd.y * 2.0 + 0.4)`. Mitigation: clamp `rd.y` away from zero, or test the tilt range (5–10° should be safe). Silhouette must not occlude stars — composite the silhouette mask only on the aurora layer, not on the sky+stars.

**Validation.** Side-by-side vs ref `01` — confirms off-axis read; vs ref `04` — confirms foreground silhouette character. Q7 reads YES.

### 3.3 Q4 — Sub-second ray flicker

**The change.** Add a fast-time noise modulation on per-step density:

```msl
float rzt = aurora_tri_noise_2d(...);
// Sub-second flicker: 5–10 Hz character. Modulates only the bright
// regions (where rzt is already high) to avoid waking the band's dim
// regions into noise.
float flicker = 1.0 + 0.25 * aurora_tri(time * 7.0 + bpos.x * 0.5)
                          * smoothstep(0.15, 0.30, rzt);
rzt *= flicker;
```

**Grounding.** Research §2.1 temporal table: "0.1–0.2 s (5–10 Hz) — Ray brightness flicker within bright pillars." AGU/Wiley *EMCCD imaging of flickering aurora* (2010, [DOI 10.1029/2010ja016333](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2010ja016333)) confirms 5–10 Hz as the canonical fast-flicker timescale. No working code reference for this specific implementation — it's a physics-grounded prescription. Soft-rule grounding level 2 (physics + math) per CLAUDE.md research-first design.

**Cost.** ~5 lines.

**Risks.** Tuning amplitude (`0.25` here) is conservative — overdriving the flicker produces FM #11 festival-strobe. Localize the flicker to the bright regions (the `smoothstep` mask above) so dim areas stay quiet. Real aurora flicker is **localised to active rays**, not whole-curtain — the mask achieves that.

**Validation.** Multi-frame test harness (extend `AuroraVeilMVWarpAccumulationTest` pattern, but exercise scene-only — mv_warp is OFF for AV). Check that consecutive frames at silence show no flicker (it should be tied to bright regions which mostly emerge from audio response), and that frames with audio show localised twinkle in the bright pillars. Q4 closes from N/A to YES.

### 3.4 Q6 — Sharp bottom edge

**The change.** Replace the symmetric `smoothstep` envelope (lines 524–525) with the nimitz-style asymmetric profile:

```msl
// Original:
// float auroraEnv = smoothstep(0.02, 0.40, uv.y)
//                 * (1.0 - smoothstep(0.74, 0.84, uv.y));
//
// Replacement: sharp bottom, soft top via the natural exp_decay tail.
// (a) Bottom: hard step at the silhouette horizon.
// (b) Top: let the exp_decay accumulator's tail handle the natural fade.
float auroraEnv = (1.0 - silhouetteMask) * smoothstep(0.20, 0.05, uv.y);
```

(`silhouetteMask` from §3.2 if shipped together; otherwise use a hard `step` on a fixed `uv.y` threshold.)

**Grounding.** Research §2.1 mandates "Sharp lower altitude cutoff, soft diffuse upper boundary (asymmetric)." nimitz's final scaling `col *= clamp(rd.y * 15.0 + 0.4, 0, 1)` fades aurora *below* the horizon line — which is intrinsically asymmetric because `rd.y` near the horizon is small.

**Cost.** ~3 lines.

**Risks.** None significant. Q6 closes from PARTIAL to YES.

---

## Part 4 — Sequencing options

### Option A — AV.3.x.1 only (Recommended for cert-decision speed)

**Scope.** §3.1 Q3 per-pixel ray construction only.

**One session.** Estimated 1.5 hours: 30 min refactor, 30 min test/fixture regen + golden hash update, 30 min walkthrough doc + commit. Matt M7 review immediately after.

**M7 outcomes:**
- Q3 closes → re-walk 9-Q. If Q7 / Q4 / Q6 are now PARTIAL with documented deferrals, cert may be approvable.
- Q3 partially closes (vertical pillars visible but pixelated) → tune ray system params (FOV, camera height) in AV.3.x.1.fix.
- Q3 doesn't close → diagnose; possible regression or additional structural issues.

**Pro.** Smallest cert-blocking scope; fastest path to cert decision. Each follow-up Q-gap becomes its own scoped increment.

**Con.** If M7 closes Q3 but rejects on Q7, requires AV.3.x.2 before cert.

### Option B — AV.3.x.1 + .2 + .3 + .4 (Strict sequencing)

**Scope.** One Q-gap per increment, M7 review between each.

**Three to four sessions.** Q3 (§3.1), then Q7 (§3.2), then Q4 (§3.3), then Q6 (§3.4).

**Pro.** Lowest regression surface; M7 catches drift at each boundary.

**Con.** Longest calendar time. Each M7 walkthrough has overhead.

### Option C — AV.3.x = comprehensive single pass

**Scope.** All of §3.1–§3.4 in one increment.

**Two sessions.** First session: implement all four. Second session: M7 walkthrough, tune, regen.

**Pro.** Single M7 walkthrough; fixes interact and may compound positively.

**Con.** Compound regression surface; if M7 rejects, harder to bisect which sub-change caused it. Higher tuning load per session.

### Recommendation

**Option A.** Q3 is the only cert-blocking gap by the prompt's rule (Q1/Q3/Q5/Q8/Q9 NO triggers stop). Q7 NO is my read but borderline by the prompt's language ("Q4 / Q6 / Q7 PARTIAL are documented partials, not blockers"). After Q3 closes, Q7 + Q4 + Q6 may become acceptable partials that pass family-bar (D-096).

If Q3 closes Q7 partially as a side-effect (per-pixel rays often produce off-axis read naturally), Aurora Veil may cert at AV.3.x.1. If not, AV.3.x.2 lands the Q7 fix. Either way, the first M7 happens earlier and with smaller scope.

---

## Part 5 — Product decisions Matt needs to make

### §AV3X-scope — Which packaging?

Option A / B / C above. Default: A (Q3 first).

### §AV3X-fov — Camera FOV starting point

The per-pixel ray construction needs a vertical FOV. Reference `01` reads as ~50–60°. Choices:

- **Narrow (~40°)** — tall thin curtain, dramatic. Risk: looks claustrophobic; minimal off-axis composition.
- **Medium (~55°)** — matches refs `01`/`04`. Default recommendation.
- **Wide (~70°)** — more sky context, more off-axis read by construction. Risk: aurora occupies smaller fraction of frame; reads as small.

Default: **medium**. Can be tuned during AV.3.x.1 if M7 review prefers different.

### §AV3X-foreground — Silhouette foreground in §3.2

Two flavours:

- **Procedural noise horizon** — `step(noise(uv.x * 5) * 0.18 + 0.85, uv.y)` style. Reads as natural ridge/treeline. Cheap. Default recommendation.
- **No foreground; just sharp horizon** — drop the silhouette layer entirely; let the bottom edge be a clean dark band. Reads more abstract / less photographic. Lower risk of unwanted artifacts.

Default: **procedural noise horizon**, deferred to AV.3.x.2 if Option A is chosen.

### §AV3X-mvwarp — mv_warp re-introduction?

AV.2.2 dropped mv_warp because at the design parameters it washed out the high-frequency content. Once Q3 closes (visible ray pillars), should we reintroduce mv_warp at *more conservative* parameters (e.g., `decay = 0.85`, `0.001` UV displacement) for the sub-second-flicker dimension? Research §1.3 NeverSeenTheSky uses curl-noise advection on a velocity field; mv_warp could approximate it at fragment-shader budget.

Default: **no for AV.3.x.1**. Sub-second flicker per §3.3 doesn't require mv_warp. Defer the question until Q3 closes — then assess whether the per-pixel ray system already produces enough motion character. If not, AV.4 (post-cert polish) can address.

### §AV3X-acceptance — How strict on Q7 for cert?

Re-read the prompt's stop-and-report rule: "Q4 / Q6 / Q7 PARTIAL are documented partials, not blockers." If after Q3 closes, Q7 is PARTIAL (some off-axis read but not strong), does that pass M7?

Default: **product-judgment call at the M7 review.** Bring the rendered output to Matt with explicit Q7 status; Matt decides whether to cert with Q7-partial-deferred or block until Q7 closes.

---

## Part 6 — Risks

### R1 — Ray system tuning is empirical

There's no published exact value for ray origin, FOV, or screen-UV-to-ray-direction transform for aurora. Reference `01` reads as ~55° FOV but that's a guess. May need 2–3 visual-iteration cycles to dial in. **Mitigation:** start with the defaults in §3.1; if the rendered output doesn't read like refs `01`/`04`, surface to Matt with explicit gap before tuning constants endlessly (Authoring Discipline rule).

### R2 — Star compositing under new ray system

Stars are currently composited in screen-UV space (`hash_f01_2(uv * 800)`). Under the new ray system, this still produces screen-stable star positions — likely fine. **Mitigation:** verify in fixture; if stars feel "stuck" relative to the curtain motion, consider projecting them to world-space and sampling against the ray. Minor effort.

### R3 — Existing test fixtures may regress

The 3-channel routing tests (`AuroraVeilContinuousDominanceTest`, `AuroraVeilPitchHueTest`) measure mean-luma / hue migration across the entire image. A structural ray-rewrite changes the visual layout, which may shift the absolute values these tests assert. **Mitigation:** re-baseline the tests after Q3 lands — the assertions are about *monotonicity / ratio*, not absolute values, so re-running and updating thresholds should be straightforward.

### R4 — Golden hash regen

`PresetRegression` Aurora Veil golden hashes will drift significantly (likely > 8-bit Hamming threshold). **Mitigation:** regenerate as part of the AV.3.x.1 commit. Per CLAUDE.md, this is acceptable when the visual change is intentional and approved.

### R5 — Performance impact

Per-pixel ray construction is ~5 ALU ops at the start of the fragment + one extra `bpos = ro + rd * pt` per march step (3 multiply-adds). Negligible vs the existing 50-step march × five-octave domain warp × IQ palette eval (the inner loop is hundreds of ops). **Estimated cost:** Tier 2 stays under 2 ms (well below the design budget 1.7 ms target + the L3 gate 16.6 ms wall). **Mitigation:** if perf measurement during AV.3.x.1 shows otherwise, drop march steps from 50 → 40 (nimitz uses 50 but at lower resolution; we have headroom).

### R6 — "Tuning constants on a fixed renderer" failure mode re-emerging

If Q3 doesn't close cleanly after the structural rewrite, the temptation is to start tuning amplitudes / phase rates / smear α to compensate. **Mitigation:** apply Failed Approach #49 discipline — if the structural rewrite landed but the output still doesn't read like the references, re-diagnose what's missing structurally before tuning. The next structural layer to consider would be a separate "ray detail" pass on top of the volumetric integration (per AURORA_VEIL_RESEARCH §1.5 Magnetosphere reference — particle-attendance to FFT-band giving fine ray detail).

---

## Part 7 — Estimated cost

| Option | Implementation | Test regen + M7 prep | M7 walkthrough | Total |
|---|---|---|---|---|
| A (Q3 only) | 1.5 h | 0.5 h | 0.5 h | **~2.5 h (one session)** |
| B (sequential 4×) | 4 × 1 h | 4 × 0.5 h | 4 × 0.5 h | **~8 h (4 sessions)** |
| C (comprehensive) | 3 h | 1 h | 1 h | **~5 h (2 sessions)** |

Recommendation: Option A; if M7 cert blocks on Q7, AV.3.x.2 lands ~1.5 h later.

---

## Part 8 — Closeout / paperwork delta for AV.3 itself

AV.3 as currently scheduled (cert prep + M7 walkthrough + cert flip) is **paused, not abandoned.** The cert flip becomes the *last* step of AV.3.x.N once the Q3 structural gap is closed and Matt accepts the 9-Q assessment at M7.

`docs/ENGINEERING_PLAN.md` Phase AV entry needs:
- AV.3 ⏳ → 🚫 Blocked on AV.3.x.1 (structural Q3 fix)
- AV.3.x.1 ⏳ Planned — per-pixel ray construction (§3.1 of this dossier)
- AV.3.x.2 ⏳ Conditional on M7 outcome at AV.3.x.1 — Q7 off-axis composition + silhouette foreground (§3.2)
- AV.3.x.3 ⏳ Optional — Q4 sub-second flicker (§3.3); AV.4 polish if M7 accepts AV.3.x.1+.2
- AV.3.x.4 ⏳ Optional — Q6 sharp bottom edge (§3.4); AV.4 polish

`docs/RELEASE_NOTES_DEV.md` needs a `[dev-2026-05-20-b]` entry covering tonight's stop-and-report: 9-Q diagnosis, root cause, dossier authored, AV.3 status flipped.

`docs/QUALITY/KNOWN_ISSUES.md` — no entry needed. This is preset-design work, not a defect.

---

## Part 9 — Sources

Citations consolidated from the AV.1 dossier + new sources surfaced for AV.3.x:

### Per-pixel ray construction prior art

- **nimitz Shadertoy "Auroras" XtGGRt** (2017) — canonical recipe; `pt = (0.8 + pow(i, 1.4) * 0.002 - ro.y) / (rd.y * 2.0 + 0.4)` formula. CC-BY-NC-SA; algorithm reimplemented from research §1.1, no source copied verbatim.
- **Toni Sagristà — *Rendering volume aurorae and nebulae*** ([blog](https://tonisagrista.com/blog/2024/rendering-aurorae-nebulae/)) — confirms the per-pixel ray + polynomial step distance as load-bearing.
- **Roy Theunissen — *Aurora Borealis: A Breakdown*** ([blog](https://blog.roytheunissen.com/2022/09/17/aurora-borealis-a-breakdown/)) — alternative implementation in Unity; uses per-pixel camera ray.
- **Lawlor & Genetti — *Interactive Volume Rendering Aurora on the GPU* (WSCG 2011)** — formal H(z) × F(x, y) factorization; integration uses ray-based volume rendering.

### Sub-second flicker grounding

- **Research §2.1 temporal table** (5–10 Hz active ray flicker).
- **AGU/Wiley — *Flickering aurora EMCCD imaging*** ([DOI 10.1029/2010ja016333](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2010ja016333)) — physics validation of timescale.

### Composition + foreground

- References `01` / `03` / `04` from `docs/VISUAL_REFERENCES/aurora_veil/`.
- Wittens NeverSeenTheSky horizon-line composition (research §1.3).

---

*End of dossier. Companion prompts: `prompts/AV.3.x.1-prompt.md` to be authored once Matt picks an option from Part 4. AV.3 prompt parked until AV.3.x.N converges Q3.*
