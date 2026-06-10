# FBS.S5 Continuity — aurora slowdown (8–10 s), global bridge heave, finish the flash hunt

> Hand this to a new Claude Code session verbatim. Read `~/.claude/.../memory/project_fbs_beat_sync.md` and `feedback_diagnose_recommend_dont_fix.md` before any work.

## The three standing rules (each was earned the hard way this phase)

1. **Matt is product/design lead, NOT an engineer.** Plain English about what he SEES. No field names, no formulas, no jargon.
2. **Matt's session feedback = observations, NOT a work order.** Bug fixes restoring approved behavior: implement. Anything changing what he sees/feels: diagnose with evidence → 2–3 options with trade-offs + recommendation → WAIT for his pick. (He called this out directly on the S3.2 aurora cap.)
3. **Validation is measurement on rendered PIXELS, not input correlation.** Three input-side theories failed his eyes before the ablation method landed. The instrument: per-frame video census (ffmpeg signalstats YAVG) + `FerrofluidFlashForensicsTests` (offline re-render of real session windows through the live dispatch with ablation arms: `PHOSPHENE_SESSION_DIR`, `PHOSPHENE_FLASH_WINDOW=seg:lo:hi`, `PHOSPHENE_FLASH_ABLATE=none|pulse|aurora|light`).

## Matt's directives from the FBS.S4 read (session `2026-06-10T19-13-14Z`) — AUTHORIZED work

1. **Keep the regional punches** (D-157 — "I like the regional punches and think we should keep them").
2. **Bridge pulses go back to GLOBAL.** The slow opening heave was not visible with regional coverage. Global across the ocean until the handoff to the beat; regional punches only after. Implementation shape: ship a mask-blend signal from `BeatPulseClock` (it knows `handedOff`) → a spare `FeatureVector` pad (floats 43–48 free; reclaim `_pad7` as float 43, update Swift struct + BOTH MSL mirrors in `Common.metal` and `PresetLoader+Preamble.swift` — snake_case in MSL, FA #72) → `fo_spike_strength` mixes `mix(1.0, mask, blendSignal)`. Consider ramping the blend over a few beats at handoff rather than stepping.
3. **Slow the aurora transitions to ~8–10 s** — his words: "the aurora color is shifting too quickly… transition over a longer length of time, e.g., 8-10s." This covers BOTH intensity (drums route, currently rise τ 0.45 s / fall 1.2 s in `RenderPipeline.auroraDriverStep`) and **HUE (vocals-pitch route — see the open flash question below)**. The hue path lives in the matID==2 lighting branch (`RayMarch.metal`, `rm_ferrofluidSky`; CPU side feeds vocals fields via stems buffer). This is a CHARACTER change he explicitly requested — implement, then his read.

## The open flash question — where the hunt stands

- S4 cut clustered flash events ~150 → 79; Matt: "still present, prominent on some tracks" (big events: Love Rehab te≈32, So What te≈7/36, There There te≈5, Lotus te≈47–49 of that session).
- **Decisive handoff finding:** on the So What te 31–41 window the VIDEO shows 72–84-luma flashes but the forensics replica reproduces almost nothing (1 step) — the remaining flasher is NOT carried by the replica. The replica's known un-replicated audio route is **vocals pitch → aurora hue** (`vocalsPitchHz`/`vocalsPitchConfidence` are never set in the harness), and Matt independently perceives "aurora color shifting too quickly." Hue rotation changes YAVG. **Working hypothesis: the remaining flashing is aurora hue motion.**
- **First task of the new session:** add the vocals-pitch fields (from `stems.csv`) to `FerrofluidFlashForensicsTests`' stem replication, re-run the So What 31–41 window — if `none` now reproduces the video's flashes and an `aurora-hue` ablation arm kills them, the hypothesis is proven BEFORE implementing the 8–10 s slowdown (which then fixes it by design). If it does NOT reproduce, widen the replica-gap list (noise textures, SSGI, resolution, governor stepCount, video-encode artifacts) and close gaps one at a time — no input-correlation theorizing.

## State (all committed on local main, NOT pushed — 7 commits since the last push; push needs Matt's word)

- **Working:** first-note slow bridge (4 beats, D-153/D-154) → invisible envelope-floor handoff ≥10 s (D-156 + Money fix — phase-window coincidence is FROZEN when two signals share a tempo source) → per-beat punches on the live beat with regional masking (D-157, ~⅓ field, `pulse_beat_index` FV float 42). Matt-confirmed: Money syncs; Love Rehab transition seamless; regional punches liked.
- **Beat-irregular tracks never see FFO** (D-154 exclusion incl. the `cheapestFallback` hole; Pyramid = canonical; So What invisible to the gate — swing feel, future signal; Mingus excluded at 49% fold though Matt liked old-FFO there — flagged, undecided).
- **BUG-039 FIXED:** video writer dies intermittently (-11800/-16341, undocumented) → recorder rolls to `video_N.mp4` segments; field-proven. Census now ALWAYS possible.
- **Aurora hardening** (BUG-041 + S3.2 soft-knee/bloom): stands on its own measurements but was NOT the flasher; S3.2 was implemented WITHOUT authorization (the trigger for rule 2) — Matt has effectively ratified keeping it by directing further aurora slowing.
- **Open bugs:** BUG-042 (9.6 s analysis stall mid-track → frozen visuals + lurch; instrumentation = next step), the dev=35 stem-deviation anomaly (StemAnalyzer EMA divide-by-tiny suspect), So What quiet-intro over-punching → **Stage 2 energy-scaled punch heights** (designed, unbuilt, awaiting sequencing after the flash hunt).
- **Tools:** `tools/fbs/` (Stage-0 measurement), the forensics harness, `BeatPulseClockTests` real-session fixtures (`Tests/Fixtures/fbs/`), `AuroraTrackStartWarmupTests`. Documented flakes: MetadataPreFetcher / ProgressiveReadiness / SoakTestHarness (wall-clock budgets under parallel load — pass isolated).
- Increment rhythm: small increments; full engine suite + app build + SwiftLint --strict per increment; docs (DECISIONS next = D-158, ENGINEERING_PLAN, RELEASE_NOTES, KNOWN_ISSUES) per the CLAUDE.md closeout protocol; commit local main; **never push without "push" from Matt**.

## Suggested order for the new session

1. Forensics: vocals-pitch replication + aurora-hue ablation arm → prove/disprove the hue hypothesis on `19-13-14Z` So What 31–41 (and one Lotus window).
2. Implement Matt's three directives (global bridge heave + 8–10 s aurora transitions — hue AND intensity; regional stays post-handoff).
3. Acceptance: census target on re-rendered windows (events → ~0), local punch motion preserved, no white-pixel regression.
4. Closeout + plain-English report; ask for a live session; STOP for his read.
5. Queued after his read: Stage 2 energy heights (So What intro), BUG-042 instrumentation, the dev=35 anomaly.
