# MM.6 Kickoff — Rebuild the Murmuration flock on Flock2 (orientation-based)

**Phase:** MM (Murmuration promote + redesign + certify). **Increment:** MM.6.
**Date prepared:** 2026-06-03. **Decision:** Matt chose "Rebuild on Flock2" after MM.3's M7 live
failure exposed that the force-based flock was a hand-derived (worse) version of a published model he
had provided at kickoff. **Supersedes the force-based substrate of MM.2 and the force-based audio
coupling of MM.3.** MM.4 (sky/perf) and MM.5 (cert) now apply to the Flock2 flock and follow this work.

---

## The #1 rule (read this twice): PORT Flock2 from its source. Do NOT rebuild or re-derive.

This increment exists **because** the last one rebuilt from first principles a system that already
existed as working, code-available reference — **Failed Approach #73** ("Don't build what's already
been built"), the parent of FA #70 (port the reference's loop *wholesale*, not piece-by-piece) and FA
#64 (do desk research instead of first-principles guessing). The single biggest way to fail MM.6 is
to read the *paper* and re-derive the model in your own words. **Read the actual source and port its
per-bird update loop as a coherent unit.**

The source (github.com/ramakarl/Flock2, MIT) is small:
- **`source/flock_types.h`** — the `Bird` struct + the params block (default coefficient values).
- **`source/flock_kernels.cu` / `.cuh`** — the GPU per-bird update (the heading controller + the
  aerodynamic integrator). **This is the load-bearing thing to port to MSL.**
- **`source/app_flock.cpp`** — the CPU app + simulation driver (neighbor grid, advance step).

Fetch them with `gh api repos/ramakarl/Flock2/contents/source/<file> --jq .content | base64 -d` (or
WebFetch raw.githubusercontent.com). Read all four before writing any MSL.

---

## Read first (binding — do not skip)

1. **Memory `project_flock2_reference.md`** — the model + concrete parameters, pre-extracted from the
   paper's Appendix A (k_align 0.60, k_coh 0.004, k_avoid −0.02, k_bound 0.10, B 20; 7 topological
   neighbours, 290° FOV; k_r 250 ms reaction, k_s 70% stability; v ∈ [5,18] m/s; aero constants). Use
   this as the map; confirm every value against the *source* before coding.
2. **The four Flock2 source files** above (FA #70 — port the loop, not the prose).
3. **`docs/presets/MURMURATION_DESIGN.md`** — esp. §1 (musical role), §2/§2.1 (reference + clip
   motion findings), §3 + §3.1 (musical contract + the NOT-all-at-once coordination), and **§11 / §11.1**
   (the MM.3 port decisions + the M7 failure write-up — what to carry vs. discard).
4. **`CLAUDE.md`** — **FA #73** (don't rebuild what exists), **FA #70 / #64** (how to port), **FA #4**
   (beat is accent, never primary motion — the M7 failure was this inverted), **FA #26**
   (`max(beatBass,beatMid,beatComposite)`), **FA #72** (MSL fields are snake_case), the Audio Data
   Hierarchy, "test in the production-grade pipeline", and "diagnostic infrastructure precedes
   fidelity claims".
5. **Memory `project_deviation_primitive_real_range.md`** — the MM.3 M7 root cause: deviation
   primitives spike to **~3×** on real music (not ~1×). Any audio modulation MUST soft-saturate the
   driver and be sized against the real range, and MUST carry the cohesion-under-3×-load test forward.
6. **Memory `project_murmuration_uplift.md`** — full project history incl. both M7 rounds.

---

## What exists now (MM.2 + MM.3, on local `main`) — and what MM.6 keeps vs. replaces

**Replace (the force-based core):**
- `MurmurationFlock.metal` `murmuration_boids` kernel — force-summed sep/align/cohesion + global roost
  attractor + `roostFar` leash + the injected curl "turning wave" + `pad0` darkening + edge flutter.
  **All of this is superseded** by Flock2's orientation-target model.
- `MurmurationFlockGeometry.computeAudio(...)` — the force-magnitude audio drives. **Re-expressed** as
  gentle biases on the turn-desire targets (see "Audio coupling" below).
- The 48-byte `MurmurationBird` layout (`position/seed/velocity/bank/speedRnd/neighborCount/pad0/pad1`)
  — **changes** to carry orientation (quaternion) + speed. Bird-layout change is fine (the preset's
  golden-hash regression renders only the **sky** fragment, not the flock — confirm, don't assume).

**Keep (the scaffolding that works):**
- The conformer shape (`ParticleGeometry` sibling, D-097), the reset→bin→integrate encoder structure,
  the render pass wiring (`RenderPipeline+FeedbackDraw.drawParticleMode`), the dusk-sky fragment, the
  `activeParticleFraction` governor hook, and the **multi-frame production-path test harness** pattern
  (`MurmurationFlockTests` + `MurmurationFlockAudioTests`) — extend these, don't reinvent.
- The point-sprite render with the **core-dark / edge-feathered density gradient** (neighbour-count
  driven) and the silhouette/blend setup (dst-alpha pinned to 1 — the white-halo fix). The orientation
  wave's darkening now comes from Flock2's *emergent* banking, not an injected `pad0` band.

---

## Porting decisions to make (flag these to Matt if any is non-obvious)

1. **Bird state = orientation + speed, not a velocity vector.** Flock2 carries a quaternion `Qᵢ` and a
   scalar speed; velocity = forward(Qᵢ)·speed. Port the struct from `flock_types.h`. Keep
   `neighborCount` (drives the density-gradient render + the L4 edge route + Flock2's boundary term).
2. **Neighbour query = ~7 topological within a 290° FOV**, not the current metric 3×3×3 count. The
   uniform grid stays; the selection changes (gather candidates from the cell neighbourhood, keep the
   ~7 nearest that fall within the forward FOV). Read how `app_flock.cpp` / the kernel does it.
3. **Unit/scale mapping is load-bearing.** Flock2 is in **metres** (v 5–18 m/s, m 0.08 kg, areas in
   m²). Phosphene's world is **±2 clip-ish units** with a fixed wide camera. Do NOT paste 5–18 m/s into
   a ±2 world. Pick a world→metre scale (or non-dimensionalise the model) so the flock fills the frame
   at a believable apparent speed; keep the *ratios* (k_* coefficients, v_min:v_max, k_r timing) intact.
4. **Drop the roost attractor + `roostFar` leash; cohesion now comes from Flock2's peripheral-boundary
   turn** (edge birds, low `nᵢ`, turn toward the centroid, strength `(B−nᵢ)/B`). BUT Phosphene needs
   the mass **framed** (static wide camera, design §9). The boundary term keeps the flock *cohesive*;
   decide whether a gentle world-bounds containment is still needed to keep the centroid on-screen, and
   if so make it a soft turn-toward-centre (orientation), never a position force.
5. **Aerodynamic model: port faithfully or simplify?** The heading controller (orientation targets →
   `k_r` reaction → `k_s` stability) is the part that produces the realistic motion + emergent waves —
   **port it faithfully.** The full lift/drag/thrust aero (constants in §A) may be more than the look
   needs; a simplified speed model (climb slows / dive speeds + clamp) may suffice. Try the faithful
   port first (FA #70); simplify only if a specific term has no visible effect, and say so.
6. **Orientation waves EMERGE — do not inject them.** The travelling dark bands come for free from the
   alignment+avoidance coupling. Deleting the MM.3 curl-wave hack is the point. Verify they appear
   before adding any audio.

---

## Audio coupling — re-express the MM.3 brain as gentle biases on the TURN-DESIRES (not forces)

The MM.3 musical contract (design §3) is unchanged; only the *mechanism* changes — and that change is
exactly why it'll stop tearing the flock (orientation nudges can't fling birds the way added forces
did). One primitive per layer, one timescale (FA #67); all deviation primitives **soft-saturated** and
sized against the real ~3× range; D-019 warmup blend + FA #26 cross-genre beat kept; **default
under-react** (§3.1 master energy/arousal gate).

- **L1 bass → macro drift + elongation.** Bias a slow global heading/centroid target the flock wheels
  toward (drift), and bias cohesion anisotropically along the travel axis (comma/ribbon). A *target*
  shift, not a roost force. Bound it so the flock stays framed.
- **L2 drums → intensify/trigger the orientation wave.** The waves already emerge; on the beat,
  briefly perturb the coupling (e.g. raise avoidance sensitivity / inject a small synchronised yaw
  bias on a flock-axis sweep) so a darker band rolls on the beat. A turn-desire bias, gentle, gated by
  energy/arousal. **Never a translating force** (FA #4 — the M7 failure).
- **L4 mid → edge shimmer.** Extra turn jitter on the peripheral birds Flock2's boundary term already
  identifies (low `nᵢ`). Fast, per-frame (not a held step — the MM.3 flutter bug).
- **L5 vocals → breathing.** Modulate cohesion strength `k_coh` (and/or the boundary pull) ± so the
  mass tightens and releases. Phrase timescale.
- **L3 flash-expansion → still DEFERRED** (design §9). Build L1/L2/L4/L5 on the new substrate first.

---

## Verification / done-when

1. **Port fidelity** — the silence/no-audio flock reproduces Flock2's qualitative behaviour (cohesive
   morphing mass, emergent travelling orientation bands, feathered edge) read against the references +
   the §2.1 clip findings. State which Flock2 source functions were ported and any simplifications.
2. **Production-path tests (mandatory).** Extend the multi-frame harness: silence baseline (cohesive,
   framed, flying, density-graded); **carry forward the cohesion-under-3×-magnitude-audio invariant**
   (`test_loudAudioStaysCohesive`) — it is the test that caught the MM.3 failure and MUST stay green;
   per-route turn-desire firing via the real dispatch path; orientation waves emerge at silence.
3. **No absolute-threshold reads** (D-026); drivers soft-saturated (real ~3× range); continuous ≥ 2×
   beat (Audio Data Hierarchy).
4. **Per-route firing evidence from a REAL recorded session** (the MM.3 pending item — now actionable:
   ask Matt to record one, run `PresetSessionReplay --preset murmuration`, update the route specs in
   `MurmurationRoutes.swift` to the new turn-desire gates). Evidence, not assertion.
5. **Full engine suite green, swiftlint --strict 0, app builds.** Confirm the sky golden hashes are
   unchanged by flock work (regression renders only the sky); regenerate only if you touch the sky.
6. **Matt M7 live review on real music** — the load-bearing gate (MM.5). Show it reads as a
   murmuration AND stays calm in calm passages. Do NOT assert the live look from tests — it cannot be
   verified headlessly (the session `video.mp4` is a 10 s rolling clip of whatever preset was active,
   NOT preset-specific; anchor on Matt's screenshots + the session CSV).
7. **Closeout report** per CLAUDE.md; state which dispatch path the tests exercised and which Flock2
   functions were ported.

---

## Discipline reminders (CLAUDE.md)

- **Port, don't rebuild** (FA #73) and **port the loop wholesale** (FA #70). If you find yourself
  re-deriving the turn model from the paper instead of the source, stop and read the source.
- **Real-range drivers** — soft-saturate; size against ~3×; keep the cohesion-under-load test
  (`project_deviation_primitive_real_range`).
- **Beat is accent, never primary motion** (FA #4) — the audio is turn-desire *bias*, gentle and gated.
- **Verify against the artifact** before asserting; the rolling `video.mp4` is not preset-specific.
- **Surface risk early** — if 2 tuning rounds don't converge, stop and write "what I now believe";
  if it doesn't change between rounds, re-scope and ask.
- **Commit small to local `main`** (`[MM.6] <component>: <desc>`). **Do not push** without Matt's "yes,
  push".

---

## Git state at handoff

Local `main`, not pushed. MM.3 commits: port `072b2b8c`, tests `205ac595`, replay `4ff18f8b`, lint
`11767968`, docs `f41dc632`, M7 fix `564f4eec`, M7-fix docs `8d3c8ce4`, FA #73 `4969fa6f`. The MM.3
force-based flock remains in the tree as the (now superseded) starting point; MM.6 replaces its
integrator + audio coupling. Tree clean.
