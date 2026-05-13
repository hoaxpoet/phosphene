# Session prompt — Increment D-120 (property taxonomy: `concept_tags` + `motion_paradigm`)

This file is the session prompt for running the D-120 retroactive
tagging + schema increment. Paste the fenced block below into a new
Claude Code session. Do not include this surrounding meta-text. The
work is two coupled landings — (1) schema extension on
`PresetDescriptor` + a new `MotionParadigm` enum, and (2) retroactive
tagging of all production preset JSON sidecars — gated by tests.

Pre-session human prerequisites:

1. Strategy + D-120 must be in tree. Verify with:
   `git log --oneline docs/DECISIONS.md | head -10` and
   `grep -n "^## D-120 " docs/DECISIONS.md` (expect 1 match).
2. Tree is at the post-`[MD-strategy-addendum]` state — the four
   addendum + post-review commits (`89281eed`, `dced1124`,
   `c348a8f0`, `2e5d14ed`) are on local `main`.
3. No new working-tree changes inside the D-120 scope before the
   session starts (out-of-scope leftovers like
   `PhospheneEngine/Sources/ML/StemFFT+GPU.swift` duplicate-comment
   or the `docs/V4_*` → `archive/` moves can stay; they are not
   touched by this session).

---

```
Context: D-120 (filed 2026-05-12, see docs/DECISIONS.md) commits the
Phosphene property taxonomy: every preset's JSON sidecar declares two
new metadata fields beyond `family` —

  - concept_tags: [String]    — visual-concept vocabulary array
                                 (cream-of-crop themes + Phosphene-
                                 native extensions; reuse over
                                 invention; extends as needed)
  - motion_paradigm: String   — one of 8 values from D-029 /
                                 MILKDROP_ARCHITECTURE.md §4
                                 (closed set; single value per
                                 dominant motion source)

This session lands:

  1. The Swift schema extension on `PresetDescriptor` (Codable for
     both new fields with sensible defaults) + a new
     `MotionParadigm` enum (closed set of 8 values).
  2. Retroactive tagging of all 15 production preset JSON sidecars.
  3. Tests gating both — schema decode + per-preset coverage
     assertion (all 15 have non-nil motion_paradigm; concept_tags
     non-empty except for diagnostic presets where empty is
     allowed per D-120).

This is NOT the orchestrator-wiring increment. D-120's Phase 4
follow-up (concept-repeat + paradigm-repeat penalties in
PresetScoringContext + scoring weights) is a separate session;
this one lays the metadata foundation.

Project context:
- 15 production presets per PresetLoaderCompileFailureTest's
  expectedProductionPresetCount (CLAUDE.md current status). Step 0
  verifies the actual count + lists the sidecars.
- PresetDescriptor already has a Codable implementation reading
  passes / scene_* / stem_affinity / certified / rubric_profile /
  rubric_hints (V.6 + earlier). Two more fields land additively;
  back-compat is preserved (defaults when absent).
- Related metadata types (FatigueRisk, TransitionAffordance,
  SongSection, ComplexityCost) live in
  PresetMetadata.swift — the new MotionParadigm enum lands there.
- The taxonomy applies to ALL Phosphene presets, not just
  Milkdrop-inspired. Per D-120, it generalises across the catalog.

Read first (mandatory):
- docs/DECISIONS.md D-120 (the load-bearing decision this session
  implements — read in full, especially the vocabulary list and the
  motion_paradigm enumeration)
- docs/DECISIONS.md D-029 (motion-source paradigms: alternatives,
  not composable; defines the closed-set rationale for the 8
  motion_paradigm values)
- docs/MILKDROP_ARCHITECTURE.md §3 + §4 (the architectural taxonomy
  D-120 draws from; §4's render-pass-breakdown table is the
  per-preset reference for motion_paradigm picks on existing
  Phosphene presets)
- docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md §0.5 (the
  cream-of-crop pack's 11-theme distribution — primary source for
  the concept_tags vocab)
- docs/MILKDROP_STRATEGY.md §12.10 (the addendum entry that filed
  D-120; cites the rejection of the speculative `fidelity` field
  in favour of this architecture-grounded taxonomy)
- PhospheneEngine/Sources/Presets/PresetDescriptor.swift (the file
  this session extends — read the existing Codable shape end-to-end
  before drafting)
- PhospheneEngine/Sources/Presets/PresetMetadata.swift (where the
  new MotionParadigm enum lands; pattern follows FatigueRisk /
  TransitionAffordance / SongSection)
- PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetDescriptorMetadataTests.swift
  AND .../Presets/PresetDescriptorRubricFieldsTests.swift (the test
  patterns this session mirrors)

---

STEP 0 — Audit tree state + production preset enumeration.

0.1 Confirm D-120 is filed:
```
grep -nE "^## D-120 " docs/DECISIONS.md   # expect exactly 1
```
If 0, halt — D-120 is the load-bearing decision this session
implements.

0.2 Confirm production preset count:
```
grep -n "expectedProductionPresetCount" \
  PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetLoaderCompileFailureTest.swift
```
Read the expected count. As of 2026-05-12 it is 15. If it differs,
update the session plan accordingly.

0.3 Enumerate the actual production preset JSON sidecars:
```
ls PhospheneEngine/Sources/Presets/Shaders/*.json
```
The count of the listing must equal the expected count from 0.2.
If not, halt and surface the mismatch to Matt — the test's expected
count is the source of truth; a discrepancy means either a sidecar
is missing or the test is stale.

0.4 Capture the 15 (or whatever) presets to a working list:
```
ls PhospheneEngine/Sources/Presets/Shaders/*.json | \
  xargs -n1 basename | sed 's/\.json$//' > /tmp/d120-presets.txt
wc -l /tmp/d120-presets.txt
```
This is the working set for Step 2's tagging pass.

---

STEP 1 — Schema landing.

1.1 Add MotionParadigm enum to PresetMetadata.swift. Pattern follows
the existing FatigueRisk / TransitionAffordance / SongSection
declarations in that file.

```swift
/// Motion-source paradigm per D-120 / D-029. A preset's dominant
/// motion source — paradigms are alternatives, not composable
/// (D-029); a preset that combines layers picks the single value
/// matching its dominant motion source.
public enum MotionParadigm: String, Codable, Sendable, Hashable, CaseIterable {
    case feedbackWarp           = "feedback_warp"
    case particles              = "particles"
    case cameraFlight           = "camera_flight"
    case meshAnimation          = "mesh_animation"
    case directTimeModulation   = "direct_time_modulation"
    case mvWarp                 = "mv_warp"
    case rayMarchStatic         = "ray_march_static"
    case stagedComposition      = "staged_composition"
}
```

1.2 Extend `PresetDescriptor` to read two new optional JSON fields.
Per D-120: both default to "absent" (empty array + nil) so existing
sidecars decode without breaking; the Step 2 tagging pass fills
every production preset. JSON keys are snake_case to match the
existing sidecar convention.

```swift
// Add to PresetDescriptor stored properties:
public let conceptTags: [String]          // JSON: concept_tags
public let motionParadigm: MotionParadigm?  // JSON: motion_paradigm

// Add to Codable CodingKeys:
case conceptTags        = "concept_tags"
case motionParadigm     = "motion_paradigm"

// Add to init(from:): default empty array / nil when absent.
```

The exact placement of stored properties + CodingKeys cases mirrors
the existing pattern in PresetDescriptor.swift. Keep ordering by
related-purpose if the existing file groups properties that way.

1.3 Test gating — new file
`PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetDescriptorTaxonomyTests.swift`
mirrors the shape of `PresetDescriptorMetadataTests.swift`.

Required tests:
- `decode_minimalJSON_defaultsToEmptyTagsAndNilParadigm` — a JSON
  with only the required existing fields parses; concept_tags is
  empty array, motion_paradigm is nil.
- `decode_withConceptTags_parsesArray` — `"concept_tags": ["a","b"]`
  decodes as `["a","b"]`.
- `decode_withMotionParadigm_parsesEnum` — `"motion_paradigm":
  "ray_march_static"` decodes as `.rayMarchStatic`.
- `decode_invalidMotionParadigm_throwsDecodingError` —
  `"motion_paradigm": "not_a_real_paradigm"` fails decode with a
  clear error (Swift's default `DecodingError.dataCorrupted` for
  enum mismatch is fine).
- `encode_decode_roundTrip_preservesBothFields` — encode a
  descriptor with both fields populated; decode; values match.
- `motionParadigm_allCases_covers8Values` — assert
  `MotionParadigm.allCases.count == 8` (regression-locks the
  closed set against accidental case removal / addition without
  a D-120 amendment).

1.4 Build + run the new tests in isolation before moving to Step 2:
```
swift test --package-path PhospheneEngine \
  --filter PresetDescriptorTaxonomyTests 2>&1 | tail
```
Expect: 6/6 pass.

1.5 Commit 1:
```
[D-120] schema: PresetDescriptor gains concept_tags + motion_paradigm
```
Body: 1-paragraph summary of the schema additions; cite D-120 and
D-029.

---

STEP 2 — Retroactive tagging of all production presets.

Walk every production JSON sidecar in
`PhospheneEngine/Sources/Presets/Shaders/` and add the two fields.

Per-preset tagging procedure:
1. Read the preset's `.metal` source (top of file — file-header
   comment usually summarises the visual register + motion model).
2. Read the preset's existing JSON sidecar (`passes` field is the
   primary signal for motion_paradigm).
3. Cross-reference CLAUDE.md module map entry for the preset
   (verifies the current state vs the .metal — CLAUDE.md may
   sometimes lag actual code, so prefer the source).
4. Cross-reference MILKDROP_ARCHITECTURE.md §4 render-pass table
   (existing presets are enumerated there with motion-source
   labels — useful as a sanity check).
5. Decide:
   - `concept_tags`: 1–3 tags. Start from D-120's listed vocab:
     `fractal`, `geometric`, `waveform`, `reaction_diffusion`,
     `dancer`, `drawing`, `sparkle`, `particles`, `supernova`,
     `hypnotic`, `kaleidoscope`, `aurora`, `cavern`, `web`,
     `terrain`, `nebula`, `plasma`, `glass`, `mosaic`. Extend
     with new tags if no existing tag fits; document each new
     tag's rationale in the commit message.
   - `motion_paradigm`: one of the 8 enum values. For multi-pass
     presets, use the **dominant motion source** per D-029. Use
     `staged_composition` only when the preset uses the staged
     fragment pipeline (currently: Arachne).
6. Update the JSON sidecar (preserve JSON formatting; insert the
   two fields near the existing `family` field for grouping).

Decision-tree guidance for motion_paradigm picks:

- Direct-fragment presets with no persistence (Waveform, Plasma,
  Nebula, etc.) → `direct_time_modulation`.
- Feedback presets (zoom+rot accumulator in a fragment-warp loop)
  with no per-vertex warp (Membrane is the canonical example) →
  `feedback_warp`.
- Presets using Phosphene's `mv_warp` per-vertex pass — even if
  they have a direct-fragment "draw" pass on top — →  `mv_warp`.
- Particle-system presets where the particle field IS the visual
  hero (Murmuration is canonical) → `particles`.
- Ray-march presets with a forward camera dolly (VolumetricLithograph
  has 1.8 u/s forward dolly) → `camera_flight`. The dolly *is* the
  motion source; the ray-march is the rendering pipeline.
- Ray-march presets with a static camera (Glass Brutalist, Kinetic
  Sculpture, TestSphere, Lumen Mosaic) → `ray_march_static`.
- Mesh-shader presets where the mesh generation IS the motion
  (FractalTree's GPU-authored geometry, Stalker's articulated
  gait) → `mesh_animation`.
- Staged-composition presets using the named offscreen-texture
  pipeline (Arachne is the only current example) → `staged_composition`.

Vocabulary guidance for concept_tags:

- Reuse pack themes when they fit. `fractal` covers Sierpinski /
  Mandelbrot / nested-tree visuals; `geometric` covers polyhedral
  / SDF-architectural / abstract-form; `waveform` covers
  oscilloscope / spectrum / wave-tangle; `particles` covers
  particle clouds / flocks / nova-fields; etc.
- New tags are allowed where the existing vocab is the wrong
  shape. Likely candidates from existing Phosphene presets:
  `terrain` (VolumetricLithograph's swept SDF terrain), `web`
  (Arachne / Gossamer / Stalker — the Arachnid Trilogy),
  `mosaic` (Lumen Mosaic), `glass` (Glass Brutalist + LM frosted
  glass), `sculpture` (Kinetic Sculpture if `geometric` doesn't
  capture its register).
- Multi-tag intersections are fine. `["supernova", "particles"]`
  for a particle-nova; `["mosaic", "glass"]` for stained-glass
  panel.
- Diagnostic presets (Spectral Cartograph) may have empty
  concept_tags per D-120 — they exist outside the aesthetic
  taxonomy by design.

Commit in batches of ~5 presets so the diffs stay reviewable.

Suggested commit grouping (session adjusts based on the actual
production preset list from Step 0.4):

- Commit 2a: direct-fragment + feedback presets (Waveform / Plasma /
  Nebula / Membrane).
- Commit 2b: ray-march presets (Glass Brutalist / Kinetic Sculpture /
  TestSphere / Volumetric Lithograph / Lumen Mosaic).
- Commit 2c: particle + mesh + staged presets (Starburst / Murmuration
  / Fractal Tree / Stalker / Arachne / Gossamer / Spectral Cartograph /
  Ferrofluid Ocean).

(The exact bucketing depends on the actual count + identities of the
sidecars enumerated in Step 0.4. Aim for ~3 commits of ~5 sidecars
each; per-commit message lists the presets touched + any new tag
vocab introduced.)

After all sidecars are tagged, add an integration test asserting
the coverage invariant.

`PhospheneEngine/Tests/PhospheneEngineTests/Presets/PresetTaxonomyCoverageTests.swift`
(or extend `PresetDescriptorTaxonomyTests.swift` with a Suite 2):

- `allProductionPresets_haveNonNilMotionParadigm` — load all
  production sidecars via `PresetLoader`; assert every descriptor's
  `motionParadigm` is non-nil. No exceptions.
- `allProductionPresets_haveConceptTagsOrAreDiagnostic` — every
  descriptor's `conceptTags` is non-empty UNLESS the preset is in a
  documented diagnostic-allowlist (Spectral Cartograph at minimum;
  session adds any others surfaced during tagging).

These tests regression-lock the coverage invariant — if a future
preset is added without taxonomy fields, the test fires.

Commit 2d (final): integration test + CLAUDE.md updates (see
Step 3).

---

STEP 3 — Documentation updates.

3.1 Update CLAUDE.md `PresetDescriptor` module-map entry to mention
the two new fields. Insertion point: the entry under
`PhospheneEngine/Presets/`. Current entry reads:

> `PresetDescriptor → JSON sidecar: passes, feedback params, scene
> camera/lights, stem affinity, certified/rubric_profile/rubric_hints (V.6)`

Extend to:

> `PresetDescriptor → JSON sidecar: passes, feedback params, scene
> camera/lights, stem affinity, certified/rubric_profile/rubric_hints
> (V.6), concept_tags + motion_paradigm (D-120)`

3.2 Update the CLAUDE.md "Current Status" landed-work list with a
short entry for D-120 (one paragraph, same shape as recent
increments — what landed, where it lives, what's still open).

3.3 Update the Key Types section in CLAUDE.md if it enumerates
PresetDescriptor's stored properties (some recent additions do
mention `certified` / `rubric_profile`); add the two new fields
with the same one-line treatment.

3.4 No SHADER_CRAFT.md / ENGINEERING_PLAN.md updates needed. The
taxonomy is metadata; it doesn't change the rubric or any phase
deliverables. D-120's carry-forward note "lands alongside the
first inspired-by uplift or earlier as a standalone tagging
session" is satisfied by this session.

3.5 No `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` update needed
(this is JSON metadata, not engine / renderer / shader capability).

---

STEP 4 — Verify.

4.1 Full engine test suite:
```
swift test --package-path PhospheneEngine 2>&1 | tail -30
```
Expect: previous pass count + ~7 new tests (6 from Step 1.3 + 2 from
Step 2's coverage suite). Pre-existing flake baseline (per CLAUDE.md
"Test suite baseline" memory: `MetadataPreFetcher.fetch_networkTimeout`,
`MemoryReporter.residentBytes`, `PreviewResolver`,
`AppleMusicConnectionViewModel`) unchanged.

4.2 SwiftLint:
```
swiftlint lint --strict --config .swiftlint.yml 2>&1 | tail -3
```
Expect: 55 violations (pre-existing baseline). Any new violation
on touched files is a regression and must be fixed before commit.

4.3 App build (warnings-as-errors via xcconfig):
```
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail -5
```
Expect: build clean.

4.4 JSON sanity — every sidecar parses as valid JSON:
```
for f in PhospheneEngine/Sources/Presets/Shaders/*.json; do
  python3 -m json.tool "$f" > /dev/null || echo "INVALID: $f"
done
```
Expect: no INVALID output.

4.5 Per-preset spot-check — print every sidecar's new fields for a
manual review pass:
```
for f in PhospheneEngine/Sources/Presets/Shaders/*.json; do
  echo "=== $(basename $f) ==="
  python3 -c "import json,sys; d=json.load(open('$f')); \
    print('  concept_tags:', d.get('concept_tags', 'MISSING')); \
    print('  motion_paradigm:', d.get('motion_paradigm', 'MISSING'))"
done
```
Expect: every preset shows non-MISSING values for motion_paradigm;
every preset except diagnostic-allowlisted ones shows non-empty
concept_tags.

---

STEP 5 — Closeout + commits.

Commit shape (recap):

- **Commit 1** (Step 1.5): Schema landing — PresetDescriptor +
  MotionParadigm + Step 1.3 tests.
- **Commit 2a, 2b, 2c** (Step 2): Per-batch JSON tagging.
- **Commit 2d** (Step 2 final): Integration tests + CLAUDE.md
  updates.

Aim for 4–5 commits total. Per-commit messages list presets
touched + any new concept_tags vocab introduced with rationale.

Do not push without Matt's "yes, push" confirmation.

Closeout report (post-completion):
1. **Files changed** — Swift sources (PresetDescriptor.swift,
   PresetMetadata.swift) + JSON sidecars (N=15-ish) + tests (1–2
   new files) + CLAUDE.md.
2. **Tests run** — engine suite + new taxonomy tests + coverage
   integration test. Pre-existing flakes unchanged.
3. **Vocabulary extensions** — list any new concept_tags coined
   during the tagging pass, with one-line rationale each. (E.g.
   "`web` — coined for the Arachnid Trilogy; cream-of-crop pack
   has no equivalent register; future Phase MD inspired-by uplifts
   of arachnid-themed sources will reuse.")
4. **Engineering plan updates** — none.
5. **Capability registry updates** — none.
6. **Known risks** — vocabulary disagreement at first inspired-by
   session may surface a missing tag; D-120 expressly allows
   extension. Phase 4 orchestrator-wiring follow-up is required
   to make the taxonomy product-effective; not in this session's
   scope.
7. **Git status** — branch, commit hashes, working tree clean
   for this session's scope. The pre-existing out-of-scope
   working-tree state (StemFFT+GPU.swift duplicate-comment;
   `docs/V4_*` → `archive/` moves) remains untouched.

---

DO NOT:

- Do not add concept_tags / motion_paradigm to any Phase 4
  orchestrator scoring logic this session. That's the D-120
  Phase-4-wiring follow-up — a separate session.
- Do not change any preset's `family` value. `family`,
  `concept_tags`, and `motion_paradigm` are three orthogonal
  fields; this session adds two, not three.
- Do not introduce a Swift enum for `concept_tags`. Per D-120 the
  vocabulary is open and extensible; `[String]` is correct.
  Validation, if added later, happens at orchestrator-wiring time,
  not here.
- Do not add a Settings toggle for any taxonomy field. This is
  descriptive metadata; no user-facing surface.
- Do not modify the existing test
  `PresetLoaderCompileFailureTest.expectedProductionPresetCount`
  — it is the source of truth for production preset count and
  this session must not affect that count.
- Do not modify the 3 out-of-scope working-tree items
  (`PhospheneEngine/Sources/ML/StemFFT+GPU.swift` duplicate
  comment, `docs/V4_AUDIT.md` → `archive/V4_AUDIT.md` move,
  `docs/V4_PERF_RESULTS.json` → `archive/V4_PERF_RESULTS.json`
  move). Those are pre-existing tree state surfaced in prior
  closeouts; addressing them is a separate housekeeping pass.
- Do not push to remote.

---

Carry-forward (informational only — do not implement in this
session):

- **Phase 4 orchestrator wiring (next D-120 follow-up).** Extend
  `PresetScoringContext` with `recentConceptTags` and
  `recentMotionParadigms` history; add concept-repeat +
  paradigm-repeat penalty terms to `DefaultPresetScorer`;
  scoring weights TBD when wiring lands; verify via
  golden-session regression tests.
- **First inspired-by uplift session.** Will use the taxonomy
  directly. New `concept_tags` (e.g. `kaleidoscope` if the source
  preset is one) may surface and get documented in that session's
  closeout.
- **`PresetCategory` Swift enum**. Stays as-is — `family` is its
  Swift representation; `concept_tags` + `motion_paradigm` are
  JSON-side metadata, not Swift enum cases. No engine-side
  enumeration of valid concept_tags is required.
```

---

## Notes on running this prompt

* **Estimated session length:** ~60–90 min total. Step 1 (schema)
  is ~30–40 min including tests; Step 2 (tagging) is ~30–40 min
  including the integration tests; documentation + verify + commit
  is ~15 min.
* **Output volume:** 4–5 commits, ~3–4 Swift / test files touched,
  ~15 JSON sidecars edited, CLAUDE.md updated in two places.
* **Prerequisite verification:** the Step 0 audit is load-bearing.
  If the production preset count differs from
  `expectedProductionPresetCount`, halt — do not proceed without
  surfacing the mismatch.
* **Vocabulary extension expectation:** ~2–4 new `concept_tags`
  likely (probable additions: `web`, `terrain`, `mosaic`, `glass`).
  The vocabulary is open per D-120; document each new tag in the
  commit message.
