Execute Commit 3 of Increment V.7.7C.2 — the closeout commit. The
shader-side build-aware rendering reads the WebGPU Row 5 build state
landed in Commit 2; golden hashes regenerate against the new
mid-build composition; D-095 is filed and all dependent docs land.
After this commit, V.7.7C.2 is **complete** and the Arachne 2D stream
moves to V.7.10 (Matt M7 cert review + sign-off). The 3D Arachne3D
parallel-preset path (D-096) is deferred per Matt's 2026-05-08
sequencing — simpler presets first, then return to V.8.x.

Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md` §5 (THE WEB). Most
relevant: §5.3 (frame polygon), §5.4 (hub knot — NOT concentric
rings), §5.5 (radials, alternating-pair draw order), §5.6 (capture
spiral chord-segment SDF, INWARD), §5.8 (drop recipe — V.7.7C lock,
per-chord drop COUNT and AGE are V.7.7C.2 surface), §5.9 (anchor
terminations on near-frame branches — Commit 1 + this commit's anchor
blob renderer), §5.12 (background webs + migration crossfade visual).

Architectural records: `docs/DECISIONS.md` D-072 (compositing-anchored
diagnosis, V.7.5 → V.7.7+), D-092 (V.7.7B port), D-093 (V.7.7C
refractive dewdrops — drop COLOR recipe lock), D-094 (V.7.7D 3D
spider + chitin + listening pose + 12 Hz vibration), D-095 (V.7.7C.2
— **filed in this commit**), D-096 (V.8.0-spec parallel-preset commit
— filed 2026-05-08, V.8.x deferred per Matt).

Commits to date in V.7.7C.2:
- **Commit 1** (`38d1bfab` 2026-05-08): WORLD branch-anchor twigs.
  `kBranchAnchors[6]` constant + Swift mirror.
- **Commit 2** (TBD title `[V.7.7C.2] Arachne: build state machine +
  background pool + spider integration (D-095)`): CPU-side
  `BuildState` + `BackgroundWeb` + per-segment spider cooldown +
  `PresetSignaling` conformance + WebGPU 80 → 96 byte expansion. NO
  shader changes beyond struct mirror.
- **Commit 3** (THIS COMMIT): shader build-aware rendering + golden
  hash regeneration + docs (D-095 entry + CLAUDE.md + RELEASE_NOTES_DEV
  + ENGINEERING_PLAN). Manual smoke on real music is load-bearing.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. Commits 1 + 2 of V.7.7C.2 have landed. Verify with:
   `git log --oneline | grep '\[V\.7\.7C\.2\]' | wc -l` — expect ≥ 2.
   The two commits in HEAD~1..HEAD (or HEAD~2..HEAD) should carry the
   V.7.7C.2 prefix. Latest should be the build-state-machine commit;
   `38d1bfab` should be the branch-anchor-twigs commit.

2. Engine builds clean post-Commit 2:
   `swift build --package-path PhospheneEngine 2>&1 | tail -5` —
   exit 0, zero warnings on touched files.

3. WebGPU stride is exactly 96 bytes (Commit 2 contract):
   `swift test --package-path PhospheneEngine --filter "ArachneStateBuildTests/test_webGPUStrideIs96Bytes"`
   — expect green. If 80 or 112+, Commit 2 is mis-landed; STOP and
   triage before proceeding with Commit 3.

4. PresetRegressionTests + ArachneSpiderRender goldens are still at
   V.7.7D values:
   `swift test --package-path PhospheneEngine --filter "PresetRegression|ArachneSpiderRender"`
   — expect green BEFORE Commit 3's shader changes. If they fail
   pre-shader, Commit 2's `ArachneWebGPU` Metal struct definition has
   corrupted byte offsets; STOP and triage.

5. `presetCompletionEvent` fires once over a 90 s simulated build
   cycle (Commit 2 contract):
   `swift test --package-path PhospheneEngine --filter "ArachneStateBuildTests/test_completionEventFiresExactlyOnce"`
   — expect green.

6. The CPU-side `BuildState` model is observable from the shader
   side via Row 5 reads: `WebGPU.buildStage` /
   `WebGPU.frameProgress` / `WebGPU.radialPacked` /
   `WebGPU.spiralPacked`. The Metal `ArachneWebGPU` struct has the
   same four trailing floats appended in the same order. Confirm:
   `grep -n 'buildStage\|frameProgress\|radialPacked\|spiralPacked' PhospheneEngine/Sources/Presets/Shaders/Arachne.metal | head -10`
   — expect 4+ hits in the struct definition.

7. `PresetSignaling` conformance is wired:
   `grep -nE 'extension ArachneState: PresetSignaling|_presetCompletionEvent' PhospheneEngine/Sources/Presets/Arachnid/ArachneState+Signaling.swift`
   — expect both hits. The orchestrator subscription
   (`activePresetSignaling()` in `VisualizerEngine+Presets.swift:328`)
   automatically picks up `ArachneState` as conforming; no app-layer
   changes needed.

8. Commits 1 + 2 deliverables match the original V.7.7C.2 scope.
   Spot-check `git log -p HEAD~1..HEAD -- 'PhospheneEngine/Sources/Presets/Arachnid/*.swift'`
   for: `BuildState`, `BackgroundWeb`, `spiderFiredInSegment`,
   `branchAnchors`, `radialDrawOrder`, `spiralChordBirthTimes`,
   `_presetCompletionEvent`. All present → Commit 2 fully landed.

9. `ArachneSpiderGPU` is 80 bytes (V.7.7D contract — V.7.7C.2 does
   NOT touch the spider GPU struct):
   `grep -A 6 'struct ArachneSpiderGPU' PhospheneEngine/Sources/Presets/Arachnid/ArachneState.swift | head -12`
   — expect `tip[8]` + 4 trailing fields, no expansion.

10. Decision-ID is **D-095** (V.7.7C.2). Verify with
    `grep '^## D-0' docs/DECISIONS.md | tail -3` — expect D-094 as
    the latest filed entry; D-095 NOT yet present (this commit files
    it). D-096 is the V.8.0-spec entry filed earlier today —
    pre-existing in the file, do NOT touch.

11. `git status` is clean except `prompts/*.md`, `default.profraw`,
    and `docs/presets/ARACHNE_3D_DESIGN.md`. Anything else surface and
    confirm before proceeding.

────────────────────────────────────────
GOAL
────────────────────────────────────────

After Commit 3 the dispatched Arachne preset is the **biology-correct
hero web** the v8 design has been working toward since D-072. The
user watching playback sees:

- A SINGLE foreground hero web that visibly **builds itself** over
  ~50–55 s of music. The bridge thread appears first, frame threads
  follow, anchor blobs land at polygon vertices, radials extend one
  at a time in alternating-pair order, the hub forms as a small
  dense knot of `worley_fbm` noise (NOT concentric rings), and the
  capture spiral winds **INWARD** chord by chord. Drops accrete on
  each chord over time per §5.8 — chords laid early have full drop
  count by the build's end; chords laid late have only partial.
- 1–2 saturated background webs at depth, fully built from preset
  entry. They sit behind the foreground build with mild blur and
  upper-end sag, providing depth context without competing with the
  hero.
- At ~55 s, the foreground reaches `.stable` and the migration
  crossfade fires: foreground opacity ramps 1 → 0.4 (joins the
  background pool), oldest background ramps 1 → 0 (evicts), then
  after 1 s the foreground BuildState resets and a new build cycle
  begins. `presetCompletionEvent` fires exactly once at settle —
  the orchestrator may transition to the next planned preset before
  the cycle restarts; that's the §9 maxDuration framework working
  as intended.
- Spider triggers on sustained low-attack-ratio bass (§6.5) at most
  once per Arachne segment and pauses the build accumulators while
  visible. When it fades, accumulators advance from exactly where
  they paused.

The success criterion for this commit is **"Matt watches the
foreground web draw itself over ~1 minute on a real music track,
drops visibly accrete on the spiral as it winds inward, the hub
reads as a small irregular knot (not concentric rings), the polygon
reads as irregular (not symmetric), and when the cycle completes the
orchestrator transitions cleanly without the visual stuttering or
restarting"**. Manual smoke is load-bearing — the regression
contact-sheet captures one mid-build moment but cannot demonstrate
"draws itself over time." Matt eyeballs that on real playback.

The risk to manage is **scope creep**. Commit 3 explicitly does NOT
modify:
- the §5.8 drop refraction COLOR recipe (V.7.7C lock — D-093). Only
  per-chord drop COUNT and per-chord AGE change.
- the spider 3D SDF, chitin material, listening pose, or 12 Hz
  vibration (V.7.7D lock — D-094).
- the WORLD pillar's six-layer composition (V.7.7B lock — D-092)
  beyond the §5.9 anchor twigs already added in Commit 1.
- `ArachneWebGPU` byte layout — it's already 96 bytes from Commit 2,
  Row 5 fields appended at the end. No further struct changes.
- `ArachneSpiderGPU` (V.7.7D contract — 80 bytes byte-for-byte
  identical).
- the app-layer bind path beyond confirming `arachneState.reset()`
  is called in `applyPreset` `case .staged:` for `desc.name ==
  "Arachne"`.
- visual references in `docs/VISUAL_REFERENCES/arachne/`.

If a tuning change feels needed, surface before diverging.

────────────────────────────────────────
SCOPE
────────────────────────────────────────

Files touched in this commit:

1. **`PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`** —
   `arachne_composite_fragment` and `arachneEvalWeb` modified to
   read Row 5 build state and progressively render frame threads,
   alternating-pair radials, hub knot fbm field, INWARD chord
   spiral with per-chord drop counts (the §5.8 COLOR recipe stays
   verbatim), anchor-blob discs at polygon vertices, and the
   background-web migration crossfade. The chord SDF stays
   `min(fract, 1−fract)` (Failed Approach #34 lock); only WHICH
   chords are visible / how many drops they have changes.

2. **`PhospheneEngine/Tests/PhospheneEngineTests/Renderer/PresetRegressionTests.swift`** —
   Arachne `steady` / `beatHeavy` / `quiet` golden hashes
   regenerated. Comment block updated to note the post-V.7.7C.2
   regression captures a *mid-build* foreground composition (not a
   steady-state). Hash divergence will be significant — expect
   double-digit hamming distance from V.7.7D values. **Spider
   forced hash also regenerates** (the spider sits on the partially-
   built foreground web at the test fixture's elapsed time;
   different web composition under the spider footprint shifts the
   hash bits).

3. **`PhospheneEngine/Tests/PhospheneEngineTests/Presets/ArachneSpiderRenderTests.swift`** —
   `goldenSpiderForcedHash` regenerated. Doc-comment extended.

4. **`docs/DECISIONS.md`** — append `## D-095 — V.7.7C.2: Arachne
   single-foreground build state machine + background pool +
   per-segment spider cooldown + PresetSignaling conformance +
   WebGPU Row 5 (filed 2026-05-09)` documenting all the architectural
   choices Commits 1+2+3 made together.

5. **`docs/RELEASE_NOTES_DEV.md`** — append a new
   `[dev-YYYY-MM-DD-X] V.7.7C.2 — Arachne single-foreground build
   state machine` entry.

6. **`docs/ENGINEERING_PLAN.md`** — Increment V.7.7C.2 section: flip
   to ✅ with closeout summary; carry-forward updated to V.7.10
   (Matt M7 cert review + sign-off). The §V.7.8 line item already in
   the plan is renamed / cross-referenced as "landed as V.7.7C.2"
   so future readers don't expect a separate V.7.8 increment.

7. **`CLAUDE.md`** — five sections updated:
   - **Module Map**: `Arachne.metal` description updated to
     V.7.7C.2 (single-foreground build state machine, frame polygon
     + bridge, alternating-pair radials, INWARD chord spiral,
     anchor blobs, background pool, migration crossfade); `ArachneState.swift`
     description updated similarly.
   - **GPU Contract Details / Buffer Binding Layout**: WebGPU
     documented as 96 bytes (post-V.7.7C.2), Row 5 fields listed.
     ArachneSpiderGPU stays at 80 bytes (V.7.7D contract).
   - **What NOT To Do**: 3 new rules from V.7.7C.2 design
     guardrails (audio-modulated TIME not beats; no V.7.5 4-web
     pool resurrection; `arachneState.reset()` only from
     `applyPreset` `.staged` branch).
   - **Recent landed work**: append a V.7.7C.2 entry summarising
     all three commits (twigs + state machine + shader rendering).
     Mark V.7.7C.2 ✅ in the next-ordered-increments list; flip
     V.7.10 to "the next open increment".
   - **Current Status**: confirm V.7.7C.2 ✅ closes the Arachne 2D
     stream's structural work; V.7.10 is the next increment;
     V.8.x (Arachne3D) deferred per Matt 2026-05-08.

NO new test files; NO new source files beyond the shader edits and
the doc updates.

────────────────────────────────────────
SUB-ITEM DETAILS — SHADER
────────────────────────────────────────

──── Sub-item 3 (shader): Frame polygon + bridge thread ────

EDIT — `PhospheneEngine/Sources/Presets/Shaders/Arachne.metal`,
inside `arachne_composite_fragment` (and/or `arachneEvalWeb`,
depending on where the existing frame-line geometry lives in
Commit 2's struct mirror).

Read Row 5 from `webs[0]`:

```metal
constant ArachneWebGPU& fgWeb = webs[0];
float buildStage     = fgWeb.buildStage;     // 0 = .frame, 1 = .radial, 2 = .spiral, 3 = .stable, 4 = .evicting
float frameProgress  = fgWeb.frameProgress;  // 0..1 within the frame phase
float radialPacked   = fgWeb.radialPacked;   // radialIndex + radialProgress
float spiralPacked   = fgWeb.spiralPacked;   // spiralChordIndex + spiralChordProgress
int   radialIndex    = int(floor(radialPacked));
float radialProgress = radialPacked - float(radialIndex);
int   spiralChordIdx = int(floor(spiralPacked));
float spiralChordProg= spiralPacked - float(spiralChordIdx);
```

Frame threads visibility:

- The CPU's `BuildState.anchors` (4–7 indices into `kBranchAnchors[6]`)
  is NOT directly visible in shader. Instead, the polygon edges are
  encoded implicitly: each thread's `(startUV, endUV)` pair must be
  reconstructable in shader. **Approach: at preset bind, the CPU
  writes per-edge endpoints into reserved buffer fields.** Since
  Commit 2 stayed at 96 bytes total, the polygon endpoints land in
  a separate constant buffer or are derived from the rngSeed — pick
  whichever Commit 2 actually shipped (verify by inspecting the
  `WebGPU` struct or by reading the CPU-side draw helpers Commit 2
  authored). If Commit 2 left no polygon-encoding affordance, the
  fallback is: shader recomputes the polygon from `webs[0].rngSeed`
  using the same selection / ordering algorithm as
  `ArachneState.computePolygon(...)`. Two-source-of-truth on the
  algorithm is acceptable for V.7.7C.2 (same precedent as
  `kBranchAnchors[6]` two-source-of-truth from Commit 1).

- For each polygon edge `e ∈ [0, edgeCount)`, render a thin line
  segment between the edge's two anchor positions when `buildStage
  >= 1.0` (frame fully done) OR `e < frameProgress * edgeCount`
  (partially drawn during the frame phase).
- The bridge thread is the polygon edge with the largest angular gap
  in the polygon ordering; render it FIRST (visible at
  `frameProgress >= 0.0` while other edges wait until
  `frameProgress >= edgeIndex / edgeCount`).
- The thread SDF is `sd_segment_2d(uv, startUV, endUV)`; rendered
  with thin smoothstep coverage `smoothstep(0.0014, 0.0010, dist)`
  matching the existing silk thread thickness.
- Silk material uses the existing thin-axial-highlight recipe (V.7.7C
  lock — `silkTint × 0.32` with the warm-rim Marschner TT lobe per
  V.7.5 §10.1). Do NOT introduce Marschner-lite — §5.10 demoted silk.

──── Sub-item 4 (shader): Hub knot + radial draw-itself ────

The hub is a small dense knot of `worley_fbm` noise threshold-clipped
per §5.4. **NOT concentric rings.** Replace the V.7.5 hub
`smoothstep(hub_radius_inner, hub_radius_outer, dist)` ring fill
with:

```metal
// §5.4 — hub knot. Small, dense, irregular. The radials terminate
// inside the knot (no visible converge point).
float2 hubUV       = float2(fgWeb.hubX, fgWeb.hubY);
float  hubR        = polygonInscribedRadius * 0.05; // small relative to web
float  hubField    = worley_fbm(uv * 80.0 + hubUV * 8.0); // dense pattern
float  hubMask     = smoothstep(hubR, hubR * 0.6, length(uv - hubUV));
// Ramp hub intensity with radial draw progress — hub forms as radials converge.
float  hubIntensity = clamp(float(radialIndex) / float(radialCount), 0.0, 1.0);
float  hubCov      = hubMask * step(0.55, hubField) * hubIntensity;
silkColor          = mix(silkColor, kLightCol * 0.45, hubCov);
```

Tune `worley_fbm` scale and `step(0.55, ...)` threshold so the hub
reads as 4–8 overlapping silk-thread blobs at maximum intensity, NOT
a smooth disc and NOT concentric rings (§5.4 anti-pattern explicitly
called out in the spec).

Radials. For each `i ∈ [0, radialCount)`, compute the spoke's
position in the alternating-pair draw order via either (a) reading
`webs[0].radialDrawOrder` from a side buffer, OR (b) recomputing it
in shader (deterministic given `radialCount`, since the algorithm is
`[0, n/2, 1, n/2+1, …]`). Approach (b) is simpler — the algorithm
is small and the result is deterministic per `radialCount`.

```metal
// Recompute alternating-pair index in shader (matches CPU's
// computeAlternatingPairOrder exactly).
int alternatingPairIndex(int i, int radialCount) {
    int half = radialCount / 2;
    if (i < 2 * half) {
        int pair  = i / 2;
        int isOdd = i & 1;
        return pair + isOdd * half;
    }
    return radialCount - 1; // odd-radialCount tail
}

// For spoke i in the polygon-ordered radial list, find its draw-order index.
// (Inverse of alternatingPairIndex: which draw-order step draws spoke i?)
// Linear scan over j ∈ [0, radialCount): if alternatingPairIndex(j, radialCount) == i, drawOrderIdx = j.
```

Each spoke has three visibility states:

- `drawOrderIdx < radialIndex`: fully drawn, render full length from
  hub to polygon edge.
- `drawOrderIdx == radialIndex`: currently drawing, render visible
  fraction `radialProgress` along the spoke (from hub outward).
- `drawOrderIdx > radialIndex`: invisible.

```metal
int drawOrderIdx = computeDrawOrderIdxForSpoke(i, radialCount);
float spokeReveal;
if (drawOrderIdx < radialIndex) {
    spokeReveal = 1.0;
} else if (drawOrderIdx == radialIndex) {
    spokeReveal = radialProgress;
} else {
    spokeReveal = 0.0;
}

if (spokeReveal > 0.0) {
    float2 spokeStart = hubUV;
    float2 spokeEnd   = mix(hubUV, polygonEdgePointForSpoke(i), spokeReveal);
    float  spokeDist  = sd_segment_2d(uv, spokeStart, spokeEnd);
    // ... render with existing silk thickness + tint
}
```

In the `.spiral` and `.stable` stages (`buildStage >= 2.0`), all
spokes are fully visible. The early-stage logic only applies during
`.frame` and `.radial`.

──── Sub-item 5 (shader): Capture spiral INWARD + per-chord drop accretion ────

**THE LOAD-BEARING SHADER CHANGE.** The chord-segment SDF stays
`min(fract, 1−fract)` (Failed Approach #34 lock). What changes is
WHICH chords are visible and HOW MANY drops are placed on each.

The CPU's `BuildState.spiralChordsTotal` and `spiralChordBirthTimes[]`
encode the spiral's progression. **The shader must read these.** Two
options:

OPTION A: Pack into a side buffer at slot 6 / 7 (the per-preset
fragment buffer reservation). Commit 2 may or may not have done
this; verify by inspecting `ArachneState.flushToGPU(...)` for
side-buffer writes.

OPTION B: Recompute in shader. `spiralChordsTotal = revolutions ×
radialCount` is deterministic per rngSeed. Per-chord birth times,
however, depend on elapsed time and audio-modulated pace — these
CANNOT be recomputed deterministically in shader. The CPU must
write them.

**Choose Option A.** Commit 2's prompt explicitly mentioned per-chord
birth times living in CPU memory and being sampled by index in
shader. If Commit 2 didn't ship the side buffer, Commit 3 adds it:

```swift
// CPU side, in ArachneState.flushToGPU(...).
// Side buffer: one Float per chord = the chord's age in seconds.
// chordAgeBuffer[k] = max(0, currentStageElapsed - spiralChordBirthTimes[k]).
// Bound at fragment buffer(8) — slot 6 is webBuffer, slot 7 is spiderBuffer.
// (Or whichever slot is free per CLAUDE.md GPU Contract.)
```

If extending the buffer slot allocation, update CLAUDE.md GPU
Contract accordingly. Slot 8 is unused as of V.7.7D and is the
natural next slot.

In the shader:

```metal
// Read chord age. spiralChordBirthAges[k] is set by CPU each frame.
float chordAge = spiralChordBirthAges[k];

// §5.8 drop accretion.
const float baseDrops      = 3.0;
const float accretionRate  = 0.5; // drops/sec/chord — constant per §5.8
float maxDropsForChord     = chordLength(k) * dropDensity; // chordLength derived per chord
float dropCount            = clamp(baseDrops + accretionRate * chordAge,
                                   baseDrops, maxDropsForChord);
int   intDropCount         = int(floor(dropCount));
```

Per-chord visibility:

- `k < spiralChordIdx`: chord fully visible; full `dropCount` drops
  placed.
- `k == spiralChordIdx`: chord partially visible (length-fraction =
  `spiralChordProg`); drops placed only along the visible portion.
- `k > spiralChordIdx`: chord invisible; no drops.

Drop positions along each chord follow the existing V.7.7C placement
rule (Plateau-Rayleigh spacing, ±5% jitter via per-chord hash). The
**§5.8 COLOR recipe (Snell's-law refraction sampling `worldTex`,
fresnel rim, specular pinpoint, dark edge ring, audio gain
`(baseEmissionGain + beatAccent)`)** is **byte-identical** to V.7.7C.
Do NOT modify any color math inside the drop block.

Visual signature: by build's end, chord 0 has `30 × 0.5 = 15` extra
drops on top of `baseDrops = 3` → ~18 drops; chord ~100 (final)
has `0.3 × 0.5 = 0.15` extra → still ~3 drops. The user watching
the build sees the spiral get visibly *denser* with drops over time,
inner chords (early) more saturated than outer chords (late).

Spiral chord radius progression — verify INWARD:

```metal
float pitch       = (outerRadius - innerRadius) / spiralRevolutions;
float chordRadius = outerRadius - (float(k) / float(radialCount)) * pitch;
//                                ^^^ MINUS, not PLUS — INWARD per §5.6
```

A `+` here is the §5.6 anti-pattern (spiral expands outward). The
CPU's chord index walks `0 → spiralChordsTotal-1`; chord 0 is the
outermost chord, the final chord is closest to the hub.

──── Sub-item 6 (shader): Anchor blobs ────

§5.9: at each polygon vertex, render a small adhesive blob where
the frame thread terminates. The CPU's
`BuildState.anchorBlobIntensities[i]` ramps 0 → 1 over 0.5 s as the
frame phase reaches anchor `i`. Read these intensities from the
shader (side buffer at slot 9, or pack into rngSeed-derived
positions and ramp in shader from `frameProgress` directly).

```metal
// For each polygon vertex (anchor), small disc at vertex UV.
const float blobRadius = dropRadius * 1.3;
for (int a = 0; a < polygonAnchorCount; a++) {
    float2 anchorUV = kBranchAnchors[anchors[a]]; // CPU writes anchors[] to a buffer
    float  intensity = anchorBlobIntensities[a];
    if (intensity < 0.05) continue;
    float  blobDist = length(uv - anchorUV);
    float  blobCov  = smoothstep(blobRadius, blobRadius * 0.6, blobDist);
    // Adhesive silk — opaque, no refraction. Slight warm tint over silk base.
    float3 blobCol  = silkBaseColor + kLightCol * 0.15;
    silkColor       = mix(silkColor, blobCol, blobCov * intensity);
}
```

The blob is NOT a refractive drop — adhesive silk is opaque. Don't
apply the §5.8 Snell's-law block here.

──── Sub-item 7 (shader): Background webs + migration crossfade visual ────

§5.12: 1–2 background webs at depth, fully built. Their `WebGPU` Row
5 is trivially `{buildStage: 3.0, frameProgress: 1.0,
radialPacked: float(radialCount), spiralPacked: float(spiralChordsTotal)}`.
The shader's existing build-aware logic above already renders them
at full visibility because all the gates resolve to "fully drawn".

What the shader DOES need from background webs:

- Saturated drops from the start (Commit 2's `BackgroundWeb` struct
  sets `chordAge = maxAge` so drop count is at maximum).
- Mild blur applied per-pixel in the `arachneEvalWeb` walk: weight
  the contribution by `0.65–0.75` so background reads as slightly
  out-of-focus / dimmer than foreground (per §5.12 "older silk,
  dimmer").
- Sag at upper end of `kSag` range (Commit 2 stores per-web sag
  multipliers; reuse them).

Migration crossfade visual: Commit 2's `BackgroundWeb.opacity` field
tracks the crossfade. Read it in shader:

```metal
constant ArachneWebGPU& bgWeb = webs[1]; // or webs[2]
float bgOpacity = bgWeb.opacity; // 0..1, ramps 1→0 during eviction
silkColor       = mix(silkColor, evaluateWeb(uv, bgWeb), bgOpacity);
```

The crossfade math is in Commit 2; the shader just reads opacity.
No new state needed beyond what Row 5 + the existing rows carry.

──── Sub-item shader-helpers: alternating-pair index inverse ────

The radial draw-order computation in Sub-item 4 needs an inverse —
"given spoke i in polygon order, what step in the draw order draws
it?". One approach is the loop-and-search:

```metal
int spokeDrawStep(int spokeIdx, int radialCount) {
    // Linear scan — radialCount is small (12-17), so cost is bounded.
    for (int j = 0; j < radialCount; j++) {
        if (alternatingPairIndex(j, radialCount) == spokeIdx) return j;
    }
    return radialCount; // unreachable for valid inputs
}
```

For `radialCount = 13`, this is at most 13 iterations per spoke per
pixel — well within budget. A closed-form inverse exists too (case
on whether `i < radialCount/2 * 2` and even/odd) but the loop is
simpler and indistinguishable in profiling.

────────────────────────────────────────
SUB-ITEM DETAILS — DOCS
────────────────────────────────────────

──── D-095 entry in DECISIONS.md ────

Append after D-094 (line ~2462) and before D-096 (or wherever the
existing D-096 entry sits — verify). The entry covers:

```markdown
## D-095 — V.7.7C.2: Arachne single-foreground build state machine + background pool + per-segment spider cooldown + PresetSignaling conformance + WebGPU Row 5 (filed 2026-05-09)

**Decision.** Replace the V.7.5 4-web pool with a single-foreground
build state machine implementing the corrected orb-weaver biology
per `ARACHNE_V8_DESIGN.md` §5: frame polygon (4–7 of 6 branch
anchors) → bridge thread first then remaining frame edges → hub knot
forming as radials converge (worley_fbm, NOT concentric rings) →
12–17 radials drawn one at a time in alternating-pair order
(§5.5 [0, n/2, 1, n/2+1, …]) → INWARD chord-segment capture spiral
(§5.6 chord radius DECREASES with k) with per-chord drop accretion
(§5.8 baseDrops=3, accretionRate=0.5/sec/chord, chordAge tracked in
CPU memory, drop count grows over time) → settle. Add 1–2 saturated
background webs at depth (§5.12 — full drop count, upper-sag, mild
blur) with migration crossfade on completion (foreground 1→0.4 joins
pool; oldest background 1→0 evicts; 1 s ramp; new build cycle
starts). Replace V.7.5's 300 s session-level spider cooldown with
per-segment cooldown (§6.5 — at most one spider per Arachne
segment); spider trigger pauses build accumulators while visible,
resumes from paused state on fade. ArachneState conforms to
PresetSignaling and emits `presetCompletionEvent` once at settle.
WebGPU struct extended 80 → 96 bytes (Row 5: buildStage,
frameProgress, radialPacked, spiralPacked); ArachneSpiderGPU stays
at 80 bytes (V.7.7D contract).

**Why now.** V.7.7B/C/D delivered the WORLD pillar, refractive
dewdrops, and 3D spider — but the WEB pillar's BUILD behaviour was
still V.7.5's 4-web pool with beat-measured stage timing, which
§5.2 explicitly admitted to be wrong. The build progression is the
visual signature the v8 design is built around (D-072): "the user
watches a single web draw itself over ~1 minute." Without the
build state machine, V.7.10 cert review against refs `01` / `11` is
impossible because those refs show finished webs in physical
contexts that imply construction history. V.7.7C.2 makes the build
visible.

**Decisions inside D-095.**

1. **Single foreground hero, 1–2 saturated background. The V.7.5
   4-web pool is retired.** Per-web spawn/eviction logic is replaced
   by the build state machine (foreground) + a fixed 1–2 background
   slot pool with migration crossfade. The composition reads as
   "one web being built, in a depth context of finished webs," not
   as "many webs of varying ages."

2. **Audio-modulated TIME pacing, not beats.** §5.2's V.7.5
   beat-measured timing produced inconsistent build cadence on
   tracks with sparse vs dense beats. V.7.7C.2 uses
   `pace = 1.0 + 0.18 × f.midAttRel + max(0, 0.5 × stems.drumsEnergyDev)`.
   At silence pace = 1.0 → 60 s cycle (matches `naturalCycleSeconds`
   ceiling); at average music pace ≈ 1.4 → ~43 s. D-026 ratio
   (continuous 0.18 × midAttRel typical 0.18 vs accent 0.5 ×
   drumsEnergyDev typical 0.05) ≈ 3.6× — well above the 2× rule.

3. **Per-segment spider cooldown.** Replaces V.7.5's 300 s session
   lock with `spiderFiredInSegment: Bool` reset on
   `BuildState.reset()`. The orchestrator's segment boundary is the
   canonical reset point. At ~1 spider per 5–10 Arachne segments in
   practice (the sustained-bass condition is naturally rare) — no
   explicit timer needed beyond the cooldown gate.

4. **Build pause/resume on spider.** While `spider.blend > 0.01`,
   `effectiveDt = 0` and all build accumulators freeze. On fade,
   accumulators resume from exactly where they paused — no restart,
   no regression, no advance during the spider's presence. The
   pause guard is checked BEFORE `effectiveDt` is computed (not
   after) so spider blend ramp time does not bleed into the build
   timeline.

5. **`presetCompletionEvent` fires once via PresetSignaling.**
   `ArachneState: PresetSignaling` extension exposes the
   PassthroughSubject. `BuildState.completionEmitted: Bool` guards
   against double-fire across ticks; reset only by
   `arachneState.reset()`. The orchestrator subscription in
   `VisualizerEngine+Presets.swift:328` picks it up automatically
   via the existing `activePresetSignaling()` lookup; no app-layer
   wiring change needed.

6. **WebGPU 80 → 96 bytes (Sub-item 2 OPTION A).** New Row 5 of 4
   individual `Float` fields (NOT `SIMD4<Float>` — that would
   16-byte-align and push stride past 96) carrying `buildStage`,
   `frameProgress`, `radialPacked` (radialIndex + radialProgress),
   `spiralPacked` (spiralChordIndex + spiralChordProgress). Buffer
   allocation `webBufSize` auto-scales via `MemoryLayout<WebGPU>.stride`.
   Existing rows 0–4 byte offsets preserved — pre-V.7.7C.2 shader
   reads of those rows are byte-identical post-expansion.

7. **`branchAnchors` stays as two-source-of-truth (Swift + MSL).**
   Constants in both `ArachneState.branchAnchors` (Swift) and
   `kBranchAnchors[6]` (Metal); they MUST stay in sync. Future
   increment can extract into a shared `.metal` header, but for
   V.7.7C.2 the dual-source is acceptable and matches the precedent
   from Commit 1.

8. **§5.8 drop COLOR recipe is V.7.7C lock; per-chord drop COUNT and
   per-chord AGE are V.7.7C.2 surface.** Drop refraction sampling
   `worldTex`, fresnel rim, specular pinpoint, dark edge ring,
   audio gain `(baseEmissionGain + beatAccent)` — all
   byte-identical to V.7.7C. What changes: which chords have how
   many drops, derived from `chordAge`.

9. **§5.4 hub knot reads as worley_fbm threshold-clipped, NOT
   concentric rings.** V.7.5's hub `smoothstep(hub_radius_inner,
   hub_radius_outer, dist)` ring fill replaced. The §5.4 spec
   explicitly calls concentric rings as the anti-pattern.

10. **Failed Approach #34 lock preserved.** The chord-segment SDF
    stays `min(fract, 1−fract)`. V.7.7C.2 changes WHICH chords are
    visible (build progression) and HOW MANY drops they have, NOT
    the chord SDF itself.

**The hard scope decisions.**

- **D-094 V.7.7D contract preserved.** `ArachneSpiderGPU` stays at
  80 bytes; listening-pose state stays CPU-side; chitin material
  recipe inlined per §6.2 (NOT `mat_chitin` cookbook); 12 Hz
  vibration on COMPOSITE only.
- **D-093 V.7.7C contract preserved.** §5.8 drop refraction COLOR
  recipe byte-identical at both call sites; `mat_frosted_glass`
  retired from foreground drops (V.7.7C lock).
- **D-092 V.7.7B contract preserved.** WORLD pillar's six-layer
  composition unchanged; only Commit 1's anchor twigs added per
  §5.9.
- **`naturalCycleSeconds: 60` framework lock.** The orchestrator's
  per-section maxDuration scaling (D-073 / V.7.6.C) is unchanged.
  V.7.7C.2 builds the actual visible build cycle the framework
  was sized for.

**Files changed (V.7.7C.2 scope across all three commits).**

- Commit 1 (`38d1bfab`): `Arachne.metal` (kBranchAnchors[6] + drawWorld
  twig SDFs); `ArachneState.swift` (public static branchAnchors);
  new `ArachneBranchAnchorsTests.swift` (regression: arrays in sync).
- Commit 2: `ArachneState.swift` (BuildState struct, phase-advance
  helpers, polygon selection, alternating-pair radial order, spiral
  chord precompute, pausedBySpider integration, reset() semantics,
  WebGPU Row 5); `ArachneState+Spider.swift` (per-segment cooldown
  gate); new `ArachneState+BackgroundWebs.swift` (BackgroundWeb +
  pool + migration); new `ArachneState+Signaling.swift`
  (PresetSignaling conformance, `_presetCompletionEvent`); new
  `ArachneStateBuildTests.swift` (≥ 8 tests).
- Commit 3 (this commit): `Arachne.metal` (build-aware
  `arachne_composite_fragment` + `arachneEvalWeb`); golden hash
  regeneration in `PresetRegressionTests.swift` +
  `ArachneSpiderRenderTests.swift`; this D-095 entry; CLAUDE.md;
  RELEASE_NOTES_DEV.md; ENGINEERING_PLAN.md.

**Test count delta.** Across all three commits: +N tests
(`ArachneBranchAnchors` Commit 1, `ArachneStateBuild` ≥ 8 Commit 2,
no new tests Commit 3 — only golden hash regen). Engine 1152 →
~1160+. Suite green modulo documented pre-existing flakes.
SwiftLint zero violations on touched files.

**Carry-forward.** V.7.10 — Matt M7 contact-sheet review + cert
sign-off. V.7.7C.2 is the last structural increment before cert;
V.7.10 is the QA + sign-off pass. No further structural changes
planned post-V.7.7C.2 in the 2D Arachne stream. V.8.x (Arachne3D
parallel preset path per D-096) is deferred per Matt's 2026-05-08
sequencing call — return to V.8.1 after building simpler presets
to validate the cert pipeline.
```

──── RELEASE_NOTES_DEV.md entry ────

Append at the top of the file (after the header) per the existing
pattern:

```markdown
## [dev-YYYY-MM-DD-X] V.7.7C.2 — Arachne single-foreground build state machine

**Increment:** V.7.7C.2. **Decision:** D-095. Three commits.

**What changed.**

- **Commit 1 — WORLD branch-anchor twigs (`Arachne.metal`,
  `ArachneState.swift`):** [reproduce key bullet points from D-095
  Commit 1 scope, ≤ 4 sentences]
- **Commit 2 — CPU build state machine + background pool + spider
  integration (`ArachneState.swift`, `ArachneState+Spider.swift`,
  new `ArachneState+BackgroundWebs.swift`, new `ArachneState+Signaling.swift`):**
  [≤ 8 sentences covering BuildState, polygon selection,
  alternating-pair radials, spiral chord precompute, per-chord birth
  times, spider pause/resume, per-segment cooldown, PresetSignaling,
  WebGPU 80→96]
- **Commit 3 — shader build-aware rendering + docs (`Arachne.metal`,
  `PresetRegressionTests.swift`, `ArachneSpiderRenderTests.swift`,
  doc updates):** [≤ 8 sentences covering Row 5 reads, frame thread
  visibility, hub knot worley_fbm, alternating-pair radial draw,
  INWARD chord spiral with per-chord drop counts, anchor blobs,
  background-web crossfade, golden hashes regenerated to mid-build
  composition]
- **Tests.** [Commit 2's ≥ 8 ArachneStateBuild tests; Commit 1's
  ArachneBranchAnchors regression. Commit 3 adds no new tests; only
  regenerates goldens.]
- **Golden hashes.** Arachne `steady` / `beatHeavy` / `quiet` all
  regenerated (mid-build composition diverges significantly from
  V.7.7D values; expect double-digit hamming distance). Spider
  forced hash regenerated (spider sits on partially-built foreground
  web; web composition under spider footprint shifts hash bits).
  Document the new values inline.

**Carry-forward.** V.7.10 — Matt M7 contact-sheet review + cert
sign-off. V.8.x (Arachne3D parallel preset, D-096) deferred per Matt
2026-05-08 sequencing.
```

Replace `YYYY-MM-DD` with the actual date of Commit 3. The `-X`
suffix is `a` if first dev entry of the day, `b` if second, etc.

──── ENGINEERING_PLAN.md V.7.7C.2 closeout ────

Find the V.7.7C.2 line item (probably at "Carry-forward" of V.7.7D
+ in the V.7.7 / V.7.8 / V.7.9 backlog block). If V.7.7C.2 has its
own section, flip status to ✅ with a closeout summary mirroring
V.7.7D's closeout (commit hashes, what changed, golden hashes, test
delta, carry-forward). If V.7.7C.2 is only mentioned in V.7.7D's
"Carry-forward" line, ADD a new full section in the same format as
V.7.7D's section, placed immediately after V.7.7D's section.

Also: V.7.8 and V.7.9 line items (currently listed as outstanding
in the backlog) are **subsumed by V.7.7C.2**. Update those line
items to "[Subsumed by V.7.7C.2 — see V.7.7C.2 section above]" with
no further detail. The original V.7.8 (foreground build refactor)
and V.7.9 (spider deepening + vibration + cert) plans are obsolete
post-V.7.7C/D + V.7.7C.2; future readers should land on V.7.10 (cert).

──── CLAUDE.md updates ────

**Module Map** — `Arachne.metal` description: replace V.7.7D
description with the V.7.7C.2 update:

```
Shaders/Arachne.metal → V.7.7C.2: single-foreground biology-correct
build state machine. Frame polygon (4–7 of 6 branch anchors) →
bridge thread first → alternating-pair radials (§5.5 [0, n/2, 1,
n/2+1, …]) drawn one at a time → hub knot (worley_fbm threshold-
clipped, §5.4 NOT concentric rings) forming as radials converge →
INWARD capture spiral (§5.6 chord radius DECREASES with k) with
per-chord drop accretion (§5.8 baseDrops=3, accretionRate=0.5/sec/
chord, chordAge from CPU, drop count grows over time) → settle.
Anchor blobs (§5.9, opaque adhesive silk discs at polygon vertices,
ramps 0→1 over 0.5 s as the frame phase reaches each anchor). 1–2
saturated background webs at depth (§5.12, full drop count,
upper-sag, mild blur, 0.65–0.75 weight). Migration crossfade on
completion (foreground 1→0.4 joins pool; oldest background 1→0
evicts; 1 s ramp). 3D SDF spider (V.7.7D §6.2 chitin recipe inlined,
biological-strength thin × 0.15) renders in 0.15 UV patch around the
spider's UV anchor when triggered. §8.2 vibration UV jitter on
COMPOSITE web walks + spider body translation (12 Hz, bass_att_rel
driven, 8×8 phase quantization, FA #33 compliant). WORLD pillar
(V.7.7B six-layer + Commit 1's branchlet anchor twigs) intentionally
still — vibration is COMPOSITE-only. ArachneWebGPU 96 bytes (Row 5:
buildStage / frameProgress / radialPacked / spiralPacked).
ArachneSpiderGPU 80 bytes (V.7.7D contract). D-019/D-026/D-040/
D-041/D-072/D-092/D-093/D-094/D-095 compliant.
```

**Module Map** — `ArachneState.swift` description: replace with the
V.7.7C.2 update covering BuildState, BackgroundWeb pool,
PresetSignaling, per-segment spider cooldown, audio-modulated TIME
pacing.

**GPU Contract Details / Buffer Binding Layout**: update the
`ArachneWebGPU` size from 80 to 96 bytes; document Row 5 fields. If
Commit 3 added a side buffer at slot 8 / 9 for `chordAgeBuffer` /
`anchorBlobIntensities`, document those slot reservations under
the per-preset fragment buffer table.

**What NOT To Do** — three new rules from V.7.7C.2 design
guardrails:

```
- Do not advance Arachne build stages in beats. Build pace is
  audio-modulated TIME (`dt × pace`, where pace responds to
  `mid_att_rel` and `drums_energy_dev`). V.7.5's beat-measured
  stage timing was admitted in `ARACHNE_V8_DESIGN.md` §5.2 to be
  wrong (inconsistent build cadence across tracks). D-095.
- Do not add the V.7.5 4-web pool back. The post-V.7.7C.2
  composition is ONE foreground build + 1–2 saturated background
  webs. Spawn / eviction logic was retired. If you find yourself
  adding `transientWebs: [WebGPU]`, stop — that's V.7.5 thinking.
  D-095.
- Do not call `arachneState.reset()` outside `applyPreset`'s
  `.staged` branch. The build state machine's segment start is the
  canonical reset point; ad-hoc resets break per-segment spider
  cooldown semantics (`spiderFiredInSegment` would clear at the
  wrong time). D-095.
```

**Recent landed work** — append a V.7.7C.2 entry summarising the
three commits.

**Current Status** — flip V.7.7C.2 to ✅ in the next-ordered-
increments list; flip V.7.10 (Matt M7 cert review + sign-off) to
"the next open Arachne increment". Note that V.8.x (Arachne3D
parallel preset, D-096) is deferred per Matt 2026-05-08 — simpler
presets first. The Arachne 2D stream is structurally complete after
V.7.7C.2; V.7.10 is QA + sign-off only.

────────────────────────────────────────
NON-GOALS (DO NOT IMPLEMENT IN THIS COMMIT)
────────────────────────────────────────

- **Tuning the §5.8 drop COLOR recipe.** V.7.7C lock — D-093.
  Per-chord drop COUNT and per-chord AGE are V.7.7C.2 surface;
  per-pixel drop COLOR is not.
- **Modifying the spider 3D SDF, chitin material, listening-pose CPU
  state machine, or 12 Hz vibration.** V.7.7D lock — D-094.
- **Modifying WORLD pillar's six-layer composition.** V.7.7B lock —
  D-092 (plus Commit 1's anchor twigs).
- **Introducing new render passes.** V.7.7C.2 stays inside the
  existing WORLD + COMPOSITE staged scaffold (V.ENGINE.1 / V.7.7A /
  D-072).
- **Adding or modifying visual references** in
  `docs/VISUAL_REFERENCES/arachne/`. The 19-image set is final for
  V.7.10.
- **Running the M7 contact-sheet review.** V.7.10.
- **Modifying `applyPreset` `case .staged:` branch beyond confirming
  `arachneState.reset()` is called.** The bind path is otherwise
  unchanged from V.7.7B.
- **Modifying `ArachneSpiderGPU`.** 80 bytes byte-for-byte identical.
- **Restoring V.7's fiber-material recipe / Marschner-lite silk.**
  §5.10 demoted silk; V.7.7C.2 keeps silk thin-and-faint.
- **Modifying JSON sidecar `passes`, `stages`, or `naturalCycleSeconds`.**
  `naturalCycleSeconds: 60` is set per V.7.6.C; the build state
  machine respects that ceiling through `presetCompletionEvent`.
- **Replacing `kBranchAnchors` in MSL with a Swift-buffer-driven
  array.** Two-source-of-truth is acceptable for V.7.7C.2.
- **Widening `naturalCycleSeconds` beyond 60.** Build pace is what's
  audio-modulated; the cycle ceiling stays at 60.
- **Changing V.7.5 sustained-bass spider trigger conditions.**
  V.7.7C.2 only adds the per-segment cooldown gate ON TOP.
- **Adding new tests beyond golden hash regeneration.** Commit 2's
  ArachneStateBuildTests cover the CPU state machine; the shader
  changes are visually verified via the harness contact sheet +
  Matt manual smoke. No new unit tests in Commit 3.
- **Backporting V.8.x (Arachne3D) features.** D-096 is deferred.
  Do NOT add `Arachne3D.metal`, `Arachne3D.json`, or any 3D-PBR
  scaffold work into Commit 3.

────────────────────────────────────────
DESIGN GUARDRAILS
────────────────────────────────────────

- **The chord-segment SDF stays `min(fract, 1−fract)`.** Failed
  Approach #34 lock. V.7.7C.2 changes WHICH chords are visible and
  HOW MANY drops they have, NOT the chord SDF itself.
- **The §5.8 drop COLOR recipe is byte-identical to V.7.7C.** Don't
  retune Snell's-law eta, fresnel rim, specular pinpoint cap, or
  dark edge ring. Per-chord COUNT (drives placement density) and
  per-chord AGE (drives placement count) are the only V.7.7C.2
  variables touching drops.
- **Hub reads as a small irregular knot (4–8 worley_fbm blobs at
  threshold ≥ 0.55), NOT concentric rings.** §5.4 explicitly calls
  concentric rings as the anti-pattern; V.7.5's
  `smoothstep(hub_radius_inner, hub_radius_outer, dist)` ring fill
  is retired.
- **Polygon reads as irregular (Failed Approach #48 lock).** Commit
  2's polygon selection rejects the 6-evenly-spaced subset; if
  shader-side polygon reconstruction is used (recommended over a
  side buffer for simplicity), the same selection algorithm runs in
  shader.
- **The spiral winds INWARD (§5.6 lock).** Chord radius DECREASES
  with k. Verify by walking `spiralChordIdx 0 → spiralChordsTotal-1`
  in shader and confirming chord 0's radius > chord 1's radius >
  ... > final chord's radius. A `+` sign on the radius progression
  is the §5.6 anti-pattern.
- **Shader file length.** `Arachne.metal` will grow significantly
  with the build-aware rendering. SwiftLint `file_length: 400` is
  relaxed for `.metal` files (`SHADER_CRAFT.md §11.1`); the file
  may end up 1100+ lines. Do NOT split into multiple .metal files
  for length compliance — the load order matters and splitting
  breaks the single-fragment dispatch.
- **`PresetLoaderCompileFailureTest` first** — Failed Approach #44
  is the silent-shader-compile-drop guard. Run the test
  immediately after each shader edit batch. Preset count must stay
  at 14 (V.7.7C.2 does NOT add a new preset).
- **D-026 audio compliance.** The build pace's continuous driver
  (`0.18 × mid_att_rel`) is ≥ 2× the per-frame accent
  (`0.5 × drums_energy_dev` peaks at ~0.05–0.07 per frame). Ratio
  ≈ 3.6× — preserved from Commit 2; Commit 3 doesn't touch pace
  formula.

────────────────────────────────────────
VERIFICATION
────────────────────────────────────────

Order matters.

1. **Build (engine)**: `swift build --package-path PhospheneEngine`
   — must succeed with zero warnings on touched files.

2. **`PresetLoaderCompileFailureTest` first**: this is the
   load-bearing gate that exposed the V.7.7C half-vector bug
   immediately. Run before regression to fail fast on shader
   compile errors:
   ```
   swift test --package-path PhospheneEngine --filter "PresetLoaderCompileFailureTest"
   ```
   Expect Arachne preset count == 14.

3. **Targeted suites** — pre-golden-regen:
   ```
   swift test --package-path PhospheneEngine \
       --filter "StagedComposition|StagedPresetBufferBinding|ArachneState|ArachneStateBuild|ArachneListeningPose|ArachneBranchAnchors"
   ```
   All must pass. PresetRegression + ArachneSpiderRender will FAIL
   here (shader changes hit the goldens) — that's expected and
   addressed in step 5.

4. **Visual harness — staged per-stage** (load-bearing for
   V.7.7C.2):
   ```
   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
       --filter "renderStagedPresetPerStage" 2>&1 | tee /tmp/v77c2_c3_staged.log
   ```
   Inspect `/tmp/phosphene_visual/<ISO8601>/Arachne_*_composite.png`.
   Compare against Commit 2's harness output (or against
   V.7.7D's harness output if Commit 2 didn't add a contact sheet).
   Expected differences:
   - `silence` fixture: build state at ~5 s × `pace ≈ 1.0` → frame
     phase mostly complete, very early radials. Drops sparse.
     Forest backdrop visible. Silk reads as polygon partially
     drawn + a few radials extending outward.
   - `mid` fixture: build state at ~5 s × `pace ≈ 1.18` → frame
     complete, ~2–3 radials drawn. Drops slightly more.
   - `beat` fixture: build state at ~5 s × `pace ≈ 1.5` → frame
     complete, ~3–4 radials drawn. Drops similar.
   The point is: the regression captures a **mid-build** moment
   (NOT steady-state). Compare silence vs mid vs beat to confirm
   pace differences are visible.

   **STOP CONDITIONS:**
   - If `silence` shows MORE radials than `beat`, the audio-
     modulated pace is wrong-signed. STOP and inspect.
   - If hub reads as concentric rings (V.7.5 anti-pattern), the
     `worley_fbm` threshold-clip is wrong; verify `step(0.55, ...)`
     not `smoothstep(...)`.
   - If polygon reads as a regular hexagon (ref `09` anti-pattern),
     polygon selection is broken; surface and inspect.
   - If spiral winds OUTWARD (chord 0 closest to hub instead of at
     polygon edge), chord radius progression is `+` instead of `-`.
     STOP and invert.

5. **Golden hash regeneration**:
   ```
   UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine \
       --filter "PresetRegressionTests/test_printGoldenHashes" 2>&1 | tail -20
   UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine \
       --filter "ArachneSpiderRenderTests/test_printSpiderGoldenHash" 2>&1 | tail -10
   ```
   Capture printed hashes; update `goldenPresetHashes` (Arachne
   `steady` / `beatHeavy` / `quiet`) in `PresetRegressionTests.swift`
   and `goldenSpiderForcedHash` in `ArachneSpiderRenderTests.swift`.
   Expected hamming distance from V.7.7D values: **double-digit**
   (significant divergence due to mid-build composition vs V.7.7D's
   steady-state composition). Document the new hashes in the commit
   message.

6. **Targeted suites — post-golden-regen**:
   ```
   swift test --package-path PhospheneEngine \
       --filter "PresetRegression|ArachneSpiderRender"
   ```
   Both must now pass at the new golden values.

7. **Manual smoke (LOAD-BEARING for this increment)**: launch the
   app, force Arachne via developer keybinding (`⌘[` / `⌘]`),
   observe a full ~50–55 s build cycle on a music track. Confirm:
   - Bridge thread appears first; remaining frame threads follow
     within ~2–3 s.
   - Anchor blobs land at polygon vertices (visible as small bright
     discs at the polygon's branchlet attachment points).
   - Hub forms as a small dense knot (irregular, 4–8 overlapping
     blobs, NOT concentric rings) as radials converge.
   - Radials extend **one at a time** in alternating-pair order
     (visually: spoke 0 first, then spoke n/2 across, then spoke 1,
     then spoke n/2+1, …). This is the §5.5 signature; very
     distinctive when you watch for it.
   - Spiral winds **INWARD**, chord by chord, with drops
     accumulating over time on each chord (early chords visibly
     denser with drops than late chords by build's end).
   - Web reads as visibly **building itself** — the user can watch
     the progression, not just steady-state.
   - At ~55 s, the build settles; orchestrator transitions to the
     next preset segment OR (if Arachne is the only segment in the
     plan) the build cycle restarts after a 1 s migration crossfade
     (foreground fades to background pool, oldest background
     evicts).
   - Verify in `session.log`: `LiveAdapter: presetCompletionEvent
     received` (or equivalent — the channel may surface differently).
   - When the spider appears mid-build (force trigger by playing a
     bass-heavy passage, e.g. James Blake — Atmosphere), the build
     pauses. When the spider fades, the build resumes from exactly
     where it left off.

   **MATT'S SIGN-OFF GATE.** This is V.7.7C.2's "the build draws
   itself, the user watches it happen" success criterion. If any
   of the above is missing or feels broken (e.g., hub stutters, or
   the polygon redraws on each tick instead of progressively
   building), STOP and surface before commit.

8. **Spider golden render** (if step 5 missed it): see step 5
   above; the spider hash regen is part of step 5.

9. **Full engine suite**: `swift test --package-path PhospheneEngine
   2>&1 | tail -10` — must remain green except documented
   pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout`,
   `MemoryReporter.residentBytes` env-dependent, parallel-load
   timing on `SessionManagerTests`).

10. **App suite**: `xcodebuild -scheme PhospheneApp -destination
    'platform=macOS' test 2>&1 | tail -5` — must end clean except
    for the documented `NetworkRecoveryCoordinator` flakes.

11. **SwiftLint**: `swiftlint lint --strict --config .swiftlint.yml
    --quiet` on all touched files — zero violations on touched files.
    `Arachne.metal` file-length gate is exempt per
    `SHADER_CRAFT.md §11.1`.

12. **`git status` + `git diff --stat`** before commit: confirm only
    the seven files in §SCOPE are modified. Anything else surface
    and back out before committing.

────────────────────────────────────────
COMMIT
────────────────────────────────────────

One commit. Do NOT push without explicit "yes, push" approval.
The visual change is the **largest** in the Arachne stream
(single-foreground build is the structural pivot the v8 design
exists for); pushing without manual smoke verification on real
music risks shipping a build state machine that test-passes but
feels broken on actual playback.

```
[V.7.7C.2] Arachne: shader build-aware rendering + golden hashes + docs (D-095)

Commit 3 of 3 — V.7.7C.2 closeout. Shader-side build-aware
rendering reads the WebGPU Row 5 build state landed in Commit 2;
arachne_composite_fragment + arachneEvalWeb progressively render
frame threads, alternating-pair radials, hub knot worley_fbm field,
INWARD chord spiral with per-chord drop accretion, anchor-blob
discs, and the background-web migration crossfade. Golden hashes
regenerated against the new mid-build composition. D-095 filed.
CLAUDE.md / RELEASE_NOTES_DEV / ENGINEERING_PLAN updated.

After this commit, V.7.7C.2 is complete. Carry-forward: V.7.10
(Matt M7 cert review + sign-off). V.8.x (Arachne3D parallel preset,
D-096) deferred per Matt 2026-05-08.

Shader-side build-aware rendering (Arachne.metal):
- Frame threads: each polygon edge renders as a thin sd_segment_2d
  with visibility ramp keyed to frameProgress and edge index. Bridge
  thread (largest angular gap) appears first.
- Hub: replaces V.7.5's smoothstep ring fill with worley_fbm
  threshold-clipped at step(0.55, ...) — small irregular knot of
  4–8 overlapping silk-thread blobs (§5.4 NOT concentric rings).
  Hub intensity ramps with radialIndex/radialCount.
- Radials: each spoke i visible based on its draw-order index
  (alternating-pair). Spokes with drawOrderIdx < radialIndex fully
  drawn; drawOrderIdx == radialIndex partially drawn from hub
  outward to radialProgress; drawOrderIdx > radialIndex invisible.
- Spiral chords: each chord k INWARD (radius DECREASES with k);
  visibility based on spiralChordIdx + spiralChordProg. Per-chord
  drop count via §5.8 accretion: dropCount(k) = baseDrops +
  accretionRate × chordAge[k] (chordAge from CPU side buffer).
  §5.8 COLOR recipe byte-identical to V.7.7C (Snell's-law eta,
  fresnel rim, specular pinpoint, dark edge ring, audio gain).
- Anchor blobs: at each polygon vertex, opaque adhesive disc
  (NOT refractive); intensity ramps via anchorBlobIntensities[a].
- Background webs: 1–2 entries at full build state; opacity reads
  from BackgroundWeb.opacity (CPU manages crossfade); rendered
  with 0.65–0.75 weight for depth context.
- Failed Approach #34 lock preserved: chord-segment SDF stays
  min(fract, 1−fract).

Golden hashes (PresetRegressionTests + ArachneSpiderRenderTests):
- Arachne `steady`: 0xV.7.7D-value → 0xNEW-VALUE (mid-build
  composition; hamming distance N from V.7.7D).
- Arachne `beatHeavy`: 0xV.7.7D-value → 0xNEW-VALUE.
- Arachne `quiet`: 0xV.7.7D-value → 0xNEW-VALUE.
- Spider forced: 0x461E2E1F07830C00 → 0xNEW-VALUE (spider sits on
  partially-built foreground web; web composition under spider
  footprint shifts hash bits).

Docs:
- D-095 filed in DECISIONS.md (~80 lines, all V.7.7C.2 architectural
  decisions across Commits 1+2+3).
- RELEASE_NOTES_DEV.md: new `[dev-YYYY-MM-DD-X] V.7.7C.2` entry
  summarising the three-commit increment.
- ENGINEERING_PLAN.md: V.7.7C.2 ✅ closeout. V.7.8 + V.7.9 line
  items marked subsumed.
- CLAUDE.md Module Map / GPU Contract / What NOT To Do (3 new
  rules) / Recent landed work / Current Status (V.7.7C.2 ✅,
  V.7.10 = next, V.8.x deferred).

Verification:
- N targeted tests / 8+ suites green (PresetLoaderCompileFailure +
  ArachneBranchAnchors + ArachneState + ArachneStateBuild +
  ArachneListeningPose + ArachneSpiderRender + PresetRegression +
  StagedComposition + StagedPresetBufferBinding).
- Visual harness contact sheet shows mid-build foreground web
  across silence/mid/beat fixtures with visibly different build
  pace per fixture.
- Manual smoke on real music: full build cycle visible, hub knot
  reads as irregular (NOT concentric rings), polygon irregular,
  spiral inward, drops accrete over time, spider trigger pauses
  + resumes cleanly.
- Engine + app builds clean. 0 SwiftLint violations on touched
  files.

Carry-forward: V.7.10 (Matt M7 contact-sheet review + cert
sign-off; Arachne 2D stream's structural work complete after
V.7.7C.2).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

────────────────────────────────────────
RISKS & STOP CONDITIONS
────────────────────────────────────────

- **PresetRegressionTests still fails after golden regen**: the new
  hashes might not have been pasted in correctly (off-by-one row,
  wrong fixture). Re-run step 5 with verbose output and compare the
  printed hash to what's in `goldenPresetHashes` literally — case,
  digits, suffix — should match exactly.

- **Visual harness output looks identical to V.7.7D**: the shader
  isn't reading Row 5. Verify the `webs[0].buildStage` / etc. reads
  are present at the top of `arachne_composite_fragment` and
  visibility gates use those values. If the gates are
  unconditionally `1.0` because the shader compiled without the
  reads, `PresetLoaderCompileFailureTest` should have caught it —
  but if Row 5 fields are silently zero (CPU not flushing), that's
  a Commit 2 bug; surface and triage.

- **Hub renders as concentric rings**: the `step(0.55, worley_fbm(...))`
  threshold-clip got reverted to a `smoothstep(...)`. Inspect and
  fix.

- **Polygon renders as a regular hexagon**: Commit 2's polygon
  selection rejects the 6-evenly-spaced subset; if shader-side
  polygon reconstruction is used, the same rejection logic must run
  in shader. Inspect the shader-side polygon-select and confirm the
  6-evenly-spaced subset is perturbed by 15° per §5.3.

- **Spiral winds OUTWARD**: chord radius progression is `+` instead
  of `-`. STOP and invert.

- **Drops don't visibly accrete**: `chordAge` is being read as 0
  for all chords. The CPU's `chordAgeBuffer` is either not flushed
  or bound at the wrong fragment buffer slot. Verify the slot
  matches between `flushToGPU()` (CPU) and the shader's `[[buffer(N)]]`
  declaration.

- **Anchor blobs missing**: the polygon vertices are wrong (e.g.,
  shader uses `kBranchAnchors` directly instead of the selected
  subset for this build cycle). Verify the shader reads the chosen
  anchor indices from `anchors[]` (CPU side buffer) or recomputes
  the polygon selection deterministically.

- **Migration crossfade flickers / loops**: the foreground's
  `BuildState.completionEmitted` flag is being reset incorrectly.
  Verify it's reset only by `arachneState.reset()` on cycle
  restart, not on every tick. Also verify the crossfade timer in
  `BackgroundWeb.opacity` ramps monotonically.

- **`presetCompletionEvent` doesn't fire**: the shader change broke
  the CPU side because the test was relying on CPU-only behaviour
  pre-Commit 3. Verify the engine test suite's
  `test_completionEventFiresExactlyOnce` still passes; if it fails,
  the regression is in the CPU side and is a Commit 2 bug — STOP
  and surface.

- **Manual smoke shows the build "jumping" instead of progressively
  drawing**: the Row 5 fields are being read with stale values
  (e.g., shader reads at frame N but CPU flushed at frame N-2).
  Verify the CPU `flushToGPU()` is called every frame, before the
  encode pass. Also verify the shader doesn't have stale uniform
  reads from a previous frame's bind.

- **STOP and report instead of forging ahead** if:
  - Manual smoke shows the build jumping / stuttering / restarting
    without provocation.
  - Hub reads as concentric rings even after threshold-clip fix.
  - Polygon comes out symmetric on multiple rngSeeds (Failed
    Approach #48 / ref 09 anti-pattern).
  - `presetCompletionEvent` fires before `stageElapsed >= 50 s` on
    the spiral phase.
  - Golden hash hamming distance is < 5 (suggests the shader didn't
    actually change behaviour) or > 30 (suggests something
    structural broke beyond the build-aware rendering).
  - Engine build emits warnings on touched files.
  - SwiftLint surfaces new violations on touched files.

────────────────────────────────────────
REFERENCES
────────────────────────────────────────

- Authoritative spec: `docs/presets/ARACHNE_V8_DESIGN.md` §5 (THE WEB) — the
  full pillar. Most relevant: §5.3 (frame polygon), §5.4 (hub knot
  — NOT concentric rings), §5.5 (radials, alternating-pair draw
  order), §5.6 (capture spiral chord-segment SDF, INWARD), §5.8
  (drops + accretion), §5.9 (anchor terminations), §5.12 (background
  webs).
- Architectural records: `docs/DECISIONS.md` D-072 (compositing-
  anchored diagnosis), D-092 (V.7.7B port), D-093 (V.7.7C
  refractive dewdrops — drop COLOR recipe lock), D-094 (V.7.7D
  spider + vibration), D-095 (V.7.7C.2 — filed in this commit),
  D-096 (V.8.0-spec parallel-preset commit — V.8.x deferred).
- V.7.6.2 channel: `PhospheneEngine/Sources/Orchestrator/PresetSignaling.swift`
  + `PhospheneApp/VisualizerEngine+Presets.swift:328`.
- V.7.6.C `naturalCycleSeconds = 60` framework:
  `docs/presets/ARACHNE_V8_DESIGN.md` §9 (per-preset maxDuration framework),
  D-073 (V.7.6.C linger factors).
- Reference recipes:
  - `Shaders/Utilities/Geometry/SDFPrimitives.metal` `sd_capsule_2d`
    + `sd_segment_2d` — the line-segment SDFs the build-aware spoke
    + frame-thread + chord rendering depend on.
  - `Shaders/Utilities/Noise/Worley.metal` `worley_fbm` — the hub
    knot's noise field source.
  - `Arachne.metal` `arachneEvalWeb` (~line 265 pre-Commit 3) — the
    chord-segment SDF that V.7.7C.2 makes build-aware.
  - `PhospheneEngine/Sources/Presets/Stalker/StalkerState.swift` —
    alternating-tetrapod gait + per-segment cooldown blueprint.
- Visual references:
  - `docs/VISUAL_REFERENCES/arachne/01_macro_dewy_web_on_dark.jpg`
    — hero frame match; full polygon + radials + spiral + drops.
  - `docs/VISUAL_REFERENCES/arachne/02_meso_per_strand_sag.jpg`
    — sag reference.
  - `docs/VISUAL_REFERENCES/arachne/03_micro_adhesive_droplet.jpg`
    — drop spacing.
  - `docs/VISUAL_REFERENCES/arachne/11_anchor_web_in_branch_frame.jpg`
    — anchor polygon context.
  - `docs/VISUAL_REFERENCES/arachne/09_anti_clipart_symmetry.jpg`
    — anti-reference (symmetric polygons).
  - `docs/VISUAL_REFERENCES/arachne/10_anti_neon_stylized_glow.jpg`
    — anti-reference (chitin neon glow).
- Failed Approaches: `CLAUDE.md`
  - #34 (chord-segment SDF correctness — V.7.7C.2 must not regress).
  - #44 (Metal built-in type names as variable names — silent
    compilation drop, gated by `PresetLoaderCompileFailureTest`).
  - #48 (§10.1-faithful but reference-divergent — ref 09
    anti-symmetry polygon irregularity required).
- CLAUDE.md sections to read: §Increment Completion Protocol,
  §Defect Handling Protocol, §GPU Contract Details, §Visual Quality
  Floor, §Failed Approaches, §What NOT To Do, §Audio Data Hierarchy.

────────────────────────────────────────
FORWARD CHAIN (do NOT do here)
────────────────────────────────────────

- **V.7.10 — Matt M7 contact-sheet review + cert.** V.7.7C.2 is the
  last structural increment before cert; V.7.10 is the QA + sign-off
  pass. The Arachne 2D stream's structural work is complete after
  Commit 3.
- **V.8.x (Arachne3D parallel preset, D-096) — deferred** per Matt's
  2026-05-08 sequencing call. Simpler presets first, then return to
  V.8.1. Do NOT touch `Arachne3D.metal` / `Arachne3D.json` scaffold
  in this commit — they don't exist yet and aren't in scope.
- **Future increment: extract `kBranchAnchors` + `branchAnchors`
  into a shared `.metal` header.** Two-source-of-truth is acceptable
  for V.7.7C.2 but is technical debt. Schedule alongside any future
  WORLD pillar changes.
- **Future increment: pure shader-side polygon reconstruction with
  no CPU side buffer.** If Commit 3 ends up adding side buffers for
  polygon endpoints / chord ages / anchor intensities, future
  refactoring may consolidate them. Not in V.7.7C.2 scope.
