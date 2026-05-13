# Historical Dead Ends

This file catalogues dead APIs, deprecated frameworks, and one-time architectural dead-ends that no longer apply to active development. Entries live here when they describe **something that no longer exists** (an API that shut down, a framework that broke and is no longer relevant) rather than **a rule that prevents a recurring bug**.

The active-rule equivalents — Failed Approaches that catch real recurring patterns — live in `CLAUDE.md §Failed Approaches — Do Not Repeat`.

## Why this file exists

Two patterns were mixed in CLAUDE.md's Failed Approaches list:

1. **Dead APIs and frameworks:** "AcousticBrainz shut down 2022" / "Spotify Audio Features deprecated 2024" / "MediaRemote private framework banned post-macOS 15." These describe historical events. Useful as "don't go looking for this" pointers but not active behavioral rules.
2. **Active rules:** "Drive presets from audio deviation, not absolute energy" / "Never use synthetic audio in diagnostics" / "No CoreML ANE Float16 with Float32 bindMemory." These describe rules that prevent recurring bugs today.

Mixing the two reduced the signal of every entry. The active rules stay in CLAUDE.md; the historical entries move here.

## Convention

Entries below preserve their original Failed Approach number from CLAUDE.md for cross-reference with git history. Each carries a one-line provenance footer recording when and why it moved here.

For entries describing **tech that may have evolved since the original observation** (BlackHole, ScreenCaptureKit audio, CoreML audio separation), the footer also records "last verified pre-macOS 26 / pre-CoreML 7.x." If a future session has reason to revisit, re-test against current platform versions before reinstating as an active Failed Approach.

---

## Audio capture dead ends

### #5 — BlackHole virtual audio driver

**Original entry:** BlackHole was broken on macOS Sequoia (macOS 15). Phosphene's needs were met without it via Core Audio taps (D-002).

> Moved to graveyard 2026-05-13 (DOC.3a). Last verified pre-macOS 26 / pre-BlackHole 0.6.x. Not actively blocking — D-002 Core Audio taps is the chosen architecture. Re-test against current platform if a future need to revisit virtual audio devices arises (e.g. browser-based Phosphene preview).

### #6 — Web Audio API AnalyserNode

**Original entry:** Web Audio API AnalyserNode broken for virtual audio devices on macOS.

> Moved to graveyard 2026-05-13 (DOC.3a). Phosphene is a native macOS app (D-001); Web Audio API is irrelevant to the current architecture. If a future browser-based companion target is scoped, re-test against then-current macOS + browser combinations.

### #7 — ScreenCaptureKit for audio-only capture

**Original entry:** Zero audio callbacks on macOS 15+/26 when using ScreenCaptureKit for audio-only capture (video discarded).

> Moved to graveyard 2026-05-13 (DOC.3a). Last verified pre-macOS 26.0; Apple has shipped substantial ScreenCaptureKit updates since the original observation. Not actively blocking — D-002 Core Audio taps via `AudioHardwareCreateProcessTap` is the chosen architecture. Re-test if a future need to capture audio + video together arises.

### #9 — MPNowPlayingInfoCenter for reading other apps' metadata

**Original entry:** `MPNowPlayingInfoCenter` only returns the host app's own Now Playing info on macOS — useless for reading Apple Music / Spotify metadata.

> Moved to graveyard 2026-05-13 (DOC.3a). Platform limitation by design; AppleScript polling is the working path (`Audio/StreamingMetadata`). No re-test expected — the API contract is intentional, not a bug.

### #11 placeholder

**Note:** #11 (MediaRemote private framework — "Operation not permitted from signed app bundles") stays in CLAUDE.md as an active Failed Approach because Apple's enforcement of private-framework restrictions is ongoing, and the rule still prevents a recurring bug ("don't reach for MediaRemote when AppleScript polling looks slow"). Cross-referenced here for completeness only.

---

## Metadata / streaming API dead ends

### #8 — AcousticBrainz

**Original entry:** Public API shut down 2022.

> Moved to graveyard 2026-05-13 (DOC.3a). Factual API death; no re-test possible (the service no longer exists). MusicBrainz (D-012) is the active free-tier metadata backbone.

### #10 — Spotify Audio Features endpoint

**Original entry:** `GET /v1/audio-features/{id}` deprecated November 2024; returns HTTP 403.

> Moved to graveyard 2026-05-13 (DOC.3a). Factual API deprecation; Spotify enforces 403. Phosphene's audio analysis is now self-computed via MIRPipeline + Beat This! (D-013, D-077). No re-test expected — Spotify will not restore the endpoint.

---

## ML / signal-processing dead ends

### #12 — HTDemucs CoreML conversion

**Original entry:** Complex tensor ops in HTDemucs block CoreML conversion.

> Moved to graveyard 2026-05-13 (DOC.3a). Last verified pre-CoreML 7.x. CoreML has matured significantly since the original observation (Apple shipped expanded complex-tensor support in iOS 17 / macOS 14, and MLX in 2024+). Not actively blocking — Phosphene uses Open-Unmix HQ via MPSGraph (D-009, D-010). Re-test if a future session has reason to revisit HTDemucs or other Demucs-family models for stem separation.

### #13 — End-to-end CoreML audio separation models

**Original entry:** No complex number support in CoreML blocks end-to-end audio separation models from converting.

> Moved to graveyard 2026-05-13 (DOC.3a). Last verified pre-CoreML 7.x. Same caveat as #12 — CoreML has evolved. Not actively blocking — MPSGraph path (D-009) is the chosen architecture for all ML audio processing. Re-test against current CoreML if a future need arises.

### #19 — Unweighted chroma accumulation

**Original entry:** Bin-count bias across pitch classes when accumulating chroma without bin-count normalisation.

> Moved to graveyard 2026-05-13 (DOC.3a). Calibration-specific learning; the correct approach (bin-count normalisation, weight = 1 / binsInPitchClass) is documented in CLAUDE.md §Audio Analysis Tuning §Chroma. No active rule needed — `ChromaExtractor.swift` implements the correct form by construction.
