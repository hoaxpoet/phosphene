# Phosphene — UX Specification

**Status:** Draft v0.2. Canonical source for user-facing product UX. Engineering-level UI decisions live in `ARCHITECTURE.md §UI Layer`; error-handling internals live in `RUNBOOK.md`.

**Scope:** What the user sees, hears (via UI sound), reads, and does. Permissions, onboarding, session flow, recovery flows, error handling, settings, accessibility.

**Out of scope:** Audio pipeline internals, render pipeline internals, preset authoring (see `SHADER_CRAFT.md`), orchestrator scoring.

**Changes from v0.1:** Persona model simplified from three roles to two (Curator + Active Viewer) to reflect the real use-case collapse. Preparation-time tolerance raised from 30 seconds to 2 minutes given delightful performance as the trade-off. New `§8 Recovery & Adaptation Flows` addresses mid-session disappointment and pre-play plan review — previously only the happy path was specified. `§7.9 Dedicated Output Display` elevates the Host-with-external-display scenario to first-class. "Increment" spelled out throughout (was abbreviated "Inc" in v0.1).

---

## 1. Personas

Two personas. They are not mutually exclusive — in almost every session both are present, and often the Curator is simultaneously an Ambient User or Active Viewer of their own session.

### 1.1 The Curator (primary)

The person who builds the playlist, runs Phosphene, owns the experience. In a listening-party scenario they're also the host. In a solo session they're also the person experiencing the visuals (what v0.1 called the "ambient user" was never a separate persona — it's the Curator in a different mood).

**What they need:** preparation that feels worthwhile, an unambiguous signal that Phosphene is ready, in-session controls that let them steer the experience without disrupting viewers, mid-session recovery when things go wrong.

**What they will tolerate:** up to 2 minutes of preparation on larger playlists, if the result is delightful. This is a significant shift from v0.1's 30-second ceiling — the Curator *will* wait if Phosphene delivers. What they will not tolerate: 2 minutes of preparation followed by mediocre output.

**What they will not tolerate:** a session that's disappointing with no mechanism to fix it, errors that interrupt the experience for viewers, hidden controls they can't find when they need to intervene.

**Key moments of truth:** preparation feels like anticipation rather than waiting; the handoff from prepared to playing is confident; mid-session steering is silent and immediate; mid-session failure recovery is obvious and reversible; visual quality meets the viewer's eye from the first frame.

### 1.2 The Active Viewer (secondary)

The person invited by the Curator to experience the playlist and visuals. They want immersion and delight. They have high standards for visual quality and synchronization, and they do not distinguish between the audio and the visuals — both are "the experience."

**What they need:** continuous, compelling visuals that feel synchronized to the music. That's the entire contract.

**What they will tolerate:** occasional subtle transitions, occasional presets they don't personally love, brief moments of reduced intensity during quiet passages.

**What they will not tolerate:** visible error messages in their line of sight, frame stutter or obviously dropped frames, cheap-looking shaders that read as "from a 2005 screensaver," audio/visual desynchronization, black frames, long gaps between presets, uninspired or repetitive preset sequences.

**They do not interact with the app.** They don't press keys, don't see the debug overlay, don't see error toasts (Curator sees toasts; viewers don't). Their only channel is their reaction: talking, saying "this is boring," or being visibly dazzled.

**Key moments of truth:** from first frame the visuals are compelling; no visible technical seams; variety across a session keeps attention; during quiet passages the visuals stay alive rather than going static.

### 1.3 Persona implications for this spec

- The **Active Viewer is silent**. Their dissatisfaction reaches the Curator only via body language or spoken feedback. Phosphene cannot observe them. Recovery mechanisms must therefore be available to the Curator via a channel the viewer doesn't see — keyboard shortcuts, hidden panels, second-display controllers.
- Every degradation during `.playing` must either recover invisibly or be surfaced only where the Curator can see it, not where viewers can.
- Visual quality ceiling (Phase V) is primarily the Active Viewer gate. Robustness (Phase 7) is primarily the Curator gate.
- The Curator-as-Active-Viewer collapse means solo sessions can skip the controller/output split (§7.9). Party sessions require it.

---

## 2. Session Lifecycle → UI View Mapping

`SessionState` (defined in `Session/SessionTypes.swift`) has six states. Each must map to a distinct, testable top-level view. `ContentView` is a pure switch on `SessionManager.state`; it owns no logic beyond routing.

| State | Top-level view | Primary visible content | User actions available |
|---|---|---|---|
| `.idle` | `IdleView` | Phosphene logo, "Connect a playlist" CTA, "Start listening" (ad-hoc fallback) | Pick a source, start ad-hoc mode, open settings |
| `.connecting` | `ConnectingView` | Per-connector spinner with honest copy ("Asking Apple Music for your playlist…") | Cancel |
| `.preparing` | `PreparationProgressView` | Track list with per-track status + aggregate progress + partial-ready CTA | Cancel, "Start now" (when progressive-ready), retry individual track |
| `.ready` | `ReadyView` | "Press play in [Apple Music / Spotify / your music app]" + plan-preview affordance (§6.2) | Preview plan, modify plan, return to preparation, cancel session |
| `.playing` | `PlaybackView` | Visuals full-bleed + auto-hiding overlay chrome + hidden recovery shortcuts | Toggle overlay, fullscreen, feedback nudges, preset nudges, re-plan, end session |
| `.ended` | `EndedView` | Summary card: track count played, session duration, "Open sessions folder" | Start new session, quit |

**Hard rule:** no state ever shows a solid black screen without a legible message. `PlaybackView` is the only full-bleed state; its minimum floor on silence is the idle visualizer described in `§7.5`.

---

## 3. First-Run Onboarding

### 3.1 Permission check

On every app foregrounding, check `CGPreflightScreenCaptureAccess()`. If `false`, route to `PermissionOnboardingView` regardless of session state. This is not a one-time flow — a user who revokes permission in System Settings must be caught on return.

### 3.2 `PermissionOnboardingView`

One screen. No wizard.

**Headline:** "Phosphene needs permission to hear music playing on your Mac."

**Body (three short sentences, not a wall of text):**

> To follow along with your music, Phosphene listens to the audio coming out of your speakers — the same way a screen recorder would. It doesn't record your screen, your microphone, or anything else. Nothing ever leaves your Mac.

**Primary CTA:** "Open System Settings" — opens `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.

**Secondary link:** "Why does this need screen recording permission?" — reveals a second paragraph:

> On macOS, permission to capture system audio is bundled with screen recording permission. Apple groups them together. Phosphene uses only the audio portion.

**Return detection:** when the app foregrounds with `CGPreflightScreenCaptureAccess()` now `true`, auto-advance to `.idle`. Don't require a user click.

### 3.3 Photosensitivity notice (first-run only)

After permission is granted, before first session, show a one-time notice:

> Phosphene renders high-contrast, fast-changing visuals. If you're sensitive to flashing lights or strobe patterns, enable **Reduce motion** in Settings before starting.

Two CTAs: "I understand" (dismisses, stored in `UserDefaults`), "Enable Reduce motion" (flips the setting, dismisses).

### 3.4 What onboarding is *not*

No tour. No "pro tips." No email capture. No account. No dark-pattern skip-to-settings chicanery. If the permission is granted and the photosensitivity notice is acknowledged, the user reaches `.idle` in two taps.

---

## 4. Playlist Connection Flow

### 4.1 `IdleView`

Two primary affordances:

1. **"Connect a playlist"** — opens `ConnectorPickerView`.
2. **"Start listening now"** — enters ad-hoc reactive mode directly (skips preparation). Uses `DefaultReactiveOrchestrator` path (Increment 4.6).

A tertiary "Settings" button sits in the top-right corner.

Nothing else on this screen. Phosphene logo, two buttons, settings gear.

### 4.2 `ConnectorPickerView`

Three tiles:

| Tile | Subtitle | Connector | Available when |
|---|---|---|---|
| Apple Music | "Pick a playlist you're playing" | `AppleMusicAppleScriptConnector` | Apple Music app is running |
| Spotify | "Paste a Spotify playlist link" | `SpotifyWebAPIConnector` | Always (paste flow) |
| Local folder | "Point at a folder of tracks" | `LocalFolderConnector` (future — Increment MD.6+ prerequisite) | Feature flag off in v1 |

If Apple Music isn't running, its tile is disabled with caption "Open Apple Music first" and a button to launch it. Don't auto-launch — that's presumptuous.

### 4.3 Apple Music flow

`AppleMusicAppleScriptConnector.connect()` returns one of:

- `.success(Playlist)` — currently-playing playlist captured
- `.noCurrentPlaylist` — user isn't playing anything yet
- `.notRunning` — Apple Music closed
- `.permissionDenied` — AppleScript permission not granted (System Settings → Privacy → Automation)
- `.error(underlying)` — any other AppleScript failure

UI response per case:

- `.success` → advance to `.preparing`
- `.noCurrentPlaylist` → "Start playing a playlist in Apple Music, then come back." with auto-retry every 2 s while this view is visible
- `.notRunning` → "Apple Music isn't running. Open it and start a playlist." with a "Open Apple Music" button
- `.permissionDenied` → same pattern as `PermissionOnboardingView`, for AppleScript
- `.error` → "Something went wrong talking to Apple Music." + "Try again" CTA + Spotify fallback suggestion

### 4.4 Spotify flow

`SpotifyWebAPIConnector` is URL-paste only in v1. No OAuth.

UI: single text field captioned "Paste a Spotify playlist link." Placeholder: `https://open.spotify.com/playlist/...`. Accepts any URL variant (`spotify:playlist:...`, `open.spotify.com/playlist/...`, with or without query params).

Validation on paste:

- Valid playlist URL → "Found [Playlist Name] — [N] tracks" preview, `Continue` button
- Valid track/album/artist URL (not playlist) → "That's a [track/album/artist], not a playlist. Phosphene needs a playlist URL."
- Invalid → "That doesn't look like a Spotify playlist link."

Rate-limit handling: Spotify Web API has client-credentials rate limits. If hit during `.connecting`, show "Spotify is being slow — still trying" (auto-retry backoff `[2 s, 5 s, 15 s]`). If three attempts fail: "Couldn't reach Spotify. Check your network or try a different source."

### 4.5 Cancel at any point

`Esc` and the `Cancel` button in each view return to `.idle`. No "are you sure" confirmations during connection — cheap to redo.

---

## 5. Session Preparation UI

### 5.1 The problem

A preparation phase with no feedback feels broken regardless of how long it takes. A preparation phase with legible per-track feedback can take two minutes and still feel like anticipation — especially if the Curator trusts that the result will be delightful.

Phosphene's design bet: Curators will wait up to 2 minutes for large playlists if Phosphene earns that time. The UI's job is to make the wait feel purposeful, not stalled.

### 5.2 `PreparationProgressView` layout

Three regions stacked vertically:

**Top — playlist header (120 pt):** playlist name, total track count, source icon, estimated time remaining, cancel button. Estimated time is honest — 20–120 seconds typical, rounded to 15 s increments.

**Middle — track list (fills):** scrollable list, one row per track. Row shows:

- Track number
- Title + artist (two lines, truncated with tooltip)
- Status indicator (see status vocabulary below)
- Duration

The first track in `.ready` state is highlighted — it's what will play first.

**Bottom — action bar (80 pt):** aggregate progress bar + `Start now` CTA (appears at progressive-readiness threshold, Increment 6.1) + `Cancel` secondary.

### 5.3 Track status vocabulary

Every track is in exactly one of these at any moment:

| Status | Icon | Copy | When |
|---|---|---|---|
| `.queued` | ·  | "Queued" | Not yet started |
| `.resolving` | ⟳ | "Finding preview…" | `PreviewResolver` in flight |
| `.downloading` | ↓ | "Downloading…" | Preview bytes transferring |
| `.analyzing` | ◉ | "Analyzing…" | Stem separation + MIR running |
| `.ready` | ● | "Ready" (first ready track: "Up first") | In `StemCache` |
| `.partial` | ◐ | "Partial" — with tap-to-expand explanation | Missing preview but has metadata BPM/genre; can still be planned |
| `.failed` | ⚠ | "Skipped — [reason]" | Unrecoverable; orchestrator plans around it |

`PreparationProgressPublishing` protocol (new, introduced in Increment U.4) publishes `[TrackID: TrackPreparationStatus]` observable state from `SessionPreparer`. View subscribes via Combine.

### 5.4 "Start now" affordance

Appears once Increment 6.1 (`ready_for_first_tracks`) threshold is hit — default 3 consecutive ready tracks starting from position 1.

Copy: **"Start now with [N] tracks ready — we'll keep preparing as you listen."**

Tapping advances to `.ready` state. Preparation continues in background. `SessionManager` exposes `progressiveReadinessLevel: ProgressiveReadinessLevel` so `PlaybackView` can show a subtle indicator while trailing tracks prepare.

### 5.5 Cancel

Cancel stops preparation, tears down pending network + MPSGraph work, returns to `.idle`. Already-completed track analyses stay in `StemCache` for the next attempt — wasted bandwidth costs users money.

### 5.6 Long-preparation fallback

If preparation takes longer than **90 seconds** for the first track (exceptional — slow network, API rate limit, large playlist), the copy changes:

> "Still working on the first tracks. Slow network? You can [Start in reactive mode] instead and we'll pick up the planned session once it's ready."

If preparation exceeds **2 minutes of total elapsed time** without reaching progressive-ready, surface a second escape:

> "This is taking longer than expected. [Try again] • [Start reactive mode]"

Reactive mode is `DefaultReactiveOrchestrator` — the ad-hoc fallback. This guarantees Phosphene always has a path to `.playing` from `.preparing`, even on degenerate networks. When a planned session later becomes ready during reactive playback, offer a seamless handoff: "Your planned session is ready. Switch?" (yes / keep reactive).

---

## 6. Ready + Handoff

The transition from `.ready` to `.playing` is where the Curator commits — and where trust has to be earned. v0.1 assumed the Curator would press play in their music app without wanting to see what was coming. In practice, especially for unfamiliar playlists or mid-session re-plans, Curators want to preview the plan before pressing play.

### 6.1 `ReadyView` layout

Full-bleed but muted. The first-track's preset runs as a background at 0.3× opacity, at silent-mode baseline. Overlaid:

**Headline:** "Ready. Press play in [Apple Music / Spotify / your music app]."

The detected source determines the trailing word. If the user came in via local folder, it's "your music app."

**Subtext:** track listing summary — "Planned [N] tracks, about [M] minutes."

**Secondary affordance:** `Preview the plan` button — opens the plan-preview panel described in §6.2. Non-modal; dismissible.

**Ambient indicator:** a soft pulsing border on the window to draw attention without being obnoxious.

### 6.2 Plan preview

Tappable compact panel showing the orchestrator's planned sequence:

```
━━━━━ PLAN PREVIEW ━━━━━
  1. Blossom                   organic      3:24
       ↓ crossfade 1.2s
  2. Volumetric Lithograph     fluid        4:01
       ↓ cut at structural boundary
  3. Gossamer                  organic      2:48
       ↓ crossfade 0.8s
  ...

          [Regenerate Plan]  [Modify]
```

**Row tap:** loops a 10-second preview of that preset at silent-mode baseline with the track's pre-analyzed stems driving it. Curator can sample what each choice will look like without starting the session.

**Long-press / right-click row:** reveals "Swap preset for this track" — a compatible-preset picker. Any manual pick is sticky for the session.

**Regenerate Plan:** re-runs `DefaultSessionPlanner.plan()` with a different random seed. Preserves any manually-locked picks. Unlocked tracks get re-scored and re-assigned. Cost: <1 second. Useful when the Curator doesn't like the feel of the plan.

**Modify:** opens a fuller editor where the Curator can drag to reorder, swap transitions (cut vs crossfade), or tag tracks with mood/energy overrides that re-feed the orchestrator.

Plan preview and modification are optional — pressing play works fine without ever opening the panel. But they're available when the Curator wants them, which answers the v0.2-revision concern: *does the Curator trust that the output will be solid?* They don't have to trust. They can verify.

### 6.3 First-audio autodetect

`AudioInputRouter` signal transition from `.silent` → `.active` sustained for >250 ms triggers automatic advance to `.playing`. No user click needed.

Fallback: if the user taps anywhere on `ReadyView`, show a one-shot hint: "Open your music app and press play." Don't advance on tap — the audio must actually start flowing.

### 6.4 Ready timeout

If no audio is detected within 90 s of entering `.ready`, overlay:

> "Haven't heard anything yet. Is the music playing?"

Two CTAs: "Retry" (stays in `.ready`, audio detection re-primes), "End session" (advances to `.ended`).

---

## 7. Playback UI

### 7.1 `PlaybackView` layers

Three:

1. **Render surface (full-bleed):** the `MetalView` hosting `VisualizerEngine`.
2. **Auto-hiding overlay chrome (top-left + top-right):** track info, preset name, progress within session, mood readout, settings gear.
3. **Error/status toast (bottom-right):** degradation messages only (audio silence detection, preview fallback, etc.). Only visible to the Curator, by convention — party setups put the output on a second display where viewers sit, leaving the primary display (with toasts) for the Curator.

### 7.2 Overlay chrome behavior

Visible by default for 3 s on session start, then auto-hides. Re-appears on:

- Mouse move (any displacement)
- Any key press
- Track change (shows for 3 s then hides)

Auto-hide uses opacity fade over 500 ms. The render surface is unmodified during fades — overlay chrome is a separate compositing layer.

**Minimum contrast:** overlay text must achieve ≥ 4.5:1 against worst-case preset frame. Because presets are unpredictable, chrome sits on a `RoundedRectangle` blur with 0.4 black opacity backdrop — the blur-and-tint handles the contrast guarantee generically.

### 7.3 Overlay content

**Top-left (track info card):**
- Track title, artist
- Currently playing preset name (subdued)
- Orchestrator state indicator: "Planned" (session mode) / "Reactive" (ad-hoc) / "Adapting" (live adaptation fired)

**Top-right (controls cluster):**
- Session progress dots (one per track, filled = played, highlighted = current)
- Settings gear
- Close/end session

**No playback controls.** Phosphene does not control the source app. Any "pause" button on `PlaybackView` would be a lie.

### 7.4 Live adaptation controls (keyboard-only, invisible to viewers)

During `.playing`, the Curator can steer the experience without the Active Viewer noticing. The keystrokes below are silent by default (no toast visible to viewers) and take effect at the next natural boundary, not mid-preset.

| Key | Action | Latency |
|---|---|---|
| `+` | More like this — boost current preset family weight; extend current preset by 30 s | Applies at next planned transition |
| `-` | Less like this — transition out early; exclude this preset family for 10 minutes | Next structural boundary or 8 s, whichever first |
| `.` | Reshuffle upcoming — re-roll the plan for not-yet-played tracks | Immediate (plan updates, current preset unaffected) |
| `←` / `→` | Preset nudge — transition to a different preset at next structural boundary | Next structural boundary |
| `Shift+←` / `Shift+→` | Force-immediate nudge — cut now, accepting viewer disruption | Immediate |
| `?` | Plan preview overlay — shows current position + upcoming tracks | Immediate |
| `⌘R` | Re-plan session — see §8.3 | <1 s |
| `⌘Z` | Undo last live-adaptation action | Immediate |

Each action is logged to `session.log` and feeds the post-v1 adaptive-learning model.

Settings → Visuals → "Show live-adaptation toasts" toggle surfaces a brief Curator-only acknowledgment ("Nudged toward organic family") bottom-right on keystroke, for Curators who want confirmation. Default off; viewers never see these toasts on a shared-display setup because they're bottom-right of the Curator's window.

### 7.5 Idle-visualizer floor

During `.silent` / `.suspect` / `.recovering` states from `AudioInputRouter`, the preset continues rendering but `FeatureVector` values fall to their warmup-fallback baseline. `SHADER_CRAFT.md §Noise layering` prescribes that every preset must stay visually alive at silence (non-black, non-static).

Additionally: a subtle "Listening…" badge appears top-center during prolonged silence (>3 s). Disappears on signal return.

### 7.6 Track-change indication

Every track boundary triggers:
- Overlay fade-in (3 s auto-hide)
- Track title/artist toast in center, 1 s, then moves to top-left

Short, unobtrusive. The user shouldn't need to remember what's playing — the visual does.

### 7.7 Keyboard shortcuts (global within `.playing`)

Combined reference for shortcuts defined in §7.4 plus general playback controls:

| Key | Action |
|---|---|
| `⌘F` | Toggle fullscreen on current display |
| `⌘Shift+F` | Send to secondary display (see §7.9) |
| `Space` | Toggle overlay visibility |
| `+` / `-` / `.` / `←` / `→` / `⌘R` / `⌘Z` / `?` | Live adaptation — see §7.4 |
| `M` | Mood-lock toggle (freeze mood values, prevent palette drift) |
| `D` | Debug overlay toggle (developer-facing — shows FFT, stems, frame timing, orchestrator state) |
| `Esc` | Exit fullscreen if fullscreen, else end session (with confirm) |

Shortcuts are listed in a help overlay accessible via `Shift+?` (to avoid conflict with the plan-preview shortcut; final key binding TBD in Increment U.6).

### 7.8 Multi-display awareness

`PlaybackView` can be dragged to any display. On display hot-plug:

- Display added: offer a toast: "New display connected. Move Phosphene there?" with "Move" / "Dismiss". Default dismiss.
- Active display removed: window reparents to primary display automatically; session state preserved.
- Drawable size change: triggers `reallocateMVWarpTextures` + `SessionRecorder` writer relock (existing engine behavior, Increment 3.5.4.8).

See §7.9 for the first-class dedicated-output flow.

### 7.9 Dedicated Output Display (Host scenario, first-class)

The listening-party case: Mac mini or laptop connected via HDMI or AirPlay to a TV or projector, with Active Viewers watching. The Curator wants Phosphene's visuals to dominate the TV while keeping controls accessible on a different display (laptop screen, phone via Sidecar, or similar).

Two supported modes, with graceful fallback between them.

**Mode A: Single-window fullscreen on chosen display (v1)**

Simplest setup. The Curator drags the Phosphene window to the target display and hits `⌘F` to fullscreen. All keyboard shortcuts continue to work from anywhere the window has focus.

Enhanced v1 support:

- **Settings → Visuals → Output display** — picker listing all connected displays. Selecting a display immediately moves the Phosphene window to it.
- **`⌘Shift+F` shortcut** — sends Phosphene to the display that's *not* primary; if more than one non-primary display, cycles through them.
- **Display-disconnect resilience** — when the target display disconnects, Phosphene reparents to primary and surfaces a toast: "Output display disconnected. Moved to main display."
- **Overlay chrome auto-hide respected** — in fullscreen on external display, overlay fades normally. Curator's keystrokes from laptop keyboard still work.

**Mode B: Two-window controller + output (v2, post-Milestone-A)**

For parties where the Curator wants a dedicated always-visible control surface. Deferred beyond v1 because Mode A meets the common case.

Structure:

- **Output window** — fullscreen on chosen display, visuals only, no chrome, no track info, no toasts. Optimized for viewer immersion.
- **Controller window** — on Curator's display (laptop or Sidecar'd iPad), resizable, shows compact session state: current track, current preset, session progress, mood readout, debug overlay if enabled. Live-adaptation controls here render as buttons as well as keyboard shortcuts, so a Curator using an iPad via Sidecar has tap targets.

Implementation path: `NSScene` multi-window in SwiftUI with a shared `VisualizerEngine` rendering into both windows' drawables (output at full-bleed resolution, controller at lower resolution in a picture-in-picture pane). Non-trivial; earns its own increment (Increment U.11 or separate).

**AirPlay receiver compatibility**

When the selected output display is an AirPlay Receiver (Apple TV, compatible smart TV), macOS routes the display stream transparently. Phosphene treats it as any other external display. Two caveats the user should know (surfaced in Settings as a notice when AirPlay is the output):

- AirPlay introduces ~60–150 ms of video latency, which is irrelevant for audio-reactive visuals (the audio is captured pre-latency at the Mac, so the visual/audio relationship is preserved at the TV).
- 4K AirPlay can drop to 1080p under network contention. Phosphene's frame budget manager (Increment 6.2) scales quality regardless.

**Audio output is not Phosphene's concern**

Phosphene captures audio via Core Audio tap and never outputs audio. The Host sends audio to speakers / HomePods / AirPlay sinks via their source app (Apple Music, Spotify) using standard macOS audio routing. Phosphene is agnostic about audio output. Documented once in Settings → Audio → (notice): "Phosphene listens to your Mac's audio but does not play audio. Use your music app's speaker settings for speakers, HomePods, or AirPlay."

### 7.10 Reduced motion

When `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is `true`:

- `mv_warp` passes disabled (no feedback accumulation blur)
- SSGI temporal feedback disabled
- Mood-driven palette shifts cross-fade over 4 s instead of 1.5 s
- Beat-pulse maximum amplitude clamped to 0.5× normal

Visual quality is intentionally reduced; the point is physical comfort.

---

## 8. Recovery & Adaptation Flows

v0.1 specified the happy path. This section addresses the three realistic failure modes: mid-session disappointment, pre-play uncertainty, and hard failure requiring restart.

### 8.1 The three intervention layers

The Curator may need to intervene at three levels of cost, each with different latency and disruption:

| Layer | When | Cost | Visible to viewer |
|---|---|---|---|
| **Feedback nudge** (§8.2) | Current preset isn't landing; mood shift needed | <1 s, next transition | No |
| **Plan revision** (§8.3) | Upcoming plan doesn't look right | <1 s, applies at next track | Minimal (next track looks different than "expected") |
| **Hard reset** (§8.4) | Something is fundamentally wrong | 1 s – 2 minutes depending on depth | Yes — visuals pause briefly or switch to reactive mode |

### 8.2 Feedback nudges (in-flight steering)

Already covered in §7.4. Restated here as the recovery entry point: when the Curator feels the current preset isn't working, they press `-`. The current preset transitions out at the next structural boundary (typically within 4–8 seconds), its family is excluded for 10 minutes, and the orchestrator re-ranks the next pick.

If the Curator loves the current preset, they press `+`: the preset is extended, its family weight boosted, and subsequent plan picks tilt toward it.

Feedback is **silent by default**. Active Viewers don't notice. Post-v1, repeated nudge patterns feed adaptive learning.

**When a nudge fails to help.** If the Curator presses `-` twice within 90 seconds, Phosphene surfaces an ambient hint in the bottom-right toast slot (Curator's display only, per §7.9 Mode A and Mode B):

> Not quite hitting the mark? Try ⌘R to re-plan.

This is not a forced prompt — it's a hint. Dismisses after 5 seconds. Once per session.

### 8.3 Plan revision (pre-play and mid-session)

The plan preview from §6.2 is accessible mid-session via `?`. Overlays on top of the current visuals with the current position highlighted. Curator can:

- Tap any upcoming track row to see its preset's 10-second preview (on the controller window, if in Mode B, or overlaid at reduced opacity if Mode A)
- Long-press any upcoming row to swap presets
- Tap "Regenerate Plan" to re-roll upcoming tracks with a different random seed (already-played tracks locked)

**`⌘R` — Re-plan session.** Shortcut for "Regenerate Plan" without opening the overlay. Re-runs `DefaultSessionPlanner.plan()` on unplayed tracks with a different random seed. Preserves already-played history and manually-locked picks. Cost: <1 second.

Current preset continues until its next natural transition, at which point the new plan takes over. No visible seam for viewers.

### 8.4 Hard reset paths

Three escalating resets, accessible from both `.playing` and `.ready` via the Settings gear (Settings → Session → Reset Options).

**"Re-plan session" — `⌘R`**
Covered in §8.3. Preserves track analysis, re-rolls plan. Cost <1 s.

**"Re-analyze playlist" (heavy reset)**
Full restart from `.preparing`. Re-runs stem separation and MIR on all tracks (discards StemCache for this session). Typical trigger: the Curator suspects preparation itself was degraded (bad stem separation, broken MIR, a track that sounded nothing like the plan predicted).

Cost: 20 s – 2 minutes depending on playlist size.

Confirmation dialog — this is expensive:

> Re-analyze takes about 20–30 seconds per 20 tracks. Meanwhile visuals continue in reactive mode. Re-analyze?

On confirm, Phosphene enters reactive mode immediately (using `DefaultReactiveOrchestrator`) and re-preparation runs in the background. When ready, offers seamless handoff: "Your re-planned session is ready. Switch?"

**"End and start over"**
Returns to `.idle`. Typical use: change playlist, change source, or abandon the current session entirely. No confirmation — the next step is picking a source anyway.

### 8.5 Pre-play recovery

Before pressing play in the music app, the Curator may want to change their mind about the plan. `ReadyView` (§6.1) supports this without needing to "reset":

- **Preview the plan** (§6.2) — see what's coming, lock specific presets, regenerate unlocked ones
- **"Not this playlist after all"** — back button returns to `ConnectorPickerView` without discarding the prepared cache. If the user comes back with a different playlist, any overlapping tracks reuse their cached analysis.
- **"Let me just preview"** — tap any track in the plan preview to auto-play a 10-second preset demo

v0.1's `ReadyView` only had pressure forward (press play, we're ready). v0.2 supports both directions.

### 8.6 Post-session reflection

After `.ended`, `EndedView` shows a compact session summary: which presets played for which tracks, which were nudged, how many times the plan was regenerated. No data leaves the device (per D-003), but the session recorder has already logged everything to `~/Documents/phosphene_sessions/`. A small "What happened this session?" link opens that folder with the specific session selected.

This matters for Curators who want to tune their preferences over time — or for developers troubleshooting a session that didn't land.

### 8.7 What this gates

New user-facing capabilities on existing engine components. All have corresponding entries in §14 Increment Scope Recap under Increment U.10.

- `SessionManager.replanSession()` — preserves prepared tracks, re-runs planner with different seed. Depends on existing Increment 4.3 planner.
- `SessionManager.reanalyzeAndReplan()` — full restart from `.preparing`. Depends on Increment 2.5.3 cache invalidation.
- `LiveAdapter.applyFeedback(_:)` — accepts `FeedbackNudge` enum (`.moreLikeThis`, `.lessLikeThis`, `.reshuffleUpcoming`). Extends Increment 4.5.
- `PlanPreviewView` — new view renders the orchestrator's `PlannedSession` as a tappable timeline.
- `PlanPreviewViewModel` — coordinates preset-preview playback and swap/regenerate actions.

---

## 9. Error Taxonomy + Copy Guide

This is the canonical mapping from internal error states to user-facing language. Any new internal error must add a row here before shipping.

### 9.1 Permission errors

| Cause | User copy | Primary CTA | Secondary |
|---|---|---|---|
| `CGPreflightScreenCaptureAccess() == false` | "Phosphene needs permission to hear music playing on your Mac." | "Open System Settings" | "Why?" (reveals explainer) |
| AppleScript permission denied | "Phosphene needs permission to talk to Apple Music. You can grant this in System Settings → Privacy & Security → Automation." | "Open System Settings" | "Skip to Spotify" |
| Sandbox preventing capture | (should not occur — app sandbox is disabled per RUNBOOK) | Dev-facing log only | — |

### 9.2 Connection errors (state: `.connecting`)

| Cause | User copy | Primary CTA | Secondary |
|---|---|---|---|
| Apple Music not running | "Apple Music isn't running. Open it and start a playlist." | "Open Apple Music" | "Use Spotify instead" |
| No currently-playing playlist | "Start playing a playlist in Apple Music, then come back." | (auto-retries) | "Cancel" |
| Spotify URL malformed | "That doesn't look like a Spotify playlist link." | "Paste again" | — |
| Spotify URL is track/album | "That's a track, not a playlist. Phosphene needs a playlist URL." | "Paste again" | — |
| Spotify API rate-limited | "Spotify is being slow — still trying." (auto-retries with backoff) | — | "Cancel" |
| Spotify API unreachable | "Couldn't reach Spotify. Check your network or try a different source." | "Try again" | "Use Apple Music" |
| Empty playlist | "That playlist doesn't have any tracks yet." | "Pick a different playlist" | — |

### 9.3 Preparation errors (state: `.preparing`)

| Cause | User copy | Placement | Recovery |
|---|---|---|---|
| iTunes preview not found (1 track) | "Skipped — preview unavailable" on row; track status `.partial` | Inline on track row | Orchestrator plans around with metadata only |
| iTunes preview API rate-limit | "Preparing more slowly than usual" top-of-list banner | Top banner | Auto-continues with backoff |
| Network offline | "You're offline. Phosphene can't fetch previews." | Full-screen replacement | "Retry when online", "Start reactive mode" |
| Stem separation failure (1 track) | "Skipped — couldn't analyze" on row | Inline on track row | Track status `.failed`; orchestrator excludes |
| All tracks failed to prepare | "Couldn't prepare any of this playlist. Try a different one." | Full-screen replacement | "Pick another playlist" + "Start reactive mode" |
| First-track preparation >90 s | Expand copy per §5.6 — offer reactive-mode handoff | Top banner | User-chosen |
| Total elapsed preparation >2 minutes without progressive-ready | Escape CTA per §5.6 | Top banner | "Try again" / "Start reactive mode" |

### 9.4 Playback errors (state: `.playing`)

Placement convention: subtle status toast, bottom-right of `PlaybackView` — **Curator's display only** in Mode A or Mode B (§7.9). Auto-dismisses when resolved. Never full-screen during playback — the visuals are the point and the Active Viewer is watching.

| Cause | User copy | Auto-dismiss on |
|---|---|---|
| Silence >3 s | "Listening…" (small badge, center-top) | Signal returns |
| Silence >15 s | "Haven't heard anything for a while. Is the music playing?" | Signal returns |
| Tap reinstall attempt | (no user copy — logged only) | — |
| Three tap reinstalls failed | "Couldn't re-hear the audio. Try quitting and re-opening Phosphene." | User action |
| MPSGraph allocation failure mid-session | "Analyzer hiccup — using backup mode." (reactive without live stems) | Next track |
| Sample rate mismatch (96 kHz) | "Audio is at 96 kHz. For best results set Audio MIDI Setup to 48 kHz." | Session restart |
| Wrong normalization (Spotify Normalize Volume on) | "Audio levels are low. Check Spotify's 'Normalize Volume' setting — it should be off." | User action |
| Frame budget exceeded, governor activated | (no user copy by default — only shown if "Show performance warnings" setting is on) | — |
| Display disconnected mid-session | "Output display disconnected. Moved to main display." (§7.9) | 5 s |
| Drawable-size mismatch (recorder) | (no user copy — logged to `session.log`) | — |
| Curator pressed `-` twice in 90 s | "Not quite hitting the mark? Try ⌘R to re-plan." (ambient hint per §8.2) | 5 s, once per session |
| `⌘R` re-plan succeeded | "Re-planned. Next transition will use the new plan." (only if "Show live-adaptation toasts" is on per §7.4) | 3 s |

### 9.5 Copy principles

1. **Describe the situation, not the exception.** Not "NSURLError -1009" but "You're offline."
2. **Tell the user what they can do.** Every error message has either a CTA or a clear "auto-retrying" status.
3. **Don't blame the user.** "That doesn't look like a Spotify playlist link" is better than "Invalid URL."
4. **No jargon.** No "MPSGraph," "FFT," "tap," "IRQ," "sandbox," "DRM" in user-facing strings. Internal logs are different — they use jargon freely.
5. **Never apologize.** "Sorry, something went wrong" is noise. Either describe what happened or offer a fix.
6. **Stability over candor for low-impact hiccups.** Governor activation, minor ML stutters, brief silence — don't notify the user. Log for developers.
7. **Active Viewer never sees error copy.** During `.playing`, all user-facing messaging lives on the Curator's display.

### 9.6 String externalization

All user-facing strings live in `Localizable.strings` (even though v1 is English-only). This is purely so future localization is additive, not a rewrite. Every string gets a meaningful key (`"error.preparation.all_tracks_failed"` not `"string_42"`).

---

## 10. Settings Surface

`SettingsView` is a sheet presented from any top-level view. Organized into four groups.

### 10.1 Audio

- **Capture mode** — System audio (default) / Specific app (picker lists running apps that produce audio) / Local file (for testing)
- **Source app overrides** — (visible when Capture mode = Specific app) dropdown
- **Quality hints** — read-only notice block linking to the relevant `RUNBOOK` checklist items: "For best results: Apple Music Sound Check off / Spotify Normalize Volume off / Audio MIDI Setup at 48 kHz"
- **Audio output notice** — "Phosphene listens to your Mac's audio but does not play audio. Use your music app's speaker settings for speakers, HomePods, or AirPlay." (per §7.9)

### 10.2 Visuals

- **Device tier** — Auto (default) / Force M1/M2 (Tier 1) / Force M3+ (Tier 2). Override for testing or deliberate quality trade-off.
- **Quality ceiling** — Auto / Performance (disables SSGI, reduces mesh density) / Balanced (default) / Ultra (ignores frame-budget governor; for recording/capture)
- **Output display** — picker listing all connected displays. Selecting moves Phosphene there. (§7.9 Mode A)
- **Include Milkdrop-style presets** — On (default, once Phase MD ships) / Off. Switches the orchestrator catalog.
- **Reduced motion** — Matches system (default) / Always on / Always off
- **Preset family blocklist** — multi-select; excludes families the user doesn't enjoy
- **Show live-adaptation toasts** — Off (default) / On. Brief Curator-only acknowledgments on `+` / `-` / `⌘R` (per §7.4)
- **Adaptive learning from feedback** — Off (default, post-v1) / On. Uses nudge history to tune weights.

### 10.3 Diagnostics

- **Session recorder** — On (default) / Off. When off, no `~/Documents/phosphene_sessions/` files written.
- **Session retention** — Keep last N sessions (default 10) / Keep all / Keep 1 day / Keep 1 week
- **Show performance warnings** — Off (default) / On. Surfaces governor activations and frame-budget overruns as toasts.
- **Open sessions folder** — button, opens `~/Documents/phosphene_sessions/` in Finder
- **Reset onboarding** — button, clears onboarding flags. For testing or when re-introducing the app to a new user.

### 10.4 About

- Version, macOS version, GPU family (M-series tier detected)
- License (MIT) link
- Documentation link (GitHub README)
- Debug info copy-to-clipboard button (for issue reports; contains system info only, no audio data)

### 10.5 Persistence

All settings persist in `UserDefaults` keyed `"phosphene.settings.<group>.<key>"`. Changes take effect immediately — no "Apply" button. Changing quality ceiling mid-session does not interrupt playback; it applies to the next preset transition.

---

## 11. Debug Overlay

The debug overlay (toggled with `D`) is developer-facing and always available. Distinct from the user overlay chrome described in §7.2. Hidden by default for users.

Contents per `RUNBOOK §Debug Overlay Fields` — retained as-is:

- Active capture provider
- Permission state
- Signal present / absent (`AudioSignalState`)
- Sample rate
- Current track
- Preparation state
- Current preset
- Frame time / dropped-frame warning
- `InputLevelMonitor` signal quality (green/yellow/red)
- Orchestrator state (Planned / Reactive / Adapting)

Position: bottom-left of `PlaybackView` (Curator's display only in Mode B). Opacity 0.7. Monospace font. Never auto-hides.

---

## 12. Accessibility

### 12.1 Contrast

Overlay text: ≥ 4.5:1 against worst-case frame. Implemented via blurred dark backdrop (§7.2). Measured against the three regression fixtures from `Increment 5.2` (silence / steady mid-energy / beat-heavy) for every preset; failures gate preset certification.

### 12.2 Motion

Per `§7.10`. System `reduceMotion` flag respected. Forced setting in `§10.2`.

### 12.3 Photosensitivity

Per `§3.3`. One-time notice. Reduced-motion mode caps beat-pulse amplitude.

In addition: the orchestrator's family-repeat penalty (Increment 4.1) and fatigue cooldowns (Increment 4.0) inherently limit how often a preset with high motion intensity can recur. A future stricter mode could cap `motion_intensity > 0.8` presets entirely — tracked as a potential Increment U.9 follow-up.

### 12.4 VoiceOver

`ContentView` and its children label their interactive elements. `PlaybackView`'s render surface is marked as decorative — VoiceOver users hear the music directly and don't benefit from "visualization of music playing." Overlay chrome (track info, status toasts) is readable.

### 12.5 Dynamic Type

All text in `SettingsView`, `PreparationProgressView`, `IdleView`, `PermissionOnboardingView`, `ConnectorPickerView`, `ReadyView`, `PlanPreviewView`, and overlay chrome respects Dynamic Type sizing. `PlaybackView` render surface is fixed (it's Metal).

### 12.6 Color-blindness

The debug overlay uses distinctly-shaped icons alongside colors for status (✓ / ⚠ / ⟳ / ●). Preparation track status (`§5.3`) is icon-first, color-second for the same reason. Quality grade traffic light (green/yellow/red from `InputLevelMonitor`) includes a letter code (G/Y/R) in the debug overlay.

---

## 13. Proposed View Hierarchy

Initial recommendation; adjust in implementation (Increment U.1). `PhospheneApp/` grows these files:

```
PhospheneApp/
  Views/
    ContentView.swift              → switch on SessionManager.state
    Idle/
      IdleView.swift
    Onboarding/
      PermissionOnboardingView.swift
      PhotosensitivityNoticeView.swift
    Connection/
      ConnectorPickerView.swift
      AppleMusicConnectionView.swift
      SpotifyConnectionView.swift
    Preparation/
      PreparationProgressView.swift
      TrackPreparationRow.swift
      PreparationProgressHeader.swift
      PreparationActionBar.swift
    Ready/
      ReadyView.swift
      PlanPreviewView.swift           → §6.2
      PlanPreviewRow.swift
    Playback/
      PlaybackView.swift
      OverlayChromeView.swift
      TrackInfoCard.swift
      SessionProgressDots.swift
      ErrorToastView.swift
      ListeningBadge.swift
      LiveAdaptationToast.swift       → §7.4 (optional toast)
      PlanOverlayView.swift           → §8.3 mid-session plan overlay
    Ended/
      EndedView.swift
      SessionSummaryCard.swift        → §8.6
    Settings/
      SettingsView.swift
      AudioSettingsSection.swift
      VisualsSettingsSection.swift
      DiagnosticsSettingsSection.swift
      AboutSettingsSection.swift
      OutputDisplayPicker.swift       → §7.9 / §10.2
    Output/
      ControllerWindow.swift          → §7.9 Mode B (v2, deferred)
      OutputWindow.swift              → §7.9 Mode B (v2, deferred)
    Shared/
      ErrorToast.swift
      LoadingSpinner.swift
      SecondaryLinkButton.swift
  ViewModels/
    SessionStateViewModel.swift    → observes SessionManager
    PreparationViewModel.swift     → observes SessionPreparer via PreparationProgressPublishing
    PlaybackOverlayViewModel.swift → tracks overlay visibility + fade timers
    PlanPreviewViewModel.swift     → §6.2 / §8.3 plan preview and swap/regenerate
    LiveAdaptationViewModel.swift  → §7.4 feedback nudge dispatch
    SettingsViewModel.swift        → persists via UserDefaults
  Copy/
    Localizable.strings            → all user-facing strings
    UserFacingError.swift          → typed error → copy mapping
```

No view file exceeds 200 lines. ViewModels are `@MainActor` subclasses of `ObservableObject`. Strings are externalized. Errors are typed.

---

## 14. Increment Scope Recap

| Increment | Scope | Done-when snippet |
|---|---|---|
| U.1 | Session-state views | 6 state views with snapshot tests |
| U.2 | Permission onboarding | Permission flow working + 4 tests |
| U.3 | Playlist connector picker | Three connector flows end-to-end |
| U.4 | Preparation progress UI | Per-track status + `PreparationProgressPublishing` protocol |
| U.5 | Ready + plan preview | `PlanPreviewView`, first-audio autodetect, preset-preview loop |
| U.6 | In-session chrome | Auto-hide chrome + keyboard shortcuts (including live-adaptation) |
| U.7 | Error taxonomy + toast system | Every row in §9 table has `UserFacingError` case |
| U.8 | Settings panel | All four settings groups persisted, including Output Display picker |
| U.9 | Accessibility pass | Reduced motion + contrast + photosensitivity gates |
| **U.10** | **Recovery & Adaptation Flows** | **`LiveAdapter.applyFeedback`, `SessionManager.replanSession`, `reanalyzeAndReplan`, `PlanOverlayView`, mid-session plan swap, ambient hint after double-`-`** |
| U.11 | *(deferred v2)* Two-window controller + output | `ControllerWindow` + `OutputWindow` coordinated via shared `VisualizerEngine` |

Milestone A blocks on U.1–U.7. U.8–U.10 are needed for Milestone A to feel *complete* rather than minimal. U.11 is post-v1.

---

## 15. Test Surface

Every new view gets a snapshot test using swift-testing `@Test` + `@MainActor`, comparing against a locked-in PNG in `Tests/Snapshots/`. Three snapshot fixtures per stateful view (empty state / mid-state / error state). Snapshots regenerate via `UPDATE_SNAPSHOTS=1 swift test --filter ViewSnapshotTests`.

`UserFacingError` → copy mapping is tested exhaustively: every enum case has a test asserting the exact string returned.

`PreparationProgressPublishing` has a test double in `Tests/TestDoubles/MockPreparationProgressPublisher.swift`.

`LiveAdapter.applyFeedback` has a test double and unit tests covering every `FeedbackNudge` case; orchestrator integration tests verify weight adjustments and family exclusion persist across the nudge window.

`SessionManager.replanSession` has integration tests verifying that already-played tracks and manually-locked picks are preserved across re-rolls.

`OutputDisplayPicker` has snapshot tests against synthetic multi-display fixtures.

---

## 16. Decisions Locked Here

These are UX-level decisions that are non-obvious; append them to `DECISIONS.md` as they are implemented.

- **UX-1: Permission onboarding is not a wizard.** One screen, two sentences, open Settings. Multi-step flows are cognitive friction.
- **UX-2: Phosphene does not control playback.** No pause/play/skip controls on `PlaybackView`. Any such control would lie.
- **UX-3: "Start now" with partial readiness is a prominent CTA.** Preparation is not a hard gate. Users who want to start early can.
- **UX-4: Never show a full-screen error during `.playing`.** Playback errors use bottom-right toasts only, on the Curator's display in multi-display setups. The visuals are the point and viewers are watching them.
- **UX-5: First-audio autodetect advances `.ready → .playing`.** No user click required. Tapping only shows a hint.
- **UX-6: Every user-facing string is externalized even in English-only v1.** Future localization is additive.
- **UX-7: Debug overlay is separate from user overlay chrome.** Never shown to users by default.
- **UX-8: Preparation time tolerance is 2 minutes, not 30 seconds.** Curators will wait if Phosphene earns the time. Progressive-ready CTA surfaces at 3 tracks; 90 s and 2 min escapes surface reactive-mode alternatives.
- **UX-9: Pre-play plan preview is a first-class affordance.** Curators do not have to blind-trust the orchestrator. They can verify.
- **UX-10: Live adaptation is silent by default.** Feedback nudges (`+` / `-` / `.`) don't surface viewer-visible acknowledgments. The Active Viewer experiences continuity; the Curator controls from behind the curtain.
- **UX-11: Dedicated output display is a first-class flow, not a workaround.** Settings → Output display, `⌘Shift+F` shortcut, display-disconnect resilience. Two-window controller + output is deferred to v2 but informs the v1 design.
- **UX-12: Phosphene never routes audio.** Output device selection is the source app's responsibility. Phosphene documents this once in Settings rather than surfacing audio-routing controls it would not actually control.

---

## 17. Cross-References

- `PRODUCT_SPEC.md` — personas, use cases, non-goals (this doc extends it)
- `ARCHITECTURE.md §UI Layer` — engineering view of the SwiftUI module (to be added Increment U.1)
- `CLAUDE.md §UX Contract` — implementation handshake for Claude Code sessions (to be added Increment U.1)
- `RUNBOOK.md §Common Failure Modes` — developer-facing diagnosis; this doc provides the user-facing language
- `ENGINEERING_PLAN.md §Phase U` — the implementation increments
- `SHADER_CRAFT.md §7.5 Idle-visualizer floor` — the silent-state visual baseline that §7.5 references

---

## Open Questions

Items that need a decision before Increment U.1 ships:

1. **Local folder connector in v1?** Proposed off in v1 to reduce scope. Decision: Matt.
2. **Session progress dots or horizontal scrubber in `PlaybackView`?** Proposed dots. Scrubber invites "skip to track" misconception given Phosphene doesn't control playback.
3. **"End session" in overlay or require Esc-twice?** Proposed visible button + Esc-twice confirm. Party-host scenario has risk of accidental end.
4. **Photosensitivity notice: mandatory first-run or skippable?** Proposed mandatory (dismissible but shown). Legal/ethical floor.
5. **Do we ship `SettingsView` in v1 at all?** Proposed yes — at minimum the diagnostics section + Output Display picker. Full settings can incrementalize.
6. **Two-window controller + output (Mode B) in v1?** Proposed deferred to v2 (Increment U.11). Single-window drag-to-display (Mode A) covers the common Host case. Deferral risk: Curators with one-Mac-one-TV setups will want it sooner than v2.
7. **Plan preview preset-demo playback: in `ReadyView` background or a separate demo window?** Proposed background (the preset takes over the 0.3×-opacity `ReadyView` backdrop for 10 seconds on row-tap). Alternative is a small PiP demo pane. Background is simpler; PiP is more discoverable.
8. **Adaptive learning from feedback: opt-in or opt-out in v1 when it ships post-v1?** Proposed opt-in (off by default). Privacy stance preserves D-003 ("local-only processing") but users must know it exists to benefit.

---

## 18. Design Context

*Source of truth for visual and interaction design decisions. Maintained in `.impeccable.md`; mirrored here for engineering sessions that reference UX_SPEC directly.*

### 18.1 Users

**The Curator** (primary): A music-attentive person who treats playlists as curated experiences, not shuffle queues. They host listening parties or listen alone with intention. They are the operator — setting up the session, trusting the system, occasionally steering it with invisible keystrokes. They will wait two minutes if the result is extraordinary. They will not forgive two minutes of waiting followed by mediocrity.

**The Active Viewer** (secondary — at listening parties): A passive experiencer. They see only the visuals and feel only the music. They do not interact with the app. Their only feedback channel is their reaction. They expect to be held, not managed.

**Use context:** Often dim rooms (living rooms, studios, bedroom listening sessions, parties). Multiple-display setups common — TV or projector for visuals, Mac for control. Night-time, focus-mode, ambient.

### 18.2 Brand Personality

**Three words: Meditative. Inspirational. Cutting-Edge.**

As a physical object: a Braun audio component redesigned today — precise, purposeful, no wasted surface — but warm from the music living inside it. Ryuichi Sakamoto liner notes: sparse text, generous breath, every word carrying weight.

**Not:**
- Winamp/screensaver nostalgia — no skeuomorphic knobs, no visualizer-bar clichés
- "AI product" glow aesthetics — no cyan-on-dark, no purple-to-blue gradients, no neon scan lines
- Streaming app chrome — no playlist carousels, no recommendation UI conventions
- Club/EDM dark mode — Phosphene serves all music, including quiet jazz, ambient, and classical

### 18.3 Aesthetic Direction

**Theme:** Dark. Phosphene runs in dim rooms. The visual output is the point; UI chrome should dissolve into the background. Every non-playback state is a waiting room for the visuals — beautiful, but aware of its supporting role.

**Color palette (OKLCH):**

| Token | Value | Role |
|---|---|---|
| `--bg` | `oklch(0.09 0.012 275)` | Base — deep desaturated blue-purple, not pure black |
| `--surface` | `oklch(0.13 0.015 278)` | Cards, panels |
| `--surface-raised` | `oklch(0.17 0.018 278)` | Elevated surfaces, popovers |
| `--border` | `oklch(0.22 0.014 278)` | Dividers, outlines |
| `--text-muted` | `oklch(0.50 0.014 278)` | Secondary text, labels |
| `--text-body` | `oklch(0.80 0.010 278)` | Body text — off-white tinted toward brand hue |
| `--text-heading` | `oklch(0.94 0.008 278)` | Headings |
| `--purple` | `oklch(0.62 0.20 292)` | Ambient presence, session depth, ready state |
| `--purple-glow` | `oklch(0.35 0.12 292)` | Subtle background tint for active states |
| `--coral` | `oklch(0.70 0.17 28)` | Energy, action, primary CTAs |
| `--coral-muted` | `oklch(0.45 0.10 28)` | Coral at rest — hover, inactive CTA |
| `--teal` | `oklch(0.70 0.13 192)` | Analytical/precision — preparation, MIR data, stem indicators |
| `--teal-muted` | `oklch(0.40 0.08 192)` | Teal at rest |

**Semantic color rules (non-negotiable):**
- **Purple** = ambient presence, session depth. Use for idle visualizer tint, ready-state pulsing border, mood indicators.
- **Coral** = energy and action. Use for primary CTAs, first-audio flash, nudge confirmation. Should feel like warmth arriving.
- **Teal** = precision and data. Use for preparation progress, MIR readouts, stem indicators. Never decorative.

**Typography:**

| Role | Font | Source | Weight |
|---|---|---|---|
| Display / headings | Clash Display | Fontshare (free) | 500–600 |
| Body / UI | Epilogue | Google Fonts (free) | 400–500 |
| Monospace (debug, plan preview) | Berkeley Mono or SF Mono | Licensed / System | — |

**Type scale (fixed for app UI — no fluid clamp in product interfaces):**

| Step | Size | Usage |
|---|---|---|
| `xs` | 11px | Captions, status labels, debug overlay |
| `sm` | 13px | Track rows, secondary UI text |
| `md` | 15px | Body, primary UI text |
| `lg` | 18px | Section headings, card titles |
| `xl` | 24px | State subheadlines |
| `2xl` | 36px | State headlines ("Ready.") |
| `3xl` | 52px | Rare — full-bleed idle headline only |

### 18.4 Design Principles

1. **Each state has one job.** IdleView is an invitation. PreparationProgressView is anticipation architecture. ReadyView is a held breath. PlaybackView is the UI disappearing. No shared chrome bleeding across states.

2. **The wait is ceremonial, not transactional.** Preparation is not a loading screen — it's the room going quiet before a performance. Per-track status should feel like watching a crew set the stage.

3. **Whitespace as signal; density as exception.** Default state is spacious. When density appears (track list, plan preview, debug overlay), it signals important data. The contrast between sparse and dense is itself information.

4. **Color carries meaning — never decorate with it.** Purple for ambient presence. Coral for energy and action. Teal for precision and data. A surface is never purple "to look good" — it's purple because something is in session.

5. **PlaybackView is the product. Everything else is infrastructure.** The visualizer IS Phosphene. All other views exist to reach that moment and should disappear the instant they are no longer needed.

### 18.5 State-Specific Design Notes

**IdleView:** Phosphene name centered, two choices only (coral primary CTA + ghost secondary). Visualizer runs at 0.1× opacity as a background whisper of what's coming.

**PermissionOnboardingView:** One screen, no wizard. Generous vertical breathing room. Headline is a statement of need, not an apology. Three sentences maximum. Nothing competes with the primary CTA.

**ConnectorPickerView:** Three source tiles in a contained panel. Understated — no giant icons, no marketing copy. Disabled tiles recede visually; they are not hidden.

**PreparationProgressView:** Three-region layout — playlist header (compact), track list (scrollable), action bar (anchored bottom). Track rows "light up" in teal as tracks become ready. "Start now" appears in coral at the progressive-readiness threshold — it should feel like permission being granted.

**ReadyView:** Full-bleed, first-track preset at very low opacity. Headline: "Ready." — one word, maximum size, Clash Display. Soft purple pulse on the window border (breathing animation, not glow). "Press play in [source app]" is the only instruction.

**PlaybackView:** The UI is not there. Overlay chrome is ghost — appears on motion, fades after 3s. Track info uses no borders — blur-and-tint backdrop only. Error toasts are small, bottom-right, never alarming.

**EndedView:** Reflection, not administration. Session duration and track count. "New session" in coral. Should feel like house lights coming up gently.

### 18.6 macOS-Specific Constraints

- Window chrome: unified toolbar, minimal — prefer `.hiddenTitleBar` + custom title area
- Materials: `NSVisualEffectView` (`.hudWindow` or `.underWindowBackground`) for overlapping panels — not opaque surfaces
- Animations: `spring(response: 0.4, dampingFraction: 0.85)` for state transitions. No bounce easing. Overlay chrome fades at `easeInOut(duration: 0.5)`
- Focus rings: `--purple` at 2px with 3px blur — never default system blue

### 18.7 Anti-Patterns

- No side-stripe `border-left`/`border-right` accents on status rows or cards
- No gradient text
- No rounded-rectangle cards with generic drop shadows as the primary UI pattern — use whitespace and typographic hierarchy instead
- No glassmorphism except where purposeful (overlay chrome blur is purposeful; decorative blur is not)
- No "Loading…" states where per-item progress is possible
- No iconography on every heading — the 6-state views should feel typographic, not icon-led
- No modal dialogs except destructive confirmation (re-analyze playlist)
