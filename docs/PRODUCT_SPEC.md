# Phosphene — Product Specification

## What Phosphene Is

Phosphene is a native macOS music visualization app for Apple Silicon. It connects to playlists from streaming services, prepares a visual session in advance, and renders high-quality visuals that respond to the music in real time.

Phosphene does not control playback. The user plays music in their streaming app of choice while Phosphene listens, analyzes, and performs the visual accompaniment.

The name references the visual phenomenon of perceiving light and patterns without external visual stimulus — exactly what this software does with sound.

## Product Promise

Phosphene should feel less like a reactive screensaver and more like an intelligent VJ:

- It prepares for a known playlist when possible.
- It adapts during playback.
- It selects and sequences visuals with taste.
- It remains fluid at 60 fps on supported hardware.

## Primary Use Cases

**Curated playlist session.** The user connects a playlist, waits briefly for preparation, then starts playback. From the first beat, stems are cached, the visualizer is chosen, and transitions are pre-planned across the entire session. This is how Phosphene is designed to be used.

**Listening party backdrop.** Friends gather, each brings a mix. One person connects the playlist, Phosphene prepares the show, and the group watches synchronized visuals on a TV or projector while listening together.

**Ambient accompaniment.** Solo listening — reading, working, unwinding — with visuals on a secondary display or in a window.

**Reactive fallback.** If no playlist is connected, Phosphene still works as a live reactive visualizer using real-time audio analysis only, without pre-planned sequencing.

## Target Platform

- macOS only
- Apple Silicon only
- Baseline support: M1 and newer (Tier 1)
- Enhanced feature tier: M3 and newer (Tier 2)

## Non-Goals

- No Windows or iOS version
- No cloud processing
- No telemetry that sends listening data off-device
- No DAW-style audio routing setup as a normal requirement
- No promise of source-perfect metadata from streaming apps

## UX Principles

- The app should not make the user think like an audio engineer.
- Setup should be simple and permissions should be clearly explained.
- The system should degrade gracefully when metadata, previews, or capture are unavailable.
- Visual quality matters as much as technical responsiveness.
- Continuous musical energy should drive motion; beats add accents, not the other way around.

## Success Criteria

Phosphene succeeds when:

- Users can get from launch to signal detection without confusion.
- Visuals feel synchronized and musically appropriate.
- Transitions feel intentional.
- The app remains stable over long listening sessions.
- The visual session feels curated rather than random.

## License

MIT.
