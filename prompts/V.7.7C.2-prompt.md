Execute Increment V.7.7C.2 — Replace the V.7.5 4-web pool with a
single-foreground biology-correct build state machine: frame polygon
→ radials (alternating-pair, drawn one at a time) → INWARD capture
spiral with per-chord drop accretion → settle. Emit
`presetCompletionEvent`. Plus 1–2 saturated background webs at depth,
per-segment spider cooldown, and build-pause-on-spider semantics.

Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md` §5 (THE WEB) in full —
§5.1 (real construction biology) → §5.13 (reference cross-walk). The
60-second compressed cycle in §5.2 is the timing table this increment
implements. §5.6 (capture spiral chord-segment SDF, INWARD) is the
load-bearing geometry decision; §5.9 (anchor terminations) is the
WORLD↔WEB coupling; §5.12 (background webs) is the depth context. §6.5
(spider trigger pause/resume) is the SPIDER↔WEB coupling. Architectural
record: `docs/DECISIONS.md` D-072 (compositing layers), D-092 (V.7.7B
port), D-093 (V.7.7C refractive dewdrops), D-094 (V.7.7D spider +
vibration). V.7.6.2 channel: `PhospheneEngine/Sources/Orchestrator/PresetSignaling.swift`
+ `PhospheneApp/VisualizerEngine+Presets.swift` line ~328 — the
subscription path is wired and waiting; ArachneState does not yet
conform to `PresetSignaling`.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. V.7.7D has landed. Verify with:
   `git log --oneline | grep -E '\[V\.7\.7D\]' | wc -l` — expect ≥ 1.

2. The dispatched COMPOSITE fragment renders the 3D SDF spider, chitin
   material, listening-pose tip lift, and §8.2 vibration. Confirm:
   `grep -nE 'sdSpiderCombined|mat_chitin|kTremorHz|listenLift' PhospheneEngine/Sources/Presets/Shaders/Arachne.metal | head -10`
   — expect occurrences of all four. Confirm:
   `grep -n 'updateListeningPose\|listenLiftEMA' PhospheneEngine/Sources/Presets/Arachnid/ArachneState+Spider.swift | head -5`
   — expect non-zero hits.

3. The §5.8 Snell's-law drop recipe is the lock at both call sites
   (V.7.7C, D-093). V.7.7C.2 reuses the recipe verbatim — drop colour
   per pixel does not change. What changes is per-chord **drop count**
   and **per-chord age**.

4. `PresetSignaling` is wired and waiting. Confirm:
   `grep -nE 'activePresetSignaling|presetCompletionCancellable' PhospheneApp/VisualizerEngine+Presets.swift | head -5`
   — expect 4+ hits. ArachneState does NOT yet conform; V.7.7C.2 makes
   it conform and emit at the end of the spiral phase (§5.2 settle).

5. `ArachneSpiderGPU` is 80 bytes (`tip[8]` + `blend/posX/posY/heading`).
   V.7.7D kept it stable. V.7.7C.2 also keeps it stable. NO struct
   expansion in this increment.

6. `ArachneWebGPU` is 80 bytes — 5 rows of 4 floats. V.7.7C.2 may extend
   it to 96 bytes (6 rows) to carry per-web build accumulators
   (frameProgress / radialIndex / radialProgress / spiralChordIndex /
   spiralChordProgress / chordAges …). See Sub-item 2 below; the
   alternative — pure CPU-side state with periodic flush — is also
   acceptable and avoids the GPU-contract change. Choose one approach
   in Sub-item 2 and document the choice in D-095.

7. Decision-ID numbering: D-094 was V.7.7D (most recent). V.7.7C.2 is
   D-095 unless something else has landed in between — verify with
   `grep '^## D-0' docs/DECISIONS.md | tail -3` and use the next free
   integer.

8. `git status` is clean except `prompts/*.md` and `default.profraw`.

────────────────────────────────────────
GOAL
────────────────────────────────────────

After V.7.7C.2 the dispatched Arachne preset is the **biology-correct
hero web** the v8 design has been working toward since D-072:

- A SINGLE foreground hero web visibly builds itself over ~50–55s of
  music. Phases:
  - **Frame (0–3s):** a bridge thread appears first (a single horizontal
    silk line between two of the chosen anchor points), then 3–6
    additional frame threads connecting branch anchors into an
    irregular polygon. Anchor blobs land at the polygon vertices where
    threads terminate on near-frame branches.
  - **Radials (3–25s):** 12–17 thin spokes from hub to polygon edge,
    drawn one at a time in alternating-pair order (`[0, n/2, 1, n/2+1,
    2, n/2+2, …]` per §5.5), each over ~1.5s. The hub forms as the
    radials converge — a small dense knot of high-density `worley_fbm`
    noise, NOT concentric rings.
  - **Spiral (25–55s):** chord segments laid INWARD from the outer
    polygon to the hub free-zone boundary. Each chord reveals over
    ~0.3s and accumulates drops over time per §5.8 (drop count grows
    after the chord is laid; chords laid early have more drops by the
    end of the build than chords laid late).
  - **Settle (55–60s):** brief pause; ArachneState emits
    `presetCompletionEvent` via the V.7.6.2 channel; orchestrator
    advances to the next planned preset segment.

- 1–2 saturated background webs at depth (full drop count from preset
  entry; mild Gaussian blur applied by post-process; sag at the upper
  end of the kSag range so they read as more weathered). When the
  foreground build completes, the foreground migrates to the
  background pool over ~1s crossfade; old background fades out if the
  pool is at capacity.

- Build pace audio-modulated per §7. Continuous mid-band boost
  (`+0.18 × f.mid_att_rel` segments/second), drum-onset accent
  (`+0.5 × stems.drums_energy_dev` per-frame), base 1.0 segment/second
  at silence. Total build at average music ≈ 50–55s; at silence ≈ 75s
  (the orchestrator transitions before completion in that case).

- Per-segment spider cooldown: at most one spider appearance per
  Arachne segment. Combined with the §6.5 sustained-low-attack-ratio
  trigger this targets ~1 spider per 5–10 Arachne segments without an
  explicit timer. The V.7.5 300s session-level lock is dropped.

- Spider trigger pauses the build accumulators. While `spider.blend >
  0.01`, the frame / radial / spiral progress counters do not advance.
  When the spider fades, accumulators resume from where they paused —
  do not restart. The spider can appear at any phase (frame-only,
  early-radials, almost-complete spiral); whichever fraction was built
  is what the spider sits on.

The success criterion is **"the user watches the web draw itself
over ~1 minute, with drops accreting on the spiral as it winds inward,
the spider may appear and pause the build, and the orchestrator
transitions cleanly when the build completes"**. It is the single
largest structural change in the Arachne stream. It is **not** a cert
run — V.7.10 is the cert.

The risk to manage is, again, **scope creep**. V.7.7C.2 explicitly
keeps the §5.8 drop recipe (V.7.7C lock), the spider anatomy +
material (V.7.7D lock), the 12 Hz vibration (V.7.7D lock), and the
WORLD pillar (V.7.7B lock) all unchanged. What this increment touches
is the WEB pillar's STATE evolution and the spider trigger's COOLDOWN
scope. Do not retune the drop recipe; do not modify the spider SDF;
do not edit drawWorld(). If a tuning change feels needed, surface
before diverging.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

The increment has eight sub-items. Land in three commits:

- Commit 1: WORLD branch-anchor twigs (Sub-item 1 — small drawWorld
  extension that the WEB pillar reads from).
- Commit 2: ArachneState build state machine + background pool +
  spider integration (Sub-items 2–6, 8). The bulk of the increment.
- Commit 3: Shader-side state-machine plumbing + golden hashes +
  docs (Sub-item 7 + golden hash regeneration + DECISIONS / CLAUDE.md
  / RELEASE_NOTES_DEV / ENGINEERING_PLAN).

──── Sub-item 1: WORLD branch-anchor twigs (shared constants) ────

EDIT — `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal` (drawWorld function, ~line 142).

§5.9 mandates that frame anchors terminate on the WORLD's near-frame
branches. The current `drawWorld()` has 2 trunk silhouettes (left + right
edges of frame). Add 6 small twig anchor points at fixed UV positions
where the WEB pillar will attach the polygon:

```metal
// V.7.7C.2 §5.9: branchlet anchor points used by both WORLD (renders
// dark capsule SDFs at these positions) and the WEB pillar (frame
// polygon vertices terminate on these positions).
//
// Single source of truth — both pillars read this array. Positions
// chosen to give an irregular distribution near the screen edges,
// avoiding the corners (anchors deep in the corners read as forced).
constant float2 kBranchAnchors[6] = {
    float2(0.18, 0.22),  // upper-left
    float2(0.82, 0.18),  // upper-right (slightly higher)
    float2(0.92, 0.55),  // right-mid
    float2(0.78, 0.84),  // lower-right
    float2(0.20, 0.78),  // lower-left
    float2(0.10, 0.50)   // left-mid
};

// drawWorld additions — render small dark twigs at the anchor positions.
// Inside drawWorld, after the existing trunk silhouettes:
for (int i = 0; i < 6; i++) {
    float2 anchorUV = kBranchAnchors[i];
    // Twig orientation — points roughly inward (toward screen center)
    // so the silk threads attach along the twig's outer edge.
    float2 inward    = normalize(float2(0.5) - anchorUV);
    float2 twigEnd   = anchorUV + inward * 0.05;
    float2 perpToTwig = float2(-inward.y, inward.x);
    float  twigD     = length(uv - mix(anchorUV, twigEnd, saturate(dot(uv - anchorUV, inward) / 0.05)));
    twigD            = abs(dot(uv - anchorUV, perpToTwig));  // approximate distance to the line
    float  twigCov   = smoothstep(0.005, 0.001, twigD);
    twigCov         *= step(0.0, dot(uv - anchorUV, inward));
    twigCov         *= step(dot(uv - anchorUV, inward), 0.05);
    // Dark twig color, mood-tinted slightly warmer than the trunk silhouettes.
    float3 twigCol  = mix(atmDark, atmMid, 0.15) * 0.5;
    bgColor          = mix(bgColor, twigCol, twigCov * 0.8);
}
```

(The exact SDF here is approximate — refine until twigs read as small
dark line segments at the anchor positions; the visual goal is that
the polygon vertices in the WEB pillar's frame phase clearly terminate
ON the twig.)

EDIT — `PhospheneEngine/Sources/Presets/Arachnid/ArachneState.swift` (CPU side).

Mirror the constants Swift-side so the build state machine can reason
about them:

```swift
// V.7.7C.2 §5.9 — single source of truth for branch anchor positions.
// Both Arachne.metal's drawWorld() and ArachneState's frame polygon
// builder consume these. Coordinate space: UV [0..1].
public static let branchAnchors: [SIMD2<Float>] = [
    SIMD2(0.18, 0.22), SIMD2(0.82, 0.18), SIMD2(0.92, 0.55),
    SIMD2(0.78, 0.84), SIMD2(0.20, 0.78), SIMD2(0.10, 0.50)
]
```

The two arrays MUST stay in sync. Add a comment in both files
referencing the other. (For V.7.7C.2 this is acceptable as a
two-source-of-truth; a future increment can extract the constants
into a shared `.metal` header file imported by both contexts.)

──── Sub-item 2: ArachneState build state machine (foreground) ────

EDIT — `PhospheneEngine/Sources/Presets/Arachnid/ArachneState.swift`.

Replace the V.7.5 4-web pool with a single-foreground build. The
current `WebStage` enum already has the right phases (`frame → radial
→ spiral → stable → evicting`); what's missing is the per-phase
visual content driver.

**Build state model (CPU side):**

```swift
// V.7.7C.2 — build state for the single foreground web.
//
// All progress values are in [0, 1] within their respective phases.
// `pausedByspider: Bool` — when true (set whenever spider.blend >
// 0.01), the per-tick advance is skipped on all *Progress fields.
//
// The build advances on a *time* basis (seconds since segment start
// minus paused time), modulated by audio per §7. Beats are NOT used
// for stage advancement — V.7.5's beat-measured stage timing was
// admitted in §5.2 to be wrong; build pace must scale with audio
// energy, not metronome time.
private struct BuildState {
    // Frame phase — bridge first, then polygon edges.
    var frameProgress: Float = 0           // 0..1 over the frame phase
    var bridgeAnchors: (Int, Int) = (0, 1) // which two of the kBranchAnchors are bridge endpoints

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
}
```

**Per-tick advance.** In `_tick(features:stems:)`:

```swift
// 1. Update spider pause guard.
let spiderActive = spiderBlendField > 0.01  // the existing field
buildState.pausedBySpider = spiderActive

// 2. Compute per-frame time advance, audio-modulated.
let basePace: Float = 1.0                                     // segments/second at silence
let midBoost: Float = 0.18 * features.mid_att_rel
let drumAccent: Float = 0.5 * stems.drums_energy_dev
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
        presetCompletionEvent.send()
        buildState.completionEmitted = true
    }
case .evicting:
    advanceEvictingPhase(by: effectiveDt)
}
```

**Phase advance helpers** — each function does the work for that
phase. Approximate timing (at average music = pace ~ 1.4):

- `advanceFramePhase`: `stageElapsed` accumulates; bridge thread
  visible over 0–1s; remaining frame threads laid sequentially over
  1–3s. At 3s/pace, transition to `.radial`.
- `advanceRadialPhase`: each radial draws over `1.5s/pace`; advance
  `radialIndex` when `radialProgress` reaches 1; transition to
  `.spiral` when `radialIndex == radialCount`.
- `advanceSpiralPhase`: each chord draws over `0.3s/pace`; advance
  `spiralChordIndex` when `spiralChordProgress` reaches 1; transition
  to `.stable` when `spiralChordIndex == spiralChordsTotal`. As each
  chord is laid, append `spiralChordBirthTimes.append(stageElapsed)`.
- `advanceEvictingPhase`: opacity ramps to 0 over 1s during migration
  to background pool; cleared on completion.

**Reset on segment start.** When the preset is re-applied (orchestrator
transition into Arachne) or when a new track begins, reset BuildState
to defaults, pick a fresh `radialCount` and `spiralRevolutions` from
`rngSeed`, compute the polygon by selecting 4–7 of `branchAnchors`, and
compute `radialDrawOrder` per §5.5. `arachneState.reset()` is the
canonical entry point — it must be called when the preset is bound (in
`applyPreset` `case .staged:` branch in `VisualizerEngine+Presets.swift`).

**GPU contract option (decide in this sub-item):**

OPTION A: Extend `WebGPU` from 80 → 96 bytes — add a Row 5 carrying
`(stage, frameProgress, radialIndex+radialProgress packed, spiralChordIndex+
spiralChordProgress packed)`. The shader reads it directly per pixel.
Spider GPU stays 80 bytes (V.7.7D contract).

OPTION B: Keep `WebGPU` at 80 bytes; encode build progress into the
unused fields of Row 4 (currently `moodData.w` is reserved). The
shader interprets `moodData.w` as a packed build-phase float
(`stage_int * 1.0 + frameProgress`). Tradeoff: smaller surface area
for state, bit-packing is fragile, but no GPU-contract change.

OPTION C: Pure CPU-side state; the shader receives no build state and
renders the entire web (all phases drawn in full) at every frame. The
"draw itself over time" effect is implemented by having the CPU side
selectively NOT include incomplete phase content in the per-frame
GPU buffer (e.g., `radialCount = currentlyVisibleRadials`,
`spiralChordsCount = currentlyVisibleChords`). Tradeoff: no shader
changes; less flexibility for per-chord age (per-chord drop accretion
becomes harder to express).

**Recommendation: OPTION A.** Spider's stable 80 bytes was preserved
because the GPU contract reasoning was about cross-stage stability
(see V.7.7B's STOP CONDITION #3 lineage). For WebGPU, expansion is
fine — the shader reads it per pixel anyway, and the extra 16 bytes
times 4 web slots is 64 bytes of additional UMA buffer. The clean
expression of per-chord age requires an array of birth times that
naturally lives in CPU memory and is sampled by index in-shader.

If choosing OPTION A, document the pre-V.7.7C.2 size (80) and
post-V.7.7C.2 size (96) in CLAUDE.md GPU Contract / Buffer Binding
Layout. Update `WebGPU.zero` accordingly. The buffer allocation in
`ArachneState.init` (see `webBufSize` ~line 199) bumps from
`MemoryLayout<WebGPU>.size * maxWebs = 80 * 4 = 320` to `96 * 4 = 384`.

──── Sub-item 3: Frame polygon + bridge thread ────

CPU side: extend `BuildState` to compute the polygon at segment start
per §5.3 (irregular polygon, 4–7 anchors). Selection rule:

- Random subset of `branchAnchors` (4–7 indices) from `rngSeed`-seeded
  hash.
- Order around polygon centroid (angular order) — then `bridgeAnchors`
  is the pair with the largest angular gap (they bookend the polygon's
  long axis; the bridge thread will visually be the "first commitment").

Shader side (Arachne.metal `arachne_composite_fragment`): render frame
threads only when the build state's frame progress allows. Each thread
is rendered as a thin smooth-stepped line. During the frame phase, the
visible portion of each thread is `mix(0, totalThreads, frameProgress)`
threads visible (i.e., 0 → all threads as `frameProgress` advances
0 → 1).

The bridge thread should be visibly "drawn first" — it appears at
`frameProgress < 0.2` while the rest stays invisible.

──── Sub-item 4: Hub knot + radial draw-itself ────

CPU side: `radialDrawOrder` precomputed per §5.5 alternating-pair.

Shader side: replace V.7.5's `arachneEvalWeb` spoke-rendering with a
build-aware version. For each spoke index `i ∈ [0, radialCount)`, the
spoke is visible if `radialDrawOrder.indexOf(i) < radialIndex` (already
fully drawn) or partially visible if `radialDrawOrder.indexOf(i) ==
radialIndex` (currently drawing — visible from hub outward to
`radialProgress` of total length).

Hub: replace the V.7.5 dense-circle hub with a `worley_fbm` noise patch
threshold-clipped per §5.4. The hub is small (radius ~`hub_radius =
polygon_inscribed_radius * 0.05`) and reads as overlapping silk
strands, NOT concentric rings. The hub appears progressively as the
radials converge — its intensity scales with `radialIndex / radialCount`.

──── Sub-item 5: Capture spiral INWARD + per-chord drop accretion ────

CPU side: at spiral-phase entry, precompute:
- `spiralChordsTotal = revolutions * radialCount` (for n=8 revs and
  n=13 radials, ~104 chord segments).
- Each chord `k` connects radial `(k mod radialCount)` to radial
  `((k+1) mod radialCount)` at radius
  `outerRadius - (k / radialCount) * pitch` where
  `pitch = (outerRadius - innerRadius) / revolutions`.
- `spiralChordBirthTimes[k] = stageElapsed when chord k laid`.

Shader side: replace V.7.5's chord-segment SDF with a build-aware
version. For each chord index `k`, the chord is:
- Invisible if `k > spiralChordIndex`.
- Partially visible (along chord length) if `k == spiralChordIndex`,
  reveal alpha `spiralChordProgress`.
- Fully visible if `k < spiralChordIndex`.

Drop accretion per §5.8: each chord has a current drop count
`dropCount(k) = min(maxDropsPerChord, baseDrops + accretionRate *
(stageElapsed - spiralChordBirthTimes[k]))` where
`accretionRate = 0.5` drops/second/chord and `maxDropsPerChord =
chordLength * dropDensity` (dropDensity ≈ 1/(4*dropRadius) per §5.8).

The drop-rendering inside the chord uses the V.7.7C §5.8 recipe
verbatim. What changes: which drops are placed (count) and how widely
they're spaced. Chords laid early have full drop count by build end;
chords laid late have only partial.

──── Sub-item 6: Anchor blobs ────

§5.9: at each polygon vertex (anchor), render a small adhesive blob
where the frame thread terminates. Radius ≈ `dropRadius * 1.3`; color
matches nearby silk + slight warm tint; opaque (no refraction —
adhesive silk is opaque).

CPU side: `anchorBlobIntensities[i]` ramps from 0 → 1 over 0.5s as the
frame phase reaches anchor `i`. Blob is rendered when intensity ≥ 0.05.

Shader side: simple disc SDF at each `branchAnchors[anchorIndex]` UV;
mix into `webColor` with `intensity * blobMask`.

──── Sub-item 7: Background webs + migration ────

§5.12: 1–2 background webs, present from preset entry, fully built
(saturated drops; sag at upper end of kSag range; mild blur applied
by post-process or in-shader). They share the same SDF + drop recipe
as the foreground but with `stage = .stable` and full drop counts.

CPU side: `ArachneState` owns a small `backgroundWebs: [BackgroundWeb]`
array (1–2 entries). Each `BackgroundWeb` carries the same per-web
state as `BuildState` but with `stage = .stable` and full chord
counts. They do NOT advance — they're already finished.

Migration on completion: when the foreground's `BuildState` reaches
`.stable` and `presetCompletionEvent.send()` fires, kick off a 1s
crossfade where:
- Foreground's opacity ramps 1 → 0.4 (it joins the background pool).
- If background pool is at capacity (2), oldest background ramps 1 → 0
  over the same 1s and is removed at the end.
- After 1s, the foreground BuildState resets and a new build cycle
  begins (new polygon, new radials, new spiral).

This is what makes Arachne a *cyclical* preset rather than a
one-shot. The orchestrator may transition before the cycle restarts —
that's fine; cycle restart is "what happens if Arachne is the active
preset across the segment boundary."

──── Sub-item 8: Per-segment spider cooldown + build pause/resume ────

EDIT — `ArachneState+Spider.swift`.

§6.5: per-segment cooldown replaces V.7.5's 300s session lock. The
state machine's `BuildState.segmentStartTime` is the canonical
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

Build pause is already wired in Sub-item 2 (`pausedBySpider = (spiderBlend >
0.01)`). When spider fades and `pausedBySpider` returns to false, the
build accumulators advance from where they paused — no restart logic
needed because `effectiveDt = 0` while paused means no progress was
recorded.

──── Sub-item 9: PresetSignaling conformance + golden hashes ────

EDIT — `ArachneState.swift`.

```swift
import Combine

extension ArachneState: PresetSignaling {
    public var presetCompletionEvent: PassthroughSubject<Void, Never> {
        return _presetCompletionEvent
    }
}

// In ArachneState body, add:
private let _presetCompletionEvent = PassthroughSubject<Void, Never>()
```

The orchestrator subscription (`activePresetSignaling()` in
`VisualizerEngine+Presets.swift:350`) automatically picks up
`ArachneState` as conforming and connects the publisher; no app-layer
changes needed beyond confirming the wiring.

After implementation:

- `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift`
  — regenerate Arachne hashes via
  `UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine --filter test_printGoldenHashes`,
  copy the new value into `goldenPresetHashes`.
- `PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift`
  — regenerate via `test_printSpiderGoldenHash`. The spider test
  fixture forces `spider.blend = 1` at a specific position; with the
  new build state machine the spider is rendered ON the foreground
  web at that fixture position (which now has frame + partial radials
  + partial spiral + drops). Hash will diverge significantly; expect
  double-digit hamming distance.

The Arachne regression hash WILL diverge because the test fixture
renders mid-build content (the build state machine starts immediately
on first tick; the test fixture's `time = 5.0` means the build is
~7s in by the time the regression render happens, putting it deep
into the radial phase). Document the new values in the commit
message. Note this in the CLAUDE.md / `goldenPresetHashes` comment:
the regression test now captures a *mid-build* foreground composition,
not a steady-state.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT)
────────────────────────────────────────

- Do NOT modify the §5.8 drop refraction recipe. V.7.7C is the lock.
  Per-chord drop COUNT and per-chord AGE are V.7.7C.2 surface; per-pixel
  drop COLOR is not.
- Do NOT modify the spider 3D SDF, chitin material, listening pose
  CPU-side state machine, or 12 Hz vibration. V.7.7D is the lock.
- Do NOT modify the WORLD pillar's six-layer composition (sky band /
  distant trees / mid trees / forest floor / fog / light shafts / dust
  motes) beyond adding the §5.9 anchor twigs in Sub-item 1. The
  V.7.7B port is the lock for everything else.
- Do NOT introduce new render passes. V.7.7C.2 stays inside the
  existing WORLD + COMPOSITE staged scaffold (V.ENGINE.1 / V.7.7A / D-072).
- Do NOT add or modify visual references in `docs/VISUAL_REFERENCES/arachne/`.
  The 19-image set is final for V.7.10.
- Do NOT run the M7 contact-sheet review. V.7.10.
- Do NOT touch `applyPreset` `case .staged:` branch beyond confirming
  `arachneState.reset()` is called when the preset is bound. The
  bind path is otherwise unchanged from V.7.7B.
- Do NOT modify `ArachneSpiderGPU`. The 80-byte struct stays
  byte-for-byte identical (V.7.7D contract).
- Do NOT modify the Marschner-lite silk BRDF or restore V.7's
  fiber-material recipe. §5.10 demoted silk; V.7.7C.2 keeps silk
  thin-and-faint.
- Do NOT implement the Marschner-lite silk material or any §5.10
  silk polish. V.7.7C.2 stays at "silk = thin lines + axial highlight";
  any silk changes are V.7.10 polish scope.
- Do NOT modify the JSON sidecar's `passes`, `stages`, or
  `naturalCycleSeconds`. The `naturalCycleSeconds: 60` is already
  set per V.7.6.C; the build state machine respects that ceiling
  through the `presetCompletionEvent` channel.
- Do NOT replace `kBranchAnchors` in MSL with a Swift-buffer-driven
  array. The two-source-of-truth is acceptable for V.7.7C.2; a future
  increment can extract them.
- Do NOT widen `naturalCycleSeconds` beyond 60. The build pace is
  what's audio-modulated; the cycle ceiling stays at 60.
- Do NOT change the V.7.5 sustained-bass spider trigger conditions
  (`f.subBass_dev > 0.30`, `bassAttackRatio < 0.55`, ≥ 0.75s sustain).
  V.7.7C.2 only adds the per-segment cooldown gate ON TOP of those
  conditions.

────────────────────────────────────────
DESIGN GUARDRAILS (CLAUDE.md)
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
- **Drop accretion is the secondary visual hero.** Drops on
  just-laid chords are sparse; drops on early chords are saturated.
  When the user watches the build, the spiral visibly grows
  *denser* with drops over time. This is the §5.8-required visual
  signature of "early winding has time to accrete drops; recent
  winding doesn't yet." Implementation precision matters here:
  `accretionRate = 0.5` drops/second/chord and `maxDropsPerChord`
  capped by chord length give a visible difference between early
  and late chords by the time the build settles.
- **Spider trigger pause/resume must be rock solid.** When the
  spider appears mid-build (e.g., during the radials phase), the
  `radialIndex` and `radialProgress` freeze. When it fades, they
  resume from exactly where they were — NO restart, NO regression
  to the last-completed radial, NO advance during the spider's
  presence. Verify this with a test fixture that forces a spider
  trigger at a known build state and confirms the build state is
  byte-identical before and after the spider's presence (modulo
  spider blend ramp time).
- **D-026 audio compliance.** The build pace's continuous driver
  (`0.18 × mid_att_rel`) is ≥ 2× the per-frame accent
  (`0.5 × drums_energy_dev` peaks at ~0.05–0.07 per frame). Ratio
  ≈ 3.6× — well above the 2× rule. Drop accretion rate is constant
  (0.5/s) regardless of audio — that's intentional per §5.8 (drops
  accrete on a per-chord physical timer, not on audio).
- **CLAUDE.md What NOT To Do additions.** Add three lines:
  1. "Do not advance Arachne build stages in beats. Build pace is
     audio-modulated TIME (`dt * pace`, where pace responds to
     `mid_att_rel` and `drums_energy_dev`). V.7.5's beat-measured
     stage timing was admitted in §5.2 to be wrong. D-095."
  2. "Do not add the V.7.5 4-web pool back. The post-V.7.7C.2
     composition is ONE foreground build + 1–2 saturated
     background webs. Spawn/eviction logic was retired. D-095."
  3. "Do not call `arachneState.reset()` outside `applyPreset`'s
     `.staged` branch. The build state machine's segment start is
     the canonical reset point; ad-hoc resets break per-segment
     spider cooldown semantics. D-095."
- **Failed Approach #34 caution.** The chord-segment SDF in
  `arachneEvalWeb` (V.7.8 promotion) is the load-bearing geometry.
  V.7.7C.2 must not regress the SDF correctness — Failed Approach
  #34 was the `abs(fract−0.5)` SDF inversion bug. The spiral path
  must continue to use `min(fract, 1−fract)`. If you find yourself
  rewriting `arachneEvalWeb`, stop — V.7.7C.2 changes WHICH chords
  are visible (build progression) but not the chord SDF itself.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters.

1. **Build (engine)**: `swift build --package-path PhospheneEngine` —
   must succeed with zero warnings on touched files.

2. **`PresetLoaderCompileFailureTest` first**: this is the
   load-bearing gate that exposed the V.7.7C half-vector bug
   immediately. Run before regression to fail fast on shader compile
   errors:
   ```
   swift test --package-path PhospheneEngine --filter "PresetLoaderCompileFailureTest"
   ```
   Expect Arachne preset count == 14.

3. **Targeted suites**:
   ```
   swift test --package-path PhospheneEngine \
       --filter "StagedComposition|StagedPresetBufferBinding|PresetRegression|ArachneSpiderRender|ArachneState"
   ```
   Each suite must pass post-port. `PresetRegressionTests` will fail
   until the golden hash is regenerated; expect that step to be the
   iterative loop. `ArachneState` tests will fail; some V.7.5
   pool-behaviour tests are obsolete (4-web pool is gone) and must be
   updated or deleted; new build-state-machine unit tests should be
   added in `ArachneStateBuildTests.swift` (frame phase advances over
   ~3s, radial phase advances over ~21s, spiral phase advances over
   ~30s, completion event fires once at settle, build pauses while
   spider blend > 0.01).

4. **Visual harness — staged per-stage** (load-bearing for V.7.7C.2):
   ```
   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
       --filter "renderStagedPresetPerStage" 2>&1 | tee /tmp/v77c2_staged.log
   ```
   Inspect `/tmp/phosphene_visual/<ISO8601>/Arachne_*_composite.png`.
   The PNGs are SINGLE-FRAME captures, so they show one moment in the
   build cycle. Expected:
   - `silence`: build state at ~5s elapsed (test fixture time = 5.0)
     × `pace ≈ 1.0` (silence) → frame phase mostly complete, very
     early radials. Drops sparse. Forest backdrop visible.
   - `mid`: build state at ~5s × `pace ≈ 1.18` (mid-band continuous)
     → frame complete, ~2–3 radials drawn. Drops slightly more.
   - `beat`: build state at ~5s × `pace ≈ 1.5` (mid + drums) → frame
     complete, ~3–4 radials drawn. Drops similar.
   The point is: the regression captures a mid-build moment. Compare
   silence vs mid vs beat to confirm pace differences are visible.
   If silence has more radials than beat, the audio-modulated pace
   is wrong-signed; STOP and inspect.

5. **Manual smoke (LOAD-BEARING for this increment)**: launch the
   app, force Arachne via developer keybinding, observe a full
   ~50–55s build cycle on a music track. Confirm:
   - Bridge thread appears first; remaining frame threads follow.
   - Anchor blobs land at polygon vertices.
   - Hub forms as radials converge (small dense knot, not concentric
     rings).
   - Spiral winds INWARD, chord by chord, with drops accumulating
     over time on each chord.
   - Web reads as visibly *building itself* — the user can watch the
     progression, not just steady-state.
   - At ~55s, the build settles; orchestrator transitions to the
     next preset segment (verify in session.log:
     `LiveAdapter: presetCompletionEvent received` — or equivalent).
   - When the spider appears mid-build (force trigger by playing a
     bass-heavy passage), the build pauses. When the spider fades,
     the build resumes from exactly where it left off.

6. **Spider golden render** (verbose):
   ```
   UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine \
       --filter "test_printSpiderGoldenHash" 2>&1 | tail -10
   ```
   Print captures the new hash. Update `goldenSpiderForcedHash` in
   `ArachneSpiderRenderTests.swift` with the printed value.

7. **Full engine suite**: `swift test --package-path PhospheneEngine`
   — must remain green. Pre-existing flakes documented in CLAUDE.md
   trip independently of this increment.

8. **App suite**: `xcodebuild -scheme PhospheneApp -destination
   'platform=macOS' test 2>&1 | tail -5` — must end clean except for
   the documented `NetworkRecoveryCoordinator` flakes.

9. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml
   --quiet` on all touched files — zero violations on touched files.
   The `Arachne.metal` file-length gate is exempt per `SHADER_CRAFT.md
   §11.1`.

10. **Build cycle timing harness (recommended)**: add a unit test that
    drives `ArachneState.tick(features: midEnergyFV, stems: .zero)` for
    60 seconds of simulated time and asserts:
    - Frame phase completes by `stageElapsed ∈ [2.5, 3.5]`s.
    - Radial phase completes by `stageElapsed ∈ [22, 28]`s.
    - Spiral phase completes by `stageElapsed ∈ [50, 60]`s.
    - `presetCompletionEvent` fires exactly once.
    - Spider pause: ticking with `spider.blend = 1` halts all phase
      progress; resuming with `spider.blend = 0` advances exactly
      from the paused state.

────────────────────────────────────────
DOCUMENTATION OBLIGATIONS
────────────────────────────────────────

After verification passes:

1. **`docs/ENGINEERING_PLAN.md`** §Increment V.7.7C.2: add a new
   section with status ✅; carry-forward (V.7.10 cert).

2. **`docs/DECISIONS.md`** — append `D-095` documenting:
   - The decision to retire the V.7.5 4-web pool entirely; replace
     with single-foreground build + 1–2 saturated background.
   - The OPTION A / B / C choice for build state in `WebGPU` (or
     CPU-side). Document which was selected and the size delta on
     `WebGPU` if Option A.
   - The decision to use audio-modulated TIME (not beats) for stage
     advancement. Cite §5.2's "V.7.5's beat-measured stage timing was
     admitted to be wrong" diagnosis.
   - The decision to keep the §5.8 drop COLOR recipe (V.7.7C lock)
     while changing per-chord COUNT and AGE. Cite D-093 / V.7.7C.
   - The decision to keep `branchAnchors` as a two-source-of-truth
     constant (Swift + MSL). Cite the future-increment plan to extract
     into a shared header.
   - The per-segment spider cooldown vs the V.7.5 300s session lock.
     Cite §6.5.

3. **`docs/RELEASE_NOTES_DEV.md`** — append `[dev-YYYY-MM-DD-X]
   V.7.7C.2` entry summarising the build state machine refactor,
   background pool, anchor blobs, completion event, per-segment
   spider cooldown.

4. **`CLAUDE.md`**:
   - §Module Map: update `Arachne.metal` description from "V.7.7D" to
     "V.7.7C.2: single-foreground build state machine — frame polygon
     + bridge thread, alternating-pair radials drawn one at a time,
     INWARD chord-segment spiral with per-chord drop accretion, settle
     emits `presetCompletionEvent`. 1–2 saturated background webs at
     depth. Build paces with audio (mid_att_rel + drums_energy_dev).
     Spider trigger pauses build accumulators."
   - §Module Map: update `ArachneState.swift` description with the
     build state machine + per-segment cooldown.
   - §What NOT To Do: add the three rules from DESIGN GUARDRAILS.
   - §Recent landed work: append the V.7.7C.2 entry.
   - §Current Status carry-forward: mark V.7.7C.2 ✅; the next open
     increment is V.7.10 (Matt M7 cert review).

5. **`docs/QUALITY/KNOWN_ISSUES.md`**:
   - No new entries unless V.7.7C.2 surfaces a defect.

────────────────────────────────────────
COMMITS
────────────────────────────────────────

Three commits per Sub-item structure:

**Commit 1** — `[V.7.7C.2] Arachne: WORLD branch-anchor twigs (D-095)`
- `Arachne.metal` — `kBranchAnchors[6]` constant + drawWorld twig SDFs.
- `ArachneState.swift` — public `static let branchAnchors`.
- Tests for the constant + a regression harness verifying Swift /
  MSL arrays stay in sync (string-search the metal file for the
  expected float pairs).

**Commit 2** — `[V.7.7C.2] Arachne: build state machine + background pool + spider integration (D-095)`
- `ArachneState.swift` — `BuildState` struct, phase-advance helpers,
  `branchAnchors` polygon selection, alternating-pair radial order,
  spiral chord precompute, `pausedBySpider` integration, `reset()`
  semantics.
- `ArachneState+Spider.swift` — per-segment cooldown gate
  (`spiderFiredInSegment`), reset on segment start.
- `ArachneState+BackgroundWebs.swift` (new) — `BackgroundWeb` struct
  + 1–2 saturated background pool, migration on completion crossfade.
- `ArachneState+Signaling.swift` (new) — `PresetSignaling` conformance,
  `_presetCompletionEvent` private subject.
- `WebGPU` — Option A: extend to 96 bytes adding Row 5 build state.
- New unit tests in `ArachneStateBuildTests.swift` (≥ 8 tests covering
  the bullets in Verification §10).

**Commit 3** — `[V.7.7C.2] Arachne: shader build-aware rendering + golden hashes + docs (D-095)`
- `Arachne.metal` — build-aware spoke / chord / hub / anchor-blob
  rendering inside `arachne_composite_fragment`; `arachneEvalWeb`
  build-state inputs.
- `PresetRegressionTests.swift` — Arachne hash regenerated.
- `ArachneSpiderRenderTests.swift` — spider forced hash regenerated.
- All docs from §Documentation Obligations.

Local commits to `main` only. Do NOT push without explicit "yes,
push" approval. The visual change is the largest in the Arachne
stream (single-foreground build is the structural pivot the v8 design
exists for); pushing without manual smoke verification on real music
risks shipping a build state machine that test passes but feels
broken on actual playback.

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **Build never advances past frame phase**: the audio-modulated pace
  is `1.0 + 0.18 * mid_att_rel + drums_energy_dev`. At silence,
  `pace = 1.0` and `effectiveDt = dt`. So 60 seconds of silence should
  take 60 seconds. If the build stalls in frame phase, the issue is
  either (a) `effectiveDt` is being clamped to 0 by the spider pause
  (verify `pausedBySpider == false` when no spider is present), or
  (b) the phase transition condition is wrong-signed (verify
  `if stageElapsed >= 3.0 { transitionToRadial() }` not the inverse).
  STOP and inspect.

- **Spiral winds OUTWARD instead of INWARD**: the chord index is
  inverted. Verify chord `k` connects radial `(k mod n)` to
  `((k+1) mod n)` at radius `outerRadius - (k / n) * pitch`. If
  `outerRadius + (k / n) * pitch`, the spiral expands outward —
  the §5.6 anti-pattern. STOP and invert the radius progression.

- **Drops don't accrete visibly**: `accretionRate = 0.5` drops/second/chord
  is the spec value. By the end of the spiral phase (30s), each chord
  has had at most `30 * 0.5 = 15` extra drops added. Compared to
  `baseDrops` (initial count when chord is laid, e.g., 3), final count
  is ~18. If chord lengths support `maxDropsPerChord = 20`, drops
  should visibly increase along the spiral. If they don't, verify
  the per-chord drop rendering reads `dropCount(k)` not a fixed
  count.

- **Polygon comes out symmetric** (Failed Approach #48 territory —
  ref `09` anti-reference): the `branchAnchors` array has 6 positions
  with intentional irregularity; selecting any 4–7 of them should
  produce an irregular polygon. If the rng selection returns a
  symmetric subset (e.g., all 6 evenly spaced), perturb one by 15°
  per §5.3. Verify with the test fixture that the polygon is NEVER
  a regular hexagon.

- **Background webs dominate the foreground**: the foreground build
  is the visual hero; the background is context. If background webs
  read as "full" while foreground reads as "building," the visual
  hierarchy is correct. If background is brighter / more saturated
  than foreground, dim background to ~0.4–0.6 of foreground brightness
  (per §5.12 "older silk, dimmer").

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

- **GPU contract change breaks tests**: Option A extends `WebGPU`
  from 80 → 96 bytes. The `webBufSize` allocation in
  `ArachneState.init` (line ~199) bumps from 320 → 384. Tests that
  assert specific byte sizes (search for `MemoryLayout<WebGPU>.size`)
  must be updated. CLAUDE.md GPU Contract section must be updated
  too.

- **Build pause/resume desync**: while paused, `effectiveDt = 0` so
  no progress is recorded. On resume, the next tick advances by the
  normal `dt * pace`. If progress jumps on resume (e.g., the
  spider's blend ramp is included in elapsed time despite being
  paused), the issue is the pause guard order — pause MUST be
  checked BEFORE `effectiveDt` is computed, not after.

- **STOP and report instead of forging ahead** if:
  - The polygon selection logic produces fewer than 4 anchors or
    more than 7. The §5.3 spec is `4–7`; surface and tune the
    selection rng.
  - The spiral chord count exceeds 200 (degenerate case from very
    high `revolutions × radialCount`). Cap at 150 and tune the
    spec values.
  - Build cycle time at average music exceeds 65s (above the 60s
    ceiling — the orchestrator transitions, but the cycle should
    fit). Surface and inspect the audio-modulated pace.
  - `presetCompletionEvent` fires before `stageElapsed >= 50s` on
    the spiral phase. The completion firing too early would cause
    the orchestrator to transition prematurely.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md` §5 (THE WEB) — the
  full pillar. Most relevant: §5.1 (real construction biology), §5.2
  (60-second compressed cycle table), §5.3 (frame polygon), §5.4
  (hub knot — NOT concentric rings), §5.5 (radials, alternating-pair
  draw order), §5.6 (capture spiral chord-segment SDF, INWARD), §5.7
  (sag), §5.8 (drops + accretion), §5.9 (anchor terminations on
  near-frame branches), §5.10 (silk material — minor finishing),
  §5.11 (lighting interaction), §5.12 (background webs), §5.13
  (reference cross-walk).
- Architectural pivot record: `docs/DECISIONS.md` D-072 (compositing-
  anchored diagnosis), D-092 (V.7.7B port), D-093 (V.7.7C refractive
  dewdrops), D-094 (V.7.7D spider + vibration).
- V.7.6.2 channel: `PhospheneEngine/Sources/Orchestrator/PresetSignaling.swift`
  + `PhospheneApp/VisualizerEngine+Presets.swift:328` (subscription
  path — already wired, V.7.7C.2 plugs in by conforming).
- V.7.6.C `naturalCycleSeconds = 60` framework:
  `docs/presets/ARACHNE_V8_DESIGN.md` §9 (per-preset maxDuration framework),
  D-073 (V.7.6.C linger factors).
- Failed Approaches: `CLAUDE.md`
  #34 (chord-segment SDF correctness — V.7.7C.2 must not regress),
  #48 (§10.1-faithful but reference-divergent visual outputs —
       V.7.7C.2 must be cross-checked against ref `09` anti-symmetry
       and ref `01` polygon irregularity, NOT just "matches the §5
       prose").
- Reference recipes:
  - `Shaders/Utilities/Geometry/SDFPrimitives.metal` `sd_capsule_2d`
    + `sd_segment_2d` — the line-segment SDFs the build-aware spoke
    and chord rendering depend on.
  - `PhospheneEngine/Sources/Presets/Stalker/StalkerState.swift`
    — alternating-tetrapod gait + per-segment cooldown blueprint.
    The §5.5 alternating-pair radial order is structurally identical
    to Stalker's gait phase ordering.
  - `Arachne.metal` `arachneEvalWeb` (~line 265) — the chord-segment
    SDF that V.7.7C.2 makes build-aware.
- Visual references:
  - `docs/VISUAL_REFERENCES/arachne/01_macro_dewy_web_on_dark.jpg`
    — hero frame match; full polygon + radials + spiral + drops
    visible.
  - `docs/VISUAL_REFERENCES/arachne/02_meso_per_strand_sag.jpg`
    — sag reference (kSag range visible).
  - `docs/VISUAL_REFERENCES/arachne/03_micro_adhesive_droplet.jpg`
    — drop spacing (Plateau-Rayleigh, ±5%).
  - `docs/VISUAL_REFERENCES/arachne/11_anchor_web_in_branch_frame.jpg`
    — anchor polygon context; web visibly attaches to branch
    polygon (6 anchors in this ref).
  - `docs/VISUAL_REFERENCES/arachne/09_anti_clipart_symmetry.jpg`
    — anti-reference. Symmetric polygons → here.
- Forward chain (do NOT do here):
  - V.7.10 — Matt M7 contact-sheet review + cert. V.7.7C.2 is the
    last structural increment before cert; V.7.10 is the QA + sign-off
    pass. No further structural changes are planned post-V.7.7C.2.
- CLAUDE.md sections to read: §Increment Completion Protocol,
  §Defect Handling Protocol, §GPU Contract Details (WebGPU buffer
  layout), §Visual Quality Floor, §Failed Approaches, §What NOT
  To Do.
