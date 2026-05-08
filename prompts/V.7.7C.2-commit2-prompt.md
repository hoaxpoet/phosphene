Execute Commit 2 of Increment V.7.7C.2 — the bulk of the increment:
the CPU-side build state machine, the 1–2 saturated background-web pool,
the per-segment spider cooldown, the `PresetSignaling` conformance, and
the WebGPU 80→96 byte extension. **No shader logic changes** — the
shader-side build-aware rendering and golden hash regeneration are
Commit 3.

Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md` §5 (THE WEB) — §5.1
(real construction biology), §5.2 (60-second compressed cycle), §5.3
(frame polygon), §5.4 (hub knot — NOT concentric rings), §5.5
(radials, alternating-pair draw order), §5.6 (capture spiral chord-
segment SDF, INWARD), §5.7 (sag), §5.8 (drop recipe — V.7.7C lock),
§5.9 (anchor terminations on near-frame branches), §5.12 (background
webs), §6.5 (spider trigger pause/resume).

Architectural records: `docs/DECISIONS.md` D-072 (compositing-anchored
diagnosis, V.7.5 → V.7.7+), D-092 (V.7.7B port), D-093 (V.7.7C
refractive dewdrops), D-094 (V.7.7D 3D spider + chitin + listening
pose + 12 Hz vibration), D-095 (V.7.7C.2 — open; this is its
second commit). The first commit of V.7.7C.2 (`38d1bfab`) added the
§5.9 branchlet anchor positions as `kBranchAnchors[6]` in
`Arachne.metal` and `ArachneState.branchAnchors` in Swift; this
commit consumes them in the frame-polygon builder.

V.7.6.2 channel: `PhospheneEngine/Sources/Orchestrator/PresetSignaling.swift`
+ `PhospheneApp/VisualizerEngine+Presets.swift:328` — the subscription
path is wired and waiting; ArachneState does not yet conform to
`PresetSignaling`. This commit makes it conform and fires the event
on settle.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. Commit 1 of V.7.7C.2 has landed. Verify with:
   `git log --oneline | grep '\[V\.7\.7C\.2\]' | wc -l` — expect ≥ 1.
   `git log --oneline | head -1` — expect title containing
   `[V.7.7C.2] Arachne: WORLD branch-anchor twigs (D-095)`.

2. `ArachneState.branchAnchors` is the Swift mirror of
   `kBranchAnchors[6]` and the Sub-item 1 regression test exists.
   Confirm:
   `grep -nE 'public static let branchAnchors' PhospheneEngine/Sources/Presets/Arachnid/ArachneState.swift`
   — expect one hit at the top of the type body.
   `ls PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneBranchAnchorsTests.swift`
   — expect file present.

3. V.7.7D landed. Verify:
   `grep -nE 'sd_spider_combined|kTremorHz|listenLiftEMA' PhospheneEngine/Sources/Presets/Shaders/Arachne.metal | head -5`
   — expect occurrences of all three.
   `grep -n 'updateListeningPose\|listenLiftEMA' PhospheneEngine/Sources/Presets/Arachnid/ArachneState+ListeningPose.swift`
   — expect non-zero hits.

4. The §5.8 Snell's-law drop recipe is the lock at both call sites
   (V.7.7C, D-093). V.7.7C.2 reuses the recipe verbatim — drop colour
   per pixel does not change. What changes is per-chord **drop count**
   and **per-chord age** — but those changes are SHADER-SIDE and ship
   in Commit 3, not here. Commit 2 stores per-chord birth times in
   CPU state only.

5. `PresetSignaling` is wired and waiting. Confirm:
   `grep -nE 'activePresetSignaling|presetCompletionCancellable' PhospheneApp/VisualizerEngine+Presets.swift | head -5`
   — expect 4+ hits. ArachneState does NOT yet conform; this commit
   makes it conform.

6. `ArachneSpiderGPU` is 80 bytes (`tip[8]` + `blend/posX/posY/heading`).
   V.7.7D / V.7.7C.2 both keep it stable. **NO struct expansion in
   this commit.**

7. `ArachneWebGPU` is currently 80 bytes — 5 rows of 4 floats. This
   commit extends it to 96 bytes (6 rows) per Sub-item 2 OPTION A.
   The shader-side struct definition mirrors the Swift change but the
   shader makes no use of Row 5 yet (that is Commit 3).

8. Decision-ID is D-095 (assigned to V.7.7C.2 in Commit 1; same ID
   carries through Commits 2 and 3). Verify with
   `grep '^## D-0' docs/DECISIONS.md | tail -3` — expect D-095 NOT yet
   present (it is filed as part of Commit 3 alongside the rest of the
   doc updates).

9. `git status` is clean except `prompts/*.md`, `default.profraw`, and
   `docs/presets/ARACHNE_3D_DESIGN.md`. Anything else: surface and confirm
   before proceeding.

────────────────────────────────────────
GOAL
────────────────────────────────────────

After Commit 2 the Arachne preset's CPU-side state model is the
biology-correct build the v8 design has been working toward, but the
shader still renders the V.7.5 visual signature — the build state is
**stored**, not yet **drawn**. Commit 3 adds the shader-side reads
that make the build progression visible.

Specifically:

- **`ArachneState.BuildState`**: a struct tracking a single foreground
  web's progression through frame → radial → spiral → settle → evict
  phases over ~50–55 s of music. Contains the polygon (4–7 of 6
  branch anchors), the alternating-pair radial draw order
  (`[0, n/2, 1, n/2+1, …]` per §5.5), the spiral chord precompute
  (revolutions × radialCount), and per-chord birth times for §5.8
  drop accretion.

- **Audio-modulated TIME pacing** (NOT beats): `pace = 1.0 + 0.18 ×
  f.mid_att_rel + max(0, 0.5 × stems.drums_energy_dev)`. At silence
  pace = 1.0 → 60 s build cycle. At average music pace ≈ 1.4 → ~43 s.
  D-026 ratio: continuous coefficient (0.18 × mid_att_rel, peak ~0.18)
  vs per-frame accent (0.5 × drums_energy_dev, typical peaks ~0.05–0.07)
  ≈ 3.6× — well above the 2× rule.

- **`ArachneState.BackgroundWeb`** array (1–2 entries): saturated
  background webs at depth, full drop count from preset entry, sag at
  the upper end of `kSag` range, blur applied by post-process or
  in-shader. They do NOT advance — they're already finished. The
  CPU state is set up here; the shader reads them in Commit 3.

- **Per-segment spider cooldown**: replaces V.7.5's 300 s session lock
  per §6.5. `spiderFiredInSegment: Bool` reset on `BuildState.reset()`.
  At most one spider appearance per Arachne segment.

- **Build pause/resume on spider**: while `spider.blend > 0.01`, all
  build accumulators (`frameProgress`, `radialIndex`, `radialProgress`,
  `spiralChordIndex`, `spiralChordProgress`) freeze. When the spider
  fades, accumulators advance from where they paused — no restart,
  no regression to the last-completed step.

- **`presetCompletionEvent`**: ArachneState conforms to
  `PresetSignaling` and emits once when `BuildState.stage` reaches
  `.stable` (the settle phase). Orchestrator subscription is already
  wired in `VisualizerEngine+Presets.swift:328`; no app-layer changes
  needed beyond confirming the wiring picks up the new conformance.

- **`WebGPU` 80 → 96 bytes** (Sub-item 2 OPTION A): a Row 5 packs
  `(stage, frameProgress, radialIndex + radialProgress, spiralChordIndex
  + spiralChordProgress)` so Commit 3's shader can read build state
  per pixel. The Metal `ArachneWebGPU` struct mirrors the Swift change
  byte-for-byte; the existing shader code does NOT read Row 5 yet.

The success criterion for this commit is **"the build state machine
runs in CPU memory across the 60-second cycle, the completion event
fires exactly once, the spider trigger pauses/resumes the build cleanly,
and the WebGPU 80→96 byte expansion compiles + flushes without
disturbing existing preset rendering"**. Not yet visible — visual
verification is Commit 3.

The risk to manage is **scope creep**. Commit 2 explicitly does NOT
modify:
- the §5.8 drop recipe (V.7.7C lock — D-093);
- the spider 3D SDF, chitin material, listening pose, or 12 Hz
  vibration (V.7.7D lock — D-094);
- the WORLD pillar's six-layer composition (V.7.7B lock — D-092)
  beyond the §5.9 anchor twigs already added in Commit 1;
- `arachne_composite_fragment` or `arachneEvalWeb`'s drawing logic
  (Commit 3 scope);
- `ArachneSpiderGPU` (V.7.7D contract);
- visual references in `docs/VISUAL_REFERENCES/arachne/`.

If a tuning change feels needed, surface before diverging.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

Six file changes / additions, all CPU-side or struct-definition:

1. **`PhospheneEngine/Sources/Presets/Arachnid/ArachneState.swift`** —
   `BuildState` struct, phase-advance helpers, polygon selection from
   `branchAnchors`, alternating-pair radial-order computation, spiral
   chord precompute, `pausedBySpider` integration, `reset()` semantics,
   `WebGPU` extended to 96 bytes (Row 5), per-tick advance replaces
   the V.7.5 4-web pool driver.

2. **`PhospheneEngine/Sources/Presets/Arachnid/ArachneState+Spider.swift`** —
   per-segment cooldown gate (`spiderFiredInSegment: Bool`), reset on
   segment start (in `BuildState.reset()`), preserve all V.7.5
   sustained-bass conditions on top.

3. **`PhospheneEngine/Sources/Presets/Arachnid/ArachneState+BackgroundWebs.swift`** (new) —
   `BackgroundWeb` struct + 1–2 saturated background pool, migration
   on completion crossfade. The migration *logic* lives here; the
   *visual* crossfade is Commit 3.

4. **`PhospheneEngine/Sources/Presets/Arachnid/ArachneState+Signaling.swift`** (new) —
   `PresetSignaling` conformance, `_presetCompletionEvent` private
   `PassthroughSubject<Void, Never>`. Public wrapper exposes the event
   exactly per `PresetSignaling` protocol contract.

5. **`PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`** —
   `ArachneWebGPU` struct expanded to 96 bytes (6 rows of 4 floats)
   to mirror Swift `WebGPU`. **No other shader changes.** The new
   Row 5 fields are not yet read by `arachne_composite_fragment` or
   `arachneEvalWeb` — Commit 3 adds the reads.

6. **`PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneStateBuildTests.swift`** (new) —
   ≥ 8 tests covering the bullets in VERIFICATION §10.

────────────────────────────────────────
SUB-ITEM DETAILS
────────────────────────────────────────

──── Sub-item 2: ArachneState build state machine ────

**Build state model (CPU side):**

```swift
// V.7.7C.2 — build state for the single foreground web.
//
// All progress values are in [0, 1] within their respective phases.
// `pausedBySpider: Bool` — when true (set whenever spider.blend > 0.01),
// the per-tick advance is skipped on all *Progress fields.
//
// The build advances on a *time* basis (seconds since segment start
// minus paused time), modulated by audio per §7. Beats are NOT used
// for stage advancement — V.7.5's beat-measured stage timing was
// admitted in §5.2 to be wrong; build pace must scale with audio
// energy, not metronome time.
internal struct BuildState {
    // Frame phase — bridge first, then polygon edges.
    var frameProgress: Float = 0           // 0..1 over the frame phase
    var bridgeAnchorPair: (Int, Int) = (0, 1) // which two of the kBranchAnchors are bridge endpoints

    // Polygon — selected at segment start, subset of kBranchAnchors.
    var anchors: [Int] = []                 // 4-7 indices into branchAnchors
    var anchorBlobIntensities: [Float] = [] // 0..1 per anchor blob; ramps as it's reached

    // Radial phase — 12–17 spokes drawn alternating-pair.
    var radialCount: Int = 13                  // chosen at segment start from rng_seed
    var radialIndex: Int = 0                   // current radial being drawn (0..radialCount-1)
    var radialProgress: Float = 0              // 0..1 within the current radial
    var radialDrawOrder: [Int] = []            // pre-computed alternating-pair order

    // Spiral phase — chord segments INWARD.
    var spiralRevolutions: Float = 8.0         // 7–9 from rng_seed
    var spiralChordsTotal: Int = 0             // pre-computed at phase entry
    var spiralChordIndex: Int = 0              // current chord being laid
    var spiralChordProgress: Float = 0         // 0..1 within the current chord
    var spiralChordBirthTimes: [Float] = []    // age of each chord since laid; for §5.8 drop accretion

    // Stage + paused
    var stage: WebStage = .frame
    var stageElapsed: Float = 0                // seconds since stage entry
    var pausedBySpider: Bool = false           // set externally by tick() when spider.blend > 0.01
    var segmentStartTime: Float = 0            // accTime at preset entry
    var completionEmitted: Bool = false        // guards against double-fire

    static func zero() -> BuildState { BuildState() }
}
```

**Per-tick advance.** In `_tick(features:stems:)`:

```swift
// 1. Update spider pause guard.
let spiderActive = spiderBlend > 0.01  // the existing field
buildState.pausedBySpider = spiderActive

// 2. Compute per-frame time advance, audio-modulated.
let basePace: Float = 1.0                                     // segments/second at silence
let midBoost: Float = 0.18 * features.midAttRel
let drumAccent: Float = 0.5 * stems.drumsEnergyDev
let pace = basePace + midBoost + max(0, drumAccent)

let dt: Float = features.deltaTime
let effectiveDt = buildState.pausedBySpider ? 0 : dt * pace

// 3. Advance the appropriate phase.
switch buildState.stage {
case .frame:
    advanceFramePhase(by: effectiveDt)
case .radial:
    advanceRadialPhase(by: effectiveDt)
case .spiral:
    advanceSpiralPhase(by: effectiveDt)
case .stable:
    // Settle phase — emit completionEvent once.
    if !buildState.completionEmitted {
        _presetCompletionEvent.send()
        buildState.completionEmitted = true
    }
case .evicting:
    advanceEvictingPhase(by: effectiveDt)
}
```

**Phase advance helpers** — each function does the work for that phase.
Approximate timing (at average music = pace ~ 1.4):

- `advanceFramePhase`: `stageElapsed` accumulates by `effectiveDt`;
  bridge thread visible over 0–1 s; remaining frame threads laid
  sequentially over 1–3 s. At `stageElapsed >= 3.0`, transition to
  `.radial`.
- `advanceRadialPhase`: each radial draws over `1.5 s`; advance
  `radialIndex` when `radialProgress` reaches 1; transition to
  `.spiral` when `radialIndex == radialCount`.
- `advanceSpiralPhase`: each chord draws over `0.3 s`; advance
  `spiralChordIndex` when `spiralChordProgress` reaches 1; transition
  to `.stable` when `spiralChordIndex == spiralChordsTotal`. As each
  chord is laid, append `spiralChordBirthTimes.append(stageElapsed)`.
- `advanceEvictingPhase`: opacity ramps to 0 over 1 s during migration
  to background pool; cleared on completion.

**Reset on segment start.** When the preset is re-applied (orchestrator
transition into Arachne) or when a new track begins, `arachneState.reset()`:
- Resets BuildState to defaults.
- Picks a fresh `radialCount` ∈ [12, 17] and `spiralRevolutions` ∈ [7, 9]
  from `rngSeed`.
- Computes the polygon by selecting 4–7 of `branchAnchors` (Sub-item 3).
- Computes `radialDrawOrder` per §5.5.
- Resets `spiderFiredInSegment = false` (Sub-item 8).

`arachneState.reset()` is the canonical entry point — it must be called
when the preset is bound (in `applyPreset` `case .staged:` branch in
`VisualizerEngine+Presets.swift`, mirroring the existing `ArachneState`
allocation pattern). Confirm the bind path calls reset; if not, add the
call. Do NOT modify the bind path otherwise — that's V.7.7B contract.

**GPU contract (Sub-item 2 OPTION A):**

Extend `WebGPU` (Swift) and `ArachneWebGPU` (Metal) from 80 → 96 bytes
by adding a `Row 5` of 4 floats:

```swift
// Row 5: V.7.7C.2 build state (foreground hero web only — webs[0]).
// Background webs (webs[1..2]) zero this row (no progressive build).
public var buildStage: Float = 0       // WebStage.rawValue as Float
public var frameProgress: Float = 0    // 0..1
public var radialPacked: Float = 0     // radialIndex + radialProgress (e.g. 5.42 = radial 5, 42% drawn)
public var spiralPacked: Float = 0     // spiralChordIndex + spiralChordProgress
```

Document the pre-V.7.7C.2 size (80) and post-V.7.7C.2 size (96) in
CLAUDE.md GPU Contract / Buffer Binding Layout in **Commit 3**. The
buffer allocation in `ArachneState.init` (`webBufSize = maxWebs *
MemoryLayout<WebGPU>.stride`) auto-updates from 80 × 4 = 320 to
96 × 4 = 384 because it uses `.stride`, not a hardcoded constant.
Verify by adding a unit test that asserts
`MemoryLayout<WebGPU>.stride == 96`.

**Note on coexistence with V.7.5 4-web pool:** the prompt's design
guardrail says "the V.7.5 4-web pool is retired." Pragmatically for
this commit: the foreground hero web lives at `webs[0]` (driven by
`BuildState`); background webs at `webs[1..2]` (driven by
`BackgroundWeb`); `webs[3]` is unused (`isAlive = 0`). Existing pool
spawn / eviction logic is REMOVED in this commit. The shader still
walks all 4 slots, but slot 3 contributes nothing. Slots 1 and 2
render as fully-formed steady-state webs (their build state is
trivially `.stable, frameProgress=1, radialPacked=radialCount,
spiralPacked=spiralChordsTotal`). Slot 0 renders the foreground build,
but with no shader changes yet, the existing V.7.5 walking math
treats it identically to the V.7.5 stable steady-state — looks the
same as background. Commit 3 differentiates them via the new Row 5
read and progressive drawing logic.

──── Sub-item 3: Frame polygon + bridge thread (CPU only) ────

CPU side: extend `BuildState.reset()` to compute the polygon at segment
start per §5.3 (irregular polygon, 4–7 anchors). Selection rule:

- Random subset of `ArachneState.branchAnchors` (4–7 indices) from
  `rngSeed`-seeded hash.
- Order around polygon centroid (angular order).
- `bridgeAnchorPair` is the pair with the largest angular gap (they
  bookend the polygon's long axis — the bridge thread will visually be
  the "first commitment").
- If selection produces a symmetric polygon (e.g., all 6 evenly
  spaced — ref `09_anti_clipart_symmetry.jpg` anti-pattern), perturb
  one anchor by 15° per §5.3.

**Symmetric-polygon detection:** test that the 6-evenly-spaced subset
({0, 1, 2, 3, 4, 5}) is NEVER chosen as-is — perturbation should
result in at least one polygon edge differing from its neighbours by
≥ 15°.

Shader-side rendering: deferred to Commit 3.

──── Sub-item 4: Hub knot + radial draw-itself (CPU only) ────

CPU side: `radialDrawOrder` precomputed per §5.5 alternating-pair:

```swift
// §5.5 alternating-pair order: [0, n/2, 1, n/2+1, 2, n/2+2, …].
// For n=13: [0, 6, 1, 7, 2, 8, 3, 9, 4, 10, 5, 11, 12].
static func computeAlternatingPairOrder(radialCount: Int) -> [Int] {
    let half = radialCount / 2
    var order: [Int] = []
    for i in 0..<half {
        order.append(i)
        order.append(i + half)
    }
    if radialCount.isMultiple(of: 2) == false {
        order.append(radialCount - 1)
    }
    return order
}
```

Test: `computeAlternatingPairOrder(13)` returns
`[0, 6, 1, 7, 2, 8, 3, 9, 4, 10, 5, 11, 12]`.

Shader-side rendering: deferred to Commit 3.

──── Sub-item 5: Capture spiral INWARD + per-chord drop accretion (CPU only) ────

CPU side: at spiral-phase entry, precompute:
- `spiralChordsTotal = revolutions * radialCount` (for n=8 revs and
  n=13 radials, ~104 chord segments).
- Each chord `k` connects radial `(k mod radialCount)` to radial
  `((k+1) mod radialCount)` at radius
  `outerRadius - (k / radialCount) * pitch` where
  `pitch = (outerRadius - innerRadius) / revolutions`.
  **Verify the sign — INWARD means radius DECREASES with k.** A
  positive sign on the radius progression would expand outward (the
  §5.6 anti-pattern).
- `spiralChordBirthTimes[k] = stageElapsed when chord k laid`
  (appended at the moment chord k is laid, so chord 0 has the largest
  age by build end).

Drop accretion per §5.8 (CPU side data; Commit 3 reads it):

```swift
// dropCount(k) = min(maxDropsPerChord, baseDrops + accretionRate * (stageElapsed - spiralChordBirthTimes[k]))
// where:
//   baseDrops      = 3
//   accretionRate  = 0.5 drops/second/chord
//   maxDropsPerChord = chordLength * dropDensity (dropDensity ≈ 1/(4*dropRadius) per §5.8)
```

Drop accretion rate is constant (0.5/s) regardless of audio — that's
intentional per §5.8 (drops accrete on a per-chord physical timer,
not on audio).

Shader-side rendering: deferred to Commit 3.

──── Sub-item 6: Anchor blobs (CPU only) ────

§5.9: at each polygon vertex (anchor), render a small adhesive blob
where the frame thread terminates. This commit owns the CPU-side
intensity ramp; Commit 3 owns the shader rendering.

```swift
// anchorBlobIntensities[i] ramps from 0 → 1 over 0.5s as the frame
// phase reaches anchor i. Blob is rendered when intensity ≥ 0.05.
//
// Update inside advanceFramePhase: for each anchor, compute the time
// at which the frame thread "reaches" that anchor (proportional to
// frameProgress along the polygon perimeter); ramp intensity 0→1 over
// 0.5 s after that time.
```

──── Sub-item 7: Background webs + migration (CPU only) ────

§5.12: 1–2 background webs, present from preset entry, fully built
(saturated drops; sag at upper end of `kSag` range; mild blur applied
by post-process or in-shader). They share the same SDF + drop recipe
as the foreground but with `stage = .stable` and full drop counts.

CPU side (`ArachneState+BackgroundWebs.swift`):

```swift
// BackgroundWeb — a finished web that decorates the depth backdrop.
// 1–2 entries in ArachneState; their "build state" is trivially full
// (stable, all radials drawn, all spiral chords laid, all drops
// at maximum count).
internal struct BackgroundWeb {
    var webGPU: WebGPU             // includes Row 5 fully populated
    var birthTime: Float           // for migration ordering
    var opacity: Float             // 1.0 by default; ramps 1→0 during eviction
}

// ArachneState owns:
//   var backgroundWebs: [BackgroundWeb] = []   // capacity 2

// Migration on completion: when foreground reaches .stable and
// presetCompletionEvent fires, trigger a 1s crossfade where:
//   - foreground opacity ramps 1 → 0.4 (it joins the background pool).
//   - if background pool at capacity (2), oldest ramps 1 → 0 over the same 1s and is removed at end.
//   - after 1s, foreground BuildState resets and a new build cycle begins
//     (new polygon, new radials, new spiral).
```

The migration *state machine* lives here. The visual *crossfade* is
Commit 3 — in this commit the migration just sets opacity values that
the shader will read in Commit 3.

──── Sub-item 8: Per-segment spider cooldown + build pause/resume ────

EDIT — `ArachneState+Spider.swift`.

§6.5: per-segment cooldown replaces V.7.5's 300 s session lock. The
build state machine's `BuildState.segmentStartTime` is the canonical
"current segment start". The spider trigger gate reads it:

```swift
// V.7.7C.2 — per-segment cooldown.
//
// Spider can fire AT MOST ONCE per segment. `spiderFiredInSegment`
// is reset when BuildState resets (segment start).
private var spiderFiredInSegment: Bool = false

func evaluateSpiderTrigger(features: FeatureVector, stems: StemFeatures, dt: Float) -> Bool {
    // Existing V.7.5 sustained-bass trigger logic stays unchanged.
    // The cooldown gate is a NEW guard:
    if spiderFiredInSegment { return false }
    if !v75TriggerConditionMet(features: features, stems: stems, dt: dt) { return false }

    spiderFiredInSegment = true
    return true
}

// In BuildState.reset(): spiderFiredInSegment = false
```

The V.7.5 300 s `timeSinceLastSpider` field is deleted.

Build pause is wired in Sub-item 2 (`pausedBySpider = (spiderBlend >
0.01)`). When spider fades and `pausedBySpider` returns to false, the
build accumulators advance from where they paused — no restart logic
needed because `effectiveDt = 0` while paused means no progress was
recorded.

──── Sub-item 9 (partial): PresetSignaling conformance ────

NEW FILE — `ArachneState+Signaling.swift`.

```swift
import Combine
import Orchestrator

extension ArachneState: PresetSignaling {
    public var presetCompletionEvent: PassthroughSubject<Void, Never> {
        return _presetCompletionEvent
    }
}
```

In `ArachneState.swift` body, add:

```swift
// V.7.7C.2 — fires once when the build cycle reaches .stable.
// Subscribed by VisualizerEngine+Presets at preset bind via the
// activePresetSignaling() lookup.
let _presetCompletionEvent = PassthroughSubject<Void, Never>()
```

The orchestrator subscription (`activePresetSignaling()` in
`VisualizerEngine+Presets.swift:350`) automatically picks up
`ArachneState` as conforming and connects the publisher; no app-layer
changes needed beyond confirming the wiring. Verify with a one-off
`grep` before commit:

```
grep -nE 'activePresetSignaling|case .arachne|ArachneState as PresetSignaling' \
    PhospheneApp/VisualizerEngine+Presets.swift
```

If `activePresetSignaling()` resolves the conforming type at runtime
(generic / `as? PresetSignaling` cast), no app-layer change is needed.
If it pattern-matches on the concrete type, surface — that's a wiring
update for the increment.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT IN THIS COMMIT)
────────────────────────────────────────

- **Shader-side build-aware rendering.** Commit 3 owns
  `arachne_composite_fragment` reading Row 5 and rendering progressive
  build content (chord-by-chord visibility, radial draw-itself, hub
  knot fbm field, anchor-blob discs, background-web crossfade).
  Commit 2 only changes the `ArachneWebGPU` *struct definition* — the
  shader makes no use of the new Row 5 fields.
- **Golden hash regeneration.** Commit 3.
  `PresetRegressionTests.test_arachne_*` and
  `ArachneSpiderRenderTests.test_spider_forced_*` will continue to
  pass against the V.7.7D goldens because the shader doesn't read the
  new state. If they fail, something is wrong with the GPU contract
  change — the shader's `ArachneWebGPU` struct must be exactly 96
  bytes and field order must match Swift.
- **Documentation updates** (D-095, RELEASE_NOTES_DEV, CLAUDE.md
  Module Map / GPU Contract / What NOT To Do, ENGINEERING_PLAN).
  Commit 3 — the doc updates are most useful when paired with
  visually-verified shader behaviour.
- **Manual smoke on real music.** Commit 3 / increment closeout.
- Do NOT modify the §5.8 drop refraction recipe. V.7.7C is the lock.
- Do NOT modify the spider 3D SDF, chitin material, listening pose
  CPU-side state machine, or 12 Hz vibration. V.7.7D is the lock.
- Do NOT modify the WORLD pillar's six-layer composition (sky band /
  distant trees / mid trees / forest floor / fog / light shafts / dust
  motes / branchlet anchor twigs). V.7.7B + Commit 1 are the lock.
- Do NOT introduce new render passes. V.7.7C.2 stays inside the
  existing WORLD + COMPOSITE staged scaffold.
- Do NOT add or modify visual references in `docs/VISUAL_REFERENCES/arachne/`.
- Do NOT modify `ArachneSpiderGPU`. The 80-byte struct stays
  byte-for-byte identical (V.7.7D contract).
- Do NOT modify the Marschner-lite silk BRDF or restore V.7's
  fiber-material recipe. §5.10 demoted silk; V.7.7C.2 keeps silk
  thin-and-faint.
- Do NOT modify the JSON sidecar's `passes`, `stages`, or
  `naturalCycleSeconds`. The `naturalCycleSeconds: 60` is already
  set per V.7.6.C; the build state machine respects that ceiling
  through the `presetCompletionEvent` channel.
- Do NOT replace `kBranchAnchors` in MSL with a Swift-buffer-driven
  array. The two-source-of-truth is acceptable for V.7.7C.2; a future
  increment can extract them.
- Do NOT widen `naturalCycleSeconds` beyond 60.
- Do NOT change the V.7.5 sustained-bass spider trigger conditions
  (`f.subBass_dev > 0.30`, `bassAttackRatio < 0.55`, ≥ 0.75 s sustain
  — actual constants vary; preserve whatever's currently in
  `ArachneState+Spider.swift` `evaluateSpiderTrigger`'s existing
  body). Commit 2 only adds the per-segment cooldown gate ON TOP of
  those conditions.

────────────────────────────────────────
DESIGN GUARDRAILS
────────────────────────────────────────

- **One foreground hero, 1–2 background.** The V.7.5 4-web pool is
  retired. If you find yourself adding a `transientWebs: [WebGPU]`
  array, stop — that's V.7.5 thinking. The composition is one
  building hero plus a small saturated background pool. Per-web
  spawn/eviction logic does not survive into V.7.7C.2.
- **Build pace is audio-modulated TIME, not beats.** §5.2's 60-second
  cycle is approximate; the actual elapsed time depends on audio.
  V.7.5 measured stages in beats and that produced inconsistent
  build cadence on tracks with sparse vs dense beats. V.7.7C.2 uses
  `effectiveDt = dt * pace` where pace is `1.0 + 0.18 * mid_att_rel +
  drumAccent`. Beats are NOT used to advance stages.
- **Build pause/resume must be rock solid.** When the spider appears
  mid-build (e.g., during the radials phase), `radialIndex` and
  `radialProgress` freeze. When it fades, they resume from exactly
  where they were — NO restart, NO regression to the last-completed
  radial, NO advance during the spider's presence. Verify with a
  test fixture that forces a spider trigger at a known build state
  and confirms the build state is byte-identical before and after the
  spider's presence (modulo spider blend ramp time).
- **D-026 audio compliance.** The build pace's continuous driver
  (`0.18 × mid_att_rel`) is ≥ 2× the per-frame accent
  (`0.5 × drums_energy_dev` peaks at ~0.05–0.07 per frame). Ratio
  ≈ 3.6× — well above the 2× rule. Drop accretion rate is constant
  (0.5/s) regardless of audio — intentional per §5.8.
- **Failed Approach #34 caution.** The chord-segment SDF in
  `arachneEvalWeb` is the load-bearing geometry. V.7.7C.2 must not
  regress the SDF correctness — Failed Approach #34 was the
  `abs(fract−0.5)` SDF inversion bug. The spiral path must continue
  to use `min(fract, 1−fract)`. Commit 2 doesn't touch
  `arachneEvalWeb`, but the build state's spiral chord index/progress
  must use INWARD radius progression (radius DECREASES with k).
- **Failed Approach #44 caution.** Metal built-in type names as local
  variable names cause silent compilation failures. If extending the
  Metal `ArachneWebGPU` struct, do NOT use `half`, `ushort`, `uchar`,
  `packed_float3`, etc. as field names.
- **Failed Approach #48 caution.** The polygon selection must produce
  irregular polygons (ref `01` polygon irregularity, NOT ref
  `09_anti_clipart_symmetry.jpg`). The 6-evenly-spaced subset must
  never be chosen as-is — perturbation per §5.3 mandatory.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters.

1. **Build (engine)**: `swift build --package-path PhospheneEngine` —
   must succeed with zero warnings on touched files.

2. **`PresetLoaderCompileFailureTest` first**: this is the
   load-bearing gate that exposed the V.7.7C half-vector bug
   immediately. Run before the rest to fail fast on shader compile
   errors:
   ```
   swift test --package-path PhospheneEngine --filter "PresetLoaderCompileFailureTest"
   ```
   Expect Arachne preset count == 14. If it fails, the
   `ArachneWebGPU` Metal struct is malformed.

3. **GPU contract sanity check**: a one-off shell:
   ```
   swift test --package-path PhospheneEngine --filter "ArachneStateBuildTests/test_webGPUStrideIs96Bytes"
   ```
   Expect `MemoryLayout<WebGPU>.stride == 96`. If 80, the Row 5
   addition is missing or padded incorrectly. If 112+, alignment is
   off.

4. **Targeted suites**:
   ```
   swift test --package-path PhospheneEngine \
       --filter "StagedComposition|StagedPresetBufferBinding|PresetRegression|ArachneSpiderRender|ArachneState|ArachneStateBuild|ArachneListeningPose|ArachneBranchAnchors"
   ```
   Each suite must pass post-port. **`PresetRegressionTests`
   MUST stay green** — the shader doesn't read the new Row 5, so
   golden hashes must NOT change. If they do, the `ArachneWebGPU`
   struct definition has corrupted byte offsets that the shader's
   existing reads (rows 0–4) are now misinterpreting. Investigate
   immediately. **Do NOT regenerate the goldens in this commit** —
   that's Commit 3.

5. **`ArachneStateBuildTests` (new) — ≥ 8 tests**:
   - `test_webGPUStrideIs96Bytes`: `MemoryLayout<WebGPU>.stride == 96`.
   - `test_buildStateResetsToFrame`: after `arachneState.reset()`,
     stage = `.frame`, frameProgress = 0, completionEmitted = false.
   - `test_framePhaseCompletesByThreeSeconds`: drive
     `tick(features: midEnergyFV, stems: .zero)` for 60 s of
     simulated time; assert frame phase completes by `stageElapsed
     ∈ [2.5, 3.5] s` (at pace ≈ 1.18 from mid_att_rel = 1.0 silence
     boost in the test fixture; tune the bound to the actual fixture's
     pace).
   - `test_radialPhaseCompletesByExpectedTime`: from frame end,
     advance ~21 s (pace ~1.4); assert radial phase completes within
     ±3 s.
   - `test_spiralPhaseCompletesByExpectedTime`: from radial end,
     advance ~30 s; assert spiral phase completes within ±5 s.
   - `test_completionEventFiresExactlyOnce`: subscribe to
     `presetCompletionEvent`, drive 90 s of simulated time, assert
     received-count == 1.
   - `test_spiderPauseHaltsBuildProgress`: at known build state
     (radialIndex = 5, radialProgress = 0.4), force `spider.blend = 1`
     for 60 frames; assert radialIndex + radialProgress are
     byte-identical before and after.
   - `test_spiderResumeAdvancesFromPaused`: from paused state, force
     `spider.blend = 0` for 30 frames; assert radialProgress
     advances by exactly the expected `dt × pace × 30` amount.
   - `test_perSegmentSpiderCooldownPreventsRefiring`: drive enough
     sustained bass to fire the spider once; assert
     `spiderFiredInSegment = true`; drive more sustained bass; assert
     spider does NOT re-fire until `arachneState.reset()` is called.
   - `test_alternatingPairOrderForN13`: assert
     `computeAlternatingPairOrder(13)` = `[0, 6, 1, 7, 2, 8, 3, 9,
     4, 10, 5, 11, 12]`.
   - `test_polygonSelectionIsIrregular`: drive 100 different rngSeeds;
     assert no polygon has all 4 / 5 / 6 / 7 angular gaps within ±2°
     of equal (Failed Approach #48 / ref 09 anti-pattern).
   - `test_spiralChordsAreInward`: at spiral-phase entry, walk the
     precomputed chord array; assert chord `k+1`'s radius is
     STRICTLY LESS THAN chord `k`'s radius (no equal — flat means
     a degenerate ring; not less means OUTWARD).
   - `test_dropAccretionAgesChordsCorrectly`: lay 5 chords at known
     `stageElapsed` times; advance 10 s; assert the first chord's
     age ≈ 10 s and the last chord's age ≈ 10 s − (4 × 0.3 s).

   ≥ 8 tests required; the list above gives 13 — pick the most
   load-bearing 8+ to prioritize and skip / defer / fold the rest.

6. **App suite**: `xcodebuild -scheme PhospheneApp -destination
   'platform=macOS' test 2>&1 | tail -5` — must end clean except for
   the documented `NetworkRecoveryCoordinator` flakes. If a new
   failure surfaces, surface and triage before commit.

7. **Full engine suite**: `swift test --package-path PhospheneEngine
   2>&1 | tail -10` — must remain green except documented
   pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout`,
   `MemoryReporter.residentBytes` env-dependent, parallel-load
   timing).

8. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml
   --quiet` on all touched files — zero violations on touched files.
   The `Arachne.metal` file-length gate is exempt per `SHADER_CRAFT.md
   §11.1`.

9. **`git status` + `git diff --stat`** before commit: confirm only
   the six files in §SCOPE are modified, plus the new test file.
   Anything else surface and back out before committing.

────────────────────────────────────────
COMMIT
────────────────────────────────────────

One commit. Do NOT push.

```
[V.7.7C.2] Arachne: build state machine + background pool + spider integration (D-095)

Sub-items 2–8 of V.7.7C.2 — the CPU-side state machine. Foreground
hero web progresses through frame → radial → spiral → settle phases
over ~50–55 s of music with audio-modulated TIME pacing. 1–2
saturated background webs at depth. Per-segment spider cooldown
replaces V.7.5's 300 s session lock; spider trigger pauses the build,
fading resumes it. PresetSignaling conformance + completion event
fires once at settle. WebGPU struct extended 80 → 96 bytes with a
Row 5 carrying packed build state for Commit 3's shader reads.

CPU state machine (ArachneState.swift):
- BuildState struct: frame/radial/spiral progress, polygon (4–7 of
  6 branchAnchors), alternating-pair radial order ([0, n/2, 1, n/2+1,
  ...]), spiral chord precompute (revolutions × radialCount), per-chord
  birth times (stageElapsed at the moment chord k is laid, for §5.8
  drop accretion).
- Per-tick advance audio-modulated: pace = 1.0 + 0.18 × midAttRel +
  max(0, 0.5 × drumsEnergyDev). At silence pace = 1.0 → 60 s cycle;
  at average music pace ≈ 1.4 → ~43 s. D-026 ratio ≈ 3.6× (≥ 2× rule).
- pausedBySpider gates effectiveDt; resume picks up exactly where it
  left off (no restart, no regression).
- arachneState.reset() resets BuildState to defaults, picks fresh
  radialCount ∈ [12,17] and spiralRevolutions ∈ [7,9] from rngSeed,
  computes polygon (rejects the 6-evenly-spaced subset per §5.3 to
  avoid ref 09 anti-symmetry), computes radialDrawOrder per §5.5,
  resets spiderFiredInSegment.

Background webs (ArachneState+BackgroundWebs.swift, new):
- BackgroundWeb struct: WebGPU + birthTime + opacity. 1–2 entries.
  Always at .stable, full radials drawn, full spiral chords laid,
  full drop counts.
- Migration on completion: foreground reaches .stable → 1 s
  crossfade where foreground opacity ramps 1 → 0.4 (joins background
  pool); if pool at capacity (2) oldest ramps 1 → 0 over the same 1 s;
  after 1 s, foreground BuildState resets and a new build cycle
  begins. Migration logic only — visual crossfade is Commit 3.

PresetSignaling (ArachneState+Signaling.swift, new):
- ArachneState: PresetSignaling conformance.
- _presetCompletionEvent: PassthroughSubject<Void, Never> fires once
  when stage transitions into .stable (settle). Orchestrator
  subscription wired since V.7.6.2 picks it up automatically through
  activePresetSignaling().
- BuildState.completionEmitted guards against double-fire across
  ticks; reset by arachneState.reset() on cycle restart.

Per-segment spider cooldown (ArachneState+Spider.swift):
- spiderFiredInSegment: Bool replaces V.7.5's 300 s timeSinceLastSpider
  field. Reset on arachneState.reset(). At most one spider appearance
  per Arachne segment. V.7.5 sustained-bass conditions on top
  (subBass_dev > 0.30, bassAttackRatio < 0.55, ≥ 0.75 s sustain)
  unchanged.

GPU contract (ArachneWebGPU mirror in Arachne.metal):
- WebGPU 80 → 96 bytes. New Row 5 (4 floats):
  buildStage / frameProgress / radialPacked (radialIndex +
  radialProgress) / spiralPacked (spiralChordIndex +
  spiralChordProgress). Shader makes no use of Row 5 in this commit;
  the existing rows 0–4 reads are byte-offset preserved
  (rendering unchanged).
- ArachneSpiderGPU stays at 80 bytes (V.7.7D contract).

Tests (ArachneStateBuildTests.swift, new — N tests):
- test_webGPUStrideIs96Bytes: MemoryLayout<WebGPU>.stride == 96.
- test_buildStateResetsToFrame: post-reset state + completionEmitted
  flag.
- test_framePhase / test_radialPhase / test_spiralPhase complete by
  expected stageElapsed bounds at known pace.
- test_completionEventFiresExactlyOnce: 90 s simulated, count == 1.
- test_spiderPauseHaltsBuildProgress: byte-identical before/after.
- test_spiderResumeAdvancesFromPaused: exact dt × pace × N.
- test_perSegmentSpiderCooldownPreventsRefiring: false on reset only.
- test_alternatingPairOrderForN13: [0, 6, 1, 7, 2, 8, 3, 9, 4, 10,
  5, 11, 12].
- test_polygonSelectionIsIrregular: no rngSeed gives ±2° equal gaps.
- test_spiralChordsAreInward: radius strictly decreasing with k.
- test_dropAccretionAgesChordsCorrectly: per-chord ages match
  laydown order.

Verification:
- 30+ targeted tests / 8+ suites green (PresetLoaderCompileFailure +
  ArachneBranchAnchors + ArachneState + ArachneStateBuild +
  ArachneListeningPose + ArachneSpiderRender + PresetRegression +
  StagedComposition + StagedPresetBufferBinding).
- PresetRegressionTests + ArachneSpiderRender goldens UNCHANGED at
  V.7.7D values (shader doesn't read Row 5 in this commit).
- Engine + app builds clean. 0 SwiftLint violations on touched files.

Carry-forward: V.7.7C.2 Commit 3 (shader-side build-aware rendering
in arachne_composite_fragment + arachneEvalWeb; golden hash regen;
docs — D-095 in DECISIONS, RELEASE_NOTES_DEV, CLAUDE.md Module Map +
GPU Contract + What NOT To Do, ENGINEERING_PLAN), then V.7.10 cert.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **WebGPU stride is wrong (not exactly 96 bytes)**:
  `MemoryLayout<WebGPU>.stride` returns 80 still → the Row 5 addition
  was not picked up by the compiler (e.g. `private` visibility hiding
  the struct change). If 112+ → field types or padding are off
  (e.g. a `SIMD4<Float>` instead of 4 individual `Float` fields adds
  16-byte alignment that may push the struct to the next stride
  boundary). Fix by using 4 individual `Float` fields, not a
  `SIMD4<Float>`.

- **PresetRegressionTests hashes change unexpectedly**: the shader
  isn't supposed to read Row 5 yet, so no visual change is expected.
  If a hash drifts, the Metal `ArachneWebGPU` struct definition has
  corrupted byte offsets — most likely the Row 5 fields were inserted
  somewhere other than the END of the struct. Inserting in the middle
  shifts existing field offsets and the shader's reads of rows 0–4
  pull garbage. Always append Row 5 at the END of the struct in BOTH
  Swift and Metal.

- **Build never advances past frame phase**: the audio-modulated pace
  is `1.0 + 0.18 * mid_att_rel + drums_energy_dev`. At silence,
  `pace = 1.0` and `effectiveDt = dt`. So 60 s of silence should
  take 60 s. If the build stalls in frame phase, the issue is
  either (a) `effectiveDt` is being clamped to 0 by the spider pause
  (verify `pausedBySpider == false` when no spider is present), or
  (b) the phase transition condition is wrong-signed (verify
  `if stageElapsed >= 3.0 { transitionToRadial() }` not the inverse).

- **Spiral chord radii expand outward instead of inward**: chord index
  is inverted. Verify chord `k` connects radial `(k mod n)` to
  `((k+1) mod n)` at radius `outerRadius - (k / n) * pitch`. If
  `outerRadius + (k / n) * pitch`, the spiral expands outward —
  the §5.6 anti-pattern.

- **Polygon comes out symmetric** (Failed Approach #48 / ref 09): the
  `branchAnchors` array has 6 positions with intentional irregularity;
  selecting any 4–7 of them should produce an irregular polygon. If
  the rng selection returns a symmetric subset (e.g., all 6 evenly
  spaced), perturb one anchor by 15° per §5.3. Verify with the
  `test_polygonSelectionIsIrregular` test that the polygon is NEVER
  a regular hexagon.

- **`presetCompletionEvent` fires multiple times**: the
  `completionEmitted: Bool` guard exists for exactly this reason.
  Verify it's reset only on `BuildState.reset()`, NOT on every tick.
  If multiple events fire per build cycle, the orchestrator may
  prematurely transition.

- **Per-segment cooldown doesn't reset across orchestrator
  transitions**: when the orchestrator transitions IN to Arachne
  (`applyPreset(.staged)` for Arachne), `arachneState.reset()` must
  be called, which resets `spiderFiredInSegment = false`. Verify
  this in `applyPreset` `case .staged:` for `desc.name == "Arachne"`
  — without the reset, the spider can never fire on the second+
  Arachne segment in a session.

- **Build pause/resume desync**: while paused, `effectiveDt = 0` so
  no progress is recorded. On resume, the next tick advances by the
  normal `dt * pace`. If progress jumps on resume (e.g., the
  spider's blend ramp is included in elapsed time despite being
  paused), the issue is the pause guard order — pause MUST be
  checked BEFORE `effectiveDt` is computed, not after.

- **`activePresetSignaling()` doesn't pick up ArachneState**: the
  protocol-conformance dispatch should resolve `ArachneState as
  PresetSignaling` automatically via the `as?` cast in the
  app-layer subscription. If the wiring uses concrete-type pattern
  matching, surface — wiring update is in scope but should be
  documented in the commit message.

- **STOP and report instead of forging ahead** if:
  - `MemoryLayout<WebGPU>.stride` is anything other than exactly 96.
  - PresetRegressionTests + ArachneSpiderRender goldens drift from
    V.7.7D values.
  - The polygon selection logic produces fewer than 4 anchors or
    more than 7. The §5.3 spec is `4–7`; surface and tune the
    selection rng.
  - The spiral chord count exceeds 200 (degenerate case from very
    high `revolutions × radialCount`). Cap at 150 and tune the
    spec values.
  - Build cycle time at average music exceeds 65 s (above the 60 s
    ceiling). Surface and inspect the audio-modulated pace.
  - `presetCompletionEvent` fires before `stageElapsed >= 50 s` on
    the spiral phase. Premature firing causes the orchestrator to
    transition prematurely.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- Spec: `docs/presets/ARACHNE_V8_DESIGN.md` §5 (THE WEB) — most relevant
  sections §5.1, §5.2, §5.3, §5.5, §5.6, §5.8, §5.9, §5.12; §6.5
  (spider trigger pause/resume).
- Architectural records: `docs/DECISIONS.md` D-072 (compositing-
  anchored diagnosis), D-092 (V.7.7B port), D-093 (V.7.7C refractive
  dewdrops), D-094 (V.7.7D spider + vibration), D-095 (V.7.7C.2 —
  open; this commit doesn't yet file the entry — Commit 3 does).
- V.7.6.2 channel: `PhospheneEngine/Sources/Orchestrator/PresetSignaling.swift`
  + `PhospheneApp/VisualizerEngine+Presets.swift:328`.
- V.7.6.C `naturalCycleSeconds = 60` framework:
  `docs/presets/ARACHNE_V8_DESIGN.md` §9 (per-preset maxDuration framework),
  D-073 (V.7.6.C linger factors).
- Reference recipes:
  - `PhospheneEngine/Sources/Presets/Stalker/StalkerState.swift` —
    alternating-tetrapod gait + per-segment cooldown blueprint. The
    §5.5 alternating-pair radial order is structurally identical to
    Stalker's gait phase ordering.
  - `PhospheneEngine/Sources/Presets/Arachnid/ArachneState+ListeningPose.swift`
    — V.7.7D CPU-side state machine pattern (file-split for SwiftLint
    compliance).
- Visual references (anti-pattern reminders only — Commit 3 does the
  contact-sheet review):
  - `docs/VISUAL_REFERENCES/arachne/01_macro_dewy_web_on_dark.jpg`
  - `docs/VISUAL_REFERENCES/arachne/09_anti_clipart_symmetry.jpg`
  - `docs/VISUAL_REFERENCES/arachne/11_anchor_web_in_branch_frame.jpg`
- Failed Approaches: `CLAUDE.md`
  - #34 (chord-segment SDF correctness — V.7.7C.2 must not regress).
  - #44 (Metal built-in type names as variable names — silent
    compilation drop, gated by `PresetLoaderCompileFailureTest`).
  - #48 (§10.1-faithful but reference-divergent — ref 09 anti-symmetry
    polygon irregularity required).
- CLAUDE.md sections to read: §Increment Completion Protocol, §Defect
  Handling Protocol, §GPU Contract Details, §Visual Quality Floor,
  §Failed Approaches, §What NOT To Do.

────────────────────────────────────────
FORWARD CHAIN (do NOT do here)
────────────────────────────────────────

- **V.7.7C.2 Commit 3** — shader-side build-aware rendering in
  `arachne_composite_fragment` + `arachneEvalWeb` (build-aware spoke
  / chord / hub / anchor-blob rendering, polygon visibility ramps,
  hub fbm knot, anchor-blob discs, background-web crossfade reads
  Row 5); golden hash regeneration (`PresetRegressionTests` Arachne
  hash; `ArachneSpiderRenderTests` spider forced hash — both expected
  to diverge significantly from V.7.7D values); docs (D-095 in
  DECISIONS, RELEASE_NOTES_DEV, CLAUDE.md Module Map / GPU Contract /
  What NOT To Do, ENGINEERING_PLAN). Manual smoke on real music is
  load-bearing for Commit 3 closeout.
- **V.7.10** — Matt M7 contact-sheet review + cert. V.7.7C.2 is the
  last structural increment before cert; V.7.10 is the QA + sign-off
  pass. No further structural changes are planned post-V.7.7C.2.
