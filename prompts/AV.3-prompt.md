# AV.3 — Aurora Veil cert prep + Matt M7 review

**Increment ID:** AV.3
**Status:** ⏳ Planned (after AV.2.h.1 lands 2026-05-20)
**Authoritative design:** `docs/presets/AURORA_VEIL_DESIGN.md` — note that §5.7's 7-route table has been **superseded** by the AV.2.h curation (3 routes: vocals → hue, bass → brightness pulse, drums → kink). The design doc was the input to the AV.2 prompt; the actual shipped preset is the curated 3-channel version. Treat the references + the 9-question rubric as the authoritative cert gate, not the route table.
**Research dossier:** `docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` — §2.1 (visual signature), §2.2 (15 failure modes), §2.3 (9-question authenticity rubric — load-bearing M7 gate)
**Reference set:** `docs/VISUAL_REFERENCES/aurora_veil/` — `01` / `02` / `03` / `04` mandatory; `09` anti-reference must NOT be matched
**Recent history:** Read `docs/RELEASE_NOTES_DEV.md` entries `[dev-2026-05-18-c]` through `[dev-2026-05-20-a]` to understand the AV.1 → AV.2 → AV.2.1 → AV.2.2 → AV.2.2a → 2.2b → 2.2c → 2.2d → 2.2e → 2.2f → 2.2g → PT.1 → AV.2.h → AV.2.h.1 cascade. The closer you read the cascade, the less likely you are to repeat its mistakes.

---

## The product change in one paragraph

Aurora Veil is functionally complete and visually validated. AV.2.h.1 was the last tuning pass — the three-channel curated design (vocals melody → ribbon hue, bass transients → brightness pulse, drum events → curtain kink) reads coherent and music-coupled in live testing. AV.3's job is to **close out the preset**: run the performance profile against Tier 1 (4.0 ms) / Tier 2 (1.7 ms) budgets, document the 9-question authenticity rubric assessment with explicit YES / NO / PARTIAL per question, run a fresh `RENDER_VISUAL=1` contact sheet, walk it past Matt for **M7 sign-off**, and on Matt's "yes" flip `AuroraVeil.json` `certified: true`. **No new features.** If anything visual feels wrong in the M7 review, the fix is a tuning pass within the existing 3 routes — not new routes. Sub-second flicker (5–10 Hz) and 2–20 s pulsation from the original design §5.4 multi-timescale-motion table are **deferred to AV.3.x or later** because the curated AV.2.h state reads correctly without them and adding them risks re-introducing the "muddled" complaint that AV.2.h just resolved.

This is the **first non-Arachne / non-Lumen-Mosaic preset to reach M7-cert candidacy** since the program started. The Aurora Veil cert flip closes Phosphene's path to its first "2 of 20" certified count.

---

## Read these first

In this order. The AV.2.h.1 closeout (`docs/RELEASE_NOTES_DEV.md` entry `[dev-2026-05-20-a]`) is the freshest empirical state — read it first.

1. **`docs/RELEASE_NOTES_DEV.md` entries from `[dev-2026-05-19-g]` (AV.2.h) onward.** The Three-Channel curation rationale, route-firing-rate data per live session, and the discipline rules captured along the way (CLAUDE.md production-pipeline-testing + research-first-design). Skim everything before `[dev-2026-05-19-g]` for context; the post-AV.2.h history is load-bearing.
2. **`docs/presets/AURORA_VEIL_RESEARCH_2026-05-18.md` §2.3 — the 9-question authenticity rubric.** This is the M7 gate. Print it out, hold it next to each rendered frame.
3. **`docs/VISUAL_REFERENCES/aurora_veil/AURORA_VEIL_README.md` — the per-image annotations + mandatory-traits checklist + anti-reference call-out.** Per CLAUDE.md Failed Approach #63: **do not author a session without reading the README annotations**. Mid-session sanity check is side-by-side comparison against named reference images, not self-judgment of "looks reasonable."
4. **`PhospheneEngine/Sources/Presets/Shaders/AuroraVeil.metal` — the shipped AV.2.h shader.** Read header docstring + the curation rationale; understand what's wired before judging what to tune.
5. **`PhospheneEngine/Sources/Presets/AuroraVeil/AuroraVeilState.swift` — the CPU-side kink accumulator + pitch ring buffer.** Constants `kinkChargeLo/Hi = 0.7/1.0` are AV.2.h.1.
6. **`PhospheneEngine/Tests/PhospheneEngineTests/Presets/AuroraVeilMVWarpAccumulationTest.swift` — the production-pipeline diagnostic.** Env-gated; if you want to verify mv_warp stays off and the direct render path is being exercised, run with `AURORA_VEIL_MVWARP_DIAG=1`.
7. **`CLAUDE.md`** — Authoring Discipline section, in particular: "Test in the production-grade rendering pipeline. No shortcuts." + "Design is upstream of testing — surface risks immediately." Both rules were promoted during the AV.2.x cascade because of the bugs that hid behind test/prod gaps. **If you find yourself authoring a change without exercising the live dispatch path, stop.**
8. **`docs/SHADER_CRAFT.md` §12 — fidelity rubric.** Aurora Veil's profile is `lightweight` (D-067(b)) — only L1/L2/L3/L4 apply. M1–M3 + E + P sections do not.

You do NOT need to read: the entire AV.1 / AV.2 / AV.2.1 / AV.2.2 / AV.2.2a–g code diffs (the cascade history is in release notes); the full Phase MV history; the AV_DESIGN doc's §5.4 (multi-timescale motion table) unless you're considering re-introducing sub-second flicker / pulsation — which is explicitly out of scope.

---

## What the codebase already does (don't re-implement)

- **The shader is shipped and working.** Three routes wired and validated in live sessions. Do not modify shader logic unless the M7 review surfaces a specific visual issue that maps to a specific shader constant.
- **`AuroraVeilState`** is shipped and working. CPU-side kink accumulator + 5-frame pitch ring. Gate at 0.7/1.0. Pitch smoothing at confidence ≥ 0.5.
- **`AuroraVeilContinuousDominanceTest`** + **`AuroraVeilPitchHueTest`** + **`AuroraVeilSilenceTest`** + **`AuroraVeilMVWarpAccumulationTest`** all green. Do not modify unless adding new tests.
- **PT.1 (PitchTracker ring buffer)** is shipped. Route 1 fires 84 % of frames on Billie Jean live. Do not re-touch PitchTracker.
- **`PresetRegression` golden hashes** for Aurora Veil are current as of AV.2.2c. Re-run hash regen ONLY if you change shader output.
- **`AuroraVeil.json`** `certified: false`. **This file flips at the end of AV.3 on Matt's M7 green.** Until then, no changes.

---

## What this increment does

### 1. Live re-verify of AV.2.h.1

Matt runs one session with Aurora Veil on a varied playlist (Billie Jean light-drum + Outkast/Foo heavy-drum + something vocal-forward + ambient/instrumental for variety). Confirm:
- Routes 1 + 2 + 5 all fire visibly per the AV.2.h.1 predictions (vocals ~80 %, bass pulse ~10 %, kink 1-3 % depending on drum density)
- No regressions from AV.2.h's curation (no "muddled" reading, no per-frame restlessness)
- No new bugs

If anything reads wrong, **do not start AV.3 cert prep.** File an AV.2.h.x tune fix first, ship, re-verify.

### 2. Performance profile (was deferred during the AV.2.x cascade)

Per `AURORA_VEIL_DESIGN.md §7`: Tier 1 budget 4.0 ms, Tier 2 budget 1.7 ms. Run `PresetPerformanceTests` (if it exists; if not, this is a quick diagnostic) to measure Aurora Veil's actual GPU cost. Document in the closeout report. **If over budget**, surface the gap and we discuss fallback options (drop march steps 50 → 40; drop background-column octave count 5 → 4; drop to 2-column merge). Do NOT preemptively optimize — measure first.

### 3. 9-question authenticity rubric (research dossier §2.3) — the M7 gate

Run `RENDER_VISUAL=1 swift test --filter "PresetVisualReview"` to produce fresh `Aurora_Veil_{silence,mid,beat}.png` at 1920×1280 (or current visual review resolution).

Walk each of the 9 questions and answer **YES / NO / PARTIAL** with one-line justification, comparing the rendered frames against `01_macro_curtain_hero_purple_green.jpg` / `02_palette_green_to_magenta_stratification.jpg` / `03_meso_curtain_fold_drape.jpg` / `04_atmosphere_multi_curtain_parallax.jpg`:

1. Vertical stratification only?
2. Green-dominant palette?
3. Vertical ray fine structure?
4. Multi-timescale motion? *(expected PARTIAL: AV.2.h's curated state has substrate drift + audio-coupled events but no sub-second flicker or 2–20 s pulsation — those are deferred. Document the PARTIAL clearly with rationale.)*
5. Emissive compositing?
6. Soft top / sharp bottom?
7. Off-axis composition with dark foreground context?
8. Brightness gradient within the curtain?
9. No theatrical beam / ground-illumination cues?

For each NO, identify the specific failure mode (1–15 in research §2.2) and decide: is it a tuning fix worth attempting in this increment, or is it a deferred-for-AV.3.x issue? Q4 partial is acceptable for cert if Matt accepts the multi-timescale gap as "AV.3 polish" deferred.

Anti-reference check: does the rendered output NOT read like `09_anti_neon_festival_aurora.jpg`?

### 4. Matt M7 review

Walk Matt through the contact sheet, the 9-Q rubric assessment, and the performance profile. Surface known partial rubric answers + acknowledge limitations (especially Q4). Get explicit "yes, certify it" or "no, here's what's wrong."

### 5. Cert flip (on Matt's "yes")

Single change: `AuroraVeil.json` `certified: false → true`. Update `docs/ENGINEERING_PLAN.md` Phase AV status to ✅ certified. Add a `RELEASE_NOTES_DEV.md` entry documenting the M7 sign-off + rubric assessment + performance numbers. Aurora Veil joins Lumen Mosaic as the 2nd certified Phosphene-native preset.

### 6. If M7 returns negative

Same discipline as the AV.2.x cascade: surface the specific problem at the product level, articulate the failure mode, propose ONE targeted fix, get sign-off, ship, re-verify. Do NOT speculatively re-tune multiple variables. Do NOT silently expand scope to include sub-second flicker / pulsation. If Matt's negative review points specifically at a multi-timescale gap (Q4), then sub-second flicker / pulsation become AV.3.x scope and a separate prompt — not part of AV.3.

---

## Done when

- [ ] AV.2.h.1 live re-verified on a multi-track playlist; no regressions; no new bugs surfaced
- [ ] Performance profile run; Aurora Veil cost documented against Tier 1 / Tier 2 budgets
- [ ] 9-Q authenticity rubric assessment written out with YES / NO / PARTIAL per question + side-by-side comparison to named references (`01` / `02` / `03` / `04`)
- [ ] Anti-reference check: rendered output does NOT read like `09`
- [ ] Matt M7 sign-off captured explicitly in chat / closeout
- [ ] `AuroraVeil.json` `certified: false → true` (only on Matt's "yes")
- [ ] `docs/ENGINEERING_PLAN.md` Phase AV / Increment AV.3 flipped ⏳ → ✅
- [ ] `docs/RELEASE_NOTES_DEV.md` entry added (`[dev-YYYY-MM-DD-X]`) documenting sign-off + rubric + perf numbers
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` clean
- [ ] `swift test --package-path PhospheneEngine --filter "AuroraVeil|PitchTracker|PresetRegression|PresetAcceptance|FidelityRubric"` — all green
- [ ] `swiftlint lint --strict --config .swiftlint.yml` — 0 violations on touched files
- [ ] **Closeout report** per CLAUDE.md Increment Completion Protocol — explicit Q1–Q9 status, perf numbers, M7 sign-off quote, files changed, git status clean

---

## Verify

```
swift test --package-path PhospheneEngine --filter "AuroraVeil|PitchTracker|PresetRegression|PresetAcceptance|FidelityRubric"

RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "PresetVisualReview" 2>&1 | grep "Aurora Veil"
# Open /tmp/phosphene_visual/<ISO8601>/Aurora_Veil_{silence,mid,beat}.png

xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build

swiftlint lint --strict --config .swiftlint.yml
```

---

## Out of scope (do NOT touch in AV.3)

- **Sub-second ray flicker (5–10 Hz).** Research §2.1, design §5.4. Deferred — adding it now risks re-introducing the "muddled" reading AV.2.h just resolved. If Matt's M7 explicitly flags Q4 multi-timescale as the cert blocker, sub-second flicker becomes AV.3.x with its own prompt.
- **2–20 s whole-curtain pulsation envelope.** Same deferral logic. Design §5.4 row.
- **New audio routes.** Any "what if X also drove Y" suggestion = AV.3.x or later. The curated 3-channel state is the product surface.
- **Re-architecting the noise function / palette / Lawlor stratification.** The shader is shipped and validated. Do not edit shader logic for "cleaner code" reasons.
- **P2 stem-warmup window engine fix.** Filed as an engine-level concern affecting all presets; not Aurora Veil's responsibility. Separate increment.
- **`SpectralHistoryBuffer[1920..]` vocal-pitch trail at slot 5.** Design §5.7 amendment-era idea; not needed because PT.1 unblocked direct stem-pitch consumption.
- **Modifying any other preset's golden hashes / acceptance behaviour.** AV.3 touches Aurora Veil files + ENGINEERING_PLAN + RELEASE_NOTES only.

---

## Open questions to surface (don't decide alone)

### §AV3-q4 — Q4 multi-timescale-motion partial status

The 9-Q rubric Q4 expects substrate drift + sub-second flicker + 2–20 s pulsation + minutes-scale substorm advance. AV.2.h's curated state has substrate drift only. **This is a known partial.** Surface to Matt explicitly: "Q4 is partial. Cert with partial, or cert-blocked?" Default position: cert with partial documented; defer sub-second + pulsation to AV.3.x if Matt wants them.

### §AV3-perf — Performance profile expectations

If the profile shows Aurora Veil over Tier 2 (1.7 ms), surface the gap and recommend a fallback. Do not preemptively optimize. The 3-column max-merge raymarch was the design target; if it's over budget after AV.2.h's simplifications (5 routes removed, kink fragment-space-only) we have headroom to reduce march steps or background-column octaves.

### §AV3-cert — `certified: true` flip prerequisites

CLAUDE.md and SHADER_CRAFT.md make Matt's M7 sign-off the only path to flipping `certified: true`. The flip is the last commit of the increment, after every other gate has cleared. Do not flip on automated-gate green alone — automated gates (L1 / L2 / L3) prove the structure is sound; L4 frame match is Matt's call.

### §AV3-followups — AV.3.x scope

After AV.3 ships ✅, the following are candidates for AV.3.x or AV.4 if Matt prioritizes them:
- Sub-second ray flicker (Q4 closure)
- 2–20 s whole-curtain pulsation (Q4 closure)
- Off-axis composition / depth-dim refinement (Q7 closure if PARTIAL)
- Soft top / sharp bottom envelope refinement (Q6 closure if PARTIAL)
- P2 stem-warmup window engine fix
- Vocals-pitch trail in `SpectralHistoryBuffer[1920..]` (if a future preset needs it)

Do NOT scope any of these into AV.3.

---

## Stop and report instead of forging ahead when

- AV.2.h.1 live re-verify shows a regression vs the 2026-05-20T01-23-03Z session
- Performance profile is significantly over budget (> 2× Tier 2)
- Any of Q1 / Q2 / Q3 / Q5 / Q8 / Q9 returns NO (the cert-blocking questions; Q4 / Q6 / Q7 PARTIAL are documented partials, not blockers)
- Matt's M7 review returns negative feedback whose root cause you cannot articulate
- You catch yourself proposing sub-second flicker / pulsation / new routes as "small additions"
- Anti-reference (`09`) similarity is non-trivial in any rendered frame

Per the cascade lesson: the cost of pausing is small. The cost of speculative tuning passes is high — AV.2.x ran twelve increments because each one tried to fix the previous one's overshoot.

---

## Commit cadence

Per CLAUDE.md, multiple small commits with `[AV.3] <component>: <description>`. Suggested boundaries:

1. `[AV.3] Live re-verify: 2026-MM-DDTHH-MM-SSZ — confirmation` (sessions notes; may not be a code commit)
2. `[AV.3] Performance profile + 9-Q rubric assessment` (docs only)
3. `[AV.3] Tune fix if M7 returns negative` (only if needed, only after Matt sign-off on the fix)
4. `[AV.3] AuroraVeil.json: certified true` (the cert flip — last code commit)
5. `[AV.3] ENGINEERING_PLAN + RELEASE_NOTES: Aurora Veil ✅ certified`

Push only after Matt's explicit "yes, push." Local main commits stay local until then.

---

## Closeout report (at end of increment)

Per CLAUDE.md Increment Completion Protocol:

1. **Files changed** — concrete paths.
2. **Tests run** — suites + pass/fail counts.
3. **Visual harness output** — paths to the three `Aurora_Veil_*.png` files + side-by-side comparison against named references.
4. **9-Q authenticity rubric** — Q1–Q9 each marked YES / NO / PARTIAL with one-line rationale.
5. **Performance profile** — Tier 1 / Tier 2 cost vs budget.
6. **Matt M7 sign-off quote** — explicit "yes" or revision request.
7. **Documentation updates** — `ENGINEERING_PLAN.md` flip + `RELEASE_NOTES_DEV.md` entry + `AuroraVeil.json` cert flag.
8. **Capability registry** — if any renderer / shader capability changed (probably not for cert work).
9. **Git status** — branch, commit hashes, clean tree.
10. **Known follow-ups** — AV.3.x scope captured in the engineering plan.

---

## Why this matters

Aurora Veil is the **second non-Arachne / non-Lumen-Mosaic Phosphene preset** to reach M7 candidacy. Its certification:

1. Moves the certified count from 1 (Lumen Mosaic) to 2 → ~10 % progress to the 20-cert first-release bundle (D-114).
2. Validates that the AV.2.x cascade's lessons — production-pipeline testing, research-first design, route curation discipline — actually produced a cert-ready preset. If we can ship cert on AV after the cascade, the discipline rules are vindicated. If cert is blocked, the discipline rules need re-examination.
3. Establishes the **Three-Channel route-curation pattern** as a reusable template for future presets. Any preset author working on a new audio-coupled preset should be able to look at AV.2.h's "vocals → hue / bass → brightness pulse / drums → rare kink" pattern and ask "does my preset need more than three coupled axes? if yes, why?"

**Estimated effort:** one session, ~2 hours including the live verify + 9-Q walkthrough + perf profile + Matt M7. If M7 returns a request for a tune fix, +1 session per tune-and-re-verify cycle.

Treat the 9-Q rubric pass + Matt M7 sign-off as the load-bearing gate. The other steps are easy. The M7 is where Aurora Veil either becomes the second certified Phosphene preset or returns to the AV.3.x backlog.
