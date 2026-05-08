# Drift Motes — Session 0 (DM.0) Claude Code Prompt

You are implementing **Phase DM, Increment DM.0** for Phosphene: a prerequisite refactor that introduces a `ParticleGeometry` protocol so each particle preset can own its own compute+render pipeline. This unblocks DM.1, which was paused at an architectural blocker.

**DM.0 is a pure refactor.** No new visual features. No new presets. Murmuration's behavior must be **bit-identical** post-refactor — verified via `PresetRegressionTests` dHash gate. If Murmuration's regression dHash changes, the refactor is wrong; revert and re-approach.

---

## Context — what you're building and why

Phosphene's catalog has Murmuration as its only particles-family preset. Murmuration's compute+render pipeline lives in `ProceduralGeometry` (Swift) + `Particles.metal` (MSL). The render pipeline's `["particles"]` pass currently dispatches `ProceduralGeometry` directly, with hardcoded kernel names (`particle_update`, `particle_vertex`, `particle_fragment`) and Murmuration-tuned config (5000 particles, decay rate 0, drag 0.8).

A second particles-family preset, **Drift Motes**, was scoped in DM.1 with its own design and architecture contract. DM.1's foundation pass attempted to plug into the existing "particles" infrastructure and discovered it isn't infrastructure at all — it's Murmuration's single-tenant implementation. DM.1 stopped cleanly without writing code. The blocker report identified the relevant files and line numbers; this prompt builds on that report rather than re-discovering it.

**Design call:** Murmuration and Drift Motes are different enough that parameterizing one pipeline to host both would bloat the configuration interface with a union of disjoint concepts (Murmuration's homePos generation, decay-rate-0 persistence, drum-driven turning waves; Drift Motes' recycle bounds, emission position derivation, per-emission hue baking). Cleaner factoring is **siblings, not subclasses** — each preset owns its own compute+render contract; the engine schedules through a `ParticleGeometry` protocol; presets conform individually.

**DM.0's job:** introduce that protocol, make `ProceduralGeometry` conform without behavior change, route the render pipeline through the protocol. **Murmuration is the only conformer at end of DM.0.** DM.1 ships Drift Motes' own conformer.

---

## Read first — canonical truth (read in this order)

1. **The DM.1 blocker report (this conversation, the message preceding this prompt).** The session that ran DM.1 already mapped the relevant files with line numbers. Don't re-discover; build on that report.
2. **`PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift`** — the file being made to conform. Read the full API surface: constructor signature, public methods, how it owns the particle buffer, what state it carries across frames.
3. **`PhospheneEngine/Sources/VisualizerEngine.swift`** (or wherever `makeParticleGeometry` lives — confirm via grep) — the construction site that selects which geometry to instantiate.
4. **`PhospheneEngine/Sources/Renderer/RenderPipeline+FeedbackDraw.swift`** at the lines DM.1 identified (~91–101) — the dispatch site that currently calls `particles.render(...)`.
5. **`PhospheneEngine/Sources/Presets/Shaders/Particles.metal`** — read for context only. **NO modifications in DM.0.**
6. **`CLAUDE.md`** — buffer binding contract (fragment buffer 0..7), Particle struct definition, preset metadata format.
7. **`docs/presets/DRIFT_MOTES_DESIGN.md` §4** + **`docs/presets/Drift_Motes_Rendering_Architecture_Contract.md`** — read so you understand what DM.1 will need from the protocol. The protocol must be **sufficient** to express both Murmuration's existing flow and Drift Motes' eventual flow, but it must **not** include features Drift Motes specifically needs (those are DM.1's work).
8. **An existing engine protocol** — find one via grep (e.g. `protocol .*Stage`, `protocol .*Pipeline`, `protocol .*Renderer`) and match the codebase's naming and definition conventions. Don't invent a new style.

If any of these files are missing or contradict each other, **stop and ask**.

---

## Out-of-scope for this session — DO NOT IMPLEMENT

DM.0 is a refactor. It introduces a protocol and routes existing functionality through it. Do **not** do the following:

- ❌ Create `DriftMotes.metal`, `DriftMotes.json`, or any Drift Motes file. That's DM.1.
- ❌ Modify `Particles.metal` (Murmuration's MSL). The kernels stay byte-identical.
- ❌ Modify the `Particle` struct's memory layout (Swift or MSL). 64 bytes, `packed_float4 color`, exactly as it is today.
- ❌ Change Murmuration's tuning constants (5000 particles, decay rate 0, drag 0.8). They remain hardcoded inside `ProceduralGeometry` (or wherever they live today). The protocol does not parameterize them.
- ❌ Add new entries to the "particles" pass dispatch beyond Murmuration's current path. Murmuration is the only conformer at end of DM.0.
- ❌ Pre-design for hypothetical future particle presets. Don't add `ParticleConfig` structs, `ParticleParameters` enums, or any extension points that exist solely "in case we need them." The protocol surface is what Murmuration uses today and what Drift Motes will need (per its design + contract). Nothing else.
- ❌ Refactor unrelated engine code. If you find yourself opening files outside the particle path, stop.
- ❌ Change fragment buffer bindings. The contract in CLAUDE.md is preserved.
- ❌ Add JSON sidecar fields. The protocol is a Swift-side concern; preset JSON is unaffected in DM.0.

If you reach for any of these, **stop**. That's a different increment.

---

## Reference infrastructure to study (read, don't modify)

- **`PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift`** — the API you're conforming to a protocol. Identify which methods are called from the render pipeline (those become protocol requirements) and which are private helpers (those stay private).
- **`PhospheneEngine/Tests/PhospheneEngineTests/PresetRegressionTests.swift`** — the dHash regression suite. Find the Murmuration entry; confirm you understand how to run it and how it reports drift.
- **`PhospheneEngine/Sources/Renderer/RenderPipeline.swift`** + extensions — the render pipeline as a whole. Skim to confirm there's only one dispatch site for the "particles" pass, not multiple.
- **`PhospheneEngine/Sources/VisualizerEngine.swift`** — preset lifecycle. Understand `applyPreset()` and `trackChanged()` so you know where the geometry's lifecycle hooks belong.
- **An existing protocol in the engine** — grep `^protocol ` under `PhospheneEngine/Sources/`. Pick one, study its definition, conformance pattern, and naming. Match it.

---

## Files to create / modify

**Create:**

1. `PhospheneEngine/Sources/Renderer/Geometry/ParticleGeometry.swift` (or whatever file path matches the codebase convention for protocol files — could be a co-located file with `ProceduralGeometry.swift`, or a separate `Protocols/` subdirectory if one exists).

**Modify:**

2. `PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift` — declare conformance to `ParticleGeometry`. Should be a near-zero-change diff: add `: ParticleGeometry` after the class declaration, possibly add `// MARK: - ParticleGeometry conformance` and group the methods that satisfy the protocol. If method signatures already match the protocol, no body changes are needed.

3. `PhospheneEngine/Sources/VisualizerEngine.swift` (or wherever `makeParticleGeometry` lives) — change the return type to `any ParticleGeometry`. The construction logic stays exactly as it is today (`ProceduralGeometry(...)` is the only branch).

4. `PhospheneEngine/Sources/Renderer/RenderPipeline+FeedbackDraw.swift` — change the type of the stored particle-geometry reference from `ProceduralGeometry` to `any ParticleGeometry`. The dispatch logic stays exactly as it is.

5. `CLAUDE.md` — add a short note in the appropriate section (likely near the existing particle / Murmuration documentation) describing the protocol pattern. Suggested wording: *"Particle presets are siblings, not subclasses. Each owns its own compute+render pipeline; the engine schedules through `ParticleGeometry`. Murmuration's `ProceduralGeometry` is one conformer; future particle presets each define their own conformer rather than parameterizing a shared pipeline."*

6. `ENGINEERING_PLAN.md` — add an `Increment DM.0` landing-note section at the end of active increments, following the format of an existing completed increment (e.g. `Increment SB.0`).

7. `DECISIONS.md` — add a brief decision entry (suggested ID: D-097, but verify against the latest decision number in the file). Title: *"Particle preset architecture: siblings, not subclasses."* Content: the design call described in the *Context* section above, plus what was rejected (parameterized common pipeline) and why (configuration interface bloats with disjoint preset-specific concepts).

**Do NOT modify:**

- `Particles.metal` (Murmuration's MSL kernel — byte-identical post-DM.0)
- `Particle` struct definition in Swift or MSL (memory layout preserved)
- Any preset's `.json` sidecar
- Any other engine file outside the four listed above

---

## Tasks

### Task 1 — Discovery (read, then write a one-page design note before any code)

Before defining the protocol, write a short design note to clarify the surface area. The note doesn't need to be checked in; it's a thinking artifact you'll reference in Task 2. Capture:

1.1 The exact API surface of `ProceduralGeometry` that the render pipeline currently uses. List each method called from `RenderPipeline+FeedbackDraw.swift` (lines ~91–101) and `VisualizerEngine` with its full signature.

1.2 Lifecycle hooks — at what points does `VisualizerEngine` instantiate, retain, replace, or release the particle geometry? (Likely: instantiation at `applyPreset()`, replacement on preset switch, release on app shutdown.)

1.3 Naming convention check — what protocols exist in the codebase already? What's the prevailing style (e.g. `Foo` noun, `Fooable` adjective, `FooProviding` participle)? Confirm `ParticleGeometry` matches the dominant pattern. If not, propose an alternative name and justify.

1.4 What Drift Motes will eventually need — per `Drift_Motes_Rendering_Architecture_Contract.md` "Required passes" table, Drift Motes needs: particle buffer allocation, per-frame compute dispatch (its own kernel), per-frame render dispatch (its own vertex+fragment), feedback compatibility (decay 0.92). Confirm these are all expressible through the same protocol surface that Murmuration uses today.

- **Done when:** You have a written list of (a) protocol methods to introduce, (b) the naming you'll use, (c) one paragraph confirming Drift Motes' needs are satisfied by the surface (without prejudicing implementation choices that belong in DM.1).

### Task 2 — Define the protocol

2.1 Create the protocol file. The protocol surface should be **minimal** — only what's needed to dispatch Murmuration's existing flow. If a method on `ProceduralGeometry` isn't called from outside the class, it's not in the protocol.

2.2 Include doc comments on each protocol member describing what conformers must do. Reference D-097 (the new decision) and CLAUDE.md.

2.3 The protocol should not be generic over particle type. The Particle struct is fixed (64 bytes, defined in MSL header) and shared across all particle presets. Conformers don't reinvent the struct.

2.4 The protocol should not expose the underlying buffer or pipeline state. Encapsulation is the point; the engine schedules dispatch through the protocol's methods, not through buffer access.

- **Done when:**
  - The protocol file compiles cleanly.
  - Every protocol member has a doc comment.
  - The protocol surface contains only methods currently called from outside `ProceduralGeometry`.

### Task 3 — Make ProceduralGeometry conform

3.1 Add `: ParticleGeometry` to the class declaration.

3.2 If method signatures already match (most likely case — you're naming the protocol around what Murmuration already does), no body changes are needed beyond the conformance declaration.

3.3 If a signature mismatch exists (e.g. `ProceduralGeometry` takes a `ProceduralConfig` parameter that the protocol doesn't), reconcile by adjusting the **protocol** to match `ProceduralGeometry`'s current signature, not by rewriting `ProceduralGeometry`. The principle: the protocol describes Murmuration's current behavior; it doesn't impose new constraints on Murmuration. (Drift Motes will conform to the same protocol; if Drift Motes needs a different signature, that's a Drift Motes design problem, not a protocol problem.)

3.4 Group conforming methods under `// MARK: - ParticleGeometry` for readability.

- **Done when:**
  - `ProceduralGeometry` conforms to `ParticleGeometry`.
  - `swift build` produces no errors and no new warnings.
  - The diff to `ProceduralGeometry.swift` is small (ideally just the conformance declaration plus a MARK comment).

### Task 4 — Route the engine through the protocol

4.1 In `VisualizerEngine.swift` (or wherever `makeParticleGeometry` lives), change the return type from `ProceduralGeometry` to `any ParticleGeometry`. The construction logic stays as it is — only Murmuration's path exists today, and it returns `ProceduralGeometry(...)`.

4.2 In `RenderPipeline+FeedbackDraw.swift`, change the stored reference's type from `ProceduralGeometry?` to `(any ParticleGeometry)?` (or whatever optional form matches the codebase's pattern). The dispatch lines (`particles.render(...)`, etc.) stay byte-identical; they're now calling protocol requirements rather than concrete methods.

4.3 Verify there are no other call sites that depend on `ProceduralGeometry`'s concrete type. Grep for `ProceduralGeometry` across `PhospheneEngine/Sources/` to confirm. If other call sites exist, evaluate each: if it can be expressed through the protocol, change it; if it depends on concrete behavior, that's a stop-condition (the protocol surface is incomplete — return to Task 2).

- **Done when:**
  - All call sites that previously held a `ProceduralGeometry` reference now hold `any ParticleGeometry`.
  - `swift build` produces no errors and no new warnings.
  - `grep "ProceduralGeometry" PhospheneEngine/Sources/` returns matches only inside `ProceduralGeometry.swift` itself (the type declaration site) and possibly `VisualizerEngine.swift` (the factory site that constructs it). No "leaked" concrete-type dependencies elsewhere.

### Task 5 — Verify Murmuration's behavior is bit-identical

This is the gate. If it fails, the refactor is wrong.

5.1 Run `swift test --package-path PhospheneEngine --filter PresetRegressionTests`. Murmuration's dHash entry must be **bit-identical** to the pre-DM.0 value. Other presets must also pass (no incidental drift).

5.2 If Murmuration's hash changes, the refactor introduced a behavior delta. Diagnose: most likely causes are (a) a method body change you didn't realize was a behavior change, (b) a lifecycle ordering change (e.g. construction now happens at a different frame), (c) an Optional unwrap or default value that's now resolving differently. Fix and re-run. **Do not update the golden hash to match the new value** — that defeats the regression test.

5.3 Run all other tests: `swift test --package-path PhospheneEngine`. All must pass.

5.4 Run a smoke test by launching the app and selecting Murmuration. Visually confirm it renders identically (the dHash test should be sufficient, but a visual sanity check catches any classes of drift the dHash misses, e.g. timing-dependent variation that hashes consistently but looks different to a human).

- **Done when:**
  - `PresetRegressionTests` passes with Murmuration's hash unchanged.
  - All other tests pass.
  - Visual smoke test confirms Murmuration renders as expected.

### Task 6 — Documentation

6.1 Add the protocol description to `CLAUDE.md`. Suggested location: near the existing particle / Murmuration documentation. Suggested wording (adapt to the file's existing voice):

> **Particle preset architecture (D-097).** Particle presets are siblings, not subclasses. Each owns its own compute+render pipeline. The engine schedules through `ParticleGeometry` (defined in `Renderer/Geometry/ParticleGeometry.swift`); presets conform individually. Murmuration's `ProceduralGeometry` is one conformer. Future particle presets define their own conformer rather than parameterizing a shared pipeline. The Particle struct memory layout (64 bytes, `packed_float4 color`) is shared across all conformers and lives in `Particles.metal` / `ProceduralGeometry.swift`.

6.2 Add the `D-097` decision entry to `DECISIONS.md`. Verify the next available decision number first; if D-097 is taken, use the next one. Content:

> ## D-097 — Particle preset architecture: siblings, not subclasses (Increment DM.0)
>
> **Status:** Accepted (date)
>
> **Context:** Drift Motes (DM.1) was scoped against the assumption that Murmuration's `Particles.metal` + `ProceduralGeometry` constituted reusable particle infrastructure. Implementation discovered they're a single-tenant Murmuration implementation: hardcoded kernel names, hardcoded particle count and tuning, hardcoded bird-silhouette fragment color. Plugging Drift Motes into the existing dispatch would render Murmuration's flock kernel over Drift Motes' sky backdrop — the literal anti-pattern called out in Drift Motes' design.
>
> **Two paths considered.** (a) Parameterize `ProceduralGeometry` to host both flocking and force-field-drift through one config (kernel names, particle count, decay rate, drag, etc.). (b) Introduce a `ParticleGeometry` protocol; Murmuration conforms via existing `ProceduralGeometry` without behavior change; Drift Motes ships its own conformer; the engine schedules through the protocol.
>
> **Decision: (b).** Murmuration and Drift Motes are different enough that parameterizing one pipeline to host both bloats the configuration interface with a union of disjoint concepts (Murmuration's homePos generation, decay-rate-0 persistence, drum-driven turning waves; Drift Motes' recycle bounds, emission position derivation, per-emission hue baking). Parameterization would force future particle presets to fit a shared interface that compromises their design; protocol-based conformance lets each preset express itself cleanly while sharing only what genuinely is shared (the Particle struct memory layout, the buffer-then-dispatch convention).
>
> **What was rejected:** parameterized common pipeline. The configuration surface required to express both Murmuration and Drift Motes is large and would only grow with future particle presets (snowfall, sparks, rain, wave spray each have their own physics). "Siblings, not subclasses" generalizes correctly; parameterized common pipeline does not.

6.3 Add the `Increment DM.0` landing note to `ENGINEERING_PLAN.md`, following the format of `Increment SB.0` or similar. Include scope, done-when criteria from this prompt, verification commands, and `Status: ✅ landed YYYY-MM-DD`.

- **Done when:** All three documentation files updated. Diffs are small and focused.

---

## Verification (run before declaring complete)

```bash
# 1. Compile cleanly
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build

# 2. All tests pass — most importantly, PresetRegressionTests
swift test --package-path PhospheneEngine

# 3. PresetRegressionTests Murmuration row unchanged (the gate)
swift test --package-path PhospheneEngine --filter PresetRegressionTests

# 4. No leaked ProceduralGeometry concrete-type dependencies outside the
#    declaration and factory sites
grep -rn "ProceduralGeometry" PhospheneEngine/Sources/
# Expected matches: ProceduralGeometry.swift (the type itself), VisualizerEngine.swift
# (the factory). Anything else is a leak.

# 5. No new presets accidentally landed
ls PhospheneEngine/Sources/Presets/Shaders/ | grep -i "drift"
# (should return ZERO matches — DriftMotes.metal/.json land in DM.1, not DM.0)

# 6. Murmuration's MSL untouched
git diff PhospheneEngine/Sources/Presets/Shaders/Particles.metal
# (should return ZERO output — the file is byte-identical to pre-DM.0)

# 7. Particle struct layout untouched
git diff PhospheneEngine/Sources/Renderer/Geometry/ProceduralGeometry.swift | grep -E "Particle\s*[{:]|packed_float4|sizeof"
# (no changes to struct definition — only conformance declaration changes acceptable)

# 8. Visual references lint still passes
swift run --package-path PhospheneTools CheckVisualReferences --strict
```

If **any** of these fail, do not commit. Fix the failure first.

---

## Anti-patterns — explicit failures to avoid

1. **Premature parameterization.** Don't add config knobs Murmuration doesn't need today. The protocol is shaped around current behavior, not hypothetical futures. If Drift Motes (DM.1) discovers it needs an additional protocol method, that's a small DM.1 amendment, not a DM.0 over-design.

2. **Behavior change in Murmuration.** The `PresetRegressionTests` dHash gate exists for this. Any change to Murmuration's rendered output — even a one-pixel difference, even a one-frame timing shift — fails DM.0. The refactor is a no-op for Murmuration.

3. **Touching `Particles.metal` for any reason.** The MSL is byte-identical post-DM.0. If you find yourself wanting to "clean up" the kernel or "modernize" the syntax, stop. That's a separate increment with a separate review.

4. **Adding Drift Motes scaffolding "while we're in here."** No `DriftMotes.*` files. No DM.1 placeholders. No "TODO: Drift Motes" comments in the engine. DM.1 is its own session with its own scope.

5. **Restructuring unrelated engine code.** If Task 4's grep for `ProceduralGeometry` references surfaces tendrils into other parts of the engine that look like they should be cleaned up, resist. Document them as follow-up issues if warranted, but don't fix them in DM.0.

6. **Updating the regression hash to match new output.** If Murmuration's dHash changes, that's a bug, not a hash to update. The whole point of the test is to detect drift; updating it defeats the purpose. Diagnose the behavior delta and fix it.

7. **Generic protocol over particle type.** The Particle struct is fixed. Don't make `ParticleGeometry` generic over `<P: ParticleProtocol>` or similar. There is one Particle layout in the engine.

8. **Exposing the underlying buffer or pipeline state.** Encapsulation is the point. The engine schedules dispatch through protocol methods, not by reaching into the conformer's buffer.

9. **Designing the protocol "for extensibility."** The protocol's job is to express Murmuration's current dispatch, no more. If you find yourself adding optional protocol methods, default implementations, or extension points, stop.

---

## Commit cadence

Per project convention (`CLAUDE.md` commit format): `[<increment-id>] <component>: <description>`.

Suggested commit cadence for DM.0:

```
[DM.0] ParticleGeometry: protocol introduction (no conformers yet)
[DM.0] ProceduralGeometry: conform to ParticleGeometry
[DM.0] VisualizerEngine: factory returns any ParticleGeometry
[DM.0] RenderPipeline: dispatch through ParticleGeometry protocol
[DM.0] Docs: D-097 + CLAUDE.md particle architecture note
[DM.0] Docs: ENGINEERING_PLAN landing note for DM.0
```

After each commit, push. Do not batch.

The first commit (protocol introduction with no conformers) should compile but be inert — the protocol exists, nothing conforms to it. The second commit makes Murmuration conform but the engine still uses the concrete type. The third and fourth commits route through the protocol. This ordering means each commit is reviewable in isolation.

---

## Done-when (overall session gate)

DM.0 is complete when **all** of the following are true:

- [ ] `ParticleGeometry` protocol exists with a minimal, documented surface.
- [ ] `ProceduralGeometry` conforms to `ParticleGeometry` with a near-zero-change diff.
- [ ] `VisualizerEngine` and `RenderPipeline+FeedbackDraw.swift` route through the protocol; no concrete `ProceduralGeometry` references outside the type's own file and the factory site.
- [ ] `PresetRegressionTests` passes with Murmuration's dHash bit-identical.
- [ ] All other tests pass.
- [ ] Visual smoke test of Murmuration confirms identical rendering.
- [ ] `CLAUDE.md` documents the protocol pattern.
- [ ] `DECISIONS.md` has the D-NNN entry.
- [ ] `ENGINEERING_PLAN.md` has the `Increment DM.0 ✅ landed <date>` block.
- [ ] All commits use `[DM.0]` prefix.
- [ ] All verification commands pass.

If you hit a stop-condition (Murmuration's dHash drift you can't diagnose, a leaked concrete-type dependency that requires unrelated refactoring, a protocol shape that can't express Murmuration's current behavior cleanly), **stop and report**. Do not work around it.

---

## After DM.0 lands

DM.1 resumes with one small revision: Task 6 (pass wiring) now references the conformer pattern from DM.0 rather than treating Murmuration's path as inherited infrastructure. Drift Motes ships:

- `DriftMotes.metal` with its own compute kernel + sprite vertex/fragment
- `DriftMotes.json` declaring `family: "particles"` and the standard sidecar fields
- A new Swift type (`DriftMotesGeometry`) conforming to `ParticleGeometry`, owning Drift Motes' particle buffer and pipeline states
- `VisualizerEngine`'s `makeParticleGeometry` factory gains a Drift Motes branch
- `DriftMotesNonFlockTest` as the Session 1 acceptance gate

Each subsequent particle preset adds a new conformer + factory branch. No central registry; no parameterized common pipeline. Siblings, not subclasses.

DM.0 is the seam that makes that pattern possible. Get the protocol shape right; everything downstream depends on it.
