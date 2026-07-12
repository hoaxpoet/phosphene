# Publishing runbook — opening the repo to preset contributors

**Decisions CONFIRMED by Matt, 2026-07-12:** (1) the history rewrite RUNS
before first publish (§2 below is no longer optional); (2) weights ship as a
Release asset, LFS keeps reference media only (§1); (3) `prompts/` ships with
its framing README (done at PUB.1); (4) preset hot-reload gets wired with
compile errors surfaced on the toast surface (queued — review Phase 2).

The PUB.1 increment (2026-07-11) made the tree publication-ready. This
runbook is the remaining, **maintainer-executed** cutover: everything here
either needs GitHub-side actions (releases, settings) or is destructive to
clones (history rewrite) and therefore runs only with Matt at the wheel.

## 0. State after PUB.1 (already done, for context)

- `LICENSE` (MIT) at root; `README.md` + `CONTRIBUTING.md` front door.
- D-111 Milkdrop attribution fulfilled: `inspired_by` blocks on all five
  Milkdrop-inspired sidecars + populated `CREDITS.md` table;
  `dragon_bloom/source.milk` removed from the tree (SHA-256 retained).
- Privacy sweep: `memory/` and the compiled `audio_tap` blob removed, the
  one personal-email occurrence redacted, `block-destructive.sh` portable,
  `*.gif` LFS rule added. **The `tools/data` corpus manifests stay in the
  repo by Matt's decision (2026-07-11)** — they are deliberate content, not
  residue.
- `Scripts/fetch_weights.sh` + `Weights/SHA256SUMS` committed (delivery
  cutover below not yet flipped).
- DOC.6 rotation run; fresh-clone test suite green (modulo the documented
  licensed-fixture and perf-suite caveats in README).

## 1. Weights cutover: LFS → Release asset (Decision 2)

Do this first — it is the big clone-cost lever (~167 MB × every clone) and
needs no history rewrite.

```bash
# 1. Build the archive from a verified checkout (from repo root):
cd PhospheneEngine/Sources/ML/Weights
shasum -a 256 -c SHA256SUMS --quiet && echo verified
tar -czf /tmp/ml-weights.tar.gz --exclude SHA256SUMS -C . .
shasum -a 256 /tmp/ml-weights.tar.gz > /tmp/ml-weights.tar.gz.sha256

# 2. Create the release and upload both files:
gh release create ml-weights-v1 /tmp/ml-weights.tar.gz /tmp/ml-weights.tar.gz.sha256 \
  --title "ML weights v1" \
  --notes "Stem-separation / beat-tracking / instrument-family weights. Fetched by Scripts/fetch_weights.sh; provenance and licenses in docs/CREDITS.md."

# 3. Verify the fetch path end-to-end BEFORE untracking anything:
mv PhospheneEngine/Sources/ML/Weights /tmp/weights-backup
mkdir PhospheneEngine/Sources/ML/Weights
cp /tmp/weights-backup/SHA256SUMS PhospheneEngine/Sources/ML/Weights/
Scripts/fetch_weights.sh          # must download + verify 482 files
# (restore from backup if anything fails)

# 4. Untrack the weights (files stay on disk), keep SHA256SUMS tracked:
git rm --cached -r PhospheneEngine/Sources/ML/Weights
git add PhospheneEngine/Sources/ML/Weights/SHA256SUMS
printf 'PhospheneEngine/Sources/ML/Weights/*\n!PhospheneEngine/Sources/ML/Weights/SHA256SUMS\n' >> .gitignore
# Remove the two Weights *.bin lines from .gitattributes (no longer LFS).

# 5. CI: in .github/workflows/ci.yml replace the LFS weights pull with
#    `Scripts/fetch_weights.sh` (cache PhospheneEngine/Sources/ML/Weights
#    keyed on SHA256SUMS to avoid re-downloading every run).
```

Commit as `[PUB.2] Infra: weights LFS→Release cutover`. Note: historical LFS
objects still exist server-side; GitHub only charges bandwidth when they are
pulled, and fresh clones no longer pull them.

## 2. History rewrite — CONFIRMED (Matt 2026-07-12): run once, before first publish

**Scope honesty (updated 2026-07-11):** when this was recommended, the main
payload was excising the corpus manifests; those now stay. What a rewrite
still buys:

| Item | Size / nature |
|---|---|
| V9 session PNGs (`7dc41106..8862d6f2`) | ~35 MiB packed, spent renders |
| `StemSeparator.mlpackage` loose in history | ~59 MB, the largest non-LFS blob |
| `docs/VISUAL_REFERENCES` GIFs as raw blobs | ~12.5 MiB (go-forward LFS rule already in) |
| `memory/`, `audio_tap` binary, `source.milk` | small; privacy/posture residue in history |
| `matt.deming@gmail.com` in 2 historical doc revs | privacy, low-harm |
| Author identities (`braesidebandit@Matthews-Mac-mini.local`, `matt@plaitandpattern.com`) | mailmap normalization |

Matt declined a size-only rewrite in June 2026 (not worth breaking clones
for ~35 MiB); with publication the calculus changed — **pre-publication is
the one moment a rewrite is free** (no external clones exist) — and Matt
confirmed on 2026-07-12: run it once before first publish. The corpus
manifests stay OUT of the excision scope (his 2026-07-11 direction).

```bash
# Fresh mirror — NEVER run filter-repo on the working clone:
git clone --mirror https://github.com/hoaxpoet/phosphene.git /tmp/phosphene-rewrite
cd /tmp/phosphene-rewrite

cat > /tmp/mailmap << 'EOF'
hoaxpoet <253968857+hoaxpoet@users.noreply.github.com> <braesidebandit@Matthews-Mac-mini.local>
hoaxpoet <253968857+hoaxpoet@users.noreply.github.com> <matt@plaitandpattern.com>
hoaxpoet <253968857+hoaxpoet@users.noreply.github.com> <matt.deming@gmail.com>
EOF

git filter-repo \
  --invert-paths \
  --path docs/diagnostics/V9_session_4_5b_phase1 \
  --path-glob 'docs/VISUAL_REFERENCES/**/*.gif' \
  --path docs/VISUAL_REFERENCES/dragon_bloom/source.milk \
  --path memory \
  --path archive/electron-prototype/assets/audio_tap \
  --path-glob '*StemSeparator.mlpackage*' \
  --mailmap /tmp/mailmap \
  --replace-text <(echo 'matt.deming@gmail.com==>[redacted]')

# Validate BEFORE pushing: clone the rewritten mirror locally, build, run
# Scripts/test_fast.sh, spot-check `git log --format='%ae' | sort -u`,
# confirm the current GIFs re-land via LFS (re-add them in a follow-up
# commit since --invert-paths removed them from the tree too — re-adding
# under the new .gitattributes rule stores them as LFS objects).

git push --force --mirror https://github.com/hoaxpoet/phosphene.git
```

**After a rewrite:** every clone and worktree is invalidated. On the Mac
mini: re-clone the primary checkout, re-run `Scripts/bootstrap_fixtures.sh`,
recreate worktrees. Parallel Claude sessions must be closed first. GitHub:
contact support or wait for GC before old objects stop being fetchable by
SHA; PR refs keep pre-rewrite objects alive — closing/locking old PRs helps.

## 3. GitHub repo settings at publish

- Branch protection on `main`: require the CI fast gate; no force pushes
  (re-enable AFTER the rewrite push if step 2 runs).
- Enable Issues; add the preset-contribution issue template if wanted.
- LFS: after step 1 the remaining LFS payload is reference media
  (~90 MB); watch the bandwidth meter the first weeks — mitigation is
  moving reference media to a release asset the same way as the weights.
- Verify the repo Social-preview/About links point at README anchors that
  exist.

## 4. Policy trigger to resolve before contributors arrive (D-113)

D-111/D-113 retired the Milkdrop author pre-release **notification
protocol** "until Phosphene opens preset development to community
contributors" — publication IS that trigger. Options: (a) reinstate
notification for future Milkdrop-inspired ports (a per-preset checklist
item in CONTRIBUTING), (b) explicitly re-retire it with a D-number
recording the rationale, or (c) narrow it (notify only when an author is
contactable via the pack metadata). **Needs Matt's pick + a DECISIONS.md
entry either way** — the trigger clause is explicit in D-113, so leaving it
unaddressed contradicts the repo's own decision log.

## 5. Post-publish watch items

- First-contributor experience: the licensed tempo fixtures and the
  Screen-Recording TCC gotcha are documented in README, but watch the first
  issues for what the docs still assume.
- Perf suites on non-Mac-mini hardware (tracked as a Phase 2 item: gate
  behind `PHOSPHENE_PERF_GATE=1`).
- LFS bandwidth meter (step 3).
