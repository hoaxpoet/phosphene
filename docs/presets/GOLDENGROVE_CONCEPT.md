# Goldengrove — Concept

**Status:** concept for sign-off. No shader code until approved.

---

## What you see

A single great tree, filling the frame, at golden hour. The low sun sits **behind** it — so the whole canopy is **back-lit and glowing**, the leaves translucent and warm the way foliage goes when the light comes through it rather than off it. The crown is dense and **asymmetric** — a billowing cloud-mass of fine branches, leaning, never mirror-symmetric. The bark catches a warm rim of light down one edge. Dust motes drift in the shafts of light. A low bank of fog pools around the base and fades out by the lower branches.

The whole image is **painterly, not photoreal** — soft-edged color masses with an Impressionist softness, like a plein-air painting of a tree rather than a crisp 3D render. Color blocked, not detail-etched.

The default palette is **autumn**: the canopy is a tapestry of deep green, gold, orange, and ember-red — varying leaf to leaf, with green holdouts mixed through, the way a real autumn tree is never uniformly turned. It reads warm, alive, and a little melancholy — the Hopkins "Goldengrove unleaving" feeling the name carries.

## What it does over a song — *this is the heart of it*

**The tree grows with the music, blooms at the peak, and sheds at the turns.**

- **Quiet open** — a sparse silhouette. Trunk and a few first branches, dim, the light still low and cool. The tree is *waiting*.
- **The build (verse)** — branches reach outward and upward, generation by generation, as the song gathers. The canopy starts to fill in. The light warms toward gold.
- **The peak (chorus / drop)** — the canopy **bursts into full radiant foliage**, back-lit and glowing, at the exact moment the song swells. *This is the payoff.* You watch the bare-ish tree bloom into a full golden crown right as the music opens up. That's the moment a listener points at and says "that's the song."
- **The sustain** — once full, wind moves through the canopy; leaves shimmer and sway, the light breathes.
- **The turn (section boundary / outro)** — leaves **release and drift down** through the light, the canopy thins, the tree settles — and is ready to build again for the next track. Every section boundary is a small release; the end of a song is the tree letting go.
- **Across the playlist** — the **season** shifts with the song's mood. A heavy or sad track turns the tree to **winter** — bare branches, cool light, hoarfrost. A bright track brings **spring** green or **summer** fullness. Default is autumn fire. Each track gets its own color-world *and* its own bloom-and-release arc.

So: not "a tree that twitches with the beat." A tree that lives a whole small life across each song — grows, blooms at the high point, lets go at the end.

## How it's different from the Fractal Tree we're keeping

The existing **Fractal Tree** is a flat, graphic, almost-diagram branch-fan — black lines on a bright field — that flicks bigger and smaller with the bass. Playful and abstract; we're keeping it exactly as-is.

**Goldengrove** is the opposite register: dimensional, painterly, golden-hour, *almost photographic but soft* — a tree you could half-believe is real, that builds an emotional arc across a whole song instead of reacting frame-to-frame. Same subject, completely different feeling — which is why it's a new preset, not a replacement.

---

## Is it buildable, and what's the bet?

**Buildable — and on unusually solid ground.** Every part of the look maps to a technique the engine already has (bark, translucent leaves, golden-hour light, surface depth), and the "tree grows" mechanic is already prototyped in the existing Fractal Tree — we'd be driving it from the song's *structure* (build → peak → shed) instead of raw bass. Crucially, this is *not* the trap Arachne fell into (references demanding things the engine couldn't render). Here the engine can render all of it.

**The honest bet:** this is an ambitious *painterly* look, and painterly hero visuals are exactly the kind that take several review-and-tune rounds with your eye to get right (Lumen Mosaic took 8, Ferrofluid Ocean took dozens). The references and existing recipes stack the odds well, but I can't promise first-pass fidelity — this is a build-and-review grind, not a quick win. There's also a performance budget to respect (lots of leaves + surface detail), which we'd design around from the start.

## What I'd want to confirm

1. **Is this the tree you want?** — the picture above (back-lit golden-hour autumn tree, painterly, that grows-blooms-sheds across each song with seasonal mood shifts). If any of that is wrong, it's far cheaper to fix here than in code.
2. **Where to start.** My recommendation: build the **grow-bloom-shed behaviour first** on cheap placeholder geometry, so you can confirm *the tree feels alive with the music* before we spend the real effort on bark, glowing leaves, and light. If the life isn't there on a rough tree, no amount of beautiful foliage saves it.

*(Engineering feasibility detail — recipe mapping, the growth state-machine design, perf budget, the layer-by-layer build plan — is real and checks out; it's kept out of this doc on purpose. Ask and I'll walk through any of it.)*
