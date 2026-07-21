---
name: preset-concept
description: Invoke BEFORE pitching Matt any new preset concept, or when deciding what preset to build next. The gate that converts a concept from prose into proof — a specific proven moving artifact, a grounded three-sentence story, and a running motion-gated look-spike, shown not told. Sits UPSTREAM of preset-session (which assumes the concept is already chosen).
---

# Preset Concept Gate

Every rejected concept in the record failed the same way: it was **prose** — a described vision, adjectives, or a mechanic with no watched look — pitched to Matt instead of **proof**. This skill makes that failure structurally impossible. It does **not** manufacture taste or invent aesthetics; it forbids pitching words and forces artifacts. A concept that cannot produce the four artifacts below is not a concept yet — do not pitch it, do not build it.

**Grounding truth (from the record).** The presets that CERTIFIED were faithful ports of a specific proven source watched in motion: Aurora Veil ← nimitz "Auroras" (D-185); Nacre / Floret / Glaze ← named butterchurn presets. Every concept ORIGINATED or DERIVED from prose died: Truchet Loom (D-194), Kinetic Sculpture (D-188), and six prose pitches in one sitting (2026-07-21). **Concept work here is not invention — it is finding the specific proven moving thing and proving it ports.** Treat "originate a fresh concept from imagination" as the known failure mode, not the goal.

## The four artifacts — produce ALL before pitching Matt

1. **A watched moving source.** A link to ONE specific existing artifact — a Shadertoy (with readable source), a video, a demo — that ALREADY looks like the concept, *in motion*. Not a still, not a genre label ("hyperbolic tiling"), not your own description. If you cannot point at one real moving thing you have actually played, you have adjectives, not a concept. (This is FA #73 — read-and-port the exact reference — pushed upstream into concept-formation.)

2. **The look verified in motion, not a cherry-picked frame.** Extract the source's frames (`Scripts/motion_gate.sh <slug> <source>` or ffmpeg) and confirm it delivers the intended look ACROSS the sequence. Truchet died because the mechanic (blocky Truchet lattice) and the curated reference (flowing scallop op-art) were different aesthetics that a still hid (D-194, D-195). The concept-source and the target look must be the SAME watched artifact — verify that before anything else.

3. **A three-sentence story, each sentence checkable — not adjectives.** Matt's exact rejection was "your inability to tell a story about any of these presets — how it looks, how it moves, what it DOES." Write:
   - **See** — the iconic subject in one still. Name it plainly; do not decorate it.
   - **Move** — what changes across a ~30 s cycle, tied to the motion you watched in artifact 1.
   - **Music** — the ONE musical feature → the ONE visual behaviour (the `preset-session` musical-role sentence; a specific feature per the audio data hierarchy — never "reacts to energy").
   Any sentence that is adjectives ("iridescent psychedelic flow") fails. Rewrite it into a checkable claim or kill the concept.

4. **A running look-spike, motion-gated, shown not told.** Port the source minimally to a running look — the smallest thing that moves — run `motion_gate.sh` on it, and show Matt the actual extracted frames. **The pitch IS the moving proof.** Never pitch prose and ask him to imagine it: he has said, verbatim, that is worthless to him ("word salad, not a real proposal"). Show early, show cheap, before going increments deep.

## Kill tells — you are about to fail if

- The concept is a description with no link to a watched moving artifact.
- The "source" is a still image or a genre name, not a video/shader you played.
- Any story sentence is adjectives instead of a checkable claim.
- You are injecting your own interpretation over Matt's stated direction (the Kinetic Sculpture failure, D-188 — "wire sculpture" imposed on his "psychedelic responsive geometry").
- You catch yourself defending kept code or a kept concept as "reusable infrastructure" (CLAUDE.md §Authoring Discipline).
- You are about to pitch before artifacts 1–4 exist. Stop; produce them, or say "I don't have a concept yet."

## Then hand off

A concept passes this gate only when all four artifacts exist AND Matt has seen the motion-gated look-spike. It then still must clear the **three-part concept bar** in `docs/PRESET_SESSION_CHECKLIST.md` Part 2 (iconic-subject-at-fidelity / clear-musical-role / infra-feasible). `preset-session` opens the build; `shader-authoring` governs the port (FA #73 / #64 / #65 — adopt the working source verbatim, adapt only context: scale, audio routing, scene type).
