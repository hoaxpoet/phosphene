# Phase MD — Milkdrop Ingestion Strategy

**Author:** Claude Code session, 2026-05-12. Awaiting Matt sign-off
on §3 decisions.
**Predecessor doc:** [`docs/MILKDROP_ARCHITECTURE.md`](MILKDROP_ARCHITECTURE.md)
(the research that informed MV-1 / MV-2 / MV-3 and now scopes this
phase).
**Empirical basis:** [`docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md`](diagnostics/MD-strategy-pre-audit-2026-05-12.md).

This document answers the *strategic* questions Phase MD has had
unspecified since 2026-04 — how the work tracks port / evolve / hybrid
relate, which Phosphene capabilities are mandatory per tier, how
ray-march hybrid candidates are picked, how big the transpiler scope
is, what the licensing posture is, and how the catalog presents this
material to the user. It does **not** implement anything — every
section ends in an open decision Matt walks before MD.1 starts.

---

## §1. Why this strategy exists

`ENGINEERING_PLAN.md` Phase MD has had MD.1 through MD.7 specified
since 2026-04, but the *direction* of the work has not been pinned
down. The mechanics are documented (grammar audit, transpiler CLI,
HLSL conversion, runtime adapter, 10 ports, 20 evolved, 5 hybrids),
but Phase MD as currently written cannot answer:

1. Is Phosphene shipping Milkdrop *clones* or Milkdrop-*influenced*
   originals — and how does that vary across the three sub-phases?
2. Which Phosphene-specific capabilities (mv\_warp, deviation
   primitives, stem routing, beat phase, pitch tracking, mood,
   structural prediction) are *mandatory* per tier vs. *opt-in*?
3. What makes a Milkdrop preset a good ray-march hybrid candidate vs.
   a "leave it as a port" preset?
4. How much of the `.milk` grammar surface does MD.2 commit to
   covering before MD.5 starts?
5. What is the licensing posture for transpiled output, and what
   needs to happen before public commit?
6. How does the user (and the orchestrator) tell the three tiers
   apart in the catalog?

Without answers, MD.2 will thrash on per-preset decisions that should
be governed by phase policy. This doc collects the open questions as
explicit decisions (§3, decisions A through J), recommends an option
per decision with rationale, surveys the cream-of-the-crop pack to
back the decisions with empirical evidence (§5), and proposes the
end-to-end workflow (§4) that the decisions assemble into.

Matt signs off on the picks (§10); the picks become D-### entries;
MD.1 starts.

---

## §2. Constraints — non-negotiable

These are inherited from existing decisions and architecture. Every
option in §3 must respect them; an option that doesn't is not a
viable pick.

* **D-029 — Motion-source paradigms are alternatives, not composable
  layers.** Milkdrop's feedback warp + per-pixel grid is one paradigm;
  Murmuration's compute particles is another; ray-march flythroughs
  are a third. Stacking them produces visual mush. MD.7 ray-march
  hybrids *only* work with static cameras (no flight) and feedback
  warp on top; no third paradigm can be added.
* **D-026 — Deviation primitives mandatory.** No production preset may
  threshold absolute AGC-normalized energy values (`f.bass > 0.22`).
  Drive from `f.bassRel` / `f.bassDev` and the per-stem deviation
  variants. This applies to every Milkdrop tier — Classic Port,
  Evolved, and Hybrid alike. Transpiled `.milk` files that drive on
  raw `bass` get re-bound to `bassRel`-equivalent semantics during
  conversion.
* **D-027 — `mv_warp` pass is opt-in per preset.** Phosphene's
  `mv_warp` is the per-vertex feedback pass that implements Milkdrop-
  style feedback motion. It is already wired and **has two production
  consumers** (Gossamer, Volumetric Lithograph — see audit §0.3).
  Phase MD is incremental on this pass, not pioneering it.
* **D-028 — MV-3 capabilities are wired.** `beatPhase01`,
  `vocalsPitchHz`, per-stem `onsetRate` / `centroid` / `attackRatio` /
  `energySlope`, plus the MV-1 deviation primitives — all have real
  value paths (audit §0.4). The strategy can build on them as
  load-bearing surfaces.
* **D-067 — Certification rubric applies to all production presets.**
  Lightweight vs full profile choice per preset (D-067(b)). Milkdrop
  ports are not exempt; they go through M7 and rubric verification
  before `certified: true`.
* **License — Phosphene is MIT.** The cream-of-crop pack is curated
  by ISOSCELES with a stated "public-domain-by-convention with
  takedown" posture (audit §0.2). Individual preset authors
  technically retain copyright. Deciding the legal posture for the
  transpiled output is Decision I; until that decision lands, no
  Milkdrop-derived preset commits to a public branch.

The strategy proposes; D-029, D-026, D-027, D-028, D-067 arbitrate.

---

## §3. Open decisions

For each decision: 2–4 options, a recommendation with rationale, and
what the pick locks in for MD.1–MD.7. Matt walks the list and picks;
picks become D-### entries before MD.1 starts.

### Decision A — Tier structure

* **A.1 — Three tiers** (Classic Port / Evolved / Hybrid). Matches the
  existing MD.5 / MD.6 / MD.7 split. Three distinct catalog
  experiences: faithful Milkdrop, Milkdrop-with-Phosphene-music-data,
  Milkdrop-warp-plus-3D-world.
* **A.2 — Two tiers** (Port / Evolved). Drop MD.7. Recognize that
  ray-march + feedback-warp + static-camera is a thin architectural
  niche.
* **A.3 — Four tiers** (Port / Light-Evolved / Heavy-Evolved /
  Hybrid). Split Evolved into "minimum stem hookup" and "full MV-3
  panel."

**Recommendation: A.1.** Matches the existing plan structure;
provides clear catalog story; MD.7 hybrids are exactly the right
home for the mv\_warp + ray-march composition that has no production
proof yet but is architecturally supported. A.2 forfeits the most
distinctive part of the strategy (a tier where Phosphene's 3D
infrastructure stacks on Milkdrop's warp accumulation). A.3 adds
fractal-style sub-tiers without adding clarity — "light evolved" vs
"heavy evolved" is hard to render as a catalog distinction.

**Locks in:** MD.5 / MD.6 / MD.7 retain their identities. Catalog
gains three new `family` values (Decision C). Settings UI gains
three sub-toggles (Decision D).

### Decision B — Mandatory vs opt-in capabilities per tier

Build the matrix. Per-row recommendation embedded in the table; full
rationale below.

| Capability | Classic Port (MD.5) | Evolved (MD.6) | Hybrid (MD.7) |
|---|---|---|---|
| Deviation primitives (D-026) | **mandatory** | **mandatory** | **mandatory** |
| `mv_warp` pass | **mandatory if source preset had per-pixel warp** | **mandatory** | **mandatory** |
| Stem-driven routing | opt-in | **mandatory ≥ 1 stem** | **mandatory ≥ 2 stems** |
| `beatPhase01` anticipation | opt-in | opt-in | **mandatory if motion-dominated** |
| Vocal pitch → hue / parameter | opt-in | opt-in | opt-in |
| Per-stem rich metadata (MV-3a) | opt-in | opt-in | **mandatory if perceptually relevant** |
| Mood (valence / arousal) | not used | opt-in | opt-in |
| Section / structural prediction | not used | not used | opt-in |
| Ray-march backdrop | N/A | N/A | **mandatory** (defining feature) |
| SSGI | N/A | N/A | opt-in (perf-constrained) |
| PBR materials | N/A | N/A | opt-in |
| V.6 rubric profile | **lightweight** | **full** | **full** |

**Rationale per row.**

* **Deviation primitives** are project-level invariants (D-026 / FA #31)
  and apply across every tier without exception. Transpiled raw `bass`
  reads get re-bound to `bassRel`-equivalent semantics. No opt-out.
* **mv\_warp** is the architectural representation of Milkdrop's per-
  vertex feedback warp. A Classic Port that doesn't use mv\_warp is
  not a port — it's a per-pixel-grid abstraction without the
  accumulation that makes the Milkdrop aesthetic Milkdrop. So
  mandatory whenever the source has the equivalent (which is the
  ~6,049 presets with `per_pixel_NN` — 62 % of the pack — per audit
  §0.5). Evolved and Hybrid inherit; both have additional reasons to
  use it.
* **Stem-driven routing** is the cheapest way to make a Milkdrop preset
  feel like a *Phosphene* preset. Classic ports skip it (they're
  trying to be faithful to the source's audio-coupling) but Evolved
  and Hybrid must use it. Evolved minimum: route at least one stem to
  at least one visual parameter. Hybrid minimum: at least two stems
  (e.g. drums → flash intensity, bass → camera dolly speed). This is
  the single biggest perceptual differentiator between tiers.
* **`beatPhase01`** lets motion anticipate the beat. Required only
  when the preset's primary visual is motion (Hybrid, where camera
  static + ray-march backdrop has limited motion vocabulary and
  anticipatory beat lock matters); opt-in otherwise.
* **Vocal pitch → hue** is a strong but narrow tool. Most
  electronic-tonal music has weak vocal pitch confidence; jazz /
  acoustic / vocal-pop is where it pays. Always opt-in.
* **MV-3a rich metadata** (per-stem onsetRate / centroid / attackRatio /
  energySlope) is mandatory in Hybrid only if the preset's visual
  reads them. Hybrid presets that don't (a static-camera ray-march
  backdrop with feedback warp on top, no fine-grained per-stem
  reactivity) are still allowed — but if the preset is sold as
  "evolved," at least one MV-3a channel should feed something the
  listener can hear-vs-see.
* **Mood** (valence / arousal) is wide-window emotional state, not
  beat-level. Useful for sustained palette shifts. Always opt-in.
* **Structural prediction** is the section-boundary signal from
  `StructuralAnalyzer`. Recommendation: skip until validated on real
  music (Decision G).
* **Ray-march backdrop** is what makes a Hybrid a Hybrid. Without it,
  it's an Evolved preset with an architecture deviation.
* **SSGI / PBR** are perf-expensive; opt-in only and gated by
  `complexity_cost` (D-067).
* **V.6 rubric profile** — Classic Ports' visual identity is the
  Milkdrop warp, not Phosphene's detail cascade. The lightweight
  rubric (D-067(b)) is the right fit. Evolved and Hybrid both have
  enough Phosphene-specific surface — stem routing, beat phase
  anticipation, ray-march geometry — to be evaluated on the full
  rubric.

### Decision C — Catalog presentation and naming

* **C.1 — Single `family: "milkdrop"` tag** with a `subtype` field
  (`port` / `evolved` / `hybrid`) that the orchestrator can filter on.
* **C.2 — Separate families** per tier: `milkdrop_classic` /
  `milkdrop_evolved` / `milkdrop_hybrid`. Three distinct top-level
  `family` values.
* **C.3 — No surfaced distinction.** Just families like `geometric` /
  `organic` etc.; Milkdrop origin is metadata only.

**Recommendation: C.2.** Separate families let:

1. Settings UI present three sub-toggles cleanly (Decision D).
2. Orchestrator's family-repeat penalty (Phase 4) naturally avoid
   two Classic Ports back-to-back without grouping ports against
   evolved or hybrids.
3. M7 reviews evaluate per-tier (a Classic Port at lightweight rubric
   shouldn't compete head-to-head with a Hybrid at full rubric for
   "best Milkdrop tier preset").

Naming convention (filesystem):

```
PhospheneEngine/Sources/Presets/Shaders/Milkdrop/<preset_name>.{metal,json}
```

with the `family` JSON field disambiguating. Optional prefix for
hybrids (`hybrid_<name>.{metal,json}`) if Matt finds it useful at
catalog scale. The existing MD.5 spec already commits to
`family: "milkdrop_classic"`; this decision aligns MD.6 / MD.7
("`milkdrop_evolved`" / "`milkdrop_hybrid`").

### Decision D — User toggle / Settings exposure

* **D.1 — Single toggle.** "Include Milkdrop-style presets" — current
  U.8 design. Off-by-default until catalog matures.
* **D.2 — Per-tier toggles.** Three sub-toggles ("Classic ports" /
  "Evolved" / "Hybrid"), optionally collapsed into a disclosure row
  to keep the Settings panel calm.
* **D.3 — No surfaced toggle.** Always on; orchestrator picks.

**Recommendation: D.2** with disclosure-row UX. A user who wants
warm-nostalgia-only Milkdrop-style should be able to turn off Evolved
and Hybrid. A user who wants Phosphene-only-modern should be able to
turn off Classic. D.1 is acceptable as a fallback if Settings UI
real-estate is tight, but the tiers are different enough that
treating them uniformly is a thin compromise. D.3 over-rotates on
orchestrator trust; users with strong tier preferences need an out.

**Locks in:** Settings UI gains three new toggles under "Visuals"
section; `SettingsStore` gains three persisted keys (e.g.
`phosphene.settings.visuals.milkdrop.classic`, `.evolved`, `.hybrid`).
The `PresetScoringContext.excludedFamilies` already supports per-
family exclusion (D-053), so wiring is shallow.

### Decision E — Ray-march hybrid candidate selection criteria

* **E.1 — Architectural fit only.** Source preset must be static-
  framed (no rotation / zoom / flight in the original). The
  ray-march backdrop slots in behind the existing warp; D-029 holds.
* **E.2 — Architectural fit + thematic fit.** As E.1, plus the source
  preset's visual subject must benefit from 3D depth (atmospheric
  haze, depth-of-field, etc.) — i.e. the ray-march pass earns its
  cost.
* **E.3 — Architectural fit + thematic fit + brand fit.** As E.2,
  plus the resulting hybrid must sit at an aesthetic register the
  Phosphene catalog actively wants (rather than reproducing what
  Phosphene already has via Glass Brutalist / Kinetic Sculpture / VL).

**Recommendation: E.3.** D-029 is non-negotiable, so E.1 is a floor,
not a strategy. Beyond that floor, Phase MD has 5 hybrid slots
budgeted (MD.7); picking 5 that *fit Phosphene's architecture and
fill catalog gaps* is the maximum-value use of those slots.
Architectural fit (no moving camera in source), thematic fit
(ray-march pass adds real depth rather than gilding), and brand fit
(register Phosphene doesn't already cover) compound.

Specific candidate criteria for Matt to apply per preset:

1. **Source preset is static-framed.** No `zoom`, `rot`, `cx`, `cy`,
   `dx`, `dy` per-frame equations modulating the warp grid in a way
   that simulates camera motion. Most Reaction / Sparkle / Particles
   presets pass; many Dancer / Hypnotic presets fail.
2. **Source preset has a clear "background"** that a ray-march pass
   can be placed *behind* without the foreground warp obscuring it.
   Presets that fill the screen edge-to-edge with feedback artifacts
   are weaker candidates.
3. **3D depth would add something specific.** Atmospheric haze for a
   particle field; volumetric god-rays behind a kaleidoscope; an
   abstract terrain horizon under a warp grid. Each candidate should
   come with a one-sentence answer to "what does the ray-march
   backdrop *do*?"
4. **Register gap.** Does Phosphene already have this aesthetic? If
   yes, the hybrid is competing internally rather than expanding.

Three plausible candidates surfaced in the audit (these are starting
points, not commitments — Matt picks 5 from MD.6 onward):

| Source preset (theme) | Why a hybrid candidate |
|---|---|
| Geiss — *3D - Luz* (Supernova / Radiate) | Static-framed; canonical "particle nova" register; ray-march backdrop could add depth-fog and a horizon line that Phosphene's catalog lacks. |
| Rovastar — *Northern Lights* (Supernova / Radiate) | Static-framed; aurora register Phosphene doesn't have (Aurora Veil is direct-fragment + mv\_warp, not ray-march); ray-march sky volume could carry the sustained-bass IBL breath that AV uses. |
| EvilJim — *Travelling backwards in a Tunnel of Light* (Fractal / Nested Square) | Tunnel composition naturally maps to a static-camera ray-march receding-tunnel SDF; warp accumulation adds the Milkdrop pulse on top. |

### Decision F — Per-stem hue affinity for Evolved tier

The Lumen Mosaic per-cell colour question has surfaced repeatedly:
should evolved Milkdrop presets get per-stem hue affinity (drums
controlled cell hue, bass controlled another, etc.)?

* **F.1 — Mandatory.** Every Evolved preset must route at least one
  stem to hue, not just to intensity.
* **F.2 — Opt-in per preset.** Authors choose; some presets keep the
  source palette intent, others use stem-hue.
* **F.3 — Skip entirely.** Evolved-tier stems modulate intensity /
  motion / threshold only; never hue.

**Recommendation: F.2.** Hue affinity is a strong tool but it can
clash with the source preset's palette intent. A Reaction-theme
preset whose original palette is a tight pink-magenta gradient
shouldn't have its hue derailed by drum onsets. Opt-in lets the
preset author (Claude Code under Matt's direction) decide on the
basis of the source's character. (LM.5's hue-affinity work was
abandoned for similar reasons; the lesson generalizes.)

### Decision G — Section-awareness for Evolved / Hybrid tiers

* **G.1 — Mandatory.** Evolved / Hybrid presets must respond to
  section boundaries from `StructuralAnalyzer` (palette shift at the
  drop, motion change at the bridge).
* **G.2 — Opt-in.** Authors choose per preset.
* **G.3 — Skip until validated.** Don't make this a Phase MD
  deliverable; revisit when `StructuralAnalyzer` has a track record
  on real-music sessions.

**Recommendation: G.3.** `StructuralAnalyzer` is wired but has not
been validated as a preset-driving signal in production. Coupling
Phase MD to a separate validation track multiplies the risk surface
and the time-to-MD.5. Better to ship Evolved / Hybrid against the
proven MV-3 capability set first, then revisit section-awareness as
its own incremental upgrade once the analyzer has earned its keep.

### Decision H — Transpiler scope

The audit (§0.5) showed the .milk format has **four distinct sub-
languages**: per-frame / per-frame-init expressions, per-pixel grid
expressions, per-shape / per-wave / per-shape-init / per-wave-init
expressions, and embedded HLSL pixel-shader source. The first three
share a parser; the fourth is its own track. 81 % of the pack uses
HLSL.

* **H.1 — Expression language only.** Transpile the first three
  sub-languages; reject presets with non-empty `warp_1=` /
  `comp_1=` HLSL blocks. Restricts MD.5 / MD.6 to the 1,559 HLSL-
  free presets (~16 % of pack). Cheap, fast, fully covered grammar.
* **H.2 — Expression language + bring in HLSL→MSL cross-compiler.**
  Use SPIRV-Cross or naga to translate the HLSL pixel-shader portion
  into MSL. Materially larger scope; introduces a non-Phosphene
  build dependency.
* **H.3 — Expression language + hand-port HLSL per preset.** Transpile
  expressions automatically; treat HLSL as a manual conversion step
  during MD.5 / MD.6 authoring. Slow per preset; predictable scope.
* **H.4 — Hand-port everything.** No transpiler. MD.2 deleted from
  plan. Each preset is a manual reauthor against Milkdrop reference.

**Recommendation: H.1 for MD.5; revisit for MD.6 / MD.7.** The 1,559
HLSL-free presets are enough to fill the MD.5 budget (10 ports) with
substantial room to maneuver and substantial diversity (Fractal 492,
Geometric 265, Dancer 262, etc.). Ship H.1 as the cheap, fully-
testable, transpiler-proof path. *After* MD.5 lands and the
transpiler is proven on real presets:

* If MD.6 / MD.7 can find 20 + 5 candidates within the HLSL-free
  subset, keep H.1 indefinitely.
* If MD.6 / MD.7 require HLSL-bearing source presets to fill the
  catalog gap, escalate to **H.3** (hand-port HLSL preset by preset).
  Avoid H.2 unless the HLSL portion proves repeatedly tractable —
  bringing in a cross-compiler is a real surface for breakage and a
  drag on the build.

H.4 forfeits the catalog-depth lever that makes Phase MD worth
running. The transpiler is the cheap path to 30+ catalog members
versus another year of hand-authored fidelity uplifts.

**Locks in:** MD.2 scope tightens to expression language only.
MD.1 grammar audit doc focuses on the expression sub-languages plus
a thin HLSL appendix (catalog the HLSL features used, deferred to
hand-port). MD.5 candidate filter is `! grep -q '^warp_1=' AND !
grep -q '^comp_1='`.

### Decision I — Licensing posture for transpiled output

The audit (§0.2) shows the cream-of-crop pack curator's stated
posture is "public-domain-by-convention" — preset authors retain
copyright but the pack ships under an informal public-release
assumption with a project-managed takedown path. The pack itself has
no SPDX-identifiable licence.

* **I.1 — Treat transpiled output as MIT-derivative.** Document the
  ISOSCELES / projectM provenance and each source-preset's original
  author + filename in `docs/CREDITS.md` (mirroring the pattern for
  Open-Unmix HQ and Beat This! ML weights). Ship under Phosphene's
  MIT licence. Commit to honoring takedown requests routed through
  projectM.
* **I.2 — Dual-license** transpiled output as MIT + a separately-
  stated "Milkdrop preset content used under ISOSCELES pack curatorial
  posture" notice. Maximalist attribution.
* **I.3 — Defer until counsel review.** Phase MD pauses. MD.1 grammar
  audit can run (no licensed content committed), but MD.2 onwards
  waits.

**Recommendation: I.1 with explicit counsel-review checkpoint.** The
operative posture is well-established (ISOSCELES has shipped this
pack as projectM's default for several years; no significant
copyright dispute is on the record). The CREDITS.md template already
exists. Counsel review is appropriate but the work can sequence: do
MD.1 (no licensed content), get counsel sign-off in parallel, then
MD.2 onwards. If counsel review concludes I.3, Phase MD pauses;
otherwise I.1 binds.

**Locks in:** Each transpiled `.metal` / `.json` ships with a
`milkdrop_source` JSON field carrying original filename + author +
SHA256 of source `.milk` for provenance. `docs/CREDITS.md` gains a
"Milkdrop preset attribution" section enumerating presets shipped.
No public-branch commit until counsel review concludes.

### Decision J — Cream-of-the-crop subset for MD.5

10 presets to port for MD.5. Three selection criteria are in
tension:

* **J.1 — By visual family diversity.** Span the audit's 11 themes
  (Fractal / Geometric / Waveform / Reaction / Dancer / Drawing /
  Sparkle / Particles / Supernova / Hypnotic / ! Transition). Spread
  the 10 ports across the theme dimension.
* **J.2 — By Phosphene catalog gap-filling.** Pick presets whose
  visual register is *underserved* in Phosphene's existing catalog
  (e.g. Phosphene has nothing in the Reaction-diffusion register;
  prioritize one Reaction port).
* **J.3 — By transpiler-proof simplicity.** Pick the simplest 10 to
  surface transpiler bugs early before MD.6 / MD.7's complexity.

**Recommendation: hybrid (J.3 *and* J.1, with J.2 as tiebreaker).**

* J.3 is the *selection criterion* — restrict the candidate set to
  HLSL-free presets ≤ 5 KB (the simplest end of the 1,559-preset
  subset). This is what proves the transpiler.
* J.1 is the *coverage check* — the final 10 must span at least 6 of
  the 11 themes so MD.5 doesn't ship as "10 Fractal presets."
* J.2 is the tiebreaker — when multiple simple HLSL-free presets are
  viable in a theme, pick the one whose register Phosphene lacks.

Concrete candidate list for Matt to walk (drawn from the audit's
HLSL-free smallest-20 list, filtered for theme diversity):

| Theme | Preset | Size | Rationale |
|---|---|---:|---|
| Supernova | Geiss — *3D - Luz* | 949 B | Smallest in the pack; canonical Geiss-3D register. |
| Waveform | Rovastar — *Voyage* | 959 B | Classic wire-tangle motion; canonical wire-3D primitive. |
| Reaction | Sjadoh — *Fortune Teller* | 969 B | Reaction-diffusion blob register Phosphene lacks. |
| Waveform | Geiss — *3D Shockwaves* | 1.0 KB | Pulsing wireframe sphere; covers wave-shockwave register. |
| Fractal | EvilJim — *Travelling backwards in a Tunnel of Light* | 1.0 KB | Tunnel-of-nested-squares register (also a hybrid candidate per Decision E). |
| Supernova | Pithlit — *Nova* | 1.0 KB | Gaseous-nova register. |
| Fractal | EvilJim — *Ice Drops* | 1.0 KB | Falling-fractal register. |
| Waveform | Geiss — *Bipolar X* | 1.0 KB | Circular-wire variation. |
| Supernova | Northern Lights | 1.2 KB | Aurora register (overlaps with Aurora Veil — gap-filler tiebreak; see below). |
| Geometric (TBD) | candidate from `Geometric/Stripes Liquid/` or `Geometric/Pulsate/` HLSL-free subset | ≤ 5 KB | Geometric theme representation; specific pick deferred to MD.5 authoring session. |

10th slot intentionally left TBD — Matt walks the HLSL-free Geometric
subset (265 presets) during MD.5 to pick the one whose register most
complements the 9 above. Substitutions in other slots are fine if a
better candidate surfaces during authoring; the goal is 10 ports
spanning ≥ 6 themes with the transpiler proven.

**Pre-emption note on Northern Lights:** Aurora Veil (Phase AV) is
already designed against a curated aurora reference set. Shipping a
Milkdrop "Northern Lights" port at the same time risks intra-catalog
overlap. Tiebreak: keep this slot if Aurora Veil slips behind MD.5;
swap for `Rovastar — Trippy S` (1.0 KB, Waveform / Wire Tangle) or
similar if AV ships first. Matt's call at MD.5 authoring.

---

## §4. Architecture proposal — per-preset workflow

Conditional on Matt's picks above. The workflow per Milkdrop preset
brought into Phosphene:

1. **Pick** from cream-of-crop pack (per Decision J for MD.5; per
   Decision E for MD.7; per the broader pack for MD.6).
2. **Transpile** (per Decision H scope) — `.milk` →
   `<preset_name>.json` sidecar + `<preset_name>.metal` shader.
   Output preserves source-preset structure where possible (e.g.
   per-frame equations become Swift-side mesh-tick logic; per-pixel
   grid equations become `mv_warp` vertex shader body).
3. **D-026 audit pass** on transpiler output. Flag absolute-threshold
   patterns like `if (bass > 0.22)` and rewrite to `bassRel` or
   `bassDev` semantics. The transpiler should do this automatically;
   the audit is a human read-through to verify.
4. **Tier assignment** (per Decision A). MD.5 — Classic Port stops
   here. MD.6 — continue to step 5. MD.7 — continue to steps 5 + 6.
5. **Evolved capabilities bolt-on** (per Decision B). Add stem
   routing (≥ 1 stem for Evolved, ≥ 2 for Hybrid). Optional MV-3a
   rich metadata, vocal-pitch coupling, mood, etc. Each capability
   added is a JSON `mv3_features_used` array entry (per MD.6 spec)
   and a clear visual contract — "drums.onsetRate raises bloom
   threshold," not "drums data goes into the shader somehow."
6. **Hybrid ray-march backdrop** (per Decision E for MD.7). Author
   the ray-march pass against curated visual references. Static
   camera per D-029. Compose via the existing
   ray\_march → composite → mv\_warp pass chain (VL's pattern).
7. **JSON metadata** — family per Decision C, complexity\_cost
   measured per device tier, visual\_density / motion\_intensity /
   fatigue\_risk per Phase 4 schema (D-029-era), rubric profile per
   Decision B, certified false until M7.
8. **V.6 rubric verification** at the profile assigned in step 7.
9. **Matt M7 review** on a real-music session. Acceptance criteria:
   does it feel like Milkdrop (Classic Port)? Like Milkdrop + stem
   awareness (Evolved)? Like Milkdrop + Phosphene-3D (Hybrid)? No
   anti-references hit. Quality floor cleared.
10. **Cert flip** → `certified: true` in JSON sidecar.

**Folder layout.** `PhospheneEngine/Sources/Presets/Shaders/Milkdrop/`
holds the .metal and .json files. The directory is enumerated by
`PresetLoader` like any other; no special handling. Preset names
follow `<theme>_<source_name>.{metal,json}` (theme prefix avoids
filename collisions across the 9,795-preset namespace).

**Golden-hash registration.** Each ported preset gets a 3-tuple
entry in `PresetRegressionTests.goldenHashes` like every other
preset (D-039). MD.5 lands 10 new entries.

**Pre-existing surfaces re-used.** No new render passes. No new
fragment-buffer slots. No new Metal preamble changes (the existing
preamble is the byte-identical engine library Gossamer and VL
already use; transpiled mv\_warp body lives in the preset's `.metal`
file alongside its fragment).

---

## §5. Cream-of-the-crop survey

Audit-evidenced findings. Section §0.5 of the audit lists feature
counts across all 9,795 presets. This section adds tier
candidate-list rationale.

### Theme-by-theme overview

| Theme | Total | HLSL-free | Strongest MD.5 candidate | Phosphene catalog gap status |
|---|---:|---:|---|---|
| Fractal | 1,354 | 492 | EvilJim — *Travelling backwards in a Tunnel of Light* | Underserved (Phosphene has Fractal Tree, no nested-square or Sierpinski register). |
| Geometric | 1,027 | 265 | TBD per MD.5 authoring | Partially served (Glass Brutalist, Kinetic Sculpture). |
| Dancer | 1,351 | 262 | Most "Dancer" presets are HLSL-heavy; one HLSL-free Hatch preset would suffice. | Largely unserved. |
| Waveform | 1,279 | 180 | Rovastar — *Voyage* / Geiss — *Bipolar X* | Unserved (Phosphene's `Waveform.metal` is the static spectrum primitive, not the Milkdrop wire-tangle register). |
| Reaction | 1,791 | 133 | Sjadoh — *Fortune Teller* | Unserved (reaction-diffusion register entirely missing from Phosphene). |
| Supernova | 380 | 120 | Geiss — *3D - Luz* | Unserved (no "explosive radial" register; closest is Nebula). |
| Particles | 389 | 64 | One pure-expression particle preset (audit §0.6, yin — Ocean of Light) | Partially served (Murmuration is the canonical particle preset). |
| Drawing | 1,143 | 23 | Mostly HLSL-heavy; weak MD.5 fit. | Unserved. |
| Sparkle | 797 | 18 | Same — weak MD.5 fit. | Unserved. |
| Hypnotic | 280 | 1 | Almost entirely HLSL — defer to H.3 escalation. | Partially served (Lumen Mosaic for stained-glass). |
| ! Transition | 4 | 1 | Skip — transitional fragments, not standalone presets. | N/A |

### 10 MD.5 candidates (transpiler-proof + theme-diverse)

See Decision J for the per-preset list. Rationale: nine concrete
slots span Supernova / Waveform / Reaction / Fractal; tenth slot
left TBD for Geometric theme representation chosen during MD.5
authoring.

### 20 MD.6 candidates (evolved tier)

Deferred until MD.5 lands. The MD.5 process surfaces which evolved
capabilities (stems / pitch / beat phase) feel "right" in real
playback; MD.6 candidate list draws from that evidence. Pre-MD.5
guess: 5 each from Reaction / Fractal / Dancer / Geometric — the
themes where Phosphene's catalog gap is largest and where stem-
driven motion would most amplify the source preset's identity.

### 5 MD.7 candidates (hybrid tier)

Deferred until MD.6 lands and the mv\_warp + ray-march composition
has at least one production proof outside VL. Pre-MD.6 starting
points (from Decision E):

1. Geiss — *3D - Luz* (Supernova / Radiate). Particle-nova register;
   ray-march sky volume backdrop.
2. Rovastar — *Northern Lights* (Supernova / Radiate). Aurora
   register; ray-march sky volume backdrop. (Coordinate with Aurora
   Veil per Decision J pre-emption note.)
3. EvilJim — *Travelling backwards in a Tunnel of Light* (Fractal /
   Nested Square). Tunnel register; ray-march receding-tunnel SDF
   backdrop with feedback warp overlay.
4. TBD from Reaction theme — a static-framed reaction-diffusion
   preset whose backdrop could become a ray-march abstract terrain.
5. TBD from Fractal theme — a static-framed fractal preset whose
   backdrop could become a ray-march cathedral / hall / void.

---

## §6. Phased plan refinement

Per-increment scope revisions conditional on Matt's picks:

| Increment | Pre-strategy scope | Strategy-conditional revision |
|---|---|---|
| MD.1 grammar audit | All grammar across pack | Focus on the **expression sub-languages**; HLSL gets a thin "deferred for hand-port" appendix per Decision H.1. |
| MD.2 transpiler CLI | Cover 100 % of pack with parser | Cover the **expression sub-languages** only. HLSL-free preset filter is built into the candidate-selection harness, not the transpiler. |
| MD.3 HLSL warp / composite conversion | First-class | Tightened to **manual** per preset per Decision H.1; no automated HLSL→MSL track. MD.3 doc becomes the hand-port playbook rather than transpiler spec. |
| MD.4 Runtime adapter | Preset entry-point glue | Unchanged. |
| MD.5 First 10 ports | 10 presets via family diversity | 10 presets via Decision J hybrid (J.3 selection + J.1 coverage). Each preset's source `.milk` ships with provenance metadata per Decision I. |
| MD.6 First 20 evolved | "MV-3 capability uplift, 20 presets" | Mandatory capabilities per Decision B (stem ≥ 1, full rubric). Candidate list deferred until MD.5 lands. |
| MD.7 First 5 hybrids | "Hybrid ray-march + warp, 5 presets" | Per Decision E criteria. Candidate list per §5 above; first hybrid is a single-preset spike, then 4 more in batch. |

---

## §7. Risks and open questions

* **Transpiler may not reach feasible coverage on the expression
  sub-language alone.** If MD.1 reveals operator / function /
  variable usage in HLSL-free presets that's harder than expected,
  MD.2's "expression-only" scope might still struggle. Mitigation:
  MD.1 reports coverage percentage *over the HLSL-free subset*, not
  over the whole pack; that's the realistic target.
* **Evolved Milkdrop presets may be perceptually indistinguishable
  from ports.** Stem routing on a faithful Milkdrop reproduction may
  not surface as "evolved" to the listener. Mitigation: MD.6's first
  3 presets get an explicit A/B comparison in M7 review (port-only
  render vs evolved-render), and if the perceptual delta is weak,
  the strategy revisits whether MD.6 earns its 20-preset budget or
  collapses to a smaller "trial evolved" set.
* **License question (Decision I) gates public commit.** MD.1 is
  safe to run during counsel review; MD.2 onwards waits if I.3
  becomes the call. Mitigation: schedule counsel review concurrently
  with MD.1 authoring.
* **mv\_warp + ray-march composition has thin proof.** VL is the only
  current consumer. MD.7's first hybrid is a high-risk spike;
  mitigation is to schedule it as its own increment ("MD.7.0 hybrid
  spike") before batch-authoring 4 more.
* **Some cream-of-crop presets are author-personality-driven** (the
  same artist's signature ripple, the same fractal recursion). Phase
  MD's "another instrument in the band" framing assumes the preset
  responds to *the listener's music*, not its own internal artistic
  character. Mitigation: M7 review explicitly checks "does the music
  drive the visual?" alongside the rubric. Author-personality
  presets that don't bend to music are excluded.
* **Catalog story coherence.** 35 Milkdrop-origin presets (MD.5 +
  MD.6 + MD.7) is a meaningful share of the catalog. Risk: Phosphene
  starts to *feel* like "Milkdrop with a frontend" rather than a
  distinct product. Mitigation: D.2 per-tier settings toggles let
  the user dial down Milkdrop content; orchestrator scoring weights
  let the family-repeat penalty (Phase 4) prevent over-selection.
  Worth monitoring after MD.5 lands.

---

## §8. Acceptance — what "approved" means

Matt walks §3 decisions A through J and picks an option per decision
in §10 below. Picks become D-### entries filed in `docs/DECISIONS.md`
(next available number is D-103 per CLAUDE.md memory note; ten
decisions consume D-103 through D-112). `ENGINEERING_PLAN.md` Phase
MD section gets revised per §6.

After sign-off:

1. MD.1 (grammar audit) becomes a runnable session prompt.
2. Counsel review for Decision I is scheduled concurrently with
   MD.1.
3. CREDITS.md gains a placeholder "Milkdrop preset attribution"
   section (no content until MD.5 commits the first ports).
4. The 10 MD.5 candidates from §3 Decision J get committed to the
   plan as concrete preset filenames.

---

## §9. Citations

* [`docs/MILKDROP_ARCHITECTURE.md`](MILKDROP_ARCHITECTURE.md) — research
  basis; sections 1 through 7 inform the deviation primitives /
  mv\_warp / MV-3 architecture this strategy builds on.
* [`docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md`](diagnostics/MD-strategy-pre-audit-2026-05-12.md) —
  empirical findings backing §0 of the strategy doc.
* [`docs/DECISIONS.md`](DECISIONS.md) — D-026 (deviation primitives),
  D-027 (mv\_warp pass), D-028 (MV-3 capabilities), D-029 (motion
  paradigms not composable), D-039 (golden-hash regression), D-053
  (excludedFamilies scoring), D-067 (cert rubric profiles).
* [`docs/ENGINEERING_PLAN.md`](ENGINEERING_PLAN.md) Phase MD section —
  the increment specs this strategy refines.
* [`docs/SHADER_CRAFT.md`](SHADER_CRAFT.md) §12 — rubric details for
  lightweight vs full profile.
* [`docs/CREDITS.md`](CREDITS.md) — Open-Unmix HQ + Beat This!
  attribution patterns serve as the template for Decision I.
* `https://github.com/projectM-visualizer/presets-cream-of-the-crop` —
  the pack itself. ISOSCELES curator; LICENSE.md asserts
  public-domain-by-convention with takedown path via projectM.
* `https://www.patreon.com/posts/pack-nestdrop-91682111` — original
  pack release; for posterity.

---

## §10. Sign-off — Matt's picks

Walk each decision and record the pick. Each pick becomes a D-###
entry after this section is filled in.

* Decision A — Tier structure: **A.1 — Three tiers (Classic Port / Evolved / Hybrid)** (Matt 2026-05-12). Filed as D-103.
* Decision B — Mandatory vs opt-in capabilities matrix: **Accept matrix as recommended.** (Matt 2026-05-12). Filed as D-104.
* Decision C — Catalog presentation / naming: **C.2 — Three separate `family` values** (`milkdrop_classic` / `milkdrop_evolved` / `milkdrop_hybrid`). (Matt 2026-05-12). Filed as D-105.
* Decision D — Settings toggle exposure: **D.2 — Per-tier toggles with disclosure-row UX.** (Matt 2026-05-12). Filed as D-106.
* Decision E — Ray-march hybrid candidate criteria: **E.3 — Architectural + thematic + brand fit.** Accept three starters (Geiss *3D-Luz*, Rovastar *Northern Lights*, EvilJim *Travelling backwards in a Tunnel of Light*). (Matt 2026-05-12). Filed as D-107.
* Decision F — Per-stem hue affinity for Evolved: **F.2 — Opt-in per preset.** (Matt 2026-05-12). Filed as D-108.
* Decision G — Section-awareness for Evolved/Hybrid: **G.2 — Opt-in per preset.** (Matt 2026-05-12 — diverged from strategy recommendation G.3; `StructuralAnalyzer` becomes a usable surface during MD.6+ rather than waiting for separate validation. See D-109 for divergence note.). Filed as D-109.
* Decision H — Transpiler scope: **H.1 for MD.5; revisit for MD.6 / MD.7.** Expression sub-languages only; HLSL-bearing source presets excluded from MD.5; escalation path for MD.6 / MD.7 is H.3 (hand-port) not H.2 (cross-compiler dependency). (Matt 2026-05-12). Filed as D-110.
* Decision I — Licensing posture: **I.1 — MIT-derivative with `milkdrop_source` provenance metadata + CREDITS.md attribution + projectM-managed takedown.** (Matt 2026-05-12; amended 2026-05-12 to remove counsel-review gating — Matt as project lead accepts the residual legal risk; counsel review remains available as optional async due-diligence but is NOT a precondition for any Phase MD increment. See D-111 amendment block.). Filed as D-111.
* Decision J — MD.5 candidate list: **9 named presets + 1 TBD Geometric slot.** Hybrid J.3 (simplicity) selection + J.1 (theme coverage) check + J.2 (catalog gap) tiebreaker. Tenth Geometric slot picked at MD.5 authoring. (Matt 2026-05-12). Filed as D-112.

**Sign-off complete 2026-05-12.** D-103 through D-112 filed in `docs/DECISIONS.md`. Next runnable increment is MD.1 (`.milk` grammar audit), with the scope tightened per D-110 to focus on the expression sub-languages and a thin HLSL appendix. `CREDITS.md` placeholder section pending. `ENGINEERING_PLAN.md` per-increment scope revisions per §6 pending.

**Subsequent amendment 2026-05-12 (counsel-review gating removed).** After sign-off, Matt directed that counsel review must not block development. D-111 was amended to remove the counsel-sign-off gate on MD.2 onwards; risk-acceptance now lives on the project lead. Counsel review remains available as optional async due-diligence (`MILKDROP_COUNSEL_BRIEF.md` retained in tree as historical context). See D-111 amendment block + revision-history entry for 2026-05-12.

**Inspired-by reframe landed 2026-05-12 (§12).** A subsequent strategy-doc addendum (§12 below) reframes Phase MD from "derivative" to "inspired by" per Matt's post-sign-off review. Under the inspired-by framing, six existing decisions (D-103 / D-105 / D-106 / D-110 / D-111 / D-112) are amended in place; six new decisions (D-113 through D-118) land alongside. The §3 picks above remain the operative record of the *derivative-posture* framing prior to the reframe; §12 is the operative record of the *inspired-by* framing going forward.

---

## §11. Revision history

* 2026-05-12 — Initial draft authored by Claude Code session.
  Awaiting Matt sign-off in §10.
* 2026-05-12 — Matt sign-off in §10. All ten decisions (A through J)
  picked; eight match strategy recommendation; one (G) diverges
  (G.2 picked, G.3 recommended — see D-109 divergence note). D-103
  through D-112 filed in `docs/DECISIONS.md`.
* 2026-05-12 — Counsel-review gating removed from D-111 (Matt
  risk-acceptance; counsel review remains optional async due
  diligence). Amendment block appended to D-111; no §3 / §10 picks
  changed.
* 2026-05-12 — §12 addendum landed (inspired-by reframe). Six §3
  decisions amended (D-103 / D-105 / D-106 / D-110 / D-111 / D-112);
  six new decisions filed (D-113 — posture reframe; D-114 — release
  model; D-115 — release-bundle composition; D-116 — substantial-
  similarity discipline rule; D-117 — catalog-ratio framing;
  D-118 — read-only analysis tool scope). §§1–11 above stand as
  historical record of the derivative-posture framing.

---

## §12. Addendum — inspired-by reframe (2026-05-12)

This section supersedes §§1–11 above where the two conflict. §§1–11
remain in place as the operative record of the *derivative-posture*
framing they were authored under; the operative record going forward
is this addendum.

### §12.1 Reframe summary + why

The base strategy (§§1–11) was authored under a "derivative work"
posture: mechanically transpile `.milk` → Phosphene `.metal`, ship
the output as MIT-derivative with provenance + attribution, treat
each port as a faithful reproduction with audio-coupling uplifts.
Matt's 2026-05-12 post-sign-off review reframed the work as
**"inspired by"** — every Milkdrop-influenced Phosphene preset is a
**new creation that takes inspiration from a source preset's concept
and aesthetic**, implemented from scratch on Phosphene's primitives.
The transpiler / mechanical-port framing is retired.

**Why it matters.** The reframe is operative on three axes
simultaneously:

1. **Legal posture.** "Inspired by" is the framing Phosphene asserts
   externally; the file enumerates source concepts honored, not
   source code copied. The CREDITS.md attribution stays; the
   substantial-similarity discipline rule (§12.5 / D-116) becomes
   the load-bearing authoring-time constraint.
2. **Scale.** The initial planning target widens from ~35 presets
   (§5) to **~200 inspired-by uplifts**. At ~2–3 days per preset
   authored to certification, this is a multi-year work stream, not
   a finite phase.
3. **Release model.** Phosphene's *first* release ships at **20
   presets** (a mix of Phosphene-native + Milkdrop-inspired; §12.4
   / D-114). Ongoing uplift batches ship at weekly / monthly /
   quarterly cadence after first release (cadence is a
   release-management decision deferred to release planning, not
   in this addendum's scope).

The base strategy's nine-step per-preset workflow (§4) is
substantially obsoleted. The replacement workflow is straightforward:
read the source `.milk` file as reference material, understand its
aesthetic intent, author a new Phosphene preset from scratch using
Phosphene's primitives (V.1–V.4 utilities, mv_warp, ray_march, stem
routing, MV-3 capabilities), apply the substantial-similarity
discipline rule, pass M7 review, certify. The transpiler-and-uplift
workflow assumed in §§4 / 6 is no longer how the work happens.

### §12.2 Decision revisions table

Six §3 picks are revised by the reframe. The originals remain in §3
(historical record); the revised forms are filed as amendment blocks
on the respective D-### entries in `docs/DECISIONS.md` and summarized
below.

| Decision | Original (§3 / §10) | Revised (§12) | Mechanism |
|---|---|---|---|
| **D-103 — Tier structure** | Three tiers: Classic Port / Evolved / Hybrid. | **Single tier: `milkdrop_inspired`.** Every uplift is a new creation; tiering on fidelity-to-source re-introduces "derivative" connotation. Authoring fidelity is governed by the discipline rule (§12.5), not by tier. | Amendment block on D-103. |
| **D-105 — Catalog presentation** | Three `family` values (`milkdrop_classic` / `_evolved` / `_hybrid`). | **One `family` value: `milkdrop_inspired`.** Filesystem path stays `PhospheneEngine/Sources/Presets/Shaders/Milkdrop/<theme>_<source_name>.{metal,json}`. | Amendment block on D-105. |
| **D-106 — Settings toggle exposure** | Three per-tier toggles in disclosure row. | **One toggle:** `phosphene.settings.visuals.milkdrop.inspired`. Defaults to `true` once first inspired-by preset ships. | Amendment block on D-106. |
| **D-110 — Transpiler scope** | Expression sub-languages only; HLSL excluded. | **Transpiler retired.** Source `.milk` files become *reference material*, read by authors. HLSL-bearing presets are no longer excluded by tooling — every preset in the 9,795-pack is a viable inspiration source. MD.1 grammar audit is preserved but reframed (§12.7 / §12.9). | Amendment block on D-110. |
| **D-111 — License / attribution** | MIT-derivative with `milkdrop_source` provenance block; pre-release notification protocol. | **Inspired-by posture.** Provenance schema renamed `inspired_by` (see below); notification protocol retired (§12.8 / D-113 / amendment block on D-111). CREDITS.md "Milkdrop preset attribution" section becomes a "Milkdrop-inspired preset attribution" section. | Amendment block on D-111. |
| **D-112 — MD.5 candidate list** | 9 named + 1 TBD Geometric, HLSL-free subset only. | **HLSL-free constraint dissolves** (all 9,795 presets become viable inspiration sources). The 10-preset list reframes as the **initial inspiration batch for the 20-preset first-release bundle** (§12.4 / D-114). Specific candidates remain operative as inspiration sources unless substituted at authoring. | Amendment block on D-112. |

**`inspired_by` provenance schema (revises D-111's `milkdrop_source`).** Each Milkdrop-inspired Phosphene preset's JSON sidecar carries:

```json
"inspired_by": {
  "milkdrop_filename": "<original .milk filename>",
  "original_artist": "<author from filename pattern, best-effort>",
  "pack": "projectM-visualizer/presets-cream-of-the-crop",
  "sha256": "<SHA256 of source .milk file>"
}
```

The `theme` field from the derivative-era schema is dropped (theme
classification was useful for transpiler tier assignment; under
inspired-by it adds no signal). Other fields preserved verbatim. The
`milkdrop_source` block in any in-tree JSON written under the
derivative posture stays valid until rewritten — there are no such
files in tree yet (Phase MD has not committed any inspired-by
preset).

### §12.3 New decisions filed

| D-### | Title | Status |
|---|---|---|
| **D-113** | Phase MD posture reframe — inspired-by, not derivative-of. Operative legal framing. | Filed 2026-05-12. |
| **D-114** | Phase MD release model — 20-preset first-release bundle. Post-release cadence deferred to release planning. | Filed 2026-05-12. |
| **D-115** | Phase MD release-bundle composition — Phosphene-native vs Milkdrop-inspired split. Question framed; Matt's call. | Filed 2026-05-12 with proposal pending sign-off. |
| **D-116** | Phase MD substantial-similarity discipline rule. Authoring-time constraint; lives in `SHADER_CRAFT.md §12.6`. | Filed 2026-05-12. |
| **D-117** | Phase MD catalog-ratio framing — steady-state Phosphene-native vs Milkdrop-inspired fraction. Question framed; explicit decision deferred. | Filed 2026-05-12 (deferred). |
| **D-118** | Phase MD read-only analysis tool — ship vs skip. Recommend skip; MD.1 grammar audit doc covers the use case. | Filed 2026-05-12. |

Full text for each lives in `docs/DECISIONS.md`.

### §12.4 Release model — the 20-preset first-release bundle

**Threshold.** Phosphene's first release ships when the production
catalog reaches **20 presets** that are all M7-certified and pass
the full V.6 rubric (`rubric_profile` matched per preset). Mix of
Phosphene-native + Milkdrop-inspired (composition framed in §12.4.1
/ D-115).

**Why 20.** Enough breadth that a 60–90 minute listening session
can rotate without preset repetition fatigue (Phase 4 family-repeat
penalty handles within-bundle rotation). Small enough that every
preset can clear M7 before release ships. Above the 1-preset
"shipping demo" threshold (Lumen Mosaic alone) without committing
to the multi-year "full catalog" target.

**Post-release cadence.** Weekly / monthly / quarterly batch
schedule for ongoing uplifts is a release-management decision
deferred to release planning. Not in this addendum's scope. The
20-preset bundle is the unit; cadence is the rhythm.

**Current state vs threshold (2026-05-12):**

* **Certified (1):** Lumen Mosaic (cert flipped at LM.7, 2026-05-12).
* **Production-but-not-all-certified (~14):** Arachne, Aurora Veil
  pending, Fractal Tree, Gossamer, Glass Brutalist, Kinetic
  Sculpture, Murmuration, Nebula, Plasma, Spectral Cartograph
  (diagnostic — excluded from auto-selection per D-074), Stalker,
  Starburst, Volumetric Lithograph, Waveform. Each one M7 + cert
  review away from counting toward the bundle.
* **Gap to 20:** 6+ presets, source TBD per §12.4.1 / D-115.

#### §12.4.1 Release-bundle composition (D-115, framed; Matt's call)

The 20 presets in the first release are a mix. The question is the
mix.

* **Proposal A — 10 + 10.** Ten Phosphene-native (mostly already
  authored, awaiting M7 + cert) + ten Milkdrop-inspired (new
  authoring against the §12.3 candidate batch). Balanced register;
  the catalog reads as "Phosphene's own work" *and* "Phosphene
  honoring the Milkdrop tradition" at equal weight.
* **Proposal B — 5 + 15.** Five Phosphene-native + fifteen
  Milkdrop-inspired. Honoring-the-tradition reads louder at
  first-release; sets a clear expectation that the catalog is
  Milkdrop-inspired in character.
* **Proposal C — 15 + 5.** Fifteen Phosphene-native + five
  Milkdrop-inspired. Phosphene's own identity reads louder; the
  Milkdrop-inspired register is a clear minority at first.

**Recommendation (Claude Code session, not Matt's call):**
**Proposal A (10 + 10).** Reasons: (a) ~14 production Phosphene-
native presets already authored — getting 10 of them through M7 +
cert in the release-bundle work window is feasible; (b) 10
Milkdrop-inspired uplifts at 2–3 days each is ~3–4 weeks of
sustained authoring, large but bounded; (c) the 50/50 balance
matches the inspired-by framing — the catalog is *new creations*
that *honor* Milkdrop, not a Milkdrop pack with a Phosphene minority
or a Phosphene catalog with a Milkdrop garnish. Matt picks; the
pick lands as the operative form of D-115.

### §12.5 Substantial-similarity discipline rule (D-116)

The authoring-time constraint that operationalizes "inspired by, not
derived from." Lives in `SHADER_CRAFT.md §12.6` as a new subsection
of the Fidelity Rubric chapter. Cross-references Failed Approach #48
("§10.1-faithful but reference-divergent visual outputs") and D-116.

**Rule (short form).** A Milkdrop-inspired Phosphene preset must be
a **new creation**, not a reproduction. Specifically:

1. **No source equations copy-pasted into Phosphene shader code.**
   The author reads the `.milk` file to understand the aesthetic
   intent; the Phosphene `.metal` is written from scratch.
2. **No source shader logic ported line-for-line.** Where the source
   `.milk` carries HLSL `warp_1=…warp_NN=` blocks, the Phosphene
   equivalent is authored against Phosphene's `mv_warp` /
   `mvWarpPerVertex` primitives, not by mechanically translating
   the HLSL surface. The shape of the motion may resemble the
   source's; the implementation is Phosphene-native.
3. **The visual structure may differ from the source.** A
   Milkdrop-inspired Phosphene preset can honor a source's concept
   (e.g. "kaleidoscope of tessellating triangles") while
   substituting a different visual structure (e.g. SDF-based
   tessellation rather than per-pixel-grid feedback warp) if that
   produces a stronger Phosphene-native result.
4. **Source `.milk` files are not redistributed.** They are read
   from a developer-local checkout of the cream-of-crop pack; the
   pack stays at its source URL. Phosphene ships only the new
   Phosphene-native creations (`.metal` + `.json`) that took the
   `.milk` files as inspiration.

Full rubric text in `SHADER_CRAFT.md §12.6`. The rule applies to
Milkdrop-inspired uplifts specifically — Phosphene-native presets
(Aurora Veil, Crystalline Cavern, Phase G-uplift catalog members)
are unaffected.

### §12.6 Catalog-ratio framing (D-117, deferred)

**Question:** at steady state — call it ~200 inspired-by uplifts
plus the ongoing Phase G-uplift / Phase AV / Phase CC / Phase MV
work — what fraction of the catalog is Phosphene-native vs
Milkdrop-inspired?

**Why it matters.** Three forces compound:

1. **Authoring economics.** Milkdrop-inspired uplifts are typically
   faster than from-scratch Phosphene-native presets — the source
   `.milk` provides aesthetic anchor and audio-coupling skeleton,
   reducing the design surface the author has to invent. Default
   gravity pulls toward higher Milkdrop-inspired share.
2. **Brand identity.** If the steady-state catalog is, say, 80 %
   Milkdrop-inspired, Phosphene's brand identity becomes "the
   Milkdrop renderer with modern fidelity" rather than "a new
   music-visualization product that takes inspiration from
   Milkdrop." Pulls toward lower Milkdrop-inspired share.
3. **Community ratio (future).** When preset development opens to
   community contributors (notification-protocol phase, §12.8 / D-113),
   community submissions will likely skew toward Milkdrop-inspired
   uplifts — the source library is large and well-known. Without a
   ceiling, community contributions could shift the catalog ratio
   sharply within months.

**Decision deferred.** The question gets an explicit answer once
the 20-preset first-release bundle ships and steady-state catalog
growth is observable. Provisional working assumption (not a
decision): aim for **rough parity (50 / 50 ± 20 %)** at steady
state, with Milkdrop-inspired ceiling enforced via Phase 4
orchestrator-side family weighting if the ratio drifts too far. The
mechanism (orchestrator family weight) already exists (D-053
`excludedFamilies` is the floor; family weighting is a complementary
lever).

**Trigger to decide.** When the catalog reaches ~40 presets total
(20-bundle release + ~20 more uplifts), revisit. Filed as a
backlog-implied future decision in this addendum; D-117 stays
"open / deferred" until then.

### §12.7 Read-only analysis tool scope (D-118)

The §3 Decision H (D-110) committed to a transpiler with a defined
expression-language scope. The reframe retires the transpiler. The
question is whether a *replacement* read-only analysis tool ships.

* **D-118.1 — Ship a read-only analysis tool.** Scope: `.milk`
  parser + AST + pretty-print. Optional: per-`.milk`-file frequency
  analysis (which variables, functions, audio bands the source
  uses) to help authors understand the source's audio-coupling
  fingerprint before drafting the Phosphene-native uplift.
* **D-118.2 — Skip; rely on MD.1 grammar audit + author manual
  reading.** Authors read `.milk` files manually (they are small,
  1–20 KB, C-like syntax). The MD.1 grammar audit doc serves as
  the variable / function reference. No standalone tool.

**Recommendation: D-118.2 (skip).** Reasons: (a) authors already
read every source material end-to-end before authoring (mandatory
per Authoring Discipline rules in CLAUDE.md — "Articulate the
musical role before authoring anything" + Failed Approach #39
"authoring without reference images"); a read-only tool duplicates
that work without adding signal. (b) MD.1's grammar audit already
catalogs the variable / function / operator surface across the
full pack. A second tool is unnecessary infrastructure. (c) The
authoring sessions that produce inspired-by Phosphene presets are
the Phase MD work; spending one of those sessions on tool-building
is opportunity cost against actual catalog growth.

**Locks in:** MD.2 (transpiler CLI) is retired entirely (see §12.9
/ ENGINEERING_PLAN.md revisions). MD.1 grammar audit is preserved
and reframed (read-only understanding aid; §12.9). MD.3 hand-port
playbook becomes obsolete (no automated translation, no hand-port
either — inspired-by authoring replaces both).

### §12.8 Notification protocol deferral (per D-113)

The base strategy's I.1 license posture committed to honoring
takedown requests routed through projectM (per the pack's stated
posture). It did *not* commit to a pre-release notification
protocol — but iterative-design discussion under the derivative
posture had suggested "notify original Milkdrop preset authors of
each Phosphene port before public release."

**Resolution under inspired-by:** notification protocol is
**retired for the pre-community phase**. Rationale:

1. **Pre-community: no third-party authors.** Until Phosphene opens
   preset development to community contributors, all
   Milkdrop-inspired Phosphene presets are authored by Matt + Claude
   Code. Notification before any third-party-authoring infrastructure
   exists is a checkbox exercise, not a community protocol.
2. **Pack takedown path covers the response surface.** The pack's
   stated takedown protocol (preset authors contact projectM team)
   routes through the upstream curator. Phosphene honors takedowns
   per that path (per D-111).
3. **Inspired-by framing reduces the surface anyway.** A new
   creation that honors a source concept is materially different
   from a faithful port; the "did you know we ported your preset?"
   communication shape no longer fits the work.

**Trigger to reopen:** when Phosphene opens preset development to
community contributors. At that point a notification protocol
becomes load-bearing community infrastructure (community submissions
that derive heavily from named source presets warrant pre-publication
review). Separate phase, separate prompt, not Phase MD. D-113
records the deferral; reopening will produce a new D-### entry.

### §12.9 Carry-forward — what changes for MD.1, MD.2, MD.5+

The §6 phased-plan revision table is largely obsoleted. The
inspired-by reframe restructures the increment scopes:

| Increment | Pre-reframe scope (§6) | Post-reframe scope (§12) |
|---|---|---|
| **MD.1 grammar audit** | Empirical grammar audit unblocking MD.2 transpiler. | **Retained, reframed.** Audit becomes a read-only *author's reference* for understanding `.milk` source files. Coverage is no longer load-bearing (no transpiler to feed). HLSL-free / HLSL-bearing split dissolves (no transpiler-input filter). MD.1 prompt revised at §4 of this session. |
| **MD.2 transpiler CLI** | Lex `.milk`, emit Swift AST, reject HLSL-bearing. | **Retired entirely.** No transpiler. No `PhospheneTools/MilkdropTranspiler` SPM target. |
| **MD.3 JSON emission + HLSL hand-port playbook** | Transpiler emits `PresetDescriptor` JSON; separate hand-port doc for HLSL. | **Retired entirely.** Hand-port playbook obsolete; inspired-by authoring replaces both translation modes. |
| **MD.4 Per-vertex Metal emission** | Transpiler emits `mvWarpPerVertex` bodies. | **Retired entirely.** Authors write `mvWarpPerVertex` bodies directly per the per-preset session. |
| **MD.5 First 10 cream-of-crop ports** | 10 Classic Port presets via transpiler. | **Reframed as "first inspired-by batch."** 10 Milkdrop-inspired Phosphene presets, hand-authored under the substantial-similarity discipline rule (§12.5 / D-116). Source candidates from D-112 list (HLSL-free constraint dissolves; substitutions encouraged where a better inspiration source surfaces). This batch contributes to the 20-preset first-release bundle (§12.4 / D-114). |
| **MD.6 Next 20 evolved-tier** | 20 Evolved-tier presets via transpiler + stem uplift. | **Reframed as "ongoing inspired-by uplifts."** No tier distinction; each preset hand-authored. Stem routing is per-preset authoring choice, not tier-mandated. Composition of this batch is part of the multi-year work stream, not the 20-preset first-release bundle. |
| **MD.7 Hybrid ray-march + warp** | 5 Hybrid-tier presets with ray-march backdrop. | **Reframed as "inspired-by uplifts that compose mv_warp + ray_march."** Architectural composition is per-preset authoring choice. The MD.7.0 spike (Geiss *3D-Luz* recommended) is still a valuable proof-of-composition increment under inspired-by — but the deliverable is one Phosphene-native preset that takes Geiss *3D-Luz* as inspiration, not a port. |

ENGINEERING_PLAN.md is revised in §6 of this session (separate commit).

---
