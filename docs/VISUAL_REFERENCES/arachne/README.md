# Visual References — Arachne

**Family:** organic
**Render pipeline:** direct_fragment (2D SDF, per D-043) + mv_warp
**Rubric:** full (gated by V.6 certification; uplift target is V.7)
**Last curated:** 2026-05-03

> **Architectural reminder.** Per D-043, Arachne is permanently ruled out of 3D ray
> march. Fine-structure presets (silk, fibers, filaments) require sub-pixel SDF
> evaluation at screen resolution; 3D miss-ray glow swamps strand detail and the
> result reads as "sand dollars or dart boards" (session 2026-04-22T14-13-58Z).
> All references and traits below assume a 2D SDF direct-fragment shader.

> **2026-05-03 extension.** References 11–19 were added to support the V.7.7+
> spec rewrite, which treats Arachne as three pillars at equal fidelity: **THE
> WORLD** (forest as fixed stage), **THE WEB**, and **THE SPIDER** (the
> easter-egg, upgraded from V.7.5's dark silhouette). The original
> macro→meso→micro→specular cascade (refs 01–10) remains the primary
> certification target; the extension set adds anchor structure, spider anatomy
> & material, and forest-world detail.

> **2026-05-05 material-priority decision.** For Arachne v8, droplets are the primary fidelity carrier. Silk is secondary. Keep axial silk highlights as a minor lighting effect, but do not implement full Marschner-lite as the first material priority. Prioritize refractive droplet material, sag, irregular geometry, and world interaction.

## Reference images

Files in this folder, ordered to walk the detail cascade (§1.2) from macro to micro to specular, then atmosphere/lighting, then palette anchor, then anti-references. References 11–19 are appended in the order they support: web-anchoring (11), spider anatomy (12–14), forest-world atmosphere/detail (15–18), spider eye specular (19). Each name encodes the trait it demonstrates per `../_NAMING_CONVENTION.md`. References should be ≤ 500 KB each; crop and compress before committing.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_dewy_web_on_dark.jpg` | **Hero image.** The single most important "must match" frame. Shows the full detail cascade in one shot: orb-weaver macro silhouette, per-strand meso variation (visible sag differences along longer radials), micro droplet beading at 8–12 px spacing on the spiral, and mirror-specular highlights on each droplet. Treat the warm dew highlights as the visual analog for bioluminescent emission peaks. |
| `02_meso_per_strand_sag.jpg` | Each radial thread sags differently based on its length; spiral threads micro-wobble. No two strands identical in tension/sag. The asymmetric, weathered character is the meso target — geometric perfection is a failure mode. |
| `03_micro_adhesive_droplet.jpg` | Adhesive droplets at 8–12 px spacing along **spiral threads only** (radial spokes are glue-free per silk biology). Dielectric droplets read as small spheres with bright pinpoint highlights. The dark-with-dim-bokeh background isolates the beading pattern that hash-lattice droplet placement must reproduce. |
| `04_specular_silk_fiber_highlight.jpg` | The narrow axial specular highlight running along the length of a silk fiber. Use this as a **minor lighting reference only**: silk may catch a subtle axial glint where the key light grazes the strand, but full Marschner-lite silk is no longer the primary material target for Arachne v8. At normal Arachne scale, droplets, sag, irregular geometry, and world interaction carry fidelity; silk remains connective tissue between droplet chains. |
| `05_lighting_backlit_atmosphere.jpg` | Warm rim back-light + atmospheric haze + the "nature-documentary close-up at dawn" mood from §10.1. Spider visible in frame is incidental, not the subject — it's a 1-in-10-song easter egg, not the visual anchor. Do not over-render the spider on the basis of this image. |
| `06_atmosphere_dark_misty_forest.jpg` | Volumetric fog density and cool blue-grey palette anchor. Stacked tree layers fading into mist communicate the spatial depth that the "web reads against air, not void" quality requires. Cool palette is intentional — it gives refractive droplets and faint silk glints something physical to catch and bend. The dark base also signals: atmosphere stays *behind* and *darker than* the web at all times. A bright atmospheric reference would pull a session toward overcast-melancholy aesthetics, which is a different family. |
| `07_atmosphere_dust_light_shaft.jpg` | Suspended dust motes catching light in a directional beam. Multiple distinct shafts visible, with airborne particulate readable as discrete points scattering through each beam. Informs both §12.3 strongly-preferred trait #3 (dust motes) and the directional rim-light behavior in §10.1.6. The image's warm tone is incidental — for *mote density and beam structure only*, NOT palette. The Arachne mote field is cool-toned per the overall palette, not warm. |
| `08_palette_bioluminescent_organism.jpg` | The emission-as-light-source quality target. Translucent blue body with brighter emission peaks against pure black. This is the palette and material-emission character Arachne's droplets and faint silk accents may evoke — biological luminescence with a soft base glow plus discrete brighter accents, NOT stylized graphic glow. The pure-black background is also a calibration reference for the silence state (`totalStemEnergy == 0`) — the preset must read against deep black, not styled darkness. Without this image as a positive anchor, "bioluminescent" gets misread as "neon" (see `10_anti_neon_stylized_glow.jpg`). |
| `09_anti_clipart_symmetry.jpg` | **NOT this — failure mode #1: clipart.** Perfect 8-fold rotational symmetry, constant stroke width, regular concentric spiral, single point hub, no per-strand variation, no materiality, no droplets, no atmosphere. The literal §1.2 "Arachne v3 reads as clipart" failure mode in iconographic form. If the rendered output could be flat-traced into this silhouette, the preset is uncertified by definition. |
| `10_anti_neon_stylized_glow.jpg` | **NOT this — failure mode #2: stylized graphic glow.** The misinterpretation of "bioluminescent" as "sci-fi neon." Pure-saturation blue strokes on black, no biological asymmetry, no droplet detail, no per-strand sag, no documentary realism. Distinguishable from `09` (which fails by being flat-graphic) — this fails by being graphic-glow. The §10.1 target is *biological emission with documentary realism*, not stylized vector art with luminescence. The bioluminescent jellyfish (`08`) anchors the correct interpretation; this image shows the easy wrong one. |
| `11_anchor_web_in_branch_frame.jpg` | **Web anchored to the world.** Outer web frame is bounded by an irregular polygon of branch attachments at multiple positions — NOT a circular frame. Informs the §1.2 frame-thread phase and the V.7.7+ "anchor-to-world" requirement: outermost radials terminate on real branches in the near-frame layer, and the attachment points are PART of the web, not an afterthought. Spider visible at hub is bonus context (treat as incidental, same handling as `05`). |
| `12_spider_orb_weaver_dorsal.jpg` | **Orb-weaver dorsal anatomy in web.** Top-down view of the spider on web center. Cephalothorax + abdomen proportions, leg arrangement, abdominal stripe pattern all readable. Use this as the anatomical baseline for the V.7.7+ spider section: segmented body, articulated 8 legs, dorsal pattern. Web context shows the in-hub posture the spider holds at rest. |
| `13_spider_orb_weaver_lateral.jpg` | **Orb-weaver lateral leg articulation.** Side view showing femur / patella / tibia / metatarsus / tarsus segments along each leg, plus relative leg-to-body proportion. Informs the gait/IK section: leg joints must be visible in articulation, not a single rigid spline per leg. The golden-silk web context is incidental. |
| `14_spider_iridescent_chitin.jpg` | **Bioluminescent chitin material reference.** Vivid blue iridescent carapace on a velvety hairy body, with thin-film-style color variation across the abdomen and legs. This is the §4.18 `mat_bioluminescent_chitin` target for the rare easter-egg spider — biological iridescence, NOT neon. Note: this is a tarantula in a funnel-web burrow, not an orb-weaver. Use this image for **material recipe only** (chitin + thin-film + hair); use `12` and `13` for orb-weaver anatomy. The funnel-style web texture surrounding the spider is also a wrong web archetype — DO NOT match the surrounding silk to this image. |
| `15_atmosphere_aurora_forest.jpg` | **High-arousal psychedelic mood point.** Green aurora ribbons across a starfield over coniferous tree silhouettes. Informs the high-arousal end of the atmospheric color field — when continuous energy peaks during a psychedelic / late-night track, the world's sky-band can drift into aurora-like ribbons of cool emission. Trees stay as dark silhouettes; the aurora is the ATMOSPHERE, not a foreground element. Cool palette consistent with `06`, but with directional ribbon structure instead of uniform fog. |
| `16_atmosphere_dappled_pine_forest.jpg` | **High-valence high-arousal warm-energetic mood point.** Bright midday sun through a coniferous forest, with dappled light on grass and trunks. Use this as the warm-bright atmospheric extreme (counterpoint to `06`'s dark cool default). When `f.bass_att_rel` and `f.mid_att_rel` are sustained-high on warm-genre tracks, the world's atmospheric color field can drift here. Note: even at this bright extreme, the web should still read DARKER than the atmosphere behind it per §10.1.5 — the web silhouette is the foreground subject. |
| `17_floor_moss_leaf_litter.jpg` | **Forest floor / bottom-of-frame ground layer.** Damp moss + decaying leaves + scattered twigs + small pine cones. Informs the ground-layer detail at the bottom edge of the frame in the V.7.7+ world model. Cool damp palette (greens + browns + decay-greys) consistent with `06`. Density of detail here sets the resolution target: the ground layer must be readable as forest floor, not abstract texture. |
| `18_bark_close_up.jpg` | **Near-frame branch surface micro-detail.** Deeply furrowed bark with vertical ridge structure, brown-grey palette, sharp relief. This is the surface texture for the near-frame branch layer — branches that the web's outer radials anchor to (see `11`). Informs the bark normal/displacement detail when a branch passes close to camera. The high-contrast ridges should NOT bleed into rim-light blooming on the silk; bark stays matte and absorbing while silk catches highlights. |
| `19_spider_eye_specular.jpg` | **Specular highlight on chitinous eye lens.** Macro showing the bright pinpoint reflections on the principal eyes of a spider. Informs the §4.18 spider-easter-egg material question: should the eyes carry a tiny mirror-specular sparkle? This image says yes — a single bright dot per eye lens reads as alive, not glassy. **Note: this is a jumping spider (Salticidae), not an orb-weaver. Orb-weaver eye clusters are smaller and more uniform — 8 small eyes in a tight cluster, not 2 large forward-facing principal eyes.** Use this image for the SPECULAR HIGHLIGHT QUESTION only; do not use it as anatomical reference for the Arachne spider's eye configuration. |

## Mandatory traits (per SHADER_CRAFT.md §12.1)

For Arachne specifically:

- [ ] **Detail cascade:**
  - macro = orb-weaver web silhouette (hub + 11–17 jittered radials + Archimedean capture spiral, per `arachneEvalWeb()` and D-041 web-pool structure); reference `01_macro_dewy_web_on_dark.jpg`
  - meso = per-strand sag/tension variation (longer threads droop more, per `02_meso_per_strand_sag.jpg`); ±22% per-spoke angular jitter; per-web hub-offset and strand-count jitter
  - micro = adhesive droplets on spiral threads only, hash-lattice placed at 8–12 px spacing per `03_micro_adhesive_droplet.jpg`
  - specular = mirror specular on refractive droplets as the primary fidelity carrier + subtle axial silk glints per `04_specular_silk_fiber_highlight.jpg` as a secondary lighting effect
- [ ] **Web-to-world anchor structure (V.7.7+):** outer frame is an irregular polygon of 4–7 branch-attachment points, not a circle; outermost radials terminate on near-frame branches with a small adhesive blob at the join. Reference `11_anchor_web_in_branch_frame.jpg`.
- [ ] **Hero noise function(s):** `fbm8` for per-strand micro-wobble and dust-mote density field; `hash_u32/f01` family for per-web seed jitter and droplet placement (from `Shaders/Utilities/Noise/`).
- [ ] **Material count and recipes (≥ 3):**
  - dielectric droplet material (clear refractive spherical cap with world-texture refraction, Fresnel rim, dark edge ring, and pinpoint specular) — **primary fidelity carrier**
  - `mat_silk_thread` — secondary connective strand material with thin translucent linework and subtle axial glints only; do **not** prioritize full Marschner-lite for v8
  - bioluminescent emission haze (rim-emission term per §5.3) — counts as third material/lighting recipe
  - `mat_bioluminescent_chitin` (§4.18) — for the rare spider easter egg only (D-040; ~1-in-10 songs); reference `14_spider_iridescent_chitin.jpg` for chitin + thin-film material recipe (NOT for surrounding web/anatomy)
- [ ] **Audio reactivity (D-026 deviation primitives only):**
  - silk emission intensity scaled by `stems.drums_energy_dev` (positive-only, zero at AGC center)
  - dust-mote density modulated by `f.mid_att_rel` (slow continuous breathing)
  - hub gentle pulsation on `f.beat_phase01` anticipation curve (MV-3b), **not** free-running `sin(time)` (rule from 3.5.5 post-session tuning)
  - **No absolute thresholds.** Reject any `smoothstep(0.22, 0.32, f.bass)` style pattern (D-026).
- [ ] **Silence fallback (D-019):** at `totalStemEnergy == 0`, blend via `smoothstep(0.02, 0.06, totalStemEnergy)` to FeatureVector proxies — silk emission falls back to `f.bass_dev * 0.6`; dust density falls back to a static low floor. Two pre-seeded stable webs guarantee D-037 invariants 1 and 4 from frame zero (per `ArachneState` seeding). Reference `08_palette_bioluminescent_organism.jpg` for the silence-state palette anchor — deep black background with soft emission readability.
- [ ] **Performance ceiling:** ≤ 5.5 ms p95 at 1080p Tier 2 (matches `complexity_cost.tier2 = 5.5` in JSON sidecar; refractive droplet evaluation and world-texture sampling are expected to dominate cost).
- [ ] **Hero reference image:** `01_macro_dewy_web_on_dark.jpg`. If a session only matches one frame, match this one.

## Expected traits (per §12.2 — at least 2 of 4)

- [ ] **Triplanar texturing on non-planar surfaces** — n/a in 2D SDF; surfaces are evaluated in screen UV. Not applicable.
- [ ] **Detail normals** — applicable first to near-frame bark and branch surfaces per `18_bark_close_up.jpg`; bark normal/displacement gives the world depth that makes the web read as foreground. Silk micro-displacement is optional and secondary; do not let it displace the refractive droplet work.
- [ ] **Volumetric fog or aerial perspective** — applicable. Soft 0.02 fog and a gentle dust-mote field behind the web make it read against air, not void. Mandatory per §10.1.5; references `06_atmosphere_dark_misty_forest.jpg` (volume + palette default), `07_atmosphere_dust_light_shaft.jpg` (mote density), `15_atmosphere_aurora_forest.jpg` (high-arousal sky variant), `16_atmosphere_dappled_pine_forest.jpg` (high-valence warm variant).
- [ ] **SSS / fiber BRDF / anisotropic specular** — applicable but **secondary for Arachne v8.** Full Marschner-lite silk is no longer the first material priority. Keep a restrained axial highlight per `04_specular_silk_fiber_highlight.jpg` only where the key light grazes a strand. The largest fidelity lift is the refractive droplet system working against a real WORLD pass, plus sag, irregular geometry, and atmospheric depth.

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [ ] **Hero specular highlight in ≥60% of frames** — applicable. Droplet mirror specular sparkles on capture-spiral threads should carry this requirement in most frames. Silk axial highlights are allowed as subtle secondary glints, not the dominant visual event. Reference `03_micro_adhesive_droplet.jpg` for bead spacing/material priority, `04_specular_silk_fiber_highlight.jpg` for restrained strand glints, and `19_spider_eye_specular.jpg` for spider eye sparkle when the easter egg is on screen.
- [ ] **Parallax occlusion mapping** — n/a in 2D SDF. Not applicable.
- [ ] **Volumetric light shafts or dust motes** — applicable and recommended. Dust-mote field at low density behind the web; faint god-ray hint from the rim back-light direction. Reference `07_atmosphere_dust_light_shaft.jpg`.
- [ ] **Chromatic aberration / thin-film interference** — applicable on the spider easter-egg carapace only (§4.18 bioluminescent chitin's iridescent thin-film, per `14_spider_iridescent_chitin.jpg`). Skip on silk to preserve documentary realism (Gossamer V.8 owns chromatic aberration on wave peaks; not Arachne).

**Score target:** 2/4 strongly preferred (hero specular, dust motes).

## Anti-references — two distinct failure modes

The anti-references cover two different ways a Claude Code session can produce a wrong-but-plausible Arachne. Both must be avoided.

**Failure mode #1 — Clipart (`09_anti_clipart_symmetry.jpg`).** The shader produces output that, if traced flat, would resemble a Halloween-decoration spiderweb. Symptoms: rotationally symmetric radials at exact angles, constant strand width, no per-segment variation, regular concentric spiral, single-point hub with no cap, no refractive droplets on capture spiral, no per-strand sag, and no world interaction. The §1.2 description of Arachne v3.

**Failure mode #2 — Stylized neon glow (`10_anti_neon_stylized_glow.jpg`).** The shader correctly avoids clipart symmetry but interprets "bioluminescent" as "neon vector art." Symptoms: pure-saturation single-hue glow (typically electric blue or magenta), uniform stroke emission with no biological asymmetry, no droplet detail, no atmospheric volume, scene reads as graphic-design poster rather than nature-documentary close-up. The bioluminescent jellyfish (`08`) is the correct interpretation; this image shows the wrong one.

**Other failure modes (no images, but called out):**

- **Sand-dollar / dart-board appearance.** The 3D ray-march failure mode (D-043). Miss-ray glow forms a soft circular halo regardless of strand position. If this is observed, the SDF evaluation has fallen back to disc-boundary distance — return to 2D SDF immediately.
- **Spider as primary subject.** The spider is a 1-in-10-song easter egg with 5-min cooldown (D-040). If the spider dominates a frame, the trigger logic or render weight is wrong. Note that V.7.7+ upgrades the spider's per-appearance fidelity (refs 12–14, 19) but does NOT change the trigger frequency or cooldown.
- **Wrong web archetype on the spider.** The chitin-material reference `14` shows a tarantula in a funnel-web burrow. Surrounding silk in that image is NOT the Arachne web archetype. Arachne is strictly orb-weaver (radials + Archimedean capture spiral); refs 11 and 01 are the web-structure targets.
- **Free-running `sin(time)` motion.** All oscillation must be beat-anchored or audio-amplitude-gated (rule established in 3.5.5 post-session tuning).
- **Beat-dominant motion.** Continuous energy must be the primary visual driver per CLAUDE.md §Audio Data Hierarchy. Beat pulses are accents only; `base_zoom` should be 2–4× larger than `beat_zoom`.

## Audio routing notes

Specific audio→visual mappings that must hold:

- **Continuous primary drivers** (deviation primitives, D-026): droplet brightness/refraction intensity and subtle silk accent intensity ← `f.bass_att_rel`; dust-mote density ← `f.mid_att_rel`; per-strand micro-quiver phase ← `f.beat_phase01` (MV-3b, not `time`).
- **Beat accents** (deviation primitives, D-026): droplet specular/emission peaks ← `stems.drums_energy_dev` blended with `f.beat_bass_dev` fallback; hub anticipation pulse ← `f.beat_phase01` approach curve (`approachFrac * 0.004` style ramp, per `VolumetricLithograph` reference).
- **Stem warmup** (D-019): all `stems.*` reads must blend through `smoothstep(0.02, 0.06, totalStemEnergy)` to FeatureVector proxies. The first ~10 s of every track and all of ad-hoc mode must look correct without stems.
- **Structure stays solid** (D-020): web geometry is mostly static. Audio modulates emission, dust density, and droplet brightness — **not** strand position, hub location, or radial count. Per-web stage lifecycle (anchorPulse → radial → spiral → stable → evicting) is beat-measured, not amplitude-driven.
- **Spider easter-egg trigger** (D-040): `subBass > 0.65 AND bassAttackRatio < 0.55` held ≥ 0.75 s, with 300 s session cooldown. Sustained resonant bass only — never kick-drum transients.

## Outstanding actions

- [ ] **Compress all images to ≤ 500 KB** before final commit. Current sizes (per disk): `03` is 1.3 MB, `04` is 3.2 MB, `06` is 2.7 MB, `07` is 7.9 MB. **New (V.7.7 extension):** `11` is 5.1 MB, `12` is 951 KB, `13` is 4.6 MB, `14` is 2.1 MB, `15` is 3.5 MB, `16` is 8.3 MB, `17` is 3.5 MB, `18` is 8.7 MB, `19` is 1.0 MB. Every extension-set image needs compression.
- [x] **P0-#1 (anchor-to-bark macro): dropped 2026-05-03.** Empirical correction — real orb-weaver webs predominantly anchor to twigs, leaf petioles, and grass stems, not bark trunks. Ref 11 covers the polygon-of-anchors context at the right scale. `ARACHNE_V8_DESIGN.md §5.9` relaxes the bark-thickness assumption accordingly (twig-thickness branches are the common case; bark detail per ref 18 used only for trunk-thickness anchors).
- [ ] **P1 enrichment refs (not blocking V.7.7+ implementation):**
  - **Mid-distance forest, moderate fog.** Boundary refinement between `06` (heavy fog, distant trees barely readable) and a clearer-mid-distance state — would refine §4.2.2 / §4.2.3 falloff. Source if V.7.7 harness review shows the boundary reads wrong.
  - **Time-lapse still — radials laid, no spiral yet.** Anchors §5.5 visual review. Construction biology is grounded in `ARACHNE_V8_DESIGN.md §13` citations and is implementable without photo refs; source if V.7.8 harness review shows the radials phase reads wrong. BBC Earth orb-weaver time-lapse (cited in §13) is the source candidate.
  - **Time-lapse still — capture spiral mid-construction.** Anchors §5.6 visual review of the inward-winding character. Source criteria as above.
- [ ] **Source P2-#13 storm-lit / dramatic forest** — for the high-arousal low-valence mood quadrant. Not blocking; can be added later.
- [ ] **Write the JSON sidecar `complexity_cost.tier2 = 5.5`** to match the §10.1 budget called out in this README's mandatory traits.
- [ ] **Fill in image attributions** in the Provenance section below — both the original `01` slot and the new extension entries (Unsplash photo IDs are recorded; full attribution lines need verification before commit).
- [ ] **M7 review 2026-05-01: failed (D-071).** Rendered output matched `10_anti_neon_stylized_glow.jpg`. Resolution: V.7.5 + V.7.6. Re-run M7 after V.7.6.
- [ ] **M7 re-run after V.7.5 (in progress, 2026-05-01).** V.7.5 (composition + warm restoration + drops + spider cleanup) shipped per `SHADER_CRAFT.md §10.1` items 1, 2, 3, 4, 6, 9. Formal contact-sheet step bypassed by Matt's choice; visual review will happen at runtime when Matt next launches the build. `Arachne.json` `certified` stays `false` until that pass succeeds. V.7.6 (atmosphere + beam-bound motes — items 5 + 7) still pending after V.7.5 is approved.

## Provenance

Curated by: Matt
Extension set (refs 11–19) curated by: Matt, 2026-05-03

Image sources:

- `01_macro_dewy_web_on_dark.jpg` — *(fill in source + license)*
- `02_meso_per_strand_sag.jpg` — Unsplash, photographer Annie Spratt, photo ID `jZaBFXiUp88`. Unsplash License.
- `03_micro_adhesive_droplet.jpg` — Unsplash, photographer Elina Okolit, photo ID `bUHjUWHczrk`. Unsplash License.
- `04_specular_silk_fiber_highlight.jpg` — Unsplash, photographer Joshua Michaels, photo ID `jQq3E5phnlQ`. Unsplash License.
- `05_lighting_backlit_atmosphere.jpg` — Unsplash, photographer Francesco Ungaro, photo ID `TIO9ln6oILs`. Unsplash License. (*verify — this slot may use a different image; confirm against disk*)
- `06_atmosphere_dark_misty_forest.jpg` — Unsplash, photographer Aleš Krivec, photo ID `Ek5w1qwGHow`. Unsplash License.
- `07_atmosphere_dust_light_shaft.jpg` — Unsplash, photographer Michael Held, photo ID `gghk1DME6Cw`. Unsplash License.
- `08_palette_bioluminescent_organism.jpg` — Unsplash, photographer Mykhailo Amirdzhanian, photo ID `NDQbSIBQEi0`. Unsplash License.
- `09_anti_clipart_symmetry.jpg` — Stock clipart reference (deliberately included as negative reference). *(verify source + license)*
- `10_anti_neon_stylized_glow.jpg` — Stock illustration reference (deliberately included as negative reference). *(verify source + license)*
- `11_anchor_web_in_branch_frame.jpg` — Unsplash, photographer Richie Bettencourt, photo ID `Lz_oGNXkk0k`. Unsplash License.
- `12_spider_orb_weaver_dorsal.jpg` — Unsplash, photographer Zdeněk Macháček, photo ID `agEmEZS3rRc`. Unsplash License.
- `13_spider_orb_weaver_lateral.jpg` — Unsplash, photographer Abba Argaman, photo ID `QiONAYKs9UY`. Unsplash License.
- `14_spider_iridescent_chitin.jpg` — Unsplash, photographer Julian Göbel, photo ID `Geu9kXvorzA`. Unsplash License.
- `15_atmosphere_aurora_forest.jpg` — Unsplash, photographer Oscar Brouchot, photo ID `x-64XYIJ4Jg`. Unsplash License.
- `16_atmosphere_dappled_pine_forest.jpg` — Unsplash, photographer Žan Lazarević, photo ID `cQ-gGklAxn8`. Unsplash License.
- `17_floor_moss_leaf_litter.jpg` — Unsplash, photographer Gryffyn M, photo ID `Xd6mLco-MYo`. Unsplash License.
- `18_bark_close_up.jpg` — Unsplash, photographer Behnam Norouzi, photo ID `RxpjF9um4cg`. Unsplash License.
- `19_spider_eye_specular.jpg` — Unsplash, photographer credited as "Getty Images" via Unsplash partnership, photo ID `6c-5EAYq8KE`. **Verify license terms before commit** — Getty/Unsplash partnership images may have stricter terms than standard Unsplash License. If license is restrictive, source an equivalent CC-BY or public-domain spider-eye macro from Wikimedia Commons (peacock spider macros by Jürgen Otto are CC-licensed).

Unsplash License terms: free for commercial and non-commercial use, no attribution required but recommended. Recording attributions here protects future re-licensing audits.
