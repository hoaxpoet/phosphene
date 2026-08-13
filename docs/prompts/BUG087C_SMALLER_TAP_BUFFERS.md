# Increment BUG087.4 — smaller tap buffers, so local-file analysis reaches ≥ 40 Hz

**Type:** fix (engine audio path; no preset, no shader, no sidecar)
**Defect:** BUG-087, open. Read its `KNOWN_ISSUES.md` entry first — in particular the
**"Fix attempted — PARTIAL, and the remedy was wrong"** section, which is the input to this
increment and must not be re-derived.

**Objective.** After this session, a local-file session's **measured** analysis rate is
**≥ 40 Hz** (from `Scripts/measure_analysis_rate.py` on a real capture), or the session has
established with evidence that no available AVAudioEngine mechanism delivers it and has said
so plainly. BUG-087 closes either way — resolved, or re-scoped to a documented ceiling.

---

## 1. What is already known, and must not be re-litigated

BUG087.2 and BUG087.3 landed (`49f7d2e4`). Local-file analysis went **10.0 → 16.4 Hz**, short
of the ≥ 40 Hz target, and the measurement explains why:

> **The ceiling is how often audio ARRIVES, not how finely it is sliced.** AVAudioEngine hands
> this path ~0.1 s buffers. All five slices of one buffer complete within microseconds — they
> process already-buffered audio — so the render loop samples ~1.6 of them as distinct values
> and supersedes the rest. Gap distribution between value changes is bimodal: **39 % one render
> frame apart, 55 % five to six frames apart.**

**Three things are therefore settled and are NOT this increment's work:**

1. **Slicing further cannot help.** More slices land in the same instant. `TapBufferSlicing`
   stays as-is.
2. **`installTap(bufferSize:)` is ignored.** BUG087.1 measured it: 4414 frames at 44.1 kHz and
   4808 at 48 kHz, both exactly 0.1 s — a fixed *duration*, so the request is discarded rather
   than rounded. Do not "try a smaller number".
3. **The analysis time base is already correct.** BUG087.2 derives `dt` from
   `frames / rate`, so any mechanism that changes buffer size is safe for the seconds-based
   followers without further work.

**This increment's whole question: can AVAudioEngine be made to deliver smaller buffers?**

---

## 2. Skill invocations

- **`defect-handling`** — at session start, before any code change. BUG-* work.
- **`closeout`** — at the end.
- Not `preset-session` / `shader-authoring` — no preset surface is touched.

---

## 3. Read first

1. `docs/QUALITY/KNOWN_ISSUES.md` → **BUG-087**, especially the partial-fix section.
2. `PhospheneEngine/Sources/Audio/LocalFilePlaybackProvider.swift` — the `installTap` site,
   `deliverSliced`, `handleTapBuffer`, and the AVAudioEngine graph in `start()`.
3. `PhospheneEngine/Sources/Audio/TapBufferSlicing.swift` — header only; it is not changing.
4. `Scripts/measure_analysis_rate.py` — header. **This is the done-when instrument.**
5. `PhospheneApp/VisualizerEngine+Audio.swift` — `makeAudioSampleCallback` and
   `processAnalysisFrame`, to see what a smaller buffer costs per callback.

---

## 4. Pre-flight invariants

Each failed check stops the session before task 1.

1. Fresh branch off current `origin/main`: `claude/bug087c-tap-buffers`. Tree clean.
2. Full suite green at the branch point (engine + app + `swiftlint --strict`). Red → report
   and stop; **note that the three GPU timing tests flake under the loaded parallel suite —
   re-run any failure in isolation before calling it red** (`KNOWN_ISSUES.md` names the class).
3. `python3 Scripts/measure_analysis_rate.py` reproduces the current state: local rows ≈ 16 Hz
   / ≈ 60 ms, streaming ≈ 51 Hz / ≈ 20 ms. **If local already reads ≥ 40 Hz, stop — something
   else changed and this increment's premise is gone.**
4. No `PhospheneApp` process running (`pgrep -fl "MacOS/PhospheneApp"` empty) — a live app
   blocks the XCTest host (BUG-072) and the app suite is a gate here.

---

## 5. Tasks

### Task 1 — Survey the mechanisms, on evidence, before writing any code

Establish which of these can actually deliver sub-25 ms buffers on the **playback** path
(audio must still reach the output device — this is a user-facing playback provider, not an
offline renderer):

- **`kAudioUnitProperty_MaximumFramesPerSlice` / `AUAudioUnit.maximumFramesPerSlice`** on the
  player or mixer node.
- **Tapping a different node** — the tap currently sits on the player node pre-mixer; the
  mixer or engine output node may have a different render quantum.
- **`AVAudioEngine.enableManualRenderingMode(_:format:maximumFrameCount:)`** — gives explicit
  frame-count control, but takes the engine off automatic device output. **Establish whether
  playback still reaches the speakers under it**; if not, say so and rule it out rather than
  building toward it.
- **`AVAudioSinkNode`** as an alternative capture point.

**Done when:** a short written verdict per mechanism — *can it deliver < 25 ms buffers while
audio still plays?* — each backed by a doc reference or a throwaway experiment, not by
reasoning alone. A mechanism ruled out on a plausible-sounding argument with no evidence is
exactly what this increment exists to avoid; four hypotheses were refuted by measurement
during BUG-086 and two more during BUG-087.

### Task 2 — HARD STOP if no mechanism survives task 1

If nothing can deliver smaller buffers while playing: **stop and report.** Do not build a
consumer-side workaround on your own initiative (see DECISION-NEEDED #1). Write the verdicts,
the evidence, and update BUG-087 to a documented ceiling rather than an open target.

Otherwise state "task 2 gate passed — mechanism X survives" and continue.

### Task 3 — Implement the surviving mechanism

Smallest change that delivers it. Constraints:

- **Audio must still play.** A change that fixes the analysis rate and breaks playback is not
  a fix; verify by ear, not by test.
- **Real-time safety.** No per-callback allocation beyond what exists (BUG-036). Smaller
  buffers mean *more* callbacks — check that per-callback cost does not rise with the count.
- **Do not touch the streaming path.** The system tap already runs at ~51 Hz and is correct.
- Keep `TapBufferSlicing` — it is harmless with smaller buffers (one slice per buffer) and
  still correct if a large buffer ever arrives.

**Done when:** the `TAP_BUFFER:` line in a fresh capture reports a delivered size under
~25 ms, and the full suite is green.

### Task 4 — Measure it, on a real capture

**The done-when is a measured effective rate, never a derived one.** Matt records one
local-file session on the built branch; then:

```
python3 Scripts/measure_analysis_rate.py ~/Documents/phosphene_sessions/<newest>
```

**Done when:** the local row reads **≥ 40 Hz** and **≤ 25 ms**.

⚠ **This is the increment's load-bearing check and the reason it exists in this form.**
BUG087.3 shipped a regression test asserting `hz >= 40` computed from slice count. It
**passed** while the live capture measured 16.4 Hz, because it was measuring the computation
rate and calling it the delivered rate. That is the third instance of the same failure in a
week — with BUG086.1's "2.5 s nominal" (measurement corrected it to 3.0 s once inference was
counted as latency, not just duty) and a false PASS from a too-permissive correlation floor.
**An automated gate that cannot see the quantity it is named for will certify a claim the
artifact refutes.** Any test written here asserts arithmetic and says so in its name; the rate
claim comes from a capture or it is not made.

### Task 5 — Fix-increment doc obligations

`KNOWN_ISSUES.md` (BUG-087 → Resolved + hash, or the documented ceiling), `RELEASE_NOTES_DEV.md`,
`ENGINEERING_PLAN.md`, and **the capability-registry row**, which currently tells preset authors
to assume ~16 Hz / ~60 ms steps on the local-file path. Leaving that stale is the drift failure
D-120 demonstrated twice.

### Task 6 — Closeout

---

## 6. Do NOT

- **No further slicing.** Settled by measurement; more slices land in the same instant.
- **Do not retry `installTap(bufferSize:)` with a different number.** Measured dead end.
- **Do not pace, sleep, or throttle** in the audio callback — it blocks the render thread.
- **Do not build the consumer-side spreading design** (buffering analysis frames and releasing
  one per render frame) without Matt's answer to DECISION-NEEDED #1 — it *adds* latency, which
  is the opposite of what BUG-086 just spent four increments reducing.
- **Do not assert the delivered rate from a derived quantity.** See task 4.
- **Do not re-tune any smoothing constant** to compensate for the new rate. Seconds-based
  followers are rate-invariant by construction (DYN.4/DYN.5); if one is not, that is a finding
  to report, not to absorb. Tuning to chase a rate change is the D-102 / FA #58 spiral.
- No push without Matt's explicit approval; then branch + PR, never direct to `main`.

---

## 7. Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test 2>&1
python3 Scripts/measure_analysis_rate.py ~/Documents/phosphene_sessions/<fresh-capture>
```

**Manual validation is required and cannot be waived.** Two things, both by ear/eye:
audio still plays correctly (no dropouts, no glitching — smaller buffers raise callback
frequency and this is the risk), and the felt result on a stem-driven preset. Use **Skein** or
**Glaze** — verified via `Scripts/check_route_liveness.py` as the densest live stem consumers.
**Do not aim this at Aurora Veil**: it declares no stem route at all (BUG-088), which is how a
review got spent on it once already.

---

## 8. Commit message templates

```
[BUG087.4] Audio: <mechanism> delivers NN ms tap buffers on the playback path
[BUG087.4] Defects: BUG-087 resolved — local-file analysis at NN Hz (fill measured)
[BUG087.4] Docs: registry, EP and release notes for the analysis-rate fix
```

---

## 9. Closeout format

Invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.
Additionally: the task-1 per-mechanism verdict table, the task-2 gate statement,
`measure_analysis_rate.py` **before and after** on real captures, and the manual
playback-integrity result. If the rate target was not reached, say so in the headline rather
than in a footnote.

---

## 10. DECISION-NEEDED

**#1 — If no AVAudioEngine mechanism can deliver smaller buffers, do you want the
consumer-side workaround?**

The fallback is to hold each burst of analysis frames and release one per render frame,
spreading them over time instead of collapsing them into one instant.

- **A — No; accept ~16 Hz and document the ceiling.** *(Recommended.)* The workaround buys
  smoother-looking motion by **adding up to ~80 ms of latency** — the opposite of what BUG-086
  spent four increments removing, and it invents no new information: the same values arrive,
  just later and more evenly. ~60 ms steps are already under 1 % of an 8 s plot's width.
- **B — Yes, build it.** Worth it only if you can see the stepping. If a preset visibly
  stutters at 16 Hz, say which and that changes the answer.

**Default if no reply: A.** Trading latency for evenness is a bad deal on a system whose
stated goal is feeling locked to the music, and no preset has been reported as visibly
stepping.
