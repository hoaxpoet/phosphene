# Shader Artists to Study — Preset Inspiration Reference

**Purpose:** A curated, source-backed study list of 3D / GPU shader artists for Matt + Claude Code to raise Phosphene's preset visual quality. Scoped per Matt's direction: a *balanced* survey across raymarching/SDF, particles/flow-fields, and feedback/demoscene; *includes* node-based real-time (TouchDesigner/Notch/vvvv/Max) alongside portable GLSL; *balances* pure visual-craft masters with audio-reactive specialists.

**Method:** Five parallel web-research passes (one per domain), then adversarial verification of the load-bearing claims (licenses, handles, technique attributions). Confirmed vs. flagged items are noted in [§Verification](#verification--confidence). The four references already studied in-house — Inigo Quilez, Robert Leitl, Robert Hodgin/Flight404, Rama Hoetzlein — are deliberately *not* re-recommended as headline finds; everything below is net-new, with their key resources noted only where another artist builds on them.

> **Read [§Licensing reality](#licensing-reality--read-before-vendoring) first.** Several of the best resources are non-commercial or copyleft. Phosphene is MIT-licensed (per `CLAUDE.md`), so *what you can paste* vs. *what you must re-implement* differs by source, and it matters.

---

## TL;DR — if you study only a handful

| Rank | Artist | Domain | The one thing to take | Vendorable? |
|---|---|---|---|---|
| 1 | **Mercury (`hg_sdf`)** | Raymarch/SDF | Domain-fold + chamfer/column/stair boolean operators = a huge free expansion of geometry/material vocabulary | ✅ MIT option |
| 2 | **Sage Jenson "mxsage" + Étienne Jacob "Bleuje"** | Feedback/agent | Physarum "36 Points" agent-deposit loop — a genuinely *new* texture substrate (feedback-on-agents, not feedback-on-noise) | ⚠️ CC-BY-NC-SA (re-implement) |
| 3 | **Keijiro Takahashi** | Particles | The whole "audio band-bank → smoothed envelope → attribute-map → instanced draw" architecture — closest existing code to what Phosphene builds | ✅ MIT/Unlicense |
| 4 | **Xor (GM Shaders)** | Feedback/raymarch | Layered-rotated-sine "turbulence" as a drop-in domain-warp for feedback-UV lookups — Milkdrop trails with no fluid pass | ✅ tutorials, re-implement |
| 5 | **nimitz (`@stormoid`)** | Raymarch/fluid | Few-evaluations-per-step volumetric integration + blue-noise temporal reuse; "Chimera's Breath" curl-in-alpha fluid | ⚠️ Shadertoy (re-implement) |
| 6 | **Ryan Geiss (Milkdrop)** | Audio/feedback | The `per_frame`/`per_pixel` 32×24 grid-warp model — proven, most-deployed music-visual hierarchy ever shipped | ✅ docs/source |
| 7 | **Olivia Jack (Hydra)** | Audio | `setBins / fft[] / setSmooth / setCutoff / setScale` — a battle-tested audio→param contract to mirror | ⚠️ AGPL (re-implement) |
| 8 | **Bileam Tschepe "elekktronaut"** | Node (TD/Notch) | Audio-reactive feedback-loop-with-displacement-and-decay — the organic-trails recipe | tutorial, re-derive |

If a single sentence summarizes the whole report: **vendor `hg_sdf` now; prototype a Physarum preset; and standardize one audio→uniform contract (Hydra/Milkdrop-style) so the entire Shadertoy ecosystem becomes reusable.**

---

## Licensing reality — read before vendoring

Phosphene ships under MIT and the team vendors references (FA #73 "port the reference"). Two distinct things are governed differently:

- **Algorithms/techniques are not copyrightable.** You can always *re-implement* a technique (Gray-Scott + advection, 36-Points parameter mapping, curl-noise) in your own Metal code regardless of the reference's license. This is the default path for anything below marked "re-implement."
- **Specific code expression is copyrightable.** Pasting someone's GLSL/MSL verbatim is bound by their license.

Buckets:

| License | Sources | What you may do |
|---|---|---|
| **MIT / Unlicense / CC0** (paste OK) | `hg_sdf` (MIT option), mrange `glsl-snippets` (CC0), Keijiro repos, Pavel Dobryakov WebGL-Fluid, Memo Akten `ofxMSAFluid`, Matthias Müller *Ten Minute Physics*, three.js examples, Steinrucken "RayMarching starting point" (MIT) | Vendor with attribution |
| **Non-commercial** (re-implement, don't paste) | **LYGIA** (Prosperity NC + Patron), Seascape (CC-BY-NC-SA), Sage Jenson / Bleuje *36 Points* (CC-BY-NC-SA) | Study + write your own Metal version; or sponsor (LYGIA) to lift the NC restriction |
| **Copyleft/viral** | Hydra (AGPL-3.0), projectM (LGPL) | Fine as a *reference for the API/contract*; do not statically link the code into a closed target |
| **Reference-only** (no portable code) | Henke, Ikeda, Nonotak, Max Cooper, Tarik Barri (paper), all node-based tutorial channels | Re-derive the technique from the explanation |

**Net:** the two highest-leverage code grabs (`hg_sdf`, Keijiro) are cleanly vendorable. The two highest-leverage *ideas* (Physarum/36-Points, Hydra's audio contract) you re-implement — which you'd do anyway to land them in Metal.

---

## Domain 1 — Raymarching / SDF / Volumetric

Where "visual quality" concentrates: lighting, materials, fog, soft shadows, geometry density.

### Mercury — `hg_sdf` (the SDF construction library) — **top grab**
- **Who:** Demoscene group (members incl. @paniq / Leonard Ritter, ps0ke) behind the 64k intros *the timeless* and *on*. `hg_sdf` is the canonical GLSL SDF-building library, distilled from shipping productions.
- **Signature:** Clean, dense, hard-surface sphere-traced geometry with sophisticated joins.
- **Steal (port verbatim — plain GLSL → MSL is trivial):**
  - **Domain operators** for near-free repetition: `pMod1/2/3` (mirror grids), `pModPolar` (radial), `pModInterval1` (bounded), `pModMirror2`. Cheapest route to visual density.
  - **Boolean operators beyond min/max:** `fOpUnionRound` (the smooth-min you already use) *plus* `fOpUnionChamfer / Columns / Stairs`, `fOpPipe / Groove / Engrave / Tongue` — each a different **bevel/seam aesthetic** at the join. A large, free material vocabulary expansion.
  - **The Lipschitz discipline** ("never multiply a distance to fix gradients; keep gradient ≤ 1") — directly relevant to Phosphene's normal-flip / dot-pattern artifact class (FA #64).
- **Where:** <https://mercury.sexy/hg_sdf/> · GLSL: <https://mercury.sexy/hg_sdf/hg_sdf.glsl> · NVScene 2015 talk: youtube `s8nFqwOho-s`
- **License:** dual **MIT OR CC-BY-NC-4.0** since 2021-07-28 — take the MIT option and vendor as a Metal SDF header. *(Verified on the page.)*

### nimitz (`@stormoid`) — volumetric & fluid raymarching
- **Who:** Prolific Shadertoy author; volumetric/fluid/noise specialist.
- **Signature:** Dense procedural 3D volumes, turbulent fluid, cinematic-yet-fast.
- **Steal:**
  - **"Protean Clouds"** volumetric model — fully procedural animated volume, ~3 density evals per march step, 1080p-capable: <https://www.shadertoy.com/view/3l23Rh>
  - **Blue-noise temporal acceleration** (the "speed up" fork) — blue-noise offset + temporal blend cuts march steps ~3× with minimal detail loss: <https://www.shadertoy.com/view/wlSGWR>. Pair with Alan Wolfe's rigorous treatment (below) to hit 60fps@1080p on fog/cloud/godray presets.
  - **"Chimera's Breath"** near-single-pass 2D fluid with **vorticity confinement stored in the alpha channel** — a clean memory layout for a Metal ping-pong target: <https://www.shadertoy.com/view/4tGfDW> (after Guay/Colin/Egli 2011).
- **Where:** <https://www.shadertoy.com/user/nimitz> · X <https://x.com/stormoid>

### Martijn Steinrucken — "The Art of Code" / `BigWIngs`
- **Who:** The most-watched raymarching *teacher*; every technique has a paired, line-by-line video. (Confirmed: BigWIngs = The Art of Code = @the_artofcode = Steinrucken.)
- **Signature:** Glowing, volumetric, emotive scenes built from clearly-explained primitives.
- **Steal:** the clean ray-marcher skeleton (`RayMarching starting point`, MIT: <https://www.shadertoy.com/view/WtGXDD>); "Tips & Tricks" video on cheap soft shadows, glow/emission accumulation, bounding tricks; "Luminescence" subsurface-glow for music-reactive emissive materials (<https://www.shadertoy.com/view/4sXBRn>). Use as the **onboarding/reference layer** for anyone touching the raymarch core.
- **Where:** YouTube "The Art of Code" · X <https://twitter.com/the_artofcode>

### Patricio Gonzalez Vivo — *Book of Shaders* + **LYGIA**
- **Who:** Artist/educator (Parsons). Author of *The Book of Shaders* and the LYGIA shader library.
- **Steal:** LYGIA is **multi-language including Metal** — it ships `*.msl` files (`sdf.msl`, `math.msl`, `lighting/…`) so the algorithms need no GLSL→MSL translation; granular (one function per file): simplex/worley/fBM noise, SDF primitives + ops, PBR/lighting helpers, color spaces, raymarching helpers. *Book of Shaders* chapters are the canonical noise/fBM/cellular derivations.
- **Where:** LYGIA <https://github.com/patriciogonzalezvivo/lygia> (<https://lygia.xyz>) · Book of Shaders <https://thebookofshaders.com/>
- **⚠️ License:** LYGIA is **Prosperity (non-commercial) + Patron** — *not* MIT. Use it as a Metal-native **reference to re-implement from**, or sponsor for the Patron License if you want to vendor `.msl` directly. (This corrects an earlier "drop-in, mind per-file licensing" read — the whole library is NC unless you sponsor.)

### Sebastian Aaltonen — production SDF rendering (Claybook)
- **Who:** Senior graphics engineer (ex-Ubisoft/Unity). GDC 2018 talk on Claybook's GPU SDF sim + raytracing — the authoritative source for making SDF rendering *robust*.
- **Steal:** **Improved SDF soft-shadow penumbra** — estimate the closest point between the current and previous march samples (triangulate the two) to compute the penumbra term, killing the banding the classic iq `rmshadows` term shows at sharp corners. Direct upgrade to Phosphene's soft-shadow pass. ("Sharp at contact, soft at distance"; ran on Switch.)
- **Where:** slides <https://ubm-twvideo01.s3.amazonaws.com/o1/vault/gdc2018/presentations/Aaltonen_Sebastian_GPU_Based_Clay.pdf> · X @SebAaltonen

### Also in this domain (confirmed, narrower)
- **Mikael Hvidtfeldt Christensen — Syntopia / Fragmentarium:** the definitive **distance-estimated fractal** reference (mandelbulb/mandelbox/KIFS) with full DE derivations + a Preetham atmospheric sky. 8-part series from <https://blog.hvidtfeldts.net/index.php/2011/06/distance-estimated-3d-fractals-part-i/>. Port the DE + folding + sky for fractal/atmospheric presets.
- **Dave Hoskins — "Hash without Sine":** sine-free, **precision-portable** GPU hashes (sine-hashes break across GPU generations) — adopt as Phosphene's canonical Metal noise seed across Apple GPUs. <https://www.shadertoy.com/view/4djSRW>
- **mrange — `glsl-snippets` (CC0):** apollonian/truchet/kaleidoscope psychedelia — *exactly* the audio-visualizer aesthetic, and CC0 so paste-able. <https://github.com/mrange/glsl-snippets>
- **Alexander Alekseev (TDM) — "Seascape":** the reference procedural-ocean heightfield-march (octave noise + Fresnel spec). <https://www.shadertoy.com/view/Ms2SD1> (⚠️ CC-BY-NC-SA — re-implement for shipping).
- **Fabrice Neyret — "Shadertoy Unofficial" blog:** deepest catalog of branchless/cheap GLSL reformulations and AA tricks; mine when a preset is over frame budget. <https://shadertoyunofficial.wordpress.com/>
- **Xor — GM Shaders:** modern, compact tutorials incl. a clean **Volumetric Raymarching** write-up. <https://mini.gmshaders.com/p/volumetric> (more in Domain 3).
- **Alan Wolfe — demofox / atrix256:** the authority on **blue-noise for raymarching** (animated blue-noise via golden-ratio temporal advance) — the rigorous source behind nimitz's volumetric acceleration. <https://blog.demofox.org/2020/05/10/ray-marching-fog-with-blue-noise/>
- **Shane:** the community's most thoroughly-*commented* raymarcher — readable reference implementations of AO/shadow/material. <https://www.shadertoy.com/user/Shane>

---

## Domain 2 — Particles / Flow-Fields / Agents / Fluids

GPU sims, curl-noise advection, flocking, fluids. (Hodgin/Hoetzlein are in-house; everyone here is net-new.)

### Keijiro Takahashi — **top grab for audio-reactive GPU VFX**
- **Who:** Tokyo graphics toolmaker; the single most prolific publisher of audio-reactive GPU-VFX *source* (MIT/Unlicense, `github.com/keijiro`). Unity/HLSL, but compute + signal-processing patterns translate almost line-for-line to Metal.
- **Signature:** Crisp, restrained, "instrumented" point-cloud/particle work driven by tightly-filtered audio bands, not raw onsets — matches Phosphene's "continuous energy is primary" doctrine.
- **Steal:**
  - **LASP / LaspVfx** — low-latency filter-bank → smoothed band envelopes → VFX. Exactly the Layer-1 continuous-energy routing Phosphene favors; read its smoothing/peak-follow design. <https://github.com/keijiro/LaspVfx>
  - **Smrvfx** — bake an animating mesh into position+velocity **attribute maps** each frame, then emit/advect particles from the surface. Port: render geometry to a position texture, sample it in the particle kernel → emit particles off any SDF/mesh surface. <https://github.com/keijiro/Smrvfx>
  - **Pcx / Rsvfx** — point-stream → position/color map → instanced-mesh source: the canonical instanced-point pattern at scale. <https://github.com/keijiro/Rsvfx>
- **Take:** the entire "audio band-bank → smoothed envelope → attribute-map → instanced draw" architecture.

### Pavel Dobryakov — the reference real-time fluid
- **Who:** Author of `WebGL-Fluid-Simulation` (the de-facto interactive GPU stable-fluids reference, MIT).
- **Steal:** the cleanly-factored GPU-Gems-38 pipeline as separable passes — **advection → divergence → curl → vorticity confinement → Jacobi pressure → gradient subtract**, ping-ponging double-buffered targets. Two natural audio hooks: **splat injection** (position/radius/force from beat accents + band energy) and **vorticity-confinement strength** (continuous energy) = "how alive" the motion feels.
- **Where:** <https://github.com/PavelDoGreat/WebGL-Fluid-Simulation> · math: GPU Gems Ch.38 <https://developer.nvidia.com/gpugems/gpugems/part-vi-beyond-triangles/chapter-38-fast-fluid-dynamics-simulation-gpu>

### Nop Jiarathanakul — the million-particle GPU pattern
- **Who:** WebGL/three.js engineer (`nopjia`), author of *A Particle Dream* with an unusually clear write-up.
- **Steal:** **three-texture particle state** (position/velocity/color), each particle one UV-addressed texel; the vertex shader looks up position/color to render. Plus **fixed-timestep sim decoupled from render framerate** (explicitly called out to avoid jitter — easy to get wrong). In Metal this is even cleaner via compute kernels writing structured buffers.
- **Where:** <https://www.iamnop.com/posts/2014-06-08-webgl-gpu-particles/> · <https://github.com/nopjia/particles-mrt>

### David Li — 3D PIC/FLIP fluid + FFT ocean
- **Who:** Graphics engineer (`dli`), featured in Google Experiments.
- **Steal:** **`dli/fluid`** — GPU **PIC/FLIP** (hybrid particle-grid) 3D liquid with a **spherical ambient-occlusion volume** for shading a raw particle cloud as a surface (cheap, splashy). **`dli/waves`** — **FFT-based (Tessendorf) ocean**, more principled than hand-tuned Gerstner sums; Metal has `MPSMatrix`/vDSP for the transforms.
- **Where:** <https://github.com/dli/fluid> · <https://github.com/dli/waves> · <https://david.li/>

### Also in this domain (confirmed)
- **Memo Akten — `ofxMSAFluid` (MIT):** the cleanest readable *minimal* stable-fluids loop (Jos-Stam), and the **velocity-field-as-shared-resource** pattern — one fluid sim drives both a dye texture and a particle advection kernel. Directly defuses Phosphene's "two layers fighting" failure (FA #67): one velocity field, many consumers. <https://github.com/memoakten/ofxMSAFluid>
- **Matthias Müller / *Ten Minute Physics* (MIT):** **Position-Based Fluids** (stable, large-timestep SPH) for cohesive droplets/splashes, plus a GPU-friendly **spatial-hash neighbor grid** reusable across SPH *and* flocking. <https://matthias-research.github.io/pages/tenMinutePhysics/>
- **Cornusammonis — Shadertoy fluid/RD virtuoso:** **multiscale MIP-pyramid fluid** (propagate pressure across mip levels instead of many Jacobi iterations) and **reaction-diffusion coupled with advection**. <https://www.shadertoy.com/user/cornusammonis> (also Domain 3).
- **three.js GPGPU birds:** the canonical compact ping-pong flocking-on-textures example; a clean cross-check against the in-house Flock2 work. <https://github.com/mrdoob/three.js/blob/master/examples/webgl_gpgpu_birds.html>
- **Foundational papers to keep on hand:** Bridson, *Curl-Noise for Procedural Fluid Flow* (SIGGRAPH 2007) — the exact divergence-free curl-noise Phosphene already uses; and GPU Gems Ch.38.

---

## Domain 3 — Feedback / Reaction-Diffusion / Demoscene Texture Craft

The Milkdrop lineage: multi-pass buffer feedback, organic growth, procedural texture.

### Sage Jenson "mxsage" + Étienne Jacob "Bleuje" — Physarum / 36 Points — **top grab for organic texture**
- **Who:** Sage Jenson (ex-AIR at Nervous System) popularized modern Physarum (slime-mold) art; Étienne Jacob ("Bleuje") published a fully-documented openFrameworks **compute-shader** port.
- **Signature:** Living, filamentary networks — veins, neural webs, dendritic growth that continuously reorganizes. Organic in a way noise-based texture never achieves.
- **Steal (a genuinely *new* primary substrate — feedback-on-agents, not feedback-on-noise):**
  - **Agent loop:** each agent (position + heading) **senses** trail at three points (ahead, ±sensor-angle), **rotates** toward the brightest, **moves** forward, **deposits** onto a trail map; then the trail map is **diffused (3×3) and decayed (×0.75)**. That's a multi-pass ping-pong loop → maps cleanly to Metal compute.
  - **"36 Points" parameterization:** make the four classic params **functions of the locally-sensed trail value `x`**: `sensorDistance = p1 + p2·x^p3` (same shape for angle/rotation/move) → 12 tunable params (20 total) from one kernel. *This* is the move that turns "a slime sim" into a tunable family — perfect for audio-driven per-section variation (map `bassDev`/energy → deposit amount, rotation angle, or the `x`-exponents to make the network bloom/tighten on the beat).
  - **Bleuje's 4-shader structure** (verified): reset counters → particle move + `atomicAdd` → deposit `sqrt(count)·f` + colorize → diffusion+decay; two-channel (trail + delayed-trail) **color-by-rate-of-change**; an inertia/velocity variant. Runs **5.8M particles @ 60fps on an RTX 2060** — comfortably within Apple-Silicon reach at preset resolutions.
- **Where:** Sage <https://www.sagejenson.com/36points/> · process write-up <https://n-e-r-v-o-u-s.com/blog/?p=9137> · **Bleuje (the copy-ready reference)** <https://bleuje.com/physarum-explanation/> · repo <https://github.com/Bleuje/physarum-36p>
- **⚠️ License:** Sage's code + Bleuje's article are **CC-BY-NC-SA 3.0** — re-implement the algorithm in your own Metal kernels (the technique is free); don't paste their GLSL into MIT Phosphene.

### Xor — GM Shaders — **top grab for cheap feedback craft**
- **Who:** Author of *GM Shaders Mini* — short, rigorous, copy-pasteable tutorials aimed at "look great cheaply in real time."
- **Steal:** **fake turbulence via layered rotated-sine domain-warping** (no simulation, no buffers): ~8–10 octaves, each adding a perpendicular sine offset along a rotated axis (`mat2(0.6,-0.8,0.8,0.6)`), frequency up / amplitude down per octave. Drop this onto your **feedback-UV lookup** (warp the previous-frame sample coords) to get **Milkdrop-style flowing trails without a fluid pass**. Fire and Phosphor/CRT-glow variants too.
- **Where:** <https://mini.gmshaders.com/p/turbulence> (demos `WclSWn`, fire `wffXDr`) · hub <https://mini.gmshaders.com/>

### cornusammonis — reaction-diffusion + advected feedback
- **Who:** Shadertoy author specializing in RD and viscous-flow feedback.
- **Steal:** two ready feedback-texture modules — **pure Gray-Scott** ping-pong for slow organic growth (ambient sections), and **RD coupled with advection** ("the pattern flows with the music," modulate feed/kill + advection strength by audio). Both are exactly Buffer-A→A feedback.
- **Where:** <https://www.shadertoy.com/user/cornusammonis>

### Demoscene craft + tooling
- **NuSan — live-coded multipass:** value is the **live-coding corpus** — how a complete look (incl. multipass feedback "zoomers" + particles) is assembled from a blank fragment shader in minutes. A model for keeping each Phosphene preset *tight* rather than 2000-line monoliths. <https://nusan.fr/demoscene/livecoding/>
- **ctrl-alt-test (Laurent "LLB" Le Brun, "Zavie") — 64k texture synthesis:** the **"Texturing a 64kB intro"** / *Immersion* making-of series is a masterclass in procedural-material layering — the exact "≥4 noise octaves, ≥3 materials" discipline Phosphene's `SHADER_CRAFT` floor demands. Also **Shader Minifier** (open source). <https://www.ctrl-alt-test.fr/category/techniques/>
- **Flopine (Cookie Collective) — live shader craft:** compact distortion/palette/repetition idioms and a teaching-grade view of size-limited shader craft; good source for "preset-author rules." <https://www.shadertoy.com/user/Flopine>
- **Fabrice Neyret — the multipass reference backbone:** the definitive write-ups on **how to use buffers correctly** — precompute at `iFrame==0`, ping-pong patterns, the gotchas. Read before finalizing Phosphene's Buffer-A→B slot conventions. <https://shadertoyunofficial.wordpress.com/>
- **Sebastian Lague — "Coding Adventure: Ant and Slime":** the most beginner-readable Physarum (Unity compute, clean source) if Bleuje's is too dense. <https://github.com/SebLague/Slime-Simulation>

---

## Domain 4 — Node-Based Real-Time (TouchDesigner / Notch / vvvv / Max-Jitter)

Great aesthetics + teaching; techniques re-derived into Metal. All net-new vs. the in-house set.

### Bileam Tschepe — "elekktronaut" (TouchDesigner + Notch) — **top node pick**
- **Who:** Berlin educator; one of the most-followed TD teachers (works in *both* TD and Notch).
- **Signature:** Organic, audio-reactive, "living" feedback systems — the closest aesthetic match to a visualizer that should feel alive.
- **Steal (re-derive into Metal):** **audio-reactive feedback loop with displacement + decay** — feed last frame back, displace by a noise/flow field, decay, recombine. A small fragment shader and the single highest-leverage node technique for "locked-to-music organic motion" (generalizes your existing feedback-zoom). Plus a CHOP-built kick/snare module that parallels your `beatBass`/`beatComposite` accents.
- **Where:** YouTube <https://www.youtube.com/c/bileamtschepe> · <https://www.elekktronaut.com/> · "Make Anything Audio Reactive" <https://derivative.ca/community-post/tutorial/make-anything-audio-reactive/64122>

### The Interactive & Immersive HQ — Matthew Ragan + Elburz Sorkhabi (TD)
- **Who:** The most systematic TD education operation (Elburz authored the first TouchDesigner book; Matthew Ragan, 100+ tutorials).
- **Steal:** **optical-flow-driven particle advection** — particles ride a per-pixel motion field derived from incoming video (motion vectors → velocity field → particle update in a Metal compute kernel). This is the clearest *net-new* technique not obviously in Phosphene's stack. Their open GitHub also documents **Shadertoy→node porting conventions** (uniform/coordinate mapping) useful for sanity-checking your re-derivations.
- **Where:** <https://interactiveimmersive.io/blog/touchdesigner-lessons/touchdesigner-gpu-particles/> · GitHub <https://github.com/interactiveimmersivehq/Introduction-to-touchdesigner>

### RayTK — Tommy Etkin / "t3kt" (TD, open source) — **FA #73 port candidate**
- **Who:** Open-source raymarching toolkit for TouchDesigner — node-composable SDF scenes that *emit GLSL*. Lineage explicitly: TDRaymarchToolkit → **hg_sdf** → **Inigo Quilez** (i.e., the node encoding of techniques you already respect).
- **Steal:** read the ROP GLSL fragments directly — a vetted, modular **SDF building-block library** (primitives, booleans, domain repetition, deformers, smooth-min variants) that translates cleanly to Metal SDF functions. High value as a *reference codebase*, not just tutorials.
- **Where:** <https://github.com/t3kt/raytk> · docs <https://t3kt.github.io/raytk/>

### Also in this domain (confirmed)
- **Simon Alexander-Adams "polyhop" (TD):** **seamless looping-noise phase trick** (perfect loops for idle/transition states) and a **CHOP-data → per-instance attribute buffer** pattern that maps to Metal instanced draws. <https://www.simonaa.media/tutorials-articles>
- **Kevin Zhu (Notch):** **"FFT-as-texture, sampled by many consumers"** routing (mirrors Phosphene's Layer-2 spectrum-as-buffer rule) + **velocity-magnitude attribute shading** for particles (trivial in Metal, big payoff). Free `.dfx` project files. <https://kevzhu.com/tutorials>
- **Paketa12 (TD, GLSL):** texture-encoded particle state (pos/vel in textures) advected by a sampled flow field — ports ~1:1 to Metal ping-pong. <https://alltd.org/uploader/paketa12/>
- **Federico Foderaro "Amazing Max Stuff" (Max/Jitter):** 270+ tutorials; the GEN breakdowns show an effect as per-sample math *before* you write the kernel, and `jit.catch~` reinforces the audio→matrix→texture pattern. <https://www.federicofoderaro.com/max-msp-jitter-tutorials.html>
- **Torin Blankensmith — Shader Park (TD + WebGL):** a high-level procedural-SDF authoring API (JS→GLSL) — a second readable SDF reference alongside RayTK. <https://shaderpark.com>
- **vvvv — DX11.Particles pack:** GPU-particle techniques for very large counts. <https://beta.vvvv.org/contributions/packs/dx11-particles/index.html>

---

## Domain 5 — Audio-Reactive / AV Specialists

How top artists map audio→visual so it feels "locked."

### Olivia Jack — Hydra — **top audio pick (the contract to mirror)**
- **Who:** Creator of Hydra, a livecoded browser video-synth on WebGL framebuffers; one of the most-used open AV systems in the livecoding scene.
- **Steal (the API *is* a battle-tested audio→param spec):**
  - **Binned FFT as the primary interface:** `a.setBins(n)` → `a.fft[i]` returns a **normalized 0–1 per band** — exactly Phosphene's "continuous energy bands as default driver," shipped as the idiomatic path (not raw onsets).
  - **Per-band temporal smoothing** `a.setSmooth(0.8)` (0 = jumpy, 1 = frozen) — your attack/decay envelope primitive.
  - **Calibration:** `a.setCutoff()` (noise-gate floor) + `a.setScale()` (range) — a hand-rolled AGC-lite worth comparing against your deviation-primitive approach.
  - Analysis delegated to **Meyda** (RMS, centroid, rolloff, flux, MFCC, chroma) — a good checklist for your Layer-3 features.
- **Take:** model a CPU-side "audio uniform" struct on `setBins / fft[] / setSmooth / setCutoff / setScale` — then any Hydra/Shadertoy audio shader becomes reusable.
- **Where:** <https://github.com/ojack/hydra> (⚠️ AGPL — reference the contract, write your own) · audio guide <https://hydra.ojack.xyz/docs/docs/learning/guides/audio/>

### Ryan Geiss — Milkdrop
- **Who:** Author of Milkdrop (the foundational visualizer projectM reimplements). The team knows the lineage; the *specific* mechanics are worth porting precisely.
- **Steal:** the **two-stage model** — `per_frame` (once/frame: set global warp/zoom/rot/decay from FFT bass/mid/treble + beat) and `per_pixel` (on a **32×24 grid**, warp per vertex with **bilinear interpolation**) → cheap, smooth, beat-locked deformation. Maps onto (per-frame uniforms) + (vertex-grid warp in a Metal mesh/compute pass). His page is a proven default palette (zoom, rot, warp, cx/cy, decay) to seed presets — and independent validation of Phosphene's continuous-energy-primary + beat-as-accent hierarchy in the most-deployed visualizer ever.
- **Where:** <https://www.geisswerks.com/milkdrop/milkdrop.html>

### Robert Henke (Monolake) — Lumière — **the principle behind "locked"**
- **Who:** Co-creator of Ableton Live; as Monolake, a foundational precise-AV figure with unusually detailed public technical write-ups.
- **Steal (concept):** **shared control signal for sound and image** — Henke derives laser motion from the *same* control voltages as the audio, so sync is *structural, not after-the-fact*. The Phosphene translation: architect **"audiovisual events"** as first-class objects where a single envelope/phase (e.g., your cached `BeatGrid` phase) feeds *both* an audio-aligned accent and its visual mark in the same frame. This is the principled version of your Layer-4 "build beat-locked motion on the cached grid, not live onsets" rule.
- **Where:** <https://roberthenke.com/> · Ableton interview <https://www.ableton.com/en/blog/robert-henke-lumiere-lasers-interview/>

### Also in this domain (confirmed)
- **Memo Akten — continuous-control thesis:** his PhD argues meaningful control of a generative system needs *continuous, smooth* mapping rather than discrete triggers — independent corroboration of Phosphene's "continuous energy beats raw onsets" from the ML side. Plus `ofxMSAFluid` force-injection (route `bassDev`/`drumsEnergyDev` → impulse, centroid → dye color). <https://www.memo.tv/>
- **Martijn Steinrucken — the audio-texture convention:** Shadertoy's **512×2 audio texture (row 0 = FFT, row 1 = waveform)**. Adopt the row layout as Phosphene's GPU audio-texture convention and the entire Shadertoy audio-shader corpus drops in near-verbatim.
- **Tarik Barri — Versum:** object = audiovisual atom; **distance-to-virtual-mic → gain**. Inverted, this is a **visual-salience model driven by audio** — place/scale scene elements by which stems are loudest, so the visible composition tracks the arrangement (relevant to the Orchestrator's emotional arc). Paper: <https://www.icad.org/Proceedings/2009/Barri2009.pdf>
- **Char Stiles — minimal audio-reactive shaders:** her `.bands` workshop `.frag` files are a corpus of "the smallest thing that feels locked" — good preset-author reference + test fixtures. <https://github.com/CODAME/Shaders-Workshop>
- **Andrew Benson — Jitter Recipes:** each "recipe" is a discrete (audio-feature → GPU-effect) mapping; good for feedback-slab techniques driven by audio. <https://cycling74.com/articles/artist-focus-andrew-benson>
- **Aesthetic-only references** (no portable code, study the look): **Ryoji Ikeda** / **Alva Noto** (data/sine, frequency-locked monochrome), **Nonotak** (light+sound minimalism), **Raven Kwok** (Voronoi-tessellation generative-from-spectrum), **Max Cooper** (how to brief/structure an audio-led concept).

---

## Cross-cutting techniques to adopt (synthesis)

These recur across multiple domains — strong signal they're worth standardizing:

1. **One shared velocity field, many consumers.** Run one fluid/curl-noise sim into a velocity texture; advect dye *and* particles by sampling it (Akten, Cornusammonis). This is the architectural fix for Phosphene's "two layers fighting" failure (FA #67) — and it appears independently in three artists.
2. **State-in-textures + fixed-dt sim / variable-dt render** (Nop) — the robust GPGPU particle backbone.
3. **"Audio spectrum as a texture, sampled by many consumers."** Appears independently in Notch (Kev Zhu FFT-texture), Jitter (Foderaro `jit.catch~`), and Hydra — cross-validates Phosphene's existing Layer-2 spectrum-as-buffer rule. Standardize the **512×2 FFT/waveform layout** (Steinrucken/Shadertoy) so community shaders are reusable.
4. **Binned normalized energy + per-band smoothing + cutoff/scale** as the canonical audio→param contract (Hydra). Compare against your deviation primitives.
5. **Grid-warp + bilinear-interpolation feedback** (Milkdrop 32×24) for cheap, smooth, beat-locked deformation; and **rotated-sine turbulence domain-warp** (Xor) on the feedback-UV lookup for Milkdrop trails with no fluid pass.
6. **Spatial-hash neighbor grid** (Müller) — one data structure reusable across SPH fluid *and* flocking.
7. **"Audiovisual event" = single source signal → both audio accent and visual mark** (Henke) — structural sync; the principled articulation of your BeatGrid-driven-accents rule.
8. **Lipschitz discipline + closest-point penumbra** (Mercury + Aaltonen) — keep distance gradients ≤ 1 and upgrade the soft-shadow term to kill banding (relevant to the FA #64 dot-pattern class).

---

## A concrete study plan (prioritized)

**Week 1 — vendor + read (cleanly-licensed, immediate):**
1. Vendor `hg_sdf` (MIT) as a Metal SDF header; wire up 2–3 chamfer/column/stair booleans + `pModPolar` on an existing preset to feel the vocabulary expansion.
2. Read Keijiro `LaspVfx` + `Smrvfx` for the audio-band→attribute-map→instanced-draw architecture.
3. Read Fabrice Neyret's multipass/buffer write-ups before touching the feedback-slot conventions.

**Week 2 — prototype one genuinely new substrate:**
4. Re-implement the Physarum/36-Points agent loop (from Bleuje's documented 4-shader pipeline) as Metal compute; drive deposit/rotation by `bassDev`. This is the biggest *new look* on the list.
5. Stand up a one-velocity-field fluid (Pavel's pass chain or Akten's minimal Stam loop) with audio-driven splat injection; advect a dye texture *and* particles from the same field.

**Week 3 — standardize the audio contract + lock-feel:**
6. Define the CPU-side audio-uniform struct on Hydra's `setBins/fft[]/setSmooth/setCutoff/setScale` model + the 512×2 GPU audio-texture layout.
7. Port Milkdrop's `per_frame`/`per_pixel` grid-warp as a preset family; apply Xor's turbulence domain-warp to the feedback UVs.

**Ongoing reference:** Steinrucken (onboarding), Shane (commented implementations), Syntopia (fractals), Alan Wolfe (blue-noise), elekktronaut/IIHQ (node techniques to re-derive).

---

## Verification & confidence

**Independently confirmed by direct page fetch during this research:**
- `hg_sdf` authorship (Mercury) + **dual MIT OR CC-BY-NC-4.0** license + the full operator list — <https://mercury.sexy/hg_sdf/>.
- **LYGIA ships Metal `.msl` files** (`sdf.msl`, `math.msl`, `sampler.msl`, `README_METAL.md`) **but is licensed Prosperity (NC) + Patron, not MIT** — <https://github.com/patriciogonzalezvivo/lygia>. (Corrects the initial "drop-in" read.)
- Bleuje/Sage Jenson **36 Points**: 4-shader pipeline, `p1+p2·x^p3` formula, `sqrt(count)·f` deposit, 5.8M particles @60fps RTX 2060, CC-BY-NC-SA — <https://bleuje.com/physarum-explanation/>.
- Aaltonen Claybook penumbra technique (triangulate current+previous march sample) and Steinrucken identity (BigWIngs = The Art of Code) — via search corroboration.
- Hydra audio API (`setBins/fft[]/setSmooth/setCutoff/setScale`, Meyda, AGPL) — agent fetched the README directly.

**Flagged — verify the exact ID/handle before relying on it:**
- A few Shadertoy IDs came from search snippets rather than opened pages: cornusammonis Gray-Scott (`WdlcWM`), nimitz "Chimera's Breath" (`4tGfDW`). High-confidence, but confirm the ID resolves before quoting.
- Keijiro's exact repo names are confirmed individually; the GitHub *profile* page is JS-gated (didn't render in fetch).
- **XT95 ≠ "Léon Denise"** — do not conflate; XT95's profile/volumetric work is real, the real-name lead was not confirmed.
- Node-based: "vual" (Notch) not confirmed as a distinct channel (Kevin Zhu is the verified free-project Notch teacher); "Noones Image" and "Wieland/Alphamoonbase" are two different people; "mrvux"/"woei" individual channels unconfirmed (the vvvv *pack* and group tutorials are confirmed).

---

## Consolidated sources

**Raymarch/SDF:** mercury.sexy/hg_sdf · shadertoy.com/user/nimitz · the_artofcode (shadertoy 4sXBRn, WtGXDD) · github.com/patriciogonzalezvivo/lygia · thebookofshaders.com · Aaltonen GDC2018 (ubm-twvideo01 PDF) · blog.hvidtfeldts.net · shadertoy.com/view/4djSRW (Hoskins) · github.com/mrange/glsl-snippets · shadertoy.com/view/Ms2SD1 (Seascape) · shadertoyunofficial.wordpress.com · mini.gmshaders.com/p/volumetric · blog.demofox.org

**Particles/fluids:** github.com/keijiro (LaspVfx, Smrvfx, Rsvfx, Pcx) · github.com/PavelDoGreat/WebGL-Fluid-Simulation · iamnop.com + github.com/nopjia/particles-mrt · github.com/dli/fluid + dli/waves · github.com/memoakten/ofxMSAFluid · matthias-research.github.io/pages/tenMinutePhysics · shadertoy.com/user/cornusammonis · GPU Gems Ch.38 · Bridson curl-noise (cs.ubc.ca)

**Feedback/demoscene:** bleuje.com/physarum-explanation + github.com/Bleuje/physarum-36p · sagejenson.com/36points · n-e-r-v-o-u-s.com/blog/?p=9137 · mini.gmshaders.com/p/turbulence · shadertoy.com/user/cornusammonis · nusan.fr/demoscene/livecoding · ctrl-alt-test.fr/category/techniques · shadertoy.com/user/Flopine · github.com/SebLague/Slime-Simulation

**Node-based:** elekktronaut.com + youtube.com/c/bileamtschepe · interactiveimmersive.io · github.com/t3kt/raytk · simonaa.media · kevzhu.com/tutorials · alltd.org/uploader/paketa12 · federicofoderaro.com · shaderpark.com · beta.vvvv.org (DX11.Particles)

**Audio/AV:** github.com/ojack/hydra + hydra.ojack.xyz · geisswerks.com/milkdrop · roberthenke.com + ableton.com (Lumière interview) · memo.tv · icad.org/Proceedings/2009/Barri2009.pdf · github.com/CODAME/Shaders-Workshop · cycling74.com (Benson) · ryojiikeda.com

---

*Compiled June 26, 2026. Net-new finds beyond the in-house four (Quilez, Leitl, Hodgin, Hoetzlein). Techniques are free to re-implement; check the per-source license before pasting code into MIT-licensed Phosphene.*
