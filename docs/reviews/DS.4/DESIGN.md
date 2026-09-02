# DS.4 — the preparation screen: design decisions

Authored at the DS.4 design pass, 2026-09-02, before any implementation. The animated
reference is [`design-pass.html`](design-pass.html) in this directory (published at
<https://claude.ai/code/artifact/2e96c872-7f93-4b4e-a2c6-d57ec96e1298>). This file is the
contract; the HTML is the look.

## Matt's brief, verbatim

> "i want people to feel entertained and excited during preparation"

> "let's go with A, and keep Start now as a button"

Direction A of the design pass. Nothing below may drift from those two sentences: if an
implementation choice does not make the wait more entertaining or more exciting, it is not
DS.4's business.

## The problem, stated from the code

Preparation today is a file-transfer dialog: a header, a progress bar, and rows reading
`Waiting` → `Finding preview` → `Downloading` → `Separating stems` → `Caching` → `Ready`.
It reports on machinery.

Meanwhile `TrackProfile` is being filled in for every track — `bpm`, `key`, `mood`
(valence × arousal), `spectralCentroidAvg`, `genreTags`, `stemEnergyBalance`,
`estimatedSectionCount`. All of it computed from the 30-second preview, cached, handed to
the Orchestrator, and **never shown to the user**. The material for an interesting wait is
already being generated and thrown away.

## The concept, anchored on the brand's own words

`uzume-site/BRAND.md`, describing the **First Opening** identity:

> "Two shadows nearly meet, leaving a tiny irregular opening through which prismatic light
> enters the dark. It is a play of shadow and light rather than a pictured aperture:
> **darkness is the condition, the opening is the event, and color is the consequence.**"

The preparation screen becomes that sentence, running. Darkness is the waiting state. Each
track Uzume finishes hearing is an opening event. The colour is what it heard.

**Progress is the aperture.** The opening widens as tracks complete, so there is no separate
progress bar — the widening *is* the progress readout.

Per-track light is derived from that track's profile:

| Property | Source | Why |
|---|---|---|
| Hue | `mood.quadrant` (happy / calm / tense / sad) | The most human-legible thing Uzume derives |
| Reach / height | `stemEnergyBalance` aggregate | Loud, dense tracks throw further |
| Brightness | `spectralCentroidAvg` | Bright tracks read bright — the one literal mapping |

These are starting mappings, not a specification to defend. What matters is that every
visual property is *derived from what Uzume heard*, never decorative or random.

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
