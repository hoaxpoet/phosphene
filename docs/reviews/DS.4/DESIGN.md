# DS.4 — the preparation screen: design decisions

Authored at the DS.4 design pass, 2026-09-02, before any implementation. The animated
reference is [`design-pass.html`](design-pass.html) in this directory (published at
<https://claude.ai/code/artifact/2e96c872-7f93-4b4e-a2c6-d57ec96e1298>). This file is the
contract; the HTML is the look.

## Matt's brief, verbatim

> "i want people to feel entertained and excited during preparation"

> "let's go with A, and keep Start now as a button"

> "What about a single opening in the cave where light spills out. The opening widens as the
> preparation proceeds."

> "It would be lovely if the preparation looked different based on the playlist content."

> "Consider the logo, which has a prism of color. I think we want a kaleidoscope of color
> spilling out of the opening, not different moods of color."

> "I think we will also want to provide users with the option to toggle between the mysterious
> view, where the contents of the playlist are never revealed to the listener/viewer, and a
> detailed view, like direction B, where there is detail about the individual tracks in the
> playlist."

> "For the mysterious view, this is an aperture, so the opening should start closed, and
> increase from a pinwheel size to a larger opening."

> "Consider that it could take 3-5 minutes to prepare a playlist from end to end. This is a
> substantial wait, so the solution needs to be suitably appropriate."

Nothing below may drift from those. If an implementation choice does not make the wait more
entertaining or more exciting, it is not DS.4's business.

## Three executions were falsified before this one

Recorded because each failed for a reason worth not repeating.

1. **One permanent shaft per track, aperture = fraction complete.** Breaks at Tunes Club
   scale. Forty shafts is a picket fence, and — worse — at forty tracks the opening would be
   **7.5 % open at the exact moment "Start now" unlocks**. The aperture was measuring the
   wrong quantity.
2. **A left-to-right landscape of the playlist.** Scaled, but still enumerated, and still
   made the per-track mark the unit.
3. **A single averaged hue for the spill.** Averaging mood quadrants in circular space
   converges *every* playlist on the same muddy amber — the exact opposite of "looks
   different based on the playlist content".
4. **Colouring the cave by mood at all.** Even fixed, a mood-tinted wash is the wrong
   identity. The logo puts a *prism* through the opening; the spill is a kaleidoscope of the
   full published spectrum, always.

The surviving design is Matt's: **one opening, and the light spilling out of it carries the
playlist's character.**

## The problem, stated from the code

Preparation today is a file-transfer dialog: a header, a progress bar, and rows reading
`Waiting` → `Finding preview` → `Downloading` → `Separating stems` → `Caching` → `Ready`.
It reports on machinery.

Meanwhile `TrackProfile` is being filled in for every track — `bpm`, `key`, `mood`
(valence × arousal), `spectralCentroidAvg`, `genreTags`, `stemEnergyBalance`,
`estimatedSectionCount`. All of it computed from the 30-second preview, cached, handed to
the Orchestrator, and **never shown to the user**. The material for an interesting wait is
already being generated and thrown away.

## Two views ship, and the listener chooses

**Grounded in beta feedback, not a hunch.** Matt, relaying a beta tester: *"some people are
going to want to know details about the playlist and some are going to prefer mystery. We need
to be able to address the desires of both."* That is the whole justification, and it is a
stronger one than any argument from taste.

DS.4 delivers **both** postures behind a preference, not one with the other rejected:

| View | What it does | Who it is for |
|---|---|---|
| **Mysterious** (default) | The cave. Never names a track, never shows a number about the music. | Someone who wants the wait to stay a held breath. |
| **Detailed** | The list, reporting what Uzume just heard — tempo, key, mood, stem balance, per track. | Someone who wants to know what is happening, and enjoys the readout. |

**The setting.** `uzume.settings.visuals.preparationView`, following the established
`SettingsStore` pattern (`@Published` + `didSet` encode, key scheme
`uzume.settings.<group>.<key>`). Changeable at any time, including mid-preparation. It is a new
key, so no `SettingsMigrator` entry is required — but a **default must be chosen and stated**,
and mysterious is it.

**Why this is a preference and not a default with a debug escape.** The detailed view spends
the surprise deliberately; the mysterious view protects it. Neither is the "advanced" one. The
surprise-model rules below bind **both** views identically — even Detailed may only show what
Uzume *heard*, never what it will *do*.

## The aperture starts closed

Matt's instruction: *"this is an aperture, so the opening should start closed, and increase
from a pinwheel size to a larger opening."*

- **At rest the cave is shut.** Nothing spills. The frame is genuinely dark, not dimly lit.
- **The first track heard cracks it to a pinprick** — a bright point with the faintest prism
  just escaping.
- **The light spills in every direction.** An opening radiates; it is not a spotlight. An
  earlier build fanned the shafts upward only, which read as a lamp rather than a cave mouth.
  The prism sweeps the full circle, so the burst is a kaleidoscope on every side.
- **The colour arrives with the light.** Vibrancy ramps with the aperture: barely cracked, the
  spill is a pale ivory-ish glimmer with almost no chroma; wide open it saturates past full.
  Each channel rotates around its own luminance, so the prism's hues never shift — only their
  intensity. This is what makes the end of a four-minute wait feel like an arrival.
- **From there it grows** through the engine's four readiness stops
  (`preparing → readyForFirstTracks → partiallyPlanned → fullyPrepared`), so it is properly
  open the moment the listener can start, at any playlist length.

**The opening is organic, not mechanical** (Matt, 2026-09-02). An irregular rock opening
growing from a pinprick — no blades, no visible mechanism. This keeps `BRAND.md` intact:
*"a play of shadow and light rather than a pictured aperture."* The edge wobble is driven by
the playlist's beat irregularity, so the opening still has character without becoming a
machine. A mechanical iris was considered and declined; it would have required editing the
brand source of truth in the same breath ([D-228]).

## The duration is the design constraint

**Three to five minutes**, end to end, for a real playlist. That is the length of a song, and
it rules out a great deal:

- **No single gesture holds it.** An aperture that widens and pulses is lovely for twenty
  seconds and wallpaper by minute two. The image must keep developing.
- **It must be glanceable.** People will alt-tab. Coming back, the state must be readable at
  once — how far along, and whether you can start.
- **The real job is making the wait worth it.** Three ready tracks unlock "Start now" well
  inside the first minute, so **the overwhelming majority of preparation happens after the
  user could already have left**. The screen's argument is: stay, and it gets better. That
  argument has to be *visible* — the light must demonstrably deepen and become more specific
  as more of the playlist is heard, not merely brighter.

## The concept, anchored on the brand's own words

`uzume-site/BRAND.md`, describing the **First Opening** identity:

> "Two shadows nearly meet, leaving a tiny irregular opening through which prismatic light
> enters the dark. It is a play of shadow and light rather than a pictured aperture:
> **darkness is the condition, the opening is the event, and color is the consequence.**"

And the myth the product is named for, from the same file:

> "In the **Ama-no-Iwato** myth, the world darkens when Amaterasu withdraws into the heavenly
> **rock-cave**. Omoikane **prepares a plan**; Ame-no-Uzume performs… Amaterasu looks out, and
> **light returns**. The product mapping is direct: **a session is planned**, a visual
> performance unfolds, and music is answered in light."

**"A plan is prepared" is this screen.** The cave opening widening while the plan comes
together is the myth's own decisive change, rendered at the moment the product actually does
it. This is not a metaphor imported from outside the brand; it is the brand's own map.

**One opening. No per-track marks.** Eight tracks and forty are the same object, which is what
makes it scale-free. A track landing *surges* the light; it does not leave a mark.

**The aperture tracks readiness, not completion** — the engine's own four stops
(`preparing → readyForFirstTracks → partiallyPlanned → fullyPrepared`). Three ready tracks
opens it properly at any playlist length, because that is when the user really can start.

## The colour is the identity's prism, and it never varies

`BRAND.md` gives two rules that settle this completely:

> "Keep the ivory opening brighter than the surrounding spectrum."

> "Do not recolor, sharpen, add type or glow, **flatten the spectrum into bands**, or place the
> icon over photography."

So: **the mouth is ivory**, brighter than everything around it, and what spills is a
**continuous kaleidoscope of the full published spectrum** — violet, cyan, gold, ember — never
banded and never tinted by content. Hue is identity, not data.

## The playlist changes how the light behaves, not what colour it is

Five properties of what has been heard drive five different things, so the same mechanism and
the same spectrum produce unmistakably different images:

| What Uzume hears | What it changes | So a playlist that is… |
|---|---|---|
| Mood **spread** (circular variance, not average) | How fast the prism churns through the fan | …varied churns quickly; uniform drifts slowly. **Both sweep the whole spectrum** — variety never buys more colour |
| Average tempo | The rate everything moves at | …fast shimmers; slow breathes |
| `spectralCentroidAvg` | Edge and contrast of the shafts | …bright throws hard-edged beams; dark glows soft and diffuse |
| Drums vs. vocals in `stemEnergyBalance` | Ray definition vs. smooth wash | …drum-forward is ribbed and defined; vocal-forward is a continuous wash |
| `beatIrregular` | How much the mouth wavers | …metronomic sits still; loose and human breathes |

Verified in the mock: late-night jazz renders a slow, soft, diffuse spill; peak-time techno a
fast, hard-edged, ribbed one — both in the same full prism. These are starting mappings, not a specification to defend —
what matters is that **every visual property derives from what Uzume heard**, and that the
image becomes *more specific* as more is heard, not merely brighter.

## The surprise model — the constraint that shapes everything

`uzume-site/DesignSystem/COMPONENTS.md` is absolute: **"Never exposes upcoming content."**
`PlanPreviewView` and its siblings are already removal candidates for violating it.

**The line that makes this design legal:** it reveals what Uzume **heard** in music the user
already chose — never what Uzume will **do** with it.

| Showing | Verdict |
|---|---|
| Tempo, key, mood, stem balance of a track the user picked | **Allowed.** Analysis of known input. `BRAND.md` grants the full spectrum to "meaningful metadata". |
| Which preset a track will get | **Forbidden.** Upcoming choreography. |
| The emotional arc across the session | **Forbidden.** This is what `PlanPreviewView` did. |
| How many tracks are ready; that you can start | **Allowed.** Session state, not content. Already shipped. |

If an implementation question is ever "would showing this spoil the performance?", the answer
is decided by *heard vs. will-do*, not by taste.

## What stays, and why it is not a compromise

**The track list survives.** `previewNotFound` and `stemSeparationFailed` are
`.inlineOnRow` (`UserFacingError+Presentation.swift:76`) — they must render on the affected
track's row. A design that deletes the list breaks the error taxonomy. The opening sits
*above* a quieter list, it does not replace it.

**"Start now" stays a button** (Matt's call). The opening may signal readiness, but it never
becomes the control. Same for Cancel.

**`NoticeBanner` keeps its slot** above the list — DS.3 built it, DS.4 consumes it unchanged.

## Hard constraints on the light field

1. **Flash safety is not negotiable.** [D-157] — bounded max per-frame brightness change and
   steady global luminance — is this product's actual flash gate ([D-228] corrected public
   copy that claimed otherwise). The opening animates *slowly and additively*; a new track
   arriving is a swell, never a flash. This needs a measured test in the
   `MitosisSketchRenderTests` / `MultiPassFlashHarnessTests` idiom, not an assurance.
2. **Reduced motion is first-class.** `SettingsStore.reducedMotion` already exists and is
   pushed to the engine. Under it, the opening still *renders* and still widens — it simply
   stops animating between states. The information must not be motion-dependent.
3. **Accessibility must not depend on the light.** A canvas of colour is invisible to
   VoiceOver. Every fact the opening conveys — how many heard, that you can start — must
   have a text equivalent. This is the same obligation DS.3 met.
4. **It must not slow preparation down.** The GPU is running MPSGraph stem separation during
   exactly this screen. A continuously-animating surface competes with the work it is
   describing. The increment measures preparation wall time with the opening on and off; a
   measurable regression means the animation gets cheaper, not that the measurement gets
   dropped.

## The prerequisite that does not exist yet

`TrackPreparationStatus` carries **only the stage** — `.analyzing(stage:)`, `.ready`,
`.partial(reason:)`. The `TrackProfile` never reaches the App layer. Either the status gains
the profile on its terminal cases, or a parallel per-track publisher carries it.

This is an **engine-side change in `UzumeEngine/Sources/Session/`**, and it is a hard
prerequisite: without it the opening has nothing to be coloured by, and would be decorative —
exactly what this design is not.

## Deliberately not decided here

- The exact geometry of the seam and the shafts. `design-pass.html` is a look reference, not
  a spec; the built version should be better than the mock, not a port of it.
- Whether a track's detail (its tempo, key, mood as text) is reachable on hover or focus.
  Worth trying, but it is direction B's idea and it is not what Matt picked.
- Whether the opening survives into `.ready`. That is DS.5's screen.

