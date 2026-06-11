# RB.1 — Plain-English Explanations: Every Failed Approach and Do-NOT Rule

**Date:** 2026-06-11 · **Purpose:** Matt decides which rules live or die. This document explains each one — what it is, why it exists, and what would happen if we removed it — so those decisions can be made with context. It contains no verdicts and no recommendations. Where I lack the context to explain honestly, I say so.

**Supersedes** the verdict tables in `RB1_RULEBOOK_AUDIT.md` as the decision instrument (the inventory and measurements there remain valid).

**How to read "if removed":** "removed" means deleted from CLAUDE.md. Git history always retains everything. Where the same content also exists in a handbook, a code comment, or an automated check, I say so — because in those cases removal from CLAUDE.md changes nothing about the actual protection.

**Honest context flags used below:**
- *(entry text only)* — the incident predates retained session history (before 2026-05-08) and isn't documented elsewhere in detail; everything I know is the entry itself.
- *(no founding incident)* — the rule reads as imported standard practice, not a learned failure; I found no record of Phosphene ever being burned by it.

---

## Failed Approaches

**FA #1 — IIR energy-difference beat detection.** *(entry text only)*
What: bans an early beat-detection technique (comparing energy through certain filters) that fired constantly on non-beats. Why: a failure from the Electron prototype era. If removed: nothing in the current app uses this technique — beat detection now runs a trained model (Beat This!) plus per-band spectral analysis. The only conceivable loss is a future session reinventing the technique during new beat work, which would fail loudly in listening tests.

**FA #2 — Rising-edge accumulation.** *(entry text only)*
What: bans a variation of the same dead technique (#1). Why: same era. If removed: same as #1 — the architecture this patched no longer exists.

**FA #3 — Per-bin spectral flux for beats.** *(entry text only)*
What: bans tuning per-frequency-bin thresholds for beat detection — untunable across genres. Why: same era. If removed: same as #1/#2.

**FA #4 — Beat-dominant visual design.**
What: the project's core design law — beat detections jitter by ±80 ms, so visuals driven primarily by beats feel out of sync; continuous loudness drives motion, beats are accents only. Why: learned in the Electron prototype, validated across every preset since. If removed from the FA list: nothing — the identical rule is the "Audio Data Hierarchy" section (the most-referenced design principle in the project) and is baked into every shipped preset. If *every* copy disappeared: new presets would risk drifting toward beat-driven motion, which your M7 reviews catch as "feels out of sync" at the cost of a wasted authoring round.

**FA #11 — MediaRemote private framework.** *(entry text only)*
What: a note that Apple's private "now playing" framework is blocked for normal apps on macOS 15+. Why: tried it; Apple blocks it. If removed: the code doesn't use it and comments at the relevant spots say why. Worst case, a future session re-tries it and wastes an hour rediscovering the block.

**FA #15 — Chroma from low FFT bins.** *(entry text only)*
What: a pitch-detection note — low-frequency analysis bins are too coarse for note/key accuracy. Why: a pre-history incident in mood-classification work. If removed: I genuinely lack the context to say whether this decision point still exists in the current mood pipeline; my code search was inconclusive. If mood/key work ever resumes, this might be re-learned at the cost of a debugging session.

**FA #16 — Raw chroma into the mood model.** *(entry text only)*
What: feeding raw note-strength numbers into the small mood model doesn't work; it needs pre-digested features. Why: same era as #15. If removed: same answer — relevant only if the mood model is ever retrained, and I can't verify the current pipeline shape from the record I have.

**FA #17 — The "autocorrelation half-tempo" story (amended).**
What: a long historical narrative about why early tempo detection got BPM wrong, including the corrected diagnosis. Why: documents the DSP.1 investigation. If removed: the actual fixes are in the code, the two specific lessons live separately as #50 and #51, and tempo now comes primarily from the ML model. This entry is at this point a history lesson; the architecture it critiques shipped and was superseded.

**FA #18 — Median tempo threshold.** *(entry text only)*
What: one line — taking the median of a mostly-zeros signal gives zero. Why: early tempo work. If removed: the current pipeline doesn't use this approach at all.

**FA #21 — Empty-array tap call gives silence.**
What: an Apple API gotcha — creating the system-audio tap with one particular "empty list" variant silently produces silence; the other variant is required. Why: discovered the hard way during audio-capture bring-up. If removed: the working call is in the code. The risk window is only a future rewrite of tap setup, where the failure mode is "no audio, no error" — genuinely nasty to debug. A one-line comment at the call site would preserve the protection entirely.

**FA #22 — Screen-capture permission required for audio.**
What: tap creation *succeeds* but delivers silent zeros unless screen-recording permission is granted; the app must request it. Why: cost real debugging time, and it affects you personally after every rebuild (permission resets). If removed: the code requests permission, RUNBOOK documents the troubleshooting, and my memory carries it too. The CLAUDE.md copy is the fourth copy.

**FA #23 — Don't deform architecture with audio.**
What: an aesthetic rule — buildings and fixed structures in 3D scenes shouldn't squash and stretch with the music; it reads as broken, not musical. Modulate light, atmosphere, camera instead. Why: early ray-march presets looked rubbery. If removed: also recorded as design decision D-020 and in the shader handbook. Note it has accumulated three "does NOT apply to" carve-outs (spider legs, surface vibration, color), which tells you it's a taste guideline that needed judgment anyway — and your M7 catches "looks broken" directly.

**FA #24 — Tint the ambient light, not just the key light.**
What: a rendering fact — indoor 3D scenes are mostly lit by ambient light, so changing only the direct light's color barely changes the image. Why: mood-color shifts looked broken. If removed: it's a one-render rediscovery with a minutes-long fix, and it's recorded as D-022 and handbook material.

**FA #25 — Mood values must take the dedicated path to the GPU.**
What: a plumbing trap — mood values visible in the debug overlay don't automatically reach the visuals; a specific call is required and another call must not overwrite them. Why: mood silently had no visual effect. If removed: the code now does this correctly, but no automated test guards it, so a refactor could silently regress it. The honest protection would be a small test; the prose only helps if someone happens to reread it at the right moment.

**FA #26 — Beat pulse from the loudest band, not just bass.**
What: keying beat flashes to bass alone misses songs whose beat lives in the snare; use the max across bands. Why: Love Shack didn't pulse. If removed: shipped presets already do this; for new presets your review catches "no pulse on this song" at the cost of one round.

**FA #27 — No synthetic audio in diagnostics.**
What: test and diagnostic harnesses must use real music — hand-made test signals don't behave like real music, so diagnostics pass while real problems persist. Why: it happened. If removed: this practice is now habit plus infrastructure (the replay harness runs real session data) and it's in my memory as one of your standing expectations. The realistic risk is a future convenience shortcut under time pressure. This is one of the few entries that names a live behavioral temptation rather than a dead technique.

**FA #28 — Video recorder locked to a transient window size.**
What: an AVAssetWriter gotcha — the window size is unstable at launch; locking the video file to the first observed size corrupts later frames; wait for the size to stabilize. Why: session recordings rendered into a corner of the frame. If removed: the fix is embodied in code with explicit counters; only a rewrite of that file re-risks it, and a comment there covers that.

**FA #29 — Sample-rate assumptions (user's audio settings).**
What: if the Mac's audio device runs at 96 kHz, the analysis math breaks; the user-facing fix is "set Audio MIDI Setup to 48 kHz"; the code-facing rule is "never assume." Why: real wrong-tempo bug. If removed: the code-level rule is enforced by an automated script that fails CI if a hardcoded rate appears, and the user-side note is in RUNBOOK. Nothing would be lost.

**FA #30 — Spotify volume normalization.**
What: Spotify's "Normalize volume" setting squashes the audio Phosphene analyzes; it should be off. Why: degraded analysis quality. If removed: it's a setup fact, recorded in RUNBOOK where setup facts live.

**FA #31 — No absolute thresholds on loudness (deviation primitives).**
What: the auto-gain system makes "absolute" loudness values mean different things on different songs and even different sections; visuals must respond to *deviation from the running average* instead. Why: six failed preset iterations hit this wall before it was diagnosed; it is the single most-referenced technical lesson in the project's history (it shaped the data the shaders receive). If removed from the FA list: the rule also exists as design decision D-026, a Do-NOT bullet, and a full chapter of the Milkdrop architecture doc — and the deviation fields physically exist in the data structures. If *every* copy disappeared: new presets would regress to absolute thresholds and feel inconsistent across songs, a failure that historically took multiple sessions to diagnose because it looks like a tuning problem, not a structural one.

**FA #32 — Feedback pass required for compounding motion.**
What: 3D presets re-rendered from scratch each frame can only show the instantaneous audio state — motion can't build on itself, so the result feels disconnected however clever the drivers are; the feedback/warp pass is the fix. Why: presets felt mechanical despite good audio routing. If removed: recorded as D-027, in the Milkdrop doc, and in the handbook with a named reference implementation. New-preset guidance — the handbook is where a preset session would meet it.

**FA #33 — Free-running oscillation.**
What: motion on a fixed timer (a sine of wall-clock time) ignores the music entirely and reads mechanical; lock cyclic motion to beat phase or gate it on loudness deviation. Why: Arachne v1's throb pulsed at its own rate regardless of the song. If removed: handbook craft material with carve-outs already (ambient drift is intentionally untethered). Your M7 catches the symptom ("ignores the music") at a round's cost.

**FA #39 — Never author without reference images.**
What: I have no visual feedback while writing shader code, so without anchoring to specific curated reference photos the output comes out primitive. Why: every pre-Phase-V preset iteration demonstrated it. If removed: honest answer — the rule already doesn't drive behavior reliably; measured compliance (reading the references before the first shader edit) is 35 %. What actually works is the infrastructure around it: curated reference folders, contact sheets, your M7. A session-start checklist or an automated nudge would do more than this prose ever has.

**FA #48 — Spec-faithful but reference-divergent.**
What: warns that following a written visual spec step-by-step can still produce output matching the named *anti-reference*, because the spec itself drifted from the reference images; mandates comparing rendered output against the actual reference images before review. Why: an Arachne M7 failure where exactly that happened. If removed: the spec-rewriting workflow this rule patched was abandoned shortly afterward (the V.8 pivot). The surviving practice — render and compare against references before review — is carried by the contact-sheet/replay infrastructure. Worth knowing: the same failure class recurred *with this rule loaded* (V.9 Session 4), so the prose demonstrably wasn't the protection. You've flagged this entry as doing more harm than good; the record is consistent with that — its main residue is a mandated ritual attached to a dead workflow.

**FA #49 — Structural gap vs. tuning gap.**
What: if every specified change landed mechanically and the output is still visually far from the references, the renderer is probably missing an entire layer (a background, refraction, depth blur) — and no amount of constant-tuning closes that. Why: an Arachne round where six tuning items landed perfectly and the result was still a flat bullseye. If removed: this is a judgment heuristic written as a stop-command. The underlying instinct — "ask whether the gap is structural before another round" — is useful. As an absolute it can stop legitimately convergent tuning (the Skein sheen took four rounds and converged). Historically, the actual escapes from tuning spirals came from desk research and your feedback, not from this rule firing.

**FA #50 — Don't fuse onset events across bass bands.**
What: a subtle tempo-detection bug class — combining beat events from two adjacent bass bands creates alternating timing artifacts that bias BPM estimates. Why: the DSP.1 diagnosis. If removed: fixed in code; tempo now primarily comes from the ML model anyway. I would only ever re-encounter this decision inside one specific function, where a code comment is the right protection.

**FA #51 — Histogram-mode BPM picking.**
What: sibling of #50 — a math bias in bucket-based BPM picking (buckets aren't uniform in time-space), replaced by robust averaging. Why: same investigation. If removed: same answer as #50.

**FA #52 — Hardcoded 44100.**
What: the code-layer version of #29 — the literal sample rate must never be hardcoded in live-audio paths. Why: stems came out time-stretched on 48 kHz systems. If removed: an automated script enforces this in CI. The script is the protection; the prose describes it.

**FA #53 — Stem-affinity scoring saturation.**
What: an orchestrator scoring bug — summing auto-gain-normalized stem values maxes out trivially, so preset selection silently ignored stem fit. Why: QR.2 diagnosis. If removed: fixed in code. This is a niche decision point inside one scoring function; a comment there covers refactors.

**FA #54 — Empty-profile scoring inversion.**
What: sibling of #53 — in ad-hoc listening mode, an empty track profile plus the affinity scorer actively *penalized* the most musical presets. Why: same investigation. If removed: same answer as #53.

**FA #55 — Duplicate SettingsStore.**
What: a SwiftUI trap — creating a second settings object inside a view silently disconnects user toggles from the app. Why: the capture-mode toggle silently did nothing. If removed: a dedicated automated regression test guards this, including an assertion on the source code itself. The test is the protection.

**FA #56 — Matching tracks by name.**
What: looking up the current track by comparing title+artist text breaks on covers, remasters, and odd characters; use the known index instead. Why: the playback chrome stuck on the wrong track. If removed: fixed in code plus an automated regression test. Same situation as #55.

**FA #57 — Spider trigger on an impossible signal combination.**
What: Arachne's spider was gated on two audio conditions that real music never produces at the same time, so it could never fire. Why: it never fired on the test track designed to trigger it. If removed: Arachne-specific; the corrected trigger is in code and the Arachne design doc carries the preset's operating rules. The general lesson ("spec triggers against signals music actually produces") is an instance of #31's understanding.

**FA #58 — A preset whose subject has no musical role can't be tuned into working.**
What: the Drift Motes lesson — the preset's main visual had no answer to "what musical moment does this respond to?", five remediation rounds each landed mechanically and changed nothing, and the right move was to kill the concept after the first negative review. Why: days of wasted iteration, ended by retiring the preset. If removed: the operating version ("articulate the musical role before authoring") lives in the Authoring Discipline section, the handbook's concept gate, and my memory. It also shaped how concepts get pitched to you now — and you enforce it at M7 regardless. The FA entry is the long-form history of how the rule was learned.

**FA #59 — Schema additions without a demonstrated consumer.**
What: don't add metadata fields until something demonstrably uses them (tags were added across 15 presets, then reverted within 24 hours when the consumer question got sharp). Why: the D-120 episode. If removed: this is generic engineering judgment, and the real protection was your product-level rejection of the premise. Low standing value as text.

**FA #60 — Batch-filed strategy decisions.**
What: twenty strategy decisions filed in one day; ten amended the same day, one reverted within 24 hours — the lesson being that strategy commitments without empirical input are forecasts, not decisions. Why: the Phase MD episode. If removed: strategy commitment is your domain — you control what gets committed, and the Phase MD entries already carry a "revisit" banner. The lesson also exists as the strategy clause in Authoring Discipline.

**FA #61 — Colored beams on a mirror surface.**
What: a rendering lesson — on a near-mirror surface, colored light must be painted into the *environment the mirror reflects*; aiming point lights at the surface produces invisibly weak results because of distance falloff. Why: the Ferrofluid stage-rig failure (shipped, failed M7 same day). If removed: a material-craft fact now written in the handbook cookbook. Rediscoverable in one bad render plus a search — the first discovery cost a full failed increment, the second time would cost far less because the handbook entry exists.

**FA #62 — Decoration layers without a musical role.**
What: the layer-level version of #58 — three detail layers were added because a prompt asked for them, none had a musical job, and one destroyed the preset's mirror-like identity. Why: a V.9 M7 failure ("no idea what the droplets are and why they are here"). If removed: same situation as #58 — the layer-scope question lives in Authoring Discipline, and your M7 is the enforcement that has actually worked.

**FA #63 — Read the reference README annotations, not just the images.**
What: the reference folders carry READMEs saying which traits of each image to trust and which to explicitly ignore; authoring from prompt text alone missed warnings that would have prevented two same-session failures (#61 and #62). Why: V.9 Session 4. If removed: same enforcement reality as #39 — compliance is weak with the rule present, so removal changes little. The READMEs themselves are the asset; getting them read is a workflow problem, not a prose problem.

**FA #64 — Desk research after repeated failed fixes.**
What: when two or more structural fixes have failed on a problem that has a name in the graphics literature, stop deriving from first principles and search for prior art. The ferrofluid "dot pattern" burned six guess-test-fail rounds; one published technique then fixed it in 30 minutes. Why: that episode, plus your direct instruction. If removed: this names a real, live tendency of mine — defaulting to deriving rather than searching. Of the judgment rules, this is one where the counterweight (this rule, or you saying "do desk research") has genuinely changed outcomes. It is also folded into the broader #73 lesson.

**FA #65 — Don't argue away components of a working reference.**
What: when adopting a working implementation, don't rationalize dropping its components without rendering proof ("X is redundant with Y" hand-waving) — the reference's character usually comes from all of its parts together. Why: the Leitl lighting-model episode, where I argued each of four components into the trash and you called it out. If removed: same family as #64 — it names a live tendency, and the tell-tale phrasing ("I think X is redundant with Y") is genuinely useful self-diagnosis. Also folded into #73.

**FA #66 — Test renders must use the live GPU path.**
What: test fixtures took a different rendering branch than the live app, so six tuning rounds "fixed" things in tests that the live app never executed; fixtures must exercise the exact dispatch path production uses. Why: Ferrofluid rounds 50–57 plus your live screenshots disagreeing with my green tests. If removed: partially embodied (the fixture helper now takes the path as a parameter; a regression test guards the related governor case), and recent work (Skein, FBS) builds live-path tests by default — the habit and infrastructure now carry it. Worth knowing: the failure recurred more than once *with this rule loaded*, so the prose alone was never the protection. The durable practical residue is one line: after two consecutive rounds of "test clean, live broken," check the test/production gap before touching the shader again.

**FA #67 — One audio signal per visual layer.**
What: routing the same audio timescale (e.g. per-beat) into two different visual layers makes the visual encode the same musical event twice and read as fighting itself; it took nine rounds to diagnose. Why: Ferrofluid's swell and spikes both pumping per-beat. If removed: a design-table practice recorded in the handbook and memory; your M7 catches the symptom ("competing rhythms") — which is exactly how it was found, at the cost of those rounds.

**FA #68 — Bass-note events are not beats.**
What: sub-bass onsets cluster tightly but *off-beat* on syncopated tracks, so they cannot correct beat timing — a tight cluster isn't an on-beat cluster, and a confidence gate based on tightness can't tell the difference. Why: a cold-start fix that made every previously-passing track worse (0/10) and was reverted same-day. If removed: the beat-sync capability registry documents this in full, and it only matters during beat-sync work, where that registry is the working document.

**FA #69 — Cold-start beat phase: the premise is dead.**
What: six different attempts to derive beat timing from the first seconds of live audio all failed, each differently; the premise itself ("some signal in the first ~3 s reliably gives the audible beat phase") is empirically falsified. Don't attempt a seventh without a fundamentally different premise and your sign-off. Why: weeks of work across CS.1 through BSAudit.3, ended by your Choice-A decision. If removed: this is the highest-cost-if-forgotten entry in the rulebook — the protection is against *me* proposing iteration #7 in good faith. It currently exists in four places (this entry, the Cold-Start contract section, a Do-NOT bullet, and the registry). One surviving copy at the place beat-sync work starts (the registry) preserves the protection; the other three are redundant.

**FA #70 — Port a reference's loop wholesale.**
What: porting a Milkdrop preset by patching differences one at a time produced an endless tail of new divergences; reading the actual source and replicating its render loop as a unit resolved everything quickly. Why: the Dragon Bloom L4 grind. If removed: the ports it informed are done and their specifics are recorded in the design decisions. Future ports would re-need the lesson — which is the parent rule #73's content.

**FA #71 — Color-space and clock audits when porting.**
What: two port gotchas — the destination engine re-encodes colors the source didn't (washed-out output), and time-driven effects behave differently if the clock runs at a different magnitude than where the reference was sampled. Why: Fata Morgana. If removed: handbook porting-checklist material; specific, rediscoverable, but each cost a real diagnosis round the first time.

**FA #72 — Swift naming inside shader code.**
What: shader code must use the snake_case field names; using the Swift camelCase names makes the shader silently fail to compile at runtime and the preset silently vanish from the catalog — the only signal is an indirect test failure. Why: Fata Morgana. If removed: the preset-count test catches the symptom (that's how it was found); a simple lint would catch it at the source. The prose mainly explains the confusing symptom.

**FA #73 — Don't rebuild what already exists.**
What: the parent lesson of #64/#65/#70 — given a working, code-available reference for the exact system being built (especially one you provided), read and port it before writing my own derivation; "I cited it in the design doc" is not using it. The Murmuration force-boids rebuilt a solved problem badly and burned an M7 round before you asked "how much have you used the references I provided?" Why: that episode. If removed: this names the single most persistent behavioral tendency of mine in the record — build rather than read. Honest counterpoint: the rule's children (#64, #70) were already loaded when Murmuration happened, so prose protection is demonstrably weak; what changed the outcome was your question. Whether a standing one-liner helps at the margin is exactly the kind of thing the removal experiment would measure.

---

## Do-NOT bullets (§What NOT To Do)

Many bullets restate an FA or a design decision. For those, the explanation is brief — removing a restatement costs nothing while the other copy (or its automated check) exists.

**DN-1 — Don't rebuild what exists.** Restates FA #73 above.

**DN-2 — Don't bend a ported reference out of its working regime.** A deepening of #73: a faithful port of a reference's *math* isn't a faithful port of its *system* — emergent behavior depends on the world the math runs in (boundaries, densities, parameters), and bending those to fit local constraints (a static frame, a perf cap) kills the emergence. Cost three Murmuration M7 rounds; resolved by retiring the emergent substrate entirely for a controlled one. If removed: the Murmuration design doc carries the full story; the shipped preset embodies the resolution. The general lesson would matter again only in a future "port an emergent system" project.

**DN-3 — Don't block the render loop on network/ML/metadata.** *(no founding incident)*
Standard realtime practice; the architecture is built async throughout. If removed: I'd follow it anyway; a violation shows up as visible stutter almost immediately.

**DN-4 — Don't allocate in the audio callback.** *(no founding incident)*
Standard realtime-audio practice — allocation in the audio thread risks glitches. Worth knowing: the June code audit found three violations in the codebase *with this bullet loaded* (BUG-036), so the bullet demonstrably doesn't prevent the mistake; the audit/review process is what caught it. If removed: same protection level as today, honestly.

**DN-5 — Don't use `.storageModeManaged` buffers.** *(no founding incident)*
A Metal buffer mode that's wrong for Apple Silicon. One greppable token; trivially lintable; embodied everywhere. If removed: a lint or review catches it; the failure would also show as a performance oddity.

**DN-6 — Don't make beat onset the primary driver.** Restates FA #4 / the Audio Data Hierarchy.

**DN-7 — Don't hardcode shader paths.** *(no founding incident)*
Presets are discovered at runtime; hardcoded paths would break packaging and hot-reload. Embodied in the loader design. If removed: low risk; the loader architecture itself makes this unnatural to do.

**DN-8 — Don't normalize the 6-band auto-gain per-band.** *(entry text only)*
Normalizing each frequency band separately would destroy the relative band information the whole audio hierarchy depends on. I lack the founding context — it predates retained history. If removed: only matters during auto-gain rework, which is rare and careful work anyway.

**DN-9 — Don't pass the warnings flag on the command line.**
A build-system fact: doing it the wrong way breaks the build immediately with a clear error, and the right way is already configured. Self-enforcing. If removed: the build error teaches the lesson in thirty seconds. (Also stated in §Build & Test.)

**DN-10 — Don't assume Now Playing metadata is available or accurate.** *(entry text only)*
The metadata fetchers are built with fallbacks already. If removed: embodied; would matter only in new connector work.

**DN-11 — Don't use `[[thread_index_in_mesh]]`.** *(no founding incident — likely a real compile error once)*
An MSL attribute that doesn't exist. Niche (mesh-shader work only); using it fails at shader compile. If removed: the compiler is the teacher; cost is minutes.

**DN-12 — Don't deform architecture geometry.** Restates FA #23 / D-020.

**DN-13 — Don't write mood values from the analysis path.** Restates FA #25's plumbing rule.

**DN-14 — Don't lock the video writer to the first size.** Restates FA #28.

**DN-15 — Don't key beat-pulse to a single band.** Restates FA #26.

**DN-16 — Don't iterate on cold-start beat phase.** Restates FA #69. One of four copies.

**DN-17 — Don't threshold absolute loudness values.** Restates FA #31 / D-026, with the recent refinement (each band deviates around its own average; mid/treble need bigger gains and have a warmup).

**DN-18 — Don't pivot deviation on a fixed 0.5.**
A subtle refinement of #31: deviation must be measured against each band's *own* running average, not the global 0.5 — getting this wrong left two of three bands structurally dead (BUG-027). Why: found and fixed June 6. If removed: a live-path automated test specifically guards the fix, including its warmup behavior. The test is the protection.

**DN-19 — Don't write ray-march presets without the feedback pass.** Restates FA #32 / D-027.

**DN-20 — Don't author without reading README + references.** Restates FA #39 + #63.

**DN-21 — Don't implement mirror-surface beams as point lights.** Restates FA #61.

**DN-22 — Don't add decoration layers without a musical role.** Restates FA #62.

**DN-23 — Don't assume fixtures match the live render path.** Restates FA #66.

**DN-24 — Don't route one timescale into two layers.** Restates FA #67.

**DN-25 — Don't ship a hero surface with fewer than 4 octaves of noise.**
A visual-richness floor from the shader handbook (§12.1), where it is mandatory and where the fidelity review checks it. If removed from CLAUDE.md: the handbook copy and your M7 are the actual enforcement.

**DN-26 — Don't ship fewer than 3 distinct materials.** Same situation as DN-25.

**DN-27 — Don't skip the coarse-to-fine workflow.**
The handbook's authoring workflow (§2.2) — single-pass shaders that try to do everything at once are untunable. Duplicate of the handbook's own rule.

**DN-28 — No full-screen errors during playback.**
A UX rule; canonical in the UX spec (§9.4) with the full error taxonomy. Duplicate.

**DN-29 — No transport controls for streaming sessions.**
A UX honesty rule (Phosphene doesn't control Spotify, so showing pause/skip would lie), with the local-files exception where the controls are honest. Canonical in the UX spec. Duplicate.

**DN-30 — No jargon in user-facing strings.**
A UX copy rule; canonical in the UX spec (§9.5); the string-externalization script covers the related mechanical check. Duplicate.

**DN-31 — Don't bypass the certification rubric.**
Process rule: certification requires your approval; no automated metric substitutes. You are the gate — this bullet describes the gate rather than being it. Canonical in the handbook.

**DN-32 — Don't ship pale-dominant panels.**
The palette rule with its history (the cream-rescission): pale tones are allowed as highlights, forbidden as the dominant ground, with a mechanical 30 % ceiling. Why: the rejected pale Lumen Mosaic output. If removed: the ceiling is enforced by per-preset certification gates for certified presets, and the handbook carries the authoring guidance. The bullet is the longest in the list and is mostly history.

**DN-33 — Don't use high smoothstep thresholds on fbm8.**
A shader-math fact: the noise function's actual output range is roughly ±0.7, so thresholds above 0.3 silently produce zero variation. Why: cost silent "flat output" bugs (the moved FA #42/#43). If removed: documented in handbook §13; it's a lookup fact a session meets when using that function.

**DN-34 — Don't sample fbm8 at scale 1.0 on unit geometry.** Sibling fact of DN-33; same situation.

**DN-35 — Don't shadow Metal type names.**
Naming a variable `half` (a Metal type) silently kills the shader and the preset vanishes with no error — one of the nastiest silent failures in the stack (the moved FA #44). If removed: the preset-count test catches the symptom; a lint could catch the cause. The prose mainly explains the bewildering symptom to whoever hits it.

**DN-36/37/38 — Spotify API gotchas (schema renames, the `fields` param, discarding `preview_url`).**
Three facts about Spotify's API learned while building the connector (the moved FA #45/46/47). The connector is built and working; the facts are canonical in RUNBOOK's connector section. Duplicates — they'd matter again only in connector rework, where RUNBOOK is the working doc.

**DN-39 — Don't fuse onsets across bands.** Restates FA #50.

**DN-40 — Don't re-introduce histogram BPM picking.** Restates FA #51.

**DN-41 — Don't write the literal 44100.** Restates FA #52; the CI script is the enforcement.

**DN-42 — Don't mutate the tap sample rate from the audio thread.**
A thread-safety rule: capture the rate once per tap install; mutating it cross-thread risks a roughly 1-in-1000-sessions wrong-tempo bug invisible to tests. Why: found in the QR.1 review. If removed: the capture-once pattern is embodied in code; only a rewrite of tap install re-risks it; a comment there covers it.

**DN-43 — Don't double sub-80 BPM.**
Some songs genuinely run below 80 BPM (Pyramid Song ~68), so "doubling slow tempos" corrupts them; the correction function is deliberately halving-only. If removed: embodied in code; the comment at that function is the natural protection.

**DN-44 — Don't store the pipeline clock as Float.**
A precision fact: a Float accumulator drifts measurably over a long session. Fixed — the code is Double. If removed: only a refactor re-risks it; nothing currently guards it but the blast radius is subtle drift, not breakage.

**DN-45 — Don't sum normalized stems for scoring.** Restates FA #53.

**DN-46 — Don't score reactive tracks against an empty profile.** Restates FA #54.

**DN-47 — Don't call the live-update path without a cooldown.**
An orchestrator rate-limit: the mood-override path runs ~94 times a second; without a per-track cooldown it would re-patch the plan every frame. The 30-second cooldown is in the code. If removed: embodied; matters only in live-adaptation rework.

**DN-48 — Don't instantiate a second SettingsStore.** Restates FA #55; the regression test is the enforcement.

**DN-49 — Don't match plan entries by name.** Restates FA #56; the regression test is the enforcement.

**DN-50 — Published values must be written-or-cleared on every path.**
An app-layer trap: a published value (like album art) written on one code path but never cleared on the parallel path leaks stale data across modes — the previous session's album art rendered against every streaming track (BUG-024). Why: it happened, June 1. If removed: this is a genuine recurring pattern with no automated guard — it would likely happen again eventually with some new published surface, caught in a live session at the cost of a bug-fix round. One of the few bullets naming a live, ungated decision point.

**DN-51 — Don't silently skip tests on missing fixtures.**
A silent skip once made an entire four-bug regression surface invisible on fresh checkouts. Why: that incident. If removed: a fixture-presence gate now enforces the known case; the general habit (fail loudly) is review-level judgment.

**DN-52 — Don't touch Arachne without its design doc.**
A pointer (the eleven Arachne-specific rules already moved to the design doc). If removed: an Arachne session might start without reading the doc — a reading-list problem; the doc itself is intact.

**DN-53 — Don't bind other things at the reserved GPU slots.**
A GPU contract fact: two binding slots are reserved for per-preset state; binding anything else there breaks presets that depend on them. If removed: embodied in the setter API design; the GPU-contract documentation is the natural home. (Note: the bullet's text is slightly stale — it says "extend with buffer3/4" as a future action, but buffer3 already exists.)

**DN-54 — Don't transition completion-gated presets on timers.**
An orchestrator contract: presets that ask to finish their build cycle (currently only Arachne) must not be cut off by duration timers; the wiring honoring this exists (BUG-011's fix). If removed: embodied; the risk is a future new transition path ignoring the flag — a comment at the transition logic covers that.

**DN-55 — Don't parameterize the particle engine for new presets.**
An architecture rule (D-097): each particle preset ships its own engine ("siblings, not subclasses") rather than adding flags to a shared one. If removed: it's a design-decision record and matters only when the next particle preset is scoped — a design-review-time question, not an always-loaded one.

**DN-56 — Don't throttle a flock by dropping members.**
The performance governor may reduce *quality* per element but never freeze a subset of a coupled system — freezing flock members left a frozen oval on screen (an M7 failure). Why: Murmuration round 6. If removed: a dedicated regression test guards it. The test is the protection.

**DN-57 — Don't extend shared GPU structs without verification.**
Extending the shared data structures shaders read requires keeping existing field positions and re-verifying every preset's output hash. Why: D-099's extension was done safely and the rule records how. If removed: a layout test plus the golden-hash suite catch violations mechanically.

**DN-58 (embedded) — Durable learnings go in docs, not chat.**
Process contract: anything a future session needs must be written somewhere persistent. If removed: the failure mode is slow knowledge loss — invisible per-session, costly over months. This is a working agreement, not a failure rule.

**DN-59 (embedded) — Never push without explicit approval.**
Your release-control contract. If removed: risk of an unwanted push to a public repo. This is the hardest contract in the file.

**DN-60 (embedded) — Evidence before fixing P0/P1/P2 defects.**
Process contract from the defect protocol: document expected/actual/repro/artifacts before changing code. If removed: regression to fix-first-diagnose-later, which the protocol exists to prevent.

**DN-61 (embedded) — No fix code in a diagnosis increment.**
Sibling of DN-60; keeps diagnosis honest. Same situation.

**DN-62 (embedded) — Cold-start ban (Cold-Start Contract section).** Duplicate of DN-16/FA #69 — the third of four copies.

**DN-63 (embedded) — SettingsStore rule (UX Contract section).** Duplicate of DN-48/FA #55 — also covered by the regression test.

---

## Summary observations (context, not verdicts)

- **Restatements:** 24 of the 57 §What-NOT bullets restate an FA or design decision that exists elsewhere in the same file — they are literal duplicates within CLAUDE.md itself. FA #69's ban exists in four places.
- **Already enforced by automation:** ~14 entries (FA #29/52/55/56, DN-18/32/41/48/49/56/57, partially #25/35/72) are covered by existing scripts or regression tests; for these, the prose describes a protection that exists independently of it.
- **Embodied in shipped code:** ~20 entries describe mistakes whose fixes are in the code, where the realistic re-risk is a future rewrite of that specific file — the kind of protection a code comment provides.
- **Canonical elsewhere:** ~15 entries duplicate handbook (SHADER_CRAFT), RUNBOOK, or UX_SPEC text that those documents own.
- **Context I don't have:** FA #1, #2, #3, #11, #15, #16, #18 and the origins of DN-3/4/5/7/8/10/11 — pre-history or no recorded founding incident.
- **Live, ungated decision points** (the entries where removal most plausibly changes a future outcome, by my honest read): FA #27 (synthetic audio temptation), FA #31 (the deviation-primitives understanding, if *all* copies vanished), FA #64/#65/#73 (the read-the-reference cluster — though the record shows prose alone was weak protection even here), FA #69 (one copy needed where beat-sync work starts), DN-50 (the published-value leak pattern), DN-58–61 (working agreements with you).
- **Entries whose own record suggests net harm or no effect:** FA #48 (ritual attached to an abandoned workflow; failure recurred with it loaded), FA #39/#63 (35 % measured compliance), DN-4 (violated three times while loaded), FA #49 as written (a stop-command where a prompt-to-consider was meant).
