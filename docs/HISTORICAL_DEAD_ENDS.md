# Historical Dead Ends

This file catalogues dead APIs, deprecated frameworks, and one-time architectural dead-ends that no longer apply to active development. Entries live here when they describe **something that no longer exists** (an API that shut down, a framework that broke and is no longer relevant) rather than **a rule that prevents a recurring bug**.

The active-rule equivalents — Failed Approaches that catch real recurring patterns — live in `CLAUDE.md §Failed Approaches — Do Not Repeat`.

## Why this file exists

Two patterns were mixed in CLAUDE.md's Failed Approaches list:

1. **Dead APIs and frameworks:** "AcousticBrainz shut down 2022" / "Spotify Audio Features deprecated 2024" / "MediaRemote private framework banned post-macOS 15." These describe historical events. Useful as "don't go looking for this" pointers but not active behavioral rules.
2. **Active rules:** "Drive presets from audio deviation, not absolute energy" / "Never use synthetic audio in diagnostics" / "No CoreML ANE Float16 with Float32 bindMemory." These describe rules that prevent recurring bugs today.

Mixing the two reduced the signal of every entry. The active rules stay in CLAUDE.md; the historical entries move here.

## Population

This file is populated by **DOC.3** (Failed Approaches refactor). It is empty in DOC.1.

Entries land below this divider in the order they moved from CLAUDE.md; numbering preserves the original Failed Approach number for cross-reference with git history.

---

<!-- Entries land here. Format mirrors CLAUDE.md §Failed Approaches: numbered + brief. -->
