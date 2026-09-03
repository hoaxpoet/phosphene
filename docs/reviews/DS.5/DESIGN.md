# DS.5 — Ready becomes the arrival: design decisions

Authored at the DS.5 design pass, 2026-09-02, before any implementation. This pass happened as
live back-and-forth in chat, not against a rendered reference from the start — but unlike DS.4's
`design-pass.html`, which mocked the whole preparation screen, this one grew a single-purpose
prototype partway through: **[The Camera Push](https://claude.ai/code/artifact/b3b137db-4fb5-4a83-9059-7450b03cf1d4)**,
testing pacing and dimensionality for the one piece with no built precedent — the literal camera
move through the aperture. Its final form ports `ApertureScene.draw()`'s math to JS verbatim and
drives a radial streak burst over it; the built version (`ArrivalPushScene`) is the same
construction in SwiftUI `Canvas` over the real `ApertureScene`. *Correction, 2026-09-03:* an
earlier draft of this paragraph, and §The camera push below, forecast that the built version would
need Uzume's GPU pipeline. It did not — see §Built.

## Matt's brief, verbatim

> "Ready = opens all the way and the camera moves into the aperture to begin the show."

> "I think we might want to have a special ready state for streaming audio that lets the user
> know they need to start audio playback in Spotify or Apple Music to begin. I don't think we
> need this for local files because playback is controlled by Uzume directly."

> "Local files get a 3-2-1 countdown before transitioning into playback. For streaming, the
> camera pushes through the aperture once real audio is detected, or when users press the start
> button from the preparing screen."

> "I'm comfortable with the Start Now button sending users to the Ready step rather than
> directly into playback. This is a cleaner flow for streaming and local audio files."

> "Local-file countdown sits over the fully-open aperture. I want a literal camera move into the
> aperture. The screen should be filled with light as the camera enters the aperture, a brief
> pause, and then the show begins."

> "Lock in 'Begin now' ('enter' is too obscure)."

## The problem, stated from the code

`ReadyView` is built around exactly one axis of variation — `PlaylistSource?` (Apple Music /
Spotify) — and it does not know local files exist. `SessionManager._beginMultiFileTransition`
sets `sessionSource = nil` for every local-file origin (`SessionManager.swift`), and
`ReadyViewModel.sourceName` falls back to `String(localized: "ready.source.fallback")` —
**`"your music app"`** — whenever `sessionSource` is `nil`. `ContentView.readyView` constructs
`ReadyView` with `sessionSource: engine.sessionManager.sessionSource`, not `currentSource`
(the `SessionOrigin?` that *does* know about local files). So today, **a local-file session
reaching `.ready` shows "Ready. Press play in your music app."** — asking the listener to go
find an app that does not exist for this source, above a screen `LocalFileTransportBar`
elsewhere in the app already contradicts (Uzume owns local transport — stop / previous /
play-pause / next). This is not a hypothetical the design pass invented; it is a live
inaccuracy, found the same way COPY-001 was (Matt noticing streaming-only assumptions bleeding
onto the local-file path).

*Correction at the build (2026-09-03):* the paragraph above reads the view, not the router. A
local-file session never reached `ReadyView` at all — `ContentView` carried an LF.4-era shortcut
sending local `.ready` straight to `PlaybackView`, while the engine's `.ready` observer started
the audio in the same tick. The wrong copy was latent, not shown. The shortcut surfaced only in a
live run of the built countdown: the count never appeared, the camera push fired at `.ready`, and
no audio ever started because nothing called `handleLocalFileReady()`. Removed at D-240.

`uzume-site/docs/design/EXPERIENCE_MODEL.md` already states the rule this design follows:
*"Local playback owns transport; streaming handoff listens for external audio and must not
promise transport control."* DS.5 is the increment that finally makes the code agree with a
rule the brand doc has stated all along.

**Separately, `PlanPreviewView` and its siblings are already a removal candidate** — DS.4's own
design doc flagged them: *"`PlanPreviewView` and its siblings are already removal candidates for
violating [Never exposes upcoming content]."* `PlanPreviewView.swift`, `PlanPreviewRowView.swift`,
`PlanPreviewTransitionView.swift`, and `PlanPreviewViewModel.swift` render exactly what DS.4's own
surprise-model table forbids: which preset a track will get, and the transition style between
tracks — "the emotional arc across the session," explicitly **Forbidden** there. DS.5 is where
that removal actually happens, not a new decision — DS.4 already decided it; this increment
executes it.

## Ready is the arrival, not a waiting room

The reframe: `.ready` has been a state to sit in, waiting for something else to happen. Matt's
call makes it the payoff instead — the aperture that has been closed, cracking, and widening all
through `.preparing` finally opens the rest of the way, and the camera **moves into it** to begin
the show. The myth DS.4 anchored on says as much already (`BRAND.md`, quoted in DS.4's own doc):
*"Amaterasu looks out, and light returns."* Reaching `.ready` is that look-out moment. DS.4 built
the widening; DS.5 builds the arrival.

**One opening, still.** Nothing here reopens DS.4's own settled question of whether the aperture
should show more than one shape — it does not. This is the same aperture, now finishing its arc.

## Two ready experiences, one for each source

**Streaming keeps a real waiting room, because Uzume genuinely does not control the source.**
`uzume-site/DesignSystem/COMPONENTS.md`'s own `StreamingHandoff` component spec already
describes this shape: *"Bridge completed preparation to externally controlled playback… wait for
sustained detected audio."* That mechanism — `FirstAudioDetector`, `AudioSignalState`
`.silent → .active` sustained ≥250 ms (UX_SPEC §6.3) — is already built and does not change.
What changes is what the waiting room looks like: source-correct "press play" copy, and the cave
behind it, fully open, waiting.

**Local files get no waiting room at all, because there is nothing to wait for.** Uzume is the
one about to press play. A 3-2-1 countdown replaces the "press play in ___" copy entirely — no
app name, no external dependency stated, because none exists. The countdown ends, and the camera
push begins, source-identically to the streaming path once its own trigger fires.

| | Streaming | Local files |
|---|---|---|
| What's asked of the listener | Go press play in Spotify / Apple Music | Nothing — wait three beats |
| What ends the wait | Real audio detected, or **"Begin now"** (below) | The countdown reaching zero |
| Copy referencing an external app | Yes — source name resolved same as today | Never |
| Timeout / retry (§6.4) | Still applies — 90 s, unchanged | Not applicable — nothing external can fail to arrive |

**The manual affordance, decided.** A real bordered button — same visual weight as Cancel, not
a link and not tap-anywhere (DS.4a already proved anything quieter doesn't read as an affordance)
— sitting below the "Press play in ___" headline as the secondary path. Copy: **"Begin now"**.
Destination-labeled, matching the "Start now" / DS.4a naming convention rather than restating the
current mode; "Enter now" was considered and rejected as too obscure a verb for this context.

**The `COMPONENTS.md` tension is resolved, upstream, at Matt's direction.** The spec used to say
*"On detection, remove the handoff and cut directly to the first preset"* — a cut, not a camera
move. `uzume-site`'s `DesignSystem/COMPONENTS.md` now reads: *"Not a cut — the opening that widened
through preparation is what the listener passes through."* (`uzume-site` branch
`claude/ds5-streaming-handoff-camera-push`, committed locally, not yet pushed.) Recorded here as
the resolution, not a live tension any more — `uzume-site` owns the design system source of truth
(D-228), and it was the doc that moved, not this one overriding it.

**`COMPONENTS.md` also names a branch this design does not build:** *"If authorized integration
can start playback, do so and bypass the instruction."* No Spotify or Apple Music playback-control
API call exists anywhere in this codebase today (checked — only playlist-reading is wired). That
branch is aspirational, out of scope, and not something DS.5 needs to account for.

## "Start now" always lands on Ready, never past it

Resolved in conversation, and it is the simpler of the two options that were on the table: from
`.preparing`, whether the listener waits for natural completion or presses "Start now" early
(≥3 consecutive ready tracks), **both paths land on `.ready`** — never a shortcut straight into
`.playing`. This holds identically for streaming and local files, which is one fewer thing to
special-case than the alternative (an immediate camera-push on "Start now" that would have had to
run the visuals at baseline until real audio caught up, borrowing the app's existing
mid-session-silence handling to justify it — workable, but a special case this design doesn't
need).

`SessionManager.beginPlayback()` already only fires `.ready → .playing` and is a no-op from any
other state — no engine change needed here. "Start now" (`SessionManager.startNow()`) stays
exactly what it is today: `.preparing → .ready`.

## The camera push through the aperture

**Decided: a literal camera move**, not a 2D treatment that merely reads as one. Three beats, in
Matt's own words: the camera enters the aperture, the screen fills with light, a brief pause, then
the show begins. This is the more expensive of the two options this document originally weighed,
and it is a real scope change worth stating plainly rather than smoothing over: `ApertureScene` is
a 2D `Canvas` construction today — a flat drawing, not a navigable scene with depth. A literal
camera move needs an actual perspective — geometry the camera can travel through, not a canvas the
camera pretends to approach. That is closer to how the real preset renderer works
(`RayMarchPipeline`, mesh shaders, `SceneUniforms`) than to how DS.4's aperture was built, and it
means this transition is new rendering work, sized more like a preset build than a UI treatment —
it should go through the same prototype-before-prompt discipline the `preset-session` skill
already enforces for exactly this reason, not skip it because it's technically a "transition."

**Local files use the same aperture, the same fully-open state, and the same camera move** — the
3-2-1 countdown sits over it, then the identical transition fires. One mechanism, two triggers
(§Two ready experiences), not two builds.

## Hard constraints carried forward, unchanged

The four constraints DS.4 established for the aperture bind this transition too, and none of
them get to be assumed away because this is "just a transition":

1. **Flash safety [D-157]** applies to whatever the camera-push renders — an expanding light
   source crossing the whole frame is exactly the shape of thing the flash gate exists for.
   Needs the same measured-luminance test DS.4 used, not a shorter one because the moment is
   brief.
2. **Reduced motion.** Under `SettingsStore.reducedMotion`, the transition must still convey
   "you have arrived" — a hard cut once the trigger fires is the obvious fallback, and needs to
   be an explicit branch, not an accident of skipping animation code.
3. **Accessibility.** The countdown must have a text/VoiceOver equivalent for each number, not
   rely on visual ticking; the streaming waiting room keeps the existing headline structure,
   correctly source-branched.
4. **No new engine dependency this increment doesn't already have.** Unlike DS.4, this design
   does not need new data from `SessionPreparer` — `SessionOrigin` already exists on
   `SessionManager.currentSource` and already distinguishes local from streaming. The
   prerequisite below is real but smaller than DS.4's was.

## The prerequisite: `ReadyViewModel` needs to see `SessionOrigin`, not just `PlaylistSource`

`SessionManager.currentSource: SessionOrigin?` already carries everything needed to tell local
from streaming — `SessionOrigin.isLocalFile` already exists (`SessionTypes.swift`). The fix is
threading it through: `ReadyViewModel.init` and `ContentView.readyView`'s construction site both
currently pass only `sessionSource: PlaylistSource?`. This is app-layer plumbing, not an engine
change — smaller than DS.4's `trackProfiles` prerequisite, but still its own early, separate
commit, since every other piece of this design depends on the view actually knowing which source
it's showing.

## The plan preview is deleted, not redesigned

`PlanPreviewView.swift`, `PlanPreviewRowView.swift`, `PlanPreviewTransitionView.swift`, and
`PlanPreviewViewModel.swift` are removed outright. DS.4's own surprise-model table already ruled
on this — showing per-track preset assignment and transition style is exactly "the emotional arc
across the session," which is Forbidden there, not merely undesirable here. `ReadyView`'s
"Preview the plan" affordance and `ready.preview_plan_button` go with them. This is DS.5 executing
a DS.4 decision, not making a new one.

## Deliberately not decided here

- **How the camera move is actually built.** A literal camera move is now the *intent*; the
  *mechanism* — a real render pass, its cost against the 60fps/1080p budget, how it hands off to
  the first preset's own render pass — is not designed here. Needs a prototype.
- **Naming for the local-file counterpart of `StreamingHandoff`.** The Phase DS plan already
  names `ReadyView` → `StreamingHandoff` for the streaming case (`ENGINEERING_PLAN.md`); the
  local-file view has no name yet.
- **Whether `uzume-site`'s branch gets pushed and merged.** Committed locally; pushing either
  repo is a separate decision from writing the doc.

## Built (2026-09-03, D-240) — what the three open items became

- **The mechanism is a `Canvas` construction, not a render pass.** The prototype answered the
  question this doc left open, and it answered it the cheap way: `ArrivalPushScene` composites the
  real, unmodified `ApertureScene` (scaled modestly toward its own centre — a supporting cue) under
  a 100-streak radial burst racing outward from the opening's centre, then a late whiteout. The
  burst's near/far parallax is what reads as the viewer moving in; two prototypes were rejected
  live before that was understood — a redrawn approximation of the aperture, then a uniform zoom on
  the real frame ("it looks like the aperture is coming out, not the camera moving into it").
  §The camera push above forecast "geometry the camera can travel through … closer to how the
  real preset renderer works"; that forecast was wrong, and the paragraph stands as written so the
  correction is visible. Cost to the preset pipeline: none — `MetalView` is live underneath from
  the first frame and the overlay simply fades to reveal it. Flash-gated (maxΔ/frame 0.0174 < 0.05).
- **The local-file view is `LocalFileCountdownView`.** Plain, destination-named, no lore — the
  same reasoning D-239 applied to the toggle. `ReadyView` keeps its name for streaming; it was not
  renamed to `StreamingHandoff` because the identifier `uzume.view.ready` and its tests are pinned
  and the rename would be churn without a consumer.
- **`uzume-site`'s branch is still local.** Unchanged: `claude/ds5-streaming-handoff-camera-push`,
  committed, not pushed. Pushing is Matt's call, separately from the app PR.

- **From Matt's first M7 pass (same day, session `2026-09-03T15-58-14Z`), two more.** Ready
  self-advanced with no audio — §Two ready experiences above says the detection mechanism "is
  already built and does not change"; it was built, but it had never listened: the tap was only
  installed after `.playing`, so the detector watched a default `.active` (BUG-112). The tap now
  comes up at `.ready`. And the copy over the cave sits on `ApertureScrim` rather than a shadow —
  Matt: *"concerned about sufficient color contrast."* Both his call between two options each.

Also built, as decided above: `OpenAperture` behind both ready screens; `ReadyViewModel` takes
`SessionOrigin?`; "Begin now" as a bordered button of the same weight as End session; the count
runs over silence because `handleLocalFileReady()` now fires from the countdown's end rather than
the engine's `.ready` observer; the plan preview deleted outright, and `ReadyPulsingBorder` with it.
