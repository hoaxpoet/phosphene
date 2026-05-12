# Session prompt — Increment MD.1 (`.milk` grammar audit)

This file is the session prompt for running Increment MD.1. Paste the
fenced block below into a new Claude Code session. Do not include this
surrounding meta-text. The work is a doc-authoring session that
produces `docs/MILKDROP_GRAMMAR.md` — the empirical grammar audit that
unblocks MD.2 (transpiler CLI skeleton).

Pre-session human prerequisites:

1. The `projectM-visualizer/presets-cream-of-the-crop` GitHub repo is
   cloned to a known location on disk, OR the session is permitted to
   clone in-session (the prompt allows either). Note the absolute path.
2. The strategy-doc + audit + Decisions D-103 through D-112 must be
   in tree. Verify with: `git log --oneline docs/MILKDROP_STRATEGY.md
   docs/DECISIONS.md | head`. The prompt is written against the
   post-sign-off state.
3. Counsel review for D-111 may or may not have concluded. MD.1
   commits no licensed content (it cites the pack as a corpus, not as
   committed content), so it can run regardless.

---

```
Context: Increment MD.1 is the first runnable Phase MD work item. The
strategy (`docs/MILKDROP_STRATEGY.md`) and ten Phase MD decisions
(D-103 through D-112 in `docs/DECISIONS.md`) are signed off. MD.1's
scope is tightened per D-110 to focus on the `.milk` *expression
sub-languages* — HLSL embedded pixel-shader source is out of
transpiler scope and gets an appendix only.

This session produces `docs/MILKDROP_GRAMMAR.md` — the empirical
grammar audit that unblocks MD.2 (transpiler CLI skeleton). The doc
enumerates every variable / operator / function used in the
expression sub-languages of the cream-of-the-crop pack, with frequency
counts, and proposes Phosphene-side Metal equivalents for each.
Coverage is reported separately for the full 9,795-preset pack AND
for the 1,559-preset HLSL-free subset (the MD.5 candidate pool per
D-110 / D-112) — the HLSL-free coverage number is what gates MD.2.

This is NOT a code-landing session. No `.metal`, no `.swift`, no
transpiler authoring. The single artifact is the grammar doc (plus
the analysis scripts it depends on, committed to a diagnostics
subdir).

Project context:
- The pack is 9,795 .milk files across 11 themes (audit §0.1 of
  `docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md`).
- 81% of presets ship embedded HLSL pixel-shader source (warp_1=,
  comp_1= line groups). Per D-110, those presets are excluded from
  MD.2 / MD.5; their HLSL portion gets a thin appendix here only.
  1,559 presets are HLSL-free.
- The `.milk` expression sub-languages are C-like — assignments,
  conditionals via `if_then_else`, arithmetic / comparison / logical
  operators, sin/cos/log/exp/etc. function calls. The vocabulary is
  Phosphene-friendly: every operator and most functions have direct
  Metal equivalents.
- Variable namespace is the main thing to enumerate: audio inputs
  (bass / mid / treb / their _att variants), time (time / frame /
  fps / progress), user vars (q1-q32), waveform / shape per-instance
  vars, per-pixel grid vars (x / y / rad / ang and out-params).
- The four expression sub-languages share syntax but differ in scope:
  per_frame, per_pixel (warp grid), wave_per_frame (custom waveforms),
  shapecode_per_frame (custom shapes). All four have `_init` variants
  that run once per preset / wave / shape.

The cream-of-the-crop pack is at: `<MATT_FILL_IN_PATH>` (clone of
https://github.com/projectM-visualizer/presets-cream-of-the-crop)

Read first (mandatory):
- docs/MILKDROP_STRATEGY.md (the full strategy + signed-off decisions)
- docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md (audit's
  paradigm-distribution + sample-preset characterizations)
- docs/DECISIONS.md D-103 through D-112 (the ten Phase MD decisions)
- docs/DECISIONS.md D-026 (deviation primitives — the audit needs to
  flag every direct-bass / direct-mid / direct-treb expression as a
  candidate for deviation-form rebinding during MD.3 emission)
- docs/DECISIONS.md D-027, D-028 (mv_warp pass + MV-3 capabilities —
  the Phosphene-side targets for grammar mapping)
- docs/MILKDROP_ARCHITECTURE.md sections 3 & 4 (the existing analysis
  of Milkdrop's variable namespace and motion model)
- PhospheneEngine/Sources/Shared/AudioFeatures.swift (FeatureVector
  field list — the Phosphene targets for `bass` / `mid` / `treb` /
  `time` / etc. rebinding)
- PhospheneEngine/Sources/Shared/StemFeatures.swift (stem-side
  field list — used in MD.6 evolved-tier rebinding spec, gets a
  forward-pointer in the doc)
- PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift (the
  Metal preamble that future transpiled presets land into — the doc
  proposes how `q1`-`q32` user variables get a new uniform buffer
  alongside FeatureVector per MD.3 spec)
- Sample 10 `.milk` files from the pack (5 HLSL-free + 5 HLSL-bearing)
  — read them end to end before drafting

---

STEP 0 — Pack accessibility + tree state check.

0.1 Confirm pack on disk and count files:
```
ls <pack-path>/presets 2>/dev/null || ls <pack-path> | head
find <pack-path> -name '*.milk' | wc -l   # expect 9795
```
If the pack isn't on disk, clone with `git clone --depth 1
https://github.com/projectM-visualizer/presets-cream-of-the-crop.git`
into /tmp.

0.2 Confirm Phosphene tree is at post-sign-off state:
```
grep -c "^## D-1[01][0-9]" docs/DECISIONS.md   # expect 10 (D-103..D-112)
grep -q "Sign-off complete 2026-05-12" docs/MILKDROP_STRATEGY.md && echo "strategy signed off"
```
If either check fails, halt and ask Matt — MD.1 is gated on the
strategy + decisions being landed.

0.3 Capture the HLSL-free vs HLSL-bearing split as your working
corpus split (per D-110):
```
PACK=<pack-path>
mkdir -p /tmp/md1-corpus
find "$PACK" -name '*.milk' > /tmp/md1-corpus/all.txt
while read f; do
  if grep -q '^warp_1=' "$f" || grep -q '^comp_1=' "$f"; then
    echo "$f" >> /tmp/md1-corpus/hlsl-bearing.txt
  else
    echo "$f" >> /tmp/md1-corpus/hlsl-free.txt
  fi
done < /tmp/md1-corpus/all.txt
wc -l /tmp/md1-corpus/*.txt   # expect 9795 / ~7900 / ~1559
```
The two split files are your input lists for the per-corpus
frequency counts in Step 2.

---

STEP 1 — Build the analysis scripts (commit them to
diagnostics subdir).

The grammar audit is empirical — frequency counts over 10k files.
The analysis is a small set of bash + awk scripts; commit them as
permanent infrastructure under `docs/diagnostics/scripts/` so MD.2
and future work can re-run the counts after grammar discoveries.

1.1 New directory: `docs/diagnostics/scripts/md1/`. Authored scripts:

- `extract_section.sh <preset.milk> <section>` — given a section
  name (e.g. `per_frame`, `per_pixel`, `wave_0_per_frame`,
  `shapecode_0_per_frame`), prints the joined body of that section
  to stdout. The `.milk` format uses indexed-line syntax —
  `per_frame_1=...`, `per_frame_2=...`, etc. Concatenate in numeric
  order.
- `enumerate_variables.sh <corpus-list>` — given a list of .milk
  paths, extracts every identifier referenced in expression sections
  and emits `<identifier> <count> <distinct-preset-count>` to stdout.
  Use the per-line identifier regex `\b[a-z_][a-z0-9_]*\b` (Milkdrop
  is case-insensitive but the dialect uses lowercase consistently).
  Filter out keywords (`if_then_else`, `above`, `below`, etc. — those
  are functions enumerated separately).
- `enumerate_functions.sh <corpus-list>` — same shape, but greps for
  `\b[a-z_][a-z0-9_]*\(` patterns (identifier immediately followed by
  open-paren — function calls).
- `enumerate_operators.sh <corpus-list>` — frequency-counts the
  arithmetic / comparison / logical operators (`+`, `-`, `*`, `/`,
  `=`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `&&`, `||`, `!`).
- `extract_q_user_vars.sh <corpus-list>` — grep `\bq[0-9]+\b` and
  emit max(q-N) per preset + global histogram; informs the q1-q32
  uniform buffer sizing in MD.3.

Each script: under 60 lines, no external deps beyond standard
shell tools (grep, awk, sort, uniq, wc, sed). The audit is
deterministic — re-running it on the same corpus produces byte-
identical output.

1.2 README in `docs/diagnostics/scripts/md1/README.md` documenting
each script's contract and a one-shot driver that runs them all
against the two corpora (HLSL-free + full pack) and writes JSON-ish
results to `docs/diagnostics/MD.1-frequency-counts-2026-XX-XX.json`
(or .txt — your call, the consumer is the strategy doc only).

---

STEP 2 — Enumerate the expression-language grammar surface.

Run the Step 1 scripts against both corpora. Capture results.
Pay attention to:

2.1 **Variables, expression sub-language scope, frequency, Phosphene
mapping.** For each variable, record:
- Name (e.g. `bass`, `q1`, `meshx`, `aspectx`, `rad`)
- Scope where it's valid: per_frame / per_pixel / wave_per_frame /
  shapecode_per_frame (some are universal; some are sub-language-
  specific; some are read-only outputs vs in-out)
- Frequency in HLSL-free corpus (preset count + total reference count)
- Frequency in full corpus (preset count + total reference count) —
  for comparison
- Proposed Phosphene-side equivalent (e.g. `bass` → `f.bass`; `bass`
  → `f.bassRel` per D-026 in the deviation-rebinding pass during
  MD.3 emission; `q1` → user-uniform-buffer slot 0; `time` →
  `fv.accumulatedAudioTime`; `aspectx` → derived from drawable
  dimensions at preset compile time)

Build a single table. Order by frequency descending. Cap the table
at ~50 most frequent variables (anything below ~1% of presets is
relegated to a "long-tail variables" sub-section with one-line
treatment).

2.2 **Functions, signature, semantic, Phosphene mapping.** For
each function used, record:
- Name (e.g. `sigmoid`, `clamp`, `above`, `below`, `if_then_else`,
  `sin`, `cos`, `atan2`)
- Arity + types (most are float-only; `if_then_else(c, t, f)` is the
  one ternary)
- Semantic (1-2 lines)
- Frequency in both corpora
- Metal equivalent or one-liner emit (e.g. `above(a, b)` → `(a > b
  ? 1.0 : 0.0)`; `sigmoid(x, k)` → custom one-liner; `if_then_else`
  → C ternary; `sin` → `sin` in MSL)

Aim for the top-20 functions with full treatment + a one-line tail
list for the rest. The MD.1 done-when said "top-20" — preserve
that target.

2.3 **Operators.** Single short subsection enumerating which
operators are observed. Milkdrop uses C-like operators with one
twist: `&&` / `||` are *not* short-circuit (both sides always
evaluate). Note this; MD.2's transpiler emits with parentheses
forcing the eager evaluation order.

2.4 **q1-q32 user variables.** Distribution of max-q-index used per
preset. Most presets use 4-8; some use all 32. Feeds the MD.3 q-uniform-
buffer sizing decision — confirm 32 slots is enough.

---

STEP 3 — HLSL appendix (deferred, per D-110).

3.1 NOT a transpiler-scope analysis. The appendix exists so that
when MD.6 / MD.7 hand-ports an HLSL-bearing source preset per the
MD.3 hand-port playbook, the author has a one-stop reference for
the HLSL surface used in the pack.

3.2 Enumerate the HLSL surface visible in `warp_1=` / `comp_1=`
blocks:
- Sampler bindings (`sampler_main`, `sampler_fw_main`, `sampler_pw_main`,
  `sampler_noise_*` — list all observed)
- Built-in textures (`texsize`, `_blur1`, `_blur2`, `_blur3`)
- Coordinate inputs (`uv`, `uv_orig`, `rad`, `ang`, the `texcoord`s)
- Output (`ret` — the float3 emitted by warp/composite per-pixel)
- HLSL functions used (`tex2D`, `tex2Dlod`, `lerp`, `saturate`,
  `length`, `normalize`, etc.)
- Audio inputs available to the HLSL shader (different from
  expression-language audio bindings — these are uniforms set by the
  host, e.g. `bass_att`, `time` get re-projected as HLSL-side floats)

3.3 For each HLSL feature, note the Phosphene-side hand-port
equivalent in a one-liner. **Do not** propose automated translation —
the rule (per D-110) is hand-port. The appendix is a cheat-sheet, not
a transpiler spec.

3.4 Cap the appendix at ~2 pages. It's a reference, not a manual.
The MD.3 hand-port playbook (a separate doc per the revised MD.3
spec) carries the actual workflow.

---

STEP 4 — Coverage report.

For both corpora, report transpiler coverage as a function of:
- (a) "If MD.2 supports the top N variables / top M functions, what
      fraction of presets transpile without fallback?"
- (b) Variables / functions in the long tail (anything below 1% of
      presets) — list them so MD.2 knows what to soft-fail on with a
      clear diagnostic, rather than discovering them at MD.5 authoring
      time.

The two numbers MD.2 most needs:
- HLSL-free corpus: fraction of the 1,559 presets that use only
  variables / functions present in the doc's primary section (not
  the long tail). Target ≥ 95%.
- Full corpus: same fraction over 9,795. Reported for context; not
  load-bearing (HLSL-bearing presets are excluded from MD.2 anyway).

If HLSL-free coverage at the top-50-variables + top-20-functions
level lands below 90%, the audit flags the gap explicitly so the
MD.2 prompt can decide whether to push the top-N higher or accept
soft-fail diagnostics on the long-tail edge cases.

---

STEP 5 — Draft `docs/MILKDROP_GRAMMAR.md`.

Section structure:

§1. What this doc is for. Cite MD.1, D-110, audit, strategy doc.
§2. Corpus split (HLSL-free vs HLSL-bearing) and why. Cite D-110.
§3. The four expression sub-languages — per_frame / per_pixel /
    wave_per_frame / shapecode_per_frame + their `_init` variants.
    Scope semantics for each.
§4. Variables — primary table (top-50). Frequency + Phosphene
    mapping per row. Long-tail subsection.
§5. Functions — primary table (top-20). Signature + Phosphene Metal
    equivalent per row. Long-tail subsection.
§6. Operators. Short. Note the &&/|| eager-evaluation quirk.
§7. q1-q32 user variables. Distribution + MD.3 uniform-buffer
    sizing recommendation.
§8. Coverage report. The two numbers MD.2 needs (Step 4).
§9. Appendix A — HLSL surface (Step 3). Hand-port reference, not
    transpiler spec.
§10. Citations.

Keep the doc readable. Tables should fit in ~10-row chunks; long
tables get scroll markers. Cite frequency counts to the analysis
scripts so future audits can re-run them.

---

STEP 6 — Manual review against 10 sample presets.

Per the revised MD.1 done-when: 5 randomly-sampled HLSL-free presets
+ 5 randomly-sampled HLSL-bearing presets. For each:

- Read the preset end to end.
- Cross-check every variable / function / operator against the doc's
  tables. Anything missing?
- For HLSL-bearing presets: cross-check HLSL appendix coverage.
- Note discrepancies in a "Manual review findings" section at the
  end of the doc.

If discrepancies surface (a variable the audit missed, a function
the audit miscounted, a long-tail item that should be primary):
fix the doc, re-run the affected script, repeat the spot-check.

---

STEP 7 — Verify.

7.1 No code changes; nothing to test-compile. Confirm:
```
grep -c "^## " docs/MILKDROP_GRAMMAR.md   # expect 10+ sections
find docs/diagnostics/scripts/md1 -name '*.sh' -type f | wc -l
                                          # expect 5 scripts + README
```

7.2 SwiftLint, build, test suites are unchanged (sanity-check):
```
swiftlint lint --strict --config .swiftlint.yml | tail
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail
swift test --package-path PhospheneEngine 2>&1 | tail
```
Pre-existing flake baseline preserved.

7.3 Markdown link sanity:
```
grep -nE '\]\([^)]+\.md\)' docs/MILKDROP_GRAMMAR.md
# spot-check each target exists
```

---

STEP 8 — Commit + closeout.

Commit 1 — the analysis infrastructure:
```
[MD.1] scripts: cream-of-crop grammar analysis (5 bash scripts + README)
```

Commit 2 — the grammar doc:
```
[MD.1] docs: MILKDROP_GRAMMAR.md — expression sub-language audit + HLSL appendix
```

Do not push without Matt's "yes, push" confirmation.

Closeout report:
1. Files created (grammar doc + 5 scripts + README + diagnostics JSON).
2. Files edited (none expected — MD.1 is purely additive).
3. Coverage numbers — the two MD.2 needs.
4. Manual review findings (Step 6).
5. Carry-forward to MD.2: variables / functions MD.2 must support
   for ≥ 95% HLSL-free coverage; long-tail soft-fail list; q-buffer
   sizing recommendation.

---

DO NOT:

- Do not start writing the MD.2 transpiler. MD.2 is its own session;
  this session produces the grammar doc the MD.2 prompt will
  consume.
- Do not author any Phosphene-side code (no `.metal`, no `.swift`,
  no JSON sidecars). The doc proposes Phosphene mappings; the
  mappings are implemented by MD.2 / MD.3 / MD.4.
- Do not commit any `.milk` files from the cream-of-crop pack. The
  pack stays at its source path; the doc cites it as a corpus, not
  as committed content. Counsel review for D-111 has not gated MD.1
  precisely because MD.1 commits no licensed content.
- Do not propose automated HLSL → MSL translation. D-110 picks
  hand-port (H.3) as the escalation path; the HLSL appendix is a
  hand-port cheat-sheet, not a transpiler spec.
- Do not over-engineer the analysis scripts. They are 5 small bash
  scripts; they don't need a Python wrapper, they don't need a unit
  test suite, they don't need to be a Swift package. Awk + grep +
  sort + uniq is the right toolset.
- Do not extend MD.1's scope to include grammar from other Milkdrop
  preset sources outside the cream-of-crop pack. The pack is the
  one corpus that matters for Phase MD per D-112.
- Do not push to remote.

---

Carry-forward (informational only — do not implement in this session):

- **MD.2 prompt expansion** is the next deliverable after MD.1
  lands. The MD.2 prompt will consume MD.1's grammar doc and the
  Step 4 coverage numbers as its input; the prompt's primary
  scope-shaping question is whether top-50 variables / top-20
  functions is enough or needs to be widened.
- **MD.3 emission spec.** MD.1 proposes Phosphene-side mappings;
  MD.3 implements them. If the grammar doc surfaces a non-obvious
  mapping (e.g. `meshx` / `meshy` need to be compile-time constants
  baked into the .metal file, not uniforms), surface it in the
  MD.1 closeout so MD.3's prompt is informed.
- **Counsel review for D-111.** MD.1 commits no licensed content;
  this is the load-bearing reason MD.1 can run in parallel with
  counsel review. If counsel review concludes the I.1 posture is
  insufficient, MD.1's findings stay valid but MD.2 onwards
  re-scopes.
- **MD.3 hand-port playbook.** The MD.3 spec gained a new doc
  deliverable (`docs/MILKDROP_HLSL_HANDPORT.md`) when D-110 split
  the manual HLSL workflow out from the transpiler. MD.1's HLSL
  appendix is the cheat-sheet; the playbook is the procedure. Both
  feed each other; expect cross-references when both land.
```

---

## Notes on running this prompt

* **Estimated session length:** 30–45 min for analysis-script
  authoring + 30–45 min for doc drafting + 15 min for manual review +
  10 min for commit/closeout. Plan for ~90 min total.
* **Counsel review for D-111 is not a blocker.** MD.1 commits zero
  licensed content (it cites the pack as a corpus, not as committed
  content). MD.2 onwards is the first increment that needs counsel
  sign-off.
* **The pack path is the one human input the prompt needs.** Fill in
  `<MATT_FILL_IN_PATH>` before pasting, or let the session clone in-
  session (the prompt covers both paths).
* **Expected output of the session:** ~2 commits, ~6 new files (1
  grammar doc, 5 scripts, optional README, optional frequency-counts
  JSON). No code changes. No engineering plan changes. No DECISIONS.md
  changes.
