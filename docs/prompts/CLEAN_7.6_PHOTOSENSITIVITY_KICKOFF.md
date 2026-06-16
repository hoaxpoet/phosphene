# CLEAN Phase 7 — Kickoff: photosensitivity flash-safety as an enforced, certifiable invariant (CLEAN.7.6, [GAP-9]) — pulled into June

> **This is a `[DEC]` + `[M7]` increment, not pure infra.** It touches what Matt *sees* and it opens with a product decision (below). Unlike CLEAN.5.4/5.5, do **not** run it end-to-end headless — **surface the §Decision fork to Matt first**, get the pick, then implement. The forensics/measurement half (§Work A) is non-destructive and can proceed in parallel.

## Why this is next (and why now, not "after June")
- **It is the only open *safety* gap.** Audit **G9** (`CODE_AUDIT_2026-06-13.md:181`) is **CONFIRMED, severity P1 (safety)**: flash-safety is "per-preset / manual only; `RayMarchPipeline:94` defers strict mode." A music visualizer that strobes can trigger photosensitive seizures — this is legal/ethical exposure, not a nicety.
- **Distribution made it real.** CLEAN.2.5a turned on hardened runtime + the notarization path; shipping outside the dev box is now the plan. The audit pre-flagged exactly this: "G9/CLEAN.7.6 to be re-sequenced into the June commit" (`:10`). Matt's standing call (this session): pull G9 forward.
- **It was explicitly deferred once already.** **D-054 (Increment U.9)** built the reduce-motion accessibility path and wrote: *"Deferred: Strict photosensitivity mode (flash frequency analysis + blanking)."* This increment is that deferred work.

## Current state (VERIFIED 2026-06-16 — re-check before trusting)

| Layer | State |
|---|---|
| **Consent (warn)** | `PhospheneApp/Permissions/PhotosensitivityAcknowledgementStore.swift` + `Views/Onboarding/PhotosensitivityNoticeView.swift` + IdleView gate — the user acknowledges a photosensitivity notice. **Done; do not rebuild.** This is the "we warned you" layer, **not** an enforced clamp. |
| **Reduce-motion (opt-in, input-side)** | D-054/U.9: when reduce-motion is active, `RenderPipeline.draw(in:)` scales `features.beat{Bass,Mid,Treble,Composite} *= beatAmplitudeScale` (0.5×) and gates mv_warp/SSGI. **Opt-in and input-side** (scales audio drivers, not measured output luminance) — a preset that strobes without beat features bypasses it entirely. |
| **Per-preset craft rules** | `SHADER_CRAFT.md` already forbids strobe by *convention* ("Never edge-trigger on `drums_beat` for intensity — produces club-strobe"; anti-references). **Advisory, not enforced** — a new/edited preset can violate it and still certify. |
| **Enforced output-side flash clamp** | **NONE.** This is the gap. |
| **Flash-measurement forensics (REUSE — do not reinvent)** | The FBS saga (`ENGINEERING_PLAN` 79–87, D-158 ctx `DECISIONS.md:~1850`) already built pixel-level flash census: it measured **373 flash events** via mean-frame-luminance deltas + an ablation harness. The reusable machinery is `PhospheneEngine/Sources/PresetSessionReplay/` — `VideoFrameExtractor`, `ImagingPrimitives`, `MotionBandAnalyzer`, `ReportGenerator`, `PresetSessionReplay`. **Build the measurement on this, not from scratch.** |
| **Common present site (where any runtime clamp goes)** | `RenderPipeline.draw(in:)` (`RenderPipeline.swift:631`) — **every** preset (ray-march + mv_warp) funnels through `renderFrame(...)` → `view.currentDrawable`, then the `onFrameRendered` recorder hook fires *after*. A runtime clamp belongs as a final full-screen pass on the frame **before** that hook, so the recorded video reflects the clamped output too. The existing `RayMarchPipeline` OR-gate comment (`:94`) reserves a flag slot for "photosensitivity strict mode" — but that path is SSGI/motion suppression, **not** luminance-rate limiting; the real clamp is output-side at the composite/present stage. |

## The standard (measure the right thing)
**Harding / WCAG 2.3.1** (general + red flash). A *flash* = a pair of opposing changes in **relative luminance ≥ 10 %** of max, where the darker state is **< 0.80** relative luminance; unsafe = **> 3 general flashes/s AND/OR > 3 red flashes/s**, when the flashing area exceeds ~25 % of a 10°-of-vision region (~`341×256 px` at standard viewing / a ~0.006 sr solid angle). Red flash (saturated-red transitions) is a separate channel. The metric is **temporal luminance-transition rate over a sufficiently large area** — not "is the frame bright."

## DECISION (resolve with Matt before §Work B; §Work A can start now)
How is the invariant *enforced* — and what is the user-visible trade-off? Three options, product-framed:

- **A — Runtime clamp (hard guarantee, alters output).** A final output-side pass slew-limits frame-to-frame luminance change so no >3/s large-area flash can ever leave the GPU, on *any* preset incl. future ones and arbitrary live tracks. **Strongest safety.** Cost: it changes every preset's look → re-golden + an **M7 re-review of all certified presets**, and risks softening the intended beat-luminance motion Matt deliberately tuned in FBS (regional punches were *hand-built* to be safe). Tunable to be near-transparent for already-safe content.
- **B — Certification gate (measures, never alters).** Extend the forensics harness to measure each preset's flash rate vs the Harding threshold and **fail certification** if exceeded; **zero runtime change.** Preserves every tuned look exactly; "every shipped preset was measured safe." Gap: doesn't protect a pathological live track/section not in the cert sessions, nor a preset before it's certified.
- **C — Hybrid (B + a transparent-below-threshold runtime backstop).** The gate as the always-on quality floor + a runtime limiter tuned as a high-water-mark that only engages on genuine danger. Belt + suspenders; most safety, preserves looks; most work.

**Recommendation: ship B first as this increment, then add the A backstop as a deliberate follow-up (= C over two increments).** B is non-destructive, immediately valuable (it *proves* the shipping presets are safe, or finds the ones that aren't), reuses the forensics harness, and needs no M7 re-review. A is the look-altering half — it deserves its own M7 sitting, not a rushed bundle. This also respects the M7-bandwidth ceiling that gates Phases 6/8. **Matt picks; default = B-now / A-next.**

## The work

### Work A — Flash metric on the forensics harness (needed for every option; start now)
- Add a Harding/WCAG luminance-transition analyzer to `PresetSessionReplay` (reuse `VideoFrameExtractor` + `ImagingPrimitives`): per-frame relative-luminance, opposing-transition detection (≥10 % swing, darker <0.80), flashes-per-second over a sliding 1 s window, computed over the area condition (full-frame first; regional/area-gated as a refinement). Red-flash channel can be a stated follow-up if it balloons scope — **say so, don't silently drop it** (CLEAN.0).
- Output a per-session **flashes/s peak + timeline** via `ReportGenerator`, comparable across presets. Validate the analyzer against the **known FBS evidence** (it must light up on a pre-FBS-fix FFO window — the "373 events" material — and read clean on a post-fix window); that A/B is your correctness proof, mirroring how FBS validated its census.

### Work B — Certification gate (the recommended shippable increment)
- A test that runs each **certified** preset through a representative real-stem session (the existing cert/replay fixtures) and **asserts peak flashes/s ≤ 3** (with margin). Wire it like the other cert gates (`FidelityRubricTests`/`PresetRegressionTests` neighborhood). A preset over threshold **fails cert** — loud, not a warning.
- Run it across the current certified set (Murmuration, DragonBloom, FataMorgana, Skein, FFO, …). **Expected outcome is informative either way:** all pass → the invariant is real and locked; any fail → a genuine pre-existing safety defect (file it P1, fix under this protocol). Document the measured peak per preset.

### Work C — Runtime backstop (only if Matt picks A or C; likely a follow-up increment)
- A final full-screen pass at `draw(in:)` (before the `onFrameRendered` hook) that limits the per-frame large-area luminance delta to stay under the rate threshold — a temporal slew-limiter, **transparent below the danger band** so safe presets are untouched. Gate it behind the existing OR-flag pattern (never assign `reducedMotion` directly — `RayMarchPipeline:94`).
- This **will** move goldens → regenerate + **M7 re-review every certified preset** with Matt. Treat it as its own M7 sitting.

## Rules / pitfalls
- **Measure output luminance, not audio drivers.** The existing 0.5× beat-clamp is input-side and opt-in; the certifiable invariant must be on the **rendered frame** (a preset can strobe with zero beat features).
- **Do not flatten the intended look.** Matt spent FBS S2–S6 making beat motion read musically *while* keeping global luminance steady (regional punches ≤ ⅓ field, ≤ 4-beat period, slow hue). The metric must pass that already-safe motion; a runtime clamp must be transparent for it. If the gate flags a *certified* preset, that's a finding to bring to Matt, not a number to tune away.
- **Reuse the forensics harness** (`PresetSessionReplay`) — the FBS census already solved "how do you count flashes from rendered frames." Reinventing it is FA-#73-class (don't rebuild a working reference).
- **Clamp before the recorder hook** so `SessionRecorder` video matches what's shown.
- **Fail loud** — a preset over threshold fails cert; a runtime clamp that can't initialize refuses, it doesn't silently pass (CLEAN.0).
- **`file_length`** — put the analyzer in its own `PresetSessionReplay` file; don't bloat an existing one.

## Closeout (per CLAUDE.md Increment Completion Protocol)
- `Scripts/closeout_evidence.sh` block (bootstrap worktree fixtures first). Link a green CI run.
- **Visually verifiable / M7:** Work B is measurement (report the per-preset peak flashes/s table — that *is* the visual evidence). Work C (if taken) requires Matt's M7 re-review of every certified preset + golden regen — state it explicitly and don't self-certify.
- Update `docs/ENGINEERING_PLAN.md` (CLEAN.7.6 row), `docs/diagnostics/CODE_AUDIT_2026-06-13.md` (Part B **G9** + Part C 7.6), `docs/RELEASE_NOTES_DEV.md`, `docs/SHADER_CRAFT.md` (promote the anti-strobe convention to a cited enforced invariant), and a new **D-#** for the photosensitivity-enforcement decision (record Matt's A/B/C pick + rationale). `RENDER_CAPABILITY_REGISTRY.md` — **update** (a new certification-pipeline capability: enforced flash-safety gate).
- A new `[DEC]` is being recorded → add it to `DECISIONS.md` §Index. Small commits (analyzer; cert gate; docs). **Push requires Matt's "yes, push."**

## After this
With G9 enforced, the remaining elevated gap is **G1** (mid-session output-device swap — awaits Matt's manual two-device test, not a coding increment). The before-July push then continues through **Phase 3** (P2 correctness: 3.1 init-failure surfacing, 3.2 scorer exclusion, 3.5 cache eviction, 3.7/G2 sample-rate) and **Phase 4** (perf), with Phases 6/8 remaining review-/soak-bandwidth-bound.
