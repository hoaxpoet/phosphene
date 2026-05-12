# Session prompt — Increment MD.1 (`.milk` grammar audit, read-only authoring aid)

This file is the session prompt for running Increment MD.1. Paste the
fenced block below into a new Claude Code session. Do not include this
surrounding meta-text. The work is a doc-authoring session that
produces `docs/MILKDROP_GRAMMAR.md` — an **empirical, read-only
reference doc** that helps authors of Milkdrop-inspired Phosphene
presets read and understand source `.milk` files before drafting
their Phosphene-native uplifts.

**Reframed under the inspired-by posture (`docs/MILKDROP_STRATEGY.md`
§12, decisions D-113 through D-118, 2026-05-12).** MD.1 was originally
scoped as the empirical input that *unblocked the MD.2 transpiler
CLI*. Under the inspired-by reframe, MD.2 / MD.3 / MD.4 are retired
entirely (D-110 amendment) — no transpiler ships. MD.1 is retained
and **reframed** as a read-only author's reference. Coverage
percentages are no longer load-bearing for transpiler scope; the
HLSL-free / HLSL-bearing corpus split (load-bearing under D-110's
transpiler scope) dissolves — every preset in the 9,795-pack is a
viable inspiration source for the inspired-by uplift work stream.

Pre-session human prerequisites:

1. The `projectM-visualizer/presets-cream-of-the-crop` GitHub repo is
   cloned to a known location on disk, OR the session is permitted to
   clone in-session (the prompt allows either). Note the absolute path.
2. The strategy-doc + audit + Decisions D-103 through D-118 must be
   in tree. Verify with: `git log --oneline docs/MILKDROP_STRATEGY.md
   docs/DECISIONS.md | head`. The prompt is written against the
   post-addendum state (after the 2026-05-12 inspired-by reframe).
3. No licensed content is committed by this session (the pack is
   cited as a corpus, not as committed content). The inspired-by
   reframe does not change MD.1's "commits no licensed content"
   property.

---

```
Context: Increment MD.1 is the first runnable Phase MD work item under
the inspired-by reframe. The strategy (`docs/MILKDROP_STRATEGY.md`),
ten base Phase MD decisions (D-103 through D-112), and six addendum
decisions (D-113 through D-118 — see `docs/MILKDROP_STRATEGY.md` §12)
are signed off.

MD.1's scope is **a read-only empirical reference doc** — not the
input that unblocks a transpiler. Under the inspired-by reframe, the
transpiler (MD.2) is retired (D-110 amendment / D-118); source `.milk`
files become **reference material** that authors read end-to-end
before drafting Phosphene-native uplifts. MD.1 produces the
companion doc that helps that reading go efficiently: a catalog of
the variables, functions, operators, and audio-coupling patterns
used across the cream-of-crop pack, so an author opening a specific
source `.milk` for the first time has a one-stop reference for
"what does `q1` mean here?" / "what does `sigmoid(x, k)` do?" / etc.

This session produces `docs/MILKDROP_GRAMMAR.md` — the empirical
grammar audit reframed as an authoring aid. The doc enumerates every
variable / operator / function used in the expression sub-languages
+ the HLSL surface used in the `warp_1=` / `comp_1=` blocks, with
frequency counts. Phosphene-side equivalents are noted where the
mapping is direct and useful for authoring context (e.g. `bass` →
`f.bass` / `f.bassRel` per D-026 deviation discipline); they are
*reference*, not transpiler emission spec.

The HLSL-free / HLSL-bearing corpus split (load-bearing under the
retired transpiler scope) is **retired** — every preset in the
9,795-pack is a viable inspiration source under the inspired-by
framing. The single corpus is the full pack.

This is NOT a code-landing session. No `.metal`, no `.swift`, no
transpiler authoring (the transpiler does not exist). The single
artifact is the grammar doc (plus the analysis scripts it depends
on, committed to a diagnostics subdir for repeatability).

Project context:
- The pack is 9,795 .milk files across 11 themes (audit §0.1 of
  `docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md`).
- 81% of presets ship embedded HLSL pixel-shader source (warp_1=,
  comp_1= line groups). Under the inspired-by reframe (D-110
  amendment) HLSL-bearing presets are NO LONGER excluded —
  every preset in the pack is a viable inspiration source. The
  HLSL surface gets first-class treatment in this doc (Step 3
  below) alongside the expression sub-languages, as a reading
  reference for authors approaching an HLSL-bearing source.
- The `.milk` expression sub-languages are C-like — assignments,
  conditionals via `if_then_else`, arithmetic / comparison / logical
  operators, sin/cos/log/exp/etc. function calls. The vocabulary is
  Phosphene-friendly: every operator and most functions have direct
  Metal equivalents — useful authoring context, NOT transpiler
  emission spec.
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
- docs/MILKDROP_STRATEGY.md (the full strategy — §§1–11 are the
  derivative-posture record; §12 is the operative inspired-by record)
- docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md (audit's
  paradigm-distribution + sample-preset characterizations)
- docs/DECISIONS.md D-103 through D-118 (the ten base + six addendum
  Phase MD decisions). Particularly relevant for this session:
  D-110 amendment (transpiler retired), D-113 (posture reframe),
  D-116 (substantial-similarity discipline rule), D-118 (read-only
  analysis tool scope — this session honors the "skip" decision by
  shipping a doc, not a tool)
- docs/DECISIONS.md D-026 (deviation primitives — the audit flags
  every direct-bass / direct-mid / direct-treb expression as a
  candidate for deviation-form authoring guidance during inspired-by
  uplift authoring; not transpiler rebinding, since no transpiler)
- docs/DECISIONS.md D-027, D-028 (mv_warp pass + MV-3 capabilities —
  Phosphene-side primitives an inspired-by author maps against)
- docs/SHADER_CRAFT.md §12.6 (substantial-similarity discipline rule —
  the load-bearing authoring-time constraint that governs how an
  author uses the source `.milk` content this doc catalogs)
- docs/MILKDROP_ARCHITECTURE.md sections 3 & 4 (the existing analysis
  of Milkdrop's variable namespace and motion model)
- PhospheneEngine/Sources/Shared/AudioFeatures.swift (FeatureVector
  field list — the Phosphene targets authors map against when
  drafting an inspired-by uplift; doc cites them as reference)
- PhospheneEngine/Sources/Shared/StemFeatures.swift (stem-side
  field list — same)
- PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift (the
  Metal preamble that inspired-by Phosphene presets compile against;
  doc cites it as context, not as transpiler emission target)
- Sample 10 `.milk` files from the pack across themes / sizes / HLSL
  presence — read them end to end before drafting

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

0.2 Confirm Phosphene tree is at post-addendum state:
```
grep -c "^## D-1[01][0-9]" docs/DECISIONS.md   # expect 16 (D-103..D-118)
grep -q "Sign-off complete 2026-05-12" docs/MILKDROP_STRATEGY.md && echo "strategy signed off"
grep -q "## §12. Addendum — inspired-by reframe" docs/MILKDROP_STRATEGY.md && echo "addendum landed"
```
If any check fails, halt and ask Matt — MD.1 is gated on the
strategy + decisions + addendum being landed.

0.3 Capture the single-corpus list (HLSL split is RETIRED under the
inspired-by reframe per D-110 amendment):
```
PACK=<pack-path>
mkdir -p /tmp/md1-corpus
find "$PACK" -name '*.milk' > /tmp/md1-corpus/all.txt
wc -l /tmp/md1-corpus/all.txt   # expect 9795
```
The single list is your input for the frequency counts in Step 2.
HLSL presence becomes an *attribute* the doc tracks (so an author
opening a specific source can see "is this an HLSL-bearing
preset?" at a glance) rather than a *filter* that excludes presets
from analysis. Optional: emit a parallel `hlsl-bearing.txt` and
`hlsl-free.txt` as informational splits for the doc's frequency
breakdown tables — but neither is load-bearing for scope.

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
authoring-equivalent (reference).** For each variable, record:
- Name (e.g. `bass`, `q1`, `meshx`, `aspectx`, `rad`)
- Scope where it's valid: per_frame / per_pixel / wave_per_frame /
  shapecode_per_frame (some are universal; some are sub-language-
  specific; some are read-only outputs vs in-out)
- Frequency in full corpus (preset count + total reference count)
- Phosphene-side authoring equivalent (e.g. `bass` → drive from
  `f.bass` or, per D-026 discipline, `f.bassRel` / `f.bassDev`;
  `q1` → an author's choice of per-preset state surface (uniform
  slot, mesh-tick property, etc.) since no transpiler emission
  spec exists; `time` → `fv.accumulatedAudioTime`; `aspectx` →
  derived from drawable dimensions at the author's discretion).
  This column is **reference material for inspired-by authors**,
  not a transpiler emission contract.

Build a single table. Order by frequency descending. Cap the table
at ~50 most frequent variables (anything below ~1% of presets is
relegated to a "long-tail variables" sub-section with one-line
treatment).

2.2 **Functions, signature, semantic, Phosphene authoring-equivalent
(reference).** For each function used, record:
- Name (e.g. `sigmoid`, `clamp`, `above`, `below`, `if_then_else`,
  `sin`, `cos`, `atan2`)
- Arity + types (most are float-only; `if_then_else(c, t, f)` is the
  one ternary)
- Semantic (1-2 lines)
- Frequency in the corpus
- Metal-side equivalent for authoring reference (e.g. `above(a, b)`
  → `(a > b ? 1.0 : 0.0)`; `sigmoid(x, k)` → custom one-liner;
  `if_then_else` → C ternary; `sin` → `sin` in MSL). Reference, not
  emission spec.

Aim for the top-20 functions with full treatment + a one-line tail
list for the rest.

2.3 **Operators.** Single short subsection enumerating which
operators are observed. Milkdrop uses C-like operators with one
twist: `&&` / `||` are *not* short-circuit (both sides always
evaluate). Note this as a reading-comprehension caveat — an
inspired-by author reasoning about a source's `if_then_else(a > 0
&& b > 0, x, y)` expression should know both `a > 0` and `b > 0`
are evaluated even if the first is false in the source's logic.

2.4 **q1-q32 user variables.** Distribution of max-q-index used per
preset. Useful authoring context — an inspired-by author opening a
source preset that uses q1–q8 can read those as the source's main
per-frame state surface; one using q1–q32 has a denser per-frame
state model the author may want to honor (or deliberately simplify
under the substantial-similarity discipline rule per D-116).

---

STEP 3 — HLSL surface (first-class under inspired-by; D-110
amendment retired the HLSL exclusion).

3.1 The HLSL surface gets first-class treatment in this doc, not
appendix-only. An inspired-by author may take an HLSL-bearing
preset as inspiration (every preset in the 9,795-pack is a viable
inspiration source under D-110 amendment); the HLSL section helps
them read what the source is doing before drafting the
Phosphene-native uplift.

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

3.3 For each HLSL feature, note the Phosphene-side authoring
equivalent in a one-liner — what Phosphene primitive an inspired-by
author would reach for if honoring the source's HLSL intent (e.g.
`sampler_fw_main` → previous-frame texture in the `mv_warp` pass;
`tex2D` → MSL `tex.sample(...)`; `_blur1` → Phosphene's bloom /
post-process surface as appropriate). **Reference, not emission
spec.** The substantial-similarity discipline rule (D-116) requires
the inspired-by author to author from scratch, not transcribe.

3.4 No page cap — first-class section, sized as needed.

---

STEP 4 — Frequency and HLSL-presence summary (no coverage gate).

The doc reports:
- Per-variable / per-function frequency over the full 9,795-preset
  corpus. Top-N tables in §4 / §5; long tail in sub-sections.
- HLSL-presence summary: how many presets carry `warp_1=` /
  `comp_1=` blocks; theme breakdown for that subset. Reading aid
  for authors approaching a new theme.
- A short "expression-language footprint per theme" summary —
  which themes use which variable / function clusters most heavily.
  Helps an inspired-by author opening a theme directory for the
  first time orient quickly.

**No transpiler coverage gate.** The base prompt's "≥ 95% HLSL-free
coverage at top-50-variables + top-20-functions" target is retired —
no transpiler ships, so coverage thresholds have no consumer.
Report the numbers as descriptive statistics; do not gate the doc
on them.

---

STEP 5 — Draft `docs/MILKDROP_GRAMMAR.md`.

Section structure:

§1. What this doc is for. Cite MD.1 (reframed scope), D-110
    amendment, D-113 (inspired-by reframe), D-116 (substantial-
    similarity discipline rule), D-118 (this doc replaces the
    standalone read-only tool). Frame the doc as a read-only
    authoring aid, not transpiler input.
§2. The corpus — single full pack (9,795 presets). HLSL presence
    is an *attribute* the doc reports per preset, not a corpus
    filter. Cite D-110 amendment.
§3. The four expression sub-languages — per_frame / per_pixel /
    wave_per_frame / shapecode_per_frame + their `_init` variants.
    Scope semantics for each.
§4. Variables — primary table (top-50). Frequency + Phosphene
    authoring-equivalent per row. Long-tail subsection.
§5. Functions — primary table (top-20). Signature + Phosphene
    Metal-side equivalent per row. Long-tail subsection.
§6. Operators. Short. Note the &&/|| eager-evaluation quirk.
§7. q1-q32 user variables. Distribution + authoring-context
    notes (how dense is the source's per-frame state model?).
§8. HLSL surface (Step 3). First-class section: sampler bindings,
    built-in textures, coordinate inputs, output, HLSL functions
    used, audio inputs available to the HLSL shader. Each row
    notes the Phosphene-side authoring equivalent for an
    inspired-by author honoring the source's HLSL intent. Cite
    D-116 — the equivalent column is authoring reference, NOT
    transpiler emission spec; substantial-similarity discipline
    requires the author to author from scratch, not transcribe.
§9. Frequency + HLSL-presence summary (Step 4) — descriptive
    statistics, no coverage gates. Expression-language footprint
    per theme.
§10. How to use this doc — short section for inspired-by authors
    opening a source `.milk` for the first time. Workflow:
    (1) read the source end-to-end before drafting (per
    `CLAUDE.md` Authoring Discipline + Failed Approach #39);
    (2) use this doc to look up unfamiliar variables / functions
    / HLSL surface; (3) author the Phosphene uplift from scratch
    against Phosphene primitives, honoring the source's *concept*
    and *aesthetic*, not its code (per `SHADER_CRAFT.md §12.6`
    discipline rule).
§11. Citations.

Keep the doc readable. Tables should fit in ~10-row chunks; long
tables get scroll markers. Cite frequency counts to the analysis
scripts so future audits can re-run them.

---

STEP 6 — Manual review against 10 sample presets.

Sample 10 randomly-selected presets across themes / sizes / HLSL
presence (do NOT split deliberately 5/5 — random sample over the
full corpus reflects the inspired-by-era use case where every
preset is a viable inspiration source). For each:

- Read the preset end to end.
- Cross-check every variable / function / operator against the doc's
  tables. Anything missing?
- For HLSL-bearing presets: cross-check HLSL surface coverage (§8).
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

- Do not start writing a transpiler. MD.2 / MD.3 / MD.4 are retired
  entirely under the inspired-by reframe (D-110 amendment / D-118).
  No transpiler exists; no transpiler ships.
- Do not author any Phosphene-side code (no `.metal`, no `.swift`,
  no JSON sidecars). The doc is a read-only authoring reference;
  preset authoring happens in separate inspired-by uplift sessions
  (per the substantial-similarity discipline rule in
  `SHADER_CRAFT.md §12.6`).
- Do not commit any `.milk` files from the cream-of-crop pack. The
  pack stays at its source path; the doc cites it as a corpus, not
  as committed content. The inspired-by reframe does not change
  this — `.milk` files are reference material read by authors, not
  redistributed content (per D-116 bullet 4).
- Do not propose automated HLSL → MSL translation OR mechanical
  hand-port emission. D-110 amendment retires both translation
  modes; the HLSL section in §8 is a *reading reference* for
  inspired-by authors, not a transcription guide. The substantial-
  similarity discipline rule (D-116) governs how the author uses
  this doc's content.
- Do not over-engineer the analysis scripts. They are small bash
  scripts; they don't need a Python wrapper, they don't need a unit
  test suite, they don't need to be a Swift package. Awk + grep +
  sort + uniq is the right toolset.
- Do not extend MD.1's scope to include grammar from other Milkdrop
  preset sources outside the cream-of-crop pack. The pack is the
  one corpus that matters for Phase MD per D-112.
- Do not split the corpus into HLSL-free / HLSL-bearing as a
  filter on which presets the doc analyzes. The split is retired
  per D-110 amendment; HLSL presence becomes a per-preset
  *attribute* the doc may surface, not a *filter* that excludes
  presets from coverage.
- Do not gate the doc on transpiler-style coverage thresholds
  (e.g. "≥ 95% coverage on the HLSL-free subset"). Those targets
  came from the transpiler-input scoping under the base strategy;
  they have no consumer under the inspired-by reframe.
- Do not push to remote.

---

Carry-forward (informational only — do not implement in this session):

- **Next runnable Phase MD increment.** Under the inspired-by
  reframe MD.2 / MD.3 / MD.4 are retired (no transpiler ships).
  The next runnable session after MD.1 lands is the **first
  inspired-by uplift authoring session** — Matt picks a source
  preset from the (now-unconstrained) cream-of-crop pack; session
  follows the substantial-similarity discipline rule in
  `SHADER_CRAFT.md §12.6` (per D-116).
- **20-preset first-release bundle.** MD.1's grammar doc is one
  of the inputs the first inspired-by batch consumes. The bundle
  is the next project-level milestone (per D-114); composition
  per D-115 (Matt's pick pending).
- **Catalog-ratio framing (D-117) and read-only analysis tool
  scope (D-118).** Both already decided as part of the
  inspired-by addendum; MD.1 does not need to revisit either.
  D-117 is deferred until the catalog reaches ~40 presets;
  D-118 ("skip the standalone tool") is what makes this MD.1
  doc the operative read-only reference.
- **MD.3 hand-port playbook is retired.** Under the inspired-by
  reframe, neither transpiler emission nor mechanical hand-port
  is the work. The `MILKDROP_HLSL_HANDPORT.md` doc referenced in
  the base MD.3 spec is no longer a deliverable; the substantial-
  similarity discipline rule (`SHADER_CRAFT.md §12.6`) is the
  operative authoring constraint, not a hand-port procedure.
```

---

## Notes on running this prompt

* **Estimated session length:** 30–45 min for analysis-script
  authoring + 30–45 min for doc drafting + 15 min for manual review +
  10 min for commit/closeout. Plan for ~90 min total.
* **Counsel review for D-111 is not a blocker.** MD.1 commits zero
  licensed content (it cites the pack as a corpus, not as committed
  content). D-111 amendment retired the counsel-review gate
  entirely; counsel review remains available as optional async
  due-diligence but is not a precondition for any Phase MD work.
* **The pack path is the one human input the prompt needs.** Fill in
  `<MATT_FILL_IN_PATH>` before pasting, or let the session clone in-
  session (the prompt covers both paths).
* **Expected output of the session:** ~2 commits, ~6 new files (1
  grammar doc, 5 scripts, optional README, optional frequency-counts
  JSON). No code changes. No engineering plan changes. No DECISIONS.md
  changes.
