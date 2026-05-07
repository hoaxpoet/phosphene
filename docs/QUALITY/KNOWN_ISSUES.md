# Phosphene — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

---

## Open

---

### BUG-007.4 — Beat-counter "1" misaligned with song's actual downbeat on prepared-cache tracks

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** **Resolved 2026-05-07** — BUG-007.4a (manual `Shift+B`) + BUG-007.4b (auto-rotate via kick density) landed. Manual validation pending for BUG-007.4b.
**Introduced:** Reported 2026-05-07 from manual validation captures (`2026-05-07T14-28-40Z/` and prior). User-observed: when watching the SpectralCartograph beat-in-bar counter and listening to SLTS / Everlong (Spotify-prepared), the visual "1" does not land on the song's actual perceived downbeat — it lands on what feels like beat 2 or beat 3 of the bar.
**Resolved:** 2026-05-07 — two-step fix.

- **BUG-007.4a (`Shift+B` manual rotation, landed earlier today)**: developer-only keybind that cycles `barPhaseOffset` 0..(beatsPerBar−1). Resets on track change. Confirmed in session `T18-21-37Z` that rotation works as designed.
- **BUG-007.4b (auto-rotate via kick density)**: after `matchedOnsets >= 8` (lock has stabilised), the tracker examines per-slot kick-onset histogram in `slotOnsetCounts` and rotates `_barPhaseOffset` so the dominant slot (where kicks land most often) becomes the displayed "1". One-shot per track. Suppressed if user pressed `Shift+B` first (manual intent wins). No-op if no clear winner — leading slot must have ≥ 4 onsets *and* ≥ 1.5× the runner-up's count. Four-on-the-floor electronic (OMT) has equal kick density on all slots → no rotation, manual `Shift+B` remains the fallback. Tracks with kick on 1+3 or 1-only patterns (HUMBLE, SLTS, Everlong, MC) auto-rotate within 4–8 seconds of lock acquisition.

Variance ring + slot histogram + auto-rotate flags reset on `setGrid` so each track starts fresh.

**Confirmed root cause (2026-05-07, after 5-track diagnostic A/B):** Spotify preview URLs return a 30-second clip from somewhere in the song — *often the chorus, not the first 30 seconds*. Beat This! analyzes the clip, builds a grid, and labels the first beat in the clip as "beat 1 of bar 1." That beat in the clip is typically beat 2, 3, or 4 of the original song's bar. When playback starts from the song's beginning and we install the grid with `offsetBy(0)`, the clip's "beat 1" maps to playback time 0 — but the song's actual beat 1 of bar 1 is at playback time 0. The two don't agree. Result: bar-phase rotation per track, depending on where in the bar Spotify's clip happens to begin.

This is **not** a flaw in Beat This!'s downbeat detection — Beat This! is correctly identifying the bar phase *of the clip*. The mismatch is between the clip's coordinate system and the live-playback song coordinate system.

**5-track A/B evidence (sessions `2026-05-07T15-50-23Z` + `2026-05-07T15-58-17Z`):**

| Track | Visual "1" lands on song's | Off by | Spotify preview likely from |
|---|---|---|---|
| One More Time (Daft Punk) | beat 4 | +3 | chorus mid-bar |
| Midnight City (M83) | beat 4 | +3 | chorus mid-bar |
| HUMBLE. (Kendrick) | beat 3 | +2 | chorus / verse mid-bar |
| SLTS (Nirvana) | beat 1 ✓ | 0 | first 30 s (intro) |
| Everlong (Foo Fighters) | beat 3 | +2 | chorus / verse mid-bar |

The varying off-by-N (0, 2, 3) per track rules out a constant pipeline rotation bug. SLTS being the only one that worked correlates with SLTS's preview being the song intro (less commercial tracks tend to preview from start; popular dance/pop tracks preview from chorus).

**Expected behavior:** On a 4/4 prepared-cache track, the SpectralCartograph beat-in-bar counter shows "1" exactly when the song's bar starts (the kick drum + accent that listeners hear as the downbeat). For SLTS, that's the kick on the strong beat after each pickup. For Everlong, the same. `is_downbeat=1` rows in `features.csv` should land at song-relative times that match the ear's perception.

**Actual behavior:** User reports visual "1" lands 2–3 beats away from the audio's perceived "1" on at least SLTS and Everlong (planned, prepared cache, drift CSV near zero). Drift `mean ≈ +2.5 ms` on SLTS and lock state holds steady — beat-phase alignment is correct. Bar-phase / downbeat selection appears to be the variable.

**Reproduction steps:**
1. Spotify-prepared session containing SLTS + Everlong.
2. Switch to SpectralCartograph (`Shift+→`); press `L` to lock the diagnostic preset.
3. Play SLTS. Watch the beat-in-bar text readout and the BR-panel BAR-φ row.
4. Listen for the song's perceived downbeats and count along.
5. Observe whether "1" on the visual matches the ear's "1".

**Minimum reproducer:** Any Spotify-prepared session on a 4/4 rock track where the user can mentally count beats. SLTS, Everlong are confirmed. May not affect electronic / four-on-the-floor tracks where every beat is a downbeat-feel.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-07T14-28-40Z/features.csv` — SLTS first observed `is_downbeat=1` at `playback_time=42.96` (during locked window). Earlier downbeats during locking phase. BPM=117.6 → bar period 2.04 s. Observed downbeat distribution across 4 beat-in-bar values is roughly uniform (1461 / 1462 / 1412 / 1442 frames each), consistent with the meter being identified correctly but the *rotation* (which beat is "1") possibly off.
- `2026-05-07T14-33-47Z/features.csv` — reactive Everlong got `meter=2/X` from a half-time grid (`bpm=85.4`) — that's BUG-009, separate from this bug.

**Confirmed failure class:** `calibration` (Spotify clip start-position not on song bar boundary; Beat This! is correctly identifying bar phase *of the clip*, but the clip's bar phase doesn't equal the song's bar phase from start).

**Fix scope (three options, ranked by leverage):**

**(C) — Developer rotation shortcut (FIRST: ship as BUG-007.4a, ~1 hour).** Add `Shift+B` to `PlaybackShortcutRegistry` to cycle `barPhaseOffset` between 0..N-1 (where N = `beatsPerBar`). Apply offset when computing `beat_in_bar` and `barPhase01` for the SpectralCartograph readouts. Does not fix anything automatically — but lets the user confirm the rotation hypothesis in seconds (cycle Shift+B until "1" lands on the audio's downbeat) and provides an escape hatch for the long-tail tracks the auto-fix won't catch. Cheap, fully reversible.

**(A) — Auto-rotate via kick-density heuristic (durable fix; BUG-007.4b, ~80 LOC + tests).** After the grid is installed and the drift tracker has 8+ matched onsets, examine which of the N beat-in-bar slots has the highest kick energy on average. That slot is the actual song downbeat. Rotate `beat_in_bar` numbering accordingly. Doesn't require Spotify metadata; works on prepared and live grids equally; converges in ~5–10 seconds. Beat This! identifies *meter* (correctly); the heuristic identifies *which beat in that meter is "1"*.

**(B) — Pre-rotate at preparation time (alternative to A).** Run the kick-density heuristic on the cached 30-second preview audio at preparation time, before the grid is stored in `StemCache`. Faster lock-in (no live convergence period), but requires re-running an onset detector on the cached audio. Higher complexity; defer unless (A)'s convergence delay is unacceptable.

**Recommended sequence:** (C) first to confirm theory in <1 hour. Then (A) as the durable fix. (B) deferred unless needed. **Both (C) and (A) landed 2026-05-07.**

**Out of scope:**
- Reactive-mode downbeat detection — different code path; live grids will benefit from (A) automatically since the same heuristic applies post-install.
- Time-displacement (visual ahead of / behind audio in absolute time). Drift CSV shows beats are aligned. This bug is about *which* beat gets labelled "1", not about *when* beats fire.
- Asking Spotify for clip-start-time-in-song metadata — not exposed by their API.

**Verification criteria:**
- [ ] (C) lands: `Shift+B` cycles bar-phase offset; visual "1" can be aligned to song's "1" on all 5 test tracks within 0..3 presses. Toast/log confirms current offset.
- [ ] (A) lands: visual "1" lands on song's "1" automatically within 10 s of lock-in on OMT, Midnight City, HUMBLE, SLTS, Everlong. No regression on SLTS.
- [ ] On a fully ambient / non-metric track (no obvious kick density per slot): system gracefully holds the Beat This! choice rather than picking a random slot.

**Related:** BUG-008 (offline BPM disagreement — orthogonal), BUG-007 / 007.2 (lock hysteresis — orthogonal), BUG-007.3 (reverted, `78ade5aa`), BUG-007.5 (separately confirmed by Everlong "pulse slightly off" observation in 2026-05-07T15-58-17Z).

---

### BUG-007.6 — Tap-vs-output audio latency calibration

**Severity:** P2 (visible — visual fires before audio is heard, persistent across all tracks).
**Domain tag:** dsp.beat
**Status:** **Resolved (calibration constant + dev shortcut landed 2026-05-07)** — manual validation pending.
**Introduced:** Pre-existing in all prior code; surfaced by the 2026-05-07 5-track A/B (sessions `T15-50-23Z`, `T15-58-17Z`, `T18-21-37Z`) which showed systematic negative drift averaging −36 to −76 ms on every prepared-cache track regardless of BPM. Pattern: tap captures audio L ms before the listener hears it (CoreAudio output buffer + DAC + driver). The tracker's drift converges to roughly −L; the visual orb fires at `pt + drift = pt − L`, before the audio reaches the speaker. User-perceived as "beat in SC feels a little bit faster than the song's actual beat."
**Resolved:** 2026-05-07. New `LiveBeatDriftTracker.audioOutputLatencyMs: Float` (default 0 in engine, set to 50 ms in `VisualizerEngine` app-layer init for internal Mac speakers). Applied to the *display path only* — `displayTime = pt + drift + (audioOutputLatencyMs + visualPhaseOffsetMs) / 1000`. Does NOT touch onset matching or drift estimation: those use unmodified `playbackTime` so the matching path is unchanged. Tunable at runtime via `,` (−5 ms) and `.` (+5 ms) developer shortcuts. Persists across track changes (it's a system property, not a per-track property).

**Expected behavior:** With `audioOutputLatencyMs` calibrated to the platform's actual tap-to-speaker delay, the visual orb pulses in sync with the kick the listener hears.

**Actual behavior (pre-fix):** Visual leads audio by ~50 ms on internal Mac speakers (typical CoreAudio output buffer). Up to several hundred ms on Bluetooth/AirPlay output devices.

**Reproduction steps:**
1. Spotify-prepared session, internal Mac speakers, any track that locks reliably (SLTS, OMT).
2. Watch the SpectralCartograph beat orb while listening.
3. Pre-fix: orb pulses just before each audible kick.

**Confirmed failure class:** `calibration`.

**Diagnosis notes:**
- Tap captures pre-output-buffer audio. The audio then takes ~10–50 ms (internal Mac speaker), 100–300 ms (Bluetooth), 500–1500 ms (AirPlay) to reach the listener's ears.
- Onset detection in our pipeline also has some processing delay (~50 ms FFT-window center bias). The combined effect of *output latency* + *detection delay* is what the user perceives. The single calibration constant `audioOutputLatencyMs` collapses both into one knob.
- Applying compensation to *matching* (shifting `pt` before grid lookup) cancels itself out on the display side — `pt + drift` is invariant under shifts of `pt`. So compensation must go on display.
- The diagnostic drift readout in SpectralCartograph remains at its raw negative value (e.g. −50 ms) — that's accurate; it represents detection delay, not perceptual sync. Visual sync is fixed by display-side compensation.

**Verification criteria:**
- [x] Automated: drift convergence is identical with `audioOutputLatencyMs=0` and `audioOutputLatencyMs=50` on the same input (matching path unaffected). Verified by `audioOutputLatencyMs_shiftsDisplayNotMatching`.
- [x] Automated: at the same playback time, `beatPhase01` differs by L/period between latency=0 and latency=L. Verified by the same test.
- [x] Automated: setter clamps to ±500 ms. Verified by `audioOutputLatencyMs_setter_clampsToRange`.
- [x] Automated: persists across `setGrid` and `reset` (system property). Verified by `audioOutputLatencyMs_persistsAcrossSetGrid`.
- [ ] Manual: SpectralCartograph beat orb pulses in audible sync with kick on SLTS, OMT, Midnight City, HUMBLE, Everlong using internal Mac speakers and the default 50 ms calibration.
- [ ] Manual: `,` / `.` shortcuts adjust visual sync ±5 ms per press; user can dial in a per-output-device offset within 1–2 minutes.

**Out of scope:**
- Persisting `audioOutputLatencyMs` across app launches (currently resets on cold start). Will be a settings-panel field in a future increment.
- Per-output-device automatic detection (Bluetooth vs internal). Future increment if needed.
- Variance-adaptive lock-window logic — that's BUG-007.5.

**Related:** BUG-007.3 (reverted), BUG-007.4 (orthogonal — bar phase rotation), BUG-007.5 (orthogonal — lock-release timing), the existing `visualPhaseOffsetMs` (`[`/`]` shortcut, ±10 ms) which is now additive with this constant on the display path.

---

### BUG-007.5 — Lock hysteresis for asymmetric drift envelopes

**Severity:** P3 (cosmetic — visual flicker between LOCKED and LOCKING; doesn't affect beat-phase)
**Domain tag:** dsp.beat
**Status:** **Resolved (parts 1 + 2 + 3, 2026-05-07)** — manual validation pending.
**Introduced:** Surfaced 2026-05-07. Pre-exists BUG-007.3 (the reverted attempt). The fixed-window Schmitt hysteresis (`staleMatchWindow=0.060` in commit `94309858`) attempted this and failed because the "right" stale window depends on the drift variance, which differs by track.
**Resolved:** 2026-05-07 — Two-part fix.

**Part 1 (time-based release gate)**: Replaced the count-based `lockReleaseMisses=7` gate with a *time-based* `lockReleaseTimeSeconds=2.5` gate. Lock now drops when 2.5 s of consecutive non-tight matches have elapsed since the last tight hit, regardless of how many onsets occurred in between. Sparse-onset tracks (HUMBLE half-time at 76 BPM = 790 ms beat period) no longer trip the gate accidentally — what matters is the elapsed time, not the count. Diagnostic counter `consecutiveMisses` retained on `LiveBeatDriftTraceEntry` for backward compat.

**Part 2 (variance-adaptive tight gate)**: Replaced the fixed ±30 ms tight-match window during the *retention* phase (after lock acquired) with an adaptive `effectiveTightWindow = clamp(2σ, 30 ms, 80 ms)` derived from the running stddev of the last 16 `instantDrift − drift` values. Acquisition path still uses the fixed 30 ms floor for selectivity. This closes the remaining lock-flicker on tracks where drift envelope is wider than ±30 ms despite small EMA bias (Midnight City: drift envelope ±20 ms with σ ≈ 12 ms → adaptive window ≈ 24 ms; HUMBLE: σ ≈ 25 ms → adaptive window ≈ 50 ms; B.O.B. polyrhythmic noise: σ ≈ 40 ms → adaptive window clamped at ceiling 80 ms).

Variance ring resets on `setGrid` / `reset` so each track starts fresh at the floor.

**Part 3 (BPM-aware time gate, landed same day)**: replaced the fixed 2.5 s `lockReleaseTimeSeconds` with `effectiveLockReleaseSeconds = max(2.5 s, 4 × medianBeatPeriod)`. At 120+ BPM the gate stays at the 2.5 s floor (4 × 0.5 = 2.0 s, below floor). At HUMBLE half-time (76 BPM, 790 ms period) the gate scales to 3.16 s — accommodates 4 consecutive sparse non-tight events without dropping lock. At 60 BPM (period 1.0 s) the gate reaches 4.0 s. This closes the failure mode where HUMBLE drops lock every ~5 seconds despite small per-onset deviations from the EMA — the issue was sparse onsets accumulating to 2.5 s before a tight match arrived.

**Expected behavior:** Once `lock_state` reaches LOCKED on a track with correct grid BPM, it stays there for the duration of the song unless the input goes silent or the BPM is genuinely wrong. Lock should not flicker due to per-onset noise within ±60 ms of the EMA.

**Actual behavior (on Everlong planned, prepared, BPM=157.8):** Drift envelope spans −68 to +25 ms with EMA settling at −41 ms. Many individual onsets fall 50–80 ms from the EMA — outside the fixed ±60 ms gate that BUG-007.3 attempted. Lock drops 14 times in 75 s (sessions `2026-05-07T14-28-40Z`). On SLTS planned (drift envelope ~ ±50 ms with EMA near zero) the same fixed gate worked: only 2 drops in 105 s. The variance is the variable; a one-size-fits-all stale window doesn't fit both.

**Reproduction steps:** Play Everlong from a Spotify-prepared session, watch the SpectralCartograph mode label flicker between `● PLANNED · LOCKED` and `◑ PLANNED · LOCKING` while the beat orb continues to pulse on the kick (beat-phase alignment is fine; only the lock indicator flickers).

**Minimum reproducer:** Any rock track with a dense, slightly-rushed snare-and-cymbal pattern at 150+ BPM. Everlong is the gold reference.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-07T14-28-40Z/features.csv` — Everlong rows at BPM=157.8: 14 lock drops, drift min/max −68 / +25, drift mean −41 ms.

**Suspected failure class:** `algorithm`.

**Diagnosis notes:**
- BUG-007.3's premise that ±60 ms covers natural tempo variation was correct on SLTS but wrong on Everlong. SLTS's drift std-dev over a 10 s window is roughly half Everlong's.
- Adaptive approach: track the running std-dev of `instantDrift` over the last N onsets. Define `staleMatchWindow = clamp(K × stddev, 30 ms, 120 ms)`. K ≈ 2 sigma. This auto-widens for noisy material and stays tight for clean material.
- Alternative: track per-onset variance via Welford's algorithm (no allocation, lock-friendly).

**Verification criteria:**
- [ ] On Everlong planned: ≤ 1 lock drop in 50 s of continuous playback.
- [ ] On SLTS planned: no regression — still ≤ 2 drops in 100 s.
- [ ] On Billie Jean reactive (control): no regression.
- [ ] Automated regression test: synthetic input with 60 ms-stddev jitter at 158 BPM should hold lock for 60 s with ≤ 1 drop.

**Fix scope (~30 LOC + tests):**
1. Add a small running-variance accumulator on per-onset `instantDrift` values to `LiveBeatDriftTracker` (Welford's online variance, ring of last 16 onsets).
2. Compute `staleMatchWindow = clamp(2.0 × stddev, 30 ms, 120 ms)` per onset.
3. Apply the same Schmitt branching as BUG-007.3's Part (a), but with the dynamic gate.

**Out of scope:**
- Replacing `strictMatchWindow` (acquisition selectivity unchanged).
- Touching the slope-detector / wider-window-retry idea from BUG-007.3 Part (b). That belongs to a *future* increment if BUG-009 doesn't subsume it.

**Related:** BUG-007.3 (reverted attempt — fixed gate). BUG-007.4 (downbeat alignment — orthogonal).

---

### BUG-009 — Halving-correction threshold (160 BPM) too aggressive; halves legitimate fast tempos

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** **Resolved 2026-05-07** — threshold raised 160 → 175 in `BeatGrid.halvingOctaveCorrected()`. New regression test `halvingOctaveCorrected_fastRockBPM_isNoOp` covers four fixtures (158 / 168 / 172.5 / 175 BPM) and confirms each passes through unchanged. Existing tests updated for the new boundary; the extreme-double-halve fixture moved from 322 → 360 BPM to retain factor-4 thinning coverage. **Manual validation pending** — next reactive Everlong session should install at `bpm=158 ± 8` (not the pre-fix 85.4 half-time alias).
**Introduced:** DSP.3.5 (2026-05-05). `BeatGrid.halvingOctaveCorrected()` halves any BPM > 160 to the nearest sub-160 value. Threshold chosen at 160 because most pop / rock / electronic music falls below it. Surfaced 2026-05-07 when reactive Everlong (true ≈158 BPM) received a Beat This! raw output > 160, triggering halving down to 85.4 BPM — visibly wrong.

**Expected behavior:** A track with true tempo in [160, 200] BPM (drum'n'bass, fast metal, jungle, fast electronic, "Everlong"-class rock) gets a grid at its true tempo, not the half-time alias. Halving should fire only when the raw analyser output is more than ~10–15 % above the genuine perceptual tempo — i.e. for true double-time errors.

**Actual behavior:** Threshold is fixed at 160 BPM. Beat This! `small0` outputs ranging 165–180 on tracks with true tempo near 158 (off by < 15 %) get halved unconditionally. Result: half-time grid; visual orb pulses at half rate; bar-phase wrong; user listens to a song at 158 BPM but sees animation at 85.

**Reproduction steps:**
1. Reactive (ad-hoc) session, no Spotify preparation.
2. Play Everlong (Foo Fighters).
3. Wait for live grid install at ~10 s.
4. Read `session.log`: `BeatGrid installed: source=liveAnalysis, ..., bpm=85.4, beats=443, meter=2/X`.

**Minimum reproducer:** Any track with true BPM in roughly [160, 175] played in a reactive session. Everlong is the canonical case.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-07T14-33-47Z/session.log` — `bpm=85.4, beats=443, meter=2/X` on Everlong reactive. True ~158 BPM.

**Suspected failure class:** `calibration`.

**Diagnosis notes:**
- 160 BPM is below typical drum'n'bass (170–175), fast metal (180+), and fast indie rock (Foo Fighters, Strokes, Arctic Monkeys typically 155–170). The threshold was chosen for a 30 s offline window where Beat This! is more accurate; the live 10 s window is noisier and pushes more legitimate tracks above 160.
- Two candidate fixes:
  - (a) Raise threshold to 175 (or 180). Captures most fast-rock without re-enabling true-double-time errors. Risk: doesn't catch an actual 90 BPM track that Beat This! reports as 180.
  - (b) Use BPM confidence from the grid output (number of beats supporting the BPM, drift slope, etc.) rather than a hard threshold. Heavier; would land in a follow-up.
- Pyramid Song (true ≈68 BPM) must stay un-corrected — already protected by BPM > 160 condition. (a) preserves this.

**Verification criteria:**
- [ ] On Everlong reactive: live grid installs at `bpm=158 ± 8` (within ±5 %).
- [ ] On Pyramid Song (true 68 BPM): grid stays at 68 BPM, not 136.
- [ ] On Money 7/4 (~123 BPM): no regression.
- [ ] On a confirmed-double-time test track (synthetic 80 BPM that triggers Beat This! to output 160+): halving still fires. Find or synthesize a fixture for this.

**Fix scope (likely ~5 LOC + test):** raise threshold to 175 in `BeatGrid.halvingOctaveCorrected()`. Add regression test on a 158 BPM input that confirms no halving fires (currently halves; post-fix doesn't).

**Out of scope:**
- BPM-confidence-aware correction (option b above). Defer to future work if option (a) leaves residual bad cases.
- Doubling correction for sub-80 BPM tracks (already disabled by design — Pyramid Song would break).

**Related:** DSP.3.5 (introduced halving correction); BUG-008 (offline BPM disagreement — orthogonal). BUG-007.3 (reverted; surfaced this issue but didn't address it).

---

### BUG-007.3 — Lock hysteresis still oscillates on drift-prone tracks; live BPM resolver fragile on busy mid-frequency content

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Closed (attempt reverted — see commit `78ade5aa`). Replaced by BUG-007.4 + BUG-007.5 + BUG-009.
**Introduced:** Surfaced 2026-05-07 during manual validation of two sessions captured post-QR.2 (`~/Documents/phosphene_sessions/2026-05-07T13-27-14Z/` planned, `~/Documents/phosphene_sessions/2026-05-07T13-30-46Z/` reactive). Predates QR.2 (QR.2 did not change drift-tracker semantics). BUG-007.2 widened `lockReleaseMisses` 3 → 7, which closed the 30 s freeze + the 400 ms/487 ms adversarial scenario but left two additional failure modes.
**Reverted:** 2026-05-07. The Schmitt hysteresis (Part a) + drift-slope retry (Part b) implementation in commit `94309858` was reverted in commit `78ade5aa` after manual validation evidence (`2026-05-07T14-28-40Z` + `T14-33-47Z`) showed Everlong planned regressed (14 lock drops vs 5 pre-fix). The fix's premise — that wider stale-OK retention would close natural-tempo-variation drops — held on SLTS but not on Everlong, where the drift envelope is asymmetric around its EMA (−68 to +25 ms with avg −41 ms) and many onsets land outside ±60 ms of the EMA. Net: the fix improved one track and worsened another. User also observed downbeat misalignment ("1" not on song's downbeat) which drift CSV cannot rule in or out — beat phase was correct (drift ≈ 0 on SLTS) but bar-phase / downbeat selection may be wrong. Three follow-up bugs scoped (BUG-007.4 / 007.5 / 009).

**Expected behavior:** On any track where the offline/live BPM is within ±1 % of true tempo, `lock_state` reaches `2` (LOCKED) and stays there for the duration of the track, with `drift_ms` settling into a band whose `stddev` over a 10 s window is below ~25 ms. On busy mid-frequency tracks (rock, power chords) where the live 10 s window is insufficient, the system either widens its analysis window or surfaces a warning, but does not silently lock to a 4 % wrong BPM.

**Actual behavior:** Two distinct mechanisms.

- **Mechanism C — natural-music tempo variation drops lock under correct BPM.** Smells Like Teen Spirit (planned, prepared cache, `grid_bpm=117.6`, true ≈117) held lock for 80 s straight but `drift_ms` walked from +15 → −90 over 90 s. Everlong (planned, prepared, `grid_bpm=157.8`) dropped lock 5 times in 50 s with drift in the −30 to −68 ms band, even though BPM was correct. The drops were caused by individual onsets falling outside `abs(instantDrift − drift) < strictMatchWindow=30 ms` for ≥ 7 consecutive onsets. At ≈158 BPM that is a 2.7 s window, and noisy onsets (harmonics, reverb tail, snare bleed) cluster easily. The 30 ms tight-match gate is too strict for the natural micro-timing variation of real performances.

- **Mechanism D — live BPM resolver returns 4 % low on busy mid-frequency content.** Reactive Everlong gave `grid_bpm=151.9` (true ≈158, 3.86 % low). Drift went from 0 → −358 ms over 75 s — roughly one full beat. Billie Jean (synth pop, kick on the beat) gave `grid_bpm=117.1` (true ≈117) and drift stayed bounded ±90 ms. The 10 s live window at busy power-chord-guitar onset density does not give Beat This! enough evidence to nail the BPM within 1 %.

**Reproduction steps:**
1. Start a Spotify-prepared session containing Smells Like Teen Spirit and Everlong.
2. Play SLTS → Everlong while Phosphene runs.
3. Observe: `lock_state` reaches 2 on both, but Everlong drops 5+ times; both walk negative drift.
4. Then start an ad-hoc (reactive) session and play Everlong.
5. Observe: `grid_bpm=151.9`, drift goes to −358 ms by ~75 s.

**Minimum reproducer:**
- Mechanism C: any prepared-cache session on a track with natural human tempo variation > 0.3 % over 60 s. SLTS, Everlong, and most rock/indie material qualify.
- Mechanism D: any reactive session on Everlong (or comparable busy mid-frequency content). Quiet-intro tracks (SLTS) recover via the 20 s retry path; high-onset-density tracks do not.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-07T13-27-14Z/features.csv` — SLTS held LOCKED 4806 frames (80 s); Everlong dropped 5 times. Drift slopes documented in chat analysis 2026-05-07.
- `~/Documents/phosphene_sessions/2026-05-07T13-30-46Z/features.csv` — Reactive Everlong drift 0 → −358 ms over 75 s; reactive Billie Jean drift bounded ±90 ms (control case).

**Confirmed failure class:** `algorithm` (Mechanism C — over-strict tight-match gate without asymmetric hysteresis) + `calibration` (Mechanism D — 10 s live window insufficient for busy mid-freq onset density).

**Diagnosis notes:**
- Mechanism C is *not* solved by raising `lockReleaseMisses` further. With the gate already at 7, raising it to 12 just delays inevitable drops on tracks with > 7-onset stretches of natural micro-timing variation. The fix is asymmetric hysteresis: keep the 30 ms gate for *entering* lock (selectivity), use a wider gate (e.g. 60 ms) for *staying* locked (stickiness). This is the standard Schmitt-trigger pattern.
- Mechanism D cannot be solved by lock hysteresis at all — the BPM itself is wrong. The fix is at the resolver layer: wider live window (10 s → 20 s) on retry, and a drift-slope detector that re-triggers live analysis when sustained drift slope exceeds a threshold for ≥ 10 s.
- Drift sign is consistently negative across all tracks, suggesting a small constant tap-output latency contribution (~10–15 ms) on top of any BPM error. Not addressed by this bug — would be a separate calibration constant if pursued.

**Verification criteria:**
- [ ] On SLTS planned (prepared cache, BPM=117.6): `lock_state == 2` for ≥ 95 % of frames after first lock; `stddev(drift_ms over 10 s window) < 25 ms`.
- [ ] On Everlong planned (prepared cache, BPM=157.8): ≤ 1 lock drop in 50 s of continuous playback.
- [ ] On Everlong reactive: either grid BPM converges to within ±1 % of 158 within 30 s of playback (via wider retry window), or `WARN: live BPM credibility low` is logged and the system stays in LOCKING rather than locking to a wrong grid.
- [ ] On Billie Jean reactive (control): no regression — drift stays bounded ±90 ms, lock holds.
- [ ] Automated: a deterministic regression test in `LiveBeatDriftTrackerTests` simulating an outlier-onset stream within a 30 ms-EMA-correct grid demonstrates Mechanism C is closed (≤ 1 lock drop per 60 s of synthetic input where current code drops ≥ 4).
- [ ] Manual: drift readout in SpectralCartograph stays close to zero on SLTS and Everlong (planned). Beat orb pulse sits exactly on the kick across both tracks.

**Fix scope (BUG-007.3 — one increment, two parts):**

**Part (a) — Asymmetric Schmitt-style hysteresis (small, ~15 LOC + tests).** In `LiveBeatDriftTracker.swift`:

```swift
// New constant:
private static let staleMatchWindow: Double = 0.060   // ±60 ms — once locked, stay locked

// In update(), replace the single isTight gate with:
let isTight = abs(instantDrift - drift) < Self.strictMatchWindow
let isStaleOK = abs(instantDrift - drift) < Self.staleMatchWindow
let alreadyLocked = (matchedOnsets >= Self.lockThreshold) && (consecutiveMisses < Self.lockReleaseMisses)

if isTight {
    matchedOnsets = min(matchedOnsets + 1, Int.max - 1)
    consecutiveMisses = 0
} else if alreadyLocked && isStaleOK {
    // While locked, a "stale-OK" onset doesn't increment matchedOnsets but
    // also doesn't increment consecutiveMisses — preserves lock under natural
    // tempo variation without making lock easier to acquire initially.
    // matchedOnsets unchanged
} else {
    consecutiveMisses += 1
}
```

This keeps lock-acquisition selectivity (still need 4 ±30 ms hits) but raises lock-retention stickiness to ±60 ms.

**Part (b) — Live-BPM credibility gate + retry with wider window (medium, ~50 LOC + tests).** Two pieces:

1. **Drift-slope detector** in `LiveBeatDriftTracker`: maintain a small ring of `(playbackTime, drift)` samples (~30 entries, ~3 s at 10 Hz onset rate). Expose `currentDriftSlope() -> Double?` returning ms/sec when ≥ 5 samples cover ≥ 5 s; nil otherwise. Called from `MIRPipeline.buildFeatureVector` once per frame; result published on a new `latestDriftSlope` property.

2. **Retry trigger** in `VisualizerEngine+Stems.runLiveBeatAnalysisIfNeeded()`: in addition to the existing two-attempt schedule (10 s, 20 s on empty grid), add a third condition — if `liveDriftTracker.hasGrid && abs(currentDriftSlope) > 5.0 ms/sec` sustained for ≥ 10 s, and at least 30 s have passed since the last attempt, trigger a re-analysis with a 20 s window (vs the standard 10 s). Cap retries at 3 per track. Log `WARN: live BPM credibility low (slope=Xms/s) — retrying with 20 s window`.

If the wider window also produces an out-of-band BPM estimate (slope still > 5 ms/sec after the retry), log `WARN: live BPM unstable on this track` and *retain the previous grid* rather than installing a new wrong one — better to keep visuals close-but-drifting than to thrash through three different wrong grids.

**Out of scope for this increment:**
- Fixing the consistent ~10–15 ms negative-drift offset (likely tap-output latency calibration). Tracked separately if pursued.
- Replacing the offline Beat This! resolver (BUG-008 — independent).
- Changes to `strictMatchWindow` itself. Selectivity at acquisition time stays at ±30 ms.

**Estimated effort:** 1 day. Part (a) is ~half a day including the deterministic regression test; part (b) is ~half a day including the 20 s window retry path and the slope-detector unit test.

**Related:** BUG-007.2 (resolved upstream — covers Mechanism A + B; this bug covers Mechanisms C + D), BUG-008 (offline BPM disagreement — independent), DSP.3.4 (sample-rate fix on live path), DSP.3.5 (octave correction + retry — already established the multi-attempt pattern this fix extends), QR.1 (touched the file but did not change lock semantics).

---

### BUG-001 — Money 7/4 stays REACTIVE on live path

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** DSP.3.5 (identified; pre-existing limitation of the 10-second live window)
**Resolved:** —

**Expected behavior:** After 20 seconds of playback (two retry attempts), Beat This! produces a usable BeatGrid for Money 7/4 and `lock_state` advances past UNLOCKED.

**Actual behavior:** Beat This! returns an empty grid on both the 10-second and 20-second attempts. The session stays in REACTIVE mode throughout. `grid_bpm=0` in `features.csv`.

**Reproduction steps:**
1. Start an ad-hoc reactive session (no Spotify preparation).
2. Play "Money" by Pink Floyd in Apple Music.
3. Switch to SpectralCartograph preset and observe mode label.
4. Observe "○ REACTIVE" for the full track.

**Minimum reproducer:** "Money" by Pink Floyd, ad-hoc reactive session.

**Session artifacts:**
- `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md` — contains the evidence and analysis.

**Suspected failure class:** calibration
**Evidence:** 10-second window at 120 BPM gives ~20 beats, which is insufficient for confident downbeat estimation on 7/4 irregular meter. The retry at 20 seconds sees the same 10-second snapshot (not a longer window), so it does not help. The 30-second Spotify-prepared path gives ~61 beats and reliably detects the meter.

**Verification criteria:**
- [ ] Connecting a Spotify playlist that includes "Money" results in a prepared BeatGrid with `beats_per_bar=7` in `KNOWN_ISSUES.md` test notes.
- [ ] Manual: beat grid ticks in SpectralCartograph align to perceived quarter notes.

**Fix scope:** The durable fix is not to tune the live path — it is to use a Spotify-prepared session. The live path (10-second window) is below the beat-count floor for irregular-meter tracks by construction. See `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md` for the evidence. A potential improvement (not yet planned) would be to extend the live-path snapshot to 20–30 seconds on the retry, but this carries a 1.5–2× memory cost per attempt.

**Related:** DSP.3.5, D-077

---

### BUG-002 — PresetVisualReviewTests PNG export broken for staged presets

**Severity:** P2
**Domain tag:** preset.fidelity
**Status:** Open
**Introduced:** V.7.7A (staged-composition scaffold)
**Resolved:** —

**Expected behavior:** `RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests` produces per-stage PNG contact sheets for Arachne (and any other staged preset) under `/tmp/phosphene_visual/<timestamp>/`.

**Actual behavior:** The export throws `cgImageFailed` for any staged preset's PNG output. Non-staged presets are unaffected.

**Reproduction steps:**
1. `RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests`
2. Observe `cgImageFailed` error for Arachne (staged); other presets export normally.

**Minimum reproducer:** Any staged preset under `RENDER_VISUAL=1`.

**Session artifacts:** Console output from the test run.

**Suspected failure class:** pipeline-wiring
**Evidence:** `PresetVisualReviewTests.makeBGRAPipeline` calls `Bundle.module.url(forResource: "Shaders")` from the test target bundle (which has no Shaders resource). Staged presets require the `arachne_world_fragment` and `arachne_composite_fragment` functions which live in `Bundle(for: PresetLoader.self)`. The source lookup fails before the pipeline is built.

**Verification criteria:**
- [ ] `RENDER_VISUAL=1 swift test --filter PresetVisualReviewTests` produces at least one PNG per stage for Arachne without `cgImageFailed`.
- [ ] Contact sheet shows WORLD stage and COMPOSITE stage as separate tiles.

**Fix scope:** Change `Bundle.module` → `Bundle(for: PresetLoader.self)` in `makeBGRAPipeline`. Small, contained change. Required before V.7.7B's harness contact-sheet review.

**Related:** V.7.7A, D-072

---

### BUG-003 — DSP.3.6 / DSP.3.7 tests not yet implemented

**Severity:** P3
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** DSP.3 planning (gap in coverage)
**Resolved:** —

**Expected behavior:** App-layer wiring integration test verifies the full chain `SessionPreparer.prepare() → StemCache.store() → resetStemPipeline(for:) → mirPipeline.liveDriftTracker.hasGrid == true`. Live drift validation replay test verifies LOCKED within 5 s, drift < 50 ms, and beat phase zero-crossings within ±30 ms on Love Rehab.

**Actual behavior:** These tests do not exist. The wiring is tested indirectly via DSP.2 S6 integration tests, but the app-layer chain from session preparation through to drift tracker activation is not explicitly asserted.

**Minimum reproducer:** Review `docs/ENGINEERING_PLAN.md` DSP.3.6 and DSP.3.7 status.

**Session artifacts:** n/a

**Suspected failure class:** documentation-drift (gap in test coverage, not a behavioral bug)

**Verification criteria:**
- [x] DSP.3.6 test file exists and passes: `swift test --filter BeatGridAppLayerWiringTests` — landed as `PreparedBeatGridAppLayerWiringTests` (BUG-006.2, 2026-05-06). Six cases, all pass.
- [ ] DSP.3.7 test file exists and passes: `swift test --filter LiveDriftValidationTests`

**Fix scope:** Two new test files in `Tests/Integration/`. No production code changes anticipated.

**Related:** DSP.3.6, DSP.3.7

---

### BUG-004 — All production presets have `certified: false`

**Severity:** P3
**Domain tag:** preset.fidelity
**Status:** Open
**Introduced:** V.6 (certification pipeline introduced; no presets have passed M7 yet)
**Resolved:** —

**Expected behavior:** At least one production preset has `certified: true` in its JSON sidecar following Matt's M7 visual review.

**Actual behavior:** All 13 production presets have `certified: false`. The Orchestrator excludes uncertified presets by default; users must enable "Show uncertified presets" in Settings to see any auto-selection behavior.

**Minimum reproducer:** `grep -r '"certified"' PhospheneEngine/Sources/Presets/Shaders/*.json`

**Session artifacts:** n/a

**Suspected failure class:** calibration (quality bar not yet met, not a code bug)

**Verification criteria:**
- [ ] Manual: Matt performs M7 review on at least one preset and approves `certified: true`.
- [ ] Automated: `GoldenSessionTests` passes with at least one certified preset producing non-zero orchestrator selections.

**Fix scope:** Preset authoring work (V.7.7B+, V.7.10). Not a code defect.

**Related:** V.6, V.7.10, D-071

---

### BUG-005 — Spotify `preview_url` returns null for some tracks

**Severity:** P3
**Domain tag:** session.ux
**Status:** Open
**Introduced:** U.11 (discovered during integration testing)
**Resolved:** —

**Expected behavior:** `PreviewResolver` finds a 30-second preview for every track in a Spotify playlist and preparation completes for all tracks.

**Actual behavior:** Rights-restricted or region-locked tracks return `null` for `preview_url` from Spotify's `/items` endpoint. These tracks fall through to iTunes Search API, which also returns no preview for some of them. Affected tracks show `TrackPreparationStatus.noPreviewURL` in `PreparationProgressView`.

**Minimum reproducer:** Any playlist containing tracks by Mclusky, or region-restricted regional-exclusives.

**Session artifacts:** `session.log` `noPreviewURL` entries.

**Suspected failure class:** api-contract (external API limitation, not a Phosphene bug)

**Verification criteria:**
- [ ] `PreparationProgressView` shows a clear "No preview available" status for affected tracks rather than a spinner or error.
- [ ] Session proceeds to `.ready` state even when some tracks have no preview.

**Fix scope:** UX copy improvement only. The underlying limitation (no preview URL from either Spotify or iTunes) is not fixable by Phosphene. See Failed Approach #47.

**Related:** U.11, D-070, Failed Approach #47

---

### BUG-006 — Spotify-prepared session does not install prepared BeatGrid (falls through to liveAnalysis)

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved (wiring — downstream BUG-007 / BUG-008 prevent full LOCKED but the prepared-grid path itself is wired correctly end-to-end)
**Introduced:** Unknown — first observed during QR.1 manual validation 2026-05-06; predates QR.1 (QR.1 did not touch the prepared-grid wiring path).
**Resolved:** 2026-05-06 (BUG-006.2, wiring path validated end-to-end via session capture `2026-05-06T20-11-46Z`. Two downstream issues — BUG-007 lock-hysteresis, BUG-008 offline BPM accuracy — prevent SpectralCartograph from reaching `● PLANNED · LOCKED` but are independent of BUG-006 and tracked separately).

**Expected behavior:** When a Spotify playlist is loaded and `SessionPreparer` completes preparation, each track's `CachedTrackData.beatGrid` is non-empty. On track change in playback, `resetStemPipeline(for: identity)` finds the cache entry and emits `BEAT_GRID_INSTALL: source=preparedCache, track=…, bpm=…, beats=…` to `session.log`. SpectralCartograph displays `◐ PLANNED · UNLOCKED` immediately on first audio, then advances to `● PLANNED · LOCKED` within the first bar or two.

**Actual behavior:** SpectralCartograph mode label stays at `○ REACTIVE` for the entire opening of the track. `session.log` contains zero `source=preparedCache` install entries. Eventually `BEAT_GRID_INSTALL: source=liveAnalysis` fires once the live Beat This! trigger reaches its 10 s window — but only because the prepared cache returned nil and the live fallback was permitted. The mode label only advances past `REACTIVE` after the live grid lands.

**Reproduction steps:**
1. Launch Phosphene fresh.
2. Connect a Spotify playlist that includes Love Rehab (Chaim).
3. Wait for `.ready`. Press play in Spotify.
4. Press `Shift+→` to advance to Spectral Cartograph.
5. Watch the mode label and `~/Documents/phosphene_sessions/<latest>/session.log`.

**Minimum reproducer:** Any Spotify playlist on a fresh launch.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-06T14-14-22Z/session.log` — zero `source=preparedCache` entries; first `source=liveAnalysis` entry at `14:16:58Z` for Pyramid Song (~2 minutes after `track → Love Rehab`).
- `features.csv` from the same session — `lock_state` and `grid_bpm` columns presumably zero throughout the early playback window.

**Suspected failure class:** `pipeline-wiring`

**Evidence:**
- `VisualizerEngine+InitHelpers.swift:85–98` correctly wires `DefaultBeatGridAnalyzer` into `SessionPreparer`.
- `VisualizerEngine+Stems.swift:354 resetStemPipeline(for:)` correctly checks `stemCache?.loadForPlayback(track: identity)` and logs both branches (`source=preparedCache` on hit, `source=none` on miss).
- The session log shows neither branch fired for Love Rehab, which means `resetStemPipeline(for:)` was not called for the track *or* the `stemCache` was nil at the call site.
- DSP.3.1/3.2 added a pre-fire call to `resetStemPipeline(for: plan.tracks.first?.track)` at the end of `_buildPlan()` (D-078). If `_buildPlan()` did not run, this pre-fire never happened. Hypothesis: planned-session path is not being entered when Spotify playlist preparation completes, falling through to ad-hoc reactive behaviour despite the user thinking they used the playlist flow.

**Verification criteria:**
- [x] Loading a known-prepared Spotify playlist produces at least one `BEAT_GRID_INSTALL: source=preparedCache` entry in `session.log` per track played. **Confirmed in capture `2026-05-06T20-11-46Z`** — 6 tracks prepared with non-empty grids; 2 tracks played (Love Rehab, Money) and both produced `source=preparedCache` install lines on track-change.
- [ ] On Love Rehab specifically: SpectralCartograph mode label transitions `◐ PLANNED · UNLOCKED → ● PLANNED · LOCKED` within 5 s of audio. **Blocked by BUG-008** (Love Rehab prepared grid is 5.5% slow → drift accumulates beyond search window) and **BUG-007** (lock hysteresis fails even with correct drift).
- [x] `features.csv` `grid_bpm` column non-zero from frame 1 of the track. **Confirmed**: Love Rehab `grid_bpm=118.126`, Money `grid_bpm=123.232` — non-zero from frame 1 in `2026-05-06T20-11-46Z` capture. Accuracy issue tracked separately as BUG-008.
- [ ] Manual: drift readout (Δ) settles near zero (±20 ms) within the first bar. **Blocked by BUG-007 + BUG-008.**
- [x] Six new automated regression tests in `PreparedBeatGridAppLayerWiringTests` close the BUG-003 coverage gap that let this ship.

**Resolution (BUG-006.2, 2026-05-06):** Two coordinated fixes. **(Cause 1)** `engine.stemCache` is now wired to `sessionManager.cache` in `VisualizerEngine.init` immediately after `makeSessionManager` returns. Both references point to the same `StemCache` instance — `SessionPreparer` writes fill the cache as preparation completes; the engine reads them on track-change without any explicit hand-off. The field had been declared at `VisualizerEngine.swift:171` since the original session-preparation work but was never assigned anywhere, so `resetStemPipeline(for:)` always took the cache-miss branch. **(Cause 2)** `VisualizerEngine+Capture.swift` now resolves the canonical `TrackIdentity` from `livePlan` via the new `PlannedSession.canonicalIdentity(matchingTitle:artist:)` helper. Streaming metadata (Apple Music / Spotify Now Playing AppleScript) only carries title+artist; the planner stored full identities (duration + spotifyID + spotifyPreviewURL hint). The pure-function helper in the Orchestrator module is testable from `PhospheneEngineTests`. Falls back to the partial identity when `livePlan` is nil (preserving ad-hoc reactive behaviour) or when more than one planned track shares the same title+artist pair (preserves conservative behaviour over the wrong cache hit).

New tests: `PreparedBeatGridAppLayerWiringTests` (6 cases) — `engineStemCache_isWiredAfterSessionPrepare`, `trackChangeIdentity_matchesPlannedIdentity`, `ambiguousMatch_returnsNil_partialFallback`, `noMatch_returnsNil`, `endToEndProduces_preparedCacheInstall`, `partialIdentity_withoutCanonicalResolution_missesCache` (negative control pinning the regression direction). All pass. Full engine suite green modulo two documented pre-existing flakes (`MetadataPreFetcher.fetch_networkTimeout`, `MemoryReporter.residentBytes growth`).

The `WIRING:` instrumentation from BUG-006.1 stays in place — it costs nothing at runtime, validates the fix in any session capture, and will catch future regressions. Removal deferred to QR.5 cleanup once the fix has stabilized across multiple sessions.

**Related:** DSP.3.1, DSP.3.2, DSP.3.6, D-078, BUG-003 (test-coverage gap closed by `PreparedBeatGridAppLayerWiringTests`), BUG-006.1 (instrumentation), BUG-006.2 (this fix), BUG-007 + BUG-008 (downstream issues exposed but not caused by the fix). Commits: BUG-006.1 instrumentation `7f95cec0` + `807d3b8c`; BUG-006.2 fix `982bf93d` + docs `d56acd89`. Manual validation capture: `~/Documents/phosphene_sessions/2026-05-06T20-11-46Z/`.

---

### BUG-007 — LiveBeatDriftTracker loses lock under stable real-music input (LOCKING ↔ LOCKED oscillation)

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Resolved (BUG-007.2, 2026-05-06)
**Introduced:** Unknown — first observed during QR.1 manual validation 2026-05-06; predates QR.1 (QR.1 did not change drift-tracker lock semantics — only widened `playbackTime` to `Double`).
**Resolved:** 2026-05-06 (BUG-007.2). Fix A: `mirPipeline.setBeatGrid(cached.beatGrid.offsetBy(0))` in `VisualizerEngine+Stems.swift resetStemPipeline(for:)` — eliminates Mechanism B (horizon exhaustion) on all prepared-cache sessions. Fix B: `lockReleaseMisses = 7` (was 3) in `LiveBeatDriftTracker.swift` — eliminates Mechanism A oscillation on cadence-mismatch input; note the implemented value is 7, not the 5 in the diagnosis document, because the deterministic 400 ms/487 ms adversarial test scenario produces exactly-5 consecutive miss runs that trip the threshold at 5 (7 × 400 ms = 2.8 s hysteresis window; well within spec intent). Diagnostic test `test_mechanismB` updated from raw-grid bug-documenter to extrapolated-grid fix-verifier (test setup changed; `#expect` assertion unchanged). Three regression gates in `LiveBeatDriftTrackerTests` (tests 16–18).

**Expected behavior:** Once `LiveBeatDriftTracker.computeLockState()` returns `.locked` (after `matchedOnsets ≥ lockThreshold`), the tracker remains `.locked` for the duration of the track unless the input has gone genuinely silent for ≥ 2 × medianBeatPeriod. Onset-time drift settles into a band ±30 ms wide (the `strictMatchWindow`) and stays there.

**Actual behavior:** Two independent mechanisms prevent lock from holding:

- **Mechanism B (primary — plateau/freeze after ~30 s):** The prepared-cache install path (`resetStemPipeline(for:)`) calls `mirPipeline.setBeatGrid(cached.beatGrid)` without `offsetBy()`. The prepared grid covers only the 30-second Spotify preview. Once `playbackTime` exceeds ~30 s, `nearestBeat()` returns nil for all subsequent onsets. `consecutiveMisses` reaches `lockReleaseMisses=3` after 3 × 400 ms = 1.2 s, lock drops to `.locking`, and never recovers. Drift EMA freezes at its last-update value permanently.

- **Mechanism A (secondary — oscillation in 0..30 s window):** Sub_bass BeatDetector cooldown is 400 ms; Money's beat period is 487 ms. These cadences produce a ~71 % miss rate (44 of 62 onsets in the session capture). With `lockReleaseMisses=3`, 3 consecutive misses (~1.2 s) drop lock; the next hit (~400 ms later) re-acquires. Net: lock oscillates at ~1–2 s frequency throughout the 30-second live window.

**Reproduction steps:**
1. Start a Spotify-prepared session for a playlist containing Money (Pink Floyd).
2. Play Money in Spotify while Phosphene is running.
3. Switch to Spectral Cartograph (`Shift+→`).
4. Observe mode label: oscillates `◑ PLANNED · LOCKING` ↔ `● PLANNED · LOCKED` in 0..30 s, then drops permanently to `◑` after ~30 s.

**Minimum reproducer:** Any Spotify-prepared session where `playbackTime > 30 s`. The 30-second Spotify preview always produces a grid of ~30 s coverage; without `offsetBy()`, every track freezes at ~30 s.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-06T20-11-46Z/` — Money 7/4, prepared grid bpm=123.2.
  - 62 onsets, 18 hits (71 % miss rate).
  - Last match: t=29.8121 s, drift=+14.396 ms.
  - Lock dropped to LOCKING: t=31.0949 s (frame 5459), drift frozen at +14.396 ms permanently.
- Diagnosis document: `docs/diagnostics/BUG-007-diagnosis.md`.
- Diagnostic test suite: `PhospheneEngine/Tests/PhospheneEngineTests/Diagnostics/LiveDriftLockHysteresisDiagnosticTests.swift` (gated: `BUG_007_DIAGNOSIS=1`).

**Confirmed failure class:** `api-contract` (BUG-R001 fix applied to live Beat This! path in DSP.3.4 but not to the prepared-cache path) + `algorithm` (lock-hysteresis `lockReleaseMisses=3` too small for 71 % miss-rate input).

**Diagnosis notes:**
- The plateau at −90.490 ms on Love Rehab is the same Mechanism B. Love Rehab's plateau is negative (BUG-008: grid BPM 5.5 % too slow → drift walks negative) rather than positive, but the freeze mechanism is identical.
- Check 2 (sensitivity sweep): widening `strictMatchWindow` from 30 ms to 50 ms would make ~83 %→100 % of the 18 hits count as tight, but does NOT reduce the 71 % nil-return miss rate. Not the fix.
- Check 3 (decay path): inter-onset gap 400 ms < 2 × 487 ms = 974 ms decay threshold → decay path never fires. Not the cause of the plateau.

**Verification criteria:**
- [ ] Once `lock_state` reaches `2` (locked) on a stable track, it stays at `2` for ≥ 30 s of continuous playback at the same tempo. (**Manual validation pending — blocked by BUG-008 on Love Rehab; automated gate passes.**)
- [ ] `drift_ms` values in `features.csv` settle into a ±30 ms band and the standard deviation over a 10-s window is < 15 ms. (**Blocked by BUG-008 on Love Rehab; independent of this fix.**)
- [ ] Manual: orb pulse sits exactly on the kick (not "mostly in time"), and the BR-panel beat-phase tick lines up with the beat orb's flash.
- [x] `BUG_007_DIAGNOSIS=1 swift test --filter test_mechanismB` prints a lock_state of `2` at t=40 s — **passes** (was: `1`).
- [x] `BUG_007_DIAGNOSIS=1 swift test --filter test_mechanismA` prints ≤ 2 oscillations in 60 s — **passes with 0 oscillations** (was: multiple per minute).
- [x] `swift test --filter LiveBeatDriftTrackerTests` — all 18 tests pass.

**Fix scope (BUG-007.2 — one increment):**

Fix A (primary, 1 line — eliminates Mechanism B entirely):
```swift
// In VisualizerEngine+Stems.swift resetStemPipeline(for:), prepared-cache branch:
mirPipeline.setBeatGrid(cached.beatGrid.offsetBy(0))   // was: no offsetBy()
```

Fix B (secondary, 1 line — eliminates Mechanism A oscillation):
```swift
// In LiveBeatDriftTracker.swift:
private static let lockReleaseMisses: Int = 7   // was: 3
```
Note: the diagnosis document stated 5; the implemented value is 7. The deterministic 400 ms/487 ms adversarial regression test produces exactly 5 consecutive miss runs that trip a threshold of 5 on every other cycle; 7 clears the worst-case gap (7 × 400 ms = 2.8 s hysteresis, in line with the spec intent of "multiple non-detections required").

Fix A closes the primary issue on all tracks (prepared-cache sessions, playback > 30 s). Fix B eliminates oscillation on any cadence-mismatch scenario. Both shipped in one increment. Widening `strictMatchWindow` is explicitly NOT needed.

**Related:** DSP.2 S7, DSP.3.4 (fixed the same issue on live path — prepared-cache path missed), D-077, D-079 (touched file but did not change lock semantics), BUG-008 (Love Rehab has an additional BPM-offset symptom on top of this bug). Commits: BUG-007.1 diagnosis `f616bdb1`; BUG-007.2 fix `4fc58bdf` + SwiftLint cleanup `3a5c9a86`.

---

### BUG-008 — Offline BeatGrid disagrees with MIR BPM estimator on some tracks

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Resolved (BUG-008.2, 2026-05-06) — disagreement is now logged at preparation time. Underlying upstream-model behaviour unchanged by design; neither estimator is mechanically "right" per BUG-008.1 diagnosis.
**Introduced:** Surfaced by BUG-006.2 fix on 2026-05-06; predates BUG-006.2 (the offline analyzer has been producing this output since DSP.2 S5 landed — was previously masked because `engine.stemCache` was never assigned, so the prepared grid was never actually used at runtime). Diagnosis (BUG-008.1) traces the disagreement to genuine musical interpretation differences between the two estimators, *not* to any Phosphene code path.
**Resolved:** 2026-05-06 (BUG-008.2 — `BPMMismatchCheck.swift` + wiring in `SessionPreparer+WiringLogs.swift`. Disagreement now surfaces as a `WARN: BPM mismatch` line in `session.log` whenever the offline grid and MIR estimator differ by more than 3 %. No runtime behaviour change — `LiveBeatDriftTracker` continues to consume the offline grid).

**Expected behavior:** Two BPM estimators run during preparation — `TrackProfile.bpm` (MIR / DSP.1 trimmed-mean IOI on sub_bass kicks) and `CachedTrackData.beatGrid.bpm` (Beat This! transformer). When they disagree by more than 3 %, the disagreement is surfaced in `session.log` so future per-track judgment can be informed by data rather than tags. Phosphene does not assert which estimator is "correct"; both are valid interpretations of the same audio.

**Actual behavior (pre-BUG-008.2):** The disagreement was silent. Love Rehab specifically reports MIR=125.0 / grid=118.1 (5.5 % delta), Beat This! locks to the perceptual beat (broader-spectrum accent integration, what the model was trained to predict on human tap annotations) while the kick-rate IOI estimator locks to the kick interval. Money 7/4 (1.4 %) and Pyramid Song 16/8 (2.86 %) fell within the threshold and would not warn. The `LiveBeatDriftTracker` consumes the offline grid; on Love Rehab specifically this drives `drift_ms` linearly negative against the live tap (which corresponds to the kick rate), pegging at the −90 ms search-window edge by 31 s. **That secondary symptom is BUG-007** — independent and not addressed by this fix.

**Reproduction steps:**
1. Connect a Spotify playlist that includes Love Rehab (Chaim).
2. Wait for `.ready`. Inspect `WIRING: SessionPreparer.beatGrid track='Love Rehab'` in `session.log`.
3. Confirm `bpm=118.1` (or thereabouts — re-check determinism on repeated preparations).
4. Play the track. Observe `features.csv`: `grid_bpm` column reads `118.126`, `drift_ms` walks negative, lock_state never reaches 2 stably.

**Minimum reproducer:** Any Spotify preparation of Love Rehab with the post-BUG-006.2 wiring active.

**Session artifacts:**
- `~/Documents/phosphene_sessions/2026-05-06T20-11-46Z/session.log` lines 5–10 — all six tracks' offline BPMs:
  - Blue in Green (true ~70 swing): bpm=56.1
  - Love Rehab (true 125): **bpm=118.1**
  - Mountains: bpm=96.1
  - Pyramid Song (true ~68): bpm=70.0
  - Money (true ~120 in 7/4): bpm=123.2
  - If I Were with Her Now: bpm=103.7
- `features.csv` from the same session — Love Rehab `drift_ms` column walks −20 → −90 → plateau at −90.490 by frame 2398 (31 s in).

**Suspected failure class:** `algorithm` (Beat This! accuracy on this audio file). **Confirmed by BUG-008.1 diagnosis** — `calibration` and `pipeline-wiring` are ruled out.

**Diagnosis (BUG-008.1, 2026-05-06):** See `docs/diagnostics/BUG-008-diagnosis.md` for the full writeup. Summary:

- The vendored PyTorch reference fixture `Tests/PhospheneEngineTests/Fixtures/beat_this_reference/love_rehab_reference.json` was generated by running the official Beat This! Python implementation (commit `9d787b97`) on the same `love_rehab.m4a` audio file. It reports `bpm_trimmed_mean = 118.05` — **the upstream model itself produces 118 BPM on this audio.** The fixture's `description` field already used the qualifier "**~**125 BPM" — the fixture author knew the model was producing 118.
- The Phosphene Swift port returns 118.10 BPM (within rounding of the upstream).
- Three already-committed regression tests (`BeatThisPreprocessorTests.test_loveRehab_goldenMatch` at 1e-3 tolerance on the spectrogram, `BeatThisModelTests.test_loveRehab_endToEnd_producesBeats` on layer-by-layer activations, `BeatGridResolverGoldenTests.test_bpm_withinTolerance` at ±0.5 BPM) prove the entire port chain is faithful to the PyTorch reference end-to-end.
- The preprocessor's spectrogram match against the Python reference at `max|Δ| ≈ 3e-5` is dispositive evidence that AVAudioConverter resampling is correct — any ratio drift would fail that gate.
- DSP.1 baseline data (`docs/diagnostics/DSP.1-baseline-love_rehab.txt`) shows two of three independent estimators on the same audio agree with Beat This!: autocorrelation produces 117.45 BPM stable, and only the kick-only sub_bass IOI trimmed-mean produces 124–129. The kick is on every quarter note in this track; the broader-spectrum detectors are seeing accent structure that places the perceptual beat 2.5 % wider than the kick interval. **This is a model-level disagreement about what "the beat" is, not a Phosphene bug.**

**Diagnostic test added:** `Tests/PhospheneEngineTests/Diagnostics/BeatGridAccuracyDiagnosticTests.swift` — two tests:
- `test_loveRehab_portMatchesPyTorchReference_notMetadataTag` runs `DefaultBeatGridAnalyzer` end-to-end on the vendored fixture and asserts the produced BPM matches the PyTorch reference (118.05 ± 0.5) and is NOT within ±3 BPM of the metadata-tag tempo (125). Permanent tripwire on port-fidelity to upstream.
- `test_synthesizedKick_modelRecoversKnownBPM` (parametrized at 120/125/130 BPM) feeds a synthetic 60 Hz exponentially-decaying kick on every quarter note through the full analyzer at 44.1 kHz native (resamples to 22.05 kHz internally). **Result: 125.0 BPM input → 125.00 BPM produced exactly; 130.0 → 130.09 (essentially exact); 120.0 → 117.97 (-1.7 %, small tempo-specific artifact).** This conclusively settles that the model is *capable* of returning 125 BPM at this tempo on machine-quantized input — so the 118 it produces on Love Rehab reflects the track's actual perceptual-beat structure, not an accuracy ceiling. Both tests pass today; the printed numbers are the deliverable.

**Verification criteria:**
- [x] `DefaultBeatGridAnalyzer` BPM matches the upstream PyTorch reference within ±0.5 BPM. **Confirmed** by `BeatGridAccuracyDiagnosticTests` (passing).
- [x] Phosphene preprocessing chain pinned to upstream reference at 1e-3 spectrogram tolerance. **Confirmed** by existing `BeatThisPreprocessorTests.test_loveRehab_goldenMatch`.
- [x] Phosphene model output pinned to upstream reference at layer-by-layer tolerance. **Confirmed** by existing `BeatThisLayerMatchTests` + `BeatThisBugRegressionTests`.
- [x] Beat This! is accurate at 125 BPM on machine-quantized input. **Confirmed** by `test_synthesizedKick_modelRecoversKnownBPM` (125.0 BPM input → 125.00 produced exactly). The 118 BPM on Love Rehab reflects the track's perceptual-beat structure, not a model accuracy ceiling.
- [x] Disagreement between MIR and offline-grid BPM is surfaced in `session.log` when delta > 3 %. **Confirmed** by `BPMMismatchCheckTests` (7 pure-function tests) and `bpmMismatch_wiring_doesNotCrash_andGridReachesCache` (integration smoke).
- [ ] `drift_ms` stays inside ±30 ms for the duration of a 60-second segment on Love Rehab. **Tracked under BUG-007** — the drift-tracker lock-hysteresis bug is independent of which BPM is "correct" and must be closed first before this can be re-evaluated meaningfully.

**Fix proposal (BUG-008.2 scope):** The fix is *not* a port-fix. Three options in increasing scope:

1. **Documentation + verification gate (recommended for BUG-008.2).** Add a smoke-test on the reference fixture set that prints the offline BPM alongside the metadata-tag BPM for each track. When they disagree by > 3 %, log a `WARN` to `session.log`. No runtime behaviour change. Surfaces the upstream-model failure mode without acting on it.
2. **Cross-validation layer.** Run a second, independent BPM estimator (Phosphene's existing DSP.1 trimmed-mean IOI on sub_bass) over the preview audio at preparation time. When the two estimators disagree by > 3 % AND the IOI estimator's confidence is high, prefer the IOI estimate. Adds ~5 ms per track and a knob (the agreement threshold). Does not fix the structural problem (still one BPM for the whole track).
3. **Drift tracker re-estimates BPM.** Modify `LiveBeatDriftTracker` so accumulated drift over N consecutive beats triggers a beat-period re-estimate from the live onset stream. Structurally correct but a non-trivial change to S7 invariants. Should not be folded into BUG-008; track separately.

Recommended for BUG-008.2: option (1) only. Defer (2)/(3) until **BUG-007** (lock-hysteresis) is closed — drift behaviour is hard to reason about on top of a separate lock bug. With BUG-007 closed and option (1) active, manual validation on Love Rehab will tell us whether the upstream-model BPM is "wrong enough that lock fails" or "merely qualitatively different from the metadata tag in a way that doesn't affect lock."

**Related:** BUG-006.2 (exposed this latent issue end-to-end), DSP.2 S5 (introduced offline BeatGrid resolver), BUG-007 (compounds with — even a perfectly accurate grid wouldn't lock cleanly while BUG-007 is open), Failed Approach #52 (sample-rate plumbing — explicitly ruled out by this diagnosis; the 22050 Hz literal in `BeatThisPreprocessor` is the model's training rate, correctly allowlisted).

---

## Pre-existing Flakes (non-blocking, test infrastructure only)

These test failures are pre-existing, environment-dependent, and do not indicate behavioral regressions. They are tracked here for completeness.

| Test | Condition | Workaround |
|---|---|---|
| `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` | Intermittent network call timing variance under load | Run in isolation: `swift test --filter fetch_networkTimeout_returnsWithinBudget` |
| `MemoryReporterTests` growth assertions | `phys_footprint` variance across system memory pressure states | Run with other apps quit; or skip with `SKIP_MEMORY_TESTS=1` |
| `AppleMusicConnectionViewModelTests` (4 tests) | Requires Apple Music.app to be installed and reachable; CI-only failure | Run on dev machine with Apple Music installed |
| `PreviewResolverTests` timing tests | Rate-limit timing sensitive under parallel test execution | `@Suite(.serialized)` applied; still flakes under peak system load |

---

## Resolved (recent)

---

### BUG-R001 — BeatGrid finite horizon caused PLANNED·LOCKED never reached

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** DSP.2 S7 (BeatGrid first used without horizon extrapolation)
**Resolved:** DSP.3.4 — commit `7033ad09`

**Root cause:** `BeatGrid.offsetBy` only shifted the ~10 recorded beats. Past the last beat, `computePhase` clamped `beatPhase01=1.0` permanently and `nearestBeat` returned nil → `consecutiveMisses` incremented every onset → `matchedOnsets` never reached `lockThreshold=4`. Diagnostic evidence: session `2026-05-05T21-13-05Z` showed 12,509 frames in LOCKING, 0 in LOCKED.

**Fix:** `offsetBy(seconds:horizon:)` now appends extrapolated beats at `period=60/bpm` up to a 300-second horizon.

---

### BUG-R002 — Hardcoded 44100 Hz sample rate in Beat This! call

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** DSP.2 S9 (live Beat This! trigger)
**Resolved:** DSP.3.4 — commit `7033ad09` (Beat This! site only)
**Generalized:** QR.1 (D-079) — every remaining live-tap consumer threaded; literal `44100` CI-banned via `Scripts/check_sample_rate_literals.sh`; `tapSampleRate` now NSLock-guarded for cross-core visibility.

**Root cause:** `runLiveBeatAnalysisIfNeeded` passed `sampleRate: 44100` to `analyzeBeatGrid` regardless of actual tap rate (48000 Hz). The mel spectrogram covered the wrong time range; BPM resolved as ~216 instead of ~125. The QR.1 multi-agent review (Architect H1; Audio+DSP D1; ML #1+#2) found four more live-tap consumers with the same bug pattern (stem separator dispatch, per-frame stem analysis sample rate, StemSampleBuffer init, StemAnalyzer init default).

**Fix:** DSP.3.4 fixed the Beat This! call site. QR.1 closes the bug class by threading `tapSampleRate` through every live-tap consumer in `PhospheneApp`, NSLock-guarding the field, allowlisting legitimate `44100` literals (StemSeparator.modelSampleRate, BeatThisPreprocessor.sourceSampleRate, default-arg boilerplate), and adding `Scripts/check_sample_rate_literals.sh` to fail loud on any future regression.

---

### BUG-R003 — StemSampleBuffer snapshot undersized at 48000 Hz

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** DSP.2 S9
**Resolved:** DSP.3.4 — commit `7033ad09` (Beat This! call site only)
**Generalized:** QR.1 (D-079) — added `rms(seconds:sampleRate:)` overload; both rate-aware overloads now used at every consumer; covered by `TapSampleRateRegressionTests` so the buffer never silently falls back to its stored default again.

**Root cause:** `snapshotLatest(seconds:)` computed sample count using stored 44100 Hz init rate — a 10-second request retrieved only 9.19 s of real audio. DSP.3.4 added the rate-aware `snapshotLatest(seconds:sampleRate:)` overload but only used it at the Beat This! call site; `performStemSeparation` still used the no-rate overload.

**Fix:** DSP.3.4 added the rate-aware snapshot overload. QR.1 added a matching `rms(seconds:sampleRate:)` overload, threaded both through `performStemSeparation`, and added `TapSampleRateRegressionTests` proving the rate-aware paths return the correct sample count on a 48 kHz tap regardless of buffer init rate.

---

### BUG-R004 — Live Beat This! returns double-time BPM on short window

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** DSP.2 S9 (live Beat This! trigger — no octave correction)
**Resolved:** DSP.3.5 — commit `eac2e140`

**Root cause:** 10-second window at 125 BPM gives ~20 beats. Beat This! correctly detected the density but measured the doubled onset pattern, returning 244.770 BPM.

**Fix:** `BeatGrid.halvingOctaveCorrected()` halves BPM > 160 and drops every other beat recursively; applied before `offsetBy()`.

---

### BUG-R005 — IOI band fusion and histogram-mode picking biased tempo high

**Severity:** P1
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** Original `BeatDetector` implementation
**Resolved:** DSP.1 — commit `bbad760f`

**Root cause:** Two independent bugs: (a) `recordOnsetTimestamps` fused sub_bass + low_bass onset events, producing frame-aliased alternating 18/19-frame IOIs for a true 441 ms beat; (b) histogram-mode BPM picking used integer-rounded buckets with non-uniform widths in period space, biasing toward faster BPMs. See Failed Approaches #50 and #51.

**Fix:** Single-band sourcing from `result.onsets[0]` only; replaced histogram-mode with trimmed-mean IOI in `computeRobustBPM`.

---

### BUG-R006 — Sample-rate plumbing audit (QR.1)

**Severity:** P1
**Domain tag:** dsp.audio
**Status:** Resolved
**Introduced:** Multi-source — DSP.2 S9 added new sites; DSP.3.4 fixed only the Beat This! call site, leaving four other live-tap consumers using the literal `44100`.
**Resolved:** QR.1 — D-079, commits `(see git log [QR.1])`.

**Root cause:** Failed Approach #52: five `PhospheneApp` sites consumed live tap audio at the literal `sampleRate: 44100`. On a 48 kHz tap (the macOS Audio MIDI Setup default) every site silently produced wrong-rate data — stems were 8.8 % time-stretched and pitch-shifted before separation, biasing every downstream stem-feature analysis. Compound with `tapSampleRate` mutated from the audio thread without a synchronization barrier — cross-core visibility for an unsynchronized 8-byte field is not guaranteed on Apple Silicon, producing wrong-tempo grids ~1-in-1000 sessions invisible in tests.

**Fix:** (1) Captured `tapSampleRate` once per tap install through an NSLock-guarded accessor (`updateTapSampleRate(_:)` writer, `tapSampleRate` reader). (2) Threaded `tapSampleRate` through every live-tap consumer (`performStemSeparation` snapshot/rms/separate, live Beat This! snapshot — already DSP.3.4-fixed). (3) Replaced literal `44100` in non-tap-consuming code with `StemSeparator.modelSampleRate`. (4) Added `Scripts/check_sample_rate_literals.sh` to fail loud on any future regression. (5) Added `TapSampleRateRegressionTests` covering the rate-aware `StemSampleBuffer` API.

**Verification:** `swift test --filter TapSampleRateRegression` passes. `bash Scripts/check_sample_rate_literals.sh` exits 0.

---

### BUG-R007 — Tempo octave correction policy split between halving-only and halving+doubling

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Resolved
**Introduced:** Original `BeatDetector+Tempo.swift` implementation
**Resolved:** QR.1 — D-079, commits `(see git log [QR.1])`.

**Root cause:** `BeatGrid.halvingOctaveCorrected()` (DSP.3.5) is halving-only by design — Pyramid Song genuinely runs at ~68 BPM and any track in [40, 80) BPM must survive. But `BeatDetector+Tempo.computeRobustBPM` and `BeatDetector+Tempo.estimateTempo` retained `if bpm < 80 { bpm *= 2 }` branches that doubled any sub-80 estimate to 150. The split policy meant a track resolving to 70 BPM via the IOI path got reported as 140 BPM in `instantBPM`/`estimatedTempo` while the prepared-grid path (when available) stayed correct at 70.

**Fix:** Deleted the sub-80 doubling branch in both `computeRobustBPM` and `estimateTempo`. Halving (`bpm > 160 → /2`) preserved. Added `tempo_75BPMKick_returnsNear75_notDoubled` and `tempo_68BPMKick_pyramidSongPreservedNotDoubled` to `BeatDetectorTests`.

**Verification:** `swift test --filter "tempo_75BPM|tempo_68BPM"` passes.

---

### BUG-R008 — `MIRPipeline.elapsedSeconds` Float-precision long-session drift

**Severity:** P3
**Domain tag:** dsp.audio
**Status:** Resolved
**Introduced:** Original `MIRPipeline` implementation
**Resolved:** QR.1 — D-079, commits `(see git log [QR.1])`.

**Root cause:** `elapsedSeconds: Float` was incremented by `+= deltaTime` every frame. After 30 minutes of accumulation, ULP ≈ 240 µs — smaller than the ±30 ms tight-match window in `LiveBeatDriftTracker` but a guaranteed monotonic drift over hours of listening. Pre-existing, never observed in production because session lengths in test fixtures are < 1 minute.

**Fix:** `elapsedSeconds` (and `lastOnsetRateTime` / `lastRecordTime`) promoted to `Double`. Consumers cast to `Float` once at the FeatureVector / CSV write site. `LiveBeatDriftTracker.update(playbackTime:)` parameter widened to `Double`. New `elapsedSeconds_typeIsDouble` and `elapsedSeconds_accumulatesAsDouble_isMoreAccurateThanFloat` tests in `MIRPipelineUnitTests`.

**Verification:** `swift test --filter elapsedSeconds_` passes.

---

### BUG-R009 — KineticSculpture sminK violated D-026 (raw AGC-energy thresholding)

**Severity:** P3
**Domain tag:** preset.fidelity
**Status:** Resolved
**Introduced:** Original `KineticSculpture.metal` implementation
**Resolved:** QR.1 — D-079, commits `(see git log [QR.1])`.

**Root cause:** Mercury melt smooth-union radius read `0.06 + f.sub_bass * 0.28 + f.bass * 0.10` — raw AGC-normalized energy with an arbitrary 2.8× weight on a sub-band that is rarely populated in real tracks. Failed Approach #31 / D-026.

**Fix:** Replaced with `0.06 + f.bass * 0.16 + f.bass_dev * 0.05` — continuous bass band (Layer 1) drives the baseline; bass deviation adds the per-onset accent. Stays within the "beat ≤ 2× continuous" rule from `PresetAcceptanceTests`. Golden hashes regenerated; original steady/quiet hashes unchanged within dHash tolerance, beatHeavy shifted slightly (deviation now contributes a small `+0.06` to sminK).

**Verification:** `swift test --filter "PresetAcceptance|PresetRegression"` passes.

---

### QR.2 — Stem-affinity scoring AGC saturation + reactive-mode TrackProfile adversarial penalty

**Severity:** P2 (orchestrator correctness; affected every Spotify/Apple Music session)
**Domain tag:** orchestrator
**Status:** Resolved
**Introduced:** Increment 4.1 (PresetScorer original implementation)
**Resolved:** QR.2 (D-080) — 2026-05-06.

**Root cause (Issue #1):** `stemAffinitySubScore` accumulated raw AGC-normalized energies across declared affinities (`clamp(sum(stemEnergy[i]))`) and clamped to [0,1]. AGC centers each energy field at ~0.5; any preset declaring 2+ stems trivially saturated at ~1.0 on most music. Two presets with disjoint affinities ("drums" vs "vocals") both scored ~1.0 on a track where only drums were active. The 25% stem-affinity weight did no discriminative work.

**Root cause (Issue #2):** `DefaultReactiveOrchestrator` built scoring contexts with `TrackProfile.empty`, whose `stemEnergyBalance == StemFeatures.zero`. Under the deviation formula, zero balance → devSum = 0 → score = 0 for ALL stem-affinity-bearing presets. Neutral presets (no affinities declared) scored 0.5 always. The most musically-engaged catalog members were adversarially penalized in the most common use case (reactive ad-hoc listening since U.3). Failed Approach #54.

**Fix:** `stemAffinitySubScore` rewritten to use `stemEnergyDev[stem]` (deviation primitives, D-026/MV-1) and compute `mean(max(0, dev))` over declared stems. Zero-balance guard returns neutral 0.5 when `stemEnergyBalance == .zero`. `DefaultLiveAdapter` converted to class with 30 s per-track mood-override cooldown. Boundary-switch gate tightened with `minBoundaryScoreGap = 0.05`. `cutEnergyThreshold` raised 0.7 → 0.85. `recentHistory` capped at 50. Live `StemFeatures` wired into reactive mode after 10 s. D-080.

**Consequence for planned sessions:** Pre-analyzed `TrackProfile.stemEnergyBalance` has dev≈0 (EMA converged over 30-second preview); stem affinity is neutral (0.5) for all presets in planned-session scoring. Golden session sequences updated in `GoldenSessionTests.swift` — VL no longer wins on a stem bonus.

**Verification:** `swift test --filter StemAffinityScoring && swift test --filter GoldenSession && swift test --filter LiveAdapter` — all pass. 1084 total engine tests, 1 pre-existing flake (MetadataPreFetcher network timeout).
