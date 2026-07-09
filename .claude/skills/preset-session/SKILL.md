---
name: preset-session
description: Mandatory opener for any preset-related increment in Phosphene — authoring, uplift, tuning, or fix. Invoke BEFORE opening any .metal file or editing a preset JSON sidecar, and when planning audio-reactivity routing for a preset. Covers the session-start checklist, the audio data hierarchy, and preset-scoped failure rules.
---

# Preset Session Opener

## Step 0 — mandatory reading, in order

1. `docs/PRESET_SESSION_CHECKLIST.md` — cover to cover. Canonical for Part 1 (session-start steps) and Part 2 (preset-session discipline: musical-role sentence, temporal contract, three-part concept bar, production-pipeline testing, design grounding, evidence-based closeouts). Do not proceed until read.
2. `docs/VISUAL_REFERENCES/<preset>/README.md` — per-image trait-trustability annotations and anti-references. No curated set → curate first or escalate to Matt.
3. The preset's design doc (`docs/presets/<PRESET>_DESIGN.md`) if one exists.

Render early: produce a `RENDER_VISUAL=1` contact sheet before the first tuning commit.

## Audio data hierarchy (canonical home: this skill, from CLAUDE.md at DOC.9)

**Visuals driven primarily by continuous energy feel locked to the music; visuals driven primarily by raw live beat detections feel out of sync.** Learned in the Electron prototype, validated across every preset since.

- **Layer 1 — Continuous energy bands (DEFAULT PRIMARY DRIVER):** `bass`/`mid`/`treble` + 6-band. Zero detection delay. Drive from deviation primitives (`bassRel`, `bassDev`, …, D-026), never from absolute thresholds on AGC-normalized values (FA #31 below).
- **Layer 2 — Spectrum and waveform textures:** 512 FFT bins + 1024 waveform samples as GPU buffer data, not scalars.
- **Layer 3 — Spectral features:** centroid, flux, rolloff, MFCCs, chroma → color temperature, complexity, scene behavior.
- **Layer 4 — Beat events:** accents by default. Live onsets jitter ±80 ms; never drive primary motion from raw live onsets. Beat-locked motion IS viable on the cached `BeatGrid` (Beat This! on the preview clip), with beat-irregular tracks excluded (D-154) and bounded spatial footprint per beat with steady global luminance (D-157). Pattern to follow: FFO beat-sync work, D-153 → D-158. Rule of thumb for onset accents: `base_zoom`/`base_rot` 2–4× larger than `beat_zoom`/`beat_rot`.
- **Layer 5a/5b — Stems:** pre-analyzed from preview clips (instant on track change, not time-aligned) crossfading to real-time tap stems after ~10 s.

**Cold-start phase contract:** automated cold-start beat-phase derivation was empirically falsified across six iterations and retired (Matt's Choice A, 2026-05-25) — do not iterate further; any new approach needs a fundamentally different premise, surfaced to Matt first. At cold-start: continuous energy + deviation primitives from frame 1; cached `BeatGrid` installs with reliable BPM/meter but possibly wrong phase; ungated beat accents fire from frame 1 (wrong-phase tracks fire wrong-phase accents). Presets needing cold-start accent suppression implement it themselves. Full contract and history: `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md` §Cold-Start Phase Contract.

## Routing rule — one primitive per layer (FA #67)

Before adding audio reactivity to a visual layer, table out (visual layer × audio primitive × timescale). If two layers share a primitive, or two primitives at the same timescale, that is the bug — the music overdrives the same information through two visual channels and reads as "fighting itself." Ferrofluid Ocean rounds 56–65 is the case study: per-beat spike pulse + per-beat swell pump competed until the drums coupling was removed from swell (arousal-only, slow) and only the spike layer carried the per-beat signal.

## Preset-scoped failure rules

- **FA #27 — Synthetic audio for diagnostics:** hand-authored FeatureVector envelopes do not reproduce real-music pipeline noise, cross-band correlation, or MIR-derived structure. Diagnostic harnesses must run the actual capture path on real audio.
- **FA #31 — Absolute thresholds on AGC-normalized energy** (e.g. `smoothstep(0.22, 0.32, f.bass)`): AGC's running-average denominator moves with mix density; the same kick reads different values across tracks. Drive from deviation — `f.bassRel`, `f.bassDev` (D-026). Full diagnosis: `docs/MILKDROP_ARCHITECTURE.md`.
- **Silence must never render black** (D-037): every preset renders a non-black silence state.
- **One rendering paradigm per preset** (D-029). **3D for physical metaphors; environments rendered, not implied.**
- Reference/porting discipline (FA #64/#65/#73) lives in the `shader-authoring` skill — invoke it before writing shader code.

## Escalation thresholds — stop and bring the gap to Matt when

- two consecutive M7 reviews return negative feedback whose root cause you cannot articulate;
- a concept pitch fails the three-part bar;
- you catch yourself producing structure as a substitute for an answer;
- a "reusable infrastructure" argument is forming in defense of deleted-concept code;
- the one-sentence "what I now believe about why this preset is failing" hasn't changed between M7 rounds.
